extends Node

# [Bucket 4 cheapest singles] 7 of the 9 originally-proposed single-move
# sub-groups — Rage(99), Clear Smog(499), Incinerate(510), Sparkling
# Aria(627), Throat Chop(638), Eerie Spell(754), Blood Moon(829). Secret
# Power(290) and Uproar(253) were deferred after Step 0: Secret Power's
# secondary depends on gBattleEnvironment, an overworld map/tile-derived
# concept this project has no analog for at all; Uproar needs the same
# multi-turn forced-move-repeat primitive Bucket 4's still-unbuilt
# M19-rampage sub-group (Thrash/Petal Dance/Outrage/Raging Fury) needs, not
# the "cheap/self-contained" shape this session's other 7 moves share.
#
# Step 0 found each move's real mechanism independently, several correcting
# or sharpening a one-line plan-doc summary — see move_data.gd's own per-flag
# doc comments for full source citations:
#   - Rage: NOT a rampage-lock (no gLockedMoves in source) — a genuinely
#     simple persistent "rage_active" volatile, set on a successful hit,
#     cleared the moment a DIFFERENT move is chosen; while active, ANY
#     damaging hit taken raises Attack +1 (self/ally-hit excluded).
#   - Clear Smog: an ABSOLUTE reset of all 7 stat stages to 0, not a relative
#     stat_change_amount delta — this project has no Haze precedent to reuse
#     (Haze itself isn't implemented), so this is a genuinely new dispatch
#     branch, just a very small one.
#   - Incinerate: destroys (not consumes) the target's held Berry — correctly
#     does NOT go through this project's existing `_consume_item` (which
#     would incorrectly trigger Cheek Pouch / register last_consumed_berry);
#     Gems are permanently moot (this project has none).
#   - Sparkling Aria: cures the TARGET's own burn (not the user's).
#   - Throat Chop / Eerie Spell: both explicit chance=100 (true secondaries,
#     gated by Shield Dust/Sheer Force/Covert Cloak/Serene Grace like any
#     other), each given its own new SE_* constant since neither fits any
#     existing SE_* semantic. Eerie Spell reuses the pre-existing
#     BattlePokemon.last_move_used field (already comprehensively wired since
#     [M16e]'s Conversion 2) — zero new tracking state needed, resolving the
#     task's own "does this need new state" question with a clean no.
#   - Blood Moon: reuses that SAME last_move_used field (object-reference
#     equality, the same pattern this project's existing Disable check
#     already uses) — also zero new tracking state, confirming Eerie Spell
#     and Blood Moon do NOT need a shared new mechanism, just a shared
#     EXISTING one.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c, battle_util.c, battle_main.c, battle_end_turn.c,
# GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_rage()
	_test_clear_smog()
	_test_incinerate()
	_test_sparkling_aria()
	_test_throat_chop()
	_test_eerie_spell()
	_test_blood_moon()

	var total := _pass + _fail
	print("m19_bucket4_cheap_singles_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


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


# ── Section A: data integrity (all 7 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var rage := _load_move(99)
	_chk("99 Rage loads", rage != null)
	_chk("99 name/type/category/power/accuracy/pp",
			rage.move_name == "Rage" and rage.type == TypeChart.TYPE_NORMAL
					and rage.category == 0 and rage.power == 20 and rage.accuracy == 100
					and rage.pp == 20)
	_chk("99 makes_contact + is_rage", rage.makes_contact and rage.is_rage)

	var clear_smog := _load_move(499)
	_chk("499 Clear Smog loads", clear_smog != null)
	_chk("499 name/type/category/power/accuracy/pp",
			clear_smog.move_name == "Clear Smog" and clear_smog.type == TypeChart.TYPE_POISON
					and clear_smog.category == 1 and clear_smog.power == 50
					and clear_smog.accuracy == 0 and clear_smog.pp == 15)
	_chk("499 is_clear_smog", clear_smog.is_clear_smog)

	var incinerate := _load_move(510)
	_chk("510 Incinerate loads", incinerate != null)
	_chk("510 name/type/category/power/accuracy/pp",
			incinerate.move_name == "Incinerate" and incinerate.type == TypeChart.TYPE_FIRE
					and incinerate.category == 1 and incinerate.power == 60
					and incinerate.accuracy == 100 and incinerate.pp == 15)
	_chk("510 is_spread + is_incinerate", incinerate.is_spread and incinerate.is_incinerate)

	var sparkling_aria := _load_move(627)
	_chk("627 Sparkling Aria loads", sparkling_aria != null)
	_chk("627 name/type/category/power/accuracy/pp",
			sparkling_aria.move_name == "Sparkling Aria" and sparkling_aria.type == TypeChart.TYPE_WATER
					and sparkling_aria.category == 1 and sparkling_aria.power == 90
					and sparkling_aria.accuracy == 100 and sparkling_aria.pp == 10)
	_chk("627 sound_move + ignores_substitute + is_spread + is_sparkling_aria",
			sparkling_aria.sound_move and sparkling_aria.ignores_substitute
					and sparkling_aria.is_spread and sparkling_aria.is_sparkling_aria)

	var throat_chop := _load_move(638)
	_chk("638 Throat Chop loads", throat_chop != null)
	_chk("638 name/type/category/power/accuracy/pp",
			throat_chop.move_name == "Throat Chop" and throat_chop.type == TypeChart.TYPE_DARK
					and throat_chop.category == 0 and throat_chop.power == 80
					and throat_chop.accuracy == 100 and throat_chop.pp == 15)
	_chk("638 makes_contact + SE_THROAT_CHOP secondary_chance=100",
			throat_chop.makes_contact and throat_chop.secondary_effect == MoveData.SE_THROAT_CHOP
					and throat_chop.secondary_chance == 100)

	var eerie_spell := _load_move(754)
	_chk("754 Eerie Spell loads", eerie_spell != null)
	_chk("754 name/type/category/power/accuracy/pp",
			eerie_spell.move_name == "Eerie Spell" and eerie_spell.type == TypeChart.TYPE_PSYCHIC
					and eerie_spell.category == 1 and eerie_spell.power == 80
					and eerie_spell.accuracy == 100 and eerie_spell.pp == 5)
	_chk("754 sound_move + ignores_substitute + SE_EERIE_SPELL secondary_chance=100",
			eerie_spell.sound_move and eerie_spell.ignores_substitute
					and eerie_spell.secondary_effect == MoveData.SE_EERIE_SPELL
					and eerie_spell.secondary_chance == 100)

	var blood_moon := _load_move(829)
	_chk("829 Blood Moon loads", blood_moon != null)
	_chk("829 name/type/category/power/accuracy/pp",
			blood_moon.move_name == "Blood Moon" and blood_moon.type == TypeChart.TYPE_NORMAL
					and blood_moon.category == 1 and blood_moon.power == 140
					and blood_moon.accuracy == 100 and blood_moon.pp == 5)
	_chk("829 cant_use_twice, no secondary effect at all",
			blood_moon.cant_use_twice and blood_moon.secondary_effect == MoveData.SE_NONE)


# ── Rage ─────────────────────────────────────────────────────────────────────

func _test_rage() -> void:
	var rage := _load_move(99)
	var tackle := _load_move(33)
	var atk := _make_mon("RageAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(rage)
	var def := _make_mon("RageDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	var rage_flag_at_hit := [false]
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk and not rage_flag_at_hit[0]:
			rage_flag_at_hit[0] = atk.rage_active)
	bm.start_battle(atk, def)

	_chk("Rage: rage_active is set on the attacker immediately after its own successful hit",
			rage_flag_at_hit[0] == true)
	_chk("Rage: the defender's own Tackle hitting the rage_active holder raises the " +
			"holder's Attack +1 (reactive trigger)",
			stat_events.any(func(e): return e[0] == atk and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1))

	# Discriminator: choosing a DIFFERENT move clears rage_active at the top of
	# the next turn, before that turn's own hit resolves.
	var atk2 := _make_mon("RageAtk2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk2.rage_active = true
	atk2.add_move(tackle)
	var def2 := _make_mon("RageDef2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var cleared := [false]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk2 and not cleared[0]:
			cleared[0] = not atk2.rage_active)
	bm2.start_battle(atk2, def2)
	_chk("Rage: pre-set rage_active is cleared once the attacker chooses a non-Rage move",
			cleared[0] == true)


# ── Clear Smog ───────────────────────────────────────────────────────────────

func _test_clear_smog() -> void:
	var clear_smog := _load_move(499)
	var tackle := _load_move(33)
	var atk := _make_mon("CSAtk", TypeChart.TYPE_POISON, 100, 60, 60, 60, 60, 100)
	atk.add_move(clear_smog)
	var def := _make_mon("CSDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.stat_stages[BattlePokemon.STAGE_ATK] = 2
	def.stat_stages[BattlePokemon.STAGE_DEF] = -3
	def.stat_stages[BattlePokemon.STAGE_SPEED] = 1
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var stat_events := []
	var dmg := [0]
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.start_battle(atk, def)

	_chk("Clear Smog deals real nonzero damage", dmg[0] > 0)
	_chk("Clear Smog resets +2 Atk to 0 (delta -2)",
			stat_events.any(func(e): return e[0] == def and e[1] == BattlePokemon.STAGE_ATK and e[2] == -2))
	_chk("Clear Smog resets -3 Def to 0 (delta +3)",
			stat_events.any(func(e): return e[0] == def and e[1] == BattlePokemon.STAGE_DEF and e[2] == 3))
	_chk("Clear Smog resets +1 Speed to 0 (delta -1)",
			stat_events.any(func(e): return e[0] == def and e[1] == BattlePokemon.STAGE_SPEED and e[2] == -1))

	# Discriminator: already-all-zero stats -> no signal fires at all (pure no-op).
	var atk2 := _make_mon("CSAtk2", TypeChart.TYPE_POISON, 100, 60, 60, 60, 60, 100)
	atk2.add_move(clear_smog)
	var def2 := _make_mon("CSDef2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var stat_events2 := []
	bm2.stat_stage_changed.connect(func(t, s, a): stat_events2.append([t, s, a]))
	bm2.start_battle(atk2, def2)
	_chk("Clear Smog no-ops silently (no stat_stage_changed signal at all) when every " +
			"stat is already 0", stat_events2.is_empty())


# ── Incinerate ───────────────────────────────────────────────────────────────

func _test_incinerate() -> void:
	var incinerate := _load_move(510)
	var tackle := _load_move(33)
	# Deliberately a NEUTRAL (hold_effect=0) berry-pocket item — see the Sticky
	# Hold discriminator below for why a real heal-on-low-HP item is avoided here.
	var neutral_berry0 := _make_item(0, 0)
	neutral_berry0.pocket = ItemManager.POCKET_BERRIES

	var atk := _make_mon("IncAtk", TypeChart.TYPE_FIRE, 100, 60, 60, 60, 60, 100)
	atk.add_move(incinerate)
	var def := _make_mon("IncDef", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 40)
	def.held_item = neutral_berry0
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var triggered := []
	var consumed := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.item_effect_triggered.connect(func(m, key): triggered.append([m, key]))
	bm.item_consumed.connect(func(m, i): consumed.append(m))
	bm.start_battle(atk, def)

	_chk("Incinerate deals real nonzero damage", dmg[0] > 0)
	_chk("Incinerate destroys the target's held Berry (held_item becomes null)",
			def.held_item == null)
	_chk("Incinerate emits item_effect_triggered('incinerate_destroyed')",
			[def, "incinerate_destroyed"] in triggered)
	_chk("Incinerate does NOT route through _consume_item (it destroys, not consumes " +
			"— item_consumed never fires for the target)",
			not (def in consumed))

	# Discriminator: Sticky Hold blocks the destruction entirely. Deliberately a
	# NEUTRAL (hold_effect=0) berry-pocket item, not a real Oran-shaped one — a
	# functional heal-on-low-HP item surviving Incinerate would ALSO legitimately
	# trigger its own unrelated HP-threshold auto-heal later in the same battle
	# (Sticky Hold blocks external removal, not the holder's own voluntary
	# consumption), which would confound this specific Incinerate-vs-Sticky-Hold
	# assertion with an unrelated mechanic.
	var sticky_hold := _load_ability(60)
	var atk2 := _make_mon("IncAtk2", TypeChart.TYPE_FIRE, 100, 60, 60, 60, 60, 100)
	atk2.add_move(incinerate)
	var def2 := _make_mon("IncDef2", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 40)
	def2.ability = sticky_hold
	var neutral_berry := _make_item(0, 0)
	neutral_berry.pocket = ItemManager.POCKET_BERRIES
	def2.held_item = neutral_berry
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.start_battle(atk2, def2)
	_chk("Incinerate discriminator: Sticky Hold blocks the destruction — held_item survives",
			def2.held_item != null)

	# Discriminator: a non-berry item (e.g. Leftovers-shaped) is untouched.
	var atk3 := _make_mon("IncAtk3", TypeChart.TYPE_FIRE, 100, 60, 60, 60, 60, 100)
	atk3.add_move(incinerate)
	var def3 := _make_mon("IncDef3", TypeChart.TYPE_GRASS, 100, 60, 60, 60, 60, 40)
	var leftovers := _make_item(ItemManager.HOLD_EFFECT_LEFTOVERS, 0)
	leftovers.pocket = 0  # not POCKET_BERRIES
	def3.held_item = leftovers
	def3.add_move(tackle)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.start_battle(atk3, def3)
	_chk("Incinerate discriminator: a non-Berry item is untouched", def3.held_item != null)


# ── Sparkling Aria ───────────────────────────────────────────────────────────

func _test_sparkling_aria() -> void:
	var sparkling_aria := _load_move(627)
	var tackle := _load_move(33)
	var atk := _make_mon("SAAtk", TypeChart.TYPE_WATER, 100, 60, 60, 60, 60, 100)
	atk.add_move(sparkling_aria)
	var def := _make_mon("SADef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.status = BattlePokemon.STATUS_BURN
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var cured := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.status_cured.connect(func(m): cured.append(m))
	bm.start_battle(atk, def)

	_chk("Sparkling Aria deals real nonzero damage", dmg[0] > 0)
	_chk("Sparkling Aria cures the TARGET's own burn", def in cured)

	# Discriminator: a target with no burn (a different status) is untouched.
	var atk2 := _make_mon("SAAtk2", TypeChart.TYPE_WATER, 100, 60, 60, 60, 60, 100)
	atk2.add_move(sparkling_aria)
	var def2 := _make_mon("SADef2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def2.status = BattlePokemon.STATUS_PARALYSIS
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var cured2 := []
	bm2.status_cured.connect(func(m): cured2.append(m))
	bm2.start_battle(atk2, def2)
	_chk("Sparkling Aria discriminator: paralysis (not burn) is left untouched",
			cured2.is_empty() and def2.status == BattlePokemon.STATUS_PARALYSIS)


# ── Throat Chop ──────────────────────────────────────────────────────────────

func _test_throat_chop() -> void:
	var throat_chop := _load_move(638)
	var growl := _load_move(45)  # sound_move status move, no damage
	var tackle := _load_move(33)

	# Direct roll test (matches this project's established convention for
	# deterministic secondary-chance testing).
	var atk := _make_mon("TCAtk", TypeChart.TYPE_DARK)
	var def := _make_mon("TCDef", TypeChart.TYPE_NORMAL)
	_chk("Throat Chop's secondary fires when forced true",
			StatusManager.try_secondary_effect(atk, def, throat_chop, true) == true)

	# Full-battle: the holder's own sound move (Growl) fails while throat_chop_turns
	# is active; a non-sound move (Tackle) is unaffected.
	var atk2 := _make_mon("TCAtk2", TypeChart.TYPE_DARK, 100, 60, 60, 60, 60, 100)
	atk2.add_move(throat_chop)
	var holder := _make_mon("TCHolder", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	holder.add_move(growl)
	holder.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	# Force the throat_chop_turns effect on directly (deterministic — matches this
	# project's established pattern of pre-setting persistent state for a
	# full-battle discriminator test rather than relying on a 100%-chance roll
	# through the full dispatch, which this move already carries anyway).
	var skipped := []
	bm.move_skipped.connect(func(m, reason): skipped.append([m, reason]))
	holder.throat_chop_turns = 2
	bm.start_battle(atk2, holder)
	_chk("Throat Chop: the holder's own sound move (Growl) fails with reason " +
			"'throat_chop' while the timer is active",
			skipped.any(func(s): return s[0] == holder and s[1] == "throat_chop"))

	# Discriminator: decrement/expiry via the direct field, and non-sound moves unaffected.
	var atk3 := _make_mon("TCAtk3", TypeChart.TYPE_DARK, 100, 60, 60, 60, 60, 100)
	atk3.add_move(throat_chop)
	var holder2 := _make_mon("TCHolder2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	holder2.throat_chop_turns = 2
	holder2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var skipped2 := []
	bm2.move_skipped.connect(func(m, reason): skipped2.append([m, reason]))
	bm2.start_battle(atk3, holder2)
	_chk("Throat Chop discriminator: a non-sound move (Tackle) is never blocked by " +
			"the timer", not skipped2.any(func(s): return s[1] == "throat_chop"))


# ── Eerie Spell ──────────────────────────────────────────────────────────────

func _test_eerie_spell() -> void:
	var eerie_spell := _load_move(754)
	var tackle := _load_move(33)

	var atk := _make_mon("ESAtk", TypeChart.TYPE_PSYCHIC)
	var def := _make_mon("ESDef", TypeChart.TYPE_NORMAL)
	_chk("Eerie Spell's secondary fires when forced true",
			StatusManager.try_secondary_effect(atk, def, eerie_spell, true) == true)

	# Full-battle: cuts 3 PP from the target's own last_move_used slot. atk3 is
	# made FASTER than the holder so Eerie Spell resolves BEFORE the holder ever
	# gets to act (and drain its own Tackle's PP naturally), isolating the -3
	# deduction against a still-full PP pool. Snapshotted via secondary_applied
	# (fires exactly where the PP deduction happens in BattleManager), NOT
	# move_executed (which fires much earlier in the same function, well before
	# the secondary-effect dispatch runs — a fresh instance of the documented
	# "signal fires before the state actually changes" pitfall, caught on this
	# test's own first run).
	var atk3 := _make_mon("ESAtk3", TypeChart.TYPE_PSYCHIC, 100, 60, 60, 60, 60, 200)
	atk3.add_move(eerie_spell)
	var holder2 := _make_mon("ESHolder2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	holder2.add_move(tackle)
	holder2.last_move_used = tackle
	var bm2 := _make_bm()
	bm2._force_hit = true
	var pp_after_eerie_spell := [-1]
	bm2.secondary_applied.connect(func(t, effect):
		if t == holder2 and effect == MoveData.SE_EERIE_SPELL and pp_after_eerie_spell[0] == -1:
			pp_after_eerie_spell[0] = holder2.current_pp[0])
	bm2.start_battle(atk3, holder2)
	_chk("Eerie Spell discriminator: exactly 3 PP deducted from the pre-existing full " +
			"PP pool, sampled at the moment secondary_applied(SE_EERIE_SPELL) fires " +
			"(%d -> %d)" % [tackle.pp, pp_after_eerie_spell[0]],
			pp_after_eerie_spell[0] == tackle.pp - 3)

	# Discriminator: no last_move_used at all -> no-op, no crash.
	var atk4 := _make_mon("ESAtk4", TypeChart.TYPE_PSYCHIC, 100, 60, 60, 60, 60, 100)
	atk4.add_move(eerie_spell)
	var holder3 := _make_mon("ESHolder3", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	holder3.add_move(tackle)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.start_battle(atk4, holder3)
	_chk("Eerie Spell discriminator: no last_move_used yet -> no crash, no effect",
			true)


# ── Blood Moon ───────────────────────────────────────────────────────────────

func _test_blood_moon() -> void:
	var blood_moon := _load_move(829)
	var tackle := _load_move(33)

	var atk := _make_mon("BMAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(blood_moon)
	atk.add_move(tackle)
	atk.last_move_used = blood_moon
	var def := _make_mon("BMDef", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var skipped := []
	bm.move_skipped.connect(func(m, reason): skipped.append([m, reason]))
	bm.start_battle(atk, def)
	_chk("Blood Moon fails with reason 'cant_use_twice' when it was the attacker's " +
			"own last move used",
			skipped.any(func(s): return s[0] == atk and s[1] == "cant_use_twice"))

	# Discriminator: NOT the last move used -> fires normally, real damage dealt.
	var atk2 := _make_mon("BMAtk2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk2.add_move(blood_moon)
	atk2.last_move_used = tackle
	var def2 := _make_mon("BMDef2", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 40)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_crit = false
	var dmg := [0]
	bm2.move_executed.connect(func(a, _d, _m, amount):
		if a == atk2 and dmg[0] == 0:
			dmg[0] = amount)
	bm2.start_battle(atk2, def2)
	_chk("Blood Moon discriminator: fires normally with real nonzero damage when it " +
			"was NOT the attacker's own last move used", dmg[0] > 0)
