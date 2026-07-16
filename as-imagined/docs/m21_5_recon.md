# M21.5 — Move Effect Review, Session 1: move_status_table.md Accuracy Audit

**RECON ONLY — no implementation this session.** Added 2026-07-16, at
Rob's request after spot-checking `docs/move_status_table.md` and
flagging 3 suspicious entries. This is a genuinely new milestone
(M21.5), not an M21 sub-item — kept as its own document per explicit
instruction, not appended to `docs/m21_recon.md`.

## Overview

Rob flagged 3 moves whose table descriptions looked wrong or
incomplete: Mega Punch (no punching-move mention), Steel Wing (a stat
raise shown with no percentage), Skull Bash (no mention of its
charge-turn Defense buff at all). This project has hit this exact
failure class before, multiple times — `scripts/gen_move_status_
table.py`'s own field allowlist missing real rendering logic for a
`MoveData` field (`target_includes_ally`, `stat_change_bypasses_type_
gate` in earlier sessions this arc). The goal here was to determine,
for each of the 3 flagged moves AND for the full roster, whether each
gap is:

- **(a) DISPLAY-ONLY**: the move is correctly implemented (data +
  dispatch), but the table generator doesn't know how to render this
  field/combination — zero functional impact, a pure doc-generator bug.
- **(b) REAL BUG**: the move itself is missing the flag/data, or the
  flag exists but dispatch doesn't actually implement the described
  behavior — a genuine implementation gap.

**Bottom line, stated up front**: 2 of the 3 flagged moves are (a)
display-only. **The third, Mega Punch, is a genuine (b) real bug** — a
missing `punching_move` flag in `gen_moves.py`'s own data, not a
generator issue at all. The broader full-roster sweep (Part 2) found
the display-only failure class is **bigger than the 3 examples**: 7
distinct `MoveData` fields have zero rendering logic in the generator,
affecting 12 moves' table descriptions in total — but every one of
those 7 fields is confirmed display-only (case a), not a second wave of
real bugs. This is a genuinely systemic generator gap, similar in shape
to how NEW ITEM B's status-spread-dispatch gap turned out bigger than
initially scoped — but unlike that case, the underlying game mechanics
here are all already correct; only the documentation is incomplete.

## Method

For each of the 3 flagged moves: re-derived the real source mechanic
directly from `moves_info.h` (not assumed from memory), checked
`gen_moves.py`'s own data entry for the move, checked `battle_manager
.gd`'s actual dispatch logic if the data looked correct, and checked
`gen_move_status_table.py`'s `describe_move()` function for whether it
has any rendering clause touching the relevant field(s).

For the full-roster sweep: enumerated every field name in `gen_move_
status_table.py`'s two field-recognition mechanisms — the `HANDLED_
FIELDS` set and the large inline exemption set inside `describe_move()`
's own `unrecognized = [...]` comprehension — cross-checked each
field's actual Godot type in `move_data.gd` (`grep`, not estimated),
and traced whether each has (1) an explicit rendering clause, (2) is a
plain boolean caught by the generic "any remaining `True` flag" fallback
at the end of `describe_move()`, or (3) neither — a genuine silent
drop. For every field found to be case (3), grepped `gen_moves.py`
directly for every move that sets it to a non-default value.

## Part 1: The 3 Flagged Moves

### 1. Mega Punch(5) — **REAL BUG (case b)**

**Source** (`moves_info.h:141-163`, `MOVE_MEGA_PUNCH`): `.punchingMove
= TRUE`. Confirmed — Mega Punch genuinely is a punching move in the
reference engine.

**gen_moves.py's own entry** (line 1152-1154):
```python
{"id": 5, "name": "Mega Punch",
 "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 85, "pp": 20,
 "makes_contact": True},
