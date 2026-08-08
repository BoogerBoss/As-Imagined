class_name NameUsage
extends RefCounted

## [M27Q Q4] "Is this name taken, how often, and where?"
##
## ⚠️ **THIS IS NOT AN ALLOCATOR, AND THE DIFFERENCE IS THE WHOLE POINT.**
## HexManiacAdvance scans for the next unused flag from `0x21` because a GBA
## save is a fixed bit array you can exhaust. `FlagStore` keys on FREE-FORM
## STRINGS — there is no pool and nothing to allocate. The real failure here is
## the inverse: silently REUSING a name. Author `FLAG_HIDE_ROUTE22_SIGN`, and
## if Kanto already uses it, the new NPC and a Route 22 event share state with
## nothing reporting it. `EventRegistry.merge_into` refuses colliding SCRIPT
## LABELS loudly; flags and vars have no such guard.
##
## Measured over the corpus: **1,004 distinct `FLAG_*` and 236 distinct `VAR_*`
## names**, across 16 name families with five or more members. Not a namespace
## anyone holds in their head.
##
## ⚠️ **THE RULES LIVE HERE, THE BUTTON LIVES IN THE PLUGIN** — the same split
## `ScriptPreview` uses, for the reason `plugin.gd` records: that addon is the
## project's one surface with no automated coverage.

## ⚠️ **NAMES THAT ARE SUPPOSED TO BE SHARED, AND WHY THE AUDIT WOULD BE
## USELESS WITHOUT THIS.** Authored scripts legitimately reference two
## reference-defined registers: `VAR_RESULT`, source's own result register that
## every yes/no box writes to, and `VAR_TEMP_*`, chosen precisely BECAUSE a
## temp var clears on map change (see `PalletTownEvents`' own note). Both also
## appear in the imported corpus, correctly — sharing them IS the mechanism.
##
## Without this exemption the audit reports two permanent false positives, and
## a tool that cries wolf on a 1,004-name corpus gets ignored, which costs more
## than never building it. Extend the list rather than widening the rule: each
## entry should be a register source itself defines as shared.
const SHARED_REGISTERS := ["VAR_RESULT"]
const SHARED_PREFIXES := ["VAR_TEMP_"]

## The namespace authored names live in — settled 2026-08-08, Rob's call.
## Measured: ZERO of the imported 1,004 flag names begin with this, so it is a
## clean namespace by measurement rather than by hope.
const AUTHORED_PREFIX := "FLAG_AUTHORED_"

## Where placements live. Scanned as TEXT rather than by instantiating scenes:
## the baked `.tscn` is the hand-editable source of truth (M27M's own
## scene-as-truth decision), loading 32 of them to read two string fields would
## be far slower, and a scene that fails to instantiate would silently drop its
## placements from the answer.
const MAPS_DIR := "res://scenes/maps/"


## True for a register source defines as shared, which must never be reported
## as a collision.
static func is_shared_register(name: String) -> bool:
	if SHARED_REGISTERS.has(name):
		return true
	for p in SHARED_PREFIXES:
		if name.begins_with(p):
			return true
	return false


## Every reference to `name`, wherever it appears.
##
## Returns:
##   name       — as queried
##   count      — total references found
##   locations  — [{ "where": String, "detail": String }]
##   shared     — a reference-defined register; overlap is expected, not a bug
##   authored   — follows the FLAG_AUTHORED_<MAP>_<THING> convention
##   verdict    — "free" / "yours" / "shared" / "taken"
static func lookup(name: String) -> Dictionary:
	var out := {
		"name": name, "count": 0, "locations": [],
		"shared": is_shared_register(name),
		"authored": name.begins_with(AUTHORED_PREFIX),
		"imported_refs": 0,
		"verdict": "free",
	}
	if name == "":
		return out

	for loc in _scan_ops(name):
		out["locations"].append(loc)
		# Counted separately so the verdict can ask "did anything I did NOT
		# write reach this name", which is the only question that matters for
		# an authored one.
		if not EventRegistry.has(str(loc["where"])):
			out["imported_refs"] = int(out["imported_refs"]) + 1
	for loc in _scan_placements(name):
		out["locations"].append(loc)
	# A text label is DEFINED by the corpus as well as referenced by it — worth
	# saying, because "0 uses" on a name that exists as a text row means the
	# dialogue is orphaned rather than free.
	if ScriptPreview.texts_index().has(name):
		out["locations"].append({
			"where": "data/map_texts.json",
			"detail": "defined as dialogue (%d page(s))"
					% (ScriptPreview.texts_index()[name] as Array).size(),
		})
	if ScriptPreview.ops_index().has(name):
		out["locations"].append({
			"where": "script corpus",
			"detail": "defined as a script label",
		})

	out["count"] = (out["locations"] as Array).size()
	out["verdict"] = _verdict(out)
	return out


