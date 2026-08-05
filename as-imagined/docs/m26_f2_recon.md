# M26F2 recon — Doubles AI-scoring gaps carried over from M24c

Written 2026-08-05. Recon only — no code written this session.

Scope per the roadmap: `_score_move_doubles`/`choose_action_doubles` never received
the `ai_flags` treatment `[M24c]` gave the singles-only `_score_move`/`choose_action`
path; RISKY/FORCE_SETUP_FIRST_TURN shipped narrow (a small bonus-scoring slice per
flag, not source's full ~15-25-case scope). Both to be reviewed and scoped for real
implementation or explicit further deferral.

Reference: pokeemerald-expansion, `battle_ai_main.c`/`battle_ai_util.c`/
`include/constants/battle_ai.h`, already cited throughout `trainer_ai.gd`'s own
Step-0-quality doc comments — re-verified directly, not re-derived from scratch.

---

## 0. TL;DR

1. **A bigger, more foundational gap sits upstream of the doubles question, found
   this session: `ai_flags` and `tier` are never actually derived from a real
   trainer's own data, in EITHER format.** `battle_screen_shared.gd`'s one call
   site builds `TrainerAI.new()` with `.tier = SMART` hardcoded and `ai_flags`
   left at its class default (`AI_FLAG_BASIC_TRAINER`) — `TrainerAI.from_trainer_data()`,
   the function `[M24c]` built specifically to read `TrainerData.ai_flags`, is
   **never called anywhere in production code** (confirmed via grep: its only
   caller anywhere in the repo is its own test suite). `set_trainer_data()` is
   called on the same code path (for money/items/portrait) but nothing connects
   it to the `ai` object. **Every real trainer battle today — Brock included,
   `[M27F]`'s own live arc — runs generic SMART-tier, Basic-Trainer-shaped AI,
   regardless of that trainer's real `ai_flags`.** This is worse than "narrow" —
   it's an active behavioral bug: 0 of the 854 real trainers use
   `AI_FLAG_SMART_SWITCHING` (`docs/m24_recon.md`'s own Step 0 finding, re-
   confirmed this session), so **every trainer battle in the game currently
   gets proactive smart-switching that literally no real trainer should have**,
   while simultaneously never getting the narrower flag combinations (640/854
   real trainers, 75%, are "Check Bad Move" ALONE — weaker than this project's
   own BASIC tier) that `[M24c]`'s whole session was built to represent.
2. **This wiring gap affects singles and doubles identically** — fixing only
   `_score_move_doubles`'s own gating (the roadmap's literal ask) without also
   fixing the wiring would still change nothing observable in real play, since
   neither path is ever handed real flags today. **The wiring fix is the
   prerequisite, not an optional extra**, and is cheap (a few lines at one call
   site) relative to everything else in this doc.
3. **The doubles-specific gap is real and independently confirmed**:
   `_score_move_doubles` runs all 3 BASIC-tier passes unconditionally (no
   `ai_flags` check at all), has no Pass 4 (`FORCE_SETUP_FIRST_TURN`) or
   Pass 5 (`RISKY`) equivalent, and doesn't use `_effective_ai_roll()` (so
   RISKY's "assume max damage" half is silently absent in doubles even once
   the flag itself is wired). Affects 77/854 real trainers (`Double Battle:
   Yes`).
4. **RISKY/FORCE_SETUP_FIRST_TURN's narrow scope is real and already
   accurately self-documented** in `trainer_ai.gd`'s own comments — 2 of
   source's ~15 RISKY cases ported (crit-stage bonus, self-faint), 1 of
   source's ~25 FORCE_SETUP_FIRST_TURN cases ported (plain self-targeted
   positive stat-change). Re-verified against source this session; the
   existing citations are accurate.
5. Proposed phasing: **F2a** (the wiring fix — actually call
   `from_trainer_data`, singles and doubles both benefit for free) → **F2b**
   (gate `_score_move_doubles`/`choose_action_doubles` on `ai_flags`,
   mirroring the singles path exactly, plus threading `_effective_ai_roll()`
   through) → **F2c** (optional: widen the RISKY/FORCE_SETUP_FIRST_TURN
   slice — a few more cheap, broadly-applicable cases, still not full
   parity). F2a+F2b are the roadmap's real ask; F2c is a genuine scope
   question for Rob, not assumed in either direction. ~1 session for F2a+F2b;
   F2c sized separately in §5.

---

## 1. The wiring gap (new finding, blocks any doubles fix from being observable)

### 1.1 What's built vs. what's called

