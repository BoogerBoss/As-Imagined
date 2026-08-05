# M35 Recon — Battle Tower, Battle Factory, and the rest of the Battle Frontier

Scoping/recon session only — **no implementation this session, no code or
test changes**. This is the dedicated recon session `docs/m24_recon.md` §6.3
flagged as needed before any Battle-Frontier-facility work: "Trainer Pools/
full AI-flag engine/facility trainers/rematch progression were always
correctly out of scope [for M24], deferred to M35 per `docs/m24_recon.md`
§6.3." This doc is that deferred recon, for the facility-trainer/battle-
format half of that deferral specifically — not Trainer Pools (already
resolved, excluded, `docs/m24_recon.md` §6.1) and not the full AI-flag
engine (already resolved, narrow-extension-now/full-engine-later,
`docs/m24_recon.md` §6.2, §2).

Four parallel research passes covered: **(1)** shared Battle Frontier
infrastructure, **(2)** Battle Tower + Battle Dome, **(3)** Battle Factory +
Battle Palace, **(4)** Battle Pike + Battle Pyramid + Battle Arena. Every
finding below is re-derived directly from
`/home/rob/GodotAsImagined/reference/pokeemerald_expansion` source, per this
project's standing Step 0 discipline — not assumed from memory of "how the
Battle Frontier works." Several premises this recon started from turned out
to be **wrong**, corrected in place below rather than silently absorbed —
see §2.5 (Battle Pike's "lucky room" doesn't exist) and §2.7 (Battle Arena's
"mind points hit zero" framing is backwards).

---

## 1. Shared Battle Frontier infrastructure

This is the machinery every facility sits on top of. Getting this right
once means every per-facility section in §2 is mostly "which of this
project's existing engine pieces does this facility's own battle format
touch," not "build a new economy from scratch" per facility.

### 1.1 Battle Points (BP) economy

Storage: `battlePoints` (u16, capped `MAX_BATTLE_FRONTIER_POINTS = 9999`,
`include/constants/battle_frontier.h:51`) and a separate lifetime/daily
`cardBattlePoints` (u16) — both in `struct BattleFrontier`,
`include/global.h:528-529`.

**Earning** — `GiveBattlePoints()`, `src/frontier_util.c:1949-2006`:
```
challengeNum = streak / FRONTIER_STAGES_PER_CHALLENGE   // battles-per-set for most facilities;
                                                          // NUM_PIKE_ROOMS for Pike; raw tournament count for Dome
points = sBattlePointAwards[facility][battleMode][challengeNum]   // 30-entry hand-tuned table, src/frontier_util.c:662-699
if opponent == TRAINER_FRONTIER_BRAIN: points += 10
battlePoints = min(battlePoints + points, 9999)
```

