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

| ~~all four b16 deferrals~~ | b16 | **CLOSED in b17** — `AnimTask_SquishTarget`, `AnimBrickBreakWall`, `AnimRazorWindTornado`, `AnimTask_NightShadeClone` all ported once read. They were the board's top three picks by yield, which is what deferring them was for. | — |
| ~~`AnimTask_ScaryFace`~~ | b17, b18 | **CLOSED in b19 — and the stated reason was WRONG both times.** Not "absent from the pull": REFUSED by the pull's own two-palette-bank guard, which measured the off-screen scroll margin. Narrowed to the visible 30x20 and re-proved on a synthetic case. | — |
| ~~`AnimTask_GlareEyeDots`~~ | b18 | **CLOSED in b20** once the `_Step` tail was read. | — |
| ~~`AnimTask_DestinyBondWhiteShadow`~~ | b18 | **CLOSED in b20.** | — |
| ~~`AnimTask_PurpleFlamesOnTarget`~~ | b20 | **CLOSED in b21** once `AnimTask_GrudgeFlames_Step` and the flame step were read. | — |
| `AnimTask_FakeOut` (+1) | b18 | **SCREEN-EFFECT gap.** WIN0/BLDY window-darken, closer to M36E's surface than a sprite behavior. | M36E-shaped |

**`AnimFallingFeather` — deferred by batches 12, 13 and 14, then taken
directly on 2026-07-30. See its own section. The list now holds only
short-lived, current-batch deferrals.**

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

### M36 VM cleanup fix — COMPLETE 2026-08-03. All 23 leaks closed at the root.

The harness's own finding, fixed. **778/778 scripts now run clean; the
`KNOWN_LEAKS` baseline is EMPTY.**

**One root cause, so one fix rather than 22.** The VM's cleanup nets only
covered the TRACKED path — `MonOffset`/`MonScale`'s metas and the recolor
shader — so a behavior writing `node.rotation`, `node.modulate` or
`node.scale` directly, or spawning a sprite that never reached
`notify_spawned`, escaped every one of them. Two additions to
`AnimScriptVM`:

* **`_capture_battler_baseline()` at `start()` / `_restore_battler_baseline()`
  at `_finish()`** — snapshots every battler's position, scale, rotation,
  visibility, modulate AND material, and puts them back unconditionally.
* **`_free_layer_visuals()` at `_finish()`** — frees every `AnimSprite` and
  every `_anim_trace` clone left on the layer, not just the nodes a behavior
  remembered to register.

**Deliberately records the WHOLE visual state**, not the specific properties
known to leak today. The failure mode this exists for is a behavior touching
something nobody thought to track; enumerating today's list would rebuild the
same gap one property along.

⚠️ **The meta-driven nets are KEPT as a fallback, not replaced.** Tests that
drive the VM directly set `state = RUNNING` without calling `start()` — the
project's own established direct-dispatch convention — so no baseline exists
for them and the old nets must still stand alone. Ordering in `_finish` is
meta nets first, snapshot second, so the snapshot wins where both apply.

⚠️ **`_free_layer_visuals` is scoped by TYPE and TAG, never "every child".**
On a real stage the battler sprites share that parent. An `AnimSprite` is
anim-owned by construction and `_anim_trace` is the meta
`_clone_battler_visual` already sets for exactly this purpose.

**Both nets proven load-bearing rather than assumed**: disabling the baseline
restore produces 21 failures, disabling the layer free produces 9. The
overlap (30 against 23 leaking moves) is moves that leak both ways — Arm
Thrust leaves a rotation AND a sprite.

**Regression**: all 8 M36 suites unchanged (m36d_batch_test 1215/1215), plus
six battle-screen-adjacent suites that consume the anim engine —
`phase4d_doubles_visual` 27/27, `m26_b4_3_weather_trigger` 24/24,
`m25b_menu` 32/32, `m26c1_databox` 60/60, `m26_b3_6c` 168/168,
`hit_effect_smoke` 91/91. Nothing depended on the old partial-restore
semantics.

---

### M36 leak harness — BUILT 2026-08-03. 23 real defects on its first run.

`scenes/battle/m36_leak_harness.tscn`. Built after asking whether a
15-batch screenshot pass was worth it. **It largely is not** — the honest
split is that screenshots do two different jobs, and only one of them is
mechanisable:

* **defect detection** — did it render, leak, wedge? Bulk, unattended, cheap.
* **fidelity judgement** — does it look like the reference? Needs the
  reference beside it, and remains a human pass. Every "a screenshot caught
  it" case in this project's history was either Rob looking or something
  obviously broken (a white box, a black slab, a 1 px bar) — never a subtle
  motion error.

So this harness does the first job across the whole roster and makes no claim
about the second. **A green run here is not "the animations are verified".**

**What it does**: runs all **778 playable in-scope move scripts** end to end
against one shared stage and checks, per move, that the run terminates, does
not end in VM ERROR, leaves every battler at its resting position / scale /
rotation / visibility / modulate / material, leaves no `AnimSprite` or
`_anim_trace` clone on the layer, and clears the batch-37 scanline band.

**Why no other suite could see this**: every per-behavior test builds a
fixture and throws it away, so nothing CAN leak into anything. A leak is only
observable across a whole script run — and it is what a player actually
suffers, because a battler left displaced, shrunk, hidden or tinted STAYS
that way into the next turn.

**FIRST RUN: 23 leaks across 22 moves**, and they are one root cause in three
dresses — **the VM's cleanup nets only cover the TRACKED path**:

| Dress | Moves | Why the net misses it |
|---|---|---|
| rotated | 7 (Double-Edge, Arm Thrust, Gyro Ball, Raging Bull, 5 Torques) | `_restore_scaled_battlers` restores rotation only when the `_anim_mon_rotation` meta is set, which only the MonScale deform helper sets. Direct `node.rotation = ...` escapes it. |
| tinted | 9 (Defense Curl, Iron Tail, Poison Tail, Doom Desire, Metal Burst, Flare Blitz, Iron Head, Shadow Force x4) | `_clear_battler_blends` clears only the recolor SHADER. Direct `node.modulate` writes escape it. |
| sprites left | 5 (Charge, Flash Cannon, Searing Shot, Lumina Crash, Armor Cannon) | `_finish` frees `_spawned`, but `_make_sprite` never calls `notify_spawned` — so a sprite whose stepper `_finish` clears before it ends is never freed. |
| scaled | 1 (Overdrive) | Same family: a direct `node.scale` write outside MonScale. |

**PINNED AS A BASELINE, NOT SILENCED.** `KNOWN_LEAKS` records the exact
23-entry set, and the suite fails if it changes in EITHER direction — a new
leak from a later batch, or a pinned one that stops leaking without the
baseline being updated. Green today, and it protects every batch that lands
on top of it. **Shrinking that dictionary is the definition of done.**

**The fix is deliberately NOT in this change.** Making the nets unconditional
(snapshot every battler at `start()`, restore at `_finish()`; free every
sprite on the layer rather than just `_spawned`) is a core-VM change that all
1215 M36D assertions sit on top of, and it should be its own task rather than
rushed in beside a batch.

**Detection proven, not assumed**: disabling `_restore_displaced_battlers`
produces 5 new failures — which also establishes that the displacement net is
load-bearing for exactly 5 moves, the rest restoring themselves.

**Informational, deliberately not asserted**: 57 scripts spawn no visual at
all. Some are genuine sound/query-only animations, so there is no source-backed
number to assert — it is printed so a REGRESSION in the count is visible.

---

### M36D batch 38 — COMPLETE 2026-08-03. Three names that over-promise.

**775 -> 778 of 845 in-scope (91.7% -> 92.1%).** 3 behaviors, 3 moves — Volt
Switch, Superpower, Skull Bash. Behaviors 485 -> 488, suite 1193 -> 1215/1215.

A small batch on purpose. The unifying thread is that **each behavior's NAME
promises something the code qualifies**, and in all three cases the plausible
port is the one that believes the name.

**`AnimTask_VoltSwitch` is not a task.** Its signature is
`void AnimTask_VoltSwitch(struct Sprite *)` -- a sprite callback wearing a
task's name. Registered under the name the extracted scripts reference, with
the trap stated at the code site.

**And the return trip IS the move.** It arcs to the target, then immediately
arcs BACK to the attacker over a fixed 0x14 = 20 frames -- Volt Switch is the
move where the user leaves. A one-way port drops its entire signature and
still looks like a perfectly good projectile. Its side branches also do
DIFFERENT work rather than mirrored work: an opponent-side user negates
args[2], while a player-side one instead nudges the spawn 10 px DOWN. Neither
branch does the other's job, so a plain mirror is wrong in both directions.

**`AnimSuperpowerRock` runs two phases at two DIFFERENT fixed-point scales** --
8.8 for the rise, 4.4 for the flight. Using one for both makes a phase 16x too
fast or too slow. It also starts at **y = 120, screen bottom**, not on the
attacker, and takes its heading ONCE, from the live attacker-to-target delta,
so the flight time is set by how far apart the battlers are and is not an
argument at all.

**`SlideMonToOffsetAndBack` only comes back when args[5] says so.** Source
stores `DestroyAnimSprite` as the completion callback otherwise, leaving the
mon exactly where it was slid to. **Reading the name rather than the code
cancels the displacement half the callers want.** The sprite itself is
invisible -- a controller that drags the battler -- so it goes through the
VM's tracked mon offset per rule (3), and an aborted run restores. The y
mirror is conditional on args[3] while the x mirror is unconditional.

⚠️ **RULE (15) A FOURTH CONSECUTIVE BATCH, again my assertion.** Five
injections; four failed at once. The fifth -- the wrong fixed-point scale for
the flight phase -- PASSED, because the guard asked only whether x changed,
which is true at any scale (16x too fast is still "moved"). Now measures the
per-frame step SIZE against the battler gap: one frame of flight is gap/16,
tens of pixels, never hundreds. Re-injected and it fails.

**Still deferred, and for a read-it-properly reason rather than a hard one**:
`AnimTask_LeafBlade`, `AnimTask_AirCutterProjectile`,
`AnimTask_EruptionLaunchRocks` and `InitPoisonGasCloudAnim` are multi-state
spawners whose step machines were not read in full this batch. Rule (4):
defer rather than guess. They remain the largest readable block left, and all
four are asserted as still-blocked so a partial port cannot pass quietly.

---

### M36D batch 37 — COMPLETE 2026-08-03. The scanline surface, and a deferral reason that was half wrong for five batches.

**851 -> 856 of 932; against the NEW in-scope denominator, 770 -> 775 of 845
(91.1% -> 91.7%).** 2 behaviors, 5 moves — Rapid Spin, Ice Spinner, Spin Out,
Mortal Spin, Aqua Step. Behaviors 483 -> 485, suite 1175 -> 1193/1193.

**SCOPE CHANGE, Rob 2026-08-03: Z-Moves and Max Moves are out of scope
entirely.** The boundary is exact and taken from source, not eyeballed:
`FIRST_Z_MOVE = MOVES_COUNT_GEN9` (`include/constants/moves.h:913`), so id 847
(Malignant Chain) is the last in-scope move and 848 (Breakneck Blitz) the
first excluded one. **87 of the 932 bound moves are Z/Max, leaving 845
in-scope.** Note coverage went DOWN when restated (91.3% -> 91.1%): 12 of the
87 were already playable, so the exclusion removed more numerator than
denominator. That is the honest figure and it is recorded rather than
presented as a gain.

⚠️ **THE DEFERRAL REASON WAS HALF WRONG, AND HAD BEEN INHERITED UNCHECKED
SINCE BATCH 27.** These five moves were recorded across five batches as
blocked on "per-scanline DMA". Reading both behaviors in full:
**`AnimRapidSpin` never touches a scanline register.** It is a plain sprite
behavior — position on a battler, oscillate x, drift y, die on a threshold —
and needed no new surface at all. Only `AnimTask_RapinSpinMonElevation` is the
scanline effect. The two were filed together because the same five moves need
both, **which is not the same thing as sharing a mechanism.** Rule (6)'s
family: a stated reason outlives the reading that produced it, and gets
re-cited as fact. The test that pins this deliberately runs Rapid Spin with no
background surface present.

