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

var fainted: bool = false


static func from_species(p_species: PokemonSpecies, p_level: int) -> BattlePokemon:
	var bp := BattlePokemon.new()
	bp.species = p_species
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
	bp.choice_locked_move = null
	bp.switched_in_this_turn = false
	bp.stat_stages = [0, 0, 0, 0, 0, 0, 0]
	bp.fainted = false
	bp._calculate_stats()
	bp.current_hp = bp.max_hp
	return bp


func add_move(move: MoveData) -> void:
	if moves.size() < 4:
		moves.append(move)
		current_pp.append(move.pp)


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
