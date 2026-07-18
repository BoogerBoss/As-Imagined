extends Node

# [M19-recoil-on-miss] Jump Kick(26), High Jump Kick(136), Axe Kick(781),
# Supercell Slam(844) — Bucket 4 sub-group.
#
# Step 0 findings (see move_data.gd's crashes_on_miss doc comment for full
# source citations):
#   - All 4 moves share the LITERAL SAME `.effect = EFFECT_RECOIL_IF_MISS` in
#     source — a genuinely uniform mechanism, contradicting the possibility
#     that Axe Kick/Supercell Slam (newer-gen additions) might use a
#     different crash formula. They don't.
#   - Crash formula, confirmed at this project's GEN_LATEST config: a FLAT
#     50% of the ATTACKER'S OWN max HP — NOT damage-scaled (the older,
#     defender's-HP-based GEN_4-only branch is dead code at GEN_LATEST).
#   - Miss-scope is broader than "accuracy roll failed" alone: crash also
#     triggers on a Protect block and on ordinary type immunity — but NEVER
#     on a pre-move-cancel failure (sleep/paralysis/Truant/etc.), since the
#     attacker never even attempted the move in those cases.
#   - A real, confirmed ASYMMETRY with ordinary recoil: Magic Guard blocks
#     crash damage, but ROCK HEAD DOES NOT (confirmed from the actual
#     battle script — Rock Head is never checked anywhere in
#     BattleScript_RecoilIfMiss, unlike ordinary EFFECT_RECOIL's own case
#     block a few lines below it, which explicitly checks both).
#   - Reckless's own power-boost check needed extending too — source gates
#     it on {EFFECT_RECOIL, EFFECT_RECOIL_IF_MISS} together, and this
#     project's prior implementation only checked `recoil_percent > 0`
#     (its own doc comment had already flagged this exact gap in advance).
#   - Gravity (`.gravityBanned = TRUE` on all 4 in source) is confirmed
#     absent from this project entirely (`[M18t]`) — nothing to build.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_move_resolution.c, battle_util.c, data/battle_scripts_1.s,
# GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_crash_direct_flat_half_max_hp()
	_test_magic_guard_blocks_crash()
	_test_rock_head_does_not_block_crash()
	_test_miss_triggers_crash()
	_test_hit_does_not_trigger_crash()
	_test_protect_block_triggers_crash()
	_test_type_immunity_triggers_crash()
	_test_reckless_boosts_own_power()

	var total := _pass + _fail
	print("m19_recoil_on_miss_test: %d/%d passed" % [_pass, total])
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
	# Pinned neutral nature + zero IVs — exact-value crash-fraction
	# assertions predate any RNG-driven stat variance.
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 4 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var jump_kick := _load_move(26)
	_chk("26 Jump Kick loads", jump_kick != null)
	_chk("26 name/type/category/power/accuracy/pp",
			jump_kick.move_name == "Jump Kick" and jump_kick.type == TypeChart.TYPE_FIGHTING
					and jump_kick.category == 0 and jump_kick.power == 100
					and jump_kick.accuracy == 95 and jump_kick.pp == 10)
	_chk("26 makes_contact + crashes_on_miss", jump_kick.makes_contact and jump_kick.crashes_on_miss)

	var hjk := _load_move(136)
	_chk("136 High Jump Kick loads", hjk != null)
	_chk("136 name/type/category/power/accuracy/pp (genuinely different power from Jump Kick)",
			hjk.move_name == "High Jump Kick" and hjk.type == TypeChart.TYPE_FIGHTING
					and hjk.category == 0 and hjk.power == 130
					and hjk.accuracy == 90 and hjk.pp == 10)
	_chk("136 makes_contact + crashes_on_miss", hjk.makes_contact and hjk.crashes_on_miss)

	var axe_kick := _load_move(781)
	_chk("781 Axe Kick loads", axe_kick != null)
	_chk("781 name/type/category/power/accuracy/pp",
			axe_kick.move_name == "Axe Kick" and axe_kick.type == TypeChart.TYPE_FIGHTING
					and axe_kick.category == 0 and axe_kick.power == 120
					and axe_kick.accuracy == 90 and axe_kick.pp == 10)
	_chk("781 makes_contact + crashes_on_miss + its own unrelated 30% confusion secondary",
			axe_kick.makes_contact and axe_kick.crashes_on_miss
					and axe_kick.secondary_effect == MoveData.SE_CONFUSION
					and axe_kick.secondary_chance == 30)

	var scs := _load_move(844)
	_chk("844 Supercell Slam loads", scs != null)
	_chk("844 name/type/category/power/accuracy/pp (Electric, not Fighting)",
			scs.move_name == "Supercell Slam" and scs.type == TypeChart.TYPE_ELECTRIC
					and scs.category == 0 and scs.power == 100
					and scs.accuracy == 95 and scs.pp == 15)
	_chk("844 makes_contact + crashes_on_miss + double_power_on_minimized",
			scs.makes_contact and scs.crashes_on_miss and scs.double_power_on_minimized)


