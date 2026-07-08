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

var species: PokemonSpecies = null
var nickname: String = ""
var level: int = 1

# Current battle HP and computed stats (not base stats — those live on species)
var current_hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0
var sp_attack: int = 0
var sp_defense: int = 0
var speed: int = 0

# IVs and EVs are present now so the stat formula reads from them.
# Both zeroed in from_species() for Milestone 1; real values added later.
# Index order matches STAT_* constants above.
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
# M18u: Metronome item's consecutive-same-move-use counter. Compared against
# last_move_used (BEFORE it's overwritten for the current move) at the same
# PP-deduction site source colocates its own reset check
# (battle_move_resolution.c L1006-1008).
var metronome_item_counter: int = 0

# Volatile: flinched. Set when a move with MOVE_EFFECT_FLINCH hits this Pokémon
# before it has acted this turn. Cleared at the start of each turn (PRIORITY_RESOLUTION).
# Source: battle_move_resolution.c :: CancelerFlinch (L298)
var flinched: bool = false

# Volatile: two-turn charge state.
# Non-null on the turn AFTER a charge: the Pokémon is locked to this move and
# it fires when their action executes (release turn).
# Set by BattleManager._phase_move_execution() on turn 1 of a two_turn move;
# cleared by BattleManager._phase_move_execution() on turn 2, and on faint.
# Source: battle_move_resolution.c :: CancelerCharging (L1737); gLockedMoves
var charging_move: MoveData = null

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

# Protect: blocks all incoming moves for one turn.
# protect_consecutive = consecutive Protect uses (0 = first use this streak).
# Cleared (protect_active) and decremented (protect_consecutive maybe) each turn.
# Source: gBattleMons[].volatiles.consecutiveMoveUses; gProtectStructs[].protected
var protect_active: bool = false
var protect_consecutive: int = 0

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

var fainted: bool = false


static func from_species(p_species: PokemonSpecies, p_level: int) -> BattlePokemon:
	var bp := BattlePokemon.new()
	bp.species = p_species
	bp.original_types = p_species.types.duplicate()
	bp.nickname = p_species.species_name
	bp.level = p_level
	bp.ivs = [0, 0, 0, 0, 0, 0]
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


# Recalculates all stats from species base stats + level + IVs + EVs.
# Call after level-up or EV gain. Does not update current_hp.
func _calculate_stats() -> void:
	max_hp    = _hp_formula(species.base_hp,        ivs[STAT_HP],    evs[STAT_HP])
	attack    = _stat_formula(species.base_attack,  ivs[STAT_ATK],   evs[STAT_ATK])
	defense   = _stat_formula(species.base_defense, ivs[STAT_DEF],   evs[STAT_DEF])
	sp_attack = _stat_formula(species.base_sp_attack, ivs[STAT_SPATK], evs[STAT_SPATK])
	sp_defense = _stat_formula(species.base_sp_defense, ivs[STAT_SPDEF], evs[STAT_SPDEF])
	speed     = _stat_formula(species.base_speed,   ivs[STAT_SPEED], evs[STAT_SPEED])


# Standard Pokémon HP formula (Gen III+):
#   floor((2*base + iv + floor(ev/4)) * level / 100) + level + 10
func _hp_formula(base: int, iv: int, ev: int) -> int:
	return floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0) + level + 10


# Standard non-HP stat formula (Gen III+):
#   floor((2*base + iv + floor(ev/4)) * level / 100) + 5
func _stat_formula(base: int, iv: int, ev: int) -> int:
	return floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0) + 5
