#!/usr/bin/env python3
"""
[M27K K-b visuals] Copies the four Oak's-Speech portrait assets (Oak, Red,
Leaf, the rival) from the read-only reference clone into a project-owned,
git-tracked asset directory.

Usage (from project root):
    python3 scripts/gen_oak_speech_assets.py

Why this exists: same rationale as gen_trainer_portraits.py -- reference/
pokeemerald_expansion/ is .gitignore'd and not directly usable by production
code, so this performs a one-time (re-runnable, idempotent) copy of just the
files this project actually needs into res://assets/sprites/oak_speech/,
which IS committed.

Confirmed before writing this script (not assumed): all four are already
64x96 indexed-palette ("P" mode) PNGs with their own embedded palette --
the identical convention gen_trainer_portraits.py already confirmed for the
in-battle front-pic pull -- so a plain copy is correct; no GBA tile/palette
decode step is needed. Unlike the front pics, none carries a transparency
chunk (they are opaque background-blit portraits in source, not sprites
with transparent corners), which does not affect how Godot loads them.

`platform.png` (the 3-frame ground-platform sheet) is ALSO pulled, added
2026-08-05 -- confirmed 32x96 indexed "P"-mode PNG with a transparency
chunk, same plain-copy handling as the portraits (three 32x32 frames
stacked vertically, the same GBA stacked-frame convention documented in
this project's own `docs/m27k_cinematic_recon.md`).

`oak_speech_bg.png` is ALSO decoded, added 2026-08-06 -- closes the "no
background" gap this file's own docstring used to flag as a separate,
undecided task. Confirmed via direct source read (`src/oak_speech.c:127-128`)
this is a standard GBA tile+tilemap pair (`oak_speech_bg.png` a 16x40px = 10
distinct 8x8-tile sheet, `oak_speech_bg.bin` a 1280-byte / 640-u16-entry
tilemap = one full 32x20-cell GBA screen, no scroll margin) using its own
palette-less indexed PNG for tile pixel data and borrowing its actual
render palette from `bg_tiles.png`'s own embedded palette (source's own
comment: "Shared by the Controls Guide, Pikachu Intro and Oak Speech
scenes", `oak_speech.c:124`) -- NOT a palette baked into `oak_speech_bg.png`
itself, which is confirmed decorative/unused for rendering.

Reuses `gen_battle_anim_backgrounds.py`'s own `composite()` (the same
screen-entry-format decoder M36E1 already proved out on 84 battle-anim
backgrounds, incl. a successful Surf-wave decode) rather than a fourth
hand-rolled copy of this project's own GBA tile/tilemap/palette technique
-- one already-tested implementation, not a new one.

Deliberately NOT pulled: anything under `controls_guide_`/`pikachu_intro/`
paths -- both screens are deferred (Rob's call, 2026-08-05).

Idempotent: re-running overwrites the destination files with a fresh copy.
"""

import os
import shutil
import sys

from ref_path import REF

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_battle_anim_backgrounds import composite

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(REF, "graphics", "oak_speech")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "oak_speech")

# dest filename -> source subdirectory (each holds a `pic.png`)
PORTRAITS = {
    "oak.png": "oak",
    "red.png": "red",
    "leaf.png": "leaf",
    "rival.png": "rival",
}

BG_TILES_REL = "graphics/oak_speech/oak_speech_bg.png"
BG_TILEMAP_REL = "graphics/oak_speech/oak_speech_bg.bin"
BG_PALETTE_REL = "graphics/oak_speech/bg_tiles.png"


def _decode_background():
    canvas, _bank_pal, error = composite(
        BG_TILES_REL, BG_TILEMAP_REL, BG_PALETTE_REL, "oak_speech_bg")
    if error:
        print(f"  UNRESOLVED 'oak_speech_bg.png' — {error}")
        return False
    canvas.save(os.path.join(OUT_DIR, "oak_speech_bg.png"))
    return True


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    copied = 0
    total = len(PORTRAITS) + 2  # + platform + background

    for dest_name, subdir in PORTRAITS.items():
        src_path = os.path.join(SRC_DIR, subdir, "pic.png")
        if not os.path.exists(src_path):
            print(f"  UNRESOLVED {dest_name!r} — missing {src_path}")
            continue
        shutil.copyfile(src_path, os.path.join(OUT_DIR, dest_name))
        copied += 1

    platform_src = os.path.join(SRC_DIR, "platform.png")
    if os.path.exists(platform_src):
        shutil.copyfile(platform_src, os.path.join(OUT_DIR, "platform.png"))
        copied += 1
    else:
        print(f"  UNRESOLVED 'platform.png' — missing {platform_src}")

    if _decode_background():
        copied += 1

    print(f"oak_speech assets: {copied}/{total} copied")


if __name__ == "__main__":
    main()
