extends Node

# [M24a] Trainer Data Pipeline smoke test — mirrors move_smoke_test.gd's own
# convention (one assertion per catalog entry, loaded through the real
# Registry rather than raw Resource.load, since TrainerRegistry/
# TrainerPicRegistry/TrainerClassRegistry are themselves thin path-convention
# wrappers this test also exercises).
#
# Covers all three .tres catalogs emitted by scripts/gen_trainer_data.py
# (trainers / trainer_classes; the trainer_pics id space was retired in Step 2
# in favour of upstream-verbatim portrait stems) plus targeted spot-checks
# against the Step 0 sample (Brawly/Sidney/Declan) verifying specific
# field values, not just "it loads".

var _pass := 0
var _fail := 0

# [Step 4] Both rosters: 854 Hoenn/Emerald (_RSE) + 623 Kanto (_FRLG).
# 623, not 624 -- TRAINER_NONE is a blank sentinel excluded from the Kanto
# roster exactly as it already was from Hoenn.
const TRAINER_COUNT := 1477
const TRAINER_COUNT_RSE := 854
const TRAINER_COUNT_FRLG := 623
const TRAINER_CLASS_COUNT := 117


func _ready() -> void:
	_test_every_trainer_loads()
	_test_unsuffixed_keys_do_not_resolve()
	_test_every_trainer_class_loads()
	_test_spot_check_brawly()
	_test_spot_check_roxanne()
	_test_spot_check_lass_robin_frlg()
	_test_spot_check_sidney()
	_test_spot_check_declan()

	var total := _pass + _fail
	print("trainer_data_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_every_trainer_loads() -> void:
	# [Step 1] Iterate the DIRECTORY by key, not an id range. The hard count is
	# asserted first and separately so the loop below cannot pass vacuously
	# against a half-populated (or empty) directory — a key-driven loop over
	# nothing would otherwise be silently green.
	var keys := TrainerRegistry.all_keys()
	_chk("exactly %d trainer files on disk (got %d)" % [TRAINER_COUNT, keys.size()],
			keys.size() == TRAINER_COUNT)

	var suffixed := 0
	var n_rse := 0
	var n_frlg := 0
	for key in keys:
		var t: TrainerData = TrainerRegistry.get_trainer_by_key(key)
		# The filename IS the key: a resource whose own trainer_key disagrees
		# with the file it was loaded from would break every lookup path.
		var ok := t != null and t is TrainerData and t.trainer_key == key \
				and not t.trainer_key.is_empty() and t.party.size() > 0
		_chk("%s loads as a valid, self-consistent TrainerData" % key, ok)
		if key.ends_with("_RSE"):
			suffixed += 1
			n_rse += 1
		elif key.ends_with("_FRLG"):
			suffixed += 1
			n_frlg += 1
		if ok:
			for mon in t.party:
				_chk("%s party member is a valid TrainerPartyMon with a resolved species" % key,
						mon is TrainerPartyMon and mon.species_dex > 0)
	_chk("every key carries an origin suffix (Rule A)", suffixed == keys.size())
	# Per-origin counts, so a roster silently failing to convert cannot hide
	# inside a correct-looking grand total.
	_chk("%d Hoenn/Emerald trainers (_RSE), got %d" % [TRAINER_COUNT_RSE, n_rse],
			n_rse == TRAINER_COUNT_RSE)
	_chk("%d Kanto trainers (_FRLG), got %d" % [TRAINER_COUNT_FRLG, n_frlg],
			n_frlg == TRAINER_COUNT_FRLG)


## [Step 1] Bare, unsuffixed keys must NOT resolve. No alias layer, no
## fallback — two spellings per trainer would make the origin suffix optional
## and defeat the reason it exists.
func _test_unsuffixed_keys_do_not_resolve() -> void:
	for bare in ["TRAINER_ROXANNE_1", "TRAINER_BRAWLY_1", "TRAINER_SIDNEY"]:
		_chk("bare %s does not resolve" % bare,
				not TrainerRegistry.has_trainer_key(bare))
	_chk("but its canonical form does",
			TrainerRegistry.has_trainer_key("TRAINER_ROXANNE_1_RSE"))


func _test_every_trainer_class_loads() -> void:
	for id in range(TRAINER_CLASS_COUNT):
		var tc: TrainerClassData = TrainerClassRegistry.get_trainer_class(id)
		_chk("TrainerClass %d loads as a valid, self-consistent TrainerClassData" % id,
				tc != null and tc is TrainerClassData and tc.trainer_class_id == id)


func _test_spot_check_brawly() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1_RSE")
	if t == null:
		_chk("TRAINER_BRAWLY_1_RSE resolves via get_trainer_by_key", false)
		return
	_chk("Brawly: trainer_name is BRAWLY", t.trainer_name == "BRAWLY")
	_chk("Brawly: party has 3 members", t.party.size() == 3)
	_chk("Brawly: gender is Male", t.gender == 0)
	_chk("Brawly: ai_flags is Basic Trainer (7)", t.ai_flags == 7)

	var tc: TrainerClassData = TrainerClassRegistry.get_trainer_class(t.trainer_class_id)
	_chk("Brawly: trainer class is LEADER", tc != null and tc.class_name_text == "LEADER")
	_chk("Brawly: trainer class ball is Ultra", tc != null and tc.ball_name == "Ultra")

	_chk("Brawly: pic_stem is leader_brawly (Rule B, upstream verbatim)",
			t.pic_stem == "leader_brawly")

	if t.party.size() == 3:
		var machop: TrainerPartyMon = t.party[0]
		_chk("Brawly Machop: species_dex is 66", machop.species_dex == 66)
		_chk("Brawly Machop: level is 16", machop.level == 16)
		_chk("Brawly Machop: ivs are all 12", machop.ivs == [12, 12, 12, 12, 12, 12])
		_chk("Brawly Machop: 4 moves resolved", machop.move_ids.size() == 4)

		var makuhita: TrainerPartyMon = t.party[2]
		_chk("Brawly Makuhita: holds Sitrus Berry (item 523)", makuhita.held_item_id == 523)


func _test_spot_check_roxanne() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")
	if t == null:
		_chk("TRAINER_ROXANNE_1_RSE resolves via get_trainer_by_key", false)
		return
	_chk("Roxanne: trainer_name is ROXANNE", t.trainer_name == "ROXANNE")
	_chk("Roxanne: party has 3 members", t.party.size() == 3)
	_chk("Roxanne: ai_flags is Basic Trainer (7)", t.ai_flags == 7)
	_chk("Roxanne: carries 2 battle items", t.battle_items.size() == 2)
	if t.party.size() == 3:
		var geodude_a: TrainerPartyMon = t.party[0]
		var geodude_b: TrainerPartyMon = t.party[1]
		var nosepass: TrainerPartyMon = t.party[2]
		_chk("Roxanne #1 Geodude: dex 74 at level 12",
				geodude_a.species_dex == 74 and geodude_a.level == 12)
		_chk("Roxanne #2 Geodude: dex 74 at level 12",
				geodude_b.species_dex == 74 and geodude_b.level == 12)
		_chk("Roxanne #3 Nosepass: dex 299 at level 15",
				nosepass.species_dex == 299 and nosepass.level == 15)
		_chk("Roxanne Nosepass holds item 520", nosepass.held_item_id == 520)
		_chk("Roxanne Nosepass has its 4 real moves",
				nosepass.move_ids == [335, 106, 33, 317])
		_chk("Roxanne Geodude ivs are all 12", geodude_a.ivs == [12, 12, 12, 12, 12, 12])


## [Step 4] Kanto content anchor. Deep-checked against trainers_frlg.party
## directly: the Hoenn anchors above would all still pass if the FRLG roster
## converted to garbage, so at least one Kanto trainer has to assert real values.
func _test_spot_check_lass_robin_frlg() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_LASS_ROBIN_FRLG")
	if t == null:
		_chk("TRAINER_LASS_ROBIN_FRLG resolves via get_trainer_by_key", false)
		return
	_chk("Robin: trainer_name is ROBIN", t.trainer_name == "ROBIN")
	_chk("Robin: party has 1 member", t.party.size() == 1)
	_chk("Robin: ai_flags is Check Bad Move (1)", t.ai_flags == 1)
	# Source really does say "Gender: Male" for this Lass -- that field is the
	# trainer's own sprite gender, and its "Music: Female" line is separate.
	# Asserted as-is rather than "corrected" to what the class implies.
	_chk("Robin: gender is Male, matching source's own field", t.gender == 0)
	_chk("Robin: pic_stem is lass_frlg (Rule B, upstream verbatim)",
			t.pic_stem == "lass_frlg")
	if t.party.size() == 1:
		var jiggly: TrainerPartyMon = t.party[0]
		_chk("Robin Jigglypuff: species_dex is 39", jiggly.species_dex == 39)
		_chk("Robin Jigglypuff: level is 14", jiggly.level == 14)
		_chk("Robin Jigglypuff: ivs are all 0", jiggly.ivs == [0, 0, 0, 0, 0, 0])
		# Source specifies no moves, so the real level-up fallback applies --
		# the same mechanism Declan's Gyarados exercises on the Hoenn side.
		_chk("Robin Jigglypuff: fallback moveset resolved (4 moves)",
				jiggly.move_ids.size() == 4)


func _test_spot_check_sidney() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_SIDNEY_RSE")
	if t == null:
		_chk("TRAINER_SIDNEY_RSE resolves via get_trainer_by_key", false)
		return
	_chk("Sidney: trainer_name is SIDNEY", t.trainer_name == "SIDNEY")
	_chk("Sidney: party has 5 members", t.party.size() == 5)
	_chk("Sidney: mugshot_color is Purple", t.mugshot_color == "Purple")
	_chk("Sidney: ai_flags is Basic Trainer + Force Setup First Turn (15)", t.ai_flags == 15)

	var tc: TrainerClassData = TrainerClassRegistry.get_trainer_class(t.trainer_class_id)
	_chk("Sidney: trainer class is ELITE FOUR", tc != null and tc.class_name_text == "ELITE FOUR")

	if t.party.size() == 5:
		var absol: TrainerPartyMon = t.party[4]
		_chk("Sidney Absol: species_dex is 359", absol.species_dex == 359)
		_chk("Sidney Absol: holds Sitrus Berry (item 523)", absol.held_item_id == 523)
		# [M24a] Confirmed via direct source re-read: Absol is the one
		# member of Sidney's team with IVs: 31 (not 30 like its 4
		# teammates) -- ivs therefore correctly stays at the class default
		# and is omitted from the emitted .tres entirely.
		_chk("Sidney Absol: ivs are all 31 (the one teammate that differs)", absol.ivs == [31, 31, 31, 31, 31, 31])


func _test_spot_check_declan() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_DECLAN_RSE")
	if t == null:
		_chk("TRAINER_DECLAN_RSE resolves via get_trainer_by_key", false)
		return
	_chk("Declan: trainer_name is DECLAN", t.trainer_name == "DECLAN")
	_chk("Declan: party has 1 member (Gyarados)", t.party.size() == 1)
	_chk("Declan: ai_flags is Check Bad Move (1)", t.ai_flags == 1)

	if t.party.size() == 1:
		var gyarados: TrainerPartyMon = t.party[0]
		_chk("Declan Gyarados: species_dex is 130", gyarados.species_dex == 130)
		_chk("Declan Gyarados: ivs are all 0", gyarados.ivs == [0, 0, 0, 0, 0, 0])
		# [M24a] Gyarados specifies zero explicit moves in trainers.party --
		# the real GiveBoxMonInitialMoveset fallback (last 4 level-up moves
		# by level 34) is pre-computed by gen_trainer_data.py at conversion
		# time, so move_ids must still be fully populated here.
		_chk("Declan Gyarados: fallback moveset resolved (4 moves, no explicit list in source)",
				gyarados.move_ids.size() == 4)
