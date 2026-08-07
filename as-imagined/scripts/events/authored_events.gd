class_name AuthoredEvents
extends RefCounted

## [M27G G6] Every script this project wrote itself, registered in one place.
##
## The counterpart to the imported corpus: `data/map_scripts.json` holds the
## 17,137 labels compiled out of `field_script_source/`, and everything under
## `scripts/events/` is content authored directly in GDScript. Both land in the
## same `ops_by_label` table and `ScriptVM` cannot tell them apart.
##
## ⚠️ **LABELS MUST NOT COLLIDE WITH THE IMPORTED CORPUS.** `EventRegistry
## .merge_into` refuses a colliding label and reports it rather than shadowing
## an imported script somewhere across Kanto. The convention that keeps that
## from ever firing: prefix authored labels with the map they belong to and end
## them in a name the reference would not use. Nothing enforces the prefix — the
## collision check is the enforcement, and it is loud.
##
## ⚠️ **Called from `ScriptDriver.setup`, which runs once per field session.**
## `EventRegistry.register` keeps the first registration and warns on a
## duplicate, so a rebuilt overworld (every battle round trip builds one) is
## harmless.


static func register_all() -> void:
	PalletTownEvents.register_all()
	NewGameEvents.register_all()
	StartMenuEvents.register_all()
	FieldPoisonEvents.register_all()
