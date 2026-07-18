extends Node

# M18 item-data-infrastructure sanity check — NOT a new mechanic test.
#
# Verifies gen_items.py's generated .tres files, loaded via ItemRegistry, are
# byte-for-byte faithful to the 40 items scenes/battle/m18a_test.gd already
# tests via inline ItemData.new() construction (160/160 assertions, unchanged by
# this session — see docs/decisions.md's item-data-infrastructure entry). This
# file exists because m18a_test.gd itself is explicitly NOT modified this session
# (per this session's own task scope) — it never touches ItemRegistry at all, so
# it cannot by itself prove the new registry/.tres layer is correct or that it
# behaves identically to the inline-construction path it exists alongside.
#
# Section 1: full-coverage data-integrity loop (all 40 items) — a for-loop is
# appropriate here (unlike per-item mechanic tests elsewhere in this project)
# because this validates ONE mechanical property (does the generator's output
# round-trip correctly) across a homogeneous data table, not 40 distinct
# behaviors — no per-item nuance would be lost by looping.
# Section 2: registry-loaded ItemData produces IDENTICAL DamageCalculator output
# to an inline-constructed ItemData with the same fields, for one representative
# item per family — proves the two construction paths are interchangeable inputs
# to ItemManager.move_power_modifier_uq412, which is the actual claim this
# session's migration needs to support.

# (id, name, hold_effect, hold_effect_param) — must match scripts/gen_items.py's
# ITEMS list exactly; kept as an independent transcription (not read from the
# .py file) so this test can catch a generator regression, not just echo it.
const EXPECTED := [
	[426, "Charcoal", 43, 11],
	[427, "Mystic Water", 43, 12],
	[428, "Magnet", 43, 14],
	[429, "Miracle Seed", 43, 13],
	[430, "Never-Melt Ice", 43, 16],
	[431, "Black Belt", 43, 2],
	[432, "Poison Barb", 43, 4],
	[433, "Soft Sand", 43, 5],
	[434, "Sharp Beak", 43, 3],
	[435, "Twisted Spoon", 43, 15],
	[436, "Silver Powder", 43, 7],
	[437, "Hard Stone", 43, 6],
	[438, "Spell Tag", 43, 8],
	[439, "Dragon Fang", 43, 17],
	[440, "Black Glasses", 43, 18],
	[441, "Metal Coat", 43, 9],
	[425, "Silk Scarf", 43, 1],
	[799, "Fairy Feather", 43, 19],
	[404, "Sea Incense", 43, 12],
	[406, "Odd Incense", 43, 15],
	[407, "Rock Incense", 43, 6],
	[410, "Rose Incense", 43, 13],
	[409, "Wave Incense", 43, 12],
	[250, "Flame Plate", 89, 11],
	[251, "Splash Plate", 89, 12],
	[252, "Zap Plate", 89, 14],
	[253, "Meadow Plate", 89, 13],
	[254, "Icicle Plate", 89, 16],
	[255, "Fist Plate", 89, 2],
	[256, "Toxic Plate", 89, 4],
	[257, "Earth Plate", 89, 5],
	[258, "Sky Plate", 89, 3],
	[259, "Mind Plate", 89, 15],
	[260, "Insect Plate", 89, 7],
	[261, "Stone Plate", 89, 6],
	[262, "Spooky Plate", 89, 8],
	[263, "Draco Plate", 89, 17],
	[264, "Dread Plate", 89, 18],
	[265, "Iron Plate", 89, 9],
	[266, "Pixie Plate", 89, 19],
]

