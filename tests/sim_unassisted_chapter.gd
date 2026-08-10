extends SceneTree

const SEEDS: Array[int] = [
	73103, 80011, 91027, 100003, 110009, 120011, 130027, 140053, 150061, 160073,
	170081, 180097, 190121, 200131, 210143, 220147, 230153, 240169, 250183, 260191,
	270209, 280219, 290243, 300247, 310261, 320267, 330287, 340297, 350303, 360319,
]
const MAX_TURNS_PER_BATTLE: int = 60
const MAX_ACTIONS_PER_BATTLE: int = 600

enum Strategy {
	OFFENSE,
	STEADY,
	EVENT_ECONOMY,
}

var failures: int = 0


func _init() -> void:
	var all_results: Array[Dictionary] = []
	for strategy: Strategy in [Strategy.OFFENSE, Strategy.STEADY, Strategy.EVENT_ECONOMY]:
		for seed_value: int in SEEDS:
			var result: Dictionary = _simulate_chapter(seed_value, strategy)
			var replay: Dictionary = _simulate_chapter(seed_value, strategy)
			_expect(result[&"digest"] == replay[&"digest"], "%s seed %d 可完全复现" % [_strategy_name(strategy), seed_value])
			all_results.append(result)
	_summarize(all_results)
	_assert_thresholds(all_results)
	if failures == 0:
		print("PASS: 无辅助章节模拟阈值通过")
		quit(0)
	else:
		push_error("FAIL: %d 项无辅助章节模拟阈值未通过" % failures)
		quit(1)


func _simulate_chapter(seed_value: int, strategy: Strategy) -> Dictionary:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value)
	var reached_depth: int = 0
	var total_turns: int = 0
	var fractures: int = 0
	var timeout: bool = false
	var death_kind: StringName = &""
	var reached_boss: bool = false
	var boss_won: bool = false
	var elite_rewards: int = 0
	while not run.available_node_ids.is_empty() and run.player_hp > 0 and not run.run_completed:
		var node_id: StringName = _choose_node(run, strategy)
		if not run.enter_node(node_id):
			break
		var node: MapNode = run.get_current_map_node()
		reached_depth = maxi(reached_depth, node.depth)
		match node.node_type:
			MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
				var combat: Dictionary = _fight(run, node.enemy_id, node.content_seed, strategy)
				total_turns += int(combat[&"turns"])
				fractures += int(combat[&"fractures"])
				timeout = timeout or bool(combat[&"timeout"])
				run.player_hp = int(combat[&"hp"])
				if not bool(combat[&"won"]):
					death_kind = &"elite" if node.node_type == MapNode.NodeType.ELITE else &"normal"
					break
				run.record_current_battle_victory()
				run.generate_reward_choices(node.depth)
				var had_elite_reward: bool = not run.get_pending_elite_reward().is_empty()
				var reward_index: int = _choose_reward(run.pending_reward_ids, strategy)
				if reward_index >= 0:
					run.choose_reward(reward_index)
				else:
					run.skip_reward()
				if had_elite_reward:
					elite_rewards += 1
				run.complete_current_node()
			MapNode.NodeType.EVENT:
				_resolve_event(run, node, strategy)
				if run.player_hp <= 0:
					death_kind = &"normal"
					break
				if run.is_event_battle_pending():
					var event_combat: Dictionary = _fight(run, run.get_event_battle_enemy_id(), node.content_seed + 313, strategy)
					total_turns += int(event_combat[&"turns"])
					fractures += int(event_combat[&"fractures"])
					timeout = timeout or bool(event_combat[&"timeout"])
					run.player_hp = int(event_combat[&"hp"])
					if not bool(event_combat[&"won"]):
						death_kind = &"normal"
						break
					run.record_event_battle_victory()
				if run.event_resolved:
					run.complete_current_node()
			MapNode.NodeType.SHOP:
				_resolve_shop(run, strategy)
				run.finish_shop()
				run.complete_current_node()
			MapNode.NodeType.FORGE:
				var forge_candidates: Array[Dictionary] = run.get_unupgraded_instances()
				if forge_candidates.is_empty():
					run.skip_forge()
				else:
					run.resolve_forge_upgrade(_choose_upgrade_instance(run, forge_candidates, strategy))
				run.complete_current_node()
			MapNode.NodeType.REST:
				_resolve_rest(run, strategy, node.depth)
				run.complete_current_node()
			MapNode.NodeType.BOSS:
				reached_boss = true
				var boss: Dictionary = _fight(run, node.enemy_id, node.content_seed, strategy)
				total_turns += int(boss[&"turns"])
				fractures += int(boss[&"fractures"])
				timeout = timeout or bool(boss[&"timeout"])
				run.player_hp = int(boss[&"hp"])
				if not bool(boss[&"won"]):
					death_kind = &"boss"
					break
				boss_won = true
				run.record_boss_outcome(boss[&"choice"] as StringName, int(boss[&"recoveries"]))
				run.complete_current_node()
	var completed: bool = run.run_completed and boss_won
	return {
		&"seed": seed_value,
		&"strategy": strategy,
		&"completed": completed,
		&"reached_depth": reached_depth,
		&"reached_boss": reached_boss,
		&"boss_won": boss_won,
		&"death_kind": death_kind,
		&"turns": total_turns,
		&"hp": run.player_hp,
		&"relics": run.relics.size(),
		&"ink": run.ink_crystals,
		&"deck": run.deck_instances.size(),
		&"fractures": fractures,
		&"elite_rewards": elite_rewards,
		&"timeout": timeout,
		&"digest": "%d/%d/%d/%d/%d/%d/%d/%d/%d/%s/%d" % [
			1 if completed else 0, reached_depth, total_turns, run.player_hp, run.relics.size(),
			run.ink_crystals, run.deck_instances.size(), fractures, elite_rewards, death_kind,
			1 if timeout else 0,
		],
	}


