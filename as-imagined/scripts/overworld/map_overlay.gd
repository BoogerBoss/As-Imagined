@tool
class_name MapOverlay
extends Node2D

## [M27B Change 2] The behaviour/elevation x-ray — read half.
##
## §20's validation surface, and the primary way to check importer output
## (including the §1.4 elevation mapping). Everything drawn here comes from
## `StepResolver.cell_info()`; this node re-derives nothing.
##
## **Original design.** The reference has no per-cell attribute visualiser at
## all — its overworld debug menu offers only "Warp to map warp…" and "Toggle
## Collision OFF", and the real authoring tool is porymap, external. So there is
## no source layout to port and this is judged by eye, not by fidelity.
##
## **Its own scene, never baked into a map.** Instanced conditionally, which
## keeps every shipping-gate option a one-liner and lets it survive M27C's
## retirement of pallet_town.tscn untouched. `@tool` controls editor execution
## and has nothing to do with export contents — the debug gate is the
## instancing condition (`OS.is_debug_build()`), not the annotation.
##
## Write support is Step D and is EDITOR-ONLY by design. Runtime F3 cycling is
## Step E and stays read-only.

## Vocabulary sized from measurement, not taste: 83 behaviours occur across the
## 421 imported maps, but these 12 cover **97.46%** of all cells. The remaining
## 71 share one "other" colour rather than inventing 71 more.
const DEFAULT_BEHAVIOR_COLORS := {
	0: Color(0.30, 0.34, 0.40, 0.30),    # MB_NORMAL — 62.3%, deliberately faint
	8: Color(0.45, 0.35, 0.25, 0.45),    # MB_CAVE
	21: Color(0.15, 0.35, 0.75, 0.45),   # MB_OCEAN_WATER
	2: Color(0.20, 0.65, 0.25, 0.45),    # MB_TALL_GRASS
	44: Color(0.20, 0.55, 0.85, 0.50),   # MB_FAST_WATER
	50: Color(0.75, 0.20, 0.20, 0.45),   # MB_IMPASSABLE_NORTH
	200: Color(0.70, 0.45, 0.15, 0.45),  # MB_CYCLING_ROAD_PULL_DOWN
	33: Color(0.85, 0.78, 0.45, 0.45),   # MB_SAND
	12: Color(0.55, 0.50, 0.45, 0.45),   # MB_MOUNTAIN_TOP
	59: Color(0.90, 0.65, 0.15, 0.55),   # MB_JUMP_SOUTH
	45: Color(0.35, 0.60, 0.80, 0.45),   # MB_CYCLING_ROAD_WATER
	23: Color(0.40, 0.70, 0.85, 0.45),   # MB_SHALLOW_WATER
}
const DEFAULT_OTHER_COLOR := Color(0.55, 0.30, 0.60, 0.45)

## §20's "bright magenta for untagged tiles". Measured: zero imported cells are
## untagged, so this can only ever mark a hand-painted cell whose behaviour was
## never set — or an importer regression.
const DEFAULT_UNTAGGED_COLOR := Color(1.0, 0.0, 1.0, 0.85)

const DEFAULT_COLLISION_COLOR := Color(0.85, 0.10, 0.10, 0.35)
const DEFAULT_LEDGE_COLOR := Color(1.0, 0.85, 0.20, 0.95)
const DEFAULT_REVIEW_COLOR := Color(1.0, 0.55, 0.0, 1.0)
const DEFAULT_GRID_COLOR := Color(0, 0, 0, 0.15)
const DEFAULT_TEXT_COLOR := Color(1, 1, 1, 0.85)

## [Rider 5] Layer type — the one piece of the baked routing that is otherwise
## invisible. It is NOT elevation and NOT a per-cell "which layer am I on":
## every metatile is split into a top and bottom half that go to DIFFERENT
## planes, so a cell always paints into two of the three. This mode shows which
## pair, which is what makes "why does this tile draw over me" checkable.
##
##   NORMAL  bottom -> Objects, top -> Overhangs
##   COVERED bottom -> Ground,  top -> Objects
##   SPLIT   bottom -> Ground,  top -> Overhangs
##
## SPLIT is deliberately loud: it occurs on FIVE cells in all 421 Kanto maps
## (Six Island Ruin Valley), so seeing it anywhere else is almost certainly an
## importer bug rather than a rare tile.
const DEFAULT_LAYER_TYPE_COLORS := {
	0: Color(0.30, 0.55, 0.35, 0.40),   # NORMAL
	1: Color(0.30, 0.40, 0.65, 0.40),   # COVERED
	2: Color(1.0, 0.35, 0.85, 0.75),    # SPLIT — 5 cells in all of Kanto
}
const LAYER_TYPE_NAMES := {0: "NORMAL", 1: "COVERED", 2: "SPLIT"}

## [Events mode] The baked entities made visible.
##
## Every other mode draws PER-CELL data derived from `StepResolver.cell_info()`.
## This one draws PLACED NODES, which is a genuinely different source: the
## entities are children of the MAP scene, not of the overlay, and not
## reachable from MapData at all. See `entity_root()` for how that is resolved
## and what happens when it cannot be.
const DEFAULT_ENTITY_COLORS := {
	"npc": Color(0.45, 0.65, 0.95, 0.55),
	"trainer": Color(0.95, 0.35, 0.35, 0.60),
	"item": Color(0.95, 0.80, 0.25, 0.60),
	"warp": Color(0.55, 0.40, 0.85, 0.60),
	"trigger": Color(0.30, 0.80, 0.75, 0.55),
	"sign": Color(0.70, 0.70, 0.70, 0.55),
	"other": Color(0.55, 0.30, 0.60, 0.55),
}

## One letter per kind. "R" is tRigger: T is already the trainer, and the two
## are the pair you least want to confuse when reading a route. The letters are
## a fast in-place read, not the identification — the legend spells every kind
## out, same reasoning as the behaviour legend's own "other" bucket.
const ENTITY_LETTERS := {
	"npc": "N", "trainer": "T", "item": "I",
	"warp": "W", "trigger": "R", "sign": "S", "other": "?",
}

## Containers map_baker.gd emits. TWO entity strata, split by draw priority
## rather than by kind (MetatileBehavior.ELEVATION_TO_PRIORITY), plus the
## trigger/sign container — so a walk that checks only one of them silently
## misses whatever sits at elevation 4.
const ENTITY_CONTAINERS := ["Entities_P2", "Entities_P1", "Triggers"]

## Facing step -> the resolver's own direction enum, so sight walks the same
## rules movement does instead of a second opinion about them.
const DIR_FOR_STEP := {
	Vector2i(0, 1): StepResolver.Dir.SOUTH,
	Vector2i(0, -1): StepResolver.Dir.NORTH,
	Vector2i(-1, 0): StepResolver.Dir.WEST,
	Vector2i(1, 0): StepResolver.Dir.EAST,
}

## A cell carrying more than one event.
##
## DELIBERATELY CALM, not an alarm. All 22 such cells in Kanto were read —
## every one, not a sample — and each is deliberate authoring, across SIX
## idioms rather than the three an earlier five-cell reading claimed:
##
##   warp + sign (5)         a door that is also readable — Viridian City 36,10
##   gated triggers (6)      paired coord_events on one VAR at DIFFERENT
##                           values, so exactly one can match. Two maps, not
##                           one: Route 22's three Early(1)/Late(3) rival
##                           triggers, and Oak's Lab's three
##                           LeaveStarterScene(2)/RivalBattle(3) — the opening
##                           sequence of the game.
##                           Exclusivity is guaranteed twice over, and the
##                           value is the half that matters: a shared var NAME
##                           proves nothing on its own. The engine also stops
##                           at the first match — GetCoordEventScriptAtPosition
##                           (field_control_avatar.c:1180-1196) returns as soon
##                           as TryRunCoordEventScript yields a script — so
##                           even a same-value pair could not double-fire; the
##                           second would simply be dead. Note the elevation
##                           gate on the same loop: Route 22 (33,6) sits at
##                           elevation 0, ELEVATION_TRANSITION, the wildcard.
##   scriptless actors (4)   cutscene NPCs parked on a warp — Indigo Plateau
##   hidden item beneath
##     an obstacle (4)       Snorlax on ITEM_LEFTOVERS (Routes 12 and 16),
##                           Mr Fuji on ITEM_SOOTHE_BELL, Giovanni on
##                           ITEM_MACHO_BRACE — collect it once they move
##   readable prop (2)       OBJ_EVENT_GFX_CLIPBOARD with script 0x0 supplying
##                           the VISUAL, a bg_event sign supplying the TEXT
##   trigger under an NPC(1) PokemonTower_5F's Channeler on a VAR_TEMP_1 zone
##
## The last three were missed by the original reading, and they are exactly the
## ones a loud marker would misrepresent: a hidden item under Snorlax looks
## like a duplicate placement and is nothing of the kind. Shouting about a
## normal idiom on 18 of 419 maps would train the eye to skip the marker, which
## is the failure this overlay exists to avoid. It is here so a stack is
## VISIBLE and clickable, not so it looks wrong.
const DEFAULT_STACK_COLOR := Color(0.90, 0.92, 1.0, 0.85)

