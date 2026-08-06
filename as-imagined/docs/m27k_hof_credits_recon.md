# M27K Hall of Fame + credits — Step-0 recon

Scope: Hall of Fame and end credits, named in M27K's own roadmap row
("Hall of Fame and credits last") but explicitly flagged "unscoped, no
Step 0 done yet" until now. This doc is that Step 0 — recon only, no
code changed, no decisions made, matching this project's standing
discipline.

## Headline: two real files, and the wrong-file trap pre-empted

Confirmed before reading anything else, per the pattern already caught
twice this session (the opening cinematic, the title screen): this
project targets `IS_FRLG`, and there are FRLG-specific and generic
variants of both systems.

- `src/hall_of_fame_frlg.c` (1280 lines) is the real file — its only
  caller, `EnterHallOfFame()` (`post_battle_event_funcs.c:95-125`),
  calls `CB2_DoHallOfFameScreenFrlg` by name. `src/hall_of_fame.c`
  (1538 lines, `CB2_DoHallOfFameScreen`, a differently-named function)
  is a separate, unused-for-this-project file.
- `src/credits_frlg.c` (1558 lines) is the real file. `src/credits.c`
  (1627 lines) is entirely wrapped `#if !IS_FRLG` — dead code for this
  build, confirmed by direct inspection.

## A. Hall of Fame — trigger and scene-by-scene

