# Handoff — Claude Code session, 2026-08-03

## What this document is, and what it is NOT

Written at the end of a session that worked exclusively on **M36 (Move
Animation Engine)**. It covers that workstream's live state, the next actions,
and — the part worth reading twice — **the traps that are not obvious from the
docs**.

⚠️ **THERE ARE TWO ACTIVE WORKSTREAMS AND THIS COVERS ONE.** Rob has been
building **M27 (overworld / full RPG)** in parallel throughout: M27F, M27H
(closed), M27I and M27O all landed between my own commits. **I have no
first-hand knowledge of that work, have never run its suites, and deliberately
never touched its files.** Do not infer M27 state from anything here — read
`CLAUDE.md`'s M27 row and `docs/overworld_scope.md` instead.

This is a supplement to `CLAUDE.md`, not a replacement. It deliberately does
not restate the standing rules, the build order, or the reference procedure.

---

## 1. Orientation — read in this order

1. **`CLAUDE.md`** — the project guide. Enormous (~1.2 M chars) and flagged as
   near its size cap. **Do not read it end to end.** Read: "What this project
   is", "Ground truth / reference", the working-directory rule, the testing
   conventions, and then only the milestone row you are working on.
2. **`docs/m26_f1_recon.md`** — **the scope of record for M36.** CLAUDE.md's
   M36 row says so explicitly and points here. One section per sub-tier and
   per batch, newest first. If a batch note and CLAUDE.md disagree, this doc
   is the fuller account.
3. This file.

**A convention worth knowing before you edit anything**: this project does
**not** rewrite historical entries when a claim turns out to be wrong. It
appends a correction and says which entry is superseded. Follow that — several
entries you will read are marked stale in place.

---

## 2. M36 state as of the final commit

| | |
|---|---|
| Coverage | **779 of 845 in-scope moves playable (92.2 %)** |
| Raw figure the tools print | 860 of 932 — that denominator **includes Z/Max** |
| Behaviors registered | 489 |
| `m36d_batch_test` | 1226/1226 |
| `m36_leak_harness` | 785/785, `KNOWN_LEAKS` **empty** |
| Batches complete | 39 |

⚠️ **THE TWO DENOMINATORS ARE BOTH REAL AND EASY TO CONFUSE.** Rob ruled
**Z-Moves and Max Moves out of scope entirely** on 2026-08-03. The cut is
source-exact — `FIRST_Z_MOVE = MOVES_COUNT_GEN9` (`include/constants/moves.h`),
so id **847 (Malignant Chain) is the last in-scope move and 848 (Breakneck
Blitz) the first excluded** — removing 87 of the 932 bound moves.
`m36_coverage_report` and `m36d_batch_test` still print **932**; only the leak
harness filters. **Report progress against 845.** Restating dropped the
percentage (91.3 % of 932 → 91.1 % of 845) because 12 excluded moves were
already playable; that is recorded rather than presented as a gain.

**Artifacts you will use:**

* `scenes/battle/m36_coverage_report.tscn` — not a test. Prints per-tier
  coverage and a greedy "what to port next" ranking. **Run it before planning
  a batch.**
* `scenes/battle/m36d_batch_test.tscn` — the batch suite. One section per
  batch, dispatch is an explicit call list in `_ready()`, not auto-discovery.
* `scenes/battle/m36_leak_harness.tscn` — built this session. Runs all 779
  playable in-scope scripts end to end and checks each terminates, does not
  error, restores every battler, and leaves nothing on the layer.

---

## 3. Working agreements with Rob

* **Rob commits** — except he gave explicit one-off approvals this session.
  Do not assume standing permission; ask, or leave the work in the tree.
* **Commit to `main`, not a topic branch.** I got this wrong once and was
  corrected. There is no PR flow here.
* **Scope every commit to your own files.** Rob's work lands between yours.
  Stage explicitly by path; never `git add -A`.
* **Full `scripts/count_assertions.sh` sweeps are Rob's manual step.** Run
  tier-specific suites for the work in hand.
* **Never fill the `A` (Approved) slot** in any `C/T/A` status table.
* 29 commits are unpushed. Pushing is Rob's call.

---

## 4. Next actions, ranked

**0. M36P — the battler transform anchor. Added 2026-08-11, ahead of
everything below.** Numbered 0 rather than renumbering the list, so what this
handoff originally ranked stays readable.

