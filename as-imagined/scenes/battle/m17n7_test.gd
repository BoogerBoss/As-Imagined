extends Node

# M17n-7 test suite — Group 6: item/berry interaction abilities: Klutz, Unnerve,
# Gluttony, Unburden, Harvest, Cud Chew.
#
# Scope: the 6 abilities queued as "next" at the end of [M17n-6]'s decisions.md entry.
# Step 0 re-verified all six IDs directly against include/constants/abilities.h — no
# corrections needed (Gluttony=82, Unburden=84, Klutz=103, Unnerve=127, Harvest=139,
# Cud Chew=291). This tier finally builds the "last consumed berry" tracking [M17d]
# deferred twice (`BattlePokemon.last_consumed_berry`), reusing the party-state-scoped
# (not volatiles-struct-scoped) shape of source's own `usedHeldItem` field.
#
# Klutz    — the holder's OWN held item has no effect anywhere. Source:
#   GetBattlerHoldEffectInternal (battle_util.c L5674-5692) — the single chokepoint
#   every held-item read funnels through. `ItemManager.effective_held_item` mirrors
#   this exactly; every other ItemManager function already reads through it.
# Unnerve  — prevents ALL opposing Pokémon from eating berries at all (not just resist
#   berries). Source: `IsUnnerveBlocked` (battle_util.c L333-345) is gated at the very
#   top of `ItemBattleEffects` (battle_hold_effects.c L1035-1048) — the single dispatcher
#   for EVERY hold-effect-triggered berry mechanic (Sitrus, Lum, resist berries, Micle,
#   stat-raise berries), not just the one `GetDefenderItemsModifier` call site this
#   project's resist-berry function already uses.
# Gluttony — for a berry whose normal eat-early fraction is ≤4 (25%-or-stricter), the
#   holder eats it at 50% HP instead. Source: `HasEnoughHpToEatBerry` (battle_util.c
#   L5461-5476). Confirmed a no-op for every berry this project currently implements
#   (Sitrus's own fraction is hardcoded to 2/50% regardless of ability) — wired in
#   generically so it composes correctly the instant a stricter-fraction berry exists.
# Unburden — Speed ×2, unconditional, while active. Source: battle_main.c L4686-4687
#   (the same unconditional-on-weather shape as Slow Start's own check immediately
#   above it). Activated the moment the holder's own item is removed by ANY means
#   (`CheckSetUnburden`, called from every item-removal site).
# Harvest  — end-of-turn chance (flat 50%, GUARANTEED in sun) to regenerate the last
#   consumed berry back onto the holder. Source: `AbilityBattleEffects`'s
#   `ABILITY_HARVEST` case (battle_util.c L3531-3539).
# Cud Chew — a one-turn arm/fire cycle: arms at the end of the turn a berry is eaten,
#   fires (re-runs that SAME berry's effect, never restoring the physical item) at the
#   NEXT end of turn. Source: `AbilityBattleEffects`'s `ABILITY_CUD_CHEW` case
#   (battle_util.c L3695-3707).
#
# A real bug was found and fixed during this session's verification pass (not present
# in the original crashed session's work as inherited — corrected here): Cud Chew's
# fire re-trigger sets `gBattleScripting.overrideBerryRequirements`
# (`BattleScript_CudChewActivates`, data/battle_scripts_1.s L4020-4026), and BOTH
# `HasEnoughHpToEatBerry` (battle_util.c L5465: returns TRUE unconditionally under the
# override flag) and `IsUnnerveBlocked` (battle_util.c L338-339: returns FALSE
# unconditionally under the same flag) key off it — meaning Cud Chew's re-trigger
# bypasses BOTH the normal HP-threshold gate AND an opposing Unnerve holder, not just
# reuse the same gated check a second time. `ItemManager.sitrus_berry_heal`/
# `lum_berry_cures` were fixed to skip both gates when `override_item` is provided,
# reproducing only the one exception `ItemHealHp` itself still enforces even under
# override (battle_hold_effects.c L831: no heal at exactly full HP). See Section 10
# below for the discriminating tests that would have caught this.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state (Harvest/Cud Chew's regenerate/re-heal
#     events are captured via `item_regenerated`/`ability_triggered`, never read from
#     `mon.held_item`/`mon.cud_chew_armed` after `start_battle()` returns, since the
#     arm→fire→clear cycle keeps advancing for as long as the battle continues).
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing function.
#   - Type immunity precedes ability logic: all scenarios below use same-type (Normal
#     vs Normal) neutral matchups, since none of this tier's mechanics are type-gated.
#
# Ground truth: pokeemerald_expansion src/battle_util.c :: GetBattlerHoldEffectInternal
#   (L5674), IsUnnerveBlocked/IsUnnerveAbilityOnOpposingSide (L333-363),
#   HasEnoughHpToEatBerry (L5461), AbilityBattleEffects's ABILITY_HARVEST (L3531) and
#   ABILITY_CUD_CHEW (L3695) cases; src/battle_main.c (L4686-4687) — Unburden Speed;
#   src/battle_hold_effects.c :: ItemBattleEffects (L1035), ItemHealHp (L826),
#   TryCureAnyStatus (L764); data/battle_scripts_1.s :: BattleScript_CudChewActivates
#   (L4020-4026); include/battle.h :: struct PartyState (L530-544, `usedHeldItem`).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_klutz_unit()
	_test_section_3_klutz_full_battle()
	_test_section_4_unnerve_unit()
	_test_section_5_unnerve_full_battle()
	_test_section_6_gluttony_unit()
	_test_section_7_unburden_unit_and_full_battle()
	_test_section_8_harvest_unit_and_full_battle()
	_test_section_9_cud_chew_arm_fire_unit()
	_test_section_10_cud_chew_override_bypass_fix()
	_test_section_11_cud_chew_full_battle()
	_test_section_12_neutralizing_gas_suppression()
	_test_section_13_negative_control()

	var total := _pass + _fail
	print("m17n7_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0, name: String = "") -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	if name != "":
		item.item_name = name
	return item


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


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var gluttony := _load_ability(82)
	_chk("S1.01 Gluttony id=82", gluttony.ability_id == 82)

	var unburden := _load_ability(84)
	_chk("S1.02 Unburden id=84", unburden.ability_id == 84)

	var klutz := _load_ability(103)
	_chk("S1.03 Klutz id=103", klutz.ability_id == 103)

	var unnerve := _load_ability(127)
	_chk("S1.04 Unnerve id=127", unnerve.ability_id == 127)

	var harvest := _load_ability(139)
	_chk("S1.05 Harvest id=139", harvest.ability_id == 139)

	var cud_chew := _load_ability(291)
	_chk("S1.06 Cud Chew id=291", cud_chew.ability_id == 291)

	_chk("S1.07 none of the six carry breakable/cant_be_suppressed " +
			"(source-verified, none of them are Mold-Breaker/Neutralizing-Gas exemptions)",
			not gluttony.breakable and not gluttony.cant_be_suppressed and
			not unburden.breakable and not unburden.cant_be_suppressed and
			not klutz.breakable and not klutz.cant_be_suppressed and
			not unnerve.breakable and not unnerve.cant_be_suppressed and
			not harvest.breakable and not harvest.cant_be_suppressed and
			not cud_chew.breakable and not cud_chew.cant_be_suppressed)


# ── Section 2: Klutz — direct unit tests ─────────────────────────────────────

func _test_section_2_klutz_unit() -> void:
	var klutz := _load_ability(103)
	var band := _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var tackle := _load_move(33)

	# (i) effective_held_item returns null for a Klutz holder regardless of the item.
	var holder_i := _make_mon("KlutzMon1", [TypeChart.TYPE_NORMAL])
	holder_i.ability = klutz
	holder_i.held_item = band
	_chk("S2.01 effective_held_item is null for a Klutz holder",
			ItemManager.effective_held_item(holder_i) == null)
	_chk("S2.02 a non-Klutz holder's item is unaffected",
			ItemManager.effective_held_item(_make_mon_with_item("Plain1", band)) == band)

	# (ii) Choice-lock detection is also suppressed — a Klutz holder wielding a Choice
	# item is NOT choice-locked (source: CheckMoveLimitations's IsHoldEffectChoice
	# reads the same GetBattlerHoldEffect chokepoint).
	_chk("S2.03 is_choice_item is false for a Klutz holder wielding Choice Band",
			not ItemManager.is_choice_item(holder_i))

	# (iii) The attack-stat modifier (Choice Band's own ×1.5) is also suppressed.
	_chk("S2.04 attack_modifier_uq412 is 4096 (no boost) for a Klutz holder with Choice Band",
			ItemManager.attack_modifier_uq412(holder_i, tackle) == 4096)

	# (iv) A non-Klutz holder with the same item DOES get the boost (discriminator).
	var plain_ii := _make_mon("KlutzMon2", [TypeChart.TYPE_NORMAL])
	plain_ii.held_item = band
	_chk("S2.05 attack_modifier_uq412 IS boosted for a non-Klutz holder with Choice Band",
			ItemManager.attack_modifier_uq412(plain_ii, tackle) == ItemManager.UQ412_CHOICE_MULT)


func _make_mon_with_item(mon_name: String, item: ItemData) -> BattlePokemon:
	var m := _make_mon(mon_name, [TypeChart.TYPE_NORMAL])
	m.held_item = item
	return m


# ── Section 3: Klutz — full-battle integration ───────────────────────────────
# A Klutz holder's Sitrus Berry must never trigger, no matter how low its HP goes.

func _test_section_3_klutz_full_battle() -> void:
	var tackle := _load_move(33)
	var klutz := _load_ability(103)

	var attacker := _make_mon("KlutzBattleAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	attacker.add_move(tackle)
	var holder := _make_mon("KlutzBattleHolder", [TypeChart.TYPE_NORMAL], 100, 60, 100, 60, 100, 20)
	holder.ability = klutz
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	holder.current_hp = 82  # just above max_hp/2=80 — one hit crosses the threshold
	holder.add_move(tackle)

	var bm := _make_bm()
	var consume_events := []
	bm.item_consumed.connect(func(m, _i): consume_events.append(m))
	bm.start_battle(attacker, holder)

	_chk("S3.01 Klutz holder's Sitrus Berry never consumed despite crossing the HP threshold",
			not consume_events.any(func(m): return m == holder))
	_chk("S3.02 Klutz holder's held_item is still the Sitrus Berry",
			holder.held_item != null and holder.held_item.item_name == "Sitrus Berry")

	bm.queue_free()


# ── Section 4: Unnerve — direct unit tests ───────────────────────────────────

func _test_section_4_unnerve_unit() -> void:
	var unnerve := _load_ability(127)
	var intimidate := _load_ability(22)

	# (i) An opponent holding Unnerve is detected.
	var opp_i := _make_mon("UnnerveOpp1", [TypeChart.TYPE_NORMAL])
	opp_i.ability = unnerve
	_chk("S4.01 is_unnerve_active true when an opponent holds Unnerve",
			AbilityManager.is_unnerve_active([opp_i]))

	# (ii) A non-Unnerve opponent: false.
	var opp_ii := _make_mon("UnnerveOpp2", [TypeChart.TYPE_NORMAL])
	opp_ii.ability = intimidate
	_chk("S4.02 is_unnerve_active false with a non-Unnerve opponent",
			not AbilityManager.is_unnerve_active([opp_ii]))

	# (iii) A fainted Unnerve holder does not count.
	var opp_iii := _make_mon("UnnerveOpp3", [TypeChart.TYPE_NORMAL])
	opp_iii.ability = unnerve
	opp_iii.fainted = true
	_chk("S4.03 is_unnerve_active false when the Unnerve holder has fainted",
			not AbilityManager.is_unnerve_active([opp_iii]))

	# (iv) A null entry (singles has no ally slot) is skipped without crashing.
	_chk("S4.04 is_unnerve_active handles a null opponent slot",
			not AbilityManager.is_unnerve_active([null]))

	# (v) Doubles: Unnerve on EITHER opposing slot is enough.
	var opp_v_a := _make_mon("UnnerveOpp5A", [TypeChart.TYPE_NORMAL])
	var opp_v_b := _make_mon("UnnerveOpp5B", [TypeChart.TYPE_NORMAL])
	opp_v_b.ability = unnerve
	_chk("S4.05 is_unnerve_active true if either opposing slot holds it (doubles)",
			AbilityManager.is_unnerve_active([opp_v_a, opp_v_b]))


# ── Section 5: Unnerve — full-battle integration ─────────────────────────────
# Unnerve blocks ALL berry effects on the opposing side (ItemBattleEffects' own top
# gate), not just resist berries — confirmed here with a Sitrus Berry.

func _test_section_5_unnerve_full_battle() -> void:
	var tackle := _load_move(33)
	var unnerve := _load_ability(127)

	var attacker := _make_mon("UnnerveBattleAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	attacker.ability = unnerve
	attacker.add_move(tackle)
	var defender := _make_mon("UnnerveBattleDef", [TypeChart.TYPE_NORMAL], 100, 60, 100, 60, 100, 20)
	defender.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	defender.current_hp = 82
	defender.add_move(tackle)

	var bm := _make_bm()
	var consume_events := []
	bm.item_consumed.connect(func(m, _i): consume_events.append(m))
	bm.start_battle(attacker, defender)

	_chk("S5.01 defender's Sitrus Berry never consumed while the opponent holds Unnerve",
			not consume_events.any(func(m): return m == defender))
	_chk("S5.02 defender's held_item is still the Sitrus Berry",
			defender.held_item != null and defender.held_item.item_name == "Sitrus Berry")

	bm.queue_free()


# ── Section 6: Gluttony — direct unit tests ──────────────────────────────────
# Confirmed a no-op for every currently-implemented berry (Sitrus's fraction is
# hardcoded to 2 regardless of ability) — tested directly against the function's own
# contract rather than via an unreachable full-battle scenario.

func _test_section_6_gluttony_unit() -> void:
	var gluttony := _load_ability(82)
	var intimidate := _load_ability(22)

	var mon_i := _make_mon("GlutMon1", [TypeChart.TYPE_NORMAL])
	mon_i.ability = gluttony
	_chk("S6.01 Gluttony widens a fraction of 4 (25%) up to 2 (50%)",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_i, 4) == 2)
	_chk("S6.02 Gluttony widens a fraction of 3 up to 2",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_i, 3) == 2)
	_chk("S6.03 Gluttony leaves a fraction of 2 (50%) unchanged — already at the target",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_i, 2) == 2)
	_chk("S6.04 Gluttony does NOT narrow a fraction looser than 4 (e.g. 5/20%)",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_i, 5) == 5)

	var mon_ii := _make_mon("GlutMon2", [TypeChart.TYPE_NORMAL])
	mon_ii.ability = intimidate
	_chk("S6.05 a non-Gluttony holder's fraction is unaffected",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_ii, 4) == 4)


