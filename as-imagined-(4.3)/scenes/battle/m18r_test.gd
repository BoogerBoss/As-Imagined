extends Node

# M18r test suite — Standalone reuses (7 items, 7 different existing mechanisms)
#
# Grouped for scheduling convenience only (per docs/m18_subtier_plan.md's own
# framing) — NOT because the items share a shape. Each section below tests ONE
# item against the SPECIFIC existing mechanism it reuses, plus a discriminator
# proving it's a genuine modifier on that mechanism, not a coincidentally-
# similar separate implementation. See docs/decisions.md's [M18r] entry for the
# full Step 0 audit, including two real corrections found there (Black Sludge's
# damage side is maxHP/8 not maxHP/16; Room Service fires on Trick Room being
# SET as well as on switch-in, not switch-in only).
#
# Sections:
#   R01 Power Herb   — skips a two-turn move's charge turn once (M6 reuse)
#   R02 Light Clay   — Reflect/Light Screen/Aurora Veil timer 5->8 (M16c reuse)
#   R03 Black Sludge — Leftovers-shape variant, pure function calls (no battle)
#   R04 Blunder Policy — +2 Speed on a genuine (non-OHKO) miss (move_missed reuse)
#   R05 Room Service — -1 Speed on Trick Room set OR switch-in while active
#   R06 Shed Shell   — bypasses ability-based trapping (M17f is_trapped reuse)
#   R07 Safety Goggles — weather-chip immunity + powder-move immunity, pure calls

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_r01_power_herb()
	_test_r02_light_clay()
	_test_r03_black_sludge()
	_test_r04_blunder_policy()
	_test_r05_room_service()
	_test_r06_shed_shell()
	_test_r07_safety_goggles()

	var total := _pass + _fail
	print("m18r_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_tackle(power: int = 40) -> MoveData:
	var m := MoveData.new()
	m.move_name = "Tackle"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 0
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	return m


# ── R01: Power Herb — skips a two-turn move's charge turn once ─────────────────
#
# Source: CancelerCharging's Power Herb branch (battle_move_resolution.c L1778),
# an `else if` checked only after the Solar-Beam-in-sun shortcut already failed.
# Fly (id=19): two_turn=true, semi_inv=ON_AIR, is_solar_beam=false — a non-Solar-
# Beam two-turn move, so this section is isolated from M15's own Solar Beam
# sun-shortcut tests entirely.

func _test_r01_power_herb() -> void:
	var fly := _load_move(19)
	var power_herb := _load_item(480)
	_chk("R01.00 fixtures load", fly != null and power_herb != null)
	if fly == null or power_herb == null:
		return
	_chk("R01.01 fixture check: Fly is two_turn, not solar beam",
			fly.two_turn == true and fly.is_solar_beam == false)

	# Positive: WITH Power Herb, Fly fires immediately on turn 1. p1 is faster
	# (so it acts, and is observed, before fainting) but fragile enough that p2's
	# counter-Tackle ends the battle at the close of turn 1 — Power Herb only
	# skips the charge ONCE, so a later turn 2 use (item already spent) would
	# legitimately charge normally; ending the battle after turn 1 avoids
	# reading that unrelated, later, correct behavior as if it contradicted
	# this turn's skip (the whole-battle-aggregation pitfall).
	var p1 := _make_mon("Herbed", [TypeChart.TYPE_FLYING], 20, 80, 1, 80, 80, 200)
	p1.held_item = power_herb
	p1.add_move(fly)
	var p2 := _make_mon("Target", [TypeChart.TYPE_NORMAL], 300, 250, 40, 80, 80, 50)
	p2.add_move(_make_tackle(250))

	var charge_events := []
	var consumed_events := []
	var effect_events := []
	var damage_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.charge_started.connect(func(a, _m): charge_events.push_back(a))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.item_effect_triggered.connect(func(m, key): effect_events.push_back([m, key]))
	bm.move_executed.connect(func(a, _d, _m, dmg): damage_events.push_back([a, dmg]))

	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("R01.02 charge_started never fires for p1's OWN turn-1 use (Power Herb " +
			"skips the charge turn); the battle ends this same turn so there's no " +
			"later, unrelated turn-2 recharge to conflate with this",
			not charge_events.any(func(a): return a == p1))
	_chk("R01.03 item_consumed fires for the holder with Power Herb itself",
			consumed_events.any(func(e): return e[0] == p1 and e[1].item_name == "Power Herb"))
	_chk("R01.04 item_effect_triggered fires with 'power_herb'",
			effect_events.any(func(e): return e[0] == p1 and e[1] == "power_herb"))
	var p1_dmg_events: Array = damage_events.filter(func(e): return e[0] == p1)
	_chk("R01.05 Fly dealt damage on turn 1 (the very first attempt)",
			not p1_dmg_events.is_empty() and p1_dmg_events[0][1] > 0)
	bm.queue_free()

	# Discriminator: WITHOUT Power Herb, the same move takes two turns.
	var p3 := _make_mon("Bare", [TypeChart.TYPE_FLYING], 100, 80)
	p3.add_move(fly)
	var p4 := _make_mon("Target2", [TypeChart.TYPE_NORMAL], 300, 40, 40)
	p4.add_move(_make_tackle(10))

	var charge_events2 := []
	var consumed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.charge_started.connect(func(a, _m): charge_events2.push_back(a))
	bm2.item_consumed.connect(func(m, item): consumed_events2.push_back([m, item]))

	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)

	_chk("R01.06 discriminator: WITHOUT Power Herb, charge_started DOES fire " +
			"(Fly still takes two turns)",
			charge_events2.any(func(a): return a == p3))
	_chk("R01.07 discriminator: nothing was consumed (no item held)",
			consumed_events2.is_empty())
	bm2.queue_free()


