#!/usr/bin/env python3
"""Emit healthbox screen geometry from source, and place the six panel nodes.

Sibling of `gen_battler_coords.py`, doing for the health panels exactly what
that script does for the battler sprites, and for the same reason: source
defines real screen coordinates, the canvas is a uniform 5x GBA, so placement
is arithmetic rather than judgement.

Reported from play (Rob, 2026-08-11): "the pokemon lv for the opponent clips
into the right edge of the hp background. Can you resize the entire player
panel and opponent panel to align with source scaled to our resolution".

TWO things from ONE parse, deliberately:

  1. writes `scripts/battle/healthbox_coords.gd` (the table), and
  2. rewrites the six panel nodes' anchors/offsets/scale in the two scenes.

Idempotent: re-running with unchanged source rewrites byte-identical files.

    python3 scripts/gen_healthbox_coords.py

────────────────────────────────────────────────────────────────────────────
STEP 0 FINDINGS, measured rather than assumed
────────────────────────────────────────────────────────────────────────────

⚠️ **A HEALTHBOX IS TWO 64-WIDE SPRITES, AND `sBattlerHealthboxCoords` IS THE
CENTRE OF THE LEFT ONE ONLY.** `CreateBattlerHealthboxSprites` makes a second
sprite from the same template and `SpriteCB_HealthBoxOther` pins it at
`main.x + 64` (`battle_interface.c`). So the footprint is 128 wide, but the
top-left is `centre.x - 32`, not `centre.x - 64`. Halving the wrong number
puts every box 32 GBA px (160 real px) too far left.

⚠️ **THE SINGLES PLAYER BOX IS 64 TALL AND THE OTHER THREE ARE 32, AND THAT
COMES FROM AN OAM SHAPE OVERRIDE, NOT FROM THE TEMPLATE.** All four use
`sOamData_64x32`; the player branch then does
`gSprites[...].oam.shape = ST_OAM_SQUARE`, and SQUARE at that size bit is
64x64. Reading the template alone gives 32 for all four and loses the EXP
ledge. Confirmed against the art: `healthbox_singles_player.png` is 128x64
while the other three sheets are 128x32.

⚠️ **THE ART IS INSET INSIDE THAT FOOTPRINT AND THE INSET IS NOT ZERO.**
Every sheet starts its real pixels at x=1, y=2. Measured here per file rather
than hardcoded, because it is exactly the kind of 1-2px constant that is
invisible when wrong.

⚠️ **THE PROJECT'S BOX ART IS NOT SOURCE'S ART, SO THIS MATCHES WIDTH AND
LETS HEIGHT FALL WHERE IT FALLS.** `databox_*.png` come from the vendored
Emerald UI Pack 1.2 (see `gen_databox_sprites.py`), an Essentials plugin that
REDREW the healthbox rather than upscaling it: source's singles player box is
103x36 (aspect 2.86) against the pack's 260x84 (aspect 3.10). No uniform
scale satisfies both axes, so:

  * WIDTH is matched exactly to source-at-5x, and
  * the resulting height comes out 5-15% shorter than source's.

Width wins because it is the axis that decides whether the box collides with
the field art and whether the level text has room -- which is the defect that
prompted this -- and because a non-uniform scale would distort art that is
otherwise pixel-clean. Recorded rather than silently chosen.
"""

import os
import re
import sys

from PIL import Image

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
SRC = os.path.join(REF, "src", "battle_interface.c")
GFX = os.path.join(REF, "graphics", "battle_interface")

OUT_GD = os.path.join(PROJECT, "scripts", "battle", "healthbox_coords.gd")
SCENE_SINGLES = os.path.join(PROJECT, "scenes", "battle", "battle_screen_singles.tscn")
SCENE_DOUBLES = os.path.join(PROJECT, "scenes", "battle", "battle_screen_doubles.tscn")

GBA_W, GBA_H = 240.0, 160.0

# One healthbox sprite. The box is two of these side by side.
SPRITE_W = 64

