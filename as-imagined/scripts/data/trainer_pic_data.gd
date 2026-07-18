class_name TrainerPicData
extends Resource

# [M24a] Deliberately separate from TrainerData/trainer_id — see
# docs/m24_recon.md §1.4. Counted directly (not assumed): 855 real trainer
# entries share only ~93 distinct "Pic" values (e.g. "Swimmer M" alone
# covers 34 different trainers). Conflating trainer identity with portrait
# identity would either force 855 duplicate portrait assets or silently
# break the many-share-one-Pic reality. This is intentionally minimal for
# M24a (just the stable id <-> source-name mapping) — Phase 3 (trainer
# portraits) is the consumer that will attach real front/back texture
# paths, and can extend this resource then without this milestone needing
# to guess at that shape now.

@export var pic_id: int = 0
@export var pic_name: String = ""  # the literal "Pic:" value from trainers.party, e.g. "Leader Brawly"
