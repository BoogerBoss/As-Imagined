#!/usr/bin/env python3
"""
[M26c-1] Pulls the real in-battle HP/name/level "databox" art from the
already-vendored Emerald UI Pack 1.2 (assets/Emerald UI Pack 1.2/, a real
Essentials plugin by Voltseon/ENLS targeting Essentials v21.1 — confirmed
via its own meta.txt during the M26a-era investigation), superseding the
Phase 4b-era raw-pokeemerald-decode health-box art per the explicit M26
decision to source most UI screens from this pack rather than continuing to
decode raw reference/pokeemerald_expansion graphics.

Usage (from project root):
    python3 scripts/gen_databox_sprites.py

Step 0 findings (measured directly via PIL pixel inspection, not assumed):

- Graphics/UI/Battle/databox_normal.png (260x84) is the PLAYER's own box —
  taller than the opponent's own box specifically to include a real EXP-bar
  "ledge" in its bottom ~24px, confirmed via direct crop/preview: a real
  "EXP" label (baked in, yellow) followed by an empty dotted EXP-bar
  background, matching the real games' own player-only EXP bar. databox_
  normal_foe.png (260x62) is the opponent's own box — no EXP ledge at all,
  matching the real games' own player-only EXP bar (never shown for an
  opponent's mon, which has no OT to gain Exp).
- Graphics/UI/Battle/databox_thin.png / databox_thin_foe.png (both 260x62)
  are the doubles-format boxes (confirmed via direct pixel measurement that
  their own internal HP-bar row sits at the exact same y=38-45 as the
  singles boxes, just without the extra EXP-ledge height below it) — NO
  EXP-bar variant exists for either doubles box in this pack at all,
  matching the real games' own "no EXP bar in doubles" convention; this is
  why the EXP bar this session builds is scoped to the singles player box
  only, not just a design choice made in isolation.
- The "HP" label is BAKED DIRECTLY into all 4 box files as real pixel art
  (confirmed via direct pixel inspection) — this supersedes the old Phase
  4b approach of layering a separate HpLabel TextureRect (sourced from
  hpbar.png's own left region) on top; that node is now redundant and
  removed by this session's own battle_screen.tscn edit.
- Every file here already carries real native PNG alpha transparency
  (confirmed via direct corner-pixel inspection: (0,0,0,0) at every box's
  4 rounded corners, and a real 'transparency' key in each file's own PIL
  .info dict) — UNLIKE the raw ROM-decoded assets earlier phases pulled,
  which needed manual color-keying at runtime. A pure flat copy (this
  script's own approach) is correct and sufficient; no _color_keyed_texture
  -style post-processing is needed for any file this script pulls.
- overlay_hp.png (96x12) and overlay_exp.png (170x4) are NOT detailed
  texture assets at all — each is just 1-3 solid, uniform-color horizontal
  bands (overlay_hp.png: 3 stacked shadow/highlight color PAIRS for the
  green/yellow/red HP-bar states; overlay_exp.png: one single flat light-
  blue color) with zero pixel detail worth preserving as a texture file —
  a plain tinted TextureProgressBar fill (this project's own established
  `tint_progress` pattern, already used for the HP bar since Phase 4b)
  reproduces them exactly. Neither file is pulled as an asset by this
  script; their real sampled RGB values are hardcoded directly into
  battle_screen.gd's own `_hp_bar_color()` / `_EXP_BAR_COLOR` instead —
  the same "extract the real value, don't manage a whole file for a flat
  color" precedent already used elsewhere in this project.
- overlay_lv.png (a real "Lv" icon glyph) and icon_numbers.png (a real
  0-9 plus "/" digit-glyph sheet, for a numeric "42/100" HP readout) both
  exist in the pack and are genuinely real/usable, but are deliberately
  NOT pulled by this session: NameLevelLabel's existing real bitmap-font
  text ("Species LvNN") already covers the "Lv" case with no need for a
  second image-based rendering path, and this project has never displayed
  a numeric HP readout in any form since M23.1 -- adding one is new scope
  beyond "swap the box art to the new pack," not a reasonable-to-assume
  extension of it. Flagged here for a future session, not silently built.
"""

import os
from PIL import Image

PACK_BATTLE_DIR = os.path.join(
    "assets", "Emerald UI Pack 1.2", "Graphics", "UI", "Battle")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "interface")

# (source filename in the pack, output filename in this project)
FILES = [
    ("databox_normal.png", "databox_player.png"),
    ("databox_normal_foe.png", "databox_opponent.png"),
    ("databox_thin.png", "databox_doubles_player.png"),
    ("databox_thin_foe.png", "databox_doubles_opponent.png"),
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
