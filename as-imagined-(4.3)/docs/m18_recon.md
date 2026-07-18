# M18 Pre-Recon — Full Item Scoping, Organized by Generation

**Status: RECON ONLY — no implementation code touched in this session.** Does not
modify `CLAUDE.md`, `docs/decisions.md`, or any `.gd`/`.tres` file. Rob reviews this and
makes the actual per-item/per-category inclusion calls, the same recon-then-decide
workflow already used for `docs/m17_recon.md`/`docs/m17n_recon.md`.

**A flag before anything else, per this project's standing practice of surfacing
unverifiable premises rather than silently assuming them:** the task that produced
this recon stated the project's scope boundary as "All items through Gen V, Gen VI+
picked as needed," attributed to `CLAUDE.md`'s "SCOPE (locked)" section. **I could not
find this text anywhere in `CLAUDE.md`** — there is no section with that heading, and
no "Gen V" text anywhere in the file. `CLAUDE.md`'s own "Build order" sections only
cover M1–M14c; M15 onward (including M18) exist only as ad-hoc bullet entries under
"Current status," with no roadmap document defining M18's scope beyond one line in the
"Follow-up fixes" entry: *"Air Balloon... and the rest of the held-item roster remain
deferred to the future M18 milestone."* I also checked project memory and found no
record of the Gen V claim. This isn't necessarily wrong — Rob may have stated it in a
conversation not captured in either place — but it should be treated as **unverified**
going into this recon, not as an established fact. This recon therefore surfaces the
**full** item catalog regardless of any generation cutoff, per the task's own
instruction to let Rob make the actual calls.

---

## Section A — Current baseline (confirmed against code, not summary text)

Read `scripts/battle/core/item_manager.gd` directly (not `docs/decisions.md`'s prose)
for the ground truth. This project implements exactly **14 distinct hold-effect
mechanisms**, backing these named items:

| Hold effect constant | Value | Named item(s) tested | Mechanic |
|---|---|---|---|
| `HOLD_EFFECT_CHOICE_BAND` | 29 | Choice Band | Attack ×1.5, locks holder into first-used move |
| `HOLD_EFFECT_CHOICE_SPECS` | 50 | Choice Specs | Sp. Atk ×1.5, same lock |
| `HOLD_EFFECT_CHOICE_SCARF` | 49 | Choice Scarf | Speed ×1.5, same lock |
| `HOLD_EFFECT_LIFE_ORB` | 60 | Life Orb | Power ×1.3 (post-roll), 1/10 max HP recoil |
| `HOLD_EFFECT_LEFTOVERS` | 41 | Leftovers | Heal 1/16 max HP at end of turn |
| `HOLD_EFFECT_RESTORE_PCT_HP` | 82 | Sitrus Berry (param=25) | Heal 25% max HP at ≤50% HP |
| `HOLD_EFFECT_CURE_STATUS` | 9 | Lum Berry | Cures any non-volatile status on infliction |
| `HOLD_EFFECT_RESIST_BERRY` | 80 | Occa Berry (Fire), Chilan Berry (Normal) | Halves damage from a matching-type hit (generic `hold_effect_param`-driven mechanism — see note below) |
| `HOLD_EFFECT_DAMP_ROCK` / `HEAT_ROCK` / `ICY_ROCK` / `SMOOTH_ROCK` | 51/53/54/56 | the 4 weather rocks | Extends the matching weather to 8 turns |
| `HOLD_EFFECT_UTILITY_UMBRELLA` | 115 | Utility Umbrella | Negates rain/sun effects for the holder |
| `HOLD_EFFECT_HEAVY_DUTY_BOOTS` | 119 | Heavy Duty Boots | Full hazard immunity on switch-in |
| `HOLD_EFFECT_PLATE` | 89 | (generic, no named Plate yet) | Multitype's type-source; not yet itemized per-Plate |

**Key structural finding, important for scoping M18's real size:** `docs/decisions.md`'s
`[M13]` entry states explicitly — *"`battle_ai_items.c` covers trainer bag consumables
only... `ShouldUseItem()` iterates `gBattleHistory->trainerItems` (bag items), not
`gBattleMons[battler].item` (held items). Completely unrelated to held-item AI."* This
project's entire architecture only ever models **held items that stay on a Pokémon
through battle** — there is no bag-item-use mechanic anywhere in `BattleManager` or
`TrainerAI`, and this was a **deliberate, already-made scope decision from M13**, not an
oversight this recon discovered. This one fact eliminates roughly 500+ of the item
catalog's 874 total IDs from real consideration before any per-item review — see
Section B.3 and Section C for the full accounting.

Two generic mechanisms already exist and just need **data-entry expansion**, not new
engine logic: the resist-berry mechanism (`HOLD_EFFECT_RESIST_BERRY` + `hold_effect_param`
= type) already supports all 18 single-type resist berries, only 2 are named; the Plate
mechanism (`HOLD_EFFECT_PLATE`) already exists for Multitype, but no specific Plate
(Flame Plate, Splash Plate, etc.) has ever been added as a named item, and per Section B
below, the same mechanism would also need to grow a power-boost read (Plates boost
same-type moves ~20% in addition to setting Arceus's type) — currently only the
type-source half is wired.

---

## Section B — Full item enumeration

**Total items in source: 874** (`ITEMS_COUNT = 874`, last real ID `ITEM_GLIMMORANITE =
873`, confirmed by reading `include/constants/items.h`'s enum tail directly, not
estimated).

**Methodology note (a deliberate structural choice, flagged rather than silently
made):** the task asked for generation as strict top-level organization for every item.
I've followed that for the ~230 items that are genuinely **held items** (the real
decision set for a battle-engine item milestone) — Section B.1 below, organized Gen II
through Gen IX. For the remaining ~640 items — Poké Balls, general Medicine, Vitamins,
Mints, Candy, X Items, Escape Items, Treasures, Fossils, Mulch, Apricorns, Mail,
menu-use Evolution Items, Nectars, Contest Scarves, Charms, all Key Item categories, and
TM/HM — Section A's finding applies uniformly regardless of generation (all are
bag/overworld/menu items this project's architecture doesn't model at all), so I've
compressed these into category-summary rows (Section B.3) rather than 640 individual
"NO, not battle-relevant" rows repeating the same verdict. Generation IS noted per
category in B.3 for completeness, just not exploded into per-generation sub-sections
for a verdict that doesn't change by generation. Full per-item detail for these
categories is available in this session's research (nothing was dropped, just
compressed for readability) — ask if any specific category needs the uncompressed list.

