extends Control
class_name MatchupOverlay

# [M26E5-1] The matchup overlay's skeleton: backdrop, panel, header, field
# strip, and open/close wiring. A CUSTOM EXPANSION screen, not a source port
# -- source never displays any of this numerically outside its own debug
# menu (docs/m26_e5_recon.md §2.4). Scope of record for the full design:
# docs/m26_e5_recon.md. Six decisions resolved by Rob 2026-08-04 (this
# file's own doc comments cite each where it matters):
#   1. Trigger: an always-visible INFO tab + TAB key (see the trigger
#      button's own wiring in battle_screen_shared.gd, near _build_top_menu).
#   2. Availability: command phase only for this first cut.
#   3. Field-strip breadth: weather/Trick Room/Tailwind PLUS screens
#      (Reflect/Light Screen/Aurora Veil/Safeguard/Mist) and hazards
#      (Spikes/Toxic Spikes/Stealth Rock/Sticky Web) -- same read, same
#      player-bookkeeping burden the brief exists to remove.
#   4. Accuracy/evasion: not in this phase's own scope (E5-1 has no stat-
#      stage table at all yet -- see below).
#   5. Opponent HP: omitted (not in this phase's own scope either).
#   6. Type-effectiveness hints: deferred past this whole arc.
#
# [Architecture, same deviation ItemSelectScreen/SwitchSelectScreen already
# established and disclosed] A full-viewport CHILD overlay added on top of
# the still-alive battle_screen instance -- BattleManager is a scene-tree
# CHILD NODE that must survive the round trip, so a literal scene swap would
# destroy the in-progress battle just to show a dashboard. See
# item_select_screen.gd's own doc comment for the full rationale, unchanged
# here. Unlike Item/Switch (which REPLACE the command menu, matching
# source's own real screen-swap architecture), this overlay is explicitly a
# PULL-UP over the live battle screen (Rob's brief, §1) -- the backdrop is
# translucent (Color(0,0,0,0.85), the SAME alpha the F3 debug overlay
# already established as this project's own precedent for "a dashboard
# layered over the battle, not a screen that replaces it" -- see
# docs/m26_e5_recon.md §4), not the fully-opaque backdrop Item/Switch use.
#
# [Deliberately NOT built in E5-1, per the recon's own phasing (§6)] Player
# panel (name/HP/type/item/ability/moves), opponent panel (name/type/stat
# stages), and the stat-stage table itself are ALL E5-2's job -- this phase
# ships the skeleton + trigger + field strip only. The type-badge mapping
# helper (_type_badge_stem/_type_badge_texture, battle_screen_shared.gd) is
# built and tested this phase too (closing the real C5 gap: "type-id ->
# badge-filename mapping doesn't exist"), but has no visual consumer inside
# THIS overlay yet -- that's E5-2's player/opponent panels' job.
#
# [M26E5-2] Player/opponent panels shipped, singles-only at ship time
# (doubles layout landed in E5-3 -- see _build_mon_columns's own doc
# comment -- by reading `_player_party`/`_opp_party` and iterating
# `num_active()` field slots instead of the two singles-only
# get_active_player_mon/get_active_opponent_mon getters this comment
# originally cited). Player panel per §5.2: name, HP cur/max, type badges, held item
# name, ability name + its populated description (AbilityData.description IS
# populated, unlike MoveData.description -- confirmed directly, this is why
# the ability line can show real flavor text today while every move row
# below it cannot), stat-stage table, and all 4 move rows (name, type badge,
# category icon -- MoveData.category's own doc comment explains the C4
# wire-up -- PP, power/accuracy, secondary-effect chance as an explicit %,
# contact flag). Move descriptions are OMITTED, not blanked -- E4-1 hasn't
# landed, so there is nothing to show yet; adding an empty description line
# would read as a bug rather than an honest "not built yet". Opponent panel
# per §5.4: name, type badges, stat-stage table ONLY -- no HP/item/ability/
# moves, matching the brief's own information-asymmetry rule (§2.4: this
# overlay removes bookkeeping, not information the base game never gives the
# player). Stat-stage table always shows all 7 rows (Atk/Def/SpA/SpD/Spe +
# Acc/Eva) regardless of whether a stage is 0 -- deliberately NOT the field
# strip's own "only show what's active" convention, since a table is
# expected to be complete and a player scanning for "is anything off neutral
# here" benefits from a stable row count more than from omitting zeroes.
# Acc/Eva show the raw stage only (decision 4, _stage_text), never a
# multiplier -- StatusManager.ACCURACY_STAGE_RATIOS is indexed by the
# COMBINED attacker-minus-target stage, so a single mon's own accuracy stage
# has no standalone multiplier to show truthfully.
signal closed()

