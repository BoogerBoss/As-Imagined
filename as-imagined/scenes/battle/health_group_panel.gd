class_name HealthGroupPanel
extends Control

# [Doubles-split roadmap, step 1 of 7 — see the scoping report in this
# session's own conversation / docs/decisions.md's doubles-split entry for
# the full recon] A reusable "one Pokémon's on-field info" component,
# extracted from battle_screen.tscn's own 6 hand-duplicated health-group
# node trees (OpponentHealthGroup/PlayerHealthGroup/OpponentHealthGroupD0/
# D1/PlayerHealthGroupD0/D1).
#
# Step 1 scope: the SINGLES-scale "opponent" template — the Background/
# StatusIcon/HpFill/NameLabel/GenderLabel/LevelLabel subset every one of the
# 6 existing groups shares. health_group_panel.tscn (no HpNumberLabel/
# ExpFill) is that opponent-shaped instance.
#
# [Step 2] PlayerHealthGroup's own two extra nodes (HpNumberLabel, ExpFill)
# are now supported too, but NOT via a shared Background rect + translated
# offsets as originally sketched — PlayerHealthGroup's real databox art is
# genuinely TALLER (520x168 vs the opponent's 520x124, reserving room for
# the EXP-bar ledge), so Background/StatusIcon/HpFill/Name/Gender/Level all
# need their own independently-correct sizes for the player variant, not a
# shared frame with an offset applied. Rather than force one Background
# size to serve both (which would either letterbox the player art or crop
# the opponent art), this script treats HpNumberLabel/ExpFill as OPTIONAL —
# present or absent is read directly off the actual child nodes via
# get_node_or_null(), no export flag to fall out of sync with reality — and
# a second, independently-geometried scene (health_group_panel_player.tscn)
# provides them, its own Background/StatusIcon/HpFill/Name/Gender/Level
# values copied VERBATIM from PlayerHealthGroup's real current .tscn values
# (not derived/translated), the same "copy the already-tuned numbers
# exactly" approach step 1 used for the opponent shape.
#
# [Step 3] The doubles-scale templates are NOT a scaled-down derivative of
# either singles shape (confirmed: OpponentHealthGroupD0/D1 share one
# identical internal template, as do PlayerHealthGroupD0/D1 — only the
# OUTER placement anchor differs between D0/D1, matching this component's
# own "the internal template is instance-independent, placement is the
# instancing scene's job" design already established in steps 1-2) — a
# 130x31 "thin" box with a 14px font and no HpNumberLabel/ExpFill on
# EITHER side (real doubles never shows an EXP bar at all, confirmed by
# this project's own pre-existing m26c1_databox_test assertion). Two more
# sibling scenes, same script, same verbatim-copy approach:
# health_group_panel_doubles_opponent.tscn / _doubles_player.tscn.
#
# Not yet wired into battle_screen.tscn — both scenes are standalone
# components, verified in isolation via health_group_panel_test.gd, with
# zero references from any production scene yet. Wiring them in (replacing
# the 6 duplicated node trees one at a time) is a later roadmap step.
#
# Deliberately data-in/data-out: refresh() takes already-resolved plain
# values (name/level/gender text, a status enum int, HP numbers, a
# pre-computed HP bar color) rather than a BattlePokemon reference or a
# callback into BattleScreen — keeps this component self-contained,
# independently testable, and eventually @tool-previewable, with zero
# dependency on the parent screen's own state.
#
# Name-length handling (the dynamic font-metric gender/level repositioning)
# is explicitly OUT of scope for this extraction — reused verbatim from
# battle_screen.gd's own _position_gender_label, unchanged, per explicit
# confirmation that this can stay orthogonal to the doubles split.

@export var databox_texture: Texture2D = preload("res://assets/sprites/battle_ui/interface/databox_opponent.png"):
	set(value):
		databox_texture = value
		if is_node_ready():
			_background.texture = value

@export var status_sheet: Texture2D = preload("res://assets/sprites/battle_ui/interface/status2.png"):
	set(value):
		status_sheet = value
		if is_node_ready():
			_status_atlas.atlas = value

const _STATUS_ICON_SIZE := Vector2(24, 8)

# [Step 2] The Emerald UI Pack's own real EXP-bar color — see
# battle_screen.gd's own identically-named/valued constant for the source
# citation (sampled directly from overlay_exp.png).
const _EXP_BAR_COLOR := Color8(66, 206, 255)

@onready var _background: TextureRect = $Background
@onready var _status_icon: TextureRect = $StatusIcon
@onready var _hp_fill: TextureProgressBar = $HpFill
@onready var _name_label: Label = $NameLabel
@onready var _gender_label: Label = $GenderLabel
@onready var _level_label: Label = $LevelLabel

# [Step 2] Optional — only present on the player-shaped variant
# (health_group_panel_player.tscn). null on the opponent-shaped
# health_group_panel.tscn, checked directly rather than via an export flag.
@onready var _hp_number_label: Label = get_node_or_null("HpNumberLabel")
@onready var _exp_fill: TextureProgressBar = get_node_or_null("ExpFill")