## A warp whose destination map exists but has no baked scene. This is the
## dangling-stem mark: the 22 unbaked interiors become a visible warning on the
## map they are missing from, instead of a surprise when M27C wires stitching up.
const DEFAULT_DEAD_WARP_COLOR := Color(1.0, 0.45, 0.0, 0.85)

## A warp naming a constant source does not define. Deliberately the same
## shout-loudly magenta as an untagged cell, and for the same reason: this can
## only be an importer regression, never an expected gap.
const DEFAULT_BROKEN_WARP_COLOR := Color(1.0, 0.0, 1.0, 0.90)

const CELL := 16

## EVENTS is appended, never inserted: `mode` is exported and serialises as an
## INT, so re-ordering this enum would silently repoint every saved overlay.
## Appending also joins it to `next_mode()`'s cycle for free.
## ⚠️ APPENDED, never reordered — `mode` is a serialised @export, so renumbering
## the existing six would silently change what an already-open scene is set to.
enum Mode { OFF, BEHAVIOR, MOVEMENT, PROVENANCE, LAYER_TYPE, EVENTS, CONNECTIONS }


# ------------------------------------------------------- appearance (live)
#
# The DEFAULT_* tables above are the measured starting point, not a decision
# nobody may revisit -- an x-ray is judged by eye, so it has to be tunable
# while you are looking at the map rather than by editing a const and waiting
# for a reload. Every value below defaults to its DEFAULT_* twin, so an
# untouched overlay is pixel-identical to before and nothing is serialised
# into a scene until you actually move something.

## Scales the alpha of every FILL. 1.0 is the measured default; drop it to see
## the map art through the overlay, raise it to read the fills at a glance.
## Deliberately does not touch text, arrows, grid or the legend -- dimming the
## thing you are trying to read is never what "less intense" means.
@export_range(0.0, 2.0, 0.05) var fill_opacity: float = 1.0:
	set(value):
		fill_opacity = value
		queue_redraw()

@export_group("Colours")
## Merged OVER the built-in behaviour table, so you can retint one behaviour
## without restating the other eleven. Keys are MB_* ids (see MetatileBehavior).
@export var behavior_color_overrides: Dictionary = {}:
	set(value):
		behavior_color_overrides = value
		queue_redraw()

@export var other_color: Color = DEFAULT_OTHER_COLOR:
	set(value):
		other_color = value
		queue_redraw()

@export var untagged_color: Color = DEFAULT_UNTAGGED_COLOR:
	set(value):
		untagged_color = value
		queue_redraw()

@export var collision_color: Color = DEFAULT_COLLISION_COLOR:
	set(value):
		collision_color = value
		queue_redraw()

@export var ledge_color: Color = DEFAULT_LEDGE_COLOR:
	set(value):
		ledge_color = value
		queue_redraw()

@export var review_color: Color = DEFAULT_REVIEW_COLOR:
	set(value):
		review_color = value
		queue_redraw()

@export var dead_warp_color: Color = DEFAULT_DEAD_WARP_COLOR:
	set(value):
		dead_warp_color = value
		queue_redraw()

@export var broken_warp_color: Color = DEFAULT_BROKEN_WARP_COLOR:
	set(value):
		broken_warp_color = value
		queue_redraw()

@export var grid_color: Color = DEFAULT_GRID_COLOR:
	set(value):
		grid_color = value
		queue_redraw()

@export var text_color: Color = DEFAULT_TEXT_COLOR:
	set(value):
		text_color = value
		queue_redraw()
@export_group("")


## A behaviour's fill, with any override applied. Not opacity-scaled -- callers
## do that, so the legend can show the true hue at full strength.
func behavior_color(beh: int) -> Color:
	if behavior_color_overrides.has(beh):
		return behavior_color_overrides[beh]
	return DEFAULT_BEHAVIOR_COLORS.get(beh, other_color)


func layer_type_color(lt: int) -> Color:
	return DEFAULT_LAYER_TYPE_COLORS.get(lt, other_color)


# ------------------------------------------------------ events mode (read)


## The node whose children the entities hang off. Null when there is none —
## events mode says so in the legend rather than drawing an empty map, because
## "this map has no events" and "the overlay cannot see any events" look
## identical otherwise and mean completely different things.
func entity_root() -> Node:
	if map_root != null and is_instance_valid(map_root):
		return map_root
	return get_parent()


## True when the resolved root actually looks like a baked map. Distinguishes
## a legitimately empty map from a misplaced overlay.
func has_entity_source() -> bool:
	var root := entity_root()
	if root == null:
		return false
	for c in ENTITY_CONTAINERS:
		if root.get_node_or_null(NodePath(c)) != null:
			return true
	return false


## Every placed event on the map, across both elevation strata.
func entities() -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	var root := entity_root()
	if root == null:
		return out
	for c in ENTITY_CONTAINERS:
		var n := root.get_node_or_null(NodePath(c))
		if n == null:
			continue
		for child in n.get_children():
			if child is OverworldEntity:
				out.append(child)
	return out


## Everything on a cell, in the order the containers are walked. Usually one,
## occasionally more — 22 cells across Kanto, every one deliberate.
func entities_at(cell: Vector2i) -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	for e in entities():
		if e.cell == cell:
			out.append(e)
	return out


## Which entity a click on `cell` should select, given what is selected now.
## Null when the cell is empty.
##
## PURE, AND THAT IS THE POINT. The plugin's click path is editor-only and so
## cannot be tested headlessly — Section L exists precisely because an
## editor-only path once shipped broken and nothing noticed. Keeping the
## decision here leaves the untestable half with nothing to get wrong but the
## act of selecting, and puts the part with actual behaviour (wrap-around,
## first-click, a selection that has moved elsewhere) on the tested side.
##
## Cycling rather than always-first is what makes a stacked cell reachable at
## all: clicking the Gym door repeatedly walks warp -> sign -> warp.
func next_in_stack(cell: Vector2i, current: Node) -> OverworldEntity:
	var stack := entities_at(cell)
	if stack.is_empty():
		return null
	for i in range(stack.size()):
		if stack[i] == current:
			return stack[(i + 1) % stack.size()]
	# Nothing here is selected — including the case where the selection is on
	# some other cell entirely, which is the ordinary first click.
	return stack[0]


## Which marker an entity gets.
##
## TrainerNPC is checked BEFORE NPC and the order is load-bearing: TrainerNPC
## EXTENDS NPC, so an `is NPC` test matches trainers too and would file every
## trainer on the map as a plain person — the exact distinction the importer's
## own three-way object_events split exists to make.
func entity_kind(e: OverworldEntity) -> String:
	if e is TrainerNPC:
		return "trainer"
	if e is ItemBall:
		return "item"
	if e is NPC:
		return "npc"
	if e is Warp:
		return "warp"
	if e is Trigger:
		return "trigger"
	if e is Sign:
		return "sign"
	return "other"


## Where a warp actually leads. Three outcomes, deliberately kept apart:
##
##   "baked"    the destination exists and has a scene — a working door.
##   "unbaked"  a real map, not yet baked. The expected M27C gap, and the
##              whole point of drawing this: 22 known interiors, made visible.
##   "unknown"  source defines no such constant. Not a gap — an importer bug.
## Why a trainer does or does not get a sight line. Four outcomes, and keeping
## them apart is the whole point: once rays are conditional, "no ray" has
## several meanings and they are NOT interchangeable when you are judging
## whether a route is passable.
##
##   "shown"    fixed facing, real range, at least one cell visible.
##   "rotates"  rotates in place or walks. Source resolves its facing from
##              live object state at the moment of the check; there is no
##              single correct line to draw, so none is drawn.
##   "blind"    fixed facing but sight_range 0 — 22 real Kanto trainers.
##              Genuinely cannot see, which is a fact worth showing.
##   "blocked"  fixed facing, real range, but a wall immediately in front.
##              The corridor is empty, and that is a finding, not a gap.
##   "unknown"  movement_type is not a type source defines — i.e. a typo,
##              almost certainly from hand-editing it in the inspector.
func trainer_sight_state(t: TrainerNPC) -> String:
	if t == null:
		return "unknown"
	if not MovementTypes.is_known(t.movement_type):
		return "unknown"
	if not MovementTypes.has_fixed_facing(t.movement_type):
		return "rotates"
	if t.sight_range <= 0:
		return "blind"
	return "shown" if trainer_sight_cells(t).size() > 0 else "blocked"


