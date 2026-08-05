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
# [M26E3-1 REWRITE] Real Emerald UI Pack art (Route B, decided
# docs/m26_e3_recon.md §0a) replaces M25h-4's own decoded-tilemap art
# (party_frame.png/party_slot_wide.png, which stay on disk but are no
# longer consumed here) and the old single-flat-row-list layout. Real,
# format-DEPENDENT layout now: singles = 1 large round "active" panel +
# 5 rect bench rows; doubles = 2 round panels + 4 rect rows -- a genuinely
# different shape, not a reflow, confirmed via direct pixel-scan of the
# pack's own bg.PNG/bg_double.png mockups (see the layout constants below
# for the exact measured coordinates). **All six party slots are now shown**
# (§0a decision 2) -- active and fainted members included, each in the
# correct real panel STATE (base/faint) -- superseding the old behavior of
# filtering them out of the list entirely.
#
# [Scope boundary, disclosed] This is E3-1's own "static layout" scope,
# not the full E3 arc:
#   - The active round panel(s) and any FAINTED bench row are rendered as
#     PURE VISUALS (no Button, not in the cursor group) -- clicking an
#     illegal slot and seeing source's own real rejection message
#     ("is already in battle!", "has no energy left to battle!", etc.) is
#     E3-3's job, not built yet. Only a live, non-active, non-fainted bench
#     mon is a real clickable row, exactly matching this screen's own
#     pre-existing selectable-candidate scope.
#   - Mon icons (32x64, HP-tier animation cadence, selection bounce), the
#     ball-open cursor marker, the real overlay_hp_back/overlay_hp HP-bar
#     compositing, and the panel _sel state swap on cursor movement are ALL
#     explicitly E3-2 ("Dynamics") scope, per the recon's own phasing table
#     -- this screen keeps its existing plain-text name/level/HP display
#     and the existing "▶"-prefix cursor convention (M25h-1.3) for now,
#     rather than inventing approximate pixel offsets for a composite this
#     project doesn't have real 004_Party.rb text/HP-bar coordinates for
#     yet.
#   - Status icon + held-item icon (M25h-4 Part C) are kept UNCHANGED --
#     both are already real, already-tested, purely static per-row
#     displays, so carrying them over is continuity, not new E3-2 work.
#   - The action submenu (SHIFT/SUMMARY/CANCEL) is E3-3 scope; picking a
#     legal mon still emits `mon_chosen` directly, exactly as before.
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
#   assets from Phase 4b (status.png's 6-row status icon sheet via the
#   party-specific party_status_icons.png, M25h-4 Part C), not a new asset
#   pull.
#
# [Layout constants -- Step 0, measured directly] The pack's own
# 004_Party.rb assembly recipe gives singles coordinates directly (panel_
# round.png at (18,62); panel_rect.png at (222, 30/90/150/210/270), 60px
# pitch) -- but the doubles half is NOT in that Ruby file (its own doubles-
# bg-selection logic lives in base Essentials, absent from this pack), so
# those coordinates come from a direct border-color pixel scan of bg_
# double.png instead (this session's own measurement, cross-checked against
# the singles scan using the identical method, confirmed internally
# consistent: same rect-column x/width, same 60px row pitch, a clean 124px
# round-panel-to-round-panel pitch = 98px panel height + 26px gap). All
# values below are the native 512x384 pack-canvas coordinates doubled to
# this project's own 1024x768 base canvas (M26A1) -- a clean 2x, matching
# how bg.PNG/bg_double.png themselves are exactly half that canvas.
const _ROUND_PANEL_SIZE := Vector2(312, 196)
const _RECT_PANEL_SIZE := Vector2(576, 96)
const _ROUND_PANEL_POS := Vector2(36, 124)
const _ROUND_PANEL_2_POS := Vector2(36, 372)
const _RECT_PANEL_X := 444.0
const _RECT_PANEL_PITCH := 120.0
const _SINGLES_RECT_FIRST_Y := 60.0
const _DOUBLES_RECT_FIRST_Y := 100.0
const _CANCEL_SIZE := Vector2(224, 72)

# [Real screenshot verification, caught a real overflow bug] `_style_menu_
# button`'s own font_size (`_MENU_BUTTON_FONT_SIZE`, 4x `_FONT_NORMAL_SIZE`
# = 60) was sized for SHORT menu labels ("Fight"/"Cancel"/a move name) --
# applying it unmodified to a full "Name♂ Lv50   HP 999/999"-shaped row
# string overflowed well past the real rect panel's own 576px width (and
# the round panel's narrower 312px), confirmed via a real non-headless
# screenshot. `_ROW_FONT_SIZE` is a SMALLER explicit override applied on
# top of `_style_menu_button`'s own call, kept an exact integer multiple of
# `_FONT_NORMAL_SIZE` (2x, matching the standing invariant recorded at that
# constant's own declaration -- a non-multiple would visibly smear this
# extracted bitmap font).
const _ROW_FONT_SIZE := 30

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

