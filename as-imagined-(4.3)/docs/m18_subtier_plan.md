# M18 Sub-Tier Plan — Grouping the 165 Included Held Items for Implementation

**Status: PLANNING ONLY.** No implementation code, `CLAUDE.md`, `docs/decisions.md`, or
`docs/m18_item_ledger.md` was touched to produce this. This report groups
`docs/m18_item_ledger.md`'s 165 INCLUDED held items into implementable sub-tiers by
mechanic shape, mirroring the discipline `docs/m17n_recon.md` used for M17n's Group
1-8 split (cheapest/most-precedented first, new-infrastructure items sequenced
deliberately, cross-system items flagged rather than forced in). Rob reviews this
before any M18 implementation prompt gets written.

Of the 165 INCLUDED items, **15 are already implemented** (Leftovers, Lum Berry,
Choice Band, Sitrus Berry, Choice Specs, Choice Scarf, Damp/Heat/Icy/Smooth Rock,
Life Orb, Chilan Berry, Occa Berry, Heavy-Duty Boots, Utility Umbrella) and are
excluded from every count below. **150 items remain to be grouped.** Of those 150,
**11 are flagged as blocked or excluded** (Section C) rather than forced into a
sub-tier — 6 for genuine infra/data blockers, plus 5 (the confusion-nature berries,
Figy/Wiki/Mago/Aguav/Iapapa) excluded by Rob's own design call as too similar to
Sitrus Berry to be worth a separate implementation — leaving **139 items across 23
proposed sub-tiers** (Section B).

All item IDs and names below were cross-checked programmatically against
`docs/m18_item_ledger.md`'s own INCLUDED rows — every one of the 150 remaining items
appears in exactly one sub-tier or exactly one Section C entry, no duplicates, no
omissions.

---

## Section A — Mechanic-shape classification

Per this task's Step 1, every item was checked against four questions. Rather than
repeat all 150 items twice, this section summarizes the counts and the reasoning;
Section B has the full per-item breakdown.

| Classification | Count | What it means |
|---|---|---|
| **(1) Extends an existing ItemManager/AbilityManager dispatch pattern exactly** | 39 | Resist berries (16), status-cure berries (6), Oran Berry (1), the EV/Power-item Speed-halving family (7), Big Root (1), Power Herb (1), Light Clay (1), Black Sludge (1), Shed Shell (1), Safety Goggles (1), Sturdy-shape survive-lethal (2, Focus Sash/Focus Band), Room Service (1) |
| **(2) Needs a genuinely NEW mechanism, but self-contained and cheap-to-moderate** | ~85 | Type-boost dispatch family (40, one new mechanism applied broadly), species-gate family (9), crit-item-bonus (2), flinch-on-hit (2), accuracy/power flat-modifier misc (7), stat-change-reactive (4), forced-switch (2), contact-reactive family (4), status orbs (2), self-heal-on-action (1, Shell Bell), Berserk Gene + Metronome item (2), Eviolite + Assault Vest (2), Iron Ball + Air Balloon (2), Red/Blue Orb (2), Mental Herb (1, scope-narrowed), Covert Cloak (1), turn-order items (3, direct reuse of M17n-3 infra so arguably closer to category 1) |
| **(3) Touches a system outside ItemManager, or depends on data/infra this project doesn't have at all** | 6 | Adamant/Lustrous/Griseous Orb (missing species), Destiny Knot (missing Attract status), Grip Claw (missing binding-move mechanic), Loaded Dice (missing multi-hit mechanic) — see Section C. **None of the 150 items require the action-queue, EXP, or evolution-triggering systems** — Eviolite only reads static "is this species fully evolved" data already in the M15 pipeline, it doesn't trigger anything. No item in this ledger needs M22.5 or M26. |
| **(5) Excluded by design — not infra-blocked, just judged too redundant with an existing item to build separately** | 5 | Figy/Wiki/Mago/Aguav/Iapapa (confusion-nature berries) — the heal half is a trivial Sitrus-shape reuse with nothing stopping it technically, but Rob judged the family too functionally similar to the already-implemented Sitrus Berry once the nature-gated confusion half (blocked anyway — no nature data exists) is set aside. See Section C item 5. |
| **(4) Pure, trivial data-entry, zero shared-pattern complexity beyond category (1)'s existing dispatch** | subset of (1) | The 16 resist berries and 6 status-cure berries are the purest example — the generic mechanism already exists (`HOLD_EFFECT_RESIST_BERRY`, `HOLD_EFFECT_CURE_STATUS`), these rows are one `hold_effect_param`/data row each. |

