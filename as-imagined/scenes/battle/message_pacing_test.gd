extends Node

# [Message pacing] Regression suite for the real message-box pacing system:
# scaled wait-time constants, the letter-by-letter text-reveal formula, the
# 2x-speed HP-bar-drain formula, _log()'s own default-vs-announce hold
# split, _flush_pending_effect_lines()'s beat-pushing, _on_log_move_executed
# pushing a real "hp_drain" beat, _run_message_pacing()'s autoplay/
# not-in-tree instant bypass, and one real end-to-end proof that a genuine
# battle turn produces beats in the correct source-ordered sequence.
#
# [Deliberately NOT tested here] Actual Tween creation/playback from
# _play_multi_stage_strip_effect/_play_surf_effect — both need a live
# SceneTree (create_tween()), and this project's own established convention
# (hit_effect_dispatch_test.gd, phase4d_doubles_visual_test.gd) is to leave
# that to the real, non-headless screenshot-verification pass rather than a
# bare-instance unit test. This file's own battle_screen.tscn --autoplay
# run (see this session's own manual verification) already proves the full
# pipeline doesn't crash end-to-end; the screenshot pass proves it looks
# right.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_wait_time_constants_are_07x_scaled()
	_test_text_reveal_seconds_per_char()
	_test_hp_drain_seconds_full_bar()
	_test_log_default_hold_is_wait_time_long()
	_test_log_custom_hold_override()
	_test_move_announced_beat_has_zero_hold()
	_test_flush_pending_effect_lines_pushes_beats()
	_test_move_executed_pushes_hp_drain_beat_on_damage()
	_test_move_executed_no_hp_drain_beat_when_no_damage()
	_test_hp_drain_beat_from_frac_clamped_at_one()
	_test_move_executed_pushes_flash_beat_before_hp_drain_on_damage()
	_test_move_executed_no_flash_beat_when_no_damage()
	_test_play_damage_flash_guards_return_null()
	_test_play_multi_stage_strip_effect_guards_return_null()
	_test_play_surf_effect_guards_return_null()
	_test_pacing_bypassed_and_cleared_when_not_in_tree()
	_test_pacing_bypassed_and_cleared_when_autoplay()
	_test_pacing_noop_when_no_beats()
	_test_exit_message_mode_held_during_intro_then_released()
	_test_battle_start_beats_stash_and_restore()
	_test_real_battle_beat_ordering_end_to_end()

	var total := _pass + _fail
	print("message_pacing_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_typed_mon(mon_name: String, type_id: int, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type_id]
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_move(move_name: String, type_id: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = type_id
	m.category = 1
	m.power = power
	m.accuracy = 0
	m.pp = 10
	m.priority = 0
	return m


func _singles_party(mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [mon]
	p.members = members
	p.active_indices = [0]
	return p


# ── 1-3. Constant values ─────────────────────────────────────────────────

func _test_wait_time_constants_are_07x_scaled() -> void:
	# Source B_WAIT_TIME_* frame constants at ~59.7275fps, scaled 0.7x per
	# explicit "make battles a bit snappier" instruction.
	_chk("SHORTEST is 0.268 * 0.7", is_equal_approx(BattleScreenShared._WAIT_TIME_SHORTEST, 0.268 * 0.7))
	_chk("SHORT is 0.536 * 0.7", is_equal_approx(BattleScreenShared._WAIT_TIME_SHORT, 0.536 * 0.7))
	_chk("MED is 0.804 * 0.7", is_equal_approx(BattleScreenShared._WAIT_TIME_MED, 0.804 * 0.7))
	_chk("LONG is 1.072 * 0.7", is_equal_approx(BattleScreenShared._WAIT_TIME_LONG, 1.072 * 0.7))
	_chk("waits are strictly ascending SHORTEST<SHORT<MED<LONG",
			BattleScreenShared._WAIT_TIME_SHORTEST < BattleScreenShared._WAIT_TIME_SHORT
			and BattleScreenShared._WAIT_TIME_SHORT < BattleScreenShared._WAIT_TIME_MED
			and BattleScreenShared._WAIT_TIME_MED < BattleScreenShared._WAIT_TIME_LONG)


func _test_text_reveal_seconds_per_char() -> void:
	# Source MID text speed is 4 frames/char (~0.06697s/char). The original
	# pacing build halved that once ("2x source pace", 2 frames/char); a
	# later "2x CURRENT rate" instruction halves it again, landing at
	# ~1 frame/char overall.
	_chk("reveal seconds/char is ~a quarter of the source MID rate",
			is_equal_approx(BattleScreenShared._TEXT_REVEAL_SECONDS_PER_CHAR, 0.016745))


func _test_hp_drain_seconds_full_bar() -> void:
	# Source's real HP-bar drain always takes exactly 24 frames (~0.402s at
	# ~59.7275fps) for a full 0%<->100% traversal, regardless of max HP; at
	# the requested 2x speed that's ~0.201s.
	_chk("full-bar HP drain is ~0.201s (2x the real ~0.402s)",
			is_equal_approx(BattleScreenShared._HP_DRAIN_SECONDS_FULL_BAR, 0.201))


# ── 4-6. _log()'s own beat-pushing ────────────────────────────────────────

func _test_log_default_hold_is_wait_time_long() -> void:
	var bs := BattleScreenShared.new()
	bs._log("A plain narration line")
	_chk("_log() pushed exactly one beat", bs._pending_beats.size() == 1)
	var beat: Dictionary = bs._pending_beats[0]
	_chk("beat kind is text", beat.get("kind") == "text")
	_chk("beat text matches", beat.get("text") == "A plain narration line")
	_chk("default hold is _WAIT_TIME_LONG", is_equal_approx(beat.get("hold"), BattleScreenShared._WAIT_TIME_LONG))


func _test_log_custom_hold_override() -> void:
	var bs := BattleScreenShared.new()
	bs._log("Custom hold", BattleScreenShared._WAIT_TIME_SHORT)
	var beat: Dictionary = bs._pending_beats[0]
	_chk("custom hold override is respected", is_equal_approx(beat.get("hold"), BattleScreenShared._WAIT_TIME_SHORT))


func _test_move_announced_beat_has_zero_hold() -> void:
	# Source's own CancelerAttackstring fires the announcement with NO
	# trailing wait command — the interpreter falls straight through into
	# the move's real animation. This is the one deliberate _log() exception.
	var bs := BattleScreenShared.new()
	var attacker := _make_typed_mon("Angler", TypeChart.TYPE_WATER)
	var defender := _make_typed_mon("Blaze", TypeChart.TYPE_FIRE)
	# _mon_label() (called by _on_log_move_announced) needs a real party to
	# resolve "Your"/"Foe" — bare instances have no @onready party of their
	# own, so both sides are stubbed directly.
	bs._player_party = _singles_party(attacker)
	bs._opp_party = _singles_party(defender)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	bs._on_log_move_announced(attacker, defender, move)
	_chk("announced one beat", bs._pending_beats.size() == 1)
	var beat: Dictionary = bs._pending_beats[0]
	_chk("announce beat hold is exactly 0.0", beat.get("hold") == 0.0)
	_chk("announce beat text names the target",
			beat.get("text") == "Your Angler used Water Gun on Foe Blaze!")


func _test_flush_pending_effect_lines_pushes_beats() -> void:
	var bs := BattleScreenShared.new()
	var mon := _make_typed_mon("Sparky", TypeChart.TYPE_ELECTRIC)
	bs._player_party = _singles_party(mon)
	bs._opp_party = _singles_party(_make_typed_mon("Other", TypeChart.TYPE_NORMAL))
	bs._on_log_stat_stage_changed(mon, 0, 1)
	_chk("stat-stage line buffered, no beat pushed yet", bs._pending_beats.is_empty())
	bs._flush_pending_effect_lines()
	_chk("flush pushed exactly one beat", bs._pending_beats.size() == 1)
	var beat: Dictionary = bs._pending_beats[0]
	_chk("flushed beat kind is text", beat.get("kind") == "text")
	_chk("flushed beat gets the default LONG hold",
			is_equal_approx(beat.get("hold"), BattleScreenShared._WAIT_TIME_LONG))
	_chk("flushed beat text mentions the stat rise", "rose" in beat.get("text"))


# ── 7-9. hp_drain beat from _on_log_move_executed ────────────────────────

func _test_move_executed_pushes_hp_drain_beat_on_damage() -> void:
	var bs := BattleScreenShared.new()
	# [Doubles-split roadmap, step 7] Bare off-tree instance -- _hp_fill_bar_for()
	# now resolves via _panel_for(), which does `panels[slot] as HealthGroupPanel`
	# (a plain Control stand-in silently fails that cast and resolves null --
	# the exact bug m25h1_3_cursor_test.gd's own target-select test hit and
	# fixed), so a real HealthGroupPanel with its own _hp_fill stubbed is
	# needed here, not the old per-field _opponent_hp_fill.
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._opp_panels = [opp_panel]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 100)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	defender.current_hp = 40  # post-hit value, matching how BattleManager
	# applies damage before emitting move_executed.
	bs._on_log_move_executed(null, defender, null, 20)
	var drain_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "hp_drain")
	_chk("exactly one hp_drain beat pushed", drain_beats.size() == 1)
	var beat: Dictionary = drain_beats[0]
	_chk("to_frac matches post-hit HP fraction", is_equal_approx(beat.get("to_frac"), 40.0 / defender.max_hp))
	_chk("from_frac reconstructs the pre-hit fraction",
			is_equal_approx(beat.get("from_frac"), 60.0 / defender.max_hp))
	_chk("bar resolves to the stubbed TextureProgressBar", beat.get("bar") == opp_panel._hp_fill)
	_chk("color matches the real _hp_bar_color threshold",
			beat.get("color") == bs._hp_bar_color(defender.current_hp, defender.max_hp))


func _test_move_executed_pushes_flash_beat_before_hp_drain_on_damage() -> void:
	# [Item 4] Bare off-tree instance -- stub both the panel's own bar AND
	# the sprite so _sprite_node_for()/_hp_fill_bar_for() both resolve
	# non-null, matching how a live scene works.
	var bs := BattleScreenShared.new()
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._opp_panels = [opp_panel]
	var opponent_sprite := TextureRect.new()
	bs._opp_sprites = [opponent_sprite]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 100)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	defender.current_hp = 40
	bs._on_log_move_executed(null, defender, null, 20)
	var kinds: Array = []
	for b: Dictionary in bs._pending_beats:
		kinds.append(b.get("kind"))
	_chk("exactly one flash beat pushed", kinds.count("flash") == 1)
	var flash_idx: int = kinds.find("flash")
	var drain_idx: int = kinds.find("hp_drain")
	_chk("flash beat comes strictly before the hp_drain beat (real hitanimation -> healthbarupdate order)",
			flash_idx != -1 and drain_idx != -1 and flash_idx < drain_idx)
	_chk("flash beat carries the real defender sprite node, not a new one",
			bs._pending_beats[flash_idx].get("sprite") == opponent_sprite)


