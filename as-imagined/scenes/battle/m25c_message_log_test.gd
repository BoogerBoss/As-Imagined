extends Node

# [M25c, retargeted M26b] Regression suite for battle message/log
# authenticity: move-announcement text, target naming, damage/effectiveness
# reporting, and the turn separator — plus one real end-to-end proof that
# BattleManager's own signals (turn_started/move_announced/
# move_effectiveness_computed) actually fire correctly from real gameplay,
# not just that the UI handler logic is correct in isolation.
#
# [M26b] The old always-visible VBox/LogLabel (and its paced reveal queue)
# was retired outright — every assertion below that used to read
# `bs._log_label.text` now reads the NARRATIVE-category entries in the new
# merged, category-tagged `_debug_entries` history instead (via the
# `_narrative_text()` helper below), which is where this exact same text
# now lands. Content/wording/ordering are unchanged from M25c's own
# original work — only the sink changed. Pacing itself (M25c's own
# `_queue_log_line`/`_run_log_reveal`, 0.6s between lines) was dropped
# entirely by M26b, not merely bypassed by this suite's bare-instance
# convention as it was before — see battle_screen.gd's own current `_log()`
# doc comment for the disclosed reasoning.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_announcement_foe_targeting_names_target()
	_test_announcement_self_targeting_omits_target()
	_test_announcement_doubles_spread_omits_target()
	_test_announcement_spread_move_in_singles_names_target()
	_test_effectiveness_super_effective()
	_test_effectiveness_not_very_effective()
	_test_effectiveness_no_effect_names_target_and_suppresses_damage_line()
	_test_effectiveness_neutral_stays_silent()
	_test_critical_hit_line_precedes_effectiveness_line()
	_test_status_move_produces_no_effectiveness_or_damage_line()
	_test_turn_separator()
	_test_doubles_spread_two_targets_one_announcement_two_damage_lines()
	_test_real_battle_end_to_end_signal_wiring()

	var total := _pass + _fail
	print("m25c_message_log_test: %d/%d passed" % [_pass, total])
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


func _make_move(move_name: String, type_id: int, power: int, is_spread: bool = false) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = type_id
	m.category = 1  # Special — irrelevant to effectiveness/announcement text
	m.power = power
	m.accuracy = 0  # always hits, matching this project's established "not checked here" convention
	m.pp = 10
	m.priority = 0
	m.is_spread = is_spread
	return m