## ⚠️ Severity depends on WHOSE name it is, which is why the convention and the
## checker are one feature rather than two. An imported name used many times is
## just Kanto working. An AUTHORED name reached by anything you did not write is
## the actual bug this exists to catch.
##
## ⚠️ **DELIBERATELY NOT A COUNT THRESHOLD.** The first cut said an authored
## name was "yours" at ≤2 references, which is wrong the moment your own script
## uses it three times — it would start reporting your own flag as stolen. The
## question is not how many references exist but whether any of them come from
## a script you did not author.
static func _verdict(r: Dictionary) -> String:
	if r["shared"]:
		return "shared"
	if int(r["count"]) == 0:
		return "free"
	if bool(r["authored"]):
		return "taken" if int(r["imported_refs"]) > 0 else "yours"
	return "taken"


## ⚠️ `imported_only` EXISTS BECAUSE THE FIRST VERSION CRIED WOLF ON ITS OWN
## FIRST CUSTOMER. `ScriptPreview.ops_index()` merges authored scripts INTO the
## corpus index — deliberately, so the preview resolves labels exactly as the
## running game does — which means an authored flag's own `setflag`/
## `goto_if_set` look identical to corpus hits. The audit reported
## `FLAG_AUTHORED_PALLETTOWN_SEA_BREEZE_READ` as "collides with 2 corpus
## references" when both were its own. `EventRegistry.has(label)` is what tells
## the two apart.
static func _scan_ops(name: String, imported_only: bool = false) -> Array:
	var out := []
	for label in ScriptPreview.ops_index():
		if imported_only and EventRegistry.has(str(label)):
			continue
		for o in ScriptPreview.ops_index()[label]:
			var op := str((o as Dictionary).get("op", ""))
			for a in (o as Dictionary).get("args", []):
				if str(a) == name:
					out.append({"where": str(label), "detail": op})
	return out


## `visibility_flag`, `trainer_key` and `script_label` on placed entities, read
## straight out of the baked scene text.
static func _scan_placements(name: String) -> Array:
	var out := []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return out
	var needle := '= "%s"' % name
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var src := FileAccess.open(MAPS_DIR + f, FileAccess.READ)
		if src == null:
			continue
		var text := src.get_as_text()
		src.close()
		if not text.contains(needle):
			continue
		# Report the FIELD, not just the file — "used in Route3" is far less
		# actionable than "used as a visibility_flag in Route3".
		for line in text.split("\n"):
			if line.ends_with(needle):
				out.append({
					"where": f.trim_suffix(".tscn"),
					"detail": line.split(" =")[0],
				})
	return out


## Every invented name in `scripts/events/`, checked against the convention and
## against the corpus. The safety net the convention exists to make cheap.
##
## Returns a list of problems only — an empty array means everything authored
## is correctly namespaced and collision-free.
static func audit_authored() -> Array:
	var problems := []
	var dir := DirAccess.open("res://scripts/events")
	if dir == null:
		return problems
	var seen := {}
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.open("res://scripts/events/" + f, FileAccess.READ)
		if src == null:
			continue
		var text := src.get_as_text()
		src.close()
		var re := RegEx.create_from_string('"((?:FLAG|VAR)_[A-Z0-9_]+)"')
		for m in re.search_all(text):
			var nm := m.get_string(1)
			if seen.has(nm):
				continue
			seen[nm] = true
			# Deliberately shared — never a problem. See SHARED_REGISTERS.
			if is_shared_register(nm):
				continue
			if not nm.begins_with(AUTHORED_PREFIX):
				problems.append({
					"name": nm, "file": f,
					"problem": "does not use the %s<MAP>_<THING> convention"
							% AUTHORED_PREFIX,
				})
				continue
			# Correctly namespaced, but still worth confirming nothing imported
			# reached the same name.
			var hits := _scan_ops(nm, true).size()
			if hits > 0:
				problems.append({
					"name": nm, "file": f,
					"problem": "collides with %d corpus reference(s)" % hits,
				})
	return problems