# ── R02: Light Clay — Reflect/Light Screen/Aurora Veil: 5 turns -> 8 ───────────
#
# Source: TrySetReflect/TrySetLightScreen (battle_script_commands.c L2088-2127),
# BS_SetAuroraVeil (L13439-13462) — all three checked on the SETTER at set time.
# Captured via the screen_set signal itself (fired synchronously right after the
# turns assignment), NOT a post-battle read of _side_conditions — the turns
# field decrements every end of turn, so a post-battle read would be exactly the
# whole-battle-aggregation pitfall CLAUDE.md documents.

func _test_r02_light_clay() -> void:
	var reflect := _load_move(115)
	var light_screen := _load_move(113)
	var aurora_veil := _load_move(657)
	var light_clay := _load_item(478)
	_chk("R02.00 fixtures load",
			reflect != null and light_screen != null and aurora_veil != null and light_clay != null)
	if reflect == null or light_screen == null or aurora_veil == null or light_clay == null:
		return

	# Reflect, WITH Light Clay -> 8 turns.
	var p1 := _make_mon("Clayed", [TypeChart.TYPE_NORMAL], 100)
	p1.held_item = light_clay
	p1.add_move(reflect)
	var p2 := _make_mon("Foe", [TypeChart.TYPE_NORMAL], 300)
	p2.add_move(_make_tackle(10))

	var captured := {}
	var bm := BattleManager.new()
	add_child(bm)
	bm.screen_set.connect(func(side, kind): captured[kind] = bm._side_conditions[side]["reflect_turns"] \
			if kind == "reflect" else captured.get(kind, -1))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)
	_chk("R02.01 Reflect WITH Light Clay: 8 turns (not 5)", captured.get("reflect", -1) == 8)
	bm.queue_free()

	# Reflect, WITHOUT Light Clay -> 5 turns (discriminator).
	var p3 := _make_mon("Bare", [TypeChart.TYPE_NORMAL], 100)
	p3.add_move(reflect)
	var p4 := _make_mon("Foe2", [TypeChart.TYPE_NORMAL], 300)
	p4.add_move(_make_tackle(10))

	var captured2 := {}
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.screen_set.connect(func(side, kind): captured2[kind] = bm2._side_conditions[side]["reflect_turns"] \
			if kind == "reflect" else captured2.get(kind, -1))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)
	_chk("R02.02 discriminator: Reflect WITHOUT Light Clay: 5 turns", captured2.get("reflect", -1) == 5)
	bm2.queue_free()

	# Light Screen, WITH Light Clay -> 8 turns.
	var p5 := _make_mon("Clayed2", [TypeChart.TYPE_NORMAL], 100)
	p5.held_item = light_clay
	p5.add_move(light_screen)
	var p6 := _make_mon("Foe3", [TypeChart.TYPE_NORMAL], 300)
	p6.add_move(_make_tackle(10))

	var captured3 := {}
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.screen_set.connect(func(side, kind): captured3[kind] = bm3._side_conditions[side]["light_screen_turns"] \
			if kind == "light_screen" else captured3.get(kind, -1))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle(p5, p6)
	_chk("R02.03 Light Screen WITH Light Clay: 8 turns", captured3.get("light_screen", -1) == 8)
	bm3.queue_free()

	# Aurora Veil (requires hail), WITH Light Clay -> 8 turns.
	var p7 := _make_mon("Clayed3", [TypeChart.TYPE_NORMAL], 100)
	p7.held_item = light_clay
	p7.add_move(aurora_veil)
	var p8 := _make_mon("Foe4", [TypeChart.TYPE_NORMAL], 300)
	p8.add_move(_make_tackle(10))

	var captured4 := {}
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.weather = BattleManager.WEATHER_HAIL
	bm4.weather_duration = 0
	bm4.screen_set.connect(func(side, kind): captured4[kind] = bm4._side_conditions[side]["aurora_veil_turns"] \
			if kind == "aurora_veil" else captured4.get(kind, -1))
	bm4.queue_move(0, 0)
	bm4.queue_move(1, 0)
	bm4.start_battle(p7, p8)
	_chk("R02.04 Aurora Veil WITH Light Clay: 8 turns", captured4.get("aurora_veil", -1) == 8)
	bm4.queue_free()