func _fight(run: RunModel, enemy_id: StringName, battle_seed: int, strategy: Strategy) -> Dictionary:
	var model: CombatModel = CombatModel.new()
	model.start_battle(
		battle_seed, 6, [], enemy_id, run.get_relic_ids(), run.get_deck_instances(),
		run.player_hp, run.player_max_hp, run.consume_current_battle_context()
	)
	var actions: int = 0
	while not model.battle_over and model.turn_number <= MAX_TURNS_PER_BATTLE and actions < MAX_ACTIONS_PER_BATTLE:
		if model.boss_terminal_choice_pending:
			var choice: StringName = &"read_original" if model.can_choose_boss_original_text() else &"deliver_seal"
			model.choose_boss_terminal(choice)
			actions += 1
			continue
		if model.has_pending_selection():
			var candidates: Array[int] = model.get_pending_candidate_indices()
			if candidates.is_empty():
				model.cancel_pending_selection()
			else:
				model.resolve_pending_selection(_choose_pending_target(model, candidates, strategy))
			actions += 1
			continue
		var card_index: int = _choose_card(model, strategy)
		if card_index >= 0:
			model.play_card(card_index)
		else:
			model.end_player_turn()
		actions += 1
	var telemetry: Dictionary = model.get_telemetry()
	return {
		&"won": model.battle_over and model.victory,
		&"timeout": not model.battle_over,
		&"turns": model.turn_number,
		&"hp": model.player_hp,
		&"fractures": int(telemetry[&"fractures"]),
		&"choice": model.boss_terminal_choice,
		&"recoveries": model.boss_recovery_count,
	}


func _choose_card(model: CombatModel, strategy: Strategy) -> int:
	var best_index: int = -1
	var best_score: int = -1_000_000
	var incoming_damage: int = _visible_incoming_damage(model)
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		if card.card_type == CardData.CardType.STATUS and card.base_cost >= 99:
			continue
		if model.get_card_cost(card) > model.energy:
			continue
		var score: int = 20 - model.get_card_cost(card) * 3
		var effective_type: int = model.get_card_effective_type(card)
		if model.is_name_eraser_battle() and model.boss_phase == 1 and effective_type >= 0 and not model.boss_type_sequence.has(effective_type):
			score += 45
		if effective_type == CardData.CardType.ATTACK:
			score += 52 if strategy == Strategy.OFFENSE else 32
		elif effective_type == CardData.CardType.DEFENSE:
			var needs_block: bool = incoming_damage > model.player_block or model.player_hp <= 24
			score += (78 if needs_block else 12) if strategy != Strategy.OFFENSE else (42 if model.player_hp <= 18 else 8)
		elif effective_type == CardData.CardType.LAW:
			score += 24
		match card.id:
			&"dissolution_protocol":
				score += 80 if model.instability >= 3 else -15
			&"critical_permission":
				score += 85 if model.instability >= model.instability_threshold - 2 else -20
			&"rift_slash", &"broken_sentence", &"aftershock":
				score += 35 if strategy == Strategy.OFFENSE else 18
			&"blank_space", &"temporary_guard", &"unsigned_support":
				score += 35 if incoming_damage > model.player_block else 0
			&"forced_stability":
				score += 50 if model.instability >= 4 and strategy != Strategy.OFFENSE else -10
			&"restate":
				score += 60 if model.last_card_type == CardData.CardType.ATTACK and model.last_damage_snapshot > 0 else -20
			&"copied_guard":
				score += 45 if model.last_card_type == CardData.CardType.DEFENSE and model.last_block_snapshot > 0 else 0
			&"unseal_order":
				score += 55 if not model.sealed_zone.is_empty() else -60
			&"prewritten_ending":
				score += 20 if model.hand.size() >= 2 else -50
			&"old_wound", &"blank_page":
				score = 5
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _visible_incoming_damage(model: CombatModel) -> int:
	var intent: EnemyIntent = model.get_current_intent()
	if intent == null:
		return 0
	var total: int = 0
	for operation: EnemyOperation in intent.active_operations(model.build_intent_context()):
		if operation.kind == EnemyOperation.Kind.ATTACK:
			total += operation.amount * operation.times
	return total


