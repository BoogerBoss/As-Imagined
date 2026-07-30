#!/usr/bin/env python3
"""
[M27A] Map importer — proof of concept, Pallet Town.

Converts a pokeemerald-expansion FRLG map into the pieces Godot needs:
a per-plane tile atlas, and per-cell arrays for metatile id / collision /
elevation / behaviour.

Everything here is documented in docs/overworld_scope.md:
  §1.1  blockdata bit layout (metatile 0-9, collision 10-11, elevation 12-15)
  §1.2  FRLG attributes are 32-BIT (behaviour 0-8, layer type 29-30)
  §1.4  elevation is per-CELL, not per-tile
  §1.6  metatile layer type -> which Godot layer each half lands on

Run from anywhere; paths are absolute per this project's standing rule.
"""

import json
import os
import struct
import sys

from PIL import Image

from ref_path import PROJECT, REF, assert_inside_project
from trainer_keys import canonical_key

# [Step 5 follow-up] Derived, not hardcoded. These were absolute paths into the
# main checkout, so running this script from a worktree or a clone elsewhere
# silently wrote its output into the ORIGINAL tree -- the same
# wrong-tree-by-hardcoded-path class ref_path.py exists to kill, missed by that
# sweep because these are OUTPUT paths rather than reference paths.
OUT = assert_inside_project(os.path.join(PROJECT, "assets", "maps"), "OUT")
# Atlases are shared per tileset PAIR and are real runtime dependencies of
# tracked scenes, so they live apart from the regenerable per-map output.
ATLAS_OUT = assert_inside_project(
    os.path.join(PROJECT, "assets", "map_atlases"), "ATLAS_OUT")

# include/fieldmap.h — the FRLG split, NOT the Hoenn one (512/512/6).
NUM_TILES_IN_PRIMARY_FRLG = 640
NUM_METATILES_IN_PRIMARY_FRLG = 640
NUM_PALS_IN_PRIMARY_FRLG = 7
NUM_TILES_PER_METATILE = 8

# include/global.fieldmap.h
MAPGRID_METATILE_ID_MASK = 0x03FF
MAPGRID_COLLISION_MASK = 0x0C00
MAPGRID_COLLISION_SHIFT = 10
MAPGRID_ELEVATION_MASK = 0xF000
MAPGRID_ELEVATION_SHIFT = 12

METATILE_ATTR_BEHAVIOR_MASK_FRLG = 0x000001FF
METATILE_ATTR_LAYER_MASK_FRLG = 0x60000000
METATILE_ATTR_LAYER_SHIFT_FRLG = 29

LAYER_NORMAL, LAYER_COVERED, LAYER_SPLIT = 0, 1, 2

# §1.6 — GBA draws Bg3, Bg2, [sprites], Bg1. Three planes, entities between
# the middle and top. Godot: Ground / Objects / [entities] / Overhangs.
PLANE_GROUND, PLANE_OBJECTS, PLANE_OVERHANGS = 0, 1, 2


def load_pal(path):
    """JASC-PAL -> list of 16 (r,g,b). Index 0 is the transparency key."""
    lines = open(path).read().split("\n")
    n = int(lines[2])
    out = []
    for i in range(n):
        r, g, b = (int(v) for v in lines[3 + i].split())
        out.append((r, g, b))
    return out


def load_tiles(path):
    """Indexed tile sheet -> list of 8x8 index grids, row-major."""
    im = Image.open(path)
    assert im.mode == "P", "%s is %s, expected indexed" % (path, im.mode)
    w, h = im.size
    px = im.load()
    tiles = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            tiles.append([[px[tx * 8 + x, ty * 8 + y] for x in range(8)]
                          for y in range(8)])
    return tiles


