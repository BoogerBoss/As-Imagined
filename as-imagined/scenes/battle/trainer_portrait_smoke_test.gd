extends Node

# [M23.11 Phase 3] Trainer portrait smoke test — mirrors
# trainer_data_smoke_test.gd's own convention (one assertion per catalog
# entry, loaded through the real registry method rather than raw
# Resource.load) and battle_ui_sprite_smoke_test.gd's Phase 1 precedent
# (a dedicated load-integrity check for a freshly-pulled asset set).
#
# Loops every distinct portrait stem the roster references (Rule B:
# all 93 currently populated by M24a) and asserts
# get_portrait_texture(pic_id) returns a non-null Texture2D of the expected
# uniform 64x64 size — confirming both the asset pull itself (scripts/
# gen_trainer_portraits.py) and the registry's own lazy directory-scan
# lookup work end-to-end, not just that files exist on disk.

var _pass := 0
var _fail := 0

# [Step 4] Both rosters reference 155 distinct stems (93 Hoenn + 62 Kanto,
# zero overlap -- every Kanto stem is _frlg-suffixed upstream).
const PORTRAIT_STEM_COUNT := 155


func _ready() -> void:
	_test_every_portrait_loads()
	_test_dangling_stem_count()
	_test_spot_check_known_portraits()
	_test_upstream_verbatim_edge_cases()
	_test_missing_stem_fails_loudly()

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
	# [Step 2 / Rule B] Driven by the roster itself: every distinct stem any
	# trainer actually references must resolve. Iterating trainers rather than
	# an id range means a stem nobody uses cannot pad the count, and a trainer
	# whose art is missing cannot hide.
	var stems := {}
	for key in TrainerRegistry.all_keys():
		var t := TrainerRegistry.get_trainer_by_key(key)
		if t != null and t.pic_stem != "":
			stems[t.pic_stem] = true
	_chk("roster references %d distinct portrait stems (got %d)"
			% [PORTRAIT_STEM_COUNT, stems.size()], stems.size() == PORTRAIT_STEM_COUNT)
	# Only stems whose art is actually pulled are load-checked; the not-yet-
	# pulled Kanto ones are counted by _test_dangling_stem_count instead, so a
	# known gap does not masquerade as 62 individual failures.
	for stem in stems:
		if not TrainerPicRegistry.has_portrait(stem):
			continue
		var tex: Texture2D = TrainerPicRegistry.get_portrait_texture(stem)
		_chk("portrait '%s' loads as a valid 64x64 Texture2D" % stem,
				tex != null and tex is Texture2D
				and tex.get_width() == 64 and tex.get_height() == 64)


## [Step 2] The dangling-stem counter: how many trainers name art that is not
## on disk. Zero now. Converting the Kanto roster raises it to 86 (the unpulled
## FRLG sprites, [M26B3-1]); pulling them returns it to 0. A number that moves
## is the point — the gap stays visible instead of becoming a silent blank.
## [Step 4] Two numbers, because they answer different questions and the
## distinction was easy to get wrong:
##
##   EXPECTED_DANGLING_STEMS  -- distinct art files still to pull (the work)
##   EXPECTED_DANGLING_TRAINERS -- trainers currently without a portrait (the blast radius)
##
## 62, not 86: the reference ships 86 _frlg front pics, but only 62 are
## referenced by any converted trainer. The other 24 have no consumer in either
## roster -- so pulling 62 satisfies the whole roster, and [M26B3-1]'s "86
## sprites" is the size of the available art, not the size of the gap.
##
## Both return to 0 when the Kanto sprites are pulled. Numbers that move, by
## design -- the gap stays visible rather than becoming a silent blank.
const EXPECTED_DANGLING_STEMS := 62
const EXPECTED_DANGLING_TRAINERS := 623

