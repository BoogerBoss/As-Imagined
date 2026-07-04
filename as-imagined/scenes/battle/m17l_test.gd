extends Node

# M17l test suite — Doubles-redirect/aura abilities: Lightning Rod, Storm Drain, Friend
# Guard, Telepathy, Propeller Tail, Stalwart.
#
# Scope: the 6 abilities locked in docs/decisions.md [M17l] (Step 0 re-verified all six
# IDs against Section 13's exclusion sweep — none needed correction). No new
# infrastructure was needed this tier (verified, not assumed, per the task's explicit
# instruction) — every mechanic reuses existing pipeline hooks: DamageCalculator's
# early ability-immunity gate (alongside Levitate), the existing `ally`/`defender_ally`
# parameters ([M17a]'s Battery/Power Spot/Steely Spirit, [M17c]'s Flower Gift), and the
# existing Follow Me/Rage Powder redirect block in `_phase_move_execution`.
#
# Two genuinely different mechanic shapes:
#   Lightning Rod (31)  — redirect-TRIGGER: an Electric move aimed at one doubles
#                          combatant redirects to this holder if it's that combatant's
#                          ally, plus full immunity + Sp. Atk +1 whenever it IS hit
#                          (whether by direct targeting or redirect).
#   Storm Drain (114)   — identical shape, Water.
#   Propeller Tail (239)— redirect-BYPASS: the OPPOSITE direction — the ATTACKER's own
#   Stalwart (242)         moves ignore ALL redirection (Follow Me/Rage Powder AND
#                          Lightning Rod/Storm Drain), confirmed mechanically identical
#                          to each other from source.
#   Telepathy (140)      — full immunity to a damaging move whose target is the
#                          holder's own ATTACKING ALLY (doubles only) — source's check
#                          isn't actually gated on the move being a spread move
#                          specifically, just on defender == attacker's ally.
#   Friend Guard (132)   — ×0.75 damage reduction for the DEFENDER when the DEFENDER'S
#                          ALLY holds it (not the holder's own incoming damage).
#
# Redirect precedence: this project ALREADY has Follow Me/Rage Powder implemented
# (M14b) — source confirms Follow Me/Rage Powder take precedence over Lightning
# Rod/Storm Drain's ability-redirect (checked first; ability-redirect only evaluated if
# Follow Me didn't already apply this hit), and Propeller Tail/Stalwart bypass BOTH
# identically. This tier's implementation follows that exact precedence.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: all scenarios use Normal-type combatants
#     except where the Electric/Water type itself is the mechanic under test.
#
# Ground truth: pokeemerald_expansion src/battle_move_resolution.c ::
#   HandleMoveTargetRedirection (L822-888), IsAffectedByFollowMe (L799-820);
#   src/battle_util.c :: CanAbilityAbsorbMove (L2258-2265),
#   AbsorbedByStatIncreaseAbility (L2328-2340), L8201-8206 (Telepathy),
#   GetDefenderPartnerAbilitiesModifier (L7460-7478).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_lightning_rod_storm_drain_unit()
	_test_section_3_telepathy_unit()
	_test_section_4_friend_guard_unit()
	_test_section_5_propeller_tail_stalwart_unit()
	_test_section_6_lightning_rod_full_battle_doubles()
	_test_section_7_storm_drain_full_battle_doubles()
	_test_section_8_lightning_rod_singles_direct_hit()
	_test_section_9_telepathy_full_battle_doubles()
	_test_section_10_friend_guard_full_battle_doubles()
	_test_section_11_propeller_tail_bypasses_redirect_full_battle()
	_test_section_12_negative_case()

	var total := _pass + _fail
	print("m17l_test: %d/%d passed" % [_pass, total])
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


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var lightning_rod := _load_ability(31)
	_chk("S1.01 Lightning Rod id=31, breakable=true", lightning_rod.ability_id == 31 and lightning_rod.breakable)

	var storm_drain := _load_ability(114)
	_chk("S1.02 Storm Drain id=114, breakable=true", storm_drain.ability_id == 114 and storm_drain.breakable)

	var friend_guard := _load_ability(132)
	_chk("S1.03 Friend Guard id=132, breakable=true", friend_guard.ability_id == 132 and friend_guard.breakable)

	var telepathy := _load_ability(140)
	_chk("S1.04 Telepathy id=140, breakable=true", telepathy.ability_id == 140 and telepathy.breakable)

	var propeller_tail := _load_ability(239)
	_chk("S1.05 Propeller Tail id=239, NOT breakable (attacker's own ability)",
			propeller_tail.ability_id == 239 and not propeller_tail.breakable)

	var stalwart := _load_ability(242)
	_chk("S1.06 Stalwart id=242, NOT breakable", stalwart.ability_id == 242 and not stalwart.breakable)