**The surface itself is small, and it is the mechanism rather than an
approximation of it.** The hardware points a DMA at `REG_BG1HOFS`/`REG_BG2HOFS`
and feeds it a per-scanline buffer — that is, a horizontal background scroll
that VARIES BY ROW. This project's background was already a UV-scrolled
shader, so the port is three uniforms (`band_top`, `band_bottom`,
`band_offset`) and one branch offsetting `u` as a function of `v`. New
`AnimStage.set_background_band` / `clear_background_band` /
`background_band`, following `set_background_scroll`'s own stage-pixels-to-UV
convention.

**The motion**: a band spanning the mon (`y-33` to `y+36`) whose top and bottom
edges both sweep UPWARD at `args[1]` px/frame, the bottom edge starting 8
frames later so the band has real depth while it travels.

⚠️ **+240 ON A 256 px BACKGROUND IS NOT A SCREEN-WIDTH JUMP — it wraps to
-16.** The visible effect is a 16 px horizontal SHIMMER alternating every two
frames. Porting the literal 240 displaces the band nearly a full screen and
reads as a tearing bug rather than a spin. Pinned by asserting the offset's
magnitude stays under 40 px.

**Disclosed divergence**: source only tears the scanline effect down when
`args[2]` asks, leaving it installed otherwise for a following script step to
reuse. This port ALWAYS clears the band — a displaced strip of background left
on screen after the move is the same leak class rule (3) exists for, and no
script in this corpus relies on the carry-over. `args[2]` is therefore
deliberately unread, stated at the code site rather than silently ignored.

⚠️ **RULE (15), TWICE MORE — AND BOTH TIMES IT WAS MY ASSERTION AT FAULT.**
Five injections were run; four failed immediately. The fifth revealed **two
weak guards of my own**:

1. *"a falling Rapid Spin ends on its threshold"* asserted only THAT it ended.
   Injecting a hardcoded crossing direction still ends the falling case — on
   frame 1, because it starts already past that test. Now measures the frame
   COUNT (both legs travel 40 px at 3 px/frame, so ~13 frames each), which is
   what separates a captured direction from a hardcoded one.
2. *"the band is cleared when done"* asserted `bottom <= top`. The two edges
   converge on the same y BY CONSTRUCTION, so that is true whether or not
   anything cleared it — it passed against an injection that removed the clear
   entirely. Now checks the explicit reset to `Vector3.ZERO`, which the sweep
   alone can never produce because the top edge converges on a real on-screen
   y, never 0.

Both were re-injected after strengthening and both now fail. **Rule (15) has
now fired in three consecutive batches, each in a different shape** — two
source facts where only one is observable (b34), a stage double that cannot
express the axis (b35), and here an assertion that is satisfied by the
degenerate case it was meant to exclude.

---

### M36D batch 36 — COMPLETE 2026-08-03. The one-away tail, and one shared family inside it.

**839 -> 851 of 932 (90.0% -> 91.3%). 12 behaviors, 12 moves.** Behaviors
471 -> 483, suite 1140 -> 1175/1175.

**The blocker graph has essentially stopped sharing.** 43 of the 93 blocked
moves need exactly one behavior — and they are 43 DIFFERENT behaviors. The
greedy top has fallen from +19 (batch 33's board) through +3 to a flat +1 for
nearly everything. This batch is therefore selected for READABILITY rather
than yield, and its ~1-move-per-behavior ratio is structural, not a miss.
**Rule (1) inverts here**: from this point the metric that mattered for 30
batches — machinery retired — no longer distinguishes candidates.

**The one family left: five behaviors are `InitAnimArcTranslation` plus an
arc step, and they differ ONLY in where the destination comes from.** That
difference is the entire port:

| Behavior | Destination |
|---|---|
| `SpriteCB_SurgingStrikes` | target + offset (the family default) |
| `SpriteCB_TripleArrowKick` | target's EXACT centre, no offset; forces frame variant 1 (feet) |
| `SpriteCB_GlacialLance` | the MIDPOINT of both targets in doubles — thrown at the side |
| **`SpriteCB_MoongeistCharge`** | **the ATTACKER** — it is a charge |
| **`SpriteCB_PowerShiftBall`** | **the ATTACKER** — a self-buff; and the only one that side-mirrors, on x only |

⚠️ **"Arc to the target" is the natural reading and is wrong for two of the
five.** Both `data[2]` and `data[4]` in Moongeist Charge are computed from
`gBattleAnimAttacker`, not the target. Registering these as one shared alias —
which the identical step function invites — would send a charge animation
flying at the opponent. Pinned by asserting the landing point is nearer the
attacker than the target; the injection sends it to the target and fails.

**`AnimLavaPlumeOrbitScatter` does not orbit, despite the name.** The phase is
sampled ONCE to pick a heading (`Sin(phase, 10)`, `Cos(phase, 7)`) and then
never advances — each ember flies a straight line at constant velocity. **The
ellipse is in the SPREAD of headings across embers, not in any one ember's
path.** Reproducing the name rather than the code gives every ember a circular
path and loses the burst entirely. Tested by asserting equal per-frame deltas
AND that two different launch phases yield genuinely different headings.

**`AnimEllipticalGustAttacker` is FLAT** — amplitude 32 in x against only 8 in
y, so it reads as a horizontal swirl. A single-radius port is a different
animation; the test requires max-x to exceed max-y by 2.5x.

**`AnimSmellingSaltExclamation` anchors to the battler's TOP edge, not its
centre, and is CLAMPED at y >= 8** so a tall Pokemon cannot push the mark off
the top of the screen. Both halves injected and caught.

**`SpriteCB_SearingShotRock` destroys itself outright** if its selected battler
has no visible sprite, rather than drawing at a stale position — the same guard
batch 22's `_anim_sprite_on_selected_mon_pos` carries.

⚠️ **RULE (12) AGAIN, and this time for two behaviors at once.**
`AnimTask_TechnoBlast` and `AnimTask_ShellSideArm` both answer on **arg 0**,
not ARG_RET, because their scripts read them with an immediately-following
`jumpargeq 0` which does not reload the register file. Normalising them onto
arg 7 looks tidier and breaks both consumers; the injection confirms it. Both
are also **structurally correct rather than stubbed**: Techno Blast returns 0
because this project has no Drive items, which is upstream's own no-Drive
branch, and Shell Side Arm returns 0 because `gBattleStruct->swapDamageCategory`
has no equivalent here. **Disclosed: a Shell Side Arm that really did swap
category will play the wrong one of its two animations** until the engine
exposes that flag.

**Injections.** 9 run, 9 caught.

**Where the remaining 81 sit.** ~20 are genuinely blocked on absent
architecture — the WIN0/WIN1 spotlight family (Encore, Spotlight, Flatter,
Flower Trick, Oceanic Operetta, Instruct), palette backup buffers (Overheat,
Burn Up), the Memento shadow, per-scanline DMA (the Rapid Spin family, 5
moves), seismic-toss BG scroll, mosaic + sheet swap (Transform, Acid Armor),
and the item-icon surface (Bestow). Terrain (Camouflage, Rising Voltage,
Terrain Pulse) is VOID by decision, not deferred. **Z-Moves and Max Moves are
a live question**: several remaining blockers serve only those, and CLAUDE.md
records that family as permanently excluded at the M19 mechanics level — if
that exclusion extends to animations, they come off the denominator rather
than being ported. Rob's call, not assumed here.

---

### M36D batch 35 — COMPLETE 2026-08-03. Pairs that are not pairs.

**827 -> 839 of 932 (88.7% -> 90.0%). 10 behaviors, 12 moves.** Behaviors
461 -> 471, suite 1114 -> 1140/1140. **The 90% line is crossed.**

The batch's shape: behaviors whose sibling is already ported, or whose twin
ships alongside. **Three of the five pairs diverge somewhere that matters**,
which is the finding — a shared name or a shared step function does not imply
a shared mechanism, and every one of those divergences is the kind that looks
correct in isolation.

**`AnimThrowMistBall` IS the shared translate callback, with one difference.**
It OVERWRITES the sprite position with the attacker's own coordinates BEFORE
delegating, so args 0/1 — the spawn offset every other user of that callback
honours — are discarded. Registering it as a plain alias would spawn the ball
at an offset and look fine on its own. Pinned by spawning with args 0/1 at 0
and at 60 and asserting the two positions are identical.

**`AnimSkyDropBallUp` shares `AnimFlyBallUp`'s step exactly and hides the
OTHER mon.** It spawns on the TARGET while hiding the ATTACKER — Sky Drop
carries the victim up, so the ball marks where they were and the user is what
vanishes. "Fly, but for the target" hides the wrong Pokemon. The shared body
was factored into `_fly_ball_up_from(spawn_on)`; batch 8's own entry point and
tests are untouched. Routed through the VM's tracked visibility, rule (3).

**`AnimWillOWispFire`'s ellipse GROWS.** Both amplitudes are accumulators, not
constants (`data[3] += 0xC0 * 2`, `data[4] += 0xA0`, each read `>> 8`), so the
flame spirals OUTWARD from the target rather than circling at a fixed radius —
and it widens faster horizontally than vertically, so the spiral flattens as it
grows. A fixed-radius port is a different move; the test asserts the late
radius exceeds the early one by more than 2x AND that max-x exceeds max-y.

⚠️ **DISCLOSED, and it is a deliberate omission rather than a miss**: source
additionally re-centres that spiral between both targets — but only when the
battle is doubles AND the move's own target type is `TARGET_BOTH`. This port
has no move-target information at the behavior layer, and applying the
side-centre unconditionally moves the flame off a single target in every
singles battle. Centred on the target itself; the doubles case is not modelled.
The first cut DID apply it unconditionally and the test caught it.

**`AnimKnockOffAquaTail`'s side branch is not a mirror.** Against a PLAYER-side
target the x delta is SUBTRACTED and the orbit runs BACKWARDS (phase step -11);
against an opponent-side one the same delta is ADDED and the orbit runs
forwards. **The y delta is added either way** — not mirrored, unlike x. Reading
it as a plain sign flip on both axes puts the tail on the wrong side of the mon
in one of the two cases, and the injection confirms it.

⚠️ **RULE (14) FIRED AGAIN, in the same shape as batch 32.** The orbit-direction
check first sampled Y — and the orbit starts at phase 192, the sine's own
minimum, where stepping either direction moves Y identically. Moved to X, where
cosine is steepest.

**`AnimWillOWispOrb`'s drift is keyed on the ATTACKER's own side**, not on the
direction of travel toward the target: the orbs fan AWAY from their source
(-4 px/frame player-side, +4 opponent-side). Pinned absolutely per side.

**`AnimPresent` arcs to a point 10 px BELOW the target's centre** — the box
lands at the feet, not the face — and its args are unused, which source's own
comment says outright. **`AnimPresentHealParticle` is a plain LINEAR drift**
(`y2 = velocity * age`, no easing and no sine anywhere); an eased port fails
the equal-per-frame-step assertion.

**`AnimateZenHeadbutt`'s +18 y is a constant, not an argument.**

⚠️ **AND ITS "NOT MIRRORED" HALF IS UNTESTED — injecting a mirror PASSED.**
`FakeStage.facing_sign()` returns a fixed 1.0, so no stage double in this suite
can observe a facing flip. The magnitude and the battler selector are pinned;
the un-mirrored claim rests on the source read alone, and the test says so.
Second occurrence of rule (15) in two batches — worth noticing that the rule
earns its place by catching a DIFFERENT shape each time (batch 34: two source
facts, only one observable; here: a stage double that cannot express the axis).

**Injections.** 8 run, 8 caught, plus the Zen Headbutt mirror which passed and
is now documented as uncovered rather than left implying coverage.

---

### M36D batch 34 — COMPLETE 2026-08-03. The multi-phase spawners batch 33 deferred.

**819 -> 827 of 932 (87.9% -> 88.7%). 8 behaviors, 8 moves** — Torment(259),
Barrage(140), Water Sport(346), Brine(362), Ion Deluge(569), Smokescreen(108),
Odor Sleuth(316), Magical Leaf(345). Behaviors 453 -> 461, suite 1070 ->
1114/1114.

Batch 33 deferred five of these as "multi-phase SPAWNERS ... a batch's work on
its own rather than a task." Four of the five are now closed; the other,
`AnimTask_LeafBlade`, genuinely is a batch on its own (a nine-state machine
that re-aims a slash between states while driving the target's own affine
table) and stays deferred alongside `AnimTask_AirCutterProjectile` and
`AnimTask_EruptionLaunchRocks`, both of which build per-sprite coordinate
tables through helpers that need their own reading pass.

**What makes these a class**: the TASK, not the script, decides how many
sprites exist and where each goes. They share no code with each other.

**THE CADENCE IS THE PORT, for Torment.** Six thought bubbles alternating
right/left, converging inward and climbing in pairs (32/-20, 26/-26, 20/-32) --
but the timing is what a plausible misreading gets wrong. Between bubbles the
attacker runs a 12-frame affine wobble, and `data[1] <= 2` is tested AFTER the
increment, so the extra 10-frame hold applies to bubbles 0 and 1 ONLY. Torment
opens slowly and then rattles off the last four: frames 0/22/44/56/68/80.
Applying the hold uniformly still produces six correctly-placed bubbles, which
is why the test pins the frame list rather than the layout.

**Barrage STROBES, it does not fade** — sixteen invisibility toggles at one per
two frames, and its arc lands BELOW the target's centre by a quarter of the
target's height, because the egg bounces off the body rather than the face.
Injecting an alpha ramp (the natural-looking alternative) fails both halves.

**Water Sport's spray direction is side-dependent** (`data[7]` is +1 on the
player's side, -1 on the opponent's), and the sweep reverses when it leaves the
-16..256 band, three times, before the task stops spawning. Pinned absolutely
per side rather than "the two sides differ" — rule (13).

