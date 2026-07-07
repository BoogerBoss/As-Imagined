# M18 Scope Ledger — Exhaustive Held-Item Include/Exclude List

**Status: DOCUMENTATION ONLY.** No implementation code, `CLAUDE.md`, `docs/decisions.md`,
or `docs/m18_recon.md` was touched to produce this. This is the single, definitive,
per-item held-item ledger for M18 — the same "build once, maintain in place, never
re-derive from scratch" pattern established by `docs/m17_final_ledger.md`.

## SCOPE UPDATE (supersedes the original "228 included by default" rule below)

Rob has finalized M18's actual scope, narrower than the original pass's default. The
current, authoritative rule:

1. **All held items through Generation IV are INCLUDED.**
2. **Plus this explicit list of 23 later-generation items, INCLUDED regardless of
   generation:** Roseli Berry, Eviolite, Rocky Helmet, Air Balloon, Eject Button,
   Weakness Policy, Pixie Plate, Red Card, Assault Vest, Safety Goggles, Red Orb, Blue
   Orb, Protective Pads, Eject Pack, Heavy-Duty Boots, Blunder Policy, Room Service,
   Utility Umbrella, Punching Glove, Covert Cloak, Loaded Dice, Mirror Herb, Fairy
   Feather. All 23 were re-verified against this ledger's existing rows and against
   `include/constants/items.h` directly — every one resolved to exactly one
   unambiguous item ID, no name collisions or decoys found.
3. **Every other Generation V+ held item NOT on that list is EXCLUDED**, with the
   reason noted per-row as "Gen V+, not on Rob's explicit inclusion list."
4. **The prior structural exclusions (Mega Stone / Z-Crystal / Terastallization)
   still apply, unaffected by this update** — none of those three categories has any
   member at Gen IV or earlier anyway, so this new rule doesn't change their status;
   confirmed explicitly rather than assumed, row by row, during this update.

This changes the previously-stated "228 included by default, pending Rob's further
exclusions" framing (item 1 in the original two-decision scope note directly below,
kept for history) to a **162 included / 213 excluded** split — see the Summary counts
table for the full breakdown.

**Out of scope entirely, unaffected by this update, deferred to a later UI-adjacent
pass (M25):** all non-held (bag/consumable) items — Poké Balls, Medicine, Vitamins,
Mints, TM/HM, Key Items, etc. **None of these appear in this ledger at all** — see
`docs/m18_recon.md`'s Section B.3 if that bucket ever needs review; it is not repeated
here.

**Original scope note (superseded by the update above, kept for history):**
1. In scope: **all held items** except Mega Stones, Z-Crystals, and Terastallization
   items (structurally excluded — no mechanic exists or will exist for any of these,
   consistent with every Mega/Z-Move/Dynamax exclusion already applied throughout M17).
2. Out of scope entirely, deferred to a later UI-adjacent pass (M25): all non-held
   (bag/consumable) items — Poké Balls, Medicine, Vitamins, Mints, TM/HM, Key Items,
   etc.

---

## Corrections found during re-verification (re-derived independently, not copied forward)

Per this task's own instruction to re-check rather than trust the recon's numbers
verbatim, I re-read `include/constants/items.h` directly rather than copying
`docs/m18_recon.md`'s Section B.1 forward as-is. Two corrections:

1. **Mega Stone count was undercounted by 1: the original block is 47 items, not 46.**
   `ITEM_VENUSAURITE = 292` through `ITEM_DIANCITE = 338` is 338−292+1 = **47** items,
   confirmed by direct line count of `include/constants/items.h:382–430` — the recon's
   "46" was an off-by-one.

