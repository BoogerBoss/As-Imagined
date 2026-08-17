# M27M5c Phase 4 — Map resize

**Scoped 2026-08-13. Scope of record for the piece.** Every decision below is
Rob's and is recorded with its ruling; every number is measured against this
project's own 421 baked maps or the canonical reference checkout, and the
measurement is named where it is not obvious.

⚠️ **THE LABEL IS M27M5c PHASE 4, NOT A NEW BLOCK LETTER.** M27M5c is the
authoring-dialog arc — Phase 1 New Map, Phase 2 Connect Map, Phase 3 Go To Edge,
all shipped. This is the fourth dialog on the same toolbar, pressing the same
`MapAuthoring`-shaped rules layer, and giving it its own letter would imply a
scope it does not have.

---

## 1. The decisions, all ruled

| # | Question | Ruling | When |
|---|---|---|---|
| 1 | How far does the resize reach? | **Scene + data + neighbour guard.** In-place surgery on the open scene, all seven `MapData` arrays, and a refusal when a grow would overlap a placed map | Rob, 2026-08-13 |
| 2 | How are the new bounds positioned? | **Four edge deltas (N/S/W/E); size and offset derived.** Ruled after Rob rejected the framing of "free offset" as hand-entered — *"why can't it be calculated"* | Rob, 2026-08-13 |
| 3 | What fills cells that did not exist? | **Replicate the nearest edge row/column** | Rob, 2026-08-13 |
| 4 | Do replicated cells count as decided? | **No — values replicated, explicit bits left clear**, so every new cell reads `needs_review`. Stated by Claude as a sub-decision of #3 rather than assumed | 2026-08-13 |

**Nothing is open.** Ruling 2 is the one that changed the design: the question
as originally put offered a nine-way anchor, a free offset, and top-left-only,
and the objection was correct — an offset that a human types is an offset a
human can get wrong, and it did not need to be typed at all.

---

## 2. Step 0 — what a map actually is, measured

### 2.1 Three artifacts, and only two are sources

| Artifact | Holds | Standing |
|---|---|---|
| `scenes/maps/<Map>_data.tres` | `width`/`height` + **seven parallel row-major arrays** | Source |
| `scenes/maps/<Map>.tscn` | 3 `TileMapLayer`s + placed entity nodes | Source |
| `assets/maps/<Map>.json` | The bake input entities are built from | **Gitignored regenerable output** |

The seven arrays are `metatile`, `collision`, `elevation`, `behavior`,
`layer_type`, `provenance`, `attr_explicit` (`map_data.gd:38-96`). All are
indexed `y * width + x`, which is the whole reason a resize is not a `resize()`
— see §3.2.

### 2.2 ⚠️ The baker cannot be the resize path, and its own guards say so

Two refusals in `map_baker._bake`:

- **`:90-95`** — refuses any map holding AUTHORED cells unless `--force`.
- **`:123-130`** — refuses any scene that diverges from what a re-bake would
  produce, unless `--force`.

Between them those describe **exactly the maps somebody would want to resize**.
And the guards are right: a re-bake rebuilds entities from
`assets/maps/<Map>.json`, so it would discard every hand-tuned `sight_range`,
`movement_type` and `script_label` in the scene. The `--force` escape is not a
workaround here, it is the damage.

**Conclusion: resize does surgery on the open scene**, the way the paint brush
already does, and regenerates nothing.

### 2.3 The reference's size ceiling is a product, not a per-axis limit

`fieldmap.c:172-176` lays every loaded map into `sBackupMapData` and refuses
when:

```c
width  = mapLayout->width  + MAP_OFFSET_W;   // +15
height = mapLayout->height + MAP_OFFSET_H;   // +14
if (width * height <= MAX_MAP_DATA_SIZE)     // 10240
```

(`include/fieldmap.h:15,23-25`.)

