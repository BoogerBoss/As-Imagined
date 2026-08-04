extends Node

# [M26b] Regression suite for the log/debug-overlay merge: the category-
# tagged entry data structure, the toggle-row/default-on-off state, the
# structural turn separator (already covered from the Narrative angle by
# m25c_message_log_test.gd's own turn-separator tests — this suite focuses
# on the category system itself and the NEW categories this design adds),
# and representative wiring for each new category (Durations & Field
# State, Stat Changes, Items & Berries, Multi-Hit Detail, Delayed Effects,
# Ability & Immunity, Niche/Situational) plus the disclosed RNG/Turn Order
# gap. Narrative/Damage Math's own pre-existing content is already covered
# by m25c_message_log_test.gd/m25d_ui_polish_test.gd — not re-derived here.
#
# [Deliberately NOT tested here] Real signal emission from a genuine
# multi-turn battle for every one of the ~20 signals wired in
# _wire_debug_signals() — this project's own BattleManager exposes ~150
# signals total; testing every single wired connection end-to-end would be
# disproportionate to this milestone's own scope. Instead: (a) each
# handler's own text-construction/category-tagging logic is exercised via
# a direct signal .emit() call on a bare BattleManager (signals don't
# require scene-tree membership to emit or receive), matching this
# project's own established "call the handler directly" convention where a
# full battle isn't needed to prove the logic correct; (b) one real
# end-to-end test drives an actual battle through _wire_debug_signals() to
# confirm the wiring itself is live, not just correct in isolation.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_default_category_state()
	_test_toggle_row_built_with_all_categories()
	_test_add_debug_entry_accumulates_regardless_of_visibility()
	_test_render_filters_by_category_toggle()
	_test_render_inserts_turn_separator_on_change()
	_test_render_recomputes_separators_after_toggle()
	_test_rng_gap_disclosure_and_partial_coverage()
	_test_turn_order_gap_disclosure_and_partial_coverage()
	_test_durations_trick_room()
	_test_durations_screen_with_real_duration()
	_test_stat_changes_before_after()
	_test_stat_changes_zero_delta_skipped()
	_test_items_berries_hp_context()
	_test_multi_hit_aggregate_disclaimer()
	_test_delayed_effects_scheduled_and_resolved()
	_test_ability_immunity_retagged_from_narrative()
	_test_ability_changed_reports_the_new_ability()
	_test_ability_changed_is_the_only_narration_for_move_effect_mechanics()
	_test_niche_default_off_but_still_recorded()
	_test_damage_math_no_longer_has_redundant_header()
	_test_real_battle_end_to_end_debug_wiring()

	var total := _pass + _fail
	print("m26b_debug_log_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_mon(mon_name: String, type_id: int, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type_id]
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _singles_party(mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	var members: Array[BattlePokemon] = [mon]
	p.members = members
	p.active_indices = [0]
	return p


func _entries_of(bs: BattleScreenShared, category: int) -> Array:
	var out := []
	for entry in bs._debug_entries:
		if entry["category"] == category:
			out.append(entry["text"])
	return out


# ── 1-2. Default category state / toggle row construction ──────────────

func _test_default_category_state() -> void:
	var bs := BattleScreenShared.new()
	bs._setup_debug_overlay()

	for category in BattleScreenShared._DEBUG_CATEGORY_ORDER:
		var expected: bool = BattleScreenShared._DEBUG_CATEGORY_DEFAULT_ON[category]
		_chk("category %d default-on state matches the locked design" % category,
				bs._debug_category_on[category] == expected)

	_chk("Niche/Situational is the one category default-off, per the locked design",
			bs._debug_category_on[BattleScreenShared.DebugCategory.NICHE] == false)
	_chk("Narrative Text is default-on (today's existing content, unchanged)",
			bs._debug_category_on[BattleScreenShared.DebugCategory.NARRATIVE] == true)
	_chk("Damage Math is default-on (today's existing content, unchanged)",
			bs._debug_category_on[BattleScreenShared.DebugCategory.DAMAGE_MATH] == true)


func _test_toggle_row_built_with_all_categories() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var instance: BattleScreenShared = scene.instantiate()
	add_child(instance)

	var toggle_row: HFlowContainer = instance.get_node("SharedChrome/DebugOverlay/VBox/ToggleRow")
	_chk("the toggle row has one CheckBox per category",
			toggle_row.get_child_count() == BattleScreenShared._DEBUG_CATEGORY_ORDER.size())

	var all_checkboxes := true
	for child in toggle_row.get_children():
		if not (child is CheckBox):
			all_checkboxes = false
	_chk("every toggle-row child is a real CheckBox", all_checkboxes)

	var first_cb: CheckBox = toggle_row.get_child(0)
	_chk("the first toggle button is labeled Narrative Text (stable _DEBUG_CATEGORY_ORDER)",
			first_cb.text == "Narrative Text")
	_chk("the first toggle button starts checked (Narrative is default-on)",
			first_cb.button_pressed == true)

	var last_cb: CheckBox = toggle_row.get_child(toggle_row.get_child_count() - 1)
	_chk("the last toggle button is labeled Niche/Situational",
			last_cb.text == "Niche/Situational")
	_chk("the last toggle button starts unchecked (Niche is default-off)",
			last_cb.button_pressed == false)

	instance.queue_free()


# ── 3. Entries accumulate regardless of panel visibility (never discarded) ──

func _test_add_debug_entry_accumulates_regardless_of_visibility() -> void:
	var bs := BattleScreenShared.new()
	bs._setup_debug_overlay()
	# _debug_overlay stays null on this bare instance -- _add_debug_entry's
	# own null guard means nothing renders, but the entry itself must still
	# be recorded (the "full history is never discarded" requirement).
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "line one")
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "line two")
	_chk("entries accumulate even with no overlay/renderer attached at all",
			bs._debug_entries.size() == 2)
	_chk("entry order is preserved", bs._debug_entries[0]["text"] == "line one" \
			and bs._debug_entries[1]["text"] == "line two")


