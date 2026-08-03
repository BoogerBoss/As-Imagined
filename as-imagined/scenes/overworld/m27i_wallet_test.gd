extends Node

## [M27I I3b] Money and coins.
##
## The reason this suite is worth its length: THREE different removal semantics
## now exist across this project, and they are genuinely different in source.
##   Bag.remove   -- all-or-nothing
##   spend        -- clamps to zero, never fails
##   remove_coins -- all-or-nothing again
## Making them consistent would be tidier and wrong.

const EXPECTED_TOTAL := 30

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _src(ops: Dictionary) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	return s


func _op(name: String, args: Array = []) -> Dictionary:
	return {"op": name, "args": args}


func _ready() -> void:
	_test_money()
	_test_coins()
	_test_opcodes()
	_test_save()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_wallet_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. money ---
func _test_money() -> void:
	var w := Wallet.new()
	_chk("A.01 caps are source's own",
			Wallet.MAX_MONEY == 999999 and Wallet.MAX_COINS == 9999)
	_chk("A.02 a new wallet is empty", w.money == 0 and w.coins == 0)
	w.earn(500)
	_chk("A.03 earning adds", w.money == 500)
	_chk("A.04 can_afford is a >= test, matching IsEnoughMoney",
			w.can_afford(500) and w.can_afford(499) and not w.can_afford(501))
	w.spend(200)
	_chk("A.05 spending subtracts", w.money == 300)
	# ⚠️ CLAMPS TO ZERO, does NOT refuse. The whiteout payout depends on this:
	# it asks for badge-scaled money and expects to take everything you have
	# when that is less. Refusing would make a broke player immune.
	w.spend(999999)
	_chk("A.06 overspending empties the wallet rather than failing", w.money == 0)
	w.earn(Wallet.MAX_MONEY)
	w.earn(1000)
	_chk("A.07 earning clamps at the cap", w.money == Wallet.MAX_MONEY)
	w.spend(-5)
	w.earn(-5)
	_chk("A.08 negative amounts are ignored in both directions",
			w.money == Wallet.MAX_MONEY)


## --- B. coins ---
func _test_coins() -> void:
	var w := Wallet.new()
	_chk("B.01 adding coins reports success", w.add_coins(100) and w.coins == 100)
	# ⚠️ ALL-OR-NOTHING, unlike money one section above.
	_chk("B.02 removing more coins than held REFUSES and changes nothing",
			not w.remove_coins(101) and w.coins == 100)
	_chk("B.03 removing what is there works", w.remove_coins(60) and w.coins == 40)
	w.add_coins(Wallet.MAX_COINS)
	_chk("B.04 adding clamps at the cap", w.coins == Wallet.MAX_COINS)
	# Source returns FALSE from AddCoins when ALREADY at the cap, before any
	# clamping -- a distinct case from clamping a partial add.
	_chk("B.05 adding at the cap reports failure", not w.add_coins(1))
	_chk("B.06 negative amounts are refused",
			not w.add_coins(-1) and not w.remove_coins(-1))


