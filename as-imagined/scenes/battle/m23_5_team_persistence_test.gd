extends Node

# [M23.5] Team persistence — automated headless test suite. Covers
# TeamStorage's save/load/delete/list API directly (Section 1) plus a real
# button-press-driven walkthrough of the actual roster_screen.tscn +
# embedded team_builder_screen.tscn (Section 2), matching M23.4's own
# established "instantiate the real scene, fire real signals" precedent
# rather than re-implementing the screens' logic in test code.
#
# This is the FIRST test in this project that touches real on-disk state
# (user://teams/, not just res:// static data or in-memory objects) — see
# _cleanup() at the bottom: every team this suite creates is tracked by ID
# and deleted at the end regardless of pass/fail, and every assertion below
# checks specific, uniquely-prefixed team IDs/names rather than the full
# list_teams() output, so this suite is safe to run repeatedly (including
# alongside real save data from manual verification) without accumulating
# cruft or tripping the duplicate-name guard on a rerun.
#
# Per this milestone's own requirement 9, this is a headless SAME-PROCESS
# save-then-load check — it does NOT and cannot verify persistence across a
# real process restart (Godot's own process can't restart itself
# mid-test); that's covered separately by a real 3-process manual
# verification (see docs/m23_recon.md's M23.5 section for the transcript).

const _NAME_PREFIX := "__M23_5_TEST__"

var _pass := 0
var _fail := 0
var _cleanup_ids: Array[String] = []


