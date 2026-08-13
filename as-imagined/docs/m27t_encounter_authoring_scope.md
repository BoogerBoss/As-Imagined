# M27T — Wild encounter authoring

**Scoped 2026-08-12. Scope of record for the block. Every decision below is
Rob's and is recorded with its ruling; every number is measured, and the
measurement is named where it is not obvious.**

⚠️ **THE BLOCK LETTER IS M27T, NOT M27E OR M27H.** Both of those are taken —
`M27E` is Field moves & traversal (shipped through E2) and `M27H` is the wild
encounter runtime (closed). A proposal for this work arrived labelled `M27E`;
that label would collide with shipped work in every future citation.

⚠️ **PART OF THIS IS M29-SHAPED, DELIBERATELY.** The roadmap's own split is
that **M27 owns the trigger** and **M29 owns encounter content and mechanics**.
Piece 2 below (version pick, slot rates, the conversion itself) is content work
riding inside an M27 authoring block. Stated here so M29 does not later read as
double-owning it.

---

## 1. The decisions, all ruled

| # | Question | Ruling | When |
|---|---|---|---|
| 1 | Rate denominator — 1600 or 2880? | **1600** (FRLG) | Rob, 2026-08-12 |
| 2 | FireRed or LeafGreen tables? | **LeafGreen** | Rob, 2026-08-12 |
| 3 | Altering Cave's 9-table rotation? | **Out of scope — one flat table like every other map** | Rob, 2026-08-12 |
| 4 | Converter scope? | **Add a Kanto scope** | Rob, 2026-08-12 |
| 5 | Encounter trigger — behaviour or the per-tile stamp? | **Switch to the stamp**, with the hand-painted override | Rob, 2026-08-12 |
| 6 | In-Godot encounter editing? | **Required. Option C — the authored-override layer** | Rob, 2026-08-12 |
| 7 | Slot rates? | **The 15-slot curve already provided stands as final** | Rob, 2026-08-12 |
| 8 | Xanadu's `MB_LONG_GRASS` cells? | **Leave — it is a test map** | Rob, 2026-08-12 |

**Still open, not blocking:** ratifying `docs/m27_behavior_capability_recon.md`
decisions #1 (ledges as a tile tag) and #2 (`encounter_source` means "can host").
Decision 5 above reduces what #2 carries, since the stamp answers it directly
for encounters.

---

## 2. Step 0 measurements

### 2.1 The denominator is a 1.80× multiplier on the whole game

`MAX_ENCOUNTER_RATE` is **1600** in pokefirered (`src/wild_encounter.c:31`)
and **2880** in pokeemerald-expansion (`src/wild_encounter.c:36`). This project
runs FRLG's per-map rate values against Emerald's denominator, which has been
halving encounter frequency since `[M27H H2]`.

⚠️ **THE RATE VALUES DO NOT COMPENSATE — measured, because the obvious
assumption is that they would.** Kanto's land rates span 1–21 (median 7),
Hoenn's span 4–25 (median 10). Same numeric band. So the denominator alone sets
felt density, and FRLG at 1600 is the genuinely denser game.

**The cap never binds**, which is what makes this a clean linear change: the
highest rate in the whole corpus is 25, i.e. 400 after the ×16, well under
either ceiling even with a lead ability doubling it.

| map | rate | at 2880 | at 1600 |
|---|---|---|---|
| Routes 1 / 2 / 3 / 22 | 21 | 11.7%/step, ~9 steps | **21.0%/step, ~5 steps** |
| Viridian Forest | 14 | 7.8%/step, ~13 steps | **14.0%/step, ~7 steps** |

### 2.2 The FireRed/LeafGreen split is large, and we were on the wrong side of it by accident

Of the **124** FRLG map pairs, **90 differ and only 34 are identical**.

⚠️ **THE SHIPPED GAME IS ALREADY LEAFGREEN, AND NOBODY CHOSE IT.**
`gen_wild_encounters.py` never reads `base_label` and assigns straight into a
dict keyed on map, so the last entry in file order wins — and LeafGreen is
always second. Ruling 2 ratifies the accident as a decision rather than
changing behaviour.

