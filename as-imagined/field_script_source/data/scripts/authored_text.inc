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

@ A signpost by the water. Read by PalletTownEvents.sea_breeze().
PalletTown_Authored_Text_SeaBreeze::
	.string "The sea wind carries something\n"
	.string "faintly sweet today.\p"
	.string "Someone has scratched a date into\n"
	.string "the post, and a name worn too far\n"
	.string "to read.$"

@ The second read, reached by the flag gate. A script that repeats itself
@ verbatim reads as broken.
PalletTown_Authored_Text_SeaBreezeShort::
	.string "The sea wind again. Just the wind.$"
