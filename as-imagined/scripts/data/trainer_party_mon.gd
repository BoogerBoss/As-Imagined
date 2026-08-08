@tool
class_name TrainerPartyMon
extends Resource

# [M24a] One Pokémon in a trainer's party. Source struct: include/data.h ::
# struct TrainerMon (reference/pokeemerald_expansion). Confirmed via direct
# Step 0 source inspection (not assumed from the M24 recon's own earlier
# excerpts): trainer mons have a FIXED moveset, EXPLICIT nature/IVs/EVs, and
# an explicit ability — none of these are randomly rolled or
# learnset-derived at battle time, unlike RandomTeamGenerator's own
# members. Feeds directly into BattlePokemon.from_species(species, level,
# nature, ivs, friendship) — that forcing-parameter API (built ahead of
# need in M18.5h) needed zero changes to consume this shape.

@export var species_dex: int = 0
@export var level: int = 100          # trainerproc's own real default when unspecified
@export var nickname: String = ""

# [Real, confirmed-in-data fallback — not hypothetical] Some real trainer
# party mons in trainers.party specify ZERO explicit moves at all (e.g.
# TRAINER_DECLAN's Gyarados). Source (battle_main.c ::
# CustomTrainerPartyAssignMoves) calls GiveMonInitialMoveset in that case,
# which walks the species' own level-up learnset from level 1 upward,
# keeping only the last 4 moves learned by the mon's current level (a
# 4-slot FIFO — pokemon.c :: GiveBoxMonInitialMoveset). This converter
# PRE-COMPUTES that exact fallback at conversion time (see
# gen_trainer_data.py's own doc comment) rather than deferring it to
# battle-time — move_ids is therefore ALWAYS fully resolved here, whether
# the source specified explicit moves or relied on the auto-fill.
@export var move_ids: Array[int] = []

@export var held_item_id: int = 0     # 0 = none
@export var ability_id: int = 0       # 0 = use the species' own default (slot 0/primary)
@export var nature: int = 0           # BattlePokemon.NATURE_* — trainerproc default: Hardy (0)
@export var ivs: Array[int] = [31, 31, 31, 31, 31, 31]  # trainerproc's own real default
@export var evs: Array[int] = [0, 0, 0, 0, 0, 0]
@export var friendship: int = 0
@export var gender: int = -1          # -1 = roll from the species' own gender_ratio; explicit override otherwise
@export var is_shiny: bool = false
@export var ball_name: String = "Poke"  # cosmetic only (which ball animation plays) — kept as a
                                         # plain string, not resolved to an ItemData id; this
                                         # project has no Poké Ball catching/item mechanic to
                                         # attach a real numeric id to yet


## [M27Q Q2 follow-up] Show names instead of raw ids where the id names
## something small enough to pick from a list.
##
## ⚠️ **`species_dex` (386) AND `move_ids` (717) ARE DELIBERATELY LEFT AS
## INTS**, and so is `ability_id` (319) — Rob's call, 2026-08-08. Godot's enum
## control is a plain OptionButton with no typeahead, and a several-hundred-entry
## scroll popup is worse to use than typing the number. The read-only roster
## in the Inspector panel (`TrainerData.describe_party`) is what makes those
## legible instead.
##
## ⚠️ **`ability_id` HAS A TRAP THAT MADE LEAVING IT ALONE THE EASY CALL.**
## `0` here means "use the species' own default" (`battle_pokemon.gd:1171`
## only applies an override when `ability_id > 0`) — but `ability_0000.tres`
## is a real file whose `ability_name` is literally "None". A dropdown built
## from the files would offer "None" at 0, and picking it would read as
## "remove this Pokémon's ability" while actually meaning "give it the species
## default". Two different things. If abilities ever do get a dropdown, entry 0
## must be relabelled `(species default)`.
func _validate_property(property: Dictionary) -> void:
	if property.name == "held_item_id":
		# Shares `InspectorHints.item_hint()` with TrainerData.battle_items —
		# one builder, so the two lists cannot drift. Here `0` genuinely does
		# mean "no item": item ids start at 1 and there is no item_0000.tres.
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = InspectorHints.item_hint()
	elif property.name == "nature":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = InspectorHints.nature_hint()
	elif property.name == "gender":
		# ⚠️ The mon hint, not the trainer one: -1 means "roll from the
		# species' gender_ratio" here and "unspecified" on TrainerData.
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = InspectorHints.mon_gender_hint()
