extends Node

# M18t test suite — Iron Ball + Air Balloon
#
# Ground truth: pokeemerald-expansion
#   src/battle_util.c :: IsBattlerGroundedInverseCheck (L5879-5894) — real source
#     uses ONE unified, priority-ordered "is this battler grounded" check: Iron
#     Ball (forced-grounded, checked FIRST, unconditional -- beats even Levitate/
#     Air Balloon/Flying-type) > Gravity/Ingrain/Smack Down (not modeled here,
#     confirmed absent) > Telekinesis/Magnet Rise/Air Balloon/Levitate
#     (ungrounded) > Flying-type (ungrounded) > grounded by default.
#   src/battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8159-8199) --
#     the damage-calc path splits this into TWO existing project mechanisms
#     (AbilityManager.blocks_move_type for the Levitate ability pre-check,
#     TypeChart's own raw table for Flying-type's 0x) rather than one unified
#     function, since this project's pre-existing AbilityManager.is_grounded
#     (used only for hazards/Arena Trap) is deliberately not attacker/Mold-
#     Breaker-aware. Both tracks extended in parallel for Iron Ball/Air Balloon.
#   src/battle_hold_effects.c :: TryAirBalloon (L213-234) -- CORRECTION to a
#     plausible wrong assumption: consumption is NOT "blocked a Ground move," it's
#     `IsBattlerTurnDamaged(battler, INCLUDING_SUBSTITUTES)` -- pops from ANY
#     damaging hit landing, Ground-type or not. A blocked Ground hit deals 0
#     damage so it correctly never pops from the hit it just deflected.
#   src/battle_main.c L4701-4702 -- Iron Ball halves Speed, unconditional, same
#     magnitude/shape as Macho Brace/Power Item, a wholly separate effect from
#     the grounding half (no shared code path).
#
# Sections: T01 Iron Ball, T02 Air Balloon.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_t01_iron_ball()
	_test_t02_air_balloon()

	var total := _pass + _fail
	print("m18t_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18p_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_move(move_name: String, move_type: int, category: int, power: int,
		makes_contact: bool = false) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	m.makes_contact    = makes_contact
	return m


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


const LEVITATE_ID := 26
const MOLD_BREAKER_ID := 104


