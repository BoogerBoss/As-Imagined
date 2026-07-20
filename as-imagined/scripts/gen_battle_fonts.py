#!/usr/bin/env python3
"""
[M25h-1.2] Extracts the real GBA bitmap fonts (FONT_NORMAL / FONT_SMALL)
from source and produces Godot-loadable bitmap FontFile assets (AngelCode
BMFont .fnt + atlas PNG), pre-recolored per the real drop-shadow TextColor
convention for each surface this project actually uses.

Usage (from project root):
    python3 scripts/gen_battle_fonts.py

Step 0 findings, re-confirmed directly against source this session (the
M25h-1.2-poc session's own findings could have gone stale):

- Both `latin_normal.png` (FONT_NORMAL, message/menu text) and
  `latin_small.png` (FONT_SMALL, health-box name/level text) are real,
  needed variants -- confirmed via direct grep: `battle_message.c`'s own
  window-text tables use FONT_NORMAL for B_WIN_MSG/B_WIN_ACTION_PROMPT/
  B_WIN_ACTION_MENU, and `battle_interface.c` uses FONT_SMALL (aliased
  `HP_FONT`) for every health-box nickname/level/HP text call site.
  FONT_NARROW (used by source's own B_WIN_MOVE_NAME window specifically)
  is confirmed used nowhere this project's move-name buttons need --
  those are plain Godot Buttons, not a dedicated GBA window -- so it is
  explicitly out of scope; this project's menu buttons reuse the "menu"
  FONT_NORMAL context instead, a disclosed simplification.
- Both source PNGs are 256x512, a 16x16-pixel glyph grid (16 cols x 32
  rows = 512 glyph slots), confirmed identical in structure to each
  other and to the M25h-1.2-poc session's own findings.
- Each glyph cell uses a FIXED 4-color indexed palette representing
  4 semantic ROLES, not literal display colors -- confirmed directly
  from `GenerateFontHalfRowLookupTable` (text.c): raw pixel value 0 is
  the "background" role (the crop-boundary sentinel filling any unused
  width beyond the glyph's own declared width -- confirmed to never
  appear WITHIN a glyph's declared width via direct pixel dump), raw
  value 1 is "foreground", raw value 2 is "shadow", raw value 3 is
  "accent" (the flood-fill bulk of the glyph's own box). Each font's
  own preview/authoring palette maps these 4 roles to fixed preview
  RGBs -- (144,200,255)=background sentinel, (56,56,56)=foreground,
  (216,216,216)=shadow, (255,255,255)=accent -- confirmed identical
  across both latin_normal.png and latin_small.png.
- The REAL per-context colors are NOT the preview palette -- they come
  from each context's own `union TextColor` struct (a background/
  foreground/shadow/accent slot-index quadruple) resolved against the
  actual active palette for that context:
    - message/action-prompt (B_WIN_MSG / B_WIN_ACTION_PROMPT):
      foreground=slot1, shadow=slot6, background=accent=slot15 of
      `graphics/battle_interface/text.pal` (gBattleWindowTextPalette,
      loaded at BG_PLTT_ID(5)) -> foreground=(255,0,0) red,
      shadow=(0,0,0) black, bulk fill=(213,213,205) off-white.
    - menu / action-menu (B_WIN_ACTION_MENU, reused here for every
      menu button label -- Fight/Switch/Item/Run, move names, target
      select): foreground=slot13, shadow=slot15, background=accent=
      slot14 of the SAME text.pal -> foreground=(74,74,74) dark grey,
      shadow=(213,213,205) light grey, bulk fill=(255,255,255) white.
    - health-box name/level text: `sHealthBoxTextColor` (battle_
      interface.c) = {background=0, foreground=1, shadow=3, accent=0}.
      Health-box text is SPRITE (not background/window) text via
      `AddSpriteTextPrinterParameterized6`, so slot 0 is the real GBA
      hardware sprite-transparency index, not an opaque color -- unlike
      the message/menu contexts, background/accent here mean genuinely
      TRANSPARENT, letting this project's own already-pulled health-box
      art (Phase 4b) show through. No separate healthbox-text .pal file
      exists in source; the sprite's own already-pulled embedded palette
      (`healthbox_singles_player.png`) is confirmed the active one for
      this text (no other candidate palette exists) -> foreground=
      slot1=(65,65,65) dark grey, shadow=slot3=(222,213,180) cream,
      background/accent=slot0=TRANSPARENT.
- The message-box red foreground is a genuine, sourced surprise (not
  what a "plain black Pokemon text" assumption would predict) -- flagged
  plainly in this session's own report rather than silently overridden
  to something that "looks more expected," per this project's own
  source-over-assumption discipline. If this turns out to look wrong
  once rendered, that is a real finding for Rob to weigh in on, not a
  bug in this script.
- Recoloring is baked into the atlas PNG at generation time (not a
  runtime Godot shader) -- the simplest robust option, and consistent
  with this project's established static-asset-preprocessing convention
  (every other gen_*.py already does one-time Python-side work rather
  than pushing transforms to the engine at runtime).
"""

