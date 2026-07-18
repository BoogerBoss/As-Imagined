# M25 Pre-Recon — Full Non-Held (Bag) Item Scoping

**Status: RECON ONLY — no implementation code touched in this session.** Does not
modify `CLAUDE.md`, `docs/decisions.md`, `docs/m18_recon.md`, or
`docs/m18_item_ledger.md`. This gets ahead of a future milestone (M25 or whenever Rob
picks this up) while item-related context is fresh — it is not a signal to start
implementation now, and nothing here should be acted on until Rob reviews and scopes
it explicitly, matching the exact recon-then-decide pattern already used for M17/M18.

**Total scope of this document: 498 items** — every real item ID in
`include/constants/items.h` (873 total, IDs 1–873) that is NOT already in
`docs/m18_item_ledger.md`'s 375-item held-item ledger. This was derived
**programmatically** (a full diff of the source enum against the ledger's exact ID
list), not by hand-recounting the earlier recon's category buckets — see the
Methodology note below for why that mattered.

---

## Methodology note, and three real gaps this diff found in the M18 held-item ledger

Per this task's instruction to re-derive and re-verify rather than copy
`docs/m18_recon.md`'s Section B.3 forward, I extracted the complete list of real item
IDs directly from `include/constants/items.h` (873 items, confirmed — two of them,
`ITEM_ORANGE_MAIL = 199` and `ITEM_CHERI_BERRY = 514`, are expressed via a
`FIRST_MAIL_INDEX`/`FIRST_BERRY_INDEX` alias rather than a literal number, which an
earlier naive count could miss) and diffed it against every ID actually listed in
`docs/m18_item_ledger.md`. **498 IDs are in source but not in that ledger** — this
document's actual scope.

**This diff surfaced three items that appear to be genuine oversights in the M18
held-item ledger, not bag items at all** — flagging clearly rather than silently
folding them into this document's non-held-item scope, since they don't belong here:

1. **Quick Powder (ID 397)** — doubles Ditto's Speed while not transformed, the exact
   same shape as Metal Powder (ID 396, Defense-doubling), which the M18 ledger DOES
   include. Quick Powder appears to have been dropped by oversight.
2. **Macho Brace (ID 418)** — the base EV-Gain-Modifier item; the M18 ledger includes
   its six derived "Power Weight/Bracer/Belt/Lens/Band/Anklet" items (419–424) but not
   Macho Brace itself.
3. **Focus Band (ID 469)** — a 10% chance to survive a lethal hit at 1 HP, mechanically
   almost identical to Focus Sash (ID 481, which the M18 ledger DOES include). Also
   appears dropped by oversight.

**Recommendation:** these three should be added to `docs/m18_item_ledger.md` (as
Gen II/III INCLUDED rows under the existing Gen I–IV blanket-include rule, since all
three predate Gen V) rather than treated as part of this bag-item recon's scope — no
edit was made to that file in this session per its explicit exclusion from this
task's scope, but Rob should be aware before that ledger is next touched.

Every other item in the 498-item non-held set was confirmed to genuinely belong here
— no other held-item candidates were found hiding in the bag-item categories.

---

## Section A — Full non-held item enumeration, by generation then category

**Implementation status: uniformly NOT IMPLEMENTED for all 498 items** — confirmed by
reading `scripts/battle/core/item_manager.gd` in full: it contains zero references to
`bag`, `inventory`, or any bag-item concept at all (see Section B.1). There is nothing
partially built here to report.

Categories with a large run of near-identical items (Mints, TM/HM) are still listed
per-item per this task's instruction, except TM/HM which gets a bulk citation instead
of 108 rows — see the explicit rationale in Section B.5.

