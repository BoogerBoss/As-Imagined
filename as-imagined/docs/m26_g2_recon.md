# M26G2 recon — `_pending_beats` sequencing audit

Scope note per CLAUDE.md's own M26G2 entry: this milestone covers
**sequencing and ordering**, not just duration/easing. Every real pacing
defect found in the M26B3/M26B5 arc was an ordering bug a
duration/easing-only pass would have walked straight past. This doc is the
Step-0 inventory that entry calls for — written before any fix, per this
project's own standing discipline.

## The one invariant everything here depends on

`_run_message_pacing()` (`scenes/battle/battle_screen_shared.gd:4622-4742`)
is written as though it is the ONLY thing that will ever walk
`_pending_beats` at a time — a single producer window (one `advance()`
call's worth of signal handlers) feeding a single consumer (one paced
`for` loop) that clears the array once, at the very end
(`_pending_beats.clear()`, line 4741).

Nothing enforces that invariant. It is a load-bearing assumption with zero
guard anywhere in the file.

## Confirmed root-cause bug: no re-entrancy guard on the three input handlers

`_dispatch_move` (7944), `_on_switch_pressed` (7955), `_on_item_pressed`
(7973) are the only entry points a human player can trigger, and all three
share this shape:

```gdscript
_bm.advance()          # synchronous, resolves the whole turn instantly
_menu = Menu.TOP        # (or similar state flip)
await _run_message_pacing()   # multi-second paced replay
_refresh_ui()            # <- this is what rebuilds/disables the buttons
```

`_refresh_ui()` — the only thing that clears the previous turn's buttons —
runs *after* `await _run_message_pacing()`. Nothing disables input for the
duration of pacing. `BattleManager._is_advancing`
(`battle_manager.gd:552,1288-1301`) only guards re-entrant calls to
`advance()` *from inside `advance()` itself*, and is already reset to
`false` before `advance()` returns — long before pacing even starts.

