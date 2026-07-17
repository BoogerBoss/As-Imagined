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
