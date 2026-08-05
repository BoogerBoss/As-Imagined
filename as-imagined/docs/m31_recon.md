# M31 Recon — Egg/Breeding

Step 0 scoping pass. No game code touched, no `.tres`/`.json` files created.
Every claim below is cited against
`/home/rob/GodotAsImagined/reference/pokeemerald_expansion` (file:line) or
against this project's own current source — nothing here is from general
Pokémon-modding memory.

## TL;DR

- The reference Day Care's real mechanics live in one file,
  **`src/daycare.c`** (1,657 lines), and split cleanly into two groups by
  function name: **deposit/withdraw/leveling** (`StorePokemonInDaycare`,
  `TakePokemonFromDaycare`, `ApplyDaycareExperience`) are UI-facing,
  party-mutating functions — this project's own already-settled
  **M27I** boundary — and **egg generation/inheritance**
  (`_TriggerPendingDaycareEgg`, `InheritIVs`, `InheritAbility`,
  `BuildEggMoveset`, `GetDaycareCompatibilityScore`, `_GiveEggFromDaycare`)
  are pure mechanics with no UI dependency at all — **M31**. **The split is
  real and already correct** — confirmed directly against source structure,
  not just restated from this project's own prior decision (§2).
- **A confirmed, real citation error, exactly as flagged**: CLAUDE.md's own
  `[M18.5d Phase 2]` and `[M18.5i]` status-history entries twice call
  Destiny Knot's real dependency **"M29/breeding"** — M29 is "Encounters &
  catching," a different, already-narrowed milestone. This is a plain
  wrong-number error, not a second undocumented meaning of M29 — confirmed
  by cross-referencing today's locked roadmap table (M29 = Encounters &
  catching; M31 = Egg/breeding, boundary clarified 2026-07-28). **A second,
  parallel instance of the same mistake exists in `docs/decisions.md`**,
  written the same day (2026-07-08), using **"M28/breeding"** in at least
  6 places — M28 is Evolution, also a real, distinct, now-scoped milestone
  (`docs/m28_recon.md`). Both are flagged explicitly in §3, not silently
  fixed (this recon does not edit either file).
- **`data/pokemon.json`'s `egg_groups` field is real, accurate, sourced
  data — not a placeholder.** Directly spot-checked against source's own
  `EGG_GROUP_*` enum (`include/constants/pokemon.h:32-46`) across a
  representative sample (Bulbasaur `[1,7]`=Monster/Grass, Ditto `[13,13]`,
  legendaries `[15,15]`=Undiscovered/Undiscovered, the gendered Nidoran
  line, genderless-but-breedable Magnemite/Voltorb/Staryu/Porygon) — every
  value matches the reference source exactly. This is the same
  already-real-data shape `gender_ratio`/`base_friendship`/`growth_rate`
  already have (§4.1).
- **A real, previously-undocumented gap, directly analogous to `weight`
  before `[M19-pre1]`**: `data/pokemon.json` has no `egg_cycles` field.
  Source's real per-species hatch-cycle count
  (`gSpeciesInfo[species].eggCycles`, `include/pokemon.h:414`) sits in the
  identical struct neighborhood as `friendship`/`eggGroups`, both of which
  this project already pulls — it was simply never pulled. At this
  project's `GEN_LATEST=GEN_9` config, one "cycle" is a real, cited
  **128 steps** (`P_EGG_CYCLE_LENGTH=GEN_LATEST`, `daycare.c:1181`).
- **A real, previously-undocumented gap: dedicated egg-move data exists in
  the raw reference tree and has never been pulled.**
  `src/data/pokemon/egg_moves.h` (6,361 lines) is a real, separate,
  per-species curated table (`sBulbasaurEggMoveLearnset[]`, etc.) — this
  project's own `data/all_learnables.json` genuinely conflates it with
  level-up/TM/tutor/universal moves, confirmed directly by this project's
  own code comment in `scripts/battle/core/movepool_resolver.gd`
  ("EVERY method combined... with NO per-entry method tag distinguishing
  which route unlocked which move"). A dedicated pull is a well-precedented,
  bounded pipeline task (same shape as `gen_weight_data.py`), not a
  research problem.
- **Both Everstone and Destiny Knot already exist as raw, unprocessed
  entries in `data/items.json`** (id 245 / id 486) — neither has a
  `gen_items.py` entry or `.tres` file. This is the exact
  "raw-dump-not-yet-a-real-consumer" gap class this project has hit
  repeatedly. **Destiny Knot's real dependency IS this milestone**,
  confirmed directly: `InheritIVs` (`daycare.c:609-710`) is the *only*
  place `HOLD_EFFECT_DESTINY_KNOT` is read anywhere in this reference
  checkout, raising the inherited-IV count from 3 to 5.
- **Everstone serves two milestones with one item.** The identical hold
  effect, `HOLD_EFFECT_PREVENT_EVOLVE`, gates BOTH evolution
  (`GetEvolutionTargetSpecies`, cited in `docs/m28_recon.md` §1.6) AND
  nature inheritance/parent-species selection here
  (`GetParentToInheritNature`, `DetermineEggSpeciesAndParentSlots`,
  `daycare.c:532-555, 997-1074`) — building it once serves both M28 and
  M31.
- **The M27I access-point/M31 mechanics split is not just this project's
  own prior call — it maps cleanly onto source's own function boundary**,
  and one function straddles it in a genuinely informative way: real
  source's compatibility SCORE (`GetDaycareCompatibilityScore`, a pure,
  parameterless-of-UI formula over egg groups/gender/OT ID) is consumed
  BOTH by the UI's own "compatibility hint" text formatter
  (`SetDaycareCompatibilityString`) AND by the actual egg-eligibility gate
  (`_GiveEggFromDaycare`) — confirming the score computation itself is
  mechanics (M31), with M27I only ever formatting its result into a string
  (§2).