func _choose_pending_target(model: CombatModel, candidates: Array[int], strategy: Strategy) -> int:
	if candidates.size() == 1:
		return candidates[0]
	if model.pending_selection != null and model.pending_selection.target_kind == TargetSelector.Kind.DRAW_PILE_TOP:
		var worst_target: int = candidates[0]
		var worst_score: int = 1_000_000
		for target_index: int in candidates:
			var card: CardData = model.draw_pile[target_index]
			var score: int = _deck_card_value(card.id, strategy)
			if score < worst_score:
				worst_score = score
				worst_target = target_index
		return worst_target
	return candidates[0]


func _choose_node(run: RunModel, strategy: Strategy) -> StringName:
	if run.available_node_ids.size() == 1:
		return run.available_node_ids[0]
	var priorities: Array[int] = []
	match strategy:
		Strategy.OFFENSE:
			priorities = [MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE, MapNode.NodeType.FORGE, MapNode.NodeType.EVENT, MapNode.NodeType.SHOP]
		Strategy.STEADY:
			priorities = [MapNode.NodeType.BATTLE, MapNode.NodeType.FORGE, MapNode.NodeType.EVENT, MapNode.NodeType.ELITE, MapNode.NodeType.SHOP]
		Strategy.EVENT_ECONOMY:
			priorities = [MapNode.NodeType.EVENT, MapNode.NodeType.SHOP, MapNode.NodeType.FORGE, MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE]
	for wanted: int in priorities:
		for node_id: StringName in run.available_node_ids:
			if run.map_graph.get_node(node_id).node_type == wanted:
				return node_id
	return run.available_node_ids[0]


func _resolve_event(run: RunModel, _node: MapNode, strategy: Strategy) -> void:
	var choice: int = 0
	match run.selected_event_id:
		&"authorless_book":
			choice = 1 if strategy == Strategy.EVENT_ECONOMY else 0
		&"seventh_dock":
			choice = 0 if strategy != Strategy.OFFENSE or run.player_hp < run.player_max_hp - 8 else 1
		&"calibration_station":
			choice = 1 if strategy == Strategy.EVENT_ECONOMY else (0 if run.player_hp < run.player_max_hp - 10 else 2)
		&"speaking_for_you":
			choice = 0 if strategy == Strategy.STEADY else (1 if strategy == Strategy.OFFENSE else 2)
		&"deleted_funeral":
			choice = 0 if strategy == Strategy.STEADY else 1
		&"definition_tax":
			choice = 1 if strategy == Strategy.EVENT_ECONOMY else (0 if strategy == Strategy.STEADY else 2)
	var options: Array[Dictionary] = run.get_event_options()
	if choice < 0 or choice >= options.size() or not bool(options[choice][&"enabled"]):
		choice = _first_enabled_choice(options)
	if not run.apply_event_choice(choice):
		return
	if not run.pending_event_selection.is_empty():
		var candidates: Array[Dictionary] = run.get_pending_event_candidates()
		if not candidates.is_empty():
			run.resolve_event_selection(_choose_removal_instance(run, candidates, strategy))


