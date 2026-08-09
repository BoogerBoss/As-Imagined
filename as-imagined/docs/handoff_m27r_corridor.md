# Handoff — M27R corridor completion, 2026-08-08

## What this is

The action plan for **M27R**: get the 32-map corridor playable end to end, add
one hand-made map, and get basic audio in. Written to be picked up cold.

⚠️ **`docs/handoff.md` (2026-08-03) IS STILL LIVE AND COVERS M36.** It is a
different workstream. Nothing here supersedes it.

**Scope of record is `CLAUDE.md`'s `## M27R` section.** This file is the
practical companion: what to do first, and the traps that will otherwise cost
you an hour each.

---

## 1. Read in this order

1. **`CLAUDE.md` → `## M27R`** — the plan, with every figure's derivation.
2. **`CLAUDE.md` → `## M27M`** — the authoring-tooling block M27R's Phase 2
   draws its sub-tiers from.
3. This file, section 4 (**Traps**). Genuinely the highest-value part.

Do **not** read CLAUDE.md end to end — it is flagged as near its size cap.

---

## 2. Where things stand

**M27Q closed 2026-08-08** (entity/event authoring). Q1–Q4 built, Q5 deferred
indefinitely. The Inspector now shows a placed entity's script, its dialogue,
and a trainer's roster; name dropdowns cover trainer class, battle items, held
item, nature and gender; there is a **Name Usage** collision checker and an
**Overlay** toggle that cannot bake itself into a map.

⚠️ **ONE THING FROM M27Q HAS NEVER BEEN SEEN IN PLAY, AND IT IS THE BIGGEST
UNVERIFIED CLAIM IN THE PROJECT RIGHT NOW.** Q1 wired `ai_flags` into real
battles for the first time. Measured against the `7` every trainer used to run
at: **1,205 of 1,477 are now strictly weaker**, 253 unchanged, 13 mixed, 6
stronger — and all 1,477 lost proactive switching, because zero of them carry
`AI_FLAG_SMART_SWITCHING`. That is source fidelity, and the old behaviour was
accidentally generous. **Fight a Kanto trainer before building on it.** If it
feels wrong, it is a tuning decision, and it is cheaper to make now.

---

## 3. The plan, in order

### Step 1 — five movement actions *(smallest thing here)*

`emote_exclamation_mark`, `face_original_direction`, `face_player`,
`jump_2_down`, `nurse_joy_bow` — **one use each** across the whole corridor.

