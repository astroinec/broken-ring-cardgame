class_name ShopCatalog
extends RefCounted


const COMMON_CARD_IDS: Array[StringName] = [
	&"broken_sentence", &"blank_space", &"index_reorder", &"unsigned_support",
	&"rift_slash", &"forced_stability", &"delayed_guard", &"countdown_scar",
	&"restate", &"copied_guard",
]
const RARE_CARD_IDS: Array[StringName] = [
	&"critical_permission", &"dissolution_protocol", &"prewritten_ending", &"unseal_order", &"homophone",
]
const RELIC_IDS: Array[StringName] = [&"wordless_bookplate"]


static func generate(content_seed: int, remove_count: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = content_seed
	var common_pool: Array[StringName] = COMMON_CARD_IDS.duplicate()
	var cards: Array[Dictionary] = []
	for draw_index: int in range(2):
		var common_index: int = rng.randi_range(0, common_pool.size() - 1)
		cards.append(_card_stock(common_pool[common_index], rng.randi_range(35, 45)))
		common_pool.remove_at(common_index)
	var use_rare: bool = rng.randi_range(0, 1) == 1
	if use_rare:
		var rare_id: StringName = RARE_CARD_IDS[rng.randi_range(0, RARE_CARD_IDS.size() - 1)]
		cards.append(_card_stock(rare_id, rng.randi_range(65, 80)))
	else:
		var final_index: int = rng.randi_range(0, common_pool.size() - 1)
		cards.append(_card_stock(common_pool[final_index], rng.randi_range(35, 45)))
	var relic_id: StringName = RELIC_IDS[rng.randi_range(0, RELIC_IDS.size() - 1)]
	return {
		&"content_seed": content_seed,
		&"cards": cards,
		&"relic": {&"relic_id": relic_id, &"price": rng.randi_range(130, 170), &"sold": false},
		&"remove_service": {&"price": 75 + remove_count * 25, &"sold": false},
	}


static func digest(stock: Dictionary) -> String:
	var parts: Array[String] = ["seed=%d" % int(stock.get(&"content_seed", 0))]
	for raw_item: Variant in stock.get(&"cards", []):
		var item: Dictionary = raw_item as Dictionary
		parts.append("card=%s/%d/%d" % [item[&"card_id"], item[&"price"], 1 if bool(item[&"sold"]) else 0])
	var relic: Dictionary = stock.get(&"relic", {})
	parts.append("relic=%s/%d/%d" % [relic.get(&"relic_id", &""), relic.get(&"price", 0), 1 if bool(relic.get(&"sold", false)) else 0])
	var service: Dictionary = stock.get(&"remove_service", {})
	parts.append("remove=%d/%d" % [service.get(&"price", 0), 1 if bool(service.get(&"sold", false)) else 0])
	return "|".join(parts)


static func _card_stock(card_id: StringName, price: int) -> Dictionary:
	return {&"card_id": card_id, &"price": price, &"sold": false}