func _resolve_shop(run: RunModel, strategy: Strategy) -> void:
	if strategy == Strategy.EVENT_ECONOMY:
		var relic: Dictionary = run.pending_shop_stock.get(&"relic", {})
		if not relic.is_empty() and int(relic[&"price"]) <= run.ink_crystals:
			run.buy_shop_relic()
	var cards: Array = run.pending_shop_stock.get(&"cards", [])
	var best_index: int = -1
	var best_value: int = -1_000_000
	for index: int in range(cards.size()):
		var item: Dictionary = cards[index]
		if bool(item.get(&"sold", false)) or int(item[&"price"]) > run.ink_crystals:
			continue
		var value: int = _deck_card_value(item[&"card_id"] as StringName, strategy) * 10 - int(item[&"price"])
		if value > best_value:
			best_value = value
			best_index = index
	if best_index >= 0:
		run.buy_shop_card(best_index)


func _resolve_rest(run: RunModel, strategy: Strategy, depth: int) -> void:
	if run.player_hp < run.player_max_hp and (strategy != Strategy.OFFENSE or run.player_hp * 2 < run.player_max_hp):
		run.resolve_rest_heal()
		return
	if strategy == Strategy.EVENT_ECONOMY and depth == 3:
		run.resolve_rest_salvage()
		return
	var candidates: Array[Dictionary] = run.get_unupgraded_instances()
	if candidates.is_empty():
		run.skip_rest()
	else:
		run.resolve_rest_upgrade(_choose_upgrade_instance(run, candidates, strategy))


func _choose_reward(ids: Array[StringName], strategy: Strategy) -> int:
	var best_index: int = -1
	var best_value: int = 0
	for index: int in range(ids.size()):
		var value: int = _deck_card_value(ids[index], strategy)
		if value > best_value:
			best_value = value
			best_index = index
	return best_index


func _choose_upgrade_instance(run: RunModel, candidates: Array[Dictionary], strategy: Strategy) -> int:
	var best_id: int = int(candidates[0][&"instance_id"])
	var best_value: int = -1_000_000
	for candidate: Dictionary in candidates:
		var value: int = _deck_card_value(candidate[&"card_id"] as StringName, strategy)
		if value > best_value:
			best_value = value
			best_id = int(candidate[&"instance_id"])
	return best_id


func _choose_removal_instance(run: RunModel, candidates: Array[Dictionary], strategy: Strategy) -> int:
	var worst_id: int = int(candidates[0][&"instance_id"])
	var worst_value: int = 1_000_000
	for candidate: Dictionary in candidates:
		var value: int = _deck_card_value(candidate[&"card_id"] as StringName, strategy)
		if value < worst_value:
			worst_value = value
			worst_id = int(candidate[&"instance_id"])
	return worst_id


func _deck_card_value(card_id: StringName, strategy: Strategy) -> int:
	var attack_values: Dictionary = {
		&"dissolution_protocol": 12, &"rift_slash": 11, &"critical_permission": 9,
		&"broken_sentence": 8, &"aftershock": 7, &"restate": 7, &"homophone": 6,
		&"calibration_strike": 4, &"countdown_scar": 7,
	}
	var steady_values: Dictionary = {
		&"blank_space": 12, &"forced_stability": 11, &"critical_permission": 10,
		&"delayed_guard": 9, &"copied_guard": 8, &"unsigned_support": 8,
		&"temporary_guard": 5, &"dissolution_protocol": 8, &"rift_slash": 7,
	}
	var values: Dictionary = attack_values if strategy == Strategy.OFFENSE else steady_values
	return int(values.get(card_id, 3 if card_id != &"old_wound" and card_id != &"redaction" and card_id != &"blank_page" else -10))


func _first_enabled_choice(options: Array[Dictionary]) -> int:
	for index: int in range(options.size()):
		if bool(options[index][&"enabled"]):
			return index
	return -1


