extends Node

# Integration test suite: final gate before M15.
# Each test exercises a cross-milestone combination that no single prior suite
# ever hit together. Tests are self-contained; all RNG is deterministically pinned.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_i1_doubles_intimidate_mid_switch()
	_test_i2_weather_spread_damage()
	_test_i3_sitrus_berry_fires_once()
	_test_i4_burn_confusion_switch()
	_test_i5_static_contact()
	_test_i6_ai_switch_decision()
	print("Integration tests: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)


# ── factory helpers ──────────────────────────────────────────────────────────

func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _make_mon(mon_name: String, type1: int,
		base_hp: int = 100, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name    = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, mtype: int, cat: int, power: int,
		se: int = MoveData.SE_NONE, makes_contact: bool = false,
		is_spread: bool = false) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = mtype
	m.category         = cat
	m.power            = power
	m.accuracy         = 100
	m.secondary_effect = se
	m.makes_contact    = makes_contact
	m.is_spread        = is_spread
	return m


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_sitrus() -> ItemData:
	var item := ItemData.new()
	item.hold_effect       = ItemManager.HOLD_EFFECT_RESTORE_PCT_HP
	item.hold_effect_param = 25
	return item


func _singles_party_bench(mon: BattlePokemon, bench: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members.append(mon)
	p.members.append(bench)
	return p


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members.append(m0)
	p.members.append(m1)
	p.active_indices.append(1)
	return p


func _doubles_party_bench(m0: BattlePokemon, m1: BattlePokemon,
		bench: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members.append(m0)
	p.members.append(m1)
	p.members.append(bench)
	p.active_indices.append(1)
	return p


# ── I1 — Doubles: Intimidate fires for both live opponents on mid-battle switch-in ─

func _test_i1_doubles_intimidate_mid_switch() -> void:
	# Setup: INTIM starts on the bench.  Turn 1: player's A1 (combatant 1) switches to INTIM.
	# Intimidate fires mid-turn → both B0 and B1 must receive ATK -1.
	# This is distinct from D7 (Intimidate at battle start) — here no Intimidate fires at
	# BATTLE_START (A0 and A1 have no ability).
	# Post-faint stat_stages check: _clear_volatiles (called on faint) does NOT clear stat_stages,
	# so B0.stat_stages[ATK] == -1 persists even after B0 faints from A0's tackle.
	#
	# Damage verification (roll=100 not pinned here; OHKO range confirmed below):
	#   A0 base_atk=200 → atk=205.  B0/B1 base_def=80 → def=85.  Tackle power=40, Normal/Normal.
	#   base = 40*205*22/85/50+2 = 44.  STAB: _uq412(44,6144) = (270336+2047)/4096 = 66.
	#   B0/B1 base_hp=1 → max_hp=61.  66 > 61 → OHKO regardless of roll (even roll=85 → 55 < 61? No:
	#   roll=85: 44*85/100=37, STAB: (37*6144+2047)/4096=55.  55 < 61 → NOT an OHKO at worst roll!
	#   Use _force_roll=100 to guarantee OHKO every turn.

	var tackle := _load_move(33)
	var intim_ab := _load_ability(22)

	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, 200, 200, 80, 80, 80, 100)
	a0.add_move(tackle)
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, 100, 80, 80, 80, 80, 60)
	# A1 switches out in turn 1 before any move; no move needed.
	var intim := _make_mon("INTIM", TypeChart.TYPE_NORMAL, 100, 80, 80, 80, 80, 45)
	intim.ability = intim_ab
	intim.add_move(tackle)

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, 1, 80, 80, 80, 80, 40)
	b0.add_move(tackle)
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, 1, 80, 80, 80, 80, 20)
	b1.add_move(tackle)

	var atk_drops := {}
	var intim_fires := [0]

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm.stat_stage_changed.connect(func(t, si, ac):
		if si == BattlePokemon.STAGE_ATK and ac < 0:
			atk_drops[t] = atk_drops.get(t, 0) + ac)
	bm.ability_triggered.connect(func(_p, ek):
		if ek == "intimidate":
			intim_fires[0] += 1)

	# Turn 1: A1 (combatant index 1) switches to party slot 2 (INTIM).
	# A0 auto-selects tackle on default target B0 (OHKO). B0/B1 auto-select tackle on A0.
	bm.queue_switch_for(1, 2)
	bm.start_battle_doubles(
		_doubles_party_bench(a0, a1, intim),
		_doubles_party(b0, b1))

	_chk("I1.01 Intimidate mid-switch: stat_stage_changed fired for B0 (ATK -1)",
			atk_drops.get(b0, 0) == -1)
	_chk("I1.02 Intimidate mid-switch: stat_stage_changed fired for B1 (ATK -1)",
			atk_drops.get(b1, 0) == -1)
	_chk("I1.03 Intimidate mid-switch: B0.stat_stages[ATK]==-1 after faint",
			b0.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	_chk("I1.04 Intimidate mid-switch: B1.stat_stages[ATK]==-1",
			b1.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	_chk("I1.05 Intimidate mid-switch: ability_triggered(\"intimidate\") fired exactly once",
			intim_fires[0] == 1)
	bm.queue_free()


# ── I2 — Weather + spread: rain boosts both spread targets independently ─────────

func _test_i2_weather_spread_damage() -> void:
	# Confirms that:
	#  (a) rain boosts the Water spread move,
	#  (b) each target is hit independently (same damage to both), and
	#  (c) the damage exceeds the no-rain expected value (46).
	#
	# Damage pipeline (roll=100, no crit, WEATHER_RAIN, spread × 2 live targets):
	#   A0 base_spatk=80 → spatk=85.  B0/B1 base_spdef=80 → spdef=85.  Power=90, Water/Special.
	#   base = 90*85*22/85/50+2 = 90*22/50+2 = 1980/50+2 = 41   (atk=spdef → cancel)
	#   spread ×0.75: _uq412(41,3072) = (125952+2047)/4096 = 31
	#   rain  ×1.5:   _uq412(31,6144) = (190464+2047)/4096 = 46
	#   roll=100:     46
	#   STAB  ×1.5:   _uq412(46,6144) = (282624+2047)/4096 = 69
	#   type_eff 1.0× (Water vs Normal): 69 per target.
	#   No-rain (skip step 3): spread→31, roll→31, STAB→(31*6144+2047)/4096=46.  46 < 69. ✓

	var water_spread := _make_move(
		"WaterSpread", TypeChart.TYPE_WATER, 1, 90,
		MoveData.SE_NONE, false, true)
	var tackle := _load_move(33)

	var a0 := _make_mon("A0", TypeChart.TYPE_WATER, 200, 80, 80, 80, 80, 100)
	a0.add_move(water_spread)
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, 200, 80, 80, 80, 80, 60)
	a1.add_move(tackle)

	# B0/B1: base_hp=20 → max_hp=80.  69 spread damage leaves 11 HP each.
	# Turn 2: A0 (spread, now only 1 live target → no reduction) OHKOs remaining target.
	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, 20, 80, 80, 80, 80, 40)
	b0.add_move(tackle)
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, 20, 80, 80, 80, 80, 20)
	b1.add_move(tackle)

	# Capture only the first hit from A0 on each target (turn-1 spread).
	var b0_dmg := [0]
	var b1_dmg := [0]

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm.weather = BattleManager.WEATHER_RAIN
	bm.weather_duration = 5
	bm.move_executed.connect(func(att, def, _mv, dmg):
		if att == a0:
			if def == b0 and b0_dmg[0] == 0:
				b0_dmg[0] = dmg
			elif def == b1 and b1_dmg[0] == 0:
				b1_dmg[0] = dmg)

	bm.start_battle_doubles(
		_doubles_party(a0, a1),
		_doubles_party(b0, b1))

	_chk("I2.01 Weather+spread: B0 takes exactly 69 damage (rain+spread+STAB)",
			b0_dmg[0] == 69)
	_chk("I2.02 Weather+spread: B1 takes exactly 69 damage (independent target)",
			b1_dmg[0] == 69)
	_chk("I2.03 Weather+spread: damage (69) > no-rain equivalent (46)",
			b0_dmg[0] > 46)
	_chk("I2.04 Weather+spread: both targets take equal damage",
			b0_dmg[0] == b1_dmg[0])
	bm.queue_free()