# ── Section 2: Lightning Rod / Storm Drain — direct unit tests ──────────────

func _test_section_2_lightning_rod_storm_drain_unit() -> void:
	var lightning_rod := _load_ability(31)
	var storm_drain := _load_ability(114)
	var mold_breaker := _load_ability(104)
	var intimidate := _load_ability(22)

	# (i) absorbs_move_type: matching type → {"kind":"stat","stat":STAGE_SPATK,"amount":1};
	# non-matching/non-holder → {} (M17m widened this from a bare int/-1 return to a
	# Dictionary — see docs/decisions.md [M17m] for why).
	var lr_holder := _make_mon("LRHolder", [TypeChart.TYPE_NORMAL])
	lr_holder.ability = lightning_rod
	_chk("S2.01 Lightning Rod absorbs Electric",
			AbilityManager.absorbs_move_type(lr_holder, TypeChart.TYPE_ELECTRIC) \
					== {"kind": "stat", "stat": BattlePokemon.STAGE_SPATK, "amount": 1})
	_chk("S2.02 Lightning Rod does NOT absorb Water",
			AbilityManager.absorbs_move_type(lr_holder, TypeChart.TYPE_WATER).is_empty())

	var sd_holder := _make_mon("SDHolder", [TypeChart.TYPE_NORMAL])
	sd_holder.ability = storm_drain
	_chk("S2.03 Storm Drain absorbs Water",
			AbilityManager.absorbs_move_type(sd_holder, TypeChart.TYPE_WATER) \
					== {"kind": "stat", "stat": BattlePokemon.STAGE_SPATK, "amount": 1})

	var non_holder := _make_mon("NonLRHolder", [TypeChart.TYPE_NORMAL])
	non_holder.ability = intimidate
	_chk("S2.04 non-holder does not absorb Electric",
			AbilityManager.absorbs_move_type(non_holder, TypeChart.TYPE_ELECTRIC).is_empty())

	# (ii) Mold Breaker bypasses the absorb.
	var mb_attacker := _make_mon("MBAttacker", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	_chk("S2.05 Mold Breaker bypasses Lightning Rod's absorb",
			AbilityManager.absorbs_move_type(lr_holder, TypeChart.TYPE_ELECTRIC, false, mb_attacker).is_empty())

	# (iii) resolve_redirect_target: ally holds it, original target doesn't → redirects.
	var target_plain := _make_mon("TargetPlain", [TypeChart.TYPE_NORMAL])
	var attacker := _make_mon("Attacker1", [TypeChart.TYPE_NORMAL])
	_chk("S2.06 redirects to the ally holding Lightning Rod",
			AbilityManager.resolve_redirect_target(target_plain, lr_holder, attacker, TypeChart.TYPE_ELECTRIC) == lr_holder)

	# (iv) Original target already holds the matching ability → no redirect needed.
	var lr_holder2 := _make_mon("LRHolder2", [TypeChart.TYPE_NORMAL])
	lr_holder2.ability = lightning_rod
	var another_lr := _make_mon("AnotherLR", [TypeChart.TYPE_NORMAL])
	another_lr.ability = lightning_rod
	_chk("S2.07 no redirect when the original target already absorbs it directly",
			AbilityManager.resolve_redirect_target(lr_holder2, another_lr, attacker, TypeChart.TYPE_ELECTRIC) == null)

	# (v) No ally (singles): no redirect.
	_chk("S2.08 no redirect with a null ally (singles)",
			AbilityManager.resolve_redirect_target(target_plain, null, attacker, TypeChart.TYPE_ELECTRIC) == null)

	# (vi) A fainted ally does not redirect.
	var fainted_lr := _make_mon("FaintedLR", [TypeChart.TYPE_NORMAL])
	fainted_lr.ability = lightning_rod
	fainted_lr.fainted = true
	_chk("S2.09 no redirect to a FAINTED ally", AbilityManager.resolve_redirect_target(
			target_plain, fainted_lr, attacker, TypeChart.TYPE_ELECTRIC) == null)

	# (vii) Mold Breaker bypasses the redirect itself.
	_chk("S2.10 Mold Breaker bypasses the redirect entirely",
			AbilityManager.resolve_redirect_target(target_plain, lr_holder, mb_attacker, TypeChart.TYPE_ELECTRIC) == null)

	# (viii) Neutralizing Gas suppresses both the absorb and the redirect.
	_chk("S2.11 Neutralizing Gas suppresses Lightning Rod's absorb",
			AbilityManager.absorbs_move_type(lr_holder, TypeChart.TYPE_ELECTRIC, true).is_empty())
	_chk("S2.12 Neutralizing Gas suppresses the redirect",
			AbilityManager.resolve_redirect_target(target_plain, lr_holder, attacker, TypeChart.TYPE_ELECTRIC, true) == null)


# ── Section 3: Telepathy — direct unit tests ─────────────────────────────────

func _test_section_3_telepathy_unit() -> void:
	var telepathy := _load_ability(140)
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)

	var holder := _make_mon("TelepathyHolder", [TypeChart.TYPE_NORMAL])
	holder.ability = telepathy

	_chk("S3.01 blocks damage when the target IS the attacker's ally",
			AbilityManager.blocks_ally_damage(holder, true, tackle))
	_chk("S3.02 does NOT block when the target is NOT the attacker's ally",
			not AbilityManager.blocks_ally_damage(holder, false, tackle))

	var non_holder := _make_mon("NonTelepathyHolder", [TypeChart.TYPE_NORMAL])
	non_holder.ability = intimidate
	_chk("S3.03 non-holder: no-op even as the attacker's ally",
			not AbilityManager.blocks_ally_damage(non_holder, true, tackle))

	# Status move (power 0) targeting the ally: not blocked (source gates on move power).
	var status_move := _load_move(45)  # Growl, power=0
	if status_move != null and status_move.power == 0:
		_chk("S3.04 a power-0 move is never blocked (source gates on move power != 0)",
				not AbilityManager.blocks_ally_damage(holder, true, status_move))
	else:
		_chk("S3.04 skip (move 45 not a 0-power move)", true)


