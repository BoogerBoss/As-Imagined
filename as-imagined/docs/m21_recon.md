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

### Stale documentation found during this re-sweep (not functional gaps) — RESOLVED 2026-07-15

Three doc-hygiene issues were found — none affected behavior, but were
worth correcting opportunistically since they actively misled a future
reader about which gaps were still open. **All three were fixed in a
follow-up session the same day this recon was written**, verified fresh
against current code state before editing (not pasted verbatim from this
recon's own wording):

1. **`item_manager.gd`'s `shell_bell_heal` doc comment** (was lines
   ~2029-2049) used to read *"NOT modeled, flagged not built (both genuine
   doubles-only edge cases... matching M18n's own flagged Red Card doubles
   gap)"* for exactly the two conditions M21's items 1 and 2 fixed. Fixed:
   updated to describe both gaps as resolved at the `BattleManager`
   call-site level (`_red_card_switched_this_move` gate at every call
   site; spread dispatch accumulates total damage/hits and calls this
   function once) — this pure calculation function itself is unchanged
   and was always correct.
2. **`gen_moves.py`'s Self-Destruct(120) entry comment** (was lines
   ~2808-2813) retained its pre-M21 first sentence (*"the ally-hit half in
   doubles is a flagged, not-built gap"*) directly above the newer `[M21]`
   annotation that already corrected it. Fixed: stale sentence removed,
   `[M21]` annotation kept.
3. **`CLAUDE.md`'s "Post-M18 Review" section, items 3 and 4** (was lines
   ~937-938) used to read *"remain open, deferred to M22."* Fixed: both
   marked `~~COMPLETE~~`, citing `[M21]` items 1/2 directly, matching the
   strikethrough convention items 1/2/5/6 in that same section already
   use. The section's own intro paragraph and the M18-status summary line
   above it were updated to match (all six Post-M18 Review items now
   resolved, not four of six).

## Triage / Sequencing for Remaining Open Items

Ordered by recommended priority, not by item number:

1. **NEW ITEM B (no status-move spread dispatch exists)** — **COMPLETE**,
   2026-07-15, same day, in a same-day follow-up session. Real final scope
   was **8 moves, not 9**: Tail Whip(39)/Leer(43)/Growl(45) (gained
   `is_spread=True`, were missing it entirely), String Shot(81)/Cotton
   Spore(178)/Poison Gas(139)/Sweet Scent(230) (already had
   `is_spread=True`, now finally live), and Teeter Dance(298) (gained
   `target_includes_ally=True`). **Venom Drench(599) needed ZERO
   changes** — a real correction found only via the fix session's own
   first test run: Venom Drench has its own pre-existing `is_venom_drench`
   dispatch branch that already loops `_get_live_opponents(attacker)`
   directly, confirmed to already return every live opponent regardless of
   `_active_per_side` — it was ALREADY correctly hitting both opponents in
   doubles before this session, via a completely separate mechanism; its
   `is_spread=True` flag was genuinely vestigial for its own dispatch, not
   evidence of a shared bug with the other 8. New
   `BattleManager._apply_status_move_to_target()` (per-target Magic
   Bounce/Coat → Substitute → type-immunity → Prankster-vs-Dark → effect),
   called once per live opposing combatant (+ally) from a new early branch
   gated on `foe_targeting and move.is_spread and _active_per_side > 1 and
   not move.is_venom_drench`. New `scenes/battle/new_item_b_test.gd`/
   `.tscn`: 29/29 assertions. See `docs/decisions.md`'s `[NEW ITEM B]`
   entry for the full Step 0 citations and both fixed bugs (the Venom
   Drench interception, a production bug; and a singles negative control's
   own whole-battle-aggregation instance, a test bug).
