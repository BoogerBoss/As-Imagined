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
	_test_exp_drain_seconds_full_bar()
	_test_log_default_hold_is_wait_time_long()
	_test_log_custom_hold_override()
	_test_move_announced_beat_has_zero_hold()
	_test_mon_label_uses_nickname_when_set()
	_test_flush_pending_effect_lines_pushes_beats()
	_test_move_executed_pushes_hp_drain_beat_on_damage()
	_test_move_executed_no_hp_drain_beat_when_no_damage()
	_test_hp_drain_beat_from_frac_clamped_at_one()
	_test_exp_gained_pushes_exp_drain_beat_with_real_from_to_fractions()
	_test_exp_gained_to_frac_clamps_at_one_across_a_level_up()
	_test_exp_gained_no_exp_drain_beat_without_a_real_exp_fill_bar()
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
	# [M27R 7a-3b] The battle SFX wiring. Every one of these asserts the
	# QUEUE, never playback -- _run_message_pacing() returns early for
	# --autoplay and for off-tree instances, which is exactly the condition
	# a headless suite runs in, so asserting a sound PLAYED would be
	# asserting through a path that is deliberately switched off here.
	_test_queue_sfx_appends_a_beat()
	_test_queue_sfx_ignores_an_empty_name()
	_test_damage_sfx_queued_before_the_hp_drain_beat()
	_test_damage_sfx_variant_follows_effectiveness()
	_test_no_damage_sfx_when_the_hit_did_nothing()
	_test_faint_queues_recall_sfx_before_the_recall_beat()
	_test_switch_out_queues_recall_sfx()
	_test_switch_in_queues_send_out_sfx_before_the_reveal()
	# [KO-ordering / battle-end wording, live-reported]
	await _test_reentrant_pacing_waits_for_the_drain_in_flight()
	_test_battle_end_line_is_source_shaped_per_battle_kind()
	# ⚠️ CALL REMOVED, AND ITS FUNCTION BODY IS GONE — I DELETED IT, 2026-08-11.
	# `_test_only_authored_dialogue_is_press_gated()` was added to this file by
	# Rob while I was editing the same file; I then rewrote the tail of the file
	# with a truncating write (`s[:index_of_target] + new`) that assumed the
	# function I was replacing was still the last one in the file. It was not —
	# his definition sat after it — so the body was destroyed. The CALL survived
	# because it is up here, which is the only reason the loss was visible at
	# all: the suite stopped parsing and hung instead of failing.
	#
	# Not reconstructed, deliberately. Only the NAME survives, and writing a
	# body to match a name would put an assertion under Rob's intent that he
	# never wrote. Restore the real one and put this call back.
	#
	# The lesson for me, not for the file: never rewrite a whole file by offset
	# when another party may be editing it. Anchored replaces only.

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


