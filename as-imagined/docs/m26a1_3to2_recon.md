# Returning to 3:2 — recon and scope

**Recon only. Nothing implemented.** Written 2026-08-07, prompted by a real
symptom: Blizzard's ported background "doesn't fill the whole screen."

Revisits **`[M26A1]` Base resolution change**, which set the canvas to
**1024×768 (4:3)**. That decision is recorded in
`docs/status/m26-build-log.md` and is not being second-guessed on its own
terms — the question is whether its premise still holds.

---

## 0. TL;DR

1. **The Blizzard symptom is real but is NOT the bug it looks like.** The
   background does fill the screen; `MessageBackdrop` is drawn on top of its
   bottom quarter. §1.
2. ⚠️ **A much larger finding fell out of investigating it: every ported
   animation is vertically compressed by 12.5%, systemically, and no test can
   see it.** `AnimStage.pixel_scale()` derives ONE scale factor from WIDTH
   only. At 4:3 the vertical relationship differs from the horizontal, so GBA
   y-offsets land 12.5% short. At 3:2 the two are identical by construction and
   the whole class of error disappears. §2. **This is the strongest argument
   for 3:2 and it was not known when M26A1 was decided.**
3. **M26A1's premise has eroded.** It chose 4:3 to integer-scale the Emerald
   UI Pack's 512×384 screens. **Nine such assets are actually adopted**, used by
   three screens; every other piece of adopted battle UI art is GBA-native. §3.
4. **The overworld gets a clean win**: 960×640 at zoom 4 shows **exactly
   15×10 tiles — the GBA's own viewport**. Today it shows 21.3×16. §4.
5. **Recommendation: yes, but not yet, and not as one move.** §7.

---

## 1. The Blizzard symptom, resolved

Measured at runtime through `m36_screenshot_harness`, not inferred:

| Node | Index | Vertical extent |
|---|---:|---|
| `Background` (battle backdrop) | 0 | −96 … 672 (**−12% … 88%**) |
| anim bg layer (`AnimBgLayer`) | 1 | full rect, 0 … 768 |
| `MessageBackdrop` | 6 | 576 … 768 (**75% … 100%**) |
| `EffectLayer` | 9 | 0 … 768 |

`BattleStage` is `(0,0) 1024×768`. `anim_stage.gd` inserts the background with
`move_child(node, 1)` — *"directly above the battle backdrop, below everything
else."* `MessageBackdrop` is a sibling at index 6, so it paints over the bottom
quarter opaquely.

**On hardware this is faithful.** The text window is a BG layer above the
animation layers; the animation genuinely does not show through it.

⚠️ **What is NOT faithful is where the box ENDS.** `[M25h-1]` derived the real
proportion from `sStandardBattleWindowTemplates[]`: `B_WIN_MSG` is
`tilemapTop=15, height=4` → **y=120…152 of 160 = 75%…95%**. Ours runs
**75%…100%**. Source leaves a 5% strip of battle scene *below* the box; we
extend the backdrop to the screen bottom and lose it. That missing strip is
what makes the box read as a wall terminating the scene rather than a window
sitting in it.

**This is a genuine, small, independent bug.** It is worth fixing whatever
happens to the aspect ratio, and it is ~1 line. It is not caused by 4:3.

---

## 2. ⚠️ The finding that actually matters: animations are 12.5% short vertically

`scripts/battle/anim/anim_stage.gd`:

```gdscript
const GBA_SCREEN_WIDTH := 240.0

func pixel_scale() -> float:
    var l := layer()
    if l == null or l.size.x <= 0.0:
        return 1.0
    return maxf(1.0, l.size.x / GBA_SCREEN_WIDTH)
```

**One scale factor, derived from width, applied to both axes.**

```
GBA 240×160 → 1024×768
  horizontal: 1024 / 240 = 4.2667   ← what pixel_scale() returns
  vertical:    768 / 160 = 4.8000   ← what the screen actually is
  vertical is 12.5% larger than the scale animations use
```

Every ported y-offset — every arc, rise, fall, screen-edge exit, every
`_linear_travel` destination — is multiplied by 4.2667 into a space that is
4.8× tall. A GBA animation crossing its full screen height covers **89%** of
ours.

**Why no test caught it, and this is the important part:** M36's suites assert
about *maths* — frame counts, travel direction, restoration. Those are all
correct. The port faithfully reproduces GBA offsets; it is the mapping onto the
canvas that is anisotropic. `docs/m26_f1_recon.md`'s own framing predicted
exactly this blind spot: *"That proves the port is faithful to the reference;
it does NOT prove a single pixel ever reaches the screen."*

