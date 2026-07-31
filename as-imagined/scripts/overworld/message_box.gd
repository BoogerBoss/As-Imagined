class_name MessageBox
extends CanvasLayer

## [M27F Stage 1] The overworld message box.
##
## Owns presentation only — which page is showing, whether it has finished
## typing, and the "press on" prompt. It does NOT decide what to say or when to
## advance; ScriptVM does, and the overworld drives the two together. That split
## is why the VM's pause states are external: this node reacts to them.
##
## Built in code rather than as a .tscn, matching how the fade and the battle
## overlay are built — it has no authored content, only layout.

signal page_finished()      ## the current page has finished typing
signal advanced()           ## the player pressed on and there are more pages
signal closed()             ## the last page was dismissed

const MARGIN := 24
const HEIGHT := 140

var _panel: Panel
var _typer: TextTyper
var _prompt: Label

var _pages: PackedStringArray = PackedStringArray()
var _index := 0
var _open := false


## Which page is showing, and how many there are. Read by the debug overlay and
## by tests — same external-state discipline as ScriptVM.
var page_index: int:
	get:
		return _index

var page_count: int:
	get:
		return _pages.size()

var is_open: bool:
	get:
		return _open

var is_typing: bool:
	get:
		return _typer != null and _typer.is_typing


func _init() -> void:
	# Above the world, BELOW the fade (200) and below the battle overlay (100),
	# so a battle or a transition covers the box rather than the reverse.
	layer = 50


func _ready() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = -(HEIGHT + MARGIN)
	_panel.offset_bottom = -MARGIN
	add_child(_panel)

	_typer = TextTyper.new()
	_typer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_typer.offset_left = 16
	_typer.offset_top = 12
	_typer.offset_right = -16
	_typer.offset_bottom = -12
	_typer.bbcode_enabled = false
	_typer.finished_typing.connect(_on_finished_typing)
	_panel.add_child(_typer)

	# The "there is more" marker. Source blinks a down-arrow; a character is
	# enough to communicate the same thing without an asset pull.
	_prompt = Label.new()
	_prompt.text = "▼"
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_prompt.offset_left = -28
	_prompt.offset_top = -30
	_prompt.visible = false
	_panel.add_child(_prompt)

	visible = false


## Show a message. `pages` is already split on \p by the text pipeline.
func open(pages: PackedStringArray) -> void:
	_pages = pages if pages.size() > 0 else PackedStringArray([""])
	_index = 0
	_open = true
	visible = true
	_show_current()


## The player pressed on. Either reveals the rest of a typing page (source lets
## you skip), advances to the next page, or closes.
##
## Returns true if the box is still open afterwards.
func advance() -> bool:
	if not _open:
		return false
	if _typer.is_typing:
		_typer.skip_typing()
		return true
	if _index + 1 < _pages.size():
		_index += 1
		_show_current()
		advanced.emit()
		return true
	close()
	return false


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_prompt.visible = false
	_pages = PackedStringArray()
	_index = 0
	closed.emit()


func _show_current() -> void:
	_prompt.visible = false
	_typer.type_out(_pages[_index])


func _on_finished_typing() -> void:
	# Only prompt when there is genuinely more to see; on the last page the
	# press closes the box, which needs no marker of its own.
	_prompt.visible = _index + 1 < _pages.size()
	page_finished.emit()