**Brine's rain band is side-dependent too, and not merely different**: player
side rains y=0..40, opponent side y=40..90 — the opposing mon sits higher on
screen, so the shorter, lower band keeps drops on the mon instead of above it.
Asserted as the 40 px DELTA rather than two absolute values, because the drop
has already taken its first fall step by the time it is measurable.

**Ion Deluge is not anchored to a battler at all** — random x across the full
240 px width, random y in the TOP HALF only (`Random2() % (DISPLAY_HEIGHT / 2)`),
because it charges the sky. The spawn test is `data[0] % interval == 1` after
the increment, so the first ion lands on frame 1.

**Smokescreen's burst is offset (+8, +8)** — down AND right, not centred; the
task destroys itself the same frame it fires, so the burst outlives it.

⚠️ **AN OVER-CLAIM CAUGHT BY ITS OWN INJECTION, and it is the most useful thing
in this batch.** Odor Sleuth's two blended clones are exact mirror images, and
the first write attributed that to their OPPOSITE phase steps (+16 / -16). The
injection — step both the same way — **PASSED**. Only x is drawn
(`Cos(phase, radius)`), and `cos(t+128) == -cos(t)` whichever way the phases
walk, so the mirror comes entirely from the **180-degree starting offset**, and
the step directions are unobservable in this port. The comment and the test now
say so explicitly, and the offset (which the same injection method DOES catch)
is what is pinned. A passing mirror test is not evidence the directions are
right.

Odor Sleuth also carries a **dead store worth not porting**: upstream sets
`x2 += 24` / `x2 -= 24` at init, then overwrites x2 with `Cos(phase, radius)` on
the very first frame. Porting those as a persistent offset would double the
separation; they are invisible upstream only because `Cos(0,24)` and
`Cos(128,24)` happen to equal exactly +24 and -24. The flicker is the other
half: each clone toggles visibility every two frames, starting in opposite
states, so exactly ONE is on screen at a time.

**Magical Leaf fades IN to each colour and then cuts** — seven colours, 17
frames each (strength 0..16 then snap to 0), 119 total. A cross-fade never
returns to 0 mid-run, which is what the injection checks. Disclosed: upstream
reaches two specific palette slots; this port has no palette indirection, so
the ramp applies to every live anim sprite — during Magical Leaf those are
exactly the leaves.

**Injections.** 9 run, 8 caught, 1 revealed the over-claim above. Every headline
claim is now either injection-verified or explicitly documented as unobservable.

---

### M36D batches 31-33 — COMPLETE 2026-07-31. Paired mechanisms, sprite singletons, and the task tail.

**+38 moves across three batches: 781 -> 819 of 932 (83.8% -> 87.9%).**
415 -> 453 registered. Tier 2 227 -> 240/283 (84.8%); Tier 3 484 -> 509/579
(87.9%). `m36d_batch_test` 959 -> **1070/1070**.

---

#### Batch 31 — paired mechanisms (+14: 781 -> 795, 16 behaviors)

Eight two-sprite (or sprite-plus-task) effects where neither half means
anything alone. Three reuse earlier machinery outright: Conversion 2 is
batch 27's Conversion with the signal **inverted** (its squares carry their
own delay and fly to the attacker, where Conversion's wait to be killed, and
the blend ramps the other way); the Perish Song notes are batch 25's music
family; the partner slides are batch 2's SlideMon pair aimed at a partner
slot.

**`AnimLockOnMoveTarget` is a WRAPPER, not a duplicate** — it applies one of
four quadrant offsets with a matching flip and then *calls*
`AnimLockOnTarget`. Registering them as an alias would drop the quadrant
work, so the test asserts they are **different** implementations — the
inverse of the alias assertions in batches 24/27/30.

**`AnimPerishSongMusicNote2` is never drawn.** It sets `invisible = TRUE` on
its first frame and exists purely as a timer: at `120 - arg0` frames it greys
the field, 80 later it ends. Porting it as a visible sprite puts a stray note
on screen that upstream never shows.

Also: the Helping Hand clap uses **absolute screen coordinates** (100/140,
y 56) like batch 26's moon; `AnimWoodHammerHammer` **waits 37 frames**
shivering before it swings, which is most of the animation; the Ingrain root
never moves at all — its whole behavior is a flicker in its last ten frames.

**Deferred**: `AnimTask_SketchDrawMon` is a scanline effect (the pencil
"drawing" the mon is a per-scanline background shear), and `AnimPencil` is
deferred with it.

---

#### Batch 32 — sprite singletons (+17: 795 -> 812, 14 behaviors)

One behavior per move, no shared machinery left to retire.

**`AnimSuperpowerOrb` holds for 180 frames** — three seconds, essentially the
whole animation — and only then crosses to the *other* battler in 16.
**`AnimDevil`'s orbit both decays and reverses**: the radius shrinks with age
while the phase runs forward to 128 and back. **`AnimOverheatFlame`'s spray
is a flattened ellipse** — the vertical amplitude is exactly 3/5 of the
horizontal — and the speed arg also offsets the *start*. **Happy Hour's coins
ride a tall narrow ellipse** (amplitudes 16 and -70), arcing up before they
drop.

**`AnimBounceBallShrink` hides the attacker** — the ball *is* the mon — so it
goes through the VM's tracked visibility rather than a raw `visible = false`,
the leak class rule (3) exists for. The test aborts the run mid-flight and
checks the VM's own net restores it.

**`AnimDragonRushStep`'s two branches are byte-identical**, and source's own
comment says so. Reproduced as the no-op it is; the side check only matters
in the init.

---

#### Batch 33 — the task tail (+7: 812 -> 819, 8 behaviors)

**The two Thrash tasks are different effects despite the shared name stem**:
`AnimTask_ThrashMoveMonHorizontal` is an affine *deformation* (and its table
carries an `AFFINEANIMCMD_LOOP(2)`, so it runs twice), while
`AnimTask_ThrashMoveMonVertical` is a plain *displacement*. Sharing one
implementation gives Thrash the same look twice.

**`AnimTask_FacadeColorBlend` cycles a 24-entry ramp** one entry per frame
rather than holding a tint. **`AnimTask_SkullBashPosition`'s step is 8.8
fixed point** — `0xC0` is 0.75 px/frame, so eight frames move the mon six
pixels; read as raw pixels it flings the mon 1536 px off the field.
**`AnimTask_MoveHeatWaveTargets` shoves every visible battler on the target's
side**, not just the target.

`AnimTask_GetStockpileCounter` ships as a **documented stub with its consumer
named**, per rule (9): it needs a disable-struct surface the anim layer does
not have, so it answers 0 — wrong but bounded — and the test pins that it
answers on arg 7 with the documented value rather than an invented one.

**Deferred with reasons rather than skipped**: `AnimTask_LeafBlade`,
`AnimTask_AirCutterProjectile`, `AnimTask_WaterSport`, `AnimTask_BrineRain`
and `AnimTask_CreateIons` are multi-phase spawners with their own step
machines — a batch's work each, not a task; `AnimTask_CreateBestowItem` draws
the player's real held-item icon, a surface the anim layer cannot reach;
`AnimTask_OdorSleuthMovement` needs the blended-clone variant this port does
not have. All five are asserted as still-unplayable.

---

**Four test bugs of mine, all caught by injection rather than shipped.**

1. **The Helping Hand direction guard was vacuous.** It used a player-side
   stage, where FakeStage puts the partner to the *right* — so the partner
   rule and the side rule both give -1 and the injection deleting the partner
   rule passed. Rewritten on an opponent-side stage, where the two disagree.
2. **The Dragon Rush spin check sampled at the sine's minimum** (phase 192),
   where stepping either direction moves Y identically. It reported "4.2 vs
   4.2" for a correct mirror. Moved to X, where cosine is at a zero crossing.
3. **The Dragon Rush side check only asserted the two sides DIFFER** — true
   under either reading, since attacker and target are always opposite in
   singles. The injection swapping to the attacker's side passed. Now pins
   the direction **absolutely** against source.
4. **The Facade blend check read a shader parameter that does not exist**
   (`blend_color`; the real name is `tint`), reporting 0 distinct colours
   against a correctly cycling blend.

One injection was itself malformed and hung the suite rather than failing it
— worth noting as a technique caveat: an injection that changes the *shape*
of a statement can produce a parse error whose symptom is a hang, not a
failure. Re-run as a one-line change inside the VM's `hide_battler` instead,
where it correctly caught three assertions.

**Injections.** 9 for batch 31, 8 for batch 32, 6 for batch 33 — each broken,
confirmed failing, reverted. Regression after all three: `m36a` 71/71,
`m36b` 53/53, `m36c` 66/66, `m36e_background_asset` 24/24,
`m36e_background_runtime` 30/30, `m36e3` 60/60, `hit_effect_dispatch` 40/40.

### M36D batches 28-30 — COMPLETE 2026-07-31. Deformations, the sprite tail, and which register a query answers on.

**+41 moves across three batches: 740 -> 781 of 932 (79.4% -> 83.8%).**
372 -> 415 registered. Tier 2 crossed 80% (203 -> 227/283); Tier 3 467 ->
484/579 (83.6%). `m36d_batch_test` 831 -> **959/959**.

---

#### Batch 28 — mon deformations (+13: 740 -> 753, 13 behaviors)

Every remaining task whose whole job is to scale, rotate, squash or clone a
battler. Most are an affine table plus batch 25's shared walk.

**⚠️ A BATCH-25 CLAIM CORRECTED.** That batch recorded the shared walk's
closing `deform.restore()` as a *disclosed divergence* — "upstream simply
stops, leaving whatever the table produced". **Wrong.**
`RunAffineAnimFromTaskData`'s `AFFINEANIMCMDTYPE_END` case calls
`ResetSpriteRotScale` and zeroes `y2`, so upstream restores at the end of
every table too. Corrected in place at the code site.

That correction matters because **one real table is genuinely asymmetric**:
`gShrinkAndGrowAffineAnimCmds` goes out over 12 frames and back over only 6,
netting +24/+30. It is harmless *because* END resets regardless — which
reframes the per-table sum assertions as **transcription guards, not leak
guards**, and the test now pins that table's asymmetry explicitly rather than
asserting a uniformity that does not hold.

**Two deferred, same surface as before.** `AnimTask_AcidArmor` is a scanline
DMA effect (the mon "melting" is a shear of the background);
`AnimTask_TransformMon` drives `REG_OFFSET_MOSAIC` and then calls
`HandleSpeciesGfxDataChange` to swap the battler's actual sprite sheet.

**`AnimTask_RotateVertically`'s two sides are NOT mirrors**: the player side
stops at `0x1FFF` (~45 degrees) while the opponent goes to `0x7FFE` (~180,
fully over). One shared limit gives a player mon that flips when it should
only tilt. **`AnimTask_Withdraw` rocks by ROTATION, not translation.**
**Minimize shrinks and drops clones; Double Team leaves the mon alone** and
sweeps its clones on a sine seeded half a cycle apart — tested together
because only one of the two deforms.

