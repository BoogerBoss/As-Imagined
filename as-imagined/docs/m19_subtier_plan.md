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
full citations. Every count below reflects this.

Of the reference catalog's **934 real moves**, **147 are already implemented**
(132 confirmed by `[M19-pipeline-fix]` + 15 new from `[M19a-gen1]`) and are
excluded from every count below. **787 moves remain.** Of those 787:

- **386 fall into 9 proposed sub-tiers** (Section B, M19a–M19i; M19g is now
  empty/dissolved — see `[M19-exclusions]` above; M19a's Gen I slice is
  done — see `[M19a-gen1]` above).
- **8 are deferred** (Population Bomb, Section C3; 7 Gen I Tier-1 stragglers
  needing new mechanisms, Section C4).
- **212 are permanently excluded** (87 Z-Move/Max-Move + 125 from Rob's
  `[M19-exclusions]` list [124 original + Raging Bull], Section C1–C2).
- **181 (a Tier 4 residual) still need their own dedicated sub-clustering
  pass** before individual implementation sub-tiers can be proposed for
  them, per the recon's own explicit recommendation (Section D).

**386 + 8 + 212 + 181 = 787**, reconciled programmatically against every
move ID in the recon's own corrected Section B listings — no duplicates,
no omissions (verified: the union of every bucket below is exactly the
787-move unimplemented set, with zero move counted twice).

---

## Section A — Scope classification (per the recon's corrected Tier breakdown)

