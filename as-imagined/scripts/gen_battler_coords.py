#!/usr/bin/env python3
"""Emit battler screen coordinates from source, and place the six sprite nodes.

[M26A1 / 3:2 Phase 2] Source defines exact battler screen coordinates in
`sBattlerCoords` (`src/battle_anim_mons.c`). At a uniform 5x GBA canvas
(1200x800) placing a battler is arithmetic rather than judgement, which is
what took Phase 2 from ~1.5 sessions of hand-tuning down to a derivation.

GENERATED, NOT TRANSCRIBED -- the same discipline as `metatile_behavior.gd`
and `movement_types.gd`. Eight coordinate pairs are exactly the size where
hand-copying looks safe and a single transposed digit is invisible for
months.

This script does TWO things from ONE parse, deliberately:

  1. writes `scripts/battle/battler_coords.gd` (the table), and
  2. rewrites the six sprite nodes' anchors/offsets in the two battle scenes.

Doing both from one source of truth is what stops the scene and the table
drifting apart. `m26a1_battler_geometry_test` then asserts they still agree,
so an editor drag on a sprite is caught rather than silently inherited --
this project has already paid for a hand-edited node once
(`PlayerHealthGroupD1`, see `m25h1_bottom_region_test`'s section 9).

Idempotent: re-running with unchanged source rewrites byte-identical files.

    python3 scripts/gen_battler_coords.py
"""

import os
import re
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
SRC = os.path.join(REF, "src", "battle_anim_mons.c")

OUT_GD = os.path.join(PROJECT, "scripts", "battle", "battler_coords.gd")
SCENE_SINGLES = os.path.join(PROJECT, "scenes", "battle", "battle_screen_singles.tscn")
SCENE_DOUBLES = os.path.join(PROJECT, "scenes", "battle", "battle_screen_doubles.tscn")

# The GBA screen the coordinates are expressed against.
GBA_W, GBA_H = 240.0, 160.0

# A battler sprite is 64x64 on hardware. The box is kept SQUARE and in
# PIXELS rather than expressed as anchors: a proportional box would distort
# on any future aspect change, and a battler sprite that is not square is
# wrong in a way no amount of correct positioning rescues.
GBA_SPRITE = 64

# Which node draws which battler position.
#   singles: only the two LEFT positions are used.
#   doubles: all four.
#
# ⚠️ **THE TRAINER SPRITES SHARE THEIR BATTLER'S BOX, AND THAT IS A REAL
# CONSTRAINT, NOT TIDINESS.** A trainer portrait occupies the same slot the
# battler will occupy -- it is what stands there before the first Pokemon is
# sent out, and source slides it out of exactly that position. `m26_
# trainer_category_party_test` asserts the two share anchors AND offsets.
#
# Moving the battlers without moving these broke all 8 of those assertions
# on the first Phase 2 run. They are placed from the same parse for the same
# reason the table and the scenes are: a pairing that must hold is cheaper to
# guarantee than to remember.
NODE_MAP = {
    "singles": {
        "PlayerSprite0": "B_POSITION_PLAYER_LEFT",
        "OpponentSprite0": "B_POSITION_OPPONENT_LEFT",
        "PlayerTrainerSprite": "B_POSITION_PLAYER_LEFT",
        "OpponentTrainerSprite": "B_POSITION_OPPONENT_LEFT",
    },
    "doubles": {
        "PlayerSprite0": "B_POSITION_PLAYER_LEFT",
        "PlayerSprite1": "B_POSITION_PLAYER_RIGHT",
        "OpponentSprite0": "B_POSITION_OPPONENT_LEFT",
        "OpponentSprite1": "B_POSITION_OPPONENT_RIGHT",
        # ⚠️ Paired with Sprite0, NOT with the RIGHT slots: there is one
        # trainer per side regardless of how many battlers that side fields.
        "PlayerTrainerSprite": "B_POSITION_PLAYER_LEFT",
        "OpponentTrainerSprite": "B_POSITION_OPPONENT_LEFT",
    },
}


def parse_coords():
    """Pull sBattlerCoords out of battle_anim_mons.c.

    Parsed rather than hardcoded so a reference update that moves a battler
    shows up as a real diff here instead of a silent divergence.
    """
    text = open(SRC, encoding="utf-8").read()
    m = re.search(
        r"const struct UCoords8 sBattlerCoords\[.*?\]\[.*?\]\s*=\s*\{(.*?)\n\};",
        text,
        re.S,
    )
    if not m:
        sys.exit("FATAL: sBattlerCoords not found in %s" % SRC)
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
            r"\[(B_POSITION_\w+)\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}", mm.group(1)
        )
        if len(entries) != 4:
            sys.exit(
                "FATAL: %s has %d positions, expected 4" % (mode_key, len(entries))
            )
        out[mode_name] = {k: (int(x), int(y)) for k, x, y in entries}
    return out