Reported from play, not found by any test: battler `Control`s have
`pivot_offset == (0, 0)`, so every `rotation`/`scale` a behavior writes on one
pivots at the **top-left corner of a 320-357px box** rather than its centre.
**19 behaviors, 89 of 933 moves.** It outranks more porting because those 89
moves are already "playable" and are rendering wrong — coverage is not the
constraint here, correctness is.

⚠️ **Read this before trusting §6 or the leak harness**: `m36_leak_harness`
passes **784/784** over this defect, because it asserts the END state and the
VM's own `_restore_battler_baseline()` puts every battler back first. Nothing
in this project samples DURING a run. That is now standing rule (16).

Scope of record: `docs/m26_f1_recon.md`'s own **`M36P`** section — diagnosis,
five phases, the separate `_bow_mon` absolute-vs-incremental bug it turned up
(14 moves), and 2 open decisions for Rob. Nothing is built and nothing is
approved.

**0b. M36E4 — the background viewport mapping. Added 2026-08-11, same
ranking.** Also reported from play, on Blizzard, and the same underlying shape
as 0: correctly pulled, wrongly placed.

`AnimStage.background_layer()` stretches every background to fill the whole
1024×768 stage, where hardware views a BG through a fixed **240×160 window**.
Blizzard's `highspeed_*` asset is 256×256 with y-scroll 0, so its bottom 96
rows — measured as flat filler — are unreachable on hardware and are now drawn
across the bottom 37.5% of the screen, with the real artwork squashed to 62.5%
of its correct vertical scale. **82 of 92 backgrounds are mis-mapped**, in both
directions (48 taller than the screen, 34 shorter).

⚠️ **This REOPENS M36E**, which §2 records as complete. E1/E2/E3 themselves are
fine — fade ordering, palette cycle, scroll and scanline band are all correct
and unaffected; what was never established is where the layer sits.

⚠️ **`m36e_background_asset_test` passes over this** — it asserts width is
exactly 256 and height only `% 8 == 0`. That is now standing rule (17):
verifying an ASSET is not verifying its PLACEMENT.

Scope of record: `docs/m26_f1_recon.md`'s own **`M36E4`** section — including
the third mismatch in the same code (backgrounds render at 93.75% of the scale
sprites use, because `pixel_scale()` assumes a 240px-wide screen and the
background is 256 wide) and 2 open decisions for Rob.

**1. Re-read the six remaining "blocked" surfaces before porting anything
else.** This is the highest-value item and it is not a batch.

On the last check, my own "permanently blocked on absent architecture" label
was wrong for at least three of them:

| Surface | Moves | What it actually is |
|---|---|---|
| Spotlight | 6 | `WIN1` set to `WIN_RANGE(0,240) × WIN_RANGE(120,160)` — a **rectangular band** plus a fade. Same shape as the batch-37 band; `set_fade`/`fade_overlay` already exist. |
| Seismic-toss BG | 3 | `gBattle_BG3_Y += speed/10`, decaying — **vertical background scroll.** `set_background_scroll(Vector2)` already takes both axes. |
| Item icon | 2 | `AddItemIconSprite(..., gLastUsedItem)`. **324 item icon PNGs keyed by item id already exist**, and `last_used_item` is ported. |
| Palette backup buffers | 2 | Save/restore around a fade. No palette indirection exists here (colours are shader tints), but the observable is expressible. |
| Mosaic + sheet swap | 2 | **NOT READ. Cost unknown.** |
| Memento shadow | 3 | **NOT READ.** I called it "stencil" from the function names — which is exactly the inference that was wrong about Rapid Spin. |