⚠️ **ONE DISCLOSED SIMPLIFICATION, and it is the highest-value item for a
screenshot pass.** Upstream calls `SetBattlerSpriteYOffsetFromYScale` after
every affine step so a scaling mon keeps its **feet planted** rather than
growing about its centre. Not ported: CLAUDE.md records a bottom-centre
`pivot_offset` being tried during M26B3-6a and **reverted for looking worse**,
and this session cannot check a visual change against that. Flagged, not
guessed at.

---

#### Batch 29 — the simple-sprite tail (+16: 753 -> 769, 16 behaviors)

One behavior per move, mostly a spawn point plus a short motion. Grouped
because they share no machinery beyond what is already built — **which is
itself the finding**: at this depth the port is no longer retiring
mechanisms, it is spending the ones batches 1-28 built.

Shapes worth naming: **Spit Up's spray is elliptical** (amplitudes 10 and 7,
wider than tall) while **the Angel's loop is circular** (Sin and Cos share
amplitude 80) — a real distinction between neighbouring behaviors, and both
are tested for it. **Swallow's orb decelerates** and ends by falling back
below its launch height, not on a timer. **Bonemerang comes back** — the
return leg is the whole move. **Wish Star enters from the side opposite the
caster** and accelerates on both axes. **Milk Bottle and Mean Look Eye both
open by arming BLDALPHA to (0,16)** and fade themselves in, so a port that
skips the arming has them pop in at full opacity.

---

#### Batch 30 — query tasks and the misc tail (+12: 769 -> 781, 14 behaviors)

**THE FINDING IS WHICH REGISTER A QUERY ANSWERS ON.** Most write
`gBattleAnimArgs[ARG_RET_ID]` (7) — the channel batch 24 taught the VM to
preserve. But **`AnimTask_IsTargetPartner` and `AnimTask_GetLycanrocForm`
write arg 0**, and that is not an upstream slip: both are read by a
`jumpargeq 0 ...` on the very next line, and `jumpargeq` does not reload the
arg registers. They work precisely *because* nothing intervenes. Normalising
either to arg 7 "for consistency" silently breaks its consumer; normalising
the others to arg 0 breaks the moment a `createsprite` comes between task and
jump. Both groups are tested for the register they use *and* for leaving the
other alone.

**`AnimTask_IsHealingMove` is inverted** — `gAnimMoveDmg > 0` means NOT
healing. **Doom Desire's query is `== 2`, not `>= 2`.** **`AnimMoveWringOut`'s
arg 2 is a DIVISOR of a full circle** (256/arg per frame), not a duration,
and the ring starts a quarter turn in.

**`AnimPunishment` is the FOURTH member of one duplicate chain** — verbatim
identical to `AnimForcePalm` (batch 27) and `AnimGunkShotImpact` (batch 24).
Three names, one implementation, asserted by identity.

Two stubs recorded rather than left bare, per rule (9):
`AnimTask_GetLycanrocForm` always reports the Midday form (no per-battler
species surface in the anim layer) and
`AnimTask_SetAnimTargetToAttackerOpposite` is a genuine no-op here
(`ANIM_TARGET` already resolves to the primary opposing slot, which is what
`BATTLE_OPPOSITE` names).

---

**Three test bugs of mine, all caught rather than shipped.**

1. **The template-name guard did its job**: `gWringOutSpriteTemplate` does not
   exist — the real name is `gWringOutHandSpriteTemplate`. This is exactly the
   failure rule (7) was written for after batch 13.
2. **The confetti variance check measured one particle twelve times.**
   `_spawn` returns the layer's FIRST `AnimSprite` child, so spawning twelve
   onto one stage re-measures particle zero — the same trap batch 24's Hydro
   Cannon test hit. It reported "2 distinct" no matter how varied the draws
   were. Fixed with a fresh stage per particle.
3. **A coverage list that was aspirational.** The first draft asserted Torment
   and Happy Hour play; `AnimTask_TormentAttacker` and
   `AnimHappyHourCoinShower` were read at Step 0 but never ported. An
   over-claimed move list is how a coverage test starts lying, and it failed
   immediately.

**Injections.** 9 for batch 28, 7 for batch 29, 7 for batch 30 — each broken,
confirmed failing, reverted. One injection had to be retargeted: `_side_centre`
appears in batch 22's code first, so the first attempt patched
`_centred_electricity` and was caught by *that* batch's test instead.

Regression after all three: `m36a` 71/71, `m36b` 53/53, `m36c` 66/66,
`m36e_background_asset` 24/24, `m36e_background_runtime` 30/30, `m36e3` 60/60,
`hit_effect_dispatch` 40/40.

### M36D batches 25-27 — COMPLETE 2026-07-31. The sound family, everything that fades, and the Gen 1 long tail.

**+40 moves across three batches: 700 -> 740 of 932 (75.1% -> 79.4%).**
346 -> 372 registered. Tier 1 closed at 70/70; Tier 2 189 -> 203/283 (71.7%);
Tier 3 441 -> 467/579 (80.7%). `m36d_batch_test` 718 -> **831/831**.

---

#### Batch 25 — the sound family (+15: 700 -> 715, 8 behaviors)

Music notes that fly off the singer, plus the two affine deformations that
make a mon look like it is bellowing or inhaling: `AnimJaggedMusicNote`,
`AnimWavyMusicNotes`, `AnimSlowFlyingMusicNotes`, `AnimBellyDrumHand`,
`AnimTask_UproarDistortion`, `AnimTask_DeepInhale`, and the two rainbow-blend
tasks.

**`_run_affine_cmds` retired.** Both deformations drive a battler through an
`AFFINEANIMCMD_FRAME(dx, dy, drot, frames)` list via
`PrepareAffineAnimInTaskData`, so the walk is shared. Deltas apply once per
frame for `frames` frames, and scale is in GBA units where **256 is identity
and larger means smaller** — the inversion this port already encodes in
`MonAnimator.godot_scale`.

**Every real affine table sums to exactly identity on both axes**, which is
the property the tests assert directly: a mis-transcribed or truncated table
leaves the battler permanently deformed. Disclosed divergence — the shared
walk restores explicitly on completion where upstream simply stops. The two
agree on real data; restoring makes a bad table a test failure rather than a
squashed mon for the rest of the battle.

**`AnimTask_DeepInhale`'s shiver is gated by a u16 UNDERFLOW.**
`var0 = data[0]; var0 -= 20; if (var0 < 23)` — on frames 0-19 the subtraction
wraps to ~65516 and fails, so the jitter runs only on frames 20-42. Read as a
signed comparison it shakes from frame zero, before the inhale has begun.

**`AnimJaggedMusicNote`'s offset is also its velocity.**
`data[3] = (args[1] << 3) / 8` is args[1] again, accumulated every frame — a
note spawned 29 px right also drifts right at 29/8 px per frame. One arg, two
jobs; read as a position only, every Uproar note hangs motionless.

**The rainbow is real, the allocation is not.** Upstream's two blend tasks
allocate and free GBA palette slots; Godot has no palette-bank surface, so
they are no-ops — but the colours still reach the notes, which read the
ported `gParticlesColorBlendTable` directly. Recorded at the stub per rule (9)
rather than left bare.

⚠️ **A vacuous guard, caught by injection.** The "cycle time 0 holds one
colour" check stepped 20 frames and compared once. With four colours in the
table, a note cycling *every* frame lands back on its starting colour at any
multiple of 4 — so it passed against a port that ignored the cycle arg
entirely. Now sampled every frame.

---

#### Batch 26 — everything that fades (+10: 715 -> 725, 7 behaviors)

The Moonlight set, the alpha ramps, and Sky Attack's bird.

**⚠️ THE SPOTLIGHT TRIO WAS DROPPED AT STEP 0, and that is the finding.**
`AnimSpotlight`, `AnimTask_CreateSpotlight` and `AnimTask_RemoveSpotlight`
are **WIN0/WIN1 hardware-window** effects: they write WININ/WINOUT/DISPCNT
and mark the sprite `ST_OAM_OBJ_WINDOW` so it acts as a **stencil**, not as
something drawn. Same surface as the already-deferred `AnimTask_FakeOut` and
`AnimTask_MoveTargetMementoShadow`. Deferred per rule (4) rather than
approximated; the three moves it gates are asserted to remain *unplayable*,
so a half-port cannot pass silently.

**`AnimMoon` uses ABSOLUTE screen coordinates.** Moonlight passes (120, 56) —
the middle of a 240-wide screen. Every other sprite in this port positions
relative to a mon, so the tempting read puts the moon on top of the attacker
instead of in the sky.

**The moon has no lifetime of its own.** It and the sparkles idle until
`AnimTask_MoonlightEndFade` sets `data[0]` on every sprite built from their
two templates — a cross-sprite kill, modelled as a mark on the node rather
than a timer. The kill is **state 1, after the 15-step whiteout completes**,
so the moon vanishes while the screen is already washed out; killing in state
0 makes it pop out in plain view and every "the moon dies" assertion still
passes.

**`AnimTask_AlphaFadeIn` moves its two coefficients ALTERNATELY.** `data[2]`
is a parity counter — odd ticks advance eva, even ticks evb — so a 0..16 ramp
takes **32 ticks, not 16**, and the two are never more than one step apart.
Moving them together halves the duration and changes the curve mid-blend.
16 ticks is the discriminating sample: half done under the real reading, fully
done under the wrong one.

**Sky Attack's bird does not stop at the target.** It is *created* at the
target, teleported to the attacker, and given velocity `(target - attacker)/12`
with nothing decrementing — it arrives on frame 12 and keeps going until it
leaves the screen. Stopping on arrival reads as landing rather than swooping
through.

`AnimScriptVM.set_blend_context` added so a behavior can drive the same
BLDALPHA state the `setalpha` opcode writes, rather than a private copy the
sprite host cannot see.

---

#### Batch 27 — Conversion and the Gen 1 long tail (+15: 725 -> 740, 11 behaviors)

**Two of the eleven are ALIASES.** `AnimGrassKnot` is a verbatim duplicate of
`AnimSuckerPunch` and `AnimForcePalm` of batch 24's `AnimGunkShotImpact` —
same bodies, same step functions, same args. Registered as aliases with
identity assertions, the same guard batch 24 put on the gunk-shot particles.
That is three duplicate pairs found across four batches; it is worth checking
for one before writing any new sprite behavior.

**`AnimConversion` is the first behavior that could not have worked before
batch 24.** It has no lifetime: it parks and polls `gBattleAnimArgs[7]`,
dying only when `AnimTask_ConversionAlphaBlend` writes `0xFFFF` there — and
`_load_args` used to clear arg 7 on every command, so the signal could never
survive the `createsprite` that follows it. Source carries a
`// TODO: gBattleAnimArgs[ARG_RET_ID]?` comment at both ends, the upstream
authors noticing the same channel. The signal is written **after** the 16-step
ramp completes, so the squares fade out with the blend rather than popping.

**⚠️ RAPID SPIN DEFERRED, and the name is the trap.**
`AnimTask_RapinSpinMonElevation` **never touches the mon sprite at all** — it
writes `gScanlineEffectRegBuffers` and hands `REG_BG1HOFS`/`REG_BG2HOFS` to a
per-scanline DMA. The "elevation" is a horizontal shear of the *background* in
a band around the mon. Same surface as the spotlight. `AnimRapidSpin` is
deferred *with* it rather than ported alone: every move needing the spin
sprite also needs the elevation, so porting it by itself would add code no
move can reach and no coverage test can exercise.

**`AnimTriAttackTriangle` has three beats and the middle one is easy to
miss.** It flickers on alternate frames for 30, then holds **solid** from 31
to 60 (`data[0] > 30` overrides the parity check rather than sitting beside
it), and only at frame 61 launches. A port that flickered throughout still
looks busy.

**`AnimSharpenSphere`'s blink PERIOD GROWS** — `data[1]` starts at 2 and
increments every second toggle, so it strobes fast then slows to a stop. A
fixed-rate blink never settles.