- **M31 is NOT blocked on PC storage, unlike M33's genuine block on
  encounter-table generation.** Real source's own answer to "the Day Care
  produced an egg but the player's party is full" is confirmed directly
  from the real Kanto-applicable event script
  (`data/scripts/day_care.inc:24-27`, reused verbatim by the FRLG Route 5
  Day Care per that map's own `scripts.inc` comment "Handled by
  data/scripts/day_care.inc"): the egg is simply **held at the counter and
  offered again on a later visit** — `CalculatePlayerPartyCount() !=
  PARTY_SIZE` gates receipt; no box/PC involvement at all. This project
  already has the identical established pattern (**"a full party
  REFUSES"**) for the two closest precedents, `[M27H H4]` (catching) and
  `[M27K K-a]` (the starter gift) — M31 should follow the same shape, not
  invent a new one or wait on M27I's still-deferred PC (I5-5).
- **The Masuda method is doubly moot for this project, not merely
  single-player-adjacent.** Confirmed: this reference's own shiny-odds
  function (`ComputePlayerShinyOdds`, `src/pokemon.c:866-900`) has real
  reroll sources (Shiny Charm, Lure, chain fishing, DexNav) but **zero
  foreign-language/OT reroll of any kind** — the whole mechanic is absent
  from this reference source, not merely inapplicable to a
  single-player game. Compounding that: this project's own `BattlePokemon`
  tracks **no language/origin field on any individual Pokémon instance at
  all** (confirmed by direct grep), and trading/link infrastructure is
  itself a confirmed, standing exclusion (`docs/overworld_scope.md`
  rev 11: "trading, link/Union Room... OUT by implication"). There is no
  data this project could ever produce that the Masuda method could act
  on — it is not a deferred feature, it is a non-applicable one (§6).
- **Zero shiny concept anywhere remains a real, disclosed, cross-milestone
  gap — but it is M27H's, not M31's.** CLAUDE.md's own M27H roadmap-block
  text already lists "shiny" under that block's scope; nothing about
  breeding mechanics changes that ownership.
- **The split-gender-line case the task explicitly asks about is real and
  in this project's own roster**: Nidoran-F/M (dex 29/32) and Illumise/
  Volbeat (dex 314/313) both sit inside the 386-species range, both
  confirmed via direct data read to carry the real always-female (254)/
  always-male (0) gender ratios source uses, and source's real resolution
  mechanism (`DetermineEggSpeciesAndParentSlots`, a random bit in the
  egg's own personality, independent of the ordinary gender roll) is
  small, self-contained, and cited in full (§1.7).

---

## 1. Reference facts (with citations)

### 1.1 `src/daycare.c` — the real file, and its own internal structural split

1,657 lines, confirmed read in full via direct function-listing and
targeted reads of every mechanically-relevant function. The function names
themselves already sort cleanly into the two categories this project's
current M27I/M31 boundary decision describes — see §2 for the full
mapping, cited by function.

`struct DayCare` (referenced throughout, not independently re-derived here
since this project's own equivalent is a fresh design, not a struct port)
holds `DAYCARE_MON_COUNT` (= 2) `DaycareMon` slots, an
`offspringPersonality` (0 = no pending egg), and a `stepCounter`.

### 1.2 IV inheritance — `InheritIVs` (`daycare.c:609-710`)

- Always inherits **3** IVs; **5** if either parent holds
  `ITEM_DESTINY_KNOT` (`:620-621`) — this is Destiny Knot's *entire* real
  in-battle-and-out-of-battle effect in this reference checkout, confirmed
  via a full grep of `battle_hold_effects.c`/`battle_util.c`/
  `battle_script_commands.c` for `HOLD_EFFECT_DESTINY_KNOT`: **zero hits
  anywhere else.** (This directly re-confirms, rather than newly
  discovers, `[M18.5i]`'s own already-recorded finding — see §3.)
- If either parent holds a `HOLD_EFFECT_POWER_ITEM` item (the Power
  Weight/Bracer/Belt/Lens/Band/Anklet family — **already implemented in
  this project, `[M18h]`**), that item's own targeted stat is
  guaranteed-inherited first, consuming one of the 3/5 slots
  (`:630-652`); if BOTH parents hold a Power item, one of the two is
  picked at random to supply the guaranteed slot (`:633-638`).
- The remaining slots are filled by picking a random stat index (with a
  **documented, deliberately-preserved bug** in the non-`BUGFIX` build
  path — `:658-670` — that skews which stat gets picked; this project's
  config is not checked either way, flagged as a real "does this reference
  build with `BUGFIX` defined" question for whoever implements M31c, not
  resolved here) and a random parent (mother=slot 0, father=slot 1) per
  slot (`:673-710`).
- **The parent-slot convention is fixed, not arbitrary**: source's own
  `DetermineEggSpeciesAndParentSlots` (§1.7) always assigns slot 0 to the
  female (or Ditto's non-Ditto partner) and slot 1 to the male (or Ditto);
  `InheritIVs`/`InheritAbility`/`InheritPokeball`/`BuildEggMoveset` are all
  called with those already-resolved slots, not raw daycare-array indices.

### 1.3 Ability inheritance — `InheritAbility` (`daycare.c:742-766`)

- Base case: the mother's own `MON_DATA_ABILITY_NUM` (ability SLOT index,
  0/1/2 — not the raw ability ID) is the candidate to inherit.
- **If the mother is Ditto**, the roles invert at this project's
  `P_ABILITY_INHERITANCE >= GEN_6` config (true at `GEN_LATEST`): the
  FATHER's ability slot becomes the candidate instead (`:749-755`) — this
  is a real, source-confirmed exception to the "mother supplies the
  ability" default, not a symmetric fallback.
- **Two different success chances depending on ability SLOT**: if the
  candidate slot is 0 or 1 (a normal, non-Hidden ability), 80% chance to
  inherit (`Random() % 10 < 8`, `:757-760`); if slot 2 (a Hidden Ability),
  60% chance at this project's config (`P_ABILITY_INHERITANCE >= GEN_6`,
  `:761-765`) — i.e. Hidden Abilities are HARDER to pass down than normal
  ones, the opposite of a plausible "Hidden Abilities are special, so
  favor them" assumption.
- On failure, the egg simply keeps whatever ability `SetInitialEggData`/
  `CreateMonWithIVs` already rolled for it (the species' own default
  slot-0/1 distribution) — `InheritAbility` never explicitly sets a
  fallback, it just doesn't overwrite.

### 1.4 Nature inheritance — Everstone (`GetParentToInheritNature`, `daycare.c:532-590`)

- **Not unconditional, and not symmetric with IV/ability inheritance.**
  `GetParentToInheritNature` scans for a parent holding
  `HOLD_EFFECT_PREVENT_EVOLVE` (Everstone's real hold effect — the SAME
  one M28's own evolution-block mechanism uses, see TL;DR).
- **If BOTH parents hold an Everstone**, the choice of WHICH parent's
  nature is inherited is a coin flip (`Random() & 1`, `:548-549`) — nature
  inheritance itself still happens, just the source parent is randomized.
- **If exactly one parent holds an Everstone**, that parent's nature is
  inherited **unconditionally** at this project's config
  (`P_NATURE_INHERITANCE > GEN_4`, true at `GEN_LATEST` — `:551-552`); at
  an OLDER config it would only be a 50% chance (`:554`, dead code here).
  This is the real answer to "is Everstone's nature-pass 100% or
  probabilistic" — **100% at this project's own config**, with the
  probabilistic branch confirmed unreachable.
- **If NEITHER parent holds an Everstone, nature is fully random**
  (`:566-569`) — no natural "closer to one parent" bias exists.
- The actual mechanism when a nature IS being inherited is a real
  rejection-sampling loop (`:571-587`): roll a random personality value,
  check if it happens to produce the wanted nature, retry up to 2,400
  times. This project's own architecture (nature is a direct rolled field,
  no personality-value intermediate — `[M18.5h-1]`) doesn't need to
  reproduce the rejection loop itself, only its OBSERVABLE effect
  (inherit-or-don't, with the documented chance above).

### 1.5 Pokéball inheritance — `InheritPokeball` (`daycare.c:712-740`)

Not asked for directly by the task, but real, cheap, and directly relevant
to "what data does the egg actually carry" — flagged here rather than
silently dropped. At this project's `P_BALL_INHERITING >= GEN_7` config:
same base species on both parents → 50/50 either parent's ball; different
species and the mother isn't Ditto → mother's ball; otherwise → father's
(i.e. Ditto's own) ball. Master/Cherish/Strange Balls are excluded from
inheritance and fall back to a plain Poké Ball (`:720-724`). Genuinely
small — a single field read/write, not a system.

### 1.6 Egg-move inheritance — `GetEggMoves`/`BuildEggMoveset` (`daycare.c:770-936`)

- `GetSpeciesEggMoves` (`src/pokemon.c:3342-3348`) reads a real, dedicated
  per-species table — `src/data/pokemon/egg_moves.h`, 6,361 lines,
  `s<Species>EggMoveLearnset[]` arrays, confirmed via direct read
  (Bulbasaur: 15 real egg moves — Skull Bash, Charm, Petal Dance, Magical
  Leaf, Grass Whistle, Curse, Ingrain, Nature Power, Amnesia, Leaf Storm,
  Power Whip, Sludge, Endure, Giga Drain, Grassy Terrain) — **this table
  is entirely separate from level-up/TM/tutor data and has never been
  pulled into this project's own pipeline in any form.**
- **`BuildEggMoveset` (`:822-936`) is genuinely a multi-step algorithm,
  not a single lookup**, in this real order:
  1. At this project's `P_MOTHER_EGG_MOVE_INHERITANCE >= GEN_6` config
     (true at `GEN_LATEST`): for each of the MOTHER's own known moves, if
     it's one of the offspring species' real egg moves, give it to the
     egg (`:849-870`) — a real Gen 6+ feature; before Gen 6 only the
     father could pass egg moves.
  2. Unconditionally: same check for the FATHER's own known moves
     (`:872-890`).
  3. At `P_TM_INHERITANCE < GEN_6` (**false, dead code, at this project's
     `GEN_LATEST` config**): a pre-Gen-6 TM-move-inheritance branch
     (`:892-909`) — confirmed inactive at this project's own config, not
     something M31 needs to model.
  4. A real, obscure "shared parent move" rule (`:911-935`): of the
     FATHER's own known moves, any that the MOTHER *also* currently knows
     are collected; of THOSE, any that also appear in the egg species'
     own real level-up learnset get passed down too. This is the
     mechanism behind moves an over-leveled parent has since "forgotten"
     from its own early learnset still transferring if both parents
     happen to share it.
  5. `GiveMoveToMon`'s own 4-slot overflow is handled by
     `DeleteFirstMoveAndGiveMoveToMon` throughout — dropping the OLDEST
     learned move to make room, the same "learned last wins" shape this
     project's own `[M20b]` move-learning-at-level-up already implements.
- **This project's own `data/learnsets.json` (real, level-tagged) is
  directly reusable for step 4's own filter** — no new level-up data
  needed, only the egg-move table itself (step 1/2's real gate).

### 1.7 Species/evolution-stage determination — `GetEggSpecies`/`DetermineEggSpeciesAndParentSlots` (`daycare.c:494-1074`)

- `GetEggSpecies` (`:494-530`) walks a species' own evolution table
  **backwards** up to 5 times, looking for whatever pre-evolves into the
  given species — the real "hatches as the lowest unevolved stage"
  mechanic, reusing evolution DATA (`GetSpeciesEvolutions`) that
  `docs/m28_recon.md` already covers in full (§1.4 of that doc). No new
  evolution-table concept is needed here; M31 consumes the same
  `evolutions.json` M28 already scoped.
- **`DetermineEggSpeciesAndParentSlots` (`:997-1074`) is the real
  species-and-slot-assignment function**, and its core logic (with the
  Gen-4+-region/regional-form branch confirmed MOOT for this project — see
  below) is:
  1. Whichever parent is Ditto (or, if neither is, whichever is female)
     becomes "slot 0" (the mother/primary parent for every other
     inheritance function).
  2. The pre-evolution species of the primary parent (or, per an Everstone
     exception, of whichever parent holds one, `:1028-1035`) becomes the
     egg's target species.
  3. **A real, source-confirmed split-gender-line resolution**
     (`:1039-1046`): if the resolved species is Nidoran-F but the egg's
     own personality has the `EGG_GENDER_MALE` bit set, the target flips
     to Nidoran-M; the identical rule pairs Illumise↔Volbeat. This bit is
     decided at the SAME point (and by the same rejection-loop mechanism)
     as nature inheritance, in `_TriggerPendingDaycareEgg`
     (`:557-590` — a genuinely random 0x8000 bit of the personality's own
     low 16 bits, confirmed via `EGG_GENDER_MALE`'s definition,
     `include/constants/daycare.h:17`, to be independent of the
     personality byte gender/nature actually read from).
  4. **This project's own roster contains both real pairs** — confirmed
     directly: Nidoran-F (dex 29, gender_ratio 254=always-female) /
     Nidoran-M (dex 32, gender_ratio 0=always-male), and Illumise (dex
     314, 254) / Volbeat (dex 313, 0), both pairs sharing real egg groups
     in `pokemon.json` already.
  5. Several further special-case branches (`:1047-1063` — Manaphy→Phione,
     Rotom/Scatterbug/Furfrou/Sinistea/Poltchageist/Mimikyu-Totem/
     Togedemaru-Totem form handling) are all **Gen 4+ species entirely
     outside this project's 386-species (Gen 1-3) roster** — confirmed
     none of the named species/dex numbers fall in range 1-386 — genuinely
     irrelevant noise, not a gap.
  6. `motherIsForeign`/`fatherIsForeign`/`IsSpeciesForeignRegionalForm`
     (`:1025-1033`) — this is the Alolan/Galarian-form regional-breeding
     branch. Confirmed **moot for this project**: this roster (dex 1-386)
     has zero regional-form species, and `GetCurrentRegion()` is itself an
     overworld concept this project's single-region (Kanto-only) design
     has no reason to model. No code path in M31 needs this branch at
     all.

### 1.8 Gender determination for the offspring

The egg's personality (`daycare->offspringPersonality`, decided at cast
time by `_TriggerPendingDaycareEgg`/`_TriggerPendingDaycareMaleEgg`) is
passed straight into the ordinary `CreateMonWithIVs`/`CreateBoxMon`
construction path (`SetInitialEggData`, `:1133-1151`) — the offspring's
actual playable gender is then derived by the exact same
`GetGenderFromSpeciesAndPersonality` function (`src/pokemon.c:1847-1861`)
every other Pokémon in the game uses, reading the species' own
`gender_ratio` against the personality's low byte. **This is, byte for
byte, the same mechanism this project's own `BattlePokemon._roll_gender`
already implements** (`[M18.5d Phase 1]`) — no new gender logic is needed
for M31, only a call to the existing roll using the resolved egg species'
own `gender_ratio`. The `EGG_GENDER_MALE` bit (§1.7) is a *separate* bit
of the same personality value (0x8000, outside the low byte the gender
roll reads) — the two mechanisms don't interfere.

### 1.9 Shiny odds / the Masuda method

`ComputePlayerShinyOdds` (`src/pokemon.c:866-900`) is the one real
shiny-roll function in this reference — confirmed via `SetInitialEggData`/
`CreateMonWithIVs`'s own `OTID_STRUCT_PLAYER_ID` trainer-ID mode, an
egg's shininess is rolled through this exact same function as any other
player-created Pokémon (a wild encounter, a gift Pokémon, etc.), with real
reroll sources: Shiny Charm (`I_SHINY_CHARM_ADDITIONAL_ROLLS`), an active
Lure, chain fishing, and DexNav encounters. **A full read of this function
and a full grep of `src`/`include` for "Masuda" confirms zero
foreign-language/foreign-OT reroll exists anywhere in this reference
checkout** — the Masuda method is not merely inapplicable to a
single-player project, it is genuinely absent from this exact source, in
any generation-gated form. See §6 for the full implication.

### 1.10 Compatibility scoring — `GetDaycareCompatibilityScore` (`daycare.c:1289-1365`)

- **Undiscovered-group exclusion**: if either parent's own first egg-group
  slot is `EGG_GROUP_NO_EGGS_DISCOVERED` (=15), return
  `PARENTS_INCOMPATIBLE` immediately (`:1326-1327`) — this is the real
  legendary-exclusion mechanism, and this project's own `pokemon.json`
  already tags every legendary/mythical in its roster this exact way
  (confirmed via a 13-species spot-check: Zapdos, Moltres, Mew, Lugia,
  Ho-Oh, Celebi, Rayquaza, Kyogre, Groudon, Deoxys, Latios, Latias,
  Jirachi — all `[15,15]`).
- **Two Ditto can't breed** (`:1329-1330`), a special-cased flat
  incompatibility distinct from the general same-species check below.
- **One parent is Ditto**: compatibility bypasses the egg-group-overlap
  AND gender checks entirely — same-OT gives `PARENTS_LOW_COMPATIBILITY`,
  different-OT gives `PARENTS_MED_COMPATIBILITY` (`:1333-1339`). This is
  the real mechanism behind "Ditto pairs with (almost) anything" — the
  ONLY gate a Ditto pairing still has to clear is the earlier
  Undiscovered-group check.
- **Neither parent is Ditto** (`:1341-1364`): same-gender → incompatible;
  **either parent genderless → incompatible** (this is the real
  genderless-non-Ditto rule the task asks about, confirmed directly —
  Magnemite/Voltorb/Electrode/Staryu/Starmie/Porygon are all real,
  breedable-egg-group, genderless species in this project's own roster,
  meaning under this formula they can ONLY ever successfully breed with
  Ditto); no egg-group overlap → incompatible; then a 4-way same-species/
  same-OT matrix (`PARENTS_MAX_COMPATIBILITY` for same-species/different-OT
  down to `PARENTS_LOW_COMPATIBILITY` for different-species/same-OT).
- `EggGroupsOverlap` (`:1289-1303`) is a plain 2×2 any-match check across
  both parents' up-to-2 egg groups each — no weighting, first shared group
  wins.

### 1.11 Egg-cycle / hatch-step mechanic — `TryProduceOrHatchEgg` (`daycare.c:1158-1214`)

- Called every overworld step, via `ShouldEggHatch` →
  `field_control_avatar.c:768` — the SAME real per-step overworld
  dispatch file this project's own already-shipped `[M27D D4]`
  (trainer sight), `[M27H]` (wild encounter check), and `[M27O O4]`
  (field poison tick) all hook into. This is real, existing connective
  tissue between the overworld's step-processing loop and pure mechanics
  — M31's own per-step hook belongs at the identical seam those three
  precedents already established.
- **Egg PRODUCTION** (`:1168-1174`): only checked once BOTH daycare slots
  are occupied AND the second slot's own step counter has just crossed a
  256-step boundary (`(daycare->mons[1].steps & 0xFF) == 0xFF`) — i.e. egg
  production is itself checked only once per 256 steps, not every step.
  When checked, `GetDaycareCompatibilityScore` (possibly boosted by the
  Oval Charm, `ModifyBreedingScoreForOvalCharm` — not investigated
  further, a real item this project doesn't have and isn't asked to model
  here) is rolled against a random threshold.
- **Egg HATCHING** (`:1176-1213`): `daycare->stepCounter` increments every
  step; when it crosses a threshold that is real and CONFIG-DEPENDENT
  (`:1178-1181` — 256/255/257/128 depending on `P_EGG_CYCLE_LENGTH`'s
  generation), **one full cycle has elapsed**. At this project's own
  `P_EGG_CYCLE_LENGTH = GEN_LATEST = GEN_9` config, that threshold is
  **128 steps**. Every egg-carrying party slot's own remaining-cycles
  counter (stored, cleverly, in that mon's `MON_DATA_FRIENDSHIP` field
  while it IS an egg — see §1.12) is decremented by `GetEggCyclesToSubtract()`.
- **`GetEggCyclesToSubtract` (`src/egg_hatch.c:958-973`) is the real Flame
  Body/Magma Armor mechanic**: scans every non-egg party member (not just
  an active battler — any party member) for Magma Armor, Flame Body, OR
  **Steam Engine** (this expansion fork's own addition to the halving
  list — confirmed via direct read, not assumed) and returns 2 (halving
  effective hatch time) if any is found, else 1. **All three abilities are
  already fully implemented in this project** (`ABILITY_FLAME_BODY`=49,
  `ABILITY_MAGMA_ARMOR`=40, `ABILITY_STEAM_ENGINE`=243, per `[M17c]`) —
  their in-battle effects are built; this egg-cycle-halving effect simply
  has no consumer yet, the same dormant-until-M31 shape `weight`/`gender_ratio`
  had before their own consumers landed.
- When a decrement reaches 0, the egg is flagged ready to hatch
  (`gSpecialVar_0x8004 = i; return TRUE;`) — actual hatching (the visual
  scene, `egg_hatch.c`) is presentation and out of M31's own scope per the
  same reasoning `docs/m28_recon.md` §1.8 already established for
  evolution's own scene/mechanics split.

### 1.12 Hatching mutation — `CreateHatchedMon` (`src/egg_hatch.c:308-358`)

Confirms hatching is purely presentational for the mechanics that matter:
species/personality/IVs/moves/held-ball are all read straight off the
already-fully-determined egg and copied verbatim onto the newly-created
mon (`:318-355`) — nothing about the Pokémon's own identity changes at
hatch time. **One real, specific, easy-to-miss rule**: friendship is reset
to a flat **120** on hatching (`:351-352`), NOT the species' own
`base_friendship` value — the egg's `MON_DATA_FRIENDSHIP` field had been
repurposed as the remaining-cycles counter (§1.11) up to this point, and
120 is the real post-hatch starting friendship in this reference,
independent of whatever `base_friendship` the hatched species would
otherwise have as an ordinarily-encountered Pokémon. Language is also
reset from the egg's placeholder Japanese "tamago" nickname/language to
the real player's own game language (`:346-347`).

### 1.13 Incense/held-item baby-form alteration and Volt Tackle — low-priority edge case

`AlterEggSpeciesWithIncenseItem` (`:949-964`) and `GiveMoveIfItem`
(`:976-993`) are both small, table-driven special cases: certain
"baby form" species (e.g. Azurill from Marill) require a specific
Incense item held by a parent to produce the baby form rather than the
base form directly; Pichu with a parent holding a Light Ball learns Volt
Tackle. Neither mechanism is investigated further here — genuinely small,
data-table-driven, and low-priority relative to the core inheritance
mechanics above; flagged for a later sub-tier rather than expanded on.

---

## 2. The M27I/M31 boundary — re-confirmed against real source structure

CLAUDE.md's current M31 roadmap row (*"the Day Care **access point**
(deposit/withdraw UI) is **M27I**; breeding mechanics stay here"*) is
**already accurate**, and maps cleanly onto a real split in `daycare.c`'s
own function names — confirmed directly, not merely re-asserted:

| Function | Real behavior | Owner |
|---|---|---|
| `StorePokemonInDaycare`/`StoreSelectedPokemonInDaycare` (`:248-297`) | Deposits a party/PC mon into an empty daycare slot; strips mail; triggers a form-change check | **M27I** — pure party-interaction UI glue |
| `ShiftDaycareSlots` (`:300-314`) | Compacts slot 1→0 when slot 0 is withdrawn | **M27I** |
| `ApplyDaycareExperience`/`GetNumLevelsGainedFromSteps`/`TakePokemonFromDaycare` (`:316-425, 392-395`) | Retroactively applies accumulated Exp on withdrawal, levels the mon up, teaches level-up moves it missed | **M27I** — this is a real leveling mechanic, but it's the SAME `[M20b]`-already-shipped level-up dispatch this project already owns; nothing egg/breeding-specific about it |
| `GetDaycareCost*` (`:426-446`) | The per-level withdrawal fee | **M27I** |
| `_TriggerPendingDaycareEgg`/`GetParentToInheritNature`/`InheritIVs`/`InheritAbility`/`InheritPokeball`/`BuildEggMoveset`/`DetermineEggSpeciesAndParentSlots`/`_GiveEggFromDaycare`/`SetInitialEggData`/`CreateEgg` | The actual egg-generation/inheritance mechanics | **M31** — zero UI dependency, callable and testable headless |
| `GetDaycareCompatibilityScore`/`EggGroupsOverlap` | The compatibility formula | **M31** (mechanics) — but consumed by BOTH `_GiveEggFromDaycare`'s own eligibility gate (mechanics) AND `SetDaycareCompatibilityString` (`:1374-1391`, a pure UI hint-text formatter). **This is the clean, source-grounded example the task asked for**: the SCORE is mechanics; the STRING is presentation. M31 owns the function that returns a score; M27I owns the one line of code that turns that score into a displayed hint. |
| `TryProduceOrHatchEgg`/`ShouldEggHatch` (`:1158-1223`) | The per-step production-roll and hatch-countdown tick | **The seam itself** — triggered from the overworld's own step-processing loop (`field_control_avatar.c:768`, the same file `[M27D]`/`[M27H]`/`[M27O]` already hook into for trainer sight/wild encounters/field poison), but the WORK it does (rolling compatibility, decrementing a cycle counter, flagging hatch-readiness) is pure M31 mechanics. Treat this the same way M27O's own field-poison tick is treated: a thin per-step call into `BattleManager`/an equivalent mechanics object, not overworld logic itself. |

**Conclusion: the boundary is confirmed correct as stated, requires no
correction, and is now grounded in real source structure rather than only
this project's own prior decision.**

---

## 3. Corrections to this project's own current framing

1. **CLAUDE.md's own `[M18.5d Phase 2]` and `[M18.5i]` status-history
   entries both say "M29/breeding."** Confirmed via direct grep of
   CLAUDE.md (two exact hits, both from the 2026-07-08 session). Today's
   locked roadmap table unambiguously assigns M29 to "Encounters &
   catching" (narrowed 2026-07-28) and M31 to "Egg/breeding" (boundary
   clarified the same day). This is a plain wrong-number citation error
   from a past session — **not** a second, undocumented meaning of "M29"
   — and should read "M31" wherever it's next touched. Not fixed here per
   this recon's own scope (no CLAUDE.md edits made).
2. **A second, parallel instance of the identical mistake exists in
   `docs/decisions.md`**, using **"M28/breeding"** instead — confirmed via
   grep: at least 6 occurrences, all from the same 2026-07-08 session
   (`[M18.5d Phase 2]`/`[M18.5i]`'s own `docs/decisions.md` entries,
   including a full paragraph explicitly stating "M28 (breeding) has not
   started"). M28 is Evolution — a real, distinct, now fully-scoped
   milestone (`docs/m28_recon.md`, "SCOPED 2026-08-04" per the current
   roadmap row). Whether the milestone numbering was genuinely still
   unsettled on 2026-07-08 (before the 2026-07-28 twelve-block M27
   decomposition that also "clarified" M28 and M31's own scopes) is not
   something this recon can determine from the files alone — but under
   TODAY's numbering, both citations are wrong and should read "M31."
   Flagged, not fixed, per this recon's own file-edit scope.
3. **Nothing else in this project's own framing needs correction.** The
   M27I/M31 boundary itself (§2), the `egg_groups` data's real-vs-placeholder
   status (§4.1), and the shiny/Masuda framing (§6) were all checked
   directly and found accurate as currently stated.

---

## 4. What this project already has vs. what's genuinely missing

### 4.1 Already real and directly reusable

- **`data/pokemon.json`'s `egg_groups` field**: real, accurate, matches
  source's `EGG_GROUP_*` enum exactly across every spot-check performed
  (§1.10's citation list). Not a placeholder.
- **`gender_ratio`, `base_friendship`, `growth_rate`, `catch_rate`,
  `ev_yield_*`**: all real, populated, precedent fields — the same
  "already-real, already-populated" data shape as `egg_groups`, useful as
  confirmation that this project's data pipeline is generally trustworthy
  for species-level fields, not just for the one field this recon
  independently verified.
- **`BattlePokemon`'s real rolling infrastructure** (`from_species`,
  `[M18.5d Phase 1]`/`[M18.5h-1]`/`[M18.5h-2]`/`[M19-pre1]`):
  `gender`/`nature`/`ivs`/`friendship` are all real fields with real
  rolling logic and real `forced_nature`/`forced_ivs`/`forced_friendship`
  Variant-forcing parameters. `_roll_ivs`'s own forcing shape — an Array
  of 6 elements, each independently either a forced int or null (roll
  normally) — was built for M24's trainer-data needs, but is the EXACT
  mechanism shape IV inheritance needs (some stats forced from one
  parent, some from the other, the rest random) — directly reusable, not
  a new design.
- **`original_species`/`original_ability`/`original_types`'s
  setter-capture-on-first-assignment pattern**: already built and proven
  (Transform, `[Transform]`/`[Ability-reset fix]`) — the exact shape
  needed if M31's own inheritance mutation ever needs a "restore the
  pre-mutation value" mechanic (it likely doesn't, since an egg's fields
  are set once at creation and never need reverting — flagged so a future
  session doesn't over-build against this precedent unnecessarily).
- **`nickname`/`display_name()`'s already-shipped auto-update check**
  (`[M27K K-c]`): `from_species` already seeds `nickname` with the
  species' own display name, and the "is this still the default" check
  this project already uses for other mutations is the same shape
  source's own `EvolutionRenameMon` uses (`docs/m28_recon.md` §1.10) —
  irrelevant to egg CREATION (an egg is always freshly created, its
  nickname is the Japanese placeholder per source, §1.12) but directly
  relevant if a future session ever wants the hatched mon's own nickname
  logic to match source precisely.
- **Flame Body/Magma Armor/Steam Engine are already fully implemented
  abilities** (`[M17c]`) — their egg-cycle-halving effect is a new
  CONSUMER of an existing ability, not a new ability to build.
- **The "full party refuses" precedent is already established twice**
  (`[M27H H4]` catching, `[M27K K-a]` the starter gift) — directly reusable
  for "the Day Care has an egg ready but the party is full" (§5.2).
- **`OverworldSession`'s flat, additive, per-object `to_save()`/
  `from_save()` save-shape pattern** (`identity`/`flags`/`bag`/`wallet`/
  `respawn`/`party`, `save_manager.gd:63-151`) is proven and trivially
  extensible — a new `daycare` key follows the identical pattern every
  other piece of session state already uses (§5.1).
- **Real Kanto Day Care map data already exists as imported (unbaked)
  data** — confirmed via `map_constants.gd`'s own `MAP_*` table containing
  a Day Care entry, and via the real source scripts/maps directly
  (`FourIsland_PokemonDayCare_Frlg`, `Route5_PokemonDayCare_Frlg`) — but
  no Day Care map is currently baked into `scenes/maps/`, matching this
  project's own vertical-slice scope (the 32-map corridor stops at Pewter
  and never reaches either Kanto Day Care).

### 4.2 Genuinely missing / needs building

- **No `egg_cycles` data anywhere in `data/pokemon.json`** — a real,
  dormant-struct-field gap, same shape as `weight` before
  `[M19-pre1]`/`exp_yield` before `[M20a]` (§1.11, TL;DR).
- **No egg-move-specific data has ever been pulled** — `all_learnables.json`
  conflates it with everything else; the real source table
  (`src/data/pokemon/egg_moves.h`) exists, unpulled (§1.6, TL;DR).
- **Both Everstone (id 245) and Destiny Knot (id 486) exist only as raw,
  unprocessed `data/items.json` entries** — neither has a `gen_items.py`
  entry or `.tres` file. **A small, worth-flagging nuance for whoever
  writes Destiny Knot's real `.tres` description**: the raw dump's own
  description text ("If the holder falls in love, the foe does too")
  reproduces the exact removed-in-Gen-6 flavor text still shipped
  verbatim in this reference's own current source
  (`src/data/items.h:10292-10295`) — confirmed this is the reference
  source's own real current text, not a stale extraction artifact on this
  project's side, and re-confirms `[M18.5i]`'s already-recorded finding
  that this description does not describe the real mechanic
  (`InheritIVs`'s IV-count boost). Don't copy the flavor text verbatim
  into the `.tres` description without correcting it.
- **No compatibility-scoring, IV-inheritance, ability-inheritance,
  nature-inheritance, egg-move-building, or species-determination
  mechanic exists anywhere in this project** — this is the entire real
  build scope of M31 (§7).
- **No Day Care save-state structure exists** — no equivalent of "2
  deposited-mon specs, a step counter, a pending-egg flag/personality"
  anywhere in `OverworldSession`/`SaveManager` (§5.1).
- **No Pokéball-inheritance mechanic** — small, low-priority (§1.5).
- **No Incense/held-item baby-form or Volt Tackle special case** — small,
  low-priority (§1.13).

---

## 5. Cross-milestone dependencies

### 5.1 Save-state (M27L) — a real dependency, but the shape is already well-precedented

Deposited daycare mons, their own hidden parentage/IV/nature snapshot
(needed to actually compute inheritance when the egg is produced), and
the step-counter-toward-hatch are all genuinely playthrough-specific
state and must live inside the active save slot's own payload — the same
"box rule" `docs/overworld_scope.md` §0 already establishes as this
project's day-one save constraint, and the same constraint M33's own
recon (§3.1 of that doc) already had to reckon with for seen/owned dex
state. **Unlike M33's own genuinely open architectural question**
("does this live in the main payload or a separate file, like
`TeamStorage`'s own deliberate carve-out"), M31's answer is
straightforward: Day Care state is exactly as playthrough-specific as
`bag`/`wallet`/`respawn` already are, and `SaveManager.build_payload`/
`apply` (`save_manager.gd:63-151`) already demonstrates the exact
additive pattern a new `"daycare"` key would follow — a real dependency
on M27L existing (it already does), but a trivial, well-precedented
extension of it, not an open design question.

### 5.2 PC storage — confirmed NOT a blocker, unlike M33's genuine one

`docs/m33_recon.md`'s own §3.1 recorded a real, unavoidable hard
dependency on M27L for seen/owned dex state. **M31 has no equivalent hard
dependency on PC storage.** Confirmed directly from real source
(`data/scripts/day_care.inc:24-27`, cited in full in the TL;DR and §1):
the real games' own answer to "an egg is ready but the party has no room"
is to hold the egg at the Day Care counter and offer it again on a later
visit — no box interaction of any kind. This project already has the
identical shape of precedent established twice, independently, for the
exact same class of problem: `[M27H H4]`'s "a full-party catch REFUSES,
source's own no-PC behaviour" and `[M27K K-a]`'s "a full party refuses the
gift [starter] and says so." **M31 should follow the identical
refuse-and-hold pattern** rather than being sequenced behind M27I's own
still-deferred PC (I5-5, "deferred past the slice" per Rob's own
2026-08-03 decision).

### 5.3 Persistent party (M27O O4) — already sufficient scaffolding

The overworld has held a single, real, persistent `BattleParty`
(`OverworldSession.party`, capped at the real `PARTY_SIZE=6` constant)
since `[M27O O4]`, replacing the earlier per-battle-rebuilt debug team.
This is exactly the scaffolding a hatched egg (or a produced-but-not-yet-collected
egg) needs to eventually occupy a party slot — confirmed via source's own
`_GiveEggFromDaycare` writing directly into the last party slot
(`gParties[B_TRAINER_PLAYER][PARTY_SIZE - 1] = egg;`), the same shape
this project's own persistent party already supports. No further
scaffolding is needed here.

---

## 6. Shiny Pokémon and the Masuda method

The general "zero shiny concept anywhere in this project" gap is real,
already disclosed, and already owned by M27H's own roadmap-block text —
nothing about M31's own mechanics changes that ownership, and this recon
does not re-scope it.

**The Masuda method specifically is not a deferred feature of this
project — it is a mechanic with no path to ever applying, confirmed on
two independent, compounding grounds:**

1. **The reference source itself doesn't model it.** A full read of
   `ComputePlayerShinyOdds` (§1.9) plus a full grep for "Masuda" across
   `src`/`include` in this exact checkout returns real reroll sources
   (Shiny Charm, Lure, chain fishing, DexNav) and zero foreign-OT/
   foreign-language reroll of any kind, in any generation-gated branch.
   This is not "present but gated off at this project's config" the way
   several other mechanics in this reference are — it is simply absent.
2. **Even if it existed in source, this project has no data for it to
   read.** `BattlePokemon` carries no language/origin-trainer field on
   any individual instance (confirmed by direct grep of
   `battle_pokemon.gd`), and the entire trade/link system — the only
   real-games mechanism by which two differently-originated Pokémon could
   ever be paired for breeding — is itself a standing, confirmed
   exclusion (`docs/overworld_scope.md` rev 11: "trading, link/Union
   Room, Mystery Gift, Easy Chat, the link minigames" all listed as OUT
   by implication).

Recommendation to state plainly in any future M31 scoping conversation:
treat the Masuda method as **permanently moot**, not as a backlog item —
there is no incremental piece of infrastructure that would ever make it
relevant, since the trading precondition it needs is already excluded at
the project level for reasons unrelated to breeding.

---

## 7. Proposed sub-tier build sequence

| Sub-tier | Scope | Real dependency |
|---|---|---|
| **M31a — data pipeline** | `scripts/gen_egg_moves.py` (mirrors `gen_weight_data.py`'s proven `#if P_FAMILY_*`-gated extraction shape) pulling `src/data/pokemon/egg_moves.h` into a new, dedicated `data/egg_moves.json` — NOT folded into `all_learnables.json`, which stays as-is for its own existing TM/tutor consumer (`MovepoolResolver`). Also pulls `eggCycles` into `data/pokemon.json` as a new field, same file, additive, matching `[M19-pre1]`'s exact precedent. | None — fully self-contained, both pulls are proven-pattern extractions of already-checked-out reference data |
| **M31b — compatibility scoring** | A pure, standalone function porting `GetDaycareCompatibilityScore`/`EggGroupsOverlap` (§1.10) — testable headless with zero UI, zero save-state, zero party involvement. The natural first mechanics piece since nothing else in M31 depends on anything BUT this. | M31a (needs `egg_groups`, already real; needs no new data) |
| **M31c — core inheritance mechanics** | The real algorithmic core: species/parent-slot determination (`GetEggSpecies`/`DetermineEggSpeciesAndParentSlots`, incl. the Ditto/Nidoran/Illumise-Volbeat cases), IV inheritance (`InheritIVs`, reusing `_roll_ivs`'s existing per-stat forcing shape), ability inheritance (`InheritAbility`), nature inheritance (`GetParentToInheritNature`, needs Everstone — see M31e below, but can ship the no-Everstone/random-nature path first and layer the item check in once M31e lands), gender determination (reusing `_roll_gender` unchanged), and egg-move building (`BuildEggMoveset`, needs M31a's egg-move data). The single largest sub-tier; consider splitting species-determination from IV/ability/nature/move inheritance if it proves too large for one session. | M31a (egg-move data), M31b (the compatibility gate `_GiveEggFromDaycare` checks before doing any of this) |
| **M31d — the egg-cycle/hatch mechanic and save-state** | The Day Care's own save-state object (2 deposited-mon specs, step counter, pending-egg personality/flag — a new additive key in `SaveManager`'s payload, §5.1), the per-step production-roll and hatch-countdown tick (`TryProduceOrHatchEgg`, hooked at the same overworld step seam `[M27D]`/`[M27H]`/`[M27O]` already use), and Flame Body/Magma Armor/Steam Engine's egg-cycle-halving effect (a new consumer of 3 already-implemented abilities). | M27L (already shipped, needs only the additive extension), M31c (the egg this state eventually produces) |
| **M31e — Everstone and Destiny Knot** | Two held items, both already sitting as raw `data/items.json` entries — `HOLD_EFFECT_PREVENT_EVOLVE` (Everstone, shared with M28's own evolution-block need) and `HOLD_EFFECT_DESTINY_KNOT` (raises inherited IVs 3→5). Small, self-contained, and — per §7's own Rob-decision item 1 below — worth building once for both M28 and M31 rather than twice. | M31c (Everstone changes nature-inheritance behavior; Destiny Knot changes `InheritIVs`' own IV count) |
| **M31f — deferred / explicitly excluded** | Pokéball inheritance (§1.5) and the Incense/held-item baby-form + Volt Tackle special case (§1.13) — both small, low-priority polish, not core mechanics. The Masuda method is NOT listed here — per §6, it is permanently moot, not deferred. | None — genuinely optional polish whenever picked up |

---

## 8. Decisions needed from Rob

1. **Everstone: build it once, in M31e, serving both M28 (evolution-block)
   and M31 (nature-inheritance eligibility)?** Both milestones need the
   exact same hold effect (`HOLD_EFFECT_PREVENT_EVOLVE`) for two
   different mechanical purposes. **Recommendation: yes** — one item,
   one hold-effect constant, two consumers; building it inside whichever
   milestone reaches it first (this recon proposes M31e, but M28's own
   already-open decision #2 recommends building it "now," so whichever
   milestone actually starts first should claim it).
2. **Destiny Knot: build alongside M31c/M31e, now that its real
   dependency (`InheritIVs`) is finally in scope?** It has been sitting
   deferred since `[M18.5i]` for exactly this reason. **Recommendation:
   yes**, and correct its `.tres` description away from the stale
   Gen IV flavor text this reference's own current source still ships
   verbatim (§4.2).
3. **Should M31c reproduce `InheritIVs`' own documented non-`BUGFIX`-build
   IV-selection bug (§1.2), or the corrected `BUGFIX`-branch behavior?**
   This recon could not determine which build path this reference
   checkout compiles with by default. **Recommendation: use the corrected
   (`BUGFIX`) behavior** — it's a straightforward, uniform random pick
   with no reason to intentionally reproduce an acknowledged upstream bug,
   and this project has no precedent of deliberately preserving a
   confirmed-buggy mechanic elsewhere (compare: the AI-doubles hardlock
   bugs `[M25a]` found and fixed rather than reproduced).
4. **Party-full behavior when an egg is ready: hold-and-reoffer (source-accurate,
   §5.2) or something else?** **Recommendation: hold-and-reoffer**,
   matching real source exactly and this project's own already-established
   `[M27H H4]`/`[M27K K-a]` "full party refuses" precedent — no new design
   needed, and it sidesteps any dependency on M27I's still-deferred PC
   entirely.
5. **Save-shape key naming/placement for Day Care state**: a new
   `"daycare"` key inside `SaveManager`'s existing flat payload dict
   (matching `identity`/`flags`/`bag`/`wallet`/`respawn`/`party`), or a
   separate object with its own `to_save()`/`from_save()` methods the
   payload key simply delegates to (matching how `bag`/`wallet` etc.
   already work)? **Recommendation: the latter** — a new `DaycareState`
   (or similarly-named) class with its own `to_save`/`from_save`, added
   as one more key in `build_payload`/`apply`, is the exact pattern every
   existing piece of session state already follows; no new architectural
   decision is actually needed here, just an application of the existing
   one.
6. **Sub-tier granularity for M31c**: ship species-determination,
   IV/ability/nature inheritance, and egg-move-building as one combined
   sub-tier, or split further? This recon proposes one sub-tier in §7 but
   flags it as the largest, most likely candidate for a split if it
   proves too large in practice. **Recommendation: attempt as one
   sub-tier first** (the individual pieces are each small and
   well-cited above); split only if a real session finds it too large,
   matching this project's own general pattern of not pre-splitting work
   that might not need it.
