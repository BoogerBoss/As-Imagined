# M33 Recon — Pokédex

Step 0 scoping pass. No game code touched, no `.tres` files created. Every
claim below is cited against `/home/rob/GodotAsImagined/reference/pokeemerald_expansion`
(file:line) or against this project's own current source — nothing here is
from general Pokémon-modding memory.

## TL;DR

- The reference Pokédex is a real, split-file system in this rh-hideout fork:
  `src/pokedex.c` (5,924 lines, the main RSE-style screen), `src/pokedex_area_screen.c`
  (habitat/area screen), `src/pokedex_cry_screen.c` (dedicated cry-waveform
  screen), `src/pokedex_area_region_map.c` (a thin adapter reusing
  `region_map.c`'s own rendering), plus an entirely alternate HGSS-style UI
  (`src/pokedex_plus_hgss.c`, build-config-gated, `POKEDEX_PLUS_HGSS = FALSE`
  by default — not relevant here). **This reference build genuinely compiles
  as FRLG** (`make firered`/`make leafgreen` targets are real, not
  hypothetical), so Kanto-native dex numbering, `IS_FRLG`-branching
  functions, and the regional/national split are all live, non-emulated
  behavior in this exact checkout — not "Hoenn code repurposed for Kanto."
- **The seen/owned model is real per-save-file state** — two bit arrays in
  `SaveBlock1` (`dexSeen[]`/`dexCaught[]`), read/written by one function,
  `GetSetPokedexFlag` (`src/pokedex.c:4513-4540`) — and this project's own
  `[M27L]` save work never built any equivalent structure. This is the one
  hard, unavoidable ordering dependency M33 has on another milestone (§3.1).
- **The area screen reads the real, live wild-encounter table** (`gWildMonHeaders[]`,
  same array `[M27H]` already imports), not a separate curated habitat data
  file (§1.6). This project's own encounter data pipeline is real and
  already covers this: `[M27H H1]` shipped `data/land_encounters.json`
  (real per-map species tables, generated, **192 of Kanto's 262 encounter
  maps**, region-wide, not corridor-limited) — but **water/fishing/rock-smash
  tables are still only a raw, unprocessed dump** (`data/wild_encounters.json`),
  the exact "imported but not generated into a per-map lookup" state
  `[M27H]`'s own recon already flagged for land encounters before H1 built
  `gen_wild_encounters.py`. A real area page needs that same treatment
  extended to the other three encounter types.
- **A real, needed correction to CLAUDE.md's own current M33 roadmap line**
  ("M33 keeps the Pokédex itself, including the area pages that read from
  M29's encounter tables"): **the encounter-table data pipeline lives in
  M27H, not M29.** M29 itself (status `` `---` ``, genuinely unbuilt) never
  owned any encounter *data* — its own roadmap row's remaining real scope,
  after `[M27H H1-H5]` shipped triggering/catching/fleeing/the real
  capture-rate formula, is narrower than the row's own text still implies
  (catch-rate maths already shipped under `[M27H H4]`; what's left is Repel
  and roaming/static encounters — see §3.2 for the full reconciliation).
  M33's area pages are **not blocked on M29 at all** — they're blocked on a
  small, well-precedented extension to M27H's own already-real pipeline.
- **This project's own `data/pokemon.json` (386 species, confirmed by direct
  read) is missing every field a real Pokédex entry needs except weight**:
  no height, no category/genus text, no dex flavor/description text, no
  footprint, no size-comparison scale data. `weight` *is* present (added by
  `[M19-pre1]`'s `gen_weight_data.py`, parsed the same way this recon
  recommends the missing fields be pulled — see §2.1).
- **Zero audio infrastructure exists anywhere in this project** (confirmed
  repeatedly elsewhere — `[M26B7]`, `[M23.11]`) — cry-on-view is a real,
  already-known blocker, not a new finding, and should ship as a disclosed
  silent no-op exactly like every other cosmetic-audio gap in this project.
- **The reference models exactly one real upgrade tier** — the Regional→National
  Dex switch (`FLAG_SYS_NATIONAL_DEX`, `EnableNationalPokedex`,
  `src/event_data.c:82-97`) — and no separate "expanded search" tier exists
  anywhere in `pokedex.c`. Given this project's single-region, Kanto-only
  overworld scope (`[M27B]`: 421 Kanto maps, no other region ever planned),
  whether this tier is even meaningful here is a real open decision (§7,
  item 1), not something safe to silently port or silently drop.
- **The region map is a real, separate system** (`src/region_map.c`, general
  map rendering + Fly), already scoped under **M27I**, not M33 — CLAUDE.md's
  own M27I roadmap row already lists "region map" explicitly. The Pokédex
  area screen only ever *reuses* region_map's rendering machinery through a
  thin adapter (`src/pokedex_area_region_map.c`, 40 lines) — it never
  duplicates it. The boundary in CLAUDE.md's own roadmap table is already
  correct; `docs/overworld_scope.md`'s own Phase-7 prose just lists them
  side-by-side without restating the split, which reads as more ambiguous
  than it is (§3.3).
- **The Emerald UI Pack — already this project's established asset route for
  Bag/Party/Summary — ships a real Pokédex kit too**: `Graphics/UI/Pokedex/`
  (27 real files: `bg_list`/`bg_info`/`bg_area`/`bg_search` + 6 search-filter
  variants, seen/owned pokéball icons, list/search cursors, a spinning
  pokéball sprite) plus a full assembly recipe, `Plugins/Emerald UI
  Pack/005_Pokedex.rb` (382 lines), at the project's own already-adopted
  512×384 (=2× canvas) convention. **One real gap, the same shape M26E4 already
  found for Summary**: the recipe references `icon_types`/`icon_hw` bitmaps
  the pack does not actually ship (§4.1) — covered for free by this
  project's own already-pulled type badges (zero consumers since M23.11,
  same asset M26E4's own Summary work is *also* waiting to finally consume).
- Proposes **M33a** (data pipeline: height/category/description/footprint/
  scale) → **M33b** (seen/owned save-state, coordinated with M27L) →
  **M33c** (national dex list screen, pack-styled) → **M33d** (species
  detail/info screen) → **M33e** (area screen, extending M27H's encounter
  pipeline) → **M33f** (cry screen, ships as a disclosed silent no-op until
  audio exists). 7 decisions for Rob in §7.

---

## 1. Reference facts (with citations)

### 1.1 Core implementation files — real, split, and FRLG-live

Confirmed via direct read, not assumed from vanilla-pokeemerald memory:

| File | Role |
|---|---|
| `src/pokedex.c` (5,924 lines) | Main RSE-style Pokédex screen — list, info page, search, cry-button dispatch |
| `src/pokedex_plus_hgss.c` (8,814 lines) | Alternate HGSS-style UI, gated `POKEDEX_PLUS_HGSS` (`include/config/pokedex_plus_hgss.h:4`, default `FALSE`) — a build-time config choice, not a save-file unlock; not modeled here |
| `src/pokedex_area_screen.c` | The "where is this species found" habitat screen |
| `src/pokedex_area_region_map.c` (40 lines) | Thin adapter loading `region_map.c`'s own per-region graphics tables onto the dex area screen's background layer |
| `src/pokedex_cry_screen.c` | Dedicated cry-listening screen with a waveform visualization |
| `include/pokedex.h` (27 lines) | Public API: `ResetPokedex`, `GetSetPokedexFlag`, `GetNationalPokedexCount`, `GetRegionalPokedexCount`, `GetKantoPokedexCount`, `GetHoennPokedexCount`, `DrawFootprint`, `HasAllKantoMons`/`HasAllHoennMons`/`HasAllRegionalMons`/`HasAllMons`, `CB2_OpenPokedex` |
| `include/constants/pokedex.h` (1,567 lines) | `enum NationalDexOrder`/`KantoDexOrder`/`HoennDexOrder`, `FOREACH_SPECIES_IN_KANTO_DEX_ORDER`/`..._HOENN_...` macros, `FLAG_GET_SEEN`/`FLAG_GET_CAUGHT`/`FLAG_SET_SEEN`/`FLAG_SET_CAUGHT` (:1558-1564), `DEX_MODE_HOENN`/`DEX_MODE_NATIONAL` (:1552-1556) |

**This checkout genuinely builds as FRLG**, not just Emerald with Kanto data
bolted on: `include/constants/global.h:67-78` — `#ifdef FIRERED` /
`#ifdef LEAFGREEN` both set `IS_FRLG 1`; the `Makefile`'s `make firered`/
`make leafgreen` targets are real build targets, not documentation. Every
`IS_FRLG`-branching function cited below is live, reachable code in this
exact reference tree.

### 1.2 Species dex-entry data — the real struct fields, and where each lives

`include/pokemon.h:421-459`, the "Pokédex data" section of `struct SpeciesInfo`:

```c
u8 categoryName[13];                        // :422 — "Seed", "Lizard", etc.
enum NationalDexOrder natDexNum:16;         // :425
u16 height;                                  // :426 — decimeters
u16 weight;                                  // :427 — hectograms
u16 pokemonScale; u16 pokemonOffset;        // :428-429 — size-comparison silhouette scaling
u16 trainerScale; u16 trainerOffset;        // :430-431
const u8 *description;                      // :432 — flavor text, INLINE POINTER, not a separate table
#if P_FOOTPRINTS
const u8 *footprint;                        // :453
#endif
```

Real worked example, `src/data/pokemon/species_info/gen_1_families.h:7-41`
(Bulbasaur): `.categoryName = _("Seed")`, `.height = 7`, `.weight = 69`,
`.description = COMPOUND_STRING("Bulbasaur can be seen napping...")`,
`.pokemonScale = 356`, `.pokemonOffset = 17`.

Size-comparison scaling is read live, not baked: `GetPokemonScaleFromNationalDexNumber`/
`GetPokemonOffsetFromNationalDexNumber` (`src/pokedex.c:4911-4920`) pull
`gSpeciesInfo[nationalNum].pokemonScale`/`.pokemonOffset` and apply them via
`SetOamMatrix` (`src/pokedex.c:3855-3856`) — the silhouette-grows-to-real-size
animation on the info page.

Footprints: `void DrawFootprint(u8 windowId, enum Species species)`
(`src/pokedex.c:4811`) reads `gSpeciesInfo[...].footprint` (:4818) and
converts a 1bpp glyph to 4bpp tiles.

**Every one of these fields is absent from this project's own species data**
except weight — see §2.1.

### 1.3 Seen vs owned — real per-save-file state, not derivable from anything static

Confirmed real, not a UI-only concept:

- `include/global.h:1186-1187`: `u8 dexSeen[NUM_DEX_FLAG_BYTES]; u8
  dexCaught[NUM_DEX_FLAG_BYTES];` as fields on `SaveBlock1`
  (`gSaveBlock1Ptr`).
- `s8 GetSetPokedexFlag(enum NationalDexOrder nationalDexNo, u8 caseID)`
  (`src/pokedex.c:4513-4540`) is the single accessor — bit-indexes into
  `dexSeen[]`/`dexCaught[]`, `caseID` one of `FLAG_GET_SEEN`/`FLAG_GET_CAUGHT`/
  `FLAG_SET_SEEN`/`FLAG_SET_CAUGHT`.
- Called from 26+ sites across `pokemon.c`, `battle_script_commands.c`,
  `evolution_scene.c`, `trade.c`, `egg_hatch.c`, `dexnav.c` — confirming this
  is the canonical seen/owned gate for the whole game, not just the dex UI.
  A real, already-cited example from this project's own prior recon:
  `evolution_scene.c`'s `EVOSTATE_SET_MON_EVOLVED` sets both flags on the
  post-evolution species (`docs/m28_recon.md`'s own §1.8 citation, verbatim
  same lines).

### 1.4 National vs. regional numbering — the real split/switch mechanic

Three separate dex orderings exist as real enums, not one list with a filter:
`enum NationalDexOrder` (Kanto-first, since National Dex historically starts
there — `include/constants/pokedex.h:6-...`), `enum KantoDexOrder` (:1519),
`enum HoennDexOrder` (:1310).

`#define REGIONAL_DEX_COUNT (IS_FRLG ? KANTO_DEX_COUNT : HOENN_DEX_COUNT)`
(`include/constants/pokedex.h:1530`) — the regional/national resolution is
`IS_FRLG`-branched throughout `src/pokemon.c`'s conversion functions:
`NationalPokedexNumToSpecies`/`SpeciesToNationalPokedexNum` (:4761, :4822),
`NationalToRegionalOrder`/`NationalToKantoOrder`/`NationalToHoennOrder`
(:4779-4804), and their reverse counterparts (:4831-4873), built from
`sKantoToNationalOrder[]`/`sHoennToNationalOrder[]` tables (`src/pokemon.c:132-142`).

**The switch itself is a real save-state toggle, not automatic** — see §1.9.
`GetRegionalPokedexCount` (`src/pokedex.c:4564-4569`) branches `IS_FRLG` to
pick `GetKantoPokedexCount`/`GetHoennPokedexCount`, so the regional/national
switch genuinely changes *which species the browsable list shows*, not just
their numbering.

### 1.5 Search/filter — real, and richer than a plain alphabetical toggle

`src/pokedex.c:55-67` and `:77-85` (local enums, not exposed in the header):
search categories `SEARCH_NAME`/`SEARCH_COLOR`/`SEARCH_TYPE_LEFT`/
`SEARCH_TYPE_RIGHT`/`SEARCH_ORDER`/`SEARCH_MODE`/`SEARCH_OK`; sort orders
`ORDER_NUMERICAL`/`ORDER_ALPHABETICAL`/`ORDER_HEAVIEST`/`ORDER_LIGHTEST`/
`ORDER_TALLEST`/`ORDER_SMALLEST`, dispatched in `CreatePokedexList(u8
dexMode, u8 order)` (:2180).

Type filter offers all 18 types across **two independent slots**
(`SEARCH_TYPE_LEFT`/`SEARCH_TYPE_RIGHT`, dual-type search — :1376-1398).
Mode filter (`sPokedexModes[] = {DEX_MODE_HOENN, DEX_MODE_NATIONAL}`, :1400)
means search also toggles regional/national scope directly. Input handling:
`Task_HandleSearchParameterInput` (:5419), `Task_OpenSearchResults` (:1864).

**The Emerald UI Pack's own `bg_search*.png` files (§4.1) map directly onto
this real structure** — separate `bg_search_type`/`bg_search_color`/
`bg_search_shape`/`bg_search_size`/`bg_search_order`/`bg_search_name`
backgrounds exist in the pack for exactly this multi-parameter search screen,
confirming the pack's own art was built against this real source shape, not
a simplified guess.

### 1.6 Area/habitat screen — reads the LIVE wild-encounter table, not a separate curated file

`void DisplayPokedexAreaScreen(enum Species species, u8 *screenSwitchState,
enum TimeOfDay timeOfDay, enum PokedexAreaScreenState areaState)`
(`src/pokedex_area_screen.c:711`), called from `src/pokedex.c:3542,3567`.

Core population loop (`:336-359`): iterates `gWildMonHeaders[]` — **the same
real wild encounter table `[M27H]` already imports** (confirmed via direct
source `#include "wild_encounter.h"` at line 25) — and calls
`MapHasSpecies(&gWildMonHeaders[i].encounterTypes[gAreaTimeOfDay],
headerSectionId, species)` per map, marking the region map via
`SetAreaHasMon`/`SetSpecialMapHasMon`.

Also folds in special-case data the normal table doesn't carry: a hardcoded
`sFeebasData[]` special encounter (:314-332) and roamers
(`gSaveBlock1Ptr->roamer[i]`, :362+). A species can be explicitly hidden from
the screen via `sSpeciesHiddenFromAreaScreen[]` (:304, e.g. Wynaut/Mirage
Island). **Time-of-day matters** — indexed by `gAreaTimeOfDay` against
`encounterTypes[]` — and this project has **no in-game clock of any kind**,
already confirmed and flagged in `docs/m28_recon.md`'s own §2 (the real
`GetTimeOfDay()` is a persistent save-state RTC clock, not wall-clock; the
same-named `AnimTask_GetTimeOfDay` in this project's `[M36]` animation VM is
an unrelated coincidental namesake). This is the identical blocker M28
already flagged for `IF_TIME`/`IF_NOT_TIME` evolutions — a real, disclosed
constraint on any time-of-day differentiation in an M33 area screen, not a
new finding.

