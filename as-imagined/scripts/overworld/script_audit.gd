@tool
class_name ScriptAudit
extends RefCounted

## [M27S] The static corpus audit: every symbolic argument in the compiled
## field-script corpus, checked against the resolver that will actually be
## asked to turn it into a number.
##
## ⚠️ **THE BUG CLASS THIS EXISTS FOR HAS HAPPENED SIX TIMES.**
## `ScriptVM._literal` returns **0** for a token it has no case for. Zero is a
## valid number, so nothing errors, nothing halts, and the script runs to
## completion — the comparison just quietly does the wrong thing. Every one of
## these was found by PLAYING the one scene that used it, months later, and
## every one was fixed by adding one more `match` case:
##
##   * `YES`/`NO` (753 uses) — inverted EVERY yes/no branch in the region
##   * `SPECIES_*` (295) — the starter script could not name its own Pokémon
##   * `PARTY_SIZE` (57) — every "was anything chosen" check took Decline
##   * `INGAME_TRADE_*` (13) — every trade NPC read the wrong table row
##   * `LOCALID_*` — Gary's own starter ball never disappeared
##   * `RIVAL_BATTLE_*` — the heal-after-loss branch never fired
##
## Nobody ever made the fallthrough itself fail loud. This is that.
##
## ⚠️ **IT LIVES IN GDSCRIPT, NOT `gen_map_scripts.py`, AND THE EARLIER
## RECOMMENDATION TO PUT IT THERE WAS WRONG.** That was argued from the three
## guards already in the generator (the `pokemart` stock check, trainer-key
## canonicalisation, the `normalize()` collision assert) — but every one of
## those is pure Python over data the generator itself produces. This one needs
## `_literal`, which is GDScript. Putting it in the generator would mean
## REIMPLEMENTING the resolver in Python, and two hand-kept copies of one rule
## is precisely the failure this project has already paid for once, when
## `check_bake_diff`'s normalisation drifted from `map_baker`'s and produced a
## permanent false positive. Calling the real function is the whole point.
##
## ⚠️ **REPORTS, NEVER RESOLVES.** A finding here is a question ("should this
## be a number?"), not a defect. Roughly 90% of unresolved tokens are consumed
## as STRINGS and are perfectly correct — see `STRING_CONTEXT`.


## Families whose members are consumed BY NAME and never as a number, so
## `_literal` answering 0 for them is irrelevant. Each entry is the reason,
## and each was confirmed by reading the consumer rather than assumed from the
## name — a family whitelisted on a guess is how an audit stops finding things.
const STRING_CONTEXT := {
	"LOCALID_": "object-op / applymovement target, resolved by name",
	"TRAINER_": "trainer key, via canonical_key / is_trainer_constant",
	"MAP_": "warp + connection destination, via MapConstants.map_name_for",
	"ITEM_": "resolved by _resolve_item, not _literal",
	"SE_": "audio cue name, played by name",
	"MUS_": "audio track name, played by name",
	"MOVEMENT_TYPE_": "NPC.movement_type is a String by design",
	"FADE_": "FadeScreen compares dir.begins_with('FADE_FROM')",
	"STR_VAR_": "TextBuffers slot name",
	"HEAL_LOCATION_": "RespawnPoint.set_to takes the name",
	"STDSTRING_": "bufferstdstring looks the name up",
	"OBJ_EVENT_GFX_": "graphics id, a String throughout",
	"NPC_TEXT_COLOR_": "textcolor is a no-op",
	"FAMECHECKER_": "famechecker is a no-op",
	"FLDEFF_": "dofieldeffect/waitfieldeffect are no-ops",
	"CRY_MODE_": "playmoncry takes the mode by name",
}

## Tokens whose 0 IS the right answer rather than a fallthrough.
const LEGIT_ZERO := ["FALSE", "NO", "NONE", "NULL"]


