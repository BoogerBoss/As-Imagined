# Overworld Scope — Detailed List (rev. 20)

**Rev 20 settles the render structure: three content-named terrain layers** —
`Ground` / `Objects` / `Overhangs` — with the Y-sorted entity container as a
**sibling of `Objects`**, which is the detail that makes buildings sort
correctly. Supersedes §0's original elevation-named layer framing. The
multi-tier second entity container is **deferred and verifiably safe to
defer**: elevation 4/5 is 1.05% of Kanto cells, and **none of the first ten
maps of the game use it at all**.

---

# (rev. 19 header, retained)

**Rev 19 measures the elevation table (§1.4) — the last blocker on Phase 1.**
Sampled all 421 Kanto maps / 305 layouts / 216,537 cells: **only five of the
sixteen values occur**, three of them mapping onto named source constants, so
the 5-bucket enum fits exactly. **The accepted multi-tier limitation turns out
not to apply to Kanto** — zero layouts use both upper values, so collapsing
them loses nothing. Bonus: collision is effectively boolean here (only 0 and 1
occur). Two decisions remain open, neither blocking.

---

# (rev. 18 header, retained)

**Rev 18 closes the last three product decisions.**

- **Simulator caught-only mode: AS-CAUGHT** — the exact instance, real
  IVs/nature/EVs/moveset. This is a **save-format constraint**: the RPG save
  must persist per-instance fidelity for every caught Pokémon, party and boxes
  alike. Store them in `TeamStorage`'s existing spec shape and the simulator
  side is close to free.
- **Scripted partner double battles: IN. Persistent follower: OUT** — short-term
  scripted escorts cover the walking-together case. §17.2 sizes the real cost:
  the control-flag change is small, but **the party model is a genuine design
  decision**, because the reference gives the partner its own party while this
  project has one `BattleParty` per side.
- **Three decisions remain open**, none blocking, one of them mine to unblock.

---

# (rev. 17 header, retained)

**Rev 17 closes two decisions and answers two cost questions.** Lead-ability
encounter hooks: **all eight out**. Nuzlocke party semantics: **decided at
implementation time**. New assessments:

- **§17.1 — RPG save → simulator "caught-only" mode.** The plumbing is nearly
  free: `TeamStorage` already stores construction-input specs, `PokemonFactory`
  already rebuilds from that exact shape, and `BattleSetupContext` is
  origin-agnostic, so **the battle engine needs zero changes**. The open part
  is a design question — *as-caught instances* vs *species-unlocked* — and it
  must be settled **before the save format is fixed**.
- **§26 — partner double battles are a separate system from followers.** A
  scripted partner battle is a script command setting `gPartnerTrainerId`, with
  the partner's team coming from a static table; no follower is involved. The
  real blocker is ours: `_human_controlled` is indexed **by side**, so the
  player's side cannot currently be half-human, half-AI.

---

# (rev. 16 header, retained)

**Rev 16 adds §30, an ordered roadmap with every settled decision folded in**,
renames §29 to **Modes and tweaks** and moves the in-battle speed multiplier
into it (it is a fourth thing that changes how a battle plays without changing
its rules), and records **trainer roster-swap difficulty as deliberately
parked** — undecided at no ongoing cost, since the seam is a ten-minute
retrofit on one loader function.

---

# (rev. 15 header, retained)

**Rev 15 settles the Options menu and answers two cost questions.**

- **Options (§16):** TEXT SPEED, BATTLE STYLE and FRAME **in**; BATTLE SCENE
  **out**; BUTTON MODE **replaced** by Godot-native control remapping; SOUND
  deferred with audio. Plus one original option with no reference equivalent —
  a universal in-battle speed multiplier.
- **§16.1 — in-battle speed multiplier: cheap.** `Engine.time_scale` covers
  the whole battle timing surface (25 tweens, 3 timers, 2 `MonAnimator.Clock`
  steppers) because none of it uses hand-rolled `Time.get_ticks_msec()`
  pacing — a direct dividend of M26G4's audit. One property, set on entry and
  restored on exit. It also absorbs BATTLE SCENE's intent without the desync
  risk of skipping queued beats.
- **§29 — roster-swap seam: a ten-minute retrofit, so stay undecided.**
  `TrainerRegistry.get_trainer()` is one path-convention function; the seam is
  an optional variant path with fallback, mirroring the reference's own
  null-fallback exactly. The only thing worth protecting now is that
  difficulty resolution stays outside `BattleManager` — which it already does.

---

# (rev. 14 header, retained)

**Rev 14 closes the two research questions and locks RPG difficulty.**

- **Dialogue Manager — RPG side only** (§6.1). The RPG leans on it properly:
  conversational branching, conditions, responses, mutations calling into
  engine systems. The **battle simulator stays plain** — minimal dialogue, no
  branching, keeping the already-built `MessageLabel` + `_run_message_pacing()`
  typewriter. Recorded precisely: DM is a *superseded* dependency, not an
  unused one — Phase 4e really used it, M26A2 retired that use, and rev 14
  gives it a new job rather than resuming the old.
- **RPG difficulty is exactly three things** (§29), everything else out —
  including level caps, EV caps, all eight alternate-mode flags, and the
  reference's own EASY/NORMAL/HARD roster-swap system:
  1. **EXP variants renamed Reduced / Normal / Bonus** — a rename of the
     shipped `DifficultyMode`, mapped by value (`HARD`→`REDUCED` ×0.50,
     `CASUAL`→`BONUS` ×1.35). The old naming read backwards.
  2. **Nuzlocke mode** — fainted Pokémon cannot be revived at all. Original
     design; no reference equivalent.
  3. **Toggleable per-battle item limit** for the player. Original; the
     nearest reference analogue is a binary bag lockout, not a budget.
- **Simulator game modes and difficulty are deferred to M35** (battle
  expansion) and are out of this document entirely.
- **New: the reference Options menu enumerated** (§16) — exactly six items,
  with a note on what it conspicuously lacks.

---

# (rev. 13 header, retained)

**Rev 13 settles three more decisions and delivers the two research tasks.**
Settled: field-move badge gating ports the FRLG mapping **exactly** (re-mapped
later as the story develops); **speaker names are ours to implement**, neither
ported from `field_name_box.c` nor taken from Dialogue Manager; the summary
screen reproduces INFO / SKILLS / BATTLE MOVES faithfully while **keeping the
fourth page slot parameterised and empty** for possible alternate information.

Research delivered, decisions still open:
- **§6.1 — Dialogue Manager.** It has **zero live consumers today**, and it is
  far more capable than a message box (conditions, mutations that call game
  code, responses, jumps, a native speaker field). §0's boundary is drawn in
  the wrong place as a result — the real line is a script's *spine*, not its
  verbs. Raises a genuine question about whether the plugin still earns its
  place if it ends up providing typewriter text alone.
- **§29 — Difficulty, caps and alternate modes.** The reference has its own
  **EASY/NORMAL/HARD system that swaps trainer rosters**, script-settable
  mid-playthrough — and it **collides by name** with this project's existing
  `BattleManager.difficulty_mode`, which is an EXP multiplier and an entirely
  different mechanism. Plus full level/EV cap machinery (including catch-up
  EXP) and eight alternate-mode flags.

---

# (rev. 12 header, retained)

Compiled from pokeemerald-expansion. Descriptions per sub-point. Opens with the
current implementation plan (§0); closes with scope status (§24), the game-flow
arc (§25), newly-surfaced systems (§26), settled and outstanding decisions
(§27), and deferred nice-to-haves (§28).

**Rev 12 records Rob's decisions on the rev 11 open list and answers five
questions that needed research rather than opinion.** Eleven items settled
(§27); six still open, two of which are blocked on measurement or verification
rather than preference.

**One correction, and it is a real one: §19's live-world snapshot description
was wrong on every count.** Verified in source: `objectEventTemplates` is
cleared and refilled from the map header on every map load, `mapView` is a
screen-window snapshot cleared on restore rather than a world-wide tile-diff
ledger, and cut trees persist through ordinary object-event visibility flags —
in FRLG's Cerulean City, through a **temp** flag, so the tree regrows on
re-entry. The upshot is that a whole persistence category and a 512-byte
structure come **out** of scope rather than into it.

Two answers worth carrying forward: **NPC following really is just replaying
the player's previous tile** (the reference logs exactly one coordinate pair) —
the 1,885-line file is edge cases, not step logic — and **field-move badge
gating is one-line flag checks entirely independent of map data**, so it is
adjustable at any time and is not a decision that blocks importing.

**Rev 11 adds the results of a full reference sweep** (config headers, `src/`
inventory, encounter internals) looking specifically for systems this document
had never named. Findings, in rough order of consequence:

- **§25 — an entire missing arc: new-game flow and endgame.** Title screen,
  main menu / save-slot selection, opening cinematic, professor intro, starter
  choice, player naming, Hall of Fame, credits. None of it was in rev 10, and
  player naming is the concrete thing that unblocks the §0 player-identity item.
- **§11 — seven lead-Pokémon ability encounter modifiers that are ON by
  default** at `GEN_LATEST` and were entirely unlisted.
- **§26 — five real systems newly surfaced**, each with a decision attached:
  badge-gated level caps (with a real default table), Pokérus (**enabled by
  default**), the FRLG map-preview screen (**effectively on for a Kanto
  project, with Kanto art already present**), the dialogue name box, and NPC
  followers.
- **§5** — fishing is a configurable subsystem with a real reeling minigame,
  not the one line rev 10 gave it.
- **§24** — the OUT list now carries sizing: the confirmed exclusions total
  **~67,000 lines** of reference source.

---

### Revision history

**Rev 10 merges `docs/m27_recon.md` and `docs/m27a_recon.md` into this
document, which is now the single overworld scope of record.** Those two files
are superseded; keep them only as history. Changes from rev 9:

- **Kanto encounter data is IN and imported** — the 264-of-388 figure is
  verified from source (§11).
- **Import first, author tweaks after** — settled for map geometry AND
  encounters. The `pallettown.tscn` spike is **no longer the starting point**,
  reversing rev 9's own §0 line (§0, §20).
- **New: the FRLG 32-bit metatile-attribute trap** (§1) — the one finding from
  the M27A pass genuinely absent from rev 9, and the most expensive thing here
  to get wrong silently.
- **New: a 0–15 → 5-bucket elevation mapping table is a required deliverable**
  (§1, §22) — a real seam neither prior document covered.
- **New: five battle-side carry-ins** already researched during M26 and
  otherwise at risk of being re-derived (marked **[carry-in]**).
- **New: §22.1, a numbers-reconciliation gate before implementation begins.**

Items awaiting Rob's decision are marked **[OPEN — Rob]**.

---

## 0. Current Implementation Plan

- **⚠ Save-slot self-containment ("box rule") — day-one constraint** — Every
  piece of playthrough state (world flags/vars, party, money, stats, field
  effects, position) lives inside the active save slot's payload; nothing
  playthrough-specific is ever stored in shared/global state or fixed paths.
  This is what makes 3 RPG save slots + 3 simulator profiles essentially free
  (a slot = a path prefix) instead of a painful retrofit. Applies to every
  persistent structure from the first one built. **This constraint is the main
  forcing function behind the renumbering recommendation in §23** — it cannot
  wait for a save milestone late in the sequence.
- **Target region: Kanto** — Kanto/FRLG data is present in the reference and is
  substantial, not incidental: **421 Kanto maps** alongside 518 Hoenn, **62
  FRLG secondary tilesets**, and **264 of 388 wild-encounter entries**. Note:
  field-move badge gating differs between Hoenn and FRLG — pick the FRLG
  assignment explicitly.
- **Content strategy: IMPORT FIRST, THEN AUTHOR TWEAKS** *(settled rev 10)* —
  reference map geometry and encounter data are converted in bulk as the
  starting point; Rob authors deviations on top of imported output rather than
  building maps from scratch. This applies to geometry, tilesets, collision,
  elevation, warps, connections and encounter tables alike. What stays authored
  from scratch is **content and meaning**: which NPC stands where and what they
  say, trainer rosters, story triggers.
- **The `pallettown.tscn` prototype is NOT the starting point** *(reverses rev
  9)* — rev 9 adopted it; rev 10 does not. It is hand-painted over a
  third-party metatile sheet, so it carries none of the real blockdata (no
  collision, no elevation, no behaviours), and the real `map.bin` cannot
  address its art at all. Keep it as a reference spike if useful, but the
  importer's output is what A-tier work builds on. Retire or ignore, do not
  extend.
- **Map data via importer (primary path)** — `map.json` + `layouts.json` are
  clean, schema-documented JSON; the binary parts (`map.bin`, `border.bin`,
  `metatiles.bin`, `metatile_attributes.bin`) are the same class of GBA decode
  this project has already done successfully five times. **Prototype the
  importer early as a spike** — it determines the entire content and tooling
  budget. If it works, the editor tooling below (ghost preview, map dock)
  becomes optional polish. Geometry (width/height/tileset/border) lives in
  `layouts.json`, separate from `map.json`.
- **⚠ FRLG metatile attributes are 32-bit; Hoenn's are 16-bit** — see §1. This
  is the single most expensive thing in the importer to get wrong, because it
  fails silently rather than loudly.
- **Scripting is its own milestone** — §6 is not a section-sized component: the
  script language is a coroutine driver over ~620 C specials (~421 actually
  called across ~2,090 call sites). Deciding *which specials are in scope* is
  the real scoping problem, and it needs an M19-style dedicated pass.
  **Specials scoping session planned.** Godot softens implementation cost (our
  "C side" is just GDScript, so the escape hatch is cheap) but not scoping cost.
  Realistically 30–40% of total overworld work — size it as a milestone, never
  as a peer block alongside maps or movement.
- **Dialogue Manager plugin for text presentation** — Handles message boxes,
  typewriter text, choices, and variable interpolation (covers name/item/number
  buffers). Boundary: DM owns *conversations*; the field script engine still
  owns movement scripting, give/take, warps, battle calls, and the specials
  inventory. Scripts call DM for talky parts; DM mutation hooks call back into
  engine systems. (Matches the standing CLAUDE.md constraint: DM was approved
  for conversation/text presentation only and must not become the field script
  engine.)
- **Pure 2D rendering** — HD-2D-style 3D z-depth rejected; depth comes from
  Y-sort, layers, parallax, shadows, and canvas lighting. Simulation and
  rendering stay cleanly separated so a fancier renderer remains possible later
  without touching game logic.
- **Seamless map stitching** — Map connections (N/S/E/W), not discrete scene
  loads.
- **Grid-locked movement with smooth interpolation** — GBA-style: logic moves
  one tile per step, renderer tweens between tiles. Free movement rejected;
  grid position is the simulation's source of truth. Preserves step-based
  mechanics (encounters, Repel, egg/friendship steps) and pokeemerald as a near
  1:1 reference.
- **Day/night system in scope** — Tint via CanvasModulate + gradient keyed to
  time of day; PointLight2D punch-through for windows/lamps at night; interiors
  skip tint via outdoor flag.
- **Accelerated game-time clock** — Fake, accelerated in-game clock (not real
  RTC) so players actually experience the full day/night cycle; drives tint,
  time-of-day encounters, daily flags. Pause behavior (battles/menus/cutscenes)
  to be specified during implementation.