2. **Legends Z-A Mega Stones' provenance question is now resolved, not left open.**
   The recon flagged (its Section C, item 7) that these 45 items' presence in this
   project's actual reference source was unconfirmed. **Directly re-verified: they ARE
   physically present** in `/home/rob/GodotAsImagined/reference/pokeemerald_expansion/include/constants/items.h`,
   lines 1006–1054, under source's own two category comments: `// Legends Z-A Mega
   Stones` (26 items, IDs 829–854) and `// Legends Z-A: Mega Dimension DLC Mega
   Stones` (19 items, IDs 855–873). This is not a hallucination or a wrong-fork issue —
   this particular clone of `pokeemerald_expansion` has clearly been kept current
   with very recent (2025) game content well beyond the project's originally-stated
   "Gen III ROM hack" framing.

   **This resolves cleanly under Rob's own structural rule, without needing a separate
   scope conversation**: since source itself labels both blocks "Mega Stones," and
   Rob's rule excludes the *category* "Mega Stones" (not just "the original 47"), all
   45 Legends Z-A stones fall under the same structural exclusion automatically. They
   are listed in this ledger (for exhaustiveness) but marked `EXCLUDED — Mega Stone`
   like every other stone in the category. **Total Mega Stones across all three
   source blocks: 47 (original) + 26 (Legends Z-A) + 19 (Legends Z-A DLC) = 92.**

3. **One placement correction, not a count error:** the recon's Section C bundled
   Ogerpon's three Masks (Cornerstone/Wellspring/Hearthflame, IDs 803–805) in with the
   Terastallization exclusion. Re-checking the mechanic: holding an Ogerpon Mask
   changes Ogerpon's form/type on its own, independent of Terastallizing — the
   Tera-specific nuance (Ogerpon keeping its held-mask type when Terastallized) is a
   secondary interaction, not the Mask's core function. **Masks are NOT Terastallization
   items** by Rob's stated exclusion rule (which only covers the Tera Orb and the 19
   Tera Shards) — they default to **INCLUDED** here, same family as Rusted Sword/Shield
   (a held item that changes the holder's form/type), flagged `needs new mechanism`
   like every other form-change item.

4. **A generation-classification correction found during this update's Step 1
   spot-check:** Berserk Gene (ID 798) sits in the Gen IX ID block by table
   placement, but its own row already noted it's *"mechanically a revived Gen II
   item, just assigned a high ID in this ROM hack's table."* Under the new Gen I-IV
   blanket-include rule, generation-introduced (not ID/table placement) is what
   matters — Berserk Gene's TRUE generation is II, so it is reclassified INCLUDED
   under that rule (not evaluated against the 23-item Gen V+ list at all), despite
   remaining physically listed in this document's Generation IX table for ID-ordering
   consistency. No other row in the ledger had a similar table-placement-vs-true-
   generation mismatch — checked as part of this update's required spot-check.

No other count or category discrepancies were found — everything else in
`docs/m18_recon.md`'s Section B.1 checked out against a fresh read of
`include/constants/items.h` and `src/data/items.h`.

---

## Summary counts (current, under the finalized Gen I-IV + 23-item rule)

| Bucket | Count |
|---|---|
| **Total held items in this ledger** | **375** (unchanged — verified by direct row count) |
| **Total INCLUDED** | **162** (verified by direct row count under the new rule) |
| — Gen I–IV (blanket include) | 138 (35 Gen II + 26 Gen III + 77 Gen IV) |
| — Explicit Gen V+ override (23 named items + Berserk Gene's Gen-II reclassification) | 24 |
| **Total EXCLUDED** | **213** (verified: 375−162) |
| — Structurally EXCLUDED — Mega Stone | 92 (47 original + 26 Legends Z-A + 19 Legends Z-A DLC; unaffected by this update) |
| — Structurally EXCLUDED — Z-Crystal | 35 (unaffected by this update) |
| — Structurally EXCLUDED — Terastallization | 20 (unaffected by this update) |
| — Gen V+, not on Rob's explicit list (newly excluded by this update) | 66 |
| Already implemented (subset of the 162 INCLUDED) | **15** — Leftovers, Lum Berry, Choice Band, Sitrus Berry, Choice Specs, Choice Scarf, Damp/Heat/Icy/Smooth Rock, Life Orb, Chilan Berry, Occa Berry, Heavy-Duty Boots, Utility Umbrella (unaffected — all 15 are either Gen ≤ IV or on the 23-item list) |
| Included, needs a new mechanism before it can function (subset of the 162) | ~14 (recomputed against the new included set — the 16 Gen IV Plates, Red Orb/Blue Orb's Primal Reversion trigger, Pixie Plate's same Plate-mechanism gap, Loaded Dice's multi-hit gap; several previously-flagged "needs new mechanism" Gen V+ items — all 4 Drives, all 17 Memories, all 4 Terrain Seeds + Terrain Extender, Booster Energy, the Adamant/Lustrous/Griseous Orb family, the Ogerpon Masks, Rusted Sword/Shield — are now EXCLUDED under the new rule and no longer count here) |

**Per-generation breakdown** (also shown in each section's own `##` heading below):

| Generation | Total | Included | Excluded |
|---|---|---|---|
| II | 35 | 35 | 0 |
| III | 26 | 26 | 0 |
| IV | 77 | 77 | 0 |
| V | 34 | 6 | 28 |
| VI | 56 | 6 | 50 (47 Mega Stone + 3 not listed) |
| VII | 59 | 1 | 58 (35 Z-Crystal + 23 not listed) |
| VIII | 8 | 5 | 3 |
| IX | 80 | 6 | 74 (65 structural + 9 not listed) |
| **Total** | **375** | **162** | **213** |

Every row below has a blank **"Rob's override"** column — leave blank to accept the
default status shown, or write an override (e.g. `EXCLUDE` or a reason) to record a
further individual decision on top of the rules above. This is the mechanism for
Rob's promised follow-up exclusion list.

---

