# Font system recon — `pokeemerald-expansion`

**Status:** Research complete. **Report only — nothing implemented, ported, or extracted.**
**Date:** 2026-07-26
**Reference tree:** `/home/rob/GodotAsImagined/reference/pokeemerald_expansion`
**Pinned at:** HEAD `74e40e033966421de974398a6777b87945e46c62` (`74e40e0339`, 2026-06-27)

> The reference clone is a **snapshot, not a live-updated source of truth.** Every
> citation below is line-accurate against the commit above and should be
> re-verified if that checkout is ever updated.

## Why this document exists

M25h built a UI element's text with no real font or styling at all — discovered
only in a later recon pass, costing three sessions to reach one authentic-looking
element. This is the Step 0 pass that should have preceded it: scope the real
reference behavior **first**, so direction can be decided with the whole picture
in hand rather than assembled piecemeal.

Scope was deliberately limited to the canonical checkout. Findings are reportable,
not actionable — nothing here has been decided.

---

# 1. Font inventory

## 1.1 The font IDs

**14 IDs, 11 distinct typefaces.** An anonymous enum at **`include/text.h:17-35`**.
Note there is **no `include/constants/fonts.h`** — that path does not exist.

| Value | Constant | Notes |
|---|---|---|
| 0 | `FONT_SMALL` | |
| 1 | `FONT_NORMAL` | the universal default |
| 2 | `FONT_SHORT` | |
| 3 | `FONT_SHORT_COPY_1` | behaviourally identical to `FONT_SHORT` |
| 4 | `FONT_SHORT_COPY_2` | " |
| 5 | `FONT_SHORT_COPY_3` | " |
| 6 | `FONT_BRAILLE` | separate renderer, `src/braille.c` |
| 7 | `FONT_NARROW` | |
| 8 | `FONT_SMALL_NARROW` | |
| 9 | `FONT_BOLD` | **JP glyph set only**, `fontFunction` is NULL |
| 10 | `FONT_NARROWER` | |
| 11 | `FONT_SMALL_NARROWER` | |
| 12 | `FONT_SHORT_NARROW` | |
| 13 | `FONT_SHORT_NARROWER` | |

`FONT_SHORT_COPY_1/2/3` are byte-identical copies (`src/text.c:1062-1100`), sharing
`GetGlyphWidth_Short` (`src/text.c:79-82`) and falling through to
`DecompressGlyph_Short` (`src/text.c:1588-1593`). They exist only so the engine can
hold four separate "current font" identities.

Two aliases at `include/text.h:34-35`: **`FONT_MALE`** and **`FONT_FEMALE`** both
`#define` to `FONT_NORMAL` — vestigial FRLG gendered fonts, collapsed. Only 2 uses
in the whole tree.

## 1.2 Metrics — `sFontInfos`

**`src/text.c:116-272`**. Struct at `include/text.h:141-157`. Fields: `fontFunction`,
`maxLetterWidth`, `maxLetterHeight`, `letterSpacing`, `lineSpacing`, and a
`union TextColor color`.

All fonts have `letterSpacing = 0` and `lineSpacing = 0` **except Braille**
(`lineSpacing = 8`). Default colour indices are uniform — fg 2 / bg 1 / accent 1 /
shadow 3 — **except `FONT_BOLD`**, which inverts to fg 1 / bg 2 / accent 2 / shadow 15.

| Font | maxLetterWidth | maxLetterHeight | **actual rendered height** | src/text.c |
|---|---|---|---|---|
| FONT_SMALL | 5 | 12 | **13** | 2237 |
| FONT_NORMAL | 6 | 16 | **15** | 2407 |
| FONT_SHORT | 6 | 14 | 14 | 2365 |
| FONT_NARROW | 5 | 16 | **15** | 2279 |
| FONT_SMALL_NARROW | 5 | 8 | **12** | 2321 |
| FONT_NARROWER | 5 | 16 | **15** | 2460 |
| FONT_SMALL_NARROWER | 5 | 8 | **15** | 2502 |
| FONT_SHORT_NARROW | 5 | 14 | 14 | 2546 |
| FONT_SHORT_NARROWER | 5 | 14 | 14 | 2590 |
| FONT_BOLD | 8 | 8 | **12** (w=8 hardcoded) | 2426-2427 |

> ⚠️ **`maxLetterHeight` does not match what the renderer emits.** The authoritative
> height is set per-glyph in the `DecompressGlyph_*` functions. `FONT_SMALL_NARROWER`
> is the worst case: declared 8, renders 15. A port that trusts `sFontInfos` for line
> height inherits the wrong number. Whether this causes visible clipping in-game
> **needs the ROM run — not determinable from source.**

Separate menu-cursor sizing table at `src/text.c:274-290` (all `{8, N}`;
`FONT_NORMAL/NARROW/NARROWER = {8,15}`, `FONT_BOLD = {}`).

## 1.3 Proportional vs fixed-width

**All 9 Latin fonts are fully proportional.** Every one has a real **512-entry**
per-glyph width table in `src/fonts.c`. **There is no fixed-width Latin font.**

| Table | Font | src/fonts.c | min–max width |
|---|---|---|---|
| `gFontSmallNarrowLatinGlyphWidths` | FONT_SMALL_NARROW | 4 | 0–8 |
| `gFontSmallLatinGlyphWidths` | FONT_SMALL | 40 | 1–9 |
| `gFontNarrowLatinGlyphWidths` | FONT_NARROW | 76 | 1–10 |
| `gFontShortLatinGlyphWidths` | FONT_SHORT (+COPY_1/2/3) | 112 | 1–12 |
| `gFontNormalLatinGlyphWidths` | FONT_NORMAL | 148 | 1–10 |
| `gFontNarrowerLatinGlyphWidths` | FONT_NARROWER | 184 | 0–10 |
| `gFontSmallNarrowerLatinGlyphWidths` | FONT_SMALL_NARROWER | 220 | 0–8 |
| `gFontShortNarrowLatinGlyphWidths` | FONT_SHORT_NARROW | 256 | 0–12 |
| `gFontShortNarrowerLatinGlyphWidths` | FONT_SHORT_NARROWER | 292 | 0–10 |

**Fixed-width cases** are all non-Latin or special: `FONT_BRAILLE` (constant from
`src/braille.c`), `FONT_BOLD` (hardcoded `width = 8`, `src/text.c:2426`), and the
Japanese halfwidth path (hardcoded 8). The one proportional JP case is the fullwidth
SHORT family (`gFontShortJapaneseGlyphWidths`).

## 1.4 Font graphics

**`graphics/fonts/` — 23 PNGs.** All nine Latin fonts are **256×512 = 16 cols × 32
rows of 16×16 glyphs, 2bpp**.

| File | Symbol | src/fonts.c | FONT_* |
|---|---|---|---|
| `latin_small.png` | `gFontSmallLatinGlyphs` | 39 | FONT_SMALL |
| `latin_normal.png` | `gFontNormalLatinGlyphs` | 147 | FONT_NORMAL |
| `latin_short.png` | `gFontShortLatinGlyphs` | 111 | FONT_SHORT + COPY_1/2/3 |
| `latin_narrow.png` | `gFontNarrowLatinGlyphs` | 75 | FONT_NARROW |
| `latin_narrower.png` | `gFontNarrowerLatinGlyphs` | 183 | FONT_NARROWER |
| `latin_small_narrow.png` | `gFontSmallNarrowLatinGlyphs` | 3 | FONT_SMALL_NARROW |
| `latin_small_narrower.png` | `gFontSmallNarrowerLatinGlyphs` | 219 | FONT_SMALL_NARROWER |
| `latin_short_narrow.png` | `gFontShortNarrowLatinGlyphs` | 255 | FONT_SHORT_NARROW |
| `latin_short_narrower.png` | `gFontShortNarrowerLatinGlyphs` | 291 | FONT_SHORT_NARROWER |

