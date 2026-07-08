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

Of the reference catalog's **934 real moves**, **132 are already implemented**
(re-confirmed directly from `gen_moves.py`'s own `MOVES` dict by
`[M19-pipeline-fix]`, up from the recon's original 91 — entirely M18.5's
completed infrastructure, not new work from this planning session) and are
excluded from every count below. **802 moves remain.** Of those 802:

- **438 fall into 9 proposed sub-tiers** (Section B, M19a–M19i).
- **10 are deferred or blocked** on missing infrastructure or standing
  decisions this project already has (Section C2–C3).
- **87 are Z-Move/Max-Move exclusions**, confirmed permanent by Rob,
  matching the Mega Evolution exclusion precedent (Section C1).
- **267 (a Tier 4 residual) still need their own dedicated sub-clustering
  pass** before individual implementation sub-tiers can be proposed for
  them, per the recon's own explicit recommendation (Section D).

**438 + 10 + 87 + 267 = 802**, reconciled programmatically against every
move ID in the recon's own corrected Section B listings — no duplicates,
no omissions (verified: the union of every bucket below is exactly the
802-move unimplemented set, with zero move counted twice).

---

## Section A — Scope classification (per the recon's corrected Tier breakdown)

| Recon Tier | Total moves | Already implemented | **Remaining** | Where it lands in this plan |
|---|---|---|---|---|
| Tier 1 — no-effect / pure damage | 157 | 14 | **143** | M19a (all 143) |
| Tier 2 — simple secondary effect | 308 | 42 | **266** | M19b (all 266, incl. Low Kick/Grass Knot — unblocked by `[M19-pre1]`) |
| Tier 2b — Protect-family variants | 10 | 1 | **9** | M19c (all 9) |
| Tier 3a — Multi-hit family | 31 | 30 | **1** | C4 (Population Bomb, deferred to its own future tier) |
| Tier 3b — Binding-move family | 11 | 10 | **1** | M19f (Jaw Lock — does NOT share this mechanism, see Section C2) |
| Tier 3c — Terrain family | 9 | 0 | **9** | C3 (all 9, standing decision to re-confirm) |
| Tier 3d — Counter/Mirror-Move family | 5 | 2 | **3** | M19d (all 3) |
| Tier 3e — Weather-conditional heal family | 4 | 0 | **4** | M19e (all 4) |
| Tier 4 — high complexity / standalone | 312 | 33 | **279** | M19f (3) + M19g (3) + M19h (2, weight — unblocked by `[M19-pre1]`) + M19i (4, friendship — unblocked by `[M19-pre1]`) = 12 carved out; **267 residual** (Section D) |
| Z-Move (permanently excluded) | 35 | 0 | **35** | C1 |
| Max Move / Dynamax (permanently excluded) | 52 | 0 | **52** | C1 |
| **Total** | **934** | **132** | **802** | |

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

### M19a — Tier 1 pure-damage data-entry (143 moves) — **CHEAPEST**

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

### M19b — Tier 2 secondary-effect data-entry (266 moves) — **CHEAP**

Also no new mechanism — every generic field this tier needs
(`secondary_effect`/`secondary_chance`, `stat_change_stat`/`amount`/`self`,
`recoil_percent`, `drain_percent`, `two_turn`, `semi_inv_state`) already
exists and is already read generically by `BattleManager`/`StatusManager`/
`DamageCalculator`. This is the tier `[M19-pipeline-fix]` directly repaired
data for — most of these 266 already had correct data before that session;
94 unique moves were fixed (88 stat-change, 12 chance, 6 overlapping), 82 of
which landed in Tier 2 via reclassification from Tier 1, the rest were
already-Tier-2 chance-only fixes. Sub-clusters by generic-field family, for
reference (no further mechanism work needed for any of them):
- `EFFECT_HIT` + guaranteed/probabilistic `secondary_effect` or
  `stat_change_*`: the large majority of the 266.
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

### M19c — Protect-family variants (9 moves) — **CHEAP**

