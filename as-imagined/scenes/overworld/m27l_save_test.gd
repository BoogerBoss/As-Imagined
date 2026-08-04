extends Node

## [M27L L1] Save slots — serialisation and the round trip.
##
## The claims most worth pinning:
##
##   * a saved Pokémon is a SNAPSHOT, not a recipe — HP, status, PP, nickname and
##     held item all survive, which is exactly what `team_storage`'s 7-field spec
##     cannot express and why L1 did not reuse it;
##   * battle-VOLATILE state does not survive, matching source's own
##     `gPlayerParty`/`gBattleMons` split;
##   * a slot is a path prefix and nothing playthrough-specific escapes it —
##     the box rule, which is the whole reason three slots are cheap;
##   * a save file is UNTRUSTED: corrupt, truncated, future-versioned and
##     hand-edited payloads all fail closed rather than half-loading.

const EXPECTED_TOTAL := 94

## A slot index deliberately outside SLOT_COUNT.
const BAD_SLOT := 9

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	for i in range(SaveManager.SLOT_COUNT):
		SaveManager.erase(i)

	_test_mon_snapshot()
	_test_volatiles()
	_test_containers()
	_test_round_trip()
	_test_untrusted()
	_test_summary()
	_test_save_affordance()
	_test_drive_findings()
	_test_title_screen()
	_test_boot_path()

	for i in range(SaveManager.SLOT_COUNT):
		SaveManager.erase(i)

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27l_save_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## A mon carrying state a RECIPE could not express.
func _damaged_mon() -> BattlePokemon:
	var m := PokemonFactory.create_battle_pokemon(1, 12)
	m.nickname = "SPUD"
	m.current_hp = 7
	m.status = BattlePokemon.STATUS_POISON
	m.toxic_counter = 3
	m.friendship = 143
	m.current_exp = 1234
	m.current_pp[0] = 2
	m.held_item = ItemRegistry.get_item(_potion_id())
	return m


## ⚠️ Resolved by NAME through the registry, not from a constant — this project
## has no `ITEM_*` id constants in GDScript (`[M16c]`-era items are inline-built),
## so a hardcoded int here would be a second, driftable copy of the id.
func _potion_id() -> int:
	return PokemonRegistry.item_id_of("ITEM_POTION")


## --- A. the snapshot ---
func _test_mon_snapshot() -> void:
	var m := _damaged_mon()
	var back := BattlePokemon.from_save(m.to_save())
	_chk("A.01 a saved Pokemon rebuilds at all", back != null)
	if back == null:
		_gated += 9
		return
	# ⚠️ EVERY ONE OF THESE IS A FIELD `team_storage`'s SPEC HAS NO ROOM FOR.
	# That is the whole reason L1 did not reuse it.
	_chk("A.02 the nickname survives", back.nickname == "SPUD")
	_chk("A.03 current HP survives, and is not restored to full",
			back.current_hp == 7 and back.max_hp > 7)
	_chk("A.04 status survives", back.status == BattlePokemon.STATUS_POISON)
	_chk("A.05 the toxic counter survives", back.toxic_counter == 3)
	_chk("A.06 spent PP survives", back.current_pp[0] == 2)
	_chk("A.07 friendship survives", back.friendship == 143)
	_chk("A.08 experience survives", back.current_exp == 1234)
	_chk("A.09 species and level survive",
			back.species.national_dex_num == 1 and back.level == 12)
	# ⚠️ STATS ARE RECOMPUTED, NOT STORED — so they must still come out right.
	_chk("A.10 stats are recomputed and match the original",
			back.max_hp == m.max_hp and back.attack == m.attack
			and back.speed == m.speed)

	# A fainted member is a legal thing to save. 0 HP must not read as "missing"
	# and get defaulted back to full.
	var down := PokemonFactory.create_battle_pokemon(4, 9)
	down.current_hp = 0
	down.fainted = true
	var down_back := BattlePokemon.from_save(down.to_save())
	_chk("A.11 a FAINTED member saves as fainted, not silently healed",
			down_back != null and down_back.current_hp == 0 and down_back.fainted)