### B.1 — Held items, by generation (the real M18 decision set)

#### Generation II (first held items ever introduced)

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 425 | Silk Scarf | Type-boosting | +20% Normal-type move power | *(placed here for proximity; actually Gen III — see B.1 Gen III)* |
| 426 | Charcoal | Type-boosting | +20% Fire-type move power | Not implemented |
| 427 | Mystic Water | Type-boosting | +20% Water-type move power | Not implemented |
| 428 | Magnet | Type-boosting | +20% Electric-type move power | Not implemented |
| 429 | Miracle Seed | Type-boosting | +20% Grass-type move power | Not implemented |
| 430 | Never-Melt Ice | Type-boosting | +20% Ice-type move power | Not implemented |
| 431 | Black Belt | Type-boosting | +20% Fighting-type move power | Not implemented |
| 432 | Poison Barb | Type-boosting | +20% Poison-type move power | Not implemented |
| 433 | Soft Sand | Type-boosting | +20% Ground-type move power | Not implemented |
| 434 | Sharp Beak | Type-boosting | +20% Flying-type move power | Not implemented |
| 435 | Twisted Spoon | Type-boosting | +20% Psychic-type move power | Not implemented |
| 436 | Silver Powder | Type-boosting | +20% Bug-type move power | Not implemented |
| 437 | Hard Stone | Type-boosting | +20% Rock-type move power | Not implemented |
| 438 | Spell Tag | Type-boosting | +20% Ghost-type move power | Not implemented |
| 439 | Dragon Fang | Type-boosting | +20% Dragon-type move power | Not implemented |
| 440 | Black Glasses | Type-boosting | +20% Dark-type move power | Not implemented |
| 441 | Metal Coat | Type-boosting | +20% Steel-type move power (also an evolution trigger, non-battle half) | Not implemented |
| 392 | Light Ball | Species-specific | Doubles Pikachu's Atk and Sp.Atk | Not implemented |
| 393 | Leek / Stick | Species-specific | Raises Farfetch'd/Sirfetch'd crit ratio | Not implemented |
| 394 | Thick Club | Species-specific | Doubles Cubone/Marowak Attack | Not implemented |
| 395 | Lucky Punch | Species-specific | Raises Chansey's crit ratio | Not implemented |
| 396 | Metal Powder | Species-specific | Doubles Ditto's Defense (while untransformed) | Not implemented |
| 459 | Bright Powder | Misc. held | Lowers foe's accuracy vs. holder (10%) | Not implemented |
| 462 | Quick Claw | Misc. held | ~20% chance to move first in its priority bracket | Not implemented |
| 465 | King's Rock | Misc. held | 10% chance to add flinch to a hit that doesn't already flinch | Not implemented |
| 471 | Scope Lens | Misc. held | Raises holder's crit ratio one stage | Not implemented |
| 472 | Leftovers | Misc. held | Heal 1/16 max HP/turn | **Implemented** |