# ── Section 4: Friend Guard — direct unit tests ──────────────────────────────

func _test_section_4_friend_guard_unit() -> void:
	var friend_guard := _load_ability(132)
	var intimidate := _load_ability(22)

	var defender := _make_mon("FGDefender", [TypeChart.TYPE_NORMAL])
	var attacker := _make_mon("FGAttacker", [TypeChart.TYPE_NORMAL])
	var fg_ally := _make_mon("FGAlly", [TypeChart.TYPE_NORMAL])
	fg_ally.ability = friend_guard

	_chk("S4.01 Friend Guard reduces damage to 0.75x when the defender's ally holds it",
			AbilityManager.friend_guard_modifier_uq412(fg_ally, attacker, defender) == 3072)

	_chk("S4.02 no reduction with no ally (singles)",
			AbilityManager.friend_guard_modifier_uq412(null, attacker, defender) == 4096)

	var non_fg_ally := _make_mon("NonFGAlly", [TypeChart.TYPE_NORMAL])
	non_fg_ally.ability = intimidate
	_chk("S4.03 no reduction when the ally holds a different ability",
			AbilityManager.friend_guard_modifier_uq412(non_fg_ally, attacker, defender) == 4096)

	var fainted_fg_ally := _make_mon("FaintedFGAlly", [TypeChart.TYPE_NORMAL])
	fainted_fg_ally.ability = friend_guard
	fainted_fg_ally.fainted = true
	_chk("S4.04 no reduction when the Friend Guard ally is fainted",
			AbilityManager.friend_guard_modifier_uq412(fainted_fg_ally, attacker, defender) == 4096)

	# Confusion self-hit shape (attacker == defender): no reduction.
	_chk("S4.05 no reduction when attacker == defender (confusion self-hit shape)",
			AbilityManager.friend_guard_modifier_uq412(fg_ally, defender, defender) == 4096)