## --- B. what must NOT survive ---
func _test_volatiles() -> void:
	# ⚠️ SOURCE'S OWN SPLIT: `gPlayerParty` is what a Pokemon IS, `gBattleMons` is
	# what is happening to it right now. Saving the second would let a mid-battle
	# state outlive a reload.
	var m := PokemonFactory.create_battle_pokemon(1, 12)
	m.confusion_turns = 3
	m.substitute_hp = 20
	m.perish_song_active = true
	m.perish_song_timer = 2
	m.flinched = true
	m.stat_stages[BattlePokemon.STAGE_ATK] = 6
	var row := m.to_save()
	var joined := ",".join(PackedStringArray(row.keys()))
	_chk("B.01 no volatile field is even PRESENT in the payload",
			not joined.contains("confusion") and not joined.contains("substitute")
			and not joined.contains("perish") and not joined.contains("stage"))
	var back := BattlePokemon.from_save(row)
	_chk("B.02 and a reload comes back clean",
			back != null and back.confusion_turns == 0 and back.substitute_hp == 0
			and not back.perish_song_active and not back.flinched)
	_chk("B.03 with stat stages at zero, not the +6 that was saved over",
			back.stat_stages[BattlePokemon.STAGE_ATK] == 0)

	# ⚠️ A TRANSFORMED MON MUST SAVE AS ITSELF. `species` mutates in place, so
	# saving the live value would make a mid-battle Transform permanent.
	var ditto := PokemonFactory.create_battle_pokemon(132, 20)
	var was := ditto.species.national_dex_num
	ditto.species = PokemonRegistry.get_species_resource(25)
	var ditto_back := BattlePokemon.from_save(ditto.to_save())
	_chk("B.04 a species mutation is NOT written back as permanent truth",
			ditto_back != null and ditto_back.species.national_dex_num == was
			and was != 25)


## --- C. the containers ---
func _test_containers() -> void:
	var p := BattleParty.new()
	p.members.append(_damaged_mon())
	p.members.append(PokemonFactory.create_battle_pokemon(4, 9))
	p.active_indices = [0, 1]
	var p2 := BattleParty.new()
	# ⚠️ SEEDED WITH A DOUBLES LAYOUT BEFORE LOADING. A fresh BattleParty already
	# has `active_indices == [0]`, so a fixture that skipped this could not tell
	# "resets on load" from "was never touched" — deleting the reset passed. This
	# is the negation the assertion needs in order to mean anything.
	p2.active_indices = [0, 1]
	var dropped := p2.from_save(p.to_save())
	_chk("C.01 a party round-trips with its members in order",
			p2.members.size() == 2 and p2.members[0].nickname == "SPUD"
			and p2.members[1].species.national_dex_num == 4)
	_chk("C.02 and nothing was dropped", dropped == 0)
	# ⚠️ active_indices is a BATTLE concept and must not be restored — a doubles
	# layout surviving into the field is a real failure, not a cosmetic one.
	_chk("C.03 active_indices resets rather than restoring a doubles layout",
			p2.active_indices.size() == 1 and p2.active_indices[0] == 0)

	# ⚠️ AN UNREADABLE MEMBER IS DROPPED, NOT SUBSTITUTED, and the count says so.
	var p3 := BattleParty.new()
	var lossy := p3.from_save([{"dex": 1, "level": 5}, {"dex": 99999}, "junk"])
	_chk("C.04 an unreadable member is dropped rather than substituted",
			p3.members.size() == 1)
	_chk("C.05 and the loss is REPORTED, not silent", lossy == 2)

	var f := FlagStore.new()
	f.flag_set("FLAG_BADGE01_GET")
	f.flag_set("FLAG_BADGE02_GET")
	f.var_set("VAR_STARTER_MON", 3)
	var f2 := FlagStore.new()
	f2.from_save(f.to_save())
	_chk("C.06 flags and vars round-trip together",
			f2.flag_get("FLAG_BADGE01_GET") and f2.var_get("VAR_STARTER_MON") == 3)
	# ⚠️ BADGES NEED NO FIELD OF THEIR OWN — they ARE flags.
	_chk("C.07 badges ride along in the flags, with no separate store",
			f2.badge_count() == 2)

	var id := PlayerIdentity.new()
	id.set_name("ROB")
	id.set_rival_name("GARY")
	id.gender = PlayerIdentity.Gender.GIRL
	var id2 := PlayerIdentity.new()
	id2.from_save(id.to_save())
	_chk("C.08 identity round-trips, gender included",
			id2.name == "ROB" and id2.rival_name == "GARY"
			and id2.gender == PlayerIdentity.Gender.GIRL)
	# ⚠️ Goes through `set_name`, so a hand-edited save cannot exceed the cap
	# every other path enforces.
	var id3 := PlayerIdentity.new()
	id3.from_save({"name": "ABCDEFGHIJKLMNOPQRST", "gender": 0, "rival": ""})
	_chk("C.09 a hand-edited over-long name is truncated on LOAD, not accepted",
			id3.name.length() == PlayerIdentity.NAME_LENGTH)


