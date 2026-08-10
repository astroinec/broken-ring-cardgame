extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_shop_determinism_and_ranges()
	_test_purchase_atomicity()
	_test_removal_service()
	_test_elite_rewards()
	_test_shop_relic_pool()
	_test_instance_upgrade()
	_test_rest_and_forge()
	_test_rest_salvage_tradeoff()
	if failures == 0:
		print("PASS: all economy and upgrade checks")
		quit(0)
	else:
		push_error("FAIL: %d economy checks failed" % failures)
		quit(1)


func _test_shop_determinism_and_ranges() -> void:
	var first: Dictionary = ShopCatalog.generate(73103, 0)
	var second: Dictionary = ShopCatalog.generate(73103, 0)
	_expect(first == second, "same node seed reproduces shop stock and prices")
	var cards: Array = first[&"cards"]
	_expect(cards.size() == 3, "shop has three card offers")
	var seen: Array[StringName] = []
	var rare_count: int = 0
	for raw_item: Variant in cards:
		var item: Dictionary = raw_item as Dictionary
		var card_id: StringName = item[&"card_id"] as StringName
		_expect(not seen.has(card_id), "shop card offers are unique")
		seen.append(card_id)
		var rarity: String = str(CardCatalog.get_definition(card_id)[&"rarity"])
		var price: int = int(item[&"price"])
		if rarity == "罕见":
			rare_count += 1
			_expect(price >= 65 and price <= 80, "rare card price is 65-80")
		else:
			_expect(price >= 35 and price <= 45, "common card price is 35-45")
	_expect(rare_count <= 1, "shop has at most one rare card")
	var relic: Dictionary = first[&"relic"]
	_expect(int(relic[&"price"]) >= 130 and int(relic[&"price"]) <= 170, "relic price is 130-170")
	_expect(int(first[&"remove_service"][&"price"]) == 75, "first removal costs 75")
	_expect(int(ShopCatalog.generate(73103, 1)[&"remove_service"][&"price"]) == 100, "second removal costs 100")


func _test_purchase_atomicity() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	var stock: Dictionary = ShopCatalog.generate(91027, 0)
	var shop: ShopModel = ShopModel.new(stock)
	var initial_size: int = run.deck_instances.size()
	var initial_stock: Dictionary = shop.stock.duplicate(true)
	_expect(not shop.buy_card(run, 0), "unaffordable purchase fails")
	_expect(run.ink_crystals == 0 and run.deck_instances.size() == initial_size, "failed purchase has no run-state side effects")
	_expect(shop.stock == initial_stock, "failed purchase does not mutate stock")
	run.ink_crystals = 999
	var price: int = int((shop.stock[&"cards"] as Array)[0][&"price"])
	_expect(shop.buy_card(run, 0), "affordable card purchase succeeds")
	_expect(run.ink_crystals == 999 - price, "purchase deducts exact price once")
	_expect(run.deck_instances.size() == initial_size + 1, "purchase creates one card instance")
	_expect(not shop.buy_card(run, 0), "sold card cannot be bought twice")
	var relic_price: int = int(shop.stock[&"relic"][&"price"])
	var relic_id: StringName = shop.stock[&"relic"][&"relic_id"] as StringName
	_expect(shop.buy_relic(run), "relic purchase succeeds")
	_expect(run.relics.has(relic_id), "purchased relic enters run state")
	_expect(run.ink_crystals == 999 - price - relic_price, "relic deducts exact price")


func _test_removal_service() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	run.ink_crystals = 500
	var target: Dictionary = run.deck_instances[0].duplicate(true)
	var same_id_count_before: int = run.get_deck_card_ids().count(target[&"card_id"])
	var shop: ShopModel = ShopModel.new(ShopCatalog.generate(80011, 0))
	_expect(shop.remove_card(run, int(target[&"instance_id"])), "removal service removes selected instance")
	_expect(not run.has_deck_instance(int(target[&"instance_id"])), "selected instance no longer exists")
	_expect(run.get_deck_card_ids().count(target[&"card_id"]) == same_id_count_before - 1, "other copies remain intact")
	_expect(run.ink_crystals == 425 and run.shop_remove_count == 1, "removal deducts 75 and increments count")
	_expect(not shop.remove_card(run, int(run.deck_instances[0][&"instance_id"])), "one shop removal service cannot be reused")

	var stamped: RunModel = RunModel.new()
	stamped.start_run(73103)
	stamped.relics.append(&"seventh_dock_stamp")
	stamped.ink_crystals = 500
	var stamped_shop: ShopModel = ShopModel.new(ShopCatalog.generate(80011, 0, stamped.relics))
	var stamped_target: int = int(stamped.deck_instances[0][&"instance_id"])
	_expect(stamped_shop.get_remove_price(stamped) == 50, "dock stamp lowers removal price by exactly twenty-five")
	_expect(stamped_shop.remove_card(stamped, stamped_target), "discounted removal succeeds")
	_expect(stamped.ink_crystals == 450, "discounted removal deducts fifty ink")
	var telemetry: Dictionary = stamped_shop.get_relic_telemetry()
	_expect(int((telemetry[&"trigger_counts"] as Dictionary).get(&"seventh_dock_stamp", 0)) == 1, "dock stamp records one consumed discount")
	_expect(int((telemetry[&"net_benefits"] as Dictionary).get(&"seventh_dock_stamp", 0)) == 25, "dock stamp telemetry records twenty-five ink saved")


