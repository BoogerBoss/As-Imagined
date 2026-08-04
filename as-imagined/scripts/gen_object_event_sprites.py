#!/usr/bin/env python3
"""
[M27D D1] Pulls the overworld sprite set from the reference clone, and emits
the graphics_id -> sheet lookup that renders it.

Usage (from anywhere; paths are absolute per this project's standing rule):
    python3 scripts/gen_object_event_sprites.py

Three pulls, one table:

  object events   449 PNGs -> assets/sprites/overworld/object_events/
  field effects    66 PNGs -> assets/sprites/overworld/field_effects/
  trainer pics     25 PNGs -> assets/sprites/trainers/portraits/  (gap close)
  ObjectEventGraphics.gd    387 ids -> sheet / frame size / frame count

WHY A FOUR-FILE JOIN AND NOT A NAME TRANSFORM. Nothing about a graphics id
predicts its file. `OBJ_EVENT_GFX_LASS_FRLG` resolves through:

    object_event_graphics_info_pointers.h  -> gObjectEventGraphicsInfo_LassFrlg
    object_event_graphics_info.h           -> .width/.height/.paletteTag
    object_event_pic_tables.h              -> sPicTable_LassFrlg -> ..Pic_LassFrlg
    object_event_graphics.h                -> INCGFX(".../people/lass_frlg.png")

Same discipline as gen_trainer_portraits.py's own three-file join: parse the
real tables rather than trusting a filename convention.

TWO THINGS MEASURED RATHER THAN ASSUMED, both of which a naive copy gets wrong:

1. INDEX 0 IS THE TRANSPARENCY KEY AND NO FILE CARRIES tRNS. A plain
   shutil.copyfile renders every sprite inside an opaque box -- exactly what
   happened to the ball sheets in [M26B3-6a], where the white box was misread
   as a shrinking Pokemon for several screenshots. Index 0 is NOT a constant
   colour across these files, so tag the INDEX rather than colour-keying a
   value. Same fix as gen_ball_sprites.py / gen_hit_effect_sprites.py.

2. THE EMBEDDED PALETTE IS NOT ALWAYS THE ONE THE GAME USES. 44 of the
   corridor's 46 ids match their `.paletteTag`, and OBJ_EVENT_GFX_WORKER_M
   genuinely does not -- so its sprite would render in the wrong colours from a
   flat copy. Same shape as [M23.11 Phase 5b]'s Thunder, whose tile data and
   palette lived in different files. Every sprite therefore has its tagged
   palette applied, and the script REPORTS how many differed rather than
   silently fixing them, because a rising count means the reference changed.

Pull scope is the WHOLE set, not the 46 the corridor happens to name: 449 files
total 0.5 MB, and this project has already paid for a selective pull once --
[M26B3-1] took 93 trainer front pics and the Kanto roster then forced a second
session for 62 more.
"""

import os
import re
import shutil
import sys

from PIL import Image

from ref_path import PROJECT, REF, assert_inside_project

OE_DIR = os.path.join(REF, "src/data/object_events")
GFX_ROOT = os.path.join(REF, "graphics")

OUT_OE = assert_inside_project(
    os.path.join(PROJECT, "assets/sprites/overworld/object_events"), "OUT_OE")
OUT_FX = assert_inside_project(
    os.path.join(PROJECT, "assets/sprites/overworld/field_effects"), "OUT_FX")
OUT_TRAINER = assert_inside_project(
    os.path.join(PROJECT, "assets/sprites/trainers/portraits"), "OUT_TRAINER")
OUT_GD = assert_inside_project(
    os.path.join(PROJECT, "scripts/overworld/object_event_graphics.gd"), "OUT_GD")

# include/constants/event_object_movement.h -- ANIM_STD_FACE_*. EAST is WEST
# mirrored (sAnim_FaceEast is ANIMCMD_FRAME(2, .., .hFlip = TRUE)), so there is
# no fourth facing frame and a renderer must flip rather than look one up.
FACE_FRAME = {"SOUTH": 0, "NORTH": 1, "WEST": 2, "EAST": 2}

