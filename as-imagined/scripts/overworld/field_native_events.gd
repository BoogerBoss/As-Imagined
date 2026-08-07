class_name FieldNativeEvents
extends RefCounted

## [M27G G5] This project's own `native` handlers, in one place.
##
## The counterpart to `FieldSpecials`: that file is the single answer to "which
## `special` functions exist here", this one is the single answer to "which
## `native` handlers exist here". Kept separate from `NativeEventRegistry`
## (which is just the table) for the same reason `FieldSpecials` is separate
## from `ScriptVM` — the mechanism should not know the content.
##
## ⚠️ **THE RULE, restated because this is where it will be broken first:**
## `native` is for PRESENTATION and ENGINE CAPABILITY, never control flow and
## never state. A handler may return a value into VAR_RESULT — answering a
## question the script then branches on — but must not set flags, move the
## player, or decide what happens next.


## Register every built-in handler. Called once from `ScriptDriver.setup`.
##
## ⚠️ Idempotent by construction: `register` keeps the FIRST registration and
## warns on a duplicate. In practice each `ScriptDriver` owns its own registry
## so a rebuilt overworld gets a fresh one — but the guarantee costs nothing
## and makes double-calling harmless.
static func register_all(reg: NativeEventRegistry) -> void:
	# ⚠️ **DELIBERATELY NOT WIRED TO THE `fadescreen` OPCODE.** These are
	# reachable by NAME from an authored script (`native "FadeToBlack"`), and
	# that is all G5 claims. The imported `fadescreen` opcode stays a no-op:
	# its own doc comment in `script_vm.gd` records that in **106 of 128 corpus
	# uses the fade is never closed by another opcode** — source closes it from
	# `CB2_ReturnToFieldContinueScriptPlayMapMusic`, engine plumbing this
	# project does not have — so making that opcode fade for real would leave
	# the screen black permanently. Pairing it with the screen TRANSITION is a
	# per-call-site analysis and its own piece of work; see `docs/m27g_scope.md`
	# §5 G5's own "done when" note.
	reg.register("FadeToBlack", func(driver, _args) -> Variant:
		await driver.scene()._fade_to(1.0)
		return null)
	reg.register("FadeFromBlack", func(driver, _args) -> Variant:
		await driver.scene()._fade_to(0.0)
		return null)
	# A pause measured in frames rather than the movement runner's own ticks —
	# the shape every cinematic beat wants between two actions, and something
	# the opcode language cannot express at all (`delay` is a movement action,
	# not a script command).
	reg.register("Wait", func(driver, args) -> Variant:
		var seconds := 0.5
		if args.size() > 0:
			seconds = maxf(0.0, float(str(args[0])) / 60.0)
		await driver.scene().get_tree().create_timer(seconds).timeout
		return null)
