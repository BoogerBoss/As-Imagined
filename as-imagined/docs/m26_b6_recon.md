# M26B6 — Ability activation popup: full recon and scope

**Status: SCOPED, nothing built.** Deep-dive verification pass, 2026-07-27.
All figures re-derived against current code and the canonical reference
checkout; nothing carried over from the roadmap's own summary.

---

## 0. Executive summary

- **The art is already in the tree** — `assets/sprites/battle_ui/interface/ability_pop_up.png`,
  128×32, **pixel-identical to the reference**. The roadmap does not say this.
  But it is **not usable as-is**: index 0 is untagged (§3).
- **The separate `.pal` is redundant** — byte-identical to the PNG's own
  embedded palette, so no second pull is needed (§3).
- **Source's popup shows TWO lines: the Pokémon's name with a possessive, then
  the ability name** (§2.4). It is not an ability-name-only banner, which is
  how the roadmap describes it.
- **The real scope risk is trigger volume, not visuals**: `ability_triggered`
  fires from **109 sites across 72 distinct effect keys**, and it is a
  per-EFFECT signal while the popup is a per-ACTIVATION visual. Source solves
  this with a one-popup-per-battler guard that this port must reproduce (§4).
- Plus **two residual signals inherited from D3-2's retirement** which the
  popup does NOT cover and which still want message-box text (§5).

---

## 1. What this item is

Source shows a sliding banner naming the Pokémon and its ability whenever an
ability activates. This project shows nothing in normal play — the readable
per-effect text exists but is tagged to the F3 debug panel, which is off by
default.