**At 3:2 the two factors are identical:**

| Candidate | h scale | v scale | |
|---|---|---|---|
| 1024×768 (current) | 4.2667 | 4.8000 | **mismatch** |
| 960×640 | 4.000 | 4.000 | uniform (4× GBA) |
| 1200×800 | 5.000 | 5.000 | uniform (5× GBA) |
| 720×480 | 3.000 | 3.000 | uniform (3× GBA) |

⚠️ **NOT VERIFIED, and it matters:** I did not test whether animations
currently *look* wrong, only that the maths is anisotropic. It is possible the
port compensates somewhere I did not find, or that 12.5% is below the threshold
anyone would notice on most moves. **Before committing to 3:2 on this argument,
capture one long-travel vertical move** (Sky Attack, Bounce, Fly, Dig's
re-emergence) **densely and compare against reference footage.** That is a
one-hour check and it either confirms the strongest reason to move or removes
it.

---

## 3. M26A1's premise, re-measured

The recorded reasoning:

> Revised from an earlier **1200×800 (3:2, the true GBA hardware ratio)** once
> the Emerald UI Pack investigation found that pack's entire screen set — Bag,
> Party, Summary, Pokédex, Trainer Card — is uniformly **512×384 (4:3)**,
> matching Essentials' own native canvas; **1024×768 is a clean 2× integer
> multiple of that**, keeping pixel scaling crisp.

That was correct at the time. What has changed:

**148 assets in the tree are 512×384. Only 9 are adopted project art**; the
rest sit in reference packs (`Essentials_v19.1/Graphics` 94,
`Emerald UI Pack 1.2/Graphics` 36, `FRLG Summary Screen/Graphics` 6).

The nine, and what uses them:

| Asset | Screen |
|---|---|
| `bag/bag_bg_male.png` | `item_select_screen` |
| `bag/bag_bg_female.png` | **0 references — unused** |
| `party/party_bg_singles.png`, `party_bg_doubles.png` | `switch_select_screen` |
| `summary/summary_frlg_frame_base.png` + 4 page backgrounds | `summary_screen` |

**Three screens.** Everything else in `assets/sprites/battle_ui/` is GBA-native
small art — 16×48 (28), 32×16 (25), 24×24 (21), 8×16 (20), 156×98, 288×48. The
512×384 group is 9 of ~150 files in that tree.

**So the 4:3 canvas is now protecting three full-screen backdrops**, not a
screen set. That is a much smaller anchor than the decision was made against —
and M26A1's own second half already anticipated the split: *"most of M26's
actual screen art … doesn't need the outer canvas itself to be 3:2 to stay
correct — they're sized to their own real ratio within the bigger 4:3 canvas."*
The same argument runs in reverse: three 4:3 backdrops can be letterboxed
inside a 3:2 canvas.

⚠️ **NOT VERIFIED:** whether those three screens are intended to stay on pack
art or eventually move to real FRLG art like the rest of the UI has. **That is
the single question that decides this**, and it is Rob's, not mine. If they
stay, 3:2 costs re-authoring or letterboxing them. If they were always going to
be replaced, the 4:3 anchor is temporary and the move gets cheaper by waiting.

---

## 4. The overworld — a clean win, and an authenticity one

```
current   1024×768 zoom 3  → 21.3 × 16.0 tiles visible
3:2        960×640 zoom 3  → 20.0 × 13.3 tiles
3:2        960×640 zoom 4  → 15.0 × 10.0 tiles
GBA hardware                 15.0 × 10.0 tiles
```

**960×640 at zoom 4 reproduces the GBA's viewport exactly.** Today the player
sees 42% more width and 60% more height than the real game — which changes
encounter pacing, how much of a map reads at once, and how cutscenes frame.

Knock-ons, all mechanical:
- The camera zoom constant (`overworld.gd:613`, `Vector2(3, 3)`).
- **The border skirt.** `[M27C C3]` sized its depth by measuring the visible
  region at 1024×768 zoom 3 — *"21.3 × 16.0 cells … per-axis 12 × 9"* — and
  that measurement is the only reason the value is what it is. ⚠️ **The skirt
  system is not in `map_manager.gd` at HEAD** (see the note on commit
  `8115a7f8`); whoever re-lands it should size it against the final canvas
  rather than re-deriving 12×9.
