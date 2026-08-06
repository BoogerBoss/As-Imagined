# M27K K-b visual presentation — asset recon

Scope: what `run_new_game()` (`scenes/overworld/overworld.gd:1156`) would
need to become a visually-presented scene instead of the current
text-only implementation. K-b's own doc comment already disclosed the
gap: *"most of [`oak_speech.c`'s 2193 lines] are theatre this project has
no layer for."* This doc catalogs exactly what that theatre is, against
real source and real vendored assets. Recon only — no code changed, no
decisions made, matching this project's Step-0 convention.

## Headline: the real source is bigger than K-b's own citation

K-b cited `src/oak_speech.c` correctly by name, but the file's real entry
point is `StartNewGameSceneFrlg()`, and it drives **three** back-to-back
screens under one continuous task chain, not just Oak's speech:

1. **Controls Guide** (3 text pages, `:713-932`) — button-legend
   explainer, no Pokémon content at all.
2. **Pikachu Intro** (3 text pages, `:934-1101`) — a dedicated animated
   Pikachu (3-piece sprite: body/ears/eyes, real blink/twitch
   `ANIMCMD` tables, `:484-528`) narrating over its own background.
3. **Oak's Speech proper** (`:1103-1791`) — the beats K-b already ported
   the text/logic for: welcome → world → Nidoran release → gender →
   naming → rival → "let's go" → exit.

**Only #3 has any logic in this project today.** #1 and #2 are entirely
unbuilt, text included — this project's own `run_new_game()` starts
straight at Oak's opening lines, with no Controls Guide or Pikachu Intro
screen at all. Worth stating plainly since neither prior K-b nor this
recon's own request named them.

## A. Scene-by-scene breakdown of what's visually missing

Only covering Oak's Speech proper (#3), since that's what `run_new_game`
already has the logic for — #1/#2 would need their own separate
decision on whether they're in scope at all (see Section E).

- **Opening beats** (`:1103-1258`): Oak's portrait appears (see below —
  a tile-blit, not a sprite), a 3-sprite ground platform underneath
  where Oak/player/Nidoran stand, a fade-in from black, `MUS_RG_ROUTE24`
  starts. Text plays beat by beat, already ported by K-b.
- **The Nidoran-released-from-its-ball moment** (`:1170-1204`): a real
  Nidoran♀ sprite loaded through the **general Pokémon front-sprite
  pipeline** (`LoadSpecialPokePic`/`SetMultiuseSpriteTemplateToPokemon`
  — the same machinery battle send-outs use, not a bespoke intro
  asset), released via `CreatePokeballSpriteToReleaseMon` — the
  engine's general-purpose ball-open/emerge animation — with a real cry
  (`PlayCry_Normal`, gated on `IsCryFinished()`). Later recalled the
  same way in reverse (`CreateTradePokeballSprite`) as Nidoran slides
  back into its ball and both sprites are destroyed. **This project
  already has both halves of the reusable machinery this needs** — the
  per-species sprite pipeline and ball send-out particles are both
  built for battle (`[M26B3-6a]` for the Poké Ball particle animation
  specifically) — porting this beat is substantially a hookup, not new
  art.
