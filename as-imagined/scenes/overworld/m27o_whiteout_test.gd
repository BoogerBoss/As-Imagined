extends Node

## [M27O O2] The loss path.
##
## Two properties matter more than the warp itself, and both are about what must
## NOT happen: the beaten-trainer flag must stay unset, and the parked script
## must not resume. Either one getting through hands out the reward for a fight
## the player lost.

const EXPECTED_TOTAL := 43

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_defeat_rules()
	_test_flag_not_set()
	_test_destination()
	_test_scene_wiring()
	_test_payout()
	_test_heal_after_loss()
	_test_downgrade_bad_poison()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27o_whiteout_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. which outcomes are a defeat ---
func _test_defeat_rules() -> void:
	# ⚠️ A DRAW IS A DEFEAT. Source's own `IsPlayerDefeated` set is
	# {LOST, DREW, FORFEITED} — the one a winner-side boolean cannot express.
	_chk("A.01 a loss is a defeat",
			BattleOutcome.make(BattleOutcome.LOST).player_defeated())
	_chk("A.02 a DRAW is a defeat too",
			BattleOutcome.make(BattleOutcome.DREW).player_defeated())
	_chk("A.03 and a forfeit",
			BattleOutcome.make(BattleOutcome.FORFEITED).player_defeated())
	_chk("A.04 a win is not",
			not BattleOutcome.make(BattleOutcome.WON).player_defeated())
	_chk("A.05 nor is running or catching",
			not BattleOutcome.make(BattleOutcome.RAN).player_defeated()
			and not BattleOutcome.make(BattleOutcome.CAUGHT).player_defeated())


## --- B. the flag must NOT be set on a defeat ---
func _test_flag_not_set() -> void:
	# Source only calls SetBattledTrainersFlags on its non-defeat branch. This
	# is what makes losing cost something: the trainer is beatable again.
	_chk("B.01 a win against a trainer sets the flag",
			BattleOutcome.make(BattleOutcome.WON, "TRAINER_X").should_set_defeated_flag())
	_chk("B.02 a LOSS does not",
			not BattleOutcome.make(BattleOutcome.LOST, "TRAINER_X").should_set_defeated_flag())
	_chk("B.03 a DRAW does not",
			not BattleOutcome.make(BattleOutcome.DREW, "TRAINER_X").should_set_defeated_flag())
	_chk("B.04 a forfeit does not",
			not BattleOutcome.make(BattleOutcome.FORFEITED, "TRAINER_X").should_set_defeated_flag())
	# A wild battle has no trainer to flag, however it ended.
	_chk("B.05 a win with no trainer key flags nothing",
			not BattleOutcome.make(BattleOutcome.WON, "").should_set_defeated_flag())


## --- C. where a whiteout sends you ---
func _test_destination() -> void:
	if not FileAccess.file_exists(RespawnPoint.TABLE_PATH):
		_gated += 5
		return
	var r := RespawnPoint.new()
	r.set_to("HEAL_LOCATION_PEWTER_CITY")
	var w := r.respawn_warp()
	# ⚠️ At this project's config OW_WHITEOUT_CUTSCENE is GEN_LATEST, so
	# SetWarpDestinationToLastHealLocation takes its IsWhiteoutCutscene branch
	# and warps INSIDE. Using the heal point would drop the player outdoors.
	_chk("C.01 the destination is the respawn point, not the heal point",
			str(w.get("map", "")) == "PewterCity_PokemonCenter_1F_Frlg"
			and str(w.get("map", "")) != str(r.heal_warp().get("map", "")))
	_chk("C.02 with the centre's own interior coordinates",
			Vector2i(w.get("cell", Vector2i.ZERO)) == Vector2i(7, 4))
	# The corridor's respawn destinations must actually be baked, or a real
	# whiteout there has nowhere to go.
	var baked := 0
	for id in ["HEAL_LOCATION_PALLET_TOWN", "HEAL_LOCATION_VIRIDIAN_CITY",
			"HEAL_LOCATION_PEWTER_CITY"]:
		var e := RespawnPoint.entry(id)
		if ResourceLoader.exists("res://scenes/maps/%s.tscn" % str(e.get("respawn_map", ""))):
			baked += 1
	_chk("C.03 the corridor's own three respawn maps are baked", baked == 3)
	# ⚠️ And most are NOT — the whiteout must treat that as a real case rather
	# than tearing the region down and arriving nowhere.
	var unbaked := 0
	for id in RespawnPoint.ids():
		var e := RespawnPoint.entry(str(id))
		if not ResourceLoader.exists("res://scenes/maps/%s.tscn" % str(e.get("respawn_map", ""))):
			unbaked += 1
	_chk("C.04 most respawn maps are genuinely unbaked (%d of %d)"
			% [unbaked, RespawnPoint.ids().size()], unbaked > 30)
	_chk("C.05 an unset respawn resolves to nothing rather than a wrong map",
			RespawnPoint.new().respawn_warp().is_empty())


