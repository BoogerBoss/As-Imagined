class_name FieldBagScreen
extends CanvasLayer

## [M27I I4] The field Bag — the first screen that shows what you are carrying.
##
## `[M27I I3]` built a real bag: five pockets, source's own capacities, real
## stacking. Nothing has ever displayed it. Brock hands over TM39 and the player
## has no way to look at it.
##
## ⚠️ **DELIBERATELY NOT A REUSE OF `ItemSelectScreen`.** That screen
## (`[M25h-1.4]`) is the BATTLE bag: three hardcoded battle items, one pocket,
## wired to a `BattleScreen` parent it calls back into. Its visual conventions
## are reused here — the real `bag_frame.png`, the header, chrome-stripped rows,
## the "▶" cursor — but its data path is not, and reworking it is **M26E1/E2**'s
## job. Touching it now would risk the battle screen for no gain here.
##
## Source: `GoToBagMenu(ITEMMENULOCATION_FIELD, POCKETS_COUNT, ...)`
## (`item_menu.c:593`) — the field bag opens with ALL pockets, unlike battle's
## restricted set, which is why pocket switching is part of this and was not
## part of that.

signal closed()
## [M27I I5-3] The player chose USE on an item. The bag does NOT apply it — the
## caller opens the party screen as a target picker, matching source's own flow
## (`ItemUseOutOfBattle_Medicine` -> party menu).
signal item_use_requested(item_id: int)

const MARGIN := 40

## Source's own names, `gPocketNamesStringsTable` (`strings.c:204-211`).
const POCKET_NAMES := {
	ItemManager.POCKET_ITEMS: "ITEMS",
	ItemManager.POCKET_POKE_BALLS: "POKé BALLS",
	ItemManager.POCKET_TM_HM: "TMs & HMs",
	ItemManager.POCKET_BERRIES: "BERRIES",
	ItemManager.POCKET_KEY_ITEMS: "KEY ITEMS",
}

## Tab order, matching source's own pocket ordinals rather than a chosen one.
const POCKET_ORDER := [
	ItemManager.POCKET_ITEMS,
	ItemManager.POCKET_POKE_BALLS,
	ItemManager.POCKET_TM_HM,
	ItemManager.POCKET_BERRIES,
	ItemManager.POCKET_KEY_ITEMS,
]

## Shown in place of the item list when a pocket holds nothing. Source prints
## nothing at all and simply shows CANCEL; an empty panel reads as a bug here,
## where there is no bag graphic to fill the space.
const EMPTY_TEXT := "No items."

var _panel: Panel
var _tab_label: Label
var _rows_box: VBoxContainer
var _desc_label: Label

## [M27I I5-3] Which battle usages have a field use at all.
##
## ⚠️ **DERIVED, BECAUSE THE REAL FIELD-USE DATA IS NOT IN THE PIPELINE.** Source
## carries `.fieldUseFunc` per item (`ItemUseOutOfBattle_Medicine` on Potion, and
## NOTHING on X Attack — verified directly), but `items.json` holds only
## description/hold_effect/pocket/price. The derivation is exact for every item
## this project has: medicine has a field use, X items and balls do not.
## **Flagged for a future items-pipeline pass**, not guessed at — the mapping is
## checked against source rather than assumed from the name.
const FIELD_USABLE_BATTLE_USAGES := [
	ItemManager.BATTLE_USE_RESTORE_HP,
	ItemManager.BATTLE_USE_CURE_STATUS,
]

## The action menu, when open. Source builds this per item
## (`OpenContextMenu`) and simply OMITS actions the item does not support —
## which is why an unusable item needs no "you can't use that" text.
var _actions: PackedStringArray = PackedStringArray()
var _action_index := 0
var _actions_open := false

var _bag: Bag = null
var _pocket_index := 0
var _row_index := 0
var _open := false


var is_open: bool:
	get:
		return _open

## Which pocket is showing, as a real pocket id rather than a tab position.
var pocket: int:
	get:
		return int(POCKET_ORDER[_pocket_index])

var row_index: int:
	get:
		return _row_index


func _init() -> void:
	# Above the message box (50) and the yes/no prompt (60), below the fade.
	layer = 70


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	_tab_label = Label.new()
	_tab_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tab_label.offset_left = 20
	_tab_label.offset_top = 16
	_tab_label.offset_bottom = 56
	_panel.add_child(_tab_label)

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.offset_left = 24
	_rows_box.offset_top = 72
	_rows_box.offset_right = -24
	_rows_box.offset_bottom = -120
	_panel.add_child(_rows_box)

	# Source's own bag has a description box along the bottom
	# (`WIN_DESCRIPTION`), and `items.json` genuinely carries descriptions — so
	# this is real data, not a placeholder.
	_desc_label = Label.new()
	_desc_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_desc_label.offset_left = 24
	_desc_label.offset_top = -104
	_desc_label.offset_right = -24
	_desc_label.offset_bottom = -20
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_desc_label)

	visible = false


