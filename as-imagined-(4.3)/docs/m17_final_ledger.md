# M17 Final Ability Ledger — the definitive, closed-book reconciliation

**Status: CLOSED.** Every one of the 318 canonical ability IDs (`include/constants/abilities.h`,
`ABILITY_NONE`=0 excluded, `ABILITIES_COUNT`=319 confirms 1-318 is the full real range) is
accounted for in exactly one of three buckets below, verified programmatically with zero
overlaps and zero gaps:

- **226 IMPLEMENTED** — has a real `const ABILITY_*` in `scripts/battle/core/ability_manager.gd`
  with working battle logic, cross-checked against a non-blank `data/abilities/ability_NNNN.tres`
  file for every single one (verified 2026-07-06, zero discrepancies).
- **91 EXCLUDED** — a permanent, deliberate scope decision, with a citation to the specific
  recon section, decisions.md entry, or direct Rob instruction that excluded it.
- **1 OPEN** — Stench (1). No blocker, simply fell out of the sub-tier planning process (see
  its own row below for the full explanation). This is the ONLY ability left requiring either
  implementation or an explicit exclusion decision before M17 can be called done.

**226 + 91 + 1 = 318.** This was verified programmatically (not by hand-tally) on 2026-07-06,
during a dedicated reconciliation session that resolved a previously-flagged ~12-ability
accounting gap left open by `[M17n-11]`'s own closing summary. That gap turned out to be
larger than estimated (91 excluded, not ~60 as `[M17n-11]` guessed) because `[M17n-11]`'s own
pass only checked the ORIGINAL 61-ID exclusion set recorded in `docs/m17n_recon.md`'s
pre-M17n baseline, and missed:
  1. 24 additional exclusions that decisions.md itself already recorded across
     `[M17n-4]` through `[M17n-9]`'s own Step-0 "accumulated exclusion set" cross-references
     (Ruin quartet, Water Bubble/Supreme Overlord/Plus/Minus, RKS System, Rivalry, Heavy/Light
     Metal, the Wind trio, Protosynthesis, Embody Aspect ×4, Dancer, Wimp Out/Emergency Exit,
     Curious Medicine) — these were sitting in decisions.md the whole time but weren't
     cross-referenced during `[M17n-11]`'s own reconciliation pass.
  2. 3 abilities from `[M17n-1]`'s own Group 1 (Run Away, Pickup, Ball Fetch) that were
     confirmed "genuinely out-of-battle-engine scope" and deliberately given NO constant or
     `.tres` entry at all — these were always excluded in spirit but never actually added to
     any running exclusion tally until this session.
  3. 5 abilities (Skill Link, Good As Gold, Illusion, Perish Body, Suction Cups) that this
     session's Rob confirmed as excluded directly, three of which (Good As Gold, Illusion,
     Suction Cups) `[M17n-11]`'s own summary had listed as merely "unassigned" — this
     session's own memory search independently found NO prior record of Illusion's exclusion
     specifically (flagged here rather than silently accepted; the other four had at least
     partial textual support already in decisions.md, detailed in each row's citation below).

**Do not re-derive this table from scratch in a future session.** If a new ability gets
implemented or a new exclusion decision is made, update this file's specific row(s) and its
running totals — do not recount all 318 by hand again. See "Maintenance" at the bottom.

## The complete 318-ID table

| ID | Name | Status | Note |
|---|---|---|---|
| 1 | Stench | OPEN | no blocker at all — a simple on-hit flinch-chance secondary effect, same shape as this project's existing contact/hit-triggered abilities (Static/Flame Body). Genuinely fell through the cracks: present in m17_recon.md's original Bucket F classification table, but dropped from docs/m17n_recon.md's Group 1-8 prose entirely (Group 4's own header claimed "27 abilities" while only 26 were ever named in its body text — this is the missing 27th). Never assigned to any M17n sub-tier, never excluded by any recorded decision. |
| 2 | Drizzle | IMPLEMENTED |  |
| 3 | Speed Boost | IMPLEMENTED |  |
| 4 | Battle Armor | IMPLEMENTED |  |
| 5 | Sturdy | IMPLEMENTED |  |
| 6 | Damp | IMPLEMENTED |  |
| 7 | Limber | IMPLEMENTED |  |
| 8 | Sand Veil | IMPLEMENTED |  |
| 9 | Static | IMPLEMENTED |  |
| 10 | Volt Absorb | IMPLEMENTED |  |
| 11 | Water Absorb | IMPLEMENTED |  |
| 12 | Oblivious | IMPLEMENTED |  |
| 13 | Cloud Nine | IMPLEMENTED |  |
| 14 | Compound Eyes | IMPLEMENTED |  |
| 15 | Insomnia | IMPLEMENTED |  |
| 16 | Color Change | IMPLEMENTED |  |
| 17 | Immunity | IMPLEMENTED |  |
| 18 | Flash Fire | IMPLEMENTED |  |
| 19 | Shield Dust | IMPLEMENTED |  |
| 20 | Own Tempo | IMPLEMENTED |  |
| 21 | Suction Cups | EXCLUDED | [M17n-8] decisions.md — deferred to a later Group 8 sub-tier that never picked it up; excluded per Rob's direct instruction 2026-07-06 |
| 22 | Intimidate | IMPLEMENTED |  |
| 23 | Shadow Tag | IMPLEMENTED |  |
| 24 | Rough Skin | IMPLEMENTED |  |
| 25 | Wonder Guard | IMPLEMENTED |  |
| 26 | Levitate | IMPLEMENTED |  |
| 27 | Effect Spore | IMPLEMENTED |  |
| 28 | Synchronize | IMPLEMENTED |  |
| 29 | Clear Body | IMPLEMENTED |  |
| 30 | Natural Cure | IMPLEMENTED |  |
| 31 | Lightning Rod | IMPLEMENTED |  |
| 32 | Serene Grace | IMPLEMENTED |  |
| 33 | Swift Swim | IMPLEMENTED |  |
| 34 | Chlorophyll | IMPLEMENTED |  |
| 35 | Illuminate | IMPLEMENTED |  |
| 36 | Trace | IMPLEMENTED |  |
| 37 | Huge Power | IMPLEMENTED |  |
| 38 | Poison Point | IMPLEMENTED |  |
| 39 | Inner Focus | IMPLEMENTED |  |
| 40 | Magma Armor | IMPLEMENTED |  |
| 41 | Water Veil | IMPLEMENTED |  |
| 42 | Magnet Pull | IMPLEMENTED |  |
| 43 | Soundproof | IMPLEMENTED |  |
| 44 | Rain Dish | IMPLEMENTED |  |
| 45 | Sand Stream | IMPLEMENTED |  |
| 46 | Pressure | IMPLEMENTED |  |
| 47 | Thick Fat | IMPLEMENTED |  |
| 48 | Early Bird | IMPLEMENTED |  |
| 49 | Flame Body | IMPLEMENTED |  |
| 50 | Run Away | EXCLUDED | [M17n-1] decisions.md — confirmed genuinely out-of-battle-engine scope (flee is simulator-layer, not engine-layer), given no constant/.tres entry at all |
| 51 | Keen Eye | IMPLEMENTED |  |
| 52 | Hyper Cutter | IMPLEMENTED |  |
| 53 | Pickup | EXCLUDED | [M17n-1] decisions.md — confirmed genuinely out-of-battle-engine scope (post-battle item pickup is simulator-layer) |
| 54 | Truant | IMPLEMENTED |  |
| 55 | Hustle | IMPLEMENTED |  |
| 56 | Cute Charm | IMPLEMENTED |  |
| 57 | Plus | EXCLUDED | [M17n-5] task prompt exclusion (Plus/Minus doubles pair) |
| 58 | Minus | EXCLUDED | [M17n-5] task prompt exclusion (Plus/Minus doubles pair) |
| 59 | Forecast | IMPLEMENTED |  |
| 60 | Sticky Hold | IMPLEMENTED |  |
| 61 | Shed Skin | IMPLEMENTED |  |
| 62 | Guts | IMPLEMENTED |  |
| 63 | Marvel Scale | IMPLEMENTED |  |
| 64 | Liquid Ooze | IMPLEMENTED |  |
| 65 | Overgrow | IMPLEMENTED |  |
| 66 | Blaze | IMPLEMENTED |  |
| 67 | Torrent | IMPLEMENTED |  |
| 68 | Swarm | IMPLEMENTED |  |
| 69 | Rock Head | IMPLEMENTED |  |
| 70 | Drought | IMPLEMENTED |  |
| 71 | Arena Trap | IMPLEMENTED |  |
| 72 | Vital Spirit | IMPLEMENTED |  |
| 73 | White Smoke | IMPLEMENTED |  |
| 74 | Pure Power | IMPLEMENTED |  |
| 75 | Shell Armor | IMPLEMENTED |  |
| 76 | Air Lock | IMPLEMENTED |  |
| 77 | Tangled Feet | IMPLEMENTED |  |
| 78 | Motor Drive | IMPLEMENTED |  |
| 79 | Rivalry | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — blocked on missing per-mon gender field |
| 80 | Steadfast | IMPLEMENTED |  |
| 81 | Snow Cloak | IMPLEMENTED |  |
| 82 | Gluttony | IMPLEMENTED |  |
| 83 | Anger Point | IMPLEMENTED |  |
| 84 | Unburden | IMPLEMENTED |  |
| 85 | Heatproof | IMPLEMENTED |  |
| 86 | Simple | IMPLEMENTED |  |
| 87 | Dry Skin | IMPLEMENTED |  |
| 88 | Download | IMPLEMENTED |  |
| 89 | Iron Fist | IMPLEMENTED |  |
| 90 | Poison Heal | IMPLEMENTED |  |
| 91 | Adaptability | IMPLEMENTED |  |
| 92 | Skill Link | EXCLUDED | [M17n-5] decisions.md — deferred, no multi-hit mechanic exists in this codebase; excluded per Rob's direct instruction 2026-07-06 |
| 93 | Hydration | IMPLEMENTED |  |
| 94 | Solar Power | IMPLEMENTED |  |
| 95 | Quick Feet | IMPLEMENTED |  |
| 96 | Normalize | IMPLEMENTED |  |
| 97 | Sniper | IMPLEMENTED |  |
| 98 | Magic Guard | IMPLEMENTED |  |
| 99 | No Guard | IMPLEMENTED |  |
| 100 | Stall | IMPLEMENTED |  |
| 101 | Technician | IMPLEMENTED |  |
| 102 | Leaf Guard | IMPLEMENTED |  |
| 103 | Klutz | IMPLEMENTED |  |
| 104 | Mold Breaker | IMPLEMENTED |  |
| 105 | Super Luck | IMPLEMENTED |  |
| 106 | Aftermath | IMPLEMENTED |  |
| 107 | Anticipation | IMPLEMENTED |  |
| 108 | Forewarn | IMPLEMENTED |  |
| 109 | Unaware | IMPLEMENTED |  |
| 110 | Tinted Lens | IMPLEMENTED |  |
| 111 | Filter | IMPLEMENTED |  |
| 112 | Slow Start | IMPLEMENTED |  |
| 113 | Scrappy | IMPLEMENTED |  |
| 114 | Storm Drain | IMPLEMENTED |  |
| 115 | Ice Body | IMPLEMENTED |  |
| 116 | Solid Rock | IMPLEMENTED |  |
| 117 | Snow Warning | IMPLEMENTED |  |
| 118 | Honey Gather | IMPLEMENTED |  |
| 119 | Frisk | IMPLEMENTED |  |
| 120 | Reckless | IMPLEMENTED |  |
| 121 | Multitype | IMPLEMENTED |  |
| 122 | Flower Gift | IMPLEMENTED |  |
| 123 | Bad Dreams | EXCLUDED | Pre-decided before M17a (Bad Dreams — Nightmare-adjacent, out of scope) |
| 124 | Pickpocket | IMPLEMENTED |  |
| 125 | Sheer Force | IMPLEMENTED |  |
| 126 | Contrary | IMPLEMENTED |  |
| 127 | Unnerve | IMPLEMENTED |  |
| 128 | Defiant | IMPLEMENTED |  |
| 129 | Defeatist | IMPLEMENTED |  |
| 130 | Cursed Body | IMPLEMENTED |  |
| 131 | Healer | IMPLEMENTED |  |
| 132 | Friend Guard | IMPLEMENTED |  |
| 133 | Weak Armor | IMPLEMENTED |  |
| 134 | Heavy Metal | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — no weight-based move exists |
| 135 | Light Metal | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — no weight-based move exists |
| 136 | Multiscale | IMPLEMENTED |  |
| 137 | Toxic Boost | IMPLEMENTED |  |
| 138 | Flare Boost | IMPLEMENTED |  |
| 139 | Harvest | IMPLEMENTED |  |
| 140 | Telepathy | IMPLEMENTED |  |
| 141 | Moody | IMPLEMENTED |  |
| 142 | Overcoat | IMPLEMENTED |  |
| 143 | Poison Touch | IMPLEMENTED |  |
| 144 | Regenerator | IMPLEMENTED |  |
| 145 | Big Pecks | IMPLEMENTED |  |
| 146 | Sand Rush | IMPLEMENTED |  |
| 147 | Wonder Skin | IMPLEMENTED |  |
| 148 | Analytic | IMPLEMENTED |  |
| 149 | Illusion | EXCLUDED | Excluded per Rob's direct instruction 2026-07-06 (no memory/decisions.md record found independently; recon's own source read already confirmed zero mechanical battle-calc effect in this text/state-driven engine) |
| 150 | Imposter | EXCLUDED | Pre-decided before M17a (Imposter/Transform not modeled) |
| 151 | Infiltrator | IMPLEMENTED |  |
| 152 | Mummy | IMPLEMENTED |  |
| 153 | Moxie | IMPLEMENTED |  |
| 154 | Justified | IMPLEMENTED |  |
| 155 | Rattled | IMPLEMENTED |  |
| 156 | Magic Bounce | IMPLEMENTED |  |
| 157 | Sap Sipper | IMPLEMENTED |  |
| 158 | Prankster | IMPLEMENTED |  |
| 159 | Sand Force | IMPLEMENTED |  |
| 160 | Iron Barbs | IMPLEMENTED |  |
| 161 | Zen Mode | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Darmanitan-Zen) |
| 162 | Victory Star | EXCLUDED | m17_recon.md 13.1 — mythical-exclusive (Victini) |
| 163 | Turboblaze | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Reshiram/Kyurem-White) |
| 164 | Teravolt | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Zekrom/Kyurem-Black) |
| 165 | Aroma Veil | IMPLEMENTED |  |
| 166 | Flower Veil | IMPLEMENTED |  |
| 167 | Cheek Pouch | IMPLEMENTED |  |
| 168 | Protean | IMPLEMENTED |  |
| 169 | Fur Coat | IMPLEMENTED |  |
| 170 | Magician | IMPLEMENTED |  |
| 171 | Bulletproof | IMPLEMENTED |  |
| 172 | Competitive | IMPLEMENTED |  |
| 173 | Strong Jaw | IMPLEMENTED |  |
| 174 | Refrigerate | IMPLEMENTED |  |
| 175 | Sweet Veil | IMPLEMENTED |  |
| 176 | Stance Change | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Aegislash-Blade/Shield) |
| 177 | Gale Wings | IMPLEMENTED |  |
| 178 | Mega Launcher | IMPLEMENTED |  |
| 179 | Grass Pelt | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 180 | Symbiosis | IMPLEMENTED |  |
| 181 | Tough Claws | IMPLEMENTED |  |
| 182 | Pixilate | IMPLEMENTED |  |
| 183 | Gooey | IMPLEMENTED |  |
| 184 | Aerilate | IMPLEMENTED |  |
| 185 | Parental Bond | EXCLUDED | m17_recon.md 13.3 — Mega-exclusive-only holder (Kangaskhan-Mega) |
| 186 | Dark Aura | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Yveltal) |
| 187 | Fairy Aura | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Xerneas) |
| 188 | Aura Break | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Zygarde) |
| 189 | Primordial Sea | IMPLEMENTED |  |
| 190 | Desolate Land | IMPLEMENTED |  |
| 191 | Delta Stream | IMPLEMENTED |  |
| 192 | Stamina | IMPLEMENTED |  |
| 193 | Wimp Out | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs new HP-threshold forced-self-switch mechanism |
| 194 | Emergency Exit | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs new HP-threshold forced-self-switch mechanism |
| 195 | Water Compaction | IMPLEMENTED |  |
| 196 | Merciless | IMPLEMENTED |  |
| 197 | Shields Down | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Minior forms) |
| 198 | Stakeout | IMPLEMENTED |  |
| 199 | Water Bubble | EXCLUDED | [M17n-5] task prompt exclusion |
| 200 | Steelworker | IMPLEMENTED |  |
| 201 | Berserk | IMPLEMENTED |  |
| 202 | Slush Rush | IMPLEMENTED |  |
| 203 | Long Reach | IMPLEMENTED |  |
| 204 | Liquid Voice | IMPLEMENTED |  |
| 205 | Triage | IMPLEMENTED |  |
| 206 | Galvanize | IMPLEMENTED |  |
| 207 | Surge Surfer | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 208 | Schooling | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Wishiwashi-School) |
| 209 | Disguise | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Mimikyu-Busted) |
| 210 | Battle Bond | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Greninja-Ash) |
| 211 | Power Construct | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Zygarde-Complete) |
| 212 | Corrosion | IMPLEMENTED |  |
| 213 | Comatose | IMPLEMENTED |  |
| 214 | Queenly Majesty | IMPLEMENTED |  |
| 215 | Innards Out | IMPLEMENTED |  |
| 216 | Dancer | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs new dance flag + move-repeat mechanism |
| 217 | Battery | IMPLEMENTED |  |
| 218 | Fluffy | IMPLEMENTED |  |
| 219 | Dazzling | IMPLEMENTED |  |
| 220 | Soul-Heart | EXCLUDED | m17_recon.md 13.1 — mythical-exclusive (Magearna) |
| 221 | Tangling Hair | IMPLEMENTED |  |
| 222 | Receiver | IMPLEMENTED |  |
| 223 | Power Of Alchemy | IMPLEMENTED |  |
| 224 | Beast Boost | EXCLUDED | m17_recon.md 13.1 — Ultra-Beast-exclusive (all 11 UBs, zero non-UB holders) |
| 225 | RKS System | EXCLUDED | [M17n-4] decisions.md — Rob's explicit instruction, excluded from Group 7's own tier |
| 226 | Electric Surge | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 227 | Psychic Surge | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 228 | Misty Surge | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 229 | Grassy Surge | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 230 | Full Metal Body | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Solgaleo) |
| 231 | Shadow Shield | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Lunala) |
| 232 | Prism Armor | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Necrozma) |
| 233 | Neuroforce | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Necrozma-Ultra) |
| 234 | Intrepid Sword | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Zacian) |
| 235 | Dauntless Shield | EXCLUDED | m17_recon.md 13.1 — box-legendary-exclusive (Zamazenta) |
| 236 | Libero | IMPLEMENTED |  |
| 237 | Ball Fetch | EXCLUDED | [M17n-1] decisions.md — confirmed genuinely out-of-battle-engine scope (Safari-Zone-adjacent, simulator-layer) |
| 238 | Cotton Down | IMPLEMENTED |  |
| 239 | Propeller Tail | IMPLEMENTED |  |
| 240 | Mirror Armor | IMPLEMENTED |  |
| 241 | Gulp Missile | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Cramorant forms) |
| 242 | Stalwart | IMPLEMENTED |  |
| 243 | Steam Engine | IMPLEMENTED |  |
| 244 | Punk Rock | IMPLEMENTED |  |
| 245 | Sand Spit | IMPLEMENTED |  |
| 246 | Ice Scales | IMPLEMENTED |  |
| 247 | Ripen | IMPLEMENTED |  |
| 248 | Ice Face | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Eiscue-Noice) |
| 249 | Power Spot | IMPLEMENTED |  |
| 250 | Mimicry | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 251 | Screen Cleaner | IMPLEMENTED |  |
| 252 | Steely Spirit | IMPLEMENTED |  |
| 253 | Perish Body | EXCLUDED | [M17n-8] decisions.md — excluded from that sub-tier, blocked on the unimplemented Perish Song move; confirmed excluded per Rob's direct instruction 2026-07-06 |
| 254 | Wandering Spirit | IMPLEMENTED |  |
| 255 | Gorilla Tactics | IMPLEMENTED |  |
| 256 | Neutralizing Gas | IMPLEMENTED |  |
| 257 | Pastel Veil | IMPLEMENTED |  |
| 258 | Hunger Switch | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Morpeko forms) |
| 259 | Quick Draw | IMPLEMENTED |  |
| 260 | Unseen Fist | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Urshifu) |
| 261 | Curious Medicine | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list |
| 262 | Transistor | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Regieleki) |
| 263 | Dragon's Maw | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Regidrago) |
| 264 | Chilling Neigh | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Glastrier) |
| 265 | Grim Neigh | EXCLUDED | m17_recon.md 13.1 — legendary-exclusive (Spectrier) |
| 266 | As One | EXCLUDED | m17_recon.md 13.1 — box-legendary-fusion-exclusive (Calyrex-Ice) |
| 267 | As One | EXCLUDED | m17_recon.md 13.1 — box-legendary-fusion-exclusive (Calyrex-Shadow) |
| 268 | Lingering Aroma | IMPLEMENTED |  |
| 269 | Seed Sower | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 270 | Thermal Exchange | IMPLEMENTED |  |
| 271 | Anger Shell | IMPLEMENTED |  |
| 272 | Purifying Salt | IMPLEMENTED |  |
| 273 | Well-Baked Body | IMPLEMENTED |  |
| 274 | Wind Rider | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs a new wind_move MoveData flag |
| 275 | Guard Dog | IMPLEMENTED |  |
| 276 | Rocky Payload | IMPLEMENTED |  |
| 277 | Wind Power | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs a new wind_move MoveData flag |
| 278 | Zero to Hero | EXCLUDED | m17_recon.md 8.4 — Mega/battle-form-bound (Palafin-Hero) |
| 279 | Commander | EXCLUDED | m17_recon.md 8.6 — Tatsugiri+Dondozo two-party-member gimmick |
| 280 | Electromorphosis | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs a new wind_move MoveData flag |
| 281 | Protosynthesis | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list — needs a "highest stat" helper (Quark Drive's own terrain half is separately excluded above) |
| 282 | Quark Drive | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 283 | Good as Gold | EXCLUDED | [M17n-9] decisions.md — "explicitly EXCLUDED... per Rob's instruction" |
| 284 | Vessel of Ruin | EXCLUDED | [M17n-5] task prompt exclusion (Ruin quartet, needs new field-aura mechanism, deferred as a group) |
| 285 | Sword of Ruin | EXCLUDED | [M17n-5] task prompt exclusion (Ruin quartet) |
| 286 | Tablets of Ruin | EXCLUDED | [M17n-5] task prompt exclusion (Ruin quartet) |
| 287 | Beads of Ruin | EXCLUDED | [M17n-5] task prompt exclusion (Ruin quartet) |
| 288 | Orichalcum Pulse | EXCLUDED | [M17d] decisions.md — reclassified Koraidon-exclusive per Rob's updated legendary-exclusivity standard |
| 289 | Hadron Engine | EXCLUDED | [M17d] Next-tier note / CLAUDE.md M17d line — Terrain system voided entirely |
| 290 | Opportunist | IMPLEMENTED |  |
| 291 | Cud Chew | IMPLEMENTED |  |
| 292 | Sharpness | IMPLEMENTED |  |
| 293 | Supreme Overlord | EXCLUDED | [M17n-5] task prompt exclusion |
| 294 | Costar | IMPLEMENTED |  |
| 295 | Toxic Debris | IMPLEMENTED |  |
| 296 | Armor Tail | IMPLEMENTED |  |
| 297 | Earth Eater | IMPLEMENTED |  |
| 298 | Mycelium Might | IMPLEMENTED |  |
| 299 | Hospitality | IMPLEMENTED |  |
| 300 | Mind's Eye | IMPLEMENTED |  |
| 301 | Embody Aspect | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list (Embody Aspect x4) |
| 302 | Embody Aspect | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list (Embody Aspect x4) |
| 303 | Embody Aspect | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list (Embody Aspect x4) |
| 304 | Embody Aspect | EXCLUDED | [M17n-6] decisions.md Step 0 accumulated-exclusion-set list (Embody Aspect x4) |
| 305 | Toxic Chain | EXCLUDED | m17_recon.md 13.1 — DLC legendary trio, same shape as the Ruin quartet (the Loyal Three) |
| 306 | Supersweet Syrup | IMPLEMENTED |  |
| 307 | Tera Shift | EXCLUDED | m17_recon.md 8.1 — Terapagos Terastal-exclusive |
| 308 | Tera Shell | EXCLUDED | m17_recon.md 8.1 — Terapagos Terastal-exclusive |
| 309 | Teraform Zero | EXCLUDED | m17_recon.md 8.1 — Terapagos Terastal-exclusive |
| 310 | Poison Puppeteer | EXCLUDED | m17_recon.md 13.1 — mythical-exclusive (Pecharunt) |
| 311 | Piercing Drill | EXCLUDED | m17_recon.md 13.3 — hack-custom-Mega-exclusive-only holder (Excadrill-Mega) |
| 312 | Dragonize | IMPLEMENTED |  |
| 313 | Eelevate | EXCLUDED | m17_recon.md 8.3 — hack-custom, description literally "Unimplemented." |
| 314 | ------- | EXCLUDED | m17_recon.md 8.3 — hack-custom, empty enum slot |
| 315 | Mega Sol | EXCLUDED | m17_recon.md 8.3 — hack-custom addition, not mainline |
| 316 | Fire Mane | EXCLUDED | m17_recon.md 8.3 — hack-custom, description literally "Unimplemented." |
| 317 | ------- | EXCLUDED | m17_recon.md 8.3 — hack-custom, empty enum slot |
| 318 | Spicy Spray | EXCLUDED | m17_recon.md 13.3 — hack-custom-Mega-exclusive-only holder (Scovillain-Mega) |


## Maintenance

When a future tier implements Stench or any currently-EXCLUDED ability gets reconsidered:
1. Update that ID's row: change its Status and Note.
2. Update the three running totals in this file's header (226/91/1, and the sum-check line).
3. Do NOT re-run a full 318-ID recount from scratch — this file IS the source of truth now.
   Only re-verify the specific ID(s) that changed, plus re-confirm the code-derived
   IMPLEMENTED count still matches `ability_manager.gd`'s actual constant list (a quick
   `grep -oP "const ABILITY_\w+:\s*int\s*=\s*\d+" scripts/battle/core/ability_manager.gd | wc -l`,
   minus 1 for `ABILITY_NONE`).
4. If Stench (1) gets implemented, this file's own "1 OPEN" bucket becomes empty and M17 can
   be truthfully declared fully closed for the first time — update CLAUDE.md's status line
   accordingly at that point, not before.

See `docs/decisions.md`'s `[M17 Final Reconciliation]` entry for the full session narrative
this ledger was produced during.

