extends Node

# [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS] — the last structured D1 cluster,
# closing out D1 entirely. 5 moves, individually re-verified at Step 0
# against a fresh brace-matched read of moves_info.h rather than assumed
# uniform:
#
#   Hex(506)             — STATUS_ARG_ANY (any non-volatile status)
#   Venoshock(474)        — STATUS_ARG_POISON_ANY (poison or toxic)
#   Smelling Salts(265)   — STATUS_PARALYSIS specifically; ALSO cures it on
#                           hit, UNLESS blocked by a live, non-ignored
#                           Substitute (a genuine, move-specific exception to
#                           the power-double itself, not just the cure)
#   Barb Barrage(767)     — STATUS_ARG_POISON_ANY; ALSO a 50% chance to
#                           poison the target (pure reuse of the existing
#                           generic secondary_effect/SE_POISON dispatch)
#   Infernal Parade(772)  — STATUS_ARG_ANY; ALSO a 30% chance to burn the
#                           target (pure reuse of SE_BURN)
#
# Comatose (`[M17n-11]`) holders are treated as having STATUS_SLEEP for the
# STATUS_ARG_ANY check specifically, matching source's own
# `(status1 | (STATUS1_SLEEP * isComatose)) & argStatus` — a real,
# currently-reachable interaction since Comatose already ships.
#
# Ordering: power is computed strictly BEFORE this same hit's own secondary
# effect (Barb Barrage's poison, Infernal Parade's burn) could apply a new
# status, by construction of this project's pipeline (`_dmg_power_override`
# runs in `_phase_move_execution`, before `_do_damaging_hit` is ever called).
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h (MOVE_HEX
# L13491-13508, MOVE_VENOSHOCK L12683-12696, MOVE_SMELLING_SALTS
# L7259-7280, MOVE_BARB_BARRAGE L20152-20170, MOVE_INFERNAL_PARADE
# L20271-20289); src/battle_util.c, case EFFECT_DOUBLE_POWER_ON_ARG_STATUS
# (L6186-6191).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_status_matches_helper()
	_test_hex()
	_test_venoshock()
	_test_smelling_salts()
	_test_barb_barrage()
	_test_infernal_parade()
	_test_comatose_interaction()

	var total := _pass + _fail
	print("d1_double_power_status_test: %d/%d passed" % [_pass, total])
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
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Doubling the effective base power before the damage formula's later floor
# operations and additive "+2" term doesn't guarantee an EXACTLY 2x final
# output (the same over-precise-assertion pitfall CLAUDE.md's [D2 batch]
# entry documents) — allow a small tolerance rather than exact equality.
func _approx_scaled(actual: int, baseline: int, factor: int, tolerance: int = 4) -> bool:
	return absi(actual - baseline * factor) <= tolerance


# ── Section A: data integrity ────────────────────────────────────────────────

func _test_data_integrity() -> void:
	var hex := _load_move(506)
	_chk("A.01 Hex power=65/acc=100/pp=10/SPEC/Ghost",
			hex.power == 65 and hex.accuracy == 100 and hex.pp == 10
			and hex.category == 1 and hex.type == TypeChart.TYPE_GHOST)
	_chk("A.02 Hex is_double_power_on_status + STATUS_ARG_ANY",
			hex.is_double_power_on_status and hex.double_power_status_arg == MoveData.STATUS_ARG_ANY)
	_chk("A.03 Hex is NOT Smelling Salts and has no secondary effect",
			not hex.is_smelling_salts and hex.secondary_effect == MoveData.SE_NONE)

	var venoshock := _load_move(474)
	_chk("A.04 Venoshock power=65/acc=100/pp=10/SPEC/Poison",
			venoshock.power == 65 and venoshock.accuracy == 100 and venoshock.pp == 10
			and venoshock.category == 1 and venoshock.type == TypeChart.TYPE_POISON)
	_chk("A.05 Venoshock is_double_power_on_status + STATUS_ARG_POISON_ANY",
			venoshock.is_double_power_on_status
			and venoshock.double_power_status_arg == MoveData.STATUS_ARG_POISON_ANY)
	_chk("A.06 Venoshock has no secondary effect", venoshock.secondary_effect == MoveData.SE_NONE)

	var salts := _load_move(265)
	_chk("A.07 Smelling Salts power=70/acc=100/pp=10/PHYS/Normal/contact",
			salts.power == 70 and salts.accuracy == 100 and salts.pp == 10
			and salts.category == 0 and salts.type == TypeChart.TYPE_NORMAL and salts.makes_contact)
	_chk("A.08 Smelling Salts is_double_power_on_status + STATUS_PARALYSIS + is_smelling_salts",
			salts.is_double_power_on_status
			and salts.double_power_status_arg == BattlePokemon.STATUS_PARALYSIS
			and salts.is_smelling_salts)

	var barb := _load_move(767)
	_chk("A.09 Barb Barrage power=60/acc=100/pp=10/PHYS/Poison",
			barb.power == 60 and barb.accuracy == 100 and barb.pp == 10
			and barb.category == 0 and barb.type == TypeChart.TYPE_POISON)
	_chk("A.10 Barb Barrage is_double_power_on_status + STATUS_ARG_POISON_ANY",
			barb.is_double_power_on_status
			and barb.double_power_status_arg == MoveData.STATUS_ARG_POISON_ANY)
	_chk("A.11 Barb Barrage's own secondary: 50% chance to poison",
			barb.secondary_effect == MoveData.SE_POISON and barb.secondary_chance == 50)
	_chk("A.12 Barb Barrage is NOT Smelling Salts", not barb.is_smelling_salts)

	var parade := _load_move(772)
	_chk("A.13 Infernal Parade power=60/acc=100/pp=15/SPEC/Ghost",
			parade.power == 60 and parade.accuracy == 100 and parade.pp == 15
			and parade.category == 1 and parade.type == TypeChart.TYPE_GHOST)
	_chk("A.14 Infernal Parade is_double_power_on_status + STATUS_ARG_ANY",
			parade.is_double_power_on_status
			and parade.double_power_status_arg == MoveData.STATUS_ARG_ANY)
	_chk("A.15 Infernal Parade's own secondary: 30% chance to burn",
			parade.secondary_effect == MoveData.SE_BURN and parade.secondary_chance == 30)


# ── Section B: _status_matches_double_power_arg direct unit tests ───────────

func _test_status_matches_helper() -> void:
	var mon := _make_mon("StatusMatchMon")

	# (i) arg == -1 (N/A) always false, regardless of status.
	mon.status = BattlePokemon.STATUS_BURN
	_chk("B.01 arg == -1 always returns false",
			not BattleManager._status_matches_double_power_arg(mon, -1, false))

	# (ii) STATUS_ARG_ANY matches every real non-volatile status, not NONE.
	for s in [BattlePokemon.STATUS_BURN, BattlePokemon.STATUS_FREEZE,
			BattlePokemon.STATUS_PARALYSIS, BattlePokemon.STATUS_POISON,
			BattlePokemon.STATUS_TOXIC, BattlePokemon.STATUS_SLEEP]:
		mon.status = s
		_chk("B.02 STATUS_ARG_ANY matches status %d" % s,
				BattleManager._status_matches_double_power_arg(
						mon, MoveData.STATUS_ARG_ANY, false))
	mon.status = BattlePokemon.STATUS_NONE
	_chk("B.03 STATUS_ARG_ANY does NOT match STATUS_NONE",
			not BattleManager._status_matches_double_power_arg(
					mon, MoveData.STATUS_ARG_ANY, false))

	# (iii) STATUS_ARG_POISON_ANY matches only POISON/TOXIC.
	mon.status = BattlePokemon.STATUS_POISON
	_chk("B.04 STATUS_ARG_POISON_ANY matches POISON",
			BattleManager._status_matches_double_power_arg(
					mon, MoveData.STATUS_ARG_POISON_ANY, false))
	mon.status = BattlePokemon.STATUS_TOXIC
	_chk("B.05 STATUS_ARG_POISON_ANY matches TOXIC",
			BattleManager._status_matches_double_power_arg(
					mon, MoveData.STATUS_ARG_POISON_ANY, false))
	mon.status = BattlePokemon.STATUS_BURN
	_chk("B.06 STATUS_ARG_POISON_ANY does NOT match BURN",
			not BattleManager._status_matches_double_power_arg(
					mon, MoveData.STATUS_ARG_POISON_ANY, false))

	# (iv) A specific arg matches only that exact status.
	mon.status = BattlePokemon.STATUS_PARALYSIS
	_chk("B.07 specific arg STATUS_PARALYSIS matches PARALYSIS",
			BattleManager._status_matches_double_power_arg(
					mon, BattlePokemon.STATUS_PARALYSIS, false))
	mon.status = BattlePokemon.STATUS_SLEEP
	_chk("B.08 specific arg STATUS_PARALYSIS does NOT match SLEEP",
			not BattleManager._status_matches_double_power_arg(
					mon, BattlePokemon.STATUS_PARALYSIS, false))

	# (v) Comatose-as-sleep proxy: STATUS_NONE + Comatose matches STATUS_ARG_ANY
	# and the specific STATUS_SLEEP arg, but NOT STATUS_ARG_POISON_ANY or a
	# different specific arg (Comatose only ever proxies to SLEEP).
	var comatose_ability := AbilityData.new()
	comatose_ability.ability_id = AbilityManager.ABILITY_COMATOSE
	var comatose_mon := _make_mon("ComatoseMon")
	comatose_mon.ability = comatose_ability
	comatose_mon.status = BattlePokemon.STATUS_NONE
	_chk("B.09 Comatose (real status NONE) matches STATUS_ARG_ANY",
			BattleManager._status_matches_double_power_arg(
					comatose_mon, MoveData.STATUS_ARG_ANY, false))
	_chk("B.10 Comatose matches the specific STATUS_SLEEP arg",
			BattleManager._status_matches_double_power_arg(
					comatose_mon, BattlePokemon.STATUS_SLEEP, false))
	_chk("B.11 Comatose does NOT match STATUS_ARG_POISON_ANY",
			not BattleManager._status_matches_double_power_arg(
					comatose_mon, MoveData.STATUS_ARG_POISON_ANY, false))
	_chk("B.12 Comatose does NOT match the specific STATUS_PARALYSIS arg",
			not BattleManager._status_matches_double_power_arg(
					comatose_mon, BattlePokemon.STATUS_PARALYSIS, false))

	# (vi) discriminator: a plain (non-Comatose) mon with real STATUS_NONE
	# does NOT match STATUS_ARG_ANY.
	var plain_mon := _make_mon("PlainMon")
	plain_mon.status = BattlePokemon.STATUS_NONE
	_chk("B.13 discriminator: a plain unstatused mon does NOT match STATUS_ARG_ANY",
			not BattleManager._status_matches_double_power_arg(
					plain_mon, MoveData.STATUS_ARG_ANY, false))


# The doubling dispatch (_dmg_power_override) lives entirely in
# BattleManager._phase_move_execution, NOT inside DamageCalculator — a raw
# DamageCalculator.calculate() call has zero awareness of
# move.is_double_power_on_status, so "doubling" must be observed through a
# real battle turn (matching how Rollout/Magnitude/Stomping Tantrum/etc. are
# all tested elsewhere in this project), not a direct calculator call.
# Returns the attacker's own first observed move_executed damage for `move`,
# or -1 if it never fired. Callers are responsible for adding moves to both
# mons and configuring speed so the attacker acts (and this signal fires)
# before anything else can interfere.
func _observed_damage(atk: BattlePokemon, def: BattlePokemon, move: MoveData) -> int:
	var events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk and m == move and events.is_empty():
			events.append(amount))
	bm.start_battle(atk, def)
	bm.queue_free()
	return events[0] if events.size() > 0 else -1


