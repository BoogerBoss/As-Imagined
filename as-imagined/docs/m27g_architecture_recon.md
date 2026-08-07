# Event scripting architecture — investigation & recommendation

**Written 2026-08-07. Investigation only — no project files were modified.**

Scope: whether to replace the field-script architecture with a native
Godot/GDScript `EventRunner` built on `await`, retaining FireRed
compatibility where practical.

---

## 0. Step 0 finding, stated before anything else

**The premise of the question does not match the codebase.**

The brief contrasts a "literal FireRed VM" (Architecture A) against a native
GDScript event system (B) and a hybrid (C), and asks which to build. But this
project has already built C's runtime half, and it is roughly 92% complete
against the whole FireRed field-script corpus.

`scripts/overworld/script_vm.gd` (1,906 lines) is **not** a GBA bytecode
interpreter. It never touches a byte, an opcode number, a ROM pointer, or a
`gScriptCmdTable` index. It is a **Godot-native interpreter over a JSON
intermediate representation** that a Python compiler
(`scripts/gen_map_scripts.py`) produces from hand-editable assembly-syntax
source text. Its op stream looks like this:

```json
{"op": "goto_if_eq", "args": ["VAR_MAP_SCENE_PALLET_TOWN", "3", "SomeLabel"]}
```

Compare that to the brief's own diagram:

```
FireRed scripts / native scripts
            ↓
      Event representation      ← data/map_scripts.json IS this
            ↓
       EventRunner              ← ScriptVM IS this
         (GDScript)
            ↓
       Godot systems            ← overworld.gd's _drive_script IS this seam
```

**That is the same architecture.** The disagreement is not about the shape of
the pipeline. It is about two narrower things:

1. **The authoring front-end** — today the only way in is `.inc` assembly
   syntax plus a Python regenerate step. There is no GDScript front-end.
2. **The escape hatch** — there is no way for a script to hand control to
   arbitrary Godot code (tween, particle, camera, shader) and get it back.
   Every such need currently costs a new `Pause` enum member plus a hand-written
   branch in a 3,155-line driver.

Those are both real, both worth fixing, and **neither requires replacing the
runtime.** Replacing the runtime would discard 17,137 compiled script labels,
11,451 dialogue entries, ~92% opcode coverage, a 229-assertion test suite built
specifically around the runtime's inspectability, and the save format that
depends on it — to solve an authoring-ergonomics problem and a missing-feature
problem.

**Recommendation in one line: keep `ScriptVM` as the sole execution engine; add
a GDScript authoring DSL that compiles to the same op stream, and a `native`
opcode that suspends the VM on a GDScript coroutine.** Full reasoning below.

---

# Part 1 — The existing project

## 1.1 Engine and shape

| | |
|---|---|
| Engine | Godot **4.7.1** stable, Standard edition, GDScript (`config/features=PackedStringArray("4.7","Forward Plus")`) |
| Main scene | `res://scenes/main.tscn` |
| Autoloads | **exactly one** — `PokemonRegistry` (`res://scripts/data/pokemon_registry.gd`) |
| Editor plugins enabled | `map_overlay_editor` only |
| `addons/dialogue_manager` | present on disk but **plugin not enabled**, zero `.dialogue` files, one file (`text_typer.gd`) vendored *from* it with a documented refusal to integrate. Effectively dead weight — **there is no competing dialogue runtime to reconcile with.** |
| GDScript files | 540 |
| Viewport | 1024×768, `canvas_items` stretch, pixel snapping on |

The near-total absence of autoloads is architecturally significant and
deliberate: cross-scene state is held as **class-level statics**
(`OverworldSession`, `BattleSetupContext`, `TextBuffers.identity`) rather than
via singletons. Any proposal that introduces `EventSystem` /
`FlagManager` / `VariableManager` autoloads is fighting an established,
documented convention.

## 1.2 The two products

`CLAUDE.md` is emphatic that this is **one engine, two co-equal products**: a
full single-player Kanto RPG with an original story, and a standalone
Showdown-style battle simulator. The battle engine is the shared subsystem.
**Anything built for the field must not leak into the simulator's dependency
graph.** `ScriptVM` currently satisfies this cleanly: it is a `RefCounted` with
no scene-tree access and no autoload dependency.

## 1.3 Scene structure

```
scenes/
  main.tscn                       entry
  overworld/
    overworld.tscn / .gd          THE field controller — one generic scene,
                                  3,155 lines, owns player+camera+input+VM
    map_baker.tscn                editor-time artifact producer
    title.tscn                    save-slot menu
    *_test.tscn / *_test.gd       ~24 headless test scenes, 12,613 lines total
  maps/
    <MapName>_Frlg.tscn           BAKED map artifact, ~421 importable / 32 baked
    <MapName>_Frlg_data.tres      per-cell MapData resource
  battle/                         battle screens (singles/doubles), ~6,900 lines
```

A baked map `.tscn` is pure data — five nodes, no logic:

```
PalletTown_Frlg (Node2D)
├── Ground          TileMapLayer  (tile_map_data blob + shared TileSet)
├── Objects         TileMapLayer
├── Entities_P2     Node2D  y_sort  ← elevation→priority 2 stratum
│   ├── Npc_3_10    NPC   script_label="PalletTown_EventScript_SignLady"
│   ├── Npc_13_17   NPC   ...
│   └── Npc_10_8    NPC   visibility_flag="FLAG_HIDE_OAK_IN_PALLET_TOWN"
├── Overhangs       TileMapLayer
└── Entities_P1     Node2D  y_sort  ← priority 1 stratum (draws above overhangs)
```

The two entity strata are **not** "upper vs lower" — they come from source's
`sElevationToPriority` table, which alternates (`[2,2,2,2,1,2,1,2,1,2,1,2,1,0,0,2]`).
This matters for any event system that moves entities between elevations.

## 1.4 Map loading / streaming

`MapManager` (1,472 lines) owns a **global cell coordinate space** shared by
every loaded chunk; each chunk carries its own origin offset. Several chunks
can be live simultaneously (M27C4 connection stitching), and the player crosses
between them **without a scene change** — `manager.chunk_owning(_cell)` answers
"which map am I in" at runtime rather than by scene identity.

Key consequences for an event system:

- A warp (`_teardown_and_load`) **frees the outgoing chunk's node tree**,
  including every `OverworldEntity` in it. Any long-lived reference to an NPC
  node is invalidated by a warp.
- Chunk rebuild costs **66–100 ms** (measured), which is why the battle
  transition was changed from a scene swap to an overlay.
- `MapManager` also paints a per-axis border "skirt" (12×9 cells) and applies
  the shared weather `ShaderMaterial` to terrain planes only.

## 1.5 NPCs and other placed events

Six `@tool` node classes over one base:

| Class | Source array | Distinguishing fields |
|---|---|---|
| `OverworldEntity` | (base) | `cell`, `elevation`, `visibility_flag`, `script_label` |
| `NPC` | object_events | `graphics_id`, `movement_type`, `local_id`, `range_x/y` |
| `TrainerNPC` : NPC | object_events (`TRAINER_TYPE_NORMAL`) | `trainer_key`, `sight_range` |
| `ItemBall` | object_events (ball graphic) | `graphics_id`, `local_id` |
| `Warp` | warp_events | `warp_id`, `dest_map`, `dest_warp_id`, `arrow_dir`, `exit_dir`, `triggers` |
| `Trigger` | coord_events | `var_name`, `var_value` |
| `Sign` | bg_events | `bg_type`, `facing`, `item` |

**The placed instance is the source of truth for spawn data**; identity that
outlives a placement (a trainer's party/class/name) lives in a registry keyed by
`trainer_key`. This is already exactly the "NPC definition vs NPC placement vs
event" separation the brief asks for in Part 8. It does not need redesigning.

Entities are referenced from scripts by `local_id` (a `LOCALID_*` token), never
by node path. `overworld.gd::_resolve_movement_entity` does the lookup;
`VAR_LAST_TALKED` resolves to `_vm.subject`.

## 1.6 The player

**The player is not an `OverworldEntity`.** It is spawned by `overworld.gd`
(`_spawn_player`, `_build_player_node`) as a bare `Node2D` + `Sprite2D`, held in
`_player`, with `_cell`/`_facing`/`_elev`/`_moving` as controller state. It
shares `OverworldEntity.make_sprite()` (static) and `WalkAnim` with NPCs but is
otherwise a separate code path, including `_reparent_for_elevation()` between
`Entities_P1`/`Entities_P2`.

Scripts address it as `LOCALID_PLAYER` / `"255"`
(`overworld.gd::_is_player_target`), and `_start_player_movement` routes it
through the **same** `MovementRunner` every NPC uses.

## 1.7 Interaction

`Interaction.resolve()` (103 lines, pure static, fully injectable) is a faithful
port of `GetInteractionScript` (`field_control_avatar.c:308`) including the
**counter hop** (729 `MB_COUNTER` cells across 89 maps — without it every shop
clerk and nurse is unreachable). It returns a Dictionary
(`{source, entity, script, cell}`), not a label, so the caller knows what it hit.

`overworld.gd::try_interact()` then:
1. refuses if `_vm != null or _in_battle or _warping or _moving or _in_approach`
2. tries surf first (water carries no script/entity)
3. calls `Interaction.resolve`
4. turns the NPC to face the player (`faceplayer` is a VM no-op — the scene owns it)
5. `run_script(label, entity)`

## 1.8 Dialogue

`MessageBox` (171 lines) + `TextTyper` (128 lines, vendored typewriter) +
`YesNoBox` (153) + `TextBuffers` (185, the `gStringVar1-3` equivalent + `{PLAYER}`
/ `{RIVAL}` / `{STR_VAR_n}` expansion) + `NamingScreen` (321).

Text is **data**: `data/map_texts.json`, 11,451 labels, 1.67 MB, produced by
`gen_map_texts.py` from the same `.inc` fork. Pages are split on `\p`.
`ScriptVM.TEXT_OVERRIDES` is the (currently one-entry) authored-content override
table.

## 1.9 Battles

**A battle is an overlay, not a scene swap** (`_mount_battle_overlay`): a
`CanvasLayer` at layer 100 holding the instantiated battle screen, added as a
child of `overworld.gd`. The overworld stays alive underneath — map, chunks,
player position all intact. Round trip:

```
ScriptVM: trainerbattle_single → Pause.WAIT_BATTLE
overworld._drive_script: shows intro pages, then start_script_battle(key)
  → _begin_battle → _mount_battle → BattleSetupContext.set_pending(...)
  → fade out, add CanvasLayer, fade in
battle screen emits battle_finished(outcome)
  → _on_battle_overlay_finished: prize, restore_party, caught mon
  → OverworldSession.set_result(BattleOutcome...)
  → fade, free layer, _apply_battle_result() [while _in_battle STILL true]
  → _vm.resume_after_battle(won)   ← branches the script
  → _in_battle = false
```

The `_in_battle`-still-true window is documented as load-bearing: clearing it
first left a multi-frame gap where `_drive_script` saw the still-parked
`WAIT_BATTLE` and started a **second** battle.

## 1.10 Warps / map transitions

Three paths, all `async` (`await`) functions on `overworld.gd`:

- `_do_warp(w: Warp)` — player stepped on a warp node
- `_do_scripted_warp(warp_data)` — the `warp` opcode's `Pause.WAIT_WARP`
- `_do_whiteout()` — respawn after a loss

All share: `_warping = true` → `await _fade_to(1.0)` → `_teardown_and_load(dest)`
→ `_place_player` → `await _run_arrival_map_scripts(dest)` → `await _fade_to(0.0)`
→ `await _exit_arrival(w)` → `_warping = false`.

## 1.11 Flags and global state

`FlagStore` (208 lines, `RefCounted`) — **flags and vars keyed by NAME, not
numeric id**, because the importer already carries source's `FLAG_*`/`VAR_*`
constants as strings on every placed entity. Only *set* flags are stored (unset
reads false, matching `FlagGet`). Vars are `String → int`, unset reads 0.

It also owns: `badge_count()` (over `BADGE_FLAGS`), `trainer_defeated()` /
`set_trainer_defeated()` (derived `DEFEATED_<key>` flag), `entity_visible(e)`
(the `FLAG_HIDE_*` convention — set means hidden), `trigger_armed(t)`.
Serialisation: `snapshot`/`restore`/`to_save`/`from_save` (the latter coerces
types because a save file is untrusted input).

`OverworldSession` (285 lines) holds everything that must survive a battle or a
map teardown as **class statics**: `flags`, `bag`, `wallet`, `respawn`,
`identity`, `party`, `surfing`, `active_slot`, `playtime`, `pending_return`,
`pending_result`, `pending_trainer_key`, `pending_new_game`.

`SaveManager` (217 lines) writes one JSON per slot (3 slots), `FORMAT_VERSION 1`,
box rule (everything playthrough-specific inside the slot directory). The scope
doc **explicitly refuses** to inherit source's `ramScript` (an executable script
buffer stored inside the save).

