extends Node

# [M36D] The coverage report — a TOOL, not a test. It answers the only two
# questions batch sequencing needs:
#
#   1. Where does coverage stand, per batch tier?
#   2. What should be ported NEXT to move it the most?
#
# Question 2 is why this exists rather than a plain blocker count. Because a
# move plays only when EVERY behavior its script reaches is ported (M36C's
# structural finding), the most-referenced behavior is often a poor next
# choice — it may be the one behavior a hundred moves share while each of
# them still needs five others. The greedy pass below instead asks "which
# behavior, if ported, would COMPLETE the most moves", and then repeats,
# which is the question that actually predicts coverage movement.
#
# Run:
#   godot --headless --path <project> scenes/battle/m36_coverage_report.tscn
#
# Tiers follow Rob's decision 5 (2026-07-29): iconic Gen 1-3 first, then the
# rest of Gen 1-3, then everything else. Generation boundaries are taken from
# the reference's own enum: Gen 1-3 is move ids 1..354 (MOVE_PSYCHO_BOOST is
# 354 and MOVES_COUNT_GEN3 follows it).

const GEN3_LAST_MOVE_ID := 354

# The iconic set. This is an explicit editorial judgment -- there is no
# "iconic" flag in any data source -- so the criteria are written down and the
# list is auditable rather than tacit:
#
#   (a) the elemental headline attacks every player recognises by name,
#   (b) the Gen 1-3 status moves that defined battling in that era,
#   (c) signature moves of starters and famous legendaries,
#   (d) TM staples with unmistakable animations.
#
# Deliberately NOT included: moves whose animation is a plain hitsplat with no
# distinguishing effect -- they are already covered by the shared machinery
# and add nothing to a showcase batch.
const ICONIC_GEN13 := {
	# (a) elemental headliners
	52: "Ember", 53: "Flamethrower", 126: "Fire Blast", 172: "Flame Wheel",
	55: "Water Gun", 56: "Hydro Pump", 57: "Surf", 61: "Bubble Beam",
	58: "Ice Beam", 59: "Blizzard", 62: "Aurora Beam",
	84: "Thunder Shock", 85: "Thunderbolt", 87: "Thunder", 86: "Thunder Wave",
	22: "Vine Whip", 75: "Razor Leaf", 76: "Solar Beam", 74: "Growth",
	89: "Earthquake", 90: "Fissure", 91: "Dig",
	94: "Psychic", 100: "Teleport", 60: "Psybeam",
	# (b) era-defining status
	73: "Leech Seed", 79: "Sleep Powder", 78: "Stun Spore", 77: "Poison Powder",
	92: "Toxic", 109: "Confuse Ray", 14: "Swords Dance", 97: "Agility",
	105: "Recover", 156: "Rest", 164: "Substitute", 113: "Light Screen",
	115: "Reflect", 147: "Spore",
	# (c) signature / legendary
	63: "Hyper Beam", 245: "Extreme Speed", 246: "Ancient Power",
	347: "Aeroblast", 354: "Psycho Boost", 344: "Volt Tackle",
	# (d) TM staples with distinctive animations
	34: "Body Slam", 36: "Take Down", 38: "Double-Edge", 44: "Bite",
	46: "Roar", 65: "Slash", 70: "Strength", 88: "Rock Throw",
	157: "Rock Slide", 163: "Slash", 247: "Shadow Ball", 188: "Sludge Bomb",
	189: "Mud-Slap", 202: "Giga Drain", 216: "Return", 218: "Frustration",
	237: "Hidden Power", 240: "Rain Dance", 241: "Sunny Day",
	201: "Sandstorm", 258: "Hail", 269: "Taunt", 331: "Bullet Seed",
	337: "Dragon Claw", 349: "Dragon Dance", 352: "Water Pulse",
}


func _ready() -> void:
	if not AnimData.ensure_loaded():
		print("m36_coverage_report: DATA MISSING (%s)" % AnimData.load_error())
		get_tree().quit(1)
		return

	var registry := AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(registry)
	var dispatcher := AnimDispatcher.new(registry)

	var all_ids := _bound_move_ids()
	var iconic: Array = []
	var rest_gen13: Array = []
	var later: Array = []
	for id in all_ids:
		if ICONIC_GEN13.has(id):
			iconic.append(id)
		elif id <= GEN3_LAST_MOVE_ID:
			rest_gen13.append(id)
		else:
			later.append(id)

	print("")
	print("=== M36 coverage report ===")
	print("behaviors registered: %d" % registry.size())
	print("")
	_report_tier("TIER 1  iconic Gen 1-3", iconic, dispatcher, registry)
	_report_tier("TIER 2  remaining Gen 1-3", rest_gen13, dispatcher, registry)
	_report_tier("TIER 3  Gen 4+", later, dispatcher, registry)
	_report_tier("ALL", all_ids, dispatcher, registry)
	_list_playable(all_ids, dispatcher)
	get_tree().quit(0)


