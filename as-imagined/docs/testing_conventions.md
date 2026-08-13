# Testing conventions — the full worked examples

Extracted from `CLAUDE.md` during the 2026-08-13 housekeeping pass.
`CLAUDE.md` keeps the one-line checklist; this file keeps each convention's
full reasoning, the milestone(s) it cost, and the worked example of the test
that broke. Every convention here was written after a real bug — treat each as
a known risk from the *first draft* of any new test, not as something to catch
reactively after a false pass slips through.

Verbatim from `CLAUDE.md`, only relocated.

## Testing conventions

Every convention in this section was written after a real bug, and each one
names the milestone(s) it cost. They are recorded here rather than
re-discovered per milestone. Treat each as a known risk from the *first draft*
of any new test, not as something to catch reactively after a false pass slips
through.

### Testing convention: snapshot via signals, not post-battle state

  This bit M16c and M16d independently (see `docs/decisions.md`), so it's
  captured here as a permanent rule rather than something each milestone
  re-discovers.

  Any Pokémon whose only available move is a **repeatable** effect — a
  side-condition/hazard-setter that can legitimately be re-cast after its
  effect naturally expires or gets cleared, or a toggle like Trick Room — will
  keep re-triggering once the turn's action queue drains and auto-select
  falls back to `moves[0]`, for as many turns as the test battle runs. A test
  Pokémon with no other move WILL cast that move again.

  Consequence: any assertion about "what happened after one specific action"
  must **never** read state (`_side_conditions`, `trick_room_turns`,
  `attacker.stat_stages`, etc.) after `start_battle()` fully returns — by then
  the battle may have run many more turns than intended, re-triggering,
  re-expiring, or re-toggling the exact state under test. Instead, snapshot
  the state by connecting to the relevant signal (`screen_set`,
  `hazard_set`, `trick_room_set`, `move_executed`, etc.) and capturing the
  value at the precise moment the signal fires — guarded to the first
  matching occurrence if the signal could plausibly fire more than once
  during the battle.

  Applies to every future milestone that introduces persistent/toggleable
  battle state (side conditions, field conditions, per-Pokémon volatiles) —
  see `docs/decisions.md`'s `[M16c]`/`[M16d]` entries for worked examples of
  tests that broke this way and how they were fixed.

### Testing convention: lambda-captured scalars are snapshots, not references

  This has already caused real bugs in M16c, M16d, M16e, and M17a — treat it as
  a known, recurring risk from the first draft of any new test, not something
  to catch reactively after a false pass slips through.

  GDScript lambdas capture local variables **by value, at the moment the
  lambda is defined** — not by reference. If a test connects a signal to a
  lambda that reads a local scalar (`int`/`bool`/`float`/`String`), and the
  lambda body then assigns to that variable, the assignment mutates a private
  copy inside the closure. The outer variable the test later reads never
  changes.

  This is dangerous in exactly the same "silent until it isn't" way as the
  signal-snapshot pitfall above: the test still runs, still prints a result,
  and often still passes — a positive-case assertion checking "did this stay
  false" trivially passes even when the mechanism under test is completely
  disconnected, because the outer variable was never going to change anyway.
  The bug only surfaces when a negative-case or discriminator assertion needs
  the captured value to actually flip, which is exactly what happened in
  M17a's Rock Head recoil test: the positive case (no recoil should fire)
  passed for the wrong reason, and only the negative case (recoil SHOULD fire
  for a non-Rock-Head attacker) failed and exposed that the signal handler's
  mutation was never reaching the outer scope.

  Fix: wrap the value in a single-element `Array` and mutate/read index `0`.
  Arrays are captured by reference, so mutations inside the lambda are visible
  to code outside it that holds the same Array.

  ```gdscript
  # WRONG — outer `fired` never becomes true, no matter what the signal does.
  var fired := false
  bm.recoil_damage.connect(func(mon, amount): fired = true)
  bm.start_battle(atk, def)
  _chk("recoil fired", fired == true)   # false pass/fail regardless of behavior

  # RIGHT — Array wrapper is captured by reference.
  var fired := [false]
  bm.recoil_damage.connect(func(mon, amount): fired[0] = true)
  bm.start_battle(atk, def)
  _chk("recoil fired", fired[0] == true)
  ```

  Applies to every test that connects a signal to a lambda and expects the
  lambda to communicate a result back to the enclosing test function — see
  `docs/decisions.md`'s `[M17a]` entry for the worked example of a test that
  broke this way and how it was fixed.