- **Three content-named terrain layers** *(DECIDED rev 20 — supersedes this
  bullet's original elevation-named framing)* — `Ground` / `Objects` /
  `Overhangs`, with the Y-sorted entity container sitting as a **sibling of
  `Objects`**, not beneath it. Full structure and the reasoning in §1.4.
  Elevation is a movement property the step resolver queries, not a rendering
  one — which is why layers are named by content instead. Small enum (ground / water / upper / transition /
  any), not the GBA's 0–15. **Because maps are imported rather than painted,
  the importer needs an explicit 0–15 → 5-bucket mapping table to decide which
  layer each cell lands on** — see §1.
- **Behaviors via TileSet custom data layers** — Metatile behaviors and flags
  ride on tiles as custom data (`behavior`, transition flags); painted art
  carries its logic.
- **Logic-based collision** — No physics layers for movement. A step is a
  request: the resolver reads target-cell behavior + elevation and
  allows/denies/redirects (ledge, ice, warp) before tweening. Deterministic and
  testable in the existing suite style. Source stores collision as 2 bits per
  metatile in the map data and tests it per-tile — Godot physics layers are the
  wrong tool for it, and a custom data layer is both closer to source and
  cheaper.
- **Entity layer sandwich, global containers** — Y-sorted entity containers
  (with a y-sorted Props tile layer as sibling) sandwiched between terrain
  layers; elevation change = deferred `reparent()` driven by an `elevation`
  setter, triggered when a step lands off a transition tile. Containers are
  global across stitched maps so sorting never breaks at seams.
- **No 16-object cap** — The reference's `OBJECT_EVENTS_COUNT` is a GBA RAM
  limit, not a design rule; Godot has no equivalent constraint and no map
  surgery is needed. What carries over: chunk unload frees its entities
  (already in the design), and optionally "sleeping" far-offscreen NPCs so
  patrol timers and sight checks don't tick. Optimization, not required
  machinery.
- **Stitching runtime** — One global tile coordinate space; each map's metadata
  carries connections `{direction, neighbor, offset}`. MapManager computes
  chunk origins, instantiates neighbor scenes into the shared layer containers
  (threaded loading, no frame hitches), unloads non-adjacent chunks with
  hysteresis. `cell_info()` routes queries to the owning chunk.
- **Border blocks via programmatic skirt** — Map loader paints a border-block
  strip (from metadata) on every edge without a connection, deep enough to
  cover screen overshoot. Skirt cells are impassable and marked distinct from
  real map cells. Connected edges get the neighbor map instead.
- **Map hook semantics** — `on_load` = load-time setup (invisible tile edits,
  runs at chunk instantiation); `on_transition` = entry-time reaction (fires on
  border-cross or warp); no heavy visual work on stitched borders. `on_frame`
  polls a small `{var, value, script}` table; `on_warp_into` positions/faces on
  arrival.
- **Player identity is a real, small, early prerequisite** **[carry-in]** —
  trainer name, gender and ID do not exist in any form today. Small, but it
  unblocks a placeholder already sitting in shipped battle code:
  `_PLAYER_BACK_PIC = Leaf` is hardcoded in `battle_screen_shared.gd`
  explicitly awaiting a player-character system. Also gates the `bg_m`/`bg_f`
  gender-variant question in §16.
- **Editor tooling (planned)** — Porymap-style workflow inside Godot:
  behavior/elevation debug overlay (see Dev Tooling), `@tool` ghost-neighbor
  connection preview reading real connection metadata, TileMap Patterns as
  prefab stamps, 16px event snap, event gizmos (warp destination arrows,
  trainer sight cones), later a map dock EditorPlugin for map list + connection
  editing.

---

## 1. Maps & Tilesets

- **Map data record** — Layout, dimensions, and header info: music, default
  weather, map type, show-name-on-entry popup.
- **Seamless map connections** — N/S/E/W stitching so adjacent maps load and
  render contiguously (decided: in). Reference also defines DIVE/EMERGE as
  connection directions that warp rather than stitch geometry — handle them as
  warp targets, not chunk loads.
- **Map metadata (two files, per reference)** — Reference splits this:
  `map.json` holds events/connections/header, `layouts.json` holds geometry
  (width, height, tileset, border) and there is no encounter reference in
  either — encounter/terrain classification derives from the metatile behavior
  byte. Model as one Godot resource but expect a two-file import. Fields:
  outdoor flag (day/night tint applies), bike allowed, run allowed, Escape
  Rope/Dig allowed, dark map (Flash), town-map position, battle
  environment/backdrop key, display name + popup style, encounter table
  reference, heal/respawn definition, fly landing spot, map type enum
  (town/city/route/cave/indoor/underwater — can derive several flags), dive
  pair, camera bounds/lock, border block, tint override (caves/underwater
  ignore day/night), ambient SFX + music overrides, battle transition override,
  connections list.

### 1.1 Binary formats — all understood, none novel

Every binary piece below is the same GBA tile/tilemap shape this project has
already decoded successfully five times (Phase 5a backgrounds, Phase 5c
`water.png`, M25h-4 Bag/Party frames, M26B4 sandstorm BG, and
`gen_ui_frames.py`'s reusable `decode_screen_block`). The novelty is metatiles
— a second indirection, blockdata → metatile → 8 tiles — plus per-tile palette
selection, not the fundamentals.

**Blockdata (`map.bin`)** — `width × height` u16 entries. Verified: Pallet Town
is 24×20 and its `map.bin` is exactly 960 bytes. Per `include/global.fieldmap.h`:

| Bits | Field |
|---|---|
| 0–9 | metatile id (`MAPGRID_METATILE_ID_MASK 0x03FF`) |
| 10–11 | **collision** |
| 12–15 | **elevation** |

Collision and elevation living in the map data is the key structural point:
neither needs authoring by hand, and neither maps onto a Godot physics layer.

**Tilesets** — each directory holds `tiles.png`, `metatiles.bin`,
`metatile_attributes.bin`, and a `palettes/` directory (16 palettes).
`metatiles.bin` is 8 tile entries × u16 per metatile (2×2 tiles on each of two
layers).

### 1.2 ⚠ The FRLG attribute trap — read this before writing the importer

**Hoenn metatile attributes are 16-bit. FRLG's are 32-bit.** Different masks,
different shifts, 9 behaviour bits instead of 8:

```
METATILE_ATTR_BEHAVIOR_MASK_FRLG  0x000001ff   // bits 0-8
METATILE_ATTR_LAYER_MASK_FRLG     0x60000000   // bits 29-30
METATILE_ATTR_LAYER_SHIFT_FRLG    29
```

`struct MapLayout` carries a real `bool8 isFrlg` field — the distinction is
live at runtime in source, not a build-time variant.

Confirmed arithmetically on Pallet Town's secondary tileset: `metatiles.bin`
1424 B ÷ 16 = **89 metatiles**, and `metatile_attributes.bin` 356 B ÷ **4** =
**89**. A 2-byte-per-entry reader produces 178 bogus entries and misparses
every Kanto tileset — **with nothing failing loudly**. Since this project is
Kanto, FRLG is the variant that matters; branch on `isFrlg` rather than
assuming either width.

### 1.3 Metatile behaviors (a subsystem, not an enum)

Reference has **240 enum constants, 213 of them named** (27 are `UNUSED`) with
~190 predicate functions; behavior also drives warp dispatch and
encounter/terrain classification. Design the custom-data layer plus a
predicate/query module, not a flat tag lookup. Behaviors include: tall grass,
deep sand, ice, directional ledges, surfable water, waterfalls, dive spots,
muddy slopes, spin tiles, cracked floors, footprint sand, warp tiles, etc. The
behaviour field is what §11's encounter triggering and §5's ledge/surf handling
read.

### 1.4 Elevation system — and the mapping table that must be built

Layer-derived: ground / water / upper / transition / any. Collision semantics
in reference are equality plus wildcards (0 matches anything, 15 matches as map
tile) — no ordering — so the 5-value enum is correct for movement. Known
limitation, accepted deliberately: reference's full 0–15 range feeds a 16-entry
draw-priority table whose odd/even alternation above 3 produces *stacked*
multi-tier bridges; one "upper" layer gives a single bridge deck. Adding a
second upper layer later is additive, not a rework.

### ✅ The mapping table — MEASURED rev 19, ready to approve

Sampled every Kanto map's real blockdata: **421 maps, 305 distinct layouts,
216,537 cells.** The result is far cleaner than the scoping assumed — **only
five of the sixteen possible values occur at all.**

| Raw | Source constant | Bucket | Kanto cells | % | Layouts |
|---|---|---|---|---|---|
| **0** | `ELEVATION_TRANSITION` | **transition** | 121,738 | 56.22% | all 305 |
| **1** | `ELEVATION_SURF` | **water** | 19,909 | 9.19% | 56 |
| **3** | `ELEVATION_DEFAULT` | **ground** | 72,613 | 33.53% | all 305 |
| **4** | — | **upper** | 1,853 | 0.86% | 25 |
| **5** | — | **upper** | 424 | 0.20% | 3 |
| 15 | `ELEVATION_MULTI_LEVEL` | **any** | 0 | — | 0 |
| 2, 6–14 | — | *(never occur)* | 0 | — | 0 |

Three of the five map onto named source constants, which is why the buckets
line up so exactly — the 5-value enum was effectively reverse-engineered from
these semantics already. `IsElevationMismatchAt` confirms the wildcard
behaviour the enum assumes: both `ELEVATION_TRANSITION` (0) and
`ELEVATION_MULTI_LEVEL` (15) short-circuit to "no mismatch," matching
*anything*.

**⚠ The accepted multi-tier limitation turns out not to apply to Kanto at all.**
§1.4 previously conceded that one `upper` layer gives a single bridge deck,
losing source's stacked tiers. Measured: **zero layouts use both 4 and 5.**
Every map with an upper tier uses exactly one of them — 25 layouts use 4, 3
use 5, none use both. So collapsing 4 and 5 into one `upper` bucket loses
**nothing**; the difference is which value that map's author happened to pick,
not a stacking relationship. The disclosed limitation can be retired.

Worth noting where the outliers live: **elevation 5 appears in exactly three
layouts, all Sevii Islands** (Six Island Ruin Valley, Seven Island Sevault
Canyon and its entrance) — post-game FRLG content. Elevation 4 is the genuine
mainland multi-tier value: Seafoam Islands B1F–B4F, Cerulean Cave, Victory
Road, Safari Zone, Kindle Road — all real multi-level locations.

**Keep the `any` bucket even though Kanto never uses 15**, because
`IsElevationMismatchAt` gives it real wildcard semantics that authored maps or
any future Hoenn import would depend on.

**The importer must assert that no other value appears** rather than bucketing
an unexpected one silently. 2 and 6–14 occurring would mean either an authored
map introducing new semantics or a reference update — both worth failing loudly
on, in the same spirit as §1.2's attribute-width assertion.

### ⚠ Five buckets ≠ five TileMapLayers

Worth stating plainly, because the table above invites the wrong reading. The
five buckets are a **movement-permission enum**, queried per step by the
resolver. How many *render* layers exist is a separate question, driven by how
many visual strata entities need to sort between — and the answer is fewer.

Two of the five are never render strata at all:

- **`transition` (0) is not a layer** — it is the *default*, and the measurement
  makes that obvious: at **56% of all cells** it is the single most common
  value. It does not mean "this cell is a staircase"; it means *"elevation is
  unconstrained here,"* which is true of most of a flat world. Painting 56% of
  Kanto onto a dedicated layer would be meaningless.
- **`any` (15) is not a layer** — same wildcard role, and unused in Kanto.

So the real question is how many strata entities sort between, and the
measurement answers it: **two.** Ground-ish (`transition` / `water` / `ground`)
and `upper`. Since **no Kanto layout uses both upper values**, there is never a
third stratum. That yields the sandwich §0 already describes:

```
terrain (ground stratum: transition / water / ground art)
  entity container  ← Y-sorted, reparented on elevation change
terrain (upper stratum: bridge decks, upper cave tiers)
  entity container  ← Y-sorted
props / overhang    ← optional, draws above everything
```

**`water` is a separate bucket for movement, not for drawing.** Surf is a
traversal-state question (§5); water art sits on the same visual plane as
ground and needs no stratum of its own. It may still deserve its own
TileMapLayer for unrelated reasons — animated tiles (§1.5) are easier to manage
isolated — but that is an organisational choice, not a draw-order requirement,
and the two justifications should not be conflated.

### ✅ DECIDED rev 20 — three terrain layers, content-named

Rob's call, and it supersedes §0's elevation-named framing ("one TileMapLayer
per logical elevation"). Layers are named by **what they contain**, not by
which elevation value painted them — which is the better axis, because
elevation is a movement property the resolver queries, not a rendering one.

```
Overhangs      terrain — roof tops, tree canopy, cave ceilings.  Draws above all.
┌─ Y-sorted parent ─────────────────────────────────────────────┐
│  Objects     terrain, Y-SORTED — houses, trees, signs, rocks   │
│  Entities    container, Y-sorted — player, NPCs, item balls    │
└───────────────────────────────────────────────────────────────┘
Ground         terrain — grass, path, water, floor.  Draws below all.
```

**⚠ The one thing that must not be got wrong: `Objects` has to be Y-sorted and
a SIBLING of the entity container, not a layer beneath it.** Godot 4
`TileMapLayer` supports `y_sort_enabled`, and this is what makes a house work:
the player walks *behind* its upper rows and *in front of* its lower ones,
sorted per-tile by Y. Put `Objects` flatly beneath `Entities` instead and the
player renders over the entire building, roof included. This is §0's existing
"y-sorted Props tile layer as sibling" clause — `Objects` is that layer, better
named.

`Ground` and `Overhangs` need no Y-sorting: one is always below everything, the
other always above.

**Elevation still maps onto this cleanly.** `water` (1) is `Ground` art with a
traversal rule; `transition` (0) and `any` (15) are permission values that
paint nothing of their own; `ground` (3) is `Ground`. Only `upper` (4/5) needs
anything structural — see below.

### The upper stratum — deferred, and verifiably safe to defer

Multi-tier terrain needs a **second entity container**, so an entity on a
bridge deck draws above it while one underneath draws below. That is genuinely
not expressible in the three layers above.

**It is also not needed for a long time.** Measured: elevation 4/5 is
**2,277 of 216,537 cells (1.05%)** across **28 of 305 layouts** — and checking
the first ten maps of the game directly, **none of them use it at all**:

| Map | Upper? | Elevations present |
|---|---|---|
| Pallet Town | no | 0, 1, 3 |
| Route 1 | no | 0, 3 |
| Viridian City | no | 0, 1, 3 |
| Route 2 | no | 0, 3 |
| Viridian Forest | no | 0, 3 |
| Pewter City | no | 0, 3 |
| Route 3 | no | 0, 3 |
| Mt. Moon 1F | no | 0, 3 |
| Cerulean City | no | 0, 1, 3 |
| Route 4 | no | 0, 1, 3 |

The upper tier first appears in Seafoam Islands, Cerulean Cave, Victory Road,
Safari Zone and Kindle Road — all mid-to-late game.

### ⚠ CORRECTED rev 23 — the deferral window is M27A only, not "Phase 1 and 2"

The paragraph above originally concluded that *"Phase 1 and Phase 2 ship on
three terrain layers and one entity container with no compromise."* **That
used a play-order argument to justify a build-order decision, and the two do
not line up.** M27B imports all 421 maps at once, not in play order — so
Seafoam Islands, Cerulean Cave and Victory Road land in the same pass as
Pallet Town. There is no phase during which the upper-tier maps are absent
from the project.

Three further reasons the deferral is weaker than it looked:

1. **The second container is not the work — the elevation-change mechanism
   is.** A second `Node2D` is trivial. What matters is the `elevation` setter
   driving a deferred `reparent()`, and the step resolver knowing when a step
   changes elevation. Build with one container and that machinery never gets
   written; adding it later means **retrofitting into core movement code that
   is already written and tested**, which is not additive.
2. **Elevation data with no consumer is unvalidated data.** Rev 21 decided the
   importer records elevation per cell from the start. If nothing reads it,
   421 maps get imported carrying an elevation column **nobody has ever
   exercised** — and the first real test of whether the 0–15→5-bucket mapping
   is correct arrives long after the pipeline is trusted. The M27B debug
   overlay displays elevation, which is not the same as proving the movement
   semantics work.
3. **Tests encode the assumption.** This project tests from day one, and §22
   already lists chunk-seam state as a convention to design for from the
   skeleton rather than retrofit. Elevation strata are the same shape of
   problem: a suite written against a single-stratum world bakes that in.

**Corrected position:**

- **M27A (spike + walking skeleton) — one container is fine.** Pallet Town is
  0/1/3, the goal is a deliberately trivial provable slice, and there is
  genuinely nothing to reparent onto. Deferring here is real YAGNI, not
  shortcut-taking.
- **M27B (import pipeline) — build the second container and the reparent
  mechanism.** This is the pass that imports the 28 upper-tier layouts, and
  the point at which the elevation column acquires a consumer that can
  actually validate it.

So the window is one block wide, not two phases. The cost of building it at
M27B is a `Node2D`, a terrain layer and a setter; the cost of building it after
the step resolver is settled is a change to tested movement code plus
re-verification of every map imported in the meantime.

**DECIDED rev 21: the importer records elevation per cell from the start**,
even while only one entity container consumes it. Free to carry now, expensive
to backfill later.

**⚠ And it cannot ride the TileSet — elevation is per-CELL, not per-tile.**
This is a real trap, because §0's neighbouring bullet says behaviours ride on
tiles as TileSet custom data, and the obvious move is to store elevation the
same way. It does not work:

- **Behaviour** lives in `metatile_attributes.bin` — a property *of the
  metatile*. Same metatile, same behaviour, everywhere. TileSet custom data is
  exactly right.
- **Elevation** lives in the map's own blockdata (bits 12–15 of each cell's
  u16) — a property *of the position*. The same metatile can sit at different
  elevations in different places.

Measured, rather than assumed from the bit layout: across Kanto's 959 distinct
metatile ids, **500 of them (52.1%) appear at more than one elevation.**
Metatile 306 appears at all five values. So a per-tile store would be wrong for
half the tileset.

Elevation therefore needs **per-cell storage in the map resource** — a parallel
`width × height` array alongside the tile data, written by the importer and
read by the step resolver. Collision has the same shape and the same answer
(also blockdata bits, also per-cell).

**Bonus finding — collision is effectively a boolean here.** The same sweep
read the 2-bit collision field: only values **0 (passable, 46.27%)** and
**1 (blocked, 53.73%)** occur across all 216,537 cells. Values 2 and 3 never
appear in Kanto, so the collision half of each blockdata entry can be modelled
as a bool, with the same assert-on-unexpected rule.

---

**Original requirement, retained for context:**

**Required deliverable: a 0–15 → 5-bucket mapping table.** The 5-value enum was
designed for an authoring-first world where a cell's elevation is *whichever
layer you painted it on*. Imported cells don't arrive painted — they arrive
carrying a raw 0–15 value, and the importer must decide which layer each one
lands on. That table is specified nowhere today, and getting it wrong produces
maps whose bridges and underpasses are subtly unwalkable rather than obviously
broken. Build it explicitly, derive it from real Kanto blockdata (sample the
actual value distribution across the 421 maps rather than reasoning from the
constants alone), and treat it as a reviewable artifact, not an inline
constant. **[OPEN — Rob]** on the final bucket assignments once the real
distribution is measured.

### 1.6 How a GBA metatile becomes Godot tiles — M27A's real unknown *(researched rev 24)*

Formats were never the hard part of M27A. This is: **a metatile is two 2×2 tile
layers, and which of those layers draws above or below the player is decided
per-metatile by its attribute's layer-type field** (bits 29–30, the FRLG mask
from §1.2).

**Source's model.** Three BG layers, with the sprite plane **between Bg2 and
Bg1** — confirmed by `DrawMetatile`'s own comment on the NORMAL case: *"Draw
metatile's top layer to the top background layer, **which covers object event
sprites**."* Each layer type routes the metatile's two halves differently
(`field_camera.c:245-310`):

| Type | Bottom half → | Top half → | Effect |
|---|---|---|---|
| **NORMAL** | Bg2 | Bg1 | bottom below sprites, **top above** |
| **COVERED** | Bg3 | Bg2 | **both below** sprites |
| **SPLIT** | Bg3 | Bg1 | bottom below, **top above**, middle empty |

(NORMAL fills Bg3 with a garbage tile because it can never be seen under an
opaque Bg2; in Godot those cells are simply left empty.)

**Measured across all 64 FRLG tilesets — 10,895 metatiles:**

| Type | Count | Share |
|---|---|---|
| COVERED | 6,018 | 55.2% |
| NORMAL | 4,874 | 44.7% |
| **SPLIT** | **3** | **0.0%** |

SPLIT is effectively unused in FRLG — three metatiles in the entire region.
Handle it for correctness, but it is not a case worth designing around.

### ✅ This validates the three-layer decision exactly

Three source BG layers map one-to-one onto Rob's three Godot terrain layers,
with the entity container landing in the same slot the sprite plane occupies:

| GBA | Godot layer | Receives |
|---|---|---|
| Bg3 | **`Ground`** | COVERED bottoms, SPLIT bottoms |
| Bg2 | **`Objects`** | COVERED tops, NORMAL bottoms |
| — | *entity container* | player, NPCs |
| Bg1 | **`Overhangs`** | NORMAL tops, SPLIT tops |

### ⚠ CORRECTION — `Objects` must NOT be Y-sorted for imported terrain

§1.4 previously stated that `Objects` "has to be Y-sorted," calling it the one
thing that must not be got wrong. **That is wrong for imported maps**, and the
reason is worth stating plainly: **the GBA does not Y-sort tiles at all.**

The "walk behind a house" effect is not sorting — it is *authored per
metatile*. A building's upper rows use NORMAL metatiles whose top half lands on
Bg1 (above sprites); its lower rows use COVERED metatiles with both halves
below. The data already answers, cell by cell, what draws in front of the
player. Y-sorting imported terrain would be second-guessing an answer the
source already provides — and would produce *different* results from the real
game wherever the two disagree.

Y-sorting remains correct for the **entity container** (NPCs against each
other and the player) and for any **hand-authored Godot-native content** added
on top of imported maps. It is not correct for imported terrain.

### The importer algorithm this implies

1. Blockdata → per cell: metatile id (bits 0–9), collision (10–11), elevation
   (12–15).
2. Metatile → 8 tile refs: 4 bottom, 4 top, each with palette bank and h/v flip.
3. Attributes (**32-bit, FRLG**) → behaviour (bits 0–8), layer type (29–30).
4. Composite each half into a 16×16 image with its palette applied.
5. Route the halves to `Ground` / `Objects` / `Overhangs` per the table above.
6. Collision and elevation → **per-cell parallel arrays** (§1.4 — they cannot
   ride the TileSet).
7. Behaviour → **TileSet custom data** (per-metatile, where it belongs).

---

### 1.7 Collision is three systems, not one field *(researched rev 25)*

**The 2-bit collision field cannot express a ledge, and was never meant to.**
Movement permission is three independent mechanisms feeding one resolver.

**1. Collision bits** — blockdata, per-cell, 2 bits. Plain "is this cell
solid." `MapGridGetCollisionAt()` is treated as truthy/falsy, and §1.4's
measurement stands: only 0 and 1 occur in Kanto. **But "collision is
effectively boolean" was a statement about the FIELD, not about movement** —
everything directional lives elsewhere.

**2. Directional impassability** — metatile *behaviour*, per-metatile.
`MB_IMPASSABLE_NORTH / SOUTH / EAST / WEST / NORTHEAST / NORTHWEST /
SOUTHEAST / SOUTHWEST / SOUTH_AND_NORTH`. **⚠ Checked two-sided**, which is
the easiest thing here to half-implement:

```
IsMetatileDirectionallyImpassable(dir, from, to):
    gOppositeDirectionBlockedMetatileFuncs[dir-1](CURRENT tile behaviour)   // may I LEAVE?
 || gDirectionBlockedMetatileFuncs[dir-1](TARGET  tile behaviour)          // may I ENTER?
```

The two tables are mirror images: moving north checks the current tile's
*north-blocked* rule and the target tile's *south-blocked* rule — you leave via
one edge and enter via the opposite one. Implement only the entry side and it
looks correct in most of the world and wrong at exactly the places that matter.

**3. Ledges** — `MB_JUMP_SOUTH / NORTH / EAST / WEST` plus four diagonals.
These are **not blocks, they are redirects**: the resolver returns
`COLLISION_LEDGE_JUMP` and the step becomes a two-tile hop.

### The resolver returns an outcome, not a bool

`enum Collision` has **fifteen** values, and §0's "allows / denies / redirects"
phrasing turns out to be exactly right — here is the vocabulary:

`COLLISION_NONE` · `OUTSIDE_RANGE` · `IMPASSABLE` · `ELEVATION_MISMATCH` ·
`OBJECT_EVENT` · `STOP_SURFING` · `LEDGE_JUMP` · `PUSHED_BOULDER` ·
`ROTATING_GATE` · `WHEELIE_HOP` · `ISOLATED_VERTICAL_RAIL` ·
`ISOLATED_HORIZONTAL_RAIL` · `VERTICAL_RAIL` · `HORIZONTAL_RAIL` ·
`STAIR_WARP`

Ordering in `GetVanillaCollision` is load-bearing: out-of-range → impassable
(bits **or** directional **or** map border) → elevation mismatch → object
collision → none. Elevation is checked *after* solidity, so an elevation
mismatch is only ever reported for a cell that was otherwise enterable.

The expansion adds sideways stairs on top, which can **overwrite the movement
direction** (`objectEvent->directionOverwrite`) rather than allow or deny —
a fourth outcome category worth knowing exists, though nothing in Kanto's
base maps requires it.

`OW_FLAG_NO_COLLISION` short-circuits the whole function, which is §20's
"no-collision walking" debug toggle already provided for.

### Measured — how much of this Kanto actually uses

Scanned every Kanto cell whose tilesets resolved (**170,964 of 216,537, ~79%**
— the remainder had secondary tileset directories my name-mapping missed, so
treat these as lower bounds; ledges live in the primary tileset, which
resolved for every map):

| Behaviour | Cells |
|---|---|
| `MB_JUMP_SOUTH` | 911 |
| `MB_IMPASSABLE_NORTH` | 340 |
| `MB_JUMP_EAST` | 35 |
| `MB_JUMP_WEST` | 30 |

**1,316 cells, ~0.77% of the region.** Two things stand out: **`MB_JUMP_NORTH`
never appears** — you never hop *up* a ledge, so the asymmetry is real and not
an artefact — and **no diagonal jumps are used in Kanto at all**. Directional
impassability reduces to a single case, `MB_IMPASSABLE_NORTH`.

**Consequence for M27A:** the resolver needs the full outcome enum and the
two-sided directional check from the start, because they shape its signature.
But the *behaviour coverage* needed to walk Pallet Town and the early routes is
small — south ledges and one impassable direction. The long tail (rails,
boulders, rotating gates, sideways stairs) is later work and mostly maps to
already-declined scope (§28 retired rotating gates outright).

---

### 1.8 Port or re-implement? — DECIDED rev 26

**The question splits in two, and only the second half is a choice.**

**The data is not a choice.** Ledge and directional-block information lives in
the metatile attributes of the 62 FRLG tilesets being imported. Import a map
and you get `MB_JUMP_SOUTH` on specific metatiles whether you want it or not.
Re-authoring collision natively would mean hand-painting it across 421 maps —
precisely what the import-first decision (§0) exists to avoid.

**The logic is a choice, and the answer is: port the semantics, express them
natively.** Concretely:

| Port faithfully | Express in Godot idiom |
|---|---|
| The outcome enum (it is a domain concept, not a C artifact) | GDScript `enum`, trimmed to scoped mechanics but left extensible |
| The two-sided exit/entry directional rule | A `const` Dictionary of direction → blocking-behaviour set |
| `GetVanillaCollision`'s check **ordering** (load-bearing) | Sequential `if/elif` in one resolver function |
| Ledge-as-redirect, not ledge-as-block | Returned outcome the step resolver acts on |
| — | **Not** C function-pointer tables; **not** physics layers (§0) |

**This project has already made this exact call once, successfully.** Source's
pre-move cancelers are `sMoveSuccessOrderCancelers`, a C function-pointer table
with a fixed order. This project ported the *ordering and semantics* into
`StatusManager.pre_move_check` — a plain GDScript function with sequential
checks — rather than reproducing the table. The payoff showed up later: when
`[Charge-cancellation fix]` needed to know which cancelers clear an in-progress
charge, it could **diff directly against source's chain** and find that 4 of 9
branches call `CancelMultiTurnMoves`. That diff is only possible because the
semantics were ported faithfully; it would have been guesswork against a
from-scratch reimplementation.

**Why not re-implement the rules natively.** The data is authored *for* these
rules. Re-deriving them means reconstructing decisions someone already made
correctly, against inputs that assume the original model — and any divergence
is **silent**: a mis-derived directional rule does not crash, it just makes one
fence walkable somewhere in Kanto, discovered by a player rather than a test.
That is the exact failure shape §0's Step 0 rule exists to prevent, and this
file's history is a long record of improvisation losing to porting.

**Scope note:** implement the outcomes the scoped mechanics need — `NONE`,
`IMPASSABLE`, `ELEVATION_MISMATCH`, `OBJECT_EVENT`, `LEDGE_JUMP`,
`STOP_SURFING`, `STAIR_WARP`, `PUSHED_BOULDER` (Strength, M27E). Leave the enum
open so the declined ones (rotating gates — §28; rails; wheelie hops) can be
added without touching the resolver's signature.

---

### 1.9 Hand-authoring on top of imported maps *(measured rev 28)*

"Import first, author tweaks after" (§0) was a decision; this is what it costs
to implement, and it changes two things in M27B.

**The measurement that forces it.** Across all 421 maps / 230,619 cells:

| Property | Varies by placement | Can a painted tile carry it? |
|---|---|---|
| **Collision** | **52.0%** of metatiles | **No** |
| **Elevation** | **52.1%** of metatiles | **No** |
| Behaviour | 0% — per-metatile by construction | **Yes** |

A per-metatile collision *default* would mis-set **29,827 of 230,619 cells
(12.93%)**. So "paint a tile and infer its collision" is not a viable
shortcut — the same metatile is genuinely solid in one place and walkable in
another. Painting gives you the art and the behaviour free; collision and
elevation must still be set for the cell.

**⚠ And in the M27A proof of concept, hand-painting is silently destroyed.**
`pallet_town.gd::_paint()` writes every cell from JSON at `_ready()`, so
anything painted in the editor is overwritten the moment the scene runs, with
no warning. That is fine for a skeleton whose only job was proving the import;
it is not a shape to build authoring on.

#### Change 1 — bake tiles into the `.tscn` at import time

The scene becomes the artifact and the JSON becomes a build *input* rather than
a runtime one. Painting is then just editing the real scene, which is what
"author tweaks after" has to mean in practice. Cheap to do now with one map;
steadily more annoying across 421.

#### Re-import policy — per-map, refuse-unless-forced, no merge *(decided rev 29)*

Baking tiles into the scene reintroduces the destruction problem one level up:
a generated-and-then-hand-edited scene is clobbered by rerunning the importer
on it. **But re-import is per-map, not bulk**, which collapses the problem —
it is a usage question, not an architecture one. You re-import the map you mean
to, and authored maps simply are not in that set.

So: **no merge machinery.** A three-way merge keyed on provenance was designed
and then dropped as solving a problem that only exists if re-import is
all-or-nothing.

**What is kept is the cheap guard**: the importer refuses to overwrite a map
containing any `AUTHORED` cell unless `--force` is passed. ~5 lines, no merge
logic, and it converts "silently destroyed your afternoon" into "importer
declined; pass --force if you meant it." It reads the provenance field Change 3
requires anyway, so it costs nothing extra.

**Why re-import will happen at all, rarely:** four importer bugs surfaced in
M27A/M27B alone — the naive lowercase directory guess, `gTileset_BuildingFrlg`
→ `gMetatiles_Building_Frlg`, SilphCo borrowing its graphics from
Condominiums, and an output-filename change that broke two consumers. A fifth
is likelier than not, and when it lands the affected maps get re-imported —
most of which will never have been hand-touched.

**Still open at implementation time**: cells authored *outside* the source
map's bounds (extending a map edge) have no source counterpart, so
refresh-vs-preserve does not apply. Either always preserved, or resizing an
imported map is disallowed. Leaning always-preserved.

#### Generated vs tracked output *(settled rev 29)*

Two directories, split on whether the artifact is a runtime dependency:

| Path | Git | Why |
|---|---|---|
| `assets/maps/` | **ignored wholesale** | 421 per-map JSON plus `_preview`/`_above` validation renders. All regenerable; ignored as a *directory* so a new kind of generated output cannot quietly start being tracked |
| `assets/map_atlases/` | **tracked** | Shared per tileset PAIR — **60 pairs for 421 maps**. Real runtime dependencies of tracked scenes, and Godot convention is to commit texture + `.import` |

The shared-atlas layout is a **7x reduction**: 180 PNGs (360 files with
sidecars) instead of 1,263 (2,526). `gTileset_BuildingFrlg +
gTileset_GenericBuilding2` alone backs 51 maps, so per-map atlases would have
stored that byte-identical image 51 times. Nearly free to adopt because
`get_tileset()` already cached by pair — only the *filenames* were per-map.

#### Change 2 — the debug overlay becomes an editor, not just a viewer

§20 scoped it as a validation surface for *reading* behaviour and elevation.
Given the measurement above it must also be where collision and elevation are
*set*, because nothing else in the pipeline can infer them for a newly painted
cell. Without this there is no way to author a walkable house at all.

#### Change 3 — defaults are offered, and visibly marked as defaults

Inheriting collision and elevation from the cell painted over — or from the
metatile's most common value — is right **~87%** of the time. That makes it a
genuinely useful authoring assist and a genuinely dangerous silent behaviour:
the remaining **13%** would be wrong in a way nobody can see.

So the overlay must distinguish **defaulted** cells from **explicitly set**
ones, and the map format needs somewhere to record which is which. This is a
data-shape requirement, not just a UI one — it cannot be retrofitted onto a
format that only stores final values, which is why it belongs alongside
Change 1 rather than after it.

---

### 1.5 Remaining

- **Tile animations** — Animated terrain (water, flowers, waterfall) via
  TileSet atlas animation frames; synced by default. Stateful tiles (doors
  opening, cracked floor breaking) are objects or `set_cell` swaps, not tile
  animations.
- **Cross-map rendering** — With stitching, adjacent-map objects/NPCs are
  visible across boundaries; per-map TileMapLayers slot into the shared global
  layer stack.
- **Border blocks** — Skirt strip painted by the loader on unconnected edges;
  impassable, visually seals map edges so void never shows. Per reference:
  border is a hardcoded 2×2 block on Emerald, while `borderWidth`/
  `borderHeight` are real `MapLayout` fields alongside `isFrlg` — relevant
  since target is Kanto, and `layouts.json` exposes both per layout.

---

## 2. Map Events (the four types)

- **Object events** — NPCs, item balls, cuttable trees, Strength boulders;
  anything with a sprite and behavior. Spawn data: cell, elevation, sprite,
  movement type, script, visibility flag. Already present in every `map.json`
  alongside the header/connection data the importer reads, so import cost is
  near zero even though the *content* (who says what) is authored.
- **Warps** — Doors (with open/close animation), stairs, cave entrances; paired
  warp destinations. Warps belong here with the other event types, not with map
  geometry — the destination is data, but the presentation is decided by the
  metatile behavior at trigger time (§12).
- **Coord events (triggers)** — Step-on tiles that run scripts: rival ambushes,
  cutscene starts, forced encounters.
- **BG events** — Signs, hidden items, and interactable furniture (PC, TVs,
  bookshelves) bound to tiles.

---

## 3. Map Scripts & Hooks

Reference has **seven** hooks, not four:

- **On-load** — Runs before render; dynamic tile changes (e.g., opened doors,
  altered terrain).
- **On-transition** — Runs on map entry; sets ambient weather, respawn logic,
  per-visit state.
- **On-resume** — Fires on *every* return to field (closing the bag, finishing
  a battle, exiting a menu). Heavily used in reference; this is the natural
  hook for post-battle application (see §17).
- **On-return-to-field** — Related return-path hook; distinct from on-resume in
  reference.
- **On-dive-warp** — Dive/emerge transitions.
- **On-frame (table)** — Var-conditional *dispatch table* (`{var, value,
  script}` entries), not a plain callback; drives entry cutscenes once
  conditions are met.
- **On-warp-into (table)** — Also a var-conditional dispatch table; positions/
  faces the player or objects on arrival.
- **Stitching interaction** — Decide when "map entered" hooks fire under
  seamless connections (border-cross vs. warp).

---

## 4. NPCs / Object Events

- **Movement types** — Wander, patrol paths, look-around, face-direction,
  walk-in-place; all grid-step based, sharing the player's step resolver.
- **Visibility flags** — Show/hide objects based on event flags (defeated
  trainers, story-removed NPCs).
- **Trainer sight & approach** — Per reference: a **one-tile-wide straight line
  along the facing axis** — no cone, no radius, no diagonals (diagonal-facing
  trainers are blind). Detection priority is object-ID order, not proximity.
  Exclamation mark, approach walk, then battle.
- **Trainer battle variants** — Single vs. double trainer battles from the
  overworld; defeat flags; rematch support.
- **Trainer sprite assets** **[carry-in]** — **86 Kanto/FRLG trainer front pics
  are identified but deliberately unpulled.** The pull itself is a trivial flat
  copy (same shape as the original `gen_trainer_portraits.py` run — no decode,
  no conversion); it was deferred because the sprites are vocabulary for
  trainers that do not exist yet. Pull them at the point the Kanto trainer
  roster is actually authored, not before. Several are Kanto-exclusive classes
  with no Hoenn equivalent (Channeler, Burglar, Cue Ball, Biker) plus the Kanto
  Elite Four.
- **Entity attachments** — Shadows, reflections, grass-rustle effects as
  children of the entity so they sort as one unit.
- **Polish effects** — Water/ice reflections, grass rustle, sand footprints,
  dust clouds (deferrable).

---

## 5. Player Movement

- **Grid step resolver** — Step request → behavior/elevation/occupancy check →
  allow, deny, or redirect; tween executes the visual move; landing applies
  tile consequences (elevation change, encounter roll, trigger fire).
- **Gaits** — Walk, run (running shoes flag, running indoors toggle), bike(s);
  input buffering and quick turn-in-place for feel.
- **Surf / dive / waterfall** — Water traversal states with their own sprites
  and movement rules; surf mounts/dismounts across the water/ground elevation
  boundary.
- **Forced movement** — Ice sliding, ledge hops, currents, muddy slopes, spin
  tiles.
- **Fishing — a configurable subsystem, not one flow** *(expanded rev 11)* —
  `include/config/fishing.h` exposes: **per-rod bite odds that differ by
  generation** (`I_FISHING_BITE_ODDS`, at GEN_LATEST Old 25% / Good 50% /
  Super 75% — the *inverse* of the Gen 1/2 ordering); **a real reeling
  minigame** (`I_FISHING_MINIGAME`, defaulting to the Gen 3 variant, with only
  the Gen 1/2 and Gen 3 versions implemented upstream) — this is an interactive
  input sequence, not a dice roll, and rev 10 did not account for it;
  `I_FISHING_ENVIRONMENT` (Gen 4+ picks the battle backdrop from the tile being
  fished *into*, not the one the player stands on); and
  `I_FISHING_STICKY_BOOST` (**Suction Cups or Sticky Hold in party slot 1
  doubles base bite chance** at GEN_LATEST — a lead-ability effect belonging
  with the §11 cluster). Default-off extras: chain fishing (shiny odds),
  proximity bonus, time-of-day bonus, follower-friendship bonus.
- **Overworld poison** — `field_poison.c` plus `OW_POISON_DAMAGE`. At
  GEN_LATEST poisoned Pokémon take **no overworld damage at all** (Gen 4
  stopped them fainting; Gen 5+ stopped the damage). Recorded so its absence
  reads as the deliberate config outcome it is, rather than an oversight.
- **Per-step field tasks** — `field_tasks.c` runs a per-step callback slot for
  map-specific terrain: ash grass, submerging log bridges, ice-sliding puzzles,
  cracked floors that break underfoot, muddy slopes. The step resolver needs a
  hook for this class of "landing on this tile mutates the map" behaviour; §1's
  behaviour list names the tile types but not the mechanism that drives them.
- **Escalators — IN, low priority** *(decided rev 12)*. `fldeff_escalator.c`
  is 242 lines and matters for Kanto specifically (Celadon's department store).
  Small, self-contained, no dependencies; land it whenever the department store
  is authored. **Rotating gates** (`rotating_gate.c`, 1,031 lines) moved to
  §28 nice-to-haves — Hoenn puzzle furniture, nothing in Kanto needs it.
- **Field-move badge gating — adjustable at any time, not a gate on anything**
  *(resolved rev 12)*. Confirmed by reading `src/field_move.c` (233 lines
  total): each field move's unlock is a **one-line function** returning
  `FlagGet(FLAG_BADGEnn_GET)`, with an `IS_FRLG` ternary picking which badge —
  e.g. Cut is Badge 2 on FRLG vs Badge 1 on Hoenn, Flash is the mirror image,
  Rock Smash is Badge 6 vs Badge 3. **Nothing in map data, tilesets or
  blockdata encodes any of it**, so importing maps neither locks nor
  constrains the assignment. **DECIDED rev 13: port the FRLG mapping exactly**,
  and re-map later as the story's badge order develops. Deliberately not
  "approximately FRLG" — an exact port means any later change is a visible,
  intentional edit against a known baseline rather than a drift nobody can
  date. This is a content decision made late, not a port decision made early.
- **Field moves** — Reference defines 16, 14 live by default (Rock Climb and
  Defog config-gated off). Badge gating differs between Hoenn and FRLG
  (Cut/Flash and Rock Smash/Fly swap); **take the FRLG assignment as the
  starting point** — and see the badge-gating note below, which establishes
  that this is freely re-mappable later rather than a decision to make now.

---

## 6. Scripting & Dialogue Engine

> **Its own milestone, not a section — under-scoped here by roughly an order of
> magnitude, and pulled out for a dedicated scoping session.** Reference: ~230
> live script opcodes, 393 macros, ~620 special C functions of which ~421 are
> actually called across ~2,090 call sites, 168 applymovement action macros (a
> second embedded language), and 3 native escape hatches. Porting opcodes buys
> control flow and little else — *the in-scope specials list is the game*.
> There is no generic "run a shop" opcode; marts, daycare, etc. each hand off
> to bespoke code. Realistically 30–40% of total overworld work. Treat the
> bullets below as a placeholder until the specials scoping session produces
> its own document. **Exact opcode counts need reconciling first — see §22.1.**

### 6.1 Dialogue Manager — what it actually gives us *(researched rev 13)*

**Version 3.10.2, enabled as an editor plugin *and* registered as an autoload**
(`project.godot:25`). Two facts reframe the §0 boundary:

**It currently has zero live consumers.** The only references to it anywhere in
project code are comments describing the *retired* `LogLabel` — M26A2 retired
the `DialogueLabel`-based battle log, and no `.dialogue` file has ever been
authored. The approved dependency is dormant: it costs nothing today, and it
does nothing today.

**It is much more than a message box.** Real, shipped capability:

- `DialogueLine.character` — **a native speaker field**, with
  `get_resolved_character()` interpolating game state into it.
- **Conditions** — lines gated on evaluated expressions.
- **Mutations** — `_mutate()` resolves an expression against a `game_states`
  array (autoloads plus any objects passed in), supporting **method calls,
  assignment, and `await` for blocking mutations**, plus built-in `wait`/`debug`.
- **Responses** (choice menus), **jumps** (`next_id`), tags, per-line speed
  overrides, concurrent lines, inline mid-line mutations, translation keys.
- The expression layer is a genuine little language: variables, comparisons,
  assignment, function calls, dictionaries, arrays, dot access, null
  coalescing, grouping, negation.
- `DialogueLabel` supplies typewriter output with a per-letter `spoke` signal,
  a skip action, automatic pauses at `.?!` with abbreviation exceptions, and
  configurable speed.

**Consequence — §0's boundary is drawn in the wrong place.** §0 says the field
script engine owns "movement scripting, give/take, warps, battle calls, and the
specials inventory." But give/take and battle calls are precisely what a DM
*mutation* is: a method call on an autoload. The line that actually holds is
about a script's **spine**, not its verbs:

- **DM owns scripts whose spine is a conversation** — talk → check a flag →
  give an item → set a flag → say a line. That is most NPC interaction in the
  game, and DM can drive all of it including the branching.
- **The field script engine owns scripts whose spine is choreography** —
  applymovement sequences, camera pans, mid-scene warps, timed cutscenes. DM
  has no vocabulary for these and should not grow one.

**DECIDED rev 14 — DM is the RPG side's dialogue engine; the simulator stays
plain.** The split is along product lines, and it resolves cleanly because the
two sides genuinely have different needs:

- **RPG side — DM's job.** Lean on it properly: conversational branching,
  conditions, responses, and mutations calling into engine systems. This is
  where its expression layer earns its keep, and it meaningfully shrinks §6's
  specials inventory, because a script whose spine is a conversation never
  needs a bespoke opcode.
- **Battle simulator side — stays simple.** Minimal dialogue, no branching, so
  it keeps the project's own message pipeline: `MessageLabel` (a plain
  `RichTextLabel`) driven by `_run_message_pacing()`'s `visible_ratio` tween at
  `_TEXT_REVEAL_SECONDS_PER_CHAR`, fed by the `_pending_beats` queue. Already
  built, already tuned, no dependency.

**Worth recording precisely, because the history is easy to misread:** DM is
not an unused dependency — it is a *superseded* one. M23.11 Phase 4e genuinely
used it, retyping the battle log's `LogLabel` from `RichTextLabel` to DM's own
`DialogueLabel` for a real typewriter reveal over real GBA `text_window` art.
M26A2 then retired that log outright (node deleted, `_setup_message_box()`
deleted) when it merged into the F3 debug overlay, and the message-pacing work
rebuilt the typewriter natively. So DM's former job is gone and rebuilt; rev
14 gives it a genuinely new one on the RPG side rather than resuming the old.

### 6.2 Engine components

- **Script engine core** — Coroutine driver: commands, contexts, conditional
  branches on flags/vars, and calls out to engine functions (our equivalent of
  the reference's C specials — cheap in GDScript, but the *inventory* still
  needs deciding).
- **Specials inventory (to scope)** — Decide which of the ~421 used specials
  are in scope; group by subsystem so exclusions (contests, secret bases, Match
  Call) drop whole clusters.
- **Message boxes** — Delivered by the Dialogue Manager plugin: display, speed,
  styles, colors. Note: reference's MSGBOX_* "types" are indices into a table
  of scripts written in the script language itself, not opcodes.
- **Text buffers & control codes** — Player/Pokémon/item/number interpolation
  via DM variables. Reference has two independent placeholder namespaces (15
  field, 72 battle) plus ~29 inline control codes with varying operand arity,
  expanded recursively — a real component, not a formatting detail.
- **Choices** — Yes/no prompts and multichoice menus (dynamic multichoice), via
  DM where it fits.
- **Movement scripting** — applymovement-style scripted NPC/player movement
  during cutscenes, expressed in tile steps (fits grid-locked decision).
- **Give/take commands** — Items, Pokémon, money, badges granted or removed by
  script.
- **Battle calls** — Script-initiated wild and trainer battles: single, double,
  sight-triggered, scripted-loss variants.

---

## 7. Camera & Screen Effects

- **Scripted camera** — Camera detaches from player for pans during cutscenes,
  then returns.
- **Screen effects** — Shake, flash, fade to black/white and back;
  fade-through-warp transitions.

---

## 8. Flags & Vars

- **Event flags** — One-shot state: item balls collected, hidden items found,
  one-time NPC interactions.
- **Trainer flags** — Per-trainer defeated state.
- **System flags** — Badges, visited locations, unlocked features.
- **Story vars** — Integer state machines driving story progression and
  cutscene sequencing.
- **Temp flags/vars** — Reset on map load; scratch state for scripts.
- **Daily flags** — Reset on day rollover for daily events (requires time
  system).

---

## 9. Time & Day/Night (decided: in)

- **Clock architecture (decided)** — Accelerated fake game-time. Note this is a
  *shipped reference feature*, not just a pattern: `OW_USE_FAKE_RTC`,
  `OW_ALTERED_TIME_RATIO` (60× / 20×), `OW_FLAG_PAUSE_TIME`, persisted in
  SaveBlock3 — port rather than invent.
- **Day/night tint** — CanvasModulate color sampled from a Gradient keyed to
  hour; UI on a separate CanvasLayer stays untinted; interiors skip via outdoor
  flag; PointLight2D lamps/windows punch through at night. Full-screen shader
  (blue-shift/LUT) remains an optional upgrade.
- **Time buckets** — **Four**, not three: morning / day / evening / night
  (TIME_EVENING is real and default-active). Boundaries are config-switched
  across six generational variants (default 6/10/19/20).
- **Daily events** — Lotteries, berry masters, daily flag resets.
- **Time-based evolutions & forms (deferred)** — Now supportable given the
  clock; formal in/out decision deferred to evolution scoping, alongside the
  standing trade-evolution question.

---

## 10. Weather

- **Overworld weather per map** — Rain, thunderstorm, snow, sandstorm, fog,
  drought, underwater.
- **Scripted weather changes** — Script command to change weather mid-map for
  story events.
- **Battle carryover** — Overworld weather sets battle-start weather.
- Note: the battle-side weather visual system (M26B4) is already built and is
  driven by battle state, not by a persistent renderer — there is no field
  weather renderer running during a battle to hand off to.

---

## 11. Encounters (Kanto data is IN and imported)

- **Per-map encounter tables — IMPORT KANTO** *(settled rev 10)* — Grass,
  water, rock smash, and per-rod fishing tables with encounter rates; checks
  roll per landed step (grid-locked makes "step" unambiguous). **Verified:
  `wild_encounters.json`'s `gWildMonHeaders` group holds 388 entries, of which
  264 are `REGION_KANTO`** (124 Hoenn), spanning 124 unique Kanto maps —
  Viridian Forest, Mt. Moon, Diglett's Cave, Cerulean Cave, Rock Tunnel and the
  rest. Kanto's encounter maps are named plainly rather than `_FRLG`-suffixed
  (only 4 entries carry that suffix), which is why a naive suffix filter makes
  the dataset look Hoenn-only — it is not. Real caveat that still stands: the
  repo's own copy is a verbatim reference copy that **nothing loads** (excluded
  from the data pipeline), so the pipeline work is real even though the content
  is largely there. `hidden_mons` has a struct field and no map data.