Version-exclusive species, by map count:

| FireRed only | LeafGreen only | maps |
|---|---|---|
| Psyduck | Slowpoke | **84** |
| Seadra | Kingler | ~20 |
| Horsea | Krabby | 17 |
| Murkrow | Misdreavus | 14 |
| Oddish | Bellsprout | 13 |
| Qwilfish | Remoraid | 9 |
| Gloom | Weepinbell | 8 |
| Shellder | Staryu | 7 |
| Growlithe | Vulpix | 6 |
| Ekans | Sandshrew | 6 |
| Arbok | Sandslash | 4 |
| Weezing | Muk | 4 |
| Wooper | Marill | 4 |

⚠️ The single biggest effect (Psyduck/Slowpoke, 84 maps) lands almost entirely
on **water** encounters, which are not wired yet — which is why this was cheap
to decide now and would have been expensive to revisit after surfing ships.

**Corridor impact is near nil**: Route 3 swaps Nidoran-male and Nidoran-female
across three slots, Viridian Forest swaps Metapod and Kakuna across four. Both
species stay obtainable either way; only slot rarity moves. (Route 3's pair is
the same gendered Nidoran that caused the real `normalize()` collision at
`[M27B Step 4]` — handled by aliases since, so a callback rather than a risk.)

### 2.3 Altering Cave needs no special case at all

Six Island Altering Cave's 18 entries are **9 tables × 2 versions**, not 18
designs: table 1 is Zubat, tables 2–9 are Mareep / Pineco / Houndour /
Teddiursa / Aipom / Shuckle / Stantler / Smeargle. Hoenn's copy carries the
same 9. **In unmodified play only table 1 is reachable** — the rotation needs
e-Reader/Mystery Gift infrastructure, a standing exclusion here.

⚠️ Today both caves have collapsed to **table 9 (all Smeargle)** through the
same last-wins bug. Under "first entry per map per version" Altering Cave
simply yields Zubat at rate 7 like any other map, and Hoenn's copy disappears
entirely under the Kanto scope. **Ruling 3 costs zero lines of special-case
code.**

### 2.4 The Kanto scope is a guard, not a filter — today

All **124** LeafGreen-labelled encounter maps are already `REGION_KANTO`, zero
exceptions. So the scope changes nothing now and catches the day it would.
⚠️ It must read the `region` field from `map.json` — the same test
`gen_map_import.py` already uses — rather than inferring Kanto from the version
label, so the two can disagree loudly instead of silently agreeing.

Corpus after all four rulings: **192 mixed-region maps → 105 Kanto land maps**,
plus **50 water, 50 fishing, 14 rock smash** when those are built.

### 2.5 Two pre-existing converter defects, independent of any of this

- **Last-entry-wins** (§2.2, §2.3) — `base_label` is never read.
- **It reads the committed snapshot**, `data/wild_encounters.json`, not the
  canonical clone through `ref_path`. Byte-identical today (`md5
  d4591b46c19bf7815c3680cf7e0f18c4` both sides); it is the only generator that
  does this, and the drift is recorded nowhere.

---

## 3. The trigger — the finding this block turns on

### 3.1 The two references genuinely disagree about mechanism

Every tile carries two independent labels. **What kind of tile it is** (the
behaviour — grass, cave floor, water) and **a separate hand-set stamp saying
wild Pokémon can appear here** (none / land / water,
`METATILE_ATTRIBUTE_ENCOUNTER_TYPE`, bits 24-26, mask `0x07000000`,
`fieldmap.c:71`).

- **pokeemerald-expansion** — the project's declared first-stop reference —
  branches on the **behaviour** (`MetatileBehavior_IsLandWildEncounter`,
  `wild_encounter.c:692/740/869/890`).
- **pokefirered** branches on the **stamp**
  (`wild_encounter.c:704-707, 1092-1128`).

