@tool
extends AcceptDialog

## [M27M5c Phase 1] "Make me a map," without a command line.
##
## ⚠️ **CONTAINS NO RULES.** Which tileset pairs can be built on, what fill a
## pair implies, whether a name is already taken, how a `MAP_AUTHORED_*`
## constant is derived and registered — every one of those lives in
## `MapAuthoring` and is driven by `m27a_step_resolver_test` section BB. This
## is four inputs and a results label. Same split as `name_usage_dialog.gd`/
## `NameUsage` and `entity_inspector.gd`/`ScriptPreview`, for the reason
## `plugin.gd` records: this addon is the project's one surface with no
## automated coverage, so a dialog that holds no rules is one there is nothing
## to test.
##
## ⚠️ **THE CLI IS NOT REPLACED, AND THAT IS DELIBERATE.**
## `scenes/overworld/map_creator.tscn` says of itself: *"THIS IS THE TEST
## SURFACE, NOT THE USER SURFACE... this driver exists so they can be asserted
## headlessly and so a batch of maps stays scriptable"* (`:6-9`). Both press the
## same `MapAuthoring` functions. This is the human path; that one stays the
## testable and batchable path.
##
## ⚠️ **A DIALOG RATHER THAN AN INSPECTOR SECTION**, matching `name_usage_dialog`
## for the same reason: making a NEW map is a project-level action, not a
## property of whatever node happens to be selected. Requiring a selection first
## would be asking for a map before you have one.


## The dialog's own OK button says what it does. `AcceptDialog`'s default "OK"
## reads as "dismiss" next to a results box, which is exactly wrong on the one
## press that writes files.
const CREATE_TEXT := "Create"

var _name: LineEdit
var _pair: OptionButton
var _width: SpinBox
var _height: SpinBox
var _fill: SpinBox
var _fill_auto: CheckBox
var _results: RichTextLabel


func _init() -> void:
	title = "New map"
	min_size = Vector2i(620, 460)
	ok_button_text = CREATE_TEXT
	# ⚠️ The dialog must NOT close on Create. A refusal (name taken, no fill
	# derivable, save failed) is reported into `_results`, and a dialog that
	# vanished would take the reason with it.
	get_ok_button().pressed.connect(_on_create)

	var box := VBoxContainer.new()
	add_child(box)

	var hint := Label.new()
	hint.text = ("Creates scenes/maps/<Name>.tscn + _data.tres, registers "
			+ MapAuthoring.CONSTANT_PREFIX + "<NAME>, and opens it.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	box.add_child(_label("Name  (PascalCase, e.g. XanaduNursery)"))
	_name = LineEdit.new()
	_name.placeholder_text = "XanaduNursery"
	_name.text_submitted.connect(func(_t: String) -> void: _on_create())
	box.add_child(_name)

	# ⚠️ **ONLY PAIRS THAT ALREADY HAVE A BUILT TILESET**, which is what makes
	# this a plain dropdown rather than a typeahead: a pair becomes usable only
	# once some map on it has been BAKED (that is what writes the shared
	# TileSet), so this is ~16 of 60 rather than everything. Said in the hint
	# because a short list with no explanation reads as a bug.
	box.add_child(_label("Tileset pair  (only pairs with a built TileSet — "
			+ "bake a map on a pair to unlock it)"))
	_pair = OptionButton.new()
	box.add_child(_pair)

	var size_row := HBoxContainer.new()
	size_row.add_child(_label("Width"))
	_width = _spin(1, 200, 20)
	size_row.add_child(_width)
	size_row.add_child(_label("Height"))
	_height = _spin(1, 200, 18)
	size_row.add_child(_height)
	box.add_child(size_row)

	# The fill is DERIVED by default — the point of `default_fill_for` is that
	# a map can be made without knowing a single metatile id. The override
	# exists for the pair where nothing sensible can be derived, which reports
	# itself rather than failing silently.
	var fill_row := HBoxContainer.new()
	_fill_auto = CheckBox.new()
	_fill_auto.text = "Derive fill metatile"
	_fill_auto.button_pressed = true
	_fill_auto.toggled.connect(func(on: bool) -> void: _fill.editable = not on)
	fill_row.add_child(_fill_auto)
	_fill = _spin(0, 4095, 0)
	_fill.editable = false
	fill_row.add_child(_fill)
	box.add_child(fill_row)

	_results = RichTextLabel.new()
	_results.bbcode_enabled = true
	_results.selection_enabled = true
	_results.custom_minimum_size = Vector2(0, 200)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	return s


## ⚠️ Re-reads the pair list on every open. `usable_pairs()` grows whenever a
## map is baked, and a list cached at plugin start would tell an author a pair
## they just unlocked does not exist.
func popup_fresh() -> void:
	_pair.clear()
	for p in MapAuthoring.usable_pairs():
		_pair.add_item(p)
	if _pair.item_count == 0:
		_say("[color=#ddaa66]No tileset pair has a built TileSet yet — bake a "
				+ "map first (scenes/overworld/map_baker.tscn).[/color]")
	else:
		_results.text = ""
	_name.grab_focus()
	_name.select_all()
	popup_centered()


func _say(bbcode: String) -> void:
	_results.text = bbcode


func _on_create() -> void:
	var map_name := _name.text.strip_edges()
	if map_name == "":
		_say("[color=#dd8888]Name a map first.[/color]")
		return
	if _pair.selected < 0:
		_say("[color=#dd8888]Pick a tileset pair.[/color]")
		return
	var pair := _pair.get_item_text(_pair.selected)

	# Refused rather than overwritten — the same call `map_creator.gd` makes,
	# and the reason is that the artifact may already carry hand-painted work.
	if MapAuthoring.map_exists(map_name):
		_say("[color=#dd8888]%s already exists — refusing to overwrite.[/color]"
				% map_name)
		return

	var fill := int(_fill.value)
	if _fill_auto.button_pressed:
		fill = MapAuthoring.default_fill_for(pair)
		if fill < 0:
			_say("[color=#dd8888]No fill metatile could be derived for %s — "
					% pair + "untick and set one.[/color]")
			return

	var md := MapAuthoring.create_map(map_name, int(_width.value),
			int(_height.value), pair, fill)
	var err := MapAuthoring.save_map(md)
	if err != OK:
		_say("[color=#dd8888]Save failed — %s[/color]" % error_string(err))
		return

	# ⚠️ Reported, not fatal. A map whose constant did not register still EXISTS
	# and is still paintable; what it cannot yet do is be named by a connection.
	# `connect_maps` refuses loudly in that state ("has no MAP_* constant"), so
	# surfacing it here is what stops that becoming a confusing later refusal.
	var reg := MapAuthoring.register_constant(map_name)
	var konst := MapAuthoring.constant_for(map_name)
	var lines := "[b][color=#88dd88]Created %s[/color][/b]  %d×%d on %s (fill %d)\n" \
			% [map_name, int(_width.value), int(_height.value), pair, fill]
	lines += "constant %s%s\n" % [konst,
			"" if reg == "" else "  [color=#ddaa66]— %s[/color]" % reg]
	lines += "\nNext: paint it, then [b]Sync Painted Tiles[/b], then set "
	lines += "collision/elevation with the Overlay."
	_say(lines)

	# Land in the new map rather than leaving it to be hunted for in the
	# FileSystem dock — the one thing this genuinely adds over the CLI.
	EditorInterface.open_scene_from_path(
			MapAuthoring.OUT_DIR + map_name + ".tscn")
