class_name SurfBlob
extends Sprite2D

## [M27E E1c] The surf blob — the thing the player visibly rides.
##
## Ported from `FldEff_SurfBlob` / `UpdateSurfBlobFieldEffect`
## (`src/field_effect_helpers.c:1199-1330`) and the field-effect template
## (`src/data/field_effects/field_effect_objects.h:211-256`).
##
## ⚠️ **THE SHEET IS `object_events/misc_surf_blob.png` — 192x32, SIX frames —
## AND THAT IS AN ART-DIRECTION CALL, NOT A PORT.** Rob's, from a live
## playthrough: the blob this first shipped with is EMERALD's, and this project
## is Kanto.
##
## Both sheets exist and they are visibly different designs: the 3-frame
## `field_effects/surf_blob.png` is dark navy with a heavy black outline (what
## `gFieldEffectObjectTemplate_SurfBlob` actually uses in source), while this
## 6-frame one is a lighter purple blob with a pale blue crest and foam. Only
## the first has a consumer in source — `gObjectEventPic_SurfBlob` is
## referenced by nothing outside its own INCGFX, confirmed by grep — so the
## reference offers NO anim table for the sheet we are using and the frame
## mapping below is READ OFF THE ART, not ported.
##
## ⚠️ **SO THE FRAME MAPPING IS INFERRED AND IS THE THING TO CHECK ON SCREEN.**
## Six frames read as three facings x two bob frames: (0,1) wide with foam at
## both corners = SOUTH, (2,3) narrower with two prongs below = NORTH, (4,5)
## elongated with a tail = WEST, EAST mirrored. If a facing looks wrong in play,
## this table is the first suspect — not the bob, not the placement.
##
## The SECOND frame of each pair is deliberately unused for now: source's blob
## bobs by y-offset alone (`UpdateBobbingEffect`), which is ported below, and
## animating the sprite as well would be inventing a second motion on top of a
## real one. Recorded so the spare frames read as a deliberate choice rather
## than an oversight.
##
## The bob (`UpdateBobbingEffect`): `y2 += velocity` every 4th frame, velocity
## flipping sign every 16th — a 0..-4px triangle wave, 32-frame period. While a
## cardinal neighbour is dismountable land the step slows to every 8th frame
## (`SynchronizeSurfPosition`'s ELEVATION_DEFAULT scan), which also halves the
## amplitude to 0..-2px — source's own "bobs slower while dismounting".
##
## ⚠️ **THE PLAYER RIDES THE SAME OFFSET.** Source's normal state is
## BOB_PLAYER_AND_MON: `playerSprite->y2 = sprite->y2`, both sprites bobbing in
## lockstep — which is what makes it read as riding rather than two sprites
## coincidentally overlapping. Reproduced by this node bobbing the linked body
## sprite alongside itself.
##
## Stepped on WALL CLOCK in whole 1/60s increments, per [M26G4] — frame-tied
## stepping runs ~10% slow at 144Hz and half speed at 30Hz.

const SHEET := "res://assets/sprites/overworld/object_events/misc_surf_blob.png"
const FRAME_W := 32
const FRAME_H := 32
const CELL := 16
const GBA_FRAME := 1.0 / 60.0

## Frame per facing on the Kanto sheet — INFERRED from the art, since this sheet
## has no anim table in source (see the header). Pairs are (facing, bob); only
## the first of each pair is drawn. EAST is WEST mirrored, which is the one part
## that IS source's own convention (`sSurfBlobAnim_FaceEast` is
## `ANIMCMD_FRAME(2, .hFlip = TRUE)`) and holds for the people sheets too.
const FACE_FRAME := {"SOUTH": 0, "NORTH": 2, "WEST": 4, "EAST": 4}

## The player's body sprite, bobbed in lockstep (BOB_PLAYER_AND_MON).
var body: Sprite2D = null
var body_base_y := 0.0
var base_y := 0.0

## Bob state, source's own fields: sTimer / sVelocity / y2, plus the interval
## mask — 3 = step every 4th frame, 7 = every 8th while shore-adjacent
## (`UpdateBobbingEffect`'s `intervals[] = {0x3, 0x7}`).
var bob_timer := 0
var bob_velocity := -1
var bob_y := 0
var interval_mask := 3

var _accum := 0.0
var _face_key := ""