Corrected split: **~4 genuinely closed** (Terrain — void by Rob's M17e
decision; Secret Power — out of scope by Rob's call), **~62 reachable.** My
earlier "~19 blocked" figure was wrong in Rob's favour.

**2. The three named spawners** — the largest readable block left. Each has a
specific blocker recorded at the batch-39 section header:
`AnimTask_AirCutterProjectile` (fixed-point division, direction packed in
`data[8]`'s low bit, subpriority packed in `args[4]`'s high bit),
`InitPoisonGasCloudAnim` (three phases, per-frame OAM priority flipping),
`AnimTask_LeafBlade` (nine states driving the target's affine table).

**3. Everything else is ~1 move per behavior.** The greedy top fell from +19
to +1 around batch 36. **Rule (1) — "judge a batch by the machinery it
retires" — has stopped discriminating.** Pick for readability now.

**4. The screenshot pass.** See §6.

---

## 5. Traps

**The one that will bite you first: `cd` cannot be trusted.** The repo root
the environment enforces is `/home/rob/GodotAsImagined`, **one level above**
the Godot project at `as-imagined/`. A `cd` outside the repo is silently
intercepted and resets you to the root, after which every relative path fails.
Always use absolute paths in the same command string. CLAUDE.md has a whole
section on this; it is not paranoia, it recurred repeatedly.

**Blocker-reason rot — the finding this session ends on.** A deferral reason,
once written, gets re-cited as fact by later sessions *including by me*. It
has collapsed on contact with source **four times**: `AnimTask_ScaryFace`, the
batch-16 four, Rapid Spin (labelled "scanline DMA" for ten batches — half of
it never touched a scanline register, and the real surface was three shader
uniforms), and now the list in §4. **Treat every stated blocker as a
hypothesis with a date on it.**

**Injection-first, not injection-after.** Rule (7) now carries the preventive
form: derive each assertion from the **negation**, not the truth. Ask "what
would the specific plausible WRONG version do differently?" and assert the
difference — ideally write the injection before the assertion. Across five
consecutive batches the injection found a weak *test*, not weak *code*; batch
39's gravity guard needed **two** rewrites before it discriminated at all
("it accelerates" is true of constant gravity as well as quadratic).

**`KNOWN_LEAKS` in the leak harness must stay empty.** An entry reappearing
means a batch reintroduced the leak class the VM cleanup fix closed.

**Fixture limits that silently pass tests.** `FakeStage.facing_sign()` returns
a fixed `1.0`, so **no test in this suite can observe a side-mirror**. And
`_spawn()` returns the layer's *first* `AnimSprite` child — spawning several
onto one stage re-measures sprite zero. Both have produced vacuous guards; use
a fresh `FakeStage` per sprite.

**New `class_name` files need an import pass** before the test scenes see
them: `--headless --path . --import`. Note `--editor --quit` is a *different*
flag and has silently failed to pick up same-size texture changes before.

**Scaled GBA literals are a latent bug class.** Several behaviors free a
sprite once it leaves the "240×160 screen" by scaling those literals by
`pixel_scale`. That is wrong on a stage whose aspect differs from the GBA's —
it cost batch 39 a real bug (rocks spawning past the floor, dying on frame
one). `_layer_extent()` exists now; batch 36's lava plume still uses the old
pattern and is harmless only because its sprites start mid-screen.

**Do not touch `scripts/overworld/`, `scenes/overworld/`, or `scripts/gen_map_*`.**
That is Rob's active M27 work.

---

## 6. What is NOT verified — read before claiming anything is done

**Nothing since batch 24 has been looked at on screen.** Sixteen batches,
~150 behaviors. The suites are strong on state and structurally blind to
appearance.

**The leak harness does not close that gap.** It is *defect detection* — did
it render, leak, wedge — not *fidelity verification*. It cannot tell you an
animation looks like the reference. A green run there is not "the animations
are verified".

**The core-VM cleanup change (`bc122097`) is the least-verified thing I
shipped.** It touches `_finish()`, the function every animation ends through,
and my verification is the suite plus the harness — not a battle on screen. If
the new snapshot-restore ever fights a legitimately persistent effect (one a
script *means* to leave up for a following step), **no test here would catch
it** — the harness would call it clean, because clean is exactly what it
asserts.

**A known, flagged, unfixed divergence**: upstream's
`SetBattlerSpriteYOffsetFromYScale` keeps a scaling mon's **feet planted**;
this port scales about the pivot. It affects every affine behavior from
batches 25, 27, 28, 33 and 39. Not ported because a bottom-centre
`pivot_offset` was tried in M26B3-6a and reverted for looking worse. **This is
the top item for a screenshot pass.**

**Recommended screenshot list (~8, not 150)** — chosen where a wrong port is
*systemic* rather than per-move: the batch-37 background band; any affine
mon-scale move (the feet-planting divergence); Flamethrower (exercises the
batch-24 `_load_args` fix, which had silently broken its flame stream for ten
batches); a spread move; Volt Switch (the two-leg arc); Rapid Spin; an
arc-family move; Odor Sleuth. If those are right, the tail is mostly parameter
values the tests already pin.

---

## 7. Open questions for Rob

* **Push?** 29 commits sit unpushed on `main`.
* **When to do the screenshot pass** — my recommendation is once M36D closes,
  since the shared surfaces it checks are the least likely to change. The
  batch-37 background band is the one item worth looking at sooner.
* **`m36_coverage_report` and `m36d_batch_test` still print /932.** Worth
  teaching them the 845 denominator so the two figures stop diverging.
