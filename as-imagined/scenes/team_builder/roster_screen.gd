extends Control

# [M23.5] Basic roster screen — list/create/edit/delete a saved team of up
# to 6 Pokémon, persisted via TeamStorage (scripts/data/team_storage.gd —
# see that file's own doc comment for the persistence-format decision and
# reasoning). This screen adds "assemble N built Pokémon into a named,
# saved team" on top of M23.4's team_builder_screen — it does NOT touch
# that screen's own species/moveset/ability/nature/EV/IV building or
# legality logic (the only changes there were the small, additive
# `pokemon_built` signal / `get_current_spec()` accessor this screen
# consumes). Battle setup/format selection and wiring a saved team into
# the battle screen are both explicitly M23.6 — out of scope here.
#
# [UI mechanism] Two mutually-exclusive panels (ListView / EditorView)
# toggled via `.visible`, each internally rebuilt-from-scratch on state
# change — matching M23.1/M23.4's own "rebuild the affected dynamic area,
# don't toggle individual pre-declared nodes" convention for the TRULY
# dynamic parts (the team list rows, the 6 slot rows), while the
# List-vs-Editor split itself is a coarser visibility toggle. Flagged as a
# reasonable adaptation, not identical precedent: M23.1/M23.4 never had two
# whole separate "modes" to switch between, only ever a single dynamic
# button/content area within one mode.
#
# [Building a slot] Reuses M23.4's team_builder_screen.tscn directly — a
# fresh instance is instantiated and embedded under BuilderHost each time
# "Add"/"Replace" is pressed on a slot, then freed once that slot's build
# completes or is cancelled (matching this project's own "throwaway,
# rebuilt fresh" convention rather than trying to reset/reuse one instance
# across multiple slots). [Flagged design decision] Editing an already-
# filled slot does NOT pre-populate the embedded builder with that slot's
# existing species/moves/EVs/etc. — "Replace" always starts the builder
# blank, i.e. editing a slot means fully re-building that Pokémon from
# scratch, not tweaking one field of the old one. This keeps the
# integration surface with team_builder_screen.gd minimal (a signal + a
# read-only spec accessor, nothing that reaches into or replays its
# internal widget state) at the cost of a less convenient "just change one
# EV" edit flow — a real, disclosed trade-off, not an oversight. A future
# `load_spec()`-style pre-population method on team_builder_screen.gd would
# be a reasonable, low-risk follow-up if Rob wants it.
#
# [Delete has no confirmation step] A single button press deletes a team
# immediately — matches M23.1's own "plain functional buttons, no polish"
# precedent (no dialog/modal convention exists anywhere in this project
# yet). Flagged, not silently under-built: a two-step "press again to
# confirm" or a real confirmation dialog would be a reasonable follow-up.

const _NATURE_NAMES: Array[String] = [
	"Hardy", "Lonely", "Brave", "Adamant", "Naughty",
	"Bold", "Docile", "Relaxed", "Impish", "Lax",
	"Timid", "Hasty", "Serious", "Jolly", "Naive",
	"Modest", "Mild", "Quiet", "Bashful", "Rash",
	"Calm", "Gentle", "Sassy", "Careful", "Quirky",
]

@onready var _status_label: Label = $Scroll/VBox/StatusLabel
@onready var _list_view: VBoxContainer = $Scroll/VBox/ListView
@onready var _team_list_container: VBoxContainer = $Scroll/VBox/ListView/TeamListContainer
@onready var _new_team_name_edit: LineEdit = $Scroll/VBox/ListView/NewTeamRow/NewTeamNameEdit
@onready var _create_team_button: Button = $Scroll/VBox/ListView/NewTeamRow/CreateTeamButton

@onready var _editor_view: VBoxContainer = $Scroll/VBox/EditorView
@onready var _editor_name_edit: LineEdit = $Scroll/VBox/EditorView/EditorNameRow/EditorNameEdit
@onready var _slots_container: VBoxContainer = $Scroll/VBox/EditorView/SlotsContainer
@onready var _cancel_builder_row: HBoxContainer = $Scroll/VBox/EditorView/CancelBuilderRow
@onready var _cancel_builder_button: Button = $Scroll/VBox/EditorView/CancelBuilderRow/CancelBuilderButton
@onready var _builder_host: VBoxContainer = $Scroll/VBox/EditorView/BuilderHost
@onready var _save_team_button: Button = $Scroll/VBox/EditorView/EditorButtonsRow/SaveTeamButton
@onready var _cancel_editor_button: Button = $Scroll/VBox/EditorView/EditorButtonsRow/CancelEditorButton

var _editing_team_id: String = ""  # "" means "creating a new team."
var _slot_specs: Array = [null, null, null, null, null, null]
var _active_slot_index: int = -1
var _builder_instance: Node = null


func _ready() -> void:
	_create_team_button.pressed.connect(_on_create_team_pressed)
	_save_team_button.pressed.connect(_on_save_team_pressed)
	_cancel_editor_button.pressed.connect(_on_cancel_editor_pressed)
	_cancel_builder_button.pressed.connect(_on_cancel_builder_pressed)
	_show_list_view()


# ── List view ─────────────────────────────────────────────────────────────

func _show_list_view() -> void:
	_remove_active_builder()
	_list_view.visible = true
	_editor_view.visible = false
	_refresh_list()