# Where the level text's RIGHT EDGE sits, in footprint pixels.
#
# `UpdateLvlInHealthbox` (`battle_interface.c:862`) prints at `32 - width` on
# the player side and `24 - width` on the opponent's, into the SECOND of the
# two sprites -- so the absolute right edge is `SPRITE_W + 32` / `SPRITE_W +
# 24`. That is a fixed edge minus the text's own width, which is why the level
# must never follow the name (see `HealthGroupPanel._position_gender_and_level`
# for the defect that came of it doing so).
#
# ⚠️ THE TWO SIDES GENUINELY DIFFER BY 8px AND THAT IS THE REPORTED BUG.
# Reported from play: "the pokemon lv for the opponent clips into the right
# edge of the hp background". The opponent panel had been authored with the
# level 38 local px further right than this rule puts it, which on the
# opponent's own (shorter) box runs it into the frame.
LEVEL_RIGHT_IN_SPRITE2 = {"player": 32, "opponent": 24}

# Which reference sheet and which OAM height each position draws with, and
# which of this project's own panel scenes stands in for it.
#   sheet         -- reference art, measured for its real inset and extent
#   sprite_h      -- 64 only for the singles player (the SQUARE override)
#   panel         -- the project's panel scene, read for its Background rect
LAYOUT = {
    "singles": {
        "B_POSITION_PLAYER_LEFT": {
            "sheet": "healthbox_singles_player",
            "sprite_h": 64,
            "panel": "health_group_panel_player",
            "node": "PlayerPanel0",
            "side": "player",
        },
        "B_POSITION_OPPONENT_LEFT": {
            "sheet": "healthbox_singles_opponent",
            "sprite_h": 32,
            "panel": "health_group_panel",
            "node": "OpponentPanel0",
            "side": "opponent",
        },
    },
    "doubles": {
        "B_POSITION_PLAYER_LEFT": {
            "sheet": "healthbox_doubles_player",
            "sprite_h": 32,
            "panel": "health_group_panel_doubles_player",
            "node": "PlayerPanel0",
            "side": "player",
        },
        "B_POSITION_PLAYER_RIGHT": {
            "sheet": "healthbox_doubles_player",
            "sprite_h": 32,
            "panel": "health_group_panel_doubles_player",
            "node": "PlayerPanel1",
            "side": "player",
        },
        "B_POSITION_OPPONENT_LEFT": {
            "sheet": "healthbox_doubles_opponent",
            "sprite_h": 32,
            "panel": "health_group_panel_doubles_opponent",
            "node": "OpponentPanel0",
            "side": "opponent",
        },
        "B_POSITION_OPPONENT_RIGHT": {
            "sheet": "healthbox_doubles_opponent",
            "sprite_h": 32,
            "panel": "health_group_panel_doubles_opponent",
            "node": "OpponentPanel1",
            "side": "opponent",
        },
    },
}


def parse_coords():
    """Pull sBattlerHealthboxCoords out of battle_interface.c."""
    text = open(SRC, encoding="utf-8").read()
    m = re.search(
        r"static const s16 sBattlerHealthboxCoords\[.*?\]\[.*?\]\[2\]\s*=\s*\{(.*?)\n\};",
        text,
        re.S,
    )
    if not m:
        sys.exit("FATAL: sBattlerHealthboxCoords not found in %s" % SRC)
    body = m.group(1)

    out = {}
    for mode_key, mode_name in (
        ("BATTLE_COORDS_SINGLES", "singles"),
        ("BATTLE_COORDS_DOUBLES", "doubles"),
    ):
        mm = re.search(
            r"\[%s\]\s*=\s*\{(.*?)\n\s*\}," % re.escape(mode_key), body, re.S
        )
        if not mm:
            sys.exit("FATAL: %s block not found" % mode_key)
        entries = re.findall(
            r"\[(B_POSITION_\w+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*\}", mm.group(1)
        )
        got = {k: (int(x), int(y)) for k, x, y in entries}
        want = set(LAYOUT[mode_name])
        if set(got) != want:
            sys.exit(
                "FATAL: %s has positions %s, this script expects %s -- source "
                "changed shape, so the layout table above needs revisiting "
                "rather than this check relaxing." % (mode_key, sorted(got), sorted(want))
            )
        out[mode_name] = got
    return out


