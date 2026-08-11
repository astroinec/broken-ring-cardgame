class_name ShopCatalog
extends RefCounted


const COMMON_CARD_IDS: Array[StringName] = [
	&"broken_sentence", &"blank_space", &"index_reorder", &"unsigned_support",
	&"rift_slash", &"forced_stability", &"delayed_guard", &"countdown_scar",
	&"restate", &"copied_guard", &"reverse_index", &"delete_redundancy", &"borrowed_name_execution",
]
const RARE_CARD_IDS: Array[StringName] = [
	&"critical_permission", &"dissolution_protocol", &"prewritten_ending", &"unseal_order", &"homophone",
	&"missing_name_arbitration", &"tenth_answer", &"echo_chamber",
]


static func generate(
	content_seed: int,
	remove_count: int,
	owned_relics: Array[StringName] = [],
	unlocked_card_ids: Array[StringName] = [],
	run_seen_reward_ids: Array[StringName] = []
) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = content_seed
	var allowed: Array[StringName] = unlocked_card_ids.duplicate()
	if allowed.is_empty():
		allowed = CardCatalog.REWARD_IDS.duplicate()
	var cards: Array[Dictionary] = []
	var unseen: Array[StringName] = []
	for card_id: StringName in allowed:
		if not run_seen_reward_ids.has(card_id):
			unseen.append(card_id)
	var first_pool: Array[StringName] = unseen if not unseen.is_empty() else allowed
	var rare_count: int = 0
	if not first_pool.is_empty():
		var first_id: StringName = first_pool[rng.randi_range(0, first_pool.size() - 1)]
		cards.append(_card_stock(first_id, _price_for(first_id, rng)))
		rare_count += 1 if RARE_CARD_IDS.has(first_id) else 0
		allowed.erase(first_id)
	while cards.size() < 3 and not allowed.is_empty():
		var candidates: Array[StringName] = []
		for card_id: StringName in allowed:
			if rare_count == 0 or not RARE_CARD_IDS.has(card_id):
				candidates.append(card_id)
		if candidates.is_empty():
			break
		var card_id: StringName = candidates[rng.randi_range(0, candidates.size() - 1)]
		cards.append(_card_stock(card_id, _price_for(card_id, rng)))
		rare_count += 1 if RARE_CARD_IDS.has(card_id) else 0
		allowed.erase(card_id)
	var relic_stock: Dictionary = {}
	var relic_pool: Array[StringName] = RelicCatalog.get_shop_offer_ids(owned_relics)
	if not relic_pool.is_empty():
		var relic_id: StringName = relic_pool[rng.randi_range(0, relic_pool.size() - 1)]
		relic_stock = {&"relic_id": relic_id, &"price": rng.randi_range(130, 170), &"sold": false}
	return {
		&"content_seed": content_seed,
		&"cards": cards,
		&"relic": relic_stock,
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


static func _price_for(card_id: StringName, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(65, 80) if RARE_CARD_IDS.has(card_id) else rng.randi_range(35, 45)


static func _card_stock(card_id: StringName, price: int) -> Dictionary:
	return {&"card_id": card_id, &"price": price, &"sold": false}