⚠️ **A CLAIM I INVENTED, CAUGHT BY MY OWN TEST.** The Sucker Punch test first
asserted the sprite "waves vertically", reasoning from the `Sin()` call in its
step function. It failed — and it was right to. **Both real call sites pass
amplitude ZERO** (`-18, 5, 40, 8, 160, 0`), so the sine term is inert in every
animation that reaches it and the sprite slides flat. The term is ported
anyway because a future caller could use it, and the test now pins both halves:
flat with the real args, moving with a synthetic amplitude, so the code is not
dead either. **Reading a `Sin()` call as "therefore it waves" is the mistake;
the args decide.**

---

**Injections.** 8 for batch 25, 8 for batch 26, 8 for batch 27 — every
headline claim broken and confirmed failing, then reverted. Regression after
all three: `m36a` 71/71, `m36b` 53/53, `m36c` 66/66, `m36e_background_asset`
24/24, `m36e_background_runtime` 30/30, `m36e3` 60/60,
`hit_effect_dispatch` 40/40.

### M36D batch 24 — COMPLETE 2026-07-31. A severed channel in the VM, a duplicate that needed no port, and a speed wearing a duration's clothes.

**+16 moves: 684 -> 700 of 932 (73.4% -> 75.1%)** — the largest single-batch
gain of the whole M36D arc. 338 -> 346 registered. Tier 1 closed at 70/70;
Tier 2 189/283 (66.8%); Tier 3 441/579 (76.2%).

**The batch is one family**: a thrown projectile plus the particle that
scatters where it lands, ported four pairs at a time — Hydro Cannon
(charge + beam), Acid (bubble + droplet), Gunk Shot (particles + impact),
Pay Day (throw + falling coin). Chosen over the higher-headcount
alternatives because the pairs share one mechanism story rather than being
four unrelated wins that happened to sum.

**THE FINDING, and it is a VM bug the batch only exposed by accident.**
Source's `Cmd_createsprite` writes **only the args the command supplies** —
`gBattleAnimArgs` is a persistent global that is never cleared between
commands. This port's `_load_args` opened with `args.fill(0)`. That reads as
hygiene and is not: it silently severed the one channel
`AnimTask_StartSinAnimTimer` uses.

That task runs for 100 frames adding 3 to `gBattleAnimArgs[7]` every frame,
and every sprite created *while it runs* reads that value as its phase seed.
**`_to_target_in_sin_wave` has read a permanently-zero seed since the day it
was ported**, so Flamethrower's 22 flames have been wobbling in lockstep
instead of forming a staggered stream. The task itself was registered as a
literal no-op, with a comment stating that nothing consumed it — true when
written, false ever since. Fixed in the VM (arg 7 now survives a short
command) and in the behavior (the timer is now a real counted task).

**DISCLOSED DIVERGENCE**: only arg 7 is carried, not all eight. Arg 7 is the
documented cross-command register — query tasks already write it for a
following `jumpargeq` — while args 0-6 have no cross-command consumer
anywhere in this port, and every behavior ported so far was written against
"an arg my command did not supply reads 0". Carrying all eight would change
those inputs with no reference call site asking for it.

**`AnimGunkShotParticles` needed no port at all.** It is a **verbatim
duplicate** of the already-ported `AnimToTargetInSinWave` — same body, same
step function, same `0xD200 / 30`, same `> 127` amplitude fold — differing
only in reading `gBattleAnimArgs[ARG_RET_ID]` where the original reads
`gBattleAnimArgs[7]`, and `ARG_RET_ID` **is** 7. Registered as an alias, with
a test asserting the two resolve to the same object so a later session cannot
"port" it into a second copy to keep in step.

**`AnimCoinThrow`'s arg 4 is a SPEED, not a duration.** It flows into
`InitAnimLinearTranslationWithSpeed`, which **overwrites** `data[0]` with
`(|dx| << 8) / data[0]` — the value is a divisor and the frame count falls
out of the distance. Pay Day passes **1152** (4.5 px/frame, ~26 frames). Read
as a duration that is a coin in flight for **nineteen seconds**. Nothing at
the call site distinguishes it from `AnimHydroCannonBeam`'s arg 4, which
*is* a real duration — both are `data[0] = gBattleAnimArgs[4]`. Both are
tested, side by side, for exactly that reason.

**`AnimAcidPoisonDroplet` has a dead arg, reproduced.**
`data[4] = sprite->y + sprite->data[0]` reads `data[0]` *after* it was
overwritten with arg 4, so the fall distance is the DURATION and arg 3 is
never read. Acid passes 15 and 55 for those two, so the difference is 40 px
of visible fall, not an academic one. Recorded in the running lists — do not
"fix" it to arg 3.

**Smaller ported details.** The acid bubble's arc amplitude is a hardcoded
**-30**, negative so it lifts above the chord and lands back on the target;
its arg 3 selects the alternate cel sequence when **zero**, inverted from
what the name suggests. The falling coin is **two bounces with halving
amplitude**, not one fall, drifting 0.5 px/frame *away* from the player's
side. Hydro Cannon's charge carries a real per-side **sub-priority** flip
(+2 player / -2 opponent) that this port has no surface for — recorded and
skipped rather than approximated with a z-index guess.

**`_packed_coord_flags` retired.** Batch 23 met this packed word on
`SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles` and left the decode
in a comment; `AnimHydroCannonBeam` is the second caller, so it is a function
now. Hydro Cannon's own **257** (`0x0101`) is exactly the value that hides
the bug: both fields set, indistinguishable from any other nonzero value
under a plain-int read.

⚠️ **A GUARD OF MINE SHIPPED VACUOUS AGAIN AND BOTH INJECTIONS PASSED IT.**
The end-to-end phase test spawned two flames twelve frames apart and compared
their deviation from the chord — but a flame's phase also advances with its
**own age**, so two sprites of different ages deviate differently whether or
not either ever received a seed. Identical shape to batch 23's lattice guard:
the assertion was true for a reason unrelated to the claim. Rewritten to hold
age constant and vary only the seed, routed **through** `_load_args` so the VM
fix is genuinely on the path under test. It now reports `25.85 vs 25.85`
under the injection — the two paths being the same *is* the failure.

**This is the second batch running where the vacuous guard was found by the
injection and not by review.** The standing rule holds and is worth
restating: injecting the plausible misreading is not a formality after the
tests pass, it is the only thing that distinguishes a guard from a decoration.

**Every headline claim was proven to catch its regression** — 8 injections,
each reverted after: VM clears all args (3 failures), timer inert (4), coin
arg 4 as duration, droplet using arg 3 (2), arc amplitude positive (2), coin
amplitude not decaying, coin drift unmirrored, packed flags as plain int,
impact ignoring arg 2.

**One further test bug, not a vacuity**: the Hydro Cannon test spawned the
charge and the beam onto one stage, and `_spawn` returns the layer's FIRST
`AnimSprite` child — so the beam's travel was measured on the charge, which
never moves. It reported "221 of 221 left", the failure a shared stage always
gives.

**Tests.** `m36d_batch_test` 675 -> **718/718**, eleven new test functions.
Regression: `m36a` 71/71, `m36b` 53/53, `m36c` 66/66, `m36e_background_asset`
24/24, `m36e_background_runtime` 30/30, `m36e3` 60/60,
`hit_effect_dispatch` 40/40 — all green, including after the VM change, which
touches every animation in the project.

### M36D batch 23 — COMPLETE 2026-07-30. A function whose name is the misreading, and two vacuous guards caught by injection.

**+7 moves: 677 -> 684 of 932 (72.6% -> 73.4%).** Five behaviors plus two
shared helpers, 333 -> 338 registered. Tier 1 closed at 70/70; Tier 2 186/283
(65.7%); Tier 3 428/579 (73.9%).

**Machinery retired first, per rule (1).** Two helpers now back the batch and
one earlier behavior:

- **`_anim_battler_from_arg`** — the reference's `LoadBattleAnimTarget`
  (`battle_anim_new.c:6330`). An arg holds an ANIM_* battler SELECTOR, not a
  battler, and **in singles both partner values collapse onto the primary**.
  Reading the arg as a slot index would aim a singles animation at a slot
  that is not on the field. All three sprite callbacks in this batch take
  their battler this way.
- **`_side_centre`** — `InitSpritePosTo{Attackers,Targets}Centre`. Batch 22's
  `CentredElectricity` open-coded this; it is now refactored onto the shared
  helper (behavior-preserving, its own tests unchanged and green).
- **`_make_sprite_named`** — `_make_sprite`'s twin for a TASK that names its
  own template in C rather than receiving one from the script's `createsprite`.

**THE FINDING: `SpriteCB_AnimSpriteOnTargetSideCentre` anchors on the
ATTACKER's side centre when the selected battler is an ALLY**, despite the
name. Taking the name literally — "centre of the target side" — puts every
ally-directed use on the wrong half of the screen, and it still looks like a
perfectly plausible effect there. Injecting the literal reading fails both
assertions; reverting restores 675/675.

**`SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles`'s arg 5 is TWO
fields packed in one word** — high byte selects the pic-offset mode, low byte
the Y coordinate type. Reading it as a plain int makes every nonzero value
select the same branch and silently loses one of the two. Both resolve to this
port's single battler centre, so neither is branched on; the decode is
recorded in the comment rather than shipped as a no-op `if`, so a later
session adding pic offsets has the packing already worked out. arg 2 is also
mirrored when the attacker is on the opposing side — upstream writes that back
into the shared `gBattleAnimArgs`, a real side-effect, reproduced here on the
local copy only.

**`AnimTask_ShockWaveLightning`** builds a vertical column of segments 32 px
apart marching DOWN to the target, one every 2 frames. The start point is
neither the target nor zero: upstream takes `target_y + 32` and subtracts 32
until the value drops to 16 or below, landing the first segment above the
screen **on the same lattice the rest of the column sits on**. Starting at the
target and walking up uses a different lattice and leaves a seam.

**`AnimTask_ShockWaveProgressingBolt`** crosses to the target in 5 columns,
each a vertical sweep of segments 8 px apart, with **consecutive columns
sweeping in opposite directions** — that alternation is what reads as a zigzag
rather than five identical strokes. Each segment also advances the sheet frame
by one (upstream nudges `oam.tileNum`), walking 7->0 or 0->7 and wrapping.

**TWO GUARDS SHIPPED VACUOUS AND WERE CAUGHT BY THEIR OWN INJECTION — rule (7)
in two more dresses.** Both passed against deliberately broken code:

1. The lattice check asserted only "starts above the screen" and "even
   spacing". **Any** downward march on any lattice satisfies both. Fixed by
   making it two-sided: the first segment must be at or above the 16 px line
   AND one step earlier must be off-lattice — i.e. it is the LAST such point.
2. The zigzag check scanned consecutive points globally, so the jump from one
   column's last segment (near the top) to the next column's first (at the
   bottom) registered as a downward sweep. **A bolt with no alternation at all
   reported a zigzag.** Fixed by grouping points into columns by x and
   measuring direction WITHIN a column, then asserting every consecutive pair
   alternates.

The lesson generalises past this batch: **a guard whose injection you had to
hand-pick is a guard you have not tested.** The first lattice injection
(`target_y - 3*gap`) happened to land on the correct lattice and passed
honestly; only a clearly-wrong start exposed the gap.

**One further test bug, not a vacuity**: the doubles-translate arrival check
stepped the full duration, but `_linear_travel` destroys on arrival WITHOUT
writing the final position (existing convention), so it read a freed node's
stale value. Rewritten to step to duration-1 and assert the sprite is far
nearer the selected battler than the default target.

**Tests.** `m36d_batch_test` 652 -> **675/675**, six new test functions. All
three headline guards proven to catch their regressions by injection.
Regression: `m36a` 71/71, `m36b` 53/53, `m36c` 66/66, `m36e_background_asset`
24/24, `m36e_background_runtime` 30/30, `m36e3` 60/60, `hit_effect_dispatch`
40/40 — all green.

### M36D batch 22 — COMPLETE 2026-07-30. A query behavior, and a halved divisor that reads like a full one.

**+7 moves: 670 -> 677 of 932 (71.9% -> 72.6%).** Four behaviors, 329 -> 333
registered. Tier 1 stays closed at 70/70; Tier 2 185/283 (65.4%); Tier 3
422/579 (72.9%).

