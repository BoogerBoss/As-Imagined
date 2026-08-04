extends Node

## [M27O O2] The loss path.
##
## Two properties matter more than the warp itself, and both are about what must
## NOT happen: the beaten-trainer flag must stay unset, and the parked script
## must not resume. Either one getting through hands out the reward for a fight
## the player lost.

const EXPECTED_TOTAL := 32

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