`[M27H H2]` ported the Emerald method, correctly, under the reference-first
rule — and pointed it at FRLG maps. **Neither method is a bug; each is right
for its own game.**

⚠️ **The Emerald 16-bit attribute layout has no encounter-type field at all**
(`fieldmap.c:106-118`, that slot is the `0xFFFFFFFF` invalid sentinel). This
stamp exists only on FRLG-format tilesets — which is every tileset this project
imports.

### 3.2 What the difference costs — all 421 maps, 230,619 cells

| | |
|---|---|
| cells by stamp | NONE 149,259 / **LAND 47,372** / **WATER 33,988** |
| maps with ≥1 land cell | **142** |
| maps with ≥1 water cell | **75** |
| stamp vs behaviour disagreement | **15,677 cells (6.8%)** |

- **Land: the behaviour rule is a strict subset.** Zero cells are
  behaviour-land where the stamp says none. But **9,711 cells are stamped LAND
  that behaviour cannot see** — 7,275 plain `MB_NORMAL`, 2,104
  `MB_IMPASSABLE_NORTH`. Concentrated in **Pokémon Mansion (all four floors,
  400–580 cells each)**, Mt Ember, Mt Moon B2F. ⚠️ **Real FRLG rolls encounters
  on the Mansion's ordinary floor tiles; we never would, despite those maps
  carrying full tables.**
- **Water: wrong in both directions.** The stamp marks 3,909 cells behaviour
  misses (`MB_FAST_WATER` 2,831, `MB_CYCLING_ROAD_WATER` 751, currents 229,
  `MB_WATERFALL` 80) and behaviour would over-trigger on 2,057
  `MB_OCEAN_WATER` cells FRLG stamps NONE. ⚠️ **The water half forces this
  question anyway** — surfing is built and water tables exist for 98 Kanto
  maps.

**Corridor impact today: exactly one map, and it has no table**
(DiglettsCave_NorthEntrance, 15 stamped cells). Nothing a player can currently
reach changes.

### 3.3 The stamp is per-metatile per-pair — so it is tile-level data

- **0 of 11,031** distinct (pair, metatile) combinations carry more than one
  stamp. Zero placement variance, like behaviour and layer type.
- But **299 of 959 bare metatile ids differ across pairs** — so it can never be
  a global id-keyed table. It is per-pair, exactly like the two sidecars that
  already exist.

### 3.4 The hand-painted override, and why Xanadu proves it

⚠️ **VERIFIED 2026-08-12 AFTER ROB CHALLENGED AN EARLIER CLAIM, AND HE WAS
RIGHT — encounters work in Xanadu today.** `MapManager.behavior_at()` reads
`MapData.behavior_at()` (`map_manager.gd:463-468`), the painted array, not the
pair sidecar. `authored_encounters.json` carries XanaduNursery at rate 21 with
15 slots. The chain is live and firing. An earlier framing implied it was
broken; it is not, and the risk was always conditional on switching.

Decoded from `XanaduNursery_data.tres` (20×18 = 360 cells, provenance
`AUTHORED` throughout):

| | |
|---|---|
| cells with a land-encounter behaviour painted | **91** |
| metatile under all 91 | **8** — the plain floor fill |
| stamp on metatile 8 (this pair) | **NONE** |
| the real grass metatile (13, stamped LAND) | appears **0** times in Xanadu |
| `attr_explicit` on those 91 cells | **7** — `BEHAVIOR_EXPLICIT` set |
| `attr_explicit` elsewhere | 3 (×137), 0 (×132) |

⚠️ **THE OVERRIDE NEEDS NO NEW DATA. The flag is already set on exactly the 91
cells that need it and nowhere else**, by Rob's own paint. So:

> **Imported cells read the stamp. Cells carrying `BEHAVIOR_EXPLICIT` derive
> from their painted behaviour.**

On imported land data this is provably identical to a pure-stamp read (§3.2:
behaviour-land is a strict subset), so the override costs zero fidelity and
preserves hand-painting as the authoring lever.

