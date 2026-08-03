class_name NamingScreen
extends CanvasLayer

## [M27K K-b] Type a name. Source's `naming_screen.c` is 2650 lines of GBA
## keyboard presentation; this is the same INTERACTION at this project's own
## plain-Panel fidelity, matching the bag and party screens rather than
## inventing a third look.
##
## ⚠️ **TWO SCREENS, AND SOURCE SHOWS THE MENU FIRST — FOR *PLAYER* NAMES.**
## FRLG does not open a keyboard for those; it offers a list of preset names with
## **NEW NAME** at the head (`gOtherText_NewName`), and only picking that reaches
## the keyboard. So `open()` has two modes and starts in CHOICES. Skipping
## straight to the keyboard would be a different game: nearly every real
## playthrough takes a preset.
##
## ⚠️ **[M27K K-c] NICKNAMES ARE THE OPPOSITE, AND THAT IS SOURCE TOO.** There is
## no preset list anywhere for a Pokémon nickname — `sMonNamingScreenTemplate`
## (`naming_screen.c:2172`) is a plain keyboard, used by both
## `NAMING_SCREEN_NICKNAME` and `NAMING_SCREEN_CAUGHT_MON`, while only the
## PLAYER/RIVAL templates get the preset treatment. Hence `open_keyboard()`: a
## second entry point rather than a flag on the first, because the two really
## are different screens in source and collapsing them would make one of the two
## wrong.
##
## ⚠️ **CAPPED AT `PlayerIdentity.NAME_LENGTH`, WHICH IS 12 AND DELIBERATELY NOT
## SOURCE'S 7** — see that class's own header for why. Read the constant here
## rather than repeating the number: the 7 -> 12 change caught a hardcoded `7`
## in the suite, and this file would have been the next one.
##
## Enforced HERE as well as in `PlayerIdentity.sanitize`, deliberately: this
## refuses the keypress past the cap (so the limit is visible), and that one
## truncates whatever it is handed (so a caller bypassing this screen still
## cannot mint an unstorable name). Two different jobs, not a duplicated check.

signal name_chosen(value: String)
signal cancelled()

const MARGIN := 40
const ROWS := 5

## The keyboard pages. Source cycles UPPER -> LOWER -> OTHERS with SELECT;
## reproduced as three pages rather than one flat grid so the shape matches.
const PAGE_UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const PAGE_LOWER := "abcdefghijklmnopqrstuvwxyz"
const PAGE_OTHER := "0123456789 -.,'!?"

## [M27K K-c] ⚠️ **THE OK KEY IS A REAL CELL ON THE GRID, AND IT HAD TO BECOME
## ONE.** K-b left accepting to a separate `ui_text_submit` binding, and a probe
## of the actual InputMap found that **`ui_accept` and `ui_text_submit` are BOTH
## bound to Enter** by Godot's defaults (this project declares no `[input]`
## section, so those defaults are what ship). `_drive_naming` tests `ui_accept`
## first in an elif chain, so Enter always typed a character and a typed name
## could never be submitted at all — the keyboard was unreachable from the
## keyboard. K-b's live drive missed it because the driver called `accept()`
## directly rather than pressing keys.
##
## The fix is source's own design rather than a fourth binding: `naming_screen.c`
## puts an **OK key on the grid** that you move to and press A on. So does this —
## which removes the collision instead of working around it, and means the screen
## needs exactly the same four actions every other field screen uses.
const OK_LABEL := "OK"

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

## [M27K K-c] Whether OK on an EMPTY entry is accepted. See `accept()` — the two
## callers genuinely disagree, and source is the reason.
var _allow_empty := false


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
	_allow_empty = false
	_open = true
	visible = true
	_refresh()


## [M27K K-c] Open straight onto the keyboard, with no preset list — source's
## `sMonNamingScreenTemplate`, used for nicknames and caught mons.
##
## ⚠️ **AND IT ACCEPTS AN EMPTY ENTRY, WHICH `open()` REFUSES.** Not an
## inconsistency: `SaveInputText` (`naming_screen.c:1921`) copies the typed
## buffer into the destination **only if some character is neither space nor
## EOS**, so pressing OK having typed nothing leaves the destination holding
## whatever it already held. For a nickname that is the species name, which is
## exactly how "no, I don't want to rename it" is expressed once the keyboard is
## already open. For a player name the destination starts blank, so the same
## behaviour would mint an unnamed player — which is why `open()` refuses
## instead. The caller decides by which entry point it uses.
func open_keyboard(prompt: String) -> void:
	_prompt_text = prompt
	_choices = PackedStringArray()
	_choice_index = 0
	_mode = Mode.KEYBOARD
	_typed = ""
	_page = 0
	_cursor = 0
	_allow_empty = true
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
##
## The keyboard's upper bound is `length()`, not `length() - 1`: the extra index
## is the OK key, which is a cell you move onto like any other.
func move(delta: int) -> void:
	if not _open:
		return
	if _mode == Mode.CHOICES:
		_choice_index = clampi(_choice_index + delta, 0, _choices.size() - 1)
	else:
		_cursor = clampi(_cursor + delta, 0, _pages[_page].length())
	_refresh()


## True when the cursor is on the OK key rather than on a character.
func on_ok_key() -> bool:
	return _mode == Mode.KEYBOARD and _cursor == _pages[_page].length()


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
	# [M27K K-c] OK is a cell on the grid, so pressing A on it accepts — see
	# OK_LABEL for why this is a grid key and not its own input binding.
	if on_ok_key():
		accept()
		return
	# ⚠️ The cap is enforced by REFUSING the keypress past it rather than by
	# silently dropping the character — the row stays on screen and simply does
	# nothing, which is what tells the player they are full.
	if _typed.length() < PlayerIdentity.NAME_LENGTH:
		_typed += _pages[_page][_cursor]
		_refresh()


## Accept what has been typed. Source's OK key.
##
## ⚠️ **WHETHER AN EMPTY ENTRY IS ACCEPTED DEPENDS ON WHICH `open*` WAS USED**,
## and both halves are source — see `open_keyboard`'s note on `SaveInputText`.
## A player name refuses (a blank player renders every `{PLAYER}` as nothing); a
## nickname accepts and emits "", which the caller reads as "keep what you had".
func accept() -> bool:
	if not _open or _mode != Mode.KEYBOARD:
		return false
	if PlayerIdentity.sanitize(_typed).is_empty() and not _allow_empty:
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
	# [M27K K-c] Its own row, below the characters — source puts OK off to the
	# side of the grid, and a row of its own is this layout's equivalent.
	out.append(("[%s]" % OK_LABEL) if on_ok_key() else (" %s " % OK_LABEL))
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
