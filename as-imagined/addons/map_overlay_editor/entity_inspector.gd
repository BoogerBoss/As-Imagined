@tool
extends EditorInspectorPlugin

## [M27Q Q3] Shows a placed entity's script and dialogue in the Inspector.
##
## ⚠️ **THIS FILE DELIBERATELY CONTAINS NO RULES.** Every decision — which
## labels chain into which, loop protection, truncation, where the text comes
## from — lives in `ScriptPreview`, which a headless suite drives directly
## (`m27a_step_resolver_test` section AT, 15 assertions). This side only turns
## a Dictionary into Controls. That split is the plugin's own standing rule,
## written in `plugin.gd`: this addon is the project's one surface with no
## automated coverage and has already shipped three defects, so anything with a
## rule in it belongs on the other side of the boundary.
##
## ⚠️ **NO DOCK, DELIBERATELY.** `plugin._select_entity_at` already resolves a
## 2D-viewport click into a selected node and `MapOverlay.next_in_stack`
## already cycles stacked entities, so the Inspector follows for free. A dock
## would re-solve selection sync, multi-select, deselect and freed-node guards
## — all of it code that does not exist, on the surface least able to catch a
## mistake in it.
##
## Scoped to every entity that can carry a script (Rob's call, 2026-08-08):
## measured region-wide, that is **2,386 placements — 1,029 NPCs, 519 signs,
## 432 trainers, 228 triggers, 178 item balls**. Signs are 22% of the total and
## are almost pure dialogue, so excluding them would have hidden a large share
## of the game's readable text. Warps carry no script and get nothing.

const _MONO_SIZE := 11


func _can_handle(object: Object) -> bool:
	return object is OverworldEntity or object is TrainerData


## Drawn at the TOP, above the Node2D/CanvasItem sections rather than below
## them — an entity's script is the thing you opened it to read, and burying it
## under Transform/Visibility would make the panel technically present and
## practically unused.
func _parse_begin(object: Object) -> void:
	var td := object as TrainerData
	if td != null:
		_parse_trainer(td)
		return
	var e := object as OverworldEntity
	if e == null or e.script_label == "":
		return
	var preview: Dictionary = ScriptPreview.build(e.script_label)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	if not preview["found"]:
		# ⚠️ Says WHICH label failed. The configuration warning added in Q2
		# already flags this in the scene tree, but the panel is where you are
		# looking when you notice, and "no script" with no name attached is
		# indistinguishable from "this entity has no script", which is a real
		# and common state.
		var miss := Label.new()
		miss.text = "⚠ '%s' resolves to no script." % e.script_label
		miss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		miss.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		root.add_child(miss)
		add_custom_control(root)
		return

	# --- dialogue first. It is the reason this panel exists: measured across
	# the 1,738 labels real placements reference, the median entity has ONE
	# dialogue entry and eight lines of ops, so putting the ops first would
	# push the useful half below the fold on a typical selection.
	var dialogue: Array = preview["dialogue"]
	if not dialogue.is_empty():
		root.add_child(_heading("Dialogue"))
		for d in dialogue:
			var pages: PackedStringArray = d["pages"]
			if pages.is_empty():
				# A message op naming a label the text corpus does not define.
				# Worth showing rather than skipping — it is exactly what
				# `EventRegistry.verify_text` catches at boot, surfaced early.
				root.add_child(_dim("%s — no text found" % d["label"]))
				continue
			for p in pages:
				root.add_child(_page(p))

	# --- then the raw op listing. Raw, not pretty-printed (Rob's call): a
	# friendlier rendering would be a second place that has to understand
	# opcode semantics, and `ScriptVM`'s set grows by stages, so it would go
	# stale while still reading confidently.
	root.add_child(_heading("Script — %s%s" % [e.script_label,
			"  (authored)" if preview["authored"] else ""]))
	var listing := TextEdit.new()
	listing.text = "\n".join(preview["lines"])
	listing.editable = false
	listing.custom_minimum_size = Vector2(0, 160)
	listing.add_theme_font_size_override("font_size", _MONO_SIZE)
	listing.scroll_fit_content_height = false
	root.add_child(listing)

	if preview["truncated"]:
		root.add_child(_dim("… truncated (depth or length cap)"))

	# ⚠️ AUTHORED ONLY, and that is a scope decision rather than an oversight.
	# An authored label opens in Godot's own script editor; an imported one
	# lives in `field_script_source/**/*.inc`, which the editor has no viewer
	# for, so the button would have to reveal-in-filesystem or shell out. Left
	# for a later pass rather than half-built now.
	if preview["authored"]:
		var jump := Button.new()
		jump.text = "Open authored script"
		jump.pressed.connect(_open_authored.bind(e.script_label))
		root.add_child(jump)

	add_custom_control(root)


## Opens the `scripts/events/` file that registers `label`.
##
## ⚠️ Found by SEARCHING the authored sources for the label rather than by
## deriving a filename from it: the label is a content string
## (`PalletTown_Authored_SeaBreeze`) and the file is named after its map
## (`pallet_town_events.gd`), so no transform relates them — and guessing one
## is the same mistake `[M27D D1]` paid for when it derived a pic-table name
## from an info symbol and lost 48 of 387 ids.
func _open_authored(label: String) -> void:
	var dir := DirAccess.open("res://scripts/events")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := "res://scripts/events/" + f
		var src := FileAccess.open(path, FileAccess.READ)
		if src == null:
			continue
		var found := src.get_as_text().contains('"%s"' % label)
		src.close()
		if found:
			var editor := Engine.get_singleton("EditorInterface")
			if editor != null:
				editor.edit_script(load(path))
			return
	push_warning("EntityInspector: no file under scripts/events/ names '%s'." % label)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
	return l


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return l


## One dialogue page, shown with its own line breaks intact — `\n` inside a
## page is a real line break the player sees, not formatting to collapse.
func _page(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## [M27Q Q3] The read-only roster, shown when the Q2 button opens a trainer.
##
## ⚠️ **READ-ONLY ON PURPOSE — Rob's call, 2026-08-08.** `species_dex` and
## `move_ids` stay raw ints below, edited by number. The alternative was real
## name dropdowns, but Godot's enum control is a plain OptionButton with no
## typeahead and those lists are **386 species and 717 implemented moves**; a
## 717-entry scroll popup is worse to use than typing the number. This gets the
## readability — which was the actual complaint — without the widget that makes
## it worse. A filtered picker is the deferred item that would replace both.
##
## The formatting itself is `TrainerData.describe_party()`, driven directly by
## `m24c_test` section I. This function only prints what it returns.
func _parse_trainer(td: TrainerData) -> void:
	var lines := td.describe_party()
	if lines.is_empty():
		return
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	root.add_child(_heading("Party — %d" % lines.size()))
	for l in lines:
		var row := Label.new()
		row.text = l
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(row)
	root.add_child(_dim("Read-only. Edit via the fields below."))
	add_custom_control(root)
