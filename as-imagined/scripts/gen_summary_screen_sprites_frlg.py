#!/usr/bin/env python3
"""
[M26 Fire-Red art swap, pivot] Replaces this file's own previous approach --
a raw pokefirered-expansion GBA tile/tilemap/palette decode -- with a flat
pull from a ready-composited Essentials plugin pack, `assets/FRLG Summary
Screen/` (real plugin, "FRLG Summary Screen" v2.0, Essentials 21, by
Shashu-Greninja/Pnick0509/Superjustinbros/Lucidious89 -- confirmed via its
own meta.txt), the same "Emerald UI Pack" shape this project's own
`gen_databox_sprites.py`/M26c-1 already established as the preferred source
whenever one exists: a real designed screen, not a byte-for-byte hardware
tile reconstruction.

Rob's own call, after the raw-decode output shipped with a real, confirmed
defect (the whole top-left portrait quadrant rendering as a void, since
Fire Red's real BG-tile data genuinely leaves that region blank -- the
portrait is a separate hardware SPRITE there, not BG-tile content -- and
this project's own dark `Backdrop` node showed through it instead of the
real game's pale backdrop color). That defect is structurally impossible
with this pack's own art: every `bg_*.png` is a single, fully OPAQUE
512x384 canvas with the portrait-box art (a light "lined notebook paper"
placeholder rect) already baked directly into the pixel content, not left
as a hardware-transparent hole.

## Real coordinate source

`Plugins/FRLG Summary Screen/[001] Essentials Scripts/001_UI_Summary.rb`
draws its own text/icon overlay directly onto this pack's `bg_*.png` canvas,
in the SAME 512x384 coordinate space -- e.g. `drawPageOne`'s real label
positions (`textpos = [[_INTL("Dex No."), 238+70, 86-40, ...], ...]`),
`drawPageTwoStats`'s real stat-value positions, `drawPageThree`'s real
move-row Y stride (`yPos = 44; yPos += 68` per row). Used as this session's
own real layout reference for repositioning `summary_screen.tscn`'s
existing label nodes (which live in a 960x640 space -- 1.875x/1.6667x the
pack's own 512x384 canvas, since `GbaLayer` stretches whatever background
texture is assigned to fill that fixed box regardless of the source
texture's own native resolution) -- see that `.tscn`'s own per-node history
for the exact values carried over.

## Page mapping (confirmed from the Ruby script's own page-index logic,
## `pbScene`'s `@page` clamp to 1..3 plus `drawPage(page)`'s own dispatch)

- bg_1.png  -> INFO page   (`drawPageOne`)   -> summary_frlg_frame_base.png
                (the PERSISTENT base layer every page's portrait column
                shows through, matching this project's own established
                PortraitBase role since the original Emerald-era rework).
- bg_2.png  -> SKILLS page (`drawPageTwo`)   -> summary_frlg_page_skills.png
- bg_3.png  -> MOVES page  (`drawPageThree`) -> summary_frlg_page_moves.png
- bg_movedetail.png -> the MOVES page's own move-SELECTED state
  (`drawPageThreeSelecting`/`drawSelectedMove`, real, distinct background
  swap in this pack's own design -- NOT wired into `_PAGE_OVERLAY` this
  session, since `summary_screen.gd`'s own move-detail panel is drawn as a
  plain overlay on the ordinary MOVES background today; pulled ahead of
  that future consumer, matching this project's established convention for
  exactly this shape of asset (see `gen_summary_screen_sprites.py`'s own
  precedent for HP-bar/EXP-bar/cursor pulls ahead of their own wiring)).

This pack has NO dedicated EV/IV background (`Settings::SUMMARY_EV_IV`'s
own `drawPageTwoEVIV` reuses bg_2.png's SKILLS canvas and just draws
different text over it -- confirmed via direct read, not assumed) --
`summary_frlg_page_evs_ivs.png` is therefore bg_2.png reused verbatim, a
disclosed placeholder matching how this project's own EVS/IVS page has no
real dynamic content built yet either (E4-4, still open).

bg_egg.png / bg_learnmove.png are deliberately NOT pulled -- matches this
project's own already-locked "no eggs, no move-learning UI" scope note,
carried over unchanged from the raw-decode script this one replaces.

## What this script deliberately does NOT touch

This pack's own `Graphics/UI/category.png` / `types.png` / `statuses.png`
(outside the `Summary/` subfolder) are NOT pulled here -- this project
already has its own separately-sourced, already-wired type-badge/move-
category-icon/status-icon systems (`_type_badge_texture`/
`_category_icon_texture`, the switch/party screens' own status-icon row),
and duplicating a second copy of the same concept from a different pack
would be new, unrequested scope, not a reasonable reading of "swap the
background art."

This pack's own `overlay_hp.png`/`overlay_exp.png`/`icon_pokerus.png`/
`cursor_move.png`/`overlay_shiny.png`/`markings*.png`/`icon_ball_*.png`
(29 ball variants) are ALSO not pulled this session -- none of the
raw-decode script's own equivalent flat-sprite pulls were ever wired into
any code either (confirmed at the time: "None of these flat sprites are
wired into any code yet"), so re-sourcing them from this cleaner pack is
zero-risk but also zero immediate payoff; flagged here for a future
session to pick up wholesale once any of them actually gets a real
consumer, rather than guessed at piecemeal now.

Usage (from project root):
    python3 scripts/gen_summary_screen_sprites_frlg.py
"""

import os
from PIL import Image

PACK_SUMMARY_DIR = os.path.join(
    "assets", "FRLG Summary Screen", "Graphics", "UI", "Summary")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "summary")

# (source filename in the pack, output filename in this project)
FILES = [
    ("bg_1.png", "summary_frlg_frame_base.png"),
    ("bg_2.png", "summary_frlg_page_skills.png"),
    ("bg_3.png", "summary_frlg_page_moves.png"),
    ("bg_2.png", "summary_frlg_page_evs_ivs.png"),  # placeholder, see doc header
    ("bg_movedetail.png", "summary_frlg_page_movedetail.png"),  # pulled ahead of its own consumer
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, dst_name in FILES:
        src_path = os.path.join(PACK_SUMMARY_DIR, src_name)
        dst_path = os.path.join(OUT_DIR, dst_name)
        img = Image.open(src_path).convert("RGBA")
        img.save(dst_path)
        print(f"{src_name} ({img.size[0]}x{img.size[1]}) -> {dst_path}")


if __name__ == "__main__":
    main()
