# M27A — Map foundation: scope

> ⚠️ **SUPERSEDED 2026-07-28 by `docs/overworld_scope.md` (rev 10).** Kept as
> history only. Everything load-bearing here — the FRLG 32-bit attribute trap,
> the binary formats, the elevation-mapping seam — is carried into the merged
> document. Its §3 spike recommendation is resolved there: import first, author
> tweaks after; the spike is not the starting point.


**Status: SCOPED, nothing built.** 2026-07-28. This is the deeper scope of the
first block in `docs/m27_recon.md`'s decomposition — the one every other block
inherits its decisions from.

---

## 0. Executive summary

- **This confirms, rather than discovers, the import decision.** ⚠️ Rob's own
  `overworldscopedetailed.md` (rev 9, §0) already states "converting reference
  maps is the primary content strategy, not hand-authoring" and already
  identifies Kanto as the target with FRLG data present. This session
  re-derived that independently instead of consulting it; what it adds is
  harder numbers and byte-level verification, **not a new conclusion**. What it
  genuinely does overturn is `m27_recon.md` §3, which said map DATA would be
  *authored* — that was wrong, and Rob's document already had it right. The
  reference contains **421 Kanto-region maps** — Pallet Town, Oak's Lab,
  Viridian, Pewter, Cerulean, Cerulean Cave, Celadon department stores — with
  complete layouts, blockdata, tilesets, palettes, object events, warps and
  connections. Kanto is **importable**, not authorable-from-scratch (§1).
- **The one finding here that is genuinely absent from Rob's document: the
  FRLG 32-bit metatile-attribute trap** (§2.3). That document discusses
  metatile behaviours as a subsystem but never mentions the attribute bit
  layout or the Hoenn/FRLG width difference, so a reader working only from it
  would write a 16-bit reader and silently misparse every Kanto tileset.
- **Every format involved is already understood**, and the binary parts are
  the same class of GBA tile/tilemap decode this project has now done
  successfully five times (§2).
- **One real trap: FRLG metatile attributes are 32-bit, Hoenn's are 16-bit**,
  with different masks and shifts. Since this project is Kanto, the FRLG
  variant is the relevant one, and a Hoenn-shaped reader would silently
  misparse every Kanto tileset (§2.3).
- **The existing `pallettown.tscn` spike should be retired**, not extended —
  it is hand-painted against third-party metatile art and cannot represent
  collision, elevation or behaviour (§3).
- Proposed: **A1–A5** (§5), with decisions for Rob in §6.

---

## 1. Kanto is importable — the scope-defining finding

`m27_recon.md` §3 concluded that because this project is "Kanto with an
original story", map data would be authored, extrapolating from
`[M26B3-1]`'s trainer-roster reasoning. **Maps are not like trainers.**

| | Count |
|---|---|
| `REGION_HOENN` maps | 518 |
| **`REGION_KANTO` maps** | **421** |
| FRLG secondary tilesets | **62** (plus `general_frlg`, `building_frlg` primaries) |

Spot-checked end to end on Pallet Town: `PalletTown_Frlg`,
`PalletTown_PlayersHouse_1F/2F_Frlg`, `PalletTown_ProfessorOaksLab_Frlg`,
`PalletTown_RivalsHouse_Frlg` all present, each with a real layout entry,
`map.bin` blockdata, `border.bin`, and named primary/secondary tilesets whose
art and palettes exist on disk.

**This does not make the story or the NPC scripts imported.** The distinction
that matters:

- **Geometry and art — IMPORTABLE.** Town layouts, building interiors,
  tilesets, collision, elevation, warps, connections.
- **Content and meaning — AUTHORED.** Which NPC stands where and what they say,
  trainer rosters, encounter tables, story triggers.

So M27A (geometry) is largely a **conversion pipeline**, while M27C/M27D
(NPCs, scripts) remain authoring work. That is a materially smaller and more
mechanical M27A than the high-level pass assumed, and it is the main reason to
scope this block first.

---

## 2. The formats — all understood

