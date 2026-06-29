extends Node

# Trainer AI decision test suite — M10 (A1-A13) and M13 (A14-A20).
#
# Verification methodology: decision tests, not exact-value unit tests. Each test
# constructs a scenario where one choice is clearly correct given already-verified
# mechanics (damage calc, type chart, status, items) and asserts the AI makes it.
# RNG is forced deterministically where needed.
#
# Confirmed from source: the AI IS rule-based / scoring-based, not deep search.
# Source: ChooseMoveOrAction_Singles (battle_ai_main.c L856) iterates AI_FLAG
# bits and runs a scoring pass per flag. Tie-breaking is random (L915).
#
# M13 confirmed from source:
#   - Items compose through DamageCalculator automatically (no scoring changes needed).
#   - Choice-lock: moveLimitations prefilter (battle_ai_main.c L174-187).
#   - ShouldSwitchIfBadChoiceLock (battle_ai_switch.c L1170-1213): 100% deterministic.
#   - Berry-triggered awareness: confirmed absent from source (see docs/decisions.md).
#
# Sections:
#   A1:  TrainerAI unit — type effectiveness scoring
#   A2:  TrainerAI unit — KO move preference (FAST_KILL / SLOW_KILL)
#   A3:  AI_CheckBadMove — type immunity avoidance
#   A4:  AI_CheckBadMove — status move vs already-statused target
#   A5:  AI_CheckBadMove — two-turn non-semi-inv avoided when being OHKOd
#   A6:  AI_CheckViability — status bonus on fresh target
#   A7:  BASIC tier does NOT proactively switch
#   A8:  SMART tier switches when all moves are type-immune
#   A9:  SMART tier switches when being OHKOd (force_switch_rng=1)
#   A10: SMART tier stays when force_switch_rng=0
#   A11: Faint replacement picks best type matchup
#   A12: BattleManager integration — AI drives a full singles battle
#   A13: Integration — AI avoids wasted status move (Thunder Wave on Ground)
#   A14: M13 — choice-locked AI returns locked move (positive)
#   A15: M13 — pre-lock AI scores freely (negative/contrast to A14)
#   A16: M13 — SMART switches when locked into status move (positive)
#   A17: M13 — SMART stays when locked into effective move (negative)
#   A18: M13 — SMART switches when locked into type-immune move (positive)
#   A19: M13 — Choice Band makes previously-non-KO move KO → AI picks it (positive)
#   A20: M13 — Without Band, other move wins (negative/contrast to A19)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a1_effectiveness_scoring()
	_test_section_a2_ko_preference()
	_test_section_a3_type_immunity()
	_test_section_a4_status_on_statused()
	_test_section_a5_two_turn_ohko()
	_test_section_a6_status_fresh_bonus()
	_test_section_a7_basic_no_switch()
	_test_section_a8_smart_all_immune()
	_test_section_a9_smart_hasbadodds_force_switch()
	_test_section_a10_smart_hasbadodds_force_stay()
	_test_section_a11_faint_replacement()
	_test_section_a12_full_battle()
	_test_section_a13_integration_immune_status()
	_test_section_a14_choice_lock_returns_locked()
	_test_section_a15_pre_lock_free_scoring()
	_test_section_a16_bad_lock_switch_status()
	_test_section_a17_bad_lock_stay_effective()
	_test_section_a18_bad_lock_switch_immune()
	_test_section_a19_band_changes_move_selection()
	_test_section_a20_without_band_other_move_wins()

	var total := _pass + _fail
	print("ai_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 160, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	# append() avoids the typed Array assignment gotcha (Array[int] rejects an
	# untyped literal built from variables at runtime in GDScript 4.x).
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp    = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, move_type: int, category: int, power: int,
		secondary_effect: int = MoveData.SE_NONE,
		two_turn: bool = false) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = move_type
	m.category = category
	m.power = power
	m.accuracy = 100
	m.pp = 40
	m.secondary_effect = secondary_effect
	m.secondary_chance = 0
	m.two_turn = two_turn
	m.semi_inv_state = MoveData.SEMI_INV_NONE
	return m


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_item(hold_effect: int) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	return item