⚠️ **This replaced an invented per-axis cap of 200 that was in the first draft
of the code.** Measured across all 421 baked Kanto maps:

| | |
|---|---|
| Maps already over the cap | **0** |
| Largest consumer | **Diglett's Cave B1F, 85x80 → 9,400 of 10,240 (92%)** |
| Widest map | 144 |
| Tallest map | 160 |

A per-axis cap would be wrong in both directions at once: it would refuse the
legitimate 24x160 shape of Route 23 and permit an illegal 144x100 one. The cap
is real, close, and binding, so the dialog shows the budget live rather than
only refusing at the edge.

### 2.4 Placed entities — 3,872 of them, and every name carries its cell

Measured over all 421 baked `.tscn`:

| Container | Nodes |
|---|---|
| `Triggers` (warps, triggers, signs) | 2,224 |
| `Entities_P2` (NPCs at ground priority) | 1,631 |
| `Entities_P1` (NPCs above the overhang plane) | 17 |
| **Total** | **3,872** |

`OverworldEntity.cell` is the authored field and `position` is derived from it
by the setter (`overworld_entity.gd:20-25`), so shifting an entity is a single
`cell` write — nothing has to touch pixels.

Node names are cell-derived (`map_baker._node_name`), and classifying all 3,872
against their own `cell` value:

- **3,865** end in exactly `_<x>_<y>`
- **7** are stacked entities carrying a `_<x>_<y>_<k>` suffix
- **0** carry no cell in the name

⚠️ **The 7 are why the rename rule needs two branches, and a naive one would
corrupt them.** `Warp_6_7_2` does not end with `_6_7` — it ends with `_7_2` —
so a single `ends_with` test both misses the real tag and would match a
coordinate pair that is not one. Both branches are exercised by real data.

### 2.5 Connection offsets are the common case, not the corner

Measured over the 421 baked `_data.tres`:

| | |
|---|---|
| Maps carrying connections | **61** |
| Connections | **118** |
| **With a nonzero offset** | **68 (57.6%)** |

An `offset` slides the neighbour along the shared edge, measured from this map's
origin. §3.4 is why that makes offsets a resize concern.

### 2.6 Two things that turned out to be safe, checked rather than assumed

- **`Warp.dest_warp_id` is matched by VALUE, not by array position** —
  `map_manager.warp_arrival` scans for `w.warp_id == warp_id` (`:691`). So
  trimming a warp away does **not** renumber the others; the only consequence is
  that inbound references to that specific id dangle. Bad, worth reporting, but
  not the silent misrouting it would be under positional matching.
- **Tile routing already has one shared owner.** `MapManager.paint_metatile` is
  used by both the `setmetatile` opcode and the editor brush, precisely so the
  rule is not kept by hand in two places. New cells are painted through it, so
  resize cannot invent a fourth routing.

---

## 3. The design

### 3.1 Four edge deltas — the input model, and why the obvious one is worse

The author says how much to add or remove on each **edge**. Everything else is
derived:

```
offset = (west, north)                             # where old (0,0) lands
size   = (w + west + east, h + north + south)
```

⚠️ Asking for width, height and an offset is **three numbers of which two can
contradict each other**: an offset of (3, 0) against a width that only grew by 1
is silently a trim on the right, and the author who typed it meant a grow on the
left. Each edge delta names one edge and means exactly one thing, so no
combination is self-contradictory and nothing needs validating against anything
else.

- A **nine-way anchor** is a lossy special case — it cannot express "+3 north
  AND +5 south" in one action.
- A **free offset** is the same information in the form where you can get it
  wrong.

**Reference parity:** Porymap's own Change Dimensions is a drag-rectangle you
reposition the map inside — *"anything outside the rectangle when you finish
will be deleted"* — so an arbitrary offset is the reference behaviour, not a
convenience invented here. A viewport drag can be added later as a second
front-end onto the identical call; it would compute the four deltas and change
nothing else.