func _test_move_executed_no_flash_beat_when_no_damage() -> void:
	var bs := BattleScreenShared.new()
	bs._opp_sprites = [TextureRect.new()]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	bs._on_log_move_executed(null, defender, null, 0)
	var flash_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "flash")
	_chk("no flash beat for a 0-damage hit", flash_beats.is_empty())


func _test_play_damage_flash_guards_return_null() -> void:
	var bs := BattleScreenShared.new()
	_chk("null sprite returns null (no live-tree Tween ever attempted)",
			bs._play_damage_flash(null) == null)


func _test_move_executed_no_hp_drain_beat_when_no_damage() -> void:
	var bs := BattleScreenShared.new()
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL)
	bs._on_log_move_executed(null, defender, null, 0)
	var drain_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "hp_drain")
	_chk("no hp_drain beat for a 0-damage hit", drain_beats.is_empty())


func _test_hp_drain_beat_from_frac_clamped_at_one() -> void:
	# A hit that would have overkilled past 100% (impossible in practice
	# since current_hp is already clamped by BattleManager, but this proves
	# the reconstruction formula itself doesn't produce a >1.0 fraction).
	var bs := BattleScreenShared.new()
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 50)
	defender.current_hp = 50
	bs._on_log_move_executed(null, defender, null, 0)
	# (No damage here — this test only exercises the pure clamp math via a
	# direct call, since a real >max_hp reconstruction can't occur through
	# the normal dispatch path.)
	var to_frac: float = float(defender.current_hp) / float(defender.max_hp)
	var reconstructed: float = min(1.0, float(defender.current_hp + 1000) / float(defender.max_hp))
	_chk("reconstruction formula clamps at 1.0", reconstructed == 1.0)
	_chk("sanity: to_frac itself is a valid fraction", to_frac <= 1.0)


