extends Node

# M18g test suite — Species-gated stat/crit items + Soul Dew
#
# Ground truth: pokeemerald-expansion, src/battle_util.c's CalcAttackStat
# (L6977-6989), CalcDefenseStat (L7160-7189), CalcMoveBasePowerAfterModifiers
# (L6653-6658), GetHoldEffectCritChanceIncrease (L7804-7810), and
# battle_main.c's speed pipeline (L4705).
#
# MAJOR CORRECTION found at Step 0: [M17n-4] (cited by the task as the
# species-gate precedent) establishes NO species-gate mechanism at all —
# Multitype's own held-item read is a Plate-TYPE check, not a species check.
# This tier builds the species-gate mechanism (ItemData.required_species/
# required_species2, ItemManager._species_matches) fresh, with no prior
# precedent to extend.
#
# Other corrections found and tested explicitly below:
#   - Metal Powder (Defense) and Quick Powder (Speed) are NOT the same stat,
#     despite the "Ditto powder pair" resemblance (G05/G06).
#   - Lucky Punch is Chansey-ONLY — does NOT extend to Blissey (G04.04).
#   - Lucky Punch/Leek are +2 crit stage, NOT +1 like Scope Lens/Razor Claw
#     from [M18e], despite sharing the exact same source function (G02/G04).
#   - Deep Sea Scale/Tooth/Metal Powder live in the raw-stat-before-formula
#     pipeline stage (CalcAttackStat/CalcDefenseStat), confirmed DISTINCT from
#     AbilityManager.defense_damage_modifier_uq412's post-effectiveness stage
#     (a similarly named but different function) — no test needed to prove
#     this beyond correct wiring, since the two functions are independent.
#   - Soul Dew is TYPE-BOOST ONLY under this project's B_SOUL_DEW_BOOST=
#     GEN_LATEST (>=GEN_7) config — no SpDef stat component (G09).
#
# Sections: G01 Light Ball, G02 Leek, G03 Thick Club, G04 Lucky Punch,
# G05 Metal Powder, G06 Quick Powder, G07 Deep Sea Scale, G08 Deep Sea Tooth,
# G09 Soul Dew.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_g01_light_ball()
	_test_g02_leek()
	_test_g03_thick_club()
	_test_g04_lucky_punch()
	_test_g05_metal_powder()
	_test_g06_quick_powder()
	_test_g07_deep_sea_scale()
	_test_g08_deep_sea_tooth()
	_test_g09_soul_dew()

	var total := _pass + _fail
	print("m18g_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18d_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, required_species: int = 0, required_species2: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.required_species = required_species
	item.required_species2 = required_species2
	return item


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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


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


# ── G01: Light Ball (392) — Pikachu, x2.0 BOTH Atk and SpAtk, no category gate ──
func _test_g01_light_ball() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_LIGHT_BALL, ItemManager.SPECIES_PIKACHU)
	_chk("G01.01 Light Ball hold_effect=LIGHT_BALL, required_species=Pikachu(25)",
			item.hold_effect == ItemManager.HOLD_EFFECT_LIGHT_BALL \
					and item.required_species == ItemManager.SPECIES_PIKACHU)

	var pikachu := _make_mon("G01_Pikachu", TypeChart.TYPE_ELECTRIC)
	pikachu.species.national_dex_num = ItemManager.SPECIES_PIKACHU
	pikachu.held_item = item
	var physical := _make_move("G01_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	var special := _make_move("G01_Special", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("G01.02 CORRECTION-confirming: Light Ball boosts a PHYSICAL move x2.0 " +
			"(no category gate, unlike Thick Club/Deep Sea Tooth)",
			ItemManager.attack_modifier_uq412(pikachu, physical) == ItemManager.UQ412_DOUBLE)
	_chk("G01.03 Light Ball ALSO boosts a SPECIAL move x2.0 — BOTH stats, confirmed",
			ItemManager.attack_modifier_uq412(pikachu, special) == ItemManager.UQ412_DOUBLE)

	var raichu := _make_mon("G01_Raichu", TypeChart.TYPE_ELECTRIC)
	raichu.species.national_dex_num = 26  # Raichu — thematically related, wrong species
	raichu.held_item = item
	_chk("G01.04 discriminator: Raichu (thematically related) gets NO boost",
			ItemManager.attack_modifier_uq412(raichu, physical) == 4096)