**A pixel scan of all nine confirmed only palette indices 0–3 are ever used**, even
where the PLTE is padded to 16 entries. Index semantics are fixed by
`GenerateFontHalfRowLookupTable` (`src/text.c` ~1935):

> **0 = background · 1 = foreground · 2 = shadow · 3 = accent**

That is the entire recolour model — a 4-index bitmap remapped at print time.

**There are no `.pal` files in `graphics/fonts/`.** Each PNG carries an embedded
PLTE, but those are **build-time preview colours only** — real on-screen colour comes
from the window/sprite palette at the indices above.

Japanese sets are separate files: `japanese_small.png`, `japanese_normal.png`
(both 128×512 halfwidth), `japanese_short.png` (256×512 fullwidth),
`japanese_bold.png` (128×256, declared at `src/text.c:317`, not `fonts.c`),
`braille.png` (256×64).

**Dead data:** `japanese_frlg_male.png` / `japanese_frlg_female.png` and their width
tables (`src/fonts.c:330, 331, 366, 367`) are **completely unreferenced** — the
definition line is the only occurrence of each symbol in the entire tree.

Non-font assets in the same directory: `down_arrow*.png` (4 variants),
`keypad_icons.png`, `unused_frlg_down_arrow.png`, `unused_frlg_blanked_down_arrow.png`.

---

# 2. Usage map — grouped by font

## 2.1 FONT_NORMAL — the universal default

**There is no "default font" parameter anywhere in `src/menu.c`.** It is hardcoded at
every generic helper, making `FONT_NORMAL` the de facto fallback:

| Helper | Line |
|---|---|
| `AddTextPrinterForMessage` | `menu.c:196` |
| `AddTextPrinterWithCustomSpeedForMessage` | `menu.c:202` |
| `DisplayItemMessageOnField` | `menu.c:379` |
| `AddTextPrinterWithCallbackForMessage` | `menu.c:453` |
| `InitMenuInUpperLeftCorner` | `menu.c:1325` |
| `PrintMenuTable` | `menu.c:1350` |
| **`CreateYesNoMenu`** (all confirmation dialogs) | `menu.c:1393-1401` |
| `PrintMenuGridTable` | `menu.c:1416` |
| `InitMenuActionGrid` | `menu.c:1462` |
| `PrintPlayerNameOnWindow` | `menu.c:1770` |

The only non-NORMAL in `menu.c` is the Hall-of-Fame PC top bar (`FONT_SMALL`,
`menu.c:580-618`). Note `InitMenu`/`InitMenuNormal`/`PrintMenuActionTexts` take
`fontId` as an explicit parameter with no default.

**Battle** — from `sTextOnWindowsInfo_Normal` (`src/battle_message.c:1560-1831`):
`B_WIN_MSG` (`:1564`), `B_WIN_ACTION_PROMPT` (`:1575`), `B_WIN_ACTION_MENU` (`:1586`),
`B_WIN_DUMMY` (`:1652`), `B_WIN_PP_REMAINING` — the "nn/nn" numerals (`:1663`),
`B_WIN_YESNO` (`:1696`), `B_WIN_LEVEL_UP_BOX` (`:1707`), `B_WIN_LEVEL_UP_BANNER`
(`:1718`, **overridden at runtime — see 2.3**), all `B_WIN_VS_*` (`:1727-1811`).
Arena table adds all `ARENA_WIN_*` (`:2276-2362`); Kanto-tutorial adds
`B_WIN_OAK_OLD_MAN` (`:2106`).

Battle message **auto-line-breaking is computed against FONT_NORMAL**:
`u8 fontId = FONT_NORMAL` (`battle_message.c:3051`) feeding
`BreakStringAutomatic(dst, BATTLE_MSG_MAX_WIDTH=208, BATTLE_MSG_MAX_LINES=2, fontId,
SHOW_SCROLL_PROMPT)` (`battle_message.c:3650`); constants at
`include/battle_message.h:14-15`.

**Overworld** — all NPC dialogue, signs, and script `msgbox` route through
`AddTextPrinterForMessage` → `AddTextPrinterParameterized2(0, FONT_NORMAL,
gStringVar4, GetPlayerTextSpeedDelay(), NULL, TEXT_COLOR_DARK_GRAY,
TEXT_COLOR_WHITE, TEXT_COLOR_LIGHT_GRAY)` (`src/menu.c:193-197`). Printer set at
x=0, y=1, letterSpacing=0, lineSpacing=0 (`menu.c:178-183`).

Also: script `messageinstant` (`src/scrcmd.c:1744`), field item messages
(`menu.c:379`), whiteout text (`src/field_screen_effect.c:1388`), Match Call
(`src/match_call.c:1444`), map preview (`src/map_preview_screen.c:445`), and the
**map name popup in its default Gen-3 style** (`src/map_name_popup.c:633-635`, with
a unique `letterSpacing = -1`; `OW_POPUP_GENERATION` defaults to `GEN_3` at
`include/config/overworld.h:118`).

**Screens that are FONT_NORMAL end to end** (no other base font in the file):
Trainer card (`src/trainer_card.c`, all printers) · Start menu (`src/start_menu.c`) ·
Options menu (`src/option_menu.c`) · Region map (`src/region_map.c`) · Main menu and
save-slot readout (`src/main_menu.c`) · Save-failure screen
(`src/save_failed_screen.c:155`) · Money box (`src/money.c:158-159`).

**FONT_NORMAL within mixed screens:** Bag pocket header (`item_menu.c:2546-2551`),
description box (`:1040`), quantity-entry window (`:1245`), TM/HM info panel
(`:2686-2722`) · Party "Choose a POKéMON." header (`party_menu.c:2830`), submenu
(`:2903`), per-slot description text (`:2769`), level-up stats (`:8486`) · Pokédex
entry/info body (`pokedex.c:3219`), cry/size labels (`:4709`), search menu (`:5062`),
area screen (`pokedex_area_screen.c:700`) · **the entire Summary screen**
(`pokemon_summary_screen.c:3179`) · Shop message text (`shop.c:780, 785`) · Naming
screen keyboard (`naming_screen.c:2020`) · PC box names, main-menu descriptions,
message box, nickname (`pokemon_storage_system.c:1321, 1521-1606, 4021, 4334`).

## 2.2 FONT_NARROW — list rows and the battle move grid

**Battle** (all from the table): `B_WIN_MOVE_NAME_1..4` (`:1597-1630`), `B_WIN_PP` —
the literal "PP " label (`:1641`), `B_WIN_MOVE_TYPE` — the "TYPE/" label (`:1674`),
`B_WIN_SWITCH_PROMPT` (`:1685`), `B_WIN_MOVE_DESCRIPTION` (`:1820`, the only entry
that explicitly sets spacing).