# [M18-cleanup]: the 15 M12-era legacy items migrated into the pipeline this
# session. (id, name, hold_effect, hold_effect_param, pocket) -- independently
# transcribed (not read from gen_items.py), same discipline as EXPECTED above.
const EXPECTED_LEGACY := [
	[472, "Leftovers",        41,  0,  0],
	[522, "Lum Berry",         9,  0,  3],
	[442, "Choice Band",      29,  0,  0],
	[523, "Sitrus Berry",     82, 25,  3],
	[443, "Choice Specs",     50,  0,  0],
	[444, "Choice Scarf",     49,  0,  0],
	[447, "Damp Rock",        51,  0,  0],
	[448, "Heat Rock",        53,  0,  0],
	[450, "Icy Rock",         54,  0,  0],
	[449, "Smooth Rock",      56,  0,  0],
	[479, "Life Orb",         60,  0,  0],
	[549, "Chilan Berry",     80,  1,  3],
	[550, "Occa Berry",       80, 11,  3],
	[510, "Heavy-Duty Boots", 119, 0,  0],
	[513, "Utility Umbrella", 115, 0,  0],
]

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section1_registry_data_integrity()
	_test_section2_registry_vs_inline_behavioral_parity()
	_test_section3_legacy_data_integrity()
	_test_section4_legacy_behavioral_parity()

	var total := _pass + _fail
	print("item_registry_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_section1_registry_data_integrity() -> void:
	for row: Array in EXPECTED:
		var iid: int = row[0]
		var iname: String = row[1]
		var he: int = row[2]
		var param: int = row[3]
		var item: ItemData = ItemRegistry.get_item(iid)
		_chk("S1.%d %s loaded" % [iid, iname], item != null)
		if item == null:
			continue
		_chk("S1.%d %s item_id matches filename" % [iid, iname], item.item_id == iid)
		_chk("S1.%d %s item_name matches" % [iid, iname], item.item_name == iname)
		_chk("S1.%d %s hold_effect=%d" % [iid, iname, he], item.hold_effect == he)
		_chk("S1.%d %s hold_effect_param=%d" % [iid, iname, param], item.hold_effect_param == param)


func _test_section2_registry_vs_inline_behavioral_parity() -> void:
	# One representative item per family (Charcoal=TYPE_POWER, Flame Plate=PLATE) —
	# proves ItemManager.move_power_modifier_uq412 treats a registry-loaded ItemData
	# identically to the inline-constructed ItemData m18a_test.gd already verified,
	# since the function only ever reads hold_effect/hold_effect_param off whatever
	# object mon.held_item points to — it has no notion of where that object came
	# from, so this is the correctness claim this session's "migration" actually rests on.
	var attacker := _make_mon("RegAtk", TypeChart.TYPE_MYSTERY)
	var move := _make_move("FireMove", TypeChart.TYPE_FIRE, 1, 40)

	var registry_item: ItemData = ItemRegistry.get_item(426)  # Charcoal
	attacker.held_item = registry_item
	var mod_from_registry: int = ItemManager.move_power_modifier_uq412(attacker, move)

	var inline_item := ItemData.new()
	inline_item.hold_effect = ItemManager.HOLD_EFFECT_TYPE_POWER
	inline_item.hold_effect_param = TypeChart.TYPE_FIRE
	attacker.held_item = inline_item
	var mod_from_inline: int = ItemManager.move_power_modifier_uq412(attacker, move)

	_chk("S2.charcoal registry-loaded modifier=4915 (UQ_4_12(1.2))",
			mod_from_registry == 4915)
	_chk("S2.charcoal registry-loaded and inline-constructed give IDENTICAL modifier",
			mod_from_registry == mod_from_inline)

	var plate_item: ItemData = ItemRegistry.get_item(250)  # Flame Plate
	attacker.held_item = plate_item
	var plate_mod: int = ItemManager.move_power_modifier_uq412(attacker, move)
	_chk("S2.flame_plate registry-loaded modifier=4915 (UQ_4_12(1.2))",
			plate_mod == 4915)

	# Discriminator: a registry-loaded item does NOT boost a non-matching-type move.
	var water_move := _make_move("WaterMove", TypeChart.TYPE_WATER, 1, 40)
	attacker.held_item = registry_item
	var mismatch_mod: int = ItemManager.move_power_modifier_uq412(attacker, water_move)
	_chk("S2.charcoal registry-loaded does NOT boost a Water move (modifier=4096, neutral)",
			mismatch_mod == 4096)


# [M18-cleanup]: Section 3 mirrors Section 1's exact shape (a for-loop is
# appropriate for the identical reason -- one mechanical property checked
# across a homogeneous table, not per-item behavioral nuance), scoped to
# ONLY the 15 newly-migrated legacy items -- does NOT retroactively cover
# the ~99 items other M18 tiers' own dedicated test files already verify.
func _test_section3_legacy_data_integrity() -> void:
	for row: Array in EXPECTED_LEGACY:
		var iid: int = row[0]
		var iname: String = row[1]
		var he: int = row[2]
		var param: int = row[3]
		var pocket: int = row[4]
		var item: ItemData = ItemRegistry.get_item(iid)
		_chk("S3.%d %s loaded" % [iid, iname], item != null)
		if item == null:
			continue
		_chk("S3.%d %s item_id matches filename" % [iid, iname], item.item_id == iid)
		_chk("S3.%d %s item_name matches" % [iid, iname], item.item_name == iname)
		_chk("S3.%d %s hold_effect=%d" % [iid, iname, he], item.hold_effect == he)
		_chk("S3.%d %s hold_effect_param=%d" % [iid, iname, param], item.hold_effect_param == param)
		_chk("S3.%d %s pocket=%d" % [iid, iname, pocket], item.pocket == pocket)


# [M18-cleanup]: Section 4 is this migration's actual correctness claim, made
# explicit and directly tested rather than assumed from Section 3's data-
# integrity checks alone (same purpose as Section 2, one representative
# assertion per item family, using each item's own already-established
# ItemManager dispatch function directly -- pure function calls, no battle
# needed, avoiding any whole-battle-aggregation risk by construction).
func _test_section4_legacy_behavioral_parity() -> void:
	var weather_setter := _make_mon("LegacyWeatherSetter", TypeChart.TYPE_NORMAL)

	var leftovers := ItemRegistry.get_item(472)
	var leftovers_mon := _make_mon("LegacyLeftovers", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	leftovers_mon.held_item = leftovers
	leftovers_mon.current_hp = leftovers_mon.max_hp - 50
	_chk("S4.472 Leftovers heals max_hp/16",
			ItemManager.leftovers_heal(leftovers_mon) == max(1, leftovers_mon.max_hp / 16))

	var lum := ItemRegistry.get_item(522)
	var lum_mon := _make_mon("LegacyLum", TypeChart.TYPE_NORMAL)
	lum_mon.held_item = lum
	lum_mon.status = BattlePokemon.STATUS_BURN
	_chk("S4.522 Lum Berry cures any status",
			ItemManager.status_cure_berry_cures(lum_mon))

	var band := ItemRegistry.get_item(442)
	var band_mon := _make_mon("LegacyBand", TypeChart.TYPE_NORMAL)
	band_mon.held_item = band
	var physical_move := _make_move("LegacyPhysical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("S4.442 Choice Band boosts physical attack (UQ_4_12(1.5)=6144)",
			ItemManager.attack_modifier_uq412(band_mon, physical_move) == 6144)

	var sitrus := ItemRegistry.get_item(523)
	var sitrus_mon := _make_mon("LegacySitrus", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	sitrus_mon.held_item = sitrus
	sitrus_mon.current_hp = 1
	_chk("S4.523 Sitrus Berry heals max_hp*25/100",
			ItemManager.hp_threshold_berry_heal(sitrus_mon) == sitrus_mon.max_hp * 25 / 100)

	var specs := ItemRegistry.get_item(443)
	var specs_mon := _make_mon("LegacySpecs", TypeChart.TYPE_NORMAL)
	specs_mon.held_item = specs
	var special_move := _make_move("LegacySpecial", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("S4.443 Choice Specs boosts special attack (UQ_4_12(1.5)=6144)",
			ItemManager.attack_modifier_uq412(specs_mon, special_move) == 6144)

	var scarf := ItemRegistry.get_item(444)
	var scarf_mon := _make_mon("LegacyScarf", TypeChart.TYPE_NORMAL)
	scarf_mon.held_item = scarf
	_chk("S4.444 Choice Scarf boosts Speed to 150%",
			ItemManager.apply_speed_modifier(scarf_mon, 100) == 150)

	var damp := ItemRegistry.get_item(447)
	weather_setter.held_item = damp
	_chk("S4.447 Damp Rock extends Rain to 8 turns",
			ItemManager.weather_duration(weather_setter, DamageCalculator.WEATHER_RAIN) == 8)

	var heat := ItemRegistry.get_item(448)
	weather_setter.held_item = heat
	_chk("S4.448 Heat Rock extends Sun to 8 turns",
			ItemManager.weather_duration(weather_setter, DamageCalculator.WEATHER_SUN) == 8)

	var icy := ItemRegistry.get_item(450)
	weather_setter.held_item = icy
	_chk("S4.450 Icy Rock extends Hail to 8 turns",
			ItemManager.weather_duration(weather_setter, DamageCalculator.WEATHER_HAIL) == 8)

	var smooth := ItemRegistry.get_item(449)
	weather_setter.held_item = smooth
	_chk("S4.449 Smooth Rock extends Sandstorm to 8 turns",
			ItemManager.weather_duration(weather_setter, DamageCalculator.WEATHER_SANDSTORM) == 8)

	var life_orb := ItemRegistry.get_item(479)
	var life_orb_mon := _make_mon("LegacyLifeOrb", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	life_orb_mon.held_item = life_orb
	_chk("S4.479 Life Orb recoil is max_hp/10",
			ItemManager.life_orb_recoil(life_orb_mon) == life_orb_mon.max_hp / 10)

	var chilan := ItemRegistry.get_item(549)
	var chilan_mon := _make_mon("LegacyChilan", TypeChart.TYPE_NORMAL)
	chilan_mon.held_item = chilan
	var normal_move := _make_move("LegacyNormalMove", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("S4.549 Chilan Berry resists a Normal-type hit (UQ_4_12(0.5)=2048)",
			ItemManager.defender_item_modifier_uq412(chilan_mon, normal_move, 1.0) == 2048)

	var occa := ItemRegistry.get_item(550)
	var occa_mon := _make_mon("LegacyOcca", TypeChart.TYPE_NORMAL)
	occa_mon.held_item = occa
	var fire_move := _make_move("LegacyFireMove", TypeChart.TYPE_FIRE, 0, 40)
	_chk("S4.550 Occa Berry resists a super-effective Fire hit (UQ_4_12(0.5)=2048)",
			ItemManager.defender_item_modifier_uq412(occa_mon, fire_move, 2.0) == 2048)

	var boots := ItemRegistry.get_item(510)
	var boots_mon := _make_mon("LegacyBoots", TypeChart.TYPE_NORMAL)
	boots_mon.held_item = boots
	_chk("S4.510 Heavy-Duty Boots grants hazard immunity",
			ItemManager.is_hazard_immune(boots_mon))

	var umbrella := ItemRegistry.get_item(513)
	var umbrella_mon := _make_mon("LegacyUmbrella", TypeChart.TYPE_NORMAL)
	umbrella_mon.held_item = umbrella
	_chk("S4.513 Utility Umbrella blocks the weather damage modifier",
			ItemManager.blocks_weather_modifier(umbrella_mon))


# ── Helpers (mirrors item_test.gd / m18a_test.gd's established pattern) ───────

func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m

