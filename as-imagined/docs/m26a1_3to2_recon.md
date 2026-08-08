# 4:3 → 3:2 — decision document

**Recon only, nothing implemented.** Written 2026-08-07; **rewritten the same
day** because the first draft was a findings dump rather than a decision
document — it buried the question under discoveries, overstated the blast
radius, and closed with two contradictory recommendations.

Revisits **`[M26A1]` Base resolution change** (canvas set to 1024×768, 4:3).

---

## The question

The GBA is 240×160 — **3:2**. This project renders at 1024×768 — **4:3**.
M26A1 chose that deliberately and recorded why. Is that choice still right?

**Short answer: probably not, but one cheap check decides it, and that check
has not been done.** Everything below is arranged around that.

---

## 1. The core problem, stated once

4:3 forces an impossible choice on every GBA→canvas mapping, and **the codebase
has already made it twice, differently:**

| System | Mapping | Result at 1024×768 |
|---|---|---|
| **Weather** (`_weather_stage_scale`) | `Vector2(size.x/240, size.y/160)` — per-axis | `(4.267, 4.800)` → **fills the screen, distorts shape** |
| **Move animations** (`AnimStage.pixel_scale`) | `float(size.x/240)` — width only | `4.267` both axes → **preserves shape, falls 12.5% short vertically** |

Neither is wrong. **At 4:3 there is no right answer** — you either fill the
canvas and stretch the art, or keep the art true and leave a band unused. Two
subsystems reached opposite conclusions independently, and both are defensible.

**At 3:2 the question dissolves.** At 1200×800 both expressions evaluate to
exactly `(5.0, 5.0)`. One scale, no choice to make, no divergence to maintain.

This is the whole case. Everything else is consequence or cost.

---

## 2. Benefits — what 3:2 actually buys

**a. The two mappings converge.** No subsystem has to decide; no future one can
decide differently. This is worth more than the 12.5% itself, because the
inconsistency is invisible and self-propagating.

**b. Animation fidelity becomes achievable.** M36's bar is *1× GBA
frame-accurate*. Today it is met in time and violated in space, on every one of
779 playable moves, and **no test can see it** — the suites assert frame counts
and travel direction, which are correct. `m26_f1_recon.md` predicted this blind
spot in its own words: *"proves the port is faithful… does NOT prove a single
pixel ever reaches the screen."*

**c. Compensating constants disappear.** `BattleStage/Background` carries
`offset_top = -96` — a hand-tuned correction for a GBA-proportioned backdrop in
a 4:3 window, living in a scene file. It should be `0`.

**d. The overworld matches hardware exactly.**

```
now        1024×768 zoom 3  → 21.3 × 16.0 tiles
1200×800   zoom 5           → 15.0 × 10.0 tiles
GBA                          15.0 × 10.0 tiles
```

Today the player sees **42% more width and 60% more height** than the real
game. That changes how much of a map reads at once, how cutscenes frame, and
how close an encounter feels.

---

## 3. Costs — what it actually breaks

⚠️ **Smaller than the first draft claimed, and the correction matters** —
overstating this is what made the original recommendation unusable.

**a. The battle UI is anchor-based, so most of it survives untouched.**
`battle_screen_singles.tscn` carries **51 anchors against 38 offsets**; anchors
are proportional and resolution-independent. `m25h1_bottom_region_test` — the
only suite that genuinely asserts battle layout — checks
`anchor_top == 0.75` / `anchor_bottom == 0.95`, both of which **survive any
canvas change**.

**b. The "16 geometry-touching test suites" figure was wrong.** Most are false
positives: `damage_test`'s `1024`/`768` are fixed-point arithmetic
(`uq4_12_multiply(2048, 2048)`), not layout; the `m19_*` hits are the same.
**Real layout coverage is one suite.**

**c. Sprite placement is the genuine cost.** M26A1 records that sprites are
*"placed via a fixed-pixel-size box anchored at a single fraction point"* and
that the last canvas change needed *"real re-tuning, not just
re-verification."* Expect that again. This is hand-work, it is the bulk of the
effort, and it cannot be automated.

**d. Three screens use 512×384 art.** `item_select`, `switch_select`,
`summary` — nine assets (one of them, `bag_bg_female.png`, referenced zero
times). At 1200×800 those scale 2.34×, non-integer. Options: letterbox with
side bars, accept soft scaling, or re-author.

⚠️ **This is the one question I cannot answer and it changes the cost
materially:** are those three screens staying on Emerald UI Pack art, or moving
to real FRLG art like the rest of the UI already has? Everything else in
`assets/sprites/battle_ui/` is GBA-native small art (16×48, 32×16, 24×24,
8×16). If they were always going to be replaced, this cost is temporary.

