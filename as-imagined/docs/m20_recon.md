# M20 Recon — Experience & Leveling System Scoping

Report-only. No code/test changes in this pass. Matches the established
recon convention (`m17_recon.md`/`m18_recon.md`/`m19_recon.md`): catalog
what exists, what's missing, cite source precisely, propose a sub-tier
order, and flag decisions that are Rob's to make rather than resolving
them here.

Scope, per the roadmap discussion: M20 = "Experience & leveling." Every
prior reference to this milestone across the codebase (`[M18.5h-1]`,
`[M18.5h-2]`, `[M18.5i]`, `docs/m18_5h_recon.md`'s own Section F) treats
it as covering both Exp gain/leveling AND EV gain — EV gain was
deliberately deferred here in full (both yield-data extraction and
grant-logic dispatch), per `docs/m18_5h_recon.md`'s own option (b).

## Section A — What already exists (more than a typical fresh milestone)

Because M18.5h built Nature/IV with an eye toward this milestone, and
M15's data pipeline reached further than its own immediate needs, M20
starts with real infrastructure already in place:

- **`data/exp_curves.json`** (M15 Task 4a): all 6 growth-rate curves
  (`MediumFast`/`Erratic`/`Fluctuating`/`MediumSlow`/`Fast`/`Slow`), each a
  plain array indexed by level, holding the CUMULATIVE Exp threshold to
  reach that level — a direct port of source's `gExperienceTables`.
- **`PokemonRegistry.get_exp_for_level(growth_rate, level)`** (M15,
  `scripts/data/pokemon_registry.gd:164`): already reads `exp_curves.json`
  correctly. Confirmed via its own existing test (`growth_rate ==
  "MediumSlow"` for Charizard) that the string-keyed convention matches
  `pokemon.json`'s own `growth_rate` column.
- **`data/pokemon.json`'s `growth_rate` column**: populated for all 386
  species already (string form, e.g. `"MediumSlow"`) — confirmed present
  in the schema dump, not a gap.
- **`PokemonSpecies.exp_yield`** (`scripts/data/pokemon_species.gd:26`):
  the schema FIELD already exists (default `64`, source's own Bulbasaur
  value) — but `pokemon.json` has **no `exp_yield` column at all**, so
  every species currently reads the same hardcoded default regardless of
  its real value. Confirmed via a full column-list dump of `pokemon.json`
  — `exp_yield` is absent. This is the same "schema field exists, data
  pipeline never populated it" gap shape as `gender_ratio` before
  `[M18.5d]` and `base_friendship` before `[M19-pre1]` — a dormant field,
  not a missing mechanism.
- **EV formula read-side, already correct** (re-confirmed via
  `docs/m18_5h_recon.md`'s own Section D3, itself re-verified against
  `_stat_formula`/`_hp_formula` in `battle_pokemon.gd:469-476`): both
  already compute `floori(ev / 4.0)` from the real `ev` parameter — not a
  hardcoded placeholder the way `ivs`/`evs` themselves are in
  `from_species`. **Zero formula changes needed** the moment something
  writes a real value into `evs[]`.
- **`forced_nature`/`forced_ivs`** (`[M18.5h-1]`/`[M18.5h-2]`): explicit
  parameters on `from_species`, built with M24 (Trainer Data) as the
  primary stated consumer, but directly reusable for M20's own test
  fixtures (pinning a mon's Nature/IVs before asserting an exact
  post-level-up stat recompute).
- **Zero Exp/leveling infrastructure of any kind exists yet** — confirmed
  via direct grep: no `current_exp`/`gain_exp`/`level_up` anywhere in
  `battle_pokemon.gd` or `battle_manager.gd`. `BattlePokemon.level` is a
  plain static int set once at construction and never mutated. `MAX_LEVEL`
  has no representation. This milestone is genuinely greenfield beyond the
  data-pipeline pieces listed above.
- **`BattleParty.active_indices`**: tracks which slots are CURRENTLY on
  the field, but there is no "was this mon ever sent out THIS BATTLE" bit
  tracking anywhere (source's `gSentPokesToOpponent`/`expSentInMons`
  bitmask equivalent) — needed for Exp/Exp-Share recipient-list
  computation (see B4).
- **EV yield data**: confirmed **zero** per-species EV-yield data exists
  anywhere in this project (no `ev_yield_*` fields in `PokemonSpecies` or
  `pokemon.json`) — this is the same gap `docs/m18_5h_recon.md`'s Section
  D2 already flagged and explicitly deferred to M20; still fully open.

## Section B — What M20 needs to build

Each item below is independently source-cited; none should be assumed to
share a mechanism with its neighbors without individual verification at
implementation time (the standing discipline this project has followed
since M17n).

**B1. Exp-yield data population (386-species gap).** `exp_yield` is
already a schema field, but needs real per-species values extracted from
source (`gSpeciesInfo[].expYield` across `src/data/pokemon/species_info/
gen_*_families.h`) into `pokemon.json`, the same shape as the `growth_rate`
column that's already there. Cheap, well-precedented (same pattern as
`[M19-pre1]`'s weight/friendship extraction) — no rerunnable extractor
tool exists in this repo for any species field (a recurring, expected gap
class per multiple prior sessions), so a new one-off script would be
needed, matching `scripts/gen_weight_data.py`'s own precedent.

**B2. EV-yield data population (386-species gap, the larger of the two
data-pipeline items).** Source's `evYield_HP`/`evYield_Attack`/
`evYield_Defense`/`evYield_SpAttack`/`evYield_SpDefense`/`evYield_Speed` (6
fields per species, most species yielding 1-3 total points across 1-2
stats) need new `PokemonSpecies` fields plus a 386-row extraction pass —
already flagged as the single largest data-pipeline item M18.5h's own
Section D2 deferred here in full.

**B3. Exp-gain formula — the live branch at this project's actual
`GEN_LATEST=GEN_9` config, confirmed directly from `include/config/
battle.h` (each `B_*` config re-checked line-by-line against its own
consuming `if` in `src/battle_script_commands.c`, not assumed from the
config comment alone) — with real-game generational context added so a
future session knows WHY this project's config branch is shaped this way,
not just what value it currently resolves to:**
- `B_SCALED_EXP = GEN_LATEST` (`include/config/battle.h:17`, comment: "In
  Gen5 and Gen7+, experience is weighted by level difference") → the
  `>= GEN_5 && != GEN_6` branch is live (`battle_script_commands.c` L3917):
  `calculatedExp = exp_yield * fainted_level / 5` (NOT `/7`, the older
  branch). Note the real-game history here is non-monotonic — Gen 5 used
  the scaled formula, Gen 6 reverted to the older `/7` unscaled one, then
  Gen 7+ picked the scaled formula back up — this project's `!= GEN_6`
  clause exists specifically to reproduce that non-monotonic history, not
  a simplification.
- **`B_TRAINER_EXP_MULTIPLIER = GEN_LATEST`** (`include/config/
  battle.h:15`, comment: "In Gen7+, trainer battles no longer give a 1.5
  multiplier to EXP gain") → gated at `battle_script_commands.c:3921`:
  `if (B_TRAINER_EXP_MULTIPLIER <= GEN_7 && ...) calculatedExp = (calculatedExp * 150) / 100;`.
  Since `GEN_9 > GEN_7`, this bonus is **OFF** at this project's config —
  re-verified directly (not a misread) after this recon's own claim was
  challenged. This is a real, separately-timed change from the bigger Gen
  6 Exp-formula overhaul below (B_SPLIT_EXP) — Gen 6 (X/Y) kept the
  trainer bonus alongside its new full-share model; Gen 7 (Sun/Moon) is
  specifically where the 1.5× trainer multiplier was dropped. Per this
  project's own CLAUDE.md principle (source over Bulbapedia prose as
  ground truth), this is being treated as accurate real-game history
  rather than a fork-specific house rule — every other `B_*` config in
  this same file uses an identical "In GenX+, real games changed Y"
  comment style for uncontroversial, well-known mechanic changes, so
  nothing here suggests this one entry is different in kind. Worth a
  spot-check against independent sources before M20b locks in a
  trainer-battle bonus of zero, given how easy this specific (later,
  smaller) change is to miss relative to Gen 6's larger rewrite.
- `B_SPLIT_EXP = GEN_LATEST` (`include/config/battle.h:16`, comment: "In
  Gen6+, all participating mon get full experience") → since `GEN_9 >=
  GEN_6`, the modern **full-Exp-to-every-participant** model applies
  (source: `Cmd_getexp` case 1's `else` branch, `*exp = calculatedExp`
  with no division across `viaSentIn`) — NOT the older Gen 1-5 "split the
  reward across participants" formula. This is genuinely **Gen 6+ in
  origin, not narrowly tied to this project's GEN_9 config value** — it's
  simply been true at every generation since, so `GEN_LATEST` still
  resolves to it. Flagging the real origin generation explicitly so a
  future session reasoning about this config branch understands it's a
  long-standing modern-era rule, not something specific to Gen 9 itself.
  This meaningfully simplifies B4 below versus what an older-gen
  implementation would need.
- `B_MAX_LEVEL_EV_GAINS = GEN_LATEST` → a Lv100 mon still gains EVs (just
  not Exp) — confirmed live at this config, a real rule to reproduce, not
  a simplification to skip.
- `ApplyExperienceMultipliers`/`GetSoftLevelCapExpValue`/
  `GetCurrentLevelCap` (referenced in `Cmd_getexp` case 2 and
  `pokemon.c:3569`) were located but not fully traced in this pass — flag
  as needing their own Step 0 read at implementation time, not resolved
  here. `B_EXP_CAP_TYPE`'s two modes (`EXP_CAP_HARD`/soft) govern whether
  Exp gain is ever truncated at a level cap; likely low-priority for a
  single-player, non-tournament context (see D4).

**B4. Exp-Share / recipient-list dispatch — the highest-leverage open
design question.** Source's real system is genuinely PARTY-WIDE: every
`Cmd_getexp` call computes a recipient list from (a) which mons were sent
into battle this fight and (b) which mons hold `HOLD_EFFECT_EXP_SHARE` or
have the Gen6+ Exp Share flag active, then awards Exp to the whole list in
one pass — sharing its own dispatch with EV gain (`MonGainEVs` is called
from the exact same `Cmd_getexp` state machine, at 2 call sites). This
project's only existing "something happened when a mon fainted" hook is
`pokemon_fainted` (signal) + `_last_attacker` (dict) — Moxie's own
precedent, single-recipient (only the mon that landed the kill). Building
Exp gain via that existing simpler hook would model a meaningfully
narrower system than source's real one — the exact same tension
`docs/m18_5h_recon.md`'s Section F1 already flagged for EV gain, but now
unavoidable rather than deferrable, since Exp gain (unlike EV gain) is
M20's own primary deliverable. See D1.

**B5. Level-up trigger + stat recalculation.** Needs a real `current_exp`
field (doesn't exist anywhere yet) checked against
`PokemonRegistry.get_exp_for_level` each time Exp is awarded, looping
while the threshold is exceeded (a single big Exp award — e.g. from a
high-level Trainer battle — can cross more than one level in one step,
confirmed from source's own `while` loop shape around this check,
`pokemon.c:5180` neighborhood). Stat recompute reuses `_stat_formula`/
`_hp_formula` directly (already fully correct, per Section A) — but a
real rule needs to be gotten right, not just re-invoking the formula:
current HP typically increases by the exact delta in max HP on a level-up
(not reset to full, not left unchanged) — confirmed this project has no
existing precedent for this specific "stat recompute mid-battle,
preserving the damage-taken proportion or delta" shape anywhere.

**B6. Level-up move learning — a related but distinct concern from B5.**
`data/learnsets.json`/`data/all_learnables.json` already exist (M15's
pipeline, `[M18.5j]`'s own species_name wrapper) but have **zero runtime
consumers** anywhere in battle logic yet (confirmed via
`pokemon_registry.gd`'s own `get_learnset()` — zero callers outside the
registry itself, per `[M18.5j]`'s own finding). A real design question:
auto-learn (overwrite the oldest/first move slot, matching this project's
existing "no menu-legality/mid-battle-choice architecture" precedent — see
CLAUDE.md's own Torment/Disable notes on this point) vs. building an
actual move-replacement prompt, which would be the FIRST player-facing
choice UI this project has ever needed mid-battle-flow (M1-M19 explicitly
deferred all UI to last). See D2.

**B7. Level cap / Rare Candy — likely out of scope, flagged not
resolved.** Rare Candy is a non-held BAG item (already covered by
`docs/m25_bag_items_recon.md`'s own 498-item catalogue, not a held
battle item) — its "skip straight to the next level" mechanic has no
battle-time trigger at all in source (it's an overworld/bag-menu action).
`B_EXP_CAP_TYPE`'s hard/soft level-cap system exists mainly to support
in-game "story gate" level caps or link-battle-style formats; recommend
treating this as out of scope for M20's own core deliverable unless Rob
has a specific in-game-progression reason to want it now (see D4).

**B8. Evolution-on-level-up interaction — an ordering dependency, not a
blocker.** The roadmap (per the M20-M32 discussion) already sequences
Evolution (M26) after Leveling (M20), so this is confirmed correctly
ordered already, not a new finding — noted here only so a future session
picking up M20 doesn't have to re-derive that the two milestones are
related. Level-up-triggered evolution checks are M26's own concern, not
M20's — M20 only needs to leave a clean signal/hook point (e.g. an
analogous `pokemon_leveled_up` signal, mirroring `battle_ended`'s/
`pokemon_fainted`'s existing shape) for M26 to later consume.

## Section C — Explicitly out of scope / deferred, and why

- **Exp Share (the physical item) / Rare Candy**: non-held bag items —
  `docs/m25_bag_items_recon.md`'s own domain, not M20's. M20 needs to know
  WHETHER a party member holds a `HOLD_EFFECT_EXP_SHARE` item (that part
  IS in scope, it's a held-item check like any other `ItemManager` gate)
  but does not need to build bag-level Exp Share toggling/management.
- **Friendship-driven mechanics** (Return/Frustration's move power,
  friendship-based evolution): confirmed a wholly separate 4th stat by
  `docs/m18_5h_recon.md`'s own Section E — still separate from Exp/Level
  too, not implicitly bundled into M20 just because both are "numbers that
  change as you play."
- **Move relearning (post-level-up, via an NPC/Move Reminder)**: the
  roadmap's own M28 label is "Move learning & relearning" — recommend M20
  owns only the AT-level-up learn trigger (B6), leaving the separate
  "go back and re-teach an old move" flow to whichever session tackles
  M28, since that flow depends on overworld/NPC infrastructure this
  project doesn't have yet either. Flagged for Rob's confirmation, not
  assumed (see D2).
- **EV-training items' grant-logic** (Power items/Macho Brace,
  `docs/m18_5h_recon.md`'s own Section F2): directly unblocked once B2+B4
  land, but implementing them is a small follow-up to M20's own EV-gain
  dispatch, not part of this recon's scope to build.
- **Trainer-side/NPC leveling** (do enemy trainer Pokémon scale up across
  a playthrough, e.g. rematch-level scaling): a wholly separate concern
  from post-battle Exp gain for the PLAYER's own party — likely M24
  (Trainer Data) territory if it's wanted at all. Flagged, not scoped.

## Section D — Open questions for Rob

**D1. Recipient-model for Exp gain: full party-wide/Exp-Share-aware
dispatch (matching source exactly) vs. a simpler single-recipient model
(extending Moxie's existing `_last_attacker` hook) for a first cut.**
Unlike EV gain (which could be — and was — deferred whole), Exp gain IS
M20's primary deliverable, so this can't be sidestepped the way
`docs/m18_5h_recon.md`'s F1 sidestepped it for EV. Recommend the
party-wide model since it's needed correctly eventually and this project
has generally preferred building the source-faithful version once rather
than twice (e.g. `[M18.5h-2]`'s IV system was built once, correctly, from
the start) — but this is a real scope/cost tradeoff, not an obvious
default, and this recon isn't resolving it unilaterally.

**D2. Scope of level-up move learning (B6): auto-replace-oldest-slot only,
or build an actual choice/prompt mechanism now?** Given this project has
zero mid-battle-flow player-choice UI precedent anywhere, recommend
auto-replace as the M20-scoped default, with the real "prompt to choose
which move to forget" flow explicitly deferred to whenever real UI work
begins (M25's own "UI & overworld" milestone, or wherever the roadmap
lands it) — but this is Rob's call.

**D3. Whether to build the modern GEN_LATEST=GEN_9 config precisely** (no
trainer-battle Exp multiplier, full undivided Exp to every participant) or
intentionally diverge for a specific game-feel reason. Recommend
source-faithful, matching this project's own stated ground-truth
principle, unless Rob wants a deliberate house rule — flagged since the
"no trainer multiplier" fact in particular may be counter to expectation.

**D4. Confirm Rare Candy / hard level caps / the Exp Share bag item are
out of scope for M20 itself** (recommended: yes — all three are
bag-item/UI/progression-format concerns belonging to M25 or a future
"game structure" milestone, not the core Exp/leveling mechanism).

## Section E — Proposed sub-tier sequence

1. **M20a — Data pipeline**: exp_yield (B1) + EV-yield (B2) extraction,
   386-species scale, reusing the established `gen_*.py`-and-new-
   `PokemonSpecies`-field pattern (`[M18.5d]`/`[M19-pre1]`'s own
   precedent). Cheap, no design decisions blocking it — could start
   immediately regardless of how D1/D2 resolve.
2. **M20b — Core Exp-gain-and-level-up dispatch**: `current_exp` field,
   the exact GEN_9-config formula (B3), the recipient-list dispatch per
   D1's resolution (B4), the level-up loop + stat recompute with correct
   current-HP-delta handling (B5). The largest and most architecturally
   consequential sub-tier — should not start until D1 is resolved.
3. **M20c — EV-gain grant logic**: once M20b's dispatch shape exists,
   attach EV-yield-driven EV gain to the same recipient list (reusing
   B2's data) — this is the piece `docs/m18_5h_recon.md`'s own option (b)
   explicitly deferred here in full; closes that milestone's own open
   loop. Directly unblocks the Power-item/Macho-Brace family flagged in
   Section C.
4. **M20d — Level-up move learning**: per D2's resolution — likely a
   small, cheap addition once M20b's level-up loop exists to hook into.
5. **Not part of M20** (see Section C): move relearning flow, Rare Candy,
   Exp Share bag-item management, friendship mechanics, trainer-side
   leveling — each flagged for its own future milestone.

## Section F — Gen III EXP formula, verified against source (Step 0,
## report-only — design intent: Gen III formula shape, trainer-battle
## bonus deliberately removed as a conscious divergence)

Every component below is re-derived directly from `pokeemerald_expansion`
source, not from the web-research hypothesis that prompted this pass
(Serebii-style summaries). Differences from that hypothesis are called
out explicitly where they occur.

**Where the real formula lives** — split across three functions, not one:
- `Cmd_getexp` (`src/battle_script_commands.c`, starts line 3851):
  computes the pre-split `calculatedExp` total (base yield × level, the
  divisor choice, the trainer-battle bonus, and the participant-split
  divisor).
- `ApplyExperienceMultipliers` (`src/battle_script_commands.c:11173`):
  applies PER-RECIPIENT multipliers after the split — traded-mon bonus,
  Lucky Egg, evolution-delay bonus, Affection, Exp Charm, and (Gen5+/
  Gen7+ only) the level-difference scaling factor.
- `GetSoftLevelCapExpValue` (`src/caps.c:41`): a separate level-cap
  scaling step, called from `Cmd_getexp` case 2 before
  `ApplyExperienceMultipliers` runs. **Confirmed a pure no-op at this
  project's actual current config** — `B_EXP_CAP_TYPE` defaults to
  `EXP_CAP_NONE` (`include/config/caps.h:14`, independent of any
  `GEN_LATEST`/generation setting), and the function's own first line is
  `if (B_EXP_CAP_TYPE == EXP_CAP_NONE) return expValue;` — so a Gen III
  formula reconstruction under this project's real settings doesn't need
  to reproduce any level-cap scaling at all, confirmed rather than assumed.

**1-2. Base yield, level factor, and each component checked individually:**

- **Base experience yield** (`Cmd_getexp`, `battle_script_commands.c:3915`):
  `calculatedExp = gSpeciesInfo[gBattleMons[gBattlerFainted].species]
  .expYield * gBattleMons[gBattlerFainted].level;` — confirms `.expYield`
  is exactly the right per-species source field (matching this project's
  already-dormant `PokemonSpecies.exp_yield`, Section A), and the fainted
  mon's **level is a direct multiplicative factor** on the base yield, not
  a separate later step. Both parts of the web hypothesis check out.

- **Divisor** (`Cmd_getexp:3917-3920`):
  ```c
  if (B_SCALED_EXP >= GEN_5 && B_SCALED_EXP != GEN_6)
      calculatedExp /= 5;
  else
      calculatedExp /= 7;
  ```
  At a hypothetical `B_SCALED_EXP = GEN_3` config, `GEN_3 >= GEN_5` is
  false, so the **`/7` branch is live** — matching the classic Gen I-IV
  divisor from web research. Plain truncating integer division, no
  rounding adjustment at this stage.

- **Traded-mon "outside trainer" bonus** — found in
  `ApplyExperienceMultipliers:11177-11178`, NOT in `Cmd_getexp`:
  ```c
  if (IsTradedMon(&gParties[B_TRAINER_PLAYER][expGetterMonId]))
      *expAmount = (*expAmount * 150) / 100;
  ```
  Confirmed exactly **×150/100 (1.5×)**, matching the web-researched
  figure precisely — not an approximation. `IsTradedMon`
  (`src/pokemon.c:5479-5485`) delegates to `IsOtherTrainer`, which
  compares the mon's stored OT ID/name against the current save file's
  player identity — a straightforward "does this Pokémon's OT match the
  current player" check, no generation gate of any kind wraps it.
  **Confirmed this bonus is completely UNGATED by any `B_*` config** — it
  applies unconditionally in every generation this engine models,
  including whatever Gen III reconstruction this project builds. This
  matters directly for investigation item 3 (isolation) below.

- **Trainer-vs-wild bonus (the one being removed)** — found in
  `Cmd_getexp:3921-3922`, a structurally different location from the
  traded-mon bonus above:
  ```c
  if (B_TRAINER_EXP_MULTIPLIER <= GEN_7 && gBattleTypeFlags & BATTLE_TYPE_TRAINER)
      calculatedExp = (calculatedExp * 150) / 100;
  ```
  Also confirmed exactly **×150/100 (1.5×)** — the same numeric value as
  the traded-mon bonus, but a genuinely separate `if` block, checked
  against a separate condition (`BATTLE_TYPE_TRAINER`, not `IsTradedMon`),
  applied to the SHARED pre-split `calculatedExp` total rather than a
  per-recipient value. At a hypothetical `B_TRAINER_EXP_MULTIPLIER =
  GEN_3` config, `GEN_3 <= GEN_7` is true, confirming this bonus really
  was active in Gen III (consistent with the earlier session's finding
  that it's `GEN_7`+ specifically where source says it was dropped) —
  this is precisely, and only, the factor this design intends to cut.

- **Participant-split divisor (s)** (`Cmd_getexp:3882-3899, 3927-3944`):
  Two bitmasks are built by scanning the whole party once: `sentInBits`
  (which party slots were actually sent into this battle,
  `gSentPokesToOpponent`) and `expShareBits` (which slots hold
  `HOLD_EFFECT_EXP_SHARE` — the classic held item, `IsGen6ExpShareEnabled()`
  confirmed separately gated behind its own `I_EXP_SHARE_FLAG` toggle,
  `battle_util.c:9458-9464`, which defaults OFF and is irrelevant to a
  Gen III reconstruction). Then, gated on `B_SPLIT_EXP < GEN_6` (true at
  a hypothetical `GEN_3` setting):
  ```c
  if (viaExpShare) {
      *exp = SAFE_DIV(calculatedExp / 2, viaSentIn);
      if (*exp == 0) *exp = 1;
      gBattleStruct->expShareExpValue = calculatedExp / 2 / viaExpShare;
      if (gBattleStruct->expShareExpValue == 0) gBattleStruct->expShareExpValue = 1;
  } else {
      *exp = SAFE_DIV(calculatedExp, viaSentIn);
      if (*exp == 0) *exp = 1;
      gBattleStruct->expShareExpValue = 0;
  }
  ```
  Confirms the classic Gen I-V shape: if nobody holds the held-item Exp
  Share, the FULL `calculatedExp` splits evenly among however many party
  members were actually sent into battle (`viaSentIn`) — bench-only mons
  get nothing. If at least one mon holds Exp Share, `calculatedExp` is
  HALVED first, with one half split evenly among sent-in participants and
  the other half split evenly among Exp-Share holders (a holder that was
  ALSO sent in gets both shares, since the two groups aren't mutually
  exclusive in this loop). `SAFE_DIV` (`include/global.h:81`) is a
  divide-by-zero-guarded plain truncating division; each branch has its
  own explicit floor-to-1 safety net immediately after.

- **Level-difference scaling** — confirmed **ABSENT** from the Gen III
  path, exactly as the web research claimed (verified, not assumed): the
  scaling-factor lookup table lives entirely inside
  `ApplyExperienceMultipliers:11188-11198`, gated behind the SAME
  `B_SCALED_EXP >= GEN_5 && != GEN_6` condition that governs the `/5` vs
  `/7` divisor choice above. At a hypothetical `GEN_3` setting, that
  condition is false, so this whole block — including its lookup-table
  multiply/divide and its trailing `+1` — never executes. **A Gen III
  reconstruction must NOT include either the scaling factor or the `+1`
  constant; both are Gen5+/Gen7+-only**, confirmed by their shared gate
  rather than assumed from general "EXP formulas often add 1" folklore.

- **Rounding/floor behavior, Gen III path specifically**: every division
  in the live Gen III path (`/7`, `SAFE_DIV` splits, and each `(*x*150)/
  100` bonus multiply in `ApplyExperienceMultipliers`) is plain truncating
  integer division — no rounding, no add-1 anywhere. The only floor-to-1
  safety nets in the whole pipeline are the two explicit `if (*exp==0)
  *exp=1`-style checks immediately after the participant split; nothing
  downstream (the traded-mon/Lucky-Egg/Exp-Charm bonuses in
  `ApplyExperienceMultipliers`) has its own additional floor, since each
  ×1.5 of an already-≥1 value truncates to at least 1 regardless.

**3. Isolation of the trainer-bonus removal**: confirmed clean. The
trainer bonus is exactly one `if` block (`Cmd_getexp:3921-3922`) applied
to the shared pre-split total, with no other computation reading from or
depending on it — removing it means skipping that one check, nothing
else in `Cmd_getexp` changes shape. The traded-mon bonus lives in a
completely different function (`ApplyExperienceMultipliers`), applied
later, per-recipient, entangled only with 4 OTHER independent bonus
checks in that same function (Lucky Egg, evolution-delay ×4915/4096,
Affection, Exp Charm) — **never with the trainer bonus**. Cutting the
trainer bonus specifically, while keeping the traded-mon bonus, requires
touching exactly one line in one function and zero lines anywhere else.

**4. Cross-check against the exp_yield/EV-yield data-pipeline backfill**:
confirmed **separate data points**, not the same field — `.expYield` (one
scalar) and the 6 `.evYield_HP`/`.evYield_Attack`/`.evYield_Defense`/
`.evYield_SpAttack`/`.evYield_SpDefense`/`.evYield_Speed` fields are
distinct struct members, matching Section A's/B2's earlier finding
(`gen_1_families.h:17-19` shows `.expYield` and `.evYield_SpAttack` as
adjacent-but-separate members of the same species literal). They DO,
however, live in the exact same source struct literal per species (the
same `species_info/gen_N_families.h` files) — so a single 386-species
extraction pass could grab both `exp_yield` and all 6 `ev_yield_*` values
in one script run, an efficiency opportunity for M20a's data-pipeline
sub-tier, not a reason to treat them as one field.

**Summary of where source confirms vs. corrects the web-research
hypothesis**: confirms the `/7` divisor, the exact ×1.5 value for both
bonuses, the no-scaling-in-Gen-III claim, and the participant-split
shape. Adds precision the hypothesis didn't have: the traded-mon bonus is
generation-UNGATED in this engine (not itself a "Gen III mechanic" to
port — it's always-on), the two ×1.5 bonuses are structurally unrelated
(different functions, different scope — pre-split shared total vs.
post-split per-recipient), and the `+1`/scaling-factor block must be
excluded entirely rather than assumed absent. No implementation
performed — this section is verification only, per instruction.

## Section G — Step 0 addendum: multi-participant split detail, and Exp
## Share/Exp All feasibility review (report-only, no implementation)

### G1. Multi-participant split — full mechanics, source-cited

**Eligibility ("participated") is checked in TWO independent layers, not
one — both must pass:**

1. **`IsValidForBattle`** (`src/battle_controllers.c:391-397`):
   ```c
   return (species != SPECIES_NONE && species != SPECIES_EGG
        && GetMonData(mon, MON_DATA_HP) != 0
        && GetMonData(mon, MON_DATA_IS_EGG) == FALSE);
   ```
   Applied at the very top of `Cmd_getexp`'s party-scan loop
   (`battle_script_commands.c:3887-3888`, `if (!IsValidForBattle(...))
   continue;`) — **a party member currently at 0 HP is skipped entirely,
   before either the sent-in or Exp-Share bitmask is even consulted.**
   This directly answers the "does a mon that fainted earlier still
   count" question: **no** — eligibility is checked at the moment THIS
   opponent faints, not accumulated across the battle. A mon that fainted
   against an EARLIER opponent, or that fainted from its own recoil/
   Explosion in the very hit that KO'd this opponent, is excluded from
   both the divisor count and the recipient list for this specific award.
   (Note: `IsValidForBattleButDead`, `battlerControllers.c:400-405`, is
   the same check WITHOUT the HP condition — it exists in source but is
   NOT what `Cmd_getexp` uses for Exp eligibility, confirming the HP gate
   is a deliberate choice, not an oversight.)

2. **`gSentPokesToOpponent[flank]`** (a per-opponent-flank bitmask over
   the player's OWN party indices, `src/battle_main.c:207`,
   `include/battle.h:1029`): tracks which player party members have been
   ACTIVE against the CURRENT opponent occupying that flank, updated by
   `UpdateSentPokesToOpponentValue` (`battle_util.c:1224-1234`, called on
   every switch-in) and reset by `OpponentSwitchInResetSentPokesToOpponentValue`
   (`battle_util.c:1207-1222`, called specifically when a NEW opponent
   Pokémon switches in). **Key finding**: the tracking is PER-OPPONENT,
   not per-battle — the instant a new opponent Pokémon enters, its own
   flank's bitmask resets to just whichever player battler(s) are active
   at that exact moment; a player mon's OWN bit, once set, is never
   cleared except by that reset (fainting does not clear it — only
   `IsValidForBattle`'s live HP check, layer 1 above, can exclude an
   already-tracked mon). **This confirms merely being sent out/active
   against this specific opponent is sufficient — dealing damage is NOT
   required for eligibility.** A support-only Pokémon (e.g. one that only
   used Helping Hand) that was active when this opponent fainted counts
   identically to one that landed every hit.

**Doubles/2v1 worked mechanics**: with 2 player battlers simultaneously
active against 1 opponent, both party indices are set in that opponent's
`sentInBits` (assuming neither has since fainted, per layer 1), so
`viaSentIn = 2` in `Cmd_getexp`'s per-party scan (`:3887-3892`). The
divisor step (`:3927-3944`, `B_SPLIT_EXP < GEN_6` branch, live at a Gen
III setting) computes:
```c
*exp = SAFE_DIV(calculatedExp, viaSentIn);   // no Exp Share holder case
if (*exp == 0) *exp = 1;
```
**This division happens exactly ONCE**, producing a single shared
per-recipient base value (`gBattleStruct->expValue`) — it is NOT
recomputed independently for each recipient. Every eligible sent-in
recipient is then processed one at a time (`Cmd_getexp` case 2→3→4,
looping `*expMonId` through `gBattleStruct->expGettersOrder`,
`:3925-3926` for the ordering, `:3946-3952` for the per-recipient reward
assignment: `battlerExpReward = GetSoftLevelCapExpValue(recipientLevel,
gBattleStruct->expValue)` if `wasSentOut`), reusing that SAME shared base
value — **the even split really is "divide once, apply the same quotient
to everyone eligible," not "compute each recipient's cut independently."**

**Traded bonus timing — confirmed AFTER the split, per-recipient, not
applied to the shared pool beforehand.** The split (above) produces
`battlerExpReward` for a given recipient; `ApplyExperienceMultipliers`
(`:11173`, called at `:4005` from case 2, once per recipient) then
applies the traded-mon ×1.5, Lucky Egg, etc. to THAT recipient's own
already-split share. Two recipients who receive the identical
pre-bonus share can end up with different final Exp if only one is
traded — the bonus is layered on individually, not shared.

**Rounding for the multi-recipient case**: the shared division
(`SAFE_DIV`, plain truncating, floor-to-1 guarded) happens once, as
above. Each recipient's OWN bonus multiplication in
`ApplyExperienceMultipliers` (`(*expAmount * 150) / 100`-style, also
plain truncating integer division) is computed independently per
recipient, using that shared base value as its own starting point — so
"floored once at the split, then floored again independently per
recipient's own bonus multiply," not one single combined calculation.

**Concrete worked example** (wild battle, so the — already-being-removed
— trainer bonus never enters into it either way; deliberately chosen to
keep the example uncomplicated by that removal):

- Fainted wild Pokémon: `expYield = 71`, `level = 10`.
- `calculatedExp = 71 * 10 = 710`; Gen III divisor `/7` → `710 / 7 = 101`
  (integer truncation).
- No trainer-battle bonus applies (wild battle; also the factor being
  cut regardless).
- Two player Pokémon, A and B, both active this fight, neither fainted,
  neither holds Exp Share: `viaSentIn = 2`.
- Split: `SAFE_DIV(101, 2) = 50` (truncates `50.5` → `50`; not zero, no
  floor-to-1 needed). **Both A and B share this identical base value of
  50.**
- Level-cap scaling: a no-op at this project's actual `EXP_CAP_TYPE=NONE`
  config (Section F) — `battlerExpReward` stays `50` for both, unchanged.
- Per-recipient bonus (`ApplyExperienceMultipliers`): **A is traded** →
  `50 * 150 / 100 = 75`. **B is not traded** → no multiplier applies,
  stays `50`.
- **Final result: A gains 75 Exp, B gains 50 Exp** — despite an
  exactly-even 50/50 split of the shared pool, because the traded bonus
  is applied afterward, individually, only to the recipient who qualifies
  for it.

### G2. Exp Share / Exp All — feasibility-only pass, NOT implemented

> **⚠️ SUPERSEDED (2026-07-15, see Section I)**: the base-formula design
> has since moved from a Gen III target to a Gen VII+ scaled formula, and
> — separately, and more relevantly to this specific subsection — Rob's
> final non-participant distribution design is the **Gen VI+ "always-on,
> no item required" party-wide 20% mechanic**, NOT the classic held-item
> Exp Share this subsection investigated below. The held-item mechanic's
> feasibility findings below (double-dip behavior, additive-components
> shape, etc.) are preserved for historical reference and may still be
> useful if a future session ever wants the classic held-item variant
> alongside the automatic one, but **they are NOT the mechanism M20 will
> actually build**. See Section I's own dedicated note for the correct,
> current target (a flat 20%-to-every-bench-mon rule, no item, deferred
> to a future session) before acting on anything below.

**Which mechanic is actually relevant to a Gen III target**: the classic
per-mon HELD ITEM Exp. Share (`HOLD_EFFECT_EXP_SHARE`), not the older
Generation I "Exp. All" (a different, non-held-item mechanic that gave
the whole party a flat bonus regardless of participation — not what
Gen III's source branch models). Confirmed via the exact branch already
found in Section F: `Cmd_getexp`'s `B_SPLIT_EXP < GEN_6` code path
(`:3927-3944`), live at a Gen III setting, is precisely the classic
Gen II-V held-item Exp Share mechanic — half of `calculatedExp` splits
among sent-in participants, the other half splits among however many
party members hold the item (`viaExpShare`, counted in the SAME party
scan as `viaSentIn`, `:3887-3899`).

**A real, Gen III-specific finding relevant to feasibility**: a party
member that is BOTH sent-in AND holds Exp Share gets **BOTH shares
added together**, not just one — confirmed at `:3958-3963`:
```c
if (wasSentOut)
    battlerExpReward = GetSoftLevelCapExpValue(level, expValue);
else
    battlerExpReward = 0;

if ((holdEffect == HOLD_EFFECT_EXP_SHARE || IsGen6ExpShareEnabled())
    && (B_SPLIT_EXP < GEN_6 || battlerExpReward == 0))
    battlerExpReward += GetSoftLevelCapExpValue(level, expShareExpValue);
```
At a Gen III setting, `B_SPLIT_EXP < GEN_6` is unconditionally true, so
the second condition is always satisfied regardless of `wasSentOut` —
meaning **a Gen III sent-in Exp-Share holder "double-dips": its own
sent-in cut PLUS its Exp-Share cut, added.** (This differs from the
modern Gen6+ shape, where the `battlerExpReward == 0` half of that OR
only lets a mon claim the Exp-Share cut if it did NOT already get a
sent-in cut — avoiding double-dipping. That modern behavior is
irrelevant to a Gen III target but is worth knowing exists in the same
function, in case a later milestone ever wants the modern split instead.)

**What state/data this needs beyond what's already planned for core
dispatch**: 
- A held-item check (`ItemManager`-shaped — already a familiar pattern
  in this project, cheap on its own).
- Per-party-member tracking of TWO independent boolean facts
  simultaneously (sent-in this fight vs. holds-Exp-Share), not mutually
  exclusive, computed together in one pass over the whole party — not
  one flag that overrides the other.
- A recipient's total reward computed as the SUM of up to two components
  (sent-in share + Exp-Share cut), not a single flat scalar chosen from
  one of two mutually-exclusive paths.

**Feasibility/effort assessment — this is the one point requiring
attention BEFORE core dispatch starts, to avoid rework:** if M20b's core
dispatch is built assuming a single flat "this recipient's Exp is X"
value per party member — the natural, simplest reading of "split evenly
among sent-in participants" without also anticipating Exp Share — adding
Exp Share later would NOT bolt on cleanly. It would require restructuring
in two places: (1) the divisor-computation step, which in source
computes `viaSentIn` and `viaExpShare` together in one pass BEFORE any
per-recipient processing begins (not as a separate later step), and (2)
the per-recipient reward step, which needs to become an ADDITIVE
multi-component model (sent-in cut + Exp-Share cut, summed) rather than
a single resolved number.

**Recommendation** (not a decision made here — Rob's call): design core
dispatch's internal data model now with this shape in mind even though
Exp Share itself stays deferred — e.g., compute recipient eligibility as
a set of `{mon, components: []}` entries where `components` can hold more
than one contributing share, with only the "sent-in" component actually
populated this session. This costs nothing extra to build now (it's the
same data shape either way for the sent-in-only case) and avoids a
guaranteed rework once Exp Share is picked up later. This is a design
recommendation surfaced for M20b, not an instruction to build Exp Share
now — no Exp Share/Exp All code, data, or item-check was implemented in
this pass.

## Section H — Step 0 addendum #2: traded-bonus/summation order, and Exp
## All feasibility (report-only, no implementation)

### H1. Traded bonus vs. additive components — exact order, confirmed

**Source proves summation happens FIRST, and the traded multiplier is
applied exactly ONCE afterward, to the already-summed total** —
`battle_script_commands.c:3992-4005`:
```c
if (IsValidForBattle(&gParties[B_TRAINER_PLAYER][*expMonId]))
{
    if (wasSentOut)                                                      // 3994
        gBattleStruct->battlerExpReward = GetSoftLevelCapExpValue(       // 3995 — component 1 (sent-in)
            gParties[B_TRAINER_PLAYER][*expMonId].level, gBattleStruct->expValue);
    else
        gBattleStruct->battlerExpReward = 0;                              // 3997

    if ((holdEffect == HOLD_EFFECT_EXP_SHARE || IsGen6ExpShareEnabled())   // 3999
        && (B_SPLIT_EXP < GEN_6 || gBattleStruct->battlerExpReward == 0))  // 4000
    {
        gBattleStruct->battlerExpReward += GetSoftLevelCapExpValue(       // 4002 — component 2 ADDED here
            gParties[B_TRAINER_PLAYER][*expMonId].level, gBattleStruct->expShareExpValue);
    }

    ApplyExperienceMultipliers(&gBattleStruct->battlerExpReward,          // 4005 — called ONCE, on the sum
        *expMonId, gBattlerFainted);
```
Both components write into the SAME `battlerExpReward` variable, fully
merged by line 4003, BEFORE `ApplyExperienceMultipliers` is ever called
at line 4005 — there is only one call to that function per recipient, not
one per component. **Confirmed: the traded multiplier (and every other
bonus inside `ApplyExperienceMultipliers` — Lucky Egg, evolution-delay,
Affection, Exp Charm) applies to the recipient's fully-summed total, not
independently per component before summing.**

**Confirmed: "traded" is purely a property of the final recipient mon,
uniform regardless of which component(s) contributed.**
`ApplyExperienceMultipliers`'s own check (`:11177`,
`IsTradedMon(&gParties[B_TRAINER_PLAYER][expGetterMonId])`) reads the
recipient's own stored OT data — a single fact about that mon, checked
once, after the components are already irreversibly merged into one
scalar. There is no code path by which "traded" could vary per-component;
by the time the multiplier runs, the components no longer exist as
separate values.

**This is not merely a style choice — the two orders produce genuinely
different results under integer truncation**, confirmed with a concrete
divergent example (not one where they happen to coincide): suppose a
Gen-III double-dipping recipient (Section G's finding) has a sent-in
component of 1 and an Exp-Share component of 1.
- **Source's real order (sum, then multiply once)**: `1 + 1 = 2`, then
  `2 * 150 / 100 = 300 / 100 = 3`.
- **The alternative (multiply each component, then sum)**: `1 * 150 /
  100 = 150/100 = 1` (truncated) for each component, summed = `1 + 1 =
  2`.
- **These diverge: 3 vs. 2** — confirming the order is load-bearing, not
  interchangeable, and that M20b must apply any per-recipient multiplier
  (traded, and by extension any other future per-recipient bonus) at the
  SUMMATION step (after adding all of a recipient's components together),
  never at the individual-component step.

**Implication for M20b's data shape** (recommendation, not a decision
made here): if the additive-components model from Section G is adopted,
the traded (and any future per-recipient) multiplier belongs at the
"reduce components to one final total" step — apply it once, to the sum
— not threaded into each component's own computation.

### H2. Exp All feasibility — confirmed NOT a distinct mechanic in this
### source at all; recommend dropping it from scope entirely

**Direct, unambiguous source citation**: `include/constants/items.h:587-588`:
```c
ITEM_EXP_SHARE = 461,
ITEM_EXP_ALL = ITEM_EXP_SHARE, // Gen I name
```
**"Exp. All" is not a separate item, mechanic, or code path anywhere in
this reference source — it is a plain compile-time ALIAS for the exact
same `ITEM_EXP_SHARE` constant**, with a comment confirming this is
intentional: the item was called "Exp. All" in Generation I's own
in-game text, and "Exp. Share" from Generation II onward, but
`pokeemerald_expansion` models it as one single item/mechanic throughout,
not two. Confirmed via a full-source grep for any other
`EXP_ALL`/`ExpAll`/"Exp All"/"Exp. All" reference — none exist outside
this one alias line; there is no separate "splits/halves experience and
STAT experience across the whole party regardless of participation"
mechanic anywhere in this codebase, contradicting the web-research
hypothesis this addendum was checking against.

(The real Gen I "Exp. All" additionally affected the era's separate
"stat experience" sub-system, which predates and was fully replaced by
the modern EV system by Generation III — this project's own EV work is
already tracked separately in Section B2/M20c, using the modern EV model,
so even if a distinct Exp-All-vs-stat-exp mechanic had existed in source,
it would be moot for a Gen III EV-era target regardless.)

**Feasibility conclusion**: Exp All is **not in-scope-and-different** —
it is the exact same `HOLD_EFFECT_EXP_SHARE` mechanic already fully
investigated in Section G, under an alternate display name only.
**Recommend dropping "Exp All" entirely from any future "build later"
list** — there is nothing distinct to build; whatever M20 eventually
builds for Exp Share (per Section G's feasibility notes) already covers
100% of what "Exp All" would have meant for this project. No separate
data shape, item check, or dispatch logic is needed. Nothing was
implemented in this pass — this is a scope-reduction finding, not a
deferred build item.

## Section I — M20 EXP design, FINAL (2026-07-15): Gen VII+ base formula
## (source-verified), custom distribution table, deferred 20% mechanic,
## and Difficulty Setting

**This section supersedes the Gen III formula target from Sections F/G/H
for the base per-recipient value.** The multi-participant eligibility
rules (`IsValidForBattle`'s HP check, `gSentPokesToOpponent`'s
per-opponent tracking — Section G1) and the summation-before-multiplier
finding (Section H1) are UNCHANGED and still apply exactly as documented
— only the base-value FORMULA and the distribution-on-top mechanism have
changed. Four pieces, in order of application:

### I.1 — Base per-recipient value (Gen VII+ canonical formula, source-verified)

Confirmed live in the SAME `B_SCALED_EXP`-gated code this project's
GEN_9 config already activates (Section F/H) — `Cmd_getexp`
(`battle_script_commands.c:3915-3920`, the `/5` divisor) plus
`ApplyExperienceMultipliers` (`:11173-11198`, the per-recipient
level-scaling block). Re-verified every step precisely:

- **B (base, before A/C scaling)**: `calculatedExp = expYield *
  faintedLevel`, then `/5` (confirmed live: `B_SCALED_EXP >= GEN_5 &&
  != GEN_6`, true at `GEN_9`). Trainer-battle bonus confirmed OFF
  already (no re-verification needed, per instruction).

- **A and C — a critical correction to the drafted formula**: the
  design draft's `floor(sqrt(A) * A^2)` / `floor(sqrt(C) * C^2)` is
  **not quite what source computes**. Source uses a fully precomputed,
  211-entry static integer lookup table (`sExperienceScalingFactors[]`,
  `battle_script_commands.c:100-311`, covering indices 0-210 — exactly
  enough for every `level+level+10` combination up to `MAX_LEVEL=100`
  twice over), with its own source comment stating the exact generating
  formula: `// this returns (i^2.5)/4`. **Verified this comment
  against the literal array values, not trusted at face value**:
  `table[11] = 100`, and `floor(11^2.5 / 4) = floor(401.31/4) =
  floor(100.33) = 100` ✓; `table[20] = 447`, and `floor(20^2.5/4) =
  floor(1788.85/4) = floor(447.21) = 447` ✓. **Confirmed: the real
  per-index formula is `floor(i^2 * sqrt(i) / 4)`, NOT `floor(sqrt(i) *
  i^2)` as drafted** — the `/4` is real and material, not a
  cancel-out-able constant: e.g. at `i=2`, `floor(sqrt(2)*2^2) =
  floor(5.657) = 5`, but the ACTUAL table value is `table[2] = 1`
  (`floor(5.657/4) = floor(1.414) = 1`) — a large discrepancy at low
  indices. **This project must reproduce the exact table (or the exact
  `floor(i^2*sqrt(i)/4)` generating formula), not the `/4`-omitted
  formula from the draft, or results will diverge from source —
  confirmed via direct numeric check, not assumed equivalent.**
  Recommend **porting the literal 211-entry table verbatim** (matching
  this project's existing precedent of porting exact curve/lookup
  tables rather than recomputing them, e.g. `exp_curves.json`) rather
  than computing `sqrt()` at runtime — this guarantees bit-identical
  results and avoids any floating-point/precision risk a live `sqrt()`
  call could introduce.
  - `A = (OpponentLevel * 2) + 10` → table index for the numerator,
    confirmed exact match to source's `(faintedLevel * 2) + 10`
    (`:11195`).
  - `C = (OpponentLevel + RecipientLevel + 10)` → table index for the
    denominator, confirmed exact match to source's `faintedLevel +
    expGetterLevel + 10` (`:11196`) — `expGetterLevel` is fetched via
    `GetMonData(..., MON_DATA_LEVEL)` for the CURRENT recipient being
    processed, confirming **C uses each recipient's own level, computed
    fresh per recipient** (directly answers investigation item 4 below).
  - Runtime arithmetic is **plain integer** throughout — no float, no
    live `sqrt()` call anywhere in the runtime path (`u64 value` used
    only to avoid overflow on the intermediate multiply, per source's
    own comment at `:11189-11190`). `value *= table[A]; value /=
    table[C]; value = value + 1;` — one multiply, one truncating
    divide, one `+1` — confirming the outer nested-floor STRUCTURE from
    the draft is right (compute B fully first, including its own
    modifiers, THEN multiply/divide/floor/+1 against the A/C table
    values) even though the A/C table VALUES themselves needed the `/4`
    correction above.

- **B's modifiers — confirmed against this project's actual code, not
  assumed**: checked `item_manager.gd` and every `BattlePokemon`/
  `PokemonSpecies` field for each of the 4 modifiers named in the
  design draft, plus one more found only by reading source in full:
  - **Lucky Egg** (`HOLD_EFFECT_LUCKY_EGG`, confirmed a real source
    hold-effect constant): **NOT implemented anywhere in this
    project** — zero references in `item_manager.gd`. Omit from B for
    now.
  - **Traded/"Outsider" bonus** (`IsTradedMon`): **NOT implementable at
    all yet** — this project has no trade system, no OT (original
    trainer) tracking on `BattlePokemon` whatsoever (confirmed via
    grep — no `is_traded`/`original_trainer`/`OT` field exists). Omit
    from B for now; this needs its own future infrastructure (likely
    tied to a future trade/link-battle milestone, not M20) before it
    could ever be built, not just a missing data flag.
  - **Affection bonus** (`B_AFFECTION_MECHANICS`, confirmed **`TRUE`
    unconditionally** in source, `include/config/battle.h:354` — NOT
    gated behind `GEN_LATEST` the way most other `B_*` flags are, an
    always-on Gen6+ mechanic in this reference engine): **NOT
    implemented anywhere in this project** — zero "affection"/"heart"
    concept exists. Omit from B for now.
  - **Exp Charm** (`CheckBagHasItem(ITEM_EXP_CHARM)`, confirmed a real
    item constant, `include/constants/items.h:844`): a BAG item, not a
    held item — **NOT implemented**, and out of scope for a held-item-
    shaped `ItemManager` check anyway (would need bag-inventory
    infrastructure, `docs/m25_bag_items_recon.md` territory). Omit from
    B for now.
  - **A 5th modifier found that was NOT in the design draft's own
    list**: `B_UNEVOLVED_EXP_MULTIPLIER` (`×4915/4096 ≈ ×1.2003`, for a
    Pokémon at or past its evolution level that hasn't evolved yet,
    confirmed `>= GEN_6` live at this project's `GEN_9` config,
    `battle.h:18`) — gated on `IsMonPastEvolutionLevel`, needing
    evolution-level data this project's own M26 (Evolution) milestone
    will own, not M20. **Flagged explicitly rather than silently
    added or dropped** — recommend omitting from M20's B for the same
    reason as the other four (not yet implementable), but noting it
    exists in source and wasn't part of the original 4-item list, so a
    future session revisiting B's modifiers has the full real
    picture, not just the 4 originally named.
  - **Net effect for M20's actual implementation**: **B = `expYield *
    faintedLevel / 5`, with ZERO modifiers applied** — all 5 real
    source modifiers are confirmed unbuilt/unbuildable in this project
    today and are cleanly omitted, not blocking anything.

### I.2 — Custom participant distribution table (FINAL, in scope now, no source verification needed — original design)

Applied to each recipient's own fully-independently-computed base value
(I.1) once the number of PARTICIPANTS (mons meeting Section G1's
eligibility rules — `IsValidForBattle` + `gSentPokesToOpponent`,
unchanged) is known:

| Participants | Each keeps |
|---|---|
| 1 | 100% |
| 2 | 65% |
| 3 | 55% |
| 4 | 50% |
| 5 | 45% |
| 6 | 40% |

Confirmed via I.4/H1's own logic that this percentage is a THIRD
multiplicative step layered on top of I.1's base value — computed per
recipient, using that recipient's own I.1 result, not a shared pool.
This is original design, explicitly not checked against source per
instruction.

### I.3 — Non-participant 20% mechanic — DEFERRED, NOT built this
### session, flagged for a future session (matching the Perish Body
### precedent)

**Design, locked in for whenever this is picked up**: every benched
party member (any valid, non-fainted mon NOT counted as a participant
per Section G1's eligibility rules) automatically receives **20%** of
whatever value would apply — **no held item required, no bag item
required.** This is explicitly the **Gen VI+ "always-on" style
mechanic** (the real games' modern behavior once Exp Share became a key
item/toggle rather than a held item) — **NOT** the classic Gen II-V
held-item Exp Share mechanic Section G's own feasibility pass
investigated (that subsection's held-item findings are retained for
reference only, per the correction note added there, but are NOT what
gets built when this is eventually picked up).

**Explicitly out of scope for this session.** Nothing here should be
implemented now. When a future session builds this: the exact figure
(**20%**) and the "automatic, no item, Gen VI+ style" characterization
must both be preserved from this entry, not re-derived or assumed —
this note IS the spec for that future work, the same role this file's
`docs/m17-5_recon.md`-adjacent conventions and the Perish Body exclusion
note play elsewhere in this project. See also the corresponding
`docs/decisions.md` entry and CLAUDE.md's own M20 status line, both
updated to reference this deferred item so it isn't lost.

### I.4 — Difficulty Setting (FINAL, in scope now, custom design — no
### source equivalent)

Applied as the LAST multiplicative step, after I.1 (base) and I.2
(distribution %) have both already been applied to a recipient's value:

| Mode | Multiplier |
|---|---|
| NORMAL | ×1.0 |
| HARD | ×0.5 |
| CASUAL | ×1.35 |

**A single mutually-exclusive enum**, not independent boolean flags —
confirmed this matches an existing, real convention already used in
this exact file: `BattleManager` already declares a genuine Godot
`enum BattlePhase { ... }` block (`battle_manager.gd:18`) for its own
mutually-exclusive state. Recommend the identical shape: `enum
DifficultyMode { NORMAL, HARD, CASUAL }`.

**Storage location — confirmed by checking this project's existing
structures, not assumed**: this project has **no persistent
save/game-state layer of any kind yet** (save/load is a far-future
milestone, M32, per the roadmap) — there is no existing "global
settings"/autoload singleton this could naturally live on. The closest
existing precedent for "a single piece of per-battle configuration
state, not itself derived from any Pokémon or move" is `BattleManager`'s
own `weather`/`weather_duration` fields (`battle_manager.gd:402-403`) —
plain `var` fields directly on the manager instance. **Recommend a new
`var difficulty_mode: int = DifficultyMode.NORMAL` field directly on
`BattleManager`**, mirroring `weather`'s exact shape, as the only
currently-available option given this project's real current
architecture. **Flagged explicitly**: this is a per-`BattleManager`-
instance field for now, not truly persistent game state — a future
session (once M32's real save-data model exists) will likely need to
migrate this field's ownership from `BattleManager` itself to whatever
persistent structure M32 introduces, the same way `forced_nature`/
`forced_ivs` were built anticipating M24's future consumption. This is a
scope note for that future migration, not a blocker for building it now.

### Summary of what's authorized vs. deferred

- **I.1 (base formula) and I.2 (distribution table) and I.4 (difficulty
  enum)**: source-verified/designed and ready — **implementation
  authorization still pending explicit sign-off per this Step 0's own
  instruction**, not yet built as of this entry.
- **I.3 (20% non-participant mechanic)**: explicitly deferred to a
  future session, NOT to be built now under any circumstance in this
  pass.
- No code was written in this pass — Step 0 verification and design
  documentation only, per instruction.

### ✅ IMPLEMENTED (2026-07-15) — see `docs/decisions.md`'s `[M20 EXP
### implementation]` entry for the full build writeup

I.1, I.2, and I.4 are now **COMPLETE**: `BattleManager.EXP_SCALING_
FACTORS` (the literal 211-entry table), `_compute_exp_award` (B → A/C
table ratio+1 → distribution% → difficulty%, in that exact order),
new participant-tracking infrastructure (`_exp_participants`,
`_reset_exp_participants_for_opponent_slot`, `_add_exp_participant`,
wired into all 4 switch-in call sites + battle start) reproducing
Section G1's two-layer eligibility rule exactly, and
`_award_exp_for_fainted_opponent` wired after all 14
`pokemon_fainted.emit(...)` sites. New `BattlePokemon.current_exp`
(pure accumulator — no level-up trigger yet, that's still B5/B6, out
of scope) and `BattleManager.difficulty_mode` (`enum DifficultyMode`,
stored per-`BattleManager`-instance pending M32's future save layer).

**I.3 remains explicitly deferred**, unchanged from this section's own
spec above — not built, not scheduled.

**Deliberately NOT done this session**: the 386-species `exp_yield`
data-pipeline backfill (this recon's own proposed M20a). The mechanism
reads `species.exp_yield` directly (a real field either way); nothing
in this project's current architecture converts `pokemon.json` rows
into real `PokemonSpecies` instances at runtime yet, so the backfill
has zero effect on anything built or tested this session. Still open,
still a separate future item — matching this recon's own original
M20a/M20b split.

New `scenes/battle/m20_exp_test.gd`/`.tscn`: 34/34 assertions. Full
regression: `scripts/count_assertions.sh` run twice, both clean (122
files; 12726 and 12725 respectively, each differing from the clean
12727 baseline — 12693 prior + 34 new — only by already-documented
pre-existing flaky suites rotating between runs, zero failures
traceable to this session's own changes).
