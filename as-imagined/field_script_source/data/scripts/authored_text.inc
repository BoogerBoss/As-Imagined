@ ============================================================================
@ AUTHORED DIALOGUE — content this project wrote, not imported.
@ ============================================================================
@
@ [M27G G6 follow-up, 2026-08-07] Every line of dialogue in the game lives in
@ this corpus, including the lines belonging to scripts authored in GDScript
@ under `scripts/events/`. That is `docs/field_script_authoring.md`'s own
@ standing decision, restated because G6 briefly broke it:
@
@     "From this point on, field_script_source/ is the real source of truth
@      for every field script and every line of dialogue in the game."
@     "Text lives INSIDE the same .inc files as the script logic that
@      references it... There is no separate text-source tree to also fork."
@
@ G6's first cut registered authored dialogue in GDScript instead
@ (EventRegistry.register_text), which created exactly the second text source
@ that note rules out. Rob's call: one corpus. The friction G6 exists to
@ remove is writing script LOGIC in assembler with no type checking — text is
@ just strings, with no types to check and no autocomplete to gain, so the
@ fix reached past the problem.
@
@ ⚠️ THIS FILE IS AUTHORED, NOT A REFERENCE COPY. Every other .inc under
@ field_script_source/ started as a byte-for-byte copy of the reference tree.
@ This one has no upstream counterpart at all — it is kept separate rather
@ than appended to a map's own scripts.inc so that "what did we write" stays
@ answerable by looking at one file.
@
@ Regenerate after editing:  python3 scripts/gen_map_texts.py
@ (No bake step — overworld.gd reads data/map_texts.json fresh at boot.)
@
@ Labels are prefixed with their map and end in a name the reference would
@ never emit, which is the convention that keeps them clear of the 11,451
@ imported ones. EventRegistry's own merge is what actually enforces it.
@ ============================================================================


@ --- Pallet Town ------------------------------------------------------------

@ ⚠️ **PLACEHOLDER TEXT, DELIBERATELY NON-CANON — Rob's call, 2026-08-07.**
@
@ These two labels belong to `PalletTownEvents`, the worked example that proves
@ the GDScript authoring front-end end to end (G6). The MECHANISM is real and
@ load-bearing — it is the only thing exercising a flag gate, corpus dialogue,
@ a `native` beat, a checkpoint and a terminator together, against the real
@ compiled corpus rather than a fixture, and six assertions in
@ `m27f_script_vm_test` (R.14-R.19) read these labels by name.
@
@ The PROSE was not. An earlier draft carried invented story content — a
@ signpost by the water, a scratched date, "a name worn too far to read" — which
@ is a deliberate narrative hook in a project whose story is Rob's to write, and
@ it should have been flagged as an idea rather than committed as content. It is
@ replaced here with text that cannot be mistaken for canon and that documents
@ the mechanism instead.
@
@ ⚠️ If this is ever wired to a real signpost, REPLACE THESE LINES FIRST. The
@ tests assert that the labels RESOLVE, never what they say, so rewriting them
@ costs nothing and breaks nothing.
PalletTown_Authored_Text_SeaBreeze::
	.string "[Authored-script test signpost.]\n"
	.string "Not game content.\p"
	.string "Reading this once sets its flag and\n"
	.string "advances its checkpoint var.$"

@ The second read, reached by the flag gate — proving the branch is taken.
PalletTown_Authored_Text_SeaBreezeShort::
	.string "[Test signpost, second read.]\n"
	.string "The gated branch was taken.$"


@ --- New game / Oak's speech ------------------------------------------------
@
@ [M27G G7] Moved out of `overworld.gd`, where these were GDScript consts read
@ by `run_new_game()`'s own `_say()` helper. That coroutine is now an authored
@ script (`NewGameEvents`), so its dialogue belongs in the corpus like every
@ other line in the game.
@
@ ⚠️ PAGE GROUPING IS LOAD-BEARING and is preserved exactly. Each label below
@ is one `_say([...])` call from the old coroutine, and `\p` marks where that
@ call's own page list split. Merging two labels, or splitting one, changes how
@ many times the player presses A through Oak's speech.
@
@ ⚠️ `{PLAYER}` and `{RIVAL}` are expanded at PRINT time by TextBuffers, not
@ here — which is what lets OAK_SO_YOUR_NAME read back a name typed seconds
@ earlier, and why the confirm/retry loop works at all.

