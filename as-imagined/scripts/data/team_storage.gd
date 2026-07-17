class_name TeamStorage
extends RefCounted

# [M23.5] Team persistence — save/load/delete a named team of up to 6
# BattlePokemon "specs" (dex/level/move_ids/nature/evs/ivs/ability_slot —
# exactly team_builder_screen.gd's own `get_current_spec()` shape, i.e.
# exactly PokemonFactory.create_battle_pokemon's own parameter list).
#
# [Format choice — flagged per this milestone's own instruction] Plain JSON
# files under `user://teams/`, one file per team. Chosen for consistency
# with this project's own dominant, already-established data-persistence
# convention: EVERY existing data file (`data/pokemon.json`, `data/moves
# .json`, `data/items.json`, etc.) is JSON, loaded via a FileAccess+
# JSON.parse_string pattern (see PokemonRegistry._load_json — the exact
# shape this class's own _load_json mirrors). `.tres`/Resource WAS
# considered (this project uses it heavily for MoveData/AbilityData/
# ItemData/PokemonSpecies) but rejected for this specific use: every
# existing `.tres` in this project is SHIPPED, STATIC, pre-authored data
# living under `res://data/` — nothing in this codebase has ever used
# ResourceSaver to write USER-GENERATED, mutable save data at runtime, and
# a Resource file embeds a `script_class` reference that's fragile across
# script renames in a way a plain JSON dict never is. `user://` (not
# `res://`) is used because it's Godot's own standard writable,
# persists-across-app-updates location for exactly this kind of
# user-generated save data — `res://` is read-only once exported and this
# project's `data/` tree is itself version-controlled shipped content, not
# a place user saves belong.
#
# [One file per team, not one big teams.json] A single shared file means
# ANY corruption (a bad write, a manual edit gone wrong) loses every saved
# team at once; one file per team means a corrupted file only ever loses
# that ONE team — the others still load fine (see list_teams()'s own
# per-file try/catch-shaped handling). Matches this milestone's own
# "handle a corrupted/missing save file" requirement more gracefully than
# a monolithic file could.
#
# [Duplicate name handling — flagged decision] REJECTED at save time
# (`name_exists()`), not silently overwritten and not auto-renamed. Team
# identity (the filename) is a separately-generated ID (`generate_id()`),
# decoupled from the mutable display name — so renaming a team in a future
# session would be a pure metadata edit, not a file-rename — but for THIS
# milestone, a duplicate name is treated as a genuine "you probably meant
# something else" input error the UI surfaces and asks the user to
# resolve, rather than silently clobbering an existing team under the same
# name (the riskiest of the three options this task offered) or inventing
# an auto-suffix scheme (adds complexity for a "basic roster screen").

const TEAMS_DIR := "user://teams/"
const MAX_TEAM_SIZE := 6


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(TEAMS_DIR)


static func generate_id() -> String:
	# Astronomically unlikely to collide (sub-millisecond calls aside, which
	# a human clicking "Create Team" repeatedly can't produce) — good enough
	# for a local single-user save-file identity, no server/multi-writer
	# concern here.
	return "team_%d_%d" % [Time.get_unix_time_from_system(), randi() % 1000000]


static func list_team_ids() -> Array[String]:
	_ensure_dir()
	var ids: Array[String] = []
	for filename in DirAccess.get_files_at(TEAMS_DIR):
		if filename.ends_with(".json"):
			ids.append(filename.trim_suffix(".json"))
	ids.sort()
	return ids


# Returns one summary Dictionary per saved team: {id, name, member_count,
# corrupted}. A corrupted/unparseable file is still LISTED (never silently
# dropped) so it stays visible and deletable rather than vanishing —
# `name` is a human-readable "(corrupted: <id>)" placeholder and
# `member_count` is 0 in that case.
static func list_teams() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for id in list_team_ids():
		var team := load_team(id)
		if team.is_empty():
			summaries.append({"id": id, "name": "(corrupted: %s)" % id, "member_count": 0, "corrupted": true})
		else:
			summaries.append({
				"id": id, "name": team.get("name", "(unnamed)"),
				"member_count": team.get("members", []).size(), "corrupted": false,
			})
	return summaries


