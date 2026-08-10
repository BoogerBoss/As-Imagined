class_name FieldShopScreen
extends CanvasLayer

## [M27I I6c] The Poké Mart.
##
## ⚠️ **PLAIN GODOT CONTROLS, NO REFERENCE ART — Rob's call, 2026-08-09, and it
## OVERRIDES a standing rule.** CLAUDE.md's "pull real reference assets first"
## exists to forbid exactly this shape, citing the three sessions M25h spent
## retrofitting authenticity. Recorded as a decision at
## `docs/m27i_pokemart_scope.md` §9 so a later session does not read a plain
## `Panel` shop as an unfinished job. The chrome pass belongs with M26E's own
## screen work, and is cheap when it comes: source's sell path IS the bag, and
## `FieldBagScreen` already carries real art to copy conventions from.
##
## ⚠️ **EVERY RULE LIVES IN `Shop`, NOT HERE.** Affordability, both quantity
## caps, the sold-out refusal and the Premier Ball bonus are static functions a
## headless suite drives directly. This file asks questions and draws answers.

signal closed()

## [M27I I6d] Raised when the clerk's SELL action is chosen.
##
## ⚠️ **SELL DOES NOT BUILD A LIST — IT OPENS THE BAG.**
## `Task_HandleShopMenuSell` hands off to `CB2_GoToSellMenu`, which is one line:
## `GoToBagMenu(ITEMMENULOCATION_SHOP, POCKETS_COUNT, CB2_ExitSellMenu)`
## (`item_menu.c:622-624`). So selling is the ordinary bag across ALL pockets in
## a shop CONTEXT, and `FieldBagScreen` is already that screen. This screen
## therefore asks for it rather than growing a second list widget.
signal sell_requested()

const MARGIN := 40
const ROW_HEIGHT := 22

## Clerk actions. Source's own default for a normal mart
## (`sShopMenuActions_BuySellQuit`, `shop.c:168`).
const ACTIONS := ["BUY", "SELL", "QUIT"]

var _panel: Panel
var _title: Label
var _rows_box: VBoxContainer
var _footer: Label

var _stock: Array[int] = []
var _mode := "menu"          ## "menu" | "buy" | "count"
var _action_index := 0
var _row_index := 0
var _count := 1
var _open := false

var _bag: Bag = null
var _wallet: Wallet = null

var is_open: bool:
	get: return _open

var mode: String:
	get: return _mode

var row_index: int:
	get: return _row_index

var count: int:
	get: return _count


func _ready() -> void:
	layer = 72   # above the field, below the message box (80) that reports a sale
	_build()
	hide_all()


func _build() -> void:
	_panel = Panel.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	var col := VBoxContainer.new()
	col.anchor_right = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = 12
	col.offset_top = 8
	col.offset_right = -12
	col.offset_bottom = -8
	_panel.add_child(col)

	_title = Label.new()
	col.add_child(_title)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_rows_box)
	_footer = Label.new()
	col.add_child(_footer)


## Open on the clerk menu with this stock.
func open(stock: Array[int], bag: Bag = null, wallet: Wallet = null) -> void:
	_stock = stock
	_bag = bag if bag != null else OverworldSession.bag
	_wallet = wallet if wallet != null else OverworldSession.wallet
	_mode = "menu"
	_action_index = 0
	_row_index = 0
	_count = 1
	_open = true
	_panel.show()
	_refresh()


func hide_all() -> void:
	_open = false
	if _panel != null:
		_panel.hide()


## ⚠️ Leaving BUY returns to the clerk rather than closing the shop, matching
## `Task_GoToBuyOrSellMenu`'s own "Anything else I can help with?"
## (`shop.c:485-487`). Only QUIT ends it — and ending it is what releases the
## script, which is parked on WAIT_NATIVE until this fires.
func move(delta: int) -> void:
	if not _open:
		return
	match _mode:
		"menu":
			_action_index = clampi(_action_index + delta, 0, ACTIONS.size() - 1)
		"buy":
			_row_index = clampi(_row_index + delta, 0, maxi(0, _stock.size() - 1))
		"count":
			_count = clampi(_count + delta, 1, maxi(1, _max_for_row()))
	_refresh()