## Generation II (35 items — first held items ever introduced)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 426 | Charcoal | Type-boosting | INCLUDED | +20% Fire move power; plain data entry | |
| 427 | Mystic Water | Type-boosting | INCLUDED | +20% Water move power | |
| 428 | Magnet | Type-boosting | INCLUDED | +20% Electric move power | |
| 429 | Miracle Seed | Type-boosting | INCLUDED | +20% Grass move power | |
| 430 | Never-Melt Ice | Type-boosting | INCLUDED | +20% Ice move power | |
| 431 | Black Belt | Type-boosting | INCLUDED | +20% Fighting move power | |
| 432 | Poison Barb | Type-boosting | INCLUDED | +20% Poison move power | |
| 433 | Soft Sand | Type-boosting | INCLUDED | +20% Ground move power | |
| 434 | Sharp Beak | Type-boosting | INCLUDED | +20% Flying move power | |
| 435 | Twisted Spoon | Type-boosting | INCLUDED | +20% Psychic move power | |
| 436 | Silver Powder | Type-boosting | INCLUDED | +20% Bug move power | |
| 437 | Hard Stone | Type-boosting | INCLUDED | +20% Rock move power | |
| 438 | Spell Tag | Type-boosting | INCLUDED | +20% Ghost move power | |
| 439 | Dragon Fang | Type-boosting | INCLUDED | +20% Dragon move power | |
| 440 | Black Glasses | Type-boosting | INCLUDED | +20% Dark move power | |
| 441 | Metal Coat | Type-boosting | INCLUDED | +20% Steel move power (evolution-trigger half is non-battle) | |
| 392 | Light Ball | Species-specific | INCLUDED | Doubles Pikachu's Atk/Sp.Atk | |
| 393 | Leek / Stick | Species-specific | INCLUDED | Raises Farfetch'd/Sirfetch'd crit ratio | |
| 394 | Thick Club | Species-specific | INCLUDED | Doubles Cubone/Marowak Attack | |
| 395 | Lucky Punch | Species-specific | INCLUDED | Raises Chansey's crit ratio | |
| 396 | Metal Powder | Species-specific | INCLUDED | Doubles Ditto's Defense (untransformed) | |
| 459 | Bright Powder | Misc. held | INCLUDED | Lowers foe's accuracy vs. holder | |
| 462 | Quick Claw | Misc. held | INCLUDED | ~20% chance to move first in-bracket | |
| 465 | King's Rock | Misc. held | INCLUDED | 10% chance to add flinch | |
| 471 | Scope Lens | Misc. held | INCLUDED | +1 crit-ratio stage | |
| 472 | Leftovers | Misc. held | **ALREADY IMPLEMENTED** | Heal 1/16 max HP/turn | |
| 514 | Cheri Berry | Berries | INCLUDED | Cures paralysis | |
| 515 | Chesto Berry | Berries | INCLUDED | Cures sleep | |
| 516 | Pecha Berry | Berries | INCLUDED | Cures poison | |
| 517 | Rawst Berry | Berries | INCLUDED | Cures burn | |
| 518 | Aspear Berry | Berries | INCLUDED | Cures freeze | |
| 519 | Leppa Berry | Berries | INCLUDED | Restores 10 PP to one move | |
| 520 | Oran Berry | Berries | INCLUDED | Restores 10 HP | |
| 521 | Persim Berry | Berries | INCLUDED | Cures confusion | |
| 522 | Lum Berry | Berries | **ALREADY IMPLEMENTED** | Cures any non-volatile status | |

## Generation III (26 items)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 425 | Silk Scarf | Type-boosting | INCLUDED | +20% Normal move power (fills the gap in the Gen II type-boost family) | |
| 442 | Choice Band | Choice items | **ALREADY IMPLEMENTED** | Atk ×1.5, move-lock | |
| 398 | Deep Sea Scale | Species-specific | INCLUDED | Doubles Clamperl's Sp.Def | |
| 399 | Deep Sea Tooth | Species-specific | INCLUDED | Doubles Clamperl's Sp.Atk | |
| 400 | Soul Dew | Species-specific | INCLUDED | needs new mechanism: pending confirmation Latios/Latias are in the species roster; Gen 7+ mechanic shape (+20% Psychic/Dragon power) differs from earlier gens (Sp.Atk/Sp.Def boost) | |
| 404 | Sea Incense | Incenses | INCLUDED | +Water move power | |
| 405 | Lax Incense | Incenses | INCLUDED | Lowers foe's accuracy vs. holder | |
| 406 | Odd Incense | Incenses | INCLUDED | +Psychic move power | |
| 407 | Rock Incense | Incenses | INCLUDED | +Rock move power | |
| 408 | Full Incense | Incenses | INCLUDED | Holder always moves last in-bracket | |
| 410 | Rose Incense | Incenses | INCLUDED | +Grass move power | |
| 460 | White Herb | Misc. held | INCLUDED | Once: restores all lowered stats | |
| 464 | Mental Herb | Misc. held | INCLUDED | Once: cures infatuation (Gen 5+: also Taunt/Encore/Torment/Disable/Heal Block, none of which exist in this project yet — scope to infatuation-cure only unless those moves are added) | |
| 523 | Sitrus Berry | Berries | **ALREADY IMPLEMENTED** | Heal 25% max HP at ≤50% HP | |
| 524 | Figy Berry | Berries | INCLUDED | Heal 1/3 max HP; confuses if nature dislikes spicy | |
| 525 | Wiki Berry | Berries | INCLUDED | Heal 1/3 max HP; confuses if nature dislikes dry | |
| 526 | Mago Berry | Berries | INCLUDED | Heal 1/3 max HP; confuses if nature dislikes sweet | |
| 527 | Aguav Berry | Berries | INCLUDED | Heal 1/3 max HP; confuses if nature dislikes bitter | |
| 528 | Iapapa Berry | Berries | INCLUDED | Heal 1/3 max HP; confuses if nature dislikes sour | |
| 567 | Liechi Berry | Berries | INCLUDED | +1 Attack at ≤25% HP | |
| 568 | Ganlon Berry | Berries | INCLUDED | +1 Defense at ≤25% HP | |
| 569 | Salac Berry | Berries | INCLUDED | +1 Speed at ≤25% HP | |
| 570 | Petaya Berry | Berries | INCLUDED | +1 Sp.Atk at ≤25% HP | |
| 571 | Apicot Berry | Berries | INCLUDED | +1 Sp.Def at ≤25% HP | |
| 572 | Lansat Berry | Berries | INCLUDED | +1 crit-ratio stage at ≤25% HP | |
| 573 | Starf Berry | Berries | INCLUDED | Sharply raises a random stat at ≤25% HP | |