# ── Section C: Hex — STATUS_ARG_ANY, pure single mechanism ──────────────────

func _test_hex() -> void:
	var hex := _load_move(506)
	var tackle := _load_move(33)

	# Ghost-type moves are FLATLY IMMUNE (0x) against Normal-type defenders —
	# CLAUDE.md's own "type immunity precedes ability logic" convention. Use a
	# neutral (Water) defender type throughout this section instead of this
	# file's own _make_mon default (TYPE_NORMAL).
	var atk_i := _make_mon("HexAtk1", 300, 60, 60, 100, 60, 100)
	var def_i := _make_mon("HexDef1", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_i.add_move(hex)
	def_i.add_move(tackle)
	var baseline: int = _observed_damage(atk_i, def_i, hex)
	_chk("C.01 Hex deals real baseline damage vs an unstatused target", baseline > 0)

	# (i) doubles vs a burned target.
	var atk_ii := _make_mon("HexAtk2", 300, 60, 60, 100, 60, 100)
	var def_ii := _make_mon("HexDef2", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_ii.add_move(hex)
	def_ii.add_move(tackle)
	def_ii.status = BattlePokemon.STATUS_BURN
	var burned: int = _observed_damage(atk_ii, def_ii, hex)
	_chk("C.02 Hex roughly doubles damage vs a burned target",
			_approx_scaled(burned, baseline, 2))

	# (ii) doubles vs EVERY status (any-status scope), spot-checked with
	# paralysis and poison too (not just burn).
	var atk_iii := _make_mon("HexAtk3", 300, 60, 60, 100, 60, 100)
	var def_iii := _make_mon("HexDef3", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_iii.add_move(hex)
	def_iii.add_move(tackle)
	def_iii.status = BattlePokemon.STATUS_PARALYSIS
	var paralyzed: int = _observed_damage(atk_iii, def_iii, hex)
	_chk("C.03 Hex also doubles vs paralysis (any-status scope, not burn-specific)",
			_approx_scaled(paralyzed, baseline, 2))

	var atk_iv := _make_mon("HexAtk4", 300, 60, 60, 100, 60, 100)
	var def_iv := _make_mon("HexDef4", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_iv.add_move(hex)
	def_iv.add_move(tackle)
	def_iv.status = BattlePokemon.STATUS_POISON
	var poisoned: int = _observed_damage(atk_iv, def_iv, hex)
	_chk("C.04 Hex also doubles vs poison (any-status scope)",
			_approx_scaled(poisoned, baseline, 2))


# ── Section D: Venoshock — STATUS_ARG_POISON_ANY, pure single mechanism ─────

func _test_venoshock() -> void:
	var venoshock := _load_move(474)
	var tackle := _load_move(33)

	var atk_i := _make_mon("VenoAtk1", 300, 60, 60, 100, 60, 100)
	var def_i := _make_mon("VenoDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(venoshock)
	def_i.add_move(tackle)
	var baseline: int = _observed_damage(atk_i, def_i, venoshock)
	_chk("D.01 Venoshock deals real baseline damage vs an unstatused target", baseline > 0)

	var atk_ii := _make_mon("VenoAtk2", 300, 60, 60, 100, 60, 100)
	var def_ii := _make_mon("VenoDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(venoshock)
	def_ii.add_move(tackle)
	def_ii.status = BattlePokemon.STATUS_POISON
	var poisoned: int = _observed_damage(atk_ii, def_ii, venoshock)
	_chk("D.02 Venoshock roughly doubles damage vs a poisoned target",
			_approx_scaled(poisoned, baseline, 2))

	# discriminator: TOXIC also qualifies (STATUS_ARG_POISON_ANY, not POISON-only).
	var atk_iii := _make_mon("VenoAtk3", 300, 60, 60, 100, 60, 100)
	var def_iii := _make_mon("VenoDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(venoshock)
	def_iii.add_move(tackle)
	def_iii.status = BattlePokemon.STATUS_TOXIC
	var toxic: int = _observed_damage(atk_iii, def_iii, venoshock)
	_chk("D.03 Venoshock also doubles vs toxic (POISON_ANY scope)",
			_approx_scaled(toxic, baseline, 2))

	# discriminator: does NOT double vs paralysis (proves the scope is
	# poison-specific, not "any status" like Hex).
	var atk_iv := _make_mon("VenoAtk4", 300, 60, 60, 100, 60, 100)
	var def_iv := _make_mon("VenoDef4", 300, 60, 60, 60, 60, 50)
	atk_iv.add_move(venoshock)
	def_iv.add_move(tackle)
	def_iv.status = BattlePokemon.STATUS_PARALYSIS
	var paralyzed: int = _observed_damage(atk_iv, def_iv, venoshock)
	_chk("D.04 discriminator: Venoshock does NOT double vs paralysis " +
			"(poison-specific scope, not any-status)",
			not _approx_scaled(paralyzed, baseline, 2) and _approx_scaled(paralyzed, baseline, 1))


# ── Section E: Smelling Salts — specific PARALYSIS + cure + Substitute
# exception ────────────────────────────────────────────────────────────────

func _test_smelling_salts() -> void:
	var salts := _load_move(265)
	var tackle := _load_move(33)

	# Baseline (unstatused) for comparison.
	var atk_base := _make_mon("SaltsAtkBase", 300, 60, 60, 60, 60, 100)
	var def_base := _make_mon("SaltsDefBase", 300, 60, 60, 60, 60, 50)
	atk_base.add_move(salts)
	def_base.add_move(tackle)
	var baseline: int = _observed_damage(atk_base, def_base, salts)
	_chk("E.01 Smelling Salts deals real baseline damage vs an unstatused target",
			baseline > 0)

	# (i) doubles vs a paralyzed target, and cures the paralysis.
	var atk_i := _make_mon("SaltsAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("SaltsDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(salts)
	def_i.add_move(tackle)
	def_i.status = BattlePokemon.STATUS_PARALYSIS
	var damage_events := []
	var cured := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == salts and damage_events.is_empty():
			damage_events.append(amount))
	bm1.status_cured.connect(func(mon): if mon == def_i: cured[0] = true)
	bm1.start_battle(atk_i, def_i)
	_chk("E.02 Smelling Salts roughly doubles damage vs a paralyzed target",
			damage_events.size() == 1 and _approx_scaled(damage_events[0], baseline, 2))
	_chk("E.03 Smelling Salts cures the paralysis on hit", cured[0] == true)
	bm1.queue_free()

	# (ii) discriminator: does NOT double (and does not cure anything) vs an
	# unparalyzed target — poison specifically, proving the scope is
	# paralysis-only, not any-status like Hex/Infernal Parade.
	var atk_ii := _make_mon("SaltsAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("SaltsDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(salts)
	def_ii.add_move(tackle)
	def_ii.status = BattlePokemon.STATUS_POISON
	var damage_events2 := []
	var cured2 := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk_ii and m == salts and damage_events2.is_empty():
			damage_events2.append(amount))
	bm2.status_cured.connect(func(mon): if mon == def_ii: cured2[0] = true)
	bm2.start_battle(atk_ii, def_ii)
	_chk("E.04 discriminator: Smelling Salts does NOT double vs poison " +
			"(paralysis-specific scope)",
			damage_events2.size() == 1
			and not _approx_scaled(damage_events2[0], baseline, 2)
			and _approx_scaled(damage_events2[0], baseline, 1))
	_chk("E.05 discriminator: Smelling Salts does NOT cure poison (only removes " +
			"the target's OWN matching status)",
			cured2[0] == false and def_ii.status == BattlePokemon.STATUS_POISON)
	bm2.queue_free()

	# (iii) Substitute exception: a paralyzed target with a LIVE Substitute
	# blocks BOTH the power-double AND the cure — the real hit lands on the
	# Substitute (damage reported as 0 by this project's established
	# went_to_sub semantics), not the paralyzed body. substitute_hp is set
	# very high (matching the established "effectively unbreakable for this
	# test" precedent, e.g. m18_5g_test.gd) so it never legitimately breaks
	# over however many turns this multi-turn battle runs — avoiding the
	# documented whole-battle-aggregation pitfall, where a LATER hit (after
	# the sub breaks) would legitimately cure the paralysis and falsely look
	# like this exception failed.
	var atk_iii := _make_mon("SaltsAtk3", 300, 60, 60, 60, 60, 100)
	var def_iii := _make_mon("SaltsDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(salts)
	def_iii.add_move(tackle)
	def_iii.status = BattlePokemon.STATUS_PARALYSIS
	def_iii.substitute_hp = 999999
	var cured3 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.status_cured.connect(func(mon): if mon == def_iii: cured3[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	_chk("E.06 Smelling Salts vs a live Substitute does NOT cure the paralysis " +
			"behind it (the double is blocked, matching the cure never firing)",
			cured3[0] == false and def_iii.status == BattlePokemon.STATUS_PARALYSIS)
	bm3.queue_free()


# ── Section F: Barb Barrage — POISON_ANY + its own 50% poison secondary ─────

func _test_barb_barrage() -> void:
	var barb := _load_move(767)

	# (i) doubles vs an already-poisoned target.
	var atk_base := _make_mon("BarbAtkBase", 300, 100, 60, 60, 60, 100)
	var def_base := _make_mon("BarbDefBase", 300, 60, 60, 60, 60, 50)
	atk_base.add_move(barb)
	def_base.add_move(_load_move(33))
	var baseline: int = _observed_damage(atk_base, def_base, barb)
	_chk("F.00 Barb Barrage deals real baseline damage vs an unpoisoned target", baseline > 0)

	var atk_i := _make_mon("BarbAtk1", 300, 100, 60, 60, 60, 100)
	var def_i := _make_mon("BarbDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(barb)
	def_i.add_move(_load_move(33))
	def_i.status = BattlePokemon.STATUS_POISON
	var poisoned: int = _observed_damage(atk_i, def_i, barb)
	_chk("F.01 Barb Barrage roughly doubles damage vs an already-poisoned target",
			_approx_scaled(poisoned, baseline, 2))

	# (ii) its own secondary poison chance still fires (direct call, forced —
	# pure reuse of the existing generic secondary_effect/SE_POISON dispatch,
	# not new code, so this confirms the DATA wiring, not the mechanism itself).
	var atk_ii := _make_mon("BarbAtk2", 300, 100, 60, 60, 60, 100)
	var def_ii := _make_mon("BarbDef2", 300, 60, 60, 60, 60, 50)
	var applied: bool = StatusManager.try_secondary_effect(atk_ii, def_ii, barb, true, false)
	_chk("F.02 Barb Barrage's own 50% poison secondary fires when forced",
			applied and def_ii.status == BattlePokemon.STATUS_POISON)

	# (iii) ordering discriminator: a target that starts UNPOISONED deals only
	# the non-doubled baseline damage — deterministic and independent of
	# whatever the (real, unforced) secondary poison roll does afterward,
	# since power is computed strictly before that roll can ever run. Proves
	# the power-double reads PRE-hit status, never a status this same hit
	# is about to inflict.
	var atk_iii := _make_mon("BarbAtk3", 300, 100, 60, 60, 60, 100)
	var def_iii := _make_mon("BarbDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(barb)
	def_iii.add_move(_load_move(33))
	var baseline_iii: Dictionary = DamageCalculator.calculate(atk_iii, def_iii, barb, 100, false)
	var damage_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk_iii and m == barb and damage_events.is_empty():
			damage_events.append(amount))
	bm.start_battle(atk_iii, def_iii)
	_chk("F.03 ordering: Barb Barrage vs an initially-unpoisoned target deals " +
			"only baseline damage, regardless of its own secondary poison roll " +
			"(power-double reads PRE-hit status only)",
			damage_events.size() == 1
			and _approx_scaled(damage_events[0], baseline_iii["damage"], 1))
	bm.queue_free()


# ── Section G: Infernal Parade — ANY status + its own 30% burn secondary ────

func _test_infernal_parade() -> void:
	var parade := _load_move(772)

	# (i) doubles vs any pre-existing status (spot-checked with sleep). Ghost-
	# type is flatly immune (0x) to Normal-type defenders — use a neutral
	# (Water) defender type instead of this file's own _make_mon default.
	var atk_base := _make_mon("ParadeAtkBase", 300, 60, 60, 100, 60, 100)
	var def_base := _make_mon("ParadeDefBase", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_base.add_move(parade)
	def_base.add_move(_load_move(33))
	var baseline: int = _observed_damage(atk_base, def_base, parade)
	_chk("G.00 Infernal Parade deals real baseline damage vs an unstatused target",
			baseline > 0)

	var atk_i := _make_mon("ParadeAtk1", 300, 60, 60, 100, 60, 100)
	var def_i := _make_mon("ParadeDef1", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_i.add_move(parade)
	def_i.add_move(_load_move(33))
	def_i.status = BattlePokemon.STATUS_SLEEP
	var slept: int = _observed_damage(atk_i, def_i, parade)
	_chk("G.01 Infernal Parade roughly doubles damage vs a sleeping target",
			_approx_scaled(slept, baseline, 2))

	# (ii) its own secondary burn chance still fires (direct call, forced).
	var atk_ii := _make_mon("ParadeAtk2", 300, 60, 60, 100, 60, 100)
	var def_ii := _make_mon("ParadeDef2", 300, 60, 60, 60, 60, 50)
	var applied: bool = StatusManager.try_secondary_effect(atk_ii, def_ii, parade, true, false)
	_chk("G.02 Infernal Parade's own 30% burn secondary fires when forced",
			applied and def_ii.status == BattlePokemon.STATUS_BURN)

	# (iii) ordering discriminator: same shape as Barb Barrage's F.03 — an
	# initially-unstatused target deals only baseline damage, regardless of
	# its own (real, unforced) secondary burn roll.
	var atk_iii := _make_mon("ParadeAtk3", 300, 60, 60, 100, 60, 100)
	var def_iii := _make_mon("ParadeDef3", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_iii.add_move(parade)
	def_iii.add_move(_load_move(33))
	var baseline_iii: Dictionary = DamageCalculator.calculate(atk_iii, def_iii, parade, 100, false)
	var damage_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk_iii and m == parade and damage_events.is_empty():
			damage_events.append(amount))
	bm.start_battle(atk_iii, def_iii)
	_chk("G.03 ordering: Infernal Parade vs an initially-unstatused target deals " +
			"only baseline damage, regardless of its own secondary burn roll",
			baseline_iii["damage"] > 0 and damage_events.size() == 1
			and _approx_scaled(damage_events[0], baseline_iii["damage"], 1))
	bm.queue_free()


# ── Section H: Comatose integration (full battle, matching every other
# doubling claim in this file — see _observed_damage's own doc comment) ─────

func _test_comatose_interaction() -> void:
	var hex := _load_move(506)
	var parade := _load_move(772)
	var venoshock := _load_move(474)
	var tackle := _load_move(33)
	var comatose_ability := AbilityData.new()
	comatose_ability.ability_id = AbilityManager.ABILITY_COMATOSE

	# (i) Hex doubles vs a Comatose holder (real status stays NONE the whole
	# time). Ghost-type is flatly immune (0x) to Normal-type defenders — use
	# a neutral (Water) defender type throughout, matching Section C/G.
	var plain_atk_i := _make_mon("ComaPlainAtk1", 300, 60, 60, 100, 60, 100)
	var plain_def_i := _make_mon("ComaPlainDef1", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	plain_atk_i.add_move(hex)
	plain_def_i.add_move(tackle)
	var plain_baseline_i: int = _observed_damage(plain_atk_i, plain_def_i, hex)
	_chk("H.00 Hex deals real baseline damage vs a plain (non-Comatose) unstatused target",
			plain_baseline_i > 0)

	var atk_i := _make_mon("ComaAtk1", 300, 60, 60, 100, 60, 100)
	var def_i := _make_mon("ComaDef1", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	def_i.ability = comatose_ability
	atk_i.add_move(hex)
	def_i.add_move(tackle)
	var coma_result_i: int = _observed_damage(atk_i, def_i, hex)
	_chk("H.01 Hex roughly doubles damage vs a Comatose holder (proxy fires)",
			_approx_scaled(coma_result_i, plain_baseline_i, 2))
	_chk("H.02 the Comatose holder's real status field is still STATUS_NONE",
			def_i.status == BattlePokemon.STATUS_NONE)

	# (ii) Infernal Parade also doubles vs a Comatose holder (same ANY scope).
	var plain_atk_ii := _make_mon("ComaPlainAtk2", 300, 60, 60, 100, 60, 100)
	var plain_def_ii := _make_mon("ComaPlainDef2", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	plain_atk_ii.add_move(parade)
	plain_def_ii.add_move(tackle)
	var plain_baseline_ii: int = _observed_damage(plain_atk_ii, plain_def_ii, parade)

	var atk_ii := _make_mon("ComaAtk2", 300, 60, 60, 100, 60, 100)
	var def_ii := _make_mon("ComaDef2", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	def_ii.ability = comatose_ability
	atk_ii.add_move(parade)
	def_ii.add_move(tackle)
	var coma_result_ii: int = _observed_damage(atk_ii, def_ii, parade)
	_chk("H.03 Infernal Parade also roughly doubles damage vs a Comatose holder",
			_approx_scaled(coma_result_ii, plain_baseline_ii, 2))

	# (iii) discriminator: Venoshock (POISON_ANY-specific) does NOT double vs
	# a Comatose holder — Comatose only ever proxies to SLEEP, never POISON.
	var plain_atk_iii := _make_mon("ComaPlainAtk3", 300, 60, 60, 100, 60, 100)
	var plain_def_iii := _make_mon("ComaPlainDef3", 300, 60, 60, 60, 60, 50)
	plain_atk_iii.add_move(venoshock)
	plain_def_iii.add_move(tackle)
	var plain_baseline_iii: int = _observed_damage(plain_atk_iii, plain_def_iii, venoshock)

	var atk_iii := _make_mon("ComaAtk3", 300, 60, 60, 100, 60, 100)
	var def_iii := _make_mon("ComaDef3", 300, 60, 60, 60, 60, 50)
	def_iii.ability = comatose_ability
	atk_iii.add_move(venoshock)
	def_iii.add_move(tackle)
	var coma_result_iii: int = _observed_damage(atk_iii, def_iii, venoshock)
	_chk("H.04 discriminator: Venoshock does NOT double vs a Comatose holder " +
			"(the proxy only ever represents SLEEP, not POISON)",
			plain_baseline_iii > 0
			and not _approx_scaled(coma_result_iii, plain_baseline_iii, 2)
			and _approx_scaled(coma_result_iii, plain_baseline_iii, 1))
