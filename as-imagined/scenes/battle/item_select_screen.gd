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
# [M26E1, 2026-08-05] Rewired onto the real `OverworldSession.bag`, the
# battle-legality pocket filter, real quantities, and the real feed-a-berry
# mechanic — see `docs/m26_e2_recon.md` §0b for the full account. At that
# point this screen still showed every legal pocket's contents combined in
# one flat list (no tabs yet).
#
# [M26E2, 2026-08-05] Real per-pocket TAB switching, ported from
# `FieldBagScreen.next_pocket`/`move_row`'s own already-correct logic:
#   - `_pocket_order` is `_legal_pockets()`'s own return value (2-3 pockets
#     in battle: Items/Berries always, Poké Balls only in a wild battle) —
#     each shown SEPARATELY now, not combined.
#   - Cycling SKIPS empty pockets — source's real `@choosing`-mode behavior
#     (picking one item to use, not browsing), which
#     `FieldBagScreen`'s own doc comment already identifies as the shape
#     this screen's use case matches, distinct from that screen's own
#     plain-browse (no-skip) mode. Guarded against an all-empty pocket set
#     (a real, if rare, possible state — a playthrough that ran out of
#     everything) by capping the skip search at one full lap.
#   - The pocket NAME now shows in the real pocket-name-bar position
#     (`PocketLabel`, top-left of the real bg_m.png art) rather than inside
#     the item-list box, matching source's own real layout — the box's own
#     "ITEMS"-style in-box header from M26E1 is retired (real source has no
#     such repeated label).
#   - A real pocket POSITION indicator (`DotRow`), using
#     `ItemManager.pocket_dot_region` — see that function's own doc comment
#     for why this is a plain position dot, not per-pocket iconography
#     (`bag_pocket_icons.png`'s own real content, measured directly: 6
#     available slots, a big square for the SELECTED one, a small dot for
#     the rest — matching source's own real "solid-color tilemap square"
#     mechanism, not a picture-per-pocket design).
#   - Input: LEFT/RIGHT cycle pockets, matching this screen's own existing
#     raw-keycode convention (established for ESC) rather than Godot's
#     `ui_left`/`ui_right` actions `FieldBagScreen` uses — the two screens
#     already used different input conventions before this session (battle
#     menus have no InputMap wiring at all, per M25h-1.3's own Step 0), and
#     this keeps the split rather than quietly harmonizing it.
#   - The bag-jump lean now plays on EVERY pocket change too, not just on
#     open — `_play_bag_jump()` needed no changes to support this, exactly
#     as disclosed when it was first built.
#
# [Real source structural findings, reused directly rather than invented]
# - Item list font: this doc comment originally claimed FONT_NORMAL,
#   re-checked and CORRECTED by M25h-3's own later audit -- source's real
#   WIN_ITEM_LIST rows use FONT_NARROW (`sItemListMenu.fontId`,
#   item_menu.c:287), not FONT_NORMAL (that's the CURSOR glyph's own font,
#   a separate direct BagMenu_Print call, and the header's font -- both
#   still correctly FONT_NORMAL). Left unfixed here deliberately -- the
#   actual font swap is M25h-5's own scoped job (FONT_NARROW isn't pulled/
#   extracted into this project yet), not this session's. This project's own
#   "menu" FONT_NORMAL context (M25h-1.2) remains what's actually wired.
# - The cursor is the SAME "▶" glyph already pulled for M25h-1.3
#   (gText_SelectorArrow2 in source -- a different C constant NAME from the
#   battle menu's own gText_SelectorArrow3, but the literal same "▶"
#   string/glyph -- confirmed via direct source read). `docs/m26_e2_recon.md`
#   §0a decision 3 re-confirms reusing this rather than pulling cursor.png.
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
# [Real screenshot verification, 2026-08-05] Confirmed via a disposable
# scratch driver (deleted after the session): the real bg_m.png background,
# item list (with real quantities), cursor, and bag-sprite all render
# correctly at their real positions. One disclosed minor cosmetic gap found
# and NOT fixed this session: a description string containing certain
# characters (e.g. "P", digits) renders a few glyphs as visible black boxes
# in the menu-context bitmap font — a font glyph-coverage gap, not a layout
# or data bug (the underlying description text itself is correct, per
# `_item_description`'s own real `items.json` data). Flagged for a future
# font-coverage pass, not chased down here.
#
# [Still deliberately NOT built, disclosed] `bag_female.png`/gender
# selection (no player-gender concept exists anywhere in this project).
# Per-item icon art (source has none for this list either, per the finding
# above). The full frame-by-frame `pbBagJump` lean plus its 7-frame
# ball-flash strip stepping — this project's own simplified scale/rotate
# tween stands in, per `docs/m26_e2_recon.md`'s own decision 4.
signal item_chosen(item_id: int)
signal cancelled()

