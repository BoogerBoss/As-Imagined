@tool
extends AcceptDialog

## [M27Q Q4] "Is this name taken, how often, and where?"
##
## ⚠️ **CONTAINS NO RULES.** Every decision — what counts as a collision, which
## registers are deliberately shared, how a verdict is reached — lives in
## `NameUsage`, driven by `m27a_step_resolver_test` section AU. This is a text
## box and a label. Same split as `entity_inspector.gd`/`ScriptPreview`, for the
## reason `plugin.gd` records: this addon is the project's one surface with no
## automated coverage.
##
## ⚠️ **A DIALOG RATHER THAN A DOCK, AND RATHER THAN AN INSPECTOR SECTION.**
## This is a QUESTION ABOUT THE PROJECT, not a property of whatever happens to
## be selected — asking "is FLAG_X free" should not require first selecting an
## unrelated node. It hangs off the same toolbar as **Save Map Data** because
## that is where this addon's other project-level action already lives.

var _field: LineEdit
var _results: RichTextLabel


func _init() -> void:
	title = "Name usage"
	min_size = Vector2i(560, 380)
	var box := VBoxContainer.new()
	add_child(box)

	var hint := Label.new()
	hint.text = ("A FLAG_*, VAR_*, TRAINER_* or script/text label. "
			+ "Authored names use " + NameUsage.AUTHORED_PREFIX + "<MAP>_<THING>.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	_field = LineEdit.new()
	_field.placeholder_text = "FLAG_AUTHORED_PALLETTOWN_SEA_BREEZE_READ"
	_field.text_submitted.connect(_on_submit)
	box.add_child(_field)

	var row := HBoxContainer.new()
	var check := Button.new()
	check.text = "Check"
	check.pressed.connect(func() -> void: _on_submit(_field.text))
	row.add_child(check)
	var audit := Button.new()
	audit.text = "Audit authored names"
	audit.tooltip_text = ("Check every invented FLAG_/VAR_ name under "
			+ "scripts/events/ against the convention and the corpus.")
	audit.pressed.connect(_on_audit)
	row.add_child(audit)
	box.add_child(row)

	_results = RichTextLabel.new()
	_results.bbcode_enabled = true
	_results.selection_enabled = true
	_results.custom_minimum_size = Vector2(0, 260)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results)


func popup_fresh() -> void:
	_field.grab_focus()
	_field.select_all()
	popup_centered()


## ⚠️ The verdict is colour-coded but ALSO spelled out in words. A red/green
## dot alone would make "shared" — the state that is correct and looks alarming
## — indistinguishable from a real collision at a glance.
func _on_submit(name: String) -> void:
	name = name.strip_edges()
	if name == "":
		return
	var r: Dictionary = NameUsage.lookup(name)
	var verdict := str(r["verdict"])
	var colour := {
		"free": "88dd88", "yours": "88ccff",
		"shared": "ddcc66", "taken": "ff8866",
	}.get(verdict, "cccccc")
	var head := {
		"free": "FREE — no references anywhere.",
		"yours": "YOURS — referenced only by scripts you authored.",
		"shared": ("SHARED REGISTER — reference-defined and deliberately "
				+ "shared. Overlap here is the mechanism, not a collision."),
		"taken": "TAKEN — already in use. Picking it shares state.",
	}.get(verdict, verdict)

	var s := "[b][color=#%s]%s[/color][/b]\n" % [colour, head]
	s += "[color=#999]%d reference(s)" % int(r["count"])
	if bool(r["authored"]):
		s += "  ·  %d from scripts you did not author" % int(r["imported_refs"])
	s += "[/color]\n\n"
	var shown := 0
	for l in (r["locations"] as Array):
		s += "  %s  [color=#888]%s[/color]\n" % [l["where"], l["detail"]]
		shown += 1
		if shown >= 40:
			s += "  [color=#888]… and %d more[/color]\n" \
					% (int(r["count"]) - shown)
			break
	_results.text = s


func _on_audit() -> void:
	var problems: Array = NameUsage.audit_authored()
	if problems.is_empty():
		_results.text = ("[b][color=#88dd88]No problems.[/color][/b]\n"
				+ "[color=#999]Every invented FLAG_/VAR_ name under "
				+ "scripts/events/ uses the convention and is collision-free."
				+ "[/color]")
		return
	var s := "[b][color=#ff8866]%d problem(s)[/color][/b]\n\n" % problems.size()
	for p in problems:
		s += "  [b]%s[/b]  [color=#888]%s[/color]\n     %s\n" \
				% [p["name"], p["file"], p["problem"]]
	_results.text = s