## The cells this trainer actually catches the player on.
##
## NOT simply `sight_range` cells in a line, and NOT merely truncated at the
## collision bit — that was this function's first shipped form and it drew
## some rays too long.
##
## `CheckPathBetweenTrainerAndPlayer` (trainer_see.c:708-742) walks the tiles
## between trainer and player calling `GetCollisionFlagsAtCoords`, and abandons
## the check on ANY returned flag except OUTSIDE_RANGE. Quoted from the read
## body rather than paraphrased, because the width of this mask is the single
## fact the whole truncation rests on:
##
##     for (i = 0; i < approachDistance - 1; i++, MoveCoords(direction, &x, &y))
##     {
##         collision = GetCollisionFlagsAtCoords(trainerObj, x, y, direction);
##         if (collision != 0 && (collision & ~(1 << (COLLISION_OUTSIDE_RANGE - 1))))
##             return 0;
##     }
##
## Only OUTSIDE_RANGE is tolerated — so ELEVATION_MISMATCH and OBJECT_EVENT
## both end the line. Had the mask been wider, rays would now truncate too
## SHORT on split-elevation maps, which is a quieter wrong than too-long.
##
## The tail confirms the excluded-terminating-cell choice below: after the
## loop, source checks the final cell with `GetCollisionAtCoords` and returns
## a hit only for `collision == COLLISION_OBJECT_EVENT` — the player has to be
## standing there.
##
## That function (event_object_movement.c:6561) raises FOUR flags, so three
## things stop a sight line besides the plain collision bit:
##   - IMPASSABLE also covers `IsMetatileDirectionallyImpassable` — the §1.7
##     two-sided rule, which a raw collision read misses entirely.
##   - ELEVATION_MISMATCH — a trainer does not see across a stratum boundary.
##   - OBJECT_EVENT — another NPC standing in the line blocks it.
##
## So the walk goes through `StepResolver.resolve()` rather than reading cells:
## the resolver already ports the first three, and re-deriving them here would
## let the drawn line disagree with the movement rules it is supposed to
## describe. Only the object-event check is added on top, because the resolver
## models terrain and knows nothing about placed entities.
##
## LEDGES STOP SIGHT, and the reason is worth stating because `resolve()` says
## otherwise. It tests ledges BEFORE the collision bit and reports LEDGE_JUMP,
## a redirect rather than a block — correct for walking, wrong for looking.
## Source has no such special case: it reads the collision bit, and every jump
## tile in Kanto carries one — measured across ALL 421 imported maps and all
## eight MB_JUMP_* behaviours: EAST 39, WEST 41, SOUTH 962, and **1042 of 1042
## carry collision = 1, with no exception anywhere**. NORTH and all four
## diagonals occur zero times, matching StepResolver's own note. So any outcome
## other than NONE ends the line.
##
## (An earlier figure here read "155 of 155 sampled". That sweep covered 80
## maps and used ids 59-62 — JUMP_SOUTH plus three DIAGONALS — so it missed
## east and west entirely, the two directions the resolver says are in use.
## The conclusion survived re-measurement; the sample did not support it.) An earlier comment here asserted the exact
## opposite — that ledges are not collisions and sight passes over them — which
## was wrong on both halves while the code happened to behave correctly.
##
## One disclosed departure from source's own loop: source never collision-checks
## the player's OWN cell, because the player is standing in it. Here the
## terminating cell is excluded, since nobody can stand in a wall or on top of
## another NPC, so it is not a cell you can be caught on.
func trainer_sight_cells(t: TrainerNPC) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if t == null or _resolver == null or t.sight_range <= 0:
		return out
	if not MovementTypes.has_fixed_facing(t.movement_type):
		return out
	var step: Vector2i = MovementTypes.FIXED_FACING[t.movement_type]
	var dir: int = DIR_FOR_STEP[step]
	var blockers := _sight_blocking_cells()
	var c: Vector2i = t.cell
	for _i in range(t.sight_range):
		var r: Dictionary = _resolver.resolve(c, dir, t.elevation)
		if int(r["outcome"]) != StepResolver.Outcome.NONE:
			break
		c += step
		if blockers.has(c):
			break
		out.append(c)
	return out


## Cells occupied by something a sight line cannot pass through.
##
## Only the three kinds that come from source's own `object_events` array —
## `DoesObjectCollideWithObjectAt` consults that array and nothing else. Warps,
## triggers and signs live in the separate warp/coord/bg arrays, occupy no
## collision slot, and correctly do not block: a trainer sees straight over a
## doormat.
func _sight_blocking_cells() -> Dictionary:
	var out := {}
	for e in entities():
		match entity_kind(e):
			"npc", "trainer", "item":
				out[e.cell] = true
	return out


func warp_state(w: Warp) -> String:
	if w == null or w.dest_map == "":
		return "unknown"
	if MapConstants.map_name_for(w.dest_map) == "":
		return "unknown"
	return "baked" if MapConstants.is_baked(w.dest_map) else "unbaked"


## Applies `fill_opacity` to a fill colour.
func _fill(c: Color) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * fill_opacity, 0.0, 1.0))

@export var map_data: MapData:
	set(value):
		map_data = value
		_resolver = StepResolver.new(value) if value != null else null
		queue_redraw()

@export var mode: Mode = Mode.BEHAVIOR:
	set(value):
		mode = value
		_sync_previews()
		queue_redraw()

## [Events mode] Where the placed entities live.
##
## Left null, this falls back to `get_parent()`, which is correct for the
## expected placement: the overlay instanced as a child of the baked map scene.
## Set it explicitly when the overlay sits anywhere else.
##
## Nothing else in this file needs it — assigning only `map_data` keeps every
## other mode working exactly as before, which is why events mode reports its
## own absence rather than the overlay refusing to draw.
@export var map_root: Node2D = null:
	set(value):
		map_root = value
		queue_redraw()

## Drawing every cell of Viridian Forest (3,726) each frame is wasted work, so
## the draw is clipped to what is actually on screen. Left settable so a test
## can pin a region without a live camera.
@export var visible_rect_override := Rect2i()

## [Step D] The write half — EDITOR ONLY.
##
## Collision and elevation cannot be inferred for a hand-painted cell, so this
## is where they are SET, not merely inspected (§1.9). Without it there is no
## way to author a walkable building at all.
##
## Editor-only is enforced twice over: `paint()` refuses outright unless
## `Engine.is_editor_hint()`, and the clicks that reach it arrive through an
## EditorPlugin (addons/map_overlay_editor) which does not exist at runtime.
## Runtime stays strictly read-only, which is what Step E ships.
enum EditMode {
	NONE,        ## read-only x-ray, the Step C behaviour
	COLLISION,   ## click sets collision to `paint_collision` and confirms it
	ELEVATION,   ## click sets elevation to `paint_elevation` and confirms it
	AUTHOR,      ## click marks AUTHORED with INHERITED defaults, left unconfirmed
	## [M27M3] click paints `paint_metatile` into all three planes and adopts
	## the cell. Appended, not inserted: `edit_mode` is a serialised @export, so
	## renumbering the existing four would silently change what an open scene is
	## set to.
	METATILE,
}

@export var edit_mode: EditMode = EditMode.NONE:
	set(value):
		edit_mode = value
		queue_redraw()

## [M27M3] Which metatile the brush draws. A raw id rather than a picker,
## because a pair carries up to 1,024 of them and M27M6 is what turns that into
## something browsable — this is the mechanism, not the affordance.
@export var paint_metatile: int = 0


@export_range(0, 1) var paint_collision: int = 1:
	set(value):
		paint_collision = value
		queue_redraw()

## 0/1/3/4/5 are the only values that occur anywhere in Kanto, but the field is
## 0-15 in source and a hand-authored map may legitimately use another.
@export_range(0, 15) var paint_elevation: int = 3:
	set(value):
		paint_elevation = value
		queue_redraw()

var _resolver: StepResolver = null
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	queue_redraw()


## Editor-side entry point: the node is instanced first and map_data assigned
## afterwards, so redraw on any property notification rather than relying on
## _ready() having seen a map.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_POST_SAVE or what == NOTIFICATION_ENTER_TREE:
		queue_redraw()


## Cells intersecting the viewport, clamped to the map. Falls back to the whole
## map only when there is no camera and no override — acceptable for a 24x20
## test map, and never hit in normal editor/runtime use.
func _visible_cells() -> Rect2i:
	if map_data == null:
		return Rect2i()
	var full := Rect2i(0, 0, map_data.width, map_data.height)
	if visible_rect_override.size != Vector2i.ZERO:
		return visible_rect_override.intersection(full)
	# In the EDITOR, draw the whole map. get_viewport_transform() does not track
	# the 2D editor camera for a node in the edited scene, so clipping there
	# produced an empty rect and the overlay rendered nothing at all -- which is
	# exactly how this first shipped. The clip exists for the runtime case where
	# a moving camera redraws constantly; in-editor the redraw only fires when a
	# property changes, so even Viridian Forest's 3,726 cells cost nothing.
	if Engine.is_editor_hint():
		return full
	var vp := get_viewport()
	if vp == null:
		return full
	var xf := get_viewport_transform() * get_global_transform()
	var view := xf.affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	var r := Rect2i(
		Vector2i((view.position / CELL).floor()) - Vector2i.ONE,
		Vector2i((view.size / CELL).ceil()) + Vector2i.ONE * 2)
	var clipped := r.intersection(full)
	# A degenerate clip means the transform lied; better to draw everything than
	# to silently draw nothing, which reads as "the overlay is broken".
	return full if clipped.size.x <= 0 or clipped.size.y <= 0 else clipped


