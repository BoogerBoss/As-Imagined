class_name UiLetterbox
extends RefCounted

## [M26A1 / 3:2 Phase 3] Present the Emerald-UI-Pack screens without
## distorting them.
##
## Three screens — Item/Bag, Switch/Party and Summary — are built on art from
## the Emerald UI Pack, which is **512x384**. Every one of them is laid out
## internally against a **1024x768** canvas, because that is exactly 2x the
## art: at the old 4:3 resolution the pack scaled pixel-perfectly with no
## filtering and no distortion.
##
## ⚠️ **THAT PIXEL-PERFECT 2x WAS `[M26A1]`'s WHOLE REASON FOR CHOOSING
## 1024x768, AND IT IS THE ONE THING THE 3:2 CONVERSION GENUINELY COSTS.**
## At 1200x800 the same art would scale 2.34x horizontally and 2.08x
## vertically — non-integer *and* non-uniform, i.e. blurred and stretched.
## Nothing about M26A1's reasoning was wrong; its premise simply narrowed to
## these three screens once everything else moved to real GBA-native art.
##
## So they are letterboxed: drawn at an honest integer 2x, centred, with bars
## down the sides. **Distortion is not an option** — a stretched 4:3 panel
## inside a 3:2 window looks broken in a way bars do not.
##
## ⚠️ **THIS IS A HOLDING MEASURE, AND IT IS MEANT TO BE DELETED.** Rob's
## call, 2026-08-07: the screens are re-authored at 3:2 later, against real
## FRLG art like the rest of the UI already uses. Re-authoring them *now*
## would be work thrown away, since almost no UI element here is in its final
## form. Everything lives behind this one class precisely so that removing it
## is a single deletion plus three call sites, rather than an archaeology
## exercise.


## The canvas these three screens are internally laid out against, and exactly
## 2x the pack's own 512x384 art.
##
## ⚠️ **NOT A FREE PARAMETER.** Changing it re-scales the art off an integer
## multiple, which is the exact defect this class exists to avoid. If these
## screens are ever re-authored, delete this class rather than retune it.
const DESIGN_SIZE := Vector2(1024.0, 768.0)

## The source art's own size. Kept so the 2x relationship is asserted rather
## than assumed — see `m26a1_letterbox_test`.
const SOURCE_ART_SIZE := Vector2(512.0, 384.0)


## The project's configured canvas. Read from ProjectSettings rather than from
## a live viewport so this is callable off-tree, which the tests need.
static func viewport_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))


## The bar thickness on each side. (88, 16) at 1200x800.
static func margin() -> Vector2:
	return ((viewport_size() - DESIGN_SIZE) * 0.5).floor()


## Centre `root` as a fixed `DESIGN_SIZE` box.
##
## ⚠️ **EVERY CHILD KEEPS ITS EXISTING COORDINATES, AND THAT IS THE WHOLE
## POINT OF DOING IT AT THE ROOT.** These screens' internals — anchors,
## offsets, hand-placed panels like Summary's own `GbaLayer` at (32, 64) —
## were all authored against a 1024x768 parent. Making the root *be* 1024x768
## keeps every one of them correct with no re-layout, no reparenting, and no
## edit to the `.tscn` trees. Letterboxing by any other means would have meant
## touching all three screens' internals for a change that is meant to be
## temporary.
static func apply(root: Control) -> void:
	if root == null:
		return
	root.anchor_left = 0.5
	root.anchor_top = 0.5
	root.anchor_right = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -DESIGN_SIZE.x * 0.5
	root.offset_top = -DESIGN_SIZE.y * 0.5
	root.offset_right = DESIGN_SIZE.x * 0.5
	root.offset_bottom = DESIGN_SIZE.y * 0.5
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH


## Make a full-rect child cover the whole viewport despite its parent now
## being smaller, so the bars are filled rather than transparent.
##
## ⚠️ **THE BARS MUST BE OPAQUE.** These screens are mounted as CHILD OVERLAYS
## over a live battle (`[M25h-1.4]`'s design — `BattleManager` stays alive
## underneath rather than the scene being swapped), so a transparent bar shows
## the battle still running either side of the panel. That reads as a
## rendering bug, not as a letterbox.
static func expand_to_viewport(rect: Control) -> void:
	if rect == null:
		return
	var m := margin()
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = -m.x
	rect.offset_top = -m.y
	rect.offset_right = m.x
	rect.offset_bottom = m.y