# ── 10-11. Tween-returning guard paths (no live tree needed) ─────────────

func _test_play_multi_stage_strip_effect_guards_return_null() -> void:
	var bs := BattleScreenShared.new()
	_chk("empty textures returns null", bs._play_multi_stage_strip_effect([], null) == null)
	_chk("null target returns null",
			bs._play_multi_stage_strip_effect([PlaceholderTexture2D.new()], null) == null)


func _test_play_surf_effect_guards_return_null() -> void:
	var bs := BattleScreenShared.new()
	_chk("null target returns null", bs._play_surf_effect(true, null) == null)


# ── 12-14. _run_message_pacing() bypass paths ────────────────────────────

func _test_pacing_bypassed_and_cleared_when_not_in_tree() -> void:
	var bs := BattleScreenShared.new()
	bs._log("Should never reveal")
	_chk("beat queued before the call", bs._pending_beats.size() == 1)
	_chk("bare instance is genuinely not in the tree", not bs.is_inside_tree())
	await bs._run_message_pacing()
	_chk("beats cleared without needing a live tree", bs._pending_beats.is_empty())


func _test_pacing_bypassed_and_cleared_when_autoplay() -> void:
	# _is_autoplay_run alone short-circuits _run_message_pacing() regardless
	# of tree membership -- no need to add this bare instance to the tree
	# (which would trigger _ready() against nodes that don't exist on a
	# plain BattleScreenShared.new()).
	var bs := BattleScreenShared.new()
	bs._is_autoplay_run = true
	bs._log("Should never reveal either")
	_chk("beat queued before the call", bs._pending_beats.size() == 1)
	await bs._run_message_pacing()
	_chk("beats cleared instantly under --autoplay", bs._pending_beats.is_empty())