def render_gd(coords):
    def block(mode):
        rows = []
        for pos, (x, y) in coords[mode].items():
            rows.append(
                '\t"%s": Vector2i(%d, %d),' % (pos, x, y)
            )
        return "\n".join(rows)

    return '''class_name BattlerCoords
extends RefCounted

## Battler screen coordinates, ported verbatim from source.
##
## ⚠️ **GENERATED BY `scripts/gen_battler_coords.py` -- DO NOT HAND-EDIT.**
## Re-run the generator instead; it also places the six sprite nodes in
## `battle_screen_singles.tscn` / `battle_screen_doubles.tscn` from this same
## parse, which is what keeps the table and the scenes from drifting apart.
##
## Source: `sBattlerCoords` (`src/battle_anim_mons.c`). The values are GBA
## screen pixels on a %dx%d canvas, and are the sprite's CENTRE.
##
## ⚠️ **SINGLES USES ONLY THE TWO `_LEFT` POSITIONS.** The `_RIGHT` entries in
## the singles table are real data and are deliberately unused here -- source
## reaches them through move animations that borrow a second slot, not through
## battler placement. Placing a singles battler at a `_RIGHT` coordinate would
## look plausible and be wrong.


## The canvas these coordinates are expressed against.
const GBA_SCREEN := Vector2(%.1f, %.1f)

## A battler sprite is 64x64 on hardware.
const GBA_SPRITE_SIZE := %d


const SINGLES := {
%s
}

const DOUBLES := {
%s
}


## The point anchor for a battler, as a fraction of the canvas.
##
## ⚠️ **Anchors, not pixels, and that is the whole point of expressing it this
## way:** a fraction survives a canvas change untouched, while a pixel offset
## is a constant tuned against one resolution. This project has changed canvas
## twice (16:9 -> 4:3 -> 3:2), and each time the pixel-placed nodes drifted
## while the anchored ones did not.
static func anchor_for(mode: Dictionary, position_key: String) -> Vector2:
	var c: Vector2i = mode.get(position_key, Vector2i.ZERO)
	return Vector2(float(c.x) / GBA_SCREEN.x, float(c.y) / GBA_SCREEN.y)


## Half the sprite box in pixels, at a given uniform GBA->canvas scale.
static func half_box(scale: float) -> float:
	return GBA_SPRITE_SIZE * scale * 0.5
''' % (
        int(GBA_W),
        int(GBA_H),
        GBA_W,
        GBA_H,
        GBA_SPRITE,
        block("singles"),
        block("doubles"),
    )


def place_nodes(scene_path, mode, coords, scale):
    """Rewrite each battler node's anchors and offsets in place.

    Only the six geometry lines per node are touched -- texture, expand_mode,
    stretch_mode and every other property are left exactly as authored, so
    this cannot quietly undo art or layout work done in the editor.
    """
    text = open(scene_path, encoding="utf-8").read()
    half = GBA_SPRITE * scale / 2.0
    changed = []

    for node, pos_key in NODE_MAP[mode].items():
        x, y = coords[mode][pos_key]
        ax, ay = x / GBA_W, y / GBA_H

        pat = re.compile(
            r'(\[node name="%s" type="TextureRect" parent="BattleStage"[^\]]*\]\n)'
            r"((?:(?!\[node ).)*)" % re.escape(node),
            re.S,
        )
        m = pat.search(text)
        if not m:
            sys.exit("FATAL: node %s not found in %s" % (node, scene_path))

        body = m.group(2)
        # Drop the existing geometry lines, keep everything else in order.
        body = re.sub(
            r"^(?:anchors_preset|anchor_left|anchor_top|anchor_right|anchor_bottom"
            r"|offset_left|offset_top|offset_right|offset_bottom"
            r"|grow_horizontal|grow_vertical) = .*\n",
            "",
            body,
            flags=re.M,
        )
        geom = (
            "anchors_preset = -1\n"
            "anchor_left = %.7f\nanchor_top = %.7f\n"
            "anchor_right = %.7f\nanchor_bottom = %.7f\n"
            "offset_left = %.1f\noffset_top = %.1f\n"
            "offset_right = %.1f\noffset_bottom = %.1f\n"
            "grow_horizontal = 2\ngrow_vertical = 2\n"
        ) % (ax, ay, ax, ay, -half, -half, half, half)

        # Geometry sits directly after layout_mode, matching how Godot itself
        # orders a Control's properties.
        if "layout_mode = 1\n" in body:
            body = body.replace("layout_mode = 1\n", "layout_mode = 1\n" + geom, 1)
        else:
            body = geom + body

        text = text[: m.start(2)] + body + text[m.end(2) :]
        changed.append("%s -> (%d, %d) anchor (%.4f, %.4f)" % (node, x, y, ax, ay))

    open(scene_path, "w", encoding="utf-8").write(text)
    return changed


def main():
    coords = parse_coords()

    os.makedirs(os.path.dirname(OUT_GD), exist_ok=True)
    open(OUT_GD, "w", encoding="utf-8").write(render_gd(coords))
    print("wrote %s" % os.path.relpath(OUT_GD, PROJECT))

    # The canvas is asserted to be a uniform GBA multiple rather than assumed.
    # A non-uniform canvas makes "scale" ambiguous, and silently picking the
    # width is exactly the anisotropy the 3:2 conversion exists to remove.
    # Read directly rather than with configparser: project.godot opens with a
    # comment preamble and bare `config_version=5` before its first section
    # header, which configparser rejects outright.
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
            "FATAL: canvas %gx%g is not a uniform GBA multiple "
            "(x=%.4f, y=%.4f). Battler placement is only arithmetic while it "
            "is -- fix the canvas or this script is guessing." % (w, h, sx, sy)
        )
    print("canvas %gx%g = uniform %.4fx GBA" % (w, h, sx))

    for scene, mode in ((SCENE_SINGLES, "singles"), (SCENE_DOUBLES, "doubles")):
        for line in place_nodes(scene, mode, coords, sx):
            print("  %-18s %s" % (os.path.basename(scene).split("_")[-1][:7], line))


if __name__ == "__main__":
    main()