## [M26E1] Standalone/debug-mode seed stock — see `_ensure_debug_stock`'s own
## doc comment for the exact gate. The same 4 items this screen has shown
## since M23.1/M27H, plus 2 of the newly-bag-feedable berries so standalone
## testing/`--autoplay` coverage of the berry path doesn't regress either.
const _DEBUG_STOCK := [
	{"id": 28, "count": 10},   # Potion
	{"id": 48, "count": 5},    # Full Heal
	{"id": 121, "count": 5},   # X Attack
	{"id": 1, "count": 10},    # Poké Ball
	{"id": 520, "count": 5},   # Oran Berry
	{"id": 522, "count": 5},   # Lum Berry
]

const _EMPTY_TEXT := "No items."

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

## [M26E2] Computed once per `setup()`/`_build()` call — `is_wild_battle`
## is read once at open time, matching `_legal_pockets`'s own pre-existing
## "computed fresh every open" contract; a battle can't change from wild to
## trainer mid-fight, so re-reading it per cycle would be pointless.
var _pocket_order: Array = []
var _pocket_index: int = 0

## [M26E1] The rows this screen actually built for the CURRENT pocket, in
## display order, so a row button's own hover can look up "which item/
## description is this."
var _row_item_ids: PackedInt32Array = PackedInt32Array()


func setup(parent_bs, field_slot: int) -> void:
	# [M26A1 / 3:2 Phase 3] Letterboxed at an honest integer 2x rather than
	# stretched to 3:2 — see `UiLetterbox`. Applied here rather than in the
	# `.tscn` so all three screens share ONE mechanism, including
	# `switch_select_screen`, which has no tree to author it into.
	UiLetterbox.apply(self)
	var _backdrop := get_node_or_null("Backdrop") as Control
	if _backdrop != null:
		UiLetterbox.expand_to_viewport(_backdrop)
	_parent_bs = parent_bs
	_field_slot = field_slot
	_build()


## Which pockets this screen is allowed to show, computed fresh every open
## since `is_wild_battle` can differ between battles in the same session.
## Source: real games only allow POCKET_POKE_BALLS in a wild encounter
## (never against a trainer, `is_wild_battle`) and never open POCKET_TM_HM/
## POCKET_KEY_ITEMS from battle at all (teaching a move or using a Bike
## mid-fight isn't a real battle-legal action, and this project has no such
## mechanics regardless). POCKET_BERRIES is included per
## docs/m26_e2_recon.md §0a decision 2/2b.
func _legal_pockets() -> Array:
	var pockets: Array = [ItemManager.POCKET_ITEMS, ItemManager.POCKET_BERRIES]
	if _parent_bs != null and _parent_bs._bm != null and _parent_bs._bm.is_wild_battle:
		pockets.append(ItemManager.POCKET_POKE_BALLS)
	return pockets


## [M26E1] Seeds a small standalone/debug stock into `OverworldSession.bag`
## — ONLY when this battle was NOT launched from the overworld
## (`_parent_bs.is_overworld_battle == false`, the standalone battle
## simulator's own case, `main.tscn` -> "Start Battle" -> `battle_setup
## _screen.tscn`, which has no RPG session behind it and so never put
## anything real into the bag). A real RPG playthrough's own bag is never
## touched by this function — the gate is checked BEFORE any `Bag.add()`
## call, not worked around after the fact.
##
## Re-tops-up each entry independently (`has_item(id, 1)` gate, not a
## one-shot flag) rather than seeding once and letting it deplete — this is
## a testing convenience, not a resource-scarcity simulation, matching
## `[M27D D5]`'s own debug-party precedent of always handing back something
## usable rather than modelling depletion for its own sake.
func _ensure_debug_stock() -> void:
	if _parent_bs != null and _parent_bs.is_overworld_battle:
		return
	for entry in _DEBUG_STOCK:
		var id: int = int(entry["id"])
		if not OverworldSession.bag.has_item(id, 1):
			OverworldSession.bag.add(id, int(entry["count"]))


## [M26E2] The battle-usable (item_id, item, count) rows a pocket would
## show — the SAME filter `_build()` used to apply across every legal
## pocket combined at once before this session, now scoped to one pocket
## so cycling can ask "does pocket N have anything at all."
func _pocket_rows(pocket: int) -> Array:
	var out: Array = []
	for slot in OverworldSession.bag.slots(pocket):
		var item_id: int = int(slot["item"])
		var count: int = int(slot["count"])
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item == null or item.battle_usage == 0:
			continue
		out.append({"id": item_id, "item": item, "count": count})
	return out


