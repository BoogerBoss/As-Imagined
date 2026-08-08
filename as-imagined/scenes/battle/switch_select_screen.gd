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
# [M26E3-1] Real Emerald UI Pack art (Route B, decided docs/m26_e3_recon.md
# §0a) replaces M25h-4's own decoded-tilemap art. Real, format-DEPENDENT
# layout: singles = 1 large round "active" panel + 5 rect bench rows;
# doubles = 2 round panels + 4 rect rows -- confirmed via direct pixel-scan
# of the pack's own bg.PNG/bg_double.png mockups. **All six party slots are
# shown** (§0a decision 2).
#
# [M26E3-2] Real per-species mon icons, their real 2-frame idle animation,
# a real selection bounce, the real ball-icon cursor marker, real overlay_
# hp_back/overlay_hp HP-bar compositing, and the panel `_sel` state swap.
#
# [M26E3-3 "Full roster + legality + submenu"] Every one of the six slots
# (both active round panel(s) and every bench row, fainted or not) is now a
# REAL, clickable, cursor-selectable Button -- superseding E3-1's own "only
# a live bench mon is clickable" restriction. Clicking an illegal slot
# rejects with source's own real message (see `_rejection_message`'s own
# doc comment for the full TrySwitchInPokemon citation); clicking a LEGAL
# slot opens a real action submenu (Shift/Summary/Cancel, or Send Out/
# Summary/Cancel for a forced replacement — §0a decision 3, Summary stubbed
# disabled as M26E4's own future hook) rather than immediately emitting
# `mon_chosen`.
#
# [Real source finding -- default cursor position] `004_Party.rb`'s own
# `pbStartScene` sets `@activecmd = 0` and selects `@sprites["pokemon0"]` --
# the ACTIVE mon's own slot, not the first bench candidate. Confirmed via
# this session's own re-read, and reproduced here: the button order is now
# [active panel(s), in active_indices order] + [every bench row, in party
# order, fainted included] + [Cancel, if voluntary] -- so the default
# selected slot (cursor index 0) is genuinely the active mon's own panel,
# matching source, a deliberate change from E3-1/E3-2's own "first legal
# bench mon" default (which predated this slot's own becoming selectable at
# all).
#
# [Real source structural findings, reused directly rather than invented]
# - The real in-battle party screen (`OpenPartyMenuInBattle`) always shows
#   the SAME header message regardless of voluntary-vs-forced context --
#   `PARTY_MSG_CHOOSE_MON` = gText_ChoosePokemon = "Choose a POKéMON."
#   (strings.c:304) -- confirmed directly, NOT the "_OR_CANCEL" variant,
#   even for the voluntary case. This screen's own header stays fixed
#   regardless of _is_forced_replacement (except while flashing a real
#   rejection message -- see below).
# - Cancel behavior genuinely differs and was confirmed directly against
#   `HandleChooseMonCancel` (party_menu.c): for PARTY_ACTION_SEND_OUT and
#   PARTY_ACTION_CHOOSE_FAINTED_MON (the two forced-replacement actions),
#   pressing B plays a failure sound and does NOTHING -- no cancel path
#   exists at all. For PARTY_ACTION_SWITCH (voluntary), B triggers a real
#   cancel. Reproduced unchanged in `_unhandled_input` -- ESC backs the
#   ACTION SUBMENU out to the list if one is open (a real, always-available
#   step regardless of voluntary/forced, matching the submenu's own Cancel
#   button), and otherwise falls through to the existing top-level
#   voluntary-only cancel.
#
# [Layout constants -- Step 0, measured directly] See the individual
# constant doc comments below for each element's own real-source citation.
const _ROUND_PANEL_SIZE := Vector2(312, 196)
const _RECT_PANEL_SIZE := Vector2(576, 96)
const _ROUND_PANEL_POS := Vector2(36, 124)
const _ROUND_PANEL_2_POS := Vector2(36, 372)
const _RECT_PANEL_X := 444.0
const _RECT_PANEL_PITCH := 120.0
const _SINGLES_RECT_FIRST_Y := 60.0
const _DOUBLES_RECT_FIRST_Y := 100.0
const _CANCEL_SIZE := Vector2(224, 72)

# [Real screenshot verification, caught a real overflow bug, E3-1] A
# smaller explicit font-size override applied on top of `_style_menu_
# button`'s own 60px (sized for a short menu label, not this row's longer
# info string) -- kept an exact integer multiple of `_FONT_NORMAL_SIZE`.
const _ROW_FONT_SIZE := 30

# [M26E3-2] Real name/level/HP text shares its row with the real icon +
# ball graphics (both anchored at/near the row's own left edge) -- shifted
# right so the two don't overlap.
const _ROW_TEXT_LEFT_MARGIN := 100.0