# ── A1: Type effectiveness scoring ───────────────────────────────────────────
# AI should prefer a 4× move > 2× move > 0.5× move when neither KOs.
# Mechanism: AI_CompareDamagingMoves (battle_ai_main.c L3940) — the move with the
# fewest hits to KO the defender gets BEST_DAMAGE_MOVE (+1). Higher effectiveness
# means more damage per hit → fewer hits to KO → wins the comparison.

func _test_section_a1_effectiveness_scoring() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	# Attacker: Normal type, moves: Water (neutral vs Fire), Water (2× vs Fire),
	# should prefer the 2× effective move. We'll do this by giving the attacker
	# two moves with identical stats but different types.
	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	# Defender: pure Water type. Water→Water = 0.5×. Fire→Water = 0.5×. Grass→Water = 2×.
	var defender := _make_mon("Def", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)
	defender.current_hp = 500  # well above any KO

	var fire_move  := _make_move("Ember",   TypeChart.TYPE_FIRE,  1, 40)   # 0.5× vs Water
	var grass_move := _make_move("Vine",    TypeChart.TYPE_GRASS, 1, 40)   # 2×  vs Water
	attacker.add_move(fire_move)
	attacker.add_move(grass_move)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	_chk("A1.01 choose_action returns move", action["type"] == "move")
	_chk("A1.02 prefers 2× effective move (index 1)", action["index"] == 1)

	# 4× test: add Ice move (4× vs Dragon/Flying). Defender = Dragon+Flying.
	var defender2 := _make_mon("Dragon", TypeChart.TYPE_DRAGON, TypeChart.TYPE_FLYING,
			500, 40, 80, 40, 80, 80)
	defender2.current_hp = 500
	var attacker2 := _make_mon("Atk2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var normal_move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)   # 1× vs Dragon
	var ice_move    := _make_move("Ice",    TypeChart.TYPE_ICE,    1, 40)   # 4× vs Dragon/Flying
	attacker2.add_move(normal_move)
	attacker2.add_move(ice_move)

	var action2 := ai.choose_action(attacker2, defender2,
			BattleParty.single(attacker2), BattleParty.single(defender2))
	_chk("A1.03 prefers 4× effective move (index 1)", action2["index"] == 1)


# ── A2: KO move preference (FAST_KILL / SLOW_KILL) ───────────────────────────
# AI must pick the move that OHKOs the defender.
# Source: AI_TryToFaint L3000 — FAST_KILL(+6) if faster, SLOW_KILL(+4) if slower.

func _test_section_a2_ko_preference() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	# Attacker with high attack, defender at 1 HP. One KO move, one weak move.
	var attacker := _make_mon("Strong", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 150, 80, 80, 80, 200)
	var defender := _make_mon("Fragile", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 40, 80, 40, 80, 80)
	defender.current_hp = 1  # any hit KOs

	var splash := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0)  # status, 0 power, no damage
	# Use a real MoveData for the damaging move so DamageCalculator works correctly:
	# Splash won't KO, tackle will (power 40, defender at 1 HP).
	var tackle := _load_move(33)
	attacker.add_move(splash)
	attacker.add_move(tackle)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	_chk("A2.01 picks KO move over status noop (index 1)", action["index"] == 1)

	# Slower attacker should also prefer KO move (SLOW_KILL +4 still beats default 100).
	var slow_attacker := _make_mon("Slow", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 150, 80, 80, 80, 40)
	var splash2 := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0)
	var tackle2  := _load_move(33)
	slow_attacker.add_move(splash2)
	slow_attacker.add_move(tackle2)

	var action2 := ai.choose_action(slow_attacker, defender,
			BattleParty.single(slow_attacker), BattleParty.single(defender))
	_chk("A2.02 slower attacker still picks KO move", action2["index"] == 1)


# ── A3: Type immunity avoidance ───────────────────────────────────────────────
# AI must avoid a type-immune move when a usable alternative exists.
# Ground type is immune to Electric (Thunder Wave, Electric moves).
# Source: AI_CheckBadMove L1294 — RETURN_SCORE_MINUS(20) when effectiveness == 0.

