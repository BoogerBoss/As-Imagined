# M23 Recon

Foundation doc for M23 (the UI/Simulator-layer milestone), matching the role
`m21_recon.md`/`m22_recon.md` played for their own milestones — one
persistent, session-appended document, not re-derived per sub-phase.

---

## M23.0a — Async battle-loop mechanism, Step 0 design + no-UI proof scene

**COMPLETE** — 2026-07-16.

### Background / why this session exists

Every existing battle flow (136 pre-existing test files) drives
`battle_manager.gd` synchronously — `_chosen_moves`/`_chosen_switch_slots`/
`_chosen_items` arrays are fully populated before `_phase_action_execution`
starts, and no pause/resume mechanism existed anywhere in the engine before
this session. A real UI needs the battle loop to PAUSE mid-phase and wait
for a human click, then resume once an action is externally queued. Per this
project's own established pattern (M22's Potion-before-the-rest, the
turn-order-splice trio's item-8-before-11-13), this — the single riskiest,
most architecturally novel piece of M23 — was proven in isolation, first,
before any UI or team-builder work gets built on top of it.

### Step 0 findings

**1. Where choice-arrays are populated today.** Read `_phase_move_selection`
(then at `battle_manager.gd:981`) and `_phase_switch_prompt` (then at
`:6711`) in full. `_phase_move_selection`'s per-combatant loop did an
UNCONDITIONAL reset of `_chosen_switch_slots[i]`/`_chosen_targets[i]`/
`_chosen_items[i]`/`_chosen_item_targets[i]` at the top of every iteration,
on every call — the exact mechanism that would have wiped and re-rolled an
already-decided combatant's choice (including AI RNG rolls) had the pause
mechanism been built as a naive "just call this function again" retrofit.
`_phase_switch_prompt` had NO per-combatant "resolved" tracking at all,
iterating all fainted combatants once per call and unconditionally
transitioning to `BATTLE_END_CHECK` at the end.

`_get_replacement_slot` (faint-replacement's own resolution chain: test-queue
→ `_trainer_ais[side] != null` AI → `_parties[side]
.get_first_non_fainted_not_active()` auto-select) is structurally IDENTICAL
in shape to `_phase_move_selection`'s own queue→AI→auto-select chain — the
same general "human-controlled + wait" pattern generalizes to faint
replacement too, confirmed by inspection before design.

Four other call sites reach `_get_replacement_slot`/`_get_baton_pass_slot`
directly, all **mid-move-execution self-switch contexts** unrelated to
either pause point in scope for this session: Teleport/Chilly Reception
(`:3040`), Hit Escape (`:3654`), Parting Shot (`:5505`), and Baton Pass
(`:2936`). These are attacker-initiated voluntary switches happening inside
an already-executing move, not a distinct "wait for a decision" phase the
way move-selection or faint-replacement are — explicitly **out of scope**
for M23.0a (the task scoped Step 0 to `_phase_move_selection` and "whatever
the real faint-replacement/switch-prompt phase is called") and flagged here
as a known follow-up gap: a human-controlled side using one of these 4 moves
will still auto-resolve the switch synchronously (queue → AI → auto-select,
no pause) until a future M23 sub-phase extends the mechanism to them.

**2. State representation.** New per-SIDE `var _human_controlled:
Array[bool] = [false, false]`, mirroring `_trainer_ais`'s own per-side shape
exactly. Checked via a new `elif _human_controlled[side]:` branch inserted
between the existing `_trainer_ais[side] != null` (AI) branch and the final
`else:` auto-select fallback in `_phase_move_selection`'s per-combatant
if/elif chain. Coexists cleanly with zero collision: the new branch is only
ever reached once the test-queue is empty AND `_trainer_ais[side] == null`
already holds, so `_trainer_ais[side] == null`'s existing "fall through to
auto-select" meaning is completely undisturbed for any side that never calls
the new `set_human_controlled(side, true)` API — which is every one of the
136 pre-existing tests, confirmed via a full grep showing zero references to
the new field/method anywhere outside `battle_manager.gd` itself before this
session added them.

**3. Pause/resume flow and external API.** `advance()`'s PRE-EXISTING stall
detection (`if _phase == phase_before: break`, unchanged by this session)
needed ZERO modification. Both `_phase_move_selection` and
`_phase_switch_prompt` gained a per-combatant "resolved this pass" tracking
array (`_move_choice_resolved`/`_switch_prompt_resolved`) plus an
activation-guard bool (`_move_selection_active`/`_switch_prompt_active`) that
resets the tracking array to all-false only on a genuinely fresh entry into
the phase. Neither function calls `_set_phase` to advance while any tracked
entry remains false — so a human-paused call simply `return`s with the phase
unchanged, and `advance()`'s existing `phase == phase_before` check halts the
whole battle loop with no new code in `advance()` at all.

The external "supply the human's action" API is **not a new method** — it is
the exact same `queue_move`/`queue_move_targeted`/`queue_switch_for`/
`queue_item_for`/`queue_replacement_for` methods every existing test already
calls. A future UI's click-handler calls one of these on the relevant
combatant index, then calls `advance()` again; the very next dispatch of the
paused phase function re-enters the loop, sees the test-queue for that
combatant is no longer empty, and resolves it through the pre-existing queue
branch exactly as if a test had queued it from the start.

**4. Recompute-vs-lock-in, walked through concretely.** Doubles, side 0
human-paused, side 1 already resolved (AI or, as the proof scene
demonstrates, pre-queued) within the SAME `_phase_move_selection` call: the
single per-combatant `for` loop processes all 4 indices in one pass — side
1's slots (2, 3) resolve immediately (AI decision rolled, or queue popped)
and `_move_choice_resolved[2]/[3]` become `true`; side 0's slots (0, 1) hit
the new human-controlled branch and stay unresolved. On a LATER call
(resumed after the human supplies input), the guard `if
_move_choice_resolved[i]: continue` at the very top of the loop — checked
BEFORE any of the reset lines — means indices 2 and 3 are skipped entirely,
never re-touched, never re-rolled. Any AI RNG decision (e.g.
`_roll_switch_decision`) already made for side 1 is preserved exactly as
first rolled. This was directly exercised in the proof scene's Section C
(assertion C.02) using a pre-queued side 1 rather than a real `TrainerAI`
instance, which is behaviorally identical for this purpose (both resolve via
the same queue→AI→auto-select chain, and the "already resolved, don't
re-touch" guard applies uniformly regardless of which branch resolved it).

**5. Faint-replacement generalization — confirmed, no second design needed.**
`_phase_switch_prompt` gained the identical pattern
(`_switch_prompt_active`/`_switch_prompt_resolved`), with the human-pause
check done as a pre-check — `if _human_controlled[side] and
_replacement_queues[ci].is_empty(): continue` — placed BEFORE calling
`_get_replacement_slot`, rather than changing that function's own return
contract. This was a deliberate choice: `_get_replacement_slot` has 3 other
call sites (the mid-execution self-switch moves flagged in point 1), all
unrelated to this pause point, and changing its `-1`-means-"no valid target"
return contract to also carry a distinct "-1, waiting for human" meaning
would have risked all three. The external API for supplying a replacement is
`queue_replacement_for(combatant_idx, slot)` — again, an existing method, no
new one.

**6. Turn-order-splice interaction — confirmed via code tracing, not
assumed.** Traced (not assumed) that `_phase_switch_prompt`'s own PRE-EXISTING,
unrelated-to-this-session behavior already transitions unconditionally to
`BATTLE_END_CHECK` → (if no side is fully fainted) a FRESH `MOVE_SELECTION`,
regardless of whether the fainted-mon replacement happened mid-turn or at
genuine end-of-turn (`_phase_faint_check`'s own tail, lines ~6113-6123,
sends any-new-faint straight to `SWITCH_PROMPT` rather than resuming
`ACTION_EXECUTION`'s remaining `_turn_order` entries for that turn — a
pre-existing, already-tested design decision this session does not touch or
need to touch). Consequence: MOVE_SELECTION and SWITCH_PROMPT pauses are
**temporally disjoint by construction** from ACTION_EXECUTION's own
turn-order splices (Quash/Pursuit/Round/Shell Trap) — `_turn_order` is only
ever built (`_phase_priority_resolution`) once EVERY combatant's
move-selection choice is fully resolved, and by the time `SWITCH_PROMPT`
fires (mid-turn or end-of-turn), the engine has already decided this turn's
`ACTION_EXECUTION` portion is over. A human pause can therefore never leak
into a splice primitive's own read/write of `_turn_order`/
`_current_actor_index` — there is nothing to test for "a splice firing while
a side is mid-pause" because the two are never concurrent.

The one interaction actually worth testing (and built into the proof scene's
Section C) is the reverse direction: a human pauses at MOVE_SELECTION,
supplies input, and THAT SAME TURN's `ACTION_EXECUTION` runs a splice
primitive (Quash) that reorders the human's now-fully-resolved,
already-locked-in action — confirming the human's choice participates in a
splice with no special-casing needed, exactly like any AI/auto/queued
action. Building this test surfaced a genuine, useful discovery about
Quash's own real Gen8+ bubble-swap (`_apply_quash_bubble`,
`battle_manager.gd:8395`, shipped in the earlier `[Turn-order-splice trio]`
session): the bubble only ever swaps the target past a battler it is
GENUINELY SLOWER than **at the moment the bubble runs** — a naturally
speed-sorted `_turn_order` can never present that condition on its own
(whoever's positioned immediately after a battler in a stable sort is, by
construction, never someone that battler is slower than), so a plain
"target is fast, quasher is faster" fixture is a silent no-op. The proof
scene's actual working fixture uses a realistic 3-actor sequence: the
fastest combatant (b1) lowers the target's (a0's) Speed via Scary Face
BEFORE the Quash user (b0) acts — a0's INITIAL sort position used its
original, undropped Speed, but `_apply_quash_bubble`'s own
`_move_action_precedes` comparison re-evaluates Speed fresh at call time,
now reflecting the drop, which is exactly the condition needed for the
bubble to continue past the next battler. This is a real, previously-obscure
detail about Quash's own mechanic, surfaced only by trying to build this
test — not a bug (matches the already-shipped, already-tested behavior in
`turn_order_splice_test.gd`'s own `_test_item13_quash_partial_bubble`/
`_bubbles_to_end_when_slower_than_all`/`_noop_when_already_faster` fixtures,
which all use manually-constructed non-natural `_turn_order` arrays for the
identical reason), but worth recording here since a future session
attempting a similar "prove a splice fires" test should expect the same
pitfall.