signal mon_chosen(slot: int)
signal cancelled()

# [Real source, strings.c:304] gText_ChoosePokemon.
const _HEADER_TEXT := "Choose a POKéMON."

const _STATUS_ICON_DISPLAY_SIZE := Vector2(24, 8)

# [M25h-4, Part C] party_status_icons.png's own 8-row layout, each row
# 32x8px -- confirmed via direct read of UpdatePartyMonAilmentGfx
# (StartSpriteAnim(..., status - 1)) against the real AILMENT_* enum order
# (include/constants/party_menu.h): PSN=1, PRZ=2, SLP=3, FRZ=4, BRN=5,
# PKRS=6, FNT=7, FRB=8 -- so anim index (row) = AILMENT value - 1.
const _PARTY_STATUS_ICON_SIZE := Vector2(32, 8)
const _PARTY_STATUS_ROW_FNT := 6

# [M26E3-2 mon icon -- Step 0, 004_Party.rb's own refresh_pokemon_icon]
# CENTER-anchored: active x=self.x+20, y=self.y+38; bench x=self.x+8,
# y=self.y+26 -- both doubled. Display size likewise doubled.
const _ICON_CENTER_OFFSET_ACTIVE := Vector2(40, 76)
const _ICON_CENTER_OFFSET_BENCH := Vector2(16, 52)
const _ICON_DISPLAY_SIZE := Vector2(64, 64)

# [M26E3-2 ball cursor -- Step 0, 004_Party.rb's own refresh_ball_graphic]
# TOP-LEFT anchored: active x=self.x-16, y=self.y-12; bench x=self.x-20,
# y=self.y-4 -- both doubled.
const _BALL_OFFSET_ACTIVE := Vector2(-32, -24)
const _BALL_OFFSET_BENCH := Vector2(-40, -8)
const _BALL_DISPLAY_SIZE := Vector2(88, 112)

# [M26E3-2 HP-bar compositing -- Step 0] Trough (its own sprite) and zone
# fill (blitted at a different relative position, confirmed via pixel
# inspection to visually align) offsets, both doubled.
const _HP_TROUGH_OFFSET_ACTIVE := Vector2(36, 124)
const _HP_TROUGH_OFFSET_BENCH := Vector2(292, 28)
const _HP_TROUGH_SIZE := Vector2(276, 28)
const _HP_FILL_OFFSET_ACTIVE := Vector2(100, 128)
const _HP_FILL_OFFSET_BENCH := Vector2(356, 32)
const _HP_FILL_MAX_WIDTH := 192.0
const _HP_FILL_HEIGHT := 16.0

# [M26E3-2 icon animation -- see the E3-2 shipping note in docs/m26_e3_
# recon.md §0c for the real-source correction this reflects: a single real
# tier-0 cadence, not an HP-fraction-driven one.]
const _ICON_FRAME_SECONDS := 6.0 / 60.0

# [M26E3-2 selection bounce -- Step 0, party_menu.c's own
# SpriteCB_BouncePartyMonIcon / AnimateSelectedPartyIcon]
const _ICON_BOUNCE_UP := -6.0
const _ICON_BOUNCE_DOWN := 2.0
const _ICON_UNSELECTED_SHIFT := -8.0

const _PARTY_DIR := "res://assets/sprites/battle_ui/party/"

# [M26E3-3] How long a rejection message stays on the header before
# reverting to the real "Choose a POKéMON." prompt -- a feel value, not a
# ported constant (source's own `{PAUSE_UNTIL_PRESS}` waits for a real
# keypress; this project's established message-box convention elsewhere
# uses a timed auto-advance instead, matching that same precedent rather
# than requiring an extra click on a screen that already requires several).
const _MESSAGE_DISPLAY_SECONDS := 1.6

# [M26E3-3 action submenu -- §0a decision 3] Positioned bottom-right,
# verified via real screenshot (not measured from source -- 004_Party.rb's
# own submenu is a raw GBA window-template popup this project has no
# pixel-exact citation for; "bottom-right, grows upward" is the recon's own
# qualitative citation, reproduced as a fixed on-screen rect).
const _SUBMENU_BUTTON_SIZE := Vector2(220, 64)
const _SUBMENU_SPACING := 8.0
const _SUBMENU_POS := Vector2(760, 520)

# [Doubles-split roadmap, step 5] Deliberately UNTYPED -- see
# item_select_screen.gd's own identical field for the full rationale.
var _parent_bs = null
var _field_slot: int = 0
var _is_forced_replacement: bool = false

# [M26E3-2] Every mon icon on screen -- driven by one shared _process()
# timer so every icon animates in lockstep.
var _icon_entries: Array[Dictionary] = []
var _icon_elapsed: float = 0.0
var _icon_frame: int = 0

