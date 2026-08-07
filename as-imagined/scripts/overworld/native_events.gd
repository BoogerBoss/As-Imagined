class_name NativeEventRegistry
extends RefCounted

## [M27G G5] Name -> Godot code, for the `native` opcode.
##
## ⚠️ **THIS IS THE ESCAPE HATCH, AND IT HAS A RULE.**
##
## > `native` is for PRESENTATION and ENGINE CAPABILITY — never for control
## > flow, never for state.
##
## The moment a handler starts setting flags and branching, the op stream stops
## being the whole story: `describe()` stops telling the truth, a frozen test
## can no longer see what a script is doing, and save state stops being
## re-derivable from flags and vars. That is the coroutine architecture
## `docs/m27g_architecture_recon.md` declined, rebuilt inside the hatch. A
## handler may RETURN a value (it lands in VAR_RESULT and the script branches on
## it, exactly like a `special`) — that is answering a question, not owning the
## decision.
##
## What belongs here: fades, camera work, tweens, particles, shaders, sprite
## flourishes, screen transitions — everything source expresses through field
## effects and `createvobject` and this project has had no way to reach.
##
## ⚠️ **A HANDLER MAY BE A COROUTINE.** `ScriptDriver._run_native` awaits it, and
## that `await` is the ONLY one in the whole script pipeline. Containing it to
## one call site is deliberate: it is the single place that has to get
## "the scene may have been torn down while we were suspended" right.
##
## Signature: `func(driver: ScriptDriver, args: Array) -> Variant`. Return null
## (or nothing) to leave VAR_RESULT alone.
##
## ⚠️ **AN INSTANCE, NOT A STATIC TABLE — and the first cut was static.**
## `FieldSpecials` is static and correct to be: it holds constants and pure
## functions. This holds **Callables**, and a `static var` Dictionary of
## lambdas outlives the GDScript that created them. Godot then aborts at
## process exit with heap corruption ("corrupted size vs. prev_size while
## consolidating", SIGABRT/134) — observed on four suites the moment the
## built-in handlers started registering from a real overworld boot.
##
## Owned by `ScriptDriver` instead, so handler lifetime matches the field
## session that registered them. That is the correct lifetime anyway: a
## handler reaches the scene through `driver.scene()`, and outliving the scene
## it reaches into was never meaningful.
var _handlers: Dictionary = {}


## ⚠️ Refuses to overwrite silently. Two registrations under one name is a
## real conflict — the second would win invisibly and the first would look
## implemented — so the first wins and the collision is reported, matching the
## fail-loudly discipline `gen_trainer_data.py`'s own normalize() guard uses.
func register(handler_name: String, fn: Callable) -> bool:
	if handler_name == "" or not fn.is_valid():
		push_warning("NativeEventRegistry: refusing to register '%s'" % handler_name)
		return false
	if _handlers.has(handler_name):
		push_warning("NativeEventRegistry: '%s' is already registered — keeping the first"
				% handler_name)
		return false
	_handlers[handler_name] = fn
	return true


func has(handler_name: String) -> bool:
	return _handlers.has(handler_name)


## The handler, or an empty Callable if none is registered. The caller halts
## and names it rather than skipping — see `ScriptDriver._run_native`.
func get_handler(handler_name: String) -> Callable:
	return _handlers.get(handler_name, Callable())


## Every registered name. For the debug overlay and for tests.
func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _handlers:
		out.append(str(k))
	out.sort()
	return out


## Tests only — production registers once at boot and never clears.
func clear() -> void:
	_handlers.clear()