func _draw() -> void:
	if map_data == null or _resolver == null or mode == Mode.OFF:
		return
	var area := _visible_cells()
	var legend := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var info := _resolver.cell_info(Vector2i(x, y))
			if not info["in_bounds"]:
				continue
			_draw_cell(info)
			_note_legend(legend, info)
	# After the cell pass, so markers sit on top of the grid rather than under
	# it. In EVENTS mode `_draw_cell` contributes only that grid.
	if mode == Mode.EVENTS:
		_draw_events(area, legend)
	# ⚠️ NOT inside the cell pass above: that loop skips anything out of bounds,
	# and a neighbour is BY DEFINITION out of bounds. This is the one view that
	# draws outside the map.
	if mode == Mode.CONNECTIONS:
		_draw_connections(legend)
	_draw_legend(area, legend)


# ------------------------------------------------ [M27M5] connections view
#
# ⚠️ **CONNECTIONS ARE OTHERWISE INVISIBLE.** An edge is three numbers in a
# Dictionary — direction, map, offset — with no way to see where the neighbour
# actually lands or that two of them collide. Every seam defect this project has
# had was found by walking, because there was nothing to look at.

## Which of THIS map's connections the offset editor targets. -1 edits nothing.
@export var connection_index: int = -1:
	set(value):
		connection_index = value
		connection_offset = _offset_of(value)
		_conn_cache = {}
		queue_redraw()

## The selected connection's offset. Writing it moves the neighbour — and the
## RECIPROCAL on the neighbour's own side, which is the whole reason this is not
## just an Inspector edit of `MapData.connections`.
@export var connection_offset: int = 0:
	set(value):
		connection_offset = value
		_apply_offset(value)

## `placed_rects` loads a MapData per reachable map, which is far too much for
## a per-frame `_draw`. Rebuilt only when the mode, the selection or an offset
## changes.
var _conn_cache: Dictionary = {}

## Neighbours whose reciprocal this overlay has edited. Saved alongside our own
## MapData — ⚠️ without this, moving a seam would write one side and leave the
## other, which is the one state the connection format cannot express.
var _dirty_neighbours: Dictionary = {}


func _offset_of(idx: int) -> int:
	if map_data == null or idx < 0 or idx >= map_data.connections.size():
		return 0
	return int(map_data.connections[idx].get("offset", 0))


func _apply_offset(value: int) -> void:
	if map_data == null or connection_index < 0 \
			or connection_index >= map_data.connections.size():
		return
	var conn: Dictionary = map_data.connections[connection_index]
	if int(conn.get("offset", 0)) == value:
		return
	conn["offset"] = value
	# The other side, negated. A seam written on one side only is not a
	# half-applied edit — it is two maps that disagree about where they meet.
	var nb_name := MapConstants.map_name_for(str(conn.get("map", "")))
	var nb := _neighbour_data(nb_name)
	if nb != null:
		var want_dir: int = MapAuthoring.OPPOSITE.get(
				int(conn.get("direction", 0)), -1)
		for c in nb.connections:
			if int(c.get("direction", -1)) == want_dir \
					and MapConstants.map_name_for(str(c.get("map", ""))) \
							== map_data.map_name:
				c["offset"] = -value
				_dirty_neighbours[nb_name] = nb
	_unsaved_edits = true
	_conn_cache = {}
	_sync_previews()
	queue_redraw()


## Real neighbour tiles, so a seam can be lined up by eye.
##
## ⚠️ **DIRECT CONNECTIONS ONLY — at most four maps.** `placed_rects` reaches
## the whole graph (8 maps from Route 2, including Viridian City at 48x40), and
## instantiating all of them to look at one seam is a great deal of scene for no
## gain. The wider graph still draws as outlines, which is all it is needed
## for: spotting an overlap.
##
## ⚠️ **`owner` IS LEFT NULL, AND THAT IS THE SAFETY.** `PackedScene.pack()`
## skips a node with no owner, so a preview can never be baked into the map the
## way a hand-added MapOverlay once was (section N). Same guarantee the Overlay
## toggle and `[M27D D1]`'s entity sprites already rely on.
const PREVIEW_ROOT := "__ConnectionPreviews"


func _sync_previews() -> void:
	var existing := get_node_or_null(PREVIEW_ROOT)
	if existing != null:
		existing.free()
	if mode != Mode.CONNECTIONS or map_data == null:
		return
	var host := Node2D.new()
	host.name = PREVIEW_ROOT
	# Dimmed, so a neighbour never reads as part of THIS map — the one way a
	# preview could actively mislead rather than merely inform.
	host.modulate = Color(1, 1, 1, 0.55)
	host.z_index = -1
	add_child(host)
	if _conn_cache.is_empty():
		_conn_cache = MapAuthoring.placed_rects(map_data.map_name)
	for c in map_data.connections:
		var nb := MapConstants.map_name_for(str(c.get("map", "")))
		if nb == "" or not _conn_cache.has(nb):
			continue
		var path := "res://scenes/maps/%s.tscn" % nb
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node2D
		if inst == null:
			continue
		inst.position = Vector2((_conn_cache[nb] as Rect2i).position) * CELL
		host.add_child(inst)   # owner deliberately NOT set


func _neighbour_data(map_name: String) -> MapData:
	if map_name == "":
		return null
	if _dirty_neighbours.has(map_name):
		return _dirty_neighbours[map_name]
	var p := "res://scenes/maps/%s_data.tres" % map_name
	return load(p) as MapData if ResourceLoader.exists(p) else null


## Where every reachable map sits, in THIS map's own cell space — which is
## exactly what `placed_rects` returns, with this map at (0, 0).
func _draw_connections(legend: Dictionary) -> void:
	if map_data == null or map_data.map_name == "":
		legend["no MapData"] = untagged_color
		return
	if _conn_cache.is_empty():
		_conn_cache = MapAuthoring.placed_rects(map_data.map_name)
	if map_data.connections.is_empty():
		legend["this map has no connections"] = text_color
		return

	var font := _font if _font != null else ThemeDB.fallback_font
	var self_rect: Rect2i = _conn_cache.get(map_data.map_name,
			Rect2i(0, 0, map_data.width, map_data.height))
	for name in _conn_cache:
		var r: Rect2i = _conn_cache[name]
		var is_self: bool = name == map_data.map_name
		# ⚠️ Overlap is drawn, not just refused at creation time: an existing
		# pair can be made to collide by dragging an offset, and
		# `chunk_owning()` answers overlapping chunks nondeterministically.
		var clash := false
		if not is_self:
			for other in _conn_cache:
				if other != name and other != map_data.map_name \
						and (_conn_cache[other] as Rect2i).intersects(r):
					clash = true
		var col: Color = text_color if is_self else (
				untagged_color if clash else layer_type_color(0))
		var box := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		draw_rect(box, col, false, 2.0)
		var label: String = name
		if not is_self:
			for i in range(map_data.connections.size()):
				var c: Dictionary = map_data.connections[i]
				if MapConstants.map_name_for(str(c.get("map", ""))) == name:
					label = "[%d] %s  offset %d%s" % [i, name,
							int(c.get("offset", 0)),
							"  ⚠ OVERLAP" if clash else ""]
					if i == connection_index:
						draw_rect(box, col, false, 5.0)
		draw_string(font, box.position + Vector2(6, 16), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	# ⚠️ **A SILENT NO-OP IS THE ONE THING THIS EDITOR MUST NOT BE.**
	# `connection_offset` writes nothing unless `connection_index` names a real
	# connection, and the default is -1 — so typing an offset with nothing
	# selected changes neither the data nor the picture, and looks broken rather
	# than unselected. Say which it is.
	if connection_index < 0 or connection_index >= map_data.connections.size():
		legend["⚠ set connection_index (0-%d) before connection_offset"
				% maxi(0, map_data.connections.size() - 1)] = untagged_color
	else:
		legend["editing [%d] — offset %d" % [connection_index, connection_offset]] = text_color
	for i in range(map_data.connections.size()):
		var c: Dictionary = map_data.connections[i]
		var nm := MapConstants.map_name_for(str(c.get("map", "")))
		legend["[%d] %s off %d%s" % [i, nm if nm != "" else str(c.get("map", "?")),
				int(c.get("offset", 0)),
				"" if _conn_cache.has(nm) else "  (not baked)"]] = (
						text_color if _conn_cache.has(nm) else untagged_color)
	# Self rect is drawn above; noted so the legend explains the outline.
	legend["%s (this map)" % map_data.map_name] = text_color
	if self_rect.size == Vector2i.ZERO:
		legend["this map has no size"] = untagged_color


## [Events mode] One marker per placed entity, clipped like the cell pass.
func _draw_events(area: Rect2i, legend: Dictionary) -> void:
	if not has_entity_source():
		legend["no entity source — set map_root"] = untagged_color
		return
	var found := entities()
	if found.is_empty():
		legend["no events on this map"] = text_color
		return
	# Sight lines first, so a marker is never buried under another trainer's
	# corridor passing over it.
	for e in found:
		if e is TrainerNPC:
			_draw_sight_line(e as TrainerNPC, area, legend)
	for e in found:
		if not area.has_point(e.cell):
			continue
		var kind := entity_kind(e)
		var col: Color = DEFAULT_ENTITY_COLORS.get(kind, other_color)
		var label := kind
		var hollow := false
		# A dead door outranks its own kind colour. A warp that leads nowhere
		# is not "a warp" any more, it is the thing you need to see.
		if kind == "warp":
			match warp_state(e as Warp):
				"unbaked":
					col = dead_warp_color
					label = "warp -> NOT BAKED"
				"unknown":
					col = broken_warp_color
					label = "warp -> unknown map (importer bug)"
				_:
					label = "warp -> baked"
		elif kind == "trainer":
			var st := trainer_sight_state(e as TrainerNPC)
			# Hollow means "no line drawn", readable at a glance without
			# reading the legend; the legend then says WHY, which is the part
			# that actually differs.
			hollow = st != "shown"
			match st:
				"shown": label = "trainer (sight shown)"
				"rotates": label = "trainer (rotates/walks — no line)"
				"blind": label = "trainer (blind: sight_range 0)"
				"blocked": label = "trainer (sight blocked at 0 cells)"
				_:
					label = "trainer (UNKNOWN movement_type — typo?)"
					col = broken_warp_color
		_draw_marker(e.cell, col, str(ENTITY_LETTERS.get(kind, "?")), hollow)
		legend[label] = col

	# Stacks last, so the ring sits over every marker it encloses.
	for cell in _stacked_cells():
		if not area.has_point(cell):
			continue
		draw_rect(Rect2(Vector2(cell) * CELL, Vector2(CELL, CELL)),
				DEFAULT_STACK_COLOR, false, 2.0)
		legend["stacked events (expected)"] = DEFAULT_STACK_COLOR


## Cells holding more than one event. Ordinary authoring — see
## DEFAULT_STACK_COLOR for why this is drawn quietly.
func _stacked_cells() -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for e in entities():
		var n: int = int(seen.get(e.cell, 0)) + 1
		seen[e.cell] = n
		if n == 2:
			out.append(e.cell)
	return out


## The corridor a fixed-facing trainer actually covers, drawn as a run of
## faint cells with a solid cap on the far end so the direction reads even
## when the run is one cell long.
func _draw_sight_line(t: TrainerNPC, area: Rect2i, legend: Dictionary) -> void:
	var cells := trainer_sight_cells(t)
	if cells.is_empty():
		return
	var col: Color = DEFAULT_ENTITY_COLORS["trainer"]
	var faint := Color(col.r, col.g, col.b, col.a * 0.5)
	for c in cells:
		if not area.has_point(c):
			continue
		draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), _fill(faint))
	var last: Vector2i = cells[cells.size() - 1]
	if area.has_point(last):
		draw_rect(Rect2(Vector2(last) * CELL, Vector2(CELL, CELL)),
				Color(col.r, col.g, col.b, 0.9), false, 1.0)
	# One entry, not one per distinct sight_range: they share a colour AND a
	# meaning, and the range is already legible as the length of the drawn run.
	# Keyed per range it produced four identical swatches on Route 3 alone.
	legend["trainer sight line"] = faint


