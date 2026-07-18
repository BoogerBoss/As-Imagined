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
