class_name BattlePokemon
extends RefCounted

# Primary status condition constants (a Pokémon can have at most one at a time)
const STATUS_NONE: int     = 0
const STATUS_BURN: int     = 1
const STATUS_FREEZE: int   = 2
const STATUS_PARALYSIS: int = 3
const STATUS_POISON: int   = 4
const STATUS_TOXIC: int    = 5
const STATUS_SLEEP: int    = 6

# IV/EV index constants (both arrays are length-6, same order)
const STAT_HP: int      = 0
const STAT_ATK: int     = 1
const STAT_DEF: int     = 2
const STAT_SPATK: int   = 3
const STAT_SPDEF: int   = 4
const STAT_SPEED: int   = 5

# Stat stage index constants (stat_stages array, length 7)
const STAGE_ATK: int      = 0
const STAGE_DEF: int      = 1
const STAGE_SPATK: int    = 2
const STAGE_SPDEF: int    = 3
const STAGE_SPEED: int    = 4
const STAGE_ACCURACY: int = 5
const STAGE_EVASION: int  = 6

# [M18.5d] Resolved per-instance gender. A clean small enum for this project's
# own code (matching STATUS_*/STAGE_* above), distinct from
# PokemonSpecies.gender_ratio's raw source-matching byte encoding (0-255,
# thresholded against a roll — see _roll_gender below).
const GENDER_MALE: int       = 0
const GENDER_FEMALE: int     = 1
const GENDER_GENDERLESS: int = 2

# [M18.5h-1] Nature constants, matching source's NATURE_* ordinal order exactly
# (include/constants/pokemon.h L52-76) so a future forced_nature caller (M24
# trainer data) can use the same ordinal source itself documents. 5 neutral
# natures (no stat effect): HARDY, DOCILE, SERIOUS, BASHFUL, QUIRKY.
const NUM_NATURES: int = 25
const NATURE_HARDY: int   = 0   # Neutral
const NATURE_LONELY: int  = 1   # +Atk -Def
const NATURE_BRAVE: int   = 2   # +Atk -Speed
const NATURE_ADAMANT: int = 3   # +Atk -SpAtk
const NATURE_NAUGHTY: int = 4   # +Atk -SpDef
const NATURE_BOLD: int    = 5   # +Def -Atk
const NATURE_DOCILE: int  = 6   # Neutral
const NATURE_RELAXED: int = 7   # +Def -Speed
const NATURE_IMPISH: int  = 8   # +Def -SpAtk
const NATURE_LAX: int     = 9   # +Def -SpDef
const NATURE_TIMID: int   = 10  # +Speed -Atk
const NATURE_HASTY: int   = 11  # +Speed -Def
const NATURE_SERIOUS: int = 12  # Neutral
const NATURE_JOLLY: int   = 13  # +Speed -SpAtk
const NATURE_NAIVE: int   = 14  # +Speed -SpDef
const NATURE_MODEST: int  = 15  # +SpAtk -Atk
const NATURE_MILD: int    = 16  # +SpAtk -Def
const NATURE_QUIET: int   = 17  # +SpAtk -Speed
const NATURE_BASHFUL: int = 18  # Neutral
const NATURE_RASH: int    = 19  # +SpAtk -SpDef
const NATURE_CALM: int    = 20  # +SpDef -Atk
const NATURE_GENTLE: int  = 21  # +SpDef -Def
const NATURE_SASSY: int   = 22  # +SpDef -Speed
const NATURE_CAREFUL: int = 23  # +SpDef -SpAtk
const NATURE_QUIRKY: int  = 24  # Neutral

var species: PokemonSpecies = null
var nickname: String = ""
var level: int = 1
# [M18.5d] Rolled once in from_species() (see _roll_gender), matching the
# species' gender_ratio. Freely reassignable afterward like every other field
# here — future gender-aware mechanics (Attract, M18.5e) should just set this
# directly on a test fixture, the same way every other field in this class is
# already hand-set by this project's ~70 existing `_make_mon`-style test
# helpers, rather than needing a new forcing seam.
var gender: int = GENDER_MALE

# [M18.5h-1] Rolled once in from_species() (see _roll_nature), uniform 1/25 unless
# a forced_nature override is threaded through from_species — see _roll_nature's
# own doc comment for why this field, unlike gender, needed an explicit forcing
# parameter rather than relying on post-construction reassignment alone (M24
# trainer data will need to assign SPECIFIC natures, not a random roll). Freely
# reassignable afterward like every other field here.
var nature: int = NATURE_HARDY

# [M19-pre1] Set once in from_species() (see _default_friendship) from the
# species' own base_friendship — NOT randomly rolled (friendship isn't a
# personality-derived stat like gender/nature/IVs), but still needs the same
# forcing-parameter shape (forced_friendship) since M24 trainer data will need
# to assign SPECIFIC friendship values (e.g. a maxed-friendship starter), the
# same real requirement Nature/IVs already established this convention for.
# Freely reassignable afterward like every other field here. Used by
# Return/Frustration/Pika Papow/Veevee Volley's power calculation
# (move.is_return_power / move.is_frustration_power).
var friendship: int = 50

# Current battle HP and computed stats (not base stats — those live on species)
var current_hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0
var sp_attack: int = 0
var sp_defense: int = 0
var speed: int = 0

# [M18.5h-2] IVs: rolled once in from_species() (see _roll_ivs), independent
# real 0-31 per stat unless a forced_ivs override is threaded through
# from_species. Index order matches STAT_* constants above. Freely
# reassignable afterward like every other field here.
# EVs: still zeroed in from_species() — EV gain is out of scope for all of
# M18.5h (deferred to land with M20); the formula's own floor(ev/4) term is
# already correctly wired (confirmed [M18.5h-1]/[M18.5h-2]), just fed zero.
var ivs: Array[int] = []
var evs: Array[int] = []

# Up to 4 moves. current_pp is parallel to moves.
var moves: Array = []  # Array of MoveData
var current_pp: Array[int] = []

var ability: AbilityData = null
var held_item: ItemData = null  # null = no item