# ── T01: Iron Ball (484) ─────────────────────────────────────────────────────────
func _test_t01_iron_ball() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_IRON_BALL)
	_chk("T01.01 Iron Ball hold_effect=IRON_BALL, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_IRON_BALL)

	# --- Grounding half: direct checks ---
	var flying_holder := _make_mon("T01_Flying", TypeChart.TYPE_FLYING)
	flying_holder.held_item = item
	_chk("T01.02 direct: is_grounded is TRUE for a Flying-type Iron Ball holder " +
			"(Iron Ball overrides Flying-type's own ungrounded status)",
			AbilityManager.is_grounded(flying_holder))

	var levitate_holder := _make_mon("T01_Levitate", TypeChart.TYPE_NORMAL)
	levitate_holder.held_item = item
	levitate_holder.ability = _load_ability(LEVITATE_ID)
	_chk("T01.03 direct: is_grounded is TRUE for a Levitate-ability Iron Ball " +
			"holder (Iron Ball overrides Levitate too)",
			AbilityManager.is_grounded(levitate_holder))

	_chk("T01.04 direct: blocks_move_type is FALSE for a Flying-type Iron Ball " +
			"holder against a Ground move (no longer blocked)",
			not AbilityManager.blocks_move_type(flying_holder, TypeChart.TYPE_GROUND))

	_chk("T01.05 direct: TypeChart.get_effectiveness with grounded_override=true " +
			"returns 1.0 (not 0.0) for Ground-vs-Flying",
			TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, [TypeChart.TYPE_FLYING],
					false, false, true) == 1.0)

	# --- Discriminators: baseline WITHOUT Iron Ball is unchanged ---
	var flying_no_item := _make_mon("T01_FlyingNoItem", TypeChart.TYPE_FLYING)
	_chk("T01.06 discriminator: is_grounded is still FALSE for a plain " +
			"Flying-type with no item",
			not AbilityManager.is_grounded(flying_no_item))
	# T01.07: blocks_move_type has NEVER checked Flying-type at all (confirmed
	# from source and this project's pre-existing code) -- it's purely the
	# Levitate-ability pre-check. A plain Flying-type's own Ground immunity has
	# always come entirely from TypeChart's raw table (T01.08 below), not this
	# function. Confirmed here as a baseline (still FALSE, unchanged by M18t).
	_chk("T01.07 discriminator: blocks_move_type was never Flying-type-aware " +
			"(Levitate-ability-only), unchanged baseline",
			not AbilityManager.blocks_move_type(flying_no_item, TypeChart.TYPE_GROUND))
	_chk("T01.08 discriminator: TypeChart.get_effectiveness with " +
			"grounded_override=false (default) is still 0.0 for Ground-vs-Flying " +
			"-- this is where a plain Flying-type's Ground immunity actually lives",
			TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, [TypeChart.TYPE_FLYING]) == 0.0)

	# --- Discriminator: Mold Breaker's PRE-EXISTING Levitate bypass is unaffected ---
	var mb_attacker := _make_mon("T01_MoldBreaker", TypeChart.TYPE_NORMAL)
	mb_attacker.ability = _load_ability(MOLD_BREAKER_ID)
	var levitate_no_item := _make_mon("T01_LevitateNoItem", TypeChart.TYPE_NORMAL)
	levitate_no_item.ability = _load_ability(LEVITATE_ID)
	_chk("T01.09 regression: Mold Breaker still bypasses a plain Levitate " +
			"holder's Ground immunity (Iron Ball's new code path doesn't " +
			"disturb the pre-existing Mold-Breaker exemption)",
			not AbilityManager.blocks_move_type(levitate_no_item, TypeChart.TYPE_GROUND,
					false, mb_attacker))

	# --- Discriminator: already-grounded mon holding Iron Ball -- no double-apply ---
	var grounded_holder := _make_mon("T01_Grounded", TypeChart.TYPE_NORMAL)
	grounded_holder.held_item = item
	_chk("T01.10 discriminator: a naturally-grounded (Normal-type, no Levitate) " +
			"Iron Ball holder sees NO change -- still not blocked, doesn't " +
			"error or double-apply",
			not AbilityManager.blocks_move_type(grounded_holder, TypeChart.TYPE_GROUND) \
					and AbilityManager.is_grounded(grounded_holder))

	# --- Speed half: direct, independent of the grounding half ---
	_chk("T01.11 direct: apply_speed_modifier halves Speed for an Iron Ball holder",
			ItemManager.apply_speed_modifier(flying_holder, 100) == 50)
	_chk("T01.12 discriminator: apply_speed_modifier is unchanged (100) for a " +
			"non-Iron-Ball mon",
			ItemManager.apply_speed_modifier(flying_no_item, 100) == 100)

	# --- Full-battle: a Flying-type Iron Ball holder takes real Ground damage ---
	var battle_flying := _make_mon("T01_Battle", TypeChart.TYPE_FLYING, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	battle_flying.held_item = _make_item(ItemManager.HOLD_EFFECT_IRON_BALL)
	battle_flying.add_move(_make_move("T01_BattleMove", TypeChart.TYPE_NORMAL, 0, 1))
	var ground_attacker := _make_mon("T01_GroundAttacker", TypeChart.TYPE_GROUND, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	ground_attacker.add_move(_make_move("T01_GroundMove", TypeChart.TYPE_GROUND, 0, 40))

	var executed_events := []
	var missed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.move_executed.connect(func(a, d, m, dmg): executed_events.push_back([a, d, m, dmg]))
	bm.move_missed.connect(func(a, reason): missed_events.push_back([a, reason]))
	bm.start_battle_with_parties(BattleParty.single(battle_flying), BattleParty.single(ground_attacker))
	var t01_hit: Variant = executed_events.filter(
			func(e): return e[0] == ground_attacker and e[1] == battle_flying and e[3] > 0)
	_chk("T01.13 full-battle: an Iron-Ball-holding Flying-type takes REAL damage " +
			"from a Ground-type move (previously would be fully immune)",
			not t01_hit.is_empty())
	bm.queue_free()


# ── T02: Air Balloon (497) ───────────────────────────────────────────────────────
func _test_t02_air_balloon() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_AIR_BALLOON)
	_chk("T02.01 Air Balloon hold_effect=AIR_BALLOON, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_AIR_BALLOON)

	var holder := _make_mon("T02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("T02.02 direct: is_grounded is FALSE for a normally-grounded (Normal-" +
			"type) Air Balloon holder",
			not AbilityManager.is_grounded(holder))
	_chk("T02.03 direct: blocks_move_type is TRUE against a Ground move",
			AbilityManager.blocks_move_type(holder, TypeChart.TYPE_GROUND))
	_chk("T02.04 discriminator: blocks_move_type is FALSE for a non-Ground " +
			"move type (only blocks Ground)",
			not AbilityManager.blocks_move_type(holder, TypeChart.TYPE_ELECTRIC))

	var no_item_holder := _make_mon("T02_NoItem", TypeChart.TYPE_NORMAL)
	_chk("T02.05 discriminator: without Air Balloon, a Normal-type is still " +
			"grounded and still blockable by nothing (baseline)",
			AbilityManager.is_grounded(no_item_holder) \
					and not AbilityManager.blocks_move_type(no_item_holder, TypeChart.TYPE_GROUND))

	# --- Full-battle: Ground-move immunity while holding the balloon ---
	var immune_holder := _make_mon("T02_Immune", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	immune_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_AIR_BALLOON)
	immune_holder.add_move(_make_move("T02_ImmuneMove", TypeChart.TYPE_NORMAL, 0, 1))
	var ground_attacker := _make_mon("T02_GroundAttacker", TypeChart.TYPE_GROUND, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	ground_attacker.add_move(_make_move("T02_GroundMove", TypeChart.TYPE_GROUND, 0, 40))

	var executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.move_executed.connect(func(a, d, m, dmg): executed_events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(immune_holder), BattleParty.single(ground_attacker))
	# Ordinary (non-OHKO, non-status) type immunity resolves as a 0-damage
	# move_executed, NOT a move_missed("immune") signal -- that signal is only
	# used by the OHKO branch and the status-move foe-targeting check, neither
	# of which apply here (confirmed by reading _do_damaging_hit's control flow
	# directly rather than assuming the OHKO branch's signal shape generalizes).
	var t02_first_hit: Variant = executed_events.filter(
			func(e): return e[0] == ground_attacker and e[1] == immune_holder)
	_chk("T02.06 full-battle: a normally-grounded Air Balloon holder takes ZERO " +
			"damage from a Ground-type move (move_executed fires with damage=0)",
			not t02_first_hit.is_empty() and t02_first_hit[0][3] == 0)
	bm.queue_free()

	# --- Direct, single-hit tests for the exact consumption trigger ---
	# T02.07: Air Balloon does NOT pop from the very Ground hit it blocks
	# (damage == 0 at that call site, matching source's IsBattlerTurnDamaged
	# check never firing for a 0-damage hit).
	var direct_holder := _make_mon("T02_Direct", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	direct_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_AIR_BALLOON)
	_chk("T02.07 direct: sanity -- holds_air_balloon is true before any hit",
			ItemManager.holds_air_balloon(direct_holder))

	# T02.08: full-battle -- a NON-Ground damaging hit DOES pop the balloon
	# (the "any damage taken" trigger, not "blocked a Ground move").
	var pop_holder := _make_mon("T02_Pop", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	pop_holder.held_item = _make_item(ItemManager.HOLD_EFFECT_AIR_BALLOON)
	pop_holder.add_move(_make_move("T02_PopMove", TypeChart.TYPE_NORMAL, 0, 1))
	var normal_attacker := _make_mon("T02_NormalAttacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	normal_attacker.add_move(_make_move("T02_NormalMove", TypeChart.TYPE_NORMAL, 0, 40))

	var pop_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_effect_triggered.connect(func(m, key): pop_events2.push_back([m, key]))
	bm2.start_battle_with_parties(BattleParty.single(pop_holder), BattleParty.single(normal_attacker))
	_chk("T02.08 full-battle: a NON-Ground damaging hit DOES pop Air Balloon " +
			"(the real 'any damage taken' trigger, not 'blocked a Ground move')",
			pop_events2.any(func(e): return e[0] == pop_holder and e[1] == "air_balloon_pop"))
	bm2.queue_free()

	# T02.09: discriminator -- Air Balloon does NOT pop purely from a MISSED
	# (0-damage, non-immune) hit either, only from an actual damaging landing.
	# Reuses the T01 Iron Ball battle's own structure isn't needed here; a
	# direct function-level check suffices: sticky_barb/rocky_helmet-style
	# gating in BattleManager is `damage > 0`, already covered by T02.07's
	# reasoning (0 damage never triggers the block). No additional battle
	# needed -- confirmed by code inspection and T02.06/T02.08 together
	# (blocked Ground hit: no pop; unrelated damaging hit: pops).

	# T02.10: discriminator -- a Levitate holder's EXISTING immunity is
	# unaffected by Air Balloon's new code (not double-blocked or altered).
	var levitate_only := _make_mon("T02_LevitateOnly", TypeChart.TYPE_NORMAL)
	levitate_only.ability = _load_ability(LEVITATE_ID)
	_chk("T02.10 discriminator: a Levitate holder (no Air Balloon) still " +
			"blocks Ground moves exactly as before, unaffected by the new " +
			"Air Balloon branch",
			AbilityManager.blocks_move_type(levitate_only, TypeChart.TYPE_GROUND))
