class_name TextBuffers
extends RefCounted

## [M27I I2] The three script string buffers, and placeholder expansion.
##
## Source keeps exactly three (`sScriptStringVars[] = { gStringVar1,
## gStringVar2, gStringVar3 }`, `scrcmd.c:102`) and every `buffer*` command
## writes one of them. Text then carries `{STR_VAR_n}` markers that are expanded
## AT PRINT TIME by `StringExpandPlaceholders` — not when the text is loaded.
##
## ⚠️ **PRINT TIME IS LOAD-BEARING.** A script buffers, then prints; buffering
## again before the next print must change what the next print shows. Expanding
## when a `message` op is executed rather than when its page is shown would
## freeze the first value and quietly break every script that reuses a slot,
## which is most of them — `STR_VAR_1` alone is written 176 times across the
## corpus and read 1369 times.
##
## Placeholders are ALREADY IN BRACE FORM in this project's extracted text
## (`{STR_VAR_1}`, `{PLAYER}`), because the M27F Stage 1 extractor resolved
## source's own two-byte `PLACEHOLDER_BEGIN` encoding at extraction time. So
## this is a string substitution, not a byte-stream walk.

const SLOTS := 3

## ⚠️ Unknown placeholders expand to EMPTY, which is source's own rule
## (`GetExpandedPlaceholder` returns `gText_ExpandedPlaceholder_Empty` for any
## id past its table) — not a convenience. It matters because the corpus
## carries markers this project has no concept for, and leaving a raw `{KUN}`
## in the middle of a sentence would look like a bug to a player.
const EMPTY := ""

## Identity placeholders this project cannot answer properly yet.
##
## ⚠️ `{PLAYER}` is 1193 corpus uses and there is NO player-identity system —
## M27K owns naming. "LEAF" matches the overworld sprite and the battle side's
## own `_PLAYER_BACK_PIC`, so all three halves agree on who the player is until
## then, rather than each inventing a different answer.
const PLAYER_NAME := "LEAF"
const RIVAL_NAME := "BLUE"

## ⚠️ `{KUN}` is genuinely EMPTY in English — `gText_ExpandedPlaceholder_Kun`
## and `_Chan` are both `_("")` (`strings.c:8-9`). It is a Japanese honorific
## slot the English build deliberately blanks, not a missing string. 400 corpus
## uses, so getting this wrong would be visible everywhere.
const FIXED := {
	"PLAYER": PLAYER_NAME,
	"RIVAL": RIVAL_NAME,
	"KUN": "",
	"VERSION": "AS IMAGINED",
	"LEFT_ARROW": "◀",
	"RIGHT_ARROW": "▶",
	"UP_ARROW": "▲",
	"DOWN_ARROW": "▼",
}

var _slots: PackedStringArray = PackedStringArray(["", "", ""])
var _std: Dictionary = {}
var _std_by_id: Dictionary = {}


func _init() -> void:
	var f := FileAccess.open("res://data/std_strings.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_std = parsed.get("by_name", {})
		_std_by_id = parsed.get("by_id", {})


## Resolve a slot argument to 0-2, or -1 if it names no slot.
##
## ⚠️ BOTH SPELLINGS ARE REAL. Scripts mostly write `STR_VAR_1`, but the corpus
## also carries a bare `0` — the macro takes an index and two call sites pass
## the number directly. Handling only the named form drops those silently.
static func slot_index(arg: String) -> int:
	match arg:
		"STR_VAR_1": return 0
		"STR_VAR_2": return 1
		"STR_VAR_3": return 2
	if arg.is_valid_int():
		var i := int(arg)
		return i if i >= 0 and i < SLOTS else -1
	return -1


func set_slot(index: int, value: String) -> void:
	if index < 0 or index >= SLOTS:
		return
	_slots[index] = value


func get_slot(index: int) -> String:
	if index < 0 or index >= SLOTS:
		return EMPTY
	return _slots[index]


func clear() -> void:
	_slots = PackedStringArray(["", "", ""])


## A `STDSTRING_*` constant, or its ordinal, as text.
func std_string(arg: String) -> String:
	if _std.has(arg):
		return str(_std[arg])
	if arg.is_valid_int() and _std_by_id.has(arg):
		return str(_std_by_id[arg])
	return EMPTY


## Expand every `{...}` marker in one page of text.
##
## Deliberately single-pass over the real markers rather than a repeated
## replace: source's own expander recurses into an expanded value, but this
## project's buffers only ever hold plain names and numbers, and a naive
## repeated pass over attacker-controlled content is how a substitution loop
## turns into an infinite one.
func expand(text: String) -> String:
	if not text.contains("{"):
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var open_at := text.find("{", i)
		if open_at < 0:
			out += text.substr(i)
			break
		var close_at := text.find("}", open_at)
		if close_at < 0:
			out += text.substr(i)
			break
		out += text.substr(i, open_at - i)
		out += _value_for(text.substr(open_at + 1, close_at - open_at - 1))
		i = close_at + 1
	return out


## What one marker's name expands to.
func _value_for(name: String) -> String:
	var slot := slot_index(name)
	if slot >= 0:
		return _slots[slot]
	if FIXED.has(name):
		return str(FIXED[name])
	# Control markers the extractor preserved (`{PLAY_BGM}`, `{FONT_NORMAL}`,
	# a bare music constant) are directives, not text. Source drops them from
	# the rendered string too — they drive sound and font, neither of which
	# exists here yet. Falling through to EMPTY is the same answer.
	return EMPTY
