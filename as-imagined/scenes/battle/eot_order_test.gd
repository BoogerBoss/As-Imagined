extends Node

# [End-of-turn reorder, 2026-08-10] Pins the ORDER of `_phase_end_of_turn`'s
# stages against source's own `enum EndTurnResolutionOrder`
# (include/constants/battle_end_turn.h) / `sEndTurnFuncs` dispatch table
# (battle_end_turn.c L1547-1600).
#
# ⚠️ **ORDER IS THE MECHANIC HERE, AND THE WHOLE POINT IS THAT A WRONG ORDER
# STILL "WORKS".** Every effect below fires correctly in isolation under both
# the old and new orderings — a suite that only checked "does Leftovers heal"
# or "does poison damage" was fully green while the order was wrong, which is
# exactly how the bug survived. So every assertion here is built as a
# SURVIVAL-vs-FAINT or a SIDE-EFFECT-OBSERVED discriminator: a case whose
# OUTCOME differs between the two orderings, not merely its intermediate values.
#
# Drives `_phase_end_of_turn()` directly rather than through a live battle,
# matching the established convention (see d4_bundle7_test's own Curse tests
# for the same shape and its reasoning about unbounded-stalemate risk).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_leftovers_heals_before_poison_damage()
	_test_weather_ability_heals_before_poison_damage()
	_test_curse_resolves_before_wrap()
	_test_stage_filter_does_not_double_apply()

	var total := _pass + _fail
	print("eot_order_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


# base_hp=100 at level 50 -> max_hp = floor(2*100*50/100)+50+10 = 160.
# Leftovers heal = 160/16 = 10. Poison damage = 160/8 = 20. Curse = 160/4 = 40.
func _make_mon(mon_name: String, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


## ⚠️ `mons` is typed `Array[BattlePokemon]`, not a bare `Array`, because
## `_combatants`/`_turn_order` are themselves typed and GDScript refuses an
## untyped-Array assignment into a typed one at runtime — this project's own
## documented typed-Array gotcha, hit while writing this very file.
func _make_bm(mons: Array[BattlePokemon]) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = mons
	bm._active_per_side = 1
	bm._turn_order = mons.duplicate()
	return bm


func _leftovers() -> ItemData:
	var item := ItemData.new()
	item.hold_effect = ItemManager.HOLD_EFFECT_LEFTOVERS
	return item


# ── A: Leftovers (idx 8) heals BEFORE poison damage (idx 13) ──────────────
#
# THE HEADLINE FIX. Source's ENDTURN_FIRST_EVENT_BLOCK is index 8 and
# ENDTURN_POISON is 13, so a poisoned Leftovers holder is topped up first and
# only then takes its poison tick. This project ran the heal AFTER the damage
# until 2026-08-10 (its own comment miscited FIRST_EVENT_BLOCK as "position
# 19"), so a Pokémon source leaves alive at low HP fainted outright here.
#
# Constructed so the two orderings give OPPOSITE outcomes:
#   start 20 HP -> heal +10 = 30 -> poison -20 = 10  ... ALIVE  (correct)
#   start 20 HP -> poison -20 = 0 -> faint, heal skipped ... DEAD (old bug)
func _test_leftovers_heals_before_poison_damage() -> void:
	var mon := _make_mon("LeftoversPoisoned")
	var foe := _make_mon("Bystander")
	mon.held_item = _leftovers()
	mon.status = BattlePokemon.STATUS_POISON
	mon.current_hp = 20

	var roster: Array[BattlePokemon] = [mon, foe]
	var bm := _make_bm(roster)
	bm._phase_end_of_turn()

	_chk("A.01 a poisoned Leftovers holder SURVIVES the tick (heal at idx 8 " +
			"precedes poison at idx 13)", not mon.fainted)
	_chk("A.02 and lands on exactly heal-then-damage's own value (20 +10 -20 = 10)",
			mon.current_hp == 10)
	bm.queue_free()


# ── B: the weather abilities (idx 3) heal BEFORE poison damage (idx 13) ────
#
# Independent of A on purpose: this is an ABILITY dispatched from inside
# HandleEndTurnWeatherDamage (battle_end_turn.c L129-141), not a held item, so
# it exercises the WEATHER stage filter rather than FIRST_BLOCK. Before the
# reorder these abilities ran dead last — a ~23-rank displacement, the largest
# found.
#
# Rain Dish in rain heals maxHP/16 = 10, same arithmetic as A.
func _test_weather_ability_heals_before_poison_damage() -> void:
	var mon := _make_mon("RainDishPoisoned")
	var foe := _make_mon("Bystander2")
	mon.ability = _load_ability(44)  # Rain Dish
	mon.status = BattlePokemon.STATUS_POISON
	mon.current_hp = 20

	var roster: Array[BattlePokemon] = [mon, foe]
	var bm := _make_bm(roster)
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 5  # well clear of the idx-2 expiry tick
	bm._phase_end_of_turn()

	_chk("B.01 a poisoned Rain Dish holder in rain SURVIVES the tick (weather " +
			"abilities at idx 3 precede poison at idx 13)", not mon.fainted)
	_chk("B.02 and lands on exactly heal-then-damage's own value (20 +10 -20 = 10)",
			mon.current_hp == 10)
	bm.queue_free()


# ── C: Curse (idx 17) resolves BEFORE Wrap (idx 18) ───────────────────────
#
# Both are damage, so a naive "did it take damage" check cannot tell the two
# orderings apart. The discriminator is a SIDE EFFECT: `wrapped_turns` only
# decrements if the Wrap stage actually reaches a live target.
#
#   start 40 HP -> curse -40 = 0, faint -> Wrap stage skips a fainted mon,
#                  so wrapped_turns is UNTOUCHED           (correct)
#   start 40 HP -> wrap -20 = 20 AND wrapped_turns-- -> curse -40 = faint
#                  so wrapped_turns is DECREMENTED         (old bug)
func _test_curse_resolves_before_wrap() -> void:
	var mon := _make_mon("CursedAndWrapped")
	var foe := _make_mon("Wrapper")
	mon.cursed = true
	mon.wrapped_by = foe
	mon.wrapped_turns = 4
	mon.current_hp = 40

	var roster: Array[BattlePokemon] = [mon, foe]
	var bm := _make_bm(roster)
	bm._phase_end_of_turn()

	_chk("C.01 the cursed mon faints from Curse's own tick", mon.fainted)
	_chk("C.02 discriminator: Wrap (idx 18) never reached it, so wrapped_turns " +
			"is untouched at 4 — proving Curse (idx 17) resolved first",
			mon.wrapped_turns == 4)
	bm.queue_free()


# ── D: the stage filter applies each effect exactly ONCE per tick ──────────
#
# `AbilityManager.try_end_of_turn` is now called THREE times per battler per
# tick (once per source stage it serves). A gate that leaked would double- or
# triple-apply — most visibly on Speed Boost, whose stage-42 stat change is a
# real in-place mutation rather than a value the caller applies.
func _test_stage_filter_does_not_double_apply() -> void:
	var mon := _make_mon("SpeedBoostHolder")
	var foe := _make_mon("Bystander3")
	mon.ability = _load_ability(3)  # Speed Boost
	mon.switched_in_this_turn = false

	var roster: Array[BattlePokemon] = [mon, foe]
	var bm := _make_bm(roster)
	bm._phase_end_of_turn()

	_chk("D.01 Speed Boost raises Speed by exactly ONE stage per end-of-turn, " +
			"despite try_end_of_turn now being called once per source stage",
			mon.stat_stages[BattlePokemon.STAGE_SPEED] == 1)
	bm.queue_free()