# ── R03: Black Sludge — Leftovers-shape variant ─────────────────────────────────
#
# Source: HOLD_EFFECT_BLACK_SLUDGE dispatch (battle_hold_effects.c L1150-1155):
# Poison-type holder reuses TryLeftovers exactly (maxHP/16 heal). Non-Poison
# holder takes maxHP/8 damage (TryBlackSludgeDamage, L650) — NOT 1/16, a
# correction to this tier's own plan doc. Pure function calls, no battle needed
# (per this tier's preference for function-level testing, [M18-patch-1]'s model).

func _test_r03_black_sludge() -> void:
	var black_sludge := _load_item(487)
	var magic_guard := _load_ability(98)
	_chk("R03.00 fixture loads", black_sludge != null and magic_guard != null)
	if black_sludge == null:
		return

	# Poison-type holder: heals maxHP/16, no damage.
	var poison_holder := _make_mon("Sludged", [TypeChart.TYPE_POISON], 320)
	poison_holder.held_item = black_sludge
	poison_holder.current_hp = 100
	_chk("R03.01 Poison-type holder: heals maxHP/16",
			ItemManager.black_sludge_heal(poison_holder) == poison_holder.max_hp / 16)
	_chk("R03.02 Poison-type holder: no damage function output",
			ItemManager.black_sludge_damage(poison_holder) == 0)

	# Non-Poison holder: damages maxHP/8 (NOT maxHP/16 — the correction).
	var normal_holder := _make_mon("Sludged2", [TypeChart.TYPE_NORMAL], 320)
	normal_holder.held_item = black_sludge
	var dmg: int = ItemManager.black_sludge_damage(normal_holder)
	_chk("R03.03 Non-Poison holder: damages maxHP/8",
			dmg == normal_holder.max_hp / 8)
	_chk("R03.04 CORRECTION-confirming: damage is NOT maxHP/16 (the plan doc's error)",
			dmg != normal_holder.max_hp / 16)
	_chk("R03.05 Non-Poison holder: no heal function output",
			ItemManager.black_sludge_heal(normal_holder) == 0)

	# Magic Guard: blocks the DAMAGE side only (checked at the caller, per this
	# function's own doc comment) — the heal side is entirely unaffected.
	var mg_normal := _make_mon("SludgedMG", [TypeChart.TYPE_NORMAL], 320)
	mg_normal.held_item = black_sludge
	mg_normal.ability = magic_guard
	_chk("R03.06 Magic Guard holder (non-Poison): blocks_indirect_damage is true " +
			"(the caller would skip applying black_sludge_damage's own nonzero output)",
			ItemManager.black_sludge_damage(mg_normal) > 0 and
			AbilityManager.blocks_indirect_damage(mg_normal))

	var mg_poison := _make_mon("SludgedMGPoison", [TypeChart.TYPE_POISON], 320)
	mg_poison.held_item = black_sludge
	mg_poison.ability = magic_guard
	mg_poison.current_hp = 100
	_chk("R03.07 discriminator: Magic Guard does NOT block the HEAL side " +
			"(still heals maxHP/16 regardless of Magic Guard)",
			ItemManager.black_sludge_heal(mg_poison) == mg_poison.max_hp / 16)

	# Already-at-max-HP Poison holder: no heal (gate check, same shape as Leftovers).
	var full_hp_poison := _make_mon("SludgedFull", [TypeChart.TYPE_POISON], 320)
	full_hp_poison.held_item = black_sludge
	_chk("R03.08 Poison-type holder already at max HP: no heal",
			ItemManager.black_sludge_heal(full_hp_poison) == 0)