def measure_sheet(name):
    """The real art's inset and extent inside its OAM sheet.

    Index 0 is the GBA's transparency key, so a plain alpha bbox reports the
    whole sheet -- these PNGs carry no tRNS and every pixel is 'opaque'.
    """
    im = Image.open(os.path.join(GFX, name + ".png"))
    if im.mode != "P":
        sys.exit("FATAL: %s is %s, expected an indexed sheet" % (name, im.mode))
    px = im.load()
    w, h = im.size
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y] != 0]
    if not pts:
        sys.exit("FATAL: %s is entirely index 0" % name)
    xs = [a for a, _ in pts]
    ys = [b for _, b in pts]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    return {"inset": (x0, y0), "size": (x1 - x0 + 1, y1 - y0 + 1), "sheet": (w, h)}


def panel_background_rect(panel_name):
    """The Background child's own local rect inside a panel scene.

    Read rather than hardcoded: the four variants genuinely differ (the player
    box is taller for its EXP ledge, the doubles boxes draw at half scale), and
    a copy here would be a second place to keep in step.
    """
    path = os.path.join(PROJECT, "scenes", "battle", panel_name + ".tscn")
    text = open(path, encoding="utf-8").read()
    m = re.search(
        r'\[node name="Background"[^\]]*\]\n((?:(?!\[node ).)*)', text, re.S
    )
    if not m:
        sys.exit("FATAL: no Background node in %s" % path)
    body = m.group(1)

    def off(name, default=0.0):
        mm = re.search(r"^offset_%s = (-?[\d.]+)" % name, body, re.M)
        return float(mm.group(1)) if mm else default

    left, top, right, bottom = off("left"), off("top"), off("right"), off("bottom")
    if right <= left or bottom <= top:
        sys.exit("FATAL: %s Background has a degenerate rect" % panel_name)
    return left, top, right - left, bottom - top


def solve(coords, mode, pos_key, scale):
    """Where this panel's Background must land, and at what node scale."""
    spec = LAYOUT[mode][pos_key]
    art = measure_sheet(spec["sheet"])
    cx, cy = coords[mode][pos_key]

    # ⚠️ Half of ONE sprite, not half the 128-wide footprint -- see the header.
    foot_x = cx - SPRITE_W / 2.0
    foot_y = cy - spec["sprite_h"] / 2.0
    art_x = (foot_x + art["inset"][0]) * scale
    art_y = (foot_y + art["inset"][1]) * scale
    art_w = art["size"][0] * scale
    art_h = art["size"][1] * scale

    bg_left, bg_top, bg_w, bg_h = panel_background_rect(spec["panel"])
    node_scale = art_w / bg_w  # width-matched; see the header for why

    # The level text's right edge, carried across as a FRACTION of the art's
    # own width rather than as pixels: source's box and this project's are
    # different widths, so the fraction is the part that transfers.
    lvl_frac = (
        SPRITE_W + LEVEL_RIGHT_IN_SPRITE2[spec["side"]] - art["inset"][0]
    ) / float(art["size"][0])
    return {
        "level_right": bg_left + lvl_frac * bg_w,
        "level_frac": lvl_frac,
        "node": spec["node"],
        "panel": spec["panel"],
        "gba_art": (foot_x + art["inset"][0], foot_y + art["inset"][1]) + art["size"],
        "rect": (art_x, art_y, art_w, art_h),
        "drawn_h": bg_h * node_scale,
        "source_h": art_h,
        "node_scale": node_scale,
        "bg": (bg_left, bg_top, bg_w, bg_h),
    }