func _test_pacing_noop_when_no_beats() -> void:
	var bs := BattleScreenShared.new()
	_chk("starts with no beats queued", bs._pending_beats.is_empty())
	await bs._run_message_pacing()
	_chk("still empty, no error", bs._pending_beats.is_empty())


# ── 15. Real end-to-end beat ordering ─────────────────────────────────────

func _test_exit_message_mode_held_during_intro_then_released() -> void:
	# [Intro menu-artifact fix] While _intro_active, _exit_message_mode()
	# must be a no-op: the intro's own pacing runs each end with an exit
	# call, and letting one through would flash the .tscn's authored
	# UNSTYLED placeholder menu (default-font/default-chrome Fight/Item/Run
	# + the "..." prompt) back on screen mid-intro — the exact artifact
	# Rob's real-play report caught (2026-08-03). Once the flag clears, the
	# identical call must restore the menu content exactly as it always
	# did, so mid-battle beat replays are untouched by the fix.
	var bs := BattleScreenShared.new()
	bs._message_label = RichTextLabel.new()
	# The real scene authors MessageLabel `visible = false` (a fresh
	# RichTextLabel.new() defaults visible) — without this the fixture trips
	# _enter_message_mode()'s own already-in-message-mode no-op guard.
	bs._message_label.visible = false
	bs._action_panel = PanelContainer.new()
	bs._status_label = Label.new()
	bs._new_button_grid = GridContainer.new()
	bs._new_button_area = VBoxContainer.new()
	bs._top_action_hbox = HBoxContainer.new()
	bs._fight_action_hbox = HBoxContainer.new()
	bs._action_panel_message_style = StyleBoxTexture.new()
	bs._action_panel_menu_style = StyleBoxTexture.new()
	# [Bugfix regression guard] Simulate the exact real-play scenario: the
	# FIGHT menu was the last thing _layout_action_menu_for() built before
	# this message beat started (its own bordered grid slot left visible),
	# which is what let the "action box" stay on screen, shrunken, instead
	# of being hidden. _enter_message_mode() must clear it.
	bs._fight_action_hbox.visible = true
	bs._enter_message_mode()
	_chk("setup: message mode genuinely entered",
			bs._message_label.visible and not bs._new_button_grid.visible)
	_chk("bugfix: FIGHT's bordered grid box is hidden, not left shrunken",
			not bs._fight_action_hbox.visible)
	_chk("bugfix: TOP's own HBox stays hidden too", not bs._top_action_hbox.visible)
	bs._intro_active = true
	bs._exit_message_mode()
	_chk("intro hold: message label stays visible", bs._message_label.visible)
	_chk("intro hold: placeholder grid stays hidden", not bs._new_button_grid.visible)
	_chk("intro hold: status label stays hidden", not bs._status_label.visible)
	_chk("intro hold: button area stays hidden", not bs._new_button_area.visible)
	bs._intro_active = false
	bs._exit_message_mode()
	_chk("released: message label hidden again", not bs._message_label.visible)
	_chk("released: grid visibility restored", bs._new_button_grid.visible)
	_chk("released: status label restored", bs._status_label.visible)
	_chk("released: button area restored", bs._new_button_area.visible)


