extends Node

# M18q test suite — Self-heal-on-action items (Big Root, Shell Bell)
#
# Ground truth: pokeemerald-expansion
#   include/constants/items.h -- ITEM_BIG_ROOT=491, ITEM_SHELL_BELL=473.
#   src/battle_util.c :: GetDrainedBigRootHp (L1735-1743) -- shared by TWO
#     source families: move-based drain (SetHealScript, the SAME chokepoint
#     this project's move.drain_percent/Liquid-Ooze mechanism already
#     occupies) AND Ingrain/Leech Seed/Strength Sap/Aqua Ring (a separate
#     volatile-status family, confirmed absent from this project entirely via
#     grep). Big Root's real scope here is move-drain only. Source's own
#     formula is DELIBERATELY NOT UQ4.12: `hp = (hp * 1300) / 1000` -- plain
#     integer math, unlike nearly every other item modifier in this project.
#     Applied BEFORE the Liquid Ooze branch (GetDrainedBigRootHp is called
#     unconditionally, first, inside SetHealScript) -- a Liquid-Ooze-inverted
#     hit against a Big Root holder's own drain move is ALSO boosted, since
#     the multiply happens before the invert/heal split.
#   src/battle_hold_effects.c :: TryShellBell (L524-541) -- reads
#     gBattleScripting.savedDmg, set in MoveEndSetValues, the VERY FIRST
#     moveend state, running immediately after damage is applied -- confirming
#     this is unambiguously the FINAL damage (post-crit, post-type-
#     effectiveness, post-item/ability boosts). Gated on NOT already at max
#     HP (no waste-heal). Fires on ANY nonzero damage regardless of mechanism
#     (fixed/level damage included -- no move-category gate).
#   NOT modeled, flagged not built (both genuine doubles-only edge cases, same
#   class as [M18n]'s own flagged Red Card doubles gap): (1) source excludes
#   Shell Bell healing if the attacker was JUST forced to switch out by Red
#   Card earlier in the same hit resolution; (2) source's savedDmg accumulates
#   across ALL targets of a spread move before healing once, this project's
#   per-target dispatch would heal once per target in a hypothetical doubles
#   spread-move scenario.
#
# Docs: docs/m18_subtier_plan.md (M18q section) -- 2 items, no cross-tier
# dependencies, genuinely unrelated mechanics sharing this tier only for
# scheduling efficiency. New ItemManager.big_root_drain_heal()/
# shell_bell_heal(); Big Root wired into the existing move.drain_percent
# block in _do_damaging_hit (battle_manager.gd); Shell Bell is a new hook
# placed right after it, attacker-keyed like Life Orb recoil/drain heal.
#
# Sections: Q01 Big Root (incl. a discriminator against a non-holder and the
# Liquid Ooze boosted-inversion finding), Q02 Shell Bell (incl. a crit +
# super-effective scenario to prove it reads FINAL damage, a missed-attempt
# discriminator, and the not-already-at-max-HP gate).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_q01_big_root()
	_test_q02_shell_bell()

	var total := _pass + _fail
	print("m18q_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18o_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── Q01: Big Root (491) ──────────────────────────────────────────────────────────
func _test_q01_big_root() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_BIG_ROOT, 30)
	_chk("Q01.01 Big Root hold_effect == HOLD_EFFECT_BIG_ROOT(58), param == 30",
			item.hold_effect == ItemManager.HOLD_EFFECT_BIG_ROOT and item.hold_effect_param == 30)

	var holder := _make_mon("Q01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("Q01.02 direct: a 100 HP base heal becomes 130 with Big Root " +
			"(source's own (hp*1300)/1000, NOT UQ4.12)",
			ItemManager.big_root_drain_heal(holder, 100) == 130)
	var bare := _make_mon("Q01_Bare", TypeChart.TYPE_NORMAL)
	_chk("Q01.03 discriminator: no Big Root -> heal unchanged",
			ItemManager.big_root_drain_heal(bare, 100) == 100)

	var absorb := _load_move(71)  # power 20, drain_percent 50

	# Full-battle: attacker WITH Big Root -- capture the ACTUAL final damage
	# dealt via move_executed, then confirm the observed drain heal matches
	# damage*50/100*1300/1000 exactly (not a hand-derived damage figure).
	var atk1 := _make_mon("Q01_Atk1", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 100)
	atk1.held_item = item
	atk1.add_move(absorb)
	var def1 := _make_mon("Q01_Def1", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 20)
	def1.add_move(absorb)

	var dealt1 := []
	var healed1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, d, m, dmg): dealt1.push_back(dmg))
	bm1.drain_heal.connect(func(m, amt): healed1.push_back(amt))
	bm1.start_battle_with_parties(BattleParty.single(atk1), BattleParty.single(def1))
	_chk("Q01.04 fixture check: at least one hit landed",
			not dealt1.is_empty() and dealt1[0] > 0)
	var expected_heal1: int = (dealt1[0] * 50 / 100) * 1300 / 1000
	_chk("Q01.05 full-battle: Big Root's drain heal matches the exact source " +
			"formula applied to the FINAL dealt damage (observed=%d, expected=%d)" %
					[healed1[0] if not healed1.is_empty() else -1, expected_heal1],
			not healed1.is_empty() and healed1[0] == expected_heal1)
	bm1.queue_free()

	# Discriminator: attacker WITHOUT Big Root gets the base (unboosted) heal.
	var atk2 := _make_mon("Q01_Atk2", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 100)
	atk2.add_move(absorb)
	var def2 := _make_mon("Q01_Def2", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 20)
	def2.add_move(absorb)

	var dealt2 := []
	var healed2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, d, m, dmg): dealt2.push_back(dmg))
	bm2.drain_heal.connect(func(m, amt): healed2.push_back(amt))
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(def2))
	var expected_heal2: int = dealt2[0] * 50 / 100
	_chk("Q01.06 discriminator: no Big Root -> the base (unboosted) heal amount " +
			"(observed=%d, expected=%d)" % [healed2[0] if not healed2.is_empty() else -1, expected_heal2],
			not healed2.is_empty() and healed2[0] == expected_heal2)
	bm2.queue_free()

	# Liquid Ooze interaction: Big Root's boost is applied BEFORE the invert
	# branch, so the damage reflected back at the attacker (via Liquid Ooze)
	# is ALSO boosted -- confirmed from source's exact ordering.
	var liquid_ooze := _load_ability(64)
	var atk3 := _make_mon("Q01_Atk3", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 100)
	atk3.held_item = item
	atk3.add_move(absorb)
	var def3 := _make_mon("Q01_Def3", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 20)
	def3.ability = liquid_ooze
	def3.add_move(absorb)

	var dealt3 := []
	var recoil3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a, d, m, dmg): dealt3.push_back(dmg))
	bm3.recoil_damage.connect(func(m, amt): recoil3.push_back(amt))
	bm3.start_battle_with_parties(BattleParty.single(atk3), BattleParty.single(def3))
	var expected_recoil3: int = (dealt3[0] * 50 / 100) * 1300 / 1000
	_chk("Q01.07 Liquid Ooze interaction: the INVERTED damage against the Big " +
			"Root holder is ALSO boosted (source applies Big Root before the " +
			"invert/heal split), observed=%d, expected=%d" %
					[recoil3[0] if not recoil3.is_empty() else -1, expected_recoil3],
			not recoil3.is_empty() and recoil3[0] == expected_recoil3)
	bm3.queue_free()


