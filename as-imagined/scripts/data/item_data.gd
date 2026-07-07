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
