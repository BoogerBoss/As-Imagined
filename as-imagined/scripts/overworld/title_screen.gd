class_name TitleScreen
extends CanvasLayer

## [M27L L3] The main menu: pick a slot, then CONTINUE or NEW GAME.
##
## ⚠️ **SOURCE HAS ONE SAVE AND NO SLOT CONCEPT AT ALL.** `main_menu.c` knows
## `HAS_SAVED_GAME` / `HAS_NO_SAVED_GAME` and offers CONTINUE / NEW GAME /
## OPTION against a single file. Three slots is this project's own design, so
## this screen INVERTS source's shape: the slot is chosen first, and what the
## chosen slot already holds decides whether the action is CONTINUE or NEW GAME.
## Said plainly so a later session does not go looking for a slot picker in
## source and conclude it was missed.
##
## What IS ported is the CONTINUE card — source's own four fields, in source's
## own order: PLAYER / TIME / POKéDEX / BADGES (`main_menu.c:274-277`), with TIME
## formatted `H:MM` the way `MainMenu_FormatSavegameTime` prints it.
##
## ⚠️ **THE POKéDEX ROW IS A STUB, AND SOURCE WOULD OMIT IT INSTEAD.** Rob's call
## (2026-08-03) was to show a stubbed row rather than fabricate a count. Worth
## recording alongside it: `MainMenu_FormatSavegamePokedex` (`main_menu.c:2193`)
## gates the whole row on `FlagGet(FLAG_SYS_POKEDEX_GET)`, so source simply does
## not draw it before you own a Pokédex — which this project never does, M33
## owning the Pokédex. Both behaviours are one line apart; `SHOW_DEX_ROW` is that
## line, so flipping it needs no rework.
const SHOW_DEX_ROW := true

const MARGIN := 48
const TITLE := "POKéMON — AS IMAGINED"
const NEW_GAME := "NEW GAME"
const CONTINUE := "CONTINUE"

## Emitted with the chosen slot and whether it starts a fresh playthrough.
signal slot_chosen(slot: int, is_new: bool)
signal cancelled()

var _panel: Panel
var _title: Label
var _rows_box: VBoxContainer

var _index := 0
var _open := false
var _summaries: Array = []


var is_open: bool:
	get:
		return _open

var index: int:
	get:
		return _index


func _init() -> void:
	# Above everything — this screen is what the field appears *under*.
	layer = 150


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_left = 24
	_title.offset_top = 20
	_title.offset_bottom = 64
	_panel.add_child(_title)

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.offset_left = 28
	_rows_box.offset_top = 80
	_rows_box.offset_right = -28
	_rows_box.offset_bottom = -24
	_panel.add_child(_rows_box)

	visible = false


## Read every slot from disk. Called on open so the screen always reflects what
## is actually there — a slot deleted or corrupted since last time reads empty.
func open() -> void:
	_summaries = []
	for i in range(SaveManager.SLOT_COUNT):
		_summaries.append(SaveManager.summary(i))
	_index = 0
	_open = true
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	cancelled.emit()


## ⚠️ CLAMPS, like every other list in this project's field UI. Source's start
## menu wraps, but this is not source's screen at all — and a wrap on a
## three-item destructive-ish list makes it easy to overshoot onto a save you did
## not mean to overwrite.
func move(delta: int) -> void:
	if not _open:
		return
	_index = clampi(_index + delta, 0, SaveManager.SLOT_COUNT - 1)
	_refresh()


## Whether the highlighted slot already holds a playthrough.
func slot_has_save(slot: int) -> bool:
	if slot < 0 or slot >= _summaries.size():
		return false
	return not (_summaries[slot] as Dictionary).is_empty()


func confirm() -> void:
	if not _open:
		return
	var slot := _index
	_open = false
	visible = false
	slot_chosen.emit(slot, not slot_has_save(slot))


## The card for one slot, as the lines it should display.
##
## ⚠️ An empty slot is ONE line, not a card with blanks in it — there is no
## player, no time and no badges to report, and four empty fields read as a
## broken save rather than a free slot.
func card_lines(slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	if not slot_has_save(slot):
		out.append(NEW_GAME)
		return out
	var s: Dictionary = _summaries[slot]
	out.append(CONTINUE)
	out.append("PLAYER   %s" % str(s.get("player", "")))
	out.append("TIME     %s" % SaveManager.format_playtime(int(s.get("playtime", 0))))
	if SHOW_DEX_ROW:
		# ⚠️ The count is a STUB and the payload says so; source would omit this
		# row entirely until FLAG_SYS_POKEDEX_GET is set. See SHOW_DEX_ROW.
		out.append("POKéDEX  %d%s" % [int(s.get("dex_seen", 0)),
				"  (not yet tracked)" if bool(s.get("dex_stub", false)) else ""])
	out.append("BADGES   %d" % int(s.get("badges", 0)))
	return out


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(SaveManager.SLOT_COUNT):
		var mark := "▶ " if i == _index else "   "
		out.append("%sSLOT %d" % [mark, i + 1])
		for line in card_lines(i):
			out.append("      %s" % line)
	return out


func _refresh() -> void:
	if _title == null:
		return
	_title.text = TITLE
	for c in _rows_box.get_children():
		c.queue_free()
	for t in row_texts():
		var row := Label.new()
		row.text = t
		_rows_box.add_child(row)


## Take a slot: load it into the session and report where the player should go.
##
## ⚠️ **RETURNS `pending_return`'s OWN SHAPE, and that is the point.** The
## overworld already resumes from a saved position after a battle; CONTINUE is
## the same problem, so it reuses that path rather than growing a second one.
## Returns an empty dictionary for a slot with nothing in it, so a caller cannot
## resume into a playthrough that does not exist.
static func begin_continue(slot: int) -> Dictionary:
	var payload := SaveManager.read(slot)
	if payload.is_empty():
		return {}
	SaveManager.apply(payload)
	return SaveManager.position_of(payload)