### 3.2 ⚠️ A re-layout, never a `resize()`

The arrays are row-major over `width`. Growing 20x18 to 24x18 by resizing the
backing arrays in place would leave row 1 starting four cells into row 0 and the
whole map diagonally smeared — **a map that still loads and is wrong**, which is
the worst available failure. Every cell is placed by coordinate into fresh
arrays; the old arrays are only ever read.

`plan()` also refuses outright when `metatile.size() != width * height` on the
way in, because a short array would read the wrong row rather than fail.

### 3.3 Replicated fill, unreplicated decisions

New cells copy the **nearest edge cell** (a clamp on both axes, so a corner
copies the corner) for metatile, collision, elevation, behaviour and layer type.

⚠️ **But the explicit bits are left clear**, so every new cell reads
`needs_review` in the overlay. §1.9's own measurement is the reason: collision
varies by placement for 52.0% of metatiles and elevation for 52.1%, so a
replicated attribute is a ~87%-right *guess*, not a decision. Stamping them
explicit would have one resize claim hundreds of confirmed decisions nobody
made. This is the same rule, for the same reason, as
`MapData.author_cell_with_defaults`.

Surviving cells carry their own provenance over **verbatim** — an imported cell
stays imported, because it was not re-decided by being moved, and flipping it
AUTHORED would make `map_baker` refuse to re-bake a map nobody hand-edited.

### 3.4 ⚠️ Growing north or west slides every seam, and nothing else would notice

A connection's `offset` is measured from this map's own origin. Adding rows to
the **north** moves all existing content down by that many rows **while the
origin stays put** — so the tile that used to line up with the neighbour's row 0
is now `north` rows lower, and the seam is wrong by exactly the amount you grew.
With 57.6% of this project's connections carrying a nonzero offset (§2.5), this
is the common case.

The correction is decided by which **axis** the edge runs along, not by which
edge it is:

| Neighbour edge | Slides along | Correction |
|---|---|---|
| NORTH / SOUTH | X | `offset += west` |
| WEST / EAST | Y | `offset += north` |
| DIVE / EMERGE | — | none; they warp rather than stitch (§1) |

Growing **south or east** moves no existing content and therefore corrects
nothing — the neighbour simply re-derives flush against the longer edge.

**The host's side is corrected in memory** and rides along with Save Map Data.
**The guests' reciprocals are written to disk immediately**, because a guest has
no open scene to hold an edit — the same conclusion `connect_maps` reached when
it chose to save both sides itself. The reciprocal is the negative, derived
rather than recomputed.

⚠️ **This asymmetry is the sharpest edge in the piece and is opt-in for that
reason**: an undo puts the host back but cannot un-write the guests. The dialog
defaults it on, names every file it wrote, and says plainly that the guest half
is not undoable.

### 3.5 The overlap guard

A grow is a placement change: adding eight columns east pushes nothing (the east
neighbour re-derives flush), but it does put eight columns of this map where
empty world used to be — and a map **two hops away** can be sitting there, which
is what nearly happened to Xanadu Nursery and Pewter City.

Refused rather than warned, matching `connect_maps`, and for its recorded
reason: `chunk_owning()` is first-match-wins over an **unordered** Dictionary, so
two overlapping chunks answer differently run to run — a bug that reproduces
intermittently and points nowhere near itself.

Implemented by running the **real** placement BFS with the post-resize size and
offsets substituted, via a new optional `overrides` parameter on
`MapAuthoring.placed_rects`, rather than re-deriving the geometry. One rule, one
implementation.

### 3.6 Undo

⚠️ **`MapOverlay.snapshot_cells` is not enough and would fail silently.** It
captures the seven arrays and the tile blobs but **not `width`, `height` or the
entities** — so undoing a resize through it would restore 24x18-shaped arrays
into a `MapData` still claiming to be 20x18. That is not a broken map so much as
a differently sheared one. Resize carries its own snapshot/restore pair.

