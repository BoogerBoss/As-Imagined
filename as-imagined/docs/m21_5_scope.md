# M21.5 Session 3 — Scoping the Full Move-Effect Review

**RECON/PLANNING ONLY — no implementation this session**, except the
bounded Punch-family check explicitly authorized in the task (Step 4),
whose findings are reported, not fixed, below. Added 2026-07-16.

## Overview

M21.5 Session 1 spot-checked 3 moves Rob flagged and found a mix of
doc-generator bugs (fixed in Session 2) and one real implementation gap
(Mega Punch missing `punching_move`, not yet fixed). Rob wants a full
sweep of all 717 implemented moves against source, but 717 individual
Step-0 re-verifications in one undifferentiated pass isn't practical or
high-value. This session's job is to figure out *how* to partition and
sequence that sweep, using this project's own verification history as
evidence rather than guessing.

**Bottom line up front**: the ground-truth review (Part 1) shows
verification depth was NOT uniform across this arc, and the specific
failure mode Session 1 found (a shared boolean move-flag silently unset
on one roster member) is a **recurring, already-precedented bug class**
(Ice Ball/`ballistic_move` was the first instance, fixed in `[M17n-1]`
before this review even started) — not a one-off. The bounded
Punch-family check (Part 4) confirms this empirically: it found **two
more real, functionally-consequential gaps** beyond Mega Punch in about
ten minutes of grep-and-cross-reference work, at zero cost beyond this
session's own time. This strongly shapes the recommended sequencing:
shared-boolean-flag families are the cheapest, highest-confidence,
lowest-effort bucket to sweep exhaustively, and should go first.

## Part 1: Ground truth on prior verification depth

There is no single per-move verification ledger, but there IS a
reliable proxy: `docs/decisions.md` (session-by-session) and CLAUDE.md's
own "Current status" section record, for essentially every tier/bundle,
*how* each batch of moves was verified — individually against source
with an explicit checklist, vs. classified into a mechanism cluster and
implemented/tested mostly at the cluster level. Reading through that
history yields a clear pattern:

### High-scrutiny tiers (individual per-move Step 0, explicit source citation per move)

- **M16a–M16e** (Tier A–E, ~50–60 moves per sub-tier, all individually
  named): small enough lists that each move got its own source citation
  and its own test assertion. Low risk.
- **M19a-gen1** (Generation I Tier-1 slice, 22 moves): explicitly
  "individually re-verified... rather than trusting it" — but the
  session's own checklist only covered `makes_contact`, `slicing_move`,
  `ballistic_move`, `damages_airborne`, `critical_hit_stage`, `is_spread`.
  **`punching_move` was never on this checklist** — this is the direct
  origin of the Mega Punch bug: not carelessness, but an incomplete
  checklist applied carefully.
- **Bucket 1** (67 pure-damage moves): the *most* rigorous flag audit in
  the whole arc — explicitly re-verified with a broadened scan adding
  `alwaysCriticalHit`, `damagesAirborne`, `pulseMove`, `windMove`,
  `ignoresTargetAbility`, `ignoresTargetDefenseEvasionStages`,
  `cantUseTwice`, `priority` on top of the M19a-gen1 checklist. Still,
  by this point Mega Punch(5) was already implemented (from M19a-gen1)
  and out of Bucket 1's own scope, so this broadened checklist never
  touched it retroactively.
- **D4 Bundles 1–9** (6–23 moves per bundle): consistently did
  "Step 0 re-derived all N fresh from source," but scoped to *that
  bundle's own mechanism* — a bundle about turn-order or delayed effects
  checks turn-order/delayed-effect fields carefully, not an unrelated
  flag like `punching_move` that a bundle member might happen to also
  carry.

### Lower-scrutiny tiers (classified by mechanism cluster, tested at the cluster/mechanism level)

- **Bucket 2 (246 moves, the single largest tier in the whole M19
  effort)**: split into 8 mechanism groups (`EFFECT_HIT`+secondary 72,
  pure `EFFECT_STAT_CHANGE` 30, `EFFECT_NON_VOLATILE_STATUS` 9,
  `EFFECT_RECOIL` 9, `EFFECT_ABSORB` 8, `EFFECT_CONFUSE` 3,
  `EFFECT_SEMI_INVULNERABLE` 2, `EFFECT_TWO_TURNS_ATTACK` 2). Its own
  entry explicitly says the functional test suite was "deliberately lean
  (5 checks)" — one representative check per mechanism group, not one
  check per move, and explicitly NOT re-deriving mechanisms "already
  proven in general by earlier tiers." This is architecturally sound for
  proving the *mechanism* works, but by construction it does not
  individually confirm every cross-cutting boolean flag (contact-move
  family membership, punching/biting/sound/ballistic/pulse-move
  membership) on all 246 members. **This is the single highest-risk
  bucket by move count and by shallowness of per-move flag scrutiny.**