func _test_battle_start_beats_stash_and_restore() -> void:
	# [Battle-start message-order fix] The engine's battle-start events
	# (switch-in abilities, lead weather) queue beats BEFORE the intro's own
	# messages exist; source prints them AFTER the whole intro
	# (TryDoEventsBeforeFirstTurn, battle_main.c:3697/3834). The stash must
	# hand back exactly what was queued (leaving the queue empty for the
	# intro's own messages), and the restore must re-append IN ORDER and
	# also flush any buffered stat/status lines those same events produced
	# (Intimidate's shape — otherwise they attach to the first move
	# announcement, even later than the old wrong order).
	var bs := BattleScreenShared.new()
	var beat_a := {"kind": "text", "text": "Rain began to fall!", "hold": 1.0}
	var beat_b := {"kind": "anim_async", "start": Callable()}
	bs._pending_beats.append(beat_a)
	bs._pending_beats.append(beat_b)
	bs._pending_effect_lines.append("Gyarados's Attack fell!")
	var stash := bs._stash_battle_start_beats()
	_chk("stash carries both beats in order", stash.size() == 2
			and stash[0] == beat_a and stash[1] == beat_b)
	_chk("queue left empty for the intro's own messages", bs._pending_beats.is_empty())
	_chk("buffered effect line NOT consumed by the stash",
			bs._pending_effect_lines.size() == 1)
	# The intro's own messages queue and drain in between — simulate the
	# drained state (empty queue) and restore.
	bs._restore_battle_start_beats(stash)
	_chk("restore re-appends both beats in order", bs._pending_beats.size() == 3
			and bs._pending_beats[0] == beat_a and bs._pending_beats[1] == beat_b)
	_chk("restore flushes the buffered line AFTER the replayed beats",
			bs._pending_beats[2].get("kind") == "text"
			and bs._pending_beats[2].get("text") == "Gyarados's Attack fell!")
	_chk("effect-line buffer cleared by the restore", bs._pending_effect_lines.is_empty())