> **Move names are re-fitted at runtime** —
> `GetFontIdToFit(text, FONT_NARROW, letterSpacing, 8*TILE_WIDTH)`
> (`battle_message.c:3837-3846`; `16*TILE_WIDTH` when viewing Z-move details). A long
> move name can render as **FONT_NARROWER**. This is the only place in battle where a
> table font is silently swapped.

**Menus:**
- **Bag item list rows** — `sItemListMenu.fontId = FONT_NARROW`, **`item_menu.c:287`**
  (template at `:269`, copied into `gMultiuseListMenuTemplate` at `:927`).
  `.textNarrowWidth` is **not** set, so rows do not auto-shrink at print time —
  instead names are **pre-shrunk at build time** via `PrependFontIdToFit`: TM/HM
  60–65px (`:940`), Berries 61px (`:957`), everything else 88px (`:962`).
- **Bag quantity "x 12"** — `item_menu.c:1013-1014`, right-aligned x=119
- **Bag context menu** (USE/GIVE/TOSS/CANCEL) — `item_menu.c:1749, 1755`
- **Shop list rows** — `sShopBuyMenuListTemplate`, `shop.c:222`; unlike the bag these
  **do** auto-shrink (`.textNarrowWidth = 84` at `:224` + `list_menu.c:600-602`)
- **Shop prices / "SOLD OUT"** — `shop.c:664-665`, right-aligned 120
- **Pokédex list rows** — dex number `pokedex.c:2447`, species name `:2467`
- Same pattern: PC item storage (`player_pc.c:291, 1043`), Decoration menu
  (`decoration.c:317`), Pokéblock case (`pokeblock.c:733`), PokéNav list
  (`pokenav_list.c:745, 765`), **PokéNav region map** (`pokenav_region_map.c:568-687`),
  Move Relearner (`menu_specialized.c:809, 841`), starter-choose label
  (`starter_choose.c:588-589`), Frontier Pass landmarks (`frontier_pass.c:1719-1748`)

> ⚠️ `src/region_map.c` is FONT_NORMAL-only, but the **PokéNav** region map is a
> different file and uses FONT_NARROW.

## 2.3 FONT_SMALL — the battle HUD and small prompts

**All battle health-box text**, printed to **sprites, not windows**
(`AddSpriteTextPrinterParameterized6`), `src/battle_interface.c`:
- Level — width measured `:884`, printed `:889` (player, x = 32−width) / `:894`
  (opponent, x = 24−width)
- HP numbers — `#define HP_FONT FONT_SMALL` at `:898`, used `:925, 927, 929`.
  Width measured with **letterSpacing = −1** (`:925`) but printer passed 0.
- Nickname + gender — `GetFontIdToFit(gDisplayedStringBattle, FONT_SMALL, 0, 55)`
  (`:1728`), printed `:1733/:1738`. Degrades to **FONT_SMALL_NARROW** then
  **FONT_SMALL_NARROWER** for long names.
- Safari "BALLS" label and count — `:1941, 1964`
- **Ability popup** — `GetFontIdToFit(str, FONT_SMALL, 0, ABILITY_POP_UP_STR_WIDTH)`
  (`:2462`), printed `:2463`, width re-check `:2509`

> ⚠️ **The gender symbol is not a separate printer.** It is appended into the nickname
> buffer (`:1708-1719`) as `{COLOR DYNAMIC_COLOR2}♂` / `{COLOR DYNAMIC_COLOR1}♀`
> (`src/strings.c:716-718`) — same font, colour control code only.

> ⚠️ **The level-up banner overrides the table.** `DrawLevelUpBannerText` builds its
> own `TextPrinterTemplate` with `fontId = FONT_SMALL`
> (`src/battle_script_commands.c:6410`), bypassing `BattlePutTextOnWindow` entirely.
> **The table entry at `battle_message.c:1718` is dead code for that path.**

**Menus:**
- **Every party-slot bar field** — both printers hardcode it
  (`party_menu.c:2584` `DisplayPartyPokemonBarDetail`, `:2589` `...ToFit`): nickname
  (`:2601`, auto-fit to 50px), level (`:2625`), gender (`:2651, 2656`), current HP
  (`:2692`, or `:2678` when maxHP ≥ 1000), max HP (`:2717`), multi-battle partner
  slots (`:1227-1232`)
- **Party CONFIRM / CANCEL** — `party_menu.c:2415, 2432, 2437`
- **Summary "RELEARN" prompt** — `pokemon_summary_screen.c:4873-4874` — the **only**
  non-NORMAL base in that entire file
- **Naming screen bottom banner** (MOVE/OK/BACK) — `naming_screen.c:2066`
- PC held-item name (`pokemon_storage_system.c:4024, 4028`), Hall-of-Fame PC top bar
  (`menu.c:580-618`), DexNav throughout (`dexnav.c:460-507, 2089-2140, 2616-2620`)

**Overworld:** the **speaker name box** — `src/field_name_box.c:46`, printed `:87`,
width measured with letterSpacing **−1** (`:51`), centred `:79`.

## 2.4 FONT_SHORT

- **PC storage info panel** — species name `pokemon_storage_system.c:4022`
  (and `:4030` in Move-Items mode), gender+level line `:4023` (`:4031`)
- **Map name popup, Gen-5 (B/W) style only** — `map_name_popup.c:627`. **Not active
  by default** (`OW_POPUP_GENERATION == GEN_3`)
- Outside this doc's focus: union-room chat (`union_room_chat.c:2885-3014`),
  berry crush

## 2.5 FONT_BRAILLE

Script command `braillemessage` — `src/scrcmd.c:2091` (sizing `:2056`, width special
`:3422`). **The only field text surface using a font other than NORMAL/SMALL/SHORT.**
Also a table entry at `src/string_util.c:414`.

## 2.6 FONT_BOLD

JP-glyph-only, NULL `fontFunction`, no narrower variant (`src/text.c:2613`). Only
reachable via `RenderTextHandleBold()` (`src/text.c:2010`), called exclusively from
`src/battle_interface.c:953, 997` (`UpdateOpponentHpText*` — source comments at
`:935`/`:981` say **debug-only**, "an unused GF function") and `:1072, 1105`
(`PrintSafariMonInfo`, commented `:1059` as a leftover test feature).
**Not reachable in normal English gameplay.**

## 2.7 The four narrow variants — never chosen directly

**No screen ever selects `FONT_NARROWER`, `FONT_SMALL_NARROW`,
`FONT_SMALL_NARROWER`, `FONT_SHORT_NARROW` or `FONT_SHORT_NARROWER` directly.** They
are reached **exclusively** through the auto-fit chain from a wider base. Sole
exceptions: Frontier Pass Battle-Points readout (`frontier_pass.c:1160-1163`) and the
optional HGSS Pokédex (`pokedex_plus_hgss.c:4296, 6804`).

Fields that can silently drop into a narrow variant:

