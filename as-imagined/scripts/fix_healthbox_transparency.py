#!/usr/bin/env python3
"""
[M23.11 Phase 4b] Chroma-keys pure black (0,0,0) to transparent in the
health-box background art -- these 2 files (unlike every other asset
pulled in this project's whole M23.11 arc) have NO alpha channel at all
in source (confirmed via direct PIL inspection: 'transparency' not in
im.info), rendering as a solid black rectangle behind the cream panel
once actually placed in a real scene -- found via this phase's own
mandatory screenshot check, not assumed.

Confirmed SAFE before writing this: a full pixel-color histogram of
healthbox_singles_player.png shows pure (0,0,0,255) as the single most
common color (4,807 px) with the next-darkest color being a genuinely
distinct dark green (32,57,0,255) used for the outline stroke -- no risk
of a naive black-key stripping legitimate border pixels.

Usage (from project root):
    python3 scripts/fix_healthbox_transparency.py

Idempotent: re-running is safe -- an already-transparent pixel (alpha=0)
is simply left alone, not double-processed.
"""

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_FILES = [
    os.path.join(ROOT, "assets", "sprites", "battle_ui", "interface", "healthbox_singles_player.png"),
    os.path.join(ROOT, "assets", "sprites", "battle_ui", "interface", "healthbox_singles_opponent.png"),
]


def main():
    for path in TARGET_FILES:
        im = Image.open(path).convert("RGBA")
        pixels = im.load()
        w, h = im.size
        changed = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = pixels[x, y]
                if (r, g, b) == (0, 0, 0) and a != 0:
                    pixels[x, y] = (0, 0, 0, 0)
                    changed += 1
        im.save(path)
        print(f"{os.path.relpath(path, ROOT)}: {changed} pixels keyed to transparent")


if __name__ == "__main__":
    main()