func _ready() -> void:
	_test_section_1_storage_api()
	await _test_section_2_ui_driven_flow()

	_cleanup()

	var total := _pass + _fail
	print("m23_5_team_persistence_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for id in _cleanup_ids:
		TeamStorage.delete_team(id)


# ── Section 1: TeamStorage direct API ────────────────────────────────────

func _test_section_1_storage_api() -> void:
	var id1 := TeamStorage.generate_id()
	var id2 := TeamStorage.generate_id()
	_chk("S1.01 generate_id produces distinct IDs on separate calls", id1 != id2)

	# Round-trip: a single-member team.
	var bulba_spec := {
		"dex": 1, "level": 20, "move_ids": [33, 45], "nature": BattlePokemon.NATURE_ADAMANT,
		"evs": [0, 100, 0, 0, 0, 50], "ivs": [31, 31, 10, 31, 31, 31],
		"ability_slot": PokemonFactory.ABILITY_SLOT_PRIMARY,
	}
	var name1 := _NAME_PREFIX + "RoundTrip"
	_cleanup_ids.append(id1)
	var saved := TeamStorage.save_team(id1, name1, [bulba_spec])
	_chk("S1.02 save_team succeeds for a valid single-member team", saved)

	var loaded := TeamStorage.load_team(id1)
	_chk("S1.03 load_team returns a non-empty dict for a saved team", not loaded.is_empty())
	_chk("S1.04 loaded name matches exactly", loaded.get("name", "") == name1)
	_chk("S1.05 loaded member count is 1", loaded.get("members", []).size() == 1)

	var loaded_member: Dictionary = loaded["members"][0]
	_chk("S1.06 loaded dex matches", loaded_member["dex"] == 1)
	_chk("S1.07 loaded level matches", loaded_member["level"] == 20)
	_chk("S1.08 loaded move_ids matches exactly (order preserved)", loaded_member["move_ids"] == [33, 45])
	_chk("S1.09 loaded nature matches", loaded_member["nature"] == BattlePokemon.NATURE_ADAMANT)
	_chk("S1.10 loaded evs matches exactly", loaded_member["evs"] == [0, 100, 0, 0, 0, 50])
	_chk("S1.11 loaded ivs matches exactly", loaded_member["ivs"] == [31, 31, 10, 31, 31, 31])
	_chk("S1.12 loaded ability_slot matches", loaded_member["ability_slot"] == PokemonFactory.ABILITY_SLOT_PRIMARY)
	for key in ["dex", "level", "nature", "ability_slot"]:
		_chk("S1.13 loaded %s is a real int, not a leftover JSON float" % key, typeof(loaded_member[key]) == TYPE_INT)

	# build_member reconstructs a real BattlePokemon matching a direct
	# PokemonFactory call with the same inputs.
	var built := TeamStorage.build_member(bulba_spec)
	var direct := PokemonFactory.create_battle_pokemon(1, 20, [33, 45], BattlePokemon.NATURE_ADAMANT,
			[31, 31, 10, 31, 31, 31], null, [0, 100, 0, 0, 0, 50], PokemonFactory.ABILITY_SLOT_PRIMARY)
	_chk("S1.14 build_member reconstructs a BattlePokemon matching a direct PokemonFactory call",
			built != null and built.max_hp == direct.max_hp and built.attack == direct.attack
			and built.species.species_name == direct.species.species_name)

	# Edge case: empty team rejected.
	_chk("S1.15 save_team rejects an empty member list", not TeamStorage.save_team(TeamStorage.generate_id(), "should not save", []))

	# Edge case: partial team (fewer than 6 members) — explicitly valid.
	var id_partial := TeamStorage.generate_id()
	_cleanup_ids.append(id_partial)
	var name_partial := _NAME_PREFIX + "Partial"
	var partial_ok := TeamStorage.save_team(id_partial, name_partial, [bulba_spec, bulba_spec, bulba_spec])
	_chk("S1.16 save_team accepts a partial (3-member) team", partial_ok)
	_chk("S1.17 loaded partial team has exactly 3 members", TeamStorage.load_team(id_partial).get("members", []).size() == 3)

	# list_teams reflects both saved teams.
	var ids_seen: Dictionary = {}
	var names_seen: Dictionary = {}
	for summary in TeamStorage.list_teams():
		ids_seen[summary["id"]] = true
		names_seen[summary["name"]] = summary["member_count"]
	_chk("S1.18 list_teams includes both teams created above", ids_seen.has(id1) and ids_seen.has(id_partial))
	_chk("S1.19 list_teams reports the correct member_count per team",
			names_seen.get(name1, -1) == 1 and names_seen.get(name_partial, -1) == 3)

	# name_exists — including the exclude_id case an in-progress edit needs.
	_chk("S1.20 name_exists is true for an already-saved name", TeamStorage.name_exists(name1))
	_chk("S1.21 name_exists is false for a name never saved", not TeamStorage.name_exists(_NAME_PREFIX + "NeverSaved"))
	_chk("S1.22 name_exists excludes the team's own id when checking its own unchanged name",
			not TeamStorage.name_exists(name1, id1))

	# Missing / corrupted save file handling.
	_chk("S1.23 load_team on a never-existing id returns an empty dict", TeamStorage.load_team("no_such_team_id_at_all").is_empty())

	var corrupt_id := "team_%d_corrupt" % Time.get_unix_time_from_system()
	_cleanup_ids.append(corrupt_id)
	var corrupt_path := TeamStorage.TEAMS_DIR + corrupt_id + ".json"
	DirAccess.make_dir_recursive_absolute(TeamStorage.TEAMS_DIR)
	var f := FileAccess.open(corrupt_path, FileAccess.WRITE)
	f.store_string("{ this is not valid json at all ]]]")
	f.close()
	_chk("S1.24 load_team on a corrupted file returns an empty dict (not a crash)", TeamStorage.load_team(corrupt_id).is_empty())
	var found_corrupt := false
	for summary in TeamStorage.list_teams():
		if summary["id"] == corrupt_id:
			found_corrupt = true
			_chk("S1.25 list_teams flags the corrupted entry as corrupted", summary["corrupted"] == true)
	_chk("S1.26 the corrupted file is still listed (not silently dropped)", found_corrupt)

	# Deleting a team that doesn't exist is a silent no-op, not a crash.
	TeamStorage.delete_team("this_id_was_never_saved_either")
	_chk("S1.27 delete_team on a nonexistent id doesn't crash (reached this line)", true)

	# Real delete.
	var id_to_delete := TeamStorage.generate_id()
	TeamStorage.save_team(id_to_delete, _NAME_PREFIX + "ToDelete", [bulba_spec])
	TeamStorage.delete_team(id_to_delete)
	_chk("S1.28 load_team on a just-deleted id returns an empty dict", TeamStorage.load_team(id_to_delete).is_empty())
	var still_listed := false
	for summary in TeamStorage.list_teams():
		if summary["id"] == id_to_delete:
			still_listed = true
	_chk("S1.29 a deleted team no longer appears in list_teams", not still_listed)


# ── Section 2: real UI-driven roster flow ────────────────────────────────

func _instantiate_roster() -> Node:
	var scene: PackedScene = load("res://scenes/team_builder/roster_screen.tscn")
	var instance := scene.instantiate()
	add_child(instance)
	return instance


# Drives the embedded team_builder_screen (already instantiated by pressing
# a slot's Add/Replace button) through a real build via genuine
# Button.pressed.emit() calls, matching m23_4_team_builder_test.gd's own
# established pattern.
func _drive_embedded_build(roster: Node, dex: int, level: int, move_ids: Array, nature: int) -> void:
	var builder: Node = roster._builder_instance
	var species_edit: LineEdit = builder.get_node("Scroll/VBox/SpeciesRow/SpeciesLineEdit")
	var load_btn: Button = builder.get_node("Scroll/VBox/SpeciesRow/LoadSpeciesButton")
	species_edit.text = str(dex)
	load_btn.pressed.emit()

	var level_spin: SpinBox = builder.get_node("Scroll/VBox/LevelRow/LevelSpinBox")
	level_spin.value = level

	var nature_option: OptionButton = builder.get_node("Scroll/VBox/NatureRow/NatureOptionButton")
	nature_option.select(nature_option.get_item_index(nature))

	var available_option: OptionButton = builder.get_node("Scroll/VBox/MovesSection/AddMoveRow/AvailableMovesOptionButton")
	var add_move_btn: Button = builder.get_node("Scroll/VBox/MovesSection/AddMoveRow/AddMoveButton")
	for move_id in move_ids:
		for i in range(available_option.item_count):
			if available_option.get_item_id(i) == move_id:
				available_option.select(i)
				add_move_btn.pressed.emit()
				break

	var build_btn: Button = builder.get_node("Scroll/VBox/BuildButton")
	build_btn.pressed.emit()


func _test_section_2_ui_driven_flow() -> void:
	var roster := _instantiate_roster()

	# ── Create a 2-member team via real roster + embedded-builder clicks ──
	var team_name := _NAME_PREFIX + "UI_Team"
	var name_edit: LineEdit = roster.get_node("Scroll/VBox/ListView/NewTeamRow/NewTeamNameEdit")
	var create_btn: Button = roster.get_node("Scroll/VBox/ListView/NewTeamRow/CreateTeamButton")
	name_edit.text = team_name
	create_btn.pressed.emit()
	_chk("S2.01 pressing Create Team switches to the editor view",
			roster.get_node("Scroll/VBox/EditorView").visible and not roster.get_node("Scroll/VBox/ListView").visible)

	# Slot 0: Bulbasaur.
	roster._on_slot_action_pressed(0)
	_chk("S2.02 pressing a slot's Add button embeds a real team_builder_screen instance", roster._builder_instance != null)
	# [Bugfix regression guard] A real bug shipped here once: the embedded
	# instance was genuinely instantiated/added/`visible == true` (every
	# check above this line already passed) but rendered at a real,
	# confirmed-via-screenshot ZERO height — BuilderHost is a
	# VBoxContainer, and Godot's Container layout silently overrides an
	# anchor-laid-out child's own anchors entirely, collapsing it to
	# whatever its own (absent) custom_minimum_size provided: nothing.
	# Confirmed this collapse is fully visible in --headless mode too (not
	# a rendering-only symptom) — the ONLY reason this shipped was that no
	# assertion here had ever checked the resulting Control's actual size,
	# only its existence/parentage. One process_frame await lets the
	# deferred container-sort settle before checking.
	await get_tree().process_frame
	await get_tree().process_frame
	_chk("S2.02b the embedded builder actually has a real, nonzero rendered size (not collapsed by its Container parent)",
			roster._builder_instance.size.y > 0)
	_drive_embedded_build(roster, 1, 15, [33, 45], BattlePokemon.NATURE_BOLD)
	_chk("S2.03 slot 0 is populated after the embedded build completes", roster._slot_specs[0] != null)
	_chk("S2.04 the embedded builder instance is freed after the slot completes", roster._builder_instance == null)

	# Slot 1: Charmander.
	roster._on_slot_action_pressed(1)
	_drive_embedded_build(roster, 4, 25, [52], BattlePokemon.NATURE_MODEST)
	_chk("S2.05 slot 1 is populated with a DIFFERENT species than slot 0",
			roster._slot_specs[1] != null and roster._slot_specs[1]["dex"] != roster._slot_specs[0]["dex"])

	var save_btn: Button = roster.get_node("Scroll/VBox/EditorView/EditorButtonsRow/SaveTeamButton")
	save_btn.pressed.emit()
	_chk("S2.06 pressing Save Team returns to the list view",
			roster.get_node("Scroll/VBox/ListView").visible and not roster.get_node("Scroll/VBox/EditorView").visible)

	var saved_id := ""
	for summary in TeamStorage.list_teams():
		if summary["name"] == team_name:
			saved_id = summary["id"]
	_cleanup_ids.append(saved_id)
	_chk("S2.07 the UI-created team is genuinely on disk (found via TeamStorage.list_teams)", saved_id != "")

	var reloaded := TeamStorage.load_team(saved_id)
	_chk("S2.08 the UI-created team round-trips with exactly 2 members", reloaded.get("members", []).size() == 2)
	_chk("S2.09 member 0's fields match what was entered in the embedded builder",
			reloaded["members"][0]["dex"] == 1 and reloaded["members"][0]["level"] == 15
			and reloaded["members"][0]["nature"] == BattlePokemon.NATURE_BOLD
			and reloaded["members"][0]["move_ids"] == [33, 45])
	_chk("S2.10 member 1's fields match what was entered in the embedded builder",
			reloaded["members"][1]["dex"] == 4 and reloaded["members"][1]["level"] == 25
			and reloaded["members"][1]["nature"] == BattlePokemon.NATURE_MODEST)

	# ── Duplicate-name rejection ──────────────────────────────────────────
	name_edit.text = team_name  # same name as the team just saved
	create_btn.pressed.emit()
	_chk("S2.11 attempting to create a second team with an already-used name is blocked (stays on list view)",
			roster.get_node("Scroll/VBox/ListView").visible)
	var count_with_name := 0
	for summary in TeamStorage.list_teams():
		if summary["name"] == team_name:
			count_with_name += 1
	_chk("S2.12 only one team with that name actually exists on disk", count_with_name == 1)

	# ── Edit flow: replace slot 1, confirm the change persists ────────────
	var edit_btn := _find_row_button(roster, team_name, 0)  # 0 = Edit button index
	edit_btn.pressed.emit()
	_chk("S2.13 pressing Edit switches to the editor view pre-loaded with the saved members",
			roster._slot_specs[0] != null and roster._slot_specs[0]["dex"] == 1
			and roster._slot_specs[1] != null and roster._slot_specs[1]["dex"] == 4)

	roster._on_slot_action_pressed(1)
	_drive_embedded_build(roster, 7, 30, [55], BattlePokemon.NATURE_TIMID)  # Squirtle, replacing Charmander
	_chk("S2.14 slot 1 now holds the replacement species", roster._slot_specs[1]["dex"] == 7)

	save_btn.pressed.emit()
	var reloaded_after_edit := TeamStorage.load_team(saved_id)
	_chk("S2.15 the edit persists under the SAME team id (not a duplicate)",
			reloaded_after_edit.get("members", []).size() == 2
			and reloaded_after_edit["members"][0]["dex"] == 1
			and reloaded_after_edit["members"][1]["dex"] == 7)
	var teams_with_saved_id := 0
	for summary in TeamStorage.list_teams():
		if summary["id"] == saved_id:
			teams_with_saved_id += 1
	_chk("S2.16 editing did not create a second team file", teams_with_saved_id == 1)

	# ── Cancel-mid-build discards the in-progress slot ─────────────────────
	edit_btn = _find_row_button(roster, team_name, 0)
	edit_btn.pressed.emit()
	roster._on_slot_action_pressed(1)
	_drive_embedded_build(roster, 25, 40, [], BattlePokemon.NATURE_HARDY)  # Pikachu — not yet committed
	var cancel_editor_btn: Button = roster.get_node("Scroll/VBox/EditorView/EditorButtonsRow/CancelEditorButton")
	cancel_editor_btn.pressed.emit()
	var reloaded_after_cancel := TeamStorage.load_team(saved_id)
	_chk("S2.17 pressing Cancel on the editor discards any changes (still Squirtle, not Pikachu)",
			reloaded_after_cancel["members"][1]["dex"] == 7)

	# ── Delete flow ─────────────────────────────────────────────────────────
	var delete_btn := _find_row_button(roster, team_name, 1)  # 1 = Delete button index
	delete_btn.pressed.emit()
	_chk("S2.18 after pressing Delete, the team no longer loads", TeamStorage.load_team(saved_id).is_empty())
	var still_in_list := false
	for summary in TeamStorage.list_teams():
		if summary["id"] == saved_id:
			still_in_list = true
	_chk("S2.19 the deleted team no longer appears in the roster list", not still_in_list)

	roster.queue_free()


# Finds the Edit (button_index=0) or Delete (button_index=1) button for the
# row whose label starts with `team_name`, by walking the REAL dynamically-
# built rows under TeamListContainer — the same nodes a real click would
# hit, not a re-derived reference.
func _find_row_button(roster: Node, team_name: String, button_index: int) -> Button:
	var container: VBoxContainer = roster.get_node("Scroll/VBox/ListView/TeamListContainer")
	for row in container.get_children():
		var label: Label = row.get_child(0)
		if label.text.begins_with(team_name):
			return row.get_child(1 + button_index)
	return null