func _test_elite_rewards() -> void:
	var selected: RunModel = _enter_elite(73103)
	_expect(selected.record_current_battle_victory(), "elite victory settles its base reward")
	_expect(not selected.record_current_battle_victory(), "elite base reward cannot settle twice")
	_expect(selected.ink_crystals == 30, "elite victory grants exactly thirty ink")
	var selected_reward: Dictionary = selected.get_pending_elite_reward()
	_expect(selected_reward.get(&"kind", &"") == &"relic", "elite prepares a relic when an eligible one remains")
	var selected_relic: StringName = selected_reward.get(&"relic_id", &"") as StringName
	_expect(selected_relic != &"" and not selected.relics.has(selected_relic), "elite fixed seed chooses an unowned relic")
	var repeated: RunModel = _enter_elite(73103)
	repeated.record_current_battle_victory()
	_expect(repeated.get_pending_elite_reward().get(&"relic_id", &"") == selected_relic, "elite relic choice reproduces for the same seed and ownership")
	var choices: Array[StringName] = selected.generate_reward_choices(6)
	_expect(choices.size() == 3, "elite offers three card choices")
	var rare_count: int = 0
	for card_id: StringName in choices:
		if str(CardCatalog.get_definition(card_id).get(&"rarity", "")) == "罕见":
			rare_count += 1
	_expect(rare_count >= 1, "elite card choices contain at least one rare card")
	_expect(not selected.relics.has(selected_relic), "elite relic remains pending before card choice")
	selected.mark_current_node_resolved()
	_expect(not selected.complete_current_node(), "elite node cannot complete before card reward settles")
	_expect(selected.choose_reward(0), "choosing an elite card settles the pending relic")
	_expect(selected.relics.count(selected_relic) == 1, "card choice grants the elite relic exactly once")
	var selected_relic_count: int = selected.relics.size()
	_expect(not selected.choose_reward(0) and not selected.skip_reward(), "settled elite reward cannot be selected or skipped again")
	_expect(selected.relics.size() == selected_relic_count, "repeated settlement attempts do not duplicate the elite relic")
	_expect(selected.complete_current_node(), "settled elite node completes once")
	_expect(not selected.complete_current_node(), "completed elite node cannot complete twice")

	var skipped: RunModel = _enter_elite(73103)
	skipped.record_current_battle_victory()
	var skipped_relic: StringName = skipped.get_pending_elite_reward().get(&"relic_id", &"") as StringName
	skipped.generate_reward_choices(6)
	_expect(skipped.skip_reward(), "skipping elite cards settles the pending relic")
	_expect(skipped.relics.count(skipped_relic) == 1, "card skip grants the elite relic exactly once")
	_expect(not skipped.skip_reward(), "elite card skip cannot settle twice")

	var fallback: RunModel = _enter_elite(73103)
	for relic_id: StringName in RelicCatalog.get_elite_drop_ids():
		if not fallback.relics.has(relic_id):
			fallback.relics.append(relic_id)
	fallback.record_current_battle_victory()
	var fallback_reward: Dictionary = fallback.get_pending_elite_reward()
	_expect(fallback_reward.get(&"kind", &"") == &"ink" and int(fallback_reward.get(&"amount", 0)) == 50, "owning every elite relic prepares fifty replacement ink")
	_expect(fallback.ink_crystals == 30, "replacement ink remains pending before card resolution")
	fallback.generate_reward_choices(6)
	_expect(fallback.skip_reward(), "skipping cards settles elite replacement ink")
	_expect(fallback.ink_crystals == 80, "elite grants thirty base ink plus fifty replacement ink once")
	_expect(not fallback.skip_reward() and fallback.ink_crystals == 80, "replacement ink cannot settle twice")


func _test_shop_relic_pool() -> void:
	var purchasable: Array[StringName] = RelicCatalog.get_shop_offer_ids()
	var stock: Dictionary = ShopCatalog.generate(73103, 0)
	var relic: Dictionary = stock.get(&"relic", {})
	var relic_id: StringName = relic.get(&"relic_id", &"") as StringName
	_expect(relic_id != &"" and purchasable.has(relic_id), "shop relic comes from the purchasable pool")
	var owned: Array[StringName] = [relic_id]
	var without_owned: Dictionary = ShopCatalog.generate(73103, 0, owned)
	var replacement: Dictionary = without_owned.get(&"relic", {})
	_expect(replacement.is_empty() or replacement.get(&"relic_id", &"") != relic_id, "shop never repeats an owned relic")
	var exhausted: Dictionary = ShopCatalog.generate(73103, 0, purchasable)
	_expect((exhausted.get(&"relic", {}) as Dictionary).is_empty(), "shop omits relic stock when the purchasable pool is fully owned")