## Inset box plus its own letter, so a marker never covers the cell's own grid
## line and two adjacent entities stay individually readable.
func _draw_marker(cell: Vector2i, col: Color, letter: String,
		hollow: bool = false) -> void:
	var at := Vector2(cell) * CELL
	var box := Rect2(at + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
	if not hollow:
		draw_rect(box, _fill(col))
	# Border at full alpha: fill_opacity is for reading the map THROUGH the
	# overlay, and an entity you can no longer locate is not a dimmer entity.
	draw_rect(box, Color(col.r, col.g, col.b, 1.0), false, 1.0)
	_draw_letter(at, letter, text_color)


## [Rider 3] Records what this cell contributes to the legend.
##
## Built from the cells actually drawn rather than from a fixed key, because a
## fixed key is wrong in both directions: it lists 12 behaviours when Pallet
## Town has four, and it silently omits the ones that matter. The tail is where
## the interesting behaviours live — signs and doors both land in the OTHER
## bucket and are indistinguishable by colour alone, so the legend is what
## makes them readable at all.
func _note_legend(legend: Dictionary, info: Dictionary) -> void:
	match mode:
		Mode.BEHAVIOR:
			var beh: int = info["behavior"]
			if info["untagged"]:
				legend["UNTAGGED (%d)" % beh] = untagged_color
			elif DEFAULT_BEHAVIOR_COLORS.has(beh) or behavior_color_overrides.has(beh):
				legend[str(info["behavior_name"])] = behavior_color(beh)
			else:
				# Named individually even though they share one colour — that
				# shared colour is exactly why the name has to be spelled out.
				legend["%s  (other)" % info["behavior_name"]] = other_color
		Mode.MOVEMENT:
			if info["collision"] != 0:
				legend["blocked"] = collision_color
			else:
				legend["elevation %d" % info["elevation"]] = text_color
			if info["ledge_dir"] != -1:
				legend["ledge"] = ledge_color
			if not info["exits_blocked"].is_empty() or not info["entries_blocked"].is_empty():
				legend["one-way edge"] = Color(1.0, 0.25, 0.25, 0.9)
		Mode.PROVENANCE:
			if info["needs_review"]:
				legend["needs review"] = review_color
			elif info["provenance"] == MapData.Provenance.AUTHORED:
				legend["authored"] = Color(0.2, 0.6, 1.0, 0.30)
			if not info["collision_explicit"]:
				legend["c = collision is a guess"] = review_color
			if not info["elevation_explicit"]:
				legend["e = elevation is a guess"] = review_color
		Mode.LAYER_TYPE:
			var lt: int = info["layer_type"]
			legend[str(LAYER_TYPE_NAMES.get(lt, "layer %d" % lt))] = layer_type_color(lt)


## [M27M5] Hide the legend without leaving the mode.
##
## ⚠️ The legend is anchored to the VISIBLE area, not the map, so it follows the
## camera and lands on whatever you are working on rather than sitting in one
## place you can learn to avoid. Turning it off is the cheap half of the fix;
## a configurable corner and moving the colour key off-canvas are still open.
##
## The counters go with it, deliberately: hiding the key and leaving two banners
## behind would not clear the space, which is the entire point.
@export var show_legend: bool = true:
	set(value):
		show_legend = value
		queue_redraw()


func _draw_legend(area: Rect2i, legend: Dictionary) -> void:
	if legend.is_empty() or not show_legend:
		return
	# Sorted so the same view always produces the same legend — an arbitrary
	# row-major-first-seen order would make it shuffle as the camera moves.
	var labels := legend.keys()
	labels.sort()

	const PAD := 4.0
	const ROW := 12.0
	const SWATCH := 9.0
	var font := _font if _font != null else ThemeDB.fallback_font
	var widest := 0.0
	for l in labels:
		widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x)

	var origin := Vector2(area.position) * CELL + Vector2(PAD, PAD)
	var box := Rect2(origin, Vector2(SWATCH + PAD * 3 + widest, PAD * 2 + ROW * labels.size()))
	draw_rect(box, Color(0, 0, 0, 0.72))
	draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)

	var y := origin.y + PAD
	for l in labels:
		draw_rect(Rect2(origin.x + PAD, y + 1.5, SWATCH, SWATCH), legend[l])
		draw_string(font, Vector2(origin.x + PAD * 2 + SWATCH, y + ROW - 2.5), l,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.92))
		y += ROW

	_draw_review_banner(Vector2(origin.x, box.end.y + PAD), font)
	if mode == Mode.EVENTS:
		_draw_events_banner(Vector2(origin.x, box.end.y + PAD + 16.0), font)


