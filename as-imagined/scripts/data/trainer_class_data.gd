class_name TrainerClassData
extends Resource

# [M24a] Source struct: src/battle_main.c :: struct TrainerClass /
# gTrainerClasses[] (116 entries) — a plain hardcoded C designated-
# initializer array, NOT part of the trainers.party pipeline at all
# (confirmed via Step 0 direct source inspection — no companion
# trainer_classes.party-style file exists). money defaults to 0 in several
# real entries (e.g. Team Aqua/Magma grunts, PKMN TRAINER) — the real
# money formula (battle_script_commands.c :: GetTrainerMoneyToGive)
# treats 0 as "fall back to 5", reproduced directly in ItemManager/
# battle-outcome code at M24b, not baked into this static data field.

@export var trainer_class_id: int = 0
@export var class_name_text: String = ""  # can't use `name` — Resource already has one
@export var money: int = 0                # raw value as authored; 0 means "falls back to 5" at use time
# [Consistency with TrainerPartyMon.ball_name] Source's own `ball` field
# (both here and on TrainerMon) is the SAME real PokeBall enum — kept as a
# plain string on both, not resolved to a numeric id, since neither struct's
# ball field has any real mechanical consequence in this project yet (no
# Poké Ball catching/item mechanic exists to attach real behavior to).
@export var ball_name: String = "Poke"