#### Generation III

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 425 | Silk Scarf | Type-boosting | +20% Normal-type move power | Not implemented |
| 442 | Choice Band | Choice items | Atk ×1.5, move-lock | **Implemented** |
| 398 | Deep Sea Scale | Species-specific | Doubles Clamperl's Sp.Def | Not implemented |
| 399 | Deep Sea Tooth | Species-specific | Doubles Clamperl's Sp.Atk | Not implemented |
| 400 | Soul Dew | Species-specific | Latios/Latias: +20% Psychic/Dragon move power (Gen 7+ shape; earlier gens boosted Sp.Atk/Sp.Def instead — a generational-nuance item) | Not implemented |
| 404 | Sea Incense | Incenses | +Water-type move power | Not implemented |
| 405 | Lax Incense | Incenses | Lowers foe's accuracy vs. holder | Not implemented |
| 406 | Odd Incense | Incenses | +Psychic-type move power | Not implemented |
| 407 | Rock Incense | Incenses | +Rock-type move power | Not implemented |
| 408 | Full Incense | Incenses | Holder always moves last in its priority bracket | Not implemented |
| 410 | Rose Incense | Incenses | +Grass-type move power | Not implemented |
| 460 | White Herb | Misc. held | Once: restores all lowered stats to normal | Not implemented |
| 464 | Mental Herb | Misc. held | Once: cures infatuation (Gen 5+: also Taunt/Encore/Torment/Disable/Heal Block) | Not implemented |
| 523 | Sitrus Berry | Berries | Heal 25% max HP at ≤50% HP | **Implemented** |
| 524–528 | Figy/Wiki/Mago/Aguav/Iapapa Berry | Berries | Heal 1/3 max HP; confuses if nature dislikes the flavor | Not implemented |
| 567–573 | Liechi/Ganlon/Salac/Petaya/Apicot/Lansat/Starf Berry | Berries | +1 stat (or crit-ratio, or random-stat for Starf) at ≤25% HP | Not implemented |

#### Generation IV

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 443 | Choice Specs | Choice items | Sp.Atk ×1.5, move-lock | **Implemented** |
| 444 | Choice Scarf | Choice items | Speed ×1.5, move-lock | **Implemented** |
| 447–450 | Damp/Heat/Icy/Smooth Rock | Weather Rocks | Extends matching weather to 8 turns | **Implemented** (all 4) |
| 479 | Life Orb | Misc. held | Power ×1.3, 1/10 max HP recoil | **Implemented** |
| 549 | Chilan Berry | Berries | Halves damage from a Normal-type hit | **Implemented** |
| 550 | Occa Berry | Berries | Halves damage from a super-effective Fire hit | **Implemented** |
| 551–565 | Passho/Wacan/Rindo/Yache/Chople/Kebia/Shuca/Coba/Payapa/Tanga/Charti/Kasib/Haban/Colbur/Babiri Berry (15) | Berries | Same shape, other 15 types | Mechanism exists generically (`hold_effect_param`), these 15 not individually named/tested |
| 401 | Adamant Orb | Species-specific | +20% Dialga's Dragon/Steel move power | Not implemented |
| 402 | Lustrous Orb | Species-specific | +20% Palkia's Dragon/Water move power | Not implemented |
| 403 | Griseous Orb | Species-specific | +20% Giratina's Dragon/Ghost move power | Not implemented |
| 250–265 | Flame/Splash/Zap/Meadow/Icicle/Fist/Toxic/Earth/Sky/Mind/Insect/Stone/Spooky/Draco/Dread/Iron Plate (16) | Plates | +20% matching-type move power + sets Arceus's type/Judgment's type | Mechanism (`HOLD_EFFECT_PLATE`) exists for the type-source half only (Multitype); power-boost half + all 16 named items not yet added |
| 445 | Flame Orb | Status Orbs | Burns the holder at end of first turn held | Not implemented |
| 446 | Toxic Orb | Status Orbs | Badly poisons the holder at end of first turn held | Not implemented |
| 409 | Wave Incense | Incenses | +Water-type move power (duplicate of Sea Incense) | Not implemented |
| 473 | Shell Bell | Misc. held | Heals 1/8 of damage dealt, per hit | Not implemented |
| 474 | Wide Lens | Misc. held | +10% accuracy | Not implemented |
| 475 | Muscle Band | Misc. held | +10% physical move power | Not implemented |
| 476 | Wise Glasses | Misc. held | +10% special move power | Not implemented |
| 477 | Expert Belt | Misc. held | +20% power on super-effective hits | Not implemented |
| 478 | Light Clay | Misc. held | Extends Reflect/Light Screen/Aurora Veil to 8 turns | Not implemented |
| 480 | Power Herb | Misc. held | Once: lets a charge move execute in one turn | Not implemented |
| 481 | Focus Sash | Misc. held | At full HP, survives a lethal hit at 1 HP (consumed) | Not implemented |
| 482 | Zoom Lens | Misc. held | +20% accuracy if moving after the target | Not implemented |
| 483 | Metronome (item) | Misc. held | Power ramps up to +100% over 5 consecutive uses of the same move | Not implemented |
| 484 | Iron Ball | Misc. held | Halves Speed; grounds the holder (Ground-move-hittable even if Flying/Levitate) | Not implemented |
| 485 | Lagging Tail | Misc. held | Holder always moves last in its priority bracket | Not implemented |
| 486 | Destiny Knot | Misc. held | Infatuation is mirrored back onto its source | Not implemented |
| 487 | Black Sludge | Misc. held | Heals Poison-types 1/16 max HP/turn; damages all others 1/8 max HP/turn | Not implemented |
| 488 | Grip Claw | Misc. held | Extends binding-move duration to the 7-turn max | Not implemented |
| 489 | Sticky Barb | Misc. held | Damages holder 1/8 max HP/turn; can transfer via contact | Not implemented |
| 490 | Shed Shell | Misc. held | Holder can always switch out, bypassing trapping | Not implemented |
| 491 | Big Root | Misc. held | +30% HP recovered by HP-drain moves | Not implemented |
| 492 | Razor Claw | Misc. held | +1 crit-ratio stage (also an evolution trigger) | Not implemented |
| 493 | Razor Fang | Misc. held | Same flinch effect as King's Rock (also an evolution trigger) | Not implemented |
| 574 | Enigma Berry | Berries | Heals 1/4 max HP when hit by a super-effective move | Not implemented |
| 575 | Micle Berry | Berries | Raises accuracy of the next move at low HP | Not implemented |
| 576 | Custap Berry | Berries | Grants a priority boost that turn at low HP | Not implemented |
| 577 | Jaboca Berry | Berries | Damages attacker 1/8 max HP on a physical contact hit | Not implemented |
| 578 | Rowap Berry | Berries | Same, on a special hit | Not implemented |
| 419–424 | Power Weight/Bracer/Belt/Lens/Band/Anklet | EV Gain Modifiers | Doubles one EV stat's gain, halves Speed | Not implemented — **non-battle-mechanic** (an EV-training item; only the Speed-halving half is battle-visible) |