- **Encounter modifiers** — Two distinct mechanics, per reference: **level
  gating** (Repel, Keen Eye, Intimidate — these do *not* change encounter rate)
  vs. **rate scaling** (bike, flutes, Cleanse Tag, lures, rate abilities). Plus
  species-biasing abilities (Static, Magnet Pull, Sticky Hold) and Sweet Scent.
  Repel keeps the B2W2 re-use prompt. Note the Repel effect is also reachable
  as a **held item on the lead** (`HOLD_EFFECT_REPEL`, `wild_encounter.c:1169`),
  not only as a used consumable.
- **⚠ Lead-Pokémon ability modifiers — seven of them, and ON by default**
  *(new rev 11)* — an entire Gen 8+ cluster rev 10 never listed, all resolving
  to active at this project's `GEN_LATEST` config and all keyed on the ability
  of the **party leader**, not a battler:

  | Config | Effect when the lead has it |
  |---|---|
  | `OW_SYNCHRONIZE_NATURE` | Synchronize forces the wild Pokémon's nature **always**, not the older 50% |
  | `OW_INFILTRATOR` | Encounter **rate halved** |
  | `OW_SUPER_LUCK` | Wild **held-item rate raised to 60%/20%** |
  | `OW_HARVEST` | 50% chance the encounter is **Grass-type** |
  | `OW_LIGHTNING_ROD` | 50% chance **Electric-type** |
  | `OW_STORM_DRAIN` | 50% chance **Water-type** |
  | `OW_FLASH_FIRE` | 50% chance **Fire-type** |

  Confirmed live in `wild_encounter.c` (the type-biasing four share a
  `TRY_GET_ABILITY_INFLUENCED_WILD_MON_INDEX` macro applied to both land and
  water tables; Infiltrator branches separately at `:613`). Add
  `I_FISHING_STICKY_BOOST` from §5 and this is **eight lead-ability hooks**
  encounter generation has to consult. **DECIDED rev 17: all eight OUT.**
  Encounter generation consults no lead-ability hooks at all. Recorded rather
  than deleted so a future session sees they were considered and declined —
  and so nobody "restores" one of them piecemeal on the grounds that it is
  default-on upstream.
