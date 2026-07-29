# M26B7 recon — Catch UI: reference review, current-state review, and implementation proposal

Written 2026-07-29. Recon only — no code written, no assets pulled this session.

M26B7 (was M26n): real in-battle catch-attempt UI — ball throw, shakes, success/break-free
— for the engine's stubbed catch seam, which currently has no visual representation at all.

Reference repo state at time of review: pokeemerald-expansion v1.16.2, HEAD
`74e40e033966421de974398a6777b87945e46c62`, clean tree.

---

## 0. TL;DR

1. **The owed Step 0 is resolved** (§2.4): `LoadBallParticleGfx` loads one of exactly two
   8×64 sheets — `graphics/battle_anims/sprites/particles.png` (rendered with
   **`circle_impact.png`'s palette**, 20 balls) or `particles2.png` (own palette, 8 balls).
   `gold_stars.png` is NOT catch-related (shiny-encounter stars only). The success stars
   are frames of `particles.png` itself (Master Ball tag, anim frame 3).
2. The whole catch presentation is one file, `src/battle_anim_throw.c` (2,648 lines), a
   linear sprite-callback chain with fully-derived timing: throw arc 34f → open/absorb →
   shrink 28f → close → 4 bounces (84f) → N×(28f wobble + 31f gap) → capture (~700f
   total) or break-free (~390f). Every constant is documented in §2.
3. The Godot side already has more than half the primitives from M26B3-6's send-out/recall
   work: the ball sprite helper, the open-particle burst, the pink absorb shader (which is
   literally BALL_POKE's `openFadeColor`), frame-clock waits, and the beat queue.
4. The engine gap is the real constraint: `attempt_catch` is an always-false stub (M22),
   the `catch_attempted` signal carries no shake count, and nothing anywhere handles
   success. **B7 must animate outcomes the engine cannot yet produce** — so the proposal
   adds a small presentation-only seam (case ID with shake count) now, which M29's real
   formula later feeds without any UI change.
5. Proposal: 3 sub-phases (seam+messages, core throw/shake/break-free sequence,
   success/critical/trainer-block) plus a deferred per-ball-variety pass that waits for
   ball roster reality (only 1 of 28 balls exists as an item today). Audio stays out of
   scope per M26's standing rule; every SE cue point is recorded in §2.8 for the future
   audio pass.

Factual correction for the roadmap row: it says the catch seam exists "per M18" — it was
actually **M22 Phase 2** (`docs/m22_recon.md` §5). M18 excluded all Poké Balls.

---

## 1. Reference review — the catch presentation, end to end

### 1.1 Flow and case IDs

Using a ball runs `BattleScript_BallThrow` (`data/battle_scripts_2.s:171`): print
"You used {item}!" (`STRINGID_PLAYERUSEDITEM` — there is no "threw a ball" line), then
`Cmd_handleballthrow` (`src/battle_script_commands.c:10015`) computes odds and a **case
ID** it sends to the controller:

```
BALL_NO_SHAKES(0), BALL_1_SHAKE(1), BALL_2_SHAKES(2), BALL_3_SHAKES_FAIL(3),
BALL_3_SHAKES_SUCCESS(4), BALL_TRAINER_BLOCK(5), BALL_GHOST_DODGE(6)
```
(`include/battle_controllers.h:185-193`). Trainer battles short-circuit to
`BALL_TRAINER_BLOCK` before any odds math. The case ID lands in
`animationData->ballThrowCaseId` and the special anim `B_ANIM_BALL_THROW` (or
`_WITH_TRAINER` for Safari/Wally, `B_ANIM_CRITICAL_CAPTURE_THROW` for critical captures)
is launched. **The animation is entirely case-ID-driven** — presentation never recomputes
the outcome. Post-anim messages by case: `gBallEscapeStringIds` = "Oh no! The Pokémon
broke free!" (0) / "It appeared to be caught!" (1) / "Aargh! Almost had it!" (2) /
"Gah! It was so close, too!" (3); success prints "Gotcha! {mon} was caught!" with the
caught fanfare embedded in the string, then EXP (Gen6+), dex, nickname, party/box —
those tails are overworld-RPG scope, not simulator scope. Success sets
`gBattleOutcome = B_OUTCOME_CAUGHT` (counts as a win); failure just `finishaction`s.
After a failed throw the wild mon replays its front animation + cry
(`AnimateMonAfterPokeBallFail`).

### 1.2 The sprite-callback chain (`src/battle_anim_throw.c`)

Stage by stage, with derived frame counts at 60fps:

| Stage | Key facts | Frames |
|---|---|---|
| Throw arc | ball spawns at **(32, 80)** subpriority 29, arcs to target x, target y−16; duration 34, sine amplitude −40 (`SpriteCB_Ball_Throw/_Arc`) | 34 |
| Ball opens | `StartSpriteAnim(1)` = frames 4→8, 5 ticks each; particles burst (§2.4); mon palette fades toward the ball's `openFadeColor` over 17f (`LaunchBallFadeMonTask(FALSE,…,14,ballId)`) | 10 |
| Mon shrinks | the battler's own sprite rot-scales: inverse scale 256→1152 in +32/frame steps (28f, ends ≈22% size) while pulled down toward the ball (`gMonShrinkDelta`); `SE_BALL_TRADE` at t=11; then invisible | ~31 |
| Ball closes | anim 2 = frames 4→0, 5 ticks each | 10 |
| Bounce | 4 contacts, cosine bounces of amplitude **40/30/20/10**, ground hits at t=16/42/64/84; per-hit `SE_BALL_BOUNCE_1..4` | 84 |
| Pre-shake wait | ball at rest | 31 |
| Wobble cycle ×N | roll right 8f / pivot / roll left 13f / pivot / roll right 5f + 1 decision frame; x-track 0→+3→−2→0 px; rotation ±3 GBA-units/frame = **±4.22°/f** (net −33.75°, +54.8°, −21°, back to 0); `SE_BALL` at each cycle start | 28 each |
| Inter-shake gap | | 31 each |
| **Break-free** | ball reopens (anim 1) + particles + reverse palette fade; mon `BATTLER_AFFINE_EMERGE` (grow from 0.16× over 12f) rising ~1.125 px/f from y2=16; ball destroyed | ~44 |
| **Capture** | ball darkens (`BlendPalettes(…,6,BLACK)`) + `SE_RG_BALL_CLICK` + **3 capture stars** at t=40; un-darken at t=60; fanfare `MUS_RG_CAUGHT_INTRO` at t=95 (all other audio stopped); mon sprite destroyed at t=315; then ball white-blend fade-out over ~32f | ~350 |

Totals: ball-at-rest at **169f (~2.8s)**; a full 3-shake decision point at **346f
(~5.8s)**; break-free ≈ **390f (~6.5s)**; successful capture ≈ **698f (~11.6s)**;
`BALL_NO_SHAKES` instant fail ≈ **213f (~3.6s)**.

Shake-count semantics: on failure the anim plays exactly `caseId` wobbles then releases;
on `BALL_3_SHAKES_SUCCESS` it plays 3 wobbles then captures.

**Capture stars**: 3 sprites from `sBallParticles[BALL_MASTER].spriteTemplate`
(particles.png frame 3), arcing outward with per-star offsets (+10,+2,−3)/(+15,0,−4)/
(−10,+2,−4), duration 24, **toggling `invisible` every frame** (flicker), drawn one
subpriority in front of the ball.

**Critical capture** (`CB_CriticalCaptureThrownBallMovement`): throw SE is `SE_FALL`;
after the arc the ball is *suspended 40px above the ground* and shudders horizontally
(±1px, 6 half-cycles, 34f) before the normal 84f drop; then at most **one** wobble —
success → capture, failure → emitted as `BALL_NO_SHAKES` (no wobble at all) while the
message deliberately shows the 3-shakes-fail string.

**Trainer block** (`BALL_TRAINER_BLOCK`): the arc completes, then the ball is knocked
away off-screen with accumulator physics (`SpriteCB_Ball_Block_Step`), and the anim
script overlays a basic hitsplat on the target 25f later; message "The Trainer blocked
the Ball! Don't be a thief!". **Ghost dodge** exists too (ball arcs down and vanishes).

Caveat for implementers: `src/pokeball.c:488-560+` contains a near-duplicate catch chain
the file itself marks as dead code ("These do not seem to get run") — **port from
`battle_anim_throw.c` only.**

### 1.3 Ball sprites

`gPokeBalls[28]` (`src/pokeball.c:213-382`): per-ball 16×48 sheet = 3 frames of 16×16
(closed / opening / open-overlay), OAM 16×16 AffineDouble, priority 2. Anim sequences:
0 = closed; 1 = open (frames 4→8, 10f); 2 = close (frames 4→0, 10f). Affine anims:
rotate-right (−3/f), rotate-left (+3/f), identity reset, fast-spin (25/f — send-out
only). `graphics/balls/open.png` is a 4th "fully open" tile block overlaid into VRAM for
about half the balls. 28 ball types (`POKEBALL_COUNT`), item→ball via secondary ID.

### 1.4 Particles — the resolved Step 0

`LoadBallParticleGfx` reads `sBallParticles[28]` (`src/battle_anim_throw.c:236-461`),
each entry = {sheet, palette, template(8×8 OAM), openFadeColor, anim index, emitter
task}. Exactly two sheets:

- **`particles.png`** (8×64 = 8 frames of 8×8) paired with **`circle_impact.png`'s
  palette** (`gBattleAnimSpritePal_CircleImpact`, `src/graphics.c:837,843`) — 20 balls.
- **`particles2.png`** with its own palette — 8 balls (Heal, Dusk, Quick, Level, Moon,
  Fast, Heavy, Cherish).

`gold_stars.png` is the shiny-sparkle sheet only (`TryShinyAnimation`) — not catch UI.

Six frame-selection anims (regular flicker loop; Master=frame 3; Net/Dive=4; Nest=5;
Luxury/Premier=6/7 alternating; Ultra/Repeat/Timer=7) and **9 distinct emitter
patterns** (Poke's staggered 16-frame expanding ring; Timer wide ellipse; Dive tall
ellipse; Safari/Net slow circle; Ultra/Nest 10-sprite ring; Great/Luxury two 8-sprite
waves 8f apart; Master's 16-sprite double ring; Premier lissajous; Repeat 12-sprite
cosine-of-sine). Shared spiral stepper, 51-frame particle lifetime. Per-ball
`openFadeColor` table is reproduced in full in the reference report and already
tabulated in CLAUDE.md's M26B3-6 notes — BALL_POKE's is RGB(31,22,30) = the exact
pink `_RECALL_FADE_COLOR = (255,181,247)` the project's blend shader already hardcodes.

### 1.5 How the battle waits

`Controller_WaitForBallThrow` completes when `gDoingBattleAnim` clears **or** the special
anim ends — and the anim deliberately clears `gDoingBattleAnim` early on capture (at
fanfare start, t=95) so "Gotcha!" prints while the ball fade-out still plays. Healthboxes
are re-prioritized at each of these points. The anim script's own `waitforvisualfinish`
holds until the ball sprite self-destroys.

### 1.6 Sound cue map (recorded for the future audio pass; audio NOT in B7 scope)

`SE_BALL_THROW` (throw; `SE_FALL` if critical) → `SE_BALL_OPEN` (every particle burst,
both absorb and break-free) → `SE_BALL_TRADE` (suck-in, shrink t=11) →
`SE_BALL_BOUNCE_1..4` (per contact) → `SE_BALL` (each wobble start; every frame of the
first critical shudder cycle) → `SE_RG_BALL_CLICK` (capture click) →
`MUS_RG_CAUGHT_INTRO` then `MUS_CAUGHT` (fanfare + BGM, embedded in the Gotcha string).
There is no dedicated break-free SE — it's `SE_BALL_OPEN` plus the mon's cry.

---

## 2. Current-state review (Godot side)

What exists (full detail with line numbers in the survey this section summarizes):

- **Seam (M22 Phase 2)**: `ItemManager.attempt_catch()` is a one-line always-false stub
  (`item_manager.gd:1364`); `catch_attempted(user, target, item, caught)` fires from
  `_do_item_use`'s `BATTLE_USE_THROW_BALL` branch (`battle_manager.gd:8477-8482`),
  correctly targets the opponent, consumes the turn, sits in the front action tier.
  **No shake count exists anywhere; nothing branches on `caught == true`; the signal has
  zero non-test listeners.** `PokemonSpecies.catch_rate` is data with zero readers.
- **Reachability**: the player cannot throw a ball — the M25h-1.4 bag overlay's roster is
  3 hardcoded non-ball items. Only tests call `queue_item_for(0, 1)`. Only 1 of 29 balls
  exists as a `.tres` (Poké Ball, item 1). Trainer AI never uses balls. There is no
  wild-battle mode; nothing blocks throwing in trainer battles.
- **Assets (M26B3-6)**: `gen_ball_sprites.py` already pulled **all 29 ball sheets + the
  shared `particles.png`** into `assets/sprites/battle_ui/balls/` (index-0 transparency
  tagged). Gaps found by this recon: **`particles2.png` was not pulled** (needed by 8
  balls), and the pulled `particles.png` carries its own embedded palette — the
  reference renders it through `circle_impact.png`'s palette for 20 of 28 balls, so the
  current colors need verification against source before per-ball work (B3-6 only ever
  shows it as the Poké Ball burst).
- **Reusable animation infra (M26B3-6, all in `battle_screen_shared.gd`)**:
  `_make_ball_sprite` (AtlasTexture over poke.png, center pivot), the throw arc pattern
  (separate x/rotation tween + two-leg sine y tween), `_spawn_ball_open_particles`
  (16 particles, one per frame staggered — matching source's Poke emitter cadence,
  though as straight spokes rather than the spiral stepper), the pink
  `_apply_blend_material` shader (= BALL_POKE openFadeColor), `_wait_anim_frames`
  (1/60s wall-clock), recall-shrink, and the `_pending_beats` queue with `anim_async`
  for multi-phase coroutines. The ball/emerge already runs on EVERY send-out.
- **Message ownership**: `docs/m26_d3_recon.md` §6 explicitly assigns catch text to B7.
  Today a throw produces only "X used Poké Ball!" via `item_action_used`.
- **Tests**: `m22_item_action_test.gd` Section K (5 tests — stub behavior, targeting,
  turn tier); `m26_trainer_category_party_test.gd` pins the recall/throw constants
  against source. Nothing visual.
- **Boundaries** (`overworld_scope.md`): M27H owns the encounter TRIGGER, **M29 owns the
  catch MATHS** (formula, ball modifiers, Repel etc.); the per-ball particle variants
  carry-in says "fully researched, do not re-derive, sequence late." B7 is presentation
  only and must not implement the formula.

---

## 3. The design problem B7 must solve

The reference animation is driven by a **case ID the mechanics compute**. This engine's
mechanics are a stub that returns a bare `false`. Three consequences:

1. **A seam extension is required**: the anim needs shakes 0–3 / success / critical /
   trainer-block, and `catch_attempted(… caught: bool)` cannot express that. The clean
   shape is `attempt_catch` returning a small result Dictionary
   (`{caught: bool, shakes: int, critical: bool}`) and the signal gaining that payload —
   M29 later replaces the stub's internals and the UI never changes. (Breaking-change
   precedent: M17b's int→Dictionary migration.)
2. **The stub must produce presentation-quality failures**: always-0-shakes would read as
   broken. Proposal: stub keeps `caught = false` but rolls shakes 0–2 uniformly (never 3
   — 3 shakes + failure is the rare "so close" case source reserves for a real odds
   loss), deterministic under a seeded RNG for tests.
3. **Success is unreachable**, so the success/critical paths need a test-only forced
   outcome hook (`set_catch_override()` — the M10 `set_trainer_ai()` seam precedent).
   Real success wiring (mon leaves field, battle ends as caught) stays with M29/M27H;
   B7 ships the visuals and the hook.

A fourth wrinkle is an opportunity: this simulator's battles are either trainer battles
or wild/test fixtures (no `TrainerData`). Source's rule is trainer battle ⇒
`BALL_TRAINER_BLOCK` — the trainer bats the ball away. Implementing that case makes ball
throws *correct* in every battle the simulator can currently produce, and it is cheap
(arc + deflection + existing hitsplat asset).

---

## 4. Implementation proposal

### B7-1 — Seam extension, dispatch, and messages (1 session)

- `attempt_catch` → result Dictionary; `catch_attempted` gains the payload; stub rolls
  shakes 0–2; trainer-attached battles resolve to `trainer_block` before the stub
  (mirroring `Cmd_handleballthrow`'s early-out); `set_catch_override()` test hook.
- Battle-screen listener on `catch_attempted` → one `anim_async` catch beat (the
  F1-recon beat contract: damage-order beats don't apply here; a throw is its own turn
  action). Autoplay/headless bypass like every other beat.
- Message lines per case from `gBallEscapeStringIds` + Gotcha + trainer-block, enqueued
  after the anim beat (text ownership per D3 recon).
- Rewrite Section K assertions for the new payload (the M26B3/B5 lesson: changing a
  seam means rewriting its tests, and that is expected, not incidental).

### B7-2 — The core sequence (1–2 sessions)

Throw arc → open+particles+absorb-fade → mon shrink-with-pull → close → 4-bounce →
N wobbles → break-free, all against §1.2's constants at 1× GBA timing (the MonAnimator/
B3-6 fidelity standard). New pieces beyond B3-6 reuse: target-mon shrink (rot-scale +
downward pull — distinct from the recall shrink), the wobble cycle (rotation ±4.22°/f
with the roll/pivot x-track), bounce cosine physics, and the break-free emerge (the
send-out emerge already exists; parameters differ slightly). Failed-throw epilogue:
replay the target's species entry animation (the engine's `MonAnimator` equivalent of
`AnimateMonAfterPokeBallFail`).
Acceptance: a seeded battle shows 0/1/2-shake break-frees frame-matching §1.2's budget
(~213f/~270f/~330f to message).

### B7-3 — Success, critical capture, trainer block (1 session)

- Success (via override hook): 3 wobbles → darken + 3 flickering arc stars → un-darken →
  white fade-out; "Gotcha!" message; battle-end handling stops at "visuals + message"
  (no party/box — engine work, M29).
- Critical capture: suspended shudder variant + single wobble (hook-driven; real
  trigger is M29's).
- Trainer block: deflection physics + hitsplat (reuses `physical_impact.png`) + message.
  This is the one case reachable in normal play immediately.
- Optional enabler (Rob decision): add Poké Ball to the flat bag list so the block/fail
  paths are reachable by hand before M26E2's pocket tabs.

### B7-4 — Per-ball variety (DEFERRED — do not build yet)

Pull `particles2.png`, verify/fix the particles-vs-circle_impact palette pairing, add
the 27 missing ball `.tres` items, port the 9 emitter patterns and per-ball
openFadeColors (both already fully tabulated — CLAUDE.md B3-6 notes + this recon).
Blocked-by-reality: ball variety has no consumer until M29 gives balls mechanics.
Matches the overworld-scope carry-in's "sequence late."

Out of scope: audio (M26 standing rule; cue map preserved in §1.6), ghost dodge (no
ghost-marowak mechanic), Safari/Wally trainer-visible throws (`_WITH_TRAINER` — no
player battler sprite exists to animate), dex/nickname/party tails (RPG scope), the
catch formula itself (M29).

---

## 5. Decisions needed (Rob)

1. **Seam shape**: result-Dictionary + widened signal (recommended) vs. a second
   parallel signal keeping `catch_attempted` stable.
2. **Stub shake behavior**: random 0–2 (recommended) vs. always 0.
3. **Trainer-block case in B7-3**: ship it (recommended — it's the only case real play
   can reach, and it's authentic) vs. keep balls test-only.
4. **Bag enabler**: add Poké Ball to the flat item list now, or leave throws
   test/override-only until M26E2's pocket tabs.
5. **Confirm B7-4 deferral** and audio deferral.
