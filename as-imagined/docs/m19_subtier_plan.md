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

Of the reference catalog's **934 real moves**, **513 are already implemented**
and are excluded from every count below. **421 moves remain.** Of those 421:

- **26 fall into proposed sub-tiers**: 9 in the mechanism-based Buckets
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
  Kick/Axe Kick/Supercell Slam, `[M19-recoil-on-miss]`, 2026-07-09),
  `M19-weather-conditional-accuracy` (5 moves — Thunder/Hurricane/Bleakwind
  Storm/Wildbolt Storm/Sandsear Storm, `[M19-weather-conditional-accuracy]`,
  2026-07-09), and 9 more 2-move (and one 3-move) sub-groups —
  `M19-percent-current-hp-damage`/`M19-ignores-stat-stages`/
  `M19-charge-turn-spatk-boost`/`M19-hp-based-power`/
  `M19-stat-raised-trigger`/`M19-random-status-choice`/`M19-self-faint`/
  `M19-berry-steal`/`M19-ignores-target-ability` (19 moves,
  `[Bucket 4 2-move sub-groups]`, 2026-07-09) — are now CLOSED/complete
  and no longer counted as pending, for
  a 9-move Bucket 4-only total) + 17 in M19c-i
  (Section B — M19h/M19i's 6 moves are COMPLETE and no longer counted as
  pending: M19c(7) + M19d(2) + M19e(4) + M19f(4) + M19g(0)).
- **0 remain deferred** (Population Bomb, Section C3, was deferred as of
  this note but has SINCE been permanently excluded by Rob, 2026-07-10 —
  see Section E's current reconciliation for the up-to-date figures; C4 is
  closed, folded into the 9 above).
- **213 are permanently excluded** (87 Z-Move/Max-Move + 126 from Rob's
  `[M19-exclusions]` list [124 original + Raging Bull + Psychic Noise],
  Section C1–C2 — unchanged by this update).
- **181 (a Tier 4 residual)** — **`[M19-section-d-cluster]` update
  (2026-07-09): Section D now has a full mechanism-clustered breakdown**
  (21 effect-name clusters/51 moves, a 130-move singleton pool with a
  first-pass difficulty sweep, and a priority-unblock spotlight on Leech
  Seed/Haze/Aromatherapy+Heal Bell that directly resolves Bucket 4's
  `M19-blocked-on-other-tier4` gate) — no longer just a placeholder
  awaiting a future pass. See Section D itself for the full writeup;
  concrete sub-tiers can now be picked off it the same way sessions have
  been picking sub-groups off Bucket 4.

**26 + 1 + 213 + 181 = 421**, exactly matching `934 − 513`. Fully
reconciled — no outstanding discrepancy. **Bucket 3 is now CLOSED (30/30)**
— see its own section below for the full writeup of both remaining
clusters (`[Bucket 3 clusters 1-2]`, 2026-07-09). **`M19-rampage` (5/5,
Uproar merged in), `M19-recharge` (10/10), `M19-break-protect` (4/4),
`M19-recoil-on-miss` (4/4), `M19-weather-conditional-accuracy` (5/5), and
all 9 of the bundled 2-move sub-groups (19 moves) are
all now CLOSED** — see
the Bucket 4 section below and `docs/decisions.md`'s `[M19-rampage]`/
`[M19-recharge]`/`[M19-break-protect]`/`[M19-recoil-on-miss]`/
`[M19-weather-conditional-accuracy]`/`[Bucket 4 2-move sub-groups]` entries for
the full findings. Bucket
4's `M19-secret-power` sub-group was investigated and DEFERRED as of this
note, but has SINCE been permanently excluded by Rob (2026-07-10) — see
`docs/decisions.md`'s `[Bucket 4 cheapest singles]` entry for the original
Step 0 findings and Section E's current reconciliation for the up-to-date
figures.

---

## Section A — Scope classification (per the recon's corrected Tier breakdown)

