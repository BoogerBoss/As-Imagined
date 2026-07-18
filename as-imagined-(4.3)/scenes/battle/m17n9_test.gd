extends Node

# M17n-9 test suite — Group 8, "wide-but-shallow systems": Magic Guard, Infiltrator,
# Magic Bounce.
#
# Scope: the 3 abilities in docs/m17n_recon.md's Group 8 "wide-but-shallow systems"
# sub-cluster, trimmed by Rob's explicit exclusion decision — Good As Gold (283) is
# excluded from this sub-tier even though that recon's original text lists it
# alongside these three; that document predates the exclusion decision and is stale
# on this point. Step 0 re-verified all three IDs directly against
# include/constants/abilities.h — no corrections needed (Magic Guard=98,
# Infiltrator=151, Magic Bounce=156).
#
# Magic Guard blocks ALL indirect damage this project implements: weather chip
# (sandstorm/hail), status residual (burn/poison/toxic — but the toxic counter still
# ticks, matching source's HandleEndTurnPoison L526-530), standard recoil moves
# (alongside Rock Head), Rough Skin/Iron Barbs' damage to the ATTACKER, Life Orb
# recoil, and Spikes/Stealth Rock switch-in damage. Deliberately does NOT block two
# indirect sources this project also implements, confirmed from source: Struggle's
# fixed recoil, and Aftermath/Innards Out's retaliation against the killer (gated
# only by Damp in source, never Magic Guard). Toxic Spikes' poison INFLICTION is
# also NOT blocked (only the resulting residual damage is, via the same
# end_of_turn_damage gate every other status source uses). No single existing
# chokepoint unifies all six exempted call sites — see
# AbilityManager.blocks_indirect_damage's own doc comment for the full reasoning on
# why a single reusable predicate (not a new pipeline) is the right shape here.
#
# Infiltrator bypasses Reflect/Light Screen/Aurora Veil (GetScreensModifier,
# battle_util.c L7358-7362) AND Substitute (IsSubstituteProtected,
# battle_script_commands.c L9534 — a single shared chokepoint every substitute
# check in source routes through) for the ATTACKER's own moves, both damaging and
# status. Deliberately scoped to ONLY these two systems (source's Infiltrator also
# bypasses Mist/Safeguard, neither implemented here — no-op, nothing to gate).
#
# Magic Bounce reflects the FIRST foe-targeting status move used against the holder
# back at its own user, scoped to this project's `move.bounceable` subset —
# re-derived per-move from source's `magicCoatAffected` flag rather than assumed for
# "every status move": exactly 9 of this project's 91 moves qualify (Sand Attack,
# Tail Whip, Leer, Growl, Sleep Powder, Thunder Wave, Toxic, Confuse Ray,
# Will-O-Wisp). Implemented as a single non-recursive attacker/defender swap in
# `_phase_move_execution`, which gets "only one bounce ever" (even in a
# Magic-Bounce-vs-Magic-Bounce matchup) for free from the linear control flow.
# `.breakable = TRUE` in source (unlike Magic Guard/Infiltrator) — a Mold-Breaker
# attacker's status move is NOT reflected. Checked BEFORE the Prankster-Dark-type
# immunity gate further down `_phase_move_execution`, matching source's
# CanTargetBlockPranksterMove (battle_util.c L2203-2210) — a Prankster-boosted
# status move against a Dark-type Magic Bounce holder correctly bounces rather than
# being eaten by the Dark immunity gate as a no-op.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state (every discriminator below captures the
#     FIRST occurrence of the relevant signal, never reads mon state after
#     start_battle() returns).
#   - Type immunity precedes ability logic: neutral Normal-vs-Normal matchups unless
#     the mechanic under test is itself type-specific (Corrosion-style — N/A here;
#     Thunder Wave vs Ground, Dark-type Prankster interaction).
#   - Pairwise damage comparisons (screens, Substitute) force both _force_roll and
#     _force_crit identically across the compared runs.
#   - _force_hit = true on any non-100-accuracy move used as a mechanism probe.
#
# Ground truth: pokeemerald_expansion src/battle_end_turn.c (Magic Guard's exemption
#   chain, L134-700 throughout); src/battle_util.c :: GetScreensModifier
#   (L7347-7365), IsSubstituteProtected-adjacent (battle_script_commands.c L9522-9536);
#   src/battle_move_resolution.c :: TryMagicBounce/TryMagicCoat/MoveEndBouncedMove
#   (L5158-5182, L3142-3200); include/move.h :: MoveCanBeBouncedBack (L350-352);
#   src/battle_util.c :: CanTargetBlockPranksterMove (L2203-2210); src/data/abilities.h
#   (breakable flags, L736-741 Magic Guard, L1139-1144 Infiltrator, L1174-1180 Magic Bounce).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_magic_guard_unit()
	_test_section_3_magic_guard_full_battle()
	_test_section_4_infiltrator_unit()
	_test_section_5_infiltrator_screens_full_battle()
	_test_section_6_infiltrator_substitute_full_battle()
	_test_section_7_magic_bounce_unit()
	_test_section_8_magic_bounce_full_battle()
	_test_section_9_magic_bounce_mold_breaker()
	_test_section_10_magic_bounce_vs_magic_bounce()
	_test_section_11_magic_bounce_prankster_dark()
	_test_section_12_neutralizing_gas_suppression()
	_test_section_13_negative_control()

	var total := _pass + _fail
	print("m17n9_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


# ── Helpers ───────────────────────────────────────────────────────────────────

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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [Flaky-suite audit] pinned neutral nature + zero IVs -- S5.02's Infiltrator-vs-Reflect comparison is a cross-instance damage-magnitude check


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var magic_guard := _load_ability(98)
	_chk("S1.01 Magic Guard id=98", magic_guard.ability_id == 98)
	_chk("S1.02 Magic Guard not breakable, not cant_be_suppressed (source-verified)",
			not magic_guard.breakable and not magic_guard.cant_be_suppressed)

	var infiltrator := _load_ability(151)
	_chk("S1.03 Infiltrator id=151", infiltrator.ability_id == 151)
	_chk("S1.04 Infiltrator not breakable, not cant_be_suppressed (source-verified)",
			not infiltrator.breakable and not infiltrator.cant_be_suppressed)

	var magic_bounce := _load_ability(156)
	_chk("S1.05 Magic Bounce id=156", magic_bounce.ability_id == 156)
	_chk("S1.06 Magic Bounce IS breakable (source data/abilities.h L1179 — the one " +
			"exception among this tier's three)", magic_bounce.breakable == true)
	_chk("S1.07 Magic Bounce not cant_be_suppressed", not magic_bounce.cant_be_suppressed)


# ── Section 2: Magic Guard — direct unit tests ───────────────────────────────

func _test_section_2_magic_guard_unit() -> void:
	var magic_guard := _load_ability(98)
	var rock_head := _load_ability(69)
	var life_orb_dummy := _make_mon("MGLifeOrb", [TypeChart.TYPE_NORMAL])
	life_orb_dummy.ability = magic_guard

	_chk("S2.01 blocks_indirect_damage true for Magic Guard holder",
			AbilityManager.blocks_indirect_damage(life_orb_dummy))
	var plain_s2 := _make_mon("MGPlain", [TypeChart.TYPE_NORMAL])
	_chk("S2.02 blocks_indirect_damage false for a plain Pokémon",
			not AbilityManager.blocks_indirect_damage(plain_s2))

	# end_of_turn_damage: burn/poison/toxic all return 0 under Magic Guard.
	var burn_mon := _make_mon("MGBurn", [TypeChart.TYPE_NORMAL])
	burn_mon.ability = magic_guard
	burn_mon.status = BattlePokemon.STATUS_BURN
	_chk("S2.03 Magic Guard: burn end_of_turn_damage == 0",
			StatusManager.end_of_turn_damage(burn_mon) == 0)

	var poison_mon := _make_mon("MGPoison", [TypeChart.TYPE_NORMAL])
	poison_mon.ability = magic_guard
	poison_mon.status = BattlePokemon.STATUS_POISON
	_chk("S2.04 Magic Guard: poison end_of_turn_damage == 0",
			StatusManager.end_of_turn_damage(poison_mon) == 0)

	var toxic_mon := _make_mon("MGToxic", [TypeChart.TYPE_NORMAL])
	toxic_mon.ability = magic_guard
	toxic_mon.status = BattlePokemon.STATUS_TOXIC
	toxic_mon.toxic_counter = 0
	var toxic_dmg := StatusManager.end_of_turn_damage(toxic_mon)
	_chk("S2.05 Magic Guard: toxic end_of_turn_damage == 0", toxic_dmg == 0)
	_chk("S2.06 Magic Guard: toxic_counter STILL increments (source L526-530 ticks it " +
			"even inside the Magic Guard branch)", toxic_mon.toxic_counter == 1)

	# blocks_recoil: Magic Guard blocks recoil alongside Rock Head.
	_chk("S2.07 blocks_recoil true for Magic Guard holder",
			AbilityManager.blocks_recoil(life_orb_dummy))
	var rock_head_mon := _make_mon("RockHeadMon", [TypeChart.TYPE_NORMAL])
	rock_head_mon.ability = rock_head
	_chk("S2.08 blocks_recoil still true for Rock Head (pre-existing, unbroken)",
			AbilityManager.blocks_recoil(rock_head_mon))
	_chk("S2.09 blocks_recoil false for a plain Pokémon",
			not AbilityManager.blocks_recoil(plain_s2))

	# life_orb_recoil: 0 under Magic Guard even while holding Life Orb.
	var life_orb_item := ItemData.new()
	life_orb_item.hold_effect = ItemManager.HOLD_EFFECT_LIFE_ORB
	life_orb_dummy.held_item = life_orb_item
	_chk("S2.10 life_orb_recoil == 0 under Magic Guard",
			ItemManager.life_orb_recoil(life_orb_dummy) == 0)
	var plain_lo := _make_mon("PlainLifeOrb", [TypeChart.TYPE_NORMAL])
	plain_lo.held_item = life_orb_item
	_chk("S2.11 life_orb_recoil > 0 for a plain Life Orb holder (discriminator)",
			ItemManager.life_orb_recoil(plain_lo) > 0)

	# Rough Skin/Iron Barbs: the ATTACKER's own Magic Guard blocks the damage back.
	var rough_skin := _load_ability(24)
	var rs_holder := _make_mon("RSHolder", [TypeChart.TYPE_NORMAL])
	rs_holder.ability = rough_skin
	var mg_attacker := _make_mon("MGAttacker", [TypeChart.TYPE_NORMAL])
	mg_attacker.ability = magic_guard
	var tackle_s2 := _load_move(33)
	var result_mg_atk: Dictionary = AbilityManager.try_contact_effects(
			mg_attacker, rs_holder, tackle_s2, 10)
	_chk("S2.12 Rough Skin damage blocked when the ATTACKER has Magic Guard",
			result_mg_atk.get("rough_skin_damage", -1) == 0)
	var plain_attacker_s2 := _make_mon("PlainAttackerS2", [TypeChart.TYPE_NORMAL])
	var result_plain_atk: Dictionary = AbilityManager.try_contact_effects(
			plain_attacker_s2, rs_holder, tackle_s2, 10)
	_chk("S2.13 Rough Skin damage still fires for a plain attacker (discriminator)",
			result_plain_atk.get("rough_skin_damage", 0) > 0)


# ── Section 3: Magic Guard — full-battle integration ─────────────────────────

func _test_section_3_magic_guard_full_battle() -> void:
	var magic_guard := _load_ability(98)
	var tackle := _load_move(33)

	# (i) Weather chip: Magic Guard holder takes no sandstorm damage; a plain
	# opponent on the same field still does (discriminator).
	var mg_holder_i := _make_mon("MGWeatherHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	mg_holder_i.ability = magic_guard
	mg_holder_i.add_move(tackle)
	var opp_i := _make_mon("MGWeatherOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i.weather = DamageCalculator.WEATHER_SANDSTORM
	bm_i.weather_duration = 10
	var weather_dmg_events_i := []
	bm_i.weather_damage.connect(func(m, amt): weather_dmg_events_i.append([m, amt]))
	bm_i.start_battle(mg_holder_i, opp_i)

	_chk("S3.01 Magic Guard holder NEVER takes weather_damage across the whole battle",
			not weather_dmg_events_i.any(func(e): return e[0] == mg_holder_i))
	_chk("S3.02 the plain opponent DOES take weather_damage (discriminator)",
			weather_dmg_events_i.any(func(e): return e[0] == opp_i))
	bm_i.queue_free()

	# (ii) Status residual: Magic Guard holder poisoned takes no status_damage.
	var mg_holder_ii := _make_mon("MGStatusHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	mg_holder_ii.ability = magic_guard
	mg_holder_ii.status = BattlePokemon.STATUS_POISON
	mg_holder_ii.add_move(tackle)
	var opp_ii := _make_mon("MGStatusOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp_ii.add_move(tackle)

	var bm_ii := _make_bm()
	var status_dmg_events_ii := []
	bm_ii.status_damage.connect(func(m, amt): status_dmg_events_ii.append([m, amt]))
	bm_ii.start_battle(mg_holder_ii, opp_ii)

	_chk("S3.03 Magic Guard holder never takes status_damage from its own poison",
			not status_dmg_events_ii.any(func(e): return e[0] == mg_holder_ii))
	bm_ii.queue_free()

	# (iii) Recoil: Magic Guard attacker using a recoil move takes no recoil_damage,
	# but still deals normal damage to the target.
	var recoil_move := MoveData.new()
	recoil_move.move_name = "TestRecoilMove"
	recoil_move.type = TypeChart.TYPE_NORMAL
	recoil_move.category = 0
	recoil_move.power = 60
	recoil_move.accuracy = 100
	recoil_move.pp = 15
	recoil_move.makes_contact = true
	recoil_move.recoil_percent = 25

	var mg_attacker_iii := _make_mon("MGRecoilAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	mg_attacker_iii.ability = magic_guard
	mg_attacker_iii.add_move(recoil_move)
	var target_iii := _make_mon("MGRecoilTarget", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	target_iii.add_move(recoil_move)

	var bm_iii := _make_bm()
	bm_iii._force_roll = 100
	bm_iii._force_crit = false
	var recoil_events_iii := []
	var move_executed_iii := []
	bm_iii.recoil_damage.connect(func(m, amt): recoil_events_iii.append([m, amt]))
	bm_iii.move_executed.connect(func(a, d, m, dmg): move_executed_iii.append([a, d, m, dmg]))
	bm_iii.start_battle(mg_attacker_iii, target_iii)

	_chk("S3.04 Magic Guard attacker never takes recoil_damage from its own recoil move",
			not recoil_events_iii.any(func(e): return e[0] == mg_attacker_iii))
	_chk("S3.05 the recoil move still dealt normal damage to the target",
			not move_executed_iii.is_empty() and move_executed_iii[0][3] > 0)
	bm_iii.queue_free()

	# (iv) Hazards: Magic Guard holder switching in over Spikes+Stealth Rock takes
	# zero hazard_damage; Toxic Spikes' poison INFLICTION still lands (not blocked),
	# but the resulting residual damage is (already covered by S2.03-06).
	var mg_holder_iv := _make_mon("MGHazardHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	mg_holder_iv.ability = magic_guard
	mg_holder_iv.add_move(tackle)
	var opp_iv := _make_mon("MGHazardOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp_iv.add_move(tackle)

	var bm_iv := _make_bm()
	bm_iv._side_conditions[0]["spikes_layers"] = 3
	bm_iv._side_conditions[0]["stealth_rock"] = true
	bm_iv._side_conditions[0]["toxic_spikes_layers"] = 1
	var hazard_dmg_events_iv := []
	var hazard_status_events_iv := []
	bm_iv.hazard_damage.connect(func(m, amt, name): hazard_dmg_events_iv.append([m, amt, name]))
	bm_iv.hazard_status_applied.connect(func(m, s): hazard_status_events_iv.append([m, s]))
	bm_iv.start_battle(mg_holder_iv, opp_iv)

	_chk("S3.06 Magic Guard holder takes zero hazard_damage from Spikes/Stealth Rock " +
			"on switch-in", hazard_dmg_events_iv.is_empty())
	_chk("S3.07 Toxic Spikes still POISONS the Magic Guard holder on switch-in " +
			"(infliction itself is not exempted, only the residual damage)",
			hazard_status_events_iv.any(func(e): return e[0] == mg_holder_iv))
	bm_iv.queue_free()

	# Discriminator: a plain Pokémon over the same hazards DOES take hazard damage.
	var plain_holder_v := _make_mon("PlainHazardHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	plain_holder_v.add_move(tackle)
	var opp_v := _make_mon("PlainHazardOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp_v.add_move(tackle)

	var bm_v := _make_bm()
	bm_v._side_conditions[0]["spikes_layers"] = 3
	var hazard_dmg_events_v := []
	bm_v.hazard_damage.connect(func(m, amt, name): hazard_dmg_events_v.append([m, amt, name]))
	bm_v.start_battle(plain_holder_v, opp_v)

	_chk("S3.08 a plain Pokémon DOES take Spikes hazard_damage (discriminator)",
			hazard_dmg_events_v.any(func(e): return e[0] == plain_holder_v))
	bm_v.queue_free()


# ── Section 4: Infiltrator — direct unit tests ───────────────────────────────

func _test_section_4_infiltrator_unit() -> void:
	var infiltrator := _load_ability(151)
	var holder := _make_mon("InfHolder", [TypeChart.TYPE_NORMAL])
	holder.ability = infiltrator
	_chk("S4.01 bypasses_infiltrator_barriers true for Infiltrator holder",
			AbilityManager.bypasses_infiltrator_barriers(holder))
	var plain := _make_mon("InfPlain", [TypeChart.TYPE_NORMAL])
	_chk("S4.02 bypasses_infiltrator_barriers false for a plain Pokémon",
			not AbilityManager.bypasses_infiltrator_barriers(plain))


# ── Section 5: Infiltrator — screens full-battle ─────────────────────────────

func _test_section_5_infiltrator_screens_full_battle() -> void:
	var infiltrator := _load_ability(151)
	var tackle := _load_move(33)

	# (i) Infiltrator attacker vs a target behind Reflect: damage NOT halved.
	var inf_atk_i := _make_mon("InfScreenAtk1", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	inf_atk_i.ability = infiltrator
	inf_atk_i.add_move(tackle)
	var target_i := _make_mon("InfScreenTarget1", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	target_i.add_move(tackle)

	var bm_i := _make_bm()
	bm_i._force_roll = 100
	bm_i._force_crit = false
	bm_i._side_conditions[1]["reflect_turns"] = 5
	var events_i := []
	bm_i.move_executed.connect(func(a, d, m, dmg): events_i.append([a, d, m, dmg]))
	bm_i.start_battle(inf_atk_i, target_i)
	_chk("S5.01 Infiltrator attacker's damage is NOT reduced by the target's Reflect",
			not events_i.is_empty() and events_i[0][0] == inf_atk_i and events_i[0][3] > 0)
	var infiltrator_dmg: int = events_i[0][3] if not events_i.is_empty() else -1
	bm_i.queue_free()

	# (ii) Discriminator: a plain attacker's identical hit against the SAME setup IS
	# halved by Reflect.
	var plain_atk_ii := _make_mon("InfScreenAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	plain_atk_ii.add_move(tackle)
	var target_ii := _make_mon("InfScreenTarget2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	target_ii.add_move(tackle)

	var bm_ii := _make_bm()
	bm_ii._force_roll = 100
	bm_ii._force_crit = false
	bm_ii._side_conditions[1]["reflect_turns"] = 5
	var events_ii := []
	bm_ii.move_executed.connect(func(a, d, m, dmg): events_ii.append([a, d, m, dmg]))
	bm_ii.start_battle(plain_atk_ii, target_ii)
	_chk("S5.02 a plain attacker's identical hit IS reduced by Reflect (discriminator)",
			not events_ii.is_empty() and events_ii[0][3] > 0 and events_ii[0][3] < infiltrator_dmg)
	bm_ii.queue_free()


# ── Section 6: Infiltrator — Substitute full-battle ──────────────────────────

func _test_section_6_infiltrator_substitute_full_battle() -> void:
	var infiltrator := _load_ability(151)
	var tackle := _load_move(33)

	# (i) Infiltrator attacker hits a Substituted target: damage lands on the REAL
	# HP directly, Substitute itself is untouched (no substitute_broke signal).
	var inf_atk_i := _make_mon("InfSubAtk1", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	inf_atk_i.ability = infiltrator
	inf_atk_i.add_move(tackle)
	var sub_target_i := _make_mon("InfSubTarget1", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	sub_target_i.add_move(tackle)
	sub_target_i.substitute_hp = 50

	var bm_i := _make_bm()
	bm_i._force_roll = 100
	bm_i._force_crit = false
	var events_i := []
	var sub_broke_i := []
	bm_i.move_executed.connect(func(a, d, m, dmg): events_i.append([a, d, m, dmg]))
	bm_i.substitute_broke.connect(func(m): sub_broke_i.append(m))
	bm_i.start_battle(inf_atk_i, sub_target_i)

	_chk("S6.01 Infiltrator's hit is reported against the real target with real damage",
			not events_i.is_empty() and events_i[0][1] == sub_target_i and events_i[0][3] > 0)
	_chk("S6.02 the Substitute itself never breaks from an Infiltrator hit " +
			"(bypassed entirely, not merely absorbed)", sub_broke_i.is_empty())
	bm_i.queue_free()

	# (ii) Discriminator: a plain attacker's identical hit against the SAME
	# Substitute setup routes through the substitute (move_executed reports the
	# substitute-absorbed chip, not full raw damage against the real Pokémon).
	var plain_atk_ii := _make_mon("InfSubAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	plain_atk_ii.add_move(tackle)
	var sub_target_ii := _make_mon("InfSubTarget2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	sub_target_ii.add_move(tackle)
	sub_target_ii.substitute_hp = 50

	var bm_ii := _make_bm()
	bm_ii._force_roll = 100
	bm_ii._force_crit = false
	var sub_broke_ii := []
	bm_ii.substitute_broke.connect(func(m): sub_broke_ii.append(m))
	bm_ii.start_battle(plain_atk_ii, sub_target_ii)

	_chk("S6.03 a plain attacker's hit against the same Substitute setup CAN break " +
			"it (discriminator confirming the Substitute was actually up)",
			not sub_broke_ii.is_empty())
	bm_ii.queue_free()


# ── Section 7: Magic Bounce — direct unit tests ──────────────────────────────

func _test_section_7_magic_bounce_unit() -> void:
	var growl := _load_move(45)
	var defender := _make_mon("MBDefender1", [TypeChart.TYPE_NORMAL])
	defender.ability = _load_ability(156)
	var attacker := _make_mon("MBAttacker1", [TypeChart.TYPE_NORMAL])

	_chk("S7.01 bounces_status_move true for a Magic Bounce holder vs a plain attacker",
			AbilityManager.bounces_status_move(defender, false, attacker, growl))

	var mb_attacker := _make_mon("MBAttacker2", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = _load_ability(104)  # Mold Breaker
	_chk("S7.02 bounces_status_move false when the attacker has Mold Breaker " +
			"(Magic Bounce IS breakable, source-confirmed)",
			not AbilityManager.bounces_status_move(defender, false, mb_attacker, growl))

	_chk("S7.03 bounces_status_move false when Neutralizing Gas is active",
			not AbilityManager.bounces_status_move(defender, true, attacker, growl))

	var plain_defender := _make_mon("MBPlainDefender", [TypeChart.TYPE_NORMAL])
	_chk("S7.04 bounces_status_move false for a plain (non-Magic-Bounce) defender",
			not AbilityManager.bounces_status_move(plain_defender, false, attacker, growl))


# ── Section 8: Magic Bounce — full-battle reflection ─────────────────────────

func _test_section_8_magic_bounce_full_battle() -> void:
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var encore := _load_move(227)
	var magic_bounce := _load_ability(156)

	# (i) Growl (bounceable) used against a Magic Bounce holder: the holder's OWN
	# Attack is unaffected; the ORIGINAL ATTACKER's Attack drops instead.
	var atk_i := _make_mon("MBBattleAtk1", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	atk_i.add_move(growl)
	var holder_i := _make_mon("MBBattleHolder1", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	holder_i.ability = magic_bounce
	# Harmless Tackle (not Growl) — isolates this scenario to exactly ONE bounceable
	# move in play this turn (the attacker's Growl), so the holder's own move can't
	# introduce a second, independent stat_stage_changed event.
	holder_i.add_move(tackle)

	var bm_i := _make_bm()
	var stat_events_i := []
	var bounced_events_i := []
	bm_i.stat_stage_changed.connect(func(t, s, a): stat_events_i.append([t, s, a]))
	bm_i.move_bounced.connect(func(h, nt): bounced_events_i.append([h, nt]))
	bm_i.start_battle(atk_i, holder_i)

	_chk("S8.01 move_bounced fired with the Magic Bounce holder as holder and the " +
			"original attacker as new_target",
			not bounced_events_i.is_empty() and bounced_events_i[0][0] == holder_i
					and bounced_events_i[0][1] == atk_i)
	_chk("S8.02 the FIRST stat_stage_changed lands on the ORIGINAL ATTACKER, not the " +
			"Magic Bounce holder",
			not stat_events_i.is_empty() and stat_events_i[0][0] == atk_i)
	_chk("S8.03 the Magic Bounce holder's own Attack is never lowered by its own " +
			"reflected Growl", not stat_events_i.any(func(e): return e[0] == holder_i))
	bm_i.queue_free()

	# (ii) Discriminator: a damaging move against the same holder is NOT bounced —
	# it just hits the holder normally.
	var atk_ii := _make_mon("MBBattleAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk_ii.add_move(tackle)
	var holder_ii := _make_mon("MBBattleHolder2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 20)
	holder_ii.ability = magic_bounce
	holder_ii.add_move(tackle)

	var bm_ii := _make_bm()
	bm_ii._force_roll = 100
	bm_ii._force_crit = false
	var bounced_events_ii := []
	var move_events_ii := []
	bm_ii.move_bounced.connect(func(h, nt): bounced_events_ii.append([h, nt]))
	bm_ii.move_executed.connect(func(a, d, m, dmg): move_events_ii.append([a, d, m, dmg]))
	bm_ii.start_battle(atk_ii, holder_ii)

	_chk("S8.04 a damaging move is NEVER bounced by Magic Bounce", bounced_events_ii.is_empty())
	_chk("S8.05 the damaging move landed normally on the Magic Bounce holder",
			not move_events_ii.is_empty() and move_events_ii[0][1] == holder_ii
					and move_events_ii[0][3] > 0)
	bm_ii.queue_free()

	# (iii) Discriminator: a foe-targeting status move NOT in this project's
	# bounceable subset (Encore — confirmed absent from source's
	# magicCoatAffected=TRUE table) is NOT bounced; it lands on the holder normally.
	var atk_iii := _make_mon("MBBattleAtk3", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	atk_iii.add_move(tackle)
	atk_iii.add_move(encore)
	var holder_iii := _make_mon("MBBattleHolder3", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	holder_iii.ability = magic_bounce
	holder_iii.add_move(tackle)
	holder_iii.last_move_used = tackle

	var bm_iii := _make_bm()
	bm_iii._force_hit = true
	bm_iii.queue_move(0, 1)  # force attacker to use Encore (index 1) on turn 1
	var bounced_events_iii := []
	var encored_events_iii := []
	bm_iii.move_bounced.connect(func(h, nt): bounced_events_iii.append([h, nt]))
	bm_iii.encored.connect(func(m, mv): encored_events_iii.append([m, mv]))
	bm_iii.start_battle(atk_iii, holder_iii)

	_chk("S8.06 Encore (not in the bounceable subset) is never reflected",
			bounced_events_iii.is_empty())
	_chk("S8.07 Encore still applied normally to the Magic Bounce holder",
			not encored_events_iii.is_empty() and encored_events_iii[0][0] == holder_iii)
	bm_iii.queue_free()


# ── Section 9: Magic Bounce — Mold Breaker bypass ────────────────────────────

func _test_section_9_magic_bounce_mold_breaker() -> void:
	var growl := _load_move(45)
	var mold_breaker := _load_ability(104)
	var magic_bounce := _load_ability(156)

	var mb_atk := _make_mon("MBMoldBreakerAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	mb_atk.ability = mold_breaker
	mb_atk.add_move(growl)
	var mb_holder := _make_mon("MBMoldBreakerHolder", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	mb_holder.ability = magic_bounce
	mb_holder.add_move(growl)

	var bm := _make_bm()
	var stat_events := []
	var bounced_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.move_bounced.connect(func(h, nt): bounced_events.append([h, nt]))
	bm.start_battle(mb_atk, mb_holder)

	_chk("S9.01 a Mold-Breaker attacker's Growl is NOT bounced by Magic Bounce",
			bounced_events.is_empty())
	_chk("S9.02 the Magic Bounce holder's own Attack DOES drop (move landed normally)",
			not stat_events.is_empty() and stat_events[0][0] == mb_holder)
	bm.queue_free()


# ── Section 10: Magic Bounce vs Magic Bounce — only one bounce ever ──────────

func _test_section_10_magic_bounce_vs_magic_bounce() -> void:
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var magic_bounce := _load_ability(156)

	# atk's HP is set deliberately very low: since neither mon has more than one
	# move, CLAUDE.md's own auto-select-fallback-to-moves[0] convention means BOTH
	# Growl and Tackle would otherwise re-fire every subsequent turn, accumulating
	# multiple unrelated move_bounced events across many turns (not "the same move
	# bouncing twice") and making a bare bounced_events.size() check meaningless.
	# Ending the battle after exactly one turn (holder's Tackle KOs atk) isolates
	# this to the one exchange actually under test.
	var atk := _make_mon("MBvMBAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	atk.ability = magic_bounce
	atk.add_move(growl)
	atk.current_hp = 10  # guarantees holder's single Tackle one-shots it this turn
	var holder := _make_mon("MBvMBHolder", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	holder.ability = magic_bounce
	# Harmless Tackle, not Growl — isolates this to exactly ONE bounceable move in
	# play this turn (the attacker's Growl); otherwise the holder's own independent
	# Growl would ALSO get reflected back at the (also-Magic-Bounce-holding)
	# attacker, producing a second, unrelated move_bounced event that would make
	# this "only one bounce ever" test unfalsifiable.
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm._force_hit = true
	var stat_events := []
	var bounced_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.move_bounced.connect(func(h, nt): bounced_events.append([h, nt]))
	bm.start_battle(atk, holder)

	_chk("S10.01 exactly ONE move_bounced fires this turn, not two (no re-bounce loop)",
			bounced_events.size() == 1)
	_chk("S10.02 the bounced Growl lands on the ORIGINAL ATTACKER (whose own Magic " +
			"Bounce does not get a second chance to reflect it back again)",
			not stat_events.is_empty() and stat_events[0][0] == atk)
	_chk("S10.03 the original holder's own Attack is never lowered",
			not stat_events.any(func(e): return e[0] == holder))
	bm.queue_free()


# ── Section 11: Magic Bounce + Prankster + Dark-type interaction ────────────

func _test_section_11_magic_bounce_prankster_dark() -> void:
	var thunder_wave := _load_move(86)
	var prankster := _load_ability(158)
	var magic_bounce := _load_ability(156)

	# (i) Prankster attacker's Thunder Wave against a DARK-type Magic Bounce holder:
	# bounces (Magic Bounce takes priority over the Dark-Prankster-immunity gate)
	# rather than simply failing.
	var atk_i := _make_mon("PranksterAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk_i.ability = prankster
	atk_i.add_move(thunder_wave)
	var holder_i := _make_mon("DarkMBHolder1", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 20)
	holder_i.ability = magic_bounce
	holder_i.add_move(thunder_wave)

	var bm_i := _make_bm()
	bm_i._force_hit = true
	var bounced_events_i := []
	var failed_events_i := []
	var secondary_events_i := []
	bm_i.move_bounced.connect(func(h, nt): bounced_events_i.append([h, nt]))
	bm_i.move_effect_failed.connect(func(t, r): failed_events_i.append([t, r]))
	bm_i.secondary_applied.connect(func(t, e): secondary_events_i.append([t, e]))
	bm_i.start_battle(atk_i, holder_i)

	_chk("S11.01 the Prankster'd Thunder Wave bounces off the Dark-type Magic Bounce " +
			"holder instead of failing", not bounced_events_i.is_empty())
	_chk("S11.02 it does NOT fail as prankster_dark_immune (Magic Bounce took " +
			"priority over that gate)",
			not failed_events_i.any(func(e): return e[1] == "prankster_dark_immune"))
	_chk("S11.03 the reflected Thunder Wave successfully paralyzes the ORIGINAL " +
			"ATTACKER", secondary_events_i.any(
					func(e): return e[0] == atk_i and e[1] == MoveData.SE_PARALYSIS))
	bm_i.queue_free()

	# (ii) Discriminator: the SAME Prankster'd Thunder Wave against a Dark-type
	# target WITHOUT Magic Bounce correctly fails outright (Dark immunity applies).
	var atk_ii := _make_mon("PranksterAtk2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk_ii.ability = prankster
	atk_ii.add_move(thunder_wave)
	var dark_plain_ii := _make_mon("DarkPlain2", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 20)
	dark_plain_ii.add_move(thunder_wave)

	var bm_ii := _make_bm()
	bm_ii._force_hit = true
	var failed_events_ii := []
	var bounced_events_ii := []
	bm_ii.move_effect_failed.connect(func(t, r): failed_events_ii.append([t, r]))
	bm_ii.move_bounced.connect(func(h, nt): bounced_events_ii.append([h, nt]))
	bm_ii.start_battle(atk_ii, dark_plain_ii)

	_chk("S11.04 without Magic Bounce, the Prankster'd Thunder Wave DOES fail as " +
			"prankster_dark_immune (discriminator)",
			failed_events_ii.any(func(e): return e[1] == "prankster_dark_immune"))
	_chk("S11.05 and it never bounces (no Magic Bounce present)", bounced_events_ii.is_empty())
	bm_ii.queue_free()


# ── Section 12: Neutralizing Gas suppression ─────────────────────────────────

func _test_section_12_neutralizing_gas_suppression() -> void:
	var magic_guard := _load_ability(98)
	var infiltrator := _load_ability(151)

	var mg_mon := _make_mon("NGMagicGuard", [TypeChart.TYPE_NORMAL])
	mg_mon.ability = magic_guard
	_chk("S12.01 Magic Guard suppressed by Neutralizing Gas: blocks_indirect_damage false",
			not AbilityManager.blocks_indirect_damage(mg_mon, true))

	var inf_mon := _make_mon("NGInfiltrator", [TypeChart.TYPE_NORMAL])
	inf_mon.ability = infiltrator
	_chk("S12.02 Infiltrator suppressed by Neutralizing Gas: bypasses_infiltrator_barriers false",
			not AbilityManager.bypasses_infiltrator_barriers(inf_mon, true))

	# S7.03 already covers Magic Bounce's own NG suppression directly; recorded here
	# for section-grouping completeness rather than re-testing the same call.
	var mb_mon := _make_mon("NGMagicBounce", [TypeChart.TYPE_NORMAL])
	mb_mon.ability = _load_ability(156)
	var atk_ng := _make_mon("NGAtk", [TypeChart.TYPE_NORMAL])
	var growl_ng := _load_move(45)
	_chk("S12.03 Magic Bounce suppressed by Neutralizing Gas: bounces_status_move false",
			not AbilityManager.bounces_status_move(mb_mon, true, atk_ng, growl_ng))


# ── Section 13: Negative control ─────────────────────────────────────────────

func _test_section_13_negative_control() -> void:
	var plain_atk := _make_mon("NegCtrlAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	plain_atk.add_move(_load_move(45))  # Growl
	var plain_def := _make_mon("NegCtrlDef", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	plain_def.add_move(_load_move(45))

	var bm := _make_bm()
	var stat_events := []
	var bounced_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.move_bounced.connect(func(h, nt): bounced_events.append([h, nt]))
	bm.start_battle(plain_atk, plain_def)

	_chk("S13.01 two plain Pokémon: Growl is never bounced", bounced_events.is_empty())
	_chk("S13.02 two plain Pokémon: Growl lowers the DEFENDER's Attack as normal",
			not stat_events.is_empty() and stat_events[0][0] == plain_def)
	bm.queue_free()

	_chk("S13.03 blocks_indirect_damage false for a plain Pokémon (no ability at all)",
			not AbilityManager.blocks_indirect_damage(_make_mon("NegCtrlPlain1", [TypeChart.TYPE_NORMAL])))
	_chk("S13.04 bypasses_infiltrator_barriers false for a plain Pokémon",
			not AbilityManager.bypasses_infiltrator_barriers(_make_mon("NegCtrlPlain2", [TypeChart.TYPE_NORMAL])))
