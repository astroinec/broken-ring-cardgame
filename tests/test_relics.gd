extends SceneTree


var failures: int = 0


func _init() -> void:
	_test_catalog()
	_test_crack_stabilizer()
	_test_wordless_bookplate()
	_test_calibrator_red_pen()
	_test_delay_gear()
	_test_echo_hyoid()
	_test_seventh_dock_stamp()
	_test_blank_epitaph()
	_test_expired_return_bell()
	if failures == 0:
		print("PASS: all eight relic checks")
		quit(0)
	else:
		push_error("FAIL: %d relic checks failed" % failures)
		quit(1)


func _test_catalog() -> void:
	_expect(RelicCatalog.get_all_ids().size() == 8, "catalog contains eight relics")
	for relic_id: StringName in RelicCatalog.get_all_ids():
		var definition: Dictionary = RelicCatalog.get_definition(relic_id)
		for field: StringName in [&"id", &"title", &"rarity", &"description", &"flavor", &"source_hint", &"implemented"]:
			_expect(definition.has(field), "%s has catalog field %s" % [relic_id, field])
		_expect(bool(definition[&"implemented"]), "%s is marked implemented" % relic_id)
		_expect(RuleEngine.RELIC_DEFINITIONS.has(relic_id), "rule engine compatibility proxy exposes %s" % relic_id)
	var bell: Dictionary = RelicCatalog.get_definition(&"expired_return_bell")
	_expect(str(bell[&"description"]).contains("可能仍被后续裂解杀死"), "return bell full text explicitly warns about later fracture death")
	_expect(str(bell[&"short_description"]).contains("可能仍被后续裂解杀死"), "return bell HUD text keeps the same explicit warning")


func _test_crack_stabilizer() -> void:
	var model: CombatModel = _start_with_relic(&"crack_stabilizer", 91001)
	model._gain_instability(2)
	model._gain_instability(2)
	_expect(model.instability == 3, "stabilizer affects only the first instability gain")
	_expect(_triggers(model, &"crack_stabilizer") == 1, "stabilizer records one trigger")
	_expect(_benefit(model, &"crack_stabilizer") == 1, "stabilizer records one prevented instability")


func _test_wordless_bookplate() -> void:
	var model: CombatModel = _start_with_relic(&"wordless_bookplate", 91002)
	_prepare_hand(model, [&"boundary_read", &"forced_stability"])
	var before: int = model.hand.size()
	model.play_card(0)
	_expect(model.hand.size() >= before, "bookplate adds a draw after the first law card")
	model.play_card(_find_hand(model, &"forced_stability"))
	_expect(_triggers(model, &"wordless_bookplate") == 1, "bookplate triggers once per battle")


func _test_calibrator_red_pen() -> void:
	var deck: Array[Dictionary] = [
		{&"instance_id": 1, &"card_id": &"calibration_strike", &"upgrade_id": &"calibration_strike_plus"},
		{&"instance_id": 2, &"card_id": &"temporary_guard", &"upgrade_id": &"temporary_guard_plus"},
	]
	var relics: Array[StringName] = [&"calibrator_red_pen"]
	var model: CombatModel = CombatModel.new()
	model.start_battle(91003, 6, [], &"pressure_archivist", relics, deck)
	_prepare_hand(model, [&"calibration_strike", &"temporary_guard"])
	var hp_before: int = model.enemy_hp
	model.play_card(0)
	_expect(model.enemy_hp == hp_before - 12, "red pen adds three to the first effective upgraded damage")
	model.play_card(0)
	_expect(model.player_block == 8, "red pen does not trigger again on upgraded block")
	_expect(_triggers(model, &"calibrator_red_pen") == 1, "red pen records one trigger")
	_expect(_benefit(model, &"calibrator_red_pen") == 3, "red pen records three benefit")
	_expect(_log_contains(model, "高于未升级基线"), "red pen writes a detection log")
	model.start_battle(91004, 6, [], &"pressure_archivist", relics, deck)
	_expect(_triggers(model, &"calibrator_red_pen") == 0, "red pen resets between battles")


func _test_delay_gear() -> void:
	var model: CombatModel = _start_with_relic(&"delay_gear", 91005)
	_prepare_hand(model, [&"delayed_guard", &"countdown_scar"])
	model.play_card(0)
	_expect(model.sealed_zone.size() == 1 and model.sealed_zone[0].sealed_turns == 0, "delay gear lowers the first seal countdown to zero")
	_expect(model.player_block == 0, "zero countdown does not recursively unseal inside the effect queue")
	model.play_card(0)
	_expect(model.sealed_zone.size() == 2 and model.sealed_zone[1].sealed_turns == 2, "delay gear only affects the first sealed card")
	model.end_player_turn()
	_expect(_find_hand(model, &"delayed_guard") >= 0, "zero-count card unseals in the next seal window")
	_expect(_triggers(model, &"delay_gear") == 1, "delay gear records one trigger")
	_expect(_log_contains(model, "下一次封存结算窗口"), "delay gear logs non-recursive timing")


func _test_echo_hyoid() -> void:
	var model: CombatModel = _start_with_relic(&"echo_hyoid", 91006)
	_prepare_hand(model, [&"calibration_strike", &"restate", &"calibration_strike", &"restate"])
	model.play_card(0)
	model.play_card(0)
	_expect(model.player_block == 3, "first successful echo grants three block")
	model.play_card(0)
	model.play_card(0)
	_expect(model.player_block == 3, "second successful echo in the same turn grants no extra block")
	model._start_player_turn()
	_prepare_hand(model, [&"calibration_strike", &"restate"])
	model.play_card(0)
	model.play_card(0)
	_expect(model.player_block == 3, "echo hyoid resets at the next player turn")
	_expect(_triggers(model, &"echo_hyoid") == 2, "echo hyoid telemetry counts per-turn triggers")