### 1.7 Shiny/form-variant display — confirmed real but narrow; no browsing-time toggle found

`u8 DisplayCaughtMonDexPage(enum Species species, bool32 isShiny, u32
personality)` (`include/pokedex.h:12`, impl `src/pokedex.c:4010`) is the
"just registered to the dex" screen shown immediately after a catch, called
from `src/battle_script_commands.c:10312` with the real caught mon's own
shininess/personality — loads the correct palette via
`LoadDexMonPalette(taskId, isShiny)` (:4026).

**No shiny toggle was found anywhere in the ordinary dex-browsing info
screen** (`Task_HandleInfoScreenInput`-adjacent code, ~:3280-3370) — confirmed
by direct read, and independently confirmed absent in `pokedex_plus_hgss.c`
(`grep -i shiny` returned nothing in that file either). **No form-variant
browsing/switching UI was found** — forms collapse to their base species for
dex purposes via `GET_BASE_SPECIES_ID(species)` inside
`NationalPokedexNumToSpecies` (`src/pokemon.c:4776`).

This project has **zero shiny concept anywhere** — already flagged under
`[M27H]`'s own roadmap scope ("Shiny — rolled at creation time, displayed on
send-out") and explicitly deferred by `[M26E3]`'s own exclusion list
("shiny indicator... defer until the sim has a shiny concept — flag, don't
build"). M33's own shiny display is therefore doubly blocked: on M27H's
shiny-generation work, and — per this section's own finding — the real
reference doesn't even show it in the ordinary browsing screen anyway, only
at catch-time.

### 1.8 Cry-on-view — real, confirmed, and this project's own already-known audio blocker

`src/pokedex.c:3358-3363`, inside the info-screen's paletted-fade state
machine:

```c
if (!gPaletteFade.active)
{
    gMain.state++;
    if (!gTasks[taskId].tSkipCry)
    {
        StopCryAndClearCrySongs();
        PlayCry_NormalNoDucking(NationalPokedexNumToSpecies(sPokedexListItem->dexNum),
                                 0, CRY_VOLUME_RS, CRY_PRIORITY_NORMAL);
    }
```

A second cry call exists inside the caught-mon display flow (:4112,
`PlayCry_Normal`). A dedicated cry-listening screen with waveform
visualization also exists (`src/pokedex_cry_screen.c`, entered via
`CryScreenPlayButton`, `src/pokedex.c:3717`).

This project has **zero audio infrastructure anywhere** — confirmed
repeatedly in this project's own history (`[M26B7]`: "this project has ZERO
audio infrastructure anywhere, flagged... still unscoped"; `[M23.11]`'s own
Phase 5 recon reserves an entire future sound pass). Not a new finding for
M33 — the correct treatment is the same disclosed-silent-no-op pattern
already established project-wide (e.g. `[M20b]`'s move-learning fanfare, or
`[M27K]`'s explicit no-fanfare-audio list).

### 1.9 Upgrade tiers — exactly one real tier: the Regional→National Dex switch

- Gate flag: `#define FLAG_SYS_NATIONAL_DEX (SYSTEM_FLAGS + 0x36)`
  (`include/constants/flags.h:1415`).
- State check: `bool32 IsNationalPokedexEnabled(void)` (`src/event_data.c:93-97`)
  — `gSaveBlock2Ptr->pokedex.nationalMagic == 0xDA && VarGet(VAR_NATIONAL_DEX)
  == 0x302 && FlagGet(FLAG_SYS_NATIONAL_DEX)`.
- Enable: `void EnableNationalPokedex(void)` (`src/event_data.c:82-91`) —
  sets the magic byte, the var, the flag, and `pokedex.mode =
  DEX_MODE_NATIONAL`.
- Triggered from real map scripts — a Hoenn/Emerald path
  (`data/maps/LittlerootTown_ProfessorBirchsLab/scripts.inc:193-197`) and a
  parallel FRLG trigger confirmed present (grep match) in
  `data/maps/PalletTown_ProfessorOaksLab_Frlg/scripts.inc` (body not fully
  read — flagged as not independently confirmed line-by-line, unlike the
  Hoenn script).
- `IsNationalPokedexEnabled()` gates dozens of call sites throughout
  `pokedex.c` (list/count/digit formatting, mode switching) and several
  unrelated systems (`trade.c`, `easy_chat.c`, `birch_pc.c`, `hall_of_fame.c`,
  `link.c`, `tv.c`).

**No separate "expanded search" or search-upgrade item/flag was found
anywhere** — searched the whole of `pokedex.c`'s search code. The only
upgrade tier is this one national/regional switch. `POKEDEX_PLUS_HGSS`
(§1.1) is a *build-time config choice*, not a save-file/in-game unlock —
worth distinguishing explicitly from a true upgrade tier.

**Whether this tier is meaningful for M33 at all is a real open question**,
not something to silently resolve: this project's overworld is Kanto-only,
single-region, with no other region ever scoped (`[M27B]`: 421 Kanto maps
imported, zero non-Kanto maps anywhere in the pipeline). The 386-species
roster spans several real generations' worth of movepool/ability data (far
more than Kanto's original 151), so whether the encounter tables/roster ever
surface a genuinely "non-native" species that would need a National-Dex-style
unlock to see listed is not something this recon resolved — see §7 item 1.

### 1.10 Region map / Fly — a real, separate module; the Pokédex only ever reuses it

`src/region_map.c` is the general-purpose region-map module: Fly menu
(`CB2_FlyMap`, `CB_HandleFlyMapInput`, `CB_ExitFlyMap`, `LoadFlyDestIcons`,
`CreateFlyDestIcons`, `TryCreateRedOutlineFlyDestIcons` — function list
`:89-118`), map cursor/zoom, player-location display. `src/field_region_map.c`
and `src/pokenav_region_map.c` are two more separate consumers (field item
use, Pokénav) — further evidence this is a shared, decoupled module, not
Pokédex-specific.

The link into the dex area screen is the thin adapter already cited in §1.1:
`src/pokedex_area_region_map.c` (40 lines, fully read) pulls
`gRegionMapInfos[regionMapType].dexMapGfx/dexMapTilemap/dexMapPalette` and
loads them onto `POKEDEX_AREA_MAP_BG` — a separate background layer from the
Fly-menu's own rendering path. `region_map.c:730` exposes `void
ShowRegionMapForPokedexAreaScreen(struct RegionMap *regionMap)` specifically
for this reuse. `src/pokedex_area_screen.c` itself (the dex-specific *logic*
— which species maps to which highlighted section) calls
`Overworld_GetMapHeaderByGroupAndId(...)->regionMapSectionId` and
`GetRegionMapType(...)`, both region-map-owned concepts it depends on but
never reimplements.

**Summary: three cooperating modules, cleanly separated** — `region_map.c`
(generic rendering + Fly, owned by M27I per CLAUDE.md's own roadmap row),
`pokedex_area_region_map.c` (a thin dex-specific graphics loader reusing
region_map's per-region tables), and `pokedex_area_screen.c` (dex-specific
logic: which species → which highlighted section, sourced from the live
encounter table). See §3.3 for how this maps onto this project's own M27I/M33
split.

---

## 2. What this project already has vs. what's genuinely missing

### 2.1 `data/pokemon.json` — the real field list, by direct read

Full field set present on every one of the 386 entries (Bulbasaur, dex 1,
shown as the worked example):

```
dex, name, base_hp, base_atk, base_def, base_spa, base_spd, base_spe,
types, catch_rate, base_friendship, gender_ratio, egg_groups,
ability1, ability2, ability_h, item_common, item_rare, growth_rate,
weight, exp_yield, ev_yield_hp, ev_yield_atk, ev_yield_def, ev_yield_spa,
ev_yield_spd, ev_yield_spe, back_anim_id, front_anim_id, front_anim_delay
```

Cross-referenced against §1.2's real struct fields, itemized:

| Real Pokédex field | Present? | Note |
|---|---|---|
| `weight` | **Yes** | Added by `[M19-pre1]`'s `scripts/gen_weight_data.py`, parsed directly from `gen_{1,2,3}_families.h` — the exact precedent §7 item 2's proposed pipeline should follow |
| `height` | **No** | Same struct, same files, never pulled |
| `categoryName` (genus, e.g. "Seed") | **No** | Not present under any field name |
| `description` (dex flavor text) | **No** | Not present under any field name |
| `pokemonScale`/`pokemonOffset` (size-comparison scale) | **No** | Not present |
| `footprint` | **No** | Not present; also gated `#if P_FOOTPRINTS` in source, not confirmed always-on at this project's config |
| cry | **No** | No audio infra exists at all (§1.8) |
| seen/caught flags | **N/A** | Real per-save-file state, not a static species field — see §2.4 |

`base_friendship`/`gender_ratio` are both real, already-populated fields not
needed by the Pokédex itself, cited here only to show this file already
carries several "dormant until a consumer exists" fields in the exact same
shape height/category/description would need — precisely the pattern
`[M18.5d Phase 1]`'s own recon found for `gender_ratio` before Attract needed
it, and the same pattern `[M20a]` found for `exp_yield`/`ev_yield_*` before
M20 needed them. Adding four more fields this way is a well-precedented,
low-risk operation in this project, not a new kind of change.

### 2.2 `PokemonRegistry`/`PokemonFactory` — the real current API surface

`scripts/data/pokemon_registry.gd` (confirmed real path — not
`scripts/battle/core/`, which does not contain this file) public functions,
by direct read: `get_species(dex) -> Dictionary`, `get_species_resource(dex)
-> PokemonSpecies`, `get_move(id)`, `get_learnset(dex)`, `get_all_species()`,
`get_learnable_moves(dex)`, `get_item(id)`, `item_id_of(constant)`,
`item_constants()`, `get_item_identity(id)`, `get_evolutions(dex)`,
`get_tm_move(tm_number)`, `get_exp_for_level(growth_rate, level)`,
`species_id_of(constant)`, `species_constants()`.

**None of these expose height/category/description/footprint/cry/scale** —
consistent with §2.1's direct data audit (there is nothing for them to
expose). `get_species(dex)` returns the raw dict as-is, so once §2.1's
fields are added to `pokemon.json`, they surface through this exact
already-existing accessor with zero new registry code — the same "the
accessor already generalizes, only the data needs populating" shape
`[M18.5j]` found for `species_name`.

