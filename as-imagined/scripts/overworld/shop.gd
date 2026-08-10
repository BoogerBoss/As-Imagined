@tool
class_name Shop
extends RefCounted

## [M27I I6c] What buying actually costs and yields.
##
## Separated from the screen on purpose, and for the reason this project keeps
## re-learning: the plugin and the UI layers are where defects hide, so anything
## with a RULE in it lives on the side a headless suite can reach. The screen
## below this only asks questions and draws answers.

## Source caps a purchase at the bag's own stack ceiling, not at an arbitrary
## picker limit (`shop.c:1089-1094`): `maxQuantity = money / unitCost`, then
## clamped to what the bag can actually hold.
const MAX_PER_PURCHASE := Bag.MAX_STACK


## True when the player may only ever hold one — source's `GetItemImportance`.
static func is_key_item(item_id: int) -> bool:
	var data := ItemRegistry.get_item(item_id)
	return data != null and data.importance > 0


## The most of `item_id` the player could buy right now.
##
## ⚠️ **BOTH CAPS, NOT JUST MONEY.** Source clamps by money AND by bag space, so
## the "you don't have enough money" path only ever guards the edge — a picker
## that offered more than the bag can hold would fail at the confirm instead of
## refusing to offer it.
static func max_affordable(price: int, money: int, item_id: int, bag: Bag) -> int:
	if price <= 0:
		# ⚠️ A FREE ITEM IS REAL, NOT A DIVIDE-BY-ZERO. Escape Rope is price 0
		# at this project's GEN_LATEST config and is stocked in Pewter, so this
		# path runs in the corridor rather than being defensive.
		return bag.free_space_for(item_id) if bag != null else 0
	var by_money := int(money / price)
	var by_space := bag.free_space_for(item_id) if bag != null else 0
	return mini(mini(by_money, by_space), MAX_PER_PURCHASE)


## Free Premier Balls for a purchase of `count` of `item_id`.
##
## ⚠️ **TRIPLED, AND THAT IS A DELIBERATE DIVERGENCE FROM SOURCE — Rob, 2026-08-09.**
## Source awards `count / 10` (`Task_ReturnToItemListAfterItemPurchase`,
## `shop.c:1190-1211`); this awards three times that, so 10 balls yield 3 and 20
## yield 6. Recorded here rather than left to be discovered as a bug, because it
## is exactly the kind of number a later session would "correct" against source.
##
## Everything else is source's own: the gate is the whole POKE_BALLS pocket
## rather than Poké Balls alone (`I_PREMIER_BALL_BONUS >= GEN_8`, and this
## project is `GEN_LATEST`), and the award is clamped to real bag space.
const PREMIER_BONUS_MULTIPLIER := 3

static func premier_bonus(item_id: int, count: int, bag: Bag) -> int:
	var identity := PokemonRegistry.get_item_identity(item_id)
	if identity.is_empty():
		return 0
	# ⚠️ `pocket` IS ALREADY AN ORDINAL, not a name. `get_item_identity` returns
	# `{"pocket": 1}`, so routing it through `pocket_from_name` — which expects
	# "poke_balls" — silently answered POCKET_ITEMS and the bonus was never
	# awarded at all. Measured, not guessed: the helper returned 0 for a
	# ten-ball purchase until this line changed.
	if int(identity.get("pocket", -1)) != ItemManager.POCKET_POKE_BALLS:
		return 0
	var award := int(count / 10) * PREMIER_BONUS_MULTIPLIER
	if award <= 0:
		return 0
	var premier := PokemonRegistry.item_id_of("ITEM_PREMIER_BALL")
	if premier <= 0 or bag == null:
		return 0
	# Clamped to what the bag can hold, as source does — a bonus that cannot fit
	# is not owed.
	return mini(award, bag.free_space_for(premier))


## Buy `count` of `item_id`. Returns
## `{"ok": bool, "reason": String, "spent": int, "premier": int}`.
##
## ⚠️ **CHECKS BEFORE IT SPENDS, because `Wallet.spend` CLAMPS rather than
## refusing.** That clamp is correct for the whiteout payout it was built for
## and wrong for a purchase: without an affordability check first, an
## unaffordable buy would take every coin the player had and hand over the goods
## anyway. `[M27I I3b]` records the same warning at the wallet itself — do not
## "fix" `spend`.
static func purchase(bag: Bag, wallet: Wallet, item_id: int, count: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "spent": 0, "premier": 0}
	if bag == null or wallet == null or count <= 0:
		res["reason"] = "nothing to buy"
		return res
	var identity := PokemonRegistry.get_item_identity(item_id)
	if identity.is_empty():
		res["reason"] = "unknown item"
		return res
	# ⚠️ A KEY ITEM THE PLAYER ALREADY HOLDS IS REFUSED, matching source's own
	# SOLD OUT (`shop.c:660, 1024`) — shown rather than hidden, and refused
	# rather than silently sold a second copy.
	#
	# ⚠️ `importance` comes from the `.tres`, NOT from `get_item_identity`:
	# that returns the `items.json` view, which carries name/pocket/price/
	# description and no importance at all, so reading it there answered 0 for
	# everything and every key item stayed buyable forever. The two-layer rule
	# again — importance is implemented BEHAVIOUR, so it lives in the `.tres`.
	if is_key_item(item_id) and bag.count_of(item_id) > 0:
		res["reason"] = "sold out"
		return res
	var price := int(identity.get("price", 0))
	var cost := price * count
	if not wallet.can_afford(cost):
		res["reason"] = "not enough money"
		return res
	if not bag.has_space(item_id, count):
		res["reason"] = "no room"
		return res
	# The bonus is computed BEFORE the purchase lands, so its own space check
	# sees the bag as the player does when deciding — but it is added after, so
	# a failed purchase never awards one.
	var bonus := premier_bonus(item_id, count, bag)
	if not bag.add(item_id, count):
		res["reason"] = "no room"
		return res
	wallet.spend(cost)
	if bonus > 0:
		bag.add(PokemonRegistry.item_id_of("ITEM_PREMIER_BALL"), bonus)
	res["ok"] = true
	res["spent"] = cost
	res["premier"] = bonus
	return res
