# M21 Recon — Doubles Interaction Cleanup

## Overview

This document is a **retroactive, full re-run** of the M21 recon, written on
2026-07-15 — the same day M21's bundle-safe implementation session already
shipped (see `docs/decisions.md`'s `[M21]` entry and `CLAUDE.md`'s M21 status
bullet). It did not exist before this session: the original M21 recon was
delivered conversationally across several prior chat turns and never written
to disk, so there was no historical file to update. Rather than reconstruct
that missing file from `decisions.md`'s existing M21 write-up or prior chat
summaries (which would risk baking in any unverified claims from those
sources), every finding below was **independently re-derived from
`pokeemerald_expansion` source and the CURRENT project code**, per this
project's standing Step 0 discipline. Where a finding happens to match what
`decisions.md` already says, that is expected and noted as confirmed — not
assumed or copied forward.

**Net result of this re-run: the original M21 inventory was correct, but
incomplete.** Every previously-known item (1–10) is accounted for below,
correctly reconciled against the current (post-bundle-safe-session) code
state. But this re-sweep also surfaced **two new, genuinely more severe
doubles-targeting bugs** that the original recon never caught — one of them
(no status-move spread-targeting dispatch exists at all) is arguably the
single most impactful open item in this whole document, larger in scope than
anything in the original inventory.

## Method

1. Full re-sweep: exhaustive `grep` across `docs/decisions.md`, `CLAUDE.md`,
   every `docs/*recon*.md` file, and production `.gd`/`.py` code comments for
   `doubles-only` / `spread move` / `not modeled` / `flagged` / `deferred`
   phrasing (same method as the original recon). Confirmed no other
   `m21`-named recon doc exists anywhere under `docs/` (`ls docs/ | grep -i
   m21` returns only this new file).
2. Every hit was read in context (not just grepped) and individually
   classified against **current** code state — not the pre-M21-bundle
   state — to catch anything already resolved, anything still open, and
   anything newly stale.
3. Every claim about source behavior was re-derived by reading
   `reference/pokeemerald_expansion` directly (file:line cited throughout),
   not trusted from `decisions.md`'s prose.
4. Two additional targeted investigations were run fresh, per this session's
   own instructions: (a) a full re-grep of `moves_info.h` for every move
   carrying `TARGET_FOES_AND_ALLY`, cross-checked against current
   `gen_moves.py` state one move at a time; (b) a from-scratch re-read of
   Parabolic Charge's real drain-application mechanism.
5. While performing (4a), the cross-check was widened one step further (to
   `TARGET_BOTH`, the sibling "hits both foes, not the ally" target type) as
   a natural byproduct of verifying the `is_spread` flag's true consumption
   path — this is what surfaced the two new findings in this document.

## Full Inventory

### Resolved in the M21 bundle-safe session (2026-07-15)

All seven re-confirmed present and correct in current code (cross-checked
against the live `m21_test.tscn` suite, re-run this session: **33/33
passing**).