# ── R04: Blunder Policy — +2 Speed on a genuine (non-OHKO) accuracy miss ───────
#
# Source: TryBlunderPolicy (battle_hold_effects.c L398-414), gated on the
# attacker's own move genuinely missing (move_move_resolution.c L2212-2214's
# `moveEffect != EFFECT_OHKO` exclusion). This project's OHKO-miss path never
# reaches the general move_missed("accuracy") site Blunder Policy is wired to
# (it returns early from its own dedicated block, battle_manager.gd L1098+), so
# the OHKO exclusion is structural here, not a runtime check — tested below by
# confirming an OHKO miss produces NO stat change at all.

func _test_r04_blunder_policy() -> void:
	var tackle := _make_tackle(10)
	var guillotine := _load_move(12)
	var blunder_policy := _load_item(511)
	_chk("R04.00 fixtures load", guillotine != null and blunder_policy != null)
	_chk("R04.00b fixture check: Guillotine is_ohko=true", guillotine.is_ohko == true)

	# Positive: a genuine accuracy miss triggers +2 Speed and consumes the item.
	var p1 := _make_mon("Blundered", [TypeChart.TYPE_NORMAL], 100)
	p1.held_item = blunder_policy
	p1.add_move(tackle)
	var p2 := _make_mon("Foe", [TypeChart.TYPE_NORMAL], 300)
	p2.add_move(_make_tackle(5))

	var stat_events := []
	var consumed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = false
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("R04.01 +2 Speed fires on the holder after its own move misses",
			stat_events.any(func(e): return e[0] == p1 and e[1] == BattlePokemon.STAGE_SPEED and e[2] == 2))
	_chk("R04.02 item_consumed fires for Blunder Policy",
			consumed_events.any(func(e): return e[0] == p1 and e[1].item_name == "Blunder Policy"))
	bm.queue_free()

	# Discriminator: an OHKO move's own miss does NOT trigger Blunder Policy at all.
	# Guillotine's PP is only 5 — once it depletes, p3 falls back to Struggle,
	# whose own miss (NOT OHKO-excluded) WOULD legitimately trigger Blunder
	# Policy several turns later. That's correct behavior, not a violation of
	# THIS test — so the inspection window is bounded to p3's very first action
	# (turn 1) via p3's own event indices, rather than reading "never happens
	# anywhere in the whole battle" (the whole-battle-aggregation pitfall).
	var p3 := _make_mon("BlunderedOHKO", [TypeChart.TYPE_NORMAL], 100)
	p3.held_item = _load_item(511)
	p3.add_move(guillotine)
	var p4 := _make_mon("Foe2", [TypeChart.TYPE_NORMAL], 300)
	p4.add_move(_make_tackle(5))

	var event_log := []  # [tag, mon, ...]
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = false
	bm2.move_missed.connect(func(a, reason): event_log.push_back(["missed", a, reason]))
	bm2.move_executed.connect(func(a, _d, _m, _dmg): event_log.push_back(["executed", a]))
	bm2.stat_stage_changed.connect(func(t, idx, amt): event_log.push_back(["stat", t, idx, amt]))
	bm2.item_consumed.connect(func(m, item): event_log.push_back(["consumed", m, item]))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)

	var p3_action_indices := []
	for i in range(event_log.size()):
		var e = event_log[i]
		if (e[0] == "missed" or e[0] == "executed") and e[1] == p3:
			p3_action_indices.push_back(i)
	_chk("R04.03-setup: p3 acted at least once", not p3_action_indices.is_empty())
	var window_end: int = p3_action_indices[1] if p3_action_indices.size() > 1 else event_log.size()
	var turn1_events: Array = event_log.slice(0, window_end)

	_chk("R04.03 CORRECTION-confirming: an OHKO move's own miss triggers NO " +
			"+2 Speed within its own turn (structural OHKO exclusion)",
			not turn1_events.any(func(e): return e[0] == "stat" and e[1] == p3 \
					and e[2] == BattlePokemon.STAGE_SPEED and e[3] == 2))
	_chk("R04.04 Blunder Policy is never consumed within p3's OHKO-missed turn",
			not turn1_events.any(func(e): return e[0] == "consumed" and e[1] == p3))
	bm2.queue_free()

	# Discriminator: already at +6 Speed -> no consumption (source's CompareStat
	# guard covers the whole trigger, not just the stat-change call).
	var p5 := _make_mon("BlunderedCapped", [TypeChart.TYPE_NORMAL], 100)
	p5.held_item = _load_item(511)
	p5.stat_stages[BattlePokemon.STAGE_SPEED] = 6
	p5.add_move(tackle)
	var p6 := _make_mon("Foe3", [TypeChart.TYPE_NORMAL], 300)
	p6.add_move(_make_tackle(5))

	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = false
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle(p5, p6)

	_chk("R04.05 discriminator: holder already at +6 Speed -> Blunder Policy " +
			"is NOT consumed on a miss",
			not consumed_events3.any(func(e): return e[0] == p5))
	bm3.queue_free()