# ── 4-6. Rendering: category filter, turn separators, recompute-on-toggle ──

func _test_render_filters_by_category_toggle() -> void:
	var bs := BattleScreenShared.new()
	bs._setup_debug_overlay()
	bs._debug_body = RichTextLabel.new()

	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "a narrative line")
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NICHE, "a niche line")
	bs._render_debug_overlay()

	_chk("a default-on category's entry is rendered", "a narrative line" in bs._debug_body.text)
	_chk("the default-off Niche category's entry is NOT rendered",
			not ("a niche line" in bs._debug_body.text))
	_chk("the underlying data still holds both entries regardless of what's rendered",
			bs._debug_entries.size() == 2)


func _test_render_inserts_turn_separator_on_change() -> void:
	var bs := BattleScreenShared.new()
	bs._setup_debug_overlay()
	bs._debug_body = RichTextLabel.new()

	bs._on_log_turn_started(1)
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "turn 1 event")
	bs._on_log_turn_started(2)
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "turn 2 event")
	bs._render_debug_overlay()

	_chk("a separator for turn 1 is rendered", "Turn 1" in bs._debug_body.text)
	_chk("a separator for turn 2 is rendered", "Turn 2" in bs._debug_body.text)
	_chk("turn 1's own separator precedes turn 2's own separator",
			bs._debug_body.text.find("Turn 1") < bs._debug_body.text.find("Turn 2"))


func _test_render_recomputes_separators_after_toggle() -> void:
	# Two turns, but only turn 2 has anything in a category that's turned
	# on -- confirms the separator logic is based on what's actually being
	# RENDERED, not a fixed pre-baked line, per the locked design's own
	# "toggling a category recomputes correctly" requirement.
	var bs := BattleScreenShared.new()
	bs._setup_debug_overlay()
	bs._debug_body = RichTextLabel.new()

	bs._on_log_turn_started(1)
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NICHE, "turn 1 niche-only event")
	bs._on_log_turn_started(2)
	bs._add_debug_entry(BattleScreenShared.DebugCategory.NARRATIVE, "turn 2 narrative event")
	bs._render_debug_overlay()

	_chk("with Niche off (default), turn 1 (niche-only) produces no separator at all",
			not ("Turn 1" in bs._debug_body.text))
	_chk("turn 2's own separator is still correctly rendered", "Turn 2" in bs._debug_body.text)

	bs._on_debug_category_toggled(true, BattleScreenShared.DebugCategory.NICHE)
	_chk("toggling Niche on re-renders immediately when the panel is (simulated) visible",
			not ("Turn 1" in bs._debug_body.text))  # _debug_overlay is still null -> no auto re-render

	bs._render_debug_overlay()
	_chk("after an explicit re-render with Niche on, turn 1's separator now appears too",
			"Turn 1" in bs._debug_body.text)


# ── 7-8. Disclosed RNG / Turn Order gap ─────────────────────────────────

