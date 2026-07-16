# M22 Recon — Battle Item Actions (turn-action queue 3rd action type)

**Status: RECON ONLY — no implementation code touched this session.** Per
explicit instruction, this document proposes a design; it does not
implement anything. Companion context: `docs/m25_bag_items_recon.md`
(the full 498-item non-held-item roster scoping) already anticipated
this exact gap in its own Section B.3 ("No item-use-DURING-battle
framework exists... this is core-engine work, not UI work, and could in
principle be built earlier if Rob ever wants to decouple it from the
rest of M25") — M22 is that decoupled piece. Read that document's
Section B before this one if picking up implementation later; nothing
here duplicates it, and the minimal item set proposed in Step 4 below
was cross-checked against Section A's own category listing rather than
re-derived from scratch.

## Step 0 findings

### 1. Data model check

**Confirmed: ONE shared struct, not two parallel systems — but two
genuinely separate DISPATCH mechanisms.** Source's `struct ItemInfo`
(`include/item.h`) carries `holdEffect`/`holdEffectParam` (held-item
fields) and `battleUsage` (usable-item field) side by side in the exact
same struct, on every item, regardless of which kind of item it is —
confirmed directly, not assumed. But the two are executed through
completely different code paths: held-item triggers all route through
`ItemBattleEffects()` (confirmed via grep — every one of its ~11 call
sites in `battle_script_commands.c` passes a `holdEffect`, never a
`battleUsage`), while a bag item's `battleUsage` is read once, at
selection time, by `CannotUseItemsInBattle()` (`item_use.c:1259`) via a
`switch (battleUsage)` on the `EFFECT_ITEM_*` enum
(`include/constants/items.h:1126-1140`: `RESTORE_HP=1`,
`CURE_STATUS=2`, `HEAL_AND_CURE_STATUS=3`, `INCREASE_STAT=4`,
`SET_MIST=5`, `SET_FOCUS_ENERGY=6`, `ESCAPE=7`, `THROW_BALL=8`,
`REVIVE=9`, `RESTORE_PP=10`, `INCREASE_ALL_STATS=11` — source's own
comment marks this one "// Never called," dead code, exclude it from
scope — `USE_POKE_FLUTE=12`). The actual effect application (healing,
curing, stat-raising) happens via a further, separate byte-array
`.effect[]` field (`constants/item_effects.h`) with its own bespoke bit-
packed encoding (`ITEM0_*`/`ITEM1_*`/`ITEM3_*`/`ITEM4_*`/`ITEM5_*`
masks) — this is source's OWN representation, not something this
project should mirror byte-for-byte.

**This project's own `ItemData` (`scripts/data/item_data.gd`) already
mirrors source's shared-struct shape exactly**: `hold_effect`/
`hold_effect_param` (M18, fully built) sit alongside a `battle_usage:
int = 0` field that has existed in the schema since the M18 item-data
infrastructure session but has **never been populated on any item and
has zero read sites anywhere** (confirmed via grep of `gen_items.py`
and `item_manager.gd`) — the exact "dormant schema field carried
forward, never wired" pattern this project has hit repeatedly
(`gender_ratio`, `exp_yield`, `ItemData.pocket` before their own
fixes). **M22 has a natural, already-existing extension point — it
does not need a new parallel data structure.** What M22 DOES need,
matching source's own separation: a handful of new dedicated parameter
fields for the usable-item effect payload (heal amount, which status
gets cured, which stat gets raised) — proposed as clean, purpose-built
fields in this project's own established style (matching
`ev_boost_stat`'s precedent: a new dedicated field per concern, not an
overloaded generic one), not a port of source's bit-packed `.effect[]`
array. Exact field names are an implementation-time decision, not
locked in by this recon; a concrete direction is sketched in Step 4.

**One correctness trap flagged for implementation time**: do NOT reuse
`ItemManager.hp_threshold_berry_heal()` verbatim for bag-item HP
restoration, even though its flat-vs-percent math is exactly what a
Potion/Super Potion/Max Potion needs. That function is a BERRY-shaped
function — it threads Ripen-doubling, Gluttony's eat-early threshold,
and the Cud-Chew-style `override_item` bypass, none of which apply to
a bag item (Ripen's own gate is explicitly berry-pocket-scoped in
source; a Potion is never a berry). Reuse the underlying flat/percent
arithmetic pattern in a new, bag-item-specific function, not the
existing function itself.

### 2. Turn-order/priority of an item action

**Confirmed directly from source, not assumed from general knowledge —
and the real mechanism is simpler, and different in kind, from "treat
it as a move with infinite priority."** `battle_main.c`'s turn-order
builder (`SetActionsAndBattlersTurnOrder`, ~L4967-5010) does this in
three passes:

1. A first pass places every battler whose chosen action is
   `B_ACTION_USE_ITEM`, `B_ACTION_SWITCH`, or `B_ACTION_THROW_BALL`
   into `gActionsByTurnOrder` **in raw battler-iteration order** (0, 1,
   2, 3) — no speed comparison of any kind.
2. A second pass places every remaining (move) battler, in the same
   raw order, and rolls Quick Claw/Quick Draw for each.
3. **Only the second-pass (move) battlers are then pairwise compared**
   via `GetWhichBattlerFaster` — the comparison loop's own `if`
   guard explicitly skips any pair where EITHER side's action is
   `USE_ITEM`/`SWITCH`/`THROW_BALL`, so those battlers are never
   swapped once placed.