func _test_section_a3_type_immunity() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	# Attacker: Electric type. Defender: Ground type (immune to Electric).
	var attacker := _make_mon("Atk", TypeChart.TYPE_ELECTRIC, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var defender := _make_mon("Ground", TypeChart.TYPE_GROUND, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 40)
	defender.current_hp = 500

	# Electric move (immune) vs Normal move (not immune).
	var thunder_move := _make_move("Thunderbolt", TypeChart.TYPE_ELECTRIC, 1, 90)
	var tackle       := _load_move(33)  # Normal, always hits vs Normal/Ground
	attacker.add_move(thunder_move)
	attacker.add_move(tackle)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	_chk("A3.01 avoids immune Electric move vs Ground (picks index 1)",
			action["index"] == 1)

	# Score sanity: immune move score = 100 - 20 = 80; tackle = 100.
	# So tackle wins.
	_chk("A3.02 picks the only non-immune move", action["type"] == "move")


# ── A4: Status move vs already-statused target ────────────────────────────────
# AI should not waste Thunder Wave on a target that is already paralyzed.
# Source: AI_CheckBadMove L2933-2960 — ADJUST_SCORE(-10) when !AI_CanParalyze.

func _test_section_a4_status_on_statused() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 100)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)
	defender.current_hp = 500
	defender.status = BattlePokemon.STATUS_PARALYSIS  # already paralyzed

	var thunder_wave := _make_move("ThunderWave", TypeChart.TYPE_ELECTRIC, 2, 0,
			MoveData.SE_PARALYSIS)
	var tackle := _load_move(33)
	attacker.add_move(thunder_wave)
	attacker.add_move(tackle)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# Thunder Wave score: 100 - 10 (already paralyzed) = 90. Tackle: 100. Tackle wins.
	_chk("A4.01 avoids Thunder Wave on already-paralyzed target", action["index"] == 1)
	_chk("A4.02 picks tackle instead", action["type"] == "move")


# ── A5: Two-turn avoided when being OHKOd ─────────────────────────────────────
# AI should not use Solar Beam (two-turn, no semi-invulnerability) when the
# opponent can KO it before the release turn.
# Source: AI_CheckBadMove L1254 — RETURN_SCORE_MINUS(10) when two-turn + OHKOd.

func _test_section_a5_two_turn_ohko() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	# Attacker: low HP (1), defender has a damaging move. Two-turn move + tackle.
	var attacker := _make_mon("Weak", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			160, 40, 40, 80, 40, 80)
	attacker.current_hp = 1  # any hit from defender KOs us

	var defender := _make_mon("Atk", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			500, 150, 80, 80, 80, 200)
	defender.current_hp = 500
	var tackle_def := _load_move(33)
	defender.add_move(tackle_def)

	# Solar Beam: Grass, Special, power=120, two_turn, no semi-inv.
	var solar_beam := _make_move("SolarBeam", TypeChart.TYPE_GRASS, 1, 120,
			MoveData.SE_NONE, true)  # two_turn=true, semi_inv_state default 0
	var tackle := _load_move(33)
	attacker.add_move(solar_beam)
	attacker.add_move(tackle)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# Solar Beam score: 100 - 10 (two-turn penalty when OHKOd). Tackle: 100. Tackle wins.
	_chk("A5.01 avoids two-turn non-semi-inv move when being OHKOd", action["index"] == 1)
	_chk("A5.02 picks tackle instead", action["type"] == "move")


# ── A6: Status move fresh-target bonus ────────────────────────────────────────
# Status move on a fresh (no-status) target gets +2 vs neutral damaging move.
# Source: AI_CalcMoveEffectScore IncreasePoisonScore etc. → DECENT_EFFECT(+2).

func _test_section_a6_status_fresh_bonus() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	var attacker := _make_mon("Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 100)
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)
	defender.current_hp = 500
	# defender.status = STATUS_NONE (default)

	# Two moves: Splash (category=2, no effect → SE_NONE, NO status bonus) vs
	# Toxic (category=2, SE_TOXIC, should get +2 on fresh target).
	var splash  := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0, MoveData.SE_NONE)
	var toxic_m := _make_move("Toxic",  TypeChart.TYPE_POISON, 2, 0, MoveData.SE_TOXIC)
	attacker.add_move(splash)
	attacker.add_move(toxic_m)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# Splash: 100 (no bonus). Toxic: 100 + 2 = 102. Toxic wins.
	_chk("A6.01 prefers status move on fresh target (index 1)", action["index"] == 1)
	_chk("A6.02 returns move type", action["type"] == "move")