**Trigger chain**: beating the Champion
(`PokemonLeague_ChampionsRoom_Frlg`'s `trainerbattle_no_intro
TRAINER_CHAMPION_*` entries) → `warp MAP_POKEMON_LEAGUE_HALL_OF_FAME` →
that map's own `OnFrame` script plays Oak's congratulations, a
ball-placement/flash overworld effect
(`FLDEFF_HALL_OF_FAME_RECORD_FRLG`), fades to black, then `special
EnterHallOfFame` → `EnterHallOfFame()` heals the party, sets the
game-clear flag, awards the Champion Ribbon, and hands off to
`CB2_DoHallOfFameScreenFrlg` — the actual screen this recon covers.

**Scene sequence** (`Task_Hof_*` chain, `hall_of_fame_frlg.c:309-708`):
init/fade-in with `MUS_HALL_OF_FAME` → copy each live party Pokémon into
a `HallofFameMon` record (species/OT-id/personality/level/shiny/
nickname) → (save path only) append to a ring-buffer save slot, "SAVING…
DON'T TURN OFF THE POWER" → each Pokémon flies in one at a time to a
fixed on-screen position, cry plays, dex/nickname/species/gender/level/
ID text prints, earlier Pokémon dim via palette fade as the next arrives
→ "Welcome to the Hall of Fame!" + applause SFX + ~400 frames of falling
confetti sprites → a trainer-card-style player front sprite slides in,
prints Name/Trainer-ID/total play time, "League Champ" message → A
button exits, BGM fades, screen fades to black.

**A second, separate entry point exists**: `CB2_InitHofPC()`/
`ReturnFromHallOfFamePC()` (`:710-961`) is a read-only **browsing**
screen reached from a PC in the overworld (not investigated further —
its own caller is a PC interaction script outside this recon's two
files), letting the player page back through every saved team. Confirms
Hall-of-Fame data is meant to be revisited later, not just shown once.

**Hand-off at the end**: not directly to credits and not back to a
playable field either. `SetWarpsToRollCredits()` warps the player to
`MAP_INDIGO_PLATEAU_EXTERIOR` and sets a one-shot scene-sequencing var —
that map's own `OnFrame` script runs a real scripted farewell cutscene
(rival and Oak both walk out of the League building and leave, the
player turns and runs off) **before** it calls `special
CB2_StartCreditsSequence`. Credits are not chained directly off Hall of
Fame; there's a whole intermediate overworld scene between them.

## B. Credits — structure

**Trigger**: exactly one real call site, `IndigoPlateau_Exterior_Frlg`'s
own map script, after the farewell cutscene above finishes.

**Real shape, confirmed**: the classic "scroll through named Kanto
locations with staff-credit text over a darkened map view, four
dedicated full-screen Pokémon-reveal interludes, ending on copyright +
THE END cards" sequence. One master state machine, `RollCredits()`,
dispatches a linear script table (`sCreditsScript[]`) of five command
types: `PRINT` (a role + name-list text block), `MAPNEXT`/`MAP` (load a
real Kanto map and scroll the camera across it — confirmed via real
table entries: `LOADMAP(MAP_ROUTE23, 11, 107, 1), SCROLL(0, 1, 0x0500)`
and 12 more, retracing the player's own Kanto route), `MON` (Charizard,
Venusaur, Blastoise, Pikachu, in that order — a dedicated full-screen
scene: map view torn down, a Poké Ball graphic with a species-specific
palette, a BG-affine zoom-in reveal of a white circle backdrop, the
Pokémon's cry plays), and `THEENDGFX` (two static full-screen cards:
copyright, then "THE END").

**What it hands off to**: **not** back to a playable field. `CB2_Credits`
case 2 (reached once the terminal fade completes) calls `SoftReset(
RESET_ALL)` — the game soft-resets to the title screen. There is no
"resume playing" exit from credits.

## C. Assets

**Hall of Fame owns almost nothing dedicated**: one background
(`graphics/misc/hall_of_fame.png`, 437 bytes) — no dedicated
`graphics/hall_of_fame/` directory exists. The confetti sprite is a
**shared** asset (`graphics/misc/confetti.png`), also used by the
in-game Contest system elsewhere — not Hall-of-Fame-exclusive.

**Credits owns a real dedicated tree**: `graphics/credits_frlg/`, 47
files, ~192KB total — the white-circle reveal backdrop, 2-layer window
graphics per revealed species (Charizard/Venusaur/Blastoise/Pikachu, one
Venusaur file explicitly named `_unused`), a shared Poké Ball graphic
with 4 species-specific palettes, THE END and copyright cards, and
walking player/male/female/rival sprites plus 3 terrain-appropriate
ground sprites for the map-scroll segments. All individual files small
(600B-2.1KB).

## D. Rendering technique — mixed complexity, not uniform

**Hall of Fame itself is close to plain-fades-suffice**: palette fades,
one alpha-blend compositing effect (`BLDCNT`/`BLDALPHA`) used both to
dim previously-shown Pokémon and as a "border fade" transition, plain
sprite fly-ins. No scanline-DMA tricks (`ScanlineEffect_Stop()` is only
ever called to halt a leftover effect, never to start one).

**Credits is more exotic, genuinely**: a palette-darken blend dims the
map while text prints over it; a **progressive** hardware-window-open
animation (`WIN0V` shrunk by one scanline pair per frame, not snapped
open) reveals the letterboxed map view; the four Pokémon-reveal scenes
use a real BG affine transform ramping a zoom scale from 0 to full size
frame-by-frame. All three map onto ordinary Godot primitives (a masked
`Control`/clip-rect animation for the window-open, a scale `Tween` for
the affine zoom) — genuinely reproducible, but each needs recognizing
it's a *progressive* per-frame effect, not an instant cut, the same
"technique differs, beat doesn't" pattern already established for the
opening cinematic and Oak's speech.

## E. Save/flag interaction — this is real persistent state, not cosmetic

Unlike the opening cinematic and Oak's speech (both purely
presentational, confirmed zero save interaction), **this system has a
real, meaningful save-data surface this project would need to model**:

1. **A permanent "has beaten the Champion" flag** (`FLAG_SYS_GAME_CLEAR`)
   — set on first Hall-of-Fame entry, checked on every subsequent one to
   decide whether to load existing records or start fresh.
2. **A persistent, size-capped ring buffer of past teams** — up to 50
   `HallofFameTeam` records, each 6 `HallofFameMon` entries (species/
   level/shiny/nickname/OT-ID), written to a real dedicated save-sector
   category (`SAVE_HALL_OF_FAME`, 2 sectors) at Hall-of-Fame-entry time,
   readable later from the separate PC-browsing screen. Oldest team
   evicted once full.
3. **A crash-safe continuation pointer** (`gGameContinueCallback`) set
   during the save write, so a soft-reset mid-save resumes into the
   display-only variant rather than re-saving — confirming source treats
   this write as a real, resumable operation.
4. **Two short-lived, self-clearing script variables** used only to
   sequence the one-time post-credits farewell cutscene, reset to 0 once
   it's done.

This project's own save system (`[M27L]`, complete) currently has no
concept of "has beaten the game" or a saved-teams history — both would
be new fields on top of what `SaveManager`/the slot payload already
carries, not a reuse of anything that exists today.

## What this recon does not cover

The PC-browsing entry point's own real trigger (what script/NPC in the
overworld actually opens it) — flagged, not traced. The `ComputerScreenOpen/
CloseEffect` CRT-wipe transition it reuses — a shared, pre-existing
effect implemented elsewhere in source, not read here. Nothing in this
document should be read as authorizing implementation — recon only.