```
`"punching_move": True` is **completely absent**. This is a genuine
data-entry omission in this project's own hand-authored move table, not
a generator rendering gap.

**Cross-checked against 2 other Punch-family moves**, per the task's
own instruction, to confirm the flag and its rendering mechanism both
work correctly when actually present — Fire Punch(7) and Ice Punch(8)
(`gen_moves.py:1556-1562`) both correctly carry `"punching_move": True`,
and both show "Punching Move" in their current table descriptions
(confirmed directly against `docs/move_status_table.md`). This confirms
the flag mechanism itself is fine; Mega Punch is an isolated omission.

**Functional impact, confirmed via runtime consumers** (`grep` across
`ability_manager.gd`/`item_manager.gd`):
- `ability_manager.gd:1961`: `if id == ABILITY_IRON_FIST and move.punching_move:` —
  Iron Fist's power boost.
- `ability_manager.gd:1691` / `item_manager.gd:1425`: Punching Glove's
  item interaction, gated on `move.punching_move`.

**Both are real, currently-reachable mechanics this bug silently
breaks**: a Pokémon with Iron Fist or holding Punching Glove using Mega
Punch does NOT get the intended boost/interaction in this project
today, contrary to real game behavior. This is not a doc problem — it's
a genuine, if narrow (1 move), implementation gap.

**Not fixed this session** (recon only, per instruction). The fix is
small: add `"punching_move": True` to Mega Punch's `gen_moves.py` entry,
regenerate `data/moves/move_0005.tres`, and — per this project's own
test-audit-first discipline for real bugs — add a small regression test
confirming Iron Fist/Punching Glove now correctly recognize Mega Punch
specifically (not just re-running the doc generator).

### 2. Steel Wing(211) — **DISPLAY-ONLY (case a)**

**Source** (`moves_info.h:5778-5799`, `MOVE_STEEL_WING`):
`additionalEffects = ADDITIONAL_EFFECTS({.moveEffect = MOVE_EFFECT_
STAT_PLUS, .defense = 1, .self = TRUE, .chance = 10})` — confirmed
**10%** chance (not assumed), +1 Defense, self-targeted.

**gen_moves.py's own entry** (line 2187-2190):
```python
{"id":  211, "name": "Steel Wing",
 "type": TYPE_STEEL, "category": PHYS, "power": 70, "accuracy": 90,
 "pp": 25, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1,
 "stat_change_self": True, "secondary_chance": 10},
```
**Correct** — `secondary_chance: 10` exactly matches source. The data
is right.

**Runtime dispatch, traced directly** (`battle_manager.gd:9851-9859`,
inside `_do_damaging_hit`, the universal per-hit chokepoint):
```gdscript
if damage > 0 and (move.secondary_effect != MoveData.SE_NONE or move.stat_change_stat >= 0):
    var effect_hit: bool = StatusManager.try_secondary_effect(attacker, target, move, ...)
    ...
    elif move.secondary_effect == MoveData.SE_NONE and move.stat_change_stat >= 0:
        # only applies the stat change if effect_hit (the chance roll) succeeded
```
This is the exact `[M19-secondary-stat-on-hit]` mechanism this arc
built earlier — `stat_change_stat >= 0` combined with `secondary_effect
== SE_NONE` (Steel Wing's own case) routes through `try_secondary_
effect`'s existing chance-roll gate (reusing Shield Dust/Covert Cloak/
Sheer Force/Serene Grace composition for free), and the stat change is
ONLY applied if that roll succeeds. **Confirmed: Steel Wing's Defense
raise is genuinely a 10% probabilistic roll at runtime, not
unconditional.** No probabilistic test was needed to distinguish the
two hypotheses — the dispatch code itself unambiguously gates the stat
change behind the chance roll; a statistical test would only be needed
to prove the ROLL RATE itself is correctly ~10%, which is not in
question here (the shared `try_secondary_effect` mechanism is already
tested elsewhere).

**The generator bug, found precisely**: `gen_move_status_table.py`'s
`describe_move()` stat-change rendering block is:
```python
stat_stage = coerce(fields.get("stat_change_stat", "-1"))
if stat_stage is not None and stat_stage != -1:
    amt = coerce(fields.get("stat_change_amount", "0"))
    who = "ally's" if target_ally else ("own" if self_target else "target's")
    direction = "raises" if amt > 0 else "lowers"
    parts.append(f"{direction} {who} {STAGE_NAMES.get(stat_stage, stat_stage)} by {abs(amt)} stage(s)")
```
This block **never reads `secondary_chance` at all**. The SEPARATE
secondary-effects block a few lines later (which DOES print
percentages, e.g. "10% chance of burn") only fires `if eff_key in
fields` — i.e. only when `secondary_effect` is actually set to a
non-`SE_NONE` value. Steel Wing (and every other move using the
`stat_change_stat`-without-`secondary_effect` shape) never reaches that
block at all. The generator was written assuming stat changes on a
damaging hit are always unconditional — true for the ~15 multi-stat
Bucket-3 moves and self-buff status moves, but **false for the entire
`[M19-secondary-stat-on-hit]` family** (79 moves built specifically to
carry a probabilistic stat change on a damaging hit).

### 3. Skull Bash(130) — **DISPLAY-ONLY (case a)**

**Source** (`moves_info.h:3527-3552`, `MOVE_SKULL_BASH`):
`additionalEffects = ADDITIONAL_EFFECTS({.moveEffect = MOVE_EFFECT_
STAT_PLUS, .defense = 1, .self = TRUE, .onChargeTurnOnly = TRUE})` — no
`.chance` field at all (guaranteed), fires only on the charge turn.

**gen_moves.py's own entry** (line 403-406):
```python
{"id": 130, "name": "Skull Bash",
 "type": TYPE_NORMAL, "category": PHYS, "power": 130, "accuracy": 100, "pp": 10,
 "makes_contact": True, "two_turn": True, "charge_turn_defense_boost": 1,
 "ban_flags": BAN_SLEEP_TALK},