import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
REF_FONTS = ROOT / "reference/pokeemerald_expansion/graphics/fonts"
FONTS_C = ROOT / "reference/pokeemerald_expansion/src/fonts.c"
OUT_DIR = ROOT / "assets/fonts"

GLYPH_CELL = 16  # source grid cell size, both axes, both font variants

# charmap.txt: character -> glyph ID, transcribed directly from
# reference/pokeemerald_expansion/charmap.txt (re-checked this session,
# not carried over from the PoC's smaller hand-picked subset).
CHARMAP = {
    " ": 0x00, "!": 0xAB, "?": 0xAC, ".": 0xAD, "-": 0xAE, ",": 0xB8,
    "'": 0xB4, "(": 0x5C, ")": 0x5D, "%": 0x5B, ":": 0xF0, "/": 0xBA,
    "&": 0x2D, "+": 0x2E,
    "0": 0xA1, "1": 0xA2, "2": 0xA3, "3": 0xA4, "4": 0xA5,
    "5": 0xA6, "6": 0xA7, "7": 0xA8, "8": 0xA9, "9": 0xAA,
}
for i in range(26):
    CHARMAP[chr(ord("A") + i)] = 0xBB + i
    CHARMAP[chr(ord("a") + i)] = 0xD5 + i

# [M25h-1.3] The real menu-selection cursor glyph -- confirmed via direct
# source read, not assumed: BOTH of source's two cursor mechanisms (the
# generic list-menu cursor, `RedrawMenuCursor` in menu.c, which literally
# prints `gText_SelectorArrow3 = _("▶")` through the same font/window
# text system a menu's own options use; and the action-selection 2x2 grid's
# own `ActionSelectionCreateCursorAt`, a raw-BG-tile mechanism whose exact
# source tileset file could not be located in this reference checkout) draw
# the same real Pokemon-wide selection marker, a right-pointing triangle.
# Reusing this glyph (already present in the same latin_normal/latin_small
# sheets at charmap id 0xEF, confirmed via direct pixel inspection to be a
# clean filled triangle) means the cursor renders through the exact same
# per-context bitmap-font pipeline as the text it sits beside -- no new
# asset pull, no separate color to source.
CHARMAP["▶"] = 0xEF

# raw preview-palette RGB -> semantic role, confirmed identical across
# both latin_normal.png and latin_small.png
ROLE_BY_RAW_RGB = {
    (144, 200, 255): "background",
    (56, 56, 56): "foreground",
    (216, 216, 216): "shadow",
    (255, 255, 255): "accent",
}


def _parse_width_table(array_name: str) -> list[int]:
    text = FONTS_C.read_text()
    m = re.search(array_name + r"\[\] = \{(.*?)\};", text, re.S)
    if not m:
        raise RuntimeError(f"could not find {array_name} in fonts.c")
    nums = [int(x) for x in re.findall(r"\d+", m.group(1))]
    if len(nums) != 512:
        raise RuntimeError(f"{array_name}: expected 512 entries, got {len(nums)}")
    return nums


FONT_NORMAL_WIDTHS = _parse_width_table("gFontNormalLatinGlyphWidths")
FONT_SMALL_WIDTHS = _parse_width_table("gFontSmallLatinGlyphWidths")

