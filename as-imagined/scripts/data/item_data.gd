class_name ItemData
extends Resource

# Source struct: include/item.h :: struct ItemInfo

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
