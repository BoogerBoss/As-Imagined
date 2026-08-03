class_name NamingScreen
extends CanvasLayer

## [M27K K-b] Type a name. Source's `naming_screen.c` is 2650 lines of GBA
## keyboard presentation; this is the same INTERACTION at this project's own
## plain-Panel fidelity, matching the bag and party screens rather than
## inventing a third look.
##
## ⚠️ **TWO SCREENS, AND SOURCE SHOWS THE MENU FIRST.** FRLG does not open a
## keyboard — it offers a list of preset names with **NEW NAME** at the head
## (`gOtherText_NewName`), and only picking that reaches the keyboard. So this
## has two modes and opens in CHOICES. Skipping straight to the keyboard would
## be a different game: nearly every real playthrough takes a preset.
##
## ⚠️ **CAPPED AT 7**, source's own `PLAYER_NAME_LENGTH`. Enforced HERE as well
## as in `PlayerIdentity.sanitize`, deliberately: this stops the player typing
## an 8th character (so the cap is visible), and that one truncates whatever it
## is handed (so a caller bypassing this screen still cannot mint an
## unstorable name). Two different jobs, not a duplicated check.

signal name_chosen(value: String)
signal cancelled()

const MARGIN := 40
const ROWS := 5

## The keyboard pages. Source cycles UPPER -> LOWER -> OTHERS with SELECT;
## reproduced as three pages rather than one flat grid so the shape matches.
const PAGE_UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const PAGE_LOWER := "abcdefghijklmnopqrstuvwxyz"
const PAGE_OTHER := "0123456789 -.,'!?"

enum Mode { CHOICES, KEYBOARD }

var _panel: Panel
var _prompt: Label
var _entry: Label
var _rows_box: VBoxContainer

var _mode: int = Mode.CHOICES
var _choices: PackedStringArray = PackedStringArray()
var _choice_index := 0
var _pages: Array[String] = [PAGE_UPPER, PAGE_LOWER, PAGE_OTHER]
var _page := 0
var _cursor := 0
var _typed := ""
var _prompt_text := ""
var _open := false


var is_open: bool:
	get:
		return _open

var mode: int:
	get:
		return _mode

var typed: String:
	get:
		return _typed

var choice_index: int:
	get:
		return _choice_index


func _init() -> void:
	# Above the field menus and the message box (80), below the yes/no prompt
	# (85) — naming is a screen, not a question asked over one.
	layer = 82


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_left = 20
	_prompt.offset_top = 16
	_prompt.offset_bottom = 56
	_panel.add_child(_prompt)

	_entry = Label.new()
	_entry.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_entry.offset_left = 20
	_entry.offset_top = 60
	_entry.offset_bottom = 100
	_panel.add_child(_entry)

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.offset_left = 24
	_rows_box.offset_top = 108
	_rows_box.offset_right = -24
	_rows_box.offset_bottom = -24
	_panel.add_child(_rows_box)

	visible = false


## Open on the preset list. `choices` should NOT already contain NEW NAME — it
## is prepended here so every caller gets it in the same place.
func open(prompt: String, choices: PackedStringArray) -> void:
	_prompt_text = prompt
	_choices = PackedStringArray([PlayerIdentity.NEW_NAME])
	_choices.append_array(choices)
	_choice_index = 0
	_mode = Mode.CHOICES
	_typed = ""
	_page = 0
	_cursor = 0
	_open = true
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	cancelled.emit()


## ⚠️ CLAMPS in both modes, like every other list in this project's field UI.
func move(delta: int) -> void:
	if not _open:
		return
	if _mode == Mode.CHOICES:
		_choice_index = clampi(_choice_index + delta, 0, _choices.size() - 1)
	else:
		_cursor = clampi(_cursor + delta, 0, _pages[_page].length() - 1)
	_refresh()


## Cycle the keyboard page. Source binds this to SELECT.
func next_page() -> void:
	if not _open or _mode != Mode.KEYBOARD:
		return
	_page = wrapi(_page + 1, 0, _pages.size())
	_cursor = 0
	_refresh()


## Delete the last character. Source binds this to B while typing, which is
## why B does NOT cancel the whole screen once you are on the keyboard.
func backspace() -> void:
	if not _open or _mode != Mode.KEYBOARD or _typed.is_empty():
		return
	_typed = _typed.substr(0, _typed.length() - 1)
	_refresh()


## Type the highlighted character, or take the highlighted preset.
func confirm() -> void:
	if not _open:
		return
	if _mode == Mode.CHOICES:
		var picked := str(_choices[_choice_index])
		if picked == PlayerIdentity.NEW_NAME:
			_mode = Mode.KEYBOARD
			_refresh()
			return
		_finish(picked)
		return
	# ⚠️ The cap is enforced by REFUSING the 8th character rather than by
	# silently dropping it — the row stays on screen and simply does nothing,
	# which is what tells the player they are full.
	if _typed.length() < PlayerIdentity.NAME_LENGTH:
		_typed += _pages[_page][_cursor]
		_refresh()


## Accept what has been typed. Source's OK key; an empty name is refused
## because a blank player would render every `{PLAYER}` as nothing.
func accept() -> bool:
	if not _open or _mode != Mode.KEYBOARD:
		return false
	if PlayerIdentity.sanitize(_typed).is_empty():
		return false
	_finish(_typed)
	return true


func _finish(value: String) -> void:
	_open = false
	visible = false
	name_chosen.emit(PlayerIdentity.sanitize(value))


func prompt_text() -> String:
	return _prompt_text


## What the entry line reads — the typed name plus source's own underscores for
## the remaining slots, so the cap is visible before you hit it.
func entry_text() -> String:
	if _mode != Mode.KEYBOARD:
		return ""
	return _typed + "_".repeat(PlayerIdentity.NAME_LENGTH - _typed.length())


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _mode == Mode.CHOICES:
		for i in range(_choices.size()):
			out.append(("▶ " if i == _choice_index else "   ") + str(_choices[i]))
		return out
	var page := _pages[_page]
	var per_row := int(ceil(float(page.length()) / float(ROWS)))
	for r in range(ROWS):
		var line := ""
		for c in range(per_row):
			var idx := r * per_row + c
			if idx >= page.length():
				break
			line += ("[%s]" % page[idx]) if idx == _cursor else (" %s " % page[idx])
		if line != "":
			out.append(line)
	return out


func _refresh() -> void:
	if _prompt == null:
		return
	_prompt.text = _prompt_text
	_entry.text = entry_text()
	for c in _rows_box.get_children():
		c.queue_free()
	for t in row_texts():
		var row := Label.new()
		row.text = t
		_rows_box.add_child(row)
