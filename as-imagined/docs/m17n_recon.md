# M17n Pre-Recon: Grab-Bag Scoping + Deferred-M17m Ability Audit

Report-only. No implementation in this pass. Written as the milestone-closing recon for
M17 — every ability ID from 1-318 is now accounted for as implemented, excluded, or
remaining, with the remaining 121 organized into a proposed sub-tier split.

## Baseline confirmed

Direct foreground sweep, `pkill`/`timeout` discipline: **34 `.tscn` files, 1766 total
assertions, 0 failures** — matches `[M17m]`'s decisions.md entry exactly, no drift.

## Methodology, and a discrepancy worth flagging up front

This session's task prompt cited "318 total IDs − 61 excluded" as if that number were
already written down in `docs/m17_recon.md`. **It isn't** — grepped the recon doc,
`docs/decisions.md`, and `CLAUDE.md` directly for "61 excl"/"245 remaining"/"scope
finalized" and got zero matches in any of the three actual project docs. The "61
excluded, 245 remaining" figure only appears in a past git commit message summary (for
the M17-recon-authoring commit), which is not itself an authoritative project document.
Per standing "verify, don't assume" discipline, this recon re-derived the exclusion
count from scratch rather than trusting that number — **the re-derivation independently
lands on exactly 61 excluded**, so the commit message's figure checks out, but it was
confirmed, not assumed. The reasoning is laid out in full below so the number is
reproducible instead of quoted.

**Re-derivation method:**
1. Extracted all 318 canonical ID→name pairs directly from
   `include/constants/abilities.h` (313 literal `= NNN` entries + the 6 symbolic ones
   already known from `docs/m17_recon.md` Section 3/12: Tangled Feet 77, Pickpocket 124,
   Aroma Veil 165, Stamina 192, Intrepid Sword 234, Lingering Aroma 268).
2. Extracted the full IMPLEMENTED set directly from `ability_manager.gd`'s own
   `const ABILITY_*` declarations (not from any decisions.md summary table) — **136
   ability IDs** (137 constants minus `ABILITY_NONE`).
3. Reconstructed the EXCLUDED set from every exclusion decision actually recorded across
   `docs/m17_recon.md` Sections 8/13 and `docs/decisions.md`'s `[M17a]` through `[M17m]`
   entries (see the itemized breakdown below) — **61 ability IDs**.
4. `remaining = {1..318} − implemented − excluded` — verified no overlap between the two
   sets, verified `136 + 61 + remaining = 318` exactly. **121 ability IDs remain.**

## The excluded set — 61 IDs, itemized and re-confirmed

