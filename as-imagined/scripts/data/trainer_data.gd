class_name TrainerData
extends Resource

# [M24a] Main per-trainer resource. Source: src/data/trainers.party (855
# entries) — see docs/m24_recon.md §1.2/§1.6/§6 for the full derivation and
# scope decisions this shape reflects. Deliberately excludes (per §6, all
# already-excluded mechanics or deferred to M34, not oversights):
#   - teraType, shouldUseDynamax/gigantamaxFactor/dynamaxLevel (mechanics
#     not in this project at all)
#   - tags / trainer-pool membership fields (Trainer Pools — excluded, §6.1)
#   - overrideTrainer (confirmed via Step 0 source trace to be populated
#     ONLY via trainers.party's own "Copy Pool" field, a Trainer-Pools-only
#     data-sharing mechanism; zero of 855 real trainers use it at all —
#     moot once Trainer Pools itself is excluded)
#   - startingStatus (0 real uses across all 855 trainers — dormant field,
#     not worth carrying)
#   - any MUTABLE "has this trainer been beaten / rematch state" field —
#     rematch_group_id/rematch_tier below are static source data only;
#     save-state progression is M33/M34 territory (§6.5), out of scope here.

# [Step 1] There is no trainer_id. It was an index this project minted by
# sorting keys, so a second roster renumbered 94.6% of it. The canonical,
# origin-suffixed trainer_key below is the identifier, and it is also the
# filename -- see scripts/trainer_keys.py for the suffix rule.
@export var trainer_key: String = ""   # canonical origin-suffixed key, e.g. "TRAINER_BRAWLY_1_RSE"
@export var trainer_name: String = ""  # the in-battle display name, e.g. "Brawly"
@export var trainer_class_id: int = 0  # -> TrainerClassData
# [Step 2 / Rule B] Upstream's own graphics/trainers/front_pics/<stem>.png
# filename stem, verbatim — "leader_roxanne", "brendan_rs", "channeler_frlg".
# Never re-slugified: the stem's whole value is direct traceability to the
# exact source file. Resolves to assets/sprites/trainers/portraits/<stem>.png.
# Replaced trainer_pic_id, a second minted index with the same renumbering
# defect as trainer_id (92.5% of pic ids shift once the Kanto pics land).
@export var pic_stem: String = ""

@export var gender: int = -1           # BattlePokemon.GENDER_* of the trainer themself; -1 if unspecified/not applicable
@export var is_doubles: bool = false

# [§6.2] AI-tier kept narrow, per Rob's own explicit direction: only 6
# distinct AI-flag combinations are used across all 855 real trainers
# (confirmed via direct grep of trainers.party's own "AI:" lines) — this
# int is a small bitmask covering exactly those real combos, not a
# reimplementation of the source's full 64-bit AI_FLAG_* space. Flagged
# for a broader AI engine revisit no earlier than M30 (§6.2, M34 row).
@export var ai_flags: int = 0

@export var battle_items: Array[int] = []  # up to 4 held battle-consumable item ids (Full Restore, etc.), separate from party mons' own held_item_id

@export var mugshot_color: String = ""  # optional; e.g. Sidney's real "Mugshot: Purple" — cosmetic only, empty if unspecified

@export var party: Array[TrainerPartyMon] = []

# Static source data only (see exclusion note above re: no mutable rematch state).
@export var rematch_group_id: int = -1  # -1 = this trainer has no rematch group
@export var rematch_tier: int = 0