## --- D. the scene wiring ---
func _test_scene_wiring() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	_chk("D.01 the overworld has a whiteout path", ow.has_method("_do_whiteout"))
	_chk("D.02 and a way to abandon a script without reporting a coverage gap",
			ow.has_method("_abandon_script"))
	# ⚠️ `_apply_battle_result` REPORTS rather than performing, so each caller
	# can pick a moment when the scene is actually whole. The battle-return
	# spawn runs before the camera and fade exist, and a whiteout there would
	# fade an overlay that has not been built.
	_chk("D.03 applying a result reports whether a whiteout is owed",
			ow.has_method("_apply_battle_result"))
	_chk("D.04 and a deferred whiteout is recorded rather than performed early",
			"_pending_whiteout" in ow)
	_chk("D.05 load and placement are shared with the warp, and SEPARATE",
			ow.has_method("_teardown_and_load") and ow.has_method("_place_player"))
	# Nothing owed on a fresh scene.
	_chk("D.06 a fresh overworld owes no whiteout", ow._pending_whiteout == false)
	ow.free()


## --- E. [M27O O3] what losing costs ---
func _test_payout() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# The table and the flag list, against source.
	_chk("E.01 the badge table is source's own",
			ow.WHITEOUT_BADGE_MONEY == [8, 16, 24, 36, 48, 64, 80, 100, 120])
	_chk("E.02 nine entries, for 0 through 8 badges",
			ow.WHITEOUT_BADGE_MONEY.size() == 9
			# [M27L L1] BADGE_FLAGS moved to FlagStore, so the save-slot summary
			# can count badges with no field scene loaded. Same list, new home.
			and FlagStore.BADGE_FLAGS.size() == 8)

	# A clean session: no badges, so the 0-badge rate.
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
	OverworldSession.wallet.earn(100000)
	_chk("E.03 no badges uses the first rate x level",
			ow.whiteout_payout(10) == 8 * 10)
	# One badge moves to the next rate — Brock's own flag, which the corridor
	# really does set.
	OverworldSession.flags.flag_set("FLAG_BADGE01_GET")
	_chk("E.04 one badge moves up the table", ow.whiteout_payout(10) == 16 * 10)
	OverworldSession.flags.flag_set("FLAG_BADGE02_GET")
	_chk("E.05 and two badges again", ow.whiteout_payout(10) == 24 * 10)
	# ⚠️ Level scales it, and a level-0 party must not make losing free.
	_chk("E.06 the payout scales with the highest party level",
			ow.whiteout_payout(50) == 24 * 50)
	_chk("E.07 a zero level is floored at 1, not free", ow.whiteout_payout(0) == 24)

	# ⚠️ CLAMPED TO WHAT THE PLAYER HOLDS — source's own
	# `if (!IsEnoughMoney(..)) money = GetMoney()`. The returned figure is the
	# REAL amount taken, which is what any message would have to report.
	OverworldSession.wallet = Wallet.new()
	OverworldSession.wallet.earn(100)
	_chk("E.08 a poor player loses only what they have",
			ow.whiteout_payout(50) == 100)
	OverworldSession.wallet = Wallet.new()
	_chk("E.09 a broke player loses nothing rather than going negative",
			ow.whiteout_payout(50) == 0)

	# The outcome carries what the field needs, because there is no persistent
	# party to read a level back off.
	var won := BattleOutcome.make(BattleOutcome.WON, "T", 1900, 12)
	_chk("E.10 an outcome carries the prize and the party level",
			won.prize_money == 1900 and won.highest_party_level == 12)
	_chk("E.11 and defaults harmlessly when neither is supplied",
			BattleOutcome.make(BattleOutcome.LOST).prize_money == 0
			and BattleOutcome.make(BattleOutcome.LOST).highest_party_level == 1)
	ow.free()
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()