Trimmed entity nodes are **detached, never freed**, and handed to
`EditorUndoRedoManager.add_undo_reference()` — freeing them would make the trim
half of a resize permanently irreversible while the other half undid cleanly.

Restore runs in three passes, and the middle one is not optional: **every node
is given a throwaway name before any real one is set**, because restoring names
in one pass hits transient collisions (node A wants the name node B still holds)
and Godot resolves those by silently renaming to `@Node2D@N`. An undo that
returned the map with `@Node2D@41` where a script's target used to be is worse
than no undo.

---

## 4. The pieces

| # | Piece | Where | State |
|---|---|---|---|
| 1 | `plan()` — validation, derived size/offset, the reference cap, the kept footprint | `scripts/overworld/map_resize.gd` | Built |
| 2 | `resize_data()` — the seven-array re-layout with edge replication | same | Built |
| 3 | `resize_scene()` — tile shift, added-cell paint, entity move/rename/detach | same | Built |
| 4 | `snapshot()` / `restore()` — the resize-shaped undo pair | same | Built |
| 5 | `overlaps_after()` + `placed_rects` overrides — the neighbour guard | same + `map_authoring.gd` | Built |
| 6 | `realigned_connections()` / `realign_neighbours()` — seam correction, both sides | same | Built |
| 7 | The dialog — four spinboxes, live budget readout, results box, **no rules** | `addons/map_overlay_editor/resize_map_dialog.gd` | Built |
| 8 | Toolbar button + undo wiring (`_commit_resize`) | `addons/map_overlay_editor/plugin.gd` | Built |
| 9 | `MapOverlay.restore_resize()` — the undo entry point | `scripts/overworld/map_overlay.gd` | Built |
| 10 | Test section **BH**, 39 assertions, all ungated | `scenes/overworld/m27a_step_resolver_test.gd` | Built |
| 11 | `size_mismatch()` / `painted_extent()` + the overlay banner | `map_resize.gd`, `map_overlay.gd` | Built — see §4b |

**`m27a_step_resolver_test` `EXPECTED_TOTAL` 649 → 688 (+39).** The suite ran
**684/684** at the +34 mark. ⚠️ **The +39 total has NOT been confirmed on a clean
tree** — Pallet Town is currently resized in the working tree, which legitimately
fails ~25 assertions that hardcode its geometry, so the last observed run is
660/686. **BH itself has zero failures in that run.** Re-confirm once Pallet Town
is restored; do not record a total that has not been seen.
`m27n_weather_test` 54/54, `m27h_wild_encounters_test` 118/118 and
`m27e_surf_test` 82/82 re-run green after the `map_authoring`/`map_overlay`
changes. Full sweeps remain Rob's manual step.

**The split is the addon's own standing rule, not a preference.** `plugin.gd`
records that this addon is the project's one surface with no automated coverage
and has already shipped three defects, so anything holding a rule belongs on the
other side of the boundary. Piece 7 turns a Dictionary into Controls and does
nothing else; pieces 1–6 are driven headlessly by piece 9.

Section **BH** is the next free prefix — BG is currently the highest in use.

---

## 4b. ⚠️ The defect the first real drive found — two saves, one of them forgotten

**Found by Rob, 2026-08-13, on the very first use of the tool. Fixed the same
day. Recorded here because the cause was a design decision, not a slip.**

Resizing Pallet Town `+4` north and pressing Ctrl+S — but not **Save Map Data** —
persisted shifted tiles and entities against unshifted collision. The map still
loaded, still looked correct, and had its movement rules four rows out of
register. Nothing anywhere said so.

**The measurement that separated cause from symptom.** A probe resized a real
Pallet Town and compared both halves against a control:

| | Scene/data agreement |
|---|---|
| Before any resize (control) | 127 agree, **353 disagree** |
| After the resize | 223 agree, **353 disagree** |

