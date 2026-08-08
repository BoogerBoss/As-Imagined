# 3:2 conversion — action plan

**Rob committed to 3:2 on 2026-08-07.** The reasoning, costs and alternatives
are in `docs/m26a1_3to2_recon.md`; this is the plan, not the argument.

**Target canvas: 1200×800** — exactly **5× the GBA's 240×160**, larger than
today so nothing reads as a downgrade, and M26A1's own original choice before
it was revised to 4:3.

⚠️ **This supersedes `[M26A1]`'s canvas decision.** M26A1's *reasoning* stays
valid and is not being called wrong — its premise (integer-scaling the Emerald
UI Pack's 512×384 screens) has simply narrowed to three screens. See the recon
§3.

---

## The one thing that makes this cheap

**Source defines exact battler screen coordinates.** `sBattlerCoords`
(`src/battle_anim_mons.c:37`):

```c
[BATTLE_COORDS_SINGLES] = {
    [B_POSITION_PLAYER_LEFT]    = { 72, 80 },
    [B_POSITION_OPPONENT_LEFT]  = { 176, 40 },
    ...
[BATTLE_COORDS_DOUBLES] = {
    [B_POSITION_PLAYER_LEFT]    = { 32, 80 },
    [B_POSITION_OPPONENT_LEFT]  = { 200, 40 },
    [B_POSITION_PLAYER_RIGHT]   = { 90, 84 },
    [B_POSITION_OPPONENT_RIGHT] = { 152, 32 },
};
```

At uniform 5× these are **arithmetic, not judgement**: player (360, 400),
opponent (880, 200). The recon costed Phase 2 as ~1.5 sessions of hand-tuning
because M26A1 warned of exactly that. **With this table it becomes derivation
plus screenshot verification.**

⚠️ **But it exposes a real decision.** Current placement, measured live, is not
where source puts things:

| | current (frac) | source (frac) | delta |
|---|---|---|---|
| player | (0.186, 0.617) | (0.300, 0.500) | **x −0.114, y +0.117** |
| opponent | (0.715, 0.201) | (0.733, 0.250) | x −0.018, y −0.049 |

The **opponent is close**; the **player is substantially left and low** of
source. That is not aspect drift — it is composition, tuned by eye across two
prior canvas changes (16:9 → 4:3). See **Decision 1**.

---

## Open decisions — needed before Phase 2 and Phase 3

**Decision 1 — RESOLVED 2026-08-07: adopt.** Rob: *"almost no UI elements are
implemented correctly yet, so we will be reimplementing them all."* Preserving
a composition that is going to be redone has no value, which makes this the
recommended option on cost as well as fidelity. Original framing kept below.

**Decision 1 — battler placement: adopt `sBattlerCoords`, or preserve the
current composition?**

- **Adopt (recommended).** Cheaper (derived, not tuned), strictly more
  faithful, and makes every future canvas change arithmetic. ⚠️ **The player
  sprite moves visibly** — right and up. Sprites here are much larger relative
  to the canvas than the GBA's 64×64, so source's coordinates may crowd the
  message region; verify by screenshot before committing.
- **Preserve.** Keeps the look you have. Costs the hand-tuning the recon
  warned about, and re-tunes against nothing authoritative.

**Decision 2 — the three 512×384 screens** (`item_select`, `switch_select`,
`summary`): letterbox with side bars, accept 2.34× soft scaling, or re-author
at 3:2? Cost of Phase 3 swings 0.5 → 1.5 sessions on this. If they are headed
for real FRLG art anyway, letterbox now and re-author when that happens.

---

## Phase 0 — instrument first (~0.5 session)

**Nothing changes visually. This is what makes every later phase verifiable.**

| | |
|---|---|
| **Do** | Extend `m36_screenshot_harness` with a `--layout` mode that dumps every battler/panel/region rect as fractions of the canvas. Capture a **baseline set** at 1024×768: 6–8 moves plus an idle frame, singles and doubles. |
| **Files** | `scenes/battle/m36_screenshot_harness.gd` |
| **Done when** | A single command produces before/after fraction tables and a PNG set, so Phase 2 is diffable rather than eyeballed. |
| **Do NOT** | Change any geometry yet. |
| **Status** | ✅ **Done 2026-08-07.** `--layout` and `--doubles` landed; singles + doubles baselines captured. It found two things on its first run — below. |

**What Phase 0 caught before Phase 1 touched anything** — both were invisible
to the ordinary test sweep, which is the entire argument for instrumenting
first:

1. **`m25h1_bottom_region_test` was red at 40/41 and nobody knew.** The suite
   asserted `ActionRegion.anchor_bottom == 0.95` (source's `B_WIN_MSG`
   proportion) while the scene had carried `1.0` since `02bc4926` ("Polished
   lower battle text field") deliberately changed it. **Rob's call: return to
   0.95, and start from reference where possible.**

   So the fix went further than the one anchor. `B_WIN_MSG` defines all four
   edges (`tilemapLeft=2, tilemapTop=15, width=26, height=4` of a 30×20-tile
   screen), and the region now carries **all four as anchors with every offset
   zero** — `0.0667 / 0.75 / 0.9333 / 0.95`. Both prior geometries mixed
   anchors with hand-tuned pixel offsets (`14/18/-18/18`, then `5/2/-5/-1`);
   ⚠️ **neither offset set was reference-derived** — the older one is not more
   faithful for being older.

   ⚠️ **This makes Phase 2's message-region derivation already done, and
   canvas-proof.** Proportional anchors survive the aspect change with no edit,
   which is the same argument as Phase 1's `pixel_scale()` rewrite: a constant
   tuned against one canvas is a latent bug on the next, and this project has
   now changed canvas twice.

   ⚠️ **The wider finding: the battle suites are not in the routine sweep.**
   This session's work swept the 23 overworld suites only; 224 exist. Phase 5's
   full sweep is not a formality.

2. **`PartyStatusPlayer` and `PartyStatusOpponent` both report `(0,0)` /
   `216×30`** — identical rects at the canvas origin, in singles *and* doubles.
   Either they are inert at capture time or one is genuinely mispositioned.
   ⚠️ **Resolve before Phase 2**, or the conversion faithfully preserves a bug
   into the new canvas and it becomes much harder to attribute afterwards.

⚠️ Without this, Phase 2's acceptance is "looks right to me," which is exactly
how the current placement drifted from source in the first place.

---

## Phase 1 — the canvas (~0.5 session)

| | |
|---|---|
| **Do** | `project.godot`: `viewport_width=1200`, `viewport_height=800`. Add `window/stretch/aspect="keep"` **explicitly** — it is absent today though M26A1 records choosing it (recon §5.3). Remove `BattleStage/Background`'s `offset_top = -96` / `offset_bottom = -96`. **Make `AnimStage.pixel_scale()` per-axis (`Vector2`) outright**, matching `_weather_stage_scale()`'s form. |
| **Files** | `project.godot`, `battle_screen_singles.tscn`, `battle_screen_doubles.tscn` |
| **Done when** | Project boots at 1200×800; both expressions return `(5.0, 5.0)` **by construction, not by coincidence**. |
| **Do NOT** | Touch sprite placement, UI screens, or the overworld. |
| **Status** | ✅ **Done 2026-08-07.** Canvas 1200×800, `aspect="keep"` explicit, both `-96` pairs removed. Scoreboard reads `anim=5.0000  weather=(5.0000, 5.0000)`. |

⚠️ **THE `pixel_scale()` REWRITE WAS DROPPED, AND THIS ENTRY IS THE RECORD OF
WHY — DO NOT REINSTATE IT.** I proposed making it per-axis to match weather.
Reading the code killed that: `pixel_scale()` has exactly ONE production
consumer (`AnimBehaviors._scale`), and it scales **animation offsets**. A
uniform float keeps a diagonal offset at 45° and a circular orbit circular;
per-axis would skew both, on 779 move animations. Weather fills the screen so
per-axis is right *there*; animations preserve shape so a float is right
*here*. **The recon said "neither is wrong" and I had misread it as "one needs
fixing."**

What replaced it is an invariant on the real hazard — the canvas silently
ceasing to be a uniform GBA multiple — pinned in
`m26a1_battler_geometry_test`. Set a non-3:2 resolution and it fails loudly,
forcing a re-decision instead of a silent 12.5% squash.

⚠️ **The project is visibly wrong at the end of this phase and stays wrong
until Phase 2.** Do not start unless Phases 1–2 can land together.

---

## Phase 2 — battler geometry (~1 session with Decision 1 = adopt)

| | |
|---|---|
| **Do** | Replace point-anchor + pixel-offset placement with positions derived from `sBattlerCoords × 5`. Generate the table rather than transcribing it — same discipline as `metatile_behavior.gd` and `movement_types.gd`. Re-derive health-box and message-region geometry from `sStandardBattleWindowTemplates`. |
| **Files** | `battle_screen_singles.tscn`, `battle_screen_doubles.tscn`, `battle_screen_shared.gd` |
| **Done when** | Every battler sits within 1px of `sBattlerCoords × 5`; `m25h1_bottom_region_test` green **unmodified** (it asserts all four `B_WIN_MSG` anchors AND that every offset is zero — all resolution-independent, so a canvas change cannot move them; if it goes red, geometry was converted to pixels somewhere and that is the finding); Phase 0's capture set reshot and compared. |
| **Do NOT** | Re-tune by eye. If a derived position looks wrong, that is a finding to record, not a number to nudge. |
| **Status** | ✅ **Done 2026-08-07**, via `scripts/gen_battler_coords.py` — generated, not transcribed. |

⚠️ **A REAL REGRESSION PHASE 2 CAUSED, CAUGHT BY AN EXISTING SUITE.** Moving
the battlers broke all 8 of `m26_trainer_category_party_test`'s trainer-sprite
assertions: a trainer portrait **shares its battler's box** — it stands where
the battler will stand — and I had moved only the battler. The generator now
places both from the same parse, so the pairing is guaranteed rather than
remembered.

⚠️ **The six boxes were 312, 292 and 131 px before this, none derived from
anything.** All are now 320×320 — 5× the GBA's own 64×64. **The doubles
battlers therefore grow ~2.4×**, which is the single most likely thing to read
wrong on screen, and is also exactly source's proportion (four 64×64 sprites on
240×160). Screenshot call for Rob.

⚠️ **Sprites are ~4.8× the GBA's 64×64 relative to the canvas.** Source's
coordinates assume GBA-sized sprites; at this scale they may overlap the
message region. If so, the honest fix is a documented, uniform inset applied
to the whole table — not per-sprite fudging.

---

## Phase 3 — the 512×384 screens (0.5–1.5 sessions, per Decision 2)

| | |
|---|---|
| **Do** | Whichever Decision 2 selects, for `item_select_screen`, `switch_select_screen`, `summary_screen`. Delete `bag_bg_female.png` — **zero references**, confirmed. |
| **Done when** | All three render without stretching artefacts; their suites green. |
| **Do NOT** | Non-uniformly stretch 4:3 art to fill 3:2. Letterboxing is honest; distortion is not. |

---

## Phase 4 — overworld (~0.5 session)

| | |
|---|---|
| **Do** | Camera zoom 3 → **5**, giving exactly **15×10 tiles — the GBA viewport** (today: 21.3×16). Re-measure border-skirt depth against the new visible region. |
| **Files** | `scenes/overworld/overworld.gd:613`, `map_manager.gd` |
| **Done when** | Visible region is 15×10; no void at map edges; the 23 overworld suites green. |
| **Status** | ✅ **Done 2026-08-07.** `CAMERA_ZOOM = 5`; visible region is exactly **15×10 tiles**. |

⚠️ **THE STATED BLOCKER WAS WRONG, AND THE CORRECTION MATTERS.** This row read
*"blocked on the skirt system not being in `map_manager.gd` at HEAD — re-land
it first."* The skirt is indeed absent (zero matches; the file is 1283 lines,
last touched by `8115a7f8`), **but it was not lost.** That commit's own `git
notes` records the 542 deletions it swept as *"Rob's and… intended; only their
attribution is wrong"* — the mistake was mine, in committing them under my
message, not in their existence. `m27a_step_resolver_test` agrees: it reports
500/500, not 514/514, because its 13 skirt assertions went with the
implementation.

So there was nothing to re-land, and **Phase 4 improves the situation rather
than depending on it**: zoom 5 shows 15×10 tiles where zoom 3 showed 21.3×16,
so *less* void is exposed at an unskirted map edge, not more. The old **12×9
depth is moot** rather than merely stale — there is no skirt to size.

⚠️ **Still open, and Rob's call, not this plan's:** whether a border skirt
returns and in what form. Walking to a map edge shows void today. That is
pre-existing and unchanged by Phase 4.

⚠️ **A COUPLED CONSTANT THE PLAN NEVER NAMED, AND PHASE 4 WOULD HAVE SHIPPED
IT BROKEN.** `TiledWeatherOverlay.TILE_SCALE` was `3.0`, carrying the comment
*"matches overworld.gd's own fixed `_camera.zoom`"* — a hand-kept duplicate,
unavoidable because `overworld.gd` has no `class_name` for that class to read.
Left at 3 it would draw every weather tile at 3/5 size with visible gaps
between them, which is the exact failure that file's own header warns about.
Found by grepping for consumers of the zoom, **not** by reading the plan.
Both are now 5 and `m27n_weather_test` pins them equal, so the duplication is
CHECKED rather than commented — the same fix `check_bake_diff` needed after
two hand-kept copies of one rule drifted and produced a false positive.

⚠️ **Cutting the visible area by ~50% is a real gameplay change**, not just a
render change. Encounter pacing, how much of a map reads at once, and cutscene
framing all shift. That is the *point* — but play the corridor before signing
it off.

---

## Phase 5 — verification (~0.5 session)

| | |
|---|---|
| **Do** | Full sweep: 23 overworld + the battle suites. Re-run `m36_coverage_report`. Re-shoot Phase 0's capture set and diff. Play the Route 22 rival chain end to end (`m27g_integration_test` covers it headlessly). |
| **Done when** | All suites green; capture diff shows only intended changes; one real playthrough of the corridor. |

---

## Total

**2.5–4 sessions.** Phase 2 dropped from the recon's ~1.5 to ~1 because
`sBattlerCoords` makes it derivation rather than hand-work — **provided
Decision 1 is "adopt."** If it is "preserve," Phase 2 returns to ~1.5 sessions
of tuning against no authority.

---

## Risks

| Risk | Mitigation |
|---|---|
| **Phases 1–2 split across sessions leaves the game visibly broken** | Land them together or not at all. |
| Source coordinates crowd the message region at this sprite scale | Phase 0's baseline makes it visible immediately; fix with a uniform documented inset, never per-sprite. |
| Phase 4 blocked on unlanded skirt work | Sequence after it; do not reconstruct from the old 12×9. |
| Something outside the 16 flagged suites depends on 1024/768 | Full sweep in Phase 5; **224 suites exist** and only the overworld 23 were swept during this session's work. |
| Scope creep into "while we're here" retuning | Every phase has an explicit **Do NOT**. |

---

## Explicitly not in this plan

- ~~The message-box 75%/95%-vs-100% question.~~ ✅ **Settled 2026-08-07 — the
  region is back on source's proportion, and on all four edges.** ⚠️ Worth
  keeping the shape of how it settled: the recon refused to act on the claim
  because it was unverified, and that was right — the evidence turned out to
  be a *deliberate* authored change, not the bug v1 asserted. It then took
  Rob's call, not the evidence, to decide which way to go. **Evidence settled
  what was true; it could not settle what was wanted.**
- Any move-animation re-authoring. 3:2 fixes the *mapping*; whether a given
  animation reads well is M36's own question.
- ~~The `AnimStage.pixel_scale()` per-axis rewrite.~~ ❌ **Dropped outright —
  it was never a bug.** This entry first said "unnecessary", then I moved it
  into Phase 1 as a prevention measure, then reading the code showed the
  rewrite would have *introduced* a defect. See Phase 1's ⚠️ block. The
  invariant that replaced it lives in `m26a1_battler_geometry_test`.