# [Deliberately untyped -- see item_select_screen.gd's own identical field
# for why: a strict BattleScreenShared type would work, but this overlay
# only ever calls a few duck-typed methods/fields on it
# (_bm/_action_panel_menu_style/_font_menu/_style_menu_button/
# _strip_button_chrome), and leaving it untyped avoids coupling this file to
# that one class for no real benefit.]
var _parent_bs = null

# [Deliberately $Path lookups INSIDE _build(), NOT @onready -- same reason
# item_select_screen.gd's own identical field-declaration doc comment gives:
# @onready only resolves at NOTIFICATION_READY (real tree entry), but this
# project's own established bare-instance test convention calls setup()
# directly on a freshly instantiate()'d overlay that's NEVER added to a
# tree at all. A plain $Path lookup resolves against the child nodes
# instantiate() already created regardless of tree membership, so it works
# in both the real (tree-added) and test (bare-instance) cases with no
# special-casing. (Found the hard way: the first draft used @onready here
# and crashed on a null _header the moment a bare-instance probe called
# setup() before ever adding the node to a tree.)
@warning_ignore("unused_private_class_variable")
var _field_strip_box: VBoxContainer = null

# [M26E5-2] Same $Path-lookup-inside-_build(), not @onready, reasoning as
# _field_strip_box's own doc comment above -- these two are populated by
# _build_player_panel/_build_opponent_panel, called separately from _build()
# the same way _build_field_strip already is.
@warning_ignore("unused_private_class_variable")
var _player_panel_box: VBoxContainer = null
@warning_ignore("unused_private_class_variable")
var _opponent_panel_box: VBoxContainer = null


func setup(parent_bs) -> void:
	_parent_bs = parent_bs
	_build()


func _build() -> void:
	var panel: PanelContainer = $Panel
	var vbox: VBoxContainer = $Panel/Margin/VBox
	var header: Label = $Panel/Margin/VBox/Header
	_player_panel_box = $Panel/Margin/VBox/PanelsRow/PlayerPanel
	_opponent_panel_box = $Panel/Margin/VBox/PanelsRow/OpponentPanel
	_field_strip_box = $Panel/Margin/VBox/FieldStrip

	if _parent_bs != null:
		# Reuses the SAME StyleBoxTexture Resource instance ActionPanel and
		# the two-box TOP/FIGHT slots already share (built once in
		# _setup_action_region_panel(), text_window/1.png, color-keyed) --
		# no second texture load/color-key pass, matching that function's
		# own "a Resource can back multiple nodes' theme overrides
		# simultaneously" precedent exactly.
		if _parent_bs._action_panel_menu_style != null:
			panel.add_theme_stylebox_override("panel", _parent_bs._action_panel_menu_style)
		header.add_theme_font_override("font", _parent_bs._font_menu)
		header.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
		header.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	header.text = "MATCHUP"
	_build_player_panel()
	_build_opponent_panel()
	_build_field_strip()

	var close_btn := Button.new()
	if _parent_bs != null:
		_parent_bs._style_menu_button(close_btn)
		_parent_bs._strip_button_chrome(close_btn)
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)


# [M26E5-1] Rebuildable independently of _build() -- a future live-refresh
# hook (deferred, decision 2) would call just this, not the whole overlay.
func _build_field_strip() -> void:
	for child in _field_strip_box.get_children():
		child.queue_free()
	if _parent_bs == null or _parent_bs._bm == null:
		return
	var bm: BattleManager = _parent_bs._bm
	for line in field_strip_lines(bm):
		_field_strip_box.add_child(_styled_label(line))