| Group | Count | IDs | Source |
|---|---|---|---|
| Already-decided pre-M17 | 2 | Imposter (150), Bad Dreams (123) | `m17_recon.md` Sections 3/7, locked before M17a |
| Section 8.1 — Terastallization-bound | 3 | Tera Shift (307), Tera Shell (308), Teraform Zero (309) | `m17_recon.md` §8.1, Terapagos-exclusive |
| Section 8.3 — hack-custom/non-canonical | 6 | Dragonize (312), Eelevate (313), id 314 ("-------"), Mega Sol (315), Fire Mane (316), id 317 ("-------") | `m17_recon.md` §8.3 |
| Section 8.6 — Commander | 1 | Commander (279) | `m17_recon.md` §8.6, Tatsugiri+Dondozo two-party-member gimmick |
| Section 8.4 — Mega/battle-form-bound group | 11 | Zen Mode (161), Stance Change (176), Schooling (208), Disguise (209), Battle Bond (210), Power Construct (211), Shields Down (197), Ice Face (248), Hunger Switch (258), Gulp Missile (241), Zero to Hero (278) | `m17_recon.md` §8.4; confirmed treated as out-of-scope in `[M17g]`'s decisions.md entry ("NONE of these 16 [cantBeSuppressed form-mechanics] are implemented... already out of scope") — **flagging this status as inferred-from-precedent, not a documented explicit Rob approval of one of §8.4's 3 options; worth a one-line confirmation before M17n locks its scope** |
| Section 13.1 — legendary/mythical/UB sweep | 23 | Victory Star (162), Dark Aura (186), Fairy Aura (187), Aura Break (188), Turboblaze (163), Teravolt (164), Soul-Heart (220), Beast Boost (224), Full Metal Body (230), Shadow Shield (231), Prism Armor (232), Neuroforce (233), Intrepid Sword (234), Dauntless Shield (235), Transistor (262), Dragon's Maw (263), Chilling Neigh (264), Grim Neigh (265), As One–Ice Rider (266), As One–Shadow Rider (267), Unseen Fist (260), Toxic Chain (305), Poison Puppeteer (310) | `m17_recon.md` §13.1 — **Air Lock (76) is explicitly KEPT** (it's the pre-existing precedent example the section opens with, not one of the 23 new findings) — confirmed still unimplemented, still in scope, placed in this recon's remaining set below |
| Section 13.3 — Mega-exclusive-only holder | 4 | Parental Bond (185), Aerilate (184), Piercing Drill (311), Spicy Spray (318) | `m17_recon.md` §13.3 |
| Terrain-reliant group | 10 | Electric Surge (226), Psychic Surge (227), Misty Surge (228), Grassy Surge (229), Surge Surfer (207), Grass Pelt (179), Quark Drive (282), Mimicry (250), Hadron Engine (289), Seed Sower (269) | `[M17d]`'s decisions.md "Next tier" note + `CLAUDE.md`'s M17d status line: "M17e (Terrain system) is void... all 10 terrain-reliant abilities excluded" |
| Orichalcum Pulse | 1 | Orichalcum Pulse (288) | `[M17d]` decisions.md: reclassified Koraidon-exclusive per Rob's updated legendary-exclusivity standard, corrects Section 11's original "keep" recommendation |

**2 + 3 + 6 + 1 + 11 + 23 + 4 + 10 + 1 = 61.** Cross-checked for zero overlap with the
136-ID implemented set (confirmed programmatically).

Note: Primordial Sea (189) / Desolate Land (190) / Delta Stream (191) were also flagged
for reconsideration under this same stricter standard (`m17_recon.md` §13.2) but Rob's
explicit call — recorded in `[M17d]`'s decisions.md entry — was to KEEP and implement
them anyway. They are correctly in the IMPLEMENTED set (M17d), not excluded. Listed here
only so this recon doesn't look like it forgot about §13.2.

## The 121 remaining IDs, folded into a proposed M17n sub-tier split