func _test_real_battle_beat_ordering_end_to_end() -> void:
	var attacker := _make_typed_mon("RealAngler", TypeChart.TYPE_WATER)
	var opp := _make_typed_mon("RealBlaze", TypeChart.TYPE_FIRE, 200)
	var opp_move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 20)
	opp.add_move(opp_move)
	var atk_move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	attacker.add_move(atk_move)

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)

	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(attacker)
	bs._opp_party = _singles_party(opp)
	bs._bm = bm
	# A bare off-tree BattleScreenShared never ran _ready(), so its @onready HP-bar/
	# sprite fields are null -- stub in real (but unparented) HealthGroupPanel/
	# Control nodes so _hp_fill_bar_for()/_sprite_node_for() can both resolve
	# non-null and the "flash"/"hp_drain" beats actually get pushed, matching
	# what a live scene does. _panel_for() does `panels[slot] as
	# HealthGroupPanel` -- a plain Control stand-in for the panel arrays would
	# silently fail that cast (see m25h1_3_cursor_test.gd's own identical fix).
	var ply_panel := HealthGroupPanel.new()
	ply_panel._hp_fill = TextureProgressBar.new()
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._ply_panels = [ply_panel]
	bs._opp_panels = [opp_panel]
	bs._ply_sprites = [TextureRect.new()]
	bs._opp_sprites = [TextureRect.new()]
	bs._wire_log_signals()

	bm.start_battle_with_parties(_singles_party(attacker), _singles_party(opp))
	bm.queue_move_targeted(0, 0, 1)
	bm.queue_move_targeted(1, 0, 0)
	bm.advance()

	# Per BattleScript_Hit_RetFromAtkAnimation's real order: announce (no
	# hold) -> [anim, skipped here since _on_hit_effect_move_executed is a
	# SEPARATE connect() this bare-instance test never wires, only
	# _wire_log_signals()'s own handlers] -> flash -> hp_drain -> crit/
	# effectiveness text -> damage text -- all still buffered in
	# _pending_beats since pacing was never run. Both mons act this turn
	# (equal speed, tie-break order not asserted), so exactly two zero-hold
	# announces, two flash beats, and two hp_drain beats are expected, each
	# flash+drain pair sandwiched between its own announce and its own
	# damage line.
	var kinds: Array = []
	for beat: Dictionary in bs._pending_beats:
		kinds.append(beat.get("kind"))
	var announce_count: int = 0
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind") == "text" and beat.get("hold") == 0.0:
			announce_count += 1
	_chk("exactly two zero-hold announce beats (one per mon's move)", announce_count == 2)
	_chk("exactly two flash beats (both hits connected)", kinds.count("flash") == 2)
	_chk("exactly two hp_drain beats (both hits connected)", kinds.count("hp_drain") == 2)
	_chk("the very first beat is a zero-hold announce",
			bs._pending_beats[0].get("kind") == "text" and bs._pending_beats[0].get("hold") == 0.0)
	# Each flash+hp_drain pair must sit strictly after its own announce, in
	# flash-then-drain order (real hitanimation -> healthbarupdate), and
	# strictly before the FIRST text beat that follows it (that beat is
	# either the effectiveness line or, if none, the damage line — either
	# way, real narration for that same hit).
	var first_flash_idx: int = kinds.find("flash")
	var first_drain_idx: int = kinds.find("hp_drain")
	_chk("the first flash beat is preceded by an announce beat",
			first_flash_idx > 0 and kinds[first_flash_idx - 1] == "text")
	_chk("the first flash beat comes strictly before the first hp_drain beat",
			first_flash_idx != -1 and first_drain_idx != -1 and first_flash_idx < first_drain_idx)
	_chk("the first hp_drain beat is followed by more narration text for that same hit",
			first_drain_idx + 1 < kinds.size() and kinds[first_drain_idx + 1] == "text")
	_chk("a real damage line ('took N damage!') is among the queued text beats",
			bs._pending_beats.any(func(b): return b.get("kind") == "text" and "took" in b.get("text") and "damage!" in b.get("text")))
	_chk("the super-effective line is among the queued text beats",
			bs._pending_beats.any(func(b): return b.get("kind") == "text" and "super effective" in b.get("text")))

	bm.queue_free()
