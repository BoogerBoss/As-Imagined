#!/usr/bin/env python3
"""
[M26E1] Pulls the real Bag-screen art from the already-vendored Emerald UI
Pack 1.2 (assets/Emerald UI Pack 1.2/Graphics/UI/Bag/), per the decisions
locked in docs/m26_e2_recon.md's own §0a (2026-08-05).

Usage (from project root):
    python3 scripts/gen_bag_sprites.py

Pulled (source filename -> project filename), all under
assets/sprites/battle_ui/bag/:

- bg_m.png / bg_f.png -> bag_bg_male.png / bag_bg_female.png. The real
  four-region background (pocket tab top-left, item-list box top-right,
  item-icon slot left-middle, description box bottom), 512x384. No player-
  gender concept exists anywhere in this project yet, so `bag_bg_male.png`
  is the one actually wired (item_select_screen.gd/field_bag_screen.gd);
  the female variant is pulled anyway, matching this project's own
  established "pull the whole set even if one entry has no consumer yet"
  precedent (`[M27D D1]`/`[M26B3-1]`).
- icon_pocket.png -> bag_pocket_icons.png. A 168x48, 16x16-per-cell icon
  grid (two rows in use — selected/unselected state — the sheet's own 3rd
  row is unused by the pack's own bundled scene script). Pulled now
  (asset-pull phase) for E2's own pocket-tab row to consume later; not
  wired by E1 itself, which has no tab UI.
- bag_1.png ... bag_6.png (+ _f variants) -> bag_sprite_1.png ...
  bag_sprite_6.png (+ _f). The small "the bag itself" sprite, one per
  pocket, that leans/bounces on a pocket-cycle (`pbBagJump`). Per
  docs/m26_e2_recon.md's own §7 decision 5 (recommended mapping):
  bag_1=Items, bag_2=Poké Balls, bag_3=TM/HM, bag_4=Berries, bag_5=Key
  Items, bag_6=unused.
- icon_pokeball.png -> bag_ball_flash.png. A 32x224, 7-frame vertical
  strip — the tiny ball-flash animation played alongside the bag-jump
  lean. Built now per decision 4 (bag-jump animation shipped in E1, not
  deferred).

Deliberately NOT pulled, per docs/m26_e2_recon.md's own §7/§5:
- cursor.png / cursor_swap.png — this project reuses its own existing "▶"
  glyph cursor (decision 3); cursor_swap.png backs a reordering "sort mode"
  this project has no feature for.
- icon_hm.png — no per-row item icon is shown by this screen at all
  (matching source's own real list-drawing function, which uses
  BlitBitmapToWindow only for the TM/HM slot's icon and a "registered
  item" indicator — neither reproduced here).
- icon_register.png — no Select-button quick-item slot exists anywhere in
  this project.

Step 0 findings (measured directly via PIL, not assumed): every P-mode file
here (bag_N.png/_f, icon_pokeball.png) already carries a real embedded PNG
tRNS chunk (`'transparency' in im.info`), which PIL's own P->RGBA convert
already resolves correctly — a plain flat copy is correct and sufficient,
same as `gen_databox_sprites.py`'s own precedent, no runtime color-keying
needed for any file this script pulls. icon_pocket.png is already native
RGBA. bg_m.png/bg_f.png are opaque P-mode backgrounds with no transparency
key at all (correct — a full-screen backdrop has nothing to key out).
"""

import os
from PIL import Image

PACK_BAG_DIR = os.path.join(
    "assets", "Emerald UI Pack 1.2", "Graphics", "UI", "Bag")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "bag")

# (source filename in the pack, output filename in this project)
FILES = [
    ("bg_m.png", "bag_bg_male.png"),
    ("bg_f.png", "bag_bg_female.png"),
    ("icon_pocket.png", "bag_pocket_icons.png"),
    ("icon_pokeball.png", "bag_ball_flash.png"),
    ("bag_1.png", "bag_sprite_1.png"),
    ("bag_1_f.png", "bag_sprite_1_f.png"),
    ("bag_2.png", "bag_sprite_2.png"),
    ("bag_2_f.png", "bag_sprite_2_f.png"),
    ("bag_3.png", "bag_sprite_3.png"),
    ("bag_3_f.png", "bag_sprite_3_f.png"),
    ("bag_4.png", "bag_sprite_4.png"),
    ("bag_4_f.png", "bag_sprite_4_f.png"),
    ("bag_5.png", "bag_sprite_5.png"),
    ("bag_5_f.png", "bag_sprite_5_f.png"),
    ("bag_6.png", "bag_sprite_6.png"),
    ("bag_6_f.png", "bag_sprite_6_f.png"),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, dst_name in FILES:
        src_path = os.path.join(PACK_BAG_DIR, src_name)
        dst_path = os.path.join(OUT_DIR, dst_name)
        img = Image.open(src_path).convert("RGBA")
        img.save(dst_path)
        print(f"{src_name} ({img.size[0]}x{img.size[1]}) -> {dst_path}")


if __name__ == "__main__":
    main()