- **Gender selection is NOT a plain yes/no, contrary to what K-b's own
  implementation assumes.** K-b's `run_new_game()` reuses `YesNoBox` for
  this question. Source shows **no portrait at all** during the choice
  (Oak's portrait is explicitly slid off-screen first, `:1284-1285`)
  and opens a small dedicated 2-item text menu ("BOY"/"GIRL") in its
  own window — closer to this project's own menu-cursor widgets than
  to a yes/no box, though functionally equivalent (two options, pick
  one). Not a visual gap in the portrait sense, but a real divergence
  from K-b's own implementation choice, worth knowing about if this is
  ever revisited.
- **Player-naming and rival-naming are bookended by more than the bare
  keyboard K-b built.** Source shows a preset-name-choice window first
  (NEW NAME + 4 random presets, matching what K-b's own naming screen
  already offers) — K-b already has this part. What's missing: a
  **confirmation screen with the trainer's portrait re-shown**
  ("So your name is {PLAYER}.", yes/no, portrait visible) before
  proceeding, and for the rival specifically, the **player's own
  portrait fades out and the rival's fades in** before that question is
  even asked.
- **Portraits are the dominant asset class, and they are NOT sprites.**
  Oak's, the player's (gender-specific), and the rival's portraits are
  all drawn as BG-layer tile-blits (`LoadTrainerPic` decompresses
  straight into VRAM and stamps a tilemap rect) — a GBA-specific
  technique with no sprite-based equivalent. A Godot port would
  represent these as plain `TextureRect`/`Sprite2D` swaps, which is
  simpler than the source technique, not harder.
- **The exit ("shrink into the overworld")** uses a single hardware BG
  affine scale-down (not the stacked-tilemap-frame tricks
  `intro_frlg.c` uses elsewhere) — conceptually a `Tween` shrinking a
  portrait's scale to zero while a whiteout/blackout fade plays
  underneath. The simplest visual beat in the whole chain to reproduce.

## B. Asset inventory (`graphics/oak_speech/`)

20 real files, ≈13.8 KB combined — small relative to the intro cinematic
(`docs/m27k_cinematic_recon.md`'s own `graphics/intro_frlg/` catalog).

| Asset | Real dims | Role |
|---|---|---|
| `leaf/pic.png` + `leaf/pal.pal` | 64×96 | female player portrait |
| `red/pic.png` + `red/pal.pal` | 64×96 | male player portrait |
| `oak/pic.png` + `oak/pal.pal` | 64×96 | Oak's portrait — **confirmed a distinct asset**, not the same file as the 64×64 in-battle trainer front-pic already partially pulled for `[M26B3]` |
| `rival/pic.png` + `rival/pal.pal` | 64×96 | rival's portrait |
| `platform.png` + `platform.pal` | 32×96 | the 3-sprite ground platform |
| `pikachu_intro/body.png`/`ears.png`/`eyes.png` + shared `pikachu.pal` | 32×64 / 32×32 / 32×8 | Pikachu's 3-piece animated sprite (Pikachu Intro screen only, not Oak's Speech) |
| `bg_tiles.png` (shared) | 128×80 | Controls Guide + Pikachu Intro background |
| `oak_speech_bg.png` + `.bin` tilemap | 16×40 tiles / 1280B map | Oak's Speech proper background (the platform/grass scene) |
| `controls_guide_page_2.bin`/`_3.bin` | 160B each | per-page Controls Guide tilemap swap |

No Nidoran-specific asset exists here — it's pulled from the general
species sprite data this project already imports.

## C. Entry/exit (confirms this project's own scene boundary is right)

Real chain: `main_menu.c`'s NEW GAME branch → `StartNewGameSceneFrlg()`
→ [Controls Guide → Pikachu Intro →] Oak's Speech → naming (a genuine
`SetMainCallback2` swap out to `naming_screen.c` and back, not an
in-place transition) → `CB2_NewGame` (field/overworld setup) →
`CB2_Overworld`. This matches this project's own boundary exactly —
`run_new_game()` already hands off into the live overworld the same
way, confirming K-b's original scene-split decision was correct, only
its visual layer is what's missing.

## D. No exotic GBA tricks — simpler than the cinematic

Confirmed by direct grep: **zero per-scanline HDMA effects anywhere in
this file** (only cleanup `ScanlineEffect_Stop()` calls). What it
actually uses — whole-screen alpha-blend cross-fades (`BLDCNT`/
`BLDALPHA`, uniform coefficient ramped over several frames) and one BG
affine scale-down for the exit — both map onto plain Godot `Tween`s with
no GBA-specific workaround needed, unlike several of the cinematic's own
stacked-tilemap-frame tricks.

## E. Decisions — resolved 2026-08-05, then built the same day

1. **Controls Guide and Pikachu Intro: DEFERRED, Rob's call.** Neither
   screen has any logic or visuals in this project, and neither was
   built in this pass either — `run_new_game()` still starts straight at
   Oak's opening line.
