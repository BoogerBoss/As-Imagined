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
# - Item list font: this doc comment originally claimed FONT_NORMAL,
#   re-checked and CORRECTED by M25h-3's own later audit -- source's real
#   WIN_ITEM_LIST rows use FONT_NARROW (`sItemListMenu.fontId`,
#   item_menu.c:287), not FONT_NORMAL (that's the CURSOR glyph's own font,
#   a separate direct BagMenu_Print call, and the header's font -- both
#   still correctly FONT_NORMAL). Left unfixed here deliberately -- the
#   actual font swap is M25h-5's own scoped job (FONT_NARROW isn't pulled/
#   extracted into this project yet), not this session's (M25h-4, visual
#   ELEMENTS only). This project's own "menu" FONT_NORMAL context
#   (M25h-1.2) remains what's actually wired below until then.
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
# switching, and the big animated bag_male.png/bag_female.png graphic
# bounces behind the list. NONE of that is reproduced here: this project has
# no player-gender/overworld-avatar concept the big bag graphic depends on,
# and every other pocket besides the one already-implemented battle-item set
# has zero real content to show. Building real multi-pocket browsing now
# would be scope far beyond what has real data behind it -- explicitly
# deferred to M26 (Full RPG rescope), which owns the real bag/inventory
# system this would need. One single flat list (matching what genuinely IS
# usable right now) is the faithful-but-proportionate choice.
#
# [M25h-4, Part C] Item icons remain absent (confirmed via direct read of
# the list-drawing function: BlitBitmapToWindow is only used for the TM/HM
# slot's icon and a "registered item" indicator, neither applicable to a
# curated battle-item list -- text rows only). The per-row quantity ("x12")
# slot DOES now exist as a real, correctly-positioned layout element (see
# _build()'s own qty_label, right-aligned matching item_menu.c:1011-1014's
# real GetStringRightAlignXOffset placement) -- but renders empty, since
# `ItemData` still has no quantity field and these 3 items are still this
# project's own "always available, unlimited use" placeholder set, unchanged
# since M23.1. A future session wiring in real item-quantity data needs only
# to set qty_label.text, not touch layout.

# [Pocket-sorting investigation, same day] Confirmed via direct source read
# (data/items.h) that Potion(28)/Full Heal(48)/X Attack(121) -- this
# screen's entire real item roster -- all carry `.pocket = POCKET_ITEMS`.
# So do PP Up and Rare Candy (checked as part of the same investigation,
# since a task prompt raised them -- though NEITHER exists anywhere in
# this project's own data at all, confirmed via a direct grep; there was
# nothing to resolve for them specifically, only the general principle to
# confirm). Every real pocket-tab candidate this project could plausibly
# add given its own current battle-item scope (more POCKET_ITEMS medicine/
# X-items) still lands in the exact same single pocket -- POCKET_POKE_BALLS/
# POCKET_TM_HM/POCKET_KEY_ITEMS are never battle-relevant, and
# POCKET_BERRIES would need a "manually feed a held berry from the bag"
# mechanic this project has never built (berries are currently held-item-
# only, M12/M18's own scope). Real multi-pocket TAB-SWITCHING UI (source's
# own `PrintPocketNames`/`DrawPocketIndicatorSquare`/pocket-switch scroll
# arrows) was investigated and confirmed buildable with zero new asset
# pulls (pocket names are plain text through the same font already in use;
# the current-pocket indicator is a raw solid-color tilemap square, not an
# icon; the switch arrows are the same generic SCROLL_ARROW_LEFT/RIGHT
# primitive used all over source, not Bag-specific art) -- but building
# real switching chrome for a screen that can only ever show ONE populated
# tab, given this project's own real current scope, would be pure unused
# machinery, the same principle this screen's own original scope decision
# above already applied to the pocket-tab question in general. What IS
# built: the real POCKET_ITEMS data (ItemManager.POCKET_ITEMS, set
# explicitly on all 3 items in gen_items.py, even though it's already the
# schema default) and the real pocket NAME as this screen's own header
# (source: `gPocketNamesStringsTable[POCKET_ITEMS] = "ITEMS"`,
# strings.c:206) -- genuine source-accurate architecture and the one real,
# cheap authenticity win available, without the zero-payoff tab UI.
signal item_chosen(item_id: int)
signal cancelled()

const _HEADER_TEXT := "ITEMS"

