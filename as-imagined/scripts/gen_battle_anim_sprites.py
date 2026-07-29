#!/usr/bin/env python3
r"""[M36A] Battle-anim sprite pull: reference PNGs -> assets/sprites/battle_anims/.

Scope of record: docs/m26_f1_recon.md (M36A = Phase A3). Reads the tag table
produced by gen_battle_anim_meta.py and materialises one ready-to-load PNG per
ANIM_TAG, so the M36B runtime never has to know about palettes, .pal files, or
build-time sheet assembly.

Why one file per TAG rather than per source sheet: the reference deliberately
reuses one tile sheet under several tags with DIFFERENT palettes (the
"one sheet, N recolors" pattern — gBattleAnimSpriteGfx_GreenLightWall serves 5
tags, 43 palette symbols are shared, 26 gfx symbols are shared). On the GBA the
recolor is free (palette bank swap at load); Godot has no indexed-palette
runtime, so the recolor is BAKED HERE, at extraction time. Tag-keyed output is
therefore both unique and directly loadable. This is the same approach every
prior sprite pull in this project took, and it is why the file count exceeds
the 383-distinct-source-sheet figure.

What this handles, each verified against the tree rather than assumed:

- Palette source may be the sheet's own embedded PLTE (most tags), a sibling
  JASC `.pal` file (46 in battle_anims/sprites), or ANOTHER png's palette
  (e.g. Dreepy shiny; Ivy Cudgel borrows four Ogerpon mon palettes). All three
  resolve through the same code path: get 16 RGB triples, apply to the indexed
  gfx image.
- Five sheets are BUILD-TIME COMPOSITES: `ice_cube.4bpp`, `ice_crystals.4bpp`,
  `mud_sand.4bpp`, `flower.4bpp`, `spark.4bpp` do not exist as PNGs; the
  makefile `cat`s numbered part files together (`ice_cube_0..3.4bpp`).
  It concatenates TILE DATA, not images, and the parts have DIFFERENT pixel
  dimensions (spark_0 is 8x64, spark_1 is 16x64; ice_cube's four parts are
  64x64/64x32/32x64/32x32) — so naive image stacking would be wrong. Parts are
  therefore decomposed into 8x8 tiles in raster order, concatenated as a tile
  STREAM (exactly what `cat` produces), and re-laid-out into one sheet.
  The assembled tile count is asserted against the tag's own declared VRAM
  size (bytes / 32), so a mis-assembly cannot pass silently.
  Note `spark_h.png` and `spark_2.png` exist on disk but are NOT part of the
  spark composite (the recipe takes spark_0/1 only); they are left alone.

- Tile addressing is the universal invariant this pull preserves: gbagfx
  converts with a 1x1 metatile, so GBA tile N is always the Nth 8x8 tile in
  RASTER order of the source PNG. Every output here keeps that property (the
  index records `tiles_wide`), which is what lets ANIMCMD_FRAME's tile offsets
  be resolved against any frame size — necessary because several composite
  tags are consumed at two or three different OAM sizes at once
  (ANIM_TAG_SPARK is used as 8x8 and 8x16; ANIM_TAG_FLOWER as 8x8 and 16x16).
- Palette index 0 is the GBA's transparency key and the source PNGs carry no
  tRNS chunk, so every output is written with `transparency = 0` — the same
  defect-and-fix this project already hit in gen_hit_effect_sprites.py and
  gen_ball_sprites.py.
- The two explicit NULL rows (ANIM_TAG_UNAVAILABLE_1/2) are skipped, as is
  ANIM_TAG_SAFARI_BAIT, which has no table entry at all upstream.

Output: assets/sprites/battle_anims/<tag>.png  (tag = ANIM_TAG_X -> x.png)
plus assets/sprites/battle_anims/index.json mapping tag -> file, size, frames.

Idempotent; overwrites unconditionally. Requires Pillow.
"""

import json
import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_path import REF, PROJECT, assert_inside_project

TAGS_JSON = os.path.join(PROJECT, "data", "battle_anims", "tags.json")
OUT_DIR = assert_inside_project(
    os.path.join(PROJECT, "assets", "sprites", "battle_anims"),
    "battle_anims sprite dir")
INDEX_PATH = os.path.join(OUT_DIR, "index.json")