# [M26E3-3] EVERY slot (active + every bench row, legal or not) now
# participates in cursor-driven visual selection (ball sel/desel, panel
# `_sel` swap, icon bounce) -- index-aligned with `_slot_buttons` below,
# NOT a legal-only subset the way E3-2 shipped it (see this file's own
# header doc comment for the real source citation behind this widening).
var _mon_visual_entries: Array[Dictionary] = []

# [M26E3-3] Every real per-mon slot Button, in on-screen/cursor order
# (active panel(s) first, then every bench row) -- excludes Cancel, which
# has its own separate top-level cancel semantics. Used both for the
# shared cursor group and to disable/re-enable the whole list while the
# action submenu is open.
var _slot_buttons: Array[Button] = []
var _cancel_btn: Button = null

var _header: Label = null
var _message_revert_timer: float = -1.0

var _action_submenu: Control = null

# [M26E4-2] The Summary overlay this submenu opens, tracked so a second
# press (or a stray re-entry) can never stack a duplicate -- mirrors
# battle_screen_shared.gd's own established `_item_select_overlay`/
# `_switch_select_overlay` idempotency-guard convention.
var _summary_screen: SummaryScreen = null


func setup(parent_bs, field_slot: int, is_forced_replacement: bool) -> void:
	_parent_bs = parent_bs
	_field_slot = field_slot
	_is_forced_replacement = is_forced_replacement
	_build()


func _build() -> void:
	# [M26A1 / 3:2 Phase 3] Letterboxed at an honest integer 2x rather than
	# stretched to 3:2 — see `UiLetterbox`. This screen has only a root node
	# in its `.tscn` (everything below is built here), which is why the
	# letterbox is applied in code for all three screens rather than authored
	# into two trees and coded into a third.
	UiLetterbox.apply(self)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var is_doubles: bool = _parent_bs != null and _parent_bs._is_doubles()

	var bg := TextureRect.new()
	bg.texture = load(_PARTY_DIR + "party_bg_doubles.png") \
			if is_doubles else load(_PARTY_DIR + "party_bg_singles.png")
	# Fills the letterboxed panel exactly (1024x768 = 2x the art's own
	# 512x384), so STRETCH_SCALE here is a clean integer upscale rather than
	# the 2.34 x 2.08 distortion filling a 3:2 viewport would give.
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ⚠️ The letterbox bars must be OPAQUE. This screen is a CHILD OVERLAY
	# over a live battle, so a transparent bar shows the battle still running
	# either side of the panel — which reads as a rendering bug rather than a
	# letterbox. The other two screens already own a full-rect `Backdrop`
	# ColorRect; this one has none, so it gets one here, added BEFORE `bg` so
	# it draws behind it.
	var bars := ColorRect.new()
	bars.color = Color(0.05, 0.05, 0.05, 1.0)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLetterbox.expand_to_viewport(bars)
	add_child(bars)

	add_child(bg)

	_header = Label.new()
	_header.text = _HEADER_TEXT
	_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header.offset_left = 16
	_header.offset_top = 8
	_header.offset_bottom = 64
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _parent_bs != null:
		_header.add_theme_font_override("font", _parent_bs._font_menu)
		_header.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		_header.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_header.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		_header.add_theme_constant_override("shadow_offset_x", 1)
		_header.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_header)

	var party: BattleParty = _parent_bs._player_party
	var active: Array = party.active_indices

	# Active mon(s) -- now REAL, clickable slots (E3-3), matching source's
	# real behavior of accepting a click there and rejecting with "already
	# in battle!" (see _rejection_message). Built FIRST so the default
	# cursor position (index 0) lands here, matching pbStartScene's own
	# real default.
	var round_positions := [_ROUND_PANEL_POS, _ROUND_PANEL_2_POS]
	for i in range(active.size()):
		var mon: BattlePokemon = party.members[active[i]]
		var built := _build_slot(mon, active[i], round_positions[i], _ROUND_PANEL_SIZE, true)
		add_child(built.container)
		_slot_buttons.append(built.button)
		_mon_visual_entries.append(built.visual)

	# Bench -- every OTHER party member, in index order, one real rect row
	# each. All six slots are shown (§0a decision 2), fainted included.
	var first_y: float = _DOUBLES_RECT_FIRST_Y if is_doubles else _SINGLES_RECT_FIRST_Y
	var bench_row := 0
	for i in range(party.members.size()):
		if active.has(i):
			continue
		var mon: BattlePokemon = party.members[i]
		var pos := Vector2(_RECT_PANEL_X, first_y + bench_row * _RECT_PANEL_PITCH)
		var built := _build_slot(mon, i, pos, _RECT_PANEL_SIZE, false)
		add_child(built.container)
		_slot_buttons.append(built.button)
		_mon_visual_entries.append(built.visual)
		bench_row += 1

	if not _is_forced_replacement:
		var cancel_pos := Vector2(_RECT_PANEL_X + (_RECT_PANEL_SIZE.x - _CANCEL_SIZE.x) / 2.0,
				first_y + bench_row * _RECT_PANEL_PITCH + 12.0)
		_cancel_btn = Button.new()
		if _parent_bs != null:
			_parent_bs._style_menu_button(_cancel_btn)
			_parent_bs._strip_button_chrome(_cancel_btn)
		_cancel_btn.text = "Cancel"
		_cancel_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_cancel_btn.offset_left = cancel_pos.x
		_cancel_btn.offset_top = cancel_pos.y
		_cancel_btn.offset_right = cancel_pos.x + _CANCEL_SIZE.x
		_cancel_btn.offset_bottom = cancel_pos.y + _CANCEL_SIZE.y
		_cancel_btn.pressed.connect(_on_cancel_pressed)
		add_child(_cancel_btn)

	# [M26E3-3] Every slot participates in the shared cursor group now,
	# Cancel included -- _wire_cursor_group defaults to index 0, which is
	# the first active panel per the button-order change above.
	var all_buttons: Array[Button] = _slot_buttons.duplicate()
	if _cancel_btn != null:
		all_buttons.append(_cancel_btn)
	if _parent_bs != null:
		_parent_bs._wire_cursor_group(all_buttons)

	# [M26E3-3] Cursor-driven ball/panel-_sel/bounce state now covers every
	# slot -- wired AFTER _wire_cursor_group (which disconnects+reconnects
	# mouse_entered first), so this screen's own additional listener isn't
	# wiped by that call.
	for i in range(_slot_buttons.size()):
		_slot_buttons[i].pressed.connect(_on_slot_pressed.bind(_slot_buttons[i].get_meta("party_slot")))
		_slot_buttons[i].mouse_entered.connect(_set_mon_visual_selected.bind(i))
	if _cancel_btn != null:
		_cancel_btn.mouse_entered.connect(_clear_mon_visual_selection)
	_set_mon_visual_selected(0)