⚠️ **FLAGGED, NOT FIXED (ruling 8): Xanadu's painted value is `3 =
MB_LONG_GRASS`, not `MB_TALL_GRASS` (2).** Encounters fire either way — both
are land-encounter behaviours — but `MB_LONG_GRASS` is also in the run-block
set (`metatile_behavior.gd:537-541`), so **running is disabled on those 91
cells**. Cosmetically the art underneath is still plain floor, so the grass is
invisible. Left alone by ruling 8; Xanadu is a test map.

---

## 4. Editing — what Option C is, and what it reopens

⚠️ **THIS REOPENS D4b BY NAME.** `docs/m27m5_map_creator_scope.md:226-245`
decided (Rob, 2026-08-09) that authored encounter tables live in JSON, and
explicitly weighed and rejected **"rename-safety and Inspector editability"**.
Ruling 6 is new information that decision did not have: an editing UI is now
required, and Godot provides free undo, dirty-tracking and property
interception **only for Resources**.

Three shapes were put to Rob:

| | shape | verdict |
|---|---|---|
| A | convert all 105 tables to `.tres` | rejected — reverses D4b *and* the `pokemon.json` precedent (bulk reference data stays greppable), 105 files, no divergence guard |
| B | JSON stays truth; edit through a transient Resource, explicit write-back | rejected — custom serializer, and unsaved edits lost on deselect |
| **C** | **authored-override `.tres` layer** | **chosen** |

### C, stated exactly

- `land_encounters.json` stays **generated and never hand-edited**.
- `data/encounters/<MapName>.tres` is **this map's table, authored** — created
  by a button on the map root, seeded from the generated table when one exists
  and blank when it does not.
- Lookup is **authored → generated → none**, which is *already* what
  `WildEncounters.table_for()` does for `authored_encounters.json`. Only the
  authored layer's storage changes; Xanadu migrates across.

Why C:

- **It honours the two-layer rule as written** — full reference dataset in
  JSON, the authored subset as `.tres` — rather than reversing it.
- **Real editing over ~1–20 files, not 105.**
- ⚠️ **It dissolves the converter re-run question outright.** Generated files
  are never hand-edited, so regenerating is always safe and **no `--force`
  guard is needed** — which matters, because loose `.tres` under `data/` is
  invisible to both bake guards (`map_baker._scene_divergence` and
  `check_bake_diff` compare scene text only, verified) and has no
  `has_authored_cells()` equivalent.

Accepted cost, eyes open: **a map you take ownership of stops receiving
converter fixes.** Same trade `field_script_source/` made deliberately, and
visible, because the override is a file you created.

### From-scratch tables are the same path, not a special case

A map with no reference table (Xanadu; or **Saffron City**, one of the 38 maps
with encounter tiles and no table) seeds a blank table instead of a copy. Three
things this forces:

1. ⚠️ **A blank or half-filled table must behave as NO table.** Empty slots
   would otherwise resolve to species 0 and produce a nonsense encounter, so
   `has_table()` must report false until the table is complete.
2. **Empty slots must be loud** — the counter idiom, visible in the suite and
   in the map panel, not discovered by walking into it.
3. ⚠️ **Creating a table does not create grass.** The map still needs encounter
   tiles. Authoring order is paint the tiles, then create the table — which is
   exactly what makes the two-way mismatch check (§5, piece 6) worth surfacing
   at the map root rather than only in the suite.

### Slot rates — final

**15 slots at `[15, 15, 15, 10, 10, 10, 5, 5, 4, 4, 2, 2, 1, 1, 1]`** (ruling
7), Rob's own design call from 2026-08-04, deliberately past source's
12/`[20,20,10,10,10,10,5,5,4,4,1,1]`.

⚠️ **The PADDING rule is separately a placeholder and stays one.** Reference
tables have 12 rows; the extra three are filled by duplicating each map's three
rarest entries. Net effect per map: the commonest two species drop 20% → 15%,
the third rises 10% → 15%, and **the two rarest are tripled, 1% → 3%**. Under C
this stops needing a global answer — any map you take ownership of can have
those three slots replaced with real species in the Inspector.

---

## 5. The six pieces

| # | piece | depends on | changes play? |
|---|---|---|---|
| 1 | ✅ **Encounter density** — `MAX_ENCOUNTER_RATE` → 1600 | — | ⚠️ yes, immediately |
| 2 | ✅ **Converter rebuild** — LeafGreen, first-per-map, Kanto guard, `ref_path`, all four fields | — | yes (fixes Altering Cave, drops Hoenn) |
| 3 | ✅ **Import the stamp** — per-pair sidecar + ENCOUNTERS overlay mode | — | no |
| 4 | ✅ **Switch the trigger** — stamp + `BEHAVIOR_EXPLICIT` override | 3 | no (one corridor map, no table) |
| 5 | ✅ **Authored table layer** — `EncounterTable`/`EncounterSlot`, `data/encounters/`, migrate Xanadu | — | no |
| 6 | **The editor** — Inspector plugin, species picker, map-root panel | 5 | no |
| 7 | **Validation** — suite section, both mismatch directions baselined | grows with 5/6 | no |

**Piece 3 detail.** The stamp goes to
`assets/map_atlases/<pair>_encounter_types.json`, mirroring the existing
`<pair>_behaviors.json` / `<pair>_layer_types.json` (bare arrays indexed by
metatile id, git-tracked, emitted outside the render path,
`gen_map_import.py:1258-1288`). ⚠️ **No map regen and no re-bake** — this is
why the sidecar was chosen over a per-cell `MapData` array, which would also
have had to join M27M4's six-array `snapshot_cells`/`restore_cells`/`adopt_cell`
set or undo would tear a sync half-apart. ⚠️ Those sidecars carry an
`if not os.path.exists` **write-once guard that a re-run never refreshes** —
the `layer_types` version of that trap is already recorded at
`gen_map_import.py:1261-1262` as a *second* occurrence, so a new sidecar kind
needs its own J.20-style guard.

**Piece 6 detail.** Inspector and buttons only — **no docked panels**
(CLAUDE.md M27Q, Rob 2026-08-08) and **no `ResourceSaver` on change** (the
~5 s `EditorFileSystem` rescan that `[M27M]` already paid for). The species
picker must be **filtered/typeahead, not a plain `OptionButton`** — Rob's own
2026-08-08 call at `entity_inspector.gd:168-179` records that a 386-entry
dropdown is worse than typing, and names a filtered picker as the deferred item
that would replace it. Building it here retires that item too.

**Piece 7 detail.** ⚠️ **The obvious check is wrong.** "Every map with land
tiles has a land table" **fails 38 legitimate reference maps** — tiles without
a table is source's normal way of saying "no encounters here". Measured
buckets:

| | both | tiles, no table | table, no tiles |
|---|---|---|---|
| land | 104 | **38** | 1 (`MAP_ROUTE21_SOUTH`) |
| water | 50 | **25** | 0 |

So both directions are **counted and baselined** (the M27S
`CORRIDOR_UNRESOLVED_BASELINE` idiom), not hard failures. Hard failures are:
species resolution, rate in range, `min ≤ max`, slot-count agreement, map-name
resolution.

**Order:** 1 and 2 are independent. 3 → 4. 5 → 6. 7 grows alongside 5 and 6.

### Piece 5 as built — the authored layer

`EncounterSlot` (dex, min, max) and `EncounterTable` (map, field, rate, slots)
are Resources under `data/encounters/<Map>_<field>.tres`. **Xanadu migrated and
`data/authored_encounters.json` is retired** — two files claiming to be the
authored source, one silently ignored, is worse than either.

⚠️ **`to_runtime()` IS WHAT KEPT THIS FROM TOUCHING ANYTHING DOWNSTREAM.** It
returns the generated layer's exact dictionary, so `should_encounter`,
`build_wild_party` and every older test are unchanged — the storage swap is
invisible past `table_for()`.

⚠️ **DEX NUMBERS, NOT SPECIES KEYS**, against the original proposal. This
project already resolves species names to dex at GENERATION time and is numeric
at runtime; a key here would add a second resolution path and re-open the
dangling-key class `[M27B Step 4]`'s Nidoran collision already cost. The number
is unreadable in a raw Inspector — that is what piece 6's picker answers, not a
reason to change the storage.

⚠️ **AN INCOMPLETE TABLE IS TREATED AS NO TABLE.** A fresh one is all-zero by
construction and an unset slot would resolve to species 0, so the loader refuses
it and says why. Clamping lives in the setters, not the UI, so it holds for a
script edit and a fixture as well as a spinbox — and both directions are tested
separately, per the pair-symmetry convention.

**Section H, 14 assertions** (`EXPECTED_TOTAL` 76 → 91). Four injections, each
failing exactly its own guard:

| injection | fails |
|---|---|
| loader accepts an incomplete table | **H.14** |
| min/max clamp only one direction | H.09 |
| `to_runtime()` emits a different slot shape | **H.03** |
| filename ignores the field | H.12 |

⚠️ **TWO OF THOSE FOUR ONLY EXIST BECAUSE THE INJECTION WENT FIRST.** The
loader's completeness gate was untestable while the scan was welded to the live
directory — removing it failed nothing — so the scan was split into
`scan_authored_dir(path)` and is now driven against a throwaway `user://`
directory. And **H.03 was vacuous**: it compared top-level keys and only checked
`dex` inside a slot, so renaming `min`/`max` passed while `build_wild_party`
would have read nothing at runtime. Both are the callee-tested/caller-untested
shape this arc keeps producing — after `[M27H H4]`'s accessor, BG.10 and G.10.