### 2.1 Per-map: `data/maps/<Name>/map.json`

Already **JSON**, human-readable, no decode needed. Carries `id`, `name`,
`layout`, `music`, `region`, `map_type`, `weather`, the allow-cycling/running/
escaping flags, `connections`, and full `object_events` / `warp_events` arrays
(each with x, y, elevation, movement type, script name, flag).

Only the header/warp/connection portions are M27A's; `object_events` belong to
M27C/M27D but are already available in the same file.

### 2.2 Per-layout: `data/layouts/layouts.json` + two `.bin` files

`layouts.json` gives `width`, `height`, `border_width/height`,
`primary_tileset`, `secondary_tileset`, and a `layout_version` (`"frlg"` for
Kanto). Alongside it: `map.bin` (blockdata) and `border.bin`.

**Blockdata is `width × height` u16s** — verified: Pallet Town is 24×20 and its
`map.bin` is exactly 960 bytes. Each u16
(`include/global.fieldmap.h:7-12`):

| Bits | Field |
|---|---|
| 0–9 | metatile id (`MAPGRID_METATILE_ID_MASK 0x03FF`) |
| 10–11 | **collision** |
| 12–15 | **elevation** |

Collision and elevation being *in the map data itself* is the key structural
point: this project does not need to author collision by hand, and Godot
physics layers are not the natural target for it (§4).

### 2.3 Per-tileset — and the FRLG trap

Each tileset directory holds `tiles.png`, `metatiles.bin`,
`metatile_attributes.bin`, and a `palettes/` directory (16 palettes).

- `metatiles.bin` — 8 tile entries × u16 per metatile (each metatile is 2×2
  tiles on each of two layers).
- `metatile_attributes.bin` — **the trap.** Hoenn uses 16-bit attributes
  (`METATILE_ATTR_BEHAVIOR_MASK 0x00FF`, layer at bits 12–15); **FRLG uses
  32-bit** (`..._MASK_FRLG 0x000001FF`, 9 behaviour bits, layer at bits
  **29–30**). Confirmed arithmetically on Pallet Town's secondary tileset:
  `metatiles.bin` 1424 B ÷ 16 = **89 metatiles**, and
  `metatile_attributes.bin` 356 B ÷ **4** = **89**. A 2-byte-per-entry reader
  would produce 178 bogus entries and silently misparse every Kanto tileset.

The **behaviour** byte is what later blocks need: it distinguishes tall grass,
water, ledges, doors, stairs and so on — i.e. it is what M27E's encounter
triggering and M27B's ledge/surf handling will read.

### 2.4 Decode precedent

Every binary piece above is the same GBA tile/tilemap shape this project has
already decoded successfully **five times**: Phase 5a backgrounds, Phase 5c's
`water.png`, M25h-4's Bag/Party frames, M26B4's sandstorm BG, and
`gen_ui_frames.py`'s reusable `decode_screen_block`. The novelty here is
metatiles (a second indirection: blockdata → metatile → 8 tiles) and per-tile
palette selection, not the fundamentals.

---

## 3. The existing spike should be retired — ⚠️ CONFLICTS WITH ROB'S DOCUMENT

**Direct contradiction, needs Rob's decision.** `overworldscopedetailed.md`
rev 9 §0 says the spike "is **adopted** as the starting point rather than
retired." This section recommends the opposite. The case for retiring is below;
note also that Rob's document is in tension with *itself* here — if the
importer is the primary content path (§0), then a hand-painted map over
third-party metatile art cannot be the starting point, because the real
`map.bin` indexes tiles that art does not contain.


`scenes/maps/pallettown.tscn` (26 June, referenced by nothing) is a Godot-4
`TileMapLayer` over a hand-pulled `New_General_PalletTown_Metatiles.png`,
hand-painted, with zero physics layers, terrain sets or custom data.

**Recommend retiring rather than extending it**, for reasons that are now
concrete rather than stylistic:

1. It is **hand-painted**, so it carries none of the real blockdata — no
   collision, no elevation, no metatile behaviours. Those exist in the
   reference and would have to be re-authored by hand for every map.
