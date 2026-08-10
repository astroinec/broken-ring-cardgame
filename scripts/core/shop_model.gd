class_name ShopModel
extends RefCounted


var stock: Dictionary = {}
var last_error: String = ""
var _relic_trigger_counts: Dictionary = {}
var _relic_net_benefits: Dictionary = {}


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
	var price: int = get_remove_price(run)
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
	if run.relics.has(&"seventh_dock_stamp"):
		var base_price: int = maxi(0, int(service.get(&"price", 0)))
		_record_relic_benefit(&"seventh_dock_stamp", base_price - price)
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
	if item.is_empty():
		return "本次没有未持有的可售遗物"
	if bool(item.get(&"sold", false)):
		return "已售出"
	if run.relics.has(item.get(&"relic_id", &"") as StringName):
		return "已持有该遗物"
	if run.ink_crystals < int(item.get(&"price", 0)):
		return "墨晶不足"
	return ""


func get_remove_price(run: RunModel) -> int:
	var service: Dictionary = stock.get(&"remove_service", {})
	var discount: int = 25 if run.relics.has(&"seventh_dock_stamp") else 0
	return maxi(0, int(service.get(&"price", 0)) - discount)


func remove_unavailable_reason(run: RunModel) -> String:
	var service: Dictionary = stock.get(&"remove_service", {})
	if bool(service.get(&"sold", false)):
		return "本节点移除服务已使用"
	if run.ink_crystals < get_remove_price(run):
		return "墨晶不足"
	if run.deck_instances.size() <= 1:
		return "牌组至少保留1张牌"
	return ""


func get_relic_telemetry() -> Dictionary:
	return {
		&"trigger_counts": _relic_trigger_counts.duplicate(),
		&"net_benefits": _relic_net_benefits.duplicate(),
	}


func _record_relic_benefit(relic_id: StringName, benefit: int) -> void:
	_relic_trigger_counts[relic_id] = int(_relic_trigger_counts.get(relic_id, 0)) + 1
	_relic_net_benefits[relic_id] = int(_relic_net_benefits.get(relic_id, 0)) + benefit