## Open on a bag. Explicitly injected rather than reaching for
## `OverworldSession.bag`, so a test can hand in a known one.
func open(bag: Bag, start_pocket: int = ItemManager.POCKET_ITEMS) -> void:
	_bag = bag
	_pocket_index = maxi(0, POCKET_ORDER.find(start_pocket))
	_row_index = 0
	_open = true
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## Move between pockets. Source cycles with L/R and wraps; reproduced.
func next_pocket(delta: int) -> void:
	if not _open:
		return
	_pocket_index = wrapi(_pocket_index + delta, 0, POCKET_ORDER.size())
	_row_index = 0
	_refresh()


## Move the cursor within a pocket.
##
## ⚠️ Clamps rather than wraps, unlike the pocket tabs. Source's item list is a
## scrolling `ListMenu`, which does not wrap either — and with the pockets
## wrapping right beside it, a wrapping row list would make a held Down key
## silently cycle forever.
func move_row(delta: int) -> void:
	if not _open:
		return
	var n := _slots().size()
	if n == 0:
		_row_index = 0
		return
	_row_index = clampi(_row_index + delta, 0, n - 1)
	_refresh()


## The slots of the current pocket. One entry per STACK, which is what the bag
## stores — a pocket holding 999+1 of something genuinely has two rows.
func _slots() -> Array:
	if _bag == null:
		return []
	return _bag.slots(pocket)


## What the cursor is on, or -1.
func selected_item_id() -> int:
	var s := _slots()
	if s.is_empty() or _row_index >= s.size():
		return -1
	return int(s[_row_index]["item"])


## The rows as they render, for tests and for the description lookup.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	var s := _slots()
	if s.is_empty():
		out.append(EMPTY_TEXT)
		return out
	for i in range(s.size()):
		var id := int(s[i]["item"])
		var count := int(s[i]["count"])
		var mark := "▶ " if i == _row_index else "   "
		out.append("%s%s%s" % [mark, _item_name(id), _quantity_suffix(id, count)])
	return out


## ⚠️ KEY ITEMS AND TM/HM SHOW NO COUNT, and that is source, not a shortcut.
## `gText_NumberItem_TMBerry` vs `gText_NumberItem_HM` (`strings.c:213-214`) —
## an HM prints no quantity at all, and source suppresses the count for key
## items too, because you can only ever hold one.
func _quantity_suffix(item_id: int, count: int) -> String:
	if pocket == ItemManager.POCKET_KEY_ITEMS:
		return ""
	# `get_item_identity` names TM/HM items "TM39" / "HM05" — the bag shows the
	# item, not the move it teaches — so the name IS the discriminator.
	if _item_name(item_id).begins_with("HM"):
		return ""
	return "  x%d" % count


func _item_name(item_id: int) -> String:
	var identity: Dictionary = PokemonRegistry.get_item_identity(item_id)
	var n := str(identity.get("name", ""))
	return n if n != "" else "ITEM %d" % item_id


func description_text() -> String:
	var id := selected_item_id()
	if id < 0:
		return ""
	var identity: Dictionary = PokemonRegistry.get_item_identity(id)
	# ⚠️ `items.json` carries source's own LITERAL "\n" two-character sequences,
	# not newlines — the reference wraps its description box by hand at fixed
	# GBA widths. Rendering them raw prints a visible backslash-n. Unwrapped to
	# spaces rather than converted to real newlines, because this box is a
	# different width and autowraps on its own.
	return str(identity.get("description", "")).replace("\\n", " ")


## Is the highlighted item usable outside battle?
static func is_field_usable(item_id: int) -> bool:
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return false
	return item.battle_usage in FIELD_USABLE_BATTLE_USAGES


var actions_open: bool:
	get:
		return _actions_open

var action_index: int:
	get:
		return _action_index


## Open the per-item action menu. Returns false when there is nothing to open.
func open_actions() -> bool:
	if not _open or selected_item_id() < 0:
		return false
	_actions = PackedStringArray()
	if is_field_usable(selected_item_id()):
		_actions.append("USE")
	# ⚠️ GIVE and TOSS are source actions deliberately NOT offered: GIVE needs a
	# held-item UI and TOSS needs a quantity prompt, neither of which exists.
	# Omitted rather than shown-and-broken.
	_actions.append("CANCEL")
	_action_index = 0
	_actions_open = true
	_refresh()
	return true


func move_action(delta: int) -> void:
	if not _actions_open or _actions.is_empty():
		return
	_action_index = clampi(_action_index + delta, 0, _actions.size() - 1)
	_refresh()


func action_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(_actions.size()):
		out.append(("▶ " if i == _action_index else "   ") + _actions[i])
	return out


## Activate the highlighted action. Returns the action name.
func confirm_action() -> String:
	if not _actions_open or _actions.is_empty():
		return ""
	var a: String = _actions[_action_index]
	_actions_open = false
	if a == "USE":
		item_use_requested.emit(selected_item_id())
	_refresh()
	return a


func close_actions() -> void:
	_actions_open = false
	_refresh()


func _refresh() -> void:
	if _tab_label == null:
		return
	_tab_label.text = str(POCKET_NAMES.get(pocket, "?"))
	for c in _rows_box.get_children():
		c.queue_free()
	for t in row_texts():
		var row := Label.new()
		row.text = t
		_rows_box.add_child(row)
	if _actions_open:
		_desc_label.text = "  ".join(action_texts())
	else:
		_desc_label.text = description_text()
