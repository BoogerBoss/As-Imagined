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

### M36B — COMPLETE 2026-07-29

The runtime core. `m36b_anim_vm_test` **53/53**; regression across every
battle-screen-dependent suite green (m36a 71/71, hit_effect dispatch 40/40 +
smoke 91/91, trainer/category/party 128/128, b3_6c 168/168, ui_polish 26/26,
item_select 31/31, switch_select 42/42, debug_log 57/57, weather_asset 33/33).

| File | Role |
|---|---|
| `scripts/battle/anim/anim_data.gd` | Loads/caches the four M36A products + sheet textures; resolves a template's frame sequences through its file-qualified key and offset |
| `scripts/battle/anim/anim_behavior_registry.gd` | `symbol -> Callable`, plus the **static walk** that decides fallback |
| `scripts/battle/anim/anim_script_vm.gd` | The interpreter: frame-pumped execution, 8-slot arg register file, 4-deep call stack, completion accounting, runaway guards |
| `scripts/battle/anim/anim_stage.gd` | Anim-battler -> real sprite node bridge (centres, rects, facing sign, partner resolution) |
| `scripts/battle/anim/anim_dispatcher.gd` | The verdict + VM construction + the coverage report M36D sequences from |

**The fallback contract is live and enforced.** Every move now routes through
the dispatcher first; with an empty registry all 932 bound moves decline and
take the existing hit-effect path, so this sub-tier changes no pixels while
making the seam real and tested. Verified directly: `playable == 0` across the
whole roster, and a script whose behaviors are only PARTLY registered still
falls back (all-or-nothing per move -- a half-played script is worse than the
generic effect it replaces).

**Sized by the suite, from the real data**: **587 distinct behaviors** across
**932 move scripts**. Top blockers -- `AnimTask_ShakeMon` (436 moves),
`AnimHitSplatBasic` (386), `AnimTask_ShakeMon2` (368) -- which is the M36C
batch, confirmed by measurement rather than the recon's estimate.

**One upstream reality found by the suite**: `gBattleAnimMove_SecretPower`'s
body is literally just `end`. Upstream that is legal because
`LaunchBattleAnimation` REMAPS Secret Power at launch to whichever script the
terrain calls for, so the placeholder never executes. We do not model that
remap (Secret Power is permanently excluded from this project), and running an
empty script would render nothing where the generic effect renders something
-- a silent regression. So `Reason.EMPTY_SCRIPT` was added and such scripts
fall back too. It is the only move in that bucket.

**Disclosed as incomplete, not hidden**: `_anim_turn_for()` derives
`gAnimMoveTurn` from the attacker's charging state. That is correct for the
two-turn branch (`choosetwoturnanim`, the only thing a script branches on)
but not a true per-hit counter, so multi-hit variation (Double Slap's
alternating direction) will need the real counter in M36C.

### M36C — COMPLETE 2026-07-29

The first real behavior port. `m36c_anim_behaviors_test` **66/66**; full
regression sweep green (m36a 71/71, m36b 53/53, hit_effect 40/40 + 91/91,
trainer/category/party 128/128, b3_6c 168/168, ui_polish 26/26, switch 42/42,
item 31/31, debug_log 57/57).