**Ported.** `AnimTask_IsTargetSameSide` (a pure query, writing `gBattleAnimArgs[7]`);
`SpriteCB_MindBlownBall`; `SpriteCB_CentredElectricity`;
`AnimTask_CreateSmallSteelBeamOrbs`.

**Templates resolved by callback up front**, per rule (7), before any test was
written — `gBreakingSwipeCenteredElectricity`, `gMindBlownHeadTemplate`,
`gSteelBeamSmallOrbSpriteTemplate`.

**THE FINDING: MindBlownBall's phase-0 divisor is `arg0 << 1` while its
countdown is `arg0`, so the wind-up covers only HALF the way back to the
template's own spawn point.** Reading both as `arg0` — the obvious reading, and
the one every other two-phase behavior in this port actually uses — doubles the
retreat and still looks like a perfectly reasonable wind-up on screen. Nothing
about the animation would look broken; it would just be wrong.

That is also the one thing in this batch that is **only discriminable against
the template's own spawn point**, which the behavior overwrites on its first
line. The test therefore captures it directly with a bare `_make_sprite()` call
on a throwaway stage rather than inferring it from the attacker's position.
Proven non-vacuous by injecting the plain-`arg0` divisor: the guard reports
`515.2 of 515.2` and fails, and passes again on revert.

**`AnimTask_IsTargetSameSide` needs its POLARITY pinned, not just its presence.**
Both arms of the branching script animate, so a reversed polarity plays the
wrong animation rather than no animation — invisible to any "did it write
arg 7" check. Injecting the inversion fails both assertions.

**`SpriteCB_CentredElectricity`** anchors on the MIDPOINT of the two opposing
slots in doubles and on the target itself in singles; arg 3 selects one of three
genuinely different widths. Tested by building both formats and asserting the
two anchors differ, rather than asserting either in isolation.

**A vacuous assertion caught by its own failure, and the fix is the finding.**
The steel-orb spawner check asserted peak CONCURRENT sprites reached 15. Each
orb travels 80 frames and then destroys itself while a new one arrives every 7,
so no more than ~12 are ever alive at once — the check failed at "peak 12"
against a correct spawner. **Concurrency is not the quantity the claim is
about.** Rewritten to accumulate distinct instance IDs across the run, which is
what "the spawner stops at 15" actually means.

**Deferred: `AnimTask_MoveTargetMementoShadow`** — a WIN0/scanline screen-effect
gap, the same family as `AnimTask_FakeOut`, not an unread step function.

**Tests.** `m36d_batch_test` 637 -> **652/652**, six new test functions. Both
headline guards were proven to catch their own regressions by injection before
being trusted. Regression: `m36a` 71/71, `m36b` 53/53, `m36c` 66/66,
`m36e_background_asset` 24/24, `m36e_background_runtime` 30/30, `m36e3` 60/60,
`hit_effect_dispatch` 40/40 — all green.

### M36D batch 21 — COMPLETE 2026-07-30. A script signal, and a vacuous assertion caught by its own failure.

**4 behaviors, +5 moves (665 → 670 of 932, 71.4% → 71.9%).** Tier 3 71.7%;
iconic Gen 1-3 still closed at 70/70.

`AnimTask_SnatchOpposingMonMove` · `AnimTask_PurpleFlamesOnTarget` ·
`SpriteCB_SteelRoller` · `SpriteCB_FlippableSlash`.

⚠️ **`AnimTask_SnatchOpposingMonMove` SIGNALS THE SCRIPT by writing
`gBattleAnimArgs[7] = -1`** the moment the crossing look-alike passes the
target — the same arg-register protocol `AnimTask_SetPsychicBackground`
watches from the other end. **A port that reproduces every visible motion but
skips the write leaves any script polling arg 7 waiting forever, and looks
completely correct while doing it.** Proven by injecting exactly that: motion
identical, signal dropped, guard fails.

The behavior is a genuine five-state sequence — the attacker slides off its
OWN side, a look-alike enters from the FAR side and crosses, the look-alike
leaves, the attacker is teleported to the far edge and walks back in through
the side it left by. Getting any state's direction backwards still animates,
just nonsensically, so the suite checks the round trip and the exact restore.

⚠️ **`AnimTask_PurpleFlamesOnTarget`'s flames flip DRAW ORDER at the sine
midpoint.** Upstream computes `index = phase - 65` as UNSIGNED and puts the
flame behind the mon while `index < 127`, in front otherwise. That front/behind
swap is what makes the six read as ORBITING the Pokemon rather than sliding
across it — **and it is invisible to any assertion that only checks
position**, which is precisely the kind of detail a position-only test would
bless. Pinned by tracking one flame through both states.

**`SpriteCB_SteelRoller` hands itself to the left/right sweep batch 18 already
ported** — upstream literally assigns `SpriteCB_LeftRightSliceStep0` as its
callback, so this reuses the ported motion rather than restating it.

**`SpriteCB_FlippableSlash`'s two flips are INDEPENDENT args**, not a
side-derived mirror; a port that ties them to the battler's side loses the
per-call control the behavior exists to provide. All four combinations are
pinned.

**A VACUOUS ASSERTION, caught only because a neighbouring one failed.** The
test's first `_clone_count` counted "any TextureRect that is not an
AnimSprite" — which also counts the four BATTLER sprites, so it never reached
zero. "A look-alike crossed the screen" was therefore passing **trivially**,
and only "no look-alike is left behind" failed and exposed it.
`_clone_battler_visual` already tags its clones with a `_anim_trace` meta for
exactly this purpose — its own comment says *"only these should ever be
cleaned up"* — so the discriminator existed and I did not use it. **Fourth
distinct dress of the same defect** (batch 13's `if node != null:` skip, batch
15's no-op replace, batch 16's `is_inside_tree()`, now this).

Also of note: the Python patch that fixed it silently matched nothing on the
first attempt, and its own `assert` caught that — standing rule (8) working
rather than being rediscovered.

**Tests:** `m36d_batch_test` 621 → **637/637**. Regression green: `m36c`
66/66, `m36b` 53/53, `m36a` 71/71, `m36e_background_runtime` 30/30, `m36e3`
60/60, `m36e_background_asset` 24/24, `hit_effect_dispatch` 40/40.

### M36D batch 20 — COMPLETE 2026-07-30. Batch 18's deferrals, and a helper that was quietly wrong for one caller.

**3 behaviors, +5 moves (660 → 665 of 932, 70.8% → 71.4%).** Tier 2 65.4%,
Tier 3 70.8%; iconic Gen 1-3 still closed at 70/70.

`AnimTask_GlareEyeDots` · `AnimTask_DestinyBondWhiteShadow` ·
`AnimTask_AttackerFadeToInvisible`. The first two were batch 18's own
deferrals, back near the top of the ranking — the same pattern as batches 11,
17 and 19, which is what deferring them was for.

⚠️ **`_linear_travel` destroys its sprite on arrival, and that is wrong for
this caller.** `AnimDestinyBondWhiteShadow_Step` stops moving when its frame
count runs out and leaves the shadow STANDING on the foe for the rest of the
task. Reusing the existing helper made every shadow vanish the instant it
arrived — **found by this batch's own travel test, not by reading**. New
`_travel_and_hold` sits beside it; the distinction (does the sprite's own
motion end it, or does its owning task?) is worth having named, because the
two are indistinguishable in any test that only checks the destination.

**`AnimTask_GlareEyeDots` — three details a plausible port gets wrong:**

1. **The interpolation divisor is `pairMax - 1`, not `pairMax`.** With 12
   pairs the span is divided by ELEVEN. Using 12 shortens the whole trail so
   it never quite reaches the target — and looks entirely reasonable in
   motion. Proven by injecting the off-by-one (600.0 → 550.0 at the midpoint).
2. **The endpoints are special-cased, not interpolated** — pair 0 sits exactly
   on the start, pair ≥ pairMax exactly on the target.
3. **Dots come in diagonal PAIRS offset by ±3**, not singly.

**`AnimTask_DestinyBondWhiteShadow` spawns one shadow PER OPPOSING VISIBLE
battler** — skipping the attacker *and* the attacker's partner, and skipping
anything not currently visible. A "spawn one" port and a "spawn for every
slot" port are wrong in opposite directions, so the suite pins both: two
shadows in the default layout, one fewer when a foe is hidden. Its blend ramp
also moves eva and evb on **alternate** steps, so the fade takes twice as long
as moving both each step would.

**`AnimTask_AttackerFadeToInvisible` deliberately does NOT restore** — it ends
with the mon hidden and the paired script call fades it back. Routed through
the tracked visibility setter so a run ending there still leaves a usable
stage.

**Two small quality fixes to my own recent work**, neither behavioural:
a dead variable in the DestinyBond setup (read only by a no-op `if … pass`)
was removed rather than left with a comment excusing it; and the new divisor
assertion's label was reworded to name both the wanted and the wrong value,
after it first printed the same self-referential `"550.0, not 550.0"` that
batch 18's fall-through guard did.

**Template names were resolved by callback UP FRONT this time**, rather than
guessed and then caught — three consecutive batches of the guard firing was
enough evidence to change the order of work.

**Tests:** `m36d_batch_test` 605 → **621/621**. Regression green: `m36c`
66/66, `m36b` 53/53, `m36a` 71/71, `m36e_background_runtime` 30/30, `m36e3`
60/60, `m36e_background_asset` 24/24, `hit_effect_dispatch` 40/40.

### M36D batch 19 — COMPLETE 2026-07-30. A deferral reason that was wrong, and a guard narrowed then re-proved.

**1 behavior + 3 recovered background assets, +3 moves (657 → 660 of 932,
70.5% → 70.8%).** Tier 2 64.7%, Tier 3 70.3%.

⚠️ **CORRECTION TO BATCHES 17 AND 18.** Both recorded `AnimTask_ScaryFace` as
an ASSET gap — *"needs `gBattleAnimBgTilemap_ScaryFacePlayer`/`...Opponent`,
absent from M36E1's 84-background pull"*. **That reason was wrong.** The pull
script has always listed both, and the source `.bin` files have always been in
the tree. They were being **REFUSED by the pull's own two-palette-bank
correctness guard**, which printed the real reason on every run — I recorded
"absent" from an `ls` that found no output file, without ever running the
generator to ask why. *An empty output directory and a refused asset look
identical from the outside.*

**The refusal was over-strict, for a precise reason.** A tilemap is 32 cells
wide by up to 32 tall, but the GBA draws only **30x20** of it; the rest is
scroll margin. The authors parked filler cells out there in whatever bank was
convenient, so measuring the WHOLE map reports a bank span nothing on screen
exhibits:

| asset | whole map | visible region only | what the second bank is |
|---|---|---|---|
| `scary_face_player` | banks 1, 8 | **bank 8** | one filler row at y=20, directly below the screen |
| `scary_face_opponent` | banks 1, 8 | **bank 8** | same |
| `attract` | banks 0, 8 | **bank 8** | the x>=30 margin and y>=20 rows |

Measured across **every** tilemap in the tree: **none** is multi-bank inside
the visible region. So the guard was narrowed to what is actually drawn —
which changes what it *measures*, not what it *means*.

**Narrowing a detector demands proving it still detects, and here real data
cannot.** Since no asset can trip the narrowed guard any more, a synthetic
tilemap with genuine content in a second bank at an on-screen cell was
injected: it is still refused (`content spans 2 palette banks [3, 8] INSIDE
the visible region`) while the real file passes. Without that, the guard would
have been indistinguishable from a deleted one — the same vacuous-assertion
trap this project has now hit in three separate dresses.

**DISCLOSED:** the composite still covers the FULL map (the scroll margin is
load-bearing for the sliding-BG family), so an off-screen cell in another bank
is drawn with the visible bank's palette. That is only ever seen if a behavior
scrolls it into view. Confirmed non-scrolling for ScaryFace —
`AnimTask_ScaryFace_Step` holds BG1 X/Y at 0 and only blends. **NOT checked
for `attract`**, which currently has no consumer; stated rather than implied.

**`AnimTask_ScaryFace` itself** is a pure blend ramp: eva climbs 1..14 one
step every 2 frames, holds 21, unwinds the same way — 28 + 21 + 28 = 77
frames, peaking at **14/16, never fully opaque**. Its `case 3` also falls
through into `case 4`, explicitly commented upstream this time.

