extends Node

# [M19-secondary-stat-on-hit] Unlocks the 79 EFFECT_HIT moves whose secondary
# stat-change payload previously had nowhere to attach (Bug Buzz, Focus Blast,
# Iron Tail, Shadow Ball, Crunch, Moonblast, Psychic, Mud-Slap, Rock Tomb, and
# 70 more), per [M19-bucket2]'s finding #3.
#
# Step 0 re-verified everything from scratch rather than trusting
# [M19-bucket2]'s own numbers:
#   - Move list: an independent re-derivation from moves_info.h (brace-matched
#     block-scoping, distinct-nonzero-subfield counting per CLAUDE.md's
#     convention) found 92 EFFECT_HIT + MOVE_EFFECT_STAT_PLUS/MINUS entries,
#     10 genuinely multi-stat (Bucket 3, excluded), leaving 82 single-stat;
#     minus Triple Arrows(771)/Make It Rain(802) (each need a separate
#     mechanism) and Bleakwind Storm(774) (double-blocked — ALSO needs the
#     still-unbuilt weather-conditional-accuracy mechanism, so it stays
#     excluded from THIS tier even though its stat-on-hit half is now
#     unblocked) = exactly 79. Cross-checked byte-for-byte against a raw
#     extraction saved earlier in the same investigation (91 raw entries,
#     9 multi-stat there — Clangorous Soulblaze, a Z-move-exclusive with no
#     resolvable numeric ID, wasn't caught by that earlier pass at all) —
#     zero ID differences after accounting for that one extra multi-stat
#     catch. **This 79 is the correct, final count — Bleakwind Storm is
#     already excluded from it, not "79 minus Bleakwind Storm = 78."** An
#     earlier restatement of this figure during scoping said "78 (79 minus
#     Bleakwind Storm)"; that arithmetic was wrong, corrected here after two
#     independent re-derivations agreed exactly. See docs/decisions.md's
#     [M19-secondary-stat-on-hit] entry for the full reconciliation.
#   - Gap mechanism reproduced independently (branch-condition tracing):
#     stat_change_stat is read only inside battle_manager.gd's `else` branch
#     of `if move.power > 0:` — physically unreachable for any move with
#     power > 0, i.e. every one of these 79.
#   - Self-targeted fraction: 24/79 (30%), not "almost certainly foe-only" as
#     first assumed — the existing stat_change_self field already generalizes
#     correctly, no schema change needed.
#   - Magnitude spread: NOT uniformly ±1 — 10 moves are ±2. Of those, 7 are
#     self-targeted and guaranteed (Overheat/Draco Meteor/Leaf Storm/Psycho
#     Boost/Fleur Cannon spAtk-2, Diamond Storm +2 Def, Spin Out -2 Speed);
#     the other 3 (Seed Flare/Acid Spray/Lumina Crash, all Sp.Def-2) are
#     foe-targeted and probabilistic.
#   - Guaranteed-vs-explicit-100 distinction: 10 moves (Ice Hammer, Clanging
#     Scales, Fleur Cannon, Zippy Zap, Spin Out, Overheat, Psycho Boost,
#     Hammer Arm, Draco Meteor, Leaf Storm — all self-targeted post-hit drops)
#     OMIT the .chance field in source entirely, encoded here as
#     secondary_chance=0 (this project's "guaranteed, skip roll, EXEMPT from
#     Shield Dust/Sheer Force/Serene Grace" convention) rather than 100 — the
#     other 69 have an EXPLICIT .chance and are encoded with their real value,
#     remaining subject to those gates like any other true secondary effect.
#     This matches real game behavior: Overheat/Draco Meteor/Leaf Storm/
#     Psycho Boost's self stat-drop is NOT affected by Sheer Force.
#
# Design: StatusManager.try_secondary_effect's existing gating (chance-roll,
# Serene Grace, Shield Dust, Covert Cloak, Sheer Force — all keyed generically
# on is_true_secondary = secondary_chance > 0) is extended with one new
# escape hatch (move.secondary_effect == SE_NONE and move.stat_change_stat >=
# 0) that returns true/false exactly like the pre-existing SE_FLINCH case —
# the actual stage math is applied by the CALLER. BattleManager gained a new
# _apply_stat_change_effect(attacker, defender, move, ng_active) — extracted
# from the pre-existing pure-status-move EFFECT_STAT_CHANGE dispatch so this
# new damage-move call site reuses the exact same Mirror Armor redirect /
# Defiant-Competitive / Opportunist / Mirror Herb logic rather than
# re-deriving it. Two guard clauses needed updating (battle_manager.gd's
# caller-side `if damage > 0 and (secondary_effect != SE_NONE or
# stat_change_stat >= 0):`, plus status_manager.gd's own internal early
# return) since these moves have secondary_effect == SE_NONE by construction.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h. All
# power/accuracy/pp/type/chance/amount values reflect GEN_LATEST config
# (every ternary resolved to its highest-gen branch, verified against the
# actual comparison operator per move, not assumed).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_functional()

	var total := _pass + _fail
	print("m19_secondary_stat_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data-integrity table (all 79 moves) ───────────────────────────
# [id, name, type, category, power, accuracy, pp, stat_stage, amount, self, chance, flag_tokens]

func _test_data_integrity() -> void:
	var expected := [
		[51, "Acid", TypeChart.TYPE_POISON, 1, 40, 100, 30, BattlePokemon.STAGE_SPDEF, -1, false, 10, ["spread"]],
		[61, "Bubble Beam", TypeChart.TYPE_WATER, 1, 65, 100, 20, BattlePokemon.STAGE_SPEED, -1, false, 10, []],
		[62, "Aurora Beam", TypeChart.TYPE_ICE, 1, 65, 100, 20, BattlePokemon.STAGE_ATK, -1, false, 10, []],
		[94, "Psychic", TypeChart.TYPE_PSYCHIC, 1, 90, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 10, []],
		[132, "Constrict", TypeChart.TYPE_NORMAL, 0, 10, 100, 35, BattlePokemon.STAGE_SPEED, -1, false, 10, ["contact"]],
		[145, "Bubble", TypeChart.TYPE_WATER, 1, 40, 100, 30, BattlePokemon.STAGE_SPEED, -1, false, 10, ["spread"]],
		[189, "Mud-Slap", TypeChart.TYPE_GROUND, 1, 20, 100, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 100, []],
		[190, "Octazooka", TypeChart.TYPE_WATER, 1, 65, 85, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 50, ["ballistic"]],
		[196, "Icy Wind", TypeChart.TYPE_ICE, 1, 55, 95, 15, BattlePokemon.STAGE_SPEED, -1, false, 100, ["spread"]],
		[211, "Steel Wing", TypeChart.TYPE_STEEL, 0, 70, 90, 25, BattlePokemon.STAGE_DEF, 1, true, 10, ["contact"]],
		[231, "Iron Tail", TypeChart.TYPE_STEEL, 0, 100, 75, 15, BattlePokemon.STAGE_DEF, -1, false, 30, ["contact"]],
		[232, "Metal Claw", TypeChart.TYPE_STEEL, 0, 50, 95, 35, BattlePokemon.STAGE_ATK, 1, true, 10, ["contact"]],
		[242, "Crunch", TypeChart.TYPE_DARK, 0, 80, 100, 15, BattlePokemon.STAGE_DEF, -1, false, 20, ["contact", "biting"]],
		[247, "Shadow Ball", TypeChart.TYPE_GHOST, 1, 80, 100, 15, BattlePokemon.STAGE_SPDEF, -1, false, 20, ["ballistic"]],
		[249, "Rock Smash", TypeChart.TYPE_FIGHTING, 0, 40, 100, 15, BattlePokemon.STAGE_DEF, -1, false, 50, ["contact"]],
		# [M21.5 Bucket 2] power corrected 9->95: both rows had the same
		# transcription typo (a dropped trailing digit) as the underlying
		# data itself, so this table was silently validating the wrong
		# value all along -- source's own `(B_UPDATED_MOVE_DATA >= GEN_9)
		# ? 95 : 70` resolves to 95 at this project's GEN_LATEST=GEN_9 config.
		[295, "Luster Purge", TypeChart.TYPE_PSYCHIC, 1, 95, 100, 5, BattlePokemon.STAGE_SPDEF, -1, false, 50, []],
		[296, "Mist Ball", TypeChart.TYPE_PSYCHIC, 1, 95, 100, 5, BattlePokemon.STAGE_SPATK, -1, false, 50, ["ballistic"]],
		[306, "Crush Claw", TypeChart.TYPE_NORMAL, 0, 75, 95, 10, BattlePokemon.STAGE_DEF, -1, false, 50, ["contact"]],
		[309, "Meteor Mash", TypeChart.TYPE_STEEL, 0, 90, 90, 10, BattlePokemon.STAGE_ATK, 1, true, 20, ["contact", "punching"]],
		[315, "Overheat", TypeChart.TYPE_FIRE, 1, 130, 90, 5, BattlePokemon.STAGE_SPATK, -2, true, 0, []],
		[317, "Rock Tomb", TypeChart.TYPE_ROCK, 0, 60, 95, 15, BattlePokemon.STAGE_SPEED, -1, false, 100, []],
		[330, "Muddy Water", TypeChart.TYPE_WATER, 1, 90, 85, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 30, ["spread"]],
		[341, "Mud Shot", TypeChart.TYPE_GROUND, 1, 55, 95, 15, BattlePokemon.STAGE_SPEED, -1, false, 100, []],
		[354, "Psycho Boost", TypeChart.TYPE_PSYCHIC, 1, 140, 90, 5, BattlePokemon.STAGE_SPATK, -2, true, 0, []],
		[359, "Hammer Arm", TypeChart.TYPE_FIGHTING, 0, 100, 90, 10, BattlePokemon.STAGE_SPEED, -1, true, 0, ["contact", "punching"]],
		[405, "Bug Buzz", TypeChart.TYPE_BUG, 1, 90, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 10, ["sound"]],
		[411, "Focus Blast", TypeChart.TYPE_FIGHTING, 1, 120, 70, 5, BattlePokemon.STAGE_SPDEF, -1, false, 10, ["ballistic"]],
		[412, "Energy Ball", TypeChart.TYPE_GRASS, 1, 90, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 10, ["ballistic"]],
		[414, "Earth Power", TypeChart.TYPE_GROUND, 1, 90, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 10, []],
		[426, "Mud Bomb", TypeChart.TYPE_GROUND, 1, 65, 85, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 30, ["ballistic"]],
		[429, "Mirror Shot", TypeChart.TYPE_STEEL, 1, 65, 85, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 30, []],
		[430, "Flash Cannon", TypeChart.TYPE_STEEL, 1, 80, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 10, []],
		[434, "Draco Meteor", TypeChart.TYPE_DRAGON, 1, 130, 90, 5, BattlePokemon.STAGE_SPATK, -2, true, 0, []],
		[437, "Leaf Storm", TypeChart.TYPE_GRASS, 1, 130, 90, 5, BattlePokemon.STAGE_SPATK, -2, true, 0, []],
		[451, "Charge Beam", TypeChart.TYPE_ELECTRIC, 1, 50, 90, 10, BattlePokemon.STAGE_SPATK, 1, true, 70, []],
		[465, "Seed Flare", TypeChart.TYPE_GRASS, 1, 120, 85, 5, BattlePokemon.STAGE_SPDEF, -2, false, 40, []],
		[488, "Flame Charge", TypeChart.TYPE_FIRE, 0, 50, 100, 20, BattlePokemon.STAGE_SPEED, 1, true, 100, ["contact"]],
		[490, "Low Sweep", TypeChart.TYPE_FIGHTING, 0, 65, 100, 20, BattlePokemon.STAGE_SPEED, -1, false, 100, ["contact"]],
		[491, "Acid Spray", TypeChart.TYPE_POISON, 1, 40, 100, 20, BattlePokemon.STAGE_SPDEF, -2, false, 100, ["ballistic"]],
		[522, "Struggle Bug", TypeChart.TYPE_BUG, 1, 50, 100, 20, BattlePokemon.STAGE_SPATK, -1, false, 100, ["spread"]],
		[527, "Electroweb", TypeChart.TYPE_ELECTRIC, 1, 55, 95, 15, BattlePokemon.STAGE_SPEED, -1, false, 100, ["spread"]],
		[534, "Razor Shell", TypeChart.TYPE_WATER, 0, 75, 95, 10, BattlePokemon.STAGE_DEF, -1, false, 50, ["contact", "slicing"]],
		[536, "Leaf Tornado", TypeChart.TYPE_GRASS, 1, 65, 90, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 50, []],
		[539, "Night Daze", TypeChart.TYPE_DARK, 1, 85, 95, 10, BattlePokemon.STAGE_ACCURACY, -1, false, 40, []],
		[549, "Glaciate", TypeChart.TYPE_ICE, 1, 65, 95, 10, BattlePokemon.STAGE_SPEED, -1, false, 100, ["spread"]],
		[552, "Fiery Dance", TypeChart.TYPE_FIRE, 1, 80, 100, 10, BattlePokemon.STAGE_SPATK, 1, true, 50, []],
		[555, "Snarl", TypeChart.TYPE_DARK, 1, 55, 95, 15, BattlePokemon.STAGE_SPATK, -1, false, 100, ["sound", "spread"]],
		[583, "Play Rough", TypeChart.TYPE_FAIRY, 0, 90, 90, 10, BattlePokemon.STAGE_ATK, -1, false, 10, ["contact"]],
		[585, "Moonblast", TypeChart.TYPE_FAIRY, 1, 95, 100, 15, BattlePokemon.STAGE_SPATK, -1, false, 30, []],
		[591, "Diamond Storm", TypeChart.TYPE_ROCK, 0, 100, 95, 5, BattlePokemon.STAGE_DEF, 2, true, 50, ["spread"]],
		[595, "Mystical Fire", TypeChart.TYPE_FIRE, 1, 75, 100, 10, BattlePokemon.STAGE_SPATK, -1, false, 100, []],
		[612, "Power-Up Punch", TypeChart.TYPE_FIGHTING, 0, 40, 100, 20, BattlePokemon.STAGE_ATK, 1, true, 100, ["contact", "punching"]],
		[628, "Ice Hammer", TypeChart.TYPE_ICE, 0, 100, 90, 10, BattlePokemon.STAGE_SPEED, -1, true, 0, ["contact", "punching"]],
		[642, "Lunge", TypeChart.TYPE_BUG, 0, 80, 100, 15, BattlePokemon.STAGE_ATK, -1, false, 100, ["contact"]],
		[643, "Fire Lash", TypeChart.TYPE_FIRE, 0, 80, 100, 15, BattlePokemon.STAGE_DEF, -1, false, 100, ["contact"]],
		[651, "Trop Kick", TypeChart.TYPE_GRASS, 0, 70, 100, 15, BattlePokemon.STAGE_ATK, -1, false, 100, ["contact"]],
		[654, "Clanging Scales", TypeChart.TYPE_DRAGON, 1, 110, 100, 5, BattlePokemon.STAGE_DEF, -1, true, 0, ["sound", "spread"]],
		[659, "Fleur Cannon", TypeChart.TYPE_FAIRY, 1, 130, 90, 5, BattlePokemon.STAGE_SPATK, -2, true, 0, []],
		[662, "Shadow Bone", TypeChart.TYPE_GHOST, 0, 85, 100, 10, BattlePokemon.STAGE_DEF, -1, false, 20, []],
		[664, "Liquidation", TypeChart.TYPE_WATER, 0, 85, 100, 10, BattlePokemon.STAGE_DEF, -1, false, 20, ["contact"]],
		[676, "Zippy Zap", TypeChart.TYPE_ELECTRIC, 0, 80, 100, 10, BattlePokemon.STAGE_EVASION, 1, true, 0, ["contact", "always_crit", "prio:2"]],
		[706, "Drum Beating", TypeChart.TYPE_GRASS, 0, 80, 100, 10, BattlePokemon.STAGE_SPEED, -1, false, 100, []],
		[712, "Breaking Swipe", TypeChart.TYPE_DRAGON, 0, 60, 100, 15, BattlePokemon.STAGE_ATK, -1, false, 100, ["contact", "spread"]],
		[715, "Apple Acid", TypeChart.TYPE_GRASS, 1, 80, 100, 10, BattlePokemon.STAGE_SPDEF, -1, false, 100, []],
		[717, "Spirit Break", TypeChart.TYPE_FAIRY, 0, 75, 100, 15, BattlePokemon.STAGE_SPATK, -1, false, 100, ["contact"]],
		[734, "Skitter Smack", TypeChart.TYPE_BUG, 0, 70, 90, 10, BattlePokemon.STAGE_SPATK, -1, false, 100, ["contact"]],
		[751, "Thunderous Kick", TypeChart.TYPE_FIGHTING, 0, 90, 100, 10, BattlePokemon.STAGE_DEF, -1, false, 100, ["contact"]],
		[756, "Psyshield Bash", TypeChart.TYPE_PSYCHIC, 0, 70, 90, 10, BattlePokemon.STAGE_DEF, 1, true, 100, ["contact"]],
		[759, "Springtide Storm", TypeChart.TYPE_FAIRY, 1, 100, 80, 5, BattlePokemon.STAGE_ATK, -1, false, 30, ["spread"]],
		[760, "Mystical Power", TypeChart.TYPE_PSYCHIC, 1, 70, 90, 10, BattlePokemon.STAGE_SPATK, 1, true, 100, []],
		[768, "Esper Wing", TypeChart.TYPE_PSYCHIC, 1, 80, 100, 10, BattlePokemon.STAGE_SPEED, 1, true, 100, ["crit:1"]],
		[769, "Bitter Malice", TypeChart.TYPE_GHOST, 1, 75, 100, 15, BattlePokemon.STAGE_ATK, -1, false, 100, []],
		[783, "Lumina Crash", TypeChart.TYPE_PSYCHIC, 1, 80, 100, 10, BattlePokemon.STAGE_SPDEF, -2, false, 100, []],
		[787, "Spin Out", TypeChart.TYPE_STEEL, 0, 100, 100, 5, BattlePokemon.STAGE_SPEED, -2, true, 0, ["contact"]],
		[799, "Torch Song", TypeChart.TYPE_FIRE, 1, 80, 100, 10, BattlePokemon.STAGE_SPATK, 1, true, 100, ["sound"]],
		[800, "Aqua Step", TypeChart.TYPE_WATER, 0, 80, 100, 10, BattlePokemon.STAGE_SPEED, 1, true, 100, ["contact"]],
		[810, "Pounce", TypeChart.TYPE_BUG, 0, 50, 100, 20, BattlePokemon.STAGE_SPEED, -1, false, 100, ["contact"]],
		[811, "Trailblaze", TypeChart.TYPE_GRASS, 0, 50, 100, 20, BattlePokemon.STAGE_SPEED, 1, true, 100, ["contact"]],
		[812, "Chilling Water", TypeChart.TYPE_WATER, 1, 50, 100, 20, BattlePokemon.STAGE_ATK, -1, false, 100, []],
	]

	for e: Array in expected:
		var id: int = e[0]
		var mv := _load_move(id)
		var tag: String = "%d %s" % [id, e[1]]
		_chk(tag + " loads", mv != null)
		if mv == null:
			continue
		_chk(tag + " move_name", mv.move_name == e[1])
		_chk(tag + " type", mv.type == e[2])
		_chk(tag + " category", mv.category == e[3])
		_chk(tag + " power", mv.power == e[4])
		_chk(tag + " accuracy", mv.accuracy == e[5])
		_chk(tag + " pp", mv.pp == e[6])
		_chk(tag + " stat_change_stat", mv.stat_change_stat == e[7])
		_chk(tag + " stat_change_amount", mv.stat_change_amount == e[8])
		_chk(tag + " stat_change_self", mv.stat_change_self == e[9])
		_chk(tag + " secondary_chance", mv.secondary_chance == e[10])
		# every one of these 79 moves must keep secondary_effect == SE_NONE —
		# the whole point of this tier is that the stat payload dispatches
		# WITHOUT a status-style SE_* token.
		_chk(tag + " secondary_effect stays SE_NONE", mv.secondary_effect == MoveData.SE_NONE)

		var tokens: Array = e[11]
		_chk(tag + " makes_contact", mv.makes_contact == ("contact" in tokens))
		_chk(tag + " punching_move", mv.punching_move == ("punching" in tokens))
		_chk(tag + " biting_move", mv.biting_move == ("biting" in tokens))
		_chk(tag + " sound_move", mv.sound_move == ("sound" in tokens))
		_chk(tag + " slicing_move", mv.slicing_move == ("slicing" in tokens))
		_chk(tag + " ballistic_move", mv.ballistic_move == ("ballistic" in tokens))
		_chk(tag + " always_critical_hit", mv.always_critical_hit == ("always_crit" in tokens))
		_chk(tag + " is_spread", mv.is_spread == ("spread" in tokens))
		var expect_crit := 0
		var expect_prio := 0
		for t: String in tokens:
			if t.begins_with("crit:"):
				expect_crit = int(t.split(":")[1])
			elif t.begins_with("prio:"):
				expect_prio = int(t.split(":")[1])
		_chk(tag + " critical_hit_stage", mv.critical_hit_stage == expect_crit)
		_chk(tag + " priority", mv.priority == expect_prio)


# ── Section B: functional checks ──────────────────────────────────────────────

func _test_functional() -> void:
	_test_b1_full_pipeline_fire()
	_test_b2_self_targeting()
	_test_b3_magnitude_negative_two()
	_test_b4_does_not_fire_gate()
	_test_b5_sheer_force_suppresses_and_boosts()
	_test_b6_guaranteed_chance_exempt_from_sheer_force()
	_test_b7_mirror_armor_redirect()
	_test_b8_self_targeted_bypasses_mirror_armor()


# B1: Icy Wind(196, foe, Speed-1, chance=100) — deterministic fire (chance=100
# needs no forcing), primary damage still confirmed nonzero (discriminator:
# secondary firing must never suppress/alter the hit), and stat_stage_changed
# fires on the DEFENDER with the correct stage/amount. Covers the ±1 magnitude
# case.
func _test_b1_full_pipeline_fire() -> void:
	var icy_wind := _load_move(196)
	var tackle := _load_move(33)
	var atk := _make_mon("B1Atk", TypeChart.TYPE_ICE)
	atk.add_move(icy_wind)
	var def := _make_mon("B1Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var stat_events := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, def)

	_chk("B1 Icy Wind deals real nonzero primary damage (secondary firing " +
			"doesn't suppress the hit)", dmg[0] > 0)
	_chk("B1 stat_stage_changed fires on the DEFENDER, Speed, -1 (first event)",
			not stat_events.is_empty() and stat_events[0][0] == def
					and stat_events[0][1] == BattlePokemon.STAGE_SPEED and stat_events[0][2] == -1)


# B2: Flame Charge(488, self, Speed+1, chance=100) — confirms self-targeting
# threads move.stat_change_self correctly: the stat change lands on the
# ATTACKER, not the defender.
func _test_b2_self_targeting() -> void:
	var flame_charge := _load_move(488)
	var tackle := _load_move(33)
	var atk := _make_mon("B2Atk", TypeChart.TYPE_FIRE)
	atk.add_move(flame_charge)
	var def := _make_mon("B2Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, def)

	_chk("B2 Flame Charge (self) raises the ATTACKER's Speed, not the defender's",
			not stat_events.is_empty() and stat_events[0][0] == atk
					and stat_events[0][1] == BattlePokemon.STAGE_SPEED and stat_events[0][2] == 1)
	_chk("B2 the defender is never targeted", not stat_events.any(func(e): return e[0] == def))


# B3: Acid Spray(491, foe, Sp.Def-2, chance=100) — covers the ±2 magnitude case.
func _test_b3_magnitude_negative_two() -> void:
	var acid_spray := _load_move(491)
	var tackle := _load_move(33)
	var atk := _make_mon("B3Atk", TypeChart.TYPE_POISON)
	atk.add_move(acid_spray)
	var def := _make_mon("B3Def", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, def)

	_chk("B3 Acid Spray lowers the defender's Sp.Def by exactly 2 (±2 magnitude case)",
			not stat_events.is_empty() and stat_events[0][0] == def
					and stat_events[0][1] == BattlePokemon.STAGE_SPDEF and stat_events[0][2] == -2)


# B4: Iron Tail(231, foe, Def-1, chance=30) — direct StatusManager.
# try_secondary_effect unit calls (this project's established convention for
# deterministic secondary-chance testing, see stat_test.gd/m17n1_test.gd),
# proving the new stat_change_stat >= 0 escape hatch respects force_secondary
# in both directions exactly like every pre-existing SE_* case.
func _test_b4_does_not_fire_gate() -> void:
	var iron_tail := _load_move(231)
	var atk := _make_mon("B4Atk", TypeChart.TYPE_STEEL)
	var def := _make_mon("B4Def", TypeChart.TYPE_NORMAL)

	_chk("B4 force_secondary=false suppresses the roll (does NOT fire)",
			StatusManager.try_secondary_effect(atk, def, iron_tail, false) == false)
	_chk("B4 force_secondary=true fires the roll (gate passes through for a " +
			"probabilistic stat-change move)",
			StatusManager.try_secondary_effect(atk, def, iron_tail, true) == true)


# B5: Sheer Force suppresses Iron Tail's (chance=30, a true probabilistic
# secondary) stat-change roll AND boosts power — reusing the existing
# is_true_secondary-gated Sheer Force checks in both StatusManager and
# AbilityManager, same precedent as [M17n-5]'s own Sheer Force test.
func _test_b5_sheer_force_suppresses_and_boosts() -> void:
	var iron_tail := _load_move(231)
	var sheer_force := _load_ability(125)
	var sf_atk := _make_mon("B5SFAtk", TypeChart.TYPE_STEEL)
	sf_atk.ability = sheer_force
	var plain_atk := _make_mon("B5PlainAtk", TypeChart.TYPE_STEEL)
	var def := _make_mon("B5Def", TypeChart.TYPE_NORMAL)

	_chk("B5 Sheer Force suppresses Iron Tail's stat-change secondary even " +
			"when force_secondary=true",
			StatusManager.try_secondary_effect(sf_atk, def, iron_tail, true) == false)

	var sf_power := AbilityManager.move_power_modifier_uq412(
			sf_atk, iron_tail, DamageCalculator.WEATHER_NONE)
	var plain_power := AbilityManager.move_power_modifier_uq412(
			plain_atk, iron_tail, DamageCalculator.WEATHER_NONE)
	_chk("B5 Sheer Force boosts Iron Tail's power (secondary_chance=30 qualifies)",
			sf_power > plain_power)


# B6: Overheat(315, self, Sp.Atk-2, chance=0/omitted) is exempt from BOTH
# halves of Sheer Force — proving the guaranteed-vs-explicit-100 encoding
# distinction has real behavioral consequences, matching real game behavior
# (Overheat's own self stat-drop is never affected by Sheer Force).
func _test_b6_guaranteed_chance_exempt_from_sheer_force() -> void:
	var overheat := _load_move(315)
	var sheer_force := _load_ability(125)
	var sf_atk := _make_mon("B6SFAtk", TypeChart.TYPE_FIRE)
	sf_atk.ability = sheer_force
	var plain_atk := _make_mon("B6PlainAtk", TypeChart.TYPE_FIRE)
	var def := _make_mon("B6Def", TypeChart.TYPE_NORMAL)

	_chk("B6 Sheer Force does NOT suppress Overheat's guaranteed self stat-drop",
			StatusManager.try_secondary_effect(sf_atk, def, overheat, null) == true)

	var sf_power := AbilityManager.move_power_modifier_uq412(
			sf_atk, overheat, DamageCalculator.WEATHER_NONE)
	var plain_power := AbilityManager.move_power_modifier_uq412(
			plain_atk, overheat, DamageCalculator.WEATHER_NONE)
	_chk("B6 Sheer Force does NOT boost Overheat's power (secondary_chance=0 " +
			"fails the > 0 qualification, discriminator vs B5)",
			sf_power == plain_power)


# B7: Fire Lash(643, foe, Def-1, chance=100) against a Mirror Armor holder —
# the decrease redirects onto the ATTACKER instead, reusing
# BattleManager._apply_stat_change_effect's shared Mirror Armor logic
# (extracted from the pre-existing pure-status-move dispatch, see
# [M17n-11]'s m17n11_test.gd Section 7 for the original worked example this
# mirrors).
func _test_b7_mirror_armor_redirect() -> void:
	var fire_lash := _load_move(643)
	var tackle := _load_move(33)
	var mirror_armor := _load_ability(240)
	var atk := _make_mon("B7Atk", TypeChart.TYPE_FIRE, 100, 80, 60, 60, 60, 100)
	atk.add_move(fire_lash)
	var holder := _make_mon("B7Holder", TypeChart.TYPE_NORMAL, 100, 80, 60, 60, 60, 20)
	holder.ability = mirror_armor
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	var trig_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.ability_triggered.connect(func(m, tg): trig_events.append([m, tg]))
	bm.start_battle(atk, holder)

	_chk("B7 Fire Lash's Defense drop redirects onto the ATTACKER via Mirror Armor",
			not stat_events.is_empty() and stat_events[0][0] == atk
					and stat_events[0][1] == BattlePokemon.STAGE_DEF and stat_events[0][2] == -1)
	_chk("B7 the Mirror Armor holder's own Defense is never lowered",
			not stat_events.any(func(e): return e[0] == holder))
	_chk("B7 ability_triggered fires with the mirror_armor tag on the holder",
			trig_events.any(func(e): return e[0] == holder and e[1] == "mirror_armor"))


# B8: Overheat(315, self, Sp.Atk-2) used by a PLAIN attacker against a Mirror
# Armor-holding defender — self-targeted drops are never redirected (the
# holder was never the stat_target to begin with), confirming the new call
# site correctly inherits the pre-existing `not move.stat_change_self` gate
# rather than needing its own bespoke self-targeting exemption.
func _test_b8_self_targeted_bypasses_mirror_armor() -> void:
	var overheat := _load_move(315)
	var tackle := _load_move(33)
	var mirror_armor := _load_ability(240)
	var atk := _make_mon("B8Atk", TypeChart.TYPE_FIRE)
	atk.add_move(overheat)
	var holder := _make_mon("B8Holder", TypeChart.TYPE_NORMAL)
	holder.ability = mirror_armor
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(atk, holder)

	_chk("B8 Overheat's self Sp.Atk-2 lands on the ATTACKER even against a " +
			"Mirror Armor holder (self-targeted, never redirected)",
			not stat_events.is_empty() and stat_events[0][0] == atk
					and stat_events[0][1] == BattlePokemon.STAGE_SPATK and stat_events[0][2] == -2)
	_chk("B8 the Mirror Armor holder is never targeted by a self-inflicted drop",
			not stat_events.any(func(e): return e[0] == holder))
