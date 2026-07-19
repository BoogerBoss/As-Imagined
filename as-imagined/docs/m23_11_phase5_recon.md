# M23.11 Phase 5 Recon — Environments & Move Animations

Recon and planning only, per explicit instruction — no code written, no
assets pulled this session. Mirrors `docs/m24_recon.md`'s own precedent:
numbered findings sections, a resolved-vs-open scope-decisions section, and
a proposed sequencing plan, all subject to confirmation before any
implementation session begins.

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

### 4.4 Recommendation: a small generic hit-effect library, per-move fidelity explicitly deferred

Given 4.2/4.3: **build a small, type/category-keyed generic hit-effect
system** (e.g. ~15-30 curated particle sprites pulled flat — a burst per
major type family, a physical-impact star, a status-cloud puff, a
stat-buff shimmer — driven by a lightweight Godot `AnimationPlayer`/tween
dispatcher keyed on `move.type`/`move.category`), NOT an attempt at real
per-move fidelity. This directly matches the task's own suggested
fallback option and is the only realistic path given the confirmed 941-
script/125-opcode scope of full fidelity. Real per-move animation
fidelity, if ever wanted, would need its own dedicated multi-session
sub-arc on the scale of M17/M19's own tiered ability/move rollouts — not
attempted here, not silently ruled out either (see Open Question 5).

## 5. Open scope decisions for the project owner (mirrors `docs/m24_recon.md` §6 format)

1. **Background reconstruction approach**: confirm the "one-time Python
   reconstruction script → flat PNG → this project's existing flat-copy
   pipeline" approach (§2's recommendation) rather than a live Godot-side
   tile renderer.
2. **Intro-reveal animation**: confirm excluding the `.entry` layer
   (grass-parting-style intro wipe) from scope — Phase 5 delivers only the
   steady-state background, not the GBA-style reveal animation.
3. **Background-selection mechanism**: given no overworld/map data exists
   yet (§3), which placeholder approach do you want — (a) one single
   hardcoded default background for every battle, (b) a manual picker
   added to `battle_setup_screen.gd`, (c) something else? Real per-
   encounter selection waits for M26 either way.
4. **Palette-variant scope**: pull only the 11 base terrain tilesets now,
   or also the ~11 extra palette-only recolors (Elite Four members, Team
   Aqua/Magma HQ, Champion, Frontier, Groudon/Kyogre)? The latter has no
   real consumer yet (no trainer-vs-player battle flow exists — same
   "data ahead of consumer" situation M24a/M24c already established as an
   acceptable pattern in this project).
5. **Move-animation scope**: confirm the generic hit-effect library
   approach (§4.4) as Phase 5's real deliverable for move animations
   rather than (a) skipping move animations entirely for now (just damage
   numbers/HP drain, no VFX), or (b) attempting real per-move fidelity for
   a small hand-picked subset of "iconic" moves first.
6. **Secret Power/Nature Power/Camouflage reconsideration**: building even
   a minimal environment-id concept in Phase 5 would remove the specific
   blocker that's kept these 3 moves permanently excluded (§1.3). Not
   proposing to build them now — just flagging that Phase 5 may make them
   newly buildable, for Rob's own future prioritization.

## 6. Proposed sequencing plan (mirrors M23.11's own Phase 4a-4f discipline)

- **Phase 5a — Environment backgrounds**: build the one-time reconstruction
  script (§2), pull the 11 base tilesets as flat PNGs via the established
  flat-copy convention, wire a manual/default selector into
  `battle_setup_screen.gd` (§3), regression sweep. No move animations yet.
- **Phase 5b — Generic hit-effect asset pull**: curate and flat-copy ~15-30
  representative particle sprites from `graphics/battle_anims/sprites/`
  (§4.4), following the exact `gen_*_sprites.py` precedent — asset staging
  only, no engine wiring yet (matching Phase 1's own "no UI consumption
  this session" discipline).
- **Phase 5c — Generic hit-effect dispatch**: a small type/category-keyed
  effect-selection system wired into `battle_screen.gd`'s existing
  `move_executed` signal handling, triggering the appropriate pulled
  sprite via `AnimationPlayer`/tween. This is the first phase with real UI
  consumption.
- **Phase 5d (explicitly NOT scoped now, a future candidate only)**:
  palette-variant pull for special-context battles (Elite Four/Champion/
  legendary encounters) — deferred pending a real trainer-battle
  consumer, per Open Question 4.

Risk/complexity ranking: 5a (moderate — new reconstruction-script format,
but small/bounded scope) < 5b (low — same flat-copy shape as every prior
asset phase) < 5c (moderate — first real animation-dispatch engine code
in this project, though deliberately small) < 5d (low effort, but
explicitly deferred, no consumer yet).