⚠️ **Five actions is not five table entries.** `MovementRunner._build()` is a
static table; two of these need runtime context it has no slot for
(`face_player` needs the player's position, `face_original_direction` needs the
entity's spawn facing). `jump_2_down` is an arc, not a frame count.
`emote_exclamation_mark` needs the "!" bubble — `[M27D D1]` already pulled
`emotion_exclamation.png`, so the asset exists. `nurse_joy_bow` is bespoke.

**Worth deciding first:** all five are single-use. Find where each fires before
building — one or two may be better as documented no-ops than as animations
nobody will look at twice. `NameUsage`-style: check the call site, then decide.

### Step 2 — `trywondercardscript` → documented no-op

One use, Mystery Gift. Follow the existing named-no-op convention in
`script_vm.gd` (listed explicitly, never falling through to `UNKNOWN_OP`, with
a comment saying why it is a no-op rather than a gap).

### Step 3 — M27M1: behaviour onto the tile at bake

The `behavior` custom-data layer is **already declared on every baked TileSet
and carries zero values** — `map_baker.gd:698-700` declares it and nothing
writes it. Populate it from the same per-metatile data the importer already
has. Everything below reads this, so it goes first.

### Step 4 — M27M4: write painted ids back into `MapData`

⚠️ **THE ONE THAT TURNS PAINTED GRASS INTO GRASS.** `StepResolver` reads
`MapData.behavior`; nothing writes it, so a painted map plays inert — no
encounters, no surfing, no ledges.

**Much of this is already built.** `[M27B Change 2 / Step D]` shipped the whole
editing apparatus: `paint()`/`apply_edit()`, `snapshot_cells()`/
`restore_cells()` in the editor's undo, `review_cells()`/`review_count()`, the
dirty banner, `author_cell_with_defaults()`, `save_map_data()`. What is missing:

- **`MapData.set_metatile_id()` and `MapData.set_behavior()` do not exist.**
  The full mutator set today is `set_attr_explicit`, `set_collision`,
  `set_elevation`, `author_cell_with_defaults`.
- **The detection** — comparing painted atlas coords against
  `MapData.metatile`. Nothing anywhere does this.

Two setters and a comparison, not a write path.

### Step 5 — M27M3: the metatile brush *(rescoped)*

⚠️ **Ask "in front of the player or behind?", NOT "what layer type is this?"**
Layer type is a GBA taxonomy for how source packed its BG layers and is **not
load-bearing at runtime** — nothing reads `MapData.layer_type` to decide
anything; draw order comes from `PLANE_Z` alone.

Write all three planes at the cell, each with its own source. The non-routed
one is transparent (measured: all 10,494 non-routed atlas cells fully blank),
so it costs nothing and needs no routing lookup.
`MapManager.set_metatile()` already does this paint and is green at **20/20** —
expose it, do not reinvent it.

### Step 6 — M27M5: a blank new map, then connect it

`.tscn` + `_data.tres` written straight to `scenes/maps/`. No importer, no
JSON. Then a `Warp` at each end, plus `connections` if it should stitch rather
than door.

### Step 7 — audio scoping *(a decision, not a build)*

⚠️ **THE ASSET SITUATION INVERTS THE OBVIOUS PLAN.**
`assets/Essentials_v19.1/Audio/` is tracked and holds **SE 858, ME 22, BGS 0,
BGM 35 — of which 32 are `.mid` and 3 are `.ogg`.** Godot does not play MIDI
and none of those 32 has an `.import` sidecar, so they are inert bytes. The
three usable tracks are *Evolution*, *HoF room*, *Hall of Fame* — no town
theme, no battle theme.

So the half Rob asked for has no assets and the half nobody asked for is ready
to wire. **BGM is an asset-sourcing decision before it is a code question** and
it is Rob's to make.

Seams already exist: the audio opcodes are named no-ops at `script_vm.gd:559`,
and the battle anim VM records SE id + pan per cue for **M36-S**. ⚠️ **Do not
port source's m4a engine** — channel priority and DirectSound allocation are
hardware accommodation.

### Step 8 — `pokemart`

Two uses; Viridian and Pewter marts. Needs a shop UI, so it is the largest
single build in M27R. **M27I** owns it. Last because nothing waits on it.

---

## 4. Traps — read this section twice

### ⚠️ Grep tells you what is written; only running it tells you what is true

**This failed three times in one session**, always the same shape:

- `OBJECT_EVENT` grepped as 26, measured as 25.
- `ai_flags` grepped with `^ai_flags = ` — **missed the 15 trainers whose value
  is 0**, because Godot omits an `@export` sitting at its default.
- The movement tail grepped as **~53 uses**, measured as **5** — because
  `MovementRunner._build()` generates names by concatenation
  (`"walk_in_place_faster_" + suffix`), so the literals never appear.

**Drive the real function.** `MovementRunner.action(name)`,
`ScriptPreview.build(label)`, a parsed `.tres` — not a regex over source.

### ⚠️ `git add -A` is unsafe in this repo

The Godot editor rewrites files merely by opening them — `uid=` annotations on
`.tres`, input-map reordering in `project.godot`. This session swept an
unintended `project.godot` change into a commit that way. **Stage explicitly.**

### ⚠️ A resource the editor touches must be `@tool`

Without it Godot builds a **placeholder instance** with no methods, and
`_validate_property` never runs — so dropdowns, checkboxes and panels silently
do not appear. Symptom: *"Attempt to call a method on a placeholder instance."*
`TrainerData`, `TrainerPartyMon`, `TrainerClassData`, `ItemData` are `@tool` as
of 2026-08-08.

And `@tool` alone is not enough if the code reaches an **autoload**:
`PokemonRegistry` is not `@tool`, so it does not execute in the editor at all.
`TrainerData.species_name_for()` reads `data/pokemon.json` directly for exactly
this reason. `MoveRegistry`/`ItemRegistry` are plain static classes and are fine.

### ⚠️ `--script` mode reports fake compile errors

`godot --headless --script foo.gd` does not initialise autoloads the way a
scene run does, so dependency chains touching `PokemonRegistry` print
`Identifier not found` / `Failed to compile depended scripts`. **Real scene
runs and `--editor --quit` both report zero.** Ignore it in `--script` probes;
do not "fix" it.

### ⚠️ `EXPECTED_TOTAL` must be read off a real run

`m27a_step_resolver_test` has a Z.99 balance check. Its constant is
**measured, never counted from `_chk(` call sites** — branches and early
returns break static counting. Add assertions, run, read the reported number,
set it.

### ⚠️ `m24c_test` C.02 is a documented flake

It fails intermittently (~1 run in 3) and has since before this work. Confirm
28/28-style clean runs before blaming a change on it.

### ⚠️ Two different saves

**Ctrl+S** saves the scene *and* an edited `.tres` (confirmed 2026-08-08 —
`TRAINER_BUG_CATCHER_RICK_FRLG` persisted). **`MapData` is different**: the
overlay's edits only reach disk via the **Save Map Data** button. Painting
alone changes memory.

### ⚠️ Never save a `MapOverlay` into a map

It contaminates twice — the node, and an `ext_resource` for the map's own
`_data.tres`, a dependency baked maps are built without. `m27a` section N
catches it after the fact. **Use the `Overlay` toggle button** — it adds the
node from code, so `owner` is null and `PackedScene.pack()` cannot see it.

---

## 5. How to run things

```bash
# overworld suite (treats engine ERROR lines as failures)
bash scripts/run_overworld_tests.sh                                  # m27a, the default
bash scripts/run_overworld_tests.sh scenes/overworld/m27f_script_vm_test.tscn

# battle suites
/home/rob/Godot_v4.7.1-stable_linux.x86_64 --headless \
  --path /home/rob/GodotAsImagined/as-imagined \
  res://scenes/battle/m24c_test.tscn --autoplay
```

**Green baseline as of 2026-08-08** — compare against these, not memory:

| suite | |
|---|---|
| `m27a_step_resolver_test` | 542 |
| `m27f_script_vm_test` | 292 |
| `m27l_save_test` | 102 |
| `m27k_newgame_test` | 67 |
| `m27_setmetatile_test` | 20 |
| `trainer_data_smoke_test` | 5091 |
| `m24c_test` | 67 *(66 when C.02 flakes)* |
| `ai_test` / `m24b_test` / `doubles_test` | 40 / 61 / 54 |
| `m26_trainer_category_party_test` | 130 |

---

## 6. Decisions waiting on Rob

1. **Fight a trainer.** Q1 is unverified in play and 1,205 trainers got weaker.
   Everything else can proceed regardless, but this is the one that might send
   work backwards if left too long.
2. **Which of the five movement actions are worth animating** versus recording
   as no-ops. All are single-use.
3. **BGM assets** — render the 32 MIDIs through a soundfont, source `.ogg`
   equivalents, or commission. Blocks Phase 3 entirely.
4. **`TRAINER_BUG_CATCHER_RICK_FRLG` is `ai_flags = 3`**, hand-edited during
   testing. Source says `1`. It is the only one of 1,477 that diverges, and a
   roster regen would silently revert it. Keep or revert — committed alone as
   `d0a31c79` so it is one `git revert` either way.

---

## 7. What this plan does NOT cover

M27J (modes & tweaks — nothing built), PC storage (M27I I5-5, deferred),
FOG_HORIZONTAL and the other six weather stubs, M27M6/M27M7 (behaviour picker
and new art — only needed for *original* tiles; Kanto art covers a first custom
map), and M27P (overworld polish, deliberately empty and Rob's to fill).

None of them block a playthrough.