# ── Section 7: Unburden — direct unit test + full-battle turn-order flip ────

func _test_section_7_unburden_unit_and_full_battle() -> void:
	var unburden := _load_ability(84)
	var tackle := _load_move(33)

	# Direct: effective_speed doubles once unburden_active is set, not merely equipped.
	var mon := _make_mon("UnburdenMon", [TypeChart.TYPE_NORMAL], 100, 80, 80, 80, 80, 60)
	mon.ability = unburden
	var base_speed: int = StatusManager.effective_speed(mon)
	_chk("S7.01 effective_speed unaffected before unburden_active is set",
			base_speed == mon.speed)
	mon.unburden_active = true
	_chk("S7.02 effective_speed doubled once unburden_active is set",
			StatusManager.effective_speed(mon) == base_speed * 2)

	# Full battle: defender is naturally slower (60 < 100); once its held Sitrus Berry
	# is consumed (crossing the HP threshold on turn 1), Unburden should make it
	# faster than the attacker starting turn 2.
	var fast_atk := _make_mon("UBBattleAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	fast_atk.add_move(tackle)
	var ub_holder := _make_mon("UBBattleHolder", [TypeChart.TYPE_NORMAL], 100, 60, 80, 60, 80, 60)
	ub_holder.ability = unburden
	ub_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	ub_holder.current_hp = 82
	ub_holder.add_move(tackle)

	var bm := _make_bm()
	var move_events := []
	bm.move_executed.connect(func(a, d, m, dmg): move_events.push_back([a, d, m, dmg]))
	bm.start_battle(fast_atk, ub_holder)

	_chk("S7.03 turn 1: naturally-faster attacker acts first (Unburden not active yet)",
			move_events.size() >= 1 and move_events[0][0] == fast_atk)
	_chk("S7.04 turn 2: Unburden holder (now 2x Speed) acts first",
			move_events.size() >= 3 and move_events[2][0] == ub_holder)
	_chk("S7.05 Unburden holder's item was actually removed (Sitrus consumed) by turn 2",
			ub_holder.held_item == null or ub_holder.held_item.item_name != "Sitrus Berry")

	bm.queue_free()


# ── Section 8: Harvest — direct unit tests + full-battle integration ────────

func _test_section_8_harvest_unit_and_full_battle() -> void:
	var harvest := _load_ability(139)
	var berry := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")

	# (i) No-ops: wrong ability, item still held, no berry ever consumed.
	var mon_i := _make_mon("HarvMon1", [TypeChart.TYPE_NORMAL])
	_chk("S8.01 harvest_activates false without the ability",
			not AbilityManager.harvest_activates(mon_i))

	var mon_ii := _make_mon("HarvMon2", [TypeChart.TYPE_NORMAL])
	mon_ii.ability = harvest
	mon_ii.held_item = berry
	mon_ii.last_consumed_berry = berry
	_chk("S8.02 harvest_activates false while still holding an item",
			not AbilityManager.harvest_activates(mon_ii))

	var mon_iii := _make_mon("HarvMon3", [TypeChart.TYPE_NORMAL])
	mon_iii.ability = harvest
	_chk("S8.03 harvest_activates false with no last_consumed_berry",
			not AbilityManager.harvest_activates(mon_iii))

	# (ii) Sun guarantees the proc regardless of the 50% roll.
	var mon_iv := _make_mon("HarvMon4", [TypeChart.TYPE_NORMAL])
	mon_iv.ability = harvest
	mon_iv.last_consumed_berry = berry
	_chk("S8.04 harvest_activates guaranteed true in sun (no forced_roll needed)",
			AbilityManager.harvest_activates(mon_iv, DamageCalculator.WEATHER_SUN))

	# (iii) forced_roll seam (mirrors quick_draw_activates' established shape).
	var mon_v := _make_mon("HarvMon5", [TypeChart.TYPE_NORMAL])
	mon_v.ability = harvest
	mon_v.last_consumed_berry = berry
	_chk("S8.05 harvest_activates respects forced_roll=true outside sun",
			AbilityManager.harvest_activates(mon_v, DamageCalculator.WEATHER_NONE, false, true))
	_chk("S8.06 harvest_activates respects forced_roll=false outside sun",
			not AbilityManager.harvest_activates(mon_v, DamageCalculator.WEATHER_NONE, false, false))

	# Full battle: berry consumed on turn 1, Harvest guaranteed (forced) to regenerate
	# it at turn 1's end-of-turn.
	var tackle := _load_move(33)
	var attacker := _make_mon("HarvBattleAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	attacker.add_move(tackle)
	var holder := _make_mon("HarvBattleHolder", [TypeChart.TYPE_NORMAL], 100, 60, 100, 60, 100, 20)
	holder.ability = harvest
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	holder.current_hp = 82
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_harvest_roll = true
	var regen_events := []
	bm.item_regenerated.connect(func(m, i): regen_events.append([m, i]))
	bm.start_battle(attacker, holder)

	_chk("S8.07 item_regenerated fired for the Harvest holder",
			regen_events.any(func(e): return e[0] == holder and e[1] != null and e[1].item_name == "Sitrus Berry"))

	bm.queue_free()


# ── Section 9: Cud Chew — arm/fire cycle direct unit tests ──────────────────

func _test_section_9_cud_chew_arm_fire_unit() -> void:
	var cud_chew := _load_ability(291)
	var berry := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")

	# (i) No-op without the ability.
	var mon_i := _make_mon("CCMon1", [TypeChart.TYPE_NORMAL])
	mon_i.last_consumed_berry = berry
	_chk("S9.01 cud_chew_check returns \"\" without the ability",
			AbilityManager.cud_chew_check(mon_i) == "")

	# (ii) No-op with the ability but nothing consumed yet.
	var mon_ii := _make_mon("CCMon2", [TypeChart.TYPE_NORMAL])
	mon_ii.ability = cud_chew
	_chk("S9.02 cud_chew_check returns \"\" with nothing consumed",
			AbilityManager.cud_chew_check(mon_ii) == "")

	# (iii) Arms the turn after a berry is consumed.
	var mon_iii := _make_mon("CCMon3", [TypeChart.TYPE_NORMAL])
	mon_iii.ability = cud_chew
	mon_iii.last_consumed_berry = berry
	_chk("S9.03 cud_chew_check returns \"arm\" once a berry has been consumed",
			AbilityManager.cud_chew_check(mon_iii) == "arm")

	# (iv) Fires (does not re-arm) once already armed.
	mon_iii.cud_chew_armed = true
	_chk("S9.04 cud_chew_check returns \"fire\" once already armed",
			AbilityManager.cud_chew_check(mon_iii) == "fire")

	# (v) The if/else-if shape means arm and fire can never happen in the same check —
	# a freshly-armed mon (armed just became true) does not ALSO report "arm" again.
	_chk("S9.05 arm and fire are mutually exclusive on a single check",
			AbilityManager.cud_chew_check(mon_iii) != "arm")


# ── Section 10: Cud Chew's fire re-trigger bypasses BOTH the HP threshold AND ──
# ── Unnerve — the bug found and fixed during this session's verification pass ─
#
# Source: BattleScript_CudChewActivates sets gBattleScripting.overrideBerryRequirements
# around its re-trigger; HasEnoughHpToEatBerry (L5465) and IsUnnerveBlocked (L338-339)
# both key off that exact flag. Confirmed here directly against ItemManager, since a
# full-battle scenario can't reliably force "Unnerve switched in between arm and fire"
# or "HP recovered above threshold between arm and fire" deterministically.

func _test_section_10_cud_chew_override_bypass_fix() -> void:
	var berry := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	var lum := _make_item(ItemManager.HOLD_EFFECT_CURE_STATUS, 0, "Lum Berry")

	# (i) HP-threshold bypass: mon is well ABOVE the normal 50% threshold (would
	# normally return 0), but override_item is set — heal must still fire.
	var mon_i := _make_mon("CCFixMon1", [TypeChart.TYPE_NORMAL], 100)  # max_hp=160
	mon_i.current_hp = 159  # not full, but nowhere near ≤80 (=max_hp/2)
	_chk("S10.01 sitrus_berry_heal bypasses the HP threshold when override_item is set",
			ItemManager.sitrus_berry_heal(mon_i, false, false, berry) == 40)
	# Discriminator: the exact same HP, WITHOUT override_item, correctly returns 0 —
	# proves S10.01 wasn't vacuously true.
	mon_i.held_item = berry
	_chk("S10.02 discriminator: the same HP without override_item correctly returns 0",
			ItemManager.sitrus_berry_heal(mon_i) == 0)

	# (ii) Full-HP exemption still holds even under override (source's one carve-out).
	var mon_ii := _make_mon("CCFixMon2", [TypeChart.TYPE_NORMAL], 100)
	mon_ii.current_hp = mon_ii.max_hp
	_chk("S10.03 sitrus_berry_heal still returns 0 at exactly full HP, even with override_item",
			ItemManager.sitrus_berry_heal(mon_ii, false, false, berry) == 0)

	# (iii) Unnerve bypass: unnerve_active=true would normally block the heal entirely,
	# but override_item makes it fire anyway.
	var mon_iii := _make_mon("CCFixMon3", [TypeChart.TYPE_NORMAL], 100)
	mon_iii.current_hp = 60  # below threshold on its own merits, isolating the unnerve check
	_chk("S10.04 sitrus_berry_heal bypasses unnerve_active when override_item is set",
			ItemManager.sitrus_berry_heal(mon_iii, false, true, berry) == 40)
	# Discriminator: the same mon/HP, WITHOUT override_item, correctly blocked by Unnerve.
	_chk("S10.05 discriminator: the same scenario without override_item is correctly blocked",
			ItemManager.sitrus_berry_heal(mon_iii, false, true) == 0)

	# (iv) Same Unnerve-bypass check for Lum Berry's status cure (no HP threshold to
	# begin with, so override_item's only effect here is the unnerve bypass).
	var mon_iv := _make_mon("CCFixMon4", [TypeChart.TYPE_NORMAL])
	mon_iv.status = BattlePokemon.STATUS_PARALYSIS
	_chk("S10.06 lum_berry_cures bypasses unnerve_active when override_item is set",
			ItemManager.lum_berry_cures(mon_iv, false, true, lum))
	_chk("S10.07 discriminator: the same scenario without override_item is correctly blocked",
			not ItemManager.lum_berry_cures(mon_iv, false, true))


# ── Section 11: Cud Chew — full-battle arm/fire integration ─────────────────

func _test_section_11_cud_chew_full_battle() -> void:
	var tackle := _load_move(33)
	var cud_chew := _load_ability(291)

	var attacker := _make_mon("CCBattleAtk", [TypeChart.TYPE_NORMAL], 100, 70, 60, 60, 60, 100)
	attacker.add_move(tackle)
	var holder := _make_mon("CCBattleHolder", [TypeChart.TYPE_NORMAL], 100, 60, 100, 60, 100, 20)
	holder.ability = cud_chew
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	holder.current_hp = 82
	holder.add_move(tackle)

	var bm := _make_bm()
	var cud_chew_triggers := []
	bm.ability_triggered.connect(func(m, key): if key == "cud_chew": cud_chew_triggers.append(m))
	bm.start_battle(attacker, holder)

	_chk("S11.01 Cud Chew fired exactly once across the whole battle",
			cud_chew_triggers.count(holder) == 1)

	bm.queue_free()


# ── Section 12: Neutralizing Gas suppression ─────────────────────────────────

func _test_section_12_neutralizing_gas_suppression() -> void:
	var unnerve := _load_ability(127)
	var harvest := _load_ability(139)
	var cud_chew := _load_ability(291)
	var gluttony := _load_ability(82)
	var berry := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")

	# (i) Unnerve suppressed — the opponent's berry is no longer blocked.
	var opp_i := _make_mon("NGUnnerveOpp", [TypeChart.TYPE_NORMAL])
	opp_i.ability = unnerve
	_chk("S12.01 Unnerve suppressed by Neutralizing Gas",
			not AbilityManager.is_unnerve_active([opp_i], true))

	# (ii) Harvest suppressed.
	var mon_ii := _make_mon("NGHarvMon", [TypeChart.TYPE_NORMAL])
	mon_ii.ability = harvest
	mon_ii.last_consumed_berry = berry
	_chk("S12.02 Harvest suppressed by Neutralizing Gas (even in sun)",
			not AbilityManager.harvest_activates(mon_ii, DamageCalculator.WEATHER_SUN, true))

	# (iii) Cud Chew suppressed.
	var mon_iii := _make_mon("NGCCMon", [TypeChart.TYPE_NORMAL])
	mon_iii.ability = cud_chew
	mon_iii.last_consumed_berry = berry
	_chk("S12.03 Cud Chew suppressed by Neutralizing Gas",
			AbilityManager.cud_chew_check(mon_iii, true) == "")

	# (iv) Gluttony suppressed.
	var mon_iv := _make_mon("NGGlutMon", [TypeChart.TYPE_NORMAL])
	mon_iv.ability = gluttony
	_chk("S12.04 Gluttony suppressed by Neutralizing Gas",
			AbilityManager.gluttony_adjusted_hp_fraction(mon_iv, 4, true) == 4)

	# (v) Klutz suppressed — the holder's own item works again.
	var klutz := _load_ability(103)
	var mon_v := _make_mon("NGKlutzMon", [TypeChart.TYPE_NORMAL])
	mon_v.ability = klutz
	mon_v.held_item = berry
	_chk("S12.05 Klutz suppressed by Neutralizing Gas — the holder's item is usable again",
			ItemManager.effective_held_item(mon_v, true) == berry)


# ── Section 13: Negative control ─────────────────────────────────────────────

func _test_section_13_negative_control() -> void:
	var mon := _make_mon("PlainMon", [TypeChart.TYPE_NORMAL])
	mon.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25, "Sitrus Berry")
	mon.current_hp = 60

	_chk("S13.01 negative control: an ordinary Pokémon's held item is unaffected",
			ItemManager.effective_held_item(mon) == mon.held_item)
	_chk("S13.02 negative control: is_unnerve_active false with no Unnerve anywhere",
			not AbilityManager.is_unnerve_active([_make_mon("PlainOpp", [TypeChart.TYPE_NORMAL])]))
	_chk("S13.03 negative control: gluttony_adjusted_hp_fraction unchanged without the ability",
			AbilityManager.gluttony_adjusted_hp_fraction(mon, 4) == 4)
	_chk("S13.04 negative control: harvest_activates false without the ability",
			not AbilityManager.harvest_activates(mon))
	_chk("S13.05 negative control: cud_chew_check returns \"\" without the ability",
			AbilityManager.cud_chew_check(mon) == "")
	_chk("S13.06 negative control: ordinary Sitrus Berry still fires normally " +
			"(HP≤50%, no interfering ability)",
			ItemManager.sitrus_berry_heal(mon) == 40)