⚠️ **The converter re-run question dissolves here as predicted**: generated
files are never hand-edited, so regenerating is always safe and no `--force`
guard is needed.

### Piece 2 as built — the measured delta

⚠️ **THE CONTENT DELTA IS ONE MAP, AND THAT IS THE PROOF THE REASONING WAS
RIGHT.** Four rulings landed at once, so the outcome was predicted first and
then checked:

| | before | after |
|---|---|---|
| maps in `land_encounters.json` | 192 | **105** |
| removed | — | **87, every one non-Kanto** (zero `_Frlg` maps lost) |
| added | — | 0 |
| **content changed** | — | **1 — `SixIsland_AlteringCave_Frlg`, Smeargle → Zubat** |
| `slot_rates` | — | unchanged |

The 123 ordinary split maps did not move because last-wins was *already*
selecting LeafGreen; only the 18-entry map could change. Idempotent —
byte-identical on re-run.

New sibling files, all Kanto-scoped and LeafGreen: `water_encounters.json` (50
maps), `fishing_encounters.json` (50, carrying `rod_groups`),
`rock_smash_encounters.json` (14). ⚠️ **Separate files, not one combined table**
— each field's runtime consumer arrives at a different time, and keeping
`land_encounters.json`'s shape untouched is what let the rebuild land with
**zero runtime changes**. ⚠️ **Only land carries Rob's widened curve**; the
other three emit source's counts and rates, per his standing 2026-08-04 note
that those numbers come from him rather than being guessed.