| Recon Tier | Total moves | Already implemented | **Remaining** | Where it lands in this plan |
|---|---|---|---|---|
| Tier 1 — no-effect / pure damage | 157 | 93 (14 + 15 `[M19a-gen1]` + 61 `[M19-bucket1]` + 1 `[M19-bucket2]` + Thrash/Petal Dance `[M19-rampage]`) | **64** | 15 permanently excluded (14 `[M19-exclusions]` + Psychic Noise, `[M19-rescope-followup]`, Section C2); remaining 49 folded into Bucket 4 below (Buckets 1 AND 2 are now both CLOSED/complete) |
| Tier 2 — simple secondary effect | 308 | 297 (42 + Low Kick/Grass Knot, `[M19-pre1]` + 134 `[M19-bucket2]` + 79 `[M19-secondary-stat-on-hit]` + 24 `[Bucket 3 multi-stat]` + 5 Thunder/Ice/Fire Fang + Glitzy Glow/Baddy Bad `[Bucket 3 clusters 1-2]` + 7 Rage/Clear Smog/Incinerate/Sparkling Aria/Throat Chop/Eerie Spell/Blood Moon `[Bucket 4 cheapest singles]` + Jump Kick/High Jump Kick/Axe Kick/Supercell Slam `[M19-recoil-on-miss]`) | **11** | 10 permanently excluded (Section C2); remaining 1 folded into Bucket 4 below (Buckets 1, 2, `M19-secondary-stat-on-hit`, Bucket 3 in its entirety, and `M19-recoil-on-miss` are now all CLOSED/complete — reverse-engineered as this Tier's own origin, matching this doc's pre-existing "remaining 5 folded into Bucket 4" note, since none of the 4 was individually itemized before this session) |
| Tier 2b — Protect-family variants | 10 | 8 (1 + 7 `[M19c]`/`[M19d]`) | **2** | M19c — **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09); the remaining 2 are permanently excluded (Crafty Shield/King's Shield, Section C2), not outstanding |
| Tier 3a — Multi-hit family | 31 | 30 | **1** | C3 (Population Bomb, deferred to its own future tier — also on Rob's `[M19-exclusions]` list, consistent, no status change). Dragon Darts(697) is one of the 30 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Tier 3b — Binding-move family | 11 | 11 (10 + Jaw Lock `[M19e]`/`[M19f]`) | **0** | M19f — **COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09) — Jaw Lock does NOT share the `[M18.5f]` binding-move mechanism, confirmed the `MOVE_EFFECT_TRAP_BOTH` variant of escape-prevention instead |
| Tier 3c — Terrain family | 9 | 0 | **9** | Permanently excluded (`[M19-exclusions]`, Section C2) — resolves Open Question #2 |
| Tier 3d — Counter/Mirror-Move family | 5 | 4 (2 + 2 `[M19c]`/`[M19d]`) | **1** | M19d — **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09) + 1 permanently excluded (Comeuppance, Section C2) |
| Tier 3e — Weather-conditional heal family | 4 | 4 (`[M19e]`/`[M19f]`, 2026-07-09) | **0** | M19e — **COMPLETE** |
| Tier 4 — high complexity / standalone | 312 | 88 (33 + 6 `[M19-pre1]`/M19h+M19i, corrected `[M19-rescope-followup]` + Outrage/Raging Fury/Uproar `[M19-rampage]` + 10 `[M19-recharge]` + 4 `[M19-break-protect]` + 5 `[M19-weather-conditional-accuracy]` + 19 `[Bucket 4 2-move sub-groups]` + Spectral Thief/Howl/Aromatic Mist/Coaching `[M19-steal-stats]`/`[M19-ally-targeting-stat-change]` + Spider Web/Mean Look/Block/Spirit Shackle `[M19e]`/`[M19f]`) | **224** | M19f's 3 carved moves (Spider Web/Mean Look/Block) plus Bucket 4's Spirit Shackle (reverse-engineered as this Tier's own origin, matching the disclosed-simplification convention `[Bucket 4 2-move sub-groups]` established) are now COMPLETE, no longer carved as pending; M19g dissolved/M19h/M19i now COMPLETE too; 89 permanently excluded (3 ex-M19g + 85 residual + Raging Bull, Section C2); **181 residual** (Section D). Heal Order(456) is one of the 39 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Z-Move (permanently excluded) | 35 | 0 | **35** | C1 |
| Max Move / Dynamax (permanently excluded) | 52 | 0 | **52** | C1 |
| **Total** | **934** | **535** (corrected, `[M19c]`/`[M19d]` — was 526) | **399** | |

**Every "already implemented" figure in this table now sums to exactly
513** (93+297+1+30+10+0+2+0+80+0+0), and every "remaining" figure sums to
exactly 421 (64+11+9+1+1+9+3+4+232+35+52) — confirmed via direct
addition, matching `934 − 513 = 421` exactly. Zero outstanding
discrepancy as of `[Bucket 4 2-move sub-groups]`. (This session's Tier
attribution for all 19 newly-shipped moves — all Tier 4, none Tier 1/2/3
— is a SIMPLIFICATION, explicitly flagged as such: 5 of the 9 sub-groups
were originally cited as "found during `[M19-bucket1]`/`[M19-bucket2]`'s
Step 0" in this doc's own prose, suggesting a Tier 1/2 origin, but none
of these 19 moves was ever individually itemized in ANY earlier session's
per-Tier breakdown with enough precision to split them correctly across
Tier 1 vs. Tier 2 vs. Tier 4 without risking a double-count against
Tier 2's own already-exhausted "5 folded into Bucket 4" allocation
(`[M19-recoil-on-miss]` already claimed 4 of that 5). Bucket-4-wide
arithmetic closure (all 19 attributed to Tier 4) was the only method that
closed cleanly without over-drawing any single Tier row's own remaining
pool — a deliberate, disclosed approximation, not a claim that all 19
moves were originally Tier-4-classified by the recon.)
(The 5 weather-conditional-accuracy moves' own earlier attribution — all
Tier 4, none Tier 1/2 — was reverse-engineered from the reconciliation
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

### Bucket 4 — Needs a genuinely new mechanism (0 moves remaining — `M19-blocked-on-other-tier4` CLOSED by `[D0]`, 2026-07-09; `M19-secret-power` PERMANENTLY EXCLUDED by Rob, 2026-07-10 — Bucket 4 is now fully closed)

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
resolving Bleakwind Storm's long-standing double-block. **9 of Bucket 4's
remaining 2-move (and one 3-move) sub-groups are now ALL COMPLETE**
(`[Bucket 4 2-move sub-groups]`, 2026-07-09) — `M19-percent-current-hp-damage`,
`M19-ignores-stat-stages`, `M19-charge-turn-spatk-boost`,
`M19-hp-based-power`, `M19-stat-raised-trigger`, `M19-random-status-choice`,
`M19-self-faint`, `M19-berry-steal`, and `M19-ignores-target-ability`,
bundled into one session matching `[Bucket 4 cheapest singles]`'s own
precedent — each sub-group verified independently from source, none
assumed to share a mechanism just because they were bundled together.
Shrinks Bucket 4's own total 28→9 moves, 15→6 sub-groups.

**Doc-drift fix (found during the `[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`
session, 2026-07-09)**: the "9 moves, 6 named sub-groups" figure carried at
the top of this section (and mirrored in Section E's summary table and the
"recommended execution order" list) was WRONG by one sub-group — a fresh,
careful count of the actual open (non-CLOSED) bullets below found only 5:
`M19-secret-power`, `M19-trap-secondary`, `M19-steal-stats`,
`M19-blocked-on-other-tier4`, `M19-ally-targeting-stat-change`. Traced the
drift's origin: adding the immediately-prior session's own 9 newly-closed
sub-group names back to this fresh count of 5 yields a reconstructed
pre-session baseline of 14, not the claimed 15 — meaning the drift PRE-DATES
`[Bucket 4 2-move sub-groups]`'s own session (whose internal "15→6"
arithmetic was self-consistent given ITS stated starting point of 15; that
starting point was already off by one before that session began). Not
re-litigated further, just corrected here. **`M19-steal-stats` and
`M19-ally-targeting-stat-change` are now BOTH CLOSED, COMPLETE
(`[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`, 2026-07-09)** — see
their own entries below for the full findings, including two corrections to
this section's own prior framing (Spectral Thief does NOT reuse
Opportunist's pattern; ally-targeting stat-change infrastructure already
existed via Helping Hand, contrary to the original "no mechanism exists in
any form" claim). Shrinks Bucket 4's own total 9→5 moves, 6→3 sub-groups
(post-drift-fix baseline) — the 3 remaining sub-groups are
`M19-secret-power` (deferred), `M19-trap-secondary` (gated on M19f), and
`M19-blocked-on-other-tier4` (gated on Leech Seed/Haze/Aromatherapy).
**Both later fully resolved**: `M19-trap-secondary` closed the same day,
folded into M19f (`[M19e]`/`[M19f]`, 2026-07-09, see that entry above);
`M19-blocked-on-other-tier4` closed in a later session (`[D0]`,
2026-07-09, see its own CLOSED entry above and Section D's D0 below) —
Bucket 4's final state at that point was **1 move, 1 sub-group**
(`M19-secret-power` only, deferred by Rob) — **since permanently excluded
by Rob, 2026-07-10, closing Bucket 4 entirely.**

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
- **M19-self-faint — CLOSED, COMPLETE (`[Bucket 4 2-move sub-groups]`,
  2026-07-09).** Self-Destruct(120), Explosion(153). Confirmed
  `CancelerExplosion` is a genuine PRE-MOVE canceler (zeroes the user's HP
  BEFORE accuracy/damage resolution even runs) — the self-faint happens
  regardless of whether the hit lands, verified via a forced-miss test.
  Damp blocks the move entirely, reusing the pre-existing
  `AbilityManager.is_damp_active` built for `[M17n-8]`'s Aftermath — a
  simplified EXECUTION-time translation of source's SELECTION-time
  `.dampBanned` legality flag, since this project has no move-selection
  menu filter. `TARGET_FOES_AND_ALLY` (hits opponents AND the user's own
  ally in doubles) modeled as `is_spread` (opponents only) — the ally-hit
  half is a flagged, not-built doubles-only gap (same class as Shell
  Bell's own deferred gap, M22).
- **M19-random-status-choice — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Tri Attack(161), Dire Claw(755). Confirmed
  genuinely DIFFERENT pools, not shared: Tri Attack picks uniformly from
  {burn, freeze-or-frostbite, paralysis} (resolves to plain STATUS_FREEZE
  at this project's config — no STATUS_FROSTBITE exists anywhere here);
  Dire Claw picks uniformly from {poison, paralysis, sleep}. Both reuse
  `StatusManager.try_apply_status` directly, which already gates on
  "already has a status" the same way every other status move does — no
  new immunity logic needed. New `SE_RANDOM_STATUS` token +
  `random_status_pool: Array[int]` field + a new `force_random_status_index`
  test seam on `try_secondary_effect`.
- **M19-hp-based-power — CLOSED, COMPLETE (`[Bucket 4 2-move sub-groups]`,
  2026-07-09).** Flail(175), Reversal(179). Confirmed a STEPPED/BANDED
  formula from the user's own missing-HP fraction, NOT continuous (the
  task's own flagged risk, verified from source directly): `hp_fraction =
  floor(current_hp*48/max_hp)` (floored up to 1 if >0), then the first
  ascending threshold {1:200, 4:150, 9:100, 16:80, 32:40, 48:20} the
  fraction is <= wins. New `_flail_power` helper, same established
  banded-table pattern as Magnitude/Heat Crash/Low Kick.
- **M19-rage — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Rage(99). Step 0 corrected the plan's own one-line
  summary: NOT a rampage-lock (no `gLockedMoves` in source at all) — a
  genuinely simple persistent `rage_active` volatile, set on a successful
  hit, cleared the moment the user chooses a DIFFERENT move; while active,
  the holder's Attack rises +1 whenever THEY take any damaging hit
  (self/ally-hit excluded, capped at +6).
- **M19-secret-power — investigated, PERMANENTLY EXCLUDED (2026-07-10, Rob's
  explicit decision — was DEFERRED as of `[Bucket 4 cheapest singles]`,
  2026-07-09, now closed out).** Secret Power(290). Step 0 resolved Open
  Question #8 with a real finding: the secondary depends on
  `gBattleEnvironment`, an OVERWORLD map/tile-derived field (set from the
  actual battle background — grass/cave/water/building/etc. — via
  `BattleSetup_GetEnvironmentId()`), structurally unrelated to the
  already-excluded in-battle Terrain mechanic and with zero analog in this
  project (no map system at all). The natural default would have been
  `BATTLE_ENVIRONMENT_PLAIN`'s own GEN_LATEST effect — a flat 30%
  Paralysis chance, confirmed cheap and schema-representable — but Rob
  chose not to take that path, and has since confirmed permanent exclusion
  rather than leaving it as an open deferral. Moves from "Proposed
  sub-tiers" into "Permanently excluded" — see Section E's reconciliation.
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
- **M19-berry-steal — CLOSED, COMPLETE (`[Bucket 4 2-move sub-groups]`,
  2026-07-09).** Pluck(365), Bug Bite(450). Confirmed both share the
  LITERAL SAME `MOVE_EFFECT_BUG_BITE` additionalEffect (Pluck's own name
  is a historical artifact, not a distinct mechanism). Steals the target's
  berry and IMMEDIATELY consumes its effect on the ATTACKER — genuinely
  different from `M19-item-destroy`'s Incinerate (destroys, no beneficiary
  effect) and from Pickpocket/Magician/Sticky Barb (possession TRANSFER,
  held not eaten). Blocked entirely by the target's own Sticky Hold; a
  held Jaboca/Rowap Berry is exempt (triggers its own retaliation instead
  of being stolen — source checks this FIRST). New `ItemManager.
  steal_and_eat_berry_effect` reuses 4 existing per-berry-family functions
  (HP-threshold heal, status-cure, confusion-cure, stat-raise) via their
  own pre-existing `override_item` parameter — the same forced-trigger
  pattern `[M17n-7]`'s Cud Chew fix established. **Explicitly scoped, not
  exhaustive**: Starf Berry's random-stat pick, Micle, Enigma, White Herb,
  Weakness Policy, Lansat, and Custap are NOT wired into this steal path —
  a genuine, flagged scope limitation, not a silently-dropped case.
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
- **M19-trap-secondary — CLOSED, COMPLETE (`[M19e]`/`[M19f]`, 2026-07-09,
  folded into M19f as originally planned).** Spirit Shackle(625) inflicts
  escape-prevention as a SECONDARY effect on a damaging hit
  (`MOVE_EFFECT_PREVENT_ESCAPE`) — confirmed the same underlying
  `escapePrevention` state Mean Look/Block/Spider Web/Jaw Lock set (built
  together with M19f in the same session, resolving this gate directly
  rather than as a future follow-up). See M19f's own entry (Section B
  above) for the full findings, including the real Ghost-type-immunity
  asymmetry Spirit Shackle does NOT share with the 3 status moves.
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
- **M19-steal-stats — CLOSED, COMPLETE (`[M19-steal-stats]`, 2026-07-09).**
  Spectral Thief(666). **A real correction to this sub-group's own original
  "reuse Opportunist's pattern" note**: Opportunist reacts to a fresh
  stat-RISE EVENT elsewhere (copying the same delta without touching the
  original mon's own stage); Spectral Thief instead snapshots-and-TRANSFERS
  whatever positive stages ALREADY exist at the moment of use, across ALL 7
  stats (confirmed via source's `NUM_BATTLE_STATS = NUM_STATS + 2`, which
  includes Accuracy/Evasion, unlike Starf Berry's narrower 5-stat pool),
  zeroing the target's own stage in the process — a custom orchestration was
  built instead, reusing only `StatusManager.apply_stat_change` as the
  actual mutation primitive. Dispatched via `.preAttackEffect = TRUE` in
  source — fires BEFORE the move's own accuracy roll, UNCONDITIONAL on
  whether the subsequent hit connects (confirmed via a forced-miss test:
  the steal still fires). Per-stat gated on the ATTACKER's own stage for
  that stat not already being at +6 — confirmed from source
  (`battle_script_commands.c` L3355) that this gate covers BOTH halves of
  the transfer together: when the attacker is capped on a given stat, the
  DEFENDER's matching stage is also left untouched for that stat (not
  zeroed anyway), a real correction to an initial test-authoring assumption
  caught during this session's own test-writing. Type immunity blocks the
  steal specifically (not the whole move) — the move still proceeds to its
  own zero-damage resolution. 27/27 tests (shared with
  `M19-ally-targeting-stat-change` below in one combined suite), stable;
  10-suite regression clean.
- **M19-ally-targeting-stat-change — CLOSED, COMPLETE
  (`[M19-ally-targeting-stat-change]`, 2026-07-09).** Howl(336), Aromatic
  Mist(597), Coaching(739). **A real correction to this sub-group's own
  original "no ally-targeting stat-change mechanism exists in any form"
  claim**: this project already had exactly such a mechanism, via Helping
  Hand's own established `TARGET_ALLY`/"fails if not doubles" dispatch
  shape (`[M14b]`) and the pre-existing general-purpose
  `BattleManager._get_ally()` helper — just not yet reused for a second
  move. Aromatic Mist/Coaching are TARGET_ALLY ONLY (never self, never
  opponent) — fails entirely (`move_effect_failed`, reason `"not_doubles"`)
  if not in doubles or the ally has fainted (`_get_ally` already handles
  both cases). Coaching's 2-stat payload (Atk+1, Def+1) reuses the
  pre-existing `extra_stat_change_stats`/`amounts` multi-stat mechanism
  (`[Bucket 3 multi-stat]`) with zero further changes. Howl is
  TARGET_USER_AND_ALLY at this project's GEN_LATEST config — the self half
  is an ordinary self-buff (already handled by the general
  `stat_change_self` dispatch); a new `also_boosts_ally` flag bolts the
  SAME stat change onto the user's own ally too, a genuine no-op in singles
  and the only difference from a plain self-buff move in doubles. 27/27
  tests (shared with `M19-steal-stats` above), stable across reruns;
  10-suite regression clean (`damage_test`/`move_test`/`stat_test`/
  `status_test` plus `doubles_test`/`m17n8_test`/`m17l_test`/
  `m19_secondary_stat_test`/`m19_bucket3_multistat_test`).
- **M19-blocked-on-other-tier4 — CLOSED, COMPLETE (`[D0]`, 2026-07-09).**
  Sappy Seed(685), Freezy Frost(686), Sparkly Swirl(687). Unblocked and
  shipped in the SAME session as their 3 parent mechanisms (Leech
  Seed(73)/Haze(114)/Aromatherapy(312)+Heal Bell(215), see D0's own CLOSED
  entry in Section D below) — all 3 confirmed genuinely trivial once their
  parents existed: each is a plain `EFFECT_HIT` damage move with a
  GUARANTEED (no `.chance` field) secondary reusing the parent primitive
  verbatim (Sappy Seed → `StatusManager.try_apply_leech_seed`; Freezy
  Frost → the shared `_reset_stat_stages` loop, over EVERY combatant, not
  just the target; Sparkly Swirl → `_apply_heal_bell`, applied to the
  ATTACKER'S OWN party even though the move damages an opponent, matching
  source's `Cmd_healpartystatus` always operating on
  `GetBattlerParty(gBattlerAttacker)` regardless of the move's own
  `.self = TRUE` flag). Section D's own "open architecture question" flag
  on Aromatherapy's party-wide-cure scope is now resolved — see D0.
- **M19-pp-reduce — CLOSED, COMPLETE (`[Bucket 4 cheapest singles]`,
  2026-07-09).** Eerie Spell(754). Step 0's real finding: NO new tracking
  state was needed at all — this project already has comprehensive
  per-battler `last_move_used` tracking (wired since `[M16e]`'s Conversion
  2), directly reusable to find the target's own move slot and deduct 3 PP
  (capped at available PP via the existing `use_pp(idx, amount)`). Explicit
  chance=100 in source, same true-secondary shape as Throat Chop above.
- **M19-ignores-stat-stages — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Chip Away(498), Sacred Sword(533), Darkest
  Lariat(626). **A real correction to this sub-group's own original "no
  bypass path exists" framing**: this project's existing Unaware
  implementation already established the EXACT insertion points needed —
  `DamageCalculator.calculate`'s `def_stage = 0` reset (alongside
  `ignores_defender_def_stage`) and `StatusManager.check_accuracy`'s
  `eva_stage = 0` reset (alongside `ignores_defender_evasion_stage`). One
  new `ignores_defense_evasion_stages` flag, checked at both existing
  sites — zero new mechanism needed, confirmed cheaper than originally
  assumed.
- **M19-ignores-target-ability — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Sunsteel Strike(667), Moongeist Beam(668).
  Confirmed from source (`battle_util.c` L9800) that this move-level flag
  sets the LITERAL SAME `moldBreakerActive` flag Mold Breaker/Mycelium
  Might already use — not a separate, parallel mechanism. `AbilityManager.
  effective_ability_id`'s existing `attacker_move` param (already built for
  Mycelium Might) gained a third OR condition; `move` threaded as
  `attacker_move` into every damage-pipeline ability check that already
  reaches Mold Breaker (`defense_damage_modifier_uq412`, `blocks_move_type`
  /Levitate, `blocks_non_super_effective_hit`/Wonder Guard,
  `absorbs_move_type`/the absorb family) — inherits Mold Breaker's EXACT
  scope for free, since it's the identical underlying flag, not
  independently re-scoped.
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
- **M19-percent-current-hp-damage — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Super Fang(162), Ruination(803). New
  `percent_current_hp_damage: int` field, inserted at the exact same
  bypass point `fixed_damage`/`level_damage` already occupy in
  `DamageCalculator.calculate` (after type immunity/Wonder Guard, before
  STAB/crit/roll) — `damage = defender.current_hp * pct / 100`, confirmed
  reading CURRENT hp specifically (tested with a pre-damaged defender as a
  discriminator against a max-hp-based formula).
- **M19-charge-turn-spatk-boost — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Meteor Beam(728), Electro Shot(833). New
  `charge_turn_spatk_boost` field — a deliberate PARALLEL field to Skull
  Bash's `charge_turn_defense_boost`, not a generalization of it (avoids
  any risk to Skull Bash's own already-working behavior, per this
  sub-group's own explicit scope preference). Confirmed Electro Shot's
  own rain-skip is a SEPARATE flag (`skips_charge_in_rain`) from the
  stat-boost flag — Meteor Beam has the boost but NOT the skip, verified
  individually rather than assumed symmetric; a parallel `_rain_skip`
  check alongside the existing `_solar_skip`, combined into `_weather_skip`.
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
- **M19-stat-raised-trigger — CLOSED, COMPLETE (`[Bucket 4 2-move
  sub-groups]`, 2026-07-09).** Burning Jealousy(735), Alluring Voice(842).
  New `BattlePokemon.stat_raised_this_turn` flag, set at the SAME single
  chokepoint every stat-raising path in this project already routes
  through (`StatusManager.apply_stat_change`, whenever a positive stage
  delta actually applies — matching source's own broad "any positive stat
  change, from a move/ability/item alike" concept), cleared each turn
  alongside `protect_active`/`flinched`. Confirmed self-triggering isn't a
  real risk for these 2 moves specifically — neither raises stats itself.
  New `requires_target_stat_raised` gate, checked as a pure eligibility
  pre-check in `try_secondary_effect`, before the chance roll (matching
  source's own `AdditionalEffectsMoveConditionMet` ordering).
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
(`M19-ally-targeting-stat-change` — see its own CLOSED entry above,
alongside `M19-steal-stats`, for the full findings; both are now COMPLETE.)

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
moves across 18 sub-groups. `M19-break-protect` (4), `M19-recoil-on-miss`
(4), `M19-weather-conditional-accuracy` (5), and the 9 2-move sub-groups
(19) have since ALSO shipped (`[M19-break-protect]`/`[M19-recoil-on-miss]`/
`[M19-weather-conditional-accuracy]`/`[Bucket 4 2-move sub-groups]`, all
2026-07-09): 41-4-4-5-19 = 9 moves across 6 sub-groups, matching the
pre-drift-fix header. **`M19-steal-stats` (1) and
`M19-ally-targeting-stat-change` (3) have since ALSO shipped
(`[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`, 2026-07-09): 9-1-3
= 5 moves across 3 sub-groups (`M19-secret-power`, `M19-trap-secondary`,
`M19-blocked-on-other-tier4`), matching this section's own post-drift-fix
header above.** **`M19-trap-secondary` (1, Spirit Shackle) has since ALSO
shipped, folded into M19f (`[M19e]`/`[M19f]`, 2026-07-09): 5-1 = 4 moves
across 2 sub-groups (`M19-secret-power`, `M19-blocked-on-other-tier4`),
matching this section's own current header.)

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
   - **M19-trap-secondary (Spirit Shackle) — CLOSED, COMPLETE
     (`[M19e]`/`[M19f]`, 2026-07-09).** Folded directly into M19f exactly
     as this bullet anticipated — see M19f's own CLOSED entry (Section B
     above) for the full findings.
   - **M19-steal-stats (Spectral Thief)** should reuse Opportunist's
     existing ability-side "copy a positive stat raise" pattern
     (`[M17n-8]`) rather than building fresh.
   - **M19-blocked-on-other-tier4 (Sappy Seed/Freezy Frost/Sparkly
     Swirl)** can't be scheduled independently — each waits on its own
     parent mechanism (Leech Seed/Haze/Aromatherapy) landing first. **Now
     resolved**: Section D's `[M19-section-d-cluster]` pass (2026-07-09)
     found all 3 parent mechanisms are CHEAP with zero new
     `BattleManager`-level infrastructure needed — see Section D's own D0
     for the full writeup, flagged there as the recommended next M19
     session.
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

### M19c — Protect-family variants (7 moves) — **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09)

Wide Guard(469), Quick Guard(501), Spiky Shield(596), Baneful Bunker(624),
Obstruct(720), Silk Trap(780), Burning Bulwark(836). Confirmed all 7 share
the LITERAL SAME `.effect = EFFECT_PROTECT` as Protect(182)/Detect
themselves in source, distinguished only by a per-move
`.argument.protectMethod` value, and the SAME shared consecutive-use
fail-chance counter (`usesProtectCounter` is a per-EFFECT setting, not
per-move) — zero changes needed to the existing `is_protect` dispatch or
`_roll_protect_success`. Confirmed genuinely NOT uniform beyond that shared
base, exactly as this sub-tier's own "don't assume symmetry" flag
anticipated: Obstruct/Silk Trap block only NON-STATUS moves (a real
narrowing from plain Protect's "blocks everything"); Wide Guard/Quick Guard
are SIDE-WIDE (checked against the defender's own state AND its ally's —
source's `IsSideProtected` reads the SAME per-battler `protected` field for
either battler on the side, not a separate side-level flag, so this
project's existing per-mon `protect_active`/new `protect_method` fields
needed no new `_side_conditions`-style infrastructure at all); Wide Guard
blocks only SPREAD moves (`is_spread`), Quick Guard blocks only
PRIORITY>0 moves via the SAME ability-boosted effective-priority
computation (`AbilityManager.move_priority_bonus`) `[M17k]`'s
`blocks_priority_move` already established for the identical
`GetChosenMovePriority` source function. The 5 contact-punish variants
(Spiky Shield's maxHP/8 recoil, Baneful Bunker's poison, Burning Bulwark's
burn, Obstruct's -2 Def, Silk Trap's -1 Speed) are gated on
`AbilityManager.move_triggers_contact_retaliation` — the SAME
Protective-Pads-aware wrapper Rough Skin/Iron Barbs/Rocky Helmet already
use, confirmed from source as the correct (wrapper-level, not the narrower
`move_makes_contact`) gate for this exact effect family
(`MoveEndProtectLikeEffect`'s own `CanBattlerAvoidContactEffects` check).
Obstruct/Silk Trap's stat-drops reuse the raw `StatusManager.
apply_stat_change` primitive plus an inline Defiant/Competitive
reactive-trigger check (matching `_apply_one_stat_change_pair`'s own
established shape for "an opponent lowered my stat"), a real correctness
gap closed proactively rather than flagged-and-skipped.

**`[M19-exclusions]` update:** 2 moves permanently excluded and removed
from this count (9→7): Crafty Shield(578), King's Shield(588). See
Section C2.

### M19d — Counter/Mirror-Move remnants (2 moves) — **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09)

Mirror Move(119), Metal Burst(368). **Metal Burst**: confirmed the same
`EFFECT_REFLECT_DAMAGE` shape as Counter/Mirror Coat, but with two real,
source-confirmed asymmetries this sub-tier's own framing flagged as worth
checking — 1.5x (not Counter/Mirror Coat's 2x) and reflects EITHER category
(source: `.argument.reflectDamage.damageCategories = PHYSICAL | SPECIAL`,
vs. each of Counter/Mirror Coat's own single-category bitmask), plus a
THIRD, not-originally-flagged asymmetry found at Step 0: priority=0, NOT
Counter/Mirror Coat's own -5. When both categories were taken in the same
turn (doubles), reflects whichever was hit LAST (a new
`BattlePokemon.last_hit_was_special` flag, mirroring source's own
`lastHitBySpecialMove`), not the larger of the two — confirmed via
`GetReflectDamageMoveDamageCategory`. Deliberately kept as its own separate
`metal_burst` flag rather than generalizing `counter`/`mirror_coat` into
one data-driven mechanism, avoiding any risk to their own already-tested
dispatch. **Mirror Move**: the real open question, given real Step 0
attention as instructed — confirmed via direct source read
(`GetMirrorMoveMove`, battle_move_resolution.c L4966-4993) that it reads
`lastTakenMove[gBattlerAttacker]` — the move that hit the MIRROR MOVE USER
itself, a GENUINELY DIFFERENT tracking axis from "the target's own
last-used move" (a Copycat-style lookup this project doesn't have and
didn't need to build). This project's existing per-turn
`_last_attacker`/`_last_attacker_move` dictionaries (already built for
Destiny Bond/Aftermath/Innards Out, cleared every turn) already capture
EXACTLY this — zero new tracking state needed, resolving the sub-tier's
own flagged uncertainty in the cheaper direction. Confirmed Mirror Move
dispatches through the LITERAL SAME `CancelerCallSubmove` mechanism as
Metronome (`EFFECT_MIRROR_MOVE` and `EFFECT_METRONOME` are two cases of one
switch) — reused this project's existing Metronome "reassign `move` and
fall through to normal dispatch" pattern directly, with `defender` also
reassigned to the actual hitter (`_last_attacker`) for doubles-correctness.
Fails outright if the user hasn't been hit by any move yet this turn; no
move-category exclusion exists in source for what can be mirrored.

**`[M19-exclusions]` update:** 1 move permanently excluded and removed from
this count (3→2): Comeuppance(820). See Section C2.

### M19e — Weather-conditional heal family (4 moves) — **COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09)

Morning Sun(234), Synthesis(235), Moonlight(236), Shore Up(622). Confirmed
all 4 share ONE dispatch function in source (`Cmd_recoverbasedonsunlight`,
battle_script_commands.c L8622-8689), not 4 independent implementations
despite 4 separate `EFFECT_*` move-data IDs. Two genuinely different
fraction shapes, confirmed individually rather than assumed uniform: Morning
Sun/Synthesis/Moonlight share a 3-way formula (sun=2/3, no-weather=1/2,
any OTHER weather incl. rain/sand/hail=1/4); Shore Up has only TWO states
(sandstorm=2/3, everything else=1/2 — genuinely no 1/4 branch at all, a
real non-uniformity within this 4-move sub-group). Two further nuances
found and correctly modeled: Strong Winds (Delta Stream) is treated as
"no weather" (the 1/2 case) for the 3 sun-based moves specifically, NOT the
1/4 "other weather" case (source strips the Strong Winds bit before the
weather-presence check); Utility Umbrella strips SUN/RAIN specifically for
those same 3 moves (turning either into the "no weather" 1/2 case) but does
NOT strip Sandstorm/Hail (which still correctly fall into the 1/4 branch),
and has ZERO effect on Shore Up at all (its own branch never references
Umbrella). New `MoveData.heals_based_on_weather`/`weather_heal_boost_type`/
`weather_heal_has_quarter_branch` fields; new `BattleManager.
_weather_heal_amount()` helper; dispatch shares `is_restore_hp`'s exact
"fails at full HP" shape.

### M19f — Escape-prevention family (5 moves) — **COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09)

Spider Web(169), Mean Look(212), Block(335), Jaw Lock(692), **plus Spirit
Shackle(625)** (merged in from Bucket 4's `M19-trap-secondary`, resolving
its own gate — confirmed genuinely the SAME mechanism, not just
thematically similar: Spirit Shackle's `MOVE_EFFECT_PREVENT_ESCAPE`
secondary and Mean Look's own `EFFECT_MEAN_LOOK` script both set the
literal same `volatiles.escapePrevention`/`battlerPreventingEscape` state).
Confirmed from source that Jaw Lock's `MOVE_EFFECT_TRAP_BOTH` is a genuine
THIRD variant of this exact mechanism (not a separate one) — it sets the
SAME `escapePrevention` field on BOTH battlers simultaneously, gated on
NEITHER already being trapped (a stricter all-or-nothing guard than Spirit
Shackle's own single-sided check). New `BattlePokemon.escape_prevented_by`
(direct object reference, mirroring `wrapped_by`/`infatuated_by`'s own
shape exactly) plus `StatusManager.try_apply_escape_prevention()`.
`AbilityManager.is_trapped()` extended with a 1-line check right alongside
its existing `wrapped_by` check — that function's own doc comment had
already anticipated and named this exact move-based trap back at `[M17f]`.
Shed Shell's exemption needed ZERO new code: it already bypasses trapping
at the `_phase_move_selection` call site (before `is_trapped()` is even
consulted), confirmed via source to apply uniformly to every trapping
SOURCE, not per-ability. A real, source-confirmed asymmetry WITHIN this
5-move family: Mean Look/Block/Spirit Shackle/Jaw Lock all correctly reach
`AbilityManager.is_trapped()`'s Ghost-type gate for free, but Spider
Web/Mean Look/Block additionally carry a MOVE-SCRIPT-level Ghost-type
IMMUNITY (the move itself fails against a Ghost-type target at GEN_LATEST
config) that Spirit Shackle/Jaw Lock do NOT share — confirmed via source
that this immunity lives only in `BattleScript_EffectMeanLook`'s own
dedicated script, never in the generic secondary-effect dispatch the
damaging moves use. A further asymmetry WITHIN the 3 status moves: Spider
Web's own `ignoresProtect` is FALSE at GEN_LATEST (Mean Look's/Block's are
both TRUE) — confirmed individually per move, not assumed uniform just
because all 3 share one effect ID.

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

## Section C — Moves better left out of M19 for now (216 moves: 215 permanently excluded + 1 deferred)

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

### C2 — Rob's `[M19-exclusions]` list (128 moves) — **PERMANENTLY EXCLUDED, confirmed by Rob (2026-07-08; +6 more 2026-07-14, then -4 reversed same day — see below)**

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
- **From D4's singleton pool, a genuine capability gap rather than a
  choice, 2 moves — 2026-07-14:** Nature Power(267) and Camouflage(293)
  both key off `gBattleEnvironment`, an overworld map/tile-derived field
  with no analog anywhere in this project — the same blocker Secret
  Power(290) is already excluded for.

**`[Exclusion bookkeeping]`'s own 2026-07-14 bullet excluding move IDs
496/289/286/716 — Round, Snatch, Imprison, and Grav Apple respectively
(Rob's own scope choice despite being REUSE-LIKELY at the recon pass) —
was REVERSED by Rob on 2026-07-14 (same day) — see `docs/decisions.md`'s
new `[Reversal: Round/Snatch/Imprison/Grav Apple]` entry for the full
record; that entry is NOT rewritten, only superseded. All 4 moves are
back in D4's residual pool, since shipped via `[D4 Bundle 8]` — see that
entry below. (Note for anyone re-deriving this section's own move-ID
list programmatically: the four IDs are deliberately NOT written in
`Name(ID)` form in this paragraph, since `scripts/gen_move_status_
table.py`'s own C2 parser pattern-matches that exact shape anywhere in
this section's text — writing them that way here would have
re-excluded all four under the wrong bullet's reason string, which is
exactly the bug this phrasing avoids.)**

Removed from D4's own remaining pool (19→13, then 13→13 net after the
4-move reversal put Round, Snatch, Imprison, and Grav Apple back — see
the `[D4 Bundle 8]` update note just below for the final accounting) —
see Section E's recomputed totals.

**14 + 10 + 2 + 1 + 3 + 9 + 85 + 1 + 1 + 2 = 128.**

**`[D4 Bundle 8]` update (2026-07-14): final accounting closed.** The
4 reinstated moves (Round/Snatch/Imprison/Grav Apple) were re-derived
fresh from source (Step 0) and implemented in the same session as this
reversal — see `docs/decisions.md`'s `[D4 Bundle 8]` entry. They never
sat in the residual pool as unimplemented moves; the reversal and the
implementation landed together. Net effect on D4's own singleton pool:
6 moves before this session's reversal (Mimic/Transform/Sketch/Perish
Song/Sky Drop/Flying Press, all NOVEL-MECHANISM, per `[D4 Bundle 7]`) →
briefly 10 once the 4 were reinstated as residual → back to the same 6
now that all 4 are implemented. Section E's "already implemented" row
is now **711** (707 + 4), "Permanently excluded" is **217** (221 − 4,
Nature Power/Camouflage only), and "Tier 4 residual" stays **6** — the
same 6 moves as before this session, confirmed unchanged by identity,
not just by count.

### C3 — Population Bomb (1 move) — PERMANENTLY EXCLUDED (2026-07-10)

Population Bomb(788) is the sole `.strikeCount` move `[M18.5g]` deliberately
excluded from the multi-hit mechanism it otherwise built — per-hit accuracy
checks (unlike every other `strikeCount` move, which checks once) AND a
uniquely-shaped Loaded Dice interaction (`RandomUniform(4,10)` instead of
the standard `(4,5)`). Not blocked on missing infrastructure — a genuinely
higher complexity class than the rest of Tier 3a. Previously slated for its
own small future tier; Rob has since confirmed permanent exclusion instead,
closing out that deferral. **Also appears on Rob's `[M19-exclusions]`
list.** Moves from "Deferred" into "Permanently excluded" — see Section E's
reconciliation.

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

## Section D — Tier 4 residual (181 moves): mechanism-clustered breakdown (`[M19-section-d-cluster]`, 2026-07-09)

**Status: this section is now a full sub-clustering pass**, replacing the
old 10-cluster/158-singleton placeholder table (which explicitly
disclaimed itself as "not a finished sub-tier list"). Discovery/recon
only — no `.tres` files, code, or tests were touched to produce this;
matches the discipline `docs/m19_recon.md`/`docs/m18_item_ledger.md`
established for planning-only sessions.

### Step 1/2 — re-verification against current state

Re-derived the full 181-move list FRESH from `data/moves.json` (the
`[M19-pipeline-fix]`-corrected extraction, itself re-verified against
`moves_info.h` throughout this pass) rather than trusting the old table's
own prose: computed as (934 real moves) − (535 implemented, cross-checked
directly against `gen_moves.py`'s own `MOVES` dict AND a fresh
`ls data/moves/*.tres | wc -l` — both 535, matching) − (213 permanently
excluded: 87 Z-Move/Max-Move IDs 848–934 + 126 from Rob's
`[M19-exclusions]` list, individually re-transcribed from Section C2's own
prose and cross-checked to zero overlap with the implemented set) − (1
deferred, Population Bomb(788)) − (4 Bucket 4 gated/deferred moves: Secret
Power(290), Sappy Seed(685)/Freezy Frost(686)/Sparkly Swirl(687)) = **181,
exact match, zero drift**. The old 10-cluster head-start table is
CONFIRMED ACCURATE (its `EFFECT_DOUBLE_POWER_ON_ARG_STATUS` count of 6 vs.
this pass's 5 is fully explained by Wake-Up Slap(358) having been removed
by `[M19-exclusions]` in the meantime — not drift, just a later exclusion
the old table predates).

**One real doc-quality finding, not a scope change**: **Struggle(165)** is
sitting in this 181-move residual by ID, but is **already fully
implemented** — `BattleManager._construct_struggle_move()` (`battle_manager.gd`
L344-356) hardcodes a complete, tested `MoveData` instance inline (the
same "no-PP fallback" pattern documented since M1), it simply was never
added to `gen_moves.py`/`data/moves/*.tres` because it doesn't need
per-species selection the way a normal move does. This matches the
Heal Order/Dragon Darts "resolved conflict, stays as-is" precedent from
Section C's own resolved-conflicts note — **flagged here, not silently
fixed**: Rob should decide whether to (a) leave it exactly as documented
here (Struggle stays a special-cased inline construction, permanently
outside the `.tres` pipeline and this residual's future scope) or (b) do
a docs-only reclassification moving it out of "181 remaining" into
"already implemented" (535→536, 181→180) with zero code change. No
action taken pending that call.

**No other incidental implementations were found** — every other one of
the 181 IDs was independently confirmed absent from `gen_moves.py`.

### Step 2 — full effect-name re-clustering

The old table only named 10 effect-name clusters (using an older,
pre-`[M19-pipeline-fix]` naming convention) and lumped everything else
into one 158-move "singletons/small pairs" bucket. A full pass over
`data/moves.json`'s (source-verified accurate) `effect_name` field for
all 181 residual IDs found **21 clusters of 2+ moves (51 moves total)**
— 11 more clusters than the old table surfaced, since the old table was
hand-derived without a systematic per-move effect-name scan — leaving a
smaller, more precisely-characterized **130-move singleton pool** (Step 4
below), not 158.

### D0 — Priority unblock: Leech Seed / Haze / Aromatherapy+Heal Bell (4 moves) — **CLOSED, COMPLETE (`[D0]`, 2026-07-09)**

**Shipped exactly as this recon predicted — all 3 mechanisms confirmed
CHEAP at Step 0, zero new `BattleManager`-level architecture needed.**
Also shipped in the same session: the two "already-free" pairs Section
D3 flagged (Follow Me(266)/Rage Powder(476), Soft-Boiled(135)/Milk
Drink(208)) and the 3 moves this D0 unblock directly gated
(`M19-blocked-on-other-tier4`: Sappy Seed(685)/Freezy Frost(686)/Sparkly
Swirl(687), confirmed genuinely trivial once their parents existed — see
that sub-group's own CLOSED entry in Section B above). One real Step 0
correction beyond this recon's own framing: Rage Powder's powder-move
immunity does NOT come "for free" from the general `blocks_move_flag`
gate as originally assumed — that gate checks `defender`, which for a
self-targeted move resolves to the default-selected opponent, not the
user itself; fixed with one explicit check inside `is_follow_me`'s own
dispatch instead. 11 moves total, 546 `.tres` files (was 535). New
`m19_d0_test.gd`/`.tscn`: 38/38 assertions, stable across 5 reruns.
13-suite regression clean. See `docs/decisions.md`'s `[D0]` entry for
full Step 0 citations and the Rage Powder correction's own writeup.

The original recon writeup below is kept for its source citations and
mechanism analysis — all forward-looking language ("would resolve",
"is now CHEAP") should be read as already-shipped past tense.

**Spotlight, not a 5th bucket**: these 4 moves are already counted inside
D1 (Heal Bell/Aromatherapy = the `EFFECT_HEAL_BELL` cluster row) and D4
(Leech Seed/Haze, 2 of the 130 singletons) — called out here first
because building them directly resolves the 3-move
`M19-blocked-on-other-tier4` gate (Sappy Seed/Freezy Frost/Sparkly
Swirl) for free. Re-derived each from source (`battle_script_commands.c`,
`battle_end_turn.c`) rather than assuming any of the three need genuinely
new infrastructure — **none
do**:

- **Aromatherapy(312) / Heal Bell(215)** (`EFFECT_HEAL_BELL`) — source's
  `Cmd_healpartystatus` (L8259-8340) cures `status1` for the ENTIRE
  PARTY, not just the active battler, gated per-mon on Soundproof only
  for Heal Bell (a genuine sound move; Aromatherapy is not). Confirmed
  this project's `BattleParty.members: Array[BattlePokemon]`
  (`battle_party.gd`) already holds real `BattlePokemon` instances for
  every bench mon with their own live `.status` field, and
  `BattleManager._parties[side]` is already reachable mid-battle — the
  "does party-wide status reach exist" open question the old table
  flagged is answered **yes, trivially**: a plain loop over
  `_parties[attacker_side].members` setting `.status = STATUS_NONE`,
  gated per-mon on the existing `sound_move` flag for Heal Bell only.
  Zero new architecture.
- **Haze(114)** (`EFFECT_HAZE`) — source's `MOVE_EFFECT_HAZE` case
  (`battle_script_commands.c` L2861-2865) loops EVERY battler on the
  field (`TryResetBattlerStatChanges`) resetting all 7 stat stages to 0.
  This is the LITERAL SAME "reset all stages to exactly 0" primitive
  `[Bucket 4 cheapest singles]` just built for Clear Smog(499) —
  confirmed Haze is now a trivial extension of an already-shipped
  mechanism (loop it over every combatant instead of one target), not a
  new one. High-leverage: also unblocks Haze's own future value as a
  precedent for any other "reset, don't just clear stat stages" move.
- **Leech Seed(73)** (`EFFECT_LEECH_SEED`) — source's `MOVE_EFFECT_LEECH_SEED`
  case sets `volatiles.leechSeed = LEECHSEEDED_BY(battlerAtk)` (a
  seeder-reference field), Grass-type-immune, fails if already seeded;
  `HandleEndTurnLeechSeed` (`battle_end_turn.c` L476+) drains 1/8 max HP
  from the seeded battler to the seeder each end of turn. This is the
  SAME "per-battler source-reference field + end-of-turn tick + reciprocal
  clear when the source leaves the field" shape this project has now
  built THREE times (`wrapped_by`/`[M18.5f]`, `infatuated_by`/`[M18.5d-3]`,
  `escape_prevented_by`/`[M19e]`/`[M19f]`) — a well-precedented pattern,
  not a new one, plus it composes for free with the already-implemented
  Liquid Ooze drain-inversion (`[M17n-9]`) and Big Root's own confirmed
  "move-drain only" scope note (`[M18q]`) means Big Root correctly does
  NOT need to touch Leech Seed's drain, consistent with that prior
  finding rather than contradicting it. Heal Block interaction is
  permanently moot (Heal Block itself is excluded/unimplemented).

**Combined verdict: CHEAP.** None of the 3 gating mechanisms need new
`BattleManager`-level architecture — this is a strong candidate for the
very next M19 implementation session regardless of Section D's overall
sequencing, since it closes out Bucket 4 entirely (down to just
`M19-secret-power`, deferred by Rob at the time — since permanently
excluded, 2026-07-10).

### D1 — Effect-name clusters, 2+ members (21 clusters, 51 moves originally — 3 clusters/6 moves CLOSED by `[D0]`; 8 clusters/21 moves CLOSED by `[D1 cheap clusters]`, 2026-07-09; `EFFECT_FORESIGHT` CLOSED by `[D2 batch 2]`; `EFFECT_FUTURE_SIGHT`/`EFFECT_PSYSHOCK` CLOSED by the Delayed-effect-family session; 6 more clusters/13 moves CLOSED by the D1 easy bundle; `EFFECT_DOUBLE_POWER_ON_ARG_STATUS` CLOSED (5 moves), all 2026-07-10 — **D1 is now FULLY CLOSED, all 21 clusters/51 moves accounted for**)

Every cluster below was spot-checked against `moves_info.h` for at least
2 members (source line numbers in `docs/decisions.md`'s
`[M19-section-d-cluster]` entry), per this task's own instruction not to
trust a shared effect_name as proof of a shared BUILDABLE mechanism
without verification — flagged explicitly wherever real divergence was
found within a cluster.

| Cluster | Moves | Cheap/Moderate/Hard | Mechanism + existing infra reused |
|---|---|---|---|
| `EFFECT_WEATHER` — **CLOSED (`[D1 cheap clusters]`)** | Sandstorm(201), Rain Dance(240), Sunny Day(241), Hail(258), Snowscape(809) | **CHEAP** | `BattleManager.try_set_weather(weather_type, by_pokemon)` already exists as a fully generic, non-ability-specific function (built for Drizzle/Drought/Sand Stream/Snow Warning, `[M17c]`) — already handles duration (`ItemManager.weather_duration`, rocks-aware) and Neutralizing Gas. Snowscape maps to the same `WEATHER_HAIL` constant Snow Warning already uses (this project doesn't model Gen9's Hail/Snow split, consistent with existing convention). Shipped `[D1 cheap clusters]`, 2026-07-09. **Two pre-existing gaps flagged, not fixed**: (1) real source's Snow is mechanically DIFFERENT from Hail (Ice-type Defense boost, no chip, vs. Hail's chip-only) — this project's already-shipped Snow Warning ability shares the same simplification; (2) `try_set_weather` has no Primal-weather block at all — confirmed the SAME gap already exists in the already-shipped Drizzle/Drought/Sand Stream/Snow Warning abilities, predating this tier. |
| `EFFECT_DOUBLE_POWER_ON_ARG_STATUS` — **CLOSED (closes D1 entirely, 2026-07-10)** | Smelling Salts(265), Venoshock(474), Hex(506), Barb Barrage(767), Infernal Parade(772) | **CHEAP-MODERATE** | Confirmed genuinely non-uniform, all 5 individually re-verified: Hex/Infernal Parade use `STATUS_ARG_ANY` (any non-volatile status — including a Comatose holder, treated as SLEEP for this check specifically, a real reachable interaction since Comatose already ships `[M17n-11]`); Venoshock/Barb Barrage use `STATUS_ARG_POISON_ANY` (poison or toxic); Smelling Salts uses a single specific PARALYSIS value. This row's own flagged `MOVE_EFFECT_REMOVE_STATUS` concern was confirmed real and narrower than feared: only Smelling Salts carries it (cures the target's paralysis on hit) — and it carries a SECOND, move-specific nuance this row didn't anticipate: the power-double itself (not just the cure) is suppressed if blocked by a live, non-ignored Substitute (`battle_util.c` L6188-6190). Barb Barrage/Infernal Parade are genuine two-mechanism composites too, but their own 50%/30% poison/burn secondary is PURE REUSE of the existing generic `secondary_effect`/`SE_POISON`/`SE_BURN` dispatch — zero new code for that half. New power-modifier check reuses the exact `_dmg_power_override` pipeline stage Rollout/Magnitude/Stomping Tantrum/etc. already occupy (`[M16b]`/`[D1 easy bundle]` precedent), not a new mechanism. New `d1_double_power_status_test.gd`/`.tscn`: 60/60 assertions, stable across 5 reruns after fixing 3 test-authoring bugs on the first run (a fresh instance of CLAUDE.md's own "type immunity precedes ability logic" pitfall — Ghost-type Hex/Infernal Parade tested against this file's default Normal-type defender, a flat 0x immunity; direct `DamageCalculator.calculate()` calls used to test "doubling," which has zero awareness of this project's `_dmg_power_override` dispatch — the mechanism lives entirely in `BattleManager`, so doubling claims needed real full-battle observation instead; and a substitute_hp=50 fixture that legitimately broke over a long multi-turn battle, a fresh whole-battle-aggregation instance, fixed by setting it to 999999 matching the established "effectively unbreakable for this test" precedent). Total move-implementation count: 617→622. |
| `EFFECT_POWER_BASED_ON_USER_HP` — **CLOSED (`[D1 cheap clusters]`)** | Eruption(284), Water Spout(323), Dragon Energy(748) | **CHEAP** | `battle_util.c` L6136-6137: `basePower = move.power * userHP/userMaxHP` — a plain CONTINUOUS linear scale, genuinely simpler than (and distinct from) `M19-hp-based-power`'s stepped/banded Flail/Reversal formula. Reuses the existing `power_override` dispatch mechanism (`[M16b]` Rollout/Magnitude precedent). Shipped `[D1 cheap clusters]`, 2026-07-09 exactly as predicted — no floor-to-1 clamp confirmed, a very-low-HP hit can legitimately compute to 0 power. |
| `EFFECT_POWER_BASED_ON_TARGET_HP` — **CLOSED (`[D1 cheap clusters]`)** | Wring Out(378), Crush Grip(462), Hard Press(840) | **CHEAP** | Mirror of the above: `basePower = move.power * targetHP/targetMaxHP` (`battle_util.c` L6192-6193). Same `power_override` reuse. Shipped `[D1 cheap clusters]`, 2026-07-09. |
| `EFFECT_HIT_ESCAPE` — **CLOSED (D1 easy bundle, 2026-07-10)** | U-turn(369), Volt Switch(521), Flip Turn(740) | **CHEAP-MODERATE** | The player-choice question this row itself flagged is resolved: reuses `_get_replacement_slot`'s existing test-queue→AI-choice→deterministic-first-available chain (the SAME one faint-replacement already uses) rather than Red Card's random pick, since the user's own trainer genuinely chooses. Confirmed INCLUDING a Substitute-absorbed hit (source's own `INCLUDING_SUBSTITUTES`) still triggers the switch. |
| `EFFECT_HIT_SWITCH_TARGET` — **CLOSED (D1 easy bundle, 2026-07-10)** | Circle Throw(509), Dragon Tail(525) | **CHEAP-MODERATE** | Confirmed exactly as described — reuses `_do_forced_switch_in` + the SAME random-replacement helper Roar/Whirlwind/Red Card already use (a genuinely forced switch, unlike Hit Escape's player-choice shape above). EXCLUDING a Substitute-absorbed hit (the opposite of Hit Escape's own inclusive check) — must be real HP damage. |
| `EFFECT_FOLLOW_ME` — **CLOSED (`[D0]`)** | Follow Me(266), Rage Powder(476) | **FREE** | The redirect MECHANISM already exists and is fully tested — `MoveData.is_follow_me`, `BattleManager._follow_me_used`/`_follow_me_targets`, the redirect-resolution block at `battle_manager.gd` L945-967/1886 — built during `[M14b]` and exercised indirectly by `[M17l]`'s Propeller Tail/Stalwart bypass tests. **Neither move was ever added as a data entry** — this is 2 moves of pure `gen_moves.py` data-entry against an already-complete, already-proven mechanism. Spotlight(634) stays excluded. **Shipped `[D0]`, 2026-07-09 — one real correction found**: Rage Powder's `powder_move` immunity does NOT come free from the general `blocks_move_flag` gate as this table assumed (that gate checks `defender`, which resolves to the default-selected opponent for a self-targeted move, not the user) — fixed with one explicit check inside `is_follow_me`'s own dispatch. |
| `EFFECT_SOFTBOILED` — **CLOSED (`[D0]`)** | Soft-Boiled(135), Milk Drink(208) | **FREE** | `BattleScript_EffectSoftboiled` (`battle_scripts_1.s` L2379) is functionally IDENTICAL to `BattleScript_EffectRestoreHp` (L1693) — both `tryhealhalfhealth` against a self-targeted move (`BS_TARGET` resolves to the attacker itself since `.target = TARGET_USER`), a historical/legacy distinct enum for what M16a's own `EFFECT_RESTORE_HP` (Recover/Slack Off/Heal Order) already fully implements. Literally 2 more names in that same existing dispatch, zero new code. Shipped `[D0]`, 2026-07-09 exactly as predicted — genuinely identical data confirmed individually. |
| `EFFECT_STEAL_ITEM` — **CLOSED (`[D1 cheap clusters]`)** | Thief(168), Covet(343) | **CHEAP** | `battle_move_resolution.c` L3487-3499: on-hit steal, gated on the attacker having no item of its own, reuses `AbilityManager._try_steal_item` (the exact Pickpocket/Magician primitive, `[M17j]`, via a new `try_thief_steal` wrapper) directly — Sticky Hold gate already built in. Shipped `[D1 cheap clusters]`, 2026-07-09 — confirmed item-general (no Jaboca/Rowap exemption, unlike Pluck/Bug Bite). |
| `EFFECT_LOCK_ON` — **CLOSED (`[D1 cheap clusters]`)** | Mind Reader(170), Lock-On(199) | **CHEAP** | Sets an "always hits with my next move" volatile on the target (`setalwayshitflag`) — same accuracy-bypass insertion point `always_hits_in_rain` (`[M19-weather-conditional-accuracy]`) and No Guard (`[M17a]`) already occupy, just target-scoped and one-shot instead of attacker-scoped and permanent. Shipped `[D1 cheap clusters]`, 2026-07-09 — a genuine 2-tick per-attacker-target volatile (not a pure flag), confirmed to bypass semi-invulnerability too (inserted before that check, not just alongside No Guard), and reuses the established reciprocal-clear-on-departure shape for the 5th time. |
| `EFFECT_FORESIGHT` — **CLOSED (`[D2 batch 2]`, 2026-07-10)** | Foresight(193), Odor Sleuth(316) | **CHEAP-MODERATE** | Confirmed genuinely identical (literal same effect ID). New permanent per-mon `BattlePokemon.foresight_active`; the Ghost-bypass half OR'd directly into `bypass_ghost_immunity` at the `DamageCalculator.calculate` call site (no new TypeChart param needed); the evasion-ignore half reuses the exact `eva_stage = 0` insertion point `ignores_defense_evasion_stages` already established, confirmed mathematically identical to source's own `buff = accStage` shape. **A real bug found and fixed**: this project's own general "type immunity for foe-targeting moves" gate was over-generalized — Foresight's own source script (`BattleScript_EffectForesight`) never calls `typecalc` at all, meaning it's never blocked by ANY type immunity in the real engine, including its own primary use case (a Ghost-type target). Fixed with a narrow `not move.is_foresight` exemption, matching the existing `corrosion_bypasses_type_gate` precedent's own scoping shape; whether any other already-shipped status move shares this gap is flagged, not investigated further. |
| `EFFECT_SWAGGER` — **CLOSED (`[D1 cheap clusters]`)** | Swagger(207), Flatter(260) | **CHEAP** | Confuses the target AND raises a stat (Swagger: Atk +2; Flatter: SpAtk +1) in one move. Shipped `[D1 cheap clusters]`, 2026-07-09 — **NOT a pure composition, the one real correction found this tier**: Own Tempo blocks the ENTIRE move (including the stat raise), not just the confusion, confirmed from source's own `BattleScript_OwnTempoPrevents` redirect — a naive independent composition would have still let the stat raise through. |
| `EFFECT_FUTURE_SIGHT` — **CLOSED (Delayed-effect family, 2026-07-10)** | Future Sight(248), Doom Desire(353) | **MODERATE** | Confirmed genuinely as described — see the Delayed-effect family write-up below for full findings, including the real 3-way mechanism-shape correction and the cast-time-vs-resolve-time snapshot resolution. |
| `EFFECT_FIRST_TURN_ONLY` — **CLOSED (D1 easy bundle, 2026-07-10)** | Fake Out(252), First Impression(623) | **CHEAP-MODERATE** | Reuses the EXISTING `switched_in_this_turn` flag directly (zero new tracking state, a correction to this row's own "new per-mon flag" framing). **A real, previously-latent bug found and fixed along the way**: `switched_in_this_turn` was only ever set by mid-battle switch-in functions — a battle's own STARTING leads never got it set at all, so Fake Out could never connect on a lead's own first turn (and Stakeout/Speed Boost were silently reading a permanently-false value every battle's opening turn too). Fixed at the root (`_phase_battle_start` + a new `_pending_initial_switch_in` flag consumed by `_phase_priority_resolution`'s own per-turn reset). Also closed the Instruct-double-fire loophole (source's own `backUpTarget` check) by adding `is_first_turn_only` to Instruct's exclusion list. |
| `EFFECT_TRICK` — **CLOSED (D1 easy bundle, 2026-07-10)** | Trick(271), Switcheroo(415) | **CHEAP-MODERATE** | Confirmed exactly as described — a genuinely new 4th direction for the M17j item-transfer family. Of source's full unswappable-item exclusion list, only Multitype's Plate is relevant (Mail/E-Reader-Berry/Z-Crystals/Booster-Energy-Paradox/Ogerpon-Masks are all permanently moot, items/species this project never implemented). Sticky Hold checked ONLY on the target, matching source. |
| `EFFECT_REVENGE` — **CLOSED (D1 easy bundle, 2026-07-10)** | Revenge(279), Avalanche(419) | **CHEAP-MODERATE** | Confirmed the narrow per-(victim,attacker)-PAIR scoping exactly as flagged — genuinely distinct from Lash Out/Retaliate's shipped D2-tracker-family shape, needed its own new `BattlePokemon.hit_by_this_turn` list. Verified via a real 2v2 doubles test that being hit by one opponent does NOT double Revenge targeted at a different opponent. |
| `EFFECT_SUCKER_PUNCH` — **CLOSED (`[D1 cheap clusters]`)** | Sucker Punch(389), Thunderclap(837) | **CHEAP** | `battle_move_resolution.c` L1387-1394: fails if the target has already acted this turn, or if the target's chosen move is a status move (Me-First-exempted). **Directly reuses `[M18j]`'s existing `_has_target_already_acted` turn-position helper** (built for Zoom Lens) with zero new tracking — just add the move-category check on the target's own chosen move. Shipped `[D1 cheap clusters]`, 2026-07-09. |
| `EFFECT_PSYSHOCK` — **CLOSED (2026-07-10)** | Psyshock(473), Psystrike(540) | **MODERATE** | Confirmed exactly as described — `battle_util.c :: CalcDefenseStat` (L7021-7035) adds one OR condition to the existing category-based defense-stat-selection branch, reading `defender.defense`/`STAGE_DEF` instead of the Special defaults. No category swap (unlike Photon Geyser); implemented as a third override alongside the already-shipped Foul Play/Body Press overrides in `DamageCalculator`, same insertion point. Secret Sword(548) stays excluded. |
| `EFFECT_STORED_POWER` — **CLOSED (`[D1 cheap clusters]`)** | Stored Power(500), Power Trip(644) | **CHEAP** | `battle_util.c` L6240-6241: `basePower += 20 * count(positive stat stages)`. Trivial formula over the existing `stat_stages` array. Shipped `[D1 cheap clusters]`, 2026-07-09 — confirmed the formula SUMS stage magnitude (Atk+3 contributes 3), not a count of raised stats, a real easy-to-misread detail implemented explicitly correctly. |
| `EFFECT_STOMPING_TANTRUM` — **CLOSED (D1 easy bundle, 2026-07-10)** | Stomping Tantrum(661), Temper Flare(843) | **CHEAP-MODERATE** | Confirmed a genuine 2-turn COUNTER (not a plain bool), sharing the LITERAL SAME decrement site as Retaliate's own side-timer (`battle_main.c`'s per-battler action-reset). **This surfaced a real bug in already-shipped `[D3 turn-order/event-tracker batch]` code**: Retaliate's decrement had been placed in `_phase_end_of_turn`, which this project's own architecture skips on a faint/replacement turn — source's real site runs unconditionally every turn. Fixed by moving both timers' decrement to `_phase_priority_resolution`, with the D3 test's own assertions corrected to match. |
| `EFFECT_HEAL_BELL` — **CLOSED (`[D0]`)** | Heal Bell(215), Aromatherapy(312) | **CHEAP** | See D0 above (the priority-unblock section) for the full writeup — listed here too so this table's own cluster count/total stays self-consistent. Shipped `[D0]`, 2026-07-09. |

(5+5+3+3+3+2×16 = 51 across the 21 rows above, reconciled against the
51-move/21-cluster figure Step 2 computed programmatically. **Note**:
D0 above highlights 4 of these 181 moves for priority — Heal
Bell(215)/Aromatherapy(312) are this table's own `EFFECT_HEAL_BELL` row
(not additive); Leech Seed(73)/Haze(114) are 2 of D4's 130 singletons
(not additive). D0 is a cross-reference/spotlight, not a 5th bucket —
51 (D1) + 130 (D4) = 181 still holds exactly.)

**`[D1 cheap clusters]` update (2026-07-09)**: 8 of the remaining 18
clusters (`EFFECT_WEATHER` 5, `EFFECT_POWER_BASED_ON_USER_HP` 3,
`EFFECT_POWER_BASED_ON_TARGET_HP` 3, `EFFECT_STEAL_ITEM` 2,
`EFFECT_LOCK_ON` 2, `EFFECT_SWAGGER` 2, `EFFECT_SUCKER_PUNCH` 2,
`EFFECT_STORED_POWER` 2 — 21 moves total, every cluster tagged strictly
**CHEAP**, not CHEAP-MODERATE) are now CLOSED, marked individually above.
**Scope correction against D5's own "~15 moves" estimate**: the true
strictly-CHEAP total was 21, not ~15 — D5's own prior list had silently
omitted the two HP-based-power clusters (6 moves) without explanation;
all 8 CHEAP clusters were bundled into one session instead of an
arbitrary 6-cluster subset, matching this arc's own "bundle the cheapest
tier" precedent. D1's own remaining pool: 45→24 moves, 18→10 clusters,
all tagged CHEAP-MODERATE or harder (`EFFECT_DOUBLE_POWER_ON_ARG_STATUS`,
`EFFECT_HIT_ESCAPE`, `EFFECT_HIT_SWITCH_TARGET`, `EFFECT_FORESIGHT`,
`EFFECT_FUTURE_SIGHT`, `EFFECT_FIRST_TURN_ONLY`, `EFFECT_TRICK`,
`EFFECT_REVENGE`, `EFFECT_PSYSHOCK`, `EFFECT_STOMPING_TANTRUM`).

### D2 — Cross-cutting families surfaced while sweeping the singleton pool

These aren't effect-name clusters (each move below has a UNIQUE
`effect_name`), but grouping them by underlying MECHANISM — not just
name — surfaced real shared-infrastructure opportunities the flat
effect-name lens alone would miss, the same style of finding this arc's
Jaw Lock (`[M19e]`/`[M19f]`) and Spicy Extract (`[Bucket 3 multi-stat]`)
sessions already produced:

- **Delayed-effect family (6 moves, MODERATE, build together)**: Future
  Sight(248)/Doom Desire(353) (cluster D1 above, delayed damage on a
  field slot), **Wish(273)** (delayed heal on whichever mon occupies the
  user's OWN slot next turn), **Yawn(281)** (delayed sleep-infliction at
  the end of the FOLLOWING turn), **Healing Wish(361)** (self-faint +
  full heal for whoever switches in next), **Lunar Dance(461)**
  (Healing Wish + also restores PP). None of these share one identical
  mechanism (Wish/Future-Sight are turn-counted regardless of switches;
  Healing Wish/Lunar Dance trigger on the SWITCH-IN event itself, not a
  turn count), but all 6 need some shape of "an effect that isn't
  resolved now" — worth scoping as one combined design session rather
  than 4-5 separate ones, since the turn-counted half (Future
  Sight/Doom Desire/Wish/Yawn) can likely share one small "pending
  effects" list checked once per end-of-turn, and the switch-in-triggered
  half (Healing Wish/Lunar Dance) can reuse the self-faint precedent
  (`M19-self-faint`) plus a simple "next switch-in gets a bonus" flag on
  the party slot.
- **Ability-manipulation family (4 moves) — CLOSED, COMPLETE
  (`[D2 batch]`, 2026-07-09).** Confirmed all 4 reuse M17h's already-built
  ability-copy/overwrite primitives directly, exactly as predicted — new
  `AbilityManager.try_role_play`/`try_skill_swap`/`try_worry_seed_overwrite`
  mirror Trace/Wandering Spirit/Mummy's own established shapes
  respectively (Heart Swap needed no ability-side function at all, see
  below). **Role Play(272)**: attacker copies the target's ability
  (`ignoresProtect=TRUE` AND `ignoresSubstitute=TRUE` in source — a real
  asymmetry within this family, Skill Swap/Heart Swap do NOT ignore
  Protect), gated on `cant_be_copied`/`cant_be_suppressed`, compared by
  `.ability_id` not object identity (this project has no `AbilityRegistry`,
  so "the same ability" on two mons is typically two separate `AbilityData`
  Resource instances). **Skill Swap(285)**: a genuine bidirectional swap,
  confirmed to reuse Wandering Spirit's EXACT primitive shape (gated on
  `cant_be_swapped` on BOTH sides independently, an ability-less mon
  treated the same as `cant_be_swapped`, matching source's own
  `ABILITY_NONE`). **Worry Seed(388)**: shares the LITERAL SAME
  `EFFECT_OVERWRITE_ABILITY` Mummy/Lingering Aroma's own mechanism
  conceptually corresponds to, gated on `cant_be_overwritten` (the exact
  field `[M17h]`'s own entry had predicted would be "consumed by Skill-
  Swap/Entrainment-style moves this project doesn't have" — confirmed
  correct), fixed target ability_id (Insomnia=15) rather than a bespoke
  per-move flag. `magicCoatAffected=TRUE` in source → `bounceable=true`,
  confirmed working via a dedicated Magic Bounce integration test with
  zero extra code (the existing `move.bounceable` mechanism already
  generalizes). **Heart Swap(391)**: confirmed genuinely NOT an ability
  move despite the family label — a real bidirectional swap of all 7 stat
  STAGES, implemented as a direct `battle_manager.gd` array swap (no
  `AbilityManager` function at all), reusing Psych Up's own `[M16e]`
  precedent shape but swapping instead of copying. **Flagged, not fixed**:
  Worry Seed's own source script also calls
  `trytoclearprimalweather`/`tryendneutralizinggas` after a successful
  overwrite (in case the ability just stripped away was sustaining Primal
  weather or Neutralizing Gas) — a real, narrow, out-of-scope edge case.
  **Also flagged, not fixed**: this project's Sheer-Force-boosts-
  guaranteed-non-probabilistic-secondaries gap (see the hazard/screen
  family's own entry below) is unrelated to this family.
- **Damage/defense-stat-source-override family (3 moves) — CLOSED,
  COMPLETE (`[D2 batch 2]`, 2026-07-10).** **A real correction to this
  bullet's own framing**: `EFFECT_PSYSHOCK` (D1) is NOT "already built" —
  confirmed via direct `.tres`/`gen_moves.py` grep that Psyshock/
  Psystrike remain fully unimplemented (D1's own table still lists this
  cluster as an open MODERATE item, unaffected by this session). The
  offense-side mechanism was built fresh, matching the same conceptual
  insertion-point shape Psyshock's own defense-side override would need,
  without building Psyshock itself. **Foul Play(492)** (uses the
  TARGET's own Attack/Sp.Atk stat+stage, category-gated the same as
  normal — confirmed via source that `EFFECT_FOUL_PLAY` never triggers a
  category swap, so type effectiveness/STAB/ability gates all stay keyed
  on the attacker as usual). **Body Press(704)** (uses the USER's own
  Defense stat+stage instead of Attack; Wonder Room's own edge case
  permanently moot — unimplemented, on Rob's exclusion list).
  **Photon Geyser(675) — the one real hidden second effect this bullet's
  own task explicitly flagged as likely, confirmed true**: NOT a raw
  bigger-stat lookup — its own description ("User's highest attack stat
  determines its category") is literal. Source's `SetDynamicMoveCategory`
  DYNAMICALLY SWAPS the move's WHOLE category (Special→Physical) based on
  a stage-adjusted Atk-vs-SpAtk comparison (ties go Special), cascading
  into every category-gated check downstream (Guts, Choice items, any
  category-keyed ability) — implemented via the same shallow-duplicate-
  and-substitute pattern already established for Hidden Power/M17n-6's
  type mutation, mutating `.category` instead of `.type`, so every
  existing category check sees the swap for free. `.ignoresTargetAbility
  = TRUE` in source reuses the EXISTING `ignores_target_ability`
  mechanism (`[Bucket 4 2-move sub-groups]`) directly, zero new code.
- **On-hit hazard/screen set-or-clear family (6 moves) — CLOSED, COMPLETE
  (`[D2 batch]`, 2026-07-09).** Real Step 0 findings corrected two of this
  bullet's own framings. **Stone Axe(758)/Ceaseless Edge(773)**: confirmed
  a guaranteed on-hit hazard set on the TARGET's side via the same
  `sets_reflect_on_hit`/`sets_light_screen_on_hit` pattern predicted, BUT
  dispatched through a MoveEnd-keyed switch on the move's own top-level
  `.effect` (not the standard secondary-effect mechanism at all — no
  `.moveEffect` token exists in either move's own `additionalEffects`
  block). **Flagged, not fixed**: source's own `.sheerForceOverride=TRUE`
  means Sheer Force should boost these two moves' power even though this
  project's Sheer Force gate only checks true (chance>0) secondaries — a
  narrow, pre-existing-shape gap, out of scope for this small tier.
  **Ice Spinner(789) — a real correction, not a confirmation**: this
  bullet's own "clears hazards, reusing Rapid Spin" framing was WRONG.
  Real source's `EFFECT_ICE_SPINNER` removes TERRAIN, a completely
  different effect ID from `EFFECT_RAPID_SPIN` (which Mortal Spin, not
  Ice Spinner, actually shares). Since Terrain is permanently void in this
  project, Ice Spinner reduces to a plain damage move with no working
  secondary at all — cheaper than predicted, not a hazard-clearer.
  **Mortal Spin(794)**: confirmed to share the LITERAL SAME
  `EFFECT_RAPID_SPIN` Rapid Spin(229) itself uses — `is_rapid_spin` set
  directly on its own data entry, zero new field, plus a guaranteed 100%
  Poison secondary via the existing generic fields. **Tidy Up(808) —
  broader than predicted**: confirmed to ALSO clear every Substitute
  currently on the field (both sides, any battler), not just hazards — a
  real finding beyond this bullet's own "hazards + self stat-raise"
  framing, found directly from source (`TryTidyUpClear`). **Defog(432) —
  also broader than predicted**: clears the TARGET's side's screens
  (Reflect/Light Screen/Aurora Veil — this project's implemented subset;
  Mist/Safeguard permanently moot) via the SAME `breaks_screens`/Brick
  Break shape (`[M16c]`) rather than a new mechanism, AND clears hazards
  from BOTH sides (not just the target's), AND drops the target's
  evasion — three composed pieces, not two. New `_clear_all_hazards(side)`
  helper (clears every hazard type on one side at once, unlike Rapid
  Spin/Mortal Spin's own one-type-at-a-time clear) shared by both
  Defog and Tidy Up.
- **Per-mon TypeChart-override family (4 moves) — CLOSED, COMPLETE
  (`[D2 batch 2]`, 2026-07-10).** A real scope-count correction: this
  bullet's own "3 moves" total undercounted by one — Foresight(193) and
  Odor Sleuth(316) are TWO real move IDs sharing one mechanism, not one,
  bringing this family's true total to 4 (closed together with D1's own
  `EFFECT_FORESIGHT` cluster row above, not tracked twice). **Freeze-
  Dry(573)**: forces the Water-type component to a flat 2.0 UNCONDITION-
  ALLY (not a "fix 0→1" pattern like the existing Ghost-immunity-bypass
  overrides — Water is normally just neutral to Ice, not resistant) — new
  `force_super_effective_type` param added to both of this project's
  independent type-effectiveness functions (`TypeChart.get_uq412`/
  `get_effectiveness`), checked per-defending-type-component (a dual-type
  target's OTHER type composes independently, confirmed via a dedicated
  test). **A real secondary this move also carries, beyond this bullet's
  own "always super-effective vs Water" framing**: a 10%-chance Freeze
  secondary, reusing the existing `SE_FREEZE` token verbatim.
  **Tar Shot(695)**: confirmed a GENUINELY DIFFERENT shape from Freeze-
  Dry — a flat POST-COMBINATION ×2.0 doubler (not per-component) applied
  to the fully-combined effectiveness, gated on the ATTACKING move being
  Fire-type. New permanent `BattlePokemon.tar_shot_active`. Confirmed via
  direct source read this can NEVER stack with/conflict against Freeze-
  Dry's own override on the same hit (mutually exclusive by construction
  — Freeze-Dry is always Ice-type, never Fire-type). **A real coupling
  found and correctly modeled**: Tar Shot's flag-set and its associated
  -1 Speed are bundled as ONE all-or-nothing gate in source, not
  independent — an already-tar-shot'd target blocks the Speed drop too,
  not merely the redundant flag re-set. **Foresight/Odor Sleuth**: see
  D1's own `EFFECT_FORESIGHT` row above (marked CLOSED in the same
  session) for the full findings, including the real type-immunity-gate
  bug found and fixed along the way.
- **Turn-order-manipulation family (4 moves) — CLOSED, COMPLETE
  (`[D3 turn-order/event-tracker batch]`, 2026-07-10).** **After
  You(495)**: pushes the target to act IMMEDIATELY NEXT (position
  `_current_actor_index + 1`), fails if already acted — at this
  project's GEN_LATEST config (`B_AFTER_YOU_TURN_ORDER >= GEN_8`) an
  already-next target is a trivial success, reproduced for free since
  the reorder is a no-op in that case. **Quash(511)**: pushes the
  target to the absolute END of the remaining turn order — a
  deliberate simplification of source's speed-order-preserving GEN_8+
  doubles-only nuance (this project always pushes fully to the end,
  observably identical to source in singles, the primary supported
  case), flagged not silently assumed. **Upper Hand(846)**: re-derived
  fresh from source rather than assumed — connects ONLY if the
  target's own CHOSEN (not-yet-executed) move has an ABILITY-BOOSTED
  priority in [1,3] (via the exact same `AbilityManager.
  move_priority_bonus` function real turn-order sorting uses, not raw
  `move.priority`), the target hasn't acted yet, and that move isn't
  status-category; on failure the WHOLE move fails (no damage, no
  flinch) — same "ButItFailed" shape as the existing Sucker Punch
  dispatch. **Instruct(652)**: forces the target to immediately
  re-use its own `last_move_used` for FREE (no PP cost, a genuine
  "called move" matching Metronome/Mirror Move's existing fall-through
  shape) — but, unlike Mirror Move/Metronome (which only reassign
  `defender`/`move`), Instruct reassigns `attacker` ITSELF (the
  instructed Pokémon becomes the one actually executing), a genuinely
  new fall-through shape requiring `attacker_idx`/`attacker_side` to
  be recomputed too. New defender = the ORIGINAL attacker (exact in
  singles, a disclosed simplification in doubles where source tracks a
  real `backUpTarget`). Its exclusion list was re-derived against this
  project's own 23 currently-implemented `instructBanned` moves rather
  than source's full list or the project's own sparsely-populated
  `BAN_INSTRUCT` bitflag (only 2 of the 23 carry it) — 21 already fall
  out of the pre-existing `two_turn`/`is_recharge`/`is_rollout` checks,
  Metronome/Mirror Move via their own flags, Obstruct via
  `protect_method` (source flags ONLY Obstruct + King's Shield among
  the whole Protect family — Protect/Detect/Baneful Bunker/Silk
  Trap/Burning Bulwark/Wide Guard/Quick Guard are NOT banned, a
  genuine move-specific data quirk), Thrash/Petal Dance/Outrage/Uproar
  via `is_rampage`/`is_uproar`, and Bide (the one real gap found) via
  its own `is_bide` flag. All 4 read/write the existing
  `_turn_order`/`_current_actor_index` state `[M18j]`'s Zoom Lens and
  `[M17n-3]`'s Quick Draw/Stall already established as directly
  accessible — no new turn-order infrastructure, just new consumers of
  it, confirming the MODERATE tag was accurate for Upper Hand/Instruct
  but conservative for After You/Quash. New `d3_batch_test.gd`/`.tscn`:
  48/48 assertions across 9 sections, stable across 4 reruns.
- **"Stat/event happened this turn" tracker family (4 moves) — CLOSED,
  COMPLETE (`[D3 turn-order/event-tracker batch]`, 2026-07-10).**
  Mirrors the already-shipped `stat_raised_this_turn` flag
  (`M19-stat-raised-trigger`) with a sibling condition each, each
  independently re-verified rather than assumed identical in shape —
  **Lash Out(736)**: power ×2 if the USER'S OWN stat was lowered this
  turn, by ANY source — confirmed the genuine decrease-side mirror
  (new `BattlePokemon.stat_lowered_this_turn`, set at the exact same
  `StatusManager.apply_stat_change` chokepoint, cleared the same
  per-turn cadence). **Retaliate(514)**: power ×2 if a Pokémon on the
  user's OWN SIDE fainted during the PREVIOUS turn — a genuine
  side-wide 2-turn timer (`_retaliate_timer[side]`, set to 2 on any
  faint on that side, decremented once per turn boundary, checked
  `==1`), NOT a per-mon flag. **A real, empirically-confirmed timing
  nuance found while testing (not assumed)**: this project's
  END_OF_TURN phase is SKIPPED for the turn a faint/replacement
  occurs in, so the timer stays at 2 (undoubled) through the
  replacement mon's entire FIRST turn back — only its SECOND turn
  sees the first decrement (timer=1, doubled). **Rage Fist(815)**:
  power scales +50 per hit taken, capped 350 — confirmed a genuine
  BATTLE-LIFETIME counter (new `BattlePokemon.times_hit`), with NO
  reset mechanism in source at all (deliberately excluded from
  `_clear_volatiles`, unlike every other per-turn/per-stint tracker
  in this family — verified directly, not assumed, via a dedicated
  unit test calling `_clear_volatiles` and confirming the field
  survives). **Echoed Voice(497)**: power scales with a FIELD-WIDE
  (not per-mon, not per-side) consecutive-turn-use counter
  (`BattleManager._echoed_voice_counter`, capped 4), incremented once
  per turn boundary if used by ANYONE that turn (gated only on the
  move being attempted, not on hit success), reset to 0 the instant a
  turn passes without use. All 4 are small new tracker fields at
  existing dispatch chokepoints (the established `_dmg_power_override`
  pattern `[M16b]`'s Rollout/`[D1 cheap clusters]`'s Stored Power
  already use), no shared mechanism between them beyond "cheap to
  add" — confirmed CHEAP as tagged. New `d3_batch_test.gd`/`.tscn`
  (same file as the turn-order family above): 48/48 total, including
  a real cross-tier discovery caught while writing the test suite —
  a Ghost-type Rage Fist tested against a default Normal-type opponent
  produced a flat, silent 0-damage type immunity (Normal is immune to
  Ghost), the same class of pitfall CLAUDE.md's own
  type-immunity-precedes-ability-logic convention documents, fixed by
  giving the opponent a neutral (Water) type in those fixtures.

### D3 — Additional "already effectively free" findings (beyond Struggle, D0's cluster notes)

- **Solar Blade(632) — CLOSED, COMPLETE (`[D1]`, 2026-07-09).** the
  Fighting/Grass-family two-turn Sword variant of Solar Beam;
  near-identical reuse of the already-implemented charge-turn/sun-skip
  mechanism (`[M6]`/`[M15]`), just a different power/type/category
  (Physical, not Special — confirmed category-agnostic) on an existing
  dispatch shape. **Flagged, not fixed**: source's own `EFFECT_SOLAR_BEAM`
  also halves damage in rain/sand/hail/fog, but this project's existing
  Solar Beam(76) never implemented that half — Solar Blade ships with the
  same incomplete-but-consistent behavior; a future session should build
  both halves together.
- **Snipe Shot(691) — CLOSED, COMPLETE (`[D1]`, 2026-07-09).** ignores all
  redirection (Follow Me/Rage Powder/Lightning Rod/Storm Drain).
  Confirmed it bypasses BOTH halves at the ONE existing call site
  `AbilityManager.bypasses_redirection` (built for Propeller Tail/Stalwart,
  `[M17l]`) already occupies — extended with one new `move` param + a
  move-level `ignores_redirection` flag, zero new call sites needed.
- **Hidden Power(237) — CLOSED, COMPLETE (`[D1]`, 2026-07-09).** **A real
  correction to this entry's own "type/power determined by the user's real
  IVs" framing**: at this project's GEN_LATEST config
  (`B_HIDDEN_POWER_DMG >= GEN_6`), power is a FLAT 60 — the classic
  bit-parity power formula is dead code here, only TYPE is IV-derived.
  Found and fixed a genuine ordering trap: source's bit-packing order (HP,
  Atk, Def, SPEED, SpAtk, SpDef) does NOT match this project's own `ivs[]`
  array order (Speed LAST, not fourth) — the same trap already documented
  for Nature (`[M18.5h-1]`). Also found and fixed a real must-fix gap in
  the EXISTING `[M17n-6]` type-mutation infrastructure: `effective_move_type`
  had no exclusion for Hidden Power (never needed one before), so a
  Pixilate/Normalize holder would have incorrectly converted its computed
  type — source explicitly excludes Hidden Power from that whole pipeline.
- **Nature Power(267)** — calls a different move depending on Terrain;
  since Terrain is permanently VOID for this project (locked decision,
  `[M17d]`), this collapses to "always calls a fixed move" (the
  no-terrain default) — a trivial, confirmed-non-applicable
  simplification matching the Delta Stream/Overcoat precedent for
  documenting a source branch as permanently moot rather than silently
  dropping it. **Not yet built** — flagged as free but not part of this
  `[D1]` session's own scope (only Solar Blade/Snipe Shot/Hidden
  Power/Hyperspace Fury were requested).
- **Hyperspace Fury(621) — CLOSED, COMPLETE (`[D1]`, 2026-07-09).** breaks
  Protect + drops the user's own Defense −1 + never misses. Confirmed its
  own distinct `.effect = EFFECT_HYPERSPACE_FURY` dispatches via the
  LITERAL SAME `BattleScript_EffectHit` every plain damage move uses —
  functionally identical to a plain hit, genuinely just composition: reuse
  `breaks_protect` (`[M19-break-protect]`) directly for its Feint-shaped
  protect-break, plus a GUARANTEED (secondary_chance=0, the same shape
  `M19-secondary-stat-on-hit`'s own guaranteed self-drops use) self -1
  Defense via the existing `stat_change_stat`/`amount`/`self` fields —
  zero new mechanism, pure composition of 2 already-shipped pieces.
- **Grav Apple(716)** — power boosts under Gravity; since Gravity(356)
  itself is on Rob's exclusion list (unimplemented, permanently
  excluded), this condition is permanently moot and Grav Apple reduces
  to a plain damage move — confirmed, not silently dropped, matching the
  Metal Powder/Quick Powder "untestable condition, explicitly flagged"
  precedent from `[M18g]`.

### D4 — Singleton pool: RE-DERIVED AND RECONCILED, 97 moves confirmed (2026-07-10 recon pass, supersedes the original ~130-move first-pass sweep)

**Update (2026-07-14, `[D4 Bundle 6]`)**: 23 more moves shipped from this
pool in one bundle — all 23 of the REUSE-LIKELY-tagged moves from the
verification-pass recon immediately preceding it (see the `#### D4
Bundle 6` entry further down this section for the full move list and
findings). **D4's remaining pool is now 19 moves** — the CHEAP/MODERATE/
HARD/BLOCKED per-move breakdown tables below this point were NOT
individually re-edited to strike the 23 shipped moves out (a deliberate,
disclosed bookkeeping gap, not a re-derivation — Section E's own summary
table and the top-of-document totals ARE fully reconciled at 19). A
future session picking from this pool should cross-check any candidate
move against `gen_moves.py`'s real `MOVES` dict before trusting this
section's own per-move tier tags.

**Update (2026-07-14, exclusion bookkeeping)**: 6 more moves permanently
excluded by Rob's own choice/scope call, following a fresh residual-sort
recon pass over all 19 remaining moves — see Section C2's own newly-added
bullet for the full per-move reasoning (Round(496)/Snatch(289)/
Imprison(286)/Grav Apple(716) were all REUSE-LIKELY at the recon pass but
excluded anyway by Rob's choice; Nature Power(267)/Camouflage(293) are a
genuine capability gap, sharing Secret Power's own `gBattleEnvironment`
blocker). **D4's remaining pool is now 13 moves.** Same disclosed
bookkeeping gap as above applies — the per-move tier tables below were
not individually re-edited to strike these 6 out; Section E's summary
table and the top-of-document totals below ARE fully reconciled at 13.

**Update (2026-07-14, `[D4 Bundle 7]`)**: all 7 of the remaining
REUSE-LIKELY moves shipped in one bundle — Curse(174)/Focus Punch(264)/
Grudge(288)/Last Resort(387)/Pollen Puff(639)/Beak Blast(653)/Shell
Trap(658). **D4's remaining pool is now 6 moves — Mimic(102)/
Transform(144)/Sketch(166)/Perish Song(195)/Sky Drop(507)/Flying
Press(560) — every one of them confirmed genuinely NOVEL-MECHANISM at
the preceding recon pass, not merely unaddressed.** No REUSE-LIKELY
moves remain anywhere in Section D or M19 as a whole; any future M19
session picking up this pool is choosing among build-a-new-mechanism
work, not further bulk data-entry. Same disclosed bookkeeping gap as
above — Section E's summary table and the top-of-document totals below
ARE fully reconciled at 6.

**Update (2026-07-14, `[D4 Bundle 9]`)**: Flying Press(560) and Sky
Drop(507) — re-derived fresh from source at Step 0 per Rob's explicit
"report only first" instruction, then implemented after Rob's 3
decisions on the open questions (Flying Press's STAB deviation from
source's own mutation artifact; Sky Drop's attacker-faints-while-holding
reciprocal release; the freeze/paralysis behavior verified-and-documented
rather than built) — both shipped. **D4's remaining pool is now 4
moves — Mimic(102)/Transform(144)/Sketch(166)/Perish Song(195), every
one of them confirmed genuinely NOVEL-MECHANISM.** Section D as a whole
— and M19 as a whole — has no REUSE-LIKELY or partially-scoped moves
left anywhere; the remaining 4 are the entirety of what's left. Section
E's summary table and the top-of-document totals below ARE fully
reconciled at 4.

**This entire section was rebuilt from scratch this session** — not
patched — using a fully programmatic cross-check rather than trusting the
original recon's prose: `all 934 real move IDs` minus `gen_moves.py`'s
622 implemented IDs minus the complete 215-ID permanently-excluded set
(Z-Move/Max-Move IDs 848–934, plus every individual ID from Rob's
`[M19-exclusions]` list reconstructed from Section C2's own itemized
breakdown, plus Secret Power(290)/Population Bomb(788)) yields **exactly
97 moves** — cross-validated against zero overlap between the excluded
and implemented sets, and matching Section E's own "Tier 4 residual: 97"
figure precisely. D0/D1/D2/D3 are all fully shipped, so this 97 **is**
the entirety of Section D's remaining scope.

**Two classes of discrepancy found**, exactly as anticipated by this
task's own Step 2 instruction:

1. **16 moves the old D4 write-up still named (even under a "(see D2)"/
   "(D1)" cross-reference) are already fully shipped** and have been
   dropped from this list entirely: Foresight(193), Odor Sleuth(316),
   Defog(432), Foul Play(492), Freeze-Dry(573), Photon Geyser(675),
   Body Press(704), Stone Axe(758), Ceaseless Edge(773), Ice Spinner(789),
   Mortal Spin(794), Tidy Up(808) (all via `[D2 batch]`/`[D2 batch 2]`),
   Wish(273), Yawn(281), Healing Wish(361), Lunar Dance(461) (all via the
   Delayed-effect-family session). The old write-up's own prose already
   flagged most of these as shipped-elsewhere via inline "(see D2)"/"(D1)"
   notes, but the CHEAP/MODERATE bucket text and counts were never
   actually trimmed to remove them — a pure bookkeeping gap, not a new
   finding about the moves themselves.
2. **10 moves are genuinely still unbuilt but were NEVER individually
   named anywhere in the old D4 or D3 write-ups at all** — a real gap in
   the original recon, not just staleness: Dream Eater(138), Struggle(165),
   Belly Drum(187), Taunt(269), Helping Hand(270), Magic Coat(277),
   Assurance(372), Heal Pulse(505), Flying Press(560), Octolock(699). Two
   of these are especially high-value (see FREE tier below).

Every one of the 97 was re-derived fresh from `data/moves.json`'s
`effect_name` field and spot-checked against `moves_info.h`/
`battle_util.c`/`battle_script_commands.c` directly (not trusted from the
old recon's tags) — full findings below, organized by tier and by newly-
discovered shared-mechanism cluster.

#### FREE (2 moves) — mechanism already 100% built and wired, only a `.tres` data entry is missing

- **Struggle(165)** — already flagged in a prior session
  (`[M19-section-d-cluster]`): fully implemented as
  `BattleManager._construct_struggle_move()`, a hardcoded inline
  `MoveData` for the no-PP fallback since M1. Sits in this residual by ID
  alone; needs zero further mechanism work — the only open question is
  whether/how Rob wants a `.tres` entry added at all, given it's
  constructed programmatically rather than data-driven.
- **Helping Hand(270)** — a genuinely new finding this session, not
  previously flagged anywhere: `MoveData.is_helping_hand`, the full
  dispatch in `_phase_move_execution` (including the fail-in-singles/
  fail-if-ally-already-moved/fail-if-ally-fainted checks), the
  `_helping_hand[]` per-slot state array, and the `helping_hand_used`
  signal are ALL already implemented and wired end-to-end (`[M14b]`) —
  confirmed via direct grep, not inferred. Multiple LATER sessions
  (`[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`) even cited
  Helping Hand's own mechanism as an existing precedent to reuse for
  Aromatic Mist/Coaching, without anyone noticing the move itself had no
  `.tres` file. Source-confirmed identical to this project's own doc
  comment (`move_data.gd`'s `is_helping_hand`, target=ALLY, priority=+5,
  ignoresProtect/ignoresSubstitute=TRUE) — zero discrepancy, pure data-
  entry gap exactly matching the `[D0]` Follow-Me/Soft-Boiled precedent.

#### Newly-discovered clusters (Step 4) — genuine sibling mechanisms hiding in the singleton pool

**"Call-a-different-move" family (5 moves)** — all reassign the user's
own move to some OTHER move and let it execute, reusing the exact
"duplicate/substitute and fall through" pattern Mirror Move/Metronome
already established (and D3's Instruct extended to reassigning the
attacker too):
- Sleep Talk(214) — CHEAP. Random from the user's own moveset,
  sleep-gated. (Already informally flagged as reusing this pattern in the
  old write-up — now formalized into its proper cluster.)
- **Nature Power(267) — CORRECTED to BLOCKED (`[D4 bundle]`, 2026-07-10)**.
  This entry originally claimed Terrain's permanent void collapses Nature
  Power to "always call one fixed default move" — WRONG, caught during
  the `[D4 bundle]` session's own Step 0: source's `GetNaturePowerMove()`
  checks Terrain FIRST (correctly moot, Terrain is void), but falls
  through to `gBattleEnvironmentInfo[gBattleEnvironment].naturePower` —
  the SAME overworld-tile field Secret Power/Camouflage are blocked on.
  Only environments explicitly configured with no default move use the
  TRI_ATTACK/SWIFT fallback; every real environment (grass/cave/water/
  etc.) has its own specific move, so defaulting to "always TRI_ATTACK"
  would be wrong most of the time. Moved to the BLOCKED tier below,
  alongside Secret Power/Camouflage — see that section for the corrected
  count.
- Copycat(383) — MODERATE. Calls the global last-move-used-by-anyone;
  needs a new field to track it (the reassignment mechanism itself is
  free, but the "what was the last move" tracker is new state).
- Me First(382) — MODERATE. Copies the TARGET's own chosen move
  (turn-order-dependent — must act before the target) with a power boost;
  needs to read the target's pre-resolved chosen move, likely reusing
  `[M18j]`'s existing turn-position/action-queue visibility.
- Assist(274) — MODERATE. Random move from the whole PARTY's movepool
  (not just the user's own) — the reassignment half is free, but
  enumerating "every move every bench Pokémon knows" is new surface area.

**Magic Coat / Snatch — "intercept the next qualifying move this turn"
family (2 moves)**:
- Magic Coat(277) — CHEAP (reclassified). Confirmed directly from source
  (`battle_move_resolution.c` L5157: `return TryMagicBounce(cv) ||
  TryMagicCoat(cv);`) that Magic Coat shares the EXACT SAME dispatch
  chain as the already-implemented Magic Bounce ability (`[M17n-9]`) —
  it's mechanically a temporary, move-granted version of the same
  bounce-back-the-first-foe-status-move logic, just gated by a new
  per-turn volatile instead of an ability check. Reuses Magic Bounce's
  existing 9-move bounceable-move whitelist and non-recursive
  attacker/defender swap almost entirely.
- Snatch(289) — MODERATE. A related but genuinely different shape —
  STEALS (not bounces) the next qualifying status move's effect for
  itself, redirecting its outcome onto the Snatch user rather than
  reflecting it at its original user. Shares the "intercept before it
  resolves" timing with Magic Coat but not the swap mechanism itself.

**Existing small pairs/trios (carried over from the old write-up,
still valid, unaffected by this recon)**:
- Stockpile(254)/Spit Up(255)/Swallow(256) — MODERATE. Self-contained
  3-move combo trio (counter + scaled damage + scaled heal); all 3 need
  building together.
- Mud Sport(300)/Water Sport(346) — MODERATE. Temporary field-wide
  type-damage halving, a new small field modifier shared by both.
- Gyro Ball(360)/Electro Ball(486) — CHEAP. Speed-ratio power formulas,
  a natural pair (same shape, different ratio direction).

#### Reclassified CHEAP (were MODERATE or unnamed in the old sweep — genuinely easier now given infrastructure built since)

- **Taunt(269)** — MODERATE→CHEAP. Source confirms `volatiles.tauntTimer`
  is a plain turn-counter volatile blocking STATUS-category move
  selection — the exact shape already established three times over
  (Disable/Encore/Throat Chop: a turn-counter volatile gating a move
  category at selection/execution time). Aroma Veil's own blocking hook
  (`[M17n-1]`) explicitly anticipated extending to Taunt already.
- **Assurance(372)** — CHEAP (never individually named before). Source
  confirms `assuranceDoubled` is a flag set on whichever battler took ANY
  damage this turn, from anyone — this project's own
  `BattlePokemon.hit_by_this_turn` (built for Revenge, `[D1 easy
  bundle]`) already tracks exactly this. `not defender.hit_by_this_turn.
  is_empty()` answers the whole condition directly — zero new state.
- **Octolock(699)** — CHEAP-MODERATE (never individually named before).
  Traps the target (reuses the escape-prevention mechanism directly,
  `[M19f]`) AND applies a recurring end-of-turn Def/SpDef stat drop tied
  to the trapper — the trap half is free; the recurring EOT tick is a
  small new addition, similar in shape to Leech Seed's own end-of-turn
  tick (source reference, not HP drain).
- **Chilly Reception(807)** — reconfirmed CHEAP, no longer conditional.
  The old write-up flagged this as cheap "once D1's weather cluster
  ships" — it has (`[D1 cheap clusters]`), so the condition is now simply
  satisfied.

#### HARD (4 moves) — re-confirmed, one pair flagged for a possible future downgrade

- **Transform(144)** — still HARD. No new precedent anywhere in this
  project for "become a full copy of another Pokémon" (stats, moves,
  type, ability all at once).
- **Sky Drop(507)** — still HARD. No precedent for a move that revokes
  the DEFENDER's own action availability for a turn (every other
  two-turn/semi-invulnerable move only affects the user's own state).
- **Beak Blast(653)/Shell Trap(658)** — still tagged HARD, but with a
  genuine new lead: source keys both off `gChosenMoveByBattler[
  battlerDef]` — reading what the OPPONENT selected THIS turn, before it
  resolves. This project's own architecture already selects every
  battler's action up front (before `PRIORITY_RESOLUTION` executes any of
  them), which MIGHT mean the equivalent fact is already readable via the
  existing action-queue state rather than needing new prediction
  infrastructure. **Not confirmed either way this session** — flagged as
  a concrete architecture question for whichever future session picks
  these two up, not asserted as an actual downgrade.

#### BLOCKED (2 moves — corrected from 1, `[D4 bundle]`, 2026-07-10)

- **Camouflage(293)** — re-confirmed the same `gBattleEnvironment`
  (overworld map/tile-derived field) blocker as Secret Power(290, now
  permanently excluded).
- **Nature Power(267)** — moved here from the "call-a-different-move"
  cluster above, `[D4 bundle]` session — genuinely shares Camouflage/
  Secret Power's own `gBattleEnvironment` blocker via its post-Terrain
  fallback, a real correction to this row's own original "reduces to a
  fixed call" framing. Both moves should stay deferred alongside Secret
  Power, not attempted independently.

#### Full corrected tier counts

**FREE: 2. CHEAP: 62. MODERATE: 27. HARD: 4. BLOCKED: 2. Total: 97** —
corrected from the original 2/63/27/4/1 split after `[D4 bundle]`'s own
Step 0 moved Nature Power from CHEAP to BLOCKED; confirmed by direct
tabulation, matching Section E's own residual figure exactly (the 97
total itself is unaffected — this was a reclassification within the
pool, not a count change).

#### D4 bundle — CLOSED, COMPLETE (`[D4 bundle]`, 2026-07-10)

The 2 FREE moves (Struggle, Helping Hand) plus 4 of the CHEAP moves
recommended below (Sleep Talk, Taunt, Assurance, Magic Coat) shipped —
**Nature Power was pulled from the bundle per its own corrected BLOCKED
status above**, deferred alongside Secret Power/Camouflage rather than
force-shipped. 6 moves shipped total. See `docs/decisions.md`'s
`[D4 bundle]` entry for the full Step 0 findings, two real gaps caught
before the first test run (Helping Hand/Magic Coat both needed their own
`ban_flags` — missed on the first data-entry pass — and Sleep Talk needed
an explicit "is the attacker actually asleep" gate independent of its
`pre_move_check` bypass), and the two test-authoring bugs caught during
the suite's own first run. **Total move-implementation count: 622→628.**
D4's own remaining pool: 91 moves (97 − 6 shipped), unaffected by the
Nature Power reclassification (still counted in D4's total either way).
**Further reduced to 79 by the `[D4 CHEAP bundle]` session below (12 more
moves shipped).**

**Historical recommendation (superseded by the shipped session above):**
A CHEAP-tier bundle of the 2 FREE moves (Struggle, Helping Hand) plus
the newly-formalized "call-a-different-move" family's CHEAP member
(Sleep Talk, Nature Power) and the 3 reclassified-CHEAP singletons
(Taunt, Assurance, Magic Coat) — 7 moves total, all confirmed CHEAP or
FREE this session, spanning one genuinely new small mechanism (Taunt's
turn-counter volatile, though fully precedented) and otherwise pure data-
entry or direct reuse of already-proven infrastructure (Magic Bounce's
swap, Revenge's `hit_by_this_turn`, the Mirror-Move/Metronome
reassignment pattern). This is comparable in size and risk profile to
prior successful bundle sessions (`[Bucket 4 cheapest singles]`,
`[D1 cheap clusters]`) and would immediately bank 2 free wins plus 5
cheap ones before tackling the remaining, more heterogeneous CHEAP/
MODERATE pool.

#### D4 CHEAP bundle — CLOSED, COMPLETE (`[D4 CHEAP bundle]`, 2026-07-10)

12 moves shipped: Dream Eater(138), Torment(259), Gyro Ball(360),
Electro Ball(486) (the 4 confirmed standouts named in the prompt) plus 8
additional CHEAP-tagged picks selected and Step-0-verified before
implementation — Snore(173), Endure(203), Fell Stinger(565), Magnet
Rise(393), Smack Down(479), Ingrain(275), Aqua Ring(392), Payback(371).
Snore(173) was a genuine gap in this section's own residual accounting —
never individually named in either the "10 moves never named" list above
or anywhere else in this document, despite being mathematically part of
the pre-session 91-move residual (confirmed via direct `gen_moves.py`
diff: absent from the pre-session 628-implemented set, absent from every
excluded-list citation in this document) — a pure prose-completeness gap
in the residual pool's own itemization, not a miscount of the pool's
size.

Several real Step-0 corrections found and confirmed against source before
implementing (full citations in `docs/decisions.md`'s own `[D4 CHEAP
bundle]` entry): Dream Eater's drain reuses the generic `EFFECT_ABSORB`/
`EFFECT_DREAM_EATER` `drain_percent` chokepoint (Giga Drain's own family),
NOT the Volt Absorb/Water Absorb ABILITY family the task's own prompt
suggested checking; Torment is a PERMANENT (never-naturally-expiring)
target-side volatile, reusing Blood Moon's `cant_use_twice` SHAPE but
target- rather than self-inflicted (the decoy `tormentTimer`/
`Cmd_TrySetTormentSide` path belongs to an unimplemented side-wide
variant); Electro Ball's speed-ratio formula is confirmed genuinely
stepped/banded (a fixed 5-entry lookup table), NOT a mirrored version of
Gyro Ball's own continuous formula; Endure shares Protect/Detect's
`Cmd_setprotectlike` dispatch, but that command itself branches
internally to a SEPARATE `endure_active` field (never touching
`protect_active`) — the session's own first-draft plan (reuse
`protect_active` with an `_is_protected_from` bypass case) was found
wrong against source and abandoned before any code was written; Ingrain's
own scope turned out FULLY buildable (self-heal + self-grounding + BOTH
voluntary-switch-block AND forced-switch-block against Roar/Circle Throw/
Red Card, confirmed from source that Roar's own script checks
`VOLATILE_ROOT` directly) rather than the partial "flag but don't build
the Roar-block" scope originally proposed — achieved via pure reuse of
the existing `AbilityManager.blocks_forced_switch`/`is_trapped`
functions, a fuller build than planned, not a scope cut.

A real, pre-existing gap was found and fixed as a byproduct of Smack
Down/Ingrain's own grounding work, unrelated to any single move in this
bundle: `TypeChart.get_uq412` never had a `grounded_override` parameter
at all (unlike `get_effectiveness`, which already did, built for Iron
Ball in `[M18t]`) — meaning `DamageCalculator.calculate`'s own SECOND,
independent UQ4.12 damage computation would silently re-immune a Ground-
type move against ANY forced-grounded target (Iron Ball holders
included, not just this bundle's new moves) even after the FIRST
immunity gate already correctly passed it through. Fixed by adding the
identical parameter/check to `get_uq412` and threading it through both of
`calculate`'s own call sites — confirmed via `damage_test`/`m18t_test`
both still passing unchanged.

New `d4_bundle2_test.gd`/`.tscn`: 66/66 assertions, stable across 8
reruns after fixing 4 real test-authoring bugs on the first run (a
whole-battle-aggregation instance in the Torment discriminator, fixed via
an ordered timeline isolating just the turn-2 scenario under test; two
missing `queue_move` calls that silently let auto-select re-pick a
move's own first slot every turn instead of exercising the intended
second move, for both the Smack Down and — diagnosed via a throwaway
debug scene — the Payback test; and an exact-equality pairwise-damage
assertion that didn't account for integer-division rounding, fixed with
a small tolerance, matching this project's own established convention
for this exact class of comparison). Also caught and fixed a real
regression during this session's own regression sweep, not by the test
suite itself: the `is_protect` dispatch's Endure branch had moved
`protect_consecutive`'s increment to AFTER `protected.emit()`, changing
the order relative to `[M7]`'s pre-existing `protected`-signal listeners
(which read `protect_consecutive` at the moment the signal fires) —
`tier4_test.gd`'s own S4.04 caught this immediately and consistently
across every rerun; fixed by incrementing before the emit in both
branches, matching the original ordering exactly. One additional flaky
test was found and root-caused as PRE-EXISTING and unrelated: `m19a_gen1_
test.gd`'s own "Hydro Pump does NOT trigger Rough Skin" discriminator
(a whole-battle-aggregation bug in a much older test file, untouched by
this session) — confirmed via `git stash` to reproduce identically on
the pristine pre-session baseline, flagged not fixed, out of this
session's own scope.

Regression: the 4 required suites (`damage_test`/`move_test`/`stat_test`/
`status_test`) plus every suite touching reused infrastructure
(`d4_bundle_test`/`tier4_test`/`m17n5_test`/`m18o_test`/`m16d_test`/
`m17f_test`/`m18t_test`/`switch_test`/`m17n10_test`/`m18n_test`/
`d1_easy_bundle_test`/`item_registry_test`/`ability_test`/`m18q_test`/
`doubles_test`/`m17n9_test`/`weather_test`) — all clean. Given this
session's changes touch `DamageCalculator`/`TypeChart` (used by every
damaging move in the roster), a full 106-file sweep was also run twice
from independent process states: 0 real failures both times (the single
`m19a_gen1_test` flake above reproduces identically with or without this
session's changes, confirmed via `git stash`).

**Total move-implementation count: 628→640.** Section D's residual:
91→79 (all 12 moves confirmed part of the pre-session residual pool, none
from the excluded set). Reconciliation: 640 implemented + 79 D4 residual
+ 215 excluded = 934, confirmed by direct addition.

#### D4 bundle 3 — CLOSED, COMPLETE (`[D4 bundle 3]`, 2026-07-10)

12 more moves shipped, all self-selected from the remaining residual
pool rather than user-named: Splash(150), Refresh(287), Purify(648),
Memento(262), Belly Drum(187), Fillet Away(796), Clangorous Soul(703),
Nightmare(171), Spite(180), Recycle(278), Facade(263), Take Heart(778).

Real Step-0 corrections found before implementing (full citations in
`docs/decisions.md`'s own `[D4 bundle 3]` entry): Refresh cures Burn/
Poison/Toxic/Paralysis ONLY — confirmed via source's own
`STATUS1_CAN_MOVE` bitmask that Sleep and Freeze are explicitly
excluded, matching the move's own literal flavor text rather than a
folklore "cures anything" assumption; Take Heart raises Attack + Sp.Atk
(source's own data table), NOT Sp.Atk/Sp.Def as general series knowledge
would suggest; Belly Drum/Fillet Away/Clangorous Soul all hard-fail with
ZERO HP cost unless the stat change would genuinely do something AND the
HP payment can be made (`WillAnyStatChange() && Try*Hp(...)`, an AND
gate — confirmed NOT "always pay HP, sometimes no boost"), with
Clangorous Soul's own divisor (a third of max HP) genuinely different
from the other two's (half); Recycle restores a NEW, genuinely BROADER
`BattlePokemon.last_used_item` field (any item, not just berries),
confirmed distinct from Harvest/Cud Chew's own berry-only
`last_consumed_berry` tracker via direct source read of
`Cmd_removeitem`/`usedHeldItem` — with an explicit Air-Balloon-pop
exclusion mirroring source's own "cannot be restored by any means"
carve-out; Facade's burn-halving bypass is confirmed a separate,
independent mechanism from Guts', not conditioned on it
(`B_BURN_FACADE_DMG >= GEN_6` at this project's config).

**A real, previously-flagged-as-open bug was also resolved this
session**: `[D2 batch 2]`'s own Foresight entry had explicitly flagged
"whether any OTHER already-shipped move shares this same gap [a script
that never calls `typecalc`] is an open question beyond this session's
own scope." This session found the answer — Purify(648, Poison-type),
Nightmare(171, Ghost-type), and Spite(180, Ghost-type) all share it,
confirmed via direct source read of their own battle scripts. Most
consequentially for Nightmare: its own primary use case (an asleep
Normal-type target) is the EXACT Ghost-vs-Normal-immunity shape
Foresight's own bug already demonstrated — this project's general
foe-targeting type-immunity gate was silently blocking Nightmare against
its own most common target before this fix. (Memento, Dark-type, shares
the same gap in principle but is provably unreachable — no type in this
project's own chart is immune to Dark — so it was deliberately left off
the exemption list rather than added for no behavioral effect.)

New `d4_bundle3_test.gd`/`.tscn`: 56/56 assertions, stable across 9
reruns after fixing 6 real test-authoring bugs, ALL instances of the
same whole-battle-aggregation pitfall (reading state after
`start_battle()` returns instead of snapshotting live inside a signal
handler) recurring across multiple independent tests in this one
session — Splash's own discriminator collided with the opponent's
unrelated Growl move eventually hitting its own "stat_limit" failure
message over many turns (same battler identity, different move, same
signal); the HP-cost stat-boost family's own tests read `current_hp`/
`stat_stages` after the full multi-turn battle instead of at the moment
of interest, both for the successful-boost case (later chip damage from
the opponent's own Tackle) and the discriminator-fail case (same); and
Fillet Away/Clangorous Soul's own `stat_stage_changed` listeners had no
first-occurrence guard, so a defender's own unrelated stat-lowering move
on a LATER turn would silently overwrite the captured delta. Also fixed
one real test-DESIGN error (not aggregation): the Memento-vs-Substitute
discriminator originally asserted the self-faint would ALSO be blocked
by Substitute, contradicting this move's own implementation (and its
well-established real-game behavior) — Substitute protects the TARGET
from a move's effects, not the ATTACKER from its own move's
self-consequence, so only the stat-drop is Substitute-gated; the test's
own expectation was corrected to match, not the implementation.

Regression: the 4 required suites plus a full 107-file sweep (this
session's changes touch `_consume_item`/the shared type-immunity
gate/`DamageCalculator`'s burn modifier, all central chokepoints), run
twice from independent process states — 0 real failures either time
(the same pre-existing, already-diagnosed `m19a_gen1_test` flake from
the prior `[D4 CHEAP bundle]` session reproduces identically, confirmed
unrelated).

**Total move-implementation count: 640→652.** Section D's residual:
79→67. Reconciliation: 652 implemented + 67 D4 residual + 215 excluded =
934, confirmed by direct addition.

#### D4 Bundle 4 — CLOSED, COMPLETE (`[D4 Bundle 4]`, 2026-07-13)

12 more moves shipped, proposed as 4 mechanism-clusters and confirmed
individually at Step 0 rather than assumed symmetric within a cluster:
Tailwind(366)/Sticky Web(564)/Safeguard(219)/Mist(54) (side-condition
timers), Copycat(383)/Me First(382)/Assist(274) (call-a-different-move
family), Heal Pulse(505)/Life Dew(719) (target-directed heal variants),
Stockpile(254)/Spit Up(255)/Swallow(256) (Stockpile family).

Real Step-0 corrections found before implementing (full citations in
`docs/decisions.md`'s own `[D4 Bundle 4]` entry): Sticky Web's own -1
Speed switch-in effect routes through the FULL generic stat-change
pipeline (`_apply_one_stat_change_pair`) rather than a raw hazard tick
like Spikes/Toxic Spikes/Stealth Rock — confirmed via source
(`battle_stat_change.c` L481-491) that the switch-in drop dispatches
through the ordinary `SetStatChange`/`StatChanged` path, so
Defiant/Competitive/Mirror Armor/Opportunist/Mirror Herb all react to it
correctly, a real behavioral difference from the other three hazards.
Mist and Safeguard both bypass an opposing Infiltrator holder — a real,
previously-anticipated-but-unwired extension of
`AbilityManager.bypasses_infiltrator_barriers`, whose own doc comment
had explicitly flagged this exact addition in advance ("source's
Infiltrator also bypasses Mist and Safeguard, but neither exists in this
project"). Me First — the bundle's own flagged HIGH-SCRUTINY item — needs
NO turn-order pre-emption at all: confirmed via direct source read
(`GetMeFirstMove`, `battle_move_resolution.c` L5143-5151) it's a passive
`HasBattlerActedThisTurn` check, reusing the existing
`_has_target_already_acted` primitive built for Zoom Lens/Upper Hand —
whether Me First "works" is purely a function of the EXISTING
speed/priority-driven turn order, no broader refactor needed. Copycat's
own "last move used by anyone" tracker (`_last_landed_move_anyone`) is
genuinely distinct from the existing per-mon `last_move_used` (gated on
the move actually LANDING — confirmed via source's `gLastUsedMove`
assignment, `battle_move_resolution.c` L3034-3039 — not merely being
attempted); a disclosed simplification, not silently assumed complete:
only ordinary damaging hits (the `_do_damaging_hit` `damage > 0` gate,
the same one Rapid Spin/Air Balloon already use) update this tracker,
since this project has no single dispatch chokepoint every status-move
effect passes through — a landed status move isn't tracked. Heal Pulse's
Mega Launcher boost (75% vs. 50%) is a hardcoded special case inside the
heal-amount calc itself (`BS_TryHealPulse`, `battle_script_commands.c`
L11645-11663), NOT the generic pulse-move damage multiplier (moot
anyway, Heal Pulse has power=0). Stockpile's own `stockpile_count`
(scaling counter for Spit Up/Swallow, increments unconditionally) and
`stockpile_def_added`/`stockpile_spdef_added` (only the ACTUAL stat
rise, 0 if capped at +6 or inverted by Contrary) are genuinely SEPARATE
trackers — confirmed via source (`battle_stat_change.c` L481-491:
`stockpileDef`/`stockpileSpDef` only increment when `st->stage > 0`) —
release removes exactly the tracked amount via a RAW, ungated stat
decrease (source's own `SetStatChange` call for the undo has no
Mist/ability gate, unlike the original raise), and fires even when
Swallow's own heal "fails" at full HP (`MoveEndMoveBlock`,
`battle_move_resolution.c` L3416-3439, is gated only on the move being
ATTEMPTED, not on Spit Up/Swallow's own script succeeding —
`Cmd_stockpiletohpheal`'s own fail branch still zeroes
`stockpileCounter`). Also populated `BAN_COPYCAT`/`BAN_ME_FIRST`/
`BAN_ASSIST` across 22 already-implemented moves that needed them per
source (of 31 candidate moves found via a full source cross-check, 9 —
Struggle, Sleep Talk, Helping Hand, Feint, Shadow Force, Phantom Force,
Follow Me, Rage Powder, Thief, Covet — already had them correctly from
earlier tiers, confirmed unchanged rather than assumed).

A real, dispatch-ORDER bug (not a logic bug) was caught and fixed during
this session's own first test run: Spit Up carries a `power=1`
PLACEHOLDER (real power is `100 * stockpile_count`, computed at
dispatch time) — the same convention Sonic Boom/Dragon Rage/Night
Shade/OHKO already use, all of which are dispatched BEFORE the generic
`move.power > 0` damaging-move branch for exactly this reason. Stockpile/
Spit Up/Swallow were originally placed AFTER that generic branch (matching
the file position of thematically-similar moves like Heal Bell/Haze),
so the generic dispatch silently claimed Spit Up first, dealing a flat
power=1 hit and never reaching the real 100×count logic — caught because
Spit Up's own damage output didn't scale with stack count in this
session's first test run. Fixed by moving all three dispatch blocks
earlier, alongside OHKO/Counter/Mirror Coat/Metal Burst.

Two required additional Step-0 items closed by dedicated tests: (1) Me
First calling a target move that is ITSELF a move-reassignment effect
(Metronome/Sleep Talk) — resolved as genuinely IMPOSSIBLE, not merely
"handled cleanly": Metronome/Sleep Talk/Mirror Move/Copycat/Assist are
ALL `category == STAT` in this project's schema, and Me First's own
`mf_target_move.category == 2` gate excludes status moves entirely,
before the reassignment logic is ever reached — closing the exact edge
case flagged as unresolved in this bundle's own Step 0 report (source's
`meFirstBanned` flag on these moves is therefore redundant with the
category check in every one of this project's own implemented cases,
though still faithfully populated per source). (2) A Contrary-holding
Pokémon using Stockpile — confirmed Def/SpDef are LOWERED (not raised)
and `stockpile_def_added`/`stockpile_spdef_added` do NOT increment (0,
not negative), while `stockpile_count` still does (the scaling counter
increments unconditionally regardless of the raise's real direction).

Also explicitly verified per this bundle's own additional requirements:
`_last_landed_move_anyone` is correctly battle-scoped — a plain
`BattleManager` instance var, never reset mid-battle but also never
leaking across battles, since every test in this codebase (confirmed via
a repo-wide grep before relying on this) creates a fresh
`BattleManager.new()` per battle; and it's assigned at the same point in
the turn sequence as source's `gLastUsedMove` — inside `_do_damaging_hit`,
at the identical `damage > 0` gate Rapid Spin/Air Balloon already use,
which only fires once accuracy/immunity/Protect have already resolved
in the attacker's favor (i.e. only after the hit has been confirmed to
actually affect its target), not earlier and not from a separate
dispatch path.

New `m17j`/`m17n9`-adjacent signals (`side_condition_set`/
`side_condition_expired`/`stockpile_gained`/`stockpile_released`); new
`BattlePokemon.stockpile_count`/`stockpile_def_added`/
`stockpile_spdef_added` (cleared in `_clear_volatiles` like every other
switch-scoped volatile); new `StatusManager.effective_speed`
`tailwind_active` param (wired into turn-order sort + Gyro Ball/Electro
Ball's own speed reads); new `DamageCalculator.calculate` `me_first`
param (same ×1.5 pipeline stage as `helping_hand`); `_apply_one_stat_change_pair`
extended to return `int` (previously void) and gained the Mist gate,
checked before Mirror Armor/the ability-block chain, matching source's
own `CanDecreaseStat` ordering.

New `d4_bundle4_test.gd`/`.tscn`: 89/89 assertions, stable across 5
reruns after fixing 6 real test-authoring bugs on the first run (80/90) —
all fresh recurrences of the whole-battle-aggregation pitfall (Stockpile/
Contrary-Stockpile/Spit-Up-release/Life-Dew-heal-amount tests all
originally read state after `start_battle()` fully returned instead of
snapshotting via signal at the moment of interest; the Me-First-chains-
into-Metronome/Sleep-Talk tests originally checked "did `move_called`
ever fire for the attacker" unguarded, which incorrectly caught a LATER
Struggle fallback once Me First's own PP ran out over the many
auto-repeated turns) plus one speed-value tuning bug (B.04's "outpaces"
comparison used stat values too far apart for a ×2 multiplier to close
the gap) and one shared-resource-mutation bug (a Mist unit test mutated
a cached, shared `Growl` MoveData directly instead of via `.duplicate()`,
found and fixed even though it happened not to affect this session's own
outcome). Regression: the required suites plus a full 108-file sweep
(this session's changes touch `_apply_one_stat_change_pair`,
`StatusManager.try_apply_status`/`try_apply_confusion`/
`try_secondary_effect`/`effective_speed`, `DamageCalculator.calculate`,
`_do_damaging_hit`, `_do_multi_hit_sequence`, `_clear_volatiles` — all
central chokepoints), run twice from independent process states via
`scripts/count_assertions.sh` — **11407 total assertions, 0 failures,
identical GRAND TOTAL both runs**.

**Total move-implementation count: 652→664.** Section D's residual:
67→55. Reconciliation: 664 implemented + 55 D4 residual + 215 excluded =
934, confirmed by direct addition.

#### D4 Bundle 5 — CLOSED, COMPLETE (`[D4 Bundle 5]`, 2026-07-14)

13 more moves shipped, self-selected from Section D's residual by the
assistant and confirmed by Rob before Step 0, across 7 mechanism-clusters:
Mud Sport(300)/Water Sport(346) (field-wide damage-reduction timers),
Weather Ball(311)/Reflect Type(513) (type-mutation family), Roost(355)/
Strength Sap(631) (heal-and-drain family), Steel Beam(724)/
Chloroblast(763) (HP-cost-attached-to-damage family), Charge(268)/Laser
Focus(636) (persistent-flag-consumed-by-next-action family),
Topsy-Turvy(576)/Autotomize(475) (stat-array manipulation), Fury
Cutter(210) (escalating power).

Real Step-0 corrections found before implementing (full citations in
`docs/decisions.md`'s own `[D4 Bundle 5]` entry): Mud Sport/Water Sport's
damage reduction is x0.33 at this project's `B_SPORT_DMG_REDUCTION>=GEN_5`
config, NOT x0.5 (the pre-Gen-5 value some folk knowledge assumes) —
confirmed genuinely FIELD-WIDE (`.target = TARGET_FIELD`), not per-side
like Tailwind/Safeguard/Mist, via two standalone `_mud_sport_turns`/
`_water_sport_turns` battle-wide ints mirroring `_echoed_voice_counter`'s
own shape rather than extending `_side_conditions`. Weather Ball bundles
TWO independently-computed pieces under one effect ID — a type mutation
(Sun→Fire/Rain→Water/Sandstorm→Rock/Hail→Ice, computed in
`DamageCalculator.calculate`'s pre-processing pass alongside Hidden
Power, with a matching `is_weather_ball` exclusion added to
`AbilityManager.effective_move_type`) and a SEPARATE x2 power multiplier
in any weather except Strong Winds — confirmed as two distinct source
hookups (`battle_main.c` L5812-5833 for the type; `battle_util.c`
L6175-6177 for the power), not one shared function. Reflect Type needed
a genuinely NEW `_set_mon_type_array` sibling function — `_set_mon_type`
(the pre-existing function backing Conversion/Conversion 2/Protean/
Libero/Multitype/Forecast) always forces a mono-type result and cannot
represent copying a dual-type target's full array — confirmed via a
REQUIRED regression test that all 3 reachable existing callers
(Conversion/Protean/Multitype) still produce byte-identical mono-type
results afterward (all still padding to `[TYPE_X, TYPE_NONE]`, a real
test-authoring correction caught on the first run — see below). Reflect
Type's Multitype exclusion is ability-keyed (`effective_ability_id ==
ABILITY_MULTITYPE`), not species-keyed like source's own
`targetBaseSpecies == SPECIES_ARCEUS` check — this project has no
species-check pattern anywhere, and Multitype is itself implemented
purely as an ability+Plate check (`[M17n-4]`), so the ability-keyed
equivalent is the establishment-consistent choice, not a new pattern for
one move. Reflect Type is also exempted from the general
foe-targeting-move type-immunity gate — confirmed via direct source read
(`BattleScript_EffectReflectType`, `data/battle_scripts_1.s` L991-999)
that its own script never calls `typecalc`, the same precedent
Foresight/Purify/Nightmare/Spite already established. Roost's type
removal is a query-time overlay in real source (a plain `roostActive`
bool consulted at every type-read call site via ONE funneled getter,
`GetBattlerTypes`) — this project has no such funneled getter (type
reads happen directly off `species.types` at each call site), so Roost
instead mutates `species.types` directly at use-time (via
`_set_mon_type_array`) and restores the EXACT pre-mutation snapshot
(`BattlePokemon.roost_pre_types` — deliberately NOT `original_types`,
since a mon with an already-active Conversion/Protean mutation must be
restored to THAT state, not its natural species type) via a NEW
end-of-turn trigger, rather than reusing `_reset_mon_type`'s existing
switch-in-only restore. Confirmed a mono-Flying Roost user becomes pure
NORMAL-type for the turn (not typeless) at this project's
`B_ROOST_PURE_FLYING>=GEN_5` config. Strength Sap's heal and stat-lower
are NOT independent — confirmed via source
(`CheckSpecificMoveCondition`/`SetStrengthSapHealing`,
`battle_stat_change.c` L50-113) that if the target's Attack is already at
-6, NEITHER the heal NOR the lower happens (the whole move fails with
"Attack won't go any lower"), rather than healing unconditionally and
merely failing the stat-lower half; the heal amount reads the target's
CURRENT (stat-stage-adjusted) Attack, reusing
`DamageCalculator._apply_stage` directly. Steel Beam and Chloroblast —
despite the "same family" framing — diverge in a load-bearing way,
exactly as Step 0 flagged to verify rather than assume symmetric: Steel
Beam applies ceil(maxHP/2) self-recoil UNCONDITIONALLY (hit, miss, OR
Protect-blocked), gated ONLY by Magic Guard, dispatched from THREE
separate call sites (the Protect-block early return, the accuracy-miss
early return, and the normal post-hit-resolution path) via a new shared
`_apply_max_hp_50_recoil` helper — a genuinely different, UNCONDITIONAL
shape from both this project's existing `crash_damage` (fires only on a
FAILED hit) and `recoil_percent` (fires only on a CONNECTING hit)
mechanisms; Chloroblast, despite sharing the identical ceil(maxHP/2)
formula, is dispatched through the ORDINARY `EFFECT_RECOIL`-shaped path
(requires a connecting hit, blocked by BOTH Rock Head and Magic Guard via
the existing `AbilityManager.blocks_recoil`) — confirmed via source that
it shares literally the same switch-case as ordinary recoil moves
(`battle_move_resolution.c` L3370-3389), not Steel Beam's own
`MoveEndAbsorb`-routed dispatch. Charge's `attacker.charged` flag, per
the ACTUAL executable source (`TryClearChargeVolatile`,
`battle_move_resolution.c` L4927-4939) at this project's
`B_CHARGE=GEN_LATEST(>=GEN_9)` config, is consumed ONLY by using a
genuinely LATER Electric-type move — the function's OWN inline comment
claims "Charge status is lost regardless of the typing of the next
move," which directly CONTRADICTS its own executable code; the comment
is deliberately NOT trusted here, and a code comment at the implementation
site explicitly preserves this finding so a future session doesn't "fix"
it back to match the misleading comment. Laser Focus is a flat,
UNCONDITIONAL 2-turn guaranteed-crit window (`B_LASER_FOCUS_TIMER=2`,
decremented every end of turn regardless of whether the holder even
attacks) — genuinely NOT "consumed by the next qualifying hit" the way
Charge is; grants `CRITICAL_HIT_ALWAYS`, the SAME outright-guarantee tier
this project's Merciless ability already uses
(`DamageCalculator.calculate`'s own `merciless_guaranteed` pre-check,
extended with a parallel `laser_focus_guaranteed` condition) — NOT the
separate, dormant `MoveData.always_critical_hit` field (Storm
Throw/Frost Breath/Zippy Zap), which was found during this session to be
completely unconsumed anywhere in the codebase (those 3 moves are
actually represented via `critical_hit_stage=3` instead) — flagged as a
pre-existing, unrelated gap, not fixed here. Topsy-Turvy inverts the SIGN
of every nonzero stat stage (`new = -old`, cleanly symmetric at both
+6/-6 caps — `BS_InvertStatStages`, `battle_script_commands.c`
L13064-13074), NOT a reset-to-0 like Haze/Clear Smog; fails only if ALL 7
stats (including Accuracy/Evasion) are simultaneously at stage 0,
confirmed via the exact check order in
`BattleScript_EffectTopsyTurvy` (succeeds if even one is non-neutral).
Autotomize is SCOPE-LIMITED per Rob's explicit instruction: only the +2
Speed self-raise ships this bundle (a pure reuse of the generic
`stat_change_stat`/`amount`/`self` dispatch, confirmed via source that
Autotomize shares the literal same `BattleScript_EffectStatChange`
generic script Charge/Strength Sap also use — zero new code needed for
this half); the weight-reduction half (a stacking `autotomizeCount`
counter, -100kg per use down to a 0.1kg floor) is DELIBERATELY NOT BUILT
— this project's Low Kick/Grass Knot/Heavy Slam/Heat Crash formulas
(`BattleManager._low_kick_power`/`_heat_crash_power`) read
`species.weight` directly off the static species Resource, and there is
no mutable per-instance weight field on `BattlePokemon` at all; adding
one would mean editing those two already-shipped, already-tested
formulas' call sites, out of scope for this bundle. Fury Cutter's power
escalates per consecutive successful use (base 40 at this project's
`B_UPDATED_MOVE_DATA>=GEN_6` config, doubling per use, clamped at 160
total), but a real, non-obvious nuance was confirmed at Step 0: the
counter itself caps at 5, and source's own increment condition
(`SetSameMoveTurnValues`, case `EFFECT_FURY_CUTTER`,
`battle_move_resolution.c` L4893-4897) is `if (increment && counter < 5)
counter++; else counter = 0` — the counter does NOT plateau once
capped; the very next SUCCESSFUL use after reaching 5 WRAPS back to 0
(back to base power), confirmed via a dedicated 7-use full-battle test
reading the counter at each `move_executed` (0,1,2,3,4,5,0 — the wrap
happening after the 6th use, confirmed explicitly by observing the 7th
use read 0 again rather than assuming it).

A real, pre-existing PRODUCTION bug was found and fixed mid-session, not
merely a test bug: Charge's own power-doubling consumption
(`attacker.charged = false` on a later Electric-type move) was originally
implemented as an unconditional per-action check positioned BEFORE the
`if move.power > 0:` branch even splits — but `DamageCalculator.calculate`
reads `attacker.charged` to decide the power double DURING that same
later branch's own damage computation, meaning the flag would have been
cleared before the very move that's supposed to consume it ever got to
read it, silently robbing that move of its own boost. Caught by this
bundle's own I.05 test (which initially read `atk3.charged` from the
WRONG snapshot point too — see the test-authoring bugs below). Fixed by
moving the clear to the shared post-dispatch tail (alongside the Steel
Beam/Fury Cutter post-hit code), which runs only AFTER `_do_damaging_hit`
has already consumed the flag for that action.

New signals: `field_sport_set`(sport_name) for Mud Sport/Water Sport;
`types_changed`(mon, new_types, reason) — a general-purpose replacement
for the single-int `type_changed` signal's inability to carry a dual-type
array, used by both Reflect Type (`"reflect_type"`) and Roost
(`"roost"`/`"roost_restore"`); `charge_set`(mon); `laser_focus_set`(mon).
New `BattlePokemon` fields: `roost_active`/`roost_pre_types`, `charged`,
`laser_focus_turns`, `fury_cutter_counter` — all cleared in
`_clear_volatiles` like every other switch-scoped volatile. New
`BattleManager._mud_sport_turns`/`_water_sport_turns` (field-wide, not
per-mon). New `BattleManager._set_mon_type_array`,
`_apply_max_hp_50_recoil`, `_invert_stat_stages`, `_fury_cutter_power`
(static). New `DamageCalculator._weather_ball_type` (static); `calculate`
gained trailing `mud_sport_active`/`water_sport_active` bool params (both
additive, no breaking changes) and a `laser_focus_guaranteed` pre-check
alongside the existing `merciless_guaranteed` one.

New `d4_bundle5_test.gd`/`.tscn`: 85/85 assertions, stable across 5
reruns after fixing 8 real test-authoring bugs on the first run
(75/85) — (1) a dual-type-mon construction bug: reassigning
`mon.species.types` directly AFTER `_make_mon`/`from_species` construction
does NOT stick, since every switch-in site calls `_reset_mon_type`, which
restores `species.types` from `original_types` (captured ONCE at
construction time, BEFORE the post-hoc reassignment) — fixed with a new
`_make_dual_type_mon` helper building the dual-type species BEFORE
`from_species` is called, so both fields agree from the start; (2) the
Conversion/Protean/Multitype regression tests originally expected a
length-1 mono-type result, not accounting for `_set_mon_type`'s own
established `[TYPE_X, TYPE_NONE]` padding convention; (3) a fresh
whole-battle-aggregation recurrence in the Steel-Beam-Magic-Guard and
Chloroblast-Rock-Head tests — both moves have only 5 PP, so once
exhausted the mon falls back to Struggle, whose OWN recoil is
unconditional (not ability-gated, per this project's established
`blocks_recoil` precedent) — a plain "did recoil ever fire" boolean
incorrectly caught Struggle's later, unrelated recoil; fixed via a
move-count guard scoping the check to strictly the first use; (4) the
SAME whole-battle-aggregation shape in the Topsy-Turvy inversion tests —
the mon's only move keeps re-inverting the same stages every turn once
queued actions drain, making a post-battle stage read depend purely on
whether an even or odd number of turns elapsed; fixed via a first-use
signal-snapshot guard; (5) a speed-tie bug in the Strength Sap tests
(both mons defaulted to the same base_spd=60, risking the defender's
Tackle resolving first against the attacker's deliberately-low 1 HP and
fainting it before it ever acted) — fixed by making the attacker
strictly faster; (6) the Charge-persistence test (I.05) had the SAME
"snapshot before the real update lands" ordering issue as the production
bug above — `move_executed` fires inside `_do_damaging_hit`, before the
post-dispatch clear runs — fixed by snapshotting at the NEXT
`move_executed` event of any kind (the defender's own reply) rather than
synchronously at the tested move's own event; (7) the Fury-Cutter
different-move-reset test similarly read state post-battle instead of
snapshotting right after the one relevant action, since the mon's
moveset auto-repeats Fury Cutter from slot 0 once the single queued
action drains.

Regression: the required suites plus a full 109-file sweep (this
session's changes touch `DamageCalculator.calculate`'s signature,
`AbilityManager.effective_move_type`, and several shared
`BattleManager` dispatch chokepoints), run twice from independent
process states via `scripts/count_assertions.sh` — **11492 total
assertions, 0 failures, identical GRAND TOTAL both runs**. Special
attention paid to `m19_pre1_test.tscn` (the Low Kick/Grass Knot/Heavy
Slam/Heat Crash/Return/Frustration suite) given Autotomize's own
scope-limitation claim about not touching those formulas — confirmed
unchanged at 48/48.

**Total move-implementation count: 664→677.** Section D's residual:
55→42. Reconciliation: 677 implemented + 42 D4 residual + 215 excluded =
934, confirmed by direct addition.

#### D4 Bundle 6 — CLOSED, COMPLETE (`[D4 Bundle 6]`, 2026-07-14)

23 more moves shipped — all 23 of the REUSE-LIKELY residual moves flagged
by the recon session immediately preceding this one, self-selected by the
assistant and confirmed by Rob before Step 0: Teleport(100), Rest(156),
False Swipe(206), Present(217), Knock Off(282), Endeavor(283), Brine(362),
Acupressure(367), Psycho Shift(375), Punishment(386), Telekinesis(477),
Acrobatics(512), Bulldoze(523), Belch(562), Parting Shot(575), Venom
Drench(599), Geomancy(601), Toxic Thread(635), Stuff Cheeks(693), No
Retreat(694), Octolock(699), Poltergeist(737), Chilly Reception(807).

Step 0 was run fresh against source for all 23 rather than trusting the
recon's own infra-reuse claims, per the task's own explicit instruction —
8 real forks were found and confirmed load-bearing (full citations in
`docs/decisions.md`'s own `[D4 Bundle 6]` entry):

- **Octolock does NOT actually trap** in this reference source —
  `CanBattlerEscape` (the function behind `AbilityManager.is_trapped`)
  never checks the Octolock volatile at all, despite the move's own
  flavor text. Implemented faithfully: `octolocked_by` drives ONLY the
  recurring -1 Def/-1 Sp. Def end-of-turn tick, deliberately NOT wired
  into `is_trapped`.
- **No Retreat's self-trap needed its OWN dedicated bool**
  (`no_retreat_active`), not a reuse of `escape_prevented_by` — that
  field's reciprocal-clear-when-the-source-leaves-the-field rule (correct
  for Mean Look) would incorrectly free a No-Retreat user if a LATER
  opponent's Mean Look overwrote the same reference and that opponent
  subsequently left the field.
- **Telekinesis is two independent halves**: ungrounding (a clean peer
  addition to `AbilityManager.is_grounded`'s existing tier, subordinate to
  Iron Ball/Ingrain/Smack Down) AND a separate guaranteed-hit mechanic
  (any move against the target auto-hits except OHKO moves and except
  while semi-invulnerable) — inserted into `StatusManager.check_accuracy`
  AFTER the semi-invulnerable gate, the opposite ordering from Lock-On.
- **Parting Shot's switch is GATED ON the stat-lower landing** (this
  project's GEN_LATEST/Gen7+ config) — the OPPOSITE of Memento's
  independence finding. A fully stat-capped target blocks both the
  stat-lower AND the switch.
- **Chilly Reception's switch is UNCONDITIONAL** regardless of the
  weather-set's own success — the opposite gating from Parting Shot,
  despite both being "effect then switch" moves.
- **Toxic Thread/Venom Drench both needed a type-immunity-gate
  exemption**: their shared `BattleScript_EffectStatChange` never calls
  `typecalc` in source (confirmed via `toxic_thread.c`'s own test suite:
  "Toxic Thread still lowers Speed if the target can't be Poisoned [a
  Steel-type]") — the same class of bug `[D2 batch 2]`'s Foresight finding
  first surfaced. FLAGGED, NOT FIXED: this same generic script backs every
  other already-shipped plain stat-change foe-targeting move in this
  project's roster (Growl/Leer/etc.), which may share this exact gap
  against an immune-type target — auditing the full existing roster is
  out of scope for this bundle.
- **Knock Off's power boost and item removal share one gate**
  (`AbilityManager.can_remove_item`, reusing `[M17j]`'s Sticky Hold check
  and `[Multitype-Plate fix]`'s `is_form_locked_by_item` minus the
  transfer-to-attacker step) — confirmed via a real test-authoring
  correction (below) that this project's `_consume_item` chokepoint must
  NOT be reused for the removal itself, since Knock Off never triggers
  Cheek Pouch or `last_consumed_berry` (the item is knocked away, not
  eaten) — Unburden and Symbiosis were replicated directly instead.
- **Present is a flat 0-255 uniform roll** (102/76/26/51 bands →
  40/80/120/heal), confirmed NOT Magnitude's weighted-table shape — the
  heal branch bypasses the whole damaging dispatch entirely (heals the
  TARGET max_hp/4, type effectiveness never computed, fails at full HP).

Geomancy and Bulldoze both needed ZERO new dispatch code — Geomancy
reuses the existing `two_turn` charge/release infra plus the generic
multi-stat `stat_change_stat`/`extra_stat_change_stats` mechanism
(`[Bucket 3 multi-stat]`); Bulldoze reuses `is_spread` plus the generic
guaranteed-secondary-stat-change dispatch (`[M19-secondary-stat-on-hit]`)
verbatim, confirmed via its own explicit `.chance = 100` (not the
guaranteed/omitted-chance shape) — pure data entries for both. Rest's
own 3-way fail chain (already asleep/Comatose, already full HP, blocked
by the user's own Insomnia/Vital Spirit/Purifying Salt) is checked
BEFORE any heal or status-clear happens, matching source exactly. Stuff
Cheeks reuses `ItemManager.steal_and_eat_berry_effect` (built for Pluck/
Bug Bite) self-targeted, confirming that function's own multi-family
dispatch generalizes cleanly to a second caller with zero changes.

New `BattlePokemon` fields: `telekinesis_turns`, `no_retreat_active`,
`octolocked_by` (all cleared/reciprocal-cleared via `_clear_volatiles`,
matching the established `wrapped_by`/`infatuated_by`/`escape_prevented_by`/
`leeched_by` pattern). New `AbilityManager.can_remove_item`. New
`DamageCalculator` bypass branch for Endeavor (same shape as
`percent_current_hp_damage`). New `_force_present_roll` test seam.

New `d4_bundle6_test.gd`/`.tscn`: 90/90 assertions, stable across 5
reruns after fixing 11 real test-authoring bugs on the first run (72/90)
— by far the largest count of test-only bugs in a single D4 bundle so
far, nearly all fresh recurrences of CLAUDE.md's own documented
pitfalls: (1) SEVEN instances of the whole-battle-aggregation trap
(Rest's heal amount, False Swipe's HP floor, Endeavor's HP-set,
Telekinesis's turn count, Parting Shot's/Venom Drench's/Geomancy's/No
Retreat's stat-change counts, Stuff Cheeks' heal amount — all fixed via
first-occurrence signal-snapshot guards rather than post-battle state
reads); (2) THREE instances of raw `DamageCalculator.calculate()` calls
bypassing `_dmg_power_override` entirely for Brine/Punishment/Acrobatics
(that computation lives in `BattleManager`, not `DamageCalculator` —
rewritten as full-battle comparisons); (3) a genuine confound caught in
the Punishment rewrite — boosting the TARGET's own Defense/Sp. Defense
to test Punishment's power scaling directly fights the damage formula's
own defense term, nearly canceling the power increase by coincidence
(fixed by boosting Speed/Accuracy instead, neither of which affects
physical damage); (4) a second confound in the Acrobatics/Knock-Off
rewrites — Choice Band (used in an earlier draft as a "holds an item"
test item) ALSO boosts Attack by 50% on its own, masking the comparison
(fixed with a mechanically-inert `HOLD_EFFECT_NONE` item); (5) a THIRD
confound, the same "berry gets eaten mid-battle via the unrelated
HP-threshold pathway" trap `[D4 CHEAP bundle]` already flagged, recurring
in the Knock-Off-vs-Sticky-Hold discriminator (fixed with a non-berry
Choice-Band item there instead); (6) a fresh instance of CLAUDE.md's own
"type immunity precedes ability logic" pitfall — Poltergeist (Ghost-type)
tested against the default Normal-type defender, a flat 0x immunity
unrelated to the item-check logic (fixed with a Water-type defender);
(7) No Retreat's own expected stat count was simply wrong in the test
(6, when the move only touches 5 stats — Atk/Def/SpAtk/SpDef/Speed, NOT
Accuracy/Evasion, confirmed via direct data read) — a test-bug, not an
implementation bug; (8) the Octolock direct-`_phase_end_of_turn()` unit
test originally overwrote `_side_conditions` with empty dicts, crashing on
an already-templated key read (`reflect_turns`) — fixed by leaving
`_side_conditions` at its own properly-initialized default. Every one of
these was independently confirmed via direct debug tracing to be a test
bug, not a production bug, before being fixed — no move's underlying
dispatch code was changed as a result of any of the 11.

Regression: the required 4 suites plus a full 110-file sweep (this
session touches `AbilityManager.is_grounded`/`is_trapped`,
`StatusManager.check_accuracy`, `DamageCalculator.calculate`, and
`_clear_volatiles` — all central chokepoints), run twice from independent
process states via `scripts/count_assertions.sh` — **11582 total
assertions, 0 failures, identical GRAND TOTAL both runs**. Special
attention paid to `m19_pre1_test.tscn` (Low Kick/Grass Knot/Heavy
Slam/Heat Crash/Return/Frustration) and `switch_test.tscn`, both rerun 3x
independently — confirmed unchanged at 48/48 and 64/64.

**Total move-implementation count: 677→700.** Section D's residual:
42→19. Reconciliation: 700 implemented + 19 D4 residual + 215 excluded =
934, confirmed by direct addition.

### D5 — Recommended next steps out of Section D

1. **`M19-blocked-on-other-tier4`'s unblock (D0, 4 moves: Leech
   Seed/Haze/Aromatherapy+Heal Bell) — CLOSED, COMPLETE (`[D0]`,
   2026-07-09).** Shipped alongside 2 free pairs (Follow Me/Rage
   Powder, Soft-Boiled/Milk Drink) and the 3 moves it directly unblocked
   (Sappy Seed/Freezy Frost/Sparkly Swirl) — 11 moves total. Bucket 4 was
   down to just `M19-secret-power` (deferred by Rob) at this point — since
   permanently excluded, 2026-07-10, closing Bucket 4 entirely.
2. **D1's remaining cheapest clusters as a bundled session — CLOSED,
   COMPLETE (`[D1 cheap clusters]`, 2026-07-09).** All 8 strictly-CHEAP
   clusters (`EFFECT_WEATHER`/`EFFECT_POWER_BASED_ON_USER_HP`/
   `EFFECT_POWER_BASED_ON_TARGET_HP`/`EFFECT_STEAL_ITEM`/`EFFECT_LOCK_ON`/
   `EFFECT_SWAGGER`/`EFFECT_SUCKER_PUNCH`/`EFFECT_STORED_POWER`, 21 moves
   — a real correction to this item's own "~15" estimate, which had
   silently dropped the 2 HP-based-power clusters) shipped in one bundled
   session, matching the `[Bucket 4 cheapest singles]`/`[Bucket 4 2-move
   sub-groups]` bundling precedent. D1's remaining pool (24 moves/10
   clusters) is now entirely CHEAP-MODERATE or harder — see D1's own
   table for the current candidates (`EFFECT_HIT_ESCAPE`/
   `EFFECT_HIT_SWITCH_TARGET`/`EFFECT_TRICK` are flagged there as
   touching switch-handling/item-swap code more sensitively than this
   tier's own clusters did).
3. **D2's "already-shipped-mechanism reuse" families**: on-hit hazard/
   screen set-or-clear (6 moves) and ability-manipulation (4 moves) are
   BOTH CLOSED, COMPLETE (`[D2 batch]`, 2026-07-09) — see their own
   entries above for the full findings, including two real corrections
   (Ice Spinner does NOT clear hazards — it removes Terrain, permanently
   moot here; Tidy Up/Defog are both broader than originally framed).
   **Damage/defense-stat-source-override family (3 moves: Foul Play/Body
   Press/Photon Geyser) and per-mon TypeChart-override family (4 moves:
   Freeze-Dry/Tar Shot/Foresight/Odor Sleuth) are now ALSO CLOSED,
   COMPLETE (`[D2 batch 2]`, 2026-07-10)** — see their own entries above
   for the full findings, including a real correction (`EFFECT_PSYSHOCK`
   was NOT already built, contrary to this bullet's own prior framing —
   remains a genuinely open D1 cluster), a confirmed hidden second effect
   (Photon Geyser's real category swap), and a real bug found and fixed
   (Foresight's own type-immunity-gate exemption). D2's
   turn-order-manipulation family (4 moves: After You/Quash/Upper
   Hand/Instruct) and "stat/event happened this turn" tracker family
   (4 moves: Lash Out/Retaliate/Rage Fist/Echoed Voice) are now ALSO
   CLOSED, COMPLETE (`[D3 turn-order/event-tracker batch]`,
   2026-07-10)** — see their own entries above for the full findings,
   including Instruct's genuinely new attacker-reassignment fall-
   through shape and Retaliate's empirically-confirmed END_OF_TURN-
   skipped-on-faint timing nuance. D2's only remaining cross-cutting
   family is now delayed-effect (6 moves) — see item 4 below.
4. **The delayed-effect family (D2, 6 moves) — CLOSED, COMPLETE
   (Delayed-effect family session, 2026-07-10).** Future Sight(248)/Doom
   Desire(353)/Wish(273)/Yawn(281)/Healing Wish(361)/Lunar Dance(461) all
   shipped in one session. **A real correction to this item's own "one
   shared new mechanism" framing**: it's genuinely THREE mechanism
   shapes, not one — (a) a per-slot delayed scheduler (Future Sight/Doom
   Desire, Wish) living in new `BattleManager` dictionaries keyed by
   combatant index, resolving against whoever occupies that SLOT when a
   counter expires (not the original target's identity — a switch
   survives); (b) a per-mon volatile counter (Yawn) that turned out to be
   ZERO new infrastructure — mechanically identical to the already-shipped
   `disable_turns`/`encore_turns`/`throat_chop_turns` pattern, already
   correctly cleared by the existing switch-out plumbing; (c) a switch-in-
   triggered one-shot flag (Healing Wish/Lunar Dance) consumed by the
   slot's very next switch-in via any method, requiring a new
   `has_valid_switch_target()`-gated fail condition Explosion/Self-
   Destruct doesn't have. Future Sight/Doom Desire resolve through the
   EXISTING `_do_damaging_hit` chokepoint (screens/Substitute/Sturdy-
   chain/times_hit/Air Balloon all apply for free) rather than a bespoke
   damage path; the cast-time-vs-resolve-time snapshot question resolved
   to "always resolve-time, never cast-time" (confirmed from source), with
   a disclosed simplification for a switched-out caster (this project
   reuses the existing switch-out stat-stage reset for free but doesn't
   additionally null a benched caster's ability/item the way source's own
   struct-swap does). Healing Wish/Lunar Dance's Gen8+ "persist until
   beneficial" nuance was confirmed with Rob and simplified to always-
   consume-next-switch-in. New `delayed_effect_test.gd`/`.tscn`: 41/41
   assertions across 6 sections, stable across 5 reruns after fixing 2
   real test-authoring bugs (a heal-amount assertion that didn't account
   for the missing-HP cap; a whole-battle-aggregation instance where an
   unrelated later faint was misread as the move's own self-faint). This
   closes out D2 entirely — no remaining cross-cutting families.
5. **Perish Song(195)** is worth flagging to Rob specifically: building it
   re-opens the currently-excluded Perish Body ability for reconsideration
   — a cross-system dependency this session surfaced, not previously
   documented anywhere. Perish Song itself remains unbuilt and still
   carries this note forward, unaffected by this session's Delayed-effect-
   family work — a different mechanism (multi-battler delayed-faint
   countdown, not a per-slot scheduler or switch-in one-shot).
6. **Transform/Sky Drop/Beak Blast/Shell Trap** (the 4 HARD singletons)
   and **Camouflage** (BLOCKED) are reasonable candidates to defer
   indefinitely or exclude, matching this arc's own precedent for
   Secret Power/Population Bomb — genuinely higher complexity or
   structurally blocked, not just under-scoped.

This section is now a real sub-tier starting point, not a placeholder —
future sessions should pick concrete clusters/families off D0-D2 the same
way sessions have been picking sub-groups off Bucket 4, rather than
re-deriving this breakdown from scratch.

---

## Section E — Summary and recommended sequencing

| Bucket | Move count |
|---|---|
| Already implemented (excluded from this plan) — includes Heal Order/Dragon Darts (resolved conflicts); `M19-secondary-stat-on-hit` (79) shipped `[M19-secondary-stat-on-hit]` 2026-07-09; Bucket 3 in its entirety (30) shipped across `[Bucket 3 multi-stat]` + `[Bucket 3 clusters 1-2]`, both 2026-07-09; 7 of Bucket 4's single-move sub-groups shipped `[Bucket 4 cheapest singles]` 2026-07-09; `M19-rampage` (5) shipped `[M19-rampage]` 2026-07-09; `M19-recharge` (10) shipped `[M19-recharge]` 2026-07-09; `M19-break-protect` (4) shipped `[M19-break-protect]` 2026-07-09; `M19-recoil-on-miss` (4) shipped `[M19-recoil-on-miss]` 2026-07-09; `M19-weather-conditional-accuracy` (5) shipped `[M19-weather-conditional-accuracy]` 2026-07-09; 9 more 2-move sub-groups (19) shipped `[Bucket 4 2-move sub-groups]` 2026-07-09; `M19-steal-stats` (1) + `M19-ally-targeting-stat-change` (3) shipped `[M19-steal-stats]`/`[M19-ally-targeting-stat-change]` 2026-07-09; M19e (4) + M19f (5, incl. Spirit Shackle/`M19-trap-secondary`) shipped `[M19e]`/`[M19f]` 2026-07-09; M19c (7) + M19d (2) shipped `[M19c]`/`[M19d]` 2026-07-09; D0's 11 moves (Leech Seed/Haze/Aromatherapy/Heal Bell/Follow Me/Rage Powder/Soft-Boiled/Milk Drink/Sappy Seed/Freezy Frost/Sparkly Swirl) shipped `[D0]` 2026-07-09; D1's 4 moves (Solar Blade/Snipe Shot/Hidden Power/Hyperspace Fury) shipped `[D1]` 2026-07-09; D1 cheap clusters' 21 moves (Sandstorm/Rain Dance/Sunny Day/Hail/Snowscape, Eruption/Water Spout/Dragon Energy, Wring Out/Crush Grip/Hard Press, Thief/Covet, Mind Reader/Lock-On, Swagger/Flatter, Sucker Punch/Thunderclap, Stored Power/Power Trip) shipped `[D1 cheap clusters]` 2026-07-09; D2's on-hit hazard/screen family (6: Stone Axe/Ceaseless Edge/Ice Spinner/Mortal Spin/Tidy Up/Defog) + ability-manipulation family (4: Role Play/Skill Swap/Worry Seed/Heart Swap) shipped `[D2 batch]` 2026-07-09; D1's `EFFECT_FORESIGHT` cluster (2: Foresight/Odor Sleuth) + D2's offense-stat-source-override family (3: Foul Play/Body Press/Photon Geyser) + per-mon TypeChart-override family (2: Freeze-Dry/Tar Shot) shipped `[D2 batch 2]` 2026-07-10; D2's turn-order-manipulation family (4: After You/Quash/Upper Hand/Instruct) + "stat/event happened this turn" tracker family (4: Lash Out/Retaliate/Rage Fist/Echoed Voice) shipped `[D3 turn-order/event-tracker batch]` 2026-07-10; D2's delayed-effect family (6: Future Sight/Doom Desire/Wish/Yawn/Healing Wish/Lunar Dance) + D1's `EFFECT_PSYSHOCK` cluster (2: Psyshock/Psystrike) shipped in the Delayed-effect-family session 2026-07-10; D1's remaining 6 easy clusters (13: U-turn/Volt Switch/Flip Turn, Circle Throw/Dragon Tail, Fake Out/First Impression, Trick/Switcheroo, Revenge/Avalanche, Stomping Tantrum/Temper Flare) shipped in the D1 easy bundle session 2026-07-10; D1's LAST cluster (5: Smelling Salts/Venoshock/Hex/Barb Barrage/Infernal Parade, `EFFECT_DOUBLE_POWER_ON_ARG_STATUS`) shipped 2026-07-10, closing D1 entirely; D4 bundle (6: Struggle/Helping Hand/Sleep Talk/Taunt/Assurance/Magic Coat) shipped `[D4 bundle]` 2026-07-10; D4 CHEAP bundle (12: Dream Eater/Torment/Gyro Ball/Electro Ball/Snore/Endure/Fell Stinger/Magnet Rise/Smack Down/Ingrain/Aqua Ring/Payback) shipped `[D4 CHEAP bundle]` 2026-07-10; D4 bundle 3 (12: Splash/Refresh/Purify/Memento/Belly Drum/Fillet Away/Clangorous Soul/Nightmare/Spite/Recycle/Facade/Take Heart) shipped `[D4 bundle 3]` 2026-07-10; D4 Bundle 4 (12: Tailwind/Sticky Web/Safeguard/Mist/Copycat/Me First/Assist/Heal Pulse/Life Dew/Stockpile/Spit Up/Swallow) shipped `[D4 Bundle 4]` 2026-07-13; D4 Bundle 5 (13: Mud Sport/Water Sport/Weather Ball/Reflect Type/Roost/Strength Sap/Steel Beam/Chloroblast/Charge/Laser Focus/Topsy-Turvy/Autotomize/Fury Cutter) shipped `[D4 Bundle 5]` 2026-07-14; D4 Bundle 6 (23: Teleport/Rest/False Swipe/Present/Knock Off/Endeavor/Brine/Acupressure/Psycho Shift/Punishment/Telekinesis/Acrobatics/Bulldoze/Belch/Parting Shot/Venom Drench/Geomancy/Toxic Thread/Stuff Cheeks/No Retreat/Octolock/Poltergeist/Chilly Reception) shipped `[D4 Bundle 6]` 2026-07-14; D4 Bundle 7 (7: Curse/Focus Punch/Grudge/Last Resort/Pollen Puff/Beak Blast/Shell Trap — the LAST of D4's own REUSE-LIKELY moves) shipped `[D4 Bundle 7]` 2026-07-14; D4 Bundle 8 (4: Round/Snatch/Imprison/Grav Apple — reinstated from `[Exclusion bookkeeping]`'s reversal, see `[Reversal: Round/Snatch/Imprison/Grav Apple]` in decisions.md) shipped `[D4 Bundle 8]` 2026-07-14; D4 Bundle 9 (2: Flying Press/Sky Drop — the LAST 2 of D4's own NOVEL-MECHANISM moves) shipped `[D4 Bundle 9]` 2026-07-14; Mimic/Sketch (2: the last 2 of D4's remaining NOVEL-MECHANISM moves cheap enough to bundle together — Transform gets its own dedicated session, per the recon's recommendation — shipped alongside a standalone `[Ability-reset fix]` bugfix to already-shipped M17h/D2-batch code, same session) shipped `[Mimic/Sketch]` 2026-07-14 | 715 |
| Proposed sub-tiers (Section B: Bucket 4 is now fully closed — `M19-secret-power` PERMANENTLY EXCLUDED by Rob 2026-07-10, moved below; `M19-blocked-on-other-tier4` CLOSED by `[D0]`) | 0 |
| Deferred (Section C3 — Population Bomb PERMANENTLY EXCLUDED by Rob 2026-07-10, moved below; C4 closed) | 0 |
| Permanently excluded, confirmed by Rob (Section C1 Z-Move/Max-Move + Section C2 `[M19-exclusions]`, incl. Raging Bull + Psychic Noise addenda + the 2-move exclusion-bookkeeping addendum 2026-07-14 [Nature Power/Camouflage — genuine `gBattleEnvironment` capability gap; the SAME date's own Round/Snatch/Imprison/Grav Apple exclusion was REVERSED by Rob later the same day — see `[Reversal: Round/Snatch/Imprison/Grav Apple]` in decisions.md]; + Secret Power(290)/`M19-secret-power` + Population Bomb(788), both confirmed excluded 2026-07-10) | 217 |
| Tier 4 residual, mechanism-clustered (Section D, `[M19-section-d-cluster]` 2026-07-09) — D0's 8 moves shipped `[D0]` 2026-07-09; D1's 4 D4 singletons (Solar Blade/Snipe Shot/Hidden Power/Hyperspace Fury) shipped `[D1]` 2026-07-09; D1's 8 remaining CHEAP clusters (21 moves) shipped `[D1 cheap clusters]` 2026-07-09; D2's on-hit hazard/screen + ability-manipulation families (10 moves) shipped `[D2 batch]` 2026-07-09; D1's `EFFECT_FORESIGHT` cluster + D2's offense-stat-source-override and per-mon TypeChart-override families (7 moves) shipped `[D2 batch 2]` 2026-07-10; D2's turn-order-manipulation + "stat/event happened this turn" tracker families (8 moves) shipped `[D3 turn-order/event-tracker batch]` 2026-07-10; D2's delayed-effect family + D1's `EFFECT_PSYSHOCK` cluster (8 moves) shipped 2026-07-10; D1's remaining 6 easy clusters (13 moves) shipped 2026-07-10; D1's LAST cluster (5 moves, `EFFECT_DOUBLE_POWER_ON_ARG_STATUS`) shipped 2026-07-10; D4's own recon re-derivation (`[D4 bundle]` — 2 FREE/62 CHEAP/27 MODERATE/4 HARD/2 BLOCKED after the Nature Power correction) shipped 6 of the pool's moves 2026-07-10; `[D4 CHEAP bundle]` shipped 12 more 2026-07-10 (Snore(173) surfaced as a genuine prose-completeness gap in this pool's own itemization — see that entry); `[D4 bundle 3]` shipped 12 more 2026-07-10; `[D4 Bundle 4]` shipped 12 more 2026-07-13 (side-condition timers/call-a-different-move family/target-heal variants/Stockpile family); `[D4 Bundle 5]` shipped 13 more 2026-07-14 (field-wide damage reducers/type-mutation family/heal-and-drain family/HP-cost-attached-to-damage family/persistent-flag family/stat-array manipulation/escalating power); `[D4 Bundle 6]` shipped 23 more 2026-07-14 (all 23 REUSE-LIKELY residual moves from the preceding recon); 6 more moves permanently excluded 2026-07-14 (exclusion bookkeeping); `[D4 Bundle 7]` shipped the LAST 7 REUSE-LIKELY moves 2026-07-14, leaving only 6 confirmed NOVEL-MECHANISM moves (Mimic/Transform/Sketch/Perish Song/Sky Drop/Flying Press) — no REUSE-LIKELY moves remain anywhere in M19; `[D4 Bundle 9]` then shipped Flying Press/Sky Drop (down to 4: Mimic/Transform/Sketch/Perish Song); `[Mimic/Sketch]` shipped Mimic/Sketch 2026-07-14 | 2 |
| **Total (matches the recon's 934-move catalog)** | **934** |

715 + 0 + 0 + 217 + 2 = 934, confirmed by direct addition. Zero
outstanding discrepancy. **D1 and D2 are now both fully closed, and Bucket
4/Section C3 are now both fully closed too** (Secret Power and Population
Bomb both moved from pending/deferred into permanently excluded, per Rob's
explicit 2026-07-10 decision). Every cluster/family surfaced during the
singleton-pool sweep (`[M19-section-d-cluster]`) has shipped or been
excluded — **Section D's remaining singleton pool (D4, now 2 moves after
`[D4 Bundle 7]` shipped the last of the REUSE-LIKELY moves,
`[D4 Bundle 9]` shipped Flying Press/Sky Drop, and `[Mimic/Sketch]`
shipped Mimic/Sketch) is the ONLY open scope left in all of M19, and the
2 remaining moves (Transform/Perish Song) are both confirmed
NOVEL-MECHANISM builds, not further bulk data-entry — Transform in
particular is recommended to get its own dedicated session given its real
architectural scope (a full species/stat/type/ability/moveset clone),
per the Step 0 recon that covered all 4 of these moves together.**

| Sub-tier | Moves | Risk | Depends on |
|---|---|---|---|
| Bucket 1 — pure damage, no additional effect | **COMPLETE** (`[M19-bucket1]`, 61 implemented + 6 moved to Bucket 4) | — | — |
| Bucket 2 — single existing secondary mechanism | **COMPLETE** (`[M19-bucket2]`, 135 implemented + 111 reclassified — 15 to Bucket 3, 96 to Bucket 4) | — | — |
| Bucket 3 — existing mechanisms, needs scrutiny | **COMPLETE** (30/30 — 24 multi-stat `[Bucket 3 multi-stat]` + 3 combined-secondary + 2 screen+damage `[Bucket 3 clusters 1-2]` + 1 (Coaching) moved to Bucket 4) | — | — |
| Bucket 4 — genuinely new mechanism | **COMPLETE/CLOSED** — 0 moves remaining (`M19-secret-power` PERMANENTLY EXCLUDED by Rob, 2026-07-10) | — | see Section B's own per-sub-group notes; `M19-secondary-stat-on-hit` (79 moves) is **COMPLETE** (`[M19-secondary-stat-on-hit]`, 2026-07-09); 7 single-move sub-groups (Rage/Clear Smog/Incinerate/Sparkling Aria/Throat Chop/Eerie Spell/Blood Moon) are **COMPLETE** (`[Bucket 4 cheapest singles]`, 2026-07-09); `M19-rampage` (5 moves, Uproar merged in) is **COMPLETE** (`[M19-rampage]`, 2026-07-09); `M19-recharge` (10 moves) is **COMPLETE** (`[M19-recharge]`, 2026-07-09); `M19-break-protect` (4 moves) is **COMPLETE** (`[M19-break-protect]`, 2026-07-09); `M19-recoil-on-miss` (4 moves) is **COMPLETE** (`[M19-recoil-on-miss]`, 2026-07-09); `M19-weather-conditional-accuracy` (5 moves) is **COMPLETE** (`[M19-weather-conditional-accuracy]`, 2026-07-09); 9 more 2-move sub-groups (19 moves) are **COMPLETE** (`[Bucket 4 2-move sub-groups]`, 2026-07-09); `M19-steal-stats` (1 move) and `M19-ally-targeting-stat-change` (3 moves) are **COMPLETE** (`[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`, 2026-07-09); `M19-trap-secondary` (1 move, Spirit Shackle) is **COMPLETE**, folded into M19f (`[M19e]`/`[M19f]`, 2026-07-09); `M19-blocked-on-other-tier4` (3 moves, Sappy Seed/Freezy Frost/Sparkly Swirl) is **COMPLETE** (`[D0]`, 2026-07-09); `M19-secret-power` (1 move, Secret Power(290)) is **PERMANENTLY EXCLUDED by Rob**, 2026-07-10 |
| M19c — Protect-family variants | **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09) | — | — |
| M19d — Counter/Mirror-Move remnants | **COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09) | — | — |
| M19e — Weather-conditional heal family | **COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09) | — | — |
| M19f — Escape-prevention family (Spider Web/Mean Look/Block/Jaw Lock + Bucket 4's Spirit Shackle merged in, 5 moves total) | **COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09) | — | — |
| M19g — DISSOLVED, all 3 moves permanently excluded | 0 | — | — |
| M19h — Weight-ratio dynamic power | **COMPLETE** (`[M19-pre1]`, confirmed `[M19-rescope-followup]`) | — | — |
| M19i — Friendship-based dynamic power | **COMPLETE** (`[M19-pre1]`, confirmed `[M19-rescope-followup]`) | — | — |
| Tier 4 sub-clustering pass | 2 (was 181 — D0/D1/D1-cheap-clusters/D2/D2-batch-2/D3/delayed-effect-family/D1-easy-bundle/D1's-last-cluster fully shipped, all sessions 2026-07-09/2026-07-10; D4's own recon re-derivation then shipped 89 of its 97 moves across `[D4 bundle]` (6) + `[D4 CHEAP bundle]` (12) + `[D4 bundle 3]` (12) + `[D4 Bundle 4]` (12) + `[D4 Bundle 5]` (13) + `[D4 Bundle 6]` (23) + `[D4 Bundle 7]` (7) + `[D4 Bundle 9]` (2: Flying Press/Sky Drop) + `[Mimic/Sketch]` (2: Mimic/Sketch); 6 more permanently excluded 2026-07-14 — Round/Snatch/Imprison/Grav Apple/Nature Power/Camouflage) | D1 and D2 are now FULLY CLOSED. Remaining: D4's singleton pool, 2 moves, ALL NOVEL-MECHANISM (Transform/Perish Song) — no REUSE-LIKELY moves remain | D0/D1/D1-cheap-clusters/D2-batch-1+2/D3/delayed-effect-family/D1-easy-bundle/D1's-last-cluster are all CLOSED — D4's own remaining pool (2 moves, both requiring a genuinely new mechanism, Transform recommended for its own dedicated session) is the only open Section D scope |

**M19c-i is now FULLY CLOSED** — every sub-tier proposed in Section B (M19c
through M19i) has shipped. **`[D0]` update (2026-07-09): Bucket 4's
`M19-blocked-on-other-tier4` gate is now CLOSED too** — the only
remaining M19 scope is Bucket 4's single deferred move
(`M19-secret-power`, Section B above) and Section D's residual. **`[D1]`
update (2026-07-09): Section D's residual dropped to 169** (D0's own 8
moves plus D1's own 4 moves, Solar Blade/Snipe Shot/Hidden Power/
Hyperspace Fury, both shipped). **`[D1 cheap clusters]` update
(2026-07-09): Section D's residual is now 148** — all 8 strictly-CHEAP
D1 clusters (21 moves) shipped in one bundled session; D1's own
remaining pool (24 moves/10 clusters) is entirely CHEAP-MODERATE or
harder. **`[D2 batch]` update (2026-07-09): Section D's residual is now
138** — D2's on-hit hazard/screen family (6 moves) and ability-
manipulation family (4 moves) both shipped in the same session as three
flagged batch-fix items (Hail-only design decision confirmed, Primal
weather block built, Solar Beam/Blade rain/sand/hail damage-halving
built) that touched zero additional move count. **`[D2 batch 2]` update
(2026-07-10): Section D's residual is now 131** — D2's offense/defense-
stat-source-override family (Foul Play/Body Press/Photon Geyser) and
per-mon TypeChart-override family (Freeze-Dry/Tar Shot) both shipped,
plus D1's own `EFFECT_FORESIGHT` cluster (Foresight/Odor Sleuth, 7 moves
total this session — a real scope-count correction, since this bullet's
own prior "3 moves"/"3 moves" per-family framing undercounted by one:
Foresight+Odor Sleuth are 2 real move IDs, not 1). A real bug was found
and fixed along the way (Foresight's own type-immunity-gate exemption —
see that cluster's own CLOSED entry above). D2's own remaining cross-
cutting families (delayed-effect, turn-order-manipulation, "stat/event
happened this turn" tracker) are unaffected and still open — see D5.
**`[D3 turn-order/event-tracker batch]` update (2026-07-10): Section D's
residual is now 123** — D2's turn-order-manipulation family (After
You/Quash/Upper Hand/Instruct) and "stat/event happened this turn"
tracker family (Lash Out/Retaliate/Rage Fist/Echoed Voice) both shipped
in one bundled session (8 moves total), per their own CLOSED entries
above for the full findings. D2's only remaining cross-cutting family
is now the delayed-effect family (6 moves — Future Sight/Doom Desire/
Wish/Yawn/Healing Wish/Lunar Dance), still flagged as needing its own
dedicated design session before implementation — see D5.
**Delayed-effect-family session update (2026-07-10): Section D's residual
is now 115** — the delayed-effect family (6 moves) shipped alongside D1's
`EFFECT_PSYSHOCK` cluster (Psyshock/Psystrike, 2 moves, bundled for
efficiency, unrelated mechanism) in one session, closing the LAST
remaining D2 cross-cutting family — D2 is now fully closed, see the
delayed-effect family's own CLOSED entry above (D5, item 4) for the full
3-way mechanism-shape correction and findings.
**D1 easy bundle update (2026-07-10): Section D's residual is now 102** —
the 6 remaining "easy" D1 clusters (`EFFECT_HIT_ESCAPE`/
`EFFECT_HIT_SWITCH_TARGET`/`EFFECT_FIRST_TURN_ONLY`/`EFFECT_TRICK`/
`EFFECT_REVENGE`/`EFFECT_STOMPING_TANTRUM`, 13 moves) all shipped in one
bundled session, per their own CLOSED entries above. Two real bugs were
found and fixed along the way, both flagged in their own cluster rows:
(1) `switched_in_this_turn` was never set for a battle's own starting
leads (only mid-battle switch-ins), silently breaking Fake Out's
first-turn condition AND Stakeout/Speed Boost's own turn-1 reads since
those tiers shipped — fixed at the root; (2) Stomping Tantrum's own
decrement-site research revealed Retaliate's timer (`[D3 turn-order/
event-tracker batch]`) had been decrementing in the wrong phase,
under-doubling by one turn boundary after a faint — fixed to match
source's real timing.
**`EFFECT_DOUBLE_POWER_ON_ARG_STATUS` update (2026-07-10): Section D's
residual is now 97 — D1 is FULLY CLOSED.** The last remaining D1 cluster
(Smelling Salts/Venoshock/Hex/Barb Barrage/Infernal Parade, 5 moves)
shipped in its own dedicated session per that row's own table entry
above — confirmed genuinely non-uniform (3 distinct STATUS_ARG shapes,
not a copy-paste), with Smelling Salts's `MOVE_EFFECT_REMOVE_STATUS`
flag resolving into a real, narrower-than-fully-uniform composite (only
1 of the 5 moves carries it, plus a Substitute-blocks-the-double
exception this row's own flag hadn't anticipated) and a real, reachable
Comatose-as-sleep interaction confirmed and tested (Comatose already
ships, `[M17n-11]`). **Section D's only remaining scope is now D4's
singleton pool** — every named cluster/family from the original
`[M19-section-d-cluster]` sweep has shipped.
**Exclusion decision update (2026-07-10): Bucket 4 and Section C3 are both
now fully CLOSED.** Rob confirmed permanent exclusion (not further
deferral) for the two moves that had been sitting as open deferrals since
`[Bucket 4 cheapest singles]`: **Secret Power(290)** (`M19-secret-power` —
blocked on `gBattleEnvironment`, an overworld map/tile field this project
has no analog for) and **Population Bomb(788)** (Section C3 — a genuinely
higher-complexity `.strikeCount` variant with per-hit accuracy checks and
its own uniquely-shaped Loaded Dice interaction). Both moved from their
respective "pending" buckets into "Permanently excluded" in Section E's
reconciliation (213→215 excluded; "Proposed sub-tiers" and "Deferred" both
now read 0). **M19's only open scope of any kind, anywhere in the
document, is now D4's singleton pool.**

**D4 reconnaissance update (2026-07-10, docs-only, no implementation):**
D4's own singleton-pool write-up has been fully re-derived and reconciled
— see D4's own section above for the complete breakdown. The original
~130-move/~87-cheap-~35-moderate-4-hard-1-blocked first-pass estimate
(from `[M19-section-d-cluster]`, 2026-07-09) is superseded by a
programmatically cross-validated **97-move total: 2 FREE / 63 CHEAP / 27
MODERATE / 4 HARD / 1 BLOCKED**. Found 16 moves the old write-up still
named as remaining that are actually already shipped (pure bookkeeping
drift), and 10 genuinely-remaining moves that were never individually
named anywhere before this session — two of which (Struggle(165),
Helping Hand(270)) turned out to be FREE, their entire mechanism already
built and wired, missing only a `.tres` data entry. Surfaced two new
shared-mechanism clusters within the pool: a 5-move "call-a-different-
move" family (Sleep Talk/Nature Power/Copycat/Me First/Assist, reusing
Mirror Move/Metronome's reassignment pattern) and a 2-move Magic-Coat/
Snatch interception family (Magic Coat confirmed to share Magic Bounce's
own exact dispatch chain from source). Reclassified 3 moves from
MODERATE/unnamed to CHEAP given infrastructure built since the original
sweep (Taunt reuses the Disable/Encore/Throat-Chop turn-counter-volatile
shape; Assurance reuses Revenge's own `hit_by_this_turn` tracking
directly; Magic Coat reuses Magic Bounce's swap). Recommended next pick:
a 7-move CHEAP/FREE bundle (Struggle, Helping Hand, Sleep Talk, Nature
Power, Taunt, Assurance, Magic Coat).

**D4 bundle update (2026-07-10): Section D's residual is now 91.** 6 of
the recommended 7 moves shipped (`[D4 bundle]`) — Struggle, Helping Hand,
Sleep Talk, Taunt, Assurance, Magic Coat. **Nature Power was pulled from
the bundle during its own Step 0**: re-deriving it fresh found it
genuinely shares Camouflage/Secret Power's `gBattleEnvironment` blocker
(the reconnaissance pass's own "reduces to a fixed call" framing was
wrong — corrected in D4's own BLOCKED section, now 2 moves instead of 1).
Two real gaps were caught before the first test run: Helping Hand and
Magic Coat both needed their own `ban_flags` (metronomeBanned/
copycatBanned/assistBanned/mirrorMoveBanned for Helping Hand;
mirrorMoveBanned for Magic Coat) that the first data-entry pass missed,
since neither move had ever been callable by Metronome before this
session; Sleep Talk's own move-picking function needed an explicit
"is the attacker actually asleep or Comatose" gate, independent of its
new `usable_while_asleep` `pre_move_check` bypass. **Total move-
implementation count: 622→628.** Section D's residual: 97→91 (unaffected
by the Nature Power reclassification itself — it stays counted in D4's
pool either way, just moved from CHEAP to BLOCKED).

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
   total: 489→494 implemented. **9 more of Bucket 4's 2-move (and one
   3-move) sub-groups — COMPLETE (`[Bucket 4 2-move sub-groups]`,
   2026-07-09).** `M19-percent-current-hp-damage` (Super Fang/Ruination),
   `M19-ignores-stat-stages` (Chip Away/Sacred Sword/Darkest Lariat, a real
   correction — reuses Unaware's EXISTING insertion points, no new
   mechanism needed), `M19-charge-turn-spatk-boost` (Meteor Beam/Electro
   Shot, a parallel field to Skull Bash's own), `M19-hp-based-power`
   (Flail/Reversal, the established banded-formula pattern),
   `M19-stat-raised-trigger` (Burning Jealousy/Alluring Voice, new
   `stat_raised_this_turn` at the shared `apply_stat_change` chokepoint),
   `M19-random-status-choice` (Tri Attack/Dire Claw, two genuinely
   different pools), `M19-self-faint` (Self-Destruct/Explosion, a
   pre-move-canceler self-KO reusing the existing Damp check),
   `M19-berry-steal` (Pluck/Bug Bite, steal-and-immediately-consume reusing
   4 existing per-berry functions via their own `override_item` param, an
   explicitly scoped subset not exhaustive), and `M19-ignores-target-ability`
   (Sunsteel Strike/Moongeist Beam, the LITERAL SAME `moldBreakerActive`
   flag Mold Breaker uses, inheriting its exact bypass scope for free).
   19 moves total, 52/52 tests, stable across 5 reruns; 27-suite regression
   clean. Running total: 494→513 implemented.
2. **M19c (7) — COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09) — see the new
   item 10 at the end of this list for the full findings.
3. **M19d (2) — COMPLETE** (`[M19c]`/`[M19d]`, 2026-07-09) — see item 10
   for the full findings, including Mirror Move's own resolved tracking
   question.
4. **M19e (4) — COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09) — see item 7
   below for the full findings.
5. **M19f (5, incl. Bucket 4's Spirit Shackle merged in) — COMPLETE**
   (`[M19e]`/`[M19f]`, 2026-07-09) — see item 7 below for the full
   findings, including the Ghost-type/Shed Shell interaction confirmation
   against `AbilityManager.is_trapped()`.
6. **Bucket 4's remaining sub-groups (originally 6, corrected to 5 by a
   doc-drift fix, now 3 after the `[M19-steal-stats]`/
   `[M19-ally-targeting-stat-change]` session, then 2 after this session's
   own M19f completion — see item 7 below) (originally 9 moves, now 4)** —
   `M19-secondary-stat-on-hit`
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
   accuracy half, as the task's own framing assumed). **9 more of Bucket
   4's 2-move (and one 3-move) sub-groups (19 moves) are now COMPLETE**
   (`[Bucket 4 2-move sub-groups]`, 2026-07-09), bundled into one session
   matching `[Bucket 4 cheapest singles]`'s own precedent — each
   independently verified from source. New `MoveData.
   percent_current_hp_damage`/`ignores_defense_evasion_stages`/
   `charge_turn_spatk_boost`/`skips_charge_in_rain`/`is_flail_power`/
   `requires_target_stat_raised`/`random_status_pool`/`is_self_faint`/
   `steals_and_eats_berry`/`ignores_target_ability` fields; new
   `BattlePokemon.stat_raised_this_turn` field; new `AbilityManager.
   effective_ability_id` third bypass condition (inheriting Mold Breaker's
   exact scope via the same `attacker_move` param already built for
   Mycelium Might); new `ItemManager.steal_and_eat_berry_effect` reusing 4
   existing berry-family functions via `override_item`. Running total:
   494→513 implemented. **`M19-steal-stats` (1 move) and
   `M19-ally-targeting-stat-change` (3 moves) are now COMPLETE**
   (`[M19-steal-stats]`/`[M19-ally-targeting-stat-change]`, 2026-07-09) —
   two corrections to this plan's own prior framing, both confirmed via
   fresh source reads rather than assumed: Spectral Thief does NOT reuse
   Opportunist's pattern (a custom snapshot-and-transfer orchestration was
   built instead, reusing only `StatusManager.apply_stat_change` as the
   mutation primitive); "no ally-targeting stat-change mechanism exists in
   any form" was wrong — Helping Hand's own `TARGET_ALLY`/`_get_ally` shape
   already provided it. New `MoveData.steals_positive_stat_stages`/
   `stat_change_target_ally`/`also_boosts_ally` fields; zero new
   `BattleManager` infrastructure beyond one new orchestration block per
   sub-group, both reusing pre-existing primitives. 27/27 tests, 10-suite
   regression clean. Running total: 513→517 implemented. Also fixed a
   pre-existing doc-drift (Bucket 4's "6 named sub-groups" figure was
   stale by one — see Bucket 4's own section for the full root-cause
   trace). Bucket 4's only remaining sub-groups are now
   `M19-trap-secondary` (Spirit Shackle → merge into M19f once built),
   `M19-blocked-on-other-tier4` (3 moves, wait on their own Tier-4-residual
   parents), and `M19-secret-power` (deferred by Rob, not closed).
   M19-heal-block-secondary (Psychic Noise) is closed/excluded, no longer
   part of this count. 3 sub-groups
   (`M19-ignores-stat-stages`/`M19-ignores-target-ability`/
   `M19-cant-use-twice`) were found during `[M19-bucket1]`'s Step 0; 7 more
   (`M19-recoil-on-miss`/`M19-percent-current-hp-damage`/
   `M19-charge-turn-spatk-boost`/`M19-weather-conditional-accuracy`/
   `M19-stat-raised-trigger`/`M19-secondary-stat-on-hit`/
   `M19-ally-targeting-stat-change`) were found during `[M19-bucket2]`'s
   Step 0.
7. **M19e (4 moves) and M19f (5 moves, incl. `M19-trap-secondary`'s Spirit
   Shackle) are now BOTH COMPLETE** (`[M19e]`/`[M19f]`, 2026-07-09). Read
   fresh from the plan doc per the task's own Step 1 discipline (not
   reconstructed from the stale in-context summary), then re-derived from
   source at Step 0 rather than trusted at face value. M19e: confirmed all
   4 moves share ONE dispatch function (`Cmd_recoverbasedonsunlight`), but
   split into 2 genuinely different fraction shapes (Morning
   Sun/Synthesis/Moonlight's 3-way sun/no-weather/other-weather formula vs.
   Shore Up's own 2-way sandstorm/else formula with NO 1/4 branch at all).
   M19f: confirmed `is_trapped()`'s own pre-existing doc comment (written
   back at `[M17f]`) had already anticipated this exact move-based trap by
   name, so `AbilityManager.is_trapped()` needed only a 1-line extension,
   not a parallel mechanism; confirmed Shed Shell's exemption needed ZERO
   new code (already gated at the `_phase_move_selection` call site,
   uniformly across every trapping source); confirmed Jaw Lock's
   `MOVE_EFFECT_TRAP_BOTH` is a genuine THIRD variant of the SAME mechanism
   (bidirectional, all-or-nothing guard) rather than a separate one, so it
   was built in this same session too — completing Tier 3b (the
   binding-move family) alongside M19f's own status-move family. Confirmed
   `M19-trap-secondary`'s own "should be folded into M19f" note was
   accurate and folded Spirit Shackle in directly, resolving Bucket 4's
   gate in the same session rather than deferring it. New `MoveData.
   heals_based_on_weather`/`weather_heal_boost_type`/
   `weather_heal_has_quarter_branch`/`is_mean_look` fields; new
   `BattlePokemon.escape_prevented_by`; new `StatusManager.
   try_apply_escape_prevention`; new `BattleManager._weather_heal_amount()`
   helper and `escape_prevented` signal; new `SE_PREVENT_ESCAPE`/
   `SE_TRAP_BOTH` tokens. 48/48 tests, stable across reruns; 14-suite
   regression clean. Running total: 517→526 implemented. **Bucket 4's only
   remaining sub-groups are now `M19-secret-power` (deferred by Rob) and
   `M19-blocked-on-other-tier4` (3 moves, still confirmed genuinely
   unbuilt, wait on their own Tier-4-residual parents) — 4 moves, 2
   sub-groups total.**
8. **Tier 4 sub-clustering recon (181 moves) — COMPLETE
   (`[M19-section-d-cluster]`, 2026-07-09).** Section D is now a full
   mechanism-clustered breakdown (21 clusters/51 moves, 130-move
   singleton pool with a difficulty sweep, priority-unblock spotlight on
   Leech Seed/Haze/Aromatherapy+Heal Bell) — a real starting point for
   implementation sub-tiers, not just a head start.
9. **Section C's 214 moves stay out of M19 scope**: 213 permanently
   excluded (87 Z-Move/Max-Move + 126 `[M19-exclusions]`, both confirmed by
   Rob), 1 deferred (Population Bomb) to its own small future tier once Rob
   wants it. Separately, Heal Order and Dragon Darts stay implemented —
   Rob resolved that conflict (option a, docs-only) — see Section C's
   "Resolved conflicts". M19h/M19i are COMPLETE, not part of this list.
10. **M19c (7 moves) and M19d (2 moves) are now BOTH COMPLETE**
    (`[M19c]`/`[M19d]`, 2026-07-09) — **this closes out M19c-i entirely.**
    Read fresh per Step 1 discipline; confirmed no doc-drift (Section A,
    Section B, and this Section E's own table all agreed on 7/2 before this
    session started). **M19c Step 0**: confirmed all 7 share the LITERAL
    SAME `.effect = EFFECT_PROTECT` as Protect/Detect in source
    (distinguished only by `.argument.protectMethod`), and the SAME shared
    consecutive-use fail-chance counter — zero changes needed to the
    existing `is_protect` dispatch. Confirmed genuinely non-uniform beyond
    that shared base, exactly as flagged: Obstruct/Silk Trap block only
    non-status moves; Wide Guard/Quick Guard are SIDE-WIDE (checked against
    the defender's own state AND its ally's via the SAME per-battler field,
    confirmed needing NO new `_side_conditions`-style infrastructure at
    all — source's own `IsSideProtected` just reads the identical
    per-battler `protected` field twice); Wide Guard blocks only spread
    moves, Quick Guard blocks only priority>0 moves via the SAME
    ability-boosted priority computation `[M17k]`'s `blocks_priority_move`
    already established. The 5 contact-punish variants are gated on
    `AbilityManager.move_triggers_contact_retaliation` (`[M18p]`'s
    Protective-Pads-aware wrapper, confirmed the correct gate from source's
    own `CanBattlerAvoidContactEffects`). Obstruct/Silk Trap's stat-drops
    proactively wired through the same Defiant/Competitive reactive-trigger
    check `_apply_one_stat_change_pair` already establishes for "an
    opponent lowered my stat," rather than flagged-and-skipped. New
    `BattlePokemon.protect_method`/`MoveData.protect_method` (8-value enum
    mirroring source's own `ProtectMethod` exactly); new
    `BattleManager._is_protected_from()`/`_apply_protect_contact_punish()`/
    `_apply_protect_stat_punish()` helpers. **M19d Step 0**: Metal Burst
    confirmed the same `EFFECT_REFLECT_DAMAGE` shape as Counter/Mirror
    Coat, but with THREE real asymmetries (1.5x not 2x; reflects EITHER
    category, whichever was hit LAST if both landed in the same turn, not
    Counter/Mirror Coat's own single-category bitmask; priority=0, not
    their shared -5 — the third found fresh at Step 0, not originally
    flagged) — kept as its own separate `metal_burst` flag rather than
    generalizing `counter`/`mirror_coat`, avoiding any risk to their
    already-tested dispatch. **Mirror Move — the one point given real Step
    0 attention per the task's own instruction, confirmed via direct
    source read**: `GetMirrorMoveMove` reads `lastTakenMove[gBattlerAttacker]`
    — the move that hit the MIRROR MOVE USER itself, NOT the target's own
    last-used move (a Copycat-style axis this project doesn't have and
    didn't need). This project's existing per-turn
    `_last_attacker`/`_last_attacker_move` dictionaries (already built for
    Destiny Bond/Aftermath/Innards Out) already capture exactly this —
    zero new tracking state needed, resolving the sub-tier's own flagged
    uncertainty in the cheaper direction. Confirmed Mirror Move dispatches
    through the LITERAL SAME `CancelerCallSubmove` mechanism as Metronome —
    reused the existing "reassign `move` and fall through" pattern
    directly, with `defender` also reassigned to the actual hitter for
    doubles-correctness. New `m19cd_test.gd`/`.tscn`: 38/38 assertions,
    stable across 5 reruns, after fixing 3 real test-authoring bugs on the
    first run — a probabilistic assumption in the shared-consecutive-counter
    test (no RNG-forcing seam exists for `_roll_protect_success`, fixed by
    testing Spiky Shield's own guaranteed first use instead of a 2-move
    probabilistic sequence) and two speed-ordering mistakes in the Mirror
    Move tests (the mirroring Pokémon was accidentally FASTER than its
    attacker in both the singles and doubles scenarios, so it acted before
    ever being hit — fixed by swapping the relative speeds so the hit
    lands first within the same turn). 12-suite regression clean
    (`tier4_test`/`switch_test`/`doubles_test`/`m17k_test`/`m17n3_test`/
    `m18p_test` — all touching Protect/Counter/Mirror Coat, priority-block,
    or contact-retaliation infrastructure this tier extended — plus the 4
    required suites and 2 of the most recent M19 sessions' own suites).
    **Total move-implementation count: 526→535.** **M19c-i is now fully
    closed** — the only remaining M19 scope is Bucket 4's 4 gated/deferred
    moves and Section D's 181-move Tier 4 residual, both unaffected by
    this session.

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

4. ~~Tier 4's sub-clustering pass (181 moves, Section D)~~ — **RESOLVED
   (`[M19-section-d-cluster]`, 2026-07-09).** The report-only recon this
   question asked about has now been done — Section D is a full
   mechanism-clustered breakdown (21 clusters/51 moves, a 130-move
   difficulty-swept singleton pool, and a priority-unblock spotlight).
   The remaining open question is purely sequencing (which cluster to
   implement first), not whether/when to recon — see Section D's own D5
   recommendation (the Leech Seed/Haze/Aromatherapy+Heal Bell unblock)
   for the suggested next step, still deferred to Rob's own priorities.

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