So a second click during the paced sequence fires a second `advance()`
(instantly resolving the *next* turn's damage/faint/switch-in in engine
state while the first turn's animation is still mid-flight) and a second,
concurrent `_run_message_pacing()` coroutine. That coroutine does not
inherit or wait for the first one's iteration state — it starts its own
fresh `for beat in _pending_beats:` loop over the *same shared array*,
which by now holds the first turn's not-yet-clined-because-still-mid-loop
beats *plus* everything the second `advance()` just appended.

Concretely, `switch_reveal`'s handler (4693-4725) calls
`_refresh_battlefield_side()` **synchronously**, as the very first thing it
does, before any `await`:

```gdscript
"switch_reveal":
    var reveal_party: BattleParty = beat.get("party", null)
    if reveal_party != null:
        _refresh_battlefield_side(reveal_party, beat.get("is_player", false))
    ...
    await _play_send_out(reveal_mon)
```

If the second coroutine reaches its own `switch_reveal` beat before the
first coroutine's `for` loop reaches the KO-causing attack's own `anim`/
`hp_drain` beats, the new Pokémon's sprite snaps into view immediately —
which is exactly the reported symptom: the next Pokémon appears before the
attack animation that produced the knockout, and the surrounding text
narrates as though it were already the active combatant.

## Full inventory

### Beat kinds (doc comment at 1156-1166, consumer at 4629-4739)

| kind | payload | awaited? |
|---|---|---|
| `text` | `text`, `hold` | yes — reveal tween, then `hold` timer |
| `anim` | `start: Callable` returning a `Tween` or null | yes, if a Tween was returned |
| `anim_async` | `start: Callable` (a coroutine, not a Tween) | yes — `await run.call()` |
| `ability_popup` | `mon` | fire-and-forget popup animation, but the beat itself still `await`s a fixed `_WAIT_TIME_SHORT` timer |
| `flash` | `sprite` | yes — damage-blink tween |
| `hp_drain` | `bar`, `from_frac`, `to_frac`, `color` | yes — HP-bar tween |
| `switch_reveal` | `party`, `is_player`, `mon` | sprite/HP sync is **synchronous**, then `await _play_send_out(...)` |
| `party_summary_show` | `is_player` | synchronous, no await (just shows a row) |
| `recall` | `mon` | yes — `await _play_recall_to_ball(...)` |

### Every append site

- 2258 — `pokemon_fainted` handler → `recall` (queued, not awaited inline, deliberately — comment notes a second listener on the same signal, M26o's party-summary re-show)
- 2272 — `pokemon_switched_out` handler → `recall`
- 2276 — `pokemon_switched_out` handler → `party_summary_show`
- 2292 — `pokemon_switched_in` handler → `switch_reveal`
- 2681, 2692, 2966, 2993 — various hit-effect/ability dispatch → `anim_async`
- 2798 — item-4 damage blink → `flash`
- 2812 — HP-bar sync → `hp_drain`
- 3021 — hit-effect dispatch → `anim`
- 3395 — battle-start message stash flush → `text`
- 3451 — `_log()`, the general-purpose narration sink → `text`
- 6105 — ability-popup trigger → `ability_popup`
- 6930 — (a second, narrower `text` append site)

### The connection-order dependency (1725-1743)

`_bm.move_executed.connect(_on_hit_effect_move_executed)` is deliberately
connected **before** `_wire_log_signals()`'s own `move_executed` listener,
because Godot fires multiple handlers on one signal in connection order,
and that's the *only* mechanism keeping the `anim` beat ahead of the
`hp_drain` beat in the queue. The comment records this already broke once
(HP bar draining before the hit animation played) and was fixed by
reordering the `.connect()` calls — not by any structural ordering
guarantee. This is a real, working fix, but it's an implicit contract: any
future handler added on `move_executed` ahead of this line, or any
reordering of `_ready()`, silently reintroduces the same bug class with no
test to catch it.

### Disclosed bypass (7569-7586)

`_build_switch_buttons`'s zero-valid-candidate auto-resolve path calls
`_bm.advance()` then `_pending_beats.clear()` immediately, discarding
whatever beats that resolution produced, with an explicit comment
explaining why (this runs synchronously inside `_refresh_ui()`'s own build
phase, not from a real player action — awaiting pacing here would require
making `_refresh_ui()` itself a coroutine). This is safe in isolation: it
runs before any pacing has started for the turn, and clears rather than
interleaving. Not part of the re-entrancy bug, but it is a second place
`_pending_beats` gets mutated outside the normal single-producer/
single-consumer flow — worth knowing about if `_pending_beats`'s contract
is ever tightened.

### Stash/restore mechanism (3399-3432)

Used exactly once, at intro time, to reorder battle-start events
(switch-in abilities/weather/hazards) to print *after* the intro's own
challenge/send-out messages rather than before, matching source's real
message order. `_stash_battle_start_beats()` duplicates-and-clears;
`_restore_battle_start_beats()` appends the stash back plus flushes
buffered effect lines. Runs entirely within `_ready()`, before any player
input is possible — not a race risk, but establishes that direct
manipulation of `_pending_beats` outside the beat-append convention is a
precedent in this codebase, not a one-off.

### Other `.advance()` call sites — confirmed complete list

- 2002 — the `--autoplay` loop. Never calls `_run_message_pacing()` at
  all — every turn resolves and the loop just moves on. Immune to the
  race by construction, but this also means **the entire paced-animation
  layer has zero automated test coverage**: no existing suite could ever
  have caught this bug, or would catch a regression on the eventual fix,
  because the only automated path through this file bypasses pacing
  entirely.
- 7576 — the disclosed bypass above.
- 7947, 7961, 7976 — `_dispatch_move`/`_on_switch_pressed`/
  `_on_item_pressed`, the three vulnerable entry points.

Confirmed the Item/Switch select overlays (`_on_switch_screen_mon_chosen`
7597, `_on_item_screen_item_chosen` 7635) don't have their own `advance()`
— they close the overlay and call back into `_on_switch_pressed`/
`_on_item_pressed`, so they inherit this bug rather than adding a new
instance of it.

### Past ordering fixes — spot-checked, still correct

Cross-referenced against CLAUDE.md's own list of previously-found ordering
bugs (party-status row racing an attack animation; recall never playing;
ball-throw racing a trainer slide-out): the `pokemon_fainted`/
`pokemon_switched_out`/`pokemon_switched_in` handlers (2251-2293) all
correctly queue beats rather than acting inline, with doc comments citing
the exact reasoning. These remain correct under *normal* single-threaded
draining — they say nothing about the re-entrancy case, since that
capability didn't exist when they were written.

## Proposed scope, in priority order

**G2-1 (fixes the reported bug).** A re-entrancy guard on the three input
handlers — a boolean flag (or equivalent: disabling the action-region
input) set before `_bm.advance()` and cleared after `_refresh_ui()`,
checked at the top of all three. Smallest possible change, directly
addresses the reported symptom.

**G2-2 (defense in depth).** A guard *inside* `_run_message_pacing()`
itself — e.g. refuse/assert if entered while already draining — so a
future new call site that forgets G2-1's guard fails loudly instead of
silently reintroducing this bug class.

**G2-3 (test coverage).** A bare-instance regression test that drives two
overlapping `advance()`+pacing cycles and asserts the second is refused/
queued rather than racing the first. Currently impossible to catch this
via `--autoplay` (see above), so this is new coverage, not an extension of
existing coverage.

**G2-4 (lower priority, cosmetic).** The rest of M26G2's original scope —
reviewing every animation's own await-vs-fire-and-forget choice for
deliberateness, and the double-particle-burst feel judgment already
flagged in CLAUDE.md. Neither is a correctness bug; both are Rob's own
call on feel, not something to resolve by code inspection.

No code changed in this pass — recon only.
