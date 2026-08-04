extends Node

## [M27O O4] Field poison, and the persistent party it needs.
##
## The two things most worth pinning are both places where a plausible port
## diverges from source and still looks right:
##
##   * the damage is a FLAT 1 HP and toxic ticks at the SAME rate as ordinary
##     poison — the in-battle escalation is the obvious thing to reach for and
##     source does not apply it here;
##   * a mon ALREADY at 1 HP re-announces every tick, because source's own
##     `hp == 1 || --hp == 1` short-circuits. The cure is what breaks the loop,
##     not the damage.
##
## Everything else here guards the persistent party, which is new and is what
## makes a leaked volatile a cross-battle bug rather than a per-battle one.

const EXPECTED_TOTAL := 56

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


## A real Bulbasaur, so `species_name` is real for the message test.
func _mon(hp: int, status: int = BattlePokemon.STATUS_NONE) -> BattlePokemon:
	var m := PokemonFactory.create_battle_pokemon(1, 20)
	m.current_hp = hp
	m.status = status
	return m


func _party(mons: Array) -> BattleParty:
	var p := BattleParty.new()
	for m in mons:
		p.members.append(m as BattlePokemon)
	p.active_indices = [0]
	return p


func _ready() -> void:
	_test_cadence()
	_test_tick()
	_test_cure()
	_test_reannounce_loop()
	_test_party_persistence()
	_test_wiring()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27o_field_poison_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the step cadence ---
func _test_cadence() -> void:
	var f := FlagStore.new()
	_chk("A.01 the interval is source's own 4", FieldPoison.STEP_INTERVAL == 4)
	var fires: Array[bool] = []
	for i in range(8):
		fires.append(FieldPoison.advance_counter(f))
	# Source: `(*ptr)++; (*ptr) %= 4; if (*ptr == 0)` — so the 4th step fires,
	# not the 1st. An off-by-one here poisons on the step you take out of a
	# Centre, which is the shape a naive `% 4 == 1` would give.
	_chk("A.02 the FIRST step does not tick", fires[0] == false)
	_chk("A.03 nor the 2nd or 3rd", fires[1] == false and fires[2] == false)
	_chk("A.04 the 4th does", fires[3] == true)
	_chk("A.05 and then every 4th after it",
			fires[4] == false and fires[5] == false and fires[6] == false and fires[7] == true)
	# The counter is a REAL var, not a private field — so it rides the scene
	# swap a battle performs, exactly like every other persistent var.
	_chk("A.06 the counter lives in the var store under source's own name",
			f.var_get(FieldPoison.STEP_COUNTER_VAR) == 0)
	FieldPoison.advance_counter(f)
	_chk("A.07 which is genuinely written, not just read",
			f.var_get(FieldPoison.STEP_COUNTER_VAR) == 1)
	FieldPoison.clear_counter(f)
	_chk("A.08 clearing resets it (source does this at every battle entry)",
			f.var_get(FieldPoison.STEP_COUNTER_VAR) == 0)
	_chk("A.09 a null store is a no-op, not a crash",
			FieldPoison.advance_counter(null) == false)