## --- D. the slot round trip ---
func _test_round_trip() -> void:
	OverworldSession.reset()
	OverworldSession.identity.set_name("ROB")
	OverworldSession.identity.set_rival_name("GARY")
	OverworldSession.bag.add(_potion_id(), 3)
	OverworldSession.wallet.earn(4321)
	OverworldSession.flags.flag_set("FLAG_BADGE01_GET")
	OverworldSession.flags.var_set("VAR_STARTER_MON", 1)
	var party := BattleParty.new()
	party.members.append(_damaged_mon())
	OverworldSession.party = party

	var payload := SaveManager.build_payload(
			"PalletTown_Frlg", Vector2i(5, 7), 2, 3, 3725)
	_chk("D.01 saving reports success", SaveManager.save(0, payload))
	_chk("D.02 and the slot now has a save", SaveManager.has_save(0))
	# ⚠️ THE BOX RULE, ASSERTED RATHER THAN ASSUMED: slot 0's write must not have
	# put anything in slot 1.
	_chk("D.03 writing slot 0 leaves the other slots empty",
			not SaveManager.has_save(1) and not SaveManager.has_save(2))
	_chk("D.04 and the payload lives UNDER the slot's own prefix",
			SaveManager.slot_path(0).begins_with(SaveManager.slot_dir(0))
			and SaveManager.slot_dir(0) != SaveManager.slot_dir(1))

	# Wipe the live session completely, then load it back.
	OverworldSession.reset()
	_chk("D.05 the session really is empty before loading",
			not OverworldSession.identity.is_named()
			and OverworldSession.wallet.money == 0)

	# ⚠️ **DIRTY THE FIELDS THE PAYLOAD DOES NOT COVER, WHICH IS A SHORTER LIST
	# THAN IT LOOKS.** A first version of this seeded money/bag/flags and was
	# VACUOUS — deleting `apply`'s own `reset()` still passed, because every
	# `from_save` already clears its own container first (`Bag.from_save` calls
	# `clear()`, `FlagStore.from_save` rebuilds both dictionaries, `Wallet`
	# assigns). So the ONLY state `reset()` uniquely clears is the pending
	# battle-return trio, and that is what this has to assert on.
	#
	# It is a real leak, not a theoretical one: loading a save while a battle
	# return is pending would resume the loaded playthrough into the PREVIOUS
	# one's map and cell.
	OverworldSession.pending_trainer_key = "SOMEONE_ELSE"
	OverworldSession.save_position("AnotherMap_Frlg", Vector2i(99, 99), 1, 0)
	OverworldSession.set_result(null)

	var read_back := SaveManager.read(0)
	var dropped := SaveManager.apply(read_back)
	_chk("D.05b loading clears a PENDING BATTLE RETURN rather than inheriting it",
			not OverworldSession.has_pending_return()
			and OverworldSession.pending_trainer_key == "")
	_chk("D.06 the load drops nothing", dropped == 0)
	_chk("D.07 the player comes back", OverworldSession.identity.name == "ROB")
	_chk("D.08 the money comes back", OverworldSession.wallet.money == 4321)
	_chk("D.09 the bag comes back",
			OverworldSession.bag.count_of(_potion_id()) == 3)
	_chk("D.10 the flags and vars come back",
			OverworldSession.flags.flag_get("FLAG_BADGE01_GET")
			and OverworldSession.flags.var_get("VAR_STARTER_MON") == 1)
	_chk("D.11 the damaged party comes back damaged",
			OverworldSession.party.members.size() == 1
			and OverworldSession.party.members[0].nickname == "SPUD"
			and OverworldSession.party.members[0].current_hp == 7)
	# ⚠️ `{PLAYER}` must follow the load. Without this, a loaded save renders
	# every one of the corpus's 1193 uses as the fallback name.
	_chk("D.12 and {PLAYER} follows the load, not the fallback",
			TextBuffers.new().expand("{PLAYER}") == "ROB")

	var pos := SaveManager.position_of(read_back)
	_chk("D.13 the position round-trips, Vector2i included",
			str(pos.get("map", "")) == "PalletTown_Frlg"
			and pos.get("cell") == Vector2i(5, 7)
			and int(pos.get("facing", -1)) == 2
			and int(pos.get("elevation", -1)) == 3)
	# ⚠️ Shaped like `pending_return` so the overworld's existing resume path
	# consumes it unchanged rather than growing a second one.
	_chk("D.14 in the same shape the battle-return path already consumes",
			pos.has("map") and pos.has("cell") and pos.has("facing")
			and pos.has("elevation"))


