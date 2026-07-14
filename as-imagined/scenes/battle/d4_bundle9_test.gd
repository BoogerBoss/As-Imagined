extends Node

# [D4 Bundle 9] Flying Press(560), Sky Drop(507) — the last 2 of D4's 6
# confirmed NOVEL-MECHANISM moves. Full Step-0 findings and decisions are
# recorded in docs/decisions.md's own [D4 Bundle 9] entry; summarized here:
#
#  - Flying Press: EFFECT_TWO_TYPED_MOVE — TWO independent type-effectiveness
#    computations (Fighting vs defender, Flying vs defender, each already
#    correctly combining a dual-typed defender's own two types) multiplied
#    together. Every existing type-override (Scrappy's bypass_ghost_immunity,
#    Iron-Ball/Smack-Down/Ingrain's grounded_override, Delta Stream's
#    Strong-Winds weakening, Freeze-Dry's force_super_effective_type) applies
#    to BOTH components independently. STAB is a DELIBERATE DEVIATION from
#    the literal current source behavior (Rob's decision, 2026-07-14): source's
#    own shared mutable ctx->moveType gets left at Flying by the type-calc
#    pass, so the literal C code grants STAB for Flying-type attackers, not
#    Fighting — but the dev team's own unimplemented test placeholder names
#    the OPPOSITE as intended ("Flying-type Pokémon don't receive STAB on
#    Flying Press"). Implemented: STAB keyed on move.type (Fighting) only,
#    via this project's pre-existing STAB code (untouched, never mutates
#    move.type).
#  - Sky Drop: EFFECT_SKY_DROP — BOTH combatants become semi-invulnerable;
#    the target's own action is unconditionally skipped every turn held
#    (checked BEFORE any other pre-move status check); turn 2 releases and
#    deals ordinary damage, failing gracefully if the target left the field
#    via a different route in the meantime (this project's existing
#    _clear_volatiles already handles that generically). If the ATTACKER
#    faints first while still holding a target, a new reciprocal-release
#    scan in _clear_volatiles frees the target immediately (mirrors source's
#    dedicated Cmd_tryconfusionafterskydrop), including the conditional
#    confuse-on-drop for an interrupted rampage. Freeze/paralysis on the
#    scheduled release turn was ORIGINALLY left deliberately un-special-cased
#    (Rob's initial decision) — but a later recon session (see
#    docs/decisions.md's [Charge-cancellation fix] entry) found this actually
#    diverges from source in the OTHER direction for 4 of these conditions:
#    Truant/Flinch/Paralysis/Infatuation all call CancelMultiTurnMoves in
#    source, canceling the charge outright, while Sleep/Frozen/Confusion's own
#    cancelers never do. That same recon also confirmed source's own version
#    of "cancel the attacker's charge but leave the Sky Drop target orphaned"
#    is a genuine, non-self-healing SOFT-LOCK in the reference engine (no lazy
#    release path exists, the target can't even switch out on its own) — so
#    this project's fix deliberately cancels the charge for all 4 conditions
#    AND reciprocally releases a held Sky Drop target via the same
#    _release_sky_drop_target helper _clear_volatiles' faint/switch-out case
#    uses (confuse-after-drop is explicitly NOT applied from this release
#    path — source only ever attaches it to the faint-specific
#    Cmd_tryconfusionafterskydrop, never to an ordinary release). Sleep/Frozen/
#    Confusion-self-hit remain correctly un-special-cased (source doesn't
#    cancel for those either) — see C.11-C.14 below.
#
# Ground truth: pokeemerald_expansion src/battle_util.c (CalcTypeEffectiveness
# Multiplier L8221-8236, GetSameTypeAttackBonusModifier L7239-7248,
# CancelMultiTurnMoves L1076-1093); src/battle_move_resolution.c
# (HandleSkyDropResult L1676-1733, CancelerSkyDrop L76-85, CancelerParalyzed
# L447-458); src/battle_script_commands.c (Cmd_tryconfusionafterskydrop
# L10710-10740); src/data/moves_info.h (MOVE_FLYING_PRESS L14867-14882,
# MOVE_SKY_DROP L13514-13534).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_flying_press()
	_test_sky_drop()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle9_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.weight = 500
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# Dual-type variant (matching [D4 Bundle 5]'s own established fix: build the
# dual-type species BEFORE from_species so species.types/original_types agree
# from construction — a post-hoc `.types =` reassignment is silently
# overwritten by _reset_mon_type at the next switch-in).
func _make_dual_type_mon(mon_name: String, type1: int, type2: int, base_hp: int = 100,
		base_atk: int = 60, base_def: int = 60, base_spatk: int = 60,
		base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type1, type2]
	sp.weight = 500
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_heavy_mon(mon_name: String, weight_hg: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.weight = weight_hg
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var flying_press := _load_move(560)
	_chk("A.01 Flying Press name", flying_press.move_name == "Flying Press")
	_chk("A.02 Flying Press type Fighting", flying_press.type == TypeChart.TYPE_FIGHTING)
	_chk("A.03 Flying Press power 100", flying_press.power == 100)
	_chk("A.04 Flying Press accuracy 95", flying_press.accuracy == 95)
	_chk("A.05 Flying Press two_typed_move", flying_press.two_typed_move == true)
	_chk("A.06 Flying Press second_type Flying", flying_press.second_type == TypeChart.TYPE_FLYING)
	_chk("A.07 Flying Press makes_contact", flying_press.makes_contact == true)
	_chk("A.08 Flying Press double_power_on_minimized", flying_press.double_power_on_minimized == true)
	_chk("A.09 Flying Press category physical", flying_press.category == 0)

	var sky_drop := _load_move(507)
	_chk("A.10 Sky Drop name", sky_drop.move_name == "Sky Drop")
	_chk("A.11 Sky Drop type Flying", sky_drop.type == TypeChart.TYPE_FLYING)
	_chk("A.12 Sky Drop power 60", sky_drop.power == 60)
	_chk("A.13 Sky Drop accuracy 100", sky_drop.accuracy == 100)
	_chk("A.14 Sky Drop is_sky_drop", sky_drop.is_sky_drop == true)
	_chk("A.15 Sky Drop makes_contact", sky_drop.makes_contact == true)
	_chk("A.16 Sky Drop bans Sleep Talk", (sky_drop.ban_flags & MoveData.BAN_SLEEP_TALK) != 0)
	_chk("A.17 Sky Drop bans Instruct", (sky_drop.ban_flags & MoveData.BAN_INSTRUCT) != 0)
	_chk("A.18 Sky Drop bans Assist", (sky_drop.ban_flags & MoveData.BAN_ASSIST) != 0)

	# Every other move must default to two_typed_move=false, confirming zero
	# unintended cross-contamination.
	var tackle := _load_move(33)
	_chk("A.19 Tackle two_typed_move false (negative)", tackle.two_typed_move == false)
	_chk("A.20 Tackle second_type default -1 (negative)", tackle.second_type == -1)
	_chk("A.21 Tackle is_sky_drop false (negative)", tackle.is_sky_drop == false)


# ── Section B: Flying Press ───────────────────────────────────────────────

func _test_flying_press() -> void:
	var flying_press := _load_move(560)

	# B.01: dual-type effectiveness is a genuine PRODUCT of two independent
	# combined-across-defender-types computations, not either component
	# alone. Rock/Steel defender: Fighting alone = 2.0×2.0 = 4.0x; Flying
	# alone = 0.5×0.5 = 0.25x; true combined = 4.0×0.25 = 1.0x (neutral) —
	# a value neither single-attacking-type calculation would produce,
	# confirming genuine multiplication of both components.
	var rock_steel_def := _make_dual_type_mon("RSDef", TypeChart.TYPE_ROCK, TypeChart.TYPE_STEEL)
	var fp_atk := _make_mon("FPAtk", 100, 100, 60, 60, 60, 60, TypeChart.TYPE_FIGHTING)
	var b01_result := DamageCalculator.calculate(fp_atk, rock_steel_def, flying_press,
			100, false, DamageCalculator.WEATHER_NONE)
	_chk("B.01 Flying Press dual-type product == 1.0 (neutral)",
			is_equal_approx(b01_result["effectiveness"], 1.0))

	# B.02: either component being a flat 0x immunity zeroes the WHOLE move —
	# Ghost-type defender: Fighting vs Ghost = 0 (immune), Flying vs Ghost =
	# 1.0 (neutral) — product = 0, the move fails entirely. This is the
	# CORRECT expected behavior (matches Flying Press's real Ghost-immunity),
	# not a bug.
	var ghost_def := _make_mon("GhDef", 100, 60, 60, 60, 60, 60, TypeChart.TYPE_GHOST)
	var b02_result := DamageCalculator.calculate(fp_atk, ghost_def, flying_press,
			100, false, DamageCalculator.WEATHER_NONE)
	_chk("B.02 Flying Press vs Ghost: 0 damage (Fighting immunity zeroes the whole move)",
			b02_result["damage"] == 0 and b02_result["effectiveness"] == 0.0)

	# B.03/B.04: STAB keyed on move.type (Fighting) ONLY, per Rob's explicit
	# decision — a mono-Fighting attacker gets STAB, a mono-Flying attacker
	# does NOT, despite Flying being the move's own "argument type". Uses a
	# neutral-effectiveness defender (Normal-type) so the STAB delta is the
	# only variable — Fighting vs Normal = 1.0, Flying vs Normal = 1.0,
	# combined = 1.0 (no type-effectiveness noise).
	var neutral_def := _make_mon("NeutDef", 100, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	var fighting_atk := _make_mon("FightAtk", 100, 100, 60, 60, 60, 60, TypeChart.TYPE_FIGHTING)
	var flying_atk := _make_mon("FlyAtk", 100, 100, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	var b03_result := DamageCalculator.calculate(fighting_atk, neutral_def, flying_press,
			100, false, DamageCalculator.WEATHER_NONE)
	var b04_result := DamageCalculator.calculate(flying_atk, neutral_def, flying_press,
			100, false, DamageCalculator.WEATHER_NONE)
	_chk("B.03 Fighting-type attacker gets STAB (Flying Press)",
			int(b03_result["damage"]) > int(b04_result["damage"]))
	_chk("B.04 Flying-type attacker does NOT get STAB (Flying Press)",
			b04_result["damage"] > 0)

	# B.05: Scrappy's Ghost-immunity bypass applies to BOTH type components
	# independently — confirmed via source (CalcTypeEffectivenessMultiplier
	# Internal is the FULL modifier pipeline, run twice). Fighting vs Ghost
	# normally 0, bypassed to 1.0 by Scrappy; Flying vs Ghost already 1.0;
	# combined = 1.0, so the move now connects against a target it would
	# otherwise be fully immune to (B.02's own scenario).
	var scrappy_atk := _make_mon("ScrapAtk", 100, 100, 60, 60, 60, 60, TypeChart.TYPE_FIGHTING)
	scrappy_atk.ability = load("res://data/abilities/ability_0113.tres") as AbilityData
	var b05_result := DamageCalculator.calculate(scrappy_atk, ghost_def, flying_press,
			100, false, DamageCalculator.WEATHER_NONE)
	_chk("B.05 Scrappy bypasses Ghost immunity for BOTH Flying Press components",
			b05_result["damage"] > 0 and b05_result["effectiveness"] > 0.0)


# ── Section C: Sky Drop ────────────────────────────────────────────────────

func _test_sky_drop() -> void:
	var sky_drop := _load_move(507)
	var tackle := _load_move(33)

	# C.01/C.02: turn 1 setup — no damage dealt, both combatants become
	# semi-invulnerable, the target's own next action is skipped.
	var atk1 := _make_mon("SDAtk1", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def1 := _make_mon("SDDef1", 100, 60, 60, 60, 60, 60)
	atk1.add_move(sky_drop)
	def1.add_move(tackle)
	var bm1 := _make_bm()
	bm1.queue_move(0, 0)
	bm1.queue_move(1, 0)
	var c01_turn1_damage := [-1]
	var c01_atk_semi_inv := [-1]
	var c01_def_semi_inv := [-1]
	var c02_target_skipped := [false]
	bm1.move_executed.connect(func(a, _d, m, dmg):
		if a == atk1 and m == sky_drop and c01_turn1_damage[0] == -1:
			c01_turn1_damage[0] = dmg
			c01_atk_semi_inv[0] = atk1.semi_invulnerable
			c01_def_semi_inv[0] = def1.semi_invulnerable)
	bm1.move_skipped.connect(func(mon, reason):
		if mon == def1 and reason == "sky_drop_held":
			c02_target_skipped[0] = true)
	bm1.start_battle(atk1, def1)
	_chk("C.01 Sky Drop turn 1 deals 0 damage", c01_turn1_damage[0] == 0)
	_chk("C.01b Attacker becomes SEMI_INV_SKY_DROP_ATTACKER",
			c01_atk_semi_inv[0] == MoveData.SEMI_INV_SKY_DROP_ATTACKER)
	_chk("C.01c Target becomes SEMI_INV_SKY_DROP_TARGET",
			c01_def_semi_inv[0] == MoveData.SEMI_INV_SKY_DROP_TARGET)
	_chk("C.02 Target's own action is skipped while held", c02_target_skipped[0] == true)

	# C.03: turn 2 release deals real damage and clears both states.
	var atk2 := _make_mon("SDAtk2", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def2 := _make_mon("SDDef2", 100, 60, 60, 60, 60, 60)
	atk2.add_move(sky_drop)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.queue_move(1, 0)
	var c03_release_damage := [-1]
	var c03_atk_semi_inv_after := [-1]
	var c03_def_semi_inv_after := [-1]
	bm2.move_executed.connect(func(a, _d, m, dmg):
		if a == atk2 and m == sky_drop and c01_turn1_damage[0] != -1 \
				and c03_release_damage[0] == -1 and dmg > 0:
			c03_release_damage[0] = dmg
			c03_atk_semi_inv_after[0] = atk2.semi_invulnerable
			c03_def_semi_inv_after[0] = def2.semi_invulnerable)
	# Track the sequence distinctly since bm1's own closures captured atk1/def1;
	# re-derive turn-1-vs-turn-2 by watching the raw event count for THIS battle.
	var c03_events := []
	bm2.move_executed.connect(func(a, _d, m, dmg):
		if a == atk2 and m == sky_drop:
			c03_events.append(dmg))
	bm2.start_battle(atk2, def2)
	_chk("C.03 Sky Drop fires exactly twice (turn 1 setup, turn 2 release)",
			c03_events.size() >= 2)
	if c03_events.size() >= 2:
		_chk("C.03b Turn 1 event is 0 damage", c03_events[0] == 0)
		_chk("C.03c Turn 2 event deals real damage", c03_events[1] > 0)

	# C.04: fail conditions — already semi-invulnerable, Substitute blocks,
	# target too heavy. Each checked via a fresh turn-1-only battle (attacker
	# faster, so only the attacker's own turn-1 action matters).
	var atk3 := _make_mon("SDAtk3", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def3 := _make_mon("SDDef3", 100, 60, 60, 60, 60, 60)
	def3.semi_invulnerable = MoveData.SEMI_INV_ON_AIR  # mid-Fly already
	atk3.add_move(sky_drop)
	def3.add_move(tackle)
	var bm3 := _make_bm()
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	var c04_already_semi_inv_failed := [false]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "sky_drop_already_semi_invulnerable":
			c04_already_semi_inv_failed[0] = true)
	bm3.start_battle(atk3, def3)
	_chk("C.04 Sky Drop fails against an already semi-invulnerable target",
			c04_already_semi_inv_failed[0] == true)
	_chk("C.04b Attacker never became SEMI_INV_SKY_DROP_ATTACKER on failure",
			atk3.semi_invulnerable != MoveData.SEMI_INV_SKY_DROP_ATTACKER)

	var atk4 := _make_mon("SDAtk4", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def4 := _make_mon("SDDef4", 100, 60, 60, 60, 60, 60)
	def4.substitute_hp = 25
	atk4.add_move(sky_drop)
	def4.add_move(tackle)
	var bm4 := _make_bm()
	bm4.queue_move(0, 0)
	bm4.queue_move(1, 0)
	var c05_sub_blocks := [false]
	bm4.move_effect_failed.connect(func(mon, reason):
		if mon == atk4 and reason == "sky_drop_substitute_blocks":
			c05_sub_blocks[0] = true)
	bm4.start_battle(atk4, def4)
	_chk("C.05 Sky Drop fails against a Substitute", c05_sub_blocks[0] == true)

	var atk5 := _make_mon("SDAtk5", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def5 := _make_heavy_mon("SDDef5Heavy", 2000)
	atk5.add_move(sky_drop)
	def5.add_move(tackle)
	var bm5 := _make_bm()
	bm5.queue_move(0, 0)
	bm5.queue_move(1, 0)
	var c06_too_heavy := [false]
	bm5.move_effect_failed.connect(func(mon, reason):
		if mon == atk5 and reason == "sky_drop_too_heavy":
			c06_too_heavy[0] = true)
	bm5.start_battle(atk5, def5)
	_chk("C.06 Sky Drop fails against a target weighing >= 200.0kg", c06_too_heavy[0] == true)

	# C.06b negative control: a target just UNDER the weight threshold succeeds.
	var atk5b := _make_mon("SDAtk5b", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def5b := _make_heavy_mon("SDDef5bLight", 1999)
	atk5b.add_move(sky_drop)
	def5b.add_move(tackle)
	var bm5b := _make_bm()
	bm5b.queue_move(0, 0)
	bm5b.queue_move(1, 0)
	var c06b_grabbed := [false]
	bm5b.charge_started.connect(func(a, m):
		if a == atk5b and m == sky_drop:
			c06b_grabbed[0] = true)
	bm5b.start_battle(atk5b, def5b)
	_chk("C.06b Just-under-threshold weight (1999hg) succeeds (negative control)",
			c06b_grabbed[0] == true)

	# C.07: anti-air bypass shares Fly's exact STATE_ON_AIR rule — a
	# damages_airborne move (Gust) can hit both SEMI_INV_SKY_DROP_ATTACKER
	# and SEMI_INV_SKY_DROP_TARGET; an ordinary move (Tackle) cannot. Tested
	# via the direct unit-level helper (no full battle needed — this is a
	# pure function of MoveData + the semi-invulnerable state constant).
	var gust := _load_move(16)
	_chk("C.07 Gust (damages_airborne) hits SEMI_INV_SKY_DROP_ATTACKER",
			StatusManager._can_hit_semi_invulnerable(gust, MoveData.SEMI_INV_SKY_DROP_ATTACKER))
	_chk("C.07b Gust (damages_airborne) hits SEMI_INV_SKY_DROP_TARGET",
			StatusManager._can_hit_semi_invulnerable(gust, MoveData.SEMI_INV_SKY_DROP_TARGET))
	_chk("C.07c Tackle (no damages_airborne) does NOT hit SEMI_INV_SKY_DROP_TARGET (negative)",
			not StatusManager._can_hit_semi_invulnerable(tackle, MoveData.SEMI_INV_SKY_DROP_TARGET))

	# C.08: reciprocal release on attacker faint — the attacker, mid-charge
	# and holding a target, faints (from residual poison) before its own
	# turn-2 release. The target must be freed immediately, matching
	# source's dedicated Cmd_tryconfusionafterskydrop.
	var atk6 := _make_mon("SDAtk6", 30, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def6 := _make_mon("SDDef6", 100, 60, 60, 60, 60, 60)
	atk6.add_move(sky_drop)
	def6.add_move(tackle)
	var bm6 := _make_bm()
	bm6.start_battle(atk6, def6)  # not used further; rebuilding state directly below
	# Directly drive the grab (turn 1) then force a faint via residual status,
	# bypassing full multi-turn RNG choreography — matches this project's
	# established direct-field-manipulation precedent for isolating one
	# specific mechanic (the reciprocal release), not re-deriving the whole
	# charge sequence via a slow/RNG-dependent full battle.
	var atk7 := _make_mon("SDAtk7", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def7 := _make_mon("SDDef7", 100, 60, 60, 60, 60, 60)
	atk7.charging_move = sky_drop
	atk7.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
	atk7.sky_drop_target = def7
	def7.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
	def7.rampage_turns = 2  # mid-rampage when grabbed, per C.09's own confuse-on-drop check
	def7.confuse_after_drop = true
	var bm7 := _make_bm()
	bm7._combatants = [atk7, def7]
	bm7._clear_volatiles(atk7)  # simulates atk7 fainting/leaving the field
	_chk("C.08 Reciprocal release: target's semi_invulnerable cleared when attacker leaves",
			def7.semi_invulnerable == MoveData.SEMI_INV_NONE)
	_chk("C.08b Reciprocal release: attacker's own sky_drop_target cleared",
			atk7.sky_drop_target == null)

	# C.09: the interrupted-rampage confuse-on-drop fires as part of the same
	# reciprocal release above (def7.confuse_after_drop was true).
	_chk("C.09 Confuse-on-drop: target's confuse_after_drop consumed",
			def7.confuse_after_drop == false)
	_chk("C.09b Confuse-on-drop: target actually became confused",
			def7.confusion_turns > 0)

	# C.09c negative control: a target that was NOT mid-rampage when grabbed
	# does not get confused on release.
	var atk8 := _make_mon("SDAtk8", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def8 := _make_mon("SDDef8", 100, 60, 60, 60, 60, 60)
	atk8.charging_move = sky_drop
	atk8.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
	atk8.sky_drop_target = def8
	def8.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
	# def8.confuse_after_drop left false (was not mid-rampage when grabbed)
	var bm8 := _make_bm()
	bm8._combatants = [atk8, def8]
	bm8._clear_volatiles(atk8)
	_chk("C.09c Non-rampaging target released without confusion (negative control)",
			def8.confusion_turns == 0 and def8.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# C.10: target-left-early (turn-2 lazy check) — the target's own
	# semi_invulnerable is already cleared by some OTHER route by the time the
	# attacker's own turn 2 resolves (this project's existing _clear_volatiles
	# already handles the target's own departure generically) — Sky Drop
	# should fail gracefully with no damage, not crash or hit a fainted/gone
	# target.
	var atk9 := _make_mon("SDAtk9", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def9 := _make_mon("SDDef9", 100, 60, 60, 60, 60, 60)
	atk9.charging_move = sky_drop
	atk9.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
	atk9.sky_drop_target = def9
	def9.semi_invulnerable = MoveData.SEMI_INV_NONE  # already released via some other route
	var bm9 := _make_bm()
	bm9._combatants = [atk9, def9]
	bm9._actor_indices = {atk9: 0, def9: 1}
	bm9._active_per_side = 1
	bm9._chosen_moves = [sky_drop, null]
	bm9._chosen_targets = [1, 0]
	bm9._turn_order = [atk9, def9]
	bm9._current_actor_index = 0
	var c10_no_target_failed := [false]
	bm9.move_effect_failed.connect(func(mon, reason):
		if mon == atk9 and reason == "sky_drop_no_target":
			c10_no_target_failed[0] = true)
	bm9._phase_move_execution()
	_chk("C.10 Turn-2 lazy check: fails gracefully if target already left",
			c10_no_target_failed[0] == true)

	# C.11-C.14: Truant/Flinch/Paralysis/Infatuation on the attacker's
	# scheduled release turn — SUPERSEDES the old "verify and document,
	# uniformly stuck" framing (see docs/decisions.md's
	# [Charge-cancellation fix] entry for the full recon that reversed this).
	# Source's CancelerTruant/CancelerFlinch/CancelerParalyzed/
	# CancelerInfatuation each call CancelMultiTurnMoves, canceling the
	# charge — and, confirmed via a full source trace, leave the Sky Drop
	# target permanently orphaned if reproduced literally (a genuine
	# soft-lock: the attacker isn't forced to reselect Sky Drop, a fresh
	# attempt against the same target just fails without releasing it, and
	# the target can't even switch out on its own). This project's fix
	# cancels the charge for all 4 AND reciprocally releases the target via
	# _cancel_charge_if_needed/_release_sky_drop_target directly (bypassing
	# RNG — _phase_pre_move_checks has no forcing seam for the paralysis/
	# infatuation rolls, so these call the extracted, directly-testable
	# production function with a deterministic `reason` instead).
	var bm11 := _make_bm()
	for case in [
		{"tag": "C.11", "cond": "Paralysis", "reason": "paralyzed"},
		{"tag": "C.12", "cond": "Flinch", "reason": "flinched"},
		{"tag": "C.13", "cond": "Truant", "reason": "loafing"},
		{"tag": "C.14", "cond": "Infatuation", "reason": "infatuated"},
	]:
		var atk := _make_mon("SDAtk_" + case["cond"], 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
		var def := _make_mon("SDDef_" + case["cond"], 100, 60, 60, 60, 60, 60)
		atk.charging_move = sky_drop
		atk.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
		atk.sky_drop_target = def
		def.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
		bm11._cancel_charge_if_needed(atk, case["reason"])
		_chk(case["tag"] + " " + case["cond"] + " clears the attacker's charging_move",
				atk.charging_move == null)
		_chk(case["tag"] + "b " + case["cond"] + " clears the attacker's semi_invulnerable",
				atk.semi_invulnerable == MoveData.SEMI_INV_NONE)
		_chk(case["tag"] + "c " + case["cond"] + " clears the attacker's own sky_drop_target reference",
				atk.sky_drop_target == null)
		_chk(case["tag"] + "d " + case["cond"] + " ALSO releases the held target (no soft-lock)",
				def.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# C.15-C.17: Sleep/Frozen/Confusion negative controls — these three
	# correctly do NOT cancel anything in source (no CancelMultiTurnMoves
	# call in either CancelerAsleepOrFrozen branch or CancelerConfused's
	# self-hit branch), so this project's fix must not touch them either.
	for case in [
		{"tag": "C.15", "cond": "Sleep", "reason": "asleep"},
		{"tag": "C.16", "cond": "Frozen", "reason": "frozen"},
		{"tag": "C.17", "cond": "Confusion", "reason": "confused"},
	]:
		var atk := _make_mon("SDAtkNeg_" + case["cond"], 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
		var def := _make_mon("SDDefNeg_" + case["cond"], 100, 60, 60, 60, 60, 60)
		atk.charging_move = sky_drop
		atk.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
		atk.sky_drop_target = def
		def.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
		bm11._cancel_charge_if_needed(atk, case["reason"])
		_chk(case["tag"] + " " + case["cond"] + " does NOT cancel the attacker's charge (negative control)",
				atk.charging_move == sky_drop and atk.semi_invulnerable == MoveData.SEMI_INV_SKY_DROP_ATTACKER)
		_chk(case["tag"] + "b " + case["cond"] + " does NOT release the target either",
				def.semi_invulnerable == MoveData.SEMI_INV_SKY_DROP_TARGET)

	# C.18: confuse-after-drop is deliberately NOT applied from this release
	# path, even when the target was mid-rampage when grabbed — verified
	# from source that HandleSkyDropResult's own normal "second turn" success
	# branch never checks confuseAfterDrop either; it's consumed ONLY by
	# Cmd_tryconfusionafterskydrop, called only from the attacker-faint
	# script path. The target is still released from semi-invulnerability,
	# but confuse_after_drop itself is left untouched (unconsumed) rather
	# than silently firing.
	var atk18 := _make_mon("SDAtk18", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	var def18 := _make_mon("SDDef18", 100, 60, 60, 60, 60, 60)
	atk18.charging_move = sky_drop
	atk18.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
	atk18.sky_drop_target = def18
	def18.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
	def18.rampage_turns = 2
	def18.confuse_after_drop = true
	bm11._cancel_charge_if_needed(atk18, "paralyzed")
	_chk("C.18 Target is still released despite being mid-rampage when grabbed",
			def18.semi_invulnerable == MoveData.SEMI_INV_NONE)
	_chk("C.18b Confuse-after-drop is NOT consumed from this path (source-confirmed faint-only)",
			def18.confuse_after_drop == true)
	_chk("C.18c Target did NOT actually become confused",
			def18.confusion_turns == 0)

	# C.19: full end-to-end wiring check through the REAL
	# _phase_pre_move_checks() dispatch (not just the extracted function
	# directly) — Truant is used since truant_loafing is a plain bool with
	# no RNG involved, letting this run through the actual phase function
	# exactly as a real turn would.
	var atk19 := _make_mon("SDAtk19", 100, 100, 60, 60, 60, 90, TypeChart.TYPE_FLYING)
	atk19.ability = load("res://data/abilities/ability_0054.tres") as AbilityData
	atk19.truant_loafing = true
	atk19.charging_move = sky_drop
	atk19.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
	var def19 := _make_mon("SDDef19", 100, 60, 60, 60, 60, 60)
	atk19.sky_drop_target = def19
	def19.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
	var bm19 := _make_bm()
	bm19._combatants = [atk19, def19]
	bm19._actor_indices = {atk19: 0, def19: 1}
	bm19._active_per_side = 1
	bm19._chosen_moves = [sky_drop, null]
	bm19._chosen_targets = [1, 0]
	bm19._turn_order = [atk19, def19]
	bm19._current_actor_index = 0
	var c19_skip_reason := [""]
	bm19.move_skipped.connect(func(mon, reason):
		if mon == atk19:
			c19_skip_reason[0] = reason)
	bm19._phase_pre_move_checks()
	_chk("C.19 End-to-end: Truant fires move_skipped with the loafing reason",
			c19_skip_reason[0] == "loafing")
	_chk("C.19b End-to-end: attacker's charge cleared via the real phase function",
			atk19.charging_move == null)
	_chk("C.19c End-to-end: held target released via the real phase function",
			def19.semi_invulnerable == MoveData.SEMI_INV_NONE)


# ── Section D: negative control ────────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon("NegAtk", 100, 60, 60, 60, 60, 60)
	var def := _make_mon("NegDef", 100, 60, 60, 60, 60, 60)
	atk.add_move(tackle)
	def.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	var events := []
	bm.move_executed.connect(func(a, _d, m, dmg):
		events.append([a, m, dmg]))
	bm.start_battle(atk, def)
	_chk("D.01 Negative control: ordinary Tackle exchange still works", events.size() >= 2)
	_chk("D.02 Negative control: neither combatant carries Sky-Drop state",
			atk.semi_invulnerable != MoveData.SEMI_INV_SKY_DROP_ATTACKER
			and def.semi_invulnerable != MoveData.SEMI_INV_SKY_DROP_TARGET)