| Field | Base | Site |
|---|---|---|
| Bag item name | NARROW | `item_menu.c:940, 957, 962` |
| Shop list row | NARROW | `shop.c:224` + `list_menu.c:600-602` |
| Battle move name | NARROW | `battle_message.c:3837-3846` |
| Battle nickname / ability popup | SMALL | `battle_interface.c:1728, 2462` |
| Party slot nickname | SMALL | `party_menu.c:2601` |
| Party move-select move names | NORMAL | `party_menu.c:5392` (72px) |
| Summary nickname / species | NORMAL | `pokemon_summary_screen.c:3242, 3244` |
| Summary held item | NORMAL | `pokemon_summary_screen.c:3823-3825` |
| Summary move names / new move | NORMAL | `pokemon_summary_screen.c:4072, 4236, 4238` |
| PC nickname / species / item | NORMAL / SHORT / SMALL | `pokemon_storage_system.c:4021-4031` |
| Pokédex search labels | NORMAL | `pokedex.c:5062` |
| Pokédex cry-screen species | NORMAL | `pokedex.c:4736` (60px) |
| Money amount | NORMAL | `money.c:158` (54px) |
| Map name popup | NORMAL | `map_name_popup.c:633` (80px) |

## 2.8 Per-screen quick reference

| Screen | Fonts |
|---|---|
| Battle message box | FONT_NORMAL (`battle_message.c:1564`) |
| Battle action menu | FONT_NORMAL (`:1586`) |
| Battle move grid / PP / type / description | FONT_NARROW (`:1597-1820`) |
| Battle PP numerals | FONT_NORMAL (`:1663`) |
| Battle healthbox (name/level/HP) | FONT_SMALL, **sprite-printed** (`battle_interface.c`) |
| Battle ability popup | FONT_SMALL (`battle_interface.c:2462`) |
| Battle level-up banner | FONT_SMALL, **bypasses table** (`battle_script_commands.c:6410`) |
| Field dialogue / signs / msgbox | FONT_NORMAL (`menu.c:196`) |
| Field speaker name box | FONT_SMALL (`field_name_box.c:46`) |
| Map name popup | FONT_NORMAL (Gen-3 default) / FONT_SHORT (Gen-5, off) |
| Braille walls | FONT_BRAILLE (`scrcmd.c:2091`) |
| Bag — pocket header | FONT_NORMAL (`item_menu.c:2547`) |
| Bag — item rows / quantity / context menu | FONT_NARROW (`:287, 1014, 1749`) |
| Bag — description box | FONT_NORMAL (`:1040`) |
| Party — header / submenu | FONT_NORMAL (`party_menu.c:2830, 2903`) |
| Party — nickname / level / HP | FONT_SMALL (`:2584/2589`) |
| Pokédex — list rows | FONT_NARROW (`pokedex.c:2447, 2467`) |
| Pokédex — entry / info / area | FONT_NORMAL (`:3219, 4709`) |
| Summary — all pages | FONT_NORMAL (`:3179`); RELEARN prompt FONT_SMALL (`:4874`) |
| Trainer card / Start / Options / Region map | FONT_NORMAL only |
| Shop | rows+prices FONT_NARROW; text FONT_NORMAL |
| Naming screen | FONT_NORMAL; banner FONT_SMALL |
| PC / storage | FONT_NORMAL + FONT_SHORT + FONT_SMALL (`:4021-4031`) |
| Yes/No confirms, save/load | FONT_NORMAL (`menu.c:1393`) |

---

# 3. Palette pairings

## 3.1 Four colour channels, not three

The expansion extends the classic 3-colour model with an **`accent`** channel. Glyph
art is **2bpp** — four logical values mapping 1:1 onto
`background / foreground / shadow / accent`.

`union TextColor` — `include/text.h:73-80`:
```c
union TextColor {
    struct { u8 background; u8 foreground; u8 shadow; u8 accent; };
    u32 asU32;
};
```
Embedded in `struct TextPrinterTemplate` at `include/text.h:100-110`; the old flat
`bgColor`/`fgColor`/`shadowColor`/`accentColor` names remain but are marked
`DEPRECATED(...)`. `struct FontInfo` carries the same union (`include/text.h:145-157`).

**The packer:** `GenerateFontHalfRowLookupTable` (`src/text.c:645-683`) builds a
256-entry `sFontHalfRowLookupTable` (`src/text.c:61`); `DecompressGlyphTile`
(`src/text.c:695-724`) converts each 2bpp glyph row to 4bpp VRAM purely through it.
Save/restore helpers `SaveTextColors`/`RestoreTextColors` (`src/text.c:685-693`)
backed by a single global `sLastTextColor` (`:62`); early-returns if unchanged
(`:647-651`).

## 3.2 `TEXT_COLOR_*` are palette indices, not colours

**`include/constants/characters.h:240-255`.** 4-bit indices into the window's or
sprite's 16-colour GBA palette. Names are conventional only — actual RGB depends on
which palette is loaded. `charmap.txt:501-508` documents `0xA–0xF` as
"set to anything arbitrary at runtime".

| Constant | Value | | Constant | Value |
|---|---|---|---|---|
| `TEXT_COLOR_TRANSPARENT` | 0x0 | | `TEXT_COLOR_LIGHT_BLUE` | 0x9 |
| `TEXT_COLOR_WHITE` | 0x1 | | `TEXT_DYNAMIC_COLOR_1` | 0xA |
| `TEXT_COLOR_DARK_GRAY` | 0x2 | | `TEXT_DYNAMIC_COLOR_2` | 0xB |
| `TEXT_COLOR_LIGHT_GRAY` | 0x3 | | `TEXT_DYNAMIC_COLOR_3` | 0xC |
| `TEXT_COLOR_RED` | 0x4 | | `TEXT_DYNAMIC_COLOR_4` | 0xD |
| `TEXT_COLOR_LIGHT_RED` | 0x5 | | `TEXT_DYNAMIC_COLOR_5` | 0xE |
| `TEXT_COLOR_GREEN` | 0x6 | | `TEXT_DYNAMIC_COLOR_6` | 0xF |
| `TEXT_COLOR_LIGHT_GREEN` | 0x7 | | | |
| `TEXT_COLOR_BLUE` | 0x8 | | | |

> ⚠️ **Argument-order trap.** Every 3-element `const u8 color[3]` API is ordered
> **`{background, foreground, shadow}`** (`item_menu.c:416`, `data/party_menu.h:148`),
> and the 3-element helpers force `accent = color[0]` (`text.c:406-446`,
> `menu.c:1676, 1698`). But **`AddTextPrinterParameterized2` takes them in the
> opposite order `(fgColor, bgColor, shadowColor)`** (`menu.c:170-189`).

## 3.3 Resolved RGB — plain-text JASC-PAL

`graphics/text_window/text_pal1.pal` … `text_pal4.pal`. **Indices 0–9 are
byte-identical across all four:**

| Idx | Constant | RGB |
|---|---|---|
| 0 | TRANSPARENT | 115, 205, 164 *(hardware-transparent; placeholder)* |
| 1 | WHITE | **255, 255, 255** |
| 2 | DARK_GRAY | **98, 98, 98** |
| 3 | LIGHT_GRAY | **213, 213, 205** |
| 4 | RED | **230, 8, 8** |
| 5 | LIGHT_RED | **255, 189, 115** |
| 6 | GREEN | **32, 156, 8** |
| 7 | LIGHT_GREEN | **148, 246, 148** |
| 8 | BLUE | **49, 82, 205** |
| 9 | LIGHT_BLUE | **164, 197, 246** |

Indices 10–15 (`TEXT_DYNAMIC_COLOR_1..6`) differ per file — the frame-dependent slots:

