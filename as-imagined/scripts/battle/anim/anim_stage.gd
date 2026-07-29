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


func set_battler_visible(anim_battler: int, visible: bool) -> void:
	var node := sprite_for(anim_battler)
	if node != null:
		node.visible = visible
