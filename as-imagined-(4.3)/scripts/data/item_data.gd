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
@export var pocket: int = 0            # Pocket enum id. Was present in the schema
                                        # since M18's item-data infrastructure but
                                        # never actually populated for any item until
                                        # [M18-patch-1], which set POCKET_BERRIES=3
                                        # on every real berry entry to gate Cheek
                                        # Pouch/Harvest/Cud Chew correctly (see
                                        # ItemManager.POCKET_BERRIES).
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

# [M20c] Which stat a Power item boosts EV-gain for — matches
# BattlePokemon.STAT_* ordinal order (HP=0/ATK=1/DEF=2/SPATK=3/SPDEF=4/
# SPEED=5), NOT source's raw `enum Stat` (which places Speed before
# SpAtk/SpDef). -1 = not applicable (every item except the 6 Power items).
# Source: `.secondaryId = STAT_X` per item, `src/data/items.h:8731-8853`.
@export var ev_boost_stat: int = -1

# [M22 Phase 2] Which BATTLE STAT STAGE an X-item (X Attack, etc.) raises —
# matches MoveData's own `stat_change_stat`/`BattlePokemon.STAGE_*` ordinal
# order (ATK=0/DEF=1/SPATK=2/SPDEF=3/SPEED=4/ACCURACY=5/EVASION=6), the SAME
# generic stat-stage dispatch every stat-changing move already reuses —
# deliberately NOT `ev_boost_stat` above, which is a DIFFERENT ordinal
# (BattlePokemon.STAT_*, EV-shaped, HP-inclusive, Speed-before-SpAtk/SpDef)
# for a different mechanic (M20c's EV gain) entirely. Conflating the two
# would silently reproduce this whole project's own well-documented Nature/
# Hidden-Power "Speed ordering" pitfall. -1 = not applicable (every item
# except the X-item family). Source: `.effect[1] = ITEM1_X_ATTACK` etc.
# (`ITEM1_X_ATTACK` is literally `#define`d as source's own `STAT_ATK`,
# src/data/pokemon/item_effects.h), resolved here to this project's STAGE_*
# convention at data-entry time, not carried as a raw source enum value.
@export var stat_boost_stage: int = -1