## --- E. untrusted input ---
func _test_untrusted() -> void:
	_chk("E.01 an empty slot reads as empty, not as an error",
			SaveManager.read(1).is_empty() and not SaveManager.has_save(1))
	_chk("E.02 an out-of-range slot is refused rather than writing somewhere",
			not SaveManager.save(BAD_SLOT, {"version": 1})
			and not SaveManager.is_valid_slot(BAD_SLOT))

	# ⚠️ A TRUNCATED FILE — what a crash mid-write leaves behind.
	DirAccess.make_dir_recursive_absolute(SaveManager.slot_dir(1))
	var f := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"party\": [")
	f.close()
	_chk("E.03 a truncated file reads as empty rather than half-loading",
			SaveManager.read(1).is_empty())
	# ⚠️ AND THE MENU MUST STILL WORK OVER IT — the player needs to be able to
	# start a new game on top of a corrupt slot.
	_chk("E.04 and the slot can still be written over",
			SaveManager.save(1, {"version": SaveManager.FORMAT_VERSION}))
	SaveManager.erase(1)

	# ⚠️ A SAVE FROM THE FUTURE IS REFUSED, not partially understood.
	SaveManager.save(2, {"version": SaveManager.FORMAT_VERSION + 1})
	_chk("E.05 a future format version is refused", SaveManager.read(2).is_empty())
	SaveManager.erase(2)
	# A version of 0 or missing is equally not ours.
	SaveManager.save(2, {"party": []})
	_chk("E.06 and so is a payload with no version at all",
			SaveManager.read(2).is_empty())
	SaveManager.erase(2)

	# Hand-edited nonsense in a field that reaches a clamp.
	var mon := BattlePokemon.from_save({"dex": 1, "level": 9999, "hp": 999999})
	_chk("E.07 a hand-edited level is clamped, not trusted",
			mon != null and mon.level == 100)
	_chk("E.08 and HP cannot exceed the recomputed max",
			mon.current_hp == mon.max_hp)
	_chk("E.09 a bad species returns null rather than a half-built Pokemon",
			BattlePokemon.from_save({"dex": 99999}) == null
			and BattlePokemon.from_save({}) == null)