The single highest-leverage finding: **40 of the 150 remaining items (27%) share one
missing mechanism** — a "+20% power to moves of type X" dispatch (the Charcoal
family, Plates, two of the type-boosting Incenses' cousins, Silk Scarf, Fairy
Feather). `ItemManager` has zero type-boost dispatch today (only
`HOLD_EFFECT_RESIST_BERRY`'s defender-side halving and `HOLD_EFFECT_PLATE`'s
Multitype type-source read exist) — building this once and batch-applying it is the
single best cost/item ratio in the entire remaining 150, exactly the shape M17n-6
found for the Normalize/"-ate" family.

---

## Section B — Proposed sub-tier breakdown (cheapest/most-precedented first)

### M18a — Type-boost dispatch (40 items) — **CHEAP** (after one new mechanism)

**New mechanism needed:** one attack-modifier function, same shape as
`ItemManager.attack_modifier_uq412` (Choice Band/Specs), keyed on "does this move's
type match the item's associated type" → ×1.2 power (UQ4.12 ≈ 4915). This is the
`HOLD_EFFECT_PLATE` gap the ledger already flagged ("`HOLD_EFFECT_PLATE` exists...
but has no power-boost read yet") — build the read once, apply it to every type-boost
item at once, including the non-Plate ones that share the identical ×1.2 shape.

Member items:
- **Charcoal family (16, Gen II):** Charcoal(426, Fire), Mystic Water(427, Water),
  Magnet(428, Electric), Miracle Seed(429, Grass), Never-Melt Ice(430, Ice), Black
  Belt(431, Fighting), Poison Barb(432, Poison), Soft Sand(433, Ground), Sharp
  Beak(434, Flying), Twisted Spoon(435, Psychic), Silver Powder(436, Bug), Hard
  Stone(437, Rock), Spell Tag(438, Ghost), Dragon Fang(439, Dragon), Black
  Glasses(440, Dark), Metal Coat(441, Steel; evolution-trigger half is non-battle,
  out of scope).
- **Silk Scarf(425, Normal)** — Gen III, fills the family's Normal-type gap.
- **Fairy Feather(799, Fairy)** — Gen IX override, fills the family's Fairy-type gap.
- **Type-boost Incenses (5):** Sea Incense(404, Water), Odd Incense(406, Psychic),
  Rock Incense(407, Rock), Rose Incense(410, Grass), Wave Incense(409, Water —
  duplicate of Sea Incense's effect).
- **Plates (17, Gen IV + Pixie Plate):** Flame(250, Fire), Splash(251, Water),
  Zap(252, Electric), Meadow(253, Grass), Icicle(254, Ice), Fist(255, Fighting),
  Toxic(256, Poison), Earth(257, Ground), Sky(258, Flying), Mind(259, Psychic),
  Insect(260, Bug), Stone(261, Rock), Spooky(262, Ghost), Draco(263, Dragon),
  Dread(264, Dark), Iron(265, Steel), Pixie(266, Fairy).

**Recommend this be M18's first sub-tier**, matching M17n-6's precedent of front-loading
the highest-leverage shared mechanism rather than leaving it in a grab-bag.

### M18b — Berry/misc data-entry on an EXISTING exact dispatch (23 items) — **CHEAPEST**

No new mechanism at all — every one of these is a data row against a dispatch that
already exists and is already generic.

- **Type-resist berries (16):** Passho(551, Water), Wacan(552, Electric), Rindo(553,
  Grass), Yache(554, Ice), Chople(555, Fighting), Kebia(556, Poison), Shuca(557,
  Ground), Coba(558, Flying), Payapa(559, Psychic), Tanga(560, Bug), Charti(561,
  Rock), Kasib(562, Ghost), Haban(563, Dragon), Colbur(564, Dark), Babiri(565,
  Steel), Roseli(566, Fairy). Direct extension of `HOLD_EFFECT_RESIST_BERRY` — Occa
  and Chilan already prove the generic mechanism works.
- **Status-cure berries (6):** Cheri(514, paralysis), Chesto(515, sleep), Pecha(516,
  poison), Rawst(517, burn), Aspear(518, freeze), Persim(521, confusion). Direct
  extension of `HOLD_EFFECT_CURE_STATUS` (Lum Berry) — narrower (one status) instead
  of "any status."
- **Oran Berry(520):** flat 10 HP heal at the same HP-threshold trigger Sitrus
  already uses, just a flat amount instead of a percentage.

### M18c — Berry misc-effect on the existing HP-threshold trigger shape (10 items) — **CHEAP**

All reuse Sitrus Berry's existing "HP falls to a threshold → trigger, consume"
shape; only the *effect* differs, and each effect is itself a small, already-built
primitive (stat-stage change, crit bonus from M18e, turn-order-first from M18l-style
logic, or a flat accuracy/heal bump).

Liechi(567, +1 Atk @25%), Ganlon(568, +1 Def @25%), Salac(569, +1 Spe @25%),
Petaya(570, +1 SpA @25%), Apicot(571, +1 SpD @25%), Starf(573, +2 random stat @25%),
Lansat(572, +1 crit stage @25% — depends on M18e's crit-bonus mechanism), Custap(576,
act-first-in-bracket @ low HP — depends on M18l's turn-order mechanism), Micle(575,
+accuracy on next move @ low HP), Enigma(574, heal 1/4 max HP when hit
super-effectively — inverts the resist-berry trigger condition instead of the
HP-threshold one, grouped here for berry-family cohesion).

### M18d — Leppa Berry + contact-retaliation berries (3 items) — **CHEAP**

Leppa Berry(519, restore 10 PP to one move) — small standalone mechanism, no
precedent needed, self-contained. Jaboca Berry(577, damages attacker 1/8 max HP on a
physical contact hit) and Rowap Berry(578, same, special hit) — reuse
`move_makes_contact()`/hit-reactive-retaliation shape (same family as M18p's Rocky
Helmet, sequence together if convenient).

### M18e — Crit-stage item bonus (2 items) — **CHEAP**

Scope Lens(471), Razor Claw(492) — both +1 crit-ratio stage. `DamageCalculator._roll_crit`
already takes an `ability_bonus: int` parameter (built for Super Luck) — adding a
parallel `item_bonus` is a direct, tiny extension of an already-parameterized
function. Lansat Berry (M18c) depends on this being built first.

### M18g — Species-gated stat/crit items (9 items) — **CHEAP-MODERATE**

**New mechanism needed:** a small "species-gate" check (holder's species ID ==
item's expected species) feeding into the existing stat-modifier/crit-bonus
machinery — precedented in shape by M17n-4's Multitype/RKS System held-item read,
just gated on species instead of ability.

Light Ball(392, Pikachu, Atk+SpAtk ×2), Leek/Stick(393, Farfetch'd/Sirfetch'd, +crit
stage), Thick Club(394, Cubone/Marowak, Atk ×2), Lucky Punch(395, Chansey, +crit
stage), Metal Powder(396, Ditto, Def ×2 untransformed), Quick Powder(397, Ditto, Spe
×2 untransformed), Deep Sea Scale(398, Clamperl, SpDef ×2), Deep Sea Tooth(399,
Clamperl, SpAtk ×2). All 8 species (Pikachu, Farfetch'd, Cubone, Marowak, Chansey,
Ditto, Clamperl) confirmed present in `data/pokemon.json` — none of these are
species-blocked.

**Soul Dew(400)** rides along but is sequenced last in this tier: it needs BOTH this
tier's species-gate mechanism AND M18a's type-boost dispatch (+20% Psychic/Dragon
power for Latios/Latias specifically). Latios and Latias are confirmed present in the
roster — this closes the ledger's own "pending confirmation" flag. Not blocked.

### M18h — EV/Power-item Speed-halving family (7 items) — **CHEAPEST**

Macho Brace(418), Power Weight(419), Power Bracer(420), Power Belt(421), Power
Lens(422), Power Band(423), Power Anklet(424). **This project has no EV system at
all** (confirmed via grep — no `ev_gain`/`EV_GAIN` anywhere), so the EV-doubling half
of all 7 items is permanently moot; the ONLY battle-visible effect is "halve the
holder's Speed," identical in shape to `ItemManager.apply_speed_modifier`'s existing
Choice Scarf branch. Direct one-line-per-item extension of an existing function.

### M18i — Status Orbs (2 items) — **CHEAP**

Flame Orb(445), Toxic Orb(446) — self-inflict burn/badly-poison at the end of the
holder's first turn held. New but small, fully self-contained "apply status to self
after N turns held" mechanism — no dependency on anything else in this plan.

### M18j — Power/accuracy flat-modifier misc (7 items) — **CHEAP**

**Power (3):** Muscle Band(475, +10% physical power), Wise Glasses(476, +10% special
power), Expert Belt(477, +20% power on super-effective hits) — direct extensions of
`attack_modifier_uq412`'s existing shape (same category-gated pattern Choice
Band/Specs already use).
**Accuracy/evasion (4):** Wide Lens(474, +10% accuracy), Zoom Lens(482, +20%
accuracy if moving after target — needs a "did I act after my target this turn"
check, slightly more conditional than the others), Bright Powder(459, lowers foe's
accuracy vs. holder), Lax Incense(405, same as Bright Powder) — new item-keyed
extension of `AbilityManager.accuracy_modifier_percent`'s existing
attacker-ability/defender-ability branch structure, adding attacker-item/defender-item
branches alongside it.

### M18k — Flinch-on-hit items (2 items) — **CHEAP-MODERATE**

King's Rock(465), Razor Fang(493) — both 10% chance to add a flinch as a bonus
secondary effect of any of the holder's attacking hits. New "item grants bonus flinch
chance" hook, but reuses the existing `mon.flinched` flag and the existing
secondary-effect-roll machinery (same roll infra `[M17a]`'s Serene Grace touches).

### M18l — Turn-order items (3 items) — **CHEAPEST**

Quick Claw(462, ~20% chance to act first in-bracket), Full Incense(408, always acts
last in-bracket), Lagging Tail(485, same as Full Incense). Direct reuse of M17n-3's
already-built `AbilityManager.quick_draw_activates` (probabilistic-first) and
`has_slow_turn_order_effect` (always-last) shapes — these are the exact same
turn-order sort hooks, just item-keyed instead of ability-keyed.

### M18m — Stat-change-reactive consumed items (4 items) — **MODERATE**

Weakness Policy(502, super-effective hit → +2 Atk/SpAtk, consumed — reuses the
resist-berry-style "was this hit super-effective" trigger condition), White
Herb(460, once: restores all lowered stats to 0, consumed — needs a new "on any stat
lowered" hook plus a stat-reset), Eject Pack(509, any stat lowered → forced switch,
consumed — needs the same "on any stat lowered" hook as White Herb, PLUS M18n's
forced-switch plumbing), Mirror Herb(769, once: copies an opponent's positive stat
change onto the holder, consumed — direct reuse of the Opportunist ability's
existing "copy opponent's stat increase" shape from `[M17n-8]`). The `stat_stage_changed`
signal and `StatusManager.apply_stat_change` already exist as the building blocks;
the new piece is wiring a consumption check into that path for items specifically.

### M18n — Forced-switch items (2 items) — **CHEAP**

Red Card(498, forces the ATTACKER to switch out after hitting the holder, consumed),
Eject Button(501, forces the HOLDER to switch out after being hit, consumed). Direct
reuse of `BattleManager._do_forced_switch_in` — the exact mechanism Roar/Whirlwind
already use. M18m's Eject Pack depends on this same plumbing.

### M18o — Survive-lethal-hit items (2 items) — **CHEAPEST of the ledger's "needs new mechanism" items**

Focus Sash(481, survives a lethal hit at 1 HP if at full HP), Focus Band(469, 10%
chance to survive a lethal hit at 1 HP regardless of starting HP). Direct reuse of
the Sturdy ability's already-implemented "survive lethal from full HP at 1 HP" hook
(`battle_manager.gd:3276`) — Focus Band just relaxes the "must be at full HP" gate to
a flat probability roll instead. The ledger listed these as "needs new mechanism" but
that mechanism (survive-lethal) already exists for Sturdy; this tier is nearly free.

### M18p — Contact-reactive damage family (4 items) — **CHEAP-MODERATE**

Rocky Helmet(496, 1/6 max HP retaliation on contact), Sticky Barb(489, 1/8 max HP
damage/turn to holder — plus "transfers to the attacker on contact," a genuinely
small NEW item-swap-on-contact sub-mechanism, sequence this piece after the base
retaliation shape), Protective Pads(507, blocks contact-triggered side effects AGAINST
the holder — the inverse/gate of this whole family, sequence last so it has
something to gate), Punching Glove(760, +10% punching-move power, strips the contact
flag from the holder's own punching moves — direct reuse of M17n-5's
`move_makes_contact()`/`punching_move` flag wiring). All lean on `move_makes_contact()`,
the same wrapper Tough Claws/Iron Fist/Strong Jaw already use.

### M18q — Self-heal-on-action items (2 items) — **CHEAP**

Big Root(491, +30% HP recovered by drain moves) — direct modifier on the existing
`move.drain_percent`/`drain_heal` calculation, essentially free. Shell Bell(473,
heals 1/8 of damage dealt per hit) — needs a small new "heal holder on dealing
damage" hook, still simple and self-contained.

### M18r — Standalone reuses of already-built mechanisms (7 items) — **CHEAPEST, grab-bag by convenience only**

Each of these is a near-zero-cost extension of a DIFFERENT existing mechanism —
grouped here purely for sequencing convenience, not because they share a shape with
each other:
- Power Herb(480) — direct reuse of M6's charge-and-release move mechanism (Solar
  Beam/Dig/Fly); skips the charge turn once.
- Light Clay(478) — direct `_side_conditions` duration modifier, same dictionary
  `[M16c]`'s Reflect/Light Screen/Aurora Veil already use.
- Black Sludge(487) — direct Leftovers-shape variant (heals Poison-types 1/16,
  damages all others 1/16) plus one type check.
- Blunder Policy(511) — direct reuse of the existing `move_missed` signal (already
  emitted for Sturdy's OHKO block) as a trigger; +2 Speed, consumed.
- Room Service(512) — direct reuse of the existing `trick_room_turns` field; -1
  Speed on switch-in while Trick Room is active, consumed.
- Shed Shell(490) — direct reuse of `AbilityManager.is_trapped()` / `[M17f]`'s
  trapping-check infra; holder bypasses trapping for voluntary switches.
- Safety Goggles(504) — direct reuse of TWO existing mechanisms at once:
  `blocks_weather_chip_damage`'s Overcoat shape (`[M17d]`) and the Grass-type
  powder-move-immunity exemption pattern (`[M17.5]`).

### M18s — Eviolite + Assault Vest (2 items) — **MODERATE**

Eviolite(494, +50% Def/SpDef if the holder is not fully evolved) — needs a
species/evolution-data lookup ("does this species have any further evolution");
`docs/decisions.md`'s M15 Task 4a entry confirms evolution data is already in the
data pipeline, so this is a read against existing data, not new data collection.
Assault Vest(503, +50% SpDef, but the holder cannot select status-category moves) —
needs a new move-legality restriction (a different SHAPE from choice-lock's
"only this one move," closer to "no move of this category," self-contained).

### M18t — Iron Ball + Air Balloon (2 items) — **MODERATE**

Iron Ball(484, Speed halved + grounds the holder) — Speed half reuses the same
Choice-Scarf-style speed-dispatch shape as M18h; the "grounds the holder" half
extends `AbilityManager.is_grounded()` (`[M16d]`) with a held-item branch. Air
Balloon(497, grants Ground-move immunity, popped on any hit taken) — genuinely new
single-use-immunity mechanism; touches the type-immunity pipeline (the same area
Wonder Guard's restructuring warning in `docs/m17n_recon.md` flagged as delicate) —
budget real attention here even though it's only one item.

### M18u — Berserk Gene + Metronome item (2 items) — **MODERATE**

Berserk Gene(798, sharply raises Attack but confuses the holder, then is consumed) —
new small "self-target stat raise + self-inflict confusion" mechanism; confusion
infliction already exists generically (Confuse Ray etc. from M3), this just targets
the holder instead of an opponent. Metronome item(483, power ramps +20% per
consecutive use of the same move, up to +100% at 5 uses) — needs a new small
"consecutive same-move-use counter" piece of per-Pokémon state, self-contained.

### M18v — Mental Herb (1 item) — **MODERATE, narrowed scope**

Cures infatuation once, consumed. **Infatuation/Attract does not exist anywhere in
this project** (confirmed: an M17n-era `ability_manager.gd` comment states
"infatuation/taunt — both N/A, neither exists in this project"). However, Gen 5+
widens Mental Herb to also cure Taunt/Encore/Torment/Disable/Heal Block — and
Disable and Encore ARE already implemented (M7, per `[M17n-1]`'s own Aroma Veil
note). Recommend scoping Mental Herb to **"cures Disable or Encore"** for now (both
confirmed present), rather than either blocking on Attract entirely or
mis-implementing a no-op. Revisit if Attract/Taunt/Torment/Heal Block are ever added.

### M18w — Red Orb / Blue Orb (2 items) — **MODERATE**

Red Orb(290, Groudon), Blue Orb(291, Kyogre) — trigger automatic Primal Reversion on
switch-in. Groudon and Kyogre are both confirmed present in `data/pokemon.json` (this
resolves the ledger's own "pending Dialga in species roster"-style caveat — these two
are NOT blocked, unlike M18's Section C orbs below). The target abilities (Desolate
Land, Primordial Sea) are already implemented (`[M17d]`) — the only missing piece is
a new "orb + matching species → auto form-change + set ability, on switch-in"
mechanism. This is a genuinely new trigger shape (first "item forces a form/ability
change" case), but self-contained and low-risk given the destination abilities
already work.

### M18x — Covert Cloak (1 item) — **MODERATE-HIGH**

Blocks ALL secondary/additional effects of moves used against the holder. Not
infra-blocked, but a wide-but-shallow gate: it needs to intercept every existing
secondary-effect application point (status infliction, stat-lowering secondaries,
flinch chance, etc.), the same shape M17n Group 8 flagged for Magic Guard/Good As
Gold. Budget this as a "touches many systems a little" item, not a quick add, despite
being conceptually simple.

---

## Section C — Items better left out of M18 entirely (11 items)

None of these belong to an already-planned FUTURE milestone (M22.5's action-queue
work and M26's catching/encounter system were both checked explicitly — no item in
this ledger depends on either). Rob has reviewed this section and confirmed the
Orbs' disposition (item 1) and the confusion-nature berries' disposition (item 5)
below; items 2-4 carry a build-order recommendation rather than an open question.

1. **Adamant Orb(401), Lustrous Orb(402), Griseous Orb(403)** — **OUT OF SCOPE,
   confirmed by Rob.** Dialga, Palkia, and Giratina are **not present anywhere in
   `data/pokemon.json`** (confirmed via direct search) — unlike Latios/Latias
   (present, unblocks M18g's Soul Dew) and Groudon/Kyogre (present, unblocks M18w),
   these three species genuinely don't exist in this project's roster at all. Unlike
   items 2-4 below, this isn't a "build the prerequisite, then the item falls out
   cheap" situation — adding three legendary species to the roster is a roster
   decision with no relation to M18's item work, not a small unblocking step. Drop
   these three from consideration entirely; no further tracking needed unless Rob
   independently decides to expand the species roster for unrelated reasons.

2. **Destiny Knot(486)** — BLOCKED. Mirrors infatuation back onto its inflicter, but
   infatuation/Attract doesn't exist as a status anywhere in this project (same
   "N/A, neither exists" note cited under M18v). This is the identical "no-op
   dependency" shape M17n already used to defer Cute Charm and Oblivious (both
   abilities that also depend on Attract) — recommend deferring Destiny Knot
   alongside those two for consistency, revisit together if Attract is ever added.
   **Build-order recommendation: implement the Attract status FIRST, not a partial
   item stub.** There is nothing for item-side logic to hook into today — a
   "mirrors infatuation" function with no infatuation status ever fires is
   unreachable dead code, the same bar this project already declines to cross
   (see Klutz's documented "recorded, not reachable" exceptions, which only apply
   when the exception case is real, not when the whole mechanism is absent).
   Building Attract first also has payoff beyond this one item — it directly
   unblocks the already-deferred Cute Charm and Oblivious abilities from M17n.
   Once Attract exists, Destiny Knot becomes a small, cheap reactive hook (same
   "mirror an inflicted status back at its source" shape as Mirror Herb/Opportunist).

3. **Grip Claw(488)** — BLOCKED. Extends binding-move duration to 7 turns, but no
   binding-move mechanic (Wrap/Bind/Fire Spin/Clamp/Whirlpool/Sand Tomb/Infestation/
   Magma Storm's actual turn-locked recurring-damage effect) is implemented anywhere
   in `battle_manager.gd` — those moves exist only as plain data rows today. This is
   a pre-existing gap in the move-effects pipeline (conceptually the same "Tier 4
   one-off mechanic" bucket as M7), not something M18's held-item work should build
   item-side plumbing for ahead of the move mechanic it modifies.
   **Build-order recommendation: implement the binding-move mechanic FIRST, not a
   partial item stub.** "Extend the binding duration to 7 turns" has no turn counter
   to extend until binding moves exist — item-side logic here would be provably
   unreachable, same reasoning as Destiny Knot above. Building binding moves first
   also has payoff beyond Grip Claw: it fixes 8 real moves (Wrap, Bind, Fire Spin,
   Clamp, Whirlpool, Sand Tomb, Infestation, Magma Storm) that currently resolve as
   plain single-hit damage with no trap/DoT effect at all — a bigger, independently
   worthwhile fix. Once binding moves exist, Grip Claw becomes a one-line duration
   modifier (5 turns → 7). Recommend Grip Claw wait until binding moves are actually
   implemented, whichever milestone that ends up being.

4. **Loaded Dice(762)** — BLOCKED, per the ledger's own correct flag. No multi-hit
   move mechanism exists anywhere in this codebase — confirmed independently via the
   same M17n-era comment that already deferred the Skill Link ability for the
   identical reason ("multi_hit/strike_count are dormant... no multi_hit mechanic
   exists anywhere in this codebase's battle logic"). `MoveData.strike_count` and
   `MoveData.multi_hit` fields exist but nothing reads them in `BattleManager` today.
   **Build-order recommendation: implement the multi-hit move mechanic FIRST, not a
   partial item stub**, for the same "nothing to hook into yet" reasoning as items 2
   and 3 above. Building multi-hit first has the widest payoff of all three
   build-first cases here — it simultaneously unblocks the Skill Link ability (M17n)
   AND fixes however many currently-mis-resolving moves rely on `strike_count`/
   `multi_hit` (e.g. Bullet Seed, Icicle Spear, Rock Blast, Double Slap). Once
   multi-hit exists, Loaded Dice becomes a one-line "always take the max end of the
   hit-count roll" modifier. Recommend Loaded Dice stay out of M18 and get revisited
   together with Skill Link and the base multi-hit moves once that infra is
   eventually built — no current milestone owns this gap.

5. **Figy(524), Wiki(525), Mago(526), Aguav(527), Iapapa(528)** — **EXCLUDED,
   confirmed by Rob: functionally too similar to Sitrus Berry to be worth building
   as distinct items.** Unlike items 2-4 above, this isn't an infra blocker — the
   heal-at-low-HP half is a trivial, cheap Sitrus-shape reuse with nothing
   technically stopping it. The exclusion is a design call: once the
   nature-dependent confusion half is set aside (this project has no
   nature/likes-dislikes data anywhere — no `nature` field on `PokemonSpecies`, no
   `NatureData` class), all five berries collapse to "heal 1/3 max HP at low HP,"
   which duplicates Sitrus Berry's already-implemented effect closely enough that a
   separate implementation isn't worth it. Drop this family from M18 scope entirely;
   revisit only if a nature system is ever built AND Rob decides the
   confusion-on-dislike differentiation is worth adding at that point.

---

## Section D — Summary and recommended sequencing

| Bucket | Item count |
|---|---|
| Already implemented (excluded from this plan) | 15 |
| Proposed sub-tiers M18a–M18x (23 tiers, M18f retired — see below) | 139 |
| Deferred to Section C (blocked or excluded, no owning milestone) | 11 |
| **Total INCLUDED (matches the ledger)** | **165** |

`M18f` (Confusion-nature berries) was retired from Section B and folded into
Section C as item 5 (Figy/Wiki/Mago/Aguav/Iapapa, excluded — too similar to Sitrus
Berry) rather than renumbering every subsequent letter; the gap in the sequence
below is intentional, not a typo.

| Sub-tier | Items | Risk | Depends on |
|---|---|---|---|
| M18a — Type-boost dispatch | 40 | Cheap | — |
| M18b — Berry/misc exact-dispatch data-entry | 23 | Cheapest | — |
| M18c — Berry HP-threshold misc-effect | 10 | Cheap | M18e, M18l (partial) |
| M18d — Leppa + contact-retaliation berries | 3 | Cheap | — |
| M18e — Crit-stage item bonus | 2 | Cheap | — |
| M18g — Species-gated stat/crit + Soul Dew | 9 | Cheap-moderate | M18a (Soul Dew only) |
| M18h — EV/Power-item Speed-halving family | 7 | Cheapest | — |
| M18i — Status Orbs | 2 | Cheap | — |
| M18j — Power/accuracy flat-modifier misc | 7 | Cheap | — |
| M18k — Flinch-on-hit items | 2 | Cheap-moderate | — |
| M18l — Turn-order items | 3 | Cheapest | — |
| M18m — Stat-change-reactive consumed items | 4 | Moderate | M18n (Eject Pack) |
| M18n — Forced-switch items | 2 | Cheap | — |
| M18o — Survive-lethal-hit items | 2 | Cheapest (of "new mechanism" flags) | — |
| M18p — Contact-reactive damage family | 4 | Cheap-moderate | — |
| M18q — Self-heal-on-action items | 2 | Cheap | — |
| M18r — Standalone reuses (grab-bag by convenience) | 7 | Cheapest | — |
| M18s — Eviolite + Assault Vest | 2 | Moderate | — |
| M18t — Iron Ball + Air Balloon | 2 | Moderate | — |
| M18u — Berserk Gene + Metronome item | 2 | Moderate | — |
| M18v — Mental Herb (narrowed scope) | 1 | Moderate | — |
| M18w — Red Orb / Blue Orb | 2 | Moderate | — |
| M18x — Covert Cloak | 1 | Moderate-high | — |

**Recommended implementation order:**

1. **M18a (type-boost dispatch, 40 items) first** — the single highest-leverage new
   mechanism in the whole ledger, same "build once, batch-apply" logic M17n-6 used
   for Normalize/the "-ate" family.
2. **M18b (23) and M18h (7) next** — pure data-entry / near-pure data-entry against
   mechanisms that already fully exist; good for rebuilding momentum after a
   higher-effort tier,30 items for near-zero marginal mechanism cost.
3. **M18e, M18l, M18n, M18o, M18q, M18r (2+3+2+2+2+7 = 18 items)** — each a small,
   independent, near-zero-cost extension of an already-built mechanism (Super Luck's
   crit param, M17n-3's turn-order hooks, Roar/Whirlwind's forced-switch, Sturdy's
   survive-lethal, drain-heal math, and six other one-off reuses respectively).
   Cluster these together as a "cheap wins" pass — order within the cluster doesn't
   matter.
4. **M18c (10)** — depends on M18e and M18l being done first (Lansat needs the crit
   bonus, Custap needs the turn-order hook); sequence right after cluster 3.
5. **M18d, M18g, M18j, M18k, M18p (3+9+7+2+4 = 25 items)** — each needs one small new
   hook (species-gate, item-keyed accuracy branch, bonus-flinch roll, contact-family
   retaliation) but no cross-item dependencies; batch together as "one new hook per
   sub-tier, several sub-tiers per session."
6. **M18i, M18m (2+4 = 6 items)** — M18m needs M18n's forced-switch plumbing (already
   built by step 3) for Eject Pack; otherwise independent.
7. **M18s, M18t, M18u, M18v, M18w (2+2+2+1+2 = 9 items) last among the "moderate"
   tier** — each self-contained but each touches a slightly different system
   (evolution data, groundedness, self-confusion, cross-status scoping, form-change
   triggers) with no shared infra to batch — treat as five small independent passes.
8. **M18x (Covert Cloak, 1 item) get its own dedicated pass**, not tacked onto the
   end of a larger tier — its "touches many systems a little" shape is exactly the
   kind of thing `docs/m17n_recon.md` warned shouldn't be rushed at the tail of a
   grab-bag (same warning that applied to Wonder Guard in M17n Group 5).
9. **Section C's 11 items stay out of M18 scope entirely.** 6 are genuine blockers
   (missing species for the 3 Orbs, missing Attract status, missing binding-move
   mechanic, missing multi-hit mechanic) to be resolved by some other, currently
   unscheduled piece of work; 5 (the confusion-nature berries) are excluded by
   design, not blocked — no future trigger needed unless Rob revisits the
   nature-system question independently.

No sub-tier here is flagged as needing further splitting before it's attempted (M18a
and M18b are the largest at 40 and 23 items respectively, but both are single-shape,
low-variance batches — unlike M17n's Group 8, there's no genuine grab-bag requiring a
follow-up recon pass here).
