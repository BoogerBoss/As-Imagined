# M26D3 — Battle dialogue completeness: full recon and sub-scope

**Status: SCOPED, nothing built.** This is the "dedicated future session to do
the real recon … and produce a real numbered sub-scope" that M26D3's own
roadmap entry called for. It supersedes the 2026-07-25 signal-wiring audit
recorded in CLAUDE.md's status history — that audit's method was sound and its
three highlighted findings all hold, but its **headline number and its scope
boundary were both too small** (§1).

No code, no tests, no `.tres` changes. Numbers below are re-derived
programmatically against current code, not carried over.

---

## 0. Executive summary

- The real candidate surface is **101 signals, not 72** (§1). The prior figure
  counted only signals with *no listener anywhere*; it missed an entire second
  population — **29 signals wired to the F3 debug panel but never to the
  in-battle message box**, which are just as invisible during normal play.
- **Essentially every one has real player-facing text in source.** Twenty
  distinct concepts were checked against `battle_message.c` and all twenty
  resolve to real `STRINGID`s (§3). This is not a case where the reference is
  silent and we would be inventing dialogue.
- Only **4** should never be narrated, and only one of those for a content
  reason rather than a plumbing one (§4).
- Proposed split: **D3-1 … D3-9**, ordered by leverage (§5). D3-1 is a single
  `connect` that restores 16 distinct player-visible messages.
- **Two decisions for Rob before building** (§7): meta-progression text, and
  how this interacts with M26B6's ability popup.

---

## 1. The number was wrong, and why

The 2026-07-25 audit reported **72 of 133** signals with "zero listener
anywhere (debug panel or message box)". Re-deriving today gives 134 declared
(the +1 is `weather_continues`, added *and* wired by M26B4-0, so it nets out).

Two corrections:

**(a) 74, not 72, are unwired for NARRATION purposes.** The original figure
counted a signal as "wired" if it was connected anywhere in
`battle_screen_shared.gd`. But two signals — `battle_ended` and
`move_damage_breakdown` — are connected outside the two narration functions
(`_ready()`'s own lifecycle wiring and the debug overlay's breakdown handler).
They are correctly *not* D3 candidates, but excluding them from "unwired"
understated the narration gap by 2.

**(b) The bigger miss: 29 signals are wired to the DEBUG PANEL ONLY.** The
audit noted this for `ability_triggered`/`ability_healed` specifically but
never generalised it. The F3 overlay is **off by default**, so a debug-only
signal is exactly as silent in normal play as an unwired one. The full set:

`ability_healed`, `ability_triggered`, `berry_stolen_and_eaten`,
`curse_damage`, `field_sport_set`, `future_sight_resolved`,
`future_sight_scheduled`, `healing_wish_activated`, `item_consumed`,
`item_damage`, `item_effect_triggered`, `item_stolen`, `item_transferred`,
`items_swapped`, `leech_seed_drained`, `move_bounced`, `move_stolen`,
`multi_hit_sequence_finished`, `nightmare_damage`, `pp_drained`, `pp_reduced`,
`side_condition_expired`, `side_condition_set`, `trick_room_ended`,
`trick_room_set`, `turn_order_changed`, `wish_resolved`, `wish_scheduled`,
`yawn_set`.

That set includes Trick Room, Reflect/Light Screen, Wish, Future Sight, Yawn
and every item interaction — all things a player currently gets **no in-battle
text for at all**.

**Reconciliation** (verified by direct count, both directions):

```
74 unwired (for narration)  +  29 debug-only          = 103
                            -   2 wired elsewhere      = 101 candidates
101 = 4 never-narrate + 96 across D3-1..D3-9 + 1 owned elsewhere
```

**Method, reproducible in one command** — parse `^signal (\w+)` from
`battle_manager.gd`, parse `_bm\.(\w+)\.connect` from the bodies of
`_wire_log_signals()` and `_wire_debug_signals()` separately, and set-difference.
Re-run it rather than trusting this document's numbers if the code has moved.

---

## 2. Current state, for reference

| Population | Count |
|---|---|
| Wired to the message box (`_wire_log_signals`) | 31 |
| Wired to the debug panel (`_wire_debug_signals`) | 42 |
| Wired to **both** | 13 |
| **Debug-only** (invisible in normal play) | **29** |
| **Unwired entirely** (for narration) | **74** |

---

## 3. Source verification — the reference is NOT silent

Twenty distinct concepts spanning every proposed sub-phase were checked
directly against `src/battle_message.c`. **All twenty resolve to real
`STRINGID`s**, most to several:

`SUBSTITUTE` (7 strings), `PROTECTED` (11), `SEEDED` (2), `FELLINLOVE` (2),
`NIGHTMARE` (2), `CURSE` (3), `FAINTINTHREE` (1), `STORINGENERGY` (1),
`UNLEASHED` (2), `TRANSFORMEDINTO` (2), `CHANGEDTYPE` (3), `STOCKPILED` (2),
`CHARGINGPOWER` (1), `GAINEDEXP` (2), `GOTMONEY` (1), `DISABLED` (5),
`ENCORE` (4), `TAUNT` (6), `TORMENT` (4), `ENDURED` (2).

A second batch confirmed the less obvious ones: `CRASHED`, `BUTITFAILED`,
`DEFROSTED`, `TOOKAIM`, `IDENTIFIED`, `CENTERATTENTION`, `READYTOHELP`,
`CANTESCAPE` (9 strings), `COPIEDSTATCHANGES`, `TRACED`, `TELEKINESIS`,
`RESTOREDPP`, `REGAINEDHEALTH`, `SHAREDPAIN`, `GREWTOLV`, `LEARNEDMOVE` — all
present. Octolock resolves under different naming
(*"{B_DEF_NAME_WITH_PREFIX} can no longer escape because of Octolock!"*).

**Two returned zero and need per-item confirmation at implementation time,
not assumed absent**: Recycle and Tar Shot. Both are real implemented moves
here; only their exact string names were not located by this pass's naming
patterns.

**One returned zero and genuinely IS absent: EV gain.** EVs are hidden stats
and source narrates nothing — see §4.

**Consequence:** D3 is overwhelmingly a *wiring and string-authoring* exercise
against text that already exists in the reference. It is not a design exercise,
and it should not become one.

---

## 4. Never narrate (4)

| Signal | Why |
|---|---|
| `phase_changed` | State-machine plumbing; no source concept |
| `action_needed` | Ditto |
| `replacement_needed` | Ditto — the *prompt* is UI, already handled by the Switch screen |
| `ev_gained` | **Content reason, not plumbing**: EVs are hidden stats and source prints nothing for them. Narrating them would be inventing dialogue the reference deliberately does not have. |

The first three are pure internals. `ev_gained` is the one worth stating
explicitly, because it looks like a meta-progression sibling of `exp_gained`
(which *does* have text) and would be easy to wire by analogy.

---

## 5. Proposed sub-scope

Ordered by leverage. Counts are exact and reconcile to 96.

### D3-1 — `move_skipped` (1 signal) ★ **COMPLETE 2026-07-27**

**47/47** in a new `scenes/battle/m26_d3_1_move_skipped_test.tscn`; 9 further
suites green. All 16 reasons now narrate.

Shipped: `_MOVE_SKIPPED_TEXT` (16 entries, strings taken from
`battle_message.c`) wired into `_wire_log_signals()`, plus an **RNG-category**
debug entry — 4 of the 16 (flinched / paralyzed / asleep / confused) are the
observable *outcome* of the very rolls that category was created for, which
M26A2's own category note names explicitly. Raw roll values remain unexposed;
that gap is unchanged.

**Three source findings worth keeping:**

1. **The confusion line has no name slot.** Source's is
   *"It hurt itself in its confusion!"* — unlike the other fifteen, which all
   take `{B_ATK_NAME_WITH_PREFIX}`. A naive `template % name` would have thrown
   on it, so the handler substitutes only when the template actually contains a
   slot. Pinned by its own test.
2. **Three reasons have NO dedicated STRINGID: Assault Vest, Blood Moon's
   "twice in a row", and Sky-Drop-held.** Not an oversight in source — it
   prevents all three at SELECTION time (the move is never offerable), whereas
   this project has no menu-legality filter and fails them at EXECUTION. They
   fall back to source's own generic `STRINGID_BUTITFAILED` (*"But it
   failed!"*), which is what source itself prints when an attempted move
   doesn't go through. **If a menu-legality filter is ever built, these three
   should become unreachable rather than getting better text.**
3. **Paralysis is not forceable in this project**, so the end-to-end test uses
   `must_recharge` (a plain bool) instead — `[M17n-10]` already hit the 25%
   full-paralysis roll as a real flake and worked around it the same way.

**The highest-value assertion is A.02, and it is not a hand-kept list.** It
re-derives every reason string from `battle_manager.gd` itself — both the 8
dedicated `move_skipped.emit(mon, "literal")` sites and the 8
`reason = "literal"` assignments feeding the shared site — and fails if any
reason exists that the text table doesn't cover. That is what stops a 17th
reason silently reintroducing the exact silence this sub-phase removed.