def render_gd(solved, scale):
    def block(mode):
        rows = []
        for pos_key, s in solved[mode].items():
            x, y, w, h = s["gba_art"]
            rows.append(
                '\t"%s": Rect2(%g, %g, %g, %g),' % (pos_key, x, y, w, h)
            )
        return "\n".join(rows)

    return '''class_name HealthboxCoords
extends RefCounted

## Healthbox screen geometry, derived from source.
##
## ⚠️ **GENERATED BY `scripts/gen_healthbox_coords.py` -- DO NOT HAND-EDIT.**
## Re-run the generator instead; it also places the six panel nodes in
## `battle_screen_singles.tscn` / `battle_screen_doubles.tscn` from the same
## parse, which is what keeps the table and the scenes from drifting apart.
##
## Each Rect2 is the REAL ART's rectangle in GBA screen pixels on a %dx%d
## canvas -- already resolved from `sBattlerHealthboxCoords`
## (`src/battle_interface.c`, the CENTRE of the left of two 64-wide sprites)
## plus the measured inset of the art inside its own OAM sheet. Consumers
## multiply by the canvas scale and nothing else.
##
## ⚠️ **HEIGHT IS NOT MATCHED, AND THAT IS DELIBERATE.** This project draws the
## Emerald UI Pack's redrawn box art, whose aspect differs from source's by
## 5-15%%. The generator matches WIDTH exactly and lets height fall out, rather
## than distorting the art with a non-uniform scale -- see the generator's own
## header for the measurements behind that call.


## The canvas these coordinates are expressed against.
const GBA_SCREEN := Vector2(%.1f, %.1f)

## One healthbox sprite; a box is two of these side by side.
const GBA_SPRITE_WIDTH := %d


const SINGLES := {
%s
}

const DOUBLES := {
%s
}


## The art's rectangle in canvas pixels at a given uniform GBA->canvas scale.
static func rect_for(mode: Dictionary, position_key: String, scale: float) -> Rect2:
	var r: Rect2 = mode.get(position_key, Rect2())
	return Rect2(r.position * scale, r.size * scale)


## The point anchor for a healthbox's top-left, as a fraction of the canvas.
##
## Anchors rather than pixels, for the reason `BattlerCoords.anchor_for` gives:
## a fraction survives a canvas change untouched.
static func anchor_for(mode: Dictionary, position_key: String) -> Vector2:
	var r: Rect2 = mode.get(position_key, Rect2())
	return r.position / GBA_SCREEN
''' % (
        int(GBA_W),
        int(GBA_H),
        GBA_W,
        GBA_H,
        SPRITE_W,
        block("singles"),
        block("doubles"),
    )


def place_level_labels(solved):
    """Set each panel scene's own LevelLabel right edge from source's rule.

    ⚠️ ONLY `offset_right` and the alignment are touched. The label's left
    edge, font, colour and every other property stay exactly as authored --
    a RIGHT-aligned label draws from its right edge, so that is the only
    number the rule actually determines.
    """
    seen = {}
    for mode in solved:
        for s in solved[mode].values():
            seen.setdefault(s["panel"], s)

    changed = []
    for panel, s in sorted(seen.items()):
        path = os.path.join(PROJECT, "scenes", "battle", panel + ".tscn")
        text = open(path, encoding="utf-8").read()
        m = re.search(
            r'(\[node name="LevelLabel"[^\]]*\]\n)((?:(?!\[node ).)*)', text, re.S
        )
        if not m:
            sys.exit("FATAL: no LevelLabel node in %s" % path)
        body = m.group(2)
        before = re.search(r"^offset_right = (-?[\d.]+)", body, re.M)
        body = re.sub(
            r"^offset_right = .*\n", "offset_right = %.4f\n" % s["level_right"], body,
            count=1, flags=re.M,
        )
        # The alignment is what makes the right edge meaningful at all.
        if not re.search(r"^horizontal_alignment = 2$", body, re.M):
            sys.exit(
                "FATAL: %s LevelLabel is not right-aligned; the rule this "
                "script applies only means anything for a right-aligned label."
                % panel
            )
        text = text[: m.start(2)] + body + text[m.end(2) :]
        open(path, "w", encoding="utf-8").write(text)
        changed.append(
            "%-36s offset_right %s -> %.1f  (%.1f%% of the art's width)"
            % (panel, before.group(1) if before else "?", s["level_right"],
               s["level_frac"] * 100.0)
        )
    return changed


