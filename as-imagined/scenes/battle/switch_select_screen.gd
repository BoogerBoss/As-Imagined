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
# [M25h-4, Part A -- supersedes the note below] A 3rd tilemap-decode
# attempt (gen_ui_frames.py) succeeded cleanly this time (unlike Phase 5a's
# own flagged-incorrect battle-background reconstruction) -- see that
# script's own doc comment for the full Step 0 writeup on why this attempt
# was warranted despite Phase 5a's history. This screen now uses the real
# decoded `graphics/party_menu/bg.png`+`bg.bin` frame (party_frame.png) and
# the real per-row "wide" slot art (`slot_wide.bin`, party_slot_wide.png --
# confirmed via direct read of BlitBitmapToPartyWindow to be exactly
# source's own multi-mon-list-row format, the correct match for this
# screen's own scrollable single-column list), replacing the text_window
# reuse this section originally shipped with. The original text_window
# note is kept below, struck through in spirit rather than deleted, since
# the REASONING it documents (why a 3rd attempt wasn't obviously safe) is
# still real project history worth keeping visible.
#
# [Original M25h-1.5 note, now superseded] Source's real Party screen has a
# genuine dedicated background/slot-frame graphic (`graphics/party_menu/
# bg.png`, `slot_main.bin`/`slot_wide.bin`) -- confirmed via direct source
# read to be raw GBA tilesets/tilemaps (INCGFX_U32 4bpp + separate binary
# tilemap data), the SAME class of asset M25h-1.4 already declined to
# reconstruct for the Bag screen's own `bag/menu.png` (and the same class
# Phase 5a already tried once and abandoned as disproportionate for battle
# backgrounds). This screen reuses the already-pulled, already-flat
# `text_window/1.png` panel art (h-1.1) instead, matching Item's own
# precedent exactly.
#
# [M25h-4, Part C] Held-item icons ARE now shown (`hold_icons.png`,
# confirmed a flat, simple 2-icon sheet -- item/mail -- not a raw tileset,
# unlike the frame art above) -- this project's first-ever held-item UI,
# reading `BattlePokemon.held_item` directly (already-populated real data,
# confirmed via direct grep, never displayed anywhere before now). This
# project has no Mail item concept (confirmed via grep), so the generic
# item icon (sheet index 0) is used unconditionally whenever held_item !=
# null, never the mail icon (index 1).
signal mon_chosen(slot: int)
signal cancelled()

# [Real source, strings.c:304] gText_ChoosePokemon -- see doc comment above
# for why this stays fixed regardless of voluntary-vs-forced context.
const _HEADER_TEXT := "Choose a POKéMON."

const _STATUS_ICON_DISPLAY_SIZE := Vector2(24, 8)

# [M25h-4, Part C] party_status_icons.png's own 8-row layout, each row
# 32x8px -- confirmed via direct read of UpdatePartyMonAilmentGfx
# (StartSpriteAnim(..., status - 1)) against the real AILMENT_* enum order
# (include/constants/party_menu.h): PSN=1, PRZ=2, SLP=3, FRZ=4, BRN=5,
# PKRS=6, FNT=7, FRB=8 -- so anim index (row) = AILMENT value - 1.
const _PARTY_STATUS_ICON_SIZE := Vector2(32, 8)
const _PARTY_STATUS_ROW_FNT := 6

# [M25h-4, Part A] The real decoded per-row slot art's own known pixel
# layout within its 144x24 native canvas (measured directly against
# party_slot_wide.png -- see this session's own report for the visual
# confirmation): the baked "HP" label sits at roughly x=[74,92], and the
# bar's own empty fill rectangle -- the region Part B's HP-fraction color
# tint overlays -- sits at roughly x=[94,134], y=[9,15].
const _SLOT_ART_SIZE := Vector2(144, 24)
const _SLOT_HP_FILL_RECT := Rect2(94, 9, 40, 6)

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

	# [M25h-4, Part A] Real decoded Party-screen frame art (gen_ui_frames.py,
	# from graphics/party_menu/bg.png+bg.bin), replacing text_window reuse.
	# party_frame.png is a fixed 240x192 composition (a rounded-corner olive
	# list panel), rendered the same STRETCH_SCALE way bag_frame.png is on
	# the Item screen -- see that screen's own _build() doc comment for the
	# shared precedent citation (M25e's stretch convention).
	var panel := Control.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.06
	panel.anchor_right = 0.48
	panel.anchor_bottom = 0.75
	add_child(panel)

	var frame_rect := TextureRect.new()
	frame_rect.texture = load("res://assets/sprites/battle_ui/screens/party_frame.png")
	frame_rect.anchor_right = 1.0
	frame_rect.anchor_bottom = 1.0
	frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame_rect)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
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