# Names every move that currently plays its real animation, so a human can
# pick one in a battle and see the port working. Ordered by move id.
func _list_playable(ids: Array, dispatcher: AnimDispatcher) -> void:
	var names := {}
	var f := FileAccess.open("res://data/moves.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Array:
			for row in parsed:
				if row is Dictionary and row.has("id") and row.has("name"):
					names[int(row["id"])] = str(row["name"])
	print("")
	print("=== PLAYABLE MOVES (these use the ported engine in a real battle) ===")
	var line := ""
	var n := 0
	for id in ids:
		if not dispatcher.can_play_move(int(id)):
			continue
		n += 1
		var label: String = "%s(%d)" % [names.get(int(id), "move"), int(id)]
		line += label.rpad(26)
		if n % 3 == 0:
			print("  " + line)
			line = ""
	if line != "":
		print("  " + line)
	print("  total: %d" % n)


func _bound_move_ids() -> Array:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	return ids


func _report_tier(title: String, ids: Array, dispatcher: AnimDispatcher,
		registry: AnimBehaviorRegistry) -> void:
	if ids.is_empty():
		return
	var cov := dispatcher.coverage(ids)
	var playable := int(cov["playable"])
	print("%s  --  %d/%d playable (%.1f%%)"
			% [title, playable, ids.size(),
				100.0 * playable / maxi(1, ids.size())])

	# Missing-behavior set per still-blocked move, for the greedy pass.
	var blocked: Dictionary = {}
	for id in ids:
		var v := dispatcher.verdict_for_move(int(id))
		if int(v.get("reason", -1)) != AnimDispatcher.Reason.MISSING_BEHAVIORS:
			continue
		var missing: Dictionary = {}
		for symbol in (v.get("missing", []) as Array):
			missing[str(symbol)] = true
		blocked[int(id)] = missing

	if blocked.is_empty():
		print("    (nothing blocked)")
		print("")
		return

	# How many moves each behavior is the SOLE remaining blocker for -- port
	# these and those moves light up immediately.
	var sole: Dictionary = {}
	for id in blocked:
		var missing: Dictionary = blocked[id]
		if missing.size() == 1:
			for symbol in missing:
				sole[symbol] = int(sole.get(symbol, 0)) + 1
	if not sole.is_empty():
		var ranked_sole: Array = _rank(sole)
		var line := "    one-away wins: "
		for i in range(mini(6, ranked_sole.size())):
			line += "%s(%d) " % [ranked_sole[i]["symbol"],
					ranked_sole[i]["count"]]
		print(line)

	# Greedy: repeatedly take the behavior that COMPLETES the most moves,
	# pretending it is ported, and see how far a short batch would get.
	var sim: Dictionary = {}
	for id in blocked:
		sim[id] = (blocked[id] as Dictionary).duplicate()
	var picks: Array = []
	var unlocked_total := 0
	for step in range(8):
		var gain: Dictionary = {}
		for id in sim:
			var missing: Dictionary = sim[id]
			if missing.size() != 1:
				continue
			for symbol in missing:
				gain[symbol] = int(gain.get(symbol, 0)) + 1
		if gain.is_empty():
			# Nothing is one-away; fall back to the behavior blocking the
			# most moves at all, which is the only way to make progress.
			var freq: Dictionary = {}
			for id in sim:
				for symbol in (sim[id] as Dictionary):
					freq[symbol] = int(freq.get(symbol, 0)) + 1
			if freq.is_empty():
				break
			var top: Dictionary = _rank(freq)[0]
			picks.append({"symbol": top["symbol"], "unlocks": 0,
					"blocks": int(top["count"])})
			_remove_symbol(sim, str(top["symbol"]))
			continue
		var best: Dictionary = _rank(gain)[0]
		var symbol := str(best["symbol"])
		var unlocked := int(best["count"])
		unlocked_total += unlocked
		picks.append({"symbol": symbol, "unlocks": unlocked, "blocks": 0})
		_remove_symbol(sim, symbol)
		for id in sim.keys():
			if (sim[id] as Dictionary).is_empty():
				sim.erase(id)

	print("    next 8 by greedy value (would add ~%d moves):" % unlocked_total)
	for p in picks:
		if int(p["unlocks"]) > 0:
			print("      +%-3d  %s" % [int(p["unlocks"]), p["symbol"]])
		else:
			print("       --   %s  (blocks %d, none one-away)"
					% [p["symbol"], int(p["blocks"])])

	# Name a few still-blocked iconic moves so the report is legible.
	if title.begins_with("TIER 1"):
		var names: Array = []
		for id in blocked:
			if names.size() >= 8:
				break
			names.append("%s(%d needs %d)" % [ICONIC_GEN13.get(id, "?"), id,
					(blocked[id] as Dictionary).size()])
		print("    still blocked: %s" % ", ".join(names))
	print("")


func _rank(counts: Dictionary) -> Array:
	var out: Array = []
	for symbol in counts:
		out.append({"symbol": symbol, "count": int(counts[symbol])})
	out.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return out


func _remove_symbol(sim: Dictionary, symbol: String) -> void:
	for id in sim:
		(sim[id] as Dictionary).erase(symbol)
