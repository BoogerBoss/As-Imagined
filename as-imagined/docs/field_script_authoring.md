# Field script authoring — `field_script_source/`

**Scope of record for how to hand-edit field scripts and dialogue.**
Created 2026-08-06, following the same architectural move M27M made for map
tiles ("the scene becomes the source of truth"), applied here to field
script logic and dialogue text.

## What this is

`field_script_source/` is a project-owned, **tracked**, hand-editable copy
of every `.inc`/`.s` field-script file the reference project ever had —
1025 files, ~7.4 MB, copied byte-for-byte from
`reference/pokeemerald_expansion/data/` on 2026-08-06, in the identical
relative layout (`field_script_source/data/maps/<Map>/scripts.inc`,
`field_script_source/data/scripts/*.inc`, `field_script_source/data/
event_scripts.s`, etc.).

`scripts/gen_map_scripts.py` (opcodes) and `scripts/gen_map_texts.py`
(dialogue text) now read from `field_script_source/` instead of
`reference/pokeemerald_expansion/`. **Verified byte-for-byte identical
output** against the previously-committed `data/map_scripts.json`/
`data/map_texts.json` before any hand edit was made — the fork started as
a proven-clean baseline, not an unverified copy.

From this point on, `field_script_source/` is the real source of truth for
every field script and every line of dialogue in the game. It is a fork,
not a mirror — `reference/pokeemerald_expansion` will never be consulted
for scripts or text again, and future upstream changes to those files will
never be picked up automatically. That trade-off (lose free upstream
fixes, gain real hand-authorability) is the same one M27M already made for
map geometry; see that milestone's own CLAUDE.md entry for the fuller
reasoning.

## Why one fork covers both scripts AND dialogue

Text lives *inside* the same `.inc` files as the script logic that
references it — as `Label:: .string "..." .string "..."` blocks, usually
near the bottom of a map's `scripts.inc`. There is no separate text-source
tree to also fork.

## What is NOT covered by this fork (already solved elsewhere, or a
different concern entirely)

- **Map geometry, tiles, collision, elevation, NPC/warp/trigger
  placement.** Already hand-authorable via the baked `.tscn` scene per
  scene per M27M — completely separate from field scripts. A script
  referencing `LOCALID_X` for an NPC still needs a matching placed entity
  in that map's own baked scene (or an `addobject` call).
- **Species/move/item/ability ROSTERS.** A script can use any `SPECIES_X`/
  `ITEM_X`/`FLAG_X`/`VAR_X` token already known to `ScriptVM._literal` or
  the project's own name→id maps (generous — every real constant, not just
  reachable ones). Flags and vars are free-form strings with no lookup
  table at all. A genuinely NEW species not in the 386-species roster is a
  data question, unrelated to script authoring.
- **Which opcodes actually run.** `ScriptVM.step()` implements **124 of the
  reference's 231 field-script commands** (`data/script_cmd_table.inc`),
  covering **92.3% of all command uses** across the corpus — 57,464 of
  62,249, measured 2026-08-07 over 974 files in `field_script_source/data/`,
  excluding the ~79 movement-script actions, which are a separate
  sub-language handled by `MovementRunner`. *(This bullet previously read
  "roughly 90 of 237"; both figures were stale.)* A hand-written script
  using an unported opcode compiles cleanly and then halts at runtime with
  `UNKNOWN_OP`, naming itself — exactly the same as it does today for
  anything from the original reference.

  ⚠️ **"Implemented" is not the same as "does something."** A meaningful
  group is dispatched and deliberately silent because the system behind it
  does not exist here — `fadescreen` (+`fadescreenspeed`/
  `fadescreenswapbuffers`), `dofieldeffect`/`waitfieldeffect`,
  `showmonpic`/`hidemonpic`, `opendoor`/`closedoor`/`waitdooranim`,
  `showmoneybox`/`showcoinsbox` and their families, and every audio opcode
  (a project-wide absence, **M36-S**). Each carries its own doc comment at
  the dispatch site explaining why. A script using one runs to completion
  and shows nothing, which is a different failure from `UNKNOWN_OP` and will
  not show up in a coverage count. Closing that category is **M27G G5** —
  see `docs/m27g_scope.md` §3.1.

## The edit → regenerate → test loop

1. Edit a file directly under `field_script_source/data/...` — any text
   editor.
2. Regenerate:
   ```bash
   python3 scripts/gen_map_scripts.py
   python3 scripts/gen_map_texts.py
   ```
3. That's it — no bake step for scripts. `overworld.gd` reads
   `data/map_scripts.json`/`data/map_texts.json` fresh at boot
   (`overworld.gd:1919`), not from anything baked into a `.tscn`, so
   launching the game (or the relevant test scene) immediately reflects
   the edit.

## Syntax quick reference

**A script** is a label followed by a sequence of opcodes, one per line:
```
PalletTown_ProfessorOaksLab_EventScript_BulbasaurBall::
	lock
	faceplayer
	setvar PLAYER_STARTER_NUM, 0
	setvar PLAYER_STARTER_SPECIES, SPECIES_BULBASAUR
	goto_if_ge VAR_MAP_SCENE_PALLET_TOWN_PROFESSOR_OAKS_LAB, 3, PalletTown_ProfessorOaksLab_EventScript_LastPokeBall
	msgbox PalletTown_ProfessorOaksLab_Text_ThoseArePokeBalls
	release
	end
```

**Dialogue** is a label followed by one or more `.string` lines:
```
PalletTown_ProfessorOaksLab_Text_ThoseArePokeBalls::
	.string "Those are POKé BALLS.\n"
	.string "They contain POKéMON!$"
```
`\n` = newline within a page. `\p` = new page (waits for a button press).
`$` = string terminator, required at the end of the *last* line only.

**Comments**: `@` starts a comment, stripped before parsing.

**Conditional compilation**: `#ifdef`/`#if defined(...)`/`#else`/`#endif`
already work. The compiler resolves to the `#else` branch by default,
matching this project's own established LeafGreen convention (see
`[M27K K-b]`) — nothing special needs to be done to get that branch; it is
simply what compiles.

**New content**: a brand-new script is just a new `SomeNewLabel::` block
anywhere in the corpus, ending in `end`/`return`, reached by a `call`/
`goto` from somewhere, or wired into a map's own `OnFrame`/`OnTransition`
table, or a placed entity's own `script_label`.

## Standing rule

**Never repoint `gen_map_scripts.py`'s or `gen_map_texts.py`'s `REF`
constant back at `reference/pokeemerald_expansion`.** Doing so would
silently discard every hand edit made to `field_script_source/` on the
very next regeneration — both files carry this warning inline as well, but
it is recorded here as the standing rule it is.
