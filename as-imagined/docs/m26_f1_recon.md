# M26F1 recon — move (attack) animations: reference review, current-state review, and implementation proposal

Written 2026-07-29. Recon only — no code written, no assets pulled this session.

This is the research half of M26F1 ("Bespoke move-animation data research + balance/setup
fixes", orig. M25f, orig. M26j). The balance half (random-opponent team level matching) is
NOT covered here — it is unrelated work that happens to share the roadmap slot, and should
be resolved separately.

Reference repo state at time of review: pokeemerald-expansion **v1.16.2**, HEAD
`74e40e033966421de974398a6777b87945e46c62` (2026-06-27), clean tree.

---

## 0. TL;DR

1. The reference's move-animation system is a **54-opcode bytecode VM** (not ~125 as the
   M23.11 Phase 5 recon estimated — that count included assembler convenience macros)
   driving sprites, tasks, palette effects, backgrounds, and sound. The scripts themselves
   are **data** (35,606 lines of `.s`, 941 move scripts) and are mechanically parseable.
2. The real cost is not the VM — it is the C-side behavior library the scripts call into:
   ~1,149 sprite templates, ~1,010 sprite callbacks, ~264 tasks across ~55k lines of C.
3. **But usage is extremely head-heavy.** 12 opcodes cover >96% of all opcode occurrences,
   one hitsplat macro alone appears 402 times, and a curated set of ~25 callbacks/tasks
   covers the majority of the move roster's actual on-screen behavior.
4. All graphics assets are source-form indexed PNGs + JASC palettes + raw tilemaps —
   directly consumable with the pipeline patterns this project already has. **Sound is the
   one hard asset class** (MIDI + GBA soundfont, no prebuilt samples).
5. Proposal: a **tiered faithful port with graceful fallback** — extract all scripts and
   assets, build a small Godot VM + core behavior library, implement callbacks in
   prioritized batches, and let any unimplemented callback degrade to the current generic
   hit-effect. Full-roster coverage from day one, fidelity that grows monotonically per
   batch. This is bounded in a way the "port everything" reading (correctly rejected
   2026-07-19) was not.

---

## 1. Where this sits in the roadmap

- **M26F1** (`---`, nothing started) carries M25f's scope: research what the move-animation
  data source actually holds for Flamethrower/Thunder/Surf beyond Phase 5b/5c's pull,
  because the current bespoke animations "look nothing like the real games'".
- M26F is explicitly flagged in CLAUDE.md as a **split-out candidate** — its two items are
  the only non-graphical work in M26. The scale documented below justifies exercising that
  option: this recon closes M26F1's research mandate, and implementation should become its
  own milestone with sub-tiers (§7).
- Prior art constraints (M23.11 Phase 5, locked 2026-07-19): hybrid model = generic
  type/category hit-effect library + 3 bespoke moves, with the explicit note that the
  hybrid "is not a first step toward per-move fidelity, just a bounded exception for 3
  specific moves." This recon supersedes that assessment with better data — see §6.1.

---

## 2. Reference review — how move animations actually work

### 2.1 Architecture (five layers)

| Layer | Where | Role |
|---|---|---|
| Launch | `src/battle_anim.c:317-499` | `DoMoveAnim`/`LaunchBattleAnimation` pick a script |
| VM | `src/battle_anim.c:128-184, 638-644` | `sScriptCmdTable[54]` + `RunAnimScriptCommand` |
| Scripts | `data/battle_anim_scripts.s` (35,606 lines) | 1,023 labelled animations (data, not code) |
| Behavior lib | `src/battle_anim_*.c` (27 files, 54,718 lines) | sprite templates, callbacks, tasks |
| Resources | `src/data/battle_anim.h` | tag→gfx/pal table (413), BG table (84) |

Key mechanics a port must reproduce (full detail in the sections below):

- **Frame-pumped, not free-running.** The battle controller calls the VM once per frame
  and polls `gAnimScriptActive`. Commands execute in a tight loop within one frame until a
  wait (`delay`, `waitforvisualfinish`, …) is hit — so `createsprite`/`createvisualtask`/
  `playsewithpan` cost zero frames.
- **Move → script binding is a move-struct field** in expansion (`.battleAnimScript` in
  `src/data/moves_info.h`, 935 assignments — there is NO `gBattleAnims_Moves` table).
- **`gBattleAnimArgs[8]`**: every create-command stuffs its inline args into this global;
  the callback/task reads them on its first (immediate, same-frame) invocation. Slot 7 is
  the return channel for query tasks (`jumpargeq`/`jumpreteq` branching).
