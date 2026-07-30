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