# Returns {} on ANY failure (missing file, unreadable, malformed JSON, or a
# top-level shape that isn't the expected {"name":..., "members":[...]})
# — the one, uniform "this save is unusable" signal every caller checks via
# `.is_empty()`, matching this project's own PokemonRegistry.get_species()
# "return {} for unknown" convention.
static func load_team(id: String) -> Dictionary:
	var path := TEAMS_DIR + id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if not parsed.has("name") or not parsed.has("members") or typeof(parsed["members"]) != TYPE_ARRAY:
		return {}

	# [JSON float gotcha — standing project convention] Every numeric field
	# inside a member spec is re-cast to int explicitly; JSON.parse_string
	# returns numeric values as float, and PokemonFactory.
	# create_battle_pokemon's own int-typed parameters would otherwise
	# silently receive floats.
	var members: Array[Dictionary] = []
	for raw_member in parsed["members"]:
		if typeof(raw_member) != TYPE_DICTIONARY:
			continue
		members.append(_normalize_member_spec(raw_member))

	return {"name": str(parsed["name"]), "members": members}


static func _normalize_member_spec(raw: Dictionary) -> Dictionary:
	var move_ids: Array[int] = []
	for v in raw.get("move_ids", []):
		move_ids.append(int(v))
	var evs: Array[int] = []
	for v in raw.get("evs", [0, 0, 0, 0, 0, 0]):
		evs.append(int(v))
	var ivs: Array[int] = []
	for v in raw.get("ivs", [0, 0, 0, 0, 0, 0]):
		ivs.append(int(v))
	return {
		"dex": int(raw.get("dex", -1)),
		"level": int(raw.get("level", 1)),
		"move_ids": move_ids,
		"nature": int(raw.get("nature", 0)),
		"evs": evs,
		"ivs": ivs,
		"ability_slot": int(raw.get("ability_slot", PokemonFactory.ABILITY_SLOT_PRIMARY)),
	}


# `members` may hold 1-6 entries (a "partial team" — fewer than 6 is
# explicitly valid per this milestone's own edge-case requirement); an
# empty array is rejected (nothing to save) and a >6 array is rejected
# (never constructible through roster_screen.gd's own 6-slot UI, but
# guarded here too since this is also a direct, callable API).
static func save_team(id: String, team_name: String, members: Array[Dictionary]) -> bool:
	if members.is_empty() or members.size() > MAX_TEAM_SIZE:
		return false
	_ensure_dir()

	var path := TEAMS_DIR + id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false

	var payload := {"name": team_name, "members": members}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


# A missing/already-deleted id is a silent no-op (the goal — "this team is
# gone" — is already true), not an error; matches this milestone's own
# "deleting a team that doesn't exist" edge case.
static func delete_team(id: String) -> void:
	var path := TEAMS_DIR + id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# Exact (case-sensitive) match against every non-corrupted saved team's own
# display name. `exclude_id` lets an in-progress EDIT of a team keep its
# own existing name without tripping the duplicate check against itself.
static func name_exists(team_name: String, exclude_id: String = "") -> bool:
	for summary in list_teams():
		if summary["corrupted"]:
			continue
		if summary["id"] == exclude_id:
			continue
		if summary["name"] == team_name:
			return true
	return false


# Reconstructs a real BattlePokemon from a stored spec via PokemonFactory
# directly — zero new stat/moveset logic, this is pure pass-through. Returns
# null if the spec's dex is invalid (mirrors PokemonFactory.
# create_battle_pokemon's own null-on-unknown-dex contract).
static func build_member(spec: Dictionary) -> BattlePokemon:
	return PokemonFactory.create_battle_pokemon(
			int(spec.get("dex", -1)), int(spec.get("level", 1)),
			spec.get("move_ids", []), int(spec.get("nature", 0)),
			spec.get("ivs", [0, 0, 0, 0, 0, 0]), null,
			spec.get("evs", [0, 0, 0, 0, 0, 0]),
			int(spec.get("ability_slot", PokemonFactory.ABILITY_SLOT_PRIMARY)))