func _test_dangling_stem_count() -> void:
	var dangling_trainers := 0
	var dangling_stems := {}
	var examples := []
	for key in TrainerRegistry.all_keys():
		var t := TrainerRegistry.get_trainer_by_key(key)
		if t == null or t.pic_stem == "":
			continue
		if not TrainerPicRegistry.has_portrait(t.pic_stem):
			dangling_trainers += 1
			dangling_stems[t.pic_stem] = true
			if examples.size() < 3:
				examples.append("%s -> %s" % [key, t.pic_stem])
	_chk("distinct dangling portrait stems == %d (got %d)%s"
			% [EXPECTED_DANGLING_STEMS, dangling_stems.size(),
					"" if examples.is_empty() else " e.g. " + str(examples)],
			dangling_stems.size() == EXPECTED_DANGLING_STEMS)
	_chk("trainers without a portrait == %d (got %d)"
			% [EXPECTED_DANGLING_TRAINERS, dangling_trainers],
			dangling_trainers == EXPECTED_DANGLING_TRAINERS)
	# Every dangling stem must be a Kanto one -- a Hoenn portrait going missing
	# would be a real regression hiding inside an expected-looking count.
	var non_frlg := 0
	for stem in dangling_stems:
		if not str(stem).ends_with("_frlg"):
			non_frlg += 1
	_chk("every dangling stem is an unpulled Kanto sprite, not a lost Hoenn one",
			non_frlg == 0)


func _test_spot_check_known_portraits() -> void:
	# The same three Step 0 trainers M24a's own spot-checks used, now asserting
	# the real upstream stem rather than an index into a retired table.
	var brawly: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1_RSE")
	var sidney: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_SIDNEY_RSE")
	var declan: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_DECLAN_RSE")
	var roxanne: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_ROXANNE_1_RSE")

	if brawly != null:
		_chk("Brawly's pic_stem is leader_brawly", brawly.pic_stem == "leader_brawly")
		_chk("Brawly's portrait resolves",
				TrainerPicRegistry.has_portrait(brawly.pic_stem))
	if sidney != null:
		_chk("Sidney's pic_stem is elite_four_sidney", sidney.pic_stem == "elite_four_sidney")
		_chk("Sidney's portrait resolves",
				TrainerPicRegistry.has_portrait(sidney.pic_stem))
	if declan != null:
		_chk("Declan's pic_stem is swimmer_m (shared by many trainers)",
				declan.pic_stem == "swimmer_m")
	if roxanne != null:
		_chk("Roxanne's pic_stem is leader_roxanne", roxanne.pic_stem == "leader_roxanne")


## [Rule B] The two stems a naive slug of the `Pic:` string gets WRONG. Source
## calls these files brendan_rs/may_rs while the roster's Pic: values are
## "RS Brendan"/"RS May", so `lower().replace(" ","_")` yields rs_brendan --
## not a real file. Pinned so nobody "tidies" the resolver into re-slugifying.
func _test_upstream_verbatim_edge_cases() -> void:
	for stem in ["brendan_rs", "may_rs"]:
		_chk("upstream-verbatim stem '%s' exists on disk" % stem,
				TrainerPicRegistry.has_portrait(stem))
	for wrong in ["rs_brendan", "rs_may"]:
		_chk("the naive re-slugified form '%s' does NOT exist" % wrong,
				not TrainerPicRegistry.has_portrait(wrong))


## [Step 2] A missing stem must fail LOUDLY: a visible placeholder, never a
## silent null that renders as an empty slot.
func _test_missing_stem_fails_loudly() -> void:
	var tex := TrainerPicRegistry.get_portrait_texture(
			"definitely_not_a_real_stem", "TRAINER_TEST")
	_chk("a missing stem returns a placeholder, not null", tex != null)
	_chk("the placeholder is a real 64x64 texture",
			tex != null and tex.get_width() == 64 and tex.get_height() == 64)
	var empty := TrainerPicRegistry.get_portrait_texture("", "TRAINER_TEST")
	_chk("an empty stem also returns the placeholder, not null", empty != null)
	_chk("both unresolvable cases share one placeholder instance", tex == empty)
	_chk("has_portrait() reports the miss as false",
			not TrainerPicRegistry.has_portrait("definitely_not_a_real_stem"))