The five abilities `[M17m]`'s own decisions.md entry explicitly flagged as deferred and
unscheduled (Wonder Guard 25, Scrappy 113, Overcoat 142, Normalize 96, Mind's Eye 300)
are folded into this list at Group 5 below, per this recon's explicit purpose — they do
NOT get a special separate tier; they belong with the rest of the type-effectiveness
leftovers they were originally grouped with in `m17_recon.md`'s pre-addendum Bucket E.

All mechanic notes below are carried forward from `docs/m17_recon.md`'s own
classification tables (Sections 4/5, 9) rather than re-derived from source in this pass
— per that report's own stated confidence level, treat these as "high confidence, not
exhaustively re-verified," and re-check each one against source directly before writing
any implementation prompt, the same discipline every M17a-m tier applied at its own
Step 0.

### Group 1 — Status-immunity family + simple no-ops (22 abilities, cheapest, most precedented)

The largest single precedented shape in the remaining set: every M8-established
`StatusManager.try_apply_status`-style immunity hook, batched together.

Insomnia (15), Vital Spirit (72) — same as Insomnia; Immunity (17); Limber (7); Water
Veil (41); Magma Armor (40); Inner Focus (39) — flinch immunity; Own Tempo (20) —
confusion-infliction immunity; Shield Dust (19) — blocks secondary effects targeting the
holder; Soundproof (43) + Bulletproof (171) — move-flag immunity (`sound_move`/needs a
new `ballistic` `MoveData` flag); Leaf Guard (102) — status immunity gated on sun;
Early Bird (48) — sleep-counter decrements 2×, simple `StatusManager` tweak, batched
here for thematic proximity to the sleep/status family; Aroma Veil (165) — self+ally
immune to Taunt/Disable/Torment/Encore/Heal Block — **partial move-dependency**: Disable
and Encore are already implemented (M7), but Taunt/Torment/Heal Block need to be
confirmed implemented or not before this ability's full scope is known; Oblivious (12) —
blocks Attract/Taunt infliction, **no-op dependency**, neither move exists yet; Cute
Charm (56) — inflicts Attract, **no-op dependency**, Attract isn't a modeled status yet;
Damp (6) — blocks explosive moves/abilities, **no-op dependency**, no
Explosion/Self-Destruct/Aftermath-triggering move exists; Illuminate (35), Honey Gather
(118) — no mechanical battle effect at all (overworld-only), document as cosmetic
no-ops matching the Anticipation/Forewarn/Frisk precedent (`[M17c]`); Run Away (50),
Pickup (53), Ball Fetch (237) — all explicitly out-of-battle-engine scope per the
Project Scope note (flee/post-battle rewards are simulator-layer, not engine-layer).

### Group 2 — Weather/terrain-adjacent evasion + speed family, plus Air Lock (8 abilities)

Sand Veil (8), Snow Cloak (81) — accuracy-formula modifiers under a weather condition;
Swift Swim (33), Chlorophyll (34), Sand Rush (146) — Speed ×2 under a weather
condition, natural home is the existing `StatusManager.effective_speed` (Slush Rush
precedent, `[M17c]`); Air Lock (76), Cloud Nine (13) — negates ALL weather effects
field-wide while active (damage modifiers AND end-turn chip/heal), **kept in scope per
Section 13.1's explicit resolution** (the established legendary-exclusive precedent
example, not itself excluded); Sand Spit (245) — reactive Sandstorm-setter on being hit,
Sand-Stream shape but hit-triggered rather than switch-in.

### Group 3 — Turn-order/priority modifiers (6 abilities)

Prankster (158), Gale Wings (177) — conditional on full HP, Triage (205), Quick Draw
(259) — probabilistic "act first in bracket," all touch the SAME turn-order/priority
resolution Trick Room (`[M16d]`)/Pursuit (`[M16e]`) already modified, as a per-move or
per-Pokémon conditional rather than a global rule (established precedent, moderate
cost); Stall (100) — always last in its bracket, same area; Mycelium Might (298) —
hybrid: its ability-ignore half is now CHEAP (M17g's `effective_ability_id`/Mold-Breaker
plumbing already exists and this recon's own `[M17g]`-adjacent note already flagged
Mycelium Might as "not in Section 13's exclusion sweep, stays in scope"), but its
turn-order-last half needs the same Stall-shape mechanism as Stall(100) itself — sequence
after Stall, not before.

### Group 4 — Damage-pipeline leftovers, Bucket A shape (27 abilities)

The same shape M17a already shipped 32 of — no new infra needed for most of these,
individually verified per-ability at implementation time same as `[M17a]`:

Sturdy (5) — survive-lethal-from-full-HP, needs a FAINT_CHECK-adjacent hook (also blocks
OHKO moves outright, cross-ref the already-implemented OHKO move effect from `[M16a]`);
Iron Fist (89) — punching-move power ×1.2, needs a `punching_move` `MoveData` flag;
Technician (101) — ≤60-power move ×1.5; Reckless (120) — recoil-move power ×1.2; Sheer
Force (125) — power ×1.3 + secondary-effect suppression, two-part; Analytic (148) —
power ×1.3 if moving last, needs turn-order-position awareness at damage-calc time;
Skill Link (92) — multi-hit moves always hit max count, verify the `multi_hit`
mechanic's actual variable-roll wiring before scoping; Super Luck (105) — crit stage +1;
Tangled Feet (77) — evasion ×2 while confused (accuracy-check function, reuses M3's
`confusion_turns`; its `.tres` placeholder already exists per the M17-recon data-pipeline
fix); Strong Jaw (173) — biting-move power ×1.5, needs a `bite` flag; Mega Launcher
(178) — pulse-move power ×1.5, needs a `pulse` flag; Stakeout (198) — power ×2 vs. a
target that switched in this turn; Water Bubble (199) — three-part (Water power ×2,
Fire damage taken ×0.5, burn-immune); Long Reach (203) — removes the "contact" flag from
all the holder's own moves; Fluffy (218) — contact damage ×0.5, Fire damage ×2, two
independent conditions; Punk Rock (244) — own sound-move power ×1.3, sound-move damage
taken ×0.5 (reuses the same `sound_move` flag Soundproof needs in Group 1 — sequence
together); Sharpness (292) — slicing-move power ×1.5, needs a `slicing` flag; Supreme
Overlord (293) — power boost scaled by fainted-party-member count, needs a new
lookup; Slow Start (112) — Atk/Spe ×0.5 for 5 turns post-switch-in, needs a turn-counter
volatile; Plus (57) / Minus (58) — SpA ×1.5 if the doubles ally has the other (or,
GEN_LATEST, either) — same `attack_modifier_uq412` function as Huge Power, doubles-only
condition, same shape as `[M17a]`'s Battery/Power Spot/Steely Spirit trio; Serene Grace
(32) — doubles all secondary-effect trigger chances, simple modifier on the existing M5
secondary-effect roll; Vessel of Ruin (284), Sword of Ruin (285), Tablets of Ruin (286),
Beads of Ruin (287) — the "Ruin quartet," a genuinely NEW "field aura" shape (persistent,
always-on while holder is present, lowers every OTHER Pokémon's stat) — confirmed via
source in the original recon; design all four together as one mechanism, not four
separate features.

### Group 5 — Type-effectiveness-pipeline leftovers, INCLUDING the 5 abilities `[M17m]` deferred (9 abilities)

This is the direct fold-in this recon exists to perform. `[M17m]`'s decisions.md entry
named exactly these five as unscheduled: **Wonder Guard (25)** — highest-risk item in
the ENTIRE M17 scope per the original recon's own flag (needs the full combined
type-effectiveness multiplier computed FIRST, then blocks unless >1.0×; this project's
current ability-immunity check happens BEFORE type effectiveness is computed, so this
needs restructuring where the check sits in the pipeline, not just a new branch — same
warning `[M17l]`'s decisions.md "Next tier" note already relayed); **Scrappy (113)** —
Normal/Fighting bypass Ghost's immunity, same pipeline area, inverse of Levitate's
pattern; **Overcoat (142)** — two-part (powder-move immunity, simple move-flag check;
weather-chip-damage immunity, touches M11's existing weather-chip code); **Normalize
(96)** — mutates the MOVE's effective type to Normal before the type-chart lookup, a
genuinely different shape from every other entry in this dispatch (mutates the move, not
the defender check); **Mind's Eye (300)** — Scrappy-shape variant (ignores Ghost's
Normal/Fighting immunity) PLUS ignores the opponent's evasion boosts, a second,
unrelated half.

Riding along with Normalize per the recon's own explicit sequencing note ("recommend
sequencing Normalize before its four '-ate' variants since they reuse its exact
mechanism once built") — three of the four "-ate" family survive exclusion (Aerilate 184
is Mega-exclusive-only, already excluded per Section 13.3 above): **Refrigerate (174)**
— Normal→Ice + power bonus; **Pixilate (182)** — Normal→Fairy + power bonus; **Galvanize
(206)** — Normal→Electric + power bonus. Also **Liquid Voice (204)** — own sound-category
moves become Water-type, a Normalize-adjacent move-mutation mechanism worth building
alongside even though it isn't literally part of the "-ate" family.