2. **Fidelity target: simplified equivalent, and built.** Portraits are
   real (pulled from source, see §B), the exit is a plain fade rather
   than the BG-affine shrink (recon confirmed no exotic technique is
   actually load-bearing for the beat). The ball-release beat is now
   built too (§G below) — **releasing a RANDOM roster species, not
   source's fixed Nidoran♀**, Rob's own explicit call, fully random
   across all 386, legendaries included (there is no legendary/mythical
   tag anywhere in this project's own species data to filter against
   even if a curated pool had been chosen instead). The platform/
   background scene is still NOT built.
3. **Gender-menu divergence: resolved AWAY from source, Rob's own
   explicit call, not left as K-b's simplification.** Source shows no
   portrait during the choice; this project now shows Red and Leaf
   **side by side, clickable directly** — picking a look IS the answer,
   rather than a text choice followed by a portrait appearing after the
   fact. `YesNoBox` no longer drives this question at all — replaced by
   `OakSpeechOverlay.pick_gender()`. K-b's original 47 assertions
   (`m27k_newgame_test`) never actually drove `_yes_no` through
   `run_new_game()` end to end (confirmed before touching anything), so
   none needed changing; 6 new assertions were added instead (F.01-F.06,
   EXPECTED_TOTAL 47 → 53).
4. **Sequencing against the cinematic:** not combined — built
   independently, since the gender-picker's own scope (mouse-clickable
   portraits) turned out to have nothing in common with the cinematic's
   BG-scroll choreography.

## F. What got built, 2026-08-05

**Assets**: `scripts/gen_oak_speech_assets.py` (new, idempotent, mirrors
`gen_trainer_portraits.py`'s plain-copy pattern — all four portraits are
already indexed "P"-mode PNGs with an embedded palette, confirmed before
writing the script, no GBA tile/palette decode needed) pulls
`oak.png`/`red.png`/`leaf.png`/`rival.png` into
`assets/sprites/oak_speech/`. **`platform.png` added the same day** (also
a plain-copy indexed PNG, 32×96, three 32×32 frames stacked vertically —
confirmed before pulling). `oak_speech_bg.png`/`.bin` (the tiled
background scene) is still NOT pulled — unlike everything else here, that
pair needs a real tile+tilemap decode, not a plain copy, and remains a
separate, larger, undecided task.

**`OakSpeechOverlay`** (`scripts/overworld/oak_speech_overlay.gd`, new)
— a `CanvasLayer` widget matching every sibling field widget's own
established shape (code-built in `_ready()`, not a `.tscn` — confirmed
this project's actual convention for this subsystem, not the more
general "prefer scene-tree-visible UI" guidance, which does not govern
this particular subsystem). `show_solo(which)` swaps a single centered
portrait; `pick_gender()` shows Red and Leaf as real `TextureButton`s
side by side and awaits a click, returning the same BOY/GIRL polarity
`YesNoBox` used to carry; `fade_out()` is the simplified exit. **The
FIRST mouse-clickable widget in this project's overworld field-UI
subsystem** — every sibling (`YesNoBox`, `FieldStartMenu`, ...) is
keyboard/gamepad-only via a central `move()`/`confirm()` dispatch in
`overworld.gd`'s `_unhandled_input`, confirmed by a full grep before
writing this file. `move()`/`confirm()` are exposed on
`OakSpeechOverlay` too, matching the sibling shape, but **deliberately
NOT wired into that central dispatch** — Rob's own "mouse now, keyboard/
gamepad in future" sequencing, stated as a deferral rather than left to
read as the same class of oversight `[M27L L2]` already found and fixed
for this exact question's prior `YesNoBox`.

**`run_new_game()`** now shows Oak throughout his own lines, swaps to
the gender picker for the BOY/GIRL question, shows the chosen portrait
for name confirmation, swaps to the rival's portrait for rival naming,
and shows Oak again for the closing line before fading out.

