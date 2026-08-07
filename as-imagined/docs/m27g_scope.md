# M27G scope — the field script engine, G4 onward

**Scope of record for M27G phases G4–G9.** Written 2026-08-07, following an
architecture investigation prompted by Rob's question of whether to replace
`ScriptVM` with a native Godot/GDScript `EventRunner` built on `await`.

**Companion documents, both still current, neither superseded:**

- `docs/m27g_recon.md` — the `special`/`specialvar`/`callnative` surface
  recon (2026-08-06). Scope of record for **G1–G3**, which have shipped, and
  for the reachability method this document leans on.
- `docs/m27g_architecture_recon.md` — the full investigation behind this
  scope: the A/B/C architecture comparison, the `await` analysis, the FireRed
  execution-model research, the 30-row command mapping, and the measured
  coverage figures. **Read that for the reasoning; read this for the work.**
- ⚠️ **`docs/m27_corridor_opcode_scope.md`** (2026-08-07) — **the scope of
  record for WHICH opcodes and specials to implement.** Written the same day
  as this document and found only after it was drafted. It supersedes this
  document's own G8/G9 content lists entirely; see §2.4 for the
  reconciliation and for why the two audits measure genuinely different
  things rather than disagreeing.

`docs/overworld_scope.md` §30 remains the scope of record for M27 as a whole
and reserves this block: *"M27G | Field script engine — its own block,
post-specials-scoping. 30–40% of the milestone."* That precondition is
satisfied — the specials scoping is `m27g_recon.md`.

---

## 0. TL;DR

1. **The answer to the architecture question is: do not replace `ScriptVM`.**
   This project already runs the hybrid architecture the question proposes
   building. `ScriptVM` is not a GBA bytecode VM; it is a Godot-native
   interpreter over a JSON IR, and it covers **92.3%** of all field-script
   command uses in the corpus.
2. **Two additions, both small, one of them the block's centrepiece:**
   a `native` opcode (a direct port of source's own `SetupNativeScript`), and
   an `EventScript` GDScript authoring front-end that compiles to the same op
   stream. Together well under 200 lines of new engine code.
3. **The problem being solved is not "the runtime is wrong."** It is that the
   field engine can express **logic but not presentation** — `fadescreen`,
   `dofieldeffect`, `showmonpic`, `opendoor` and their siblings are all silent
   no-ops today, with nothing a script can reach — and that authoring original
   story content currently means GBA assembler plus a Python regenerate step.
4. **Three Step 0 findings in §2**, two of which correct existing documents.
5. **Five decisions for Rob in §8.**

---

## 1. What this block is, in one diagram

```
                    ┌── FireRed/ASM ──→ gen_map_scripts.py ──┐
                    │   (imported Kanto content,              ↓
Authoring ──────────┤    17,137 labels, unchanged)    JSON/IR op stream
                    │                                         ↓
                    └── GDScript EventScript ────────────────→ ScriptVM
                        (authored original content)            ↓
                                                      Godot game systems
                                                               ↓
                                                        native "Name"
                                                               ↓
                                                     NativeEventRegistry
                                                               ↓
                                              await → tweens, camera, particles,
                                                      shaders, fades, overlays
```

**Two authoring paths, one runtime.** That invariant is load-bearing and §7
records the two mechanical guards that keep it true.

---

## 2. Step 0 findings

Per the standing rule, these are reported before any implementation, and two
of them contradict framings already recorded in this project's own docs.

### 2.1 The architecture question's premise did not match the codebase

The question contrasted a "literal FireRed VM" against a native GDScript
event system and asked which to build. **`ScriptVM` has never been the
former.** It never touches a byte, an opcode number, a ROM pointer or a
`gScriptCmdTable` index. Its op stream is
`{"op": "goto_if_eq", "args": ["VAR_X", "3", "Label"]}` — a JSON IR compiled
from hand-editable assembly text by `gen_map_scripts.py`.

That IS the "event representation" layer the hybrid architecture calls for.
The disagreement was never about pipeline shape; it was about the authoring
front-end and the missing escape hatch, both of which are addressed here
without touching the runtime.

### 2.2 ⚠️ The special surface figure in circulation is corpus-wide, and the actionable one is 17× smaller

`FieldSpecials`' own header, `[M27F Stage 4]`, and M27's roadmap row all
carry **"2,109 uses across 569 distinct functions"**. That figure is correct
*as a measurement of the whole compiled corpus* — which mixes Kanto with
Hoenn, and field scripts with battle-animation and contest-AI scripts.

`m27g_recon.md` already corrected this on 2026-08-06 by walking reachability
from the 32 baked maps: **51 distinct functions / 99 uses**, of which roughly
a third are Cable Club / Union Room / Colosseum-gated and therefore
permanently excluded. **The real near-term surface is ~34 functions.**

⚠️ **This materially changes how G8 should be sized and argued.** `native`'s
value is *not* primarily grinding through 569 functions. It is (a) making
those ~34 cheap, and (b) unlocking the presentation capability that no number
of specials would provide, because it does not exist in this project at all.
A future session sizing G8 off the 569 figure would over-scope it by an order
of magnitude.

### 2.3 ⚠️ The M27F/M27G boundary in `overworld_scope.md` §30 is stale

As written:

| Block | §30 says | What actually shipped |
|---|---|---|
| **M27F** | "Dialogue & interaction — interaction, **Dialogue Manager wiring**, speaker names" | The entire script VM (Stages 1–4 plus the "Map scripts" batch), `Interaction`, `MessageBox`, `TextTyper`, `YesNoBox`, `TextBuffers` |
| **M27G** | "Field script engine" | The `special` surface (G1–G3) |

Two consequences worth recording rather than silently absorbing:

1. **The block names are swapped relative to reality.** F built the field
   script engine; G is doing specials and will now do the rest of the engine.
   Someone reading §30 cold would misplace every phase in this document.
2. **"Dialogue Manager wiring" never happened, and deliberately.**
   `addons/dialogue_manager` is present on disk but **its plugin is not
   enabled**, there are zero `.dialogue` files, and the single file that
   references it (`text_typer.gd`) is a **vendored copy** whose header records
   an explicit, reasoned refusal to integrate with the plugin (the
   `type_out()` contract reads a `dialogue_line` object from four private
   seams, and upstream rewrote that interaction in v3.8.0). That was the right
   call and it is well documented at the vendoring site — but §30 still names
   the wiring as planned work, and CLAUDE.md still describes the plugin as an
   approved, scope-bounded dependency without recording that it went unused.

**Neither is fixed here.** §9 lists the one-line corrections needed and they
are Rob's call to apply.

### 2.4 ⚠️ This document's own G8/G9 content lists were over-scoped, and are superseded

`docs/m27_corridor_opcode_scope.md` was written the same day as this document
and found only after it was drafted. It audits the **32 baked map scenes**
directly — parsing each map's own `scripts.inc` for label boundaries (924
labels, 546 with real op lists), diffing every op name against
`ScriptVM.step()`'s dispatcher, then BFS-ing from those 546 labels through
every `goto`/`call`/`goto_if_*`/`case` target (686 labels reached).