**The variant pick reads backwards** and is worth pinning: `onPlayer =
!IsOnPlayerSide(target)` selects the *Player* tilemap, so "Player" names the
viewpoint the face is aimed FROM, not the side it sits on. Wiring it the
intuitive way silently swaps the two on every use.

**Three naming misses in one batch, all the same shape.** `AnimData` and
`index.json` key backgrounds by **UPPERCASE BG NAME**, not by lowercase
filename — and `set_background()` returns `false` for an unknown name, so the
lowercase form makes the whole behavior a silent no-op. Caught once in the
asset test's own first draft and once in the behavior; both fixed by reading
the index rather than guessing. **The coverage report still counted the move
as playable throughout**, because it is a static registration walk — coverage
measures REACH, not that a behavior does anything.

**Tests:** `m36e_background_asset_test` 20 → **24/24** (the three recovered
assets pinned by name, plus a check that the two ScaryFace variants composite
to genuinely different images — if the variant pick were wired to the wrong
file nothing else would notice). `m36e3_bg_behaviors_test` 52 → **60/60**.
Regression green: `m36d` 605/605, `m36c` 66/66, `m36b` 53/53, `m36a` 71/71,
`m36e_background_runtime` 30/30, `hit_effect_dispatch` 40/40.

### M36D batch 18 — COMPLETE 2026-07-30. Past 70%, and a switch fall-through.

**6 behaviors, +7 moves (650 → 657 of 932, 69.7% → 70.5%).** Tier 2 64.3%,
Tier 3 69.9%; iconic Gen 1-3 still closed at 70/70.

**The curve has genuinely flattened** — no remaining pick is worth more than
+2 — so this batch went wider and shallower rather than chasing a headline.

`SpriteCB_PhotonGeyserBeam` · `SpriteCB_HorizontalSlice` ·
`SpriteCB_LeftRightSlice` · `AnimEyeSparkle` · `AnimLetterZ` ·
`AnimBatonPassPokeball`.

⚠️ **`AnimBatonPassPokeball`'s case 1 FALLS THROUGH into case 2** — upstream
has no `break` — so on every frame in state 1 BOTH blocks run: the x param
gains 96 **twice** (192/frame), the y param goes −26 then +48 (net +22), and
the step counter advances by **two**, making state 1 last 3 frames rather
than 5.

Reading the switch as if each case were exclusive gives half the horizontal
stretch and nearly twice the duration — and looks perfectly reasonable on
screen, which is why it needs pinning rather than eyeballing. Injecting that
misreading lands the scale on exactly **0.727** against the correct **0.571**,
failing the guard. The test label names both numbers so a future failure is
self-diagnosing.

It also mutates the ATTACKER's scale and then hides it — **two leak classes at
once**, both covered by existing restore nets. The hide is deliberate (the mon
has just been Baton Passed out) and the paired script call brings it back.

**`SpriteCB_HorizontalSlice` is distance-bound, not time-bound.** It
accumulates `speed` per frame until it has covered `distance`, so a FASTER
slice is a SHORTER one — a time-bound port inverts that relationship. Pinned
by running a fast and a slow slice side by side and asserting the fast one
finishes first.

**`SpriteCB_PhotonGeyserBeam` bails outright if the chosen target's sprite is
not visible** — a beam aimed at a semi-invulnerable or already-fainted battler
is not drawn at all, rather than drawn at an empty slot.

**`SpriteCB_LeftRightSlice` goes out AND back** across the same span; ending
on the far side would read as the blade simply leaving.

**DISCLOSED — `AnimLetterZ`'s exit test.** Upstream is
`(u16)(x + x2) > DISPLAY_WIDTH`, and that u16 cast means a Z drifting off the
LEFT edge wraps to a huge value and also exits. Ported as "off either
horizontal edge", which is what the cast *achieves* rather than what it
literally says.

**The template guard earned its keep for the third batch running**, catching
three guessed names at once. All resolved by **callback** from
`templates.json`, and two were nowhere near guessable:
`SpriteCB_HorizontalSlice` → `gSpriteTemplate_StoneAxeSlash`,
`SpriteCB_LeftRightSlice` → `gFishiousRendTeethTemplate`,
`SpriteCB_PhotonGeyserBeam` → `gPhotonGeyserBeam` (no `SpriteTemplate`
suffix at all).

**Deferred, and of three different kinds — worth distinguishing rather than
lumping:** `AnimTask_GlareEyeDots` (+2) and `AnimTask_DestinyBondWhiteShadow`
(+2) are multi-step task SPAWNERS whose setup was read but whose `_Step` tails
were not — **UNREAD, not unfindable**. `AnimTask_FakeOut` (+1) is a WIN0/BLDY
screen window-darken effect, closer to M36E's surface than to a sprite
behavior. `AnimTask_ScaryFace` (+2) remains an **asset** gap from batch 17.

**Tests:** `m36d_batch_test` 588 → **605/605**. Regression green: `m36c`
66/66, `m36b` 53/53, `m36a` 71/71, `m36e_background_runtime` 30/30, `m36e3`
52/52, `m36e_background_asset` 20/20, `hit_effect_dispatch` 40/40.

### M36D batch 17 — COMPLETE 2026-07-30. Batch 16's deferrals, and an affine reading that was wrong two ways at once.

**7 behaviors, +15 moves (635 → 650 of 932, 68.1% → 69.7%).** Tier 2 63.3%,
Tier 3 69.3%; iconic Gen 1-3 still closed at 70/70.

All four of batch 16's deferrals cleared, plus three one-away wins. The
deferrals were the top three picks on the board by yield (+6, +3, +2) — which
is exactly what deferring them was for.

`AnimTask_SquishTarget` · `AnimTask_SquishTargetShort` (free alongside) ·
`AnimTask_NightShadeClone` · `AnimBrickBreakWall` · `AnimRazorWindTornado` ·
`AnimMegahornHorn` · `AnimCrossChopHand`.

⚠️ **`AFFINEANIMCMD_FRAME`'s deltas are PER FRAME, not per command — and both
readings are plausible on paper.** Traced through `AffineAnimDelay` →
`ApplyAffineAnimFrameRelativeAndUpdateMatrix` (`sprite.c`), which re-applies
the delta on **every tick the delay counter runs down**, not once when the
command starts. So `FRAME(0, 64, 0, 16)` is **+1024**, not +64.

