extends Node

# M18x test suite — Covert Cloak
#
# Ground truth: pokeemerald-expansion
#   src/battle_util.c :: IsMoveEffectBlockedByTarget (L9811-9825) -- the LITERAL
#     SAME function as Shield Dust (ABILITY_SHIELD_DUST): an if/else-if chain
#     checking the target's ability first, then its held item, both returning
#     the identical block. Covert Cloak's scope is confirmed identical to
#     Shield Dust's, not assumed.
#   src/battle_script_commands.c :: SetMoveEffect (L2292+) -- the general
#     move-secondary-effect dispatcher; its own gate is
#     `!primary && !affectsUser && IsMoveEffectBlockedByTarget(...)`. This
#     project's existing Shield Dust check (status_manager.gd's
#     try_secondary_effect) reproduces "!primary" via its own
#     `is_true_secondary` (secondary_chance > 0) gate -- confirmed correct by
#     checking every secondary_chance=0 move in this project's roster is a
#     genuine status move (Thunder Wave/Toxic/Confuse Ray/Will-O-Wisp/etc.),
#     and that `stat_change_stat` (Growl/Swords Dance) has NO probability
#     field at all, so no damaging move can carry a probabilistic
#     stat-lowering secondary effect here.
#   Confirmed OUT of scope, NOT wired in (matching Shield Dust's CURRENT
#     actual behavior, not source's full behavior): real source ALSO gates
#     Poison Touch/Toxic Chain (ability-triggered) through this same check
#     (battle_util.c L4286/L4304) -- Toxic Chain is excluded from this
#     project entirely ([M17c]); Poison Touch IS implemented but this
#     project's Shield Dust has no gate there (a pre-existing gap from
#     [M17c], predating this tier, flagged not fixed). Static (a clean,
#     unambiguous example with NO IsMoveEffectBlockedByTarget reference
#     anywhere in source) is used here as the scope-boundary discriminator
#     instead, to avoid conflating the Poison Touch gap with a separate
#     pre-existing direction bug also discovered during this tier's Step 0
#     (out of scope for an item-only tier, not tested here).
#
# Sections: W01 status infliction (probabilistic), W02 confusion, W03 flinch,
# W04 guaranteed/primary status move NOT blocked, W05 stat-change move
# unaffected (full battle), W06 ability-triggered contact effect NOT blocked
# (Static), W07 Sheer Force interaction (no conflict), W08 permanence
# (never consumed).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_w01_status_infliction()
	_test_w02_confusion()
	_test_w03_flinch()
	_test_w04_guaranteed_effect_not_blocked()
	_test_w05_stat_change_move_unaffected()
	_test_w06_ability_contact_effect_not_blocked()
	_test_w07_sheer_force_interaction()
	_test_w08_permanence()

	var total := _pass + _fail
	print("m18x_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18v_test.gd's established pattern) ───────────────────────

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
		secondary_effect: int = MoveData.SE_NONE, secondary_chance: int = 0,
		makes_contact: bool = false) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = secondary_effect
	m.secondary_chance = secondary_chance
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	m.makes_contact    = makes_contact
	return m


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


const SHIELD_DUST_ID := 19
const SHEER_FORCE_ID := 125
const STATIC_ID := 9