func _pocket_has_items(pocket: int) -> bool:
	return not _pocket_rows(pocket).is_empty()


func _build() -> void:
	_ensure_debug_stock()

	var desc_label: Label = $Panel/DescLabel
	# [M26E1] `_font_menu` can genuinely be null here — a bare-instance test
	# that never ran the parent's own `_ready()` (this project's own
	# established convention, see `_style_menu_button`'s identical guard),
	# or a real battle screen whose `_load_battle_fonts()` call hasn't
	# resolved yet at the moment this overlay is built. Either way, missing
	# a font override is the correct degrade — not a crash.
	if _parent_bs != null and _parent_bs._font_menu != null:
		desc_label.add_theme_font_override("font", _parent_bs._font_menu)
		desc_label.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		desc_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1))
	desc_label.text = ""

	_pocket_order = _legal_pockets()
	_pocket_index = 0
	# [M26E2] Snap to the first non-empty pocket, matching the same
	# skip-empty discipline `next_pocket` applies when cycling — a fresh
	# open should not land on an empty pocket if a non-empty one exists.
	for i in range(_pocket_order.size()):
		if _pocket_has_items(_pocket_order[i]):
			_pocket_index = i
			break

	_refresh_pocket()


## [M26E2] Rebuilds ONLY the per-pocket content (item rows + Cancel, the
## pocket-name label, the dot row) — called on open and again on every
## `next_pocket()` cycle. The static chrome (background, DescLabel's own
## font, the bag sprite node itself) is set up once in `_build()`/the
## .tscn and untouched here.
func _refresh_pocket() -> void:
	var vbox: VBoxContainer = $Panel/Margin/VBox
	var desc_label: Label = $Panel/DescLabel
	var pocket_label: Label = $Panel/PocketLabel
	var dot_row: HBoxContainer = $Panel/DotRow

	# Clear every dynamic row (everything below Header/Spacer — see the
	# .tscn: those two are the only static VBox children). Removed
	# IMMEDIATELY (`remove_child` before `queue_free`), not just
	# queue_free()'d on its own — this project's own established bare-
	# instance test convention calls `next_pocket()` back-to-back with no
	# frame processed in between, and a deferred-only free would leave the
	# PREVIOUS pocket's rows still counted by a synchronous `get_children()`
	# read right after.
	for c in vbox.get_children():
		if c.name != "Header" and c.name != "Spacer":
			vbox.remove_child(c)
			c.queue_free()
	desc_label.text = ""

	var pocket: int = int(_pocket_order[_pocket_index]) if not _pocket_order.is_empty() else ItemManager.POCKET_ITEMS
	var header: Label = $Panel/Margin/VBox/Header
	header.visible = false  # [M26E2] retired — the real pocket name now
			# lives in PocketLabel, matching source's own layout; the node
			# is kept (not deleted) so VBox's own Header/Spacer clear-guard
			# above still has a stable "static" node set to skip.

	pocket_label.text = str(FieldBagScreen.POCKET_NAMES.get(pocket, "?"))
	if _parent_bs != null and _parent_bs._font_menu != null:
		pocket_label.add_theme_font_override("font", _parent_bs._font_menu)
		pocket_label.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		pocket_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	_refresh_dot_row(dot_row)

	var buttons: Array[Button] = []
	_row_item_ids = PackedInt32Array()
	var rows := _pocket_rows(pocket)
	if rows.is_empty():
		var empty_label := Label.new()
		empty_label.text = _EMPTY_TEXT
		if _parent_bs != null and _parent_bs._font_menu != null:
			empty_label.add_theme_font_override("font", _parent_bs._font_menu)
			empty_label.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
			empty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		vbox.add_child(empty_label)
	else:
		for row_data in rows:
			_add_item_row(vbox, buttons, int(row_data["id"]), row_data["item"],
					int(row_data["count"]), desc_label)

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

	_play_bag_jump()


## [M26E2] One `TextureRect` dot per pocket in `_pocket_order`, cropped from
## `bag_pocket_icons.png` via `ItemManager.pocket_dot_region` — see that
## function's own doc comment for the measured region shapes.
func _refresh_dot_row(dot_row: HBoxContainer) -> void:
	for c in dot_row.get_children():
		dot_row.remove_child(c)
		c.queue_free()
	if _pocket_order.size() <= 1:
		return  # a single-pocket set has nothing to indicate a position among.
	var sheet: Texture2D = load("res://assets/sprites/battle_ui/bag/bag_pocket_icons.png")
	for i in range(_pocket_order.size()):
		var dot := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = ItemManager.pocket_dot_region(i, i == _pocket_index)
		dot.texture = atlas
		dot.custom_minimum_size = Vector2(16, 16)
		dot_row.add_child(dot)