var status: int = STATUS_NONE
var sleep_turns: int = 0    # turns of sleep remaining (set on application)
var toxic_counter: int = 0  # bad-poison escalation counter; 0 before first EOT tick
var confusion_turns: int = 0  # volatile; 0 = not confused; set to 2-5 on application
# M18u: Berserk Gene's confusion never wears off naturally (source: infiniteConfusion
# volatile, battle_move_resolution.c L389-393). Set true by StatusManager.
# try_apply_confusion's `infinite` param on application; every fresh application
# (infinite or not) explicitly sets this, so a later normal confusion correctly
# clears a stale true from an earlier Berserk Gene use. Meaningless while
# confusion_turns == 0.
var infinite_confusion: bool = false
# [M18.5d-2, extended M18.5d-3] Attract's infatuation volatile. Source:
# gBattleMons[].volatiles.infatuation (battle_script_commands.c ::
# Cmd_tryinfatuating L7613-7650) — real source stores WHICH battler caused it
# (INFATUATED_WITH(battler) = battler_index + 1, include/constants/battle.h
# L347), used for (a) flavor text and (b) clearing infatuation if THAT SPECIFIC
# battler later leaves the field via its own switch/faint (battle_main.c
# L3167/L3281, SwitchInClearSetData/FaintClearSetData — TWO source functions,
# unified here into one, see BattleManager._clear_volatiles). [M18.5d-2]
# originally simplified this to a plain bool (no "who" tracking) and flagged
# (b) as a deliberately-not-built gap; [M18.5d-3] closed that gap by storing a
# direct BattlePokemon reference instead — this project already tracks
# "who did this to me" via direct object references elsewhere (BattleManager's
# `_last_attacker` dictionary), so a reference fits established convention
# better than reproducing source's raw battler-slot-index encoding. null = not
# infatuated; non-null = infatuated, holding a reference to the inflicting mon
# (used for the cross-battler cure check, NOT for flavor text — this project
# still has no text system, so (a) stays genuinely moot). Cleared by
# BattleManager._clear_volatiles both on THIS mon's own switch-out/faint (sets
# its own field to null) AND, via the new cross-battler scan, on every OTHER
# active battler whose `infatuated_by` pointed at a mon that just left the
# field — see the [M18.5d-3] decisions.md entry for the full citation.
var infatuated_by: BattlePokemon = null
# [M18.5f] Bind/Wrap-family trapping volatile — direct object reference to the
# battler who applied it, same shape and same reason as infatuated_by just
# above (source: wrappedBy, include/constants/battle.h L220 — an enum BattlerId
# field literally alongside INFATUATED_WITH's own encoding in the same struct).
# null = not trapped; non-null = trapped, holding a reference to the battler
# who applied it (used for the source-leaves-the-field cure check, reusing
# [M18.5d-3]'s reciprocal-scan pattern in BattleManager._clear_volatiles
# verbatim). Does NOT restrict move selection — confirmed absent from source's
# pre-move cancelers; only blocks voluntary switching (AbilityManager.is_trapped)
# and drives the end-of-turn recurring-damage tick.
var wrapped_by: BattlePokemon = null
# [M18.5f] Turns remaining on the current trap, counting down every end of turn
# UNCONDITIONALLY — even under Magic Guard, which only suppresses the damage
# itself (source: HandleEndTurnWrap, battle_end_turn.c L659-687, decrements
# wrapTurns BEFORE the Magic Guard check; same "counter still ticks" shape this
# project's own toxic_counter already established for Magic Guard). Random 4-5
# turns on application (RandomUniform, B_BINDING_TURNS >= GEN_5 branch); Grip
# Claw's 7-turn extension is out of scope — deferred to M18.5i.
var wrapped_turns: int = 0
# [M19f] Mean Look/Block/Spider Web/Spirit Shackle's escape-prevention
# volatile — direct object reference to the battler who applied it, the
# EXACT SAME shape as infatuated_by/wrapped_by above, and — per source —
# genuinely the same underlying state those two comments' own citations
# already anticipated (`AbilityManager.is_trapped()`'s own doc comment
# named "escapePrevention from Mean Look/Block/Spider Web" specifically as
# a future move-based trap to gate through it, written back at [M17f]).
# null = not trapped; non-null = trapped, holding a reference to the
# battler who applied it (used for the source-leaves-the-field cure check,
# reusing [M18.5d-3]'s reciprocal-scan pattern in
# BattleManager._clear_volatiles verbatim). No recurring damage tick (unlike
# wrapped_by) — source's MOVE_EFFECT_PREVENT_ESCAPE is a pure switch-block,
# no HP component at all.
var escape_prevented_by: BattlePokemon = null
# [D0] Leech Seed's own per-battler seeder-reference — direct object
# reference to whoever planted the seed, the exact same shape as
# infatuated_by/wrapped_by/escape_prevented_by above. null = not seeded;
# non-null = seeded, drained 1/8 max HP to `leeched_by` every end of turn
# (BattleManager._phase_end_of_turn) until the seeder itself leaves the
# field (reciprocal clear via BattleManager._clear_volatiles, the exact
# [M18.5d-3] pattern those 3 fields already established) or the seeded mon
# itself switches out/faints (its own base-case clear).
var leeched_by: BattlePokemon = null
# [D1] Lock-On(199)/Mind Reader(170) — direct object reference (held on the
# ATTACKER, unlike leeched_by/wrapped_by/etc. which are held on the VICTIM)
# to whichever opponent this mon's NEXT move is guaranteed to hit,
# bypassing both the accuracy roll AND semi-invulnerability. null = no
# active lock; non-null = guaranteed-hit target, cleared after
# `sure_hit_turns` reaches 0 (BattleManager._phase_end_of_turn) or the
# instant EITHER battler leaves the field (reciprocal clear in
# BattleManager._clear_volatiles, the same established shape
# infatuated_by/wrapped_by/escape_prevented_by/leeched_by all use — this
# is the FIFTH field using it, and the first held on the SOURCE side of
# the relationship rather than the victim side, since here the "victim"
# is just a target reference, not itself carrying any state).
var sure_hit_target: BattlePokemon = null
var sure_hit_turns: int = 0

# [D2 batch 2] Tar Shot(695) — permanent per-mon flag, no turn counter.
# Doubles the damage-multiplier effect of any Fire-type move against this
# mon for the rest of the battle (see MoveData.is_tar_shot's own doc
# comment for the full source citation). Cleared on switch-out via the
# standard `_clear_volatiles` convention — no reciprocal-clear needed
# since it isn't tied to a source battler leaving the field.
var tar_shot_active: bool = false

# [D2 batch 2] Foresight(193)/Odor Sleuth(316) — permanent per-mon flag,
# no turn counter. Bypasses this mon's own Ghost-type Normal/Fighting-
# immunity AND ignores this mon's own evasion stage for the rest of the
# battle (see MoveData.is_foresight's own doc comment for the full source
# citation). Cleared on switch-out via the standard `_clear_volatiles`
# convention.
var foresight_active: bool = false

# [D4 CHEAP bundle] Torment(259) — permanent (switch-cleared) per-mon flag
# on the TARGET, blocking use of the exact same move used on the
# immediately preceding turn. Confirmed from source (not the decoy timer-
# based `tormentTimer`/`Cmd_TrySetTormentSide` used by an unrelated
# side-wide variant this project doesn't implement) that the base move
# dispatches via `Cmd_settorment`, which sets a PLAIN bool with NO turn
# counter and NO natural expiry — checked at execution time against
# `attacker.last_move_used == move`, the exact same shape MoveData.
# cant_use_twice (Blood Moon) already established, just target-inflicted
# instead of self-inflicted. This project has no menu-legality/Struggle-
# fallback architecture (confirmed absent for Disable/Taunt/Assault Vest/
# Blood Moon too) — a Torment-blocked mon with no other legal move simply
# has its turn skipped via `move_skipped`, matching this project's existing
# behavior for every other execution-time move restriction.
# Source: battle_script_commands.c :: Cmd_settorment (L8795-8809);
# battle_util.c L1606 (MOVE_LIMITATION_TORMENTED check against gLastMoves).
var tormented: bool = false

# [D4 CHEAP bundle] Magnet Rise(506) — 5-turn self-ungrounding volatile.
# Decrements at end of turn; reaching 0 clears it. Fails to apply if the
# user already has Magnet Rise, Ingrain (root), or Smack Down active
# (source: BattleScript_EffectMagnetRise's own 2 pre-checks + Cmd_
# trysetvolatile's own already-active fail case). See AbilityManager.
# is_grounded's own doc comment for the exact priority-ordering insertion.
# Source: battle_script_commands.c, case VOLATILE_MAGNET_RISE
# (Cmd_trysetvolatile, L9277-9280); B_MAGNET_RISE_TIMER = 5
# (include/config/battle.h L208).
var magnet_rise_turns: int = 0

# [D4 CHEAP bundle] Smack Down(479)/its own MOVE_EFFECT — permanent
# (switch-cleared) per-mon flag forcing this mon to be treated as grounded
# for the rest of the battle, regardless of Flying-type/Levitate/Air
# Balloon/Magnet Rise. Also clears any active Magnet Rise timer and, if
# the target was mid-Fly (semi_invulnerable == SEMI_INV_ON_AIR), knocks it
# out of the air early. See AbilityManager.is_grounded's own doc comment
# for the exact priority-ordering insertion (Iron Ball > Smack Down/Ingrain
# forced-grounded > Magnet Rise/Levitate/Air Balloon ungrounded > Flying-
# type ungrounded > grounded by default).
# Source: battle_move_resolution.c, case EFFECT_SMACK_DOWN (L3547-3570);
# battle_util.c L5885 (grounding check, B_ROOTED_GROUNDING >= GEN_4 shares
# this same "forced grounded" priority tier with Ingrain's own root field).
var smack_down_active: bool = false