## Generation IV (77 items)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 443 | Choice Specs | Choice items | **ALREADY IMPLEMENTED** | Sp.Atk ×1.5, move-lock | |
| 444 | Choice Scarf | Choice items | **ALREADY IMPLEMENTED** | Speed ×1.5, move-lock | |
| 447 | Damp Rock | Weather Rocks | **ALREADY IMPLEMENTED** | Rain → 8 turns | |
| 448 | Heat Rock | Weather Rocks | **ALREADY IMPLEMENTED** | Sun → 8 turns | |
| 449 | Smooth Rock | Weather Rocks | **ALREADY IMPLEMENTED** | Sandstorm → 8 turns | |
| 450 | Icy Rock | Weather Rocks | **ALREADY IMPLEMENTED** | Hail → 8 turns | |
| 479 | Life Orb | Misc. held | **ALREADY IMPLEMENTED** | Power ×1.3, 1/10 recoil | |
| 549 | Chilan Berry | Berries | **ALREADY IMPLEMENTED** | Halves Normal-type damage taken | |
| 550 | Occa Berry | Berries | **ALREADY IMPLEMENTED** | Halves super-effective Fire damage taken | |
| 551 | Passho Berry | Berries | INCLUDED | Halves super-effective Water damage; mechanism exists generically (`hold_effect_param`), just needs this data entry | |
| 552 | Wacan Berry | Berries | INCLUDED | Same, Electric | |
| 553 | Rindo Berry | Berries | INCLUDED | Same, Grass | |
| 554 | Yache Berry | Berries | INCLUDED | Same, Ice | |
| 555 | Chople Berry | Berries | INCLUDED | Same, Fighting | |
| 556 | Kebia Berry | Berries | INCLUDED | Same, Poison | |
| 557 | Shuca Berry | Berries | INCLUDED | Same, Ground | |
| 558 | Coba Berry | Berries | INCLUDED | Same, Flying | |
| 559 | Payapa Berry | Berries | INCLUDED | Same, Psychic | |
| 560 | Tanga Berry | Berries | INCLUDED | Same, Bug | |
| 561 | Charti Berry | Berries | INCLUDED | Same, Rock | |
| 562 | Kasib Berry | Berries | INCLUDED | Same, Ghost | |
| 563 | Haban Berry | Berries | INCLUDED | Same, Dragon | |
| 564 | Colbur Berry | Berries | INCLUDED | Same, Dark | |
| 565 | Babiri Berry | Berries | INCLUDED | Same, Steel | |
| 574 | Enigma Berry | Berries | INCLUDED | Heals 1/4 max HP when hit super-effectively | |
| 575 | Micle Berry | Berries | INCLUDED | +accuracy on next move at low HP | |
| 576 | Custap Berry | Berries | INCLUDED | Priority boost that turn at low HP | |
| 577 | Jaboca Berry | Berries | INCLUDED | Damages attacker 1/8 max HP on a physical contact hit | |
| 578 | Rowap Berry | Berries | INCLUDED | Same, special hit | |
| 401 | Adamant Orb | Species-specific | INCLUDED | needs new mechanism: pending Dialga in species roster; +20% Dragon/Steel move power | |
| 402 | Lustrous Orb | Species-specific | INCLUDED | needs new mechanism: pending Palkia in species roster; +20% Dragon/Water move power | |
| 403 | Griseous Orb | Species-specific | INCLUDED | needs new mechanism: pending Giratina in species roster; +20% Dragon/Ghost move power | |
| 250 | Flame Plate | Plates | INCLUDED | needs new mechanism: `HOLD_EFFECT_PLATE` exists (Multitype's type-source) but has no power-boost read yet; +20% Fire move power once added | |
| 251 | Splash Plate | Plates | INCLUDED | Same gap, Water | |
| 252 | Zap Plate | Plates | INCLUDED | Same gap, Electric | |
| 253 | Meadow Plate | Plates | INCLUDED | Same gap, Grass | |
| 254 | Icicle Plate | Plates | INCLUDED | Same gap, Ice | |
| 255 | Fist Plate | Plates | INCLUDED | Same gap, Fighting | |
| 256 | Toxic Plate | Plates | INCLUDED | Same gap, Poison | |
| 257 | Earth Plate | Plates | INCLUDED | Same gap, Ground | |
| 258 | Sky Plate | Plates | INCLUDED | Same gap, Flying | |
| 259 | Mind Plate | Plates | INCLUDED | Same gap, Psychic | |
| 260 | Insect Plate | Plates | INCLUDED | Same gap, Bug | |
| 261 | Stone Plate | Plates | INCLUDED | Same gap, Rock | |
| 262 | Spooky Plate | Plates | INCLUDED | Same gap, Ghost | |
| 263 | Draco Plate | Plates | INCLUDED | Same gap, Dragon | |
| 264 | Dread Plate | Plates | INCLUDED | Same gap, Dark | |
| 265 | Iron Plate | Plates | INCLUDED | Same gap, Steel | |
| 445 | Flame Orb | Status Orbs | INCLUDED | Burns holder at end of first turn held | |
| 446 | Toxic Orb | Status Orbs | INCLUDED | Badly poisons holder at end of first turn held | |
| 409 | Wave Incense | Incenses | INCLUDED | +Water move power (duplicate of Sea Incense) | |
| 473 | Shell Bell | Misc. held | INCLUDED | Heals 1/8 of damage dealt, per hit | |
| 474 | Wide Lens | Misc. held | INCLUDED | +10% accuracy | |
| 475 | Muscle Band | Misc. held | INCLUDED | +10% physical move power | |
| 476 | Wise Glasses | Misc. held | INCLUDED | +10% special move power | |
| 477 | Expert Belt | Misc. held | INCLUDED | +20% power on super-effective hits | |
| 478 | Light Clay | Misc. held | INCLUDED | Extends Reflect/Light Screen/Aurora Veil to 8 turns | |
| 480 | Power Herb | Misc. held | INCLUDED | Once: charge move executes in one turn | |
| 481 | Focus Sash | Misc. held | INCLUDED | At full HP, survives a lethal hit at 1 HP | |
| 482 | Zoom Lens | Misc. held | INCLUDED | +20% accuracy if moving after target | |
| 483 | Metronome (item) | Misc. held | INCLUDED | Power ramps to +100% over 5 same-move uses | |
| 484 | Iron Ball | Misc. held | INCLUDED | Halves Speed; grounds the holder | |
| 485 | Lagging Tail | Misc. held | INCLUDED | Holder always moves last in-bracket | |
| 486 | Destiny Knot | Misc. held | INCLUDED | Mirrors infatuation back onto its source | |
| 487 | Black Sludge | Misc. held | INCLUDED | Heals Poison-types, damages all others | |
| 488 | Grip Claw | Misc. held | INCLUDED | Extends binding moves to 7-turn max | |
| 489 | Sticky Barb | Misc. held | INCLUDED | Damages holder 1/8 max HP/turn; transfers via contact | |
| 490 | Shed Shell | Misc. held | INCLUDED | Holder can always switch out, bypasses trapping | |
| 491 | Big Root | Misc. held | INCLUDED | +30% HP recovered by drain moves | |
| 492 | Razor Claw | Misc. held | INCLUDED | +1 crit-ratio stage | |
| 493 | Razor Fang | Misc. held | INCLUDED | Same flinch effect as King's Rock | |
| 419 | Power Weight | EV Gain Modifiers | INCLUDED | non-battle EV mechanic; only the Speed-halving half is battle-visible | |
| 420 | Power Bracer | EV Gain Modifiers | INCLUDED | Same | |
| 421 | Power Belt | EV Gain Modifiers | INCLUDED | Same | |
| 422 | Power Lens | EV Gain Modifiers | INCLUDED | Same | |
| 423 | Power Band | EV Gain Modifiers | INCLUDED | Same | |
| 424 | Power Anklet | EV Gain Modifiers | INCLUDED | Same | |

## Generation V (34 items — 6 included, 28 excluded)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 267 | Douse Drive | Drives | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: reusable Plate-style pattern, Genesect-only, pending species-roster confirmation; changes Techno Blast to Water |  |
| 268 | Shock Drive | Drives | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Electric |  |
| 269 | Burn Drive | Drives | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fire |  |
| 270 | Chill Drive | Drives | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ice |  |
| 339 | Normal Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. One-time consumed +30%/+50% power boost (gen-config nuance) on a matching-type move |  |
| 340 | Fire Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fire |  |
| 341 | Water Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Water |  |
| 342 | Electric Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Electric |  |
| 343 | Grass Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Grass |  |
| 344 | Ice Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ice |  |
| 345 | Fighting Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fighting |  |
| 346 | Poison Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Poison |  |
| 347 | Ground Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ground |  |
| 348 | Flying Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Flying |  |
| 349 | Psychic Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Psychic |  |
| 350 | Bug Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Bug |  |
| 351 | Rock Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Rock |  |
| 352 | Ghost Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ghost |  |
| 353 | Dragon Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Dragon |  |
| 354 | Dark Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Dark |  |
| 355 | Steel Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Steel |  |
| 356 | Fairy Gem | Gems | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fairy |  |
| 455 | Absorb Bulb | Type-activated | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Consumed on a Water hit, +1 Sp.Atk |  |
| 456 | Cell Battery | Type-activated | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Consumed on an Electric hit, +1 Atk |  |
| 458 | Snowball | Type-activated | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Consumed on an Ice hit, +1 Atk |  |
| 494 | Eviolite | Misc. held | INCLUDED | +50% Def/Sp.Def for not-fully-evolved Pokémon — explicitly included (Gen V+ override) |  |
| 495 | Float Stone | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Halves holder's weight |  |
| 496 | Rocky Helmet | Misc. held | INCLUDED | Damages attacker 1/6 max HP on contact — explicitly included (Gen V+ override) |  |
| 497 | Air Balloon | Misc. held | INCLUDED | Grants Ground-move immunity; popped on any hit — explicitly included (Gen V+ override) |  |
| 498 | Red Card | Misc. held | INCLUDED | Forces attacker to switch out (consumed) — explicitly included (Gen V+ override) |  |
| 499 | Ring Target | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Removes one type immunity vs. the attacking type |  |
| 500 | Binding Band | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Raises binding-move damage 1/8 → 1/6 max HP |  |
| 501 | Eject Button | Misc. held | INCLUDED | Forces holder to switch out after being hit — explicitly included (Gen V+ override) |  |
| 502 | Weakness Policy | Misc. held | INCLUDED | Consumed on a super-effective hit; +2 Atk/Sp.Atk — explicitly included (Gen V+ override) |  |

## Generation VI (56 items — 6 included, 50 excluded: 47 Mega Stone + 3 Gen V+ not listed)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 266 | Pixie Plate | Plates | INCLUDED | Same Plate-mechanism gap as the 16 Gen IV Plates; Fairy — explicitly included (Gen V+ override) |  |
| 457 | Luminous Moss | Type-activated | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Consumed on a Water hit, +1 Sp.Def |  |
| 566 | Roseli Berry | Berries | INCLUDED | Halves super-effective Fairy damage; mechanism exists generically, needs this data entry — explicitly included (Gen V+ override) |  |
| 579 | Kee Berry | Berries | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. +1 Defense when hit by a physical move |  |
| 580 | Maranga Berry | Berries | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. +1 Sp.Def when hit by a special move |  |
| 503 | Assault Vest | Misc. held | INCLUDED | +50% Sp.Def; holder cannot use status moves — explicitly included (Gen V+ override) |  |
| 504 | Safety Goggles | Misc. held | INCLUDED | Blocks weather chip damage AND powder/spore moves — closes the loop `docs/m17-5_recon.md` flagged (Safety Goggles was the one unimplemented exemption for Grass-type powder immunity) — explicitly included (Gen V+ override) |  |
| 290 | Red Orb | Colored Orbs | INCLUDED | needs new mechanism: automatic switch-in Primal Reversion trigger for Groudon — the ability it grants (Desolate Land) already exists (`[M17d]`), only the Orb-triggered form-change is missing — explicitly included (Gen V+ override) |  |
| 291 | Blue Orb | Colored Orbs | INCLUDED | Same, Kyogre / Primordial Sea — explicitly included (Gen V+ override) |  |
| 292 | Venusaurite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 293 | Charizardite X | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 294 | Charizardite Y | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 295 | Blastoisinite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 296 | Beedrillite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 297 | Pidgeotite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 298 | Alakazite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 299 | Slowbronite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 300 | Gengarite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 301 | Kangaskhanite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 302 | Pinsirite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 303 | Gyaradosite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 304 | Aerodactylite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 305 | Mewtwonite X | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 306 | Mewtwonite Y | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 307 | Ampharosite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 308 | Steelixite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 309 | Scizorite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 310 | Heracronite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 311 | Houndoominite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 312 | Tyranitarite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 313 | Sceptilite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 314 | Blazikenite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 315 | Swampertite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 316 | Gardevoirite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 317 | Sablenite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 318 | Mawilite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 319 | Aggronite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 320 | Medichamite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 321 | Manectite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 322 | Sharpedonite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 323 | Cameruptite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 324 | Altarianite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 325 | Banettite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 326 | Absolite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 327 | Glalitite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 328 | Salamencite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 329 | Metagrossite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 330 | Latiasite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 331 | Latiosite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 332 | Lopunnite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 333 | Garchompite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 334 | Lucarionite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 335 | Abomasite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 336 | Galladite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 337 | Audinite | Mega Stones | **EXCLUDED — Mega Stone** | | |
| 338 | Diancite | Mega Stones | **EXCLUDED — Mega Stone** | | |

## Generation VII (59 items — 1 included, 58 excluded: 35 Z-Crystal + 23 Gen V+ not listed)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 271 | Fire Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: reusable Plate/Drive-style pattern, Silvally-only (Silvally's own RKS System ability is separately already excluded per `[M17n-4]`, pending species-roster confirmation); changes Multi-Attack + Silvally's own type |  |
| 272 | Water Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Water |  |
| 273 | Electric Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Electric |  |
| 274 | Grass Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Grass |  |
| 275 | Ice Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ice |  |
| 276 | Fighting Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fighting |  |
| 277 | Poison Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Poison |  |
| 278 | Ground Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ground |  |
| 279 | Flying Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Flying |  |
| 280 | Psychic Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Psychic |  |
| 281 | Bug Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Bug |  |
| 282 | Rock Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Rock |  |
| 283 | Ghost Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Ghost |  |
| 284 | Dragon Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Dragon |  |
| 285 | Dark Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Dark |  |
| 286 | Steel Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Steel |  |
| 287 | Fairy Memory | Memories | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fairy |  |
| 451 | Electric Seed | Terrain Seeds | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: this project's Terrain system is void (`[M17e]`, Rob's locked decision) — moot unless Terrain is reconsidered; consumed on switch-in during Electric Terrain, +1 Def |  |
| 452 | Psychic Seed | Terrain Seeds | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same dependency, Psychic Terrain, +1 Sp.Def |  |
| 453 | Misty Seed | Terrain Seeds | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same dependency, Misty Terrain, +1 Sp.Def |  |
| 454 | Grassy Seed | Terrain Seeds | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same dependency, Grassy Terrain, +1 Def |  |
| 505 | Adrenaline Orb | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Consumed when targeted by Intimidate, +1 Speed |  |
| 506 | Terrain Extender | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: same Terrain-system dependency as the 4 Seeds above |  |
| 507 | Protective Pads | Misc. held | INCLUDED | Blocks contact-triggered side effects taken by the holder — explicitly included (Gen V+ override) |  |
| 357 | Normalium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 358 | Firium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 359 | Waterium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 360 | Electrium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 361 | Grassium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 362 | Icium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 363 | Fightinium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 364 | Poisonium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 365 | Groundium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 366 | Flyinium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 367 | Psychium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 368 | Buginium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 369 | Rockium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 370 | Ghostium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 371 | Dragonium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 372 | Darkinium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 373 | Steelium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 374 | Fairium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | | |
| 375 | Pikanium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Pikachu) |
| 376 | Eevium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Eevee) |
| 377 | Snorlium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Snorlax) |
| 378 | Mewnium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Mew) |
| 379 | Decidium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Decidueye) |
| 380 | Incinium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Incineroar) |
| 381 | Primarium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Primarina) |
| 382 | Lycanium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Lycanroc) |
| 383 | Mimikium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Mimikyu) |
| 384 | Kommonium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Kommo-o) |
| 385 | Tapunium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Tapu family) |
| 386 | Solganium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Solgaleo) |
| 387 | Lunalium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Lunala) |
| 388 | Marshadium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Marshadow) |
| 389 | Aloraichium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Alolan Raichu) |
| 390 | Pikashunium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, partner Pikachu) |
| 391 | Ultranecrozium Z | Z-Crystals | **EXCLUDED — Z-Crystal** | (signature, Ultra Necrozma) |