| Idx | text_pal1 | text_pal2 | text_pal3 | text_pal4 |
|---|---|---|---|---|
| 10 | 255,255,255 | 255,255,255 | 255,0,255 | 57,98,115 |
| 11 | 205,205,222 | 74,205,238 | 205,213,213 | 131,131,131 |
| 12 | 205,205,222 | 49,164,238 | 156,205,222 | 164,164,164 |
| 13 | 230,246,255 | 0,90,131 | 98,115,123 | 197,197,205 |
| 14 | 205,205,222 | 24,98,197 | 65,172,230 | 230,230,238 |
| 15 | 106,115,123 | 16,115,230 | 131,164,180 | 65,90,106 |

Selected via `GetTextWindowPalette(id)` (`src/text_window.c:170-203`), backed by
`sTextWindowPalettes[][16]` (`:55-61`) — slot 0 is `message_box.png`, slots 1–4 are
`text_pal1..4.pal`. `LoadStdWindowGfx` uses palette 3 (`:107-111`); `LoadSignBoxGfx`
uses palette 1 (`:113-117`).

**Other readable palettes:**
- **`graphics/interface/std_menu.pal`** (`gStandardMenuPalette`, `menu.c:78`, loaded
  to palette 14 at `:355-357`): idx 0 = 255,255,255; **1–9 identical to the table
  above**; 10–15 = 0,0,0
- **`graphics/battle_interface/text.pal`** (`gBattleWindowTextPalette`,
  `graphics.c:1349`, → BG palette 5 at `battle_bg.c:966`):
  `0:(0,0,0) 1:(255,0,0) 2:(131,0,0) 3:(255,164,98) 4:(131,82,49) 5–10:(0,0,0)
  11:(131,131,131) 12:(74,74,74) 13:(74,74,74) 14:(255,255,255) 15:(213,213,205)`
- **`graphics/battle_interface/textbox_0.pal`** (battle message box, BG palette 0):
  `1:(255,255,255) 6:(106,90,115) 15:(106,164,164)` among others
- **`graphics/battle_interface/text_pp.pal`** (`gPPTextPalette`, `graphics.c:1350`)

## 3.4 Per-context pairings

Battle values from `struct BattleWindowText` (`battle_message.c:40-58`), copied into
the printer at `:3831`. Window palette numbers from `sStandardBattleWindowTemplates`
(`battle_bg.c:154-260`).

| Context | fg | bg | shadow | accent | fill | pal | Resolved RGB |
|---|---|---|---|---|---|---|---|
| `B_WIN_MSG` (`:1562`) | 1 | 15 | 6 | 15 | 0xF | 0 | fg **white**, bg **(106,164,164)**, shadow **(106,90,115)** |
| `B_WIN_ACTION_PROMPT` (`:1574`) | 1 | 15 | 6 | 15 | 0xF | 0 | as above |
| `B_WIN_ACTION_MENU` (`:1586`) | 13 | 14 | 15 | 14 | 0xE | 5 | fg **(74,74,74)**, bg **white**, shadow **(213,213,205)** |
| `B_WIN_MOVE_NAME_1..4` | 13 | 14 | 15 | 14 | 0xE | 5 | as above |
| `B_WIN_PP` (`:1641`) | 13 (12 if `B_SHOW_EFFECTIVENESS == NEVER`) | 14 | 15 (11 if NEVER) | 14 | 0xE | 5 | 11 = (131,131,131) |
| `B_WIN_PP_REMAINING` (`:1661`) | 12 | 14 | 11 | 14 | 0xE | 5 | |
| `B_WIN_MOVE_DESCRIPTION` (`:1757`) | DYN_4 (13) | DYN_5 (14) | DYN_6 (15) | DYN_5 | 0xE | 5 | |
| `B_WIN_LEVEL_UP_BANNER` (`:1704`) | 1 | 0 | 2 | 0 | 0 | — | |
| **Battle healthbox** (`battle_interface.c:569-575`) | 1 | 0 | 3 | **0** | — | OBJ | ⚠️ **not resolvable — see 3.5** |
| **Field message box** (`menu.c:196`) | 2 | 1 | 3 | 1 | — | 15 | fg **(98,98,98)**, bg **white**, shadow **(213,213,205)** |
| **Field name box** (`field_name_box.c:78`) | 1 | 0 | 2 | — | — | — | configured `config/name_box.h:14-15` |

Arena and Kanto-tutorial `B_WIN_MSG` use the **identical** set (`:1835-1845`,
`:2120-2130`).

Related: `#define HEALTHBOX_BG_INDEX 2` (`battle_interface.c:38`) is the fill index
used to clear the text region — **not** the same as the printer's `background = 0`.

## 3.5 Palettes requiring binary decoding — NOT decoded

- **`graphics/text_window/message_box.png`** → `gMessageBox_Pal` (`graphics.c:2066`)
  — **the overworld dialog box palette.** 56×16, 4-bit colormap PNG.
- **`graphics/battle_interface/ball_status_bar.png`** →
  `gBattleInterface_BallStatusBarPal` (`graphics.c:710`) — **the healthbox palette.**
  128×8, 4-bit colormap PNG.
- **`graphics/text_window/1.png` … `20.png`** → the 20 user-selectable window frame
  palettes (`text_window.c:33-52`, table `sWindowFrames[]` at `:64-85`).

## 3.6 Selected / disabled states

**No engine-level "selected" or "disabled" concept exists.** Each screen defines its
own table.

**Bag** (`item_menu.c:409-422`):
```
COLORID_NORMAL      {0, 1, 3}   TRANSPARENT / WHITE      / LIGHT_GRAY
COLORID_POCKET_NAME {0, 1, 4}   TRANSPARENT / WHITE      / RED
COLORID_GRAY_CURSOR {0, 3, 6}   TRANSPARENT / LIGHT_GRAY / GREEN
COLORID_UNUSED      {2, 1, 3}
COLORID_TMHM_INFO   {0, 14, 10} TRANSPARENT / DYN_5      / DYN_1
```

