extends Node

# M17g test suite — Ability-suppression plumbing (new infrastructure): Mold Breaker /
# Neutralizing Gas.
#
# Scope: the 2 abilities locked in docs/decisions.md [M17g] (Step 0 excluded
# Turboblaze/Teravolt as legendary-exclusive per Section 13.1, and deferred Mycelium
# Might since its other half needs the not-yet-built Stall turn-order shape):
#   Mold Breaker      (104) — attacker-scoped: while THIS Pokémon is attacking, ignores
#                              the TARGET's ability if it's flagged AbilityData.breakable
#                              (M17h retrofit: was a hardcoded array, see [M17h]).
#   Neutralizing Gas  (256) — field-wide: suppresses every OTHER live battler's ability
#                              for as long as this Pokémon remains in battle.
#
# New infrastructure:
#   AbilityManager.effective_ability_id(mon, ng_active, attacker) -> int — the single
#     suppression-aware chokepoint every ability-consuming function in this project now
#     routes through, mirroring source's GetBattlerAbilityInternal.
#   AbilityManager.is_neutralizing_gas_active(combatants) -> bool
#   BattleManager._is_neutralizing_gas_active() -> bool
#
# Source-verified correction (see ability_manager.gd's is_trapped doc comment and
# docs/decisions.md [M17g]): Neutralizing Gas DOES suppress trapping (Shadow Tag/Arena
# Trap/Magnet Pull all route through the same GetBattlerAbility chokepoint), but Mold
# Breaker does NOT — moldBreakerActive is scoped strictly to the window of processing
# one specific move, and IsAbilityPreventingEscape is only ever called from
# selection-time menu code, entirely outside that window.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: Ground vs Normal-type is neutral (not
#     resisted, not immune), used as this suite's baseline matchup for every damage
#     scenario; Ground-vs-Flying immunity is deliberately reused for the Levitate cases
#     themselves (that immunity IS the mechanism under test, not a confound).
#
# Ground truth: pokeemerald_expansion src/battle_util.c ::
#   GetBattlerAbilityInternal (L4844-4878), IsMoldBreakerTypeAbility (L4805-4820),
#   CanBreakThroughAbility (L4822-4827), IsNeutralizingGasOnField (L4794-4803),
#   IsAbilityPreventingEscape (L4917-4941).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_effective_ability_id_unit()
	_test_section_3_is_neutralizing_gas_active_unit()
	_test_section_4_mold_breaker_damage_bypass()
	_test_section_5_mold_breaker_not_attacking_no_bypass()
	_test_section_6_neutralizing_gas_suppresses_intimidate()
	_test_section_7_neutralizing_gas_stops_after_holder_leaves()
	_test_section_8_is_trapped_interaction()
	_test_section_9_negative_ordinary_mon_suppresses_nothing()

	var total := _pass + _fail
	print("m17g_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var mold_breaker := _load_ability(104)
	_chk("S1.01 Mold Breaker id=104", mold_breaker.ability_id == 104)
	var neutralizing_gas := _load_ability(256)
	_chk("S1.02 Neutralizing Gas id=256", neutralizing_gas.ability_id == 256)


# ── Section 2: AbilityManager.effective_ability_id — direct unit tests ───────

func _test_section_2_effective_ability_id_unit() -> void:
	var levitate := _load_ability(26)
	var intimidate := _load_ability(22)
	var mold_breaker := _load_ability(104)
	var neutralizing_gas := _load_ability(256)

	var levitate_mon := _make_mon("LevMon", [TypeChart.TYPE_NORMAL])
	levitate_mon.ability = levitate
	var intimidate_mon := _make_mon("IntimMon", [TypeChart.TYPE_NORMAL])
	intimidate_mon.ability = intimidate
	var mb_mon := _make_mon("MBMon", [TypeChart.TYPE_NORMAL])
	mb_mon.ability = mold_breaker
	var ng_mon := _make_mon("NGMon", [TypeChart.TYPE_NORMAL])
	ng_mon.ability = neutralizing_gas
	var no_ability_mon := _make_mon("NoAbilityMon", [TypeChart.TYPE_NORMAL])

	_chk("S2.01 no ability, ng_active=false: NONE",
			AbilityManager.effective_ability_id(no_ability_mon, false) == AbilityManager.ABILITY_NONE)
	_chk("S2.02 ordinary ability, ng_active=false: resolves normally",
			AbilityManager.effective_ability_id(intimidate_mon, false) == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S2.03 Neutralizing Gas active suppresses an ordinary ability (Intimidate)",
			AbilityManager.effective_ability_id(intimidate_mon, true) == AbilityManager.ABILITY_NONE)
	_chk("S2.04 Neutralizing Gas active suppresses Levitate too (breakable ability, but NG doesn't care)",
			AbilityManager.effective_ability_id(levitate_mon, true) == AbilityManager.ABILITY_NONE)
	_chk("S2.05 Neutralizing Gas does NOT suppress its own holder",
			AbilityManager.effective_ability_id(ng_mon, true) == AbilityManager.ABILITY_NEUTRALIZING_GAS)

	# Mold Breaker: attacker-scoped, only for breakable abilities, never the wielder's own.
	_chk("S2.06 Mold Breaker (as attacker) suppresses defender's breakable Levitate",
			AbilityManager.effective_ability_id(levitate_mon, false, mb_mon) == AbilityManager.ABILITY_NONE)
	_chk("S2.07 Mold Breaker (as attacker) does NOT suppress defender's non-breakable Intimidate",
			AbilityManager.effective_ability_id(intimidate_mon, false, mb_mon) == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S2.08 Mold Breaker never suppresses its own wielder's ability (attacker == mon)",
			AbilityManager.effective_ability_id(mb_mon, false, mb_mon) == AbilityManager.ABILITY_MOLD_BREAKER)
	_chk("S2.09 an ordinary attacker (no Mold Breaker) does NOT suppress defender's Levitate",
			AbilityManager.effective_ability_id(levitate_mon, false, intimidate_mon) == AbilityManager.ABILITY_LEVITATE)

	# Double-suppression: Neutralizing Gas active elsewhere suppresses the Mold Breaker
	# holder's OWN ability identity directly — a real, source-faithful interaction
	# (effective_ability_id's recursive self-check inside the Mold Breaker branch), not
	# a special case bolted on afterward. Checked directly on mb_mon itself (not via a
	# defender's Levitate, which NG would suppress on its own regardless — this is the
	# sharp discriminator: does NG reach INTO the attacker's own ability check).
	_chk("S2.10 Neutralizing Gas suppresses a Mold-Breaker holder's own ability identity",
			AbilityManager.effective_ability_id(mb_mon, true) == AbilityManager.ABILITY_NONE)


# ── Section 3: AbilityManager.is_neutralizing_gas_active — direct unit tests ─

func _test_section_3_is_neutralizing_gas_active_unit() -> void:
	var neutralizing_gas := _load_ability(256)

	var ordinary_a := _make_mon("OrdA", [TypeChart.TYPE_NORMAL])
	var ordinary_b := _make_mon("OrdB", [TypeChart.TYPE_NORMAL])
	var ng_mon := _make_mon("NGMon2", [TypeChart.TYPE_NORMAL])
	ng_mon.ability = neutralizing_gas
	var fainted_ng_mon := _make_mon("FaintedNGMon", [TypeChart.TYPE_NORMAL])
	fainted_ng_mon.ability = neutralizing_gas
	fainted_ng_mon.fainted = true

	_chk("S3.01 no Neutralizing Gas anywhere: inactive",
			not AbilityManager.is_neutralizing_gas_active([ordinary_a, ordinary_b]))
	_chk("S3.02 a live Neutralizing Gas holder anywhere on the field: active",
			AbilityManager.is_neutralizing_gas_active([ordinary_a, ng_mon, ordinary_b]))
	_chk("S3.03 a FAINTED Neutralizing Gas holder no longer counts: inactive",
			not AbilityManager.is_neutralizing_gas_active([ordinary_a, fainted_ng_mon, ordinary_b]))


# ── Section 4: Mold Breaker bypasses a defending Levitate holder's Ground immunity ──

func _test_section_4_mold_breaker_damage_bypass() -> void:
	var earthquake := _load_move(89)
	_chk("S4.0x Earthquake is Ground-type", earthquake.type == TypeChart.TYPE_GROUND)

	var mold_breaker := _load_ability(104)
	var levitate := _load_ability(26)

	var ordinary_attacker := _make_mon("OrdAtk", [TypeChart.TYPE_NORMAL], 100, 100, 80, 80, 80, 80)
	var mb_attacker := _make_mon("MBAtk", [TypeChart.TYPE_NORMAL], 100, 100, 80, 80, 80, 80)
	mb_attacker.ability = mold_breaker
	var levitate_defender := _make_mon("LevDef", [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 80)
	levitate_defender.ability = levitate

	var blocked: Dictionary = DamageCalculator.calculate(ordinary_attacker, levitate_defender, earthquake, 100, false)
	_chk("S4.01 ordinary attacker's Earthquake is blocked (0 damage) by Levitate",
			blocked["damage"] == 0)

	var bypassed: Dictionary = DamageCalculator.calculate(mb_attacker, levitate_defender, earthquake, 100, false)
	_chk("S4.02 Mold-Breaker-holder's Earthquake deals real damage, bypassing Levitate",
			bypassed["damage"] > 0)


# ── Section 5: Mold Breaker does NOT suppress when its holder isn't the attacker ────

func _test_section_5_mold_breaker_not_attacking_no_bypass() -> void:
	var earthquake := _load_move(89)
	var mold_breaker := _load_ability(104)
	var levitate := _load_ability(26)

	# The Mold Breaker holder exists on the field but is NOT the one making this attack —
	# an ordinary Pokémon attacks instead. Levitate must still block fully. This is the
	# direct proof that Mold Breaker's bypass requires the CURRENT attacker to hold it,
	# not merely that a Mold-Breaker-holding Pokémon exists somewhere in the battle.
	var mb_bystander := _make_mon("MBBystander", [TypeChart.TYPE_NORMAL], 100, 100, 80, 80, 80, 80)
	mb_bystander.ability = mold_breaker
	var ordinary_attacker := _make_mon("OrdAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 80, 80, 80, 80)
	var levitate_defender := _make_mon("LevDef2", [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 80)
	levitate_defender.ability = levitate

	var result: Dictionary = DamageCalculator.calculate(ordinary_attacker, levitate_defender, earthquake, 100, false)
	_chk("S5.01 Levitate still blocks fully when the actual attacker lacks Mold Breaker " +
			"(a Mold-Breaker holder existing elsewhere in the battle is irrelevant)",
			result["damage"] == 0)

	# Same check at the primitive level, unambiguous about WHO is attacking.
	_chk("S5.02 blocks_move_type: ordinary attacker (not mb_bystander) still blocked",
			AbilityManager.blocks_move_type(levitate_defender, TypeChart.TYPE_GROUND, false, ordinary_attacker))


# ── Section 6: Neutralizing Gas suppresses a switched-in ability holder's passive ──

func _test_section_6_neutralizing_gas_suppresses_intimidate() -> void:
	var tackle := _load_move(33)
	var neutralizing_gas := _load_ability(256)
	var intimidate := _load_ability(22)

	# Player's Neutralizing Gas holder is active from battle start and stays active —
	# Opponent's Intimidate holder switches in from the bench mid-battle while NG is
	# still active field-wide.
	var ng_holder := _make_mon("NGHolder", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	ng_holder.ability = neutralizing_gas
	ng_holder.add_move(tackle)

	var opp_ordinary := _make_mon("OppOrd", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	opp_ordinary.add_move(tackle)
	var opp_intimidate := _make_mon("OppIntim", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	opp_intimidate.ability = intimidate
	opp_intimidate.add_move(tackle)

	var stat_changes := []
	var triggers := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(p, s, a): stat_changes.push_back([p, s, a]))
	bm.ability_triggered.connect(func(p, name): triggers.push_back([p, name]))

	var opp_party := BattleParty.new()
	opp_party.members = [opp_ordinary, opp_intimidate]
	opp_party.active_index = 0

	bm.queue_switch(1, 1)  # Turn 1: opponent switches in the Intimidate holder.
	bm.start_battle_with_parties(BattleParty.single(ng_holder), opp_party)

	_chk("S6.01 Intimidate's switch-in did NOT lower Player's Attack while Neutralizing " +
			"Gas is active on the field",
			not stat_changes.any(func(e): return e[0] == ng_holder and e[1] == BattlePokemon.STAGE_ATK))
	_chk("S6.02 no 'intimidate' ability_triggered event fired at all",
			not triggers.any(func(e): return e[1] == "intimidate"))

	bm.queue_free()


# ── Section 7: Neutralizing Gas stops suppressing once its holder leaves the field ──

func _test_section_7_neutralizing_gas_stops_after_holder_leaves() -> void:
	var tackle := _load_move(33)
	var neutralizing_gas := _load_ability(256)
	var intimidate := _load_ability(22)

	# Player's Neutralizing Gas holder voluntarily switches away on turn 1 (removing NG
	# from the field) BEFORE Opponent's Intimidate holder ever switches in on turn 2 —
	# by the time Intimidate's own switch-in trigger evaluates, Neutralizing Gas is
	# already gone, so Intimidate should fire normally this time.
	var ng_holder := _make_mon("NGHolder2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 200)
	ng_holder.ability = neutralizing_gas
	ng_holder.add_move(tackle)
	var player_bench := _make_mon("PlayerBench", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	player_bench.add_move(tackle)

	var opp_ordinary := _make_mon("OppOrd2", [TypeChart.TYPE_NORMAL], 200, 60, 40, 60, 40, 40)
	opp_ordinary.add_move(tackle)
	var opp_intimidate := _make_mon("OppIntim2", [TypeChart.TYPE_NORMAL], 200, 60, 40, 60, 40, 30)
	opp_intimidate.ability = intimidate
	opp_intimidate.add_move(tackle)

	var stat_changes := []
	var triggers := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(p, s, a): stat_changes.push_back([p, s, a]))
	bm.ability_triggered.connect(func(p, name): triggers.push_back([p, name]))

	var player_party := BattleParty.new()
	player_party.members = [ng_holder, player_bench]
	player_party.active_index = 0
	var opp_party := BattleParty.new()
	opp_party.members = [opp_ordinary, opp_intimidate]
	opp_party.active_index = 0

	bm.queue_switch(0, 1)  # Turn 1: Player switches NG_holder -> player_bench (NG leaves).
	bm.queue_switch(1, 1)  # Turn 2: Opponent switches in Intimidate holder (NG already gone).
	bm.start_battle_with_parties(player_party, opp_party)

	_chk("S7.01 Intimidate DID lower player_bench's Attack once Neutralizing Gas had " +
			"already left the field",
			stat_changes.any(func(e): return e[0] == player_bench and e[1] == BattlePokemon.STAGE_ATK and e[2] < 0))
	_chk("S7.02 an 'intimidate' ability_triggered event fired",
			triggers.any(func(e): return e[1] == "intimidate"))

	bm.queue_free()


# ── Section 8: Mold Breaker / Neutralizing Gas × is_trapped() interaction ──────────

func _test_section_8_is_trapped_interaction() -> void:
	var arena_trap := _load_ability(71)
	var mold_breaker := _load_ability(104)
	var neutralizing_gas := _load_ability(256)

	var grounded_mon := _make_mon("GroundedMon", [TypeChart.TYPE_NORMAL])
	var opp_arena_trap := _make_mon("OppArenaTrap2", [TypeChart.TYPE_NORMAL])
	opp_arena_trap.ability = arena_trap

	# (a) Neutralizing Gas DOES suppress trapping — direct unit test.
	_chk("S8.01 Arena Trap traps normally when Neutralizing Gas is inactive",
			AbilityManager.is_trapped(grounded_mon, [opp_arena_trap], false))
	_chk("S8.02 Arena Trap no longer traps while Neutralizing Gas is active",
			not AbilityManager.is_trapped(grounded_mon, [opp_arena_trap], true))

	# (b) Mold Breaker does NOT suppress trapping — is_trapped() has no attacker param
	# at all (confirmed via source: moldBreakerActive is scoped strictly to the window
	# of processing one specific move, and trapping is checked at selection time,
	# outside that window entirely — see ability_manager.gd's is_trapped doc comment).
	# Full-battle proof: a Mold-Breaker-holding Pokémon gets ZERO benefit from its own
	# ability against being trapped by an opponent's Arena Trap.
	var tackle := _load_move(33)
	var mb_trapped := _make_mon("MBTrapped", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	mb_trapped.ability = mold_breaker
	mb_trapped.add_move(tackle)
	var bench := _make_mon("MBTrappedBench", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var trapper := _make_mon("Trapper8", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	trapper.ability = arena_trap
	trapper.add_move(tackle)

	var switched_out := []
	var moves_used := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back([p, s]))
	bm.move_executed.connect(func(a, d, m, dmg): moves_used.push_back(a))

	var player_party := BattleParty.new()
	player_party.members = [mb_trapped, bench]
	player_party.active_index = 0

	bm.queue_switch(0, 1)  # Turn 1: Mold-Breaker-holding player tries to switch away.
	bm.start_battle_with_parties(player_party, BattleParty.single(trapper))

	_chk("S8.03 Mold Breaker holder is STILL trapped by the opponent's Arena Trap " +
			"(Mold Breaker gives it no escape benefit)",
			not switched_out.any(func(e): return e[0] == mb_trapped))
	_chk("S8.04 blocked switch fell back to Tackle instead",
			moves_used.any(func(a): return a == mb_trapped))

	bm.queue_free()

	# (c) Full-battle proof of (a): the escaping mon's OWN Neutralizing Gas suppresses
	# the opponent's Arena Trap field-wide, letting it switch away freely.
	var ng_escaper := _make_mon("NGEscaper", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	ng_escaper.ability = neutralizing_gas
	ng_escaper.add_move(tackle)
	var ng_bench := _make_mon("NGEscaperBench", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	ng_bench.add_move(tackle)
	var trapper2 := _make_mon("Trapper8b", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	trapper2.ability = arena_trap
	trapper2.add_move(tackle)

	var switched_out2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.pokemon_switched_out.connect(func(p, s): switched_out2.push_back([p, s]))

	var player_party2 := BattleParty.new()
	player_party2.members = [ng_escaper, ng_bench]
	player_party2.active_index = 0

	bm2.queue_switch(0, 1)
	bm2.start_battle_with_parties(player_party2, BattleParty.single(trapper2))

	_chk("S8.05 a Neutralizing-Gas-holding Pokémon switches away freely despite the " +
			"opponent's Arena Trap (NG suppresses the trapper's ability field-wide)",
			switched_out2.any(func(e): return e[0] == ng_escaper))

	bm2.queue_free()


# ── Section 9: Negative case — an ordinary Pokémon's presence suppresses nothing ────

func _test_section_9_negative_ordinary_mon_suppresses_nothing() -> void:
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)

	_chk("S9.01 direct: no Neutralizing Gas on a field of ordinary Pokémon",
			not AbilityManager.is_neutralizing_gas_active([
				_make_mon("O1", [TypeChart.TYPE_NORMAL]),
				_make_mon("O2", [TypeChart.TYPE_NORMAL]),
			]))

	# Full-battle control: Intimidate fires completely normally with no suppression
	# ability anywhere in the battle — the exact same scenario as Section 6, just
	# without the Neutralizing Gas holder, to show the baseline behavior is unaffected.
	var ordinary_active := _make_mon("OrdinaryActive", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	ordinary_active.add_move(tackle)

	var opp_ordinary := _make_mon("OppOrd3", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	opp_ordinary.add_move(tackle)
	var opp_intimidate := _make_mon("OppIntim3", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	opp_intimidate.ability = intimidate
	opp_intimidate.add_move(tackle)

	var stat_changes := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(p, s, a): stat_changes.push_back([p, s, a]))

	var opp_party := BattleParty.new()
	opp_party.members = [opp_ordinary, opp_intimidate]
	opp_party.active_index = 0

	bm.queue_switch(1, 1)
	bm.start_battle_with_parties(BattleParty.single(ordinary_active), opp_party)

	_chk("S9.02 Intimidate fires normally against an ordinary Pokémon with no " +
			"suppression ability anywhere on the field",
			stat_changes.any(func(e): return e[0] == ordinary_active and e[1] == BattlePokemon.STAGE_ATK and e[2] < 0))

	bm.queue_free()