# ── G02: Leek (393) — Farfetch'd, +2 crit stage ─────────────────────────────────
func _test_g02_leek() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_LEEK, ItemManager.SPECIES_FARFETCHD)
	_chk("G02.01 Leek hold_effect=LEEK, required_species=Farfetch'd(83)",
			item.hold_effect == ItemManager.HOLD_EFFECT_LEEK \
					and item.required_species == ItemManager.SPECIES_FARFETCHD)

	var farfetchd := _make_mon("G02_Farfetchd", TypeChart.TYPE_NORMAL, TypeChart.TYPE_FLYING)
	farfetchd.species.national_dex_num = ItemManager.SPECIES_FARFETCHD
	farfetchd.held_item = item
	_chk("G02.02 CORRECTION-confirming: Leek grants +2 crit stage, NOT +1 like " +
			"Scope Lens/Razor Claw ([M18e]) despite the same source function",
			ItemManager.crit_stage_bonus(farfetchd) == 2)

	var bare := _make_mon("G02_Bare", TypeChart.TYPE_NORMAL, TypeChart.TYPE_FLYING)
	bare.species.national_dex_num = ItemManager.SPECIES_FARFETCHD
	_chk("G02.03 discriminator: holding nothing gets no bonus",
			ItemManager.crit_stage_bonus(bare) == 0)

	var wrong_species := _make_mon("G02_Wrong", TypeChart.TYPE_NORMAL, TypeChart.TYPE_FLYING)
	wrong_species.species.national_dex_num = 84  # Doduo — thematically related (Flying), wrong species
	wrong_species.held_item = item
	_chk("G02.04 discriminator: Doduo (thematically related) gets NO bonus",
			ItemManager.crit_stage_bonus(wrong_species) == 0)


# ── G03: Thick Club (394) — Cubone OR Marowak, x2.0 Atk, physical-only ─────────
func _test_g03_thick_club() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_THICK_CLUB,
			ItemManager.SPECIES_CUBONE, ItemManager.SPECIES_MAROWAK)
	_chk("G03.01 Thick Club hold_effect=THICK_CLUB, required_species=Cubone(104)/Marowak(105)",
			item.hold_effect == ItemManager.HOLD_EFFECT_THICK_CLUB \
					and item.required_species == ItemManager.SPECIES_CUBONE \
					and item.required_species2 == ItemManager.SPECIES_MAROWAK)

	var physical := _make_move("G03_Physical", TypeChart.TYPE_GROUND, 0, 40)
	var special := _make_move("G03_Special", TypeChart.TYPE_GROUND, 1, 40)

	var cubone := _make_mon("G03_Cubone", TypeChart.TYPE_GROUND)
	cubone.species.national_dex_num = ItemManager.SPECIES_CUBONE
	cubone.held_item = item
	_chk("G03.02 Cubone (first of the matched pair) gets x2.0 on a PHYSICAL move",
			ItemManager.attack_modifier_uq412(cubone, physical) == ItemManager.UQ412_DOUBLE)

	var marowak := _make_mon("G03_Marowak", TypeChart.TYPE_GROUND)
	marowak.species.national_dex_num = ItemManager.SPECIES_MAROWAK
	marowak.held_item = item
	_chk("G03.03 Marowak (second of the matched pair) ALSO gets x2.0 — both " +
			"species independently confirmed",
			ItemManager.attack_modifier_uq412(marowak, physical) == ItemManager.UQ412_DOUBLE)

	_chk("G03.04 discriminator: does NOT boost a SPECIAL move (physical-only)",
			ItemManager.attack_modifier_uq412(cubone, special) == 4096)

	var wrong_species := _make_mon("G03_Sandshrew", TypeChart.TYPE_GROUND)
	wrong_species.species.national_dex_num = 27  # Sandshrew — Ground-type, wrong species
	wrong_species.held_item = item
	_chk("G03.05 discriminator: a random other Ground-type does NOT get the boost",
			ItemManager.attack_modifier_uq412(wrong_species, physical) == 4096)