# ── Q02: Shell Bell (473) ────────────────────────────────────────────────────────
func _test_q02_shell_bell() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SHELL_BELL, 8)
	_chk("Q02.01 Shell Bell hold_effect == HOLD_EFFECT_SHELL_BELL(44), param == 8",
			item.hold_effect == ItemManager.HOLD_EFFECT_SHELL_BELL and item.hold_effect_param == 8)

	var holder := _make_mon("Q02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	holder.current_hp = 50
	holder.max_hp = 100
	_chk("Q02.02 direct: 80 final damage -> heals 10 (80/8)",
			ItemManager.shell_bell_heal(holder, 80) == 10)
	var bare := _make_mon("Q02_Bare", TypeChart.TYPE_NORMAL)
	bare.current_hp = 50
	bare.max_hp = 100
	_chk("Q02.03 discriminator: no Shell Bell -> 0",
			ItemManager.shell_bell_heal(bare, 80) == 0)
	var full_hp_holder := _make_mon("Q02_FullHp", TypeChart.TYPE_NORMAL)
	full_hp_holder.held_item = item
	_chk("Q02.04 direct: already at max HP -> 0, even with damage dealt " +
			"(no-waste-heal gate)",
			ItemManager.shell_bell_heal(full_hp_holder, 80) == 0)

	var water_gun := _load_move(55)  # Water/Special/40 power, no secondary effect

	# Full-battle: attacker holds Shell Bell, hits a Fire-type target (2x type
	# effectiveness) with a forced CRIT -- two independent damage modifiers
	# stacked -- to prove the heal reads the FINAL dealt damage, not base power.
	var atk1 := _make_mon("Q02_Atk1", TypeChart.TYPE_WATER, 100, 60, 60, 60, 60, 100)
	atk1.held_item = item
	atk1.current_hp = 50  # not at max HP, so the heal is actually observable
	atk1.add_move(water_gun)
	var def1 := _make_mon("Q02_Def1", TypeChart.TYPE_FIRE, 200, 60, 60, 60, 60, 20)
	def1.add_move(water_gun)

	var dealt1 := []
	var healed1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_roll = 100
	bm1._force_crit = true
	bm1.move_executed.connect(func(a, d, m, dmg): dealt1.push_back(dmg))
	bm1.item_healed.connect(func(m, amt): healed1.push_back(amt))
	bm1.start_battle_with_parties(BattleParty.single(atk1), BattleParty.single(def1))
	_chk("Q02.05 fixture check: the hit landed with a crit against a 2x-weak " +
			"target (multiple damage modifiers stacked)",
			not dealt1.is_empty() and dealt1[0] > 0)
	var expected_heal1: int = dealt1[0] / 8
	_chk("Q02.06 CORRECTION-confirming: Shell Bell heals based on the FINAL " +
			"(post-crit, post-type-effectiveness) damage, not base power " +
			"(observed damage=%d, observed heal=%d, expected heal=%d)" %
					[dealt1[0], healed1[0] if not healed1.is_empty() else -1, expected_heal1],
			not healed1.is_empty() and healed1[0] == expected_heal1)
	bm1.queue_free()

	# Discriminator: a miss deals 0 damage -> no heal at all.
	var atk2 := _make_mon("Q02_Atk2", TypeChart.TYPE_WATER, 100, 60, 60, 60, 60, 100)
	atk2.held_item = item
	atk2.current_hp = 50
	atk2.add_move(water_gun)
	var def2 := _make_mon("Q02_Def2", TypeChart.TYPE_FIRE, 200, 60, 60, 60, 60, 20)
	def2.add_move(water_gun)

	var healed2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = false
	bm2.item_healed.connect(func(m, amt): healed2.push_back(amt))
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(def2))
	_chk("Q02.07 discriminator: a missed attempt (0 damage) never triggers a heal",
			healed2.is_empty())
	bm2.queue_free()

	# Discriminator: the holder is already at max HP -> no heal despite dealing
	# real damage (the no-waste-heal gate, newly added by this tier). def3 is
	# deliberately fragile (base_hp=1) so atk3's very first hit ends the battle
	# outright -- avoiding the whole-battle-aggregation pitfall (CLAUDE.md):
	# a longer battle would let def3 counter-attack and dent atk3's HP on a
	# LATER turn, at which point Shell Bell WOULD legitimately fire, making
	# an aggregate "no heal anywhere in the battle" check meaningless.
	var atk3 := _make_mon("Q02_Atk3", TypeChart.TYPE_WATER, 100, 255, 60, 60, 60, 100)
	atk3.held_item = item  # left at full HP deliberately
	atk3.add_move(water_gun)
	var def3 := _make_mon("Q02_Def3", TypeChart.TYPE_FIRE, 1, 60, 1, 60, 60, 20)
	def3.add_move(water_gun)

	var healed3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_hit = true
	# [M18.5a] def3's max HP (61, from the HP formula's +level+10 floor — base_hp=1
	# alone can't push it lower) is NOT reliably one-shot by a non-crit hit at forced
	# max roll (56 damage observed) -- def3 was surviving to counter-attack, denting
	# atk3 below max HP, so atk3's FOLLOW-UP kill legitimately (and correctly) healed
	# via Shell Bell. Forcing crit too (1.5x -> 84 damage, exceeding def3's 61 max HP)
	# guarantees the genuine one-hit kill this discriminator's own comment already
	# claimed, mirroring Q02.05/06's identical forced-roll+forced-crit pattern above
	# and this project's established pairwise-RNG-forcing convention (CLAUDE.md).
	bm3._force_crit = true
	bm3.item_healed.connect(func(m, amt): healed3.push_back(amt))
	bm3.start_battle_with_parties(BattleParty.single(atk3), BattleParty.single(def3))
	_chk("Q02.08 fixture check: def3 fainted from the very first hit (one-turn " +
			"battle, no counter-attack turn to confound the discriminator)",
			def3.fainted)
	_chk("Q02.09 discriminator: the holder is already at max HP -> no heal, " +
			"despite dealing real damage",
			healed3.is_empty())
	bm3.queue_free()