`scripts/battle/core/pokemon_factory.gd` (`PokemonFactory`, 266 lines):
`build_species(dex) -> PokemonSpecies`, `create_battle_pokemon(dex, level,
move_ids, forced_nature, forced_ivs, forced_friendship, evs, ability_slot)
-> BattlePokemon`. Battle-construction only — no dex-browsing concept, and
none needed for M33 (a dex entry doesn't need a live `BattlePokemon`
instance, only the static `PokemonSpecies`/raw-dict data `get_species`
already returns).

### 2.3 Encounter-table data — real for land, raw for water/fishing/rock-smash

`[M27H H1]` shipped `scripts/gen_wild_encounters.py` → `data/land_encounters.json`,
a real, generated, per-map species/level lookup — **192 of Kanto's 262
encounter-carrying maps** (per `[M27E]`'s own header measurement: "of
Kanto's 262 encounter maps, water_mons on 98, fishing_mons on 98,
rock_smash_mons on 29"), region-wide, independent of which maps are baked
into playable scenes. Confirmed real per-map species data by direct read
(sample: `AlteringCave`, 12 species-slot entries with real
`dex`/`min`/`max` fields).

`data/wild_encounters.json` (confirmed real structure by direct read) is
**still the raw reference dump** — one `wild_encounter_groups` blob per
map, `land_mons`/`water_mons`/`rock_smash_mons`/`fishing_mons` all present
as raw structured data, but **never processed into a per-map, per-species
lookup the way `land_encounters.json` already is**. This is the exact same
state `[M27H]`'s own recon (`docs/m27_next_step_recon.md`) already
identified and flagged for land encounters before H1 built the real
generator — the file has data, but "has data" and "has a consumer-ready
lookup" are different claims, a distinction this project has already had
to correct once for this exact file.

**Consequence for M33's area screen (§1.6)**: a real area page wanting to
show *every* place a species can be found (not just land/grass encounters)
needs `gen_wild_encounters.py` extended to also emit `water_mons`/
`fishing_mons`/`rock_smash_mons` into the same per-map lookup shape — a
well-precedented, bounded piece of work, not a new investigation. See §3.2
for the full M29/M27H reconciliation this depends on.

### 2.4 Seen/owned — genuinely nothing to build on yet

No `dexSeen`/`dexCaught`-equivalent structure exists anywhere in this
project — confirmed via the same grep sweep that found `FLAG_SYS_POKEDEX_GET`/
`FLAG_SYS_POKEMON_GET` are the *only* Pokédex-adjacent state this project
currently tracks (see §5). `FlagStore` (`scripts/overworld/flag_store.gd`)
is a generic named-flag/named-var store with no species-indexed bit-array
concept at all. This is entirely `[M27L]`'s own territory — see §3.1.

---

## 3. Real dependencies / ordering constraints

### 3.1 M27L (save/load) — a genuine hard dependency, not a soft one

Seen/owned is real per-save-file state (§1.3, §2.4) — there is no way to
build a meaningful Pokédex without *something* persisting which species have
been seen/caught across a play session, and this project's own save system
is what would own that. `[M27L]`'s own shipped status (per CLAUDE.md's own
roadmap history) covers L1 (serialisation/slot round-trip) through L5 (an
honest empty-party new game) — **it never built a species-seen/owned bit
array, because nothing has needed one until now.**