## --- C. the opcodes ---
func _test_opcodes() -> void:
	var flags := FlagStore.new()
	var w := Wallet.new()
	w.earn(500)
	var vm := ScriptVM.new(_src({
		"A": [_op("checkmoney", ["300"]), _op("removemoney", ["300"]),
			_op("checkmoney", ["300"]), _op("addmoney", ["100"]), _op("end")],
	}), flags)
	vm.wallet = w
	vm.start("A")
	vm.step()
	_chk("C.01 checkmoney reports affordable", flags.var_get("VAR_RESULT") == 1)
	vm.step()
	_chk("C.02 removemoney takes it", w.money == 200)
	vm.step()
	_chk("C.03 and checkmoney now reports NOT affordable",
			flags.var_get("VAR_RESULT") == 0)
	vm.step()
	_chk("C.04 addmoney gives", w.money == 300)

	# ⚠️ NOT EVERY MONEY ARG IS A LITERAL, and finding that out is what this
	# assertion is for. 6 corpus args are file-scoped assembler constants
	# (`COINS_PRICE_500` = 10000, `MAGIKARP_PRICE` = 500) declared with `.equ`
	# INSIDE the map script that uses them; the script compiler does not resolve
	# them yet, so they arrive as names. 32 such constants exist region-wide and
	# `REQUIRED_CAUGHT_MONS` is declared three times with three different values,
	# so the fix belongs in the compiler with file scope, not in a global table.
	#
	# ⚠️ AND THE DEGRADE MUST FAIL CLOSED. Reading an unresolved price as 0 would
	# make `checkmoney` say AFFORDABLE and the following `removemoney` charge
	# nothing — free goods. Guessing from the name would be worse still:
	# `COINS_PRICE_50` is 1000, so the suffix is the COIN count and would be
	# wrong by 20x.
	var flags2 := FlagStore.new()
	var w2 := Wallet.new()
	w2.earn(100000)
	var vm2 := ScriptVM.new(_src({
		"A": [_op("checkmoney", ["COINS_PRICE_500"]),
			_op("removemoney", ["COINS_PRICE_500"]), _op("end")],
	}), flags2)
	vm2.wallet = w2
	vm2.start("A")
	vm2.step()
	_chk("C.05 an unresolvable price reports NOT affordable, not free",
			flags2.var_get("VAR_RESULT") == 0)
	_chk("C.05b and names itself rather than failing silently",
			vm2.diagnostic.contains("COINS_PRICE_500"))
	vm2.step()
	_chk("C.05c and charges nothing rather than charging zero for the goods",
			w2.money == 100000)

	# checkcoins writes into the NAMED var, not VAR_RESULT.
	var flags3 := FlagStore.new()
	var w3 := Wallet.new()
	w3.add_coins(77)
	var vm3 := ScriptVM.new(_src({
		"A": [_op("checkcoins", ["VAR_TEMP_1"]), _op("end")],
	}), flags3)
	vm3.wallet = w3
	vm3.start("A")
	vm3.step()
	_chk("C.06 checkcoins writes into the named var", flags3.var_get("VAR_TEMP_1") == 77)
	_chk("C.07 and not into VAR_RESULT", flags3.var_get("VAR_RESULT") != 77)

	# ⚠️ THE INVERSION. Source sets VAR_RESULT to FALSE on SUCCESS for both coin
	# commands. Reading it the natural way round makes every Game Corner "did
	# that work" branch take the wrong path.
	var flags4 := FlagStore.new()
	var w4 := Wallet.new()
	var vm4 := ScriptVM.new(_src({"A": [_op("addcoins", ["50"]), _op("end")]}), flags4)
	vm4.wallet = w4
	vm4.start("A")
	vm4.step()
	_chk("C.08 a SUCCESSFUL addcoins sets VAR_RESULT to FALSE",
			w4.coins == 50 and flags4.var_get("VAR_RESULT") == 0)
	# And the failure case sets it TRUE.
	var w5 := Wallet.new()
	w5.add_coins(Wallet.MAX_COINS)
	var flags5 := FlagStore.new()
	var vm5 := ScriptVM.new(_src({"A": [_op("addcoins", ["1"]), _op("end")]}), flags5)
	vm5.wallet = w5
	vm5.start("A")
	vm5.step()
	_chk("C.09 a FAILED addcoins sets VAR_RESULT to TRUE",
			flags5.var_get("VAR_RESULT") == 1)
	# Coins DO resolve through the variable store, the opposite of money.
	var flags6 := FlagStore.new()
	flags6.var_set("VAR_TEMP_2", 30)
	var w6 := Wallet.new()
	w6.add_coins(100)
	var vm6 := ScriptVM.new(_src({"A": [_op("removecoins", ["VAR_TEMP_2"]), _op("end")]}), flags6)
	vm6.wallet = w6
	vm6.start("A")
	vm6.step()
	_chk("C.10 a coin amount held in a VARIABLE resolves", w6.coins == 70)

	# The money-box display commands must not halt a script.
	var vm7 := ScriptVM.new(_src({
		"A": [_op("showmoneybox", ["0", "0"]), _op("updatemoneybox"),
			_op("hidemoneybox"), _op("end")],
	}), FlagStore.new())
	vm7.start("A")
	vm7.step(); vm7.step(); vm7.step()
	_chk("C.11 the money-box display commands are accepted, not unknown",
			vm7.pause_reason != ScriptVM.Pause.UNKNOWN_OP)


## --- D. the save shape ---
func _test_save() -> void:
	var w := Wallet.new()
	w.earn(1234)
	w.add_coins(56)
	var w2 := Wallet.new()
	w2.from_save(w.to_save())
	_chk("D.01 a wallet round-trips", w2.money == 1234 and w2.coins == 56)
	_chk("D.02 the save shape is plain data",
			typeof(JSON.stringify(w.to_save())) == TYPE_STRING)
	# A corrupt or hand-edited save must not produce an impossible wallet.
	var w3 := Wallet.new()
	w3.from_save({"money": 99999999, "coins": -5})
	_chk("D.03 loading clamps rather than trusting the file",
			w3.money == Wallet.MAX_MONEY and w3.coins == 0)