**Break-tested, each failing exactly its own guard and nothing else:** taking
FireRed fails F.03/F.04 (the version discriminator — Murkrow vs Misdreavus,
version-exclusive across 59 Kanto land maps); restoring last-wins fails F.05
(Altering Cave back to Smeargle); and **dropping the Kanto scope makes the
generator refuse outright**, naming the 116 Hoenn maps that have encounter
tables and no LeafGreen variant — a build-time failure rather than a test one.

⚠️ **`data/wild_encounters.json` NOW HAS NO CONSUMER.** 1.0 MB, still tracked,
was the converter's input until piece 2 repointed it at the canonical clone.
Flagged for Rob rather than deleted.

### Piece 3 as built

**60 per-pair sidecars**, `assets/map_atlases/<pair>_encounter_types.json`,
bare arrays indexed by metatile id — the third of a set beside `_behaviors` and
`_layer_types`, generated by the same pass from the same attribute word. 421/421
maps re-imported with every histogram byte-identical to the recorded aggregate,
so the run changed nothing but the new files. `MapManager.encounter_type_for()`
reads them through the existing shared `_table_lookup`, and **nothing calls it
yet** — that is piece 4.

**A new `Mode.ENCOUNTERS` overlay view**, appended so serialised `mode` ints do
not repoint. LAND green, WATER blue, **NONE deliberately unpainted** (it is
64.7% of the region and filling it would bury the signal), and a pair with no
table draws a loud `?` rather than reading as a world where nothing spawns.