## Generation VIII (8 items — 5 included, 3 excluded)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 288 | Rusted Sword | Form-changing (held) | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: permanent Hero↔Crowned form change on holding, Zacian-only, pending species-roster confirmation; expressible via existing type-mutation infra (`_set_mon_type`, `[M16e]`/`[M17n-4]`) |  |
| 289 | Rusted Shield | Form-changing (held) | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Zamazenta |  |
| 508 | Throat Spray | Misc. held | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. +1 Sp.Atk whenever holder uses a sound move; this project already has a `sound_move` flag wired (`[M17n-1]`/`[M17n-6]`) — should be cheap |  |
| 509 | Eject Pack | Misc. held | INCLUDED | Forces holder to switch out whenever any of its stats are lowered — explicitly included (Gen V+ override) |  |
| 510 | Heavy-Duty Boots | Misc. held | **ALREADY IMPLEMENTED** | Full hazard immunity on switch-in — explicitly included (Gen V+ override) |  |
| 511 | Blunder Policy | Misc. held | INCLUDED | Consumed when holder's move misses; +2 Speed — explicitly included (Gen V+ override) |  |
| 512 | Room Service | Misc. held | INCLUDED | Consumed on switch-in during Trick Room; −1 Speed; this project already has Trick Room (`[M16d]`) — should be cheap — explicitly included (Gen V+ override) |  |
| 513 | Utility Umbrella | Misc. held | **ALREADY IMPLEMENTED** | Negates rain/sun for the holder — explicitly included (Gen V+ override) |  |

