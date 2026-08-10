extends SceneTree

const SEEDS: Array[int] = [
	73103, 80011, 91027, 100003, 110009, 120011,
	130027, 140053, 150061, 160073, 170081, 180097,
]

enum RoutePolicy {
	EVENT_ECONOMY,
	BATTLE_INCOME,
}

var failures: int = 0


func _init() -> void:
	var event_results: Array[Dictionary] = []
	var battle_results: Array[Dictionary] = []
	for seed_value: int in SEEDS:
		var event_run: Dictionary = _simulate(seed_value, RoutePolicy.EVENT_ECONOMY)
		var event_replay: Dictionary = _simulate(seed_value, RoutePolicy.EVENT_ECONOMY)
		var battle_run: Dictionary = _simulate(seed_value, RoutePolicy.BATTLE_INCOME)
		var battle_replay: Dictionary = _simulate(seed_value, RoutePolicy.BATTLE_INCOME)
		_expect(event_run[&"digest"] == event_replay[&"digest"], "event route seed %d fully reproduces" % seed_value)
		_expect(battle_run[&"digest"] == battle_replay[&"digest"], "battle route seed %d fully reproduces" % seed_value)
		event_results.append(event_run)
		battle_results.append(battle_run)
	_summarize_and_assert(event_results, battle_results)
	if failures == 0:
		print("PASS: all M1 expedition simulation thresholds")
		quit(0)
	else:
		push_error("FAIL: %d M1 expedition simulation thresholds failed" % failures)
		quit(1)


func _simulate(seed_value: int, policy: RoutePolicy) -> Dictionary:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value)
	var purchased_cards: int = 0
	var spent_ink: int = 0
	var shop_entry_ink: int = -1
	var cheapest_common: int = -1
	var common_affordable: bool = false
	var relic_affordable: bool = false
	var removal_affordable: bool = false
	var removal_plus_common_affordable: bool = false
	var high_event_income: bool = false
	var upgraded: bool = false
	while true:
		if run.available_node_ids.is_empty():
			break
		var node_id: StringName = _choose_node(run, policy)
		if not run.enter_node(node_id):
			break
		var node: MapNode = run.get_current_map_node()
		match node.node_type:
			MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
				run.record_current_battle_victory()
				run.generate_reward_choices(node.depth)
				run.skip_reward()
				run.complete_current_node()
			MapNode.NodeType.EVENT:
				var ink_before: int = run.ink_crystals
				var choice_index: int = 0
				if run.selected_event_id == &"authorless_book" or run.selected_event_id == &"calibration_station":
					choice_index = 1
				run.apply_event_choice(choice_index)
				high_event_income = run.ink_crystals - ink_before >= 60
				run.complete_current_node()
			MapNode.NodeType.SHOP:
				shop_entry_ink = run.ink_crystals
				var stock: Dictionary = run.pending_shop_stock
				var common_index: int = _cheapest_common_index(stock)
				if common_index >= 0:
					cheapest_common = int((stock[&"cards"] as Array)[common_index][&"price"])
					common_affordable = run.ink_crystals >= cheapest_common
				var relic_price: int = int((stock[&"relic"] as Dictionary)[&"price"])
				var remove_price: int = int((stock[&"remove_service"] as Dictionary)[&"price"])
				relic_affordable = run.ink_crystals >= relic_price
				removal_affordable = run.ink_crystals >= remove_price
				removal_plus_common_affordable = common_index >= 0 and run.ink_crystals >= remove_price + cheapest_common
				if common_affordable:
					var before_purchase: int = run.ink_crystals
					if run.buy_shop_card(common_index):
						purchased_cards += 1
						spent_ink += before_purchase - run.ink_crystals
				run.finish_shop()
				run.complete_current_node()
			MapNode.NodeType.FORGE:
				var candidates: Array[Dictionary] = run.get_unupgraded_instances()
				if candidates.is_empty():
					run.skip_forge()
				else:
					upgraded = run.resolve_forge_upgrade(int(candidates[0][&"instance_id"]))
				run.complete_current_node()
			MapNode.NodeType.REST:
				if policy == RoutePolicy.EVENT_ECONOMY and node.depth == 3:
					run.resolve_rest_salvage()
				else:
					run.skip_rest()
				run.complete_current_node()
			MapNode.NodeType.BOSS:
				# 远征经济模拟只验证路线/经济；Boss战本体由sim_boss覆盖。
				run.record_boss_outcome(&"deliver_seal", 0)
				run.complete_current_node()
				break
	var unique_ids: Dictionary = {}
	var upgraded_count: int = 0
	var deck_parts: Array[String] = []
	for instance: Dictionary in run.deck_instances:
		unique_ids[int(instance[&"instance_id"])] = true
		if instance[&"upgrade_id"] != &"":
			upgraded_count += 1
		deck_parts.append("%d/%s/%s" % [instance[&"instance_id"], instance[&"card_id"], instance[&"upgrade_id"]])
	return {
		&"seed": seed_value,
		&"policy": policy,
		&"reached_boss": run.map_graph.get_node(run.map_graph.boss_node_id).completed,
		&"completed_nodes": _completed_count(run),
		&"visited": run.visited_node_ids.duplicate(),
		&"shop_entry_ink": shop_entry_ink,
		&"cheapest_common": cheapest_common,
		&"common_affordable": common_affordable,
		&"relic_affordable": relic_affordable,
		&"removal_affordable": removal_affordable,
		&"removal_plus_common_affordable": removal_plus_common_affordable,
		&"high_event_income": high_event_income,
		&"purchased_cards": purchased_cards,
		&"spent_ink": spent_ink,
		&"upgraded": upgraded,
		&"upgraded_count": upgraded_count,
		&"unique_instances": unique_ids.size() == run.deck_instances.size(),
		&"final_ink": run.ink_crystals,
		&"digest": "%s|visited=%s|deck=%s|ink=%d|spent=%d" % [
			run.map_graph.digest(), str(run.visited_node_ids), ",".join(deck_parts),
			run.ink_crystals, spent_ink,
		],
	}