Its results are **tighter and more current than §2.2's**, and they change two
of this document's phases:

| | This document originally said | The corridor audit measured |
|---|---|---|
| **Specials remaining** | "~34 functions to port" | **39 reachable names: 17 already implemented, 18 permanently-excluded multiplayer, 4 blocked on M33/M30/friendship. "No specials work is proposed here."** |
| **Missing opcodes** | `createvobject`/`turnvobject` (267), `setobjectxy`, `getplayerxy`, `setwildbattle`, warp variants, `multichoicedefault`… | **Six, total: `map_script` (verified closed), `fadeoutbgm`, `setmetatile`, `copyobjectxytoperm`, `multichoicegrid`, `pokemart`.** Everything else on my list is corpus-wide and **not corridor-reachable**. |
| **`setmetatile`** | "1,406 uses — the biggest genuine gap" | **2 uses, one script** (`ViridianCity_Mart_EventScript_HideQuestionnaire`) |

**My figures were corpus-wide; theirs are corridor-scoped, and the corridor is
Rob's chosen boundary.** This is the same class of correction `m27g_recon.md`
already made once for specials and `[M27F]` made once for opcodes — applied
here to my own numbers. **G8 and G9 below are rewritten accordingly.**

⚠️ **BUT THE TWO AUDITS ARE BLIND TO DIFFERENT THINGS, AND THAT IS THE WHOLE
REASON THIS BLOCK STILL HAS WORK IN IT.**

The corridor audit diffs op names **against `ScriptVM.step()`'s dispatcher**.
So it finds opcodes that **halt the VM** — and it is structurally incapable of
finding opcodes that are **in the dispatcher and do nothing**. `fadescreen`,
`dofieldeffect`, `showmonpic`, `opendoor`, `waitdooranim`, `showmoneybox` and
their siblings all sit in that `match` returning `true`. They are dispatched,
they are covered, and they are silent.

Two different gaps:

- **"What halts"** → `m27_corridor_opcode_scope.md`. Content work. Largely
  small; one real subsystem (`pokemart`).
- **"What runs and does nothing"** → §3.1 of this document. Capability work.
  This is what G5 exists for, and no amount of the first kind reaches it.

Neither audit supersedes the other. **Both are needed, and they should be
sequenced together** — see §8 decision 6.

---

## 3. What this block affords

Stated as capability, cost and risk rather than as architecture, because the
architecture is already right.

### 3.1 Capability — the engine can express logic but not presentation

This is the headline, and it is easy to miss because everything currently
*works*. These are opcodes that scripts **actively execute today** and which
the VM answers with `return true`:

| Opcode | Corpus uses | Why it is a no-op |
|---|---|---|
| `fadescreen` / `fadescreenspeed` / `fadescreenswapbuffers` | **128 / 8 / 34** | ⚠️ The fade this opcode opens is **never closed by another opcode** in 106 of 128 uses — source closes it from `CB2_ReturnToFieldContinueScriptPlayMapMusic`, engine plumbing this project lacks. A faithful-looking fade here would leave the screen **black permanently**. The existing comment explicitly asks for this to be paired with the **screen transition**, not with a matching opcode — which is exactly what a native handler is. |
| `dofieldeffect` / `waitfieldeffect` | — | No field-effect layer exists. This is the Pokécentre heal animation. |
| `showmonpic` / `hidemonpic` | — | No field picture layer. Oak holds up your starter and nothing appears. |
| `opendoor` / `closedoor` / `waitdooranim` | — | Doors do not animate. |
| `createvobject` / `turnvobject` | **267** | **Halts the VM outright** — virtual cutscene sprites. |
| `showmoneybox` and family (×3 + coins ×3) | **32** | No money/coins box exists. |
| `DoInGameTradeScene` | — | G3b, deferred — the trade completes silently. |

**Right now a field script cannot fade the screen.** That is a primitive, not
a flourish, and there is no way for a script to reach one.

Forward, the same mechanism serves: **M28**'s evolution scene (which
`docs/m28_recon.md` already places on M27H's battle-return path), **M27E**'s
field-move effects, camera work, screen shake, and **G3b**'s deferred trade
animation.

⚠️ **Audio is NOT in this list and `native` does not fix it.** `playse` /
`playbgm` / `playfanfare` / `waitfanfare` / `playmoncry` / `waitmoncry` /
`waitse` / `savebgm` / `fadedefaultbgm` are no-ops because **audio does not
exist anywhere in this project** — a project-wide absence already tracked
against **M36-S**, not a script-engine gap. `native` gives audio a clean home
when it arrives; it does not create one.

### 3.2 Cost — four coordinated edits per async feature becomes one

Any script-driven thing that owns the screen currently costs:

1. a new `Pause.WAIT_*` enum member in `script_vm.gd`
2. an interception branch before `FieldSpecials.run` in the `special` case
3. an `answer_*()` method on the VM (because `resume()` deliberately refuses
   result-carrying pauses — see its own guard, which is good design and stays)
4. a new `match` arm in `_drive_script` plus a callback on the driver

`ChangePokemonNickname`, `ChoosePartyMon` and `CreateInGameTradePokemon` each
paid it in full. `Pause` currently has **12 members, 8 of them waits**, and
every one of the async ones bought exactly one feature.

`Pause.WAIT_NATIVE` is the last one that ever needs adding.

### 3.3 Risk — two of everything, currently maintained by hand