# ── I3 — Sitrus Berry fires exactly once across a multi-turn doubles battle ───────

func _test_i3_sitrus_berry_fires_once() -> void:
	# B0 holds Sitrus Berry.  A0 (high attack) deals 66 per turn to B0.
	# A1 (very low attack) deals 6 per turn to B0.
	# Combined: 72 HP per turn.
	#
	# B0 max_hp = base_hp 100 → 160.  Berry threshold = 80.  Heal = 160*25/100 = 40.
	#   Turn 1: HP=160-66=94 (after A0), -6=88 (after A1).  88 > 80 → no berry.
	#   Turn 2: HP=88-66=22 ≤ 80 → BERRY FIRES after A0's hit.  HP=22+40=62.
	#           Then A1 hits: HP=62-6=56.  held_item=null → no second fire.
	#   Turn 3: HP=56-66 → 0.  B0 faints.  No re-trigger (item gone).
	#
	# A0 base_atk=200 → atk=205.  B0 base_def=80 → def=85.  Tackle power=40.
	#   base=40*205*22/85/50+2=44.  STAB: _uq412(44,6144)=66. ✓
	# A1 base_atk=5   → atk=10.   Same def.
	#   base=40*10*22/85/50+2=4.   STAB: _uq412(4,6144)=6.   ✓

	var tackle := _load_move(33)

	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, 200, 200, 80, 80, 80, 100)
	a0.add_move(tackle)
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, 200, 5, 80, 80, 80, 60)
	a1.add_move(tackle)

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, 100, 80, 80, 80, 80, 40)
	b0.held_item = _make_sitrus()
	b0.add_move(tackle)
	# B1: high defense so it survives many hits; no item.
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, 20, 5, 200, 80, 80, 20)
	b1.add_move(tackle)

	var consume_count := [0]
	var heal_count    := [0]
	var heal_amount   := [0]

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm.item_consumed.connect(func(m, _i):
		if m == b0:
			consume_count[0] += 1)
	bm.item_healed.connect(func(m, amount):
		if m == b0:
			heal_count[0] += 1
			heal_amount[0] = amount)

	bm.start_battle_doubles(
		_doubles_party(a0, a1),
		_doubles_party(b0, b1))

	_chk("I3.01 Sitrus Berry: item_consumed fired exactly once", consume_count[0] == 1)
	_chk("I3.02 Sitrus Berry: item_healed fired exactly once",   heal_count[0] == 1)
	_chk("I3.03 Sitrus Berry: heal amount = 40 (max_hp*25/100 = 160*25/100)",
			heal_amount[0] == 40)
	_chk("I3.04 Sitrus Berry: B0.held_item == null after consumption",
			b0.held_item == null)
	bm.queue_free()


