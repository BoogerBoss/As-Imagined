#!/usr/bin/env python3
"""
[M26o] Pulls the party-status-summary pokeball icon set — the compact
6-ball HP/status row source shows at battle start and after every KO
(CreatePartyStatusSummarySprites, battle_interface.c:1206).

Usage (from project root):
    python3 scripts/gen_party_ball_sprites.py

Step 0 findings:

- Source's own real ball icon is ONE spritesheet addressed by tile-index
  offset (checked in priority order: empty slot/egg -> fainted -> has
  status -> normal), not an HP-fraction color gradient. The vendored
  Emerald UI Pack 1.2 carries the same 4 states as 4 separate flat 14x14
  files rather than one sheet -- a flat per-state copy (mirroring
  gen_databox_sprites.py's own precedent) is correct here, no slicing
  needed.
- icon_ball.png / icon_ball_faint.png are palette-indexed with a real
  PNG tRNS chunk (confirmed via direct PIL .info inspection: transparency
  index present, matching every corner pixel) -- convert("RGBA") alone
  is correct, unlike the message-overlay/health-box precedent that
  needed manual runtime color-keying because THEIR source lacked a tRNS
  chunk. icon_ball_status.png / icon_ball_empty.png already carry native
  RGBA alpha.
- HP fraction itself is intentionally NOT pulled as a texture here --
  this project already has a proven, asset-free `_hp_bar_color()` helper
  (battle_screen.gd) for exactly this, and no confirmed ready-made
  graded-color ball-row asset exists in the pack (overlay_hp.png is a
  flat 3-band strip for the main HP bar, a different UI element).
"""

import os
from PIL import Image

PACK_BATTLE_DIR = os.path.join(
    "assets", "Emerald UI Pack 1.2", "Graphics", "UI", "Battle")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "party_status")

# (source filename in the pack, output filename in this project)
FILES = [
    ("icon_ball.png", "ball_normal.png"),
    ("icon_ball_status.png", "ball_status.png"),
    ("icon_ball_faint.png", "ball_fainted.png"),
    ("icon_ball_empty.png", "ball_empty.png"),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, dst_name in FILES:
        src_path = os.path.join(PACK_BATTLE_DIR, src_name)
        dst_path = os.path.join(OUT_DIR, dst_name)
        img = Image.open(src_path).convert("RGBA")
        img.save(dst_path)
        print(f"{src_name} ({img.size[0]}x{img.size[1]}) -> {dst_path}")


if __name__ == "__main__":
    main()