# ── G04: Lucky Punch (395) — Chansey ONLY, +2 crit stage ────────────────────────
func _test_g04_lucky_punch() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_LUCKY_PUNCH, ItemManager.SPECIES_CHANSEY)
	_chk("G04.01 Lucky Punch hold_effect=LUCKY_PUNCH, required_species=Chansey(113)",
			item.hold_effect == ItemManager.HOLD_EFFECT_LUCKY_PUNCH \
					and item.required_species == ItemManager.SPECIES_CHANSEY)

	var chansey := _make_mon("G04_Chansey", TypeChart.TYPE_NORMAL)
	chansey.species.national_dex_num = ItemManager.SPECIES_CHANSEY
	chansey.held_item = item
	_chk("G04.02 Chansey gets +2 crit stage",
			ItemManager.crit_stage_bonus(chansey) == 2)

	var blissey := _make_mon("G04_Blissey", TypeChart.TYPE_NORMAL)
	blissey.species.national_dex_num = 242  # Blissey — Chansey's own evolution
	blissey.held_item = item
	_chk("G04.03 CORRECTION-confirming: Blissey (Chansey's own evolution) gets " +
			"NO bonus — Lucky Punch is Chansey-ONLY, confirmed via source, not " +
			"assumed to extend to the evolved form",
			ItemManager.crit_stage_bonus(blissey) == 0)


# ── G05: Metal Powder (396) — Ditto, x2.0 DEFENSE (not SpDef), physical-only ────
func _test_g05_metal_powder() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_METAL_POWDER, ItemManager.SPECIES_DITTO)
	_chk("G05.01 Metal Powder hold_effect=METAL_POWDER, required_species=Ditto(132)",
			item.hold_effect == ItemManager.HOLD_EFFECT_METAL_POWDER \
					and item.required_species == ItemManager.SPECIES_DITTO)

	var ditto := _make_mon("G05_Ditto", TypeChart.TYPE_NORMAL)
	ditto.species.national_dex_num = ItemManager.SPECIES_DITTO
	ditto.held_item = item
	var incoming_physical := _make_move("G05_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	var incoming_special := _make_move("G05_Special", TypeChart.TYPE_NORMAL, 1, 40)
	_chk("G05.02 Metal Powder boosts DEFENSE x2.0 against a PHYSICAL move",
			ItemManager.defense_stat_modifier_uq412(ditto, incoming_physical) == ItemManager.UQ412_DOUBLE)
	_chk("G05.03 discriminator: does NOT boost against a SPECIAL move (physical-only)",
			ItemManager.defense_stat_modifier_uq412(ditto, incoming_special) == 4096)
	_chk("G05.04 CORRECTION-confirming: Metal Powder does NOT affect apply_speed_modifier " +
			"(Quick Powder's own pipeline) — confirms the two are NOT the same stat",
			ItemManager.apply_speed_modifier(ditto, 100) == 100)

	var wrong_species := _make_mon("G05_Wrong", TypeChart.TYPE_NORMAL)
	wrong_species.species.national_dex_num = 133  # Eevee — wrong species
	wrong_species.held_item = item
	_chk("G05.05 discriminator: a different species gets no Defense boost",
			ItemManager.defense_stat_modifier_uq412(wrong_species, incoming_physical) == 4096)


# ── G06: Quick Powder (397) — Ditto, x2.0 SPEED (not Defense) ──────────────────
func _test_g06_quick_powder() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_QUICK_POWDER, ItemManager.SPECIES_DITTO)
	_chk("G06.01 Quick Powder hold_effect=QUICK_POWDER, required_species=Ditto(132)",
			item.hold_effect == ItemManager.HOLD_EFFECT_QUICK_POWDER \
					and item.required_species == ItemManager.SPECIES_DITTO)

	var ditto := _make_mon("G06_Ditto", TypeChart.TYPE_NORMAL)
	ditto.species.national_dex_num = ItemManager.SPECIES_DITTO
	ditto.held_item = item
	_chk("G06.02 Quick Powder doubles SPEED (100 -> 200)",
			ItemManager.apply_speed_modifier(ditto, 100) == 200)

	var incoming_physical := _make_move("G06_Physical", TypeChart.TYPE_NORMAL, 0, 40)
	_chk("G06.03 CORRECTION-confirming: Quick Powder does NOT affect " +
			"defense_stat_modifier_uq412 (Metal Powder's own pipeline) — a genuine " +
			"correction, these are NOT a same-stat matched pair despite the " +
			"'Ditto powder' family resemblance",
			ItemManager.defense_stat_modifier_uq412(ditto, incoming_physical) == 4096)

	var wrong_species := _make_mon("G06_Wrong", TypeChart.TYPE_NORMAL)
	wrong_species.species.national_dex_num = 133  # Eevee — wrong species
	wrong_species.held_item = item
	_chk("G06.04 discriminator: a different species gets no Speed boost",
			ItemManager.apply_speed_modifier(wrong_species, 100) == 100)