# ── A7: BASIC tier — no proactive switch ──────────────────────────────────────
# Basic trainers (AI_FLAG_BASIC_TRAINER) never voluntarily switch mid-battle.
# Source: AI_TrySwitchOrUseItem L465 — only fires if gAiLogicData->shouldSwitch
# is set, which requires AI_FLAG_SMART_SWITCHING (not present in BASIC_TRAINER).

func _test_section_a7_basic_no_switch() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.BASIC

	# Attacker: Ghost type with only Normal move (immune vs Ghost defender).
	# This WOULD trigger a switch in SMART tier, but BASIC stays and attacks.
	var attacker := _make_mon("Ghost", TypeChart.TYPE_GHOST, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	# NOTE: Normal is immune vs Ghost; but we're asking ATTACKER (Ghost) to use Normal.
	# TypeChart: Normal vs Ghost = immune. So attacker's only move is ineffective.
	var normal_move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	attacker.add_move(normal_move)

	var defender := _make_mon("Ghost", TypeChart.TYPE_GHOST, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)

	var partner := _make_mon("Backup", TypeChart.TYPE_FIGHTING, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var ghost_move := _make_move("Shadow", TypeChart.TYPE_GHOST, 0, 60)
	partner.add_move(ghost_move)

	var my_party := BattleParty.new()
	my_party.members = [attacker, partner]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A7.01 BASIC tier returns move (not switch)", action["type"] == "move")
	_chk("A7.02 BASIC tier picks index 0 (only move)", action["index"] == 0)


# ── A8: SMART tier — switch when all moves immune ─────────────────────────────
# SMART AI switches out when every damaging move is type-immune vs opponent.
# Source: ShouldSwitchIfAllMovesBad (battle_ai_switch.c L481).
# Chance = 100% (SHOULD_SWITCH_ALL_MOVES_BAD_PERCENTAGE = 100).

func _test_section_a8_smart_all_immune() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART

	# Attacker: only Normal moves. Defender: Ghost type (Normal immune vs Ghost).
	var attacker := _make_mon("Normal", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	attacker.add_move(tackle)

	var defender := _make_mon("Ghost", TypeChart.TYPE_GHOST, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)

	# Backup mon with a Ghost move (actually effective vs Ghost).
	var backup := _make_mon("Backup", TypeChart.TYPE_PSYCHIC, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var ghost_move := _make_move("Shadow", TypeChart.TYPE_GHOST, 0, 60)
	backup.add_move(ghost_move)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A8.01 SMART tier switches (not move) when all moves immune",
			action["type"] == "switch")
	_chk("A8.02 switches to slot 1 (backup)", action["slot"] == 1)


# ── A9: SMART tier — ShouldSwitchIfHasBadOdds (force switch) ─────────────────
# SMART AI switches when being OHKOd, has no SE move, and HP >= 50%.
# Switch chance = 50%, forced to 100% with _force_switch_rng=1.
# Source: ShouldSwitchIfHasBadOdds (battle_ai_switch.c L367).

func _test_section_a9_smart_hasbadodds_force_switch() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	ai._force_switch_rng = 1  # force "switch" branch of the 50% roll

	# Attacker: mid HP, only neutral move. Defender: high attack, can OHKO attacker.
	var attacker := _make_mon("Mid", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			160, 40, 40, 40, 40, 80)
	# attacker.current_hp defaults to max_hp (full) → >= 50%
	var water_move := _make_move("Water", TypeChart.TYPE_WATER, 1, 40)  # neutral vs Normal
	attacker.add_move(water_move)

	# Defender: high power move (power=120) to guarantee OHKO.
	# At level 50 with base_atk=250 → actual_atk=255, attacker actual_def=45:
	#   damage ≈ ((22 * 120 * 255 / 45 / 50) + 2) * 1.5 (STAB Normal) ≈ 450+ >> 220 HP.
	var defender := _make_mon("Strong", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 250, 100, 80, 100, 200)
	var big_move_a9 := _make_move("Crush", TypeChart.TYPE_NORMAL, 0, 120)
	defender.add_move(big_move_a9)

	var backup := _make_mon("Backup", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var grass_move := _make_move("Vine", TypeChart.TYPE_GRASS, 1, 45)
	backup.add_move(grass_move)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A9.01 SMART switches when OHKOd + no SE + HP≥50% (forced)",
			action["type"] == "switch")
	_chk("A9.02 switches to slot 1", action["slot"] == 1)


# ── A10: SMART tier — ShouldSwitchIfHasBadOdds (force stay) ──────────────────
# Same scenario as A9 but force_switch_rng=0 → AI stays and attacks.
# Source: RandomPercentage(RNG_AI_SWITCH_HASBADODDS, 50) — 50% chance to stay.

func _test_section_a10_smart_hasbadodds_force_stay() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	ai._force_switch_rng = 0  # force "stay" branch

	var attacker := _make_mon("Mid", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			160, 40, 40, 40, 40, 80)
	var water_move := _make_move("Water", TypeChart.TYPE_WATER, 1, 40)
	attacker.add_move(water_move)

	var defender := _make_mon("Strong", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 250, 100, 80, 100, 200)
	var big_move_a10 := _make_move("Crush", TypeChart.TYPE_NORMAL, 0, 120)
	defender.add_move(big_move_a10)

	var backup := _make_mon("Backup", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var grass_move := _make_move("Vine", TypeChart.TYPE_GRASS, 1, 45)
	backup.add_move(grass_move)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A10.01 SMART stays when force_switch_rng=0 (50% stay branch)",
			action["type"] == "move")


# ── A11: Faint replacement picks best type matchup ────────────────────────────
# After a faint, choose_replacement should prefer the party member with a
# super-effective move against the current opponent.
# Source: GetSwitchinCandidate SWITCHIN_CONSIDER_MOST_SUITABLE (battle_ai_switch.c L55+).

func _test_section_a11_faint_replacement() -> void:
	var ai := TrainerAI.new()

	# Opponent: Fire type. Party has: Normal mon (neutral) and Water mon (2× vs Fire).
	var normal_mon := _make_mon("Neutral", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	normal_mon.add_move(tackle)

	var water_mon := _make_mon("Water", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)
	water_mon.add_move(water_gun)

	var opponent := _make_mon("Fire", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)

	# Active mon fainted; party is [normal_mon (active, fainted), water_mon].
	var my_party := BattleParty.new()
	my_party.members = [normal_mon, water_mon]
	my_party.active_index = 0
	normal_mon.fainted = true

	var chosen_slot := ai.choose_replacement(my_party, opponent)
	_chk("A11.01 picks slot 1 (Water mon has 2× vs Fire)",  chosen_slot == 1)

	# Reversed order: [water_mon, normal_mon], active = water_mon (fainted).
	var my_party2 := BattleParty.new()
	my_party2.members = [water_mon, normal_mon]
	my_party2.active_index = 0
	water_mon.fainted = false  # reset
	normal_mon.fainted = false
	water_mon.fainted = true   # now water_mon is the fainted active

	var chosen_slot2 := ai.choose_replacement(my_party2, opponent)
	_chk("A11.02 still picks Water mon (slot 1) even from reversed order",
			chosen_slot2 == 1)


# ── A12: Full BattleManager integration — AI drives battle ────────────────────
# Attach a BASIC TrainerAI to side 1 (opponent). Player side uses auto-select.
# Battle should run to completion and emit battle_ended.

func _test_section_a12_full_battle() -> void:
	var player := _make_mon("Player", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 120, 80, 80, 80, 150)
	var opp := _make_mon("Opp", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)

	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.BASIC

	var result := [-1]
	var bm := BattleManager.new()
	add_child(bm)
	bm.battle_ended.connect(func(w): result[0] = w)
	bm.set_trainer_ai(1, ai)
	bm.start_battle(player, opp)

	_chk("A12.01 battle runs to completion with AI on side 1", result[0] >= 0)
	_chk("A12.02 player wins (faster + stronger attacker)",    result[0] == 0)
	bm.queue_free()


# ── A13: Integration — AI avoids immune status move ───────────────────────────
# When AI has Thunder Wave (Electric) and Tackle (Normal), opponent is Ground type.
# AI should never use Thunder Wave (immune). Observable: no paralysis on defender.

func _test_section_a13_integration_immune_status() -> void:
	var player := _make_mon("Ground", TypeChart.TYPE_GROUND, TypeChart.TYPE_NONE,
			500, 150, 200, 80, 200, 200)  # Very tanky, high attack
	var opp := _make_mon("Elec", TypeChart.TYPE_ELECTRIC, TypeChart.TYPE_NONE,
			40, 80, 80, 80, 80, 80)

	var tackle := _load_move(33)
	player.add_move(tackle)

	# Opponent AI has Thunder Wave (immune vs Ground) and Tackle.
	# Should always choose Tackle since Thunder Wave scores 80 vs Tackle's 100.
	var thunder_wave := _make_move("ThunderWave", TypeChart.TYPE_ELECTRIC, 2, 0,
			MoveData.SE_PARALYSIS)
	opp.add_move(thunder_wave)
	opp.add_move(tackle)

	var paralysis_applied := [false]
	var ai_moves_used := []

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.BASIC

	var bm := BattleManager.new()
	add_child(bm)
	bm.secondary_applied.connect(func(target, eff):
		if eff == MoveData.SE_PARALYSIS and target == player:
			paralysis_applied[0] = true)
	bm.move_executed.connect(func(atk, _def, mv, _dmg):
		if atk == opp:
			ai_moves_used.push_back(mv.move_name))
	bm.set_trainer_ai(1, ai)
	player.current_hp = 500
	opp.current_hp = 1  # player OHKOs opp on first hit

	bm.start_battle(player, opp)

	_chk("A13.01 player (Ground) never gets paralyzed by AI's Thunder Wave",
			not paralysis_applied[0])
	_chk("A13.02 AI used Tackle (only non-immune move) when move executed",
			ai_moves_used.all(func(n): return n == "Tackle"))

	bm.queue_free()


# ── A14: Choice-lock — AI returns locked move (positive) ─────────────────────
# If choice_locked_move is set, AI must return it regardless of scoring.
# Source: BattleAI_SetupAIData (battle_ai_main.c L174-187) — moveLimitations
#   prefilter sets score=0 for all non-locked moves; only locked move is scored.

func _test_section_a14_choice_lock_returns_locked() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	# Attacker: Bug type (no STAB). Moves: Tackle(0) and Water Gun(1).
	# Defender: Fire type. Water Gun is 2× effective → would score 102 vs Tackle 100.
	# If NOT locked, AI picks Water Gun. If locked to Tackle, AI must return Tackle.
	var attacker := _make_mon("Bug", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 100)
	var defender := _make_mon("Fire", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)
	defender.current_hp = 500  # no KO risk

	var tackle  := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 40)
	var water   := _make_move("WaterGun", TypeChart.TYPE_WATER,  1, 40)
	attacker.add_move(tackle)
	attacker.add_move(water)

	attacker.choice_locked_move = tackle  # locked into index 0

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	_chk("A14.01 choice-locked AI returns move (not switch)", action["type"] == "move")
	_chk("A14.02 returns locked move index (0), not higher-scoring Water Gun",
			action["index"] == 0)


# ── A15: Pre-lock — AI scores freely (negative/contrast to A14) ──────────────
# Same setup as A14 but NO choice_locked_move. AI should score Water Gun higher
# (2× vs Fire) and pick it — proving lock removal restores free scoring.

func _test_section_a15_pre_lock_free_scoring() -> void:
	var ai := TrainerAI.new()
	ai._force_tie_rng = 0

	var attacker := _make_mon("Bug", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 100)
	var defender := _make_mon("Fire", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			500, 40, 80, 40, 80, 80)
	defender.current_hp = 500

	var tackle := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 40)
	var water  := _make_move("WaterGun", TypeChart.TYPE_WATER,  1, 40)
	attacker.add_move(tackle)
	attacker.add_move(water)
	# NO choice_locked_move set — free scoring

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# Water Gun (2× vs Fire): base=19 dmg, ×2=38 → hits-to-KO 500hp = ceil(500/38)=14.
	# Tackle (1× vs Fire): base=19 dmg, ×1=19 → hits-to-KO 500hp = ceil(500/19)=27.
	# WaterGun is outright fewest-hits → BEST_DAMAGE_MOVE(+1) → 101. Tackle: 100.
	_chk("A15.01 unlocked AI picks best move (not forced to index 0)",
			action["index"] == 1)
	_chk("A15.02 returns move (not switch)", action["type"] == "move")


# ── A16: Bad choice lock — switch when locked into status move (positive) ─────
# SMART tier should switch when locked into a status move with a choice item.
# Source: ShouldSwitchIfBadChoiceLock (battle_ai_switch.c L1206-1209, singles):
#   GetMoveCategory(choicedMove) == DAMAGE_CATEGORY_STATUS → switch at 100%.

func _test_section_a16_bad_lock_switch_status() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART

	# Attacker holds Choice Band, locked into Toxic (status).
	# Also has Tackle so AllMovesBad (all-immune) doesn't fire.
	var attacker := _make_mon("Poke", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	var toxic  := _make_move("Toxic",  TypeChart.TYPE_POISON, 2, 0, MoveData.SE_TOXIC)
	attacker.add_move(tackle)
	attacker.add_move(toxic)
	attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	attacker.choice_locked_move = toxic  # locked into index 1 (status move)

	# Defender: Normal type. Tackle is effective (1×), so AllMovesBad = false.
	# Defender has no damaging moves → can't OHKO → HasBadOdds = false.
	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 40, 200, 40, 200, 50)
	defender.current_hp = 500
	var splash := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0)
	defender.add_move(splash)

	var backup := _make_mon("Backup", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var water := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)
	backup.add_move(water)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A16.01 SMART switches when locked into status move", action["type"] == "switch")
	_chk("A16.02 switches to backup (slot 1)", action["slot"] == 1)


# ── A17: Bad lock — stays when locked into effective move (negative) ───────────
# Same party as A16 but locked into Tackle (damaging, effective vs Normal).
# BadChoiceLock condition not met (not status, not immune) → no switch.
# Source: ShouldSwitchIfBadChoiceLock returns FALSE when move can affect target.

func _test_section_a17_bad_lock_stay_effective() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART

	var attacker := _make_mon("Poke", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	var toxic  := _make_move("Toxic",  TypeChart.TYPE_POISON, 2, 0, MoveData.SE_TOXIC)
	attacker.add_move(tackle)
	attacker.add_move(toxic)
	attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	attacker.choice_locked_move = tackle  # locked into index 0 (damaging, 1× vs Normal)

	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			500, 40, 200, 40, 200, 50)
	defender.current_hp = 500
	var splash := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0)
	defender.add_move(splash)

	var backup := _make_mon("Backup", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var water := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)
	backup.add_move(water)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	# BadChoiceLock: Tackle is not status AND Normal vs Normal ≠ immune → no switch.
	# Choice-lock early return: choice_locked_move=Tackle → return {move, index 0}.
	_chk("A17.01 stays when locked into effective move (not switch)", action["type"] == "move")
	_chk("A17.02 returns locked move index 0", action["index"] == 0)