⚠️ **THE WRITE-ONCE GUARD IS GONE FROM ALL THREE SIDECARS, NOT JUST THE NEW
ONE.** Two of them carried `if not os.path.exists(...)`, so a re-run never
REFRESHED — a corrected extraction rule would silently leave every existing pair
on the old values, in the same file whose own comment records this bug class
hitting twice already. Output is deterministic, so the unconditional write costs
nothing: **regenerating all 421 maps produced zero changes to the existing 120
sidecars**, which also confirms none of them were stale.

**Section BG, 11 assertions** (`EXPECTED_TOTAL` 635 → 646). Four injections,
each failing exactly its own guard:

| injection | fails |
|---|---|
| emit behaviour into the stamp sidecar | BG.03, BG.04, **BG.06** |
| `-1` degraded to `0` for a missing table | BG.07, BG.08 |
| `ENCOUNTERS` inserted rather than appended | BG.09 (**and pre-existing BC.01**) |
| overlay reads the wrong tileset pair | **BG.10** |

⚠️ **BG.06 IS THE LOAD-BEARING ONE**: `building_frlg__pokemon_mansion_frlg`
metatile 672 is `MB_NORMAL` **and** stamped LAND. Everything else in the section
would still pass if the sidecar were a copy of the behaviour table; only that
proves the two are independent — and it is literally the Pokémon Mansion case
piece 4 exists to fix.

⚠️ **BG.10/BG.11 EXIST BECAUSE THE REST OF THE SECTION IS BLIND TO THE CALLER.**
BG.04-BG.08 drive `MapManager` directly, while the overlay reaches the stamp
through its own accessor off `map_data.atlas` — a guard on the callee cannot see
a caller wired to the wrong pair or not wired at all, which is exactly how
`[M27H H4]`'s caught-Pokémon fix shipped tested and unreachable.

### Piece 4 as built — the switch

`WildEncounters.encounter_type_at(manager, gcell)` is the whole rule:
**`BEHAVIOR_EXPLICIT` → derive from the painted behaviour; otherwise read the
stamp; `-1` → fall back to behaviour.** `should_encounter` now gates on the
resolved TYPE and still takes the behaviour, because the 40% new-metatile gate
keys on the behaviour *changing* — which is true of Fire Red too
(`pokefirered/src/wild_encounter.c:566`), so the same tile is asked two
different questions for two different reasons.

⚠️ **THE `-1` FALLBACK IS A DELIBERATE DEGRADE, NOT AN OVERSIGHT.** A pair with
no sidecar means an unregenerated checkout; treating that as NONE would make a
fresh clone play as a world where nothing spawns anywhere, which reads as a
content bug rather than a missing build step. It degrades to the pre-piece-4
rule instead, and the loudness lives where it can be acted on: the overlay draws
a `?` and BG.01 asserts all 60 tables exist.