func _summarize(results: Array[Dictionary]) -> void:
	print("《断环》M3无辅助章节基线｜%d固定种子×3策略=%d局｜无生命辅助、无失败重跑、无直接置胜" % [SEEDS.size(), results.size()])
	for strategy: Strategy in [Strategy.OFFENSE, Strategy.STEADY, Strategy.EVENT_ECONOMY]:
		var subset: Array[Dictionary] = _for_strategy(results, strategy)
		var wins: int = _count_true(subset, &"completed")
		print("%s｜通关 %d/%d（%.1f%%）｜平均到达层 %.2f｜平均回合 %.2f｜平均剩余HP %.2f｜遗物 %.2f｜墨晶 %.2f｜牌组 %.2f｜裂解 %.2f" % [
			_strategy_name(strategy), wins, subset.size(), 100.0 * float(wins) / float(subset.size()),
			_average(subset, &"reached_depth"), _average(subset, &"turns"), _average(subset, &"hp"),
			_average(subset, &"relics"), _average(subset, &"ink"), _average(subset, &"deck"), _average(subset, &"fractures"),
		])
	var normal_deaths: int = _count_value(results, &"death_kind", &"normal")
	var elite_deaths: int = _count_value(results, &"death_kind", &"elite")
	var boss_deaths: int = _count_value(results, &"death_kind", &"boss")
	var boss_arrivals: int = _count_true(results, &"reached_boss")
	var boss_wins: int = _count_true(results, &"boss_won")
	print("死亡分布｜普通/事件 %d｜精英 %d｜Boss %d｜Boss到达者胜利 %d/%d（%.1f%%）｜超时 %d" % [
		normal_deaths, elite_deaths, boss_deaths, boss_wins, boss_arrivals,
		0.0 if boss_arrivals == 0 else 100.0 * float(boss_wins) / float(boss_arrivals), _count_true(results, &"timeout"),
	])
	print("精英奖励审计｜实际领取 %d 件；返航铃出现局 %d；Boss阶段2死亡计入Boss死亡 %d" % [
		_sum_int(results, &"elite_rewards"), _count_relic_threshold(results, 2), boss_deaths,
	])


func _assert_thresholds(results: Array[Dictionary]) -> void:
	var rates: Array[float] = []
	for strategy: Strategy in [Strategy.OFFENSE, Strategy.STEADY, Strategy.EVENT_ECONOMY]:
		var subset: Array[Dictionary] = _for_strategy(results, strategy)
		rates.append(float(_count_true(subset, &"completed")) / float(subset.size()))
	var one_calibrated: bool = false
	for rate: float in rates:
		one_calibrated = one_calibrated or (rate >= 0.20 and rate <= 0.65)
	_expect(one_calibrated, "至少一个策略整体通关率在20%至65%")
	_expect(not (rates[0] == 0.0 and rates[1] == 0.0 and rates[2] == 0.0), "三个策略不应全部0%通关")
	_expect(not (rates[0] == 1.0 and rates[1] == 1.0 and rates[2] == 1.0), "三个策略不应全部100%通关")
	var failures_total: int = results.size() - _count_true(results, &"completed")
	var elite_deaths: int = _count_value(results, &"death_kind", &"elite")
	_expect(failures_total == 0 or float(elite_deaths) / float(failures_total) <= 0.60, "精英死亡不超过全部失败的60%")
	var boss_arrivals: int = _count_true(results, &"reached_boss")
	var boss_wins: int = _count_true(results, &"boss_won")
	var boss_rate: float = 0.0 if boss_arrivals == 0 else float(boss_wins) / float(boss_arrivals)
	_expect(boss_arrivals > 0 and boss_rate >= 0.15 and boss_rate <= 0.75, "Boss到达者胜率在15%至75%")
	_expect(_count_true(results, &"timeout") == 0, "章节模拟无超时")


func _for_strategy(results: Array[Dictionary], strategy: Strategy) -> Array[Dictionary]:
	var subset: Array[Dictionary] = []
	for result: Dictionary in results:
		if int(result[&"strategy"]) == int(strategy):
			subset.append(result)
	return subset


func _count_true(results: Array[Dictionary], key: StringName) -> int:
	var count: int = 0
	for result: Dictionary in results:
		count += 1 if bool(result[key]) else 0
	return count


func _count_value(results: Array[Dictionary], key: StringName, value: Variant) -> int:
	var count: int = 0
	for result: Dictionary in results:
		count += 1 if result[key] == value else 0
	return count


func _sum_int(results: Array[Dictionary], key: StringName) -> int:
	var total: int = 0
	for result: Dictionary in results:
		total += int(result[key])
	return total


func _average(results: Array[Dictionary], key: StringName) -> float:
	return 0.0 if results.is_empty() else float(_sum_int(results, key)) / float(results.size())


func _count_relic_threshold(results: Array[Dictionary], minimum: int) -> int:
	var count: int = 0
	for result: Dictionary in results:
		count += 1 if int(result[&"relics"]) >= minimum else 0
	return count


func _strategy_name(strategy: Strategy) -> String:
	match strategy:
		Strategy.OFFENSE:
			return "进攻"
		Strategy.STEADY:
			return "稳健"
		Strategy.EVENT_ECONOMY:
			return "事件经济"
	return "未知"


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