## 1.12 Trainer and Pokémon data

Trainers: 1,477 `.tres` resources (854 `_RSE` + 623 `_FRLG`), keyed by
`trainer_key` (a canonical string, not a numeric id). Placements carry the key;
`OverworldParty.build_trainer_party` builds the roster.

Pokémon: `PokemonSpecies`/`MoveData`/`AbilityData`/`ItemData` as `.tres`
(locked at M1), plus generated JSON lookups (`pokemon.json`, `moves.json`,
`items.json`, `learnsets.json`, name→id maps). `BattlePokemon` is the runtime
instance; `PokemonFactory.create_battle_pokemon(dex, level, ...)` is the builder
the `givemon` opcode uses.

## 1.13 Animation

Three unrelated systems:

- **Field walk cycles** — `WalkAnim` (240 lines) + `ObjectEventGraphics` (536),
  frame-table driven off horizontal sprite strips. Used by both player and NPCs.
- **Field movement** — `MovementRunner` (276 lines): a table of ~79 movement
  actions (`walk_*`, `walk_fast_*`, `walk_faster_*`, `walk_slow_*`,
  `walk_in_place_*`, `face_*`, `step_end`, `delay_*`) with per-action frame
  counts (32/16/8/6/4/2). Ticked by `manager.tick_movement(_delta)`. It is a
  **second, separate mini-VM** for the movement sub-language and it works well.
- **Battle animations** — `scripts/battle/anim/anim_script_vm.gd` etc. A third
  script VM, for `battle_anim_scripts.s`. Unrelated to the field.

Note that the project already runs **three** script interpreters happily. This is
an established, working pattern here, not a novelty.

## 1.14 Signals / coroutines / `await` today

`await` is used in exactly two ways:

**(a) Scene-level sequencing inside `overworld.gd`** — fades, warp teardown,
trainer approach, `_run_map_script_to_completion` (which `await`s
`get_tree().process_frame` in a loop until `_vm == null`).

**(b) One hand-authored cutscene**: `run_new_game()` (Oak's speech, lines
1196–1256). This is **Architecture B, already implemented, already shipped**:

```gdscript
await _oak_overlay.fade_in()
await _say([OAK_WELCOME, OAK_THIS_WORLD])
await _oak_overlay.release_random_pokemon()
await _say([OAK_INHABITED, OAK_I_STUDY, OAK_ABOUT_YOURSELF])
await _say([OAK_ASK_GENDER])
var boy: bool = await _oak_overlay.pick_gender()
...
```

**This is the single most important empirical data point in the whole
investigation, and I will come back to it in Part 4.**

Signals are used narrowly and correctly (one-shot completion signals on UI
components: `MessageBox.closed`, `YesNoBox.chosen`, `NamingScreen.name_chosen`,
`FieldPartyScreen.mon_chosen`). `overworld.gd` itself emits `script_started` /
`script_finished` / `trainer_spotted` / `battle_starting` / `battle_returned`.

## 1.15 Is there already an event/cutscene system? Yes.

**`ScriptVM` + `overworld.gd::_drive_script` is the event system.** It is
mature. Here is its design, in its own words (file header, paraphrased):

> STATE IS EXTERNAL, DELIBERATELY. `pc`, `current_op` and `pause_reason` are
> plain readable properties, never information that exists only inside a
> suspended call frame. Three things depend on that and would each be impossible
> otherwise: the resolve-or-degrade path has to report WHERE it degraded; the
> F-key debug overlay convention; tests that freeze the VM mid-script and assert
> from outside. So `step()` advances exactly one opcode and RETURNS — it never
> awaits. **A coroutine would have been shorter and would have buried every one
> of the three above.**

That paragraph is a direct, considered rejection of the architecture this brief
proposes, written by whoever built the thing. It deserves to be taken seriously —
and, as Part 4 shows, the evidence has since accumulated in its favour.

### Execution model

```
overworld._process(delta)
  ├─ camera, playtime, tick_movement, surf blob    (run even during scripts)
  ├─ [gates: yes/no box → message box → naming → party → bag → start menu]
  └─ if _vm != null: _drive_script(); return       ← world frozen below here

_drive_script():
  while _vm.step() and guard < 500:  ...           ← run until VM needs us
  _start_pending_movements()                        ← drain applymovement queue
  _apply_pending_object_ops()                       ← drain add/remove/turn/move
  match _vm.pause_reason:
    WAIT_MESSAGE       → _box.open(pages); _vm.resume()
    WAIT_BUTTON        → on A: _box.advance() or _vm.resume()
    WAIT_YES_NO        → open/drive box; _vm.answer_yes_no(...)
    WAIT_BATTLE        → intro pages, then start_script_battle()
    WAIT_MOVEMENT      → if not _movement_pending(): _vm.resume()
    WAIT_NAMING        → _naming.open_keyboard(_vm.naming_prompt())
    WAIT_WARP          → _do_scripted_warp(_vm.pending_warp)
    WAIT_PARTY_CHOICE  → _party_screen.open(_vm.party)
    DONE/UNRESOLVED/UNKNOWN_OP → _finish_script()
```

The VM never awaits, never touches a node, never knows what a button is. The
driver owns every scene concern. **This separation is correct and should be
preserved by any future design.**

### Coverage, measured

I recompiled the field corpus directly rather than trusting the (self-declared
stale) figures in the code comments:

| Metric | Value |
|---|---|
| Source's script command table (`data/script_cmd_table.inc`) | **231 commands** |
| Field-script files in `field_script_source/data/{maps,scripts}` + `event_scripts.s` | 974 |
| Script labels in that corpus | 22,697 |
| Distinct tokens used | 558 (479 script commands + 79 movement actions) |
| Script-command uses (excl. movement actions) | **62,249** |
| Distinct commands `ScriptVM` implements | **124** |
| **Uses covered** | **57,464 = 92.3%** |
| Movement-action uses (handled by `MovementRunner`) | 9,974 across 79 actions |
| Compiled output | `data/map_scripts.json` 8.9 MB, **17,137 labels** |

**Top uncovered commands by use count:**

| Command | Uses | Note |
|---|---|---|
| `setmetatile` | 1,406 | The single biggest genuine gap — dynamic map geometry (opening doors, moving boulders, revealing stairs) |
| `map_script` | 890 | Table header; the compiler already expands entries to `map_script_2`, which IS implemented |
| `frontier_set` / `frontier_get` / `frontier_setpartyorder` | 239 | Battle Frontier — M35, out of Kanto scope |
| `createvobject` / `turnvobject` | 267 | Virtual (non-collision) sprites for cutscenes |
| `pokemart` / `pokemartlistend` / `setitemandprice` | 117 | Shops — M27G |
| `register_matchcall` | 76 | Match Call — Hoenn feature, likely permanent exclusion |
| `setberrytree` | 80 | Berry trees — Hoenn |
| `setweather` / `dofieldeffect` variants | ~60 | Partially covered as no-ops |
| `braillemsgbox` / `braillemessage_wait` | 63 | Braille puzzles |

Excluding Hoenn-only and facility content, the *real* remaining Kanto surface is
small: `setmetatile`, `createvobject`/`turnvobject`, the shop family,
`setobjectxy`, `hideobjectat`/`showobjectat`, `getplayerxy`, `setwildbattle`,
`setescapewarp`/`setdynamicwarp`, `multichoicedefault`/`dynmultipush`.

### The `special` bottleneck — the actual pain point

`special` (1,390 uses) and `specialvar` (719) are *implemented as opcodes* but
they dispatch into `FieldSpecials`, which currently answers **1 real function
(`HealPlayerParty`) + 7 no-ops + 5 `specialvar` constants**. The measured
surface is **2,109 uses across 569 distinct C functions**, plus 62 `callnative`
across 28 more.

An unknown special **halts the VM** by design (so coverage figures stay honest).

`FieldSpecials.run()` returns a `bool` **in the same frame**. That shape works
for `HealPlayerParty` and fails for anything that owns the display. Every such
special today costs **four coordinated edits**:

1. a new `Pause.WAIT_*` enum member in `script_vm.gd`
2. an interception branch before `FieldSpecials.run` in the `special` case
3. an `answer_*()` method on the VM (because `resume()` refuses result-carrying pauses)
4. a new `match` branch in `overworld.gd::_drive_script` + a callback

`ChangePokemonNickname`, `ChoosePartyMon` and `CreateInGameTradePokemon` each
paid that cost. **This is the thing that does not scale**, and it is what a
native escape hatch fixes.

## 1.16 Systems that would become EventRunner dependencies

Already are, via injection into `ScriptVM`:

`FlagStore` · `ScriptSource` (ops + texts) · `Bag` · `Wallet` · `RespawnPoint` ·
`BattleParty` · `TextBuffers` · `PokemonRegistry` · `IngameTradeRegistry` ·
`ItemRegistry` · `PokemonFactory` · `FieldSpecials`

Reached only through the driver (correctly): `MapManager` · `MovementRunner` ·
`MessageBox` · `YesNoBox` · `NamingScreen` · `FieldPartyScreen` ·
`FieldBagScreen` · `WeatherManager` · `OakSpeechOverlay` · battle screens ·
`MapConstants` · `StepResolver` · `WalkAnim`.

## 1.17 Testing

24 headless test scenes, 12,613 lines. `scripts/run_overworld_tests.sh` runs a
scene with `--headless` and **fails the run on any engine `ERROR` line**,
because a GDScript runtime error aborts its function silently while the summary
still reports N/N.