var _status_atlas: AtlasTexture
var _font: FontFile


func _ready() -> void:
	# [Matches battle_screen.gd's own _load_battle_fonts()/_setup_health_ui()
	# exactly — see those functions' own doc comments for why
	# fixed_size_scale_mode=2 is required for the .tscn's font_size overrides
	# to have any visible effect at all with this bitmap font.]
	_font = FontFile.new()
	_font.load_bitmap_font("res://assets/fonts/latin_small_healthbox.fnt")
	_font.fixed_size_scale_mode = 2
	var labels: Array[Label] = [_name_label, _gender_label, _level_label]
	if _hp_number_label != null:
		labels.append(_hp_number_label)
	for label: Label in labels:
		label.add_theme_font_override("font", _font)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	if databox_texture != null:
		_background.texture = databox_texture

	_status_atlas = AtlasTexture.new()
	_status_atlas.atlas = status_sheet
	_status_atlas.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
	_status_icon.texture = _status_atlas

	_configure_solid_fill_bar(_hp_fill, _solid_fill_texture())

	if _exp_fill != null:
		_configure_solid_fill_bar(_exp_fill, _solid_fill_texture())
		_exp_fill.tint_progress = _EXP_BAR_COLOR
		_exp_fill.min_value = 0.0
		_exp_fill.max_value = 1.0
		_exp_fill.step = 0.0


static func _solid_fill_texture() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


static func _configure_solid_fill_bar(bar: TextureProgressBar, fill_tex: Texture2D) -> void:
	bar.texture_progress = fill_tex
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 0
	bar.stretch_margin_right = 0
	bar.stretch_margin_top = 0
	bar.stretch_margin_bottom = 0
	bar.step = 0.0


static func status_icon_row(status: int) -> int:
	match status:
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


func _update_status_icon(status: int) -> void:
	var row := status_icon_row(status)
	if row < 0:
		_status_icon.visible = false
		return
	_status_icon.visible = true
	_status_atlas.region = Rect2(0, row * _STATUS_ICON_SIZE.y, _STATUS_ICON_SIZE.x, _STATUS_ICON_SIZE.y)


# Extracted verbatim from battle_screen.gd's own _position_gender_label —
# see this file's own top-of-file doc comment for why name-length handling
# itself is out of scope here.
func _position_gender_and_level(name_text: String, gender_glyph: String, level_text: String) -> void:
	_gender_label.text = gender_glyph
	var font: Font = _name_label.get_theme_font("font")
	if font == null:
		return
	var font_size: int = _name_label.get_theme_font_size("font_size")
	var name_width: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap: float = font_size * 0.15
	var content_right: float = _name_label.offset_left + name_width
	if not gender_glyph.is_empty():
		_gender_label.offset_top = _name_label.offset_top
		_gender_label.offset_bottom = _name_label.offset_bottom
		_gender_label.offset_left = _name_label.offset_left + name_width + gap
		_gender_label.offset_right = _gender_label.offset_left + font_size * 1.2
		content_right = _gender_label.offset_right
	var level_width: float = font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var desired_left: float = content_right + gap * 2.5
	var max_left: float = INF
	if _background != null:
		max_left = _background.offset_right - level_width - gap
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.offset_top = _name_label.offset_top
	_level_label.offset_bottom = _name_label.offset_bottom
	_level_label.offset_left = minf(desired_left, max_left)
	_level_label.offset_right = _level_label.offset_left + font_size * 4.0
	_level_label.text = level_text


# [Doubles-split roadmap, step 5] Public accessor -- message-pacing's
# "hp_drain" beat (battle_screen_shared.gd) tweens this bar directly rather
# than snapping it via refresh(), so it needs the real live node, not a
# value copy.
func get_hp_fill_bar() -> TextureProgressBar:
	return _hp_fill


# [EXP bar animation fix] Same shape as get_hp_fill_bar() immediately above --
# message-pacing's own "exp_drain" beat (battle_screen_shared.gd) tweens this
# bar directly rather than snapping it via refresh(), so it needs the real
# live node too. null on the opponent-shaped variant (no ExpFill node at
# all), matching get_hp_fill_bar's null-safe contract for every caller.
func get_exp_fill_bar() -> TextureProgressBar:
	return _exp_fill


func refresh(name_text: String, gender_glyph: String, level_text: String, status: int,
		current_hp: int, max_hp: int, hp_color: Color, exp_fraction: float = -1.0) -> void:
	_name_label.text = name_text
	_position_gender_and_level(name_text, gender_glyph, level_text)
	_update_status_icon(status)
	_hp_fill.max_value = max_hp
	_hp_fill.value = current_hp
	_hp_fill.tint_progress = hp_color
	if _hp_number_label != null:
		_hp_number_label.text = "%d/%d" % [current_hp, max_hp]
	if _exp_fill != null and exp_fraction >= 0.0:
		_exp_fill.value = exp_fraction
