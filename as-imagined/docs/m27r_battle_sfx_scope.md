# M27R 7a-3b — wiring the battle SFX

**Scoped 2026-08-09. Nothing built.** The catalogue and the selection rules
shipped with 7a-3; this is the half that makes them audible.

---

## 1. What already exists

| | |
|---|---|
| the 11 `.ogg` files | present, verified on disk by H.02 |
| `AudioMap.SE` entries | `SE_DAMAGE_*`, `SE_BALL_*`, `SE_RECALL`, `SE_SEND_OUT`, `SE_FLEE` |
| `AudioMap.damage_se(effectiveness)` | tested, break-tested |
| `AudioMap.catch_sequence(shakes, caught)` | tested, break-tested |
| `FieldAudio` | a working SE pool with a cue log |

**What is missing is only the calling.** `battle_screen_shared.gd` never
references any of it.

---

## 2. Step 0 findings

### 2.1 ⚠️ A SOUND MUST BE A BEAT, NOT A SIGNAL HANDLER

This is the finding that decides the whole shape, and it is the one a naive
implementation gets wrong.

`battle_screen_shared.gd` does not render a turn as it happens. It **queues**
`_pending_beats` and drains them in `_run_message_pacing()`, sequentially, with
`await` between each — nine kinds today (`text`, `anim`, `anim_async`,
`hp_drain`, `flash`, `recall`, `switch_reveal`, `party_summary_show`,
`ability_popup`). Text reveals character by character; HP bars drain over a
tween; animations are awaited to completion.

**So playing a sound directly from `move_executed` fires it seconds before the
damage it belongs to is drawn** — every sound in a turn would stack up at the
front while the visuals played out after. Sounds need a tenth beat kind,
`"sfx"`, queued in the same order as everything else.

⚠️ That also means the work is **not** "connect five signals". It is "append a
beat at the right point in five existing handlers", which is a smaller change to
more delicate code — those handlers already order themselves carefully against
one another (see the comment at `:1910` about connection order).

### 2.2 ⚠️ The pacing path is BYPASSED in two modes, and that shapes the tests

`_run_message_pacing()` returns early, clearing the queue, for **`--autoplay`
runs** and for **bare test instances that never entered the tree**
(`not is_inside_tree()`). Both are correct — neither wants audio or timing —
but it means:

**A test cannot assert that a sound PLAYED. It can only assert the beat was
QUEUED.** Anything else would be asserting through a path that is deliberately
switched off in exactly the conditions a headless suite runs in. `FieldAudio`'s
own `cues` log is the right target for the few tests that do drive a player.

### 2.3 The data each hook needs is already in hand

- **Damage** — `_pending_hit_effectiveness` is set by
  `_on_hit_effectiveness_computed` *before* the damage line is logged
  (`:2990`, used at `:3045`), so the correct variant is known at queue time.
- **Capture** — `catch_attempted(user, target, item, caught, shakes)` already
  carries the shake count. `[M27H H4]` emitted it specifically so a later
  consumer would have nothing to retrofit; this is that consumer.
- **Recall / send-out** — `_pending_beats` already has `recall` and
  `switch_reveal` beats, so the sound belongs *inside* those rather than beside
  them.
- **Flee** — the escape path is `try_flee`'s own outcome.

### 2.4 It is genuinely simulator-shared

`battle_screen_shared.gd` (8,432 lines) backs **both**
`battle_screen_singles.tscn` and `battle_screen_doubles.tscn`, which the
simulator and the RPG overlay both use. Anything added here is added to both
products — which is why the catalogue already lives in the shared `AudioMap`
rather than beside the field code.

---

## 3. Decisions

### D1 — ⚠️ Where does the audio player live? *(the one that needs answering first)*

There is no player on the battle side. `FieldAudio` is a plain `Node` with an SE
pool and a cue log — nothing in it is overworld-specific except its **name** and
a BGM stub it need not use.

1. **Reuse `FieldAudio` as-is**, added as a child of the battle screen.
   Zero new code, reuses a tested player. ⚠️ Costs a misleading name in battle
   code, which is exactly the kind of thing that misleads a later reader.
2. **Rename it** to something neutral (`GameAudio`) and reuse.
   Correct, and churns `overworld.gd`, `field_native_events.gd`, `script_vm.gd`
   and `m27r_audio_test.gd`. A mechanical rename, but it touches the audio suite
   that is currently the only proof any of this works.
3. **A second, battle-local player.** ⚠️ Rejected on sight — two SE pools with
   two lifetimes is the two-hand-kept-copies shape this project has paid for
   repeatedly.

**Recommendation: 2.** The rename is cheap now and permanent; option 1's cost
compounds every time someone reads the battle screen.

### D2 — Does the capture sequence wait for M26B7?

`catch_sequence()` returns an ordered list, but the *timing between* its
entries is the ball animation's — and **M26B7 (catch UI) is scoped, not built**.

1. **Wait for M26B7.** The sounds land with the animation they describe.
2. **Ship now with fixed delays** (throw, ~0.4 s, hit, then a shake every
   ~0.6 s). Audible immediately; ⚠️ the delays are invented and would be
   re-tuned once there is something to sync to, so they are guessed twice.

**Recommendation: 1 for the capture sounds specifically, 2 for everything
else.** Damage, recall, send-out and flee all have real visual beats to attach
to *today*; only the ball sequence does not. Splitting them is what lets the
other eight ship without inventing timings.

### D3 — Volume, and whether the simulator wants sound at all

Not investigated: this project has no audio bus configuration, no master
volume, and no options screen (`OPTION` is deliberately absent from the start
menu). A battle that suddenly makes noise with no way to turn it down is a real
complaint. ⚠️ **Worth deciding before shipping, not after** — it may be one
`AudioServer` bus and a constant, or it may be the first piece of an options
screen, which is a different size of job.

---

## 4. Proposed tiers

- **7a-3b — the `sfx` beat kind and the eight anchored sounds.** One new beat
  kind in `_run_message_pacing`, the player resolved per D1, and beats appended
  in the existing damage / faint / recall / switch-reveal / flee handlers.
  Tests assert the QUEUE, per §2.2.
- **7a-3c — the capture sequence**, folded into M26B7 rather than led by it, so
  the sounds and the ball animation are timed together once.

**Sizing:** 7a-3b is small in lines and delicate in placement — five existing
handlers, each of which already orders itself against the others. The risk is
ordering, not volume of code.

---

## 5. Open questions for Rob

1. **D1** — rename `FieldAudio`, or reuse it under its current name?
2. **D2** — hold the capture sounds for M26B7, or ship them now with invented
   delays?
3. **D3** — does anything exist for volume control, or is that a new job?