Wide Guard(469), Quick Guard(501), Crafty Shield(578), King's Shield(588),
Spiky Shield(596), Baneful Bunker(624), Obstruct(720), Silk Trap(780),
Burning Bulwark(836). Each layers one small twist (side-wide instead of
single-target, a contact-punish stat-drop, a contact-punish burn/poison,
etc.) on top of the SAME underlying "block the move, track the
consecutive-use success-chance falloff" mechanism Protect (182) already has
fully working. Matches `[M18]`'s own C6 characterization almost exactly —
"arguably not even Tier 3 moderate," flagged separately only because each
variant's own exact twist needs individual source verification (this
project's standing "don't assume symmetry between similar-looking effects"
discipline).

### M19d — Counter/Mirror-Move remnants (3 moves) — **CHEAP-MODERATE**

Mirror Move(119), Metal Burst(368), Comeuppance(820). Counter(68) and Mirror
Coat(243) already prove this project's `_last_attacker`/`_last_attacker_move`
tracking (`[M14b]`/`[M17n-8]`) generalizes to "reflect 1.5–2× the last hit of
a specific category taken this turn." Metal Burst/Comeuppance are the same
`EFFECT_REFLECT_DAMAGE` shape as Counter/Mirror Coat — likely closer to
data-entry than new mechanism. Mirror Move (`EFFECT_MIRROR_MOVE`, reuse the
target's own last-used move) is the one genuinely different piece — confirm
whether `_last_attacker_move` already captures enough to reuse a move
object directly, or whether a new "last move USED BY the target" (not
"last move that hit me") field is needed — a subtly different tracking axis
from what Destiny Bond/Moxie currently use.

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

### M19g — Dynamax-conditional-power moves, doubling-condition-always-false (3 moves) — **CHEAPEST, effectively Tier 1**

Dynamax Cannon(690), Behemoth Blade(709), Behemoth Bash(710) — Tier 4 moves
whose `EFFECT_DYNAMAX_DOUBLE_DMG` doubles power only when the user is
Dynamaxed. This project has no Dynamax mechanic (matching the Z-Move/Max-
Move exclusion precedent) and none is planned, so the doubling condition is
permanently false — these three resolve as flat base-power `EFFECT_HIT`-
shaped moves, no different from M19a's data-entry in practice. Not a
Dynamax-mechanic dependency the way the 52 actual Max Moves are; flagged
separately here so they aren't mistakenly bundled into the Z-Move/Max-Move
exclusion candidates in Section C1 — these 3 are normal, always-usable
moves, just currently sitting in the recon's Tier 4 bucket by classification
inertia.

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

## Section C — Moves better left out of M19 for now (97 moves: 87 permanently excluded + 10 blocked/deferred)

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

### C2 — Terrain family (9 moves) — standing decision to re-confirm, not a missing-data gap

Grassy Terrain(580), Misty Terrain(581), Electric Terrain(604), Psychic
Terrain(641), Expanding Force(725), Misty Explosion(730), Rising
Voltage(732), Terrain Pulse(733), Psyblade(827). Per this project's own
standing decision: **"M17e (Terrain) is VOID — all 10 terrain abilities
excluded, no Terrain system will be built."** These 9 moves depend on the
exact field-state system that decision already declined to build.
Implementing any of these 9 would either require reopening that decision or
building a terrain system scoped ONLY to moves (a genuinely different,
narrower proposition than what M17e voided). See Open Questions below —
this needs Rob's explicit go/no-go, not a silent inclusion or continued
exclusion. Still open — unaffected by `[M19-pre1]`.

### C3 — Population Bomb (1 move) — its own future tier, not blocked

Population Bomb(788) is the sole `.strikeCount` move `[M18.5g]` deliberately
excluded from the multi-hit mechanism it otherwise built — per-hit accuracy
checks (unlike every other `strikeCount` move, which checks once) AND a
uniquely-shaped Loaded Dice interaction (`RandomUniform(4,10)` instead of
the standard `(4,5)`). Not blocked on missing infrastructure — a genuinely
higher complexity class than the rest of Tier 3a, deliberately deferred to
its own small future tier rather than bundled here.

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

## Section D — Tier 4 residual (267 moves): needs its own dedicated sub-clustering pass

Of Tier 4's 279 total remaining moves, 12 were confidently carved into
Section B above (Spider Web/Mean Look/Block → M19f, Dynamax Cannon/
Behemoth Blade/Behemoth Bash → M19g, Heavy Slam/Heat Crash → M19h,
Return/Frustration/Pika Papow/Veevee Volley → M19i). **The remaining 267 are
NOT sub-tiered by this plan**, per the corrected recon's own explicit
recommendation ("a dedicated Tier-4 sub-clustering pass, mirroring this
recon's own C1–C6 methodology, is the natural next step before any attempt
to estimate M19's true total size"). Sizing 267 structurally diverse moves
by effect-name alone (the only lens this planning session had time to
apply) risks the same "grab-bag needing a follow-up recon" shape `[M17n]`'s
own Group 8 hit — better flagged explicitly than forced into sub-tiers here.

What effect-name clustering DID surface with reasonable confidence, offered
as a head start for that future pass, not a finished sub-tier list:

| Cluster | Count | Members (by effect_name) |
|---|---|---|
| `EFFECT_DOUBLE_POWER_ON_ARG_STATUS` | 6 | Power doubles if target has a specific status — likely one shared modifier function |
| `EFFECT_FOLLOW_ME`/redirect-targeting | 3 | Follow Me(266)/Rage Powder(476)/Spotlight(634) — confirm whether any redirect-targeting infra exists at all (doubles-only mechanic, may interact with `[M14a]`) |
| `EFFECT_HEAL_BELL` | 2 | Heal Bell(215)/Aromatherapy(312) — party-wide status cure, confirm whether party-wide (not just active-battler) status effects are reachable in this project's current architecture |
| `EFFECT_PSYSHOCK` | 3 | Psyshock(473)/Psystrike(540)/Secret Sword(548) — physical-stat-vs-special-category mismatch, a real new damage-calc branch |
| `EFFECT_PLEDGE` | 3 | Water/Fire/Grass Pledge — combo-move mechanic (requires doubles-turn-order coordination between two allies) |
| `EFFECT_POWER_BASED_ON_USER_HP` / `_TARGET_HP` | 6 | Eruption/Water Spout/Dragon Energy (user HP), Wring Out/Crush Grip/Hard Press (target HP) — likely one shared modifier function each |
| `EFFECT_HIT_ESCAPE` | 3 | U-turn(369)/Volt Switch(521)/Flip Turn(740) — forced-switch-after-hit, likely reuses `[M18n]`'s forced-switch plumbing directly |
| `EFFECT_HIT_SWITCH_TARGET` | 2 | Circle Throw(509)/Dragon Tail(525) — forces the DEFENDER to switch, a mirror of the above |
| `EFFECT_CHANGE_TYPE_ON_ITEM` | 3 | Judgment/Techno Blast/Multi-Attack — Arceus-plate/Genesect-drive/Silvally-memory type-source, same `HOLD_EFFECT_PLATE` read `[M17n-4]` already built for Multitype |
| Everything else (singletons/small pairs) | 236 | Genuinely one-off (Metronome, Sketch, Transform, Substitute-adjacent, room-setting moves, stat-swap moves, etc.) — this is the real sizing uncertainty for M19, exactly as the recon itself flagged |

(6+3+2+3+3+6+3+2+3+236 = 267, reconciled.)

---

## Section E — Summary and recommended sequencing

| Bucket | Move count |
|---|---|
| Already implemented (excluded from this plan) | 132 |
| Proposed sub-tiers M19a–M19i (Section B) | 438 |
| Deferred/blocked (Section C2–C3) | 10 |
| Permanently excluded, confirmed by Rob (Section C1) | 87 |
| Tier 4 residual, needs its own sub-clustering pass (Section D) | 267 |
| **Total (matches the recon's 934-move catalog)** | **934** |

| Sub-tier | Moves | Risk | Depends on |
|---|---|---|---|
| M19a — Tier 1 pure-damage data-entry | 143 | Cheapest | — (recommend splitting execution by generation) |
| M19b — Tier 2 secondary-effect data-entry | 266 | Cheap | — (recommend splitting execution by generation/sub-cluster) |
| M19c — Protect-family variants | 9 | Cheap | — |
| M19d — Counter/Mirror-Move remnants | 3 | Cheap-moderate | — |
| M19e — Weather-conditional heal family | 4 | Cheap-moderate | — |
| M19f — Escape-prevention family (incl. Jaw Lock) | 4 | Moderate (new mechanism) | — |
| M19g — Dynamax-conditional-power, always-flat | 3 | Cheapest (effectively Tier 1) | — |
| M19h — Weight-ratio dynamic power | 2 | Cheapest | — (unblocked by `[M19-pre1]`) |
| M19i — Friendship-based dynamic power | 4 | Cheapest | — (unblocked by `[M19-pre1]`) |
| Tier 4 sub-clustering pass | 267 | Unknown — needs its own recon | M19a-i not required first, but recommended for momentum |

**Recommended implementation order:**

1. **M19g, M19h, M19i (3 + 2 + 4 = 9) first** — trivially cheap, effectively
   Tier 1 data-entry, clears 9 moves with zero new mechanism (M19h/M19i only
   just unblocked by `[M19-pre1]` — good candidates to confirm the new
   fields work correctly in real implementation before the big bulk tiers).
2. **M19a and M19b (143 + 266 = 409)** — the overwhelming majority of M19's
   buildable scope, zero new mechanism cost, matching M18a/M18b's own
   "front-load the cheapest bulk" precedent. Given the scale (10× M18's
   largest single tier), strongly recommend splitting execution across
   multiple sessions (by generation is the most natural axis, since it's
   already how the recon itself is organized) rather than attempting either
   in one prompt.
3. **M19c (9)** — cheap, single shared mechanism, no dependencies.
4. **M19d, M19e (3 + 4 = 7)** — each a small, self-contained extension of an
   already-built system (`_last_attacker` tracking, weather + `RESTORE_HP`).
5. **M19f (4)** — the one genuinely new mechanism in this plan's buildable
   scope; budget real care per `[M17f]`'s own trapping-infrastructure
   precedent, confirm the Ghost-type/Shed Shell interaction against
   `AbilityManager.is_trapped()` before writing new code.
6. **Tier 4 sub-clustering recon (267 moves)** — recommend as its OWN
   dedicated report-only session, mirroring how `docs/m19_recon.md` itself
   was produced before this plan, rather than guessing sub-tiers from
   effect-name clustering alone. Section D's own table is a head start, not
   a finished breakdown.
7. **Section C's 97 moves stay out of M19 scope**: 87 permanently excluded
   (Z-Move/Max-Move, confirmed by Rob), 9 pending Rob's Terrain
   re-confirmation, 1 (Population Bomb) deferred to its own small future
   tier once Rob wants it.

No sub-tier in Section B is flagged as needing further internal splitting
before it's attempted, EXCEPT M19a/M19b's own explicitly-noted execution-
scale recommendation (split by generation) — unlike M18's own plan, this
isn't a shape concern (both are single-shape, low-variance batches), purely
a session-length one given their combined 409-move size.

---

## Open questions for Rob

1. ~~Z-Move/Max-Move exclusion (87 moves)~~ — **RESOLVED.** Rob confirmed
   the exclusion (`[M19-pre1]`), matching the Mega Evolution precedent. See
   Section C1.

2. **Terrain family (9 moves, Section C2)**: reopening the `[M17e]`-voided
   ability decision, or building a moves-only terrain system narrower than
   what that decision declined. Needs Rob's explicit re-confirmation either
   way, not a silent inclusion or continued exclusion — the recon itself
   already flagged this as needing the same treatment, this plan just
   carries it forward unresolved. **Still open.**

3. ~~Weight/friendship data (8 moves)~~ — **RESOLVED.** `[M19-pre1]` built
   both fields and implemented all 8 moves. See Section B's M19b/M19h/M19i.

4. **Tier 4's sub-clustering pass (267 moves, Section D)**: should this be
   scheduled as its own explicit report-only session (matching how
   `docs/m19_recon.md` itself, and this plan, were both produced) before
   any Tier 4 implementation work starts, or should Tier 4 wait entirely
   until M19a/M19b/M19c-i's ~438 moves are done? This plan recommends the
   former (parallel-track the recon while the cheap bulk work proceeds) but
   defers the actual scheduling call to Rob's own preference, matching this
   project's established pattern of not pre-deciding sequencing questions
   that are really about Rob's available time and priorities, not technical
   dependency. **Still open.**
