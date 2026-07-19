class_name HitEffectRegistry
extends RefCounted

# [M23.11 Phase 5c] Move -> hit-effect asset lookup, consuming 5b's pulled
# asset set (assets/sprites/battle_effects/{generic,bespoke}/) — the hybrid
# model locked in docs/m23_11_phase5_recon.md Section 0 item 5 / Section 4.4:
# 3 hand-picked moves (Flamethrower/Thunder/Surf) get their own bespoke
# asset(s), every other move falls through to a type/category-keyed generic
# pick. Pure lookup, RefCounted, no scene-tree dependency — mirrors
# BattleBackgroundRegistry/SpriteRegistry's own static-loader convention.
# Actual node creation/animation lives in battle_screen.gd (this registry
# only resolves WHICH texture(s), never touches Control nodes).
#
# MoveData has no numeric id field of its own (move_registry.gd's own doc
# comment confirms id is a pure filename convention,
# "res://data/moves/move_NNNN.tres") -- move_id_of() below recovers it from
# the loaded resource's own .resource_path rather than matching on
# move_name text, so this stays correct even if move_name display text is
# ever retouched.

const GENERIC_DIR := "res://assets/sprites/battle_effects/generic/"
const BESPOKE_DIR := "res://assets/sprites/battle_effects/bespoke/"

const MOVE_ID_FLAMETHROWER := 53
const MOVE_ID_SURF := 57
const MOVE_ID_THUNDER := 87

const _BESPOKE_SUBDIR := {
	MOVE_ID_FLAMETHROWER: "0053_flamethrower",
	MOVE_ID_SURF: "0057_surf",
	MOVE_ID_THUNDER: "0087_thunder",
}

# TypeChart.TYPE_* -> generic/<name>.png, matching gen_hit_effect_sprites.py's
# own GENERIC_PICKS output names exactly (Part A, 18 type-family entries).
# TYPE_NONE/TYPE_MYSTERY/TYPE_STELLAR deliberately absent -- no roster move
# resolves to these as a real attacking type (TYPE_MYSTERY is Struggle's own
# typeless marker; TYPE_STELLAR is Tera-only, not implemented), so
# get_generic_texture() below falls through to its own physical/status
# fallback for any of the 3.
const _TYPE_TO_GENERIC := {
	TypeChart.TYPE_NORMAL: "normal",
	TypeChart.TYPE_FIGHTING: "fighting",
	TypeChart.TYPE_FLYING: "flying",
	TypeChart.TYPE_POISON: "poison",
	TypeChart.TYPE_GROUND: "ground",
	TypeChart.TYPE_ROCK: "rock",
	TypeChart.TYPE_BUG: "bug",
	TypeChart.TYPE_GHOST: "ghost",
	TypeChart.TYPE_STEEL: "steel",
	TypeChart.TYPE_FIRE: "fire",
	TypeChart.TYPE_WATER: "water",
	TypeChart.TYPE_GRASS: "grass",
	TypeChart.TYPE_ELECTRIC: "electric",
	TypeChart.TYPE_PSYCHIC: "psychic",
	TypeChart.TYPE_ICE: "ice",
	TypeChart.TYPE_DRAGON: "dragon",
	TypeChart.TYPE_DARK: "dark",
	TypeChart.TYPE_FAIRY: "fairy",
}


static func move_id_of(move: MoveData) -> int:
	if move == null or move.resource_path.is_empty():
		return -1
	# "res://data/moves/move_0053.tres" -> "move_0053" -> "0053"
	var stem := move.resource_path.get_file().trim_suffix(".tres")
	var digits := stem.trim_prefix("move_")
	return digits.to_int() if digits.is_valid_int() else -1


static func is_bespoke(move_id: int) -> bool:
	return _BESPOKE_SUBDIR.has(move_id)


static func get_flamethrower_texture() -> Texture2D:
	return load(BESPOKE_DIR + _BESPOKE_SUBDIR[MOVE_ID_FLAMETHROWER] + "/small_ember.png")


