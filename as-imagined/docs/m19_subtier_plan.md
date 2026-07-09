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
`M19-cant-use-twice`). Implemented-move count: **155 → 216**. Every count
below reflects this update.

Of the reference catalog's **934 real moves**, **216 are already implemented**
and are excluded from every count below. **718 moves remain.** Of those 718:

- **323 fall into proposed sub-tiers**: 306 in the mechanism-based Buckets
  1-4 (Section B — Bucket 1 is now CLOSED/complete and no longer counted as
  pending; Bucket 4 grew from 39 to 45 to absorb Bucket 1's 6 exceptions,
  for a 306-move Bucket 2-4 total: 246 + 15 + 45)
  + 17 in M19c-i (Section B — M19h/M19i's 6 moves are COMPLETE and no
  longer counted as pending: M19c(7) + M19d(2) + M19e(4) + M19f(4) +
  M19g(0)).
- **1 is deferred** (Population Bomb, Section C3 — C4 is closed, folded
  into the 306 above).
- **213 are permanently excluded** (87 Z-Move/Max-Move + 126 from Rob's
  `[M19-exclusions]` list [124 original + Raging Bull + Psychic Noise],
  Section C1–C2 — unchanged by this update; Bucket 1's 6 exceptions moved
  to Bucket 4, NOT to this excluded count, since they're still pending
  future implementation).
- **181 (a Tier 4 residual) still need their own dedicated sub-clustering
  pass** before individual implementation sub-tiers can be proposed for
  them, per the recon's own explicit recommendation (Section D) — not
  re-audited by this session (Tier 4 residual is outside this task's own
  scope).

**323 + 1 + 213 + 181 = 718**, exactly matching `934 − 216`. Fully
reconciled — no outstanding discrepancy.

---

## Section A — Scope classification (per the recon's corrected Tier breakdown)