| # | Item | Resolution |
|---|------|------------|
| 1 | Shell Bell / Life Orb + Red Card interaction | Both relocated to the tail of `_do_damaging_hit`, gated on `not _red_card_switched_this_move`. `docs/decisions.md` lines 25384–25419. |
| 2 | Shell Bell / Life Orb spread-move accumulation | Spread dispatch now accumulates damage/hits across all targets, heals/recoils once off the total. Also fixed a related pre-existing Life Orb multi-hit over-recoil bug. `docs/decisions.md` lines 25570–25633. |
| 3 | Red Card double-trigger guard | Two distinct flags (`_red_card_activated_this_move` / `_red_card_switched_this_move`), matching source's real two-flag shape rather than Snatch's turn-scoped guard. `docs/decisions.md` lines 25356–25383. |
| 4 | Self-Destruct/Explosion ally-hit | New `MoveData.target_includes_ally`, set on IDs 120/153 only. `docs/decisions.md` lines 25420–25456. **Superseded in scope by the new TARGET_FOES_AND_ALLY full-roster finding below — Self-Destruct/Explosion were only 2 of 20 real source moves carrying this target type.** |
| 7 | TrainerAI `active_index` doubles bug | `choose_replacement`/`_best_switch_target` now check `active_indices.has(i)` instead of the old singular `active_index` comparison. Confirmed via `scripts/battle/ai/trainer_ai.gd` current source: both functions now use the fixed check. `docs/decisions.md` lines 25330–25355. |
| 9 | Snatch vs. Magic Coat/Bounce doubles ordering | Test-only, via a synthetic dual-flagged `MoveData` (confirmed structurally unreachable with real move data — `snatch_affected` and `bounceable` are mutually exclusive across all 717 implemented moves). `docs/decisions.md` lines 25536–25569. |
| 10 | Stale Infiltrator/screens doc comment | `damage_calculator.gd`'s `GetScreensModifier` port comment corrected to describe the real (correct) caller-level bypass architecture. `docs/decisions.md` lines 25634–25646. Doc-only, zero functional change. |

### Excluded per project owner decision (not a gap, a scope-out)

