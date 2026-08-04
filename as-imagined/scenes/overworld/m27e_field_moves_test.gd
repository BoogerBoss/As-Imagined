extends Node

## [M27E E0] The field-move gate: badges, and nothing but badges.
##
## The claims most worth pinning:
##
##   * the gate is the BADGE — a party that knows nothing still cuts the tree,
##     which is Rob's design call and a large deliberate divergence from source;
##   * the eight assignments are series CANON authored here, not ported: the
##     reference has no badge->HM field gating in C anywhere;
##   * Dive's assignment is an INVENTION, kept in scope on Rob's call despite
##     zero Dive cells on zero of the 421 Kanto maps.

const EXPECTED_TOTAL := 20

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_gate()
	_test_mapping()
	_test_messages()
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27e_field_moves_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the gate ---
func _test_gate() -> void:
	var f := FlagStore.new()
	_chk("A.01 with no badges, nothing is usable",
			not FieldMoves.can_use(f, FieldMoves.Ability.CUT)
			and not FieldMoves.can_use(f, FieldMoves.Ability.SURF))
	f.flag_set("FLAG_BADGE02_GET")
	# ⚠️ **THE WHOLE DESIGN, IN ONE ASSERTION.** The store holds a badge and
	# nothing else — no party, no moves, no HM items exist in this fixture at
	# all — and Cut is usable anyway.
	_chk("A.02 the Cascade Badge ALONE makes Cut usable, with no party at all",
			FieldMoves.can_use(f, FieldMoves.Ability.CUT))
	# ⚠️ AND IT MUST NOT UNLOCK THE OTHERS, or "reads the badge" would be
	# indistinguishable from "returns true once you hold any badge".
	_chk("A.03 and unlocks ONLY Cut, not every ability",
			not FieldMoves.can_use(f, FieldMoves.Ability.SURF)
			and not FieldMoves.can_use(f, FieldMoves.Ability.STRENGTH)
			and not FieldMoves.can_use(f, FieldMoves.Ability.FLASH))
	f.flag_set("FLAG_BADGE05_GET")
	_chk("A.04 a second badge adds its own ability and keeps the first",
			FieldMoves.can_use(f, FieldMoves.Ability.SURF)
			and FieldMoves.can_use(f, FieldMoves.Ability.CUT))
	# Defensive: a null store and a nonsense ability must refuse, not crash.
	_chk("A.05 a null flag store refuses rather than crashing",
			not FieldMoves.can_use(null, FieldMoves.Ability.CUT))
	_chk("A.06 an unknown ability refuses", not FieldMoves.can_use(f, 999))


## --- B. the mapping ---
func _test_mapping() -> void:
	# ⚠️ EVERY ability has a badge, or one of them would be permanently unusable
	# with nothing to say why.
	_chk("B.01 all eight abilities have a badge",
			FieldMoves.BADGE_FOR.size() == FieldMoves.Ability.size()
			and FieldMoves.Ability.size() == 8)
	# ⚠️ AND NO TWO SHARE ONE. A duplicate would silently unlock two abilities
	# from one gym and leave a badge governing nothing.
	var badges := {}
	for a in FieldMoves.BADGE_FOR:
		badges[str(FieldMoves.BADGE_FOR[a])] = true
	_chk("B.02 and no two abilities share a badge", badges.size() == 8)
	# The badge ORDER is ported and verified from each gym's own script.
	_chk("B.03 every badge named is one the flag store knows",
			badges.size() == PackedStringArray(FlagStore.BADGE_FLAGS).size())
	for b in FlagStore.BADGE_FLAGS:
		if not badges.has(str(b)):
			_chk("B.04 %s governs an ability" % str(b), false)
			return
	_chk("B.04 every one of the eight badges governs exactly one ability", true)

	# Canon, spot-checked at the two ends and at Rob's own worked example.
	_chk("B.05 Cascade (02) is Cut — Rob's own worked example",
			str(FieldMoves.BADGE_FOR[FieldMoves.Ability.CUT]) == "FLAG_BADGE02_GET")
	_chk("B.06 Boulder (01) is Flash and Soul (05) is Surf",
			str(FieldMoves.BADGE_FOR[FieldMoves.Ability.FLASH]) == "FLAG_BADGE01_GET"
			and str(FieldMoves.BADGE_FOR[FieldMoves.Ability.SURF]) == "FLAG_BADGE05_GET")
	# ⚠️ DIVE IS THE INVENTION. FRLG has no Dive and Kanto has zero cells for it;
	# kept in scope on Rob's call, on the badge canon leaves free.
	_chk("B.07 Dive takes the Earth Badge, which canon leaves free",
			str(FieldMoves.BADGE_FOR[FieldMoves.Ability.DIVE]) == "FLAG_BADGE08_GET")

	# ⚠️ A BADGE-ONLY GATE MEANS AN EMPTY PARTY CAN STILL ACT, and since
	# `[M27L L5]` an empty party is a real starting state. Academic in play — you
	# cannot win a gym with nothing — but it is reachable, so it is pinned rather
	# than left to surprise someone.
	OverworldSession.reset()
	OverworldSession.flags.flag_set("FLAG_BADGE02_GET")
	_chk("B.08 a player with an EMPTY party can still cut, by design",
			OverworldSession.player_party().members.is_empty()
			and FieldMoves.can_use(OverworldSession.flags, FieldMoves.Ability.CUT))
	OverworldSession.reset()


## --- C. the messages ---
func _test_messages() -> void:
	# ⚠️ GENERIC BY DESIGN. Source names the Pokemon (`{STR_VAR_1} used CUT!`);
	# there is no such Pokemon here, so naming one would put a lie in the box.
	var used := FieldMoves.used_message(FieldMoves.Ability.CUT)
	_chk("C.01 the use message names the ABILITY", used.contains("CUT"))
	_chk("C.02 and names no Pokemon and no placeholder for one",
			not used.contains("{") and not used.contains("STR_VAR"))
	_chk("C.03 a two-word ability reads correctly",
			FieldMoves.used_message(FieldMoves.Ability.ROCK_SMASH)
					.contains("ROCK SMASH"))
	var blocked := FieldMoves.blocked_message(FieldMoves.Ability.SURF)
	_chk("C.04 the refusal names what is needed", blocked.contains("SURF"))
	# ⚠️ It must NOT name the badge or the gym — that is a hint source never
	# gives, and it would flatten the region's own progression.
	_chk("C.05 but does not name the badge or the gym that grants it",
			not blocked.to_upper().contains("BADGE")
			and not blocked.to_upper().contains("GYM"))
	_chk("C.06 every ability has a name, so none can print as '?'",
			FieldMoves.ability_name(FieldMoves.Ability.WATERFALL) == "WATERFALL"
			and FieldMoves.ABILITY_NAME.size() == FieldMoves.Ability.size())