func _refresh_list() -> void:
	for child in _team_list_container.get_children():
		child.queue_free()

	var teams := TeamStorage.list_teams()
	if teams.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no saved teams yet)"
		_team_list_container.add_child(empty_label)

	for summary in teams:
		var row := HBoxContainer.new()

		var label := Label.new()
		if summary["corrupted"]:
			label.text = "%s" % summary["name"]
		else:
			label.text = "%s  (%d member%s)" % [
				summary["name"], summary["member_count"],
				"" if summary["member_count"] == 1 else "s"]
		label.custom_minimum_size = Vector2(260, 0)
		row.add_child(label)

		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		edit_btn.disabled = summary["corrupted"]
		edit_btn.pressed.connect(_on_edit_team_pressed.bind(summary["id"]))
		row.add_child(edit_btn)

		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.pressed.connect(_on_delete_team_pressed.bind(summary["id"]))
		row.add_child(delete_btn)

		_team_list_container.add_child(row)


func _on_create_team_pressed() -> void:
	var name := _new_team_name_edit.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter a team name before creating a team."
		return
	if TeamStorage.name_exists(name):
		_status_label.text = "A team named '%s' already exists — choose a different name." % name
		return

	_editing_team_id = ""
	_slot_specs = [null, null, null, null, null, null]
	_editor_name_edit.text = name
	_new_team_name_edit.text = ""
	_status_label.text = "Building a new team. Add up to 6 Pokémon, then Save Team."
	_show_editor_view()


func _on_edit_team_pressed(id: String) -> void:
	var team := TeamStorage.load_team(id)
	if team.is_empty():
		_status_label.text = "That team could not be loaded (corrupted save)."
		_refresh_list()
		return

	_editing_team_id = id
	_slot_specs = [null, null, null, null, null, null]
	var members: Array = team.get("members", [])
	for i in range(min(members.size(), _slot_specs.size())):
		_slot_specs[i] = members[i]
	_editor_name_edit.text = team.get("name", "")
	_status_label.text = "Editing '%s'." % team.get("name", "")
	_show_editor_view()


func _on_delete_team_pressed(id: String) -> void:
	TeamStorage.delete_team(id)
	_status_label.text = "Deleted."
	_refresh_list()


# ── Editor view ───────────────────────────────────────────────────────────

func _show_editor_view() -> void:
	_list_view.visible = false
	_editor_view.visible = true
	_refresh_slots()


func _refresh_slots() -> void:
	for child in _slots_container.get_children():
		child.queue_free()

	for i in range(_slot_specs.size()):
		var spec = _slot_specs[i]
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = "Slot %d: %s" % [i + 1, _slot_summary_text(spec)]
		label.custom_minimum_size = Vector2(320, 0)
		row.add_child(label)

		var action_btn := Button.new()
		action_btn.text = "Replace" if spec != null else "Add"
		action_btn.disabled = _builder_instance != null
		action_btn.pressed.connect(_on_slot_action_pressed.bind(i))
		row.add_child(action_btn)

		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.disabled = spec == null or _builder_instance != null
		remove_btn.pressed.connect(_on_slot_remove_pressed.bind(i))
		row.add_child(remove_btn)

		_slots_container.add_child(row)


func _slot_summary_text(spec) -> String:
	if spec == null:
		return "(empty)"
	var species_data: Dictionary = PokemonRegistry.get_species(int(spec.get("dex", -1)))
	var species_name: String = species_data.get("name", "?")
	var nature_id: int = int(spec.get("nature", 0))
	var nature_name: String = _NATURE_NAMES[nature_id] if nature_id >= 0 and nature_id < _NATURE_NAMES.size() else "?"
	var move_count: int = spec.get("move_ids", []).size()
	return "%s  Lv.%d  %s  (%d move%s)" % [
		species_name, int(spec.get("level", 1)), nature_name,
		move_count, "" if move_count == 1 else "s"]


func _on_slot_action_pressed(index: int) -> void:
	if _builder_instance != null:
		return
	_active_slot_index = index
	var scene: PackedScene = load("res://scenes/team_builder/team_builder_screen.tscn")
	_builder_instance = scene.instantiate()
	_builder_instance.pokemon_built.connect(_on_slot_pokemon_built)
	_builder_host.add_child(_builder_instance)
	_cancel_builder_row.visible = true
	_status_label.text = "Building Pokémon for slot %d — use the builder below, then press Build Pokémon." % (index + 1)
	_refresh_slots()


func _on_slot_pokemon_built(spec: Dictionary, _bp: BattlePokemon) -> void:
	if _active_slot_index < 0:
		return
	_slot_specs[_active_slot_index] = spec
	_status_label.text = "Slot %d set." % (_active_slot_index + 1)
	_remove_active_builder()
	_refresh_slots()


func _on_slot_remove_pressed(index: int) -> void:
	if index < 0 or index >= _slot_specs.size():
		return
	_slot_specs[index] = null
	_refresh_slots()


func _on_cancel_builder_pressed() -> void:
	_remove_active_builder()
	_status_label.text = "Cancelled — slot unchanged."
	_refresh_slots()


func _remove_active_builder() -> void:
	if _builder_instance != null:
		_builder_instance.queue_free()
		_builder_instance = null
	_active_slot_index = -1
	_cancel_builder_row.visible = false


func _on_save_team_pressed() -> void:
	var name := _editor_name_edit.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter a team name before saving."
		return

	var members: Array[Dictionary] = []
	for spec in _slot_specs:
		if spec != null:
			members.append(spec)
	if members.is_empty():
		_status_label.text = "Add at least one Pokémon before saving."
		return

	if TeamStorage.name_exists(name, _editing_team_id):
		_status_label.text = "A team named '%s' already exists — choose a different name." % name
		return

	var id: String = _editing_team_id if _editing_team_id != "" else TeamStorage.generate_id()
	if not TeamStorage.save_team(id, name, members):
		_status_label.text = "Save failed."
		return

	_status_label.text = "Saved '%s' (%d member%s)." % [name, members.size(), "" if members.size() == 1 else "s"]
	_show_list_view()


func _on_cancel_editor_pressed() -> void:
	_status_label.text = "Cancelled — no changes saved."
	_show_list_view()