## [M26E2] Cycle pockets, SKIPPING any with nothing battle-usable in it —
## source's real `@choosing`-mode behavior (see this file's own class-level
## doc comment). Capped at one full lap so an all-empty pocket set (a real,
## if rare, possible state) can't spin forever; in that case the cycle
## simply lands wherever `delta` would naturally put it, and `_refresh_
## pocket` shows the real "No items." placeholder there.
func next_pocket(delta: int) -> void:
	if _pocket_order.size() <= 1:
		return
	var start := _pocket_index
	var i := wrapi(_pocket_index + delta, 0, _pocket_order.size())
	while i != start:
		if _pocket_has_items(_pocket_order[i]):
			break
		i = wrapi(i + delta, 0, _pocket_order.size())
	_pocket_index = i
	_refresh_pocket()


func _add_item_row(vbox: VBoxContainer, buttons: Array[Button], item_id: int,
		item: ItemData, count: int, desc_label: Label) -> void:
	var row := HBoxContainer.new()
	vbox.add_child(row)

	var btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
	btn.text = _item_label(item_id, item)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_item_button_pressed.bind(item_id))
	btn.mouse_entered.connect(_on_item_row_hovered.bind(item_id, desc_label))
	row.add_child(btn)
	buttons.append(btn)
	_row_item_ids.append(item_id)

	# [M25h-4, Part C -> M26E1] Real quantity, matching source's own
	# right-aligned "xNN" placement (GetStringRightAlignXOffset(FONT_NARROW,
	# gStringVar4, 119), item_menu.c:1011-1014) — now the real per-stack
	# count from the Bag rather than an always-empty placeholder.
	var qty_label := Label.new()
	qty_label.text = "x%d" % count
	qty_label.custom_minimum_size = Vector2(48, 0)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _parent_bs != null and _parent_bs._font_menu != null:
		qty_label.add_theme_font_override("font", _parent_bs._font_menu)
		qty_label.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		qty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	row.add_child(qty_label)


func _item_label(item_id: int, item: ItemData) -> String:
	var identity: Dictionary = PokemonRegistry.get_item_identity(item_id)
	var n := str(identity.get("name", ""))
	return n if n != "" else "ITEM %d" % item_id


## Real per-item description, matching `FieldBagScreen.description_text`'s
## own established treatment of source's literal "\n" escape sequences.
func _item_description(item_id: int) -> String:
	var identity: Dictionary = PokemonRegistry.get_item_identity(item_id)
	return str(identity.get("description", "")).replace("\\n", " ")


func _on_item_row_hovered(item_id: int, desc_label: Label) -> void:
	desc_label.text = _item_description(item_id)


## [M26E1/E2] `pbBagJump`'s own real shape (Emerald UI Pack `002_Bag.rb`): a
## brief lean-and-settle on the bag sprite, played on open AND on every
## pocket change. Reproduced as a simple scale/rotation tween rather than
## the pack's own frame-by-frame lean, and deliberately WITHOUT the
## 7-frame ball-flash strip stepping (a disclosed simplification — the
## flash asset is pulled and available for a future polish pass, see
## gen_bag_sprites.py's own doc comment).
func _play_bag_jump() -> void:
	if not is_inside_tree():
		return
	var sprite: TextureRect = $Panel/BagSprite
	sprite.scale = Vector2(0.85, 1.15)
	sprite.rotation = deg_to_rad(-8.0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(sprite, "scale", Vector2.ONE, 0.28)
	tw.parallel().tween_property(sprite, "rotation", 0.0, 0.28)


func _on_item_button_pressed(item_id: int) -> void:
	item_chosen.emit(item_id)


func _on_cancel_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	# [Real source parity] The real Bag screen's own B_BUTTON cancels back to
	# battle the same as selecting the Cancel row -- this project's menus
	# have no other keyboard wiring (confirmed in M25h-1.3's own Step 0), so
	# only this one extra affordance is added, not a full input remap.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
	elif key == KEY_LEFT:
		get_viewport().set_input_as_handled()
		next_pocket(-1)
	elif key == KEY_RIGHT:
		get_viewport().set_input_as_handled()
		next_pocket(1)