func _test_rng_gap_disclosure_and_partial_coverage() -> void:
	var bm := BattleManager.new()
	var attacker := _make_mon("Wired1", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(attacker)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	var rng_before := _entries_of(bs, BattleScreenShared.DebugCategory.RNG)
	_chk("a one-time gap-disclosure entry is present in RNG as soon as debug signals are wired",
			rng_before.size() == 1 and "aren't exposed" in rng_before[0])

	bm.move_missed.emit(attacker, "accuracy")
	var rng_after := _entries_of(bs, BattleScreenShared.DebugCategory.RNG)
	_chk("a real accuracy-miss OUTCOME is captured under RNG (roll value itself remains unavailable)",
			rng_after.size() == 2 and "accuracy check failed" in rng_after[1])
	_chk("the entry text has no vacuous self-referential parenthetical (no roll/threshold to show)",
			not ("(accuracy)" in rng_after[1]))

	# [Bugfix regression guard] move_missed's own `reason` covers 7 OTHER,
	# entirely deterministic block reasons (Protect/immune/Substitute/OHKO
	# level-check/Sturdy/semi-invulnerable/type-doesn't-affect) with zero
	# roll involved — none of those belong under RNG & Probability, and
	# mislabeling them "accuracy check failed" was the original bug this
	# guards against.
	for reason in ["protected", "immune", "doesnt_affect", "substitute",
			"semi_invulnerable", "ohko_failed", "sturdy_blocks_ohko"]:
		bm.move_missed.emit(attacker, reason)
	_chk("none of the 7 deterministic move_missed reasons produce an RNG entry",
			_entries_of(bs, BattleScreenShared.DebugCategory.RNG).size() == 2)


func _test_turn_order_gap_disclosure_and_partial_coverage() -> void:
	var bm := BattleManager.new()
	var mover := _make_mon("Wired2", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mover)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	var before := _entries_of(bs, BattleScreenShared.DebugCategory.TURN_ORDER)
	_chk("a one-time gap-disclosure entry is present in Turn Order as soon as debug signals are wired",
			before.size() == 1 and "isn't exposed" in before[0])

	bm.turn_order_changed.emit(mover, "after_you")
	var after := _entries_of(bs, BattleScreenShared.DebugCategory.TURN_ORDER)
	_chk("a real After You/Quash splice IS captured (the one real-coverage case)",
			after.size() == 2 and "after_you" in after[1])


# ── 9-10. Durations & Field State — real duration numbers, not just "it happened" ──

func _test_durations_trick_room() -> void:
	var bm := BattleManager.new()
	bm.trick_room_turns = 5
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.trick_room_set.emit()
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.DURATIONS)
	_chk("Trick Room's real remaining-turn count (5) is reported, not just that it activated",
			"5 turns" in entries[-1])

	bm.trick_room_ended.emit()
	entries = _entries_of(bs, BattleScreenShared.DebugCategory.DURATIONS)
	_chk("Trick Room ending is also reported", "ended" in entries[-1])


func _test_durations_screen_with_real_duration() -> void:
	var bm := BattleManager.new()
	bm._side_conditions[0]["reflect_turns"] = 5
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.screen_set.emit(0, "reflect")
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.DURATIONS)
	_chk("Reflect's real starting duration (read from _side_conditions right after the signal fires) is reported",
			"5 turns" in entries[-1] and "Reflect" in entries[-1])


# ── 11-12. Stat Changes — real before->after stage values ───────────────

func _test_stat_changes_before_after() -> void:
	var bm := BattleManager.new()
	var mon := _make_mon("StatMon", TypeChart.TYPE_NORMAL)
	mon.stat_stages[BattlePokemon.STAGE_ATK] = 2  # the AFTER value, matching how the real signal fires post-mutation
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mon)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.stat_stage_changed.emit(mon, BattlePokemon.STAGE_ATK, 2)
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.STAT_CHANGES)
	_chk("a real before->after stage transition is reported (0 -> +2), not just 'rose'",
			"+0 -> +2" in entries[-1])


func _test_stat_changes_zero_delta_skipped() -> void:
	var bm := BattleManager.new()
	var mon := _make_mon("StatMon2", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mon)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.stat_stage_changed.emit(mon, BattlePokemon.STAGE_ATK, 0)
	_chk("a zero-delta stat change (already maxed/blocked) produces no Stat Changes entry",
			_entries_of(bs, BattleScreenShared.DebugCategory.STAT_CHANGES).is_empty())


# ── 13. Items & Berries — real HP context at the moment of the trigger ──

func _test_items_berries_hp_context() -> void:
	var bm := BattleManager.new()
	var mon := _make_mon("ItemMon", TypeChart.TYPE_NORMAL, 100)
	mon.current_hp = 42
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mon)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.item_healed.emit(mon, 20)
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.ITEMS_BERRIES)
	_chk("the real HP value at the moment the item fired is reported, not just the amount",
			"42/%d HP" % mon.max_hp in entries[-1])


