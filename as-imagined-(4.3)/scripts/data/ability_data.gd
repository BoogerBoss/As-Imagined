class_name AbilityData
extends Resource

# Source struct: include/pokemon.h :: struct AbilityInfo
# Canonical ability IDs from include/constants/abilities.h

@export var ability_id: int = 0
@export var ability_name: String = ""
@export var description: String = ""
@export var ai_rating: int = 0

# Interaction constraint flags — source: struct AbilityInfo flag bitfields
@export var cant_be_copied: bool = false      # Role Play, Doodle
@export var cant_be_swapped: bool = false     # Skill Swap, Wandering Spirit
@export var cant_be_traced: bool = false      # Trace (subset of cant_be_copied)
@export var cant_be_suppressed: bool = false  # Gastro Acid, Neutralizing Gas
@export var cant_be_overwritten: bool = false # Entrainment, Worry Seed, Simple Beam
@export var breakable: bool = false           # can be bypassed by Mold Breaker and clones