# [D4 CHEAP bundle] Ingrain(182) — a 3-piece composite self-targeted
# permanent (switch-cleared) volatile: (1) end-of-turn self-heal of
# maxHP/16, Big-Root-boosted, gated on not already at max HP — shares the
# EXACT SAME formula/helper as Aqua Ring's own end-of-turn heal below;
# (2) forces this mon to be treated as grounded (see smack_down_active's
# own doc comment for the shared priority-ordering insertion — Ingrain and
# Smack Down are the SAME "forced grounded" tier); (3) blocks voluntary
# switching (wired into AbilityManager.is_trapped, the same choke point
# wrapped_by/escape_prevented_by already established) AND blocks being
# forced out by Roar/Whirlwind/Circle Throw/Dragon Tail/Red Card (wired
# into the EXISTING AbilityManager.blocks_forced_switch Guard Dog already
# occupies — confirmed from source, not a partial-scope simplification,
# that Roar's own script explicitly checks VOLATILE_ROOT before its
# accuracy check: `jumpifvolatile BS_TARGET, VOLATILE_ROOT,
# BattleScript_PrintMonIsRooted`, data/battle_scripts_1.s L1656).
# Confirmed via source that Baton Pass explicitly passes
# SWITCH_IGNORE_ESCAPE_PREVENTION (data/battle_scripts_1.s L2247) — Ingrain
# does NOT block Baton Pass, matching every other trapping source's
# already-established Baton-Pass-bypasses-trapping architecture. Fails to
# apply if the user is already rooted (Cmd_trysetvolatile's own
# already-active fail case, mirrored for consistency with Magnet Rise
# even though this project builds it as a bespoke dispatch, not
# trysetvolatile-generic).
# Source: data/battle_scripts_1.s L2555 (trysetvolatile ... VOLATILE_ROOT);
# battle_end_turn.c :: HandleEndTurnIngrain (L457-474); battle_util.c
# L4953 (CanBattlerEscape's own root check).
var ingrain_active: bool = false

# [D4 CHEAP bundle] Aqua Ring(392) — self-targeted permanent (switch-
# cleared) volatile, end-of-turn self-heal of maxHP/16, Big-Root-boosted,
# gated on not already at max HP — the EXACT SAME formula/helper as
# Ingrain's own end-of-turn heal above (both route through
# BattleManager._ingrain_aqua_ring_heal_amount). No grounding/switch-block
# component, unlike Ingrain.
# Source: battle_end_turn.c :: HandleEndTurnAquaRing (L438-455) — the
# literal same GetDrainedBigRootHp(battler, GetNonDynamaxMaxHP(battler)/16)
# call Ingrain's own heal uses.
var aqua_ring_active: bool = false

# [D4 bundle 3] Nightmare(171) — target-side permanent (switch-cleared)
# volatile, maxHP/4 recurring end-of-turn damage while the target remains
# asleep/Comatose, Magic-Guard-blocked. Confirmed via source
# (HandleEndTurnNightmare) that sleep status is RE-CHECKED every turn, not
# just at application — if the target wakes up (or loses Comatose), this
# is silently cleared with no damage that turn rather than re-attempted.
var nightmare_active: bool = false

# [D4 bundle 3] Recycle(278) — the item most recently removed via
# BattleManager._consume_item, for ANY reason (berry or not) EXCEPT a
# popped Air Balloon (excluded explicitly, matching source's own "cannot
# be restored by any means" carve-out). Genuinely BROADER in scope than
# last_consumed_berry (Harvest/Cud Chew's own berry-only tracker) — see
# MoveData.is_recycle's own doc comment for the full source citation
# confirming these are two distinct fields in source too (usedHeldItem vs.
# the berry-specific tracker), not one field serving both purposes.
# Deliberately NOT reset by _clear_volatiles/_switch_out_clear — like
# last_consumed_berry, this persists across switches for the whole battle
# (matches source's own PartyState-scoped, not Volatiles-scoped, storage).
var last_used_item: ItemData = null

# M18u: Metronome item's consecutive-same-move-use counter. Compared against
# last_move_used (BEFORE it's overwritten for the current move) at the same
# PP-deduction site source colocates its own reset check
# (battle_move_resolution.c L1006-1008).
var metronome_item_counter: int = 0

# Volatile: flinched. Set when a move with MOVE_EFFECT_FLINCH hits this Pokémon
# before it has acted this turn. Cleared at the start of each turn (PRIORITY_RESOLUTION).
# Source: battle_move_resolution.c :: CancelerFlinch (L298)
var flinched: bool = false

# [M19-stat-raised-trigger] Volatile: did ANY of this Pokémon's stats rise
# this turn (from a move, ability, or item — a broad, general concept, not
# move-specific). Set by StatusManager.apply_stat_change whenever a positive
# stage delta actually applies. Cleared at the start of each turn
# (PRIORITY_RESOLUTION), same cadence as flinched/protect_active above.
# Source: include/battle.h L74 (`statRaised:1`); battle_main.c L3304
# (`gProtectStructs[battler].statRaised = FALSE;`, the per-turn reset).
var stat_raised_this_turn: bool = false

# [D3 turn-order/event-tracker batch] Lash Out's own trigger — the exact
# decrease-side mirror of stat_raised_this_turn above, set at the same
# general stat-change chokepoint (StatusManager.apply_stat_change) whenever
# THIS battler's own stat actually decreases, from any source. Cleared at
# the start of each turn, same cadence/site as stat_raised_this_turn.
# Source: battle_stat_change.c L368 (`gProtectStructs[cv->battlerDef].
# lashOutAffected = TRUE`); battle_main.c L5056 (per-turn reset).
var stat_lowered_this_turn: bool = false

# [D3 turn-order/event-tracker batch] Rage Fist's own trigger — a
# battle-LIFETIME count of direct hits taken, incremented once per hit that
# deals damage > 0 (BattleManager._do_damaging_hit). Deliberately NOT
# cleared by _clear_volatiles or anywhere else — source has no reset
# mechanism at all, so this survives switch-out/switch-in for the whole
# battle, the same switch-persistent-per-party-slot shape already
# established for last_consumed_berry ([M17n-7] Harvest).
# Source: battle_util.c, case EFFECT_RAGE_FIST (L6349-6351) —
# GetBattlerPartyState(battler)->timesGotHit, incremented at
# battle_script_commands.c L1685.
var times_hit: int = 0

# Volatile: two-turn charge state.
# Non-null on the turn AFTER a charge: the Pokémon is locked to this move and
# it fires when their action executes (release turn).
# Set by BattleManager._phase_move_execution() on turn 1 of a two_turn move;
# cleared by BattleManager._phase_move_execution() on turn 2, and on faint.
# Source: battle_move_resolution.c :: CancelerCharging (L1737); gLockedMoves
var charging_move: MoveData = null

