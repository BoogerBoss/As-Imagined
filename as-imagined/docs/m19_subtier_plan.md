# M19 Sub-Tier Plan — Grouping the Remaining Moves for Implementation

**Status: PLANNING ONLY.** No implementation code, `CLAUDE.md`, `docs/decisions.md`,
or `docs/m19_recon.md` was touched to produce this. This report groups the
corrected `docs/m19_recon.md`'s (post-`[M19-pipeline-fix]`) remaining moves into
implementable sub-tiers by mechanism shape, mirroring the discipline
`docs/m18_subtier_plan.md` used for M18's own 165-item held-item ledger
(cheapest/most-precedented first, new-infrastructure moves sequenced
deliberately, cross-system/blocked moves flagged rather than forced in). Rob
reviews this before any M19 implementation prompt gets written.

**[M19-pre1] update (2026-07-08):** the weight and friendship data gaps this
plan originally flagged in Section C (4 moves each) are now BUILT
infrastructure, not blockers — both fields (`PokemonSpecies.weight`,
`BattlePokemon.friendship`) exist and all 8 previously-blocked moves (Low
Kick/Grass Knot/Heavy Slam/Heat Crash/Return/Frustration/Pika Papow/Veevee
Volley) are real, tested mechanics. Moved from Section C into Section B
below (2 into M19b, 2 into a new M19h, 4 into a new M19i) — see
`docs/decisions.md`'s `[M19-pre1]` entry for the full implementation. Also
per this update: **Rob has confirmed the Z-Move/Max-Move exclusion (87
moves)** — no longer an open question, matching the Mega Evolution
exclusion precedent. Every count below reflects both changes.

**[M19-exclusions] update (2026-07-08):** Rob provided a 127-move manual
exclusion list (`[M19-exclusions]`, a reconciliation task — not blind
list-application). Outcome: **124 moves permanently excluded** (14 removed
from M19a, 10 from M19b, 2 from M19c, 1 from M19d, all 3 of M19g's own
moves — dissolving that sub-tier entirely, all 9 Terrain moves — resolving
Open Question #2 below, and 85 from the Tier 4 residual). **1 move**
(Population Bomb) was already excluded for its own reasons (Section C3) —
Rob's list is consistent with that, no status change. **2 moves were
flagged as conflicts — since RESOLVED:** Heal Order(456) and Dragon
Darts(697) are both already implemented and tested (`[M16a]`/`[M18.5g]`
respectively); Rob has confirmed **option (a)** for both — docs-only
exclusion, shipped code and tests untouched, no revert. They remain real,
working mechanics in the engine and stay counted in the 132
already-implemented figure, but are now marked excluded from future
consideration/listings. See Section C's "Resolved conflicts" section for
the full record. **A follow-up
`[M19-exclusions]` addendum (2026-07-08) added one more move to the
exclusion list: Raging Bull(801)**, not implemented, removed from the Tier
4 residual — see Section C2's own list and Section D's updated totals.

**[M19a-gen1] update (2026-07-08):** the first execution slice of M19a ran
against Generation I's 22 not-yet-implemented Tier-1 moves. Step 0
re-verified the recon's "pure data-entry" framing individually against
source rather than trusting it — 15 confirmed pure and implemented (Mega
Punch/Pay Day/Vise Grip/Cut/Gust/Slam/Mega Kick/Horn Attack/Hydro
Pump/Peck/Drill Peck/Razor Leaf/Egg Bomb/Crabhammer/Slash), **7 found to
need a mechanism this project doesn't have** (Thrash/Petal Dance's rampage
lock-in, Rage's hit-triggered boost, Hyper Beam's recharge, Self-Destruct/
Explosion's unconditional self-faint + Damp block, Tri Attack's random
status choice) and moved to a new Section C4, no longer counted as M19a
data-entry scope. See `docs/decisions.md`'s `[M19a-gen1]` entry for the
full citations.

**[M19-rescope] update (2026-07-08):** `[M19a-gen1]` found generation
number has zero correlation with implementation complexity (32% of Gen I's
Tier-1 pool needed a new mechanism). Per Rob's explicit decision, this
session did a FULL reset of M19a/M19b's entire remaining pool — both
dissolved, replaced by 4 mechanism-based Buckets (Section B below); Section
C4 folded back in and closed. **While reconciling this pool against the
true current implemented-move count, a separate pre-existing error was
found**: the "147 implemented" figure below (132 + 15 from
`[M19a-gen1]`) never added `[M19-pre1]`'s own 8 moves — the correct figure,
confirmed directly against `gen_moves.py`'s own `MOVES` dict, is **155**.
Two related gaps were found but left unfixed pending Rob's own call, both
since resolved by `[M19-rescope-followup]` below.

