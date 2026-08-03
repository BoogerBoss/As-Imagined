class_name YesNoBox
extends CanvasLayer

## [M27F Stage 4] The yes/no prompt.
##
## `msgbox X, MSGBOX_YESNO` compiles to `Std_MsgboxYesNo` — `message` /
## `waitmessage` / **`yesnobox 20, 8`** (`data/scripts/std_msgbox.inc`) — so the
## message box shows the question and THIS shows the choice. **425 corpus uses**,
## every one of which was previously hardwired to answer NO by Stage 1's own
## disclosed stopgap: the Pokecentre, every shop, and every "would you like
## to..." in Kanto was dead behind it.
##
## Built in code rather than as a .tscn, matching MessageBox and the fade — it
## has no authored content, only layout.
##
## Source's own window is placed by the opcode's `left, top` arguments (20, 8 for
## the standard case) in GBA tile coordinates. Deliberately NOT ported literally:
## those are tile offsets into a 240x160 screen, and this project's canvas is
## 1024x768 with a completely different message box. Anchored above the message
## box's own top edge instead, which is where 20,8 puts it relative to the same
## box in source.

signal chosen(yes: bool)

const MARGIN := 24
const WIDTH := 180
const ROW_HEIGHT := 44

## ⚠️ **THE INPUT DEBOUNCE, AND IT IS LOAD-BEARING.** Source's
## `Task_HandleYesNoInput` refuses input for its first 5 frames
## (`if (gTasks[taskId].tRight < 5) { tRight++; return; }`, `script_menu.c`).
## Without it the very A press that dismissed the question's last page is still
## down when the box opens and instantly confirms YES — which reads as "the
## prompt does not work, it just says yes", not as a timing bug.
##
## Held as SECONDS, not frames: `[M26G4]` measured frame-tied stepping running
## ~10% slow at 144 Hz and half speed at 30 Hz, and this is a correctness
## window rather than an animation.
const INPUT_DELAY := 5.0 / 60.0

var _panel: Panel
var _rows: Array[Label] = []
var _index := 0
var _open := false
var _elapsed := 0.0


var is_open: bool:
	get:
		return _open

## Which row the cursor is on: 0 = YES, 1 = NO.
var index: int:
	get:
		return _index

## Has the debounce elapsed? Input before this is deliberately ignored.
var accepts_input: bool:
	get:
		return _open and _elapsed >= INPUT_DELAY


func _init() -> void:
	# Above the message box (50) so the prompt sits over the question, but still
	# below the fade (200) and the battle overlay (100).
	layer = 60


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -(WIDTH + MARGIN)
	_panel.offset_right = -MARGIN
	# Sits directly above the message box, which is HEIGHT + MARGIN tall.
	_panel.offset_top = -(MessageBox.HEIGHT + MARGIN + ROW_HEIGHT * 2 + 16)
	_panel.offset_bottom = -(MessageBox.HEIGHT + MARGIN + 8)
	add_child(_panel)

	for i in range(2):
		var row := Label.new()
		row.set_anchors_preset(Control.PRESET_TOP_WIDE)
		row.offset_left = 12
		row.offset_right = -12
		row.offset_top = 8 + i * ROW_HEIGHT
		row.offset_bottom = 8 + (i + 1) * ROW_HEIGHT
		_panel.add_child(row)
		_rows.append(row)

	visible = false
	_refresh()


func _process(delta: float) -> void:
	if _open:
		_elapsed += delta


## Open the prompt.
##
## ⚠️ **THE CURSOR DEFAULTS TO YES.** Source calls `DisplayYesNoMenuDefaultYes`
## (`ScriptMenu_YesNo`, `script_menu.c`), i.e. `initialCursorPos = 0`. Defaulting
## to NO would be the safe-looking choice and is the wrong one — it silently
## changes what a mashed A button does in all 425 call sites.
func open() -> void:
	_index = 0
	_elapsed = 0.0
	_open = true
	visible = true
	_refresh()


## Move the cursor. Source uses `Menu_ProcessInputNoWrap*`, so it does NOT wrap:
## pressing up on YES stays on YES.
func move(delta: int) -> void:
	if not accepts_input:
		return
	_index = clampi(_index + delta, 0, 1)
	_refresh()


## Confirm the highlighted row. Returns the answer.
func confirm() -> bool:
	if not accepts_input:
		return false
	var yes := _index == 0
	_close()
	chosen.emit(yes)
	return yes


## B / Escape. Source maps `MENU_B_PRESSED` onto the same branch as choosing NO
## (`Task_HandleYesNoInput`'s `case MENU_B_PRESSED: case 1:` fallthrough), so
## cancelling is answering NO — not a third outcome.
func cancel() -> void:
	if not accepts_input:
		return
	_close()
	chosen.emit(false)


func _close() -> void:
	_open = false
	visible = false


func _refresh() -> void:
	for i in range(_rows.size()):
		var mark := "▶ " if i == _index else "   "
		_rows[i].text = mark + ("YES" if i == 0 else "NO")