func _process(delta: float) -> void:
	if _message_revert_timer >= 0.0:
		_message_revert_timer -= delta
		if _message_revert_timer <= 0.0:
			_message_revert_timer = -1.0
			_header.text = _HEADER_TEXT

	if _icon_entries.is_empty():
		return
	_icon_elapsed += delta
	if _icon_elapsed < _ICON_FRAME_SECONDS:
		return
	_icon_elapsed -= _ICON_FRAME_SECONDS
	_icon_frame = 1 - _icon_frame
	for entry in _icon_entries:
		var rect: TextureRect = entry["rect"]
		var frames: Array = entry["frames"]
		rect.texture = frames[_icon_frame]
	_refresh_icon_positions()


# ── Legality gauntlet (M26E3-3) ────────────────────────────────────────────

# [Real source, party_menu.c:7526-7593 `TrySwitchInPokemon`, in its own
# exact real order] Two of source's checks are deliberately NOT reproduced,
# matching §0a decision 5's already-confirmed exclusions: the 6v6-multi-
# battle partner-party case (L7538-7543, no multi-battle support at all)
# and the egg check (L7561-7565, no egg concept anywhere in this project).
# Every remaining check is real:
#   1. Fainted (HP==0, L7544-7549) -> gText_PkmnHasNoEnergy.
#   2. Already active on this side (L7550-7560) -> gText_PkmnAlreadyInBattle.
#   3. [Doubles only] Already picked for the SIBLING active field slot this
#      same choosing round (L7566-7572, BattlersShareParty &&
#      prevSelectedPartySlot) -> gText_PkmnAlreadySelected.
#   4. The ACTIVE (outgoing) mon itself can't leave the field at all
#      (L7573-7584, gPartyMenu.action == ABILITY_PREVENTS/CANT_SWITCH) --
#      checked LAST and independent of which slot was picked, matching
#      source's own pre-set action flag never depending on the picked
#      replacement. Wired to this project's own established is_trapped()
#      seam (M17f), which by now also covers the move-based trapping
#      volatiles (M18.5f Bind/Wrap, M19f Mean Look family, D4 Ingrain/No
#      Retreat) -- exactly the "wire the two trap cases to the existing
#      is_trapped() seam" instruction from §5. `_find_trapping_opponent`
#      mirrors is_trapped()'s own tail loop to recover the real ability
#      holder for the ability-specific message (battle_message.c:74,
#      gText_PkmnsXPreventsSwitching) rather than widening is_trapped()'s
#      own return type, which has too many existing call sites to risk for
#      this one message's sake.
# All four real strings quoted verbatim from strings.c:249-254 (`{STR_VAR_1}`
# substituted here with the real display name), with `{PAUSE_UNTIL_PRESS}`
# dropped -- this screen's own established flash-then-auto-revert
# convention stands in for the real per-line acknowledgment source uses.
# Returns "" for a legal pick.
func _rejection_message(picked_slot: int) -> String:
	var party: BattleParty = _parent_bs._player_party
	var picked: BattlePokemon = party.members[picked_slot]
	var picked_name: String = _display_name(picked)

	if picked.fainted or picked.current_hp <= 0:
		return "%s has no energy left to battle!" % picked_name

	if party.active_indices.has(picked_slot):
		return "%s is already in battle!" % picked_name

	if party.active_indices.size() > 1 and _parent_bs != null and _parent_bs._bm != null:
		var sibling_field_slot: int = 1 - _field_slot
		var sibling_chosen: int = _parent_bs._bm._chosen_switch_slots[sibling_field_slot]
		if sibling_chosen == picked_slot:
			return "%s has already been selected." % picked_name

	var active_mon: BattlePokemon = party.get_active_at(_field_slot)
	var ng_active: bool = _parent_bs._bm._is_neutralizing_gas_active() \
			if _parent_bs != null and _parent_bs._bm != null else false
	var live_opponents: Array = _parent_bs._bm._get_live_opponents(active_mon) \
			if _parent_bs != null and _parent_bs._bm != null else []
	if AbilityManager.is_trapped(active_mon, live_opponents, ng_active):
		var trapper: BattlePokemon = _find_trapping_opponent(active_mon, live_opponents, ng_active)
		if trapper != null:
			var ability_id: int = AbilityManager.effective_ability_id(trapper, ng_active)
			var ability: AbilityData = load("res://data/abilities/ability_%04d.tres" % ability_id) as AbilityData
			var ability_name: String = ability.ability_name if ability != null else "?"
			return "%s is preventing switching out with its %s Ability!" % [_display_name(trapper), ability_name]
		return "%s can't be switched out!" % _display_name(active_mon)

	return ""