# (source png, width table, real glyph height in px -- confirmed via
# direct pixel dump: content occupies exactly this many rows from the
# top of each 16-tall cell, remainder is background-sentinel padding)
FONT_SOURCES = {
    "normal": (REF_FONTS / "latin_normal.png", FONT_NORMAL_WIDTHS, 15),
    "small": (REF_FONTS / "latin_small.png", FONT_SMALL_WIDTHS, 13),
}

# context name -> (font variant, foreground RGB, shadow RGB, bulk-fill RGBA)
COLOR_CONTEXTS = {
    "latin_normal_message": ("normal", (255, 0, 0), (0, 0, 0), (213, 213, 205, 255)),
    "latin_normal_menu": ("normal", (74, 74, 74), (213, 213, 205), (255, 255, 255, 255)),
    "latin_small_healthbox": ("small", (65, 65, 65), (222, 213, 180), (0, 0, 0, 0)),
}


def _crop_glyph(sheet: Image.Image, glyph_id: int, width: int, height: int) -> Image.Image:
    col = glyph_id % 16
    row = glyph_id // 16
    x0 = col * GLYPH_CELL
    y0 = row * GLYPH_CELL
    return sheet.crop((x0, y0, x0 + width, y0 + height))


def _recolor(tile: Image.Image, fg, shadow, bulk) -> Image.Image:
    target = {"foreground": (*fg, 255), "shadow": (*shadow, 255), "accent": bulk, "background": (0, 0, 0, 0)}
    out = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    src = tile.load()
    dst = out.load()
    for y in range(tile.height):
        for x in range(tile.width):
            role = ROLE_BY_RAW_RGB.get(src[x, y][:3])
            if role is None:
                # shouldn't happen -- defensive fallback to transparent
                continue
            dst[x, y] = target[role]
    return out


def build_context(context_name: str) -> None:
    font_variant, fg, shadow, bulk = COLOR_CONTEXTS[context_name]
    png_path, widths, height = FONT_SOURCES[font_variant]
    sheet = Image.open(png_path).convert("RGBA")

    chars = list(CHARMAP.keys())
    cells = []
    for ch in chars:
        gid = CHARMAP[ch]
        w = widths[gid]
        if w == 0:
            cells.append((ch, gid, w, None))
            continue
        tile = _crop_glyph(sheet, gid, w, height)
        cells.append((ch, gid, w, _recolor(tile, fg, shadow, bulk)))

    total_w = sum(c[2] for c in cells)
    atlas = Image.new("RGBA", (max(total_w, 1), height), (0, 0, 0, 0))
    x = 0
    positions = {}
    for ch, gid, w, glyph_img in cells:
        positions[ch] = x
        if glyph_img is not None:
            atlas.paste(glyph_img, (x, 0))
        x += w

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas_path = OUT_DIR / f"{context_name}.png"
    atlas.save(atlas_path)

    fnt_lines = [
        f'info face="{context_name}" size={height} bold=0 italic=0 charset="" '
        f'unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
        f"common lineHeight={height} base={height - 2} scaleW={max(total_w, 1)} "
        f"scaleH={height} pages=1 packed=0",
        f'page id=0 file="{context_name}.png"',
        f"chars count={len(cells)}",
    ]
    for ch, gid, w, _glyph_img in cells:
        cid = ord(ch)
        if w == 0:
            fnt_lines.append(
                f"char id={cid} x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 "
                f"xadvance=3 page=0 chnl=15"
            )
        else:
            fnt_lines.append(
                f"char id={cid} x={positions[ch]} y=0 width={w} height={height} "
                f"xoffset=0 yoffset=0 xadvance={w} page=0 chnl=15"
            )

    (OUT_DIR / f"{context_name}.fnt").write_text("\n".join(fnt_lines) + "\n")
    print(f"{context_name}: {len(cells)} glyphs, atlas {atlas.size}")


def main() -> None:
    for context_name in COLOR_CONTEXTS:
        build_context(context_name)


if __name__ == "__main__":
    main()