Identical disagreement, so the resize preserved the relationship — the 353 are
the pre-existing "`metatile` is a watermark, not a cache of the scene" property
(`map_data.gd:247-266`). Every entity and all 960 tiles moved by an identical
`(0,+4)`. **The shift maths was never wrong.** `git status` gave the real answer:
`.tscn` modified, `_data.tres` untouched at `width 24, height 20`.

### Why the design allowed it

The addon's standing rule is *writes happen only on explicit buttons*. That rule
is correct for painting, which touches **one** artifact — forget to save and you
have simply not saved. ⚠️ **A resize touches two, persisted by two different
gestures, and the half-saved state is worse than either extreme.** Asking for two
saves in the results box was not a guard; asking for two is what lets one be
forgotten.

It also compounds: in that state two entities sat past the un-updated height, and
a *second* resize would have counted them out of bounds and deleted them.

### The two fixes, both Rob's call

1. **The resize writes the `.tres` itself**, as it already did for neighbour
   maps. Deliberately breaks the standing rule above, at the site, with the
   reasoning recorded there. One artifact is left to save, so no combination of
   presses can misalign a map.
2. **A `SIZE MISMATCH` banner on the overlay**, from `MapResize.size_mismatch()`.
   Kept even though fix 1 removes the cause, because it reaches the two cases
   fix 1 cannot: maps already saved in that state, and any other source of the
   same divergence. ⚠️ **Keyed on paint OUTSIDE the data bounds, never on a size
   comparison** — a painted extent smaller than the data is completely normal and
   comparing sizes would light up hundreds of maps (BH.37 pins this).

### The standing lesson

**`m27a_step_resolver_test` is a real acceptance gate after a resize, not a
formality.** It caught this without being asked to — `AY.08 an untouched baked
map reports NO painted changes` fails the moment a map's tiles move — but it had
not been run between the save and the report. Run it after resizing any map the
suite uses as a fixture.

---

## 5. Flagged, not fixed

Per the standing rule, these were found while scoping and are deliberately left
alone:

1. **Trimming a warp dangles inbound `dest_warp_id` references from other maps.**
   Detected and reported by the tool (it knows which warps it removed), but not
   repaired — repairing would mean editing other maps' warps, which is a larger
   decision than a resize should make on its own.
2. **`assets/maps/<Map>.json` is not updated by a resize.** It is gitignored
   regenerable output and nothing reads it after bake, so the artifacts stay
   correct — but a future re-run of `gen_map_import.py` + bake on a resized map
   would reintroduce the old dimensions. That is the same standing hazard the
   §1.9 AUTHORED-cell guard already exists to catch, and the guard will fire.
3. **`MapAuthoring.usable_pairs`/`baked_maps` re-scan the directory per call.**
   Fine at 421 maps and unrelated to this piece; noted because the resize dialog
   is the fourth caller.
4. **CLAUDE.md's fresh-checkout baseline for `m27a_step_resolver_test` is
   stale, and was before this piece.** It records *"44/44 (90 gated) in a clean
   clone, and 134/134 only after `gen_map_import.py`"*, against an
   `EXPECTED_TOTAL` that was already 649. Section BH adds 34 ungated
   assertions, so the clean-clone figure moves again — but the recorded numbers
   are wrong by a different order of magnitude and re-deriving them needs a real
   fresh checkout, which is not this piece's to do. Left for whoever next has
   one.

---

## 6. Out of scope

- **Viewport drag-to-resize.** The rules layer is already shaped for it (§3.1);
  it is a second front-end, not a redesign, and can land whenever it is wanted.
- **Resizing the border block.** `MapData.border` is imported data with **no
  live consumer** (`map_data.gd:122-129`) — the border-skirt renderer that read
  it was removed. Resizing it would be work with no observable effect.
- **Batch/headless resize.** `map_creator.tscn` is the precedent for a scriptable
  driver and could press the same functions later. Not needed for the ask.
