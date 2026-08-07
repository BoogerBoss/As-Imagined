class_name MultichoiceGrid
extends CanvasLayer

## [M27G] `multichoicegrid` — a grid of named options, answering into VAR_RESULT.
##
## The first GENERAL list-choice widget in this project. `YesNoBox` is a fixed
## two-row special case and every other picker (Bag, Party, naming) is a bespoke
## screen; this one takes an arbitrary list and a row width, which is what the
## opcode actually means.
##
## ⚠️ **IT DRIVES ITS OWN INPUT, AND THAT IS WHAT MAKES IT WORK AT ALL.** It is
## opened by a `native` handler, so while it is up the VM sits on `WAIT_NATIVE`
## and `ScriptDriver.drive()` is in its `WAIT_NATIVE` branch — nothing there
## advances a widget. `YesNoBox` cannot self-drive because the VM's own
## WAIT_YES_NO branch owns its keys and two drivers would fight; this one has no
## VM branch, so owning its keys is the whole design rather than a second path.
## `NamingScreen` is the existing precedent for a widget that owns input.
##
## ⚠️ **B ANSWERS 127, NOT "the last entry".** `MULTI_B_PRESSED` is a real,
## distinct outcome that scripts branch on separately — the Viridian blackboard
## has `case 5` (EXIT) and `case 127` pointing at the same label, which only
## reads as redundant if you assume they are the same event. They are not:
## `ignore_b` can make B do nothing at all.

signal chosen(index: int)

## Source's own sentinel (`include/constants/script_menu.h:8`).
const B_PRESSED := 127

## ⚠️ The same 5-frame debounce `YesNoBox` uses, for the same reason: this
## widget is opened by a press of A, and without it that same press is still
## down on the frame the menu appears and instantly confirms the first entry.
const INPUT_DELAY := 5.0 / 60.0

var is_open: bool = false
var index: int = 0

var _entries: PackedStringArray = PackedStringArray()
var _per_row: int = 1
var _ignore_b: bool = false
var _elapsed: float = 0.0
var _panel: PanelContainer
var _grid: GridContainer

var accepts_input: bool:
	get:
		return is_open and _elapsed >= INPUT_DELAY


func _init() -> void:
	# Above the message box (80) and level with YesNoBox (85) — it draws OVER
	# the question it is answering, exactly as the yes/no does.
	layer = 85
	visible = false


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 24)
	add_child(_panel)
	_grid = GridContainer.new()
	_panel.add_child(_grid)


func open(entries: PackedStringArray, per_row: int = 1, ignore_b: bool = false) -> void:
	if entries.is_empty():
		return
	_entries = entries
	_per_row = maxi(1, per_row)
	_ignore_b = ignore_b
	index = 0
	_elapsed = 0.0
	is_open = true
	visible = true
	_rebuild()


func close() -> void:
	is_open = false
	visible = false


func _rebuild() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	_grid.columns = _per_row
	for i in range(_entries.size()):
		var l := Label.new()
		# ⚠️ The cursor is a TEXT PREFIX, not a sprite. Source does the same for
		# list rows (`gText_SelectorArrow2` printed at x=0), and this project
		# already follows that convention in the Bag and Party screens.
		l.text = ("▶" if i == index else "  ") + str(_entries[i])
		_grid.add_child(l)


func _process(delta: float) -> void:
	if not is_open:
		return
	_elapsed += delta
	if not accepts_input:
		return
	# ⚠️ Movement is GRID-SHAPED: left/right step one, up/down step a whole row.
	# Treating it as a flat list works for `per_row == 1` and is wrong for every
	# real call site — the one in the corridor is 3 wide.
	if Input.is_action_just_pressed("ui_right"):
		_move(1)
	elif Input.is_action_just_pressed("ui_left"):
		_move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_move(_per_row)
	elif Input.is_action_just_pressed("ui_up"):
		_move(-_per_row)
	elif Input.is_action_just_pressed("ui_accept"):
		var picked := index
		close()
		chosen.emit(picked)
	elif Input.is_action_just_pressed("ui_cancel") and not _ignore_b:
		close()
		chosen.emit(B_PRESSED)


## ⚠️ CLAMPS rather than wrapping. Source's menus use
## `Menu_ProcessInputNoWrap*`, the same call `YesNoBox` already documents.
func _move(step: int) -> void:
	index = clampi(index + step, 0, _entries.size() - 1)
	_rebuild()
