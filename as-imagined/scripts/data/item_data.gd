class_name ItemData
extends Resource

# Source struct: include/item.h :: struct ItemInfo

# M18 item-data infrastructure: canonical item ID, matching include/constants/items.h
# and this item's data/items/item_NNNN.tres filename. Added alongside gen_items.py/
# ItemRegistry — mirrors AbilityData.ability_id's convention (MoveData has no
# equivalent move_id field; the two existing patterns diverge on this point, and
# this one was picked as the more explicit/self-describing of the two, useful for
# round-trip integrity checks when a caller loads by ID via ItemRegistry).
@export var item_id: int = 0

@export var item_name: String = ""
@export var description: String = ""
@export var hold_effect: int = 0       # holdEffect enum id
@export var hold_effect_param: int = 0 # numeric parameter for the hold effect
@export var pocket: int = 0            # Pocket enum id
@export var importance: int = 0        # 0 = normal, 1 = important, 2 = key item
@export var not_consumed: bool = false
@export var battle_usage: int = 0      # BATTLE_USE_* constant id
@export var fling_power: int = 0
@export var price: int = 0

# M18g: species-gated items (Light Ball, Thick Club, Lucky Punch, etc.). 0 = no
# restriction. `required_species2` covers matched-pair gates (Cubone OR Marowak,
# Latias OR Latios) — 0 = no second species. No precedent for this existed
# anywhere in the codebase before this tier (confirmed at Step 0: Multitype's
# own held-item read, [M17n-4], is a Plate-TYPE check, not a species check) —
# scalar int fields chosen over an Array[int] to match every other ItemData
# field's plain-scalar shape and avoid Godot typed-array .tres serialization
# risk for what is at most a 2-element set.
@export var required_species: int = 0   # national_dex_num, matching PokemonSpecies
@export var required_species2: int = 0  # second species for a matched pair, or 0