func _enter_elite(seed_value: int) -> RunModel:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value)
	var elite_ids: Array[StringName] = [&"d06_00"]
	run.available_node_ids = elite_ids
	var elite: MapNode = run.map_graph.get_node(&"d06_00")
	elite.revealed = true
	elite.reachable = true
	_expect(elite.node_type == MapNode.NodeType.ELITE and run.enter_node(&"d06_00"), "test enters the deterministic elite node")
	return run


func _test_instance_upgrade() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	var first: Dictionary = run.deck_instances[0].duplicate(true)
	var second: Dictionary = run.deck_instances[1].duplicate(true)
	_expect(first[&"card_id"] == second[&"card_id"], "test has two copies of same card")
	_expect(run.upgrade_card_instance(int(first[&"instance_id"])), "specific instance upgrades")
	var upgraded: Dictionary = run.get_deck_instance(int(first[&"instance_id"]))
	var untouched: Dictionary = run.get_deck_instance(int(second[&"instance_id"]))
	_expect(upgraded[&"upgrade_id"] != &"", "selected instance stores upgrade id")
	_expect(untouched[&"upgrade_id"] == &"", "same-card sibling remains unupgraded")
	var upgraded_card: CardData = CardCatalog.create_card(upgraded[&"card_id"], int(upgraded[&"instance_id"]), upgraded[&"upgrade_id"])
	var base_card: CardData = CardCatalog.create_card(untouched[&"card_id"], int(untouched[&"instance_id"]), untouched[&"upgrade_id"])
	_expect(upgraded_card.title.ends_with("+"), "upgraded battle card title shows plus")
	_expect(upgraded_card.description != base_card.description, "upgrade changes battle card rules text")
	_expect(not run.upgrade_card_instance(int(first[&"instance_id"])), "same instance cannot upgrade twice")
	_expect(CardUpgradeCatalog.DEFINITIONS.size() == 19, "all nineteen formal cards have upgrade data")
	for card_id: StringName in CardUpgradeCatalog.DEFINITIONS:
		var definition: Dictionary = CardUpgradeCatalog.get_definition(card_id)
		_expect((definition[&"upgrades"] as Array).size() >= 1, "%s upgrade schema reserves branches" % card_id)


func _test_rest_and_forge() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	# Progress deterministically to depth three REST.
	for depth: int in [1, 2]:
		var node_id: StringName = run.available_node_ids[0]
		var node: MapNode = run.map_graph.get_node(node_id)
		run.enter_node(node_id)
		if node.node_type == MapNode.NodeType.BATTLE:
			run.record_current_battle_victory()
			run.generate_reward_choices(node.depth)
			run.skip_reward()
		else:
			run.apply_event_choice(0)
		run.complete_current_node()
	var rest_id: StringName = run.available_node_ids[0]
	_expect(run.enter_node(rest_id), "enter rest node")
	run.player_hp = 30
	_expect(run.resolve_rest_heal(), "rest heal resolves")
	_expect(run.player_hp == 44, "rest heals twenty percent of max hp")
	_expect(run.complete_current_node(), "rest node completes once")
	# Choose forge lane at depth six after resolving depths four and five.
	for depth: int in [4, 5]:
		var chosen: StringName = run.available_node_ids[0]
		var node: MapNode = run.map_graph.get_node(chosen)
		run.enter_node(chosen)
		if node.node_type == MapNode.NodeType.BATTLE:
			run.record_current_battle_victory(); run.generate_reward_choices(node.depth); run.skip_reward()
		elif node.node_type == MapNode.NodeType.EVENT:
			run.apply_event_choice(0)
		else:
			run.mark_current_node_resolved()
		run.complete_current_node()
	var forge_id: StringName = &""
	for candidate: StringName in run.available_node_ids:
		if run.map_graph.get_node(candidate).node_type == MapNode.NodeType.FORGE:
			forge_id = candidate
	_expect(forge_id != &"", "depth six exposes forge lane")
	run.enter_node(forge_id)
	var target: Dictionary = run.get_unupgraded_instances()[0]
	_expect(run.resolve_forge_upgrade(int(target[&"instance_id"])), "forge upgrades selected instance for free")
	_expect(run.complete_current_node(), "forge node completes")


func _test_rest_salvage_tradeoff() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	var rest_ids: Array[StringName] = [&"d03_00"]
	run.available_node_ids = rest_ids
	_expect(run.enter_node(&"d03_00"), "test can enter the depth-three rest node")
	var before_ink: int = run.ink_crystals
	_expect(run.resolve_rest_salvage(), "rest can be spent on salvage income")
	_expect(run.ink_crystals == before_ink + RunModel.REST_SALVAGE_INCOME, "rest salvage grants exactly thirty ink")
	_expect(not run.resolve_rest_heal(), "resolved rest cannot also heal")
	_expect(not run.resolve_rest_upgrade(int(run.deck_instances[0][&"instance_id"])), "resolved rest cannot also upgrade")
	_expect(run.complete_current_node(), "salvage rest completes through node protocol")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