func _singles_party(mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [mon]
	p.members = members
	p.active_indices = [0]
	return p


func _doubles_party(mons: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed: Array[BattlePokemon] = []
	for m: BattlePokemon in mons:
		typed.append(m)
	p.members = typed
	p.active_indices = [0, 1]
	return p


func _make_bs(attacker: BattlePokemon) -> BattleScreen:
	var bs := BattleScreen.new()
	bs._player_party = _singles_party(attacker)
	return bs


# [M26b] Joins every NARRATIVE-category entry's own text, each followed by
# "\n" — reproduces the exact shape `bs._log_label.text` used to have
# (`_log()` always appended `text + "\n"`), so most of this file's own
# pre-existing exact-string assertions needed no change beyond swapping
# `bs._log_label.text` for `_narrative_text(bs)`.
func _narrative_text(bs: BattleScreen) -> String:
	var out := ""
	for entry in bs._debug_entries:
		if entry["category"] == BattleScreen.DebugCategory.NARRATIVE:
			out += entry["text"] + "\n"
	return out


# ── 1-4. Move announcement / target naming ───────────────────────────────

func _test_announcement_foe_targeting_names_target() -> void:
	var attacker := _make_typed_mon("Angler", TypeChart.TYPE_WATER)
	var defender := _make_typed_mon("Blaze", TypeChart.TYPE_FIRE)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	var bs := _make_bs(attacker)

	bs._on_log_move_announced(attacker, defender, move)

	_chk("foe-targeting announcement names the target",
			_narrative_text(bs) == "Your Angler used Water Gun on Foe Blaze!\n")


func _test_announcement_self_targeting_omits_target() -> void:
	var attacker := _make_typed_mon("Angler2", TypeChart.TYPE_WATER)
	var move := _make_move("Swords Dance", TypeChart.TYPE_NORMAL, 0)
	var bs := _make_bs(attacker)

	# Self-targeting moves resolve defender == attacker at the BattleManager
	# layer already (see _on_hit_effect_move_executed's own doc comment for
	# the same established convention).
	bs._on_log_move_announced(attacker, attacker, move)

	_chk("self-targeting announcement does NOT awkwardly name the user as a target",
			_narrative_text(bs) == "Your Angler2 used Swords Dance!\n")


func _test_announcement_doubles_spread_omits_target() -> void:
	var attacker := _make_typed_mon("Angler3", TypeChart.TYPE_WATER)
	var opp0 := _make_typed_mon("Opp0", TypeChart.TYPE_FIRE)
	var move := _make_move("Surf", TypeChart.TYPE_WATER, 30, true)
	var bs := _make_bs(attacker)
	bs._is_doubles_mode = true

	bs._on_log_move_announced(attacker, opp0, move)

	_chk("a real doubles spread hit's announcement names no single target (ambiguous)",
			_narrative_text(bs) == "Your Angler3 used Surf!\n")


func _test_announcement_spread_move_in_singles_names_target() -> void:
	# A move flagged is_spread (a per-move data property, independent of
	# battle format) used in an ACTUAL singles battle only ever has one
	# possible target — must still be named, unlike the real doubles case
	# above. Confirms the gate is `move.is_spread AND _is_doubles_mode`, not
	# raw `move.is_spread` alone.
	var attacker := _make_typed_mon("Angler4", TypeChart.TYPE_WATER)
	var opp := _make_typed_mon("SoloOpp", TypeChart.TYPE_FIRE)
	var move := _make_move("Surf", TypeChart.TYPE_WATER, 30, true)
	var bs := _make_bs(attacker)
	bs._is_doubles_mode = false

	bs._on_log_move_announced(attacker, opp, move)

	_chk("a spread-flagged move used in an actual singles battle still names its one real target",
			_narrative_text(bs) == "Your Angler4 used Surf on Foe SoloOpp!\n")


# ── 5-9. Damage / effectiveness / crit reporting ─────────────────────────
# Phrasing and thresholds confirmed directly against
# reference/pokeemerald_expansion/src/battle_message.c: STRINGID_CRITICALHIT,
# STRINGID_SUPEREFFECTIVE (>=2.0x), STRINGID_NOTVERYEFFECTIVE (0<x<1.0),
# STRINGID_ITDOESNTAFFECT (exactly 0.0x, the one line that names a target in
# the real games too). Neutral (1.0x) stays silent, matching source exactly.

func _test_effectiveness_super_effective() -> void:
	var attacker := _make_typed_mon("A5", TypeChart.TYPE_WATER)
	var defender := _make_typed_mon("D5", TypeChart.TYPE_FIRE)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	var bs := _make_bs(attacker)

	bs._on_hit_effectiveness_computed(defender, 2.0, false)
	bs._on_log_move_executed(attacker, defender, move, 40)

	_chk("super-effective (2.0x) prints the real games' own exact line",
			_narrative_text(bs) == "It's super effective!\nFoe D5 took 40 damage!\n")


func _test_effectiveness_not_very_effective() -> void:
	var attacker := _make_typed_mon("A6", TypeChart.TYPE_WATER)
	var defender := _make_typed_mon("D6", TypeChart.TYPE_GRASS)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	var bs := _make_bs(attacker)

	bs._on_hit_effectiveness_computed(defender, 0.5, false)
	bs._on_log_move_executed(attacker, defender, move, 10)

	_chk("not-very-effective (0.5x) prints the real games' own exact line",
			_narrative_text(bs) == "It's not very effective…\nFoe D6 took 10 damage!\n")


func _test_effectiveness_no_effect_names_target_and_suppresses_damage_line() -> void:
	var attacker := _make_typed_mon("A7", TypeChart.TYPE_ELECTRIC)
	var defender := _make_typed_mon("D7", TypeChart.TYPE_GROUND)
	var move := _make_move("Thunder Shock", TypeChart.TYPE_ELECTRIC, 40)
	var bs := _make_bs(attacker)

	bs._on_hit_effectiveness_computed(defender, 0.0, false)
	bs._on_log_move_executed(attacker, defender, move, 0)

	_chk("a true 0x immunity names the target (matching source's own STRINGID_ITDOESNTAFFECT) and prints no damage line",
			_narrative_text(bs) == "It doesn't affect Foe D7…\n")


func _test_effectiveness_neutral_stays_silent() -> void:
	var attacker := _make_typed_mon("A8", TypeChart.TYPE_NORMAL)
	var defender := _make_typed_mon("D8", TypeChart.TYPE_NORMAL)
	var move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 40)
	var bs := _make_bs(attacker)

	bs._on_hit_effectiveness_computed(defender, 1.0, false)
	bs._on_log_move_executed(attacker, defender, move, 25)

	_chk("a neutral 1.0x hit stays silent on effectiveness, matching source exactly",
			_narrative_text(bs) == "Foe D8 took 25 damage!\n")


func _test_critical_hit_line_precedes_effectiveness_line() -> void:
	var attacker := _make_typed_mon("A9", TypeChart.TYPE_WATER)
	var defender := _make_typed_mon("D9", TypeChart.TYPE_FIRE)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40)
	var bs := _make_bs(attacker)

	bs._on_hit_effectiveness_computed(defender, 2.0, true)
	bs._on_log_move_executed(attacker, defender, move, 80)

	_chk("a crit prints 'A critical hit!' before the effectiveness line, then the damage line",
			_narrative_text(bs) == "A critical hit!\nIt's super effective!\nFoe D9 took 80 damage!\n")