**Item 6 — Guard Dog + Flower Veil ally speed-order tie-break.** Source:
`StatChange_IsFlowerVeilProtected` (`battle_stat_change.c` L678-681) — a
doubles-only guard preventing double-applying an Attack-drop block when a
Grass-type Guard-Dog-holder's own Flower-Veil-holding ally would already
block the drop first. Re-confirmed still unbuilt in current code
(`ability_manager.gd:3090`, comment: *"a narrow doubles-only edge case not
modeled here — flagged, not implemented"*). **Excluded per Rob's explicit
decision** during the M21 bundle-safe session — low value/niche, a
deliberate scope-out, not an oversight (`docs/decisions.md` line 25320).
Still open for a future session if ever reprioritized.

### Deferred to a dedicated turn-order-splice session

**Item 5 — Dragon Darts smart-redirect.** Re-confirmed still unbuilt.
Source has TWO separate trigger mechanisms, not one:
1. Pre-move immunity redirect (`SetPossibleNewSmartTarget`, called from
   `CancelerMultihitMoves`, `battle_move_resolution.c:2293-2304`): if the
   originally-selected target is fully immune/unaffected before the move
   even executes, retarget to the partner (if not also immune).
2. Mid-execution miss redirect (`battle_move_resolution.c:2216-2224`,
   inside the accuracy-canceler loop): if the FIRST hit specifically
   MISSES (an accuracy-roll failure — not "fainted", which isn't a trigger
   at all), redirect the remaining hits.

Both need dynamic mid-loop retargeting inside the shared
`_do_multi_hit_sequence` function. Escalated to Rob via `AskUserQuestion`
mid-session; Rob chose to defer this entirely to its own dedicated session
(`docs/decisions.md` lines 25458–25483).

**Item 8 — Trick Room × Pursuit doubles turn-order integrity: a genuinely
new, significant bug, not just an untested scenario.** Original scope (a
regression test proving the mechanism, per `m16_review_test.gd`'s own
explicit "untested, not built" flag from the M16 Review) was escalated once
Step 0 found something worse: `_turn_order.sort_custom` (`battle_manager.gd`
line 1159, re-confirmed still present in current code) is Godot's own
**unstable sort with no transitivity guarantee**. A same-side speed-tie
scenario with 3+ combatants made the Pursuit-interception test
non-deterministically pass/fail ACROSS RERUNS with byte-identical code and
inputs (confirmed via repeated debug-printed `_turn_order` state).
Escalated to Rob via `AskUserQuestion`; Rob chose to fold this into the same
future turn-order-splice session as item 5 (`docs/decisions.md` lines
25484–25535). **No test shipped for this item** — shipping a test that
"sometimes passes, sometimes fails for reasons unrelated to the code under
test" would misrepresent reliability.

**Item 11 — Round's doubles-only turn-order self-promotion splice.**
Re-verified fresh: `TryUpdateRoundTurnOrder` (`battle_script_commands.c`
L11100-11149) is gated entirely on `IsDoubleBattle()` at its very first
line — a complete no-op in singles. If another Pokémon used Round
successfully earlier the same turn, the Round-using battler moving next
gets spliced to act immediately after it. Confirmed still unbuilt in
current code (`move_data.gd:3520-3532`): only the power-doubling half is
built (`_last_landed_move_anyone`-driven); the turn-order splice itself is
a disclosed, unbuilt gap, correctly noted as not affecting singles-only
correctness. Only reachable/relevant in doubles.

**Item 12 — Shell Trap's doubles-only turn-order splice.** Re-verified
fresh: `MoveEndShellTrap` (`battle_move_resolution.c` L3660-3678) sets
`gProtectStructs[battlerDef].shellTrap = TRUE` on a landed physical hit,
then — `if (IsDoubleBattle())` — calls `ChangeOrderTargetAfterAttacker()`
(the SAME turn-order-splice primitive Pursuit's own interception already
uses internally) to move the Shell-Trap holder to act immediately after its
attacker, rather than waiting for its own priority -3 slot. Confirmed still
unbuilt in current code (`move_data.gd:3499-3518`): the reactive arming
itself is fully implemented, but the doubles-only splice is explicitly
disclosed as not built (singles-only correctness is unaffected by
construction — there's only one other actor to have already resolved by
the time Shell Trap's own -3 slot arrives in singles).

**Item 13 — Quash's doubles-only speed-preserving reorder.** Re-verified
fresh against `BS_TryQuash` (`battle_script_commands.c` L11762-11799): at
`B_QUASH_TURN_ORDER >= GEN_8` (confirmed this project's actual active
branch — `B_QUASH_TURN_ORDER = GEN_LATEST`,
`include/config/battle.h:140`), when 3+ battlers remain to act, source
performs an incremental speed-order-preserving swap among the remaining
Quash targets rather than a flat "move to absolute end." This project's
current implementation (`move_data.gd:2102-2112`) always moves the target
to the absolute end of `_turn_order` — a disclosed simplification,
observably identical to source's own real behavior in singles (only one
other battler total) and to source's own pre-Gen-8 branch, but NOT
identical to the true Gen-8+ behavior in a 3+-battler doubles scenario with
multiple Quash uses queued in the same turn.

These three (11, 12, 13) share a common shape — each is a small,
self-contained doubles-only turn-order splice that reuses or resembles
mechanisms this project already has in some form (Pursuit's own
interception, the existing `_turn_order`/`_current_actor_index` machinery)
but doesn't yet generalize into a reusable primitive. Bundling them with
items 5 and 8 into one dedicated turn-order-splice session (rather than
scattering them across future bundle-safe sessions) is recommended,
since a session that's already elbow-deep in `_turn_order` mechanics for
items 5/8 is the natural place to also close 11/12/13.

### Newly discovered this session — genuinely more severe than anything above

**NEW ITEM A — 9 already-implemented damage-category moves are missing the
`is_spread` flag entirely**, meaning they currently behave as single-target
moves in doubles despite being real spread moves in source. Found as a
byproduct of re-deriving the `TARGET_FOES_AND_ALLY` list fresh (below):
Surf and Earthquake — two of the most iconic, commonly-used spread moves
in the actual games — both show `is_spread: False` (absent from both
`gen_moves.py`'s dict and the live `.tres` file; confirmed via direct
`cat data/moves/move_0057.tres` / `move_0089.tres`). Widening the check to
source's full 58-entry `TARGET_BOTH` list (the sibling "hits both foes,
not the ally" target type) surfaced 7 more:

| Move | ID | Real target |
|------|-----|--------------|
| Surf | 57 | `TARGET_FOES_AND_ALLY` (config-gated `B_UPDATED_MOVE_DATA>=GEN_4`, true here) |
| Earthquake | 89 | `TARGET_FOES_AND_ALLY` |
| Razor Wind | 13 | `TARGET_BOTH` |
| Swift | 129 | `TARGET_BOTH` |
| Rock Slide | 157 | `TARGET_BOTH` |
| Eruption | 284 | `TARGET_BOTH` |
| Water Spout | 323 | `TARGET_BOTH` |
| Shell Trap | 658 | `TARGET_BOTH` (`moves_info.h:17438`) |
| Dragon Energy | 748 | `TARGET_BOTH` |

All 9 are damage-category (power > 0), meaning the FIX for each is
mechanically simple — the existing spread-damage dispatch branch
(`_phase_move_execution`'s `if move.is_spread and _active_per_side > 1:`,
`battle_manager.gd:3313`) already correctly handles everything once the
flag is set. Surf/Earthquake additionally need `target_includes_ally` once
that mechanism is retrofitted (see NEW ITEM C below) since they're
`TARGET_FOES_AND_ALLY`, not plain `TARGET_BOTH`. This is the exact same
"mechanically trivial per-move, but changes doubles behavior possibly
covered by existing single-target-assuming tests" caution shape already
established for item 4's own follow-up sweep — bundle these together with
that sweep rather than treating them as two separate audits.

**NEW ITEM B — no status-move spread-targeting dispatch exists ANYWHERE in
this project.** This is the most significant finding of this whole
re-run. Confirmed via a full grep of every `_active_per_side` use in
`battle_manager.gd`: **exactly one** per-target opposing-side dispatch loop
exists in the entire file (`battle_manager.gd:3313-3313+`), and it sits
strictly inside the "Damaging move" section of `_phase_move_execution` —
reached only when `move.power > 0`. Every pure status/stat-change move
(power = 0) returns from an earlier branch in the same function
(`battle_manager.gd:3301-3306`) before that spread-dispatch code is ever
reached. The consequence: **`is_spread`'s value is never even read for a
status move, regardless of what it's set to.**

Cross-checking source's own `TARGET_BOTH` list against implemented status
moves found:
- **Tail Whip (39), Leer (43), Growl (45)** — `is_spread: False` in current
  data. Missing the flag AND the (nonexistent) dispatch.
- **String Shot (81), Sweet Scent (230), Venom Drench (599)** — `is_spread:
  True` in current data, but the flag is **completely inert** for these
  three, since nothing in `_phase_move_execution` ever reads `is_spread`
  for a status-category move. These three currently behave identically to
  Tail Whip/Leer/Growl in a doubles battle (single-target only) despite
  having the "correct" flag value already set — a data-looks-right,
  behavior-is-wrong trap.

All six are real, already-shipped moves whose flavor text and Bulbapedia
description explicitly say "lowers the Sp. Atk of both opposing Pokémon"
(or equivalent) — this is not an edge case, it's the move's whole point in
a doubles context, currently silently broken. Fixing this needs genuinely
NEW infrastructure: a status-move-spread dispatch loop analogous to (but
structurally separate from, since there's no damage/spread-reduction
modifier involved) the existing damage-spread branch, applying
`_apply_stat_change_effect`/`_apply_one_stat_change_pair` once per live
opposing combatant instead of once against the single resolved `defender`.
This is a strictly bigger lift than NEW ITEM A (a data fix) or the
TARGET_FOES_AND_ALLY sweep below (also mostly a data fix) — it needs a new
code path, plus a design decision about how it interacts with
Substitute/type-immunity/Magic Bounce/Prankster-vs-Dark checks per-target
rather than once.

Given the severity (multiple already-shipped moves silently not doing
their documented job in doubles) and the size (new dispatch
infrastructure, not a flag flip), this should be treated as its own
dedicated session — likely higher priority than items 11-13's turn-order
splices, since those are edge cases within an already-working mechanism,
while this is a complete absence of a mechanism for an entire move
category.

**NEW ITEM C — the `TARGET_FOES_AND_ALLY` full-roster ally-hit gap
(item 4's own follow-up), re-confirmed fresh.** Re-derived independently
via a full grep of `moves_info.h` for `.target = TARGET_FOES_AND_ALLY`
(20 total hits, not just recalled from the prior count):

Surf, Earthquake, Self-Destruct, Explosion, Magnitude, Teeter Dance,
Discharge, Lava Plume, Sludge Wave, Synchronoise, Bulldoze, Searing Shot,
Parabolic Charge, Petal Blizzard, Boomburst, Sparkling Aria, Brutal Swing,
Mind Blown, Misty Explosion, Corrosive Gas.

Self-Destruct(120)/Explosion(153) are the 2 already fixed by M21 (`item 4`
above). Of the remaining 18:

- **14 already implemented**, confirmed via fresh `gen_moves.py`
  cross-check, all currently `is_spread: True, target_includes_ally:
  False` — Magnitude, Discharge, Lava Plume, Sludge Wave, Bulldoze,
  Searing Shot, Parabolic Charge, Petal Blizzard, Boomburst, Sparkling
  Aria, Brutal Swing (11 of these are clean flag-only fixes), **plus Surf
  and Earthquake**, which — per NEW ITEM A above — are missing `is_spread`
  itself too, so they need BOTH fixes together, not just the ally-hit
  half. (14 = 11 + Surf + Earthquake + Teeter Dance, which is a STATUS
  move — see below.)
- **Teeter Dance (298)** is a genuine STATUS-category member of this same
  `TARGET_FOES_AND_ALLY` list (confirmed `category` field), meaning its
  own gap is actually a special case of NEW ITEM B (no status-move spread
  dispatch exists), not a simple `target_includes_ally` flag addition —
  flagging this cross-reference explicitly so a future session doesn't
  "fix" Teeter Dance the same shallow way as the 11 damage moves and
  wonder why it still doesn't hit the ally.
- **4 not yet implemented**, unaffected by any current gap, to build
  correctly whenever eventually implemented: Synchronoise, Mind Blown,
  Misty Explosion, Corrosive Gas.

**Damage-modifier de-risking note, re-confirmed fresh (not just asserted):**
`GetTargetDamageModifier` (`battle_util.c` L7220-7230) returns the
identical flat `UQ_4_12(0.75)` for both the 2-target and 3-target spread
case at this project's `B_MULTIPLE_TARGETS_DMG>=GEN_4` config — re-derived
directly from source this session, not copied from the prior finding. This
means extending the target SET to include the ally needs no new damage
modifier value, only the target-set extension itself — the fix genuinely
is "mechanically trivial," as previously stated, at least for the 11 pure
damage-only moves in the list above.

**Why still deferred, not silently bundled in:** the fix is mechanically
trivial per move (one flag, regenerate `.tres`), but it's a real behavior
change to up to 16 already-implemented moves (14 above, plus once NEW
ITEM A's Surf/Earthquake data fix lands) whose existing test suites may
specifically assert "only the opponents take damage, the ally is
untouched" as a passing case today — this needs its own test-audit-first
pass (confirm what each move's existing suite currently asserts about its
ally, fix any now-stale assertions, THEN flip the flags), not a silent
bundle-in in an unrelated session. Filed as the LAST item in this
recon's open-scope list per the task's own instruction, since it's lower
priority than the turn-order-splice trio (items 11-13) and the two more
severe newly-discovered items (A, B) above — even though, chronologically,
this was the starting point that led to discovering A and B.

**Parabolic Charge drain-rounding — re-confirmed fresh, genuinely a
non-issue, with a nuance beyond the original recon's own scope.**
Re-derived from scratch: Parabolic Charge is `EFFECT_ABSORB` with
`.argument.absorbPercentage = 50` (`moves_info.h:15146-15152`), sharing the
exact same source dispatch as Absorb/Mega Drain/Giga Drain/Drain
Punch/etc. `MoveEndAbsorb`'s `EFFECT_ABSORB` case
(`battle_move_resolution.c:2635-2643`) computes
`healAmount = (moveDamage[battlerDef] * GetMoveAbsorbPercentage(move) /
100)` **per target, applied immediately via `SetHealScript`/`SetHealAmount`
for that one target** — `SetHealAmount` (`include/battle.h:1182-1187`)
OVERWRITES `passiveHpUpdate[battler]` (assignment, not `+=`), and the heal
is realized via an immediate `BattleScriptCall`, not accumulated the way
Shell Bell's `savedDmg` genuinely is. **This means source's own absorb-
family drain is computed and applied per-hit, independently per target —
the exact same shape this project's own `drain_percent` mechanism already
uses** (`battle_manager.gd:9083-9084`: `damage * move.drain_percent / 100`,
applied inside `_do_damaging_hit`, called once per target in the spread
loop). Both the formula (integer floor-division truncation) and the
per-hit-not-accumulated application timing match exactly — **confirmed, no
divergence exists, in either direction.**

The nuance beyond the original recon's scope: this ALSO means the
Shell-Bell-style "accumulate across all spread targets, then apply once"
fix pattern (item 2) must NOT be applied to Parabolic Charge or any other
absorb-family move if/when NEW ITEM A/C's ally-hit or is_spread fixes ever
reach it — the correct behavior for drain is genuinely per-hit, and
attempting to "fix" it the same way Shell Bell was fixed would introduce a
new bug, not close one. Flagging this explicitly so a future session
doesn't over-generalize item 2's pattern.

### Reconfirmed still open, lower priority (not previously itemized 1-13, but caught by the re-sweep)

**Lightning Rod / Storm Drain's attacker-ally redirect (`B_REDIRECT_ABILITY_ALLIES`) —
still not modeled.** Re-confirmed via `ability_manager.gd:2642-2658`
(comment still present, unchanged): source's `B_REDIRECT_ABILITY_ALLIES >=
GEN_4` quirk additionally lets Lightning Rod/Storm Drain redirect a move
used by the ATTACKER's OWN ally onto that ally — this project only models
redirect onto the ORIGINAL TARGET's ally (the overwhelmingly common real
scenario). A known, narrower gap, consistent with this project's
established defender/defender_ally-pair convention rather than a full
N-battler search. Not part of the original M21 numbered inventory; kept
here as a minor, low-priority open item rather than promoted into the
main numbered list, since it's a rare edge case (an attacker deliberately
redirecting a move onto its OWN ally) rather than a commonly-hit gap.

### Stale documentation found during this re-sweep (not functional gaps)

Three doc-hygiene issues were found — none affect behavior, but are worth
correcting opportunistically since they actively mislead a future reader
about which gaps are still open:

1. **`item_manager.gd`'s `shell_bell_heal` doc comment** (lines ~2029-2049)
   still reads *"NOT modeled, flagged not built (both genuine doubles-only
   edge cases... matching M18n's own flagged Red Card doubles gap)"* for
   exactly the two conditions M21's items 1 and 2 fixed. The fix lives at
   the `BattleManager` call-site level (relocating dispatch, adding the
   `_red_card_switched_this_move` gate, restructuring the spread-dispatch
   loop) — this pure calculation function itself never needed to change,
   so its own doc comment was never touched and is now stale.
2. **`gen_moves.py`'s Self-Destruct(120) entry comment** (lines ~2808-2813)
   retains its pre-M21 first sentence (*"the ally-hit half in doubles is a
   flagged, not-built gap"*) directly above a newer `[M21]` annotation
   confirming `target_includes_ally` was added — self-contradictory when
   read in isolation, though the `[M21]` annotation does correct it in
   context. Minor.
3. **`CLAUDE.md`'s "Post-M18 Review" section, items 3 and 4** (around line
   937-938) still read *"remain open, deferred to M22"* — these are the
   exact same two gaps as M21's items 1 and 2, both now fixed. This is the
   most visible of the three staleness issues, since `CLAUDE.md` is the
   first file read at the start of every session.

None of these were fixed in this recon session (docs-only recon, no
implementation authorized) — flagged here for a future opportunistic
cleanup pass, most naturally the same session that tackles NEW ITEM A/B/C
above, since that session will already be touching these exact areas.

## Triage / Sequencing for Remaining Open Items

Ordered by recommended priority, not by item number:

1. **NEW ITEM B (no status-move spread dispatch exists)** — highest
   priority. Several already-shipped moves (Tail Whip/Leer/Growl/String
   Shot/Sweet Scent/Venom Drench, plus Teeter Dance's own cross-reference
   from NEW ITEM C) are silently not doing their documented job in
   doubles. Needs new dispatch infrastructure, not just a flag fix.
2. **NEW ITEM A (9 damage moves missing `is_spread` entirely)** — high
   priority, mechanically simple once test coverage is confirmed. Surf and
   Earthquake in particular are extremely commonly-used moves.
3. **Items 5 + 8 + 11 + 12 + 13 (turn-order-splice family)** — bundle into
   one dedicated session, per the original recon's own sequencing
   decision, reconfirmed still valid. All five touch `_turn_order`/
   `_current_actor_index` machinery in doubles-only scenarios.
4. **NEW ITEM C (TARGET_FOES_AND_ALLY 18-move ally-hit sweep, including
   Teeter Dance's cross-reference to item B)** — lower priority, needs a
   test-audit-first pass before flipping flags. File last, per this
   session's own instruction.
5. **Lightning Rod/Storm Drain attacker-ally redirect** — lowest priority,
   a rare edge case, not part of the original numbered inventory.
6. **Stale documentation (3 items)** — opportunistic, zero functional
   urgency, bundle into whichever session above touches the same files
   first.

## Explicitly Out of Scope

- **Item 6 (Guard Dog + Flower Veil ally tie-break)** — excluded per Rob's
  own decision, not a technical blocker. Would need its own session to
  reconsider, not a recon action.
- **M22 (Doubles Battle Support) planning generally** — this document is
  scoped to M21's own doubles-interaction-cleanup inventory (bugs/gaps in
  already-shipped doubles-adjacent mechanics), not a fresh ground-up
  Doubles Battle Support milestone plan. Some items here (the turn-order
  splices, the status-spread gap) may end up folded into M22 depending on
  Rob's own sequencing preference when that milestone is eventually
  scoped — not decided here.
- **Any further widening of the `TARGET_BOTH`/`TARGET_FOES_AND_ALLY` cross-
  check beyond what's cited above** — the widened check in this session
  was itself a byproduct of verifying item 4's own follow-up list, not an
  exhaustive audit of every spread-eligible move in the game. A handful of
  `TARGET_BOTH` moves in source are not yet implemented in this project at
  all (Heal Block, Captivate, Dark Void, Thousand Arrows, Thousand Waves,
  Core Enforcer, Make It Rain, Clangorous Soulblaze) — these carry no
  current gap since they don't exist yet, and are out of this document's
  scope (they belong to M19's own already-closed residual-move ledger, not
  M21's doubles-cleanup scope).

## Change Log

- **2026-07-15**: This file created retroactively, after M21's bundle-safe
  implementation session had already shipped (per `docs/decisions.md`'s
  `[M21]` entry and `CLAUDE.md`'s M21 status bullet, both dated the same
  day). Full recon re-run from scratch per explicit instruction — no
  reconstruction from `decisions.md`/prior chat summaries. Recon-only, no
  implementation in this session; `docs/decisions.md` and `CLAUDE.md` were
  NOT modified by this session (their existing M21 entries/status bullets
  are unchanged and remain the authoritative record of what the
  bundle-safe session itself shipped).