2. Its art is **third-party metatile sheet**, not the reference tilesets the
   real layouts index into — so the real `map.bin` cannot address it.
3. It targets **one** map. There are 421.

Retiring it is a decision worth recording explicitly (as with `[M26B4]`'s
sandstorm-layering call), because the file's mere existence otherwise reads as
a chosen direction to a future session.

---

## 3.5 Elevation: an unresolved seam between the two documents

Neither document covers this, and it is the one place their models genuinely
have to be reconciled before A1.

`overworldscopedetailed.md` §0 specifies **layer-derived elevation**: "a cell's
elevation is defined by which layer it's painted on," collapsed to a 5-value
enum (ground/water/upper/transition/any). That is an **authoring-first** model —
"painted art carries its logic."

But if maps are imported, elevation does not arrive as paint. It arrives as
**4 bits per cell in `map.bin`** (§2.2), values 0–15. So the importer needs an
explicit **0–15 → 5-bucket mapping table**, and must route each cell to the
right `TileMapLayer` based on that value. The two models are compatible — the
importer can do the routing — but the mapping table itself is specified
nowhere, and getting it wrong silently produces maps whose bridges and
underpasses are subtly unwalkable.

Rob's document does defend the 5-value collapse well (collision semantics are
equality-plus-wildcards with no ordering, so the enum is sufficient for
*movement*), and explicitly accepts the single-bridge-deck limitation. The gap
is not the collapse — it is that nothing says which raw values collapse to
which bucket.

---

## 4. Godot mapping — the one genuinely open technical question

The natural Godot target is a `TileMapLayer` per map layer with a generated
`TileSet`. Two things do **not** map cleanly and need deciding in A1:

- **Collision.** Source stores it as 2 bits per *metatile* in the map data, and
  movement is grid-based and tile-tested — it is not physics-body collision.
  Godot physics layers would be the wrong tool; a **custom data layer** (or a
  parallel lookup array) queried by the movement code is far closer to source
  and much cheaper.
- **Elevation.** 4 bits per metatile driving bridge/underpass layering and
  movement permission. Godot has no native equivalent; it is per-tile metadata
  plus rules in M27B.

Both argue for **generating TileSets and per-map data from the reference**
rather than authoring in Godot's editor — which is also what makes 421 maps
tractable.

---

## 5. Proposed sub-phases

- **A1 — Format decision and a single vertical slice.** Decide the Godot
  representation (TileSet generation, collision/elevation as custom data),
  then prove it end to end on **one** real map — Pallet Town — rendered from
  real reference data. Retire the spike here.
- **A2 — Tileset conversion pipeline.** A `gen_*` script converting a
  reference tileset (tiles + metatiles + attributes + palettes) into a Godot
  `TileSet`, handling the FRLG attribute width and per-tile palette selection.
- **A3 — Map conversion pipeline.** `map.json` + `layouts.json` + `map.bin` +
  `border.bin` → a Godot map scene/resource, including collision, elevation and
  behaviour as queryable data.
- **A4 — Map loading and the border.** Runtime loading, the border-block fill
  around map edges, and the camera.
- **A5 — Connections and warps.** Map-to-map connections and warp events —
  the point at which more than one map exists at once.

Sequencing note: A1 deliberately produces a *throwaway-quality* slice whose
purpose is to validate the representation before A2/A3 industrialise it.

---

## 6. Decisions for Rob

1. **Import Kanto, or author maps?** §1 shows importing is available and far
   cheaper. Recommend importing geometry and authoring content — but this is
   the decision the whole block rests on, and it is genuinely yours: an
   original story might want original town layouts.
2. **How many maps, and when?** 421 exist. A1–A5 need only one. Converting all
   Kanto up front versus on demand is a separate call.
3. **Retire the `pallettown.tscn` spike?** §3 recommends yes, explicitly.
4. **Does the same import logic extend to Hoenn's 518 maps** if ever wanted, or
   is Kanto-only an explicit constraint worth baking into the pipeline?