## --- F. the CONTINUE card ---
func _test_summary() -> void:
	OverworldSession.reset()
	OverworldSession.identity.set_name("ROB")
	OverworldSession.flags.flag_set("FLAG_BADGE01_GET")
	OverworldSession.flags.flag_set("FLAG_BADGE02_GET")
	OverworldSession.flags.flag_set("FLAG_BADGE03_GET")
	var party := BattleParty.new()
	party.members.append(PokemonFactory.create_battle_pokemon(1, 5))
	OverworldSession.party = party
	SaveManager.save(0, SaveManager.build_payload(
			"PalletTown_Frlg", Vector2i(0, 0), 0, 3, 3725))

	var s := SaveManager.summary(0)
	# Source's own four fields (`main_menu.c:274-277`).
	_chk("F.01 PLAYER is real", str(s.get("player", "")) == "ROB")
	_chk("F.02 BADGES is real, counted from the flags", int(s.get("badges", -1)) == 3)
	_chk("F.03 TIME is real", int(s.get("playtime", -1)) == 3725)
	_chk("F.04 and TIME formats as source's H:MM",
			SaveManager.format_playtime(3725) == "1:02")
	# ⚠️ **POKéDEX IS A STUB AND THE PAYLOAD SAYS SO** — Rob's call. M33 owns the
	# Pokédex and nothing counts seen/caught, so the card gets its fourth row
	# without a fabricated number. This assertion is what stops a later session
	# reading `dex_seen == 0` as a real count.
	_chk("F.05 POKeDEX is flagged as a STUB, not passed off as a real count",
			bool(s.get("dex_stub", false)) and int(s.get("dex_seen", -1)) == 0)
	_chk("F.06 an empty slot has no summary at all",
			SaveManager.summary(1).is_empty())
	SaveManager.erase(0)


## --- G. [M27L L2] the SAVE affordance and the playtime counter ---
func _test_save_affordance() -> void:
	# ⚠️ **UNCONDITIONAL, WHERE THE TWO ENTRIES ABOVE IT ARE NOT.**
	# `BuildNormalStartMenu` gates POKéDEX and POKéMON on flags and then adds
	# SAVE with no condition at all (`start_menu.c:349`) — you can save before you
	# own a single Pokémon. A fixture with the flags SET could not tell an
	# unconditional entry from a gated one, so this uses an empty store.
	var bare := FieldStartMenu.build_entries(FlagStore.new())
	_chk("G.01 SAVE is offered with no flags set at all",
			bare.has(FieldStartMenu.Entry.SAVE))
	_chk("G.02 while POKeDEX and POKeMON are still correctly absent",
			not bare.has(FieldStartMenu.Entry.POKEDEX)
			and not bare.has(FieldStartMenu.Entry.POKEMON))
	# ⚠️ Source's order: ... BAG, [PLAYER], SAVE, [OPTION], EXIT. SAVE sits
	# BEFORE EXIT, and a list that appended it last would still contain it.
	var full := FlagStore.new()
	full.flag_set("FLAG_SYS_POKEDEX_GET")
	full.flag_set("FLAG_SYS_POKEMON_GET")
	var entries := FieldStartMenu.build_entries(full)
	_chk("G.03 and it sits before EXIT, in source's own order",
			entries.find(FieldStartMenu.Entry.SAVE)
			< entries.find(FieldStartMenu.Entry.EXIT)
			and entries.find(FieldStartMenu.Entry.SAVE)
			> entries.find(FieldStartMenu.Entry.BAG))

	var menu := FieldStartMenu.new()
	add_child(menu)
	menu.open(full)
	var fired: Array[bool] = []
	menu.save_selected.connect(func() -> void: fired.append(true))
	# Walk down to SAVE the way a player would, rather than reaching past the
	# widget to set the index — the cursor has to be able to REACH it.
	for i in range(entries.size()):
		if entries[menu.index] == FieldStartMenu.Entry.SAVE:
			break
		menu.move(1)
	_chk("G.03b and the cursor can actually reach it",
			entries[menu.index] == FieldStartMenu.Entry.SAVE)
	menu.confirm()
	_chk("G.04 picking it reports the choice and closes",
			fired.size() == 1 and not menu.is_open)
	menu.free()

	# ⚠️ ACCUMULATED AS A FLOAT. Ticking `+= delta` into an int truncates every
	# frame — at 60 fps that loses most of an hour per hour, which looks like a
	# working counter right up until someone reads it.
	OverworldSession.reset()
	_chk("G.05 a new playthrough starts at zero",
			OverworldSession.playtime_seconds() == 0)
	for i in range(600):
		OverworldSession.tick_playtime(1.0 / 60.0)
	_chk("G.06 sub-second ticks accumulate rather than truncating to zero",
			OverworldSession.playtime_seconds() == 10)
	# ⚠️ **TRUNCATES, NEVER ROUNDS UP.** Summing exact 1/60 ticks lands epsilon
	# BELOW the integer (3600 of them give 59.999999999999986), so an hour of
	# play can report one second short. That is the correct direction: "whole
	# seconds played" must never claim a second the player has not finished.
	# This pins the direction so a later session cannot "fix" it with `round()`,
	# which would over-report at every single read.
	OverworldSession.reset()
	for i in range(3600):
		OverworldSession.tick_playtime(1.0 / 60.0)
	var secs := OverworldSession.playtime_seconds()
	_chk("G.06b and it never reports MORE time than was played",
			secs <= 60 and secs >= 59)
	OverworldSession.reset()
	OverworldSession.tick_playtime(9.99)
	_chk("G.06c a part-second is dropped, not rounded up to the next one",
			OverworldSession.playtime_seconds() == 9)
	# The overworld's own text is source's, verbatim from `data/text/save.inc`.
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	_chk("G.07 the save flow uses source's own three lines",
			str(ow.SAVE_CONFIRM) == "Would you like to save the game?"
			and str(ow.SAVE_IN_PROGRESS).contains("DON'T TURN OFF THE POWER")
			and str(ow.SAVE_DONE).contains("{PLAYER}"))
	_chk("G.08 and the report is a PLACEHOLDER, expanded at print time",
			TextBuffers.new().expand(str(ow.SAVE_DONE)).contains("saved the game")
			and not str(ow.SAVE_DONE).contains("LEAF"))
	ow.free()


