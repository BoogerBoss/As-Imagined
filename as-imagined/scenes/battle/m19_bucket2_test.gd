extends Node

# [M19-bucket2] Bulk move implementation, Bucket 2 (reuses a single existing
# secondary mechanism), per docs/m19_subtier_plan.md's mechanism-based
# re-bucketing (`[M19-rescope]`).
#
# Of the 246 moves the plan classified into Bucket 2, individual Step 0
# verification found THREE further classification gaps beyond the plan's own
# declared numbers (matching [M19-bucket1]'s precedent of not trusting a
# bucket label blindly):
#   1. 15 moves needing a genuinely new mechanism the plan's own
#      primary-effect clustering didn't check for (crash-on-miss,
#      percent-of-current-HP damage, charge-turn Sp.Atk boost, weather-
#      conditional accuracy, stat-raised-this-turn trigger).
#   2. 15 more moves are actually multi-stat-in-one-block (Calm Mind,
#      Ancient Power, etc.) — found via a widened multi-stat scanner after
#      discovering the original one only checked STAT_CHANGE_EFFECT_* blocks,
#      missing the identical shape inside MOVE_EFFECT_STAT_PLUS/MINUS blocks
#      (Superpower, Close Combat) due to a field-naming gap (spAtk/spDef
#      short forms) — the same class of bug this project has hit twice
#      before.
#   3. The single biggest gap: ALL 79 EFFECT_HIT + STAT_PLUS/STAT_MINUS-token
#      moves (Bug Buzz, Focus Blast, Iron Tail, Shadow Ball, Crunch, Moonblast,
#      etc.) — confirmed via this project's OWN existing comment
#      (item_manager.gd:768): "this project's stat_change_stat schema has NO
#      probability field at all, so no damaging move can carry a
#      probabilistic stat-lowering secondary effect here." Verified directly:
#      stat_change_stat is only ever read inside the pure-status-move branch
#      of battle_manager.gd, never inside EFFECT_HIT's own damage-execution
#      path. This is the highest-leverage gap found in this entire M19
#      effort — a single new mechanism (extend EFFECT_HIT dispatch to roll
#      and apply stat_change_stat, mirroring try_secondary_effect's existing
#      chance-roll shape) would unlock 79 moves at once.
#   4. Two more found via a `.target` field sweep: Howl (TARGET_USER_AND_ALLY
#      at GEN8+) and Aromatic Mist (TARGET_ALLY) — neither self-vs-opponent
#      shape `stat_change_self` supports; this project has no ally-targeting
#      stat-change mechanism at all.
#
# **135 moves confirmed genuinely single-mechanism reuse** and implemented
# here, organized into 8 mechanism groups matching the plan's own
# sub-clustering (minus the exclusions above):
#   EFFECT_HIT+single-SE-token (72), EFFECT_STAT_CHANGE pure (30),
#   EFFECT_NON_VOLATILE_STATUS (9), EFFECT_RECOIL (9), EFFECT_ABSORB (8),
#   EFFECT_CONFUSE (3), EFFECT_SEMI_INVULNERABLE (2, Dive/Bounce),
#   EFFECT_TWO_TURNS_ATTACK (2, Freeze Shock/Ice Burn — the OTHER two of
#   this primary effect's 4 members needed a charge-turn stat boost this
#   project's charge_turn_defense_boost field can't represent, since it's
#   hardcoded to Defense only).
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h. All
# power/accuracy/pp/type/priority/chance values reflect GEN_LATEST config
# (every ternary resolved to its highest-gen branch).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_effect_hit()
	_test_effect_stat_change()
	_test_effect_non_volatile_status()
	_test_effect_recoil()
	_test_effect_absorb()
	_test_effect_confuse()
	_test_effect_semi_invulnerable()
	_test_effect_two_turns_attack()
	_test_functional()

	var total := _pass + _fail
	print("m19_bucket2_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, type1: int,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _chk_flag_tokens(tag: String, mv: MoveData, tokens: Array) -> void:
	var seen := {}
	for token: String in tokens:
		if token == "contact":
			seen["contact"] = true
			_chk(tag + " makes_contact", mv.makes_contact)
		elif token == "punching":
			seen["punching"] = true
			_chk(tag + " punching_move", mv.punching_move)
		elif token == "biting":
			seen["biting"] = true
			_chk(tag + " biting_move", mv.biting_move)
		elif token == "sound":
			seen["sound"] = true
			_chk(tag + " sound_move", mv.sound_move)
		elif token == "slicing":
			seen["slicing"] = true
			_chk(tag + " slicing_move", mv.slicing_move)
		elif token == "ballistic":
			seen["ballistic"] = true
			_chk(tag + " ballistic_move", mv.ballistic_move)
		elif token == "powder":
			seen["powder"] = true
			_chk(tag + " powder_move", mv.powder_move)
		elif token == "pulse":
			seen["pulse"] = true
			_chk(tag + " pulse_move", mv.pulse_move)
		elif token == "always_crit":
			seen["always_crit"] = true
			_chk(tag + " always_critical_hit", mv.always_critical_hit)
		elif token == "thaws":
			seen["thaws"] = true
			_chk(tag + " thaws_user", mv.thaws_user)
		elif token == "double_min":
			seen["double_min"] = true
			_chk(tag + " double_power_on_minimized", mv.double_power_on_minimized)
		elif token == "ignores_protect":
			seen["ignores_protect"] = true
			_chk(tag + " ignores_protect", mv.ignores_protect)
		elif token == "ignores_sub":
			seen["ignores_sub"] = true
			_chk(tag + " ignores_substitute", mv.ignores_substitute)
		elif token == "bounceable":
			seen["bounceable"] = true
			_chk(tag + " bounceable", mv.bounceable)
		elif token == "healing_move":
			seen["healing_move"] = true
			_chk(tag + " healing_move", mv.healing_move)
		elif token == "spread":
			seen["spread"] = true
			_chk(tag + " is_spread", mv.is_spread)
		elif token == "airborne":
			seen["airborne"] = true
			_chk(tag + " damages_airborne", mv.damages_airborne)
		elif token.begins_with("crit:"):
			seen["crit"] = true
			var n: int = int(token.split(":")[1])
			_chk(tag + " critical_hit_stage=%d" % n, mv.critical_hit_stage == n)
		elif token.begins_with("prio:"):
			seen["prio"] = true
			var n: int = int(token.split(":")[1])
			_chk(tag + " priority=%d" % n, mv.priority == n)
	if not seen.has("contact"): _chk(tag + " NOT makes_contact", not mv.makes_contact)
	if not seen.has("punching"): _chk(tag + " NOT punching_move", not mv.punching_move)
	if not seen.has("biting"): _chk(tag + " NOT biting_move", not mv.biting_move)
	if not seen.has("sound"): _chk(tag + " NOT sound_move", not mv.sound_move)
	if not seen.has("slicing"): _chk(tag + " NOT slicing_move", not mv.slicing_move)
	if not seen.has("ballistic"): _chk(tag + " NOT ballistic_move", not mv.ballistic_move)
	if not seen.has("powder"): _chk(tag + " NOT powder_move", not mv.powder_move)
	if not seen.has("pulse"): _chk(tag + " NOT pulse_move", not mv.pulse_move)
	if not seen.has("always_crit"): _chk(tag + " NOT always_critical_hit", not mv.always_critical_hit)
	if not seen.has("thaws"): _chk(tag + " NOT thaws_user", not mv.thaws_user)
	if not seen.has("double_min"): _chk(tag + " NOT double_power_on_minimized", not mv.double_power_on_minimized)
	if not seen.has("bounceable"): _chk(tag + " NOT bounceable", not mv.bounceable)
	if not seen.has("healing_move"): _chk(tag + " NOT healing_move", not mv.healing_move)
	if not seen.has("spread"): _chk(tag + " NOT is_spread", not mv.is_spread)
	if not seen.has("crit"): _chk(tag + " critical_hit_stage=0", mv.critical_hit_stage == 0)
	if not seen.has("prio"): _chk(tag + " priority=0", mv.priority == 0)


# ── Group 1: EFFECT_HIT + single secondary (72 moves) ────────────────────────
# [id, name, type, category, power, accuracy, pp, secondary_effect_or_"BREAK_SCREEN", chance, flag_tokens]

func _test_effect_hit() -> void:
	var expected := [
		[7, "Fire Punch", TypeChart.TYPE_FIRE, 0, 75, 100, 15, MoveData.SE_BURN, 10, ["contact", "punching"]],
		[8, "Ice Punch", TypeChart.TYPE_ICE, 0, 75, 100, 15, MoveData.SE_FREEZE, 10, ["contact", "punching"]],
		[9, "Thunder Punch", TypeChart.TYPE_ELECTRIC, 0, 75, 100, 15, MoveData.SE_PARALYSIS, 10, ["contact", "punching"]],
		[27, "Rolling Kick", TypeChart.TYPE_FIGHTING, 0, 60, 85, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		[29, "Headbutt", TypeChart.TYPE_NORMAL, 0, 70, 100, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		[40, "Poison Sting", TypeChart.TYPE_POISON, 0, 15, 100, 35, MoveData.SE_POISON, 30, []],
		[44, "Bite", TypeChart.TYPE_DARK, 0, 60, 100, 25, MoveData.SE_FLINCH, 30, ["contact", "biting"]],
		[59, "Blizzard", TypeChart.TYPE_ICE, 1, 110, 70, 5, MoveData.SE_FREEZE, 10, ["spread"]],
		[85, "Thunderbolt", TypeChart.TYPE_ELECTRIC, 1, 90, 100, 15, MoveData.SE_PARALYSIS, 10, []],
		[93, "Confusion", TypeChart.TYPE_PSYCHIC, 1, 50, 100, 25, MoveData.SE_CONFUSION, 10, []],
		[122, "Lick", TypeChart.TYPE_GHOST, 0, 30, 100, 30, MoveData.SE_PARALYSIS, 30, ["contact"]],
		[123, "Smog", TypeChart.TYPE_POISON, 1, 30, 70, 20, MoveData.SE_POISON, 40, []],
		[124, "Sludge", TypeChart.TYPE_POISON, 1, 65, 100, 20, MoveData.SE_POISON, 30, []],
		[125, "Bone Club", TypeChart.TYPE_GROUND, 0, 65, 85, 20, MoveData.SE_FLINCH, 10, []],
		[126, "Fire Blast", TypeChart.TYPE_FIRE, 1, 110, 85, 5, MoveData.SE_BURN, 10, []],
		[127, "Waterfall", TypeChart.TYPE_WATER, 0, 80, 100, 15, MoveData.SE_FLINCH, 20, ["contact"]],
		[146, "Dizzy Punch", TypeChart.TYPE_NORMAL, 0, 70, 100, 10, MoveData.SE_CONFUSION, 20, ["contact", "punching"]],
		[158, "Hyper Fang", TypeChart.TYPE_NORMAL, 0, 80, 90, 15, MoveData.SE_FLINCH, 10, ["contact", "biting"]],
		[181, "Powder Snow", TypeChart.TYPE_ICE, 1, 40, 100, 25, MoveData.SE_FREEZE, 10, ["spread"]],
		[188, "Sludge Bomb", TypeChart.TYPE_POISON, 1, 90, 100, 10, MoveData.SE_POISON, 30, ["ballistic"]],
		[192, "Zap Cannon", TypeChart.TYPE_ELECTRIC, 1, 120, 50, 5, MoveData.SE_PARALYSIS, 100, ["ballistic"]],
		[209, "Spark", TypeChart.TYPE_ELECTRIC, 0, 65, 100, 20, MoveData.SE_PARALYSIS, 30, ["contact"]],
		[221, "Sacred Fire", TypeChart.TYPE_FIRE, 0, 100, 95, 5, MoveData.SE_BURN, 50, ["thaws"]],
		[223, "Dynamic Punch", TypeChart.TYPE_FIGHTING, 0, 100, 50, 5, MoveData.SE_CONFUSION, 100, ["contact", "punching"]],
		[225, "Dragon Breath", TypeChart.TYPE_DRAGON, 1, 60, 100, 20, MoveData.SE_PARALYSIS, 30, []],
		[239, "Twister", TypeChart.TYPE_DRAGON, 1, 40, 100, 20, MoveData.SE_FLINCH, 20, ["spread"]],
		[257, "Heat Wave", TypeChart.TYPE_FIRE, 1, 95, 90, 10, MoveData.SE_BURN, 10, ["spread"]],
		[299, "Blaze Kick", TypeChart.TYPE_FIRE, 0, 85, 90, 10, MoveData.SE_BURN, 10, ["contact", "crit:1"]],
		[302, "Needle Arm", TypeChart.TYPE_GRASS, 0, 60, 100, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		[305, "Poison Fang", TypeChart.TYPE_POISON, 0, 50, 100, 15, MoveData.SE_TOXIC, 50, ["contact", "biting"]],
		[310, "Astonish", TypeChart.TYPE_GHOST, 0, 30, 100, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		[324, "Signal Beam", TypeChart.TYPE_BUG, 1, 75, 100, 15, MoveData.SE_CONFUSION, 10, []],
		[326, "Extrasensory", TypeChart.TYPE_PSYCHIC, 1, 80, 100, 20, MoveData.SE_FLINCH, 10, []],
		[342, "Poison Tail", TypeChart.TYPE_POISON, 0, 50, 100, 25, MoveData.SE_POISON, 10, ["contact", "crit:1"]],
		[352, "Water Pulse", TypeChart.TYPE_WATER, 1, 60, 100, 20, MoveData.SE_CONFUSION, 20, ["pulse"]],
		[395, "Force Palm", TypeChart.TYPE_FIGHTING, 0, 60, 100, 10, MoveData.SE_PARALYSIS, 30, ["contact"]],
		[398, "Poison Jab", TypeChart.TYPE_POISON, 0, 80, 100, 20, MoveData.SE_POISON, 30, ["contact"]],
		[399, "Dark Pulse", TypeChart.TYPE_DARK, 1, 80, 100, 15, MoveData.SE_FLINCH, 20, ["pulse"]],
		[403, "Air Slash", TypeChart.TYPE_FLYING, 1, 75, 95, 15, MoveData.SE_FLINCH, 30, ["slicing"]],
		[407, "Dragon Rush", TypeChart.TYPE_DRAGON, 0, 100, 75, 10, MoveData.SE_FLINCH, 20, ["contact", "double_min"]],
		[428, "Zen Headbutt", TypeChart.TYPE_PSYCHIC, 0, 80, 90, 15, MoveData.SE_FLINCH, 20, ["contact"]],
		[431, "Rock Climb", TypeChart.TYPE_NORMAL, 0, 90, 85, 20, MoveData.SE_CONFUSION, 20, ["contact"]],
		[435, "Discharge", TypeChart.TYPE_ELECTRIC, 1, 80, 100, 15, MoveData.SE_PARALYSIS, 30, ["spread"]],
		[436, "Lava Plume", TypeChart.TYPE_FIRE, 1, 80, 100, 15, MoveData.SE_BURN, 30, ["spread"]],
		[440, "Cross Poison", TypeChart.TYPE_POISON, 0, 70, 100, 20, MoveData.SE_POISON, 10, ["contact", "slicing", "crit:1"]],
		[441, "Gunk Shot", TypeChart.TYPE_POISON, 0, 120, 80, 5, MoveData.SE_POISON, 30, []],
		[442, "Iron Head", TypeChart.TYPE_STEEL, 0, 80, 100, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		[482, "Sludge Wave", TypeChart.TYPE_POISON, 1, 95, 100, 10, MoveData.SE_POISON, 10, ["spread"]],
		[503, "Scald", TypeChart.TYPE_WATER, 1, 80, 100, 15, MoveData.SE_BURN, 30, ["thaws"]],
		[517, "Inferno", TypeChart.TYPE_FIRE, 1, 100, 50, 5, MoveData.SE_BURN, 100, []],
		[531, "Heart Stamp", TypeChart.TYPE_PSYCHIC, 0, 60, 100, 25, MoveData.SE_FLINCH, 30, ["contact"]],
		[537, "Steamroller", TypeChart.TYPE_BUG, 0, 65, 100, 20, MoveData.SE_FLINCH, 30, ["contact", "double_min"]],
		[545, "Searing Shot", TypeChart.TYPE_FIRE, 1, 100, 100, 5, MoveData.SE_BURN, 30, ["ballistic", "spread"]],
		[547, "Relic Song", TypeChart.TYPE_NORMAL, 1, 75, 100, 10, MoveData.SE_SLEEP, 10, ["sound", "spread", "ignores_sub"]],
		[550, "Bolt Strike", TypeChart.TYPE_ELECTRIC, 0, 130, 85, 5, MoveData.SE_PARALYSIS, 20, ["contact"]],
		[551, "Blue Flare", TypeChart.TYPE_FIRE, 1, 130, 85, 5, MoveData.SE_BURN, 20, []],
		[556, "Icicle Crash", TypeChart.TYPE_ICE, 0, 85, 90, 10, MoveData.SE_FLINCH, 30, []],
		[592, "Steam Eruption", TypeChart.TYPE_WATER, 1, 110, 95, 5, MoveData.SE_BURN, 30, ["thaws"]],
		[609, "Nuzzle", TypeChart.TYPE_ELECTRIC, 0, 20, 100, 20, MoveData.SE_PARALYSIS, 100, ["contact"]],
		[660, "Psychic Fangs", TypeChart.TYPE_PSYCHIC, 0, 85, 100, 15, "BREAK_SCREEN", 0, ["contact", "biting"]],
		[670, "Zing Zap", TypeChart.TYPE_ELECTRIC, 0, 80, 100, 10, MoveData.SE_FLINCH, 30, ["contact"]],
		[677, "Splishy Splash", TypeChart.TYPE_WATER, 1, 90, 100, 15, MoveData.SE_PARALYSIS, 30, ["spread"]],
		[678, "Floaty Fall", TypeChart.TYPE_FLYING, 0, 90, 95, 15, MoveData.SE_FLINCH, 30, ["contact"]],
		# [M21.5 Bucket 3] chance corrected 100->0: source omits `.chance`
		# entirely for both (unlike Nuzzle's own explicit `.chance = 100`
		# two rows up) -- 0 = guaranteed, Sheer-Force-exempt, matching this
		# project's own established convention for that shape.
		[681, "Buzzy Buzz", TypeChart.TYPE_ELECTRIC, 1, 60, 100, 20, MoveData.SE_PARALYSIS, 0, []],
		[682, "Sizzly Slide", TypeChart.TYPE_FIRE, 0, 60, 100, 20, MoveData.SE_BURN, 0, ["contact", "thaws"]],
		[708, "Pyro Ball", TypeChart.TYPE_FIRE, 0, 120, 90, 5, MoveData.SE_BURN, 10, ["ballistic", "thaws"]],
		[718, "Strange Steam", TypeChart.TYPE_FAIRY, 1, 90, 95, 10, MoveData.SE_CONFUSION, 20, []],
		[743, "Scorching Sands", TypeChart.TYPE_GROUND, 1, 70, 100, 10, MoveData.SE_BURN, 30, ["thaws"]],
		[749, "Freezing Glare", TypeChart.TYPE_PSYCHIC, 1, 90, 100, 10, MoveData.SE_FREEZE, 10, []],
		[750, "Fiery Wrath", TypeChart.TYPE_DARK, 1, 90, 100, 10, MoveData.SE_FLINCH, 20, ["spread"]],
		[764, "Mountain Gale", TypeChart.TYPE_ICE, 0, 100, 85, 10, MoveData.SE_FLINCH, 30, []],
		[847, "Malignant Chain", TypeChart.TYPE_POISON, 1, 100, 100, 5, MoveData.SE_TOXIC, 50, []],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "HIT.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/category/power/accuracy/pp)",
				mv.move_name == e[1] and mv.type == e[2] and mv.category == e[3]
				and mv.power == e[4] and mv.accuracy == e[5] and mv.pp == e[6])
		if typeof(e[7]) == TYPE_STRING and e[7] == "BREAK_SCREEN":
			_chk(tag + " breaks_screens", mv.breaks_screens)
		else:
			_chk(tag + " secondary_effect", mv.secondary_effect == e[7])
			_chk(tag + " secondary_chance=%d" % e[8], mv.secondary_chance == e[8])
		_chk_flag_tokens(tag, mv, e[9])


# ── Group 2: pure EFFECT_STAT_CHANGE (30 moves) ───────────────────────────────
# [id, name, type, accuracy, pp, stat_stage, amount, self, flag_tokens]

func _test_effect_stat_change() -> void:
	var expected := [
		[81, "String Shot", TypeChart.TYPE_BUG, 95, 40, BattlePokemon.STAGE_SPEED, -2, false, ["bounceable", "spread"]],
		[96, "Meditate", TypeChart.TYPE_PSYCHIC, 0, 40, BattlePokemon.STAGE_ATK, 1, true, ["ignores_protect"]],
		[97, "Agility", TypeChart.TYPE_PSYCHIC, 0, 30, BattlePokemon.STAGE_SPEED, 2, true, ["ignores_protect"]],
		[103, "Screech", TypeChart.TYPE_NORMAL, 85, 40, BattlePokemon.STAGE_DEF, -2, false, ["sound", "bounceable", "ignores_sub"]],
		[104, "Double Team", TypeChart.TYPE_NORMAL, 0, 15, BattlePokemon.STAGE_EVASION, 1, true, ["ignores_protect"]],
		[106, "Harden", TypeChart.TYPE_NORMAL, 0, 30, BattlePokemon.STAGE_DEF, 1, true, ["ignores_protect"]],
		[108, "Smokescreen", TypeChart.TYPE_NORMAL, 100, 20, BattlePokemon.STAGE_ACCURACY, -1, false, ["bounceable"]],
		[110, "Withdraw", TypeChart.TYPE_WATER, 0, 40, BattlePokemon.STAGE_DEF, 1, true, ["ignores_protect"]],
		[112, "Barrier", TypeChart.TYPE_PSYCHIC, 0, 20, BattlePokemon.STAGE_DEF, 2, true, ["ignores_protect"]],
		[133, "Amnesia", TypeChart.TYPE_PSYCHIC, 0, 20, BattlePokemon.STAGE_SPDEF, 2, true, ["ignores_protect"]],
		[134, "Kinesis", TypeChart.TYPE_PSYCHIC, 80, 15, BattlePokemon.STAGE_ACCURACY, -1, false, ["bounceable"]],
		[148, "Flash", TypeChart.TYPE_NORMAL, 100, 20, BattlePokemon.STAGE_ACCURACY, -1, false, ["bounceable"]],
		[151, "Acid Armor", TypeChart.TYPE_POISON, 0, 20, BattlePokemon.STAGE_DEF, 2, true, ["ignores_protect"]],
		[159, "Sharpen", TypeChart.TYPE_NORMAL, 0, 30, BattlePokemon.STAGE_ATK, 1, true, ["ignores_protect"]],
		[178, "Cotton Spore", TypeChart.TYPE_GRASS, 100, 40, BattlePokemon.STAGE_SPEED, -2, false, ["powder", "bounceable", "spread"]],
		[184, "Scary Face", TypeChart.TYPE_NORMAL, 100, 10, BattlePokemon.STAGE_SPEED, -2, false, ["bounceable"]],
		[204, "Charm", TypeChart.TYPE_FAIRY, 100, 20, BattlePokemon.STAGE_ATK, -2, false, ["bounceable"]],
		[230, "Sweet Scent", TypeChart.TYPE_NORMAL, 100, 20, BattlePokemon.STAGE_EVASION, -2, false, ["bounceable", "spread"]],
		[294, "Tail Glow", TypeChart.TYPE_BUG, 0, 20, BattlePokemon.STAGE_SPATK, 3, true, ["ignores_protect"]],
		[297, "Feather Dance", TypeChart.TYPE_FLYING, 100, 15, BattlePokemon.STAGE_ATK, -2, false, ["bounceable"]],
		[313, "Fake Tears", TypeChart.TYPE_DARK, 100, 20, BattlePokemon.STAGE_SPDEF, -2, false, ["bounceable"]],
		[319, "Metal Sound", TypeChart.TYPE_STEEL, 85, 40, BattlePokemon.STAGE_SPDEF, -2, false, ["sound", "bounceable", "ignores_sub"]],
		[334, "Iron Defense", TypeChart.TYPE_STEEL, 0, 15, BattlePokemon.STAGE_DEF, 2, true, ["ignores_protect"]],
		[397, "Rock Polish", TypeChart.TYPE_ROCK, 0, 20, BattlePokemon.STAGE_SPEED, 2, true, ["ignores_protect"]],
		[417, "Nasty Plot", TypeChart.TYPE_DARK, 0, 20, BattlePokemon.STAGE_SPATK, 2, true, ["ignores_protect"]],
		[538, "Cotton Guard", TypeChart.TYPE_GRASS, 0, 10, BattlePokemon.STAGE_DEF, 3, true, ["ignores_protect"]],
		[589, "Play Nice", TypeChart.TYPE_NORMAL, 0, 20, BattlePokemon.STAGE_ATK, -1, false, ["ignores_protect", "ignores_sub", "bounceable"]],
		[590, "Confide", TypeChart.TYPE_NORMAL, 0, 20, BattlePokemon.STAGE_SPATK, -1, false, ["sound", "ignores_protect", "bounceable", "ignores_sub"]],
		[598, "Eerie Impulse", TypeChart.TYPE_ELECTRIC, 100, 15, BattlePokemon.STAGE_SPATK, -2, false, ["bounceable"]],
		[608, "Baby-Doll Eyes", TypeChart.TYPE_FAIRY, 100, 30, BattlePokemon.STAGE_ATK, -1, false, ["bounceable", "prio:1"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "STAT.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/accuracy/pp/power=0/category=STATUS)",
				mv.move_name == e[1] and mv.type == e[2] and mv.accuracy == e[3]
				and mv.pp == e[4] and mv.power == 0 and mv.category == 2)
		_chk(tag + " stat_change_stat", mv.stat_change_stat == e[5])
		_chk(tag + " stat_change_amount=%d" % e[6], mv.stat_change_amount == e[6])
		_chk(tag + " stat_change_self=%s" % e[7], mv.stat_change_self == e[7])
		_chk_flag_tokens(tag, mv, e[8])


# ── Group 3: EFFECT_NON_VOLATILE_STATUS (9 moves) ─────────────────────────────
# [id, name, type, accuracy, pp, secondary_effect, flag_tokens]

func _test_effect_non_volatile_status() -> void:
	var expected := [
		[47, "Sing", TypeChart.TYPE_NORMAL, 55, 15, MoveData.SE_SLEEP, ["sound", "bounceable", "ignores_sub"]],
		[77, "Poison Powder", TypeChart.TYPE_POISON, 75, 35, MoveData.SE_POISON, ["powder", "bounceable"]],
		[78, "Stun Spore", TypeChart.TYPE_GRASS, 75, 30, MoveData.SE_PARALYSIS, ["powder", "bounceable"]],
		[95, "Hypnosis", TypeChart.TYPE_PSYCHIC, 60, 20, MoveData.SE_SLEEP, ["bounceable"]],
		[137, "Glare", TypeChart.TYPE_NORMAL, 100, 30, MoveData.SE_PARALYSIS, ["bounceable"]],
		[139, "Poison Gas", TypeChart.TYPE_POISON, 90, 40, MoveData.SE_POISON, ["bounceable", "spread"]],
		[142, "Lovely Kiss", TypeChart.TYPE_NORMAL, 75, 10, MoveData.SE_SLEEP, ["bounceable"]],
		[147, "Spore", TypeChart.TYPE_GRASS, 100, 15, MoveData.SE_SLEEP, ["powder", "bounceable"]],
		[320, "Grass Whistle", TypeChart.TYPE_GRASS, 55, 15, MoveData.SE_SLEEP, ["sound", "bounceable", "ignores_sub"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "NVS.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/accuracy/pp/power=0/category=STATUS)",
				mv.move_name == e[1] and mv.type == e[2] and mv.accuracy == e[3]
				and mv.pp == e[4] and mv.power == 0 and mv.category == 2)
		_chk(tag + " secondary_effect", mv.secondary_effect == e[5])
		_chk(tag + " secondary_chance=0 (guaranteed)", mv.secondary_chance == 0)
		_chk_flag_tokens(tag, mv, e[6])


# ── Group 4: EFFECT_RECOIL (9 moves) ──────────────────────────────────────────
# [id, name, type, category, power, accuracy, pp, recoil_percent, secondary_effect, chance, flag_tokens]

func _test_effect_recoil() -> void:
	var expected := [
		[66, "Submission", TypeChart.TYPE_FIGHTING, 0, 80, 80, 20, 25, MoveData.SE_NONE, 0, ["contact"]],
		[344, "Volt Tackle", TypeChart.TYPE_ELECTRIC, 0, 120, 100, 15, 33, MoveData.SE_PARALYSIS, 10, ["contact"]],
		[394, "Flare Blitz", TypeChart.TYPE_FIRE, 0, 120, 100, 15, 33, MoveData.SE_BURN, 10, ["contact", "thaws"]],
		[452, "Wood Hammer", TypeChart.TYPE_GRASS, 0, 120, 100, 15, 33, MoveData.SE_NONE, 0, ["contact"]],
		[457, "Head Smash", TypeChart.TYPE_ROCK, 0, 150, 80, 5, 50, MoveData.SE_NONE, 0, ["contact"]],
		[528, "Wild Charge", TypeChart.TYPE_ELECTRIC, 0, 90, 100, 15, 25, MoveData.SE_NONE, 0, ["contact"]],
		[543, "Head Charge", TypeChart.TYPE_NORMAL, 0, 120, 100, 15, 25, MoveData.SE_NONE, 0, ["contact"]],
		[617, "Light Of Ruin", TypeChart.TYPE_FAIRY, 1, 140, 90, 5, 50, MoveData.SE_NONE, 0, []],
		[762, "Wave Crash", TypeChart.TYPE_WATER, 0, 120, 100, 10, 33, MoveData.SE_NONE, 0, ["contact"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "RECOIL.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/category/power/accuracy/pp)",
				mv.move_name == e[1] and mv.type == e[2] and mv.category == e[3]
				and mv.power == e[4] and mv.accuracy == e[5] and mv.pp == e[6])
		_chk(tag + " recoil_percent=%d" % e[7], mv.recoil_percent == e[7])
		if e[8] != MoveData.SE_NONE:
			_chk(tag + " secondary_effect", mv.secondary_effect == e[8])
			_chk(tag + " secondary_chance=%d" % e[9], mv.secondary_chance == e[9])
		else:
			_chk(tag + " no secondary_effect", mv.secondary_effect == MoveData.SE_NONE)
		_chk_flag_tokens(tag, mv, e[10])


# ── Group 5: EFFECT_ABSORB (8 moves) ──────────────────────────────────────────
# [id, name, type, category, power, accuracy, pp, drain_percent, secondary_effect, chance, flag_tokens]

func _test_effect_absorb() -> void:
	var expected := [
		[141, "Leech Life", TypeChart.TYPE_BUG, 0, 80, 100, 10, 50, MoveData.SE_NONE, 0, ["contact", "healing_move"]],
		[532, "Horn Leech", TypeChart.TYPE_GRASS, 0, 75, 100, 10, 50, MoveData.SE_NONE, 0, ["contact", "healing_move"]],
		[570, "Parabolic Charge", TypeChart.TYPE_ELECTRIC, 1, 65, 100, 20, 50, MoveData.SE_NONE, 0, ["spread", "healing_move"]],
		[577, "Draining Kiss", TypeChart.TYPE_FAIRY, 1, 50, 100, 10, 75, MoveData.SE_NONE, 0, ["contact", "healing_move"]],
		[613, "Oblivion Wing", TypeChart.TYPE_FLYING, 1, 80, 100, 10, 75, MoveData.SE_NONE, 0, ["healing_move"]],
		[680, "Bouncy Bubble", TypeChart.TYPE_WATER, 1, 60, 100, 20, 100, MoveData.SE_NONE, 0, ["healing_move"]],
		[817, "Bitter Blade", TypeChart.TYPE_FIRE, 0, 90, 100, 10, 50, MoveData.SE_NONE, 0, ["contact", "slicing", "healing_move"]],
		[830, "Matcha Gotcha", TypeChart.TYPE_GRASS, 1, 80, 90, 15, 50, MoveData.SE_BURN, 20, ["thaws", "healing_move", "spread"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "ABSORB.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/category/power/accuracy/pp)",
				mv.move_name == e[1] and mv.type == e[2] and mv.category == e[3]
				and mv.power == e[4] and mv.accuracy == e[5] and mv.pp == e[6])
		_chk(tag + " drain_percent=%d" % e[7], mv.drain_percent == e[7])
		if e[8] != MoveData.SE_NONE:
			_chk(tag + " secondary_effect", mv.secondary_effect == e[8])
			_chk(tag + " secondary_chance=%d" % e[9], mv.secondary_chance == e[9])
		else:
			_chk(tag + " no secondary_effect", mv.secondary_effect == MoveData.SE_NONE)
		_chk_flag_tokens(tag, mv, e[10])


# ── Group 6: EFFECT_CONFUSE (3 moves) ─────────────────────────────────────────
# [id, name, type, accuracy, pp, flag_tokens]

func _test_effect_confuse() -> void:
	var expected := [
		[48, "Supersonic", TypeChart.TYPE_NORMAL, 55, 20, ["sound", "bounceable", "ignores_sub"]],
		[186, "Sweet Kiss", TypeChart.TYPE_FAIRY, 75, 10, ["bounceable"]],
		[298, "Teeter Dance", TypeChart.TYPE_NORMAL, 100, 20, ["spread"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "CONFUSE.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/accuracy/pp/power=0/category=STATUS)",
				mv.move_name == e[1] and mv.type == e[2] and mv.accuracy == e[3]
				and mv.pp == e[4] and mv.power == 0 and mv.category == 2)
		_chk(tag + " secondary_effect=SE_CONFUSION", mv.secondary_effect == MoveData.SE_CONFUSION)
		_chk(tag + " secondary_chance=0 (guaranteed)", mv.secondary_chance == 0)
		_chk_flag_tokens(tag, mv, e[5])


# ── Group 7: EFFECT_SEMI_INVULNERABLE (2 moves: Dive/Bounce) ─────────────────
# [id, name, type, power, accuracy, pp, semi_inv_state, secondary_effect, chance, flag_tokens]

func _test_effect_semi_invulnerable() -> void:
	var expected := [
		[291, "Dive", TypeChart.TYPE_WATER, 80, 100, 10, MoveData.SEMI_INV_UNDERWATER, MoveData.SE_NONE, 0, ["contact"]],
		[340, "Bounce", TypeChart.TYPE_FLYING, 85, 85, 5, MoveData.SEMI_INV_ON_AIR, MoveData.SE_PARALYSIS, 30, ["contact"]],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "SEMIINV.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/power/accuracy/pp)",
				mv.move_name == e[1] and mv.type == e[2] and mv.power == e[3]
				and mv.accuracy == e[4] and mv.pp == e[5])
		_chk(tag + " two_turn", mv.two_turn)
		_chk(tag + " semi_inv_state", mv.semi_inv_state == e[6])
		if e[7] != MoveData.SE_NONE:
			_chk(tag + " secondary_effect", mv.secondary_effect == e[7])
			_chk(tag + " secondary_chance=%d" % e[8], mv.secondary_chance == e[8])
		_chk_flag_tokens(tag, mv, e[9])


# ── Group 8: EFFECT_TWO_TURNS_ATTACK (2 moves: Freeze Shock/Ice Burn) ────────
# [id, name, type, category, power, accuracy, pp, secondary_effect, chance, flag_tokens]

func _test_effect_two_turns_attack() -> void:
	var expected := [
		[553, "Freeze Shock", TypeChart.TYPE_ICE, 0, 140, 90, 5, MoveData.SE_PARALYSIS, 30, []],
		[554, "Ice Burn", TypeChart.TYPE_ICE, 1, 140, 90, 5, MoveData.SE_BURN, 30, []],	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "2TURN.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/category/power/accuracy/pp)",
				mv.move_name == e[1] and mv.type == e[2] and mv.category == e[3]
				and mv.power == e[4] and mv.accuracy == e[5] and mv.pp == e[6])
		_chk(tag + " two_turn", mv.two_turn)
		_chk(tag + " semi_inv_state=NONE (charge only, no vanish)", mv.semi_inv_state == MoveData.SEMI_INV_NONE)
		_chk(tag + " secondary_effect", mv.secondary_effect == e[7])
		_chk(tag + " secondary_chance=%d" % e[8], mv.secondary_chance == e[8])
		_chk_flag_tokens(tag, mv, e[9])

# ── Functional confirmation ────────────────────────────────────────────────
# Scoped per this tier's own testing convention: EFFECT_STAT_CHANGE/
# EFFECT_NON_VOLATILE_STATUS/EFFECT_CONFUSE/EFFECT_RECOIL/EFFECT_ABSORB's
# drain/EFFECT_SEMI_INVULNERABLE's semi-invulnerable-bypass mechanisms are
# ALL already proven in general by earlier tiers (Swords Dance/Growl,
# Sleep Powder/Thunder Wave/Toxic/Will-O-Wisp, Confuse Ray, Take Down/
# Double-Edge, Absorb/Giga Drain, Fly/Dig respectively) — re-deriving them
# functionally here would just repeat an already-covered mechanism on new
# data, not test anything new. Only genuinely NEW-to-this-tier plumbing is
# checked: (1) a representative EFFECT_HIT move through the real dispatch
# path, confirming this whole batch's data shape is wired correctly, not
# just present on disk; (2)/(3) makes_contact still correctly triggers
# Rough Skin on these specific new moves, with a non-contact discriminator;
# (4)/(5) the healing_move flag newly added to the EFFECT_ABSORB cluster's
# Bitter Blade/Matcha Gotcha (per Step 0's Giga-Drain-precedent finding)
# actually grants Triage's +3 priority bonus — genuinely never exercised by
# real data before (Giga Drain itself is missing this flag, a pre-existing
# gap flagged, not fixed, in docs/decisions.md).

func _test_functional() -> void:
	# F1: a representative EFFECT_HIT move (Fire Punch) deals real nonzero
	# damage through the actual .tres -> dispatch -> DamageCalculator
	# pipeline.
	var fire_punch := _load_move(7)
	var f1_atk := _make_mon("F1Atk", TypeChart.TYPE_FIRE)
	f1_atk.add_move(fire_punch)
	var f1_def := _make_mon("F1Def", TypeChart.TYPE_NORMAL)
	f1_def.add_move(fire_punch)
	var f1_bm := _make_bm()
	f1_bm._force_hit = true
	f1_bm._force_crit = false
	f1_bm._force_roll = 100
	var f1_dmg := [0]
	f1_bm.move_executed.connect(func(a, d, m, dmg):
		if f1_dmg[0] == 0 and a == f1_atk:
			f1_dmg[0] = dmg)
	f1_bm.queue_move(0, 0)
	f1_bm.queue_move(1, 0)
	f1_bm.start_battle(f1_atk, f1_def)
	_chk("F1 Fire Punch deals real nonzero damage through the real dispatch path",
			f1_dmg[0] > 0)

	# F2: makes_contact=true still correctly triggers Rough Skin on this
	# batch's own new moves (Headbutt), matching [M18.5g]'s established
	# _force_contact_roll pattern.
	var headbutt := _load_move(29)
	var f2_atk := _make_mon("F2Atk", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 100)
	f2_atk.add_move(headbutt)
	var f2_def := _make_mon("F2Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	f2_def.ability = _load_ability(24)  # Rough Skin
	f2_def.add_move(headbutt)
	var f2_bm := _make_bm()
	f2_bm._force_hit = true
	f2_bm._force_crit = false
	f2_bm._force_roll = 100
	f2_bm._force_contact_roll = true
	var f2_recoil_fired := [false]
	f2_bm.recoil_damage.connect(func(a, _amt):
		if a == f2_atk:
			f2_recoil_fired[0] = true)
	f2_bm.queue_move(0, 0)
	f2_bm.queue_move(1, 0)
	f2_bm.start_battle(f2_atk, f2_def)
	_chk("F2 Headbutt (makes_contact=true) triggers Rough Skin recoil on the attacker",
			f2_recoil_fired[0])

	# F3: discriminator — Poison Sting (makes_contact=false) does NOT trigger
	# Rough Skin, confirming F2 wasn't a vacuous pass.
	var poison_sting := _load_move(40)
	var f3_atk := _make_mon("F3Atk", TypeChart.TYPE_POISON, 300, 60, 60, 60, 60, 100)
	f3_atk.add_move(poison_sting)
	var f3_def := _make_mon("F3Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	f3_def.ability = _load_ability(24)  # Rough Skin
	f3_def.add_move(poison_sting)
	var f3_bm := _make_bm()
	f3_bm._force_hit = true
	f3_bm._force_crit = false
	f3_bm._force_roll = 100
	f3_bm._force_contact_roll = true
	var f3_recoil_fired := [false]
	f3_bm.recoil_damage.connect(func(a, _amt):
		if a == f3_atk:
			f3_recoil_fired[0] = true)
	f3_bm.queue_move(0, 0)
	f3_bm.queue_move(1, 0)
	f3_bm.start_battle(f3_atk, f3_def)
	_chk("F3 Poison Sting (makes_contact=false) does NOT trigger Rough Skin (discriminator)",
			not f3_recoil_fired[0])

	# F4: healing_move (newly added to Bitter Blade per Step 0's Giga-Drain-
	# precedent finding) actually grants Triage's +3 priority bonus —
	# confirms the flag isn't inert data. A direct call, not a full-battle
	# turn-order re-derivation (already covered by battle_test.gd/M17c).
	var bitter_blade := _load_move(817)
	var f4_mon := _make_mon("F4Mon", TypeChart.TYPE_FIRE)
	f4_mon.ability = _load_ability(205)  # Triage
	_chk("F4 Bitter Blade (healing_move=true) grants Triage's +3 priority bonus",
			AbilityManager.move_priority_bonus(f4_mon, bitter_blade, false) == 3)

	# F5: discriminator — a plain damaging move with healing_move=false gets
	# NO Triage bonus, confirming F4 wasn't vacuous.
	var fire_punch2 := _load_move(7)
	_chk("F5 Fire Punch (healing_move=false) gets NO Triage bonus (discriminator)",
			AbilityManager.move_priority_bonus(f4_mon, fire_punch2, false) == 0)