func _test_seventh_dock_stamp() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(91007)
	run.relics.append(&"seventh_dock_stamp")
	var stock: Dictionary = ShopCatalog.generate(91007, 0, run.relics)
	var shop: ShopModel = ShopModel.new(stock)
	_expect(shop.get_remove_price(run) == 50, "dock stamp reduces first removal from 75 to 50")
	stock[&"remove_service"][&"price"] = 10
	shop = ShopModel.new(stock)
	_expect(shop.get_remove_price(run) == 0, "dock stamp removal discount clamps at zero")
	run.available_node_ids = [&"d04_01"]
	if run.map_graph.get_node(&"d04_01").node_type == MapNode.NodeType.SHOP:
		run.enter_node(&"d04_01")
		_expect(run.can_view_shop_archive(), "dock stamp exposes the shop archive through RunModel")
		var before: String = ShopCatalog.digest(run.pending_shop_stock)
		_expect(not run.get_shop_archive_record().is_empty(), "shop archive record has rule-layer content")
		_expect(ShopCatalog.digest(run.pending_shop_stock) == before, "viewing the archive consumes no stock")


func _test_blank_epitaph() -> void:
	var model: CombatModel = _start_with_relic(&"blank_epitaph", 91008)
	_prepare_hand(model, [&"calibration_strike", &"temporary_guard"])
	model.player_hp = 42
	model._deal_damage_to_player(6, "半血压力")
	_expect(model.player_hp == 36, "epitaph does not trigger before crossing half hp")
	model._deal_damage_to_player(2, "半血压力")
	_expect(model.player_hp == 34, "crossing damage is fully settled before epitaph block")
	_expect(model.player_block == 12, "epitaph grants twelve block after crossing damage")
	_expect(model.sealed_zone.size() == 1, "epitaph seals one eligible hand card")
	var hp_after_trigger: int = model.player_hp
	model._deal_damage_to_player(5, "后续伤害")
	_expect(model.player_hp == hp_after_trigger, "epitaph block protects only later damage")
	_expect(_triggers(model, &"blank_epitaph") == 1, "epitaph triggers only once")
	var empty: CombatModel = _start_with_relic(&"blank_epitaph", 91009)
	empty.hand.clear()
	empty.player_hp = 36
	empty._deal_damage_to_player(2, "空手跨线")
	_expect(_triggers(empty, &"blank_epitaph") == 1, "empty hand still consumes epitaph trigger")
	_expect(_log_contains(empty, "没有合规非状态牌"), "empty-hand epitaph writes an explicit log")


func _test_expired_return_bell() -> void:
	var doomed: CombatModel = _start_with_relic(&"expired_return_bell", 91010)
	doomed.player_hp = 5
	doomed._deal_damage_to_player(6, "致命测试")
	_expect(doomed.battle_over and not doomed.victory and doomed.player_hp == 0, "bell can still die to its required fracture")
	_expect(_triggers(doomed, &"expired_return_bell") == 1, "bell records one trigger when it fails to save")
	var saved: CombatModel = _start_with_relic(&"expired_return_bell", 91011)
	saved.player_hp = 5
	saved.prevent_next_fracture_damage = true
	saved._deal_damage_to_player(6, "致命测试")
	_expect(not saved.battle_over and saved.player_hp == 1, "critical permission prevents the bell fracture and saves at one hp")
	_expect(not saved.prevent_next_fracture_damage, "bell fracture consumes critical permission")
	_expect(_log_contains(saved, "返航铃后续裂解"), "bell logs its immediate fracture clearly")


func _start_with_relic(relic_id: StringName, seed_value: int) -> CombatModel:
	var relics: Array[StringName] = [relic_id]
	var bonus_cards: Array[StringName] = [
		&"delayed_guard", &"countdown_scar", &"restate", &"copied_guard",
	]
	var model: CombatModel = CombatModel.new()
	model.start_battle(seed_value, 6, bonus_cards, &"pressure_archivist", relics)
	return model


func _prepare_hand(model: CombatModel, ids: Array[StringName]) -> void:
	while not model.hand.is_empty():
		model.discard_pile.append(model.hand.pop_back())
	for card_id: StringName in ids:
		var card: CardData = _extract(model, card_id)
		if card != null:
			model.hand.append(card)
	model.energy = 20


func _extract(model: CombatModel, card_id: StringName) -> CardData:
	for pile: Array[CardData] in [model.draw_pile, model.discard_pile]:
		for index: int in range(pile.size()):
			if pile[index].id == card_id:
				var card: CardData = pile[index]
				pile.remove_at(index)
				return card
	_expect(false, "test deck contains %s" % card_id)
	return null


func _find_hand(model: CombatModel, card_id: StringName) -> int:
	for index: int in range(model.hand.size()):
		if model.hand[index].id == card_id:
			return index
	return -1


func _triggers(model: CombatModel, relic_id: StringName) -> int:
	return int((model.get_telemetry()[&"relic_trigger_counts"] as Dictionary).get(relic_id, 0))


func _benefit(model: CombatModel, relic_id: StringName) -> int:
	return int((model.get_telemetry()[&"relic_net_benefits"] as Dictionary).get(relic_id, 0))


func _log_contains(model: CombatModel, fragment: String) -> bool:
	for entry: String in model.log_entries:
		if entry.contains(fragment):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
