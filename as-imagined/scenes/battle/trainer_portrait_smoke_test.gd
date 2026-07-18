extends Node

# [M23.11 Phase 3] Trainer portrait smoke test — mirrors
# trainer_data_smoke_test.gd's own convention (one assertion per catalog
# entry, loaded through the real registry method rather than raw
# Resource.load) and battle_ui_sprite_smoke_test.gd's Phase 1 precedent
# (a dedicated load-integrity check for a freshly-pulled asset set).
#
# Loops every pic_id TrainerPicRegistry.get_trainer_pic() resolves (0-92,
# all 93 currently populated by M24a) and asserts
# get_portrait_texture(pic_id) returns a non-null Texture2D of the expected
# uniform 64x64 size — confirming both the asset pull itself (scripts/
# gen_trainer_portraits.py) and the registry's own lazy directory-scan
# lookup work end-to-end, not just that files exist on disk.

var _pass := 0
var _fail := 0

const TRAINER_PIC_COUNT := 93


func _ready() -> void:
	_test_every_portrait_loads()
	_test_spot_check_known_portraits()

	var total := _pass + _fail
	print("trainer_portrait_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_every_portrait_loads() -> void:
	for id in range(TRAINER_PIC_COUNT):
		var tex: Texture2D = TrainerPicRegistry.get_portrait_texture(id)
		_chk("Portrait %d loads as a valid 64x64 Texture2D" % id,
				tex != null and tex is Texture2D and tex.get_width() == 64 and tex.get_height() == 64)


func _test_spot_check_known_portraits() -> void:
	# Cross-references the exact same three Step 0 trainers M24a's own
	# spot-checks used, confirming the portrait pipeline resolves the
	# correct art for each, not just "some" 64x64 image.
	var brawly: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1")
	var sidney: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_SIDNEY")
	var declan: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_DECLAN")

	if brawly != null:
		var pic: TrainerPicData = TrainerPicRegistry.get_trainer_pic(brawly.trainer_pic_id)
		_chk("Brawly's pic_name is Leader Brawly", pic != null and pic.pic_name == "Leader Brawly")
		_chk("Brawly's portrait texture resolves", TrainerPicRegistry.get_portrait_texture(brawly.trainer_pic_id) != null)

	if sidney != null:
		var pic: TrainerPicData = TrainerPicRegistry.get_trainer_pic(sidney.trainer_pic_id)
		_chk("Sidney's pic_name is Elite Four Sidney", pic != null and pic.pic_name == "Elite Four Sidney")
		_chk("Sidney's portrait texture resolves", TrainerPicRegistry.get_portrait_texture(sidney.trainer_pic_id) != null)

	if declan != null:
		var pic: TrainerPicData = TrainerPicRegistry.get_trainer_pic(declan.trainer_pic_id)
		_chk("Declan's pic_name is Swimmer M", pic != null and pic.pic_name == "Swimmer M")
		_chk("Declan's portrait texture resolves", TrainerPicRegistry.get_portrait_texture(declan.trainer_pic_id) != null)

	# Negative control: an out-of-range id must resolve to null, not crash
	# or silently return a wrong texture (matching MoveRegistry/ItemRegistry's
	# own "return null for unresolvable" convention).
	_chk("Out-of-range pic_id (999) resolves to null, not a crash",
			TrainerPicRegistry.get_portrait_texture(999) == null)