def place_nodes(scene_path, mode, solved):
    """Rewrite each panel node's anchors, offsets and scale in place.

    Only the geometry lines are touched -- every other property the scene
    authors on the instance is left exactly as written.
    """
    text = open(scene_path, encoding="utf-8").read()
    changed = []

    for pos_key, s in solved[mode].items():
        node = s["node"]
        x, y, w, h = s["rect"]
        bg_left, bg_top, bg_w, bg_h = s["bg"]
        sc = s["node_scale"]

        ax, ay = x / (GBA_W * SCALE), y / (GBA_H * SCALE)

        # ⚠️ **THE NODE'S RECT IS SIZED IN UNSCALED LOCAL UNITS, BECAUSE
        # `scale` MULTIPLIES IT AGAIN.** A Control's rendered extent is
        # `size * scale`, so writing `bg_w * sc` into the offsets draws the
        # rect at `bg_w * sc * sc` -- which is what the first cut of this
        # generator did, and `m26c1_databox_test` caught on all six nodes.
        # The OFFSETS, by contrast, position the node in its parent and are
        # NOT re-scaled, so those genuinely do carry `* sc`.
        off_l = -bg_left * sc
        off_t = -bg_top * sc

        pat = re.compile(
            r'(\[node name="%s" parent="BattleStage"[^\]]*instance=[^\]]*\]\n)'
            r"((?:(?!\[node ).)*)" % re.escape(node),
            re.S,
        )
        m = pat.search(text)
        if not m:
            sys.exit("FATAL: node %s not found in %s" % (node, scene_path))

        body = m.group(2)
        body = re.sub(
            r"^(?:anchors_preset|anchor_left|anchor_top|anchor_right|anchor_bottom"
            r"|offset_left|offset_top|offset_right|offset_bottom"
            r"|grow_horizontal|grow_vertical|scale) = .*\n",
            "",
            body,
            flags=re.M,
        )
        geom = (
            "anchor_left = %.7f\nanchor_top = %.7f\n"
            "anchor_right = %.7f\nanchor_bottom = %.7f\n"
            "offset_left = %.4f\noffset_top = %.4f\n"
            "offset_right = %.4f\noffset_bottom = %.4f\n"
            "scale = Vector2(%.7f, %.7f)\n"
        ) % (
            ax, ay, ax, ay,
            off_l, off_t, off_l + bg_w, off_t + bg_h,
            sc, sc,
        )
        text = text[: m.start(2)] + geom + body + text[m.end(2) :]
        changed.append(
            "%-14s art %6.1f,%6.1f %5.1fx%5.1f  scale %.4f  (h %.0f vs source %.0f)"
            % (node, x, y, w, s["drawn_h"], sc, s["drawn_h"], s["source_h"])
        )

    open(scene_path, "w", encoding="utf-8").write(text)
    return changed


def main():
    global SCALE
    coords = parse_coords()

    godot = open(os.path.join(PROJECT, "project.godot"), encoding="utf-8").read()

    def setting(name):
        m = re.search(r"^%s=(\d+)" % re.escape(name), godot, re.M)
        if not m:
            sys.exit("FATAL: %s not found in project.godot" % name)
        return float(m.group(1))

    w = setting("window/size/viewport_width")
    h = setting("window/size/viewport_height")
    sx, sy = w / GBA_W, h / GBA_H
    if abs(sx - sy) > 1e-6:
        sys.exit(
            "FATAL: canvas %gx%g is not a uniform GBA multiple (x=%.4f, y=%.4f). "
            "Healthbox placement is only arithmetic while it is." % (w, h, sx, sy)
        )
    SCALE = sx
    print("canvas %gx%g = uniform %.4fx GBA" % (w, h, sx))

    solved = {
        mode: {k: solve(coords, mode, k, sx) for k in LAYOUT[mode]}
        for mode in ("singles", "doubles")
    }

    os.makedirs(os.path.dirname(OUT_GD), exist_ok=True)
    open(OUT_GD, "w", encoding="utf-8").write(render_gd(solved, sx))
    print("wrote %s" % os.path.relpath(OUT_GD, PROJECT))

    for scene, mode in ((SCENE_SINGLES, "singles"), (SCENE_DOUBLES, "doubles")):
        print("  %s:" % os.path.basename(scene))
        for line in place_nodes(scene, mode, solved):
            print("    %s" % line)

    print("  level labels:")
    for line in place_level_labels(solved):
        print("    %s" % line)


if __name__ == "__main__":
    main()