**Spending**: no unified "BP price" field on items anywhere — every
purchasable thing is wired via per-item map-script calls at the Exchange
Service Corner (`data/maps/BattleFrontier_ExchangeServiceCorner/scripts.inc`,
`setitemandprice ITEM, price` macro), split across 4 fixed clerk pools
defined in `src/data/battle_frontier/battle_frontier_exchange_corner.h`:
decor pool 1 (cheap dolls/posters), decor pool 2 (starter/legendary dolls,
pricier), vitamins, held items (Leftovers/White Herb/Quick Claw/Mental Herb/
Bright Powder/Choice Band/King's Rock/Focus Band/Scope Lens). Deduction:
`TakeFrontierBattlePoints` (`src/field_specials.c:3060-3066`), floors at 0.

Note: `BattleFrontier_Mart` is an ordinary money-based Poké Mart (Ultra
Balls, Hyper Potions) — **not** BP-based. Don't conflate the two shops.

**Port cost: low.** Simple capped-add/floored-subtract integer counter plus
a static lookup table. The one real gap: "price" isn't data on the item
definitions themselves, it's baked into per-item script call sites — a port
needs its own explicit item→BP-price table rather than finding one ready-
made table to lift wholesale.

### 1.2 Frontier symbols (Silver/Gold) — real thresholds, verified not assumed

`gFrontierBrainInfo[NUM_FRONTIER_FACILITIES]`, `src/frontier_util.c:107-257`.
Each facility's `streakAppearances[4] = {silver, gold, goldRepeatEvery, offset}`:

| Facility | Silver | Gold | Repeat after Gold | Offset |
|---|---|---|---|---|
| Tower | 35 | 70 | 35 | 1 |
| Dome | 4 | 9 | 5 | 0 |
| Palace | 21 | 42 | 21 | 1 |
| Arena | 28 | 56 | 28 | 1 |
| Factory | 21 | 42 | 21 | 1 |
| Pike | 28 | 140 | 56 | 1 |
| Pyramid | 21 | 70 | 35 | 0 |

(These match the well-documented real Emerald numbers — the reference
hasn't rebalanced them.) `GetFrontierBrainStatus()`
(`src/frontier_util.c:1742-1780`) only fires in `FRONTIER_MODE_SINGLES`;
computes `winStreak = currentStreak + offset` then checks against silver/
gold/repeat thresholds in that order.

**Save data**: symbols are ordinary event flags
(`FLAG_SYS_TOWER_SILVER + facility*2` / `..._GOLD + facility*2`,
`src/frontier_util.c:1943-1947, 2014-2021`), **not** a dedicated struct
field — "has symbol" is queried the same way any other one-off story flag
is, not iterated as an array.

**Port cost: low.** Clean, already-parameterized data — a 4-int array per
facility plus the same formula ports directly.

### 1.3 Streak tracking / challenge structure / the anti-savescum mechanism

`FRONTIER_STAGES_PER_CHALLENGE = 7` (`include/constants/battle_frontier.h:60`)
— confirmed 7 battles per challenge/set for Tower, Palace, Arena, Factory,
Pyramid (floors, in Pyramid's case). **Dome** uses its own bracket-round
count instead (not a flat 7 — see §2.2). **Pike** uses `NUM_PIKE_ROOMS`
(rooms, not battles — Pike is a branching-room gauntlet, not straight
battles; see §2.5).

Per-facility fields live in `struct BattleFrontier`
(`include/global.h:455-540`), all u16 capped at `MAX_STREAK = 9999`:
`towerWinStreaks[4][2]`+record, `domeWinStreaks[2][2]`+record+
`domeTotalChampionships`, `palaceWinStreaks[2][2]`+record,
`arenaWinStreaks[2]`+record (no doubles), `factoryWinStreaks[2][2]`+record+
`factoryRentsCount`, `pikeWinStreaks[2]`+record+`pikeTotalStreaks`,
`pyramidWinStreaks[2]`+record. Plus `curChallengeBattleNum`,
`challengeStatus` (`SAVING`/`PAUSED`/`WON`/`LOST`), and
`trainerIds[20]` — the whole challenge's opponent roster pre-rolled up
front, reset via `ResetFrontierTrainerIds()`.

**Loss behavior — the subtle, easy-to-under-replicate part.** The current
streak is **not** reset the instant you lose. There's a
`winStreakActiveFlags` bitfield (`include/global.h:471`, one bit per
facility/mode/level combo) that's set `TRUE` when a challenge *begins*
(lobby scripts) and cleared `FALSE` only when a challenge *concludes
normally* — quitting without saving, or a genuine loss
(`BattleFrontier_BattleTowerLobby_EventScript_LostChallenge` etc.). At
challenge start, the streak is zeroed **only if this bit is not already
set** (`if (!(winStreakActiveFlags & flag)) towerWinStreaks[...] = 0;`,
`src/battle_tower.c:718-719`, same pattern in `battle_palace.c:93-94`,
`battle_dome.c:1770-1771`). Net effect: a mid-challenge crash/soft-reset
does NOT wipe your streak on Continue, because the active bit is still set
— this is a deliberate anti-savescum measure, not incidental behavior. The
only place `ResetWinStreaks()` runs unconditionally is corrupted-save
recovery (`CB2_ContinueSavedGame` when `gSaveFileStatus == SAVE_STATUS_ERROR`,
`src/overworld.c:2099-2100`) — a punitive wipe-everything path, not normal
loss handling.

**Port cost: medium.** The anti-savescum active-flag mechanism is real
design intent, easy to silently drop if only the increment/reset-on-loss
happy path is read. If the fangame's save architecture doesn't have the
same soft-reset exploit vector (single save slot, no cartridge-reset
trick), simplifying to "reset streak immediately on loss" is a legitimate,
disclosed simplification — but it should be a deliberate call, not an
oversight.

### 1.4 Difficulty/level modes — LV50 vs Open Level

`enum FrontierLevelMode { FRONTIER_LVL_50, FRONTIER_LVL_OPEN, FRONTIER_LVL_TENT }`
— only 2 real Frontier modes; `_TENT` is a sentinel for the unrelated
Battle Tent minigames reusing the same code paths (see §4).
`FRONTIER_MAX_LEVEL_50 = 50`, `FRONTIER_MIN_LEVEL_OPEN = 60`,
`FRONTIER_MAX_LEVEL_OPEN = 100` (`include/constants/battle_frontier.h:54-56`).

**Opponent level** (`GetFrontierEnemyMonLevel`,
`src/frontier_util.c:3270-3288`): LV50 mode → flat 50. Open Level → the
**player's own highest party level** (`GetHighestLevelInPlayerParty`,
`:3290-3307`), floored at 60 — i.e. Open Level opponents dynamically scale
to your best Pokémon, not fixed at 100.

**Player-side enforcement is eligibility filtering, NOT re-leveling.**
`CheckPartyIneligibility`/`AppendIfValid`
(`src/frontier_util.c:2046-2200`) simply excludes any candidate mon
`level > 50` from the selection list when in LV50 mode — the game never
deletes your Pokémon's levels, it just refuses entry if too few eligible
mons remain. Confirmed by grepping every other `FRONTIER_LVL_50` check
across `battle_factory.c`/`battle_arena.c`/`battle_pike.c`/
`battle_pyramid.c`/`battle_dome.c`: every one of them governs the
*opponent's* rental-level/species-tier selection, never the player's own
party stats.

**Port cost: low.** Easy to over-engineer by assuming a stat-recalculation-
at-reduced-level system exists — it doesn't. It's a simple "can't enter
with mons over X level" gate plus an enemy-level-scaling formula.

### 1.5 Opponent trainer generation — a separate Frontier trainer pool, distinct from the main 855-trainer roster

Three-layer data model, entirely apart from `trainers.party`
(`docs/m24_recon.md`'s own pipeline):

1. **Trainer identity table**: `gBattleFrontierTrainers[300]`
   (`src/data/battle_frontier/battle_frontier_trainers.h`,
   `FRONTIER_TRAINERS_COUNT = 300`). Struct
   (`include/battle_frontier.h:7-16`): facility class, name, Easy-Chat
   pre-battle/win/lose speech (word IDs, not free text), and a pointer to a
   mon-set.
2. **Named mon-set groups**: `src/data/battle_frontier/battle_frontier_trainer_mons.h`
   — `#define`d lists of `FRONTIER_MON_*` indices, shared across multiple
   trainer-class instances (e.g. "also used by early PKMN Breeder,
   Collector, and Beauty").
3. **The actual mon pool**: `gBattleFrontierMons[882]`
   (`src/data/battle_frontier/battle_frontier_mons.h`,
   `NUM_FRONTIER_MONS = 882`). Each entry **reuses the exact same
   `struct TrainerMon` type** ordinary overworld trainers use (per
   `docs/m24_recon.md` §1.1) — species + 4 fixed moves + item + EVs +
   nature + ball, no bespoke data shape here. Split at
   `FRONTIER_MONS_HIGH_TIER = 849`: species above that index (Dragonite,
   Tyranitar, legendary birds/beasts) are **Open-Level-only**, enforced in
   the roll loop (`src/battle_frontier.c:266`).

**Party assembly** (`FillTrainerParty`, `src/battle_frontier.c:202-307`):
random-rolls from the mon-set until party size is reached, rejecting
duplicate species and duplicate held items within one party.
`CreateFacilityMon` (`:309-395`) builds the actual runtime Pokémon —
gender-consistent personality, fixed nature, fixed IV (below), the 4 fixed
moves (with a Return↔Frustration friendship-move swap gimmick),
ability-by-name lookup, EVs, then stat calc.

**Fixed IV scaling by trainer-ID tier**
(`GetFrontierTrainerFixedIvs`, `src/frontier_util.c:2792-2812`): IDs 0-99 →
IV 3, 100-119 → 6, 120-139 → 9, … 220+ → 31 (max).

**Streak-scaled trainer identity**:
`GetRandomScaledFrontierTrainerId(challengeNum, battleNum)`
(`src/frontier_util.c:2817-2843`) indexes two parallel trainer-ID-range
tables keyed by `challengeNum` (0-7+) — a normal-battle table and a harder
sub-range table used specifically for the **last battle of each 7-battle
set** (a deliberate difficulty spike at the end of each set). Past
`challengeNum > 7`, both lock to their hardest range permanently.

Since trainer ID directly determines both the fixed-IV tier above *and*
which facility-class/mon-set that trainer draws from, **trainer ID is the
single knob driving most Frontier difficulty scaling** — species/movepool
tier is a second, independent axis gated by level mode (some
legendary-tier species locked to Open Level regardless of streak).

**Port cost: medium.** The three-layer indirection (trainer → named
mon-set macro → mon-pool index) is C-preprocessor convenience, not an
inherent requirement — a flattened "trainer → list of species+moveset
entries" table in this project's own data pipeline is simpler than the
source, not harder. The one thing worth deliberately preserving: the
**two-axis difficulty model** (trainer-ID tier → fixed IV + end-of-set
spike; level mode → species-tier gate). Losing either axis silently
flattens the intended difficulty curve.

### 1.6 AI flags for Frontier battles

Central dispatch, `GetAiFlags()` (`src/battle_ai_main.c:253-291`):

```c
else if (BATTLE_TYPE_FACTORY)
    flags = GetAiScriptsInBattleFactory();   // see below — the one facility with real scaling
else if (BATTLE_TYPE_FRONTIER | EREADER_TRAINER | TRAINER_HILL | SECRET_BASE)
    flags = AI_FLAG_CHECK_BAD_MOVE | AI_FLAG_CHECK_VIABILITY | AI_FLAG_TRY_TO_FAINT;
else
    flags = GetTrainerAIFlagsFromId(trainerId);   // ordinary trainer.party AI: line, per docs/m24_recon.md §2
```

**Every non-Factory Frontier trainer gets one fixed, non-scaling AI flag
set regardless of streak** — no per-facility/per-streak AI escalation
outside Factory. (`AI_FLAG_DOUBLE_BATTLE` additionally OR'd in for doubles.)

**Battle Factory is the sole exception**, streak-ramped
(`GetAiScriptsInBattleFactory`, `src/battle_factory.c:773-795`):
`challengeNum < 2` → no smart AI at all (0); `< 4` → `CHECK_BAD_MOVE` only;
else → the full `CHECK_BAD_MOVE | TRY_TO_FAINT | CHECK_VIABILITY` set (also
always-full against the Frontier Brain regardless of challenge number).

`BattleAI_SetupItems` (`src/battle_ai_main.c:193-221`) explicitly
**excludes held-item AI reasoning for Frontier battles** — Frontier
opponents' items are never registered into `gBattleHistory->trainerItems`,
so Frontier AI never reasons about "the opponent could have item X" the
way an ordinary trainer battle's AI does (plausibly because rental/facility
mons already have hand-picked items rather than trainer-class-based item
pools).

**Port cost: low.** One `if/else` chain this project's existing AI-tier
system (per `docs/m24_recon.md` §2/§6.2 — a narrow BASIC/SMART extension
already covering the real 855-trainer roster) can trivially fold in:
map "Frontier, non-Factory" to whichever tier corresponds to that fixed
3-flag set, give Factory its own bespoke 3-step streak ramp.

### 1.7 Shared file inventory

| File | Role |
|---|---|
| `include/frontier_util.h` / `src/frontier_util.c` (3439 lines) | Public API + the bulk of shared logic: BP, symbols, streak get/set/increment, per-facility results text, ranking hall, Frontier Brain data/roster, trainer name/class/gfx/level/fixed-IV lookups, party-eligibility filtering, banned-species UI. |
| `include/constants/frontier_util.h` | Dispatch IDs for the `frontier_...` script commands, `FRONTIER_DATA_*` field IDs, brain-status enum, `STREAK_*` active-flag bitmask constants. |
| `include/constants/battle_frontier.h` | Facility IDs, battle-mode IDs, challenge-status IDs, party-size/level/streak-cap constants — **plus 3 separate, inconsistent facility-numbering schemes**, see below. |
| `include/constants/battle_frontier_mons.h` / `include/constants/battle_frontier_trainers.h` | The 882 mon-loadout indices / 300 trainer-name constants. |
| `include/battle_frontier.h` | `struct BattleFrontierTrainer`, extern table declarations, `FillFrontierTrainerParty(ies)`/`CreateFacilityMon` prototypes. |
| `src/battle_frontier.c` (395 lines) | Per-facility battle-launch glue, `FillTrainerParty`, `CreateFacilityMon`. |
| `src/data/battle_frontier/battle_frontier_{trainers,trainer_mons,mons}.h` | The 3-layer trainer-pool data (§1.5). |
| `src/data/battle_frontier/battle_frontier_exchange_corner.h` | The 4 BP-shop item pools. |
| `src/data/battle_frontier/apprentice.h` (621 lines) | Apprentice data tables — §1.8. |
| `src/data/battle_frontier/trainer_hill.h` (4821 lines) | **Trainer Hill** — a related-but-distinct facility, flagged not investigated (§4). |
| `src/data/battle_frontier/battle_tent.h` (3165 lines) | **Battle Tent** minigames (Verdanturf/Fallarbor/Slateport) — reuse `FRONTIER_LVL_TENT` and share code paths, flagged not investigated (§4). |
| `src/data/battle_frontier/battle_pyramid_*_wild_mons.h` | Pyramid-specific wild encounter tables — see §2.6. |

**Facility-ID inconsistency, flagged for the port**: `battle_frontier.h`
itself has **3 different facility-numbering schemes** —
`FRONTIER_FACILITY_*` (0-6, most lookups), `RANKING_HALL_*` (0-9, splits
Tower into singles/doubles/multis/link and reorders), `FRONTIER_MANIAC_*`
(0-9, yet another order). The header's own comment admits this is
redundant. Recommend picking **one** canonical enum for the port and
writing 2-3 explicit remap tables at the couple of places that genuinely
need an alternate ordering (ranking-hall display, an NPC's dialogue
selection), rather than trying to unify the source's own inconsistency.

### 1.8 Interview / Apprentice system

Confirmed present, in the Tower lobby, with a self-documenting comment
block at `src/apprentice.c:32-58`:

- **Identity pool**: `gApprentices[]` (`include/apprentice.h:6-16`) — name,
  OT ID, facility class, up to 10 possible species, a fixed loss-speech.
  Data in `src/data/battle_frontier/apprentice.h`.
- **Question flow** (`CallApprenticeFunction` dispatch,
  `include/constants/apprentice.h:15-40`): always "will you teach me?" →
  "Lv50 or Open?" → 3× "which of 2 mons?" (species shuffled and packed 2-
  per-slot into a nibble-packed byte array) → 1-8 further randomized
  questions (lead-mon choice, move choice ×5 max, held-item choice ×3 max,
  always ending on "what should I say when I win?"). A threshold table
  (`sApprenticeChallengeThreshold`, `src/battle_tower.c:667-670`) governs
  at which challenge-count an old Apprentice becomes battleable, scaled by
  how many questions it answered.
- Up to **4 old Apprentices retained** as future opponents (or Multi-mode
  partners), keyed to the level mode they were taught for; storage is a
  packed-bitfield `struct PlayersApprentice` (current) plus a
  `struct Apprentice apprentices[4]` array (retained, checksummed) in
  SaveBlock2.
- **Distinct from the separate "Battle Tower Interview" feature** — a
  lighter post-battle-blurb snapshot (`struct BattleTowerInterview`,
  `SetTowerInterviewData`) shown by a reporter NPC. Don't conflate the two
  when scoping.
- Also record-mixed (§1.9) — up to 2 Apprentices can arrive from another
  player's save via wireless exchange.

**Port cost: medium-high — but not for algorithmic reasons.** The
nibble-packed structs are pure C space-optimization with zero reason to
replicate in a Resource-based port (plain typed fields are strictly
better). The real cost is the **stateful, multi-turn scripted conversation**
(shuffle → ask → wait → branch → repeat, with progress that must survive a
warp/save mid-conversation) — a dialogue-state-machine problem, not a
data-structure one. Worth budgeting real time for only if the feature is
actually wanted; it's a genuinely separate system from "just fight
Frontier trainers."

### 1.9 Record mixing / wireless — recommend exclusion, not port

`src/record_mixing.c` exchanges: the player's own Tower "ghost record" (so
another cartridge can fight a simulated version of you), up to 2
Apprentices, and Ranking Hall entries — all over real link-cable/wireless
communication with a second physical Game Boy Advance, plus a legacy
Ruby/Sapphire-format conversion path for cross-gen link. **None of this has
anything to hang off of in a single-player-only fangame** — there is no
"expensive part" to budget, the correct action is exclusion, not
translation. The only design question it raises is cosmetic: does the
fangame want a *fake* Ranking Hall (static/scripted "rival" entries) to
preserve the flavor of "other trainers' streaks on display," since the
real feature needs a second physical player? That's a product decision for
Rob, not a technical one — flagged, not resolved here.

---

## 2. Per-facility findings

### 2.1 Battle Tower (`src/battle_tower.c`)

**Format**: confirmed — a plain streak of consecutive Trainer battles, no
bracket/tournament structure. `InitTowerChallenge`
(`src/battle_tower.c:708`) resets the in-set battle counter;
`SetTowerBattleWon` (`:771-785`) increments it per win;
`SetNextTowerOpponent` (`:855`) picks the next single opponent (with an
occasional cosmetic substitution of a record-mixed friend's or Apprentice's
team via `ChooseSpecialBattleTowerTrainer`, `:787` — variety, not a format
change). Singles/Doubles/Multis/Link-Multis are just longer or
partner-assisted versions of the same loop
(`sBattleTowerPartySizes`, `:684-690`). No team-preview or swap between
fights in a set — the corridor map script goes straight from one battle
into the next.

**Team selection**: confirmed the player's **own** team, not rentals — a
grep for "rental" across `src/*.c` only matches `battle_factory.c`/
`battle_factory_screen.c`/`battle_tent.c`, never `battle_tower.c`. The
lobby script calls `special ChoosePartyForBattleFrontier` once per
challenge, driving the shared party-menu flow over the player's real party.

**Team eligibility (shared with every other facility, via
`GetBattleEntryEligibility`/`CheckBattleEntriesAndGetMessage`,
`src/party_menu.c:7302-7459`)**: species clause (no two selected mons share
a species), item clause (no two share a held item), the level cap (§1.4),
a per-species `isFrontierBanned` data flag (`include/pokemon.h:492`, checked
generically for Frontier, not Tower-specific), eggs always rejected. This
machinery is **shared infrastructure**, reused by Dome/Pike/Arena/Pyramid/
Palace as well.

**Rewards**: nothing Tower-specific beyond the shared BP table plus a
Tower-only Ribbon award at streak milestones
(`AwardBattleTowerRibbons`, `:1668`) — cosmetic persisted-flag bookkeeping,
not a battle-format mechanic.

**Out of scope, flagged not investigated further**: co-op Multi-Battle
partner selection (AI or record-mixed), real link-cable Multi Battles,
e-Reader trainer support, RS↔Emerald record-format conversion, and the
separate Battle Tent rental-format variant — all wireless/e-Reader-
specific and correctly excludable for an offline single-player port.

**Port cost: essentially free reuse**, given an engine that already has
trainer battles, doubles, held items, abilities, and trainer AI tiers (all
already built through this project's own M8-M17). Only genuinely new work:
a streak counter + next-opponent generator loop (trivial), the shared
eligibility filter (small, generic, reused everywhere else too), and
milestone-ribbon bookkeeping (cosmetic).

### 2.2 Battle Dome (`src/battle_dome.c`)

**Format**: confirmed — a real 16-participant, 4-round single-elimination
bracket. `DOME_TOURNAMENT_TRAINERS_COUNT = 16`
(`include/global.h:452`); `DOME_ROUND1/2/SEMIFINAL/FINAL, DOME_ROUNDS_COUNT=4`
(`include/constants/battle_dome.h:4-8`). Seeding
(`InitDomeTrainers`, `src/battle_dome.c:1911-2115`): 15 opponents generated
(first 5 slots deliberately easier via
`GetRandomScaledFrontierTrainerId(streak+1, 0)`, the rest at full
streak-scaling); every entrant (including the player) gets a
`rankingScores[]` value (sum of 6 stats across their 3 entered Pokémon plus
a small type-diversity bonus); entrants insertion-sorted by that score into
a fixed seeded-placement array
(`sTourneyTreeTrainerIds[16] = {0,8,12,4,7,15,11,3,2,10,14,6,5,13,9,1}`,
`:749` — keeps strong seeds apart early, matching the in-game rules-board
text). The Frontier Brain (Tucker) is inserted afterward specifically on
the bracket half opposite the player, guaranteeing he's only faced in the
Final.

**Team selection/preview — a real two-stage commitment, more specific than
"pick N for the whole tournament":**
1. **3** Pokémon (`FRONTIER_PARTY_SIZE`) chosen once, before round 1, locked
   in for the whole tournament (`ChooseParty­ForBattleFrontier`).
2. Before **each individual match**, the player can view that round's
   specific opponent's full 3-mon roster (`dome_showopponentinfo`) and
   browse the whole bracket tree at any time
   (`dome_showtourneytree`), then must choose which **2 of their own
   already-committed 3** will actually battle that round
   (`DOME_BATTLE_PARTY_SIZE = 2`,
   `include/constants/battle_dome.h:13`) — held-in-reserve slot decided
   fresh each round, packed into
   `gSaveBlock2Ptr->frontier.selectedPartyMons[3]`.

**Off-screen bracket matches are NOT simulated battles — they're a cheap
scoring formula, not a real engine invocation.** `DecideRoundWinners`
computes, per non-player pairing:
```
points = Σ_3_mons_×_4_moves [ TypeEffectivenessPoints(move, opposingSpecies, AI_VS_AI) ]
       + Σ_3_mons [ TotalBaseStat / 10 ]
       + (Random() & 0x1F)
       + tournamentId   // deterministic tiebreak
```
Higher points wins; the Frontier Brain is hardcoded to always win any match
he's in, checked before this formula runs at all. A separate function
(`GetWinningMove`) independently fabricates a plausible "won using move X"
flavor line via its own best-power heuristic. `ResolveDomeRoundWinners`
marks the player's own opponent eliminated after the real battle, then
calls `DecideRoundWinners` once for every remaining round to resolve the
rest of the bracket in one pass. **No turn-based simulation of any kind is
run for matches the player doesn't fight.**

**Win condition**: standard last-team-standing per battle, plus "win 4
rounds." A simultaneous double-KO draw counts as a player loss — but this
is confirmed **generic, whole-game** logic
(`IsPlayerDefeated`, `src/battle_setup.c:1021-1038`, lists
`B_OUTCOME_DREW` alongside `LOST`/`FORFEITED` for any Trainer battle), not
Dome-specific — the Dome's "referees review the match" text is pure flavor
over a pre-existing rule.

**Rewards**: standard BP table, but its tier index advances per
**tournament won**, not per individual battle — a real indexing-semantics
difference from every streak-based facility, worth reconciling with the BP
economy port (§1.1).

**Port cost: two genuinely new pieces, both cheap, not expensive.**
(1) A 16-node single-elimination bracket with seeded placement — simple
array/sort logic, no simulation infrastructure. (2) The off-screen match
resolver — the part that *sounds* expensive ("simulate every bracket
match") turns out to be a handful of stat sums, one type-effectiveness
lookup pass, and one `Random() & 0x1F` per round, run once for all still-
live non-player pairs. **It deliberately avoids invoking the actual battle
engine at all.** Everything else (the real player-vs-opponent battles, the
3-then-2-of-3 team selection UI) is free reuse of the same eligibility
machinery/battle engine every other facility uses.

### 2.3 Battle Factory (`src/battle_factory.c`, `src/battle_factory_screen.c`)

**Core mechanic**: a pool of **6** rental Pokémon offered
(`SELECTABLE_MONS_COUNT = 6`), player picks **3**
(`FRONTIER_PARTY_SIZE`), with full stats/moveset/ability/item visible via a
real Summary Screen lookup before choosing (`SUMMARY_MODE_LOCK_MOVES` —
just prevents *editing* the moveset in that UI, doesn't hide anything).
`rentalMons[FRONTIER_PARTY_SIZE * 2]` (`include/global.h:527`) — 6 slots:
`[0..2]` current team, `[3..5]` the swap-candidate pool.

**The swap mechanic — one-for-one, optional, offered before each
subsequent battle, and the swap pool is the team you just DEFEATED, not the
upcoming one:**
- After each win, `SetRentalsToOpponentParty`
  (`src/battle_factory.c:316-333`) copies the just-fought team into
  `rentalMons[3..5]`.
- `AskSwapMon` (Yes/No prompt) then optionally swaps exactly one of your 3
  for one of those 3, via a two-screen UI (`SWAP_PLAYER_SCREEN` then
  `SWAP_ENEMY_SCREEN`, `src/battle_factory_screen.c:2311-2314`).
- A subsequent `factory_generateopponentmons` call (rolling the *next*
  opponent, for hint-text purposes only —
  `GetOpponentMostCommonMonType`/`GetOpponentBattleStyle`,
  `:480-601`) does **not** touch the swap-pool array — the pool is
  strictly "what you just beat."
- **No AI/heuristic recommends a swap** — the hint text (dominant type +
  an informal "style" bucket like HIGH_RISK/WEAKENING derived from
  per-move effect tags) is purely informational; the player reasons about
  it unaided.
- Items/abilities/natures on rental mons reset to their fixed table values
  every battle (`RestorePlayerPartyHeldItems`) — not persistent inventory.

**Rental pool data source**: a dedicated static table,
`gBattleFrontierMons[882]` (§1.5) — **the same shared Frontier trainer
pool** every other facility draws from, not something Factory-specific.
`CreateFacilityMon` applies a Factory-specific quirk: a rental mon's Return
is silently substituted with Frustration (`src/battle_frontier.c:332-333`),
since rental mons have no real bond with the player.

**Difficulty scaling**, two independent axes: species tier scales via
`challengeNum`-indexed range tables (`sInitialRentalMonRanges`); fixed IVs
scale the same way (`sFixedIVTable`); a separate slow-burn "veteran renter"
bonus (`factoryRentsCount`, cumulative swaps across all time, thresholds at
15/22/29/36/43) bumps some of the *initial* offered mons one tier higher.
AI scaling reuses the streak-ramped flags already covered in §1.6.

**Port cost: mostly free reuse, one real UI-flow piece to build.** Free:
damage calc/abilities/items/AI during battles — `battle_factory*.c` is pure
pre/post-battle menu-layer code, no battle-turn logic at all. The genuinely
new piece is the **6-offered/pick-3, then one-for-one-swap-against-the-
defeated-team UI flow**, gated by a small state machine (which team is
currently the swap pool). Given this project's own stated UI preference
(scene-tree-visible screens, fixed template pools — per memory), this maps
naturally onto that established pattern rather than requiring anything new
architecturally.

### 2.4 Battle Palace (`src/battle_gfx_sfx_util.c`, `src/battle_palace.c`)

**Headline mechanic, confirmed real algorithm — and confirmed NOT a fourth
AI system**, correcting the likely-assumed shape of this facility.
`ChooseMoveAndTargetInBattlePalace`
(`src/battle_gfx_sfx_util.c:144-310`):

- Every move belongs to one of 3 groups — Attack/Defense/Support — derived
  from its real target type + status-vs-damaging split
  (`GetBattlePalaceMoveGroup`, `:321-349`), not an arbitrary hand-tagged
  category.
- Each Nature carries **two** cumulative-percent pairs (healthy-HP set and
  low-HP set) in its own data struct
  (`NatureInfo.battlePalacePercents[4]`, `include/pokemon.h:598-608`) — real
  example: Hardy is 61/7/32 Atk/Def/Support at any HP; a more aggressive-
  when-hurt nature swings from 20/25/55 healthy to 84/8/8 below 50% HP.
- Per turn: roll 0-99, pick the healthy or low-HP threshold pair based on a
  one-way "ever dropped below 50% HP (and not asleep)" latch bit set at
  switch-in/end-of-turn, land in a group.
- **The group only NARROWS the candidate move bitmask — the actual "which
  move within that group" decision is handed to the exact same
  `BattleAI_SetupAIData`/`BattleAI_ChooseMoveIndex` pipeline ordinary
  trainer battles already use.** Confirmed directly:
  `BattleAI_SetupAIData(gBattleStruct->palaceFlags >> 4, battler)` under
  `BATTLE_TYPE_PALACE` vs. `BattleAI_SetupAIData(0xF, battler)` otherwise —
  same function, just a narrower bitmask input. There is no separate
  scoring loop and no separate opponent-modeling anywhere in this facility.
- Total genuinely new logic across the whole facility: roughly
  **230-350 lines** (the group-roll function, the group classifier, a
  doubles-only nature-based target picker, one persistent per-battler flag
  bit).
- A documented, preserved vanilla bug exists in the fallback path (a
  Support-count check accidentally reads the Defense bitfield under
  `#ifndef BUGFIX`) — worth knowing if porting literally rather than
  reimplementing intent.

**Player input**: 100% automated move selection for BOTH sides, including
the player's own team — `PlayerHandleChooseMove` special-cases
`BATTLE_TYPE_PALACE` to route straight into the same automated chooser used
for AI opponents (with a fixed ~8-tick "eyes glint" delay for presentation).
The top-level action menu (Fight/Bag/Pokémon/Run) is **untouched** — the
player still picks Fight/Switch/Run/Item each turn; only "Fight" then skips
past move selection.

**Rewards/quirks**: prize tiers by streak length (vitamins early, held
items like Bright Powder/Leftovers/Choice Band past streak 41); a
preserved, source-comment-acknowledged bug in the streak-record
conditional; opponent selection is a flat random pick, not
challenge-scaled the way Factory's is.

**Port cost: small, not a new subsystem.** The premise that this needs
"essentially a fourth AI decision-making system" does not hold up against
source — it's a small nature-driven pre-filter bolted onto the AI you
already have. Free reuse: the entire move-scoring backend, damage calc,
abilities, items, the action-menu flow. New but small: the per-nature
percent table (~25 entries, must be sourced from real data, not
regenerated/guessed), the group classifier, the roll-and-handoff function,
the persistent low-HP latch bit, and (only if doubles support is wanted for
this facility) the nature-based target picker.

### 2.5 Battle Pike (`src/battle_pike.c`)

**In-universe name**: the game's own script text calls this "your Battle
Choice challenge," not "Battle Pike" — worth knowing for authentic flavor
text if that matters to the port.

**Room types — confirmed complete, 9 total**
(`include/constants/battle_pike.h:6-15`): Single Battle (easiest trainer
tier), Heal Full, NPC (flavor chat, no battle), Status (inflicts a random
ailment on 1-3 party mons), Heal Partial (1-2 mons), Wild Mons, Hard Battle
(single trainer from the *toughest* tier), Double Battle (two trainers back
to back), Brain (final room only).

**Correction to a likely assumed premise: there is no "lucky room" with a
favorable/stat-boosted encounter anywhere in this source.** The closest
candidate, Wild Mons, is actually stacked *against* the player — a small,
deliberately dangerous species pool (Seviper/Milotic/Dusclops/Electrode/
Breloom/Wobbuffet with movesets like Toxic+Glare+Body Slam, Explosion,
Spore, Counter/Mirror Coat/Destiny Bond). Flagging this explicitly as a
correction rather than silently building a room type that doesn't exist.

**Status room mechanic**
(`TryInflictRandomStatus`, `:878-982`): weighted roll (Toxic 35%/Freeze or
Frostbite 25%/Paralysis 20%/Sleep 10%/Burn 10%), applied to 1/2/3 random
mons depending on progress through the run, respecting the exact same
type- and ability-immunity checks this project's own status engine already
implements — pure reuse.

**Hint mechanic — real, precisely bounded, and never lies for the door it
covers**: each 3-door intersection secretly pre-assigns one door a specific
real room type. The 9 room types collapse to **5** hint categories (People,
Whispering, Nostalgia, Pokémon, Brain — a many-to-one mapping). A Hint
Giver NPC, if asked, reveals **only the category, only for the pre-picked
door** — and is always accurate for that one door. For the other two doors,
the room type is randomly rolled *excluding* whichever types share the
hinted door's category — so the hint also carries unstated negative
information about the unhinted doors. Asking is optional; the hint is
always computed regardless. A special unmissable warning fires
unconditionally when the *next* room will be the Frontier Brain.

**No Shiny/special-colored dangerous-Pokémon mechanic found** — checked
explicitly, confirmed absent, flagged as a correction rather than a gap
this recon failed to find.

**Structure**: 14 sequential 3-door checkpoints
(`NUM_PIKE_ROOMS = 14`) — a straight linear progression with a real (if
immediately resolved) 3-way branch at each checkpoint, not a maze and not
backtrackable ("there is no turning back"). Room 14+ leads to the Pike
Queen. Held items are stripped for the challenge's duration and restored
by species-match afterward (`SaveMonHeldItems`/`RestoreMonHeldItems`) —
possibly shared plumbing with Pyramid's identical-shaped mechanic, worth
reconciling during implementation.

**Port cost: small, entirely non-battle-engine work.** Free reuse: status
infliction (type/ability immunity), trainer battles, healing, wild-mon
assignment. New but cheap: the 9-room-type state machine, the 5-category
hint-mapping table, the "one door truthful / other two category-excluded"
RNG rule. **Overworld-dependent, not battle-engine work**: the entire
"3-door room → resolved room → fresh 3-door room" warp loop needs your
map/warp/NPC/dialogue system, not the battle engine.

### 2.6 Battle Pyramid (`src/battle_pyramid.c`)

**Overwhelmingly overworld/map-generation code, confirmed strongly** — of
~2200 lines, the large majority is floor-template data, item/trainer
scatter algorithms, hint tables, and map-layout assembly. The only
battle-adjacent logic is stripping held items and swapping wild-mon
species/level/moves before a fight starts.

**Floor generation is NOT true procedural generation — it's assembly from
a fixed library of 16 hand-authored 8×8 "squares."** Each floor is a 4×4
grid (`PYRAMID_FLOOR_SQUARES_WIDE/HIGH = 4`) of
`NUM_PYRAMID_FLOOR_SQUARES = 16` pre-made map layouts
(`data/layouts/BattlePyramidSquare01`-`16`). A floor template
(`sPyramidFloorTemplates[]`) specifies item/trainer counts, placement
style, a run-speed multiplier, and 8 *candidate* square IDs from which 16
are drawn (with repeats) via a seeded RNG. One square is designated
entrance, one exit; every other square's copy of the shared "potential
stairs" tile gets silently overwritten to plain floor. Trainer/item
objects are likewise **not freely scattered** — each pre-made square
already has its own candidate object-event spawn slots baked in;
placement just randomly selects among these pre-authored slots per the
floor template's rule. **This is a "shuffle a small hand-built room
library + tagged spawn markers" system, not BSP/cellular-automata/
recursive-backtracker maze generation** — porting it is a content-
authoring task (build ~16 reusable Godot room chunks with tagged spawn
markers) plus a straightforward shuffle/placement script, much cheaper
than real procedural maze generation would be.

**Held items — physically removed, not just disabled.**
`ClearPyramidPartyHeldItems` literally sets each held item to none; the
originals are preserved in a separate backup and reattached by
species-match afterward (`RestorePyramidPlayerParty`) — a real removal +
restore-by-match, not a hold-effect-disable flag.

**Visibility radius/fog-of-war**: real, and reuses the base game's
existing dark-cave/Flash scanline-darkening mechanic verbatim (same
`SetFlashScanlineEffectWindowBoundaries` call, same
`GetFlashLevel() > 0 || InBattlePyramid_()` gate elsewhere in
`overworld.c`). Not affected by any item or ability (items are all
stripped anyway) — it's a fixed scripted animation on floor entry, not a
gameplay-affectable stat.

**Per-floor contents**: trainer count fixed per floor template (3-8,
capped at 8); item count fixed (2-7); wild encounters are **not** a fixed
per-floor count — they hook into the ordinary overworld wild-encounter RNG
(step-on-grass checks), just swapping in a Pyramid-specific species/level/
moves table. Finding the exit is a standard walk-onto-a-tile warp trigger.

**Scattered item pickups — confirmed, and separate from the held-item
strip.** Per-round, per-difficulty item tables (20 rounds × 10 items each)
back a classic "walk up to a glowing Poké Ball, pick up a Potion/Ether/
Leftovers" mechanic, fully independent of the party's own (stripped) held
items.

**Port cost: overwhelmingly overworld work, minimal battle-engine
touch.** Free reuse: trainer battles, wild encounters, party-data
mutation for the item strip/restore. New, and squarely overworld-owned:
the 16-square floor-composition + entrance/exit algorithm, scattered item
pickups, the fog-of-war radius animation (cheap if the overworld already
has any "dark room"/vision-radius mechanic to piggyback on; new field-
rendering work otherwise), and a per-floor run-speed penalty. **This
facility's real cost lives in content authoring (16 room chunks with
tagged markers), not algorithm design.**

### 2.7 Battle Arena (`src/battle_arena.c`, plus hooks scattered through `battle_util.c`/`battle_script_commands.c`/`battle_end_turn.c`/`battle_main.c`)

**Correction to the likely assumed premise: it is NOT "mind points hit
zero and the battle ends early."** Mind points can go negative and there
is no zero-threshold check anywhere in the source (confirmed by grepping
every usage of the point fields). What actually happens is a **periodic,
forced, deterministic 3-category judgment every 2 turns**:

Three categories are tracked per current 1-on-1 pairing —
`ARENA_CATEGORY_MIND/SKILL/BODY`:
- **Mind points**, awarded the instant a move is *used*: a normal
  damaging move (excluding Counter/Mirror Coat/Bide) → **+1**; a
  first-turn-only move (Fake Out-style), Protect/Detect, or Endure →
  **−1**; any other status move → **0**.
- **Skill points**, awarded once the move *resolves*: failed/already-used-
  up → **−2**; immune/unaffected (not a plain miss) → **−2**; hit landed
  both super- and not-very-effective simultaneously (split typing) →
  **+1**; super-effective → **+2**; not-very-effective → **−1**; ordinary
  connecting hit → **+1**; plus a flat **−3** on several specific
  "message printed" triggers (move made useless, blocked, drain-heal
  printed, prevented flinch/confusion/attraction, stayed awake via item).
- **Body** — not accumulated at all; computed live at judgment time as
  `(currentHP × 100) / hpAtBattleStart` for each side's current mon.

**The judgment itself**: a per-pairing turn counter resets on every
switch-in and increments once per completed turn; it fires an
**unconditional** judgment exactly when it hits 2 (both battlers still
alive). At that judgment, for **each** of the 3 categories, whoever's
value is higher gets +2 to a running total (ties give +1 each); after all
3, whoever has the higher grand total (0-6 scale) **wins the entire
pairing immediately** — the loser is force-set to 0 HP and flagged
fainted, even if their actual HP is well above zero. A tied grand total
fails **both** sides simultaneously. A judge's-commentary text/state
system prints per-category referee lines plus animated win/tie/lose icons.

**So is there a turn limit? Effectively yes, and it's exact, not
probabilistic.** Since the judgment is unconditional once triggered and
fires reliably at turn 2 of every surviving pairing, **every 1-on-1
Arena pairing is guaranteed to resolve within at most 2 full turns**,
barring an earlier ordinary HP-based faint. Since Arena also disallows
mid-battle voluntary switching, a full trainer battle plays out as a
sequence of these ≤2-turn pairings, with each fainted-mon replacement
resetting the point counters, the HP-at-start snapshot, and the 2-turn
gate.

**Move-selection restriction**: none found beyond the scoring bias itself
— Protect/Detect/Endure/first-turn-only moves cost Mind points, plain
status moves earn nothing, blocked/useless/ineffective hits cost Skill
points. This shapes incentives, it doesn't restrict legality — existing
move-selection/legality code is untouched.

**A field-name collision to note, not an Arena mechanic**: the
`arenaMindPoints` struct field is separately reused, under an unrelated
name, as a plain countdown timer inside the **Battle Palace**'s automated
move-choice delay (`battle_controller_player.c:2101-2119`, the source
comment admits it's "used here as a placeholder for a timer"). Don't let
this coincidental field-name reuse bleed into an Arena port.

**Port cost: small, self-contained, and entirely inside the battle
engine — no overworld dependency at all.** Free reuse: move category/
effect lookup, move-result-flag checks (super/not-very-effective),
fainting/switch-in flow, the no-switch-in-Arena enforcement pattern (very
possibly shared Frontier plumbing, worth reconciling with §1). New but
small: a per-pairing 2-category point accumulator keyed off hooks this
project's damage pipeline already computes every hit, an HP% snapshot at
switch-in, and a turn-counter gate forcing the 3-category comparison at
turn 2 with a hard win/lose/draw override on the normal fainting
condition. On the order of a few hundred lines, no new engine
infrastructure beyond a small "Arena battle mode" flag with its own
end-of-turn hook.

---

## 3. Cross-cutting port-cost synthesis

Given this project's already-built battle engine (damage calc, type chart,
abilities, held items, status conditions, doubles support, trainer AI
tiers — all shipped through M8-M19 per the roadmap), the Frontier
facilities split cleanly into three cost bands:

**Free reuse, essentially zero new battle-engine work**: Battle Tower
(entirely — it's just streak bookkeeping and eligibility filtering over
ordinary trainer battles), the actual battles fought in every other
facility (all facilities use the same damage calc/abilities/items/AI
underneath their own format wrapper), Battle Palace's move-scoring backend
(hands off to the existing trainer AI, doesn't replace it).

**Small, self-contained new logic, no new architecture required**: Battle
Dome's bracket structure + off-screen resolver (array/sort logic + a cheap
scoring formula, deliberately not a simulation), Battle Palace's
nature-driven move-group pre-filter (~300 lines, one new per-nature data
table), Battle Arena's point-accumulator-plus-judgment gate (a few hundred
lines, entirely inside the battle engine), Battle Pike's room-type state
machine + hint-category mapping (small, but genuinely overworld-dependent
for its warp-loop presentation).

**Real content-authoring or UI-flow cost (not algorithmic complexity)**:
Battle Factory's 6-offered/pick-3/swap-against-the-defeated-team UI (a
real multi-screen flow, but maps onto this project's own established
scene-tree UI pattern), Battle Pyramid's whole floor-generation-and-
traversal system (genuinely the single most overworld-heavy facility —
16 hand-built room chunks + tagged spawn markers is the actual cost, not
new algorithm design), the shared Apprentice/Interview system (a
stateful multi-turn dialogue mechanic, separable from "just fight
Frontier trainers" and optional in scope).

**Data volume, not architecture, is the largest real cost across the
board**: the shared 300-trainer/882-mon Frontier pool (§1.5) needs its own
Kanto-appropriate content roster the same way the main 855-trainer/717-
move/226-ability rosters already did — that's authoring work sized like
any of this project's own prior data-pipeline milestones, not a new kind
of problem.

---

## 4. Adjacent systems flagged but explicitly NOT investigated this session

- **Trainer Hill** (`src/data/battle_frontier/trainer_hill.h`, 4821 lines)
  — a related facility with its own trainer/mon data, distinct from the 7
  facilities covered above. Already named in this project's own M35
  roadmap row ("facility/special trainers... Trainer Hill... deferred per
  §6.3") — this recon confirms the file exists and is substantial, but did
  not open it.
- **Battle Tent** (`src/data/battle_frontier/battle_tent.h`, 3165 lines) —
  the Verdanturf/Fallarbor/Slateport rental-format minigames, reusing
  `FRONTIER_LVL_TENT` and sharing Factory-adjacent code paths. Not
  investigated.
- **Secret Base trainers** — already named in the M35 roadmap row as its
  own money-formula branch (`docs/m24_recon.md` §3's `GetTrainerMoneyToGive`
  discussion references it); not touched by this session.
- **Roaming trainers / `AI_FLAG_SAFARI` / `AI_FLAG_FIRST_BATTLE`** —
  already named in the M35 roadmap row; not touched by this session.

None of these four are part of "the Battle Frontier" as conventionally
scoped (Tower/Dome/Factory/Palace/Pike/Pyramid/Arena) but they sit in
clearly adjacent territory and were flagged during this recon's own file
inventory (§1.7). Recommend a short, separate future recon pass for these
four specifically before deciding whether any belong in the same
implementation arc as the 7 facilities above.

---

## 5. Open questions for Rob

None of these were resolved this session — this is recon only. Recorded
here so a future scoping/decision session doesn't have to rediscover the
fork points.

1. **Scope breadth**: build all 7 facilities, or a subset first? Given the
   cost bands in §3, Tower is by far the cheapest first target (near-zero
   new work) and would prove the shared-infrastructure layer (§1) end to
   end before investing in Dome's bracket logic or Pyramid's room-chunk
   authoring.
2. **Anti-savescum streak protection (§1.3)** — port faithfully, or
   simplify to "reset on loss" given this project's own save architecture?
3. **Apprentice/Interview system (§1.8)** — build at all? It's a real,
   separable feature from "fight Frontier trainers," with a genuinely
   different (dialogue-state-machine) cost shape than every battle-format
   mechanic above.
4. **Record mixing / Ranking Hall (§1.9)** — confirmed excludable as a
   *mechanism* (no multiplayer transport exists), but is a fake/static
   Ranking Hall wanted for flavor, or dropped entirely?
5. **Facility-ID numbering (§1.7)** — which single canonical enum should
   this project standardize on, given the source's own 3 inconsistent
   schemes?
6. **Trainer Hill / Battle Tent / Secret Base trainers / roaming trainers
   (§4)** — worth their own recon pass now, or deferred further?
7. **AI-tier fidelity for Frontier trainers (§1.6)** — this project's
   existing narrow BASIC/SMART extension (`docs/m24_recon.md` §6.2) already
   covers the fixed Frontier flag set for free; Factory's own 3-step
   streak ramp is the only facility needing anything beyond that. Confirm
   this is sufficient, or does Rob want the fuller 34-flag AI system
   (already flagged for an M30-onward revisit per `docs/m24_recon.md`)
   pulled forward specifically for Frontier trainers?

---

## 6. Proposed sequencing (draft — pending Rob's answers to §5)

Mirrors this project's own established multi-session-per-milestone
discipline. Not locked in — offered as a starting point once scope
decisions land.

1. **Shared infrastructure first** (§1): BP economy, symbols, streak
   tracking (with or without the anti-savescum flag per §5.2), the
   Frontier trainer-pool data pipeline (§1.5, the real content-authoring
   cost), AI-flag wiring (§1.6), the shared party-eligibility filter.
   Nothing here is facility-specific — building it once unblocks every
   facility below.
2. **Battle Tower** — the cheapest possible first facility, validates the
   shared infrastructure end to end with essentially zero facility-unique
   work.
3. **Battle Dome** — next-cheapest: a bracket data structure + a
   deliberately non-simulating scoring formula, both small and
   self-contained.
4. **Battle Arena** — similarly small and self-contained, entirely inside
   the battle engine, no overworld dependency.
5. **Battle Palace** — small nature-driven pre-filter on existing AI;
   needs real per-nature data sourced from the actual reference table, not
   invented.
6. **Battle Factory** — the rental/swap UI flow is the real new surface
   area here; sequence after the simpler facilities so the shared
   party-selection UI patterns are already proven out.
7. **Battle Pike** — small battle-side logic, but its warp-loop
   presentation depends on the overworld/map-script system being ready.
8. **Battle Pyramid** — last, and likely its own multi-session arc given
   it's overwhelmingly overworld/room-authoring work rather than battle
   logic; probably wants sequencing alongside other overworld-heavy
   milestones (M27) rather than purely alongside the other 6 battle-format
   facilities.

No code written this session, per its own explicit recon-only scope.