# ── G07: Deep Sea Scale (398) — Clamperl, x2.0 SpDef, special-only ─────────────
func _test_g07_deep_sea_scale() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_DEEP_SEA_SCALE, ItemManager.SPECIES_CLAMPERL)
	_chk("G07.01 Deep Sea Scale hold_effect=DEEP_SEA_SCALE, required_species=Clamperl(366)",
			item.hold_effect == ItemManager.HOLD_EFFECT_DEEP_SEA_SCALE \
					and item.required_species == ItemManager.SPECIES_CLAMPERL)

	var clamperl := _make_mon("G07_Clamperl", TypeChart.TYPE_WATER)
	clamperl.species.national_dex_num = ItemManager.SPECIES_CLAMPERL
	clamperl.held_item = item
	var incoming_special := _make_move("G07_Special", TypeChart.TYPE_WATER, 1, 40)
	var incoming_physical := _make_move("G07_Physical", TypeChart.TYPE_WATER, 0, 40)
	_chk("G07.02 Deep Sea Scale boosts Sp.Defense x2.0 against a SPECIAL move",
			ItemManager.defense_stat_modifier_uq412(clamperl, incoming_special) == ItemManager.UQ412_DOUBLE)
	_chk("G07.03 discriminator: does NOT boost against a PHYSICAL move (special-only)",
			ItemManager.defense_stat_modifier_uq412(clamperl, incoming_physical) == 4096)

	var wrong_species := _make_mon("G07_Wrong", TypeChart.TYPE_WATER)
	wrong_species.species.national_dex_num = 90  # Shellder — Water-type, wrong species
	wrong_species.held_item = item
	_chk("G07.04 discriminator: a random other Water-type does NOT get the boost",
			ItemManager.defense_stat_modifier_uq412(wrong_species, incoming_special) == 4096)


# ── G08: Deep Sea Tooth (399) — Clamperl, x2.0 SpAtk, special-only ─────────────
func _test_g08_deep_sea_tooth() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_DEEP_SEA_TOOTH, ItemManager.SPECIES_CLAMPERL)
	_chk("G08.01 Deep Sea Tooth hold_effect=DEEP_SEA_TOOTH, required_species=Clamperl(366)",
			item.hold_effect == ItemManager.HOLD_EFFECT_DEEP_SEA_TOOTH \
					and item.required_species == ItemManager.SPECIES_CLAMPERL)

	var clamperl := _make_mon("G08_Clamperl", TypeChart.TYPE_WATER)
	clamperl.species.national_dex_num = ItemManager.SPECIES_CLAMPERL
	clamperl.held_item = item
	var special := _make_move("G08_Special", TypeChart.TYPE_WATER, 1, 40)
	var physical := _make_move("G08_Physical", TypeChart.TYPE_WATER, 0, 40)
	_chk("G08.02 Deep Sea Tooth boosts Sp.Attack x2.0 on a SPECIAL move",
			ItemManager.attack_modifier_uq412(clamperl, special) == ItemManager.UQ412_DOUBLE)
	_chk("G08.03 discriminator: does NOT boost a PHYSICAL move (special-only) — " +
			"confirmed asymmetric magnitude/gate pairing with Deep Sea Scale's " +
			"own defensive-side special-only gate (same category, different stat)",
			ItemManager.attack_modifier_uq412(clamperl, physical) == 4096)

	var wrong_species := _make_mon("G08_Wrong", TypeChart.TYPE_WATER)
	wrong_species.species.national_dex_num = 90  # Shellder — wrong species
	wrong_species.held_item = item
	_chk("G08.04 discriminator: a different species does NOT get the boost",
			ItemManager.attack_modifier_uq412(wrong_species, special) == 4096)


