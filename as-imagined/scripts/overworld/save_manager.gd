class_name SaveManager
extends RefCounted

## [M27L L1] Save slots — the box rule made concrete.
##
## ⚠️ **A SLOT IS A PATH PREFIX, AND THAT IS THE WHOLE DESIGN.** The scope doc's
## day-one "box rule" (§0) is that every piece of playthrough state lives inside
## the active slot's payload and nothing playthrough-specific is ever written to
## a shared path. Obeying it is what makes three slots nearly free instead of a
## retrofit — this file adds a directory level and nothing else has to change.
##
## ⚠️ **THREE SLOTS IS THIS PROJECT'S OWN INVENTION, NOT A PORT.** The GBA has
## ONE save: `main_menu.c` knows only `HAS_SAVED_GAME` / `HAS_NO_SAVED_GAME` and
## offers CONTINUE / NEW GAME / OPTION. So there is no reference behaviour to be
## faithful to here, the same standing as this project's Win/Lose screen. Said
## plainly so a later session does not go looking for a `slot` concept in source
## and conclude it was missed.
##
## ⚠️ **UNTRUSTED INPUT, AS A RULE AND NOT A COURTESY.** A save file can be
## hand-edited, copied between machines, or truncated by a crash mid-write. Every
## loader below validates and clamps rather than trusting; a slot that fails to
## parse reports itself empty instead of half-loading. The reference stores an
## executable script buffer (`ramScript`) *inside* its save — the scope doc
## explicitly refuses to inherit that, and this is that principle applied
## throughout.
##
## ⚠️ **`team_storage.gd` IS A KNOWN, RECORDED VIOLATION OF THE BOX RULE AND IS
## LEFT ALONE — Rob's call, 2026-08-03.** It writes simulator teams to a fixed
## `user://teams/`, which is playthrough-ish state at a shared path. It blocks
## nothing here because it is SIMULATOR state, not RPG state, and migrating it
## would mean moving files that already exist on Rob's machine. It gets fixed
## when simulator profiles are actually built, not as a rider on this.

const SAVE_ROOT := "user://saves/"
const SLOT_COUNT := 3
const SAVE_FILE := "slot.json"

## ⚠️ Bumped whenever the payload's SHAPE changes in a way an older build cannot
## read. Written on save, checked on load. A save from the future is refused
## rather than partially understood — the failure mode of guessing is a
## playthrough that looks loaded and is quietly wrong.
const FORMAT_VERSION := 1


static func slot_dir(slot: int) -> String:
	return "%sslot%d/" % [SAVE_ROOT, slot]


static func slot_path(slot: int) -> String:
	return slot_dir(slot) + SAVE_FILE


static func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


## Everything the session holds, as one payload.
##
## ⚠️ Reads `OverworldSession` rather than taking arguments, because that class
## is already the single answer to "what is this playthrough" — every field here
## is one it owns. A caller assembling its own dictionary would be a second
## definition of the save shape.
static func build_payload(map_name: String, cell: Vector2i, facing: int,
		elevation: int, playtime_seconds: int) -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"playtime": maxi(0, playtime_seconds),
		"identity": OverworldSession.identity.to_save(),
		"flags": OverworldSession.flags.to_save(),
		"bag": OverworldSession.bag.to_save(),
		"wallet": OverworldSession.wallet.to_save(),
		"respawn": OverworldSession.respawn.to_save(),
		"party": OverworldSession.player_party().to_save(),
		# [M27G G9] Script-driven object-event changes — source's own
		# `objectEventTemplates` equivalent. Absent from older saves, which
		# `from_save` reads as "no overrides" rather than failing.
		"object_events": ObjectEventState.to_save(),
		# ⚠️ Vector2i does not survive JSON, so the cell is stored as two ints
		# rather than relying on a stringified "(45, 21)" that would have to be
		# parsed back by hand.
		"position": {
			"map": map_name, "x": cell.x, "y": cell.y,
			"facing": facing, "elevation": elevation,
		},
	}


static func save(slot: int, payload: Dictionary) -> bool:
	if not is_valid_slot(slot):
		return false
	if not DirAccess.dir_exists_absolute(slot_dir(slot)):
		var err := DirAccess.make_dir_recursive_absolute(slot_dir(slot))
		if err != OK:
			push_warning("SaveManager: could not create %s" % slot_dir(slot))
			return false
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not write %s" % slot_path(slot))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true