func confirm() -> void:
	if not _open:
		return
	match _mode:
		"menu":
			match ACTIONS[_action_index]:
				"BUY":
					if not _stock.is_empty():
						_mode = "buy"
				"SELL":
					# ⚠️ I6d. Deliberately inert rather than absent: source's
					# normal mart really does offer three actions, and hiding
					# one would be a different menu shape from the reference.
					_footer.text = "Selling is not available yet."
				"QUIT":
					hide_all()
					closed.emit()
					return
		"buy":
			_count = 1
			if _max_for_row() > 0:
				_mode = "count"
		"count":
			_buy()
	_refresh()


## B / cancel. Backs out one level; from the clerk menu it quits.
func cancel() -> void:
	if not _open:
		return
	match _mode:
		"count": _mode = "buy"
		"buy": _mode = "menu"
		_:
			hide_all()
			closed.emit()
			return
	_refresh()


## [M27I I6d] Sell what the bag context chose. Returns the message to show.
##
## ⚠️ A stack of ONE skips the quantity picker entirely (`tQuantity == 1`,
## `item_menu.c:2189`) — the caller decides that, but the rule lives here so the
## count is never invented by a screen.
func sell_from_bag(item_id: int, count: int) -> String:
	var res := Shop.sell(_bag, _wallet, item_id, count)
	var name := str(PokemonRegistry.get_item_identity(item_id).get("name", "?"))
	if not bool(res["ok"]):
		# Source's own refusal string is confusingly named gText_CantBuyKeyItem
		# and IS the sell refusal.
		return "%s can't be sold here." % name
	_refresh()
	return "Sold %s x%d for $%d." % [name, count, int(res["earned"])]


func _current_item() -> int:
	if _row_index < 0 or _row_index >= _stock.size():
		return 0
	return _stock[_row_index]


func _max_for_row() -> int:
	var id := _current_item()
	if id <= 0:
		return 0
	var identity := PokemonRegistry.get_item_identity(id)
	# A key item already held is SOLD OUT — shown, not hidden (shop.c:660).
	if Shop.is_key_item(id) and _bag != null and _bag.count_of(id) > 0:
		return 0
	return Shop.max_affordable(int(identity.get("price", 0)),
			_wallet.money if _wallet != null else 0, id, _bag)


func _buy() -> void:
	var res := Shop.purchase(_bag, _wallet, _current_item(), _count)
	if bool(res["ok"]):
		var name := str(PokemonRegistry.get_item_identity(
				_current_item()).get("name", "?"))
		_footer.text = "%s x%d — %d paid." % [name, _count, int(res["spent"])]
		if int(res["premier"]) > 0:
			_footer.text += "  Free Premier Ball x%d!" % int(res["premier"])
	else:
		_footer.text = str(res["reason"]).capitalize() + "."
	_mode = "buy"


func _refresh() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	var money: int = _wallet.money if _wallet != null else 0
	match _mode:
		"menu":
			_title.text = "POKéMART        $%d" % money
			for i in range(ACTIONS.size()):
				_add_row("%s %s" % ["▶" if i == _action_index else " ", ACTIONS[i]])
		"buy", "count":
			_title.text = "BUY             $%d" % money
			for i in range(_stock.size()):
				var id: int = _stock[i]
				var identity := PokemonRegistry.get_item_identity(id)
				var price := int(identity.get("price", 0))
				var sold_out := Shop.is_key_item(id) \
						and _bag != null and _bag.count_of(id) > 0
				# ⚠️ SOLD OUT is a PRICE-COLUMN replacement, not a hidden row —
				# the same "show it and say why" discipline the party screen
				# already uses for an ineligible Pokemon.
				_add_row("%s %-16s %s" % [
						"▶" if i == _row_index else " ",
						str(identity.get("name", "?")),
						"SOLD OUT" if sold_out else "$%d" % price])
			if _mode == "count":
				var id2 := _current_item()
				var p := int(PokemonRegistry.get_item_identity(id2).get("price", 0))
				_add_row("")
				_add_row("   x%d        $%d" % [_count, p * _count])
	_footer.visible = _footer.text != ""


func _add_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.y = ROW_HEIGHT
	_rows_box.add_child(l)