- `TrainerAI.from_trainer_data(data: TrainerData) -> TrainerAI` (`trainer_ai.gd:97-100`):
  a plain identity copy, `ai.ai_flags = data.ai_flags`, `tier` left at its
  class default (`BASIC`) — correct by construction, since no real trainer's
  `ai_flags` ever implies `AI_FLAG_SMART_SWITCHING` (bit 14, `AI_FLAG(14)`,
  `include/constants/battle_ai.h:24`), confirmed absent from all 6 real
  combinations in `docs/m24_recon.md`'s own Step 0 table.
- The one place a battle actually starts (`battle_screen_shared.gd`, the
  `_ready()` overworld/setup-context branch, ~line 1667-1678):
  ```gdscript
  var opp_trainer_data: TrainerData = null
  if opp_trainer_key != "":
      opp_trainer_data = TrainerRegistry.get_trainer_by_key(opp_trainer_key)

  var ai := TrainerAI.new()
  ai.tier = TrainerAI.Tier.SMART
  _bm.set_trainer_ai(1, ai)
  _bm.set_human_controlled(0, true)
  _bm.battle_ended.connect(_on_battle_ended)
  if opp_trainer_data != null:
      _bm.set_trainer_data(1, opp_trainer_data)
  ```
  `ai` is built and attached **before** `opp_trainer_data` is even resolved to
  a non-null value in the reading order, and nothing downstream ever revisits
  it. `set_trainer_ai`/`set_trainer_data` (`battle_manager.gd:1090`/`1098`)
  are two completely independent setters — confirmed via direct read, neither
  references the other.
- Consequence, precisely: **every trainer battle reachable through the real
  overworld/script-VM path (`[M27F]` Stage 2 onward — every gym leader,
  every route trainer) runs with `ai_flags = AI_FLAG_BASIC_TRAINER` (7) and
  `tier = SMART`, regardless of what `gen_trainer_data.py` parsed for that
  trainer from `trainers.party`.** Brock's own real `AI:` line (whatever it
  is — not re-derived here, but it's one of the 6 known combinations, none of
  which is `SMART_TRAINER`-shaped) has never once been read by the AI that
  actually plays him.
- `TrainerAI.from_trainer_data()` has exactly one caller in the whole repo:
  its own direct-unit-test call site. It has shipped, tested, and unused in
  production since `[M24c]` (2026-07-18) — over 100 sessions of history
  later, still unwired.

### 1.2 Why this predates and subsumes the doubles-specific framing

The roadmap's own framing ("gaps carried over from M24c... 77/854 doubles-
format trainers") implicitly assumes the *singles* path already reflects
real per-trainer flags correctly and only doubles lags behind. **That
assumption is false for both formats equally** — the singles path's own
`ai_flags`-gated passes (`[M24c]`'s real work) are just as unreachable in
practice as the ungated doubles ones, because the `ai` object handed to
either function never carries anything but the hardcoded default. Framed
correctly: this isn't "doubles is behind singles," it's "neither format
is connected to real data yet, and doubles additionally lacks the gating
mechanism even once it is."

### 1.3 One real edge case worth flagging before F2a, not solving here

`gen_trainer_data.py`'s `resolve_ai_flags("")` (no `AI:` line at all,
16/854 real trainers per `docs/m24_recon.md`) returns `flags = 0` — every
one of `_score_move`'s three gated passes would be skipped, degrading to
`_pick_best` breaking ties across every move at the flat `AI_SCORE_DEFAULT`
(effectively a random/first-move pick with no real logic). Not necessarily
wrong — but worth a deliberate check against source (does vanilla ever
leave a trainer with a genuinely empty AI flag set, or does this reflect an
extraction gap in those 16 records specifically?) before F2a ships, rather
than silently inheriting whatever the data pipeline currently produces.

---

## 2. The doubles-specific scoring gap, confirmed directly against source

### 2.1 `_score_move_doubles` (`trainer_ai.gd:537-594`) vs. `_score_move` (`:376-517`)

