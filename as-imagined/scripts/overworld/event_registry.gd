class_name EventRegistry
extends RefCounted

## [M27G G6] Authored scripts, merged into the same table imported ones live in.
##
## The point of the whole front-end is that `ScriptVM` cannot tell the two
## apart. This is where that is made true: `ScriptDriver.setup` loads
## `map_scripts.json` and then merges whatever is registered here, so an
## authored script can be `goto`'d from an imported one and vice versa — they
## are the same op list in the same dictionary.
##
## ⚠️ **A COLLISION FAILS LOUDLY AND THE IMPORTED SCRIPT WINS.** Two definitions
## of one label is a real conflict, and silent shadowing is the worst possible
## resolution: the imported corpus is 17,137 labels nobody reads end to end, so
## an authored script accidentally reusing a name would look like it worked
## while actually replacing content somewhere across Kanto. Refusing the merge
## and naming the label is the recoverable direction — the same fail-closed
## reasoning `ScriptVM`'s own money handling uses, and the same
## kill-the-bug-class discipline as `gen_trainer_data.py`'s normalize() guard.


## label -> ops. Authored content only; imported content never comes through here.
static var _scripts: Dictionary = {}

## Labels that collided with the imported corpus, for the test and the overlay.
static var _rejected: PackedStringArray = PackedStringArray()

## ⚠️ **THERE IS DELIBERATELY NO TEXT REGISTRY HERE.** G6's first cut had one;
## it was removed the same day. Every line of dialogue in the game — imported
## and authored alike — lives in `field_script_source/`, per
## `docs/field_script_authoring.md`'s standing decision that there is no
## separate text-source tree. Authored lines go in
## `field_script_source/data/scripts/authored_text.inc`; an authored script
## then names the label exactly as an imported one does, and
## `verify_text` below checks at boot that it resolves.
##
## The friction this front-end exists to remove is writing script LOGIC in
## assembler with no type checking. Text is just strings — no types to check,
## no autocomplete to gain — so registering it here reached past the problem
## and cost a second place to grep for a line.
## Register one authored script.
##
## `ops` is what `EventScript.end()` / `.ret()` / `.build()` or `Move.done()`
## returns — a plain Array of `{"op":..., "args":[...]}`.
static func register(label: String, ops: Array) -> bool:
	if label == "" or ops.is_empty():
		push_warning("EventRegistry: refusing to register '%s' (empty)" % label)
		return false
	if _scripts.has(label):
		push_warning("EventRegistry: '%s' is registered twice — keeping the first" % label)
		return false
	_scripts[label] = ops
	return true


static func has(label: String) -> bool:
	return _scripts.has(label)


static func labels() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _scripts:
		out.append(str(k))
	out.sort()
	return out


## Merge every authored script into a loaded corpus, in place.
##
## Returns the number merged. Anything colliding with an imported label is
## REFUSED, recorded in `rejected()`, and reported — see the class doc comment.
static func merge_into(ops_by_label: Dictionary) -> int:
	_rejected = PackedStringArray()
	var merged := 0
	for label in _scripts:
		if ops_by_label.has(label):
			_rejected.append(str(label))
			# ⚠️ `push_warning`, NOT `push_error`, and the reason is precedent
			# rather than taste: a collision is a HANDLED, TESTED degrade, and
			# `run_overworld_tests.sh` fails any run containing an ERROR line —
			# so pushing an error here would make the collision test unrunnable.
			# `SaveManager.read` records the identical call for the identical
			# reason (it uses `JSON.new().parse()` precisely because
			# `JSON.parse_string` pushes an engine error on a corrupt file it is
			# designed to handle). Loudness is preserved by the warning plus
			# `rejected()`, which is the programmatic record a caller can act on.
			push_warning("EventRegistry: authored label '%s' collides with an "
					% label + "imported script — the imported one is kept. Rename it.")
			continue
		ops_by_label[label] = _scripts[label]
		merged += 1
	return merged


## Labels refused by the last `merge_into` because they already existed.
static func rejected() -> PackedStringArray:
	return _rejected


## [M27G G6 follow-up] Every text label the authored scripts reference, that
## the corpus does not define. Empty is the healthy answer.
##
## ⚠️ Catches at BOOT what would otherwise surface mid-conversation as the VM's
## own "no text for 'X'" diagnostic — a typo in a label is the one thing the
## GDScript front-end cannot type-check, because the label is a string naming
## a row in a corpus compiled by a separate tool.
static func verify_text(texts: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	for label in _scripts:
		for op in _scripts[label]:
			if str(op.get("op", "")) != "message":
				continue
			var args: Array = op.get("args", [])
			if args.is_empty():
				continue
			var key := str(args[0])
			if not texts.has(key) and not missing.has(key):
				missing.append(key)
	return missing


## Tests only.
static func clear() -> void:
	_scripts.clear()
	_rejected = PackedStringArray()
