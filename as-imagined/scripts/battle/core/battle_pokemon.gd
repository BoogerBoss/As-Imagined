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
var sleep_turns: int = 0  # turns of sleep remaining (drawn on application)

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
