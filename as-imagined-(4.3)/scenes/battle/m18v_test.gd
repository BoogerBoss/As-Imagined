extends Node

# M18v test suite — Mental Herb
#
# Ground truth: pokeemerald-expansion
#   src/battle_hold_effects.c :: TryMentalHerb (L416-476) -- current-gen source
#     cures SIX volatiles in one unconditional scan: Infatuation, Torment,
#     Disable, Heal Block, Encore, Taunt -- NOT just "Disable/Encore" as the
#     plan doc's own prose loosely summarized. Of those six, this project
#     confirmed implements only Disable (`disabled_move`/`disable_turns`) and
#     Encore (`encored_move`/`encore_turns`) -- Infatuation/Torment/Heal
#     Block/Taunt are all confirmed absent (no code anywhere references any of
#     them as a real mechanic). The tier table's "Disable/Encore only"
#     narrowing DOES hold up, just via a fuller source citation.
#   src/data/hold_effects.h L162-167 -- HOLD_EFFECT_MENTAL_HERB's dispatch is
#     `.onTargetAfterHit`/`.onAttackerAfterHit`, and TryMentalHerb's own body
#     never branches on which -- an UNCONDITIONAL per-checkpoint scan, the
#     SAME shape as White Herb ([M18m]), reusing the identical
#     `_phase_faint_check()` insertion point rather than new infrastructure.
#     Consumed ONCE if EITHER condition was cured (source sets a single
#     `effect` flag regardless of how many conditions matched).
#
# Sections: V01 Disable, V02 Encore, V03 both simultaneously (single
# consumption), V04 scope-boundary discriminator (confusion, NOT in Mental
# Herb's real scope, must be left untouched).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_v01_disable()
	_test_v02_encore()
	_test_v03_both_simultaneously()
	_test_v04_scope_boundary()

	var total := _pass + _fail
	print("m18v_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18t_test.gd's established pattern) ───────────────────────

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
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
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
	return m


# ── V01: Disable ─────────────────────────────────────────────────────────────────
# Direct _phase_faint_check() calls on a minimally-configured bare BattleManager
# -- Mental Herb's trigger is a pure scan of current volatile state, not
# dependent on any move having just executed, matching White Herb's own
# established no-battle-needed testing shape.

func _test_v01_disable() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_MENTAL_HERB)
	_chk("V01.01 Mental Herb hold_effect=MENTAL_HERB, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_MENTAL_HERB)

	var holder := _make_mon("V01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	holder.disabled_move = _make_move("V01_DisabledMove", TypeChart.TYPE_NORMAL, 0, 40)
	holder.disable_turns = 4

	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = [holder]
	bm._active_per_side = 1
	var trigger_events := []
	var consumed_events := []
	bm.item_effect_triggered.connect(func(m, key): trigger_events.push_back([m, key]))
	bm.item_consumed.connect(func(m, item2): consumed_events.push_back([m, item2]))
	bm._phase_faint_check()

	_chk("V01.02 disabled_move cleared to null",
			holder.disabled_move == null)
	_chk("V01.03 disable_turns reset to 0",
			holder.disable_turns == 0)
	_chk("V01.04 item_effect_triggered fires with key 'mental_herb_disable'",
			trigger_events.any(func(e): return e[0] == holder and e[1] == "mental_herb_disable"))
	_chk("V01.05 Mental Herb is consumed",
			consumed_events.any(func(e): return e[0] == holder))
	bm.queue_free()

	# Discriminator: same Disable state, but the mon does NOT hold Mental Herb --
	# Disable persists normally, unaffected.
	var no_item_holder := _make_mon("V01_NoItem", TypeChart.TYPE_NORMAL)
	no_item_holder.disabled_move = _make_move("V01_NoItemMove", TypeChart.TYPE_NORMAL, 0, 40)
	no_item_holder.disable_turns = 4

	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._combatants = [no_item_holder]
	bm2._active_per_side = 1
	bm2._phase_faint_check()

	_chk("V01.06 discriminator: without Mental Herb, disabled_move is unaffected",
			no_item_holder.disabled_move != null)
	_chk("V01.07 discriminator: without Mental Herb, disable_turns is unaffected",
			no_item_holder.disable_turns == 4)
	bm2.queue_free()


# ── V02: Encore ───────────────────────────────────────────────────────────────────
func _test_v02_encore() -> void:
	var holder := _make_mon("V02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_MENTAL_HERB)
	holder.encored_move = _make_move("V02_EncoredMove", TypeChart.TYPE_NORMAL, 0, 40)
	holder.encore_turns = 3

	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = [holder]
	bm._active_per_side = 1
	var trigger_events := []
	var consumed_events := []
	bm.item_effect_triggered.connect(func(m, key): trigger_events.push_back([m, key]))
	bm.item_consumed.connect(func(m, item2): consumed_events.push_back([m, item2]))
	bm._phase_faint_check()

	_chk("V02.01 encored_move cleared to null",
			holder.encored_move == null)
	_chk("V02.02 encore_turns reset to 0",
			holder.encore_turns == 0)
	_chk("V02.03 item_effect_triggered fires with key 'mental_herb_encore'",
			trigger_events.any(func(e): return e[0] == holder and e[1] == "mental_herb_encore"))
	_chk("V02.04 Mental Herb is consumed",
			consumed_events.any(func(e): return e[0] == holder))
	bm.queue_free()

	# Discriminator: same Encore state, no Mental Herb -- persists.
	var no_item_holder := _make_mon("V02_NoItem", TypeChart.TYPE_NORMAL)
	no_item_holder.encored_move = _make_move("V02_NoItemMove", TypeChart.TYPE_NORMAL, 0, 40)
	no_item_holder.encore_turns = 3

	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._combatants = [no_item_holder]
	bm2._active_per_side = 1
	bm2._phase_faint_check()

	_chk("V02.05 discriminator: without Mental Herb, encored_move is unaffected",
			no_item_holder.encored_move != null)
	_chk("V02.06 discriminator: without Mental Herb, encore_turns is unaffected",
			no_item_holder.encore_turns == 3)
	bm2.queue_free()


# ── V03: both Disable AND Encore active simultaneously -- single consumption ──────
func _test_v03_both_simultaneously() -> void:
	var holder := _make_mon("V03_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_MENTAL_HERB)
	holder.disabled_move = _make_move("V03_DisabledMove", TypeChart.TYPE_NORMAL, 0, 40)
	holder.disable_turns = 4
	holder.encored_move = _make_move("V03_EncoredMove", TypeChart.TYPE_NORMAL, 0, 40)
	holder.encore_turns = 3

	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = [holder]
	bm._active_per_side = 1
	var trigger_events := []
	var consumed_events := []
	bm.item_effect_triggered.connect(func(m, key): trigger_events.push_back([m, key]))
	bm.item_consumed.connect(func(m, item2): consumed_events.push_back([m, item2]))
	bm._phase_faint_check()

	_chk("V03.01 both cured: disabled_move null AND encored_move null",
			holder.disabled_move == null and holder.encored_move == null)
	_chk("V03.02 both trigger keys fire ('mental_herb_disable' AND 'mental_herb_encore')",
			trigger_events.any(func(e): return e[1] == "mental_herb_disable") \
					and trigger_events.any(func(e): return e[1] == "mental_herb_encore"))
	_chk("V03.03 consumed EXACTLY ONCE despite curing two conditions in one call",
			consumed_events.size() == 1 and consumed_events[0][0] == holder)
	bm.queue_free()


# ── V04: scope-boundary discriminator -- confusion is NOT in Mental Herb's scope ──
# Direct test of Step 0's scope-confirmation work: this project HAS confusion
# implemented, but source's TryMentalHerb does not cure it (only Infatuation/
# Torment/Disable/Heal Block/Encore/Taunt) -- must be left completely untouched.

func _test_v04_scope_boundary() -> void:
	var holder := _make_mon("V04_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = _make_item(ItemManager.HOLD_EFFECT_MENTAL_HERB)
	holder.confusion_turns = 3

	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = [holder]
	bm._active_per_side = 1
	var consumed_events := []
	bm.item_consumed.connect(func(m, item2): consumed_events.push_back([m, item2]))
	bm._phase_faint_check()

	_chk("V04.01 confusion_turns is completely untouched (Mental Herb does not " +
			"cure confusion, confirmed out of its real source scope)",
			holder.confusion_turns == 3)
	_chk("V04.02 Mental Herb is NOT consumed when neither Disable nor Encore " +
			"is active, even with an unrelated volatile (confusion) present",
			consumed_events.is_empty())
	bm.queue_free()