2. **NEW ITEM A (9 damage moves missing `is_spread` entirely)** —
   **COMPLETE**, 2026-07-15, same day, in a same-day follow-up session.
   All 9 confirmed clean flag-only fixes (Shell Trap falls through to
   ordinary dispatch once armed; Eruption/Water Spout/Dragon Energy's
   HP-scaled power computed once before the spread/single split; Razor
   Wind's charge turn is target-agnostic). Surf(57)/Earthquake(89)
   deliberately do NOT gain `target_includes_ally` — that stays deferred
   to NEW ITEM C, proven explicitly (not just assumed) via a dedicated
   test showing they now hit both opponents but not the ally. **A real,
   significant, but PRE-EXISTING architectural finding surfaced during
   Step 0**: this project's accuracy roll is checked exactly once,
   against the single default target, for EVERY damaging move already
   shipped — not independently per spread target as source does. This
   affects all ~37 already-"OK" spread damage moves too, not just
   Swift/Rock Slide — flagged as a new, high-value item for a future
   dedicated session (see the Triage note below), but didn't block this
   session since it's inherited, unworsened behavior. New
   `scenes/battle/new_item_a_test.gd`/`.tscn`: 31/31 assertions. See
   `docs/decisions.md`'s `[NEW ITEM A]` entry for full Step 0 citations.
3. **NEW ITEM D (severity CORRECTED/RAISED, 2026-07-16 scoping session —
   see the dedicated section above): spread damage moves share ONE
   accuracy roll across all targets, instead of each target getting its
   own independent roll — CONFIRMED via source (not assumed) to be a
   genuine divergence, not a simplification source also makes.**
   `CancelerAccuracyCheck` (`battle_move_resolution.c:2174-2260`) and the
   target-validity canceler (`battle_move_resolution.c:1960-2010`) both
   loop and check accuracy/semi-invulnerability INDEPENDENTLY per target
   in real source — this project's own single shared
   `StatusManager.check_accuracy` call (`battle_manager.gd:2658`) is a
   confirmed gap, not shared upstream behavior. Affects **59 currently-
   implemented spread damage moves** (exact count, queried directly — not
   the "~37" originally estimated). Neither `check_accuracy` nor
   `_can_hit_semi_invulnerable` need logic changes (both already
   per-target-capable); the gap is purely a call-site scoping issue, but
   real surrounding bookkeeping (`move_missed`'s per-move-not-per-target
   signal shape, `crashes_on_miss`'s unresolved partial-spread-miss
   semantics, Blunder Policy's own per-target trigger point) needs its
   own design pass first. **Flagged explicitly per this session's own
   instruction — no firm priority assigned; awaiting Rob's input on
   whether this becomes its own dedicated session, folds into the
   turn-order-splice session (only a soft/thematic connection via Dragon
   Darts), or is deprioritized.** See the dedicated "NEW ITEM D" section
   above and `docs/decisions.md`'s `[NEW ITEM D scoping]` entry for the
   full citation trail.
4. **Items 5 + 8 + 11 + 12 + 13 (turn-order-splice family)** — bundle into
   one dedicated session, per the original recon's own sequencing
   decision, reconfirmed still valid. All five touch `_turn_order`/
   `_current_actor_index` machinery in doubles-only scenarios.
5. **Acupressure's ally-choice gap (newly found in the full-roster
   audit)** — a genuinely different, self-contained gap (a missing target
   CHOICE, not a missing flag or dispatch). Low urgency (one move, no
   other move shares this exact `TARGET_USER_OR_ALLY` shape), but flagged
   here as its own item since it doesn't fit cleanly into A/B/C above.
6. **NEW ITEM C (TARGET_FOES_AND_ALLY full-roster ally-hit sweep)** —
   **COMPLETE**, 2026-07-16. Fresh Step 0 re-derivation (not copied from
   this recon's own earlier count) confirmed the corrected worklist: 13
   moves needed `target_includes_ally` (Magnitude, Discharge, Lava
   Plume, Sludge Wave, Bulldoze, Searing Shot, Parabolic Charge, Petal
   Blizzard, Boomburst, Sparkling Aria, Brutal Swing, plus Surf/
   Earthquake — the latter two closing the gap NEW ITEM A had
   deliberately left open), 3 were already fully correct (Self-Destruct/
   Explosion/Teeter Dance, verified not assumed), 4 remain unimplemented.
   A real, specifically-checked interaction (not assumed safe):
   `AbilityManager.pressure_pp_cost` structurally cannot count the ally
   (its own loop only ever scans the opposing side), confirmed via
   source that Pressure's PP surcharge is genuinely opponent-only by
   design even for a `TARGET_FOES_AND_ALLY` move — `m17n10_test.gd`'s own
   Magnitude-vs-Pressure doubles test reconfirmed unaffected. Parabolic
   Charge's drain reconfirmed genuinely per-hit, explicitly NOT
   converted to the Shell-Bell accumulate-then-heal-once pattern. **Also
   found and fixed a real, expected regression in this arc's own
   `new_item_a_test.gd`**: its own A.10/A.11/H.03/I.03 had explicitly
   asserted Surf/Earthquake's OLD "ally not yet hit" boundary — updated
   in place to assert the new correct behavior. New
   `scenes/battle/new_item_c_test.gd`/`.tscn`: 30/30 assertions. See
   `docs/decisions.md`'s `[NEW ITEM C]` entry for full Step 0 citations.
   **This closes the full NEW ITEM A/B/C arc** — both halves (`is_spread`
   from NEW ITEM A, `target_includes_ally` from this session) are now
   done for Surf/Earthquake, and all 13 previously-open moves are fully
   correct.
7. **Lightning Rod/Storm Drain attacker-ally redirect** — lowest priority,
   a rare edge case, not part of the original numbered inventory.
8. **Stale documentation (3 items)** — **RESOLVED** in the same follow-up
   session that added the full-roster audit below; see that subsection's
   own updated status.

### Does the full-roster audit change this sequencing?

**No — it confirms the existing order, while growing NEW ITEM B's own
scope.** The audit's only sequencing-relevant finding is that NEW ITEM B
(no status-move spread dispatch) affects 9 moves, not 6 — Cotton Spore(178)
and Poison Gas(139) were not part of the original NEW ITEM A/B/C
investigation, and Growl/Leer/Tail Whip's own `is_spread=False` (rather
than merely "not yet checked") is now directly confirmed rather than
inferred. This makes item B's priority MORE justified, not less — it was
already ranked first, and the audit found more affected moves, not fewer.
Item A's 9-move list is confirmed complete and unchanged. Item C's 18-move
list (2 already fixed, 13 with a clean fix path, 1 [Teeter Dance] blocked
on item B, 4 not implemented) is likewise confirmed complete. The one
genuinely new addition to the sequencing — Acupressure's ally-choice gap —
is small enough (one move, no shared mechanism with anything else in this
document) that it doesn't warrant reordering anything; it's slotted in as
its own low-urgency item rather than merged into A, B, or C, since its
fix shape (a target-choice mechanism) doesn't match any of theirs.

## Full-Roster Spread/Status-Target Audit

Added 2026-07-15, same day, in a follow-up session — recon only, no
implementation. This supersedes and widens the `TARGET_BOTH`/
`TARGET_FOES_AND_ALLY` check already partially done above (NEW ITEM A/B/C)
into a single, complete, source-verified map of every move whose real
target type has ANY multi-Pokémon or ally-inclusion implication, across
both damage and status categories — not just the subset checked while
verifying item 4's own follow-up list.

### Method

`moves_info.h` was parsed programmatically (not re-grepped by hand) into a
move-name → raw `.target` expression table for all 935 entries (934 real
moves + the `MOVE_NONE` placeholder), with every `B_UPDATED_MOVE_DATA`/
`B_UPDATED_MOVE_FLAGS`-gated ternary resolved to its true branch at this
project's actual config (`B_UPDATED_MOVE_DATA = B_UPDATED_MOVE_FLAGS =
GEN_LATEST`, confirmed fresh via `include/config/battle.h:66,68` — not
assumed). The resulting distribution, source-verified in full:

| Target type | Count | In scope for this audit? |
|---|---|---|
| `TARGET_SELECTED` | 690 | No — ordinary single-target, no multi/ally implication |
| `TARGET_USER` | 110 | No — self-only, no multi/ally implication |
| `TARGET_BOTH` | 60 | **Yes** |
| `TARGET_FOES_AND_ALLY` | 20 | **Yes** |
| `TARGET_FIELD` | 20 | No — field-wide effects (weather/Trick Room/etc.), not a specific-Pokémon target |
| `TARGET_DEPENDS` | 11 | **Yes** (resolves dynamically; checked individually, not guessed) |
| `TARGET_RANDOM` | 5 | No — picks one random single opponent, no multi/ally implication |
| `TARGET_ALLY` | 5 | **Yes** |
| `TARGET_OPPONENTS_FIELD` | 4 | No — hazard/side-wide effects, not a specific-Pokémon target |
| `TARGET_ALL_BATTLERS` | 4 | **Yes** |
| `TARGET_USER_AND_ALLY` | 3 | **Yes** |
| `TARGET_USER_OR_ALLY` | 1 | **Yes** |
| `TARGET_OPPONENT` | 1 | **Yes** |
| `TARGET_SMART` | 1 | **Yes** (already item 5, Dragon Darts) |

Total distinct move entries confirmed: 690+110+60+20+20+11+5+5+4+4+3+1+1+1
= 935, exactly matching the parsed entry count — confirms the parse is
complete with no double-counted or dropped entries.

**106 moves** (60+20+11+5+4+3+1+1) fall into the "in scope" rows above.
Every one was individually cross-checked against `gen_moves.py`'s current
implementation state (`is_spread`, `target_includes_ally`, category, and —
critically — whether `battle_manager.gd`'s dispatch code would actually
*read* those flags for a move of that category at all, per NEW ITEM B's
own finding that a flag can be set correctly yet be completely inert).

Per this session's own scope instruction: **only moves already implemented
in this project's 717-move roster were investigated in depth.**
Not-yet-implemented moves sharing an interesting target type are named
only, with zero further investigation, so a future implementation session
gets the targeting right from the start rather than this audit spending
budget speccing unbuilt moves.

### Summary table

| Category | Count | Notes |
|---|---|---|
| **Total in-scope moves (all 8 relevant target types)** | 106 | |
| Not yet implemented (name-only, no further investigation) | 25 | See per-category breakdown below |
| **Implemented, fully correct (no gap)** | 45 (corrected from 44 — see below) | 39 from `TARGET_BOTH`/`TARGET_FOES_AND_ALLY` + Helping Hand/Aromatic Mist/Coaching/Howl/Perish Song (5) + Venom Drench (1, corrected — see below) |
| **Structural gap — dispatch unreachable for this move's category (NEW ITEM B)** | 8 (corrected from 9 — **COMPLETE**, see Triage section) | STATUS-category `TARGET_BOTH`/`TARGET_FOES_AND_ALLY` moves whose ONLY path was the now-fixed generic dispatch. Venom Drench(599) was originally counted here but corrected out: it has its own pre-existing `is_venom_drench` branch that already loops all live opponents independently of `is_spread` — it was never actually broken, just carrying a vestigial flag. See `docs/decisions.md`'s `[NEW ITEM B]` entry. |
| **Data-only fix — `is_spread` missing entirely, damage-category (NEW ITEM A)** | 9 — **COMPLETE**, 2026-07-15 | 7 `TARGET_BOTH`-only + 2 (Surf, Earthquake) that ALSO need the ally-inclusion fix below |
| **Ally-inclusion mismatch — `is_spread` already correct, `target_includes_ally` missing (NEW ITEM C)** | 13 — **COMPLETE**, 2026-07-16 | 11 `TARGET_BOTH`/no-is_spread-issue + Surf + Earthquake (the same 2 moves counted in the row above, needing both fixes together) |
| **Newly found, distinct gap: Acupressure's ally-choice not modeled** | 1 | See below — a genuinely new, self-contained finding |
| **`TARGET_DEPENDS` — structurally sound by construction** | 10 implemented / 1 not | See below — no gap found |
| **`TARGET_OPPONENT` (Me First) — no gap found** | 1 | Already correctly implemented |
| **`TARGET_SMART` (Dragon Darts) — already item 5** | 1 | Cross-referenced, not re-litigated |

(44 + 9 + 9 + 1[Acupressure] + 10 + 1 + 1 = 75 implemented moves accounted
for across all 8 target types, + 25 not-yet-implemented + the 2 Surf/
Earthquake double-counted between the two "9" rows already reconciled
above via row notes = 106 total in-scope moves, confirmed by direct
addition: 106 − 25 = 81 implemented; 81 = 39 + 2(Explosion/Self-Destruct
folded into the 39) ... see the itemized breakdown immediately below for
the exact non-overlapping tally, since the summary table's row counts
double-list Surf/Earthquake by design for readability.)

**Exact non-overlapping implemented-move tally** (each move counted once):
39 (correct) + 9 (structural/status) + 7 (is_spread-only fix) + 2 (Surf/
Earthquake, both-fixes) + 11 (ally-inclusion-only fix) + 1 (Acupressure) +
10 (`TARGET_DEPENDS`, sound) + 1 (Me First, sound) = **80 implemented
moves** audited in depth, + **25 not-yet-implemented** named for future
reference (1 `TARGET_SMART` entry, Dragon Darts, is implemented but
already tracked as item 5, not re-counted here) = **106 total**, confirmed
against the summary table above (106 − 25 − 1[Dragon Darts, tracked
separately] = 80).

### `TARGET_BOTH` (60 total — 51 implemented, 9 not implemented)

**Implemented, dispatch-reachable, flag correct — no gap (37):** Acid(51),
Air Cutter(314), Astral Barrage(753), Bleakwind Storm(774), Blizzard(59),
Breaking Swipe(712), Bubble(145), Burning Jealousy(735), Clanging
Scales(654), Dazzling Gleam(605), Diamond Storm(591), Disarming
Voice(574), Electroweb(527), Fiery Wrath(750), Glacial Lance(752),
Glaciate(549), Heat Wave(257), Hyper Voice(304), Icy Wind(196),
Incinerate(510), Lands Wrath(616), Matcha Gotcha(830), Mortal Spin(794),
Muddy Water(330), Origin Pulse(618), Overdrive(714), Powder Snow(181),
Precipice Blades(619), Razor Leaf(75), Relic Song(547), Sandsear
Storm(776), Snarl(555), Splishy Splash(677), Springtide Storm(759),
Struggle Bug(522), Twister(239), Wildbolt Storm(775).

**Implemented, damage-category, `is_spread` MISSING entirely — data-only
fix (NEW ITEM A, 7):** Dragon Energy(748), Eruption(284), Razor Wind(13),
Rock Slide(157), Shell Trap(658), Swift(129), Water Spout(323). All
verified via direct `.tres`/`gen_moves.py` cross-check — none carry
`is_spread` at all, meaning each currently behaves as single-target in
doubles despite being a real spread move in source.

**Implemented, STATUS-category, dispatch UNREACHABLE regardless of flag
value — structural gap (NEW ITEM B, 7 confirmed + 1 corrected out, see
below):** Cotton Spore(178, `is_spread` already `True` but inert),
Growl(45, `is_spread=False`), Leer(43, `is_spread=False`), Poison
Gas(139, `True` but inert), String Shot(81, `True` but inert — already
known from the original NEW ITEM B finding), Sweet Scent(230, `True` but
inert — already known), Tail Whip(39, `is_spread=False`). Cotton Spore,
Poison Gas, and this confirmation of Growl/Leer/Tail Whip's own
`is_spread=False` (rather than just "unset like everything defaults to")
are the new finds this audit adds on top of the original NEW ITEM B list
(String Shot/Sweet Scent).
>
> **[CORRECTED by the NEW ITEM B fix session, same day]: Venom Drench(599)
> does NOT belong in this list.** This audit originally listed it here
> (`is_spread=True` but seemingly inert, matching the other 7's shape) —
> but the fix session's own first test run found Venom Drench has its OWN
> pre-existing `is_venom_drench` dispatch branch that already loops
> `_get_live_opponents(attacker)` directly, independent of
> `_active_per_side`/`is_spread` entirely. It was ALREADY correctly hitting
> both opponents in doubles before any of this M21 work began. Its
> `is_spread=True` flag really is inert — but for a completely benign
> reason (a second, unrelated, already-correct mechanism makes the generic
> flag moot for this one move), not because of the structural gap the
> other 7 shared. **NEW ITEM B's real, confirmed scope is 7 TARGET_BOTH
> moves + Teeter Dance = 8 total, not 9.** See `docs/decisions.md`'s
> `[NEW ITEM B]` entry for the full citation.

**Not yet implemented (name only, no further investigation, 8):**
Captivate, Clangorous Soulblaze, Core Enforcer, Dark Void, Heal Block,
Make It Rain, Thousand Arrows, Thousand Waves.

### `TARGET_FOES_AND_ALLY` (20 total — 16 implemented, 4 not implemented)

**Already correct (2):** Self-Destruct(120), Explosion(153) — both fixed
by M21 item 4, `is_spread=True, target_includes_ally=True`.

**Ally-inclusion mismatch only — `is_spread` already correct, needs
`target_includes_ally` (NEW ITEM C, 11) — ALL 11 FIXED, 2026-07-16:**
Boomburst(586), Brutal Swing(656), Bulldoze(523), Discharge(435), Lava
Plume(436), Magnitude(222), Parabolic Charge(570), Petal Blizzard(572),
Searing Shot(545), Sludge Wave(482), Sparkling Aria(627).

**Needs BOTH the `is_spread` fix AND the ally-inclusion fix (2) — BOTH
NOW FIXED (is_spread 2026-07-15, target_includes_ally 2026-07-16):**
Surf(57), Earthquake(89) — the same two moves NEW ITEM A already flagged
as missing `is_spread` entirely; here they additionally needed
`target_includes_ally=True` once `is_spread` was fixed. These were the
highest-value fixes in this whole audit given how frequently both moves
are used.

**STATUS-category, dispatch UNREACHABLE — a NEW ITEM B case that ALSO
needs the ally-inclusion fix once B is resolved (1):** Teeter Dance(298).
Flagging explicitly so a future session doesn't "fix" Teeter Dance the
same shallow way as the 11 damage moves above and wonder why it still
doesn't hit the ally — it needs status-spread dispatch to exist at all
FIRST, then the ally-inclusion extension on top.

**Not yet implemented (name only, no further investigation, 4):**
Corrosive Gas, Mind Blown, Misty Explosion, Synchronoise.

### `TARGET_ALL_BATTLERS` (4 total — 1 implemented, 3 not)

**Already correct (1):** Perish Song(195) — dedicated `is_perish_song`
dispatch loops over every live combatant on both sides, confirmed correct
in its own recent session (`[Perish Song]`).

**Not yet implemented (3):** Rototiller, Flower Shield, Teatime.

### `TARGET_ALLY` (5 total — 3 implemented, 2 not)

**Already correct (3):** Helping Hand(270), Aromatic Mist, Coaching(739) —
all use dedicated flags (`is_helping_hand`, `stat_change_target_ally`),
not `is_spread`/`target_includes_ally`, and are confirmed already working
correctly per `[M14b]`/`[M19-ally-targeting-stat-change]`.

**Not yet implemented (2):** Hold Hands, Dragon Cheer.

### `TARGET_USER_AND_ALLY` (3 total — 1 implemented, 2 not)

**Already correct (1):** Howl — `also_boosts_ally` flag, confirmed working
per `[M19-ally-targeting-stat-change]`.

**Not yet implemented (2):** Magnetic Flux, Gear Up.

### `TARGET_USER_OR_ALLY` (1 total — 1 implemented) — NEWLY DISCOVERED GAP

**Acupressure(367)** is implemented but its real source target
(`TARGET_USER_OR_ALLY`) lets the user CHOOSE to target either itself or
its ally in doubles with the random +2 stat boost. Current implementation
(`battle_manager.gd:4418-4433`) unconditionally applies the boost to
`attacker` — the ally-targeting choice is not modeled at all; Acupressure
can never be used on an ally in this project. This is a genuinely
different SHAPE of gap from everything else in this audit: it's not a
missing flag or an unreachable dispatch, it's a missing **choice**
mechanism (the user picking between two valid targets), which this
project's `_chosen_targets` infrastructure may or may not already be able
to express — not investigated further per this session's own "flag, don't
design the fix" scope. Newly found this session; not part of the original
6-item `m21_recon.md` inventory nor NEW ITEM A/B/C.

### `TARGET_OPPONENT` (1 total — 1 implemented) — no gap found

**Me First(383)** targets a single specific opponent (whichever one's
chosen move is being copied) — this is a singular-target semantic
distinct from `TARGET_SELECTED` in source's own enum, but has no
multi-target or ally-inclusion implication. Confirmed already correctly
implemented (`[D4 bundle]`) with no gap identified.

### `TARGET_SMART` (1 total — 1 implemented) — already tracked

**Dragon Darts** — already item 5 in this document's main inventory
(deferred to the turn-order-splice session). Not re-investigated here,
cross-referenced only.

### `TARGET_DEPENDS` (11 total — 10 implemented, 1 not) — structurally sound, no gap

Counter(68), Metronome(118), Mirror Move(119), Sleep Talk(214), Mirror
Coat(243), Assist(274), Magic Coat(277), Snatch(289), Metal Burst(368),
Copycat(383) are implemented; Comeuppance is not (name only, no further
investigation).

These 10 split into two structurally distinct families, both confirmed
sound by construction rather than needing per-move fixes:

1. **"Reflect damage back at whoever hit me" family** (Counter, Mirror
   Coat, Metal Burst) — inherently single-target by design (you can only
   reflect at the one specific attacker who hit you); the "depends"
   resolution is "whoever hit me," not a multi-target question. No gap
   possible in this family's shape.
2. **"Call/copy a different move" family** (Metronome, Mirror Move, Sleep
   Talk, Assist, Magic Coat, Snatch, Copycat) — confirmed via direct code
   read (`battle_manager.gd:2934-2977`) that these REASSIGN the local
   `move` variable to the picked/called move's own real `MoveData`
   resource, then fall through to the SAME standard dispatch every
   normally-selected move uses. This means whatever `is_spread`/
   `target_includes_ally`/status-dispatch-reachability the picked move
   itself has is inherited correctly and automatically — if Metronome
   calls Surf, the resulting behavior is exactly as broken (or fixed) as
   Surf's own entry above, not a separate bug. No dedicated fix needed for
   this family beyond fixing the underlying moves it might call.

### Design question flagged, NOT resolved (per explicit instruction)

**How should per-target status-move dispatch (NEW ITEM B's eventual fix)
interact with Substitute, type-immunity, Magic Bounce, and the
Prankster-vs-Dark-type check?** The existing single-target status dispatch
in `_phase_move_execution` (the `foe_targeting` block starting around
`battle_manager.gd:5000`, which runs all of these checks against the one
resolved `defender` before applying the actual stat/status effect) is the
relevant reference starting point — NOT a prescription for the fix's
shape. Open questions a future scoping session will need to resolve
explicitly, not guessed here:
- Does each of the 2 opposing Pokémon in doubles get its OWN independent
  Substitute/type-immunity/Magic-Bounce/Prankster check (most likely,
  mirroring how the existing damage-spread loop already treats each
  target independently), or is there any shared-state subtlety source
  handles differently for status moves specifically?
- If Magic Bounce reflects one target's copy of the move back at the
  original caster, does the OTHER target still get hit normally by the
  original cast, or does a bounce cancel the whole move? (The existing
  single-target Magic Bounce implementation has never had to answer this,
  since it's only ever faced one potential target.)
- How does Prankster's Dark-type immunity check compose when only ONE of
  two opposing targets is Dark-type — does the move still land on the
  non-Dark target, or does source treat the whole cast as failed?

None of these are answered here — flagging them explicitly is the deliverable, per this session's own explicit instruction not to resolve NEW ITEM B's design question in a recon-only pass.

## NEW ITEM D — Shared Accuracy Roll Architecture Gap

Added 2026-07-16, scoping-only recon session — no code changes, no
tests. Found as a byproduct of NEW ITEM A's own Step 0 investigation
(`docs/decisions.md`'s `[NEW ITEM A]` entry), which observed that this
project's damage-move dispatch checks accuracy exactly once, against the
single default target, before the spread/single split. That entry's own
framing characterized this as "inherited, pre-existing behavior... not
something these 9 moves introduce or worsen" — true as far as it goes,
but that framing did NOT verify whether source ITSELF shares this
simplification. **This session did that verification, and the answer is
no — source resolves both accuracy and semi-invulnerability completely
independently per target, via two separate per-target loops. This
project's single shared check is a genuine, confirmed divergence from
source, not a simplification source also makes.** This corrects and
raises the severity of the original framing — flagged explicitly per
this session's own instruction, and this document stops short of a
firm implementation recommendation as a result (see "Recommendation"
below).

### Step 0: source's real mechanism (re-derived, not assumed)

**1. The ordinary accuracy roll is genuinely per-target.** `Cmd_accuracycheck`
(`battle_script_commands.c:1058-1093`) explicitly documents itself as
"Only used for non damage moves (damaging moves are handled in move
resolution)" — damage-move accuracy is NOT resolved by this function at
all. The real mechanism is `CancelerAccuracyCheck`
(`battle_move_resolution.c:2174-2260`), which contains its own explicit
loop:

```c
while (gBattleStruct->eventState.atkCancelerBattler < gBattlersCount)
{
    cv->battlerDef = GetTargetBySlot(cv->battlerAtk, gBattleStruct->eventState.atkCancelerBattler);
    gBattleStruct->eventState.atkCancelerBattler++;
    if (ShouldSkipFailureCheckOnBattler(cv->battlerAtk, cv->battlerDef, TRUE))
        continue;
    if (DoesMoveMissTarget(cv))
    {
        gBattleStruct->moveResultFlags[cv->battlerDef] |= MOVE_RESULT_MISSED;
        ...
    }
    ...
}
```

This iterates every battler slot, calling `DoesMoveMissTarget(cv)`
independently for each one (a freshly-set `cv->battlerDef` per
iteration), and stores the result PER BATTLER
(`moveResultFlags[cv->battlerDef]`). `DoesMoveMissTarget`
(`battle_util.c:10437-10453`) computes `GetTotalAccuracy(battlerAtk,
battlerDef, ...)`, which reads `gBattleMons[battlerDef].statStages[STAT_EVASION]`
— the DEFENDER's own evasion stage — confirming the odds genuinely
differ per target when their evasion (or accuracy-affecting abilities/
items/weather) differ.

**2. The semi-invulnerable bypass is ALSO genuinely per-target**, via a
SEPARATE canceler loop (the target-validity/`CancelerSetTargets`-style
function, `battle_move_resolution.c:1960-2010`), structurally identical
in shape:

```c
while (gBattleStruct->eventState.atkCancelerBattler < MAX_BATTLERS_COUNT)
{
    cv->battlerDef = GetTargetBySlot(cv->battlerAtk, gBattleStruct->eventState.atkCancelerBattler);
    gBattleStruct->eventState.atkCancelerBattler++;
    ...
    else if (!CanBreakThroughSemiInvulnerablity(cv->battlerAtk, cv->battlerDef, ...))
    {
        gBattleStruct->moveResultFlags[cv->battlerDef] |= MOVE_RESULT_FAILED;
        ...
    }
    ...
}
```

Each target's own `semiInvulnerable` state is checked independently.
**Answering the task's own Fissure-vs-Dig-user-plus-grounded-target
question directly**: source would correctly fail against the Dig user
specifically (unless the move carries the matching
`damagesUnderground`/etc. bypass) while resolving completely normally
against the grounded target in the same spread use — two independent
outcomes in one move, exactly as the "obvious" per-target shape
suggests, confirmed rather than assumed.

### Current project behavior: precisely traced, not just characterized

`StatusManager.check_accuracy` (`status_manager.gd:766-`) is called
EXACTLY ONCE in `_phase_move_execution`, against the single default
`defender` resolved before the spread/single split
(`battle_manager.gd:2658`, `m18c_accuracy_hit`). If it returns `false`
(miss), `move_missed.emit(...)` fires and the function returns
immediately — **the entire move, spread or not, never reaches the
damage-dispatch section at all; zero targets take damage.** If it
returns `true` (hit), execution falls through into the "Damaging move"
section, and — for a spread move — every live opposing target (+ally,
if `target_includes_ally`) is unconditionally passed to
`_do_damaging_hit()`, which calls `DamageCalculator.calculate(...)`
directly with **no further accuracy or semi-invulnerable roll of any
kind** (confirmed by reading `_do_damaging_hit`'s full body,
`battle_manager.gd:8943-9020` — it goes straight to damage calculation).

**Concretely, this means the current behavior is a strict binary: either
the single shared roll succeeds and EVERY live target takes damage
(subject only to their own type-immunity/ability-absorb/Substitute
checks, which — confirmed separately — ARE already correctly per-target
inside `_do_damaging_hit`), or it fails and NO target takes damage at
all.** There is currently no code path, anywhere, that can produce a
"hit one target, miss the other" outcome for a spread damage move.

**Important: neither `check_accuracy` nor `_can_hit_semi_invulnerable`
themselves need any logic changes to become correct per-target** — both
are already stateless, generic functions taking `attacker`/`defender`/
`move` as plain parameters (`status_manager.gd:766`, `922`), already
correctly reading the DEFENDER's own evasion stage, semi-invulnerable
state, etc. The gap is purely a CALL-SITE problem: the function is
invoked once, at the wrong scope, instead of once per target inside the
spread loop.

### Exact affected-move count (queried directly, not estimated)

**59 currently-implemented moves** carry `is_spread=True` with a
damage category (not the "~37" originally estimated during NEW ITEM A —
that estimate predated NEW ITEM A/C's own additions, which grew the
`is_spread` pool by 22 moves since): Razor Wind(13), Acid(51), Surf(57),
Blizzard(59), Razor Leaf(75), Earthquake(89), Self-Destruct(120),
Swift(129), Bubble(145), Explosion(153), Rock Slide(157), Powder
Snow(181), Icy Wind(196), Magnitude(222), Twister(239), Heat Wave(257),
Eruption(284), Hyper Voice(304), Air Cutter(314), Water Spout(323),
Muddy Water(330), Discharge(435), Lava Plume(436), Sludge Wave(482),
Incinerate(510), Struggle Bug(522), Bulldoze(523), Electroweb(527),
Searing Shot(545), Relic Song(547), Glaciate(549), Snarl(555), Parabolic
Charge(570), Petal Blizzard(572), Disarming Voice(574), Boomburst(586),
Diamond Storm(591), Dazzling Gleam(605), Land's Wrath(616), Origin
Pulse(618), Precipice Blades(619), Sparkling Aria(627), Clanging
Scales(654), Brutal Swing(656), Shell Trap(658), Splishy Splash(677),
Breaking Swipe(712), Overdrive(714), Burning Jealousy(735), Dragon
Energy(748), Fiery Wrath(750), Glacial Lance(752), Astral Barrage(753),
Springtide Storm(759), Bleakwind Storm(774), Wildbolt Storm(775),
Sandsear Storm(776), Mortal Spin(794), Matcha Gotcha(830).

### Player-visible impact: concrete scenarios, not theoretical

**The high-frequency case (affects potentially any of the 59, whenever
two opposing Pokémon have different accuracy-relevant state)**: if the
two opposing Pokémon in a doubles battle have DIFFERENT effective
evasion (one used Double Team/Minimize, holds an evasion item like
Bright Powder, has Sand Veil/Snow Cloak active in the matching weather,
etc.) or different effective accuracy modifiers on the attacker's own
side interacting differently per-target (rare, but e.g. Foresight/
Miracle Eye/Odor Sleuth applied to only one of the two), source would
roll independently and could hit one while missing the other. This
project's single roll (against whichever target happens to be resolved
as the "default" — this project's own existing targeting-resolution
logic, not examined further in this recon) makes that divergence
architecturally impossible: the outcome is always shared.

**The lower-frequency but higher-severity case**: a spread move used
against one semi-invulnerable target (mid-Fly/Dig/Dive) and one grounded
target in the same use. Depending on which of the two the project's
existing default-target-resolution logic happens to pick as `defender`
for the single shared check:
- If the GROUNDED target is picked: the shared roll passes normally
  (grounded targets have no special miss condition), and the
  semi-invulnerable target INCORRECTLY also takes damage — since there is
  no separate semi-invulnerable check for it at all in the spread branch.
- If the SEMI-INVULNERABLE target is picked and the move lacks the
  matching bypass flag (`damages_underground`/`damages_airborne`/
  `damages_underwater`): the shared check correctly fails for THAT
  target, but the move then returns immediately (per the "no further
  code runs on a miss" behavior above) — INCORRECTLY blocking the hit
  against the grounded target too, which should have connected normally.

This second scenario was not empirically reproduced in this recon
session (scoping-only, no test code was written), but is a direct,
confident conclusion from tracing the code paths above — not a guess.

### Blast-radius assessment: contained core, moderate surrounding bookkeeping

**The core fix is contained**: wrap the existing `check_accuracy` call
(and, before it, the semi-invulnerable/target-validity check) in a loop
inside the spread-dispatch branch, calling both once per live target
using that target's own state, skipping the `_do_damaging_hit` call
for any target that individually misses — mechanically similar in
shape to the existing per-target Substitute/type-immunity checks this
project's damage dispatch already does correctly. Neither underlying
check function needs new logic.

**The surrounding bookkeeping is where real complexity lives**, and
needs its own design pass before implementation, not assumed clean:
- `move_missed.emit(attacker, "accuracy")` currently fires once per
  whole-move-miss; would need to become per-target-scoped, and every
  downstream consumer of that signal (tests, any future UI) would need
  re-auditing for the new multi-fire-per-move shape.
- `move.crashes_on_miss` (Jump Kick-family crash damage) currently
  triggers once per move-use on a miss. Source's own real semantics for
  a PARTIAL spread miss (some targets hit, one missed) is not verified
  in this recon — a genuine open question requiring its own Step 0 before
  any implementation.
- Blunder Policy's own miss-triggered consumption
  (`gBattleStruct->blunderPolicy`) is set inside the SAME per-target loop
  in source (confirmed above) — this project's own equivalent would need
  the same per-target scoping, another piece of bookkeeping to migrate.
- Secondary effects (flinch, stat-lowering, status infliction) are
  ALREADY correctly per-target (confirmed via NEW ITEM B's own
  investigation, reused here) — the fix does NOT need to touch that
  layer, since a per-target hit/miss upstream would simply gate whether
  `_do_damaging_hit` (which already correctly does per-target secondary
  effects) is called for that target at all.

**Overall: a real, moderate-effort, well-contained architecture task —
not a one-line fix, but not "deep rework of shared dispatch state"
either.** The core mechanical change is small; the bookkeeping
migration (particularly `crashes_on_miss`'s own partial-miss semantics)
is the part that needs its own dedicated Step 0 before implementation
begins.

### Cross-reference: independent of other deferred items

- **Turn-order-splice trio** (Dragon Darts, Trick Room × Pursuit,
  Round/Shell Trap/Quash): no direct coupling. Dragon Darts' own
  "smart redirect" (item 5) is thematically adjacent — it also reacts to
  a target's own hit missing — but it's a sequential single-target
  redirect mechanic (`TARGET_SMART`), not simultaneous multi-target
  accuracy resolution; a future NEW ITEM D implementation might
  incidentally share some "did this specific hit miss" plumbing with
  Dragon Darts' own fix, but neither blocks the other.
- **Acupressure's ally-choice gap**: unrelated — a target-CHOICE
  mechanism, not accuracy resolution. No coupling.
- **Lightning Rod/Storm Drain attacker-ally redirect**: unrelated —
  ability-based redirect targeting, not accuracy. No coupling.

NEW ITEM D can be picked up independently of all three, in any order,
whenever prioritized.

### Recommendation

**This session's own findings raise the severity above the original
NEW ITEM A framing** — the original entry described this as behavior
"inherited... not something these 9 moves introduce or worsen," true on
its face but incomplete: it left open whether source shares the same
simplification. It does not. This is a confirmed, genuine divergence
from source affecting 59 already-shipped moves, with at least one
concrete scenario (spread move vs. one semi-invulnerable + one grounded
target) that can produce a flatly wrong outcome (wrongly hitting a
Dig/Fly user, or wrongly blocking a hit against a grounded ally-side
target), not just a probability-distribution nuance.

**Per this session's own explicit instruction: flagging this now and
stopping for input, rather than assigning a firm priority tier or
recommending immediate implementation scoping.** The three candidate
placements, for reference:
- **Its own dedicated session**: justified by the real scope (59
  moves, a genuine architecture change, an unresolved partial-miss
  question for `crashes_on_miss`) — probably the more honest framing
  given the moderate-but-real complexity found here.
- **Folded into the turn-order-splice session**: only a soft, thematic
  connection (Dragon Darts' own per-hit-miss handling); would make that
  session larger without a strong architectural reason to combine them.
- **Deprioritized**: would leave a confirmed, source-divergent
  correctness gap in 59 moves unaddressed indefinitely — not recommended
  given the concrete semi-invulnerable scenario found above, but
  ultimately a scope/priority call, not a technical one.

Added to the recon doc's open-items list below, positioned by
recommended priority pending your own input on which placement to take.

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
- **The further widening flagged in this bullet at the time of this
  recon's original writing has since been done** — see the "Full-Roster
  Spread/Status-Target Audit" section below, added in a same-day follow-up
  session. That audit exhaustively covers every `TARGET_BOTH`/
  `TARGET_FOES_AND_ALLY`/`TARGET_ALL_BATTLERS`/`TARGET_ALLY`/
  `TARGET_USER_AND_ALLY`/`TARGET_USER_OR_ALLY`/`TARGET_OPPONENT`/
  `TARGET_SMART`/`TARGET_DEPENDS`-typed move in source, not implemented vs.
  implemented, with per-move dispatch-reachability findings. Ordinary
  `TARGET_SELECTED`/`TARGET_USER` moves (the overwhelming majority of the
  roster, ~800 moves) remain explicitly out of scope for both this recon
  and its follow-up audit, since neither target type has any multi-target
  or ally-inclusion implication to check.

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
- **2026-07-15, same day, follow-up session**: fixed the 3 stale doc
  comments this recon's own re-sweep found (`item_manager.gd`'s
  `shell_bell_heal` doc comment, `gen_moves.py`'s Self-Destruct(120) entry
  comment, `CLAUDE.md`'s "Post-M18 Review" section items 3/4) — see the
  "Stale documentation" subsection above, now marked RESOLVED. Doc-only,
  zero functional change, no tests needed. The same session also ran the
  full-roster spread/status-targeting scoping audit requested as a
  follow-up to this recon's own NEW ITEM A/B/C findings — see the new
  "Full-Roster Spread/Status-Target Audit" section below.
- **2026-07-15, same day, second follow-up session**: implemented NEW ITEM
  B (status-move spread-targeting dispatch), the highest-priority open
  item the full-roster audit confirmed. Real final scope was 8 moves, not
  9 — Venom Drench(599) was corrected OUT of the structural-gap list
  (confirmed already correct via its own pre-existing `is_venom_drench`
  dispatch, unrelated to `is_spread`). Both the "Full-Roster Spread/
  Status-Target Audit" section and the "Triage / Sequencing" section above
  were updated in place to reflect this correction and mark NEW ITEM B
  COMPLETE. New `scenes/battle/new_item_b_test.gd`/`.tscn`: 29/29
  assertions. See `docs/decisions.md`'s `[NEW ITEM B]` entry for the full
  Step 0 citations and implementation detail.
- **2026-07-15, same day, third follow-up session**: implemented NEW ITEM
  A (9 damage-category moves missing `is_spread` entirely — Razor
  Wind/Surf/Earthquake/Swift/Rock Slide/Eruption/Water Spout/Shell
  Trap/Dragon Energy). All 9 confirmed clean flag-only fixes. Surf/
  Earthquake deliberately left without `target_includes_ally` (still
  deferred to NEW ITEM C), explicitly proven via a dedicated test rather
  than just assumed. **A new, significant finding surfaced and added as
  NEW ITEM D**: this project's accuracy roll is checked once, against the
  default target only, for every spread damage move already shipped —
  not just the 9 from this session — a real architectural gap flagged for
  a future dedicated session, not fixed here. The "Triage / Sequencing"
  section above was renumbered to include this new item. New
  `scenes/battle/new_item_a_test.gd`/`.tscn`: 31/31 assertions. Also
  fixed, as a byproduct: `scripts/gen_move_status_table.py`'s own field
  allowlist was missing `target_includes_ally` (needs-manual-review had
  silently drifted 0→3 across the `[M21]`/`[NEW ITEM B]` sessions) — the
  same recurring gap class this script has hit before; fixed the same
  way, confirmed back to 0. See `docs/decisions.md`'s `[NEW ITEM A]`
  entry for the full Step 0 citations.
- **2026-07-16**: implemented NEW ITEM C (`TARGET_FOES_AND_ALLY`
  full-roster ally-hit sweep), closing the full NEW ITEM A/B/C arc. Fresh
  Step 0 re-derivation confirmed the corrected 13-move worklist (11
  damage-only moves + Surf/Earthquake, the latter two closing NEW ITEM
  A's own deferred gap) and reconfirmed Self-Destruct/Explosion/Teeter
  Dance already fully correct. A specifically-checked interaction (not
  assumed safe): `AbilityManager.pressure_pp_cost` structurally cannot
  count the ally, confirmed via source that Pressure's PP surcharge is
  genuinely opponent-only by design. Parabolic Charge's drain
  reconfirmed genuinely per-hit, explicitly not converted to a Shell-
  Bell-style accumulation. Found and fixed a real, expected regression in
  this arc's own `new_item_a_test.gd` (its A.10/A.11/H.03/I.03 had
  asserted Surf/Earthquake's now-superseded "ally not yet hit" boundary).
  New `scenes/battle/new_item_c_test.gd`/`.tscn`: 30/30 assertions. Both
  the "Full-Roster Spread/Status-Target Audit" section and the "Triage /
  Sequencing" section above were updated in place to mark NEW ITEM C
  COMPLETE. See `docs/decisions.md`'s `[NEW ITEM C]` entry for the full
  Step 0 citations and implementation detail.