func _display_name(mon: BattlePokemon) -> String:
	return _parent_bs._name_text(mon) if _parent_bs != null else mon.species.species_name


# Mirrors AbilityManager.is_trapped()'s own tail loop exactly (Shadow Tag/
# Arena Trap/Magnet Pull) to recover which opponent is actually responsible,
# for the message only -- is_trapped() itself stays bool-only, deliberately
# not widened for this one message's sake (see _rejection_message's own doc
# comment).
static func _find_trapping_opponent(mon: BattlePokemon, live_opponents: Array, ng_active: bool) -> BattlePokemon:
	for opp: BattlePokemon in live_opponents:
		var opp_id: int = AbilityManager.effective_ability_id(opp, ng_active)
		if opp_id == AbilityManager.ABILITY_NONE:
			continue
		if opp_id == AbilityManager.ABILITY_SHADOW_TAG:
			if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_SHADOW_TAG:
				continue
			return opp
		if opp_id == AbilityManager.ABILITY_ARENA_TRAP and AbilityManager.is_grounded(mon, ng_active):
			return opp
		if opp_id == AbilityManager.ABILITY_MAGNET_PULL and TypeChart.TYPE_STEEL in mon.species.types:
			return opp
	return null


func _show_rejection_message(text: String) -> void:
	_header.text = text
	_message_revert_timer = _MESSAGE_DISPLAY_SECONDS


func _on_slot_pressed(party_slot: int) -> void:
	if _action_submenu != null:
		return
	var reason := _rejection_message(party_slot)
	if not reason.is_empty():
		_show_rejection_message(reason)
		return
	_show_action_submenu(party_slot)


# ── Action submenu (M26E3-3, §0a decision 3) ───────────────────────────────