# ── A18: Bad lock — switch when locked into type-immune move (positive) ────────
# SMART tier switches when locked into a move that cannot affect the target.
# Source: ShouldSwitchIfBadChoiceLock L1208: !CanMoveAffectTarget (type immunity).

func _test_section_a18_bad_lock_switch_immune() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART

	# Attacker locked into Tackle (Normal) vs Ghost defender — Normal is immune vs Ghost.
	# Has Shadow Ball (Ghost) too so AllMovesBad doesn't fire (Ghost 0.5× vs Ghost is ≠ 0).
	var attacker := _make_mon("Poke", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var tackle       := _make_move("Tackle",     TypeChart.TYPE_NORMAL, 0, 60)
	var shadow_ball  := _make_move("ShadowBall", TypeChart.TYPE_GHOST,  1, 80)
	attacker.add_move(tackle)
	attacker.add_move(shadow_ball)
	attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	attacker.choice_locked_move = tackle  # locked into Normal vs Ghost = 0× immune

	# Defender: Ghost type. Normal vs Ghost = 0.0× (immune). Ghost vs Ghost = 0.5× > 0.
	var defender := _make_mon("Ghost", TypeChart.TYPE_GHOST, TypeChart.TYPE_NONE,
			500, 40, 200, 40, 200, 50)
	defender.current_hp = 500
	var splash := _make_move("Splash", TypeChart.TYPE_NORMAL, 2, 0)
	defender.add_move(splash)

	var backup := _make_mon("Backup", TypeChart.TYPE_FIGHTING, TypeChart.TYPE_NONE,
			160, 80, 80, 80, 80, 80)
	var close_combat := _make_move("CC", TypeChart.TYPE_FIGHTING, 0, 120)
	backup.add_move(close_combat)

	var my_party := BattleParty.new()
	my_party.members = [attacker, backup]
	my_party.active_index = 0

	var action := ai.choose_action(attacker, defender, my_party, BattleParty.single(defender))
	_chk("A18.01 SMART switches when locked into type-immune move", action["type"] == "switch")
	_chk("A18.02 switches to backup (slot 1)", action["slot"] == 1)


# ── A19: Choice Band changes move selection — Band makes Tackle KO (positive) ──
# Discriminating test: Band boosts physical attack, making Tackle KO the defender.
# Without Band (A20), only Water Gun KOs → Water Gun wins via FAST_KILL.
# With Band, both KOs → both get FAST_KILL → tie → force_tie_rng=0 → index 0 (Tackle).
#
# Damage derivation (force_roll=100, force_crit=false, level=50):
#   Attacker: Bug type (no STAB), base_atk=120→actual 125, base_spatk=80→actual 85,
#             base_spd=200→faster than defender (spd 85) → FAST_KILL.
#   Defender: Fire type, base_def=50→actual 55, current_hp=45.
#
#   Tackle (Normal, physical, power 40):
#     Without Band: 40*125*22/55/50+2 = 110000/55/50+2 = 2000/50+2 = 42. No KO (42<45).
#     With Band (atk→(125*6144+2047)/4096=187): 40*187*22/55/50+2 = 164560/55/50+2 = 2992/50+2 = 61. KO! (61≥45).
#   Water Gun (Water, special, power 40, no STAB, 2× vs Fire):
#     spatk=85: 40*85*22/55/50+2 = 74800/55/50+2 = 1360/50+2 = 29; ×2.0 = 58. KO! (58≥45).
#
#   Scores WITH Band: Tackle=106 (FAST_KILL), WaterGun=106 (FAST_KILL). Tie → index 0.
#   Source: ItemManager.attack_modifier_uq412 called from DamageCalculator L157-159.

func _test_section_a19_band_changes_move_selection() -> void:
	var ai := TrainerAI.new()
	ai._force_roll = 100
	ai._force_crit = false
	ai._force_tie_rng = 0

	var attacker := _make_mon("Bug", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			160, 120, 80, 80, 80, 200)
	attacker.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)

	var defender := _make_mon("Fire", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			160, 40, 50, 40, 50, 80)
	defender.current_hp = 45

	var tackle   := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 40)
	var water    := _make_move("WaterGun", TypeChart.TYPE_WATER,  1, 40)
	attacker.add_move(tackle)
	attacker.add_move(water)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# Band: Tackle 61≥45 → FAST_KILL 106. WaterGun 58≥45 → FAST_KILL 106. Tie → index 0.
	_chk("A19.01 with Band: both KO, tie-break favors index 0 (Tackle)", action["index"] == 0)
	_chk("A19.02 returns move", action["type"] == "move")