**24 behaviors ported**, line-for-line from the C, in two new files:
`anim_sprite.gd` (the OAM-sprite stand-in: tile-offset framing, centre-origin
positioning, x2/y2 offsets) and `anim_behaviors.gd` (the batch itself) —
shakes (ShakeMon / ShakeMon2 / ShakeMonInPlace), the hitsplat family with its
four affine size presets, `AnimToTargetInSinWave` (Flamethrower's beam),
linear travel, the invisible controller sprites (lunge / dip / slide), the
palette-blend family, and the single-frame query tasks.

**Acceptance set met**: Pound, Tackle and **Flamethrower** now play their real
scripts — verified end to end, including that Flamethrower spawns its full
**22-flame stream** with several airborne at once, rather than the single
static puff the legacy hit-effect showed.

**The headline finding — coverage climbs slowly at first, and that is
structural.** The batch moved the roster from 0 to **23 of 932** playable
(2.5%). That is not underperformance: a move plays only when EVERY behavior
its script reaches is ported, so the most common behavior unblocks almost
nothing alone — each script also needs its own particular effects. Two
consequences worth carrying into M36D: (1) batch value should be judged by
how much *shared machinery* it retires, not by the immediate move count, and
(2) the count accelerates as the shared core fills in and only per-move
specifics remain. Post-batch top blockers are already far smaller than
pre-batch (`AnimTask_StartSlidingBg` 83 moves, down from `AnimTask_ShakeMon`'s
436).

**A real bug in M36B's fallback walk, found by this suite**: the walk did not
stop at `return`, so it ran off the end of a `call` subroutine into whatever
script sat next in the command array — Flamethrower appeared to require
SANDSTORM tasks. Conservative (it over-blocked rather than mis-played), but it
suppressed coverage and made the blocker ranking wrong: the pre-fix "top
blockers" figures in M36B's own notes are inflated for that reason. Fixed;
`_finish()` now also zeroes the completion counter so an aborted run leaves
nothing behind.

**Disclosed approximations** (each visible in the code at its site):
`AnimTask_BlendParticle` tints the live sprites of a tag rather than a palette
(Godot has no runtime palette indirection); `AnimTask_StartSinAnimTimer` is a
no-op because each beam particle carries its own phase, as the per-sprite data
slots do upstream; BG-selector palette blends consume their frames but draw
nothing until M36E builds the background layer.

### M36D — first expansion batch, 2026-07-29 (ONGOING sub-tier)

M36D is the open-ended batch tier, so this records the first pass rather than
a completion. `m36d_batch_test` **66/66**; full regression sweep green
(13 suites, including all prior M36 work).

**New tool: `scenes/battle/m36_coverage_report.tscn`.** Not a test — the
sequencing instrument the recon called for. It tiers the roster per Rob's
decision 5 (**Gen 1-3 verified from source as move ids 1-354**:
`MOVE_PSYCHO_BOOST = 354`, `MOVES_COUNT_GEN3` follows), reports playable
counts per tier, and — the part that actually drives decisions — runs a
**greedy "what to port next"** pass. That matters because the most-*referenced*
behavior is usually a poor choice: it may be shared by a hundred moves that
each still need five others. The greedy pass instead asks which behavior would
*complete* the most moves, which is the question that predicts coverage
movement. The iconic set is an explicit editorial judgment with its criteria
written into the tool, so it is auditable rather than tacit.

**20 more behaviors ported**, chosen by that report: the powder/spore
families, vortex particles, the slice family, Bite, Vine Whip, the
Ember/travel-diagonally family, Fire Spread, the fist/foot set, Endure energy,
the absorption orb, bubbles, single-sine-wave travel, and the mon tasks
(scale-and-restore, sway, elliptical translation and its side-respecting
variant), plus shared arc-travel and cel-lifetime helpers.

**Coverage after batch 1: 23 -> 85 of 932 (2.5% -> 9.1%).** Per tier: iconic
Gen 1-3 **3 -> 12 of 70**, remaining Gen 1-3 12 -> 37, Gen 4+ 8 -> 36.

**Batch 2 (same session): 85 -> 138 of 932 (9.1% -> 14.8%).** Iconic Gen 1-3
**12 -> 18 of 70 (25.7%)**, remaining Gen 1-3 37 -> 56 (19.8%), Gen 4+
36 -> 64 (11.1%). 29 more behaviors, again family-grouped: the projectile
family (Shadow Ball, water-bubble, bone-hit, stinger, missile-arc), the
seed/leaf/rock family (Leech Seed's three phases, razor-leaf flutter, falling
rock, frenzy-plant root), mon visuals (afterimage tracing, fly-up, jump-kick,
dizzy-punch duck, claw slash, on-mon-for-duration, shake-and-sink), the
complex palette blend and grayscale ops, the defensive wall (Reflect/Light
Screen), and the sound-task set.

**Batch 3 (same session): 138 -> 200 of 932 (14.8% -> 21.5%).** Iconic
Gen 1-3 **18 -> 31 of 70 (44.3%)**, remaining Gen 1-3 56 -> 68 (24.0%),
Gen 4+ 64 -> 101 (17.4%). 22 more behaviors: the mon-task family (horizontal
shake with its ring-down, wind-up lunge, sprite rotation and its restoring
variant, teleport, Dynamax growth, blend-in-and-out, the shake controller
sprite) and a particle set (wall sparkle, bullet seed's fly-then-scatter,
sunlight, raindrops, dirt scatter, roar noise lines, rock fragments, twister
particles, fire spiral, Protect's shield, revenge scratch, assist pawprint,
swirling fog).

**The family rule keeps holding, and the trend is now clear**: batch 1 got
62 moves from 20 behaviors, batch 2 got 53 from 29, batch 3 got 62 from 22.
Roughly 2-3 moves per behavior, sustained -- so M36C's "one behavior per one-
to-three moves" was right in magnitude but pessimistic about which end of
that range family-grouping lands on.

**A third bug in the fallback walk, found while porting batch 2**:
`createsoundtask` symbols were treated as required behaviors, but the VM
handles that opcode itself (it records the cue for M36-S and moves on) and
upstream those tasks report to a SEPARATE counter that `waitforvisualfinish`
never waits on. Moves were being blocked on symbols nothing would ever call.
Removing them from the walk unblocked 3 moves immediately.

**Sound is deferred but TIMING is not.** The sound tasks are registered as
structured no-ops that still reproduce their frame cost, because upstream the
distinction is real: most are single-frame, but the cry tasks block a script
until the cry finishes. With no audio a cry is "finished" immediately after
its two warm-up frames, so that is what the port costs. Collapsing every
sound cue to zero frames would have quietly sped up a number of scripts.

**This revises M36C's "linear grind" expectation upward.** M36C measured the
best next behavior as unlocking ~6 moves and concluded progress would be
roughly one behavior per one-to-three moves. In practice 20 behaviors bought
62 moves — better than 3:1 — because porting a *family* retires the shared
helpers its neighbours also need. The lesson for later batches: pick by
family, not by individual rank.

**A fidelity bug the test doubles were hiding, found by inspecting the real
scene.** Offsets were scaled by `pixel_scale()` (the stage is ~4.3x the GBA
canvas) but the sprites themselves were not, so a 32x32 particle drew 32 px
wide on a 1024-wide stage while being flung 4x further than it should -- a
"beam" would have rendered as a scatter of specks. Sprites now render at the
same scale their offsets use. Related: the test doubles used plain `Control`
nodes for battlers where the real scene uses `TextureRect`, which silently
hid that afterimage cloning needs a texture to copy; the doubles were made
faithful rather than the code loosened.

**The M36E-gated set is now well defined**, and it is the single biggest
remaining blocker: `AnimTask_SetPsychicBackground` (8 moves),
`AnimTask_MetallicShine` (5), `AnimTask_StartSlidingBg`, the platform-shake
paths of `AnimTask_HorizontalShake` (arg 0 == 5) and
`AnimShakeMonOrBattlePlatforms` (SHAKE_BG_X/Y, which write `gBattle_BG3_X/Y`),
and `AnimTask_HazeScrollingFog`. Those two shake paths are implemented for
their SPRITE variants and consume their frames for the BG variants, so script
pacing stays right and only the visual is missing. Note the fog case was
checked rather than assumed: `InitSwirlingFogAnim` is a pure sprite and was
ported; it is `AnimTask_HazeScrollingFog` that is the BG one.

**Two iconic moves are gated on M36E, not on more behaviors.** `Surf` and
`Metallic Shine` were investigated and deliberately NOT faked:
`AnimTask_CreateSurfWave` is **100% background-layer work** — a scrolling BG1
tilemap with a rotating palette cycle and a per-scanline BLDALPHA table, with
*no sprite motion whatsoever* — and `AnimTask_MetallicShine` needs an OBJWIN
mask clipped to the mon's silhouette. Both are real M36E dependencies, and
Surf is exactly the move M23.11 Phase 5b flagged as looking wrong today, so it
stays on the fallback until the background layer exists rather than getting a
plausible-looking substitute.

### Regression found in real play, fixed 2026-07-29 — the visibility leak

Rob played a battle and reported the opposing side not appearing. Real bug,
mine, and the mechanism is worth recording because the whole class was
invisible to the test suite:

**Animation scripts hide battlers and rely on the ENGINE to put them back.**
`invisible`/`visible` are ordinary opcodes, and 35 move scripts (Feint Attack,
Shadow Force, Sky Drop, Phantom Force, Fusion Bolt, Dragon Ascent, ...) end
with a battler still marked invisible on the path taken. Upstream that is
perfectly safe: the battle controller calls
`CopyAllBattleSpritesInvisibilities` (`src/battle_controllers.c:2146`)
immediately after every animation, re-syncing each sprite from real battle
state. **This port had no such re-sync, so one animation could remove a
Pokemon from the screen for the rest of the battle.**

Fixed at three levels, deliberately belt-and-braces because the failure is
silent and permanent:
1. The VM records every battler it hides and restores them in `_finish()`,
   so no code path can outlive its own hide.
2. `AnimTask_Teleport`'s deliberate hide now routes through that same
   tracked call rather than setting `visible` directly.
3. The battle screen calls `_refresh_ui()` after every animation — the direct
   analogue of the reference's own post-animation re-sync, which also
   restores health boxes and anything else an animation might disturb.

**Two lessons recorded rather than the fix alone.** First, the suite could
not have caught this: every test drove behaviors in isolation, and the leak
only manifests across an animation boundary in a live battle. There is now a
general invariant test ("no animation may leave a battler invisible once it
is over") plus an end-to-end run of Feint Attack specifically. Second, the
test double hid it twice over — its `set_battler_visible` was a no-op, so the
new tests initially passed while asserting nothing. That is the second time an
unfaithful double masked a real defect (the first was plain `Control` nodes
where the scene uses `TextureRect`), so doubles here are now written to
actually apply what they are asked to do.

### M36E1 — background asset pull, COMPLETE 2026-07-29

The asset half of the background layer. `m36e_background_asset_test`
**20/20**; generator verified idempotent.

`scripts/gen_battle_anim_backgrounds.py` composites **89 backgrounds** — all
**84** `gBattleAnimBackgroundTable` entries plus 5 code-referenced ones (the
Surf trio, its muddy-water recolor, and sandstorm brew). Unlike the sprite
pull this must COMPOSITE rather than copy: each background is a tilemap over
a tile sheet with per-cell flip flags, so it is the GBA screen-entry decode
this project has now done four times.

**The palette-bank rule was measured, not assumed — and the first cut was
wrong in the right direction.** It asserted a single palette bank per
background and consequently refused 19 of them, which is how the real rule
came to light: a background's CONTENT lives in one bank (2 for table entries,
8 for a couple of the others) while **bank 0 carries only the blank tile**
for empty cells. The assertion now allows the blank-tile bank and still
refuses content spanning two banks, because one 16-colour palette cannot
render that and it would come out miscoloured. Three assets legitimately fail
that test and are reported rather than silently dropped: `attract`,
`scary_face_player`, `scary_face_opponent`.

**Two guessed pairings were checked and removed rather than shipped**:
`solarbeam.bin` is marked `// Unused` upstream and the real Solar Beam
backgrounds are ordinary table entries; `fog.bin` has no matching `fog.png`
at all — its tiles come from another symbol, which the scrolling-fog behavior
will have to resolve when it is ported.

Decode verified by eye as well as by assertion: `BG_PSYCHIC` renders the
authentic diagonal wave, and the palette-only variants prove the recolor step
really applies (Hyper Beam and Hydro Cannon share tiles *and* tilemap
upstream, and come out visibly different).

**Still to come in M36E**: the runtime background layer plus the
`fadetobg`/`restorebg`/`changebg`/`waitbgfade*` opcodes (currently timing-only
no-ops), then the BG-dependent behaviors — `AnimTask_SetPsychicBackground`
(8 moves), `AnimTask_MetallicShine` (5), `AnimTask_StartSlidingBg`,
`AnimTask_CreateSurfWave` (Surf), the scrolling fog, and the platform-shake
paths whose sprite variants already work.

### M36E2 — background runtime, COMPLETE 2026-07-29

`m36e_background_runtime_test` **30/30**; 14-suite sweep green.

The six background opcodes were timing-only no-ops; they now really work.
`fadetobg`, `fadetobgfromset`, `changebg`, `restorebg`, `waitbgfadeout` and
`waitbgfadein` drive a real fade state machine ported from `Task_FadeToBg`
(`src/battle_anim.c:1750`): 16 frames to black, swap, 16 frames back, with the
two wait opcodes blocking on different phases exactly as
`sAnimBackgroundFadeState` makes them upstream.

Two nodes are created lazily inside `BattleStage` rather than authored into
both battle scenes: `AnimBgLayer` (inserted just above the battle backdrop and
BELOW the bases and battlers, so a swapped background sits behind the Pokemon
as it does on hardware) and `AnimFadeOverlay` (added last, so the fade darkens
the battlers and effect layer too -- upstream's is a hardware palette fade
across every palette, not a background-only dim).

**BG ids resolve through the extractor's own constant table**, not a second
hand-maintained map: `fadetobg` carries the integer the assembler emitted, and
`AnimData.bg_name_for_id` reverses it from the 74 `BG_*` constants M36A
already recorded.

**The leak lesson from the visibility bug was applied pre-emptively.** A
script that ends while its background is still up would leave the battlefield
permanently wearing a move's background — the same class of defect, with the
same silent-and-permanent character. So `_finish()` clears any background this
run swapped in and resets the fade, and the suite asserts that invariant
directly rather than trusting the scripts to call `restorebg`.

**Coverage is unchanged at 200/932, and that is correct**: these opcodes never
blocked a move (they were no-ops, not missing behaviors), so E2 buys FIDELITY
rather than coverage — the 198 `fadetobg` sites in already-playable scripts
now actually render. Unknown or unpulled background ids still consume the
fade's frames, so a script referencing one keeps its real pacing instead of
running measurably fast.

### M36E3 — BG-dependent behaviors, COMPLETE 2026-07-29

`m36e3_bg_behaviors_test` **52/52**; 17-suite sweep green. Coverage
**200 -> 228 of 932 (24.5%)**, iconic Gen 1-3 **44.3% -> 50.0%**.

**SURF PLAYS.** It had been one behavior short since M36D and no amount of
further sprite porting could reach it, because `AnimTask_CreateSurfWave` is
100% background work — there is no sprite motion in that animation at all.
Ten behaviors landed: the Surf wave, the psychic palette cycle,
`FadeScreenToWhite`, the sliding-BG pair, the platform shake, the scrolling
fog (plus its `MistBallFog` twin), the two storm-background loaders, and
`MetallicShine`.

**Four Step-0 findings reshaped this from its own scoping sketch.**

1. **`AnimTask_SetPsychicBackground` loads no background and scrolls nothing.**
It is an 11-colour palette ROTATION on the image `fadetobg BG_PSYCHIC` already
installed — and it runs at **32 call sites**, not the 8 the M36D pass
estimated. The extracted psychic palette's entries 1-11 are exactly a
red->purple->magenta ramp, so the rotation *is* the whole visual.

2. **Surf's cycle is the same mechanism with a 7-entry window**, so building
the psychic cycler delivered Surf's shimmer for free. That is why these two
shipped together rather than in separate batches.

3. **The orphaned `fog.bin` from E1 is now explained.** It pairs with
`graphics/weather/fog_horizontal.png` and `graphics/weather/fog.pal` — a
CROSS-DIRECTORY pairing nothing in the backgrounds directory hints at, which
is exactly why E1 was right to remove the orphan rather than guess.

4. **`AnimTask_ShakePlatforms` restores its CAPTURED offset, not zero.** The
background can legitimately be mid-scroll when a shake starts, so zeroing
would silently cancel it. Pinned by a test that starts the shake on an
already-scrolled background.

**The palette cycle needed new extracted data.** A composited RGBA image
records which colour each pixel ended up as, not which palette SLOT it came
from, so a rotation cannot be derived from the texture. The generator now
emits each background's 16 colours in palette order, and the runtime does a
per-pixel colour SUBSTITUTION in a shader — a background is ~40k pixels and
rebuilding 11 Images on the CPU would stall the frame the effect starts on.

**Two real defects were caught by the work rather than shipped.**

*(a) `MetallicShine`'s recolour was a no-op.* It went through `modulate`,
which MULTIPLIES — so grayscaling a default `(1,1,1)` modulate yields
`(1,1,1)` and the effect would have been invisible. This is the identical trap
`[M26B3-6a]` hit when the recall's pink came out invisible twice; the fix is
the same answer, a real `mix()` shader. Caught by the suite's own first run.

*(b) The scroll support regressed how EVERY background draws.* Adding scroll
first switched the layer to `STRETCH_TILE` so a long scroll could wrap. That
renders a 256px-wide GBA background at native size, tiled — four small copies
across a 1024px canvas, reading as thin stripes rather than a wave. **Found by
screenshot, not by any assertion**, and not by the move under test: the tiling
was wrong for the plain E2 backgrounds too. Fixed by scrolling through a UV
offset in the shader instead, so the layer still stretches to cover the stage
while `fract()` does the wrapping the hardware register does. The scroll and
the palette cycle share ONE shader, because a CanvasItem has one material.

**Verified visually, not just by assertion**: a real windowed capture of Surf
shows the wave filling the stage with visible crest structure, and 68% of
sampled pixels change between consecutive frames — it genuinely scrolls and
cycles rather than sitting still.

**The wave is blue-violet, and that is correct.** It looks wrong against an
expectation that water is blue, so it was checked rather than assumed:
`gBattleAnimBgPalette_Surf` *is* `water.png`'s own embedded palette
(`INCGFX_U16("...water.png", ".gbapal")`) and `B_NEW_SURF_PARTICLE_PALETTE` is
FALSE, so E1's pull already had the source-exact colours.

**Disclosed unported, both recorded at their code sites:**
`AnimTask_SurfWaveScanlineEffect` is an HBlank per-scanline offset giving the
wave its rippled edge — there is no scanline hook to port it to, so the wave
is a clean diagonal sweep; and `MetallicShine`'s OBJWIN stencil is
approximated with a duplicate of the battler's own texture, since there is no
object-window equivalent. Every frame count, direction and phase boundary in
both IS source-exact.

**Also disclosed**: the sliding-BG updater and the psychic cycle are
registered as UNCOUNTED steppers. That is not an optimisation — upstream both
decrement `gAnimVisualTaskCount` at setup precisely so `waitforvisualfinish`
does NOT wait for them, because they are open-ended effects torn down by an
explicit `setarg 7, -1`. Counting them would hang the script forever, which is
why the suite asserts the accounting directly.

### M36D batch 4 — COMPLETE 2026-07-30

`m36d_batch_test` 121 -> **165/165**; 18-suite sweep green. Coverage
**228 -> 290 of 932 (31.1%)**, iconic Gen 1-3 **50.0% -> 62.9%** — the
largest single batch so far.

23 behaviors across 8 families. **Step 0 did most of the work by collapsing
the list**: four of them (PowerAbsorptionOrb, RaiseSprite, AirWaveCrescent,
DragonFireToTarget) are literally the same shape upstream — set a start, set
duration/destination, hand off to `StartAnimLinearTranslation` with a stored
destroy-callback — so all four are one call to the `_linear_travel` helper
M36C already built. And three PAIRS are the same function under two names
(Fang/WhipHit_WaitEnd; KnockOffStrike/LashOutStrike; NeedleArmSpike/
MindBlownExplosion share a step). Registering both names against one
implementation is correct, and the suite asserts it so a later session doesn't
"fix" the duplication by writing a second, divergent copy.

**Two real defects, both found by the tests, both systemic rather than
per-behavior.**

*(a) `AnimSprite` had no `animEnded` concept at all.* `is_finished()` only
ever reported whether `finish()` had been CALLED — nothing set it when a frame
sequence actually ran out. An entire upstream idiom depends on that flag
(`RunStoredCallbackWhenAnimEnds` is how Fang, Slash, Knock Off and the whole
False Swipe / Cut family decide they are done, with no frame count anywhere),
so those behaviors had nothing to wait on and ran forever. Added a real
`anim_ended()` driven by the sequence hitting its `end`, plus a frame cap as a
safety net — because a LOOPING sequence never ends, on hardware or here.

*(b) The VM restored visibility and backgrounds but never DISPLACEMENT.*
`AnimTask_SlideOffScreen` deliberately leaves the battler off-screen — upstream
the script that used it always followed up — so it would have parked a Pokemon
off the edge of the battlefield for the rest of the battle. That is the exact
silent-and-permanent shape as the M36D visibility leak, so it got the same
treatment: `_finish()` now restores every battler carrying MonOffset's own
recorded base, a systemic net rather than a per-task patch. It reads the meta
MonOffset already writes, so it cannot disagree with whatever moved the sprite.

**Three upstream oddities reproduced deliberately rather than tidied**, each
recorded at its code site: `DragonFireToTarget` takes its opponent-side
horizontal offset from `args[1]` (the Y argument) — very likely a typo in the
reference, but the scripts were authored against the result;
`RandomCentredHits` genuinely aliases args 0 and 1 as both selector/variant and
x/y offset; and `GetReturnPowerLevel`'s thresholds leave a gap at exactly 60
which falls through to the weakest band, because upstream's comparisons are
sequential rather than `else`-chained.

**One upstream bug NOT reproduced**, also recorded: `AttackerPunchWithTrace`
subtracts the SPRITE ID from `x2` during setup, mixing an object handle into a
coordinate. It is masked by the explicit `x2 = 0` at the end of the return leg,
so porting it would add a garbage displacement with no visible intent.

**Disclosed simplifications:** `AnimTask_SporeDoubleBattle` is a genuine
structured no-op — upstream it only reorders per-battler BG priority ranks, a
concept this port does not have — registered anyway precisely so it stops
gating the moves that call it. And friendship is not modelled on the battle
side, so `GetReturnPowerLevel` reports the weakest band and Return plays its
smallest burst rather than being blocked.

**Verified visually**: a real windowed capture of Slash shows the slash marks
landing on the target with correct positioning.

**Sequencing note for whatever comes next**: this batch took nearly all the
cheap iconic wins. Exactly ONE one-away behavior remains (`AnimPsychoBoost`),
and every other still-blocked iconic move now needs 2+ new behaviors — Swords
Dance 2, Water Gun 2, Ice Beam 2, Aurora Beam 2, Hyper Beam 2, Slash 2, Solar
Beam 2, Blizzard 3. The port's cost per iconic move is rising, which is the
context that makes **M36-H** (hand-authored animations as a per-move escape
hatch) worth evaluating now rather than later.

### M36D batch 5 — COMPLETE 2026-07-30

`m36d_batch_test` 165 -> **204/204**; 18-suite sweep green. Coverage
**290 -> 356 of 932 (38.2%)**, iconic Gen 1-3 **62.9% -> 70.0%**.

**The selection method changed, and that is the point.** Batch 4 had taken
nearly all the cheap wins, so the greedy value had flattened from +6 to +3 and
the coverage tool had begun reporting a new category — behaviors that BLOCK
moves while being worth nothing alone (`AnimTask_ElectricBolt`, "blocks 3,
none one-away"). Picking by greedy value would score those zero and skip them
forever. So batch 5 was **cluster-driven**: whole elemental families, chosen so
co-blockers land together.

It beat its own projection (~330-340 estimated, 356 actual), which is the
family rule holding: porting a family retires the shared helpers its
neighbours also need.

**Step 0 corrected an expectation before any code was written.** Only ONE of
the 31 (`AnimSwordsDanceBlade`'s second phase) collapses onto the
`_linear_travel` helper M36C built. The rest use genuinely different
translation machinery — arc, fast-linear-with-speed, or raw 8.8 velocity — so
they were deliberately NOT forced onto one helper. One new shared shape did
fall out: `_velocity_travel`, the port of `TranslateSpriteLinearFixedPoint`.
Four alias groups were also found and registered against single
implementations (SkillSwap/HeartSwap; Stockpile/SpitUp/Swallow deform; the
three FrozenIceCube variants; Stretch target/attacker).

**The palette group needed a real judgement, and the answer differed per
behavior**, which is why it was worth asking up front:

* `AnimFlashingHitSplat` does **no palette work at all** — it toggles
  visibility for 14 frames. It is in that group by name association only.
* `AnimTask_FlashAnimTagWithColor` touches exactly one OBJ palette, which here
  is 1:1 with a sprite sheet, so it maps cleanly onto tinting every live
  sprite of that tag. Disclosed: upstream also catches sprites spawned LATER
  while the blend is applied; that is not emulated.
* `AnimTask_BlendBattleAnimPalExclude` is **genuinely un-portable as a palette
  operation** — it blends by palette SLOT, a set that includes the
  battle-background palettes and in which two battlers can share a slot, so it
  does not decompose into a per-object list. Ported as the nearest thing a
  compositing engine can express: tint the background layer and every battler
  except the excluded one, on the same coefficient ramp.

**Reused rather than duplicated:** an earlier batch already had a blend ramp
(`_run_blend`). The exclude-variant was routed through it via a new node-list
core rather than shipping a parallel implementation — matching upstream, where
both variants also share one function.

**FLAGGED, NOT FIXED** (pre-existing, predates this batch): that shared ramp
blends through `modulate`, which MULTIPLIES rather than replacing — the same
weakness behind MetallicShine's no-op grayscale and the twice-invisible recall
pink. It is less wrong here (a blend toward a colour still shifts a multiplied
sprite) and the correct shader now exists, but switching it would change
values M36C's own suite asserts, so it is left for a deliberate pass rather
than changed underneath a batch.

**A miss worth recording honestly:** the water/ice cluster was chosen partly
to unblock Water Gun / Ice Beam / Aurora Beam / Blizzard, and it did **not** —
their real blockers are `AnimIceBeamParticle` and `AnimIceEffectParticle`, not
the FrozenIceCube/bubble behaviors picked. Coverage still beat projection, and
Swords Dance and Hyper Beam *were* unblocked, but the specific iconic targets
were not verified against their actual blocker lists before picking. Next
batch should read each target move's own missing set rather than inferring it
from a family name.

**Verified**: Swords Dance captured on a real windowed run, rendering
correctly. The lilac tint visible on the opponent mid-animation is the
exclude-blend working as intended, and it was checked rather than assumed —
a full run leaves every battler back at neutral, because the script pairs its
blend calls exactly as source does. That check is now a permanent assertion,
since this would have been the third leak of its class in M36 after visibility
and displacement.

### M36 blend ramp — replace-semantics fix, COMPLETE 2026-07-30

`m36d_batch_test` 204 -> **205/205**; 16-suite sweep green. **Coverage
deliberately unchanged at 356/932** — this is a FIDELITY fix, not a coverage
one, and that is the whole point of doing it.

**The defect.** The shared blend ramp (`AnimTask_BlendBattleAnimPal`, its
Exclude variant, and `AnimTask_BlendColorCycle`) blended through `modulate`,
which MULTIPLIES. `BlendPalette` (util.c:224) REPLACES a channel toward the
target. Multiplying a white-modulated sprite toward white is the identity, so
**every blend toward white rendered as nothing at all**.

**Measured before deciding, not asserted.** Across the extracted scripts:
126 of 777 blend call sites (16%) target white or near-white and rendered
nothing; another 141 (18%) target other light colours and were visibly
weakened; 261 (34%) target dark colours and were already correct. Pure white
is the second most common blend colour in the entire roster after black.

This is the **third** time this project has hit the modulate-multiply trap,
after the twice-invisible recall pink and MetallicShine's no-op grayscale, so
the fix is the same `mix()` shader the second of those introduced.

**Why it was worth doing before more batches**: it degrades moves ALREADY
counted as playable, so the coverage figure was overstating what actually
renders. It is also a fair-comparison prerequisite for M36-H — judging a
hand-authored animation against a ported one that is silently missing its
flash would rig that comparison before anyone looked at it.

**A blast-radius claim of mine turned out to be wrong, in the good
direction.** Batch 5 flagged this as "would change values M36C's own suite
asserts". It does not: M36C's only `modulate` assertion is about sprite ALPHA
via `setalpha`, unrelated to the palette ramp. The only dependent assertions
were the two written in batch 5 itself.

**A second correction, this one to my own measurement.** An initial count
claimed 278 moves blend toward white. That was inflated 3.3x by a naive walk
that scanned 120 commands past each move's label without stopping at
`end`/`return` — so it attributed later scripts' blends to earlier moves, the
same walk bug M36C hit in the fallback checker. Re-walked properly (stop at
`end`/`return`, follow `call`/`goto`, depth-limited): **83 moves** genuinely
reach a white blend. The 126-of-777 CALL SITE figure is unaffected, since that
counts blend commands directly rather than walking scripts.

**Also fixed while here**: the VM now clears any blend still applied to a
battler when a run ends (`_clear_battler_blends`), the third member of the same
family as the visibility and displacement restores. A ramp that ends on a
non-zero coefficient leaves the tint deliberately — upstream never restores it
either, scripts pair a second call to blend back — so this is the net for a run
that ENDS mid-ramp, which would otherwise leave a Pokemon permanently tinted.
And a duplicate RGB15 converter introduced in E3 (`_gba_rgb_to_color`) is now a
thin alias of the pre-existing `_rgb15_to_color`.

**VERIFICATION, stated precisely.** The mechanism is confirmed by a headless
probe that runs real moves' VMs and samples the shader parameter on real
battler nodes: Mega Punch and Mega Kick both reach a peak tint of 0.44, so the
blend genuinely fires and applies. The suite additionally asserts that a blend
toward WHITE now yields a visible tint, which is the exact case that was
previously the multiply identity.

**NOT verified: a screenshot of a white flash specifically.** Three capture
attempts failed to time one. The harness takes a fixed number of shots at a
fixed gap and the battle intro alone consumes ~830 frames, so hitting a
particular blend's peak inside a ~100-frame animation is largely luck. What
the captures DO show is the animation window rendering (the impact background
and a heavy screen darken on Mega Punch, whose blend is toward black rather
than white — which is also why an earlier attempt measured the region
darkening instead of flashing). Flagged as a harness limitation worth fixing
before the next visual check: it needs a "start capturing when the move
actually begins" trigger rather than a fixed gap.

### M36 screenshot harness — trigger-driven capture, FIXED 2026-07-30

13-suite sweep green. Closes the limitation flagged by the blend-ramp fix,
which lost three verification attempts to it.

**The defect.** The harness captured a fixed number of shots at a fixed frame
gap, starting the moment the move was queued. But the battle intro — trainer
sprites, party summary, both send-outs, two messages — drains through
`_pending_beats` for **~830 frames** before a move's animation begins. So a
26x26 window landed entirely on the intro, and a shorter window never reached
the move at all. Every "capture the animation" attempt was effectively a coin
flip on the numbers chosen.

**The fix** is two signals on the battle screen, `anim_script_started` and
`anim_script_finished(move_id, frames)`, emitted around `_run_anim_script`.
The harness waits for the start signal and only then begins shooting.
Measured: it now triggers at frame ~670-677, exactly where the animation
begins, versus never reaching it before.

**These are not test-only scaffolding.** M36-H's whole premise is comparing a
hand-authored animation against the ported one, and any in-editor preview
(the piece that gates every version of the M36-H "expose the knobs" option)
needs to know precisely when an animation runs. `anim_script_finished` also
reports the animation's real length in GBA frames, which makes a capture
window derivable rather than guessed.

**A mistake made and caught inside this fix.** The first cut also connected
`move_executed` as a general fallback — and it triggered at frame 0, capturing
the intro all over again. `move_executed` fires during the battle's
synchronous resolution inside `advance()`, long before the queued animation
beat runs. The fallback is now conditional: it is only connected when the
dispatcher says the engine will NOT play the move, i.e. when the move takes
the legacy hit-effect path and no `anim_script_started` will ever come.

**A second sizing detail worth recording**: the VM steps on a wall-clock timer
(`_ANIM_FRAME_SECONDS`), not once per process frame, so a 105-GBA-frame
animation spans ~1.75s — roughly 250 process frames at 144Hz, not 105. A first
widened attempt at 24 shots x 4 frames still covered only ~40% of the
animation. Shots x gap must be sized against wall-clock, not GBA frames.

Verified by capturing Mega Kick and landing squarely mid-animation on the
impact background at full brightness — a window that was simply unreachable
before this change.

### M36D batch 6 — COMPLETE 2026-07-30

`m36d_batch_test` 205 -> **246/246**; 16-suite sweep green. Coverage
**356 -> 401 of 932 (43.0%)**, iconic Gen 1-3 **70.0% -> 91.4%** (64/70).

**Selection changed again, and this time it was a correction.** Batch 5's
recorded miss was picking an ice/water CLUSTER that did not unblock Ice Beam,
because the targets were inferred from a family name rather than read. So
batch 6 began by querying each blocked iconic move's ACTUAL missing set. That
showed there is almost no sharing left — only `AnimIceEffectParticle` (Ice
Beam + Blizzard) and `AnimDirtPlumeParticle` (Fissure + Dig) block two moves
each; every other blocker blocks exactly one. Batch 6 is therefore a list of
MOVES, not of families, and it landed on its 15 targets exactly.

**Three existing helpers absorbed a third of the batch**, per Step 0:
`_arc_travel` covers ThrowProjectile, SludgeProjectile and DirtPlumeParticle —
which share ONE step function upstream, byte-for-byte; `_linear_travel` covers
IceBeamParticle, WaterGunDroplet, SolarBeamBigOrb and (degenerately, with no
movement at all) DigDirtMound; `_velocity_travel` covers SludgeBombHitParticle,
with a decay term making it a decelerating spray.

**The leak-prone pair, asked about at Step 0 precisely because of this
project's history.** `AnimTask_DigDownMovement` / `AnimTask_DigUpMovement` are
a FOUR-CALL sequence upstream — down(false), down(true), up(false), up(true) —
and omitting any one strands the attacker: shoved past the right edge, parked
below the screen, or simply invisible. Upstream relies entirely on the script
getting all four right. Here every displacement goes through `MonOffset` and
every visibility change through a new tracked setter, so the VM's own
end-of-run restores catch a broken sequence. **The suite proves that net by
running the sequence four times, omitting a different call each time, and
asserting the mon still ends up on-screen and visible.**
`AnimTask_SetAllNonAttackersInvisiblity` is the same shape — a raw setter with
no restore, relying on a paired call the script may never make — and is
covered the same way.

**Two script-terminated behaviors** (`AnimOrbitFast`, and `AuroraBeamRings`
which reads arg 7 live) are registered UNCOUNTED, since a counted stepper on
an effect that orbits until the script stops it would hang
`waitforvisualfinish` forever.

**Faithful oddities reproduced rather than tidied**: `AnimWaterGunDroplet`
uses arg 4 as BOTH duration and y-delta while arg 3 goes unused;
`AnimTask_CreateSmallSolarBeamOrbs` clobbers args 0-3 permanently on every
spawn; `AnimDrillPeckHitSplats` uses a NEGATIVE radius, inverting its points;
and `AnimBowMon` is an invisible CONTROLLER sprite that moves the attacker's
own body, deliberately leaving its tilt applied for a later paired call.

**An accounting correction to my own earlier note.** I had said Hail sits in
the iconic tier's 70-move denominator as permanently unblockable. It does not:
the table has 71 entries, and the tier is built only from moves with a bound
script, so Hail (which has none) is excluded and 64/70 is self-consistent. The
underlying finding still stands — Hail and Snowscape have no animation script
and are handled by M26B4's weather path — as does its converse: Rain Dance,
Sunny Day and Sandstorm DO have scripts and count toward coverage while being
intercepted before the engine ever runs them.

Verified by real capture with the now-reliable harness: Ice Beam renders a
crystal stream from attacker to target with the target tinted icy, and the
harness triggered at frame 672, exactly on the animation.

**Remaining blocked iconic (6):** Thunder (3), Confuse Ray (3), Frustration
(3), Volt Tackle (3), Dragon Dance (3), Extreme Speed (6) — the last being by
some way the most expensive single move left in the tier.

### Essentials pack move animations — reviewed 2026-07-30, recorded as a FALLBACK

Reviewed at Rob's request. Findings only; nothing built, nothing adopted.
Every figure below is measured from the vendored pack
(`assets/Essentials_v19.1`), not estimated.

**Structure.** Three Ruby-Marshal classes in `Data/PkmnAnimations.rxdata`
(~1 MB):

* `PBAnimations` — the container, an `@array` of **311** animations.
* `PBAnimation` — **subclasses Array**, so each animation IS its list of
  frames, with `@name`, `@graphic` (which sheet), `@position`, `@scope`
  (single/both targets), `@hue` and `@timing` hung off it as ivars.
* `PBAnimTiming` — a timed event: `@frame`, `@timingType`, `@name` (the SE
  file), `@volume`, `@pitch`, `@flashScope`/`@flashColor`/`@flashDuration`,
  `@colorRed/Green/Blue/Alpha`, `@opacity`, `@bgX`/`@bgY`, `@duration`.

So the model is a **fixed keyframe cel timeline** — each frame lists cells
(sheet region, position, zoom, angle, opacity) — plus a **separate timing
track** for sound, flashes and background events keyed to frame numbers.
Authored in RMXP's visual animation editor, with `animmaker.exe` (documented
in `animmaker.txt`, XML-driven) for importing sprite sheets.

`Data/move2anim.dat` is the move mapping: **212 of 674 moves** have a bespoke
animation (31%), plus 18 in a second array.

**Assets**: 97 animation sheets (`Graphics/Animations`), 6 full-screen
overlays plus 52 ball sprites (`Graphics/Battle animations`), and **137
animation SFX as real ogg/mp3/wav** (`Audio/SE/Anim`) — some named per-move
(`Comet Punch.mp3`, `Flail.mp3`), most by effect family (`Fire1-6`,
`Explosion1-7`, `Blow1-7`, `Earth1-5`).

**Against what M36 ports:**

| | pokeemerald (M36) | Essentials |
|---|---|---|
| Model | 54-opcode bytecode VM, procedural per-frame callbacks | keyframe timeline + timing track |
| Volume | 32,318 commands, 941 scripts, 587 behaviors | 311 animations |
| Move coverage | **401/932 playable (43%)** | **212/674 shipped (31%)** |
| Positioning | computed live from battler coords, per-side mirroring | cells in animation space, anchored by `@position`/`@scope` |
| Sound | SE id + 3-value pan, MIDI-only | real ogg/mp3/wav with volume + pitch |
| Editing | code | visual editor |

**RECORDED AS A FALLBACK, NOT A DIRECTION.** Adopting it wholesale would be a
COVERAGE DOWNGRADE — M36 already plays 401 moves to Essentials' 212 — at lower
fidelity to the reference this project set as ground truth, and in a different
art style from the GBA sprites used everywhere else. That is the reason it is
filed here rather than acted on.

Where it IS a real fallback:

1. **M36-S's open asset question.** That sub-tier's blocker was recorded as
   "the reference's SFX are MIDI-only, so there is nothing to flat-copy, and
   sourcing is a decision for Rob." The 137 real playable files are a concrete
   answer to exactly that, and they arrive already organised by effect family,
   which is the shape a per-move SE mapping wants.
2. **M36-H's escape hatch, for the expensive tail.** Essentials' model —
   keyframe timeline plus timing track — is structurally what Godot's
   `AnimationPlayer` does natively, so it is much closer to a hand-authored
   Godot animation than the bytecode VM is. Where a move costs a lot to port
   (Extreme Speed needs 6 behaviors), an Essentials animation is a ready
   reference or raw material rather than a from-scratch authoring job.

Neither use requires adopting the pack's animation system; both are asset
sourcing plus, at most, reading its timing data as a reference.

## M36 — sections relocated from CLAUDE.md's roadmap row (2026-07-30)

CLAUDE.md's M36 row had grown to **51,224 characters on one table line** —
4.6% of a file already flagged as near its size cap. Rob approved a
restructure: the row becomes an index, and this document (already the declared
scope of record) carries the detail.

Most sub-tiers already had proper sections here. These four did NOT, so their
text is relocated **verbatim** below rather than summarised — nothing is lost,
and the wording is the original.

### M36D batches 1-3 (relocated verbatim)

**M36D — Batched expansion — FIRST PASS DONE 2026-07-29, sub-tier ONGOING** (`m36d_batch_test` 66/66, 13-suite regression green. New sequencing tool `scenes/battle/m36_coverage_report.tscn` — tiers the roster (Gen 1-3 verified from source as ids 1-354) and runs a GREEDY 'what to port next' pass, because the most-referenced behavior is usually a poor choice while the one that COMPLETES the most moves is the one that moves coverage. Batch 1: 20 behaviors, coverage 23 -> 85 of 932 (2.5% -> 9.1%), iconic 3 -> 12 of 70. **Batch 2: 29 behaviors, 85 -> 138 (14.8%), iconic 12 -> 18. Batch 3: 22 behaviors, 138 -> 200 of 932 (21.5%), iconic 18 -> 31 of 70 (44.3%)** — mon tasks (shake ring-down, wind-up lunge, rotation, teleport, Dynamax growth, blend pulse) and a particle set. The family rule holds across all three batches at ~2-3 moves per behavior, so M36C's linear estimate was right in magnitude but pessimistic. THE BIGGEST REMAINING BLOCKER IS NOW M36E: SetPsychicBackground (8 moves), MetallicShine (5), StartSlidingBg, the platform-shake paths, and HazeScrollingFog — the sprite variants of those shakes ARE ported and the BG variants consume their frames, so only the visual is missing — projectiles, seed/leaf/rock, mon visuals incl. real afterimages, palette ops, the defensive wall, and the sound-task set (registered as structured no-ops that still reproduce their FRAME COST, since upstream cry tasks block a script and collapsing them to zero would quietly speed scripts up). Batch 2 also found a THIRD fallback-walk bug — `createsoundtask` symbols were demanded as behaviors though the VM handles that opcode itself and upstream they report to a separate counter — and a fidelity bug the test doubles were hiding: offsets were scaled by pixel_scale but SPRITES WERE NOT, so beams would have rendered as scattered specks. This REVISES M36C's linear-grind expectation upward: 20 behaviors bought 62 moves because porting a FAMILY retires the shared helpers its neighbours need — pick by family, not by individual rank. **Surf and Metallic Shine are gated on M36E, not on more behaviors**: `AnimTask_CreateSurfWave` is 100% background-layer work with no sprite motion at all, and MetallicShine needs an OBJWIN silhouette mask — deliberately NOT faked, so Surf stays on the fallback until the background layer exists.) (coverage report; order per decision 5: ICONIC GEN 1-3 MOVES FIRST, then remaining Gen 1-3, then the rest of the 717 — supersedes the recon's Kanto-encounter-surface recommendation).

### M36-S — SFX & audio surface (relocated verbatim)

**M36-S — SFX & audio surface** (per amended decision 3: owns the move-anim audio pass AND starts with its own recon of the project's entire missing audio surface, since the project currently ships NO audio at all: battle music, cries, UI SEs, fanfares; move-anim SFX is M36-S's first consumer, not its whole scope). **MEASURED 2026-07-30 while closing M36E — everything M36-S needs from the extraction is ALREADY PRESERVED; it is a wiring-and-assets problem, not a re-extraction one.** Figures below are from the shipped `scripts.json`, not estimates. **(1) The opcode surface is 3,635 invocations across 11 opcodes, and it is dominated by ONE**: `playsewithpan` 3124 (86%), then `loopsewithpan` 258, `waitplaysewithpan` 95, `panse` 61, `stopsound` 34, `createsoundtask` 31, `waitsound` 17, `playse` 6, `panse_adjustnone` 4, `setpan` 4, `panse_adjustall` 1 — so a single opcode's implementation covers the overwhelming majority of sites, and the long tail is genuinely short. **(2) 140 distinct sound-effect ids are referenced, and they survive as resolved INTs — but the extractor also captured 146 `SE_*` constants**, so ids map back to names with no re-extraction needed; that mapping is the first thing a M36-S session should build, exactly as `bg_name_for_id` was for M36E2. **(3) Panning is preserved and is effectively THREE values**: -64 (1546 sites), +63 (1511), 0 (63), plus 3 one-off literals — matching the captured `SOUND_PAN_ATTACKER` / `SOUND_PAN_TARGET` / `SOUND_PAN_MIDDLE` constants, so pan is a per-side stereo decision rather than a continuous parameter. **(4) The `createsoundtask` port surface is THREE functions total** — `SoundTask_LoopSEAdjustPanning` (29 sites), `SoundTask_PlaySeChangingVolume` (1), `SoundTask_FireBlast` (1) — a far smaller tail than the visual-task side. **(5) The VM already has the whole sound-side skeleton**: a `_sound_count` field kept SEPARATE from `_visual_count`, every one of the 11 opcodes routed (as timing-only no-ops), and 9 `SoundTask_*` behaviors registered — the cry ones as WAITING no-ops that still reproduce their frame cost, because upstream a cry blocks the script and collapsing it to zero would quietly speed every affected animation up. **A real M36D finding worth not re-deriving**: `createsoundtask` must NOT be treated as a behavior blocker — the VM handles the opcode itself and upstream those tasks report to `gAnimSoundTaskCount`, not the visual counter; treating it as a blocker wrongly gated 3 moves until M36D batch 2 caught it. **The genuinely open question is ASSETS, not code**: the reference's SFX are MIDI-only, so there is nothing to flat-copy the way sprites and backgrounds were — sourcing (render the MIDI set? use the Essentials pack's own SFX, which ship real files for at least the ball-throw family per [M26B3-6]? something else?) is a decision point for Rob, not a licence to pick one. Cries are a second, separate asset question with 386 species behind it. Sizing still pending that recon. Sizing: A 1-2 / B 2 / C 2-3 sessions, D per-batch, E 1-2; S unsized pending its recon.

### Essentials pack animations — recorded as a fallback (relocated verbatim)

**ESSENTIALS PACK ANIMATIONS — REVIEWED 2026-07-30, RECORDED AS A FALLBACK for M36-S and M36-H (Rob's call). Findings only; nothing adopted.** Measured from the vendored `assets/Essentials_v19.1`, not estimated. Structure: three Ruby-Marshal classes in `Data/PkmnAnimations.rxdata` — `PBAnimations` (container, 311 animations), `PBAnimation` (SUBCLASSES Array, so each animation IS its frame list, with @name/@graphic/@position/@scope/@hue/@timing as ivars), and `PBAnimTiming` (@frame/@timingType/@name/@volume/@pitch/@flash*/@color*/@bgX/@bgY/@duration). So the model is a FIXED KEYFRAME CEL TIMELINE plus a separate timing track for sound/flash/background — authored in RMXP's visual editor with `animmaker.exe` (documented, XML-driven) — as against pokeemerald's 54-opcode bytecode VM with procedural per-frame callbacks. `move2anim.dat` maps **212 of 674 moves (31%)**. Assets: 97 animation sheets, 6 overlays + 52 ball sprites, and **137 animation SFX as real ogg/mp3/wav**, some named per-move, most by effect family (Fire1-6, Explosion1-7, Blow1-7, Earth1-5). **NOT a direction: adopting it wholesale would be a COVERAGE DOWNGRADE** — M36 already plays 401 moves to Essentials' 212 — at lower fidelity to the stated ground truth and in a different art style from the GBA sprites used everywhere else. **Where it IS a real fallback**: (1) it answers M36-S's recorded blocker ("reference SFX are MIDI-only, nothing to flat-copy, sourcing is Rob's decision") with 137 playable files already organised by effect family; and (2) it is raw material or reference for M36-H's escape hatch on expensive moves, since a keyframe timeline is structurally what Godot's AnimationPlayer does natively — far closer to a hand-authored Godot animation than the VM is. Neither use requires adopting its animation system.

### M36-H — hand-authored move animations (relocated verbatim)

**M36-H — HAND-AUTHORED MOVE ANIMATIONS (escape hatch) — RESEARCHED 2026-07-30, Rob's proposal, NOT started.** Rob's idea: rebuild one or two animations by hand in Godot's own animation editor, compare against the ported version, and replace that ONE move if the hand-made one comes out better. **First, the fact that prompted it, because it is not obvious from the code: these animations are NOT Godot animations at all.** Verified by direct grep — there is ZERO use of `AnimationPlayer`, `AnimationTree` or `AnimationNodeStateMachine` anywhere in the anim engine or the battle scenes. Nothing appears in the animation editor and there are no keyframes to scrub; M36 is a bytecode interpreter walking extracted GBA scripts and driving plain Control nodes procedurally at 1/60s steps. **The seam this needs ALREADY EXISTS and already has precedent**: `_on_hit_effect_move_executed` performs per-move overrides checked BEFORE the general path — the M26B4-3 weather branch intercepts weather moves outright, including an id-specific case for Snowscape. A `move_id -> hand-authored scene` branch is the same shape: additive, per-move, low risk. **The timing turned favourable at batch 4**: that batch took nearly all the cheap iconic wins, leaving exactly ONE one-away behavior (AnimPsychoBoost), so every still-blocked iconic move now needs 2+ new behaviors (Swords Dance 2, Water Gun 2, Ice Beam 2, Aurora Beam 2, Hyper Beam 2, Slash 2, Solar Beam 2, Blizzard 3) — the port's cost per iconic move is rising, which is precisely when a hand-authored alternative becomes competitive. **Recommended test subjects, chosen to answer two different questions**: Blizzard (blocked, needs 3, the most expensive remaining iconic — tests 'is hand-authoring CHEAPER than porting?') and Flamethrower (already playable, so a direct A/B — tests 'is hand-authoring BETTER?'). **What makes it viable here specifically**: the battle stage uses FIXED slot anchors, so hand-authored keyframes at fixed coordinates genuinely work in singles — that is the constraint that normally kills this approach and it does not apply. **Three constraints any hand-authored animation must respect**: mirroring for an opponent-side attacker (a flipped variant or a flipped parent); doubles, where 4 combatants sit at different slots (simplest rule — the override applies in SINGLES ONLY and falls through to the VM in doubles); and fire-and-forget with self-cleanup, since the engine never blocks the turn. **TWO FLAGS THAT ARE DECISIONS, NOT DETAILS**: (1) this DIVERGES FROM THE 1x GBA FRAME-ACCURATE FIDELITY BAR that decision 4 set for M36 — it would be a deliberate per-move exception to a stated project standard, and it should be RECORDED as one rather than drifted into; (2) it does not scale to 941 moves, so it is an escape hatch for moves whose port reads badly, never a replacement strategy — and because it creates two sources of truth for 'how does move X look', the override needs an explicit precedence rule. **Supporting measurements from the same session** (taken to size the alternative 'expose the constants in an inspector' option, and recorded so a future session need not re-derive them): the per-move tuning surface is already DATA — 12,258 createsprite/createvisualtask sites carrying ~72,356 arguments in `scripts.json` — whereas the per-behavior surface is 2,279 numeric literals of which only 16 are named constants, across 158 functions containing 601 branches and 80 steppers, with 55 of those functions reading no args at all. So per-MOVE tuning is cheap and per-BEHAVIOR tuning is not, and a large share of an animation's character is phase structure rather than any number. **A live preview is what actually gates every version of this** — a knob or a comparison you cannot see is useless, and today the only preview is the windowed screenshot harness at a minute-plus per look. **Also note `scripts.json` is GENERATED**: any hand-edit to move args would be destroyed by a regen, so that route needs an overlay/provenance layer — M27B already solved exactly this shape for maps (AUTHORED-cell marking plus a refuse-unless-forced re-bake guard) and should be copied rather than redesigned. **Split of work**: Claude builds the override seam, the registry, the singles/doubles fallback and a scene scaffolded against real battle geometry, with tests; Rob authors the actual animation. Sizing: ~1 session for the seam; the authoring is Rob's time.


## M36 — running lists (added 2026-07-30)

Three lookups that previously existed only inside batch prose. Each answers a
question a future session will actually ask, without reading every entry.

### Upstream bugs reproduced DELIBERATELY

Reference bugs ported as written because fixing them would change what the
animation draws away from the reference. **Do not "fix" these** — each is
pinned by test.

| Behavior | The bug | Effect if "fixed" |
|---|---|---|
| `AnimSprayWaterDroplet` (b9) | Step does `data[0] = data[0]` — a self-assignment where the vertical decay reads `data[1] -= 32`. The horizontal speed never decays, and the `if (data[0] < 0)` guard beneath it is unreachable. | The arc would change shape. x is constant, y decelerates. |
| `AnimTask_AttackerPunchWithTrace` (b4) | Subtracts the SPRITE ID from `x2` — an object handle used as a coordinate. | **NOT reproduced** — it is masked by a later `x2 = 0`, so reproducing it would be copying dead arithmetic. Recorded for contrast: not every upstream bug is worth porting. |

### Deferred behaviors — what and why

| Behavior | Deferred by | Reason | Cost |
|---|---|---|---|
| ~~`AnimTask_SpiteTargetShadow`~~ | b10, again in b11 | **CLOSED 2026-07-30 — both deferrals OVERTURNED.** Reading Step1 case 1 through Step2 in full showed the earlier call was wrong: the tint lands on the REAL target, the echo and its 128-frame sine pulse are directly expressible, and only the per-scanline nature of the waver is lost — which batch 7 had already approximated and disclosed for Dragon Dance's identical mechanism. Ported. | — |
| `AnimTask_SecretPower` / terrain family | M19-era | `gBattleEnvironment` has no analogue — no overworld. | — |

Batch 10 also deferred `AnimTask_Rollout`, `AnimTask_FlailMovement`,
`AnimTask_NightmareClone` and `AnimTask_ShrinkTargetCopy` for unread step
functions; **all four were ported in batch 11** once read, which is what
deferring them was for.

### Disclosed divergences — deliberate, do NOT "correct" without asking

| Item | Divergence | Why |
|---|---|---|
| `AnimTask_AnimateGustTornadoPalette` (b8) | **Structured no-op.** Frame cost exact, no visual. | Rotates 8 OBJ palette entries; sprite sheets are composited PNGs with no recoverable palette index. A hue shift would invent motion the reference does not describe. |
| `AnimGrowingShockWaveOrb` (b8) | Affine starts at `0x10` = **16x** magnification, ported as-is. | Source-exact, but 4x on 1024px is not 1x on 240px. **Open look-call** — see the look-calls list. |
| `AnimTask_Rollout` (b11) | Per-interval dirt sprites not spawned. | The attacker's own motion is what the frames are spent on and what every one of these moves shares. |
| `AnimSparkElectricity` (b8) | arg 5 coord variant and arg 6 BG-priority bump are no-ops. | Both resolve to this stage's sprite centre / have no per-sprite equivalent. |
| `AnimHyperVoiceRing` (b9) | Subpriority ordering not modelled. | No per-sprite draw-order equivalent. |
| `AnimMudSportDirt` (b12) | Falling branch ported from its SETUP only; its step function was not read. | The setup fully determines start and end. The rising branch — the one scripts spawn in bulk — is fully ported. |
| `AnimTask_SpiteTargetShadow` (b11) | Per-scanline BG waver ported as a horizontal wobble of the whole clone, on the source-exact envelope. | Second use of the approximation batch 7 disclosed for `AnimTask_DragonDanceWaver` — the same per-scanline heat-haze mechanism. Consistent rather than novel. |
| `AnimTask_SurfWaveScanlineEffect` (E3) | Unported — the wave is a clean sweep, not rippled. | Per-scanline HBlank offset with no hook to port to. |
| MetallicShine OBJWIN stencil (E3) | Approximated with a duplicate of the battler's texture. | No stencil equivalent. |

### M36D batch ordering — Decision 5's phase order AMENDED by Rob, 2026-07-30

Decision 5 (§7) set Phase D's order as **iconic Gen 1-3 -> remaining Gen 1-3 ->
the rest of the 717**. The iconic tier closed at 70/70 in batch 7. Batch 8 then
measured what the remaining two tiers actually cost, and the ordering turned out
to be leaving throughput on the table:

| Tier | Playable after batch 8 | Top-8 greedy picks yield |
|---|---|---|
| Tier 2 — remaining Gen 1-3 | 126/283 (44.5%) | **+12 moves** |
| Tier 3 — Gen 4+ | 250/579 (43.2%) | **+33 moves** |

Tier 2's one-away wins are worth 3/2/2/1/1/1; Tier 3's are 5/5/4/4/4/4 —
**~2.75x the return per behavior.** The two tiers also sit at essentially the
same completion percentage, so there is no partially-finished-tier argument for
holding the order either.

**Rob's call: take Tier 3's high-yield picks next.** The remaining ordering is
now **by measured yield, not by generation**. Decision 5's tier definitions
still stand (the coverage report still reports all three), and the iconic-first
phase it mandated was carried out in full — only the ordering of the two
REMAINING phases is superseded, and only because the iconic phase completing is
what made the comparison possible.

### M36 — open look-calls and capability gaps (running list)

Kept here so they are findable without reading every batch entry.

**Look-calls for Rob — appearance judgement, not correctness gaps.** All three
are the same shape: a source-exact scale or amplitude that reads differently at
this project's 4x on a 1024px canvas than at source's 1x on 240px.

| Item | State | Levers |
|---|---|---|
| M36E3 Sun ray | Mechanically source-accurate; reads as a pale diamond rather than a beam. `sunlight.png` genuinely is a solid 32x32 diamond. | `_SUN_RAY_ALPHA`, `_SUN_RAY_AFFINE_START` |
| M36D b8 `AnimGrowingShockWaveOrb` | **SCREENSHOT-CHECKED 2026-07-30 — less alarming than feared.** In context the 16x reads as a ~280px charge aura around the user, not a screen-filler. Recommend leaving source-exact. | `_SHOCKWAVE_ORB_PARAM_START`, `_SHOCKWAVE_ORB_PARAM_STEP` |
| M36D b11 `AnimTask_Rollout` | **NEW 2026-07-30.** Pull-back clips the attacker off the left edge. Proportionally source-accurate (~18% vs ~13% of screen width) but our attacker sits far closer to the edge. Same class as the reverted fly-out excursion. | clamp the pull-back distance |
| M36B3-6b fly-out excursion | Already REVERTED for this exact reason; constants kept unused so the numbers are not re-derived. Listed so the pattern reads as a pattern. | — |

**Capability gap — a different kind of item.**
`AnimTask_AnimateGustTornadoPalette` (M36D batch 8) ships as a structured
no-op. M36E3's palette remapping is BACKGROUND-only, driven by the
per-background `palette_colors` the extractor emits; the pulled sprite sheets
are composited PNGs from which a pixel's source palette index is not
recoverable. **Closing it needs sprite-palette data the extraction does not
currently produce** — not a tuning change. Faking it with a hue shift would
invent motion the reference does not describe. Frame cost is exact and pinned
by test, so script pacing is unaffected.

### M36 — screenshot verification pass, 2026-07-30

The first visual check across batches 8-13 (~70 behaviors, all previously
marked "NOT screenshot-verified"). Eight moves captured windowed through
`m36_screenshot_harness.tscn`, chosen to exercise the riskiest work rather
than the prettiest.

**A HARNESS BUG WAS BLOCKING MOST OF THIS, and it had been noted in passing
and never chased.** Batch 7 recorded that "the harness has never shown the
player's Pokemon — a pre-existing intro artifact, unrelated." It was not
unrelated. `_ready()` clears both sides' sprites and relies on each side's own
send-out to reveal them (M26B3-5); the opponent's completes, the player's does
not — its trainer is still mid-sequence in every captured frame.

Consequence: **every attacker-side behavior was unverifiable by screenshot** —
Defense Curl's squash, Rollout's wind-up, Flail's decay, the whole mon-deform
family, which is a large share of what batches 8-13 built. Two batches' worth
of "not screenshot-verified" was partly *could not be*.

Fixed in the HARNESS (an instrument fault, not a licence to change production
behaviour from a test rig): it now forces the player's side visible before
triggering. **The underlying send-out stall is real and is flagged separately**
— normal play reveals the mon correctly per M26B3-5's own verification, so it
is harness-specific, not a shipped bug.

**What the pass confirmed working:**

| Move | Verified |
|---|---|
| Fly (19) | **The batch 8 + batch 9 pair works end to end** — attacker hidden, ball rises, and `AnimFlyBallAttack` brings it back. The reveal is the real script step, exactly as the headless test claimed. |
| Charge Beam (451) | `ElectricChargingParticles` converge correctly and `AnimGrowingShockWaveOrb` renders. **The 16x orb reads as a charge aura around the user, not the absurd screen-filler feared** — see the look-call note below. |
| Rollout (205) | The wind-up pull-back is clearly visible and in the right direction. |
| Spite (180) | Background swap plus a visibly drained, darkened target — the violet tint on the REAL target, as the batch-11 reversal claimed. |
| Defense Curl (111) | Attacker now visible; the squash is subtle at 4x. |

**Look-calls updated:**

- ⚠️ **`AnimGrowingShockWaveOrb`'s 16x is LESS alarming than feared.** Seen in
  context it is a charge aura enveloping the user, roughly 280px across, not a
  screen-filler. Recommend leaving it source-exact. Still Rob's call.
- ⚠️ **NEW: Rollout's pull-back clips the attacker off the left edge.**
  Proportionally it matches source (~18% of screen width against source's
  ~13%), but this project's attacker sits far closer to the screen edge than
  source's does, so the same proportion runs out of room. Same class as the
  fly-out excursion reverted in M26B3-6a. Cheap lever: clamp the pull-back
  distance.

**Also observed, pre-existing and NOT M36:** the attacker's back sprite is
clipped by the message box (already flagged for M26G), and the player's trainer
lingers on screen for the whole capture (the send-out stall above).

### M36D batch 13 — COMPLETE 2026-07-30. Deferrals cleared, and a real test-quality bug found.

`m36d_batch_test` 455 -> **489/489**; 8-suite sweep green. Coverage
**571 -> 580 of 932 (62.2%)** — a deliberately small batch, four of batch 12's
five deferrals.

⚠️ **THE HEADLINE IS NOT THE COVERAGE. Eight template names in the suite were
WRONG, and 26 assertions across batches 8-13 had never been running.**

Every spawning test guards on `if node != null:`. A template name that fails to
resolve produces a null sprite, so the guard skips its assertions **silently
while the suite still reports green**. This is the second time this exact
false-pass shape has appeared (batch 11's `_anim_clone` meta key was the first)
and this time it was eight names, not one.

Found by checking a failing assertion's premise rather than patching it: batch
13's geyser test failed to spawn, and the template it named turned out not to
exist — which immediately raised the question of how batch 12's mud test, using
the SAME bad name, had passed. It had not; it had skipped.

The names were then resolved **authoritatively, by callback** — matching each
behavior's `callback` field in `templates.json` rather than guessing from the
name, which is what produced the wrong names in the first place. Fixing all
eight took the suite from 462 to 488 assertions.

**A self-maintaining guard now closes the class.** `_test_every_template_name_resolves`
reads the suite's own source, extracts every `"g...Template"` string, and
requires each to resolve in `AnimData`. It is not a hand-kept list, so a future
batch naming a bad template fails here without anyone remembering to extend
anything. **Proven non-vacuous**: injecting `gDefinitelyNotARealTemplate` makes
it fail and name the offender; restoring returns 489/489.

**The alias pattern held for a FOURTH consecutive batch**, both hits against
work from the two batches immediately prior:

- **`SpriteCB_Geyser` hands straight over to `AnimMudSportDirtRising`** — batch
  12's own rising path, ported one batch earlier. The rising body was extracted
  so both share it.
- **`AnimSuperpowerFireball` IS batch 9's `SpriteCB_GrowingSuperpower`** — the
  same flat 16-frame translation between the same endpoints, differing only in
  whether the side-mirror is an affine anim or an OAM flip. **Registered
  directly against the same function rather than wrapped**, so the suite's
  identity assertion is meaningful; a wrapper would have passed a "both exist"
  check while failing a real one, which is exactly what happened on the first
  run.

**Shapes pinned:** `AnimFlyingParticle` crosses the WHOLE SCREEN and dies at
the far edge — it has no duration argument at all, and its vertical phase is
RECOMPUTED as `(step * elapsed) & 0xFF` from the frame counter rather than
accumulated, so a large step aliases into a flutter. `AnimTrickBag` spawns at
SCREEN CENTRE rather than on any battler, falls with real acceleration
(`y += speed/10` while `speed += 3`), then orbits an 11-row table whose rows
supply an angle step, a frame count and a direction — on a WIDE FLAT ellipse
(x radius 60, y radius 20; the axes are the reverse of the usual convention).

⚠️ **`AnimFallingFeather` remains deferred and is now the ONLY item left on the
list.** Its step function is **247 lines** of state machine over a packed
`FeatherDanceData` bitfield struct aliased onto the sprite's data array — a
genuinely different order of complexity from anything else in this tier. It
wants its own pass, not a slot between two other behaviors.

**NOT screenshot-verified.**

### M36D batch 12 — COMPLETE 2026-07-30

`m36d_batch_test` 431 -> **455/455** (first run); 9-suite sweep green.
Coverage **553 -> 571 of 932 (61.3%)** — +18 from 9 behaviors (2.0 each), the
flattened curve holding steady.

**9 of 14 candidates. FIVE DEFERRED** for unread step functions, per the rule
batch 10 established and batch 11 vindicated: `AnimFallingFeather` (drives a
packed `FeatherDanceData` bitfield struct), `AnimFlyingParticle`,
`SpriteCB_Geyser`, `AnimTrickBag`, `AnimSuperpowerFireball`. Guarded by test,
same as batch 10's were.

**Two more near-aliases of already-ported work — the third batch running to
turn one up.** This is now a pattern worth expecting at Step 0 rather than
discovering mid-implementation.

- **`AnimLargeFlame` IS batch 9's `AnimFirePlume` with exactly ONE SIGN
  INVERTED** — the x drift. Same step function, same both counters, same every
  argument. So they sweep OPPOSITE ways from the same spawn. This is the
  sharpest collapse risk yet seen here: registering them as one behavior would
  look correct in a still frame and be wrong in motion. Ported through one
  shared body with that sign as the only parameter (`_fire_plume_common`), and
  **the suite demands they genuinely diverge** — both drift, in opposite
  directions, and are not the same registered implementation.
- **`AnimGuardRing` IS batch 10's `SpriteCB_SurroundingRing`** plus a
  doubles-centre branch: identical `data[0]=13`, +40 spawn, -72 rise. Ported as
  the general case with the plain variant delegating.

**Shapes pinned by test:**

- **`AnimMudSportDirt` rises EVERY frame but drifts sideways only every
  OTHER** — the uneven rate is deliberate and a smooth diagonal reads wrong.
  It also dies by clearing the screen top rather than on a counter, so its
  lifetime depends on where it spawned.
- **`AnimTask_BlendNonAttackerPalettes` SHIFTS ITS ARGS RIGHT BY ONE** before
  delegating (`args[5..1] = args[4..0]`), because the shared blend entry point
  expects a selector in slot 0 that this task supplies itself. Reading them
  unshifted applies the wrong delay, coefficients AND colour — a silent
  mis-blend, not a crash.
- **`AnimBlockX`'s drop height is side-dependent** — 144px onto a player-side
  target against 96px onto an opponent-side one.
- **`AnimPoisonJabProjectile` rotates to FACE its target** (`ArcTan2Neg`), so
  the jab points along its own flight path; without it the sprite arrives
  sideways.
- **`AnimParticleBurst` wanders on a sine rather than arcing**, and fades out
  entirely with VISIBILITY — no alpha involved — flickering past phase 100 and
  dying at 120.
- `AnimTask_IsPowerOver99` is a one-frame query; the boundary is asserted on
  both sides, since an off-by-one silently picks the wrong script branch.

**DISCLOSED:** `AnimMudSportDirt`'s FALLING branch step function was not read.
Its setup fully determines start and end (`y = arg2`, `y2 = -arg2` — it begins
at the screen top and settles to its resting y) and that is what is ported; the
RISING branch is the one Mud Sport scripts actually spawn in bulk.

**NOT screenshot-verified.**

### M36D batch 11 — COMPLETE 2026-07-30. Batch 10's deferrals, and a fourth restore net.

`m36d_batch_test` 396 -> **421/421**; 16-suite sweep green. Coverage
**543 -> 551 of 932 (59.1%)** — +8 from 4 behaviors, the ~2.0/behavior the
flattened curve now predicts.

**Four of batch 10's five deferrals, ported once their step functions were
actually read.** That was the whole point of deferring them, and it paid off
immediately:

⚠️ **A NEW LEAK CLASS, and the fourth of its kind.**
`AnimTask_ShrinkTargetCopy` does not copy anything — it shrinks the **REAL
target** and then HOLDS until the script writes `-1` into arg 7 before putting
it back. That is the same wait-for-signal shape as batch 7's Extreme Speed
visibility pair, but on **SCALE**, which none of the VM's three existing restore
nets covered. A script ending before its paired signal would have left a Pokemon
permanently shrunk for the rest of the battle.

Closed systemically rather than per-behavior: new `_restore_scaled_battlers()`
on the VM (fourth member of the family, after visibility, displacement and
blend) plus a `MonScale` helper built to the same meta-driven contract as
`MonOffset`, so the two read alike and neither can disagree with whatever
actually changed the sprite. **The suite asserts the net directly** — shrink the
target, end the run with no signal, require the scale back — and separately
asserts the signalled path still restores through the behavior itself, so the
net cannot be masking a behavior that never restores at all.

**`AnimTask_FlailMovement` DECAYS**, which is what makes it flail rather than
wobble: the rotation amplitude starts at `0x800` and loses `0x40` every 9 frames
(floored at 16, 32 times) while the swing rate stays constant at `0x200`/frame,
so the oscillation visibly quickens as it tightens. The horizontal sway is not
independent — it is derived from the current tilt (`x2 = -(rot >> 6)`), so the
mon leans into its own rotation rather than sliding separately.

**`AnimTask_Rollout`'s wind-up is most of the move.** The attacker pulls BACK
away from the target for 10 frames, HOLDS for 20 dead frames, returns over 10,
and only then charges — at a speed keyed off the rollout counter this project
already tracks from M16b (`48 - counter*8`, first turn special-cased to 32), so
a later-turn Rollout visibly slams in faster. A port that only charges arrives
with no anticipation at all. Disclosed: the per-interval dirt sprites are not
spawned; the attacker's own motion is what the frames are spent on.

**`AnimTask_NightmareClone`** runs two things at once and neither is the obvious
one: the blended ghost creeps away on a raw 8.8 velocity of barely half a pixel
a frame, while the GBA blend coefficients CROSS-FADE (15 -> 0 and 2 -> 16), each
stepping only on its own phase of a 4-frame cycle. It ends when both have
arrived AND 80 frames have passed, so the drift always completes.

⚠️ **`AnimTask_SpiteTargetShadow` is DEFERRED AGAIN — with a better reason than
last time.** Batch 10 deferred it for an unread step function; that has now been
read, and the answer is that its Step1 allocates a fresh sprite palette, copies
the mon's live palette into a clone, blends that toward `RGB(13,0,15)`, **clears
a hardware BG layer** chosen by the target's BG priority rank, and drives a
per-scanline effect from the target sprite's y. The scanline and BG-layer halves
are the same class of gap as batch 8's gust palette: they need per-sprite
palette indices and hardware layer control that composited PNGs and a single
background layer cannot express. Porting only the purple clone would ship the
least characteristic third of the effect while claiming the behavior. Left
unregistered so its moves keep falling back rather than playing something wrong.

**A false pass caught by checking rather than trusting the green.** The
NightmareClone test looked for a `_anim_clone` meta; the real key is
`_anim_trace`, so `ghost` was null and two assertions were **silently skipped**
while the suite reported 418/418. Fixed, plus a guard assertion that the clone
is findable at all — 418 -> 421, the delta being the guard and the two that had
never been running.

**REVERSAL, same day.** The `AnimTask_SpiteTargetShadow` deferral recorded
above was **overturned** once its remaining steps were read in full. The
paragraph above is left as written — this project does not rewrite a historical
entry — but its conclusion is superseded: the characteristic parts (a violet
tint on the REAL target, an un-tinted echo behind it, a 128-frame sine pulse
between them) are all directly expressible, and the one piece that is not (the
per-scanline waver) already had a disclosed precedent in batch 7's Dragon Dance
port of the identical mechanism. Ported; coverage 551 -> 553. **All five of
batch 10's deferrals are now closed.**

**NOT screenshot-verified.**

### M36D batch 10 — COMPLETE 2026-07-30. The curve flattened, as predicted.

`m36d_batch_test` 373 -> **396/396** (first run, no failures); 16-suite sweep
green. Coverage **516 -> 543 of 932 (58.3%)**.

**Batch 9's closing measurement called this correctly.** The 6s, 5s and 4s are
gone: the best remaining pick is worth **+3**, and the greedy walk over 16
candidates returned only 37 moves (2.3 each) against batch 9's 4.4. 200 moves
still sit one behavior away, but each of those behaviors now serves ~2 moves
rather than ~5.

**11 of the 16 candidates shipped. FIVE WERE DEFERRED RATHER THAN GUESSED AT** —
`AnimTask_Rollout`, `AnimTask_FlailMovement`, `AnimTask_SpiteTargetShadow`,
`AnimTask_NightmareClone` and `AnimTask_ShrinkTargetCopy` each needed a step
function this pass did not read in full. Worth ~10 moves between them. A
half-read port is how a behavior ships looking right and being wrong, and the
suite **asserts all five remain unregistered** so a later session cannot quietly
take the shortcut.

**A second byte-identical alias, one batch after the first.**
`AnimFireSpiralInward` (`battle_anim_fire.c:511`) and batch 9's
`AnimIcePunchSwirlingParticle` are the same `TranslateSpriteInGrowingCircle`
driver with the **same four constants** — duration `0x3C`=60, amplitude 9,
angle step `0x1E`=30, amplitude delta `0xFE00`=-512. Registered against one
implementation, asserted as sharing it.

**Beats a half-read port drops, each pinned by test:**

- **`AnimTask_Flash` HOLDS.** It slams every battler palette to black and the
  background to white, waits 7 frames, and only then blends both back over 16
  steps at 2 frames each (~39 total). The hold is the part that gets lost.
- **`AnimSpikes` has a DEAD 30-frame wait.** Arc (amplitude -50, so it lobs up
  and over rather than travelling straight), then the spikes sit perfectly
  still, and only then flicker out over 16 frames — **on odd frames only**,
  unlike Black Smoke's every-frame flicker. Dropping the wait makes the hazard
  vanish on landing.
- **`AnimGuillotinePincer`'s middle phase is the move.** Converge over 6 frames,
  then **grind for 51 frames**, jittering ±2px on both axes every single frame,
  then retreat. Porting only the converge gives a pincer that arrives and
  politely stops.
- **`SpriteCB_FallingObject` is two phases** — a constant-speed fall, then the
  flicker-out on landing. Merging them loses the landing beat.
- **`AnimOutrageFlame` starts INVISIBLE** (`sprite->invisible = TRUE` at setup)
  and blinks into existence when the flicker first toggles it on.
- **`AnimBlackSmoke` flickers EVERY frame** — that is what makes it read as
  smoke rather than a sliding sprite.

**Two shapes whose names mislead:** `SpriteCB_SurroundingRing` does not expand
around the attacker — it starts 40px BELOW and sweeps 72px UP through it over 13
frames. And `AnimReversalOrb`'s ellipse **widens four times as fast as it
heightens** (0x400 vs 0x100 per frame), growing then unwinding symmetrically
back to nothing.

`AnimQuestionMark` is placed from the attacker's own SPRITE SIZE (half-width to
the side, half-height up, mirrored and clamped to the screen top) rather than a
fixed offset, so a larger Pokemon pushes it further out.

**NOT screenshot-verified.**

### M36D batch 9 — COMPLETE 2026-07-30. First yield-ordered batch.

`m36d_batch_test` 328 -> **373/373**; 16-suite sweep green. Coverage
**446 -> 516 of 932 (55.4%)** — exactly the +70 the greedy walk predicted.
**Both remaining tiers crossed 50%** (Tier 2 44.5 -> 50.9%, Tier 3
43.2 -> 52.2%).

16 behaviors, **4.4 moves each — double batch 8**, which is the ordering
amendment paying for itself immediately.

**Step 0 collapsed a good deal of the batch before any code was written:**

- `AnimRockBlastRock` is `TranslateAnimSpriteToTargetMonLocation` plus a
  side-mirrored flip — M36C's `_translate_to_target` already IS that, so it
  registered as a thin wrapper with a test asserting the shared implementation.
- **`AnimEllipticalGust` and `AnimEllipticalGustCentered` share ONE step
  function** and differ only in placement (the centred variant averages both
  targets in doubles; in singles that average is a no-op). One implementation,
  two entry points.
- `AnimGustToTarget`, `SpriteCB_GrowingSuperpower` and `AnimFlyBallAttack` are
  plain linear translations -> `_linear_travel`.
- `AnimDragonRageFirePlume` is position-then-play-out -> `_play_until_anim_ends`.

**THE BATCH CLOSES BATCH 8's FLY PAIR.** `AnimFlyBallAttack`'s teardown does
`gSprites[attacker].invisible = sprite->data[5]` — the attacker's visibility is
restored FROM ARG 1 as the ball leaves the screen. Batch 8 shipped the hiding
half relying on the VM's restore net; this is the real script step. The suite
asserts the reveal happens **with the VM still running**, so a pass cannot be
the net doing the work, plus the `arg 1 = 1` discriminator proving the reveal
reads its argument rather than being unconditional.

**Distinctive shapes a port gets wrong while looking plausible:**

- **`AnimHornHit` SNAPS BACK.** On the second-to-last frame it teleports to its
  recorded origin (`if (--data[1] == 1) { x = data[6]; y = data[7]; }`) and only
  then dies. A port that merely interpolates toward the destination looks close
  and never actually lands.
- **`AnimFirePlume` has TWO independent counters** — it drifts for `arg3` frames
  but LIVES for `arg2`, so it coasts to a halt and hangs before dying.
  Collapsing them into one duration loses the hang.
- **`AnimZapCannonSpark` stutters** — visibility toggles whenever its angle
  index divides by 3. A smooth port reads as a different move entirely.
- **`AnimIcePunchSwirlingParticle`'s amplitude accumulates NEGATIVE on a
  positive base**, so the radius passes through zero and back out: it spirals
  in, through the centre, and out the far side rather than simply expanding.
- **The gust orbit is an ELLIPSE** — 32 across, 8 down, 5 units/frame for 71
  frames (~1.4 turns). A circular port reads as a bubble, not a tornado.

⚠️ **UPSTREAM BUG reproduced as written — `AnimSprayWaterDroplet`.** Its step
does `sprite->data[0] = sprite->data[0];`, a self-assignment that clearly meant
to decay the horizontal speed the way `data[1] -= 32` decays the vertical. It
does nothing, so **x speed never falls off while the rise does**, and the guard
below it (`if (data[0] < 0) data[0] = 0;`) is unreachable. Ported faithfully and
**pinned by test**, so a future session does not "fix" the arc into a shape the
reference never draws.

`AnimTask_DefenseCurlDeformMon`'s two affine halves cancel EXACTLY — self-
restoring by construction rather than by a corrective final step, and asserted
as returning to precisely its starting scale. Under the inverted GBA rule its
NEGATIVE x delta widens the sprite while the positive y delta flattens it, so
the mon squashes down and out.

**Headliners unblocked** (named in the suite so a regression is legible): Fly,
Metronome, Ice Punch, Dragon Rage, Gust, Horn Attack, Hyper Voice, Rock Blast,
Defense Curl.

**NOT screenshot-verified.**

### M36D batch 8 — COMPLETE 2026-07-30. First batch of the post-iconic grind.

`m36d_batch_test` 279 -> **328/328**; 16-suite sweep green. Coverage
**419 -> 446 of 932 (47.9%)**.

**The selection rule changed, because it had to.** With the iconic tier closed,
batches can no longer be picked by naming moves. Rather than extrapolate batch
7's yield, the remaining work was MEASURED first:

| Blocked moves needing… | Count |
|---|---|
| 1 more behavior | **208** |
| 2 | 174 |
| 3–4 | 95 |
| 5–9 | 35 |

**513 blocked moves across 367 distinct behaviors.** The top 12 blockers appear
in 231 move-slots, and those 12 are this batch.

**Yield was 2.25 moves per behavior — up from batch 7's 0.86, but far below what
231 move-slots implies.** Unblocking a shared behavior only COMPLETES a move if
it was that move's LAST missing one; the rest of those 231 are moves that went
from needing 3 blockers to needing 2. **The greedy ranking measures reach, not
yield** — worth stating plainly so a future session reads the tool correctly.

**The visibility trio is the cheapest work in the batch and the most dangerous.**
`AllBattlersVisible` / `AllBattlersInvisible` /
`AllBattlersInvisibleExceptAttackerAndTarget` (72 move-slots between them) are
one-frame raw setters that RESTORE NOTHING upstream — the fifth appearance of
the leak class this project has hit with Dig, `SetAllNonAttackersInvisiblity`,
Extreme Speed and Volt Tackle. All three route through the VM's tracked setter,
and **the headline assertion runs each one then ends the VM WITHOUT the paired
call and requires every battler back.** Same net applied to `AnimFlyBallUp`,
which hides the attacker and depends entirely on a later script step.

`...ExceptAttackerAndTarget` compares **sprite ids** upstream, not battler ids,
so any slot resolving to the same sprite as the attacker or target is skipped
rather than hidden. Ported as a node comparison, which keeps both singles (no
partner sprites at all) and an ally-target correct.

**Two upstream asymmetries reproduced rather than smoothed:**

- `ShakeTargetBasedOnMovePowerOrDmg` splits its magnitude UNEVENLY —
  `+ceil(mag/2)` one way, `-floor(mag/2)` the other, so an odd magnitude leans —
  and writes its two axes differently: **x** offsets from the sprite's captured
  displacement, **y** is assigned ABSOLUTELY, discarding whatever vertical
  offset was already in place. Both are asserted.
- `ShakeBattlePlatforms` flips x between `+offset` and `-offset` but alternates
  y between `-offset` and **zero**, never going positive. It also restores the
  scroll offset it CAPTURED rather than zero, per M36E3's rule; the test double
  seeds a non-zero scroll specifically so those two outcomes are distinguishable.

**A finding that inverts the obvious reading of `RockMonBackAndForth`:
intensity does NOT widen the motion.** The phase shortens (`8 - 2i` frames)
exactly as fast as the step widens (`i + 2` px), so peak travel lands at
**16 / 18 / 16 px** across the three tiers — not even monotonic. Total rotation
per phase behaves the same way (**2048 / 2304 / 2048**). What intensity actually
controls is SPEED (a cycle is `4 * (8 - 2i)` frames). A first-draft test
asserted "intensity 2 rocks further", failed at 68.3 vs 68.3, and the arithmetic
is now recorded at both the code site and the assertion so it cannot be
re-guessed. The three motion phases (out / back-twice / out) also cancel
EXACTLY, so the test requires the mon to land back on its mark with rotation
restored — no corrective step covering for a drifting port.

**Three more shapes a naive port gets wrong while looking right:**

- **`AnimFlyBallUp` is quadratic, not linear.** The 8.8 velocity accumulator
  needs 7 frames at accel 40 just to reach one whole pixel, so a linear port
  passes "does it rise" and is still wrong. Asserted as later steps covering
  more ground than earlier ones.
- **`SparkElectricity` takes x from SINE and y from COSINE of the same index**,
  so index 0 sits directly BELOW the centre. Swapping them puts it to the right
  and looks entirely plausible.
- **`ElectricChargingParticles` SPEEDS UP as it runs** (`40 - tier*5` frames,
  tier rising every `arg3` spawns, capped at 6) and ends only once the last
  particle LANDS, not when the last one spawns — which is what makes it safe to
  wait on. New shared `_spawn_template_sprite` for tasks that spawn their own
  particles, since a visual task's ctx carries no sprite of its own.

⚠️ **`AnimGrowingShockWaveOrb` — DISCLOSED, and the most likely thing in this
batch to read wrong on screen.** It is a contract-then-expand under the INVERTED
GBA affine rule (parameter climbs `0x10 -> 0x100` over 30 frames and back, so
the orb starts large, draws IN, then blows out); asserted on direction, because
reading the inversion backwards produces exactly the opposite motion.
**`0x10` is a 16× magnification.** That is what the affine table says and it is
reproduced rather than invented down — but this project draws at 4× on a 1024px
canvas where source drew at 1× on 240px, the same carries-badly risk M36E3's Sun
ray hit at a much milder 3.2×, which is still an open look-call. Rob's judgement,
not a correctness gap; the two constants are named so it is a one-line change.

⚠️ **`AnimTask_AnimateGustTornadoPalette` ships as a STRUCTURED NO-OP, and this
is a genuine capability gap rather than a choice.** It rotates 8 entries of the
`ANIM_TAG_GUST` OBJ palette. M36E3's palette remapping is BACKGROUND-only
because it is driven by the per-background `palette_colors` the extractor emits;
the pulled sprite sheets are composited PNGs from which the index a pixel came
from is not recoverable. Faking it with a hue shift would invent motion the
reference does not describe. **The frame COST is reproduced exactly and pinned
by test**, which is what a following `waitforvisualfinish` depends on, and the
tornado's own frame sequence still supplies the bulk of the visible motion.

**NOT screenshot-verified.**

**Flagged, not fixed:** `m36d_batch_test` leaks ~1600 ObjectDB instances at exit
because its `FakeStage` doubles are never freed. Confirmed PRE-EXISTING by
running the pre-batch-8 test file against the current behaviors (16 resources
before, 17 after — one more placeholder texture), so it is the file's
long-standing pattern rather than anything behavior-level.

### M36D batch 7 — COMPLETE 2026-07-30. THE ICONIC TIER IS CLOSED.

`m36d_batch_test` 246 -> **279/279** (first run, no failures); 16-suite sweep
green. Coverage **401 -> 419 of 932 (45.0%)**, and iconic Gen 1-3
**91.4% -> 100% (70/70)**.

21 behaviors closing the last six blocked iconic moves: Thunder, Confuse Ray,
Frustration, Volt Tackle, Dragon Dance and Extreme Speed (the most expensive
single move in the tier, at 6 behaviors).

**Step 0 was asked up front which of the 21 mutate a BATTLER rather than
spawning particles**, because that is the leak class M36 has now hit four
times. The answer was much better than Dig's four-call chain: **only TWO
pairings are required** — `AttackerStretchAndDisappear` ->
`ExtremeSpeedMonReappear` for visibility, and `VoltTackleOrbSlide` ->
`VoltTackleAttackerReappear` for a displacement that drags the attacker ~320px
off-screen. Everything else self-restores. Both pairings still route through
`MonOffset` and the tracked visibility setter, and **the suite asserts the
broken-pair case for each** — omit the partner, end the run, and the mon is
still on its mark and visible.

**A detail worth pinning, and exactly the sort a port gets wrong silently:**
`AnimTask_SetAttackerInvisibleWaitForSignal` releases on `arg 7 == 0x1000`
(4096), **not** the `-1` sentinel every other waiting behavior in this engine
uses. The suite asserts that -1 does NOT release it and 0x1000 does. It also
decrements the visual task count by hand upstream — so the script cannot
deadlock waiting on a task that is waiting on the script — reproduced here as
an uncounted stepper.

**`AnimTask_InvertScreenColor` is genuinely un-portable as written**, and is
the second such case after batch 5's exclude-blend. Upstream it is
`InvertPlttBuffer` (palette.c:384) — a bitwise NOT of every entry of the
selected palettes, of BGR555 words including bit 15, not of pixels. There is
no palette indirection here, so it became a per-pixel inversion in the recolor
shader. The property that matters is that it is an **INVOLUTION which restores
nothing**: Thunder calls it an EVEN number of times and relies on the second
call undoing the first, so it is ported as a TOGGLE. A port that always
inverted would leave the screen wrong after any odd count — asserted directly.

**Other faithful details kept rather than tidied:** Frustration's power bands
are INVERTED relative to Return's (0 is the strongest, since low friendship
means a stronger Frustration); `ShakeTargetInPattern` walks a fixed 10-entry
direction table, and its vertical mode takes an ABSOLUTE value so the target
only ever bounces downward — a real asymmetry between its two modes, asserted;
`ConfuseRayBallSpiral` orbits on an ELLIPSE (32 across, 8 down) while drifting
downward, so a circular port would read wrong; and `AnimHitSplatOnMonEdge`
positions from the battler sprite's ORIGIN rather than its centre, which is
the whole "on mon edge" part.

**Approximated, and recorded as such:** `AnimTask_DragonDanceWaver` is a
per-scanline horizontal offset on the BG layer the script has moved the
attacker into — a heat-haze. There are no scanlines here, so it became a
horizontal wobble of the attacker on the same ramp-in / hold / ramp-out
envelope. The timing is source-exact; the mechanism is not.

**Verification, stated precisely.** Extreme Speed captured on a real windowed
run (the harness triggered at frame 687, on the animation): the mid-animation
frame shows the screen darkened with the attacker correctly hidden, and the
final frame shows the screen fully restored with the target back to normal
colours. **The attacker-visibility pairing itself is confirmed by TEST, not by
that capture** — the harness has never shown the player's Pokemon in any run,
a pre-existing intro artifact flagged earlier and unrelated to this batch.

**M36D's iconic phase is complete.** Decision 5 ordered iconic Gen 1-3 first,
then remaining Gen 1-3, then the rest; that first phase is now finished, and
the next batch would be a different character of work.

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