| | `_score_move` (singles) | `_score_move_doubles` |
|---|---|---|
| Pass 1 (bad-move/type-immunity) | Gated on `AI_FLAG_CHECK_BAD_MOVE` | **Always runs**, ungated |
| Pass 2 (fastest/slowest KO) | Implicit in `_apply_best_damage_move`, itself gated on `AI_FLAG_CHECK_VIABILITY` at the singles call site (`choose_action:286`) | **Runs unconditionally** at the doubles call site (`choose_action_doubles:217`, no gate at all) |
| Pass 3 (status-move viability: Toxic/Burn/Paralysis/Sleep) | Gated on `move.category==2 and defender.status==NONE` (itself only reached inside the function body, but the whole pass composes with Pass 1's gate) | Present, same conditions, but the ENCLOSING function has no `ai_flags` check anywhere |
| Pass 4 (`FORCE_SETUP_FIRST_TURN`) | Gated on `AI_FLAG_FORCE_SETUP_FIRST_TURN and is_first_turn` | **Absent entirely** — no equivalent code exists |
| Pass 5 (`RISKY`, crit/self-faint) | Gated on `AI_FLAG_RISKY` | **Absent entirely** |
| Damage-roll assumption (`_effective_ai_roll()`, RISKY's "assume max damage" half) | Used in `_can_attacker_ko_defender` (called from Pass 3's `can_faint` checks) | `_score_move_doubles` computes its own KO check inline (`result["damage"] >= defender.current_hp`) via a **raw `DamageCalculator.calculate(..., _force_roll, _force_crit, ...)`** call, never routed through `_effective_ai_roll()` — RISKY's roll-assumption bonus would be silently absent even after F2a/F2b wire the flag itself, unless this call site is also updated |

Net: `_score_move_doubles` is a genuine, hand-maintained second copy of most
of `_score_move`'s body (Passes 1/3 duplicated near-verbatim, confirmed via
direct comparison of the `match move.secondary_effect:` blocks — byte-for-
byte identical conditions and score deltas), missing Passes 4/5 outright and
silently bypassing the one existing roll-forcing seam Pass 3's own KO check
depends on.

### 2.2 `choose_action_doubles` itself (`:150-233`)