**Recommend this group be M17n's FIRST sub-tier**, not its last — it's the direct
continuation of `[M17m]`'s own work and the highest-risk item in the group (Wonder
Guard) is exactly the kind of thing that benefits from being tackled with a full,
un-rushed milestone budget rather than as an afterthought at the tail of a large
grab-bag tier.

### Group 6 — Item/berry interaction (6 abilities)

Klutz (103) — holder's held item has no effect (with canonical exceptions), touches
`ItemManager` broadly; Unnerve (127) — opponent can't eat berries at all, touches every
existing berry-trigger check (Sitrus/Lum/resist berries); Gluttony (82) — berry
HP-trigger threshold 25%→50%, modifies the existing Sitrus-Berry-precedent threshold
check; Unburden (84) — Speed ×2 after the holder's item is lost, needs an "item was just
lost" event flag; Harvest (139) — chance to regenerate a consumed berry, needs the
still-missing "last consumed item" tracking on `ItemManager` (the SAME infra gap
`[M17d]`'s decisions.md deferred Harvest over, twice now — this is the natural place to
finally build it); Cud Chew (291) — re-triggers the last berry eaten one turn later,
same "last consumed berry" tracking dependency as Harvest, design together.

### Group 7 — Type-mutation / choice-lock cheap reuses (6 abilities)

All directly reuse infrastructure this project already has, matching the
Color-Change/Protean precedent already noted in the original recon as "genuinely cheap":
Color Change (16), Protean (168), Libero (236) — all reuse the EXISTING
`_set_mon_type`/`original_types`/`_reset_mon_type` Conversion infrastructure directly;
Multitype (121), RKS System (225) — Arceus/Silvally's held-item-driven typing, same
type-mutation reuse, checked whenever the held item changes instead of on
switch-in/move-use; Gorilla Tactics (255) — locks the holder into its first-used move
plus Atk ×1.5, reuses M12's EXISTING choice-lock infrastructure directly.

### Group 8 — Contact/hit-reactive + genuinely unique grab-bag (37 abilities)

The true "grab-bag" — no single shared shape, but sub-clustered by rough proximity for
sequencing convenience. This is intentionally the largest, least-sequenced group,
matching Section 11's own framing — recommend splitting THIS group further into 2-3
passes once M17n's earlier groups are actually underway, rather than pre-committing a
fixed split now (same recommendation the original recon gave for this exact bucket).