```
**Correct** — `charge_turn_defense_boost: 1` matches source exactly.

**Runtime dispatch, traced directly** (`battle_manager.gd:1798-1807`,
inside the two-turn-move dispatch, gated on `attacker.charging_move ==
null` — i.e. genuinely only the FIRST/charge turn, not the release
turn):
```gdscript
if move.two_turn and not move.is_bide and not _weather_skip and not _power_herb_skip:
    if attacker.charging_move == null:
        # Charge-turn stat boost (Skull Bash: +1 Defense on charge turn only).
        if move.charge_turn_defense_boost > 0:
            var actual_boost: int = StatusManager.apply_stat_change(
                attacker, BattlePokemon.STAGE_DEF, move.charge_turn_defense_boost, null, ng_active)
            ...
```
**Confirmed fully correct and functional** — Skull Bash genuinely gets
+1 Defense on its charge turn, matching source exactly.

**The generator bug**: `charge_turn_defense_boost` appears **only**
inside the large "don't flag this as unrecognized" exemption set in
`describe_move()` (line 311) — it has **zero** rendering logic
anywhere else in the file. It is an `int` field (not a boolean), so it
is also never caught by the generic "any remaining `True` boolean flag"
fallback at the end of the function (that fallback only fires `if val
is True`, and `1 is True` is `False` in GDScript/Python alike). The
field is silently, completely invisible in the table — not even a
generic "Charge Turn Defense Boost" flag-style mention, since it isn't
a plain boolean.

## Part 2: Full-Roster Sweep for the Same Failure Class

Enumerated every field referenced in `gen_move_status_table.py`'s two
recognition mechanisms (`HANDLED_FIELDS`, ~19 entries, and the large
inline exemption set inside `describe_move()`, ~60 entries) and
cross-checked each one's real Godot type directly via `grep` against
`move_data.gd` — not estimated. Every **boolean** field in either list
is confirmed to either have its own explicit rendering clause, or fall
through correctly to the generic `if val is True:` fallback at the end
of `describe_move()` (spot-checked ~15 of these directly against
`docs/move_status_table.md`'s own current output — e.g. "Punching
Move", "Biting Move", "Damages Airborne", "Sets Reflect On Hit" all
render correctly today). **Every genuinely silent gap found is a
non-boolean field** (`int` or `Array[int]`), since those never match
`val is True` and therefore only render if some explicit clause
handles them — confirmed precisely, not by estimation.

### The 7 confirmed under-described fields

| # | Field | Type | Where recognized (never rendered) | Moves affected |
|---|---|---|---|---|
| 1 | `charge_turn_defense_boost` | `int` | inline exemption set (L311) | Skull Bash(130) |
| 2 | `charge_turn_spatk_boost` | `int` | inline exemption set (L312) | Meteor Beam(728), Electro Shot(833) |
| 3 | `second_type` | `int` | inline exemption set (L330) | Flying Press(560) |
| 4 | `target` | `int` | inline exemption set (L332) | Perish Song(195) |
| 5 | `also_boosts_ally` | `bool` | inline exemption set (L318) — **explicitly excluded from the generic bool fallback** (L462-463), with no alternative clause | Howl(336) |
| 6 | `weather_heal_boost_type` | `int` | `HANDLED_FIELDS` (L237) | Morning Sun(234), Synthesis(235), Moonlight(236), Shore Up(622) |
| 7 | `random_status_pool` | `Array[int]` | inline exemption set (L310) | Tri Attack(161), Dire Claw(755) |

**12 distinct moves affected in total** (some fields share moves —
none of these 12 overlap across fields). Confirmed via direct grep of
`gen_moves.py` for every literal occurrence of each field name; this is
an exhaustive list, not a sample.

Current (confirmed-live, from `docs/move_status_table.md` as of this
session) descriptions for all 12, showing exactly what's missing:

- **130 Skull Bash**: *"...two-turn charge move."* — missing the +1
  Defense charge-turn buff entirely.
- **728 Meteor Beam**: *"...two-turn charge move."* — missing the +1
  Sp. Atk charge-turn buff entirely.
- **833 Electro Shot**: *"...two-turn charge move; Skips Charge In
  Rain."* — `skips_charge_in_rain` (a plain bool) renders fine; the +1
  Sp. Atk charge-turn buff is still missing.
- **560 Flying Press**: *"...Double Power On Minimized, Two Typed
  Move."* — confirms the move has a second type, but never names it
  (Flying).
- **195 Perish Song**: *"...Ignores Protect, Ignores Substitute, Perish
  Song, Sound Move."* — never mentions it targets ALL battlers on both
  sides, arguably the move's single most distinctive targeting trait.
- **336 Howl**: *"...raises own Attack by 1 stage(s); Ignores Protect,
  Snatch Affected, Sound Move."* — omits that the boost ALSO applies to
  the user's own ally in doubles.
- **234/235/236 Morning Sun/Synthesis/Moonlight**: *"...Heals Based On
  Weather, Ignores Protect, Snatch Affected, Weather Heal Has Quarter
  Branch."* — confirms a weather dependency exists but never says which
  weather (sun) boosts it, or that non-sun weather gives only 1/4.
- **622 Shore Up**: *"...Heals Based On Weather, Ignores Protect,
  Snatch Affected."* — same gap, and additionally never distinguishes
  that Shore Up's own boosting weather is sandstorm, not sun (a real,
  source-confirmed non-uniformity within this family, per this arc's
  own `[M19e]` decisions.md entry) — the CURRENT table text makes Shore
  Up look identical to the other 3 despite this genuine difference.
- **161 Tri Attack**: *"...20% chance of random status."* — never lists
  which 3 statuses (burn/freeze/paralysis) are in the pool.
- **755 Dire Claw**: *"...50% chance of random status."* — same gap,
  different pool (poison/paralysis/sleep), also invisible.

### Runtime verification (spot-checked, not assumed)

For all 12 moves, confirmed the underlying field is correctly SET in
`gen_moves.py` (matching source, cross-referenced against this arc's
own prior decisions.md entries for each — `[M19-charge-turn-spatk-
boost]`, `[D4 Bundle 9]`, `[Perish Song]`, `[M19-ally-targeting-stat-
change]`, `[M19e]`, `[M19-random-status-choice]` all independently
document these exact mechanics as already correctly implemented). None
of these 12 needed fresh dispatch-code tracing beyond what this arc's
own history already established — **every one of the 7 fields is a
pure generator-rendering gap, zero functional impact, matching the
Steel Wing/Skull Bash pattern exactly.** No second real bug was found
in the broader sweep — Mega Punch remains the sole (b)-classified
finding across all 3 flagged moves and the full 12-move broader list.

### `ban_flags` — reviewed, intentionally not counted as a gap

One additional non-boolean field (`ban_flags: int`, a bitmask of
Metronome/Sleep-Talk/Instruct/etc. eligibility exclusions) also
appears in the exemption set with no rendering clause. Reviewed and
deliberately NOT counted among the 7 above: unlike the others, this
field doesn't describe a move's own MECHANIC — it's internal
dispatch-eligibility metadata (which OTHER moves can call this one via
Metronome/Assist/Copycat/etc.), which isn't information the table's own
stated purpose ("Implementation" column — what does this move actually
do) is trying to convey. Flagged here for completeness per the "don't
estimate" instruction, not recommended for any future fix.

## Recommendation

**Two conceptually distinct follow-ups, not one**:

1. **Doc-generator-only fix (cheap, one session)**: extend
   `gen_move_status_table.py`'s `describe_move()` with 7 new rendering
   clauses (one per confirmed field above), regenerate `docs/move_
   status_table.md`, confirm the implemented/excluded/residual/needs-
   review counts are unchanged (currently 717/217/0/0) before and after.
   Zero production code changes, zero new tests needed beyond visually
   confirming the 12 affected moves' new descriptions read correctly.
   This matches the established, low-risk pattern this arc has already
   used multiple times for this exact failure class (`target_includes_
   ally`, `stat_change_bypasses_type_gate`).

2. **Real-bug fix session (small but genuine)**: fix Mega Punch's
   missing `punching_move` flag in `gen_moves.py`, regenerate `data/
   moves/move_0005.tres`, and — per this project's own test-audit-first
   discipline for real bugs, even a 1-line/1-move fix — add a small
   regression test proving Iron Fist now boosts Mega Punch and/or
   Punching Glove now recognizes it, matching the shape of prior
   single-move real-bug fixes elsewhere in this arc.

Both are small enough to combine into one practical follow-up session
if preferred (the doc-generator fix has zero risk of interacting with
the Mega Punch data fix), but they should be reported and tested as two
separate, distinct changes — a display fix and a real bug fix — not
folded into a single "regenerate the table" narrative, since only one
of the two actually changes game behavior.

No implementation performed this session. No code changed. No commit.