## Scan the corpus. `corridor_prefixes` are the script-label prefixes of maps
## that actually exist (`PalletTown_ProfessorOaksLab` for
## `PalletTown_ProfessorOaksLab_Frlg`); anything outside them is Hoenn, contest
## or battle-animation content this project cannot reach, and reporting it
## would bury the actionable list in thousands of rows.
##
## Returns `{"corridor": {tok: {"uses": int, "ops": PackedStringArray}},
##           "all": {tok: ...}, "scanned": int}`.
static func scan(ops_by_label: Dictionary,
		corridor_prefixes: Array) -> Dictionary:
	var all := {}
	var corridor := {}
	var scanned := 0
	for label in ops_by_label:
		var in_corridor := false
		for p in corridor_prefixes:
			if String(label).begins_with(str(p)):
				in_corridor = true
				break
		for entry in ops_by_label[label]:
			var op := str((entry as Dictionary).get("op", ""))
			for a in (entry as Dictionary).get("args", []):
				scanned += 1
				var tok := str(a)
				if not is_reportable(tok):
					continue
				_tally(all, tok, op)
				if in_corridor:
					_tally(corridor, tok, op)
	return {"corridor": corridor, "all": all, "scanned": scanned}


## Would this argument be reported? False for anything that is not a symbolic
## constant, is legitimately zero, is a store key, is whitelisted, or resolves.
static func is_reportable(tok: String) -> bool:
	if not is_symbolic(tok):
		return false
	if tok in LEGIT_ZERO:
		return false
	# `VAR_`/`FLAG_` are store KEYS — they are looked up in FlagStore, never
	# turned into a number by `_literal`, so a 0 here means nothing.
	if tok.begins_with("VAR_") or tok.begins_with("FLAG_"):
		return false
	for fam in STRING_CONTEXT:
		if tok.begins_with(fam):
			return false
	# ⚠️ THE REAL FUNCTION, deliberately. See the class comment.
	return ScriptVM._literal(tok) == 0


## A symbolic constant is SCREAMING_SNAKE. Script, movement and text labels are
## mixed case (`PalletTown_EventScript_Foo`, `Common_Movement_WalkDown`) and are
## correctly excluded by this — which is what keeps 17,159 label arguments out
## of the report.
static func is_symbolic(t: String) -> bool:
	if t == "" or t.is_valid_int():
		return false
	for i in range(t.length()):
		var c := t[i]
		if c == "_" or (c >= "0" and c <= "9"):
			continue
		if c != c.to_upper() or c == c.to_lower():
			return false
	return true


static func _tally(into: Dictionary, tok: String, op: String) -> void:
	if not into.has(tok):
		into[tok] = {"uses": 0, "ops": []}
	var e: Dictionary = into[tok]
	e["uses"] = int(e["uses"]) + 1
	if not (e["ops"] as Array).has(op):
		(e["ops"] as Array).append(op)


## The corridor's own script-label prefixes, from the maps that are baked.
static func corridor_prefixes() -> Array[String]:
	var out: Array[String] = []
	for m in MapAuthoring.baked_maps():
		out.append(m.substr(0, m.length() - 5) if m.ends_with("_Frlg") else m)
	return out


## A readable report, grouped by family. For a human running this deliberately;
## the test asserts on `scan()` itself.
static func format(findings: Dictionary) -> String:
	var fams := {}
	for tok in findings:
		var fam := str(tok).split("_")[0] + "_"
		if not fams.has(fam):
			fams[fam] = {"distinct": 0, "uses": 0, "sample": []}
		var e: Dictionary = fams[fam]
		e["distinct"] = int(e["distinct"]) + 1
		e["uses"] = int(e["uses"]) + int((findings[tok] as Dictionary)["uses"])
		if (e["sample"] as Array).size() < 3:
			(e["sample"] as Array).append(tok)
	var keys := fams.keys()
	keys.sort_custom(func(a, b): return int(fams[a]["uses"]) > int(fams[b]["uses"]))
	var out := ""
	for k in keys:
		var e: Dictionary = fams[k]
		out += "%-20s %3d distinct %5d uses   e.g. %s\n" % [k,
				int(e["distinct"]), int(e["uses"]),
				", ".join(e["sample"] as Array)]
	return out