- **D1/D2/D3 "cluster" sessions** (the ~90-move D1 effect-name-cluster
  sweep, D2's batches): moderate depth — grouped and tested per cluster,
  similar risk shape to Bucket 2 but smaller scale per cluster.

### "Implementation predates a later generalization" — a confirmed, recurring pattern, not hypothetical

This project's own history already contains **two prior confirmed
instances** of exactly this failure shape, found and fixed *before* this
review started:

1. **Ice Ball / `ballistic_move`**: flagged in a code comment since
   `[M16b]` ("Ice Ball's own `ballistic_move` flag was cited in a
   comment... but never actually set") — sat wrong for roughly a dozen
   sessions until `[M17n-1]` (Soundproof/Bulletproof implementation)
   incidentally retroactively fixed it while wiring up the same field
   family for its own abilities.
2. **Air Balloon/Iron Ball groundedness**: `AbilityManager.is_grounded`'s
   own doc comment explicitly flagged both items as "known, anticipated
   gap" back at `[M16d]`'s creation — sat correctly-documented-but-unbuilt
   until `[M18t]` implemented both items and closed the gap.

Both cases share the same shape as Mega Punch: a field or mechanism
existed and was even *correctly documented as incomplete*, but nothing
forced a full-roster sweep until an unrelated later session happened to
touch the same field family. **This is now a 4th-and-5th confirmed
instance** (Mega Punch + this session's own two new finds below) of the
identical bug class — five independent occurrences is enough to treat
"shared boolean move-flag, silently unset on some roster member" as a
standing, expected defect class for this project, not a fluke.

### Recently-added (D1–D4) vs. early-tier (M16–M17) defect-rate comparison

Counter to what the task's own framing guessed, the LATER bulk sessions
(D1–D4, all under the "Step 0 first" discipline this arc formalized
partway through M19) show **better** per-move scrutiny than the
earliest bulk sessions (M19a-gen1, Bucket 1/2), not worse — the
discipline of "individually re-verify against source, don't trust the
classifier" was itself a lesson learned partway through M19 (explicitly
stated in multiple D-bundle entries: "Step 0 re-derived X fresh... per
this arc's own standing rule"). The real risk concentration is:

- **Bucket 2 specifically** (246 moves, mid-arc, before the "always
  re-verify individually" norm fully solidified, and inherently
  cluster-tested by design) is the largest single risk pool.
- **The earliest generation-sliced/bucketed sessions** (M19a-gen1,
  Bucket 1) used *incomplete but evolving* flag checklists — later
  sessions had a longer checklist than earlier ones, meaning moves
  implemented earliest are more likely to be missing a flag that was
  only "discovered" as worth checking in a later session.

## Part 2: Candidate risk buckets

Based on Part 1's evidence, not the task's own example list taken
uncritically:

1. **Shared boolean move-flag families** (punching/biting/sound/
   ballistic/pulse/powder/dance/slicing-move, plus similar smaller
   families like `thaws_user`, `ignores_protect`, `ignores_substitute`).
   **Confirmed non-hypothetical via Part 4 below**: 2 more real gaps
   found (Headlong Rush/`punching_move`, Aerial Ace/`slicing_move`) in
   a single bounded check. This is the highest-confidence, lowest-cost
   bucket — a mechanical grep-and-cross-reference per flag, not a
   judgment call.
2. **Bucket 2's 246 moves specifically** (not "all Bucket-2-descended
   moves" generically — this specific historical tier, identifiable by
   its own `docs/decisions.md` `[M19-bucket2]` entry's move list). The
   largest pool of moves implemented with cluster-level rather than
   individual scrutiny. Highest raw move-count risk.
3. **Move-specific secondary mechanics** (charge-turn stat boosts,
   weather-conditional healing/accuracy, HP-based power, random-status
   pools, and similar "this one move (or handful of moves) has a unique
   numeric parameter, not just a boolean flag" cases) — the exact class
   Session 1's 3 examples came from. Lower move-count than bucket 1/2
   but the display-generator blind spot already proved these are easy to
   get subtly wrong even when the underlying data is correct (Steel
   Wing/Skull Bash were both correct-but-invisible; Mega Punch was
   genuinely wrong).
4. **Fields that predate a later generalization/fix** (the Ice-Ball/
   Air-Balloon-Iron-Ball pattern). Not a fixed list — an ongoing
   *review discipline* rather than a one-time bucket: whenever a future
   ability/item session builds a new consumer for an existing MoveData
   field, immediately grep the full roster for who *should* carry that
   field per source, not just the named examples the session already
   knows about. Recommend formalizing this as a standing checklist item
   (mirroring the already-existing "does this foe-targeting move call
   `typecalc`" standing checklist CLAUDE.md documents) rather than a
   one-time sweep.
5. **D1/D2/D3 cluster-tested moves** (~90 moves, moderate risk,
   moderate size) — lower priority than 1–3 but higher than the
   individually-Step-0'd tiers.

**Deliberately NOT its own bucket**: M16a–M16e, D4 Bundles 1–9, and the
Bucket-1-style individually-re-verified tiers. These were already
verified at the highest depth this arc has practiced; re-auditing them
with the same rigor a second time is low expected value relative to
buckets 1–3 above. A cheap spot-check (5–10 moves) as a sanity check is
reasonable but a full sweep is not recommended for these tiers.

## Part 3: Proposed audit methodology per bucket

**Bucket 1 (shared boolean flags) — mechanical, cheap, do first:**
For each of the ~15–20 boolean move-flags this project's schema defines
(not just the 8 checked in Part 4 — also `thaws_user`,
`blocked_by_aroma_veil`, `ignores_protect`, `ignores_substitute`,
`crashes_on_miss`, `breaks_protect`, `snatch_affected`,
`target_includes_ally`, etc.): programmatically enumerate every source
move carrying the real C flag TRUE, cross-reference against
`move_status_table.md`'s Implemented/Excluded classification (skip
Excluded — no bug there), and cross-reference the Implemented subset
against `gen_moves.py`'s own entries. Flag every mismatch. This is
*exactly* the script written for Part 4 below, generalized to every
flag in the schema — a single script run, not per-move manual review.
Escalate anything found to a manual "is there a real functional
consumer, or is this display-only" check per Session 1's own
established (a)/(b) classification discipline, same as Mega Punch vs.
Steel Wing/Skull Bash.

**Bucket 2 (Bucket 2's 246 moves) — spot-check first, escalate on signal:**
Given this is a judgment-call-shaped review (not a clean flag mismatch),
recommend: (a) run Bucket 1's flag-mismatch script filtered to just
these 246 moves first (near-zero extra cost, reuses the same tooling);
then (b) hand-verify a stratified sample — 15–20 moves, at least 2 from
each of the 8 mechanism sub-groups, weighted toward the largest
sub-group (`EFFECT_HIT`+secondary, 72 moves) — against source's full
struct entry, not just the one field the mechanism group cares about.
If the sample's defect rate is at or below what Bucket 1's mechanical
sweep already found for the same 246 moves (i.e., nothing NEW beyond
flag mismatches already caught), stop — full manual audit of all 246 is
not justified. If the sample turns up a genuinely new defect class (not
just another flag omission), escalate to a full pass over that specific
sub-group only, not all 246.

**Bucket 3 (move-specific secondary mechanics) — full individual
Step-0, matching Session 1's own precedent:**
This is inherently a "read the source struct for this one move, compare
to its `.tres`, compare to its dispatch code" review — no shortcut
exists, since each move's own numeric parameter (a charge-turn boost
amount, a weather-fraction, an HP threshold) is independent. Enumerate
every `MoveData` field that is NOT a plain boolean and is set to a
non-default value on 10 or fewer moves (a superset of Session 1's own
7-field finding, likely 15–25 fields once every non-boolean field is
enumerated fresh — re-enumerate at the start of whichever session picks
this up, don't assume Session 1's list is exhaustive, since Session 1
was scoped to display-generator gaps specifically, not a full
implementation audit). For each field, individually re-verify every
move that sets it against source, exactly as Session 1 did for Skull
Bash/Steel Wing/Mega Punch. Budget roughly 3–5 moves verified per
"unit of session effort," based on Session 1's own pace.

**Bucket 4 (predates-a-later-generalization) — standing discipline, not
a one-time sweep:** No dedicated session needed now. Add a checklist
line to CLAUDE.md (or `docs/decisions.md`'s own process notes) that any
future ability/item session building a new consumer for an existing but
previously-dormant `MoveData` field must grep the full roster for every
move that *should* carry it per source, not just the specific named
moves that session already has in mind — mirroring the already-existing
"does this foe-targeting move call `typecalc`" standing rule.

**Bucket 5 (D1/D2/D3 cluster-tested moves) — spot-check only, lowest
priority:** A light 8–10-move stratified spot-check across the ~90
moves, similar cost/depth to Bucket 2's escalation step, run only after
buckets 1–3 are done and only if time/interest remains.

## Part 4: Punch-family check (run this session, per Step 4's authorization)

**Method**: parsed `moves_info.h` directly for every move with
`.punchingMove = TRUE` (24 real punching moves in source, independently
re-derived — not assumed from memory), cross-referenced each by name
against `gen_moves.py`'s own entries for the `punching_move` key.

**Results** (24 source punching moves, 23 implemented in this project +
1 excluded):

| Move | ID | punching_move in gen_moves.py? |
|---|---|---|
| Comet Punch | 4 | YES |
| Mega Punch | 5 | **MISSING (already-confirmed Session 1 bug)** |
| Fire Punch | 7 | YES |
| Ice Punch | 8 | YES |
| Thunder Punch | 9 | YES |
| Dizzy Punch | 146 | YES |
| Mach Punch | 183 | YES |
| Dynamic Punch | 223 | YES |
| Focus Punch | 264 | YES |
| Meteor Mash | 309 | YES |
| Shadow Punch | 325 | YES |
| Sky Uppercut | 327 | YES |
| Hammer Arm | 359 | YES |
| Drain Punch | 409 | YES |
| Bullet Punch | 418 | YES |
| Power-Up Punch | 612 | YES |
| Ice Hammer | 628 | YES |
| Plasma Fists | 674 | N/A — **Excluded** (Rob's `[M19-exclusions]` list, not a gap) |
| Double Iron Bash | 689 | YES |
| Wicked Blow | 745 | YES |
| Surging Strikes | 746 | YES |
| **Headlong Rush** | **766** | **MISSING — NEW FINDING** |
| Jet Punch | 785 | YES |
| Rage Fist | 815 | YES |

**New finding**: **Headlong Rush(766) is also missing `punching_move`.**
Traced its origin: Headlong Rush was implemented in the "Bucket 3
multi-stat cluster" session (`[Bucket 3 multi-stat]`, 2026-07-09), whose
entire checklist focus was the move's self Def/SpDef -1 multi-stat
change — `punching_move` was never part of that session's own review
scope, the same root-cause shape as Mega Punch's own M19a-gen1 omission.
**Same functional impact as Mega Punch**: confirmed via
`ability_manager.gd:1961`/`item_manager.gd:1425` that Iron Fist and
Punching Glove both key off `move.punching_move` — a Pokémon with Iron
Fist or holding Punching Glove using Headlong Rush does not currently
get the intended boost/interaction.

**A broader confirming sweep** (checking 7 other similar boolean-flag
families as a quick supporting data point for Part 2's bucket
prioritization, not a full audit) found:

| Flag | Source TRUE count | Real gaps among Implemented moves |
|---|---|---|
| `punching_move` | 24 | **2** (Mega Punch, Headlong Rush) |
| `biting_move` | 10 | 0 |
| `sound_move` | 32 | 0 |
| `ballistic_move` | 25 | 0 (already fixed — see `[M17n-1]`'s Ice Ball retroactive fix) |
| `pulse_move` | 7 | 0 |
| `powder_move` | 8 | 0 |
| `dance_move` | 12 | 11 (see below — NOT currently a functional bug) |
| `slicing_move` | 26 | **1** (Aerial Ace, ID 332) |

**`slicing_move` / Aerial Ace(332) — a third real, functionally-confirmed
gap, found the same way**: confirmed via `ability_manager.gd:1975`
(`if id == ABILITY_SHARPNESS and move.slicing_move:`) that Sharpness
directly consumes this flag. Aerial Ace is missing it in `gen_moves.py`
— a Sharpness holder using Aerial Ace currently does not get its
intended 1.5× boost. **Not fixed this session, per Step 7's
instruction** — flagged for the Bucket 1 fix session below.

**`dance_move` / 11 "gaps" — investigated and confirmed NOT a live bug**:
`MoveData.dance_move` exists as a real exported field (`move_data.gd`
line 76), but grepping the whole codebase found **zero functional
consumers anywhere** — the only ability that would read it, Dancer, is
itself confirmed EXCLUDED (`docs/m17_final_ledger.md`: "needs new dance
flag + move-repeat mechanism"). So these 11 moves (Swords Dance, Petal
Dance, Feather Dance, Teeter Dance, Dragon Dance, Lunar Dance, Quiver
Dance, Fiery Dance, Clangorous Soul, Victory Dance, Aqua Step) missing
`dance_move` are a genuine data-completeness gap but currently
**zero functional impact** — exactly Session 1's "(a) display-only, case
(a)" classification, except here it's not even display-visible (no
generator clause reads it either). Flagged for whenever Dancer is
reconsidered, not for immediate fixing.

**Recommendation folding Mega Punch's fix in**: do NOT fix Mega Punch in
isolation. Since this session found 2 more real punching_move/
slicing_move-family gaps at zero marginal cost, the sensible "first
concrete task" is the full Bucket 1 sweep (Part 3's methodology) rather
than a 1-move patch — Mega Punch, Headlong Rush, and Aerial Ace should
all be fixed together in that same session, plus whatever the full
~15-20-flag sweep additionally turns up, each with its own small
regression test per this project's established real-bug-fix discipline
(a targeted test proving the relevant ability/item now recognizes the
previously-missing flag, matching the Mega Punch fix Session 1 already
scoped).

## Part 5: Recommended sequencing plan

1. **Bucket 1 — shared boolean move-flag full sweep + fixes** (includes
   Mega Punch, Headlong Rush, Aerial Ace, plus whatever the full
   ~15–20-flag mechanical sweep additionally finds). **1 session.**
   Highest confidence, lowest cost, already has 3 confirmed real bugs
   queued. Do this first.
2. **Bucket 3 — move-specific secondary-mechanic fields, full
   individual sweep.** Likely **2–3 sessions** given the "3–5 moves per
   session-unit" pace estimate and an expected 15–25 fields to
   individually re-derive (re-enumerate fresh at the start, don't reuse
   Session 1's 7-field list uncritically — it was scoped to
   display-generator gaps, not a full field census).
3. **Bucket 2 — Bucket 2's 246 moves, mechanical sweep + stratified
   spot-check.** **1 session** for the mechanical flag-mismatch pass
   (reuses Bucket 1's tooling), **1 more session** only if the
   stratified sample (15–20 moves) surfaces a genuinely new defect class
   beyond flag mismatches — otherwise stop after the mechanical pass.
   **1–2 sessions.**
4. **Bucket 5 — D1/D2/D3 cluster-tested moves, light spot-check.**
   **1 session**, lowest priority, only after 1–3 are done.
5. **Bucket 4 — standing discipline, not a session.** Add one checklist
   line to CLAUDE.md now (or fold into whichever session ships Bucket 1,
   since it's directly analogous to the already-existing `typecalc`
   standing-checklist precedent) rather than scheduling dedicated time.

**Total estimate: roughly 5–7 sessions** to cover buckets 1, 2, 3, and 5
at the depths recommended above, with bucket 4 folded in as a
process-doc change rather than its own session. Bucket 1 should start
immediately — it is bounded, mechanical, and already has 3 confirmed
real bugs waiting.

No Step-0-first "architectural fork" risk was found in any bucket —
every proposed methodology reuses tooling/discipline this arc has
already established (the Part 4 script, Session 1's per-field
individual-verification pattern, the existing cluster-then-spot-check
shape M19's own D1/D2 sessions already used). Nothing here requires
stopping to ask a judgment-call question before proceeding to
implementation, other than Rob's own choice of which bucket to schedule
next.

## Bucket 1 — IMPLEMENTATION COMPLETE (2026-07-16)

Re-verified Part 4's 3 confirmed bugs and the `dance_move` non-bug
classification fresh against current code before touching anything —
all still accurate. Extended the sweep from the 8 originally-checked
flag families to **all 25 simple boolean move-property flags** this
project tracks with a real 1:1 source struct-field equivalent (every
non-`is_*` field in `move_data.gd` matching that shape — `makes_contact`,
`ignores_protect`, `bounceable`/`magicCoatAffected`, `snatch_affected`,
the 8 already-checked move-family flags, `healing_move`,
`double_power_on_minimized`, `ignores_target_ability`,
`ignores_defense_evasion_stages`, `damages_underground/underwater/airborne`,
`thaws_user`, `ignores_substitute`, `cant_use_twice`, `always_hits_in_rain`,
`accuracy_halved_in_sun`, `always_critical_hit`). Deliberately excluded
from this bucket: the `ban_flags` bitmask family (already fully audited
in `[M19.5]` Task 1) and derived/composite fields that aren't plain 1:1
source booleans (`stat_change_self`, `target_includes_ally`,
`stat_change_bypasses_type_gate`, `blocked_by_aroma_veil`).

**Two methodology corrections found and fixed before trusting any
result, beyond Part 4's own scope:**

1. **The Part 4 script had an uncaught false-positive bug**: it matched
   `.fieldName = TRUE` anywhere in a move's source chunk, including
   inside a `//`-commented-out line (found via Swagger/Defog's own
   commented-out `ignoresSubstitute` lines, both deliberately disabled
   at this reference tree's Gen4+/Gen5+ config — real game behavior,
   not a gap). Fixed by stripping `//` comments per-line before
   matching.
2. **The sweep initially only matched bare `TRUE` values, silently
   skipping every GEN-conditional expression** (`X >= GEN_N`-style,
   used extensively for flags whose scope changed across generations).
   Resolved all such expressions against this project's own real
   config (`GEN_LATEST = GEN_9 = 8`, confirmed directly from
   `include/config/general.h`/`battle.h`) rather than treating them as
   unresolvable — this materially changed several fields' gap counts
   (e.g. `magicCoatAffected` went from 6 bare-TRUE gaps to 14 once
   Gen5/Gen6-conditional entries like Encore/Disable/Spikes were
   correctly resolved).

**A third, more consequential finding, made only by reading the actual
dispatch code rather than trusting a flag's source truth-value in
isolation**: this project's `_phase_move_execution` is one large
sequential function where many moves have their OWN dedicated `is_X`
dispatch branch ending in an unconditional early `return` — meaning a
flag can be **100% correct per source** yet have **zero functional
consequence** in this specific codebase, because the move's own
dispatch never reaches the generic mechanism that would consume it.
Confirmed via direct line-position tracing (does the move's own
dispatch sit before or after the generic gate?) for every ambiguous
case, not assumed. This reclassified several apparent "gaps" as
non-bugs that a naive flag-only sweep would have wrongly "fixed" with
zero effect:

- `makes_contact` on **Bide(117)**: its damage path
  (`_apply_fixed_dmg_to_target`, shared with Counter/Mirror Coat) never
  reads `makes_contact` at all — no contact-reactive ability
  (Rough Skin/Static/etc.) can currently fire off Bide regardless of
  the flag. Non-bug, not fixed; flagged as a real, disclosed
  architecture gap (fixed-damage moves never trigger contact-reactive
  effects) for a future session if Bide's own contact status ever
  needs to matter.
- `ignores_protect` on **Protect/Detect/Endure** (182/197/203): their
  own `is_protect` dispatch returns unconditionally before the generic
  Protect-block gate is ever reached. Non-bug, not fixed.
- `bounceable` on **Whirlwind(18)/Roar(46)** (`is_roar`),
  **Disable(50)** (`is_disable`), **Encore(227)** (`is_encore`),
  **Attract(213)** (`is_attract`), and **Sappy Seed(685)** (a damaging
  move dispatched via `is_leech_seed_on_hit`, never through the
  status-move bounce-check path at all): each has its own dedicated
  early-return dispatch that never consults `move.bounceable` or the
  Magic Bounce/Coat swap. Non-bugs, not fixed. (Encore's own
  `ignores_substitute`, by contrast, IS real — its `is_encore` block
  contains its own **local** substitute check, independent of the
  generic gate.)
- `bounceable` on **Spikes(191)/Toxic Spikes(390)/Stealth Rock(446)**:
  already an explicitly documented, pre-existing known limitation
  (`AbilityManager.bounces_status_move`'s own doc comment: hazard-bounce
  needs a side-wide dispatch rework, flagged for a future tier since
  `[M17n-9]`) — re-confirmed, not touched, not re-flagged as new.
- `ignores_substitute` on **Haze(114)/Destiny Bond(194)/Heal Bell(215)**:
  all three dispatch purely against `attacker`/the whole field, never
  reading `defender.substitute_hp` at all. Non-bugs, not fixed.

**A genuine correction to a prior session's own claim, found and
documented rather than silently overridden**: `[M17n-9]`'s own doc
comment for `bounces_status_move` asserted "Encore... confirmed absent
from source's `magicCoatAffected=TRUE` table" — this is factually wrong
against current source (`B_UPDATED_MOVE_FLAGS >= GEN_5` resolves TRUE
at `GEN_LATEST=GEN_9`). However, per the reachability finding above,
Encore's own dispatch never reaches the generic bounce-check anyway, so
this correction has zero practical consequence today — noted for the
record, not acted on beyond documentation, since "fixing" the flag
alone would do nothing.

### Final fix list — 71 field additions across 69 moves, 10 flags (all confirmed reachable via an existing, already-tested generic consumer)

| Flag | Moves fixed |
|---|---|
| `punching_move` | Mega Punch(5), Headlong Rush(766) |
| `slicing_move` | Aerial Ace(332) |
| `makes_contact` | Feint Attack(185) |
| `healing_move` | Absorb(71), Mega Drain(72), Giga Drain(202), Drain Punch(409), Morning Sun(234), Synthesis(235), Moonlight(236), Shore Up(622) |
| `double_power_on_minimized` | Body Slam(34), Dragon Rush(407), Heavy Slam(484), Heat Crash(535) |
| `damages_underwater` | Whirlpool(250) |
| `bounceable` | Kinesis(134), Tickle(321), Noble Roar(568), Tearful Look(669), Spicy Extract(786) |
| `snatch_affected` | Conversion(160), Wish(273), Recycle(278), Healing Wish(361), Aqua Ring(392), Magnet Rise(393), Lunar Dance(461) |
| `ignores_protect` | Swords Dance(14), Metronome(118), Substitute(164), Destiny Bond(194), Sandstorm(201), Rain Dance(240), Sunny Day(241), Hail(258), Cosmic Power(322), Bulk Up(339), Calm Mind(347), Dragon Dance(349), Hone Claws(468), Quiver Dance(483), Coil(489), Shell Smash(504), Shift Gear(508), Work Up(526), Tearful Look(669), Decorate(705), Victory Dance(765), Snowscape(809), Hyper Drill(813) |
| `ignores_substitute` | Growl(45), Sing(47), Supersonic(48), Screech(103), Encore(227), Hyper Voice(304), Metal Sound(319), Grass Whistle(320), Bug Buzz(405), Echoed Voice(497), Relic Song(547), Snarl(555), Noble Roar(568), Disarming Voice(574), Boomburst(586), Confide(590), Clanging Scales(654), Overdrive(714), Torch Song(799) |

Every one of these 10 flags is consumed by an already-built, already-tested,
generic mechanism (Iron Fist/Punching Glove; Sharpness; contact-reactive
ability dispatch; Triage's `move_priority_bonus`; the post-roll Stomp-family
damage modifier; the semi-invulnerable bypass check; Magic Bounce/Magic Coat's
swap; Snatch's steal-and-reassign; the universal `_is_protected_from` gate;
the universal `went_to_sub`/per-hit Substitute-bypass check or, for Encore,
its own local check) — none of these fixes required new dispatch code, only
`gen_moves.py` data additions.

**Test-audit-first pass, before regenerating anything**: grepped every
scene file for all 69 touched move names/IDs, checked every file doing
an exact-equality or exhaustive negative-flag check against the
specific fields touched. Found and fixed 3 genuinely stale assertions:

1. `m19_bucket1_test.gd`'s own Section A table had `makes_contact=false`
   hardcoded for Feint Attack(185) — updated to `true`.
2. `m19_bucket2_test.gd`'s shared `_chk_flag_tokens` exhaustive
   negative-check pattern required updating 9 rows' own token lists
   (Dragon Rush +`double_min`, Kinesis +`bounceable`, Screech/Metal
   Sound/Confide/Sing/Grass Whistle/Supersonic/Relic Song all
   +`ignores_sub`) — each would otherwise have asserted "NOT
   ignores_substitute"/"NOT bounceable"/"NOT double_power_on_minimized"
   against a move this session correctly changed.
3. `m17n3_test.gd`'s own `[M17n-3]` Section 1 (2026-07-04) explicitly
   asserted `not giga_drain.healing_move`, with a comment claiming
   "drain moves like Giga Drain do NOT carry it" — this claim was
   simply wrong even at the time it was written: `[M19-bucket2]`
   (2026-07-08) independently found and correctly set
   `healing_move=true` for its OWN 8 absorb-family moves via the exact
   same `B_HEAL_BLOCKING >= GEN_6` resolution, explicitly noting "that
   earlier gap [on Giga Drain/Absorb/Mega Drain/Drain Punch] remains
   unfixed, re-flagged here for visibility" — a flag this session
   finally closed. Updated the assertion (now expects `true`) with a
   corrected doc comment citing both sessions.

No other file's existing assertions needed changes — every other
reference to a touched move name/ID was either a synthetic
`MoveData.new()` construction unrelated to the real `.tres` data, or
didn't check any of the 10 touched fields at all.

**Regenerated** `data/moves/*.tres` for all 69 moves via
`python3 scripts/gen_moves.py`, then `docs/move_status_table.md` via
`python3 scripts/gen_move_status_table.py` — confirmed counts
**unchanged**: 717 implemented / 217 excluded / 0 residual / 0
needs-manual-review (a pure flag/data fix, no implementation-status
change).

**Regression**: 27 targeted suites (every file touching any of the 69
moves, plus `move_smoke_test.tscn`) all passed clean on the first run
after the 3 test fixes above. Two full sweeps via
`scripts/count_assertions.sh` from independent process states: **132
files, GRAND TOTAL 13360 then 13359**, differing only by the
already-documented pre-existing `m19a_gen1_test.tscn` flake (confirmed
via direct diff of both sweep logs) — zero failures traceable to this
session's changes in either run.

**Bucket 1 was provisionally closed here** — see the dedicated
verification pass below, which found this closure was premature (no
flag category had a genuine runtime-behavior test) and fixed it before
Bucket 3 began.

## Bucket 1 — Verification pass (2026-07-16, Part A of a follow-up session)

Bucket 1's own implementation session repaired 3 EXISTING data-integrity
assertions that would otherwise have broken (`m19_bucket1_test.gd`'s
Feint Attack row, `m19_bucket2_test.gd`'s 9 token-list rows,
`m17n3_test.gd`'s Giga Drain row) — but never added a NEW test proving
any of the 10 fixed flags' real consumer mechanism actually fires for
the SPECIFIC move it was added to. Checked directly: **every
pre-existing consumer test in this codebase uses either a synthetic
`MoveData` or an already-correct move that predates this session** —
Iron Fist's own test (`m17n5_test.gd` S3) uses `_synth_move(60, 0)` with
`.punching_move` set programmatically, never the real Mega Punch(5)
`.tres`; Sharpness's own test (S10) is explicitly commented "synthetic
slicing move — none exist in this roster" (stale even before this
session, but never touching Aerial Ace(332) either way); Triage's own
test uses Recover(105); Stomp's own minimize test predates Body Slam's
fix; Magic Bounce's suite doesn't touch any of the 5 newly-bounceable
moves; Snatch's own test steals Swords Dance(14), which `[D4 Bundle 8]`
(not this session) made snatch_affected. **This confirms the gap the
task flagged is real** — not just under-documented, genuinely untested.

**Fixed**: wrote `scenes/battle/bucket1_behavior_test.gd`/`.tscn`, one
representative move per fixed flag category (10 categories, 9 test
functions — punching_move and slicing_move share the same
DamageCalculator-based shape), each loading the REAL `.tres` data via
`_load_move(id)` and proving the already-built consumer mechanism now
fires, with a negative control per mechanism:

| Flag | Representative move | Consumer proven | Negative control |
|---|---|---|---|
| `punching_move` | Mega Punch(5) | Iron Fist damage boost | Tackle (no flag) — no boost |
| `slicing_move` | Aerial Ace(332) | Sharpness damage boost | Tackle (no flag) — no boost |
| `healing_move` | Absorb(71) | Triage +3 priority | Tackle — +0 priority |
| `double_power_on_minimized` | Body Slam(34) | Stomp-family ×damage vs. minimized target | Tackle — no difference |
| `damages_underwater` | Whirlpool(250) | `_can_hit_semi_invulnerable` vs. Dive | Tackle — cannot hit |
| `bounceable` | Tickle(321) | Magic Bounce reflects onto the attacker | Leer (already-correct pre-session) — still bounces, confirming no regression |
| `snatch_affected` | Aqua Ring(392) | Snatch steal-and-reassign — snatcher gets the volatile, not the caster | (mechanism itself already has its own negative cases in `d4_bundle8_test.gd`) |
| `ignores_protect` | Substitute(164) | Succeeds despite the opponent's `protect_active` | Leer (no flag) — correctly blocked |
| `ignores_substitute` | Growl(45) | Stat drop lands through an active Substitute | Kinesis (no flag) — correctly blocked |

**Two real test-authoring bugs caught and fixed before trusting the
result**, both fresh recurrences of already-documented pitfall classes:

1. The `snatch_affected`/Aqua Ring test initially read
   `atk.aqua_ring_active`/`def.aqua_ring_active` AFTER a full
   `start_battle()` call — the exact whole-battle-aggregation pitfall
   this project's testing conventions document: `def`'s only move is
   Aqua Ring, so once the queue drains it legitimately re-casts Aqua
   Ring on its own later turn, setting `def.aqua_ring_active = true` for
   real and making the post-battle read misreport the steal as failed.
   Fixed by snapshotting at the first `move_executed` occurrence,
   matching `d4_bundle8_test.gd`'s own established pattern for this
   exact move family.
2. The `ignores_substitute` negative control (Kinesis, 80% accuracy —
   unlike Growl's 100%) intermittently failed: a natural accuracy miss
   fires `move_missed` with a different reason than `"substitute"`,
   making the assertion fail on the ~20% of runs where Kinesis missed
   outright. Fixed with `_force_hit = true`. Confirmed stable across 8
   consecutive reruns after the fix (2 of 5 runs failed before it).

All 17 assertions pass, stable. **No flag fix was found to be broken —
every one of the 10 categories has a confirmed, real runtime effect.**
Bucket 1 is genuinely closed now, not just provisionally.

**Doc-organization gap flagged, not fixed this session** (per the
task's own instruction): the "documented as non-bug" list (Bide's
`makes_contact`, Protect/Detect/Endure's `ignores_protect`, 6
unreachable `bounceable` moves, Spikes/Toxic Spikes/Stealth Rock,
Haze/Destiny Bond/Heal Bell's `ignores_substitute`) exists ONLY in this
scoping doc and its `docs/decisions.md` counterpart — the actual
`move_data.gd` field declarations for `makes_contact`/`ignores_protect`/
`bounceable`/`ignores_substitute` carry NO doc comment at all (they
predate this project's later convention of annotating fields inline).
A future Bucket 2/3 session investigating one of these same fields for
a DIFFERENT move would have no in-code signal pointing back to this
finding — it would need to already know to check `m21_5_scope.md`
first. Not restructured this session; flagged for whoever picks this up
next.

## Bucket 3 — Step 0 findings (Part B, same session)

**Full field enumeration** (every non-boolean `MoveData` field with a
real 1:1 or near-1:1 source equivalent, via the same
grep-`move_data.gd` technique Bucket 1 used, cross-checked
programmatically against `gen_moves.py`/`.tres` state — not accepted
from memory):

- **Excluded from this bucket** (own dedicated verification path
  already, or purely structural): `type`/`power`/`accuracy`/`pp`/
  `priority`/`category` (checked in nearly every test file's own
  spot-check table); `target` (NEW ITEM B/C's own full audits);
  `ban_flags` (`[M19.5]` Task 1); `effect` (confirmed via grep: **zero**
  occurrences anywhere in `gen_moves.py` — a vestigial schema field this
  project's `is_*`-flag dispatch architecture never actually populates
  or reads; not a live verification target).
- **Small fields, already individually audited by a dedicated prior
  session, reconfirmed via a direct move-count check this session** (no
  full value-level diff, per the task's own "just needs reconfirmation"
  framing) — all counts matched their known enumerated lists exactly,
  no new mover found for any of them: `weather_type` (5: Sandstorm/Rain
  Dance/Sunny Day/Hail/Snowscape), `second_type` (1: Flying Press),
  `overwrite_target_ability_id` (1: Worry Seed), `super_effective_vs_type`
  (1: Freeze-Dry), `double_power_status_arg` (5: Hex/Venoshock/Smelling
  Salts/Barb Barrage/Infernal Parade), `hp_cost_divisor` (3: Belly
  Drum/Fillet Away/Clangorous Soul), `charge_turn_defense_boost` (1:
  Skull Bash), `charge_turn_spatk_boost` (2: Meteor Beam/Electro Shot),
  `weather_heal_boost_type` (4: Morning Sun/Synthesis/Moonlight/Shore
  Up), `protect_method` (8: the full Protect family), `semi_inv_state`
  (6: Fly/Dig/Dive/Bounce/Shadow Force/Phantom Force), `strike_count>1`
  (15 fixed-hit-count moves), `extra_stat_change_stats` (32: the Bucket
  3 multi-stat family), `random_status_pool` (2: Tri Attack/Dire Claw),
  `secondary_effect_2`/`secondary_chance_2` (3: the Fang family).
- **Fully cross-referenced programmatically this session, extending
  Bucket 1's own hardened extraction script**: `critical_hit_stage`,
  `recoil_percent`, `drain_percent`, `fixed_damage`,
  `percent_current_hp_damage`. **0 real gaps found** across 21+13+13+2+2
  = 51 checked implemented moves with a nonzero source value.
- **NOT yet swept this session** (deliberately, see below):
  `secondary_effect`/`secondary_chance` and `stat_change_stat`/
  `stat_change_amount` — the two highest-value, highest-risk fields
  (hundreds of moves each; the exact field pair Steel Wing/Skull
  Bash/Bubble Beam's own display bugs and every real bug found so far
  in this whole M21.5 arc have come from).

**A genuinely new, significant methodology trap found and understood
before trusting any result**: Bucket 1's own extraction script handles
inline ternaries (`X >= GEN_N ? A : B`) and comment-stripping, but has
**no concept of C preprocessor `#if`/`#elif`/`#else` branches** — a
naive regex match can silently pick up a value from a DEAD branch that
isn't the one active at this project's real `GEN_LATEST=GEN_9` config.
Caught concretely: the sweep initially flagged **Struggle(165)** as
missing `recoil_percent=25` — but Struggle's source entry is genuinely
`#if B_UPDATED_MOVE_DATA >= GEN_4` (the active branch at this project's
config) using `.effect = EFFECT_STRUGGLE` / `MOVE_EFFECT_RECOIL_HP_25`
(a flat maxHP/4 recoil), with `.argument = { .recoilPercentage = 25 }`
living only in the INACTIVE `#elif B_UPDATED_MOVE_DATA >= GEN_2` branch
below it. Confirmed this project already implements Struggle's recoil
correctly via a wholly separate, dedicated code path
(`battle_manager.gd`'s `is_struggle` gate, `max_hp / 4`,
`[M15 Task 3]`) that has nothing to do with `recoil_percent` at all —
a false positive, not a bug. A follow-up check found only 2 of the ~30
fields checked so far (`criticalHitStage`, `recoilPercentage`) have ANY
occurrence inside a `#if...#endif` block anywhere in the whole reference
file, and the other (Sky Attack's `criticalHitStage`) turned out to be a
parser limitation, not a real ambiguity (a bare `COND >= GEN_N` boolean
expression assigned directly to an int bitfield, not a ternary — resolved
by hand: `8 >= 2` → true → 1, matching `gen_moves.py`'s already-correct
value). **`drain_percent`/`fixed_damage`/`percent_current_hp_damage` have
zero exposure to this trap** (confirmed via the same file-wide `#if`
containment check) — their 0-mismatch results stand fully trusted.
`secondary_effect`/`secondary_chance` and `stat_change_stat`/
`stat_change_amount`, by contrast, are exactly the fields where
Gen-specific `#if` branches are most likely to recur (chance/amount
values are a classic per-generation tuning target) — this needs to be
checked for EVERY match before trusting it, not assumed absent the way
it was safe to assume for the 3 small fields above.

**Stopping here, per the task's own explicit split-permission (item
9)**: `secondary_effect`/`secondary_chance` and `stat_change_stat`/
`stat_change_amount` need a genuinely more complex parser (extracting
structured `additionalEffects`/`STAT_CHANGE_EFFECT_PLUS`/`MINUS` blocks,
resolving nested moveEffect+chance+stat sub-fields, and now also
detecting/resolving `#if`/`#elif`/`#else` branches rather than assuming
a single unconditional value) applied across hundreds of moves each —
matching the scoping doc's own original "2-3 sessions" estimate for
this bucket, not a same-session mechanical pass. **Recommended natural
split point: a dedicated session for
`secondary_effect`/`secondary_chance` first** (the more consequential of
the two — every prior real bug found in this arc, Mega Punch aside, has
been in this exact field shape), then a second session for
`stat_change_stat`/`stat_change_amount`/`extra_stat_change_*`'s
cross-field consistency (do the extra-stat arrays' own lengths/values
match source's multi-stat blocks exactly, beyond the count-level check
already done above).

**Fix count this Bucket 3 partial pass: 0** — every field checked so
far (`critical_hit_stage`, `recoil_percent`, `drain_percent`,
`fixed_damage`, `percent_current_hp_damage`, plus the 15 reconfirmed
small fields) came back clean. No `gen_moves.py`/`.tres` changes made in
Part B. `docs/move_status_table.md` counts unaffected (717/217/0/0,
unchanged from Bucket 1's own confirmation, no move data touched this
session).

## Part A — Doc-organization fix (2026-07-16, follow-up session)

Confirmed this project's own established convention for "flagged, not
fixed" reasoning is scattered inline comments at the relevant move's own
`gen_moves.py` dict entry (dozens of existing examples: "deliberately
excluded", "flagged, not built", etc.) — NOT a single markdown doc
parsed by a script the way M19's own move-level exclusion list is
(`docs/m19_subtier_plan.md`'s Section C, read by
`gen_move_status_table.py`'s `parse_exclusions()`). That mechanism is a
different scope entirely (whole excluded MOVES, not individual fields
correctly absent on already-implemented moves) and isn't the right fit
here.

Added a single consolidated **"KNOWN NON-BUGS" index block inside
`gen_moves.py`'s own top-of-file docstring** — the one place any future
sweep session already opens first (it's the file every prior sweep in
this arc has edited directly). Lists all 6 non-bug findings from
Bucket 1 (dance_move's 11 moves, Bide's makes_contact,
Protect/Detect/Endure's ignores_protect, the 6 unreachable bounceable
moves, Spikes/Toxic Spikes/Stealth Rock's separately-flagged limitation,
Haze/Destiny Bond/Heal Bell's ignores_substitute) with the field name,
affected move(s), a one-line reason, and a pointer to this doc's own
Bucket 1 section for the full reasoning — an index, not a duplicate of
the writeup. Verified the file still parses and regenerates identically
(`python3 scripts/gen_moves.py` — 717 files, no diff beyond the 3
Part B fixes below).

## Part B — secondary_effect/secondary_chance + stat_change_stat/amount sweep (COMPLETE, same session)

Extended Bucket 1's hardened extraction script with the two capabilities
Bucket 3's own Step 0 flagged as needed: full `#if`/`#elif`/`#else`
preprocessor-branch resolution (a line-by-line flattener tracking a
branch-taken stack, evaluating each condition against this project's
real `GEN_LATEST=GEN_9` config — reused for every one of the 934 move
chunks, **zero unresolved conditions** across the whole file) and
structured block parsing (`.additionalEffects = ADDITIONAL_EFFECTS({...},
{...})`, brace-matched per sub-block, extracting `.moveEffect`/`.chance`/
`.self`/the 7 stat sub-fields — matching CLAUDE.md's own "Stat sub-field
enumeration" convention).

**Three genuine bugs found and fixed in the extraction script itself
before trusting any result** — each would otherwise have produced a
large batch of false positives:

1. `secondary_effect`/`secondary_effect_2` read via a bare-integer regex,
   but `gen_moves.py` stores these as symbolic constants (`SE_BURN`, not
   `1`) — produced **122 false-positive mismatches** on the first run
   (every punching/elemental move with a real, correct secondary status
   looked "missing"). Fixed by resolving `SE_*` names against the same
   integer table `move_data.gd` defines.
2. Stat sub-fields (`.defense`, `.spDef`, etc.) read via a bare-integer
   regex too, but source frequently expresses them as GEN-conditional
   ternaries (`.spDef = B_UPDATED_MOVE_DATA >= GEN_4 ? 1 : 0`) — produced
   3 more false positives (Acid, Crunch, Diamond Storm all "appeared"
   to have no stat block at all). Fixed by evaluating each sub-field
   through the same ternary resolver already used for scalar fields.
3. `.onChargeTurnOnly` `STAT_PLUS` blocks (Skull Bash/Meteor Beam/Electro
   Shot) were being compared against the generic `stat_change_stat`
   field, when this project deliberately uses the SEPARATE, already-
   audited `charge_turn_defense_boost`/`charge_turn_spatk_boost` fields
   for exactly this shape — excluded these blocks from the generic
   check (matching Bucket 3's own Step 0 finding, not a new discovery).

**Final result after all three fixes: exactly 3 real discrepancies
across every implemented move** (roughly 300+ moves carry a
`secondary_effect`/`stat_change` block) — a much smaller, cleaner result
than the scoping doc's own "hundreds of moves, 2-3 sessions" estimate
anticipated, which meant this bucket completed in the SAME session
rather than needing the proposed split:

1. **Rapid Spin(229) — confirmed real bug, the most consequential
   finding**: source's own `additionalEffects` block (gated `#if
   B_SPEED_BUFFING_RAPID_SPIN >= GEN_8`, TRUE at this project's config)
   is `MOVE_EFFECT_STAT_PLUS, .speed=1, .self=TRUE, .chance=100` — a
   guaranteed self Speed+1 on every hit. Checked `battle_manager.gd`'s
   `is_rapid_spin` dispatch directly: it ONLY clears hazards, with zero
   stat-boost logic anywhere. **Rapid Spin has never raised the user's
   Speed in this project**, despite this being real, active Gen8+
   behavior at this project's own `GEN_LATEST=GEN_9` target. Fixed via
   the pre-existing `[M19-secondary-stat-on-hit]` generic mechanism
   (`stat_change_stat`/`stat_change_self` set, `secondary_effect` left
   at `SE_NONE`) — the exact shape Torch Song(799) already uses, zero
   new dispatch code.
2. **Buzzy Buzz(681)/Sizzly Slide(682) — confirmed real bugs, an
   extraction-ambiguity case resolved by cross-checking a working
   precedent rather than guessing**: both had `secondary_chance=100` in
   `gen_moves.py`, but source omits `.chance` entirely for both (unlike
   Nuzzle(609), which explicitly sets `.chance=100`). Initially flagged
   as a genuine ambiguity (per the task's own item 5 category) since
   "always paralyzes/burns" flavor text could plausibly map to either
   convention — resolved by reading `MoveIsAffectedBySheerForce`
   directly (`(chance > 0) != sheerForceOverride`): an absent/0 chance
   with no override means Sheer Force does NOT apply, matching this
   project's own already-established "0 = guaranteed, Sheer-Force-
   exempt" convention (the Overheat/Draco-Meteor self-drop family) —
   and Nuzzle's own already-correct, already-shipped explicit-100 entry
   is direct proof this project's data model correctly represents both
   cases when the data is entered correctly. Not a judgment call left
   unresolved — a real, fixable, source-grounded correction.

**Test-audit-first pass**: grepped every scene file referencing these 3
moves. Found and fixed one real conflict — `m19_bucket2_test.gd`'s own
data-integrity table asserted `secondary_chance=100` for Buzzy
Buzz/Sizzly Slide (now corrected to 0, with a doc comment explaining
the Nuzzle-contrast reasoning). `m16d_test.gd`'s Rapid Spin checks
(power/accuracy/`is_rapid_spin`/`makes_contact`/category only) don't
touch `stat_change_stat` at all — no conflict.

**New runtime-behavior test coverage** (matching Bucket 1's own
just-established standard, not just data-integrity): new
`scenes/battle/bucket3_secondary_sweep_test.gd`/`.tscn`, 6 assertions —
Rapid Spin's real Speed+1 self-boost confirmed via a direct one-action
dispatch (plus a Tackle negative control); Buzzy Buzz's and Sizzly
Slide's Sheer-Force-exemption confirmed via direct
`AbilityManager.move_power_modifier_uq412` calls (holder vs. plain,
`==` not `>`), each paired with a **positive control using Nuzzle**
(the same Sheer-Force holder, same function call shape, genuinely DOES
get boosted) — proving the comparison itself can discriminate a real
boost from no boost, not just structurally incapable of ever showing
one. All 6 pass, stable across 5 reruns.

**Regenerated** `data/moves/move_0229.tres`/`move_0681.tres`/
`move_0682.tres` via `gen_moves.py`, then `docs/move_status_table.md` —
counts confirmed **unchanged**: 717/217/0/0 (a pure data-value fix,
not an implementation-status change).

**Regression**: targeted suites (`m16d_test`, `m19_bucket2_test`,
`m17a_test`, `m19_secondary_stat_test`, `move_smoke_test`) all clean.
Two full sweeps via `scripts/count_assertions.sh` from independent
process states: **134 files, GRAND TOTAL 13382 then 13381**, differing
only by `m17l_test.tscn` — a THIRD already-documented pre-existing
flaky suite from CLAUDE.md's own baseline note (distinct from
`doubles_test`/`m18q_test`/`m19a_gen1_test`, all of which surfaced
during Bucket 1's own verification session) — zero failures traceable
to this session's changes in either run.

**Part B is fully complete** — both fields swept end-to-end across
every implemented move, no further split needed. Combined with Part A,
Bucket 3 (as originally scoped in the earlier session) is now closed:
every non-boolean `MoveData` field with a real source equivalent has
either been fully cross-referenced (this session's 2 big fields plus
the prior session's 5 numeric scalars) or reconfirmed via move-count
against its own already-known enumerated list (the 15 small fields).

No commit made this session — per standing instruction, Rob commits.