**[M19-rescope-followup] update (2026-07-08):** closed both gaps
`[M19-rescope]` left open. (1) **M19h/M19i staleness** — confirmed directly
against `gen_moves.py`: Heavy Slam(484)/Heat Crash(535) (M19h) and
Return(216)/Pika Papow(679)/Veevee Volley(688)/Frustration(218) (M19i) are
all real, implemented moves from `[M19-pre1]`. Both sub-tiers marked
COMPLETE. (2) **Psychic Noise(845)** — Rob confirmed exclusion, matching
Heal Block's own permanently-excluded status. Re-verified the dependency
directly against source rather than trusting the prior session's flagged
note at face value: `MOVE_EFFECT_PSYCHIC_NOISE`'s handler
(`battle_script_commands.c` L2796-2805) sets the literal same
`volatiles.healBlock` field Heal Block(377) itself sets — genuinely
dependent, not thematically similar. Moved from Bucket 4 into Section C2
alongside Heal Block. 155 re-confirmed still accurate at this session's
own start (re-derived independently from `gen_moves.py`, not trusted
blindly from `[M19-rescope]`'s own claim). Every count below now fully
reconciles — zero outstanding arithmetic discrepancy.

**[M19-bucket1] update (2026-07-08):** first execution slice of the
mechanism-based Buckets. Bucket 1 (67 moves) is now COMPLETE: Step 0
individually re-verified all 67 against source (not trusting the
classifier's own bucketing blindly, matching `[M19a-gen1]`'s precedent) —
61 confirmed genuinely pure and implemented, 6 found to need a new
mechanism and moved into Bucket 4 as three new named sub-groups
(`M19-ignores-stat-stages`, `M19-ignores-target-ability`,
`M19-cant-use-twice`). Implemented-move count: **155 → 216**.

**[M19-bucket2] update (2026-07-08):** second execution slice. Bucket 2
(246 moves) is now COMPLETE: Step 0 found a substantially higher exception
rate than Bucket 1 (45%, vs. 9%) — 135 confirmed genuinely single-mechanism
reuse and implemented; 111 reclassified (15 multi-stat moves moved into
Bucket 3 [15→30, a stale count inherited from the same scan gap], 96
moved into Bucket 4 as 7 new named sub-groups [45→141], including the
79-move `M19-secondary-stat-on-hit` group — the single highest-leverage
gap found in this entire M19 effort, confirmed via this project's own
pre-existing comment that damaging moves structurally cannot carry a
probabilistic stat-change secondary at all). Implemented-move count:
**216 → 351**. Every count below reflects both updates.

Of the reference catalog's **934 real moves**, **494 are already implemented**
and are excluded from every count below. **440 moves remain.** Of those 440:

- **45 fall into proposed sub-tiers**: 28 in the mechanism-based Buckets
  1-4 (Section B — Buckets 1, 2, Bucket 4's `M19-secondary-stat-on-hit`
  sub-group, Bucket 3 in its ENTIRETY, 7 of Bucket 4's own single-move
  sub-groups (`M19-rage`/`M19-stat-reset`/`M19-item-destroy`/
  `M19-cure-opponent-status`/`M19-sound-block`/`M19-pp-reduce`/
  `M19-cant-use-twice`, `[Bucket 4 cheapest singles]`, 2026-07-09),
  `M19-rampage` (5 moves — Thrash/Petal Dance/Outrage/Raging Fury/Uproar,
  `[M19-rampage]`, 2026-07-09), `M19-recharge` (10 moves —
  `[M19-recharge]`, 2026-07-09), `M19-break-protect` (4 moves —
  Feint/Shadow Force/Phantom Force/Hyperspace Hole, `[M19-break-protect]`,
  2026-07-09), `M19-recoil-on-miss` (4 moves — Jump Kick/High Jump
  Kick/Axe Kick/Supercell Slam, `[M19-recoil-on-miss]`, 2026-07-09), and
  `M19-weather-conditional-accuracy` (5 moves — Thunder/Hurricane/Bleakwind
  Storm/Wildbolt Storm/Sandsear Storm, `[M19-weather-conditional-accuracy]`,
  2026-07-09) are now CLOSED/complete and no longer counted as pending, for
  a 28-move Bucket 4-only total) + 17 in M19c-i
  (Section B — M19h/M19i's 6 moves are COMPLETE and no longer counted as
  pending: M19c(7) + M19d(2) + M19e(4) + M19f(4) + M19g(0)).
- **1 is deferred** (Population Bomb, Section C3 — C4 is closed, folded
  into the 28 above).
- **213 are permanently excluded** (87 Z-Move/Max-Move + 126 from Rob's
  `[M19-exclusions]` list [124 original + Raging Bull + Psychic Noise],
  Section C1–C2 — unchanged by this update).
- **181 (a Tier 4 residual) still need their own dedicated sub-clustering
  pass** before individual implementation sub-tiers can be proposed for
  them, per the recon's own explicit recommendation (Section D) — not
  re-audited by this session (Tier 4 residual is outside this task's own
  scope).

**45 + 1 + 213 + 181 = 440**, exactly matching `934 − 494`. Fully
reconciled — no outstanding discrepancy. **Bucket 3 is now CLOSED (30/30)**
— see its own section below for the full writeup of both remaining
clusters (`[Bucket 3 clusters 1-2]`, 2026-07-09). **`M19-rampage` (5/5,
Uproar merged in), `M19-recharge` (10/10), `M19-break-protect` (4/4),
`M19-recoil-on-miss` (4/4), and `M19-weather-conditional-accuracy` (5/5) are
all now CLOSED** — see
the Bucket 4 section below and `docs/decisions.md`'s `[M19-rampage]`/
`[M19-recharge]`/`[M19-break-protect]`/`[M19-recoil-on-miss]`/
`[M19-weather-conditional-accuracy]` entries for
the full findings. Bucket
4's `M19-secret-power` sub-group remains investigated but DEFERRED, not
closed — see `docs/decisions.md`'s `[Bucket 4 cheapest singles]` entry for
its own Step 0 findings and Rob's explicit scope decision.

---

## Section A — Scope classification (per the recon's corrected Tier breakdown)

| Recon Tier | Total moves | Already implemented | **Remaining** | Where it lands in this plan |
|---|---|---|---|---|
| Tier 1 — no-effect / pure damage | 157 | 93 (14 + 15 `[M19a-gen1]` + 61 `[M19-bucket1]` + 1 `[M19-bucket2]` + Thrash/Petal Dance `[M19-rampage]`) | **64** | 15 permanently excluded (14 `[M19-exclusions]` + Psychic Noise, `[M19-rescope-followup]`, Section C2); remaining 49 folded into Bucket 4 below (Buckets 1 AND 2 are now both CLOSED/complete) |
| Tier 2 — simple secondary effect | 308 | 297 (42 + Low Kick/Grass Knot, `[M19-pre1]` + 134 `[M19-bucket2]` + 79 `[M19-secondary-stat-on-hit]` + 24 `[Bucket 3 multi-stat]` + 5 Thunder/Ice/Fire Fang + Glitzy Glow/Baddy Bad `[Bucket 3 clusters 1-2]` + 7 Rage/Clear Smog/Incinerate/Sparkling Aria/Throat Chop/Eerie Spell/Blood Moon `[Bucket 4 cheapest singles]` + Jump Kick/High Jump Kick/Axe Kick/Supercell Slam `[M19-recoil-on-miss]`) | **11** | 10 permanently excluded (Section C2); remaining 1 folded into Bucket 4 below (Buckets 1, 2, `M19-secondary-stat-on-hit`, Bucket 3 in its entirety, and `M19-recoil-on-miss` are now all CLOSED/complete — reverse-engineered as this Tier's own origin, matching this doc's pre-existing "remaining 5 folded into Bucket 4" note, since none of the 4 was individually itemized before this session) |
| Tier 2b — Protect-family variants | 10 | 1 | **9** | M19c (7) + 2 permanently excluded (Crafty Shield/King's Shield, Section C2) |
| Tier 3a — Multi-hit family | 31 | 30 | **1** | C3 (Population Bomb, deferred to its own future tier — also on Rob's `[M19-exclusions]` list, consistent, no status change). Dragon Darts(697) is one of the 30 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Tier 3b — Binding-move family | 11 | 10 | **1** | M19f (Jaw Lock — does NOT share this mechanism, see Section D) |
| Tier 3c — Terrain family | 9 | 0 | **9** | Permanently excluded (`[M19-exclusions]`, Section C2) — resolves Open Question #2 |
| Tier 3d — Counter/Mirror-Move family | 5 | 2 | **3** | M19d (2) + 1 permanently excluded (Comeuppance, Section C2) |
| Tier 3e — Weather-conditional heal family | 4 | 0 | **4** | M19e (all 4) |
| Tier 4 — high complexity / standalone | 312 | 61 (33 + 6 `[M19-pre1]`/M19h+M19i, corrected `[M19-rescope-followup]` + Outrage/Raging Fury/Uproar `[M19-rampage]` + 10 `[M19-recharge]` + 4 `[M19-break-protect]` + 5 `[M19-weather-conditional-accuracy]`) | **251** | M19f (3 carved out; M19g dissolved/M19h/M19i now COMPLETE, no longer carved as pending); 89 permanently excluded (3 ex-M19g + 85 residual + Raging Bull, Section C2); **181 residual** (Section D). Heal Order(456) is one of the 39 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Z-Move (permanently excluded) | 35 | 0 | **35** | C1 |
| Max Move / Dynamax (permanently excluded) | 52 | 0 | **52** | C1 |
| **Total** | **934** | **494** (corrected, `[M19-weather-conditional-accuracy]` — was 489) | **440** | |

**Every "already implemented" figure in this table now sums to exactly
494** (93+297+1+30+10+0+2+0+61+0+0), and every "remaining" figure sums to
exactly 440 (64+11+9+1+1+9+3+4+251+35+52) — confirmed via direct
addition, matching `934 − 494 = 440` exactly. Zero outstanding
discrepancy as of `[M19-weather-conditional-accuracy]`. (This session's
Tier attribution for the 5 weather-conditional-accuracy moves — all Tier
4, none Tier 1/2 — was reverse-engineered from the reconciliation
arithmetic closing exactly, the same method used for
`[M19-recharge]`/`[M19-break-protect]`, since none of the 5 was
individually itemized in any earlier session's per-Tier breakdown either;
unlike `[M19-recoil-on-miss]`'s own direct textual hint, no such hint
existed for this sub-group.)
(The 4 recoil-on-miss moves' own earlier attribution — all Tier 2, none
Tier 1/4 — was reverse-engineered from this doc's own pre-existing
"remaining 5 folded into Bucket 4" note on Tier 2's row, itself written
when `M19-recoil-on-miss` was first carved out during `[M19-bucket2]`'s own
Step 0 — a more direct attribution than the arithmetic-closure method used
above, since this one had a standing textual hint rather than needing to be
inferred purely from the totals closing.)
(The 4 break-protect moves' own earlier attribution — all Tier 4, none
Tier 1/2 — was reverse-engineered, matching the same method `[M19-recharge]`
used for its own 10 moves, since none of the 4 was individually itemized
in any prior session's per-Tier breakdown; Feint/Shadow Force/Phantom
Force/Hyperspace Hole all read as standalone/high-complexity moves, not
simple Tier 1/2 data-entry, consistent with their Bucket-4 classification.)
(The 10 recharge moves' own earlier attribution — all Tier 4, none Tier
1/2 — was reverse-engineered
from the reconciliation arithmetic closing exactly, the same method used
for `[M19-rampage]`'s own Outrage/Raging Fury/Uproar attribution, since
none of these 10 moves was individually itemized in any earlier session's
per-Tier breakdown either.)

**Confirming the pipeline fix's own scoping implication, per this task's
explicit ask**: the 81 moves `[M19-pipeline-fix]` reclassified Tier 1 → Tier 2
carry **no special handling requirement beyond a normal Tier 2 implementation
tier**. The reclassification was purely a data-accuracy correction — these 81
moves' real mechanics (a secondary stat-change attached to a damage move, e.g.
Mud-Slap/Icy Wind/Rock Tomb) are the exact same generic `stat_change_stat`/
`amount`/`self` dispatch every other Tier 2 stat-change move already uses.
They are NOT called out as a separate sub-tier below — they're folded into
Bucket 2 alongside every other Tier 2 move needing only a single existing
secondary mechanism, since nothing about them is mechanically distinct now
that the reference data is correct. The 12 moves
`[M19-pipeline-fix]`'s second bug fixed (`secondary_chance`) are similarly
unremarkable — plain status-infliction Tier 2 moves whose extracted chance
value is now simply correct.

---

## Section B — Proposed sub-tier breakdown (cheapest/most-precedented first)

### M19a/M19b — DISSOLVED, replaced by mechanism-based buckets (`[M19-rescope]`, 2026-07-08)

**Why:** `[M19a-gen1]` found that generation number has zero correlation
with implementation complexity — 7 of Generation I's 22 not-yet-implemented
Tier-1 moves (32%) needed a real mechanism this project doesn't have,
despite the recon's own "pure data-entry" framing for the whole Tier-1/
Tier-2 bucket. Generation is an accident of release history, not a useful
organizing principle for verification risk. Per Rob's explicit decision,
this was a FULL reset of M19a/M19b's entire remaining pool (Gen I's 15
already-implemented moves stay implemented and untouched; Gen I's 7
Section-C4 stragglers are folded back into this unified re-bucketing,
Section C4 is now closed) — every move re-classified fresh from
`moves_info.h` source, not from the recon's own Tier 1/Tier 2 labels
(which answer a different question — "was the data-extraction pipeline
correct" — and don't reliably predict implementation complexity).

**Methodology:** for every move, determine its real primary `.effect`, every
`additionalEffects` `.moveEffect` token (including how many DISTINCT stat
sub-fields a single stat-change block sets — Growth's own "two stats in one
block" shape recurs in 8 more moves this pass found, see Bucket 3), and any
non-`.moveEffect` mechanism flags (`.explosion`, matching `[M19a-gen1]`'s
own Self-Destruct/Explosion finding) — then classify against the full
existing-mechanism map in `move_data.gd` (every `SE_*` constant, every
`is_*`/`stat_change_*`/`recoil_percent`/`drain_percent`/`two_turn`/
`semi_inv_state`/`damages_*` field). A programmatic first pass classified
all 368 moves; every anomaly, false positive (token-naming mismatches like
`MOVE_EFFECT_PARALYSIS` vs. this project's `SE_PARALYSIS`, and a real
double-counting bug in the first draft of the classifier) and edge case was
individually re-verified directly against source before being trusted —
matching this project's standing "re-verify before trusting" discipline.

**The pool: 368 moves** (107 from the old M19a + 256 from the old M19b + 7
from Section C4, minus 2 — Low Kick(67)/Grass Knot(447) were still being
counted as "remaining" in the old M19b's 256 despite being implemented by
`[M19-pre1]`; this re-scope corrects that stale count as part of the full
reset). Classified into 4 buckets by what implementing them actually
requires:

### Bucket 1 — Pure damage, no additional effect — **COMPLETE** (`[M19-bucket1]`, 2026-07-08)

Every one of these was `EFFECT_HIT` with zero `additionalEffects` at all —
literally the same shape as `[M19a-gen1]`'s own 15-move Gen I slice, just
spanning Generations II–IX instead. Lowest possible risk; matched Tackle's
shape exactly.

Per Step 0's individual re-verification (matching `[M19a-gen1]`'s own
precedent of not trusting a "pure data-entry" classification blindly), **61
of the 67 were confirmed genuinely pure and are now implemented**: Aeroblast(177),
Mach Punch(183), Feint Attack(185), Megahorn(224), Vital Throw(233), Cross
Chop(238), Extreme Speed(245), Hyper Voice(304), Air Cutter(314), Shadow
Punch(325), Sky Uppercut(327), Dragon Claw(337), Magical Leaf(345), Leaf
Blade(348), Shock Wave(351), Aura Sphere(396), Night Slash(400), Aqua
Tail(401), Seed Bomb(402), X-Scissor(404), Dragon Pulse(406), Power
Gem(408), Vacuum Wave(410), Bullet Punch(418), Ice Shard(420), Shadow
Claw(421), Shadow Sneak(425), Psycho Cut(427), Power Whip(438), Magnet
Bomb(443), Stone Edge(444), Aqua Jet(453), Spacial Rend(460), Storm
Throw(480), Frost Breath(524), Drill Run(529), Petal Blizzard(572),
Disarming Voice(574), Fairy Wind(584), Boomburst(586), Dazzling
Gleam(605), Land's Wrath(616), Origin Pulse(618), Precipice Blades(619),
High Horsepower(630), Leafage(633), Smart Strike(647), Dragon Hammer(655),
Brutal Swing(656), Accelerock(663), Branch Poke(713), Overdrive(714),
False Surrender(721), Wicked Blow(745), Glacial Lance(752), Astral
Barrage(753), Jet Punch(785), Kowtow Cleave(797), Flower Trick(798), Hyper
Drill(813), Aqua Cutter(821).

**6 were found to need a genuinely new mechanism** and were moved to
Bucket 4 (see the new `M19-ignores-stat-stages`/`M19-ignores-target-ability`/
`M19-cant-use-twice` sub-groups below): Chip Away(498), Sacred
Sword(533), Darkest Lariat(626), Sunsteel Strike(667), Moongeist
Beam(668), Blood Moon(829). Full Step 0 citations in `docs/decisions.md`'s
`[M19-bucket1]` entry.

### Bucket 2 — Reuses a single existing secondary mechanism — **COMPLETE** (`[M19-bucket2]`, 2026-07-08)

Originally declared 246 moves as reusing exactly one existing secondary
mechanism, sub-clustered by primary effect. Per Step 0's individual
re-verification (matching `[M19-bucket1]`'s own precedent), **111 of the
246 were found to need something this bucket's classification didn't
check for** — see the full citations in `docs/decisions.md`'s
`[M19-bucket2]` entry:

- **15 multi-stat-in-one-block moves** the original scan missed due to a
  field-naming gap (only checked `STAT_CHANGE_EFFECT_*` blocks, not the
  identical shape inside `MOVE_EFFECT_STAT_PLUS/MINUS` blocks) — moved into
  Bucket 3's own multi-stat category below (15→30).
- **96 moves needing a genuinely new mechanism** — moved into Bucket 4 as
  7 new named sub-groups below, including the single highest-leverage gap
  found in this entire M19 effort: **79 `EFFECT_HIT` + stat-token moves**
  (Bug Buzz, Focus Blast, Iron Tail, Shadow Ball, Crunch, Moonblast,
  Psychic, and 72 more) that this project's `stat_change_stat` schema
  cannot represent on a damaging move AT ALL (confirmed via this project's
  own pre-existing comment, `item_manager.gd:768` — "no damaging move can
  carry a probabilistic stat-lowering secondary effect here").

**135 moves confirmed genuinely single-mechanism reuse and implemented**,
organized into 8 mechanism groups: `EFFECT_HIT` + single secondary (72),
pure `EFFECT_STAT_CHANGE` (30), `EFFECT_NON_VOLATILE_STATUS` (9),
`EFFECT_RECOIL` (9), `EFFECT_ABSORB` (8), `EFFECT_CONFUSE` (3),
`EFFECT_SEMI_INVULNERABLE` (2, Dive/Bounce), `EFFECT_TWO_TURNS_ATTACK` (2,
Freeze Shock/Ice Burn — the other 2 members of this primary effect needed
a charge-turn Sp.Atk boost this project's Defense-only
`charge_turn_defense_boost` field can't represent, folded into Bucket 4).

(72+30+9+9+8+3+2+2 = 135, reconciled. 135+111 = 246, matching the
original declaration exactly.) Full move-by-move ID list omitted here for
length (matching this document's own precedent for large single-shape
buckets) — full field-mapping-per-move detail lives in
`docs/decisions.md`'s `[M19-bucket2]` entry and
`scenes/battle/m19_bucket2_test.gd`.

### Bucket 3 — Reuses existing mechanisms, needs closer scrutiny — COMPLETE (30/30)

Each of these combines something this project already has with a SECOND
thing in a way the current single-slot schema can't cleanly represent, or
reuses an existing mechanism in a combination not yet proven safe. Three
distinct shapes:

- **Multi-stat-in-one-block — COMPLETE (`[Bucket 3 multi-stat]`,
  2026-07-09), 24 of 25 shipped.** Step 0 re-derived the full 25-move list
  fresh from source (a broadened brace-matched scanner unioning stats
  across ALL of a move's stat-change blocks, not just within one — the
  first draft missed **Spicy Extract(786)**, whose "+2 Atk/-2 Def" is
  actually TWO SEPARATE single-stat blocks, not one multi-field block like
  Ancient Power's shape) and cross-checked byte-for-byte against this
  section's own 25-move list below: exact match, confirming it was
  accurate all along. Found the cluster is NOT uniform in three ways the
  design needed to account for: (1) it splits 8 `EFFECT_HIT` (damage
  moves) / 17 `EFFECT_STAT_CHANGE` (pure status moves) — both dispatch
  paths needed extending, not just one; (2) magnitude/sign is not uniform
  ±1 — Shell Smash mixes +2 (Atk/SpAtk/Speed) with -1 (Def/SpDef) in ONE
  move, Shift Gear mixes +1 Atk with +2 Speed; (3) **Coaching(739) is
  genuinely `TARGET_ALLY`**, a third targeting mode the `stat_change_self:
  bool` schema can't represent at all — carved out of this tier's
  buildable scope and merged into `M19-ally-targeting-stat-change` (now 3
  moves: Howl, Aromatic Mist, Coaching) instead, leaving 24 moves shipped
  here. Design: two new optional `MoveData` fields
  (`extra_stat_change_stats`/`extra_stat_change_amounts`, parallel
  `Array[int]`, empty for every other move in the roster) rather than a
  per-move flag matching `is_growth`'s own precedent — Growth's dispatch is
  bespoke around sun-doubling, not a reusable "N stat pairs" shape, and a
  generalized mechanism was cheap specifically because
  `[M19-secondary-stat-on-hit]` had already extracted
  `BattleManager._apply_stat_change_effect` into one shared function reused
  by both dispatch paths — refactored into a new per-pair helper
  (`_apply_one_stat_change_pair`) called once per (stat, amount) pair,
  running Mirror Armor/Defiant-Competitive/Opportunist/Mirror Herb
  independently PER PAIR rather than once per move (confirmed necessary,
  not just convenient: Spicy Extract's -2 Def redirects via Mirror Armor
  while its simultaneous +2 Atk does not; a 2-stat-lowering move against a
  Defiant holder correctly triggers it twice, matching real game
  behavior). Zero changes needed to either dispatch gate or to Sheer Force
  (both already generic, confirmed not assumed). Full move list (25,
  Coaching flagged separately): Tickle(321, -1 Atk/-1 Def), Bulk Up(339,
  +1 Atk/+1 Def), Dragon Dance(349, +1 Atk/+1 Spe), Hone Claws(468, +1
  Atk/+1 Acc), Coil(489, +1 Atk/+1 Def/+1 Acc), Shift Gear(508, +1 Atk/+2
  Spe), **Coaching(739, ally-targeting +1 Atk/+1 Def — NOT shipped, merged
  into `M19-ally-targeting-stat-change`)**, Victory Dance(765, +1 Atk/+1
  Def/+1 Spe), Shell Smash(504, +2 Atk/+2 SpAtk/+2 Spe/-1 Def/-1 SpDef),
  Spicy Extract(786, +2 Atk/-2 Def), Ancient Power(246, +1 all 5 non-HP
  stats), Superpower(276, -1 Atk/-1 Def, self), Silver Wind(318, +1 all
  5), Cosmic Power(322, +1 Def/+1 SpDef, self), Calm Mind(347, +1 SpAtk/+1
  SpDef, self), Close Combat(370, -1 Def/-1 SpDef, self), Ominous
  Wind(466, +1 all 5), Quiver Dance(483, +1 SpAtk/+1 SpDef/+1 Spe, self),
  Work Up(526, +1 Atk/+1 SpAtk, self), Noble Roar(568, -1 Atk/-1 SpAtk,
  foe), Dragon Ascent(620, -1 Def/-1 SpDef, self), Tearful Look(669, -1
  Atk/-1 SpAtk, foe), Decorate(705, +2 Atk/+2 SpAtk, foe), Headlong
  Rush(766, -1 Def/-1 SpDef, self), Armor Cannon(816, -1 Def/-1 SpDef,
  self).
- **Combined secondary effects — COMPLETE (`[Bucket 3 clusters 1-2]`,
  2026-07-09), 3 of 3 shipped.** Thunder Fang(422, paralysis 10% + flinch
  10%), Ice Fang(423, freeze/frostbite 10% + flinch 10%), Fire Fang(424,
  burn 10% + flinch 10%). Step 0 confirmed from source
  (`Cmd_setadditionaleffects`'s loop) that the two rolls are genuinely
  INDEPENDENT — own RNG index (`RNG_SECONDARY_EFFECT + counter`), own
  Serene-Grace doubling, own Shield-Dust/Covert-Cloak/Sheer-Force gate per
  effect (`CalcSecondaryEffectChance`/`MoveIsAffectedBySheerForce` both
  operate per-additionalEffect, not per-move) — confirming the historical
  "10% status, 10% flinch, independently rolled" assumption rather than
  taking it on faith. Design: a second, fully independent
  `secondary_effect_2`/`secondary_chance_2` slot on `MoveData` (status
  stays in the existing slot 1; flinch goes in the new slot 2), dispatched
  via a SECOND `StatusManager.try_secondary_effect` call on a
  shallow-duplicated `MoveData` (slot-2 values substituted in) — the same
  "duplicate and substitute" pattern `[M17n-6]` established for move-type
  mutation, rather than changing `try_secondary_effect`'s own signature.
  This composes every existing gate (Serene Grace/Shield Dust/Covert
  Cloak/Sheer Force) correctly for free, checked independently per slot.
  `[M18k]`'s King's Rock/Razor Fang mutual-exclusion gate (`move.
  secondary_effect != SE_FLINCH`) was extended to also check
  `secondary_effect_2 != SE_FLINCH`, since a move's native flinch can now
  live in slot 2 instead of slot 1 — confirmed via a dedicated statistical
  test (n=300, King's Rock's own roll forced true) that the observed
  flinch rate on a Thunder-Fang user still tracks the native ~10%, not the
  ~100% a stacked independent roll would produce if the gate had missed
  slot 2.
- **Existing mechanism + simultaneous damage — COMPLETE (`[Bucket 3
  clusters 1-2]`, 2026-07-09), 2 of 2 shipped.** Glitzy Glow(683, sets
  Light Screen)/Baddy Bad(684, sets Reflect) — both `EFFECT_HIT` (power 80,
  accuracy 95 at this project's GEN_LATEST config), each with a GUARANTEED
  (no `.chance` field — primary, not a true secondary, so Shield Dust/Sheer
  Force/Serene Grace never apply), SELF-targeted `MOVE_EFFECT_LIGHT_SCREEN`/
  `MOVE_EFFECT_REFLECT` additional effect. Step 0 confirmed the existing
  `is_light_screen`/`is_reflect` pure-status dispatch branches (return
  immediately with zero damage) are structurally UNREACHABLE from a
  damaging move — real source's `TrySetReflect`/`TrySetLightScreen` calls
  are reached from `Cmd_setadditionaleffects`'s normal post-damage
  additional-effect dispatch, the identical mechanism every other
  `additionalEffects` entry uses, not a separate "screen" pathway that
  needed reconciling against damage — so this was genuinely zero-code-
  coexisting-already only in the sense that source itself never special-
  cases it; this project's OWN dispatch needed a new insertion point since
  its pure-status branches short-circuit before dealing damage at all. New
  `sets_reflect_on_hit`/`sets_light_screen_on_hit` `MoveData` flags,
  dispatched inside `_do_damaging_hit` unconditional on `damage > 0` alone
  (not routed through `try_secondary_effect`, matching the guaranteed/
  primary-effect reasoning above) — reusing the exact same already-up
  no-refresh check and Light Clay duration extension the pure-status
  moves already have. Confirmed via a dedicated test that the screen lands
  on the SETTER's (attacker's) own side (`screen_set(0, ...)`), never the
  target's side.

### Bucket 4 — Needs a genuinely new mechanism (28 moves, 15 named sub-groups)

**`M19-secondary-stat-on-hit` (79 moves) is COMPLETE** (`[M19-secondary-stat-on-hit]`,
2026-07-09) — see that sub-group's own entry below for the full writeup. Bucket 4's
own totals in this section (141→62 moves, 28→27 sub-groups) already reflect its
removal. **Coaching(739) added to `M19-ally-targeting-stat-change`
(`[Bucket 3 multi-stat]`, 2026-07-09)** — carved out of Bucket 3's multi-stat
cluster (genuinely `TARGET_ALLY`, the same blocker as Howl/Aromatic Mist),
growing Bucket 4's own total 62→63 (sub-group count unchanged at 27, only
that one sub-group's move count grew 2→3). **7 single-move sub-groups are now
COMPLETE** (`[Bucket 4 cheapest singles]`, 2026-07-09) — `M19-rage`,
`M19-stat-reset`, `M19-item-destroy`, `M19-cure-opponent-status`,
`M19-sound-block`, `M19-pp-reduce`, and `M19-cant-use-twice`, shrinking
Bucket 4's own total 63→56 moves, 27→20 sub-groups. `M19-secret-power` and
`M19-uproar` were investigated in that SAME session but explicitly DEFERRED
by Rob (not closed) — see `M19-secret-power`'s own entry below for the
corrected, sharpened findings. **`M19-rampage` (Uproar merged in) is now
COMPLETE** (`[M19-rampage]`, 2026-07-09) — see its own entry below,
shrinking Bucket 4's own total 56→51 moves, 20→19 sub-groups. **`M19-recharge`
is now COMPLETE** (`[M19-recharge]`, 2026-07-09) — see its own entry below,
shrinking Bucket 4's own total 51→41 moves, 19→18 sub-groups. **`M19-break-protect`
is now COMPLETE** (`[M19-break-protect]`, 2026-07-09) — see its own entry below,
shrinking Bucket 4's own total 41→37 moves, 18→17 sub-groups. **`M19-recoil-on-miss`
is now COMPLETE** (`[M19-recoil-on-miss]`, 2026-07-09) — see its own entry below,
shrinking Bucket 4's own total 37→33 moves, 17→16 sub-groups. **`M19-weather-conditional-accuracy`
is now COMPLETE** (`[M19-weather-conditional-accuracy]`, 2026-07-09) — see its own
entry below, shrinking Bucket 4's own total 33→28 moves, 16→15 sub-groups, and
resolving Bleakwind Storm's long-standing double-block.

Each sub-group below shares ONE real mechanism this project doesn't have
yet — building it once should let a future tier apply it to every move in
that sub-group at once, rather than rediscovering the same mechanism
move-by-move (the exact trap `[M19a-gen1]` flagged as a risk and this
re-scope exists to avoid repeating).

- **M19-rampage — CLOSED, COMPLETE (`[M19-rampage]`, 2026-07-09).** Thrash(37),
  Petal Dance(80), Outrage(200), Raging Fury(761), Uproar(253) — Uproar
  merged in here per Rob's confirmation, resolving its own prior deferral
  (matching the Spirit Shackle/M19f precedent rather than being tracked as a
  separate closed sub-group). Step 0 confirmed all 4 "true" rampage moves
  are structurally IDENTICAL in source (same `MOVE_EFFECT_THRASH`
  additionalEffect, same 2-3 turn range, no per-move behavior difference) and
  that the lock is a genuine FORCED REPEAT (selection bypassed entirely, not
  "user-selected-but-can't-switch"). New shared `BattlePokemon.locked_move`
  field (deliberately kept SEPARATE from the pre-existing `charging_move`
  field per Rob's confirmed design — matches this project's own
  one-field-per-lock convention rather than overloading a field with
  two-turn/Bide-specific dispatch gates already keyed on it), plus two
  distinct counters (`rampage_turns` — random 2-3, self-confuses at 0;
  `uproar_turns` — flat 3 at this project's Gen5+ config, does NOT
  self-confuse). A miss does not cancel a continuing lock (still decrements,
  still confuses on schedule); a type-IMMUNE hit against a continuing lock
  cancels it WITHOUT confuse (a real, distinct rule from a miss); a
  first-use immune hit never sets the lock at all. Target-faints-mid-rampage
  and attacker-faints/switches-mid-lock both needed zero special-case code
  (confirmed free from this project's existing `_default_target`, recomputed
  fresh every turn, and `_clear_volatiles`, already called at every
  faint/switch site). Uproar's sleep-block is FIELD-WIDE (both sides, not
  just the user's own team — confirming the correction already flagged in
  this sub-group's prior deferred entry) and only blocks NEW sleep at this
  project's Gen5+ config (does not wake already-sleeping mons — that half is
  pre-Gen5-only, dead code here). 33/33 new assertions, stable across 4
  reruns. 17-suite regression (the 4 required plus every suite touching
  two-turn/binding-move mechanics, turn-resolution, or the two functions
  whose signatures were extended for Uproar's sleep-block) all clean, 0
  failures.
- **M19-recharge — CLOSED, COMPLETE (`[M19-recharge]`, 2026-07-09).** Hyper
  Beam(63), Blast Burn(307), Hydro Cannon(308), Frenzy Plant(338), Giga
  Impact(416), Rock Wrecker(439), Roar of Time(459), Prismatic Laser(665),
  Meteor Assault(722), Eternabeam(723). Step 0 found the 10 are NOT
  mechanically uniform (Prismatic Laser is 160/100/10, not the 150/90/5
  norm; Meteor Assault is 150/100/5; Giga Impact/Rock Wrecker/Meteor
  Assault are Physical, the other 7 Special; only Giga Impact makes
  contact). A genuine, source-confirmed CORRECTION to the commonly-assumed
  "recharges even on a miss" folklore: none of the 10 set
  `.preAttackEffect = TRUE` on their `MOVE_EFFECT_RECHARGE` additionalEffect,
  so it dispatches ONLY via `Cmd_setadditionaleffects` — reachable solely
  via the successful-hit script path, never on a miss. Confirmed with Rob
  via `AskUserQuestion` before implementing. Also a genuinely different
  mechanism SHAPE from `M19-rampage`'s `locked_move` forced-repeat lock:
  recharge is a PRE-MOVE canceler (source: `CancelerRecharge`, confirmed to
  run BEFORE Sleep/Truant in the real canceler chain), reusing this
  project's existing `StatusManager.pre_move_check` chokepoint (where
  Truant already lives) via one new `BattlePokemon.must_recharge: bool`,
  rather than the `_phase_move_selection`-override pattern from last
  session. Switch-out/faint clears it for free (source's `rechargeTimer`
  lives in the same bulk-memset `Volatiles` struct every other
  switch-cleared field does).
- **M19-self-faint (2)** — unconditional self-faint after use, plus Damp
  blocks the move outright at selection (`.explosion = TRUE`, matching
  `[M19a-gen1]`'s own finding exactly): Self-Destruct(120), Explosion(153).
- **M19-random-status-choice (2)** — randomly inflicts ONE of several
  statuses (`MOVE_EFFECT_TRI_ATTACK`/`MOVE_EFFECT_DIRE_CLAW` shape — no
  existing `SE_*` supports a random multi-status choice): Tri Attack(161),
  Dire Claw(755, needs its own individual chance-table verification —
  not assumed identical to Tri Attack's 3-way split).
- **M19-hp-based-power (2)** — power scales with the user's own missing
  HP% (`EFFECT_FLAIL`), the same "formula-driven power" SHAPE as
  `is_return_power`/`is_low_kick_power` but a genuinely different formula:
  Flail(175), Reversal(179).
- **M19-rage — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Rage(99). Step 0 corrected the plan's own one-line
  summary: NOT a rampage-lock (no `gLockedMoves` in source at all) — a
  genuinely simple persistent `rage_active` volatile, set on a successful
  hit, cleared the moment the user chooses a DIFFERENT move; while active,
  the holder's Attack rises +1 whenever THEY take any damaging hit
  (self/ally-hit excluded, capped at +6).
- **M19-secret-power — investigated, DEFERRED (not closed) (`[Bucket 4
  cheapest singles]`, 2026-07-09).** Secret Power(290). Step 0 resolved
  Open Question #8 with a real finding: the secondary depends on
  `gBattleEnvironment`, an OVERWORLD map/tile-derived field (set from the
  actual battle background — grass/cave/water/building/etc. — via
  `BattleSetup_GetEnvironmentId()`), structurally unrelated to the
  already-excluded in-battle Terrain mechanic and with zero analog in this
  project (no map system at all). Rob's explicit decision: defer entirely
  rather than hardcode a fixed effect (the natural default would have been
  `BATTLE_ENVIRONMENT_PLAIN`'s own GEN_LATEST effect — a flat 30%
  Paralysis chance, confirmed cheap and schema-representable — but Rob
  chose not to take that path).
- **M19-break-protect — CLOSED, COMPLETE (`[M19-break-protect]`,
  2026-07-09).** Feint(364), Shadow Force(467), Phantom Force(566),
  Hyperspace Hole(593). Confirmed all 4 share the LITERAL SAME
  `MOVE_EFFECT_FEINT` additionalEffect — genuinely uniform mechanism despite
  Feint's lower historical power suggesting it might be structurally
  distinct from the other 3 (two-turn semi-invulnerable attacks); it isn't.
  Confirmed `breaks_protect` is a real, ADDITIONAL mechanic beyond this
  project's pre-existing `ignores_protect` field: `ignores_protect` only
  lets THIS move's own hit bypass an already-up Protect check;
  `breaks_protect` is a separate POST-HIT mutation that clears the target's
  `protect_active` and resets `protect_consecutive` (the Gen5+ 1/3^n
  fail-chance ramp) — a corrected, sharpened version of this sub-group's own
  original one-line summary above, now retired in favor of this entry. POST-
  HIT ONLY, confirmed from source (none of the 4 set `.preAttackEffect`) —
  a miss never breaks Protect, the same shape `[M19-recharge]` already
  established. Source's side-wide-Protect-on-the-partner half (Wide
  Guard/Quick Guard/Crafty Shield) is NOT modeled — this project has zero
  side-wide protect moves implemented, so that half of source's own logic
  has nothing to act on; single-target scope only, confirmed not a gap.
  Shadow Force/Phantom Force needed a genuinely NEW semi-invulnerable state
  (`MoveData.SEMI_INV_VANISH`) — source's `STATE_PHANTOM_FORCE` explicitly
  returns FALSE from `CanBreakThroughSemiInvulnerablityInternal` (nothing
  hits through it, no move-flag exception unlike Fly/Dig/Dive), a DIFFERENT
  branch from that function's own default (`STATE_NONE`/unknown → TRUE) —
  and this project's own `StatusManager._can_hit_semi_invulnerable` helper
  defaulted an unrecognized state to `true` too (the opposite of what's
  needed), so an explicit `match` case was required rather than relying on
  the default; flagged and fixed before implementing, not discovered via a
  failing test. No King's Shield/Spiky Shield/Baneful Bunker/Obstruct/Silk
  Trap/Crafty Shield exist in this project (only Protect/Detect) — the
  "does this bypass every Protect-family move uniformly" question was moot.
  26/26 tests, stable across 4 reruns; 12-suite regression clean.
- **M19-berry-steal (2)** — eats/consumes the target's held berry after a
  successful hit (`MOVE_EFFECT_BUG_BITE`): Pluck(365), Bug Bite(450).
- **M19-stat-reset — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Clear Smog(499). Confirmed genuinely a NEW dispatch
  branch (an absolute reset of all 7 stat stages to 0, not representable
  by the existing `stat_change_stat`/`amount` relative-delta schema) — this
  project has no Haze precedent to reuse at all (Haze itself is still
  unimplemented, per M19-blocked-on-other-tier4's own Freezy Frost entry
  below), so this was built from scratch, just a very small addition.
- **M19-item-destroy — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Incinerate(510). Confirmed distinct from M19-berry-steal
  exactly as suspected: destroys the target's held Berry outright (no
  consumption-effect side triggers — deliberately bypasses this project's
  `_consume_item`, which would have incorrectly ALSO triggered Cheek Pouch
  and registered `last_consumed_berry`), blocked by Sticky Hold, correctly
  triggers Unburden via a small dedicated destroy-path. This project has no
  Gem items, so the Gen6+ Gem half of source's condition is permanently
  moot here.
- **M19-trap-secondary (1)** — inflicts escape-prevention as a SECONDARY
  effect on a damaging hit (`MOVE_EFFECT_PREVENT_ESCAPE`) — shares the
  SAME mechanism M19f (Section B above) is already planned to build for
  Spider Web/Mean Look/Block/Jaw Lock; **should be folded into M19f once
  that tier is built, not treated as its own new family**: Spirit
  Shackle(625).
- **M19-cure-opponent-status — CLOSED, COMPLETE (`[Bucket 4 cheapest
  singles]`, 2026-07-09).** Sparkling Aria(627). Confirmed as suspected:
  cures BURN specifically on the TARGET this hit lands on (the inverse of
  every existing self-cure precedent) — a dedicated flag/branch, not routed
  through the existing SE_* schema at all (no token represents "cure a
  status FROM the target").
- **M19-sound-block — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Throat Chop(638). Confirmed as suspected: a new
  `throat_chop_turns` volatile on the TARGET, checked at the same "chosen,
  then fails at execution" insertion point Disable/Assault Vest already
  use, gated on `move.sound_move` rather than a specific move ID. Explicit
  chance=100 in source (a true secondary, correctly gated by Shield
  Dust/Sheer Force/Covert Cloak/Serene Grace), given its own new SE_*
  constant since it doesn't fit any existing token.
- **M19-steal-stats (1)** — copies the target's positive stat stages onto
  the user (removing them from the target) before dealing damage — similar
  in spirit to Opportunist's existing ability-side "copy a positive raise"
  logic (`[M17n-8]`), worth reusing that pattern rather than building from
  scratch: Spectral Thief(666).
- **M19-blocked-on-other-tier4 (3)** — secondary effect depends entirely
  on ANOTHER unimplemented Tier-4-residual move's own mechanism (not a new
  mechanism family of their own — genuinely blocked, not genuinely new):
  Sappy Seed(685, needs Leech Seed(73)'s own mechanism), Freezy Frost(686,
  needs Haze(114)'s own mechanism), Sparkly Swirl(687, needs
  Aromatherapy/Heal Bell's own party-wide-cure mechanism, itself flagged in
  Section D as having an open architecture question).
- **M19-pp-reduce — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Eerie Spell(754). Step 0's real finding: NO new tracking
  state was needed at all — this project already has comprehensive
  per-battler `last_move_used` tracking (wired since `[M16e]`'s Conversion
  2), directly reusable to find the target's own move slot and deduct 3 PP
  (capped at available PP via the existing `use_pp(idx, amount)`). Explicit
  chance=100 in source, same true-secondary shape as Throat Chop above.
- **M19-ignores-stat-stages (3)** — found during `[M19-bucket1]`'s Step 0:
  `.ignoresTargetDefenseEvasionStages = TRUE` bypasses the target's Def/Eva
  stat stages entirely when calculating damage — `DamageCalculator`
  currently always applies them (`_apply_stage`), no bypass path exists:
  Chip Away(498), Sacred Sword(533), Darkest Lariat(626).
- **M19-ignores-target-ability (2)** — found during `[M19-bucket1]`'s Step
  0: `.ignoresTargetAbility = TRUE` unconditionally ignores the target's
  ability regardless of the USER's own ability — `AbilityManager.
  effective_ability_id()` only bypasses a target's ability when the
  attacker itself has Mold Breaker/Mycelium Might
  (`ability_manager.gd:1041-1056`); a genuinely different, move-level gate:
  Sunsteel Strike(667), Moongeist Beam(668).
- **M19-cant-use-twice — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Blood Moon(829). Step 0's real finding, resolving this
  sub-group's own original "no move-repeat tracking exists" framing: this
  project's pre-existing `last_move_used` field (the SAME one M19-pp-reduce
  above reuses) already IS the move-repeat tracking needed — a simple
  reference-equality check (`attacker.last_move_used == move`, the same
  pattern the existing Disable check already uses) at the same "chosen,
  then fails at execution" insertion point, zero new state. Real source
  gates this at SELECTION time (a menu-legality filter); this project has
  no such architecture, so it's implemented at execution time instead,
  matching the precedent Assault Vest already established.

**M19-heal-block-secondary — CLOSED, excluded (`[M19-rescope-followup]`,
2026-07-08).** Formerly a 1-move sub-group (Psychic Noise(845)) pending
Rob's scope call on whether it should be excluded alongside its parent
mechanism. Rob confirmed exclusion. Re-verified the dependency directly
against source before applying it (not just trusting the prior session's
flagged note): `MOVE_EFFECT_PSYCHIC_NOISE`'s handler
(`battle_script_commands.c` L2796-2805) sets the literal SAME
`volatiles.healBlock` field Heal Block(377) itself sets — a genuine
mechanism dependency, not thematic similarity. Moved to Section C2
alongside Heal Block; no longer part of this bucket's count.

- **M19-recoil-on-miss — CLOSED, COMPLETE (`[M19-recoil-on-miss]`,
  2026-07-09).** Jump Kick(26), High Jump Kick(136), Axe Kick(781),
  Supercell Slam(844). Confirmed all 4 share the LITERAL SAME
  `.effect = EFFECT_RECOIL_IF_MISS` — a genuinely uniform mechanism despite
  power/accuracy/pp NOT being uniform, contradicting the possibility that
  the two newer-gen additions (Axe Kick/Supercell Slam) might use a
  different crash formula. Formula confirmed at this project's GEN_LATEST
  config: a FLAT 50% of the ATTACKER'S OWN max HP, NOT damage-scaled (the
  older defender's-HP-based GEN_4-only branch is dead code at GEN_LATEST).
  Miss-scope confirmed BROADER than accuracy-roll-failed alone — also
  triggers on a Protect block and on ordinary type immunity (source's
  `MOVE_RESULT_NO_EFFECT = MISSED | FAILED | PROTECTED |
  DOESNT_AFFECT_FOE`) — but NEVER on a pre-move-cancel failure (sleep/
  paralysis/Truant/etc.), since the attacker never attempted the move in
  those cases. A real, confirmed ASYMMETRY with ordinary recoil: Magic
  Guard blocks crash damage, but Rock Head does NOT (confirmed directly
  from `BattleScript_RecoilIfMiss` — Rock Head is never checked there,
  unlike ordinary recoil's own case block a few lines below it). Also
  fixed a directly-adjacent gap: Reckless's power-boost check in source is
  gated on `{EFFECT_RECOIL, EFFECT_RECOIL_IF_MISS}` together, and this
  project's prior implementation only checked `recoil_percent > 0` — its
  own doc comment had already flagged this exact re-check as needed.
  Gravity (`.gravityBanned = TRUE` on all 4 in source) reconfirmed absent
  from this project entirely (`[M18t]`) — nothing to build. 26/26 tests,
  stable across 4 reruns; 13-suite regression clean.
- **M19-percent-current-hp-damage (2)** — found during `[M19-bucket2]`'s
  Step 0: `EFFECT_FIXED_PERCENT_DAMAGE` deals 50% of the target's CURRENT
  HP — no field computes a percentage of current HP (`fixed_damage` is a
  flat int, `level_damage` is level-based): Super Fang(162),
  Ruination(803).
- **M19-charge-turn-spatk-boost (2)** — found during `[M19-bucket2]`'s
  Step 0: raises the user's Sp.Atk specifically on the charge turn —
  `charge_turn_defense_boost` is hardcoded to Defense only (dispatch
  hardcodes `STAGE_DEF`); Electro Shot additionally skips its charge turn
  in RAIN, but `is_solar_beam` is hardcoded to sun only: Meteor
  Beam(728), Electro Shot(833).
- **M19-weather-conditional-accuracy — CLOSED, COMPLETE
  (`[M19-weather-conditional-accuracy]`, 2026-07-09).** Thunder(87),
  Hurricane(542), Bleakwind Storm(774), Wildbolt Storm(775), Sandsear
  Storm(776). Confirmed 2 genuinely SEPARATE flags, not 1: `always_hits_in_rain`
  (all 5, a FULL BYPASS of the entire accuracy chain, the same "family" as
  No Guard/accuracy==0) and `accuracy_halved_in_sun` (Thunder/Hurricane
  ONLY — a literal override to a flat 50, applied at the same insertion
  point `[M17n-11]`'s Wonder Skin already established, composing with
  rather than bypassing the rest of the modifier chain). **A real
  correction beyond this bullet's own original framing**: Bleakwind
  Storm(774) was NEVER actually implemented before this session (re-verified
  directly — no prior `.tres`/`gen_moves.py` entry existed for it, or for
  any of the other 4 IDs) — it was correctly excluded from
  `[M19-secondary-stat-on-hit]`'s 79-move batch specifically because of
  this double-block, meaning its stat-on-hit half was never actually
  shipped either. This session built Bleakwind Storm's stat-on-hit
  secondary AND its weather-accuracy flag together in one entry, fully
  resolving the double-block. 27/27 tests, stable across 5 reruns;
  15-suite regression clean.
- **M19-stat-raised-trigger (2)** — found during `[M19-bucket2]`'s Step 0:
  `onlyIfTargetRaisedStats` — secondary only fires if the target's own
  stats rose this turn; no "stat raised this turn" tracking exists
  anywhere: Burning Jealousy(735), Alluring Voice(842).
- **M19-secondary-stat-on-hit (79) — COMPLETE (`[M19-secondary-stat-on-hit]`,
  2026-07-09).** The single highest-leverage gap found in this entire M19
  effort, found during `[M19-bucket2]`'s Step 0:
  EVERY `EFFECT_HIT` + `MOVE_EFFECT_STAT_PLUS`/`STAT_MINUS`-token move,
  regardless of chance value. Confirmed via this project's OWN
  pre-existing comment (`item_manager.gd:768`): "this project's
  `stat_change_stat` schema has NO probability field at all, so no
  damaging move can carry a probabilistic stat-lowering secondary effect
  here." Independently re-verified: every `stat_change_stat` reference in
  `battle_manager.gd` lives inside the pure-status-move-only branch
  (`category == STATUS`), never inside `EFFECT_HIT`'s own damage-execution
  path. A SINGLE new mechanism (extend `EFFECT_HIT`'s dispatch to
  roll+apply `stat_change_stat`, mirroring `try_secondary_effect`'s
  existing chance-roll shape) would unlock all 79 at once: Acid(51),
  Bubble Beam(61), Aurora Beam(62), Psychic(94), Constrict(132),
  Bubble(145), Mud-Slap(189), Octazooka(190), Icy Wind(196), Steel
  Wing(211), Iron Tail(231), Metal Claw(232), Crunch(242), Shadow
  Ball(247), Rock Smash(249), Luster Purge(295), Mist Ball(296), Crush
  Claw(306), Meteor Mash(309), Overheat(315), Rock Tomb(317), Muddy
  Water(330), Mud Shot(341), Psycho Boost(354), Hammer Arm(359), Bug
  Buzz(405), Focus Blast(411), Energy Ball(412), Earth Power(414), Mud
  Bomb(426), Mirror Shot(429), Flash Cannon(430), Draco Meteor(434), Leaf
  Storm(437), Charge Beam(451), Seed Flare(465), Flame Charge(488), Low
  Sweep(490), Acid Spray(491), Struggle Bug(522), Electroweb(527), Razor
  Shell(534), Leaf Tornado(536), Night Daze(539), Glaciate(549), Fiery
  Dance(552), Snarl(555), Play Rough(583), Moonblast(585), Diamond
  Storm(591), Mystical Fire(595), Power-Up Punch(612), Ice Hammer(628),
  Lunge(642), Fire Lash(643), Trop Kick(651), Clanging Scales(654), Fleur
  Cannon(659), Shadow Bone(662), Liquidation(664), Zippy Zap(676), Drum
  Beating(706), Breaking Swipe(712), Apple Acid(715), Spirit Break(717),
  Skitter Smack(734), Thunderous Kick(751), Psyshield Bash(756),
  Springtide Storm(759), Mystical Power(760), Esper Wing(768), Bitter
  Malice(769), Lumina Crash(783), Spin Out(787), Torch Song(799), Aqua
  Step(800), Pounce(810), Trailblaze(811), Chilling Water(812).
  **Count note**: this is the correct, final count of 79 — during
  `[M19-secondary-stat-on-hit]`'s own Step 0, an independent re-derivation
  from source (a different extraction method than the one that produced this
  list) reproduced this exact 79-move ID set byte-for-byte, with Bleakwind
  Storm(774) already excluded (it needs `M19-weather-conditional-accuracy`
  too, see that sub-group's own note above). A restatement of this figure
  during scoping said "78 (79 minus Bleakwind Storm)" — that arithmetic was
  wrong; Bleakwind Storm was never part of this 79 to begin with, so nothing
  needed subtracting. See `docs/decisions.md`'s `[M19-secondary-stat-on-hit]`
  entry for the full reconciliation.
- **M19-ally-targeting-stat-change (3, grew from 2)** — found during
  `[M19-bucket2]`'s `.target` field sweep: Howl (`TARGET_USER_AND_ALLY` at
  GEN8+) and Aromatic Mist (`TARGET_ALLY` — buffs the ally, not the user at
  all). Neither self-vs-opponent shape `stat_change_self` supports; no
  ally-targeting stat-change mechanism exists in any form: Howl(336),
  Aromatic Mist(597). **Coaching(739) added (`[Bucket 3 multi-stat]`,
  2026-07-09)** — confirmed genuinely `TARGET_ALLY` (not the generic
  `TARGET_SELECTED` every other Bucket 3 multi-stat move uses), carved out
  of that cluster's buildable scope and merged in here since it shares the
  exact same blocker.

(4+10+2+2+2+1+1+1+4+2+1+1+1+1+1+1+3+1+3+2+1+4+2+2+5+2+79+2 = 141,
reconciled at the time Bucket 4 was first classified. `M19-secondary-stat-on-hit`
(79) has since shipped (`[M19-secondary-stat-on-hit]`, 2026-07-09) and is no
longer counted in Bucket 4's remaining total: 141-79 = 62 moves across the
other 27 sub-groups. Coaching(739) was then added to
`M19-ally-targeting-stat-change` above (`[Bucket 3 multi-stat]`,
2026-07-09), growing the total to 63 across the same 27 sub-groups. 7 more
single-move sub-groups (`M19-rage`/`M19-stat-reset`/`M19-item-destroy`/
`M19-cure-opponent-status`/`M19-sound-block`/`M19-pp-reduce`/
`M19-cant-use-twice`) have since ALSO shipped (`[Bucket 4 cheapest
singles]`, 2026-07-09): 63-7 = 56 moves across 20 sub-groups. `M19-rampage`
(5 moves — Thrash/Petal Dance/Outrage/Raging Fury/Uproar, the last merged
in per Rob's confirmation) has since ALSO shipped (`[M19-rampage]`,
2026-07-09): 56-5 = 51 moves across 19 sub-groups. `M19-recharge` (10
moves) has since ALSO shipped (`[M19-recharge]`, 2026-07-09): 51-10 = 41
moves across 18 sub-groups, matching the Bucket 4 section header.)

**Recommended execution order for Buckets 1-4:**

1. **Bucket 1 (67) — COMPLETE (`[M19-bucket1]`, 2026-07-08).** 61 implemented,
   6 moved to Bucket 4 as new-mechanism exceptions (see above).
2. **Bucket 2 (246) — COMPLETE (`[M19-bucket2]`, 2026-07-08).** 135
   implemented, 111 reclassified (15 to Bucket 3, 96 to Bucket 4).
3. **Bucket 3 (30, corrected from 15 by `[M19-bucket2]`)** — still
   reuse-based, but each move needs individual care before implementation:
   the 25 multi-stat moves (corrected from 10) need a dedicated flag
   decision (one per-move flag matching `is_growth`'s precedent, or a
   small generalized multi-stat mechanism — worth deciding once, up front,
   rather than per move); the 3 combined-secondary-effect moves need a
   schema decision (second secondary-effect slot vs. dedicated handling);
   the 2 screen+damage moves need the dispatch-order verification noted
   above.
4. **Bucket 4's remaining 27 sub-groups, sequenced by real dependency, not
   move count** — each is effectively its own small new-mechanism tier,
   closer in shape to M19c-i than to bulk data-entry:
   - **M19-secondary-stat-on-hit (79 moves) — COMPLETE
     (`[M19-secondary-stat-on-hit]`, 2026-07-09).** Found by
     `[M19-bucket2]`, by far the single highest-leverage sub-group in this
     entire plan — one new mechanism (extended `try_secondary_effect`'s
     existing chance-roll gate to also dispatch a stat-change payload via a
     new shared `BattleManager._apply_stat_change_effect`, reused from the
     pre-existing pure-status-move dispatch) unlocked all 79 at once,
     exactly as anticipated. No longer part of this bucket's remaining
     count.
   - **M19-trap-secondary (Spirit Shackle)** should be folded directly
     into M19f (Section B above) rather than run separately — same
     mechanism, already planned.
   - **M19-steal-stats (Spectral Thief)** should reuse Opportunist's
     existing ability-side "copy a positive stat raise" pattern
     (`[M17n-8]`) rather than building fresh.
   - **M19-blocked-on-other-tier4 (Sappy Seed/Freezy Frost/Sparkly
     Swirl)** can't be scheduled independently — each waits on its own
     parent mechanism (Leech Seed/Haze/Aromatherpy) landing first,
     wherever those end up in the eventual Tier 4 residual sub-clustering
     pass (Section D).
   - **M19-heal-block-secondary (Psychic Noise)** — CLOSED, excluded per
     Rob's explicit call (`[M19-rescope-followup]`), no longer part of
     this bucket at all.
   - Historical note (this list predates `[Bucket 4 cheapest singles]`,
     `[M19-rampage]`, and `[M19-recharge]`, all 2026-07-09): of the original
     15 sub-groups named here (M19-rampage, M19-recharge, M19-self-faint,
     M19-random-status-choice, M19-hp-based-power, M19-rage, M19-uproar,
     M19-secret-power, M19-break-protect, M19-berry-steal, M19-stat-reset,
     M19-item-destroy, M19-cure-opponent-status, M19-sound-block,
     M19-pp-reduce), 9 are now CLOSED/complete (M19-rampage — Uproar merged
     in — M19-recharge, M19-rage, M19-stat-reset, M19-item-destroy,
     M19-cure-opponent-status, M19-sound-block, M19-pp-reduce) and
     M19-secret-power was investigated and explicitly DEFERRED by Rob. The
     remaining 5 (M19-self-faint, M19-random-status-choice,
     M19-hp-based-power, M19-break-protect, M19-berry-steal) still have no
     known dependency on each other or on unimplemented moves — sequence by
     whichever mechanism Rob wants built next.

### M19c — Protect-family variants (7 moves) — **CHEAP**

Wide Guard(469), Quick Guard(501), Spiky Shield(596), Baneful Bunker(624),
Obstruct(720), Silk Trap(780), Burning Bulwark(836). Each layers one small
twist (side-wide instead of single-target, a contact-punish stat-drop, a
contact-punish burn/poison, etc.) on top of the SAME underlying "block the
move, track the consecutive-use success-chance falloff" mechanism Protect
(182) already has fully working. Matches `[M18]`'s own C6 characterization
almost exactly — "arguably not even Tier 3 moderate," flagged separately
only because each variant's own exact twist needs individual source
verification (this project's standing "don't assume symmetry between
similar-looking effects" discipline).

**`[M19-exclusions]` update:** 2 moves permanently excluded and removed
from this count (9→7): Crafty Shield(578), King's Shield(588). See
Section C2.

### M19d — Counter/Mirror-Move remnants (2 moves) — **CHEAP-MODERATE**

Mirror Move(119), Metal Burst(368). Counter(68) and Mirror Coat(243) already
prove this project's `_last_attacker`/`_last_attacker_move` tracking
(`[M14b]`/`[M17n-8]`) generalizes to "reflect 1.5–2× the last hit of a
specific category taken this turn." Metal Burst is the same
`EFFECT_REFLECT_DAMAGE` shape as Counter/Mirror Coat — likely closer to
data-entry than new mechanism. Mirror Move (`EFFECT_MIRROR_MOVE`, reuse the
target's own last-used move) is the one genuinely different piece — confirm
whether `_last_attacker_move` already captures enough to reuse a move
object directly, or whether a new "last move USED BY the target" (not
"last move that hit me") field is needed — a subtly different tracking axis
from what Destiny Bond/Moxie currently use.

**`[M19-exclusions]` update:** 1 move permanently excluded and removed from
this count (3→2): Comeuppance(820). See Section C2.

### M19e — Weather-conditional heal family (4 moves) — **CHEAP-MODERATE**

Morning Sun(234), Synthesis(235), Moonlight(236), Shore Up(622). Each heals
a DIFFERENT fraction of max HP depending on current weather (typically 2/3
in sun, 1/4 in rain/sand/hail, 1/2 in clear weather; Shore Up's own
sand-specific bonus differs — confirm exact fractions from source
individually before implementing, per this project's standing discipline).
Combines two already-built systems (`M11` weather, `RESTORE_HP` from
`[M16a]`) rather than a new mechanism — likely a small `RESTORE_HP` variant
reading current weather state.

### M19f — Escape-prevention family (4 moves) — **MODERATE, genuinely new mechanism**

Spider Web(169), Mean Look(212), Block(335), **plus Jaw Lock(692)** — a
grouping this recon's own Section C2 correction makes possible: `[M18.5f]`'s
own Step 0 found Jaw Lock's real dispatch is `MOVE_EFFECT_TRAP_BOTH`, the
SAME mechanism `EFFECT_MEAN_LOOK` moves use (source: the Mean Look/Block
family's `escapePrevention` flag), not the binding-move `MOVE_EFFECT_WRAP`
family it was originally lumped with. This is a genuinely NEW mechanism this
project doesn't have yet: unconditional, permanent (no turn counter),
zero-damage prevention of the target's voluntary switching (Jaw Lock's own
variant is bidirectional — traps the user too). Confirm the exact
Ghost-type/Shed Shell exemption interaction against `AbilityManager.
is_trapped()`'s existing shape (`[M17f]`) before building a parallel check,
matching the binding-move tier's own precedent of reusing that function
rather than duplicating it.

### M19g — DISSOLVED (`[M19-exclusions]` update, 2026-07-08)

Formerly "Dynamax-conditional-power moves, doubling-condition-always-false
(3 moves)": Dynamax Cannon(690), Behemoth Blade(709), Behemoth Bash(710) —
Tier 4 moves whose `EFFECT_DYNAMAX_DOUBLE_DMG` doubles power only when the
user is Dynamaxed. This project has no Dynamax mechanic and none is
planned, so the doubling condition is permanently false — this sub-tier's
own argument was that these three are normal, always-usable moves (flat
base-power `EFFECT_HIT`-shaped in practice) that shouldn't be mistakenly
bundled into the Z-Move/Max-Move exclusion candidates in Section C1.

**Rob's `[M19-exclusions]` list overrides that argument** — all 3 of this
sub-tier's own moves are on it. Since none were implemented, this is a
clean reclassification, not a revert: all 3 move to permanent exclusion
(Section C2) and this sub-tier is now empty. Flagged explicitly (not
silently deleted) since it reverses this plan's own prior reasoning rather
than just confirming it — see the reconciliation summary at the top of
this document.

### M19h — Weight-ratio dynamic power (2 moves) — **COMPLETE** (`[M19-rescope-followup]`, 2026-07-08)

Heavy Slam(484), Heat Crash(535) — Tier 4 moves (`EFFECT_HEAT_CRASH`) whose
power derives from the integer ratio of the attacker's weight to the
target's weight (`PokemonSpecies.weight`, hectograms), indexed into a fixed
6-entry table. Originally deferred to Section C over a missing per-species
weight field this project's data pipeline had never populated —
`[M19-pre1]` added `PokemonSpecies.weight` (species-level, fixed, no
forcing parameter needed) and a new `scripts/gen_weight_data.py` extraction
pipeline. **Both moves were actually implemented as part of `[M19-pre1]`
itself** (confirmed directly in `gen_moves.py`'s own `MOVES` dict) — this
sub-tier's "pending" status was stale bookkeeping, corrected this session.

### M19i — Friendship-based dynamic power (4 moves) — **COMPLETE** (`[M19-rescope-followup]`, 2026-07-08)

Return(216), Pika Papow(679), Veevee Volley(688) (`EFFECT_RETURN` — all
three confirmed to share the IDENTICAL formula, not just a similar one) and
Frustration(218) (`EFFECT_FRUSTRATION`, the confirmed INVERSE relationship).
Originally deferred to Section C — this recon's own Section D only named
Return/Frustration, missing Pika Papow/Veevee Volley's identical real
dependency entirely (a correction `[M19-scoping]`'s own subtier-plan
session found). `[M19-pre1]` added `BattlePokemon.friendship` (per-instance,
defaulted from the species' own `base_friendship` — already-dormant-but-
correct data, the exact same "extracted but never wired" shape
`gender_ratio` had before `[M18.5d]`) with a `forced_friendship` override
for M24's future trainer-data needs. **All 4 moves were actually
implemented as part of `[M19-pre1]` itself** (confirmed directly in
`gen_moves.py`'s own `MOVES` dict) — this sub-tier's "pending" status was
stale bookkeeping, corrected this session. Combined with M19h above,
`[M19-pre1]`'s own 8 implemented moves split exactly 2 (M19h) + 4 (M19i) +
2 (Low Kick(67)/Grass Knot(447), which landed in the old M19b — now
Bucket 2 — and were already correctly excluded from Bucket 1-4's pool
(368 at `[M19-rescope]`'s own classification time, 367 as of
`[M19-rescope-followup]`'s Psychic Noise exclusion) as implemented, not
part of this staleness). No remaining infrastructure gap; now a
pure formula-lookup data-entry tier.

---

## Section C — Moves better left out of M19 for now (214 moves: 213 permanently excluded + 1 deferred)

### C1 — Z-Move / Max Move families (87 moves) — **PERMANENTLY EXCLUDED, confirmed by Rob**

Z-Moves (848–882, 35 moves) and the Max Move/Dynamax family (883–934, 52
moves) mirror the Mega Evolution exclusion class already established for
abilities/items in M17/M18 — each requires a one-per-battle gimmick
mechanic (a Z-Crystal item + Z-Power resource, or Dynamax/Gigantamax
itself) this project has no plans to build. **Originally flagged by the
recon as awaiting explicit confirmation, not pre-excluded — Rob has since
confirmed the exclusion (`[M19-pre1]`), matching the Mega Evolution
precedent exactly.** This closes what had been this plan's own Open
Question #1; no further action needed on this bucket.

### C2 — Rob's `[M19-exclusions]` list (126 moves) — **PERMANENTLY EXCLUDED, confirmed by Rob (2026-07-08)**

A manually-curated exclusion list Rob provided, reconciled move-by-move
against this plan's existing buckets rather than applied blindly (see
`[M19-exclusions]` in `docs/decisions.md` — note this was a docs-only
reconciliation task, so no `docs/decisions.md` entry was written for it per
that task's own instructions; the reconciliation record lives in this
document's edit history and the session summary delivered to Rob). No
mechanism-level reasoning applies uniformly here — these are excluded by
Rob's own judgment, not because of a shared technical blocker. Removed from
their previously-proposed buckets:

- **From M19a (Tier 1), 14 moves:** Attack Order(454), Flame Burst(481),
  V-create(557), Thousand Waves(615), Anchor Shot(640), Core Enforcer(650),
  Plasma Fists(674), Order Up(784), Glaive Rush(790), Salt Cure(792), Make
  It Rain(802), Gigaton Hammer(819), Syrup Bomb(831), Mighty Cleave(838).
- **From M19b (Tier 2), 10 moves:** Chatter(448), Defend Order(455),
  Nature's Madness(671), Shelter(770), Triple Arrows(771), Blazing
  Torque(822), Wicked Torque(823), Noxious Torque(824), Combat Torque(825),
  Magical Torque(826).
- **From M19c (Protect-family), 2 moves:** Crafty Shield(578), King's
  Shield(588).
- **From M19d (Counter/Mirror-Move), 1 move:** Comeuppance(820).
- **From M19g, 3 moves — dissolving that sub-tier entirely:** Dynamax
  Cannon(690), Behemoth Blade(709), Behemoth Bash(710). Note: this
  reverses M19g's own prior argument that these three are normal,
  non-gimmick moves — see M19g's own section above for the explicit
  callout.
- **Terrain family, 9 moves — resolves Open Question #2 (previously
  open/pending, per the old C2 section below):** Grassy Terrain(580),
  Misty Terrain(581), Electric Terrain(604), Psychic Terrain(641),
  Expanding Force(725), Misty Explosion(730), Rising Voltage(732), Terrain
  Pulse(733), Psyblade(827). Per this project's own standing decision:
  "M17e (Terrain) is VOID — all 10 terrain abilities excluded, no Terrain
  system will be built." Rob's list confirms these 9 moves stay excluded
  too, rather than reopening that decision or building a moves-only
  terrain system.
- **From the Tier 4 residual (Section D), 85 moves** — see Section D's
  updated cluster table for the full breakdown of which named clusters
  lost members (Water/Fire/Grass Pledge and Judgment/Techno Blast/
  Multi-Attack fully removed; Spotlight removed from the Follow-Me/redirect
  cluster; Secret Sword removed from the Psyshock cluster) versus the
  singleton/small-pairs bucket. Full 85-move list: Psywave(149), Beat
  Up(251), Gravity(356), Miracle Eye(357), Wake-Up Slap(358), Natural
  Gift(363), Embargo(373), Fling(374), Trump Card(376), Heal Block(377),
  Power Trick(379), Gastro Acid(380), Lucky Chant(381), Power Swap(384),
  Guard Swap(385), Captivate(445), Judgment(449), Dark Void(464), Guard
  Split(470), Power Split(471), Wonder Room(472), Magic Room(478),
  Synchronoise(485), Soak(487), Simple Beam(493), Entrainment(494), Ally
  Switch(502), Final Gambit(515), Bestow(516), Water Pledge(518), Fire
  Pledge(519), Grass Pledge(520), Techno Blast(546), Secret Sword(548),
  Fusion Flare(558), Fusion Bolt(559), Mat Block(561), Rototiller(563),
  Trick-or-Treat(567), Ion Deluge(569), Forest's Curse(571), Flower
  Shield(579), Electrify(582), Fairy Lock(587), Powder(600), Magnetic
  Flux(602), Happy Hour(603), Celebrate(606), Hold Hands(607), Hold
  Back(610), Thousand Arrows(614), Floral Healing(629), Spotlight(634),
  Gear Up(637), Burn Up(645), Speed Swap(646), Revelation Dance(649),
  Multi-Attack(672), Mind Blown(673), Magic Powder(696), Teatime(698), Bolt
  Beak(700), Fishious Rend(701), Court Change(702), Aura Wheel(711), Steel
  Roller(726), Shell Side Arm(729), Grassy Glide(731), Corrosive Gas(738),
  Jungle Healing(744), Power Shift(757), Lunar Blessing(777), Tera
  Blast(779), Last Respects(782), Revival Blessing(791), Doodle(795),
  Collision Course(804), Electro Drift(805), Shed Tail(806), Double
  Shock(818), Hydro Steam(828), Ivy Cudgel(832), Tera Starstorm(834),
  Fickle Beam(835), Dragon Cheer(841).
- **From the Tier 4 residual (Section D), 1 more move — `[M19-exclusions]`
  addendum (2026-07-08):** Raging Bull(801, `EFFECT_RAGING_BULL`), not
  implemented, was sitting in the singleton/small-pairs bucket. Removed
  from Section D's own totals (182→181 residual, 159→158 singleton).
- **From Bucket 4's M19-heal-block-secondary sub-group, 1 more move —
  `[M19-rescope-followup]` addendum (2026-07-08):** Psychic Noise(845),
  not implemented, excluded alongside its parent mechanism. Re-verified
  directly against source rather than trusting `[M19-rescope]`'s own
  flagged note: `MOVE_EFFECT_PSYCHIC_NOISE`'s handler
  (`battle_script_commands.c` L2796-2805) sets
  `gBattleMons[effectBattler].volatiles.healBlock = TRUE` — the EXACT SAME
  volatile field Heal Block(377)'s own move sets, not just a thematically
  similar effect. A genuine mechanism dependency, confirmed. Removed from
  Bucket 4's own totals (40→39) — see Section B's Bucket 4 for the update.

**14 + 10 + 2 + 1 + 3 + 9 + 85 + 1 + 1 = 126.**

### C3 — Population Bomb (1 move) — its own future tier, not blocked

Population Bomb(788) is the sole `.strikeCount` move `[M18.5g]` deliberately
excluded from the multi-hit mechanism it otherwise built — per-hit accuracy
checks (unlike every other `strikeCount` move, which checks once) AND a
uniquely-shaped Loaded Dice interaction (`RandomUniform(4,10)` instead of
the standard `(4,5)`). Not blocked on missing infrastructure — a genuinely
higher complexity class than the rest of Tier 3a, deliberately deferred to
its own small future tier rather than bundled here. **Also appears on
Rob's `[M19-exclusions]` list — consistency-confirmed, this was a check
against the existing status, not a new decision; no status change.**

### C4 — CLOSED, folded into Bucket 4 (`[M19-rescope]`, 2026-07-08)

Formerly "Gen I Tier-1 stragglers needing new mechanism (7 moves)": Thrash,
Petal Dance, Rage, Hyper Beam, Self-Destruct, Explosion, Tri Attack. Per
`[M19-rescope]`'s explicit full-reset instruction, these 7 are no longer a
separate quarantine bucket — they're folded into the unified mechanism-based
re-bucketing of M19a/M19b's entire remaining pool (Section B above), landing
in Bucket 4's M19-rampage/M19-recharge/M19-self-faint/M19-random-status-choice/
M19-rage sub-groups alongside every other move needing the same mechanism
family, found fresh from the rest of the pool rather than treated as a
Gen-I-specific quarantine. This section is kept only for historical
continuity — not counted in Section C's own totals below (it never was; C4
was always a "deferred," not "permanently excluded," bucket, and deferred
moves aren't part of Section C's 212-excluded/1-deferred count split).

### Resolved conflicts — 2 already-implemented moves, kept implemented (2026-07-08)

Rob's `[M19-exclusions]` list included two moves that are already
implemented and tested. Rob has confirmed **option (a)** for both: leave
the shipped code and tests exactly as-is, no revert — they're marked
excluded from future consideration/documentation listings only.

- **Heal Order(456)** — `EFFECT_RESTORE_HP`, built in `[M16a]` alongside
  Softboiled/Roost/etc., covered by `m16a_test.gd` and `m17n3_test.gd`.
  **Stays implemented.**
- **Dragon Darts(697)** — `strike_count: 2`, one of `[M18.5g]`'s 30
  multi-hit moves, covered by `m18_5g_test.gd` (315/315 passing).
  **Stays implemented.**

Both remain counted in this document's "already implemented" figure (132
at the time of this resolution, 147 as of `[M19a-gen1]`) — no code,
`.tres`, or test file was touched by this resolution.

### Closed: weight and friendship (8 moves) — resolved by `[M19-pre1]`, no longer deferred

Low Kick(67)/Grass Knot(447)/Heavy Slam(484)/Heat Crash(535) (weight) and
Return(216)/Frustration(218)/Pika Papow(679)/Veevee Volley(688)
(friendship) were originally deferred here — both real per-species/
per-instance data gaps, neither flagged by the recon's own Section D.
`[M19-pre1]` built both fields (`PokemonSpecies.weight`,
`BattlePokemon.friendship`) and implemented all 8 moves with real,
tested mechanics — Low Kick/Grass Knot are correctly excluded from Bucket
1-4's 368-move pool (already implemented); Heavy Slam/Heat Crash/Return/
Frustration/Pika Papow/Veevee Volley are tracked via M19h/M19i above
(flagged elsewhere in this document as likely already done too — see
Open Question #6) — see `docs/decisions.md`'s `[M19-pre1]` entry for the
full implementation.
Listed here only for this document's own historical continuity; not
counted in this section's own totals above.

---

## Section D — Tier 4 residual (181 moves): needs its own dedicated sub-clustering pass

Of Tier 4's 279 total remaining moves, 9 were confidently carved into
Section B above (Spider Web/Mean Look/Block → M19f, Heavy Slam/Heat Crash →
M19h, Return/Frustration/Pika Papow/Veevee Volley → M19i — M19g's own
3-move carve-out, Dynamax Cannon/Behemoth Blade/Behemoth Bash, was
dissolved and permanently excluded by `[M19-exclusions]`, see Section C2),
and 88 were permanently excluded (the ex-M19g 3 plus 85 more removed
directly from this residual by `[M19-exclusions]`, see Section C2's own
85-move list, plus a follow-up addendum removing Raging Bull(801) too).
**The remaining 181 are NOT sub-tiered by this plan**, per
the corrected recon's own explicit recommendation ("a dedicated Tier-4
sub-clustering pass, mirroring this recon's own C1–C6 methodology, is the
natural next step before any attempt to estimate M19's true total size").
Sizing 181 structurally diverse moves by effect-name alone (the only lens
this planning session had time to
apply) risks the same "grab-bag needing a follow-up recon" shape `[M17n]`'s
own Group 8 hit — better flagged explicitly than forced into sub-tiers here.

What effect-name clustering DID surface with reasonable confidence, offered
as a head start for that future pass, not a finished sub-tier list:

| Cluster | Count | Members (by effect_name) |
|---|---|---|
| `EFFECT_DOUBLE_POWER_ON_ARG_STATUS` | 6 | Power doubles if target has a specific status — likely one shared modifier function |
| `EFFECT_FOLLOW_ME`/redirect-targeting | 2 | Follow Me(266)/Rage Powder(476) — confirm whether any redirect-targeting infra exists at all (doubles-only mechanic, may interact with `[M14a]`). Spotlight(634) removed by `[M19-exclusions]`. |
| `EFFECT_HEAL_BELL` | 2 | Heal Bell(215)/Aromatherapy(312) — party-wide status cure, confirm whether party-wide (not just active-battler) status effects are reachable in this project's current architecture |
| `EFFECT_PSYSHOCK` | 2 | Psyshock(473)/Psystrike(540) — physical-stat-vs-special-category mismatch, a real new damage-calc branch. Secret Sword(548) removed by `[M19-exclusions]`. |
| `EFFECT_PLEDGE` | 0 | Water/Fire/Grass Pledge — all 3 removed by `[M19-exclusions]`, cluster fully closed |
| `EFFECT_POWER_BASED_ON_USER_HP` / `_TARGET_HP` | 6 | Eruption/Water Spout/Dragon Energy (user HP), Wring Out/Crush Grip/Hard Press (target HP) — likely one shared modifier function each |
| `EFFECT_HIT_ESCAPE` | 3 | U-turn(369)/Volt Switch(521)/Flip Turn(740) — forced-switch-after-hit, likely reuses `[M18n]`'s forced-switch plumbing directly |
| `EFFECT_HIT_SWITCH_TARGET` | 2 | Circle Throw(509)/Dragon Tail(525) — forces the DEFENDER to switch, a mirror of the above |
| `EFFECT_CHANGE_TYPE_ON_ITEM` | 0 | Judgment/Techno Blast/Multi-Attack — all 3 removed by `[M19-exclusions]`, cluster fully closed |
| Everything else (singletons/small pairs) | 158 | Genuinely one-off (Metronome, Sketch, Transform, Substitute-adjacent, room-setting moves, stat-swap moves, etc.) — this is the real sizing uncertainty for M19, exactly as the recon itself flagged. 78 moves removed by `[M19-exclusions]` (236→158, incl. the Raging Bull addendum). |

(6+2+2+2+0+6+3+2+0+158 = 181, reconciled.)

---

## Section E — Summary and recommended sequencing

| Bucket | Move count |
|---|---|
| Already implemented (excluded from this plan) — includes Heal Order/Dragon Darts (resolved conflicts); `M19-secondary-stat-on-hit` (79) shipped `[M19-secondary-stat-on-hit]` 2026-07-09; Bucket 3 in its entirety (30) shipped across `[Bucket 3 multi-stat]` + `[Bucket 3 clusters 1-2]`, both 2026-07-09; 7 of Bucket 4's single-move sub-groups shipped `[Bucket 4 cheapest singles]` 2026-07-09; `M19-rampage` (5) shipped `[M19-rampage]` 2026-07-09; `M19-recharge` (10) shipped `[M19-recharge]` 2026-07-09; `M19-break-protect` (4) shipped `[M19-break-protect]` 2026-07-09; `M19-recoil-on-miss` (4) shipped `[M19-recoil-on-miss]` 2026-07-09; `M19-weather-conditional-accuracy` (5) shipped `[M19-weather-conditional-accuracy]` 2026-07-09 | 494 |
| Proposed sub-tiers (Section B: Bucket 4 only — Buckets 1, 2, `M19-secondary-stat-on-hit`, Bucket 3 in its entirety, 7 of Bucket 4's own single-move sub-groups, `M19-rampage`, `M19-recharge`, `M19-break-protect`, `M19-recoil-on-miss`, and `M19-weather-conditional-accuracy` now COMPLETE — plus M19c-i minus M19h/M19i now COMPLETE) | 45 (28 + 17) |
| Deferred (Section C3 — Population Bomb only; C4 closed) | 1 |
| Permanently excluded, confirmed by Rob (Section C1 Z-Move/Max-Move + Section C2 `[M19-exclusions]`, incl. Raging Bull + Psychic Noise addenda) | 213 |
| Tier 4 residual, needs its own sub-clustering pass (Section D) | 181 |
| **Total (matches the recon's 934-move catalog)** | **934** |

494 + 45 + 1 + 213 + 181 = 934, confirmed by direct addition. Zero
outstanding discrepancy.

| Sub-tier | Moves | Risk | Depends on |
|---|---|---|---|
| Bucket 1 — pure damage, no additional effect | **COMPLETE** (`[M19-bucket1]`, 61 implemented + 6 moved to Bucket 4) | — | — |
| Bucket 2 — single existing secondary mechanism | **COMPLETE** (`[M19-bucket2]`, 135 implemented + 111 reclassified — 15 to Bucket 3, 96 to Bucket 4) | — | — |
| Bucket 3 — existing mechanisms, needs scrutiny | **COMPLETE** (30/30 — 24 multi-stat `[Bucket 3 multi-stat]` + 3 combined-secondary + 2 screen+damage `[Bucket 3 clusters 1-2]` + 1 (Coaching) moved to Bucket 4) | — | — |
| Bucket 4 — genuinely new mechanism (15 sub-groups remaining) | 28 | Varies per sub-group | see Section B's own per-sub-group notes; `M19-secondary-stat-on-hit` (79 moves) is **COMPLETE** (`[M19-secondary-stat-on-hit]`, 2026-07-09); 7 single-move sub-groups (Rage/Clear Smog/Incinerate/Sparkling Aria/Throat Chop/Eerie Spell/Blood Moon) are **COMPLETE** (`[Bucket 4 cheapest singles]`, 2026-07-09); `M19-rampage` (5 moves, Uproar merged in) is **COMPLETE** (`[M19-rampage]`, 2026-07-09); `M19-recharge` (10 moves) is **COMPLETE** (`[M19-recharge]`, 2026-07-09); `M19-break-protect` (4 moves) is **COMPLETE** (`[M19-break-protect]`, 2026-07-09); `M19-recoil-on-miss` (4 moves) is **COMPLETE** (`[M19-recoil-on-miss]`, 2026-07-09); `M19-weather-conditional-accuracy` (5 moves) is **COMPLETE** (`[M19-weather-conditional-accuracy]`, 2026-07-09); `M19-secret-power` reviewed and explicitly DEFERRED by Rob, still counted here |
| M19c — Protect-family variants | 7 | Cheap | — |
| M19d — Counter/Mirror-Move remnants | 2 | Cheap-moderate | — |
| M19e — Weather-conditional heal family | 4 | Cheap-moderate | — |
| M19f — Escape-prevention family (incl. Jaw Lock, + Bucket 4's Spirit Shackle) | 4 (+1 once merged) | Moderate (new mechanism) | — |
| M19g — DISSOLVED, all 3 moves permanently excluded | 0 | — | — |
| M19h — Weight-ratio dynamic power | **COMPLETE** (`[M19-pre1]`, confirmed `[M19-rescope-followup]`) | — | — |
| M19i — Friendship-based dynamic power | **COMPLETE** (`[M19-pre1]`, confirmed `[M19-rescope-followup]`) | — | — |
| Tier 4 sub-clustering pass | 181 | Unknown — needs its own recon | not required first, but recommended for momentum |

**Recommended implementation order:**

1. **Bucket 1 (67) — COMPLETE (`[M19-bucket1]`, 2026-07-08).** 61
   implemented, 6 moved to Bucket 4. **Bucket 2 (246) — COMPLETE
   (`[M19-bucket2]`, 2026-07-08).** 135 implemented, 111 reclassified (15
   to Bucket 3, 96 to Bucket 4 — including the 79-move
   `M19-secondary-stat-on-hit` sub-group, this plan's single
   highest-leverage remaining gap). **`M19-secondary-stat-on-hit` (79) —
   COMPLETE (`[M19-secondary-stat-on-hit]`, 2026-07-09).** All 79 moves
   implemented; Bleakwind Storm(774) stays excluded (needs
   `M19-weather-conditional-accuracy` too, see Section B's note on that
   sub-group). Running total: 351→430 implemented. **Bucket 3's
   multi-stat-in-one-block cluster (25) — COMPLETE (`[Bucket 3 multi-stat]`,
   2026-07-09).** 24 implemented via a generalized `extra_stat_change_stats/
   amounts` mechanism (not a per-move flag — cheaper given last session's
   shared `_apply_stat_change_effect` extraction); Coaching(739) carved out
   (genuinely `TARGET_ALLY`) and merged into `M19-ally-targeting-stat-change`.
   Running total: 430→454 implemented. **Bucket 3's remaining two clusters
   (5) — COMPLETE (`[Bucket 3 clusters 1-2]`, 2026-07-09).** Thunder
   Fang/Ice Fang/Fire Fang (3, combined secondary effects — status in the
   existing `secondary_effect` slot, flinch in a new independent
   `secondary_effect_2` slot) + Glitzy Glow/Baddy Bad (2, screen+damage —
   new `sets_reflect_on_hit`/`sets_light_screen_on_hit` flags). **Bucket 3
   is now CLOSED (30/30).** Running total: 454→459 implemented. **7 of
   Bucket 4's cheapest single-move sub-groups (`M19-rage`/`M19-stat-reset`/
   `M19-item-destroy`/`M19-cure-opponent-status`/`M19-sound-block`/
   `M19-pp-reduce`/`M19-cant-use-twice`, 7 moves) — COMPLETE (`[Bucket 4
   cheapest singles]`, 2026-07-09).** `M19-secret-power` and `M19-uproar`
   (the other 2 moves originally proposed for this same batch) were
   investigated in the SAME session but explicitly DEFERRED by Rob, not
   shipped — see Bucket 4's own section for the corrected findings. Running
   total: 459→466 implemented. **`M19-rampage` (5 moves — Thrash/Petal
   Dance/Outrage/Raging Fury/Uproar) — COMPLETE (`[M19-rampage]`,
   2026-07-09).** Uproar's earlier deferral is now resolved by merging it
   into this sub-group (per Rob's confirmation, matching the Spirit
   Shackle/M19f precedent) rather than tracking it separately — see Bucket
   4's own section for the full findings. Running total: 466→471
   implemented. **`M19-recharge` (10 moves — Hyper Beam/Blast Burn/Hydro
   Cannon/Frenzy Plant/Giga Impact/Rock Wrecker/Roar of Time/Prismatic
   Laser/Meteor Assault/Eternabeam) — COMPLETE (`[M19-recharge]`,
   2026-07-09).** A genuine, source-confirmed correction to the commonly-
   assumed "recharges even on a miss" folklore (it does not, in this
   reference engine) — see Bucket 4's own section for the full findings.
   Running total: 471→481 implemented. **`M19-break-protect` (4 moves —
   Feint/Shadow Force/Phantom Force/Hyperspace Hole) — COMPLETE
   (`[M19-break-protect]`, 2026-07-09).** Confirmed a genuinely uniform
   mechanism across all 4 (same `MOVE_EFFECT_FEINT`), a real additional
   effect beyond this project's pre-existing `ignores_protect` field
   (post-hit `protect_active`/`protect_consecutive` clear, hit-gated same
   as `[M19-recharge]`), and a new `MoveData.SEMI_INV_VANISH` state for
   Shadow Force/Phantom Force's own two-turn mechanic — see Bucket 4's own
   section for the full findings. Running total: 481→485 implemented.
   **`M19-recoil-on-miss` (4 moves — Jump Kick/High Jump Kick/Axe Kick/
   Supercell Slam) — COMPLETE (`[M19-recoil-on-miss]`, 2026-07-09).**
   Confirmed a uniform mechanism (flat 50% of the attacker's own max HP,
   not damage-scaled) across a broader miss-scope than accuracy-only
   (Protect block and type immunity too), plus a real asymmetry with
   ordinary recoil (Magic Guard blocks it, Rock Head does not) and a
   related Reckless power-boost gap — see Bucket 4's own section for the
   full findings. Running total: 485→489 implemented.
   **`M19-weather-conditional-accuracy` (5 moves — Thunder/Hurricane/
   Bleakwind Storm/Wildbolt Storm/Sandsear Storm) — COMPLETE
   (`[M19-weather-conditional-accuracy]`, 2026-07-09).** Confirmed 2
   genuinely separate flags (always_hits_in_rain, a full bypass shared by
   all 5; accuracy_halved_in_sun, a flat-50 override shared by only
   Thunder/Hurricane) and fully resolved Bleakwind Storm's long-standing
   double-block — it turned out to have never been implemented at all, not
   merely missing its weather-accuracy half as originally assumed. Running
   total: 489→494 implemented.
2. **M19c (7)** — cheap, single shared mechanism, no dependencies.
3. **M19d, M19e (2 + 4 = 6)** — each a small, self-contained extension of an
   already-built system (`_last_attacker` tracking, weather + `RESTORE_HP`).
4. **M19f (4, or 5 once Bucket 4's Spirit Shackle is merged in per Section
   B's own recommendation)** — the one genuinely new mechanism in this
   plan's non-Bucket-4 buildable scope; budget real care per `[M17f]`'s own
   trapping-infrastructure precedent, confirm the Ghost-type/Shed Shell
   interaction against `AbilityManager.is_trapped()` before writing new
   code.
5. **Bucket 4's remaining 15 sub-groups (28 moves)** — `M19-secondary-stat-on-hit`
   (79 moves) is now **COMPLETE** (`[M19-secondary-stat-on-hit]`, 2026-07-09),
   the single new mechanism it needed (extending `try_secondary_effect`'s
   existing chance-roll gate to also dispatch a stat-change payload, applied
   via a new shared `BattleManager._apply_stat_change_effect`) unlocked all
   79 at once, exactly as this plan anticipated. 7 more single-move
   sub-groups (`M19-rage`/`M19-stat-reset`/`M19-item-destroy`/
   `M19-cure-opponent-status`/`M19-sound-block`/`M19-pp-reduce`/
   `M19-cant-use-twice`) are now **COMPLETE** (`[Bucket 4 cheapest
   singles]`, 2026-07-09) — `M19-cant-use-twice`/`M19-pp-reduce` both
   turned out to reuse the SAME pre-existing `last_move_used` field rather
   than needing any new state. `M19-secret-power` (the other move originally
   proposed for that same batch) was investigated but explicitly DEFERRED
   by Rob — it depends on an overworld-location concept this project has no
   analog for at all. **`M19-rampage` (5 moves, Uproar merged in) is now
   COMPLETE** (`[M19-rampage]`, 2026-07-09) — new shared
   `BattlePokemon.locked_move` field (kept separate from `charging_move`
   per Rob's confirmed design) plus distinct `rampage_turns`/`uproar_turns`
   counters unlocked both the 4 "true" rampage moves and Uproar's own
   forced-move-repeat lock at once. **`M19-recharge` (10 moves) is now
   COMPLETE** (`[M19-recharge]`, 2026-07-09) — a new `BattlePokemon.
   must_recharge: bool`, reusing the existing `StatusManager.
   pre_move_check` chokepoint (where Truant already lives) rather than the
   `locked_move` pattern, since recharge is a pre-move canceler with no
   move to force, not a forced-repeat lock. **`M19-break-protect` (4 moves)
   is now COMPLETE** (`[M19-break-protect]`, 2026-07-09) — new
   `MoveData.breaks_protect` flag (genuinely additional to the pre-existing
   `ignores_protect`), wired into `_do_damaging_hit` right after the
   `[M19-recharge]` block, plus a new `MoveData.SEMI_INV_VANISH` state
   (with its own explicit `StatusManager._can_hit_semi_invulnerable` case,
   since that helper's default fallthrough is `true` — the opposite of
   what Shadow Force/Phantom Force's vanish state needs) for the two
   two-turn moves in this sub-group. **`M19-recoil-on-miss` (4 moves) is
   now COMPLETE** (`[M19-recoil-on-miss]`, 2026-07-09) — new
   `MoveData.crashes_on_miss` flag plus a new `BattleManager.
   _apply_crash_damage` helper (flat 50% of the attacker's own max HP,
   Magic-Guard-only gate — confirmed NOT Rock-Head-gated, a real asymmetry
   with ordinary recoil), wired into 3 dispatch points (Protect block,
   accuracy miss, and a new type-immunity pre-check specific to
   crashes_on_miss moves, since this project's general damaging-move path
   has no separate immune signal otherwise); also fixed a related, already-
   anticipated gap in Reckless's own power-boost check. **`M19-weather-
   conditional-accuracy` (5 moves) is now COMPLETE**
   (`[M19-weather-conditional-accuracy]`, 2026-07-09) — new
   `MoveData.always_hits_in_rain` (a full accuracy-chain bypass, all 5
   moves) and `MoveData.accuracy_halved_in_sun` (a flat-50 override,
   Thunder/Hurricane only — confirmed a genuinely separate second flag, not
   shared by the Storm trio), both wired into `StatusManager.
   check_accuracy` at the same insertion points established for No
   Guard/accuracy==0 (bypass) and Wonder Skin (override); also fully
   resolved Bleakwind Storm's double-block, discovering along the way that
   it had never been implemented at all (not merely missing its weather-
   accuracy half, as the task's own framing assumed). Sequence the rest per
   Section B's own dependency-ordered recommendation: Spirit Shackle → merge
   into M19f; Spectral Thief → reuse Opportunist's pattern; the 3
   blocked-on-other-Tier4 moves → wait on their own parents; the remaining
   sub-groups → sequence freely, cheapest/single-move groups first.
   M19-heal-block-secondary (Psychic Noise) is closed/excluded, no longer
   part of this count. 3 sub-groups
   (`M19-ignores-stat-stages`/`M19-ignores-target-ability`/
   `M19-cant-use-twice`) were found during `[M19-bucket1]`'s Step 0; 7 more
   (`M19-recoil-on-miss`/`M19-percent-current-hp-damage`/
   `M19-charge-turn-spatk-boost`/`M19-weather-conditional-accuracy`/
   `M19-stat-raised-trigger`/`M19-secondary-stat-on-hit`/
   `M19-ally-targeting-stat-change`) were found during `[M19-bucket2]`'s
   Step 0.
7. **Tier 4 sub-clustering recon (181 moves)** — recommend as its OWN
   dedicated report-only session, mirroring how `docs/m19_recon.md` itself
   was produced before this plan, rather than guessing sub-tiers from
   effect-name clustering alone. Section D's own table is a head start, not
   a finished breakdown.
8. **Section C's 214 moves stay out of M19 scope**: 213 permanently
   excluded (87 Z-Move/Max-Move + 126 `[M19-exclusions]`, both confirmed by
   Rob), 1 deferred (Population Bomb) to its own small future tier once Rob
   wants it. Separately, Heal Order and Dragon Darts stay implemented —
   Rob resolved that conflict (option a, docs-only) — see Section C's
   "Resolved conflicts". M19h/M19i are COMPLETE, not part of this list.

Buckets 1 and 2 are flagged as needing further internal splitting for
execution-scale reasons only (session length), same as M19a/M19b's own
prior note — not a shape concern, both are single-shape, low-variance
batches.

---

## Open questions for Rob

1. ~~Z-Move/Max-Move exclusion (87 moves)~~ — **RESOLVED.** Rob confirmed
   the exclusion (`[M19-pre1]`), matching the Mega Evolution precedent. See
   Section C1.

2. ~~Terrain family (9 moves, Section C2)~~ — **RESOLVED.** Rob's
   `[M19-exclusions]` list includes all 9 Terrain-family moves by name —
   confirmed staying excluded, not reopening `[M17e]`'s voided decision.
   See Section C2.

3. ~~Weight/friendship data (8 moves)~~ — **RESOLVED.** `[M19-pre1]` built
   both fields and implemented all 8 moves (2 now correctly excluded from
   Bucket 1-4's pool as already-implemented; 6 tracked via M19h/M19i, see
   Open Question #6 for that pair's own still-open staleness flag).

4. **Tier 4's sub-clustering pass (181 moves, Section D)**: should this be
   scheduled as its own explicit report-only session (matching how
   `docs/m19_recon.md` itself, and this plan, were both produced) before
   any Tier 4 implementation work starts, or should Tier 4 wait entirely
   until the Bucket 1-4 / M19c-i buildable scope is done? This plan
   recommends the former (parallel-track the recon while the cheap bulk
   work proceeds) but defers the actual scheduling call to Rob's own
   preference, matching this project's established pattern of not
   pre-deciding sequencing questions that are really about Rob's available
   time and priorities, not technical dependency. **Still open.**

5. ~~Heal Order(456) / Dragon Darts(697) conflict~~ — **RESOLVED
   (2026-07-08).** Rob confirmed option (a) for both: docs-only exclusion,
   shipped code/tests untouched, no revert. See Section C's "Resolved
   conflicts".

6. ~~M19h/M19i staleness (6 moves)~~ — **RESOLVED (`[M19-rescope-followup]`,
   2026-07-08).** Confirmed directly against `gen_moves.py`: Heavy
   Slam(484)/Heat Crash(535) (M19h) and Return(216)/Pika Papow(679)/Veevee
   Volley(688)/Frustration(218) (M19i) are all real, implemented moves.
   Both sub-tiers marked COMPLETE in Section B; Section E's table and this
   document's running totals updated to match.

7. ~~Psychic Noise(845, Bucket 4's M19-heal-block-secondary)~~ —
   **RESOLVED (`[M19-rescope-followup]`, 2026-07-08).** Rob confirmed
   exclusion, matching Heal Block's own status. Dependency re-verified
   directly against source (not just trusted from the prior session's
   note): `MOVE_EFFECT_PSYCHIC_NOISE` sets the literal same
   `volatiles.healBlock` field Heal Block itself sets. Moved to Section C2
   alongside Heal Block.

8. **Secret Power(290, Bucket 4's M19-secret-power)**: its secondary effect
   depends on terrain/location, which this project has no system for.
   Likely resolves to one fixed effect by default, but needs Rob's
   explicit scope confirmation before assuming that rather than excluding
   it alongside the Terrain-family moves. **New, open.**