# [EXP bar animation fix] Unlike _make_typed_mon above (a bare
# PokemonSpecies.new() with no national_dex_num, which _exp_fraction_at's
# own disclosed fallback correctly resolves to an always-0.0 fraction), the
# exp_drain beat tests need REAL growth-rate data to exercise a genuine
# nonzero from/to pair -- same real-registry-species shape m20_exp_test.gd's
# own _species_from_registry() already established for the same reason.
func _make_registry_mon(dex: int, level: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.national_dex_num = dex
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 45
	sp.base_attack = 49
	sp.base_defense = 49
	sp.base_sp_attack = 65
	sp.base_sp_defense = 65
	sp.base_speed = 45
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


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
	# ~59.7275fps) for a full 0%<->100% traversal, regardless of max HP.
	# Rob slowed this by ~33% once the KO-ordering fix made it visible on a
	# finishing blow, landing at 2/3 of source's own figure (~1.5x pace).
	# Asserted as that RATIO, not as a bare literal, so the assertion still
	# says what the number means after the next adjustment.
	_chk("full-bar HP drain is 2/3 of the real ~0.402s (~1.5x pace)",
			is_equal_approx(BattleScreenShared._HP_DRAIN_SECONDS_FULL_BAR, 0.402 * 2.0 / 3.0))
	# ⚠️ The EXP bar is a SEPARATE constant and was deliberately NOT slowed
	# with it — the two happened to share a value, they do not share a rule.
	# Pinned so a later session cannot "restore consistency" by accident.
	_chk("the EXP bar keeps its own, faster duration",
			BattleScreenShared._EXP_DRAIN_SECONDS_FULL_BAR
			< BattleScreenShared._HP_DRAIN_SECONDS_FULL_BAR)


func _test_exp_drain_seconds_full_bar() -> void:
	# [EXP bar animation fix] Reuses the HP bar's own proportional-duration
	# SHAPE (disclosed simplification of source's real per-amount
	# GetScaledExpFraction speed curve -- see the constant's own doc
	# comment).
	#
	# ⚠️ THE LABEL USED TO SAY "matches the established HP-drain duration" AND
	# THAT IS NO LONGER TRUE. The two constants shared 0.201 when this was
	# written, so the assertion read as though it were checking the pair stayed
	# in step -- it never was; it pinned the literal. Rob slowed the HP bar to
	# 0.268 and deliberately left this one alone, and a label claiming a match
	# that the code does not check is exactly the stale-comment shape this
	# project keeps having to correct. It pins the EXP bar's own value, and
	# says so.
	_chk("full-bar EXP drain keeps its own ~0.201s (2x the real ~0.402s)",
			is_equal_approx(BattleScreenShared._EXP_DRAIN_SECONDS_FULL_BAR, 0.201))


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


# [post-K-c pass] `_mon_label`/`_name_text` swapped from `species.species_name`
# to `display_name()` — this pins that the swap actually reaches the battle
# log, not just the field party screen K-c itself covered.
func _test_mon_label_uses_nickname_when_set() -> void:
	var bs := BattleScreenShared.new()
	var attacker := _make_typed_mon("Angler", TypeChart.TYPE_WATER)
	attacker.nickname = "REEL"
	var defender := _make_typed_mon("Blaze", TypeChart.TYPE_FIRE)
	bs._player_party = _singles_party(attacker)
	bs._opp_party = _singles_party(defender)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	bs._on_log_move_announced(attacker, defender, move)
	var beat: Dictionary = bs._pending_beats[0]
	_chk("nicknamed attacker announces by nickname, not species name",
			beat.get("text") == "Your REEL used Water Gun on Foe Blaze!")


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


# ── EXP bar animation fix: exp_drain beat from _on_log_exp_gained ────────
# This is the fix for the reported bug (experience "isn't being visibly
# shown") -- the EXP bar previously only ever snapped via _refresh_ui()'s
# plain refresh() call, with no tween of its own, unlike the HP bar's
# established "hp_drain" beat immediately above.

func _test_exp_gained_pushes_exp_drain_beat_with_real_from_to_fractions() -> void:
	var bs := BattleScreenShared.new()
	var ply_panel := HealthGroupPanel.new()
	ply_panel._exp_fill = TextureProgressBar.new()
	bs._ply_panels = [ply_panel]
	var recipient := _make_registry_mon(1, 10)  # Bulbasaur, real growth data
	bs._player_party = _singles_party(recipient)
	bs._opp_party = _singles_party(_make_typed_mon("Foe", TypeChart.TYPE_NORMAL))

	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_this_level: int = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	var exp_next_level: int = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	var needed: int = exp_next_level - exp_this_level
	var amount: int = int(needed / 4.0)  # a partial gain, well short of leveling
	recipient.current_exp = exp_this_level + amount

	bs._on_log_exp_gained(recipient, amount)
	var drain_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "exp_drain")
	_chk("exactly one exp_drain beat pushed", drain_beats.size() == 1)
	var beat: Dictionary = drain_beats[0]
	_chk("to_frac matches post-gain progress at this level",
			is_equal_approx(beat.get("to_frac"), float(amount) / float(needed)))
	_chk("from_frac reconstructs the pre-gain progress (zero here, since exp started exactly at the level floor)",
			is_equal_approx(beat.get("from_frac"), 0.0))
	_chk("bar resolves to the stubbed player ExpFill node", beat.get("bar") == ply_panel._exp_fill)

	var text_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "text")
	_chk("the gained-EXP text beat still queues alongside the animation",
			text_beats.size() == 1 and text_beats[0].get("text").contains("gained %d Exp" % amount))