# [M19-rampage] Volatile: forced-move-repeat lock, distinct from charging_move
# (charging_move is two-turn/Bide-specific and has its own dispatch gates
# keyed on move.two_turn/move.is_bide — a genuinely different mechanic
# despite the surface similarity, kept separate per this project's own
# one-field-per-lock convention: disabled_move/encored_move/choice_locked_move
# are all separate fields too). Shared by BOTH is_rampage moves (Thrash/Petal
# Dance/Outrage/Raging Fury) and is_uproar (Uproar) — the two mechanisms use
# the SAME lock field but distinct counters (rampage_turns vs uproar_turns)
# to know which end-of-lock behavior applies (self-confuse vs. none).
# Non-null while locked: BattleManager._phase_move_selection forces this
# exact move every turn, the same override shape charging_move already gets.
# Cleared on faint/switch-out via _clear_volatiles, same as charging_move.
# Source: gLockedMoves[battler] (shared by Thrash/Uproar/Recharge/Sky Drop in
# source too — this project only needs the rampage/Uproar slice of that).
var locked_move: MoveData = null

# [M19-rampage] Turns remaining on an is_rampage lock (Thrash/Petal Dance/
# Outrage/Raging Fury). Random 2-3 on application. Reaching 0 clears the lock
# and self-confuses the user (CanBeConfused-gated). A turn whose hit is fully
# unaffected by type immunity cancels the lock WITHOUT confusing, checked
# independently of this counter reaching 0.
# Source: gBattleMons[].volatiles.rampageTurns; RandomUniform(2, B_RAMPAGE_TURNS).
var rampage_turns: int = 0

# [M19-rampage] Turns remaining on an is_uproar lock (Uproar). Flat 3 at this
# project's Gen5+ config. Reaching 0 clears the lock — NO self-confuse, unlike
# rampage_turns. While > 0 on ANY active battler (field-wide, both sides), new
# sleep infliction is blocked project-wide (see MoveData.is_uproar's own doc
# comment for the full field-wide-scope citation).
# Source: gBattleMons[].volatiles.uproarTurns; B_UPROAR_TURNS>=GEN_5 → 3.
var uproar_turns: int = 0

# Volatile: semi-invulnerable state (underground, on-air, underwater).
# Set on the charge turn of a semi-invulnerable two-turn move; cleared on release.
# Incoming moves miss unless their bypass flag matches (damages_underground etc.).
# Source: gBattleMons[].volatiles.semiInvulnerable; STATE_UNDERGROUND etc.
var semi_invulnerable: int = 0  # MoveData.SEMI_INV_* constant

# ── M7 volatiles ─────────────────────────────────────────────────────────────

# Substitute: a decoy that absorbs incoming damaging moves.
# Created by the Substitute move (HP cost = max_hp / 4).
# Cleared when substitute_hp reaches 0 (substitute breaks) or on faint.
# Source: battle_script_commands.c :: Cmd_setsubstitute; gBattleMons[].volatiles.substituteHP
var substitute_hp: int = 0

# Per-turn damage tracking for Counter and Mirror Coat.
# Set when a physical/special hit lands directly (not via substitute).
# Cleared at the start of each turn (PRIORITY_RESOLUTION).
# Source: gProtectStructs[].physicalDmg / .specialDmg (cleared by memset each turn)
var last_physical_damage: int = 0
var last_special_damage: int = 0
# [M19c/M19d] Metal Burst: which category the MOST RECENT hit this turn was —
# a genuinely separate axis from the two amount fields above (both can be
# simultaneously nonzero in doubles if hit by both categories in one turn;
# Metal Burst reflects whichever was taken LAST, not the larger of the two).
# Source: gProtectStructs[].lastHitBySpecialMove (battle_util.c
# GetReflectDamageMoveDamageCategory L306-320) — Counter/Mirror Coat never
# consult this field at all since their own damageCategories bitmask is
# single-valued, only Metal Burst's dual-category bitmask needs it.
var last_hit_was_special: bool = false

# Protect: blocks all incoming moves for one turn.
# protect_consecutive = consecutive Protect uses (0 = first use this streak).
# Cleared (protect_active) and decremented (protect_consecutive maybe) each turn.
# Source: gBattleMons[].volatiles.consecutiveMoveUses; gProtectStructs[].protected
var protect_active: bool = false
var protect_consecutive: int = 0

# [D4 bundle] Magic Coat's own single-turn volatile — same "self-flag,
# expires at the start of the next turn" shape as protect_active just
# above (cleared in `_phase_priority_resolution`'s existing reset loop),
# but ALSO cleared immediately the instant it successfully bounces a move
# back (so it can't reflect a SECOND status move later the same turn).
# See MoveData.is_magic_coat's own doc comment for the full citation.
var magic_coat_active: bool = false
# [M19c] Which Protect-family variant is active — mirrors source's own
# `enum ProtectMethod` (battle.h) exactly. PROTECT_METHOD_NONE(0) covers both
# "not protected" AND plain Protect/Detect (left at their default 0 —
# `_is_protected_from`'s own `_` match branch treats an unrecognized/default
# method as an unconditional block, matching Protect/Detect's real behavior
# with zero data changes needed for those two pre-existing moves).
const PROTECT_METHOD_NONE: int = 0
const PROTECT_METHOD_SPIKY_SHIELD: int = 1
const PROTECT_METHOD_BANEFUL_BUNKER: int = 2
const PROTECT_METHOD_BURNING_BULWARK: int = 3
const PROTECT_METHOD_OBSTRUCT: int = 4
const PROTECT_METHOD_SILK_TRAP: int = 5
const PROTECT_METHOD_WIDE_GUARD: int = 6
const PROTECT_METHOD_QUICK_GUARD: int = 7
# [D4 CHEAP bundle] Endure — used ONLY as a MoveData.protect_method tag
# read at dispatch time (`move.protect_method == PROTECT_METHOD_ENDURE`),
# NEVER actually stored into BattlePokemon.protect_method itself. Confirmed
# via direct source read of Cmd_setprotectlike (battle_script_commands.c
# L6934-6957) that Endure takes a genuinely SEPARATE branch of that shared
# command — `if (GetMoveEffect(gCurrentMove) == EFFECT_ENDURE)` sets ONLY
# `volatiles.endured = TRUE`, completely bypassing `gProtectStructs[].
# protected` (the field this project's own `protect_active`/`protect_method`
# together represent) — so Endure does NOT block the incoming hit, unlike
# every other PROTECT_METHOD_*, and needed its own dedicated `endure_active`
# field below rather than reusing protect_active at all. The ONE piece
# still genuinely shared: `volatiles.consecutiveMoveUses++` is unconditional
# in that same command regardless of branch, so Endure still ticks and is
# subject to the SAME per-battler consecutive-use fail-chance ramp
# (protect_consecutive) every other Protect-family move uses — see the
# is_protect dispatch's own branch for the exact insertion.
const PROTECT_METHOD_ENDURE: int = 8
var protect_method: int = PROTECT_METHOD_NONE

# [D4 CHEAP bundle] Endure(203) — single-turn self-volatile, guarantees
# survival at 1 HP against a lethal hit WITHOUT blocking the hit itself
# (see PROTECT_METHOD_ENDURE's own doc comment for the source-verified
# separation from protect_active). Cleared every turn in
# `_phase_priority_resolution`'s existing reset loop, the same cadence
# protect_active/flinched/stat_raised_this_turn already use.
var endure_active: bool = false

# Destiny Bond: if this Pokémon faints before their next action, the KO attacker
# also faints. Cleared when this Pokémon acts next (before their move executes).
# Source: gBattleMons[].volatiles.destinyBond (set to 2, decremented after each move use)
var destiny_bond: bool = false

# Disable: prevents a specific move from being used.
# disable_turns decrements at END_OF_TURN; cleared when it reaches 0.
# Source: gBattleMons[].volatiles.disabledMove / .disableTimer
var disabled_move: MoveData = null
var disable_turns: int = 0

# last_move_used: last move successfully executed by this Pokémon.
# Used as the target for Disable and Encore.
# Source: gLastMoves[] (set after each move execution)
var last_move_used: MoveData = null

