class_name IngameTradeRegistry
extends RefCounted

## [M27G G3a] `data/ingame_trades.json` — `sIngameTrades[]`
## (`src/data/trade.h:969-1215`), with species/item names already resolved
## to this project's own numeric IDs by `scripts/gen_ingame_trades.py`.
##
## An ARRAY, not a name-keyed dict, matching source's own `sIngameTrades[idx]`
## indexing — `VAR_0x8005` holds this same row index at runtime (see
## `ScriptVM._INGAME_TRADE_IDS`'s own doc comment), so `entry(index)` is the
## one real lookup shape this table needs.

const TABLE_PATH := "res://data/ingame_trades.json"

static var _table: Array = []


static func _load() -> Array:
	if not _table.is_empty():
		return _table
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return _table
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_ARRAY:
		_table = parsed
	return _table


## The row at this index, or `{}` if the index is out of range. Out-of-range
## degrades safely rather than erroring — an unresolved `INGAME_TRADE_*`
## constant upstream (see `ScriptVM._INGAME_TRADE_IDS`) is the only way this
## could happen in practice, and it is already fixed at that source.
static func entry(index: int) -> Dictionary:
	var t := _load()
	if index < 0 or index >= t.size():
		return {}
	return t[index]


## Every known row, in index order — for tests and completeness checks.
static func all() -> Array:
	return _load()