# [Doubles-split roadmap, step 5] Deliberately UNTYPED -- see
# item_select_screen.gd's own identical field for the full rationale
# (BattleScreenShared is an unrelated class exposing the same duck-typed
# interface, not a BattleScreen subclass, and even a looser `Control` type
# would still fail GDScript's static member-access checking for the custom
# fields/methods this overlay calls).
var _parent_bs = null
var _field_slot: int = 0
var _is_forced_replacement: bool = false


func setup(parent_bs, field_slot: int, is_forced_replacement: bool) -> void:
	_parent_bs = parent_bs
	_field_slot = field_slot
	_is_forced_replacement = is_forced_replacement
	_build()


func _build() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var is_doubles: bool = _parent_bs != null and _parent_bs._is_doubles()

	var bg := TextureRect.new()
	bg.texture = load("res://assets/sprites/battle_ui/party/party_bg_doubles.png") \
			if is_doubles else load("res://assets/sprites/battle_ui/party/party_bg_singles.png")
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var header := Label.new()
	header.text = _HEADER_TEXT
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 16
	header.offset_top = 8
	header.offset_bottom = 40
	if _parent_bs != null:
		header.add_theme_font_override("font", _parent_bs._font_menu)
		header.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		header.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		header.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		header.add_theme_constant_override("shadow_offset_x", 1)
		header.add_theme_constant_override("shadow_offset_y", 1)
	add_child(header)

	var party: BattleParty = _parent_bs._player_party
	var active: Array = party.active_indices

	# Active mon(s) -- real round panel(s), pure visual (no Button; picking
	# one is always illegal and its real rejection text is E3-3's job).
	var round_positions := [_ROUND_PANEL_POS, _ROUND_PANEL_2_POS]
	for i in range(active.size()):
		var mon: BattlePokemon = party.members[active[i]]
		add_child(_build_active_panel(mon, round_positions[i]))

	# Bench -- every OTHER party member, in index order, one real rect row
	# each. All six slots are shown (§0a decision 2): a fainted bench mon
	# still gets a row, in the real "faint" panel state, just with no
	# Button (illegal pick, real rejection text is E3-3's job).
	var first_y: float = _DOUBLES_RECT_FIRST_Y if is_doubles else _SINGLES_RECT_FIRST_Y
	var buttons: Array[Button] = []
	var bench_row := 0
	for i in range(party.members.size()):
		if active.has(i):
			continue
		var mon: BattlePokemon = party.members[i]
		var pos := Vector2(_RECT_PANEL_X, first_y + bench_row * _RECT_PANEL_PITCH)
		var built := _build_bench_row(mon, i, pos)
		add_child(built.container)
		if built.button != null:
			buttons.append(built.button)
		bench_row += 1

	if not _is_forced_replacement:
		var cancel_pos := Vector2(_RECT_PANEL_X + (_RECT_PANEL_SIZE.x - _CANCEL_SIZE.x) / 2.0,
				first_y + bench_row * _RECT_PANEL_PITCH + 12.0)
		var cancel_btn := Button.new()
		if _parent_bs != null:
			_parent_bs._style_menu_button(cancel_btn)
			_parent_bs._strip_button_chrome(cancel_btn)
		cancel_btn.text = "Cancel"
		cancel_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cancel_btn.offset_left = cancel_pos.x
		cancel_btn.offset_top = cancel_pos.y
		cancel_btn.offset_right = cancel_pos.x + _CANCEL_SIZE.x
		cancel_btn.offset_bottom = cancel_pos.y + _CANCEL_SIZE.y
		cancel_btn.pressed.connect(_on_cancel_pressed)
		add_child(cancel_btn)
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


func _mon_info_text(mon: BattlePokemon) -> String:
	var name_level: String = ("%s%s %s" % [_parent_bs._name_text(mon),
			_parent_bs._gender_glyph(mon.gender), _parent_bs._level_text(mon)]) \
			if _parent_bs != null else "%s Lv%d" % [mon.species.species_name, mon.level]
	return "%s   HP %d/%d" % [name_level, mon.current_hp, mon.max_hp]