- **Wild-battle configuration cluster** *(new rev 11)* —
  `include/config/wild_encounter.h` also exposes: `WE_DOUBLE_WILD_CHANCE` (a %
  chance any encounter is a double, with `WE_DOUBLE_WILD_REQUIRE_2_MONS`
  guarding the one-usable-Pokémon case); **`WE_WILD_NATURAL_ENEMIES`, on by
  default — certain species attack each other when paired in a double wild
  battle** (Zangoose/Seviper being the canonical pair), a real mechanic with no
  equivalent here; `WE_SMART_WILD_AI_FLAG` (a flag that gives wild Pokémon the
  full trainer AI flag set); and flag-driven global disables for encounters,
  catching, and running — the last of which also makes Roar/Whirlwind and
  Teleport fail. The disable flags cover §11's own "encounter/battle disable
  flags" bullet and are worth porting as flags rather than as ad-hoc booleans.
- **Roaming Pokémon system** — Dedicated roamer state: current map, movement on
  map changes, HP/status persistence between encounters.
- **Time-of-day encounter tables — OUT for now, see §28** *(decided rev 12)*.
  The feature exists in reference but ships **zero data**
  (`OW_TIME_OF_DAY_ENCOUNTERS` defaults FALSE), so it is authoring from
  scratch rather than a port. Cleanly additive later — the tables are a
  separate lookup keyed on the §9 time bucket, not a change to encounter
  dispatch — so nothing is lost by deferring it.
- **Static & scripted encounters** — Fixed legendaries/gift encounters launched
  by script.
- **Shiny Pokémon** **[carry-in]** — rolled at Pokémon-creation time, so it
  belongs to encounter generation, not battle display.
  `TrainerPartyMon.is_shiny` is already parsed from real trainer data, but
  `BattlePokemon` has no equivalent field, no shiny sprite/palette variant ever
  loads, and source's `TryShinyAnimation` (the send-out sparkle) has no
  equivalent. A `shiny.png` sparkle overlay already sits unused in two vendored
  asset packs. The display-side consequence (sprite variant + sparkle on
  send-out) lands in §17.
- **Double wild battles** — 2v2 wild support triggered from overworld context.
- **Encounter/battle disable flags** — Global toggles disabling wild encounters
  or trainer battles (dev + design uses).

---

## 12. Warping & Travel

- **Warp execution** — Fade-out, reposition, fade-in; door animations.
  Correction: warps are **not typed** in map data (no door/stair/cave field).
  Behavior is selected by the **metatile behavior at trigger time** — reference
  has 16 distinct warp paths plus a script-based hole. Warp scenes carry
  destination only; the tile decides the presentation.
- **Fly / Escape Rope / Dig / Teleport** — Long-range travel with destination
  rules.
- **Heal-spot memory** — Last Pokémon Center recorded for whiteout respawn.
- **Whiteout flow** — Party wipe → money loss calculation → message
  (FRLG-style) → respawn at heal spot. **Plus a cutscene, at this config**
  *(new rev 11)*: `OW_WHITEOUT_CUTSCENE` is `GEN_LATEST`, so Gen 4+ behaviour
  applies — an **additional message and a post-whiteout event-script scene
  with a healing NPC**, not a bare fade-and-respawn. It is a scripted sequence,
  so it depends on §6 existing.
- **Map preview screen** *(new rev 11, see §26)* — warping into a landmark map
  can play an FRLG-style preview card before the map appears. Relevant here
  because it sits *inside* the warp transition, not beside it.

---

## 13. Field Items & Money

- **Item balls** — Visible pickups tied to flags.
- **Hidden items** — Flag-tied invisible pickups + Itemfinder/Dowsing mechanic.
- **Pickup descriptions** — Obtained-item description text on pickup (QoL).
- **Money** — Earn/spend/lose; whiteout deduction.
- **Berry trees (deferred, likely out)** — Plant/water/growth stages; XY
  mechanics (mutations, moisture, weeds, pests) out regardless. Decision
  deferred, leaning cut.

---

## 14. Shops / Marts

- **Buy flow** — Mart inventory lists, quantity select, money deduction.
- **Sell flow** — Sell at half price from bag.
- **Specialty marts** — TM shops, herb shops, department store floors.
- **Premier Ball bonus** — Bonus ball per 10 Poké Balls purchased.

---

## 15. NPC Services

- **Move relearner / deleter / tutors** — Overworld NPCs hooking into learnset
  and moveset APIs.
- **Name rater** — Nickname editing service.
- **IV judge / happiness checker** — NPCs surfacing hidden stats.
- **Day Care access point** — Overworld interface to deposit/withdraw (breeding
  logic separate).

---

## 16. Menus & Overworld UI

- **Start menu** — Root pause menu.
- **Party menu (field context)** and **Bag** — **real full-screen Bag and Party
  views already exist** **[carry-in]**: M25h-1.4 and M25h-1.5 built both as
  genuine separate screens (real screen-swap architecture, real window art,
  real fonts, real per-row HP bars/status icons/held-item icons, real
  forced-replacement flow). These are a **head start, not a rebuild** — the
  field-context work is adding field-move dispatch, item use outside battle,
  and real inventory/quantity data behind the Bag, not building the screens.
- **Trainer card** — Player info, badges, playtime. Depends on the player
  identity item in §0.
- **Options — the reference's own menu is exactly six items** *(enumerated rev
  14 at Rob's request; `src/option_menu.c`, all persisted in SaveBlock2 as a
  bit-packed `u16` plus one `u8`)*. **[OPEN — Rob]** which to include:

  | Option | Values | Decision (rev 15) |
  |---|---|---|
  | **TEXT SPEED** | Slow / Mid / Fast | **IN.** Near-free — maps onto `_TEXT_REVEAL_SECONDS_PER_CHAR`, already a tunable constant |
  | **BATTLE STYLE** | Shift / Set | **IN.** Whether the player is offered a switch when the opponent sends out a new Pokémon. Touches real battle logic, not presentation |
  | **FRAME** | 1 of 20 borders | **IN** — already scoped as M26C6, so effectively free once that lands |
  | **BATTLE SCENE** | On / Off | **OUT.** Would have meant skipping animation beats out of `_pending_beats` without desyncing the queue — real work, and §16.1 covers the intent better |
  | **BUTTON MODE** | Normal / LR / L=A | **REPLACED** by a Godot-native control-remapping option. GBA-specific as written; a desktop build wants real rebindable actions |
  | **SOUND** | Mono / Stereo | **Deferred with audio** (§18) — nothing to configure until audio exists |

  **Plus one original option with no reference equivalent: a universal
  in-battle speed multiplier** — see §29.

  Worth noting what the reference *doesn't* offer, since a modern build might
  be expected to: no difficulty selector (difficulty is a var, never a menu
  item — so §29's RPG difficulty options are original UI with no layout to
  copy), no text-size or accessibility settings, no autosave toggle, no
  control remapping, and no battle-speed control.

- **Save UI** — Save prompt and confirmation.
- **Region map UI** — Town map with location name popups; Fly destination
  selection; Pokédex area pages highlighting habitats from encounter tables.
- **Summary screen** *(new rev 11, elaborated rev 12)* — the multi-page
  per-Pokémon detail view reached from the party menu, `pokemon_summary_screen.c`,
  **4,886 lines**. Rev 10 listed no summary screen at all despite every
  party-menu flow reaching one. Four pages in reference, navigated with L/R,
  with up/down cycling party members:
  - **INFO** — species, dex number, types, OT name and ID, held item, nature,
    met location/level.
  - **SKILLS** — the six stats, current EXP, EXP to next level, ability name
    and its description text.
  - **BATTLE MOVES** — all four moves with type, power, accuracy and PP, plus
    per-move description text; also where moves are reordered and forgotten.
  - **CONTEST MOVES** — contests are OUT (§24), so **three pages, not four**.

  This is the only place a player ever sees stats, nature, ability text and
  move details — all of which this project's battle engine already computes and
  none of which is currently surfaced anywhere. **DECIDED rev 12: build it once
  and reuse it.** M26E4 owns an unbuilt battle-context Summary/Stats screen;
  the same screen serves both, and building two would be the only way to get
  this wrong.

  **DECIDED rev 13 — build the three real pages exactly, and keep the fourth
  slot.** Reproduce INFO / SKILLS / BATTLE MOVES faithfully rather than
  redesigning them, and **retain the page-4 position as an optional slot** in
  case Rob later wants alternate information where Contest Moves used to sit.
  Concretely that means the page container, the L/R cycling, and
  `maxPageIndex` stay parameterised over a page *list* rather than hardcoded to
  three — the reference already works this way (`sTextPrinterFunctions[]` and
  `sTaskFunctions[]` are indexed by page enum), so keeping the seam costs
  nothing now and avoids a refactor if the slot is ever filled. Ship with the
  slot empty and page count 3.
- **PC box storage** *(new rev 11)* — `pokemon_storage_system.c` is **10,137
  lines, the fourth-largest file in the source tree**. Rev 10 mentioned the PC
  only as a piece of BG-event furniture. CLAUDE.md's M33 owns the system, but
  a document that otherwise spans M27–M35 should carry its real size, because
  it is a milestone on its own and its config surface (`OW_PC_*`) already
  encodes five behavioural decisions — deposit-healing, release-with-item,
  menu ordering, B-button semantics, and the Walda wallpaper icons.
- **The player's own bedroom PC — CUT** *(decided rev 12)*. `player_pc.c`
  (1,473 lines) is a separate system from box storage: the PC in the player's
  bedroom, holding item storage and a mailbox. Mail is already OUT (§24), and
  Rob's call is to drop the bedroom terminal entirely and keep **one** PC —
  the standard Pokémon Center terminal — covering box storage and whatever
  else that menu needs. One PC, one place, no duplicate item-storage concept.

---

## 17. Overworld ↔ Battle Glue

- **Battle-return contract (unbuilt half — specify before menu/battle wiring)**
  — `BattleSetupContext` already handles injection *into* battle; the return
  path is unspecified. Define an explicit **results object** the battle emits
  and the *overworld applies* — never the battle engine mutating save state
  directly. Contents: HP/PP/status deltas, EXP and level-ups, evolution
  triggers, consumed items, caught Pokémon, money delta, EV gains, stat-counter
  bumps. This one rule is also what keeps simulator battles off the save file
  (§21): sim mode routes the same results object to its own pool or discards
  it. Natural application point is the on-resume map hook (§3).
- **Battle environment selection** — Map/terrain determines battle backdrop and
  player/enemy base graphics.
- **Battle transitions, incl. the Mugshot effect** **[carry-in]** — the
  overworld→battle wipe animations. `B_TRANSITION_MUGSHOT` is the Gym-Leader/
  Elite-Four entry animation, selected by `GetTrainerBattleTransition()` only
  when `DoesTrainerHaveMugshot(trainerId)` passes; ordinary trainers fall
  through to faction-specific and generic transitions. **It uses no dedicated
  portrait asset** — it scales and rotates the same 64×64 trainer front pic the
  battlefield sprite uses, across coloured diagonal banners driven by an HBlank
  scanline effect, with five per-trainer palette variants plus a player-gender
  palette. This closes the question of whether a "portrait" concept exists
  anywhere in the reference: it does not. There are exactly two trainer-sprite
  uses, both the same 64×64 front pic.