# ── W01: probabilistic status infliction ───────────────────────────────────────
func _test_w01_status_infliction() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	_chk("W01.01 Covert Cloak hold_effect=COVERT_CLOAK, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_COVERT_CLOAK)

	var attacker := _make_mon("W01_Attacker", TypeChart.TYPE_NORMAL)
	var holder := _make_mon("W01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	var move := _make_move("W01_Move", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_PARALYSIS, 30)

	var applied: bool = StatusManager.try_secondary_effect(attacker, holder, move, true)
	_chk("W01.02 direct: try_secondary_effect returns FALSE (blocked) for a " +
			"Covert Cloak holder even with the roll forced to succeed",
			not applied)
	_chk("W01.03 status was NOT applied",
			holder.status == BattlePokemon.STATUS_NONE)

	# Discriminator: same move, no item -- status applies normally.
	var no_item_holder := _make_mon("W01_NoItem", TypeChart.TYPE_NORMAL)
	var applied2: bool = StatusManager.try_secondary_effect(attacker, no_item_holder, move, true)
	_chk("W01.04 discriminator: without Covert Cloak, the same forced roll " +
			"DOES apply paralysis",
			applied2 and no_item_holder.status == BattlePokemon.STATUS_PARALYSIS)


# ── W02: confusion ──────────────────────────────────────────────────────────────
func _test_w02_confusion() -> void:
	var attacker := _make_mon("W02_Attacker", TypeChart.TYPE_NORMAL)
	var holder := _make_mon("W02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	var move := _make_move("W02_Move", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_CONFUSION, 10)

	var applied: bool = StatusManager.try_secondary_effect(attacker, holder, move, true)
	_chk("W02.01 direct: confusion is blocked for a Covert Cloak holder",
			not applied)
	_chk("W02.02 confusion_turns was NOT set",
			holder.confusion_turns == 0)

	var no_item_holder := _make_mon("W02_NoItem", TypeChart.TYPE_NORMAL)
	var applied2: bool = StatusManager.try_secondary_effect(attacker, no_item_holder, move, true)
	_chk("W02.03 discriminator: without Covert Cloak, confusion DOES apply",
			applied2 and no_item_holder.confusion_turns > 0)


# ── W03: flinch ───────────────────────────────────────────────────────────────
func _test_w03_flinch() -> void:
	var attacker := _make_mon("W03_Attacker", TypeChart.TYPE_NORMAL)
	var holder := _make_mon("W03_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	var move := _make_move("W03_Move", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_FLINCH, 30)

	var applied: bool = StatusManager.try_secondary_effect(attacker, holder, move, true)
	_chk("W03.01 direct: flinch roll is blocked for a Covert Cloak holder " +
			"(returns FALSE, caller never sets .flinched)",
			not applied)

	var no_item_holder := _make_mon("W03_NoItem", TypeChart.TYPE_NORMAL)
	var applied2: bool = StatusManager.try_secondary_effect(attacker, no_item_holder, move, true)
	_chk("W03.02 discriminator: without Covert Cloak, the flinch roll DOES " +
			"succeed (returns TRUE)",
			applied2)


# ── W04: guaranteed/primary status move effect is NOT blocked ─────────────────
# Direct test of Step 0's own scope-confirmation work: a chance=0 status move
# (Thunder Wave-shape) reaches the SAME try_secondary_effect function but must
# NOT be blocked by Covert Cloak, matching source's "!primary" exemption.
func _test_w04_guaranteed_effect_not_blocked() -> void:
	var attacker := _make_mon("W04_Attacker", TypeChart.TYPE_NORMAL)
	var holder := _make_mon("W04_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	# secondary_chance=0 -- the SAME shape this project's real Thunder Wave/
	# Toxic/Confuse Ray/Will-O-Wisp entries use for their own guaranteed,
	# PRIMARY effect (gen_moves.py, confirmed at Step 0).
	var move := _make_move("W04_ThunderWaveShape", TypeChart.TYPE_ELECTRIC, 2,
			0, MoveData.SE_PARALYSIS, 0)

	var applied: bool = StatusManager.try_secondary_effect(attacker, holder, move)
	_chk("W04.01 a guaranteed (secondary_chance=0) status-move effect is NOT " +
			"blocked by Covert Cloak -- it's a PRIMARY effect, out of scope, " +
			"exactly like source's own !primary exemption",
			applied and holder.status == BattlePokemon.STATUS_PARALYSIS)


# ── W05: stat-change moves are architecturally unaffected (full battle) ───────
# try_secondary_effect is never even called for stat_change_stat moves in this
# project (a completely separate dispatch path) -- confirmed via a full-battle
# sanity check that Covert Cloak doesn't accidentally interfere.
func _test_w05_stat_change_move_unaffected() -> void:
	var holder := _make_mon("W05_Holder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 30)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	holder.add_move(_make_move("W05_HolderMove", TypeChart.TYPE_NORMAL, 0, 1))
	var attacker := _make_mon("W05_Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	var growl_shape := _make_move("W05_GrowlShape", TypeChart.TYPE_NORMAL, 2, 0)
	growl_shape.stat_change_stat = BattlePokemon.STAGE_ATK
	growl_shape.stat_change_amount = -1
	growl_shape.stat_change_self = false
	attacker.add_move(growl_shape)

	var stat_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.start_battle_with_parties(BattleParty.single(holder), BattleParty.single(attacker))
	_chk("W05.01 full-battle: a Growl-shaped stat-lowering move still lowers " +
			"a Covert Cloak holder's stat normally (architecturally " +
			"unreachable by Covert Cloak's gate, not accidentally blocked)",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_ATK and e[2] < 0))
	bm.queue_free()


# ── W06: ability-triggered contact effect is NOT blocked (Static) ─────────────
# Scope-boundary discriminator: Covert Cloak's gate lives ONLY in
# try_secondary_effect, never touching try_contact_effects at all. Static is
# used as a clean, unambiguous example (confirmed via source: NO reference to
# IsMoveEffectBlockedByTarget anywhere near Static's own case, unlike Poison
# Touch/Toxic Chain).
func _test_w06_ability_contact_effect_not_blocked() -> void:
	var holder := _make_mon("W06_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	holder.ability = _load_ability(STATIC_ID)
	var attacker := _make_mon("W06_Attacker", TypeChart.TYPE_NORMAL)
	var contact_move := _make_move("W06_ContactMove", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_NONE, 0, true)

	var result: Dictionary = AbilityManager.try_contact_effects(
			attacker, holder, contact_move, 20, true)
	_chk("W06.01 Static (an ability-triggered contact effect, dispatched " +
			"through a wholly separate function) still fires normally against " +
			"the ATTACKER even though the Covert-Cloak-holding DEFENDER owns " +
			"the ability -- Covert Cloak has zero reach into try_contact_effects",
			result["status_applied"] == BattlePokemon.STATUS_PARALYSIS)


# ── W07: Sheer Force interaction -- confirmed unrelated, no conflict ──────────
func _test_w07_sheer_force_interaction() -> void:
	var attacker := _make_mon("W07_Attacker", TypeChart.TYPE_NORMAL)
	attacker.ability = _load_ability(SHEER_FORCE_ID)
	var holder := _make_mon("W07_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	var move := _make_move("W07_Move", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_PARALYSIS, 30)

	var applied: bool = StatusManager.try_secondary_effect(attacker, holder, move, true)
	_chk("W07.01 an attacker with Sheer Force AND a Covert-Cloak-holding " +
			"defender together still just block once (no double-trigger " +
			"error, no conflict -- the two mechanisms are keyed on different " +
			"battlers entirely)",
			not applied)
	_chk("W07.02 status was NOT applied",
			holder.status == BattlePokemon.STATUS_NONE)


# ── W08: permanence -- never consumed ──────────────────────────────────────────
func _test_w08_permanence() -> void:
	var attacker := _make_mon("W08_Attacker", TypeChart.TYPE_NORMAL)
	var holder := _make_mon("W08_Holder", TypeChart.TYPE_NORMAL)
	var cloak := _make_item(ItemManager.HOLD_EFFECT_COVERT_CLOAK)
	holder.held_item = cloak
	var move := _make_move("W08_Move", TypeChart.TYPE_NORMAL, 0, 40,
			MoveData.SE_PARALYSIS, 30)

	StatusManager.try_secondary_effect(attacker, holder, move, true)
	StatusManager.try_secondary_effect(attacker, holder, move, true)
	StatusManager.try_secondary_effect(attacker, holder, move, true)
	_chk("W08.01 Covert Cloak is still held after blocking THREE separate " +
			"secondary effects -- a permanent modifier, never consumed",
			holder.held_item == cloak and holder.held_item.hold_effect == ItemManager.HOLD_EFFECT_COVERT_CLOAK)