func _choose_node(run: RunModel, policy: RoutePolicy) -> StringName:
	if run.available_node_ids.size() == 1:
		return run.available_node_ids[0]
	var wanted: Array[int] = []
	if policy == RoutePolicy.EVENT_ECONOMY:
		wanted = [MapNode.NodeType.EVENT, MapNode.NodeType.SHOP, MapNode.NodeType.FORGE]
	else:
		wanted = [MapNode.NodeType.BATTLE, MapNode.NodeType.SHOP, MapNode.NodeType.ELITE]
	for wanted_type: int in wanted:
		for node_id: StringName in run.available_node_ids:
			if run.map_graph.get_node(node_id).node_type == wanted_type:
				return node_id
	return run.available_node_ids[0]


func _cheapest_common_index(stock: Dictionary) -> int:
	var result: int = -1
	var best_price: int = 1_000_000
	var cards: Array = stock.get(&"cards", [])
	for index: int in range(cards.size()):
		var item: Dictionary = cards[index] as Dictionary
		var definition: Dictionary = CardCatalog.get_definition(item[&"card_id"] as StringName)
		if str(definition[&"rarity"]) != "普通":
			continue
		if int(item[&"price"]) < best_price:
			best_price = int(item[&"price"])
			result = index
	return result


func _completed_count(run: RunModel) -> int:
	var count: int = 0
	for raw_node: Variant in run.map_graph.nodes_by_id.values():
		if (raw_node as MapNode).completed:
			count += 1
	return count


func _summarize_and_assert(event_results: Array[Dictionary], battle_results: Array[Dictionary]) -> void:
	var event_common: int = _count_true(event_results, &"common_affordable")
	var event_high_income: int = _count_true(event_results, &"high_event_income")
	var event_removal: int = _count_true(event_results, &"removal_affordable")
	var battle_common: int = _count_true(battle_results, &"common_affordable")
	var purchases: int = _sum_int(event_results, &"purchased_cards") + _sum_int(battle_results, &"purchased_cards")
	var spent: int = _sum_int(event_results, &"spent_ink") + _sum_int(battle_results, &"spent_ink")
	print("《断环》M1 远征经济模拟｜固定种子 %d 个｜两种路线 %d 局" % [SEEDS.size(), event_results.size() + battle_results.size()])
	print("事件经济路线：高额事件 %d/%d｜第4层普通卡可负担 %d/%d｜首次移除可负担 %d/%d" % [
		event_high_income, event_results.size(), event_common, event_results.size(), event_removal, event_results.size(),
	])
	print("战斗收入路线：第4层普通卡可负担 %d/%d｜无高额事件时遗物可负担 %d/%d" % [
		battle_common, battle_results.size(), _count_true(battle_results, &"relic_affordable"), battle_results.size(),
	])
	print("消费闭环：购买卡牌 %d 张｜总支出 %d 墨晶｜锻造升级 %d/%d 局" % [
		purchases, spent, _count_true(event_results, &"upgraded"), event_results.size(),
	])
	for result: Dictionary in event_results + battle_results:
		_expect(bool(result[&"reached_boss"]), "seed %d policy %d reaches the Boss placeholder" % [result[&"seed"], result[&"policy"]])
		_expect(int(result[&"completed_nodes"]) == 9, "seed %d policy %d completes exactly one node per depth" % [result[&"seed"], result[&"policy"]])
		_expect(bool(result[&"unique_instances"]), "seed %d policy %d keeps deck instance ids unique" % [result[&"seed"], result[&"policy"]])
	_expect(float(event_common) / float(event_results.size()) >= 0.5, "event-oriented routes can usually afford one common card at depth four")
	_expect(_count_true(battle_results, &"relic_affordable") == 0, "routes without high event income cannot afford a relic at depth four")
	_expect(purchases > 0 and spent > 0, "ink has both battle/event sources and actual shop sinks")
	_expect(_count_true(event_results, &"upgraded") == event_results.size(), "forge route upgrades one card in every simulated expedition")
	var forced_tradeoffs: int = 0
	for result: Dictionary in event_results:
		if bool(result[&"removal_affordable"]) and not bool(result[&"high_event_income"]):
			forced_tradeoffs += 1
			_expect(not bool(result[&"removal_plus_common_affordable"]), "seed %d without event windfall must choose between first removal and a common card" % result[&"seed"])
	_expect(forced_tradeoffs > 0, "at least one event route faces the intended removal-versus-purchase tradeoff")
	_expect(str(event_results[0][&"digest"]) != str(battle_results[0][&"digest"]), "route choice changes the deterministic expedition fingerprint")


func _count_true(results: Array[Dictionary], key: StringName) -> int:
	var count: int = 0
	for result: Dictionary in results:
		if bool(result[key]):
			count += 1
	return count


func _sum_int(results: Array[Dictionary], key: StringName) -> int:
	var total: int = 0
	for result: Dictionary in results:
		total += int(result[key])
	return total


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