| Recon Tier | Total moves | Already implemented | **Remaining** | Where it lands in this plan |
|---|---|---|---|---|
| Tier 1 — no-effect / pure damage | 157 | 29 (14 + 15 `[M19a-gen1]`) | **128** | M19a (107, Gen II–IX remaining) + 14 permanently excluded (`[M19-exclusions]`, Section C2) + 7 deferred (`[M19a-gen1]`, Section C4, Gen I stragglers needing new mechanism) |
| Tier 2 — simple secondary effect | 308 | 42 | **266** | M19b (256, incl. Low Kick/Grass Knot — unblocked by `[M19-pre1]`) + 10 permanently excluded (Section C2) |
| Tier 2b — Protect-family variants | 10 | 1 | **9** | M19c (7) + 2 permanently excluded (Crafty Shield/King's Shield, Section C2) |
| Tier 3a — Multi-hit family | 31 | 30 | **1** | C3 (Population Bomb, deferred to its own future tier — also on Rob's `[M19-exclusions]` list, consistent, no status change). Dragon Darts(697) is one of the 30 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Tier 3b — Binding-move family | 11 | 10 | **1** | M19f (Jaw Lock — does NOT share this mechanism, see Section D) |
| Tier 3c — Terrain family | 9 | 0 | **9** | Permanently excluded (`[M19-exclusions]`, Section C2) — resolves Open Question #2 |
| Tier 3d — Counter/Mirror-Move family | 5 | 2 | **3** | M19d (2) + 1 permanently excluded (Comeuppance, Section C2) |
| Tier 3e — Weather-conditional heal family | 4 | 0 | **4** | M19e (all 4) |
| Tier 4 — high complexity / standalone | 312 | 33 | **279** | M19f (3) + M19g (0, dissolved — all 3 of its moves permanently excluded) + M19h (2, weight) + M19i (4, friendship) = 9 carved out; 89 permanently excluded (3 ex-M19g + 85 residual + Raging Bull, Section C2); **181 residual** (Section D). Heal Order(456) is one of the 33 "already implemented" — was flagged as a conflict, RESOLVED: stays implemented (option a), see "Resolved conflicts" below. |
| Z-Move (permanently excluded) | 35 | 0 | **35** | C1 |
| Max Move / Dynamax (permanently excluded) | 52 | 0 | **52** | C1 |
| **Total** | **934** | **147** | **787** | |

**Confirming the pipeline fix's own scoping implication, per this task's
explicit ask**: the 81 moves `[M19-pipeline-fix]` reclassified Tier 1 → Tier 2
carry **no special handling requirement beyond a normal Tier 2 implementation
tier**. The reclassification was purely a data-accuracy correction — these 81
moves' real mechanics (a secondary stat-change attached to a damage move, e.g.
Mud-Slap/Icy Wind/Rock Tomb) are the exact same generic `stat_change_stat`/
`amount`/`self` dispatch every other Tier 2 stat-change move already uses.
They are NOT called out as a separate sub-tier below — they're folded into
M19b alongside every other Tier 2 move, since nothing about them is
mechanically distinct now that the reference data is correct. The 12 moves
`[M19-pipeline-fix]`'s second bug fixed (`secondary_chance`) are similarly
unremarkable — plain status-infliction Tier 2 moves whose extracted chance
value is now simply correct.

---

## Section B — Proposed sub-tier breakdown (cheapest/most-precedented first)

### M19a — Tier 1 pure-damage data-entry (107 moves remaining) — **CHEAPEST**

No new mechanism at all. Every one of these is `EFFECT_HIT` with zero
secondary data (no `stat_change_*`, no `secondary_effect`, no `recoil_percent`,
etc.) — a pure power/accuracy/pp/type/category/flags data row against
`DamageCalculator`'s already-fully-generalized damage pipeline, the exact
same shape `[M18b]`'s resist-berry data-entry occupied for items. This is the
single largest sub-tier by move count in the entire plan, spanning every
generation. **Recommend splitting execution across multiple sessions by
generation** (matching `[M17n]`'s own Group 1-8 precedent for large batches)
rather than one prompt — this plan does not pre-commit to an exact split,
since that's an execution-sequencing choice, not a scoping one.

**`[M19-exclusions]` update:** 14 moves permanently excluded and removed
from this count (143→129): Attack Order(454), Flame Burst(481),
V-create(557), Thousand Waves(615), Anchor Shot(640), Core Enforcer(650),
Plasma Fists(674), Order Up(784), Glaive Rush(790), Salt Cure(792), Make It
Rain(802), Gigaton Hammer(819), Syrup Bomb(831), Mighty Cleave(838). See
Section C2.

**`[M19a-gen1]` update (2026-07-08):** Generation I's slice (22 moves) is
DONE. Step 0 re-verified the recon's "pure data-entry" framing individually
against source rather than trusting it uniformly — 15 confirmed pure and
**IMPLEMENTED**: Mega Punch(5), Pay Day(6), Vise Grip(11), Cut(15),
Gust(16), Slam(21), Mega Kick(25), Horn Attack(30), Hydro Pump(56),
Peck(64), Drill Peck(65), Razor Leaf(75), Egg Bomb(121), Crabhammer(152),
Slash(163) — see `docs/decisions.md`'s `[M19a-gen1]` entry for full source
citations and the per-move data table. **7 more moved OUT of this tier
entirely** (Thrash(37), Petal Dance(80), Rage(99), Hyper Beam(63),
Self-Destruct(120), Explosion(153), Tri Attack(161)) — each needs a
mechanism this project doesn't have (rampage lock-in, hit-triggered stat
boost, recharge, unconditional self-faint + Damp block, random multi-status
choice), so building them would mean adding new dispatch logic inside what
this tier is supposed to be a pure data-entry pass — see the new Section
C4. Net: 129 → 107 remaining in this tier's own scope (15 done, 7
reclassified), spanning Generations II–IX. **Recommend Generation II next**
(IDs 166-251 per `docs/m19_recon.md`), continuing the same per-generation
execution split.

### M19b — Tier 2 secondary-effect data-entry (256 moves) — **CHEAP**