# ── R05: Room Service — -1 Speed on Trick Room set OR switch-in while active ───
#
# Source: hold_effects.h's HOLD_EFFECT_ROOM_SERVICE entry (.onSwitchIn=TRUE AND
# .onEffect=TRUE) — TWO independent triggers, a correction to this tier's own
# plan doc (which named only switch-in). BattleScript_EffectTrickRoom
# unconditionally loops over every battler on the field right after setroom
# (data/battle_scripts_1.s L1296-1304).

func _test_r05_room_service() -> void:
	var trick_room := _load_move(433)
	var tackle := _make_tackle(10)
	var room_service := _load_item(512)
	_chk("R05.00 fixtures load", trick_room != null and room_service != null)
	_chk("R05.00b fixture check: Trick Room is_trick_room=true", trick_room.is_trick_room == true)

	# Trigger A: Room Service holder is ALREADY on the field when Trick Room is set.
	var p1 := _make_mon("Roomer", [TypeChart.TYPE_PSYCHIC], 100)
	p1.add_move(trick_room)
	var p2 := _make_mon("Serviced", [TypeChart.TYPE_NORMAL], 100)
	p2.held_item = room_service
	p2.add_move(tackle)

	var stat_events := []
	var consumed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("R05.01 Trigger A: -1 Speed fires on the ALREADY-ON-FIELD holder the " +
			"instant Trick Room is set",
			stat_events.any(func(e): return e[0] == p2 and e[1] == BattlePokemon.STAGE_SPEED and e[2] == -1))
	_chk("R05.02 Trigger A: item_consumed fires for Room Service",
			consumed_events.any(func(e): return e[0] == p2 and e[1].item_name == "Room Service"))
	bm.queue_free()

	# Trigger B: Room Service holder switches in while Trick Room is ALREADY active.
	var switcher := _make_mon("Switcher", [TypeChart.TYPE_NORMAL], 100)
	switcher.add_move(tackle)
	var active := _make_mon("Active", [TypeChart.TYPE_NORMAL], 100)
	active.add_move(tackle)
	var bench := _make_mon("Bench", [TypeChart.TYPE_NORMAL], 100)
	bench.held_item = _load_item(512)
	bench.add_move(tackle)

	var opp_party := BattleParty.new()
	opp_party.members = [active, bench]
	opp_party.active_index = 0

	var stat_events2 := []
	var consumed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.trick_room_turns = 5
	bm2.stat_stage_changed.connect(func(t, idx, amt): stat_events2.push_back([t, idx, amt]))
	bm2.item_consumed.connect(func(m, item): consumed_events2.push_back([m, item]))
	bm2.queue_switch(1, 1)
	bm2.start_battle_with_parties(BattleParty.single(switcher), opp_party)

	_chk("R05.03 Trigger B: -1 Speed fires on the Room Service holder switching " +
			"in while Trick Room is already active",
			stat_events2.any(func(e): return e[0] == bench and e[1] == BattlePokemon.STAGE_SPEED and e[2] == -1))
	_chk("R05.04 Trigger B: item_consumed fires for Room Service",
			consumed_events2.any(func(e): return e[0] == bench and e[1].item_name == "Room Service"))
	bm2.queue_free()

	# Discriminator: switching in WITHOUT Trick Room active -> no effect at all.
	var switcher2 := _make_mon("Switcher2", [TypeChart.TYPE_NORMAL], 100)
	switcher2.add_move(tackle)
	var active2 := _make_mon("Active2", [TypeChart.TYPE_NORMAL], 100)
	active2.add_move(tackle)
	var bench2 := _make_mon("Bench2", [TypeChart.TYPE_NORMAL], 100)
	bench2.held_item = _load_item(512)
	bench2.add_move(tackle)

	var opp_party2 := BattleParty.new()
	opp_party2.members = [active2, bench2]
	opp_party2.active_index = 0

	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.queue_switch(1, 1)
	bm3.start_battle_with_parties(BattleParty.single(switcher2), opp_party2)

	_chk("R05.05 discriminator: switching in WITHOUT Trick Room active -> " +
			"Room Service never consumed",
			not consumed_events3.any(func(e): return e[0] == bench2))
	bm3.queue_free()