# Encore: forces this Pokémon to repeat its last-used move.
# encore_turns decrements at END_OF_TURN; cleared when it reaches 0.
# Source: gBattleMons[].volatiles.encoredMove / .encoreTimer
var encored_move: MoveData = null
var encore_turns: int = 0

# Bide: accumulated damage and turn counter for the Bide state machine.
# bide_turns: 0 = not biding; 2 = first wait turn; 1 = second wait turn; release on → 0.
# bide_damage: sum of direct HP damage received during bide (not sub damage).
# The Bide move is locked via charging_move (same mechanism as two-turn charge moves).
# Source: gBattleMons[].volatiles.bideTurns; gBideDmg[]
var bide_turns: int = 0
var bide_damage: int = 0

# M16a: Focus Energy — volatile that raises crit stage by +2.
# Cleared on faint (_clear_volatiles) and switch-out (_switch_out_clear → _clear_volatiles).
# Source: battle_script_commands.c :: Cmd_setfocusenergy (L7718) — sets volatiles.focusEnergy.
var focus_energy: bool = false

# M18c: Micle Berry — one-shot ×1.2 (×1.4 Ripen) accuracy boost for exactly this
# mon's NEXT accuracy check (hit or miss), then cleared unconditionally. Cleared on
# faint/switch-out (_clear_volatiles) same as every other one-battle-stint volatile.
# Source: gBattleStruct->battlerState[battler].usedMicleBerry, cleared at the START
# of each move-processing cycle (SetSameMoveTurnValues, battle_move_resolution.c
# L4268) — this project clears it right after StatusManager.check_accuracy is
# called instead, the single call site that consumes it (see StatusManager's own
# doc comment on the accuracy pipeline for why that's the correct one-shot point).
var micle_boost_active: bool = false

# M16b: Minimize — volatile that raises Evasion +2 and doubles incoming damage from
# moves with double_power_on_minimized=true (Stomp etc.).
# Cleared on faint (_clear_volatiles) and switch-out (_switch_out_clear → _clear_volatiles).
# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case EFFECT_MINIMIZE (L1000).
var minimized: bool = false

# M16b: Defense Curl — volatile that raises Defense +1 and doubles Rollout/Ice Ball's
# starting power.
# Cleared on faint (_clear_volatiles) and switch-out (_switch_out_clear → _clear_volatiles).
# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case EFFECT_DEFENSE_CURL (L997).
var defense_curled: bool = false

# M16b: Rollout / Ice Ball consecutive-hit counter (0-4; the exponent for power doubling)
# and the power computed for the CURRENT hit (informational — recomputed each use).
# Cleared on faint/switch-out and whenever a different move is used (interruption).
# Source: gBattleMons[].volatiles.rolloutTimer; CalcRolloutBasePower (battle_util.c L6034).
var rollout_turns: int = 0
var rollout_base_power: int = 0

# M12: choice lock — the move this Pokémon is locked to by a choice item.
# Set the first time a move is used while holding a choice item.
# Cleared by BattleManager._switch_out_clear() on switch-out (NOT by _clear_volatiles).
# Source: gBattleStruct->chosenMovePositions[battler]; cleared in SwitchInClearSetData.
var choice_locked_move: MoveData = null

# Per-turn flag: true on the turn this Pokémon switches in mid-battle (voluntary,
# forced, or faint replacement). Cleared at the start of the NEXT turn in
# _phase_priority_resolution. Mirrors isFirstTurn == 2 (battle_main.c L3198/L3309;
# decremented at L5038). Used by AbilityManager to gate !BattlerJustSwitchedIn
# (battle_util.c L10982) — Speed Boost must not fire on the switch-in turn EOT.
var switched_in_this_turn: bool = false

# In-battle stat modifiers. Ranges: −6 to +6 per stage.
# Index order matches STAGE_* constants above.
var stat_stages: Array[int] = []

# M18m: Eject Pack — snapshot of `stat_stages` taken at the end of the PREVIOUS
# MoveEnd-equivalent checkpoint (BattleManager._phase_faint_check). Compared
# against the CURRENT stat_stages there to detect "a decrease was just applied
# this resolution" — reproducing source's `tryEjectPack` volatile flag (set
# only at the exact moment of application, battle_stat_change.c L365-368)
# without needing a new signal-listener pattern, since this project's own
# MoveEnd-equivalent phase already runs once per resolved move regardless of
# outcome. Always re-synced to the current stat_stages after each check.
var eject_pack_snapshot: Array[int] = []

# Follow-up fixes session, 2026-07-02: cache of this Pokémon's NATURAL species types,
# captured once at construction, before Conversion/Conversion 2 (M16e) can ever mutate
# `species.types` in place. Restored onto `species.types` on every switch-IN
# (BattleManager._reset_mon_type) — source repopulates gBattleMons[battler].types from
# GetSpeciesType() at every switch-in event (CopyMonAbilityAndTypesToBattleMon,
# battle_util.c L9365-9379; Cmd_switchindataupdate, battle_script_commands.c L5030-5032),
# so a Conversion-induced type change never survives its user leaving the field.
var original_types: Array[int] = []

# M17b: Supersweet Syrup fires ONCE per Pokémon for the whole battle (source's
# GetBattlerPartyState(battler)->supersweetSyrup flag), not once per switch-in — so
# this must NOT be cleared by _clear_volatiles/_switch_out_clear, unlike ordinary
# switch-scoped volatiles.
var supersweet_syrup_used: bool = false

# M17c: Truant's per-battler loafing toggle (source: volatiles.truantCounter, XORed every
# end of turn — include/constants/battle.h L307). NOT V_BATON_PASSABLE (no such flag on
# VOLATILE_TRUANT_COUNTER) — cleared by _clear_volatiles like an ordinary switch-scoped
# volatile, unlike Supersweet Syrup above.
var truant_loafing: bool = false

# M17m: Flash Fire's persistent absorb flag (source: volatiles.flashFireBoosted,
# battle_util.c L2344-2348/L10564). Cleared by _clear_volatiles on switch-out/faint —
# confirmed from source that the entire `volatiles` struct housing this flag gets
# wholesale memset to 0 at switch (battle_main.c L3145/3272/3421), the SAME shape as
# minimized/defense_curled/focus_energy above, not a whole-battle-persistent flag like
# supersweet_syrup_used. NOT Baton-Pass-passable (confirmed absent from source's
# Baton-Pass volatile-copy list), matching minimized/defense_curled's precedent.
var flash_fire_active: bool = false

# [M19-recharge] Pending recharge: set true on a successful, non-immune hit
# with an is_recharge move (Hyper Beam/Blast Burn/Hydro Cannon/Frenzy Plant/
# Giga Impact/Rock Wrecker/Roar of Time/Prismatic Laser/Meteor Assault/
# Eternabeam). The NEXT time this Pokémon would act, StatusManager.
# pre_move_check blocks the action entirely (checked BEFORE Sleep, matching
# source's CANCELER_RECHARGE running before CANCELER_ASLEEP_OR_FROZEN) and
# clears this flag — a single boolean reproduces source's literal
# rechargeTimer=2/decrement-twice shape, since the observable behavior is
# just "block exactly the next turn, then clear." Cleared unconditionally by
# _clear_volatiles on switch-out/faint, same as flash_fire_active above —
# source's rechargeTimer lives in the same bulk-memset Volatiles struct.
var must_recharge: bool = false

# M17n-5: Slow Start's 5-turn Atk/Speed-halving timer (source: volatiles.slowStartTimer,
# battle_util.c L3052-3055/3649-3654; B_SLOW_START_TIMER = 5). Set to 5 on switch-in via
# try_switch_in, decremented post-check at end-of-turn via try_end_of_turn (source's own
# `if (timer > 0 && --timer == 0)` shape), cleared by _clear_volatiles on switch-out —
# same whole-`volatiles`-struct-memset shape as flash_fire_active above.
var slow_start_timer: int = 0