- **Trainer intro presentation** — Per-class encounter music and intro
  slide-in. (The in-battle half — sprite entry/exit, throw animation,
  send-out — is already built as M26B3.)
- **Shiny display side** **[carry-in]** — sprite variant plus the send-out
  sparkle, consuming whatever §11's encounter generation rolls.
- **Per-ball send-out particle animations** **[carry-in]** — the eight
  non-Poké-Ball particle variants. Only the Poké Ball's is built; the rest are
  unreachable until ball variety exists, i.e. until catching lands. Fully
  researched and tabulated already (nine distinct `particleAnimationFunc`s plus
  a per-ball `animNums` frame selector) — do not re-derive. Cosmetic depth,
  sequence late.
- **Post-battle return** — Restore overworld state, apply defeat flags, run
  post-battle scripts.

### 17.2 Scripted partner double battles — real cost *(assessed rev 18, DECIDED IN)*

Three pieces, in ascending order of cost. Only the third is substantial.

**1. Control granularity — small.** Both `BattleManager._human_controlled`
(`Array[bool]`, `:566`) and `_trainer_ais` (`Array`, `:523`) are indexed **by
side**. A partner battle needs the player's side half-human, half-AI, so both
must become per-combatant. That is two declarations, two setters, and roughly
five read sites. **Keep the existing `set_human_controlled(side, …)` /
`set_trainer_ai(side, …)` as fan-out wrappers** that apply to every combatant
on that side — every existing test calls the side-level form, so this stays a
zero-churn change.

**2. Branch ordering — a real trap, not a detail.** In `_phase_move_selection`
the AI branch (`elif _trainer_ais[side] != null:`) is evaluated **before** the
human branches. So making only `_human_controlled` per-combatant is not enough:
with an AI attached to the player's side, the AI branch would claim *both*
slots and the human would never get a turn. Both arrays have to move together.

**3. The party model — the actual cost, and it is a design decision.** The
reference gives the partner **its own party**: `ZeroPartyMons(gParties[B_TRAINER_PARTNER])`,
filled from `gBattlePartners[difficulty][id].party`, sized `MULTI_PARTY_SIZE`
rather than `PARTY_SIZE` unless `AreMultiPartiesFullTeams()`. That is
`BATTLE_TYPE_MULTI` — two independent parties on one side.

This project's doubles model is **one `BattleParty` per side** with
`active_indices` holding two entries (M14a). Those are different shapes. Two
ways out:

- **A second `BattleParty` on the player's side** — closest to source, and the
  switching rules fall out correctly (the player cannot switch the partner's
  Pokémon, because it is not in their party). Costs a change to `_parties`,
  which is currently a flat `[player, opp]`.
- **One merged party with per-member ownership tagging** — cheaper to reach,
  but every switch/faint-replacement path then needs an ownership check to stop
  the player managing the partner's team, and those paths are numerous.

**Recommend the second party object.** The ownership question does not go away
in the merged model, it just moves into every call site that touches switching.

