class_name Wallet
extends RefCounted

## [M27I I3b] Money and Game Corner coins.
##
## Two separate currencies with separate caps and — the part that is easy to get
## uniformly wrong — **three different removal semantics across this project**:
##
##   * `Bag.remove`   — ALL-OR-NOTHING. Refuses and changes nothing.
##   * `spend`        — CLAMPS TO ZERO. Never fails; taking more than you have
##                      simply leaves you at 0 (`RemoveMoney`, `money.c`).
##   * `remove_coins` — ALL-OR-NOTHING again (`RemoveCoins`, `coins.c`).
##
## Money and coins genuinely differ, in source, in the same file family. Making
## them consistent would be tidier and wrong: the whiteout payout depends on
## `spend` clamping (it takes everything you have when you cannot afford the
## full amount), while a Game Corner purchase depends on coins refusing.
##
## Save state, so it lives on OverworldSession beside the bag and the flags.

const MAX_MONEY := 999999
const MAX_COINS := 9999

var money: int = 0
var coins: int = 0


## Can the player afford this? Source: `IsEnoughMoney`, a `>=` test.
func can_afford(amount: int) -> bool:
	return money >= amount


## Add money, clamped at the cap. Source guards overflow too; ints here are
## 64-bit so the guard is the cap alone.
func earn(amount: int) -> void:
	if amount <= 0:
		return
	money = mini(MAX_MONEY, money + amount)


## Take money away, CLAMPED AT ZERO — this never fails.
##
## ⚠️ Deliberately NOT all-or-nothing, unlike the bag. `RemoveMoney` sets you to
## 0 when you cannot cover the amount, and the whiteout payout relies on exactly
## that: it asks for badge-scaled money and expects to take everything you have
## if that is less. Returning false and changing nothing would make a broke
## player immune to the penalty.
func spend(amount: int) -> void:
	if amount <= 0:
		return
	money = maxi(0, money - amount)


## Add coins. Returns false when already at the cap and nothing changed —
## source returns FALSE from `AddCoins` in that one case, before any clamping.
func add_coins(amount: int) -> bool:
	if coins >= MAX_COINS:
		return false
	if amount <= 0:
		return false
	coins = mini(MAX_COINS, coins + amount)
	return true


## Take coins, ALL-OR-NOTHING. Returns false and changes nothing if short.
func remove_coins(amount: int) -> bool:
	if amount <= 0 or coins < amount:
		return false
	coins -= amount
	return true


func to_save() -> Dictionary:
	return {"money": money, "coins": coins}


func from_save(data: Dictionary) -> void:
	money = clampi(int(data.get("money", 0)), 0, MAX_MONEY)
	coins = clampi(int(data.get("coins", 0)), 0, MAX_COINS)