#### Generation V

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 267–270 | Douse/Shock/Burn/Chill Drive | Drives | Changes Genesect's Techno Blast type to match | Not implemented — same shape as the Plate mechanism, likely reusable |
| 339–356 | Normal…Fairy Gem (18) | Gems | One-time consumed power boost on a matching-type move (+50% pre-Gen VI, +30% Gen VI+, config-gated in source) | Not implemented |
| 455 | Absorb Bulb | Type-activated | Consumed on a Water hit, +1 Sp.Atk | Not implemented |
| 456 | Cell Battery | Type-activated | Consumed on an Electric hit, +1 Atk | Not implemented |
| 458 | Snowball | Type-activated | Consumed on an Ice hit, +1 Atk | Not implemented |
| 494 | Eviolite | Misc. held | +50% Def/Sp.Def for not-fully-evolved Pokémon | Not implemented |
| 495 | Float Stone | Misc. held | Halves holder's weight (weight-based move interactions) | Not implemented |
| 496 | Rocky Helmet | Misc. held | Damages an attacker 1/6 max HP on contact | Not implemented |
| 497 | Air Balloon | Misc. held | Grants Ground-move immunity; popped (consumed) on any hit | Not implemented |
| 498 | Red Card | Misc. held | Forces the attacker to switch out (consumed) | Not implemented |
| 499 | Ring Target | Misc. held | Removes one of the holder's type immunities vs. the attacking type | Not implemented |
| 500 | Binding Band | Misc. held | Raises binding-move damage dealt from 1/8 to 1/6 max HP | Not implemented |
| 501 | Eject Button | Misc. held | Forces the holder to switch out after being hit (consumed) | Not implemented |
| 502 | Weakness Policy | Misc. held | Consumed on a super-effective hit taken; +2 Atk/Sp.Atk | Not implemented |

#### Generation VI

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 266 | Pixie Plate | Plates | Same as the 16 Gen IV Plates, Fairy-type | Same mechanism gap as the Gen IV Plates |
| 457 | Luminous Moss | Type-activated | Consumed on a Water hit, +1 Sp.Def | Not implemented |
| 566 | Roseli Berry | Berries | Halves damage from a super-effective Fairy hit | Mechanism exists generically, not named |
| 579 | Kee Berry | Berries | +1 Defense when hit by a physical move | Not implemented |
| 580 | Maranga Berry | Berries | +1 Sp.Def when hit by a special move | Not implemented |
| 503 | Assault Vest | Misc. held | +50% Sp.Def; holder cannot use status moves | Not implemented |
| 504 | Safety Goggles | Misc. held | Blocks weather chip damage AND powder/spore moves | Not implemented — **directly relevant to `[M17.5]`'s own flagged gap** (Section C below) |
| 290–291 | Red Orb / Blue Orb | Colored Orbs | Triggers Primal Reversion in-battle for Groudon/Kyogre (switch-in, automatic, not player-chosen) | **Design-decision item** — see Section C (the abilities it would grant, Desolate Land/Primordial Sea, are ALREADY implemented per `[M17d]`; only the Orb-triggered form-change itself is missing) |
| 292–338 | 46 Mega Stones | Mega Stones | Enable Mega Evolution | **Excluded by precedent** — see Section C |

