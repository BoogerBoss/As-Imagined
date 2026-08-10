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

### D1 — ⚠️ Where does the audio player live? **DECIDED: rename and reuse (Rob, 2026-08-09).**

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

✅ **CHOSEN: option 2.** `FieldAudio` is renamed to a neutral `GameAudio` and
reused by both. ⚠️ The rename touches `overworld.gd`, `script_vm.gd`,
`field_native_events.gd` and `m27r_audio_test.gd` — **including the audio suite
that is currently the only proof any of this works**, so the suite must be green
before and after with the same assertion count, or the rename hid something.

### D2 — Does the capture sequence wait for M26B7? **DECIDED: split (Rob, 2026-08-09).**

`catch_sequence()` returns an ordered list, but the *timing between* its
entries is the ball animation's — and **M26B7 (catch UI) is scoped, not built**.

1. **Wait for M26B7.** The sounds land with the animation they describe.
2. **Ship now with fixed delays** (throw, ~0.4 s, hit, then a shake every
   ~0.6 s). Audible immediately; ⚠️ the delays are invented and would be
   re-tuned once there is something to sync to, so they are guessed twice.

✅ **CHOSEN: split.** The eight sounds with real visual beats — damage x3,
recall, send-out, flee, and the faint/KO — ship now. The four ball sounds wait
for M26B7 and get timed once, alongside the animation they describe, rather
than being guessed and then re-tuned.

### D3 — Volume. **DECIDED: one bus, constant level (Rob, 2026-08-09).**

This project has no audio bus configuration, no master volume, and no options
screen (`OPTION` is deliberately absent from the start menu).

✅ **CHOSEN: a named SFX bus at a fixed level.** ⚠️ **The point of the bus is
that it is the ONLY place volume ever has to be touched** — every play site
routes through it, so a later options screen or a persisted setting changes one
value rather than auditing every `play_se` call. A constant now, controllable
whenever someone wants to control it.

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

## 5. Open questions

**None — all three answered 2026-08-09.** Rename and reuse; split the capture
sounds out to M26B7; one SFX bus at a constant level.

---

## 6. Built — 2026-08-10

**7a-3b is done.** Six hooks, one new beat kind, one renamed player, one SFX
bus. 21 new assertions in `message_pacing_test` (70 → 92), six injections run.

| | |
|---|---|
| `FieldAudio` → `GameAudio` | `git mv` + rename across 6 files; `m27r_audio_test` **57/57 before and after**, which is D1's own acceptance check |
| SFX bus | `GameAudio.BUS_NAME = "SFX"` at `BUS_DB = 0.0`, created at runtime by `_ensure_bus()` and routed to Master; every SE voice, the ME player and the BGM player set `.bus` |
| the `"sfx"` beat kind | in `_run_message_pacing()`, **fire-and-forget — deliberately NOT awaited** |
| hooks | damage (×1 site, all three variants), faint recall, switch-out recall, send-out, successful flee |

### What the tests assert, and what they cannot

Per §2.2, every assertion is on the **queue**. The pacing loop returns early
and clears the queue for `--autoplay` and for off-tree instances — exactly the
conditions a headless suite runs in — so asserting that a sound PLAYED would be
asserting through a path that is switched off here.

⚠️ **THE ORDERING IS AN ASSERTION, NOT A COMMENT.** The damage sound is queued
BEFORE the `hp_drain` beat so the hit is heard as the bar starts moving rather
than after it settles. Injecting the swap fails `the sfx beat comes strictly
BEFORE the hp_drain beat` — and also breaks a pre-existing end-to-end ordering
assertion, which is the stronger signal.

⚠️ **THE VARIANT DISCRIMINATOR IS THE ONE THAT MATTERS.** A hook that queued
one fixed sound would satisfy every "a sound was queued" check. Two runs, one
variable: super-effective and resisted must queue DIFFERENT sounds, and neutral
must be neither. Injecting a hardcoded `SE_DAMAGE_NORMAL` fails all four.

⚠️ **ONE ASSERTION WAS FOUND VACUOUS BY ITS OWN INJECTION — rule 13 again.**
The no-damage test originally used an IMMUNE hit (damage 0 AND effectiveness
0), which is refused twice over: `damage_se()` returns `""` **and** the drain
block is skipped. Removing the empty-name guard failed nothing. Rebuilt on a
NEUTRAL effectiveness, which names a real sound, so only the no-damage gate can
suppress it — and the empty-name half is now asserted where it is actually the
deciding rule. Re-injected: moving the call outside the `damage > 0` gate now
fails it.

**Injections run, and what each failed:** empty name accepted → 1 (the
empty-name assertion alone); sound after the drain → 2; one fixed damage sound
→ 4; no send-out sound → 2; no faint recall → 3; damage sound outside the
`damage > 0` gate → 2.

### Not covered, stated rather than implied

- ⚠️ **THE FLEE HOOK HAS NO TEST.** It sits inside the Run button's own
  handler behind `_bm.try_flee()`, which needs a real wild battle to reach; the
  suite drives bare instances. The rule it encodes — sound only on a SUCCESSFUL
  escape, because a failed flee costs the turn and the jingle would say the
  opposite of what happened — is recorded at the call site.
- ⚠️ **NOTHING HAS BEEN HEARD.** Every assertion is on beat records. No sound
  has been played through a device, in battle or anywhere else.
- The four ball sounds stay with **M26B7**, per D2.

