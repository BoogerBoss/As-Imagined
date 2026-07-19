# M23.11 Phase 5 Recon — Environments & Move Animations

Recon and planning only, per explicit instruction — no code written, no
assets pulled this session. Mirrors `docs/m24_recon.md`'s own precedent:
numbered findings sections, a resolved-vs-open scope-decisions section, and
a proposed sequencing plan, all subject to confirmation before any
implementation session begins.

## 0. Locked scope decisions (resolved 2026-07-19)

All 6 open questions from §5 have been resolved by the project owner.
Findings sections below are left as originally written (including the
now-superseded recommendation language in §2/§4.4) for audit-trail
purposes; §5 and §6 have been updated in place to reflect the decisions
directly. Summary:

1. **Background reconstruction**: flat PNGs via a one-time Python script
   (§2's own recommendation) — confirmed, not a live Godot tile renderer.
2. **Intro-reveal animation**: excluded from Phase 5 scope. Flagged as a
   possible future standalone item — **not yet assigned to any milestone**,
   not tracked against Phase 5 or any other numbered slot.
3. **Background selection**: a manual picker added to
   `battle_setup_screen.gd` — not a single hardcoded default.
4. **Palette-variant scope**: only the 11 real base tilesets are pulled in
   5a. The ~11 palette-only recolors (Elite Four, Champion, legendaries,
   Frontier, etc.) are deferred to 5d — still no real consumer (no
   trainer-vs-player battle flow exists yet).
5. **Move-animation approach**: a **hybrid model** — the generic
   type/category-keyed hit-effect library (§4.4) remains the baseline for
   the full move roster, but 3 hand-picked moves (**Flamethrower, Thunder,
   Surf**) get real bespoke, higher-fidelity animations instead of falling
   into the generic dispatch. See the updated §4.4/§6 for what this means
   for 5b (asset pull) and 5c (dispatch engine).
6. **Secret Power/Nature Power/Camouflage**: not built, not scoped into
   Phase 5. The finding itself (§1.3) has been added to CLAUDE.md's M34 row
   as an optional/nice-to-have item, explicitly marked lower-priority than
   M34's other consolidated exclusions.

## 1. Environments — source structure, re-derived directly

Source: `graphics/battle_environment/` (art) + `src/data/graphics/
battle_environment.h` (asset declarations) + `include/battle_environment.h`
/ `src/data/battle_environment.h` (the real per-environment struct/table) +
`src/battle_bg.c` (runtime load/selection logic).

### 1.1 This is genuinely tile+tilemap, not flat images

Every terrain directory (`building/`, `cave/`, `long_grass/`, `plain/`,
`pond_water/`, `rock/`, `sand/`, `sky/`, `stadium/`, `tall_grass/`,
`underwater/`, `water/` — 12 directories on disk) contains, where a real
distinct tileset exists:

- `tiles.png` — a 128×128px, 4bpp indexed tile ATLAS (16×16 grid of 8×8
  tiles, confirmed via direct `identify`/PIL inspection on `rock`/`cave`/
  `water`/`sky`/`stadium`/`building` — uniformly 128×128, mode `P`, **no
  alpha transparency** — these are opaque backdrops, unlike every sprite
  asset pulled in prior phases).
- `map.bin` — a 4096-byte binary tilemap (2048 `u16` little-endian
  screen-entries: low 10 bits = tile index into the atlas, upper bits =
  palette bank / h-flip / v-flip — the standard GBA BG screen-entry
  format). Directly decoded one real file (`rock/map.bin`) to confirm this
  isn't a compressed blob: 99 distinct tile indices used, all within the
  atlas's 256-slot capacity, consistent with a 64-tile-wide × 32-tile-tall
  layout (2048 = 64×32) — wider than the visible 240px GBA screen,
  consistent with a horizontally-scrollable backdrop.
- `palette.pal` — a separate, small palette file.
- `anim_tiles.png` / `anim_map.bin` — **NOT a shimmer-loop variant as the
  filename suggests.** Confirmed via `battle_bg.c`'s own
  `LoadBattleEnvironmentEntryGfx`: this is a SEPARATE layer (`.entry` in
  the real `struct BattleEnvironment`, loaded onto BG1 vs. the main
  background's BG3/BG_CHAR_ADDR(2)) used for the battle-INTRO reveal
  animation (e.g. the tall-grass-parting effect when a wild encounter
  starts) — a second, independent tile+tilemap pair per environment, not
  a variant of the first.

`.smol`/`.smolTM` suffixes seen in the `INCGFX_U32(...)` declarations are a
**build-time** compression step applied by the ROM toolchain — the actual
checked-in source files (`tiles.png`, `map.bin`) are plain, uncompressed,
directly-readable assets. No exotic decompression is needed to work with
these files as they sit in the reference checkout.

### 1.2 Real environment count: ~11 distinct tile/tilemap sets, 32 logical entries

`include/constants/battle.h`'s `enum` defines **32** `BATTLE_ENVIRONMENT_*`
values (`BATTLE_ENVIRONMENT_COUNT`). But most of these are **palette-only
variants sharing one underlying tileset**, confirmed via `src/data/
battle_environment.h`'s own macro comments:

- `BUILDING`'s tiles/tilemap are shared by **11** logical entries: `PLAIN`,
  `FRONTIER`, `GYM`, `LEADER`, `MAGMA`, `AQUA`, `SIDNEY`, `PHOEBE`,
  `GLACIA`, `DRAKE`, `CHAMPION` — differing only by which `.pal` file is
  loaded (confirmed directly: `stadium/` alone holds 8 separate `.pal`
  files — `aqua`/`battle_frontier`/`drake`/`glacia`/`magma`/`phoebe`/
  `sidney`/`wallace` — all recoloring the one `stadium/tiles.png`).
- `CAVE`'s tileset is shared by `GROUDON`/`KYOGRE` (their own `.pal` files
  live under `cave/` and `water/` respectively).
- Several enum values (`SOARING`, `SKY_PILLAR`, `BURIAL_GROUND`, `PUDDLE`,
  `MARSH`, `SWAMP`, `SNOW`, `ICE`, `VOLCANO`, `DISTORTION_WORLD`, `SPACE`,
  `ULTRA_SPACE`) have **no dedicated art directory at all** in this
  checkout — they fall back to sharing an existing environment's assets
  (the same macro-value-sharing pattern), not missing/broken data.

**Real distinct visual base tilesets: 11** (TallGrass, LongGrass, Sand,
Underwater, Water, PondWater, Rock, Cave, Building, Stadium, Rayquaza/Sky).
Palette recolors bring the total *color* variants to ~22+, but that's a
much cheaper problem than 32 separate compositions.

### 1.3 A real, useful side-connection: `struct BattleEnvironment` also
### carries move-mechanic data this project has 3 permanently-excluded moves for

The real struct (`include/battle_environment.h`) is not just graphics — it
also stores `naturePower` (which move Nature Power calls per terrain),
`secretPowerAnimation`/`secretPowerEffect` (Secret Power's per-terrain
status effect), and `camouflageType`/`camouflageBlend` (Camouflage's
per-terrain type). **Secret Power, Nature Power, and Camouflage are all
currently permanently excluded/deferred in this project specifically
because no `gBattleEnvironment` analog exists** (see `[M19.5 addendum]`,
`[D1 easy bundle]` decisions.md entries). Building even a minimal
environment-id concept in Phase 5 would, as a side effect, remove that
specific blocker — flagged as a related consideration, not scoped into
Phase 5 itself (see Open Question 6 below).

### 1.4 Background selection at battle-start time (source)

`GetBattleEnvironmentOverride()` (`battle_bg.c`) resolves the environment
through the following precedence, none of which this project's own
architecture currently supports natively:

1. A test-runner forced-environment override (dev/debug only).
2. `BATTLE_TYPE_FRONTIER`/`LINK`/`RECORDED_LINK`/`EREADER_TRAINER` →
   `FRONTIER`.
3. `BATTLE_TYPE_LEGENDARY` + specific species (Groudon/Kyogre/Rayquaza) →
   their dedicated environment.
4. `BATTLE_TYPE_TRAINER` + trainer class == LEADER or CHAMPION → `LEADER`/
   `CHAMPION` (stadium recolors).
5. Otherwise: **`GetCurrentMapBattleScene()`** — the CURRENT OVERWORLD
   MAP's own baked-in terrain metadata. This is the real, primary
   selection mechanism for the vast majority of battles (wild encounters
   and ordinary trainer battles alike), and it is a genuine overworld/map
   concept this project does not have at all (M26, not started).

## 2. Environments — flat-PNG vs. tileset: direct recommendation

**Recommend: reconstruct each of the 11 base tilesets into a flat PNG via
a one-time Python script, then follow this project's existing flat-copy
asset-pipeline convention (`gen_*_sprites.py`) exactly as every prior phase
has.** Do NOT build a live runtime tile-composition system in Godot.

Reasoning:

- The source data is genuinely NOT already flat (unlike every asset pulled
  in Phases 1-4 — Pokémon sprites, trainer portraits, item icons, battle
  UI chrome — which were all single pre-rendered PNGs in the reference
  checkout). Reconstruction is a real, one-time requirement here, not
  optional.
- But the reconstruction itself is bounded and well-specified: a small
  (128×128, 4bpp) tile atlas, a small (4KB) standard-format tilemap, and a
  tiny palette file — formats this project's own asset work has ALREADY
  handled correctly (indexed-palette PNGs with this project's own
  established transparency-handling precedent from Phase 1/3, though
  transparency isn't even needed here since backgrounds are opaque). This
  is a contained, one-off Python/PIL script, not a new rendering
  subsystem.
- This project's own established convention — one-time source→flat-PNG
  conversion, committed as a plain git-tracked asset, loaded via a thin
  Registry — has worked cleanly for four straight asset phases. Building a
  LIVE tile+tilemap renderer in Godot (palette-swap machinery, tile-atlas
  slicing, scroll-window logic) would be new, untested surface for a
  purely static, non-interactive backdrop image with no established
  gameplay need for runtime scrolling/parallax in this project's own
  battle screen.
- Maintainability: once flattened, adding a NEW background later (if a
  future map/terrain needs one not in the base 11) is exactly as easy as
  adding a new Pokémon sprite today — copy, regenerate, done. A live
  tile-renderer would need to be built and debugged once regardless, for
  no compounding benefit given the small, bounded set of real
  environments.
- One clarification worth surfacing: the ".entry" intro-reveal layer (1.1
  above) is a genuinely animated, non-trivial GBA effect (a scrolling
  grass-parting wipe, etc.) that a flat-PNG approach cannot reproduce
  faithfully. Recommend treating the STEADY-STATE background (post-intro)
  as Phase 5's actual deliverable, and explicitly excluding the intro-wipe
  animation from scope (a cosmetic flourish, not a mechanical need) —
  see Open Question 2.

## 3. Environments — background-selection scope, given no overworld exists

Confirmed: this project has no map/terrain-metadata system of any kind
(M26 not started, confirmed via grep — no "current terrain"/"map scene"
concept exists anywhere in `scripts/`). Real, automatic per-encounter
background selection is therefore **not achievable this phase** — it
structurally depends on M26's own map data.

**Recommendation: a manual/default selection mechanism now, real selection
deferred to M26.** Concretely: add an optional environment picker to
`battle_setup_screen.gd` (the existing Showdown-style standalone battle
config screen, already the natural home for "configure this test battle"
settings), defaulting to a single generic background (Plain or Building)
when unset — giving the battle screen *some* real backdrop immediately
without inventing a fake terrain-detection system that would just be
thrown away once M26 lands. See Open Question 3 for the exact default/
picker shape, which is Rob's call.

## 4. Move animations — source structure, re-derived directly

Source: `data/battle_anim_scripts.s` (35,606 lines) + `graphics/
battle_anims/` (art assets).

### 4.1 Genuinely per-move, not shared families

**941 distinct `gBattleAnimMove_*` labels** (directly counted), essentially
1:1 with this project's own ~934-move roster — confirming the task's own
suspicion was correct: source assigns each move its OWN named animation
script, not a small number of shared type/category "families" a simple
lookup table could drive. Average script length ~38 lines (35,606 total
lines / 941 scripts, roughly evenly distributed).

### 4.2 Format: a genuine custom bytecode/scripting interpreter, no 1:1 Godot equivalent

Each script is written in a domain-specific assembly-like language
(`createvisualtask`, `waitforvisualfinish`, `createsprite`,
`playsewithpan`, `simple_palette_blend`, `monbg`, etc.), interpreted at
runtime by a large C engine (`battle_anim.c` and friends). Directly counted
**125 distinct opcode-level commands** across the script file — a real,
large vocabulary, not a small handful. Many opcodes are themselves
bespoke, hand-tuned sprite-behavior functions (`create_dragon_breath_fire_
sprite`, `create_megahorn_horn_sprite`, `create_leech_life_needle_sprite`,
etc.), each backed by its own custom motion-curve/particle/timing C code.

**Faithfully porting this system is not realistic as a bounded scope.**
It would mean re-implementing a substantial fraction of a bespoke 2D VFX
engine (125+ opcodes, hundreds of bespoke sprite-behavior functions, 941
individually-authored scripts averaging ~38 lines each) — a project larger
in scope than several already-completed M-tier milestones combined, not a
"Phase 5" sized unit of work.

### 4.3 Real, reusable sprite ART does exist — good news for a simplified system

`graphics/battle_anims/sprites/` holds **450 files** (~150 distinct visual
assets accounting for `.png`+`.pal`+`.import` triples) — the actual VFX
particle art these scripts reference (flames, sparks, impact stars, smoke,
orbs, beams, etc.). Spot-checked several (`blue_flames.png` 32×64/2 frames,
`blue_star.png` 32×224/7 frames, `beam.png` 64×64, `black_smoke.png`
32×16) — these are ordinary flat, indexed, multi-frame sprite STRIPS, the
exact same asset shape as the Pokémon front/back sprites already pulled in
Phase 1 (frame-sliceable via the existing `SpriteRegistry`-style
`AtlasTexture` convention). A genuine mix exists: many assets are clearly
GENERIC and type/theme-appropriate (`blue_flames`, `black_smoke`,
`blue_star`, `big_rock`, `beam`) alongside some move-SPECIFIC one-offs
(`assurance_hand`, `baton_pass_ball`, `blacephalon_head`) that wouldn't
generalize.

### 4.4 Locked scope: hybrid model — generic library baseline + 3 bespoke moves

**Resolved by Open Question 5 (§0/§5): a hybrid model**, not a pure
generic-only system. Two tiers:

- **Baseline (the whole roster minus the 3 below)**: the originally
  recommended small, type/category-keyed generic hit-effect system —
  ~15-30 curated particle sprites pulled flat (a burst per major type
  family, a physical-impact star, a status-cloud puff, a stat-buff
  shimmer), driven by a lightweight Godot `AnimationPlayer`/tween
  dispatcher keyed on `move.type`/`move.category`. This remains the only
  realistic path for the other ~938 moves, given the confirmed
  941-script/125-opcode scope a full-fidelity port would require.
- **Bespoke (Flamethrower, Thunder, Surf only)**: these 3 hand-picked
  moves get their own real, higher-fidelity animation instead of falling
  into the generic dispatch — a deliberately small, bounded proof-of-
  concept for what real per-move fidelity looks like in this project,
  without committing to the full 941-move scope. 5b's asset pull now
  needs to also identify and pull whatever source assets these 3 moves'
  own `gBattleAnimMove_*` scripts actually reference (their real sprite
  strips, not just the generic library's own curated set); 5c's dispatch
  engine needs a special-case branch — check the move's own ID against
  these 3 first, dispatch to its bespoke animation if matched, only fall
  through to the generic type/category dispatch otherwise.

Real per-move fidelity for the REMAINING ~938 moves, if ever wanted, would
still need its own dedicated multi-session sub-arc on the scale of
M17/M19's own tiered ability/move rollouts — this hybrid model is not a
first step toward that, just a bounded exception for 3 specific moves.

## 5. Scope decisions (mirrors `docs/m24_recon.md` §6 format) — RESOLVED 2026-07-19

All 6 questions below are now closed. Original question text preserved for
context; each is marked with the locked decision.

1. **Background reconstruction approach** — **RESOLVED: confirmed.** The
   "one-time Python reconstruction script → flat PNG → this project's
   existing flat-copy pipeline" approach (§2's recommendation), not a live
   Godot-side tile renderer.
2. **Intro-reveal animation** — **RESOLVED: excluded from Phase 5 scope.**
   Phase 5 delivers only the steady-state background, not the `.entry`
   layer's GBA-style grass-parting reveal wipe. Flagged as a possible
   future standalone item, **not yet assigned to any milestone**.
3. **Background-selection mechanism** — **RESOLVED: (b), a manual picker
   added to `battle_setup_screen.gd`.** Not a single hardcoded default.
   Real per-encounter selection still waits for M26.
4. **Palette-variant scope** — **RESOLVED: only the 11 base terrain
   tilesets are pulled in 5a.** The ~11 extra palette-only recolors (Elite
   Four members, Team Aqua/Magma HQ, Champion, Frontier, Groudon/Kyogre)
   are deferred to 5d — still no real consumer (no trainer-vs-player
   battle flow exists yet, same "data ahead of consumer" pattern
   M24a/M24c already established as acceptable in this project).
5. **Move-animation scope** — **RESOLVED: a hybrid model.** The generic
   hit-effect library (§4.4) remains the baseline for the full roster, PLUS
   3 hand-picked moves (Flamethrower, Thunder, Surf) get real bespoke,
   higher-fidelity animations rather than the generic dispatch. Neither of
   the original two alternatives (skip VFX entirely, or attempt full
   fidelity for a hand-picked subset) was chosen outright — see §4.4 for
   the resolved shape.
6. **Secret Power/Nature Power/Camouflage reconsideration** — **RESOLVED:
   not built, not scoped into Phase 5.** The finding (§1.3) has been added
   to CLAUDE.md's M34 row as an optional/nice-to-have item, explicitly
   marked lower-priority than M34's other consolidated exclusions.

## 6. Sequencing plan (mirrors M23.11's own Phase 4a-4f discipline) — LOCKED 2026-07-19

- **Phase 5a — Environment backgrounds**: build the one-time reconstruction
  script (§2), pull the **11 base tilesets only** as flat PNGs via the
  established flat-copy convention (palette recolors deferred to 5d, per
  §5 item 4), wire a **manual picker** into `battle_setup_screen.gd` (§5
  item 3 — not a hardcoded default), regression sweep. No move animations
  yet. The intro-reveal wipe (§5 item 2) stays out of scope here and
  everywhere else in Phase 5.
- **Phase 5b — Hit-effect asset pull (hybrid)**: two parts, per the locked
  §4.4 hybrid model —
  1. Curate and flat-copy ~15-30 representative GENERIC particle sprites
     from `graphics/battle_anims/sprites/`, following the exact
     `gen_*_sprites.py` precedent (the original baseline scope, unchanged).
  2. Additionally identify and pull whichever real source assets
     Flamethrower's, Thunder's, and Surf's own individual
     `gBattleAnimMove_*` scripts actually reference (their real bespoke
     sprite strips, not just the generic library's curated set) — a
     separate, move-ID-keyed pull alongside the generic one.
  Asset staging only for both parts, no engine wiring yet (matching Phase
  1's own "no UI consumption this session" discipline).
- **Phase 5c — Hit-effect dispatch (hybrid)**: a dispatch engine wired
  into `battle_screen.gd`'s existing `move_executed` signal handling, now
  with two tiers per the locked hybrid model —
  1. **Special-case branch, checked first**: if the executed move's ID is
     Flamethrower, Thunder, or Surf, dispatch to that move's own bespoke
     animation (5b's move-specific pull) instead of the generic path.
  2. **Generic fallback**: every other move falls through to the original
     type/category-keyed effect-selection system, triggering the
     appropriate generic pulled sprite via `AnimationPlayer`/tween.
  This is the first phase with real UI consumption.
- **Phase 5d — Palette-variant pull (still explicitly deferred)**:
  palette-variant recolors for special-context battles (Elite Four/
  Champion/legendary encounters) — still deferred pending a real
  trainer-battle consumer, per §5 item 4. Unchanged by this session's
  decisions; listed here for completeness of the locked plan.

Risk/complexity ranking: 5a (moderate — new reconstruction-script format,
but small/bounded scope) < 5b (low-to-moderate — the generic half is the
same flat-copy shape as every prior asset phase; the 3-move bespoke half
is new territory, identifying and isolating real per-script asset
references for the first time, but bounded to exactly 3 moves) < 5c
(moderate-to-higher — first real animation-dispatch engine code in this
project, now with two dispatch tiers instead of one) < 5d (low effort,
but explicitly deferred, no consumer yet).
