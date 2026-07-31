class_name BattleOutcome
extends RefCounted

## [M27D D5] How a battle ended, and what the overworld should do about it.
##
## `BattleManager.battle_ended(winner_side: int)` is a boolean in disguise — it
## cannot express a draw, a forfeit, or a flee, and source's own return logic
## needs all three. `CB2_EndTrainerBattle` (`battle_setup.c:1430`) branches on
## `gBattleOutcome`, and `IsPlayerDefeated` (`:1500`) is the rule that matters:
##
##   DEFEAT  <- B_OUTCOME_LOST, B_OUTCOME_DREW, B_OUTCOME_FORFEITED
##   NOT     <- B_OUTCOME_WON, RAN, PLAYER_TELEPORTED, MON_FLED, CAUGHT
##
## **A DRAW COUNTS AS A DEFEAT.** That is the non-obvious one, and it is exactly
## what a winner-side int cannot represent.
##
## Values match source's own numbering so a citation stays checkable.

const WON := 1
const LOST := 2
const DREW := 3
const RAN := 4
const CAUGHT := 7
const FORFEITED := 9

## Source's own `IsPlayerDefeated` set.
const DEFEAT_OUTCOMES := [LOST, DREW, FORFEITED]

var outcome: int = WON

## The trainer this battle was against, "" for a wild battle. Written back by
## the overworld on a win so the beaten flag is set against the same key the
## placement carries.
var trainer_key: String = ""


static func make(p_outcome: int, p_trainer_key: String = "") -> BattleOutcome:
	var r := BattleOutcome.new()
	r.outcome = p_outcome
	r.trainer_key = p_trainer_key
	return r


## Source: `IsPlayerDefeated`. Note DREW is a defeat.
func player_defeated() -> bool:
	return outcome in DEFEAT_OUTCOMES


## Should the beaten-trainer flag be set? Source only calls
## `SetBattledTrainersFlags()` on the non-defeat branch, so a forfeit or a loss
## leaves the trainer beatable again — which is what makes losing meaningful.
func should_set_defeated_flag() -> bool:
	return outcome == WON and trainer_key != ""


func label() -> String:
	match outcome:
		WON: return "won"
		LOST: return "lost"
		DREW: return "drew"
		RAN: return "ran"
		CAUGHT: return "caught"
		FORFEITED: return "forfeited"
	return "unknown(%d)" % outcome