**Live-driven** via a disposable probe (deleted after, per this
project's own convention) that boots the real `overworld.tscn`, drives
Oak's actual speech via `_box.advance()`, and — confirming a genuine
environment limitation, not a bug — found that headless `Viewport.
push_input()` does **not** route `InputEventMouseButton`/
`InputEventMouseMotion` to `Control` nodes in this project's Godot
build (neither `gui_input` nor `mouse_entered` ever fired on the
target button, despite a correct, sane global rect and a correctly
zeroed `mouse_filter` chain). This is the same CLASS of gap already on
record for `Input.action_just_pressed()` in headless test drivers
(`[M27L L2]`'s own note) — not previously confirmed for mouse/GUI
routing specifically until now, worth remembering for any FUTURE
button-based field widget. Fell back to calling the button's own
handler directly (the established workaround for this whole class of
limitation) to prove the LOGIC: gender correctly resolves to GIRL,
`show_solo("leaf")` fires and the solo portrait's texture updates
correctly, the rival portrait becomes visible during rival naming, and
the flow completes with a real rival name chosen end to end. **Real
mouse-click routing itself is standard `TextureButton` engine behavior,
not custom code, so it is unverified in THIS session (no display
available) rather than untrustworthy** — flagged honestly rather than
claimed as proven, per this project's own live-drive standard.

**Tests**: `m27k_newgame_test` gained section F (6 new assertions,
button visibility defaults, `show_solo`/`hide_all`, `pick_gender()`'s
full async round trip driven via `call_deferred` on the button handler,
the resolved BOY/GIRL polarity) and section G (below), `EXPECTED_TOTAL`
47 → 56, 57/57 including the harness's own Z.99 self-count. Regression:
`m27k_starter_test` 37/37, `m27f_script_vm_test` 136/136, `m27l_save_test`
105/105, `m27f_stage4_test` 63/63, `m27o_field_poison_test` 57/57,
`m27o_whiteout_test` 33/33, `m27i_i4_bag_screen_test` 53/53,
`m27i_bag_test` 47/47, `m27k_kc_nickname_test` 59/59 — all unchanged.

## G. The ball-release beat, 2026-08-05

**`OakSpeechOverlay.release_random_pokemon()`** (new) reuses the exact
ball-sheet asset the battle send-out animation already loads
(`battle_screen_shared.gd`'s own `_BALL_SPRITE`/`_BALL_FRAME_*`
constants — same file, same 2-frame closed/open layout), but does NOT
reuse the battle screen's own tuned `_play_send_out` sequence — confirmed
before writing this that it is not reusable outside battle without its
`BattleParty`/slot-array scaffolding (`_find_mon_slot`, per-slot sprite/
panel caches, `BattleManager` state). Built as a standalone, simpler
sequence instead: ball appears closed → wobbles (3 rotation tweens) →
opens, and a species sprite grows in from zero scale while fading in →
holds 1.2s → ball and sprite both fade out together.

**Species: fully random across all 386, legendaries included — Rob's
own explicit call, 2026-08-05**, after the alternative (a curated table
excluding legendaries/mythicals) was raised and declined. Picked the
same way `RandomTeamGenerator.generate_team()` already does — a random
entry from `PokemonRegistry.get_all_species()`, reading its own `dex`
field, rather than assuming dex ids are a contiguous `[1, 386]` range.
Fed straight into `SpriteRegistry.get_front(dex)`, the same front-sprite
loader the battle screen itself uses — confirmed before writing this
that all 386 real roster species have a real pulled sprite (the only
disclosed gap, dex 0/Spinda's transparent idle-bob frame, doesn't affect
frame-0-only usage here).

⚠️ **NO CRY PLAYS.** Confirmed by a fresh full grep immediately before
writing this: zero audio playback exists anywhere in the live project.
A real per-species cry `.wav` library sits vendored and unwired at
`assets/Essentials_v19.1/Audio/Cries/` — genuinely available if audio is
ever built — but standing up this project's first-ever audio system for
one incidental beat was judged out of scope, matching the existing
no-op precedent already recorded for `playfanfare`/`playse` against
`[M27K K-a]`. The reverse ball-RECALL animation source plays later
(`Task_OakSpeech_ReturnNidoranFToPokeBall`) was also not built — this
pass is the release only.

**Wired into `run_new_game()`** at source's own real placement — the
original opening `_say([OAK_WELCOME, OAK_THIS_WORLD, OAK_INHABITED,
OAK_I_STUDY, OAK_ABOUT_YOURSELF])` batch was split so the release beat
plays between `OAK_THIS_WORLD` and `OAK_INHABITED`, since source pairs
the release with `Task_OakSpeech_IsInhabitedFarAndWide` specifically
(§A4 above), not before or after.

**Live-driven** via a second disposable probe (deleted after): confirmed
the ball becomes visible immediately (closed frame), the released
sprite reaches full scale/opacity mid-sequence with a real (non-null)
texture assigned, both fade out and hide cleanly once the beat ends, and
the message box resumes with exactly `OAK_INHABITED`/`OAK_I_STUDY`/
`OAK_ABOUT_YOURSELF` right after — matching source's real beat
placement, not just "doesn't crash."

**Tests**: new section G (3 assertions) — nothing showing before the
beat, both ball and released sprite hidden again once it ends, a real
texture was assigned. Awaits the full ~2s real sequence end to end
(coroutines require `await` at their own call site in this GDScript
version, so no mid-flight snapshot was possible in an automated test —
the live-drive probe covered that instead).

## H. The ground platform, 2026-08-05

Three `TextureRect`s sliced from `platform.png`'s own 3 vertically-
stacked 32×32 frames, placed side by side as one 288×96-displayed strip
(96px per tile at 3× scale, matching the portraits' own scale factor),
added FIRST in `_ready()` so they draw behind every portrait/ball/
released sprite. **Deliberately NOT source's own 3-separate-sprite
placement at literal GBA screen coordinates** — this project's own
established convention (`YesNoBox`'s own doc comment makes the identical
call) is to not port literal GBA tile coordinates onto a 1024×768 canvas,
so this reproduces the SHAPE (three tiles forming a ground strip) rather
than source's exact pixel placement. Positioned below the ball-release
point and above the message box, so the released Pokémon appears to land
on it and Oak/the player/the rival all appear to stand on it.

Visibility is tied to `show_solo()`/`pick_gender()` (both turn it on) and
`hide_all()` (turns it off) — it is not its own separate toggle a caller
has to remember, since there is no real scenario where a portrait is
shown but the ground under it shouldn't be.

⚠️ **A REAL BUG FOUND AND FIXED WHILE TESTING, WORTH RECORDING FOR THE
NEXT SESSION THAT PULLS A BRAND-NEW ASSET FILE**: a freshly-copied PNG
with no `.import` sidecar yet logs `ERROR: No loader found for resource`
and loads as `null` — but ONLY the underlying sub-resource. The
`AtlasTexture` wrapper object `_platform_frame()` constructs is never
null itself (it's a plain `AtlasTexture.new()`), so a first-draft
assertion checking `tile.texture != null` was **vacuously true** even
while every tile was actually blank — the real signal is
`tile.texture.atlas != null` (the loaded sheet the AtlasTexture slices
from). Fixed by running `godot --headless --editor --quit` once to force
the missing import (the same fix class already on record from the
M26c-2/M25e sessions for texture-cache gotchas), and by correcting the
assertion itself to check the right property. Attempted to break-test
this by removing the `.import` sidecar and separately by hiding the
source PNG entirely — **neither reproduced the original failure a second
time**, because Godot's own `.godot/imported/` cache persists the
compiled texture independent of the source/sidecar's presence once
warm — so this is recorded as a real bug found and a real fix applied,
not as a cleanly-reproducible break-test the way this project's other
guards usually are.

**Tests**: `m27k_newgame_test` section F gained F.02b (3 tiles, each with
a real loaded sheet — checking `.atlas`, not just `.texture`) and F.03b
(`hide_all` hides the platform too), `EXPECTED_TOTAL` 56 → 58, 59/59
including Z.99. Regression: `m27k_starter_test` 37/37,
`m27k_kc_nickname_test` 59/59, `m27l_save_test` 105/105,
`m27f_script_vm_test` 136/136, `m27f_stage4_test` 63/63,
`m27o_field_poison_test` 57/57, `m27o_whiteout_test` 33/33,
`m27i_i4_bag_screen_test` 53/53, `m27i_bag_test` 47/47 — all unchanged.

**Still not built**: the tiled background scene itself (§F's own note —
needs real tile/tilemap decode, a separate task), the reverse ball-
recall animation, and source's BG-affine shrink exit (the plain-fade
stand-in remains). Nothing committed to git, per standing instruction.
