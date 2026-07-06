extends Node

# Milestone 3 verification: status conditions.
# Deterministic — all RNG pinned via force parameters.
# Expected values derived by hand from source formulas; derivations in comments.
# Source cross-references in StatusManager and DamageCalculator.
#
# Run: godot --headless --path /path/to/project scenes/battle/status_test.tscn


var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== Milestone 3 Status Conditions Verification ===")
	print("Source: battle_end_turn.c, battle_move_resolution.c, battle_util.c")
	print("")

	# --- Test Pokémon ---
	# Charmander level 50: Fire | Atk=57, Def=43, SpAtk=65, SpDef=55, Speed=65
	var charmander := _make_mon("Charmander", [TypeChart.TYPE_FIRE], 39, 52, 43, 60, 50, 65)

	# Squirtle level 50: Water | Atk=48, Def=65, Speed=43
	var squirtle   := _make_mon("Squirtle",   [TypeChart.TYPE_WATER], 44, 48, 65, 50, 64, 43)

	# Raichu level 50: Electric | Speed=110
	var raichu     := _make_mon("Raichu",     [TypeChart.TYPE_ELECTRIC], 60, 90, 55, 90, 80, 110)

	# Jolteon level 50: Electric | Speed=130
	var jolteon    := _make_mon("Jolteon",    [TypeChart.TYPE_ELECTRIC], 65, 65, 60, 110, 95, 130)

	# Arcanine level 50: Fire | Speed=95
	var arcanine   := _make_mon("Arcanine",   [TypeChart.TYPE_FIRE], 90, 110, 80, 100, 80, 95)

	# Weezing level 50: Poison | Speed=60
	var weezing    := _make_mon("Weezing",    [TypeChart.TYPE_POISON], 65, 90, 120, 85, 70, 60)

	# Steelix level 50: Steel+Ground | Def=200
	var steelix    := _make_mon("Steelix",    [TypeChart.TYPE_STEEL, TypeChart.TYPE_GROUND],
			75, 85, 200, 55, 65, 30)

	# Dewgong level 50: Water+Ice | Speed=70
	var dewgong    := _make_mon("Dewgong",    [TypeChart.TYPE_WATER, TypeChart.TYPE_ICE],
			90, 70, 80, 70, 95, 70)

	# Generic level 50: Normal type for generic tests | maxHP=184, Atk=57, Def=54, Speed=55
	# HP formula: floor((2*45+0+0)*50/100)+50+10 = floor(45)+60 = 105 HP at base_hp=45
	# Atk: floor((2*52)*50/100)+5 = 52+5=57
	# Actually let me use a custom mon with base_hp=60 for round HP numbers:
	# HP: floor((2*60)*50/100)+50+10 = 60+60=120 maxHP
	var normal_mon := _make_mon("Normal",    [TypeChart.TYPE_NORMAL], 60, 52, 43, 60, 50, 65)

	# ─── BURN TESTS ──────────────────────────────────────────────────────────

	# S1: Burn — end-of-turn damage = maxHP / 16
	# Source: battle_end_turn.c :: HandleEndTurnBurn L577
	#   B_BURN_DAMAGE = GEN_LATEST = GEN_7+ → maxHP / 16
	# Use Squirtle (Water type) — Fire types are immune to burn; Water is not.
	# Squirtle level 50, base_hp=44:
	#   HP = floor((2*44)*50/100) + 50 + 10 = 44 + 60 = 104
	#   Burn tick = 104 / 16 = 6 (integer division)
	_check_exact("S1a Burn EOT damage = maxHP/16 (104/16=6)", _burn_tick(squirtle), 6)

	# S1b: apply burn to Squirtle (Water type, not immune), confirm status set
	var sq_burn := _clone(squirtle)
	_check_exact("S1b try_apply_status burn on Water-type succeeds",
			int(StatusManager.try_apply_status(sq_burn, BattlePokemon.STATUS_BURN)), 1)
	_check_exact("S1b status == BURN", sq_burn.status, BattlePokemon.STATUS_BURN)

	# S1c: burn EOT actually reduces HP
	sq_burn.current_hp = sq_burn.max_hp
	var burn_dmg := StatusManager.end_of_turn_damage(sq_burn)
	sq_burn.current_hp -= burn_dmg
	_check_exact("S1c burn EOT dealt 6 damage", burn_dmg, 6)
	_check_exact("S1c HP after burn tick = 104-6=98", sq_burn.current_hp, 98)

	# S1d: burn halves Physical attack damage
	# Source: battle_util.c :: GetBurnOrFrostBiteModifier L7282–7286
	#   Physical move attacker burned → _uq412_half_down(dmg, 2048)
	# Squirtle (burned, Water) uses Tackle (Normal/Physical/35) vs Charmander.
	# Squirtle Atk = floor(2*48*50/100)+5 = 53. Charmander Def = floor(2*43*50/100)+5 = 48.
	# base = 35*53*22 / 48 / 50 + 2 = 1855*22/48/50+2 = 40810/48/50+2 = 850/50+2 = 19
	# Normal vs Fire = 1×, no STAB. roll100 no-burn: 19.
	# roll100 WITH burn: _uq412_half_down(19,2048) = (19*2048+2047)/4096 = 40959/4096 = 9
	var tackle    := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 35)
	var ember     := _make_move("Ember",    TypeChart.TYPE_FIRE,   1, 40)
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER,  1, 40)

	var sq_no_burn  := _clone(squirtle)
	var sq_for_burn := _clone(squirtle)
	StatusManager.try_apply_status(sq_for_burn, BattlePokemon.STATUS_BURN)
	var r_no_burn := DamageCalculator.calculate(sq_no_burn,  charmander, tackle, 100, false)
	var r_burn    := DamageCalculator.calculate(sq_for_burn, charmander, tackle, 100, false)
	_check_exact("S1d Tackle no-burn roll=100 (expect 19)", r_no_burn["damage"], 19)
	_check_exact("S1d Tackle with-burn roll=100 (expect 9 = 19 half-down)", r_burn["damage"], 9)

	# S1e: burn does NOT halve Special moves
	# Squirtle (burned) uses WaterGun (Water/Special/40) vs Charmander (Fire → 2×).
	# SpAtk = floor(2*50*50/100)+5 = 55. Charmander SpDef = floor(2*50*50/100)+5 = 55.
	# base = 40*55*22 / 55 / 50 + 2 = 48400/55/50+2 = 880/50+2 = 19
	# roll100: 19 → STAB (Water): (19*6144+2047)/4096=28 → Water→Fire 2×: (28*8192+2047)/4096=56
	# burn should NOT halve this (Special move) → also 56
	var r_special_no_burn := DamageCalculator.calculate(sq_no_burn,  charmander, water_gun, 100, false)
	var r_special_burn    := DamageCalculator.calculate(sq_for_burn, charmander, water_gun, 100, false)
	_check_exact("S1e WaterGun no-burn roll=100 (expect 56)", r_special_no_burn["damage"], 56)
	_check_exact("S1e WaterGun with-burn roll=100 (expect 56, Special not halved)", r_special_burn["damage"], 56)

	# ─── POISON TESTS ────────────────────────────────────────────────────────

	# S2: Poison — end-of-turn damage = maxHP / 8
	# Source: battle_end_turn.c :: HandleEndTurnPoison L556
	# Squirtle base_hp=44: HP = floor((2*44)*50/100)+50+10 = 44+60 = 104
	# Poison tick = 104 / 8 = 13
	var sq_poison := _clone(squirtle)
	StatusManager.try_apply_status(sq_poison, BattlePokemon.STATUS_POISON)
	_check_exact("S2a try_apply_status poison on Water-type succeeds",
			sq_poison.status, BattlePokemon.STATUS_POISON)
	var psn_dmg := StatusManager.end_of_turn_damage(sq_poison)
	_check_exact("S2b poison EOT = maxHP/8 (104/8=13)", psn_dmg, 13)

	# ─── TOXIC TESTS ─────────────────────────────────────────────────────────

	# S3: Toxic (bad poison) — escalating: (maxHP/16) × counter
	# Source: battle_end_turn.c :: HandleEndTurnPoison L547–550
	# Counter starts at 0; increments to 1 on first EOT tick, then 2, 3, ...
	# maxHP/16 base = 104/16 = 6
	# Turn 1: counter 0→1, damage = 6*1 = 6
	# Turn 2: counter 1→2, damage = 6*2 = 12
	# Turn 3: counter 2→3, damage = 6*3 = 18
	var sq_toxic := _clone(squirtle)
	StatusManager.try_apply_status(sq_toxic, BattlePokemon.STATUS_TOXIC)
	_check_exact("S3a toxic counter starts at 0", sq_toxic.toxic_counter, 0)
	var t1 := StatusManager.end_of_turn_damage(sq_toxic)
	_check_exact("S3b toxic turn 1: counter→1, dmg=6*1=6", t1, 6)
	_check_exact("S3b toxic counter after turn 1", sq_toxic.toxic_counter, 1)
	var t2 := StatusManager.end_of_turn_damage(sq_toxic)
	_check_exact("S3c toxic turn 2: counter→2, dmg=6*2=12", t2, 12)
	var t3 := StatusManager.end_of_turn_damage(sq_toxic)
	_check_exact("S3d toxic turn 3: counter→3, dmg=6*3=18", t3, 18)
	# Counter cap: stays at 15 after 15 increments
	sq_toxic.toxic_counter = 14
	var t15 := StatusManager.end_of_turn_damage(sq_toxic)
	_check_exact("S3e toxic turn 15: counter→15, dmg=6*15=90", t15, 90)
	var t_cap := StatusManager.end_of_turn_damage(sq_toxic)
	_check_exact("S3f toxic counter caps at 15 (stays 15)", sq_toxic.toxic_counter, 15)
	_check_exact("S3f toxic cap turn: dmg=6*15=90 (same)", t_cap, 90)

	# ─── PARALYSIS TESTS ─────────────────────────────────────────────────────

	# S4: Paralysis — speed cut and full-para
	# Source: battle_main.c L4714 — B_PARALYSIS_SPEED >= GEN_7 → speed /= 2
	# Source: battle_move_resolution.c :: CancelerParalyzed L451 — 25% full-para
	# Squirtle speed = floor((2*43)*50/100)+5 = 43+5 = 48
	# After paralysis: 48/2 = 24
	var sq_para := _clone(squirtle)
	StatusManager.try_apply_status(sq_para, BattlePokemon.STATUS_PARALYSIS)
	_check_exact("S4a paralysis applied to Water-type",
			sq_para.status, BattlePokemon.STATUS_PARALYSIS)
	_check_exact("S4b effective_speed normal  (Squirtle=48)",
			StatusManager.effective_speed(squirtle), 48)
	_check_exact("S4c effective_speed paralyzed (48/2=24)",
			StatusManager.effective_speed(sq_para), 24)

	# S4d: forced full-para blocks move
	var para_check_fail := StatusManager.pre_move_check(sq_para, null, null, null, true)
	_check_exact("S4d force full-para: can_move=false",
			int(para_check_fail["can_move"]), 0)

	# S4e: forced no-para can move
	var para_check_pass := StatusManager.pre_move_check(_clone(sq_para), null, null, null, false)
	_check_exact("S4e force no full-para: can_move=true",
			int(para_check_pass["can_move"]), 1)

	# ─── SLEEP TESTS ─────────────────────────────────────────────────────────

	# S5: Sleep — decrements each turn, wakes when counter reaches 0
	# Source: battle_move_resolution.c L130–169
	# B_SLEEP_TURNS = GEN_LATEST = GEN_5+ → 2–4 turns; pin at 3 for testing.
	var sq_sleep := _clone(squirtle)
	StatusManager.try_apply_status(sq_sleep, BattlePokemon.STATUS_SLEEP, 3)
	_check_exact("S5a sleep applied, sleep_turns=3", sq_sleep.sleep_turns, 3)

	# S5b: turn 1 — decrement to 2, still asleep
	var sleep_c1 := StatusManager.pre_move_check(sq_sleep, false)  # force stay asleep
	_check_exact("S5b turn 1: can_move=false (still sleeping)", int(sleep_c1["can_move"]), 0)
	_check_exact("S5b sleep_turns=2 after turn 1", sq_sleep.sleep_turns, 2)

	# S5c: turn 2 — force stay asleep again
	var sleep_c2 := StatusManager.pre_move_check(sq_sleep, false)
	_check_exact("S5c turn 2: can_move=false", int(sleep_c2["can_move"]), 0)
	_check_exact("S5c sleep_turns=1", sq_sleep.sleep_turns, 1)

	# S5d: turn 3 — force wake
	var sleep_c3 := StatusManager.pre_move_check(sq_sleep, true)
	_check_exact("S5d turn 3: woke_up=true", int(sleep_c3["woke_up"]), 1)
	_check_exact("S5d turn 3: can_move=true (moves after waking)", int(sleep_c3["can_move"]), 1)
	_check_exact("S5d status cleared after wake", sq_sleep.status, BattlePokemon.STATUS_NONE)

	# ─── FREEZE TESTS ────────────────────────────────────────────────────────

	# S6: Freeze — 20% thaw chance per turn
	# Source: battle_move_resolution.c L172–186
	# RandomPercentage(RNG_FROZEN, 20) → 20% thaw
	var sq_frozen := _clone(squirtle)
	StatusManager.try_apply_status(sq_frozen, BattlePokemon.STATUS_FREEZE)
	_check_exact("S6a freeze applied", sq_frozen.status, BattlePokemon.STATUS_FREEZE)

	# S6b: force stay frozen
	var freeze_c1 := StatusManager.pre_move_check(sq_frozen, null, false)
	_check_exact("S6b force stay frozen: can_move=false", int(freeze_c1["can_move"]), 0)
	_check_exact("S6b still frozen", sq_frozen.status, BattlePokemon.STATUS_FREEZE)

	# S6c: force thaw
	var freeze_c2 := StatusManager.pre_move_check(sq_frozen, null, true)
	_check_exact("S6c force thaw: thawed=true", int(freeze_c2["thawed"]), 1)
	_check_exact("S6c force thaw: can_move=true", int(freeze_c2["can_move"]), 1)
	_check_exact("S6c status cleared after thaw", sq_frozen.status, BattlePokemon.STATUS_NONE)

	# ─── CONFUSION TESTS ─────────────────────────────────────────────────────

	# S7: Confusion — self-hit and snap-out
	# Source: battle_move_resolution.c :: CancelerConfused L389–430
	# Duration: random 2–5 turns (B_CONFUSION_TURNS=5); pin at 3 for testing.
	# Self-hit chance: 33% (B_CONFUSION_SELF_DMG_CHANCE = GEN_LATEST = GEN_7+)

	# S7a: apply confusion (pin at turns=3)
	var sq_conf := _clone(squirtle)
	StatusManager.try_apply_confusion(sq_conf, 3)
	_check_exact("S7a confusion applied, turns=3", sq_conf.confusion_turns, 3)

	# S7b: turn 1 — decrement 3→2, still confused, force self-hit
	# Squirtle Atk = floor(2*48*50/100)+5 = 53. Def = floor(2*65*50/100)+5 = 70.
	# confusion dmg = 40 * 53 * 22 / 70 / 50 + 2 = 46640/70/50+2 = 666/50+2 = 15
	var conf_c1 := StatusManager.pre_move_check(sq_conf, null, null, true)
	_check_exact("S7b turn 1: self_hit_damage=15 (force)", conf_c1["self_hit_damage"], 15)
	_check_exact("S7b turn 1: can_move=false (self-hit)", int(conf_c1["can_move"]), 0)
	_check_exact("S7b confusion_turns decremented to 2", sq_conf.confusion_turns, 2)

	# S7c: turn 2 — decrement 2→1, still confused, force NO self-hit
	var conf_c2 := StatusManager.pre_move_check(sq_conf, null, null, false)
	_check_exact("S7c turn 2: self_hit_damage=0 (no hit)", conf_c2["self_hit_damage"], 0)
	_check_exact("S7c turn 2: can_move=true (no self-hit)", int(conf_c2["can_move"]), 1)
	_check_exact("S7c confusion_turns=1", sq_conf.confusion_turns, 1)

	# S7d: turn 3 — decrement 1→0, snaps out (can_move=true, snapped_out=true)
	var conf_c3 := StatusManager.pre_move_check(sq_conf)  # no force needed (snap-out is deterministic)
	_check_exact("S7d turn 3: snapped_out=true", int(conf_c3["snapped_out"]), 1)
	_check_exact("S7d turn 3: can_move=true after snap-out", int(conf_c3["can_move"]), 1)
	_check_exact("S7d confusion_turns=0 after snap-out", sq_conf.confusion_turns, 0)

	# S7e: confusion self-hit formula derivation check
	# Source: battle_move_resolution.c L402–413
	# Formula: 40 * atk_staged * (2*level/5+2) / def_staged / 50 + 2
	# Squirtle Atk = floor(2*48*50/100)+5 = 53. Def = floor(2*65*50/100)+5 = 70. Stage 0 → unchanged.
	# dmg = 40 * 53 * 22 / 70 / 50 + 2 = 46640/70/50+2 = 666/50+2 = 13+2 = 15
	_check_exact("S7e confusion dmg formula (Squirtle, expect 15)",
			DamageCalculator.calculate_confusion_damage(squirtle), 15)

	# S7f: confusion damage uses Attack/Defense (Physical stats)
	# Charmander Atk = floor(2*52*50/100)+5 = 57. Def = floor(2*43*50/100)+5 = 48.
	# dmg = 40 * 57 * 22 / 48 / 50 + 2 = 50160/48/50+2 = 1045/50+2 = 20+2 = 22
	_check_exact("S7f confusion dmg Charmander (Atk57/Def48, expect 22)",
			DamageCalculator.calculate_confusion_damage(charmander), 22)

	# ─── TYPE IMMUNITY TESTS ─────────────────────────────────────────────────

	# S8: Type immunities — source: battle_util.c :: CanSetNonVolatileStatus L5235

	# S8a: Fire-type cannot be burned
	var arc_try := _clone(arcanine)
	_check_exact("S8a Fire-type immune to burn",
			int(StatusManager.try_apply_status(arc_try, BattlePokemon.STATUS_BURN)), 0)
	_check_exact("S8a status unchanged", arc_try.status, BattlePokemon.STATUS_NONE)

	# S8b: Poison-type cannot be poisoned
	var weez_try := _clone(weezing)
	_check_exact("S8b Poison-type immune to poison",
			int(StatusManager.try_apply_status(weez_try, BattlePokemon.STATUS_POISON)), 0)

	# S8c: Poison-type cannot be badly poisoned (toxic)
	var weez_tox := _clone(weezing)
	_check_exact("S8c Poison-type immune to toxic",
			int(StatusManager.try_apply_status(weez_tox, BattlePokemon.STATUS_TOXIC)), 0)

	# S8d: Steel-type cannot be poisoned
	var steel_try := _clone(steelix)
	_check_exact("S8d Steel-type immune to poison",
			int(StatusManager.try_apply_status(steel_try, BattlePokemon.STATUS_POISON)), 0)

	# S8e: Electric-type cannot be paralyzed (B_PARALYZE_ELECTRIC = GEN_LATEST = GEN_6+)
	var rai_try := _clone(raichu)
	_check_exact("S8e Electric-type immune to paralysis",
			int(StatusManager.try_apply_status(rai_try, BattlePokemon.STATUS_PARALYSIS)), 0)

	# S8f: Ice-type cannot be frozen
	var dew_try := _clone(dewgong)
	_check_exact("S8f Ice-type immune to freeze",
			int(StatusManager.try_apply_status(dew_try, BattlePokemon.STATUS_FREEZE)), 0)

	# S8g: Water/Ice dual-type immune to freeze (Ice present)
	_check_exact("S8g Water/Ice immune to freeze (Ice present)",
			int(StatusManager.try_apply_status(_clone(dewgong), BattlePokemon.STATUS_FREEZE)), 0)

	# S8h: non-immune types CAN be given status
	_check_exact("S8h Water-type CAN be burned",
			int(StatusManager.try_apply_status(_clone(squirtle), BattlePokemon.STATUS_BURN)), 1)
	_check_exact("S8i Water-type CAN be frozen",
			int(StatusManager.try_apply_status(_clone(squirtle), BattlePokemon.STATUS_FREEZE)), 1)

	# S8i-2: [M17.5 Batch Fix] harsh sunlight prevents freezing entirely (ANY type, not
	# just non-Ice) — source: battle_util.c L5342-5343,
	# `IS_BATTLER_OF_TYPE(battlerDef, TYPE_ICE) || IsBattlerWeatherAffected(...,
	# B_WEATHER_SUN)`. Deferred at this project's original M3 tier with a "weather not
	# in scope" comment that went stale once weather shipped in M11 — closed here.
	_check_exact("S8i-2 Water-type immune to freeze while Sun is active",
			int(StatusManager.try_apply_status(_clone(squirtle), BattlePokemon.STATUS_FREEZE,
					null, null, false, null, DamageCalculator.WEATHER_SUN)), 0)
	_check_exact("S8i-3 Normal-type also immune to freeze in Sun (not an Ice-only carve-out)",
			int(StatusManager.try_apply_status(_clone(normal_mon), BattlePokemon.STATUS_FREEZE,
					null, null, false, null, DamageCalculator.WEATHER_SUN)), 0)
	_check_exact("S8i-4 sun-gate discriminator: Water-type CAN still be frozen in Rain (not sun)",
			int(StatusManager.try_apply_status(_clone(squirtle), BattlePokemon.STATUS_FREEZE,
					null, null, false, null, DamageCalculator.WEATHER_RAIN)), 1)
	_check_exact("S8j Normal-type CAN be paralyzed",
			int(StatusManager.try_apply_status(_clone(normal_mon), BattlePokemon.STATUS_PARALYSIS)), 1)
	_check_exact("S8k Normal-type CAN be poisoned",
			int(StatusManager.try_apply_status(_clone(normal_mon), BattlePokemon.STATUS_POISON)), 1)

	# ─── ONE STATUS AT A TIME ─────────────────────────────────────────────────

	# S9: A Pokémon already having a major status cannot receive another.
	# Source: battle_util.c :: CanSetNonVolatileStatus L5391
	var sq_already_burn := _clone(squirtle)
	StatusManager.try_apply_status(sq_already_burn, BattlePokemon.STATUS_BURN)
	_check_exact("S9a burn on already-burned fails",
			int(StatusManager.try_apply_status(sq_already_burn, BattlePokemon.STATUS_BURN)), 0)
	_check_exact("S9b poison on already-burned fails",
			int(StatusManager.try_apply_status(sq_already_burn, BattlePokemon.STATUS_POISON)), 0)
	_check_exact("S9c paralysis on already-burned fails",
			int(StatusManager.try_apply_status(sq_already_burn, BattlePokemon.STATUS_PARALYSIS)), 0)

	# ─── PARALYSIS SPEED ORDER ───────────────────────────────────────────────

	# S10: Paralyzed Pokémon's effective_speed is halved for turn ordering.
	# Source: battle_main.c L4713–4714
	# Jolteon (Speed=130) vs Raichu (Speed=110) normally: Jolteon first.
	# After Raichu paralyzed: Raichu_eff = 55, Jolteon_eff = 130 → Jolteon still first.
	# After Jolteon paralyzed: Jolteon_eff = 65, Raichu_eff = 110 → Raichu first.
	# Jolteon speed stat: floor((2*130)*50/100)+5 = 130+5=135
	# Raichu speed stat:  floor((2*110)*50/100)+5 = 110+5=115
	_check_exact("S10a Jolteon effective_speed (no para, expect 135)",
			StatusManager.effective_speed(jolteon), 135)
	_check_exact("S10b Raichu effective_speed (no para, expect 115)",
			StatusManager.effective_speed(raichu), 115)

	# Can't paralyze Electric-types directly — use a Normal-type as stand-in
	# for speed-cut verification with an explicit status assignment:
	var fast_mon := _make_mon("FastNormal", [TypeChart.TYPE_NORMAL], 45, 45, 45, 45, 45, 130)
	StatusManager.try_apply_status(fast_mon, BattlePokemon.STATUS_PARALYSIS)
	# Speed stat: floor((2*130)*50/100)+5 = 135
	# Paralyzed: 135/2 = 67
	_check_exact("S10c Normal paralyzed effective_speed = 135/2=67",
			StatusManager.effective_speed(fast_mon), 67)

	# ─── CONFUSION + MAJOR STATUS COEXISTENCE ────────────────────────────────

	# S11: Confusion (volatile) and a major status can coexist.
	var sq_both := _clone(squirtle)
	StatusManager.try_apply_status(sq_both, BattlePokemon.STATUS_PARALYSIS)
	StatusManager.try_apply_confusion(sq_both, 3)
	_check_exact("S11 confused AND paralyzed simultaneously",
			sq_both.status, BattlePokemon.STATUS_PARALYSIS)
	_check_exact("S11 confusion_turns=3", sq_both.confusion_turns, 3)

	# S11 combined check: both forced same direction (para would pass; self-hit fires)
	var both_c := StatusManager.pre_move_check(sq_both, null, null, true, false)
	_check_exact("S11 confusion self-hit fires: can_move=false",
			int(both_c["can_move"]), 0)
	_check_exact("S11 self_hit_damage > 0", int(both_c["self_hit_damage"] > 0), 1)

	# S11b: ORDER pin — confusion fires BEFORE paralysis
	# Source: CANCELER_CONFUSED (pos 15) < CANCELER_PARALYZED (pos 17)
	#   in include/constants/battle_move_resolution.h enum CancelerState
	# Force BOTH self-hit=true AND full-para=true.
	# If confusion runs first: returns early → self_hit_damage > 0, paralysis never evaluated.
	# If paralysis ran first: would return early → self_hit_damage == 0.
	var sq_order := _clone(squirtle)
	StatusManager.try_apply_status(sq_order, BattlePokemon.STATUS_PARALYSIS)
	StatusManager.try_apply_confusion(sq_order, 3)
	var order_c := StatusManager.pre_move_check(sq_order, null, null, true, true)
	_check_exact("S11b confusion before paralysis: self_hit_damage > 0 (confusion ran first)",
			int(order_c["self_hit_damage"] > 0), 1)

	# S12: ORDER pin — sleep (CANCELER_ASLEEP_OR_FROZEN, pos 5) fires BEFORE
	#   confusion (CANCELER_CONFUSED, pos 15)
	# Pokémon has both STATUS_SLEEP and confusion_turns=3. Force stay-asleep.
	# Sleep returns early → confusion check never runs → self_hit_damage == 0 even
	# though force_confusion_hit=true.
	var sq_sleep_conf := _clone(squirtle)
	StatusManager.try_apply_status(sq_sleep_conf, BattlePokemon.STATUS_SLEEP, 3)
	StatusManager.try_apply_confusion(sq_sleep_conf, 3)
	var sc_c := StatusManager.pre_move_check(sq_sleep_conf, false, null, true)
	_check_exact("S12 sleep fires before confusion: self_hit_damage=0 (sleep returned early)",
			sc_c["self_hit_damage"], 0)
	_check_exact("S12 can_move=false (blocked by sleep, not confusion)", int(sc_c["can_move"]), 0)

	# ─── RESULTS ─────────────────────────────────────────────────────────────

	print("")
	print("=== Results: " + str(_pass) + " passed, " + str(_fail) + " failed ===")
	get_tree().quit(0 if _fail == 0 else 1)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _burn_tick(mon: BattlePokemon) -> int:
	var tmp := _clone(mon)
	StatusManager.try_apply_status(tmp, BattlePokemon.STATUS_BURN)
	return StatusManager.end_of_turn_damage(tmp)


func _check_exact(label: String, got: int, expected: int) -> void:
	if got == expected:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  expected=" + str(expected) + " got=" + str(got))
		_fail += 1


func _make_mon(name: String, types: Array[int], base_hp: int, base_atk: int, base_def: int,
		base_satk: int, base_sdef: int, base_spd: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name    = name
	sp.types           = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_satk
	sp.base_sp_defense = base_sdef
	sp.base_speed      = base_spd
	sp.abilities       = []
	sp.learnset        = []
	return BattlePokemon.from_species(sp, 50)


func _make_move(name: String, type_id: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name          = name
	m.type               = type_id
	m.category           = category
	m.power              = power
	m.accuracy           = 0
	m.pp                 = 10
	m.priority           = 0
	m.critical_hit_stage = 0
	return m


func _clone(mon: BattlePokemon) -> BattlePokemon:
	var sp := mon.species
	var bp := BattlePokemon.from_species(sp, mon.level)
	bp.status          = mon.status
	bp.sleep_turns     = mon.sleep_turns
	bp.toxic_counter   = mon.toxic_counter
	bp.confusion_turns = mon.confusion_turns
	bp.stat_stages     = mon.stat_stages.duplicate()
	return bp
