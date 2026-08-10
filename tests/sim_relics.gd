extends SceneTree


const BASE_SEED: int = 94000

var failures: int = 0


func _init() -> void:
	var relic_ids: Array[StringName] = RelicCatalog.get_all_ids()
	for index: int in range(relic_ids.size()):
		var relic_id: StringName = relic_ids[index]
		var scenario_seed: int = BASE_SEED + index
		var first: Dictionary = _run_scenario(relic_id, scenario_seed)
		var repeated: Dictionary = _run_scenario(relic_id, scenario_seed)
		var triggers: int = int(first.get(&"triggers", 0))
		var net_benefit: int = int(first.get(&"net_benefit", 0))
		print("RELIC_SIM %s seed=%d triggers=%d net=%d fingerprint=%s" % [
			relic_id, scenario_seed, triggers, net_benefit, first.get(&"fingerprint", ""),
		])
		_expect(first == repeated, "%s pressure scenario is reproducible" % relic_id)
		_expect(triggers >= 1, "%s triggers at least once" % relic_id)
	if failures == 0:
		print("PASS: all eight relic pressure simulations are reproducible")
		quit(0)
	else:
		push_error("FAIL: %d relic simulation checks failed" % failures)
		quit(1)


func _run_scenario(relic_id: StringName, scenario_seed: int) -> Dictionary:
	if relic_id == &"seventh_dock_stamp":
		return _run_stamp_scenario(scenario_seed)
	var model: CombatModel
	if relic_id == &"calibrator_red_pen":
		var deck: Array[Dictionary] = [
			{&"instance_id": 1, &"card_id": &"calibration_strike", &"upgrade_id": &"calibration_strike_plus"},
			{&"instance_id": 2, &"card_id": &"temporary_guard", &"upgrade_id": &""},
			{&"instance_id": 3, &"card_id": &"restate", &"upgrade_id": &""},
		]
		var red_pen_relics: Array[StringName] = [relic_id]
		model = CombatModel.new()
		model.start_battle(scenario_seed, 6, [], &"pressure_archivist", red_pen_relics, deck)
	else:
		model = _start_with_relic(relic_id, scenario_seed)

	match relic_id:
		&"crack_stabilizer":
			model._gain_instability(3)
			model._gain_instability(2)
		&"wordless_bookplate":
			_prepare_hand(model, [&"boundary_read"])
			model.play_card(0)
		&"calibrator_red_pen":
			_prepare_hand(model, [&"calibration_strike"])
			model.play_card(0)
		&"delay_gear":
			_prepare_hand(model, [&"delayed_guard"])
			model.play_card(0)
			model.end_player_turn()
		&"echo_hyoid":
			_prepare_hand(model, [&"calibration_strike", &"restate"])
			model.play_card(0)
			model.play_card(0)
		&"blank_epitaph":
			_prepare_hand(model, [&"calibration_strike", &"temporary_guard"])
			model.player_hp = 36
			model._deal_damage_to_player(2, "遗物压测")
		&"expired_return_bell":
			model.player_hp = 5
			model._deal_damage_to_player(6, "遗物压测")
		_:
			push_error("缺少遗物压测场景：%s" % relic_id)
	return _combat_result(model, relic_id)


func _run_stamp_scenario(scenario_seed: int) -> Dictionary:
	var run: RunModel = RunModel.new()
	run.start_run(scenario_seed)
	run.relics.append(&"seventh_dock_stamp")
	run.ink_crystals = 200
	var shop: ShopModel = ShopModel.new(ShopCatalog.generate(scenario_seed, 0, run.relics))
	var target_id: int = int(run.deck_instances[0][&"instance_id"])
	var removed: bool = shop.remove_card(run, target_id)
	var telemetry: Dictionary = shop.get_relic_telemetry()
	var counts: Dictionary = telemetry[&"trigger_counts"]
	var benefits: Dictionary = telemetry[&"net_benefits"]
	return {
		&"triggers": int(counts.get(&"seventh_dock_stamp", 0)),
		&"net_benefit": int(benefits.get(&"seventh_dock_stamp", 0)),
		&"fingerprint": "%d/%d/%d" % [run.ink_crystals, run.deck_instances.size(), 1 if removed else 0],
	}


func _start_with_relic(relic_id: StringName, scenario_seed: int) -> CombatModel:
	var relics: Array[StringName] = [relic_id]
	var bonus_cards: Array[StringName] = [
		&"boundary_read", &"delayed_guard", &"restate", &"copied_guard",
	]
	var model: CombatModel = CombatModel.new()
	model.start_battle(scenario_seed, 6, bonus_cards, &"pressure_archivist", relics)
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
	_expect(false, "pressure deck contains %s" % card_id)
	return null


func _combat_result(model: CombatModel, relic_id: StringName) -> Dictionary:
	var telemetry: Dictionary = model.get_telemetry()
	var counts: Dictionary = telemetry[&"relic_trigger_counts"]
	var benefits: Dictionary = telemetry[&"relic_net_benefits"]
	return {
		&"triggers": int(counts.get(relic_id, 0)),
		&"net_benefit": int(benefits.get(relic_id, 0)),
		&"fingerprint": "%d/%d/%d/%d/%d/%d" % [
			model.player_hp, model.player_block, model.enemy_hp, model.instability,
			model.sealed_zone.size(), int(telemetry[&"fractures"]),
		],
	}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