**No genuine fork surfaced.** Every part of the design (state
representation, pause/resume flow, recompute-vs-lock-in, faint-replacement
generalization, splice interaction) composed cleanly with the existing
architecture and with each other — confirmed by full implementation,
a 4-part no-UI proof scene, and two clean full-regression sweeps (below),
not just asserted in the abstract.

### Implementation

`scripts/battle/core/battle_manager.gd`:
- New fields: `_human_controlled: Array[bool] = [false, false]`;
  `_move_selection_active: bool`/`_move_choice_resolved: Array[bool]`;
  `_switch_prompt_active: bool`/`_switch_prompt_resolved: Array[bool]`.
- New `set_human_controlled(side: int, value: bool) -> void` API, placed
  next to `set_trainer_ai`.
- `_phase_move_selection`: gained the fresh-entry reset guard, the
  per-combatant `if _move_choice_resolved[i]: continue` guard (checked
  before the existing per-iteration resets), a new `_chosen_moves[i] = null`
  reset added alongside the 4 pre-existing resets (a small correctness
  polish surfaced by the proof scene itself — see "one small production fix"
  below), the new `elif _human_controlled[side]: continue` branch, and a
  tail stall-check loop replacing the previously-unconditional
  `_set_phase(BattlePhase.PRIORITY_RESOLUTION)`.
- `_phase_switch_prompt`: gained the identical fresh-entry/per-combatant
  pattern, the human-pause pre-check before `_get_replacement_slot`, and a
  tail stall-check loop replacing the previously-unconditional
  `_set_phase(BattlePhase.BATTLE_END_CHECK)`.
- Zero changes to `advance()`, `_dispatch_phase()`, `_get_replacement_slot`,
  `_get_baton_pass_slot`, or any of the 4 mid-execution self-switch call
  sites.

**One small production fix, found by the proof scene's own first run (not
by static Step 0 reading):** without also resetting `_chosen_moves[i] =
null` at the top of the per-combatant loop (alongside the 4 fields already
reset there), a human-paused combatant's `_chosen_moves[i]` would keep
reading whatever move it resolved to on the PREVIOUS turn while awaiting
input for the CURRENT turn — harmless to production correctness (the
authoritative "is this resolved yet" signal is always
`_move_choice_resolved[i]`, never `_chosen_moves[i] == null`, and
`PRIORITY_RESOLUTION` is never reached until every entry is genuinely
resolved), but a real trap for any future UI code that might naively read
`_chosen_moves[i]` to render "what's currently selected" during a pause.
Fixed by adding the reset; confirmed via the proof scene's own Section A
(assertions A.02 through A.18) that a paused combatant's `_chosen_moves[i]`
now correctly reads `null` on every pause, not just the first.

### Proof scene results

`scenes/battle/m23_0a_proof_test.gd`/`.tscn` — no UI, a genuine test-shaped
scene playing the role of a future UI's click-handler, calling the exact
same `queue_*`/`advance()` methods a real UI would call.

- **Section A** (multi-turn singles, side 0 human-controlled): confirms
  `advance()` genuinely stalls at `MOVE_SELECTION` (not silently
  auto-resolving) on EVERY turn of a multi-turn battle, that the paused
  side's own `_chosen_moves` entry reads `null` while the auto-select side's
  already resolved within the same stalled pass, that supplying the move via
  `queue_move` + `advance()` produces real forward progress each time, and
  that this repeats across multiple separate pauses (not just the first
  turn) before the battle reaches `BATTLE_END`.
- **Section B** (faint-replacement pause): a frail human-side lead faints to
  an overwhelming opponent; confirms the phase stalls at `SWITCH_PROMPT`
  (distinct from `MOVE_SELECTION`) with the bench member NOT auto-switched
  in, then confirms `queue_replacement_for` + `advance()` cleanly switches
  the bench member in and the battle continues.
- **Section C** (turn-order-splice interaction, doubles): side 0
  human-controlled and paused at `MOVE_SELECTION` while side 1's actions are
  already pre-queued and resolved within the same stalled pass (the
  recompute-vs-lock-in proof); after side 0 supplies its actions, a
  same-turn Quash (used by a side-1 combatant) + a prior Scary Face speed
  drop (also side-1) correctly bubble the human-paused-then-resumed slot's
  action all the way to executing last — proving the human's choice, once
  supplied, participates in a splice with no special-casing.
- **Section D** (negative control): a battle with no side ever marked
  human-controlled runs to completion in a single `start_battle()` call with
  no stall at all — the same behavior every one of the 136 pre-existing
  tests already relies on.

Result: **79/79 assertions passing**, stable across 7 consecutive reruns
(after forcing `_force_roll`/`_force_crit`/`_force_hit` in Section A so the
number of turns — and therefore the number of per-turn assertions — is
deterministic rather than varying with unforced damage-roll RNG, matching
this project's own standing pairwise-RNG-forcing convention).

### Test-audit-first pass

Grepped for every existing reference to `_trainer_ais`, `_human_controlled`,
and the 5 new field/method names before writing any test: zero hits outside
`battle_manager.gd` prior to this session, confirming no existing test could
have been relying on the old unconditional single-pass behavior in any way
this change disturbs. The one file with direct (non-`advance()`-mediated)
calls to `_phase_move_selection()` — `scenes/battle/m22_item_action_test.gd`,
7 call sites — constructs a fresh `BattleManager` per call site, so
`_move_selection_active`/`_move_choice_resolved` start at their class
defaults every time; since none of these tests ever call
`set_human_controlled`, every one resolves in a single pass exactly as
before, confirmed via the regression sweep below (`m22_item_action_test`:
67/67 unchanged). No file anywhere calls `_phase_switch_prompt()` directly
(grepped, zero hits) — it is only ever reached via `advance()`/
`_dispatch_phase()` in every existing test.

### Regression sweep results

Two full sweeps via `scripts/count_assertions.sh`'s hardened absolute-path
invocation, from independent process states:

- Sweep 1: 137 files, GRAND TOTAL 13532. One suite short of clean:
  `m19a_gen1_test.tscn` 50/51.
- Sweep 2: 137 files, GRAND TOTAL 13533. `m19a_gen1_test.tscn` recovered to
  51/51; every other file's count identical to sweep 1, including the new
  `m23_0a_proof_test.tscn` (79/79 both times).

`m19a_gen1_test.tscn`'s single-assertion flake matches this project's own
already-documented, pre-existing statistical/aggregation-flaky suite (the
Hydro Pump/Rough Skin whole-battle-aggregation bug, `[D4 CHEAP bundle]`,
listed in CLAUDE.md's own "M19-complete baseline" note as expected
background noise) — confirmed unrelated to this session's changes, not a
regression.

**All 136 pre-existing test files are confirmed unaffected** by this
session's changes, run twice from independent process states with identical
results (the one flake excepted, itself pre-existing and already
documented). The new mechanism is purely additive: `_human_controlled`
defaults to `[false, false]` and is set nowhere outside the new proof scene.

### Confirmed design summary (for future M23 sessions to build on)

- **State**: `_human_controlled: Array[bool]` (per side, 2 elements always).
  Set via `bm.set_human_controlled(side, true)`.
- **Pause points covered**: `_phase_move_selection` (move/switch/item
  selection) and `_phase_switch_prompt` (faint replacement). **Not yet
  covered**: the 4 mid-move-execution self-switch contexts (Teleport/Chilly
  Reception, Hit Escape, Parting Shot, Baton Pass) — flagged as a known gap
  for a future M23 sub-phase, not attempted here.
- **External API**: no new methods — `queue_move`/`queue_move_targeted`/
  `queue_switch_for`/`queue_item_for`/`queue_replacement_for` (all
  pre-existing) are how a future UI supplies the human's action, followed by
  `advance()`.
- **Detecting a stall**: `bm.get_phase()` stays at `MOVE_SELECTION` or
  `SWITCH_PROMPT` after an `advance()` call returns without the phase having
  changed — a future UI polls or connects to `phase_changed` and checks
  `get_phase()` to know when to render an input prompt.
- **Doubles**: per-SIDE, not per-combatant — both slots of a human-controlled
  side pause independently within the same phase pass; supply both via two
  separate `queue_move_targeted`/`queue_switch_for`/`queue_item_for` calls
  before calling `advance()` (or call `advance()` after each — both work,
  since the guard only checks whether each specific combatant is resolved).
- **Recompute-vs-lock-in**: fully solved by per-combatant "resolved this
  pass" tracking — an already-resolved combatant (AI, auto-select, or
  test-queue) is never re-touched by a resumed call, regardless of how many
  times the phase function is re-entered while another side remains paused.