def load_u16(path):
    raw = open(path, "rb").read()
    return list(struct.unpack("<%dH" % (len(raw) // 2), raw))


def load_u32(path):
    raw = open(path, "rb").read()
    return list(struct.unpack("<%dI" % (len(raw) // 4), raw))


def _elev_priority():
    """Extract sElevationToPriority verbatim rather than transcribing it."""
    import re
    src = open(os.path.join(REF, "src/event_object_movement.c")).read()
    m = re.search(r"sElevationToPriority\[\]\s*=\s*\{([^}]*)\}", src)
    vals = [int(v.strip()) for v in m.group(1).split(",") if v.strip()]
    assert len(vals) == 16, "expected 16 elevations, got %d" % len(vals)
    return "[%s]" % ", ".join(str(v) for v in vals)


_BEHAVIOR_NAMES = None


def behavior_names():
    """id -> MB_* name, parsed once from the real enum.

    Shared with gen_behavior_constants() rather than re-derived: two parses of
    the same header that could disagree is the drift this project keeps paying
    for elsewhere.
    """
    global _BEHAVIOR_NAMES
    if _BEHAVIOR_NAMES is None:
        _BEHAVIOR_NAMES = {i: n for i, n in enumerate(_behavior_name_list())}
    return _BEHAVIOR_NAMES


def _behavior_name_list():
    import re
    txt = open(os.path.join(REF, "include/constants/metatile_behaviors.h")).read()
    body = re.search(r"enum\s*\{(.*?)\};", txt, re.S).group(1)
    names = []
    for line in body.split("\n"):
        m = re.match(r"\s*(MB_[A-Z0-9_]+)\s*(?:=\s*(\d+))?\s*,", line)
        if m:
            if m.group(2):
                names = names[:int(m.group(2))]
            names.append(m.group(1))
    return names


def gen_behavior_constants():
    """
    Emit all 240 MB_* metatile-behaviour constants as GDScript.

    Generated, never hand-typed: §1.3 counts 240 constants (213 named, 27
    UNUSED), and the directional/ledge subset the step resolver depends on
    sits at non-obvious indices (MB_JUMP_SOUTH = 59, MB_IMPASSABLE_NORTH = 50).
    """
    names = _behavior_name_list()

    out = [
        # @tool must be the FIRST line -- Godot requires the annotation ahead of
        # everything, and MapOverlay is an editor surface: a non-@tool script is
        # instantiated as a PLACEHOLDER in the editor and any call into one
        # throws. The overlay's whole read chain must carry it.
        "@tool",
        "# GENERATED by scripts/gen_map_import.py — do not edit by hand.",
        "# Source: include/constants/metatile_behaviors.h (%d constants)." % len(names),
        "# See docs/overworld_scope.md §1.3 and §1.7.",
        "class_name MetatileBehavior",
        "extends RefCounted",
        "",
    ]
    for i, n in enumerate(names):
        out.append("const %s := %d" % (n, i))
    # [Step B] id -> name, generated alongside the constants so the two cannot
    # drift. The overlay needs it for two things: labelling a cell, and deciding
    # what "untagged" means -- a behaviour with no MB_* name. Measured: zero of
    # the 83 behaviours present across all 421 imported maps are unnamed, so
    # magenta can only ever flag a hand-painted cell, never imported data.
    # UNUSED_* entries are deliberately INCLUDED: source names them, so they are
    # tagged, just not meaningful.
    out += [
        "",
        "## id -> MB_* name. Generated with the constants above; see"
        " StepResolver.is_untagged_behavior().",
        "const NAME_BY_ID := {",
    ]
    for i, n in enumerate(names):
        out.append('\t%d: "%s",' % (i, n))
    out.append("}")

    out += [
        "",
        "# §1.7 — directional blocking is TWO-SIDED: the exit rule is applied to",
        "# the tile being left, the entry rule to the tile being entered, and the",
        "# two tables are mirror images. Implementing only one side looks correct",
        "# across most of the world and wrong exactly where it matters.",
        "const BLOCKED_NORTH := [MB_IMPASSABLE_NORTH, MB_IMPASSABLE_NORTHEAST,"
        " MB_IMPASSABLE_NORTHWEST, MB_IMPASSABLE_SOUTH_AND_NORTH]",
        "const BLOCKED_SOUTH := [MB_IMPASSABLE_SOUTH, MB_IMPASSABLE_SOUTHEAST,"
        " MB_IMPASSABLE_SOUTHWEST, MB_IMPASSABLE_SOUTH_AND_NORTH]",
        "const BLOCKED_EAST := [MB_IMPASSABLE_EAST, MB_IMPASSABLE_NORTHEAST,"
        " MB_IMPASSABLE_SOUTHEAST, MB_IMPASSABLE_WEST_AND_EAST]",
        "const BLOCKED_WEST := [MB_IMPASSABLE_WEST, MB_IMPASSABLE_NORTHWEST,"
        " MB_IMPASSABLE_SOUTHWEST, MB_IMPASSABLE_WEST_AND_EAST]",
        "",
        "# Ported from sElevationToPriority (event_object_movement.c). Elevation",
        "# drives entity DRAW ORDER, not just movement permission: lower value",
        "# draws on top. Note 4 -> 1 (above the overhang plane) but 5 -> 2, back",
        "# to ground level — the odd/even alternation that produces stacked",
        "# multi-tier bridges. Guessing 'upper vs lower' would get elevation 5",
        "# wrong on the three Sevii maps that use it.",
        "const ELEVATION_TO_PRIORITY := %s" % _elev_priority(),
        "",
        "const LEDGE_SOUTH := MB_JUMP_SOUTH",
        "const LEDGE_NORTH := MB_JUMP_NORTH",
        "const LEDGE_EAST := MB_JUMP_EAST",
        "const LEDGE_WEST := MB_JUMP_WEST",
        "",
    ]
    p = assert_inside_project(
        os.path.join(PROJECT, "scripts", "overworld", "metatile_behavior.gd"),
        "metatile_behavior.gd output")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("\n".join(out))
    print("behaviors: %s  (%d constants)" % (p, len(names)))
    return names


def gen_map_constants():
    """
    Emit source's own MAP_* constant -> map DIRECTORY name as GDScript.

    Generated, never hand-typed, because the two are not related by any string
    transform: MAP_SSANNE_EXTERIOR -> SSAnne_Exterior_Frlg. A warp stores the
    constant (Warp.dest_map); the baked scene is named after the directory.
    Resolving one to the other is what lets the overlay flag a warp whose
    destination has no baked scene, and is the same lookup M27C's stitching
    needs to turn a warp into an actual load.

    EVERY region is emitted, not just Kanto. That is deliberate: a constant
    ABSENT from this table means the importer produced a destination source
    does not define -- an importer bug -- which is a different diagnosis from
    a destination that exists and simply has not been baked yet, the expected
    M27C gap. Filtering to Kanto would collapse those two into one symptom.
    """
    import glob as _glob
    rows = {}
    for f in sorted(_glob.glob(os.path.join(REF, "data/maps/*/map.json"))):
        try:
            m = json.load(open(f))
        except Exception:
            continue
        mid = m.get("id", "")
        if not mid.startswith("MAP_"):
            continue
        name = os.path.basename(os.path.dirname(f))
        # A duplicate id would make the lookup silently ambiguous, and the
        # overlay would flag whichever one lost. Fail the build instead.
        assert mid not in rows, "duplicate map id %s (%s and %s)" % (
            mid, rows[mid], name)
        rows[mid] = name

    out = [
        # @tool for the same reason MetatileBehavior carries it: this is read
        # from an editor surface, and a non-@tool script is instantiated as a
        # PLACEHOLDER in the editor -- any call into one throws.
        "@tool",
        "# GENERATED by scripts/gen_map_import.py — do not edit by hand.",
        "# Source: data/maps/*/map.json ('id' field -> containing directory).",
        "# %d maps across every region; see docs/overworld_scope.md §32." % len(rows),
        "class_name MapConstants",
        "extends RefCounted",
        "",
        "## Where map_baker.gd writes its artifacts.",
        'const BAKED_DIR := "res://scenes/maps/"',
        "",
        "## MAP_* constant -> map name. The map name is BOTH the baked scene's"
        " filename",
        "## and MapData.map_name, so one lookup answers both.",
        "const NAME_BY_CONSTANT := {",
    ]
    for mid in sorted(rows):
        out.append('\t"%s": "%s",' % (mid, rows[mid]))
    out += [
        "}",
        "",
        "",
        "## Empty when source defines no such constant — which is an IMPORTER",
        "## bug, not a missing bake. Callers must keep the two apart.",
        "static func map_name_for(map_constant: String) -> String:",
        '\treturn NAME_BY_CONSTANT.get(map_constant, "")',
        "",
        "",
        "## Path the baker WOULD write for this destination. Empty for an",
        "## unknown constant. Says nothing about whether the file exists.",
        "static func scene_path_for(map_constant: String) -> String:",
        "\tvar n := map_name_for(map_constant)",
        '\treturn "" if n == "" else BAKED_DIR + n + ".tscn"',
        "",
        "",
        "## True only when the destination is both a real map AND already baked.",
        "static func is_baked(map_constant: String) -> bool:",
        "\tvar p := scene_path_for(map_constant)",
        '\treturn p != "" and ResourceLoader.exists(p)',
        "",
    ]
    p = assert_inside_project(
        os.path.join(PROJECT, "scripts", "overworld", "map_constants.gd"),
        "map_constants.gd output")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("\n".join(out))
    print("map constants: %s  (%d maps)" % (p, len(rows)))
    return rows


def gen_movement_types():
    """
    Emit every MOVEMENT_TYPE_* constant, plus the four that face one fixed way.

    Two consumers, both about the same failure. `NPC.movement_type` is a plain
    exported String, so retyping one in the inspector -- the fastest way to
    turn a rotating trainer into a fixed-facing one -- accepts a typo in
    silence. Once the overlay draws sight lines off that string, a typo does
    not merely do nothing: it removes the trainer's ray, which looks exactly
    like a trainer who legitimately has none.

    So the set is generated (a hand-typed list would rot against source) and
    both NPC and MapOverlay check membership rather than assuming.
    """
    import re
    txt = open(os.path.join(
        REF, "include/constants/event_object_movement.h")).read()
    names = re.findall(r"^#define\s+(MOVEMENT_TYPE_[A-Z0-9_]+)\s", txt, re.M)
    assert len(names) > 60, "expected the full movement-type set, got %d" % len(names)

    # The only four whose facing is both fixed and knowable from the type
    # alone. Everything else either rotates in place or walks, and source
    # resolves its direction at runtime from live object state the overlay
    # does not have. Sourced from gInitialMovementTypeFacingDirections
    # (event_object_movement.c) -- for these four the initial facing is also
    # the ONLY facing, which is exactly what makes them drawable.
    fixed = {
        "MOVEMENT_TYPE_FACE_UP": "Vector2i(0, -1)",
        "MOVEMENT_TYPE_FACE_DOWN": "Vector2i(0, 1)",
        "MOVEMENT_TYPE_FACE_LEFT": "Vector2i(-1, 0)",
        "MOVEMENT_TYPE_FACE_RIGHT": "Vector2i(1, 0)",
    }
    for k in fixed:
        assert k in names, "%s is not a real movement type" % k

    out = [
        "@tool",
        "# GENERATED by scripts/gen_map_import.py — do not edit by hand.",
        "# Source: include/constants/event_object_movement.h (%d types)." % len(names),
        "class_name MovementTypes",
        "extends RefCounted",
        "",
        "## Every movement type source defines. Membership is what tells a",
        "## typo apart from a type this project simply cannot draw.",
        "const ALL := [",
    ]
    for n in names:
        out.append('\t"%s",' % n)
    out += [
        "]",
        "",
        "## The four with a single, permanent facing -> unit step in cell space.",
        "## y is DOWN, matching cell coordinates rather than source's own",
        "## DIR_SOUTH/DIR_NORTH naming.",
        "const FIXED_FACING := {",
    ]
    for k, v in fixed.items():
        out.append('\t"%s": %s,' % (k, v))
    out += [
        "}",
        "",
        "",
        "static func is_known(t: String) -> bool:",
        "\treturn t in ALL",
        "",
        "",
        "## True only for a type this project can draw a sight line for.",
        "static func has_fixed_facing(t: String) -> bool:",
        "\treturn FIXED_FACING.has(t)",
        "",
    ]
    p = assert_inside_project(
        os.path.join(PROJECT, "scripts", "overworld", "movement_types.gd"),
        "movement_types.gd output")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("\n".join(out))
    print("movement types: %s  (%d types, %d fixed-facing)"
          % (p, len(names), len(fixed)))
    return names


_SCRIPT_INDEX = None


def build_script_index():
    """
    label -> script body, across the WHOLE data/ tree.

    Trainer identity is NOT in map.json: an object event carries only a script
    label, and the TRAINER_X constant lives in the script body — often in a
    shared file (data/scripts/trainers_frlg.inc) rather than the map's own
    scripts.inc. Indexing per-map files alone resolves 46%; indexing the whole
    tree resolves 432/432 Kanto trainer placements (docs/overworld_scope.md §32).
    """
    global _SCRIPT_INDEX
    if _SCRIPT_INDEX is not None:
        return _SCRIPT_INDEX
    import re, glob as _g
    idx = {}
    # The body pattern is deliberately UNCAPPED. An earlier version capped it at
    # 800 chars, which did not truncate long bodies -- it made the match fail
    # outright, silently dropping 677 labels and costing 41 real trainer
    # resolutions elsewhere in the tree. Measured: uncapped is the same 0.07s.
    for path in _g.glob(os.path.join(REF, "data/**/*.inc"), recursive=True):
        try:
            txt = open(path, errors="ignore").read()
        except Exception:
            continue
        for m in re.finditer(r"^(\w+)::\s*\n(.*?)(?=^\w+::|\Z)", txt, re.S | re.M):
            label, body = m.group(1), m.group(2)
            # First writer wins on a duplicate label, so glob order would decide
            # identity. Harmless only while duplicates never disagree -- assert
            # that rather than assume it, because a mis-keyed trainer fails
            # SILENTLY into the wrong battle, which is far worse than a miss.
            if label in idx:
                if _trainer_key_in(body) and _trainer_key_in(body) != _trainer_key_in(idx[label]):
                    raise SystemExit(
                        "duplicate script label %s resolves to conflicting trainers "
                        "(%s vs %s) -- glob order would decide which battle starts"
                        % (label, _trainer_key_in(idx[label]), _trainer_key_in(body))
                    )
                continue
            idx[label] = body
    _SCRIPT_INDEX = idx
    return idx


def _trainer_key_in(body):
    """The TRAINER_X a script body fights with, or "" -- shared by the indexer's
    own conflict check and trainer_key_for()."""
    import re
    m = re.search(r"trainerbattle\w*\s+(TRAINER_[A-Z0-9_]+)", body)
    return m.group(1) if m else ""


def trainer_key_for(label):
    """The CANONICAL trainer key a placement's script fights with.

    [Step 5] Routed through canonical_key(), so an emitted placement carries
    TRAINER_LASS_ROBIN_FRLG rather than the bare source constant. The suffix
    rule lives only in scripts/trainer_keys.py -- reproducing it here would be
    the exact drift that makes a placement point at a trainer that does not
    exist (Rule A, docs/overworld_scope.md).
    """
    if not label or label in ("0x0", "NULL"):
        return ""
    raw = _trainer_key_in(build_script_index().get(label, ""))
    if not raw:
        return ""
    # canonical_key() raises on a constant neither header defines. Deliberately
    # not caught: that means the script index and the constants headers
    # disagree, which is a real finding and should stop the build rather than
    # emit a placement nobody can resolve.
    return canonical_key(raw)


def extract_events(mp):
    """
    map.json's four event arrays -> one normalised list.

    object_events split three ways by their own fields: TRAINER_TYPE_NORMAL is
    a trainer, the item-ball graphic is a pickup, everything else is an NPC.
    Note `trainer_sight_or_berry_tree_id` really is the sight range (§32).
    """
    out = []
    for e in mp.get("object_events", []) or []:
        gfx = str(e.get("graphics_id", ""))
        tt = str(e.get("trainer_type", ""))
        kind = "npc"
        if tt == "TRAINER_TYPE_NORMAL":
            kind = "trainer"
        elif "ITEM_BALL" in gfx:
            kind = "item_ball"
        ev = {
            "kind": kind, "x": int(e.get("x", 0)), "y": int(e.get("y", 0)),
            "elevation": int(e.get("elevation", 3)),
            "graphics_id": gfx,
            "movement_type": str(e.get("movement_type", "")),
            "flag": str(e.get("flag", "")),
            "script": str(e.get("script", "")),
            "local_id": str(e.get("local_id", "")),
        }
        if kind == "trainer":
            ev["trainer_key"] = trainer_key_for(ev["script"])
            # the field doubles as a berry-tree id elsewhere; here it is range
            try:
                ev["sight_range"] = int(e.get("trainer_sight_or_berry_tree_id", 0))
            except (TypeError, ValueError):
                ev["sight_range"] = 0
        out.append(ev)

    # [M27C C5] `warp_id` is this warp's own index in the map's warp array, and
    # it is emitted rather than re-derived downstream because THIS is the only
    # place the ordering is authoritative. A `dest_warp_id` addresses a warp by
    # position, so every consumer needs that same ordering; leaving it implicit
    # means the baker preserving node order is load-bearing and unasserted, and
    # a reorder would send every arrival in Kanto to the wrong tile while
    # looking like a content bug. Recording the index turns an assumption into
    # data.
    for i, e in enumerate(mp.get("warp_events", []) or []):
        out.append({"kind": "warp", "x": int(e.get("x", 0)), "y": int(e.get("y", 0)),
                    "elevation": int(e.get("elevation", 3)),
                    "warp_id": i,
                    "dest_map": str(e.get("dest_map", "")),
                    "dest_warp_id": str(e.get("dest_warp_id", ""))})

    for e in mp.get("coord_events", []) or []:
        out.append({"kind": "trigger", "x": int(e.get("x", 0)), "y": int(e.get("y", 0)),
                    "elevation": int(e.get("elevation", 3)),
                    "var": str(e.get("var", "")), "var_value": str(e.get("var_value", "")),
                    "script": str(e.get("script", ""))})

    for e in mp.get("bg_events", []) or []:
        out.append({"kind": "sign", "x": int(e.get("x", 0)), "y": int(e.get("y", 0)),
                    "elevation": int(e.get("elevation", 3)),
                    "bg_type": str(e.get("type", "")),
                    "facing": str(e.get("player_facing_dir", "")),
                    "script": str(e.get("script", "")),
                    "item": str(e.get("item", "")), "flag": str(e.get("flag", ""))})
    return out


def build_tileset_dir_map():
    """
    gTileset_XXX -> {metatiles, tiles, palettes} directories, resolved
    PER FIELD because a tileset does not necessarily own its own graphics.

      headers.h   gTileset_X = { .metatiles = gMetatiles_A,
                                 .tiles     = gTilesetTiles_B,
                                 .palettes  = gTilesetPalettes_C }
      metatiles.h gMetatiles_A       -> INCBIN "data/tilesets/<kind>/<dir>/..."
      graphics.h  gTilesetTiles_B    -> INCGFX  "data/tilesets/<kind>/<dir>/..."

    Three shortcuts all fail, each found the hard way:
      * lowercasing the label — gTileset_PalletTown is `pallet_town_frlg`
      * assuming label == metatiles symbol — gTileset_BuildingFrlg points at
        gMetatiles_Building_Frlg (extra underscore), which cost all 234
        indoor maps
      * assuming one directory per tileset — gTileset_SilphCo has NO tiles.png
        or palettes of its own and borrows both from Condominiums, which cost
        the 20 Silph Co / Rocket Hideout / elevator maps
    """
    import re
    hdr = open(os.path.join(REF, "src/data/tilesets/headers.h")).read()
    fields = {}
    for m in re.finditer(
            r"const struct Tileset (gTileset_\w+)\s*=\s*\{(.*?)\n\};", hdr, re.S):
        body = m.group(2)

        def grab(name):
            g = re.search(r"\.%s\s*=\s*(\w+)" % name, body)
            return g.group(1) if g else None

        fields[m.group(1)] = {
            "metatiles": grab("metatiles"),
            "tiles": grab("tiles"),
            "palettes": grab("palettes"),
        }

    sym_dir = {}
    mt = open(os.path.join(REF, "src/data/tilesets/metatiles.h")).read()
    for m in re.finditer(
            r'(gMetatiles_\w+)\[\]\s*=\s*INCBIN_U16\("data/tilesets/(\w+)/([\w/]+)/', mt):
        sym_dir[m.group(1)] = (m.group(2), m.group(3))
    gx = open(os.path.join(REF, "src/data/tilesets/graphics.h")).read()
    for m in re.finditer(
            r'(gTilesetTiles_\w+)\[\]\s*=\s*INCGFX_U32\("data/tilesets/(\w+)/([\w/]+)/', gx):
        sym_dir[m.group(1)] = (m.group(2), m.group(3))
    for m in re.finditer(
            r'(gTilesetPalettes_\w+)\[\]\[\d+\]\s*=\s*\{\s*\n?\s*INCGFX_U16\("data/tilesets/(\w+)/([\w/]+)/',
            gx):
        sym_dir[m.group(1)] = (m.group(2), m.group(3))

    out = {}
    for label, f in fields.items():
        r = {}
        for k, sym in f.items():
            if sym and sym in sym_dir:
                r[k] = sym_dir[sym]
        # the palette INCGFX path already includes the `palettes/` segment
        if "palettes" in r and r["palettes"][1].endswith("/palettes"):
            r["palettes"] = (r["palettes"][0], r["palettes"][1][:-len("/palettes")])
        if len(r) == 3:
            out[label] = r
    return out


class Tileset:
    """Primary + secondary resolved into one addressable space."""

    def __init__(self, primary, secondary):
        def d(spec, key):
            return os.path.join(REF, "data/tilesets", spec[key][0], spec[key][1])

        pp = d(primary, "metatiles")
        sp = d(secondary, "metatiles")

        self.tiles = load_tiles(os.path.join(d(primary, "tiles"), "tiles.png"))
        sec_tiles = load_tiles(os.path.join(d(secondary, "tiles"), "tiles.png"))
        # Secondary tiles start at NUM_TILES_IN_PRIMARY_FRLG regardless of how
        # many the primary actually shipped — pad rather than concatenate.
        while len(self.tiles) < NUM_TILES_IN_PRIMARY_FRLG:
            self.tiles.append([[0] * 8 for _ in range(8)])
        self.tiles += sec_tiles

        ppal = d(primary, "palettes")
        spal = d(secondary, "palettes")
        self.pals = [load_pal(os.path.join(ppal, "palettes/%02d.pal" % i))
                     for i in range(NUM_PALS_IN_PRIMARY_FRLG)]
        self.pals += [load_pal(os.path.join(spal, "palettes/%02d.pal" % i))
                      for i in range(NUM_PALS_IN_PRIMARY_FRLG, 16)]

        self.metatiles = load_u16(os.path.join(pp, "metatiles.bin"))
        sec_meta = load_u16(os.path.join(sp, "metatiles.bin"))
        need = NUM_METATILES_IN_PRIMARY_FRLG * NUM_TILES_PER_METATILE
        while len(self.metatiles) < need:
            self.metatiles.append(0)
        self.metatiles += sec_meta

        self.attrs = load_u32(os.path.join(pp, "metatile_attributes.bin"))
        sec_attr = load_u32(os.path.join(sp, "metatile_attributes.bin"))
        while len(self.attrs) < NUM_METATILES_IN_PRIMARY_FRLG:
            self.attrs.append(0)
        self.attrs += sec_attr

        # §1.2's assertion: entry counts must agree, or the attribute width
        # is being read wrong. Fails loudly rather than misparsing silently.
        assert len(self.metatiles) // NUM_TILES_PER_METATILE == len(self.attrs), (
            "metatiles/attributes disagree: %d vs %d — check FRLG 32-bit width"
            % (len(self.metatiles) // NUM_TILES_PER_METATILE, len(self.attrs)))

        self.count = len(self.attrs)

    def behavior(self, mid):
        return self.attrs[mid] & METATILE_ATTR_BEHAVIOR_MASK_FRLG

    def layer_type(self, mid):
        return (self.attrs[mid] & METATILE_ATTR_LAYER_MASK_FRLG) >> \
            METATILE_ATTR_LAYER_SHIFT_FRLG

    def _blit_half(self, mid, half, img, ox, oy):
        """Draw one 2x2 tile half (0=bottom, 1=top) into img at (ox,oy)."""
        base = mid * NUM_TILES_PER_METATILE + half * 4
        drew = False
        for i in range(4):
            e = self.metatiles[base + i]
            tidx = e & 0x03FF
            hflip = (e >> 10) & 1
            vflip = (e >> 11) & 1
            pal = self.pals[(e >> 12) & 0x0F]
            if tidx >= len(self.tiles):
                continue
            grid = self.tiles[tidx]
            tx, ty = (i % 2) * 8, (i // 2) * 8
            for y in range(8):
                for x in range(8):
                    sx = 7 - x if hflip else x
                    sy = 7 - y if vflip else y
                    ci = grid[sy][sx]
                    if ci == 0:
                        continue  # index 0 is transparent, always
                    r, g, b = pal[ci]
                    img.putpixel((ox + tx + x, oy + ty + y), (r, g, b, 255))
                    drew = True
        return drew


def build_atlases(ts):
    """One 16x16 cell per metatile, per plane. Returns (images, usage)."""
    cols = 32
    rows = (ts.count + cols - 1) // cols
    imgs = [Image.new("RGBA", (cols * 16, rows * 16), (0, 0, 0, 0))
            for _ in range(3)]
    usage = [0, 0, 0]

    for mid in range(ts.count):
        ox, oy = (mid % cols) * 16, (mid // cols) * 16
        lt = ts.layer_type(mid)

        # §1.6 routing table.
        if lt == LAYER_COVERED:
            pairs = [(0, PLANE_GROUND), (1, PLANE_OBJECTS)]
        elif lt == LAYER_SPLIT:
            pairs = [(0, PLANE_GROUND), (1, PLANE_OVERHANGS)]
        else:  # LAYER_NORMAL — Bg3 gets garbage in source; we leave it empty
            pairs = [(0, PLANE_OBJECTS), (1, PLANE_OVERHANGS)]

        for half, plane in pairs:
            if ts._blit_half(mid, half, imgs[plane], ox, oy):
                usage[plane] += 1

    return imgs, usage


# Tileset objects are expensive to build and heavily shared across maps
# (general_frlg alone backs most of the region), so cache by directory pair.
_TS_CACHE = {}


def atlas_slug(prim, sec):
    """Stable name for a tileset PAIR. 421 Kanto maps use only 60 distinct
    pairs, so atlases are shared: 180 PNGs instead of 1,263, and the biggest
    pair (BuildingFrlg + GenericBuilding2) backs 51 maps on its own."""
    return "%s__%s" % (prim["metatiles"][1].replace("/", "_"),
                       sec["metatiles"][1].replace("/", "_"))


def get_tileset(prim, sec):
    key = (str(prim), str(sec))
    if key not in _TS_CACHE:
        _TS_CACHE[key] = Tileset(prim, sec)
    return _TS_CACHE[key]



# map.json spells connection directions as screen words; the reference's own
# `enum Connection` (include/constants/global.h) is compass-based. These
# ordinals match that enum exactly, so MapData.Connection can be read straight
# against source. NOTE the crossover: "up" is NORTH, "down" is SOUTH.
#
# Measured across all 939 maps: left 68 / right 68 / up 58 / down 58, and
# dive 7 / emerge 7. The dive/emerge pair is real but appears nowhere in the
# Kanto corridor, and per §1 it warps rather than stitching geometry — carried
# through the data so a later tier need not re-derive it, consumed by nothing.
CONNECTION_DIRS = {"down": 1, "up": 2, "left": 3, "right": 4, "dive": 5, "emerge": 6}

# 441 of 785 layouts omit border_width/border_height ENTIRELY, and every one of
# them ships a 4-entry border.bin — so the reference's own default is 2x2.
# Seven layouts declare 3x2, which is why this is a default rather than a
# constant: hardcoding 2x2 would silently mis-shape those seven.
DEFAULT_BORDER_W, DEFAULT_BORDER_H = 2, 2


# [M27C C5] Behaviours the reference will actually fire a warp from, gathered
# from FOUR separate code paths in field_control_avatar.c — missing any one of
# them silently marks real warps inert:
#   IsWarpMetatileBehavior      step-on: doors, ladders, escalators, holes
#   IsArrowWarpMetatileBehavior direction-gated arrows
#   IsDirectionalStairWarp...   stair warps, a path of its own (103 region-wide)
#   TryDoorWarp                 animated doors, north only
#
# Names taken from the predicates rather than guessed: IsUnionRoomWarp is
# MB_BRIDGE_OVER_OCEAN, IsNorthArrowWarp includes MB_STAIRS_OUTSIDE_ABANDONED_SHIP,
# and IsSouthArrowWarp includes MB_SHOAL_CAVE_ENTRANCE — none of which read as
# warps from the constant name alone.
WARP_TRIGGER_BEHAVIORS = {
    "MB_ANIMATED_DOOR", "MB_LADDER", "MB_UP_ESCALATOR", "MB_DOWN_ESCALATOR",
    "MB_NON_ANIMATED_DOOR", "MB_WATER_DOOR", "MB_DEEP_SOUTH_WARP",
    "MB_SOUTH_ARROW_WARP", "MB_WATER_SOUTH_ARROW_WARP", "MB_SHOAL_CAVE_ENTRANCE",
    "MB_NORTH_ARROW_WARP", "MB_STAIRS_OUTSIDE_ABANDONED_SHIP",
    "MB_WEST_ARROW_WARP", "MB_EAST_ARROW_WARP",
    "MB_DOWN_LEFT_STAIR_WARP", "MB_DOWN_RIGHT_STAIR_WARP",
    "MB_UP_LEFT_STAIR_WARP", "MB_UP_RIGHT_STAIR_WARP",
    "MB_AQUA_HIDEOUT_WARP", "MB_MT_PYRE_HOLE", "MB_BRIDGE_OVER_OCEAN",
    "MB_MOSSDEEP_GYM_WARP", "MB_LAVARIDGE_GYM_B1F_WARP", "MB_LAVARIDGE_GYM_1F_WARP",
}


def extract_connections(mp):
    """map.json's connection list -> normalised {direction, map, offset}.

    `map` stays the raw MAP_* constant rather than a resolved directory, and
    that is deliberate: it matches what a Warp already stores in `dest_map`, so
    both kinds of link resolve through the one MapConstants table. Keeping the
    constant also preserves a distinction resolving here would destroy — a
    destination source does not define at all (a bug) reads differently from
    one that is merely unbaked (the expected M27C gap).

    Offset is NOT decorative: 104 of 266 connections across the reference carry
    a nonzero one. Pallet Town's two are both 0, which makes the corridor a
    misleading sample to generalise from.
    """
    out = []
    for c in (mp.get("connections") or []):
        d = str(c.get("direction", ""))
        assert d in CONNECTION_DIRS, "unknown connection direction %r" % d
        assert c.get("map"), "connection with no map constant: %r" % c
        out.append({
            "direction": CONNECTION_DIRS[d],
            "map": str(c["map"]),
            "offset": int(c.get("offset", 0)),
        })
    return out


def _stamp_warp_triggers(events, mids, ts, w, h):
    """Record whether the REFERENCE would fire each warp from its own tile.

    [M27C C5] This project decouples "a warp exists here" from "this tile is a
    door", because the coupling means a hand-placed warp on an ordinary tile
    silently never fires — the failure class §1.9 already exists to prevent for
    collision. So presence decides, and this flag carries the imported fidelity.

    Measured: 214 of 1294 warps sit on MB_NORMAL and are fired by nothing. They
    are not arrival points either — the flanking tiles of a multi-tile doorway,
    where exactly one tile carries the arrow behaviour that actually triggers.
    Oak's Lab is the worked example: (6,12) is MB_SOUTH_ARROW_WARP, while
    (5,12) and (7,12) are inert. Importing those as triggers would silently
    widen every doorway in Kanto; hand-placed warps default to true instead.
    """
    names = behavior_names()
    for e in events:
        if e.get("kind") != "warp":
            continue
        x, y = int(e["x"]), int(e["y"])
        beh_name = ""
        if 0 <= x < w and 0 <= y < h:
            beh_name = names.get(ts.behavior(mids[y * w + x]), "")
        e["triggers"] = beh_name in WARP_TRIGGER_BEHAVIORS
    return events


def convert(map_dir, dirmap, layouts, render=False, quiet=False):
    """
    Convert one map. Always validates and writes per-cell JSON; only builds
    atlases and previews when `render` is set, because the image work is
    ~100x the cost and 421 maps of atlases would be tens of megabytes.
    Returns a stats dict, or raises AssertionError on anything unmeasured.
    """
    mp = json.load(open(os.path.join(REF, "data/maps", map_dir, "map.json")))
    lay = layouts[mp["layout"]]
    ts = get_tileset(dirmap[lay["primary_tileset"]], dirmap[lay["secondary_tileset"]])

    blk = load_u16(os.path.join(REF, lay["blockdata_filepath"]))
    w, h = lay["width"], lay["height"]
    assert len(blk) == w * h, "%s: map.bin %d cells, layout says %d" % (
        map_dir, len(blk), w * h)

    mids = [v & MAPGRID_METATILE_ID_MASK for v in blk]
    coll = [(v & MAPGRID_COLLISION_MASK) >> MAPGRID_COLLISION_SHIFT for v in blk]
    elev = [(v & MAPGRID_ELEVATION_MASK) >> MAPGRID_ELEVATION_SHIFT for v in blk]

    # §1.4 / §1.7 guards — an unmeasured value means an authored map or a
    # reference update, and must fail loudly rather than bucket silently.
    bad_e = sorted({e for e in elev} - {0, 1, 3, 4, 5, 15})
    assert not bad_e, "%s: unexpected elevation %s" % (map_dir, bad_e)
    bad_c = sorted({c for c in coll} - {0, 1})
    assert not bad_c, "%s: unexpected collision %s" % (map_dir, bad_c)
    bad_m = [m for m in mids if m >= ts.count]
    assert not bad_m, "%s: %d metatile ids past the tileset (max %d)" % (
        map_dir, len(bad_m), ts.count - 1)

    # [M27C C1] The border block: what gets painted outside the map's own
    # bounds on any edge with no loadable neighbour. Same u16 block format as
    # map.bin, so it reuses load_u16 and the same metatile-id mask; only the
    # id is kept, because a skirt cell's impassability is a runtime rule
    # (§ "Border blocks via programmatic skirt") rather than something read
    # out of the collision bits here.
    bw = lay.get("border_width", DEFAULT_BORDER_W)
    bh = lay.get("border_height", DEFAULT_BORDER_H)
    braw = load_u16(os.path.join(REF, lay["border_filepath"]))
    assert len(braw) == bw * bh, "%s: border.bin %d cells, layout says %dx%d" % (
        map_dir, len(braw), bw, bh)
    border = [v & MAPGRID_METATILE_ID_MASK for v in braw]
    # The border's own layer types, for the same reason the map has them: a
    # metatile routes to one or two of the three planes by §1.6, and a skirt
    # that paints only the ground plane renders HALF A BLOCK. Pallet Town's own
    # border is the worked example -- ids 28/29 are COVERED (ground+objects)
    # while 20/21 are NORMAL (objects+overhangs, nothing on ground at all), so
    # painting ground-only left every other row blank. Found by screenshot; the
    # cell COUNT was already correct, which is exactly what a count cannot see.
    border_layer_type = [ts.layer_type(m) for m in border]
    bad_b = [m for m in border if m >= ts.count]
    assert not bad_b, "%s: %d border metatile ids past the tileset (max %d)" % (
        map_dir, len(bad_b), ts.count - 1)

    slug = mp["name"]
    prim = dirmap[lay["primary_tileset"]]
    sec = dirmap[lay["secondary_tileset"]]
    # [Rider 2] The atlas name is a computed string -- atlas_slug() does no image
    # work -- so it is emitted for EVERY map regardless of `render`. It used to be
    # added only on the render path, which meant `gen_map_import.py all` wrote
    # JSON with no atlas field and the baker died on
    # "missing atlas res://assets/map_atlases/_ground.png". The fresh-checkout
    # announce line tells people to run exactly that mode, so the trap was
    # directly in the documented path. `render` now gates only PNG generation.
    aslug = atlas_slug(prim, sec)
    data = {
        "name": mp["name"], "layout": lay["id"], "width": w, "height": h,
        "atlas": aslug,
        "metatile": mids, "collision": coll, "elevation": elev,
        "behavior": [ts.behavior(m) for m in mids],
        "layer_type": [ts.layer_type(m) for m in mids],
        # every freshly imported cell is IMPORTED; the overlay flips cells to
        # AUTHORED as they are hand-edited (§1.9 Change 3)
        "provenance": [0] * len(mids),
        # [Change 3] Imported cells are explicit on both attributes: their
        # values came from source and are authoritative, not a guess. Only
        # hand-painted cells start un-decided.
        "attr_explicit": [3] * len(mids),
        "events": _stamp_warp_triggers(extract_events(mp), mids, ts, w, h),
        # [M27C C1] Stitching metadata. Emitted for every map, consumed by
        # nothing yet — C2/C4 build the loader that reads it.
        "connections": extract_connections(mp),
        "border": border, "border_width": bw, "border_height": bh,
        "border_layer_type": border_layer_type,
    }
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(ATLAS_OUT, exist_ok=True)
    json.dump(data, open(os.path.join(OUT, "%s.json" % slug), "w"))

    from collections import Counter
    stats = {"name": slug, "w": w, "h": h, "cells": len(blk),
             "elev": dict(sorted(Counter(elev).items())),
             "coll": dict(sorted(Counter(coll).items())),
             "lt": dict(sorted(Counter(ts.layer_type(m) for m in mids).items())),
             "beh": len({ts.behavior(m) for m in mids})}

    if render:
        # [Rider 2] One writer only. Two json.dump sites that could disagree
        # about the same file is its own bug class -- and did in fact disagree,
        # which is how the atlas field went missing on the all-corpus path.
        imgs, _ = build_atlases(ts)
        for img, nm in zip(imgs, ["ground", "objects", "overhangs"]):
            ap = os.path.join(ATLAS_OUT, "%s_%s.png" % (aslug, nm))
            if not os.path.exists(ap):          # shared across every map on this pair
                img.save(ap)

        def draw(planes, bg):
            out = Image.new("RGBA", (w * 16, h * 16), bg)
            for plane in planes:
                for i, mid in enumerate(mids):
                    sx, sy = (mid % 32) * 16, (mid // 32) * 16
                    out.alpha_composite(imgs[plane].crop((sx, sy, sx + 16, sy + 16)),
                                        ((i % w) * 16, (i // w) * 16))
            return out

        draw([PLANE_GROUND, PLANE_OBJECTS, PLANE_OVERHANGS], (0, 0, 0, 255)).save(
            os.path.join(OUT, "%s_preview.png" % slug))
        draw([PLANE_OVERHANGS], (40, 40, 60, 255)).save(
            os.path.join(OUT, "%s_above.png" % slug))
        if not quiet:
            print("       atlas -> %s" % aslug)

    if not quiet:
        print("  %-42s %3dx%-3d cells=%-6d elev=%-22s lt=%-18s beh=%d"
              % (slug, w, h, len(blk), stats["elev"], stats["lt"], stats["beh"]))
    return stats


# Chosen from measured structure (docs/overworld_scope.md §33): the rarest
# layer type, both upper elevations, the largest and most extreme-aspect maps,
# the widest behaviour spread, heavy secondary usage, water, multi-connection
# cities — plus Pallet Town as a known-good control.
SUBSET = [
    "PalletTown_Frlg",
    "SixIsland_RuinValley_Frlg",
    "SeafoamIslands_B4F_Frlg",
    "DiglettsCave_B1F_Frlg",
    "SaffronCity_Frlg",
    "FourIsland_Frlg",
    "Route23_Frlg",
    "SSAnne_Exterior_Frlg",
]


def main():
    import glob as _glob
    layouts = {l["id"]: l for l in json.load(
        open(os.path.join(REF, "data/layouts/layouts.json")))["layouts"]}
    gen_behavior_constants()
    gen_map_constants()
    gen_movement_types()
    dirmap = build_tileset_dir_map()
    print("tileset labels resolved: %d" % len(dirmap))

    mode = sys.argv[1] if len(sys.argv) > 1 else "subset"

    if mode == "all":
        dirs = []
        for f in sorted(_glob.glob(os.path.join(REF, "data/maps/*/map.json"))):
            try:
                m = json.load(open(f))
            except Exception:
                continue
            if m.get("region") == "REGION_KANTO":
                dirs.append(os.path.basename(os.path.dirname(f)))
        print("converting %d Kanto maps (data + assertions only)...\n" % len(dirs))
        ok = 0
        fails = []
        agg_e, agg_c, agg_lt = {}, {}, {}
        for d in dirs:
            try:
                st = convert(d, dirmap, layouts, render=False, quiet=True)
                ok += 1
                for k, v in st["elev"].items():
                    agg_e[k] = agg_e.get(k, 0) + v
                for k, v in st["coll"].items():
                    agg_c[k] = agg_c.get(k, 0) + v
                for k, v in st["lt"].items():
                    agg_lt[k] = agg_lt.get(k, 0) + v
            except Exception as e:
                fails.append((d, str(e)[:110]))
        print("converted    : %d/%d" % (ok, len(dirs)))
        print("elevation    : %s" % dict(sorted(agg_e.items())))
        print("collision    : %s" % dict(sorted(agg_c.items())))
        print("layer types  : %s" % {["NORMAL", "COVERED", "SPLIT"][k]: v
                                     for k, v in sorted(agg_lt.items())})
        if fails:
            print("\nFAILURES (%d):" % len(fails))
            for d, e in fails[:20]:
                print("  %-42s %s" % (d, e))
        else:
            print("\nno assertion failures across the region")
        return 0 if not fails else 1

    targets = SUBSET if mode == "subset" else sys.argv[1:]
    print("rendering %d maps...\n" % len(targets))
    for d in targets:
        convert(d, dirmap, layouts, render=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