NewGame_Text_Welcome::
	.string "Hello, there!\n"
	.string "Glad to meet you!\p"
	.string "This world…$"

NewGame_Text_Inhabited::
	.string "…is inhabited far and wide by\n"
	.string "creatures called POKéMON.\p"
	.string "For some people, POKéMON are pets.\n"
	.string "Others use them for battling.\p"
	.string "But first, tell me a little about\n"
	.string "yourself.$"

@ ⚠️ ASKED BEFORE THE NAME, AND THAT ORDER IS LOAD-BEARING —
@ PlayerIdentity.name_choices() keys its preset list on gender, so asking the
@ other way round offers a list that then has to be thrown away.
NewGame_Text_AskGender::
	.string "Now tell me. Are you a boy?\n"
	.string "Or are you a girl?$"

NewGame_Text_YourName::
	.string "Let's begin with your name.\n"
	.string "What is it?$"

@ ⚠️ A CONFIRMATION PROMPT, not a trailing statement — source's own
@ gOakSpeech_Text_SoYourNameIsPlayer is what Task_OakSpeech_ConfirmName shows,
@ and its NO branch loops back into naming with no extra text.
NewGame_Text_SoYourName::
	.string "Right…\n"
	.string "So your name is {PLAYER}.$"

NewGame_Text_RivalIntro::
	.string "This is my grandson.\n"
	.string "He's been your rival since you both were babies.\p"
	.string "…Erm, what was his name now?$"

NewGame_Text_ConfirmRivalName::
	.string "…Er, was it {RIVAL}?$"

NewGame_Text_RememberRival::
	.string "That's right! I remember now!\n"
	.string "His name is {RIVAL}!$"

NewGame_Text_LetsGo::
	.string "{PLAYER}!\n"
	.string "Your very own POKéMON legend is about to unfold!\n"
	.string "A world of dreams and adventures with POKéMON awaits! Let's go!$"

@ --- Field poison -----------------------------------------------------------
@
@ [M27G G7] Source runs the poison notice as a real script
@ (EventScript_FieldPoison, opening with `lockall`). This project had no VM to
@ park it on when it was built, so `_poison_step()` opened the box directly and
@ expressed the lock by returning early from `_process` — a second, parallel way
@ to be a cutscene. Now it is a script like everything else.
@
@ ⚠️ VERBATIM FROM `FieldPoison.MESSAGE`, and the first draft of this block got
@ it wrong — it said "{STR_VAR_1} fainted…", which is a different event
@ entirely. The notice fires when a poisoned Pokémon is left sitting at exactly
@ 1 HP and the poison CLEARS; a faint is not what happened, and the mon is
@ still standing.
FieldPoison_Text_Survived::
	.string "{STR_VAR_1} survived the poisoning.\n"
	.string "The poison faded away!$"

@ --- Save --------------------------------------------------------------------
@
@ [M27G G7] `_on_start_menu_save` opened a yes/no outside the VM, so deleting
@ the free-standing yes/no driver would have left SAVING unanswerable from the
@ keyboard — the identical bug `[M27K K-b]`'s gender question shipped with.
@ ⚠️ This caller was NOT in G7's own scope list; it was found by deleting the
@ driver and asking what else used it.
StartMenu_Text_SaveConfirm::
	.string "Would you like to save the game?$"

StartMenu_Text_Saving::
	.string "SAVING…\n"
	.string "DON'T TURN OFF THE POWER.$"

@ Source's own gText_PlayerSavedGame. {PLAYER} is expanded at print time, so it
@ reads back the name chosen during Oak's speech.
StartMenu_Text_SaveDone::
	.string "{PLAYER} saved the game.$"

StartMenu_Text_SaveFailed::
	.string "Save error.\p"
	.string "Please exchange the\n"
	.string "backup memory.$"