func _test_exp_gained_to_frac_clamps_at_one_across_a_level_up() -> void:
	# A single award that crosses (or overshoots) the next level's threshold
	# -- the bar animates to full rather than overshooting past 1.0; the
	# level_up signal's own follow-up _refresh_ui() is what snaps it to the
	# correct in-progress fraction for the new level (see _on_log_exp_gained's
	# own doc comment).
	var bs := BattleScreenShared.new()
	var ply_panel := HealthGroupPanel.new()
	ply_panel._exp_fill = TextureProgressBar.new()
	bs._ply_panels = [ply_panel]
	var recipient := _make_registry_mon(1, 10)
	bs._player_party = _singles_party(recipient)
	bs._opp_party = _singles_party(_make_typed_mon("Foe", TypeChart.TYPE_NORMAL))

	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_this_level: int = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	var exp_next_level: int = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	var needed: int = exp_next_level - exp_this_level
	var big_amount: int = needed + 500  # comfortably crosses the level boundary
	recipient.current_exp = exp_this_level + big_amount

	bs._on_log_exp_gained(recipient, big_amount)
	var beat: Dictionary = bs._pending_beats.filter(func(b): return b.get("kind") == "exp_drain")[0]
	_chk("to_frac clamps at 1.0 when the award crosses a level boundary",
			is_equal_approx(beat.get("to_frac"), 1.0))


func _test_exp_gained_no_exp_drain_beat_without_a_real_exp_fill_bar() -> void:
	# Mirrors _test_move_executed_no_hp_drain_beat_when_no_damage's own
	# graceful-degrade shape: no panel stubbed at all, so _panel_for()
	# bounds-checks and resolves null -- the text confirmation still queues
	# even when there's nowhere to animate a bar.
	var bs := BattleScreenShared.new()
	var recipient := _make_registry_mon(1, 10)
	bs._player_party = _singles_party(recipient)
	bs._opp_party = _singles_party(_make_typed_mon("Foe", TypeChart.TYPE_NORMAL))
	recipient.current_exp += 10

	bs._on_log_exp_gained(recipient, 10)
	var drain_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "exp_drain")
	_chk("no exp_drain beat when no ExpFill bar is reachable", drain_beats.is_empty())
	var text_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "text")
	_chk("the gained-EXP text beat still queues regardless", text_beats.size() == 1)


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


# ---------------------------------------------------------------------------
# [M27R 7a-3b] Battle SFX
# ---------------------------------------------------------------------------


func _test_queue_sfx_appends_a_beat() -> void:
	var bs := BattleScreenShared.new()
	bs._queue_sfx("SE_RECALL")
	_chk("_queue_sfx pushes exactly one beat", bs._pending_beats.size() == 1)
	_chk("the beat is of kind 'sfx'", bs._pending_beats[0].get("kind") == "sfx")
	_chk("the beat carries the sound name", bs._pending_beats[0].get("se") == "SE_RECALL")


func _test_queue_sfx_ignores_an_empty_name() -> void:
	# ⚠️ AudioMap.damage_se() returns "" for an immune hit -- which did no
	# damage and so makes no damage sound. An empty name must queue NOTHING
	# rather than a beat the pacing loop then hands to the player.
	var bs := BattleScreenShared.new()
	bs._queue_sfx("")
	_chk("an empty sound name queues no beat at all", bs._pending_beats.is_empty())


func _test_damage_sfx_queued_before_the_hp_drain_beat() -> void:
	# ⚠️ ORDER IS THE POINT: the hit must be heard as the bar STARTS moving,
	# not after it settles, so the sfx beat sits strictly before hp_drain.
	var bs := BattleScreenShared.new()
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._opp_panels = [opp_panel]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 100)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	defender.current_hp = 40
	bs._pending_hit_effectiveness = 1.0
	bs._on_log_move_executed(null, defender, null, 20)
	var kinds: Array = []
	for beat: Dictionary in bs._pending_beats:
		kinds.append(beat.get("kind"))
	var sfx_idx: int = kinds.find("sfx")
	var drain_idx: int = kinds.find("hp_drain")
	_chk("a damage sfx beat was queued", sfx_idx != -1)
	_chk("an hp_drain beat was queued", drain_idx != -1)
	_chk("the sfx beat comes strictly BEFORE the hp_drain beat",
			sfx_idx != -1 and drain_idx != -1 and sfx_idx < drain_idx)