#### Generation VII

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 271–287 | 17 Memories | Memories | Changes Silvally's Multi-Attack type + Silvally's own type | Not implemented — same reusable shape as Drives/Plates; Silvally's RKS System ability is separately already excluded (`[M17n-4]`) |
| 451–454 | Electric/Psychic/Misty/Grassy Seed | Terrain Seeds | Consumed on switch-in during matching terrain, +1 Def or Sp.Def | Not implemented — **this project has no Terrain system at all** (`[M17e]` is void, all 10 terrain abilities excluded), so these 4 seeds are moot unless Terrain itself is reconsidered |
| 505 | Adrenaline Orb | Misc. held | Consumed when targeted by Intimidate, +1 Speed | Not implemented |
| 506 | Terrain Extender | Misc. held | Extends terrain duration to 8 turns | Same Terrain-system dependency as the 4 Seeds above |
| 507 | Protective Pads | Misc. held | Blocks contact-triggered side effects (Rocky Helmet, Static, Rough Skin, etc.) taken by the holder | Not implemented |
| 357–391 | 35 Z-Crystals | Z-Crystals | Enable Z-Moves | **Excluded by precedent** — see Section C |

#### Generation VIII

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 288–289 | Rusted Sword / Rusted Shield | Form-changing (adjacent) | Zacian/Zamazenta Hero↔Crowned form change | **Design-decision item**, same family as Mega/Z exclusions — see Section C |
| 508 | Throat Spray | Misc. held | +1 Sp.Atk whenever the holder uses a sound move | Not implemented (this project already has a `sound_move` `MoveData` flag wired for other abilities, per `[M17n-1]`/`[M17n-6]` — should be a cheap add) |
| 509 | Eject Pack | Misc. held | Forces the holder to switch out whenever any of its stats are lowered | Not implemented |
| 510 | Heavy-Duty Boots | Misc. held | Full hazard immunity on switch-in | **Implemented** |
| 511 | Blunder Policy | Misc. held | Consumed when the holder's move misses on the accuracy check; +2 Speed | Not implemented |
| 512 | Room Service | Misc. held | Consumed on switch-in while Trick Room is active; −1 Speed | Not implemented (this project has Trick Room already, per `[M16d]` — cheap add) |
| 513 | Utility Umbrella | Misc. held | Negates rain/sun for the holder | **Implemented** |

#### Generation IX

| ID | Name | Category | Mechanic | Status |
|---|---|---|---|---|
| 758 | Ability Shield | Gen IX battle items | Blocks the holder's own ability from being changed/suppressed/negated | Not implemented |
| 759 | Clear Amulet | Gen IX battle items | Blocks external stat-lowering (own self-lowering abilities unaffected) | Not implemented |
| 760 | Punching Glove | Gen IX battle items | +10% power to punching moves, strips their contact flag | Not implemented (this project already has a `punching_move` flag + `move_makes_contact()` wrapper per `[M17n-5]` — cheap add) |
| 761 | Covert Cloak | Gen IX battle items | Blocks secondary/additional effects of moves used against the holder | Not implemented |
| 762 | Loaded Dice | Gen IX battle items | Guarantees high hit-counts on multi-hit moves | Not implemented — **this project has no multi-hit mechanism at all** (Skill Link deferred for the same reason, per `[M17n-5]`) — blocked on the same missing infrastructure |
| 764 | Booster Energy | Gen IX battle items | One-time-per-switch-in Protosynthesis/Quark Drive activator | Not implemented — Protosynthesis/Quark Drive are already excluded abilities (Terrain/weather-adjacent, `[M17n-6]` exclusion list), so this item is moot unless those are reconsidered |
| 769 | Mirror Herb | Gen IX battle items | Once: copies an opponent's stat increase onto the holder | Not implemented — this project already has an "copy opponent's stat increase" shape from Opportunist (`[M17n-8]`) — likely a cheap adjacent add |
| 792 | Adamant Crystal | Species-specific | Origin-forme Dialga equivalent of Adamant Orb | Not implemented |
| 793 | Griseous Core | Species-specific | Origin-forme Giratina equivalent of Griseous Orb | Not implemented |
| 794 | Lustrous Globe | Species-specific | Origin-forme Palkia equivalent of Lustrous Orb | Not implemented |
| 798 | Berserk Gene | Misc. held | *(Note: mechanically a revived Gen II item, just assigned a high ID in this ROM hack's table)* Sharply raises Attack but confuses the holder, then consumed | Not implemented |
| 799 | Fairy Feather | Type-boosting | +20% Fairy-type move power | Not implemented — closes the Gen VI Fairy-type gap in the Charcoal-family set |
| 803–805 | Cornerstone / Wellspring / Hearthflame Mask | Species-specific | Ogerpon-exclusive: changes Ogerpon's type/form while held | **Design-decision-adjacent** — Terastallization-related signature mechanic (Ogerpon's "masks" interact with its own Tera type in canon) — bundle with the Tera Orb/Shard decision in Section C |
| 772, 774–791, 815 | Tera Orb + 19 Tera Shards | Tera items | Enable/support Terastallization | **Excluded by precedent** — see Section C |