func _test_status_move_produces_no_effectiveness_or_damage_line() -> void:
	# No _on_hit_effectiveness_computed call at all — mirrors a real status
	# move (move_effectiveness_computed is never emitted for one).
	var attacker := _make_typed_mon("A10", TypeChart.TYPE_NORMAL)
	var defender := _make_typed_mon("D10", TypeChart.TYPE_NORMAL)
	var move := _make_move("Growl", TypeChart.TYPE_NORMAL, 0)
	var bs := _make_bs(attacker)

	bs._on_log_move_executed(attacker, defender, move, 0)

	_chk("a status move's own move_executed (damage=0, no pending hit data) prints nothing on its own",
			_narrative_text(bs) == "")


# ── 10. Turn separator ───────────────────────────────────────────────────
# [M26b] The turn separator is now structural, not a text line —
# _on_log_turn_started updates _current_debug_turn, and every subsequent
# entry is stamped with it; _render_debug_overlay() inserts the visible
# "──── Turn N ────" line itself at render time. Confirmed two ways: the
# structural stamp itself, and the actual rendered BBCode output (which
# needs a real onready _debug_body — added directly here on a bare
# instance, mirroring this project's own established "manually construct
# the one onready node a bare-instance test needs" convention, e.g.
# phase4e_message_box_test.gd's own fake_log_label).

func _test_turn_separator() -> void:
	var attacker := _make_typed_mon("A11", TypeChart.TYPE_NORMAL)
	var bs := _make_bs(attacker)

	bs._on_log_turn_started(5)
	_chk("turn separator updates _current_debug_turn structurally, not as a text line",
			bs._current_debug_turn == 5)

	bs._add_debug_entry(BattleScreen.DebugCategory.NARRATIVE, "something happened")
	_chk("a subsequent entry is stamped with the real current turn number",
			bs._debug_entries[-1]["turn"] == 5)

	bs._debug_body = RichTextLabel.new()
	bs._render_debug_overlay()
	_chk("the rendered panel text contains a real turn separator for turn 5",
			"Turn 5" in bs._debug_body.text)


# ── 11. Doubles: one announcement, two independently-thresholded per-
# target damage/effectiveness lines for a single spread action. ─────────

func _test_doubles_spread_two_targets_one_announcement_two_damage_lines() -> void:
	var attacker := _make_typed_mon("A12", TypeChart.TYPE_WATER)
	var opp0 := _make_typed_mon("Opp0_12", TypeChart.TYPE_FIRE)   # 2.0x
	var opp1 := _make_typed_mon("Opp1_12", TypeChart.TYPE_GRASS)  # 0.5x
	var move := _make_move("Surf", TypeChart.TYPE_WATER, 30, true)
	var bs := _make_bs(attacker)
	bs._is_doubles_mode = true

	bs._on_log_move_announced(attacker, opp0, move)
	bs._on_hit_effectiveness_computed(opp0, 2.0, false)
	bs._on_log_move_executed(attacker, opp0, move, 30)
	bs._on_hit_effectiveness_computed(opp1, 0.5, false)
	bs._on_log_move_executed(attacker, opp1, move, 8)

	_chk("a 2-target spread hit announces once and reports each target's own damage/effectiveness separately",
			_narrative_text(bs) == "Your A12 used Surf!\nIt's super effective!\nFoe Opp0_12 took 30 damage!\n" \
					+ "It's not very effective…\nFoe Opp1_12 took 8 damage!\n")


# ── 12. Real end-to-end proof: BattleManager's own new signals actually
# fire from a genuine battle, not just correct handler logic in isolation.
# Mirrors m25b_menu_test.gd's own _test_target_select_back_returns_to_
# fight_not_top precedent (a real BattleManager.new() safely add_child()-able
# into the test's own tree, unlike BattleScreen which needs its scene's real
# child nodes to survive _ready()). `bs` itself stays bare/un-added (its own
# get_tree() stays null), so _wire_log_signals() is called manually instead
# of via _ready(), and log lines still land synchronously/immediately —
# exactly this project's established bare-instance convention. ─────────

func _test_real_battle_end_to_end_signal_wiring() -> void:
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

	var bs := BattleScreen.new()
	bs._player_party = _singles_party(attacker)
	bs._opp_party = _singles_party(opp)
	bs._bm = bm
	bs._wire_log_signals()

	bm.start_battle_with_parties(_singles_party(attacker), _singles_party(opp))
	_chk("battle starts at turn 1 already emitted", bm.turn_number == 1)
	_chk("the turn separator's own structural stamp reached the merged history via a genuinely fired turn_started signal",
			bs._current_debug_turn == 1)

	bm.queue_move_targeted(0, 0, 1)
	bm.queue_move_targeted(1, 0, 0)
	bm.advance()

	_chk("the real attacker's own move-announcement line reached the log via a genuinely fired move_announced signal",
			"Your RealAngler used Water Gun on Foe RealBlaze!" in _narrative_text(bs))
	_chk("the real hit's own effectiveness line reached the log via a genuinely fired move_effectiveness_computed signal",
			"It's super effective!" in _narrative_text(bs))
	_chk("the real hit's own damage line reached the log via the existing move_executed signal",
			"Foe RealBlaze took" in _narrative_text(bs) and "damage!" in _narrative_text(bs))

	bm.queue_free()
