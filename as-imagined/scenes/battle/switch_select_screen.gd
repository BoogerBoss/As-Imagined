extends Control
class_name SwitchSelectScreen

# [M25h-1.5] A genuine separate full-screen Switch/Party view, matching
# source's own real architecture (`OpenPartyMenuToChooseMon` ->
# `CloseMainBattleScreen()` + a `gMain.callback2` swap to
# `OpenPartyMenuInBattle` -> `InitPartyMenu`, confirmed directly against
# `battle_controller_player.c`/`party_menu.c`) -- the same overlay-not-
# scene-swap deviation already established and disclosed by M25h-1.4's
# ItemSelectScreen (BattleManager is a scene-tree CHILD NODE that must
# survive the trip; see that file's own doc comment for the full rationale,
# unchanged here).
#
# [Real source structural findings, reused directly rather than invented]
# - The real in-battle party screen (`OpenPartyMenuInBattle`) always shows
#   the SAME header message regardless of voluntary-vs-forced context --
#   `PARTY_MSG_CHOOSE_MON` = gText_ChoosePokemon = "Choose a POKéMON."
#   (strings.c:304) -- confirmed directly, NOT the "_OR_CANCEL" variant,
#   even for the voluntary case. Source distinguishes voluntary vs. forced
#   behaviorally (see below), not via the header text, so this screen's own
#   header stays fixed regardless of _is_forced_replacement; the existing
#   ActionPanel `_status_label` (outside this overlay, already set by
#   _refresh_ui before this screen opens) is what actually carries the
#   distinct "fainted, choose a replacement" vs "choose a Pokémon to switch
#   in" framing in THIS project, matching its own pre-existing convention.
# - Cancel behavior genuinely differs and was confirmed directly against
#   `HandleChooseMonCancel` (party_menu.c): for PARTY_ACTION_SEND_OUT and
#   PARTY_ACTION_CHOOSE_FAINTED_MON (the two forced-replacement actions
#   OpenPartyMenuToChooseMon can be entered with), pressing B plays a
#   failure sound and does NOTHING -- no cancel path exists at all. For
#   PARTY_ACTION_SWITCH (voluntary), B triggers a real cancel
#   (FinishTwoMonAction). This project's OWN pre-existing `_build_switch_
#   buttons` already matched this exactly (no Back button built at all for
#   is_forced_replacement, confirmed by re-reading that function before this
#   screen was built) -- reproduced here unchanged, not a new decision.
# - Party rows in real source show name/level, an HP bar, and a status
#   condition icon per Pokémon (`GetMonStatusAndPokerus`/health bar draw in
#   party_menu.c) -- reused here via this project's OWN already-pulled real
#   assets from Phase 4b (hpbar.png's label/fill regions, status.png's
#   6-row status icon sheet, `_hp_bar_color`'s threshold coloring), not a
#   new asset pull, exactly mirroring M25h-1.4's own "reuse already-real
#   assets in a new context" pattern.
#
# [Deliberate scope narrowing, disclosed] Source's real Party screen has a
# genuine dedicated background/slot-frame graphic (`graphics/party_menu/
# bg.png`, `slot_main.bin`/`slot_wide.bin`) -- confirmed via direct source
# read to be raw GBA tilesets/tilemaps (INCGFX_U32 4bpp + separate binary
# tilemap data), the SAME class of asset M25h-1.4 already declined to
# reconstruct for the Bag screen's own `bag/menu.png` (and the same class
# Phase 5a already tried once and abandoned as disproportionate for battle
# backgrounds). This screen reuses the already-pulled, already-flat
# `text_window/1.png` panel art (h-1.1) instead, matching Item's own
# precedent exactly. Held-item icons (`hold_icons.png`, also a raw
# palette-indexed tileset, never pulled anywhere in this project) are
# likewise NOT shown per row -- no held-item UI concept exists anywhere in
# this project's own UI yet, so adding one here would be new scope beyond
# what switching itself needs, not a faithful-but-proportionate reuse.
signal mon_chosen(slot: int)
signal cancelled()

# [Real source, strings.c:304] gText_ChoosePokemon -- see doc comment above
# for why this stays fixed regardless of voluntary-vs-forced context.
const _HEADER_TEXT := "Choose a POKéMON."

const _HP_BAR_SIZE := Vector2(72, 10)
const _STATUS_ICON_DISPLAY_SIZE := Vector2(24, 8)

var _parent_bs: BattleScreen = null
var _field_slot: int = 0
var _is_forced_replacement: bool = false