# ── R06: Shed Shell — bypasses ability-based trapping (voluntary switch only) ──
#
# Source: CanBattlerEscape's HOLD_EFFECT_SHED_SHELL carve-out (battle_main.c
# L4234/4238), checked at the exact call site AbilityManager.is_trapped()
# already occupies ([M17f]'s own established mechanism).

func _test_r06_shed_shell() -> void:
	var tackle := _make_tackle(10)
	var shadow_tag := _load_ability(23)
	var shed_shell := _load_item(490)
	_chk("R06.00 fixtures load", shadow_tag != null and shed_shell != null)

	# Positive: Shed Shell holder trapped by Shadow Tag STILL switches out.
	var trapper := _make_mon("Trapper", [TypeChart.TYPE_NORMAL], 100)
	trapper.ability = shadow_tag
	trapper.add_move(tackle)
	var trapped := _make_mon("Shelled", [TypeChart.TYPE_NORMAL], 100)
	trapped.held_item = shed_shell
	trapped.add_move(tackle)
	var bench := _make_mon("Bench", [TypeChart.TYPE_NORMAL], 100)
	bench.add_move(tackle)

	var opp_party := BattleParty.new()
	opp_party.members = [trapped, bench]
	opp_party.active_index = 0

	var switched_out := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back(p))
	bm.queue_switch(1, 1)
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)

	_chk("R06.01 Shed Shell holder switches out DESPITE Shadow Tag trapping",
			switched_out.any(func(p): return p == trapped))
	bm.queue_free()

	# Discriminator: WITHOUT Shed Shell, the same trapping blocks the switch.
	var trapper2 := _make_mon("Trapper2", [TypeChart.TYPE_NORMAL], 100)
	trapper2.ability = shadow_tag
	trapper2.add_move(tackle)
	var trapped2 := _make_mon("Bare", [TypeChart.TYPE_NORMAL], 100)
	trapped2.add_move(tackle)
	var bench2 := _make_mon("Bench2", [TypeChart.TYPE_NORMAL], 100)
	bench2.add_move(tackle)

	var opp_party2 := BattleParty.new()
	opp_party2.members = [trapped2, bench2]
	opp_party2.active_index = 0

	var switched_out2 := []
	var moves_used2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.pokemon_switched_out.connect(func(p, s): switched_out2.push_back(p))
	bm2.move_executed.connect(func(a, _d, _m, _dmg): moves_used2.push_back(a))
	bm2.queue_switch(1, 1)
	bm2.start_battle_with_parties(BattleParty.single(trapper2), opp_party2)

	_chk("R06.02 discriminator: WITHOUT Shed Shell, the trapped mon never " +
			"switches out",
			not switched_out2.any(func(p): return p == trapped2))
	_chk("R06.03 discriminator: the blocked switch fell back to a move instead",
			moves_used2.any(func(a): return a == trapped2))
	bm2.queue_free()