### Testing convention: type immunity precedes ability logic

  This has already caused real bugs in M17b and M17c — treat it as a known,
  recurring risk from the first draft of any new test involving a damaging
  move, not something to catch reactively after a misleading pass or fail
  slips through.

  Type effectiveness is checked before any ability/item logic gets a chance to
  run (see `DamageCalculator.calculate`'s early-return on `effectiveness ==
  0.0`). If a test scenario picks an attacker/defender type pairing that is a
  flat 0× immunity — not just a resistance — for the move being used, the hit
  never connects, damage is always 0, and the ability or item under test never
  actually executes its logic. The scenario looks plausible (a Ghost-typed
  defender to test a Ghost-related damage modifier, a Ground-type move against
  a Flying-type/Levitate holder to test a stat interaction) but is untestable
  by construction.

  This is dangerous in exactly the same "silent until it isn't" way as the two
  conventions above: the test still runs, still produces a result, and can
  still pass or fail in a way that looks reasonable — an assertion comparing
  "modified damage" against "baseline damage" can trivially pass at `0 == 0`
  even though the mechanism under test never fired. The bug only surfaces when
  the assertion actually needs a nonzero difference to hold, which is exactly
  what happened in M17b's Purifying Salt test (a Normal-type defender used to
  measure Ghost-type damage halving — Normal-types are outright immune to
  Ghost-type moves, unrelated to Purifying Salt, so the measured damage was 0
  regardless of the ability) and M17c's Cursed Body integration test (a
  Ghost-type holder hit by a Normal-type move — the same flat immunity, this
  time blocking the hit-reactive dispatch from firing at all).

  Fix: before writing any test scenario involving a damaging move, explicitly
  check the attacker's move type against the defender's type(s) against this
  project's own `TypeChart` and confirm effectiveness is nonzero — don't rely
  on a type pairing "sounding" safe. Unless the mechanism under test is itself
  type-specific, default to a neutral (1×) matchup chosen to have no side
  effects on the mechanic being isolated — the same one-variable-at-a-time
  discipline already used throughout this project's test suites.

  Applies to every test that measures damage, a damage modifier, or a
  hit-reactive effect through an actual `DamageCalculator.calculate` call or a
  full battle — see `docs/decisions.md`'s `[M17b]` and `[M17c]` entries for the
  worked examples of tests that broke this way and how they were fixed.

### Testing convention: pairwise damage comparisons must force every RNG input

  Any test that asserts one damage value is greater than, less than, or equal to
  another (not just "damage > 0") must explicitly force BOTH
  `BattleManager._force_roll` AND `_force_crit` on every scenario being compared — not
  just the roll, and not just on one side of the comparison. A comparison with only
  partially-forced RNG will pass most of the time and fail intermittently whenever
  an unforced crit or roll variance closes or inverts the gap the assertion expects.

  This has caused two confirmed intermittent failures so far: `[M17n-2]`'s original
  damage comparison (forced roll but not crit) and `[M17l]`'s Friend Guard comparison
  (forced neither). Both were fixed by explicitly setting `_force_roll` and
  `_force_crit = false` (or specific values, as appropriate) on every scenario in the
  comparison before running the battle. Treat any new pairwise damage comparison as
  suspect until both are confirmed forced.

### Testing convention: force_crit bypasses crit-STAGE math, only controls the
### final outcome

  `BattleManager`'s `force_crit` seam does not run `DamageCalculator._roll_crit`'s
  stage-calculation logic — it short-circuits directly to a crit/no-crit outcome.
  This means `force_crit` is USELESS for testing anything about how a crit stage is
  computed: ability-based bonuses (e.g. Super Luck), item-based bonuses (e.g. Scope
  Lens/Razor Claw), move-specific base crit stages, Focus Energy's +2, or how
  multiple simultaneous bonuses sum together. This is distinct from the pairwise-
  comparison convention above — that one is about forcing BOTH roll and crit for a
  damage-value comparison; this one is about crit-STAGE math not being reachable via
  `force_crit` at all, for any purpose.

  For testing crit-STAGE math specifically: call the stage-calculating function(s)
  directly (e.g. `AbilityManager`'s ability-bonus lookup, `ItemManager.
  crit_stage_bonus`, or `DamageCalculator._roll_crit`'s stage-summing logic itself)
  rather than running a full battle turn with `force_crit` — this is fully
  deterministic and requires no RNG forcing at all.

  For testing the resulting crit RATE specifically (e.g. proving two bonuses sum
  additively rather than one overriding the other, which stage-level unit testing
  alone cannot distinguish) — use a statistical sample (n=5000 or similar, matching
  the precedent set by `[M17n-5]` and `[M18e]`) rather than attempting to force a
  single deterministic case, since `force_crit` cannot isolate stage-composition
  behavior.

  Discovered independently twice: `[M17n-5]` (Super Luck) and `[M18e]` (Scope
  Lens/Razor Claw + item/ability composition). Treat any future crit-stage-related
  test as needing this approach from the first draft, not as something to discover
  via a failed `force_crit` attempt.

### Testing convention: aggregating across an uncontrolled number of battle
### turns breaks both absence checks and rate measurements

  `start_battle_with_parties` runs the FULL multi-turn battle to completion, not a
  single turn. Any test that reads accumulated signal events across the whole
  battle — rather than isolating a single, well-defined event or a fixed,
  explicitly-controlled number of trials — silently varies its own sample size with
  however many turns the battle happens to take. This breaks in both directions:

  - **Absence checks** ("X never happens"): scoping too broadly can MASK a real
    violation. `[M17l]` found this first — two "never hit" assertions read events
    accumulated across the whole battle rather than the specific queued turn-1
    action, and passed even when a later-turn retarget (after the original redirect
    target fainted) legitimately produced a hit that should have been distinguished
    from the turn-1 case under test. Fixed by filtering to each attacker's first
    recorded event. The same shape recurred in `[M17j]`'s `switch_test.tscn`
    (checked and ruled out that time, not re-fixed) and `[M17n-4]`'s Color Change
    re-trigger test (a queue-drained auto-reselect produced an unplanned 3rd event).

  - **Rate measurements** ("X happens Y% of the time"): aggregating "did this occur
    ANYWHERE in the battle" over an uncontrolled number of turns compounds a
    per-turn probability across however many turns elapse, badly overstating the
    true per-event rate. `[M18k]` found this independently, on this side: a
    statistical check forcing King's Rock's own roll to `true` on a Rock-Slide user
    (native flinch chance 30%) measured "did a flinch happen anywhere in the
    battle" and observed **69.3%** against an expected ~30% band — several turns'
    independent 30% chances compounding into "at least one hit" rather than
    reflecting the single per-turn rate. Fixed by recording a combined
    `move_executed`/`move_skipped` timeline per trial and measuring only the
    target's very first action attempt — a single clean per-turn sample.

  Both directions are the same underlying failure mode: an uncontrolled or variable
  number of opportunities standing in for what the assertion actually means to
  measure. When a test needs "did/didn't happen" or "happens at rate X" and the
  battle will run more than one turn, explicitly isolate the event (queue exactly
  the actions under test and read the first matching signal, or otherwise pin down
  which turn/trial is being measured) rather than trusting an aggregate over
  however many turns the battle happens to run.

### Convention: check current_hp > 0, not .fainted, for synchronous
### within-function aliveness checks

  BattlePokemon's `fainted` flag is only set during a separate, later FAINT_CHECK
  phase — it is NOT synchronously true the instant a Pokémon's HP reaches 0 within
  the same function call that reduced it. Any code that needs to know "is this
  Pokémon still alive RIGHT NOW, in this same execution" (e.g. a retaliation effect
  checking whether its target survived, a forced-switch item checking whether the
  attacker is still around) must check `current_hp > 0` directly, not `.fainted` —
  the flag will read as false-negative-safe (not yet marked fainted) even for a
  Pokémon that has already reached 0 HP moments earlier in the same call stack.

  This is an implementation-correctness issue, not a testing-methodology one — unlike
  the conventions immediately above and below it, the risk here is a real production
  bug (a mon treated as alive/eligible when it has already died this execution), not
  a flawed assertion. It's grouped with the other conventions in this section only
  because it was discovered and re-discovered through the same test-writing process.

  Discovered: `[M18d]` (Jaboca/Rowap). Independently violated despite that precedent
  being available: `[M18n]` (Red Card/Eject Button's first draft, caught by its own
  test on the first run). Treat this as a standing implementation checklist item for
  any new "does the other Pokémon still exist/qualify" check, not something to
  rediscover per tier.

### Testing convention: manual assertion-total recounts must account for
### `scenes/battle/integration_test.tscn`'s different print format

  Root-caused during a dedicated diagnostic session (2026-07-06) after this exact
  24-assertion gap recurred at least three times (`[M17f]`, `[M17g]`, `[M17n-7]`) with
  every prior occurrence resolved by shrugging and adopting whichever fresh number
  turned up, without investigating why. It's not test flakiness and it's not a real
  regression — it's a blind spot in every ad-hoc recount script written so far.

  Every suite in this project prints its result in one of two formats:
  `"<suite_name>: N/M passed"` (the majority) or `"Results: N passed, M failed"`
  (`damage_test`/`move_test`/`stat_test`/`status_test`, an older style). **One file,
  `scenes/battle/integration_test.tscn` (24 assertions, added by the "Prompt 9"
  commit — predates the M1-M17 milestone-numbering convention entirely), prints a
  third, distinct format: `"Integration tests: N passed, M failed"`** (see
  `integration_test.gd`'s own `_ready()`). Any recount that pattern-matches only the
  two known formats — which is every recount performed so far, including the one that
  produced this session's own "2160" figure before this note was added — silently
  drops this file's 24 assertions from the total. Compounding the blind spot,
  `integration_test.tscn` has never been listed in this file's own "Current status" or
  "Verification scenes" sections, so nothing here points a reader toward checking for
  it specifically.

  The direction of the drift has flipped sign across occurrences depending on which
  informal method a given session happened to use — `[M17f]`'s recount was 24 HIGHER
  than the stale prior figure (that session's method happened to catch this file,
  correcting an even older undercount), while `[M17g]`'s and `[M17n-7]`'s recounts were
  each 24 LOWER than the documented total (those sessions' methods missed it). The
  suite itself has never regressed or flaked — `integration_test.tscn` has run clean
  at 24/24 every time it's been included in a sweep at all.

  **When manually recounting total assertions across all `.tscn` files, always
  include `integration_test.tscn`'s count explicitly** (read its own `N/M passed`-style
  line by eye, or extend any grep/regex to also match `"Integration tests: (\d+)
  passed"`) — do not trust a recount that only searches for the two documented
  formats. If a fresh recount disagrees with the carried-forward total by exactly (or
  close to) 24, check this file first before assuming generic documentation drift.

  A larger, not-yet-implemented follow-up worth Rob's prioritization: either
  standardize every suite's final print line on one format (`"<name>: N/M passed"` is
  the majority convention already), or write a single canonical counting script
  checked into the repo (e.g. `scripts/count_assertions.sh`) that every session runs
  instead of ad-hoc grep, so this class of drift structurally can't recur. Not
  implemented in this session — diagnostic only, per Rob's explicit instruction.