# The two step frames per facing, from sAnim_Go{South,North,West,East}
# (src/data/object_events/object_event_anims.h). EAST reuses WEST's pair
# mirrored, exactly as its idle frame does.
STEP_FRAME = {"SOUTH": (3, 4), "NORTH": (5, 6), "WEST": (7, 8), "EAST": (7, 8)}

FACE_FLIP_EAST = True

# [M27E E2] The RUN cycle, from sAnim_Run{South,North,West,East}Frlg
# (src/data/object_events/object_event_anims.h:681-711). The FRLG variants
# specifically -- gObjectEventImageAnimTable_Standard selects them via
# `IS_FRLG ? sAnim_RunSouthFrlg : sAnim_RunSouth`, and the two differ.
#
# ⚠️ **THESE ARE PIC-TABLE INDICES 9-17, WHICH IS THE SECOND HALF OF A
# COMPOSITED SHEET** -- see the composite note in build_index. They do not exist
# on the walking sheet at all, which is why running needed the generator change
# before it could need any renderer change.
#
# Each anim is FRAME(neutral,5) FRAME(legA,3) FRAME(neutral,5) FRAME(legB,3),
# looping -- the same four-entry shape as the walk, but with TWO differences
# that matter: the neutral pose is a RUN-specific frame rather than the standing
# FACE frame, and the entries are UNEVEN (5/3), so the neutral is held longer
# than the leg. EAST is WEST hFlipped, the same convention every other anim in
# this file already uses.
RUN_IDLE_FRAME = {"SOUTH": 9, "NORTH": 12, "WEST": 15, "EAST": 15}
RUN_STEP_FRAME = {"SOUTH": (10, 11), "NORTH": (13, 14), "WEST": (16, 17), "EAST": (16, 17)}
RUN_TICKS = (5, 3, 5, 3)

# [M27E E1c] A sheet's raw frame count is not always the graphics id's own
# frame count. The two player surf ids draw from the 14-frame *_surf_run
# sheets, but their pic tables (sPicTable_GreenSurf/sPicTable_RedSurf,
# src/data/object_events/object_event_pic_tables.h:1449) only ever reference
# raw frames 0-2 — every one of the 12 logical walking frames maps back onto
# the three facing poses, so surfing shows NO walk cycle in source. Emitting
# the sheet's own 14 here would let WalkAnim's cycle index the sheet's unused
# RUN frames (3+) instead. 3 is the honest port of the pic table, and it makes
# WalkAnim.animates() false — which reproduces the facing-only surf behaviour
# with zero special-casing in the anim path.
FRAME_OVERRIDES = {
    "OBJ_EVENT_GFX_GREEN_SURF": 3,
    "OBJ_EVENT_GFX_RED_SURF": 3,
}


def _read(path):
    with open(os.path.join(OE_DIR, path)) as f:
        return f.read()


def _stem_for(png):
    """Flatten the path below pics/ instead of taking the basename.

    MEASURED: 9 basenames collide across 20 files — `walking.png` alone is
    shared by brendan, may, ruby_sapphire_brendan and ruby_sapphire_may, and a
    basename copy silently overwrote all but the last, collapsing four player
    characters into one sprite. Same shape as the Route 22 node-name collision
    in [M27C]: a name derived from partial data, wrong only where two things
    happen to meet, and invisible until they do.

    The result is verbose (`people_brendan_walking`) and that is fine — nobody
    types these, the generated table resolves them.
    """
    rel = png.split("object_events/pics/", 1)[-1]
    return rel[:-4].replace("/", "_")


def _read_src(path):
    """A source file outside src/data/object_events/, or "" if absent."""
    full = os.path.join(REF, "src", path)
    if not os.path.exists(full):
        return ""
    with open(full) as f:
        return f.read()


def tag_index0_transparent(src, dst):
    """Copy a palette PNG, marking palette index 0 transparent."""
    im = Image.open(src)
    assert im.mode == "P", "%s is %s, expected indexed" % (src, im.mode)
    im.info["transparency"] = 0
    im.save(dst)