## Generation IX (80 items — 6 included, 74 excluded: 65 structural (20 Tera + 45 Mega Stone) + 9 Gen V+ not listed)

| ID | Name | Category | Status | Notes | Rob's override |
|---|---|---|---|---|---|
| 758 | Ability Shield | Gen IX battle items | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Blocks holder's own ability from being changed/suppressed/negated |  |
| 759 | Clear Amulet | Gen IX battle items | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Blocks external stat-lowering |  |
| 760 | Punching Glove | Gen IX battle items | INCLUDED | +10% punching-move power, strips contact flag; this project already has a `punching_move` flag + `move_makes_contact()` wrapper (`[M17n-5]`) — should be cheap — explicitly included (Gen V+ override) |  |
| 761 | Covert Cloak | Gen IX battle items | INCLUDED | Blocks secondary/additional effects of moves used against the holder — explicitly included (Gen V+ override) |  |
| 762 | Loaded Dice | Gen IX battle items | INCLUDED | needs new mechanism: this project has no multi-hit-move mechanism at all (same gap that deferred Skill Link, `[M17n-5]`) — explicitly included (Gen V+ override) |  |
| 764 | Booster Energy | Gen IX battle items | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: activates Protosynthesis/Quark Drive, both already-excluded abilities — moot unless those are reconsidered |  |
| 769 | Mirror Herb | Gen IX battle items | INCLUDED | Once: copies an opponent's stat increase; this project already has an analogous "copy opponent's stat increase" shape via Opportunist (`[M17n-8]`) — likely a cheap adjacent add — explicitly included (Gen V+ override) |  |
| 792 | Adamant Crystal | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: Origin-forme Dialga equivalent of Adamant Orb, pending species/form-roster confirmation |  |
| 793 | Griseous Core | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Origin-forme Giratina |  |
| 794 | Lustrous Globe | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Origin-forme Palkia |  |
| 798 | Berserk Gene | Misc. held | INCLUDED | *(true generation-introduced is Gen II — a revived Gen II item just assigned a high ID in this ROM hack's table; reclassified under the Gen I-IV blanket-include rule despite its Gen IX table placement)* Sharply raises Attack but confuses the holder, then consumed |  |
| 799 | Fairy Feather | Type-boosting | INCLUDED | +20% Fairy move power; closes the Gen VI Fairy-type gap in the Charcoal-family set — explicitly included (Gen V+ override) |  |
| 803 | Cornerstone Mask | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. needs new mechanism: Ogerpon-only form/type change while held, pending species-roster confirmation — corrected from the recon's bundling with Terastallization (see corrections above); the base mask-holding effect is independent of Terastallizing |  |
| 804 | Wellspring Mask | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Water-type form |  |
| 805 | Hearthflame Mask | Species-specific | **EXCLUDED — Gen V+, not listed** | Excluded — Gen V+, not on Rob's explicit inclusion list. Same, Fire-type form |  |
| 772 | Tera Orb | Tera items | **EXCLUDED — Terastallization** | | |
| 774 | Bug Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 775 | Dark Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 776 | Dragon Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 777 | Electric Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 778 | Fairy Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 779 | Fighting Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 780 | Fire Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 781 | Flying Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 782 | Ghost Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 783 | Grass Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 784 | Ground Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 785 | Ice Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 786 | Normal Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 787 | Poison Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 788 | Psychic Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 789 | Rock Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 790 | Steel Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 791 | Water Tera Shard | Tera items | **EXCLUDED — Terastallization** | | |
| 815 | Stellar Tera Shard | Tera items | **EXCLUDED — Terastallization** | (the 19th shard, listed later in source's ID order but same category) | |
| 829 | Clefablite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | Not in mainline canon; see corrections note above | |
| 830 | Victreebelite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 831 | Starminite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 832 | Dragoninite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | (Dragonite) | |
| 833 | Meganiumite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 834 | Feraligite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 835 | Skarmorite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 836 | Froslassite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 837 | Emboarite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 838 | Excadrite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 839 | Scolipite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 840 | Scraftinite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 841 | Eelektrossite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 842 | Chandelurite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 843 | Chesnaughtite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 844 | Delphoxite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 845 | Greninjite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 846 | Pyroarite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 847 | Floettite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 848 | Malamarite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 849 | Barbaracite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 850 | Dragalgite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 851 | Hawluchanite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 852 | Zygardite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 853 | Drampanite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 854 | Falinksite | Mega Stones (Legends Z-A) | **EXCLUDED — Mega Stone** | | |
| 855 | Heatranite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 856 | Darkranite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 857 | Zeraorite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 858 | Raichunite X | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 859 | Raichunite Y | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 860 | Chimechite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 861 | Absolite Z | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 862 | Staraptite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 863 | Garchompite Z | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 864 | Lucarionite Z | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 865 | Golurkite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 866 | Meowsticite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 867 | Crabominite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 868 | Golisopite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 869 | Magearnite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 870 | Scovillainite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 871 | Baxcalibrite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 872 | Tatsugirinite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |
| 873 | Glimmoranite | Mega Stones (Legends Z-A DLC) | **EXCLUDED — Mega Stone** | | |

---

## Maintenance

This ledger is the single source of truth for M18's held-item scope going forward —
**update it in place, don't re-derive a count from scratch**, mirroring the discipline
established for `docs/m17_final_ledger.md`.

- **New scope rule shape, as of this update:** status is no longer "included by
  default except three structural categories" — it's now "Gen I-IV blanket include,
  plus a named 23-item Gen V+ override list, everything else Gen V+ excluded." If Rob
  ever adds a NEW item to the Gen V+ override list, update that row's Status to
  `INCLUDED` and its Notes to say "explicitly included (Gen V+ override)," matching
  the existing 23 rows' exact phrasing — don't just flip the word without adding the
  reason, since a future reader needs to know WHY a lone Gen VI+ item is included
  when its neighbors aren't.
- **When Rob adds further individual exclusions on top of either rule** (the
  promised follow-up list): fill in the "Rob's override" column for each affected row
  (e.g. `EXCLUDE — reason`) rather than deleting the row — keeps the full catalog
  intact and the decision auditable.
- **When an item gets implemented**: update its Status cell to `**ALREADY
  IMPLEMENTED**` and move its Notes to describe the actual `HOLD_EFFECT_*` constant and
  named `.tres`/data entry used, the same way this ledger's own "already implemented"
  rows are written now — don't just delete the row, since future sessions checking
  "is X implemented" should be able to answer it from this one file.
- **If a "needs new mechanism" item's blocker gets resolved** (e.g. Terrain is
  un-voided, a species roster gets confirmed, multi-hit moves get built): update that
  row's Notes to drop the blocker language, since it becomes a plain data-entry item
  from that point on.
- **If new items are ever discovered in a source update** (this reference clone has
  already shown it tracks very recent game content — see the Legends Z-A finding
  above): re-run the same `include/constants/items.h` read this session did, diff
  against this ledger's ID list, and append only the new rows — do not regenerate the
  whole document.
- **Total counts in the Summary table must be re-verified, not incremented by
  assumption**, any time a batch of rows changes status — this project has been burned
  before (`docs/decisions.md`'s `[M17f]`/`[M17g]`/`[M17n-7]` assertion-count drift) by
  trusting a carried-forward number instead of recounting.
