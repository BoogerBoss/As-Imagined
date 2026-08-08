@tool
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


## [M27Q Q2] Render `ai_flags` as real checkboxes in the Inspector.
##
## ⚠️ **THE HINT IS BUILT AT RUNTIME FROM `TrainerAI.FLAG_TABLE`, NOT WRITTEN
## OUT AS `@export_flags`.** That annotation takes literal strings at parse
## time, so it would be a second hand-maintained copy of the flag list that has
## to agree with the first — the identical two-lists-must-agree shape that hid
## a missing CHECK_VIABILITY from 80 trainers until 2026-08-08. Deriving it
## means adding a flag is one edit, in one place, and the checkbox follows.
##
## Godot's explicit-value form (`"Name:value"`) is what makes a sparse set
## expressible: the flags run 1/2/4/8/16 and then jump to 16384, and the
## default positional form would need fifteen entries to reach that bit.
##
## Nothing else about the property changes — it stays a plain `int` on disk, so
## every existing `.tres`, the importer, and `TrainerAI.from_trainer_data` are
## all untouched.
func _validate_property(property: Dictionary) -> void:
	if property.name == "ai_flags":
		property.hint = PROPERTY_HINT_FLAGS
		property.hint_string = TrainerAI.flags_hint_string()
	elif property.name == "trainer_class_id":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = InspectorHints.class_hint()
	elif property.name == "gender":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = InspectorHints.trainer_gender_hint()
	elif property.name == "battle_items":
		# ⚠️ An ARRAY's elements are hinted through PROPERTY_HINT_TYPE_STRING
		# with a packed "<type>/<hint>:<hint_string>" payload — setting
		# PROPERTY_HINT_ENUM on the array itself would hint the array, not the
		# ints inside it. Verified against this engine build.
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [TYPE_INT, PROPERTY_HINT_ENUM, InspectorHints.item_hint()]


## [M27Q Q3] One human-readable line per party member, for the Inspector panel.
##
## ⚠️ **THE FORMATTING RULE LIVES HERE, NOT IN THE PLUGIN.** Which fields
## appear, what an unresolvable id renders as, and what an empty slot means are
## all decisions, and the plugin is the project's one surface with no automated
## coverage. `m24c_test` section I drives this directly; the panel only prints
## what it returns. Same split as `ScriptPreview`.
##
## ⚠️ **AN UNRESOLVED ID RENDERS AS ITS NUMBER, NEVER AS NOTHING.** A move id
## with no shipped `.tres` — this project implements 717 of 935 — would
## otherwise vanish from the line, making a real gap look like a three-move
## Pokémon. `#284` is ugly on purpose: it is the one case worth noticing.
func describe_party() -> PackedStringArray:
	var out := PackedStringArray()
	for m in party:
		if m == null:
			continue
		out.append(_describe_mon(m))
	return out


## dex -> species name, read straight from the JSON.
##
## ⚠️ **DELIBERATELY NOT `PokemonRegistry.get_species()`, AND THE FIRST CUT WAS
## AND IT BROKE IN THE EDITOR.** `PokemonRegistry` is an AUTOLOAD whose script
## is not `@tool`, so it does not execute in the editor at all — every species
## would have rendered as `Species #39`. `MoveRegistry`/`ItemRegistry` are
## plain static classes and are fine; only this one was an autoload. Reading
## the JSON directly costs one parse per session and works identically in the
## editor and at runtime, which is the property a panel needs.
static var _species_names: Dictionary = {}
static var _species_loaded := false


static func species_name_for(dex: int) -> String:
	if not _species_loaded:
		_species_loaded = true
		var f := FileAccess.open("res://data/pokemon.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				for row in (parsed as Array):
					_species_names[int((row as Dictionary).get("dex", 0))] = \
							str((row as Dictionary).get("name", ""))
	return str(_species_names.get(dex, ""))


func _describe_mon(m: TrainerPartyMon) -> String:
	var resolved := species_name_for(m.species_dex)
	var name := resolved if resolved != "" else "Species #%d" % m.species_dex
	var line := "%s · Lv%d" % [name, m.level]
	if m.nickname != "":
		line += " \"%s\"" % m.nickname

	var moves := PackedStringArray()
	for mid in m.move_ids:
		var id := int(mid)
		if id <= 0:
			continue
		var md: MoveData = MoveRegistry.get_move(id)
		moves.append(md.move_name if md != null and md.move_name != "" else "#%d" % id)
	# ⚠️ An empty move list is REAL and common: `trainerproc` leaves moves
	# unspecified and the engine derives them from the level-up learnset at
	# battle start (`compute_fallback_moveset`). Saying so beats an empty
	# bracket, which reads as data loss.
	line += "  [%s]" % (", ".join(moves) if not moves.is_empty()
			else "moves from learnset")

	if m.held_item_id > 0:
		var it: ItemData = ItemRegistry.get_item(m.held_item_id)
		line += "  @%s" % (it.item_name if it != null and it.item_name != ""
				else "#%d" % m.held_item_id)
	return line
