extends Node

# [M24a] Trainer Data Pipeline smoke test — mirrors move_smoke_test.gd's own
# convention (one assertion per catalog entry, loaded through the real
# Registry rather than raw Resource.load, since TrainerRegistry/
# TrainerPicRegistry/TrainerClassRegistry are themselves thin path-convention
# wrappers this test also exercises).
#
# Covers all three .tres catalogs emitted by scripts/gen_trainer_data.py
# (trainers / trainer_classes / trainer_pics — three deliberately SEPARATE
# id spaces, see docs/m24_recon.md section 1.4) plus targeted spot-checks
# against the Step 0 sample (Brawly/Sidney/Declan) verifying specific
# field values, not just "it loads".

var _pass := 0
var _fail := 0

const TRAINER_COUNT := 854
const TRAINER_CLASS_COUNT := 117
const TRAINER_PIC_COUNT := 93


func _ready() -> void:
	_test_every_trainer_loads()
	_test_every_trainer_class_loads()
	_test_every_trainer_pic_loads()
	_test_spot_check_brawly()
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
	for id in range(TRAINER_COUNT):
		var t: TrainerData = TrainerRegistry.get_trainer(id)
		var ok := t != null and t is TrainerData and t.trainer_id == id and not t.trainer_key.is_empty() and t.party.size() > 0
		_chk("Trainer %d loads as a valid, self-consistent TrainerData" % id, ok)
		if ok:
			for mon in t.party:
				_chk("Trainer %d party member is a valid TrainerPartyMon with a resolved species" % id,
						mon is TrainerPartyMon and mon.species_dex > 0)


func _test_every_trainer_class_loads() -> void:
	for id in range(TRAINER_CLASS_COUNT):
		var tc: TrainerClassData = TrainerClassRegistry.get_trainer_class(id)
		_chk("TrainerClass %d loads as a valid, self-consistent TrainerClassData" % id,
				tc != null and tc is TrainerClassData and tc.trainer_class_id == id)


func _test_every_trainer_pic_loads() -> void:
	for id in range(TRAINER_PIC_COUNT):
		var tp: TrainerPicData = TrainerPicRegistry.get_trainer_pic(id)
		_chk("TrainerPic %d loads as a valid, self-consistent TrainerPicData" % id,
				tp != null and tp is TrainerPicData and tp.pic_id == id and not tp.pic_name.is_empty())


func _test_spot_check_brawly() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1")
	if t == null:
		_chk("TRAINER_BRAWLY_1 resolves via get_trainer_by_key", false)
		return
	_chk("Brawly: trainer_name is BRAWLY", t.trainer_name == "BRAWLY")
	_chk("Brawly: party has 3 members", t.party.size() == 3)
	_chk("Brawly: gender is Male", t.gender == 0)
	_chk("Brawly: ai_flags is Basic Trainer (7)", t.ai_flags == 7)

	var tc: TrainerClassData = TrainerClassRegistry.get_trainer_class(t.trainer_class_id)
	_chk("Brawly: trainer class is LEADER", tc != null and tc.class_name_text == "LEADER")
	_chk("Brawly: trainer class ball is Ultra", tc != null and tc.ball_name == "Ultra")

	var tp: TrainerPicData = TrainerPicRegistry.get_trainer_pic(t.trainer_pic_id)
	_chk("Brawly: pic is Leader Brawly", tp != null and tp.pic_name == "Leader Brawly")

	if t.party.size() == 3:
		var machop: TrainerPartyMon = t.party[0]
		_chk("Brawly Machop: species_dex is 66", machop.species_dex == 66)
		_chk("Brawly Machop: level is 16", machop.level == 16)
		_chk("Brawly Machop: ivs are all 12", machop.ivs == [12, 12, 12, 12, 12, 12])
		_chk("Brawly Machop: 4 moves resolved", machop.move_ids.size() == 4)

		var makuhita: TrainerPartyMon = t.party[2]
		_chk("Brawly Makuhita: holds Sitrus Berry (item 523)", makuhita.held_item_id == 523)


func _test_spot_check_sidney() -> void:
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_SIDNEY")
	if t == null:
		_chk("TRAINER_SIDNEY resolves via get_trainer_by_key", false)
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
	var t: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_DECLAN")
	if t == null:
		_chk("TRAINER_DECLAN resolves via get_trainer_by_key", false)
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