- **Completion accounting**: `gAnimVisualTaskCount` is incremented per successful sprite/
  task creation and decremented only by `DestroyAnimSprite`/`DestroyAnimVisualTask`;
  `waitforvisualfinish` and `end` block on it (plus `gAnimSoundTaskCount` for sound).
  `end` also auto-frees all still-loaded gfx/palette tags.
- **All anim sprites are born at the anim TARGET's center** regardless of the
  `anim_battler` argument; attacker-relative sprites reposition themselves in their
  callback (`InitSpritePosToAnimAttacker`). X offsets are direction-aware (mirrored when
  attacker is on the right).
- **Subpriority encoding**: `createsprite tmpl, ANIM_TARGET, 2, …` = 2 layers in front of
  the target; battler base subpriorities are position-keyed (player-left 30, opp-left 40…).
- **`monbg` + `setalpha 12,8` … `clearmonbg` + `blendoff`** is the near-universal
  prologue/epilogue. It exists ONLY because GBA OBJs can't alpha-blend against other OBJs
  — the mon is rasterized into a BG layer so particles can blend over it. **In Godot this
  is a no-op** (CanvasItems blend freely); `setalpha 12/16, 8/16` maps to particle
  self-modulate ≈ 0.75 over normal blending.
- **Two-turn moves**: `choosetwoturnanim chargePtr, unleashPtr` branches on
  `gAnimMoveTurn & 1` (the battle engine increments `animTurn` per `attackanimation`).
  Multi-hit moves replay the whole script per hit with `animTurn` incremented
  (Double Slap alternates slap direction this way). 31 uses.
- **Spread moves animate once** (`animTargetsHit` guard), and `DoMoveAnim` retargets the
  anim to an opponent when the logical target is an ally.
- **Sequencing contract** (`data/battle_scripts_1.s:1443-1472`): damage is computed
  BEFORE the animation; then `attackanimation` → `waitanimation` → effectiveness SE →
  hit flicker (exactly 32 frames, invisible toggled every 4) → HP-bar drain → messages.
  **This matches the beat order the Godot battle screen already implements** (anim →
  flash → hp_drain), which is a genuine architectural head start.

### 2.2 The 54 opcodes, by what matters

Frequency across all 35,606 script lines (bare opcodes; macros expand to these):

```
createsprite            7492    monbg                559    createspriteontargets      37
delay                   5968    return               449    stopsound/soundtask     34/31
createvisualtask        3165    blendoff             438    choosetwoturnanim          31
playsewithpan           3124    setalpha             395    jumpifmovetypeequal        23
call                    2729    loopsewithpan        258    createvisualtaskontargets  21
waitforvisualfinish     2372    waitbgfadein         241    splitbgprio(all/foes)      33
end                     1034    goto                 211    waitsound                  17
clearmonbg               594    fadetobg             198    jumpifmoveturn              9
unloadspritegfx/pal      154    waitbgfadeout        149    monbg_static pair         8/8
splitbgprio              116    restorebg            110    playse                      6
waitplaysewithpan         95    invisible/visible  83/73    fadetobgfromset             6
setarg                    61    jumpargeq             66    the rest                  <20
panse                     61
```

**Twelve opcodes cover >96% of occurrences.** A port that implements
`createsprite, delay, createvisualtask, playsewithpan (as no-op or SFX), call/return,
waitforvisualfinish, end, monbg/clearmonbg (no-op), setalpha/blendoff, goto` plus the
`jumpargeq` family runs almost every script structurally; the remaining opcodes
(backgrounds, pan sweeps, targets-loops) are additive.

~70 assembler convenience macros (`create_basic_hitsplat_sprite` ×402,
`blend_color_cycle` ×175, `simple_palette_blend` ×172, `create_random_pos_hitsplat` ×93,
`create_absorption_orb_sprite` ×72, …) expand to createsprite/createvisualtask — an
extractor works at the expanded level and never needs to know about them, but their
counts are the best proxy for which C behaviors to port first.

### 2.3 The behavior library (the actual cost center)

Per-file scale (lines / sprite templates / public `AnimTask_*`):

