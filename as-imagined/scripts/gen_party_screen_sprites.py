#!/usr/bin/env python3
"""
[M26E3-1] Pulls the real Party/Switch screen art from the already-vendored
Emerald UI Pack 1.2 (assets/Emerald UI Pack 1.2/), per the Route B decision
recorded in docs/m26_e3_recon.md §0a — superseding SwitchSelectScreen's own
prior M25h-4-era decoded-tilemap art (party_frame.png/party_slot_wide.png),
which stays on disk but is no longer consumed by that screen after this
pull.

Usage (from project root):
    python3 scripts/gen_party_screen_sprites.py

Step 0 findings (measured directly via PIL pixel inspection, not assumed):

- Every panel/overlay/icon file here already carries a real PNG tRNS chunk
  PIL resolves via `.convert("RGBA")` — confirmed per-file, not assumed
  uniform with earlier pack pulls (panel_blank.png/icon_item.png/icon_mail
  .png are already plain RGBA with no palette at all). A plain flat copy is
  correct and sufficient; no runtime color-keying is needed for anything
  this script pulls.
- bg.PNG/bg_double.png (512x384) and overlay_hp.png (96x24) are the one
  real exception: neither carries a "transparency" key in its own PIL
  .info dict. This is CORRECT, not a gap to fix — both are meant to be
  fully opaque (a full-screen background mockup; three stacked solid HP
  color bands), confirmed via direct pixel inspection, matching the same
  "some pack files are genuinely meant to be opaque" finding already
  documented for bag_bg_male.png/overlay_hp.png's own battle-screen
  sibling in earlier pulls.
- Real panel/background coordinates were measured directly (a border-
  color pixel scan of bg.PNG/bg_double.png, cross-checked against the
  pack's own 004_Party.rb assembly recipe), not eyeballed — recorded in
  switch_select_screen.gd's own layout constants, not duplicated here.
- statuses.png (a shared pack-wide sheet, Graphics/UI/statuses.png) is
  deliberately NOT pulled by this script, per the recon's own decision
  ("reuse existing sheet or pack statuses.png — pick one, they encode the
  same rows"): this project already has a working, already-tested status-
  icon sheet + _party_status_icon_row mapping (party_status_icons.png,
  M25h-4 Part C) that encodes the identical AILMENT_* row order — pulling
  a second, equivalent sheet would be pure duplication for zero gain.
- shiny.png is likewise NOT pulled — the shiny indicator is explicitly
  deferred (docs/m26_e3_recon.md §0a decision 5), matching this project's
  own "flag, don't build" precedent for features with no underlying
  concept anywhere in the codebase yet.
- Mon icons (386 files, 32x64, 2-frame) are NOT pulled here — they already
  exist at assets/sprites/pokemon/icon/ from an earlier reference pull
  (sprite_registry.gd's own get_icon(), currently a documented zero-
  consumer stub) and are reference-sourced rather than pack-sourced; this
  screen's own E3-2 sub-phase is their first real consumer.
"""

import os
from PIL import Image

PACK_PARTY_DIR = os.path.join(
    "assets", "Emerald UI Pack 1.2", "Graphics", "UI", "Party")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "party")

# (source filename in the pack, output filename in this project)
FILES = [
    # Panels — 7 states each, round (the active-mon slot) and rect (bench
    # rows). "_base" is appended to the otherwise-suffixless source name so
    # every one of the 7 states reads as a sibling in a file listing.
    ("panel_round.png", "panel_round_base.png"),
    ("panel_round_sel.png", "panel_round_sel.png"),
    ("panel_round_faint.png", "panel_round_faint.png"),
    ("panel_round_faint_sel.png", "panel_round_faint_sel.png"),
    ("panel_round_swap.png", "panel_round_swap.png"),
    ("panel_round_swap_sel.png", "panel_round_swap_sel.png"),
    ("panel_round_swap_sel2.png", "panel_round_swap_sel2.png"),
    ("panel_rect.png", "panel_rect_base.png"),
    ("panel_rect_sel.png", "panel_rect_sel.png"),
    ("panel_rect_faint.png", "panel_rect_faint.png"),
    ("panel_rect_faint_sel.png", "panel_rect_faint_sel.png"),
    ("panel_rect_swap.png", "panel_rect_swap.png"),
    ("panel_rect_swap_sel.png", "panel_rect_swap_sel.png"),
    ("panel_rect_swap_sel2.png", "panel_rect_swap_sel2.png"),
    ("panel_blank.png", "panel_blank.png"),
    # Full-screen background mockups (512x384 = exactly 2x this project's
    # own 1024x768 base canvas, M26A1).
    ("bg.PNG", "party_bg_singles.png"),
    ("bg_double.png", "party_bg_doubles.png"),
    # HP kit.
    ("overlay_hp.png", "party_hp_zones.png"),
    ("overlay_hp_back.png", "party_hp_trough.png"),
    ("overlay_hp_back_faint.png", "party_hp_trough_faint.png"),
    ("overlay_hp_back_swap.png", "party_hp_trough_swap.png"),
    # Glyphs/chrome.
    ("overlay_lv.png", "party_lv_icon.png"),
    ("overlay_male.png", "party_gender_male.png"),
    ("overlay_female.png", "party_gender_female.png"),
    ("icon_ball.PNG", "party_ball_icon.png"),
    ("icon_ball_sel.PNG", "party_ball_icon_sel.png"),
    ("icon_cancel.png", "party_cancel_icon.png"),
    ("icon_cancel_sel.png", "party_cancel_icon_sel.png"),
    ("icon_item.png", "party_item_icon.png"),
    ("icon_mail.png", "party_mail_icon.png"),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, dst_name in FILES:
        src_path = os.path.join(PACK_PARTY_DIR, src_name)
        dst_path = os.path.join(OUT_DIR, dst_name)
        img = Image.open(src_path).convert("RGBA")
        img.save(dst_path)
        print(f"{src_name} ({img.size[0]}x{img.size[1]}) -> {dst_path}")


if __name__ == "__main__":
    main()