## --- H. two bugs the L2 LIVE DRIVE found, neither of them L2's own ---
func _test_drive_findings() -> void:
	# ⚠️ **`{PLAYER}` RENDERED THE FALLBACK FOR A NAMED PLAYER.**
	# `TextBuffers.identity` is written in exactly ONE place
	# (`OverworldSession.reset()`), so a session named through any other path left
	# it pointing elsewhere — the drive saved as ROB and printed "LEAF saved the
	# game." A fixture that SET `TextBuffers.identity` could not see this, which
	# is why this one deliberately clears it.
	OverworldSession.reset()
	TextBuffers.identity = null
	OverworldSession.identity.set_name("ROB")
	_chk("H.01 {PLAYER} follows the SESSION even with no override set",
			TextBuffers.new().expand("{PLAYER}") == "ROB")
	var other := PlayerIdentity.new()
	other.set_name("OTHER")
	TextBuffers.identity = other
	_chk("H.02 and an explicit override still wins, for the test sites that use it",
			TextBuffers.new().expand("{PLAYER}") == "OTHER")
	TextBuffers.identity = null
	# And with nothing named anywhere, the fallback is still a name.
	OverworldSession.reset()
	TextBuffers.identity = null
	_chk("H.03 with nobody named at all it still reads as a name, not a blank",
			TextBuffers.new().expand("{PLAYER}") != "")

	# ⚠️ **A YES/NO OPENED OUTSIDE THE SCRIPT VM HAD NO INPUT DRIVER.** The only
	# one lived in `_drive_script`'s WAIT_YES_NO branch, so `[M27K K-b]`'s gender
	# question could never be answered from the keyboard. Asserted on the SHAPE of
	# `_process`, which is all a headless test can reach — the behaviour itself
	# was confirmed by the live drive.
	var src := FileAccess.open("res://scenes/overworld/overworld.gd",
			FileAccess.READ).get_as_text()
	var vm_branch := src.find("ScriptVM.Pause.WAIT_YES_NO")
	var free_branch := src.find("_vm == null and _yes_no != null and _yes_no.is_open")
	_chk("H.04 a yes/no outside the VM has an input driver at all",
			free_branch >= 0)
	_chk("H.05 and it is a SECOND one, not the VM's own branch moved",
			vm_branch >= 0 and free_branch < vm_branch)
	# ⚠️ It must sit ABOVE the message-box block, because a yes/no draws OVER the
	# message it is asking about and has to take the input first.
	var box_branch := src.find("_vm == null and _box != null and _box.is_open")
	_chk("H.06 and it takes input BEFORE the message box underneath it",
			box_branch >= 0 and free_branch < box_branch)