The VM's own suite (`m27f_script_vm_test.gd`, 229 assertions) asserts entirely
from **outside** the VM: `pc`, `current_op`, `pause_reason`, `describe()`. Its
header records two real shipped bugs (call/return frame corruption; the
compiler's `msgbox` expansion leaving a stray `return` that exited the caller),
neither of which had a test when found.

There is a recorded, hard-won lesson that bears directly on this decision:

> **A driver that reaches past the input layer cannot test the input layer.**

---

# Part 2 — FireRed / pokeemerald-expansion scripting, from source

Read directly from `/home/rob/GodotAsImagined/reference/pokeemerald_expansion`
(`src/script.c`, `src/scrcmd.c`, `include/script.h`,
`include/constants/map_scripts.h`, `data/script_cmd_table.inc`).

## 2.1 Execution model — the important part

```c
struct ScriptContext {
    u8 stackDepth;
    u8 mode;                    // STOPPED | BYTECODE | NATIVE
    u8 comparisonResult;
    bool8 breakOnTrainerBattle:1;
    bool8 waitAfterCallNative:1;
    u8 (*nativePtr)(void);      // ← THE ESCAPE HATCH
    const u8 *scriptPtr;        // ← the program counter
    const u8 *stack[20];        // ← call stack, 20 deep
    ScrCmdFunc *cmdTable;
    ScrCmdFunc *cmdTableEnd;
    u32 data[4];
};
```

`RunScriptCommand(ctx)` loops: read one byte, index the command table, call the
function. **A command function returning `TRUE` yields control back to the
engine for this frame; returning `FALSE` continues the loop.** That is the
entire cooperative-scheduling contract.

There are **three** contexts, not one:

| Context | Purpose |
|---|---|
| `sGlobalScriptContext` | The one visible, interruptible script. Driven a slice per frame. |
| `sImmediateScriptContext` | `RunScriptImmediately(ptr)` — runs to completion inside one call, no yielding. Used by map-header scripts. |
| RAM script | `ramScript` in the save block — a Mystery-Gift-delivered script. **Explicitly refused by this project's scope doc.** |

Status is a three-state global: `CONTEXT_RUNNING` / `CONTEXT_WAITING` /
`CONTEXT_SHUTDOWN`. `ScriptContext_Stop()` sets WAITING;
`ScriptContext_Enable()` sets RUNNING. Player field controls are locked
automatically while a script runs (`ScriptContext_RunScript` calls
`LockPlayerFieldControls()` every tick, and unlocks on shutdown).

**There is exactly one visible script at a time.** Multiple scripts do not
interact; a new one replaces the context. That is why the project's single
`_vm` slot is faithful rather than a simplification.

## 2.2 Two distinct waiting mechanisms — this is the key insight

**(a) `waitstate` / stop-and-be-resumed.** The command calls
`ScriptContext_Stop()`, sets status to WAITING, returns TRUE. Something else
entirely (a task, a callback) later calls `ScriptContext_Enable()`. This is how
`warp`, `trainerbattle`, `fadescreen` and menu-opening specials work.

**(b) `SetupNativeScript(ctx, fn)` / poll-a-C-function.** The command switches
the context to `SCRIPT_MODE_NATIVE` with a function pointer. Each tick the
engine calls `fn()`; **when it returns TRUE, the context flips back to
BYTECODE** and execution resumes at the saved `scriptPtr`.

```c
bool8 ScrCmd_waitmovement(struct ScriptContext *ctx) {
    u16 localId = VarGet(ScriptReadHalfword(ctx));
    if (localId != LOCALID_NONE) sMovingNpcId = localId;
    SetupNativeScript(ctx, WaitForMovementFinish);   // ← native predicate
    return TRUE;
}
```

**Mechanism (b) is a first-class, engine-level "run arbitrary native code, then
resume the script" hatch — and this project has not ported it.** It is the
single most valuable thing in FireRed's scripting design that is currently
missing here, and it is precisely what the brief is reaching for with
`await event.something()`.

`callnative` (62 uses) is its script-visible cousin, with
`waitAfterCallNative` deciding whether the script pauses afterwards.

## 2.3 Variables and flags

- **Flags**: ~2,400 bits, `FlagGet`/`FlagSet`/`FlagClear`. Unknown id → FALSE.
- **Vars**: u16 array. `VarGet(id)` returns the *id itself* when there is no
  backing pointer — that quirk is what makes the `0x8000+` range usable as
  immediates in arguments. **Every command argument goes through `VarGet`**, so
  a literal and a variable reference are indistinguishable at the call site.
- **Special vars**: `VAR_RESULT` (0x800D), `VAR_0x8000`–`VAR_0x8009` (scratch),
  `VAR_LAST_TALKED`, `VAR_FACING`.
- **String buffers**: `gStringVar1/2/3`, runtime-only, **never saved**.
- **Trainer flags**: `TRAINER_FLAGS_START + trainerId` (0x500+), one bit each,
  in a reserved block.

The project's `FlagStore` reproduces all of this by *name* instead of by id, and
documents the one deliberate divergence (`VarGet`'s id-fallback) with the reason
it is unnecessary under name keys.

## 2.4 Control flow

`goto` / `call` (20-deep stack) / `return` / `end`. `compare` writes
`ctx->comparisonResult`; `goto_if_*` / `call_if_*` come in three shapes
(3-arg self-comparing, 1-arg leaning on a preceding `compare`, and
flag/defeated forms). `switch`/`case` are macros over `copyvar VAR_0x8000` +
`compare` + `goto_if_eq`.

**No functions, no locals, no expressions, no arithmetic beyond
`addvar`/`subvar`, no data structures.** This is genuinely primitive, and it is
the single strongest argument in favour of a native authoring front-end.

## 2.5 Map scripts — seven types, run in a specific order

From `include/constants/map_scripts.h` (numbering in the file is *call order*,
not constant value):

| Order | Type | When |
|---|---|---|
| 1 | `ON_DIVE_WARP` | after choosing to dive/emerge (one use in the whole game) |
| 2 | `ON_TRANSITION` | during the transition to the map — flags, object positions, weather |
| 3 | `ON_LOAD` | after layout load, **before it is drawn** — almost exclusively `setmetatile` |
| 4 | `ON_RESUME` | end of map load, **and every return to field** (bag close, battle end) |
| 5 | `ON_WARP_INTO_MAP_TABLE` | after objects load — a **table**, first matching condition wins |
| 6 | `ON_FRAME_TABLE` | **every frame** after fade-in, before input — a table, first match wins |
| 7 | `ON_RETURN_TO_FIELD` | only on returning to field, shortly after ON_RESUME |

Tables are `(VAR_a, VAR_b, script)` triples; `MapHeaderCheckScriptTable` compares
`VarGet(v1) == VarGet(v2)` and **returns on first match**.

Types 1–4 and 7 run via `RunScriptImmediately` (synchronous, to completion).
Only `ON_FRAME_TABLE` genuinely *becomes* the running script via
`ScriptContext_SetupScript`.

The project implements `ON_TRANSITION`, `ON_WARP` and `ON_FRAME` and discloses
the rest as gaps. **`ON_LOAD` is the missing one that matters**, because it is
where `setmetatile` lives.

## 2.6 Movement scripts

A separate byte language (`data/movement_scripts.inc` + inline). ~79 actions.
`applymovement` is **asynchronous** — it kicks off and the script keeps running;
`waitmovement` is the blocking half via `SetupNativeScript(WaitForMovementFinish)`.
`waitmovement 0` means "everything in flight" (`LOCALID_NONE == 0`).

The project reproduces this exactly, with `pending_movements` as a queue the
driver drains rather than a pause.

## 2.7 Messages

`msgbox text, TYPE` is a **macro**, not a primitive: `loadword 0, text` +
`callstd TYPE`, where TYPE indexes `gStdScripts`. `Std_MsgboxNPC` decomposes to
`lock` / `faceplayer` / `message` / `waitmessage` / `waitbuttonpress` / `release`
/ `return`. Control codes in strings: `\n` newline, `\l` scroll, `\p` new page,
`{PLAYER}`, `{STR_VAR_1}`, `$` terminator.

`gen_map_scripts.py` expands `msgbox` at **compile time**, which is why the VM
needs `message`/`waitbuttonpress` and not `callstd` plus a std-script table.
That is a good decision and should be kept.

## 2.8 Battles

`trainerbattle_<variant>` — **the arity selects the battle type**. All variants
route through shared *script* handlers, not C:

- `EventScript_TryDoNormalTrainerBattle` (single/double/rematch): already-beaten
  → `gotopostbattlescript` (fall through); win → `gotobeatenscript` (the
  `event_script` argument, or a fallback that **ends the script**); loss → whiteout.
- `EventScript_DoNoIntroTrainerBattle` (`no_intro`/`earlyrival`): unconditional
  `gotopostbattlescript` — a win falls through to the next opcode.

Wild: `setwildbattle` + `dowildbattle` (not yet ported; the project drives wild
encounters from `WildEncounters` on the step seam instead, which is fine).

## 2.9 Give item / Pokémon

`giveitem` is a macro over `setorcopyvar ×2` + `callstd STD_OBTAIN_ITEM`. The
std script does: `additem` → buffer plural name → `checkitemtype` → buffer pocket
name → branch on success → "obtained"/"put away" or "bag is full".

`givemon` writes a **three-way code** to `VAR_RESULT`:
`MON_GIVEN_TO_PARTY 0` / `MON_GIVEN_TO_PC 1` / `MON_CANT_GIVE 2`
(`constants/pokemon.h:167-169`). The project had this as a boolean and it was
wrong in both directions — a documented, fixed bug.

`Common_EventScript_GetGiftMonPartySlot` finds the just-given mon via
`getpartysize` / `subvar VAR_RESULT, 1` / `copyvar VAR_0x8004, VAR_RESULT`.

## 2.10 Warps

`warp map, x, y` reads x/y **literally as a destination cell**, not a warp id
(`ScrCmd_warp`). Siblings: `warpsilent`, `warpdoor`, `warphole`, `warpteleport`,
`setwarp`, `setdynamicwarp`, `setescapewarp`. All are asynchronous and expect a
following `waitstate`.

## 2.11 Specials

`special Fn` / `specialvar VAR, Fn` index `gSpecials[]`
(`data/specials.inc`). **Measured in this project's corpus: 2,109 uses across
569 distinct functions**, plus 62 `callnative` across 28.

⚠️ `specialvar VAR_RESULT, Fn` puts the **destination var first** and the
function second — the opposite of how it reads aloud.

This is FireRed's real extensibility story, and it is precisely a "call native
engine code" mechanism. **Any Godot-native design should embrace this, not
route around it.**

## 2.12 What is genuinely hard to reproduce

| Thing | Difficulty | Verdict |
|---|---|---|
| **569 specials** | Very high — each is bespoke C | Port on demand; a generic native hatch makes each one cheap |
| `setmetatile` + `ON_LOAD` | Medium — needs runtime tile mutation + a save representation for it | **Worth doing** (1,406 uses) |
| RAM scripts (`ramScript`) | Medium | **Refuse.** Executable code in a save file is a security hole with no gameplay value here |
| `RunScriptImmediately` | Hard — no true synchronous mode in a frame-driven engine | Already approximated by `_run_map_script_to_completion`; disclosed and safe for ON_TRANSITION/ON_WARP because neither reaches a `message` |
| Field effects (`dofieldeffect`, `createvobject`) | Medium | Needs a field-effect layer that doesn't exist. Prime candidate for a native hatch |
| `SCREFF_*` effect analysis | Low value | Skip entirely |
| Contest / Frontier / Match Call / Berry trees | N/A | Out of scope |
| Exact byte-level opcode fidelity | N/A | **Explicitly not a goal.** No ROM will ever be loaded |

---

# Part 3 — Architecture comparison

Restating the three, corrected for what actually exists:

- **A — Literal FireRed VM.** Byte-level bytecode over a 231-entry table, ROM
  pointers, three contexts, ramScript. **Nobody has ever proposed this here and
  nobody should.** It is a strawman; I rate it only for completeness.
- **B — Native GDScript `EventRunner`** with `await`-based commands, replacing
  the current system.
- **C — Hybrid.** FireRed source → importer → op-stream IR ← native front-end,
  one runner. **This is what exists.** I rate both "C as-is" and "C evolved" (C+
  = the recommendation in Part 11).

Ratings out of 5.

| Criterion | A | B | C (today) | C+ (recommended) |
|---|---|---|---|---|
| Development complexity | 1 | 3 | 4 | **5** — additive; nothing to rewrite |
| Runtime performance | 4 | 4 | 5 | **5** |
| Debuggability | 2 | 2 | 5 | **5** |
| Ease of authoring **imported** content | 4 | 1 | 4 | **4** |
| Ease of authoring **original** content | 1 | 5 | 2 | **5** |
| Ease of modifying events | 2 | 4 | 3 | **4** |
| FireRed behavioural compatibility | 5 | 1 | 5 | **5** |
| Ease of importing FireRed content | 5 | 1 | 5 | **5** |
| Extensibility (new mechanics) | 1 | 5 | 2 | **5** |
| Godot integration | 1 | 5 | 4 | **5** |
| Async / wait behaviour | 3 | 3 | 5 | **5** |
| Save/load compatibility | 3 | **1** | 5 | **5** |
| Testing | 2 | **1** | 5 | **5** |
| Long-term maintainability | 1 | 3 | 4 | **5** |
| Custom mechanics beyond FireRed | 1 | 5 | 2 | **5** |
| Suitability for a large Pokémon RPG | 3 | 3 | 4 | **5** |
| **Migration cost from today** | catastrophic | **very high** | zero | **low** |

### The tradeoffs that actually decide it

**B's two fatal scores are save/load and testing, and both are project-specific,
not theoretical.**

*Save/load.* `SaveManager` writes JSON. `FlagStore.to_save()` is a dictionary. A
`ScriptVM` mid-script is `{label, pc, call_stack[], pause_reason}` — four
serialisable values. A suspended GDScript coroutine is a `GDScriptFunctionState`
holding a stack frame; there is no API to read it, write it, or reconstruct it.
Under B, "save mid-cutscene" becomes structurally impossible rather than merely
unimplemented. (Part 10 argues you shouldn't *need* it — but B removes the
option, and C keeps it free.)

*Testing.* The entire 12,613-line overworld suite is built on freezing state and
asserting from outside. Under B there is nothing to freeze. You would be reduced
to driving signals and asserting on side effects — which is exactly the failure
mode this project has already recorded and paid for.

**C-today's two weak scores are original-content authoring and extensibility**,
and both trace to the same two missing pieces (no GDScript front-end, no native
hatch). Neither is a property of the runtime.

**A's only real advantage is byte-level fidelity, which has no consumer.** No ROM
is ever loaded. The importer reads assembly *text*, which is far more robust than
bytes anyway.

---

# Part 4 — Is `await` an appropriate foundation?

## 4.1 The empirical answer, from this project's own history

`run_new_game()` is the proposed architecture, already built, already shipped:

```gdscript
await _oak_overlay.fade_in()
await _say([OAK_WELCOME, OAK_THIS_WORLD])
var boy: bool = await _oak_overlay.pick_gender()
while true:
    id.set_name(await _ask_name("Your name?", id.name_choices()))
    _box.open(...); _yes_no.open()
    var name_yes: bool = await _yes_no.chosen
    ...
```

It reads beautifully. It is also the origin of a documented defect, recorded in
`overworld.gd` at line ~710:

> ⚠️ **A YES/NO OPENED OUTSIDE THE SCRIPT VM HAD NO INPUT DRIVER AT ALL, AND
> THAT IS A REAL DEFECT OLDER THAN L2.** The only driver lived inside
> `_drive_script`'s WAIT_YES_NO branch, so `[M27K K-b]`'s own gender question —
> which does `_yes_no.open()` then `await _yes_no.chosen` with no VM running —
> **could never be answered from the keyboard.**

The cutscene worked in its own test because the test called `confirm()` directly.
It was unplayable. The fix was to add a *second*, parallel input driver to
`_process`, gated on `_vm == null`, sitting above the message-box gate — and the
comment notes the ordering there is load-bearing.

**That is the cost of `await`-based events stated precisely: every UI interaction
now needs two drivers, one for the VM path and one for the coroutine path, and
they must be kept in sync forever.** One cutscene produced one such split. A
game's worth of them would produce a systematic one.

## 4.2 Point-by-point

**Is `await` safe for long-running events?**
Mechanically yes — a `GDScriptFunctionState` survives indefinitely. But it is
only safe if nothing it captured is freed. In this project a warp calls
`_teardown_and_load`, which **frees the outgoing chunk and every
`OverworldEntity` in it**. A coroutine holding an NPC reference across a warp
resumes into a freed instance. GDScript's failure here is `Resumed function ...
after await, but class instance is gone` — a runtime error, which
`run_overworld_tests.sh` correctly treats as a suite failure, but which in play
is a silent hang mid-cutscene.

**How should paused events be represented?**
As **data**: `{label, pc, call_stack, pause_reason, pending_*}`. That is what
`ScriptVM` already is. A coroutine cannot be represented at all.

**How should events survive scene/map changes?**
They shouldn't need to — but note the VM already *does*: a scripted warp
(`Pause.WAIT_WARP`) tears down and reloads chunks while `_vm` sits untouched as a
plain `RefCounted` held by `overworld.gd`, then `resume()`s. Under `await` the
equivalent is a coroutine suspended across a teardown of the very nodes it will
touch next.

**How should save/load work if an event is interrupted?**
See Part 10. Short version: **don't save mid-event**, matching source. But the VM
keeps the option open for free; `await` closes it permanently.

**Cancellation?**
GDScript has **no coroutine cancellation.** You cannot cancel an `await`. The
workarounds are a captured flag checked after every await, or emitting the
awaited signal spuriously — both fragile. `ScriptVM` cancels by
`_abandon_script()`: set `_vm = null`. One line, total, correct.

**Preventing multiple events fighting over NPCs?**
Structurally solved today: **one `_vm` slot**, `run_script` overwrites, and every
entry point (`try_interact`, `check_step_trigger`, `check_on_frame_map_script`,
`check_trainer_sight`) guards on `_vm != null`. This is also what source does —
one global context. Under B you would need explicit mutual exclusion, or an
ownership/lease system on entities, invented from scratch.

**Disabling player input?**
Today: `if _vm != null: _drive_script(); return` — one line in `_process`,
above everything. `lock`/`lockall`/`release` are deliberate VM no-ops because
input locking is a scene concern. This mirrors source, where
`ScriptContext_RunScript` calls `LockPlayerFieldControls()` every tick. Under B
you would need a lock counter and disciplined `try`/`finally` semantics that
GDScript does not have.

**Returning control from battles/dialogue?**
Today: a typed pause carrying a result, plus an explicit `answer_*` method that
`resume()` refuses to bypass. The `resume()` guard is worth quoting — it is good
design:

> WAIT_BATTLE, WAIT_NAMING and WAIT_PARTY_CHOICE are deliberately NOT resumable
> this way. Each carries a RESULT... Clearing any of them here would silently
> drop it and read as "the script just carried on".

`await` returns a value and cannot express "this result must be consumed
deliberately".

**Error handling?**
Today: `UNRESOLVED` / `UNKNOWN_OP` are **first-class outcomes** with a
`diagnostic` string naming the thing, surfaced via `script_finished` and
`push_warning`. Play continues. Under B an error is an exception-free GDScript
runtime error that aborts the coroutine mid-way, leaving the player locked with a
box open and no diagnosis.

**One global runner or one per event?**
**One.** Source has one visible context. The project has one `_vm`. Anything else
invents concurrency problems that Pokémon-style games do not have.

**Nodes, Resources, scripts, or something else?**
- Event **definitions**: plain data (an op array), loaded from JSON or built by a
  GDScript builder. Not Nodes, not Resources.
- The **runner**: a `RefCounted` (as now) — no scene-tree presence, testable
  without a tree.
- **Native handlers**: plain GDScript `Callable`s registered in a static
  registry; not nodes.

## 4.3 Where `await` *is* right

`await` is excellent for **leaf operations that own the screen for a bounded
time and cannot be interrupted**: a fade, a tween, a camera pan, a particle
burst, a sprite arc, a portrait cross-fade. These have no meaningful
intermediate state to inspect or save.

That is exactly the shape of `_fade_to`, `_show_exclamation`,
`_await_movement`, `_oak_overlay.fade_in()` — and exactly the shape of source's
own `SetupNativeScript` predicates.

**Conclusion: `await` belongs *inside* commands, not *as* the command sequencer.**

---

# Part 5 — The event system design that actually makes sense

Not the brief's class list — the brief's list largely re-creates things that
exist. Here is what I would actually build, marked **[exists]**, **[new]**, or
**[don't]**.

| Component | Kind | Status | Responsibility |
|---|---|---|---|
| **`ScriptVM`** | `RefCounted` | **[exists]** | The only executor. Owns `pc`, `script_label`, call stack, `pause_reason`, result-carrying pauses, `describe()`. Never awaits, never touches a node. |
| **`ScriptVM.ScriptSource`** | inner class | **[exists]** | `label → ops[]` and `label → pages[]`. Injected. Rename mentally to "EventRegistry" — it already is one. |
| **`FlagStore`** | `RefCounted` | **[exists]** | Flags + vars + trainer-defeated + entity visibility + trigger gates + badges. **Do NOT split into FlagManager/VariableManager** — source keeps them as one save block and every consumer here already takes one object. |
| **`overworld.gd::_drive_script`** | method | **[exists, should be extracted]** | The VM↔scene bridge. See §5.2. |
| **`EventScript`** (builder) | static/`RefCounted` | **[NEW]** | GDScript authoring DSL → `Array[Dictionary]` op stream. Part 7. |
| **`NativeEventRegistry`** | static class | **[NEW]** | `String → Callable`. The `native` opcode's lookup. Callables may be coroutines. |
| **`Pause.WAIT_NATIVE`** | enum member | **[NEW]** | The single generic async pause that replaces the per-feature ones. |
| **`FieldSpecials`** | static | **[exists, extend]** | Synchronous specials only. Async ones become `native` handlers. |
| **`ScriptDriver`** | `Node` | **[NEW, extraction]** | The `_drive_script` match block + its queue drains + the UI nodes it owns, lifted out of `overworld.gd`. Pure refactor. |
| **`EventDebugger` / F-key overlay** | `CanvasLayer` | **[NEW, small]** | Renders `_vm.describe()` + the native handler name + the pending queues. The convention exists project-wide; the field one does not. |
| ~~`EventContext`~~ | — | **[DON'T]** | A god-object aggregating player/map/NPCs/flags is exactly what the current *injection* design avoids, and what makes the VM unit-testable without a scene. |
| ~~`EventCommand` as a class/Resource~~ | — | **[DON'T]** | A `Dictionary` `{op, args}` is the right representation. One class per opcode × 231 opcodes is 231 files for zero behaviour. |
| ~~`EventState` (separate)~~ | — | **[DON'T]** | The VM's own fields **are** the event state. A second copy is a second source of truth. |
| ~~Autoloads for any of this~~ | — | **[DON'T]** | The project has one autoload and uses statics deliberately. |

## 5.1 The `native` opcode — the one genuinely new mechanism

This is the whole proposal, and it is a direct port of `SetupNativeScript`.

**In `ScriptVM`** (~15 lines):

```gdscript
## `native "HandlerName"[, arg...]` — hand control to registered Godot code.
##
## The direct port of source's own SCRIPT_MODE_NATIVE / SetupNativeScript
## (script.c:70). The VM records WHO it is waiting on and stops; the driver
## looks the name up, runs it, and reports back. The VM never learns what a
## tween is — the same split every other pause already uses.
"native":
    if args.is_empty():
        pause_reason = Pause.UNKNOWN_OP
        diagnostic = "native needs a handler name"
        return false
    pending_native = str(args[0])
    pending_native_args = args.slice(1)
    pause_reason = Pause.WAIT_NATIVE
    return false

## The driver reports the handler finished. `result` (if any) goes to
## VAR_RESULT, so scripts branch on it the way they branch on any special.
func resume_after_native(result: Variant = null) -> void:
    if pause_reason != Pause.WAIT_NATIVE:
        return
    if result != null and _flags != null:
        _flags.var_set("VAR_RESULT", int(result))
    pending_native = ""
    pending_native_args = []
    pause_reason = Pause.NONE
```

**In the driver** (~12 lines, replacing the need for all future per-feature
branches):

```gdscript
ScriptVM.Pause.WAIT_NATIVE:
    if not _native_running:
        _native_running = true
        _run_native(_vm.pending_native, _vm.pending_native_args)

func _run_native(name: String, args: Array) -> void:
    var handler := NativeEventRegistry.get_handler(name)
    if handler.is_null():
        _native_running = false
        _vm.pause_reason = ScriptVM.Pause.UNKNOWN_OP
        _vm.diagnostic = "native handler '%s' is not registered" % name
        return
    var result = await handler.call(self, args)   # ← await lives HERE, alone
    _native_running = false
    if _vm != null:
        _vm.resume_after_native(result)
```

**A handler** — full Godot power, ordinary GDScript:

```gdscript
NativeEventRegistry.register("OakBallRelease", func(ow, _args):
    var ball := preload("res://scenes/fx/ball_release.tscn").instantiate()
    ow.add_child(ball)
    await ball.play(ow.entity_for("LOCALID_OAK").global_position)
    ball.queue_free()
)
```

**Why this is the right shape:**

- It is a **port**, not an invention — `ScrCmd_waitmovement` already works this way.
- The VM's external state stays intact: `pause_reason == WAIT_NATIVE` and
  `pending_native == "OakBallRelease"` are readable, printable, assertable.
- `await` is confined to exactly one function in the entire codebase.
- Interruption is still one line (`_vm = null`); the handler completes and its
  `resume_after_native` no-ops because the pause no longer matches.
- Save/load: a `WAIT_NATIVE` pause is serialisable as `{label, pc, native_name}`.
  A resumed save can either re-run the handler from its start or skip it — both
  are decidable, unlike a coroutine frame.
- **It collapses the 4-edit cost of every async special into 1** (register a
  handler).

## 5.2 Extracting `ScriptDriver`

`overworld.gd` at 3,155 lines is the real maintainability risk here — not the VM.
Roughly 700 of those lines are the script bridge: `_drive_script`,
`_start_pending_movements`, `_apply_pending_object_ops`,
`_resolve_movement_entity`, `_start_player_movement`, `_finish_script`,
`_expanded_pages`, `run_script`, `_setup_scripting`, `_do_scripted_warp`,
`_run_map_script_to_completion`, plus the `MessageBox`/`YesNoBox`/`NamingScreen`/
`FieldPartyScreen` ownership.

Lifting those into a `ScriptDriver` **Node** (child of the overworld, holding a
reference back) is a pure refactor with a clear win: the `_process` gate ordering
that is documented as load-bearing in four places becomes one readable function
instead of a 140-line prologue. **Do this before, not after, adding `native`** —
otherwise the new branch lands in the god object.

---

# Part 6 — FireRed compatibility mapping

The importer already exists and works. This table is therefore a **status
report plus a forward plan**, not a design proposal.

Legend: ✅ implemented · ⚠️ implemented with a disclosed divergence · 🔜 worth
adding · ❌ deliberately not supported

| FireRed command | Status | Godot equivalent / notes |
|---|---|---|
| `lock` / `lockall` | ✅ | **VM no-op by design.** Input locking is `_process`'s `if _vm != null: return`. Faithful — source locks in `ScriptContext_RunScript`, not in the command. |
| `release` / `releaseall` | ✅ | Same — the lock lifts when `_vm` becomes null. |
| `faceplayer` | ✅ | VM no-op; `try_interact` turns the NPC before starting the script. Correct placement. |
| `msgbox` | ✅ | **Expanded at compile time** into `lock`/`faceplayer`/`message`/`waitmessage`/`waitbuttonpress`/`release`/`return`. Keep this. |
| `message` | ✅ | `Pause.WAIT_MESSAGE` → `MessageBox.open(pages)`. Text from `map_texts.json`, expanded through `TextBuffers`. Missing text is a named diagnostic, not a blank box. |
| `waitmessage` | ✅ | No-op; waiting belongs to `waitbuttonpress`. |
| `waitbuttonpress` | ✅ | `Pause.WAIT_BUTTON` — the only pause that reads input directly. |
| `closemessage` | ✅ | No-op; box closes itself past the last page. |
| `applymovement` | ✅ | **Asynchronous, correctly** — queues into `pending_movements`, drained by the driver into `MovementRunner`. Two entities can walk at once. |
| `waitmovement` | ✅ | `Pause.WAIT_MOVEMENT`, plain `resume()` (no result). `0`/`LOCALID_NONE` = everything. |
| `trainerbattle_single` | ✅ | Arity-selected battle type; already-beaten skip; intro pages; `gotobeatenscript` vs `gotopostbattlescript` routing all reproduced. |
| `trainerbattle_double` | ⚠️ | Dispatched as a single battle. `not_enough_pkmn_text` parsed and discarded — the overworld has no two-active concept (`OverworldParty` gap, disclosed). |
| `trainerbattle_rematch[_double]` | ⚠️ | Re-fights the same static roster. `GetRematchTrainerId`'s tier table is M35. Safe because the *calling* script gates on `goto_if_defeated`. |
| `trainerbattle_no_intro` / `_earlyrival` | ✅ | Share `EventScript_DoNoIntroTrainerBattle`; `always_continues=true` carries the unconditional-fallthrough shape. |
| `giveitem` / `finditem` / `giveitem_msg` | ✅ | `STD_OBTAIN_ITEM`'s *decision structure* reproduced natively; every page is source's own string. |
| `givemon` | ⚠️ | Real `BattlePokemon` appended. Three-way `VAR_RESULT`. Full party → `MON_CANT_GIVE` (no PC exists — Rob's decision, matching source's no-storage behaviour). |
| `setflag` / `clearflag` | ✅ | `FlagStore`, name-keyed. |
| `goto_if_set` / `goto_if_unset` | ✅ | Two-arg form; label is the **last** argument. |
| `setvar` / `copyvar` / `setorcopyvar` | ✅ | `setorcopyvar`'s `VarGet` resolution is indistinguishable here because `var_get` is the single accessor — disclosed. |
| `addvar` / `subvar` | ⚠️ | **They resolve operands differently in source** (`addvar` raw immediate, `subvar` via `VarGet`) and that difference is reproduced. Symbolic constants outside the table resolve to 0 — disclosed, 9 known Hoenn-only cases. |
| `compare` | ✅ | Writes `last_compare`; pairs with the 1-arg conditional form (33 of each in the corpus). |
| `goto` / `call` / `return` | ✅ | ⚠️ **Frames are `{label, pc}`, not bare PCs** — `_jump` swaps the whole op array. This was a real shipped bug. |
| `switch` / `case` | ✅ | Macros over `VAR_0x8000` + compare + `goto_if_eq`. 2,027 `case` uses. |
| `warp` | ✅ | `Pause.WAIT_WARP` → `_do_scripted_warp`. Reads x/y as a literal **cell**. |
| `warpsilent` / `warpdoor` / `warphole` / `warpteleport` | 🔜 | Trivial variants of `warp` differing only in transition. Prime `native`-hatch candidates. |
| `fadescreen` (+ `speed`/`swapbuffers`) | ⚠️ | **No-op, and the reason is subtle**: in 106 of 128 uses the fade is closed by an engine callback (`CB2_ReturnToFieldContinueScriptPlayMapMusic`), not by a matching opcode. A faithful-looking fade would leave the screen black forever. **Must be paired with the screen transition, not with an opcode.** Best fixed via `native`. |
| `playsound` / `playse` / `playbgm` / `playfanfare` / `waitfanfare` / `playmoncry` | ⚠️ | All no-ops. **Audio does not exist anywhere in this project** — a project-wide absence tracked as M36-S, not a script-engine gap. |
| `special` | ⚠️ | Narrow carve-out: `HealPlayerParty` + 7 no-ops. **An unknown special halts, deliberately**, so coverage figures stay honest. **This is where `native` pays off most.** |
| `specialvar` | ⚠️ | 5 constants + 4 party/trade functions intercepted in the VM. ⚠️ Destination var is `args[0]`, function is `args[1]`. |
| `callnative` | ⚠️ | Routed to the same `special` handler. Should become the `native` opcode's alias. |
| `setmetatile` | ❌ → 🔜 | **1,406 uses — the biggest real gap.** Needs runtime `TileMapLayer` mutation + a per-cell override record in the save + `ON_LOAD` map scripts. See Phase 4. |
| `map_script` / `ON_LOAD` | ❌ → 🔜 | Compiler expands table entries to `map_script_2` (✅). `ON_LOAD` itself is unrun — it is where `setmetatile` lives, so the two land together. |
| `ON_RESUME` / `ON_RETURN_TO_FIELD` | ❌ → 🔜 | Not run. Needed for "hide the defeated static Pokémon" patterns. |
| `createvobject` / `turnvobject` | ❌ → 🔜 | Virtual cutscene sprites (267 uses). `native` handler. |
| `pokemart` family | ❌ → 🔜 | M27G. Needs a shop screen. |
| `setwildbattle` / `dowildbattle` | ❌ → 🔜 | Scripted static encounters (Snorlax, legendaries). Small. |
| `setobjectxy` / `hideobjectat` / `showobjectat` | 🔜 | Trivial additions to the existing `pending_object_ops` drain. |
| `getplayerxy` | 🔜 | Two var writes. Trivial. |
| `multichoice` (non-yes/no) | ❌ | 204 uses, overwhelmingly Frontier menus (M35). Halts rather than guessing. Correct. |
| `braillemsgbox` | ❌ | Braille puzzles. Kanto has none of consequence. |
| `register_matchcall` / `setberrytree` / `frontier_*` | ❌ | Hoenn / Frontier. Permanent exclusions. |
| **`ramScript`** | ❌ | **Never implement.** Executable code in a save file. The scope doc already refuses it; it should stay refused. |
| **Byte-level opcode numbering** | ❌ | No consumer. The importer reads assembly text. |
| **`VarGet`'s id-as-value fallback** | ❌ | Deliberately not reproduced — meaningless under name keys. Documented in `FlagStore`. |
| **`RunScriptImmediately`** | ⚠️ | Approximated by awaiting completion. Safe for ON_TRANSITION/ON_WARP because neither reaches a `message` (verified against every corridor map). Would become genuinely unsafe if a hand-authored one did. **Add an assertion.** |

### FireRed behaviour that should NOT be copied

1. **`ramScript`** — security hole, zero value.
2. **Numeric flag/var ids** — already correctly replaced with names.
3. **The 20-deep call stack limit** — an arbitrary hardware constraint.
4. **`VarGet`'s id-fallback quirk** — an artifact of pointer arithmetic.
5. **Silent 0-resolution of unknown constants** — the VM does this today for
   compatibility, but for *authored* content it should be a compile-time error in
   the new front-end. (Keep the lenient path for imported content.)
6. **The nurse's yes/no confirmation** — already deliberately skipped
   (`AUTO_CONFIRM_LABELS`); a fine precedent for content divergence.
7. **`SCREFF_*` effect analysis** — an optimisation for a system that does not
   exist here.

---

# Part 7 — Event data format

## 7.1 The four options against this project

| | Ease of editing | Git diffs | Editor integration | Runtime | Debugging | Modding | FireRed import | Visual editor later | Readability |
|---|---|---|---|---|---|---|---|---|---|
| **1. Pure GDScript coroutines** | 5 | 5 | 5 | 4 | 2 | 2 | **1** | 1 | 5 |
| **2. `.tres` command resources** | 2 | **1** | 4 | 3 | 3 | 2 | 3 | 4 | 2 |
| **3. JSON / custom data** | 2 | 3 | 1 | 5 | 4 | 5 | 5 | 4 | 3 |
| **4. Hybrid (recommended)** | **5** | **5** | **4** | **5** | **5** | **5** | **5** | **4** | **5** |

**`.tres` is disqualified outright.** Godot's resource serialiser rewrites
`SubResource` ids on every save; a 40-command cutscene would produce
unreviewable diffs, and the project already has a recorded scar from exactly
this class of churn (`unique_id` regeneration making `check_bake_diff.py`
necessary). A project whose CLAUDE.md contains a standing rule about
distinguishing real edits from re-bake churn should not adopt a format that
maximises churn.

## 7.2 The recommended hybrid

**One runtime representation, two authoring front-ends.**

```
                     AUTHORING                          RUNTIME
  field_script_source/**/*.inc  ──gen_map_scripts.py──┐
  (imported FireRed content,                          │
   hand-editable, 974 files)                          ├──► data/map_scripts.json
                                                      │    17,137 labels
  scripts/events/*.gd           ──EventScript.build()─┤         │
  (authored original content,                         │         ▼
   GDScript, typed, autocompleted)                    │  ScriptSource.ops_by_label
                                                      │         │
                                                      └────► ScriptVM.step()
```

The GDScript front-end:

```gdscript
# scripts/events/pallet_town.gd
class_name PalletTownEvents

static func seto_intro() -> Array:
    return EventScript.new() \
        .lock() \
        .face_player() \
        .message("SetoIntro_Greeting") \
        .apply_movement("LOCALID_SETO", Move.walk_down(2).face_west()) \
        .wait_movement() \
        .native("SetoCameraPan")                # ← full Godot power
        .trainer_battle("TRAINER_SETO", "SetoIntro_Challenge", "SetoIntro_Defeat") \
        .set_flag("FLAG_SETO_DEFEATED") \
        .release() \
        .end()
```

`EventScript` is a builder returning `Array[Dictionary]` — the exact shape
`gen_map_scripts.py` already emits. Registration at boot:

```gdscript
_script_source.ops_by_label.merge(EventRegistry.native_scripts())
```

**Everything downstream is unchanged.** Same VM, same driver, same tests, same
debug overlay, same save format, same `describe()`.

### Why this wins on every axis

- **Editing**: GDScript for new content — autocomplete, type checking, F12
  jump-to-definition, no Python regenerate step. `.inc` stays for the 17,137
  imported labels, which nobody hand-edits at scale anyway.
- **Diffs**: both front-ends are line-oriented text.
- **Runtime**: identical to today (an `Array[Dictionary]`).
- **Debugging**: unchanged and already good — `describe()` reports `label`,
  `pc`, `op`, `pause`, `diagnostic`, `page/pages`, `depth`, `last_compare`.
- **Modding**: JSON stays loadable at runtime; a mod is a JSON file merged into
  `ops_by_label`. (A GDScript mod would need `.pck` loading — offer both.)
- **Import**: untouched.
- **Visual editor later**: still possible — it edits the op array, and
  `map_overlay_editor` already proves the project can build real editor plugins.
  I would not build one; see Part 11.
- **Readability**: the builder reads close to the `.inc` while being real code.

### One caveat to design in from the start

Two front-ends means **two places a label can be defined**. Collisions must fail
loudly at boot, not silently shadow — the same discipline
`gen_trainer_data.py`'s `normalize()`-collision assertion already applies to
name→id tables. One assertion, written once.

---

# Part 8 — Map / NPC integration

## 8.1 The layering — mostly already correct

```
┌─ IDENTITY (registry, keyed by string, outlives any placement)
│   TrainerData .tres          keyed by trainer_key      1,477 files
│   PokemonSpecies / MoveData / ItemData .tres
│   ObjectEventGraphics        keyed by graphics_id      385 sheets
└─
┌─ PLACEMENT (the baked .tscn IS the source of truth)
│   NPC / TrainerNPC / ItemBall / Warp / Trigger / Sign
│   fields: cell, elevation, visibility_flag, script_label, local_id, ...
└─
┌─ WORLD STATE (FlagStore, name-keyed, saved)
│   FLAG_HIDE_*      → entity_visible(e)
│   DEFEATED_<key>   → trainer_defeated()
│   VAR_*            → trigger_armed(t), script branching
└─
┌─ EVENT DEFINITION (data, not nodes)
│   ScriptSource.ops_by_label   label → Array[{op,args}]
│   ScriptSource.texts          label → pages
└─
┌─ EXECUTION (one at a time)
│   ScriptVM (RefCounted)  +  ScriptDriver (Node)
└─
```

**An entity does not own an event. It names one** (`script_label: String`).
That indirection is what lets one script serve many placements and lets a script
outlive the chunk that referenced it. Keep it exactly as is.

## 8.2 Trigger sources — current state

| Source | Path today | Status |
|---|---|---|
| **NPC / item ball** | `try_interact` → `Interaction.resolve` → `run_script(label, entity)` | ✅ |
| **Sign** | same, with `_facing_satisfies` gate | ✅ |
| **Metatile behaviours** (PC, bookshelf, TV — 31 `readable` behaviours) | Interaction sources 3 and 4 | ❌ **not implemented** — source tries them *after* objects and signs |
| **Doors** | `_try_door_warp` / `_try_arrow_warp` off `Warp` nodes | ✅ (`opendoor`/`closedoor` are cosmetic no-ops) |
| **Warps** | `_do_warp` on step completion | ✅ |
| **Scripted warps** | `Pause.WAIT_WARP` → `_do_scripted_warp` | ✅ |
| **Hidden items** | `Sign.item` field carried; hidden-item flow | 🔜 partial |
| **Trainers (sight)** | `check_trainer_sight` → `_run_trainer_approach` → `_run_trainer_script` | ✅ |
| **Step triggers** (`coord_events`) | `check_step_trigger` + `FlagStore.trigger_armed` | ✅ |
| **Map scripts ON_TRANSITION / ON_WARP** | `_run_arrival_map_scripts` (awaits completion) | ✅ |
| **ON_FRAME table** | `check_on_frame_map_script` at step-completion cadence | ✅ (⚠️ source polls every raw frame; disclosed, equivalent in practice) |
| **ON_LOAD / ON_RESUME / ON_RETURN_TO_FIELD / ON_DIVE_WARP** | — | ❌ **not run** |
| **Cutscenes** | Either a script (`OnFrame`-triggered) or a free coroutine (`run_new_game`) | ⚠️ **the inconsistency to fix** |
| **Wild encounters** | `_wild_step` on step completion (not script-driven) | ✅ (divergence from `setwildbattle`, fine) |
| **Field poison** | `_poison_step` (not script-driven) | ⚠️ source runs `EventScript_FieldPoison` with `lockall`; here the lock is expressed by returning early. Works, but it is a second lock mechanism. |

The one architectural inconsistency worth naming: **there are currently two ways
to be a cutscene** (a VM script, or a free `await` coroutine). Every free
coroutine needs its own input driver. `run_new_game` should become a `native`
handler invoked from an `EventScript`-authored script, and `_poison_step`'s
message should go through the VM. Then there is exactly one.

## 8.3 The distinction the brief asks for, stated

| Concept | Where it lives | Lifetime |
|---|---|---|
| **NPC definition** | `TrainerData.tres` / `ObjectEventGraphics` / species data | Forever, global |
| **NPC placement** | a node in `scenes/maps/<Map>.tscn` | While the chunk is loaded |
| **NPC interaction** | `Interaction.resolve` — *which* event a press of A targets | One frame |
| **Event** | `ops_by_label[label]` — pure data | Forever, global, immutable |
| **EventRunner** | `ScriptVM` instance — `pc`, stack, pauses | One script's execution |
| **World state** | `FlagStore` (+ `Bag`/`Wallet`/`party`/`respawn` on `OverworldSession`) | The playthrough; saved |

---

# Part 9 — Performance

Short answer: **not a concern, and the current design is already the fast one.**

**Thousands of NPCs.** `MapManager.tick_entities` walks loaded-chunk entities
per frame. This scales with *loaded chunks*, not with the world. A Kanto map's
worst case is ~30 object events; a few stitched chunks is ~100. The existing
per-axis skirt (12×9) and chunk load/unload already bound it. No change needed.

**Are GDScript async functions appropriate?** Under the recommendation, only one
`await` exists (`_run_native`). Coroutine allocation is irrelevant at that
frequency.

**Instantiate events only when triggered?** Already true and free — an "event"
is a slice of an already-parsed `Dictionary`. `run_script` allocates one
`RefCounted` and `_ops.assign(ops_for(label))`.

**Should definitions be Resources?** **No.** `map_scripts.json` is 8.9 MB parsed
once at boot into a `Dictionary`. 17,137 `.tres` files would be catastrophically
worse — Godot's resource loader per-file overhead, plus `.import` metadata, plus
17,137 files in git. The one measurement worth taking: boot-time JSON parse
cost. If 8.9 MB parse ever shows up, the fix is a binary `.res` `Dictionary`
dump, **not** a format change.

**Centralised event system?** Yes — one `_vm` slot. Also correct semantically
(source has one context).

**Compiled / cached?** Already compiled (Python → JSON at author time) and
already cached (parsed once into `_script_source`). ✅

**Is a multi-frame event expensive?** `_drive_script` runs `while _vm.step() and
guard < 500` per frame — up to 500 `Dictionary` lookups + a `match`. That is
microseconds, and 500 is a runaway guard, not a typical count. A real script
executes 1–20 ops between pauses.

**Interaction with chunk streaming.** The one genuine risk: **an event outliving
the chunk that contains its subject.** Already partly handled — `_vm.subject` is
an `OverworldEntity` reference, and `_resolve_movement_entity` looks up
`local_id` fresh each time. But `subject` itself could dangle across a scripted
warp. Recommended hardening (small, and worth doing regardless of this
decision): store the subject's `local_id` alongside the reference and re-resolve
on use, or `is_instance_valid()`-guard every `subject` read.

**Premature optimisation to avoid:** object pooling for events, a bytecode
re-encoding of the JSON, multi-threaded script execution, an ECS for NPCs. None
of these have a problem to solve here.

---

# Part 10 — Save / load

## 10.1 What is saved today

`SaveManager.build_payload` → `user://saves/slot<N>/slot.json`, `FORMAT_VERSION 1`:

```json
{
  "version": 1,
  "playtime": 3271,
  "identity": {...},
  "flags":  {"flags": {"FLAG_BADGE01_GET": true, ...},
             "vars":  {"VAR_MAP_SCENE_PALLET_TOWN": 3, ...}},
  "bag": {...}, "wallet": {...}, "respawn": {...}, "party": [...],
  "position": {"map": "PewterCity_Frlg", "x": 14, "y": 22,
               "facing": 0, "elevation": 3}
}
```

**No script state is saved. That is correct and deliberate.**

## 10.2 Should an event survive a save/load mid-execution?

**No — and Pokémon games are architecturally built so the question never
arises.** Three mechanisms, all already present here:

1. **Saving is itself a scripted action.** You save from the START menu, which
   `_process` gates behind `_vm == null`. You literally cannot open it during a
   cutscene.
2. **Progress is recorded in flags and vars, not in a program counter.** The
   `VAR_MAP_SCENE_*` idiom is exactly this: a cutscene's first act sets the var
   to 1, the second to 2, and the map's `OnFrame`/`OnTransition` table dispatches
   on it. The var is the save state; the script is a pure function of it.
3. **Autosave does not exist**, and should not be added mid-cutscene.

Source itself takes the same position: `gSaveBlock` has no `scriptPtr` field. The
only executable thing in the save is `ramScript`, which this project has already
refused.

## 10.3 The right rule, stated

> **Events are re-entrant from world state, never resumed from execution state.**
> A cutscene must leave the world in a state from which it can be correctly
> re-derived on the next load. This is what `VAR_MAP_SCENE_*` is for.

Two engineering consequences:

- **`run_script` must remain forbidden while the save menu is reachable** — it
  already is.
- **A long cutscene should set its progress var at each act boundary**, so a
  crash or a quit loses at most one act. This is an authoring convention worth
  writing into the field-script authoring doc, and the `EventScript` builder can
  offer `.checkpoint("VAR_MAP_SCENE_X", 2)` as sugar for `setvar`.

## 10.4 What each state category needs

| Category | Where | Saved? | Notes |
|---|---|---|---|
| Flags | `FlagStore._flags` | ✅ | Only set flags stored |
| Variables | `FlagStore._vars` | ✅ | `from_save` coerces types — untrusted input |
| String buffers | `TextBuffers` | ❌ **correct** | Runtime-only, like `gStringVar1-3` |
| NPC visibility | `FLAG_HIDE_*` in `FlagStore` | ✅ | Free — it is just a flag |
| NPC position/facing changed by script | **nowhere** | ❌ **GAP** | `setobjectxyperm` mutates `e.cell` on a node that dies with the chunk. Source persists this in `gSaveBlock1.objectEventTemplates`. **Real, worth flagging.** |
| Quest state | `VAR_*` | ✅ | |
| Event execution state | — | ❌ **correct** | See §10.2 |
| Map metatile changes (`setmetatile`) | **nowhere** | ❌ | Blocks `setmetatile`. Source re-derives via `ON_LOAD` on every map entry — **adopt that**, it needs no new save data |
| Party / bag / wallet / respawn / identity / playtime / position | `OverworldSession` | ✅ | |

**Two findings worth flagging (found during this investigation, deliberately not
fixed):**

1. **`setobjectxyperm` / `setobjectmovementtype` / `turnobject` are not
   persisted.** They mutate `OverworldEntity` nodes that are freed by
   `_teardown_and_load`. Walk out of a room and back in and the NPC is at its
   baked position again. Source keeps a mutable `objectEventTemplates` copy in the
   save block for exactly this. Small, real, and it will bite the first cutscene
   that parks an NPC somewhere new permanently.

2. **`ScriptVM.removed_objects` is a second, parallel record of the same event as
   `pending_object_ops`'s `remove`.** The VM's own comment acknowledges this
   ("the second, functionally-consumed record of the same event, not a
   replacement"). It is a documented duplication, not a bug — but it is the kind
   of thing that drifts.

---

# Part 11 — Recommendation

## 11.1 What I recommend

**Architecture C+ — keep `ScriptVM` as the single execution engine; add a
GDScript authoring front-end and a `native` escape hatch. Do not build an
`EventRunner`.**

Four concrete changes, in dependency order:

1. **Extract `ScriptDriver` from `overworld.gd`.** Pure refactor. ~700 lines out
   of a 3,155-line god object. Do this first so everything after lands somewhere
   sane.
2. **Add the `native` opcode + `NativeEventRegistry` + `Pause.WAIT_NATIVE`.**
   ~40 lines total. A direct port of `SetupNativeScript`. This is where `await`
   lives, and it lives in exactly one function.
3. **Add `EventScript`, a GDScript builder producing the same op stream.** New
   content authored in real GDScript; imported content untouched.
4. **Fold the free-floating coroutines into it** — `run_new_game`, the field
   poison message — so there is exactly one way to be a cutscene and exactly one
   input driver.

## 11.2 Why

**Because the hybrid already exists and works, and the brief's own diagram is a
description of it.** Building an `EventRunner` would replace a 92%-complete,
229-assertion-tested, save-compatible, inspectable system with an untested one
whose two weakest properties (save/load and testability) are the two this project
has invested most heavily in.

The five decisive facts:

1. **92.3% of all field-script command uses across the entire corpus already
   run.** 17,137 labels compiled, 11,451 dialogue entries extracted, 32 maps
   playable end to end including a full gym.
2. **The `await` experiment has already been run here and produced a documented
   defect** — a cutscene that could not be answered from the keyboard because it
   bypassed the VM's input driver. One cutscene, one split driver. A game's worth
   would be systematic.
3. **The VM's external state is what the test suite, the debug convention, the
   degradation reports and the save format are all built on.** `await` deletes
   all four properties in exchange for prettier source.
4. **`native` is a *port*, not an invention.** `SetupNativeScript` /
   `SCRIPT_MODE_NATIVE` is first-class in source and `ScrCmd_waitmovement` is
   built on it. Adding it makes the project *more* faithful, not less.
5. **The real bottleneck is authoring ergonomics and the special-dispatch cost,
   and both are front-end problems.** The runtime is not what is slowing anything
   down.

## 11.3 What NOT to build

- ❌ An `EventRunner` that executes `await`-chained commands.
- ❌ `EventCommand` as a class hierarchy or as `.tres` resources.
- ❌ `EventContext` as a god-object. Injection already works and is what makes
  the VM testable without a scene tree.
- ❌ Separate `FlagManager` and `VariableManager`. `FlagStore` is both, matching
  source's single save block.
- ❌ A separate `EventState`. The VM's fields are the state.
- ❌ Any new autoload. The project has one and uses statics deliberately.
- ❌ A visual event editor. `map_overlay_editor` cost real effort and its own
  session; there is no evidence a *script* editor would beat GDScript with
  autocomplete. Revisit only if authoring volume proves it.
- ❌ Byte-level FireRed compatibility. No ROM will ever be loaded.
- ❌ `ramScript`. Ever.
- ❌ Multiple concurrent script contexts.
- ❌ Rewriting the importer.

## 11.4 Minimum viable implementation

Roughly one session:

```
scripts/overworld/native_events.gd      NativeEventRegistry (static, ~40 lines)
scripts/overworld/script_vm.gd          + Pause.WAIT_NATIVE
                                        + "native" / "callnative" case
                                        + pending_native, pending_native_args
                                        + resume_after_native()
scenes/overworld/overworld.gd           + WAIT_NATIVE branch, + _run_native()
scenes/overworld/m27f_script_vm_test.gd + a NATIVE section
```

Proof of value: register one handler that replaces a currently-halting
`special`, and one that does something FireRed cannot express (a camera pan, a
screen shake). Both from an existing imported script.

## 11.5 The eventual full architecture

```
AUTHORING
  field_script_source/**/*.inc  ──gen_map_scripts.py──┐  imported FireRed content
  scripts/events/*.gd (EventScript builder) ──────────┤  authored original content
                                                      │
COMPILED FORM                                         ▼
  data/map_scripts.json  +  EventRegistry.native_scripts()
  data/map_texts.json
                                                      │
EXECUTION                                             ▼
  ScriptDriver (Node)  ◄──── owns MessageBox, YesNoBox, NamingScreen,
     │                       FieldPartyScreen, FieldBagScreen, movement drain,
     │                       object-op drain, native dispatch
     ▼
  ScriptVM (RefCounted)  ── pc, label, call stack, pause_reason, describe()
     │
     ├── FlagStore ─────────────────► SaveManager (JSON, one slot dir)
     ├── Bag / Wallet / RespawnPoint / BattleParty / TextBuffers
     ├── FieldSpecials      (synchronous specials)
     └── NativeEventRegistry (async / Godot-native handlers)
                │
                └── await ──► tweens, particles, camera, shaders, overlays,
                              battle mount, screen transitions
     ▼
  MapManager · MovementRunner · WeatherManager · battle screens
     ▼
  EventDebugger (F-key overlay: describe() + native name + queues)
```

## 11.6 Major risks

| Risk | Severity | Mitigation |
|---|---|---|
| **`native` becomes the default and scripts hollow out** | **High** | A written rule: `native` is for *presentation and engine capability*, never for control flow or state. Control flow stays in the op stream so it stays inspectable and re-derivable. Enforce by review; consider a lint over the handler registry. |
| **Two front-ends diverge** (a builder method whose op the VM does not implement) | Medium | Boot-time assertion: every op the builder can emit is in the VM's `match`. Cheap, and this project already does exactly this kind of assertion for name→id collisions. |
| **Label collisions between JSON and native scripts** | Medium | Fail loudly at merge, never shadow. One assertion. |
| **`overworld.gd` keeps growing** | **High — already realised** | Extract `ScriptDriver` *first*. This is the top maintainability risk in the whole area, independent of this decision. |
| **`native` handlers `await` on freed nodes** | Medium | Guard `_run_native`'s resume on `_vm != null` (already in the sketch) and `is_instance_valid` in handlers. Contain the coroutine to one function so there is one place to get this right. |
| **`_vm.subject` dangles across a warp** | Medium | Store `local_id` beside the reference; re-resolve on use. |
| **Script-driven NPC repositioning is not persisted** | Medium | Add a per-map object-event override dictionary to the save (source's `objectEventTemplates`). |
| **`setmetatile` stays unimplemented** | Medium | 1,406 uses. Land it with `ON_LOAD` so it needs no new save data. |
| **Boot-time JSON parse cost grows** | Low | Measure. If it matters, dump a binary `.res` — a build-step change, not a format change. |
| **The 569-special tail is genuinely large** | Medium | `native` makes each one cheap. Port on demand, driven by the corridor. Keep the halt-on-unknown discipline — it is what makes coverage figures honest. |

## 11.7 What should stay FireRed-compatible

- The **command vocabulary and names** — the importer depends on them, and they
  are a good, proven vocabulary for this genre.
- **Flag/var semantics** — unset flag = false, unset var = 0, `VAR_RESULT`
  conventions, `VAR_0x8000-9` scratch, the `DEFEATED_*` derived flag.
- **`applymovement` asynchrony + `waitmovement` blocking.** This is subtle,
  correct, and load-bearing for every multi-actor cutscene.
- **The `trainerbattle` outcome routing** — already faithfully reproduced across
  five variants, including the two *different* continuation shapes.
- **Map script types and their order.**
- **The `msgbox`/`callstd` expansion**, done at compile time.
- **The one-script-at-a-time model.**
- **Text control codes** — `\n`, `\p`, `{PLAYER}`, `{STR_VAR_n}`.
- **`local_id` / `LOCALID_*` addressing.**
- **The interaction dispatch order, including the counter hop.**

## 11.8 What should deliberately differ

| | Why |
|---|---|
| **Name-keyed flags/vars, not numeric ids** | Already done. The importer carries names; ids would be a second identity to maintain. |
| **JSON IR, not bytecode** | Readable, diffable, greppable, hand-editable. No ROM consumer. |
| **`native` handlers instead of a fixed `gSpecials[]` table** | Registration beats a compiled table; handlers can be coroutines. |
| **No `ramScript`** | Security. |
| **No 20-deep stack limit** | An arbitrary hardware constraint. |
| **Halt-and-name on unknown opcode, rather than undefined behaviour** | Keeps coverage honest. This is a genuine improvement over source. |
| **Three save slots** | Already this project's own invention; GBA has one. |
| **Authored dialogue overrides (`TEXT_OVERRIDES`) and the nurse auto-confirm** | The project's premise is Kanto geometry with an original story. Content divergence is the *point*. |
| **GDScript as a first-class authoring language** | The thing the brief is actually asking for, delivered without touching the runtime. |
| **Battles as an overlay, not a scene swap** | Already done; 66–100 ms chunk rebuild avoided. |

---

# Part 12 — Roadmap

Each phase is independently valuable and independently shippable. **Phases 1–3
are the recommendation; 4–7 are ordinary M27 work that becomes much cheaper once
1–3 exist.**

---

## Phase 1 — Extract `ScriptDriver`

**Goal.** Lift the script↔scene bridge out of `overworld.gd` with zero
behaviour change, so every later phase has somewhere to land.

**Files.**
- new `scripts/overworld/script_driver.gd` (`class_name ScriptDriver extends Node`)
- `scenes/overworld/overworld.gd` — becomes a thin caller
- move: `_drive_script`, `_start_pending_movements`, `_apply_pending_object_ops`,
  `_resolve_movement_entity`, `_finish_script`, `_expanded_pages`, `run_script`,
  `_setup_scripting`, `_on_script_name_chosen`, and ownership of `MessageBox` /
  `YesNoBox` / `NamingScreen` / `FieldPartyScreen`
- keep on `overworld.gd`: `_start_player_movement`, `_do_scripted_warp`,
  `_do_warp` (they mutate player/chunk state)

**Dependencies.** None.

**Test.** Every existing overworld suite, unchanged, must stay green — that *is*
the acceptance criterion for a pure refactor. Plus: `script_started` /
`script_finished` still fire with the same payloads; the `_process` gate ordering
(yes/no → message → naming → party → bag → start menu → script) is preserved
verbatim, with its load-bearing comments moved intact.

**Done when.** `overworld.gd` is under ~2,500 lines; the full overworld suite is
green with no assertion edits; `check_bake_diff.py` still clean.

**Do NOT yet.** Change any behaviour. Add `native`. Touch the VM. Rename pauses.

---

## Phase 2 — The `native` opcode

**Goal.** One generic async escape hatch; `await` confined to one function.

**Files.**
- new `scripts/overworld/native_events.gd` — `NativeEventRegistry`
  (`register(name, Callable)`, `get_handler(name)`, `has(name)`, `names()`)
- `scripts/overworld/script_vm.gd` — `Pause.WAIT_NATIVE` (**appended**, so no
  ordinal shifts — the same discipline `WAIT_BATTLE` used), `pending_native`,
  `pending_native_args`, the `"native"` case, `resume_after_native()`,
  `describe()` reports the handler name
- `scripts/overworld/script_driver.gd` — the `WAIT_NATIVE` branch + `_run_native`
- `scripts/gen_map_scripts.py` — accept `native` as a known command
- `docs/field_script_authoring.md` — document the new command

**Dependencies.** Phase 1.

**Test.** New section in `m27f_script_vm_test.gd`:
- `native` raises `WAIT_NATIVE` and records the handler name
- an unregistered handler → `UNKNOWN_OP` with a naming diagnostic (**not** a
  crash, matching `special`'s existing discipline)
- `resume_after_native(value)` writes `VAR_RESULT` and the following
  `goto_if_eq` branches correctly
- `resume()` alone does **not** clear `WAIT_NATIVE` (result-carrying pause —
  same guard as `WAIT_BATTLE`/`WAIT_NAMING`/`WAIT_PARTY_CHOICE`)
- abandoning the script mid-handler (`_vm = null`) does not error when the
  handler finishes
- a handler that yields across frames leaves `pause_reason == WAIT_NATIVE`
  observable throughout

**Done when.** One real handler ships end to end — recommended:
`fadescreen` FADE_TO_BLACK properly paired with the screen transition, replacing
the current no-op (128 corpus uses, 106 of them unpaired, and the existing
comment explicitly asks for exactly this pairing).

**Do NOT yet.** Migrate `run_new_game`. Port the special tail. Add the builder.

---

## Phase 3 — `EventScript`, the GDScript authoring front-end

**Goal.** Author original content in GDScript, executed by the same VM.

**Files.**
- new `scripts/overworld/event_script.gd` — the builder
- new `scripts/overworld/movement_script.gd` — a movement-action builder (`Move`)
- new `scripts/overworld/event_registry.gd` — collects native scripts, merged
  into `ScriptSource.ops_by_label` at boot, **failing loudly on label collision**
- new `scripts/events/` — where authored events live
- `script_driver.gd::_setup_scripting` — the merge + the collision assertion

**Dependencies.** Phase 2 (so `.native()` exists in the builder from day one).

**Test.**
- **Round trip**: a builder-produced op array is byte-identical in structure to
  the compiler's output for the same script (compare against a real
  `map_scripts.json` entry — this is the single most valuable assertion in the
  phase)
- every builder method emits an op the VM's `match` implements (**boot-time
  assertion**, mirroring `gen_trainer_data.py`'s normalize-collision guard)
- a duplicate label across JSON and native fails loudly
- an authored script runs end to end through the unmodified driver

**Done when.** One real authored cutscene — original story content, not a port —
runs in the corridor with a `native` beat in it, and `describe()` reports it
identically to an imported script.

**Do NOT yet.** Migrate imported content. Build a visual editor. Add a text DSL
or a parser — the builder is enough.

---

## Phase 4 — `setmetatile` + `ON_LOAD`

**Goal.** Close the largest genuine opcode gap (1,406 uses).

**Files.** `script_vm.gd` (`setmetatile`, `setmetatile_impassable` variants),
`script_driver.gd` (a `pending_tile_ops` drain, same shape as
`pending_object_ops`), `map_manager.gd` (runtime `TileMapLayer` cell writes
honouring §1.6 plane routing), `overworld.gd::_run_arrival_map_scripts` (add
`ON_LOAD` **before** the layout is drawn, and `ON_RESUME` on return-to-field).

**Dependencies.** Phase 1. Independent of 2/3.

**Test.** A cell's behaviour changes and `StepResolver` sees it; the change
survives a warp out and back **because `ON_LOAD` re-derives it from flags**, not
because it was saved; the three-plane routing is respected (a `COVERED` metatile
paints two planes).

**Done when.** A real corridor script that opens a path (a gym door, a boulder)
works, and re-entering the map reproduces it.

**Do NOT yet.** Persist metatiles in the save — `ON_LOAD` re-derivation is
source's own answer and needs no new save data.

---

## Phase 5 — Migrate the free coroutines

**Goal.** Exactly one way to be a cutscene; exactly one input driver.

**Files.** `overworld.gd::run_new_game` → an `EventScript`-authored script whose
visual beats are `native` handlers (`OakPortrait`, `OakBallRelease`,
`OakGenderPick`, `OakFadeOut`). `field_poison.gd`'s message → a VM script.
Then **delete the duplicate yes/no input driver** in `_process` (the one added
for M27L L2) and the `_vm == null` message-box branch — the VM's own driver
becomes the only one.

**Dependencies.** Phases 1–3.

**Test.** The full new-game sequence is answerable **from real key presses**, not
from direct `confirm()` calls — this is the specific bug being retired, and the
test must not repeat the mistake that hid it. Assert that `_process` contains one
yes/no driver, not two.

**Done when.** `run_new_game` is gone as a coroutine, the duplicate drivers are
deleted, and `m27k_newgame_test` passes driving real input.

**Do NOT yet.** Migrate imported scripts (there is nothing to gain).

---

## Phase 6 — The special / `callnative` tail, on demand

**Goal.** Turn a 4-edit cost into a 1-edit cost and work through the corridor's
real needs.

**Files.** `native_events.gd` (handler registrations, grouped by area),
`field_specials.gd` (synchronous ones only), `script_vm.gd` (route `special` /
`specialvar` / `callnative` through `NativeEventRegistry` **after**
`FieldSpecials`, before the halt).

**Dependencies.** Phase 2.

**Test.** Per handler, against its own source function. **Keep halt-on-unknown** —
it is the only honest coverage measure.

**Done when.** Every special reachable from the baked corridor is either
implemented, a documented no-op, or a documented halt. Re-measure coverage and
record the number (the current one is admittedly stale).

**Do NOT yet.** Attempt all 569. Port Frontier/Contest/Match Call specials.

---

## Phase 7 — Remaining opcodes and hardening

**Goal.** Close the small tail and the two flagged persistence gaps.

**Scope.** `createvobject`/`turnvobject`; `setobjectxy`/`hideobjectat`/
`showobjectat`; `getplayerxy`; `setwildbattle`/`dowildbattle`; the `warp`
variants; `setescapewarp`/`setdynamicwarp`; `multichoicedefault`/`dynmultipush`;
the `pokemart` family (needs a shop screen — its own session). Plus:
**persist script-driven object-event changes** (source's `objectEventTemplates`
equivalent), and **re-resolve `_vm.subject` by `local_id`** rather than holding a
node reference across a warp.

**Dependencies.** Phases 1–3; shops depend on M27G's own scoping.

**Test.** Per opcode, against source. Plus a warp round-trip test asserting a
script-moved NPC stays moved.

**Done when.** Field-command coverage is re-measured above 96% excluding
Hoenn/Frontier content, and the two persistence gaps are closed.

**Do NOT yet.** Contest, Frontier, Match Call, berry trees, braille, link.

---

# Appendix — The question, answered directly

> **What is the simplest architecture that gives me the flexibility of native
> Godot development while preserving enough FireRed scripting concepts that
> FireRed maps/scripts can eventually be imported?**

**The one you already have, plus two additions totalling well under 200 lines:**

1. **A `native` opcode** that suspends the VM on a registered GDScript
   coroutine — a direct port of source's own `SetupNativeScript`, which gives
   you unlimited Godot-native power (tweens, particles, camera, shaders,
   overlays) inside the existing execution model, with `await` confined to a
   single function.

2. **A GDScript builder** that produces the same op stream the importer does —
   so original content is authored in a typed, autocompleted language while
   imported content keeps working untouched.

FireRed scripts do not need to "eventually" be importable. **17,137 of them are
compiled and 92.3% of all command uses already run.** The importer is the most
finished part of this system. The unfinished part is the authoring experience for
*your own* story — and that is a front-end problem, not a runtime one.

Do not build an `EventRunner`. You already have one; it is called `ScriptVM`, it
does not use `await`, and the reasons it does not use `await` are written in its
own header and have since been vindicated by a real, recorded bug in the one
cutscene that ignored them.