# M17n-4: Protean/Libero's once-per-switch-in-stint gate (source:
# volatiles.usedProteanLibero, battle_move_resolution.c L1652-1653/battle_script_commands.c
# L922). Source's own comment reads "once per Battle," but the flag lives in the same
# `Volatiles` struct that gets wholesale memset to 0 at every switch-in (battle_main.c
# L3145/3272/3421 — the identical 3 call sites flash_fire_active/slow_start_timer above
# cite) — so operationally this is once-per-switch-in-stint, not once-per-whole-battle;
# the comment's wording is loose, not a mechanic description to trust literally. Cleared
# by _clear_volatiles like the other two.
var used_protean_libero: bool = false

# M17n-7: Unburden — Speed x2 while active. Source: volatiles.unburdenActive
# (battle_util.c :: CheckSetUnburden, L10604-10611), set TRUE whenever the holder's
# OWN item is removed by any means (berry consumption, theft, a voluntary
# Symbiosis-give) — see BattleManager._consume_item / AbilityManager._try_steal_item /
# AbilityManager.try_symbiosis's doc comments for the exact set/clear call sites —
# and explicitly cleared FALSE the moment the holder GAINS an item by any means
# (source: StealTargetItem L2072, BestowItem L2078 both clear the RECEIVER's flag
# even though neither of those functions is the one that SET it). Cleared by
# _clear_volatiles on switch-out — same whole-`volatiles`-struct-memset shape as
# flash_fire_active/slow_start_timer/used_protean_libero above.
var unburden_active: bool = false

# M17n-7: Cud Chew's one-turn arm/fire cycle. Source: volatiles.cudChew
# (battle_util.c L3695-3707) — arms (sets TRUE) at end-of-turn when a berry was just
# consumed and the flag isn't already armed; fires (re-triggers the same berry's
# effect, then clears both this flag AND `last_consumed_berry`) at the NEXT
# end-of-turn tick. Cleared by _clear_volatiles on switch-out, same shape as the
# other switch-cleared volatiles above — matching source's `volatiles` struct
# membership (distinct from `last_consumed_berry` below, which is NOT cleared here).
var cud_chew_armed: bool = false

# M17n-7: the "last consumed berry" tracker both Harvest and Cud Chew need. Source:
# `GetBattlerPartyState(battler)->usedHeldItem` — deliberately PARTY-STATE-scoped in
# source (survives switch-out/switch-in), NOT part of the `volatiles` struct the two
# fields above live in — confirmed by checking the actual storage location before
# wiring this in, per the `[M17h]`-established dormant-field-check discipline
# extended to a genuinely new field. Set unconditionally in
# `BattleManager._consume_item` (which, per Cheek Pouch's own established precedent
# from `[M17c]`, only ever runs for berries in this project's current scope — no
# separate "is this a berry" gate was needed). Read by Harvest (regenerates
# `held_item` from this, does NOT clear it) and Cud Chew (re-triggers the berry's
# effect from this, THEN clears it — source's `usedHeldItem = ITEM_NONE`). NOT
# cleared on switch-out — a Pokémon that ate a berry, switched out, and switched
# back in can still have that berry Harvested/Cud-Chewed later, matching source.
var last_consumed_berry: ItemData = null

# [Bucket 4 cheapest singles] Rage's persistent "Attack rises when hit" volatile.
# Source: volatiles.rage (battle_script_commands.c :: case MOVE_EFFECT_RAGE,
# L2514-2515 — set TRUE unconditionally on a successful hit, no `.chance` field,
# self=TRUE). Cleared two ways in source, both reproduced here: (1) at the START
# of every turn, for any battler whose CHOSEN move this turn is NOT Rage itself
# (battle_main.c L5269-5270) — reproduced as a check at the top of
# `_phase_move_execution`, the same place `destiny_bond` resets; (2) implicitly,
# by this project's GEN_LATEST config matching source's B_RAGE_BUILDS >= GEN_4
# behavior (`SetOrClearRageVolatile`, battle_util.c L10899-10904): the volatile
# is only ever set on a genuine hit, never on a miss/Protect/fail — reproduced by
# gating the SET (not a separate clear) on `damage > 0`. Cleared by
# `_clear_volatiles` on switch-out, same whole-`volatiles`-struct-memset shape as
# every other switch-cleared volatile above.
var rage_active: bool = false

# [Bucket 4 cheapest singles] Throat Chop's 2-turn "target's sound moves fail"
# timer. Source: volatiles.throatChopTimer (battle_script_commands.c ::
# case MOVE_EFFECT_THROAT_CHOP, L2619-2624 — set to B_THROAT_CHOP_TIMER=2, no
# refresh if already active; battle_end_turn.c L61-63/L1280-1311 decrements at
# end of turn). Checked at move-selection/execution time
# (battle_move_resolution.c L351: `throatChopTimer > 0 && IsSoundMove(move)` —
# blocks the move from executing), reproduced at the same "chosen, then fails at
# execution" insertion point Disable/Assault Vest already use in
# `_phase_move_execution`, gated on `move.sound_move` instead of a specific move
# ID. Cleared by `_clear_volatiles` on switch-out, same shape as `disable_turns`.
var throat_chop_turns: int = 0

# [Delayed-effect family] Yawn's own 2-turn drowsiness counter — the same
# per-mon-volatile shape as throat_chop_turns/disable_turns/encore_turns
# just above, decremented at end of turn; hitting 0 triggers a completely
# FRESH sleep-infliction attempt via StatusManager.try_apply_status (all
# immunity checks re-derived at that moment, not locked in at cast time).
# Cleared by `_clear_volatiles` on switch-out, same shape as those siblings.
# Source: gBattleMons[].volatiles.yawn (battle_script_commands.c ::
# Cmd_setyawn L9091-9116; battle_end_turn.c L915-935).
var yawn_turns: int = 0

# [D4 bundle] Taunt's own turn counter — same per-mon-volatile shape as
# throat_chop_turns/disable_turns/encore_turns above, decremented at end of
# turn (source: battle_end_turn.c L762, the SAME file/category
# disable_turns/encore_turns/throat_chop_turns already decrement in — NOT
# the separate `battle_main.c` per-battler-action-reset site
# stomping_tantrum_timer/_retaliate_timer needed, confirmed individually
# rather than assumed). Cleared by `_clear_volatiles` on switch-out, same
# shape as those siblings. See MoveData.is_taunt's own doc comment for the
# duration-formula and execution-time-block citations.
var taunt_turns: int = 0

# [D1 easy bundle] Revenge/Avalanche's own "who hit me this turn" tracker —
# a per-(victim,attacker)-PAIR record, not a plain "was I hit" bool, since
# Revenge only doubles against the SPECIFIC target that hit its user this
# turn (real in doubles: being hit by one opponent doesn't double a Revenge
# used against a different one). Set at the same `_do_damaging_hit`
# chokepoint `times_hit`/`_last_attacker` already use; cleared every turn
# like its D2-tracker-family siblings (stat_lowered_this_turn, etc.).
# Source: gProtectStructs[].revengeDoubled (battle_script_commands.c
# L1656-1657, battle_util.c L6172-6174).
var hit_by_this_turn: Array = []

# [D1 easy bundle] Stomping Tantrum/Temper Flare's own "did my last move
# fail" counter — set to 2 the same turn a move fails, decremented once per
# turn boundary at the SAME site the (corrected) Retaliate side-timer uses,
# checked against exactly 1 at power-computation time. Stored per-mon
# (unlike source's per-slot struct) since this project's BattlePokemon
# objects persist across switches; source itself clears this same state on
# switch-out anyway (battle_main.c L3214, alongside lastResultingMove/
# lastHitBy), so per-mon storage cleared in `_clear_volatiles` reproduces
# the identical observable behavior.
var stomping_tantrum_timer: int = 0