**`WATER_BEHAVIORS` was added even though water encounters are M27E**, so the
behaviour-derived fallback is symmetric — otherwise a hand-painted ocean cell
would report NONE while an imported one reported WATER. Extracted from
`sTileBitAttributes`, not reasoned from names, which matters: **12 behaviours
are surfable and carry no encounter flag** (`MB_FAST_WATER`, all four currents,
`MB_WATERFALL`, `MB_CYCLING_ROAD_WATER`…) and a name-based reading sweeps them
in.

**Section G, 12 assertions** (`EXPECTED_TOTAL` 64 → 76). Four injections, each
failing exactly its own guard:

| injection | fails |
|---|---|
| revert the trigger to the behaviour rule | **G.10, G.11** |
| ignore the hand-painted override | **G.07** |
| a missing stamp table degrades to NONE | G.12 |
| water set guessed from names (fast water counts) | G.04 |

⚠️ **G.10 WAS DECORATION ON ITS FIRST WRITING AND ONLY THE INJECTION SHOWED IT.**
As a single roll it passed ~86% of the time *with the trigger reverted* — the
roll simply missed — so it was measuring RNG, not the gate. Rewritten as zero
encounters across 400 trials, which is a claim only the type gate can satisfy.
Rule (7)'s preventive form: derive the assertion from what the WRONG version
would do.

⚠️ **G.05 IS THE PROOF THE SWITCH DID ANYTHING**, and it runs on a baked
corridor map: `DiglettsCave_NorthEntrance_Frlg` has cells the stamp marks LAND
whose behaviour is not a land-encounter tile at all — the same shape as Pokémon
Mansion's 577, on a map that already exists. Registered at a **nonzero origin**
deliberately, because at (0,0) global and local cells are equal and a missing
conversion inside `encounter_type_at` would pass anyway.

**Nothing a player can currently reach changed**: the one corridor map that
differs carries no encounter table.

⚠️ **THE ENCOUNTERS OVERLAY WAS WRONG UNTIL THIS TIER FIXED IT, AND IT WAS FOUND
BY ASKING WHAT A HUMAN WOULD SEE.** Piece 3 wrote the view against the raw
stamp; piece 4 added the override and did not repoint it — so the view drew
Xanadu Nursery's 91 painted grass cells as EMPTY while the game encountered on
them, which is the single most misleading thing it could have shown. **Third
caller-not-updated instance in this arc**, after `[M27H H4]`'s `caught_pokemon()`
accessor and BG.10 itself.

Fixed by extracting `WildEncounters.resolve_encounter_type(map_data, x, y)` and
having BOTH the runtime and the overlay call it — one rule, two callers, rather
than the two hand-kept copies that already cost this project a permanent
`check_bake_diff` false positive. The view now also **outlines any cell whose
behaviour a human chose**, which is useful on its own: it is the difference
between "this grass came with the tileset" and "I put it here". G.13 pins that
the two sides cannot drift apart again.

---

## 6. Deliberately not here

- **Repel and the post-battle immunity window** — declined by Rob 2026-08-03
  against that session's own recommendation, recorded at
  `wild_encounters.gd:8-15`. Not reinstated.
- **Altering Cave's 8 other tables** (ruling 3).
- **A docked panel** of any kind.
- **Charts.** A `find_species.py`-style query script is in scope; visualisation
  is not.
- **Runtime encounter mechanics beyond the trigger** — M29's.

---

## 7. Prior art this must not contradict

| source | what it says |
|---|---|
| `docs/m27m5_map_creator_scope.md:226-245` | D4b — authored tables in JSON. **Reopened by ruling 6, by name.** |
| `docs/m27_behavior_capability_recon.md` | decisions #1/#2 still open; §5(b)'s `encounter_source` question is answered "can host" by §2/§3 measurement here |
| `docs/m27_next_step_recon.md` §5 | Rob's six M27H decisions, incl. the Repel refusal |
| CLAUDE.md, M27Q | no docked panels; rules live outside the plugin |
| CLAUDE.md, data format | two layers — full dataset JSON, implemented subset `.tres` |
| `[M27M]` | no `ResourceSaver` on change; writes on explicit buttons |