### B.2 — Held-item mechanisms needing more than a data-entry decision

A few held items above aren't simple "add this .tres entry" decisions because their
mechanic depends on something else not yet built:

- **Terrain Seeds (4) + Terrain Extender** — blocked on this project's Terrain system
  being void (`[M17e]`, Rob's locked decision). Moot unless that's revisited.
- **Loaded Dice** — blocked on no multi-hit-move mechanism existing at all (same gap
  that deferred Skill Link).
- **Booster Energy** — the abilities it activates (Protosynthesis/Quark Drive) are
  already excluded. Moot unless that's revisited.
- **Adamant/Lustrous/Griseous Orb + their Gen IX Origin-forme equivalents, Soul Dew** —
  these boost a specific move-type pair for a specific single Pokémon (Dialga/Palkia/
  Giratina/Latios/Latias). Simple mechanically, but low value unless this project
  models specific legendary Pokémon by name anywhere yet — worth Rob confirming the
  species roster's current scope before treating these as "just another held item."

### B.3 — Everything else: bag/overworld/menu items, compressed by category (cross-generation)

Per Section A's finding, all of the below are excluded by the SAME existing M13
precedent (no bag-item-use mechanic exists in this engine at all) — these are not new
per-item exclusion decisions, they're confirmations of an already-established boundary.

| Category | ID range | Count | Gen span | Why out of scope |
|---|---|---|---|---|
| Poké Balls | 1–27 | 27 | I–VII | Capture mechanic; this engine has no wild-encounter/catch loop at all |
| Medicine (Potions, Ethers, Elixirs, Revives, status-cures, Sacred Ash, regional specialties) | 28–64 | 37 | I–VII | Bag consumables; some are battle-usable in canon but the AI/engine never models bag-item use |
| Vitamins | 65–72 | 8 | I–II | EV-training, non-battle |
| EV Feathers | 73–78 | 6 | VIII | EV-training, non-battle |
| Ability Modifiers (Ability Capsule/Patch) | 79–80 | 2 | VI, VIII | Menu-only ability swap |
| Mints | 81–101 | 21 | VIII | Nature-effect override, menu-only |
| Candy (Rare Candy, Exp. Candy tiers, Dynamax Candy) | 102–108 | 7 | I, VIII | Leveling/EXP, non-battle |
| Medicinal Flutes | 109–111 | 3 | II | Battle-usable status cures, but bag items (same M13 exclusion) |
| Encounter-modifying Flutes/Repels/Lures | 112–120 | 9 | II, I, VIII(?) | Wild-encounter modifiers, non-battle |
| X Items (X Attack/Defense/Sp.Atk/Sp.Def/Speed/Accuracy, Dire Hit, Guard Spec.) | 121–128 | 8 | I–II | Battle-usable stat/crit/accuracy boosts, but bag items — **the one category here with a real battle mechanic identical in shape to already-implemented ability effects** (Dire Hit ≈ Focus Energy, Guard Spec. ≈ a Mist-style block); cheap to add IF the bag-item scope boundary is ever revisited, but currently correctly excluded |
| Escape Items (Poké Doll, Fluffy Tail, Poké Toy, Max Mushrooms) | 129–132 | 4 | I, III, VIII | Guaranteed-escape bag items; Max Mushrooms is an all-stats-+1 outlier miscategorized in this header block |
| Treasures | 133–164 | 32 | I–VII | Pure sell/quest items |
| Fossils | 165–179 | 15 | I, III–VIII | Revival-menu items |
| Mulch | 180–187 | 8 | IV, VIII | Farming, non-battle |
| Apricorns (+ misc treasures grouped here) | 188–198 | 11 | II, VIII | Ball-crafting ingredients / currency |
| Mail | 199–210 | 12 | III | Cosmetic held item, no `holdEffect`; flag for later: mainline games exempt Mail from Fling/Thief/Trick/Covet — worth remembering if those move effects are ever added |
| Evolution Items (stones + trade/level items + Sweets/Nectars-adjacent) | 211–245 | 35 | I–VIII | Bag/party-menu evolution triggers, no passive battle effect (the "held + trade" ones carry zero OTHER battle-relevant `holdEffect`, confirmed from source) |
| Nectars | 246–249 | 4 | VII | Oricorio form-change, menu-only |
| Contest Scarves | 413–417 | 5 | III | Contest-stat items, no battle `holdEffect` |
| Charms | 690–693 | 4 | mixed | Odds-modifiers (shiny/egg/capture/EXP), no battle mechanic |
| Form-changing Key Items (Rotom Catalog, Gracidea, Reveal Glass, DNA Splicers, Zygarde Cube, Prison Bottle, N-Solarizer/Lunarizer, Reins of Unity) | 694–702 | 9 | mixed | Overworld/story form-change triggers, zero in-battle mechanic (these are all "outside of battle, permanently pick a form" — distinct from Colored Orbs' in-battle automatic trigger, which is why Orbs got a design-decision flag above and these didn't) |
| Battle Mechanic Key Items (Mega Ring, Z-Power Ring, Dynamax Band) | 703–705 | 3 | VI–VIII | **The exact 3 gate-items for Mega/Z-Move/Dynamax** — see Section C, one design call covers all three |
| Misc. Key Items (Bicycle, Rods, Town Map, VS Seeker, storage UIs, etc.) | 706–726 | 21 | mixed | Traversal/menu utilities |
| Story Key Items (region-specific quest items spanning Kanto/Hoenn/etc., since this ROM hack's item table merges content from multiple canon games) | 727–757 | 31 | mixed | Pure narrative flags |
| Gen IX evolution-trigger key items (Auspicious Armor, Gimmighoul Coin, Leader's Crest, Scrolls, etc.) | 763,765–768,770–771,773,795–797,800–802,813–814 | 16 | IX | Menu-use evolution triggers, no passive battle effect |
| Legends Arceus/Z-A EV & healing consumables (Mochi, Jubilife Muffin, Remedies, Aux items, unfinished stubs) | 806–812,816–826 | 17 | mixed (recent spinoffs) | Menu/party items; the 4 "Remedy" items and Jubilife Muffin ARE functionally battle-usable status cures in their source game, but same bag-item exclusion applies; Choice Dumpling/Swap Snack/Twice-Spiced Radish appear to be unfinished stubs in this ROM hack's own data (placeholder descriptions) |
| Strange Ball, Pokéshi Doll | 827–828 | 2 | mixed | Capture variant / collectible, no battle mechanic |
| TM/HM | 582–689 | 108 | I–IX (100 TMs + 8 HMs) | **Zero in-battle effect of any kind** — pure "teach this move" bag items. This project's `tmhm_map` (from M15's data pipeline) already models the Pokémon↔learnable-move relationship directly; there is no "TM as an in-battle object" concept to build. Recommend treating this whole category as a 1-line scope confirmation, not a review. |

---

## Section C — Items needing a design decision beyond simple inclusion/exclusion

These aren't "should we add this item" calls — they each depend on a bigger mechanic
this project doesn't have, mirroring the exact "flag, don't silently assume" discipline
already used for M17's ability exclusions (Mega-form-bound, Z-Move/Dynamax-exclusive,
and Terastallization-adjacent abilities were all excluded there for the identical
reason).

1. **Mega Evolution (46 Mega Stones, IDs 292–338 + the Mega Ring key item, 703) — this
   project has NO Mega Evolution mechanic at all.** Confirmed via this project's own
   prior exclusion of every Mega-form-bound ABILITY from the M17 ability ledger
   (`docs/m17_final_ledger.md`'s 91 exclusions include the full "11 Mega/form-bound"
   group cross-referenced in the M17 Final Reconciliation). A Mega Stone can't do
   anything until Mega Evolution itself exists as new core battle infrastructure (a
   once-per-battle player-triggered transformation changing stats/ability/typing for
   the rest of the battle) — this is a "build a whole mechanic" decision, not a
   held-item addition.

2. **Z-Moves (35 Z-Crystals, IDs 357–391 + the Z-Power Ring key item, 704) — same
   shape as Mega Evolution.** No Z-Move mechanic exists (once-per-battle move-power
   override + signature-move lookup table). Same "build the mechanic first" blocker.

3. **Terastallization (Tera Orb + 19 Tera Shards, IDs 772/774–791/815, + the Ogerpon
   Masks 803–805) — this project has no Terastallization mechanic**, consistent with
   RKS System and other Tera-adjacent abilities already being excluded from the
   ability ledger. Same blocker shape.

4. **Dynamax/Gigantamax (Dynamax Band key item 705, Dynamax Candy 108, Max Mushrooms
   132) — no Dynamax mechanic exists.** Same blocker shape, smallest item footprint of
   the four (Dynamax doesn't have per-Pokémon exclusive items the way Mega/Z do).

5. **Primal Reversion (Red Orb / Blue Orb, IDs 290–291) — a smaller, more tractable
   version of the same problem.** Unlike Mega/Z/Tera, this project ALREADY has the
   abilities these Orbs would grant (Primordial Sea, Desolate Land — both implemented
   in `[M17d]`) — only the Orb-triggered, automatic, switch-in form-change itself
   (stat/typing change, no player choice involved) is missing. This is a much smaller
   lift than the other three if Rob wants it: 2 items, an existing switch-in hook
   architecture, and abilities that already exist — worth calling out as the cheapest
   of the five "needs a bigger mechanic" items if any single one gets picked up first.

6. **Rusted Sword / Rusted Shield (Zacian/Zamazenta form-change, IDs 288–289) — same
   family of problem, smaller still.** A permanent (not per-battle) hero-form change
   triggered by holding the item; no signature battle mechanic beyond a stat/type/move
   change already expressible via this project's existing type-mutation infrastructure
   (`_set_mon_type`, per `[M16e]`/`[M17n-4]`) — likely the cheapest of all six items in
   this section if it's ever picked up, since it doesn't need any NEW battle-phase
   mechanic, just a held-item check at switch-in.

7. **Legends Z-A Mega Stones (IDs 829–873, 45 items) — a scope question about the
   reference source itself, not just Mega Evolution.** "Legends Z-A" is a 2025 spinoff
   title, not a mainline numbered generation game, and several of its stones (the
   `-ite Z` and dual X/Y variants) don't correspond to any existing mainline Mega
   Evolution at all. `CLAUDE.md` names `pokeemerald_expansion` — fundamentally a
   Gen III ROM hack with modern mechanics backported — as the sole reference source;
   it doesn't mention Legends Z-A anywhere. Recommend Rob explicitly confirm whether
   this newer, non-mainline content is even intended to be in this project's universe
   at all, independent of the Mega Evolution question above.

8. **TM/HM (108 items) vs. the existing `tmhm_map` pipeline** — not really a "design
   decision" so much as a fast scope confirmation: this project's move-teaching
   relationship is already fully modeled elsewhere (M15), and TMs/HMs have no in-battle
   behavior to add. Flagging only so it doesn't get silently re-litigated as "should we
   add these as items" — the honest answer is there's nothing for an item entry to do.

9. **Bag-consumable scope boundary (Medicine, X Items, Escape Items, Poké Balls, ~110
   items total) — not new, but worth Rob's explicit reconfirmation given this recon's
   scale.** M13 already decided this engine models held items only, never bag-item use,
   for both the player and the AI. Every item in this bucket is excluded by that
   existing decision. If M18 ever wants to revisit "should the battle engine model bag
   items at all" that's a much bigger architectural question than "add item X" — flagged
   here once, clearly, rather than distributed as 110 individual repeated notes.

10. **Safety Goggles (504) specifically** — flagged because it directly overlaps with
    `docs/m17-5_recon.md`'s own finding: that recon confirmed Grass-type's general
    powder-move immunity was fixed, but noted Safety Goggles (the third canonical
    exemption alongside Overcoat and Grass-type) "is item-scope... likely absent." This
    item would close that loop completely if M18 picks it up.

---

## Section D — Summary count table

| Bucket | Item count | Notes |
|---|---|---|
| **Total items in source** | **874** | `ITEMS_COUNT`, confirmed directly from `include/constants/items.h` |
| Already implemented (Section A) | 14 hold-effect mechanisms, backing ~16 named items (some mechanisms back multiple names, e.g. resist-berry backs 2) | Choice trio, Life Orb, Leftovers, Sitrus/Lum/Occa/Chilan Berries, 4 Weather Rocks, Utility Umbrella, Heavy Duty Boots, generic Plate mechanism |
| Held items NOT yet implemented, simple data-entry additions (Section B.1, minus B.2's blocked items) | ~185 | The real M18 candidate list — organized by generation above, ready for Rob's per-item or per-category inclusion calls |
| Held items blocked on other missing infrastructure (Section B.2) | ~9 (4 Terrain Seeds + Terrain Extender, Loaded Dice, Booster Energy, arguably the 3 Origin-forme Orbs pending species-roster confirmation) | Each individually small, but gated on a separate decision first |
| Design-decision mechanics, not simple items (Section C items 1–7) | ~136 (46 Mega Stones + 35 Z-Crystals + 20 Tera items + 3 Ogerpon Masks + 2 Colored Orbs + 2 Zacian/Zamazenta items + 45 Legends Z-A stones, +3 gate key items) | 7 separate "build a mechanic first" or "confirm reference scope" questions, not per-item reviews |
| Bag/overworld/menu items, excluded by existing M13 precedent (Section B.3 + C.8/C.9) | **~535** | Poké Balls, Medicine, Vitamins, Mints, Candy, Flutes, X Items, Escape Items, Treasures, Fossils, Mulch, Apricorns, Mail, Evolution Items, Nectars, Contest Scarves, Charms, all Key Item categories, TM/HM — confirmed out of scope by the SAME existing decision, not 535 new individual calls |

**Bottom line: of 874 total item IDs, the actual "M18 scope" decision space is much
smaller than the raw count suggests** — roughly 185 straightforward held-item additions
(organized by generation in Section B.1 for Rob's review), a handful (~9) blocked on
smaller prerequisite decisions (Section B.2), 7 bundled "build a mechanic first / confirm
reference scope" questions covering ~136 items (Section C), and ~535 items already
excluded by an M13 decision this project made a milestone ago and never needed to
revisit. Recommend Rob review Section B.1 generation-by-generation as the actual next
step, treat Section C's 7 questions as a short separate discussion, and treat Section
B.3/D's bag-item bucket as already-settled unless something's changed.
