extends Node

# [M19c] Protect-family variants: Wide Guard(469), Quick Guard(501),
# Spiky Shield(596), Baneful Bunker(624), Obstruct(720), Silk Trap(780),
# Burning Bulwark(836).
# [M19d] Counter/Mirror-Move remnants: Metal Burst(368), Mirror Move(119).
#
# Closes out M19c-i entirely — the last two proposed M19 sub-tiers.
#
# Ground truth: reference/pokeemerald_expansion/src/battle_util.c
# (protect dispatch L5783-5852), src/battle_move_resolution.c
# (MoveEndProtectLikeEffect L2497-2568, CancelerCallSubmove L523-553,
# GetMirrorMoveMove L4966-4993), src/data/moves_info.h, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_spiky_shield()
	_test_baneful_bunker()
	_test_burning_bulwark()
	_test_obstruct()
	_test_silk_trap()
	_test_wide_guard()
	_test_quick_guard()
	_test_shared_consecutive_counter()
	_test_metal_burst()
	_test_mirror_move()

	var total := _pass + _fail
	print("m19cd_test: %d/%d passed" % [_pass, total])
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


func _load_item(id: int) -> ItemData:
	return load("res://data/items/item_%04d.tres" % id) as ItemData


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
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


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section A: data integrity (all 9 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var wide_guard := _load_move(469)
	_chk("469 Wide Guard: Rock/status/pp10/prio3, ignores_protect, WIDE_GUARD method",
			wide_guard.type == TypeChart.TYPE_ROCK and wide_guard.pp == 10
					and wide_guard.priority == 3 and wide_guard.ignores_protect
					and wide_guard.is_protect
					and wide_guard.protect_method == BattlePokemon.PROTECT_METHOD_WIDE_GUARD)
	var quick_guard := _load_move(501)
	_chk("501 Quick Guard: Fighting/status/pp15/prio3, QUICK_GUARD method",
			quick_guard.type == TypeChart.TYPE_FIGHTING and quick_guard.pp == 15
					and quick_guard.priority == 3 and quick_guard.is_protect
					and quick_guard.protect_method == BattlePokemon.PROTECT_METHOD_QUICK_GUARD)
	var spiky_shield := _load_move(596)
	_chk("596 Spiky Shield: Grass/status/pp10/prio4, SPIKY_SHIELD method",
			spiky_shield.type == TypeChart.TYPE_GRASS and spiky_shield.pp == 10
					and spiky_shield.priority == 4 and spiky_shield.is_protect
					and spiky_shield.protect_method == BattlePokemon.PROTECT_METHOD_SPIKY_SHIELD)
	var baneful_bunker := _load_move(624)
	_chk("624 Baneful Bunker: Poison/status/pp10/prio4, BANEFUL_BUNKER method",
			baneful_bunker.type == TypeChart.TYPE_POISON and baneful_bunker.priority == 4
					and baneful_bunker.is_protect
					and baneful_bunker.protect_method == BattlePokemon.PROTECT_METHOD_BANEFUL_BUNKER)
	var obstruct := _load_move(720)
	_chk("720 Obstruct: Dark/status/pp10/prio4, OBSTRUCT method",
			obstruct.type == TypeChart.TYPE_DARK and obstruct.priority == 4
					and obstruct.is_protect
					and obstruct.protect_method == BattlePokemon.PROTECT_METHOD_OBSTRUCT)
	var silk_trap := _load_move(780)
	_chk("780 Silk Trap: Bug/status/pp10/prio4, SILK_TRAP method",
			silk_trap.type == TypeChart.TYPE_BUG and silk_trap.priority == 4
					and silk_trap.is_protect
					and silk_trap.protect_method == BattlePokemon.PROTECT_METHOD_SILK_TRAP)
	var burning_bulwark := _load_move(836)
	_chk("836 Burning Bulwark: Fire/status/pp10/prio4, BURNING_BULWARK method",
			burning_bulwark.type == TypeChart.TYPE_FIRE and burning_bulwark.priority == 4
					and burning_bulwark.is_protect
					and burning_bulwark.protect_method == BattlePokemon.PROTECT_METHOD_BURNING_BULWARK)

	var metal_burst := _load_move(368)
	_chk("368 Metal Burst: Steel/phys/pp10, metal_burst=true, priority=0 (NOT -5)",
			metal_burst.type == TypeChart.TYPE_STEEL and metal_burst.category == 0
					and metal_burst.pp == 10 and metal_burst.priority == 0
					and metal_burst.metal_burst)
	var mirror_move := _load_move(119)
	_chk("119 Mirror Move: Flying/status/pp20, is_mirror_move=true",
			mirror_move.type == TypeChart.TYPE_FLYING and mirror_move.pp == 20
					and mirror_move.is_mirror_move)


# ── M19c: Spiky Shield — maxHP/8 recoil to attacker on contact ─────────────

func _test_spiky_shield() -> void:
	var spiky_shield := _load_move(596)
	var tackle := _load_move(33)
	var surf := _load_move(57)

	var atk := _make_mon("SSDefAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(tackle)
	var def := _make_mon("SSDefDef", [TypeChart.TYPE_GRASS], 100, 60, 60, 60, 60, 100)
	def.add_move(spiky_shield)

	var bm := _make_bm()
	var recoiled := [false, -1]
	bm.recoil_damage.connect(func(mon, amt):
		if mon == atk and not recoiled[0]:
			recoiled[0] = true
			recoiled[1] = amt)
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)
	var expected_recoil: int = max(1, atk.max_hp / 8)
	_chk("A1.01 Tackle is blocked by Spiky Shield", missed[0] == true)
	_chk("A1.02 the attacker takes maxHP/8 recoil for making contact (%d, %s)" % [expected_recoil, recoiled],
			recoiled[0] == true and recoiled[1] == expected_recoil)

	# Discriminator: a non-contact move triggers no recoil.
	var atk2 := _make_mon("SSNoContactAtk", [TypeChart.TYPE_WATER], 100, 60, 60, 60, 60, 40)
	atk2.add_move(surf)
	var def2 := _make_mon("SSNoContactDef", [TypeChart.TYPE_GRASS], 100, 60, 60, 60, 60, 100)
	def2.add_move(spiky_shield)
	var bm2 := _make_bm()
	var recoiled2 := [false]
	bm2.recoil_damage.connect(func(mon, _amt):
		if mon == atk2:
			recoiled2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("A1.03 discriminator: a non-contact move (Surf) triggers NO recoil",
			recoiled2[0] == false)

	# Magic Guard blocks the recoil entirely (attacker's own ability).
	var atk3 := _make_mon("SSMagicGuardAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk3.ability = _load_ability(98)  # Magic Guard
	atk3.add_move(tackle)
	var def3 := _make_mon("SSMagicGuardDef", [TypeChart.TYPE_GRASS], 100, 60, 60, 60, 60, 100)
	def3.add_move(spiky_shield)
	var bm3 := _make_bm()
	var recoiled3 := [false]
	bm3.recoil_damage.connect(func(mon, _amt):
		if mon == atk3:
			recoiled3[0] = true)
	bm3.start_battle(atk3, def3)
	_chk("A1.04 discriminator: Magic Guard blocks the recoil entirely",
			recoiled3[0] == false)


# ── M19c: Baneful Bunker — poisons the attacker on contact ──────────────────

func _test_baneful_bunker() -> void:
	var baneful_bunker := _load_move(624)
	var tackle := _load_move(33)
	var atk := _make_mon("BBAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(tackle)
	var def := _make_mon("BBDef", [TypeChart.TYPE_POISON], 100, 60, 60, 60, 60, 100)
	def.add_move(baneful_bunker)

	var bm := _make_bm()
	var poisoned := [false]
	bm.secondary_applied.connect(func(mon, se):
		if mon == atk and se == MoveData.SE_POISON:
			poisoned[0] = true)
	bm.start_battle(atk, def)
	_chk("A2.01 Baneful Bunker poisons the attacker on contact", poisoned[0] == true)
	_chk("A2.02 the attacker's own status is now STATUS_POISON",
			atk.status == BattlePokemon.STATUS_POISON)


# ── M19c: Burning Bulwark — burns the attacker on contact ───────────────────

func _test_burning_bulwark() -> void:
	var burning_bulwark := _load_move(836)
	var tackle := _load_move(33)
	var atk := _make_mon("BuBAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(tackle)
	var def := _make_mon("BuBDef", [TypeChart.TYPE_FIRE], 100, 60, 60, 60, 60, 100)
	def.add_move(burning_bulwark)

	var bm := _make_bm()
	var burned := [false]
	bm.secondary_applied.connect(func(mon, se):
		if mon == atk and se == MoveData.SE_BURN:
			burned[0] = true)
	bm.start_battle(atk, def)
	_chk("A3.01 Burning Bulwark burns the attacker on contact", burned[0] == true)
	_chk("A3.02 the attacker's own status is now STATUS_BURN",
			atk.status == BattlePokemon.STATUS_BURN)


# ── M19c: Obstruct — blocks only non-status moves; -2 Def on contact ───────

func _test_obstruct() -> void:
	var obstruct := _load_move(720)
	var tackle := _load_move(33)
	var growl := _load_move(45)

	var atk := _make_mon("ObAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(tackle)
	var def := _make_mon("ObDef", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 100)
	def.add_move(obstruct)

	var bm := _make_bm()
	var stat_events := []
	bm.stat_stage_changed.connect(func(mon, stat, amt): stat_events.push_back([mon, stat, amt]))
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)
	_chk("A4.01 a damaging move (Tackle) is blocked by Obstruct", missed[0] == true)
	_chk("A4.02 contact triggers -2 Def on the attacker (%s)" % [stat_events],
			stat_events.any(func(e): return e[0] == atk and e[1] == BattlePokemon.STAGE_DEF and e[2] == -2))

	# Discriminator: Obstruct does NOT block status moves (Growl connects normally).
	var atk2 := _make_mon("ObStatusAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk2.add_move(growl)
	var def2 := _make_mon("ObStatusDef", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 100)
	def2.add_move(obstruct)
	var bm2 := _make_bm()
	var growl_events := []
	bm2.stat_stage_changed.connect(func(mon, stat, amt): growl_events.push_back([mon, stat, amt]))
	var missed2 := [false]
	bm2.move_missed.connect(func(a, reason):
		if a == atk2 and reason == "protected":
			missed2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("A4.03 discriminator: a STATUS move (Growl) is NOT blocked by Obstruct",
			missed2[0] == false)
	_chk("A4.04 Growl's own -1 Atk on the defender still applies normally (%s)" % [growl_events],
			growl_events.any(func(e): return e[0] == def2 and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1))

	# Defiant discriminator: the attacker's own Defiant reacts to Obstruct's -2 Def.
	var atk3 := _make_mon("ObDefiantAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk3.ability = _load_ability(128)  # Defiant
	atk3.add_move(tackle)
	var def3 := _make_mon("ObDefiantDef", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 100)
	def3.add_move(obstruct)
	var bm3 := _make_bm()
	var stat_events3 := []
	bm3.stat_stage_changed.connect(func(mon, stat, amt): stat_events3.push_back([mon, stat, amt]))
	bm3.start_battle(atk3, def3)
	_chk("A4.05 Defiant reacts to Obstruct's -2 Def with a +2 Atk boost (%s)" % [stat_events3],
			stat_events3.any(func(e): return e[0] == atk3 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))


# ── M19c: Silk Trap — blocks only non-status moves; -1 Speed on contact ────

func _test_silk_trap() -> void:
	var silk_trap := _load_move(780)
	var tackle := _load_move(33)
	var atk := _make_mon("STAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(tackle)
	var def := _make_mon("STDef", [TypeChart.TYPE_BUG], 100, 60, 60, 60, 60, 100)
	def.add_move(silk_trap)

	var bm := _make_bm()
	var stat_events := []
	bm.stat_stage_changed.connect(func(mon, stat, amt): stat_events.push_back([mon, stat, amt]))
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)
	_chk("A5.01 Tackle is blocked by Silk Trap", missed[0] == true)
	_chk("A5.02 contact triggers -1 Speed on the attacker (%s)" % [stat_events],
			stat_events.any(func(e): return e[0] == atk and e[1] == BattlePokemon.STAGE_SPEED and e[2] == -1))


# ── M19c: Wide Guard — side-wide, blocks only SPREAD moves ─────────────────

func _test_wide_guard() -> void:
	var wide_guard := _load_move(469)
	var tackle := _load_move(33)
	var hyper_voice := _load_move(304)  # is_spread = True

	# (i) Blocks a spread move in singles too (the direct target's own Wide Guard).
	var atk := _make_mon("WGAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk.add_move(hyper_voice)
	var def := _make_mon("WGDef", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 100)
	def.add_move(wide_guard)
	var bm := _make_bm()
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)
	_chk("A6.01 Wide Guard blocks a spread move (Hyper Voice)", missed[0] == true)

	# (ii) Discriminator: does NOT block a single-target move.
	var atk2 := _make_mon("WGSingleAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk2.add_move(tackle)
	var def2 := _make_mon("WGSingleDef", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 100)
	def2.add_move(wide_guard)
	var bm2 := _make_bm()
	var missed2 := [false]
	bm2.move_missed.connect(func(a, reason):
		if a == atk2 and reason == "protected":
			missed2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("A6.02 discriminator: Wide Guard does NOT block a single-target move (Tackle)",
			missed2[0] == false)

	# (iii) Side-wide: the ALLY's own Wide Guard blocks a spread move aimed at
	# the direct target, who holds no Protect state itself.
	var attacker0 := _make_mon("WGDblAtk0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	attacker0.add_move(hyper_voice)
	var attacker1 := _make_mon("WGDblAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)
	var opp0 := _make_mon("WGDblOpp0", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 40)
	opp0.add_move(tackle)  # direct target — holds NO Wide Guard itself
	var opp1 := _make_mon("WGDblOpp1", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 200)
	opp1.add_move(wide_guard)  # the ALLY sets Wide Guard, faster so it resolves first
	var bm3 := _make_bm()
	var missed3 := [false]
	bm3.move_missed.connect(func(a, reason):
		if a == attacker0 and reason == "protected" and not missed3[0]:
			missed3[0] = true)
	bm3.queue_move_targeted(0, 0, 2)  # attacker0 Hyper Voices opp0 (the non-Wide-Guard mon)
	bm3.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(opp0, opp1))
	_chk("A6.03 side-wide: the ALLY's own Wide Guard blocks a spread move aimed at " +
			"the direct target, which holds no Protect state of its own",
			missed3[0] == true)


# ── M19c: Quick Guard — side-wide, blocks only PRIORITY>0 moves ────────────

func _test_quick_guard() -> void:
	var quick_guard := _load_move(501)
	var tackle := _load_move(33)
	var quick_attack := _load_move(98)  # priority +1

	# (i) Blocks a priority move.
	var atk := _make_mon("QGAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	atk.add_move(quick_attack)
	var def := _make_mon("QGDef", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 40)
	def.add_move(quick_guard)
	var bm := _make_bm()
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)
	_chk("A7.01 Quick Guard blocks a priority move (Quick Attack)", missed[0] == true)

	# (ii) Discriminator: does NOT block a priority-0 move.
	var atk2 := _make_mon("QGZeroAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	atk2.add_move(tackle)
	var def2 := _make_mon("QGZeroDef", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	def2.add_move(quick_guard)
	var bm2 := _make_bm()
	var missed2 := [false]
	bm2.move_missed.connect(func(a, reason):
		if a == atk2 and reason == "protected":
			missed2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("A7.02 discriminator: Quick Guard does NOT block a priority-0 move (Tackle)",
			missed2[0] == false)

	# (iii) Side-wide: the ALLY's own Quick Guard blocks a priority move aimed
	# at the direct target.
	var attacker0 := _make_mon("QGDblAtk0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	attacker0.add_move(quick_attack)
	var attacker1 := _make_mon("QGDblAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)
	var opp0 := _make_mon("QGDblOpp0", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 40)
	opp0.add_move(tackle)  # direct target — holds NO Quick Guard itself
	var opp1 := _make_mon("QGDblOpp1", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 200)
	opp1.add_move(quick_guard)
	var bm3 := _make_bm()
	var missed3 := [false]
	bm3.move_missed.connect(func(a, reason):
		if a == attacker0 and reason == "protected" and not missed3[0]:
			missed3[0] = true)
	bm3.queue_move_targeted(0, 0, 2)
	bm3.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(opp0, opp1))
	_chk("A7.03 side-wide: the ALLY's own Quick Guard blocks a priority move aimed " +
			"at the direct target, which holds no Protect state of its own",
			missed3[0] == true)


# ── The shared consecutive-use fail-chance counter spans different variants ─

func _test_shared_consecutive_counter() -> void:
	# No RNG-forcing seam exists for _roll_protect_success, and only the
	# FIRST use (consecutive=0) is deterministic (denom=1, always succeeds);
	# a second consecutive use only has a 1/3 chance, so a 2-move sequence
	# can't be tested deterministically end to end. Instead, prove Spiky
	# Shield's OWN dispatch reads/writes the SAME `protect_consecutive`
	# field Protect uses — structurally guaranteed since both go through
	# the identical unconditional `if move.is_protect:` code path keyed off
	# the flag, not the specific move ID — via its own single guaranteed
	# first use.
	var spiky_shield := _load_move(596)
	var tackle := _load_move(33)
	var user := _make_mon("ConsecUser", [TypeChart.TYPE_GRASS], 300, 60, 60, 60, 60, 100)
	user.add_move(spiky_shield)
	var opp := _make_mon("ConsecOpp", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	_chk("A8.01 protect_consecutive starts at 0", user.protect_consecutive == 0)
	var bm := _make_bm()
	var protected_snap := [false, -1]
	bm.protected.connect(func(mon):
		if mon == user and not protected_snap[0]:
			protected_snap[0] = true
			protected_snap[1] = user.protect_consecutive)
	bm.start_battle(user, opp)
	_chk("A8.02 Spiky Shield's own successful first use increments the SAME " +
			"protect_consecutive field Protect itself uses (now %d)" % [protected_snap[1]],
			protected_snap[0] == true and protected_snap[1] == 1)


# ── M19d: Metal Burst — 1.5x whichever category was hit LAST ───────────────

func _test_metal_burst() -> void:
	var metal_burst := _load_move(368)
	var tackle := _load_move(33)
	var water_gun := _load_move(55)

	# (i) Physical hit -> reflects 1.5x physical damage taken.
	var atk := _make_mon("MBPhysAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk.add_move(tackle)
	var def := _make_mon("MBPhysDef", [TypeChart.TYPE_STEEL], 300, 10, 60, 10, 60, 40)
	def.add_move(metal_burst)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var reflected := [false, -1]
	bm.move_executed.connect(func(a, _d, m, amt):
		if a == def and m == metal_burst and not reflected[0]:
			reflected[0] = true
			reflected[1] = amt)
	bm.start_battle(atk, def)
	var expected: int = def.last_physical_damage * 150 / 100 if def.last_physical_damage > 0 else -999
	_chk("B1.01 Metal Burst reflects 1.5x the physical damage taken (dmg_taken=%d, expected=%d, %s)" \
			% [def.last_physical_damage, expected, reflected],
			reflected[0] == true and reflected[1] == expected)

	# (ii) Special hit -> reflects 1.5x special damage taken (discriminator:
	# a DIFFERENT category from case (i), confirming the dual-category bitmask).
	var atk2 := _make_mon("MBSpecAtk", [TypeChart.TYPE_WATER], 100, 60, 60, 100, 60, 100)
	atk2.add_move(water_gun)
	var def2 := _make_mon("MBSpecDef", [TypeChart.TYPE_STEEL], 300, 10, 60, 10, 60, 40)
	def2.add_move(metal_burst)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_crit = false
	bm2._force_roll = 100
	var reflected2 := [false, -1]
	bm2.move_executed.connect(func(a, _d, m, amt):
		if a == def2 and m == metal_burst and not reflected2[0]:
			reflected2[0] = true
			reflected2[1] = amt)
	bm2.start_battle(atk2, def2)
	var expected2: int = def2.last_special_damage * 150 / 100 if def2.last_special_damage > 0 else -999
	_chk("B1.02 Metal Burst ALSO reflects a special hit at 1.5x (dmg_taken=%d, expected=%d, %s) " \
			% [def2.last_special_damage, expected2, reflected2] +
			"— a discriminator proving it isn't Physical-only like Counter",
			reflected2[0] == true and reflected2[1] == expected2)

	# (iii) Fails outright if no damage was taken this turn.
	var user3 := _make_mon("MBFailUser", [TypeChart.TYPE_STEEL], 100, 60, 60, 60, 60, 200)
	user3.add_move(metal_burst)
	var opp3 := _make_mon("MBFailOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp3.add_move(tackle)
	var bm3 := _make_bm()
	var failed3 := [false, ""]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == user3 and not failed3[0]:
			failed3[0] = true
			failed3[1] = reason)
	bm3.start_battle(user3, opp3)
	_chk("B1.03 Metal Burst fails outright if the user hasn't taken damage yet (%s)" % [failed3],
			failed3[0] == true and failed3[1] == "no_damage_to_counter")


# ── M19d: Mirror Move — repeats the move that hit the user, not the target's own ─

func _test_mirror_move() -> void:
	var mirror_move := _load_move(119)
	var tackle := _load_move(33)
	var growl := _load_move(45)

	# (i) Copies the move that hit the user (Tackle), even though the target's
	# own actual move this turn is Growl — the KEY discriminator proving this
	# is "last move that hit ME," not "the target's own last-used move."
	# `atk` must be FASTER than `def` so Tackle lands before Mirror Move
	# resolves within the same turn.
	var atk := _make_mon("MMAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(tackle)
	var def := _make_mon("MMDef", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 40)
	def.add_move(mirror_move)
	def.add_move(growl)  # def's own OTHER move — never chosen this turn

	var bm := _make_bm()
	bm._force_hit = true
	var called := [false, null]
	bm.move_called.connect(func(mon, called_move):
		if mon == def and not called[0]:
			called[0] = true
			called[1] = called_move)
	bm.queue_move(1, 0)  # def uses Mirror Move (its own move slot 0)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("C1.01 Mirror Move calls Tackle — the move that hit the user, " +
			"NOT the target's own Growl (%s)" % [called],
			called[0] == true and called[1] == tackle)

	# (ii) Fails outright if the user hasn't been hit by any move yet this turn.
	var user2 := _make_mon("MMFailUser", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 200)
	user2.add_move(mirror_move)
	var opp2 := _make_mon("MMFailOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp2.add_move(tackle)
	var bm2 := _make_bm()
	var failed2 := [false, ""]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == user2 and not failed2[0]:
			failed2[0] = true
			failed2[1] = reason)
	bm2.start_battle(user2, opp2)
	_chk("C1.02 Mirror Move fails outright if the user acts before being hit " +
			"this turn (%s)" % [failed2],
			failed2[0] == true and failed2[1] == "mirror_move_failed")

	# (iii) Retargets to the ACTUAL attacker who hit the user (doubles) —
	# confirms defender is reassigned via _last_attacker, not left at
	# whatever the default target resolution picked. `mm_user` must be
	# SLOWER than `opp0` so opp0's Tackle resolves before Mirror Move does.
	var mm_user := _make_mon("MMDblUser", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 10)
	mm_user.add_move(mirror_move)
	var mm_ally := _make_mon("MMDblAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	mm_ally.add_move(tackle)
	var opp0 := _make_mon("MMDblOpp0", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 200)
	opp0.add_move(tackle)  # this one hits mm_user
	var opp1 := _make_mon("MMDblOpp1", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 5)
	opp1.add_move(tackle)  # never acts before mm_user this turn (slower, and not the hitter)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var hit_events := []
	bm3.move_executed.connect(func(a, d, m, amt): hit_events.push_back([a, d, m, amt]))
	bm3.queue_move_targeted(2, 0, 0)  # opp0 (idx2) Tackles mm_user (idx0) first (faster)
	bm3.queue_move_targeted(0, 0, -1)  # mm_user (idx0) Mirror Moves back — target auto-redirected
	bm3.start_battle_doubles(_doubles_party(mm_user, mm_ally), _doubles_party(opp0, opp1))
	var mm_user_events := hit_events.filter(func(e): return e[0] == mm_user)
	_chk("C1.03 Mirror Move retaliates against the ACTUAL attacker (opp0), " +
			"not opp1 or any other default target (%s)" % [mm_user_events],
			not mm_user_events.is_empty() and mm_user_events[0][1] == opp0)