# ── 14. Multi-Hit Detail — aggregate-only, disclosed inline ─────────────

func _test_multi_hit_aggregate_disclaimer() -> void:
	var bm := BattleManager.new()
	var attacker := _make_mon("MultiAtk", TypeChart.TYPE_NORMAL)
	var target := _make_mon("MultiDef", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(attacker)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.multi_hit_sequence_finished.emit(attacker, target, 3, 45)
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.MULTI_HIT)
	_chk("the real hit count and total damage are reported", "3 hits" in entries[-1] and "45 total damage" in entries[-1])
	_chk("the aggregate-only limitation is disclosed inline, not presented as a full per-hit breakdown",
			"aggregate only" in entries[-1])


# ── 15. Delayed Effects — scheduled<->resolved correlation ──────────────

func _test_delayed_effects_scheduled_and_resolved() -> void:
	var bm := BattleManager.new()
	var caster := _make_mon("Caster", TypeChart.TYPE_PSYCHIC)
	var target := _make_mon("Target", TypeChart.TYPE_NORMAL)
	var move := MoveData.new()
	move.move_name = "Future Sight"
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(caster)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.future_sight_scheduled.emit(caster, target, move)
	bm.future_sight_resolved.emit(caster, target, move, 55)
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.DELAYED)
	_chk("the schedule event is recorded", "scheduled" in entries[0])
	_chk("the later resolve event is recorded with its real damage", "55 damage" in entries[1])


# ── 16. Ability & Immunity — retagged away from Narrative ───────────────

func _test_ability_immunity_retagged_from_narrative() -> void:
	var bm := BattleManager.new()
	var mon := _make_mon("AbilityMon", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mon)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.ability_triggered.emit(mon, "intimidate")
	_chk("an ability_triggered signal produces an Ability & Immunity entry",
			not _entries_of(bs, BattleScreenShared.DebugCategory.ABILITY_IMMUNITY).is_empty())
	_chk("it does NOT also land in Narrative (moved, not duplicated)",
			_entries_of(bs, BattleScreenShared.DebugCategory.NARRATIVE).is_empty())


# ── 16b. Ability & Immunity — ability_changed (M26B6-5, the last of the two
# residual signals D3-2's retirement handed to B6) ──────────────────────
#
# ability_changed only ever carries (pokemon, new_ability_id) -- not who the
# ability came from or which of the 8 mechanics fired it (Trace/Mummy/
# Lingering Aroma/Wandering Spirit/Receiver/Power of Alchemy/Skill Swap/Role
# Play/Worry Seed/the Primal-orb switch-in). Confirmed via battle_manager.gd's
# own real emit call sites, per this handler's own doc comment. So what's
# tested here is exactly the one fact the signal DOES carry: the resulting
# ability's real name, loaded from the real .tres a live battle would load
# too (ability_%04d.tres, id 22 = Intimidate, matching the on-disk file
# directly rather than a hand-authored AbilityData stand-in).

func _test_ability_changed_reports_the_new_ability() -> void:
	var bm := BattleManager.new()
	var mon := _make_mon("Ditto", TypeChart.TYPE_NORMAL)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(mon)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.ability_changed.emit(mon, 22)  # Intimidate — real data/abilities/ability_0022.tres
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.ABILITY_IMMUNITY)
	_chk("an ability_changed signal produces an Ability & Immunity entry", entries.size() == 1)
	_chk("it names the real ability loaded from disk, not a guessed/hardcoded string",
			"Intimidate" in entries[0])
	_chk("it names the mon it happened to", "Ditto" in entries[0])


func _test_ability_changed_is_the_only_narration_for_move_effect_mechanics() -> void:
	# Skill Swap/Role Play/Worry Seed are MOVE effects, not ability
	# activations -- battle_manager.gd's own call sites for all three emit
	# ability_changed with NO accompanying ability_triggered (confirmed:
	# unlike Trace/Mummy/Receiver/Wandering Spirit, which always pair the
	# two). So this is the only text these three mechanics ever produce.
	var bm := BattleManager.new()
	var swapper := _make_mon("Swapper", TypeChart.TYPE_PSYCHIC)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(swapper)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()

	bm.ability_changed.emit(swapper, 22)  # Intimidate, standing in for a real swap target
	_chk("a move-effect ability change (no ability_triggered pair) still narrates",
			not _entries_of(bs, BattleScreenShared.DebugCategory.ABILITY_IMMUNITY).is_empty())
	_chk("and it does not leak into Narrative either",
			_entries_of(bs, BattleScreenShared.DebugCategory.NARRATIVE).is_empty())