**M26D3-2 was retired into this item** (2026-07-27, Rob's call) after a Step 0
finding: `BattleScript_IntimidateActivates` is three lines —
`call BattleScript_AbilityPopUp` / `trystatchanges` / `destroyabilitypopup` —
i.e. **the popup carries the ability NAME and the message box carries only the
EFFECT**. Since this project already narrates effects (`stat_stage_changed`,
`secondary_applied` are log-wired), the popup is the *only* missing piece. See
`docs/m26_d3_recon.md`'s D3-2 section.

---

## 2. Source mechanics

### 2.1 Structure — it is TWO sprites, not one

`CreateAbilityPopUp` (`src/battle_interface.c:2573`) creates **two** sprites
side by side, `ABILITY_POP_UP_POS_X_DIFF` = **64** apart, each rendering half
of the 128×32 sheet (the second gets `oam.tileNum += 32`). A single 128-wide
node reproduces the same visual; the split is a GBA OAM size constraint, not a
design feature.

### 2.2 Position — per battler POSITION, and doubles differs

```
sAbilityPopUpCoordsSingles:  player { 24, 97}   opponent {178, 57}
sAbilityPopUpCoordsDoubles:  player L { 24, 80} opponent L {178, 19}
                             player R { 24, 97} opponent R {178, 36}
```

Player-side popups sit at the left edge, opponent-side at the right. Note
singles player and doubles player-RIGHT share (24, 97).

### 2.3 Timing and motion

| Phase | Value |
|---|---|
| Slide-in distance | `ABILITY_POP_UP_POS_X_SLIDE` = 128 px, from off-screen |
| Slide speed | `ABILITY_POP_UP_POS_X_SPEED` = 4 px/frame → **32 frames** |
| Idle hold | `ABILITY_POP_UP_WAIT_FRAMES` = **48 frames** |
| Slide out | same speed → **32 frames** |
| **Total** | **≈112 frames ≈ 1.87 s** |

Direction mirrors by side (`xSlide` is negative for the player). A sound plays
at slide-in frame 4 (`SE_BALL_TRAY_ENTER`) — **not portable, this project has
no audio at all.**

State machine: `SLIDE_IN → IDLE → SLIDE_OUT → END`. `IDLE` decrements its timer
unless `gBattleScripting.fixedPopup` is set, and `DestroyAbilityPopUp` sets an
`sAutoDestroy` flag that short-circuits `IDLE` — so a script can dismiss a
popup early, which is what `destroyabilitypopup` does (5 uses).

### 2.4 Text — TWO lines, and the first is possessive

`PrintBattlerOnAbilityPopUp` prints the Pokémon's **nickname plus a possessive
apostrophe**, appending `s` only when the name does not already end in s/S —
so "Pikachu's" but "Gyarados'". `PrintAbilityOnAbilityPopUp` then prints
`gAbilitiesInfo[ability].name` on the second line (offset by 8 tiles, i.e. one
8-px tile row down, at local y=4).

The ability line is **blanked first** (a 20-space string) before printing,
which is what makes `UpdateAbilityPopup` able to change the ability on an
*existing* popup rather than creating a second one.

Text colours are palette indices into the popup's own palette:

| Line | bg | fg | shadow |
|---|---|---|---|
| Battler name | 2 → `(103, 91, 111)` | 7 → `(249, 253, 255)` | 1 → `(143, 129, 149)` |
| Ability name | 7 → `(249, 253, 255)` | 9 → `(0, 0, 0)` | 1 → `(143, 129, 149)` |

### 2.5 Trigger surface in source

`BattleScript_AbilityPopUp` is called from **126 sites** across the battle
scripts. That is the scale of the equivalent surface — see §4 for how it maps
onto this project's signal.

---

## 3. Asset status — already pulled, ONE real gap

`assets/sprites/battle_ui/interface/ability_pop_up.png` already exists (from
M23.11 Phase 1's battle-HUD chrome pull) and is **pixel-identical to the
reference** — verified on decoded RGBA, not just dimensions. **The roadmap does
not record this**; it should be corrected, in the same way the M26E5 category
icons turned out to be already pulled.

**Two findings:**

1. **Index 0 is NOT tagged transparent** (`tRNS = None`), and it is the
   transparency key: it occupies all four corners and **1202 of 4096 pixels
   (29%)**, colour `(1, 177, 91)` — a green key. As-is the popup renders inside
   an opaque green box. This is exactly the defect `[M26B3-6a]` hit with the
   ball sheets, and the fix is the same `im.info["transparency"] = 0` re-save.
   **B6 therefore carries a small asset task after all**, contrary to
   "fully asset-ready".
2. **The separate `ability_pop_up.pal` is redundant** — byte-identical to the
   PNG's embedded palette across all 16 colours (checked). Same good-direction
   resolution as the sandstorm BG and the ball particles: no second pull
   needed, and the embedded palette gives correct colours.

---

### 3.1 FLAGGED, NOT FIXED — 17 other files share this defect

An audit of all 57 files in `assets/sprites/battle_ui/interface/` found **18**
with the same shape: mode-`P`, no tRNS, palette index 0 on all four corners.
B6-1 fixed only `ability_pop_up.png`. **The other 17 are flagged here and
deliberately left alone**, per the standing flag-don't-silently-fix rule —
blanket-tagging assets that currently render acceptably risks breaking working
visuals.

Consumer audit (by exact `res://` path, after correcting for two same-named
files in different directories):

- **15 have ZERO consumers** — latent only, no current visual impact:
  `ball_caught_indicator`, `ball_display`, `enemy_mon_shadow`,
  `healthbox_doubles_opponent`, `healthbox_doubles_player`, `healthbox_safari`,
  `hpbar_anim`, `last_used_ball_l`, `last_used_ball_l_cycle`,
  `last_used_ball_r`, `last_used_ball_r_cycle`, `level_up_banner`,
  `misc_frameend`, plus `interface/ball_status_bar.png` and `hpbar.png`
  (see below).
- **2 ARE live and are the only real candidates for a current bug**:
  `interface/party_hold_icons.png` and `interface/party_status_icons.png`,
  both loaded by the Switch/Party screen (M25h-4). **Not asserted as broken** —
  M25h-4 screenshot-verified that screen and reported the icons as correct, so
  either they render acceptably or the defect was missed. Worth a look during
  M26G1's consistency pass; cheap to confirm either way.

**Two false alarms worth recording so they aren't re-investigated:**

- **`ball_status_bar.png` exists TWICE.** `interface/` holds an untagged stale
  copy from the Phase 1 bulk pull; `party_status/` holds M26B5's own correctly
  tagged copy (`tRNS=0`, via `gen_ball_sprites.py`'s index-0 rule). The code
  loads the **`party_status/` one**, so **M26B5's bar is NOT affected** — this
  looked briefly like it might explain one of M26B5's reported defects, and it
  does not.
- **`hpbar.png`** has no `res://` reference at all: M26B1 replaced its use with
  a runtime-generated solid-fill texture, so it is effectively dead.

## 4. The real risk: trigger volume and per-effect vs per-activation

`ability_triggered(pokemon, effect_key)` fires from **109 sites** across **72
distinct effect keys**. It is a **per-EFFECT** signal; the popup is a
**per-ACTIVATION** visual. Wiring one to the other naively means:

- an ability that emits more than one key during a single activation would
  stack multiple popups, and
- a long chain of triggers would queue ~1.9 s of banner each.

**Source already solves this and the solution should be ported, not invented:**
`gBattleStruct->battlerState[battler].activeAbilityPopUps` allows **one popup
per battler at a time**, and `UpdateAbilityPopup` **rewrites the ability text on
the existing popup** rather than creating a second. That is why
`PrintAbilityOnAbilityPopUp` blanks its line before printing.

**Open question for implementation (not resolvable from source alone):**
whether all 72 effect keys should raise a popup, or only a subset. Some keys
name a genuine ability activation (`intimidate`, `absorb_heal`); others may be
sub-effects of one activation. This needs a per-key pass against the 109 emit
sites — the same data-driven-guard approach D3-1/D3-3/D3-7 used, where the test
re-derives the key list from `battle_manager.gd` rather than hand-keeping it.

---

## 5. Residual signals inherited from D3-2

Neither is covered by the popup; both still want **message-box** text. Current
state verified:

| Signal | log | debug | Notes |
|---|---|---|---|
| `ability_triggered` | no | **yes** | B6's own input. `_ABILITY_TRIGGER_TEXT` (~86 entries) **stays on the debug panel** — its non-source phrasing is appropriate there and wrong for the message box. |
| `ability_healed` | no | **yes** | Source has real "regained health" lines. An unexplained heal reads as a bug. Confirm per-ability. |
| `ability_changed` | no | no | Trace / Mummy / Receiver / Wandering Spirit. Source: *"{mon} traced {mon}'s {ability}!"* — fully independent of the popup, **carveable out at any time**. |

`AbilityData.ability_name` exists, so naming the ability needs no new data.

---

## 6. Proposed sub-scope

- **B6-1 — asset fix. COMPLETE 2026-07-27.** 4/4 in a new
  `scenes/battle/m26_b6_1_popup_asset_test.tscn`; 5 asset-adjacent suites
  green. New `scripts/gen_ability_popup_sprite.py` re-pulls the panel with
  index 0 tagged, asserts the four-corner key assumption and the
  embedded-vs-separate palette equality, and leaves ~70% real opaque art
  (2894/4096 px) — pinned by a non-vacuity assertion, since a fully-keyed
  image would pass a corner check while containing nothing to draw. No
  generator existed for `battle_ui/interface/` (it was a bulk filtered copy),
  so this adds one rather than editing a file in place with no record.
- **B6-2 — the popup node and its animation. COMPLETE 2026-07-27.** 21/21 in a
  new `scenes/battle/m26_b6_2_popup_node_test.tscn`; 9 further suites green.
  Shipped `_play_ability_popup(mon)` plus `_ability_popup_slot()` and
  `_ability_popup_target()`, with both coordinate tables and all three timing
  constants taken from source and asserted against it.
  **Tween-driven, not `MonAnimator.Clock`** — a change from this plan: the
  motion is a plain linear slide with no per-frame state, and M26G4's audit
  established that tween-driven work is exact at any refresh rate while
  discrete steppers drift, so a stepper would have been strictly worse here.
  `_ability_popup_slot()` is deliberately NOT `_find_mon_slot()`: that returns
  sprite/panel nodes but not the slot INDEX, which doubles placement needs.
  **The load-bearing assertion is C.02 — the panel must LEAVE the way it came.**
  Source reverses its own `xSlide` sign rather than continuing across the
  screen; a "slide out to the other side" port would look plausible and be
  wrong on the opponent's side. Also asserted: singles must not silently fall
  back to the doubles table (C.04). **Not yet seen on screen** — B6-3 adds the
  text and B6-4 the triggers, so a capture pass belongs after those.
- **B6-3 — two-line text. COMPLETE 2026-07-27.** Suite grew 21→**32/32**;
  7 further suites green. Shipped `_possessive_name()`,
  `_build_ability_popup_text()`, `_make_ability_popup_label()` and
  `_set_ability_popup_ability()`.
  **Band geometry was derived EMPIRICALLY from the panel art, not from source's
  VRAM tile offsets** — those are a tile-addressing detail that doesn't
  transfer. A per-row scan of `ability_pop_up.png` gives a dark band at rows
  3–12 (index 5) and a light band at rows 15–24 (index 7), rows 28–31 fully
  transparent, content spanning x 0–103 of the 128px sheet. **The cross-check
  that this read the bands correctly is that it matches source's own text
  colours**: near-white name on the dark band, black ability on the light one.
  **Font: `_font_healthbox`** — this project's FONT_SMALL extraction, which is
  the font source itself uses (`GetFontIdToFit` starts at FONT_SMALL). Per
  M26D1's recon that variable had **zero usages**; this is its first real
  consumer. Size is *derived* as the largest whole multiple of its native 13
  that fits the band, honouring the standing
  integer-multiple-only invariant rather than hardcoding a number.
  **The ability Label is stored on the panel's metadata**, so B6-4 can rewrite
  it on a live popup — source's `UpdateAbilityPopup`, which is why
  `PrintAbilityOnAbilityPopUp` blanks its line first. Exercised through
  `_set_ability_popup_ability()` rather than by poking the Label.
  **Correction made while testing:** this document's own worked example for the
  possessive rule said *"Pikachu's" but "Chansey'"* — wrong, Chansey ends in
  **y** and so takes `'s`. Fixed here and in CLAUDE.md; the code and tests were
  always correct (they assert Gyarados → `Gyarados'`).
- **B6-3.1 — popup font context. NEW, found by the capture pass, NOT yet
  built.** The capture (2026-07-28) confirmed the panel, transparency,
  placement, slide direction and the possessive name all render correctly — and
  found one real defect: **the text reads muddy and smeared on the dark band.**
  Root cause is not sizing. `gen_battle_fonts.py:168` bakes
  `latin_small_healthbox` with fg `(65,65,65)` dark grey and shadow
  `(222,213,180)` cream — colours chosen for the LIGHT healthbox. On the
  popup's DARK upper band the cream shadow dominates and the dark glyph nearly
  disappears. **`font_color` cannot fix this**: the colours are baked into the
  atlas pixels and Godot's override multiplies, the same trap M25h-1.2 already
  documented when the message box went white-on-white.
  **Fix: bake popup-specific contexts**, exactly as M25h-1.2 generated three —
  and it needs TWO, because the popup's own lines differ: near-white
  `(249,253,255)` on dark for the name, black `(0,0,0)` on light for the
  ability, both with shadow `(143,129,149)`. The `_make_ability_popup_label()`
  colour overrides should then be dropped rather than fought.
  **BUILT 2026-08-03.** Two new `COLOR_CONTEXTS` entries in
  `gen_battle_fonts.py` (`latin_small_popup_name` near-white
  `(249,253,255)`, `latin_small_popup_ability` black, both shadowed
  `(143,129,149)`, background/accent transparent like the healthbox
  context); `_make_ability_popup_label()` now takes the LINE's own FontFile
  and carries zero colour/shadow overrides — the three colour constants stay
  as documentation, asserted by the suite so the generator's choices are
  pinned from the consumer side. Suite grew to **44/44** (Section F: both
  contexts load, are genuinely different bakes, wire to the right lines,
  and no colour override exists on either label — the multiply-trap guard).
  Capture-verified on both sides: "Gyarados'" crisp near-white on the dark
  band, "Rock Head" black on the light one.
- **B6-2.1 — render geometry: uniform 4x + center anchor. NEW, found by a
  rescale review 2026-08-03 (Rob's ask), BUILT same day.** Two real defects
  in B6-2's own shipped geometry: (1) the panel stretched by
  `_weather_stage_scale()` (1024/240 x 768/160 = **4.267 x 4.8**) —
  non-integer, so nearest-neighbour produced uneven pixel columns, and
  non-uniform, so the art drew 12.5% taller than its own aspect; (2) the
  coordinate tables were read as the panel's TOP-LEFT, but pokeemerald
  sprite coords are CENTERS and `CreateAbilityPopUp` places a two-sprite
  pair whose own center is `(table.x + 32, table.y)` — parking the popup
  32 GBA px right and 16 low of the source spot. Now: the anchor point maps
  through the stage scale (placement stays battlefield-relative, like the
  weather effects), the art renders at the same uniform 4x every other
  GBA-native asset uses, the slide distance is the panel's own width at
  that same 4x (B3-2's "scale the motion to the art" precedent), and a new
  `_ability_popup_rest_rect()` makes the geometry assertable on a bare
  instance (Section E, incl. the center-anchor pins E.04/E.05 so the
  top-left misread cannot silently return). A bonus of the uniform scale:
  the 10-row text bands scale to exactly 40px, fitting the native-13
  FONT_SMALL at a clean 3x = 39 under the integer-multiple invariant
  (pinned by F.07). The right-edge tail clip at rest is source-faithful
  (source's own pair overhangs its 240px screen by ~10 GBA px).
- **B6-4 — trigger wiring + the one-popup-per-battler guard**, with an
  `UpdateAbilityPopup` equivalent that rewrites an active popup's ability line
  instead of stacking a second. Includes the per-key audit from §4.
- **B6-5 — the two residual D3-2 signals** (`ability_healed`,
  `ability_changed`) to the message box. Independent of B6-1…B6-4 and shippable
  separately.

**Recommended order:** B6-5 first (smallest, independent, and closes D3's last
loose thread), then B6-1 → B6-2 → B6-3 → B6-4.

---

## 7. Things NOT in scope

- **Audio.** Source plays `SE_BALL_TRAY_ENTER` on slide-in. This project has no
  audio infrastructure anywhere — already flagged as needing its own scoping
  pass.
- **Illusion.** `PrintBattlerOnAbilityPopUp` reads `GetIllusionMonPtr` to show
  the disguised name; Illusion is excluded from this project.
- **Ability Shield.** `BattleScript_AbilityPopUp` opens with
  `tryactivateabilityshield`; that item is not implemented here.
- **`fixedPopup`.** Source can pin a popup open across a script; no consumer
  exists in this project's own dispatch.

---

## 8. Open questions for Rob

1. **Which of the 72 effect keys raise a popup** (§4) — needs a per-key pass;
   the alternative is popping for all of them and accepting some noise.
2. **Pacing.** ~1.9 s per popup, and it is awaited in source the same way
   weather animations are. Combined with M26B4's per-turn weather pause and
   D3-5's per-turn tick lines, this is the third contributor to turn length —
   an M26G2 question, worth watching as B6 lands rather than after.