# [D4 Bundle 4] Stockpile family. `stockpile_count` (0-3) is the scaling
# counter Spit Up/Swallow read for their own power/heal tables — incremented
# unconditionally on each use (source: battle_move_resolution.c L4629-4631).
# `stockpile_def_added`/`stockpile_spdef_added` track EXACTLY how much Def/
# SpDef actually rose from Stockpile (0 if the raise was capped at +6 or
# inverted by Contrary) — a SEPARATE pair of counters from `stockpile_count`,
# confirmed via source (battle_stat_change.c L481-491: these only increment
# when `st->stage > 0`, i.e. an ACTUAL rise) to diverge from the scaling
# counter whenever a stat is already maxed or Contrary is active. Release
# (Spit Up/Swallow) removes exactly these tracked amounts via a raw, ungated
# stat-change (no Mist/ability gate on the undo itself — source's own
# `SetStatChange` call for the removal has none), never re-derived from the
# current stat stage. All three live in source's per-battler `volatiles`
# struct — cleared in `_clear_volatiles` like every other switch-scoped
# field here.
var stockpile_count: int = 0
var stockpile_def_added: int = 0
var stockpile_spdef_added: int = 0

var fainted: bool = false


static func from_species(p_species: PokemonSpecies, p_level: int,
		forced_nature: Variant = null, forced_ivs: Variant = null,
		forced_friendship: Variant = null) -> BattlePokemon:
	var bp := BattlePokemon.new()
	bp.species = p_species
	bp.original_types = p_species.types.duplicate()
	bp.nickname = p_species.species_name
	bp.level = p_level
	bp.gender = _roll_gender(p_species.gender_ratio)
	bp.nature = _roll_nature(forced_nature)
	bp.ivs = _roll_ivs(forced_ivs)
	bp.friendship = _default_friendship(p_species.base_friendship, forced_friendship)
	bp.evs = [0, 0, 0, 0, 0, 0]
	bp.moves = []
	bp.current_pp = []
	bp.ability = null
	bp.held_item = null
	bp.status = STATUS_NONE
	bp.sleep_turns = 0
	bp.toxic_counter = 0
	bp.confusion_turns = 0
	bp.flinched = false
	bp.charging_move = null
	bp.semi_invulnerable = 0
	# M7 volatiles
	bp.substitute_hp = 0
	bp.last_physical_damage = 0
	bp.last_special_damage = 0
	bp.protect_active = false
	bp.protect_consecutive = 0
	bp.destiny_bond = false
	bp.disabled_move = null
	bp.disable_turns = 0
	bp.last_move_used = null
	bp.encored_move = null
	bp.encore_turns = 0
	bp.bide_turns = 0
	bp.bide_damage = 0
	bp.focus_energy = false
	bp.micle_boost_active = false
	bp.minimized = false
	bp.defense_curled = false
	bp.rollout_turns = 0
	bp.rollout_base_power = 0
	bp.choice_locked_move = null
	bp.switched_in_this_turn = false
	bp.stat_stages = [0, 0, 0, 0, 0, 0, 0]
	bp.eject_pack_snapshot = [0, 0, 0, 0, 0, 0, 0]
	bp.fainted = false
	bp._calculate_stats()
	bp.current_hp = bp.max_hp
	return bp


# [M18.5d] Resolves a species' raw gender_ratio byte to a per-instance GENDER_*
# value, exactly mirroring source's GetGenderFromSpeciesAndPersonality
# (pokemon.c L1847-1861): the three gender-locked sentinel values (MON_MALE=0,
# MON_FEMALE=254, MON_GENDERLESS=255) return themselves directly with no roll;
# any other value is a female-probability threshold checked against a uniform
# 0-255 roll (`genderRatio > roll` -> female), matching source's
# `genderRatio > (personality & 0xFF)` exactly (a personality value's low byte
# is itself already uniform 0-255, so a direct `randi() % 256` reproduces the
# identical distribution without needing a personality-value concept this
# project doesn't otherwise have). No forcing seam — no other per-instance
# field in this class has one (ivs/evs are deliberately zeroed, not rolled;
# see their own doc comment above), and every field here is already freely
# reassignable by test code after construction, which is how a future
# Attract-family test should pin a specific gender rather than a new
# force_gender parameter.
static func _roll_gender(gender_ratio: int) -> int:
	if gender_ratio == 0:
		return GENDER_MALE
	if gender_ratio == 254:
		return GENDER_FEMALE
	if gender_ratio == 255:
		return GENDER_GENDERLESS
	if gender_ratio > randi() % 256:
		return GENDER_FEMALE
	return GENDER_MALE


# [M18.5h-1] Rolls a uniform-random Nature (1/25 each) unless forced_nature is
# provided (non-null), in which case it's returned directly with zero variance —
# the SAME Variant=null forcing-parameter convention already established
# throughout this project (StatusManager/DamageCalculator's force_hit/force_crit/
# force_roll, force_confusion_hit at status_manager.gd:429), reused here rather
# than inventing a new pattern. Added an explicit forcing parameter (unlike
# gender, which has none — see _roll_gender's own doc comment) because M24
# (Trainer Data, not yet started) will need to assign SPECIFIC deterministic
# natures to trainer-owned Pokémon (e.g. a gym leader's ace with a fixed
# competitive nature), not a random roll — building the override now, alongside
# the roll mechanism, avoids retrofitting a parameter onto an already-shipped
# function later.
# Source: GetNature/GetNatureFromPersonality (pokemon.c L4185-4193), a flat
# `personality % NUM_NATURES` — structurally identical to _roll_gender's own
# personality-modulo-derived shape, so a direct `randi() % NUM_NATURES`
# reproduces the same uniform distribution without a personality-value concept.
static func _roll_nature(forced_nature: Variant = null) -> int:
	if forced_nature != null:
		return forced_nature
	return randi() % NUM_NATURES


# [M18.5h-2] Rolls 6 INDEPENDENT uniform-random IVs (0-31 each), matching the
# same Variant=null forcing convention `_roll_nature`/`_roll_gender` already
# established. Source's real IVs come from a separate random "IV word" (three
# 5-bit fields packed into each of two 16-bit halves), NOT derived from
# personality the way gender/nature are (`pokemon.c` — GetBoxMonData's
# IV-unpacking, distinct from GetNature/GetGenderFromSpeciesAndPersonality) —
# this project doesn't model an "IV word" concept any more than it models a
# raw personality value, so 6 independent `randi() % 32` calls reproduce the
# resulting per-stat 0-31 uniform DISTRIBUTION directly, the same
# reproduce-the-distribution-not-the-bit-packing precedent already used for
# gender/nature.
#
# forced_ivs, if provided, must be an Array of exactly 6 elements (STAT_*
# index order), each independently either an int (forces that one stat,
# 0-31) or null (rolls that one stat normally) — NOT just all-or-nothing.
# This supports M24's real future need directly: a competitively-built
# trainer Pokémon commonly has SOME stats deliberately maxed (e.g. Speed=31)
# and the rest left at whatever, not uniformly all-6-forced or all-6-random.
# A fully-concrete Array[int] (e.g. cloning an existing mon's own .ivs) also
# satisfies this shape unchanged, since every element is already a non-null
# int.
static func _roll_ivs(forced_ivs: Variant = null) -> Array[int]:
	var result: Array[int] = []
	for i in range(6):
		var forced_stat: Variant = null
		if forced_ivs != null:
			forced_stat = forced_ivs[i]
		if forced_stat != null:
			result.append(forced_stat)
		else:
			result.append(randi() % 32)
	return result