# [M26E5-2] Shared label-styling helper -- factored out of what E5-1's own
# _build_field_strip loop used to do inline, now reused by the player/
# opponent panels below too. `color` defaults to plain white, matching every
# field-strip line's own prior behavior exactly (this refactor changes no
# rendered output, confirmed by the existing 49 E5-1 assertions still
# passing unmodified). The `_parent_bs != null` guard is technically dead at
# every real call site (every caller already returns early above that check
# itself, same as _build_field_strip's own top-of-function guard), kept only
# for the same defensive symmetry that guard has always used.
func _styled_label(text: String, color: Color = Color(1, 1, 1, 1)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if _parent_bs != null:
		lbl.add_theme_font_override("font", _parent_bs._font_menu)
		lbl.add_theme_font_size_override("font_size", BattleScreenShared._FONT_NORMAL_SIZE)
	lbl.add_theme_color_override("font_color", color)
	return lbl


# [M26E5-3] Rebuildable independently of _build(), same shape as
# _build_field_strip. Player panel only -- see this file's own top-of-file
# doc comment for the full field list and the reasoning behind each
# inclusion/omission.
#
# [M26E5-3, doubles] Reads `_parent_bs._player_party` directly (the same
# field `_refresh_battlefield_side`/every other real per-side consumer in
# battle_screen_shared.gd already reads) rather than
# `_bm.get_active_player_mon()` -- that getter is a thin `_parties[0]
# .get_active()` wrapper that only ever returns FIELD SLOT 0, correct for
# singles and silently wrong for doubles' own second active slot. Iterating
# `party.num_active()`/`get_active_at(slot)` instead is what actually makes
# this doubles-aware: singles is just the num_active()==1 case, no special
# casing needed either direction.
func _build_player_panel() -> void:
	for child in _player_panel_box.get_children():
		child.queue_free()
	if _parent_bs == null or _parent_bs._player_party == null:
		return
	_build_mon_columns(_player_panel_box, _parent_bs._player_party, true)


# [M26E5-3] Opponent-panel mirror of _build_player_panel -- see this file's
# own top-of-file doc comment for why its content is a strict subset (name/
# types/stat-stage table only).
func _build_opponent_panel() -> void:
	for child in _opponent_panel_box.get_children():
		child.queue_free()
	if _parent_bs == null or _parent_bs._opp_party == null:
		return
	_build_mon_columns(_opponent_panel_box, _parent_bs._opp_party, false)


# [M26E5-3] One column per active field slot (1 in singles, 2 in doubles),
# laid out side by side in a fresh HBoxContainer -- the VBox box passed in
# (_player_panel_box/_opponent_panel_box) holds exactly this one row.
func _build_mon_columns(box: VBoxContainer, party: BattleParty, is_player: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for slot in range(party.num_active()):
		var mon: BattlePokemon = party.get_active_at(slot)
		if mon == null:
			continue
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		_populate_mon_panel(col, mon, is_player)
		row.add_child(col)
	box.add_child(row)


# [M26E5-2] Shared body for both panels -- `is_player` gates every field the
# brief reserves for the player's own side (§5.2 vs §5.4: HP, held item,
# ability, and the move list). The stat-stage table is the one section both
# sides always get.
func _populate_mon_panel(box: VBoxContainer, mon: BattlePokemon, is_player: bool) -> void:
	box.add_child(_styled_label(_parent_bs._mon_label(mon)))
	if is_player:
		var hp_color: Color = _parent_bs._hp_bar_color(mon.current_hp, mon.max_hp)
		box.add_child(_styled_label("HP %d/%d" % [mon.current_hp, mon.max_hp], hp_color))
	box.add_child(_build_type_row(mon.species.types))
	if is_player:
		var item_name := "None"
		if mon.held_item != null:
			item_name = mon.held_item.item_name
		box.add_child(_styled_label("Item: %s" % item_name))
		var ability_name := "—"
		if mon.ability != null:
			ability_name = mon.ability.ability_name
		box.add_child(_styled_label("Ability: %s" % ability_name))
		if mon.ability != null and mon.ability.description != "":
			box.add_child(_styled_label(mon.ability.description))
	box.add_child(_build_stat_stage_table(mon))
	if is_player:
		for i in range(mon.moves.size()):
			box.add_child(_build_move_row(mon, i))


# [M26C5, wired here per M26E5-2] One badge per real type, falling back to
# the type's own display name (TypeChart.type_name) when no badge asset
# exists for it (Stellar, or an invalid id) -- mirrors _type_badge_texture's
# own null-means-degrade-gracefully convention rather than silently omitting
# the type altogether.
func _build_type_row(types: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_styled_label("Type:"))
	for t in types:
		var tex: Texture2D = _parent_bs._type_badge_texture(t)
		if tex != null:
			var rect := TextureRect.new()
			rect.texture = tex
			rect.custom_minimum_size = Vector2(32, 16)
			row.add_child(rect)
		else:
			row.add_child(_styled_label(TypeChart.type_name(t)))
	return row


# [M26E5-2] All 7 stages always shown -- see this file's own top-of-file doc
# comment for why this table deliberately does NOT follow the field strip's
# "only show what's active" convention.
func _build_stat_stage_table(mon: BattlePokemon) -> VBoxContainer:
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 1)
	var main_stats := [
		[BattlePokemon.STAGE_ATK, "Atk"], [BattlePokemon.STAGE_DEF, "Def"],
		[BattlePokemon.STAGE_SPATK, "SpA"], [BattlePokemon.STAGE_SPDEF, "SpD"],
		[BattlePokemon.STAGE_SPEED, "Spe"],
	]
	for pair in main_stats:
		table.add_child(_stat_stage_row(mon, pair[0], pair[1], true))
	var acc_eva := [
		[BattlePokemon.STAGE_ACCURACY, "Acc"], [BattlePokemon.STAGE_EVASION, "Eva"],
	]
	for pair in acc_eva:
		table.add_child(_stat_stage_row(mon, pair[0], pair[1], false))
	return table


# [M26E5-2] Red = boosted, blue = lowered, plain white = neutral -- the "up/
# down color convention shared with E4's nature coloring" the recon's own
# §5.3 names (E4 itself is unbuilt, so this is the first real use of it, not
# a reuse of existing E4 code). `show_multiplier` is false for Acc/Eva --
# see this file's own top-of-file doc comment for why those two stages have
# no honest standalone multiplier to show.
func _stat_stage_row(mon: BattlePokemon, index: int, label: String, show_multiplier: bool) -> Label:
	var stage: int = 0
	if index < mon.stat_stages.size():
		stage = mon.stat_stages[index]
	var color := Color(1, 1, 1, 1)
	if stage > 0:
		color = Color8(255, 90, 90)
	elif stage < 0:
		color = Color8(90, 160, 255)
	var text := "%s %s" % [label, _parent_bs._stage_text(stage)]
	if show_multiplier:
		text += " (%s)" % _parent_bs._stage_multiplier_text(stage)
	return _styled_label(text, color)


# [M26C4/C5, M26E5-2] One row per move: category icon, type badge, name, PP,
# power/accuracy, secondary-effect chance, contact flag. Power/accuracy show
# "—" for the cases MoveData itself uses to mean "not applicable" (power 0 =
# every status move; accuracy 0 = always-hits, per MoveData.accuracy's own
# doc comment) rather than printing a misleading "0". Secondary chance
# mirrors the recon's own §5.2 rule exactly: "100%" when secondary_chance==0
# AND a real secondary effect exists (0 means guaranteed, not absent -- see
# MoveData.secondary_chance's own doc comment), "—" when secondary_effect is
# SE_NONE. Move description is deliberately absent -- see this file's own
# top-of-file doc comment (E4-1 dependency).
func _build_move_row(mon: BattlePokemon, index: int) -> HBoxContainer:
	var move: MoveData = mon.moves[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cat_tex: Texture2D = _parent_bs._category_icon_texture(move.category)
	if cat_tex != null:
		var cat_rect := TextureRect.new()
		cat_rect.texture = cat_tex
		cat_rect.custom_minimum_size = Vector2(16, 16)
		row.add_child(cat_rect)
	var type_tex: Texture2D = _parent_bs._type_badge_texture(move.type)
	if type_tex != null:
		var type_rect := TextureRect.new()
		type_rect.texture = type_tex
		type_rect.custom_minimum_size = Vector2(32, 16)
		row.add_child(type_rect)
	row.add_child(_styled_label(move.move_name))
	row.add_child(_styled_label("PP %d/%d" % [mon.current_pp[index], move.pp]))
	var power_text := str(move.power) if move.power > 0 else "—"
	var acc_text := ("%d%%" % move.accuracy) if move.accuracy > 0 else "—"
	row.add_child(_styled_label("Pow %s / Acc %s" % [power_text, acc_text]))
	var chance_text := "—"
	if move.secondary_effect != MoveData.SE_NONE:
		var chance: int = 100 if move.secondary_chance == 0 else move.secondary_chance
		chance_text = "%d%%" % chance
	row.add_child(_styled_label("Sec %s" % chance_text))
	row.add_child(_styled_label("Contact" if move.makes_contact else "—"))
	return row


# [M26E5-1] Pure content builder -- one line per field-state fact that's
# actually ACTIVE right now (an inactive screen/hazard is omitted entirely
# rather than shown as "0 turns"/"—", matching this project's own general
# "don't show noise" convention -- a player dashboard cares what IS up, not
# an exhaustive list of what isn't). Deliberately reads `bm` inputs only, no
# node state, so this is directly unit-testable without a live scene --
# matches this project's own established "handler logic tested via direct
# call" convention (e.g. _on_log_ability_changed's own test suite).
# Weather is the one line always shown (including "None"), since confirming
# the field's own baseline state has real value; Trick Room and every
# per-side condition are omitted when inactive.
static func field_strip_lines(bm: BattleManager) -> Array[String]:
	var lines: Array[String] = []
	var weather_line := "Weather: %s" % _weather_name(bm.weather)
	if bm.weather != DamageCalculator.WEATHER_NONE:
		weather_line += " (%d turns)" % bm.weather_duration
	lines.append(weather_line)
	if bm.trick_room_turns > 0:
		lines.append("Trick Room: %d turns" % bm.trick_room_turns)
	lines.append_array(_side_lines(bm, 0, "Your side"))
	lines.append_array(_side_lines(bm, 1, "Opponent's side"))
	return lines


# [M26E5-1] Decision 3 (Rob, 2026-08-04): screens and hazards are the same
# read and the same mental-tracking burden as the three Rob originally
# named, so they're included too. Three shapes because _side_conditions
# itself has three (see get_side_condition_turns/_layers/_flag's own doc
# comment in battle_manager.gd): a countdown, a layer count, or a flag.
static func _side_lines(bm: BattleManager, side: int, side_label: String) -> Array[String]:
	var rows: Array[String] = []
	var turn_conditions := [
		["tailwind", "Tailwind"], ["reflect", "Reflect"], ["light_screen", "Light Screen"],
		["aurora_veil", "Aurora Veil"], ["safeguard", "Safeguard"], ["mist", "Mist"],
	]
	for pair in turn_conditions:
		var turns: int = bm.get_side_condition_turns(side, pair[0])
		if turns > 0:
			rows.append("%s — %s: %d turns" % [side_label, pair[1], turns])
	var layer_conditions := [["spikes", "Spikes"], ["toxic_spikes", "Toxic Spikes"]]
	for pair in layer_conditions:
		var layers: int = bm.get_side_condition_layers(side, pair[0])
		if layers > 0:
			rows.append("%s — %s: %d" % [side_label, pair[1], layers])
	var flag_conditions := [["stealth_rock", "Stealth Rock"], ["sticky_web", "Sticky Web"]]
	for pair in flag_conditions:
		if bm.get_side_condition_flag(side, pair[0]):
			rows.append("%s — %s" % [side_label, pair[1]])
	return rows


static func _weather_name(weather_type: int) -> String:
	match weather_type:
		DamageCalculator.WEATHER_NONE:
			return "None"
		DamageCalculator.WEATHER_RAIN:
			return "Rain"
		DamageCalculator.WEATHER_SUN:
			return "Sun"
		DamageCalculator.WEATHER_SANDSTORM:
			return "Sandstorm"
		DamageCalculator.WEATHER_HAIL:
			return "Hail"
		DamageCalculator.WEATHER_STRONG_WINDS:
			return "Strong Winds"
	return "Unknown"


func _on_close_pressed() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# [M26E5-1, decision 1] ESC closes, mirroring ItemSelectScreen/
	# SwitchSelectScreen's own established convention exactly. TAB is
	# deliberately NOT handled here even though it's the overlay's own
	# open/close key everywhere else in this feature -- it's centralized in
	# battle_screen_shared.gd's own _unhandled_input instead (single source
	# of truth for the toggle, avoiding any dependence on which of two
	# independent _unhandled_input handlers Godot happens to dispatch to
	# first for the same physical key event).
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_close_pressed()