**e. Overworld camera + border skirt.** Zoom constant changes; the skirt depth
was sized by measuring the visible region at the current canvas. ⚠️ The skirt
system is **not in `map_manager.gd` at HEAD** — see the note on commit
`8115a7f8`. Whoever re-lands it should size it against the final canvas.

**f. Window size.** 1200×800 is larger than today, so nothing reads as a
downgrade. 960×640 would.

---

## 4. Cost of doing nothing

Not zero, and worth stating because "stay" is the default:

- Every future move animation inherits the 12.5% compression.
- The two-mapping divergence persists and will keep generating "why does this
  look slightly off" investigations that cost a session each to trace. **This
  document is one of them.**
- Compensating constants keep accruing. `-96` is one; there is no mechanism
  preventing the next.
- M36's stated fidelity bar stays unmeetable in one axis, permanently.

---

## 5. What I verified, and what I did not

**Verified by measurement:** the two scale expressions and their values; the
node z-order producing the Blizzard symptom (`MessageBackdrop` at index 6 over
the anim layer at index 1); anchor-vs-offset counts; the 512×384 asset census
(148 in tree, 9 adopted, 1 unused); tile-visibility maths; that
`m25h1_bottom_region_test` asserts anchors, not pixels.

⚠️ **NOT verified — and the first draft asserted one of these as fact:**

1. **Whether the 12.5% is visible.** I proved the maths is anisotropic. I did
   **not** show that any animation looks wrong. This is the crux.
2. **Whether the message box should end at 95% or 100%.** v1 claimed source
   leaves a 5% strip below the box and that ours wrongly fills it. That was
   inferred from `sStandardBattleWindowTemplates` (`B_WIN_MSG` =
   `tilemapTop=15, height=4` → y=120…152 of 160), **not checked against how
   FRLG actually renders**. `ActionRegion` correctly anchors 0.75/0.95;
   `MessageBackdrop` is a separate full-bleed ColorRect to 100% and may well be
   deliberate. **Do not act on v1's claim.**
3. **`window/stretch/aspect` is absent from `project.godot`** though M26A1
   records choosing `"keep"`. Intent and config disagree — worth resolving on
   its own merits, independent of this decision.

---

## 6. Recommendation

**Spend one hour before spending anything else.**

**Step 1 — settle the crux (~1 hour).** Capture one long-vertical-travel move
densely (`--gap=1`) — Sky Attack, Bounce, Fly, or Dig's re-emergence — and
compare against reference footage. These are the moves where a 12.5% shortfall
is largest in absolute terms.

- **If it is visible → go to 3:2 at 1200×800.** The benefit is systemic and the
  blast radius is one test suite plus sprite re-tuning.
- **If it is not visible → stay at 4:3**, and instead make `pixel_scale` match
  weather's per-axis form so the two subsystems at least agree. Cheap, removes
  the divergence, keeps the canvas.

**Why 1200×800** if it goes ahead: it was M26A1's own original plan; it is
exactly 5× GBA; it is larger than today so nothing reads as a downgrade; and
zoom 5 gives the GBA-exact overworld viewport that 960×640 only reaches at
zoom 4.

**Do independently of this decision, now:** resolve the `stretch/aspect`
discrepancy (§5.3). It is a config bug either way.

---

## 7. If it goes ahead — phased plan

Sequenced as M26A1 itself was: canvas first, then re-tune what was measured
against it.

| Phase | Work | Cost | Risk |
|---|---|---|---|
| **1** | Canvas → 1200×800; `aspect` explicit; verify `pixel_scale` uniform; remove `offset_top = -96` | ~0.5 session | Low — mechanical |
| **2** | **Battle sprite / health-box / message-region re-tuning** | **~1.5 sessions** | **High — hand-work, no automation, M26A1 warns of exactly this** |
| **3** | The three 512×384 screens: letterbox or re-author | 0.5–1.5 sessions | Depends entirely on §3.d |
| **4** | Overworld camera zoom; size the skirt against the new canvas when re-landed | ~0.5 session | Medium — interacts with unlanded work |
| **5** | Re-verify `m25h1_bottom_region_test`; sweep the rest | ~0.5 session | Low |

**Total: 2.5–4.5 sessions**, dominated by Phase 2. **Do not start mid-milestone
— Phase 1 leaves the project visibly wrong until Phase 2 completes.**

---

## 8. Bottom line

The 4:3 canvas made the project choose between two wrong answers on every
GBA→canvas mapping, and it has already chosen both. 3:2 removes the choice.

**But the honest counter-argument stands:** nothing a player has complained
about is broken, 779 animations shipped at this canvas, and 12.5% vertical
compression may be genuinely imperceptible. **One hour of dense capture against
reference footage decides it.** Everything in §7 is contingent on that hour,
and spending it is the only recommendation this document makes without
qualification.