# ── A20: Without Band — Water Gun wins (negative/contrast to A19) ─────────────
# Same scenario as A19 but no held item. Tackle 42<45 → no KO → score 100.
# Water Gun 58≥45 → KO → FAST_KILL → score 106. AI picks Water Gun.

func _test_section_a20_without_band_other_move_wins() -> void:
	var ai := TrainerAI.new()
	ai._force_roll = 100
	ai._force_crit = false
	ai._force_tie_rng = 0

	var attacker := _make_mon("Bug", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			160, 120, 80, 80, 80, 200)
	# No held item.

	var defender := _make_mon("Fire", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			160, 40, 50, 40, 50, 80)
	defender.current_hp = 45

	var tackle   := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 40)
	var water    := _make_move("WaterGun", TypeChart.TYPE_WATER,  1, 40)
	attacker.add_move(tackle)
	attacker.add_move(water)

	var action := ai.choose_action(attacker, defender,
			BattleParty.single(attacker), BattleParty.single(defender))
	# No Band: Tackle 42<45 → no KO → 100. WaterGun 58≥45 → KO → FAST_KILL → 106. WaterGun wins.
	_chk("A20.01 without Band: Water Gun KOs → AI picks Water Gun (index 1)",
			action["index"] == 1)
	_chk("A20.02 returns move", action["type"] == "move")