The exact same situation already surfaced once, and was already resolved
with a real, Rob-approved decision, cited directly in CLAUDE.md's own M27L
L3 entry: *"the row reads `POKéDEX 0 (not yet tracked)`, visibly not a real
number... Rob's call (2026-08-03) was to show a stubbed row instead of
fabricating a count."* This confirms two things precisely: (1) Rob has
already, directly, considered and deferred this exact gap once, so M33's
own seen/owned work is not a surprise dependency — it's the thing that stub
was always waiting on; (2) `TitleScreen.SHOW_DEX_ROW` is "the one line
between the two behaviours" (source omits the row entirely until a real
Pokédex exists) — meaning M33 shipping real seen/owned data has a real,
already-identified single-line switch-over point in `title_screen.gd`, not
a redesign.

**Ordering**: M33's own save-state (a per-species seen/owned array, likely
keyed the same way this project already keys per-species data — dex number,
matching `pokemon.json`'s own convention) needs to be added to whatever
payload shape `[M27L]` established (`OverworldSession`/`SaveManager`, per
CLAUDE.md's own M27L entries) — a real, but bounded and precedented, task
touching M27L's own files, not M33's alone. This is the one dependency in
this recon that cannot be worked around or sequenced differently — flagged
explicitly per this project's own "flag, don't silently fix" rule, since
resolving it means editing another milestone's own save-shape code.

### 3.2 M29 — real status, and the correction to CLAUDE.md's own M33 line

CLAUDE.md's current M29 roadmap row (status `` `---` ``, confirmed genuinely
unbuilt — no M29-labeled status-history entries exist anywhere in this
project's own history) reads: *"M29 owns CONTENT and MECHANICS — catch-rate
maths, Repel, roaming/static encounters."*

**This is now stale, confirmed by direct cross-reference against `[M27H]`'s
own shipped status**: `[M27H H4]` ("catching") is explicitly recorded as
*"the formula, ported from `ComputeCaptureOdds`"* — the real catch-rate
maths, including the badge-malus loop and the Gen 9 low-level bonus, already
shipped under M27H, not M29. `[M27H H5]` shipped real flee-odds too. So
M29's own remaining real scope, after M27H's own work, is narrower than its
roadmap row's text still implies: **Repel and roaming/static encounters**
— both explicitly, deliberately declined by Rob when M27H was scoped
(CLAUDE.md's own M27H entry: *"Repel and the post-battle encounter-immunity
window are BOTH DECLINED — against this recon's own recommendation... a
decision, not an oversight"*).

**Consequence for M33's own roadmap line**: *"M33 keeps the Pokédex itself,
including the area pages that read from M29's encounter tables"* should
read **M27H's encounter tables** — `data/land_encounters.json` and its own
generator, `scripts/gen_wild_encounters.py` (§2.3), not anything M29 owns
or has ever produced. M29 has shipped zero data of any kind. This is a
direct, cited correction to the project's own current framing, in the same
spirit as `docs/m28_recon.md`'s own correction of the project's prior
"genus" framing — surfaced explicitly rather than silently worked around.

**Practical result: M33's area pages are NOT blocked on M29 at all.** They
depend on M27H's own already-real pipeline, extended per §2.3/§3.2 to cover
water/fishing/rock-smash — a small, bounded, well-precedented task inside
M33's own scope, not a cross-milestone wait.

### 3.3 Region map (M27I) — the boundary is already correct, just easy to misread

CLAUDE.md's own M27I roadmap row already lists "region map" as part of
M27I's scope (*"start menu, Bag, Party, Summary, options, region map"*), and
M33's own row already scopes "the Pokédex itself, including the area pages"
— matching §1.10's real source boundary precisely: region_map.c is a
separate, general module (M27I), and the Pokédex area screen is a thin,
dex-specific consumer of it (M33).

The apparent ambiguity comes entirely from `docs/overworld_scope.md`'s own
Phase 7 prose (*"Region map, Fly destinations, Pokédex area pages"*, line
2521), which lists all three side-by-side under one feature-area phase
without restating which formal M27-block/M33 split each belongs to — that
document's own phase numbering is a rough feature-grouping, not a literal
re-statement of the twelve-block M27A-L split CLAUDE.md's own roadmap table
locks in (`docs/overworld_scope.md §31`, confirmed: *"the M27 row now
carries the twelve-block index... no downstream number moved"*). **No
correction is needed to either document — the two are talking at different
levels of granularity, and CLAUDE.md's own formal table is the one that
resolves the milestone assignment.** Flagged here only because the task
explicitly asked whether this boundary needed clarifying, and it's worth
stating plainly that it does not — the ambiguity is presentational, not
substantive.

---

## 4. UI/asset and integration precedent already established

### 4.1 The Emerald UI Pack ships a real Pokédex kit — confirmed by direct inspection, not assumed

`assets/Emerald UI Pack 1.2/Graphics/UI/Pokedex/` — **27 real files**
(confirmed via directory listing, `.import`/`Zone.Identifier` metadata
excluded): `bg_list.png`/`bg_info.png`/`bg_area.png`/`bg_forms.png` (the four
main page backgrounds) plus **six dedicated search-parameter backgrounds**
(`bg_search`/`bg_search_color`/`bg_search_name`/`bg_search_order`/
`bg_search_shape`/`bg_search_size`/`bg_search_type`/`bg_search_type_18` —
mapping directly onto §1.5's real `SEARCH_*` categories), `bg_list_over`/
`bg_list_over_search` (list-row overlays), seen/owned pokéball icons
(`icon_seen.png`/`icon_own.png`/`seenown.png`), list/search cursors
(`cursor_list.png`/`cursor_search.png`), a spinning-pokéball sprite
(`pokeball.png`, 17.6 KB — real animated art, not a static icon), and
search-UI chrome (`icon_slider`/`icon_searchslider`/`icon_searchsel`/
`icon_shapes`/`overlay_area`/`overlay_areanone`/`overlay_info`).

**Confirmed at the project's own already-adopted 512×384 canvas convention**
(direct `PIL` dimension check on `bg_list.png`/`bg_info.png`/`bg_area.png`/
`bg_search.png`/`bg_forms.png` — all five exactly 512×384, matching M26A1's
own "clean 2× multiple of the Emerald UI Pack's own canvas" rationale
already used for every other pack-sourced screen).

A full assembly recipe exists too: `Plugins/Emerald UI Pack/005_Pokedex.rb`
(382 lines, Essentials-engine Ruby, same authoring convention as
`004_Party.rb`/`001_Summary.rb` — both already this project's own
established route for Party/Summary). Directly confirms the real seen/owned
two-state UI logic (§1.3) at the presentation layer too:

```ruby
if $player.seen?(species)
  if $player.owned?(species)
    pbCopyBitmap(self.contents, @pokeballOwn.bitmap, ...)
  else
    pbCopyBitmap(self.contents, @pokeballSeen.bitmap, ...)
  end
  text = sprintf("%03d%s %s", indexNumber, " ", @commands[index][:name])
else
  text = sprintf("%03d  ----------", indexNumber)   # unseen: name hidden
end
```

**One real gap, the identical shape M26E4 already found for Summary's own
type icons**: the recipe's own `pbStartScene` references
`AnimatedBitmap.new(_INTL("Graphics/UI/Pokedex/icon_types"))` and
`.../icon_hw` — **neither file exists in the pack** (confirmed: full
directory listing of all 27 real files contains no `icon_types.png` or
`icon_hw.png`). This is covered for free by this project's own
already-pulled reference type badges (`assets/sprites/battle_ui/types/`,
pulled `[M23.11]` Phase 1, "zero consumers" since — the exact same asset
M26E4's own Summary work is *also* waiting to finally consume, per its own
CLAUDE.md entry). Recommend the same resolution M26E4 already chose for the
identical gap: use the reference-pulled badges, not a fabricated
replacement.

### 4.2 Field-screen overlay architecture — an already-proven precedent, directly reusable

`[M25h-1.4]`/`[M25h-1.5]` (`ItemSelectScreen`/`SwitchSelectScreen`,
`scenes/battle/item_select_screen.gd`/`switch_select_screen.gd`) and
`[M27I I4]`/`[M27I I5-2]` (`FieldBagScreen`/`FieldPartyScreen`,
`scripts/overworld/`) both establish, and this project's own code comments
explicitly document, the same pattern verbatim: a full-viewport **child**
overlay added on top of the still-alive parent scene (battle screen or live
overworld map), never a `change_scene_to_file()` scene-tree swap. Confirmed
by direct read of `item_select_screen.gd`'s own header comment: *"This
project's `BattleManager` is a scene-tree CHILD NODE... a real
`change_scene_to_file()` swap... would FREE it along with the rest of the
old tree... Instead, this screen is a full-viewport CHILD overlay added on
top of the still-alive `battle_screen` instance."* `FieldStartMenu`
(`scripts/overworld/field_start_menu.gd`) already opens `FieldBagScreen` and
`FieldPartyScreen` this exact way from the live overworld map.

**M33's own national-dex-list + species-detail screens are the natural next
consumer of this identical pattern** — a Pokédex opened from the field start
menu is architecturally the same shape as Bag/Party (a full-screen browsable
list over the live map, with a detail sub-view one level in), not a new
architecture to design. No code changes recommended here — cited as the
established precedent to follow when M33c/d are actually built (§6).

### 4.3 `FlagStore` integration — a real, already-identified gating point, confirmed present but unset

`scripts/overworld/field_start_menu.gd:37,40,97-98` (direct read, full file):

```gdscript
enum Entry { POKEDEX, POKEMON, BAG, SAVE, EXIT }
...
if flags != null and flags.flag_get("FLAG_SYS_POKEDEX_GET"):
    out.append(Entry.POKEDEX)
```

The POKéDEX start-menu entry already exists in code and is already
correctly gated on `FLAG_SYS_POKEDEX_GET` — it simply has nowhere to go yet
(no screen exists to open). `scripts/overworld/title_screen.gd:18-25` (also
direct read) confirms the same flag gates the title screen's own CONTINUE
card row, currently shipping as an explicitly-disclosed stub (`POKéDEX 0
(not yet tracked)`, `TitleScreen.SHOW_DEX_ROW = true`), per Rob's own
2026-08-03 decision already cited in §3.1.

**Confirmed, not newly discovered**: this is exactly the integration point
CLAUDE.md's own M27I I4 entry already documents (*"`BuildNormalStartMenu`
adds POKéDEX only on `FLAG_SYS_POKEDEX_GET`... so the entries appear on
their own the moment M33 / I5 set them, with no code change here"*). M33's
own job is to (a) set this flag somewhere real (matching source's own
"receive the Pokédex from Professor Oak" trigger, which this project has
not yet built any equivalent of — likely `[M27K]`'s new-game/starter-choice
territory, not confirmed further this session) and (b) build the screen the
menu entry should open. No new flag work needed — the wiring already exists
and waits only for a real screen and a real set-site.

---

## 5. Confirmed-vs-flagged summary

**Confirmed correct, no action needed:**
- The M27I/M33 region-map boundary (§3.3) — already correctly split in
  CLAUDE.md's own roadmap table.
- `FLAG_SYS_POKEDEX_GET` gating (§4.3) — already wired, already correct,
  waiting only for a real screen.
- `weight` is already real, populated data (§2.1) — not a gap.

**Confirmed real gaps, flagged not fixed here:**
- `height`/`category`/`description`/`footprint`/size-scale data absent from
  `data/pokemon.json` (§2.1).
- No seen/owned save-state structure exists anywhere (§2.4) — a real M27L
  dependency (§3.1).
- `water_mons`/`fishing_mons`/`rock_smash_mons` are still a raw dump, not a
  generated per-map lookup (§2.3).
- Zero shiny concept anywhere (§1.7) — pre-existing, cross-milestone
  blocker on M27H.
- Zero audio infrastructure anywhere (§1.8) — pre-existing, project-wide,
  already-known.

**Corrections to the project's own current framing:**
- CLAUDE.md's M33 roadmap row's "M29's encounter tables" should read
  "M27H's encounter tables" (§3.2) — M29 has shipped no data of any kind;
  its own real remaining scope (Repel, roaming/static) is narrower than its
  row's text implies, since catch-rate maths already shipped under M27H H4.
- M33's area pages are **not blocked on M29** — the real dependency is a
  bounded extension to M27H's own already-real `gen_wild_encounters.py`
  pipeline (§2.3, §3.2).

---

## 6. Proposed sub-tier build sequence

Following this project's own established lettered-sub-tier convention
(M17n-1..11, M18a..x, M19's bucket system, M26A-H, M27A-L):

| Sub-tier | Scope | Real dependency |
|---|---|---|
| **M33a** | Data pipeline: `gen_pokedex_data.py` (mirroring `gen_weight_data.py`'s own already-proven `gen_1/2/3_families.h` extraction) pulling `height`/`categoryName`/`description`/`pokemonScale`/`pokemonOffset`/`footprint` into `data/pokemon.json`, same file, additive fields | None — self-contained, matches `[M19-pre1]`'s own precedent exactly |
| **M33b** | Seen/owned save-state: a per-species bit array (or equivalent) added to whatever payload `[M27L]` already established, plus the real set-sites (seen on encounter/battle-start, owned on catch/evolve — mirroring `evolution_scene.c`'s own both-flags-on-evolve behavior, §1.3) | **M27L** (§3.1) — genuinely cannot be built independently |
| **M33c** | National dex list screen: pack-styled (§4.1), overlay-architecture (§4.2), reads `PokemonRegistry.get_all_species()` + M33b's seen/owned state; sort/filter can start narrow (numerical only) and grow toward §1.5's fuller search later | M33a (list needs at least species name/number), M33b (seen/unseen row rendering) |
- Numeric-vs-national-dex-number question (§7 item 1) should be resolved before this ships, since it decides what the list's own primary ordering even is |
| **M33d** | Species detail/info screen: height/weight/category/description/types/(ability display already exists elsewhere, per M26E3/E4 precedent — coordinate, don't duplicate) | M33a, M33c (entry point) |
| **M33e** | Area/habitat screen: extends `gen_wild_encounters.py` to cover water/fishing/rock-smash (§2.3), reuses M27I's own region-map rendering per §1.6/§3.3's real boundary | M33d (entry point from species detail), the `gen_wild_encounters.py` extension (self-contained, no cross-milestone wait) |
| **M33f** | Cry screen: ships as a real screen with correct layout, but the "play cry" action is a disclosed silent no-op until audio infrastructure exists project-wide | None to build M33f itself; the *sound* itself is blocked project-wide, not M33-specific |

Shiny display and the National-Dex upgrade tier are both explicitly **not**
placed in this sequence — the former per §1.7's own cross-milestone block,
the latter pending §7 item 1's own decision.

---

## 7. Decisions needed from Rob

1. **Does the Regional↔National Dex split (§1.9) matter for this project at
   all?** This project's overworld is permanently Kanto-only (421 maps,
   no other region ever scoped), but the 386-species roster spans multiple
   real generations of movepool/ability data — meaning some fraction of the
   roster may never be genuinely "native" to any Kanto encounter table.
   **Options**: (A) build the real split — one "Regional" (Kanto-native, by
   whatever the project's own definition of native ends up being) list plus
   a National unlock exactly like source, or (B) skip the split entirely and
   ship one flat 386-entry list from the start, treating the whole roster
   as "the dex" with no regional/national concept at all.
   **Recommendation: (B).** Building a real regional/national split requires
   first deciding which of the 386 species count as "Kanto-native" — a
   real, non-trivial classification question this recon did not attempt to
   answer, since it's a content decision, not an engine one — for a
   mechanic whose entire purpose in the real games is bridging *between*
   regions this project will never have. A single flat list is simpler,
   ships sooner, and can always be split later if a second region is ever
   scoped.

2. **What should M33b's seen/owned data actually key on, and does it belong
   in `[M27L]`'s own payload shape directly, or as a separate M33-owned
   save-adjacent file?** Every other per-species reference in this project
   keys on dex number (`pokemon.json`'s own `dex` field). The real question
   is architectural: does this live inside the main save payload
   (`OverworldSession`/`SaveManager`'s own shape, per CLAUDE.md's M27L
   entries) the way party/bag/flags already do, or as its own lighter-weight
   file (mirroring `TeamStorage`'s own deliberate "not the main save
   payload" precedent from `[M23.5]`)?
   **Recommendation: inside the main save payload.** Seen/owned state is
   genuinely playthrough-specific (per-slot, not shareable across slots the
   way `TeamStorage`'s own simulator-profile teams deliberately are), so it
   belongs wherever party/flags/bag already live, not in a separate file —
   but this is Rob's call, since it touches M27L's own already-shipped file
   shape.

3. **Should M33 build the real search/filter system (§1.5, type/color/
   shape/size/order, all real in source and all backed by real pack art),
   or ship with a minimal numeric-only browse for the first release and
   grow search later?**
   **Recommendation: minimal first.** The pack ships all the art for the
   full search UI, so nothing here is asset-blocked — but building all six
   search parameters (color and shape in particular need new species-level
   data this project has never pulled at all, since neither appears
   anywhere in `data/pokemon.json` and neither was investigated in this
   recon) is a real scope expansion beyond M33a's own proposed field list.
   Numeric browse first keeps M33c shippable without a second data-pipeline
   pass mid-milestone.

4. **Does M33 need a real "who gave me the Pokédex" trigger, or is
   `FLAG_SYS_POKEDEX_GET` set some other way (e.g. always-on for this
   project, given it has no real "professor" NPC/story beat built yet)?**
   Real source sets this via the Professor Oak/Birch opening-sequence
   script. **Confirmed, not just assumed — the real trigger already exists
   as imported, placed data**: `scenes/maps/PalletTown_ProfessorOaksLab_Frlg.tscn`
   (lines 102-123) already carries two placed `OBJ_EVENT_GFX_POKEDEX`
   object events (`LOCALID_POKEDEX_1`/`_2`), each with `visibility_flag =
   "FLAG_HIDE_POKEDEX"` and `script_label =
   "PalletTown_ProfessorOaksLab_EventScript_Pokedex"` — and that exact
   label exists in the already-imported `data/map_scripts.json:351454`.
   This is real Kanto map data, sitting on real placed objects, right now —
   it is not running yet only because M27G (the field script engine) hasn't
   reached this specific label in its own opcode-coverage rollout (per
   CLAUDE.md's own M27F/M27G status history, coverage is measured, not
   assumed complete). This project's own `[M27K K-a]` (the starter script)
   was investigated only insofar as it touches `FLAG_SYS_POKEMON_GET`
   (starter choice) — whether the two are meant to fire together or
   separately in this project's own Kanto opening was not further traced.
   **Recommendation: no new M33-owned trigger needed at all** — the real
   trigger is already imported map data waiting on M27G's own opcode
   coverage to reach it, not a gap M33 needs to invent a substitute for.
   Confirm with whoever next advances M27G's coverage rather than building
   a parallel path.

5. **Is the size-comparison silhouette-scaling feature (§1.2,
   `pokemonScale`/`pokemonOffset`) worth building for M33d, or is it cosmetic
   enough to skip?** It's real, sourced, and the data would already be
   pulled by M33a's own proposed pipeline (it lives in the identical struct/
   files as height/weight) — so the *data* cost is zero either way; the
   question is purely whether the animated silhouette-grows-to-real-size UI
   effect is worth building.
   **Recommendation: skip for M33d's first pass, revisit as polish.** It's
   a real but purely cosmetic effect with no gameplay consequence — lower
   priority than getting height/weight/category/description text on screen
   at all.

6. **Cry-screen scope (§1.8/M33f): build the real screen now with a
   disclosed silent "no cry plays" gap, or defer the whole screen until
   audio infrastructure exists project-wide?**
   **Recommendation: build the screen now, disclosed-silent.** This matches
   the pattern already established throughout M26/M27 for every other
   audio-touching feature (ability-activation SFX, move-animation sound
   cues, fanfares) — the *screen* and its real waveform-adjacent layout
   have real value even silent, and retrofitting audio later is a "wire in
   a sound" task, not a rebuild.

7. **Footprint art (§1.2): pull the real per-species footprint glyphs now
   as part of M33a, or treat them as a nice-to-have deferred indefinitely?**
   This recon did not check whether footprint sprite data exists as a
   pullable asset in the reference tree (only that the *pointer field*
   exists in `SpeciesInfo`) — a genuine unresolved question, not silently
   assumed either way.
   **Recommendation: investigate as part of M33a's own Step 0** (a single
   follow-up grep for the real footprint glyph asset location), not decided
   here — flagged as incomplete rather than guessed at.