## [Step D] "N cells carry unconfirmed defaults", always visible while editing.
##
## Deliberately drawn even at zero, and in a calm colour there, because "0" is
## a real and useful answer — it is the difference between "nothing to review"
## and "the counter isn't wired up", which are otherwise indistinguishable.
func _draw_review_banner(at: Vector2, font: Font) -> void:
	# Shown while editing, and in PROVENANCE mode always -- the count is the
	# numeric form of exactly what that mode draws, so splitting them would be
	# arbitrary, and editor-only made it unobservable at runtime.
	if not Engine.is_editor_hint() and mode != Mode.PROVENANCE:
		return
	var n := review_count()
	var text := "%d cells carry unconfirmed defaults" % n
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var box := Rect2(at, Vector2(w + 8.0, 14.0))
	draw_rect(box, Color(0, 0, 0, 0.72))
	draw_rect(box, review_color if n > 0 else Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(font, at + Vector2(4.0, 10.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			review_color if n > 0 else Color(1, 1, 1, 0.75))
	_draw_unsaved_banner(at + Vector2(0.0, 16.0), font)


## The dirty indicator. Drawn whenever there are unsaved edits and NOT drawn
## otherwise — an always-present "saved" badge would be one more thing to stop
## reading, and the state that matters is the dangerous one.
##
## Deliberately not folded into the review banner above: that counts cells whose
## MOVEMENT RULES are a guess, which is a property of the data and survives a
## save. This says the file is behind the view, which is a property of the
## session and vanishes on one. Same box would conflate a standing backlog with
## work about to be lost.
##
## Loud on purpose, and this is the one place in the overlay where loud is
## right: painting no longer writes to disk, Godot cannot reliably intercept
## scene close, and the cost of missing it is a whole painting session.
func _draw_unsaved_banner(at: Vector2, font: Font) -> void:
	if not _unsaved_edits:
		return
	var text := "UNSAVED EDITS — use Save Map Data in the 2D toolbar"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var box := Rect2(at, Vector2(w + 8.0, 14.0))
	draw_rect(box, Color(0, 0, 0, 0.85))
	draw_rect(box, review_color, false, 2.0)
	draw_string(font, at + Vector2(4.0, 10.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, review_color)


## Everything the events banner reports, in one pass.
##
## Split into two groups on purpose, and the split is the whole design:
## `pending` is work that has not happened yet and is CORRECT to see today,
## `defects` cannot be anything but a mistake. A banner that rendered "5 dead
## doors" — the expected state of every corridor map until M27C stitches them —
## in the same colour as a real fault would be the cry-wolf problem the marker
## colours already avoid, one level up.
func events_counts() -> Dictionary:
	var c := {
		"trainers": 0, "sight_lines": 0, "dead_doors": 0, "stacked": 0,
		"broken_warps": 0, "typo_trainers": 0,
	}
	for e in entities():
		match entity_kind(e):
			"trainer":
				c["trainers"] += 1
				match trainer_sight_state(e as TrainerNPC):
					"shown": c["sight_lines"] += 1
					"unknown": c["typo_trainers"] += 1
			"warp":
				match warp_state(e as Warp):
					"unbaked": c["dead_doors"] += 1
					"unknown": c["broken_warps"] += 1
	c["stacked"] = _stacked_cells().size()
	return c


## Gated to EVENTS specifically, as a SIBLING of the review banner rather than
## by widening its gate. The two answer different questions — that one counts
## unconfirmed CELL defaults and belongs to PROVENANCE, this one counts EVENTS —
## so a shared gate would put each banner on screen in a mode where its own
## numbers describe nothing being drawn.
func _draw_events_banner(at: Vector2, font: Font) -> void:
	var c := events_counts()
	var calm := "%d trainers · %d sight lines · %d dead doors (pending M27C) · %d stacked" % [
			c["trainers"], c["sight_lines"], c["dead_doors"], c["stacked"]]
	var faults: int = int(c["broken_warps"]) + int(c["typo_trainers"])
	var w := font.get_string_size(calm, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var fault_text := ""
	if faults > 0:
		fault_text = "  ⚠ %d broken warp / %d typo'd movement_type" % [
				c["broken_warps"], c["typo_trainers"]]
		w += font.get_string_size(fault_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x

	var box := Rect2(at, Vector2(w + 8.0, 14.0))
	draw_rect(box, Color(0, 0, 0, 0.72))
	# The border is the at-a-glance verdict: calm unless something is actually
	# wrong. Pending work never colours it.
	draw_rect(box, review_color if faults > 0 else Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(font, at + Vector2(4.0, 10.5), calm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.85))
	if faults > 0:
		draw_string(font, at + Vector2(4.0 + font.get_string_size(
					calm, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, 10.5),
				fault_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, review_color)


func _draw_cell(info: Dictionary) -> void:
	var cell: Vector2i = info["cell"]
	var at := Vector2(cell) * CELL
	var box := Rect2(at, Vector2(CELL, CELL))

	match mode:
		Mode.BEHAVIOR:
			draw_rect(box, _fill(untagged_color if info["untagged"]
					else behavior_color(info["behavior"])))
			if info["ledge_dir"] != -1:
				_draw_ledge_arrow(at, info["ledge_dir"])
		Mode.MOVEMENT:
			if info["collision"] != 0:
				draw_rect(box, _fill(collision_color))
			_draw_blocked_edges(at, info)
			if info["ledge_dir"] != -1:
				_draw_ledge_arrow(at, info["ledge_dir"])
			# Elevation letter. Only 5 values occur in Kanto (0/1/3/4/5), and 0
			# means "unconstrained here" rather than a floor, so it is dimmed
			# rather than shouted — it is 56% of the region.
			#
			# [Rider 4] Skipped entirely on a blocked cell. A blocked cell's
			# elevation carries no information — measured on Pallet Town, all
			# 198 blocked cells are elevation 0 and they are EXACTLY the
			# elevation-0 set — so drawing it put a meaningless dim "0" over
			# 41% of the map, on top of the red fill that already said the
			# useful thing.
			if info["collision"] == 0:
				var e: int = info["elevation"]
				var col := text_color
				if info["elevation_wildcard"]:
					col = Color(text_color.r, text_color.g, text_color.b, 0.35)
				_draw_letter(at, str(e), col)
		Mode.PROVENANCE:
			if info["provenance"] == MapData.Provenance.AUTHORED:
				draw_rect(box, _fill(Color(0.2, 0.6, 1.0, 0.30)))
			# The 13%: a painted cell whose movement rules are still a guess.
			if info["needs_review"]:
				draw_rect(box, review_color, false, 2.0)
				_draw_letter(at, "?", review_color)
			else:
				var marks := ""
				if not info["collision_explicit"]:
					marks += "c"
				if not info["elevation_explicit"]:
					marks += "e"
				if marks != "":
					_draw_letter(at, marks, review_color)
		Mode.LAYER_TYPE:
			draw_rect(box, _fill(layer_type_color(info["layer_type"])))
	draw_rect(box, grid_color, false, 1.0)


## Edges a step is refused through, drawn on the side it applies to. This is the
## two-sided rule made visible: a tile can be leavable one way and un-enterable
## the other, which is invisible in the rendered map and easy to get wrong.
func _draw_blocked_edges(at: Vector2, info: Dictionary) -> void:
	var c := Color(1.0, 0.25, 0.25, 0.9)
	for dir in info["exits_blocked"]:
		match dir:
			StepResolver.Dir.NORTH:
				draw_line(at, at + Vector2(CELL, 0), c, 2.0)
			StepResolver.Dir.SOUTH:
				draw_line(at + Vector2(0, CELL), at + Vector2(CELL, CELL), c, 2.0)
			StepResolver.Dir.WEST:
				draw_line(at, at + Vector2(0, CELL), c, 2.0)
			StepResolver.Dir.EAST:
				draw_line(at + Vector2(CELL, 0), at + Vector2(CELL, CELL), c, 2.0)


## Only S/W/E occur in Kanto — MB_JUMP_NORTH and all four diagonals are defined
## in source but never placed, so no arrow is drawn for them (they would render
## correctly if a hand-painted map ever used one).
func _draw_ledge_arrow(at: Vector2, dir: int) -> void:
	var c := at + Vector2(CELL, CELL) * 0.5
	var tip := c
	match dir:
		StepResolver.Dir.SOUTH: tip = c + Vector2(0, 5)
		StepResolver.Dir.NORTH: tip = c + Vector2(0, -5)
		StepResolver.Dir.WEST: tip = c + Vector2(-5, 0)
		StepResolver.Dir.EAST: tip = c + Vector2(5, 0)
	var perp := Vector2(tip.y - c.y, c.x - tip.x) * 0.6
	draw_polygon([tip, c - (tip - c) * 0.3 + perp, c - (tip - c) * 0.3 - perp],
			[ledge_color, ledge_color, ledge_color])


func _draw_letter(at: Vector2, s: String, col: Color) -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	draw_string(_font, at + Vector2(3, CELL - 4), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


## Cycles the read-only modes. Step E wires this to F3; kept here so the
## mode set has one owner.
func next_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


# ---------------------------------------------------------------- write half


## Applies the current edit mode to one cell. Returns true if anything changed.
##
## Refuses outright outside the editor. That is not belt-and-braces over the
## plugin gate — it is the gate that survives someone instancing this node into
## a shipped scene, which has already happened once.
func paint(cell: Vector2i) -> bool:
	if not Engine.is_editor_hint():
		return false
	return apply_edit(cell)


## The edit itself, without the editor gate.
##
## Split out so the dispatch is testable: `paint()`'s gate is absolute by
## design and a headless test run is not the editor, so testing through it
## could only ever assert "it refused". Adding a bypass seam to the gate would
## defeat the gate; adding one BELOW it does not — nothing outside this file
## calls this, and `paint()` remains the only public way in.
func apply_edit(cell: Vector2i) -> bool:
	if map_data == null or edit_mode == EditMode.NONE:
		return false
	if not map_data.in_bounds(cell.x, cell.y):
		return false

	# `changed` must cover every field the setters touch, not just the one the
	# eye is on. Each `set_*` writes a VALUE, an EXPLICIT BIT, and PROVENANCE —
	# `snapshot_cells()` has always captured all four arrays for exactly that
	# reason, but this predicate only asked about the first two, so a paint that
	# flipped provenance alone reported "nothing happened": no dirty flag, no
	# undo entry, and a mutation that still reached disk on the next deliberate
	# save. Measured on a real editing pass, 8 of 38 authored cells arrived that
	# way — every one of them a repaint of a value that was already correct.
	#
	# Silent is the problem, not the flip. An IMPORTED cell going AUTHORED is
	# what makes `map_baker` refuse to re-bake without `--force`, so a gesture
	# that changed nothing visible could quietly make a map un-re-bakeable.
	var changed := false
	match edit_mode:
		EditMode.COLLISION:
			changed = (map_data.collision_at(cell.x, cell.y) != paint_collision
					or not map_data.collision_is_explicit(cell.x, cell.y)
					or not map_data.is_authored(cell.x, cell.y))
			map_data.set_collision(cell.x, cell.y, paint_collision)
		EditMode.ELEVATION:
			changed = (map_data.elevation_at(cell.x, cell.y) != paint_elevation
					or not map_data.elevation_is_explicit(cell.x, cell.y)
					or not map_data.is_authored(cell.x, cell.y))
			map_data.set_elevation(cell.x, cell.y, paint_elevation)
		EditMode.AUTHOR:
			changed = map_data.author_cell_with_defaults(cell.x, cell.y)
		EditMode.METATILE:
			# ⚠️ THE TILES AND THE RULES MOVE TOGETHER, and the ordering is the
			# whole reason this is one arm rather than "paint, then sync".
			# `MapManager.paint_metatile` refuses an id the pair cannot route,
			# having drawn nothing — so adopting only after it succeeds keeps
			# `MapData` from claiming a metatile the map does not show.
			var root := entity_root() as Node2D
			if root != null and MapManager.paint_metatile(
					root, cell, paint_metatile, map_data.atlas):
				adopt_cell(cell, paint_metatile)
				changed = true
			else:
				changed = false

	if changed:
		_unsaved_edits = true
		queue_redraw()
	return changed


# ------------------------------------------------- [M27M4] painted-tile sync
#
# Hand-painting happens in Godot's own TileMap editor, which knows nothing
# about this project: it writes tiles into the three plane layers and never
# touches `MapData`. So a freshly painted map RENDERS correctly and PLAYS
# inert — no encounters, no ledges, no surf — because `StepResolver` reads
# `MapData.behavior`/`collision`/`elevation` and nothing has written them.
#
# ⚠️ THIS IS A PULL, NOT A HOOK, AND THAT IS DELIBERATE. There is no signal
# for "the user painted a tile", and polling the scene every frame in the
# editor is exactly the per-cell cost that made the collision-paint path stall
# for ~5 s. So the author asks for it, the same way `Save Map Data` is asked
# for. It also means Godot's own TileMap undo and this project's undo never
# fight over one gesture.

## The three plane layers, in source-id order, as painted by `map_baker`.
## Aliased rather than re-listed — `MapManager` owns the paint rule the brush
## shares, so it owns the plane order too.
const PLANE_LAYER_NAMES := MapManager.PLANE_LAYER_NAMES


## What the SCENE is currently showing at a cell.
##
## Returns `{"id": int, "planes": int, "conflict": bool}` — `id` is -1 when
## nothing is painted there.
##
## ⚠️ A metatile routes to ONE OR TWO of the three planes (§1.6), never all
## three, so "read the Ground layer" is wrong for the 62% of Kanto metatiles
## that are NORMAL and put nothing on ground at all. Every plane is read, and
## the first painted one answers.
##
## `conflict` is the case worth naming: two planes of one cell showing
## DIFFERENT metatiles. That cannot happen from a correct paint and means the
## author placed two tiles into one cell by hand. Reported rather than
## silently resolved, because either answer would be a guess.
func read_painted(cell: Vector2i) -> Dictionary:
	var out := {"id": -1, "planes": 0, "conflict": false}
	var root := entity_root()
	if root == null or not is_instance_valid(root):
		return out
	for plane in range(PLANE_LAYER_NAMES.size()):
		var layer := root.get_node_or_null(PLANE_LAYER_NAMES[plane]) as TileMapLayer
		if layer == null:
			continue
		var sid := layer.get_cell_source_id(cell)
		if sid == -1:
			continue
		var mid := AtlasLayout.metatile_id(sid, layer.get_cell_atlas_coords(cell))
		if mid < 0:
			continue
		out["planes"] = int(out["planes"]) + 1
		if int(out["id"]) == -1:
			out["id"] = mid
		elif int(out["id"]) != mid:
			out["conflict"] = true
	return out


## Cells where the scene disagrees with `MapData.metatile` — i.e. cells that
## have been painted over since the movement rules were last authored.
##
## Pure read, so it can be shown before it is acted on. An unpainted cell is
## SKIPPED rather than treated as a change: erasing every plane of a cell is
## not the same gesture as painting a different tile there, and treating a
## blank as metatile 0 would re-author the whole void margin of every interior.
func scan_painted_changes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map_data == null:
		return out
	for y in range(map_data.height):
		for x in range(map_data.width):
			var cell := Vector2i(x, y)
			var got: int = int(read_painted(cell)["id"])
			if got >= 0 and got != map_data.metatile_at(x, y):
				out.append(cell)
	return out


## Record one cell as now showing `metatile_id`: the id itself, the behaviour
## that follows from it, and a return of its movement rules to the review list.
##
## Returns false when the pair has no behaviour for that id — the cell is still
## adopted, because the metatile is a fact either way; only the behaviour is
## left alone. ⚠️ -1 is the sidecar saying "this pair does not describe that
## id", and is NOT the same as `MB_NORMAL` (0), which is 62% of the region and
## would make a missing table look like perfectly ordinary ground.
##
## Shared by the brush (M27M3) and the sync button (M27M4) rather than written
## twice: they are the same act reached two ways, and the failure of a second
## copy would be a cell that plays differently depending on how it was painted.
func adopt_cell(cell: Vector2i, metatile_id: int) -> bool:
	if map_data == null or not map_data.in_bounds(cell.x, cell.y):
		return false
	map_data.set_metatile_id(cell.x, cell.y, metatile_id)
	var beh := MapManager.behavior_for(map_data.atlas, metatile_id)
	if beh >= 0:
		map_data.set_behavior(cell.x, cell.y, beh)
	map_data.author_cell_with_defaults(cell.x, cell.y)
	return beh >= 0


## Adopt what has been painted: update the metatile, re-resolve the behaviour
## from the pair, and hand the cell's collision/elevation back to the review
## backlog.
##
## Returns a report rather than a bare count, because three of the outcomes
## need to be visible and only one of them is "it worked":
##   `changed`     cells adopted
##   `conflicts`   cells showing two different metatiles across planes
##   `unresolved`  cells whose new metatile has no behaviour in the sidecar
##
## ⚠️ THE RE-AUTHORING IS THE POINT, not the metatile write. Collision and
## elevation cannot be derived from a tile — 52.0% and 52.1% of Kanto metatiles
## appear with more than one value — so a repainted cell keeps a guess that was
## made about the tile that USED to be there. `author_cell_with_defaults()`
## clears both explicit bits, which is what puts the cell into `review_cells()`
## where a human can see it. Skipping that step is how a map ends up looking
## finished and playing wrong.
func sync_painted_cells() -> Dictionary:
	var report := {"changed": 0, "conflicts": 0, "unresolved": 0}
	if map_data == null:
		return report
	for cell in scan_painted_changes():
		var got := read_painted(cell)
		if bool(got["conflict"]):
			report["conflicts"] = int(report["conflicts"]) + 1
			continue
		if not adopt_cell(cell, int(got["id"])):
			report["unresolved"] = int(report["unresolved"]) + 1
		report["changed"] = int(report["changed"]) + 1
	if int(report["changed"]) > 0 or int(report["conflicts"]) > 0:
		_unsaved_edits = true
		queue_redraw()
	return report


## Cell under a point in this node's own local space.
func cell_at(local_pos: Vector2) -> Vector2i:
	return Vector2i((local_pos / CELL).floor())


## [Step 5] The pre-drag snapshot the undo action reverts to.
##
## Lives here, not in the plugin, for the same reason `next_in_stack()` does:
## the plugin is this project's one surface with no automated coverage, and it
## has now shipped three defects — the editor clip-rect bug, click-to-select
## disabling itself, and the save stall. Anything with a rule in it belongs on
## this side of the boundary.
##
## The rule being moved is small and load-bearing: an empty snapshot must not
## produce an undo action. `restore_cells()` early-returns on `{}`, so a
## gesture that began without a capture would commit an action that silently
## reverts nothing while leaving a healthy-looking entry in the history — the
## one failure Section R structurally cannot see, because it drives
## snapshot/restore as pure functions and never asserts WHEN they are called.
var _gesture_pre: Dictionary = {}


## Open a paint gesture. False means there is nothing to capture, and the
## caller must not create an undo action.
func begin_edit_gesture() -> bool:
	_gesture_pre = snapshot_cells()
	return not _gesture_pre.is_empty()


## Close it, handing back what the undo half should restore. Empty when the
## gesture never opened properly — the caller checks this rather than deciding.
func end_edit_gesture() -> Dictionary:
	var pre := _gesture_pre
	_gesture_pre = {}
	return pre


## Whether a gesture is currently open. Exposed so the state is assertable
## rather than inferred from behaviour.
func gesture_is_open() -> bool:
	return not _gesture_pre.is_empty()


## Everything a paint can touch, copied. Backs the editor's undo (see
## addons/map_overlay_editor/plugin.gd).
##
## All four arrays together, deliberately: a paint changes a VALUE and an
## EXPLICIT BIT and possibly PROVENANCE, and an undo that restored only the
## value would leave a cell claiming to be a confirmed decision that nobody
## made — silently re-arming the exact 13%-wrong guess §1.9 exists to keep
## visible. Restoring all four keeps the review marks and the counter honest.
##
## Whole arrays rather than a per-cell delta because a drag's cost is paid once
## on mouse-up: Viridian Forest, the largest Kanto map, is 3,726 cells, so this
## is ~15k ints — nothing next to the .tres write happening beside it.
##
## ⚠️ **[M27M4] SIX ARRAYS NOW, NOT FOUR.** `sync_painted_cells()` writes
## `metatile` and `behavior` as well, and a snapshot that captured only the
## original four would undo a sync HALF WAY: the cell would go back to its old
## collision, elevation and review state while keeping the new tile's metatile
## and behaviour — a combination nothing ever produced legitimately and which
## the overlay draws as if it were fine. Exactly the failure this docstring's
## own second paragraph already warned about for the explicit bits, arriving
## through a new writer.
func snapshot_cells() -> Dictionary:
	if map_data == null:
		return {}
	return {
		"collision": map_data.collision.duplicate(),
		"elevation": map_data.elevation.duplicate(),
		"provenance": map_data.provenance.duplicate(),
		"attr_explicit": map_data.attr_explicit.duplicate(),
		"metatile": map_data.metatile.duplicate(),
		"behavior": map_data.behavior.duplicate(),
		# ⚠️ **[M27M3] THE TILES TOO — the same half-way undo, one level up.**
		# The metatile brush is the first edit that changes the SCENE as well as
		# the data, so a snapshot of the data alone would undo the rules and
		# leave the picture painted: a cell drawn as grass that the game reads
		# as whatever was there before. `tile_map_data` is the layer's whole
		# state as one blob, which keeps this symmetric with the whole-array
		# approach above rather than inventing a per-cell tile delta.
		"tiles": _snapshot_tiles(),
	}


func _snapshot_tiles() -> Dictionary:
	var out := {}
	var root := entity_root()
	if root == null or not is_instance_valid(root):
		return out
	for name in PLANE_LAYER_NAMES:
		var layer := root.get_node_or_null(name) as TileMapLayer
		if layer != null:
			out[name] = layer.tile_map_data.duplicate()
	return out


func _restore_tiles(tiles: Dictionary) -> void:
	var root := entity_root()
	if root == null or not is_instance_valid(root):
		return
	for name in tiles:
		var layer := root.get_node_or_null(str(name)) as TileMapLayer
		if layer != null:
			layer.tile_map_data = tiles[name]


## Restores a snapshot and persists it. Called by BOTH sides of the undo
## action, so redo and undo are the same code path with different data.
##
## It saves. An undo that reverted only what you can see would leave the .tres
## holding the painted state — the view and the file silently disagreeing,
## which is the class of bug this milestone has spent its time killing.
func restore_cells(snap: Dictionary) -> void:
	if map_data == null or snap.is_empty():
		return
	map_data.collision = snap["collision"]
	map_data.elevation = snap["elevation"]
	map_data.provenance = snap["provenance"]
	map_data.attr_explicit = snap["attr_explicit"]
	# [M27M4] Guarded rather than assumed present: an undo action captured
	# before this session's snapshot grew would carry only the original four,
	# and reading a missing key would abort the restore entirely — turning a
	# stale-but-harmless undo into a broken one.
	if snap.has("metatile"):
		map_data.metatile = snap["metatile"]
	if snap.has("behavior"):
		map_data.behavior = snap["behavior"]
	if snap.has("tiles"):
		_restore_tiles(snap["tiles"])
	queue_redraw()
	_unsaved_edits = true
	# IT NO LONGER SAVES, and the removed line is worth explaining rather than
	# simply deleting, because the argument for it was sound when written.
	#
	# It read: an undo that reverted only what you can see would leave the .tres
	# holding the painted state — the view and the file silently disagreeing.
	# True, and unanswerable, GIVEN that painting itself saved. Under that
	# design the only coherent choices were "both write" or "neither writes",
	# and "both" was correct.
	#
	# Painting no longer writes (see `paint()`), so the condition the argument
	# rested on is gone: nothing puts the painted state on disk in the first
	# place, so there is nothing for an undo to leave behind. What replaces the
	# invariant is an explicit one — the file reflects the last SAVE, and
	# `_unsaved_edits` says out loud when that is not the current view.
	#
	# Undo dirties rather than saves: reverting a paint still moves memory away
	# from what is on disk, so the indicator must come on, not off.


## How many cells a human painted but never decided the movement rules for.
## Drawn on screen because 13% of inherited defaults are wrong and a count
## nobody can see is a count nobody acts on.
func review_count() -> int:
	return map_data.review_cells().size() if map_data != null else 0


## Writes the edited MapData back to the .tres the baker produced.
##
## The scene is the artifact and the JSON is a build input (Change 1), so this
## saves the RESOURCE, not the JSON — re-running the importer must not be able
## to silently reproduce over a human's decisions, and the re-import guard
## already refuses any map carrying AUTHORED cells without --force.
## True when memory has moved away from the .tres — set by any paint or undo,
## cleared only by a successful save.
##
## This is not bookkeeping, it is the thing that makes stop-saving-on-paint
## safe. Godot cannot reliably intercept scene close, so without a visible
## dirty state you can shut a map and lose a painting session with no warning,
## on exactly the hand-authored data §1.9's provenance system exists to
## protect. It ships WITH the plugin's save button for that reason; either
## alone is a trap.
##
## The editor DOES save modified external resources on its own when the scene
## is saved — measured the hard way, when 106 authored cells reached disk
## during a diagnostic that had the plugin's own save commented out. That is a
## backstop, not a guarantee: it only fires if you save the scene, so it cannot
## be what the indicator relies on.
var _unsaved_edits: bool = false


## Whether the .tres is behind the current view.
func has_unsaved_edits() -> bool:
	return _unsaved_edits


## Outcome of the most recent save_map_data(), so a caller can report the truth
## without saving a second time to find it out. `restore_cells()` is invoked
## through the undo manager, which discards return values — this is how the
## result escapes.
var last_save_error: Error = OK


func save_map_data() -> Error:
	last_save_error = _save_map_data()
	return last_save_error


func _save_map_data() -> Error:
	if map_data == null:
		return ERR_UNCONFIGURED
	# Returns the code rather than logging it. The plugin reports; a library
	# function that pushes an error every time a caller probes it makes the
	# ERROR-lines-are-failures rule (scripts/run_overworld_tests.sh) unusable.
	if map_data.resource_path.is_empty():
		return ERR_FILE_BAD_PATH
	# ⚠️ **NEIGHBOURS FIRST, AND THIS IS NOT OPTIONAL.** Moving a seam edits the
	# reciprocal on the OTHER map's resource. Saving only our own would leave
	# the two sides disagreeing about where they meet — a state the connection
	# format cannot express and nothing downstream checks, so it would surface
	# as a map that loads at the wrong place.
	for nb_name in _dirty_neighbours:
		var nb: MapData = _dirty_neighbours[nb_name]
		if nb == null or nb.resource_path.is_empty():
			continue
		var nerr := ResourceSaver.save(nb, nb.resource_path)
		if nerr != OK:
			return nerr
		_tell_editor_one_file_changed(nb.resource_path)
	var err := ResourceSaver.save(map_data, map_data.resource_path)
	if err == OK:
		_dirty_neighbours.clear()
		_unsaved_edits = false
		_tell_editor_one_file_changed(map_data.resource_path)
	return err


## Point the editor at the single file that changed.
##
## THIS IS THE FIX for the ~5-second paint stall, and the numbers are why it is
## shaped this way. The write costs 0.17-0.83 ms across the corridor's map sizes
## and there is no memory pressure, so the stall was never the save — it was the
## editor reacting to it, sweeping 30,741 watched files (21,979 of them .import
## sidecars) to discover what a one-line call can simply state.
##
## Editor-only by necessity: EditorInterface does not exist in an exported game.
## Guarded on is_editor_hint() rather than a class check, matching how the rest
## of the write half gates itself, and harmless when absent — the editor would
## just find the change the slow way, which is the behaviour we are replacing.
##
## IF THIS DOES NOT SUPPRESS THE STALL, do not paper over it with a debounce:
## a stall that fires whenever you pause to think is worse than a predictable
## one. Switch designs instead — stop saving on paint entirely, mutate in
## memory, and persist on an explicit action. That change must ship WITH a
## visible dirty indicator (the review banner is the right surface) and the
## plugin's own save affordance, because Godot cannot reliably intercept scene
## close, and without both you can lose a painting session silently. It also
## makes restore_cells()'s own save wrong — see its comment.
func _tell_editor_one_file_changed(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