## --- B. the tick ---
func _test_tick() -> void:
	var poisoned := _mon(20, BattlePokemon.STATUS_POISON)
	var healthy := _mon(20)
	var p := _party([poisoned, healthy])
	var r := FieldPoison.tick(p)
	# ⚠️ FLAT 1 HP. Not maxHP/8, not maxHP/16 — source's own `--hp`. A fraction
	# would be the natural guess from every in-battle residual in this project.
	_chk("B.01 a poisoned mon loses exactly 1 HP", poisoned.current_hp == 19)
	_chk("B.02 an unpoisoned one loses nothing", healthy.current_hp == 20)
	_chk("B.03 an ordinary tick reports POISONED",
			r == FieldPoison.RESULT_POISONED)

	# ⚠️ TOXIC TICKS AT THE SAME FLAT RATE. `GetAilmentFromStatus` collapses
	# both onto AILMENT_PSN, so the escalation this project models in battle is
	# deliberately absent out of it. Asserted against an ordinary-poison twin so
	# the claim is a COMPARISON, not just "toxic lost 1".
	var tox := _mon(20, BattlePokemon.STATUS_TOXIC)
	tox.toxic_counter = 5
	var psn := _mon(20, BattlePokemon.STATUS_POISON)
	FieldPoison.tick(_party([tox, psn]))
	_chk("B.04 toxic loses exactly as much as ordinary poison",
			tox.current_hp == psn.current_hp and tox.current_hp == 19)

	# The floor, and the reason no faint hookup is needed.
	var low := _mon(2, BattlePokemon.STATUS_POISON)
	var lp := _party([low])
	_chk("B.05 dropping to 1 HP reports AT_ONE_HP",
			FieldPoison.tick(lp) == FieldPoison.RESULT_AT_ONE_HP)
	_chk("B.06 and lands on exactly 1", low.current_hp == 1)
	low.current_hp = 1
	FieldPoison.tick(lp)
	_chk("B.07 a further tick NEVER takes it below 1", low.current_hp == 1)
	_chk("B.08 and never faints it", low.fainted == false)

	# Other statuses are not poison. Burn especially — it is the in-battle
	# residual that looks most like this one.
	var burned := _mon(20, BattlePokemon.STATUS_BURN)
	_chk("B.09 burn does not tick in the field",
			FieldPoison.tick(_party([burned])) == FieldPoison.RESULT_NONE
			and burned.current_hp == 20)

	var fainted := _mon(0, BattlePokemon.STATUS_POISON)
	fainted.fainted = true
	_chk("B.10 a fainted mon is skipped (source would underflow its u32 here)",
			FieldPoison.tick(_party([fainted])) == FieldPoison.RESULT_NONE
			and fainted.current_hp == 0)

	_chk("B.11 an unpoisoned party reports NONE",
			FieldPoison.tick(_party([_mon(20)])) == FieldPoison.RESULT_NONE)
	_chk("B.12 a null party is a no-op",
			FieldPoison.tick(null) == FieldPoison.RESULT_NONE)

	# AT_ONE_HP outranks POISONED when both are true in one party — it is what
	# makes the caller run the cure at all, so a party where only one mon is
	# critical must still report it.
	var crit := _mon(2, BattlePokemon.STATUS_POISON)
	var fine := _mon(30, BattlePokemon.STATUS_POISON)
	_chk("B.13 one critical mon outranks a healthy poisoned one",
			FieldPoison.tick(_party([fine, crit])) == FieldPoison.RESULT_AT_ONE_HP)
	_chk("B.14 and both still took their damage",
			fine.current_hp == 29 and crit.current_hp == 1)


## --- C. the cure ---
func _test_cure() -> void:
	var m := _mon(1, BattlePokemon.STATUS_TOXIC)
	m.toxic_counter = 7
	var cured := FieldPoison.cure_at_one_hp(_party([m]))
	_chk("C.01 a mon at 1 HP is cured", m.status == BattlePokemon.STATUS_NONE)
	_chk("C.02 the toxic counter goes with the status (one field in source)",
			m.toxic_counter == 0)
	_chk("C.03 and it is reported, so the message can name it",
			cured.size() == 1 and cured[0] == m)
	# ⚠️ CURED, NOT HEALED. Source clears status1 and nothing else — walking it
	# off does not give the HP back.
	_chk("C.04 but NOT healed — it is still on 1 HP", m.current_hp == 1)

	var two := _mon(2, BattlePokemon.STATUS_POISON)
	_chk("C.05 a mon at 2 HP is not cured",
			FieldPoison.cure_at_one_hp(_party([two])).is_empty()
			and two.status == BattlePokemon.STATUS_POISON)

	var burned := _mon(1, BattlePokemon.STATUS_BURN)
	_chk("C.06 a BURNED mon at 1 HP is not cured — poison only",
			FieldPoison.cure_at_one_hp(_party([burned])).is_empty()
			and burned.status == BattlePokemon.STATUS_BURN)

	# Source loops back to state 0 after each message, so every survivor gets
	# its own line rather than one summary.
	var a := _mon(1, BattlePokemon.STATUS_POISON)
	var b := _mon(1, BattlePokemon.STATUS_TOXIC)
	var c := _mon(1)
	var many := FieldPoison.cure_at_one_hp(_party([a, b, c]))
	_chk("C.07 every survivor is reported separately", many.size() == 2)
	_chk("C.08 and each is genuinely cured",
			a.status == BattlePokemon.STATUS_NONE and b.status == BattlePokemon.STATUS_NONE)

	_chk("C.09 a null party is a no-op", FieldPoison.cure_at_one_hp(null).is_empty())


## --- D. the re-announce loop, and what breaks it ---
##
## The short-circuit in `hp == 1 || --hp == 1` means a mon parked at 1 HP counts
## on EVERY tick, not just the one that got it there. Reproduced deliberately —
## and the cure is the only thing that stops it, which is why the caller must
## run both halves rather than just the damage.
func _test_reannounce_loop() -> void:
	var m := _mon(1, BattlePokemon.STATUS_POISON)
	var p := _party([m])
	_chk("D.01 a mon ALREADY at 1 HP still reports AT_ONE_HP",
			FieldPoison.tick(p) == FieldPoison.RESULT_AT_ONE_HP)
	_chk("D.02 and again on the next tick, unchanged",
			FieldPoison.tick(p) == FieldPoison.RESULT_AT_ONE_HP and m.current_hp == 1)
	FieldPoison.cure_at_one_hp(p)
	_chk("D.03 the CURE is what breaks the loop, not the damage",
			FieldPoison.tick(p) == FieldPoison.RESULT_NONE)