### Generation I

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 1 | Poké Ball | Poké Balls | Catches wild Pokémon, standard rate | |
| 2 | Great Ball | Poké Balls | 1.5× catch rate | |
| 3 | Ultra Ball | Poké Balls | 2× catch rate | |
| 4 | Master Ball | Poké Balls | Catches without fail | |
| 23 | Safari Ball | Poké Balls | Standard rate, Safari Zone only | |
| 28 | Potion | Medicine | Heals 20 HP | |
| 29 | Super Potion | Medicine | Heals 50/60 HP | |
| 30 | Hyper Potion | Medicine | Heals 120/200 HP | |
| 31 | Max Potion | Medicine | Fully restores HP | |
| 32 | Full Restore | Medicine | Fully restores HP + cures status | |
| 33 | Revive | Medicine | Revives at half HP | |
| 35 | Fresh Water | Medicine | Heals 30/50 HP | |
| 36 | Soda Pop | Medicine | Heals 50/60 HP | |
| 39 | Energy Powder | Medicine | Heals 50/60 HP, lowers friendship | |
| 40 | Energy Root | Medicine | Heals 120/200 HP, lowers friendship more | |
| 41 | Heal Powder | Medicine | Cures all status, lowers friendship | |
| 42 | Revival Herb | Medicine | Fully revives, lowers friendship | |
| 43 | Antidote | Medicine | Cures poison | |
| 44 | Paralyze Heal | Medicine | Cures paralysis | |
| 45 | Burn Heal | Medicine | Cures burn | |
| 46 | Ice Heal | Medicine | Cures freeze | |
| 47 | Awakening | Medicine | Cures sleep | |
| 48 | Full Heal | Medicine | Cures all status | |
| 49 | Ether | Medicine | Restores 10 PP to one move | |
| 50 | Max Ether | Medicine | Fully restores PP to one move | |
| 51 | Elixir | Medicine | Restores 10 PP to all moves | |
| 52 | Max Elixir | Medicine | Fully restores PP to all moves | |
| 54 | Sacred Ash | Medicine | Revives + fully heals entire party (field-only per source, no `battleUsage`) | |
| 65 | HP Up | Vitamins | Raises HP EVs | |
| 66 | Protein | Vitamins | Raises Attack EVs | |
| 67 | Iron | Vitamins | Raises Defense EVs | |
| 68 | Calcium | Vitamins | Raises Sp.Atk EVs | |
| 69 | Zinc | Vitamins | Raises Sp.Def EVs | |
| 70 | Carbos | Vitamins | Raises Speed EVs | |
| 71 | PP Up | Vitamins | Raises a move's max PP | |
| 102 | Rare Candy | Candy | Raises level by 1 | |
| 114 | Repel | Encounter Modifiers | Repels weak wild Pokémon, 100 steps | |
| 115 | Super Repel | Encounter Modifiers | Same, 200 steps | |
| 116 | Max Repel | Encounter Modifiers | Same, 250 steps | |
| 120 | Escape Rope | Encounter Modifiers | Instant escape from a cave/dungeon | |
| 121 | X Attack | X Items | +1(or 2) Attack stage for the battle | |
| 122 | X Defense | X Items | +1(or 2) Defense stage | |
| 123 | X Special (Sp.Atk) | X Items | +1(or 2) Sp.Atk stage | |
| 125 | X Speed | X Items | +1(or 2) Speed stage | |
| 126 | X Accuracy | X Items | +1(or 2) accuracy stage | |
| 127 | Dire Hit | X Items | Raises crit ratio for the battle (Focus-Energy-shaped) | |
| 128 | Guard Spec. | X Items | Mist-style block on the user's side's stat drops | |
| 129 | Poké Doll | Escape Items | Guarantees escape from a wild battle | |
| 135 | Nugget | Treasures | Pure sell item | |
| 165 | Helix Fossil | Fossils | Revives into Omanyte (menu-only) | |
| 166 | Dome Fossil | Fossils | Revives into Kabuto | |
| 167 | Old Amber | Fossils | Revives into Aerodactyl | |
| 211 | Fire Stone | Evolution Items | Evolves certain Pokémon (bag/menu use) | |
| 212 | Water Stone | Evolution Items | Same | |
| 213 | Thunder Stone | Evolution Items | Same | |
| 214 | Leaf Stone | Evolution Items | Same | |
| 217 | Moon Stone | Evolution Items | Same | |
| 461 | Exp. Share | Misc. bag items | Gives partial/full Exp. to a non-battling party member (mechanic reworked Gen VI) | |
| 706 | Bicycle | Misc. Key Items | Overworld movement | |
| 709 | Old Rod | Misc. Key Items | Overworld fishing | |
| 710 | Good Rod | Misc. Key Items | Overworld fishing | |
| 711 | Super Rod | Misc. Key Items | Overworld fishing | |
| 713 | Town Map | Misc. Key Items | Overworld navigation | |
| 715 | TM Case | Misc. Key Items | Menu storage UI | |
| 717 | Pokémon Box Link | Misc. Key Items | Menu storage UI | |
| 718 | Coin Case | Misc. Key Items | Menu currency (Game Corner) | |
| 724 | Poké Flute | Misc. Key Items | Wakes a blocking sleeping Pokémon / cures party sleep outside battle | |
| 727 | S.S. Ticket | Story Key Items | Story flag | |
| 729 | Mystic Ticket | Story Key Items | Story flag (Navel Rock access) | |
| 746 | Parcel (Oak's Parcel) | Story Key Items | Story quest item | |
| 747 | Secret Key | Story Key Items | Story quest item (Mauville Gym) | |
| 748 | Bike Voucher | Story Key Items | Story quest item | |
| 749 | Gold Teeth | Story Key Items | Story quest item | |
| 750 | Card Key | Story Key Items | Story quest item (Rocket Hideout/Silph Co.) | |
| 751 | Lift Key | Story Key Items | Story quest item | |
| 752 | Silph Scope | Story Key Items | Reveals Ghosts in Pokémon Tower | |
| 755 | Tea | Story Key Items | Story quest item (Team Rocket guard bribe) | |
| 466 | Amulet Coin | Misc. bag items | Doubles trainer-battle prize money | |
| 468 | Smoke Ball | Misc. bag items | Guarantees flee from a wild Pokémon | |
| 470 | Lucky Egg | Misc. bag items | ×1.5 Exp. earned by the holder | |
| 124 | X Sp. Def | X Items | +1(or 2) Sp.Def stage *(Gen II addition after the special-stat split — placed here for X-Item-family completeness)* | |

### Generation II

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 7 | Net Ball | Poké Balls | Boosted vs. Water/Bug | |
| 15 | Level Ball | Poké Balls | Rate scales with level advantage | |
| 16 | Lure Ball | Poké Balls | Boosted for fishing encounters | |
| 17 | Moon Ball | Poké Balls | Boosted vs. Moon-Stone evolution line | |
| 18 | Friend Ball | Poké Balls | Raises caught Pokémon's friendship | |
| 19 | Love Ball | Poké Balls | Boosted vs. opposite-gender-of-lead species | |
| 20 | Fast Ball | Poké Balls | Boosted vs. high-Speed species | |
| 21 | Heavy Ball | Poké Balls | Rate scales with target's weight | |
| 24 | Sport Ball | Poké Balls | Standard rate, Bug-Catching Contest only | |
| 34 | Max Revive | Medicine | Revives at full HP | |
| 37 | Lemonade | Medicine | Heals 70/80 HP | |
| 38 | Moomoo Milk | Medicine | Heals 100 HP | |
| 53 | Berry Juice | Medicine | Heals 20 HP; source shows no `battleUsage` distinct from field use, unlike some Medicine items that are battle-only — the ledger built for `docs/m18_recon.md` noted a historical held-item usage of this exact item (e.g. a Gen II Trainer's Chansey holding it), but there is only ONE item ID here, filed by source under Medicine, not under any held-item category block | |
| 55 | Sweet Heart | Medicine | Heals 20 HP | |
| 57 | Pewter Crunchies | Regional Specialties | Cures all status | |
| 58 | Rage Candy Bar | Regional Specialties | Cures all status | |
| 72 | PP Max | Vitamins | Raises a move's max PP to its cap | |
| 109 | Blue Flute | Medicinal Flutes | Wakes a sleeping Pokémon | |
| 110 | Yellow Flute | Medicinal Flutes | Cures confusion (battle-only) | |
| 111 | Red Flute | Medicinal Flutes | Cures infatuation (battle-only) | |
| 112 | Black Flute | Encounter-modifying Flutes | Reduces wild encounter rate | |
| 113 | White Flute | Encounter-modifying Flutes | Increases wild encounter rate | |
| 216 | Sun Stone | Evolution Items | Evolves certain Pokémon | |
| 227 | Dragon Scale | Evolution Items | Held-until-trade evolution trigger (Seadra→Kingdra); no other battle `holdEffect` | |
| 228 | Upgrade | Evolution Items | Held-until-trade trigger (Porygon→Porygon2) | |
| 245 | Everstone | Evolution Items | Held item — blocks ALL evolution while held (`HOLD_EFFECT_PREVENT_EVOLVE`); no in-battle effect | |
| 188 | Red Apricorn | Apricorns | Ball-crafting ingredient | |
| 189 | Blue Apricorn | Apricorns | Same | |
| 190 | Yellow Apricorn | Apricorns | Same | |
| 191 | Green Apricorn | Apricorns | Same | |
| 192 | Pink Apricorn | Apricorns | Same | |
| 193 | White Apricorn | Apricorns | Same | |
| 194 | Black Apricorn | Apricorns | Same | |
| 137 | Tiny Mushroom | Treasures | Pure sell item | |
| 138 | Big Mushroom | Treasures | Pure sell item | |
| 140 | Pearl | Treasures | Pure sell item | |
| 141 | Big Pearl | Treasures | Pure sell item | |
| 143 | Stardust | Treasures | Pure sell item | |
| 144 | Star Piece | Treasures | Pure sell item, higher value | |
| 469 | Focus Band | Misc. bag items | *(see the found-gap note above — likely belongs in the M18 held-item ledger, not here)* | |

### Generation III

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 5 | Premier Ball | Poké Balls | Standard rate, bonus-purchase ball | |
| 8 | Nest Ball | Poké Balls | Rate scales inversely with target's level | |
| 9 | Dive Ball | Poké Balls | Boosted underwater/fishing | |
| 11 | Timer Ball | Poké Balls | Rate improves with turns elapsed | |
| 13 | Repeat Ball | Poké Balls | Boosted vs. previously-caught species | |
| 14 | Luxury Ball | Poké Balls | Standard rate, faster friendship gain | |
| 59 | Lava Cookie | Regional Specialties | Cures all status | |
| 130 | Fluffy Tail | Escape Items | Guarantees escape from a wild battle | |
| 146 | Shoal Salt | Treasures | Crafting component (Shoal Cave) | |
| 147 | Shoal Shell | Treasures | Crafting component | |
| 148 | Red Shard | Treasures | Shard Trader currency | |
| 149 | Blue Shard | Treasures | Shard Trader currency | |
| 150 | Yellow Shard | Treasures | Shard Trader currency | |
| 151 | Green Shard | Treasures | Shard Trader currency | |
| 152 | Heart Scale | Treasures | Move Reminder currency | |
| 168 | Root Fossil | Fossils | Revives into Lileep | |
| 169 | Claw Fossil | Fossils | Revives into Anorith | |
| 199 | Orange Mail | Mail | Cosmetic held item, no battle `holdEffect` | |
| 200 | Harbor Mail | Mail | Same | |
| 201 | Glitter Mail | Mail | Same | |
| 202 | Mech Mail | Mail | Same | |
| 203 | Wood Mail | Mail | Same | |
| 204 | Wave Mail | Mail | Same | |
| 205 | Bead Mail | Mail | Same | |
| 206 | Shadow Mail | Mail | Same | |
| 207 | Tropic Mail | Mail | Same | |
| 208 | Dream Mail | Mail | Same | |
| 209 | Fab Mail | Mail | Same | |
| 210 | Retro Mail | Mail | Same | |
| 229 | Protector | Evolution Items | Held-until-trade trigger (Rhydon→Rhyperior origin — actually Gen IV, see note* below) | |
| 411 | Luck Incense | Incenses | Doubles trainer-battle prize money (non-battle mechanic) | |
| 412 | Pure Incense | Incenses | Repels wild encounters (non-battle mechanic) | |
| 413 | Red Scarf | Contest Scarves | Raises Cool in Contests; no battle `holdEffect` | |
| 414 | Blue Scarf | Contest Scarves | Raises Beauty; no battle effect | |
| 415 | Pink Scarf | Contest Scarves | Raises Cute; no battle effect | |
| 416 | Green Scarf | Contest Scarves | Raises Smart; no battle effect | |
| 417 | Yellow Scarf | Contest Scarves | Raises Tough; no battle effect | |
| 418 | Macho Brace | EV Gain Modifiers | *(see the found-gap note above — likely belongs in the M18 held-item ledger, not here)* | |
| 463 | Soothe Bell | Misc. bag items | Boosts friendship gain rate (non-battle) | |
| 467 | Cleanse Tag | Misc. bag items | Repels wild encounters (non-battle) | |
| 529 | Razz Berry | Berries | Pokéblock/Poffin ingredient, no battle effect | |
| 530 | Bluk Berry | Berries | Same | |
| 531 | Nanab Berry | Berries | Same | |
| 532 | Wepear Berry | Berries | Same | |
| 533 | Pinap Berry | Berries | Same | |
| 534 | Pomeg Berry | Berries | Lowers HP EVs, raises friendship | |
| 535 | Kelpsy Berry | Berries | Lowers Attack EVs, raises friendship | |
| 536 | Qualot Berry | Berries | Lowers Defense EVs, raises friendship | |
| 537 | Hondew Berry | Berries | Lowers Sp.Atk EVs, raises friendship | |
| 538 | Grepa Berry | Berries | Lowers Sp.Def EVs, raises friendship | |
| 539 | Tamato Berry | Berries | Lowers Speed EVs, raises friendship | |
| 540 | Cornn Berry | Berries | Pokéblock ingredient | |
| 541 | Magost Berry | Berries | Pokéblock ingredient | |
| 542 | Rabuta Berry | Berries | Pokéblock ingredient | |
| 543 | Nomel Berry | Berries | Pokéblock ingredient | |
| 544 | Spelon Berry | Berries | Pokéblock ingredient | |
| 545 | Pamtre Berry | Berries | Pokéblock ingredient | |
| 546 | Watmel Berry | Berries | Pokéblock ingredient | |
| 547 | Durin Berry | Berries | Pokéblock ingredient | |
| 548 | Belue Berry | Berries | Pokéblock ingredient | |
| 581 | Enigma Berry (E-Reader) | Berries | Japan-exclusive duplicate of the Gen IV Enigma Berry (which IS a held item, already in the M18 ledger) | |
| 707 | Mach Bike | Misc. Key Items | Overworld movement | |
| 708 | Acro Bike | Misc. Key Items | Overworld movement | |
| 712 | Dowsing Machine | Misc. Key Items | Overworld item detection | |
| 719 | Powder Jar | Misc. Key Items | Menu storage | |
| 720 | Wailmer Pail | Misc. Key Items | Overworld berry-tree watering | |
| 722 | Pokéblock Case | Misc. Key Items | Menu storage (Contests) | |
| 725 | Fame Checker | Misc. Key Items | Menu NPC-info tool | |
| 726 | Teachy TV | Misc. Key Items | Menu tutorial replay | |
| 728 | Eon Ticket | Story Key Items | Story flag (Southern Island) | |
| 730 | Aurora Ticket | Story Key Items | Story flag (Birth Island) | |
| 731 | Old Sea Map | Story Key Items | Story flag (Faraway Island) | |
| 732 | Letter | Story Key Items | Story quest item | |
| 733 | Devon Parts | Story Key Items | Story quest item | |
| 734 | Go-Goggles | Story Key Items | Story quest item (desert traversal) | |
| 735 | Devon Scope | Story Key Items | Reveals Kecleon | |
| 736 | Basement Key | Story Key Items | Story quest item | |
| 737 | Scanner | Story Key Items | Story quest item | |
| 738 | Storage Key | Story Key Items | Story quest item | |
| 739 | Key to Room 1 | Story Key Items | Story quest item | |
| 740 | Key to Room 2 | Story Key Items | Story quest item | |
| 741 | Key to Room 4 | Story Key Items | Story quest item | |
| 742 | Key to Room 6 | Story Key Items | Story quest item | |
| 743 | Meteorite | Story Key Items | Story quest item (Mossdeep) | |
| 744 | Magma Emblem | Story Key Items | Story flag (Groudon encounter gate) | |
| 745 | Contest Pass | Story Key Items | Unlocks Contest entry | |
| 753 | Tri Pass | Story Key Items | Story flag (ferry route) | |
| 754 | Rainbow Pass | Story Key Items | Story flag (ferry route) | |
| 756 | Ruby | Story Key Items | Story quest item | |
| 757 | Sapphire | Story Key Items | Story quest item | |

*Note: Protector (229) and several other "held + trade" evolution items were placed
in Gen III/IV somewhat approximately by category-block proximity rather than exact
per-item release-date verification for every one of the 35 evolution items — flagged
as approximate confidence where noted; the Gen I–III batch (Fire/Water/Thunder/Leaf/
Moon Stone, Sun Stone, Dragon Scale, Upgrade, Everstone) is high-confidence.*

### Generation IV

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 6 | Heal Ball | Poké Balls | Catches + fully heals on capture | |
| 10 | Dusk Ball | Poké Balls | Boosted in caves/at night | |
| 12 | Quick Ball | Poké Balls | High rate if thrown turn 1 | |
| 25 | Park Ball | Poké Balls | Standard rate, Pal Park/PokéWalker only | |
| 27 | Cherish Ball | Poké Balls | Standard rate, event-exclusive | |
| 60 | Old Gateau | Regional Specialties | Cures all status | |
| 139 | Balm Mushroom | Treasures | Pure sell item, historical Wi-Fi event unlock | |
| 153 | Honey | Treasures | Applied to a tree to attract wild Pokémon | |
| 154 | Rare Bone | Treasures | Pure sell item | |
| 155 | Odd Keystone | Treasures | Delivered to an NPC (Spiritomb sidequest) | |
| 170 | Armor Fossil | Fossils | Revives into Shieldon | |
| 171 | Skull Fossil | Fossils | Revives into Cranidos | |
| 180 | Growth Mulch | Mulch | Speeds berry growth | |
| 181 | Damp Mulch | Mulch | Reduces berry withering | |
| 182 | Stable Mulch | Mulch | Reduces yield variance | |
| 183 | Gooey Mulch | Mulch | Boosts yield, drives away wild Pokémon | |
| 218 | Shiny Stone | Evolution Items | Evolves certain Pokémon | |
| 219 | Dusk Stone | Evolution Items | Evolves certain Pokémon | |
| 220 | Dawn Stone | Evolution Items | Evolves certain Pokémon (gender-specific) | |
| 230 | Electirizer | Evolution Items | Held-until-trade trigger (Electabuzz→Electivire) | |
| 231 | Magmarizer | Evolution Items | Held-until-trade trigger (Magmar→Magmortar) | |
| 232 | Dubious Disc | Evolution Items | Held-until-trade trigger (Porygon2→Porygon-Z) | |
| 233 | Reaper Cloth | Evolution Items | Held-until-trade trigger (Dusclops→Dusknoir) | |
| 237 | Oval Stone | Evolution Items | Held-item level-up trigger (Happiny→Chansey, daytime) | |
| 397 | Quick Powder | Species-specific held item | *(see the found-gap note above — likely belongs in the M18 held-item ledger, not here)* | |
| 690 | Oval Charm | Charms | Raises egg-in-daycare odds (non-battle) | |
| 694 | Rotom Catalog *(placed here approximately; see note)* | Form-changing Key Items | Menu form-swap for Rotom's overworld/party form | |
| 695 | Gracidea | Form-changing Key Items | Triggers Shaymin Land↔Sky (story/menu, no in-battle trigger) | |
| 714 | VS Seeker | Misc. Key Items | Overworld trainer-rematch trigger | |
| 721 | Poké Radar | Misc. Key Items | Overworld chain-encounter tool | |

### Generation V

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 22 | Dream Ball | Poké Balls | Boosted vs. sleeping Pokémon | |
| 61 | Casteliacone | Regional Specialties | Cures all status | |
| 145 | Comet Shard | Treasures | Pure sell item, very high value | |
| 157 | Relic Copper | Treasures | Pure sell item (Desert Ruins theming) | |
| 158 | Relic Silver | Treasures | Pure sell item | |
| 159 | Relic Gold | Treasures | Pure sell item | |
| 160 | Relic Vase | Treasures | Pure sell item | |
| 161 | Relic Band | Treasures | Pure sell item | |
| 162 | Relic Statue | Treasures | Pure sell item | |
| 163 | Relic Crown | Treasures | Pure sell item | |
| 172 | Cover Fossil | Fossils | Revives into Tirtouga | |
| 173 | Plume Fossil | Fossils | Revives into Archen | |
| 234 | Prism Scale | Evolution Items | Held-until-trade trigger (Feebas→Milotic) | |
| 691 | Shiny Charm | Charms | Raises shiny odds (non-battle) | |
| 696 | Reveal Glass | Form-changing Key Items | Triggers Tornadus/Thundurus/Landorus Incarnate↔Therian (story/menu) | |
| 697 | DNA Splicers | Form-changing Key Items | Kyurem fusion/un-fusion with Reshiram/Zekrom (story/menu) | |

### Generation VI

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 62 | Lumiose Galette | Regional Specialties | Cures all status | |
| 63 | Shalour Sable | Regional Specialties | Cures all status | |
| 79 | Ability Capsule | Ability Modifiers | Swaps between a Pokémon's two normal abilities (menu-only) | |
| 136 | Big Nugget | Treasures | Pure sell item | |
| 142 | Pearl String | Treasures | Pure sell item | |
| 164 | Strange Souvenir | Treasures | Pure sell item (event/quest flavor) | |
| 174 | Jaw Fossil | Fossils | Revives into Tyrunt | |
| 175 | Sail Fossil | Fossils | Revives into Amaura | |
| 235 | Whipped Dream | Evolution Items | Held-item level-up trigger (Swirlix→Slurpuff) | |
| 236 | Sachet | Evolution Items | Held-item level-up trigger (Spritzee→Aromatisse) | |
| 698 | Zygarde Cube | Form-changing Key Items | Zygarde Cell/Core collection + forme assembly (menu) *(placed here approximately)* | |
| 699 | Prison Bottle | Form-changing Key Items | Triggers Hoopa Confined↔Unbound (story/menu) | |
| 703 | Mega Ring | Battle Mechanic Key Items | **Enables Mega Evolution** — gate item | **Mega-Evolution-exclusive** |
| 723 | Soot Sack | Misc. Key Items | Overworld ash-collection tool | |

### Generation VII

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 26 | Beast Ball | Poké Balls | Boosted vs. Ultra Beasts, poor rate otherwise | |
| 64 | Big Malasada | Regional Specialties | Cures all status | |
| 133 | Bottle Cap | Treasures | Hyper Training currency (raises one IV to 31) | |
| 134 | Gold Bottle Cap | Treasures | Same, maxes all 6 IVs | |
| 215 | Ice Stone | Evolution Items | Evolves certain Pokémon (e.g. Alolan Vulpix) | |
| 246 | Red Nectar | Nectars | Changes Oricorio's form/type (party-menu, consumed) | |
| 247 | Yellow Nectar | Nectars | Same, different form | |
| 248 | Pink Nectar | Nectars | Same, different form | |
| 249 | Purple Nectar | Nectars | Same, different form | |
| 692 | Catching Charm | Charms | Raises critical-capture odds | |
| 693 | Exp. Charm | Charms | Boosts EXP-gain multiplier (post-battle reward calc, not in-battle) | |
| 700 | N-Solarizer | Form-changing Key Items | Necrozma+Solgaleo fusion trigger (story/menu) | |
| 701 | N-Lunarizer | Form-changing Key Items | Necrozma+Lunala fusion trigger (story/menu) | |
| 704 | Z-Power Ring | Battle Mechanic Key Items | **Enables Z-Move usage** — gate item | **Z-Move-exclusive** |

### Generation VIII

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 56 | Max Honey | Medicine | Fully revives (Max Revive equivalent) | |
| 73 | Health Feather | EV Feathers | Raises HP EVs by a small fixed amount | |
| 74 | Muscle Feather | EV Feathers | Raises Attack EVs | |
| 75 | Resist Feather | EV Feathers | Raises Defense EVs | |
| 76 | Genius Feather | EV Feathers | Raises Sp.Atk EVs | |
| 77 | Clever Feather | EV Feathers | Raises Sp.Def EVs | |
| 78 | Swift Feather | EV Feathers | Raises Speed EVs | |
| 80 | Ability Patch | Ability Modifiers | Changes a Pokémon's ability to its hidden ability (menu-only) | |
| 81 | Lonely Mint | Mints | Sets stat-growth pattern (Lonely) | |
| 82 | Adamant Mint | Mints | Sets stat-growth pattern (Adamant) | |
| 83 | Naughty Mint | Mints | Sets stat-growth pattern (Naughty) | |
| 84 | Brave Mint | Mints | Sets stat-growth pattern (Brave) | |
| 85 | Bold Mint | Mints | Sets stat-growth pattern (Bold) | |
| 86 | Impish Mint | Mints | Sets stat-growth pattern (Impish) | |
| 87 | Lax Mint | Mints | Sets stat-growth pattern (Lax) | |
| 88 | Relaxed Mint | Mints | Sets stat-growth pattern (Relaxed) | |
| 89 | Modest Mint | Mints | Sets stat-growth pattern (Modest) | |
| 90 | Mild Mint | Mints | Sets stat-growth pattern (Mild) | |
| 91 | Rash Mint | Mints | Sets stat-growth pattern (Rash) | |
| 92 | Quiet Mint | Mints | Sets stat-growth pattern (Quiet) | |
| 93 | Calm Mint | Mints | Sets stat-growth pattern (Calm) | |
| 94 | Gentle Mint | Mints | Sets stat-growth pattern (Gentle) | |
| 95 | Careful Mint | Mints | Sets stat-growth pattern (Careful) | |
| 96 | Sassy Mint | Mints | Sets stat-growth pattern (Sassy) | |
| 97 | Timid Mint | Mints | Sets stat-growth pattern (Timid) | |
| 98 | Hasty Mint | Mints | Sets stat-growth pattern (Hasty) | |
| 99 | Jolly Mint | Mints | Sets stat-growth pattern (Jolly) | |
| 100 | Naive Mint | Mints | Sets stat-growth pattern (Naive) | |
| 101 | Serious Mint | Mints | Sets stat-growth pattern (neutral, Serious) | |
| 103 | Exp. Candy XS | Candy | Grants a very small fixed Exp. amount | |
| 104 | Exp. Candy S | Candy | Grants a small fixed Exp. amount | |
| 105 | Exp. Candy M | Candy | Grants a moderate fixed Exp. amount | |
| 106 | Exp. Candy L | Candy | Grants a large fixed Exp. amount | |
| 107 | Exp. Candy XL | Candy | Grants a very large fixed Exp. amount | |
| 108 | Dynamax Candy | Candy | Raises a Pokémon's Dynamax Level by 1 | **Dynamax-exclusive** |
| 117 | Lure | Encounter Modifiers | Increases wild encounter rate, 100 steps *(uncertain generation — flagged, see note)* | |
| 118 | Super Lure | Encounter Modifiers | Same, 200 steps *(uncertain)* | |
| 119 | Max Lure | Encounter Modifiers | Same, 250 steps *(uncertain)* | |
| 131 | Poké Toy | Escape Items | Guarantees escape from a wild battle | |
| 132 | Max Mushrooms | Escape Items *(misfiled in source, no header of its own)* | Raises every stat +1 stage during one battle | **Dynamax-adjacent** (Max Raid/Dynamax-Adventure era item) |
| 156 | Pretty Feather | Treasures | Pure sell/quest item, cosmetic | |
| 176 | Fossilized Bird | Fossils | Combines with another piece → Dracozolt/Arctozolt | |
| 177 | Fossilized Fish | Fossils | Combines with another piece → Dracovish/Arctovish | |
| 178 | Fossilized Drake | Fossils | Combines with another piece → Dracozolt/Dracovish | |
| 179 | Fossilized Dino | Fossils | Combines with another piece → Arctozolt/Arctovish | |
| 184 | Rich Mulch | Mulch | Boosts berry yield | |
| 185 | Surprise Mulch | Mulch | Random effect | |
| 186 | Boost Mulch | Mulch | Boosts growth speed | |
| 187 | Amaze Mulch | Mulch | Guarantees a rare outcome | |
| 195 | Wishing Piece | Apricorns (misc. treasure) | Summons Max Raid dens | **Dynamax-adjacent** |
| 196 | Galarica Twig | Apricorns (misc. treasure) | Crafting ingredient | |
| 197 | Armorite Ore | Apricorns (misc. treasure) | DLC move-tutor/customization currency | |
| 198 | Dynite Ore | Apricorns (misc. treasure) | DLC move-tutor/legendary-NPC currency | |
| 221 | Sweet Apple | Evolution Items | Party-menu use (Applin→Appletun) | |
| 222 | Tart Apple | Evolution Items | Party-menu use (Applin→Flapple) | |
| 223 | Cracked Pot | Evolution Items | Party-menu use (Sinistea/Polteageist authenticity check) | |
| 224 | Chipped Pot | Evolution Items | Same slot, alternate variant | |
| 225 | Galarica Cuff | Evolution Items | Party-menu use (Galarian Slowpoke→Slowbro) | |
| 226 | Galarica Wreath | Evolution Items | Party-menu use (Galarian Slowpoke→Slowking) | |
| 238 | Strawberry Sweet | Evolution Items | Sets Milcery's future Alcremie flavor (held-and-level-up) | |
| 239 | Love Sweet | Evolution Items | Same, different flavor | |
| 240 | Berry Sweet | Evolution Items | Same, different flavor | |
| 241 | Clover Sweet | Evolution Items | Same, different flavor | |
| 242 | Flower Sweet | Evolution Items | Same, different flavor | |
| 243 | Star Sweet | Evolution Items | Same, different flavor | |
| 244 | Ribbon Sweet | Evolution Items | Same, different flavor | |
| 702 | Reins of Unity | Form-changing Key Items | Calyrex+Glastrier/Spectrier fusion trigger (story/menu) | |
| 705 | Dynamax Band | Battle Mechanic Key Items | **Enables Dynamax/Gigantamax** — gate item | **Dynamax-exclusive** |
| 716 | Berry Pouch | Misc. Key Items | Menu storage UI | |

### Generation IX (and post-Gen-IX spinoffs: Legends Arceus, Legends Z-A)

| ID | Name | Category | Mechanic | Exclusion flag |
|---|---|---|---|---|
| 763 | Auspicious Armor | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 765 | Big Bamboo Shoot | Gen IX evolution-trigger items | Sellable, not actually an evolution item despite the block | |
| 766 | Gimmighoul Coin | Gen IX evolution-trigger items | Evolution-count currency for Gimmighoul→Gholdengo | |
| 767 | Leader's Crest | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 768 | Malicious Armor | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 770 | Scroll of Darkness | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 771 | Scroll of Waters | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 773 | Tiny Bamboo Shoot | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 795 | Black Augurite *(Legends Arceus)* | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 796 | Linking Cord *(Legends Arceus)* | Gen IX evolution-trigger items | Replaces trade-evolution requirement | |
| 797 | Peat Block *(Legends Arceus)* | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 800 | Syrupy Apple | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 801 | Unremarkable Teacup | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 802 | Masterpiece Teacup | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 813 | Glimmering Charm | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 814 | Metal Alloy | Gen IX evolution-trigger items | Menu-use evolution trigger | |
| 806 | Health Mochi *(Legends Arceus)* | Legends consumables | EV-training consumable, party-menu only | |
| 807 | Muscle Mochi *(Legends Arceus)* | Legends consumables | Same, different EV | |
| 808 | Resist Mochi *(Legends Arceus)* | Legends consumables | Same | |
| 809 | Genius Mochi *(Legends Arceus)* | Legends consumables | Same | |
| 810 | Clever Mochi *(Legends Arceus)* | Legends consumables | Same | |
| 811 | Swift Mochi *(Legends Arceus)* | Legends consumables | Same | |
| 812 | Fresh-Start Mochi *(Legends Arceus)* | Legends consumables | Resets a Pokémon's EVs, party-menu only | |
| 816 | Jubilife Muffin *(Legends Arceus)* | Legends consumables | Battle-usable, cures status (Full-Heal-equivalent) | |
| 817 | Remedy *(Legends Arceus)* | Legends consumables | Battle-usable, tiered status cure | |
| 818 | Fine Remedy *(Legends Arceus)* | Legends consumables | Same, stronger tier | |
| 819 | Superb Remedy *(Legends Arceus)* | Legends consumables | Same, strongest tier | |
| 820 | Aux Evasion *(Legends Z-A)* | Legends consumables | In-battle stat-stage booster (X-Item-shaped) | |
| 821 | Aux Guard *(Legends Z-A)* | Legends consumables | Same | |
| 822 | Aux Power *(Legends Z-A)* | Legends consumables | Same | |
| 823 | Aux Powerguard *(Legends Z-A)* | Legends consumables | Same | |
| 824 | Choice Dumpling *(Legends Z-A)* | Legends consumables | Data appears unfinished/stubbed in this ROM hack (placeholder description) | |
| 825 | Swap Snack *(Legends Z-A)* | Legends consumables | Same, unfinished | |
| 826 | Twice-Spiced Radish *(Legends Z-A)* | Legends consumables | Same, unfinished | |
| 827 | Pokéshi Doll | Misc. bag items | Sellable collectible, no mechanic | |
| 828 | Strange Ball *(Legends Arceus)* | Poké Balls (variant) | Capture-mechanic item, not reviewed as part of any Poké Ball milestone yet | |

**A scope flag worth repeating from `docs/m18_item_ledger.md`'s own corrections
section:** several of the above (Legends Arceus- and Legends Z-A-sourced items) are
from post-Gen-IX spinoff titles, not mainline numbered generations. `CLAUDE.md` names
only `pokeemerald_expansion` as this project's reference source, with no mention of
either spinoff. This is the exact same "is this even in our intended scope" question
the M18 ledger already flagged for the Legends Z-A Mega Stones — worth resolving once,
for both documents, rather than separately.

---

## Section B — Architectural dependencies this future work will actually need

This is the important section for planning purposes: unlike M18's held items (which
mostly slot into `ItemManager`'s existing hold-effect dispatch pattern), almost none
of this recon's 498 items can be added as simple data entries. They need real new
systems this project doesn't have at all yet.

### B.1 — No bag/inventory data structure exists

Confirmed via direct grep: zero occurrences of `bag`, `inventory`, or any related
concept anywhere in `scripts/battle/core/item_manager.gd`, `battle_manager.gd`, or the
trainer-AI scripts. There is no data structure anywhere in this project representing
"what items does this trainer/player own, and how many of each." `ItemManager`'s
entire existing surface area is built around a single held-item slot per
`BattlePokemon` (`effective_held_item`) — a fundamentally different shape from a bag
inventory (many items, quantities, ownership independent of any one Pokémon).

### B.2 — No item-use-outside-of-battle framework exists

Using a Potion from the bag menu, applying an Evolution Stone to a party Pokémon,
teaching a TM, riding the Bicycle — all of this depends on overworld/menu/UI systems
that are explicitly M25's own territory per the project's build order (this project's
"Build order" sections in `CLAUDE.md` only ever specified a battle engine through
M14c; overworld/menu systems were never separately milestoned before M25 was named as
the future item-UI pass). This isn't something that could be meaningfully built in
isolation earlier — it depends on whatever party/overworld/menu architecture M25
actually establishes, which doesn't exist yet in any form.

### B.3 — No item-use-DURING-battle framework exists

This is the more surprising gap, since it affects even the subset of these 498 items
that ARE meaningfully battle-relevant (X Items, Guard Spec., Poké Balls thrown at a
wild Pokémon, using a Potion mid-battle). Confirmed directly: `BattleManager`'s action
queue only ever stores two action shapes —
```gdscript
{"type": "switch", "slot": int}
{"type": "move", "index": int}  # or + "target": int in doubles
```
(`battle_manager.gd:149-150`, confirmed via grep for every `"type":` literal in the
file). **There is no third action type for "use a bag item this turn."** Every
mechanic this engine has ever built is either move-based (a chosen action that
consumes the turn) or ability/held-item-passive (evaluated automatically, never
player-selected). "Spend your turn using a Potion instead of attacking" is a
genuinely new action-selection shape this project's core turn loop has never needed
before — this is arguably the single largest architectural lift in this entire
document, bigger than any individual item, since it changes the shape of
`_phase_move_selection`'s action queue itself, not just `ItemManager`.

### B.4 — Poké Ball catch-mechanic math is its own dedicated sub-system

Confirmed: `PokemonSpecies.catch_rate` (`scripts/data/pokemon_species.gd:25`,
`@export var catch_rate: int = 45`) already exists as a **dormant data field**,
populated by the data pipeline but never read anywhere in battle logic — the same
"dormant field carried from the schema, never wired" pattern this project has hit
repeatedly with `MoveData` flags (`[M17n-1]`, `[M17n-5]`). No catch-rate formula, ball
modifier table, or status/HP-based catch-rate multiplier exists anywhere. Given the
real catch formula (`CalculateWildCatch`-style: catch rate × ball modifier × HP-based
multiplier × status bonus, all combined multiplicatively with a shake-check RNG loop)
is a meaningfully large, self-contained piece of math with its own edge cases
(Master Ball's unconditional catch, Safari/Sport/Park Ball's restricted-context-only
rates, the various conditional balls like Dive/Net/Dusk/Moon/Love/Fast/Heavy/
Level/Lure/Repeat/Timer Ball each reading different battle-state signals), this is
correctly flagged as **its own dedicated recon/prompt later**, not something to fold
into a general "bag items" implementation pass. It also depends on this project
having ANY wild-encounter concept at all, which — per this engine's `CLAUDE.md`
framing as a from-scratch battle-engine clone, not a full game — may not even be in
scope; worth Rob confirming whether wild encounters (as opposed to only trainer
battles) are ever intended here before this sub-system gets its own recon.

### B.5 — TM/HM is already fully solved as a data concept; exclude it from any future item-focused milestone

Confirmed directly: `data/tmhm_map.json` exists and is loaded by
`PokemonRegistry._tmhm_map` (`scripts/data/pokemon_registry.gd:14,75-79`), queried via
`get_tm_data(tm_number)` (line 161, returning which Pokémon/moves a given TM number is
associated with). This is a complete, working Pokémon↔learnable-move mapping built
during M15's data pipeline — **"TM/HM as an item" is not a meaningful separate concept
in this project at all.** The 108 TM/HM item IDs (582–689) have zero in-battle
behavior in source either way (pure "teach this move" bag items) — there is nothing
for a future item milestone to build here. Recommend TM/HM be explicitly dropped from
any future non-held-item scope entirely, not carried forward as "108 items still
needing review."

---

## Section C — Summary counts

| Bucket | Count | Notes |
|---|---|---|
| **Total non-held items in this recon** | **498** | Verified programmatically: 873 real item IDs in source minus the 375 IDs already in `docs/m18_item_ledger.md` |
| Already implemented | **0** | Confirmed — zero bag-item scaffolding exists anywhere in `item_manager.gd`/`battle_manager.gd` |
| Mega/Z-Move/Dynamax-exclusive (gate items + directly adjacent) | **6** | Mega Ring (703), Z-Power Ring (704), Dynamax Band (705), Dynamax Candy (108), Max Mushrooms (132), Wishing Piece (195) — flagged, not pre-excluded, per standing precedent |
| Already fully solved elsewhere, recommend dropping entirely | **108** | TM/HM (582–689) — see Section B.5; this project's `tmhm_map.json` already handles the underlying concept, nothing left to build |
| Needs its own dedicated catch-mechanic sub-effort (not simple data entry) | **28** | The 27 Poké Balls (1–27) + Strange Ball (828) — see Section B.4 |
| Needs new item-use-DURING-battle infrastructure before it can function at all | **~50** | Medicine usable mid-battle (Potions/status-cures/PP-restores, ~26 items), X Items (8), Escape Items (4), Medicinal Flutes (3), Legends' battle-usable Remedies/Muffin/Aux items (~9) — see Section B.3; none of these can be added until the action-queue itself grows a third action type |
| Needs new item-use-OUTSIDE-of-battle / bag-inventory infrastructure before it can function at all | **~300** | Everything else with any mechanical function at all once picked up — Vitamins, Mints, Candy, Evolution Items, Treasures/Fossils (revival flow), Key Items, Berries (Pokéblock), etc. — see Sections B.1/B.2 |
| Purely cosmetic/no mechanic to ever build (sell items, sprites, flavor text) | **~14** | E.g. Nuggets/Pearls/Shards/Star Piece-style pure-sell Treasures, Mail (no `holdEffect`), Pokéshi Doll — these will likely never need "implementation" beyond a data entry with a price field, whenever a bag/economy system exists |
| **3 items found during this recon's diff that appear to be M18 held-item ledger oversights, not bag items** | **3** | Quick Powder (397), Macho Brace (418), Focus Band (469) — see the Methodology section above; recommend fixing the M18 ledger separately, not folding these into M25 scope |

**Bottom line:** this future milestone is architecturally much larger than M18's held
items, which mostly reused an existing dispatch pattern. Non-held items need at
least three genuinely new systems before most of them can be implemented at all: a
bag/inventory data structure, an outside-of-battle item-use framework (both
explicitly M25/UI territory), and a new in-battle action type for "use an item this
turn" (which is core-engine work, not UI work, and could in principle be built earlier
if Rob ever wants to decouple it from the rest of M25). Poké Ball catch-math is
large and self-contained enough to deserve its own separate recon rather than
folding into a general bag-items prompt. TM/HM needs nothing further — drop it from
scope entirely. And three items surfaced here belong in `docs/m18_item_ledger.md`,
not in this document, once Rob is ready to correct that file.