**Contact/faint-timing:** Aftermath (106) — contact-fainting retaliation, needs to fire
from inside FAINT_CHECK specifically; Innards Out (215) — same FAINT_CHECK-timing shape,
Aftermath variant; Perish Body (253) — contact → both sides get a 3-turn countdown,
**blocked on the Perish Song move itself being unimplemented** (a move-dependency, not a
pure infra gap — verify Perish Song's status before scoping this).

**Reactive/one-off:** Corrosion (212) — bypasses Steel/Poison status-type immunity, one
flag threaded through `StatusManager`; Merciless (196) — own moves always crit vs. a
poisoned target, crit-pipeline conditional; Opportunist (290) — copies the opponent's
positive stat-stage change onto itself, genuinely unique reactive copy; Suction Cups
(21) — blocks forced switching (Roar/Whirlwind), reuses M9's existing forced-switch code
directly, cheap despite being grab-bag-classified.

**Wide-but-shallow systems:** Magic Guard (98) — blocks ALL indirect damage (recoil,
weather chip, hazard, status, Life Orb recoil), touches ~5 already-built systems
shallowly; Magic Bounce (156) — reflects certain status moves back at the attacker, a
genuinely new move-reflection mechanic; Infiltrator (151) — bypasses Substitute AND
screens, touches both the Substitute-block check and `[M16c]`'s screen-reduction check;
Good As Gold (283) — full immunity to ALL status moves, touches the move-targeting/
status-application pipeline broadly.

**Unique/standalone:** Wonder Skin (147) — flat 50% accuracy for status moves targeting
the holder, unique accuracy special case; Mirror Armor (240) — reflects an incoming
stat-lowering effect back at its source; Comatose (213) — permanently "asleep" for
interaction purposes without ever holding SLEEP status, confirmed via source to touch ~7
separate call sites, "touches many systems a little" shape; Illusion (149) — **confirmed
via the original recon's own source read that this has NO mechanical battle-calc effect
at all** in a non-visual, text/state-driven engine (only the displayed species/sprite is
faked; real stats/type/ability are always the true ones) — recommend confirming with Rob
whether this is even worth a code entry versus a documented no-op, same as
Anticipation/Forewarn/Frisk; Quick Feet (95) — removes paralysis speed penalty +1.5×
speed while statused; **this project already has an explicit TODO marker for it** (M3's
decisions.md, S19 known gap: "source gates the paralysis speed halving on `ability !=
ABILITY_QUICK_FEET`... revisit when Quick Feet is added") — implementing this ability
also requires patching that pre-existing `StatusManager` gap, not just adding a new
branch; Rivalry (79) — power modifier from attacker/target gender match — **confirmed
missing infra**: `BattlePokemon` has no assigned-gender field at all (only
`PokemonSpecies.gender_ratio`, a per-species probability) — needs new state before this
is implementable at all; Heavy Metal (134), Light Metal (135) — weight modifiers,
**no-op dependency**, no weight-based move exists in this project yet; Wind Rider (274)
+ Wind Power (277) + Electromorphosis (280) — wind-move immunity+boost / "charged-state"
family, needs a new `wind_move` `MoveData` flag; Protosynthesis (281) — generic
highest-stat boost in harsh sun, reuses the "highest stat" helper this group would need
to build once anyway (shared conceptually with the now-excluded Beast Boost, though
Beast Boost itself is out of scope) plus a weather-change-notify hook (shared
dependency with Forecast below); Screen Cleaner (251) — removes all screens from BOTH
sides on switch-in, reuses `[M16c]`'s EXISTING `_side_conditions` directly, cheap;
Costar (294) — copies an ally's stat stages (+ certain volatiles) on switch-in,
doubles-only, genuinely unique; Curious Medicine (261) — resets an ally's stat stages to
0 on switch-in, doubles-only, simple; Guard Dog (275) — Intimidate-triggered Atk +1
(instead of the usual -1) plus blocks forced switching while active, interacts directly
with the EXISTING Intimidate code path (same precedent Rattled already set); Embody
Aspect ×4 (Teal Mask 301 / Hearthflame Mask 302 / Wellspring Mask 303 / Cornerstone Mask
304) — one-time stat boost on switch-in tied to which mask is worn, needs no true
alternate-form data (unlike Section 8.4's group) — cheap IF implemented without true
mask-item gating, sequence together; Forecast (59) — Castform-only in this roster, but
the mechanic itself is TYPE-ONLY (no stat change across forms) so it reuses the Group-7
type-mutation infra directly; the only genuinely new piece is a "weather just changed,
notify all battlers" broadcast hook M11's weather system doesn't have today (shared
dependency with Protosynthesis above — sequence together); Dancer (216) — copies and
immediately re-uses any "dance"-flagged move any other Pokémon just used, needs a new
`dance` `MoveData` flag AND a move-repeat/copy mechanism, genuinely novel and the
highest-complexity item in this group after Wonder Guard/Magic Bounce; Wimp Out (193) +
Emergency Exit (194) — forces the holder to switch out below 50% HP, **needs a
genuinely new "HP-threshold forced self-switch" mechanism** this codebase doesn't have
at all (M9's switching is voluntary/forced-by-move only) — the recon explicitly floated
batching these with Regenerator/Natural Cure (`[M17i]`, already shipped without them,
confirmed the split was correct) or giving them their own small tier; recommend the
latter now that `[M17i]` has shipped cleanly without them; Liquid Ooze (64) — inverts the
existing drain-move code so drain moves against this Pokémon damage the attacker instead
of healing them, a straightforward inversion of already-built M6 drain-move logic;
Pressure (46) — opponent's moves cost 1 extra PP when targeting this Pokémon, hooks into
the existing M15 Task 3 `use_pp` function, simple and standalone.

## Summary table

| Category | Count |
|---|---|
| Total canonical ability IDs (1-318) | 318 |
| Implemented (M8 + M17a-m) | 136 |
| Excluded (9 sub-groups, re-derived and cross-checked) | 61 |
| **Remaining, proposed for M17n** | **121** |

## Recommended sequencing

1. **Group 5 first** (type-effectiveness leftovers, 9 abilities) — direct continuation
   of `[M17m]`, includes the highest-risk remaining item (Wonder Guard) and should not
   be left to the tail of a long grab-bag tier.
2. **Group 1** (status-immunity family, 22 abilities) — cheapest, most precedented,
   good next after a high-risk tier to rebuild momentum; also resolves several
   documented no-op/dependency questions (Oblivious, Cute Charm, Damp, Illuminate, Honey
   Gather, Run Away, Pickup, Ball Fetch) that are cheap to just confirm-and-document.
3. **Group 2** (weather/terrain evasion+speed, 8) and **Group 3** (turn-order/priority,
   6) — both small, both fully precedented against existing M16d/e turn-order work and
   M17c's weather-conditional-speed precedent.
4. **Group 7** (type-mutation/choice-lock cheap reuses, 6) — genuinely free wins, could
   also be moved earlier if cheap-wins-first is preferred over infra-grouping (same
   optionality the original recon flagged for Color Change/Protean).
5. **Group 4** (damage-pipeline leftovers, 27) — same shape as the already-shipped
   `[M17a]`, largest of the "ordinary" groups, no blocking dependencies.
6. **Group 6** (item/berry interaction, 6) — finally builds the "last consumed berry"
   tracking `[M17d]` deferred twice; small, self-contained infra addition.
7. **Group 8 last** (grab-bag, 37) — recommend splitting into 2-3 further passes once
   the earlier groups are underway rather than pre-committing a fixed split now, per
   the original recon's own framing of this exact bucket. Contains every genuine
   move-dependency (Perish Song, and Taunt/Torment/Heal Block for Aroma Veil) and
   infra-gap item (gender for Rivalry, weight for Heavy/Light Metal, wind-move flag,
   HP-threshold forced-switch for Wimp Out/Emergency Exit) — these should each get an
   explicit Step-0 existence check for their move/data dependency before being
   scheduled, not assumed present.

## Open items for Rob before M17n's first implementation prompt is written

- **Section 8.4's Mega-form-bound group (11 abilities)** — this recon treated them as
  excluded based on `[M17g]`'s "already out of scope" phrasing, but that phrasing never
  explicitly named which of Section 8.4's three options (skip entirely / simplified
  reinterpretation / defer until a forme-data system exists) was chosen. Worth a
  one-line confirmation that "skip entirely" is correct before this recon's 61-exclusion
  count is treated as final and unchangeable.
- **Illusion (149)** — confirm whether a documented no-op code entry is wanted (matching
  Anticipation/Forewarn/Frisk) or whether it should simply be left off the roster
  entirely as "not applicable to a non-visual engine."
- **Aroma Veil (165)'s partial move-dependency** (Taunt/Torment/Heal Block) and **Wimp
  Out/Emergency Exit's HP-threshold forced-switch infra** — both need a quick existence
  check against this project's actual move roster before Group 1/Group 8 scoping is
  finalized; not re-verified in this pass since it's report-only.