## --- F. [Bugfix, "don't whiteout and heal"] a LOSS carrying the heal-after
## flag continues the calling script instead of whiting out ---
##
## Source: `CB2_EndTrainerBattle` (`battle_setup.c:1444-1465`) — a LOSS with
## `RIVAL_BATTLE_HEAL_AFTER` set heals the party and falls through to the
## SAME continuation a win gets; without it, a loss is a real whiteout.
## Route22's own early-rival battle passes flags=0 (unaffected, already
## correct); only the Pallet Town Lab tutorial battle passes
## RIVAL_BATTLE_TUTORIAL and needed this.
func _test_heal_after_loss() -> void:
	# `_setup_scripting` is what wires `_driver._ow`, which `_abandon_script`
	# (the discriminator's own whiteout path, below) needs to run without
	# crashing on a null `_ow._box` access — cheap and idempotent to call
	# once here rather than adding a second, fragile way to reach it.
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# ⚠️ NOT `_setup_scripting()` — that also loads the full script corpora,
	# audio, and the message box, none of which this test needs, and it hung
	# the suite outright when tried (never even reached its own first print).
	# `_abandon_script()`'s own `_driver.abandon()` needs only `_driver._ow`
	# to be a real object — `_ow._box` stays at its safe `null` default, so
	# `abandon()`'s own `if _ow._box != null:` guard skips cleanly.
	ow._driver._ow = ow

	# A real, damaged party — healing has to be OBSERVABLE, not just "the
	# function ran". Fainted AND poisoned, so F.02 cannot pass by accident.
	OverworldSession.party = OverworldParty.build_debug_player_party()
	var mon: BattlePokemon = OverworldSession.party.members[0]
	mon.current_hp = 0
	mon.fainted = true
	mon.status = BattlePokemon.STATUS_POISON
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
	OverworldSession.wallet.earn(500)

	var vm := ScriptVM.new(null, OverworldSession.flags)
	vm.pause_reason = ScriptVM.Pause.WAIT_BATTLE
	vm.pending_battle_heal_after = true
	vm.pending_battle_always_continues = true
	ow._vm = vm

	OverworldSession.set_result(BattleOutcome.make(BattleOutcome.LOST, "TRAINER_TUTORIAL", 0, 5))
	var whiteout: bool = ow._apply_battle_result()

	_chk("F.01 a heal-after loss reports NO whiteout owed", not whiteout)
	_chk("F.02 the party is actually healed, not just the function called",
			mon.current_hp == mon.max_hp and not mon.fainted)
	_chk("F.03 ⚠️ Rob's own call: the trainer is NOT marked defeated for this",
			not ow.flags.trainer_defeated("TRAINER_TUTORIAL"))
	_chk("F.04 and no money changes hands on this path",
			OverworldSession.wallet.money == 500)
	_chk("F.05 the script is left able to continue, not stopped",
			vm.pause_reason != ScriptVM.Pause.DONE)

	# --- discriminator: the SAME loss WITHOUT heal-after still whitesouts ---
	# Proves F.01-F.05 are actually reading the flag, not just always passing.
	OverworldSession.party = OverworldParty.build_debug_player_party()
	var mon2: BattlePokemon = OverworldSession.party.members[0]
	mon2.current_hp = 0
	mon2.fainted = true
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
	OverworldSession.wallet.earn(500)
	var vm2 := ScriptVM.new(null, OverworldSession.flags)
	vm2.pause_reason = ScriptVM.Pause.WAIT_BATTLE
	vm2.pending_battle_heal_after = false
	vm2.pending_battle_always_continues = true
	ow._vm = vm2
	OverworldSession.set_result(BattleOutcome.make(BattleOutcome.LOST, "TRAINER_REAL", 0, 5))
	var whiteout2: bool = ow._apply_battle_result()
	_chk("F.06 the same loss WITHOUT heal-after still whitesout — the flag is what decides",
			whiteout2)
	_chk("F.07 and DOES charge money, unlike the heal-after path",
			OverworldSession.wallet.money < 500)
	_chk("F.08 the party is left as the battle left it (a real whiteout heals separately)",
			mon2.current_hp == 0 and mon2.fainted)

	ow.free()
	OverworldSession.party = null
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()