This means Item/Switch/Ball-throwing actions are genuinely their own
tier, ordered purely by battler index among themselves, completely
outside the priority-bracket/speed/tiebreak comparator — not "priority
+999," which would still be subject to a same-priority speed-tiebreak
among multiple such actions. **Confirmed orthogonal to M21's turn-
order-splice primitives and Trick Room**, exactly as suspected but now
verified: Trick Room only inverts the speed-tiebreak inside the
move-only comparator (`_move_action_precedes` in this project's code);
since Item/Switch/Ball actions never reach that comparator at all,
Trick Room cannot affect their ordering, and none of the item/switch
tier logic needs to know about Trick Room, priority brackets, or the
`[Turn-order-splice trio]`'s post-sort splice passes (Pursuit
interception, Round promotion, Quash's bubble) — all of which operate
strictly within the move-only tier.

**This project's own existing code already implements exactly this
rule for Switch, and cites the identical source lines** —
`battle_manager.gd`'s turn-order comparator (~line 1181-1230) already
has:
```gdscript
# Switch actions before all move actions.
# Source: battle_main.c L4967-4990 — items/switches placed before moves
# in gActionsByTurnOrder; speed sort only runs between move actors (L5004-5015).
if a_switch != b_switch:
    return a_switch
if a_switch:
    return ia < ib   # battler-index order, not speed
return _move_action_precedes(a, b, ng_active)
```
The clean generalization is to replace the `a_switch`/`b_switch`
booleans with a broader "is this battler in the no-speed-sort front
tier" check — `_chosen_switch_slots[i] >= 0 or _chosen_items[i] !=
null` — with **zero other changes** to the comparator's structure.
This is the single cleanest confirmation in this whole recon that the
mechanism generalizes for free.

### 3. Action-queue architecture

**Proposed approach: extend the existing 2-type system to 3, following
the exact shape Switch already established — do NOT build a generic
polymorphic action-type dispatcher.** Concretely:

- `_action_queues[i]` entries already use a plain `{"type": ...}`
  dict (`battle_manager.gd:334-338`) — trivially extended with a third
  literal, `{"type": "item", "item_id": int, "party_target": int}`
  (`party_target` optional, defaulting to the acting combatant's own
  active party slot — see the targeting note below). New
  `queue_item_for(combatant_idx, item_id, party_target := -1)`,
  mirroring the existing `queue_switch_for`/`queue_move_targeted`
  public test-API shape exactly (`battle_manager.gd:763-786`).
- New `var _chosen_items: Array = [null, null, null, null]` (holds an
  `ItemData` reference or null) and `var _chosen_item_targets:
  Array[int] = [-1, -1, -1, -1]` (a **party slot index**, not a
  combatant index — see below), sized to 4 exactly like
  `_chosen_moves`/`_chosen_switch_slots` already are, so doubles support
  costs nothing extra later.
- `_phase_move_selection`'s existing action-resolution `if/elif` chain
  (`battle_manager.gd:963-972`, and the mirrored AI branch at
  973-1002) gets one more `elif action["type"] == "item":` arm,
  parallel to the existing `"switch"` arm — reset `_chosen_items[i] =
  null` at the top of the loop alongside the existing
  `_chosen_switch_slots[i] = -1` reset.
- `_phase_priority_resolution`'s comparator: generalize the front-tier
  check as described in point 2 above (one-line change).
- `_phase_action_execution`: add a new early-return branch, structurally
  identical to and placed immediately after the existing switch branch
  (`battle_manager.gd:1260-1266`):
  ```gdscript
  if actor_idx >= 0 and _chosen_items[actor_idx] != null:
      var item: ItemData = _chosen_items[actor_idx]
      var target_slot: int = _chosen_item_targets[actor_idx]
      _chosen_items[actor_idx] = null
      _do_item_use(actor_idx, item, target_slot)
      _current_actor_index += 1
      _set_phase(BattlePhase.FAINT_CHECK)
      return
  ```
  **No new `BattlePhase` enum value needed** — Switch itself never got
  its own phase either; it's dispatched inline within the existing
  `ACTION_EXECUTION` phase, and Item should do the same. This is the
  single biggest risk-reduction decision in this design: `Move`'s own
  dispatch path (`PRE_MOVE_CHECKS` → `MOVE_EXECUTION`) is untouched by
  construction, since Item — like Switch — returns before ever reaching
  `_set_phase(BattlePhase.PRE_MOVE_CHECKS)`.

**One real, easy-to-miss risk found and flagged**: `_phase_move_selection`
has two LATER overrides that run after the initial action is chosen —
the choice-lock override (`mon.choice_locked_move != null and
_chosen_switch_slots[i] < 0 → _chosen_moves[i] = mon.choice_locked_move`)
and the forced-Struggle override (`_is_forced_struggle(mon) and
_chosen_switch_slots[i] < 0 → _chosen_moves[i] = _struggle_move`). Both
are currently gated ONLY on `_chosen_switch_slots[i] < 0` — if a
combatant queues an item action, neither override currently knows to
leave it alone, so a Choice-locked or Struggle-forced Pokémon whose
trainer chose to use an item this turn would have that choice silently
clobbered back into a move. **Both gates must be extended to also
check `_chosen_items[i] == null`** — a small, necessary fix flagged now
so it isn't rediscovered as a test failure during implementation.
(Real-game behavior confirms this is correct: a Choice-locked or fully-
depleted-PP Pokémon can still have its trainer use a Potion on it or
switch it out — the lock/forced-Struggle is about move SELECTION only,
never about the trainer's Bag/Switch options.)

**No interaction needed with `charging_move`/`locked_move`/
`encored_move`** — those three checks sit at the TOP of the `if/elif`
chain, before the `_action_queues` branch is ever reached, exactly the
same way they already pre-empt a queued Switch today. This project's
existing behavior (no menu access at all during a forced multi-turn
lock) already matches source (`HandleAction_UseMove` force-selects the
move without ever consulting a chosen action when `multipleTurns` is
set) — nothing new to build or verify here, item actions are excluded
by the exact same pre-existing structure switch actions already are.

**Item targeting is a PARTY SLOT, not a combatant/battle-position
index** — a genuine, source-confirmed distinction worth calling out
explicitly, since every other "target" concept in this project's action
queue (`_chosen_targets`) is a combatant index into `_combatants`. In
real source, using an item lets the trainer pick ANY party member
(active or benched) as the recipient — `gPartyMenu.slotId`
(`item_use.c`), fully independent of `battlerTarget`. `BattleParty.
members: Array[BattlePokemon]` already supports direct index access
into the full roster (bench included), so resolving `party_target`
just needs `_parties[side].members[party_target]` — confirmed this
requires no new party-side infrastructure, only a new resolution step
inside `_do_item_use`. Default `party_target` to the acting combatant's
own currently-active party index when unset, so every one of M22's own
tests can omit it for the common case (heal/cure/boost the mon
currently in battle) while the field is already there, ready for a
later menu layer to let the player pick a benched target without any
further plumbing changes.

### 4. Item categories needing an in-battle effect (minimal representative set)

Cross-checked against `docs/m25_bag_items_recon.md`'s own Section A
listing rather than re-derived. Proposed minimal set — 4 items, one
per category the task asked for, chosen to be individually simple and
mutually orthogonal (no item exercises two mechanisms at once, so a
test failure localizes cleanly to one new code path):

| Item | ID | `battle_usage` | Reuses | Genuinely new |
|---|---|---|---|---|
| Potion | 28 | `EFFECT_ITEM_RESTORE_HP` | The flat-heal ARITHMETIC pattern already proven by Oran Berry (`hold_effect_param` as a literal HP amount) — reused as a pattern, not a function call (see the Ripen trap above) | A new bag-item-specific heal-dispatch function; a new field to hold the flat amount |
| Full Heal | 48 | `EFFECT_ITEM_CURE_STATUS` | `StatusManager`'s existing status-clear primitives (the same ones Lum Berry/Aromatherapy/Heal Bell/Natural Cure already call) — a "cure everything" case is already precedented by Lum Berry's own `HOLD_EFFECT_CURE_STATUS` (all 5 non-volatile statuses) | A new bag-item cure-status dispatch branch; a mask/field for which status(es) a given cure item targets (Antidote/Burn Heal/etc. would each need a narrower value later — out of M22's own minimal set, but the field should support it) |
| X Attack | 121 | `EFFECT_ITEM_INCREASE_STAT` | **Fully reusable, zero new mechanism** — this is the exact same self-targeted `+1` stat-stage raise Growth/Swords Dance/every stat-changing move already performs via `StatusManager.apply_stat_change`; stat stages are already inherently battle/switch-scoped in this engine, so "lasts only for this battle" needs no new concept at all | Nothing beyond the dispatch branch itself and reading the target stat off a new field (matching the `ev_boost_stat` STAT_*-ordinal-field precedent) |
| Poké Ball | 1 | `EFFECT_ITEM_THROW_BALL` | The action-queue/turn-order mechanism itself (this session's whole point) | A deliberately-stubbed catch outcome — see Step 5 |

**Dire Hit** (`EFFECT_ITEM_SET_FOCUS_ENERGY`) and **Guard Spec.**
(`EFFECT_ITEM_SET_MIST`) are worth naming even though they're not in
the minimal 4: both are **already fully reusable with zero new
mechanism at all** — Dire Hit sets the exact same `focus_energy`
volatile the move Focus Energy already sets, and Guard Spec. sets the
exact same `_side_conditions` Mist timer the move Mist already sets.
Not included in the minimal set only because they don't add coverage
of a NEW category beyond what X Attack (stat-adjacent
volatile-vs-timer) already exercises architecturally — worth adding in
the same implementation session as a near-zero-cost addition once the
dispatch skeleton exists, but not required to prove the mechanism.

**Revive** (`EFFECT_ITEM_REVIVE`) and **Ether/Elixir**
(`EFFECT_ITEM_RESTORE_PP`) are explicitly left for M25's full-roster
pass — both need a "target a FAINTED party member" or "target one of
the mon's own 4 moves" refinement on top of the party-slot targeting
above, which is real but genuinely incremental, not a new
architectural question this recon needs to resolve now.

### 5. The Poké Ball seam

**Recommended: option (a), matching this project's own established
"stub now, un-stub later at the same call site" pattern** — cited
directly in `CLAUDE.md`'s own Build Order (M11's entry: "Un-stub the
weather-setting abilities (`Drizzle`, `Drought`) left as placeholders
in M8"). Concretely: `_do_item_use`, on `battle_usage ==
EFFECT_ITEM_THROW_BALL`, calls a new `ItemManager.attempt_catch(...)`
(name illustrative, not final) that **always returns "catch failed"**
for M22 — never a crash, never "cannot be used," never a special
not-yet-supported branch — and emits a new `catch_attempted`/
`catch_failed`-shaped signal so tests can observe the action actually
resolved. The turn is fully consumed exactly like a real (failed)
catch attempt would be, matching source's own turn-order treatment of
`B_ACTION_THROW_BALL`/item-use-as-`EFFECT_ITEM_THROW_BALL` as a
completely ordinary front-tier action.

This is confirmed as the right choice, not options (b) or (c), because:
- Source's own turn-order builder treats a thrown ball exactly like any
  other item/switch action (same tier, same code path) — there is no
  "ball throwing isn't really an action" special case anywhere in
  source to justify NOT supporting it in the queue.
- M22's own stated purpose is to prove the ACTION-QUEUE MECHANISM
  works — having one of its 4 representative items be entirely
  unsupported would leave the mechanism's most structurally-distinct
  case (the one this whole task exists partly because of) untested.
- A hardcoded-fail stub costs nothing to build, changes only the
  INSIDE of one function when M27 lands the real formula, and needs
  zero rework at the call site, `_action_queues` entry shape, or
  turn-order logic — this is precisely the Drizzle/Drought precedent.

**One open question explicitly NOT resolved here, flagged for M27's
own recon rather than guessed at now**: this project has no modeled
concept of a "wild encounter" at all (per `m25_bag_items_recon.md`'s
own Section B.4, which already flagged this as worth Rob confirming
before that sub-system gets built). A SUCCESSFUL catch would need to
end the battle and transfer the target Pokémon into the player's party
— a second, separate mechanism beyond just "the math," and moot for
M22 since the M22-era stub always fails. Left for M27 to scope, not
guessed at here.

### 6. AI consideration

**Confirmed: zero AI awareness needed for M22.** Source has a
genuinely separate, not-yet-built AI subsystem for this —
`AI_TrySwitchOrUseItem`/`ShouldUseItem` (`battle_ai_main.c:456`,
`battle_ai_items.c:28`), gated on `BATTLE_TYPE_TRAINER` and called
BEFORE `ChooseMoveOrAction` (the move-scoring logic M10 already built)
even runs — a distinct decision point, not an extension of the
existing held-item-aware move scoring M13 already built. This
project's own `TrainerAI.choose_action`/`choose_action_doubles`
currently only ever return `{"type": "switch"/"move", ...}` — correct
to leave unchanged for M22. AI item-use decision-making belongs to a
future trainer-AI milestone (matching the task's own framing of this
as M24's territory), which would extend the AI's return dict with a
third `"item"` type once it exists — the action-queue/`_action_queues`
shape this recon proposes already supports that extension for free,
with zero rework needed to the mechanism itself when that day comes.

## Sequencing proposal

1. **Action-queue infrastructure, proven with Potion alone.** Build
   `_chosen_items`/`_chosen_item_targets`, the `queue_item_for` test
   API, the turn-order-tier generalization, the `_phase_action_execution`
   branch, the choice-lock/Struggle-override guard fix, and
   `_do_item_use`'s party-slot resolution — tested end-to-end with
   ONLY Potion. This isolates every piece of genuinely new
   infrastructure from every piece of item-effect-specific logic, so a
   test failure at this stage localizes to the mechanism, not a
   specific item's math.
2. **The remaining 3 representative items** (Full Heal, X Attack, Poké
   Ball stub) — each exercises a different dispatch branch inside
   `_do_item_use` but touches zero further action-queue machinery.
   Dire Hit/Guard Spec. as a cheap addition here too, per Step 4's own
   note, if time allows.
3. **Explicitly NOT this session or the next**: the M25 full 498-item
   non-held roster (Ethers/Revives/the rest of the Vitamin family/
   Evolution Items/etc.), the real M27 catch-math formula, and any
   AI item-use logic. All three have clean, already-identified seams
   into what step 1-2 builds, and none of them block or are blocked by
   this sequencing.

No commit made this session — recon and design proposal only, per
explicit instruction.

## M22 Phase 1 — IMPLEMENTATION COMPLETE (2026-07-16, follow-up session)

**Step 0 re-verified every finding above against current code before
implementing — all held.** Two findings sharpened on re-check:

- **Point 4/5 (party-slot targeting scope) — resolved, not a fork
  needing escalation.** Re-derived Potion's own source entry directly
  (`src/data/items.h ITEM_POTION`): `.type = ITEM_USE_PARTY_MENU`, NOT
  `ITEM_USE_BATTLER` (the "auto-select in singles, choose in doubles"
  case `X Attack` uses, confirmed by checking that item's own entry
  too). This confirms Potion's real scope genuinely includes targeting
  ANY party member, active or benched, in both singles and doubles —
  not a narrower "active battler only" case. Confirmed this is NOT a
  bigger architectural lift: `BattleParty.members` is a plain array, so
  resolving a benched slot costs nothing beyond resolving an active one
  (`_parties[side].members[party_target]`, identical code path either
  way). Shipped with full party-slot targeting, including a benched-
  target test, per the recon's own proposed design — no scope question
  remained once this was traced through, so implementation proceeded
  without stopping to ask.
- **A third real, previously-unflagged bug found this session** (beyond
  the recon's own point 3): two more turn-order-splice call sites
  (`_apply_quash_bubble`'s defensive switch-guard, and `_is_last_to_move`
  — Analytic's "am I the last to move" check) both read
  `_chosen_switch_slots` alone to detect "not a pending move action,"
  the same gap class as the choice-lock/Struggle fix. `_is_last_to_move`
  specifically would have been factually WRONG (not just defensively
  unreachable) the moment an item action existed in the turn order.
  Both extended to also check `_chosen_items`.

**Shipped:**
- `_chosen_items`/`_chosen_item_targets` arrays (sized to 4, doubles-
  ready), initialized at both `start_battle_with_parties`/
  `start_battle_doubles` entry points.
- `queue_item_for(combatant_idx, item_id, party_target := -1)` — new
  public test API mirroring `queue_switch_for`/`queue_move_targeted`.
- `_phase_move_selection`: new `"item"` arm in the action-queue
  resolution `if/elif` chain, resolving `party_target` to the acting
  combatant's own active party slot when unset
  (`_parties[side].active_indices[field_slot]`).
- **Fixed the real pre-existing bug** (recon point 3): the choice-lock
  and forced-Struggle overrides now both also check
  `_chosen_items[i] == null` before clobbering the chosen action.
- **Fixed the two newly-found analogous gaps**: `_apply_quash_bubble`'s
  guard and `_is_last_to_move` both now also recognize an item action
  as "not a pending move."
- Turn-order comparator generalized from `a_switch`/`b_switch` (pure
  switch check) to `_chosen_switch_slots[i] >= 0 or _chosen_items[i] !=
  null` — the one-line change the recon predicted, no new turn-order
  logic written.
- `_phase_action_execution`: new early-return branch mirroring the
  existing Switch branch exactly, dispatching to new `_do_item_use`.
  No new `BattlePhase` enum value.
- `_do_item_use(actor_idx, item, party_target)`: resolves the target
  via `_parties[side].members[party_target]`, dispatches on
  `item.battle_usage`. Only `BATTLE_USE_RESTORE_HP` (Potion) wired.
- New `ItemManager.BATTLE_USE_RESTORE_HP` constant and
  `ItemManager.bag_item_heal(target, item)` — a fresh, small function
  reusing only the flat-heal ARITHMETIC pattern from
  `hp_threshold_berry_heal`, deliberately NOT calling that function
  directly (it carries Ripen/Gluttony/Cud-Chew baggage a bag item must
  not inherit, confirmed at recon time). Reproduces source's exact
  restriction (`hp == 0 || hp == maxHP → no effect`) as a pure no-op
  arithmetic clamp, since this project's action-queue mechanism has no
  menu-legality layer to reject an invalid choice at selection time
  (that's M25's own future territory).
- New signal `item_action_used(user, item, target)` — deliberately NOT
  a reuse of the existing `item_consumed` signal, whose established
  meaning in this codebase is coupled to a HELD item being removed from
  `mon.held_item` (Unburden/`last_consumed_berry` etc.), which doesn't
  apply to a bag-item use. The heal itself reuses the existing
  `item_healed` signal directly, since that one's semantics ("this mon
  was healed by this amount due to an item") genuinely do apply
  unchanged.
- Potion (ID 28) added to `gen_items.py`/`ItemRegistry` —
  `battle_usage = BATTLE_USE_RESTORE_HP`, `hold_effect_param = 20`
  (reusing the same field source itself reuses — Potion has no
  `holdEffect` at all, so there's no conflict, matching the established
  "pragmatic field-repurposing" precedent from Multitype's Plate-type
  read of the same field).

**Test-audit-first pass found a real, generalizable gap**: one existing
file, `scenes/battle/turn_order_splice_test.gd`, manually constructs
`BattleManager` state and calls `_phase_priority_resolution()` /
`_phase_move_execution()` directly (this project's established direct-
dispatch test convention) without ever setting `_chosen_items` — since
that array now gets read unconditionally by the generalized comparator,
`_apply_quash_bubble`, and `_is_last_to_move`, every one of that file's
8 manually-constructed `BattleManager` fixtures needed a matching
`_chosen_items = [null, ...]` sizing line added (an all-null array is
the correct "nothing changed" fixture for every one of those tests,
none of which exercise item actions). Fixed all 8 sites; confirmed
26/26 clean afterward, stable.

**New test coverage**: `scenes/battle/m22_item_action_test.gd`/`.tscn`,
33 assertions across 8 sections — data integrity; singles basic heal
(partial-HP target, verified via both the `item_healed` signal and
final HP); bench targeting (explicit `party_target` to a non-active
party slot, confirming the active mon is untouched); doubles targeting
(the acting combatant differs from the chosen target — A0 uses the
item, explicitly targets A1); Potion's own two restrictions (already-
full-HP and fainted-target, both proven as a true no-op — the action
still resolves, `item_action_used` still fires, but no heal happens);
turn-order generalization (a deliberately much SLOWER item-user still
resolves first, ahead of a much faster move-user; an item action and a
switch action share the front tier in raw battler-index order); the
choice-lock and forced-Struggle fixes (each with its own dedicated test
proving the queued item survives instead of being overridden); two
negative controls (ordinary move-vs-move and move-vs-switch turns are
completely unaffected by the new action type's existence). All pass,
stable across 4 reruns.

Two real test-authoring bugs caught and fixed while writing this
file's own fixtures (not production bugs): (1) every manually-
constructed `BattleManager` in this new file also needed its own
`_chosen_moves`/`_chosen_switch_slots`/`_chosen_targets`/`_chosen_items`/
`_chosen_item_targets` arrays pre-sized before calling
`_phase_move_selection()` directly — `start_battle*()` normally does
this, but a direct-dispatch test must do it itself (an empty typed
array can't be assigned into by index, unlike a normal push). (2) the
default test-fixture mon originally defaulted to Tackle for "the
opponent acts normally" filler turns — this confounded every HP-delta
assertion once the front-tier ordering correctly let the item's heal
resolve first, since the opponent's Tackle then landed on the healed
target afterward in the same turn; fixed by defaulting fixtures to
Splash (a genuine no-op move) instead, isolating the item mechanism's
own effect cleanly.

**Regression**: full sweep run twice via the hardened absolute-path
invocation (the second attempt's first try produced an empty log with
no file written at all — the same still-open transient sweep-dispatch
flakiness class flagged in earlier sessions' decisions.md entries,
resolved by a bare retry with no other change) — **136 files, GRAND
TOTAL 13420, 0 failures both runs**, identical both times.

**Deliberately NOT built this session, per the recon's own proposed
sequencing — next session's scope** *(accurate as of Phase 1's own end;
all 3 items below shipped in the M22 Phase 2 section further down this
document — see that section for what actually changed)*:
- **Full Heal** (`BATTLE_USE_CURE_STATUS`) — status-cure dispatch.
- **X Attack** (`BATTLE_USE_INCREASE_STAT`) — active-battler-only
  targeting (the `ITEM_USE_BATTLER` case), reusing the generic stat-
  change dispatch directly.
- **Poké Ball placeholder** (`BATTLE_USE_THROW_BALL`) — the stubbed-
  fail `attempt_catch()` seam, matching the Drizzle/Drought "stub now,
  un-stub at M27" precedent.
- Dire Hit/Guard Spec. as a cheap addition alongside the above, per the
  recon's own note (zero new mechanism — reuses Focus Energy's
  `focus_energy` volatile and Mist's `_side_conditions` timer directly)
  — still NOT built as of the end of M22 Phase 2 either; remains a
  future near-zero-cost addition, not required for M22's own minimal set.

No commit made this session — per standing instruction, Rob commits.

## M22 Phase 1 verification pass — COMPLETE (2026-07-16, follow-up session)

**Part A — the original 2-minute hang, root-caused and empirically
reproduced, not just inferred.** Reconstructed the exact pre-fix state
from this session's own conversation history: at the moment of the
hang, `_dispatch_one_turn` was an UNBOUNDED `while bm.get_phase() !=
END_OF_TURN: bm._dispatch_phase()` (no `phase_before`/cap check), and
`_make_singles_bm`'s manually-constructed `BattleManager` fixtures had
NOT yet initialized `_chosen_moves`/`_chosen_switch_slots`/etc. to sized
arrays (the `_init_chosen_arrays` helper didn't exist yet — it was
added later, in direct response to the "Invalid assignment" errors
that appeared only AFTER the loop was bounded). Reproduced this exact
combination standalone (a throwaway scratch scene, deleted after use):
**1,631,157 iterations in 8 seconds, `_phase` permanently stuck at
MOVE_SELECTION (value 1)**, every iteration hitting the identical
`Invalid assignment of index '0' (on base: 'Array[int]')` error at
`_phase_move_selection`'s first array write. Confirmed the causal
chain precisely: that error does not raise a catchable exception in
GDScript, so `_phase_move_selection()` never reaches its own
`_set_phase(PRIORITY_RESOLUTION)` call at the end — the phase never
advances, and an unbounded caller-side loop spins on the identical
error forever.

**Confirmed this is NOT a latent production bug.** The REAL production
entry point, `advance()` (used by every actual `start_battle*()` call),
already has its own `phase_before` check
(`if _phase == phase_before: break`) plus a `MAX_PHASES_PER_ADVANCE =
4096` hard cap — inspected directly, confirmed unconditional and
already present before this session touched anything. Had this exact
array-sizing bug ever occurred through the real production path,
`advance()` would break out after exactly one stalled dispatch, not
hang. The hang was entirely confined to `m22_item_action_test.gd`'s own
hand-rolled `_dispatch_one_turn` helper, which simply hadn't yet
replicated `advance()`'s own pre-existing stall-detection when first
written — already fixed in the same original session (the
`phase_before`/`guard < 200` check present in the shipped file). No
production code change was made or needed in this verification
session — confirmed via direct diff against a pre-session backup that
`battle_manager.gd` is byte-identical before and after.

**Part B — re-read all 33 (now 38) assertions for correctness, not just
pass/fail. Found and fixed three real gaps, all confirmed empirically
(each fix verified to actually flip a targeted, temporarily-reverted
production behavior from fail to pass, not just asserted from
reading):**

1. **Section G (choice-lock/forced-Struggle fix) — both tests' original
   assertions didn't discriminate the fix at all.** `_phase_
   action_execution` checks `_chosen_items` BEFORE it ever looks at
   `_chosen_moves`, so the dispatch OUTCOME (item resolves, heal
   applies) is invariant regardless of whether the choice-lock/
   Struggle guard exists — confirmed by temporarily stripping the
   `_chosen_items[i] == null` guard from production code and re-running:
   the suite still reported all original assertions passing. Fixed by
   adding a new, earlier check directly on the SELECTION-phase property
   the fix actually changes: `bm._chosen_moves[0] == null` after a
   direct `_phase_move_selection()` call (proving the override was
   correctly skipped, not just that its result happened to not matter
   downstream). Re-verified: with the guard stripped, these new
   assertions correctly fail; restored, they correctly pass. The
   original dispatch-outcome assertions were kept alongside (not
   removed) since they're still valid confirmations of true end-to-end
   behavior, just not fix-discriminating on their own.
2. **Section H2 (move-vs-switch negative control) — didn't discriminate
   switch-tier placement from plain speed at all.** The original
   fixture made the SWITCHING mon faster than the move-user, so the
   assertion (switcher sorts first) would hold even with switch-tier
   placement entirely disabled — confirmed by temporarily hardcoding
   the front-tier check to `false` for both sides and re-running: this
   specific test still passed while every genuine front-tier test
   correctly failed. Fixed by swapping the speeds (switcher now
   deliberately SLOWER than the move-user) — re-verified this correctly
   flips to failing when the front-tier check is disabled, and passes
   with it restored.
3. **Section B (singles basic heal) — a label/assertion mismatch.** The
   assertion claimed to verify "the real user/item/target" but only
   ever checked user and target, never the item itself (`used_events[0][1]`
   was unchecked). Fixed to also confirm the item matches
   `_load_item(28)` (verified `ItemRegistry`'s `ResourceLoader.load`
   caching makes this a valid reference-equality check, matching
   Section A's own established pattern).

**Confirmed sound, no changes needed** (independently re-derived, not
assumed): the bench-targeting (Section C) and doubles-targeting
(Section D) tests are NOT vulnerable to a "silently defaults to self"
false-positive — in both fixtures the would-be wrong fallback target
(the active mon / the acting combatant) starts at full HP by
construction, so a mistargeting bug would produce ZERO heal (`healed_
events` empty), which the existing `healed_events.size() == 1 and
healed_events[0][0] == <real target>` assertion would correctly catch
as a failure, not a coincidental pass. Sections F1/F2 (turn-order
generalization) were independently confirmed to be genuine
discriminators via the same front-tier-disabled experiment used for
H2 — both correctly failed when disabled. One additional consistency
strengthening (not a correctness bug): Section E2 (fainted target)
gained an `item_action_used` check matching E1's own more thorough
pattern, confirming the action still resolves as an attempt rather
than being silently rejected outright.

**Final assertion count: 38** (33 original + 2 choice-lock + 2 forced-
Struggle + 1 item-identity check − 0 removed, net +5 from strengthening
plus the E2 addition already counted in the +5). Stable across 3
reruns. Full regression: **136 files, GRAND TOTAL 13425, 0 failures**
(13420 prior + 5 new assertions here), confirmed via the hardened
absolute-path sweep invocation. `battle_manager.gd` confirmed
byte-identical to its pre-verification-session state — this was a
test-quality pass only, no production code changed.

**Verdict: PASS.** The original hang is fully explained (a test-helper
omission, not a production robustness gap — production's own
`advance()` was already safe) and does not need a production fix. All
38 assertions now genuinely discriminate the behavior their labels
claim, confirmed empirically rather than by inspection alone for every
finding in this pass.

No commit made this session — per standing instruction, Rob commits.

## M22 Phase 2 — IMPLEMENTATION COMPLETE (2026-07-16, follow-up session)

**M22's minimal representative item set is now complete: Potion + Full
Heal + X Attack + the Poké Ball placeholder — all 4 items the recon's
own Step 4 proposed.** Step 0 re-verified each item fresh from source
rather than assuming Phase 1's Potion design transfers unchanged —
found real, item-specific wrinkles on all three:

- **Full Heal cures more than "all non-volatile status."** Source's own
  `gItemEffect_FullHeal[3] = ITEM3_STATUS_ALL` resolves (via
  `GetItemStatus1Mask`) to `STATUS1_ANY|STATUS1_TOXIC_COUNTER`, but the
  real execution function, `BS_ItemCureStatus`, ALSO separately calls
  `ItemHealMonVolatile` — which cures confusion AND infatuation for
  this specific item (confirmed via its own `effect[3] & ITEM3_STATUS_
  ALL` branch). Source restricts that volatile-cure half to the ACTIVE
  battler (or its doubles partner) only — confirmed this project's own
  architecture makes that restriction moot: `_clear_volatiles`
  unconditionally zeroes both `confusion_turns` and `infatuated_by` on
  every switch-out, so a benched `BattlePokemon` here can never carry
  either state to begin with. The cure was implemented uniformly
  (status + confusion + infatuation, regardless of active/benched) with
  zero behavioral difference from source in any observable case. New,
  dedicated `ItemManager.bag_item_cure_status()` — deliberately NOT a
  reuse of `status_cure_berry_cures` (Unnerve/Cud-Chew baggage) or
  `BattleManager._apply_heal_bell` (confirmed via direct read to only
  ever clear `.status`, correct for Heal Bell/Aromatherapy's real
  narrower scope but wrong for Full Heal).
- **X Attack raises Attack by +2 stages, not +1**, at this project's
  `GEN_LATEST` config (`X_ITEM_STAGES`, `src/data/items.h:13`,
  `B_X_ITEMS_BUFF>=GEN_7`, confirmed true here). Fully reuses
  `StatusManager.apply_stat_change` directly — already naturally
  no-ops at max stage, zero new stat-stage logic needed, exactly the
  "near-zero-cost addition" the recon predicted. New
  `ItemData.stat_boost_stage` field, deliberately kept SEPARATE from
  `ev_boost_stat` (M20c) — the two use different stat orderings
  (`STAGE_*` vs `STAT_*`) for unrelated mechanics; conflating them would
  silently reproduce this project's own documented Nature/Hidden-Power
  "Speed ordering" pitfall. Confirmed source's `hp==0` menu-legality
  gate reproduces as a pure no-op here (matching Potion's own
  precedent), while Full Heal deliberately carries NO such gate
  (confirmed via direct read that `CannotUseItemsInBattle`'s
  `EFFECT_ITEM_CURE_STATUS` case has no `hp==0` check at all — curing
  status doesn't require the target to be conscious/on-field).
- **The Poké Ball placeholder needed a genuinely new targeting branch —
  the one real design gap Phase 1's model didn't anticipate.** Every
  item Phase 1 built (and Full Heal/X Attack too) targets a PARTY SLOT
  on the ACTING TRAINER'S OWN SIDE. A Poké Ball targets the OPPONENT —
  confirmed via source (`.type = ITEM_USE_BAG_MENU`, no party-menu step
  at all, unlike Potion/Full Heal's `ITEM_USE_PARTY_MENU` or X Attack's
  `ITEM_USE_BATTLER`). Resolved by having `_do_item_use`'s Ball branch
  read `_chosen_targets[actor_idx]` instead of `party_target` — the
  SAME combatant-index mechanism every foe-targeting MOVE already uses,
  requiring zero new infrastructure, just a new consumer of an existing
  field. `queue_item_for` gained an optional `target_idx` param
  (mirroring `queue_move_targeted`'s own shape) for the doubles case
  (choosing between the two opposing slots). Confirmed via direct
  empirical disable-and-verify (see Test results below) that this is a
  real, load-bearing design decision, not an assumption.
- **The consumption/bag-inventory question — confirmed a non-issue, not
  a new scope question requiring escalation.** This project has zero
  bag/inventory infrastructure (`docs/m25_bag_items_recon.md` Section
  B.1, re-confirmed rather than assumed stale), and Potion already
  established in Phase 1 that M22's action-queue model doesn't depend
  on any such infrastructure — items are dispatched by `item_id`
  reference, not drawn from a tracked stock. The Poké Ball placeholder
  introduces nothing new here: it's exactly as consumption-free as
  Potion, Full Heal, and X Attack. `ItemData.not_consumed` stays
  unpopulated for all 4 items, matching this project's own established
  "dormant field, no current mechanic reads it" precedent. **No
  escalation was warranted** — re-traced to confirm this before
  proceeding rather than assuming.
- Confirmed source's `GetBallThrowableState` (the real menu-legality
  gate for ball-throwing) has no explicit trainer-battle check at all —
  the real "no balls in trainer battles" rule must live at a menu/item-
  filtering layer this project doesn't model (this project also has no
  wild-encounter concept at all, per the M25 recon's own Section B.4) —
  flagged as a known, disclosed non-modeling, not attempted.

**Shipped:**
- `ItemData.stat_boost_stage: int = -1` — new field, documented
  explicitly against `ev_boost_stat`'s different ordinal to avoid
  future confusion.
- `gen_items.py`: `BATTLE_USE_CURE_STATUS`/`INCREASE_STAT`/
  `THROW_BALL` constants, `STAGE_ATK` constant, `stat_boost_stage` added
  to `DEFAULTS`/`FIELD_ORDER`, 3 new item entries (Full Heal ID 48, X
  Attack ID 121, Poké Ball ID 1) — 160 total `.tres` items now (157
  prior + 3).
- `ItemManager`: matching `BATTLE_USE_*` constants, `X_ITEM_STAGES=2`,
  new `bag_item_cure_status(target, item) -> bool`, new
  `attempt_catch(target, item) -> bool` (the M27 stub — always returns
  `false`, with a doc comment explicitly directing a future M27 session
  to replace only this function's internals).
- `BattleManager`: new `catch_attempted(user, target, item, caught)`
  signal (deliberately separate from the generic `item_action_used`,
  which still fires for every item type including Ball); `_do_item_use`
  extended with 3 new branches (Ball's own early-return branch resolving
  target via `_chosen_targets`, then Cure-Status and Increase-Stat
  branches sharing the existing `party_target`-based resolution);
  `queue_item_for` gained the optional `target_idx` param;
  `_phase_move_selection`'s `"item"` branch reads and applies it.

**Test-audit-first pass** (Step 0 point 5): grepped for every reference
to `_chosen_items`/`item_action_used`/`BATTLE_USE_*`/`bag_item_heal`/
`queue_item_for` across the whole `scenes/battle/` suite — confirmed
only `m22_item_action_test.gd` and `turn_order_splice_test.gd` (already
fixed in the verification pass) touch this mechanism at all; no other
suite assumes item shapes are Potion-only. Reran Phase 1's own 38
assertions unchanged (38/38) before adding anything new, confirming the
new `target_idx` param and 3 new dispatch branches didn't disturb the
existing mechanism.

**New test coverage**: 26 new assertions across 3 sections (I: Full
Heal, J: X Attack, K: Poké Ball) — data integrity per item; Full Heal's
full cure (status + confusion + infatuation, the real scope beyond Heal
Bell) plus an already-healthy no-op; X Attack's real +2 boost plus an
already-max-stage no-op plus a fainted-target no-op (confirming Full
Heal deliberately has NO equivalent gate, a real asymmetry); the Poké
Ball's always-fails guarantee against a deliberately lethal-HP/asleep
target, its opponent-targeting (singles), its explicit doubles
target-choice via the new `target_idx` param, and its own front-tier
turn-order placement. **Applied the just-established "disable and
verify" discipline to the trickiest new assertion** — Poké Ball's
opponent-targeting: temporarily reverted `_do_item_use`'s Ball branch
to resolve via `party_target` (the same resolution the other 3 items
use) and reran — both the singles targeting test AND the doubles
`target_idx` test correctly failed (62/64) while every other assertion
still passed, confirming both are genuine discriminators of a real
design decision, not incidentally true. Restored (confirmed via direct
diff, byte-identical) and reran clean. One real test-authoring bug
caught and fixed on the first run (63/64): the "always fails regardless
of target state" fixture set `opp.status = STATUS_SLEEP` without also
setting `opp.sleep_turns`, so opp woke up during its own pre-move check
that same turn (a fresh instance of a documented fixture-construction
class of bug, not a production issue) — fixed by pinning
`sleep_turns = 3`.

**Final assertion count: 64** (38 prior + 26 new). Stable across 4
reruns. Full regression: two sweeps via the hardened absolute-path
invocation (the second attempt's first try produced an empty log with
no file written — the same still-open transient sweep-dispatch
flakiness class flagged in prior sessions, resolved by a bare retry) —
**136 files, GRAND TOTAL 13450 then 13449**, differing by exactly one
already-documented pre-existing flaky suite (`m18_5g_test.tscn`,
King's-Rock/Shell-Bell statistics — confirmed via direct diff of both
sweep outputs, not assumed), 0 failures traceable to this session's own
changes in either run. `move_status_table.md` confirmed untouched —
this session added zero moves.

**M22 is now fully closed against its own originally-bounded scope.**
Remaining, explicitly out of scope for M22 and left for future
milestones:
- **M25** (full 498-item non-held roster, bag/inventory data structure,
  item-use-outside-of-battle framework, real UI/menu-legality layer) —
  `docs/m25_bag_items_recon.md` remains the authoritative starting
  point.
- **M27** (the real Poké Ball catch-rate formula — species catch rate ×
  ball modifier × HP/status multipliers × shake-check RNG loop; also
  needs its own resolution of whether this project models wild
  encounters at all, per the M25 recon's own open question) —
  `ItemManager.attempt_catch()` is the exact, already-wired seam to
  replace.
- Dire Hit/Guard Spec. (flagged in Phase 1's recon as a near-zero-cost
  future addition — zero new mechanism, reuses Focus Energy's
  `focus_energy` volatile and Mist's `_side_conditions` timer directly)
  remain unbuilt, not required for M22's own minimal set.
- Any AI awareness of item actions remains fully out of scope (a future
  trainer-AI-tiers milestone's territory, per Phase 1's own confirmed
  finding that source's `ShouldUseItem`/`AI_TrySwitchOrUseItem` is a
  wholly separate, not-yet-built AI subsystem).

No commit made this session — per standing instruction, Rob commits.

## M22 Final Review — full-arc sanity pass (2026-07-16, follow-up session)

A holistic pass across all 3 prior M22 sessions together, not re-doing
what the verification pass already confirmed. **Verdict: PASS — M22 is
genuinely done and safe to commit as-is.** Two trivial stale-comment
fixes and one test-only gap closure were made; no production logic
changed.

**Check 1 (cross-session consistency)**: Phase 2 restructured
`_do_item_use` significantly (new Ball branch first, `target_mon`
resolution moved after it). Disable-and-verified a representative
Phase 1 assertion post-Phase-2: temporarily short-circuited Potion's
own `BATTLE_USE_RESTORE_HP` branch (`if false and ...`) and reran — all
of Phase 1's own heal-outcome assertions (Sections B/C/D/G) correctly
failed (56/64), confirming they're still real, non-vacuous
discriminators after Phase 2's restructuring, not accidentally made
trivially-true. Restored (byte-identical diff) and confirmed 64/64.
Did NOT re-run the turn-order disable-and-verify experiment the
verification pass already did — Phase 2 touched zero turn-order code
(confirmed via the M22-marker grep in Check 2 below), so repeating that
exact experiment with no intervening change would add no new
information.

**Check 2 (full diff read, final cumulative state)**: Read
`item_data.gd`, `gen_items.py`'s full M22 footprint, and every M22-
marked block in `item_manager.gd`/`battle_manager.gd` end-to-end.
**Found and fixed 2 real stale comments** (both harmless — pure
documentation drift, no logic implicated):
1. `item_manager.gd`'s `BATTLE_USE_*` constants block still said "Only
   RESTORE_HP is wired so far... left for M22's later sessions" —
   stale since Phase 2 wired 3 more. Updated to list all 4 as wired and
   correctly frame the rest of source's enum as M25's future scope.
2. `_do_item_use`'s own doc header still said "Only EFFECT_ITEM_
   RESTORE_HP is wired so far (Potion)... added in a later session" —
   the exact Phase-1-era description of the function, unchanged text
   even after Phase 2 quadrupled its dispatch branches. Rewritten to
   describe the function's actual final shape (all 4 items, the Ball's
   deliberate `party_target`-bypass exception called out explicitly).

No dead code or leftover TEMP/debug artifacts were found — both
disable-and-restore experiments from the verification pass and this
session's own new one were confirmed byte-identical via direct `diff`
against a pre-experiment backup before this review even started
touching anything, and again after this session's own experiment.
Signal-emission consistency confirmed clean: `item_action_used` fires
unconditionally for all 4 items (either at the shared `target_mon`
resolution point, or explicitly in the Ball's own early-return branch);
each item's own specific signal (`item_healed`/`party_status_cured`/
`stat_stage_changed`/`catch_attempted`) fires only when something
genuinely changed, except `catch_attempted`, which deliberately always
fires since the outcome itself (including "false") is the informative
content — no item silently skips an event a sibling item of the same
shape fires.

**Check 3 (doubles correctness sweep) — found one real, narrow gap,
closed with a test-only addition.** X Attack needs no doubles-specific
test: it shares the exact `_parties[side].members[party_target]`
resolution Potion's own Section D doubles test already proves correct,
and `StatusManager.apply_stat_change`'s ability-blocking logic only
ever gates NEGATIVE changes (confirmed via direct read) — X Attack's
strictly-positive raise has no analogous doubles risk. **Full Heal was
genuinely under-tested**: its singles test only exercises the self-cure
case, where the only non-self target is always a BENCHED party member
(confusion/infatuation provably always 0 there). The one case source's
own restriction (`ItemHealMonVolatile`, active battler OR doubles
partner) is actually about — curing an ACTIVE ALLY's confusion/
infatuation in doubles — was never exercised. Confirmed via code
reading that the implementation has no active/benched branching at all
(so it almost certainly already works), but this was asserted, not
proven, until this session. Added
`_test_full_heal_cures_active_ally_confusion_in_doubles` (3 new
assertions) — passed clean on the first run, confirming the
"apply uniformly" implementation choice was correct in the one
scenario that could have distinguished it from a naive active-only
port.

**Check 4 (turn-order proxy-pattern sweep) — the highest-value check,
came back clean.** Grepped every one of the 17 `_chosen_switch_slots[`
occurrences in `battle_manager.gd` and individually classified each:
writes (no concern), the 2 sites Phase 1 already fixed
(`_apply_quash_bubble`, `_is_last_to_move`), the comparator (already
fixed), the choice-lock/Struggle guards (already fixed), and 5 more
read sites re-examined fresh — the M17f trapping gate (line ~1089,
correctly switch-specific: trapping is irrelevant to item use), the
Quick Draw/slow-effect precompute (line ~1231, reads `_chosen_moves`
which is already null for an item action — computed but never
consumed for item-choosers either way, since the front-tier check
short-circuits before `_move_action_precedes` is ever reached), Pursuit's
own `_pursuit_targets_switcher` and `_apply_pursuit_interception` (lines
~8093-8166, correctly switch-only by design — Pursuit's power-double
and interception have no item-action equivalent in the real game
either), and Round's turn-order promotion (line ~8191, same "reads
`_chosen_moves`, already null" safety as the Quick Draw precompute).
**No third missed site was found** — the 2 sites Phase 1 fixed were
the only ones that needed it.

**Check 5 (test file organization)**: `m22_item_action_test.gd`'s 12
section headers (A-K, in call order matching `_ready()`) are clean,
sequential, and non-duplicated across all 67 assertions. One minor,
non-blocking observation: `_make_singles_bm`'s returned `party0`/`party1`
dictionary keys are never read by any caller — harmless unused surface
area, not dead code, left as-is (plausibly useful for a future test).

**Check 6 (docs/m22_recon.md coherence)**: the document reads
coherently end-to-end. One minor staleness found and fixed: Phase 1's
own closing "Deliberately NOT built this session — next session's
scope" list (Full Heal/X Attack/Ball) could read as a live TODO to a
reader who stops before the Phase 2 section further down — added an
inline forward-pointer clarifying it's accurate as of Phase 1's own end
and that all 3 shipped in Phase 2 (Dire Hit/Guard Spec. correctly
remains the one item still genuinely unbuilt). No contradictions found
between sessions' own claims.

**Final assertion count: 67** (64 prior + 3 new). Stable across 4
reruns. Full regression: two sweeps via the hardened absolute-path
invocation (the second attempt's first try again produced an empty log
— the same still-open transient flakiness, resolved by a bare retry) —
**136 files, GRAND TOTAL 13453 both times, identical, 0 failures**.

**M22 is genuinely done.** All 4 minimal representative items work
correctly individually and in combination, the turn-order generalization
has no missed proxy-pattern site, doubles behavior is now fully
verified (not just assumed) for all 4 items, and the documentation
record is internally consistent. Safe to commit as-is — no follow-up
session required before moving to M23.

No commit made this session — per standing instruction, Rob commits.