- `[M27C C4]`'s crossing-stutter work measured chunk load cost against the
  current visible area; a smaller viewport loads less, so that gets easier.

---

## 5. What else is coupled

- **`BattleStage/Background` carries `offset_top = -96`** — a hand-tuned
  compensation for a GBA-proportioned backdrop in a 4:3 window, sitting in the
  scene file. At 3:2 it should be 0. Its presence is the clearest evidence that
  4:3 is being paid for in constants.
- **Battle backdrops are 256×128; anim backgrounds 256×112 and 256×256** — GBA
  BG tilemap dimensions, never screen dimensions. They are stretched to fit
  regardless, so they do not constrain the choice either way.
- **`window/stretch/aspect` is not set in `project.godot`** — only
  `mode="canvas_items"`. The project is running Godot's default. ⚠️ M26A1's own
  text says it chose `aspect="keep"`; **that setting is absent from the file.**
  Worth checking independently of this decision: the recorded intent and the
  actual config disagree.
- **224 test suites**, of which **16** reference layout, geometry or the
  literals `1024`/`768`. That is the re-verification surface, and it is smaller
  than the headline number suggests.
- **Sprite placement** — M26A1 records that sprites are *"placed via a
  fixed-pixel-size box anchored at a single fraction point"* and needed real
  re-tuning, not just re-verification, when the canvas last changed. Expect the
  same again. This is the largest single cost item and it is hand-work, not
  arithmetic.

---

## 6. Options

| | Pros | Cons |
|---|---|---|
| **Stay 4:3** | Zero work. Three UI screens keep integer scaling. | The 12.5% anisotropy is permanent; every future animation inherits it. The `-96` class of compensation keeps accumulating. |
| **960×640 (4× GBA)** | Uniform scale. Overworld = GBA viewport exactly at zoom 4. Smallest numbers, crispest integer maths. | Smallest window; 512×384 screens letterbox with ~107px side bars. A visible downgrade in window size from 1024×768. |
| **1200×800 (5× GBA)** | Uniform scale. **The original M26A1 plan.** Larger than today, so no perceived downgrade. | 512×384 → 2.34× non-integer; those three screens need re-authoring or accept soft scaling. Overworld needs zoom 5 for a GBA-exact view. |
| **720×480 (3× GBA)** | Uniform, smallest asset budget. | Too small for a modern window. |

---

## 7. Recommendation

**Yes to 3:2 in principle — 1200×800 — but do three things first, and do not
treat it as one change.**

**Why 1200×800 over 960×640:** it was the original plan, it is 5× GBA exactly,
and it is *larger* than today so nothing reads as a downgrade. 960×640's only
real edge is that zoom 4 gives a GBA-exact overworld view — but zoom 5 at
1200×800 gives the same thing.

**Before deciding anything:**

1. **Verify the anisotropy is visible** (§2). One dense capture of a
   long-vertical-travel move against reference footage. ~1 hour. If 12.5% turns
   out to be invisible, the strongest argument evaporates and this drops to a
   nice-to-have.
2. **Answer the UI-art question** (§3). Do the Bag/Party/Summary screens stay on
   512×384 pack art? That is a product decision and it sets the cost.
3. **Fix the message-box proportion** (§1) regardless. ~1 line, independent, and
   it is the actual symptom that started this.

**If it goes ahead**, sequence it as M26A1 itself was sequenced — canvas first,
then re-tune everything measured against it:

- **Phase 1** — canvas change, `aspect="keep"` made explicit, `pixel_scale`
  verified uniform, the `-96` compensation removed.
- **Phase 2** — battle sprite/health-box/message-region re-tuning. The largest
  item, hand-work, and the one M26A1 warns needs real re-tuning.
- **Phase 3** — the three 512×384 screens: letterbox or re-author.
- **Phase 4** — overworld camera zoom, and size the border skirt against the
  new canvas when it is re-landed.
- **Phase 5** — re-verify the 16 geometry-touching suites; sweep the rest.

**Sizing: 2–4 sessions**, dominated by Phase 2. Not a one-session change, and
not one that should be started mid-milestone.

⚠️ **The honest counter-argument**, stated because it is strong: nothing is
broken today that a player would notice, the animations have shipped 92%
complete at the current canvas, and 12.5% vertical compression is the kind of
thing you only see once someone tells you it is there. If the answer to check 1
is "no one can see it", **stay at 4:3** and fix the message-box strip instead.
