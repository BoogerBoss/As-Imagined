# M27G recon — the `special`/`specialvar`/`callnative` surface

**Status: recon only, nothing implemented.** 2026-08-06. Prompted directly by
the M27F opcode session immediately before this one, which deliberately
excluded this whole surface as out of scope and pointed at it as the next
real lever.

## The headline correction

Every prior mention of this milestone (`[M27F Stage 4]`, `[M27]`'s own
roadmap row) cited **"1,390 `special` + 719 `specialvar` = 2,109 uses across
569 distinct functions, plus 62 `callnative` across 28 more"** — a measurement
of the *whole region-wide compiled corpus* (`data/map_scripts.json`, which
mixes Kanto and Hoenn content indiscriminately, the same way it mixes in
battle-animation and contest-AI scripts — already documented for the plain
opcode count in `[M27F]`'s own doc comments).

**That number was never the real scope of near-term work, and this session
measured the real one.** A reachability walk from the 32 maps this project has
actually baked (`scenes/maps/*.tscn`) — starting from every placed entity's
own `script_label` (193 of them) plus each map's own `<name>_OnTransition` /
`_OnFrame` / `_OnWarp` / `_OnLoad` / `_OnResume` table entries, then a BFS over
`call`/`goto`/every conditional's own jump target — finds only **51 distinct
`special`/`specialvar` functions (99 total uses) are reachable from content
that actually exists in this project today.** `callnative` never fires at all
from the corridor (0 uses). The method (`/tmp`-scratch, not checked in):
build a directed graph from `data/map_scripts.json`'s own `op`/`args`
structure, walk it from the corridor's real entry points, and log every
`special`/`specialvar`/`callnative` argument the walk actually passes through.

This is the same shape of correction `[M27F]`'s own opcode-frequency scan
already made once for plain opcodes (region-wide op counts mix in unrelated
content) — applied here to a MUCH larger nominal surface, where it matters
far more: 594 vs 51 is not a rounding difference, it's the whole basis for
sizing this milestone.

## Further refinement: multiplayer-gated call sites are not real, even when reachable

**A second cut through the 51 found roughly a third of them are only ever
reached through a Cable Club / Union Room / Colosseum entry point** — content
this project has already, repeatedly, explicitly excluded (link/trade/
wireless/Mystery Gift/Easy Chat, `docs/overworld_scope.md` rev 11's own
finding). Confirmed by tracing which corridor LABEL actually calls each
function, not just that the function is graph-reachable:

- `CloseLink` (13 uses) — **all 13** are `CableClub_EventScript_Abort*`
  handlers. Zero non-multiplayer call sites anywhere in the walk.
- `SavePlayerParty`/`LoadPlayerBag` (1 each) — both only from
  `CableClub_EventScript_EnterColosseum` (Battle Colosseum, a 2P/4P link
  facility).
- `HasEnoughMonsForDoubleBattle` (2) — both from Cable Club's own
  double-battle-mode selectors.
- `HasAtLeastOneBerry` (1) — `CableClub_EventScript_WirelessBerryCrush`.
- `SetCableClubWarp`/`DoCableClubWarp` (5+4) — self-explanatory.
- `ShowEasyChatProfile`/`ShowEasyChatScreen`/`IsWirelessAdapterConnected`/
  `Script_ResetUnionRoomTrade`/`RunUnionRoom`/`TryRecordMixLinkup`/
  `ValidateMixingGameLanguage`/`TryBattleLinkup`/`TryJoinLinkGroup`/
  `TryBecomeLinkLeader`/`BufferUnionRoomPlayerName` — all Union
  Room/Record-Mix/Easy-Chat, all excluded by the same standing decision.
- `IsPlayerNotInTrainerTowerLobby` (1) — Battle Frontier facility check,
  moot (the facility doesn't exist; the real function is a negated
  presence-check that would always read TRUE anyway).

**Real, actionable scope after removing multiplayer-gated call sites: ~20-25
distinct functions, ~30-40 uses.** This is the number worth building against,
not 51 and certainly not 594.

## Tier 0 — trivial, source-confirmed no-ops or already-built bridges

Every one of these was checked against the actual reference C body, not
assumed from the name.

- **`signmsg` / `normalmsg`** — not `special` calls at all, two VM OPCODES
  this recon found while tracing a real script (`PewterCity_
  EventScript_AideGiveRunningShoes`). Source's own `script_cmd_table.inc`
  dispatches both straight to `ScrCmd_nop1` (`:227-228`) — Emerald never
  implemented either, and this FRLG-focused expansion doesn't either. A
  literal, source-faithful no-op, not a simplification.
- **`DisableMsgBoxWalkaway`** — source's own body (`script.c:685-687`) is a
  single commented-out line; the reference ships this function already
  inert. No-op is not a simplification here, it is a PORT of the real
  function.
- **`SetWalkingIntoSignVars`** (`script.c:689-692`) — same shape, same file,
  both lines of its own real body are commented out in source.
- **`HealPlayerParty`** — already fully implemented (`FieldSpecials.
  HEAL_PLAYER_PARTY`, wired since `[M27F Stage 4]`). Nothing to do.
- **`ChangePokemonNickname`** — already fully implemented, but NOT through
  `FieldSpecials` — it is checked before the generic dispatch inside
  `ScriptVM.step()` itself (`_begin_nickname()`, `[M27K K-c]`), because it
  is the one special that can't answer synchronously. Nothing to do; noted
  here only so a future scan of `FieldSpecials.is_known_special` doesn't
  read its absence there as a gap.
- **`OpenMuseumFossilPic` / `CloseMuseumFossilPic`** — opens/closes a
  picture-viewer overlay of a fossil sprite (`script_menu.c:1161-1194`).
  Matches the already-established `showmonpic`/`hidemonpic` no-op precedent
  exactly (`[M27K K-a]`'s own doc comment: "this project has no picture
  layer in the field at all — a no-op loses the flourish, not the scene").
  Reachable from `PewterCity_Museum_1F_EventScript_KabutopsFossil`/
  `_AerodactylFossil`, both real corridor content.
- **`SaveGame`** — a bridge to the already-built M27L save system
  (`SaveManager`/`OverworldSession`), reached via `Common_EventScript_
  SaveGame` — a SHARED script (not Cable-Club-prefixed), so likely has real
  non-multiplayer call sites once more of the region is baked even though
  this corridor's own walk only reaches it via one path. Cheap: call the
  same save routine the START-menu SAVE option already calls.
- **`CountPartyNonEggMons`** — with no egg system anywhere in this project,
  this is exactly `party.members.size()`. Trivial once the general
  party-count bridge exists (see next).
- **`CalculatePlayerPartyCount` / `ScriptGetPartyMonSpecies`** — cheap
  reads off `OverworldSession.player_party()`, the same shape the VM's own
  `getpartysize` opcode (`[M27K K-c2]`) already established.

**None of the above needs new design.** They are either literal ports of an
already-inert source function, or a one-line bridge to a system this
project already has.

## Corrections made while implementing G1 (2026-08-06)

- **`StartOldManTutorialBattle` removed from scope entirely, Rob's decision.**
  Not deferred to a later phase — excluded outright. The investigation above
  (Old Man plays a demo battle using the player's own input/items) stands as
  a record of what was found, not as a queued future G4.
- **`SaveGame` moved OUT of Tier 0.** Re-checked its own real corridor
  callers before implementing (the same discipline this recon already
  applied to `CloseLink`/`SavePlayerParty`/etc.) and found ALL FIVE —
  `CableClub_EventScript_SaveAndChooseLinkLeader`/`_EnterUnionRoom`/
  `_RecordCorner`/`_TryEnterColosseum`/`_TradeCenter` — are themselves
  Cable-Club-gated. `Common_EventScript_SaveGame` being a shared (not
  Cable-Club-prefixed) script name was not sufficient evidence of a real
  non-multiplayer caller; it has none IN THIS CORRIDOR. Left for a future
  pass once the region grows past the corridor, not built now.
- **`CalculatePlayerPartyCount`/`CountPartyNonEggMons` moved OUT of Tier 0**
  for the identical reason: their only corridor callers are
  `CableClub_EventScript_CheckPartyTradeRequirements`/
  `_CheckPartyUnionRoomRequirements`.
- **`ScriptGetPartyMonSpecies` CONFIRMED real and kept** — its one corridor
  caller is `PalletTown_RivalsHouse_EventScript_GroomMon` (Daisy's
  grooming), genuine non-excluded content. Source (`field_specials.c:1641-
  1644`): `GetMonData(&gParties[B_TRAINER_PLAYER][gSpecialVar_0x8004],
  MON_DATA_SPECIES_OR_EGG, NULL)` — PARTY-ONLY (no PC fallback, unlike
  `BufferMonNickname` below), indexed by the same `VAR_0x8004` slot
  convention `ChoosePartyMon`/`ChangePokemonNickname` already use.
- **`BufferMonNickname` added to G1**, found while reading `GroomMon`'s own
  full script (needed at its tail regardless of whether `DaisyMassageServices`
  itself does anything). Source (`tv.c:3273-3278`):
  `GetBoxMonData(GetSelectedBoxMonFromPcOrParty(), MON_DATA_NICKNAME,
  gStringVar1)` — DOES support the PC path, but this project has none;
  guarded the same way `_begin_nickname()` already guards
  `ChangePokemonNickname`'s own PC branch (halt, don't guess), rather than
  silently assuming party-only.
- ⚠️ **`DrawWholeMapView` and `IsPlayerNotInTrainerTowerLobby`/
  `BufferUnionRoomPlayerName` were ALREADY implemented** before this recon
  started — `FieldSpecials.NOOP_SPECIALS`/`SPECIALVAR_VALUES` already
  covered all three. The recon's own Tier-2/Tier-3 placement of these was
  stale; corrected here rather than silently reclassified.
- **Daisy's own script (`GroomMon`) will still not run fully to completion
  after G1** — it needs `ChoosePartyMon` (G2) between the yes/no prompt and
  `ScriptGetPartyMonSpecies`, and `DaisyMassageServices`'s real friendship
  effect stays blocked regardless (no friendship system exists). G1 makes
  the LATER half of that script (species check → grooming message →
  nickname buffer → closing message) correct once G2 lands; it does not by
  itself make the whole script playable.

## Corrections made while implementing G2

- **`ChoosePartyMon` shipped exactly as scoped** — a new `Pause.WAIT_PARTY_CHOICE`
  bridging to the already-built `FieldPartyScreen` in browse mode, matching
  `WAIT_BATTLE`/`WAIT_NAMING`'s own result-carrying shape.
- ⚠️ **A real, GENERAL (not Hoenn-only) gap found only by driving the real
  corpus, not by reading it: `PARTY_SIZE` was unresolved.** `GroomMon`'s own
  opcode right after `ChoosePartyMon` is `goto_if_ge VAR_0x8004, PARTY_SIZE,
  DeclineGrooming` — the real "was anything chosen" check, matching this
  project's own `PARTY_NOTHING_CHOSEN` (0xFF) `>= PARTY_SIZE` (6) logic.
  `_literal` had no case for it at all, falling through to 0 — and since
  `VAR_0x8004` is always `>= 0`, this made **all 57 region-wide corpus uses**
  of `PARTY_SIZE` (nearly all in this exact shape: trade requests, minigame
  entry, grooming) unconditionally take the Decline/abort branch, regardless
  of what was actually picked. Fixed with one `_literal` case
  (`include/constants/global.h:82`). Not Hoenn-only in the way the existing
  `_SYMBOLIC_CONSTANTS` dict's own 11 entries are — kept as its own case
  rather than added there.
- **Daisy's grooming script now runs to its own real remaining blocker.**
  Live-driven: offer → `WAIT_PARTY_CHOICE` → a real slot answered →
  `ScriptGetPartyMonSpecies` genuinely reads that slot (proving the
  `PARTY_SIZE` fix, not just asserting it) → the no-op fade/fanfare chain →
  halts cleanly at `special DaisyMassageServices` — not a moment earlier.

## Tier 1 — real, single-player, Kanto-native content; genuine but bounded new work

- **Running Shoes (`PewterCity_EventScript_AideGiveRunningShoes`)** — the
  single highest-value finding this session. The script's own tail is
  `setflag FLAG_SYS_B_DASH` (plain, already-implemented `setflag`) —
  **this is THE real in-game trigger for unlocking Run**, currently granted
  only by the debug boot (`overworld.tscn`'s own `debug_flags` export,
  `[M27E E2]`'s own status note: *"no in-game event grants FLAG_SYS_B_DASH
  yet, so the debug boot grants it"*). The ONLY thing blocking this script
  from running to completion today is `DisableMsgBoxWalkaway` (Tier 0,
  trivial) plus the two Tier-0 no-op opcodes above. **Shipping Tier 0 alone
  makes this reachable for real.**
- **`ChoosePartyMon`** — opens the real party-selection screen
  (`party_menu.c:8100`) and reports the chosen slot in `VAR_0x8004` — the
  same variable/slot convention `[M27K K-c]`'s `ChangePokemonNickname`
  already established. This project already has a real party screen
  (`SwitchSelectScreen`/`FieldPartyScreen`, `[M27I I5]`) — this is a bridge
  to an EXISTING screen in browse-mode, not a new one. Two real corridor
  callers: `EventScript_ChooseMonForInGameTrade` and `PalletTown_
  RivalsHouse_EventScript_GroomMon` (Daisy).
- **In-game trade** (`CreateInGameTradePokemon`/`DoInGameTradeScene`/
  `GetTradeSpecies`/`GetInGameTradeSpeciesInfo`) — a real, SINGLE-PLAYER
  trade (swap one of your own party mons for a fixed NPC-offered one, no
  link cable involved — genuinely distinct from every Union-Room/Link-Trade
  item this recon excludes). Backed by real logic in `trade.c` (not yet
  read in depth — this recon confirmed the call sites and the general
  shape, not the exact mechanics). Reached via `EventScript_
  DoInGameTrade`, itself real corridor content. Sizeable enough to want its
  own Step 0 before implementing — not a quick win, but real and bounded.
- **Old Man tutorial battle** (`StartOldManTutorialBattle`, reached from
  `ViridianCity_EventScript_DoTutorialBattle`) — the iconic Viridian City
  catching demonstration. ⚠️ **Genuinely more complex than the name
  suggests, and this recon's own first instinct (that it might be a quick
  win given `[M27H]`'s catching system already exists) was wrong.** Real
  source has the Old Man take over the PLAYER'S OWN INPUT and play a
  demonstration battle against a wild Weedle using the player's own
  Pokémon and items — not a simple scripted cutscene, an actual battle the
  player watches an AI play through their own interface. Needs its own
  scoping pass (most likely: a disclosed simplification skipping the
  interactive demo and going straight to the item/flag payoff, matching
  this project's own precedent for other GBA-spectacle sequences it has
  simplified elsewhere — but that is a decision for whoever scopes it, not
  assumed here). The script also references `ITEM_TEACHY_TV`, not yet
  confirmed to exist in this project's item roster.
- **`DaisyMassageServices`** — cosmetic Pallet Town NPC flow (Daisy grooms
  a chosen party mon). Its real EFFECT is a friendship boost — and this
  project has **no friendship system at all** (a real, standing gap;
  friendship never increases or decreases anywhere in this codebase, per
  `docs/m18_5h_recon.md`'s own already-recorded finding). The FLOW
  (`ChoosePartyMon` + a flavor message) is buildable now; the actual
  mechanic it's supposed to trigger is not, until something builds
  friendship. A candidate for the same "flavor works, mechanic doesn't"
  disclosed-simplification shape already used elsewhere in this project.

## Tier 2 — deferred to already-scoped milestones (real functions, not this milestone's gap)

- **Pokédex family** (`DrawWholeMapView`/`GetFrlgPokedexCount`/
  `EnableNationalPokedex`/`SetUnlockedPokedexFlags`/`HasAllMons`/
  `GetProfOaksRatingMessage`) → **M33**, still unstarted.
- **`ChooseMonForMoveTutor`** → **M30**, still unstarted.
- **`DoPCTurnOnEffect`/`BedroomPC`** → **M27I I5-5**, explicitly deferred by
  Rob's own decision.
- **`ShouldTryRematchBattle`** (the single highest-usage function in the
  ENTIRE region-wide scan, 311 uses — but 0 of them reachable from this
  corridor) → **M35**'s rematch-tier system, already the reason
  `trainerbattle_rematch` had to ship a disclosed simplification in the
  immediately-prior M27F session.
- **`IsBadEggInParty`** → **M31** (breeding/eggs), still unstarted.
- **`GetLeadMonFriendship`** → **no milestone owns this yet.** A real,
  newly-surfaced gap: nothing in this project's own roadmap currently
  scopes a friendship SYSTEM (only its absence has been noted, twice, as a
  blocker for something else — `docs/m18_5h_recon.md` for EV-adjacent
  mechanics, `DaisyMassageServices` above). Flagged, not assigned.

## Tier 3 — permanently excluded, confirmed by real call-site tracing

`CloseLink`, `SetCableClubWarp`, `DoCableClubWarp`, `ShowEasyChatProfile`,
`ShowEasyChatScreen`, `IsWirelessAdapterConnected`, `Script_
ResetUnionRoomTrade`, `RunUnionRoom`, `TryRecordMixLinkup`,
`ValidateMixingGameLanguage`, `TryBattleLinkup`, `TryJoinLinkGroup`,
`TryBecomeLinkLeader`, `BufferUnionRoomPlayerName`,
`IsPlayerNotInTrainerTowerLobby`, `HasEnoughMonsForDoubleBattle`,
`HasAtLeastOneBerry`, `SavePlayerParty`, `LoadPlayerBag` — see "Further
refinement" above for the per-function call-site evidence. All fall under
this project's own already-standing multiplayer/Battle-Frontier exclusions;
nothing here is a new decision.

## What this recon deliberately does NOT do

It does not attempt to classify or scope the remaining ~540 region-wide
functions this corridor cannot reach. That number is dominated by content
(Contest Hall, Secret Bases, the Battle Frontier's 7 facilities, Trainer
Hill, Trainer Tower, Pokéblocks, the Devon Corporation plotline, dozens of
Hoenn-specific NPCs) that is either already excluded by standing decision or
whose relevance can't be judged before the maps that would use it are ever
baked. **Recommendation: re-run this exact reachability walk every time a
new batch of maps is baked, rather than trying to pre-scope the whole
region now.** The method is cheap (a few minutes of scripted analysis) and
the result changes with which maps exist — scoping against a fixed snapshot
of "everything" would be stale the moment the corridor grows, the same
lesson `[M27B]`'s own "vertical slice, not full-region import" call already
established for map baking itself.

## Proposed build order

1. **G1 — the real Tier 0 batch** (`signmsg`/`normalmsg` no-op opcodes,
   `DisableMsgBoxWalkaway`/`SetWalkingIntoSignVars`/`OpenMuseumFossilPic`/
   `CloseMuseumFossilPic` no-op specials, `ScriptGetPartyMonSpecies`/
   `BufferMonNickname` party bridges — see "Corrections made while
   implementing G1" above for what moved out, in, and was already done).
   Trivial, safe, source-verified no-ops or one-line bridges to systems
   that already exist. **Directly unblocks the Running Shoes NPC** — the
   first real, in-game source for `FLAG_SYS_B_DASH`, replacing the
   debug-only grant.
2. **G2 — `ChoosePartyMon`** — **DONE, 2026-08-06.** A bridge to the
   already-built party screen. Unblocks Daisy's grooming flow (cosmetically
   — `DaisyMassageServices` itself stays blocked on a friendship system) and
   is a real prerequisite for G3. Found and fixed a real, general
   `PARTY_SIZE` gap along the way — see "Corrections made while implementing
   G2" above.
3. **G3 — in-game trade** — **G3a DONE, 2026-08-06** (see "G3a — DONE" below
   for what shipped and the real `_conditional` bug it found). G3b deferred,
   Rob's call. Originally **SCOPED, 2026-08-06** (see "G3 Step 0 — in-game
   trade" below). Small and bounded, not open-ended: one small new data
   table, one more `_literal` symbolic-constant fix (same shape as G2's
   `PARTY_SIZE`), and 4 new `ScriptVM`-dispatched specials — almost all of
   it reuse of `ChoosePartyMon` (G2), `PokemonFactory`'s `forced_ivs`/
   `ability_slot`, and `TextBuffers`. Split into G3a (data + mechanics,
   makes `Route2_House_Frlg`'s Reyley — already baked, already fully
   compiled in the corpus — playable end to end with no animation) and
   G3b (optional: reuse the M26B3 ball recall/send-out animation for the
   swap instead of a silent state change).
4. ~~G4 — Old Man tutorial battle~~ — **REMOVED FROM SCOPE, Rob's decision,
   2026-08-06.** Not deferred; excluded. See "Corrections" above.
5. **Re-run this recon's own reachability walk** whenever the corridor
   grows, rather than scoping the region-wide tail now.

⚠️ **G4 ONWARD IS SCOPED ELSEWHERE — 2026-08-07.** This document remains the
scope of record for **G1–G3** (all shipped) and for the reachability method.
Two newer documents own everything after:

- **`docs/m27g_scope.md`** — scope of record for **G4–G9**: extract
  `ScriptDriver`, the `native` opcode, an `EventScript` GDScript authoring
  front-end, folding the free coroutines in, routing specials through the
  registry, and two save-shape gaps. Written after an architecture
  investigation (`docs/m27g_architecture_recon.md`) into whether to replace
  `ScriptVM` with an `await`-based `EventRunner`. **Conclusion: do not** —
  this project already runs that hybrid architecture and it covers 92.3% of
  field-script command uses.
- **`docs/m27_corridor_opcode_scope.md`** — scope of record for **which**
  opcodes and specials to implement, audited against the 32 baked maps. It
  **supersedes item 5 above** and reaches a stronger conclusion than this
  document did: of 39 reachable special names, 17 implemented / 18
  permanently-excluded multiplayer / 4 blocked on M33, M30 and a friendship
  system. ⚠️ **The specials side is effectively closed for this scope; no
  specials work is proposed.**

⚠️ **This document's own "51 distinct functions / 99 uses" figure is
superseded by that audit's 39**, which parsed the baked maps' own
`scripts.inc` files directly rather than the compiled corpus. The *method*
here was right and is what both later documents reuse; the number moved.

Not scoped here, deliberately: `DaisyMassageServices`'s real friendship
effect (blocked on a friendship system nothing currently owns), and every
Tier 2/3 item (each already has a home, or is already excluded).

## G3 Step 0 — in-game trade

**The real mechanism** (`reference/pokeemerald_expansion/src/trade.c`,
`src/data/trade.h:969-1215`). A flat, region-wide 13-entry
`struct InGameTrade sIngameTrades[]` table — `nickname`, `species` (given
away), `ivs[6]`, `abilityNum`, `otId`, `personality`, `heldItem`, `otName`,
`otGender`, `sheen`, `requestedSpecies` (what the NPC wants), plus 5
contest-stat fields that are flavor-only and not modeled anywhere in this
project. **Only 8 of the 13 are FRLG/Kanto** (the first four —
SEEDOT/PLUSLE/HORSEA/MEOWTH — are RSE-only, confirmed no FRLG map
references them).

Four functions, all `src/trade.c`:
- `GetInGameTradeSpeciesInfo` (`:4545-4551`) — indexes the table by
  `gSpecialVar_0x8005`, buffers the requested species' name into
  `STR_VAR_1` and the given-away species' name into `STR_VAR_2`, returns
  `requestedSpecies`.
- `GetTradeSpecies` (`:4630-4637`) — reads the player's chosen party mon
  (`gSpecialVar_0x8004`, the exact `ChoosePartyMon` output), returns
  `SPECIES_NONE` for an egg, else its species — "what did the player
  actually offer."
- `CreateInGameTradePokemon` (`:4639-4642` → `:4562-4610`) — builds the
  incoming Pokémon from the table entry: species/personality/OT/all 6 IVs
  individually/nickname/OT name+gender/ability num/contest stats/sheen/
  `MET_LOCATION = METLOC_IN_GAME_TRADE`/held item (with mail handling),
  level taken from the PLAYER'S OFFERED mon's own level, then
  `CalculateMonStats`.
- `DoInGameTradeScene` (`:4862-4867`) — ⚠️ **NOT a lightweight fade-and-swap.
  It invokes the FULL link-trade cinematic engine** (`Task_InGameTrade` →
  `CB2_InitInGameTrade` → `CB2_InGameTrade`, ball-bounce animation, GBA
  screen zoom/flash, cable-end sprites, mon-crossing animation) — the exact
  same spectacle a real link trade runs, with `isLinkTrade = FALSE`
  (`CB2_InitInGameTrade`, `:2958-3054`). A real surprise, flagged before
  anyone assumes it's simple. `TradeMons` (`:3083`+) does the actual
  party-slot swap once the animation completes.

**Success is unconditional once triggered** — none of the four functions
themselves can fail. The fail path (wrong species offered, decline,
already-traded) lives entirely in the CALLING SCRIPT via ordinary
`goto_if_ne`/`goto_if_eq`/`goto_if_set` checks against `GetTradeSpecies`'s
own return value — nothing new needed there.

**The opcode/call-site pattern** — confirmed via `data/event_scripts.s:
1531-1551`, four shared helper scripts every one of the 8 real trade NPCs
calls:
```
EventScript_GetInGameTradeSpeciesInfo:  copyvar VAR_0x8005, VAR_0x8008
                                         specialvar VAR_0x8009, GetInGameTradeSpeciesInfo
EventScript_ChooseMonForInGameTrade:    special ChoosePartyMon
EventScript_GetInGameTradeSpecies:      specialvar VAR_RESULT, GetTradeSpecies
EventScript_DoInGameTrade:              special CreateInGameTradePokemon
                                         special DoInGameTradeScene
```
No new opcode CLASS is needed — `special`/`specialvar` (G1) and
`goto_if_*`/`copyvar`/`setvar`/`msgbox`/`yesnobox` are all already-shipped.
This is four new NAMED `special`/`specialvar` functions riding entirely on
opcode infrastructure that already exists, the same shape as G1/G2's own
additions — not a new command class the way `trainerbattle` was
(`[M27F Stage 2]`).

**Real corridor caller, confirmed already baked and already playable-once-
built**: `Route2_House_EventScript_Reyley` (`data/maps/Route2_House_Frlg/
scripts.inc`) is fully compiled into this project's own `data/map_scripts.
json`/`data/map_texts.json` corpus TODAY, on `Route2_House_Frlg` — one of
the 32 already-baked maps. Its whole script (decline / not-requested-mon /
already-traded / success, all 4 branches) is real, present, and needs only
the 4 opcodes below to run end to end — the exact shape `[M27F Stage 4]`
already proved for the Pokecentre nurse. The other 7 trade NPCs (Route 11,
Underground Path, Cerulean, Vermilion, Cinnabar Lab x2, Route 18) all sit on
unbaked maps — gated on map-baking, not on this milestone.

**Not multiplayer-gated** — traced directly: every real caller of the 4
functions is a plain map NPC script, none `CableClub_*`-prefixed, and
`DoInGameTradeScene`'s own internals never touch `HandleLinkDataSend`/
`SendBlock`/any link primitive on the `isLinkTrade = FALSE` path (those live
in a separate `CB2_UpdateLinkTrade` chain further down `trade.c`, never
reached here). Confirmed, not assumed — the standing multiplayer exclusion
does not apply to G3.

**What's reuse vs. genuinely new:**

Reuse, zero new mechanism: `special`/`specialvar` dispatch (G1);
`ChoosePartyMon` (G2) — the exact selection screen this needs;
`nickname`/`held_item` on `BattlePokemon` (both already real, settable
fields); `PokemonFactory.create_battle_pokemon(...forced_nature,
forced_ivs, ..., ability_slot)` — already supports forced IVs and a
specific ability slot, exactly what the incoming mon's construction needs;
the existing `_species_name()` helper (`bufferspeciesname`'s own backing
function) for `GetSpeciesName()`; `setflag`/`goto_if_set` for the
already-traded gate; the M26B3 battle send-out/recall ball-animation
primitives as a real, already-built precedent for "a pokéball opens and a
Pokémon appears/disappears," should G3b ever want a real visual beat.

Genuinely new, but small: (1) an 8-entry trades data table — nothing
analogous exists in `as-imagined/data/` today, needs a small new generator
script mirroring `gen_species_names.py`'s own shape; (2)
`GetTradeSpecies`/`GetInGameTradeSpeciesInfo`/`CreateInGameTradePokemon`/
`DoInGameTradeScene` themselves, dispatched directly inside `ScriptVM.step()`
the same way `ChoosePartyMon`/`ScriptGetPartyMonSpecies`/`BufferMonNickname`
already are (`GetInGameTradeSpeciesInfo` needs to write real per-trade
values into `TextBuffers`; `CreateInGameTradePokemon` needs real party
mutation — `FieldSpecials`' stateless table is the wrong home for either);
(3) ⚠️ **a second `_literal` symbolic-constant gap, the same shape as G2's
`PARTY_SIZE` finding** — `INGAME_TRADE_MR_MIME` etc.
(`include/constants/trade.h:12-25`, values 0-12) have no case in
`ScriptVM._literal` and would silently resolve to 0, making every trade
NPC's own `setvar VAR_0x8008, INGAME_TRADE_*` set the wrong trade index —
must be fixed alongside implementation, not left to be found later via a
silent wrong-branch bug; (4) the actual party swap — remove the player's
offered mon, insert the newly-constructed traded-in mon at the same slot.
No existing function does this specific splice; `BattleParty`/
`OverworldSession.player_party()` have add/mutate paths but not
remove-and-replace. Bounded, not architecturally new.

**Proposed split**: **G3a** — the trades table, the `_literal` fix, and
`GetTradeSpecies`/`GetInGameTradeSpeciesInfo`/`CreateInGameTradePokemon`
(party mutation, no animation — `DoInGameTradeScene` reduced to a no-op or
a plain message beat for now). Makes Reyley's trade fully playable on its
own. **G3b** — swap the no-op for a real visual beat, reusing the M26B3
ball recall/send-out primitives rather than porting the reference's own
link-trade cinematic engine faithfully (a disclosed simplification,
matching this project's established precedent for other GBA-spectacle
sequences). Purely additive on top of G3a; can ship later without blocking
playability. No G3c — the other 7 trade NPCs are a map-baking question, not
a G3 one; they'll fall out for free once their maps are baked, since the 4
new specials are generic across all 8 table entries.

**Size**: comparable to G1/G2 — one small data table, one `_literal` case,
3-4 new `ScriptVM` dispatch cases, one new party-splice helper. Small and
bounded, not the open-ended item the old build-order phrasing implied.

## G3a — DONE, 2026-08-06

Shipped exactly as scoped above, with three corrections found only by
building it and driving the real corpus:

1. **13 table entries, not 8** — re-derived precisely from `enum
   InGameTradeID`: 4 RSE-only + **9** FRLG-reachable (not 8; Cinnabar Lab's
   Lounge hosts two trades — Electrode AND Tangela — on one map, so 8
   real NPCs cover 9 table rows).
2. **Lickitung's LeafGreen-branch requested species is Slowbro, not
   Golduck** — this doc's own informal summary table above had the
   FIRERED branch; corrected once the generator actually resolved the
   version gate per this project's own established LeafGreen convention
   (`[M27K K-b]`).
3. ⚠️ **A second, deeper, genuinely GENERAL pre-existing bug, unrelated to
   either symbolic-constant gap: `ScriptVM._conditional`'s 3-arg form
   resolved its SECOND operand through `_literal` (constants only), never
   checking whether it was itself a variable.** Reyley's own script does
   `goto_if_ne VAR_RESULT, VAR_0x8009, ...` — a genuine variable-vs-variable
   comparison — and this made every CORRECT trade take the WRONG branch.
   Confirmed general via a full corpus scan: **17 region-wide 3-arg
   conditionals compare two variables, 7 of them this exact shape across
   7 of the 8 real trade NPCs.** Fixed by resolving the second operand via
   `_resolve_number` instead; `setvar`'s own literal-only value argument is
   untouched (`copyvar` is the real var-to-var op in source).

`ITEM_STICK` (Farfetch'd's trade) resolved to a real, already-implemented
item — `ITEM_LEEK`'s own alias (`[M18g]`) — so that one trade ships with a
genuinely functional held item, not just a data value.

New `data/ingame_trades.json` (`scripts/gen_ingame_trades.py`), new
`IngameTradeRegistry`, `GetTradeSpecies`/`GetInGameTradeSpeciesInfo`/
`CreateInGameTradePokemon` dispatched in `ScriptVM.step()`,
`DoInGameTradeScene` a `FieldSpecials` no-op. `Route2_House_
EventScript_Reyley` (Mr. Mime ↔ Abra) driven end to end across all 4 of its
own branches (success/wrong-species/decline/already-traded) against the
real compiled corpus. `m27f_script_vm_test.gd` Section P, 32 assertions,
218/218 total including Z.99. Full overworld regression sweep (19 suites,
`m27h_catching_test.tscn` excluded per its own documented hang) clean —
run in full rather than narrowly scoped, since the `_conditional` fix
touches a core, widely-shared dispatch function.

**G3b (the real visual beat) remains deferred, Rob's own explicit call —
see CLAUDE.md's own answer on why.** The other 7 real trade NPCs remain
blocked on map-baking, not on G3 itself.