# Shift/Summary/Cancel (voluntary) or Send Out/Summary/Cancel (forced) --
# Summary is a real, positioned, disabled button (M26E4's own future hook,
# per §0a decision 3's own "stub SUMMARY now" wording), not omitted.
func _show_action_submenu(picked_slot: int) -> void:
	_message_revert_timer = -1.0
	_header.text = _HEADER_TEXT
	_set_slot_buttons_disabled(true)

	var menu := Control.new()
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.position = _SUBMENU_POS
	menu.size = Vector2(_SUBMENU_BUTTON_SIZE.x,
			_SUBMENU_BUTTON_SIZE.y * 3 + _SUBMENU_SPACING * 2)

	var primary_text := "Send Out" if _is_forced_replacement else "Shift"
	var primary_btn := _make_submenu_button(primary_text, 0)
	primary_btn.pressed.connect(_on_submenu_primary_pressed.bind(picked_slot))

	# [M26E4-2] Summary is now a real, wired button -- E3-3's own stub
	# resolved. Opens a real SummaryScreen overlay over this whole screen
	# (the submenu is merely hidden, not destroyed, while it's up); on
	# close, the real return-path contract fires (docs/m26_e4_recon.md
	# §1.3): the submenu is torn down and a fresh one is opened for
	# whichever party slot Summary was last showing, not necessarily the
	# slot that was originally picked here.
	var summary_btn := _make_submenu_button("Summary", 1)
	summary_btn.pressed.connect(_on_submenu_summary_pressed.bind(picked_slot))

	var cancel_btn := _make_submenu_button("Cancel", 2)
	cancel_btn.pressed.connect(_on_submenu_cancel_pressed)

	menu.add_child(primary_btn)
	menu.add_child(summary_btn)
	menu.add_child(cancel_btn)
	add_child(menu)
	_action_submenu = menu

	var submenu_buttons: Array[Button] = [primary_btn, summary_btn, cancel_btn]
	if _parent_bs != null:
		_parent_bs._wire_cursor_group(submenu_buttons)


func _make_submenu_button(text: String, index: int) -> Button:
	var btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
	btn.text = text
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.position = Vector2(0, index * (_SUBMENU_BUTTON_SIZE.y + _SUBMENU_SPACING))
	btn.size = _SUBMENU_BUTTON_SIZE
	return btn


func _on_submenu_primary_pressed(picked_slot: int) -> void:
	_close_action_submenu()
	mon_chosen.emit(picked_slot)


func _on_submenu_cancel_pressed() -> void:
	_close_action_submenu()


# [M26E4-2] Opens SummaryScreen for the picked slot. The submenu is hidden
# (not destroyed) rather than closed outright -- there's no re-entrant state
# to preserve, but leaving it alive avoids re-enabling/re-disabling the whole
# slot-button list a second time for what is, from the player's perspective,
# a single continuous "I'm looking at my roster" excursion.
func _on_submenu_summary_pressed(picked_slot: int) -> void:
	if _summary_screen != null and is_instance_valid(_summary_screen):
		return
	if _action_submenu != null:
		_action_submenu.visible = false

	var scene: PackedScene = load("res://scenes/battle/summary_screen.tscn")
	var overlay: SummaryScreen = scene.instantiate()
	add_child(overlay)
	overlay.closed.connect(_on_summary_screen_closed)
	overlay.setup(_parent_bs, _parent_bs._player_party, picked_slot)
	_summary_screen = overlay


# [M26E4-2, real return-path contract -- docs/m26_e4_recon.md §1.3] "the
# party menu reopens directly into the action submenu" for whichever slot
# Summary was LAST showing (gLastViewedMonIndex), not necessarily the slot
# that opened it -- Up/Down inside Summary may have moved on to a different
# party member entirely.
func _on_summary_screen_closed(last_viewed_slot: int) -> void:
	if _summary_screen != null and is_instance_valid(_summary_screen):
		_summary_screen.queue_free()
	_summary_screen = null
	_close_action_submenu()
	_show_action_submenu(last_viewed_slot)


func _close_action_submenu() -> void:
	if _action_submenu != null and is_instance_valid(_action_submenu):
		_action_submenu.queue_free()
	_action_submenu = null
	_set_slot_buttons_disabled(false)


func _set_slot_buttons_disabled(value: bool) -> void:
	for btn in _slot_buttons:
		btn.disabled = value
	if _cancel_btn != null:
		_cancel_btn.disabled = value


# ── Per-slot construction (M25h-4 / M26E3-1 / M26E3-2 / M26E3-3) ──────────

# [M25h-4, Part C] Maps a BattlePokemon to its real party_status_icons.png
# row, mirroring GetMonAilment's own real priority order (party_menu.c:2248)
# exactly: fainted beats status beats nothing. Pokerus (AILMENT_PKRS, row 5)
# has no equivalent concept anywhere in this project and is never returned.
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


func _add_mon_icon(slot: Control, mon: BattlePokemon, center_offset: Vector2, unselected_shift: Vector2) -> Dictionary:
	var dex: int = mon.species.national_dex_num
	var frame0: Texture2D = SpriteRegistry.get_icon(dex, 0)
	var frame1: Texture2D = SpriteRegistry.get_icon(dex, 1)

	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_pos := Vector2(center_offset.x - _ICON_DISPLAY_SIZE.x / 2.0,
			center_offset.y - _ICON_DISPLAY_SIZE.y / 2.0)
	wrap.position = base_pos
	wrap.size = _ICON_DISPLAY_SIZE
	slot.add_child(wrap)

	var icon := TextureRect.new()
	icon.texture = frame0
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(icon)

	var entry := {
		"rect": icon,
		"frames": [frame0, frame1 if frame1 != null else frame0],
		"wrap": wrap,
		"base_pos": base_pos,
		"unselected_shift": unselected_shift,
		"selected": false,
	}
	_icon_entries.append(entry)
	return entry