---

## M23.0b — UI tech decision + entry point

**COMPLETE** — 2026-07-16.

### Step 0 findings

**1. Confirmed no existing UI/main_scene setup** (verified, not assumed):
`project.godot`'s `[application]` section had no `run/main_scene` key at all
before this session (`grep` returned nothing). A full-repo grep for any
`.tscn` file containing a `Control`/`Button`/`Label`/`VBoxContainer`/
`CanvasLayer` node type found zero matches anywhere — `scenes/` only had
`maps/`, `battle/`, and `tilesets/` subfolders, none of them UI. `scripts/
ui/` (mentioned in CLAUDE.md's architecture overview) is confirmed empty.
This is genuinely greenfield.

**2. UI tech decision: plain Control nodes + one minimal shared `Theme`
resource (just `default_font_size`).** Recommended and built: a single
`scenes/main_theme.tres` setting `default_font_size = 20` (Godot 4's
default theme font is small enough at a typical window size to be a real
readability problem during dogfooding) and nothing else — no custom
StyleBoxes, no color palette, no font family override. This is the smallest
possible investment that avoids the "illegible grey-on-grey default Godot
UI becomes its own debugging obstacle" failure mode the task flagged, while
staying genuinely disposable — deleting this one `.tres` file and the one
`theme = ExtResource(...)` line reverts to pure Godot defaults with zero
other cleanup. Confirmed visually (screenshot, see below) that this single
setting alone produces perfectly legible white-on-dark-grey text and a
clearly-readable button label — no further theming was needed or added.

**3. M23.0a's external API translates with zero friction.** Read
`m23_0a_proof_test.gd`'s own calling pattern: construct a `BattleManager`
(`BattleManager.new()`), `add_child()` it, call `set_human_controlled`/
`start_battle*`, then from what would be a signal-handler in a real scene,
call `queue_move`/`queue_move_targeted`/`queue_switch_for`/
`queue_item_for`/`queue_replacement_for` followed by `advance()`. Confirmed
`BattleManager extends Node` (`battle_manager.gd:1-2`) and its own `_ready()`
(`:754-765`) does nothing but construct the internal Struggle placeholder
move and connect two purely-internal signals — no assumption anywhere that
it was constructed programmatically or added via `add_child()` specifically
(as tests do) rather than placed directly as a pre-existing node in a
scene's own `.tscn` tree (as a real scene naturally would). If anything,
real-scene usage is SIMPLER than the test harness's own pattern: a real
`.tscn` can place a `BattleManager` node directly in the scene tree with the
script already assigned, and Godot calls `_ready()` on it automatically via
ordinary node lifecycle — no manual `.new()`/`add_child()` needed at all.
A Button's `pressed` signal handler calling `bm.queue_move_targeted(...)`
then `bm.advance()` is a direct, one-to-one translation of the proof
scene's own external-call pattern. The only guidance a future UI needs (not
a gap, just a usage note): after each `advance()` call, check
`bm.get_phase()` (or connect to the pre-existing `phase_changed` signal) to
know whether the battle is now paused again (render the next input prompt)
or has moved on (e.g. to `BATTLE_END`). **No friction found; no API changes
needed.**

### Implementation

- New `scenes/main_theme.tres`: a `Theme` resource with only
  `default_font_size = 20` set.
- New `scenes/main.gd` + `scenes/main.tscn`: a single `Control` root (theme
  applied) containing a `VBoxContainer` with one `Label` and one `Button`.
  The button's `pressed` signal is connected in `_ready()` and updates the
  label text with a press count — deliberately NOT battle-specific, proving
  only that the entry point loads and that Control-node signal wiring works
  end-to-end. The real battle screen (move buttons, HP bars, switch/replace
  prompts) is M23.1's job.
- `project.godot`: added `run/main_scene="res://scenes/main.tscn"` to
  `[application]` (previously absent entirely).
- Placement: `scenes/main.tscn` sits at the `scenes/` root rather than
  inside `scenes/battle/` or a new `scenes/ui/` folder — this is the whole
  GAME's entry point (not itself a battle scene or a battle-specific UI
  element), so it doesn't fit CLAUDE.md's own "`scenes/battle/`: Battle
  scene(s), UI scene(s)" grouping, which is scoped to battle-related UI
  specifically. `scripts/ui/` (still empty) remains the intended home for
  future UI *script* logic; there is no established `scenes/ui/` convention
  to follow, so none was invented.

### Confirmed: launches normally, not just headless

Before this session, launching without `--headless` immediately failed with
`Error: Can't run project: no main scene defined in the project.` — this
confirmed the display/rendering path itself works in this environment
(reached that error, not a display-connection failure) and pinpointed the
exact gap this session closes.

After wiring `run/main_scene`:
- Headless smoke check (`--headless --quit-after 5`): loads cleanly, no
  errors, `PokemonRegistry`'s own autoload smoke test still prints
  correctly.
- **Real (non-headless) launch** (`--quit-after 15`, no `--headless`):
  initializes Vulkan via `llvmpipe` software rendering (no GPU in this
  sandbox, but a real rendering context all the same — not a stub), falls
  back to a dummy audio driver (expected: no ALSA/PulseAudio libraries in
  this sandbox, unrelated to the scene itself), loads the scene, runs 15
  real frames, exits cleanly with no scene-related errors.
- **Visually confirmed via a temporary screenshot capture** (a throwaway
  debug script swapped in for one run, then restored byte-for-byte via
  `diff`, not left in the repo): the button and label render exactly as
  designed, fully legible white-on-dark-grey text — confirming the
  `default_font_size`-only theme decision is sufficient on its own.