def read_jasc_pal(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if lines[0] != "JASC-PAL":
        raise SystemExit("not a JASC palette: %s" % path)
    count = int(lines[2])
    colors = []
    for line in lines[3:3 + count]:
        r, g, b = (int(v) for v in line.split())
        colors.extend((r, g, b))
    return colors


def load_palette(rel_path):
    """Return a flat RGB list for a palette source (.pal or .png)."""
    abs_path = os.path.join(REF, rel_path)
    if rel_path.endswith(".pal"):
        return read_jasc_pal(abs_path)
    with Image.open(abs_path) as im:
        if im.mode != "P":
            raise SystemExit("palette source not indexed: %s" % rel_path)
        pal = im.getpalette()
    return pal


def tiles_of(img):
    """Split an indexed image into 8x8 tiles in raster order — the exact
    order gbagfx emits them (default 1x1 metatile)."""
    if img.width % 8 or img.height % 8:
        raise SystemExit("image not tile-aligned: %dx%d"
                         % (img.width, img.height))
    out = []
    for ty in range(img.height // 8):
        for tx in range(img.width // 8):
            out.append(img.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    return out


def assemble_composite(entry, rel):
    stem = re.sub(r"\.4bpp$", "", rel)
    tiles, palette = [], None
    widths = []
    for i in range(entry["gfx_parts"]):
        ppath = os.path.join(REF, "%s_%d.png" % (stem, i))
        if not os.path.exists(ppath):
            raise SystemExit("composite part missing: %s" % ppath)
        with Image.open(ppath) as part:
            if part.mode != "P":
                raise SystemExit("composite part not indexed: %s" % ppath)
            if palette is None:
                palette = part.getpalette()
            widths.append(part.width)
            tiles.extend(tiles_of(part))

    declared = entry["size"] // 32  # 4bpp: 32 bytes per 8x8 tile
    if len(tiles) != declared:
        raise SystemExit(
            "composite %s assembled %d tiles but the tag declares %d "
            "(VRAM 0x%x)" % (rel, len(tiles), declared, entry["size"]))

    # Lay the stream out at the widest part's width, padding the last row so
    # the sheet stays rectangular. Padding only ever appends past the last
    # real tile, so tile N's raster position is unchanged.
    tiles_wide = max(widths) // 8
    rows = (len(tiles) + tiles_wide - 1) // tiles_wide
    canvas = Image.new("P", (tiles_wide * 8, rows * 8), 0)
    canvas.putpalette(palette)
    for n, tile in enumerate(tiles):
        canvas.paste(tile, ((n % tiles_wide) * 8, (n // tiles_wide) * 8))
        tile.close()
    return canvas


def load_gfx(entry):
    """Return an indexed PIL image for a tag's tile sheet, assembling the
    build-time composites from their numbered parts."""
    rel = entry["gfx"]
    if entry.get("gfx_kind") == "composite":
        return assemble_composite(entry, rel)
    abs_path = os.path.join(REF, rel)
    if not os.path.exists(abs_path):
        raise SystemExit("gfx source missing: %s" % abs_path)
    im = Image.open(abs_path)
    if im.mode != "P":
        raise SystemExit("gfx source not indexed: %s" % rel)
    return im.copy()


def main():
    with open(TAGS_JSON) as f:
        tags = json.load(f)["tags"]

    os.makedirs(OUT_DIR, exist_ok=True)
    index = {}
    written = composites = recolored = 0

    for tag_name, entry in sorted(tags.items(), key=lambda kv: kv[1]["index"]):
        if entry["gfx"] is None:
            continue  # ANIM_TAG_UNAVAILABLE_1 / _2
        img = load_gfx(entry)
        if entry.get("gfx_kind") == "composite":
            composites += 1

        if entry["palette"] and entry["palette"] != entry["gfx"]:
            img.putpalette(load_palette(entry["palette"]))
            recolored += 1

        img.info["transparency"] = 0
        out_name = tag_name.replace("ANIM_TAG_", "").lower() + ".png"
        out_path = os.path.join(OUT_DIR, out_name)
        img.save(out_path, transparency=0)

        # Frame layout: sheets are vertical strips whose WIDTH is the frame
        # width, so frame height == width for square frames; the runtime gets
        # the authoritative per-template size from the OAM data in
        # templates.json, so this records the sheet's own geometry only.
        index[tag_name] = {
            "file": out_name,
            "index": entry["index"],
            "width": img.width,
            "height": img.height,
            "tiles_wide": img.width // 8,
            "tiles": (img.width // 8) * (img.height // 8),
            "vram_size": entry["size"],
            "source": entry["gfx"],
            "palette_source": entry["palette"],
        }
        img.close()
        written += 1

    with open(INDEX_PATH, "w") as f:
        json.dump({"meta": {
            "generated_by": "scripts/gen_battle_anim_sprites.py [M36A]",
            "count": written}, "sprites": index},
            f, separators=(",", ":"), sort_keys=True)

    print("wrote %d PNGs to %s" % (written, os.path.relpath(OUT_DIR, PROJECT)))
    print("  composites assembled: %d   palette-recolored: %d"
          % (composites, recolored))
    print("  index: %s" % os.path.relpath(INDEX_PATH, PROJECT))


if __name__ == "__main__":
    main()