## --- G. [Bugfix, rolled in] DowngradeBadPoison ---
##
## Source: `DowngradeBadPoison` (`battle_setup.c:633`) — called on every
## post-battle path that reaches the field (won, heal-after loss), never on
## a real whiteout. TOXIC resets to plain POISON; the escalation counter
## resets with it since it means nothing for plain poison.
func _test_downgrade_bad_poison() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# ⚠️ NOT `_setup_scripting()` — that also loads the full script corpora,
	# audio, and the message box, none of which this test needs, and it hung
	# the suite outright when tried (never even reached its own first print).
	# `_abandon_script()`'s own `_driver.abandon()` needs only `_driver._ow`
	# to be a real object — `_ow._box` stays at its safe `null` default, so
	# `abandon()`'s own `if _ow._box != null:` guard skips cleanly.
	ow._driver._ow = ow

	# --- a WIN downgrades a toxic party member ---
	OverworldSession.party = OverworldParty.build_debug_player_party()
	var mon: BattlePokemon = OverworldSession.party.members[0]
	mon.status = BattlePokemon.STATUS_TOXIC
	mon.toxic_counter = 3
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
	var vm := ScriptVM.new(null, OverworldSession.flags)
	vm.pause_reason = ScriptVM.Pause.WAIT_BATTLE
	ow._vm = vm
	OverworldSession.set_result(BattleOutcome.make(BattleOutcome.WON, "TRAINER_X"))
	ow._apply_battle_result()
	_chk("G.01 a WIN downgrades TOXIC to plain POISON",
			mon.status == BattlePokemon.STATUS_POISON)
	_chk("G.02 and resets the escalation counter, meaningless for plain poison",
			mon.toxic_counter == 0)

	# --- discriminator: a REAL whiteout (no heal-after) does NOT downgrade —
	# it returns before ever reaching the shared downgrade call, and a real
	# whiteout heals everything separately anyway, making the point moot. ---
	OverworldSession.party = OverworldParty.build_debug_player_party()
	var mon2: BattlePokemon = OverworldSession.party.members[0]
	mon2.status = BattlePokemon.STATUS_TOXIC
	mon2.toxic_counter = 3
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
	var vm2 := ScriptVM.new(null, OverworldSession.flags)
	vm2.pause_reason = ScriptVM.Pause.WAIT_BATTLE
	vm2.pending_battle_heal_after = false
	ow._vm = vm2
	OverworldSession.set_result(BattleOutcome.make(BattleOutcome.LOST, "TRAINER_Y"))
	ow._apply_battle_result()
	_chk("G.03 a real whiteout leaves status untouched (it returns before the downgrade)",
			mon2.status == BattlePokemon.STATUS_TOXIC and mon2.toxic_counter == 3)

	ow.free()
	OverworldSession.party = null
	OverworldSession.flags = FlagStore.new()
	OverworldSession.wallet = Wallet.new()