```
battle_anim_new.c        8396/621/34   (Gen 4-9 expansion moves — biggest chunk)
battle_anim_effects_1.c  7387/117/38   battle_anim_ghost.c    1708/16/31
battle_anim_effects_3.c  5727/ 63/81   battle_anim_ice.c      1764/23/11
battle_anim_effects_2.c  3797/ 57/59   battle_anim_water.c    1890/24/26
battle_anim_throw.c      2648/  4/29   battle_anim_electric.c 1644/31/12
battle_anim.c            2509/  8/ 0   battle_anim_fire.c     1438/24/ 8
battle_anim_mons.c       2486/  1/13   battle_anim_psychic.c  1365/21/21
battle_anim_mon_movement 1278/  7/46   battle_anim_flying.c   1333/18/ 7
battle_anim_utility_funcs 1089/  0/45  battle_anim_normal.c   1204/14/19
battle_anim_fight.c      1063/ 24/ 1   battle_anim_dark.c     1079/ 8/19
+ ground/dragon/poison/rock/bug/status_effects/sound_tasks/smokescreen
Totals: 54,718 lines, 1,149 templates, ~1,010 sprite callbacks, 264 tasks
```

The load-bearing shared helpers live in `battle_anim_mons.c` and
`battle_anim_mon_movement.c`/`battle_anim_utility_funcs.c`:

- **Placement**: `InitSpritePosToAnimAttacker/Target` (+ direction-aware
  `SetAnimSpriteInitialXOffset`).
- **Translation**: linear (8.8 fixed, `InitAnimLinearTranslation` family), fast (4.4),
  arc (`TranslateAnimHorizontalArc/VerticalArc` = linear + sine offset), circle/ellipse/
  Lissajous, plus composite "fly to target" callbacks
  (`TranslateAnimSpriteToTargetMonLocation`, `AnimThrowProjectile`,
  `AnimTravelDiagonally`). All trivially reproducible as tween/`_process` math.
- **Mon movement**: invisible controller sprites (lunge/dip/slide, tileTag 0) +
  `AnimTask_ShakeMon/ShakeMon2/ShakeMonInPlace/WindUpLunge/…` (46 tasks) that move the
  battler sprite itself.
- **Palette/color**: `AnimTask_BlendBattleAnimPal` (blend a selected set of palettes —
  BG, attacker, target, sides, particles — toward an RGB by y/16 steps),
  `blend_color_cycle`, flashes, afterimages, hardware fades. In Godot: per-sprite
  modulate lerps for battler/particle selectors, a full-screen ColorRect/shader for the
  BG selector. The project's weather anims already do exactly this kind of tint port.
- **Queries**: `AnimTask_IsContest` (always FALSE here), `_IsDoubleBattle`,
  `_GetTargetSide`, etc. — one-liners writing `args[7]`.
- **Coordinates**: `sBattlerCoords` (singles/doubles per-position GBA screen anchors),
  `Y_PIC_OFFSET` species-height adjustment, `GetBattlerSpriteCoordAttr` bounding-box
  queries. The Godot side must expose the equivalent from its own stage layout — the
  240×160 GBA space maps onto the battle stage's existing sprite anchors.

### 2.4 Sprite frame/affine data

Frame animation lives in C next to the templates: 3,110 `ANIMCMD_FRAME` sequences
(first arg = **tile offset into the sheet**, e.g. step 16 for 32×32 frames; duration in
frames; optional h/v flip; `ANIMCMD_JUMP/LOOP/END`) and 965 `AFFINEANIMCMD_FRAME`
sequences (x/y scale delta, rotation delta, duration — the hitsplat's 4 scale-in
variants, growing flames, spinning leaves). OAM shapes come from exactly 72 shared
`gOamData_*` structs (all 12 legal GBA size combos × affine/blend modes). These parse
mechanically: the decomp code style is uniform enough for regex extraction (precedent:
`scripts/gen_anim_ids.py` already parses C source for MonAnimator).

### 2.5 Assets

- `graphics/battle_anims/sprites/`: **402 indexed PNGs** (+46 standalone JASC `.pal`
  recolors), vertical strips whose width = frame width, 16-color (389/402 exactly 16).
  5 sheets are concatenations of numbered part PNGs (`ice_cube_0..3`, `spark_0..1`, …).