# [M19-pre1] Resolves the instance's starting friendship: the species' own
# base_friendship UNLESS forced_friendship overrides it. NOT a random roll
# (source's real friendship starts at a fixed per-species value, not a
# personality-derived one like gender/nature/IVs) — but the SAME
# Variant=null forcing shape is still used, matching this project's
# established convention, since M24 trainer data needs the identical
# "assign a SPECIFIC value" capability Nature/IVs already built. Source:
# SpeciesInfo.friendship (include/pokemon.h L415), read at Pokémon-creation
# time (CreateMon family, pokemon.c) with no roll involved.
static func _default_friendship(base_friendship: int, forced_friendship: Variant = null) -> int:
	if forced_friendship != null:
		return forced_friendship
	return base_friendship


# [M18.5h-1] Returns [raise_stat, lower_stat] (BattlePokemon.STAT_* indices, THIS
# project's own ordering — NOT source's raw `enum Stat` order, which places Speed
# BEFORE SpAtk/SpDef and would silently resolve to the wrong stat if copied by raw
# index; see docs/m18_5h_recon.md Section B3's own flagged ordering trap) for a
# given nature, translated by STAT NAME from source's gNaturesInfo[] table
# (pokemon.c L154-453). Returns [-1, -1] for the 5 neutral natures (Hardy/Docile/
# Serious/Bashful/Quirky) — checked explicitly by _apply_nature below, rather than
# mirrored via source's own raise==lower placeholder-stat encoding (source assigns
# each neutral nature some arbitrary "same stat" purely so its own equality check
# works; reproducing which specific placeholder stat each neutral nature uses would
# add no behavior and only invite confusion for a future reader).
static func _nature_stat_pair(nature_id: int) -> Array[int]:
	match nature_id:
		NATURE_LONELY:  return [STAT_ATK, STAT_DEF]
		NATURE_BRAVE:   return [STAT_ATK, STAT_SPEED]
		NATURE_ADAMANT: return [STAT_ATK, STAT_SPATK]
		NATURE_NAUGHTY: return [STAT_ATK, STAT_SPDEF]
		NATURE_BOLD:    return [STAT_DEF, STAT_ATK]
		NATURE_RELAXED: return [STAT_DEF, STAT_SPEED]
		NATURE_IMPISH:  return [STAT_DEF, STAT_SPATK]
		NATURE_LAX:     return [STAT_DEF, STAT_SPDEF]
		NATURE_TIMID:   return [STAT_SPEED, STAT_ATK]
		NATURE_HASTY:   return [STAT_SPEED, STAT_DEF]
		NATURE_JOLLY:   return [STAT_SPEED, STAT_SPATK]
		NATURE_NAIVE:   return [STAT_SPEED, STAT_SPDEF]
		NATURE_MODEST:  return [STAT_SPATK, STAT_ATK]
		NATURE_MILD:    return [STAT_SPATK, STAT_DEF]
		NATURE_QUIET:   return [STAT_SPATK, STAT_SPEED]
		NATURE_RASH:    return [STAT_SPATK, STAT_SPDEF]
		NATURE_CALM:    return [STAT_SPDEF, STAT_ATK]
		NATURE_GENTLE:  return [STAT_SPDEF, STAT_DEF]
		NATURE_SASSY:   return [STAT_SPDEF, STAT_SPEED]
		NATURE_CAREFUL: return [STAT_SPDEF, STAT_SPATK]
		_: return [-1, -1]  # Hardy/Docile/Serious/Bashful/Quirky — neutral


# [M18.5d-2] Ports AreBattlersOfOppositeGender/AreBattlersOfSameGender
# (battle_util.c L9420-9434) exactly — genderless on EITHER side makes both
# functions false (genderless is neutral, neither "opposite" nor "same" of
# anything). Used by Attract's own gender-gate and Cute Charm's identical gate
# (are_opposite_gender), and by Rivalry's damage modifier (both).
static func are_opposite_gender(mon1: BattlePokemon, mon2: BattlePokemon) -> bool:
	return mon1.gender != GENDER_GENDERLESS and mon2.gender != GENDER_GENDERLESS \
			and mon1.gender != mon2.gender


static func are_same_gender(mon1: BattlePokemon, mon2: BattlePokemon) -> bool:
	return mon1.gender != GENDER_GENDERLESS and mon2.gender != GENDER_GENDERLESS \
			and mon1.gender == mon2.gender


func add_move(move: MoveData) -> void:
	if moves.size() < 4:
		moves.append(move)
		current_pp.append(move.pp)


func has_pp(move_index: int) -> bool:
	if move_index < 0 or move_index >= current_pp.size():
		return false
	return current_pp[move_index] > 0


func use_pp(move_index: int, amount: int = 1) -> void:
	if move_index >= 0 and move_index < current_pp.size() and current_pp[move_index] > 0:
		current_pp[move_index] = max(0, current_pp[move_index] - amount)


# Recalculates all stats from species base stats + level + IVs + EVs + Nature.
# Call after level-up or EV gain. Does not update current_hp.
func _calculate_stats() -> void:
	max_hp    = _hp_formula(species.base_hp,        ivs[STAT_HP],    evs[STAT_HP])
	attack    = _apply_nature(
			_stat_formula(species.base_attack,  ivs[STAT_ATK],   evs[STAT_ATK]), STAT_ATK)
	defense   = _apply_nature(
			_stat_formula(species.base_defense, ivs[STAT_DEF],   evs[STAT_DEF]), STAT_DEF)
	sp_attack = _apply_nature(
			_stat_formula(species.base_sp_attack, ivs[STAT_SPATK], evs[STAT_SPATK]), STAT_SPATK)
	sp_defense = _apply_nature(
			_stat_formula(species.base_sp_defense, ivs[STAT_SPDEF], evs[STAT_SPDEF]), STAT_SPDEF)
	speed     = _apply_nature(
			_stat_formula(species.base_speed,   ivs[STAT_SPEED], evs[STAT_SPEED]), STAT_SPEED)


# Standard Pokémon HP formula (Gen III+):
#   floor((2*base + iv + floor(ev/4)) * level / 100) + level + 10
# [M18.5h-1] HP is NEVER nature-affected (confirmed from source — ModifyStatByNature's
# own `statIndex <= STAT_HP` guard, plus CalculateMonStats computes HP entirely
# outside the loop that even calls it) — this formula has no nature term by design,
# not an oversight.
func _hp_formula(base: int, iv: int, ev: int) -> int:
	return floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0) + level + 10


# Standard non-HP stat formula (Gen III+), BEFORE nature — see _apply_nature, which
# wraps this function's return value at each of its 5 call sites in _calculate_stats.
#   floor((2*base + iv + floor(ev/4)) * level / 100) + 5
func _stat_formula(base: int, iv: int, ev: int) -> int:
	return floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0) + 5


# [M18.5h-1] Applies this Pokémon's Nature to an already-fully-computed non-HP stat
# value (i.e. wraps _stat_formula's return value, matching source's own insertion
# point exactly — ModifyStatByNature is called AFTER CalculateMonStats' base formula
# already includes its `+5` term, pokemon.c L1408). +10%/-10%, floor (C's `stat*110/
# 100`/`stat*90/100` integer division is equivalent to floori() for non-negative
# operands, which stat values always are). Neutral natures ([-1,-1] from
# _nature_stat_pair) fall through both checks and return stat_value completely
# unchanged — bit-identical to the pre-Nature formula, not just "close".
func _apply_nature(stat_value: int, stat_index: int) -> int:
	var pair: Array[int] = _nature_stat_pair(nature)
	if stat_index == pair[0]:
		return floori(stat_value * 110.0 / 100.0)
	if stat_index == pair[1]:
		return floori(stat_value * 90.0 / 100.0)
	return stat_value
