class_name MoveData
extends Resource

# Source struct: include/move.h :: struct MoveInfo

# Ban flag bitmask — use BAN_* constants below.
# Source: struct MoveInfo ban flag bitfields (gravityBanned … dampBanned)
const BAN_GRAVITY: int       = 1 << 0
const BAN_MIRROR_MOVE: int   = 1 << 1
const BAN_ME_FIRST: int      = 1 << 2
const BAN_MIMIC: int         = 1 << 3
const BAN_METRONOME: int     = 1 << 4
const BAN_COPYCAT: int       = 1 << 5
const BAN_ASSIST: int        = 1 << 6
const BAN_SLEEP_TALK: int    = 1 << 7
const BAN_INSTRUCT: int      = 1 << 8
const BAN_ENCORE: int        = 1 << 9
const BAN_PARENTAL_BOND: int = 1 << 10
const BAN_SKY_BATTLE: int    = 1 << 11
const BAN_SKETCH: int        = 1 << 12
const BAN_DAMP: int          = 1 << 13

@export var move_name: String = ""
@export var description: String = ""
@export var effect: int = 0         # BattleMoveEffects enum id
@export var type: int = 0           # Type enum id
# category: 0 = Physical, 1 = Special, 2 = Status (per-move field, not per-type)
# Physical/Special split confirmed in struct MoveInfo.category; see decisions.md.
@export var category: int = 0
@export var power: int = 0
@export var accuracy: int = 100     # 0 = always hits
@export var pp: int = 5
@export var priority: int = 0
@export var strike_count: int = 1   # number of hits; defaults to 1
@export var multi_hit: bool = false # random multi-hit (overrides strike_count)
@export var target: int = 0         # MoveTarget enum id

# Move flags — source: struct MoveInfo flag bitfields
@export var makes_contact: bool = false
@export var punching_move: bool = false
@export var biting_move: bool = false
@export var sound_move: bool = false
@export var ballistic_move: bool = false
@export var powder_move: bool = false
@export var dance_move: bool = false
@export var slicing_move: bool = false
@export var healing_move: bool = false
@export var ignores_protect: bool = false
@export var ignores_substitute: bool = false
@export var thaws_user: bool = false
@export var critical_hit_stage: int = 0   # 0–3; added to base crit stage
@export var always_critical_hit: bool = false

# Packed ban flags. Test with: move.ban_flags & MoveData.BAN_X
@export var ban_flags: int = 0