- **Tag table**: `gBattleAnimTable` (expansion merged vanilla's pic/palette tables),
  413 slots / 412 populated → 383 distinct gfx sources + 368 palette sources. Palette
  sharing is deliberate ("one sheet, N recolors": e.g. `GreenLightWall` gfx serves 5
  tags). 13/14 entries switch on `B_NEW_*` config flags (all currently FALSE — extract
  the FALSE branch). 4 palettes come from `graphics/pokemon/ogerpon*/` (Ivy Cudgel).
- **Backgrounds**: `graphics/battle_anims/backgrounds/` — 57 tile PNGs, 61 palettes,
  70 raw tilemap `.bin`s; `gBattleAnimBackgroundTable` = **84 BG ids**, heavy
  image/tilemap reuse with palette swaps (Hyper Beam/Dynamax Cannon/Chloroblast share
  Hydro Cannon's tiles). Player/opponent variants are separate ids. ~30 more BG files
  (scary_face, water/surf, solarbeam.bin, …) are referenced directly by code symbols,
  not the table. The GBA screen-entry decode needed is the SAME one already implemented
  in `gen_hit_effect_sprites.py::_render_surf_wave` and `gen_ui_frames.py`.
- **Masks/stat_change**: 5 mask pairs (metal_shine, light_beam, curse, cure_bubbles) +
  the stat-change arrow tiles/tilemaps with 8 per-stat palettes (`gStatAnim_*`).
- **Nothing prebuilt is checked in** — no `.4bpp/.lz/.smol` anywhere; everything is
  source PNG/pal/bin, directly consumable by PIL. `tools/gbagfx` exists with source if
  round-tripping is ever needed (it isn't, for our purposes).
- **Sound**: 130 `SE_M_*` move-SFX constants → `sound/songs/midi/se_m_*.mid` (132
  files) — **sequenced MIDI against a GBA soundfont** (105 instrument `.wav`s +
  voicegroup definitions), NOT prebaked samples. Faithful extraction requires either
  rendering MIDI through the voicegroup/sample set or capturing from a built ROM.
  Panning is a first-class part of the reference design (`playsewithpan` with
  attacker/target side mirroring, `panse` sweeps attacker→target during projectiles).

### 2.6 What else the anim system owns (adjacent, not move anims)

- `sBattleAnims_General` — 64 general anims (stat-change arrows, weather-turn anims,
  trap turns, held-item effect, Substitute swap, form change, heal sparkles, …). The
  project already has independent implementations of some (weather via M26B4); others
  (stat arrows, status anims) are natural early consumers of the same VM.
- `sBattleAnims_StatusConditions` — 10 status scripts (PSN/BRN/SLP/PRZ/FRZ/confusion/
  infatuation/curse/nightmare/frostbite), all short (3-6 commands).
- `sBattleAnims_Special` — 8 (ball throw, level-up, switch-out, substitute morphs) —
  ball throw alone is a 2,648-line C file; out of scope here (M26B7 owns catch UI).

---

## 3. Current-state review (Godot side)

What exists (M23.11 Phase 5b/5c, shipped 2026-07-19-ish):

- **Dispatch**: `battle_screen_shared.gd:2643` `_on_hit_effect_move_executed` — weather
  branch, then `match move_id` for the 3 bespoke moves, else generic. Defers a beat;
  `_run_message_pacing()` plays it in the correct anim→flash→hp_drain order.
- **Renderers**: exactly two. `_play_multi_stage_strip_effect` (a TextureRect stepping
  strip frames at the target's center — used by generic AND Flamethrower AND Thunder)
  and `_play_surf_effect` (a 120×90 keyhole panning over the decoded Surf canvas).
- **Registry**: `hit_effect_registry.gd` — move-ID recovery from resource_path, bespoke
  table {53, 57, 87}, 18-type generic mapping + status/stat split, frame-layout
  inference from texture dimensions.
- **Assets**: 32 PNGs (21 generic picks, 5 bespoke, 6 weather) pulled by
  `gen_hit_effect_sprites.py` / `gen_weather_effect_sprites.py`.
- **Tests**: 41 registry assertions + 14 asset smoke assertions. Nothing asserts visual
  behavior (consistent with the project's snapshot-testing conventions).

Fidelity gaps vs reference (why the bespoke 3 "look nothing like the real games'"):

| Reference | Current |
|---|---|
| Flamethrower: 22 flame sprites streaming attacker→target in a sine wave over ~46 frames, attacker recoil-shake, target flinch-shake, pan-swept SE | 1 static 32×32 sprite at target center for ~0.5s |
| Thunder: full-screen dark + `fadetobg BG_THUNDER`, descending bolt tasks, target blackout flashes, 8 phased spark sprites, BG strobes | 2 strips at target center, back-to-back |
| Surf: full-screen BG wave built/scrolled by a dedicated task with palette variants | 120×90 keyhole pan over a static canvas |
| Every physical move: lunge + hitsplat + target shake | 1 static type-keyed sprite |
| Attacker-side motion, projectile travel, mon shakes, palette effects, anim backgrounds, SFX | none |

What's genuinely right and reusable:

- The **beat queue** already enforces the reference's damage→anim→flicker→HP-drain
  order, including `anim`/`anim_async` await semantics and autoplay/headless skip.
- The **extraction pipeline idiom** (ref_path guard, idempotent gen scripts with
  findings-bearing docstrings, registry consumer, smoke test) scales directly to this.
- **MonAnimator + the weather anims prove the fidelity bar is achievable in-project**:
  verbatim sine table, accumulator clock, per-frame ports of affine data. The move-anim
  problem is the same work × a larger surface, not a new kind of work.

---

## 4. Corrections to the 2026-07-19 recon

1. **"125 distinct opcode-level commands" → actually 54 opcodes.** The 125 figure
   counted assembler macros (which expand to opcodes) as commands. The VM is half the
   estimated size, and 12 opcodes cover >96% of usage.
2. The recon had no frequency analysis, so it priced "port the system" at worst-case
   (~1,000 callbacks) with no notion of head-heaviness. 402 uses of one hitsplat macro
   was not visible in that sizing.
3. "~450 files / ~150 assets" → actually 402 sprite PNGs (the gen script's own
   docstring already corrected this) and 433 distinct files behind the tag table.
4. The verdict "faithfully porting this system is not realistic as a bounded scope"
   remains TRUE for 100%-fidelity-everything (backgrounds, contest branches, every
   one-off callback). It is FALSE for a tiered port with fallback — the architecture
   makes partial fidelity well-defined per-move, and coverage is measurable (§5.4).

---

## 5. Implementation proposal — tiered faithful port with graceful fallback

### 5.0 Shape

Extract everything once; interpret scripts in a small Godot VM; implement C-side
behaviors as a named-registry of GDScript callables, in prioritized batches; any script
that references an unimplemented behavior (or any move preferring not to run it) falls
back to today's generic hit-effect. The full 717-move roster is covered at all times;
per-move fidelity upgrades as batches land; a coverage report says exactly where we are.

### 5.1 Phase A — extraction (2 gen scripts + data)

**A1. Script extractor** (`scripts/gen_battle_anim_scripts.py`): parse
`data/battle_anim_scripts.s` + `asm/macros/battle_anim_script.inc` (to expand the ~70
macros) into JSON — one command list per label, `call`/`goto` targets resolved to label
references, args symbolic (ANIM_TAG_*, SE_*, template names kept as strings). Also
parse `src/data/moves_info.h` for move-ID → script binding (join against this project's
existing move IDs). Output: `data/battle_anims/scripts.json` (+ general/status scripts).
Deterministic, idempotent, ~1.5MB of JSON.

**A2. Metadata extractor** (`scripts/gen_battle_anim_meta.py`): parse the C sources for
(a) `gBattleAnimTable` → tag id, gfx file, palette file, VRAM size; (b) all 1,149
`SpriteTemplate`s → tag, oam size (from the 72 gOamData names), anims/affineAnims
symbol, callback name; (c) `ANIMCMD`/`AFFINEANIMCMD` sequences → frame lists.
Output: `data/battle_anims/templates.json`, `tags.json`, `frames.json`.

**A3. Asset pull** (`scripts/gen_battle_anim_sprites.py`): all table-reachable sheets →
`assets/sprites/battle_anims/<tag_name>.png` with index-0 transparency tagged
(existing `_tag_transparent_and_save` pattern); standalone `.pal` recolors baked into
palette-swapped PNG copies at extraction time (Godot has no indexed-palette runtime —
this is the established approach, and only 46 recolors exist); the 5 concat sheets
assembled; `B_NEW_*` FALSE branch. Backgrounds deferred to Phase E. Smoke test asserting
counts/dimensions against `tags.json`.

### 5.2 Phase B — runtime core

- **`AnimScriptVM`** (`scripts/battle/anim/anim_script_vm.gd`, RefCounted): program
  counter over the JSON command list, call stack (depth 4), `args[8]` with slot-7
  returns, visual/sound task counters, per-frame pump driven from a single
  `_process`-owned clock (the MonAnimator `Clock` precedent — GBA frame = 1/60s).
  Waits: `delay`, `waitforvisualfinish`, `waitsound` (no-op initially), bg waits.
  `monbg/clearmonbg/splitbgprio` = no-ops (Godot blends freely); `setalpha` sets a
  current particle-alpha context; `end` force-cleans stragglers (mirroring the
  reference's auto-free) and resolves the beat's await.
- **Stage adapter**: battler anchor/coord provider mapping GBA positions
  (`sBattlerCoords` singles/doubles + species Y offset) onto the existing battle-stage
  sprite nodes; direction-aware X mirroring; subpriority → z_index/EffectLayer child
  ordering around the battler sprites.
- **Sprite host**: `AnimSprite` node (TextureRect or Sprite2D) constructed from a
  template entry: sheet + frame list playback (tile-offset → frame index), affine
  sequences → scale/rotation tweens, callback dispatched from a **behavior registry**
  (`String → Callable`); missing callback = registry miss.
- **Fallback contract**: before launching, the VM checks the script's referenced
  callback/task set against the registry. Any miss → the whole move falls back to the
  current generic effect (never a half-played script). Per-move override list can force
  fallback for anything that lands wrong.
- Integration point: replace the `match move_id` in `_on_hit_effect_move_executed`
  with `AnimDispatcher.play(move, attacker, defender)` behind the same `anim` beat.
  The two-turn (`choosetwoturnanim` — needs the charge-turn signal from BattleManager)
  and multi-hit `animTurn` inputs wire from existing battle state.

### 5.3 Phase C — core behavior batch (the big fidelity jump)

~25 behaviors chosen by frequency, covering the physical-contact archetype (≈400+
moves) and the most common particle motions:

- Sprites: `AnimHitSplatBasic` (+ random-pos variant), `AnimToTargetInSinWave`,
  `TranslateAnimSpriteToTargetMonLocation`, `AnimThrowProjectile`,
  `AnimTravelDiagonally`, absorption/power orbs, fist/foot/chop frames, basic
  linear/arc/circle translation callbacks, the 7 invisible mon-movement drivers
  (lunge/dip/slide-to-offset/-and-back).
- Tasks: `ShakeMon`/`ShakeMon2`/`ShakeMonInPlace`, `BlendBattleAnimPal` (modulate
  lerp per selector; full-screen tint layer for F_PAL_BG), `blend_color_cycle`/
  `simple_palette_blend` equivalents, `TraceMonBlended` (afterimages) if cheap, and
  the query one-liners (`IsContest`→false, `IsDoubleBattle`, side getters).
- Acceptance: Pound, Tackle, Double Slap (multi-hit variation), Quick Attack, and the
  redone **Flamethrower** (22-flame sine stream + shakes) all read as the reference at
  1× speed; everything unimplemented still plays the generic effect.

### 5.4 Phase D — batched expansion + coverage report

A `--coverage` mode on the test suite: for each of the 717 implemented moves, resolve
script → referenced behaviors → % implemented / falls-back-and-why. Batches then go by
**this project's actual encounter surface** (Kanto trainer movesets + learnsets from
`data/`, not all 941 scripts — expansion's Gen 6-9 one-offs in `battle_anim_new.c` are
the long tail and mostly unreachable here). Suggested batch order: electric (Thunder
redo), water/ice, fire completion, psychic/ghost dark, status-move staples
(growl/leer/screech rings, powder sprinkles, stat-change arrows via the General script),
then per-type sweeps.

### 5.5 Phase E — backgrounds & screen effects (optional, later)

`fadetobg`/`restorebg` with a decoded-BG library (same tilemap decode already in-repo),
full-screen invert/flash tasks, `panse` sweeps. This unlocks the last mile for Thunder/
Solar Beam/Hyper Beam-class showpieces. Cleanly severable; scripts referencing
unimplemented BG commands simply skip them (BG opcodes are cosmetic framing, and the
fallback contract in 5.2 only gates on sprites/tasks).

### 5.6 Sound — flagged decision, default: defer

The project currently has no battle SFX at all, so move anims without SFX are not a
regression. Faithful SFX = render 132 `se_m_*.mid` files through the GBA voicegroups
(a real sub-project: build a soundfont from the 105 samples + ADSR tables, batch-render
to .ogg) or capture from a built ROM. Recommendation: keep `playsewithpan`/`panse` as
structured no-ops that already carry SE id + pan args in the extracted JSON, so a future
SFX pass is pure asset work with zero re-extraction. Do not block any phase on audio.

### 5.7 Explicit exclusions

Contest branches (`jumpifcontest` → never taken), Z-Move/Max/Tera backdrops and
general anims (mechanics excluded from this project), ball throw (M26B7), the
`teamattack_*` opcodes (unused even in source), `nop`/`nop2` (unused), Safari
(`ANIM_TAG_SAFARI_BAIT` is a hole even in source).

---

## 6. Sizing and sequencing

| Phase | Content | Size feel (project-session idiom) |
|---|---|---|
| A | 3 extractors + JSON data + smoke tests | 1-2 sessions |
| B | VM + stage adapter + fallback + beat integration + headless parse-all-941 test | 2 sessions |
| C | ~25-behavior core batch + 3-5 acceptance moves incl. Flamethrower redo | 2-3 sessions |
| D | per-batch, open-ended, each independently shippable | 1 session per batch |
| E | backgrounds/screen effects | 1-2 sessions |

Recommended roadmap treatment: **close M26F1's research half with this document**, keep
the balance/setup fix in M26F1, and open a new milestone (next free number) titled
"Move animation engine" with sub-tiers A-E — exercising the split-out option CLAUDE.md
already reserved for M26F. M26 itself stays a graphical/UI milestone and can close
without waiting on animation batches.

**DECIDED 2026-07-29 (see §7): this is now milestone M36 — Move Animation Engine**,
sub-tiers M36A-M36E mapping to phases A-E above, plus **M36-S (SFX & audio surface)**
per amended decision 3. Phase D's batch order is superseded by decision 5
(iconic Gen 1-3 → remaining Gen 1-3 → rest of 717).

### M36A — COMPLETE 2026-07-29

All three extractors built, run, and verified; `m36a_anim_extract_test` **71/71**.
Regression: `hit_effect_smoke_test` 91/91, `hit_effect_dispatch_test` 40/40,
`battle_ui_sprite_smoke_test` 222/222. All three generators verified idempotent
(byte-identical re-run).

| Script | Output | Result |
|---|---|---|
| `gen_battle_anim_scripts.py` | `data/battle_anims/scripts.json` (1.3 MB) | **32,318 commands**, 1,834 labels, 1,024 exports (**941** `gBattleAnimMove_`, matching the recon), **933** move-id bindings, general 64 / status 10 / special 8 |
| `gen_battle_anim_meta.py` | `tags.json`, `templates.json`, `frames.json` | **412** tag rows (410 real + 2 NULL), **1,148** sprite templates, 284 anim + 325 affine sequences, 166 + 178 pointer tables |
| `gen_battle_anim_sprites.py` | `assets/sprites/battle_anims/` + `index.json` | **410 PNGs**, 5 composites assembled, **101 palette recolors baked** |

**Six source realities found during implementation that the recon had not
recorded** — each caught by a failing run or by the suite, none assumed:

1. **GAS whitespace-separated macro args.** `loopsewithpan SE_M_SELF_DESTRUCT,
   SOUND_PAN_TARGET 10 3` mixes commas and spaces, while macro bodies emit
   `256 * \x_velocity` (spaces *inside* one argument). The splitter separates on
   commas/whitespace but re-merges tokens whose boundary touches an operator.
2. **Constants live in enums as well as `#define`s** (`SHAKE_MON_Y`, the
   `AnimBattler` set) — the loader parses both, chaining implicit enum values.
3. **`.if/.else/.endif` appear at TOP LEVEL in the `.s` file**, not only inside
   macro bodies (`B_UPDATED_MOVE_DATA >= GEN_7` gates two script variants).
4. **`ANIM_BATTLER` is used but defined nowhere in the reference.** It assembles
   only because `createsprite` never emits the battler symbol as data — it is
   compared for symbol identity against `ANIM_TARGET`, and an undefined symbol
   compares unequal. Baked to the attacker-side basis, documented at the site.
5. **The five composite sheets concatenate TILE DATA, not images**, and their
   parts have different pixel dimensions (spark_0 8×64 + spark_1 16×64;
   ice_cube 64×64/64×32/32×64/32×32). Naive image stacking would have been
   wrong. Parts are decomposed to 8×8 tiles, concatenated as a stream, re-laid
   out, and the tile count asserted against the tag's declared VRAM size.
6. **Three C-level reference patterns the naive model missed**, all found by the
   suite's cross-reference checks: two frame-sequence symbols are file-scoped
   statics that **collide across translation units** (`sAnimCmdAnimatedSpark2`,
   `sSpriteAffineAnim_DoNothing`) so keys are file-qualified; some frame tables
   are **non-static globals referenced cross-file** (`gSolarBeamBigOrbAnimTable`
   lives in `effects_1.c`, used from `new.c`); and some templates point
   **part-way into** a shared table (`.anims = &gAnims_PoisonProjectile[1]`),
   now preserved as an explicit `anims_offset`. Plus one upstream typo — a stray
   `goto ParabolicChargeHeal;` semicolon.

**Correction to §2.4 of this document**: it states "3,110 `ANIMCMD_FRAME`".
That figure counts **all of `src/*.c`** (3,032 occurrences). Within
`src/battle_anim*.c` — the only files that matter here — there are **1,431
total**, i.e. **784 plain `ANIMCMD_FRAME` + 647 `AFFINEANIMCMD_FRAME`**. The
extraction reproduces both counts exactly, and the suite pins them.

**Ready for M36B**: the VM has a self-describing program (`meta.opcode_signatures`
publishes every opcode's field order), a resolved label→index map, and verified
end-to-end chains script → template → tag → sheet → frame sequence.

**Self-review finding, fixed same session.** The script extractor's docstring
claimed the evaluator "asserts no negative-operand division ever occurs"; the
`_c_div`/`_c_mod` helpers written for that were never wired, and the premise was
false — 20 division sites do take a negative operand (`256 * -819 / 256` and
kin). Verified empirically that **all 19 distinct mixed-sign expressions are
exact**, so C truncation and Python flooring agree and every extracted value was
already correct. The guard is now real (`_assert_c_division_safe`, run on every
evaluation) so a future reference update introducing an inexact negative
division fails loudly instead of shifting an animation offset by one pixel
unnoticed. Output is byte-identical after the fix; suite still 71/71.

**Known gaps carried into later sub-tiers (deliberate, not oversights):**
- **Backgrounds are not extracted** — the 84-entry `gBattleAnimBackgroundTable`
  and its tiles/tilemaps/palettes belong to **M36E**, per the phase plan.
- **23 sprite sheets reachable only by C symbol, not by ANIM_TAG**, are not
  pulled: `substitute*`/`monster_doll*` (the Substitute swap visuals),
  `smokescreen_impact`, `particles`/`particles2` (ball-open particles, owned by
  **M26B7**), and the 15 composite part files. Nothing in a move script
  references them; whichever sub-tier needs them pulls them then.
- **Sound is intentionally data-only**: SE ids and pan values are resolved to
  ints and carried in the command stream as structured no-ops for **M36-S**.
- The suite samples transparency on 5 sheets rather than decoding all 410
  (geometry, alignment and load are checked on every one) — a deliberate
  runtime trade recorded in the test itself.

### 6.1 Why this supersedes the 2026-07-19 "bounded exception only" stance

That decision priced two options: (1) the shipped hybrid, (2) an unbounded full port.
The data in §2 exposes a third: the system's own head-heaviness makes a *partial* port
coherent — the VM is small, scripts are data, behaviors are independently portable, and
fallback makes every intermediate state shippable. The hybrid's own assets and dispatch
survive as the fallback tier, so nothing shipped is discarded.

---

## 7. Decisions — RESOLVED (Rob, 2026-07-29)

1. **Go/no-go: GO — full tiered port** (phases A-E with the fallback contract). The
   hand-tune-3-moves alternative is dead.
2. **Split-out: YES — new milestone M36** (next free number; M32/M34 are retired
   tombstones and are not reused, per the roadmap's own convention). Phases A-E become
   M36's sub-tiers; M26F1 retains only the balance/setup fix, and M26 can close
   without waiting on animation batches.
3. **Sound: defer with structured no-ops as proposed, AMENDED** — M36 gains a
   dedicated **SFX section** (M36-S): it owns the future audio pass for move-animation
   SFX (rendering the 132 `se_m_*.mid` files through the GBA voicegroups, or ROM
   capture — the extracted JSON already carries SE id + pan per cue), **and it must
   also note/scope the project's other missing audio** (the project currently has NO
   audio at all: battle music, cries, UI SEs, fanfares are all absent). M36-S starts
   with its own recon of that full audio surface; move-anim SFX is its first
   consumer, not its whole scope.
4. **Fidelity bar: 1× GBA frame-accurate** (60fps frame-for-frame, the
   MonAnimator/weather precedent) is the acceptance standard.
5. **Batch prioritization (Phase D): full 717-roster coverage, ordered as** —
   (1) **iconic Gen 1-3 moves first** (the visually recognizable showpieces:
   Thunder, Hyper Beam, Solar Beam, Surf redo, Blizzard, Fire Blast, Psychic,
   Earthquake, Hydro Pump, etc. — the batch list to be drawn up at Phase D start),
   (2) **remaining Gen 1-3 moves**, (3) **the rest of the 717**. This supersedes
   §5.4's Kanto-encounter-surface recommendation; the coverage report still gets
   built, but ranks by this ordering rather than encounter frequency.
