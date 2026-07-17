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