# ── R07: Safety Goggles — weather-chip immunity + powder-move immunity ─────────
#
# Source: TWO independent exemptions, at the SAME source sites Overcoat/Grass-
# type already occupy: (1) battle_end_turn.c L151/L174, (2) IsAffectedByPowderMove
# (battle_util.c L10545-10552). Pure function calls, no battle needed.

func _test_r07_safety_goggles() -> void:
	var sleep_powder := _load_move(79)
	var safety_goggles := _load_item(504)
	_chk("R07.00 fixtures load", sleep_powder != null and safety_goggles != null)
	_chk("R07.00b fixture check: Sleep Powder powder_move=true", sleep_powder.powder_move == true)

	# Weather-chip half: a non-Rock/Ground/Steel holder is normally chip-vulnerable
	# in sandstorm, but immune while holding Safety Goggles.
	var bm := BattleManager.new()
	add_child(bm)
	var vulnerable := _make_mon("Vulnerable", [TypeChart.TYPE_NORMAL], 100)
	_chk("R07.01 sanity: a plain Normal-type is NOT immune to sandstorm chip",
			not bm._is_weather_damage_immune(vulnerable, BattleManager.WEATHER_SANDSTORM, false))
	var goggled := _make_mon("Goggled", [TypeChart.TYPE_NORMAL], 100)
	goggled.held_item = safety_goggles
	_chk("R07.02 Safety Goggles holder IS immune to sandstorm chip",
			bm._is_weather_damage_immune(goggled, BattleManager.WEATHER_SANDSTORM, false))
	var goggled_hail := _make_mon("GoggledHail", [TypeChart.TYPE_NORMAL], 100)
	goggled_hail.held_item = safety_goggles
	_chk("R07.03 Safety Goggles holder IS also immune to hail chip",
			bm._is_weather_damage_immune(goggled_hail, BattleManager.WEATHER_HAIL, false))
	bm.queue_free()

	# Powder-move half: a non-Grass, non-Overcoat defender is normally hittable by
	# a powder move, but immune while holding Safety Goggles.
	var vulnerable_defender := _make_mon("VulnDef", [TypeChart.TYPE_NORMAL], 100)
	_chk("R07.04 sanity: a plain Normal-type defender is NOT immune to a powder move",
			not AbilityManager.blocks_move_flag(vulnerable_defender, sleep_powder, false, null))
	var goggled_defender := _make_mon("GoggledDef", [TypeChart.TYPE_NORMAL], 100)
	goggled_defender.held_item = safety_goggles
	_chk("R07.05 Safety Goggles defender IS immune to a powder move",
			AbilityManager.blocks_move_flag(goggled_defender, sleep_powder, false, null))
	# Discriminator: Safety Goggles does NOT block a non-powder move.
	var goggled_defender2 := _make_mon("GoggledDef2", [TypeChart.TYPE_NORMAL], 100)
	goggled_defender2.held_item = safety_goggles
	_chk("R07.06 discriminator: Safety Goggles does NOT block a non-powder move",
			not AbilityManager.blocks_move_flag(goggled_defender2, _make_tackle(10), false, null))