The difference is not subtle and is not cosmetic: 256/1280 = **0.2× height**
(a genuine flatten, matching the table's own `//Flatten` comment) against
256/320 = 0.8× (a barely-visible nudge). **I reasoned my way to the WRONG
answer first**, on the grounds that a "short" variant ought to be the same
squash played faster — under the per-frame reading `sSquishTargetShort` is
both quicker *and* shallower (4×64 = 0.5×), which felt wrong. Source settled
it against the intuition. The suite pins the depth AND the long-vs-short
difference, and both guards were proven by injecting the per-command
misreading: it produces exactly 0.800 and collapses the two tables to
identical depth, failing both.

**`AnimTask_NightShadeClone` is NOT batch 11's `_nightmare_clone`** — a
different function sharing only the word "clone". The ATTACKER ITSELF is
doubled in size and made fully transparent, fades in to 9/16 over 27 frames
(one blend step every 3), waits `arg0`, then shrinks back over 16 and
restores. It mutates scale AND blend on a battler, so it leans on two of the
VM's four restore nets at once.

**`AnimBrickBreakWall` has a real fork**, not a uniform shape: after its hold
it EITHER dies outright (`arg4 == 0`) or rattles ±2px every other frame for
`arg4` more — the wall shuddering before it breaks. A port that always shakes
would add motion to every caller that asked for none.

**`AnimMegahornHorn`'s mirroring is ASYMMETRIC.** Against a player-side target
both offsets flip on both axes; against an opponent-side target nothing flips
at all. A uniform "mirror by side" sends the horn the wrong way in half of all
uses, so the suite asserts the two sides produce genuinely opposite offsets.

**New shared helper: `_circle_orbit`**, extracted from
`TranslateSpriteInCircle` (`battle_anim_mons.c`) — `x2 = Sin(pos, amp)`,
`y2 = Cos(pos, amp)`, phase wrapping at 256. More than one behavior hands its
sprite straight to it.

**One test bug, mine:** the tornado orbit test sampled its reference point
BEFORE the first tick, but the spawn point is the orbit's CENTRE — the sprite
only reaches the orbit itself once the stepper runs (phase 0 puts it at
centre + (0, amplitude)). Fixed by sampling after one tick. The behavior was
correct throughout.

**DEFERRED — an ASSET gap, not an unread function.** `AnimTask_ScaryFace`
(+2) loads `gBattleAnimBgTilemap_ScaryFacePlayer`/`...Opponent`, neither of
which is among M36E1's 84 pulled backgrounds. Closing it means extending that
pull, not reading more C — a different kind of work from every other deferral
on the list, and recorded as such per standing rule (6).

**Tests:** `m36d_batch_test` 570 → **588/588**. Regression green: `m36c`
66/66, `m36b` 53/53, `m36a` 71/71, `m36e_background_runtime` 30/30, `m36e3`
52/52, `m36e_background_asset` 20/20, `hit_effect_dispatch` 40/40.

### M36D batch 16 — COMPLETE 2026-07-30. A second false alias, and four vacuous assertions.

**8 behaviors, +12 moves (623 → 635 of 932, 66.8% → 68.1%).** Iconic Gen 1-3
stays closed at 70/70; Tier 2 61.5%, Tier 3 67.5%.

`AnimTask_GetTimeOfDay` · `AnimViceGripPincer` · `AnimStompFoot` ·
`AnimBounceBallLand` · `AnimWeatherBallUp` · `AnimWhirlwindLine` ·
`AnimRockScatter` · `AnimGhostStatusSprite`.

**A SECOND "looks like an alias and is not", one batch after the first.**
`AnimViceGripPincer` (`battle_anim_effects_2.c:1839`) carries
`AnimGuillotinePincer`'s setup **byte for byte** — the same 32/−32 start
offsets, the same 16/−16 rest offsets, the same arg-0 mirroring, the same
6-frame converge. Its step is entirely different: Guillotine grinds in place
for 51 frames then retreats; ViceGrip arrives and dies. Batch 15's Petal Dance
pair taught this first, but there the setups merely *resembled* each other —
here they are identical, which is the sharper case. **Compare the step, not
the setup.** The suite asserts the two diverge, and that guard was proven
non-vacuous by aliasing ViceGrip to Guillotine (fails) and restoring (passes).

**`AnimBounceBallLand` is the REVEAL half** — Bounce's counterpart to Fly's
`AnimFlyBallAttack`. The ball drops onto the target, bounces straight back up
and reveals the attacker as it clears the top, routed through the tracked
visibility setter so a run ending mid-bounce still restores the Pokémon.

**`AnimTask_GetTimeOfDay`** reads the GBA's real-time clock upstream, so the
faithful port is the SYSTEM clock: 0 = day, 1 = night (≥20:00 or <04:00),
2 = evening (17:00–19:59). Boundaries reproduced exactly.

**`AnimWeatherBallUp`** rises while DECELERATING (velocity creeps from −40 back
toward −20), with an asymmetric drift — +5 player-side against −10
opponent-side, twice the distance the other way rather than a mirror — and
offsets scaled by TEN, not the usual 256.

⚠️ **TWO BUGS MY OWN TESTS FOUND, the second worth more than the batch.**

(1) *`AnimBounceBallLand` finished on frame 1.* Its exit test compared an
ABSOLUTE screen-y against a fixture-relative position, so whenever the target
sat above the −32px line the ball was already "off the top" before it moved.
Rewritten to compare against the ball's own starting offset — which is what
"off the top" means in source terms and does not depend on where the target
stands.

(2) **`is_inside_tree()` is ALWAYS FALSE in this fixture.** `FakeStage`'s layer
is deliberately detached, so every liveness assertion built on it was vacuous
in *both* directions: "has finished" passed trivially and "is still running"
could never pass at all. Four assertions across three tests were proving
nothing. Replaced with a shared `_b16_alive()` helper on
`is_queued_for_deletion()`, which flips the instant `finish()` runs.
**This is the same family as batch 13's `if node != null:` skip and batch 15's
no-op string replace: a check that cannot fail is indistinguishable from a
check that passes.**

The suite's own template guard again caught two guessed names
(`gBounceBallSpriteTemplate`, `gGhostStatusSpriteTemplate`) — both resolved by
**callback** from `templates.json` to `gBounceBallLandSpriteTemplate` and
`gCurseGhostSpriteTemplate`. Never by name-guessing.

**Deferred, and stated precisely per standing rule (6) — these are UNREAD step
functions, not failed searches:** `AnimTask_SquishTarget` (drives
`sSquishTargetAffineAnimCmds`, an affine table not yet read),
`AnimBrickBreakWall`, `AnimRazorWindTornado`, `AnimTask_NightShadeClone`.

**Tests:** `m36d_batch_test` 549 → **570/570**. Regression green: `m36c` 66/66,
`m36b` 53/53, `m36a` 71/71, `m36e_background_runtime` 30/30, `m36e3` 52/52,
`m36e_background_asset` 20/20, `hit_effect_dispatch` 40/40.

### M36D batch 15 deferrals — cleared same-day, and why they should not have been deferred

Coverage **615 -> 623 of 932 (66.8%)**; `m36d_batch_test` 536 -> **549/549**.
All four of batch 15's deferrals ported. **Nothing is currently deferred.**

WARNING: **three of the four were deferred for a bad reason, and it is the same
defect that produced batch 13's eight wrong template names: a grep pattern that
fails silently, read as evidence the code is hard.**

| Deferred as | Actually |
|---|---|
| `AnimStringWrap_Step` "not locatable in the expected file" | `battle_anim_bug.c:287`. The pattern required `static void`; it is declared plain `void`. |
| `SpriteCB_SpriteOnMonUntilAffineAnimEnds` — grep "found nothing" | `battle_anim_new.c:7934`, written `struct Sprite* sprite` with the asterisk on the TYPE. The pattern demanded `struct Sprite *sprite`. |
| The Dive pair — "a two-stage pair" | ~70 lines in total. "Two-stage" described the shape, not the size, and was allowed to imply cost. |

**Only `AnimFallingFeather` was ever genuinely hard** — and even that turned out
to be one block copy-pasted into four switch arms.

**The standing lesson: "grep found nothing" is a statement about the PATTERN,
not about the source.** Deferring is the right call for an unread step
function; it is the wrong call for an unsuccessful search, and the two are easy
to confuse because they produce the same empty terminal.

**What the four turned out to be:**

- **`AnimDiveBall` goes FURTHER than Fly's up-half.** It rises on the same 8.8
  accumulator, hides once clear of the screen top, waits 20 frames, and comes
  back DOWN, reappearing as it re-enters — one behavior covering the whole
  descend-and-return arc. Like Fly's ball it hides the attacker and never
  reveals it; the VM's visibility net is behind that, and the suite asserts it.
- **`AnimDiveWaterSplash` is a vertical SCALE pulse, not a moving sprite.** The
  affine y-parameter falls 40/frame for 12 frames then climbs back, and under
  the inverted rule a falling parameter STRETCHES — half height to roughly
  eight times it and back, anchored at its foot rather than its centre.
- **`SpriteCB_ToxicThreadWrap`** flickers on a 3-frame cycle for exactly 51
  frames. The flicker is the whole look; solid, it reads as a static sprite.
- **`SpriteCB_SpriteOnMonUntilAffineAnimEnds`** destroys itself outright if the
  battler is not visible rather than playing to an empty slot — so a script
  firing it at a Pokemon mid-Fly or mid-Dig draws nothing. Asserted both ways.

### M36D batch 15 — COMPLETE 2026-07-30

`m36d_batch_test` 520 -> **536/536**; 6-suite sweep green. Coverage
**595 -> 615 of 932 (66.0%)** — +20 from 8 behaviors, including four of batch
14's own deferrals now that their step functions have been read.

**A SIXTH alias**: `AnimGrowingShockWaveOrbOnTarget` is byte-identical to batch
8's `AnimGrowingShockWaveOrb` apart from which battler it anchors to. Shared
body, battler as a parameter.

⚠️ **And the opposite case, which matters more: a pair that LOOKS like an alias
and is not.** `AnimPetalDanceBigFlower` and `AnimPetalDanceSmallFlower` have
near-identical setups — both travel from the attacker down to
`attacker y + targetY`, both advance phase by 5 — which is exactly why batch 14
suspected them of being a pair. **Their steps are genuinely different, and the
difference IS the move:**

- **Big**: sways WIDE (amplitude 32) *and* bobs vertically (`Cos(phase, -5)`,
  note the negative), and swaps draw order in front of and behind the Pokemon
  on a half-cycle.
- **Small**: sways NARROW (amplitude 8), never bobs, and instead flips
  horizontally inside two tiny 5-unit phase windows (59-63 and 187-191).

Together that reads as heavy blossoms tumbling among light ones. Collapsing
them into one implementation would have lost the entire texture of the move —
the same instinct that correctly found six aliases would have been wrong here,
which is why each candidate pair gets its STEP compared and not just its setup.

**A trap deliberately avoided:** `SpriteCB_SunsteelStrikeRings` shares
`AnimFlyBallAttack_Step` with batch 9's Fly attack — but Fly's step also
performs an ATTACKER REVEAL driven by a `data[5]` field this behavior never
sets. Reusing `_fly_ball_attack` wholesale would have made Sunsteel Strike
quietly un-hide a Pokemon it never hid. Implemented separately; **the suite
asserts a hidden attacker STAYS hidden**, with a spawn guard so that assertion
cannot pass vacuously.

**Other shapes pinned:** `AnimWhiteHalo` is mostly HOLD — 90 frames of steady
glow then an eight-frame release, so a port that fades throughout reads as a
slow pulse instead. `AnimBrickBreakWallShard` sends four shards to four
DIAGONAL corners with the index selecting both tile and direction, and an
out-of-range index destroys the sprite outright rather than defaulting.
`AnimSmokeBallEscapeCloud` mirrors its offset by the **TARGET's** side while
spawning on the attacker — an asymmetry every neighbouring behavior does not
share.

**The batch-13 template guard earned its keep**: it caught
`gSunsteelStrikeRingsSpriteTemplate` (not a real name) the first time this
suite ran, before it could hide assertions. Resolved by callback, as the rule
requires.

**Screenshot-verified in-batch**: Petal Dance renders big and small flowers at
distinct sizes and heights.

**Deferred (4):** `AnimDiveBall`/`AnimDiveWaterSplash` (a two-stage pair),
`SpriteCB_ToxicThreadWrap` (hands to `AnimStringWrap_Step`, not locatable in
the expected file this pass), `SpriteCB_SpriteOnMonUntilAffineAnimEnds`.

### AnimFallingFeather — the last deferral, taken directly, 2026-07-30

`m36d_batch_test` 510 -> **520/520**; 6-suite sweep green. Coverage
**593 -> 595 of 932 (63.8%)**. **The M36D deferral list is now empty of
long-standing items.**

Deferred by batches 12, 13 and 14 as "247 lines of state machine over a packed
`FeatherDanceData` bitfield struct". That was accurate and, it turns out,
**misleading**: almost all of the length is the SAME twenty-line
flip-and-priority block copy-pasted into four `switch` arms, which differ only
in which neighbouring quadrant triggers a flip versus a bare pause. They
collapse into a single four-row table.

**Decoded, the mechanic is small and unusually well-designed. Three details
are what make it read as a falling feather rather than a swinging pendulum,
and a plausible-looking port drops all three:**

1. **It alternates between TWO sway amplitudes.** `unkC` is a two-byte array
   and the index is a flag toggled at ONE specific quadrant boundary, so
   consecutive swings are different widths and the descent never settles into
   a clean sine.
2. **Its tilt is derived from its own horizontal offset, not from time** —
   `sinIndex = (-x2 >> 1) + unkA`. The feather leans into its drift and levels
   out at the extremes, which is what sells "a flat object falling through
   air".
3. **The flip and the draw-order swap happen TOGETHER** — it mirrors
   horizontally and changes priority relative to the Pokemon in the same
   frame, so it turns over as it passes in front of or behind it.

All three are asserted directly, including that the flip count and the
draw-order-change count are EQUAL rather than merely both non-zero.

**A note that looks like a bug and is not:** the pause is one frame. `unk1`
starts at 0 and the test is `unk1-- % 256 == 0`, true immediately. It is a
beat between swings, not a hold.

⚠️ **And a test of mine that was wrong where the code was right.** A first
draft asserted the descent was at a flat constant rate; it failed at 16.00
against 14.40 over ten frames — which is exactly nine moving frames and one
paused one. Upstream a paused frame skips the ENTIRE motion block, so the
feather genuinely does not fall on the beat between swings. The assertion now
makes the precise claim: every frame's delta is either zero or the same
constant.

**DISCLOSED:** upstream reads `BATTLER_COORD_ATTR_HEIGHT`/`WIDTH` — sprite
DIMENSIONS — and uses them as screen coordinates for the spawn point. That is
almost certainly an upstream mix-up (every neighbouring behavior uses the
`_X_2`/`_Y_PIC_OFFSET` coordinate queries) and does not transfer to a stage
whose sprites are positioned by the scene. Spawned relative to the battler's
centre instead.

**Screenshot-verified**: Feather Dance renders feathers around the target at
visibly varied tilts, confirming detail 2 on screen.

### M36D batch 14 — COMPLETE 2026-07-30

`m36d_batch_test` 489 -> **510/510**; 7-suite sweep green. Coverage
**580 -> 593 of 932 (63.6%)**. 7 of 14 candidates; seven deferred.

**A FIFTH alias family, and the first that is a family rather than a pair.**
`AnimPsychoCut`, `AnimSonicBoomProjectile` and `AnimTealAlert` are all "spawn,
rotate to FACE the destination, travel there in a straight line" — differing
ONLY in a constant added to the computed angle (`0xC000` / `0xF000` /
`0x6000` in 1/65536 turns). Batch 12's `AnimPoisonJabProjectile` is the same
shape with a zero constant, so it was **rerouted through the shared helper**
rather than left as a fourth copy.

The constant is a **per-sheet rest-angle correction**, not a motion
difference: each sprite's artwork points a different way at rest. Getting it
wrong leaves the projectile travelling the correct path while flying sideways
— a defect that reads as an art bug rather than an animation one, which is
exactly why the suite demands the same geometry produce **four DISTINCT
rotations**.

⚠️ **That distinctness test immediately found a real fidelity gap of my own.**
The first cut applied the correction only when the travel delta was non-zero.
But `TealAlert` and `PoisonJab` genuinely spawn ON the target, so their delta
IS zero, and both came back unrotated — 3 distinct rotations out of 4. Source
adds the correction unconditionally (`ArcTan2Neg(0,0)` returns 0 and the
constant is still added), because it corrects the SHEET, not the path. Fixed:
the facing term is conditional, the correction never is.

**Shapes pinned:**

- **`AnimRedHeartProjectile` has NO duration argument** — a fixed 95 frames,
  unusually long for a projectile, which is what gives Attract its unhurried
  drift. It sways vertically on a sine as it goes.
- **`AnimHitSplatRandom` scatters in a deliberately ASYMMETRIC box** — ±24
  across but only ±12 down, so repeated hits spread ALONG the target rather
  than around it. Asserted over 40 samples.
- **`AnimSpiderWeb` holds 20 dead frames** at full opacity before fading, and
  then fades one step every OTHER frame, so the 16-step fade takes 32. ~52
  frames total, of which the first 20 are perfectly still.
- **`AnimTranslateWebThread`'s arg 2 is a SPEED, not a duration**
  (`InitAnimLinearTranslationWithSpeed`). Travel time therefore depends on
  distance, and a port that treats it as a frame count gets doubles pacing
  wrong where the per-slot distance differs. Asserted by requiring a farther
  target to take longer.

**Screenshot-verified in-batch** (the process change the screenshot pass
earned): Psycho Cut's charge spiral renders correctly over the attacker. The
crescent's own flight was not captured in the window used — partial, not full,
visual verification.

**Deferred (7):** `AnimFallingFeather` (247-line packed-struct step, now
deferred three times and genuinely wanting its own session),
`AnimPetalDanceBigFlower`/`SmallFlower` (near-identical setups but two unread
step functions determine the sway), `AnimDiveBall`, `AnimDiveWaterSplash`,
`AnimAcrobaticsSlashes`, `SpriteCB_ToxicThreadWrap`.

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