Also no new mechanism — every generic field this tier needs
(`secondary_effect`/`secondary_chance`, `stat_change_stat`/`amount`/`self`,
`recoil_percent`, `drain_percent`, `two_turn`, `semi_inv_state`) already
exists and is already read generically by `BattleManager`/`StatusManager`/
`DamageCalculator`. This is the tier `[M19-pipeline-fix]` directly repaired
data for — most of these 256 already had correct data before that session;
94 unique moves were fixed (88 stat-change, 12 chance, 6 overlapping), 82 of
which landed in Tier 2 via reclassification from Tier 1, the rest were
already-Tier-2 chance-only fixes. **`[M19-exclusions]` update:** 10 moves
permanently excluded and removed from this count (266→256): Chatter(448),
Defend Order(455), Nature's Madness(671), Shelter(770), Triple Arrows(771),
Blazing Torque(822), Wicked Torque(823), Noxious Torque(824), Combat
Torque(825), Magical Torque(826). See Section C2. Sub-clusters by
generic-field family, for reference (no further mechanism work needed for
any of them):
- `EFFECT_HIT` + guaranteed/probabilistic `secondary_effect` or
  `stat_change_*`: the large majority of the 256.
- Pure `EFFECT_STAT_CHANGE` (primary-effect stat moves): 51 moves.
- `EFFECT_NON_VOLATILE_STATUS`: 9 moves (includes 6 of `[M19-pipeline-fix]`'s
  chance-only fixes: Poison Sting/Bite/Thunder/Sludge/Fire Blast/Poison
  Fang).
- `EFFECT_RECOIL`: 9 moves. `EFFECT_ABSORB`: 8 moves. `EFFECT_CONFUSE`: 3
  moves. `EFFECT_RECOIL_IF_MISS`: 4 moves. `EFFECT_SEMI_INVULNERABLE`: 4
  moves (two-turn charge-then-hide, `[M16a]`-adjacent). `EFFECT_TWO_TURNS_
  ATTACK`: 4 moves. `EFFECT_FIXED_PERCENT_DAMAGE`: 3 moves.
- `EFFECT_LOW_KICK`: 2 moves (Low Kick(67)/Grass Knot(447)) — briefly
  carved out into a deferred bucket earlier in this plan's own history over
  a missing per-species weight dependency; **unblocked and implemented by
  `[M19-pre1]`**, folded back into this tier's own count since nothing
  about their real mechanism (a lookup-table power formula, no different in
  spirit from a generic field read) sets them apart from the rest of this
  tier anymore.

Same execution note as M19a: recommend splitting by generation or by
sub-cluster at execution time, not a single 264-move prompt.

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

### M19h — Weight-ratio dynamic power (2 moves) — **CHEAPEST, unblocked by `[M19-pre1]`**

Heavy Slam(484), Heat Crash(535) — Tier 4 moves (`EFFECT_HEAT_CRASH`) whose
power derives from the integer ratio of the attacker's weight to the
target's weight (`PokemonSpecies.weight`, hectograms), indexed into a fixed
6-entry table. Originally deferred to Section C over a missing per-species
weight field this project's data pipeline had never populated —
`[M19-pre1]` added `PokemonSpecies.weight` (species-level, fixed, no
forcing parameter needed) and a new `scripts/gen_weight_data.py` extraction
pipeline. No remaining infrastructure gap; now a pure lookup-table
data-entry tier, the same complexity class as M19g.

### M19i — Friendship-based dynamic power (4 moves) — **CHEAPEST, unblocked by `[M19-pre1]`**

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
for M24's future trainer-data needs. No remaining infrastructure gap; now a
pure formula-lookup data-entry tier.

---

## Section C — Moves better left out of M19 for now (220 moves: 212 permanently excluded + 8 deferred)

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

### C2 — Rob's `[M19-exclusions]` list (125 moves) — **PERMANENTLY EXCLUDED, confirmed by Rob (2026-07-08)**

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

**14 + 10 + 2 + 1 + 3 + 9 + 85 + 1 = 125.**

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

### C4 — Gen I Tier-1 stragglers needing new mechanism (7 moves) — found by `[M19a-gen1]` (2026-07-08)