## Build the blob under `player`, drawn BEHIND `body_sprite` (first child =
## drawn first), bobbing both itself and the body. Null if the sheet is
## missing — a mount must degrade to no-blob, never to a crash.
static func attach(player: Node2D, body_sprite: Sprite2D, facing: String) -> SurfBlob:
	if player == null or body_sprite == null:
		return null
	if not ResourceLoader.exists(SHEET):
		return null
	var blob := SurfBlob.new()
	blob.name = "SurfBlob"
	blob.texture = load(SHEET)
	blob.region_enabled = true
	blob.centered = false
	# Same placement formula as OverworldEntity.make_sprite applied to 32x32:
	# centred on the cell horizontally, bottom on the cell's own bottom. That
	# lines the blob's bottom up with the player's — exactly what source's
	# shared tile-centred OAM positioning produces, since both sprites are 32
	# tall there (player 16x32, blob 32x32).
	blob.position = Vector2((CELL - FRAME_W) * 0.5, CELL - FRAME_H)
	blob.base_y = blob.position.y
	blob.body = body_sprite
	blob.body_base_y = body_sprite.position.y
	blob.face(facing)
	player.add_child(blob)
	player.move_child(blob, 0)
	return blob


## Point the blob the way the player faces. Keyed so the caller can forward
## every idle-frame facing refresh without rewriting the region each time.
func face(facing: String) -> void:
	if facing == _face_key:
		return
	_face_key = facing
	var frame: int = int(FACE_FRAME.get(facing, 0))
	region_rect = Rect2(frame * FRAME_W, 0, FRAME_W, FRAME_H)
	flip_h = facing == "EAST"


## Slow the bob while a cardinal neighbour is dismountable land — source's
## `sIntervalIdx` flip on ELEVATION_DEFAULT (3) adjacency
## (`SynchronizeSurfPosition`, `global.fieldmap.h:18`).
func set_near_shore(near: bool) -> void:
	interval_mask = 7 if near else 3


## Advance on wall clock; whole 1/60s steps only, remainder carried. The
## accumulator is capped so a hitch (a battle return, a load stall) resumes
## the bob rather than firing a burst of catch-up frames.
func tick(delta: float) -> void:
	_accum = minf(_accum + delta, 0.25)
	while _accum >= GBA_FRAME:
		_accum -= GBA_FRAME
		advance_frame()


## One GBA frame of `UpdateBobbingEffect`, source's own order: timer first,
## y step on the masked frame, sign flip every 16th. At frame 16 both fire —
## the step uses the OLD velocity, then the flip — which is what makes the
## wave a clean 0..-4 triangle rather than overshooting.
func advance_frame() -> void:
	bob_timer += 1
	if (bob_timer & interval_mask) == 0:
		bob_y += bob_velocity
	if (bob_timer & 15) == 0:
		bob_velocity = -bob_velocity
	position.y = base_y + float(bob_y)
	if body != null and is_instance_valid(body):
		body.position.y = body_base_y + float(bob_y)


## [M27E E1f] Source's `BOB_JUST_MON`: keep bobbing, stop driving the rider, and
## STOP FOLLOWING — the player is about to jump ashore without this.
##
## Both halves are one source line apart: `UpdateBobbingEffect` runs
## `playerSprite->y2 = sprite->y2` AND `sprite->x = playerSprite->x` inside the
## same `if (bobState != BOB_JUST_MON)`, so the dismount ends the rider link and
## the position link together.
##
## ⚠️ **`top_level` ALONE IS NOT ENOUGH, AND GETTING THAT WRONG TELEPORTS THE
## BLOB.** This node is a child of the player, so staying put means `top_level`
## — but `top_level` also makes `position` mean GLOBAL position, while `tick()`
## keeps writing `position.y = base_y + bob_y` from a base captured in LOCAL
## space. Without rebasing, the first bob frame after the switch snaps the blob
## to somewhere near the world origin. Rebased so the bob continues from exactly
## where it is.
func stay_behind() -> void:
	if body != null and is_instance_valid(body):
		body.position.y = body_base_y
	body = null
	if top_level:
		return
	var here := global_position
	top_level = true
	global_position = here
	# Keep the wave continuous across the coordinate-space change: the current
	# y already includes `bob_y`, so the new base is that minus the offset.
	base_y = position.y - float(bob_y)


## Undo everything: the body back on its feet, the blob gone.
func detach() -> void:
	if body != null and is_instance_valid(body):
		body.position.y = body_base_y
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