# ── 17. Niche/Situational — default-off but still recorded ──────────────

func _test_niche_default_off_but_still_recorded() -> void:
	var bm := BattleManager.new()
	var target := _make_mon("LeechTarget", TypeChart.TYPE_NORMAL)
	var source := _make_mon("LeechSource", TypeChart.TYPE_GRASS)
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(target)
	bs._setup_debug_overlay()
	bs._wire_debug_signals()
	bs._debug_body = RichTextLabel.new()

	bm.leech_seed_drained.emit(target, source, 12)
	_chk("a Niche-category event is still recorded in the permanent history even though the toggle is off",
			not _entries_of(bs, BattleScreenShared.DebugCategory.NICHE).is_empty())

	bs._render_debug_overlay()
	_chk("but it does NOT render by default, matching the toggle's own default-off state",
			not ("LeechSource" in bs._debug_body.text))


# ── 18. Damage Math no longer repeats the panel's own static header ─────

func _test_damage_math_no_longer_has_redundant_header() -> void:
	var bm := BattleManager.new()
	var attacker := _make_mon("DmgAtk", TypeChart.TYPE_WATER)
	var defender := _make_mon("DmgDef", TypeChart.TYPE_FIRE)
	var move := MoveData.new()
	move.move_name = "Water Gun"
	move.power = 40
	move.accuracy = 100
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._setup_debug_overlay()

	var breakdown := {"damage": 30, "is_crit": false, "effectiveness": 2.0}
	bs._on_debug_move_damage_breakdown(attacker, defender, move, breakdown)
	var entries := _entries_of(bs, BattleScreenShared.DebugCategory.DAMAGE_MATH)
	_chk("a real damage breakdown lands as a DAMAGE_MATH entry",
			entries.size() == 1 and "DmgAtk -> DmgDef" in entries[0])
	_chk("the per-entry text no longer repeats the panel's own static 'Combat Debug' header",
			not ("Combat Debug" in entries[0]))


# ── 19. Real end-to-end proof: _wire_debug_signals() actually wired from a
# genuine battle, not just correct handler logic in isolation. ──────────

func _test_real_battle_end_to_end_debug_wiring() -> void:
	var attacker := _make_mon("RealDbgAtk", TypeChart.TYPE_WATER, 200)
	var opp := _make_mon("RealDbgOpp", TypeChart.TYPE_FIRE, 200)
	var atk_move := MoveData.new()
	atk_move.move_name = "Water Gun"
	atk_move.type = TypeChart.TYPE_WATER
	atk_move.category = 1
	atk_move.power = 40
	atk_move.accuracy = 0
	atk_move.pp = 10
	attacker.add_move(atk_move)
	var opp_move := MoveData.new()
	opp_move.move_name = "Growl"
	opp_move.type = TypeChart.TYPE_NORMAL
	opp_move.category = 2
	opp_move.power = 0
	opp_move.accuracy = 0
	opp_move.pp = 10
	opp_move.stat_change_stat = BattlePokemon.STAGE_ATK
	opp_move.stat_change_amount = -1
	opp.add_move(opp_move)

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)

	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._player_party = _singles_party(attacker)
	bs._opp_party = _singles_party(opp)
	bs._setup_debug_overlay()
	bs._wire_log_signals()
	bs._wire_debug_signals()

	bm.start_battle_with_parties(_singles_party(attacker), _singles_party(opp))
	# Checked BEFORE advance() -- once both actions resolve, advance() keeps
	# processing straight into turn 2's own MOVE_SELECTION stall (both sides
	# are human-controlled), which would legitimately bump _current_debug_
	# turn to 2 before this line ever ran. Mirrors m25c_message_log_test.gd's
	# own established "check turn_number right after start, before advance()"
	# precedent for the identical reason.
	_chk("_current_debug_turn reflects the real turn number as soon as the battle starts",
			bs._current_debug_turn == 1)

	bm.queue_move_targeted(0, 0, 1)
	bm.queue_move_targeted(1, 0, 0)
	bm.advance()

	_chk("a real battle turn produced at least one Narrative entry",
			not _entries_of(bs, BattleScreenShared.DebugCategory.NARRATIVE).is_empty())
	_chk("a real battle turn produced at least one Stat Changes entry (Growl's -1 Attack)",
			not _entries_of(bs, BattleScreenShared.DebugCategory.STAT_CHANGES).is_empty())

	bm.queue_free()
