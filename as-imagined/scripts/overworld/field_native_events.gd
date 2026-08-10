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
## `native` is for PRESENTATION and ENGINE CAPABILITY, never **flags, vars, or
## control flow**. A handler may return a value into VAR_RESULT — answering a
## question the script then branches on — but must not set a flag, write a var,
## or decide what happens next.
##
## ⚠️ Handlers MAY drive engine-owned state that no opcode represents — the Oak
## handlers below write `PlayerIdentity`, because source does naming in engine
## code and there is no script command to be faithful to. See
## `NativeEventRegistry`'s header for the full refinement (G7, Rob's call).


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
	# [M27R 7a-1] `waitfanfare` / `waitse`. Routed here rather than given their
	# own pause kinds, the same call `multichoicegrid` and `fadescreen` made.
	#
	# ⚠️ **BOTH AWAIT A SIGNAL THAT ALWAYS FIRES, WHICH IS THE G5 RULE AND NOT A
	# DETAIL.** `FieldAudio` emits `fanfare_finished`/`se_finished` deferred
	# when a cue could NOT start — an unmapped name, a missing asset, or no
	# audio device — precisely so a handler can never suspend forever. Four
	# corridor scripts play `MUS_LEVEL_UP`, which the Essentials pack has no
	# jingle for; without that guarantee every one of them would hang the scene
	# on a sound nobody can hear.
	reg.register("WaitFanfare", func(driver, _args) -> Variant:
		var a = driver.scene().field_audio()
		if a == null or not a.is_fanfare_playing():
			return null
		await a.fanfare_finished
		return null)
	reg.register("WaitSe", func(driver, _args) -> Variant:
		var a = driver.scene().field_audio()
		if a == null or not a.is_se_playing():
			return null
		await a.se_finished
		return null)
	reg.register("Wait", func(driver, args) -> Variant:
		var seconds := 0.5
		if args.size() > 0:
			seconds = maxf(0.0, float(str(args[0])) / 60.0)
		await driver.scene().get_tree().create_timer(seconds).timeout
		return null)


	# --- [M27G G7] Oak's speech -----------------------------------------------
	#
	# ⚠️ **EVERY DIVERGENCE `[M27K K-b]` RECORDED IS PRESERVED HERE**, and each
	# is Rob's own call rather than a simplification — a later session comparing
	# against `oak_speech.c` will find all three and must not "restore" them:
	#
	#   * the gender question shows Red and Leaf SIDE BY SIDE and picking a look
	#     IS the answer. Source shows no portrait during the choice at all —
	#     Oak's slides off, then a bare 2-line text menu asks BOY/GIRL.
	#   * the ball releases a RANDOM roster species, not source's fixed
	#     Nidoran♀, fully random across all 386 including legendaries.
	#   * gender is asked BEFORE the name, which is load-bearing rather than
	#     cosmetic: `PlayerIdentity.name_choices()` keys its preset list on it.
	reg.register("OakFadeIn", func(driver, _args) -> Variant:
		await driver.scene()._oak_overlay.fade_in()
		return null)
	reg.register("OakFadeOut", func(driver, _args) -> Variant:
		await driver.scene()._oak_overlay.fade_out()
		return null)
	# `oak` / `red` / `leaf` / `rival`. Instant, so nothing to await.
	reg.register("OakPortrait", func(driver, args) -> Variant:
		driver.scene()._oak_overlay.show_solo(str(args[0]) if args.size() > 0 else "oak")
		return null)
	# ⚠️ Shows whichever portrait the player CHOSE. `_oak_overlay` cannot know
	# the gender, so the script passes it — which is why this is a separate
	# handler from OakPortrait rather than a call site deciding the string.
	reg.register("OakPortraitPlayer", func(driver, _args) -> Variant:
		driver.scene()._oak_overlay.show_solo(
			"red" if OverworldSession.identity.gender == PlayerIdentity.Gender.BOY
			else "leaf")
		return null)
	reg.register("OakBallRelease", func(driver, _args) -> Variant:
		await driver.scene()._oak_overlay.release_random_pokemon()
		return null)
	# ⚠️ WRITES IDENTITY — see the refined rule above. Returns nothing the script
	# branches on: the answer IS the state, and the very next beat reads it back
	# through OakPortraitPlayer.
	reg.register("OakPickGender", func(driver, _args) -> Variant:
		var boy: bool = await driver.scene()._oak_overlay.pick_gender()
		OverworldSession.identity.gender = PlayerIdentity.Gender.BOY if boy \
				else PlayerIdentity.Gender.GIRL
		return null)
	# ⚠️ WRITES IDENTITY, and a name cannot round-trip through VAR_RESULT (an
	# int) — which is precisely the case that forced the rule refinement. The
	# preset list is gender-keyed, which is why the gender question runs first.
	reg.register("OakAskPlayerName", func(driver, _args) -> Variant:
		var id := OverworldSession.identity
		driver.scene()._naming.open("Your name?", id.name_choices())
		id.set_name(await driver.scene()._naming.name_chosen)
		return null)
	reg.register("OakAskRivalName", func(driver, _args) -> Variant:
		var id := OverworldSession.identity
		driver.scene()._naming.open("Your rival's name?", PlayerIdentity.RIVAL_NAMES)
		id.set_rival_name(await driver.scene()._naming.name_chosen)
		return null)


	# --- [M27G G7] Saving ------------------------------------------------------
	#
	# ⚠️ Returns 1/0 and the script branches on it — a handler ANSWERING a
	# question, which the rule permits without qualification. It writes no flag
	# and no var; the save file is engine-owned state with no opcode.
	reg.register("SaveGame", func(driver, _args) -> Variant:
		var ow = driver.scene()
		var ok := SaveManager.save(OverworldSession.active_slot,
				SaveManager.build_payload(ow.manager.chunk_owning(ow._cell),
						ow._cell, ow._facing, ow._elev,
						OverworldSession.playtime_seconds()))
		# [M27R 7a-2] The save cue, on SUCCESS only — a failed write reports its
		# own failure text and must not sound like it worked. Source plays
		# `SE_SAVE` at the same moment (`hall_of_fame_frlg.c:471` among others).
		if ok and ow.field_audio() != null:
			ow.field_audio().play_se("SE_SAVE")
		return 1 if ok else 0)


	# --- [M27G G7 follow-up] Field poison -------------------------------------
	#
	# ⚠️ Buffers the next name and answers 1, or answers 0 when drained — which
	# is what lets the notice be a LOOP in the op stream instead of N pages
	# handed to a box nobody in the VM knows about. Writes only TextBuffers,
	# which is runtime-only (source's own gStringVar1) and explicitly not a
	# flag, a var, or a branch.
	# ⚠️ Writes the RUNNING VM's OWN buffers, not a fresh TextBuffers — those are
	# what `ScriptDriver.expanded_pages()` expands the corpus line through, so a
	# private instance would buffer a name nothing ever reads.
	reg.register("BufferNextPoisonSurvivor", func(driver, _args) -> Variant:
		if FieldPoison.pending_names.is_empty():
			return 0
		var next: String = FieldPoison.pending_names[0]
		FieldPoison.pending_names.remove_at(0)
		if driver.vm != null:
			driver.vm.buffers.set_slot(0, next)
		return 1)


	# --- [M27G] multichoicegrid ------------------------------------------------
	#
	# ⚠️ Returns the chosen INDEX (or MULTI_B_PRESSED) into VAR_RESULT, which is
	# what the calling script's `switch`/`case` chain reads. A handler ANSWERING
	# a question — no flag, no var, no branch — so the rule holds unqualified.
	reg.register("Multichoice", func(driver, args) -> Variant:
		var entries := MultichoiceLists.entries(str(args[0]) if args.size() > 0 else "")
		if entries.is_empty():
			return MultichoiceGrid.B_PRESSED
		# ⚠️ EXPLICIT TYPES, NOT `:=`. `args` is an untyped lambda parameter, so
		# nothing derived from it carries a type and inference fails outright —
		# the same cost the untyped `_ow` back-reference already documents in
		# ScriptDriver. A compile error rather than a silent one.
		var per_row: int = int(str(args[1])) if args.size() > 1 \
				and str(args[1]).is_valid_int() else 1
		# Source's own arg is `ignoreBPress`; TRUE means B does nothing.
		var ignore_b: bool = args.size() > 2 and str(args[2]) == "TRUE"
		var grid = driver.scene()._multichoice
		grid.open(entries, per_row, ignore_b)
		return await grid.chosen)


	# --- [M27I I6c] pokemart ---------------------------------------------------
	#
	# ⚠️ Answers nothing into `VAR_RESULT` — source's `pokemart` has no result,
	# the script simply continues after the shop closes. Returning null keeps
	# `resume_after_native` from writing a var the calling script never reads.
	reg.register("Pokemart", func(driver, args) -> Variant:
		# ⚠️ EXPLICIT TYPES, NOT `:=` — `args` is an untyped lambda parameter, so
		# nothing derived from it carries a type and inference fails outright.
		var label: String = str(args[0]) if args.size() > 0 else ""
		var shop = driver.scene()._shop_screen
		shop.open(MartStock.stock_for(label))
		await shop.closed
		return null)


	# --- [M27G] fadescreen -----------------------------------------------------
	#
	# ⚠️ FADE_FROM_* fades IN. 17 corpus uses are FADE_FROM_BLACK and would fade
	# the screen OUT if the direction were assumed rather than read.
	# FADE_TO_WHITE / FADE_FROM_WHITE (4 uses) degrade to the black fade — this
	# project has one fade colour, a disclosed simplification.
	reg.register("FadeScreen", func(driver, args) -> Variant:
		var dir: String = str(args[0]) if args.size() > 0 else "FADE_TO_BLACK"
		var to_black: bool = not dir.begins_with("FADE_FROM")
		await driver.scene()._fade_to(1.0 if to_black else 0.0)
		return null)


	# --- [Corridor tail] party-count specials ----------------------------------
	#
	# ⚠️ All four are ONE-LINE PARTY READS, and G8 is what made them cheap: each
	# is a registration rather than a Pause member plus an intercept plus an
	# answer_* method plus a driver branch. Answering into VAR_RESULT is exactly
	# what a `specialvar` call site expects.
	reg.register("CalculatePlayerPartyCount", func(_d, _a) -> Variant:
		return OverworldSession.player_party().members.size())
	# ⚠️ Identical to the above HERE, and deliberately so: this project models
	# no eggs at all (the same reason `GetTradeSpecies` and
	# `ScriptGetPartyMonSpecies` are behaviourally identical — see ScriptVM),
	# so "non-egg party members" is every party member. Registered separately
	# rather than aliased so the day eggs exist, only this one changes.
	reg.register("CountPartyNonEggMons", func(_d, _a) -> Variant:
		return OverworldSession.player_party().members.size())
	# Source: two non-fainted, non-egg mons (`HasEnoughMonsForDoubleBattle`).
	# ⚠️ Answers source's own enum, not a bool: PLAYER_HAS_TWO_USABLE_MONS 0 /
	# PLAYER_HAS_ONE_MON 1 / PLAYER_HAS_ONE_USABLE_MON 2
	# (`include/constants/battle.h`), and 0 is the AFFIRMATIVE. A bool here
	# would invert every call site.
	reg.register("HasEnoughMonsForDoubleBattle", func(_d, _a) -> Variant:
		var members: Array = OverworldSession.player_party().members
		if members.size() < 2:
			return 1
		var usable := 0
		for m in members:
			if m != null and not m.fainted:
				usable += 1
		return 0 if usable >= 2 else 2)
	# No Bad Eggs exist here — this project has no egg model and no corruption
	# path that could produce one. FALSE is genuinely correct, not a stand-in.
	reg.register("IsBadEggInParty", func(_d, _a) -> Variant:
		return 0)
