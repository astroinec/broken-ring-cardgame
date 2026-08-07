extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_shop_determinism_and_ranges()
	_test_purchase_atomicity()
	_test_removal_service()
	_test_instance_upgrade()
	_test_rest_and_forge()
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


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