func _test_damage_sfx_variant_follows_effectiveness() -> void:
	# ⚠️ THE DISCRIMINATOR. A super-effective hit that sounds resisted is the
	# most audible mistake a battle can make, and a hook that queued one
	# fixed sound would pass every assertion above. Two runs, one variable.
	var supereff := _damage_se_for(2.0)
	var weak := _damage_se_for(0.5)
	var normal := _damage_se_for(1.0)
	_chk("a super-effective hit queues the super-effective sound",
			supereff == AudioMap.damage_se(2.0))
	_chk("a resisted hit queues the weak sound", weak == AudioMap.damage_se(0.5))
	_chk("super-effective and resisted queue DIFFERENT sounds", supereff != weak)
	_chk("a neutral hit queues neither of them", normal != supereff and normal != weak)


func _test_no_damage_sfx_when_the_hit_did_nothing() -> void:
	# ⚠️ EFFECTIVENESS IS DELIBERATELY NEUTRAL, NOT ZERO. An immune hit is
	# refused twice over — `damage_se()` returns "" AND the drain block is
	# skipped for zero damage — and a fixture where two competing rules agree
	# cannot tell them apart. A neutral effectiveness names a REAL sound, so
	# only the no-damage gate can suppress it here.
	var bs := BattleScreenShared.new()
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._opp_panels = [opp_panel]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 100)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	bs._pending_hit_effectiveness = 1.0
	bs._on_log_move_executed(null, defender, null, 0)
	var sfx_beats: Array = bs._pending_beats.filter(func(b): return b.get("kind") == "sfx")
	_chk("no damage sfx beat on a hit that dealt no damage", sfx_beats.is_empty())
	# The other half of the pair, asserted where it IS the deciding rule: an
	# immune hit has no damage sound to queue in the first place.
	_chk("an immune hit names no damage sound at all", AudioMap.damage_se(0.0) == "")


## Runs the real damage hook at one effectiveness and reports the sound name
## its queued sfx beat carries ("" if none was queued).
func _damage_se_for(effectiveness: float) -> String:
	var bs := BattleScreenShared.new()
	var opp_panel := HealthGroupPanel.new()
	opp_panel._hp_fill = TextureProgressBar.new()
	bs._opp_panels = [opp_panel]
	var defender := _make_typed_mon("Target", TypeChart.TYPE_NORMAL, 100)
	bs._opp_party = _singles_party(defender)
	bs._player_party = _singles_party(_make_typed_mon("SomeoneElse", TypeChart.TYPE_NORMAL))
	defender.current_hp = 40
	bs._pending_hit_effectiveness = effectiveness
	bs._on_log_move_executed(null, defender, null, 20)
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind") == "sfx":
			return str(beat.get("se", ""))
	return ""


func _test_faint_queues_recall_sfx_before_the_recall_beat() -> void:
	var bs := _wired_screen()
	var mon: BattlePokemon = bs._player_party.members[0]
	bs._bm.pokemon_fainted.emit(mon)
	var kinds := _kinds_of(bs)
	var sfx_idx: int = kinds.find("sfx")
	var recall_idx: int = kinds.find("recall")
	_chk("fainting queues a recall sfx beat", sfx_idx != -1)
	_chk("fainting queues the recall animation beat", recall_idx != -1)
	_chk("the faint recall sound is SE_RECALL", _first_se(bs) == "SE_RECALL")
	_chk("the sound is queued before the recall animation",
			sfx_idx != -1 and recall_idx != -1 and sfx_idx < recall_idx)
	bs._bm.queue_free()


func _test_switch_out_queues_recall_sfx() -> void:
	# The source-accurate case: ReturnMonToBall fires for a LIVING switch-out,
	# which until M27R played nothing at all.
	var bs := _wired_screen()
	var mon: BattlePokemon = bs._player_party.members[0]
	bs._bm.pokemon_switched_out.emit(mon, 0)
	_chk("a living switch-out queues a recall sound", _first_se(bs) == "SE_RECALL")
	_chk("it also queues the recall animation beat", _kinds_of(bs).has("recall"))
	bs._bm.queue_free()


