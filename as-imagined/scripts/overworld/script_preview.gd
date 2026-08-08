class_name ScriptPreview
extends RefCounted

## [M27Q Q3] Resolve a `script_label` into a readable op listing and its
## dialogue, for the entity Inspector panel.
##
## ⚠️ **THE LOGIC LIVES HERE, NOT IN THE PLUGIN, AND THAT IS THE PROJECT'S OWN
## RULE RATHER THAN A PREFERENCE.** `addons/map_overlay_editor/plugin.gd` says
## it plainly: the plugin is this project's one surface with no automated
## coverage, and it has already shipped three defects (the editor clip-rect
## bug, click-to-select disabling itself, the save stall). Everything with a
## rule in it — chain-following, loop protection, truncation, text lookup —
## is therefore on this side of the boundary where a headless suite can drive
## it, and the plugin is left with nothing to render but the result.
##
## ⚠️ **RAW OPS, NOT PRETTY-PRINTED — Rob's call, 2026-08-08.** A friendlier
## rendering (`if FLAG_X is set → Label_Y`) would be a SECOND place in the
## codebase that has to understand opcode semantics, and `ScriptVM.step()`'s
## set grows by stages — so it would go stale silently, showing confident
## English about an opcode whose meaning had moved. One line per op, verbatim.

## The corpus is 8.6 MB / 17,159 labels and measures 28 ms to read plus 198 ms
## to parse. Fine once per editor session; not fine per selection change, and
## the Inspector re-parses properties often.
const SCRIPTS_PATH := "res://data/map_scripts.json"
const TEXTS_PATH := "res://data/map_texts.json"

## ⚠️ Both caps exist because a real corpus label can be pathological, not as
## defensive decoration. Measured across all 17,159 labels: the median program
## is **6 ops**, p90 is **14**, and the longest is **622** — and `call` appears
## 4,352 times, so chains are the norm rather than the exception. A panel that
## rendered the 622-op outlier in full would be unreadable and would stall the
## Inspector; one that followed chains without a depth cap would walk a large
## fraction of Kanto from a single signpost.
const MAX_DEPTH := 6
const MAX_LINES := 240

static var _ops_index: Dictionary = {}
static var _texts_index: Dictionary = {}
static var _built := false


## label -> Array of `{"op":..., "args":[...]}`, imported and authored alike.
##
## ⚠️ **FAILS OPEN.** An unreadable corpus yields an EMPTY index, and every
## caller then reports "unknown" rather than "broken" — the same choice
## `OverworldEntity._script_labels()` makes, and for the same reason: a
## validator that cannot see the corpus would otherwise condemn every entity
## on every map at once, burying the one real problem in 2,386 false ones.
static func ops_index() -> Dictionary:
	_build()
	return _ops_index


## label -> Array of page strings.
static func texts_index() -> Dictionary:
	_build()
	return _texts_index


static func _build() -> void:
	if _built:
		return
	_built = true
	_ops_index = _read_dict(SCRIPTS_PATH)
	_texts_index = _read_dict(TEXTS_PATH)
	# Authored scripts are GDScript, not corpus rows, and `EventRegistry` is
	# populated at RUNTIME by `ScriptDriver.setup` — so in the editor it is
	# empty unless something fills it. `register_all` is static, builds plain
	# op arrays, and `register` keeps the first registration rather than
	# erroring on a repeat, so calling it here is safe and idempotent.
	if EventRegistry.labels().is_empty():
		AuthoredEvents.register_all()
	# ⚠️ `merge_into` rather than a hand-rolled copy: it is the SAME call
	# `ScriptDriver.setup` makes in production, so the preview resolves a label
	# exactly as the running game would — including refusing a label that
	# collides with the imported corpus and letting the imported one win. A
	# bespoke merge here would be a second answer to "which script is this",
	# and the panel exists to be trusted about precisely that.
	EventRegistry.merge_into(_ops_index)


static func _read_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## Tests only — production builds once and holds for the session.
static func reset_cache() -> void:
	_built = false
	_ops_index = {}
	_texts_index = {}


## Everything the panel draws for one label.
##
## Returns:
##   found      — the label resolves at all
##   lines      — the raw op listing, one entry per op, chain-indented
##   dialogue   — [{ "label": String, "pages": PackedStringArray }] in the
##                order the script would say them
##   truncated  — a cap was hit, so the listing is partial
##   authored   — the entry label came from `scripts/events/`, not the corpus
##                (the jump-to-source button is authored-only, Rob's call)
static func build(label: String) -> Dictionary:
	var out := {
		"found": false, "lines": PackedStringArray(), "dialogue": [],
		"truncated": false, "authored": false,
	}
	if label == "":
		return out
	var ops: Dictionary = ops_index()
	if ops.is_empty() or not ops.has(label):
		return out
	out["found"] = true
	out["authored"] = EventRegistry.has(label)

	# ⚠️ VISITED IS KEYED ON LABEL AND IS NEVER CLEARED between branches. A
	# script that `goto`s back to a label already shown is a loop, and the
	# corpus genuinely contains them (retry prompts jump back to their own
	# question). Clearing per-branch would make the panel hang on the first
	# one instead of showing it once and marking it.
	var visited := {}
	_walk(label, ops, visited, 0, out)
	return out


static func _walk(label: String, ops: Dictionary, visited: Dictionary,
		depth: int, out: Dictionary) -> void:
	if visited.has(label):
		out["lines"].append("%s↳ %s  (already shown above)" % [_indent(depth), label])
		return
	if depth > MAX_DEPTH:
		out["lines"].append("%s↳ %s  (depth limit)" % [_indent(depth), label])
		out["truncated"] = true
		return
	if out["lines"].size() >= MAX_LINES:
		out["truncated"] = true
		return
	visited[label] = true

	var pad := _indent(depth)
	out["lines"].append("%s%s:" % [pad, label])
	for op_entry in ops.get(label, []):
		if out["lines"].size() >= MAX_LINES:
			out["truncated"] = true
			return
		var op := str((op_entry as Dictionary).get("op", ""))
		var args: Array = (op_entry as Dictionary).get("args", [])
		var text := op if args.is_empty() else "%s  %s" % [op, ", ".join(_strs(args))]
		out["lines"].append("%s    %s" % [pad, text])

		# Dialogue, in the order it would be said. `msgbox` is accepted too
		# even though the compiler expands it to `message` before this ever
		# sees it — a hand-authored corpus edit could reintroduce it, and
		# silently showing no dialogue would look like the script having none.
		if (op == "message" or op == "msgbox") and args.size() > 0:
			var tl := str(args[0])
			out["dialogue"].append({"label": tl, "pages": _pages_for(tl)})

		# ⚠️ CHAIN TARGETS ARE FOUND BY LOOKUP, NOT BY AN OPCODE WHITELIST.
		# Any argument that is itself a known label is followed. A whitelist
		# would have to name goto/call and all eight conditional variants, and
		# would silently stop following the next branching opcode a stage adds
		# — the same "the list grew and nobody updated the other list" failure
		# that cost 80 trainers their CHECK_VIABILITY.
		for a in args:
			var target := str(a)
			if target != label and ops.has(target):
				_walk(target, ops, visited, depth + 1, out)


static func _pages_for(text_label: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in texts_index().get(text_label, []):
		out.append(str(p))
	return out


static func _strs(a: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for x in a:
		out.append(str(x))
	return out


static func _indent(depth: int) -> String:
	return "  ".repeat(depth)