Thrash(37), Petal Dance(80), Rage(99), Hyper Beam(63), Self-Destruct(120),
Explosion(153), Tri Attack(161). All 7 sat in the recon's Tier 1 ("no-effect
/ pure damage") bucket, but Step 0 of `[M19a-gen1]` re-verified that framing
against `moves_info.h` directly (rather than trusting it) and found each one
carries a real mechanism this project doesn't have yet:

- **Thrash/Petal Dance** (`MOVE_EFFECT_THRASH`): locks the user into the
  same move for 2-3 turns, then inflicts self-confusion — no rampage/
  lock-in mechanism exists anywhere in this project.
- **Rage** (`MOVE_EFFECT_RAGE`): the user's Attack rises each time it's hit
  while Rage is the active/last-used move — no such hit-triggered tracking
  exists.
- **Hyper Beam** (`MOVE_EFFECT_RECHARGE`): the user must skip its next turn
  — no recharge/`must_recharge` mechanism exists.
- **Self-Destruct/Explosion** (`.explosion = TRUE`): the user faints
  unconditionally after use, and Damp blocks the move outright at selection
  (`battle_util.c` L3993) — a genuinely different gate from Aftermath's
  existing post-faint Damp check (`[M17n-8]`).
- **Tri Attack** (`MOVE_EFFECT_TRI_ATTACK`, chance=20): randomly inflicts
  ONE of burn/paralysis/freeze — no existing `SE_*` constant supports a
  random multi-status choice (every current one is a fixed single outcome).