**Two input drivers.** `run_new_game()` (Oak's speech) bypasses the VM
entirely, so its yes/no needed a **second** input driver added to `_process`,
gated on `_vm == null`, sitting above the message-box gate with documented
load-bearing ordering. That gap shipped as a real defect — the gender question
**could not be answered from the keyboard** — and it passed its own test
because the driver called `confirm()` directly rather than pressing keys. The
lesson is already recorded in this project's own words:

> **A driver that reaches past the input layer cannot test the input layer.**

Every future `await`-based cutscene reproduces that split. **G7 deletes it.**

**One god object.** `scenes/overworld/overworld.gd` is **3,155 lines**, of
which roughly 700 are the script↔scene bridge. Every new pause branch lands
there. **G4 extracts it**, and doing so *before* G5 is what keeps the new
branch out of it.

### 3.4 Authoring — the actual product goal

This project is Kanto geometry with an **original story**. The 17,137 imported
labels supply the geometry and systems; the story is all new scripts. Writing
one today means GBA assembler syntax plus `python3 gen_map_scripts.py`, with
no type checking, no autocomplete, and an unimplemented opcode surfacing as a
runtime `UNKNOWN_OP` mid-conversation rather than an error at author time.

⚠️ This project has already paid twice for the untyped-constant failure mode
that a typed front-end removes: `YES`/`NO` resolving to 0 and **inverting
every yes/no branch in the region**, and `PARTY_SIZE` making every "nothing
chosen" check take the Decline branch. Both were silent, both were wrong at
every call site simultaneously, and both were found by live-driving rather
than by any test.

---

## 4. The two mechanisms

### 4.1 `native` — the escape hatch

⚠️ **This is a PORT, not an invention.** Source's `ScriptContext` carries a
`nativePtr` and a `SCRIPT_MODE_NATIVE` alongside `SCRIPT_MODE_BYTECODE`
(`include/script.h`, `src/script.c:70`), and `ScrCmd_waitmovement` is built on
it verbatim:

```c
bool8 ScrCmd_waitmovement(struct ScriptContext *ctx) {
    u16 localId = VarGet(ScriptReadHalfword(ctx));
    if (localId != LOCALID_NONE) sMovingNpcId = localId;
    SetupNativeScript(ctx, WaitForMovementFinish);   // ← native predicate
    return TRUE;
}
```

Adding it makes this project **more** faithful to source, not less. Its
script-visible cousin `callnative` already exists in the corpus (62 uses) and
is currently routed to the `special` handler; it becomes this opcode's alias.

**In `ScriptVM`:**

```gdscript
## `native "HandlerName"[, arg...]` — hand control to registered Godot code.
##
## The direct port of SCRIPT_MODE_NATIVE / SetupNativeScript (script.c:70).
## The VM records WHO it is waiting on and stops; the driver looks the name up,
## runs it, and reports back. The VM never learns what a tween is — the same
## split every other pause already uses.
"native":
    if args.is_empty():
        pause_reason = Pause.UNKNOWN_OP
        diagnostic = "native needs a handler name"
        return false
    pending_native = str(args[0])
    pending_native_args = args.slice(1)
    pause_reason = Pause.WAIT_NATIVE
    return false

## ⚠️ NOT reachable via resume() — WAIT_NATIVE carries a RESULT, the same as
## WAIT_BATTLE / WAIT_NAMING / WAIT_PARTY_CHOICE. resume()'s existing guard
## must be extended to refuse it, or a handler's answer is silently dropped
## and the script reads as having just carried on.
func resume_after_native(result: Variant = null) -> void:
    if pause_reason != Pause.WAIT_NATIVE:
        return
    if result != null and _flags != null:
        _flags.var_set("VAR_RESULT", int(result))
    pending_native = ""
    pending_native_args = []
    pause_reason = Pause.NONE
```

⚠️ `Pause.WAIT_NATIVE` is **appended**, never slotted beside the other
`WAIT_*` values, so no existing ordinal shifts — the same discipline
`WAIT_BATTLE` used and for the same reason.

**In the driver — this is the only `await` in the whole design:**

```gdscript
ScriptVM.Pause.WAIT_NATIVE:
    if not _native_running:
        _native_running = true
        _run_native(_vm.pending_native, _vm.pending_native_args)

func _run_native(name: String, args: Array) -> void:
    var handler := NativeEventRegistry.get_handler(name)
    if handler.is_null():
        # Halts and NAMES itself, the same discipline an unknown `special`
        # already uses — a silent skip would make coverage figures lie.
        _native_running = false
        _vm.pause_reason = ScriptVM.Pause.UNKNOWN_OP
        _vm.diagnostic = "native handler '%s' is not registered" % name
        return
    var result = await handler.call(self, args)
    _native_running = false
    # ⚠️ Guarded: _abandon_script() may have run while the handler awaited.
    if _vm != null:
        _vm.resume_after_native(result)
```

**A handler:**

```gdscript
NativeEventRegistry.register("OakBallRelease", func(driver, _args):
    var fx := preload("res://scenes/fx/ball_release.tscn").instantiate()
    driver.add_child(fx)
    await fx.play(driver.entity_for("LOCALID_OAK").global_position)
    fx.queue_free()
)
```

**Every property the VM was built for survives**: `pause_reason` and
`pending_native` are plain readable properties, so `describe()` reports which
handler is running; a test can freeze on `WAIT_NATIVE` and assert from
outside; cancellation stays one line (`_vm = null`); and the pause is
serialisable as `{label, pc, native_name}` rather than a coroutine frame that
cannot be read, written or reconstructed.

### 4.2 `EventScript` — the authoring front-end

A builder returning `Array[Dictionary]` — **the exact shape
`gen_map_scripts.py` already emits.**

Today:

```
PalletTown_ProfessorOaksLab_EventScript_BulbasaurBall::
	lock
	faceplayer
	setvar PLAYER_STARTER_NUM, 0
	setvar PLAYER_STARTER_SPECIES, SPECIES_BULBASAUR
	msgbox PalletTown_ProfessorOaksLab_Text_ThoseArePokeBalls
	release
	end
```
…then `python3 scripts/gen_map_scripts.py`.

After:

```gdscript
static func bulbasaur_ball() -> Array:
    return EventScript.new() \
        .lock() \
        .face_player() \
        .set_var("PLAYER_STARTER_NUM", 0) \
        .set_var("PLAYER_STARTER_SPECIES", Species.BULBASAUR) \
        .message("Text_ThoseArePokeBalls") \
        .release() \
        .end()
```
…and no regenerate step.

**Both produce byte-identical op arrays.** Registration at boot:

```gdscript
_script_source.ops_by_label.merge(EventRegistry.native_scripts())
```

Everything downstream is unchanged: same VM, same driver, same tests, same
`describe()`, same save format. A GDScript event may `goto` an imported label
and an imported script may `call` a GDScript one — they are the same op list
in the same table.

⚠️ **`msgbox` stays expanded at COMPILE time**, not in the builder and not in
the VM (`Std_MsgboxNPC` = `lock`/`faceplayer`/`message`/`waitmessage`/
`waitbuttonpress`/`release`/`return`). The builder's `.message()` emits the
same primitive chain. This is an existing, correct decision and the builder
must not reintroduce `callstd`.

---

## 5. Phases

Each is independently valuable and independently shippable. **G4–G7 are the
architecture work; G8–G9 are ordinary content work that becomes much cheaper
once it exists.**

---

### G4 — Extract `ScriptDriver`

**Goal.** Lift the script↔scene bridge out of `overworld.gd` with **zero
behaviour change**, so every later phase has somewhere sane to land.

**Files.**
- new `scripts/overworld/script_driver.gd` — `class_name ScriptDriver extends Node`
- `scenes/overworld/overworld.gd` — becomes a thin caller
- **moves**: `_drive_script`, `_start_pending_movements`,
  `_apply_pending_object_ops`, `_resolve_movement_entity`, `_finish_script`,
  `_expanded_pages`, `run_script`, `_setup_scripting`, `_on_script_name_chosen`,
  plus ownership of `MessageBox` / `YesNoBox` / `NamingScreen` /
  `FieldPartyScreen`
- **stays**: `_start_player_movement`, `_do_warp`, `_do_scripted_warp`,
  `_run_arrival_map_scripts`, `check_on_frame_map_script` — all mutate player
  or chunk state

**Dependencies.** None.

**Tests.** ⚠️ **AMENDED 2026-08-07, DURING G4 — the criterion is that no
BEHAVIOURAL assertion changes.** It originally read "zero edits to any test
file", which turned out to be unachievable for one reason worth recording:
`m27l_save_test` H.04–H.06 assert on the **source text** of `overworld.gd`
(`src.find("ScriptVM.Pause.WAIT_YES_NO")`), and a source-grep assertion cannot
survive code movement by construction. The three were **repointed** to span
`overworld.gd` + `script_driver.gd`, keeping the property they check — two
input drivers, the free-standing one first — genuinely tested. Rob's call.

Worth knowing *what* those three assert: the existence of the duplicate
yes/no driver, i.e. exactly the thing **G7 deletes**. They encode a temporary
state of the world and should be removed at G7, not repointed again.

Every other suite must stay green with zero edits. Additionally:
- `script_started` / `script_finished` fire with identical payloads
- the `_process` gate ordering is preserved **verbatim** (yes/no → message →
  naming → party → bag → start menu → script), with its load-bearing comments
  moved intact rather than paraphrased
- `check_bake_diff.py` still clean across the corridor

**Done when.** `overworld.gd` is under ~2,500 lines; the full overworld suite
is green.

**✅ DONE 2026-08-07.** `overworld.gd` **3,178 → 2,911** lines;
`scripts/overworld/script_driver.gd` is 379. **22/22 suites, 1,722
assertions, zero engine errors** (`m27h_catching_test` excluded per its own
documented hang).

⚠️ **Two design calls differ from this section as written, both deliberate:**

1. **The UI nodes did NOT move.** The scope said the driver would own
   `MessageBox`/`YesNoBox`/`NamingScreen`/`FieldPartyScreen`. It doesn't:
   `run_new_game`, `_poison_step` and `_on_start_menu_save` all open the same
   message box with **no VM running**, so moving ownership would have meant
   rewriting three unrelated call sites inside a phase whose whole point is
   that nothing changes. They stay on the scene and are borrowed through
   `_ow`. The real boundary that emerged is **execution vs triggering**: the
   driver runs scripts, the scene decides when one starts and owns every
   resource it borrows.
2. **`ScriptDriver` is `RefCounted`, not a `Node`.** Convention (every other
   non-visual system here — `ScriptVM`, `FlagStore`, `Interaction`,
   `MovementRunner` — is RefCounted), and necessity: `m27i_text_buffers_test`
   uses a bare `overworld.tscn` instance that never enters the tree, assigns
   `ow._vm` and calls `ow._expanded_pages()`. A Node built in
   `_setup_scripting` would not exist on that path; a Node built at
   declaration would leak. RefCounted at declaration satisfies both.

**Five forwarders stay on the scene** — `run_script`, `_drive_script`,
`_finish_script`, `_abandon_script`, `_expanded_pages`, plus `_vm` as a
get/set property. Not cosmetic: tests assign `ow._vm` directly and assert
`ow.has_method("_abandon_script")`, and every script TRIGGER is a scene
concern that legitimately calls `run_script`.

**Do NOT yet.** Change any behaviour. Add `native`. Touch `ScriptVM`. Rename
any `Pause` member. Merge the two input drivers (that is G7).

---

### G5 — The `native` opcode

**Goal.** One generic async escape hatch; `await` confined to one function.

**Files.**
- new `scripts/overworld/native_events.gd` — `NativeEventRegistry`
  (`register(name, Callable)`, `get_handler(name)`, `has(name)`, `names()`)
- `scripts/overworld/script_vm.gd` — `Pause.WAIT_NATIVE` (**appended**),
  `pending_native`, `pending_native_args`, the `"native"` case,
  `resume_after_native()`, `resume()`'s guard extended, `describe()` reports
  the handler name
- `scripts/overworld/script_driver.gd` — the `WAIT_NATIVE` branch + `_run_native`
- `scripts/gen_map_scripts.py` — accept `native` as a known command
- `docs/field_script_authoring.md` — document the new command and its rule

**Dependencies.** G4.

**Tests.** New section in `m27f_script_vm_test.gd`:
- `native` raises `WAIT_NATIVE` and records the handler name in `describe()`
- an unregistered handler → `UNKNOWN_OP` with a **naming** diagnostic, not a crash
- `resume_after_native(value)` writes `VAR_RESULT` and a following
  `goto_if_eq` branches correctly
- ⚠️ `resume()` alone does **not** clear `WAIT_NATIVE`
- abandoning the script mid-handler (`_vm = null`) does not error when the
  handler finishes
- a handler yielding across frames leaves `pause_reason == WAIT_NATIVE`
  observable throughout

**Done when.** One real handler ships end to end.

**✅ DONE 2026-08-07.** `Pause.WAIT_NATIVE` + the `native` opcode +
`resume_after_native` in `script_vm.gd`; `NativeEventRegistry` (the table);
`FieldNativeEvents` (this project's own handlers — `FadeToBlack`,
`FadeFromBlack`, `Wait`); the driver's `WAIT_NATIVE` branch and `_run_native`,
which holds the one and only `await` in the whole script pipeline.
**22/22 suites; `m27f_script_vm_test` 231 → 253 assertions** (new section Q).

Live-driven in the real scene, not only unit-tested: a script of three chained
native beats (fade out → wait → fade in) was observed **mid-run** sitting on
`WAIT_NATIVE` with `pending_native == "FadeToBlack"`, then completing and
running the opcode after them. That mid-run observability is the property the
whole design exists for, and an `await`-based command could not have it.

⚠️ **THE `fadescreen` OPCODE IS STILL A NO-OP, AND THAT IS DELIBERATE.** This
section originally named rewiring it as the acceptance target. It should not
have: `script_vm.gd`'s own comment records that in **106 of 128 corpus uses the
fade is never closed by another opcode** — source closes it from
`CB2_ReturnToFieldContinueScriptPlayMapMusic`, plumbing this project does not
have — so making the opcode fade for real would leave the screen black
permanently. Pairing it with the screen TRANSITION is a per-call-site analysis
and its own piece of work. What G5 delivers is the CAPABILITY: a fade is now
reachable by name (`native "FadeToBlack"`) from an authored script, which is
what G6 will use and what nothing could do before.

⚠️ **`NativeEventRegistry` is an INSTANCE owned by `ScriptDriver`, not static.**
The first cut was static, matching `FieldSpecials`. That is wrong for a table of
**Callables**: a `static var` Dictionary of lambdas outlives the script that
created them, and Godot aborts at process exit with heap corruption ("corrupted
size vs. prev_size while consolidating", SIGABRT/134). It took down four suites
the moment a real overworld started registering handlers. Per-driver ownership
is the correct lifetime anyway — a handler reaches the scene through
`driver.scene()`.

**Do NOT yet.** Migrate `run_new_game`. Port the special tail. Add the builder.
Rewire `fadescreen` (see above).

---

### G6 — `EventScript`, the GDScript authoring front-end

**Goal.** Author original content in GDScript, executed by the same VM.

**Files.**
- new `scripts/overworld/event_script.gd` — the builder
- new `scripts/overworld/movement_script.gd` — a movement-action builder
  (`Move.walk_down(2).face_west()`), covering `MovementRunner`'s ~79 actions
- new `scripts/overworld/event_registry.gd` — collects native scripts, merged
  into `ScriptSource.ops_by_label` at boot
- new `scripts/events/` — where authored events live
- `script_driver.gd::_setup_scripting` — the merge + the collision assertion

**Dependencies.** G5, so `.native()` exists in the builder from day one.

**Tests.**
- ⚠️ **Round trip** — a builder-produced op array is structurally identical to
  the compiler's output for the same script, compared against a **real
  `map_scripts.json` entry**. This is the single highest-value assertion in
  the phase: it is what proves the two front-ends cannot drift.
- **Boot-time assertion**: every op the builder can emit is in `ScriptVM`'s
  `match`. Same discipline as `gen_trainer_data.py`'s `normalize()`-collision
  guard — kill the bug class, not the bug.
- a label defined in **both** JSON and native **fails loudly**, never shadows
- an authored script runs end to end through the unmodified driver

**Done when.** One real authored cutscene — **original story content, not a
port** — runs with a `native` beat in it, and `describe()` reports it
identically to an imported script.

**✅ DONE 2026-08-07.** `EventScript` (the builder), `Move` (movement actions),
`EventRegistry` (merge + collision rule, ops AND text), `AuthoredEvents` /
`PalletTownEvents` (the first authored content), merged in `ScriptDriver.setup`.
**22/22 suites; `m27f_script_vm_test` 253 → 273** (new section R).

**R.01 is the assertion that matters**: the builder reproduces
`PalletTown_EventScript_FatMan` — a REAL entry from the real
`map_scripts.json` — byte-identically, proving `msgbox_npc()` expands exactly
as `gen_map_scripts.py`'s `STD_EXPANSIONS` does. Compared against the live
corpus rather than a fixture, so it is a proof and not a restatement.

Live-driven: the authored script was found in the live corpus **beside**
`PalletTown_EventScript_FatMan`, ran through the unmodified driver, opened the
box on authored text, hit its `native` beat, and completed with its flag and
checkpoint set.

⚠️ **Authored TEXT is registered too, not put in `map_texts.json`.** That file
is generated from `field_script_source/` and a hand edit is discarded on the
next regenerate — `docs/field_script_authoring.md` records that as a standing
rule. Registering pages alongside the ops is what lets authored content change
a line with no Python step, which is half the point of the front-end.

⚠️ **A collision `push_warning`s rather than `push_error`s**, and the imported
script always wins. Not a softening: `run_overworld_tests.sh` fails any run
containing an ERROR line, so pushing an error would make the collision test
unrunnable. `SaveManager.read` records the identical call for the identical
reason. Loudness is preserved by the warning plus `rejected()`.

⚠️ **Two guard probes were wrong on the first cut, and the guards caught
them** — worth recording because both look like passing tests when written
naively. (1) R.04 drove each builder op with EMPTY args and flagged `warp`,
`special`, `specialvar`, both `trainerbattle_*` and `native` as unimplemented;
they were correctly refusing their own arity. The guard now keys on the
DIAGNOSTIC — only the generic fallthrough says "outside Stage 1's set". (2)
R.05 expected `step_end` in `MovementRunner`'s action table; it is the
TERMINATOR, special-cased in `_begin`, so it is legitimately absent.

**Not yet reached by a placed entity.** Attaching the authored script means
setting an NPC's `script_label` in a baked map scene — map DATA, and a content
decision rather than a mechanism one. G6 ships the ability to write scripts;
which NPC says what is Rob's call.

**Do NOT yet.** Migrate any imported content. Build a visual editor. Write a
text DSL or a parser — the builder is sufficient.

---

### G7 — Fold in the free coroutines

**Goal.** Exactly one way to be a cutscene; exactly one input driver.

**Files.**
- `overworld.gd::run_new_game` → an `EventScript`-authored script whose visual
  beats are `native` handlers (`OakPortrait`, `OakBallRelease`,
  `OakGenderPick`, `OakFadeOut`)
- `field_poison.gd`'s message → a VM script (source runs it as
  `EventScript_FieldPoison` opening with `lockall`; this project expresses the
  same lock by returning early, which is a second lock mechanism)
- **then delete** the duplicate yes/no input driver in `_process` and the
  `_vm == null` message-box branch

⚠️ **G7 must preserve every divergence `[M27K K-b]` recorded, not quietly
normalise them back to source**: the gender question showing Red and Leaf side
by side (Rob's call, 2026-08-05), the random roster species in the ball
release rather than source's fixed Nidoran♀ (Rob's call), and the
gender-before-name ordering, which is load-bearing because
`PlayerIdentity.name_choices()` keys on it.

**Dependencies.** G4–G6.

**Tests.** ⚠️ **The full new-game sequence must be answerable from real key
presses**, not from direct `confirm()` calls — this is the specific bug being
retired and the test must not repeat the mistake that hid it. Plus: assert
`_process` contains **one** yes/no driver, not two.

**Done when.** `run_new_game` no longer exists as a coroutine, both duplicate
drivers are deleted, and `m27k_newgame_test` passes driving real input.

**✅ MOSTLY DONE 2026-08-07 — one of the two drivers survives, deliberately.**
`NewGameEvents` (Oak's speech, with both confirm/retry loops as real `goto`
branches) and `StartMenuEvents` (saving) are authored scripts; 7 new Oak
`native` handlers; Oak's dialogue moved into the corpus. **22/22 suites;
`m27k_newgame_test` 66 → 67, now driving REAL KEY PRESSES.** Live-driven end
to end: both yes/no prompts answered by real input, all 6 native beats reached,
name and rival committed.

⚠️ **A THIRD CALLER WAS MISSING FROM THIS SCOPE — `_on_start_menu_save`.** It
opened a yes/no outside the VM exactly as `run_new_game` did, so deleting the
free-standing yes/no driver would have left **saving** unanswerable from the
keyboard — the identical bug this phase exists to fix, reintroduced by the
phase fixing it. Found by deleting the driver and asking what else used it.

⚠️ **[CLOSED, same day — see G8/G9's own entry.] THE FREE-STANDING MESSAGE-BOX
DRIVER WAS STILL THERE, with exactly one user: `_poison_step`.** Not an oversight — a real limitation. The poison notice
builds its pages at RUNTIME (one per Pokémon that just hit 1 HP, each with that
Pokémon's own name buffered) and `message` names a STATIC label in the text
corpus. There is no opcode for "show these N pages I just computed". The
obvious workaround fails too: **a `native` handler cannot `await` the message
box**, because while the VM sits on `WAIT_NATIVE` the driver is in its
`WAIT_NATIVE` branch and nothing advances the box. Two ways out, both real
design calls that did not belong in this phase:

1. a dynamic-text opcode (`message_buffered`, pages supplied by the caller), or
2. letting the `WAIT_NATIVE` branch also pump the box — one driver location,
   but it lets `native` show dialogue outside the op stream, which erodes
   "the op stream is the whole story".

⚠️ **A SUSPENDED `native` HANDLER CANNOT BE CANCELLED**, and G7 is where that
first bit. `abandon()` drops the VM, but a handler already awaiting keeps a
reference to the scene until the thing it awaits completes — freeing the
overworld mid-handler leaks ("N resources still in use at exit", which the
runner fails on). Two tests now wait for the beat to settle. **The standing
rule this produces: a handler must await something that always finishes.**

**`m27l_save_test` H.04–H.06 are RETIRED**, as G4 predicted. They asserted the
duplicate yes/no driver existed; it does not any more. The coverage that
replaced them is stronger — `m27k_newgame_test` section H drives the whole
speech, both retry loops included, through real key presses.

**Do NOT yet.** Migrate imported scripts — there is nothing to gain. Close the
poison driver without deciding between the two options above.

---

### G8 — Route specials through the registry

⚠️ **RESCOPED per §2.4. This is now PLUMBING, not content — there is no
special-porting work left for the corridor.**

`m27_corridor_opcode_scope.md`'s own conclusion is *"No specials work is
proposed here… that side is done for this scope."* Of 39 reachable names: 17
implemented, 18 permanently-excluded multiplayer, and 4 owned by other
milestones (`GetFrlgPokedexCount` / `SetUnlockedPokedexFlags` /
`EnableNationalPokedex` / `HasAllMons` / `GetProfOaksRatingMessage` → **M33**;
`ChooseMonForMoveTutor` → **M30**; `GetLeadMonFriendship` /
`DaisyMassageServices` → a friendship system nothing owns, already flagged in
`docs/m18_5h_recon.md`; `SaveGame` → every corridor caller is Cable-Club-gated
and `SaveManager` already exists).

**Goal.** Make the *next* special cheap, and give the four blocked ones a
landing site that costs one registration when their milestone arrives.

**Files.** `script_vm.gd` — route `special` / `specialvar` / `callnative`
through `NativeEventRegistry` **after** `FieldSpecials` and **before** the
halt. `field_specials.gd` keeps synchronous specials only.

**Dependencies.** G5.

**Tests.** A registered async special resolves through `WAIT_NATIVE` and
writes `VAR_RESULT`; an unregistered one still halts and names itself.
⚠️ **Keep halt-on-unknown** — the reasoning in `FieldSpecials`' own header
stands, and it is the only honest coverage measure.

**Done when.** The routing exists and one previously-halting special is
served by a handler.

**✅ DONE 2026-08-07.** `special` and `specialvar` route to
`NativeEventRegistry` **after** `FieldSpecials` and **before** the halt.

⚠️ **THE REGISTRY IS INJECTED INTO `ScriptVM`, NOT CONSULTED BY THE DRIVER**,
and the first cut got this wrong. Routing at the driver meant the VM could no
longer tell an unimplemented special from a handled one — only the driver
knew — which quietly breaks the property this whole engine rests on: `step()`
alone says what a script did and why it stopped. `m27f_stage4_test` B.04/B.05
assert exactly that from a bare VM with no driver anywhere, and caught it.

⚠️ **A `specialvar` naming a destination other than `VAR_RESULT` is
deliberately NOT routed.** `resume_after_native` answers into `VAR_RESULT`, so
serving one would write the wrong slot silently — worse than halting. Widening
`resume_after_native` to take a destination is a one-line change if a real call
site ever needs it.

**Do NOT.** Port M33/M30/friendship specials — they are blocked on systems,
not on this. Attempt anything corpus-wide. Implement anything reached only
through a Cable Club / Union Room / Colosseum entry point.

---

### G9 — The two persistence gaps

⚠️ **RESCOPED per §2.4. The opcode list that was here was corpus-wide and
mostly not corridor-reachable.** The real corridor opcode work is
`m27_corridor_opcode_scope.md`'s own five items, which that document owns and
sequences; see §8 decision 6 for how the two build orders interleave.

**Two of its five items land here rather than there, because both are
save-shape questions this investigation surfaced independently:**

**`copyobjectxytoperm`** (1 use, `PalletTown_EventScript_SignLady`). That
document recommends shipping it as a documented no-op and opening a general
"persist moved/hidden NPC state" item only if M27L's save shape is revisited.
⚠️ **This investigation found the same gap from the other direction and it is
broader than one opcode:** `setobjectxyperm` / `setobjectmovementtype` /
`turnobject` are **already implemented and already mutate live nodes** that
`_teardown_and_load` frees. So the sign lady is not the only case, and the
no-op recommendation is right for `copyobjectxytoperm` specifically while
leaving the general defect open. Source keeps a mutable
`objectEventTemplates` copy in the save block for exactly this.

**`_vm.subject` holds a node reference across a scripted warp.** Store the
`local_id` beside it and re-resolve on use, matching what
`_resolve_movement_entity` already does for every other target.

**Goal.** Close both, or explicitly defer both with the general shape
recorded — not one-off mechanisms for one NPC.

**Also noted, not a bug:** `ScriptVM.removed_objects` and
`pending_object_ops`'s `remove` are two records of one event. The VM's own
comment acknowledges this ("the second, functionally-consumed record of the
same event, not a replacement"). Worth collapsing if G9 touches that code.

**Dependencies.** G4. Independent of G5/G6.

**Tests.** A **warp round-trip test** asserting a script-moved NPC stays
moved (or, if deferred, asserting it explicitly does not, so the gap is
tested rather than merely described).

**Done when.** Both gaps are closed or explicitly deferred with a recorded
decision, and the corridor suite is green.

**✅ DONE 2026-08-07 — both closed.**

**`_vm.subject`**: `ScriptVM` now captures `subject_local_id` at `start()`, and
`resolve_movement_entity` re-resolves by name when the node is gone. Every
*other* movement target already resolved by `local_id` on each use; this one
uniquely held a reference across a teardown.

**Object-event persistence**: new `ObjectEventState`, keyed by **map +
`local_id`** — the node is exactly the thing that dies, so a per-node key
could not survive the teardown it exists to survive. `setobjectxyperm` /
`setobjectmovementtype` / `turnobject` record; `MapManager._install_chunk`
re-applies on load; `SaveManager` persists it as `object_events` (absent from
older saves, read as "no overrides"). ⚠️ Applied at LOAD, never baked into the
`.tscn` — the baked scene is a reproducible artifact that `check_bake_diff`
depends on, and must keep describing the map as authored. Same shape as
`entity_visible` reading a flag rather than the scene knowing it is hidden.
⚠️ Visibility is deliberately NOT stored here: `addobject`/`removeobject`
toggle a FLAG, which is already saved.

**Plus, closing G7's own leftover:** `_poison_step` is now
`FieldPoisonEvents`, and **the last free-standing message-box driver is
deleted**. Rob's call on the shape: the script LOOPS — a `native` buffers the
next survivor's name and answers 1, or answers 0 when drained; `message` shows
the one static corpus line; `goto` comes back. No new opcode, no driver change,
and every page stays inside the op stream so `describe()` still tells the truth
about a running notice. ⚠️ The first draft of that corpus line said
"{STR_VAR_1} fainted…" — `FieldPoison.MESSAGE` is about *surviving* the
poisoning, a different event entirely, and the mon is still standing.

**Superseded content, kept so it is not re-derived:** the original G9 opcode
list (`createvobject`/`turnvobject`, `setobjectxy`, `getplayerxy`,
`setwildbattle`, warp variants, `multichoicedefault`/`dynmultipush`) was
measured corpus-wide. **None of it is corridor-reachable.** It becomes real
only when maps outside the 32 are baked, and at that point the right move is
to re-run the audit, not to work from this list.

---

---

## 6. Explicitly NOT in this block

| | Where it goes / why |
|---|---|
| **`setmetatile`** | ⚠️ **Owned by `m27_corridor_opcode_scope.md`, not this block.** ⚠️ **And it is 2 corridor uses, one script — NOT the 1,406 this document originally cited, which was corpus-wide.** The opcode is a two-line queue append; the work is a new `MapManager.set_metatile(gcell, id)` primitive routed the same layer-type way `[M27C]`'s border skirt already routes. Independent of G4–G9; can run in parallel. **Persist nothing** — source re-derives via `ON_LOAD` on every map entry, so it needs no new save data. |
| **`multichoicegrid`** | ⚠️ **Owned by `m27_corridor_opcode_scope.md`.** 1 corridor use (Viridian School blackboard), but it is the **first general list-choice primitive** rather than a one-off screen, so it is worth building properly. Note it is a natural `Pause`-shaped consumer (mirroring `answer_party_choice`) **or** a `native` handler — worth deciding once G5 exists rather than before. |
| **`pokemart` family** | ⚠️ **M27I**, and `m27_corridor_opcode_scope.md` Tier 3 is its scope of record — 2 real corridor clerks, comparable in size to the Bag or Party screen builds. Needs a stock-list extractor, a `Pause.WAIT_MART`, a Buy screen and a Sell decision. Not this block. |
| **`fadeoutbgm` / `copyobjectxytoperm`** | `m27_corridor_opcode_scope.md` Tiers 0–1. `fadeoutbgm` joins the existing audio no-op group (M36-S); `copyobjectxytoperm`'s save question is G9's, per §2.4. |
| **Any `EventRunner` / `await`-chained command system** | Rejected. See `m27g_architecture_recon.md` Parts 3–4. |
| **`EventCommand` as a class hierarchy or `.tres` resources** | Rejected. A `Dictionary` is the right representation; `.tres` `SubResource` id churn would make diffs unreviewable — this project already carries a scar from exactly that (`check_bake_diff.py` exists because of it). |
| **`EventContext` god-object** | Rejected. Injection is what makes `ScriptVM` testable without a scene tree. |
| **Split `FlagManager` / `VariableManager`** | Rejected. `FlagStore` is both, matching source's single save block, and every consumer already takes one object. |
| **Any new autoload** | Rejected. This project has exactly one (`PokemonRegistry`) and uses class-level statics deliberately. |
| **A visual event editor** | Not now. `map_overlay_editor` cost a real session; there is no evidence a script editor beats GDScript with autocomplete. Revisit only if authoring volume proves it. |
| **Byte-level FireRed opcode fidelity** | Permanent exclusion. No ROM will ever be loaded; the importer reads assembly text. |
| **`ramScript`** | ⚠️ **Permanent exclusion.** Executable code inside a save file. `overworld_scope.md` already refuses it and that refusal stands. |
| **Multiple concurrent script contexts** | Rejected. Source has one visible context; one `_vm` slot is faithful, not a simplification. |
| **Contest / Frontier / Match Call / berry trees / braille / link** | M35, or already-recorded permanent exclusions. |
| **Audio** | **M36-S**, project-wide. |

---

## 7. The two mechanical guards

"Two authoring paths, one runtime" only holds if these are enforced by code,
not by discipline:

1. **Every builder method emits an op `ScriptVM`'s `match` implements** —
   boot-time assertion (G6). Without it you can write a GDScript event that
   compiles cleanly and halts at runtime, which is the *exact* failure mode
   the builder exists to remove.
2. **A label defined in both JSON and native fails loudly, never shadows** —
   boot-time assertion (G6).

And one rule that is cultural rather than mechanical, and matters more than
either:

> ⚠️ **`native` is for presentation and engine capability — never for control
> flow, never for state.**

The moment a handler starts setting flags and branching, the op stream stops
being the whole story, `describe()` stops telling the truth, save state stops
being re-derivable, and the coroutine architecture this block declined has
been rebuilt inside the escape hatch. Enforce by review; consider a lint over
the registry if it starts to slip.

**Corollary for save/load, which needs no new machinery:** events are
**re-entrant from world state, never resumed from execution state.** A
cutscene must leave the world in a state from which it can be correctly
re-derived on the next load — which is precisely what the `VAR_MAP_SCENE_*`
idiom already does. Source takes the same position: `gSaveBlock` has no
`scriptPtr` field. Saving is itself gated behind `_vm == null`, so the
question cannot arise in play. **Worth adding to `field_script_authoring.md`
as an authoring convention**: a long cutscene should advance its progress var
at each act boundary, and the builder can offer `.checkpoint(var, n)` as sugar
for `setvar`.

---

## 8. Decisions for Rob

| # | Question | Recommendation |
|---|---|---|
| 1 | **Build order — G4 (extract) first, or straight to G5 (`native`)?** | **G4 first.** It is a pure refactor with existing suites as acceptance, and skipping it means G5's branch lands in a 3,155-line file rather than out of it. |
| 2 | **If only one of G5/G6 gets built, which?** | **G5 (`native`).** It is cheaper (~40 lines vs. a builder + movement builder + registry + round-trip test), it is a port rather than an invention, and it removes an actual capability ceiling. G6 is the nicer thing to *use*; G5 is the thing that unblocks. |
| 3 | **G5's acceptance target — `fadescreen`, or something else?** | **`fadescreen`.** 128 uses, its own comment asks for exactly this pairing, and it is the block's first player-visible win. |
| 4 | **Does `setmetatile` + `ON_LOAD` become an M27C follow-on, or stay in G?** | **M27C follow-on.** The opcode is trivial; the work is all `MapManager`. It can run in parallel with G4–G7. |
| 5 | **Apply §9's doc corrections now, or at the next housekeeping pass?** | **Next housekeeping pass**, except the §30 block-name note, which will misdirect the very next session that reads it. |
| 6 | ⚠️ **How do this block and `m27_corridor_opcode_scope.md` interleave?** They are two build orders written the same day for overlapping ground (§2.4). | **Architecture first, content second — with one exception.** G4 (extract) then G5 (`native`) unblock the presentation category that the corridor audit is structurally blind to, and make `multichoicegrid` and the `pokemart` pause cheaper to build. The exception is `setmetatile`, which touches `MapManager` rather than the script engine and can run in parallel at any time. Concretely: **G4 → G5 → {corridor Tiers 0–1, `setmetatile`} → G6 → G7 → `multichoicegrid` → G8/G9 → `pokemart` (M27I)**. |
| 7 | ⚠️ **Is `multichoicegrid` a `Pause` or a `native` handler?** | **Defer until G5 exists**, then decide from the real code. It carries a result, so it fits the `WAIT_PARTY_CHOICE` shape — but it is also exactly the kind of thing `native` exists to absorb, and building it as the *last* bespoke pause or the *first* absorbed one is a genuine fork worth seeing concretely rather than on paper. |

---

## 9. Corrections needed in existing documents

⚠️ **Flagged, not applied** — per the standing rule, and because CLAUDE.md and
`overworld_scope.md` carry their own editing conventions.

1. **`docs/overworld_scope.md` §30** — the M27F/M27G row descriptions no
   longer match what shipped (§2.3). M27F built the field script engine;
   M27G is doing specials and now the rest of the engine.
2. **`docs/overworld_scope.md` §30, M27F row** — remove or footnote
   "Dialogue Manager wiring". It never happened, deliberately, and the reasons
   are well recorded at `text_typer.gd`'s vendoring site.
3. **`CLAUDE.md`, Tech stack, `addons/dialogue_manager` worked example** —
   still describes the plugin as an approved scope-bounded dependency without
   recording that it went unused (plugin disabled, zero `.dialogue` files, one
   vendored file with a documented refusal to integrate). The *process* story
   it tells is still valid and worth keeping; the *outcome* needs a sentence.
4. **`CLAUDE.md`, M27 roadmap row** — the M27G "a few hundred distinct
   functions" estimate is stale in **both** directions: 569 corpus-wide, ~34
   actually reachable.
5. **`docs/field_script_authoring.md`** — will need the `native` command
   (G5) and the checkpoint convention (§7) once those land. Its "roughly 90 of
   the reference's 237 field-script commands" figure is also stale: **124 of
   231**, covering 92.3% of uses.
6. **One-line pointers to this document** from `overworld_scope.md` §30's
   M27G row and from `docs/m27g_recon.md`'s build-order section, so a future
   session finds G4–G9 from either entry point.
7. ⚠️ **`docs/m27_corridor_opcode_scope.md` and this document need mutual
   cross-references** — they were written the same day, for overlapping
   ground, without either knowing about the other. This document now points
   at it (header, §2.4, §6, §8 decision 6); **that document has no pointer
   back**, so a session entering from it would find the content work and miss
   the capability work entirely. One line in its "Proposed build order"
   section closes the loop. ⚠️ It is also **untracked in git** — worth
   committing alongside these two.

---

## 10. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **`native` becomes the default and scripts hollow out** | **High** | §7's rule, enforced by review. This is the way this block fails. |
| **`overworld.gd` keeps growing** | **High — already realised** | G4, first. |
| **Two front-ends drift** | Medium | G6's boot assertion + round-trip test. |
| **Label collisions shadow silently** | Medium | G6's fail-loudly merge. |
| **A `native` handler `await`s on a freed node** | Medium | `_run_native`'s `_vm != null` guard (already in §4.1); `is_instance_valid` in handlers. Containing `await` to one function is what makes this one place to get right. |
| **G8 sized off 569 rather than ~34** | Medium | §2.2, stated at the phase. |
| **Script-driven NPC repositioning silently lost** | Medium | G9. |
| **Boot-time JSON parse cost grows** | Low | Measure first. If it ever matters the fix is a binary `.res` dump — a build-step change, not a format change. |

---

## 11. What stays FireRed-compatible, and what deliberately does not

**Stays compatible:** the command vocabulary and names; flag/var semantics
(unset flag false, unset var 0, `VAR_RESULT` conventions, `VAR_0x8000-9`
scratch, the derived `DEFEATED_*` flag); `applymovement` asynchrony with
`waitmovement` blocking; the five `trainerbattle_*` variants' outcome routing
including the two *different* continuation shapes; map script types and their
order; compile-time `msgbox`/`callstd` expansion; one-script-at-a-time; text
control codes; `local_id` addressing; the interaction dispatch order including
the counter hop.

**Deliberately differs:** name-keyed flags/vars rather than numeric ids; a
JSON IR rather than bytecode; registered `native` handlers rather than a
fixed `gSpecials[]` table; no `ramScript`; no 20-deep stack limit;
halt-and-name on unknown opcode rather than undefined behaviour (**an
improvement over source**); three save slots; authored dialogue overrides and
the nurse auto-confirm (content divergence is the point of an original
story); GDScript as a first-class authoring language; battles as an overlay
rather than a scene swap.