## --- E. the persistent party ---
func _test_party_persistence() -> void:
	OverworldSession.reset()
	# [M27L L5] Seeded EXPLICITLY. `player_party()` no longer lazily builds
	# `[M27D D5]`'s debug team — a new game starts empty, like source's own
	# `ZeroPlayerPartyMons()`. The team still exists for tests like this one;
	# it is simply no longer what you get by default.
	if OverworldSession.party == null or OverworldSession.party.members.is_empty():
		OverworldSession.party = OverworldParty.build_debug_player_party()
	var p1 := OverworldSession.player_party()
	var p2 := OverworldSession.player_party()
	# ⚠️ THE SAME OBJECT, not an equal one. Identity is the whole mechanism:
	# the battle mutates these very instances, which is what carries HP and
	# status back out.
	_chk("E.01 the party is built once and reused", p1 == p2)
	_chk("E.02 and it is non-empty", p1.members.size() > 0)

	var lead: BattlePokemon = p1.members[0]
	lead.current_hp = 5
	lead.status = BattlePokemon.STATUS_POISON
	lead.stat_stages[BattlePokemon.STAT_ATK] = 6
	lead.substitute_hp = 40
	lead.confusion_turns = 3
	lead.fainted = false
	p1.active_indices = [1]

	var bm := BattleManager.new()
	bm.restore_party_after_battle(p1)
	# The copy-back's equivalent: volatiles go, persistent facts stay.
	_chk("E.03 stat stages are stripped on the way out",
			lead.stat_stages[BattlePokemon.STAT_ATK] == 0)
	_chk("E.04 so is a live Substitute", lead.substitute_hp == 0)
	_chk("E.05 and confusion", lead.confusion_turns == 0)
	_chk("E.06 but HP SURVIVES — it is the point of a persistent party",
			lead.current_hp == 5)
	_chk("E.07 and so does status, which is how poison gets into the field",
			lead.status == BattlePokemon.STATUS_POISON)
	# Set to slot 1 above, so this only passes if the restore genuinely reset it.
	_chk("E.08 the active slot is reset to the lead", p1.active_indices[0] == 0)
	# Idempotent: a mon already cleared by its own faint must not be harmed.
	bm.restore_party_after_battle(p1)
	_chk("E.09 running it twice changes nothing further",
			lead.current_hp == 5 and lead.status == BattlePokemon.STATUS_POISON)
	_chk("E.10 a null party is a no-op", _no_crash(bm))

	# A fainted member survives as fainted — the whiteout heals, not this.
	lead.fainted = true
	bm.restore_party_after_battle(p1)
	_chk("E.11 a faint is NOT undone by the restore", lead.fainted == true)

	OverworldSession.heal_party()
	_chk("E.12 the whiteout heal restores HP", lead.current_hp == lead.max_hp)
	_chk("E.13 clears status", lead.status == BattlePokemon.STATUS_NONE)
	_chk("E.14 and revives — without which the next battle starts on a dead lead",
			lead.fainted == false)
	_chk("E.15 and puts the lead back in the active slot",
			p1.active_indices[0] == 0)
	bm.free()
	OverworldSession.reset()


func _no_crash(bm: BattleManager) -> bool:
	bm.restore_party_after_battle(null)
	return true


## --- F. wiring, and the config this is built against ---
func _test_wiring() -> void:
	# ⚠️ The `>= GEN_4` string. The `< GEN_4` build of this same symbol reads
	# "{STR_VAR_1} fainted…" — pinned so a later session cannot swap in the
	# faint wording without noticing it is changing the ruleset.
	_chk("F.01 the message is source's own survived-the-poisoning line",
			FieldPoison.MESSAGE.contains("survived the poisoning")
			and FieldPoison.MESSAGE.contains("poison faded away"))
	_chk("F.02 and it is {STR_VAR_1}-shaped, so it goes through the real buffers",
			FieldPoison.MESSAGE.begins_with("{STR_VAR_1}"))
	var b := TextBuffers.new()
	b.set_slot(0, "BULBASAUR")
	var expanded := b.expand(FieldPoison.MESSAGE)
	_chk("F.03 expansion names the mon", expanded.begins_with("BULBASAUR survived"))
	_chk("F.04 and leaves no marker behind", not expanded.contains("{"))

	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	_chk("F.05 the overworld has a poison step", ow.has_method("_poison_step"))
	ow.free()

	var screen_path := "res://scenes/battle/battle_screen_singles.tscn"
	if not ResourceLoader.exists(screen_path):
		_gated += 1
	else:
		var bs: Control = load(screen_path).instantiate() as Control
		_chk("F.06 the battle screen can hand a party back cleaned",
				bs.has_method("restore_party"))
		bs.free()