Already correctly threads `tier == SMART` for the proactive-switch check
(mirroring singles) and already has the `[M25a]`/`[M21]` doubles-specific
correctness fixes (ally-slot exclusion, live-opponent counting, spread-move
reduction) — **those are unrelated to `ai_flags` and are not in scope for
this item**, cited here only to be clear they don't need touching. The gap
is scoped precisely to the move-scoring function it calls, `_score_move_doubles`,
and the missing item-use check: `_maybe_ai_use_item` (`battle_manager.gd:1448`,
`[M24b]`'s battle-item AI) is called before EITHER `choose_action`/
`choose_action_doubles` at the `BattleManager` call site — confirmed already
shared correctly between formats, not a gap.

---

## 3. RISKY/FORCE_SETUP_FIRST_TURN's real full scope, re-verified against source

Both are already accurately self-documented in `trainer_ai.gd`'s own comments
(lines 473-517) — re-checked against `battle_ai_main.c` directly this session
rather than trusted at face value, and found accurate:

- **`AI_ForceSetupFirstTurn`** (`battle_ai_main.c` L5905-5959): a `switch` over
  ~25 distinct `EFFECT_*` values (Conversion, Light Screen, Focus Energy,
  Confuse Ray-style, Reflect, non-volatile-status infliction, Substitute,
  Leech Seed, Curse, Swagger, Camouflage, Yawn, Torment, Ingrain, Imprison,
  Acupressure, the 4 terrain moves, Stealth Rock, Toxic Spikes, Trick Room,
  Wonder Room, Magic Room, Tailwind, Tidy Up, Sticky Web, weather-setting,
  Ceaseless Edge, Stone Axe). This project ports exactly one shape: a plain
  self-targeted positive stat-change status move (`stat_change_self and
  stat_change_amount > 0`) — genuinely the single most common and cleanly-
  detectable case (Swords Dance/Bulk Up/Calm Mind/Growth-style), but real
  source also gives the identical bonus to screens, hazards, Trick Room, and
  several other already-implemented mechanics this project's own move roster
  supports.
- **`AI_Risky`** (`battle_ai_main.c` L5966-6040+): ~15 further move-EFFECT-
  specific cases beyond the two ported (elevated crit stage, self-faint) —
  Memento, Revenge, Belly Drum, Clangorous Soul, Reflect Damage (Counter/
  Mirror Coat/Metal Burst family), and others, each with its own HP%/stat
  condition. None of these are ported; the two kept are, per the existing
  comment, "the cheapest, most broadly applicable, and most easily verified."

**Neither of these being narrow is itself a bug** — it's a disclosed,
deliberate scope decision from `[M24c]`, matching that whole tier's own
"narrow slice, not full engine parity" philosophy (the same discipline
applied throughout M17-M19's ability/move work). The question for this
session is whether to *widen* the slice now, not whether the narrowing was
wrong.

---

## 4. What this item does NOT touch (confirmed, not assumed)

- `_should_switch`/`_best_switch_target`/`choose_replacement` — SMART-tier
  switch logic, unrelated to per-move scoring; already correctly shared
  between formats and already carries the real `[M21]`/`[M25a]` doubles
  aliasing fixes.
- `_maybe_ai_use_item`/`should_use_item` — `[M24b]`'s battle-item AI, already
  format-agnostic (called once per combatant regardless of `_active_per_side`).
- `_apply_best_damage_move` — already takes an `is_spread_active` parameter
  and is called correctly from both `choose_action`/`choose_action_doubles`;
  its own doc comment's list of deliberately-omitted tiebreakers is unrelated
  to `ai_flags` and out of scope here.
- Doubles-specific *targeting* correctness (which of 2 opponent slots to hit)
  — already built and tested (`choose_action_doubles`'s own per-slot scoring
  loop, `m17n10_test`-adjacent doubles tests). Not touched by adding `ai_flags`
  gating to the score computed for each candidate.

---

## 5. Scope

### In scope

1. **F2a — the wiring fix.** At the one real call site
   (`battle_screen_shared.gd`, the setup-context branch), replace the
   hardcoded `TrainerAI.new()` + `.tier = SMART` with
   `TrainerAI.from_trainer_data(opp_trainer_data)` when `opp_trainer_data !=
   null`, falling back to the existing hardcoded construction only for the
   no-trainer (wild/simulator) case — matching the existing "no trainer
   attached → no special resources" precedent already established there for
   items/money (`[M26l]`'s own "Passing nothing is the smaller diff AND the
   correct semantics" note). Resolve §1.3's edge case (16 zero-flag
   trainers) as part of this phase, not silently inherited.
2. **F2b — doubles `ai_flags` gating**, mirroring the singles path exactly:
   gate `_score_move_doubles`'s Pass 1/2/3 on `AI_FLAG_CHECK_BAD_MOVE`/
   `AI_FLAG_CHECK_VIABILITY` the same way `_score_move`/`choose_action` do;
   port the SAME narrow Pass 4/Pass 5 slices already in `_score_move` (not a
   wider one — matching whatever F2c decides, see below) so singles and
   doubles carry identical scope, not two independently-drifting narrow
   slices; route the doubles KO check through `_effective_ai_roll()` instead
   of a raw `_force_roll` pass-through.
3. Tests: a direct test proving `from_trainer_data` output is what actually
   reaches a real battle (not just that the function itself is correct — it
   already has that coverage); doubles-format tests mirroring every existing
   singles `ai_flags`-gating test 1:1 for the narrower combinations; the
   `_effective_ai_roll()` threading confirmed via a discriminating case.

### Out of scope / deferred to F2c (decision needed, §6)

Widening RISKY/FORCE_SETUP_FIRST_TURN's ported case list beyond what
`_score_move` already has — genuinely optional, sized separately below, not
assumed as part of F2a/F2b.

---

## 6. Proposed phasing

| Phase | Content | Size |
|---|---|---|
| **F2a** | Wire `from_trainer_data` into the real call site; resolve the 16-zero-flag edge case | 0.5 session |
| **F2b** | Gate `_score_move_doubles`, port the SAME narrow Pass 4/5 slice singles already has, fix the roll-assumption threading | 0.5-1 session |
| **F2c** (optional) | Widen RISKY/FORCE_SETUP_FIRST_TURN's ported case list — a handful of additional cheap, broadly-applicable EFFECT_* cases (e.g. screens/hazards for Pass 4; Belly-Drum-style HP-cost setup moves for Pass 5), still not full ~15/~25 parity | 0.5-1 session, separately scoped once F2a/F2b ship and Rob decides whether it's wanted |

### Decisions needed (Rob)

1. **F2a confirmed?** This is the highest-leverage, lowest-cost fix in this
   doc and arguably shouldn't wait on the doubles question at all — every
   real trainer battle in the currently-playable slice (`[M27F]` onward) is
   affected today, in singles just as much as doubles.
2. **F2b's Pass 4/5 scope**: port the exact same narrow slice singles has
   (recommended — keeps the two formats in sync, avoids two independently-
   drifting "narrow but different" scopes) vs. widen both at once as part of
   F2b rather than deferring to a separate F2c.
3. **F2c**: pursue widening RISKY/FORCE_SETUP_FIRST_TURN now, defer
   indefinitely, or fold into F2b per decision 2 above.
4. **The 16-zero-`ai_flags`-trainer edge case (§1.3)**: worth its own quick
   source check before F2a ships, or acceptable to inherit the data
   pipeline's current output (effectively random move choice for those 16)
   as a disclosed, low-stakes gap?