# ── G09: Soul Dew (400) — Latios OR Latias, TYPE-BOOST ONLY (Psychic/Dragon) ────
func _test_g09_soul_dew() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SOUL_DEW,
			ItemManager.SPECIES_LATIAS, ItemManager.SPECIES_LATIOS)
	_chk("G09.01 Soul Dew hold_effect=SOUL_DEW, required_species=Latias(380)/Latios(381)",
			item.hold_effect == ItemManager.HOLD_EFFECT_SOUL_DEW \
					and item.required_species == ItemManager.SPECIES_LATIAS \
					and item.required_species2 == ItemManager.SPECIES_LATIOS)

	var psychic_move := _make_move("G09_Psychic", TypeChart.TYPE_PSYCHIC, 1, 40)
	var dragon_move := _make_move("G09_Dragon", TypeChart.TYPE_DRAGON, 1, 40)
	var normal_move := _make_move("G09_Normal", TypeChart.TYPE_NORMAL, 1, 40)

	var latias := _make_mon("G09_Latias", TypeChart.TYPE_DRAGON, TypeChart.TYPE_PSYCHIC)
	latias.species.national_dex_num = ItemManager.SPECIES_LATIAS
	latias.held_item = item
	_chk("G09.02 Latias: Soul Dew boosts a PSYCHIC move",
			ItemManager.move_power_modifier_uq412(latias, psychic_move) == ItemManager.UQ412_TYPE_BOOST)
	_chk("G09.03 Latias: Soul Dew ALSO boosts a DRAGON move (both types, one item)",
			ItemManager.move_power_modifier_uq412(latias, dragon_move) == ItemManager.UQ412_TYPE_BOOST)
	_chk("G09.04 discriminator: does NOT boost a NORMAL move (off-type)",
			ItemManager.move_power_modifier_uq412(latias, normal_move) == 4096)

	var latios := _make_mon("G09_Latios", TypeChart.TYPE_DRAGON, TypeChart.TYPE_PSYCHIC)
	latios.species.national_dex_num = ItemManager.SPECIES_LATIOS
	latios.held_item = item
	_chk("G09.05 Latios (second of the matched pair) ALSO gets the boost",
			ItemManager.move_power_modifier_uq412(latios, psychic_move) == ItemManager.UQ412_TYPE_BOOST)

	var wrong_species := _make_mon("G09_Wrong", TypeChart.TYPE_PSYCHIC)
	wrong_species.species.national_dex_num = 150  # Mewtwo — Psychic-type, wrong species
	wrong_species.held_item = item
	_chk("G09.06 discriminator: a non-Latios/Latias Psychic-type (Mewtwo) gets NO boost",
			ItemManager.move_power_modifier_uq412(wrong_species, psychic_move) == 4096)

	_chk("G09.07 CORRECTION-confirming: Soul Dew grants NO defensive stat component " +
			"under this project's B_SOUL_DEW_BOOST=GEN_LATEST (>=GEN_7) config — " +
			"only the type-boost above; confirmed by checking defense_stat_modifier_uq412 " +
			"never dispatches HOLD_EFFECT_SOUL_DEW at all (no case for it there)",
			ItemManager.defense_stat_modifier_uq412(latias, psychic_move) == 4096)