## The raw payload, or an empty dictionary if this slot holds nothing usable.
##
## ⚠️ **AN UNREADABLE SLOT READS AS EMPTY, NOT AS AN ERROR.** A corrupt or
## future-versioned file must not stop the menu from opening — the player still
## needs to be able to start a new game over it.
static func read(slot: int) -> Dictionary:
	if not is_valid_slot(slot) or not FileAccess.file_exists(slot_path(slot)):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	# ⚠️ `JSON.new().parse()` rather than `JSON.parse_string`, and the reason is
	# not style: the static helper PUSHES AN ENGINE ERROR on malformed input.
	# Reading a corrupt slot is a NORMAL, handled event here — a crash mid-write
	# leaves exactly this — so it must not log an error every time the menu lists
	# the slots. (It also makes the corrupt-file test unrunnable under
	# `run_overworld_tests.sh`, which fails any run with an ERROR line.)
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed = j.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var version := int((parsed as Dictionary).get("version", 0))
	if version <= 0 or version > FORMAT_VERSION:
		return {}
	return parsed


static func has_save(slot: int) -> bool:
	return not read(slot).is_empty()


## Apply a payload to the live session. Returns how many party members were
## dropped as unreadable, so a lossy load can be surfaced rather than discovered.
##
## ⚠️ Resets FIRST. Loading into a session that already holds a playthrough would
## otherwise merge the two — the bag of one and the flags of another — which is
## the exact leak `OverworldSession.reset()`'s own header records paying for.
static func apply(payload: Dictionary) -> int:
	OverworldSession.reset()
	OverworldSession.identity.from_save(payload.get("identity", {}))
	OverworldSession.flags.from_save(payload.get("flags", {}))
	OverworldSession.bag.from_save(payload.get("bag", {}))
	OverworldSession.wallet.from_save(payload.get("wallet", {}))
	OverworldSession.respawn.from_save(payload.get("respawn", {}))
	ObjectEventState.from_save(payload.get("object_events", {}))
	TextBuffers.identity = OverworldSession.identity
	var party := BattleParty.new()
	var dropped := party.from_save(payload.get("party", []))
	OverworldSession.party = party
	return dropped


## Where a loaded save puts the player. Shaped like `OverworldSession
## .pending_return` so the overworld's existing resume path consumes it unchanged
## rather than growing a second one.
static func position_of(payload: Dictionary) -> Dictionary:
	var p: Dictionary = payload.get("position", {})
	if p.is_empty():
		return {}
	return {
		"map": str(p.get("map", "")),
		"cell": Vector2i(int(p.get("x", 0)), int(p.get("y", 0))),
		"facing": int(p.get("facing", 0)),
		"elevation": int(p.get("elevation", 0)),
	}


## The CONTINUE card: PLAYER / TIME / POKéDEX / BADGES, source's own four fields
## (`main_menu.c:274-277`).
##
## ⚠️ **POKéDEX IS A REAL STUB AND SAYS SO — Rob's call, 2026-08-03.** There is
## no Pokédex in this project at all; M33 owns it, and nothing anywhere counts
## seen or caught. Rather than fabricate a number, `dex_stub` is true and the
## count is 0, so the card can render four rows while a caller (and this file's
## own test) can tell that one of them is not yet real. When M33 lands it fills
## the count and clears the flag; until then a UI showing "POKéDEX 0" is showing
## a value it has been told is a placeholder.
##
## PLAYER and BADGES are genuine — `[M27K K-b]`'s identity and the badge flags
## `badge_count()` already counts. TIME is genuine as of L1.
static func summary(slot: int) -> Dictionary:
	var payload := read(slot)
	if payload.is_empty():
		return {}
	var ident := PlayerIdentity.new()
	ident.from_save(payload.get("identity", {}))
	var flags := FlagStore.new()
	flags.from_save(payload.get("flags", {}))
	return {
		"player": ident.display_name(),
		"playtime": int(payload.get("playtime", 0)),
		"badges": flags.badge_count(),
		"dex_seen": 0,
		"dex_stub": true,
		"party_size": (payload.get("party", []) as Array).size(),
	}


## Source shows TIME as `H:MM` (`main_menu.c` prints hours and minutes only —
## seconds are tracked in the save block but never displayed here).
static func format_playtime(seconds: int) -> String:
	var s := maxi(0, seconds)
	return "%d:%02d" % [s / 3600, (s % 3600) / 60]


## Tests and a "delete slot" affordance. ⚠️ Removes the slot's DIRECTORY, which
## is only safe because the box rule guarantees nothing shared lives inside it.
static func erase(slot: int) -> void:
	if not is_valid_slot(slot):
		return
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))
	if DirAccess.dir_exists_absolute(slot_dir(slot)):
		DirAccess.remove_absolute(slot_dir(slot))
