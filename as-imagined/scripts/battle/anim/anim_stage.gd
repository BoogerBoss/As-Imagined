class_name AnimStage
extends RefCounted

# [M36B] The bridge between the reference's battler-relative coordinate model
# and this project's actual battle scene. Scope of record: docs/m26_f1_recon.md.
#
# Animation scripts address participants abstractly (ANIM_ATTACKER,
# ANIM_TARGET, the partner slots) and behaviors ask for positions in GBA
# screen space -- a 240x160 canvas with per-position anchors (sBattlerCoords)
# and a species-height Y adjustment. This project's stage is a 1024x768
# canvas whose sprites are already positioned by the scene. Rather than port
# GBA pixel coordinates and then fight the layout, the adapter resolves an
# anim-battler to the REAL sprite node and reports its rect; behaviors work
# in stage space and stay correct at any resolution.
#
# Constructed by the battle screen (which owns the nodes) and handed to the
# VM. A test can substitute any object exposing the same methods -- the VM
# only duck-types what it calls, which is why the fallback/VM suite runs with
# no stage at all.

# enum AnimBattler, from include/constants/battle_anim.h. The scripts use
# these constants directly, so they are reproduced verbatim rather than
# remapped.
const ANIM_ATTACKER := 0
const ANIM_TARGET := 1
const ANIM_ATK_PARTNER := 2
const ANIM_DEF_PARTNER := 3

var attacker: BattlePokemon = null
var target: BattlePokemon = null
var attacker_partner: BattlePokemon = null
var target_partner: BattlePokemon = null

# Callables supplied by the host, so this class never reaches into the scene
# tree itself: sprite_for(mon) -> Control, effect_layer() -> Control.
var _sprite_for: Callable
var _effect_layer: Callable


func _init(sprite_for: Callable, effect_layer: Callable) -> void:
	_sprite_for = sprite_for
	_effect_layer = effect_layer


func set_participants(atk: BattlePokemon, tgt: BattlePokemon,
		atk_partner: BattlePokemon = null,
		tgt_partner: BattlePokemon = null) -> void:
	attacker = atk
	target = tgt
	attacker_partner = atk_partner
	target_partner = tgt_partner


func mon_for(anim_battler: int) -> BattlePokemon:
	match anim_battler:
		ANIM_ATTACKER:
			return attacker
		ANIM_TARGET:
			return target
		ANIM_ATK_PARTNER:
			return attacker_partner
		ANIM_DEF_PARTNER:
			return target_partner
	# ANIM_PLAYER_LEFT..ANIM_OPPONENT_RIGHT (4..7) are absolute slots used by
	# a handful of scripts; unresolvable here without a doubles field map, so
	# they degrade to the attacker rather than returning null into a caller
	# that would then skip the sprite silently.
	return attacker


func sprite_for(anim_battler: int) -> Control:
	var mon := mon_for(anim_battler)
	if mon == null or not _sprite_for.is_valid():
		return null
	return _sprite_for.call(mon) as Control


# Centre of a battler's sprite in stage space -- the origin every anim sprite
# is born at upstream (createsprite places at the TARGET's centre regardless
# of anim_battler; behaviors that want the attacker reposition themselves).
func center_of(anim_battler: int) -> Vector2:
	var node := sprite_for(anim_battler)
	if node == null:
		return Vector2.ZERO
	return node.get_global_rect().get_center()


func rect_of(anim_battler: int) -> Rect2:
	var node := sprite_for(anim_battler)
	return node.get_global_rect() if node != null else Rect2()


# True when the attacker stands on the player's side. Upstream this drives
# the X-mirroring of every offset argument (SetAnimSpriteInitialXOffset), so
# behaviors need it to place effects on the correct side of the target.
func attacker_is_player_side() -> bool:
	var atk := sprite_for(ANIM_ATTACKER)
	var tgt := sprite_for(ANIM_TARGET)
	if atk == null or tgt == null:
		return true
	return atk.get_global_rect().get_center().y \
			>= tgt.get_global_rect().get_center().y


# Direction-aware X offset: upstream, a positive arg means "toward the
# target", which flips sign depending on which side the attacker is on.
func facing_sign() -> float:
	return 1.0 if attacker_is_player_side() else -1.0


# The scripts' offsets are GBA-screen pixels (a 240x160 canvas). This project
# renders far larger, so an offset of "8 px toward the target" has to be
# scaled or every effect would cluster invisibly at the sprite's centre.
# Derived from the effect layer's real width rather than hardcoded, so it
# stays correct under M26A1's resolution change and any future one.
const GBA_SCREEN_WIDTH := 240.0

func pixel_scale() -> float:
	var l := layer()
	if l == null or l.size.x <= 0.0:
		return 1.0
	return maxf(1.0, l.size.x / GBA_SCREEN_WIDTH)


func layer() -> Control:
	return _effect_layer.call() as Control if _effect_layer.is_valid() else null


# ── [M36E2] The animation background layer ────────────────────────────────
#
# On hardware a move animation swaps the whole battle BACKGROUND (BG1/BG3) and
# fades the screen through black to do it. Reproduced with two nodes created
# lazily inside BattleStage:
#
#   AnimBgLayer      a full-rect TextureRect inserted just above the battle
#                    backdrop and BELOW the bases and battlers, so a swapped
#                    background sits behind the Pokemon exactly as it does
#                    upstream.
#   AnimFadeOverlay  a black full-rect ColorRect added LAST, so it covers the
#                    battlers and effect layer too. The reference's fade is a
#                    hardware palette fade over every palette, which darkens
#                    everything on screen -- not just the background.
#
# Created on demand rather than authored into the two battle scenes, so the
# scenes stay untouched and doubles/singles need no separate edit.

const _BG_LAYER_NAME := "AnimBgLayer"
const _FADE_OVERLAY_NAME := "AnimFadeOverlay"


func _stage_root() -> Control:
	var l := layer()
	return l.get_parent() as Control if l != null else null


func background_layer() -> TextureRect:
	var root := _stage_root()
	if root == null:
		return null
	var existing := root.get_node_or_null(_BG_LAYER_NAME)
	if existing != null:
		return existing as TextureRect
	var node := TextureRect.new()
	node.name = _BG_LAYER_NAME
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.visible = false
	root.add_child(node)
	# Directly above the battle backdrop, below everything else.
	root.move_child(node, 1)
	return node


func fade_overlay() -> ColorRect:
	var root := _stage_root()
	if root == null:
		return null
	var existing := root.get_node_or_null(_FADE_OVERLAY_NAME)
	if existing != null:
		return existing as ColorRect
	var node := ColorRect.new()
	node.name = _FADE_OVERLAY_NAME
	node.color = Color(0, 0, 0, 0)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(node)
	root.move_child(node, root.get_child_count() - 1)
	return node


# Shows a background by its BG_* name. Returns false when the name has no
# pulled asset, so a caller can decide rather than silently showing nothing.
func set_background(bg_name: String) -> bool:
	var node := background_layer()
	if node == null:
		return false
	var tex := AnimData.background_texture(bg_name)
	if tex == null:
		return false
	node.texture = tex
	node.visible = true
	return true


func clear_background() -> void:
	var node := background_layer()
	if node != null:
		node.visible = false
		node.texture = null


# 0.0 = normal, 1.0 = fully black. The port of the hardware palette fade.
func set_fade(amount: float) -> void:
	var node := fade_overlay()
	if node != null:
		node.color = Color(0, 0, 0, clampf(amount, 0.0, 1.0))


func set_battler_visible(anim_battler: int, visible: bool) -> void:
	var node := sprite_for(anim_battler)
	if node != null:
		node.visible = visible