# ── I4 — Burn + confusion: non-volatile status persists; volatile + stat stage clear ──

func _test_i4_burn_confusion_switch() -> void:
	# Player's mon1 has burn (non-volatile) + confusion_turns=4 (volatile) + stat_stages[ATK]=+2.
	# On voluntary switch-out, _switch_out_clear fires:
	#   - clears confusion_turns → 0
	#   - resets stat_stages → all 0
	#   - does NOT clear status → burn persists
	# mon2 has high attack to end the battle quickly.
	#
	# opp base_hp=5 → max_hp=65.  mon2 base_atk=200 → atk=205.  opp base_def=80 → def=85.
	#   base=40*205*22/85/50+2=44.  STAB: _uq412(44,6144)=66.  66 > 65 → OHKO on turn 2.

	var tackle := _load_move(33)

	var mon1 := _make_mon("Mon1", TypeChart.TYPE_NORMAL, 100, 80, 80, 80, 80, 100)
	mon1.status         = BattlePokemon.STATUS_BURN
	mon1.confusion_turns = 4
	mon1.stat_stages[BattlePokemon.STAGE_ATK] = 2
	mon1.add_move(tackle)

	var mon2 := _make_mon("Mon2", TypeChart.TYPE_NORMAL, 200, 200, 80, 80, 80, 200)
	mon2.add_move(tackle)

	var opp := _make_mon("Opp", TypeChart.TYPE_NORMAL, 5, 80, 80, 80, 80, 50)
	opp.add_move(tackle)

	var switched_out := [false]
	var switched_in  := [false]

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm.pokemon_switched_out.connect(func(p, s):
		if p == mon1 and s == 0:
			switched_out[0] = true)
	bm.pokemon_switched_in.connect(func(p, s, _sl):
		if p == mon2 and s == 0:
			switched_in[0] = true)

	# Turn 1: mon1 (combatant 0) voluntarily switches to party slot 1 (mon2).
	bm.queue_switch_for(0, 1)
	bm.start_battle_with_parties(
		_singles_party_bench(mon1, mon2),
		BattleParty.single(opp))

	_chk("I4.01 Switch: pokemon_switched_out(mon1, side=0) fired", switched_out[0])
	_chk("I4.02 Switch: pokemon_switched_in(mon2, side=0) fired", switched_in[0])
	_chk("I4.03 Switch: mon1.status == STATUS_BURN (non-volatile persists)",
			mon1.status == BattlePokemon.STATUS_BURN)
	_chk("I4.04 Switch: mon1.confusion_turns == 0 (volatile cleared by _switch_out_clear)",
			mon1.confusion_turns == 0)
	_chk("I4.05 Switch: mon1.stat_stages[ATK] == 0 (stat stages reset by _switch_out_clear)",
			mon1.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	bm.queue_free()


# ── I5 — Contact ability (Static) triggers through full BattleManager turn ────────

func _test_i5_static_contact() -> void:
	# Attacker uses Tackle (makes_contact=true) on defender with Static.
	# bm._force_contact_roll=true guarantees Static fires (30% → forced).
	# bm._force_hit=true guarantees the move connects.
	#
	# Expected after the turn:
	#   secondary_applied(attacker, SE_PARALYSIS) — contact status applied to attacker
	#   ability_triggered(defender, "static")     — ability name confirmed
	#   attacker.status == STATUS_PARALYSIS
	#
	# Defender base_hp=1 → max_hp=61.  Attacker atk=205, def=85 → damage=66 > 61 → OHKO.
	# Static fires inside _do_damaging_hit BEFORE the faint check — paralysis is applied
	# even though the defender's HP drops to 0 on the same hit.

	var tackle := _load_move(33)
	var static_ab := _load_ability(9)

	var attacker := _make_mon("Att", TypeChart.TYPE_NORMAL, 200, 200, 80, 80, 80, 100)
	attacker.add_move(tackle)

	var defender := _make_mon("Def", TypeChart.TYPE_NORMAL, 1, 80, 80, 80, 80, 40)
	defender.ability = static_ab
	defender.add_move(tackle)

	var secondary_fired := [false]
	var ability_fired   := [false]

	var bm := _make_bm()
	bm._force_roll          = 100
	bm._force_crit          = false
	bm._force_hit           = true
	bm._force_contact_roll  = true
	bm.secondary_applied.connect(func(mon, eff):
		if mon == attacker and eff == MoveData.SE_PARALYSIS:
			secondary_fired[0] = true)
	bm.ability_triggered.connect(func(mon, key):
		if mon == defender and key == "static":
			ability_fired[0] = true)

	bm.start_battle(attacker, defender)

	_chk("I5.01 Static contact: secondary_applied(attacker, SE_PARALYSIS) fired",
			secondary_fired[0])
	_chk("I5.02 Static contact: ability_triggered(defender, \"static\") fired",
			ability_fired[0])
	_chk("I5.03 Static contact: attacker.status == STATUS_PARALYSIS",
			attacker.status == BattlePokemon.STATUS_PARALYSIS)
	bm.queue_free()


# ── I6 — AI switch decision: ShouldSwitchIfHasBadOdds through full BM turn ────────

func _test_i6_ai_switch_decision() -> void:
	# SMART AI on side 1.  ai_water is active; player would OHKO it.
	# ShouldSwitchIfHasBadOdds conditions (all satisfied):
	#   _can_defender_ko_attacker: player atk=805, ai_water def=45 → 474 ≥ 220. ✓
	#   _has_super_effective_move: Water vs Normal = 1.0× → no SE move. ✓
	#   ai_water.current_hp >= max_hp/2: 220 ≥ 110. ✓
	#   _roll_switch_decision: _force_switch_rng=1 → always switch. ✓
	# AI switches to ai_backup (slot 1).  Player's tackle hits ai_backup → OHKO.
	# Replacement: ai_water comes back (only non-fainted bench member).
	# Turn 2: player OHKOs ai_water → battle ends.
	#
	# Damage (ai_backup/ai_water both max_hp=220; player atk=805):
	#   vs ai_water  (def=45): base=316, STAB=474.  474 > 220 → OHKO. ✓
	#   vs ai_backup (def=85): base=168, STAB=252.  252 > 220 → OHKO. ✓
	#
	# Assertions: AI switch signals fired, battle ended (not just a stuck BM).

	var tackle := _load_move(33)
	var water_gun  := _make_move("WaterGun",  TypeChart.TYPE_WATER, 1, 40)
	var grass_move := _make_move("GrassMove", TypeChart.TYPE_GRASS, 1, 45)

	# Player: very high attack to guarantee OHKO in AI damage estimate.
	var player := _make_mon("Player", TypeChart.TYPE_NORMAL, 200, 800, 80, 80, 80, 200)
	player.add_move(tackle)

	var ai_water  := _make_mon("AIWater",  TypeChart.TYPE_WATER,  160, 80, 40, 80, 80, 50)
	ai_water.add_move(water_gun)
	var ai_backup := _make_mon("AIBackup", TypeChart.TYPE_GRASS,  160, 80, 80, 80, 80, 40)
	ai_backup.add_move(grass_move)

	var switch_out_events: Array = []
	var switch_in_events:  Array = []
	var battle_over := [false]

	var ai := TrainerAI.new()
	ai.tier             = TrainerAI.Tier.SMART
	ai._force_switch_rng = 1    # forces ShouldSwitchIfHasBadOdds to switch
	ai._force_roll       = 100
	ai._force_crit       = false

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	bm.set_trainer_ai(1, ai)
	bm.pokemon_switched_out.connect(func(p, s):
		switch_out_events.push_back([p, s]))
	bm.pokemon_switched_in.connect(func(p, s, sl):
		switch_in_events.push_back([p, s, sl]))
	bm.battle_ended.connect(func(_w):
		battle_over[0] = true)

	var opp_party := BattleParty.new()
	opp_party.members.append(ai_water)
	opp_party.members.append(ai_backup)

	bm.start_battle_with_parties(
		BattleParty.single(player),
		opp_party)

	# AI switched ai_water → ai_backup; events must include these on side 1.
	var found_water_out := false
	for ev in switch_out_events:
		if ev[0] == ai_water and ev[1] == 1:
			found_water_out = true

	var found_backup_in := false
	for ev in switch_in_events:
		if ev[0] == ai_backup and ev[1] == 1 and ev[2] == 1:
			found_backup_in = true

	_chk("I6.01 AI switch: pokemon_switched_out(ai_water, side=1) fired", found_water_out)
	_chk("I6.02 AI switch: pokemon_switched_in(ai_backup, side=1, slot=1) fired",
			found_backup_in)
	_chk("I6.03 AI switch: battle_ended fired (battle ran to completion)",
			battle_over[0])
	bm.queue_free()