Not blocked on a single shared piece of infrastructure the way weight/
friendship were (Section C's own "Closed" note below) — each needs its OWN
new mechanism, so this is a genuinely higher-complexity bucket than a
straightforward data-entry tier, deferred to its own future session(s)
rather than built inside M19a. Likely candidates for a small dedicated
"Gen I Tier-1 mechanisms" tier whenever Rob wants it, possibly bundled with
similarly-shaped stragglers found in later generations' own Tier-1 slices
(not yet checked — Gen II onward hasn't had this same re-verification pass
run yet).

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
tested mechanics — see Section B's M19b/M19h/M19i above and
`docs/decisions.md`'s `[M19-pre1]` entry for the full implementation.
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
| Already implemented (excluded from this plan) — includes Heal Order/Dragon Darts (resolved conflicts) + 15 new from `[M19a-gen1]`, see Section C | 147 |
| Proposed sub-tiers M19a–M19i (Section B; M19g now empty/dissolved, M19a's Gen I slice done) | 386 |
| Deferred (Section C3 — Population Bomb; Section C4 — 7 Gen I Tier-1 stragglers needing new mechanism) | 8 |
| Permanently excluded, confirmed by Rob (Section C1 Z-Move/Max-Move + Section C2 `[M19-exclusions]`, incl. Raging Bull addendum) | 212 |
| Tier 4 residual, needs its own sub-clustering pass (Section D) | 181 |
| **Total (matches the recon's 934-move catalog)** | **934** |

| Sub-tier | Moves | Risk | Depends on |
|---|---|---|---|
| M19a — Tier 1 pure-damage data-entry | 107 (Gen I's 22-move slice done — 15 implemented, 7 moved to C4) | Cheapest | — (recommend splitting execution by generation; Gen II next) |
| M19b — Tier 2 secondary-effect data-entry | 256 | Cheap | — (recommend splitting execution by generation/sub-cluster) |
| M19c — Protect-family variants | 7 | Cheap | — |
| M19d — Counter/Mirror-Move remnants | 2 | Cheap-moderate | — |
| M19e — Weather-conditional heal family | 4 | Cheap-moderate | — |
| M19f — Escape-prevention family (incl. Jaw Lock) | 4 | Moderate (new mechanism) | — |
| M19g — DISSOLVED, all 3 moves permanently excluded | 0 | — | — |
| M19h — Weight-ratio dynamic power | 2 | Cheapest | — (unblocked by `[M19-pre1]`) |
| M19i — Friendship-based dynamic power | 4 | Cheapest | — (unblocked by `[M19-pre1]`) |
| Tier 4 sub-clustering pass | 181 | Unknown — needs its own recon | M19a-i not required first, but recommended for momentum |

**Recommended implementation order:**

1. **M19h, M19i (2 + 4 = 6) first** — trivially cheap, effectively Tier 1
   data-entry, clears 6 moves with zero new mechanism (both only just
   unblocked by `[M19-pre1]` — good candidates to confirm the new fields
   work correctly in real implementation before the big bulk tiers). M19g
   is no longer part of this step — dissolved by `[M19-exclusions]`.
2. **M19a and M19b (107 + 256 = 363 remaining)** — the overwhelming majority
   of M19's buildable scope, zero new mechanism cost, matching M18a/M18b's
   own "front-load the cheapest bulk" precedent. Given the scale, strongly
   recommend splitting execution across multiple sessions (by generation is
   the most natural axis, since it's already how the recon itself is
   organized) rather than attempting either in one prompt — `[M19a-gen1]`
   is the first such slice (15 done), Gen II is the natural next one, and
   each Gen I-style slice should re-verify the recon's tier framing
   individually rather than trust it, per this session's own finding (7 of
   22 Gen I "Tier 1" moves needed reclassifying).
3. **M19c (7)** — cheap, single shared mechanism, no dependencies.
4. **M19d, M19e (2 + 4 = 6)** — each a small, self-contained extension of an
   already-built system (`_last_attacker` tracking, weather + `RESTORE_HP`).
5. **M19f (4)** — the one genuinely new mechanism in this plan's buildable
   scope; budget real care per `[M17f]`'s own trapping-infrastructure
   precedent, confirm the Ghost-type/Shed Shell interaction against
   `AbilityManager.is_trapped()` before writing new code.
6. **Tier 4 sub-clustering recon (181 moves)** — recommend as its OWN
   dedicated report-only session, mirroring how `docs/m19_recon.md` itself
   was produced before this plan, rather than guessing sub-tiers from
   effect-name clustering alone. Section D's own table is a head start, not
   a finished breakdown.
7. **Section C's 220 moves stay out of M19 scope**: 212 permanently
   excluded (87 Z-Move/Max-Move + 125 `[M19-exclusions]`, both confirmed by
   Rob), 8 deferred (1 Population Bomb; 7 Gen I Tier-1 stragglers needing
   new mechanism, Section C4, found by `[M19a-gen1]`) to their own small
   future tier(s) once Rob wants them. Separately, Heal Order and Dragon
   Darts stay implemented — Rob resolved that conflict (option a,
   docs-only) — see Section C's "Resolved conflicts".

No sub-tier in Section B is flagged as needing further internal splitting
before it's attempted, EXCEPT M19a/M19b's own explicitly-noted execution-
scale recommendation (split by generation) — unlike M18's own plan, this
isn't a shape concern (both are single-shape, low-variance batches), purely
a session-length one given their combined 363-move remaining size.

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
   both fields and implemented all 8 moves. See Section B's M19b/M19h/M19i.

4. **Tier 4's sub-clustering pass (181 moves, Section D)**: should this be
   scheduled as its own explicit report-only session (matching how
   `docs/m19_recon.md` itself, and this plan, were both produced) before
   any Tier 4 implementation work starts, or should Tier 4 wait entirely
   until M19a/M19b/M19c-i's ~363 remaining moves are done? This plan recommends the
   former (parallel-track the recon while the cheap bulk work proceeds) but
   defers the actual scheduling call to Rob's own preference, matching this
   project's established pattern of not pre-deciding sequencing questions
   that are really about Rob's available time and priorities, not technical
   dependency. **Still open.**

5. ~~Heal Order(456) / Dragon Darts(697) conflict~~ — **RESOLVED
   (2026-07-08).** Rob confirmed option (a) for both: docs-only exclusion,
   shipped code/tests untouched, no revert. See Section C's "Resolved
   conflicts".
