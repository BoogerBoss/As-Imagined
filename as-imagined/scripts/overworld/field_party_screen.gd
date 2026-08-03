class_name FieldPartyScreen
extends CanvasLayer

## [M27I I5-2] The field party — the first screen that shows your team.
##
## `[M27O O4]` made the party persistent, `[M27H H4]` made it grow by catching,
## and nothing has ever displayed it.
##
## ⚠️ **SHOWS ALL SIX SLOTS, INCLUDING FAINTED ONES — AND THAT IS SOURCE, NOT A
## DEVIATION FROM IT.** Verified directly: `RenderPartyMenuBoxes`
## (`party_menu.c:1236-1243`) walks slot 0 through `PARTY_SIZE` unconditionally;
## there is no eligibility filter anywhere in the draw path. Every ineligible
## case prints a REASON instead of vanishing — at selection time for the battle
## switch (`:7544-7583`: "has no energy left to battle!" / "is already in
## battle!" / "An EGG can't battle!" / "has already been selected." / "can't
## switch out!", each setting a message then returning FALSE), and at draw time
## for menus that know eligibility up front (`:1101/1125/1148/1198` print
## **"NOT ABLE"**, `gText_NotAble`, `strings.c:341`).
##
## So do NOT "restore" a filter here to match the battle-side
## `SwitchSelectScreen` — that screen is the one that diverges
## (`switch_select_screen.gd:189` skips active-or-fainted members), and
## `docs/m26_e3_recon.md` §2 already records it as a known gap with the fix
## scoped into M26E3's own design change #2.
##
## ⚠️ **IT DOES NOT OWN ITEM USE.** Source's flow starts in the BAG — pick an
## item, choose USE, and the party menu opens as a TARGET PICKER
## (`ItemUseOutOfBattle_Medicine` -> party menu). The same recon's own
## out-of-scope list says so explicitly: "item flow lives in the bag screen".
## This screen just reports which slot was chosen.

signal mon_chosen(index: int)
signal cancelled()

const MARGIN := 40
const ROW_HEIGHT := 76

## Shown above the list. Source swaps this for "Do what with this Pokémon?" and
## for the item-use prompt; the two modes it needs today are these.
const PROMPT_BROWSE := "Choose a POKéMON."
const PROMPT_USE_ITEM := "Use %s on which POKéMON?"

var _panel: Panel
var _prompt: Label
var _rows_box: VBoxContainer

var _party: BattleParty = null
var _index := 0
var _open := false
var _prompt_text := PROMPT_BROWSE


var is_open: bool:
	get:
		return _open

var index: int:
	get:
		return _index


func _init() -> void:
	# Above the bag (70), because the bag is what opens it.
	layer = 75


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

	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows_box.offset_left = 24
	_rows_box.offset_top = 72
	_rows_box.offset_right = -24
	_rows_box.offset_bottom = -24
	_panel.add_child(_rows_box)

	visible = false


## Open as a browser, or as a target picker when `item_name` is given.
func open(party: BattleParty, item_name: String = "") -> void:
	_party = party
	_index = 0
	_open = true
	_prompt_text = PROMPT_BROWSE if item_name == "" else PROMPT_USE_ITEM % item_name
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	cancelled.emit()


## ⚠️ CLAMPS, like the bag's item list and for the same reason: with nothing to
## tell the player it wrapped, a held Down would cycle forever.
func move(delta: int) -> void:
	if not _open or _party == null or _party.members.is_empty():
		return
	_index = clampi(_index + delta, 0, _party.members.size() - 1)
	_refresh()


## Pick the highlighted slot. Reports the index; the CALLER decides whether the
## pick is legal, because legality depends on why the screen was opened.
func confirm() -> int:
	if not _open or _party == null or _index >= _party.members.size():
		return -1
	var i := _index
	_open = false
	visible = false
	mon_chosen.emit(i)
	return i


func prompt_text() -> String:
	return _prompt_text


## One line per slot. Fainted slots are shown, marked, and still selectable —
## refusing them is the caller's job, so a Revive could target one later.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _party == null:
		return out
	for i in range(_party.members.size()):
		var m: BattlePokemon = _party.members[i]
		var mark := "▶ " if i == _index else "   "
		var name := m.species.species_name if m.species != null else "?"
		var state := ""
		if m.fainted or m.current_hp <= 0:
			state = "  FNT"
		elif m.status != BattlePokemon.STATUS_NONE:
			state = "  %s" % status_label(m.status)
		out.append("%s%s  Lv%d  %d/%d%s"
				% [mark, name, m.level, m.current_hp, m.max_hp, state])
	return out


## Source's own three-letter status abbreviations (`gStatusConditionStrings`).
static func status_label(status: int) -> String:
	match status:
		BattlePokemon.STATUS_POISON, BattlePokemon.STATUS_TOXIC: return "PSN"
		BattlePokemon.STATUS_BURN: return "BRN"
		BattlePokemon.STATUS_PARALYSIS: return "PAR"
		BattlePokemon.STATUS_SLEEP: return "SLP"
		BattlePokemon.STATUS_FREEZE: return "FRZ"
	return ""


func _refresh() -> void:
	if _prompt == null:
		return
	_prompt.text = _prompt_text
	for c in _rows_box.get_children():
		c.queue_free()
	for t in row_texts():
		var row := Label.new()
		row.text = t
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		_rows_box.add_child(row)
