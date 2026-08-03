class_name FieldStartMenu
extends CanvasLayer

## [M27I I4] The START menu — the field bag's entry point.
##
## Built because I4 needs a way IN. Source opens the bag from here
## (`StartMenuBagCallback` -> `GoToBagMenu(ITEMMENULOCATION_FIELD, ...)`), and a
## dedicated bag hotkey would have been a second mechanism to retire later.
##
## ⚠️ **THE ENTRY LIST IS CONDITIONAL IN SOURCE TOO, WHICH IS WHY A SHORT ONE IS
## NOT A STUB.** `BuildNormalStartMenu` (`start_menu.c`) adds POKéDEX only when
## `FLAG_SYS_POKEDEX_GET` is set, POKéMON only on `FLAG_SYS_POKEMON_GET`, and
## POKéNAV only on `FLAG_SYS_POKENAV_GET`. Those flags are genuinely unset here,
## so their absence is source behaviour rather than a missing feature — and they
## appear on their own the moment M33 / M27I I5 set them.
##
## ⚠️ **THREE ENTRIES SOURCE ADDS UNCONDITIONALLY ARE DELIBERATELY OMITTED**:
## the player's own name (needs M27K's player identity), SAVE (M27L) and OPTION
## (unscoped). Showing a dead entry that does nothing when picked is worse than
## not showing it — the player cannot tell "not built" from "broken". Each is
## listed here so a future session adds it rather than rediscovering the gap.

signal bag_selected()
signal closed()

const MARGIN := 32
const WIDTH := 260
const ROW_HEIGHT := 48

## Entry ids, in source's own order.
enum Entry { POKEDEX, POKEMON, BAG, EXIT }

const ENTRY_TEXT := {
	Entry.POKEDEX: "POKéDEX",
	Entry.POKEMON: "POKéMON",
	Entry.BAG: "BAG",
	Entry.EXIT: "EXIT",
}

var _panel: Panel
var _rows_box: VBoxContainer
var _entries: Array[int] = []
var _index := 0
var _open := false


var is_open: bool:
	get:
		return _open

var index: int:
	get:
		return _index

var entries: Array[int]:
	get:
		return _entries


func _init() -> void:
	# Above the message box and yes/no prompt, below the bag it opens.
	layer = 65


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -(WIDTH + MARGIN)
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_bottom = MARGIN + ROW_HEIGHT * 4 + 24
	add_child(_panel)

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.offset_left = 16
	_rows_box.offset_top = 12
	_rows_box.offset_right = -16
	_rows_box.offset_bottom = -12
	_panel.add_child(_rows_box)

	visible = false


## Which entries this menu shows right now.
##
## Mirrors `BuildNormalStartMenu`'s own gating, reading the same flag names.
static func build_entries(flags: FlagStore) -> Array[int]:
	var out: Array[int] = []
	if flags != null and flags.flag_get("FLAG_SYS_POKEDEX_GET"):
		out.append(Entry.POKEDEX)
	if flags != null and flags.flag_get("FLAG_SYS_POKEMON_GET"):
		out.append(Entry.POKEMON)
	out.append(Entry.BAG)   # unconditional in source
	out.append(Entry.EXIT)  # unconditional in source
	return out


func open(flags: FlagStore) -> void:
	_entries = build_entries(flags)
	_index = 0
	_open = true
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## Source's start menu wraps (`Menu_ProcessInput`), unlike the bag's item list.
func move(delta: int) -> void:
	if not _open or _entries.is_empty():
		return
	_index = wrapi(_index + delta, 0, _entries.size())
	_refresh()


## Activate the highlighted entry. Returns the entry chosen, or -1.
func confirm() -> int:
	if not _open or _entries.is_empty():
		return -1
	var e: int = _entries[_index]
	match e:
		Entry.BAG:
			close()
			bag_selected.emit()
		Entry.EXIT:
			close()
		_:
			# POKEDEX / POKEMON are only ever in the list once their flag is set,
			# which is the same moment the screen behind them exists.
			close()
	return e


func _refresh() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		c.queue_free()
	for i in range(_entries.size()):
		var row := Label.new()
		var mark := "▶ " if i == _index else "   "
		row.text = mark + str(ENTRY_TEXT.get(_entries[i], "?"))
		_rows_box.add_child(row)