# [Reuses the exact same 3 hardcoded items/descriptions already shown by
# the old inline _button_area implementation -- no new item data, this is
# a screen-architecture change only, not new item content. "pocket" is
# carried here for documentation/future-proofing (if this roster ever
# grows to include a genuinely different real pocket, grouping logic can
# key off this field directly) -- not read by _build() yet, since every
# entry currently shares the same real pocket.]
const _ITEMS := [
	{"id": 28, "label": "Potion (heal)", "pocket": 0},
	{"id": 48, "label": "Full Heal (cure status)", "pocket": 0},
	{"id": 121, "label": "X Attack (+1 Attack)", "pocket": 0},
]

# [M25h-4-follow-up] The screen's own structural/positioning nodes
# (Backdrop/Panel/FrameRect/Margin/VBox/Header/Spacer) now live as REAL
# nodes in item_select_screen.tscn, not built in code -- this lets the
# whole panel (position, size, the real bag_frame.png art) be dragged/
# resized directly in the Godot editor's 2D viewport, rather than only
# tunable by editing anchor float literals here and re-running the game to
# see the result. Only the ITEM ROWS + Cancel button stay dynamic (built
# from _ITEMS below), since their count/content is genuinely data-driven,
# not something a fixed scene-tree layout can represent. If you resize
# Panel in the editor, this script keeps working unchanged -- it never
# reads back the panel's own size, only adds its dynamic content into
# VBox, whose container layout follows wherever Panel/Margin end up.
#
# [Deliberately $Path in _build(), NOT @onready] @onready only resolves at
# NOTIFICATION_READY (real tree entry) -- this project's own established
# bare-instance test convention (item_select_screen_test.gd) calls
# setup()/_build() directly on a freshly instantiate()'d overlay that's
# NEVER added to a tree at all, to avoid the --autoplay sweep risk a real
# battle_screen.tscn instance would carry (see that file's own doc
# comment). A plain $Path lookup inside _build() itself resolves against
# the child nodes instantiate() already created regardless of tree
# membership, so it works in both the real (tree-added) and test
# (bare-instance) cases with no special-casing.
# [Doubles-split roadmap, step 5] Deliberately UNTYPED -- a strict
# BattleScreenShared type here would work fine on its own (the sole caller
# since step 7 retired the old monolithic BattleScreen class), but a plain
# `Control` type would still fail GDScript's static member-access checking
# for the custom fields/methods this overlay calls on it
# (_font_menu/_style_menu_button/_player_party/etc., none of which exist on
# plain Control). Left untyped rather than re-tightened to BattleScreenShared
# specifically, since nothing about this overlay's own logic actually needs
# the stricter type -- it just calls whatever duck-typed interface its
# caller provides.
var _parent_bs = null
var _field_slot: int = 0


func setup(parent_bs, field_slot: int) -> void:
	_parent_bs = parent_bs
	_field_slot = field_slot
	_build()


func _build() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox
	var header: Label = $Panel/Margin/VBox/Header

	header.text = _HEADER_TEXT
	if _parent_bs != null:
		header.add_theme_font_override("font", _parent_bs._font_menu)
		header.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		header.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	var buttons: Array[Button] = []
	for entry in _ITEMS:
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var btn := Button.new()
		if _parent_bs != null:
			_parent_bs._style_menu_button(btn)
			_parent_bs._strip_button_chrome(btn)
		btn.text = entry["label"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_item_button_pressed.bind(entry["id"]))
		row.add_child(btn)
		buttons.append(btn)

		# [M25h-4, Part C] Reserved quantity-text slot, matching source's
		# real right-aligned "xNN" placement (GetStringRightAlignXOffset(
		# FONT_NARROW, gStringVar4, 119), item_menu.c:1011-1014) -- this
		# project's items are currently unlimited-use placeholders with no
		# real stack count (M25h-1.4's own disclosed scope decision,
		# unchanged), so this renders empty rather than fabricating a
		# number. The layout slot itself is real and correctly positioned
		# now, so a future session wiring in real item quantities needs no
		# layout change, only setting this label's own .text.
		var qty_label := Label.new()
		qty_label.text = ""
		qty_label.custom_minimum_size = Vector2(32, 0)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _parent_bs != null:
			qty_label.add_theme_font_override("font", _parent_bs._font_menu)
			qty_label.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
			qty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		row.add_child(qty_label)

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