func _add_ball_icon(slot: Control, offset: Vector2) -> TextureRect:
	var ball := TextureRect.new()
	ball.texture = load(_PARTY_DIR + "party_ball_icon.png")
	ball.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ball.offset_left = offset.x
	ball.offset_top = offset.y
	ball.offset_right = offset.x + _BALL_DISPLAY_SIZE.x
	ball.offset_bottom = offset.y + _BALL_DISPLAY_SIZE.y
	ball.stretch_mode = TextureRect.STRETCH_SCALE
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ball)
	return ball


func _add_hp_bar(slot: Control, mon: BattlePokemon, is_active: bool) -> void:
	var trough_offset: Vector2 = _HP_TROUGH_OFFSET_ACTIVE if is_active else _HP_TROUGH_OFFSET_BENCH
	var trough_name := "party_hp_trough_faint.png" if mon.fainted else "party_hp_trough.png"
	var trough := TextureRect.new()
	trough.texture = load(_PARTY_DIR + trough_name)
	trough.set_anchors_preset(Control.PRESET_TOP_LEFT)
	trough.offset_left = trough_offset.x
	trough.offset_top = trough_offset.y
	trough.offset_right = trough_offset.x + _HP_TROUGH_SIZE.x
	trough.offset_bottom = trough_offset.y + _HP_TROUGH_SIZE.y
	trough.stretch_mode = TextureRect.STRETCH_SCALE
	trough.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(trough)

	if mon.fainted or mon.current_hp <= 0 or mon.max_hp <= 0:
		return

	var fill_offset: Vector2 = _HP_FILL_OFFSET_ACTIVE if is_active else _HP_FILL_OFFSET_BENCH
	var frac: float = clampf(float(mon.current_hp) / float(mon.max_hp), 0.0, 1.0)
	var zone := 0
	if frac <= 0.2:
		zone = 2
	elif frac <= 0.5:
		zone = 1

	var native_w: float = frac * (_HP_FILL_MAX_WIDTH / 2.0)
	if native_w < 1.0:
		native_w = 1.0
	native_w = roundf(native_w / 2.0) * 2.0
	var fill_width: float = native_w * 2.0

	var zone_sheet: Texture2D = load(_PARTY_DIR + "party_hp_zones.png")
	var fill_atlas := AtlasTexture.new()
	fill_atlas.atlas = zone_sheet
	fill_atlas.region = Rect2(0, zone * 8, native_w, 8)
	var fill := TextureRect.new()
	fill.texture = fill_atlas
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fill.offset_left = fill_offset.x
	fill.offset_top = fill_offset.y
	fill.offset_right = fill_offset.x + fill_width
	fill.offset_bottom = fill_offset.y + _HP_FILL_HEIGHT
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(fill)


# [M26E3-3] Unified slot builder -- replaces E3-1/E3-2's separate
# _build_active_panel (Label-only)/_build_bench_row (Button-only-if-legal)
# pair. Every slot (active round panel or bench rect row) is now built
# identically: real panel art (base/faint, swapping to its own real
# `_sel`/`faint_sel` variant on cursor selection), the real icon/ball/HP-bar
# compositing (M26E3-2, unchanged), and a real chrome-stripped Button
# wrapping the whole slot -- clicking it always runs through
# `_on_slot_pressed`, which decides accept-vs-reject via `_rejection_
# message`. `is_round` picks the round-vs-rect asset family (both now have
# real faint/faint_sel/sel variants pulled since E3-1).
func _build_slot(mon: BattlePokemon, party_slot: int, pos: Vector2, size: Vector2, is_round: bool) -> Dictionary:
	var slot := Control.new()
	slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	slot.offset_left = pos.x
	slot.offset_top = pos.y
	slot.offset_right = pos.x + size.x
	slot.offset_bottom = pos.y + size.y

	var stem: String = "panel_round" if is_round else "panel_rect"
	var state: String = "_faint" if mon.fainted else ""
	var base_path: String = _PARTY_DIR + stem + state + "_base.png" if not mon.fainted \
			else _PARTY_DIR + stem + state + ".png"
	var sel_path: String = _PARTY_DIR + stem + state + "_sel.png"

	var art := TextureRect.new()
	art.texture = load(base_path)
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(art)
	art.set_meta("base_path", base_path)
	art.set_meta("sel_path", sel_path)

	var ball := _add_ball_icon(slot, _BALL_OFFSET_ACTIVE if is_round else _BALL_OFFSET_BENCH)
	var icon_entry := _add_mon_icon(slot, mon,
			_ICON_CENTER_OFFSET_ACTIVE if is_round else _ICON_CENTER_OFFSET_BENCH,
			Vector2(0, _ICON_UNSELECTED_SHIFT) if is_round else Vector2(_ICON_UNSELECTED_SHIFT, 0))
	_add_hp_bar(slot, mon, is_round)

	var btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
		btn.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	var row_style := StyleBoxEmpty.new()
	row_style.content_margin_left = _ROW_TEXT_LEFT_MARGIN
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		btn.add_theme_stylebox_override(st, row_style)
	btn.text = _mon_info_text(mon)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# [Button has no vertical_alignment property, unlike Label] Autowrap on
	# the round panel keeps its own combined name+level+HP string legible
	# within the panel's shorter width; bench rows keep the established
	# single-line convention (their own wider rect panel already fits it).
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if is_round else TextServer.AUTOWRAP_OFF
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.set_meta("party_slot", party_slot)
	slot.add_child(btn)

	_add_slot_overlays(slot, mon)

	var visual := {"icon": icon_entry, "ball": ball, "panel_art": art}
	return {"container": slot, "button": btn, "visual": visual}