# [M25h-4, Part C] Maps a BattlePokemon to its real party_status_icons.png
# row, mirroring GetMonAilment's own real priority order (party_menu.c:2248)
# exactly: fainted beats status beats nothing. Pokerus (AILMENT_PKRS, row 5)
# has no equivalent concept anywhere in this project and is never returned.
# Static so it's directly unit-testable, matching this project's own
# established _status_icon_row precedent.
static func _party_status_icon_row(mon: BattlePokemon) -> int:
	if mon.fainted or mon.current_hp <= 0:
		return _PARTY_STATUS_ROW_FNT
	match mon.status:
		BattlePokemon.STATUS_POISON, BattlePokemon.STATUS_TOXIC:
			return 0
		BattlePokemon.STATUS_PARALYSIS:
			return 1
		BattlePokemon.STATUS_SLEEP:
			return 2
		BattlePokemon.STATUS_FREEZE:
			return 3
		BattlePokemon.STATUS_BURN:
			return 4
		_:
			return -1


# Builds one clickable party row: a real decoded slot-art background
# (party_slot_wide.png, M25h-4 Part A) with a chrome-stripped,
# cursor-group-eligible Button layered on top carrying the row's own text
# (name/level/HP fraction) -- Button.text drives cursor-group selection
# (_wire_cursor_group/_set_cursor_selected rewrite .text directly), so the
# background/overlay children, added separately as row siblings (not
# button children), are never touched by that rewrite. Godot draws sibling
# Controls in child order, so the background TextureRect is added FIRST
# (drawn first = appears behind) and the Button second (its own chrome is
# already fully transparent via _strip_button_chrome, so only its text
# shows, sitting naturally on top of the slot art).
func _build_mon_row(mon: BattlePokemon, slot: int) -> Dictionary:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 36)

	if _parent_bs != null:
		var slot_art := TextureRect.new()
		slot_art.texture = load("res://assets/sprites/battle_ui/screens/party_slot_wide.png")
		slot_art.anchor_left = 0.0
		slot_art.anchor_right = 0.85
		slot_art.anchor_top = 0.0
		slot_art.anchor_bottom = 1.0
		slot_art.stretch_mode = TextureRect.STRETCH_SCALE
		slot_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot_art)

		# [M25h-4, Part B] Real HP-fraction color as a tinted overlay
		# positioned over the slot art's own known bar-fill pixel region
		# (_SLOT_HP_FILL_RECT), reusing _hp_bar_color's existing threshold
		# logic -- see this session's own report for why this is a
		# disclosed EQUIVALENT to source's real mechanism (a narrow
		# palette-slot swap applied to the baked tile art,
		# DisplayPartyPokemonHPBar/party_menu.c:2726) rather than a literal
		# reproduction: Godot has no baked-tile-palette-bank concept, so a
		# semi-transparent color-tinted rectangle over the SAME pixel
		# region the real bar occupies is the direct equivalent available
		# here, not a simplification of a simplification.
		var hp_tint := ColorRect.new()
		hp_tint.color = _parent_bs._hp_bar_color(mon.current_hp, mon.max_hp)
		hp_tint.color.a = 0.85
		hp_tint.anchor_left = _SLOT_HP_FILL_RECT.position.x / _SLOT_ART_SIZE.x * 0.85
		hp_tint.anchor_right = (_SLOT_HP_FILL_RECT.position.x + _SLOT_HP_FILL_RECT.size.x) / _SLOT_ART_SIZE.x * 0.85
		hp_tint.anchor_top = _SLOT_HP_FILL_RECT.position.y / _SLOT_ART_SIZE.y
		hp_tint.anchor_bottom = (_SLOT_HP_FILL_RECT.position.y + _SLOT_HP_FILL_RECT.size.y) / _SLOT_ART_SIZE.y
		hp_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hp_tint)

	var btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
	var name_level: String = _parent_bs._name_level_text(mon) if _parent_bs != null else "%s Lv%d" % [mon.species.species_name, mon.level]
	btn.text = "%s   HP %d/%d" % [name_level, mon.current_hp, mon.max_hp]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.anchor_right = 0.85
	btn.anchor_bottom = 1.0
	btn.pressed.connect(_on_mon_button_pressed.bind(slot))
	row.add_child(btn)

	# [M25h-4, Part C] Real party-list status icon (distinct sheet from the
	# in-battle status.png, matching source's own real convention of using
	# a different icon style in this context -- see _party_status_icon_row's
	# own doc comment). Positioned in the space to the right of the slot
	# art itself (source's own status icon is a separate sprite layered
	# near the slot box, not baked into its tile art, so placing it outside
	# the decoded slot_wide.png bounds is source-accurate in spirit, not
	# just a layout convenience).
	if _parent_bs != null:
		var status_row := _party_status_icon_row(mon)
		if status_row >= 0:
			var status_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/party_status_icons.png")
			var status_atlas := AtlasTexture.new()
			status_atlas.atlas = status_sheet
			status_atlas.region = Rect2(0, status_row * _PARTY_STATUS_ICON_SIZE.y, _PARTY_STATUS_ICON_SIZE.x, _PARTY_STATUS_ICON_SIZE.y)
			var status_icon := TextureRect.new()
			status_icon.texture = status_atlas
			status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			status_icon.anchor_left = 0.87
			status_icon.anchor_right = 0.87
			status_icon.anchor_top = 0.5
			status_icon.anchor_bottom = 0.5
			status_icon.offset_left = 0
			status_icon.offset_top = -_STATUS_ICON_DISPLAY_SIZE.y / 2.0
			status_icon.offset_right = _STATUS_ICON_DISPLAY_SIZE.x
			status_icon.offset_bottom = _STATUS_ICON_DISPLAY_SIZE.y / 2.0
			status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(status_icon)

		# [M25h-4, Part C] This project's first-ever held-item UI display --
		# BattlePokemon.held_item is real, already-populated data (M12/M18's
		# own item system) that had simply never been shown in any screen
		# before now. No Mail concept exists anywhere in this project
		# (confirmed via grep), so the generic item icon (sheet index 0) is
		# the only one ever used.
		if mon.held_item != null:
			var hold_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/party_hold_icons.png")
			var hold_atlas := AtlasTexture.new()
			hold_atlas.atlas = hold_sheet
			hold_atlas.region = Rect2(0, 0, 8, 8)
			var hold_icon := TextureRect.new()
			hold_icon.texture = hold_atlas
			hold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			hold_icon.anchor_left = 0.96
			hold_icon.anchor_right = 0.96
			hold_icon.anchor_top = 0.5
			hold_icon.anchor_bottom = 0.5
			hold_icon.offset_left = 0
			hold_icon.offset_top = -8.0
			hold_icon.offset_right = 16.0
			hold_icon.offset_bottom = 8.0
			hold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(hold_icon)

	return {"container": row, "button": btn}


# [M25h-4, Part B] Real fainted-slot dimming, mirroring GetPartyBoxPalette
# Flags' own PARTY_PAL_FAINTED effect (party_menu.c) -- a whole-slot
# darkening, reproduced here as a modulate darken on the row's own real
# slot art. [Disclosed: no current call site] This screen's own row list
# (both _build() and the pre-existing _party_has_switch_candidate filter,
# unchanged since M25h-1.5) never includes a fainted party member as a
# row -- only live, non-active bench candidates are ever listed, matching
# this screen's own deliberate "candidates only" scope. Implemented here
# for correctness/reusability and because Part B's own task explicitly
# asked for the mechanism, but there is no fainted row in this project's
# actual UI today for it to visibly apply to.
static func _apply_fainted_dim(slot_art: TextureRect) -> void:
	slot_art.modulate = Color(0.55, 0.55, 0.55, 1.0)


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
