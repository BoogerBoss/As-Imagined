class_name PokemonSpecies
extends Resource

# Battle-relevant species data. Graphics, overworld, and audio fields are
# deliberately absent — those belong in a separate presentation layer (M10+).
# Source struct: include/pokemon.h :: struct SpeciesInfo

@export var species_name: String = ""
@export var national_dex_num: int = 0

# Base stats
@export var base_hp: int = 1
@export var base_attack: int = 1
@export var base_defense: int = 1
@export var base_sp_attack: int = 1
@export var base_sp_defense: int = 1
@export var base_speed: int = 1

# Up to 2 Type enum ids. Second entry = TYPE_NONE (0) if single-typed.
@export var types: Array[int] = []

# 3 ability slots: [standard_1, standard_2, hidden]. Ability enum ids.
@export var abilities: Array[int] = []

@export var catch_rate: int = 45
@export var exp_yield: int = 64
@export var growth_rate: int = 0    # GrowthRate enum id
@export var gender_ratio: int = 127 # 255 = genderless; 0 = always male; 254 = always female
@export var egg_groups: Array[int] = []

# [M19-pre1] weight: hectograms (1 hg = 100g), matching source's own u16 .weight
# field exactly (SpeciesInfo struct, include/pokemon.h L426). Fixed per species,
# no per-instance variance or forcing parameter — unlike gender_ratio/
# base_friendship below, source never rolls or overrides this per individual.
@export var weight: int = 1

# [M19-pre1] base_friendship: species-level STARTING friendship value (0-255),
# matching source's own SpeciesInfo.friendship field (include/pokemon.h L415) —
# most species default to STANDARD_FRIENDSHIP (50, this project's GEN_LATEST
# config), but several genuinely differ (Mewtwo/legendaries=0, Chansey
# family=140, Mew/Celebi/Jirachi=100). BattlePokemon.friendship is rolled from
# this once in from_species — see its own doc comment for the per-instance
# override shape.
@export var base_friendship: int = 50

# Level-up learnset. Each entry: {"level": int, "move_id": int}
# Populated with real data in Milestone 4+; empty for Milestone 1.
@export var learnset: Array[Dictionary] = []