# ── Cursor-driven visual state (M26E3-2, widened M26E3-3 to cover every
# slot rather than only the legal bench subset) ────────────────────────────

func _set_mon_visual_selected(index: int) -> void:
	for i in range(_mon_visual_entries.size()):
		var entry: Dictionary = _mon_visual_entries[i]
		var is_selected: bool = i == index
		var icon_entry: Dictionary = entry["icon"]
		icon_entry["selected"] = is_selected

		var ball: TextureRect = entry["ball"]
		ball.texture = load(_PARTY_DIR + ("party_ball_icon_sel.png" if is_selected else "party_ball_icon.png"))

		var panel_art: TextureRect = entry["panel_art"]
		var path: String = panel_art.get_meta("sel_path") if is_selected else panel_art.get_meta("base_path")
		panel_art.texture = load(path)
	_refresh_icon_positions()


func _clear_mon_visual_selection() -> void:
	_set_mon_visual_selected(-1)


func _refresh_icon_positions() -> void:
	for entry in _icon_entries:
		var wrap: Control = entry["wrap"]
		var base_pos: Vector2 = entry["base_pos"]
		if entry["selected"]:
			var bounce_y: float = _ICON_BOUNCE_UP if _icon_frame == 1 else _ICON_BOUNCE_DOWN
			wrap.position = base_pos + Vector2(0, bounce_y)
		else:
			wrap.position = base_pos + entry["unselected_shift"]


# [M25h-4, Part B] Real fainted-slot dimming, mirroring GetPartyBoxPalette
# Flags' own PARTY_PAL_FAINTED effect. [Superseded by M26E3-1] The real
# `panel_*_faint.png` pack states now render this directly -- kept only as
# a fallback for any future bare-panel-art context that hasn't got a
# dedicated faint pack file of its own.
static func _apply_fainted_dim(slot_art: TextureRect) -> void:
	slot_art.modulate = Color(0.55, 0.55, 0.55, 1.0)


func _on_cancel_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).keycode == KEY_ESCAPE):
		return
	# [M26E4-2] While Summary is open (a real child overlay of this screen,
	# hiding rather than destroying the submenu underneath -- see
	# _on_submenu_summary_pressed), ESC belongs to IT alone: SummaryScreen's
	# own _unhandled_input already consumes the key and closes itself via the
	# real return-path contract. This guard makes this screen's own ESC
	# handling below a genuine no-op for that entire window regardless of
	# which node's _unhandled_input Godot happens to dispatch to first --
	# without it, a hidden-but-still-alive `_action_submenu` could be torn
	# down by this screen's own handler on the same keypress that closes
	# Summary, racing the real _on_summary_screen_closed rebuild.
	if _summary_screen != null and is_instance_valid(_summary_screen):
		return
	# [M26E3-3] ESC backs the action submenu out to the list first, if one
	# is open -- a real, always-available step regardless of voluntary/
	# forced, matching the submenu's own Cancel button.
	if _action_submenu != null:
		get_viewport().set_input_as_handled()
		_on_submenu_cancel_pressed()
		return
	# [Real source parity] ESC mirrors B_BUTTON -- but B_BUTTON is a genuine
	# no-op during a forced replacement (HandleChooseMonCancel's
	# PARTY_ACTION_SEND_OUT/PARTY_ACTION_CHOOSE_FAINTED_MON branch plays only
	# a failure sound, never cancels), so this handler is deliberately inert
	# in that case rather than emitting `cancelled` anyway.
	if _is_forced_replacement:
		return
	get_viewport().set_input_as_handled()
	_on_cancel_pressed()