# Order matters -- lightning.png (the primary 5-frame bolt) plays first,
# lightning_2.png (a shorter secondary flash, confirmed via direct PIL
# inspection this session to already share lightning.png's exact 16-color
# embedded palette -- no runtime index/palette recoloring is actually
# needed despite 5b's own "genuine cross-file palette reference" framing of
# the SOURCE format) plays immediately after as a follow-up flash, both at
# the same on-screen position.
static func get_thunder_textures() -> Array:
	var dir := BESPOKE_DIR + _BESPOKE_SUBDIR[MOVE_ID_THUNDER] + "/"
	return [load(dir + "lightning.png"), load(dir + "lightning_2.png")]


# Surf's two pulled files are keyed by WHICH SIDE's own Surf animation they
# represent (source file naming: water_player.png / water_opponent.png),
# not attacker-vs-defender -- a player-side attacker uses water_player.png
# regardless of who it's hitting.
static func get_surf_texture(attacker_is_player: bool) -> Texture2D:
	var dir := BESPOKE_DIR + _BESPOKE_SUBDIR[MOVE_ID_SURF] + "/"
	return load(dir + ("water_player.png" if attacker_is_player else "water_opponent.png"))


# Generic fallback -- keyed on move.type first (18 of 21 generic sprites),
# falling back to move.category for the 3 non-type-specific picks:
# stat_shimmer for a stat-changing status move (mirrors this project's own
# existing "stat_change_stat >= 0" convention, e.g. battle_screen.gd's
# Menu.TARGET_SELECT gating), status_puff for any other status move, and
# physical_impact for a damaging move whose type has no curated generic
# sprite (TYPE_MYSTERY/TYPE_STELLAR only, per _TYPE_TO_GENERIC's own doc
# comment -- unreachable by this project's real roster today, kept as a
# defensive fallback rather than an unhandled null).
static func get_generic_texture(move: MoveData) -> Texture2D:
	if move == null:
		return null
	# CATEGORY gates first, not type -- almost every status move still
	# carries a real elemental .type (Growl/Swords Dance are TYPE_NORMAL,
	# Thunder Wave is TYPE_ELECTRIC, Toxic is TYPE_POISON, ...), so checking
	# type first would make stat_shimmer/status_puff nearly unreachable in
	# practice (only the rare TYPE_MYSTERY/TYPE_STELLAR case would ever hit
	# them) -- defeating their whole purpose as the non-elemental STATUS
	# read. Only a damaging move (category 0/1) uses the type-keyed sprite.
	if move.category == 2:  # STATUS
		var name := "stat_shimmer" if move.stat_change_stat >= 0 else "status_puff"
		return load(GENERIC_DIR + name + ".png")
	var type_name: String = _TYPE_TO_GENERIC.get(move.type, "")
	if not type_name.is_empty():
		return load(GENERIC_DIR + type_name + ".png")
	return load(GENERIC_DIR + "physical_impact.png")


# Slices a (possibly multi-frame) strip texture into a square frame size +
# count, matching the exact stacked-square-sub-frame shape
# gen_hit_effect_sprites.py's own doc comment documents for every pulled
# sprite. Pure function (no Image/texture loading of its own) so it's
# directly unit-testable against plain Vector2 sizes.
#
# Irregular sources (confirmed present: steel.png, 16x40, flagged "not
# fixed" in 5b's own curation notes -- 40 isn't a multiple of 16) fall back
# to frame_count=1 with the FULL source size as one frame, rather than
# cropping to a square and silently losing content.
static func compute_frame_layout(tex_size: Vector2) -> Dictionary:
	var w := int(tex_size.x)
	var h := int(tex_size.y)
	var minor: int = min(w, h)
	var major: int = max(w, h)
	if minor <= 0 or major % minor != 0:
		return {"frame_size": tex_size, "frame_count": 1, "vertical": h >= w}
	return {"frame_size": Vector2(minor, minor), "frame_count": major / minor, "vertical": h >= w}
