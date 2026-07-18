# M18.5h Pre-Recon — Nature / IV / EV System Scoping

Report-only recon. **No implementation code was touched in this session** — no
`.gd` file, `.tres` file, or test file was modified; the only change is this
document. Mirrors the recon-first, Rob-decides pattern already used for
`docs/m17_recon.md` (abilities), `docs/m18_item_ledger.md`/`m18_subtier_plan.md`
(items), and `docs/m19_recon.md` (moves) — findings and open questions for Rob
to review before any M18.5h implementation prompt gets written.

Sources consulted: `reference/pokeemerald_expansion/include/constants/pokemon.h`
(Nature/IV/EV constants), `reference/pokeemerald_expansion/include/pokemon.h`
(`NatureInfo`/`SpeciesInfo` struct layouts), `reference/pokeemerald_expansion/
src/pokemon.c` (`CalculateMonStats`, `ModifyStatByNature`, `GetNature`/
`GetNatureFromPersonality`, `MonGainEVs`), `reference/pokeemerald_expansion/
src/battle_util.c` (Hidden Power's power derivation),
`reference/pokeemerald_expansion/src/battle_main.c` (Hidden Power's type
derivation), `reference/pokeemerald_expansion/src/battle_script_commands.c`
(`Cmd_getexp`, `MonGainEVs`'s two call sites), `reference/pokeemerald_expansion/
src/data/pokemon/species_info/gen_1_families.h` (real per-species `evYield_*`
data, spot-checked), `scripts/battle/core/battle_pokemon.gd` (current
`from_species`/stat-formula state), `scripts/data/pokemon_species.gd` /
`scripts/data/pokemon_registry.gd` (current species-data schema/API),
`data/pokemon.json` (current extracted species data), `docs/decisions.md`'s
`[M18.5d]` entry (gender infrastructure — the closest prior precedent),
`docs/m19_recon.md`'s Section D items 2–3 (Hidden Power / Return-Frustration),
`docs/m18_subtier_plan.md`'s Section C (the confusion-berry exclusion and
Power-item deferral this recon's cross-cutting section re-examines).

---

## Section A — Current baseline (confirmed directly, re-verified this session)

- **`BattlePokemon.from_species` still hardcodes `ivs = [0, 0, 0, 0, 0, 0]` and
  `evs = [0, 0, 0, 0, 0, 0]` unconditionally** (`battle_pokemon.gd:354-355`),
  exactly as `[M18.5d]`'s own Step 0 found and flagged — re-verified directly
  in this session rather than trusted from the prior citation. The field's own
  doc comment (`battle_pokemon.gd:58-60`) still reads "Both zeroed in
  from_species() for Milestone 1; real values added later." Zero `randi()`
  calls exist anywhere in `battle_pokemon.gd` outside `_roll_gender`
  (`[M18.5d]`'s own addition) — still true.
- **The stat formulas already correctly READ `ivs[]`/`evs[]`** —
  `_stat_formula`/`_hp_formula` (`battle_pokemon.gd:469-476`) both take real
  `iv`/`ev` parameters and compute `floori(ev / 4.0)` correctly. This is an
  important asymmetry to note: the **EV read-path is already fully wired and
  correct** (it just always reads zero because nothing ever writes anything
  else); nothing needs to change in the stat formula itself to make EVs work
  once something actually grants them. The **Nature multiplier has NO
  insertion point at all yet** — neither formula has any nature-aware term;
  this is new code, not a dormant/miswired one.
- **Zero `nature`/`Nature` references anywhere in `scripts/`, `scenes/`, or
  `data/pokemon.json`** (grepped directly). **Zero `ev_gain`/`evYield`/
  `ev_yield` references anywhere** either — confirmed, not assumed, matching
  the task's own framing.
- **`data/pokemon.json` already carries `base_friendship` for all 386 species**
  (e.g. Bulbasaur: 50) — but this is a **species-level constant**, not a
  mutable per-individual field on `BattlePokemon`. No `friendship`-style field
  exists on `BattlePokemon` at all. (Relevant to Section E below, not this
  tier's own scope.)
- **`PokemonSpecies`/`PokemonRegistry` have no dormant Nature or EV-yield
  field anywhere** — confirmed via full read of both files' schemas/APIs.
  Unlike `[M18.5d]`'s `gender_ratio` finding (already extracted into the JSON,
  just unwired), **there is no equivalent head start here for either Nature or
  EV data** — see Sections B/D below for what each actually needs.
- **The species-data extractor script (`tools/convert_pokedata.py` per
  `[M15]`'s own decisions.md entry) still does not exist anywhere in this
  repo** — re-confirmed via `find`, matching `[M18.5d]`'s own finding exactly.
  Any new per-species extraction (EV yield, see Section D) has no existing
  rerunnable tool to extend; it would need a new one-off script.

---

## Section B — Nature

### B1. The 25-nature table (confirmed directly from source, not the task's own framing)

`include/constants/pokemon.h` L52-76 (`NATURE_HARDY` through `NATURE_QUIRKY`,
`NUM_NATURES = 25`) carries an authoritative `// +X -Y` / `// Neutral` comment
on every single constant. Spot-verified 2 of the 25 against the actual data
table (`gNaturesInfo[]`, `src/pokemon.c` L154-453) rather than trusting the
header comments alone: Hardy has `.statUp = STAT_ATK, .statDown = STAT_ATK`
(equal → neutral, matches "// Neutral"); Lonely has `.statUp = STAT_ATK,
.statDown = STAT_DEF` (matches "// +Atk -Def"). The header comments are
confirmed accurate.

| # | Nature | Raises | Lowers |
|---|---|---|---|
| 0 | Hardy | — | — (neutral) |
| 1 | Lonely | Atk | Def |
| 2 | Brave | Atk | Speed |
| 3 | Adamant | Atk | SpAtk |
| 4 | Naughty | Atk | SpDef |
| 5 | Bold | Def | Atk |
| 6 | Docile | — | — (neutral) |
| 7 | Relaxed | Def | Speed |
| 8 | Impish | Def | SpAtk |
| 9 | Lax | Def | SpDef |
| 10 | Timid | Speed | Atk |
| 11 | Hasty | Speed | Def |
| 12 | Serious | — | — (neutral) |
| 13 | Jolly | Speed | SpAtk |
| 14 | Naive | Speed | SpDef |
| 15 | Modest | SpAtk | Atk |
| 16 | Mild | SpAtk | Def |
| 17 | Quiet | SpAtk | Speed |
| 18 | Bashful | — | — (neutral) |
| 19 | Rash | SpAtk | SpDef |
| 20 | Calm | SpDef | Atk |
| 21 | Gentle | SpDef | Def |
| 22 | Sassy | SpDef | Speed |
| 23 | Careful | SpDef | SpAtk |
| 24 | Quirky | — | — (neutral) |

**5 neutral natures, confirmed exactly**: Hardy (0), Docile (6), Serious (12),
Bashful (18), Quirky (24) — every 6th nature in ID order, since the 25-nature
table is structurally a 5×5 grid (5 "raise" stats × 5 "lower" stats) plus
these 5 diagonal (raise == lower) entries.

### B2. Stat-formula insertion point and rounding (confirmed, HP exemption verified from source)

`ModifyStatByNature` (`src/pokemon.c` L4942-4952):
```c
if (statIndex <= STAT_HP || statIndex > NUM_NATURE_STATS || statUp == statDown)
    return stat;
else if (statIndex == statUp)   return stat * 110 / 100;
else if (statIndex == statDown) return stat * 90 / 100;
```
Called from `CalculateMonStats` (`src/pokemon.c` L1408) **immediately after**
the base non-HP formula fully resolves (i.e. after the existing `+5` term is
already added) — `n = floor((2*base+iv+floor(ev/4))*level/100) + 5; n =
ModifyStatByNature(nature, n, i)`. This means the insertion point in this
project's own code is **wrapping the ENTIRE existing `_stat_formula` return
value**, not a term inserted mid-formula:
```gdscript
var n = floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0) + 5
n = apply_nature(n, stat_index, nature)   # floor(n*110/100) or floor(n*90/100)
```
Rounding: `stat * 110 / 100` / `stat * 90 / 100` are C integer division on a
non-negative `u16` — equivalent to `floori()`, not round-half-up or truncate-
toward-zero-on-negatives (moot here since stats are never negative). Directly
maps to GDScript's `floori(n * 110.0 / 100.0)` / `floori(n * 90.0 / 100.0)`.

**HP exemption confirmed directly from source, not assumed**: the guard
`statIndex <= STAT_HP` short-circuits before nature is ever consulted, AND
separately, `CalculateMonStats`'s own HP branch (L1425-1426) computes HP
entirely outside the loop that calls `ModifyStatByNature` at all — HP is
double-insulated from nature, both by the guard and by physically not being
in the code path. This project's `_hp_formula` needs zero nature-related
changes.

### B3 — ⚠️ A real correctness trap this project's own stat-index ordering creates (flagged, not present in the task's own framing)

**Source's `enum Stat` ordering is `HP=0, ATK=1, DEF=2, SPEED=3, SPATK=4,
SPDEF=5`** (`include/constants/pokemon.h` L83-90) — **Speed comes BEFORE
Sp.Atk/Sp.Def.** This project's own `BattlePokemon.STAT_*` constants
(`battle_pokemon.gd` L14-19) order `HP=0, ATK=1, DEF=2, SPATK=3, SPDEF=4,
SPEED=5` — **Speed comes AFTER**. If the Nature table above (or any future
IV/EV-adjacent table) is ever ported by copying source's raw numeric
`statUp`/`statDown` index values directly, every SPEED/SPATK/SPDEF reference
would silently resolve to the wrong stat. The table in B1 above is already
built by STAT NAME, not raw index, specifically to sidestep this — any
implementation must do the same (translate by name, never copy a bare
`3`/`4`/`5` from source without checking which stat it names in THAT
enum). Flagging this explicitly since it's exactly the class of silent,
hard-to-notice bug this project's citation discipline exists to catch, and
because it will resurface identically in Hidden Power's own bit-ordering
(Section E) if that move is ever implemented later.

### B4 — Likes/dislikes (flavor-preference) data: flagged for Rob's explicit exclusion/inclusion call

`NatureInfo` (`include/pokemon.h` L598-609) additionally carries
`pokeBlockAnim`, `battlePalacePercents`, `battlePalaceFlavorText`,
`battlePalaceSmokescreen`, `natureGirlMessage` — all Pokéblock-feeding /
Battle Palace / Battle Frontier NPC-flavor fields, entirely separate from the
`statUp`/`statDown` stat-multiplier mechanic in B1/B2. **Checked this
project's roadmap for any consumer**: CLAUDE.md's explicit "Build order"
section (M1-M14) and every milestone referenced anywhere in `decisions.md`
through the current M18.5 work contain **zero mentions of Pokéblocks,
Poffins, Contests, or any "feed a Pokémon" mechanic** — grepped directly,
confirmed absent, not just unmentioned in passing. **This is a
likely-excludable scope boundary, not a silent inclusion or exclusion** —
recommend excluding entirely (nothing in this project's battle-engine-only
scope would ever consume it), but this is Rob's call to make explicitly, not
a recon conclusion.

### B5. Nature assignment — confirmed, and a genuinely good match for the gender precedent

`GetNature`/`GetNatureFromPersonality` (`src/pokemon.c` L4185-4193):
```c
u8 GetNature(struct Pokemon *mon) {
    return GetMonData(mon, MON_DATA_PERSONALITY, 0) % NUM_NATURES;
}
```
A flat `personality % 25`. This is structurally the **same shape** `[M18.5d]`'s
`_roll_gender` already used for gender (`gender_ratio > randi() % 256`,
reproducing `genderRatio > (personality & 0xFF)` without this project needing
a "personality value" concept) — a direct `randi() % 25` at instance-creation
time reproduces the identical uniform distribution `personality % 25`
produces, with no new infrastructure needed beyond one more roll call in
`from_species`, mirroring `_roll_gender`'s own established pattern exactly
(unlike `[M18.5d]`'s own finding that the task's *IV* precedent didn't
actually exist yet — for Nature specifically, the gender precedent is a
genuinely accurate analog).

---

## Section C — IV

### C1. IV range and current project behavior (re-verified, not just re-cited)

`MAX_PER_STAT_IVS = 31` / `MAX_IV_MASK = 31` (`include/constants/pokemon.h`
L227-228) — confirms the standard 0-31-per-stat range. **Re-verified this
project's current behavior directly this session** (not just cited
`[M18.5d]`'s prior finding): `battle_pokemon.gd:354` still reads `bp.ivs = [0,
0, 0, 0, 0, 0]` unconditionally, unchanged since `[M18.5d]`. This is the
**smallest-surface change of the three sub-systems** — the read-path
(`_stat_formula`) already works correctly; only `from_species` needs new
code, and even that is a single small loop (6 × `randi() % 32`), not new
architecture.

### C2. Design question for Rob — NOT resolved by this recon

Source's model is "roll once, permanently, at the individual's creation"
(`personality`-derived, same generation mechanism as gender/nature). This
project's own **gender precedent is the closest analog and would extend
cleanly** — `ivs[i] = randi() % 32` for each of the 6 stats inside
`from_species`, mirroring `_roll_gender`'s shape exactly (freely
reassignable afterward by test code, no forcing seam, matching every other
per-instance field in this class).

**However**, unlike gender (which has zero downstream "passing" mechanic
this project will ever need), IVs in the real games are inherited via
breeding (Destiny Knot passes 5 IVs from parents — already flagged and
deferred in `[M18.5d]`'s own entry, pending "M28/breeding readiness"), and
can be modified via Hyper Training (`hyperTrained[]` in `CalculateMonStats`
above — a late-game mechanic, not seen anywhere in this project's own
roadmap). **This recon does NOT resolve whether a real random-roll model is
the right choice now, or whether a simpler placeholder (e.g. all-31,
"perfect IVs," deferred to a real roll only when M28/breeding actually needs
inheritance-worthy variance) is more appropriate given no breeding system
exists or is imminent.** Presented here as an explicit design question for
Rob, not a unilateral recon decision, per the task's own instruction.

### C3. Hidden Power's IV dependency — confirmed sufficient, but Hidden Power itself stays a separate, later concern

`EFFECT_HIDDEN_POWER`'s **power** is only IV-dependent in **pre-Gen-6**
(`battle_util.c` L6319-6331, gated `if (B_HIDDEN_POWER_DMG < GEN_6)`) — this
project defaults every generational flag to `GEN_LATEST` (established
precedent: `[M18.5f]`'s binding turns, `[M18.5g]`'s hit-count roll
distribution), so **power is a fixed 60 regardless of IVs** under this
project's own config convention. Only **type** remains IV-dependent, always
(`battle_main.c` L5850-5880):
```c
typeBits = (hpIV&1)<<0 | (atkIV&1)<<1 | (defIV&1)<<2 | (speedIV&1)<<3
         | (spAtkIV&1)<<4 | (spDefIV&1)<<5
moveType = ((hpTypeCount - 1) * typeBits) / 63
```
— the **lowest bit** of all 6 IVs, in source's own `enum Stat` bit order
(HP/Atk/Def/**Speed**/SpAtk/SpDef — the SAME ordering trap flagged in B3
applies here too, if this formula is ever ported), indexed against the list
of types flagged `isHiddenPowerType` in `types_info.h` (not individually
counted/verified this session — flagged as a detail to re-confirm at
actual-implementation time, not asserted here).

**Confirmed**: this recon's own IV scope (Section C, any of the design
options in C2 that produces a real, non-hardcoded-zero per-instance IV
array) would be **fully sufficient data** for Hidden Power's type derivation
— no additional infrastructure beyond "IVs exist and vary" is needed.
**However**, implementing Hidden Power itself — wiring `EFFECT_HIDDEN_POWER`
into `move_data.gd`/`battle_manager.gd`'s actual move dispatch — is
**explicitly out of this tier's own scope**, per `docs/m19_recon.md`'s own
framing: it's catalogued there as a *move* needing this *data*, not part of
the Nature/IV/EV *infrastructure* itself. This recon's finding is only that
M18.5h's IV work would **unblock** Hidden Power as a future move-effect
tier, not that M18.5h should build it.

---

## Section D — EV

### D1. EV-yield-on-defeat mechanic, EV caps — confirmed exactly, including a correction to this task's own framing

**⚠️ Correction**: this task's own framing cited "the 520-total-EV cap" —
this is **incorrect**. Confirmed directly: `MAX_TOTAL_EVS = 510`
(`include/constants/pokemon.h` L231), not 520. This is a well-known number in
the Pokémon community and an easy one to misstate (510 is intentionally NOT
evenly divisible by the 252 per-stat cap — by design, exactly two stats at
252 plus 6 leftover). Per-stat cap: `MAX_PER_STAT_EVS = ((P_EV_CAP >= GEN_6)
? 252 : 255)` (`include/constants/pokemon.h` L230); `P_EV_CAP = GEN_LATEST`
in this project's own config default (`include/config/pokemon.h` L55) — so
**252 per stat**, matching this project's established "config defaults to
GEN_LATEST" convention.

Per-species yield: `evYield_HP/Attack/Defense/Speed/SpAttack/SpDefense`, each
a 2-bit field (0-3 EVs) on `SpeciesInfo` (`include/pokemon.h` L404-409).
Granted via `MonGainEVs` (`src/pokemon.c` L5049-5150) — per stat, in a fixed
loop order, gated by: (a) `totalEVs >= currentEVCap` stops the whole loop
early once the 510 total is reached; (b) Pokérus doubles the multiplier
(`CheckMonHasHadPokerus`); (c) `HOLD_EFFECT_POWER_ITEM` adds a flat `+8`
bonus (`POWER_ITEM_BOOST`, Gen7+/this project's default — see D4 below) to
ONE specific stat matching the item; (d) `HOLD_EFFECT_MACHO_BRACE` doubles
the whole `evIncrease` again (stacks with Pokérus); (e) two separate clamps
— the per-stat 252 cap and the running-total 510 cap, each independently
truncating `evIncrease` if it would overflow.

### D2. Per-species EV-yield data: confirmed absent, needs a genuinely NEW extraction (the biggest new-data lift of the three sub-systems)

Confirmed via direct grep: **no `ev_yield`/`evYield` field exists anywhere**
in `data/pokemon.json`, `PokemonSpecies`, or `PokemonRegistry`. Unlike
Nature (needs zero species-level data — see B5) or IV (needs zero
species-level data — purely a per-instance roll), **EV yield is priced
in `SpeciesInfo` per-species**, and the real data lives in
`src/data/pokemon/species_info/*.h` (spot-checked against
`gen_1_families.h` — e.g. Bulbasaur `evYield_SpAttack = 1`, Ivysaur/
Venusaur escalating to `2`) — **not yet extracted into this project's
pipeline at all**. Combined with Section A's confirmation that the original
extractor script no longer exists in this repo, populating this field for
all 386 species means writing a **brand-new** one-off extraction pass (most
likely a small Python script parsing or hand-transcribing `evYield_*` from
the `species_info/*.h` files, in the same spirit as `gen_moves.py`/
`gen_items.py`'s own hand-authored-dict pattern, but at **386-row scale** —
meaningfully larger than any prior tier's hand-transcription, which have
topped out around 30 entries (`[M18.5g]`'s 30 multi-hit moves)).

### D3. EV formula insertion point: already correctly wired (re-confirmed, NOT a hardcoded placeholder like IVs)

Directly re-confirmed per Section A: `_stat_formula`/`_hp_formula`
(`battle_pokemon.gd:469-476`) both already compute `floori(ev / 4.0)` from
the REAL `ev` parameter passed in — this is **not** a hardcoded placeholder
the way `ivs`/`evs` themselves are in `from_species`. The formula's read-side
is already 100% correct; **zero changes needed to either stat formula for
EVs to work**, the moment something other than `from_species`'s hardcoded
zero-array ever writes a real value into `evs[]`.

### D4. Battle-flow infrastructure: a cheap hook exists, but it models a DIFFERENT (simpler) system than source's real one

`MonGainEVs` is called from **exactly two places**, both inside
`Cmd_getexp` — the Exp-award state machine (`battle_script_commands.c`
L3976, L4063) — **not** a separate "battle ended, apply post-battle effects"
phase. Both call sites are gated by the SAME `expGettersOrder`/
`expSentInMons`/`wasSentOut` bookkeeping that determines which of the
player's PARTY members (not just the active battler) receive Exp — i.e., in
source, **EV gain and Exp gain are the same dispatch, sharing the same
party-wide, Exp-Share-aware recipient list.** This project has **zero**
Exp-Share/multi-recipient infrastructure (M20, Experience & Leveling, has
not started).

This project's only existing "something happened when a mon fainted" hook is
`pokemon_fainted` (signal) + `_last_attacker` (dictionary) — already used for
Moxie (`ability_manager.gd:3868-3874`), a **single-recipient** model (only
the mon that landed the killing hit). A "cheap" EV-gain hook COULD attach to
this existing signal with **zero new infrastructure**, granting EVs only to
the killer — but this would model a **meaningfully simpler, single-recipient
system than source's real party-wide one**, since this project currently has
no concept of "which other party members are eligible" the way Exp-Share
requires. See Section F (cross-cutting) for the explicit risk this creates
against M20.

---

## Section E — Return / Frustration: confirmed NOT in this tier's scope, a separate concern entirely

Per `docs/m19_recon.md`'s own Section D item 3: both moves scale power with
(or against) the holder's **mutable, per-individual friendship** value — a
**4th stat, wholly unrelated to Nature/IV/EV.** Confirmed directly:
`PokemonSpecies.base_friendship` exists (species-level constant, e.g.
Bulbasaur = 50 per `data/pokemon.json`), but there is **no mutable
per-individual friendship field anywhere on `BattlePokemon`** — friendship
changes through play (walking, battling, level-ups, certain berries/items)
in source, none of which this project tracks. **This genuinely does NOT fall
under M18.5h's Nature/IV/EV umbrella at all** — it is a separate, later
concern (most likely its own small tier once/if Return/Frustration are ever
prioritized), not a sub-component of this recon's own scope. Flagged per the
context-gathering instruction's own request to confirm this relationship
precisely rather than assume it.

(Incidentally: `CalculateMonStats` also carries a `B_FRIENDSHIP_BOOST`
friendship-based STAT boost, distinct from Return/Frustration's move-power
use of the same value — confirmed `FALSE` by default in this project's own
config, `include/config/battle.h` L23, an LGPE-only mechanic. Not relevant to
either Nature/IV/EV or Return/Frustration; noted only to avoid conflating it
with either.)

---

## Section F — Cross-cutting scope questions (decisions for Rob, not recon conclusions)

### F1. Should this tier build EV gain-on-defeat at all, given M20's future overlap?

**Confirmed real risk, not hypothetical**: per D4, source's EV gain is
architecturally the SAME dispatch as Exp gain (both driven by `Cmd_getexp`'s
party-wide, Exp-Share-aware recipient list). This project's only cheap hook
(`pokemon_fainted`/`_last_attacker`, Moxie's own precedent) is
single-recipient — a materially simpler model. Building EV-gain now via that
cheap hook would very likely need **rework** once M20 (Experience &
Leveling) builds real party-wide Exp/EV distribution, since M20 will need to
either absorb this tier's EV-gain call site into its own new dispatch or
maintain two separate "a mon fainted, distribute rewards" pathways
side-by-side. **Options for Rob to choose between**, not resolved here:
  - (a) Build EV-gain now via the cheap single-recipient hook, accepting the
    rework risk when M20 lands.
  - (b) Defer EV-gain (yield data + grant logic) entirely to M20, building
    only Nature + IV in M18.5h, and let M20 build Exp + EV together as one
    correctly-modeled system from the start.
  - (c) Build the EV-YIELD DATA now (Section D2's extraction, which M20 will
    need regardless and has zero risk of being modeled wrong), but defer the
    GRANT LOGIC (D4's dispatch) to M20.

### F2. Which items on M18.5's existing unblock list actually need which sub-system — confirmed individually, not assumed uniform

- **Figy/Wiki/Mago/Aguav/Iapapa (5 "confusion berries")**: **⚠️ correction to
  this task's own framing** — these are NOT an open item on an "unblock
  list" waiting on Nature. `docs/m18_subtier_plan.md`'s Section C item 5
  shows Rob **already excluded them by design** ("functionally too similar
  to Sitrus Berry to be worth building as distinct items"), independent of
  the Nature-data blocker, with its own closing line: "revisit only if a
  nature system is ever built AND Rob decides the confusion-on-dislike
  differentiation is worth adding at that point." **Building Nature in
  M18.5h does not automatically reopen this family** — it would need a
  SEPARATE, explicit re-confirmation from Rob, not an automatic unblock.
- **Power Weight/Bracer/Belt/Lens/Band/Anklet** (`HOLD_EFFECT_POWER_ITEM`,
  6 items): need **EV specifically**, not Nature or IV. Their Speed-halving
  half is already built (`[M18h]`, `item_manager.gd:1053`); their EV-boost
  half (+8 EVs to one matching stat per KO, `POWER_ITEM_BOOST` = 8 under
  this project's Gen7+/`GEN_LATEST` default, `include/config/item.h` L19)
  needs D4's grant-logic infrastructure specifically.
- **Macho Brace**: also needs EV specifically (doubles ALL EV gain,
  `MonGainEVs`'s own `HOLD_EFFECT_MACHO_BRACE` branch) — already shares its
  Speed-halving branch with the Power items above in this project's code.
- **Confirmed**: no item currently on this project's unblock list needs
  Nature or IV specifically — only EV. Worth stating explicitly since this
  task's own framing implied all three sub-systems might be needed uniformly
  for the same unblock list; that assumption doesn't hold.

### F3. Proposed sub-tier breakdown

Nature, IV, and EV are **genuinely separable** — confirmed, not just
assumed from their category names. The only shared touchpoint is that
Nature's multiplier (B2) and EV's already-existing `floor(ev/4)` term (D3)
both live inside the same `_stat_formula`/`_hp_formula` functions — a minor,
easily-sequenced overlap (Nature adds one new wrapping step; EV's own term
is already correct and needs no changes), not a real shared-infrastructure
dependency requiring combined design work.

Proposed order, smallest/most-resolved-first:

1. **M18.5h-1 — IV.** The smallest surface (Section C) — a `from_species`
   change plus (per C2) an open design-model question to resolve early,
   since it's the same "roll once at creation vs. simplified placeholder"
   shape Nature will also need an answer to.
2. **M18.5h-2 — Nature.** Small, fully self-contained (Section B) — zero
   species-level data-pipeline work (unlike EV), a static 25-row table +
   one roll function + one stat-formula wrapping step, closely mirroring
   `[M18.5d]`'s own gender precedent in both size and shape.
3. **M18.5h-3 — EV.** By far the largest (Section D) — a genuinely NEW
   386-species data-extraction pass (D2, no existing tool to extend), new
   battle-flow dispatch logic (D4), the cap-clamping/Pokérus/Power-item/
   Macho-Brace interaction logic, AND the F1 design decision about M20
   overlap risk that should be resolved BEFORE this sub-tier starts, not
   during it.

This ordering also means F2's confirmed EV-only unblock-list items (Power
items, Macho Brace) stay blocked until M18.5h-3 specifically — building
IV/Nature first does not unblock any item currently on this project's list.