**Party** (`src/data/party_menu.h:149-158`, comments are the source's own):
```
{0, LIGHT_GRAY, DARK_GRAY}   Default        {0,3,2}
{0, WHITE,      GREEN}       Unused         {0,1,6}
{0, DYN_2,      DYN_3}       Gender symbol  {0,11,12}
{WHITE, DARK_GRAY, LIGHT_GRAY} Selection actions {1,2,3}
{WHITE, BLUE,      LIGHT_BLUE} Field moves       {1,8,9}
{0, WHITE,      DARK_GRAY}   Unused         {0,1,2}
{WHITE, RED,       LIGHT_RED} Move relearner    {1,4,5}
```

**List menus** carry colours in the template — `cursorPal:4`, `fillValue:4`,
`cursorShadowPal:4` (`include/list_menu.h:73-75`), assembled at
`list_menu.c:587-589` / `:603-605`. Runtime recolour via `ChangeListMenuPals()`
(`:480-487`) and `ListMenuOverrideSetColors()` (`include/list_menu.h:145`).

**Greyed-out** is per-screen, by swapping to a light-gray foreground — e.g. Contest
unusable move emits `{COLOR LIGHT_GRAY}{SHADOW DARK_GRAY}` inline
(`contest.c:1589`) vs `{COLOR BLUE}` usable (`:1596`). Battle Pyramid bag defines
`COLORID_DARK_GRAY {0,2,3}` / `COLORID_LIGHT_GRAY {0,3,1}`
(`battle_pyramid_bag.c:203-204`). Trainer card hides a colon with an all-transparent
triple (`trainer_card.c:286`).

**Other named tables:** `sTextColors` (Hall-of-Fame PC, `menu.c:106`), mail
(`mail.c:123`), frontier pass 3 sets incl. selected-vs-unselected
(`frontier_pass.c:332`), dexnav (`dexnav.c:228-229`), trainer card
(`trainer_card.c:284-286`), naming screen per-page (`naming_screen.c:1992-2010`),
oak speech (`oak_speech.c:336-337`), hall of fame (`hall_of_fame.c:134-135`),
mystery gift (`mystery_gift_menu.c:365-366`), berry tag
(`berry_tag_screen.c:98`), credits (`credits_frlg.c:562-564`).

---

# 4. Control codes / dynamic colouring

## 4.1 The code set

**28 operation codes** (`0x01–0x1C`) plus prefix `EXT_CTRL_CODE_BEGIN = 0xFC`
(`include/constants/characters.h:179, 211-238`).

Full list: `COLOR, HIGHLIGHT, SHADOW, COLOR_HIGHLIGHT_SHADOW, PALETTE, FONT,
RESET_FONT, PAUSE, PAUSE_UNTIL_PRESS, WAIT_SE, PLAY_BGM, ESCAPE, SHIFT_RIGHT,
SHIFT_DOWN, FILL_WINDOW, PLAY_SE, CLEAR, SKIP, CLEAR_TO, MIN_LETTER_SPACING, JPN,
ENG, PAUSE_MUSIC, RESUME_MUSIC, SPEAKER, ACCENT, BACKGROUND, TEXT_COLORS`.

## 4.2 The nine that affect colour or font

Arity from `GetExtCtrlCodeLength()` (`src/string_util.c:703-742`; table values
**include the code byte**, so operands = length − 1).

| Constant | Val | Operands | Effect | charmap |
|---|---|---|---|---|
| `EXT_CTRL_CODE_COLOR` | 0x01 | 1 | foreground only | `{COLOR x}` `:439` |
| `EXT_CTRL_CODE_HIGHLIGHT` | 0x02 | 1 | **background AND accent** | `{HIGHLIGHT x}` `:440` |
| `EXT_CTRL_CODE_SHADOW` | 0x03 | 1 | shadow only | `{SHADOW x}` `:441` |
| `EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW` | 0x04 | **3** | fg, bg+accent, shadow | `:442` |
| `EXT_CTRL_CODE_PALETTE` | 0x05 | 1 | ⚠️ **no-op in all interpreters** | `{PALETTE n}` `:443` |
| `EXT_CTRL_CODE_FONT` | 0x06 | 1 | sets `fontId` | `{FONT n}` `:444` |
| `EXT_CTRL_CODE_RESET_FONT` | 0x07 | 0 | ⚠️ **empty case — does nothing** | `{RESET_FONT}` `:445` |
| `EXT_CTRL_CODE_ACCENT` | 0x1A | 1 | accent only | `{ACCENT x}` `:464` |
| `EXT_CTRL_CODE_BACKGROUND` | 0x1B | 1 | background only | `{BACKGROUND x}` `:465` |
| `EXT_CTRL_CODE_TEXT_COLORS` | 0x1C | **3** | fg, shadow, accent — **not background** | `:466` |

`ACCENT` / `BACKGROUND` / `TEXT_COLORS` (0x1A–0x1C) are **expansion additions** tied
to the 4th channel; vanilla has only 0x01–0x04.

**Font shorthands** — `charmap.txt:476-487`, all `FC 06 <id>`:
```
FONT_SMALL = FC 06 00      FONT_NARROW          = FC 06 07
FONT_NORMAL = FC 06 01     FONT_SMALL_NARROW    = FC 06 08
FONT_SHORT = FC 06 02      FONT_NARROWER        = FC 06 0A
                           FONT_SMALL_NARROWER  = FC 06 0B
                           FONT_SHORT_NARROW    = FC 06 0C
                           FONT_SHORT_NARROWER  = FC 06 0D
```
Plus `FONT = FC 06 <id>` and `RESET_FONT = FC 07` (`charmap.txt:444-445`).
`FONT_MALE`/`FONT_FEMALE` both emit `01`.

## 4.3 Where they are interpreted — four independent copies

**All must stay in sync:**
1. **`RenderText()`** — `src/text.c:1379-1440` (the real renderer). `BACKGROUND` `:1384`,
   `COLOR` `:1389`, `SHADOW` `:1394`, `ACCENT` `:1399`, `HIGHLIGHT` `:1404`,
   `COLOR_HIGHLIGHT_SHADOW` `:1410`, `TEXT_COLORS` `:1420`, `PALETTE` `:1429`,
   `FONT` `:1432`, `RESET_FONT` `:1436`
2. **`FontFunc_Braille()`** — `src/braille.c:~80-120`, near-verbatim duplicate
3. **`GetStringWidth()`** — `src/text.c:1726-1762`, skip-only
4. **`RenderTextHandleBold()`** — `src/text.c:2010-2131`, keeps a local `union TextColor`

## 4.4 Interaction with base colours

- **Overrides are permanent for the rest of the string.** The code writes directly
  into the printer's live `printerTemplate.color`, then calls
  `GenerateFontHalfRowLookupTable` and returns `RENDER_REPEAT`. **No stack, no
  save/restore, no revert at line breaks or `{CLEAR}`/scroll.** To restore you must
  emit another code — which the game does explicitly, e.g.
  `pokenav_ribbons_list.c:123`:
  `{TEXT_COLORS LIGHT_RED GREEN WHITE}{BACKGROUND WHITE}♂{TEXT_COLORS DARK_GRAY LIGHT_GRAY WHITE}{BACKGROUND WHITE}`
- **They do not affect the caller.** `AddTextPrinter` copies the template by value
  (`src/text.c:470`), so the caller's const colour table is untouched.
- **Each `AddTextPrinter` re-establishes the lookup table** (`src/text.c:489`),
  early-outing if identical to `sLastTextColor`.
- ⚠️ **The colour lookup table is a single global shared across concurrent printers**
  (`sFontHalfRowLookupTable`/`sLastTextColor`, `src/text.c:61-62`). `RenderText()`
  does not regenerate on entry (`:1327-1345`), and `RunTextPrinters()` (`:532+`)
  iterates all active printers each frame. **Two simultaneously-animating printers
  with different colour sets bleed into each other — last write wins.** Inherited
  behaviour, not new to the expansion. `RenderTextHandleBold` is the only path that
  brackets its work with `SaveTextColors`/`RestoreTextColors` (`:2017`, `:2129`).

## 4.5 `StringExpandPlaceholders` recursion

`src/string_util.c:358-407`.
- **It recurses** — `case PLACEHOLDER_BEGIN: ... dest = StringExpandPlaceholders(dest, expandedString);` (`:368-372`). Control codes inside a substituted `gStringVar` copy through correctly; nested placeholders expand.
- **Control codes are copied verbatim, never interpreted** (`:373-396`) — colour is
  resolved later, at render time.
- Its operand-copy switch (`:378-395`) uses deliberate fall-through:
  `COLOR_HIGHLIGHT_SHADOW`/`TEXT_COLORS` copy 3; `PLAY_BGM` copies 2; `default`
  copies 1; the zero-operand set copies 0.

## 4.6 Two upstream discrepancies — observations, not verified bugs

1. **`EXT_CTRL_CODE_PLAY_SE` (0x10) arity mismatch.** Absent from the 2-operand group
   in `StringExpandPlaceholders` (`string_util.c:391-394`), so it falls to `default`
   and copies **1** operand byte — while `GetExtCtrlCodeLength` (`:722`),
   `GetStringWidth` (`text.c:1733-1734`) and `RenderText` (`text.c:1461-1467`) all
   use 2. A `{PLAY_SE ...}` passed through `StringExpandPlaceholders` would desync the
   byte stream by one, causing the next byte to be misread as a control code. Live
   strings do use it, e.g. `sText_GotAwaySafely` (`battle_message.c:79`).
2. **`EXT_CTRL_CODE_SPEAKER` (0x19) arity mismatch.** Listed as length 1 (0 operands)
   in `GetExtCtrlCodeLength` (`string_util.c:733`) but grouped with 1-operand codes in
   `GetStringWidth` (`text.c:1751`), `RenderText` (`:1528`) and
   `RenderTextHandleBold` (`:2086`).

---

# 5. Structural notes

## 5.1 Font selection is overwhelmingly hardcoded, not table-driven

**Decisive evidence: `struct WindowTemplate` has no font field at all**
(`include/window.h:27-36`) — only `bg, tilemapLeft, tilemapTop, width, height,
paletteNum, baseBlock`. **A window does not know what font prints into it. There is
no window→font map.**

Instead, ~1,300 hardcoded literals at individual call sites:

```
934  FONT_NORMAL       27  FONT_SHORT_COPY_1    9  FONT_BRAILLE
142  FONT_SMALL        15  FONT_SMALL_NARROW    8  FONT_BOLD
 91  FONT_NARROW       10  FONT_SHORT_NARROW    7  FONT_SHORT_NARROWER
 48  FONT_SHORT         9  FONT_SMALL_NARROWER  7  FONT_NARROWER
```

**The one genuine table is battle.** `struct BattleWindowText`
(`battle_message.c:41-59`) = `{fillValue, fontId, x, y, color, letterSpacing,
lineSpacing, speed}`. Three tables indexed by window ID —
`sTextOnWindowsInfo_Normal` (`:1560`, 25 entries), `_KantoTutorial` (`:1833`, 26),
`_Arena` (`:2118`, 24) — dispatched via `sBattleTextOnWindowsInfo[]` (`:2386-2391`)
on `gBattleScripting.windowsType` (`include/constants/battle.h:691-693`, set at
`battle_bg.c:934-947`). Consumed by `BattlePutTextOnWindow` (`:3807-3889`).

> **But even that table carries one font policy.** The fontIds are **identical across
> all three window types** — everything is `FONT_NORMAL` except seven cramped
> move-grid windows using `FONT_NARROW`. The tables differ in **colour, position and
> fill — not font.**

Two smaller structs carry a font as data: `ListMenuTemplate.fontId:5`
(`include/list_menu.h:79`) and `PokenavListTemplate.fontId` (`include/pokenav.h:45`).
Neither is a window→font map.

## 5.2 Mechanism 2 — the auto-narrowing chain

`GetFontIdToFit` (`src/text.c:2602-2633`), backed by static `sNarrowerFontIds[]`
(`:2602-2619`):
```
FONT_NORMAL → FONT_NARROW → FONT_NARROWER → (end)
FONT_SMALL  → FONT_SMALL_NARROW → FONT_SMALL_NARROWER → (end)
FONT_SHORT  → FONT_SHORT_NARROW → FONT_SHORT_NARROWER → (end)
FONT_SHORT_COPY_1/2/3 → FONT_SHORT_NARROW → ...
FONT_BRAILLE, FONT_BOLD → −1 (no narrower variant)
```
It measures the string and walks down until it fits a pixel width; the source comment
notes it returns the narrowest ID regardless, *"because clipping is better than
crashing."* Wrappers `PrependFontIdToFit` (`:2635`) and `WrapFontIdToFit` (`:2650`)
splice an inline font control code into the buffer (`:2643-2645, 2657-2662`).

## 5.3 Mechanism 3 — in-string font switching

`EXT_CTRL_CODE_FONT` (0x06). `TextPrinter.hasFontIdBeenSet`
(`include/text.h:121`) is the latch: each `FontFunc_*` applies its own default font
**only if** a control code hasn't already set one (e.g. `text.c:1062-1070`).

**There is no script command that sets a font** — `asm/macros/event.inc` has none.
Inline control code is the only script-level mechanism.

## 5.4 The printer API

All seven `AddTextPrinterParameterized*` variants take an **explicit `fontId`**.
None infers one.

| Function | Def | Position | Spacing | Colour source |
|---|---|---|---|---|
| `AddTextPrinterParameterized` | `text.c:370` | x, y args | derived from font attrs | derived |
| `AddTextPrinterParameterized2` | `menu.c:170` | **hardcoded x=0, y=1** | hardcoded 0/0 | explicit **(fg, bg, shadow)** — reversed order; `accent = bgColor` |
| `AddTextPrinterParameterized3` | `menu.c:1676` | left, top | derived | `color[3]` = {bg, fg, shadow}; `accent = color[0]` |
| `AddTextPrinterParameterized4` | `menu.c:1698` | left, top | explicit | `color[3]`; `accent = color[0]` |
| `AddTextPrinterParameterized5` | `menu.c:1720` | left, top | explicit | all four derived |
| `AddTextPrinterParameterized6` | `menu.c:1743` | left, top | explicit | **`union TextColor` by value** — the only one that can set `accent` independently. Expansion-added. |
| `AddTextPrinter` (base) | `text.c` | caller fills template | — | — |

Sprite parallels (expansion additions): `AddSpriteTextPrinterParameterized`,
`...3`, `...4`, `...6` (`include/text.h:189-192`). Note the numbering gaps — there is
no `...1`, and no sprite `...2` or `...5`.

`struct TextPrinterTemplate` (`include/text.h:83-111`): `currentChar`, `type`
(`WINDOW_TEXT_PRINTER` | `SPRITE_TEXT_PRINTER`), `windowId`|`spriteId` union,
`fontId`, `x`, `y`, `currentX`, `currentY`, `letterSpacing`, `lineSpacing`,
`firstSpriteInRow`, `firstSprite`, colour union. **`type`, the id union,
`firstSpriteInRow` and `firstSprite` are expansion additions** — vanilla's template
is window-only. The wrapping `struct TextPrinter` (`:113-139`) adds `fontId:4` as a
*separate runtime field*, plus `hasFontIdBeenSet:1`, `japanese:1`,
`minLetterSpacing`, `textSpeed`, and a `nextPrinter` linked-list pointer.

## 5.5 Do overworld and battle share fonts?

**Yes for dialogue, no for HUD.** Both main message boxes are `FONT_NORMAL` at
identical x=0, y=1, letterSpacing=0, lineSpacing=0.

| Parameter | Battle `B_WIN_MSG` | Field message box |
|---|---|---|
| Colours | fg 1, bg 15, accent 15, shadow 6 (`battle_message.c:1568-1571`) — **battle BG palette indices** | fg DARK_GRAY, bg WHITE, shadow LIGHT_GRAY (`menu.c:196`) |
| Line breaking | **Automatic** — 208px / 2 lines (`:3650`) | **None** — relies on authored `\n`/`\l`/`\p` |
| Down arrow | `useAlternateDownArrow = TRUE` (`:3858`) | `FALSE` (`menu.c:189`, reset `field_message_box.c:22`) |
| Speed | `GetPlayerTextSpeedDelay()`, forced to 1 for link, `sRecordedBattleTextSpeeds` for recorded (`:3865-3875`) | `GetPlayerTextSpeedDelay()` |
| Auto-scroll | Forced TRUE for link/recorded/test (`:3860-3863`) | Per-call (`ShowFieldAutoScrollMessage`) |

**Divergence is entirely in the HUD:** battle has FONT_NARROW (move grid) and
FONT_SMALL (health boxes, ability popup); the overworld has almost no HUD text —
only the speaker name box (FONT_SMALL), map name popup, and braille.

**Signs use the same font as NPC dialogue.** `gMsgIsSignPost` (`src/script.c:38`, set
`field_control_avatar.c:1328`) changes **only the window frame graphics and draw
function** (`field_message_box.c:36-39`, `menu.c:243`). The printer path is identical
→ FONT_NORMAL.

## 5.6 FRLG / Kanto conditionals

**There are zero font-related FRLG conditionals in code.**

- `IS_FRLG` is defined at `include/constants/global.h:66-78`
- **No `FONT_*_FRLG` constants exist** — grep for `FONT_[A-Z_0-9]*FRLG`,
  `FRLG[A-Z_0-9]*FONT`, `Frlg.*Font`, `Font.*Frlg` across `src/` and `include/`
  returns **nothing**
- **No `#if IS_FRLG` / `if (IS_FRLG)` branch anywhere selects a font.** Every
  `IS_FRLG` occurrence was checked with ±3 lines of context and filtered for `FONT_`;
  the only hits are `src/script_menu.c:754/756`, which choose between two *strings*
  while passing the **same** `FONT_NORMAL` to both
- `FONT_MALE`/`FONT_FEMALE` are the vestige of FRLG's gendered fonts — both alias
  `FONT_NORMAL`
- The FRLG Japanese glyph sets are **dead data** (see 1.4)

**However — FRLG *text data* does carry inline font overrides that Hoenn text data
does not.** Exactly 5 map-script files in the whole tree contain `{FONT_NORMAL}`, and
**all 5 are FRLG-suffixed**:
```
data/maps/VermilionCity_Frlg/scripts.inc
data/maps/PalletTown_RivalsHouse_Frlg/scripts.inc
data/maps/CeladonCity_DepartmentStore_Roof_Frlg/scripts.inc
data/maps/CinnabarIsland_PokemonLab_ExperimentRoom_Frlg/scripts.inc
data/maps/PewterCity_Gym_Frlg/scripts.inc
```
Zero Hoenn map scripts do this. **Why those five specifically is not explained by
source — flagged as unresolved, not guessed at.** Two other data files use the code:
`data/text/pokedex_rating.inc:129` and `data/text/fame_checker_frlg.inc` (the latter
using `{FONT_MALE}`/`{FONT_FEMALE}`, cosmetic no-ops in an English build).

**The closest thing to "Kanto presentation" is `B_WIN_TYPE_KANTO_TUTORIAL`**
(`include/constants/battle.h:693`, selected at `battle_bg.c:940`) — the
Oak/Pokédude tutorial window set. It adds `B_WIN_OAK_OLD_MAN` and has its own colour
and position table, **but its fontIds are identical to the Normal table.**

> ⚠️ **Net: there is no "Kanto font" to inherit.** Kanto-style presentation in this
> reference is a window-layout and palette difference, **not a typographic one.** If
> Kanto should look typographically distinct, that is an original design decision,
> not a port.

---

# 6. Not determinable from source alone

- **Actual RGB of two key palettes** — `message_box.png` (overworld dialog box) and
  `ball_status_bar.png` (battle healthbox). Both 4-bit-colormap PNGs extracted to
  `.gbapal` at build time. Would need binary decoding.
- **Actual glyph appearance.** Which glyph index maps to which character depends on
  the proprietary charmap (`charmap.txt`), not ASCII. Determining a specific glyph
  requires opening the PNG at cell `(index % 16, index / 16)`.
- **Which runtime font a given string resolves to.** `GetFontIdToFit` is
  data-dependent — healthbox nicknames, ability popups, move names and item names may
  render at base or one/two steps narrower.
- **Whether the `maxLetterHeight` discrepancies cause visible clipping** (1.2).
  Needs the ROM.
- **JP-only behaviour** — `FONT_BOLD` and the `isJapanese` branches can't be
  evaluated without the JP charmap/build config.
- **Config-gated call sites** — `OW_POPUP_GENERATION`, `OW_POPUP_BW_TIME_MODE`,
  `OW_NAME_BOX_*`, `B_SHOW_MOVE_DESCRIPTION`, `B_SHOW_EFFECTIVENESS` all gate which
  paths run. Shipped defaults are cited where known.
- **`src/pokedex_plus_hgss.c`** is an alternative HGSS-style Pokédex selected by build
  config; whether its font choices are live was not resolved.

---

# 7. Decisions this surfaces — for Rob, not resolved here

Ranked by cost of discovering late.

1. **The auto-narrowing chain is load-bearing and has no Godot analogue.**
   Nicknames, species names, move names, item names and money all pass through
   `GetFontIdToFit`. The narrow font variants exist **solely** to serve it — no screen
   selects them directly. Porting the narrow fonts without the chain, or the chain
   without them, gets half a system. Godot's `Label` autowrap/shrink is not equivalent.
2. **There is no "Kanto font."** See 5.6. If Kanto should read as typographically
   distinct, that is original design, not a port.
3. **Four colour channels, not three.** The current project pipeline bakes a
   drop-shadow into glyph bitmaps; the reference keeps fg/shadow/accent as **separate
   runtime-swappable indices**, which is what makes per-context recolouring and
   mid-string colour changes work at all.
4. **Two palettes need binary decoding** before the overworld dialog box and battle
   healthbox can be colour-matched exactly. Everything else resolved from plain-text
   `.pal`.
5. **`B_WIN_MOVE_INFO` does not exist.** M26C3's combined PP+Type panel consolidates
   four reference windows using two fonts (`B_WIN_PP` NARROW label + `B_WIN_PP_REMAINING`
   NORMAL numerals + `B_WIN_MOVE_TYPE` NARROW label with an inline switch to NORMAL for
   the type name + `B_WIN_MOVE_DESCRIPTION` NARROW). Reasonable consolidation — but
   style it as an original element, not a port.
6. **Health-box text is sprite-printed in the reference**, not window-printed. The
   project's `.tscn` `Label` approach is fine, but won't inherit the auto-narrowing
   that long nicknames rely on.
7. **Do not replicate three known upstream defects:** `{PALETTE n}` and
   `{RESET_FONT}` are inert despite appearing in live strings (4.2), and
   `pokemon_storage_system.c:4022` measures the wrong string when picking its font.

---

*Compiled 2026-07-26 from four parallel source investigations against the pinned
checkout above. No assets extracted, no code written, no files outside this document
modified.*
