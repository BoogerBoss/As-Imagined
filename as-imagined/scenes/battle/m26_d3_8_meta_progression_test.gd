extends Node

# [M26D3-8] Regression suite for meta-progression narration — the last of
# M26D3's 9 sub-phases, and the one that was blocked. This closes it out.
#
# Was blocked on "the overworld landing" (2026-07-27), because meta-
# progression text is the one D3 group whose correct PLACEMENT depended on
# a system that didn't exist yet — this project's simulator ends at an
# invented Win/Lose screen with a Play Again button, and building the text
# then would have baked a placement decision against a battle-end flow M27
# was expected to replace outright.
#
# Re-checked this session: M27 has since shipped in full (M27A-O) and did
# NOT replace that flow — the overworld reuses this exact BATTLE_END screen
# as its own landing point (`overworld._on_battle_overlay_finished`;
# `overlay_mode`'s Play-Again button just relabels to a dismissal,
# `_on_play_again_pressed`). Nor does the overworld's own money/EXP/level
# handling (`OverworldSession.wallet.earn`, the battle-return party sync)
# print anything of its own. So this was, in fact, still just silence — a
# player gains EXP, levels up, and earns money with zero on-screen
# confirmation, in both the standalone simulator and real overworld play.
# The placement question resolves to the same answer as every other D3
# phase: the message box this project already has, via _wire_log_signals().
#
# The headline finding this suite pins: `move_learned`'s widened `kind` arg.
# Mimic and level-up both render "{mon} learned {move}!" (two different
# source STRINGIDs — PKMNLEARNEDMOVE / ...2 — that happen to share text),
# but Sketch genuinely differs (STRINGID_PKMNSKETCHEDMOVE, "{mon} sketched
# {move}!") — verified directly against data/battle_scripts_1.s, not
# assumed uniform. Widening the signal was a real breaking change (Godot 4
# errors, not silently discards, when a connected listener has fewer
# params than a signal emits — confirmed directly before this was chosen
# over an alternative), so every pre-existing listener (m20b_test.gd,
# mimic_sketch_test.gd) was updated alongside it.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_exp_gained_text()
	_test_level_up_text()
	_test_money_awarded_text()
	_test_move_learned_level_up_wording()
	_test_move_learned_mimic_wording()
	_test_move_learned_sketch_wording()
	_test_move_learn_skipped_text()
	_test_full_battle_exp_and_level_up_integration()
	_test_money_awarded_precedes_win_text()
	_test_money_awarded_absent_without_trainer_data()

	var total := _pass + _fail
	print("m26_d3_8_meta_progression_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures (mirrors m26_d3_9_switch_support_test.gd / m20b_test.gd / m24b_test.gd) ──

func _make_mon(mon_name: String, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# Real dex-backed species — growth_rate/learnset only resolve correctly for
# a species PokemonRegistry actually knows about (mirrors m20b_test.gd's
# own _species_from_registry).
func _species_from_registry(dex: int) -> PokemonSpecies:
	var data: Dictionary = PokemonRegistry.get_species(dex)
	var sp := PokemonSpecies.new()
	sp.species_name = data.get("name", "")
	sp.national_dex_num = dex
	sp.base_hp         = data.get("base_hp", 1)
	sp.base_attack     = data.get("base_atk", 1)
	sp.base_defense    = data.get("base_def", 1)
	sp.base_sp_attack  = data.get("base_spa", 1)
	sp.base_sp_defense = data.get("base_spd", 1)
	sp.base_speed      = data.get("base_spe", 1)
	sp.exp_yield = data.get("exp_yield", 0)
	return sp


func _make_bulbasaur(level: int) -> BattlePokemon:
	return BattlePokemon.from_species(_species_from_registry(1), level,
			BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_trainer_data(trainer_class_id: int, last_level: int) -> TrainerData:
	var td := TrainerData.new()
	td.trainer_class_id = trainer_class_id
	var mon := TrainerPartyMon.new()
	mon.species_dex = 1
	mon.level = last_level
	td.party = [mon]
	return td


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _make_bs(bm: BattleManager) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	var pp := BattleParty.new()
	pp.active_indices = []
	bs._player_party = pp
	bs._opp_party = BattleParty.new()
	bs._opp_party.active_indices = []
	bs._bm = bm
	bs._wire_log_signals()
	return bs


func _narrative(bs: BattleScreenShared) -> String:
	var out := ""
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.NARRATIVE:
			out += str(entry["text"]) + "\n"
	return out.strip_edges()


# ── A. exp_gained / level_up / money_awarded — direct-emit text ────────────

func _test_exp_gained_text() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.exp_gained.emit(_make_mon("Gainer"), 103)
	# _mon_label() always prefixes "Your "/"Foe " -- both fixtures below are
	# never added to either party's own `.members`, so both resolve "Foe ".
	# Substring checks (not exact equality) sidestep that, matching
	# m26_d3_9_switch_support_test.gd's own established convention.
	_chk("A.01 exp_gained narrates the real source phrasing",
			"Gainer gained 103 Exp. Points!" in _narrative(bs))
	bs.free()
	bm.queue_free()


func _test_level_up_text() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.level_up.emit(_make_mon("Riser"), 9)
	_chk("A.02 level_up narrates the real source phrasing",
			"Riser grew to Lv. 9!" in _narrative(bs))
	bs.free()
	bm.queue_free()


func _test_money_awarded_text() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.money_awarded.emit(1900)
	_chk("A.03 money_awarded narrates the real source phrasing",
			_narrative(bs) == "You got ¥1900 for winning!")
	bs.free()
	bm.queue_free()


# ── B. move_learned's `kind` distinction — the headline finding ────────────

func _test_move_learned_level_up_wording() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_learned.emit(_make_mon("Learner"), 3, _load_move(75), "level_up")
	_chk("B.01 level-up uses 'learned' (STRINGID_PKMNLEARNEDMOVE)",
			"Learner learned Razor Leaf!" in _narrative(bs))
	bs.free()
	bm.queue_free()


func _test_move_learned_mimic_wording() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_learned.emit(_make_mon("Mimicker"), 0, _load_move(33), "mimic")
	_chk("B.02 Mimic ALSO uses 'learned' — a different source STRINGID (...2) "
			+ "than level-up's, but the identical rendered text",
			"Mimicker learned Tackle!" in _narrative(bs))
	bs.free()
	bm.queue_free()


func _test_move_learned_sketch_wording() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_learned.emit(_make_mon("Sketcher"), 0, _load_move(33), "sketch")
	var line := _narrative(bs)
	_chk("B.03 Sketch is worded DIFFERENTLY: 'sketched', not 'learned' "
			+ "(STRINGID_PKMNSKETCHEDMOVE — a genuinely distinct source string)",
			"Sketcher sketched Tackle!" in line)
	_chk("B.03b ...and specifically does NOT reuse the 'learned' wording",
			not ("learned Tackle" in line))
	bs.free()
	bm.queue_free()


func _test_move_learn_skipped_text() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_learn_skipped.emit(_make_mon("FourMoves"), _load_move(59))
	_chk("B.04 move_learn_skipped narrates the real source phrasing "
			+ "(STRINGID_DIDNOTLEARNMOVE, a period not an exclamation mark)",
			"FourMoves did not learn Blizzard." in _narrative(bs))
	bs.free()
	bm.queue_free()


# ── C. Full-battle integration — the real production call sites ────────────

# Mirrors m20b_test.gd's own _test_full_battle_integration, but through the
# real message log instead of a raw signal-argument capture: proves
# exp_gained and level_up both narrate correctly, IN ORDER, from the same
# real _award_exp_for_fainted_opponent() call site D3-8 was blocked on.
func _test_full_battle_exp_and_level_up_integration() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	var recipient := _make_bulbasaur(8)
	recipient.current_exp = 418  # curve[9]-1, one short of leveling

	var fainted := _make_bulbasaur(8)
	fainted.current_hp = 1

	bm._exp_participants = [[0]]
	bm._parties = [BattleParty.single(recipient), BattleParty.single(fainted)]
	bm._combatants = [recipient, fainted]
	bm._active_per_side = 1

	# Same math m20b_test.gd already source-verified: 418+103=521, crossing
	# curve[9]=419 (one clean level-up, 8 -> 9).
	bm._award_exp_for_fainted_opponent(fainted)
	var line := _narrative(bs)
	_chk("C.01 the real call site narrates the exact computed EXP award",
			"gained 103 Exp. Points!" in line)
	_chk("C.02 ...and the level-up that award triggers",
			"grew to Lv. 9!" in line)
	_chk("C.03 EXP is narrated BEFORE the level-up it causes (source order)",
			line.find("gained 103 Exp") < line.find("grew to Lv. 9"))
	bs.free()
	bm.queue_free()


# money_awarded fires immediately before battle_ended in source order
# (_phase_battle_end_check) — proving that ordering survives all the way
# into the real narrated log, not just the raw signal-emission order, is
# the one thing worth checking end-to-end for this specific signal (every
# other D3-8 signal was already covered by the direct-emit tests above).
func _test_money_awarded_precedes_win_text() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.battle_ended.connect(bs._on_battle_ended)

	var player := _make_mon("Player", 200)
	var opp := _make_mon("Opp", 20)
	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	bm.set_trainer_data(1, _make_trainer_data(32, 19))  # LEADER, level 19 -> 1900
	bm.start_battle(player, opp)

	var line := _narrative(bs)
	_chk("D.01 setup: the battle actually produced a win with a real reward",
			"You got ¥1900 for winning!" in line and "You win!" in line)
	_chk("D.02 the prize-money line precedes the win text, matching source's "
			+ "own Cmd_getmoneyreward-then-battle-end ordering",
			line.find("You got ¥1900") < line.find("You win!"))
	bs.free()
	bm.queue_free()


# Regression guard mirroring m24b_test.gd's own D3 case — no attached
# TrainerData, no money, and therefore no money line in the log either.
func _test_money_awarded_absent_without_trainer_data() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.battle_ended.connect(bs._on_battle_ended)

	var player := _make_mon("Player", 200)
	var opp := _make_mon("Opp", 20)
	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	# Deliberately no set_trainer_data call.
	bm.start_battle(player, opp)

	var line := _narrative(bs)
	_chk("E.01 a win with no attached opponent TrainerData still shows 'You win!'",
			"You win!" in line)
	_chk("E.02 ...but no money line appears at all",
			not ("¥" in line))
	bs.free()
	bm.queue_free()