**[OPEN at implementation time]** — which of the two, plus whether the partner
gets 3 Pokémon (source's `MULTI_PARTY_SIZE`) or a full 6.

### 17.1 RPG save → simulator: "only Pokémon you actually caught" *(assessed rev 17)*

**Verdict: the plumbing is nearly free; the design question is the real work.**

The architecture already lines up, largely by accident of decisions made for
other reasons:

- **`TeamStorage` stores construction-input specs, not serialised objects** —
  `{dex, level, move_ids, nature, evs, ivs, ability_slot}`, deliberately chosen
  in M23.5 to avoid format churn against `BattlePokemon`'s volatile fields.
- **`PokemonFactory.create_battle_pokemon(dex, level, move_ids, forced_nature,
  forced_ivs, forced_friendship, evs, ability_slot)`** reconstructs from
  exactly that shape.
- **`BattleSetupContext` takes `BattleParty` objects and is origin-agnostic** —
  it cannot tell a team-builder Pokémon from a caught one, and shouldn't.

So **the battle engine needs zero changes.** By the time battle sees them, a
Pokémon caught in the RPG and one built in the team builder are the same
`BattlePokemon`. That is the expensive half already solved.

What actually has to be built:

1. **RPG-caught Pokémon must persist in a readable pool** — party plus boxes,
   inside the active save slot per the box rule (§0). **If they are stored in
   the same spec shape `TeamStorage` already uses, this step is nearly free**
   — which is a strong argument for doing exactly that when the save format is
   designed, rather than inventing a second representation and writing a
   converter later.
2. **A reader** exposing "everything this slot has caught" to the simulator.
3. **A constrained team-builder mode** sourcing from that pool instead of the
   full species list — the existing builder validates *legality*
   (`MovepoolResolver`), this adds *ownership* as a second filter.
4. **Cross-slot rules** — which save slot a simulator profile draws from, and
   what happens when that slot is deleted or the profile outlives it.

**The genuine design question, and it is not a small one: what does "the
Pokémon you caught" mean?** Two very different modes:

- **As-caught** — the exact instance, with its real IVs, nature, EVs and
  current moveset. Your actual Pikachu, flaws included. Makes the RPG
  playthrough meaningful in the simulator and is the interesting version.
- **Species-unlocked** — catching a species unlocks it for free rebuilding at
  competitive spreads. Much more permissive, and closer to how the existing
  team builder already works.

These want different UI and imply different things about the RPG. Worth
deciding before the save format is fixed, because **as-caught needs per-instance
fidelity in the save and species-unlocked only needs a set of dex numbers.**

**DECIDED rev 18: AS-CAUGHT.** The simulator's caught-only mode uses the exact
instance — real IVs, nature, EVs, current moveset, flaws included. Direct
consequence, and it is a **save-format constraint, not a simulator one**: the
RPG save must persist **per-instance fidelity for every caught Pokémon**, party
and boxes alike, not merely a set of owned species. Store them in the same
construction-input spec shape `TeamStorage` already uses and the simulator side
is close to free; store anything lossier and the mode becomes impossible
without a save migration later.

---

## 18. Audio

- **Map music + transitions** — Per-map BGM, bike/surf music overrides,
  fanfares/jingles.
- **Sound effects** — Doors, steps, ledge hops, menu sounds, overworld cries.
- Note: this project has **zero audio infrastructure anywhere** today —
  repeatedly flagged during M26 as needing its own scoping pass, still
  unscoped. Sizing this as "wire up some SFX" would be wrong.

---

## 19. Save System (bigger than flags + vars)

Decided: **build for the fuller save** rather than the minimal one. Reference
reality — flags and vars are only ~5% of SaveBlock1 (~90 top-level fields, ~14
compile-time layout toggles, an encryption key obfuscating several fields).

- **Persistent world state** — All flags/vars, object event states, berry
  trees, roamer state.
- **Live-world snapshot — ⚠ CORRECTED rev 12, the previous text was wrong on
  both counts.** It read: *"Reference persists runtime NPC positions/state
  mid-patrol and a 512-byte `mapView` tile-diff overlay recording live map
  edits (cut trees, moved boulders)… tile-diff overlay is likely still needed
  for cut/smash/boulder permanence."* Verified against source, none of that
  holds:
  1. **`objectEventTemplates[64]` in SaveBlock1 is cleared and repopulated from
     the map header on every map load** (`overworld.c:537` does a literal
     `CpuFill32(0, …)` then refills). It is a per-map working buffer, **not** a
     cross-session store of where NPCs were standing.
  2. **`mapView[0x100]` is a screen-sized window snapshot around the player,
     and it is cleared on restore** (`ClearSavedMapView()` runs at the end of
     the load path, `fieldmap.c`). Its job is holding the visible area across a
     single transition — stepping into a door and back out — **not** recording
     world-wide tile edits.
  3. **Cut trees and boulders persist through object-event visibility flags**,
     the §2 mechanism already in scope. And in FRLG they often do not persist
     at all: Cerulean City's cuttable tree is gated on **`FLAG_TEMP_13`**, a
     *temp* flag, so it **regrows on map re-entry** — and a second tree on the
     same map carries no flag whatsoever.

  **Consequence: the simplification is not a simplification.** "NPCs reset to
  spawn on load" is approximately what the reference already does, and the
  tile-diff overlay can be dropped from scope entirely rather than built. This
  removes a whole persistence category *and* a 512-byte structure, and the
  §23 save-format-churn risk shrinks accordingly. **DECIDED** — no longer open.
- **Lingering field effects** — Repel steps remaining, Flash active, current
  weather — easy-to-forget saveable state.
- **Player state** — Position/map, facing, gait state, elevation, money,
  heal-spot.
- **Untrusted input rule** — Save files can be shared or hand-edited; the
  loader validates everything and assumes nothing. (Reference stores an
  executable script buffer, `ramScript`, *inside* the save — explicitly do not
  inherit that design.)
- **Slot layout** — Per the box rule (§0): a slot is a path prefix; nothing
  playthrough-specific lives outside the active slot's payload.
- **The reference's own exclusion checklist** *(new rev 11)* —
  `include/config/save.h` is a list of `FREE_*` toggles that compile out a
  subsystem and reclaim its saveblock bytes: Trainer Hill (28 B), Trainer
  Tower, Mystery Event `ramScript` (1,104 B), Match Call / VS Seeker (104 B),
  Union Room chat (212 B), E-Reader Enigma Berry (52 B), link battle records
  (88 B), Mystery Gift (876 B), Battle Tower E-Reader (188 B), Pokémon Jump
  (16 B), record-mixing hall records (1,032 B), and unused Pokédex seen flags
  (52 B). **This maps almost one-to-one onto §24's OUT list and is worth using
  as a cross-check**: anything here that is *not* already an explicit OUT
  decision is a subsystem nobody has ruled on. Note `FREE_MYSTERY_EVENT_BUFFERS`
  frees exactly the `ramScript` buffer §19 already says not to inherit —
  independent corroboration that dropping it is the sanctioned path, not a
  deviation.

---

## 20. Dev / Debug Tooling

- **Map importer — the primary content path, not a tool** *(promoted rev 10)* —
  converts reference `map.json` + `layouts.json` (+ tilesets, events,
  connections) into Godot map scenes and metadata. No longer a
  "spike-then-decide": the decision is made (§0), so this is core
  infrastructure. Still prototype it first on one real map before
  industrialising, because it determines the entire content and tooling budget.
- **Behavior/elevation overlay — a READ AND WRITE surface** *(scope raised rev
  28, see §1.9)*: collision and elevation cannot be inferred for a
  hand-painted cell, so this is where they are set, not merely inspected.
  `@tool` x-ray view reading the real `cell_info()` resolver: color-coded behavior fills, ledge direction arrows,
  elevation letters, live redraw while painting, bright magenta for untagged
  tiles, distinct hatch for skirt cells. Same node runs in-game behind a debug
  key (F3 cycles modes) and validates stitching across chunk seams. **This
  becomes MORE valuable under the import-first decision, not less** — it is the
  primary way to validate importer output, including the §1.4 elevation
  mapping.

### 20.1 Rules for `@tool` surfaces *(new rev 29 — all three earned the hard way)*

Three defects shipped in the overlay's own read half, in one afternoon. Every
one was invisible to the runtime screenshots that "verified" it, and every one
was found by a human opening the editor. They are recorded as rules rather than
as an anecdote because the next `@tool` surface will hit the same three.

**Rule 1 — a `@tool` surface's checkpoint includes in-editor verification, not
just runtime screenshots; and its dependency chain is asserted `@tool` by
test.** Godot instantiates a NON-`@tool` script as a *placeholder* in the
editor: any call into one throws `Attempt to call a method on a placeholder
instance`. So it is not enough for the tool node itself to carry `@tool` — every
script it reads through must too (here: `map_overlay` → `step_resolver` →
`map_data` → `metatile_behavior`). Runtime screenshots cannot catch this,
because at runtime nothing is a placeholder. Asserted by reading the first line
of each file (`m27a_step_resolver_test.gd` §L) — cheap, and it would have caught
this for free. Note `metatile_behavior.gd` is GENERATED: its `@tool` comes from
the emitter in `gen_map_import.py`, since a hand-added line there is wiped on
the next importer run.

**Rule 2 — editor mode draws everything; runtime clips; a degenerate clip falls
back to full, never to nothing.** `get_viewport_transform()` does not track the
2D editor camera for a node in the edited scene, so clipping against it in the
editor yields an empty rect and the tool renders *nothing* — which reads as "the
tool is broken" rather than "the tool drew zero cells". The clip exists for the
runtime case, where a moving camera redraws constantly; in-editor the redraw is
property-driven, so drawing the whole map is free even at Viridian Forest's
3,726 cells.

**Rule 3 — the overlay is never baked into a map scene, and a test says so.**
It lives in its own scene and is instanced conditionally. That is not a style
preference: a persisted instance ships inside the map scene *unconditionally*,
bypassing the `OS.is_debug_build()` gate entirely and putting a developer x-ray
in a shipped build. This already happened once — an editor session autosaved
`PalletTown_Frlg.tscn` with the overlay instanced inside it, and the only thing
that noticed was a container-count assertion about draw order, which says
nothing about what was actually wrong. Now asserted by name across all baked
maps (§N), matching both the scene path and the script path so a bare node with
the script attached cannot slip past.

**Corollary on baked scenes.** A baked map is *also* hand-editable (§1.9), so an
added child is legitimate content, not a defect — assertions about baked
structure must check the baker's own containers and their order, never "and
nothing else". Rule 3 is the deliberate exception, and it is enforced by
identity rather than by count.

- **Connection ghost preview (wanted, lower priority)** — `@tool` script
  instancing semi-transparent neighbor maps at true offsets from connection
  metadata (never saved into the scene); Porymap's connection view in the Godot
  editor.
- **Overworld debug menu** — Real-time manipulation of flags, vars, warps,
  inventory, party (e.g., hatch egg instantly).
- **Debug toggles** — No-collision walking, trainers don't see player, disable
  encounters.
- **Version/utility submenus** — Misc utilities pattern worth copying for
  engine introspection.

---

## 21. Player Stat Tracking (to scope later)

- **Game-stats counters** — Emerald-style flat counter set: battles fought
  (wild/trainer split), trainers defeated, Pokémon caught, Pokémon encountered,
  attacks made, total money earned/spent, steps taken, eggs hatched, fishing
  attempts, Center uses, etc. Autoload singleton; bump calls live inside central
  resolvers (battle end, catch resolution, step resolver, money flow), never at
  call sites.
- **Stat list decided early** — Counters can't be backfilled on existing saves;
  over-provision from Emerald's ~50-stat menu.
- **Dual stat pools** — Overworld/save stats and simulator-mode stats tracked
  separately in the final product; battle engine emits bumps through the
  overworld↔battle event seam so the simulator routes to its own pool (and
  test/team-builder battles never inflate save-file lifetime totals).
- **Serialization + tests** — Dict-of-ints save payload; one test per stat via
  scripted battles/steps asserting counters.
- **Multi-player on one system** — 3 RPG save slots and 3 simulator-mode
  profiles, each with its own stat pool, so separate players on the same system
  track their own numbers. Save/profile selection at boot for the RPG and at
  simulator entry; each RPG slot is a fully independent save (world state,
  party, stats), each sim profile owns its teams + sim stats.

---

## 22. Build Order & Testing Strategy

- **Walking skeleton (first milestone)** — One map, grid step resolver,
  collision, camera. No NPCs, no scripts, no stitching, no day/night.
  Deliberately trivial, deliberately provable — the overworld equivalent of the
  battle engine's M1 dummy-move state machine. **Includes movement
  deliberately**: a rendered map you cannot walk on proves much less than a
  small one you can. Test suite from day one, not retrofitted.
- **Then, in order** — importer (one real map end to end, incl. the §1.4
  elevation mapping table) → importer generalised across tilesets and maps →
  stitching + border skirt → entity/object-event placement → interaction +
  Dialogue Manager wiring → script engine (own milestone, post-specials-
  scoping) → encounters → menus → save.
- **Testing conventions to establish early** — The battle engine's conventions
  were earned mistake-by-mistake; overworld has its own waiting class. Design
  for these from the skeleton: **step-timing vs. frame-timing** (assert on
  landed steps, never on frames), **tween-vs-logic desync** (logic position is
  truth; tests never wait on tweens), **chunk-seam state** (cases that cross
  map boundaries mid-step), and **script-coroutine reentrancy** (a script
  triggering a script; interaction during a cutscene).
- **Milestone decomposition still owed** — Every prior milestone of this size
  needed sub-tiers (M17: 14, M18: 24, M19: bucketed). This document is
  architecture, not sequencing; the decomposition is a separate deliverable.

### 22.1 Numbers to reconcile before implementation begins

Three figures were stated differently across the source documents this rev
merges. None blocks scoping, all should be settled to one measured value before
work starts, because they are the numbers future sizing decisions will be made
against.

| Figure | Values seen | Measured | Action |
|---|---|---|---|
| Total maps | 940 (m27_recon) | **939** `data/maps/*/map.json` = 421 Kanto + 518 Hoenn | Re-derive and fix; confirm whether any map lacks a `region` field |
| Script opcodes | "231 opcodes (223 live)" (rev 9) vs "237 script commands" (m27_recon) | **232** `script_cmd_table_entry` lines, 2 of them NOP → **230 live**; **237** `ScrCmd_` functions in `scrcmd.c` | Decide which metric the roadmap quotes (table entries vs. C functions) and state it explicitly — they are genuinely different things |
| Macros | 393 (both docs) | **393** confirmed | No action |
| Metatile behaviors | "240 constants (213 named)" (rev 9) | **240** enum entries, 27 `UNUSED` → **213 named** | Verified correct, adopt as-is |

Also re-verify at the same time: the ~620/~421/~2,090 specials figures in §6,
which drive the 30–40% sizing claim and have not been independently re-measured
in this pass.

---

## 23. Risk Register

- **Script engine sprawl** — The ~421-special inventory is the single biggest
  unknown; mitigate with the dedicated scoping session and by grouping specials
  so exclusions drop whole clusters.
- **FRLG-vs-Hoenn attribute width** *(new, rev 10)* — the highest-severity
  *silent* failure in the importer. A Hoenn-shaped reader misparses every Kanto
  tileset while appearing to work. Mitigate by branching on `isFrlg` and by
  asserting the entry-count arithmetic (`metatiles.bin ÷ 16 == attributes ÷ 4`)
  at import time.
- **Elevation bucket mapping** *(new, rev 10)* — a wrong 0–15 → 5-bucket table
  produces subtly unwalkable bridges rather than obvious breakage. Mitigate by
  measuring the real value distribution across Kanto blockdata and by leaning
  on the behavior/elevation debug overlay (§20) as the validation surface.
- **Importer fidelity** — reduced from rev 9's "importer fails" framing: the
  data is confirmed present and complete, so the risk is now fidelity and edge
  cases rather than viability. Still spike on one real map before
  industrialising.
- **Art source — SETTLED rev 12: pull the reference FRLG tilesets.** Retained
  as a risk entry because the pull itself still has to be done correctly (see
  §1.2's attribute-width trap, which is where a tileset pull goes wrong
  silently). The alternative — the tileset already committed in-repo — is
  rejected: the
  import-first decision (§0) pushes strongly toward reference tilesets, since
  the real `map.bin` can only address those.
- **Kanto region vs. Hoenn-derived battle stack** — Trainer/encounter data
  alignment needs checking; Kanto encounter data is confirmed present (§11) but
  the repo copy is unloaded.
- **Save-format churn** — Mitigated by the box rule and by deciding the
  live-world-snapshot question (§19) before serializing anything.
- **Roadmap divergence** — **[OPEN — Rob]** This doc silently spans M27–M35
  (encounters=M29, surf/field moves=M32, region map/dex areas=M33, save+box
  rule=M34, time-based evolutions=M28). CLAUDE.md and this document currently
  describe two different plans. Recommend **collapse with an explicit
  renumbering + mapping table** (same treatment M26 received), since the box
  rule genuinely must be day-one rather than deferred to M34. Fold in the three
  narrower boundary questions from the superseded `m27_recon.md` §5 while doing
  it: the **M27E-vs-M29 split** (trigger vs. content/mechanics), **what the
  overworld milestone explicitly excludes** given M28/M29/M30/M31/M32/M33/M34
  all claim adjacent scope (HM field effects especially), and **where flags/
  vars live** before a save milestone exists.

---

## 24. Scope Status (decided)

- **Confirmed OUT** — Followers, DexNav / visible overworld encounters,
  contests + Pokéblocks, Game Corner, secret bases, mail, phone system, and TV
  shows (definitively out — high-cost procedural broadcast system with
  near-zero payoff; house TVs get a static flavor line). The phone's escalating
  rematch "party versions" data model is still worth borrowing for rematch
  design.
- **Sizing the exclusions** *(new rev 11)* — worth stating, because it is the
  single largest scope saving in this document. Line counts of the confirmed-OUT
  subsystems in reference source: TV 6,788 · Contests 6,116 · Easy Chat 5,839 ·
  Dodrio Berry Picking 5,216 · Trade 5,117 · Roulette 4,687 · Union Room 4,520 ·
  Pokémon Jump 4,109 · Berry Blender 3,888 · Berry Crush 3,489 · Decorations
  2,730 · DexNav 2,671 · Secret Base 2,076 · PokéNav 842 · Mystery Gift 752 —
  and Slot Machine alone at **7,892**. **~67,000 lines** across these, before
  counting the link/RFU stack underneath several of them.
- **Confirmed OUT but never previously stated** *(new rev 11)* — surfaced by
  the `src/` sweep and by `save.h`'s own `FREE_*` list; each has real code
  behind it, so leaving them unstated risks a future session treating one as
  in-scope by default: **trading** (`trade.c`, and with it the whole
  trade-evolution question §9 defers), **link / Union Room / record mixing**,
  **Mystery Gift**, **Easy Chat**, and the **link minigames** (Berry Blender,
  Berry Crush, Dodrio Berry Picking, Pokémon Jump). Slot Machine and Roulette
  fall under the existing Game Corner exclusion. Trainer Tower / Trainer Hill
  fall under the facility-trainer deferral already recorded in CLAUDE.md's M35.
- **Explore: Safari Zone + Bug Catching Contest** — Both are "special zone"
  modes sharing machinery: entry fee, limited balls, step/time limit, modified
  catch flow, exit-and-tally. Contest adds keep-one-and-score on top (~30% extra
  if Safari Zone exists) — explore together.
- **Explore: Battle Frontier** — Likely as a frontend/connection to the existing
  standalone simulator layer (facilities are rule variants — rentals, streaks,
  restricted formats — over battles already decoupled from the RPG wrapper), not
  a standalone build.
- **Deferred** — Time-based evolutions & forms (decide at evolution scoping);
  berry trees (likely out); UI state stack architecture (TBD — shapes start menu
  / bag / party / battle-handoff nesting, settle before menu work).

---

## 25. Game flow: new game, identity, endgame *(new rev 11)*

**A whole arc rev 10 had no section for.** Every prior revision started at
"player is standing on a map" and ended at "player is still standing on a map."
The reference has a real, substantial path in and out of that state, and an RPG
cannot ship without one.

**Into the game:**

- **Title screen** (`title_screen.c`) — plus `ENABLE_QUICKSTART`
  (`include/config/quickstart.h`), a genuinely useful dev affordance: press
  SELECT at the title to skip straight into a new game with a preset gender,
  disabled on release builds. Worth porting early purely for iteration speed;
  it is the overworld equivalent of this project's own `--autoplay` flag.
- **Main menu / save-slot selection** (`main_menu.c`, **2,313 lines**) — New
  Game / Continue / Options, the continue-screen summary (badges, playtime,
  dex count), and the save-file-corrupt path. **This is where §21's "3 RPG save
  slots, selected at boot" actually lives** — that requirement was stated with
  no screen behind it.
- **Opening cinematic** (`intro.c` 3,429 lines, `intro_frlg.c` 2,796) — the
  pre-title animation. **Almost certainly out** for an original story, but it
  should be an explicit cut rather than an omission, since it is ~6,000 lines
  of reference code doing nothing else.
- **Professor intro + starter choice** (`birch_pc.c`, `starter_choose.c`) —
  the scripted opening and the three-ball selection screen. Original story
  means the *content* is authored, but the flow and the selection UI are real
  components.
- **Player naming** (`naming_screen.c`, **2,650 lines**) — the on-screen
  keyboard. **This is the concrete thing that unblocks the §0 player-identity
  item and the hardcoded `_PLAYER_BACK_PIC = Leaf` placeholder in shipped
  battle code.** Also reused for nicknaming (§15's name rater) and for box
  naming (§16's PC storage), so it is not a single-use screen.

**Out of the game:**

- **Hall of Fame** (`hall_of_fame.c`, 1,538 lines) — the champion registration
  sequence plus the saved record of past teams.
- **Credits** (`credits.c`) — the ending roll.
- **Evolution scene** (`evolution_scene.c`) — the evolution cutscene, distinct
  from the evolution *mechanics* CLAUDE.md's M28 owns. It is overworld
  presentation triggered from the post-battle return path (§17), and it is
  where an original story most visibly does or does not feel finished.

**DECIDED rev 12.** Main menu, player naming and starter choice are **in and
early** — naming is what unblocks the `_PLAYER_BACK_PIC` placeholder. Title
screen **in**, cheap, and worth taking `ENABLE_QUICKSTART` with it. Opening
cinematic **out** (~6,000 lines, and an original story wants its own opening if
it wants one at all). Hall of Fame and credits **in but late** — endgame-only,
they block nothing.

---

## 26. Newly-surfaced systems & decision points *(new rev 11)*

Five real systems found by sweeping `include/config/` against this document.
Each is listed with its default, because **three of the five are already on**.

- **Badge-gated level caps** (`include/config/caps.h`, `src/caps.c`) —
  **default OFF**, but the machinery is complete and the default table is
  already written: level cap 15 until Badge 1, then 19 / 24 / 29 / 31 / 33 /
  42 / 46, and 58 until Champion. Two cap styles (`EXP_CAP_HARD` blocks EXP
  entirely at cap, `EXP_CAP_SOFT` reduces it), two ways to derive the cap
  (badge-flag list, or an event variable for full script control), plus
  `B_RARE_CANDY_CAP` and `B_LEVEL_CAP_EXP_UP` (under-cap Pokémon gain *more*).
  There is a parallel EV-cap system. **This is a genuine design lever for an
  original story** — it is how a hand-authored campaign controls difficulty
  without hand-tuning every trainer — and it interacts directly with this
  project's already-shipped M20 EXP/EV work. **[OPEN — Rob]** in or out.
- **Pokérus — CUT** *(decided rev 12)*. Detail retained below because it is
  ON in reference and someone will otherwise re-surface it. (`include/config/pokerus.h`, `src/pokerus.c`) — **default ON**
  (`P_POKERUS_ENABLED TRUE`). 16 strains, infection odds 3/65536, spread odds
  ~1/3 to adjacent party members, with a dozen generational sub-behaviours
  configured. **It is driven by the day counter** — `clock.c:59` calls
  `UpdatePartyPokerusTime(daysSince)` — so it is a real consumer of §9's time
  system, not an isolated flag. Note this project's own M20c deliberately
  excluded Pokérus from EV gain on the grounds that no infrastructure existed;
  that reasoning holds only while it stays out — **and rev 12's decision is
  that it stays out**, so M20c's exclusion remains correct and needs no revisit.
- **Map preview screen** (`include/config/map_preview_screen.h`,
  `src/map_preview_screen.c`) — `MPS_ENABLE_MAP_PREVIEWS` is `IS_FRLG`, so for
  a Kanto/FRLG-styled project **this is effectively on by default**. It shows a
  landmark card when entering a map, longer on first visit (120 frames) than on
  return (40). **The art already exists and is Kanto** — `graphics/map_preview/`
  holds Cerulean Cave, Diglett's Cave, Berry Forest, Dotted Hole, Altering
  Cave among others. Cheap, atmospheric, asset-backed, and completely absent
  from every prior revision. Sits inside the warp transition (§12).
  **DECIDED rev 12: IN.**
- **Dialogue name box — what it actually is** *(elaborated rev 12)*.
  `src/field_name_box.c` is only **226 lines**: a small window rendering the
  **current speaker's name** alongside the message box. A script macro buffers
  a string as the speaker name, and *"the next shown message/msgbox will
  include a namebox, if the provided string is not NULL"* — so it is opt-in per
  message, not a permanent chrome change. Config covers dynamic width sizing to
  the name (capped at 8 tiles), height 2, its own foreground/shadow palette
  indices, a global suppress flag, and `OW_NAME_BOX_NPC_TRAINER` to raise it
  automatically for approaching trainers using their trainer data.
  **Worth knowing: it has zero call sites in the shipped map scripts** — a grep
  across every `data/maps/*/scripts.inc` returns nothing. It is an expansion
  feature provided for hack authors; vanilla dialogue never uses it. So it is
  purely additive presentation, not something the reference's own dialogue
  depends on. **DECIDED rev 13: implement speaker names ourselves.** Neither
  port `field_name_box.c` nor depend on a Dialogue Manager feature for it —
  a speaker label is a small, well-understood piece of UI and owning it keeps
  the DM boundary clean (DM presents the conversation; the surrounding chrome
  is ours, the same way the battle message box already is). The reference
  config is still worth mining for behaviour: dynamic width sizing to the name,
  a global suppress flag, and auto-raising it for approaching trainers from
  their trainer data are all cheap and all sensible defaults to copy.
- **NPC followers — the core is cheap, the edge cases are not**
  *(answered rev 12)*. Rob's read is correct: **the following mechanism really
  is just replaying the player's previous tile.** `PlayerLogCoordinates()`
  stores exactly one thing — the player's current x,y — and the follower steps
  onto it. That is the whole idea, and a short-term scripted escort built that
  way is genuinely cheap.

  **`follower_npc.c` is 1,885 lines because of everything around it**, not the
  step logic: surf mounting/dismounting onto a shared surf blob (32 references),
  door entry/exit with the player turning to face the follower (25),
  escalators with their own trajectory maths (16), underwater, warps, bike,
  plus partner trainer battles, the two-team party preview, and auto-heal.
  Every traversal mode the game has, the follower needs a case for.

  **So treat it as two separate items, not one:**
  - **Scripted short-term escort** — a partner walks with you through a
    defined area on flat ground. Cheap, and the coordinate-log approach is
    genuinely all it needs. Reasonable to keep in scope.
  - **Persistent companion** — follows everywhere, across surf, doors,
    escalators and battles. Inherits the full edge-case matrix and touches the
    step resolver, the battle handoff and the saveblock.

  **⚠ Partner double battles are a SEPARATE system, and they do not need a
  follower at all** *(researched rev 17)*. This is the more useful half of the
  answer: a scripted "team up with your rival for this gym" double battle is
  triggered by a **script command** that sets `gPartnerTrainerId`
  (`battle_setup.c:2136`), with the partner's team coming from a static
  `gBattlePartners[difficulty][partnerId]` table — structurally just another
  trainer. No follower infrastructure is involved.

  The follower system merely *feeds* it when present: `follower_npc.c:1673-1704`
  overrides `gPartnerTrainerId` with the following NPC's own partner id if that
  NPC is flagged `FNPC_DATA_BATTLE_PARTNER`, and can additionally let them join
  **wild** battles (`FNPC_FLAG_PARTNER_WILD_BATTLES`) — which scripted partner
  battles never do. So the follower adds two things and only two: the partner
  physically walks with you beforehand, and they can appear in wild encounters.

  **The real blocker for either is on our side, not the reference's.**
  `BattleManager._human_controlled` is `Array[bool]` **indexed by SIDE**
  (`battle_manager.gd:566`, read as `_human_controlled[side]` throughout move
  selection). An in-game partner battle needs the player's side to be *half*
  human — slot 0 the player, slot 1 AI — which the current model cannot
  express. That is a real change to the M23.0a human-control contract, and it
  is required for partner battles **whether or not followers are ever built.**

  **DECIDED rev 18: scripted partner double battles are IN; the persistent
  follower is OUT.** Short-term scripted escorts cover the walking-together
  case where a scene wants it, using the coordinate-log approach above.
  See §17.2 for what partner battles actually cost — it is more than the
  control flag.

---

## 27. Decisions — settled and outstanding

### Still open

1. **Roster-swap difficulty** (§29) — deliberately parked at no cost. The seam
   is a ten-minute retrofit on one loader function; just keep difficulty
   resolution outside `BattleManager`, which it already is.

Deferred to implementation time rather than scoping: Nuzlocke party semantics
(§29), and the partner-battle party model (§17.2 — second `BattleParty` vs
merged-with-ownership, and whether the partner carries 3 Pokémon or 6).

### Settled

| # | Decision | Rev |
|---|---|---|
| — | Import first, author tweaks after | 10 |
| — | Kanto encounter data — **IN** (264 of 388 entries) | 10 |
| — | `pallettown.tscn` — **not** the starting point | 10 |
| 1 | Art source — **reference FRLG tilesets**, pulled | 12 |
| 7 | Time-of-day encounter tables — **OUT**, §28 | 12 |
| 8 | Pokérus — **OUT** | 12 |
| 9 | Map preview screen — **IN** | 12 |
| 11 | Game flow — main menu + naming + starter early, title screen in, **cinematic out**, Hall of Fame + credits late | 12 |
| 12 | Live-world snapshot — **no persistence, no tile-diff overlay**; the reference does not do what §19 previously claimed | 12 |
| 13 | Field summary screen — **build once**, shared with M26E4 | 12 |
| 14 | Bedroom PC — **cut**; one PC only, the Pokémon Center terminal | 12 |
| 15 | Escalators — **IN**, low priority | 12 |
| 16 | Rotating gates — **§28 nice-to-have** | 12 |
| 4 | Lead-ability encounter hooks — **all eight OUT** | 17 |
| 6 | Nuzlocke party semantics — **decided at implementation time**, not scoping | 17 |
| — | Simulator caught-only mode — **AS-CAUGHT** (exact instance). Constrains the save format: per-instance fidelity required | 18 |
| 5 | Scripted partner double battles — **IN** (§17.2) | 18 |
| 6 | Persistent NPC follower — **OUT**; short-term scripted escorts cover the need | 18 |
| 1 | Elevation buckets — **MEASURED** (§1.4): only 5 of 16 values occur; 4+5 collapse to one `upper` with zero loss | 19 |
| — | Terrain layers — **three, content-named**: `Ground` / `Objects` / `Overhangs`, entity container sibling of `Objects` | 20 |
| — | Elevation stored **per-cell**, not on the TileSet — 52.1% of metatiles appear at multiple elevations | 21 |
| 2 | Roadmap renumbering — **APPROVED AND APPLIED** (§31): M27A–M27L, M32/M34 retired, nothing renumbered | 22 |
| 17 | Field-move badge gating — **port the FRLG mapping exactly**, re-map as the story develops | 13 |
| 4 | Speaker names — **implement ourselves**; neither port `field_name_box.c` nor depend on DM for it | 13 |
| 13 | Summary screen — build INFO/SKILLS/BATTLE MOVES **exactly**, keep the 4th page slot parameterised and empty | 13 |

---

## 28. Nice to haves *(new rev 12)*

Deferred deliberately, not dropped. Each is genuinely additive — none requires
a change to a system built before it, which is why deferring costs nothing.

- **Time-of-day encounter tables** (§11) — ships zero reference data, so it is
  authoring from scratch. Additive: a second lookup keyed on the §9 time
  bucket, sitting beside the normal table rather than replacing it. Note
  `OW_TIME_OF_DAY_DISABLE_FALLBACK` and `OW_TIME_OF_DAY_FALLBACK` decide what
  happens when a time-specific table is empty — with fallback on (the default),
  partial authoring works fine, so this can be filled in map by map rather than
  all at once.
- **Rotating gate puzzles** (§5) — `rotating_gate.c`, 1,031 lines. Push-to-
  rotate block puzzles. Hoenn puzzle furniture; nothing in Kanto uses them.
  Only worth revisiting if an authored dungeon specifically wants the mechanic.
- **Berry trees** (§13) — already leaning cut; recorded here so the leaning has
  somewhere to live. All the XY-era sub-mechanics (mutations, moisture, weeds,
  pests, six growth stages) default off in reference anyway.
- **Fishing extras** (§5) — chain fishing for shiny odds, proximity bonus,
  time-of-day bite bonus, follower-friendship bonus. All default off upstream;
  the base rod flow and the Gen 3 reeling minigame stand alone without them.
- **Trainer rematches** (§4) — the phone system is OUT, but its escalating
  "party versions" data model is worth borrowing whenever rematches are
  wanted.

---

## 29. Modes and tweaks *(renamed rev 16)*

RPG-side difficulty, plus the player-facing tweaks that shape how a battle
feels without changing its rules.

The reference has considerably more difficulty machinery than "level caps," and
one piece of it collides with something this project already built.

### ⚠ The reference has a difficulty system — and so do we, meaning something different

`enum DifficultyLevel { EASY, NORMAL, HARD }` (`include/constants/difficulty.h`),
driven by `B_VAR_DIFFICULTY` and script-controlled through
`Script_SetDifficulty` / `Script_IncreaseDifficulty` / `Script_DecreaseDifficulty`
/ `Script_GetDifficulty` — so difficulty is settable from an in-game NPC or
menu and **can change mid-playthrough**.

**Its mechanism is trainer-roster swapping**, not number tweaking:
`gTrainers[DIFFICULTY_COUNT][TRAINERS_COUNT]` is a 2D array, and
`GetTrainerDifficultyLevel()` falls back to `DIFFICULTY_NORMAL` whenever that
difficulty's party is `NULL`. So a trainer can have a genuinely different team
per difficulty, and any trainer you don't author variants for simply behaves
normally. Battle partners work the same way (`gBattlePartners[difficulty][…]`).

**Zero of the 855 trainers in `trainers.party` actually declare a difficulty**
— the `Difficulty:` key is fully supported by `tools/trainerproc` but unused by
every shipped trainer. Exactly the shape of the Trainer Pools finding from M24:
real infrastructure, no shipped data. Two consequences: M24a's converter lost
nothing by ignoring it, **and** `scripts/gen_trainer_data.py` has no
`Difficulty` handling at all, which should be added before the Kanto roster is
authored rather than after.

**The collision:** this project's `BattleManager.difficulty_mode`
(`DifficultyMode.NORMAL/HARD/CASUAL`, `DIFFICULTY_PERCENT`, applied at
`battle_manager.gd:7372`) is an **EXP multiplier** invented during M20's EXP
design. The reference's is a **roster swap**. They share a name and share
nothing else. They can coexist — they act on different things — but they must
not be conflated, and the naming should be disambiguated before both exist.

### Level and EXP caps — full mechanism

- **`B_EXP_CAP_TYPE`** — `NONE` / `HARD` (zero EXP at or above cap) / `SOFT`
  (reduced). Soft scaling is a real table: over cap, EXP is divided by
  `{4, 8, 16, 32, 64}` by how far over you are.
- **Catch-up EXP** — with `B_LEVEL_CAP_EXP_UP`, Pokémon *under* the cap gain
  **extra** EXP, `expValue + expValue/{16,8,4,2,1}` by how far under. A genuine
  anti-grind mechanism, not just a ceiling.
- **`B_LEVEL_CAP_TYPE`** — `NONE` / `FLAG_LIST` (badge-gated; default table
  15 / 19 / 24 / 29 / 31 / 33 / 42 / 46, then 58 until Champion) / `VARIABLE`
  (read from an event var — full script control, so caps can follow story beats
  rather than badges).
- **`B_RARE_CANDY_CAP`** — stops Rare Candy from exceeding the cap.
- **EV caps exist too** — `B_EV_CAP_TYPE` of `NONE` / `FLAG_LIST` / `VARIABLE`
  / `NO_GAIN`, with a badge-gated default table expressed as fractions of
  `MAX_TOTAL_EVS` (1/17, 3/17, …), plus `B_EV_ITEMS_CAP` to stop EV items
  bypassing it. `EV_CAP_NO_GAIN` is a one-flag way to run an EV-free campaign.

Note `include/config/caps.h` has a malformed line where `B_EV_CAP_TYPE`'s
trailing comment swallows a `#define B_EV_CAP_VARIABLE 12` before it is
redefined as `8` — a reference bug. Don't port that file by transcription.

### Other alternate modes worth knowing about

All flag- or var-driven, so all togglable per playthrough or per battle —
which makes them cheap for an authored campaign *and* useful in the simulator:

| Flag / var | Effect |
|---|---|
| `B_FLAG_INVERSE_BATTLE` | **Inverse type chart** for the whole battle |
| `B_FLAG_AI_VS_AI_BATTLE` | Player's team is AI-controlled — a real testing and demo affordance |
| `B_FLAG_SLEEP_CLAUSE` | Competitive sleep clause (AI needs `AI_FLAG_CHECK_BAD_MOVE` to respect it) |
| `B_FLAG_NO_WHITEOUT` | Player cannot white out against trainers (party is *not* auto-healed) |
| `B_VAR_NO_BAG_USE` | Disable bag in battle — `1` trainer battles, `2` also wild |
| `B_VAR_WILD_AI_FLAGS` | Add AI flags to wild Pokémon |
| `B_BADGE_BOOST` (GEN_3) | Each badge grants **+10%** to a specific stat, per-stat flag-gated |
| `B_FLAG_SKY_BATTLE` / `B_VAR_SKY_BATTLE` | Scripted Sky Battles, with position memory |

`B_BADGE_BOOST` is the one to note: it is difficulty-relevant, badge-driven,
and this project has never modelled it. Dynamax and Tera flags are present but
already excluded project-wide.

### Decisions — CLOSED rev 14

**Everything above is out. RPG difficulty is exactly three things, and the
simulator's is a different milestone's problem.**

Out, recorded rather than deleted so they read as declined and not missed:
level caps, catch-up EXP, EV caps, all eight alternate-mode flags (inverse
battle, AI-vs-AI, sleep clause, no-whiteout, bag lockout, wild AI flags,
`B_BADGE_BOOST`, sky battles), **and the reference's own EASY/NORMAL/HARD
roster-swap system**. Consequence of that last one: `gen_trainer_data.py`
needs no `Difficulty` handling, and the name collision with this project's own
`difficulty_mode` resolves — there is only one difficulty concept now, ours.

#### RPG difficulty — the complete scope

1. **EXP variants — Reduced / Normal / Bonus.** This **renames the existing
   shipped mechanism** rather than adding one. `BattleManager.DifficultyMode`
   is currently `NORMAL / HARD / CASUAL` with `DIFFICULTY_PERCENT` of
   `100 / 50 / 135`; the rename maps by value, not by position:

   | Current | New | Multiplier |
   |---|---|---|
   | `HARD` | **`REDUCED`** | ×0.50 |
   | `NORMAL` | **`NORMAL`** | ×1.00 |
   | `CASUAL` | **`BONUS`** | ×1.35 |

   The old naming was actively misleading — `HARD` meant *less EXP*, which
   reads backwards. Touches `battle_manager.gd`'s enum and `DIFFICULTY_PERCENT`
   plus `m20_exp_test.gd`'s references; it has no production consumer today
   (§29's earlier note), so the rename is safe and the RPG becomes its first
   real consumer.

2. **Nuzlocke mode — fainted Pokémon cannot be revived at all.** Genuinely new
   mechanism, no reference equivalent (the reference has no nuzlocke support of
   any kind — this is original design). Note it is *stricter* than the
   tabletop convention: not "can't be used again," but **cannot be revived**,
   so Revive/Max Revive/Pokémon Center healing must all refuse a fainted
   Pokémon while it is on. Needs a decision at implementation time on whether
   the fainted Pokémon stays in the party, is force-boxed, or is released —
   and on whether the whiteout condition changes (§12).

3. **Per-battle item limit for the player — toggleable, X items.** Also
   original; the nearest reference analogue is `B_VAR_NO_BAG_USE`, which is a
   binary lockout rather than a budget. Applies to the player only, not the AI.
   Interacts with M22's existing battle-item turn-queue work and with the
   §16 Bag screen, which will need to surface the remaining allowance.

4. **Universal in-battle speed multiplier** — a player-facing tweak rather than
   a difficulty setting, but it lives here because it is the fourth thing that
   changes how a battle plays without changing its rules. Assessment at the end
   of this section; it also absorbs the cut BATTLE SCENE option's intent.

**Nothing else is in scope for RPG difficulty or modes.**

#### Roster-swap system — cost of leaving a seam *(assessed rev 15)*

Rob is undecided, so here is what it actually costs to keep the door open
versus build it. **The seam is small enough that deferring loses nothing.**

**Leaving a seam — genuinely tiny.** `TrainerRegistry.get_trainer(id)` is a
single path-convention function (`res://data/trainers/trainer_%04d.tres`, with
an `exists()` check already in it). The whole seam is an optional variant
parameter that tries a variant path first and falls back to the base file:

```
data/trainers/trainer_0042.tres          ← base, always present
data/trainers_hard/trainer_0042.tres     ← optional variant, may not exist
```

That fallback-when-absent behaviour **is exactly what the reference does** —
`GetTrainerDifficultyLevel()` returns `DIFFICULTY_NORMAL` whenever
`gTrainers[difficulty][id].party == NULL` — so a variant roster is authored
only where you want one, and every unauthored trainer behaves normally with no
data duplication. Cost: one optional parameter, one extra `exists()` check,
and `gen_trainer_data.py` learning to emit into a variant directory when
`trainers.party` declares a `Difficulty:` key (which the reference's own
`tools/trainerproc` already parses, and which **zero** of the 855 shipped
trainers currently use).

**Where difficulty gets resolved matters more than the loader.** Whoever
resolves a `TrainerData` before calling `set_trainer_data(side, data)` — the
M27 trainer-battle trigger — is the right place to consult difficulty.
`BattleManager` should keep receiving a fully-resolved `TrainerData` and stay
ignorant of variants entirely. Getting that boundary right is the only
decision that is expensive to change later; the loader itself is not.

**Building it fully is content, not code.** Once the seam exists, the real cost
is *authoring alternate rosters*, which scales with how many trainers get
variants and is entirely Rob's to pace.

**Recommendation: don't build the seam speculatively either.** Retrofitting an
optional parameter onto one loader function later is a ten-minute change; the
only thing worth doing now is *not* baking difficulty resolution into
`BattleManager`, which the current architecture already avoids. So this can
stay genuinely undecided at no ongoing cost.

#### Simulator difficulty and game modes — deferred to M35

The battle simulator's own game modes and difficulty are **out of this
document's scope entirely** and belong to what is currently CLAUDE.md's M35
(Advanced Battle Systems / battle expansion). That is also where the
competitive-flavoured flags declined above would naturally be revisited if
they are ever wanted — sleep clause and inverse battles are simulator features,
not overworld ones, which is part of why declining them here is safe.

---

### Universal in-battle speed multiplier *(assessed rev 15, moved here rev 16)*

**Verdict: genuinely cheap — one global property, set on entry and restored on
exit.** `Engine.time_scale` covers essentially the whole battle timing surface,
because that surface was already built wall-clock-clean:

| Mechanism | Sites | Scales with `time_scale`? |
|---|---|---|
| `create_tween` — slides, ball arc, scale, fades, HP drain, text reveal | 25 | **Yes** |
| `get_tree().create_timer(...)` | 3 real | **Yes** — none passes `ignore_time_scale` |
| `MonAnimator.Clock` frame-steppers | 2 real | **Yes** — both call `clock.advance(get_process_delta_time())`, and Godot scales `delta` |
| bare `await get_tree().process_frame` | 2 | No — but single-frame yields, not paced loops. Noise |

That is all of it. **There is no hand-rolled `Time.get_ticks_msec()` pacing
anywhere to miss** — a direct dividend of M26G4's refresh-rate-independence
audit and of `MonAnimator.Clock` being an accumulator rather than a
timer-per-step. Had either gone the other way, this would be a ~40-site change
instead of a one-line one.

**Four caveats, none blocking:**

1. **It is global to the SceneTree.** Harmless today, since battle is its own
   scene. Once a battle runs as an overlay with the overworld alive beneath
   it, the overworld speeds up too — fixed the same way regardless: set on
   battle entry, restore on exit, in one place.
2. **Audio pitches up** once audio exists. Standard trade-off for this
   approach; moot now (§18), worth remembering later.
3. **Scope it to the resolution phase, not the whole battle.** Scaling time
   while the player is choosing an action makes menus feel wrong — the goal is
   faster animations, not a faster UI.
4. **Tests unaffected** — `--autoplay` and the headless suites bypass these
   paths already.

**The alternative** — threading a multiplier through ~40 individual duration
constants — is strictly more invasive and only justified if the global-scope
caveat proves unacceptable in practice. Start with `Engine.time_scale`.

**This also absorbs BATTLE SCENE's intent.** A player who turns animations off
mostly wants the battle to go faster; a speed multiplier delivers that without
the desync risk of pulling beats out of a queue that later beats depend on.

---

## 30. Roadmap *(new rev 16)*

Ordered build plan with every settled decision folded in. Supersedes §22's
"then, in order" list, which stays as the testing-conventions reference.
**§23's renumbering against CLAUDE.md's M27–M35 is still open** — this is the
work sequence, not the milestone numbering.

**Two things that are day-one and cut across every phase:**
- **The box rule** (§0) — every piece of playthrough state lives inside the
  active save slot's payload. Applies to the first persistent structure built,
  not to a later save milestone.
- **Player identity** (§0) — trainer name, gender, ID. Small, and it unblocks
  the `_PLAYER_BACK_PIC = Leaf` placeholder already sitting in shipped code.

### Phase 1 — Prove the import

- Importer spike on **one real map** (Pallet Town) end to end.
- **FRLG 32-bit metatile attributes** (§1.2) — branch on `isFrlg`; assert
  `metatiles.bin ÷ 16 == attributes ÷ 4` at import time.
- **Build the 0–15 → 5-bucket elevation mapping table** (§1.4) by measuring the
  real distribution across the 421 Kanto maps. Reviewable artifact, not an
  inline constant.
- **Walking skeleton** — one map, grid step resolver, logic-based collision,
  camera. Movement included deliberately.
- Retire `pallettown.tscn`; it is not the starting point.

### Phase 2 — Industrialise the import

- Tileset conversion pipeline across the 62 FRLG tilesets.
- Map conversion pipeline across the 421 Kanto maps (geometry, collision,
  elevation, behaviours, warps, connections).
- **Object-event emission** into M27D's node types, plus the **script-label
  indexer** that recovers trainer identity (§32) — 432 of 432 Kanto trainer
  placements resolve automatically, so none are hand-rigged.
- **Behaviour/elevation debug overlay** (§20) — the validation surface for
  everything above, and the only practical way to check the elevation table.

### Phase 3 — A connected world

- Stitching + programmatic border skirt.
- Connections and warps; warp presentation chosen by metatile behaviour at
  trigger time, not by a typed field.
- **Map preview screen** (§26) — FRLG-style landmark card, Kanto art already
  present in the reference.
- Escalators (low priority, Kanto department store).

### Phase 4 — Entities

- **Object-event system** — one `@tool` base scene per category over a shared
  `OverworldEntity` (NPC / TrainerNPC / ItemBall / Warp / Trigger / Sign),
  placed instances as the single source of truth for spawn data, trainers
  referenced by `trainer_key`. Detail and review in §32; the importer (M27B)
  emits these nodes and the editor edits them.
- NPC movement types sharing the player's step resolver.
- Trainer sight and approach — one-tile line along the facing axis, object-ID
  detection order.
- **No live-world persistence** (§19) — NPCs reset to spawn, no tile-diff
  overlay. This is what the reference already does.

### Phase 5 — Talking

- Interaction, then **Dialogue Manager wired for the RPG side** (§6.1):
  branching, conditions, responses, mutations calling engine systems.
- **Speaker names implemented ourselves** — not ported, not DM's.
- **Field script engine** — its own milestone, after a dedicated specials
  scoping session. Realistically 30–40% of total overworld work, and DM owning
  conversational scripts is the largest lever on shrinking it.

### Phase 6 — Encounters and battle glue

- Encounter triggering on landed steps; **Kanto tables imported** (264 of 388).
- **Battle-return results object** (§17) — the battle emits, the overworld
  applies. Never the battle engine mutating save state.
- Battle transitions incl. Mugshot (no portrait asset concept exists).
- Shiny — rolled at creation time, displayed on send-out.

### Phase 7 — Menus and screens

- Start menu; Bag and Party (**head start** — M25h-1.4/1.5 built both).
- **Summary screen built once**, shared with M26E4: INFO / SKILLS / BATTLE
  MOVES reproduced exactly, **fourth page slot kept parameterised and empty**.
- One PC only — the Pokémon Center terminal. No bedroom PC.
- **Options** (§16): TEXT SPEED, BATTLE STYLE, FRAME, Godot-native control
  remapping, and the in-battle speed multiplier. No BATTLE SCENE.
- Region map, Fly destinations, Pokédex area pages.

### Phase 8 — Modes and tweaks (§29)

- EXP variants **Reduced / Normal / Bonus** — a rename of the shipped
  `DifficultyMode`, mapped by value.
- **Nuzlocke mode** — fainted Pokémon cannot be revived at all.
- **Toggleable per-battle item limit** for the player.
- **In-battle speed multiplier** via `Engine.time_scale`.

### Phase 9 — Game flow and save

- Title screen (+ `ENABLE_QUICKSTART` as a dev affordance), main menu with save
  slot selection, **player naming**, starter choice. No opening cinematic.
- Save serialisation — shape already constrained by the day-one box rule.
- Hall of Fame and credits, last; they block nothing.

### Explicitly not in this sequence

Simulator game modes and difficulty (→ M35), everything in §24's OUT list
(~67,000 lines of reference source), and §28's nice-to-haves.

### ⚠ Undecided and deliberately parked

**Trainer roster-swap difficulty** (§29) — Rob undecided, and parked at no
cost: the seam is an optional variant path with fallback on one loader
function, a ten-minute retrofit whenever wanted. The only thing to protect in
the meantime is that difficulty resolution stays *outside* `BattleManager`,
which the current architecture already does. Do not build it speculatively.

---

## 31. Roadmap renumbering — ✅ APPROVED AND APPLIED *(rev 22)*

Resolves §23's roadmap-divergence item. **Applied to CLAUDE.md 2026-07-28**:
the M27 row now carries the twelve-block index, M32 and M34 are tombstone rows,
M29/M30/M33 are narrowed, M28/M31 clarified, M35 expanded, and a renumbering-
history entry records the reasoning. No downstream number moved.

### The problems it solves

1. **M27 is one milestone doing the work of nine.** Every comparable milestone
   in this project got sub-tiers (M17: 14, M18: 24, M19: bucketed, M26: 8
   themed blocks). M27 currently has none.
2. **The box rule must be day-one, but M34 owns save/load.** A genuine ordering
   conflict — the first persistent structure built is constrained by a
   milestone eight slots later.
3. **Four milestones claim work the overworld actually owns**: HM field effects
   (M32) are player traversal; PC storage (M33) is a field menu; the encounter
   *trigger* (M29) is a step-resolver concern; the relearner/daycare NPCs
   (M30/M31) are field services.

### The shape: expand M27, retire two slots, renumber nothing

Mirrors M26's own reorganisation — **uppercase block letters, deliberately
load-bearing**, so `M27E` and any historical lowercase label can never be
confused. **No downstream milestone number moves**, so every existing citation
in CLAUDE.md, `docs/decisions.md` and commit history stays valid.

| Block | Scope | Phase |
|---|---|---|
| **M27A** | Import foundation — spike, FRLG attributes, elevation table, walking skeleton. **Defines the save shape** (box rule, per-instance fidelity) | 1 |
| **M27B** | Import pipeline — 62 tilesets, 421 maps, behaviour/elevation debug overlay | 2 |
| **M27C** | Connected world — stitching, border skirt, connections, warps, map preview, escalators | 3 |
| **M27D** | Entities & NPCs — object events, movement types, trainer sight | 4 |
| **M27E** | Field moves & traversal — surf/dive/waterfall, cut/strength/rock smash/flash, forced movement, fishing ← **absorbs M32** | 3/5 |
| **M27F** | Dialogue & interaction — interaction, Dialogue Manager wiring, speaker names | 5a |
| **M27G** | Field script engine — its own block, post-specials-scoping. 30–40% of the milestone | 5b |
| **M27H** | Encounters & battle glue — triggering, Kanto tables, results object, transitions, shiny | 6 |
| **M27I** | Field UI & menus — start menu, Bag, Party, Summary, options, region map ← **absorbs PC storage from M33** | 7 |
| **M27J** | Modes & tweaks — EXP variants, Nuzlocke, item limit, speed multiplier | 8 |
| **M27K** | Game flow — title, main menu + save slots, naming, starter, Hall of Fame, credits | 9a |
| **M27L** | Save/load — serialisation and slot management ← **absorbs M34** | 9b |

### Downstream: narrowed, retired, or unchanged

| # | Disposition |
|---|---|
| **M28** Evolution | **Kept.** Note the evolution *scene* is presentation triggered from M27H's battle-return path; the mechanics stay here |
| **M29** Encounters & catching | **Kept, narrowed.** M27H owns the TRIGGER (step into grass → battle → return); M29 owns CONTENT and MECHANICS (catch maths, Repel, roaming/static). Resolves the long-standing overlap |
| **M30** Move learning & relearning | **Kept, narrowed.** The relearner/deleter/tutor NPCs are M27I; M30 owns the mechanics. M20b already built level-up learning |
| **M31** Egg/breeding | **Kept.** The daycare *access point* is M27I; breeding mechanics stay here |
| **M32** HM field effects | **RETIRED as a slot → M27E.** Tombstone row kept, per the M21 precedent |
| **M33** PC storage & Pokédex | **Narrowed to Pokédex.** PC storage → M27I |
| **M34** Save/load | **RETIRED as a slot → M27L.** Tombstone row kept. This is what resolves the box-rule conflict |
| **M35** Advanced Battle Systems | **Kept, expanded** — now explicitly also owns **simulator game modes and difficulty** (rev 14) |

### Why retire rather than renumber

Retiring a slot and keeping a tombstone row is this project's own established
move (M21). It costs one explanatory row and preserves every existing
reference; renumbering M32–M35 downward would invalidate citations across
CLAUDE.md, `docs/decisions.md` and commit messages for no benefit. The two
retirements are also the two genuine *category errors* in the current list —
HM field effects are traversal, and save cannot follow the milestone whose
state it must already constrain.

---

## 32. Object-event placement design doc — review *(rev 27)*

Reviewing `design-object-events.md` rev 1. **Verdict: architecturally sound,
feasible, and it belongs in M27D — but it needs one reframe and one factual
correction, and it surfaces a pipeline stage the roadmap does not yet account
for.**

### What it gets right

- **§4.1's split of responsibilities is exactly correct** and matches both
  source and what M24a already built: identity/party/class in the trainer
  registry, cell/elevation/facing/sight/visibility on the placement.
- **Referencing trainers by string key rather than int id is the right call**,
  and for a reason the doc does not state: `gen_trainer_data.py` assigns
  `trainer_id` as a sorted-alphabetical index, and CLAUDE.md's own M24a note
  warns that inserting a new trainer name **shifts subsequent ids on regen**.
  `trainer_key` (`TRAINER_PICNICKER_ALICIA`) is stable; the int is not.
- **`sight_range` as placement data is correct** — it is
  `trainer_sight_or_berry_tree_id` on the object event.
- Testing plan matches house conventions; non-goals are drawn sensibly.

### ⚠ Correction — §4.3 has the sprite backwards

The doc says *"Setting `trainer_id` pulls `overworld_sprite` from the
registry."* **It does not work that way, and should not.** Verified:

- `graphics_id` (e.g. `OBJ_EVENT_GFX_PICNICKER_FRLG`) sits **on the object
  event**, beside `x`/`y`/`elevation`/`movement_type`/`flag`.
- `TrainerData` carries `trainer_pic_id` — the **battle front pic** — and has
  **no overworld sprite field at all**.

This answers the doc's own §9 open question definitively: **no, and don't add
it.** The overworld sprite is a per-placement authoring choice in source; the
same trainer identity can legitimately be placed with different graphics. Keep
`graphics` on the instance (which §4.2 already does for the base NPC) and drop
the registry lookup from `TrainerNPC`.

### ⚠ Reframe — the doc is authoring-first, the project is import-first

It reads as a tool for placing events by hand. But 421 Kanto maps already carry
`object_events`, `warp_events`, `coord_events` and `bg_events`, and §0's
settled strategy is import-first-then-tweak. So the doc is **not a data-entry
tool** — it is (a) the runtime event architecture and (b) the editing surface
for what the importer emits. Same decision already made for map geometry,
applied to events.

Its six categories map cleanly onto the four source arrays: `object_events` →
NPC / TrainerNPC / ItemBall (discriminated by `graphics_id` and
`trainer_type`), `warp_events` → Warp, `coord_events` → Trigger, `bg_events` →
Sign.

### The finding that decides its value: trainer rigging is 100% automatable

**Trainer identity is not in `map.json`.** The placement carries only a
`script` label (`Route9_EventScript_Alicia`); the trainer constant lives in the
script body. That is a genuinely new pipeline stage — but a tractable one:

- A first pass searching only per-map `scripts.inc` resolved **46%**, because
  many labels live in shared files (`data/scripts/trainers_frlg.inc`).
- Indexing script labels across the **whole `data/` tree** — 17,280 labels —
  resolves **432 of 432 Kanto trainer placements (100%)**.
- The format is mechanical: `<label>::` followed by
  `trainerbattle_single TRAINER_X, <intro_text>, <defeat_text>`.

**So no hand-rigging.** The importer can emit fully-rigged `TrainerNPC` nodes —
key, sight range, sprite, cell, elevation, movement, visibility flag — and the
editor exists for tweaking and for authoring *new* content, which is where the
original story actually needs it.

### Rule A — trainer keys are OUR identifiers, and carry their roster of origin

**Adopted Step 1.** A trainer key is a name this project owns, and every one
names the roster that defined it:

| source | raw constant | canonical key | file |
|---|---|---|---|
| `src/data/trainers.party` | `TRAINER_ROXANNE_1` | `TRAINER_ROXANNE_1_RSE` | `data/trainers/TRAINER_ROXANNE_1_RSE.tres` |
| `src/data/trainers_frlg.party` | `TRAINER_LASS_ROBIN` | `TRAINER_LASS_ROBIN_FRLG` | `data/trainers/TRAINER_LASS_ROBIN_FRLG.tres` |

**The filename IS the key.** Lookup is a direct path build — no id, no scan, no
cached index.

The suffix rule lives in exactly one place, `scripts/trainer_keys.py`, imported
by both `gen_trainer_data.py` and `gen_map_import.py`. It must never be
duplicated: two copies drift, and a drifted copy points a placement at a
trainer that does not exist. The rosters are measured disjoint (the only shared
name is `TRAINER_NONE`, excluded from both), and the helper asserts that at
build time so a future expansion update that introduces a collision fails
loudly instead of resolving by dict order.

**Node names are DERIVED from the key, never styled.** A baked trainer node is
`LassRobinFrlg_40_11`, suffix included. Trimming `Frlg` for tidiness would
create a second cosmetic identity diverging from the real one — a miniature of
the two-names-per-trainer problem the no-alias clause below exists to prevent.
Origin visible in the scene tree, and greppable straight from test output to
node, are both features. Decided and closed; no code change.

**Bare, unsuffixed keys do not resolve. No alias layer, no fallback.** Two
spellings per trainer would make the origin suffix optional, which defeats it.

**Design constraint for whenever save-format work lands (M27L):** a save
references trainers **by key**, never by a minted int. The int is gone precisely
because it could not survive a roster regen; reintroducing one inside a save
file would recreate the same defect in the one place it is least recoverable —
a player's own file, which cannot be regenerated. Stated now so the future
session inherits it rather than rediscovering it.

**What this replaced, and why.** `trainer_id` was a sorted-alphabetical index
this project minted. Measured: merging the second roster changes **808 of 854
(94.6%)** existing ids, so a regen rewrites 808 files and silently repoints
anything holding one. The field is now deleted outright — not deprecated, not
kept "in case". Anything wanting a count counts the directory.

The rule generalises: **do not mint an index we own.** Use upstream's stable
identifier, or none. `trainer_class_id` is untouched precisely because it
inherits source's own enum declaration order rather than inventing a sort.

### Rule B — portrait stems are UPSTREAM's identifiers, verbatim

**Adopted Step 2.** A trainer's portrait is referenced by the reference tree's
own `graphics/trainers/front_pics/<stem>.png` filename stem, copied byte-for-byte:

| roster `Pic:` | stem | file |
|---|---|---|
| `Leader Roxanne` | `leader_roxanne` | `assets/sprites/trainers/portraits/leader_roxanne.png` |
| `RS Brendan` | `brendan_rs` | …`/brendan_rs.png` |
| `Bug Catcher Frlg` | `bug_catcher_frlg` | …`/bug_catcher_frlg.png` |

**We never add, strip, or re-case anything.** The stem's entire value is direct
traceability to the exact source file. `brendan_rs`/`may_rs` are the standing
proof: a naive `lower().replace(" ","_")` of the `Pic:` value yields
`rs_brendan`, which is not a real file. Both are pinned by test.

Hoenn stems carry no suffix and FRLG stems carry `_frlg` **only because upstream
wrote them that way**. All 180 stems in the reference are unique (measured), so
this cannot collide.

Resolution is a direct path build. `trainer_pic_id`, `TrainerPicData` and
`data/trainer_pics/` are deleted: a second minted index with the same defect as
`trainer_id` (**92.5% of pic ids shift** once the Kanto pics land, and a stale
one renders the *wrong* trainer's portrait rather than failing), plus a 93-file
table whose only job was turning that int back into a string we already had.

A missing stem fails **loudly** — a warning naming the stem and the trainer that
asked, plus a visible magenta placeholder — never a silent null.

### The Rule A / Rule B pair — the asymmetry is a decision

These two rules deliberately disagree, and the reason is worth stating so
neither gets "fixed" into matching the other:

| | Rule A (trainer keys) | Rule B (portrait stems) |
|---|---|---|
| whose identifier | **ours** | **upstream's** |
| suffix | we add `_RSE` / `_FRLG` | only what upstream already wrote |
| why | two rosters, separate files, ambiguous without it | traceability to the exact source file |

**Retiring the int id spaces is the shared pattern. It does NOT mean trainer
keys adopt Rule B's verbatim-unsuffixed form.** Trainer files are
`TRAINER_X_RSE` / `TRAINER_X_FRLG`, full stop.

The generalisation behind both: **do not mint an index we own.** Use upstream's
stable identifier, or a name we define deliberately — never a positional index.
`trainer_class_id` survives untouched precisely because it inherits source's own
enum declaration order rather than inventing a sort.

### Parked by design — two things a future session should not "fix"

**`ai_flags` is populated and intentionally unconsumed.** Every trainer carries
real flags (Roxanne: 7), but `battle_screen_shared.gd` sets
`ai.tier = TrainerAI.Tier.SMART` explicitly and never threads them through.
That is deliberate until RPG trainer battles exist — the simulator's difficulty
is a user-facing setting, not something a data file should silently override.
Wiring it is M27/M35 scope, not a bug.

**Source's numeric trainer-id partitioning is facility code only.** The ranges
(`FRONTIER_TRAINERS_COUNT`, `TRAINER_RECORD_MIXING_APPRENTICE`,
`TRAINER_PARTNER(...)`) appear exclusively in `battle_frontier.c`,
`battle_tower.c`, `battle_factory.c`, `battle_tent.c` and `battle_partner.c` —
all out of scope. Any future Battle Frontier work designs its roster selection
natively rather than resurrecting a numeric id space to inherit those ranges.

### ✅ RESOLVED — the Kanto roster is converted (was: the ⚠ blocker)

**Closed Step 4.** `gen_trainer_data.py` now reads both rosters:
`trainers.party` (854, `_RSE`) and `trainers_frlg.party` (**623**, `_FRLG`) —
1,477 trainer files. `TRAINER_LASS_ROBIN_FRLG` and its 12 corridor peers
resolve against real party data.

**623, not 624.** The earlier figure came from `grep -c "^Name:"`, which counts
`TRAINER_NONE`'s blank sentinel entry — excluded from the Kanto roster exactly
as it already was from Hoenn.

**Purely additive, which was the whole point of the Step 1 re-keying.** After
regenerating: **623 new files, 0 modified, 0 deleted.** Under the retired
`trainer_id` scheme this same merge would have rewritten **808 of 854** existing
files. The acceptance check is worth keeping for any future roster addition: if
an existing `_RSE` file changes, the key scheme has a bug.

**Three converter gaps the Kanto roster exposed**, none of which Hoenn had ever
reached:

1. **Nidoran.** `pokemon.json` names the gendered forms `Nidoran♀`/`Nidoran♂`,
   and the converter's `normalize()` strips non-alphanumerics — so **both
   collapsed to `NIDORAN` and collided**, one silently overwriting the other.
   Compounding it, the party file spells them `Nidoran F`/`Nidoran M`, matching
   neither. Latent purely because **zero Hoenn trainers use Nidoran and 19
   Kanto ones do**. Fixed with explicit aliases resolved *by symbol* from the
   data, so a pokédex renumber fails loudly instead of mis-mapping.
2. **`Faint Attack`** is the pre-Gen-VI spelling of Feint Attack — source says
   so itself: `MOVE_FAINT_ATTACK = MOVE_FEINT_ATTACK, // Pre-Gen VI name`. A
   rename, not a second move, so it resolves to the same move id 185.
3. **`Stardust`** stays unresolved, correctly. It has no `holdEffect` in source
   — a `POCKET_ITEMS` treasure with only a price — so it sits outside this
   project's held-item roster for the same reason Nugget already did.

**Portrait gap, and a correction to its size.** The reference ships **86**
`_frlg` front pics, but only **62** are referenced by any converted trainer;
the other **24 have no consumer in either roster**. So `[M26B3-1]`'s "86
sprites" is the size of the *available art*, not the size of the *gap* —
pulling 62 satisfies the whole roster. Tracked by the dangling-stem counter as
two numbers: **62 distinct stems** (the work) and **623 trainers** (the blast
radius), both returning to 0 when the sprites are pulled. **That pull is now DONE** — see below.

### ✅ Kanto portraits pulled — `[M26B3-1]` closed

All **62** referenced `_frlg` front pics are in
`assets/sprites/trainers/portraits/`, bringing the directory to **155**. Flat
copy, no decode: every source file is 64×64 palette-mode and already carries
`tRNS = 0`, so `shutil.copyfile` preserves transparency (unlike the ball sheets,
which needed explicit index-0 tagging). Verified byte-identical to source for
all 62.

**62, not 86.** The reference ships 86 `_frlg` front pics; the other **24 have
no consumer in either roster**, so they are deliberately not pulled — 86 was
always the size of the available art, not the size of the gap.

**The dangling-stem counter closes the loop it was built for.** It read 0/0
before the Kanto roster converted, **62 stems / 623 trainers** once those
trainers referenced art nobody had pulled, and **0/0** again now. A gap that
moves a number stays visible; a gap that renders as a blank portrait does not.
Its constants are updated with that history recorded at the assertion.

**The tripwire flip happened, as designed.** `m27a_step_resolver_test`'s
I.14/I.15 asserted the roster was unconverted; they now assert it resolves and
raises no warning. Proven non-vacuous by removing `TRAINER_LASS_ROBIN_FRLG.tres`
and confirming both fail.

**The 800-char indexer cap, accounted for.** The label indexer once capped each
script body at 800 characters. It was removed during the follow-up-notes pass
BEFORE this five-step sequence, and `gen_map_import.py` was first committed
already uncapped (`0611738c`) — so the capped form never existed in tracked
history, and Step 5's verification measured the uncapped one.

Measured both ways against the current code, because "the removal was probably
harmless" is not a finding:

| | capped (800) | uncapped |
|---|---|---|
| labels indexed | 17,638 | 18,315 |
| **Kanto placements resolved** | **432/432** | **432/432** |
| all-region placements resolved | 869/974 | 910/974 |
| mis-keyed (wrong trainer) | **0** | **0** |

**Uncapping was NOT necessary to reach 432/432** — the capped form scores
identically on Kanto, with zero differing placements. So the removal is
harmless for this milestone's scope, and the 432/432 claim holds under either.

It was not pointless either: the cap costs **41 Hoenn placements** (Route102's
Allen, Route103's Isabelle, Route104's Darian and 38 more), whose
`trainerbattle` sits deeper than 800 chars into a shared script file. Note the
cap did not TRUNCATE those bodies — it made the whole match fail, dropping 677
labels outright. Every one of the 41 is a MISS, never a wrong key: the cap
failed safe in every case in the tree, which is the property that mattered.

**Placements carry canonical keys.** `gen_map_import.py::trainer_key_for` routes
through the same `canonical_key()` the trainer converter uses, so an emitted
placement is `TRAINER_LASS_ROBIN_FRLG`. Re-verified at full scale with the
current importer: **432/432 Kanto trainer placements resolve, all `_FRLG`** —
none accidentally landing on an `_RSE` trainer.

**Known re-bake churn, worth knowing before reviewing any future bake.** Godot
regenerates every node's `unique_id` on each bake, so re-baking the 8 corridor
maps produced a 201-line diff of which only 26 lines are semantic (13
`trainer_key` values and the 13 node names derived from them). With `unique_id`
normalised away, **6 of the 8 scenes are byte-identical** and the two that
differ contain only the trainer changes. A real edit could hide in that churn;
diff with `sed -E 's/ unique_id=[0-9]+//'` when reviewing a re-bake.

### Regeneration chain — the expected clean-clone baseline

`assets/maps/` is a generated build input and gitignored (§1.9's
generated-vs-tracked split), so a fresh checkout has none of the 421 map JSONs
and section A of `m27a_step_resolver_test` cannot run.

| state | result |
|---|---|
| fresh checkout, as cloned | **79/79** — 12 map-data assertions gated, announced in one line |
| after `python3 scripts/gen_map_import.py all` | **91/91** |

Only the assertions that read the gitignored **JSON** gate. Section J's
round-trip checks read the baked `.tres`, which IS tracked, so they run in a
clean clone — which is why the fresh baseline rose from 62 to 79 when Change 3
landed rather than staying flat.

**The suite asserts its own arithmetic** (`Z.99`): `_total + _gated` must equal
a hardcoded `EXPECTED_TOTAL`. This retires a failure family that bit three
times — an assertion *vanishing* instead of failing, leaving a green suite with
a quietly smaller total (the 62/63 early-return, a parse error that hung Godot
with no result, and a crash-aborted function). Update `EXPECTED_TOTAL` when
adding assertions; drift is the signal, not the problem.

The suite detects the absence itself and prints
`fresh-checkout mode — 8 map-data assertions gated (run ...)`, so the smaller
total is self-explaining rather than tribal knowledge. It used to read **62/63**:
`A.01` failed on a null load and early-returned, silently taking `A.02`–`A.08`
with it. A suite that fails by design on every clean checkout teaches people to
ignore its red, so those 8 are now gated together.

**Two prerequisites a genuine fresh clone needs**, both found by actually
running this end to end rather than assuming:

1. **`reference/pokeemerald_expansion` is a git SUBMODULE** (gitlink, pinned at
   `74e40e03`). `git clone` and `git worktree add` both create the directory
   empty — run `git submodule update --init` or no generator can run at all.
2. **Fixed rev 31 — `gen_map_import.py all` used to emit unbakeable JSON.**
   `convert()` wrote the JSON before atlas resolution and only rewrote it with
   the atlas name when `render` was set, so the all-corpus mode produced maps
   the baker rejected (`missing atlas res://assets/map_atlases/_ground.png`,
   `0/8 baked`) — and the fresh-checkout announce line tells people to run
   exactly that mode, so the trap sat in the documented path. `atlas_slug()` is
   a computed string needing no image work, so the atlas name is now emitted
   for **every** map and `render` gates only PNG generation. The two
   `json.dump` sites are collapsed to one: two writers that can disagree about
   the same file is its own bug class, and these did. Guarded by `J.20`;
   verified by baking the corridor 8/8 straight from `all`-mode output.
3. Generators must be run from the checkout you intend to write to. `OUT` and
   `ATLAS_OUT` in `gen_map_import.py` were **hardcoded absolute paths into the
   main checkout**, so running it from a worktree silently wrote 421 JSONs into
   the *original* tree — the same wrong-tree-by-hardcoded-path class
   `ref_path.py` exists to kill, missed by that sweep because these are OUTPUT
   paths. Now derived from `PROJECT` **and asserted**: `assert_inside_project()`
   is the mirror of `ref_path`'s own inside-the-project guard, so a future
   refactor that breaks the derivation dies at import instead of writing 421
   files into whatever tree sits at a stale path. Verified in both directions.

**That workaround is now a tool: `scripts/check_bake_diff.py`.** It bakes to a
scratch copy, normalises `unique_id` away, diffs against the tracked scene, and
exits nonzero with a readable diff when they differ semantically:

    python3 scripts/check_bake_diff.py Route3_Frlg PalletTown_Frlg
    python3 scripts/check_bake_diff.py --all

This is the concrete detection method for the re-import-vs-hand-edits risk
§1.9 raised: a scene that is no longer reproducible is one carrying
hand-authored content a `--force` re-bake would silently overwrite. It is
**non-destructive** (the scene is restored either way) and deliberately **not
wired into the baker** — a standalone check a re-bake session runs first.
Verified in both directions: clean corridor exits 0, an injected hand-placed
node exits 1 and is named in the diff.

### Roadmap fit

| Part | Lands in |
|---|---|
| §3/§4 data model, §6 spawn/movement/despawn | **M27D** — its home |
| Importer emitting these nodes **+ the script-label indexer** | **M27B** — a new sub-task, not currently accounted for |
| §6 sight ray | **M27D** |
| §6 battle handoff via `trainer_id` | **M27H** |
| §6 interact routing (`interact_script`) | **M27F** (interaction) / **M27G** (the script it points at) |
| §5 editor tooling, §5 presets | Alongside M27D, lower priority than the runtime; overlaps §20 |

**⚠ Dependency flag on §8's order.** Step 3 is "interact handler routing
(`interact_script`)", but `interact_script` is a pointer into the field script
engine — **M27G**, the largest block in the milestone. Step 3 can only be a
stub that resolves a label and logs it until M27G lands. Worth reordering so
the trainer path (steps 4–5), which routes to an *existing* battle seam, comes
first.

### Prerequisites, answerable now

- **`TrainerRegistry` needs `@tool` plus an `all_keys()`**. It is currently a
  plain `RefCounted` with static `.tres` loaders and a private
  `_build_key_index()`; neither `@tool` nor a public id list exists. Small, but
  §5's dropdown and warnings are dead without it. (Note it loads `.tres`, not
  JSON as §5 assumes.)
- **§9's sight-frequency question — per landed step is correct**, both on the
  doc's own cost reasoning and because grid-locked movement makes "step" the
  only unambiguous unit.
- **Importer edge case**: a handful of Kanto object events carry a
  `FLAG_HIDE_*` constant in the `trainer_type` field (Seafoam and Victory Road
  boulders). Malformed-looking source data — handle it explicitly rather than
  letting it parse as a trainer.