**One test bug, worth recording because it nearly read as a code bug:**
`_wire_debug_signals()` seeds its own RNG-tagged disclosure entry at the top
(M26A2's "raw roll values aren't exposed" note), so the RNG entry count after
one skip is **2, not 1**. The first draft asserted a bare count of 1 and
failed; the implementation was correct throughout. Diagnosed with a throwaway
scratch scene rather than by assuming.

*Original scoping note follows.*

### D3-1 — `move_skipped` (1 signal) ★ do this first
The single highest-leverage fix available anywhere in M26. **One `connect` plus
a reason→string table restores 16 distinct player-visible messages**, because
`move_skipped(pokemon, reason)` carries all of: recharge, loafing (Truant),
flinch, paralysis, sleep, freeze, infatuation, confusion, Sky-Drop-held,
Throat Chop, Disable, Taunt, Torment, Imprison, Assault Vest, and
"can't use twice". Today a Pokémon that cannot move produces **silence** — the
turn simply passes with no explanation, which reads as a bug to a player.
Small, self-contained, independently shippable. Same carve-out shape as
M26B4-0's `weather_continues`.

### D3-2 — ~~Abilities reach the message box~~ — **RETIRED, MOVED TO M26B6 (Rob, 2026-07-27)**

**This sub-phase was scoped on a wrong assumption and is withdrawn rather than
built.** Open decision (2) in §7 is resolved — in the opposite direction to
what that section assumed.

**What source actually does.** `BattleScript_IntimidateActivates` is three
lines (`data/battle_scripts_1.s`):

```
call BattleScript_AbilityPopUp     <- the POPUP carries the ability NAME
trystatchanges ...                 <- the message box carries only the EFFECT
destroyabilitypopup
```

The popup names the ability; **the message box never does.** There is no
*"X's Intimidate activated!"* line anywhere in the reference — that phrasing is
this project's own invention, written for the F3 debug panel where a popup
isn't available, and it is fine there.

**Why that retires this sub-phase.** This project **already narrates the
effects**: `stat_stage_changed` and `secondary_applied` are both log-wired, so
Intimidate today already prints *"X's Attack fell!"* — exactly what source shows
in the message box. The only missing piece is the ability NAME, which is
precisely what M26B6's popup exists to provide. Wiring
`_ABILITY_TRIGGER_TEXT` to the message box would therefore **not** pre-wire B6;
it would pre-empt it, adding invented text that B6's banner then duplicates.

**Disposition:**

- **`ability_triggered` → M26B6.** The popup owns the ability name. The
  86-entry `_ABILITY_TRIGGER_TEXT` table STAYS on the F3 panel, where its
  non-source phrasing is appropriate and useful. Do not move it.
- **`ability_healed` → still wants message-box text**, and is NOT covered by
  the popup: source has real "regained health" lines, and an unexplained heal
  reads as a bug. Confirm per-ability when B6 lands.
- **`ability_changed` → still wants message-box text** and is independent of
  the popup entirely: source has *"{mon} traced {mon}'s {ability}!"* and
  friends for Trace / Mummy / Receiver / Wandering Spirit. Could be carved out
  at any time.

So B6's real scope grows by one signal and shrinks D3 by three. The two
residual signals above are recorded in M26B6's own roadmap entry so they are
not lost.

*Original scoping note follows, superseded.*

### D3-2 — Abilities reach the message box (3)
`ability_triggered`, `ability_healed`, `ability_changed`. The readable
per-effect-key text **already exists** — an 86-entry `_ABILITY_TRIGGER_TEXT`
table built during M23.2 — but is tagged to the F3 panel only, so abilities are
**completely silent in normal play**. Mostly re-pointing existing content.
**Sequence with M26B6** (ability popup): that item is the *visual* banner, this
is the *text*. See §7.

### D3-3 — Move outcome (16) — **COMPLETE 2026-07-27**

**30/30** in a new `scenes/battle/m26_d3_3_move_outcome_test.tscn`; 11 further
suites green. All 16 narrate.

**The main finding: two-turn charge text is genuinely per-move.** Source has no
shared "is charging" string and **no `twoTurnAttackStringId` field** (checked) —
each two-turn move prints its own line from its own battle script. So
`_CHARGE_TEXT` is a real 16-entry table keyed by move id, not a lookup
derivable from a flag. Three pairs legitimately **share** a line in source and
that is not duplication to factor out: Solar Beam/Solar Blade
(*"absorbed light!"*), Freeze Shock/Ice Burn (*"became cloaked in a freezing
light!"*), Shadow Force/Phantom Force (*"vanished instantly!"*). **Sky Drop is
the one move whose line names its TARGET as well as its user**, so it cannot
share the single-slot shape and is handled at its own call site.

**The load-bearing guard, C.01, is data-driven**: it parses `gen_moves.py` for
every move carrying `two_turn`, and fails if any lacks a charge line. A missing
entry would otherwise degrade to a generic fallback that reads perfectly
plausibly and is wrong — the worst failure mode for text. Proven by removing
Fly's entry: C.01 named it and failed (28/30), then passed on revert.

**`move_called` is NOT a duplicate announcement, and this is asserted so nobody
"de-duplicates" it.** `move_announced` fires early
(`battle_manager.gd:1854`, before dispatch) and names the CALLING move —
Metronome, Mirror Move, Sleep Talk, Assist, Copycat, Me First — while
`move_called` fires during dispatch (`:3418+`) and names what was actually
picked. Source prints both. Without the second line a Metronome resolves with
no indication of what it rolled.

**`bide_storing` deliberately repeats `bide_started`'s line** — source reprints
the same *"is storing energy!"* on each waiting turn rather than having a
distinct second message. Asserted as two occurrences so it doesn't look like a
copy-paste slip.

**`move_effect_failed`'s `reason`** (`"stat_limit"` / `"immune"` /
`"already_status"`) is engine detail with no player-facing equivalent in
source, which prints only the generic *"But it failed!"*. The reason stays in
the debug panel's remit rather than being surfaced as text the reference never
shows.

*Original scoping note follows.*

### D3-3 — Move outcome (16)
`protected`, `protect_broken`, `substitute_created`, `substitute_broke`,
`move_effect_failed`, `crash_damage`, `endured`, `pokemon_thawed`,
`move_called`, `charge_started`, `bide_started`, `bide_storing`,
`bide_released`, `move_bounced`, `move_stolen`,
`multi_hit_sequence_finished`.
The "what just happened to my move" layer. `charge_started` is the two-turn
"X flew up high!" text the original audit flagged; `move_effect_failed` is
source's own *"But it failed!"*.

### D3-4 — Volatile infliction (32) — **COMPLETE 2026-07-27**

**56/56** in a new `scenes/battle/m26_d3_4_volatiles_test.tscn`; 13 further
suites green. 28 of 32 narrate; 4 are deliberately silent.

**Four more "silence is correct" cases**, each verified against source rather
than assumed — bringing D3's running total to **eight**:

- **`charge_cleared`** — fires when Charge's flag is CONSUMED by a later
  Electric move. Source has no consumption line; the boosted move announces
  itself.
- **`rampage_lock_started`** — Thrash/Outrage/Uproar announce the MOVE
  normally and source prints nothing for the lock itself. Only the lock
  *ending* has a line, and only for the fatigue-confusion case — so
  `rampage_lock_ended` narrates when `confused` is true and stays silent
  otherwise (the immune-cancel path).
- **`types_changed` with reason `"roost"` / `"roost_restore"`** — Roost's
  one-turn type removal and its restore are **invisible in source**: zero Roost
  strings anywhere in `battle_message.c`. Only `"reflect_type"` gets a line,
  which doubles as the non-vacuity check that the handler isn't simply dead.
- **`stockpile_released`'s `count`** — source's release line reports only that
  the effect wore off, never the stack size. Asserted that the number does not
  leak into the text.

**Two source details reproduced rather than "improved":**

- **Encore's line does not name the move.** Source uses a second, separate
  string for that; the primary line is just *"{mon} must do an encore!"*.
- **Octolock has its own line naming the cause**, distinct from the generic
  trapping line that Mean Look / Block / Spider Web / Spirit Shackle share.

**Two disclosed deviations, both the familiar "signal narrower than source's
sentence" shape** (as with D3-6's Trick Room and D3-5's wrap lines):

- **`curse_set`** — source's line is a combined cost+effect sentence naming
  BOTH battlers (*"{caster} cut its own HP and put a curse on {target}!"*), but
  the signal carries only the target. Target-side rephrasing used.
- **`perish_song_activated`** — source's line is field-wide and names nobody
  (*"All Pokémon that heard the song will faint in three turns!"*), but this
  signal fires once PER affected combatant, so printing it verbatim would
  repeat the same sentence up to four times in doubles. Per-mon phrasing used.

*Original scoping note follows.*

### D3-4 — Volatile infliction (32) — the long tail
`disabled`, `encored`, `taunted`, `tormented`, `infatuated`, `leech_seeded`,
`nightmare_set`, `curse_set`, `escape_prevented`, `octolock_set`,
`foresight_set`, `telekinesis_set`, `magnet_rise_set`, `smack_down_set`,
`ingrain_set`, `aqua_ring_set`, `imprison_set`, `perish_song_activated`,
`sure_hit_set`, `laser_focus_set`, `charge_set`, `charge_cleared`,
`stockpile_gained`, `stockpile_released`, `rampage_lock_started`,
`rampage_lock_ended`, `tar_shot_set`, `type_changed`, `types_changed`,
`yawn_set`, `destiny_bond_set`, `destiny_bond_triggered`.
The largest group and the most mechanical. Splittable further if it runs long;
nothing here depends on anything else.

### D3-5 — Residual damage/heal ticks (10) — **COMPLETE 2026-07-27**

**13/13** in a new `scenes/battle/m26_d3_5_residual_ticks_test.tscn`; 11 further
suites green. Nine of the ten narrate; the tenth is deliberately silent.

**`passive_hp_lost` is NOT wired, on purpose.** Source has no standalone
"lost HP" line for Belly Drum / Fillet Away / Clangorous Soul — it prints ONE
combined line covering cost AND effect (*"{mon} cut its own HP and maximized
its Attack!"*), and this project **already narrates the effect half** via
`stat_stage_changed`. A separate HP line would both invent text the reference
does not have and double-report a single event. Second instance of the
D3-6/`wish_scheduled` shape: the right answer for a signal is sometimes
silence, and that has to be asserted or it looks like an oversight.

**Aqua Ring and Ingrain share one signal but NOT one line.** Source gives them
different text (*"absorbed nutrients with its roots!"* vs *"A veil of water
restored {mon}'s HP!"*), so the holder's own `ingrain_active` /
`aqua_ring_active` flags disambiguate at the handler. **Ingrain is checked
first** because a mon can legitimately have both up; documented precedence,
pinned by C.03.

**Two disclosed deviations, same cause — a signal narrower than source's
line.** `wrap_damage` / `wrap_ended` name the binding MOVE in source
(*"{mon} is hurt by {move}!"*, *"{mon} was freed from {move}!"*), but this
project's signals carry only the victim, and `BattlePokemon.wrapped_by` holds
the SOURCE BATTLER rather than the move, so the name is genuinely
unrecoverable without widening the signal. Move-less rephrasings are used
rather than passing a partial line off as verbatim source wording. Same
judgement as D3-6's Trick Room set line.

**Pacing note carried forward:** this is the group that fires every turn while
its volatile is up, so it compounds with M26B4's per-turn weather pause. That
remains an M26G2 question (§7(3)) — nothing here tries to pre-solve it.

*Original scoping note follows.*

### D3-5 — Residual damage/heal ticks (10)
`curse_damage`, `nightmare_damage`, `leech_seed_drained`, `wrap_damage`,
`wrap_ended`, `ring_heal_tick`, `passive_hp_lost`, `pp_drained`, `pp_reduced`,
`pp_restored`.
End-of-turn "X is hurt by its Curse!" lines. Note these fire **every turn**, so
they interact with pacing the same way M26B4's per-turn weather replay does —
worth a look together in M26G2.

### D3-6 — Field and delayed effects (10) — **COMPLETE 2026-07-27**

**24/24** in a new `scenes/battle/m26_d3_6_field_effects_test.tscn`; 11 further
suites green. Nine of the ten now narrate; the tenth is deliberately silent
(below). All were debug-only before this, i.e. invisible in normal play.

**The finding that shaped it: `wish_scheduled` must NOT be narrated.**
`BattleScript_EffectWish` is `attackcanceler / trywish / attackanimation /
MoveEnd` — it contains **no `printstring` at all**, so source is genuinely
silent when Wish is cast and announces only the resolution
(*"{mon}'s wish came true!"*). Wiring it by symmetry with
`future_sight_scheduled` — which *does* announce its cast
(*"{mon} foresaw an attack!"*) — would have been inventing dialogue the
reference does not have. Established by reading the script directly, not
inferred from a missing STRINGID. Pinned by test C.04, and that guard was
proven to catch the mistake: temporarily wiring `wish_scheduled` failed C.04
(23/24), then passed again on revert.

**One disclosed deviation: Trick Room's set line.** Source's is
*"{mon} twisted the dimensions!"*, but this project's `trick_room_set()` signal
carries **no caster argument** at all, so the caster cannot be named without
widening the signal. A caster-less rephrasing (*"The dimensions were
twisted!"*) is used rather than silently dropping the name from source's own
wording and passing it off as verbatim. The END line needs no name and matches
source exactly.

**Strings** are source's own throughout, with `{B_ATK_TEAM1}`/`{B_ATK_TEAM2}`
rendered via the existing `_side_label()` — verified to read grammatically for
both sides in the `"%s team"` slot ("your team" / "the foe's team"). Mist's own
line resolves through `gText_PkmnShroudedInMist`, not any of the four
similarly-named Misty Terrain strings (Terrain is void in this project).
Mud/Water Sport are phrased as source phrases them — a statement about the
weakened TYPE (*"Electricity's power was weakened!"*), not about the user or
the field.

**Scope note:** screens (Reflect / Light Screen / Aurora Veil) and hazards do
NOT come through `side_condition_set` — they have their own `screen_set` /
`hazard_set` signals, already wired to the message box since the M23.2
addendum. `side_condition_set` here is Tailwind / Safeguard / Mist only.
Unrecognised names stay silent rather than emitting a malformed line (D.01).

*Original scoping note follows.*

### D3-6 — Field and delayed effects (10)
`trick_room_set`, `trick_room_ended`, `side_condition_set`,
`side_condition_expired`, `future_sight_scheduled`, `future_sight_resolved`,
`wish_scheduled`, `wish_resolved`, `healing_wish_activated`,
`field_sport_set`.
**All currently debug-only.** Trick Room, Reflect/Light Screen, Wish and Future
Sight are strategically significant and completely unannounced in normal play —
arguably the most player-affecting group after D3-1.

### D3-7 — Item interactions (9) — **COMPLETE 2026-07-27**

**25/25** in a new `scenes/battle/m26_d3_7_items_test.tscn`; 13 further suites
green. Eight of nine narrate.

**Closes §3's open item: Recycle's string is `"{mon} found one {item}!"`** —
located under wording this recon's first pass didn't pattern-match. Tar Shot,
the other open one, was resolved in D3-4 (*"became weaker to fire!"*). **Both
§3 unknowns are now settled**; nothing in D3 is left unlocated.

**`item_consumed` is deliberately SILENT — the ninth and final "silence is
correct" case.** It fires for every one-use item, but this project already
narrates each consumption's own EFFECT: `item_healed` and `status_cured` are
both log-wired, and stat-raise berries surface via `stat_stage_changed`. Source
likewise prints ONE combined line per berry (*"{mon} restored health using its
{berry}!"*), not an effect line plus a separate "used up" line. Wiring a generic
used-up message would double-report every berry. Asserted both by absence of
output AND directly (`get_connections().is_empty()`), with a non-vacuity check
that the effect signals covering it *are* wired.

**Pluck/Bug Bite gets its own line, not the steal one** — the berry is consumed
IN PLACE rather than transferred, which is exactly why source distinguishes
them (*"stole and ate its target's {berry}!"*). Pinned so the two don't get
merged.

**Four disclosed rephrasings, same shape as elsewhere in D3** — source's line
names an item or a second battler the signal doesn't carry: `item_stolen` (no
item arg), `item_damage` (amount only, no item), and several
`_ITEM_EFFECT_TEXT` entries whose source wording uses `{B_LAST_ITEM}`.

**`item_effect_triggered`'s key coverage is data-driven**, not a hand-kept
list: C.01 re-derives every `effect_key` from `battle_manager.gd` and fails if
any lacks text — same guard shape as D3-1's A.02 and D3-3's C.01.

*Original scoping note follows.*

### D3-7 — Item interactions (9)
`item_consumed`, `item_stolen`, `item_transferred`, `items_swapped`,
`berry_stolen_and_eaten`, `item_damage`, `item_effect_triggered`,
`item_recycled`, `item_regenerated`.
Also all debug-only. Confirm Recycle's exact source string here (§3).

### D3-8 — Meta-progression (5) — **COMPLETE — closes M26D3 in full.**

`exp_gained`, `level_up`, `money_awarded`, `move_learned`,
`move_learn_skipped`.

**The BLOCKED framing below is superseded, not rewritten — kept per this
doc's own convention of not rewriting a historical entry.** The block was
scheduling, not design: "wiring the text now would bake a placement
decision against a battle-end flow that M27 is expected to replace
outright." M27 has since shipped in full (M27A-O), and it did **not**
replace that flow — the overworld reuses this project's exact BATTLE_END
screen as its own landing point (`overworld._on_battle_overlay_finished`
mounts the same `battle_screen`; `overlay_mode`'s Play-Again button just
relabels to a dismissal, `_on_play_again_pressed`). Checked directly, not
assumed: neither the overworld's own money/EXP/level handling
(`OverworldSession.wallet.earn`, the battle-return party-restore path) nor
anything else anywhere connects to any of these five signals — confirmed
via grep across `scripts/overworld/*.gd`/`scenes/overworld/*.gd`. So this
was, in practice, still just silence: a real overworld trainer battle
(M27F/H) gains real EXP, levels up, and earns real money with **zero
on-screen confirmation of any of it**, exactly as in the standalone
simulator. The placement question resolves the same way every other D3
phase already did: the message box this project already has, via
`_wire_log_signals()` — `money_awarded` already fires immediately before
`battle_ended` in source order (`_phase_battle_end_check`), so it lands
right before "You win!" with zero engine-ordering change needed.

**The Mimic/Sketch carve-out this entry flagged in advance turned out to
matter for real, not just architecturally.** Re-verified against
`data/battle_scripts_1.s` directly rather than trusted from this doc's own
earlier citation: level-up and Mimic DO both render "{mon} learned
{move}!" — but from **two different STRINGIDs** (`STRINGID_PKMNLEARNEDMOVE`
for level-up, `STRINGID_PKMNLEARNEDMOVE2` for Mimic) that happen to share
rendered text, not the single shared STRINGID this doc's §3 first pass
assumed. **Sketch does NOT share either one** — it has its own distinct
string, `STRINGID_PKMNSKETCHEDMOVE` = *"{mon} sketched {move}!"* — a real
wording difference, not a formatting nuance. Since `move_learned` is one
shared signal firing from all three call sites (Mimic, Sketch, and
level-up/`_try_learn_move_at_level`) with no way for a listener to tell
them apart, the signal itself needed widening with a `kind: String` param
(`"level_up"` / `"mimic"` / `"sketch"`) — a real breaking change, not
just an additive one: Godot 4 confirmed directly (a throwaway probe
script) to **error**, not silently discard, when a connected listener has
fewer parameters than a widened signal emits. Every pre-existing listener
(`m20b_test.gd`'s 5, `mimic_sketch_test.gd`'s 1) was updated alongside it.

**Disclosed simplification**: source's gained-EXP line
(`STRINGID_PKMNGAINEDEXP`) carries a second buffer slot for a "boosted"
qualifier (Lucky Egg / trainer bonus / Exp Charm) — omitted, since this
project has no such per-recipient multiplier concept distinct from the
plain computed amount, matching the precedent every other D3 phase set
for a signal that doesn't carry a source nuance.

New `scenes/battle/m26_d3_8_meta_progression_test.gd`/`.tscn`: **15/15**,
stable across repeated runs — direct-emit text checks for all 5 signals,
the level-up-vs-Mimic-vs-Sketch wording distinction (including a
discriminator that Sketch's line does NOT contain "learned"), a real
end-to-end integration test through the actual `_award_exp_for_fainted_
opponent()` call site (proving EXP narrates before the level-up it
triggers, matching source's own per-recipient order), a real full-battle
win proving `money_awarded`'s line precedes "You win!" in the rendered
log — not just in raw signal-emission order — and a regression guard
(no attached opponent `TrainerData` → no money line, mirroring `[M24b]`'s
own already-established D3 case). Full regression: `m20b_test` 30/30,
`mimic_sketch_test` 46/46, `m24b_test` 61/61, all 8 prior COMPLETE D3
suites, `m25c_message_log_test` 19/19, `m26b_debug_log_test` 62/62,
`message_pacing_test` 69/69, `m20_exp_test` 37/37, `m20a_data_test`
387/387, `m26_trainer_category_party_test` 130/130, and both
`battle_screen_*.tscn --autoplay` runs 1/1 — all clean.

**This closes M26D3 — every one of its 9 sub-phases is now either shipped
(D3-1/3/4/5/6/7/8/9) or retired into M26B6 (D3-2), with nothing buildable
left open.**

*Original BLOCKED framing follows, superseded above.*

**Do not build this until the overworld lands.** It was started and then
**deliberately reverted** — the wiring was written, then backed out at Rob's
direction, and the code is confirmed clean (zero connects for all five
signals). This is a scheduling block, not an unresolved design question.

**Why blocked rather than merely undecided.** Meta-progression text is the one
group in D3 whose correct *placement* depends on a system that does not exist
yet. In source these lines print in the battle message box at battle end and
then the game fades back to the overworld; this project instead ends at an
invented Win/Lose screen with a Play Again button, which exists only because a
standalone simulator has nowhere to return to. Wiring the text now would bake a
placement decision against a battle-end flow that M27 is expected to replace
outright — see M35's own note that the real source-accurate battle-end
behaviour is inseparable from systems M35/M27 own (money text, seen-flags,
rematch progression).

**Step 0 findings, recorded so the blocked work doesn't need re-deriving:**

- **Timing is already correct and needs no engine change.** `exp_gained` /
  `level_up` / `move_learned` / `move_learn_skipped` all fire DURING the
  battle, on each opponent faint (`_award_exp_for_fainted_opponent`) — exactly
  source's own `Cmd_getexp` timing. `money_awarded` fires immediately before
  `battle_ended` (`battle_manager.gd:7202-7203`), also matching source.
- **Beats queued at battle-end still drain** — `_on_battle_ended`'s own
  "You win!" line already proves that path works, so a battle-end message is
  mechanically supported whenever this is picked up.
- **Strings are already located** (`battle_message.c`): *"{mon} gained {n} Exp.
  Points!"*, *"{mon} grew to Lv. {n}!"*, *"You got ¥{n} for winning!"*,
  *"{mon} learned {move}!"*, *"{mon} did not learn {move}."*
- **`move_learned` also fires for Mimic/Sketch** (`:6063`/`:6088`), not just
  level-up learning — and that is correct, since source uses the same
  `STRINGID_PKMNLEARNEDMOVE` for Mimic. Whoever picks this up should decide
  whether the Mimic/Sketch case is carved out and shipped early (it is NOT
  meta-progression and is NOT blocked on the overworld) or left bundled here.

**Carve-out worth considering when unblocking:** the Mimic/Sketch half of
`move_learned` is battle-internal and could ship independently of M27.

*Original scoping note follows.*

### D3-8 — Meta-progression (5) — **needs a decision first, see §7**
`exp_gained`, `level_up`, `money_awarded`, `move_learned`,
`move_learn_skipped`.

### D3-9 — Switch and support (10) — **COMPLETE 2026-07-27**

**18/18** in a new `scenes/battle/m26_d3_9_switch_support_test.tscn`; 13 further
suites green. Nine of ten narrate; the tenth is deliberately silent.

**The Step 0 finding that shaped the group: `_do_forced_switch_in` emits
NOTHING** — no `pokemon_switched_in`, no `pokemon_switched_out` (verified by
reading all three switch functions' emit sets). Since `pokemon_switched_in/out`
ARE already log-wired, the obvious assumption was that `forced_switch`,
`hit_escape_switch` and `hit_switch_target` would duplicate existing text.
They don't — those three are the **only** narration those switches ever get,
so Roar, Dragon Tail, Red Card, Eject Button and U-turn were all switching
Pokémon in and out in complete silence.

**`baton_passed` is the mirror image and stays SILENT** — it fires *alongside*
`pokemon_switched_out` + `pokemon_switched_in` (`battle_manager.gd:3302-3304`),
both already narrated, and source has **no Baton-Pass-specific string at all**
(zero matches). Wiring it would put a third line on an already-narrated switch.
Fourth instance of the D3 "silence is correct" pattern. Asserted **directly**
(`baton_passed.get_connections().is_empty()`) rather than inferred from absent
output, with a non-vacuity check that the switch signals it accompanies *do*
have listeners.

**U-turn is worded differently from Roar on purpose.** All three share
`_do_forced_switch_in`, but U-turn's user leaves *voluntarily*, so source's
*"was dragged out!"* would be wrong for it. Pinned by a test asserting the
U-turn line does NOT contain "dragged out".

**Two lessons worth carrying forward:**

1. **A multi-line `match` inside a connected lambda does not parse in
   GDScript.** Writing the `turn_order_changed` handler that way broke
   `battle_screen_shared.gd`'s entire parse — and it surfaced as a **hung test
   run**, not a clean error, costing two timeouts to diagnose. Use `if`/`elif`
   in lambdas. Now recorded at the call site too.
2. **Not every signal is safe to emit on a bare test instance.** The first
   draft's non-vacuity check emitted `pokemon_switched_out`, whose handler does
   more than log — it queues M26B3-6's recall animation — and hangs off-tree.
   Prefer asserting connection state over emitting heavy signals.

*Original scoping note follows.*

### D3-9 — Switch and support (10)
`forced_switch`, `baton_passed`, `hit_escape_switch`, `hit_switch_target`,
`helping_hand_used`, `follow_me_used`, `pokemon_transformed`,
`stat_changes_copied`, `pain_split_used`, `turn_order_changed`.
`turn_order_changed` is the After You/Quash splice; the rest are
straightforward.

**Recommended order:** D3-1 → D3-2 → D3-6 → D3-3 → D3-5 → D3-9 → D3-7 → D3-4,
with D3-8 gated on §7. Rationale: biggest player-visible wins first, largest
mechanical batch last.

---

## 6. Out of scope

- **`catch_attempted`** — owned by **M26B7** (Catch UI), which is the ball-shake
  animation. Text belongs with that, not here.
- **The ability popup banner** — **M26B6**. D3-2 is text only.
- **Post-battle screens** — this project's Win/Lose screen is a disclosed
  invention (source has no such screen); see M35's own note.

---

## 7. Decisions for Rob before building

**(1) Meta-progression text (D3-8).** Source prints *"{mon} gained {n} Exp.
Points!"*, *"{mon} grew to Lv. {n}!"* and *"You got ¥{n} for winning!"* **in the
battle message box**, at battle end, before returning to the overworld. This
project instead ends at an invented Win/Lose screen with a Play Again button,
because it is a standalone simulator with no overworld to return to. So the
question is not "does source have text" (it does) but **where it should go** —
the message box before the end screen, the end screen itself, or not at all.
`move_learned`/`move_learn_skipped` inherit the same question.

**(2) D3-2 versus M26B6 sequencing.** Both make abilities visible: B6 is the
sliding icon+name banner, D3-2 is the message-box line. Source has both. Doing
them independently risks either duplicated announcement or two half-solutions.
Cheapest good outcome is probably D3-2 first (text is nearly free, the table
exists) then B6 layered on — but they should at least be scoped aware of each
other.

**(3) Pacing.** D3 will add a lot of message beats, and D3-5's tick lines fire
every turn. M26B4 already made turns pause for weather animations. The combined
effect on turn length is a real M26G2 question and is worth watching as D3
lands, not after.