## --- I. [M27L L3] the title screen and slot selection ---
func _test_title_screen() -> void:
	for i in range(SaveManager.SLOT_COUNT):
		SaveManager.erase(i)

	var t := TitleScreen.new()
	add_child(t)
	t.open()
	_chk("I.01 it opens on the first slot", t.is_open and t.index == 0)
	# ⚠️ AN EMPTY SLOT IS ONE LINE, NOT A CARD OF BLANKS. Four empty fields read
	# as a broken save rather than a free slot.
	_chk("I.02 an empty slot offers NEW GAME and nothing else",
			t.card_lines(0).size() == 1
			and str(t.card_lines(0)[0]) == TitleScreen.NEW_GAME)
	_chk("I.03 and reports itself as having no save", not t.slot_has_save(0))

	# ⚠️ CLAMPS rather than wrapping — deliberately unlike source's start menu.
	# A wrap on a three-item list makes it easy to overshoot onto a save you did
	# not mean to overwrite.
	t.move(-1)
	_chk("I.04 up on the first slot CLAMPS rather than wrapping to the last",
			t.index == 0)
	t.move(99)
	_chk("I.05 and down clamps at the last", t.index == SaveManager.SLOT_COUNT - 1)

	var got: Array = []
	t.slot_chosen.connect(func(s: int, is_new: bool) -> void: got.append([s, is_new]))
	t.confirm()
	_chk("I.06 confirming an empty slot reports it as a NEW GAME",
			got.size() == 1 and int(got[0][0]) == SaveManager.SLOT_COUNT - 1
			and bool(got[0][1]))
	t.free()

	# Now put a real save in slot 1 and check the card.
	OverworldSession.reset()
	OverworldSession.identity.set_name("ROB")
	OverworldSession.flags.flag_set("FLAG_BADGE01_GET")
	OverworldSession.flags.flag_set("FLAG_BADGE02_GET")
	var party := BattleParty.new()
	party.members.append(_damaged_mon())
	OverworldSession.party = party
	SaveManager.save(1, SaveManager.build_payload(
			"PalletTown_Frlg", Vector2i(5, 7), 2, 3, 3725))

	var t2 := TitleScreen.new()
	add_child(t2)
	t2.open()
	_chk("I.07 a filled slot reports itself as having a save",
			t2.slot_has_save(1) and not t2.slot_has_save(0))
	var card := " | ".join(t2.card_lines(1))
	# Source's own four fields, in source's own order (`main_menu.c:274-277`).
	_chk("I.08 its card is CONTINUE plus source's own fields",
			card.begins_with(TitleScreen.CONTINUE) and card.contains("PLAYER")
			and card.contains("TIME") and card.contains("BADGES"))
	_chk("I.09 with the real player, time and badge count on it",
			card.contains("ROB") and card.contains("1:02") and card.contains("2"))
	# ⚠️ THE POKeDEX ROW IS A STUB AND SAYS SO ON THE CARD. Source would omit the
	# row entirely (`main_menu.c:2193` gates it on FLAG_SYS_POKEDEX_GET); Rob's
	# call was to show it marked. This pins that it is LABELLED, so no later
	# session reads the 0 as a real count.
	_chk("I.10 and a POKeDEX row that is visibly not yet real",
			card.contains("POKéDEX") and card.contains("not yet tracked"))

	# ⚠️ The screen must reflect DISK, not memory — a slot deleted since the last
	# open has to read empty.
	SaveManager.erase(1)
	t2.open()
	_chk("I.11 re-opening re-reads disk rather than trusting what it had",
			not t2.slot_has_save(1))
	t2.free()

	# --- CONTINUE itself ---
	SaveManager.save(2, SaveManager.build_payload(
			"PalletTown_Frlg", Vector2i(5, 7), 2, 3, 3725))
	OverworldSession.reset()
	TextBuffers.identity = null
	var resume := TitleScreen.begin_continue(2)
	_chk("I.12 continuing loads the playthrough back into the session",
			OverworldSession.identity.name == "ROB"
			and OverworldSession.party.members.size() == 1
			and OverworldSession.party.members[0].current_hp == 7)
	# ⚠️ RETURNS `pending_return`'s OWN SHAPE, so the overworld's existing
	# post-battle resume path consumes it unchanged rather than growing a second.
	_chk("I.13 and hands back a resume position in pending_return's shape",
			str(resume.get("map", "")) == "PalletTown_Frlg"
			and resume.get("cell") == Vector2i(5, 7)
			and resume.has("facing") and resume.has("elevation"))
	# ⚠️ **THE EMPTY RETURN IS NOT THE POINT — THE SESSION SURVIVING IS.** A first
	# version asserted only `begin_continue(0).is_empty()` and was VACUOUS:
	# deleting the guard still returns empty, because `position_of({})` is empty
	# too. The real damage of dropping it is that `apply({})` runs and WIPES the
	# live playthrough, so a mis-aimed CONTINUE on a blank slot would erase the
	# session in memory. That is what this checks.
	OverworldSession.reset()
	OverworldSession.identity.set_name("STILLHERE")
	var untouched := TitleScreen.begin_continue(0)
	_chk("I.14 an empty slot cannot be continued into",
			untouched.is_empty())
	_chk("I.14b and the attempt leaves the live playthrough alone",
			OverworldSession.identity.name == "STILLHERE")
	SaveManager.erase(2)


