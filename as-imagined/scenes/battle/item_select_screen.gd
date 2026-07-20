extends Control
class_name ItemSelectScreen

# [M25h-1.4] A genuine separate full-screen Item/Bag view, matching source's
# own real architecture (`OpenBagAndChooseItem` -> `CloseMainBattleScreen()`
# + a `gMain.callback2` swap to `CB2_BagMenuFromBattle` -> `GoToBagMenu`,
# confirmed directly against `battle_controller_player.c`/`item_menu.c`).
#
# [Real architecture deviation, deliberate and disclosed] Source's own
# CloseMainBattleScreen only tears down GRAPHICS/window resources -- the
# underlying battle STATE (gBattleMons, turn order, etc.) lives in a
# completely separate memory region the graphics teardown never touches, so
# it survives the Bag screen for free. This project's BattleManager is a
# scene-tree CHILD NODE of battle_screen.tscn ($BattleManager) -- a real
# `change_scene_to_file()` swap (the same mechanism Run/Play Again already
# use) would FREE it along with the rest of the old tree, destroying the
# entire in-progress battle's state just to show an item picker. Run/Play
# Again can safely use that mechanism because they intentionally END the
# battle; Item selection must return to the exact same live battle
# afterward, so it can't. Instead, this screen is a full-viewport CHILD
# overlay added on top of the still-alive battle_screen instance (BattleManager
# untouched, never reparented or freed) -- a genuine separate scene/script/
# visual identity, real navigation in and out, just not a literal scene-tree
# replacement. See _build_item_buttons' own doc comment in battle_screen.gd
# for the call-site side of this.
#
# [Real source structural findings, reused directly rather than invented]
# - Item list font is FONT_NORMAL (source's WIN_ITEM_LIST window, confirmed
#   via direct read of item_menu.c) -- this project's own "menu" FONT_NORMAL
#   context (M25h-1.2) is the exact right font to reuse, not a new pull.
# - The cursor is the SAME "▶" glyph already pulled for M25h-1.3
#   (gText_SelectorArrow2 in source -- a different C constant NAME from the
#   battle menu's own gText_SelectorArrow3, but the literal same "▶"
#   string/glyph -- confirmed via direct source read).
# - Source's classic list has NO per-row item icon (BlitBitmapToWindow is
#   only used for the TM/HM slot's icon and a "registered item" indicator,
#   neither applicable to a curated battle-item list) -- text rows only,
#   confirmed via direct read of the list-drawing function.
# - Cancel is appended as the LAST entry of the SAME scrollable list
#   (`LIST_CANCEL`), not a separately-styled Back button below it --
#   reproduced here by appending a Cancel button to the exact same
#   `_wire_cursor_group` array the item rows use, matching source's real
#   structure and reusing M25h-1.3's own cursor mechanism with zero changes.
#
# [Deliberate scope narrowing, disclosed] Source's real Bag shows ALL
# pockets (POCKETS_COUNT: Items/Balls/TM-HM/Berries/Key Items) with tab
# switching, item icons are absent in the classic list but a quantity
# ("x12") is shown per stackable item, and the big animated bag_male.png/
# bag_female.png graphic bounces behind the list. NONE of that is
# reproduced here: this project has no player-gender/overworld-avatar
# concept the big bag graphic depends on, no bag/inventory/quantity data
# structure exists anywhere yet (confirmed -- `ItemData` has no quantity or
# description field, and the 3 items below are this project's own already-
# established "always available, unlimited use" placeholder set, unchanged
# since M23.1), and every other pocket besides the one already-implemented
# battle-item set has zero real content to show. Building real multi-pocket
# browsing now would be scope far beyond what has real data behind it --
# explicitly deferred to M26 (Full RPG rescope), which owns the real bag/
# inventory system this would need. One single flat list (matching what
# genuinely IS usable right now) is the faithful-but-proportionate choice.

signal item_chosen(item_id: int)
signal cancelled()

const _HEADER_TEXT := "BAG"

# [Reuses the exact same 3 hardcoded items/descriptions already shown by
# the old inline _button_area implementation -- no new item data, this is
# a screen-architecture change only, not new item content.]
const _ITEMS := [
	{"id": 28, "label": "Potion (heal)"},
	{"id": 48, "label": "Full Heal (cure status)"},
	{"id": 121, "label": "X Attack (+1 Attack)"},
]

var _parent_bs: BattleScreen = null
var _field_slot: int = 0


func setup(parent_bs: BattleScreen, field_slot: int) -> void:
	_parent_bs = parent_bs
	_field_slot = field_slot
	_build()


func _build() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.05, 1.0)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.06
	panel.anchor_right = 0.55
	panel.anchor_bottom = 0.5
	add_child(panel)

	var raw_image: Image = load("res://assets/sprites/battle_ui/text_window/1.png").get_image()
	var keyed_texture: ImageTexture = BattleScreen._color_keyed_texture(raw_image, BattleScreen._ACTION_PANEL_KEY_COLOR)
	var panel_style := StyleBoxTexture.new()
	panel_style.texture = keyed_texture
	panel_style.texture_margin_left = BattleScreen._ACTION_PANEL_MARGIN
	panel_style.texture_margin_top = BattleScreen._ACTION_PANEL_MARGIN
	panel_style.texture_margin_right = BattleScreen._ACTION_PANEL_MARGIN
	panel_style.texture_margin_bottom = BattleScreen._ACTION_PANEL_MARGIN
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var header := Label.new()
	header.text = _HEADER_TEXT
	if _parent_bs != null:
		header.add_theme_font_override("font", _parent_bs._font_menu)
		header.add_theme_font_size_override("font_size", BattleScreen._FONT_NORMAL_SIZE)
		header.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(header)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var buttons: Array[Button] = []
	for entry in _ITEMS:
		var btn := Button.new()
		if _parent_bs != null:
			_parent_bs._style_menu_button(btn)
			_parent_bs._strip_button_chrome(btn)
		btn.text = entry["label"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_item_button_pressed.bind(entry["id"]))
		vbox.add_child(btn)
		buttons.append(btn)

	var cancel_btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(cancel_btn)
		_parent_bs._strip_button_chrome(cancel_btn)
	cancel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	vbox.add_child(cancel_btn)
	buttons.append(cancel_btn)

	if _parent_bs != null:
		_parent_bs._wire_cursor_group(buttons)


func _on_item_button_pressed(item_id: int) -> void:
	item_chosen.emit(item_id)


func _on_cancel_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	# [Real source parity] The real Bag screen's own B_BUTTON cancels back to
	# battle the same as selecting the Cancel row -- this project's menus
	# have no other keyboard wiring (confirmed in M25h-1.3's own Step 0), so
	# only this one extra affordance is added, not a full input remap.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