def load_pal(path):
    """JASC-PAL -> flat [r,g,b, r,g,b, ...] for the first 16 entries."""
    lines = open(path).read().split("\n")
    n = int(lines[2])
    out = []
    for i in range(min(16, n)):
        out += [int(v) for v in lines[3 + i].split()]
    return out


def build_index():
    """graphics_id -> dict(png, width, height, frames, pal), for every id."""
    ptr = _read("object_event_graphics_info_pointers.h")
    id2sym = dict(re.findall(
        r"\[(OBJ_EVENT_GFX_[A-Z0-9_]+)\]\s*=\s*&gObjectEventGraphicsInfo_(\w+)", ptr))

    info = _read("object_event_graphics_info.h") + "\n" + \
        _read("object_event_graphics_info_followers.h")
    blocks = {m.group(1): m.group(2) for m in re.finditer(
        r"gObjectEventGraphicsInfo_(\w+)\s*=\s*\{(.*?)\n\};", info, re.S)}

    # Pic tables are spread across FOUR files, not one — berry trees and
    # followers each have their own, and a field-effect table supplies one more.
    # Reading only object_event_pic_tables.h left 5 ids unresolved, including
    # every berry tree.
    pics = "\n".join(_read(f) for f in (
        "object_event_pic_tables.h",
        "berry_tree_graphics_tables.h",
        "object_event_pic_tables_followers.h",
    )) + "\n" + _read_src("data/field_effect_object_template_pointers.h")
    graphics = _read("object_event_graphics.h")
    incbin = dict(re.findall(
        r"(gObjectEventPic_\w+)\[\]\s*=\s*INC(?:BIN|GFX)_U\d+\(\"([^\"]+)\"", graphics))

    out, unresolved, clamped = {}, [], []
    mixed_geometry = []
    stem_source = {}
    for gid, sym in sorted(id2sym.items()):
        body = blocks.get(sym)
        if body is None:
            unresolved.append((gid, "no info block for %s" % sym))
            continue
        # READ `.images`, do not derive the pic-table name from the info symbol.
        # They agree most of the time and not always: gObjectEventGraphicsInfo_
        # Azumarill points at sPicTable_AzumarillOld. Deriving cost 48 of 387
        # ids on the first run — the same guess-a-name-instead-of-reading-the-
        # field mistake M27A already paid for with tileset directories.
        img = re.search(r"\.images\s*=\s*(\w+)", body)
        if not img:
            unresolved.append((gid, "no .images field in %s" % sym))
            continue
        pm = re.search(
            r"%s\[\]\s*=\s*\{(.*?)\n\};" % re.escape(img.group(1)), pics, re.S)
        if not pm:
            unresolved.append((gid, "no %s" % img.group(1)))
            continue
        # Frame count comes from the IMAGE, not from counting entries in the
        # pic table: sPicTable_Leaf is a single `overworld_ascending_frames(...)`
        # macro that expands to nine, so counting call sites reports 1 and every
        # facing past SOUTH would be unreachable.
        frames = 0  # filled in below, once the sheet size is known
        first = re.search(r"\((gObjectEventPic_\w+)", pm.group(1))
        raw = incbin.get(first.group(1), "") if first else ""
        if not raw:
            unresolved.append((gid, "no INCBIN for %s" % (first.group(1) if first else "?")))
            continue
        png = re.sub(r"\.4bpp$", "", raw)
        if not png.endswith(".png"):
            png += ".png"
        full = os.path.join(REF, png)
        if not os.path.exists(full):
            unresolved.append((gid, "missing %s" % png))
            continue
        w = re.search(r"\.width\s*=\s*(\d+)", body)
        h = re.search(r"\.height\s*=\s*(\d+)", body)
        tag = re.search(r"\.paletteTag\s*=\s*(\w+)", body)
        pal = ""
        if tag:
            cand = os.path.join(
                GFX_ROOT, "object_events/palettes",
                tag.group(1).replace("OBJ_EVENT_PAL_TAG_", "").lower() + ".pal")
            if os.path.exists(cand):
                pal = cand
        fw = int(w.group(1)) if w else 16
        fh = int(h.group(1)) if h else 32
        sheet_w, sheet_h = Image.open(full).size
        # MEASURED across all 385 resolved ids: 384 sheets are HORIZONTAL strips
        # (sheet height == frame height) and NONE are vertical. Getting this
        # backwards renders SOUTH correctly — it is frame 0 at the origin — and
        # reads off the image for every other facing, which is exactly the shape
        # of bug a single screenshot of a resting NPC would miss.
        if sheet_h < fh or sheet_w < fw:
            # One real case: BERRY_TREE_LATE_STAGES declares 16x32 against a
            # 16x16 sheet. Clamp rather than emit a frame that reads out of
            # bounds; flagged in the report rather than silently reshaped.
            fw, fh = min(fw, sheet_w), min(fh, sheet_h)
            clamped.append(gid)
        frames = max(1, sheet_w // fw)
        # See FRAME_OVERRIDES at the top: a pic table can use fewer frames than
        # its sheet holds, and the table is what the id's behaviour follows.
        frames = FRAME_OVERRIDES.get(gid, frames)

        # [M27E E2] A PIC TABLE MAY SPAN MORE THAN ONE PIC SYMBOL, and when it
        # does, NO single file on disk is the id's real frame set.
        #
        # MEASURED across the whole reference tree: exactly THREE tables do this
        # -- sPicTable_GreenNormal, sPicTable_RedNormal (each 9 frames of the
        # character's walking sheet followed by 11 RUN frames living inside the
        # *_surf_run sheet) and sPicTable_OldMan2. Everything else resolves to
        # one file, which is why taking `first` alone was right for 384 ids and
        # silently wrong for these.
        #
        # ⚠️ **THE TABLE IS AN ORDER, NOT A CONCATENATION.** GreenNormal's
        # second half starts at raw frame 3 (frames 0-2 of that sheet are the
        # SURF poses), and OldMan2 both REPEATS and REORDERS (0,1,2,0,0,1,1,2,2
        # then one OldWoman frame). So the composite is built by walking the
        # entries in order, never by appending whole files.
        #
        # Gated on there being MORE THAN ONE symbol so the macro-expanded tables
        # are untouched: `overworld_ascending_frames(...)` emits no
        # `overworld_frame` call sites at all, so `entries` is empty for them and
        # the image-derived count above still stands -- the exact reason the
        # comment at the top of this block says frame count comes from the image.
        entries = re.findall(
            r"overworld_frame\((gObjectEventPic_\w+)\s*,\s*\d+\s*,\s*\d+\s*,\s*(\d+)\)",
            pm.group(1))
        composite = None
        if len({s for s, _ in entries}) > 1:
            composite = []
            for sym_name, idx in entries:
                sub_raw = incbin.get(sym_name, "")
                sub_png = re.sub(r"\.4bpp$", "", sub_raw)
                if sub_png and not sub_png.endswith(".png"):
                    sub_png += ".png"
                sub_full = os.path.join(REF, sub_png) if sub_png else ""
                if not sub_full or not os.path.exists(sub_full):
                    composite = None
                    unresolved.append((gid, "composite: missing %s" % sym_name))
                    break
                # ⚠️ **EVERY SOURCE MUST AGREE ON THE FRAME GEOMETRY, AND MOST DO
                # NOT.** 48 tables span several pic symbols, but only the ones
                # whose files share the declared frame size can be laid end to
                # end. A berry tree is the counter-example that forced this
                # guard: `gPicTable_CheriBerryTree` draws from a 16x16 dirt
                # pile, a 32x16 sprout AND a 96x32 tree, and the declared size
                # clamps to the FIRST of those — so compositing it would crop
                # every grown stage to its top-left 16x16 corner and look
                # plausible in a directory listing while being visibly wrong on
                # screen. Refused and REPORTED rather than silently cropped;
                # see `mixed_geometry` in the run report.
                sub_w, sub_h = Image.open(sub_full).size
                if sub_h != fh or sub_w % fw != 0 or (int(idx) + 1) * fw > sub_w:
                    composite = None
                    mixed_geometry.append(
                        (gid, "%s is %dx%d, frame is %dx%d"
                         % (sym_name, sub_w, sub_h, fw, fh)))
                    break
                composite.append((sub_full, int(idx)))
        if composite:
            # The table IS the frame set here, so its own length is the count --
            # not the width of whichever file happened to be listed first.
            frames = FRAME_OVERRIDES.get(gid, len(composite))

        out[gid] = {
            "png": full,
            "stem": _stem_for(png),
            "width": fw,
            "height": fh,
            "frames": frames,
            "pal": pal,
            "composite": composite,
        }
    # A stem that maps to two different source files means the flattening rule
    # has stopped being injective, and a copy would silently drop one of them.
    for gid, e in out.items():
        prev = stem_source.setdefault(e["stem"], e["png"])
        assert prev == e["png"], (
            "stem %r maps to two files: %s and %s" % (e["stem"], prev, e["png"]))
    return out, unresolved, clamped, mixed_geometry


def _write_composite(e, dst):
    """[M27E E2] Assemble a sheet whose pic table spans several source files.

    One frame per table entry, in the table's own order -- see the note at the
    detection site for why order matters and concatenation would be wrong.

    Index 0 is the transparency key here exactly as it is everywhere else in
    this pull, and it is applied PER SOURCE FILE before flattening, because the
    two halves do not share a palette and so do not share a colour at index 0.
    """
    fw, fh = e["width"], e["height"]
    want = load_pal(e["pal"]) if e["pal"] else None
    cache = {}
    sheet = Image.new("RGBA", (fw * len(e["composite"]), fh), (0, 0, 0, 0))
    for slot, (src, idx) in enumerate(e["composite"]):
        rgba = cache.get(src)
        if rgba is None:
            im = Image.open(src)
            if want is not None and im.mode == "P":
                pal = im.getpalette()
                pal[:len(want)] = want
                im.putpalette(pal)
            if im.mode == "P":
                im.info["transparency"] = 0
            rgba = im.convert("RGBA")
            cache[src] = rgba
        box = (idx * fw, 0, idx * fw + fw, fh)
        if box[2] > rgba.width or box[3] > rgba.height:
            raise AssertionError(
                "composite frame %d out of bounds in %s (%dx%d)"
                % (idx, src, rgba.width, rgba.height))
        sheet.paste(rgba.crop(box), (slot * fw, 0))
    sheet.save(dst)


def pull_object_events(index):
    os.makedirs(OUT_OE, exist_ok=True)
    copied = recoloured = 0
    seen = {}
    for gid, e in index.items():
        dst = os.path.join(OUT_OE, e["stem"] + ".png")
        # Several ids legitimately share one sheet; copy once, map many.
        if e["stem"] in seen:
            continue
        seen[e["stem"]] = True
        if e.get("composite"):
            # [M27E E2] Built frame-by-frame from the pic table's own order, so
            # the emitted sheet IS the id's real frame set. Written RGBA rather
            # than palette-indexed: the sources are separate files with separate
            # palettes, so there is no one index space to keep, and flattening
            # each frame through its own tagged palette first is what makes the
            # halves agree on screen.
            _write_composite(e, dst)
            copied += 1
            continue
        im = Image.open(e["png"])
        if e["pal"]:
            want = load_pal(e["pal"])
            have = im.getpalette()[:len(want)]
            if have != want:
                # The game draws this sprite with its TAGGED palette, not the
                # one baked into the PNG. Reported, not silenced -- a rising
                # count means the reference changed under us.
                full = im.getpalette()
                full[:len(want)] = want
                im.putpalette(full)
                recoloured += 1
        im.info["transparency"] = 0
        im.save(dst)
        copied += 1
    # Sweep the rest. ~90 PNGs under pics/ are referenced by no graphics id --
    # extra frames of multi-file sheets, and art for ids this build does not
    # enable. Rob's call: take the lot. They are inert until something names
    # them, and the whole set is 0.5 MB, so a second pull session later would
    # cost more than the bytes ever will.
    extra = 0
    root = os.path.join(GFX_ROOT, "object_events/pics")
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if not f.endswith(".png"):
                continue
            src = os.path.join(dirpath, f)
            stem = _stem_for(src)
            dst = os.path.join(OUT_OE, stem + ".png")
            if os.path.exists(dst):
                continue
            tag_index0_transparent(src, dst)
            extra += 1
    return copied, recoloured, extra


def pull_field_effects():
    src_dir = os.path.join(GFX_ROOT, "field_effects/pics")
    os.makedirs(OUT_FX, exist_ok=True)
    n = 0
    for f in sorted(os.listdir(src_dir)):
        if not f.endswith(".png"):
            continue
        tag_index0_transparent(os.path.join(src_dir, f), os.path.join(OUT_FX, f))
        n += 1
    return n


def pull_missing_trainer_pics():
    """[M26B3-1] close-out: source has 180 front pics, this project had 155."""
    src_dir = os.path.join(GFX_ROOT, "trainers/front_pics")
    have = {f for f in os.listdir(OUT_TRAINER) if f.endswith(".png")}
    n = 0
    for f in sorted(os.listdir(src_dir)):
        if not f.endswith(".png") or f in have:
            continue
        # These already carry tRNS upstream, so a flat copy preserves it --
        # confirmed when the 62 Kanto pics were pulled. Kept as a plain copy so
        # the 155 already tracked stay byte-identical to their source.
        shutil.copyfile(os.path.join(src_dir, f), os.path.join(OUT_TRAINER, f))
        n += 1
    return n


def render_gd(index):
    lines = [
        "@tool",
        "# GENERATED by scripts/gen_object_event_sprites.py — do not edit by hand.",
        "# Source: src/data/object_events/*.h (a four-file join; see the script).",
        "class_name ObjectEventGraphics",
        "extends RefCounted",
        "",
        "const SHEET_DIR := \"res://assets/sprites/overworld/object_events/\"",
        "const FX_DIR := \"res://assets/sprites/overworld/field_effects/\"",
        "",
        "## ANIM_STD_FACE_* -> which frame of the sheet to draw.",
        "##",
        "## EAST has no frame of its own: sAnim_FaceEast is",
        "## ANIMCMD_FRAME(2, .., .hFlip = TRUE), so a renderer draws WEST mirrored.",
        "## Getting this wrong is invisible for symmetric sprites and obvious for",
        "## every character carrying something.",
        "const FACE_FRAME := {",
    ]
    for k in ("SOUTH", "NORTH", "WEST", "EAST"):
        lines.append("\t\"%s\": %d," % (k, FACE_FRAME[k]))
    lines += [
        "}",
        "",
        "## True when EAST must be drawn as a horizontally flipped WEST.",
        "const EAST_IS_MIRRORED_WEST := true",
        "",
        "## The two step frames per facing, for the walk cycle.",
        "##",
        "## From sAnim_GoSouth/North/West/East. The cycle each one runs is",
        "## FRAME(stepA) FRAME(idle) FRAME(stepB) FRAME(idle), looping — so the",
        "## resting frame is part of the walk, not just what precedes it, and a",
        "## renderer that alternates stepA/stepB alone drops half the animation.",
        "## EAST reuses WEST's pair mirrored, exactly as its idle frame does.",
        "const STEP_FRAME := {",
    ]
    for k in ("SOUTH", "NORTH", "WEST", "EAST"):
        lines.append("\t\"%s\": [%d, %d]," % (k, STEP_FRAME[k][0], STEP_FRAME[k][1]))
    lines += [
        "}",
        "",
        "## Order the four cycle entries are played in: step, rest, step, rest.",
        "## Indexes into [stepA, idle, stepB, idle] as built by WalkAnim.",
        "const WALK_CYCLE_LEN := 4",
        "",
        "## Ticks each cycle entry is held, by movement speed (the second",
        "## argument of each ANIMCMD_FRAME).",
        "##",
        "## \u26a0 There is NO GoSlow* anim in source — the standard table is",
        "## FACE / GO / GO_FAST / GO_FASTER / GO_FASTEST only. A slow walk reuses",
        "## the NORMAL anim, so its 32 movement frames play FOUR cycle entries",
        "## rather than two stretched ones. That asymmetry is real: a slow walk",
        "## shows more foot movement per tile, not slower foot movement.",
        "const ANIM_TICKS_NORMAL := 8",
        "const ANIM_TICKS_FAST := 4",
        "const ANIM_TICKS_FASTER := 2",
        "",
        "## [M27E E2] The RUN cycle's own frames, from sAnim_Run*Frlg.",
        "##",
        "## ⚠ Indices 9-17 -- the RUN half of a COMPOSITED sheet, which only",
        "## the two player ids have (sPicTable_Green/RedNormal each span two pic",
        "## symbols). Every other id stops at 8, so `can_run()` gates on this.",
        "##",
        "## The neutral pose is a RUN-specific frame, NOT the standing FACE frame",
        "## the walk cycle rests on -- a runner never shows its standing sprite.",
        "const RUN_IDLE_FRAME := {",
    ]
    for k in ("SOUTH", "NORTH", "WEST", "EAST"):
        lines.append("\t\"%s\": %d," % (k, RUN_IDLE_FRAME[k]))
    lines += [
        "}",
        "",
        "## The two leg frames per facing, from the same four anims.",
        "const RUN_STEP_FRAME := {",
    ]
    for k in ("SOUTH", "NORTH", "WEST", "EAST"):
        lines.append("\t\"%s\": [%d, %d]," % (k, RUN_STEP_FRAME[k][0], RUN_STEP_FRAME[k][1]))
    lines += [
        "}",
        "",
        "## Ticks per cycle entry: [neutral, legA, neutral, legB].",
        "##",
        "## ⚠ UNEVEN, unlike every walk anim in this file -- source holds the",
        "## neutral pose 5 frames and each leg 3. Averaging them to 4 would run at",
        "## the right overall cadence and read wrong, because the leg would be up",
        "## as long as the body is level.",
        "const RUN_TICKS := [%d, %d, %d, %d]" % RUN_TICKS,
        "",
        "## A sheet needs 18 frames to hold a run cycle (indices 0-17).",
        "## Only the two player ids do; every NPC stops at 9.",
        "const MIN_FRAMES_TO_RUN := 18",
        "",
        "## A sheet needs all nine frames to hold a walk cycle. 136 of the 385",
        "## resolved ids do; 70 carry only the three facing frames (signs, static",
        "## props) and 96 carry a single frame. Those must draw their idle frame",
        "## and never index past it.",
        "const MIN_FRAMES_TO_ANIMATE := 9",
        "",
        "## Source's own fallback for an id it cannot resolve",
        "## (GetObjectEventGraphicsInfo: `graphicsId = OBJ_EVENT_GFX_NINJA_BOY`).",
        "## A real, visible sprite rather than an invented placeholder — so a hole",
        "## is obvious, and M27G's VAR_* lookup slots in ahead of it with nothing",
        "## to undo.",
        "const FALLBACK_ID := \"OBJ_EVENT_GFX_NINJA_BOY\"",
        "",
        "## graphics_id -> { sheet, w, h, frames }.",
        "##",
        "## Sheets are HORIZONTAL strips: frame N is at x = N * w, y = 0.",
        "## Measured across all 385 resolved ids — 384 horizontal, 0 vertical.",
        "const BY_ID := {",
    ]
    for gid in sorted(index):
        e = index[gid]
        lines.append(
            "\t\"%s\": {\"sheet\": \"%s\", \"w\": %d, \"h\": %d, \"frames\": %d},"
            % (gid, e["stem"], e["width"], e["height"], e["frames"]))
    lines += [
        "}",
        "",
        "",
        "## Sheet path for a graphics id, falling back the way source does.",
        "static func sheet_path(graphics_id: String) -> String:",
        "\tvar e: Dictionary = BY_ID.get(graphics_id, BY_ID.get(FALLBACK_ID, {}))",
        "\tif e.is_empty():",
        "\t\treturn \"\"",
        "\treturn SHEET_DIR + str(e[\"sheet\"]) + \".png\"",
        "",
        "",
        "## Frame size for a graphics id. Sizes are NOT uniform — 16x32 dominates",
        "## but 16x16 and 32x16 are both real — so a renderer must read this",
        "## rather than assuming.",
        "static func frame_size(graphics_id: String) -> Vector2i:",
        "\tvar e: Dictionary = BY_ID.get(graphics_id, BY_ID.get(FALLBACK_ID, {}))",
        "\tif e.is_empty():",
        "\t\treturn Vector2i(16, 32)",
        "\treturn Vector2i(int(e[\"w\"]), int(e[\"h\"]))",
        "",
        "",
        "## How many frames this id's sheet actually holds.",
        "##",
        "## Read it before indexing a step frame: not every sheet has one.",
        "static func frame_count(graphics_id: String) -> int:",
        "\tvar e: Dictionary = BY_ID.get(graphics_id, BY_ID.get(FALLBACK_ID, {}))",
        "\tif e.is_empty():",
        "\t\treturn 1",
        "\treturn int(e[\"frames\"])",
        "",
        "",
        "## Is this an id this project can actually draw?",
        "##",
        "## OBJ_EVENT_GFX_VAR_0..F are absent BY DESIGN: source resolves them at",
        "## runtime through VarGetObjectEventGraphicsId, so the sprite is chosen by",
        "## a script variable and cannot be pulled. 44 exist region-wide. They fall",
        "## back until M27G can answer them.",
        "static func is_known(graphics_id: String) -> bool:",
        "\treturn BY_ID.has(graphics_id)",
        "",
    ]
    with open(OUT_GD, "w") as f:
        f.write("\n".join(lines))


def main():
    index, unresolved, clamped, mixed_geometry = build_index()
    copied, recoloured, extra = pull_object_events(index)
    fx = pull_field_effects()
    tr = pull_missing_trainer_pics()
    render_gd(index)

    print("object events : %d ids -> %d sheets (%d recoloured to their tagged "
          "palette), +%d unreferenced" % (len(index), copied, recoloured, extra))
    print("field effects : %d" % fx)
    print("trainer pics  : %d newly pulled" % tr)
    print("table         : %s (%d ids)" % (os.path.relpath(OUT_GD, PROJECT), len(index)))
    if clamped:
        print("clamped       : %d (declared frame larger than its sheet) — %s"
              % (len(clamped), ", ".join(clamped)))
    composited = sorted(g for g, e in index.items() if e.get("composite"))
    print("composited    : %d id(s) whose pic table spans several pic files — %s"
          % (len(composited), ", ".join(composited) if composited else "none"))
    if mixed_geometry:
        # ⚠️ NOT a failure — a REAL, still-open finding. Each of these ids draws
        # from several files that disagree on frame size, so its emitted sheet
        # is still just the FIRST file and the rest of its frames are missing.
        # Berry trees are the whole of this list today: a tree renders its dirt
        # pile and never its grown stages. Fixing it needs per-entry frame
        # geometry, which is its own task — see M27E E2's own note.
        print("mixed geom    : %d id(s) NOT composited (sources disagree on "
              "frame size; still emitting the first file only)"
              % len(mixed_geometry))
        for gid, why in mixed_geometry[:5]:
            print("    %-38s %s" % (gid, why))
        if len(mixed_geometry) > 5:
            print("    ... and %d more" % (len(mixed_geometry) - 5))
    if unresolved:
        print("unresolved    : %d" % len(unresolved))
        for gid, why in unresolved[:10]:
            print("    %-38s %s" % (gid, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