## --- J. [M27L L4] the boot path ---
func _test_boot_path() -> void:
	# ⚠️ **A SECOND ENTRY POINT, NOT A REPLACEMENT — Rob's call.** `main_scene`
	# stays the SIMULATOR's; repointing it would change what launching the
	# project means for the half that has used it since [M23.0b].
	_chk("J.01 main_scene is still the simulator's own entry point",
			str(ProjectSettings.get_setting("application/run/main_scene"))
			== "res://scenes/main.tscn")
	var main: Control = load("res://scenes/main.tscn").instantiate() as Control
	_chk("J.02 and it offers BOTH, as real scene-tree nodes",
			main.get_node_or_null("VBoxContainer/PingButton") != null
			and main.get_node_or_null("VBoxContainer/AdventureButton") != null)
	# Both targets must actually exist — a boot button pointing at a missing
	# scene fails at the press, which is the worst moment to find out.
	_chk("J.03 both destinations resolve",
			ResourceLoader.exists(str(main.BATTLE_SCENE))
			and ResourceLoader.exists(str(main.RPG_SCENE)))
	_chk("J.04 and the RPG one leads to slot selection, not straight to the field",
			str(main.RPG_SCENE).contains("title"))
	main.free()

	# ⚠️ THE SLOT MUST SURVIVE A BATTLE. It lived on the overworld in L2, which a
	# scene swap discards — the next SAVE would then write to slot 0 whatever the
	# player had chosen.
	OverworldSession.reset()
	OverworldSession.active_slot = 2
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	_chk("J.05 the field reads its slot from the SESSION, not its own copy",
			ow.active_slot == 2)
	ow.free()

	# ⚠️ CONSUMED ON READ. A flag left set would re-run Oak's speech every time
	# the overworld rebuilt — which is after every single battle.
	OverworldSession.pending_new_game = true
	_chk("J.06 the new-game flag is taken once", OverworldSession.take_new_game())
	_chk("J.07 and is gone the second time, so a battle cannot re-run the speech",
			not OverworldSession.take_new_game()
			and not OverworldSession.pending_new_game)
	# And reset clears both, so a fresh session cannot inherit either.
	OverworldSession.active_slot = 1
	OverworldSession.pending_new_game = true
	OverworldSession.reset()
	_chk("J.08 reset clears the slot and the flag together",
			OverworldSession.active_slot == 0
			and not OverworldSession.pending_new_game)