func _test_switch_in_queues_send_out_sfx_before_the_reveal() -> void:
	var bs := _wired_screen()
	var mon: BattlePokemon = bs._player_party.members[0]
	bs._bm.pokemon_switched_in.emit(mon, 0, 0)
	var kinds := _kinds_of(bs)
	var sfx_idx: int = kinds.find("sfx")
	var reveal_idx: int = kinds.find("switch_reveal")
	_chk("a switch-in queues a send-out sound", _first_se(bs) == "SE_SEND_OUT")
	_chk("a switch-in queues the sprite-reveal beat", reveal_idx != -1)
	_chk("the sound is queued before the reveal",
			sfx_idx != -1 and reveal_idx != -1 and sfx_idx < reveal_idx)
	bs._bm.queue_free()


## A bare screen with real parties and _wire_log_signals() run against a real
## BattleManager, so the faint/switch handlers under test are the REAL ones
## rather than hand-called functions.
func _wired_screen() -> BattleScreenShared:
	var mine := _make_typed_mon("Mine", TypeChart.TYPE_NORMAL)
	var theirs := _make_typed_mon("Theirs", TypeChart.TYPE_NORMAL)
	var bm := BattleManager.new()
	var bs := BattleScreenShared.new()
	bs._player_party = _singles_party(mine)
	bs._opp_party = _singles_party(theirs)
	bs._bm = bm
	bs._wire_log_signals()
	bs._pending_beats.clear()
	return bs


func _kinds_of(bs: BattleScreenShared) -> Array:
	var kinds: Array = []
	for beat: Dictionary in bs._pending_beats:
		kinds.append(beat.get("kind"))
	return kinds


func _first_se(bs: BattleScreenShared) -> String:
	for beat: Dictionary in bs._pending_beats:
		if beat.get("kind") == "sfx":
			return str(beat.get("se", ""))
	return ""



# ── [Live-reported] KO ordering and the battle-end line ──────────────────

func _test_reentrant_pacing_waits_for_the_drain_in_flight() -> void:
	# ⚠️ THE BUG THIS PINS IS AN ORDERING RACE, NOT A BEAT ORDER. Reported as
	# "opponent HP drains fully BEFORE the attack animation that would KO".
	# The beats were always queued in the right order; what went wrong is that
	# `_on_battle_ended` drains them itself, so `_dispatch_move`'s own trailing
	# `await _run_message_pacing()` hit the re-entrancy guard, returned
	# INSTANTLY, and let the very next line -- `_refresh_ui()` -- snap every HP
	# bar to its post-hit value before the drain had played a single beat.
	#
	# So the assertion is about the AWAIT, not the queue: a re-entrant call
	# must not return until `_pacing_finished` fires.
	var bs := BattleScreenShared.new()
	bs._pacing_active = true
	var returned := [false]
	var call_it := func() -> void:
		await bs._run_message_pacing()
		returned[0] = true
	call_it.call()
	await get_tree().process_frame
	await get_tree().process_frame
	_chk("a re-entrant pacing call does NOT return while a drain is in flight",
			returned[0] == false)
	bs._pacing_finished.emit()
	await get_tree().process_frame
	_chk("...and returns once the drain in flight reports finished",
			returned[0] == true)
	bs.free()


