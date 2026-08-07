class_name ShopModel
extends RefCounted


var stock: Dictionary = {}
var last_error: String = ""


func _init(p_stock: Dictionary = {}) -> void:
	stock = p_stock.duplicate(true)


func buy_card(run: RunModel, stock_index: int) -> bool:
	last_error = ""
	var cards: Array = stock.get(&"cards", [])
	if stock_index < 0 or stock_index >= cards.size():
		last_error = "商品不存在"
		return false
	var item: Dictionary = cards[stock_index]
	if bool(item.get(&"sold", false)):
		last_error = "已售出"
		return false
	var price: int = int(item[&"price"])
	if run.ink_crystals < price:
		last_error = "墨晶不足"
		return false
	run.ink_crystals -= price
	run.add_card_instance(item[&"card_id"] as StringName)
	item[&"sold"] = true
	cards[stock_index] = item
	stock[&"cards"] = cards
	return true


func buy_relic(run: RunModel) -> bool:
	last_error = ""
	var item: Dictionary = stock.get(&"relic", {})
	if item.is_empty():
		last_error = "商品不存在"
		return false
	if bool(item.get(&"sold", false)):
		last_error = "已售出"
		return false
	var relic_id: StringName = item[&"relic_id"] as StringName
	if run.relics.has(relic_id):
		last_error = "已持有该遗物"
		return false
	var price: int = int(item[&"price"])
	if run.ink_crystals < price:
		last_error = "墨晶不足"
		return false
	run.ink_crystals -= price
	run.relics.append(relic_id)
	item[&"sold"] = true
	stock[&"relic"] = item
	return true


func remove_card(run: RunModel, instance_id: int) -> bool:
	last_error = ""
	var service: Dictionary = stock.get(&"remove_service", {})
	if service.is_empty():
		last_error = "服务不存在"
		return false
	if bool(service.get(&"sold", false)):
		last_error = "本节点移除服务已使用"
		return false
	var price: int = int(service[&"price"])
	if run.ink_crystals < price:
		last_error = "墨晶不足"
		return false
	if not run.has_deck_instance(instance_id):
		last_error = "牌组实例不存在"
		return false
	if run.deck_instances.size() <= 1:
		last_error = "牌组至少保留1张牌"
		return false
	run.ink_crystals -= price
	if not run.remove_card_instance(instance_id):
		run.ink_crystals += price
		last_error = "移除失败"
		return false
	run.shop_remove_count += 1
	service[&"sold"] = true
	stock[&"remove_service"] = service
	return true


func card_unavailable_reason(run: RunModel, stock_index: int) -> String:
	var cards: Array = stock.get(&"cards", [])
	if stock_index < 0 or stock_index >= cards.size():
		return "商品不存在"
	var item: Dictionary = cards[stock_index]
	if bool(item.get(&"sold", false)):
		return "已售出"
	if run.ink_crystals < int(item[&"price"]):
		return "墨晶不足"
	return ""


func relic_unavailable_reason(run: RunModel) -> String:
	var item: Dictionary = stock.get(&"relic", {})
	if bool(item.get(&"sold", false)):
		return "已售出"
	if run.relics.has(item.get(&"relic_id", &"") as StringName):
		return "已持有该遗物"
	if run.ink_crystals < int(item.get(&"price", 0)):
		return "墨晶不足"
	return ""


func remove_unavailable_reason(run: RunModel) -> String:
	var service: Dictionary = stock.get(&"remove_service", {})
	if bool(service.get(&"sold", false)):
		return "本节点移除服务已使用"
	if run.ink_crystals < int(service.get(&"price", 0)):
		return "墨晶不足"
	if run.deck_instances.size() <= 1:
		return "牌组至少保留1张牌"
	return ""