func setup(parent_bs: BattleScreen, field_slot: int, is_forced_replacement: bool) -> void:
	_parent_bs = parent_bs
	_field_slot = field_slot
	_is_forced_replacement = is_forced_replacement
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
	# [Screenshot-verified adjustment] First draft used anchor_right=0.68 --
	# real screenshot review found the extra width left a wide, visually
	# empty gap between each row's name/HP text and its HP bar/status icon,
	# unlike source's own tighter real list. Narrowed to bring the bar/icon
	# close to the text, matching M25h-1.4's own established "verify
	# visually once built, adjust only if proven necessary" precedent.
	panel.anchor_right = 0.42
	panel.anchor_bottom = 0.7
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

	var party: BattleParty = _parent_bs._player_party
	var buttons: Array[Button] = []
	for i in range(party.members.size()):
		if party.active_indices.has(i) or party.members[i].fainted:
			continue
		var mon: BattlePokemon = party.members[i]
		var row := _build_mon_row(mon, i)
		vbox.add_child(row.container)
		buttons.append(row.button)

	if not _is_forced_replacement:
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


# Builds one clickable party row: a chrome-stripped, cursor-group-eligible
# Button carrying the row's own text (name/level/HP fraction, matching
# _name_level_text's existing convention), with the real HP-bar and
# status-icon assets from Phase 4b layered on as child nodes anchored to
# the row's right side -- Button.text drives cursor-group selection
# (_wire_cursor_group/_set_cursor_selected rewrite .text directly), so the
# bar/icon children, added separately, are never touched by that rewrite.
func _build_mon_row(mon: BattlePokemon, slot: int) -> Dictionary:
	var btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
	var name_level: String = _parent_bs._name_level_text(mon) if _parent_bs != null else "%s Lv%d" % [mon.species.species_name, mon.level]
	btn.text = "%s   HP %d/%d" % [name_level, mon.current_hp, mon.max_hp]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 28)
	btn.pressed.connect(_on_mon_button_pressed.bind(slot))

	if _parent_bs != null:
		var hpbar_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/hpbar.png")
		var hp_fill_atlas := AtlasTexture.new()
		hp_fill_atlas.atlas = hpbar_sheet
		hp_fill_atlas.region = BattleScreen._HP_FILL_REGION
		var hp_bar := TextureProgressBar.new()
		hp_bar.texture_progress = hp_fill_atlas
		hp_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
		hp_bar.max_value = mon.max_hp
		hp_bar.value = mon.current_hp
		hp_bar.tint_progress = _parent_bs._hp_bar_color(mon.current_hp, mon.max_hp)
		hp_bar.anchor_left = 0.5
		hp_bar.anchor_right = 0.5
		hp_bar.anchor_top = 0.5
		hp_bar.anchor_bottom = 0.5
		hp_bar.offset_left = 0
		hp_bar.offset_top = -_HP_BAR_SIZE.y / 2.0
		hp_bar.offset_right = _HP_BAR_SIZE.x
		hp_bar.offset_bottom = _HP_BAR_SIZE.y / 2.0
		hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hp_bar)

		var status_row := BattleScreen._status_icon_row(mon.status)
		if status_row >= 0:
			var status_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/status.png")
			var status_atlas := AtlasTexture.new()
			status_atlas.atlas = status_sheet
			status_atlas.region = Rect2(0, status_row * BattleScreen._STATUS_ICON_SIZE.y, BattleScreen._STATUS_ICON_SIZE.x, BattleScreen._STATUS_ICON_SIZE.y)
			var status_icon := TextureRect.new()
			status_icon.texture = status_atlas
			status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			status_icon.anchor_left = 0.85
			status_icon.anchor_right = 0.85
			status_icon.anchor_top = 0.5
			status_icon.anchor_bottom = 0.5
			status_icon.offset_left = 0
			status_icon.offset_top = -_STATUS_ICON_DISPLAY_SIZE.y / 2.0
			status_icon.offset_right = _STATUS_ICON_DISPLAY_SIZE.x
			status_icon.offset_bottom = _STATUS_ICON_DISPLAY_SIZE.y / 2.0
			status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(status_icon)

	return {"container": btn, "button": btn}


func _on_mon_button_pressed(slot: int) -> void:
	mon_chosen.emit(slot)


func _on_cancel_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	# [Real source parity] ESC mirrors B_BUTTON -- but B_BUTTON is a genuine
	# no-op during a forced replacement (HandleChooseMonCancel's
	# PARTY_ACTION_SEND_OUT/PARTY_ACTION_CHOOSE_FAINTED_MON branch plays only
	# a failure sound, never cancels), so this handler is deliberately inert
	# in that case rather than emitting `cancelled` anyway.
	if _is_forced_replacement:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
