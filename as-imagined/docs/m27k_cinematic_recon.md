# M27K opening cinematic — Step-0 recon

Scope: the opening cinematic reinstated into M27K's roadmap row 2026-08-05
(Rob's call, reversing that row's own earlier "no opening cinematic"
exclusion). This doc is the Step-0 source recon that reinstatement's own
CLAUDE.md note calls for, written before any implementation, per this
project's standing discipline. No code changed in this pass — recon only.

## The headline correction: wrong files were cited before

K-a's own Step 0 (`[M27K K-a]`, CLAUDE.md) cited `title_screen.c` (873
lines) as its source for the title/naming/new-game-flow half of this
milestone. That citation is real but **reads the wrong branch for this
project**. `src/title_screen.c:564-570`:

```c
void CB2_InitTitleScreen(void)
{
    if (IS_FRLG)
    {
        CB2_InitTitleScreenFrlg();
        return;
    }
    switch (gMain.state)
    { ... }  // the 800+ remaining lines: Emerald's Rayquaza title screen
}
```

`IS_FRLG` is true for this project's own target (Kanto/FRLG, per this
file's standing framing). So every line of `title_screen.c` after 570 —
the Rayquaza logo load, the Emerald-specific BG setup, all ~800 of the
873 lines K-a's Step 0 measured — **is dead code for this project's own
compiled path**, immediately superseded by a return into
`title_screen_frlg.c` instead. This is the same mistake class already on
record in this file twice this session alone (the Birch/Oak correction,
`[M27K K-a]`'s own note on it) — a file-scoped measurement standing in
for a source-scoped one, this time landing on the wrong FILE entirely
rather than the wrong grep. Recorded here rather than silently
corrected, per this file's own convention.

**The real files for this milestone's remaining scope are
`src/intro_frlg.c` (2796 lines) and `src/title_screen_frlg.c` (1362
lines)** — neither was cited anywhere in K-a, K-b, K-c, or K-c2.

## A. What the cinematic actually is

One state machine (`struct IntroSequenceData`, `intro_frlg.c:140-158`),
driven by a single task (`Task_CallIntroCallback`, `:1089-1098`) stepping
a chain of `IntroCB_*` callbacks. Six real scenes, roughly 1200-1300
frames (~20-22s) end to end at 60fps:

1. **Copyright screen** (`SetUpCopyrightScreenFrlg`, `:926-999`) — a
   static bg image, palette fade in, hold ~140 frames, fade out. Also
   runs a GameCube multiboot handshake concurrently — Colosseum/XD
   bonus-disc connectivity, irrelevant to a port.
2. **GF logo** (5 sub-states, `IntroCB_Init` through
   `IntroCB_GF_RevealLogo`, `:1100-1278`) — theatric-bars window reveal,
   flying star + sparkle sweep, GAME FREAK wordmark + logo cross-fade,
   PRESENTS sprite. ~300 frames.
3. **Scene 1 — grass close-up** (`IntroCB_Scene1`, `:1280-1353`) — grass
   sway animation, fade from white, zoom + scroll-off. **This is where
   the intro's single music cue starts** (`MUS_RG_INTRO_FIGHT`, `:1322`)
   and plays uninterrupted through scenes 2 and 3.
4. **Scene 2 — wide shot → close-up pan** (`IntroCB_Scene2`,
   `:1416-1499`) — small Gengar/Nidorino sprites in a panning forest,
   then a BG-layer swap (texture-atlas trick: wide-shot art and
   close-up art stacked on one tilemap) into the close-up crop.
5. **Scene 3a — entrance** (`IntroCB_Scene3_Entrance`, `:1541-1596`) —
   Nidorino slides in, Gengar scrolls in behind a window mask, a
   foreground grass clump drifts past.
6. **Scene 3b — the fight** (`IntroCB_Scene3_Fight`, `:1718-1849`) — a
   16-state scripted choreography: Nidorino's cry, Gengar's attack,
   Nidorino's recoil + dust clouds, two wind-up hops, Nidorino's leap,
   a handoff from BG-scroll Gengar to a 4-sprite "Gengar back" pose, an
   affine zoom-in on both combatants, fade to white then black.

**Skip mechanism, confirmed and simple**: `Task_CallIntroCallback` checks
`JOY_NEW(A_BUTTON | START_BUTTON | SELECT_BUTTON)` once per frame, before
any scene logic — any of the three buttons at any point jumps straight
to `IntroCB_ExitToTitleScreen`, skipping everything remaining in one
step. There is no scene-by-scene skip.

**Audio**: exactly two dedicated intro-specific songs, both with real
vendored MIDI assets — `MUS_RG_GAME_FREAK` (`mus_rg_game_freak.mid`,
played once at the GF-logo star reveal) and `MUS_RG_INTRO_FIGHT`
(`mus_rg_intro_fight.mid`, started once at scene 1 and carried through
scenes 2-3 with no change). One `PlayCry_ByMode(SPECIES_NIDORINO, ...)`
call for Nidorino's cry, using the general per-species cry subsystem
rather than an intro-specific asset. `mus_rg_new_game_intro.mid` and
`mus_rg_caught_intro.mid` are real adjacent vendored files but belong to
other parts of the boot/new-game flow, not this cinematic.

**Graphics**: ~30 real, small (100B-4.3KB) sprite-sheet/BG-tileset files
under `graphics/intro_frlg/` (copyright bg, GF-logo wordmark/star/
sparkles, per-scene bg/mon art). Authentic pixel art, not placeholders —
several exploit a GBA-specific trick (animation frames stacked
vertically on one tilemap, "animated" by changing the BG Y-scroll
register) that has no direct Godot equivalent and would need
`AnimatedSprite2D`/`AnimationPlayer` instead.

**No save/flag/var interaction anywhere in either file** — confirmed by
full-file grep for `gSaveBlock`/`FlagGet`/`FlagSet`/`VarGet`/`VarSet`,
zero matches in `intro_frlg.c` or `title_screen_frlg.c`. This half of
M27K is purely presentational.

## B. Control flow and what it hands off to

Real chain (`EXPANSION_INTRO == TRUE`, the reference's own default):
`AgbMain` boot → `CB2_InitCopyrightScreenAfterBootup` (`intro.c:1139`,
also does `LoadGameSave`/`Sav2_ClearSetDefault` — save-loading lives
here, at bootup, not in the cinematic) → `SetUpCopyrightScreen()` →
(FRLG) `SetUpCopyrightScreenFrlg()` → `CB2_WaitFadeBeforeSetUpIntro` →
`CB2_ExpansionIntro`/`Task_HandleExpansionIntro`
(`expansion_intro.c` — an rh-hideout expansion-specific bonus intro, **not
part of vanilla FRLG**, out of this recon's scope if it's ever relevant)
→ `CB2_SetUpIntroFrlg` → the six-scene cinematic above →
`IntroCB_ExitToTitleScreen` (`:1902-1921`) → `SetMainCallback2(
CB2_InitTitleScreen)`, which (per the headline correction above)
immediately redirects into `CB2_InitTitleScreenFrlg`.

## C. The FRLG title screen itself

Not a static screen — a genuine looping animation (`title_screen_frlg.c`,
gated `#if IS_FRLG`, further forked `#if FIRERED`/`#elif LEAFGREEN` for
several assets). `CB2_InitTitleScreenFrlg` (`:381-433`) loads the title
logo, box-art Pokémon, and border BGs, starts `MUS_TITLE`
(`mus_title.mid`), then runs a 6-scene internal state machine
(`enum TitleScreenScene`, `:30-38`):

- **INIT** → **FLASHSPRITE** (a per-scanline HDMA "light sweep" across
  the logo, `UpdateScanlineEffectRegBuffer`) → **FADEIN** (the box-art
  Pokémon color-pulses into view) → **RUN** (the idle/interactive loop:
  ambient flame/leaf particles — FireRed vs. LeafGreen forked assets —
  a periodic slash-sweep sprite, blinking "PRESS START").
- From RUN: **A/Start** → **CRY** (plays the box-art mon's cry, fades to
  white) → `CB2_InitMainMenu` (save-slot selection, confirmed by name).
- From RUN: **45-second idle timeout** (2700 frames) → **RESTART** →
  `CB2_InitCopyrightScreenAfterTitleScreen` → **re-runs the entire
  copyright screen + cinematic from the top.** An idle title screen is
  not a silent no-op; it loops the whole intro again.

**Per-version fork, resolved by Rob 2026-08-05: FireRed.** The box-art
Pokémon is hardcoded per build (`TITLE_SPECIES`, `:40-44`) — Charizard
for FireRed, Venusaur for LeafGreen — with matching wordmark logo
(`game_title_logo.png`, the single largest asset in either tree at
5.6-5.9KB), particle species (flames for FireRed vs. leaves + streak for
LeafGreen), and palette. **This is a deliberate mix, not a cascade**: the
cinematic and title screen use FireRed's assets (Charizard box art, red
wordmark, flame particles), while `[M27K K-b]`'s own player-sprite
(`_PLAYER_BACK_PIC = Leaf`) and LeafGreen name-preset-list choices stand
unchanged — Rob's explicit call when the tension was raised, not an
oversight to reconcile later. A player named from LeafGreen's list
playing as Leaf will see a FireRed-branded title screen; that is the
shipped shape, not a bug.

## D. Decisions — five resolved by Rob 2026-08-05, one still open

1. **Fidelity target: DEFERRED, not building the cinematic itself now.**
   Rob's explicit call, after the fidelity-vs-effort tradeoff above was
   raised — record the remaining decisions below so they're settled
   whenever this is picked back up, but the six-scene Gengar/Nidorino
   sequence is not being authored this session. Nothing downstream of
   this recon should assume the cinematic exists yet.
2. **Expansion-intro bonus scene: EXCLUDED.** `CB2_ExpansionIntro`/
   `Task_HandleExpansionIntro` (an rh-hideout-specific addition ahead of
   the copyright screen, not vanilla FRLG) is out, consistent with this
   project's existing pattern of excluding expansion-only additions
   (RKS System, Skill Link, Good As Gold, Illusion, Perish Body,
   Suction Cups, per the M17n exclusion list). The real chain for this
   project is therefore copyright screen → cinematic → title screen
   directly, with no bonus scene between the first two.
3. **FireRed-vs-LeafGreen asset fork: FireRed, deliberately mixed with
   the existing Leaf-sprite convention.** See Section C above — Charizard
   box art, red wordmark, flame particles for the title screen/cinematic,
   while the player sprite stays Leaf and name presets stay LeafGreen's
   list. Not a cascade; both stand as shipped.
4. **The 45-second idle-loop-back-to-cinematic behavior: DROPPED.** An
   idle title screen sits indefinitely (blinking PRESS START, ambient
   flame particles) rather than replaying the copyright screen and full
   cinematic on a 45-second timeout. A real, deliberate divergence from
   source's own `TITLESCREENSCENE_RESTART` behavior, not an oversight.
5. **Skip-ability: carries over directly, no decision needed.** Source's
   A/Start/Select skip-to-title (Section A) is simple enough to port
   as-is whenever the cinematic itself is built.
6. **STILL OPEN: sequencing against the rest of M27L's boot path.**
   `[M27L L4]` already built the real boot chain (`main.tscn` → Start
   Adventure → slot list → field) and deliberately left `TitleScreen`
   NOT installed as the project's `main_scene`, "a decision for Rob, not
   an oversight." This cinematic sits chronologically BEFORE that title
   screen in source's own chain (cinematic → title screen → main menu),
   so its own boot placement is naturally the same still-open decision
   as L4's, not a separate one — revisit both together whenever either
   is picked up.

## What this recon does not cover

`expansion_intro.c` itself (flagged in D.2, not read). `intro.c`'s own
non-FRLG scene-1-load path (irrelevant — this project is FRLG-only).
The GameCube multiboot handshake inside the copyright screen (source
confirms it runs concurrently with the copyright screen's visual state
machine but has zero visual output of its own — a networking feature,
not a cinematic beat, safe to drop without recon). Nothing in this
document should be read as authorizing implementation — that is a
separate decision, per this milestone's own reinstatement note.