# ── Section 5: Propeller Tail / Stalwart — direct unit tests ─────────────────

func _test_section_5_propeller_tail_stalwart_unit() -> void:
	var propeller_tail := _load_ability(239)
	var stalwart := _load_ability(242)
	var intimidate := _load_ability(22)

	var pt_attacker := _make_mon("PTAttacker", [TypeChart.TYPE_NORMAL])
	pt_attacker.ability = propeller_tail
	_chk("S5.01 Propeller Tail bypasses redirection", AbilityManager.bypasses_redirection(pt_attacker))

	var sw_attacker := _make_mon("SWAttacker", [TypeChart.TYPE_NORMAL])
	sw_attacker.ability = stalwart
	_chk("S5.02 Stalwart bypasses redirection", AbilityManager.bypasses_redirection(sw_attacker))

	var ordinary := _make_mon("OrdinaryAttacker", [TypeChart.TYPE_NORMAL])
	ordinary.ability = intimidate
	_chk("S5.03 non-holder does NOT bypass redirection", not AbilityManager.bypasses_redirection(ordinary))


# ── Section 6: Lightning Rod — full-battle doubles integration ──────────────

func _test_section_6_lightning_rod_full_battle_doubles() -> void:
	var thunder_shock := _load_move(84)
	var tackle := _load_move(33)
	var lightning_rod := _load_ability(31)

	var attacker0 := _make_mon("BattleLRAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(thunder_shock)
	var attacker1 := _make_mon("BattleLRAttacker1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)

	var target := _make_mon("BattleLRTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.add_move(tackle)
	var lr_ally := _make_mon("BattleLRAlly", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	lr_ally.ability = lightning_rod
	lr_ally.add_move(tackle)

	var stat_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.queue_move_targeted(0, 0, 2)  # attacker0 (idx0) Thunder Shocks target (idx2), turn 1 only.
	bm.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(target, lr_ally))

	# Signal-snapshot discipline: attacker0's only move is Thunder Shock, so on later
	# turns (once lr_ally may have fainted) it could legitimately auto-target `target`
	# directly — check turn 1's specific (first) event, not "never" across the battle.
	var attacker0_events := move_executed_events.filter(func(e): return e[0] == attacker0)
	_chk("S6.01 the Electric move was redirected to the Lightning Rod ally on turn 1 (0 damage dealt)",
			not attacker0_events.is_empty() and attacker0_events[0][1] == lr_ally and attacker0_events[0][3] == 0)
	_chk("S6.02 Lightning Rod's holder gained Sp. Atk +1",
			stat_events.any(func(e): return e[0] == lr_ally and e[1] == BattlePokemon.STAGE_SPATK and e[2] == 1))
	_chk("S6.03 the original target took no damage from turn 1's hit",
			not attacker0_events.is_empty() and attacker0_events[0][1] != target)

	bm.queue_free()


# ── Section 7: Storm Drain — full-battle doubles integration ────────────────

func _test_section_7_storm_drain_full_battle_doubles() -> void:
	var water_gun := _load_move(55)
	var tackle := _load_move(33)
	var storm_drain := _load_ability(114)

	var attacker0 := _make_mon("BattleSDAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(water_gun)
	var attacker1 := _make_mon("BattleSDAttacker1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)

	var target := _make_mon("BattleSDTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.add_move(tackle)
	var sd_ally := _make_mon("BattleSDAlly", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	sd_ally.ability = storm_drain
	sd_ally.add_move(tackle)

	var stat_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.queue_move_targeted(0, 0, 2)  # attacker0 (idx0) Water Guns target (idx2).
	bm.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(target, sd_ally))

	_chk("S7.01 the Water move was redirected to the Storm Drain ally (0 damage dealt)",
			move_executed_events.any(func(e): return e[0] == attacker0 and e[1] == sd_ally and e[3] == 0))
	_chk("S7.02 Storm Drain's holder gained Sp. Atk +1",
			stat_events.any(func(e): return e[0] == sd_ally and e[1] == BattlePokemon.STAGE_SPATK and e[2] == 1))

	bm.queue_free()


# ── Section 8: Lightning Rod's own direct-hit component works in singles ────
#
# Redirect itself is meaningless in singles (only one possible target), but the
# immunity+boost still applies when the holder is hit directly.

func _test_section_8_lightning_rod_singles_direct_hit() -> void:
	var thunder_shock := _load_move(84)
	var lightning_rod := _load_ability(31)

	var attacker := _make_mon("BattleLRSinglesAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(thunder_shock)
	var lr_holder := _make_mon("BattleLRSinglesHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	lr_holder.ability = lightning_rod
	lr_holder.add_move(thunder_shock)

	var stat_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(lr_holder))

	_chk("S8.01 Lightning Rod absorbs the direct hit in singles (0 damage)",
			move_executed_events.any(func(e): return e[0] == attacker and e[1] == lr_holder and e[3] == 0))
	_chk("S8.02 Lightning Rod's holder gained Sp. Atk +1 in singles",
			stat_events.any(func(e): return e[0] == lr_holder and e[1] == BattlePokemon.STAGE_SPATK and e[2] == 1))

	bm.queue_free()


# ── Section 9: Telepathy — full-battle doubles integration ─────────────────

func _test_section_9_telepathy_full_battle_doubles() -> void:
	var tackle := _load_move(33)
	var telepathy := _load_ability(140)

	# Player: attacker0 will Tackle its OWN ally (telepathy_holder), attacker0 will also
	# eventually be Tackled by the opponent, which should NOT be blocked.
	var attacker0 := _make_mon("BattleTelAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(tackle)
	var telepathy_holder := _make_mon("BattleTelHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	telepathy_holder.ability = telepathy
	telepathy_holder.add_move(tackle)

	var opp0 := _make_mon("BattleTelOpp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	opp0.add_move(tackle)
	var opp1 := _make_mon("BattleTelOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 15)
	opp1.add_move(tackle)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	# combatant indices: 0,1 = player (attacker0, telepathy_holder); 2,3 = opponent.
	bm.queue_move_targeted(0, 0, 1)  # Turn 1: attacker0 (idx0) Tackles its OWN ally (idx1).
	bm.queue_move_targeted(2, 0, 1)  # Turn 1: opp0 (idx2) Tackles telepathy_holder (idx1) too.
	bm.start_battle_doubles(_doubles_party(attacker0, telepathy_holder), _doubles_party(opp0, opp1))

	_chk("S9.01 Telepathy blocked the ALLY's own attack (0 damage)",
			move_executed_events.any(func(e): return e[0] == attacker0 and e[1] == telepathy_holder and e[3] == 0))
	_chk("S9.02 Telepathy did NOT block the OPPONENT's attack (real damage dealt)",
			move_executed_events.any(func(e): return e[0] == opp0 and e[1] == telepathy_holder and e[3] > 0))

	bm.queue_free()


# ── Section 10: Friend Guard — full-battle doubles integration ─────────────

func _test_section_10_friend_guard_full_battle_doubles() -> void:
	var tackle := _load_move(33)
	var friend_guard := _load_ability(132)

	var attacker0 := _make_mon("BattleFGAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(tackle)
	var attacker1 := _make_mon("BattleFGAttacker1", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 15)
	attacker1.add_move(tackle)

	var fg_defender := _make_mon("BattleFGDefender", [TypeChart.TYPE_NORMAL], 200, 40, 40, 40, 40, 40)
	fg_defender.add_move(tackle)
	var fg_ally := _make_mon("BattleFGAlly", [TypeChart.TYPE_NORMAL], 200, 40, 40, 40, 40, 30)
	fg_ally.ability = friend_guard
	fg_ally.add_move(tackle)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	# combatant indices: 0,1 = attackers; 2,3 = fg_defender, fg_ally.
	bm.queue_move_targeted(0, 0, 2)  # attacker0 Tackles fg_defender (protected by fg_ally).
	bm.queue_move_targeted(1, 0, 3)  # attacker1 Tackles fg_ally directly (its own damage unreduced).
	bm.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(fg_defender, fg_ally))

	var hit_on_defender := move_executed_events.filter(
			func(e): return e[0] == attacker0 and e[1] == fg_defender and e[2] == tackle)
	var hit_on_ally := move_executed_events.filter(
			func(e): return e[0] == attacker1 and e[1] == fg_ally and e[2] == tackle)

	_chk("S10.01 both hits landed (sanity check)",
			not hit_on_defender.is_empty() and not hit_on_ally.is_empty())
	if not hit_on_defender.is_empty() and not hit_on_ally.is_empty():
		_chk("S10.02 Friend Guard reduced the ALLY's damage below what the holder itself took " +
				"from an identical attacker/move/target-bulk pairing (0.75x reduction applied only to the ally)",
				hit_on_defender[0][3] < hit_on_ally[0][3])

	bm.queue_free()


# ── Section 11: Propeller Tail bypasses Lightning Rod redirect — full battle ─

func _test_section_11_propeller_tail_bypasses_redirect_full_battle() -> void:
	var thunder_shock := _load_move(84)
	var tackle := _load_move(33)
	var propeller_tail := _load_ability(239)
	var lightning_rod := _load_ability(31)

	var pt_attacker := _make_mon("BattlePTAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	pt_attacker.ability = propeller_tail
	pt_attacker.add_move(thunder_shock)
	var pt_ally := _make_mon("BattlePTAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	pt_ally.add_move(tackle)

	var target := _make_mon("BattlePTTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.add_move(tackle)
	var lr_ally := _make_mon("BattlePTLRAlly", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	lr_ally.ability = lightning_rod
	lr_ally.add_move(tackle)

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.queue_move_targeted(0, 0, 2)  # pt_attacker (idx0) Thunder Shocks target (idx2), turn 1 only.
	bm.start_battle_doubles(_doubles_party(pt_attacker, pt_ally), _doubles_party(target, lr_ally))

	# Signal-snapshot discipline: the battle runs beyond turn 1, and pt_attacker's only
	# move (Thunder Shock) auto-selects a target on later turns once `target` may have
	# fainted — at that point it could legitimately hit lr_ally directly (unrelated to
	# redirect; Lightning Rod's own direct-hit absorb would apply then). So check
	# specifically pt_attacker's FIRST move_executed event (turn 1's queued action),
	# not "never hit lr_ally across the whole battle."
	var pt_attacker_events := move_executed_events.filter(func(e): return e[0] == pt_attacker)
	_chk("S11.01 Propeller Tail bypassed Lightning Rod's redirect — the ORIGINAL target was hit on turn 1",
			not pt_attacker_events.is_empty() and pt_attacker_events[0][1] == target
					and pt_attacker_events[0][2] == thunder_shock and pt_attacker_events[0][3] > 0)
	_chk("S11.02 the Lightning Rod ally was NOT the target of turn 1's move",
			not pt_attacker_events.is_empty() and pt_attacker_events[0][1] != lr_ally)

	bm.queue_free()


# ── Section 12: negative control — an ordinary Pokémon does nothing ─────────

func _test_section_12_negative_case() -> void:
	var thunder_shock := _load_move(84)
	var tackle := _load_move(33)

	var attacker0 := _make_mon("BattleNegAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(thunder_shock)
	var attacker1 := _make_mon("BattleNegAttacker1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)

	var target := _make_mon("BattleNegTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.add_move(tackle)
	var ordinary_ally := _make_mon("BattleNegAlly", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	ordinary_ally.add_move(tackle)

	var move_executed_events := []
	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))

	bm.queue_move_targeted(0, 0, 2)  # attacker0 Thunder Shocks target (idx2) — no ability involved.
	bm.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(target, ordinary_ally))

	_chk("S12.01 an ordinary target with no ability took real damage (no redirect, no absorb)",
			move_executed_events.any(func(e): return e[0] == attacker0 and e[1] == target and e[2] == thunder_shock and e[3] > 0))
	_chk("S12.02 no stray Sp. Atk +1 was granted to anyone from this hit",
			not stat_events.any(func(e): return e[1] == BattlePokemon.STAGE_SPATK))

	bm.queue_free()