# Adds the status-icon + held-item-icon overlays a slot Control needs,
# anchored to that Control's own top-right corner -- shared by both the
# active round panel and the bench rect rows so the two don't duplicate
# this logic (M25h-4, Part C; unchanged behavior, just factored out of the
# old single _build_mon_row).
func _add_slot_overlays(slot: Control, mon: BattlePokemon) -> void:
	var status_row := _party_status_icon_row(mon)
	if status_row >= 0:
		var status_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/party_status_icons.png")
		var status_atlas := AtlasTexture.new()
		status_atlas.atlas = status_sheet
		status_atlas.region = Rect2(0, status_row * _PARTY_STATUS_ICON_SIZE.y, _PARTY_STATUS_ICON_SIZE.x, _PARTY_STATUS_ICON_SIZE.y)
		var status_icon := TextureRect.new()
		status_icon.texture = status_atlas
		status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		status_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		status_icon.offset_left = -_STATUS_ICON_DISPLAY_SIZE.x - 28
		status_icon.offset_top = 10
		status_icon.offset_right = -28
		status_icon.offset_bottom = 10 + _STATUS_ICON_DISPLAY_SIZE.y
		status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(status_icon)

	if mon.held_item != null:
		var hold_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/party_hold_icons.png")
		var hold_atlas := AtlasTexture.new()
		hold_atlas.atlas = hold_sheet
		hold_atlas.region = Rect2(0, 0, 8, 8)
		var hold_icon := TextureRect.new()
		hold_icon.texture = hold_atlas
		hold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hold_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		hold_icon.offset_left = -24
		hold_icon.offset_top = 8
		hold_icon.offset_right = -8
		hold_icon.offset_bottom = 24
		hold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(hold_icon)


# The active mon's own large round panel -- real panel art (base/faint),
# pure visual, no Button (see this file's own scope-boundary doc comment).
func _build_active_panel(mon: BattlePokemon, pos: Vector2) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = pos.x
	panel.offset_top = pos.y
	panel.offset_right = pos.x + _ROUND_PANEL_SIZE.x
	panel.offset_bottom = pos.y + _ROUND_PANEL_SIZE.y

	var art := TextureRect.new()
	var art_name := "panel_round_faint.png" if mon.fainted else "panel_round_base.png"
	art.texture = load("res://assets/sprites/battle_ui/party/%s" % art_name)
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)

	var label := Label.new()
	label.text = _mon_info_text(mon)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 16
	label.offset_top = 16
	label.offset_right = -16
	label.offset_bottom = -16
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _parent_bs != null:
		label.add_theme_font_override("font", _parent_bs._font_menu)
		label.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
		label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 1))
	panel.add_child(label)

	_add_slot_overlays(panel, mon)
	return panel


# One clickable (if legal) bench row: real rect panel art (base/faint) with
# a chrome-stripped Button carrying the row's own text layered on top, only
# added to the cursor group when the mon is a real legal candidate (not
# fainted -- and never the active mon, since bench rows by construction
# exclude every index in `active`).
func _build_bench_row(mon: BattlePokemon, slot: int, pos: Vector2) -> Dictionary:
	var row := Control.new()
	row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	row.offset_left = pos.x
	row.offset_top = pos.y
	row.offset_right = pos.x + _RECT_PANEL_SIZE.x
	row.offset_bottom = pos.y + _RECT_PANEL_SIZE.y

	var art := TextureRect.new()
	var art_name := "panel_rect_faint.png" if mon.fainted else "panel_rect_base.png"
	art.texture = load("res://assets/sprites/battle_ui/party/%s" % art_name)
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)

	var btn: Button = null
	if mon.fainted:
		# Illegal pick -- shown, not clickable. Real rejection text
		# ("has no energy left to battle!") is E3-3's job; a plain Label
		# still shows the row's own info so the slot doesn't read as blank.
		var label := Label.new()
		label.text = _mon_info_text(mon)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 16
		label.offset_right = -16
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if _parent_bs != null:
			label.add_theme_font_override("font", _parent_bs._font_menu)
			label.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
			label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
		row.add_child(label)
	else:
		btn = Button.new()
		if _parent_bs != null:
			_parent_bs._style_menu_button(btn)
			_parent_bs._strip_button_chrome(btn)
			# [Overflow fix, see _ROW_FONT_SIZE's own doc comment] Shrunk
			# back down from _style_menu_button's own 60px (sized for a
			# short menu label, not this row's longer info string).
			btn.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
		btn.text = _mon_info_text(mon)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.anchor_right = 1.0
		btn.anchor_bottom = 1.0
		btn.pressed.connect(_on_mon_button_pressed.bind(slot))
		row.add_child(btn)

	_add_slot_overlays(row, mon)
	return {"container": row, "button": btn}


# [M25h-4, Part B] Real fainted-slot dimming, mirroring GetPartyBoxPalette
# Flags' own PARTY_PAL_FAINTED effect (party_menu.c) -- a whole-slot
# darkening. [Superseded by M26E3-1] The real `panel_round_faint.png`/
# `panel_rect_faint.png` pack states now render this directly, so the
# modulate-darken equivalent this function provided is no longer needed --
# kept only as a fallback for any future bare-panel-art context that hasn't
# got a dedicated faint pack file of its own.
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
