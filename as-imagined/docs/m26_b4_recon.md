# M26B4 — In-battle weather visuals: full Step 0 recon

## ⚠️ OPEN ITEMS — read before treating M26B4 as closed

B4-0 → B4-3 are all shipped (2026-07-27) with a real capture pass, 95 new
assertions, and 12 regression suites green. **Two things are deliberately still
open.** Neither is a known defect; both need Rob rather than more code.

**OPEN 1 — Sun's appearance is a LOOK-CALL for Rob, not a correctness gap.**
After the affine fix (§8's capture-pass notes) it is mechanically
source-accurate: the ray shrinks 3.2× → ~1.28× over its 60 frames, rotates, and
carries the script's own 13/16 alpha. It still reads as a large pale-yellow
diamond rather than a beam. That is because `sunlight.png` is *itself* a solid
32×32 diamond — verified by direct pixel dump, not assumed — so a faithful
render genuinely is what source draws; it simply carries differently on a
1024px canvas than a 240px one. The cheap levers are `_SUN_RAY_ALPHA` and
`_SUN_RAY_AFFINE_START`. **Do not tune either without Rob looking first** — the
same call he already made for sandstorm, where the source-faithful fix was the
one backed out.

**~~OPEN 2~~ — CLOSED 2026-07-27.** Rain (both variants), Hail, Sandstorm and
Snowscape were all re-captured against current code in a second non-headless
pass; zero leaked effect nodes again, driver deleted. All four confirmed
correct:

- **Rain**, both the move and the shorter per-turn variant — drops fall
  down-and-right at a good density, screen dims and releases cleanly.
- **Hail** — crystals fall onto the battler positions, and the BG-only tint
  still behaves exactly as intended (backdrop dims, sprites and health boxes
  stay crisp). This remains the reference shot for correct layering.
- **Snowscape** — the best-reading of the five: flakes fall STRAIGHT DOWN,
  which is the `x2++ … x2--` net-zero source quirk faithfully reproduced rather
  than "corrected" to a diagonal, under the blue-grey `RGB(11,18,22)` tint.
- **Sandstorm** — scrolls and blends as before, in its deliberately
  over-everything layering (see below).

**Not open, for the avoidance of doubt** — these are settled decisions recorded
at their own code sites, and should NOT be "fixed": sandstorm's layer drawing
over the sprites (Rob's call, source-faithful fix deliberately backed out), and
Snowscape showing snowflakes on use then hail per turn (a known consequence of
the `[D2 batch]` Hail/Snow collapse; see the M35 roadmap note).

---

**Status of the recon itself: COMPLETE.** Supersedes the incomplete first-pass Step 0 recorded in
`CLAUDE.md`'s own M26B4 roadmap entry (2026-07-27), which explicitly left two
things unchecked. Both are now checked, and the answer to the second one
**changes this item's shape**.

All citations are against the canonical checkout,
`/home/rob/GodotAsImagined/reference/pokeemerald_expansion` (HEAD `74e40e0339`).

---

## 0. Executive summary

The first pass's headline finding — **there is no persistent battle weather
renderer in source** — is CONFIRMED, with direct proof rather than absence of
evidence (§1).

But its proposed consequence was **wrong**. It proposed splitting B4 into
*(a)* four real move animations and *(b)* a persistent indicator that "would be
ORIGINAL DESIGN with no source basis" and therefore "a decision point for Rob."

**There is a real, fully source-backed, recurring in-battle weather visual.**
It just isn't a renderer — it is a **complete weather animation replayed every
single turn**, driven from end-of-turn alongside the "Rain continues to fall!"
message that this project already implements (§2).

So **no original design is required**, and item *(b)* as framed is moot. The
real split is:

- **B4-1** — the four weather animations (Rain / Sun / Sandstorm / Hail).
- **B4-2** — the trigger wiring (per-turn replay + set-by-ability).

One genuine judgement call for Rob survives, and it is a pacing question, not a
design-gap question — see §7.

---

## 1. There is no persistent battle weather renderer — confirmed

The first pass asserted this from absence of evidence. It is now positively
proven, five independent ways:

1. **No `battle_weather.c` exists.** The only weather source files are
   `field_weather.c` / `field_weather_effect.c` / `coord_event_weather.c`, all
   overworld.

2. **`battle_bg.c` — which owns the battle backdrop — contains zero weather
   references.** `grep -c -i weather src/battle_bg.c` → **0**.

3. **Battle entry destroys the entire field-weather system.**
   `CB2_InitBattleInternal` (`src/battle_main.c:512`) calls
   `ResetSpriteData()` / `ResetTasks()` / `FreeAllSpritePalettes()`
   (`:576-580`). The field weather is driven by a task created at
   `field_weather.c:224` (`gWeatherPtr->taskId = CreateTask(Task_WeatherInit, 80)`)
   plus its own sprite set — `ResetTasks()`/`ResetSpriteData()` destroy both.

4. **`StartWeather()` is never called from any battle file.** Its only three
   call sites are `overworld.c:2575`, `overworld.c:3975`, and
   `cable_car.c:253`.

5. **The battle transition explicitly tears field weather down on the way in.**
   `Transition_StartIntro` (`battle_transition.c:1046-1051`) calls
   `SetWeatherScreenFadeOut()` and sets `gWeatherPtr->noShadows = TRUE` (its
   own comment: *"cause all shadow sprites to destroy themselves, freeing up
   sprite slots for the transition"*).

### The two `field_weather.h` consumers that looked like counter-evidence

Both were traced and neither is in-battle rendering:

- **`battle_main.c`'s two `gWeatherPtr->currWeather` reads** (`:5831`, `:5962`)
  are both inside the **`else` branch of `if (state == MON_IN_BATTLE)`** — i.e.
  the *out-of-battle* path, used to display Weather Ball's / Terrain Pulse's
  type on the summary screen. Not rendering, and not reached during a battle.

- **`battle_anim_ice.c`** (`:1067`, `:1172`) reuses the raw
  `gWeatherFogHorizontalTiles` tile blob as a BG for Blizzard / Powder Snow.
  That is an *asset* reuse, not the weather system.

- `battle_setup.c:770`'s `GetSavedWeather() == WEATHER_SANDSTORM` only picks
  `BATTLE_ENVIRONMENT_SAND` (which backdrop to load), not a weather effect.

**Conclusion: field weather is never driven during a battle.** Question 1 from
the first pass is closed.

---

## 2. What source ACTUALLY does — the finding the first pass missed

`BattleScript_WeatherContinues` (`data/battle_scripts_1.s:3156`):

```
BattleScript_WeatherContinues::
	printfromtable gWeatherTurnStringIds
	waitmessage B_WAIT_TIME_LONG
	playanimation_var BS_ATTACKER, sB_ANIM_ARG1     <-- plays a full weather animation
	setbyte gBattleCommunication, 0
	call BattleScript_ActivateWeatherAbilities
	return
```

Driven every turn from `HandleEndTurnWeather` (`src/battle_end_turn.c:94-97`)
→ `EndOrContinueWeather()` (`src/battle_util.c:244`), which sets
`gBattleScripting.animArg1 = sBattleWeatherInfo[currBattleWeather].animation`
(`:266`) before calling the script.

**So the reference's answer to "how does the player see that weather is active"
is: the weather's whole animation replays at the end of every turn**, in step
with the message. That is the persistent visual. It is a real mechanic, fully
portable, and needs no invention.

### All five trigger points

| # | Trigger | Animation played | Source |
|---|---|---|---|
| 1 | Weather set by a **move** | the **move's own** animation only | `TryChangeBattleWeather` else-branch sets `moveStartMessage` and **no** `animArg1` (`battle_util.c:2004-2007`) |
| 2 | Weather set by an **ability** (Drizzle/Drought/Sand Stream/Snow Warning) | the `*_CONTINUES` general anim | `animArg1 = sBattleWeatherInfo[].animation` (`battle_util.c:2002`) |
| 3 | Weather inherited from the **overworld** at battle start | the `*_CONTINUES` general anim | `FIELD_EFFECT_OVERWORLD_WEATHER` (`battle_util.c:2788-2848`) → `BattleScript_OverworldWeatherStarts` |
| 4 | **Every turn end** while active | the `*_CONTINUES` general anim | `BattleScript_WeatherContinues` (above) |
| 5 | Weather **ends** | **none** — message only | `BattleScript_WeatherFaded` (`battle_scripts_1.s:3164`) has no `playanimation` |

Trigger 1 vs 2 is a real asymmetry, easy to miss: a move that sets weather does
*not* additionally fire the general anim — its own move animation stands in.

Trigger 3 is **not applicable to this project** (no overworld until M27), but
is recorded because it is the mechanism that genuinely connects field weather
to battle: a one-time *state* seed plus one animation, never a live renderer —
which independently corroborates §1.

---

## 3. The animation inventory — and the sharing that makes this cheap

`sBattleAnims_General` (`src/battle_anim.c:216-219`) maps the `*_CONTINUES` ids
to six scripts. Reading them (`data/battle_anim_scripts.s:29144-29174`) gives
the key structural finding:

| Weather | Per-turn script | Body |
|---|---|---|
| Rain | `gBattleAnimGeneral_Rain` | **its own shorter routine** (`RainDrops`) |
| Sun | `gBattleAnimGeneral_Sun` | `goto gBattleAnimMove_SunnyDay` |
| Sandstorm | `gBattleAnimGeneral_Sandstorm` | `goto gBattleAnimMove_Sandstorm` |
| Hail | `gBattleAnimGeneral_Hail` | `goto gBattleAnimMove_Hail` |
| Snow | `gBattleAnimGeneral_Snow` | `goto gBattleAnimMove_Snowscape` |
| Fog | `gBattleAnimGeneral_Fog` | `goto gBattleAnimMove_Haze` |

**For five of six, the per-turn animation is a literal `goto` into the move's
own script — the same animation, not a variant.** Only **Rain** has a separate,
deliberately shorter routine.

Consequence: building the move animations gets the per-turn visuals for
Sun/Sandstorm/Hail free. Only Rain needs a second, shorter variant.

**Scope note for this project:** `WEATHER_HAIL` here collapses source's Hail
and Snow into one constant — a documented permanent design decision from
`[D2 batch]`. So **Snowscape is out of scope**; Hail's animation is the one to
build. Fog is likewise out of scope (no `B_WEATHER_FOG` in this project).

### Nothing loops

Every one of these is a finite script terminating in `end`. There is no looping
weather animation anywhere. The recurrence comes entirely from the per-turn
re-trigger in §2.

---

## 4. Per-animation detail (assets, structure, duration)

Frame counts are GBA frames at 60 fps. Blend durations are
`steps × delay` from `AnimTask_BlendBattleAnimPal`'s `(delay, from, to)` args.

Particle-task arg semantics were confirmed by reading the task functions
directly (`AnimTask_CreateRaindrops`, `battle_anim_water.c:623`;
`AnimTask_CreateSnowflakes`, `battle_anim_ice.c:1724`), not inferred:
args are `(unused, spawn_interval_frames, total_task_lifetime_frames)`, and one
sprite spawns every `interval` frames at a uniformly random
`x ∈ [0, 240)`, `y ∈ [0, 80)`.

### Rain — move version (`gBattleAnimMove_RainDance`, `:24096`)
- Blend `(F_PAL_BG | F_PAL_BATTLERS_2)` → `RGB_BLACK`, 0→4 @ delay 2 = **8f**
- 2 × `AnimTask_CreateRaindrops(interval=3, duration=120)` → **~80 drops**
- `delay 120` + `delay 30` = **150f**
- Blend back 4→0 = **8f**
- **Total ≈ 166f ≈ 2.77s**

### Rain — per-turn version (`RainDrops`, `:29148`)
- Same blend in/out (8f each)
- 2 × `AnimTask_CreateRaindrops(interval=3, duration=60)` → **~40 drops**
- `delay 50`
- **Total ≈ 66f ≈ 1.1s** — deliberately ~2.5× shorter than the move version.
  This is exactly why Rain is the one weather that does not share its script.

### Sun (`gBattleAnimMove_SunnyDay`, `:25469`)
- `monbg ANIM_ATK_PARTNER`, `setalpha 13, 3`
- Blend `(F_PAL_BG | F_PAL_BATTLERS_2)` → `RGB_WHITE`, 0→6 @ delay 1 = **6f**
- 4 × `SunlightRay` (one `gSunlightRaySpriteTemplate` each, `delay 6`) = **24f**
- Blend back = **6f**
- **≈ 36f ≈ 0.6s** plus sprite tails

### Sandstorm (`gBattleAnimMove_Sandstorm`, `:25117`)
- `AnimTask_LoadSandstormBackground` — loads a **scrolling BG layer** (not
  sprites) onto BG1 with `BLDALPHA_BLEND(0, 16)` (`battle_anim_rock.c:478-506`)
- `delay 16`, then **7 ×** `gFlyingSandCrescentSpriteTemplate` at `delay 10`
  each = **60f**
- **≈ 76f ≈ 1.27s** to last spawn. Note it has **no `waitforvisualfinish`**
  before `end` — it terminates while sprites are still live.

### Hail (`gBattleAnimMove_Hail`, `:22419`)
- Blend **`F_PAL_BG` only** (not the battlers, unlike Rain/Sun) → `RGB_BLACK`,
  0→6 @ delay 3 = **18f**
- `AnimTask_Hail` (`battle_anim_ice.c:1420`) — spawns particles until it
  self-terminates
- `loopsewithpan SE_M_HAIL, ..., 8, 10`
- `waitforvisualfinish`, blend back = **18f**

### Snowscape (out of scope — recorded for completeness)
Blend → `RGB(11,18,22)` 8f; 3 × snowflakes(interval 3, duration 120); 150f;
blend back 8f ≈ **166f**.

### Per-weather screen tint — cheap and high-value

Every one of these blends the whole screen toward a per-weather colour for the
animation's duration and restores it after:

| Weather | Blend target | Palettes affected |
|---|---|---|
| Rain | `RGB_BLACK` | BG **and battlers** |
| Sun | `RGB_WHITE` | BG **and battlers** |
| Hail | `RGB_BLACK` | **BG only** |
| Snowscape | `RGB(11,18,22)` | BG and battlers |

In Godot this maps directly onto the `mix()` blend shader already built in
`[M26B3-6a]` (`_BLEND_SHADER_CODE` / `_apply_blend_material`) — no new
mechanism needed.

---

## 5. Assets — all present, all flat-copyable except one

All sprite sheets are mode-`P` with 16-colour embedded palettes, i.e. the same
shape as every prior asset pull in this project (and, per
`[M26B3-6a]`, they will need the `im.info["transparency"] = 0` index-0
transparency rule rather than a plain `shutil.copyfile`).

| Asset | Path (`graphics/battle_anims/`) | Size | Notes |
|---|---|---|---|
| `rain_drops.png` | `sprites/` | 16×224 | 16×32 OAM ⇒ 7 frames |
| `sunlight.png` | `sprites/` | 32×32 | affine (rotates/scales) |
| `flying_dirt.png` | `sprites/` | 32×32 | 32×16 OAM, 2 subsprites ⇒ 64×16 crescent |
| `hail.png` | `sprites/` | 16×16 | affine |
| `snowflakes.png` | `sprites/` | 16×224 | **out of scope** (Snow ≡ Hail here) |
| `sandstorm_brew.png` | `backgrounds/` | 64×64 | BG tileset |
| `sandstorm_brew.bin` | `backgrounds/` | **2048 B** | exactly one 32×32 GBA screen block |

Two notes:

- `snowflakes.png` shares `gBattleAnimSpritePal_RainDrops` as its palette
  (`src/data/battle_anim.h:1410`) — worth knowing if Snow is ever un-collapsed.
- **Sandstorm is the only one needing a decode.** Its 2048-byte `.bin` is the
  same one-screen-block format already decoded successfully three times in this
  project (Phase 5a backgrounds, Phase 5c's `water.png`, M25h-4's Bag/Party
  frames), so the existing technique applies directly — but it is a real,
  non-trivial piece of work, unlike the other four.

---

## 6. Two behavioural details a port must not get wrong

Both were found by reading the dispatch, not assumed:

1. **The `*_CONTINUES` anims are special-cased twice to guarantee they always
   play.**
   - `ShouldAnimBeDoneRegardlessOfSubstitute` (`battle_gfx_sfx_util.c:545-563`)
     lists all six — a Substitute never suppresses them.
   - `battle_script_commands.c:4856-4866` gives them their own branch **before**
     the `IsSemiInvulnerable(battler)` early-out — a battler mid-Fly/Dig doesn't
     suppress them either.

   Both confirm these are **field-wide ambience, not a targeted per-battler
   effect**. A port must not route them through per-target gating. (They are
   nominally emitted at `BS_ATTACKER` / `BS_BATTLER_0`, but that battler is only
   a dispatch vehicle — the visual is full-screen.)

2. **Weather ending plays no animation at all** — `BattleScript_WeatherFaded`
   is message-only. Don't add a symmetric "weather ends" effect; source has none.

---

## 7. Proposed shape, and the one open question for Rob

### Revised split (replaces the first pass's (a)/(b))

- **B4-1 — the four animations.** Rain, Sun, Sandstorm, Hail. Each is a finite,
  non-looping, fully-specified sequence (§4) over already-identified assets
  (§5). Rain additionally needs its shorter per-turn variant. Sandstorm carries
  the only real decode cost.
- **B4-2 — trigger wiring.** Per-turn replay at end of turn (alongside the
  already-implemented "weather continues" message), plus the set-by-ability
  trigger. Both source-backed; the set-by-move case correctly plays only the
  move's own animation.

**No original design is required, and item (b) as previously framed is moot.**
Per this project's reference procedure, that also means this is no longer a
"the reference doesn't cover it → decision point for Rob" situation.

### The one genuine judgement call

Source-faithful behaviour adds **~1.1 s (Rain) to ~2.8 s (a weather-setting
move) of animation to every single turn** that weather is active. That is
authentic — the reference is a handheld game with no fast-forward — but it is a
real feel question for a simulator that already resolves turns instantly and
paces purely for readability.

This is a **pacing/sequencing** question, which **M26G2 already owns** (its
scope was explicitly expanded to cover sequencing and ordering, not just
duration/easing). Options, for Rob:

1. Ship it source-faithfully at full duration.
2. Ship the animations but shorten the per-turn replay beyond source's own
   already-shortened Rain variant.
3. Ship the per-turn replay as a tint-only pulse (§4's blend), reserving the
   full particle animation for the set-by-move/ability trigger.

Recommendation: **(1), then re-judge in M26G2** — the per-weather timings are
cheap to tune later, and M26G2 is the pass designed to look at exactly this
across the whole battle flow. Building it short first would be guessing at a
feel problem before there is anything to feel.

### Sequencing note

B4 stays where it is (M26B, in-battle HUD) rather than moving to M26F1's
move-animation work: the per-turn replay is a persistent, always-visible stage
behaviour, which is the exact reason Rob's own call kept it out of the M26E5
overlay.

---

## 8. Implementation roadmap

**Rob's call, 2026-07-27: ship it SOURCE-FAITHFUL** (option 1 of §7), full
durations, and re-judge feel in M26G2. The pacing question is not re-opened
here.

### 8.0 Correction to §2 and §7 of this document

§2 and §7 both said the per-turn replay would sit "alongside the
already-implemented 'weather continues' message." **That was wrong, and is
corrected here rather than left to mislead.** A direct check of
`battle_manager.gd` found this project has **no per-turn weather signal or
message of any kind**. It has exactly three weather signals — `weather_set`
(`:211`), `weather_expired` (`:212`), `weather_damage` (`:213`) — all three
already wired to `_log()` in `battle_screen_shared.gd` (`:1908-1913`). The
end-of-turn tick (`:6487-6493`) decrements `weather_duration` and emits
**only on expiry**; a turn where weather persists emits nothing at all.

So the per-turn message does not exist and must be built. It is a **blocker
for the animation**, not a companion to it.

### 8.1 Sequencing decision — B4-0 first, as an M26D3 carve-out

The per-turn message is genuinely M26D3 (Battle dialogue completeness) work by
theme. It is nonetheless built **here, in B4**, for three reasons:

1. **M26D3 is unscoped** — an explicit recon-then-scope placeholder over 72
   unwired signals. Opening it to extract one item means either doing that
   whole recon as a detour or pre-empting it.
2. **B4 is blocked on the signal regardless.** The per-turn animation trigger
   *is* `weather_continues`. B4 must add it whether or not D3 ever runs, and
   once it exists the message is a few lines.
3. **Source fires message and animation as ONE script in a fixed order.**
   Splitting them across two milestones would establish the ordering contract
   in one and consume it in another — the exact cross-session ordering split
   M26G2's own scope note identifies as the cause of every real pacing defect
   in the M26B3/M26B5 arc.

Precedent for carving an item out of its thematic home when it is structurally
entangled with the work in hand: M26C3 pulled forward into M26C1, M25h-2
absorbed into M26A2, Spirit Shackle merged into M19f, Uproar merged into
M19-rampage.

**M26D3 inherits one fewer signal and a worked example.** Recorded so a future
D3 recon does not re-discover `weather_continues` as an open gap.

### 8.2 The ordering contract maps one-to-one onto existing infrastructure

Source (`BattleScript_WeatherContinues`):

```
printfromtable gWeatherTurnStringIds
waitmessage B_WAIT_TIME_LONG
playanimation_var BS_ATTACKER, sB_ANIM_ARG1
```

This project's `_pending_beats` queue already has both beat kinds, drained in
insertion order, and the wait constant is literally named after source's:

```gdscript
_pending_beats.append({"kind": "text", "text": line, "hold": _WAIT_TIME_LONG})
_pending_beats.append({"kind": "anim", "start": start_effect})
```

(`_WAIT_TIME_LONG`, `battle_screen_shared.gd:610`; the `anim` beat, `:2163`.)

**No new sequencing mechanism is needed.** B4-0 queues the text beat with the
animation slot empty; B4-3 fills it.

---

### B4-0 — `weather_continues` signal + per-turn message

**STATUS: COMPLETE — 2026-07-27.** 38/38 in a new
`scenes/battle/m26_b4_0_weather_continues_test.tscn`; 14 further suites green.

*Ships and is verifiable on its own. No assets, no animation.*

**One Step 0 finding reshaped the implementation.** Source's condition is
`weatherDuration > 0 && --weatherDuration == 0` — a **short-circuit**, so the
else (continues) branch catches *two* cases: weather with turns left after the
decrement, **and permanent (duration-0) weather**, which never decrements and
never expires. This project's tick was `if weather != NONE and weather_duration
> 0:`, which skips the whole block for duration 0 and would emit nothing.

The tick was therefore restructured into source's own if/else shape rather than
having the emit bolted onto the existing condition. Behaviour is byte-identical
for every reachable case. The permanent case is **currently unreachable here** —
`weather_duration` is assigned at exactly one site (`_try_set_weather`) from
`ItemManager.weather_duration`, which returns only 5 or 8 for a real weather;
primal weather is not modelled as permanent (`[D2 batch]`'s own flagged gap).
Written in source's shape anyway so that whenever primal permanence *is* built,
`weather_continues` keeps firing correctly with no further change here — and
pinned by test C.05 so it cannot silently regress in the meantime.

**Shipped:**
- `signal weather_continues(weather_type: int)` (`battle_manager.gd:214`).
- Emit from the restructured end-of-turn tick.
- `_WEATHER_CONTINUES_TEXT` (`battle_screen_shared.gd`), five entries taken
  verbatim from `gWeatherTurnStringIds` and their own STRINGID entries. Note
  the trailing **periods** rather than exclamation marks — source's own
  punctuation for these, differing from the start/end tables deliberately.
- `_log()` wiring next to the existing two weather lines, and a
  **Durations & Field State** debug entry reporting the remaining turn count
  (previously visible only at set/expiry, never during).

**Verified the guard actually guards.** The key discriminator (C.02 — does *not*
fire on the expiry turn) was proven by temporarily replacing the condition with
`if true:`: C.02 plus the whole C.04 lifecycle sequence failed (34/38), then
passed again on revert. Matches the roster-screen-bug precedent of proving a new
regression guard catches the thing it was written for.

**Suites green:** `m26_b4_0_weather_continues_test` 38/38, `weather_test` 64/64,
`m17d_test` 30/30, `m17n2_test` 58/58, `m17c_test` 95/95,
`m25c_message_log_test` 19/19, `m26b_debug_log_test` 57/57, `status_test` 78/78,
`m16d_test` 71/71, `m18_5f_test` 137/137, `d4_bundle3_test` 56/56,
`d4_bundle7_test` 34/34, `delayed_effect_test` 41/41,
`m19_d1_cheap_clusters_test` 47/47, `message_pacing_test` 52/52.
Full sweep not run — Rob's manual step per standing convention.

- New `signal weather_continues(weather_type: int)` in `battle_manager.gd`,
  declared alongside the existing three (`:211-213`).
- Emit it from the existing end-of-turn tick (`:6487-6493`) on the path where
  weather **persists** — i.e. the `else` of the `weather_duration == 0` branch.
  Position matters: source's `EndOrContinueWeather` runs at
  `HandleEndTurnWeather`, **before** weather chip damage
  (`HandleEndTurnWeatherDamage`) — and this project's tick is already in that
  same position, immediately before its own chip block. Confirm, don't assume.
- New `_WEATHER_CONTINUES_TEXT` lookup in `battle_screen_shared.gd`, mirroring
  the existing `_WEATHER_START_TEXT` / `_WEATHER_END_TEXT` dictionaries, wired
  to `_log()` next to them (`:1908-1913`). Strings from source's
  `gWeatherTurnStringIds`.
- Also wire it into `_wire_debug_signals()`'s **Durations & Field State**
  category (the existing `weather_set` debug entry at `:2642` is the model) —
  the remaining-turn counter is exactly what that category exists for.
- **Explicitly NOT done here:** no animation, no assets.

### B4-1 — asset pull

**STATUS: COMPLETE — 2026-07-27.** 33/33 in a new
`scenes/battle/m26_b4_1_weather_asset_test.tscn`; 4 asset-adjacent suites green
(`hit_effect_smoke_test` 91/91, `battle_ui_sprite_smoke_test` 222/222,
`battle_background_smoke_test` 153/153, `m26_b4_0_weather_continues_test`
38/38).

Six assets written to `assets/sprites/battle_effects/weather/` by the new
`scripts/gen_weather_effect_sprites.py`: `rain_drops.png` (16×224),
`sunlight.png` (32×32), `flying_dirt.png` (32×32), `hail.png` (16×16),
`snowflakes.png` (16×224), and the decoded `sandstorm_bg.png` (256×256).

**One Step 0 catch:** `AnimTask_LoadSandstormBackground` (`battle_anim_rock.c:498-500`)
loads the BG tiles and tilemap and then explicitly loads
`gBattleAnimSpritePal_FlyingDirt` — the *sprite's* palette, not the
background's own. A genuine cross-file palette reference, the same shape as
Thunder's `lightning.png`/`lightning_2.png` in Phase 5b. Checked directly:
`sandstorm_brew.png`'s embedded palette is **byte-identical** to
`flying_dirt.png`'s across all 16 colours, so the result is correct either way
— resolving the same way M26B3-6a's particle-palette question did. The script
still passes flying_dirt's palette (matching source's stated intent rather than
relying on the coincidence) and **asserts the equality**, so a future reference
update that breaks it fails loudly instead of silently recolouring the decode.

Decode verified beyond "it ran": zero magenta `(255,0,255)` fallback pixels
(`decode_screen_block`'s unresolved-palette marker, and the signature of the
failure mode Phase 5a was flagged for) and 6 distinct sandy tones rather than a
flat fill. Fourth successful application of Phase 5a's decode.

Transparency verified in both directions: all five sprites carry index-0 tRNS
with real opaque art remaining, and `sandstorm_bg.png` is **fully opaque** (BG
layer — index 0 is a real colour there).

*Original plan follows.*

New `scripts/gen_weather_effect_sprites.py`. Five sprite sheets + one BG.

- **Index-0 transparency is required**, not a plain `shutil.copyfile` — same
  rule as `gen_ball_sprites.py:91-92` and `gen_hit_effect_sprites.py:168-169`
  (`im.info["transparency"] = 0`). These sheets carry no tRNS chunk and index 0
  is the transparency key; index 0 is **not** a constant colour across files,
  so tag the index, never colour-key a value.
- **Destination: a NEW `assets/sprites/battle_effects/weather/` subdirectory.**
  Deliberately *not* `generic/` — `hit_effect_smoke_test` asserts that
  directory's exact contents (21 curated hit-effect sprites), and
  `[M26B3-6a]` already had to relocate the ball-particle sheet out of it for
  exactly this reason. Also not per-move `bespoke/` subdirs: these assets have
  **two consumers** (the move animation and the per-turn replay), so keying
  them by weather rather than by move avoids duplicating files four ways.
- **Sandstorm's BG is the one real decode.** `sandstorm_brew.png` (64×64
  tileset) + `sandstorm_brew.bin` (2048 B = one 32×32 GBA screen block). Reuse
  `scripts/gen_ui_frames.py`'s already-proven screen-block decode (M25h-4) —
  same format, third successful application of that technique.
- Files per §5. Verify dimensions on disk after the pull, don't assume.

### B4-2 — SPLIT into B4-2a (Rain + Sun) and B4-2b (Hail + Sandstorm)

**Split made 2026-07-27, on a real finding, not for convenience.** The recon
already anticipated splitting Sandstorm out ("consider shipping the other three
first") because it needs a scrolling BG layer rather than particles. Reading
Hail's own implementation for B4-2 found it is **also** a genuinely different
mechanism, which this document had not previously established:
`GenerateHailParticle` (`battle_anim_ice.c:1493-1545`) does not spawn free
particles — it walks an `sHailCoordData` table, resolves each entry against a
real BATTLER's on-field sprite coordinates (`GetBattlerSpriteCoord`, with
per-entry ±width/6, ±height/6 offsets), spawns each particle off-screen at
`y = -8` and `x = battlerX - ((battlerY + 8) / 2)`, and drives it toward that
battler with an impact effect on arrival.

So two of the four are simple (confirmed particle motions) and two are not:

- **B4-2a — Rain + Sun.** Both motions confirmed directly from source:
  `AnimRainDrop_Step` (`battle_anim_water.c:658-671`) is `x2++, y2 += 4` for 13
  frames; `AnimSunlight` (`battle_anim_fire.c:654-663`) pins to (0,0) and
  linear-translates to (140, 80) over 60 frames.
- **B4-2b — Hail + Sandstorm.** Battler-targeted coordinate table with impact
  effects, and a scrolling BG layer, respectively.

**B4-2a STATUS: IMPLEMENTED, NOT YET VERIFIED — 2026-07-27.** Code parses and 5
adjacent suites are green (`m26_b4_0` 38/38, `m26_b4_1` 33/33,
`m25c_message_log_test` 19/19, `m26b_debug_log_test` 57/57,
`hit_effect_dispatch_test` 40/40), but **it has no dedicated suite yet and has
not been looked at on screen.** Given every animation defect in the M26B3 arc
was found by screenshot while every suite stayed green, treat this as unproven
until B4-3 wires it up and a real capture pass runs.

Shipped in `battle_screen_shared.gd`: `_play_weather_effect(weather_type,
is_move_variant)` plus `_play_weather_rain` / `_play_weather_sun`, the
`_weather_make_tint` / `_weather_tween_tint` screen-tint pair, and
`_weather_spawn_raindrop` / `_weather_spawn_sun_ray`. Frame counts, spawn
intervals, blend coefficients and travel vectors are all source constants,
named and cited at their own declarations. Unknown weathers no-op rather than
playing a wrong stand-in.

**One deliberate deviation from this roadmap's own §B4-2 plan, worth stating:**
the screen tint is a full-screen `ColorRect` overlay, NOT
`_apply_blend_material`. That helper is per-CanvasItem and hardcodes the recall
pink, whereas source's `AnimTask_BlendBattleAnimPal` blends whole PALETTES
(`F_PAL_BG | F_PAL_BATTLERS_2`) — a hardware blend of entire layers toward a
colour. One translucent overlay reproduces that directly and covers background
and every sprite at once, which is what the flag pair actually means. GBA blend
coefficients are out of 16, so `target_blend_y / 16` maps straight onto an
alpha (Rain 4/16, Sun 6/16).

**Known and disclosed:** the overlay also tints the health boxes, which
source's two palette flags do not cover. Left for M26G2 rather than
special-cased.

**B4-2b STATUS: IMPLEMENTED, NOT YET VERIFIED — 2026-07-27.** Same caveat as
B4-2a: parses, 7 adjacent suites green, **no dedicated suite and not yet seen
on screen.**

Shipped: `_play_weather_hail` / `_play_weather_sandstorm`, plus
`_hail_target_point`, `_weather_spawn_hail_particle` and
`_weather_spawn_sand_crescent`.

**Hail** ports the real targeting rather than approximating it: the full
10-entry `sHailCoordData` table, each entry resolved against a live battler
sprite (±width/6, ±height/6) with the table's own coordinate as fallback when
that slot has no visible sprite — which is every RIGHT entry in singles,
exactly as source's `IsBattlerSpriteVisible` check intends. `AnimTask_Hail2`'s
two-level walk is reproduced (3 affine variants per entry, 2 frames apart, then
a 3-frame group delay). The three affine scales are `0x100`/`0xF0`/`0xE0` run
through the **inverted** GBA rule (256/value), the same rule `MonAnimator.godot_scale`
already encodes. The spawn-x offset is derived rather than copied: falling at
4:8 for the drop distance advances exactly half that in x, which is why source
precomputes `battlerX - ((battlerY + 8) / 2)` — reproduced as that same ratio so
it stays correct at this project's scale. Hail's blend is **BG-only**
(`F_PAL_BG`, not Rain/Sun's `F_PAL_BG | F_PAL_BATTLERS_2`), so its tint is
parented into `BattleStage` at index 1 — above `Background`, below every sprite
— a real per-weather asymmetry now reproduced rather than flattened.

**Sandstorm** is the only one built on a scrolling background layer:
`sandstorm_bg.png` tiled, oversized by one tile and wrapped modulo the tile size
so it scrolls indefinitely without exposing an edge, at source's own
`gBattle_BG1_X += -6` / `gBattle_BG1_Y += -1` per frame, with the `BLDALPHA`
envelope ported exactly (one step per 4 frames up to 7/16, hold 101 frames, then
symmetric fade — 230 frames total). The 7 crescents use the script's own per-sprite
(y, velocityX) pairs; velocities are **8.8 fixed point** (`AnimFlyingSandCrescent`
accumulates then `>> 8`), so 2304 is 9 px/frame, and each despawns at
`DISPLAY_WIDTH + 32` as source does. Each crescent is built as **two 32×16
halves side by side**, per `sFlyingSandSubsprites`' own 2-entry table — the
sheet is 32×32 but the crescent is 64×16, which a naive single-sprite port
would have got visibly wrong.

**Also corrected while wiring the dispatch:** the `_` fallback no longer means
"unimplemented" — all four real weathers now dispatch, and the fallback covers
Strong Winds (Delta Stream), which genuinely has no animation in source at all.

*Original plan follows.*

### B4-2 — the four animations

New `_play_weather_effect(weather_type, variant)` in
`battle_screen_shared.gd`. `variant` selects the **move** (long) vs **continues**
(short) form — a distinction that only actually differs for Rain (§3).

Reuse, in order of preference — none of this is new infrastructure:

- **Frame stepping:** `MonAnimator.Clock` (`mon_animator.gd:1966`) — the
  accumulator-based, refresh-rate-independent clock. Do **not** use a
  timer-per-step; M26G4 measured that pattern running ~10% slow at 144 Hz and
  half-speed at 30 Hz.
- **Screen tint:** the existing `_BLEND_SHADER_CODE` / `_apply_blend_material`
  `mix()` shader (`:709`), built in `[M26B3-6a]`. Per-weather targets per §4 —
  note Hail tints **BG only**, Rain/Sun tint BG *and* battlers.
- **Particle spawn:** `_spawn_ball_open_particles`'s wall-clock stagger is the
  model (one spawn per 1/60 s of real time, not per `process_frame` — that
  same fix was already needed once).
- **Node hosting + leak safety:** `_effect_layer` (`:509`) and
  `_active_hit_effect_nodes` (`:523`), with `_clear_active_hit_effects()`
  (`:1778`) already called from `_on_battle_ended`. Kill the tween before
  freeing the node — freeing first left a queued `tween_callback` erroring
  against a freed node in Phase 5c.
- **Move-side dispatch:** `HitEffectRegistry`'s existing bespoke branch
  (`_BESPOKE_SUBDIR`, `hit_effect_registry.gd:28`) gains the four weather move
  ids — 201 Sandstorm, 240 Rain Dance, 241 Sunny Day, 258 Hail (all confirmed
  present as real `.tres` entries). Without this they currently fall through to
  the generic `status_puff`.

**Cost is not uniform. Sandstorm is the outlier:** Rain/Sun/Hail are
particle-spawn + tint over the existing effect layer; Sandstorm needs a
*scrolling BG layer* (`AnimTask_LoadSandstormBackground` sets up BG1 with
`BLDALPHA_BLEND(0,16)` and scrolls it) plus 7 staggered crescent sprites. Size
it separately; consider shipping the other three first.

### B4-3 — trigger wiring

**STATUS: COMPLETE (code) — 2026-07-27.** 24/24 in a new
`scenes/battle/m26_b4_3_weather_trigger_test.tscn`; 11 further suites green.
**Still not screenshot-verified** — see the note at the end.

**A correction to this document's own §B4-2 claim.** An earlier draft asserted
the animations are "deliberately NOT awaited by callers — source lets the
battle carry on over these." That was an assumption and it is **wrong**.
`Cmd_playanimation` calls `BtlController_EmitBattleAnimation` +
`MarkBattlerForControllerExec`, and the main battle loop blocks on
`gBattleControllerExecFlags` until the controller reports done — so source
genuinely **does** pause the script for a weather animation. Callers therefore
await. That is also what "ship it source-faithful" means concretely: the turn
really does stop for ~1.1s–2.8s.

Implemented as a new **`anim_async`** beat kind alongside the existing `anim`
(which awaits a single `Tween`; the weather effects are multi-phase coroutines
— tint ramp → staggered spawns → tint release — so they need a Callable the
pacing loop can `await` directly). Additive: one new `match` arm, no existing
beat kind touched.

**The move-vs-ability discrimination, resolved without a signal change.**
`weather_set` does not say whether a move or an ability caused it, and the
roadmap flagged confirming this rather than adding a parameter. Resolved by
keying on the setter's own ability against `_WEATHER_SETTER_ABILITIES` (Drizzle
/ Drought / Sand Stream / Snow Warning / Sand Spit / the three primals) — real
data already on the signal, and no change to 5 emit sites and 2 live listeners.
*Disclosed edge case:* a Drizzle holder **using** Rain Dance classifies as
ability-driven and so plays the shorter rain form. Both are rain animations
differing only in length, and the move handler returns first, so the cost is
bounded to that.

**Move-side dispatch is keyed on `weather_type`, not a move-id list** — so it
covers all five weather moves and anything added later with no further wiring.
Snowscape is the one id-specific case, necessarily: it sets `WEATHER_HAIL`
here, so weather STATE cannot distinguish it from Hail and only the move id
can.

**One real design bug found and fixed while writing the tests:** the weather
branch was initially placed *after* `_on_hit_effect_move_executed`'s
target-sprite early-return. A weather animation is full-screen and has no
target, so any move whose target sprite failed to resolve would silently lose
its animation. Moved ahead of that lookup, and pinned by C.03/C.04 (which
assert the beat is queued *precisely when* no target sprite resolves).

**Verified the order guard actually guards.** A.01's beat-ORDER assertions were
proven by temporarily queueing the animation before the message: A.01–A.01e all
failed (19/24), then passed again on revert. Order, not presence, is the point
— presence alone would pass just as happily with the animation playing before
its own caption.

**Suites green:** `m26_b4_3` 24/24, `m26_b4_0` 38/38, `m26_b4_1` 33/33,
`m25c_message_log_test` 19/19, `m26b_debug_log_test` 57/57,
`hit_effect_dispatch_test` 40/40, `message_pacing_test` 52/52, `weather_test`
64/64, `m17c_test` 95/95, `m17d_test` 30/30, `m19_d1_cheap_clusters_test`
47/47, `phase4d_doubles_visual_test` 27/27.

### B4 capture pass — COMPLETE 2026-07-27

Real non-headless run (WSLg, `DISPLAY=:0`) driving `battle_screen_singles.tscn`
via a disposable scratch driver, since `--headless`'s dummy renderer rasterises
nothing. 19 shots across all five animations. Driver deleted afterwards, per
the Phase 5a/5c/M26B3 precedent.

**Zero effect nodes leaked** after every animation completed — the
`_active_hit_effect_nodes` bookkeeping holds.

**Rain — correct.** Drops fall down-and-right from the top half, screen dims
toward black, releases cleanly. Both variants behave.

**Hail — correct, and it validated the `bg_only` tint.** Crystals fall
diagonally onto the battler positions, and the backdrop dims while the Pokémon
sprites and health boxes stay crisp — exactly the `F_PAL_BG`-only behaviour
that asymmetry was built for. This shot is the reference for what correct
layering looks like.

**Sandstorm — renders and scrolls correctly; layering is a DELIBERATE
DEVIATION.** The first pass showed the sand layer drawing over the sprites and
health boxes, washing the whole scene sand-coloured — visibly different from
hail's correctly-layered tint in the same run. Source puts it behind the
battlers (`SetAnimBgAttribute(1, BG_ANIM_PRIORITY, 1)`), and a fix was written
to parent it into `BattleStage` at index 1. **Rob reviewed the capture and
preferred the over-everything look, so the fix was backed out and the current
behaviour kept on purpose.** Recorded at the code site as well. Do not
"correct" it to match source without asking — it is a reviewed, accepted
divergence, not the layering bug it resembles.

**Sun — one real defect found and fixed.** It rendered as a static opaque
yellow slab because `sAffineAnim_SunlightRay` had not been ported at all. Now
implemented: the affine param starts at `0x50` and rises `+2`/frame, which
under the inverted GBA rule (`256/param`, the same convention
`MonAnimator.godot_scale` encodes) means the ray **shrinks** from 3.2× to
~1.28× across its 60 frames; plus `+10`/frame rotation via this project's
`/65536*TAU` convention, and the script's own `setalpha 13, 3` as a 13/16
alpha. **Still an open look call for Rob:** `sunlight.png` is itself a solid
32×32 diamond (verified by direct pixel dump), so even at a faithful 3.2× with
81% alpha it reads as a large pale-yellow diamond rather than a beam. The
mechanism is now source-accurate; whether it *looks* right is a judgment call,
and the cheap levers are the alpha and the affine start scale.

**Not re-verified after the sun fix:** rain/hail/snow were captured before it
and are unaffected by it (separate functions), but the sun shots are the only
ones taken against the current code.

*(Superseded note follows.)*

**REMAINING FOR B4: the screenshot pass.** Everything in B4-1/2/3 is a faithful
reading of source plus green tests, and none of it has been looked at on
screen. Every animation defect in the M26B3 arc — the invisible pink blend, the
ball orbiting its own corner, the origin/destination collision, the mon
revealed on top of a mid-throw trainer — was found by looking, while every
suite stayed green. Treat the visuals as unproven until then.

*Original plan follows.*

### B4-3 — trigger wiring (original plan)

Three call sites, all source-backed (§2), none of which is the set-by-move case:

| Trigger | Wiring |
|---|---|
| Per-turn replay | `weather_continues` (B4-0) → text beat, then anim beat |
| Set by **ability** | `weather_set` where `by_pokemon`'s ability caused it → the `*_CONTINUES` form |
| Set by **move** | **nothing new** — the move's own animation already plays via `HitEffectRegistry` |
| Weather **ends** | **nothing** — `BattleScript_WeatherFaded` has no animation (§6) |

The `weather_set` signal already carries `by_pokemon`, so the ability-vs-move
distinction is available without a signature change — confirm which of the five
`weather_set.emit` sites (`:3338`, `:3371`, `:4660`, `:7975`, `:10949`) are
ability-driven rather than adding a parameter.

**Do not route the per-turn animation through per-target gating** — §6: source
special-cases it twice to bypass both Substitute and semi-invulnerability. It
is field-wide ambience nominally emitted at a battler.

### Test plan

New `scenes/battle/m26_b4_weather_test.gd`/`.tscn`:

- Asset integrity (files exist, real dimensions, transparency tagged) —
  mirrors `hit_effect_smoke_test` / `battle_background_smoke_test`.
- `weather_continues` fires on a persisting turn and **not** on the expiry turn
  (the discriminator that matters).
- Frame counts asserted against source's own numbers per §4, so a later
  "simplification" fails loudly — the `MonAnimator` precedent.
- Clock refresh-rate independence.
- **Beat ORDER, not just presence** — text beat precedes anim beat. This is the
  single highest-value assertion here; `m26_b3_6c_test`'s M.04 is the worked
  example, and per M26G2 this suite class is structurally blind to sequencing
  unless order is asserted explicitly.
- Zero effect nodes leaked after completion.

**A real screenshot pass is mandatory, not optional.** Every animation defect
in the M26B3 arc — the invisible pink blend, the ball orbiting its own corner,
the origin/destination collision, the mon revealed on top of a mid-throw
trainer — was found by looking at the screen while every suite stayed green.

### Snowscape — RESOLVED (Rob, 2026-07-27): option (a), asset pulled

`snowflakes.png` is pulled and Snowscape keeps its own authentic **move**
animation. The per-turn replay follows weather STATE and so shows hail.

**The residual divergence is a known, accepted consequence of the Snow/Hail
collapse, not a defect**: a Snowscape user sees snowflakes once, then hail each
turn. Do not "fix" it by deleting the asset or remapping Snowscape to hail
without revisiting the collapse itself. Recorded at the asset (in
`gen_weather_effect_sprites.py`'s own header) and pinned by test D.01/D.02 in
`m26_b4_1_weather_asset_test.gd`.

**The standing open question is one level up, and outlives B4:** whether
`WEATHER_HAIL` should keep collapsing source's genuinely different Hail (chip
damage, no stat effect) and Snow (no chip, +50% Ice-type Defense). That is a
mechanics question, not a visual one — B4 only surfaced it. See §8.2 below for
where it is cross-referenced.

*Original framing follows.*

### Open item for Rob — Snowscape

Snowscape (809) **is implemented** in this project and sets `WEATHER_HAIL`,
because `[D2 batch]` permanently collapsed source's separate Hail and Snow into
one constant. Source keeps them distinct: Snowscape sets `B_WEATHER_SNOW` and
gets `B_ANIM_SNOW_CONTINUES` (snowflakes) every turn.

So the collapse forces a choice this recon's §3 had prematurely closed by
marking `snowflakes.png` out of scope:

- **(a)** Pull `snowflakes.png` and give Snowscape its own *move* animation,
  with the per-turn replay showing hail (matching the weather state). The move
  reads authentically; the per-turn visual diverges from the move that set it.
- **(b)** Map Snowscape to the Hail animation throughout. Internally
  consistent with the collapse, one fewer asset, but Snowscape and Hail become
  visually indistinguishable.

Neither is strictly source-faithful — the collapse already decided that. **(a)**
is recommended: it is one extra flat-copy asset for a visibly distinct move,
and it keeps the door open if Snow is ever un-collapsed. Not decided here.
