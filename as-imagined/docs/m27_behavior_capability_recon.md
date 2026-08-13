# M27 — Metatile behavior → capability layer recon

**Status:** recon only. Nothing implemented, no corpus change, no importer
change. Rev 1, 2026-07-30.

**Direction being scoped (Rob's):** behavior stays stored as imported `MB_*`
values, so the corpus remains 1:1 quotable against pokefirered. Gameplay code
stops switching on `MB_*` identities and instead queries a derived capability
layer — composable tags per behavior, e.g. `MB_TALL_GRASS -> {grass,
encounter_source, rustles}`. Systems ask *"is this cell an encounter source?"*,
never *"is this cell MB_TALL_GRASS?"*.

This is a deliberate, documented deviation from source architecture. Source's
single exclusive enum flattens four concerns — surface semantics, movement
modifiers, interaction hooks, audio/VFX — into one integer per tile. We
unflatten at the QUERY layer only; storage stays flat and faithful.

Every number below was measured this session against all 421 imported maps.

---

## ⚠️ Two premises in the brief that did not survive checking

**1. There is NO per-cell ledge direction data.** The brief says "our overlay
already carries per-cell ledge direction data". The overlay *displays* a
per-cell ledge direction, but that value is DERIVED at read time —
`StepResolver.cell_info` scans `LEDGE_FOR`'s four entries against the cell's own
behavior and returns `ledge_dir`; `map_overlay.gd:765` reads that. `MapData` has
no ledge array (fields verified directly: `metatile`, `collision`, `elevation`,
`behavior`, `layer_type`, `provenance`, `attr_explicit`, `connections`,
`border`, `border_layer_type` — no ledge).

This materially changes §5's decision: it is not "tile tag vs existing cell
data", it is "tile tag vs a NEW per-cell array". One option is free, the other
costs a format field.

**2. HM field effects are M27E, not M30.** M32 was retired and absorbed into
**M27E — Field moves & traversal** (surf/dive/waterfall, cut/strength/rock
smash/flash). M30 is Move learning & relearning. Corrected in §3.

---

## PART 1 — INVENTORY

### 1. Per-behavior occurrence across all 421 maps

230,619 cells. `NAME_BY_ID` has 240 entries; **83 occur, 157 never do.**

Top 12 cumulative is **97.463%** — the recalled "97.5%" was rounded, and the
83 figure is confirmed exactly.

| # | id | behavior | cells | % | cum % | maps |
|---|---|---|---|---|---|---|
| 1 | 0 | `MB_NORMAL` | 143,605 | 62.269 | 62.269 | 420 |
| 2 | 8 | `MB_CAVE` | 32,292 | 14.002 | 76.272 | 98 |
| 3 | 21 | `MB_OCEAN_WATER` | 31,501 | 13.659 | 89.931 | 64 |
| 4 | 2 | `MB_TALL_GRASS` | 5,303 | 2.299 | 92.230 | 43 |
| 5 | 44 | `MB_FAST_WATER` | 2,831 | 1.228 | 93.458 | 12 |
| 6 | 50 | `MB_IMPASSABLE_NORTH` | 2,125 | 0.921 | 94.379 | 85 |
| 7 | 200 | `MB_CYCLING_ROAD_PULL_DOWN` | 2,041 | 0.885 | 95.264 | 1 |
| 8 | 33 | `MB_SAND` | 1,491 | 0.647 | 95.911 | 20 |
| 9 | 12 | `MB_MOUNTAIN_TOP` | 1,119 | 0.485 | 96.396 | 13 |
| 10 | 59 | `MB_JUMP_SOUTH` | 962 | 0.417 | 96.813 | 36 |
| 11 | 45 | `MB_CYCLING_ROAD_WATER` | 751 | 0.326 | 97.139 | 1 |
| 12 | 23 | `MB_SHALLOW_WATER` | 747 | 0.324 | **97.463** | 16 |

**The long tail, in full (71 behaviors, 2.537%).** Listed explicitly because
"the tail is small" is exactly the assumption that hides a case:

`MB_COUNTER` 729 · `MB_POND_WATER` 635 · `MB_ROCK_STAIRS` 358 ·
`MB_SOUTH_ARROW_WARP` 283 · `MB_POKEMON_CENTER_BOOKSHELF` 240 ·
`MB_ANIMATED_DOOR` 203 · `MB_SIGNPOST` 189 · `MB_ICE` 189 · `MB_BOOKSHELF` 163 ·
`MB_LADDER` 142 · `MB_NORTHWARD_CURRENT` 142 · `MB_PORTHOLE` 140 ·
`MB_BLINKING_LIGHTS` 117 · `MB_PUDDLE` 116 · `MB_PAINTING` 99 ·
`MB_NON_ANIMATED_DOOR` 97 · `MB_KITCHEN` 92 · `MB_REGION_MAP` 82 ·
`MB_WINDOW` 82 · `MB_DOWN_RIGHT_STAIR_WARP` 82 · `MB_CABINET` 80 ·
`MB_WATERFALL` 80 · `MB_NEATLY_LINED_UP_TOOLS` 75 ·
`MB_CYCLING_ROAD_PULL_DOWN_GRASS` 66 · `MB_IMPASSABLE_EAST` 65 ·
`MB_AQUA_HIDEOUT_WARP` 64 · `MB_COMPUTER` 52 · `MB_SPIN_DOWN` 52 ·
`MB_SPIN_UP` 51 · `MB_STOP_SPINNING` 49 · `MB_PC` 45 ·
`MB_SOUTHWARD_CURRENT` 45 · `MB_SPIN_LEFT` 45 · `MB_EASTWARD_CURRENT` 42 ·
`MB_DOWN_LEFT_STAIR_WARP` 41 · `MB_JUMP_WEST` 41 ·
`MB_POWER_PLANT_MACHINE` 40 · `MB_TELEPHONE` 39 · `MB_JUMP_EAST` 39 ·
`MB_SPIN_RIGHT` 38 · `MB_UP_RIGHT_STAIR_WARP` 37 · `MB_HOT_SPRINGS` 37 ·
`MB_EAST_ARROW_WARP` 36 · `MB_POKEMON_CENTER_SIGN` 36 ·
`MB_WEST_ARROW_WARP` 34 · `MB_MT_PYRE_HOLE` 31 · `MB_TELEVISION` 27 ·
`MB_UP_LEFT_STAIR_WARP` 26 · `MB_POKEMART_SIGN` 26 · `MB_IMPASSABLE_WEST` 25 ·
`MB_BLUEPRINTS` 25 · `MB_CUP` 22 · `MB_FOOD` 22 · `MB_INDIGO_PLATEAU_SIGN_1` 22 ·
`MB_INDIGO_PLATEAU_SIGN_2` 21 · `MB_UP_ESCALATOR` 20 ·
`MB_CABLE_CLUB_WIRELESS_MONITOR` 18 · `MB_BATTLE_RECORDS` 18 ·
`MB_DOWN_ESCALATOR` 18 · `MB_NORTH_ARROW_WARP` 16 · `MB_STRENGTH_BUTTON` 15 ·
`MB_FOOD_SMELLS_TASTY` 13 · `MB_ADVERTISING_POSTER` 12 · `MB_QUESTIONNAIRE` 12 ·
`MB_BURGLARY` 11 · `MB_THIN_ICE` 9 · `MB_IMPASSABLE_SOUTH` 9 ·
`MB_TRAINER_TOWER_MONITOR` 8 · `MB_DRESSER` 8 · `MB_TRASH_CAN` 7 ·
**`MB_BRIDGE_OVER_OCEAN` 1**

That last one — a single cell in the entire region — is the shape of case a tag
vocabulary has to survive without acquiring a first-class tag for it. See §8's
escape hatch.

### 2. Current consumers, and what each actually asks

Grepped every behavior read outside the generated table and the test suite.
**The live surface is smaller than it looks: four call sites, three questions.**

| Site | Reads | Question shape |
|---|---|---|
| `step_resolver.gd:119` | `behavior_at(to)` vs `LEDGE_FOR[dir]` | **identity, single** — is the target tile the ledge facing this way |
| `step_resolver.gd:146-147` | `behavior_at(from)` and `behavior_at(to)` vs `EXIT_BLOCKED[dir]` / `ENTRY_BLOCKED[dir]` | **set membership** — 4-element arrays, two-sided (§1.7) |
| `step_resolver.gd:184` | `NAME_BY_ID.has(beh)` | **validity** — is this a defined behavior at all |
| `step_resolver.gd:202,227` | `behavior_at(cell)` → `cell_info` | **passthrough** — exposes raw id + name + derived `ledge_dir` |
| `map_overlay.gd:249,751-759,930` | `info["behavior"]` | **presentation only** — colour lookup and legend text |

Notes that matter for the API:
- `BLOCKED_*` are already **arrays, not single ids** — `BLOCKED_NORTH` is
  `[MB_IMPASSABLE_NORTH, MB_IMPASSABLE_NORTHEAST, MB_IMPASSABLE_NORTHWEST,
  MB_IMPASSABLE_SOUTH_AND_NORTH]`. So the directional-block concern is *already*
  a set-membership query wearing an identity costume. It is the cheapest
  possible first migration.
- `LEDGE_*` are single ids (`LEDGE_SOUTH := MB_JUMP_SOUTH`).
- `MapManager.behavior_at` / `MapData.behavior_at` are plumbing, not consumers —
  they return the raw int and would keep doing so.
- `ELEVATION_TO_PRIORITY` (`map_data.gd:278`, `overworld_entity.gd:48`) lives in
  the same file but is keyed on ELEVATION, not behavior. **Out of scope** — it
  is not part of this surface.

**Importer-side, and deliberately excluded from the direction.**
`gen_map_import.py` switches on behavior identity in three tables —
`WARP_TRIGGER_BEHAVIORS` (24 names), `ARROW_WARP_DIRS`, `EXIT_WARP_DIRS`
(:756-881). These run at IMPORT time to stamp `Warp.triggers`/`arrow_dir`/
`exit_dir`, and their whole point is that the resulting entity no longer
consults behavior at runtime (M27C C5's decoupling). They should stay identity
tables: they are the boundary where source semantics are read once and
translated, which is exactly what keeps the corpus quotable.

### 3. Planned consumers, one line each

| System | Milestone | Question it will ask a cell |
|---|---|---|
| Wild encounters | **M27H** (trigger) / **M29** (content) | "is this an encounter source, and of which kind (grass/cave/water)?" |
| Repel / encounter suppression | M29 | same query, gated on party state — no new cell question |
| Walking friendship | M27 | "did the player take a step" — **no cell question at all**; listed in the brief but it does not consult behavior |
| Surf / Dive / Waterfall | **M27E** (not M30 — see the correction above) | "is this surfable?", "is this a waterfall?", "is this dive-capable?" |
| Cut / Strength / Rock Smash / Flash | **M27E** | Cut and Rock Smash are **object events, not tiles** (§6 of `docs/m27d_recon.md`: 210 HM obstacles region-wide are `object_events`). Only `MB_STRENGTH_BUTTON` (15 cells) is genuinely a tile hook. |
| Warps / connections | **M27C — already shipped** | nothing. C5 decoupled warps from behavior deliberately; `Warp.triggers` is stamped data. Listed in the brief, but this consumer is already retired. |
| Forced movement (ice, spin tiles, cycling road) | M27E | "does this cell force a move, and in which direction?" |
| Footstep audio / VFX | unscoped (no audio system exists) | "what does stepping here sound and look like?" |

**Two of the brief's five planned consumers turn out not to need the layer**
(walking friendship, warps/connections), and one is mostly entity-side (HMs).
The real driver is encounters.

---

## PART 2 — CLASSIFICATION

### 4. Proposed tag vocabulary, and the full classification

All **83 occurring behaviors classified, 0 unclassified**. Tags are composable
sets. Cell counts are the corpus-wide totals for each tag.

**Surface semantics**

| tag | cells | % | behaviors |
|---|---|---|---|
| `encounter_source` | **72,628** | **31.493** | 6 |
| `water` | 36,927 | 16.012 | 11 |
| `surfable` | 36,027 | 15.622 | 8 |
| `cave` | 32,292 | 14.002 | 1 |
| `grass` | 5,369 | 2.328 | 2 |
| `sand` | 1,491 | 0.647 | 1 |
| `rock` | 1,119 | 0.485 | 1 |
| `ice` | 198 | 0.086 | 2 |
| `waterfall` | 80 | 0.035 | 1 |
| `hole` | 31 | 0.013 | 1 |
| `bridge` | 1 | 0.000 | 1 |

**Movement modifiers**

| tag | cells | behaviors |
|---|---|---|
| `forced_move_south` | 2,159 | 3 |
| `blocks_north` | 2,125 | 1 |
| `ledge_south` | 962 | 1 |
| `stairs` | 544 | 5 |
| `slippery` | 198 | 2 |
| `current_north` / `_south` / `_east` | 142 / 45 / 42 | 1 each |
| `blocks_east` / `_west` / `_south` | 65 / 25 / 9 | 1 each |
| `forced_move_north` / `_west` / `_east` / `_stop` | 51 / 45 / 38 / 49 | 1 each |
| `ledge_west` / `ledge_east` | 41 / 39 | 1 each |
| `breakable` | 9 | 1 |

**Interaction hooks** — `readable` 1,798 (31 behaviors) · `warp_hook` 1,099 (14)
· `talk_over` 729 (1) · `service_pc` 45 (1) · `hm_hook` 15 (1)

**Audio / VFX** — `rustles` 5,369 (2) · `footprints` 1,491 (1) ·
`splashes` 863 (2)

**Untagged: `MB_NORMAL`, 143,605 cells (62.269%).** Deliberately the empty set —
"plain ground" is the absence of every capability, not a capability. This is
worth stating because it means **the tag layer answers "no" for nearly two
thirds of the world without consulting any table**, which is both the common
case and the fast path.

**The headline for the eventual encounter work:** `encounter_source` is
**31.5% of all cells** and spans six behaviors that are otherwise unrelated
(`MB_CAVE`, `MB_OCEAN_WATER`, `MB_TALL_GRASS`, `MB_FAST_WATER`,
`MB_POND_WATER`, `MB_CYCLING_ROAD_PULL_DOWN_GRASS`). Under the identity model
every encounter call site would have to know all six and stay in step with them;
under the tag model it asks one question. **That single tag is most of the
argument for doing this at all.**

### 4b. How much composability is actually there — measured

The direction rests on the claim that source's enum flattens four concerns and
that unflattening buys something. That is testable: count how many occurring
behaviors carry more than one GAMEPLAY tag (dropping pure VFX — `rustles`,
`footprints`, `splashes` — and the entity-routable hooks of §6, since neither
would justify the layer on its own).

| | behaviors | cells | % of corpus |
|---|---|---|---|
| **≥2 gameplay tags** | **13** | 73,886 | **32.04** |
| exactly 1 | 26 | 9,643 | 4.18 |
| 0 | 44 | 147,090 | 63.78 |

The 13 in full:

| behavior | cells | tags |
|---|---|---|
| `MB_CAVE` | 32,292 | cave + encounter_source |
| `MB_OCEAN_WATER` | 31,501 | water + surfable + encounter_source |
| `MB_TALL_GRASS` | 5,303 | grass + encounter_source |
| `MB_FAST_WATER` | 2,831 | water + surfable + encounter_source |
| `MB_CYCLING_ROAD_WATER` | 751 | water + surfable |
| `MB_POND_WATER` | 635 | water + surfable + encounter_source |
| `MB_ICE` | 189 | ice + slippery |
| `MB_NORTHWARD_CURRENT` | 142 | water + surfable + current_north |
| `MB_WATERFALL` | 80 | water + surfable + waterfall |
| `MB_CYCLING_ROAD_PULL_DOWN_GRASS` | 66 | grass + encounter_source + forced_move_south |
| `MB_SOUTHWARD_CURRENT` | 45 | water + surfable + current_south |
| `MB_EASTWARD_CURRENT` | 42 | water + surfable + current_east |
| `MB_THIN_ICE` | 9 | ice + slippery + breakable |

**Read this honestly: the 13 collapse into four families** — water (8
behaviors, all `water + surfable [+ encounter_source] [+ current]`), grass (2),
ice (2), cave (1). So the composability argument reduces to two facts — *water
is surfable and an encounter source*, *grass is grass and an encounter source* —
rather than a design space. That is a real benefit and a small one, and §10b
prices the cheaper way to get it.

### 5. Ambiguous classifications — Rob decides, not me

> ## ✅ RATIFIED 2026-08-13 — (a) and (b) are both CLOSED
>
> **(a) Ledges → a per-tile TAG, not a new per-cell array.** Rob's ruling.
> The evidence below (1,042 of 1,042 ledge placements agreeing with their
> behaviour) was joined by a second and third independent per-metatile fact
> during `[M27T]`: layer type, and Fire Red's own encounter stamp, measured at
> **zero placement variance across 11,031 (pair, metatile) combinations**. That
> is now a rule rather than a case-by-case call — **per-metatile facts go on the
> tile, per-position facts (collision, elevation) go on the cell** — and it saves
> a format field whenever the ledge work starts.
>
> **(b) `encounter_source` means "CAN host", not "does host".** Rob's ruling,
> and settled by measurement rather than argument: **38 Kanto maps carry
> encounter tiles and deliberately no table**, and source's own chain returns
> before it ever asks a tile question when the map's table is null. The tile
> expresses capability; the table gates. ⚠️ `[M27T piece 4]` reduced what this
> tag has to carry — Fire Red's per-tile stamp now answers "can host" directly
> for encounters, so the tag matters for other consumers (the overlay, anything
> DexNav-shaped) rather than for the encounter trigger itself.
>
> ⚠️ **Ratifying these did NOT decide §10/§10b** — whether the capability layer
> gets built at all is still open. (a) is a storage ruling and (b) a semantics
> one; both were needed by the encounter work regardless of that.

Flagged rather than silently resolved:

**(a) LEDGES — the named hard case.** Evidence, re-measured this session across
all 421 maps:

| | |
|---|---|
| `MB_JUMP_SOUTH` | 962 cells / 36 maps |
| `MB_JUMP_WEST` | 41 / 8 |
| `MB_JUMP_EAST` | 39 / 9 |
| `MB_JUMP_NORTH` | **0 / 0** |
| total | **1,042** |
| collision | **1,042 of 1,042 are `collision = 1`** — no exception |
| elevation | **1,042 of 1,042 are `elevation = 0`** — the wildcard stratum (new finding; the earlier sweep recorded only collision) |

Two homes, and the correction in the preamble changes their relative cost:

- **Tile tag** (`ledge_south` etc. on the behavior). Free — no format change,
  no re-import, no re-bake. Ledge direction stays a property of the ART, which
  is what source does and what a painter would expect: paint the south-facing
  ledge tile, get a south ledge.
- **Per-cell array** (`MapData.ledge_dir`). Costs a new format field, a
  re-import of all 421 maps, and a `MapData` version bump. Buys the ability to
  place a ledge facing a direction its art does not depict.

**Recommendation: tile tag.** The measured data does not contain a single
counter-example — every one of the 1,042 placements agrees with its own
behavior, and direction is 3-valued in practice (north is never used). Paying a
format field and a full re-import to express a case the region never contains is
the wrong trade, and §9's authoring story covers a hand-painted ledge fine.
**But it is Rob's call**, and the argument against is real: an original-story
Kanto may want a ledge shape the FRLG tileset never drew.

**(b) `MB_CAVE` as `encounter_source`.** 32,292 cells, 14% of the corpus — it is
the second-largest behavior. Tagging it makes every cave floor an encounter
source, which matches source. But it is also plain walkable interior floor in
places, and the real gate in source is the map's own encounter table, not the
tile. **Question: does `encounter_source` mean "this tile can host encounters"
or "this tile does"?** I have modelled the former; the latter needs the map-level
table M29 owns. Getting this backwards makes 14% of the world roll encounters it
should not.

**(c) `MB_MOUNTAIN_TOP` (1,119).** Tagged `rock` on surface grounds. It may be
purely audio/VFX (footstep sound) with no gameplay meaning at all. No consumer
exists to disambiguate it yet.

**(d) `MB_HOT_SPRINGS` (37).** Tagged `water`. In source it is a healing tile in
one location. Healing is a *hook*, not a surface — but modelling it as a hook
means a first-class tag with 37 cells behind it. Candidate for §8's escape
hatch instead.

**(e) `MB_COUNTER` (729, 89 maps) as `talk_over`.** This is genuinely a
movement/interaction hybrid: it lets you talk to an NPC across it. It is the
single most common interaction-ish behavior after the readables, so it is worth
deciding deliberately rather than lumping.

**(f) `MB_SHALLOW_WATER` / `MB_PUDDLE` are `water` but NOT `surfable`.**
Modelled that way deliberately; flagging because it is a judgment call about
what `water` means (walkable-wet vs swimmable).

**(g) The `stairs` tag spans two unrelated things** — `MB_ROCK_STAIRS` (358,
cosmetic/movement) and the four `*_STAIR_WARP` behaviors (186, warp hooks). They
share a name and nothing else. Probably two tags.

**(h) Cycling-road behaviors (2,858 cells across 3 behaviors, all on ONE map).**
`MB_CYCLING_ROAD_PULL_DOWN` alone is 2,041 cells — 7th most common region-wide —
entirely on a single map this project may never implement cycling for. They are
modelled as `forced_move_south`, which is probably right, but they inflate a tag
that would otherwise be tiny.

### 6. Interaction hooks better served by the entity family

Candidates for *"delete from the tag vocabulary, route through
Sign/Warp/Trigger"*. **Listed, not decided.**

| group | behaviors | cells | % of corpus |
|---|---|---|---|
| `readable` | 31 | 1,798 | 0.780 |
| `warp_hook` | 14 | 1,099 | 0.477 |
| `talk_over` | 1 | 729 | 0.316 |
| `service_pc` | 1 | 45 | 0.020 |
| **total** | **47** | **3,671** | **1.592** |

**The ratio is the finding: 47 of 83 behaviors — 57% of the vocabulary — cover
1.59% of the world.** Routing them to entities would more than halve the tag
table for a rounding error of cells.

Two strong arguments for doing exactly that:

1. **The `warp_hook` group is already routed.** M27C C5 deliberately decoupled
   warps from behavior; `Warp.triggers`/`arrow_dir`/`exit_dir` are stamped at
   import and nothing reads behavior at runtime. Giving these 14 behaviors tags
   would create a second, unread source of truth for a question already
   answered — precisely the two-implementations-of-one-rule shape that produced
   the `check_bake_diff` false positive.
2. **The `readable` group is what `Sign` exists for.** A bookshelf's text is
   content, not terrain, and the importer already emits `bg_events` as `Sign`
   entities. A tag would say only "something is readable here" without the text.

Argument against: source genuinely does gate these on the tile, and a
hand-painted bookshelf with no `Sign` placed on it would silently do nothing.
That is a real authoring trap and §9's untagged-tile question is the same one.

---

## PART 3 — DESIGN QUESTIONS

### 7. Where the mapping lives

Two shapes:

- **Generated alongside `NAME_BY_ID`** (`gen_map_import.py` already emits
  `metatile_behavior.gd`, and `movement_types.gd`, from source). Keeps one
  generator, one file, and guarantees the tag table cannot reference a behavior
  the name table does not define.
- **Hand-maintained data file.** Tags are OUR invention, not source's — they are
  not derivable from pokefirered and never will be, so generating them means a
  generator with a large hand-authored dict inside it, which is a data file
  wearing a generator's clothes.

**Recommendation: hand-maintained `.gd` const dictionary, generated
*exhaustiveness*.** The tags are a design artifact and should read like one; but
the CHECK that every occurring behavior is classified must be generated from the
corpus, so adding a map that uses a 84th behavior fails loudly.

**The exhaustiveness check is mandatory in whatever shape**, and it must be
corpus-driven, not table-driven: iterate the behaviors that actually OCCUR
across `assets/maps/*.json`, assert each has an entry. A table-vs-table check
would pass while a newly-imported map used something unclassified.

### 8. Query API sketch

What call sites would actually use:

```gdscript
# set membership — replaces EXIT_BLOCKED/ENTRY_BLOCKED/LEDGE_FOR lookups
MetatileCapability.has_tag(beh, MetatileCapability.ENCOUNTER_SOURCE) -> bool
MetatileCapability.tags(beh) -> Dictionary          # the set, for the overlay

# directional variants, so callers never assemble tag names by string
MetatileCapability.blocks(beh, dir) -> bool
MetatileCapability.ledge_dir(beh) -> int            # -1 when not a ledge
MetatileCapability.forced_move_dir(beh) -> int      # -1 when none
```

`StepResolver` would then read `blocks()` / `ledge_dir()` instead of indexing
`EXIT_BLOCKED`/`ENTRY_BLOCKED`/`LEDGE_FOR`; encounters would read
`has_tag(beh, ENCOUNTER_SOURCE)`; `cell_info` gains a `tags` field beside the
existing `behavior`/`behavior_name`, keeping both visible.

**The escape hatch for the exotic tail.** `MB_BRIDGE_OVER_OCEAN` (1 cell),
`MB_MT_PYRE_HOLE` (31), `MB_BURGLARY` (11), `MB_HOT_SPRINGS` (37) must not each
force a first-class tag. Proposal: a `SPECIAL` tag plus a per-behavior handler
registry —

```gdscript
MetatileCapability.has_tag(beh, SPECIAL)       # "this one is exotic"
MetatileCapability.special_key(beh) -> String  # "hot_springs", "" if none
```

— so a rare case is dispatched by name at the one site that cares, and the tag
vocabulary stays about capabilities rather than accumulating a tag per oddity.
**This is what stops the vocabulary drifting back into a copy of the enum.**

### 9. M27M1 (tile custom data) and hand-painted tiles

**Current state, verified:** `map_baker._build_tileset` declares exactly one
custom data layer, named `"behavior"`, type `TYPE_INT` (`map_baker.gd:690-692`)
— and **nothing writes it and nothing reads it.** M27M1's job is to populate it.

**Store `MB_*`, derive tags at read.** Three reasons:
1. It keeps the one-source-of-truth property the whole direction rests on. A
   tile storing tags directly would be a second place capability lives, and
   changing the classification would need a re-bake of everything.
2. The layer is already typed `TYPE_INT` and named `behavior` — storing a tag
   set would need a different type and a rename.
3. Deriving is free: a dictionary lookup per query, and 62% of cells (`MB_NORMAL`)
   short-circuit to the empty set.

**Untagged hand-painted tiles — the magenta class.** A new custom metatile
(id ≥ 1024 per the M27M scope) has no behavior at all. Options:
- default to `MB_NORMAL` (0) — silently plain ground, which is *usually* right
  and silently wrong for a new ledge or a new patch of grass;
- default to a sentinel `MB_UNASSIGNED` that the exhaustiveness check reports —
  loud, and consistent with how `attr_explicit` already marks a cell whose
  collision/elevation is an inherited guess.

**Recommendation: the sentinel.** This project's own repeated lesson is that the
silent-plausible-default is the expensive one, and `attr_explicit` already
established the "defaulted vs decided" pattern for exactly this.

**How an author assigns meaning to new art:** M27M6 already scopes a behaviour
picker (a named dropdown over `NAME_BY_ID`, since Godot custom data layers are
plain ints with no enum hint). That picker is the assignment mechanism, and it
needs no change for this direction — the author still picks an `MB_*`, and the
tags follow. **A tag-first design would instead need a whole new multi-select
authoring UI**, which is a further argument for storing `MB_*`.

### 10. Migration cost, priced honestly

**Call sites that change: four, all in `step_resolver.gd`.**

| site | change |
|---|---|
| `:119` ledge check | `LEDGE_FOR[dir]` → `ledge_dir(beh) == dir` |
| `:146-147` two-sided block | two array-membership tests → `blocks(beh, dir)` |
| `:184` validity | unchanged (`NAME_BY_ID.has`) — still an identity question |
| `:202,227` `cell_info` | additive: gains `tags`, keeps `behavior`/`behavior_name` |

`map_overlay.gd`'s three reads are presentation and need no change; they could
optionally gain a tag-based mode (§ below). `MapManager.behavior_at` and
`MapData.behavior_at` are plumbing and are untouched.

**What the overlay gains.** A `CAPABILITY` mode — colour by tag rather than by
behavior identity — would make "every encounter source in this map" visible in
one glance, which the current per-behavior colouring cannot express (six
unrelated colours). Cheap: the overlay already has a mode enum, a colour table
and a legend builder, and `Mode.EVENTS` is the worked precedent for appending a
mode without shifting serialised ints.

**Confirmed zero-cost on the corpus side.** The layer is derived, so:
- **no corpus regeneration** — `assets/maps/*.json` is unchanged; behavior
  values keep their imported meaning
- **no re-bakes** — `MapData.behavior` is unchanged, so no `.tres` changes and
  no `.tscn` changes; `check_bake_diff` stays 32/32
- **no importer change** — `WARP_TRIGGER_BEHAVIORS` and friends stay identity
  tables at the import boundary by design (§2)

The only new artifact is the mapping table and its test.

---

### 10b. The cheaper alternative, recorded so the decision is a real choice

Scoping the direction properly means pricing what it is being chosen *over*.
This is not a recommendation against the layer — it is the option the numbers
above make available, written down so Decision 0 is informed rather than
implicit.

**The codebase already contains the proposed pattern.** `BLOCKED_NORTH` is a
named set of `MB_*` values queried by membership, not identity:

```gdscript
const BLOCKED_NORTH := [MB_IMPASSABLE_NORTH, MB_IMPASSABLE_NORTHEAST,
                        MB_IMPASSABLE_NORTHWEST, MB_IMPASSABLE_SOUTH_AND_NORTH]
```

Extending that style — `ENCOUNTER_SOURCES` (6 members), `SURFABLE` (8),
`FORCED_MOVE_DIRS`, `LEDGE_FOR` (exists) — covers the entire gameplay-relevant
vocabulary in roughly 8–10 arrays, added one at a time as each real caller
arrives, with no table, no vocabulary decisions and no exhaustiveness harness.

What the full layer buys **over** that:

1. **Exhaustiveness** — no occurring behavior can be silently unclassified.
   Weight this against the fact that the corpus is FIXED: 421 maps, imported
   once. New behaviors arrive only via hand-painted art, which §9's
   `MB_UNASSIGNED` sentinel already governs.
2. **One table rather than N arrays.** Real, modest at N≈8, and growing in value
   with each new consumer.
3. **The overlay `CAPABILITY` mode** (§10) — though colour-by-set-membership
   works over named sets equally well.

What it costs: an 83-entry hand-maintained table of which **47 entries exist for
1.59% of cells** (§6), its exhaustiveness harness, and the eight vocabulary
questions below — all resolved before a single consumer exists.

**The project-specific argument against building it early**, recorded because
this file's own history keeps making it: `ItemData.pocket` shipped declared and
unpopulated until `[M18-patch-1]`; `MoveData.always_critical_hit` is dormant
with zero consumers; the M26C5 type badges have been asset-ready with no
consumer since M23.11 — and, directly relevant here, `_build_tileset` **already
declares a `behavior` custom data layer that nothing writes and nothing reads**
(`map_baker.gd:690-692`). Someone scaffolded this exact seam and stopped.

**The signal that flips it:** if encounters need *which kind* of source
(grass vs cave vs water, which M29's per-terrain tables imply they will), the
named-set approach starts fragmenting into parallel arrays that must stay in
step — and that is the point at which one table is cheaper than N. Watch for it
at M27H rather than deciding it now.

## VERIFICATION PLAN (for the eventual build)

- **Exhaustiveness, corpus-driven, with a deliberate break test.** Sweep every
  behavior occurring across all 421 maps; assert each has a tag entry. Then
  remove one occurring behavior from the mapping and confirm the check FAILS and
  NAMES it. Per this project's standing rule, a check never shown to fail is not
  evidence.
- **Behavioral equivalence probe.** Pick 2–3 behaviors `StepResolver` already
  handles — recommend `MB_IMPASSABLE_NORTH` (2,125 cells, 85 maps — the
  set-membership case), `MB_JUMP_SOUTH` (962, 36 maps — the identity case) and
  `MB_JUMP_WEST` (41, 8 maps — the rare-direction case) — and assert the
  tag-mediated answer equals the identity-mediated answer **cell-for-cell across
  the whole 32-map corridor**, in every direction. That is the proof the layer is
  a refactor and not a behaviour change.
- **A negative control**: `MB_NORMAL` must return the empty tag set and
  short-circuit, confirming 62% of cells cost nothing.

---

## DECISIONS FOR ROB

0. **Build the layer now, or extend the existing named-set pattern until a
   second consumer proves the table?** (§4b, §10b) — the prior question, and the
   one the measurements bear on most directly: composability reduces to four
   families, the live consumer surface is four call sites, and two of the five
   planned consumers turned out not to query cells at all. Everything below
   assumes the answer is "build it"; if it is not, decisions 2–8 lapse until
   M27H and only decision 1 stays live.
1. **Ledges: tile tag or new per-cell array?** (§5a) — recommend **tile tag**;
   1,042/1,042 placements agree with their behavior, and the brief's premise
   that per-cell ledge data already exists turned out to be false, so the array
   option now costs a format field + full re-import.
2. **What does `encounter_source` mean** — "can host" or "does host"? (§5b)
   Affects 14% of the corpus via `MB_CAVE` alone.
3. **Route the 47 interaction-hook behaviors to entities, or tag them?** (§6)
   57% of the vocabulary, 1.59% of cells. `warp_hook`'s 14 are already routed;
   giving them tags would create a second unread source of truth.
4. **Mapping table: hand-maintained or generated?** (§7) — recommend
   hand-maintained table, generated exhaustiveness check.
5. **Untagged hand-painted tiles: default `MB_NORMAL` or a loud sentinel?** (§9)
   — recommend the sentinel, matching `attr_explicit`'s precedent.
6. **Adopt the `SPECIAL` + handler escape hatch?** (§8) Without it the
   vocabulary will drift back into a copy of the enum.
7. **Smaller calls, batched:** `MB_MOUNTAIN_TOP` gameplay or VFX (§5c) ·
   `MB_HOT_SPRINGS` tag or escape hatch (§5d) · `MB_COUNTER` (§5e) ·
   split the overloaded `stairs` tag (§5g) · what to do with the
   single-map cycling-road behaviors (§5h).
8. **Does the overlay get a `CAPABILITY` mode?** (§10) Cheap, and it is the only
   way to see "all encounter sources" at a glance.
