#!/usr/bin/env python3
"""
[M26q-1] Pulls the move-category (Physical/Special/Status) icon set.

Usage (from project root):
    python3 scripts/gen_category_sprites.py

Step 0 findings:

- Two vendored reskin packs (Emerald UI Pack 1.2, Essentials_v19.1) also
  carry a `category.png`, but neither has a confirmable clean 3-frame
  split (56x66 and 64x84 respectively — neither height divides into 3
  equal frames cleanly against the sheet's own width). Rather than guess
  a slice rect, this pulls the real, unambiguous source asset instead:
  `reference/pokeemerald_expansion/graphics/interface/category_icons.png`
  is a clean 16x48 sheet, 3 stacked 16x16 frames (Physical/Special/
  Status, top to bottom — see pokemon_summary_screen.c's own
  sSpriteAnimTable_CategoryIcons: tile offset 0/4/8 = frame 0/1/2 at
  16x16 each), matching the same direct-from-reference precedent already
  used for the 18 type icons (M23.11 Phase 1) instead of the databox/
  message-overlay precedent of copying from a UI reskin pack.
- 8-bit palette-indexed, no PNG transparency chunk. Palette index 0 is
  RGB(143,241,177) at every frame's own corner (confirmed identical
  across all 3 frames, not sprite-to-sprite coincidental) -- the same
  "index 0 = background" GBA OBJ-layer convention gen_hit_effect_sprites
  .py already established and tags explicitly, since these particular
  source files don't carry a tRNS chunk despite the hardware rule
  requiring index-0 transparency for any sprite (not background) layer.
"""

from pathlib import Path
from PIL import Image

from ref_path import REF

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(REF) / "graphics/interface/category_icons.png"
DST_DIR = ROOT / "assets/sprites/battle_ui/category"

FRAME_SIZE = 16
FRAME_NAMES = ["physical", "special", "status"]  # top-to-bottom frame order


def main() -> None:
    DST_DIR.mkdir(parents=True, exist_ok=True)
    img = Image.open(SRC)
    assert img.mode == "P", f"expected palette mode, got {img.mode}"
    assert img.size == (FRAME_SIZE, FRAME_SIZE * len(FRAME_NAMES)), img.size

    bg_index = img.getpixel((0, 0))
    img.info["transparency"] = bg_index

    for i, name in enumerate(FRAME_NAMES):
        frame = img.crop((0, i * FRAME_SIZE, FRAME_SIZE, (i + 1) * FRAME_SIZE))
        frame.info["transparency"] = bg_index
        rgba = frame.convert("RGBA")
        out_path = DST_DIR / f"{name}.png"
        rgba.save(out_path)
        print(f"wrote {out_path} ({rgba.size[0]}x{rgba.size[1]})")


if __name__ == "__main__":
    main()