### Testing convention: baseline-total verification requires two independent
### methods, cross-checked, run twice — no single number is trusted on its own

  This specific number (total assertions across all `.tscn` suites) has now been
  gotten wrong at least six times in a row — `[M17f]`, `[M17g]`, the M17n-7 recovery
  session, the "2179" figure, a "2160, all formats counted correctly" claim, and a
  "2222, two formats counted" claim — each one asserted with apparent confidence and
  each one wrong in a way the next session had to re-discover. A dedicated
  verification session (2026-07-06) finally proved a number instead of asserting one,
  and that process is now the standard, not a one-off.

  `scripts/count_assertions.sh` is the canonical counting script (see the note above
  for the format-recognition bug it exists to fix). But **a script's own self-reported
  total is not sufficient evidence on its own**, given this exact number's track
  record — it must be cross-checked against a second, independently-derived method
  before being trusted as a baseline:

  1. Run `scripts/count_assertions.sh` against a fresh full sweep.
  2. Independently derive each file's true assertion count by instrumenting a
     **throwaway scratch copy** of its `.gd` file (never the real committed file) so
     every assertion helper (`_chk`/`_check_exact`/`_check_range`/etc. — confirm the
     actual helper name(s) per file, several older files use different names) prints
     on PASS too, not just FAIL, then running it and counting total PASS+FAIL lines
     directly. A plain static `grep`/regex count of assertion-helper call sites in
     source is **not sufficient by itself** — it systematically diverges from the
     true runtime count whenever a file contains an `if`/`else` branch where only one
     side's assertion(s) actually execute (dead-code guards like `if ability == null:
     _chk(...skip..., false)` are common in this codebase's older suites), or a loop/
     wrapper function that calls the helper a variable number of times from one
     static call site. Any static-count mismatch must be individually root-caused
     (which specific branch or loop, and why) before being dismissed — never averaged
     away or assumed to be a rounding artifact.
  3. Confirm both methods produce the exact same total.
  4. Re-run the full sweep from a clean process state (`pkill -9 -f "Godot.*--headless"`
     first) a second time and confirm the identical total both times.

  Only once all four steps check out cleanly should a total be stated as verified.
  The last confirmed-this-way total was **2246 across 41 `.tscn` files** (2026-07-06)
  — see `docs/decisions.md`'s `[M17n-7]` follow-up entry for the full per-file
  reconciliation. Any future session that needs to state a new baseline (after adding
  or removing a suite) must repeat this full process, not extrapolate from the prior
  confirmed number plus an assumed delta.

### Sweep-total interpretation: a meaningful shortfall is a regression, a tiny one may be noise

  [This replaces a dated baseline snapshot ("121 files / GRAND TOTAL 12693")
  and its attached list of specific flaky suites, both retired 2026-07-26 as
  superseded — later confirmed totals are far higher, and naming individual
  suites froze a list that was already stated to be non-exhaustive. The
  procedure below is what actually carried forward; the numbers did not.]

  This codebase contains several independent statistical/aggregation-flaky
  test suites — ones whose assertions depend on an RNG sample or on how many
  turns a battle happened to run. **Any one of them may intermittently shave
  1–3 assertions off a sweep total, and which ones flake varies run to run.
  That is expected background noise, not a regression.**

  How to read a sweep total against the last confirmed one:

  - **Short by ~1–3, in a suite already known to be statistical** — treat as
    noise. Confirm by rerunning that suite alone; a flake passes clean on a
    rerun with no code change.
  - **Short by meaningfully more than that, or a failure in any suite that is
    NOT of the statistical/aggregation kind** — treat as a real regression,
    not sweep noise. Do not adopt the lower number as a new baseline.
  - **Any new suite found to flake this way** — record it where the current
    baseline is recorded, rather than re-diagnosing it from scratch next
    session.

  The standing anti-pattern this exists to prevent: a session sees a total
  lower than expected, shrugs, adopts the fresh number as the new truth, and
  the next session inherits an unexplained drop as its baseline. **Never adopt
  a lower total without root-causing the difference first.**

### Testing convention: GDScript string-concatenation-then-format binds `%`
### only to the trailing literal, not the full concatenated string

  Discovered during `[M18.5d Phase 2]`: `"a" + "b %d" % [x]` does NOT format
  across the whole string — GDScript's `%` operator has higher precedence than
  `+`, so it binds only to the immediately adjacent string literal on its
  right, silently ignoring everything concatenated before it. This produced a
  runtime error ("not all arguments converted during string formatting") on
  the FIRST test run of a new file, not a silent wrong-value bug — but a
  differently-shaped version of this same mistake (e.g. one fewer format arg
  than expected) could produce a silently wrong assertion label instead of a
  hard error.

  Correct forms:
  ```gdscript
  "a" + ("b %d" % [x])          # parenthesize the formatted portion explicitly
  ("a" + "b %d") % [x]          # or format the fully-concatenated string once
  ```

  This is a language-level operator-precedence gotcha, not a repeat of the
  whole-battle-aggregation or wrong-signal-name pitfalls — a genuinely new
  class for this codebase. Treat any test-file diff containing BOTH `+`
  string concatenation AND `%` formatting on the same statement as worth a
  second look before running, not just after a failure.

### Testing convention: a wide regression sweep must grep pass/fail broadly,
### not for one fixed keyword

  Discovered during `[M18.5h-1]`: most suites in this codebase print
  `print("FAILED")` on a failing run (this project's dominant `_chk`-style
  convention), but at least 5 — `stat_test.gd`, `move_test.gd`,
  `status_test.gd`, `damage_test.gd`, `integration_test.gd` — instead print
  `"=== Results: X passed, Y failed ==="`, a format that never contains the
  literal word `FAILED` at all. A wide sweep that greps only for `"FAILED"`
  will silently miss any real failure in one of these 5 files, no matter how
  many times it's rerun. `[M18.5h-1]`'s own regression sweep grepped for
  `"FAILED"` across 4 full 75-suite iterations before this gap was caught —
  3 genuinely broken suites (`damage_test`/`move_test`/`status_test`) passed
  every one of those 4 sweeps undetected, purely because of the print-format
  mismatch, not because they were actually passing.

  For any future wide regression sweep: grep case-insensitively for
  `passed|fail` (or similarly broad), not a single fixed keyword — and cross-
  check a suite's own reported X/Y or "X passed, Y failed" numbers agree,
  not just that some matching line was present. Confirm which format a given
  suite uses with `grep -l "passed, .*failed" scenes/battle/*.gd` before
  trusting a keyword-only sweep result.

### Stat sub-field enumeration (moves_info.h stat-change blocks)

  When counting or extracting which stats a move's `STAT_CHANGE_EFFECT_PLUS`/
  `MINUS` block touches, the exhaustively-verified ground truth is exactly 7
  field names, no more, no fewer: `attack`, `defense`, `spAtk`, `spDef`,
  `speed`, `accuracy`, `evasion`. (Confirmed by scanning every field name
  appearing inside any stat-change block in `moves_info.h` directly — not
  assumed from memory.)

  Two distinct failure modes have hit this in practice and must both be
  guarded against:
  1. Using an incomplete or mis-cased field list (e.g. `spAttack`/`spDefense`
     instead of `spAtk`/`spDef`) when hand-rolling a one-off classifier.
  2. Counting `STAT_CHANGE_EFFECT_PLUS`/`MINUS` *token occurrences* rather
     than *distinct nonzero sub-fields within one block* — a single
     stat-change block with one token can still set multiple stat sub-fields
     at once (Calm Mind: +1 spAtk, +1 spDef from one token), which
     token-counting alone will silently miss.

  Correct methodology: brace-match to the enclosing block, then count
  distinct nonzero sub-fields found within that block — not tokens.

  `[M19-secondary-stat-audit]` found that a suspected third recurrence of
  issue (1) was actually a different, more consequential problem: a
  detected-but-never-reconciled gap, where a scratchpad classifier correctly
  flagged 41 multi-stat moves but a later manual reclassification pass only
  acted on 8 of them. When a classifier script produces a candidate list,
  confirm downstream steps actually consume the full list before treating
  the candidates as resolved.
