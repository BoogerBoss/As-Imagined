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

## [M27G G6] Authored dialogue. label -> Array of pages.
##
## ⚠️ **AUTHORED TEXT LIVES BESIDE AUTHORED OPS, NOT IN `map_texts.json`.** That
## file is generated from `field_script_source/` and a hand edit to it is
## discarded on the next regenerate — the exact trap
## `docs/field_script_authoring.md` records as a standing rule. Registering
## pages here is what lets an authored script change a line with no Python step
## at all, which is half the point of the front-end.
static var _texts: Dictionary = {}


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


## Register dialogue for an authored script. `pages` is one entry per page —
## the same shape `ScriptSource.pages_for` hands the message box, where `\n` is
## a line break within a page and a new entry is a new page.
static func register_text(label: String, pages: Array) -> bool:
	if label == "" or pages.is_empty():
		push_warning("EventRegistry: refusing to register text '%s' (empty)" % label)
		return false
	if _texts.has(label):
		push_warning("EventRegistry: text '%s' is registered twice — keeping the first"
				% label)
		return false
	_texts[label] = pages
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


## Merge authored dialogue into a loaded text corpus, in place. Same
## collision rule as `merge_into`: an imported line wins and the clash is
## reported, because silently replacing a line of Kanto's dialogue from an
## authored file is exactly as bad as replacing one of its scripts.
static func merge_texts_into(texts: Dictionary) -> int:
	var merged := 0
	for label in _texts:
		if texts.has(label):
			_rejected.append(str(label))
			push_warning("EventRegistry: authored text '%s' collides with an "
					% label + "imported line — the imported one is kept. Rename it.")
			continue
		texts[label] = _texts[label]
		merged += 1
	return merged


## Labels refused by the last `merge_into` because they already existed.
static func rejected() -> PackedStringArray:
	return _rejected


## Tests only.
static func clear() -> void:
	_scripts.clear()
	_texts.clear()
	_rejected = PackedStringArray()