- A pre-existing, unrelated discrepancy was noted and confirmed NOT a
  blocker: `project.godot`'s `config/features` lists `"4.7"`, a feature-set
  string ahead of the `4.3.stable` binary this project actually uses
  (per CLAUDE.md's own documented invocation) — launching non-headlessly
  produced no version-mismatch warning or error of any kind, so this
  pre-existing discrepancy (not something this session introduced or
  needs to fix) does not affect anything built here.

Confirmed via a rerun of `scenes/battle/m23_0a_proof_test.tscn` (still
79/79) that this session's changes — purely new/additive UI-scaffolding
files plus one `project.godot` line — have zero effect on the battle
engine or its existing test suite; no battle logic was touched, so a full
regression sweep was not run (out of proportion for this session's actual
scope).

### Next step

M23.1 (bare-bones battle screen, two hardcoded teams) can now build real
battle UI directly into a new scene, wiring a `BattleManager` node into the
tree and driving it via the exact `queue_*`/`advance()` pattern confirmed
here — no further scaffolding decisions are needed first.

---

## M23.1 — Bare-bones battle screen, two hardcoded teams

**COMPLETE** — 2026-07-16.

### Pre-implementation confirmations

**Fixture pattern, quoted from `scenes/battle/ai_test.gd:83-99`** (the
pattern followed exactly, unchanged, for both hardcoded teams):

```gdscript
func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 160, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp    = hp
	sp.base_attack = atk
	...
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
```

paired with `_load_move(id)` (`load("res://data/moves/move_%04d.tres" % id)
as MoveData`) for real move data and `mon.add_move(move)` to build a
moveset (which also correctly populates the parallel `current_pp` array —
`add_move`'s own established purpose per this project's own documented
`[D4 Bundle 9]` gotcha about bypassing it via a bare `moves = [...]`
assignment). Both hardcoded teams (`battle_screen.gd`'s `_build_teams`) use
this identical pattern — no `PokemonRegistry`/species-data-converter
involved anywhere, matching the explicit M23.3/M23.4 scope boundary.

**Singles confirmed as the target mode, not doubles** — checked, not
assumed: `grep -rl "start_battle_with_parties\|\.start_battle("
scenes/battle/*.gd` matched 105 files; `grep -rl "start_battle_doubles"`
matched 21. Singles is the dominant mode across the whole existing test
suite (5:1) and is this engine's original/primary entry point (`BattleParty
.active_indices: Array[int] = [0]` is the class default; doubles was a
later, secondary M14a extension with its own separate `start_battle_doubles`
entry point). No genuine ambiguity found — singles is the correct,
lower-risk choice for a first "bare-bones" UI pass, and is what this session
built.

### Implementation

- New `scenes/battle/battle_screen.gd`/`.tscn`: the battle screen itself.
  Placed inside `scenes/battle/`, matching CLAUDE.md's own documented
  architecture grouping ("`scenes/battle/`: Battle scene(s), UI scene(s)"),
  unlike M23.0b's `scenes/main.tscn` (the whole game's entry point, not
  itself a battle scene).
  - A `BattleManager` node is placed DIRECTLY in the `.tscn` tree (script
    assigned, no manual `.new()`/`add_child()`) — exactly the "even
    simpler than the test harness" usage M23.0b's own Step 0 confirmed.
  - `_build_teams()`: two 2-member hardcoded parties — side 0 (human):
    Blaze (Fire; Ember/Flamethrower/Quick Attack/Swords Dance) and Torrent
    (Water; Water Gun/Surf/Bite/Tackle, bench); side 1 (AI): Leaf (Grass;
    Vine Whip/Razor Leaf/Growl/Tackle) and Volt (Electric; Thunderbolt/
    Thunder Wave/Quick Attack/Iron Tail, bench).
  - `_ready()`: builds teams, `set_trainer_ai(1, ai)` with `ai.tier =
    TrainerAI.Tier.SMART` (the existing, already-proven AI — zero new AI
    logic), `set_human_controlled(0, true)`, connects `battle_ended`, then
    `start_battle_with_parties(...)` — which, per M23.0a's own confirmed
    design, immediately stalls at `MOVE_SELECTION` before `_ready()`
    returns, since side 0 has nothing queued yet.
  - `_refresh_ui()`: reads `bm.get_phase()` and rebuilds the button area
    from scratch (no visibility toggling on pre-declared nodes — simplest
    correct approach for a screen whose available actions genuinely change
    shape). Three phase-driven states: `BATTLE_END` (win/lose label, no
    buttons), `SWITCH_PROMPT` (mandatory bench-picker only, no "Back" — a
    forced faint replacement), and `MOVE_SELECTION` (a `Menu` enum —
    `MAIN`/`SWITCH`/`ITEM` — selects between the 4 move buttons + Switch +
    Item, a bench sub-menu with Back, or an item sub-menu with Back).
  - Every button handler is the exact `queue_*()` + `advance()` +
    `_refresh_ui()` pattern confirmed by M23.0a/M23.0b:
    `queue_move_targeted(0, move_index, 1)` (move buttons — `1` is the
    opponent's active combatant index, always correct in singles),
    `queue_switch_for(0, slot)` (voluntary switch) / `queue_replacement_for
    (0, slot)` (forced faint replacement — same bench-picker UI, different
    queue call, matching M23.0a's own documented distinction between the
    two pause points), and `queue_item_for(0, item_id)` (item menu — 3
    fixed buttons, Potion(28)/Full Heal(48)/X Attack(121), IDs confirmed via
    `grep` against `data/items/*.tres`, reusing M22's existing mechanism
    exactly with no new item-action logic).
  - `scenes/main.gd`/`.tscn` (M23.0b): the entry-point button now reads
    "Start Battle" and calls `get_tree().change_scene_to_file(
    "res://scenes/battle/battle_screen.tscn")` instead of just incrementing
    a counter — a minimal but real launch flow, still no menu/persistence
    system beyond this one transition.
- Zero changes to `battle_manager.gd` or any other production battle-logic
  file — this session is UI-only, consuming M23.0a's contract exactly as
  documented, with no genuine bug surfaced (see "deviations" below for the
  two things that looked bug-shaped at first glance but weren't).

### Manual verification (no formal test file — an interactive scene, not a
### test suite; see the regression-sweep interaction note below for why)

Two independent checks, per this project's own "confirm both logic and
rendering" precedent from M23.0b:

1. **Headless logic drive**: a temporary, throwaway driver scene (not
   committed) loaded the REAL `battle_screen.tscn`, and called
   `.pressed.emit()` on the actual dynamically-created Button nodes (the
   same signal a real mouse click fires) to walk a full battle to
   completion — deliberately exercising Switch once, Item (Potion) once,
   then spamming the first available move/bench button otherwise. Result:
   the human's Torrent switched in and was immediately hit by the AI's
   turn (HP 250→178, since switching consumes the turn exactly like a
   move — expected engine behavior, not a bug); Potion's heal was
   partially offset by a subsequent Grass-vs-Water super-effective hit,
   net HP still dropping (178→126 — correct type-chart interaction, not a
   bug); Torrent fainted, the mandatory bench-picker correctly appeared
   with no "Back" option, and pressing it switched Blaze in; Blaze's Ember
   spam correctly fainted Leaf, at which point the AI's OWN bench member
   (Volt) auto-switched in with **zero UI involvement** (confirming
   AI-side faint-replacement is untouched, pre-existing, working logic);
   the battle correctly reached `BATTLE_END` after 13 real button presses,
   `winner_side=1`, and the screen correctly rendered "You lose!". No
   crashes, no hangs, no incorrect phase transitions.
2. **Real non-headless visual confirmation**: launched `battle_screen.tscn`
   without `--headless` (`--quit-after 10`), with a temporary screenshot
   capture swapped into `_ready()` for one run and then restored
   byte-for-byte (confirmed via `diff`, matching the established M23.0b
   precedent). Screenshot confirms all 6 controls (status label, both HP
   labels, 4 move buttons with live PP, Switch, Item) render legibly with
   the same `main_theme.tres` (`default_font_size = 20`) — no additional
   theming was needed.

### Regression sweep results

- **Before** (baseline, no M23.1 changes yet): 137 files, GRAND TOTAL
  13532. One pre-existing flake: `m19a_gen1_test.tscn` 50/51 (matches the
  already-documented Hydro Pump/Rough Skin whole-battle-aggregation bug).
- **After, sweep 1**: 138 files (the new `battle_screen.tscn` is picked up
  by the sweep script, since it lives in `scenes/battle/`), GRAND TOTAL
  **unchanged at 13532**. `battle_screen.tscn` correctly reported under
  "Files with NO recognized summary line" alongside the pre-existing
  `battle_test.tscn` — expected and harmless: it's an interactive scene
  with no `get_tree().quit()` call of its own, so the sweep script's
  existing per-scene `timeout 25` wrapper (unmodified, already built for
  exactly this "some scenes don't quit" case) lets it run harmlessly for up
  to 25 seconds before being killed, contributing 0 assertions and 0
  failures — the same handling `battle_test.tscn` has always received, not
  a new gap. `m19a_gen1_test.tscn` still 50/51, unchanged.
- **After, sweep 2**: 138 files, GRAND TOTAL 13532, byte-for-byte identical
  to sweep 1 (including `m19a_gen1_test.tscn` still 50/51 both times — the
  flake happened to sit still across all 3 sweeps this session, unlike its
  flip-flopping behavior in the M23.0a session; still the same
  already-documented suite, still unrelated).

**Zero regressions.** Every one of the 136 pre-existing test files'
assertion counts is byte-identical before and after, across 3 independent
sweeps. **One accepted, documented cost**: every future regression sweep
now takes roughly 25 extra seconds waiting for `battle_screen.tscn`'s own
`timeout` to fire, mirroring the exact cost `battle_test.tscn` has always
carried — not a new problem, an extension of an already-accepted one.

### Deviations from the task's literal spec, and why

- **Two things that looked bug-shaped during manual verification but
  weren't, worth recording explicitly since a future session might
  otherwise "re-discover" and try to "fix" them**: (1) switching consumes
  the turn (the newly-switched-in mon can be hit by the opponent in the
  same button press that performed the switch) — this is the existing,
  correct, already-tested M9 switching mechanic, not something this
  session introduced or should paper over with a free "safe switch." (2)
  Potion's heal can still result in a net HP decrease within the same
  button press, if the opponent's follow-up hit that same turn is large
  enough (e.g. a super-effective Grass hit on the Water-type Torrent) —
  again correct, pre-existing turn-resolution order, not a bug in the item
  menu.
- **No deviation found from the explicit constraints**: `_trainer_ais[side]
  == null` semantics untouched; M23.0a's core contract untouched (no
  changes to `battle_manager.gd` at all this session); UI kept to plain
  functional buttons with zero animation/polish beyond the one shared
  theme already established in M23.0b.
- **One scope interpretation, not a deviation**: the task said "no battle
  log (M23.2)" — read as excluding a scrolling/persistent history of past
  events specifically, not excluding ANY display of current state. The
  screen shows the two active mons' names/HP and a one-line status message
  (whose turn it is / what's happening / the win-lose result) since a
  screen with literally zero state feedback beyond buttons would not be
  meaningfully "playable" for the manual-verification purpose this
  milestone exists for. This is presented as an explicit interpretation
  for review, not asserted as obviously correct.

### Open questions before this gets committed

1. **Is showing current HP/active-mon-name state (not a scrolling log) the
   right read of "no battle log (M23.2)"?** Flagged above as an explicit
   interpretation, not a unilateral scope expansion — happy to strip it
   back to literally nothing but buttons if that's not the intent.
2. **`scenes/battle/battle_screen.tscn`'s ~25s contribution to every future
   sweep** (documented above, not a bug) — acceptable as-is (matching
   `battle_test.tscn`'s own precedent), or worth a follow-up exclusion
   mechanism in `count_assertions.sh` for genuinely-interactive scenes?
   Not fixed here since it wasn't flagged as in-scope and the cost is
   small and precedented.
3. **The item menu's fixed 3-button list (Potion/Full Heal/X Attack)** has
   no real bag-inventory/quantity tracking behind it (every button is
   always available, unlimited uses) — matches "no team builder... purely
   to prove the async loop," but flagging explicitly in case a bag/
   inventory system is expected sooner than assumed.

---

## M23.1 addendum — headless autoplay exit path

**COMPLETE** — 2026-07-16, closes Open Question 2 above.

### Convention check

Grepped for any existing CLI-arg/env-var toggle anywhere in the codebase
(`OS.get_cmdline_args`/`OS.get_environment`/`DisplayServer.get_name`/
`OS.has_feature`) before building anything: zero hits. None of the 137
pre-existing test scenes needed one — every one of them is unconditionally
"in test mode," so there was nothing to match. **A new convention was
proposed rather than matched, per the task's own explicit fallback
instruction**: a literal CLI flag, `--autoplay`, checked via `"--autoplay"
in OS.get_cmdline_args()` — a deliberate, explicit toggle rather than
implicit `DisplayServer.get_name() == "headless"` detection, since the task
asked specifically for "a flag (CLI arg or env var)." This is now the
established pattern for any future interactive scene needing the same
headless/sweep-friendly exit path.

### Implementation

`scenes/battle/battle_screen.gd`:
- `_ready()` gained one new branch, checked immediately after
  `start_battle_with_parties()` (which already stalls at `MOVE_SELECTION`
  synchronously): if `--autoplay` is present, call `_run_autoplay()` and
  `return` — skipping `_refresh_ui()` and every button/label entirely.
  Without the flag, execution falls through to the exact same
  `_refresh_ui()` call as before this session, byte-for-byte unchanged.
- New `_run_autoplay()`: a `while` loop (capped at 200 iterations, matching
  this project's own established `guard`-loop convention) driving the
  battle via the SAME `queue_move_targeted`/`queue_replacement_for` +
  `advance()` calls the interactive button handlers already use — always
  picking the first move with remaining PP (`_first_usable_move_index`,
  falling back to index 0 if none remain, letting the engine's own
  pre-existing forced-Struggle logic take over exactly as it does for a
  human player in the same situation) and the first available bench slot
  for a mandatory faint replacement (`_first_switch_slot`). Deliberately
  does not exercise voluntary switching or the item menu — a move is
  always the most basic "first legal action," and this is a plumbing
  check, not an AI-behavior test.
- On `BATTLE_END`, prints `"battle_screen_autoplay: %d/1 passed" %
  passed`, matching `scripts/count_assertions.sh`'s own documented
  `"<suite_name>: N/M passed"` regex exactly (the majority convention
  across this whole codebase) — genuinely conditional, not an
  unconditional pass: `passed` requires BOTH that `BATTLE_END` was reached
  (not just the guard cap firing) AND that `_winner_side` recorded a real
  value (0 or 1), so a hang or a broken `battle_ended` wiring would
  correctly report `0/1` and `FAILED`, not a vacuous pass. Calls
  `get_tree().quit(0 if passed == 1 else 1)`.
- `scripts/count_assertions.sh`: the one line launching every scene now
  appends `--autoplay` unconditionally, for all 138 files — not
  special-cased to `battle_screen.tscn` alone. This is safe (the other 137
  scenes don't check for or care about any extra trailing CLI arg — Godot
  doesn't error on an unrecognized one) and avoids hardcoding a filename
  into the sweep script's own generic loop.

### Interactive path — confirmed completely unaffected

Two checks, mirroring M23.1's own verification approach:
1. **Headless, no flag** (`--quit-after 5`): loads and idles exactly as
   before — no summary line, no `quit()`, matching pre-session behavior
   precisely.
2. **Real button-press replay** (the same throwaway `.pressed.emit()`
   driver scene M23.1 used, recreated temporarily and deleted afterward —
   confirmed clean via a directory listing showing zero scratch files
   left behind): walked the interactive scene through a full battle via
   real signal emission with the flag absent — identical outcome to
   M23.1's own original verification run (`BATTLE_END` after 13 presses,
   `winner_side=1`). Zero behavioral difference from before this session.

### Regression sweep results

- **Before**: 138 files, GRAND TOTAL 13532. `battle_screen.tscn` under
  "no recognized summary line" (alongside `battle_test.tscn`).
- **After, sweep 1**: 138 files, GRAND TOTAL **13533** (+1, exactly the new
  `battle_screen_autoplay: 1/1 passed` line). `battle_screen.tscn` is now
  correctly REMOVED from the "no recognized summary line" list — only
  `battle_test.tscn` remains, exactly as documented/expected. A direct
  diff against the "before" sweep shows **every other file's count
  byte-identical** — the only line that changed at all is
  `battle_screen.tscn` itself, going from 0 (unrecognized) to 1
  (recognized).
- **After, sweep 2**: 138 files, GRAND TOTAL 13533 again. `battle_screen`
  stable at 1/1 in both sweeps. The only two differing lines between
  sweep 1 and sweep 2 are `m17l_test.tscn` (45→44) and
  `m19a_gen1_test.tscn` (50→51) — both already-documented, named,
  pre-existing statistical/aggregation-flaky suites (CLAUDE.md's own
  "M19-complete baseline" flaky-suite list), unrelated to this session.

**Zero regressions.** `battle_screen.tscn` now contributes a real,
genuinely-conditional assertion to every future sweep instead of silently
burning ~25 seconds on a `timeout` kill, closing Open Question 2 from the
M23.1 section above.

---

## M23.2 — Battle log

**COMPLETE** — 2026-07-16.

### Signal inventory

Grepped every `^signal` declaration in `battle_manager.gd`: **~110 distinct
signals** (close to the "~127" figure cited in prior M23 notes — the exact
count drifts slightly session to session as new mechanics ship, not worth
re-deriving precisely for this purpose). Per the task's own explicit
constraint ("do not invent new event types unless something critical is
missing"), zero new signals were added — `battle_manager.gd` was not
touched at all this session. The existing surface was already more than
sufficient for every category the task named.

**Deliberately wired a representative ~16-signal subset, not all ~110** —
this screen's own hardcoded 2-team roster (2 items, zero abilities
assigned, zero held items, zero hazard/screen/weather-setting moves) can
only ever trigger a specific slice of the full signal surface; wiring
literally all ~110 would mean connecting dozens of handlers for mechanics
(Bide, Substitute, weather, hazards, screens, ability triggers, doubles-
only redirects, the whole delayed-effect-scheduling family, etc.) this
roster structurally cannot reach, for zero observable benefit. The 16
chosen cover every category the task explicitly named (moves used, damage,
faints, switches, item use, status effects) plus a few cheap, generally-
useful extras:

- `move_executed` — "X used Y!" / "X used Y! (N damage)"
- `move_missed` / `move_missed_target` — "X's attack missed!" / "X avoided
  the attack!"
- `pokemon_fainted` — "X fainted!"
- `pokemon_switched_out` / `pokemon_switched_in` — "X was withdrawn!" /
  "Go, X!" (covers both a voluntary Switch button press and the AI's own
  automatic faint-replacement, confirmed via the manual playthrough below
  — `_do_voluntary_switch` emits both; faint-replacement's `_do_switch_in`
  only emits the "switched_in" half, correctly matching what's already
  logged via `pokemon_fainted` for the mon that left)
- `stat_stage_changed` — "X's STAT rose/fell!" (covers Swords Dance,
  Growl, X Attack, and any secondary stat-drop chance)
- `secondary_applied` — mapped from `MoveData.SE_*` to plain status text
  ("was burned"/"was paralyzed"/"fell asleep"/"became confused"/
  "flinched"/etc.)
- `status_cured` / `party_status_cured` — "X's status was cured!" (the
  latter is Full Heal's own actual signal, confirmed via direct source
  read of `_do_item_use` — NOT `status_cured`, a real naming trap this
  session checked rather than assumed)
- `item_action_used` — "X used ITEM!" (fires generically for every bag
  item, confirmed via source to fire unconditionally before any
  item-specific effect signal)
- `item_healed` — "X recovered N HP!" (Potion)
- `recoil_damage` / `drain_heal` / `status_damage` / `confusion_self_hit` —
  cheap, generally-useful extras; none of this specific roster's moves
  currently trigger them, but they cost nothing to wire and generalize the
  log to future rosters for free.

**Explicitly NOT wired** (flagged, not silently dropped): weather/hazard/
screen signals, ability-trigger signals (`ability_triggered`,
`ability_changed`, etc.), doubles-only redirect signals, and the long tail
of move-specific one-off signals (Bide, Substitute, the delayed-effect
scheduling family, turn-order-splice signals, etc.). None are reachable by
this screen's current fixed roster. Adding log coverage for any of them
later is a one-line `_bm.SIGNAL.connect(...)` addition inside
`_wire_log_signals()`, not a redesign.

### Implementation

- `scenes/battle/battle_screen.tscn`: new `RichTextLabel` (`LogLabel`),
  placed between the HP labels and the button area (so its position stays
  fixed regardless of how many buttons are currently showing), with
  `scroll_active = true` and `scroll_following = true` — Godot's own
  built-in auto-scroll-to-bottom behavior, needing zero manual scroll
  management code. `bbcode_enabled = false` — plain text only, no color-
  coding. `custom_minimum_size = Vector2(500, 220)`.
- `scenes/battle/battle_screen.gd`:
  - New `_wire_log_signals()`, called once from `_ready()` (unconditionally
    — see the autoplay decision below), connecting the ~16 signals above.
  - New `_log(text: String)`: appends `text + "\n"` to `_log_label.text` —
    literally "plain text lines appended in order," matching the task's
    own requirement 1 exactly, no buffering or reordering.
  - New `_mon_label(mon) -> String`: "Your X" / "Foe X", determined via
    `_player_party.members.has(mon)` membership check (this screen is
    fixed 2-side singles, so this is sufficient — no combatant-index
    lookup needed).
  - `_on_battle_ended` (already existed, M23.1) gained one added line
    logging the win/lose result — the only change to any pre-existing
    function; every other M23.1 code path (labels, buttons, menus, input
    handlers) is untouched.

### Autoplay decision

**Wired unconditionally — the log populates during BOTH the interactive
and `--autoplay` paths, no branching on the flag.** Reasoning, per the
task's own explicit prompt: it named "useful for debugging failures" as a
reason FOR populating during autoplay, and connecting ~16 signal handlers
plus short string appends has no meaningful performance cost (a typical
autoplay run is ~13 turns; this is not the kind of per-frame cost this
project's own performance-sensitive code — the battle engine itself —
needs to worry about). Keeping one unconditional wiring path is also
simpler than adding a second conditional branch for a feature with
negligible cost either way.

### Manual verification

A real button-press replay (the same `.pressed.emit()`-driven throwaway
scratch scene established in M23.1/M23.1-addendum, recreated temporarily
and deleted afterward — confirmed clean via a directory listing showing
zero scratch files left behind), printing the final `_log_label.text` at
`BATTLE_END`. Confirmed the log correctly captured, in order: a voluntary
switch ("Your Blaze was withdrawn! / Go, Your Torrent!"), moves with and
without damage, an item use plus its heal ("Your Torrent used Potion! /
Your Torrent recovered 19 HP!"), a faint ("Your Torrent fainted!"), the
resulting forced replacement ("Go, Your Blaze!"), a status effect
("Your Blaze was paralyzed!"), the opponent's own faint and the AI's
completely automatic replacement (zero UI/log-wiring special-casing needed
— "Foe Leaf was withdrawn! / Go, Foe Volt!"), and the final result
("You lose!"). Separately confirmed via a real non-headless screenshot
that the `RichTextLabel` itself renders legibly against the shared
`main_theme.tres` theme, matching every prior M23 session's own visual-
confirmation precedent.

**One honest, non-bug nuance observed and flagged, not fixed**: in one
exchange, the log printed `"Your Blaze used Ember! (36 damage)"` then
`"Your Blaze was paralyzed!"` then `"Foe Volt used Thunder Wave!"` — the
paralysis line appears to "precede its own cause" in reading order. This
is not a bug in the log (which appends strictly in the order signals
actually fire) — it reflects `battle_manager.gd`'s own existing dispatch
order for Thunder Wave's execution (the status is applied, emitting
`secondary_applied`, before the function's own trailing `move_executed`
call summarizing the action). Reordering this would require buffering and
re-sorting a turn's events by "narrative cause" before display — real
scope creep beyond "plain text lines appended in order" (this session's
literal requirement 1), and out of scope for a bare-bones milestone.
Flagged here for visibility, not fixed.

### Regression sweep results

- **Before**: 138 files, GRAND TOTAL 13534.
- **After, sweep 1**: 138 files, GRAND TOTAL 13533. The only differing line
  vs. "before" is `m19a_gen1_test.tscn` (51→50) — the same
  already-documented, named, pre-existing statistical/aggregation-flaky
  suite (CLAUDE.md's own "M19-complete baseline" flaky-suite list),
  unrelated to this session. `battle_screen.tscn` unchanged at 1/1.
- **After, sweep 2**: 138 files, GRAND TOTAL 13534 again. The only
  differing line vs. sweep 1 is the same `m19a_gen1_test.tscn` flipping
  back (50→51). `battle_screen.tscn` stable at 1/1 in both sweeps.

**Zero regressions.** Every other file's count is byte-identical across
all three sweeps (before, after-1, after-2) — this session's changes are
purely additive to `battle_screen.gd`/`.tscn`, with `battle_manager.gd`
untouched.

## M23.2 addendum — broadened signal coverage + log-ordering fix

Two independent follow-up fixes to the M23.2 battle log, requested
together. `battle_manager.gd` untouched in both parts, per the task's own
constraint.

### Part 1 — broadened signal coverage

Wired 13 more signals: `weather_set`/`weather_expired`/`weather_damage`,
`hazard_set`/`hazard_damage`/`hazard_status_applied`/`hazard_absorbed`/
`hazards_cleared`, `screen_set`/`screen_expired`/`screens_broken`,
`ability_triggered`/`ability_healed`. Confirmed via direct signature
inspection (not assumed) that all 13 are singles-safe — every one is keyed
by a plain `side: int` (0/1) or a single `pokemon` parameter, with no
ally-slot/field-position argument anywhere. None were doubles-gated, so
none needed to be skipped.

- Weather: fixed start/end flavor text per `DamageCalculator.WEATHER_*`
  (`"It started to rain!"` / `"The sunlight turned harsh!"` / etc.),
  ignoring which Pokémon/move caused it (consistent with this screen's own
  "plain text, no filtering" scope). `weather_damage` reuses the
  established `"%s was hurt by X! (%d damage)"` shape.
- Hazards/screens: display-name dictionaries keyed off the same string
  tags `battle_manager.gd`'s own signals already use ("spikes"/
  "toxic_spikes"/"stealth_rock"/"sticky_web", "reflect"/"light_screen"/
  "aurora_veil") plus a new `_side_label(side)` helper ("your"/"the foe's").
  `hazard_status_applied` reuses a new `_status_name(status)` helper
  mirroring the existing `secondary_applied` status-name mapping.
- `ability_triggered`: its own `effect_key` is a slug string with ~50
  distinct values across the whole ability roster. Rather than
  hand-authoring bespoke text per key (which would also go stale the next
  time a new ability ships), this screen formats it generically —
  `"%s's %s activated!" % [mon, effect_key.replace("_", " ")]`. Readable
  and always in sync with the real signal surface, though less polished
  than a per-ability phrase — flagged as a reasonable simplification, not
  silently under-scoped.
- `ability_healed`: handles both signs of its `amount` param (Poison
  Heal's own dispatch emits a *negative* value to represent damage, not a
  heal) — positive logs a heal line, negative logs a damage line.

This screen's own fixed 2v2 roster (Blaze/Torrent vs Leaf/Volt, no held
items, no abilities assigned to any fixture) cannot naturally trigger any
of these 13 signals through real gameplay — confirmed via a scripted
direct-signal-emission check instead (see Manual verification below),
per the task's own explicitly allowed alternative to a live playthrough.

### Part 2 — log-ordering fix

**Root cause, confirmed via direct source read**: `battle_manager.gd`'s
own pure single-target status-move dispatch (`_phase_move_selection`'s
downstream execution block, `if move.stat_change_stat >= 0: ... elif
move.secondary_effect != MoveData.SE_NONE: ...`) emits `stat_stage_changed`
/`secondary_applied` *inside* that branch, then emits the causing
`move_executed` at the very end of the same synchronous block — this is
exactly the "paralyzed" line preceding "used Thunder Wave!" nuance flagged
in M23.2. Confirmed the DAMAGING-hit path (`_do_damaging_hit`) does **not**
have this problem: `move_executed` already fires immediately after HP is
reduced, with any post-hit secondary effects (`SE_FLINCH`, on-hit stat
drops, etc.) emitted afterward in that same function — no reordering
needed there, and none was applied there.

Fix, scoped to the narrowest mechanism that corrects the flagged case
(per the task's own "simplest mechanism... without a large architectural
change" instruction) — also extended to `stat_stage_changed`, since it is
the identical bug in the identical dispatch block (e.g. Growl's own stat
drop precedes "used Growl!" the same way), not a separate issue requiring
separate scope:

- `_on_log_secondary_applied`/`_on_log_stat_stage_changed` no longer call
  `_log()` directly — they append their formatted line to a new
  `_pending_effect_lines: Array[String]` buffer instead.
- `_log()` (the sink every *other* handler still calls directly) now
  flushes that buffer *before* appending its own new line — so a buffered
  line is never dropped or permanently stuck; it surfaces at the very next
  log event, in its original relative position, unless that next event is
  specifically the causing `move_executed`.
- `_on_log_move_executed` is the one deliberate exception: it appends its
  own cause line directly (bypassing `_log()`'s auto-flush), *then* calls
  the new `_flush_pending_effect_lines()` — swapping the order only in
  exactly the case that needed swapping.

No new signals, no new BattleManager involvement, no per-action
correlation key — the fix is purely a one-step reordering local to
`battle_screen.gd`'s own log-building code.

### Manual verification

A scripted signal-emission test (a throwaway scratch scene,
`_scratch_verify_addendum.gd`/`.tscn`, created temporarily then deleted —
confirmed clean via a directory listing showing zero scratch files left
behind), instantiating the real `battle_screen.tscn`, driving a real
3-turn sequence through the actual `queue_switch_for`/`queue_move_targeted`
+ `advance()` contract (forcing Leaf → Volt via a genuine voluntary
switch, then Volt using Thunder Wave on Blaze with `_force_hit = true`),
and inspecting the resulting `_log_label.text`:

```
Your Blaze used Quick Attack! (19 damage)
Foe Leaf used Tackle! (19 damage)
Foe Leaf was withdrawn!
Go, Foe Volt!
Your Blaze used Quick Attack! (22 damage)
Your Blaze used Quick Attack! (23 damage)
Foe Volt used Thunder Wave!
Your Blaze was paralyzed!
```

Confirmed **"Foe Volt used Thunder Wave!" now precedes "Your Blaze was
paralyzed!"** — the exact case flagged in M23.2, now cause-before-effect.
Separately confirmed a newly-wired signal category produces a correct log
line via a direct `weather_set.emit(mon, DamageCalculator.WEATHER_SANDSTORM)`
call against the same live instance, producing `"A sandstorm kicked up!"`.

### Regression sweep results

- **Before**: 138 files, GRAND TOTAL 13531.
- **After**: 138 files, GRAND TOTAL 13531 (a second independent sweep read
  13532 — the +1/-1 swing matches the same already-documented pre-existing
  statistical/aggregation-flaky-suite noise class every prior M23 session
  has observed, not a regression). `battle_screen.tscn` unchanged at 1/1
  in every run.

**Zero regressions.** This session's changes are purely additive/
reordering within `battle_screen.gd`/`.tscn` — `battle_manager.gd` was not
touched, per the task's own constraint.

### Deviations / assumptions flagged

- `ability_triggered`'s generic `effect_key`-derived text (see Part 1
  above) trades per-ability flavor for zero maintenance burden — flagged
  as a deliberate simplification, open to revisiting if a future session
  wants bespoke text for specific abilities.
- The ordering fix's scope was widened from "the specific case flagged in
  M23.2" (`secondary_applied`) to also cover `stat_stage_changed`, since
  both signals share the exact same root cause in the exact same
  dispatch block — treated as one fix, not two, per the task's own
  "simplest mechanism" instruction rather than narrowly patching only the
  literal example given.
- Nothing committed, per standing instruction.

## ability_triggered message quality pass

Follow-up to the M23.2 addendum's own flagged simplification: the generic
`effect_key.replace("_", " ")` formatter is replaced with a full lookup
table. No signals rewired, no ordering-buffer changes — a
message-formatting-only pass, per the task's own scope.

### What was built

Grepped every `ability_triggered.emit(...)` call site in
`battle_manager.gd` (63 literal string arguments, plus 4 sites passing a
dynamically-resolved variable — `attract_result`, `eot_dmg_tag`,
`retaliation["ability_name"]`, `contact_result["ability_name"]` — each
traced back to its own small, fixed set of possible values by reading the
assigning code, not guessed). Combined literal + resolved-dynamic set: **86
distinct `effect_key` values**, all now covered by a new
`_ABILITY_TRIGGER_TEXT: Dictionary` constant in `battle_screen.gd`, each
mapped to a `"%s's <AbilityName> <what it did>!"`-style message (or, where
the pokemon param isn't the ability's own holder — e.g. `"damp"` fires on
the blocked attacker, not the Damp holder — phrasing that stays correct
without needing the holder's name at all).

New `_on_log_ability_triggered(mon, effect_key)` replaces the inline lambda:
looks up `effect_key` in the table and formats with `_mon_label(mon)`; if
absent, falls back to the exact prior generic formatter (requirement 4 —
nothing silently breaks for a missed or future-added key).

### Flagged low-confidence / intentionally generic messages

Per requirement 3, these keys are used across mechanically different call
sites, or bundle multiple distinct abilities/effects under one shared
string — the key alone can't disambiguate which sub-case fired, so the
message uses the most accurate generic phrasing that stays true for every
sub-case rather than guessing a specific one incorrectly:

- **`guard_dog`** — 3 shapes: blocks a Roar/Whirlwind-forced switch, blocks
  a Red-Card-forced switch, or reverses an incoming Intimidate into a
  self-buff on switch-in.
- **`moody`** — raise-or-lower and which of 7 stats isn't in the key
  (`stat_stage_changed`'s own buffered line, logged right after, does show
  the specific stat).
- **`defiant_competitive`** — Defiant (Atk) vs. Competitive (Sp. Atk) isn't
  distinguishable from the key.
- **`download`** — raises Atk or Sp. Atk depending on the target's own
  bulkier defensive stat; not in the key.
- **`hydration_shed_skin`** — Hydration (rain-cure) vs. Shed Skin
  (random-chance cure) isn't distinguishable.
- **`immunity_family_cure`** — any of Insomnia/Vital Spirit/Immunity/
  Limber/Water Veil/Magma Armor; isn't distinguishable.
- **`rain_dish_ice_body_dry_skin`** — which of the 3 heals isn't in the key.
- **`absorb_stat_boost`** — Sap Sipper/Motor Drive/Well-Baked Body, and
  which stat/magnitude, isn't in the key.
- **`absorb_heal`** — Volt Absorb/Water Absorb/Dry Skin/Earth Eater isn't
  distinguishable.
- **`dazzling_family`** — Dazzling/Queenly Majesty/Armor Tail isn't
  distinguishable.
- **`soundproof_bulletproof`** — which of the two blocked isn't in the key.
- **`effect_spore`** — poison/sleep/paralysis isn't in the key, but the
  buffered `secondary_applied` line logged right after already names the
  specific status, so this line doesn't need to repeat it.

Every other one of the 86 keys maps 1:1 to a single, unambiguous ability
(confirmed individually from source context) and got specific, accurate
text — nothing else was left generic.

### Manual verification

A scripted signal-emission test (throwaway scratch scene, deleted after),
instantiating the real `battle_screen.tscn` and calling
`bm.ability_triggered.emit(mon, key)` directly for 5 keys:

```
key=intimidate -> Your Blaze's Intimidate lowered the opposing Pokémon's Attack!
key=sturdy -> Foe Volt's Sturdy endured the hit!
key=magic_bounce -> Your Blaze's Magic Bounce reflected the move!
key=rain_dish_ice_body_dry_skin -> Foe Volt's ability restored some HP!
key=some_totally_unknown_future_key -> Your Blaze's some totally unknown future key activated!
```

Confirms 4 mapped keys each produce their intended readable message, and
an unrecognized key correctly falls through to the old generic formatter
unchanged.

### Regression sweep results

- **Before**: 138 files, GRAND TOTAL 13531.
- **After**: 138 files; three independent sweeps read 13533, 13533, and
  13534 — all within the same already-documented pre-existing
  statistical/aggregation-flaky-suite noise band this project's sweeps
  have shown throughout M23 (confirmed by name: `m17l_test.tscn` and
  `m19a_gen1_test.tscn` both read clean, 45/45 and 51/51, in the final
  sweep — the ±1-3 swing traces to other suites in the documented flaky
  set, not to this session's changes). `battle_screen.tscn` unchanged at
  1/1 in every run.

**Zero regressions.** This session's changes are confined to
`battle_screen.gd` (one new dictionary constant, one new handler function,
one changed `connect()` call) — no other file was touched.

### Deviations / assumptions flagged

- 12 of the 86 keys use intentionally generic (not per-sub-case) phrasing
  — see the flagged list above; this is a documented simplification, not
  an oversight.
- `lansat_berry`/`micle_berry` are technically item effects (berries), not
  abilities, but `battle_manager.gd` emits them via `ability_triggered`
  anyway — the existing signal contract was treated as fixed input, per
  the task's own constraint not to modify `battle_manager.gd`, so they're
  included in the lookup table rather than left on the generic fallback.
- Nothing committed, per standing instruction.

## M23.3 — PokemonSpecies-from-real-data converter

### What was built

New `scripts/battle/core/pokemon_factory.gd` (`class_name PokemonFactory`,
`extends RefCounted`, all `static func` — matching `MoveRegistry`/
`ItemRegistry`/`AbilityManager`/`DamageCalculator`'s own established
utility-class convention, not an autoload; placed alongside `move_registry
.gd`/`item_registry.gd` in `scripts/battle/core/` rather than
`scripts/data/`, since it produces battle-domain `BattlePokemon`s, not raw
registry data). Two public entry points:

- `build_species(dex) -> PokemonSpecies`: converts `PokemonRegistry.
  get_species(dex)`'s raw JSON dict into a real, fully-populated
  `PokemonSpecies` Resource. Returns `null` for a nonexistent dex.
- `create_battle_pokemon(dex, level, move_ids, forced_nature, forced_ivs,
  forced_friendship, evs, ability_slot) -> BattlePokemon`: builds the
  species, then a real `BattlePokemon` via the SAME `BattlePokemon.
  from_species(...)` constructor every hand-built test fixture already
  uses — no new `BattlePokemon`/`BattleManager` machinery of any kind, and
  `battle_manager.gd` was not touched.

### How real data is sourced

- **Species data**: `PokemonRegistry.get_species(dex)` (`data/pokemon
  .json`, loaded by the `PokemonRegistry` autoload — the same registry
  every scene's own "PokemonRegistry: smoke test passed..." boot log
  confirms, found by reading `scripts/data/pokemon_registry.gd` in full
  per this task's own explicit instruction, not guessed).
- **Moves**: `MoveRegistry.get_move(id)` (`res://data/moves/move_%04d.tres`
  — the real, implemented `.tres` `MoveData` Resources), **NOT**
  `PokemonRegistry.get_move()`. Confirmed via `[M19-pipeline-fix]`'s own
  decisions.md entry that `PokemonRegistry`'s own `data/moves.json`
  pipeline has zero real production consumers anywhere in this codebase —
  using it would have produced a converter that "worked" but fed the
  battle engine data nothing else in the project actually trusts.
- **Learnset**: `PokemonRegistry.get_learnset(dex)`, used both to populate
  `PokemonSpecies.learnset` (informational — nothing in the battle engine
  reads this field off the instance) and to auto-derive a default moveset
  when no explicit `move_ids` are given.
- **Abilities**: loaded ad hoc via `res://data/abilities/ability_%04d.tres`
  — matching this project's own already-established "no AbilityRegistry"
  convention (`AbilityManager`'s mechanic dispatch is 100% hardcoded
  ability-ID constants; the `.tres` layer is a metadata catalog only).

### Real-data quirks found and handled (not assumed from the schema's own doc comments)

- **Mono-typed species are stored as the SAME type twice** in `pokemon
  .json` (e.g. Mewtwo/Pikachu = `[15, 15]`), **not** `[type, TYPE_NONE]` as
  `PokemonSpecies.types`'s own doc comment describes for hand-built
  fixtures. Confirmed by direct inspection (Bulbasaur `[13, 4]`, Mewtwo
  `[15, 15]`), not assumed — `build_species()` de-duplicates this
  explicitly (verified in Section 1 of the test suite, S1.12, which checks
  the RESULT is `[PSYCHIC]`, not a duplicated pair).
- **`growth_rate` is a STRING in real data** (`"MediumSlow"`, `"Slow"`),
  but `PokemonSpecies.growth_rate` is a dormant `int` enum with no defined
  values anywhere in this codebase. Traced `BattleManager._check_level_up`
  directly and confirmed it already reads growth rate FRESH from
  `PokemonRegistry.get_species(dex)` every time, BY DESIGN (its own doc
  comment: keeps the level-up path automatically evolution-safe with no
  stale-species-snapshot risk) — never from a `PokemonSpecies` instance
  field. Left unpopulated rather than inventing an int mapping nothing
  would consume.
- **JSON float coercion**: `JSON.parse_string` returns every numeric value
  as `float`, not `int` — a standing project-wide gotcha (already in this
  assistant's own memory notes). Every numeric field read from the raw
  dict is explicitly `int()`-cast in `build_species()`; without this,
  assigning a bare float into one of `PokemonSpecies`'s strictly
  `int`-typed `@export` fields throws a runtime type-mismatch error.

### Verification — 4 diverse real species, checked against the registry's own data

**Bulbasaur** (1, Grass/Poison, standard dual-type/ability layout),
**Charizard** (6, Fire/Flying, real hidden ability Solar Power),
**Mewtwo** (150, mono Psychic — the type-dedup case — genderless, no 2nd
ability), **Rayquaza** (384, Dragon/Flying, genderless, EMPTY hidden
ability slot — `ability_h=0`, the "no hidden ability at all" case).

Every exact-value assertion compares against either (a) `PokemonRegistry`'s
own raw dict for that species directly, or (b) an independently
hand-computed expected stat via the documented Gen III+ HP/stat formula
(Bulbasaur L50 and Charizard L36, both with `NATURE_HARDY` + all-zero IVs
forced, hand-verified via Python before being trusted as assertions,
matching this project's own established convention) — never a value read
back from the same code path under test.

### Edge cases handled vs. explicitly deferred

**Handled** (per requirement 5):
- Fewer than 4 learnable moves at the target level (Bulbasaur L1 → exactly
  1 move, Tackle) — `BattlePokemon.add_move` already tolerates this with
  no special-casing needed.
- Zero learnable moves at or below the target level — falls back to the
  single lowest-level learnset entry. Confirmed via a full 386-species
  dataset scan that this branch is UNREACHABLE through the public
  `create_battle_pokemon` entry point at any valid level (every species
  has a real level-1 move) — tested directly against the underlying
  `_default_moveset` helper with an artificial sub-1 level instead,
  rather than leaving it unverified.
- Invalid/unimplemented explicit move ID requests — skipped silently
  (`MoveRegistry.get_move()`'s own `push_warning` is the visible signal).
- More than 4 valid move IDs requested — only the first 4 used.
- A duplicate move ID in an explicit request — not added twice.
- Level bounds — clamped to `[1, 100]` with a `push_warning` if the
  caller's request was out of range.
- Invalid/nonexistent dex number — returns `null` (both `build_species`
  and `create_battle_pokemon`), not a bogus zero-stat Pokémon.
- Malformed EV array (wrong size) — ignored, EVs stay at zero.
- An ability slot resolving to ID 0 ("None" — e.g. Rayquaza's empty
  secondary/hidden slots) — leaves `BattlePokemon.ability` at `null`,
  matching the project-wide "ability == null means no ability" convention
  (`AbilityManager.effective_ability_id`'s own null check), deliberately
  NOT resolved to `ability_0000.tres`'s own real "None" placeholder
  Resource.
- Out-of-range `ability_slot` index — leaves `.ability` at `null`, no
  crash.

**Explicitly deferred** (flagged per requirement 5, not silently
skipped — see the new file's own top-of-file doc comment for the full
reasoning):
- Held items — no parameter for one; the task's own parameter list never
  asked for it, and guessing a "reasonable default" would be inventing
  scope. Adding one later is a one-line `ItemRegistry.get_item(id)` call,
  same shape as the ability-loading code already in place.
- Cross-validating an EXPLICIT move request against the species' own
  learnable-move list (`PokemonRegistry.get_learnable_moves(dex)`, which
  returns `"MOVE_TACKLE"`-style constant-name strings). Reconciling that
  naming scheme against `MoveData.move_name`'s own display-string field
  ("Tackle") would need a nontrivial, error-prone reverse name-mapping —
  the same class of complexity `PokemonRegistry._name_to_learnable_key`
  already fights on the species-name side. This factory validates only
  that a requested move ID resolves to a real, IMPLEMENTED `MoveData` —
  it does not check whether the species could actually learn that move in
  the source game.
- Evolution-aware construction — builds exactly the requested
  species/level, nothing more.

### Not wired into the battle screen — flagged, not decided unilaterally

Per requirement 4, M23.1's hardcoded `battle_screen.gd` teams are
completely untouched — this milestone is the converter standalone. Per
the M23 roadmap, connecting real team data to the battle screen is M23.6's
job, once M23.4's team builder exists to actually produce a team; wiring
this converter into the battle screen now, ahead of either, was
considered and NOT done. Flagging explicitly per the task's own
instruction: if Rob wants the battle screen switched over to real
Pokémon sooner than M23.6 (e.g. as an interim step before the team
builder exists), that's a one-line change per team slot
(`PokemonFactory.create_battle_pokemon(dex, level)` in place of the
current `_make_mon(...)` + `add_move(...)` calls in `_build_teams()`) —
but it wasn't done without confirmation first.

### Manual verification

A scratch signal-free direct-call script (created temporarily, deleted
after use), constructing several real species end-to-end and printing
species name/types/base stats/level/max HP/moveset/ability — confirmed by
eye before the formal test suite was written: Charizard L36 correctly
showed `types=[11, 3]` (Fire/Flying), `base_hp=78`, a 4-move auto-derived
learnset (Rage/Scary Face/Flamethrower/Wing Attack, all real Charizard
learnset entries by level 36), and `ability=Blaze`; Bulbasaur L1 correctly
showed exactly 1 move (Tackle); Mewtwo showed the type-dedup fix working
(`types=[15]`, not `[15, 15]`); the invalid-dex and out-of-range-level
cases produced the expected `null`/clamped results with warnings.

### Regression sweep results

- **Before**: 139 files, GRAND TOTAL 13590 (the new suite already present
  in this count — see below for why "before" here means "before the two
  fixture bugs this session's own test-writing caught were fixed," not
  "before the suite existed," since the suite's own first run surfaced
  two real bugs in `pokemon_factory.gd` itself, fixed before any sweep was
  taken — see Deviations below).
- **After**: 139 files, GRAND TOTAL 13590, byte-for-byte identical
  per-file output across two independent sweeps (confirmed via a direct
  diff of both full sweep tables — zero differences anywhere). Matches
  the immediately-prior session's own established baseline exactly:
  13534 (138 files) + 56 (this session's new suite) = 13590.
- `m23_3_converter_test.tscn` itself: stable at 56/56 across 5 separate
  runs (3 standalone reruns plus the 2 full-sweep runs).

**Zero regressions.** This session's changes are additive only: one new
script (`pokemon_factory.gd`), one new test file/scene. No existing
production file (including `battle_manager.gd`, `battle_screen.gd`, and
every other already-shipped script) was touched.

### Deviations / assumptions flagged

- The test suite's own first run caught 2 real bugs in `pokemon_factory
  .gd` before any regression sweep was taken (both fixed, not shipped
  broken): (1) a hand-computed expected EV-boosted stat in the test itself
  was wrong (assumed EVs add linearly AFTER the level-scaling term; they
  actually add INSIDE it, before scaling — `floor((2*base+iv+floor(ev/4))
  *level/100)+5`, not `base_stat + floor(ev/4)` — caught by the test
  itself failing on its first run, fixed by recomputing via Python and
  correcting the assertion, not the factory); (2) a genuine
  `pokemon_factory.gd` bug — `_default_moveset`'s zero-eligible-moves
  fallback branch returned a plain untyped `Array` from a ternary
  expression where the function's own signature requires `Array[int]`,
  crashing at runtime — fixed by building the typed array explicitly.
- Move IDs used in the explicit-moveset test cases were independently
  verified against each move's own `.tres` `move_name` field before
  writing assertions (one initial guess — move ID 63 assumed to be
  Flamethrower — turned out to be Hyper Beam; corrected to the real
  Flamethrower ID, 53, before finalizing the test).
- Nothing committed, per standing instruction.