func _test_battle_end_line_is_source_shaped_per_battle_kind() -> void:
	# ⚠️ SOURCE PRINTS NOTHING WHEN YOU BEAT A WILD POKEMON. The non-trainer
	# arm of HandleEndTurn_BattleWon is a bare jump to
	# BattleScript_PayDayMoneyAndPickUpItems with no victory string on it, and
	# the trainer arm's own line ("You defeated {trainer}!") is queued
	# elsewhere by _show_trainer_battle_end. Reported from play as "it says You
	# win at the end of a wild battle which is not matching source".
	var won := BattleScreenShared.new()
	won.overlay_mode = true
	won._log_battle_end_result(0)
	_chk("an overworld WIN prints no closing line at all",
			won._pending_beats.is_empty())
	won.free()

	# The loss arm is three lines, and the middle one branches wild-vs-trainer.
	# A deterministic payout: 2 badges -> rate 24, level 10 -> 240 asked, and a
	# wallet holding more than that so the clamp is NOT what is being measured
	# here (E.08/E.09 below own the clamp).
	OverworldSession.reset()
	OverworldSession.flags.flag_set("FLAG_BADGE01_GET")
	OverworldSession.flags.flag_set("FLAG_BADGE02_GET")
	OverworldSession.wallet.money = 5000

	var lost := BattleScreenShared.new()
	lost.overlay_mode = true
	lost._whiteout_party_level = 10
	lost._log_battle_end_result(1)
	var lines: Array[String] = []
	for b: Dictionary in lost._pending_beats:
		lines.append(str(b.get("text", "")))
	_chk("an overworld TRAINER loss prints source's own three whiteout lines",
			lines == [
				"You have no more Pokémon that can fight!",
				"You gave ¥240 to the winner…",
				"You were overwhelmed by your defeat!",
			])
	lost.free()

	# ⚠️ THE DISCRIMINATOR FOR THE MIDDLE LINE. `jumpifbattletype
	# BATTLE_TYPE_TRAINER` picks between STRINGID_PLAYERWHITEOUT2_WILD and
	# ..._TRAINER; an implementation that printed one of them unconditionally
	# passes the assertion above and is wrong half the time.
	var wild_lost := BattleScreenShared.new()
	wild_lost.overlay_mode = true
	wild_lost._whiteout_party_level = 10
	var wild_bm := BattleManager.new()
	wild_bm.is_wild_battle = true
	wild_lost._bm = wild_bm
	wild_lost._log_battle_end_result(1)
	var wild_lines: Array[String] = []
	for b: Dictionary in wild_lost._pending_beats:
		wild_lines.append(str(b.get("text", "")))
	_chk("a WILD loss uses the panicked-and-dropped wording instead",
			wild_lines == [
				"You have no more Pokémon that can fight!",
				"You panicked and dropped ¥240…",
				"You were overwhelmed by your defeat!",
			])
	wild_lost.free()
	wild_bm.free()

	# ⚠️ The payout goes through the SAME function the overworld charges with,
	# clamp included. Asserted against `OverworldSession.whiteout_payout` rather
	# than a second literal, because a screen-side copy of the formula that
	# agreed on the easy case and diverged on the clamp is the exact failure
	# this consolidation exists to make unrepresentable.
	OverworldSession.wallet.money = 100
	var broke := BattleScreenShared.new()
	broke.overlay_mode = true
	broke._whiteout_party_level = 10
	broke._log_battle_end_result(1)
	_chk("the printed figure is clamped to what the player actually holds",
			str(broke._pending_beats[1].get("text", "")) == "You gave ¥100 to the winner…")
	_chk("...and it is the figure the overworld will charge, not a second copy",
			str(broke._pending_beats[1].get("text", ""))
			== "You gave ¥%d to the winner…" % OverworldSession.whiteout_payout(10))
	broke.free()

	# ⚠️ `jumpifnowhiteout`. A rival fight you are MEANT to lose heals you and
	# narrates none of this. Without the gate the player would read three lines
	# about money they never lost.
	var heal_after := BattleScreenShared.new()
	heal_after.overlay_mode = true
	heal_after._whiteout_on_loss = false
	heal_after._whiteout_party_level = 10
	heal_after._log_battle_end_result(1)
	_chk("a heal-after loss narrates no whiteout at all",
			heal_after._pending_beats.is_empty())
	heal_after.free()
	OverworldSession.reset()

	# The discriminator for the whole branch: the SIMULATOR is unchanged,
	# because its Play Again screen is this project's own invention with no
	# source counterpart. A fix that suppressed the line everywhere would pass
	# every assertion above and still be wrong.
	var sim_win := BattleScreenShared.new()
	sim_win._log_battle_end_result(0)
	_chk("a simulator WIN still says You win!",
			sim_win._pending_beats.size() == 1
			and sim_win._pending_beats[0].get("text", "") == "You win!")
	sim_win.free()

	var sim_lose := BattleScreenShared.new()
	sim_lose._log_battle_end_result(1)
	_chk("a simulator LOSS still says You lose!",
			sim_lose._pending_beats.size() == 1
			and sim_lose._pending_beats[0].get("text", "") == "You lose!")
	sim_lose.free()