| Recon Tier | Total moves | Already implemented | **Remaining** | Where it lands in this plan |
|---|---|---|---|---|
| Tier 1 — no-effect / pure damage | 157 | 90 (14 + 15 `[M19a-gen1]` + 61 `[M19-bucket1]`) | **67** | 15 permanently excluded (14 `[M19-exclusions]` + Psychic Noise, `[M19-rescope-followup]`, Section C2); remaining 52 folded into Buckets 2-4 below (Bucket 1 itself is now CLOSED/complete — 61 implemented, 6 moved to Bucket 4, `[M19-bucket1]`) |
| Tier 2 — simple secondary effect | 308 | 44 (42 + Low Kick/Grass Knot, `[M19-pre1]`) | **264** | 10 permanently excluded (Section C2); remaining 254 folded into the mechanism-based Buckets 1-4 below (`[M19-rescope]`) |
| Tier 2b — Protect-family variants | 10 | 1 | **9** | M19c (7) + 2 permanently excluded (Crafty Shield/King's Shield, Section C2) |
| Tier 3a — Multi-hit family | 31 | 30 | **1** | C3 (Population Bomb, deferred to its own future tier — also on Rob's `[M19-exclusions]` list, consistent, no status change). Dragon Darts(697) is one of the 30 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Tier 3b — Binding-move family | 11 | 10 | **1** | M19f (Jaw Lock — does NOT share this mechanism, see Section D) |
| Tier 3c — Terrain family | 9 | 0 | **9** | Permanently excluded (`[M19-exclusions]`, Section C2) — resolves Open Question #2 |
| Tier 3d — Counter/Mirror-Move family | 5 | 2 | **3** | M19d (2) + 1 permanently excluded (Comeuppance, Section C2) |
| Tier 3e — Weather-conditional heal family | 4 | 0 | **4** | M19e (all 4) |
| Tier 4 — high complexity / standalone | 312 | 39 (33 + 6 `[M19-pre1]`/M19h+M19i, corrected `[M19-rescope-followup]`) | **273** | M19f (3 carved out; M19g dissolved/M19h/M19i now COMPLETE, no longer carved as pending); 89 permanently excluded (3 ex-M19g + 85 residual + Raging Bull, Section C2); **181 residual** (Section D). Heal Order(456) is one of the 39 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Z-Move (permanently excluded) | 35 | 0 | **35** | C1 |
| Max Move / Dynamax (permanently excluded) | 52 | 0 | **52** | C1 |
| **Total** | **934** | **216** (corrected, `[M19-bucket1]` — was 155) | **718** | |

**Every "already implemented" figure in this table now sums to exactly
216** (90+44+1+30+10+0+2+0+39+0+0), and every "remaining" figure sums to
exactly 718 (67+264+9+1+1+9+3+4+273+35+52) — confirmed via direct
addition, matching `934 − 216 = 718` exactly. Zero outstanding
discrepancy as of `[M19-bucket1]`.

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

### Bucket 2 — Reuses a single existing secondary mechanism (246 moves)

No new mechanism — every one of these carries EXACTLY ONE known-safe
secondary token (a single `SE_*`-mapped status/flinch, or a single-stat
`stat_change_*` block, or a primary effect that's already one of this
project's own generic dispatch mechanisms) against `BattleManager`/
`StatusManager`/`DamageCalculator`'s already-generalized pipelines. This is
the bucket `[M19-pipeline-fix]` directly repaired data for. Sub-clusters by
primary effect, for reference (no further mechanism work needed for any of
them):

- `EFFECT_HIT` + a single guaranteed/probabilistic `secondary_effect` or
  `stat_change_*`: 166 moves — the large majority of this bucket.
- Pure `EFFECT_STAT_CHANGE` (single-stat primary-effect moves): 39 moves.
- `EFFECT_NON_VOLATILE_STATUS`: 9 moves. `EFFECT_RECOIL`: 9 moves.
  `EFFECT_ABSORB`: 8 moves. `EFFECT_RECOIL_IF_MISS`: 4 moves.
  `EFFECT_TWO_TURNS_ATTACK`: 4 moves. `EFFECT_CONFUSE`: 3 moves.
  `EFFECT_FIXED_PERCENT_DAMAGE`: 2 moves. `EFFECT_SEMI_INVULNERABLE`: 2
  moves.

(166+39+9+9+8+4+4+3+2+2 = 246, reconciled.) Full move-by-move ID list
omitted here for length (matching this document's own precedent for
large single-shape buckets) — re-derivable directly from
`classify_results.json`-style source parsing if a future session needs the
literal list; the sub-cluster counts above are what matters for scoping.

### Bucket 3 — Reuses existing mechanisms, needs closer scrutiny (15 moves)

Each of these combines something this project already has with a SECOND
thing in a way the current single-slot schema can't cleanly represent, or
reuses an existing mechanism in a combination not yet proven safe. Three
distinct shapes:

- **Multi-stat-in-one-block (10 moves)** — the exact same shape as the
  already-implemented Growth (`is_growth`, `[M16a]`): a SINGLE
  `additionalEffects` entry that sets MORE THAN ONE stat sub-field
  (`.attack`/`.defense`/`.spAttack`/`.spDefense`/`.speed`/`.accuracy`/
  `.evasion`) at once. Not detectable by counting `.moveEffect` tokens
  alone (each of these has exactly one) — found by counting stat
  sub-fields WITHIN each block, a check this re-scope added after Growth's
  own precedent made it worth specifically looking for. Needs its own
  dedicated flag per move (or a small generalized "multi-stat" field),
  matching `is_growth`'s own precedent directly: Tickle(321, -1 Atk/-1
  Def), Bulk Up(339, +1 Atk/+1 Def), Dragon Dance(349, +1 Atk/+1 Spe),
  Hone Claws(468, +1 Atk/+1 Acc), Coil(489, +1 Atk/+1 Def/+1 Acc), Shift
  Gear(508, +1 Spe/+1 Atk), Coaching(739, ally-targeting +1 Atk/+1 Def),
  Victory Dance(765, +1 Atk/+1 Def/+1 Spe), Shell Smash(504, -1 Def/+2
  Atk/+2 SpAtk/+2 Spe), Spicy Extract(786, +2 Atk/-2 Def).
- **Combined secondary effects (3 moves)** — Thunder Fang(422, paralysis +
  flinch chance), Ice Fang(423, freeze/frostbite + flinch chance), Fire
  Fang(424, burn + flinch chance): each rolls TWO independent secondary
  effects on one hit, which this project's single `secondary_effect`/
  `secondary_chance` pair can't represent simultaneously. Needs either a
  second optional secondary-effect slot or dedicated per-move handling.
- **Existing mechanism + simultaneous damage (2 moves)** — Glitzy
  Glow(683)/Baddy Bad(684) deal damage AND set up Light Screen/Reflect
  (`is_light_screen`/`is_reflect` already exist, but only ever wired for
  power=0 status moves so far) — needs verifying the existing screen
  dispatch actually fires correctly when combined with a simultaneous
  damage roll, not assumed safe by construction.

### Bucket 4 — Needs a genuinely new mechanism (45 moves, 21 named sub-groups)

Each sub-group below shares ONE real mechanism this project doesn't have
yet — building it once should let a future tier apply it to every move in
that sub-group at once, rather than rediscovering the same mechanism
move-by-move (the exact trap `[M19a-gen1]` flagged as a risk and this
re-scope exists to avoid repeating).

- **M19-rampage (4)** — locks the user into the same move for 2-3 turns,
  then inflicts self-confusion (`MOVE_EFFECT_THRASH`): Thrash(37), Petal
  Dance(80), Outrage(200), Raging Fury(761).
- **M19-recharge (10)** — user must skip its next turn after use
  (`MOVE_EFFECT_RECHARGE`): Hyper Beam(63), Blast Burn(307), Hydro
  Cannon(308), Frenzy Plant(338), Giga Impact(416), Rock Wrecker(439), Roar
  of Time(459), Prismatic Laser(665), Meteor Assault(722), Eternabeam(723).
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
- **M19-rage (1)** — Attack rises each time the user is hit while this
  move is active/last-used (`MOVE_EFFECT_RAGE`): Rage(99).
- **M19-uproar (1)** — locks the user into Uproar for several turns and
  prevents sleep infliction (self and foes) while active: Uproar(253).
- **M19-secret-power (1)** — secondary effect depends on terrain/location
  (this project has no Terrain/location system — likely resolves to one
  fixed effect, needs individual scope confirmation from Rob rather than
  assumed): Secret Power(290).
- **M19-break-protect (4)** — ACTIVELY removes the target's already-active
  Protect state and resets their consecutive-use counter (confirmed via
  `battle_script_commands.c` L2584: `MOVE_EFFECT_FEINT` clears
  `gProtectStructs[...].protected` and `consecutiveMoveUses`, and also
  clears a side-wide Wide-Guard/Quick-Guard-family block on the user's
  partner) — genuinely more than this project's existing `ignores_protect`
  field, which only lets a move bypass an ALREADY-resolved Protect check,
  not retroactively break one: Feint(364), Shadow Force(467), Phantom
  Force(566), Hyperspace Hole(593).
- **M19-berry-steal (2)** — eats/consumes the target's held berry after a
  successful hit (`MOVE_EFFECT_BUG_BITE`): Pluck(365), Bug Bite(450).
- **M19-stat-reset (1)** — resets the target's stat stages to exactly 0
  (an absolute reset, not a relative `stat_change_amount` delta): Clear
  Smog(499).
- **M19-item-destroy (1)** — destroys the target's held berry/gem outright
  (distinct from M19-berry-steal — the item is destroyed, not consumed by
  the user): Incinerate(510).
- **M19-trap-secondary (1)** — inflicts escape-prevention as a SECONDARY
  effect on a damaging hit (`MOVE_EFFECT_PREVENT_ESCAPE`) — shares the
  SAME mechanism M19f (Section B above) is already planned to build for
  Spider Web/Mean Look/Block/Jaw Lock; **should be folded into M19f once
  that tier is built, not treated as its own new family**: Spirit
  Shackle(625).
- **M19-cure-opponent-status (1)** — cures the TARGET's status condition
  after landing a hit (the inverse of every existing self-cure precedent):
  Sparkling Aria(627).
- **M19-sound-block (1)** — blocks the target from using sound-category
  moves for 2 turns (a new volatile, similar shape to Encore/Disable/Taunt
  but keyed on the `sound_move` flag rather than a specific move):
  Throat Chop(638).
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
- **M19-pp-reduce (1)** — sharply reduces the target's last-used move's PP
  (a stronger Spite-shaped effect, no existing "reduce opponent's PP"
  mechanism): Eerie Spell(754).
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
- **M19-cant-use-twice (1)** — found during `[M19-bucket1]`'s Step 0:
  `.cantUseTwice = TRUE` blocks selecting the same move on consecutive
  turns — no move-repeat tracking exists anywhere in the engine: Blood
  Moon(829).

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

(4+10+2+2+2+1+1+1+4+2+1+1+1+1+1+1+3+1+3+2+1 = 45, reconciled.)

**Recommended execution order for Buckets 1-4:**

1. **Bucket 1 (67) — COMPLETE (`[M19-bucket1]`, 2026-07-08).** 61 implemented,
   6 moved to Bucket 4 as new-mechanism exceptions (see above).
2. **Bucket 2 (246)** — still zero new mechanism, the overwhelming bulk of
   this pool. Recommend splitting by sub-cluster (the 10 groups listed
   above) or by count across multiple sessions.
3. **Bucket 3 (15)** — still reuse-based, but each move needs individual
   care before implementation: the 10 multi-stat moves need a dedicated
   flag decision (one per-move flag matching `is_growth`'s precedent, or a
   small generalized multi-stat mechanism — worth deciding once, up front,
   rather than per move); the 3 combined-secondary-effect moves need a
   schema decision (second secondary-effect slot vs. dedicated handling);
   the 2 screen+damage moves need the dispatch-order verification noted
   above.
4. **Bucket 4's 21 sub-groups, sequenced by real dependency, not move
   count** — each is effectively its own small new-mechanism tier, closer
   in shape to M19c-i than to bulk data-entry:
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
   - The remaining 15 sub-groups (M19-rampage, M19-recharge, M19-self-faint,
     M19-random-status-choice, M19-hp-based-power, M19-rage, M19-uproar,
     M19-secret-power, M19-break-protect, M19-berry-steal, M19-stat-reset,
     M19-item-destroy, M19-cure-opponent-status, M19-sound-block,
     M19-pp-reduce) have no known dependency on each other or on
     unimplemented moves — sequence by whichever mechanism Rob wants built
     next, cheapest/smallest first is the natural default (M19-rage,
     M19-uproar, M19-secret-power, M19-stat-reset, M19-item-destroy,
     M19-cure-opponent-status, M19-sound-block, M19-pp-reduce are all
     single-move sub-groups — cheapest to verify and land individually).

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
| Already implemented (excluded from this plan) — includes Heal Order/Dragon Darts (resolved conflicts); corrected this session, see `[M19-bucket1]` above | 216 |
| Proposed sub-tiers (Section B: Buckets 2-4 — Bucket 1 now COMPLETE — plus M19c-i minus M19h/M19i now COMPLETE) | 323 (306 + 17) |
| Deferred (Section C3 — Population Bomb only; C4 closed) | 1 |
| Permanently excluded, confirmed by Rob (Section C1 Z-Move/Max-Move + Section C2 `[M19-exclusions]`, incl. Raging Bull + Psychic Noise addenda) | 213 |
| Tier 4 residual, needs its own sub-clustering pass (Section D) | 181 |
| **Total (matches the recon's 934-move catalog)** | **934** |

216 + 323 + 1 + 213 + 181 = 934, confirmed by direct addition. Zero
outstanding discrepancy.

| Sub-tier | Moves | Risk | Depends on |
|---|---|---|---|
| Bucket 1 — pure damage, no additional effect | **COMPLETE** (`[M19-bucket1]`, 61 implemented + 6 moved to Bucket 4) | — | — |
| Bucket 2 — single existing secondary mechanism | 246 | Cheap | — (recommend splitting by sub-cluster, see Section B) |
| Bucket 3 — existing mechanisms, needs scrutiny | 15 | Moderate | schema/dispatch decisions noted per shape in Section B |
| Bucket 4 — genuinely new mechanism (21 sub-groups) | 45 | Varies per sub-group | see Section B's own per-sub-group notes |
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
   implemented, 6 moved to Bucket 4. **Bucket 2 (246)** is next — the
   overwhelming majority of M19's remaining buildable scope, zero new
   mechanism cost, matching M18a/M18b's own "front-load the cheapest bulk"
   precedent. Given the scale, strongly recommend splitting execution
   across multiple sessions (by sub-cluster or by count, not by generation
   — `[M19-rescope]` exists specifically because generation wasn't a
   useful split) rather than attempting it in one prompt.
2. **Bucket 3 (15)** — still reuse-based but needs the per-shape decisions
   noted in Section B (multi-stat dedicated-flag approach, combined-
   secondary-effect schema decision, screen+damage dispatch-order check)
   made ONCE up front, then applied uniformly.
3. **M19c (7)** — cheap, single shared mechanism, no dependencies.
4. **M19d, M19e (2 + 4 = 6)** — each a small, self-contained extension of an
   already-built system (`_last_attacker` tracking, weather + `RESTORE_HP`).
5. **M19f (4, or 5 once Bucket 4's Spirit Shackle is merged in per Section
   B's own recommendation)** — the one genuinely new mechanism in this
   plan's non-Bucket-4 buildable scope; budget real care per `[M17f]`'s own
   trapping-infrastructure precedent, confirm the Ghost-type/Shed Shell
   interaction against `AbilityManager.is_trapped()` before writing new
   code.
6. **Bucket 4's 21 sub-groups (45 moves)** — sequenced per Section B's own
   dependency-ordered recommendation (Spirit Shackle → merge into M19f;
   Spectral Thief → reuse Opportunist's pattern; the 3
   blocked-on-other-Tier4 moves → wait on their own parents; the other 18
   sub-groups → sequence freely, cheapest/single-move groups first).
   M19-heal-block-secondary (Psychic Noise) is closed/excluded, no longer
   part of this count. The 3 newest sub-groups
   (`M19-ignores-stat-stages`/`M19-ignores-target-ability`/
   `M19-cant-use-twice`) were found during `[M19-bucket1]`'s own Step 0.
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