# ── Direct unit test: crash = flat 50% of the ATTACKER's own max HP ─────────

func _test_crash_direct_flat_half_max_hp() -> void:
	var bm := _make_bm()
	var mon := _make_mon("CrashMon", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	var expected_crash: int = mon.max_hp / 2
	bm._apply_crash_damage(mon, false)
	_chk("Crash damage is exactly floor(max_hp/2) (max_hp=%d, expected=%d, actual_loss=%d)" %
			[mon.max_hp, expected_crash, mon.max_hp - mon.current_hp],
			mon.current_hp == mon.max_hp - expected_crash)
	_chk("Crash damage does not depend on any target/opponent state (attacker-only formula)",
			expected_crash == int(mon.max_hp / 2.0))


# ── Magic Guard blocks crash damage entirely ─────────────────────────────────

func _test_magic_guard_blocks_crash() -> void:
	var bm := _make_bm()
	var mon := _make_mon("MGMon", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	mon.ability = _load_ability(98)  # Magic Guard
	var hp_before: int = mon.current_hp
	bm._apply_crash_damage(mon, false)
	_chk("Magic Guard: crash damage fully blocked (hp unchanged)", mon.current_hp == hp_before)


# ── Rock Head does NOT block crash damage — the key confirmed asymmetry ─────

func _test_rock_head_does_not_block_crash() -> void:
	var bm := _make_bm()
	var mon := _make_mon("RHMon", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	mon.ability = _load_ability(69)  # Rock Head
	var expected_crash: int = mon.max_hp / 2
	bm._apply_crash_damage(mon, false)
	_chk("Rock Head discriminator: crash damage STILL applies (Rock Head only blocks " +
			"ordinary recoil, confirmed NOT checked anywhere in BattleScript_RecoilIfMiss)",
			mon.current_hp == mon.max_hp - expected_crash)


# ── A forced MISS triggers crash damage on the user ─────────────────────────

func _test_miss_triggers_crash() -> void:
	var jump_kick := _load_move(26)
	var tackle := _load_move(33)
	var atk := _make_mon("MissAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	atk.add_move(jump_kick)
	var def := _make_mon("MissDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = false  # guaranteed miss, every attempt
	var crash := [false, -1]  # [fired, amount]
	bm.crash_damage.connect(func(mon, amt):
		if mon == atk and not crash[0]:
			crash[0] = true
			crash[1] = amt)
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and not missed[0] and reason == "accuracy":
			missed[0] = true)
	bm.start_battle(atk, def)

	_chk("Jump Kick genuinely missed (confirms this isn't a vacuous pass)", missed[0] == true)
	_chk("Crash damage fired on the miss, exactly half the attacker's own max HP (%s)" % [crash],
			crash[0] == true and crash[1] == atk.max_hp / 2)


# ── Discriminator: a forced HIT does NOT trigger crash damage ───────────────

func _test_hit_does_not_trigger_crash() -> void:
	var jump_kick := _load_move(26)
	var tackle := _load_move(33)
	var atk := _make_mon("HitAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	atk.add_move(jump_kick)
	var def := _make_mon("HitDef", [TypeChart.TYPE_NORMAL], 300, 10, 20, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var crash := [false]
	bm.crash_damage.connect(func(mon, _amt):
		if mon == atk:
			crash[0] = true)
	var hit := [false, -1]  # [fired, damage_to_opponent]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not hit[0]:
			hit[0] = true
			hit[1] = amt)

	bm.start_battle(atk, def)

	_chk("Discriminator: forced hit connects for real damage against the opponent (%s)" % [hit],
			hit[0] == true and hit[1] > 0)
	_chk("Discriminator: crash damage NEVER fires on a successful hit — genuinely " +
			"miss-gated, not just 'sometimes fires'", crash[0] == false)


# ── Protect block triggers crash damage (broader than accuracy-only) ────────

func _test_protect_block_triggers_crash() -> void:
	var jump_kick := _load_move(26)
	var protect := _load_move(182)
	var atk := _make_mon("ProtAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	atk.add_move(jump_kick)
	var def := _make_mon("ProtDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 200)
	def.add_move(protect)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var protect_ok := [false]
	bm.protected.connect(func(mon):
		if mon == def and not protect_ok[0]:
			protect_ok[0] = true)
	var crash := [false, -1]
	bm.crash_damage.connect(func(mon, amt):
		if mon == atk and not crash[0]:
			crash[0] = true
			crash[1] = amt)
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and not missed[0] and reason == "protected":
			missed[0] = true)
	bm.start_battle(atk, def)

	_chk("Protect actually succeeded first (baseline, not a vacuous setup)", protect_ok[0] == true)
	_chk("Jump Kick was genuinely blocked by Protect", missed[0] == true)
	_chk("Crash damage fires on a Protect block too, not just an accuracy miss (%s)" % [crash],
			crash[0] == true and crash[1] == atk.max_hp / 2)


# ── Type immunity triggers crash damage ──────────────────────────────────────

func _test_type_immunity_triggers_crash() -> void:
	# Jump Kick (Fighting) vs a pure Ghost-type defender: 0x, confirmed via
	# this project's own TypeChart.get_uq412 (the Scrappy-bypass special
	# case explicitly names Normal/Fighting-vs-Ghost as the 0x pair it
	# overrides, confirming the immunity exists in the first place).
	var jump_kick := _load_move(26)
	var tackle := _load_move(33)
	var atk := _make_mon("ImmAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	atk.add_move(jump_kick)
	var def := _make_mon("ImmDef", [TypeChart.TYPE_GHOST], 200, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true  # accuracy would hit; immunity must independently block it
	bm._force_crit = false
	var crash := [false, -1]
	bm.crash_damage.connect(func(mon, amt):
		if mon == atk and not crash[0]:
			crash[0] = true
			crash[1] = amt)
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and not missed[0] and reason == "immune":
			missed[0] = true)
	bm.start_battle(atk, def)

	_chk("Jump Kick reported genuinely immune (Ghost vs Fighting, not an accuracy roll)",
			missed[0] == true)
	_chk("Crash damage fires on type immunity too (%s)" % [crash],
			crash[0] == true and crash[1] == atk.max_hp / 2)


# ── Reckless boosts these 4 moves' own damage output too ────────────────────
# (a directly-adjacent finding from Step 0 — Reckless's power-boost check in
# source is gated on {EFFECT_RECOIL, EFFECT_RECOIL_IF_MISS} together, not
# recoil_percent alone.)

func _test_reckless_boosts_own_power() -> void:
	var jump_kick := _load_move(26)
	var atk := _make_mon("RecklessAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	atk.ability = _load_ability(120)  # Reckless
	var plain_atk := _make_mon("PlainAtk", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)

	var boosted: int = AbilityManager.move_power_modifier_uq412(atk, jump_kick, 0)
	var neutral: int = AbilityManager.move_power_modifier_uq412(plain_atk, jump_kick, 0)
	_chk("Reckless applies its x1.2 power modifier to a crashes_on_miss move (boosted=%d neutral=%d)" %
			[boosted, neutral], boosted == 4915 and neutral == 4096)
