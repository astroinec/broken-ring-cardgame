extends SceneTree

const SEEDS: Array[int] = [
	73103, 80011, 91027, 100003, 110009, 120011,
	130027, 140053, 150061, 160073, 170081, 180097,
]
const MAX_TURNS: int = 45
const SECONDS_PER_COMBAT_TURN: float = 45.0
const SECONDS_PER_NODE_OPERATION: float = 30.0

enum RoutePolicy {
	EVENT_ARCHIVE,
	BATTLE_PRESSURE,
}

var failures: int = 0


func _init() -> void:
	var archive_results: Array[Dictionary] = []
	var pressure_results: Array[Dictionary] = []
	for seed_index: int in range(SEEDS.size()):
		var seed_value: int = SEEDS[seed_index]
		var archive: Dictionary = _simulate(seed_value, seed_index, RoutePolicy.EVENT_ARCHIVE)
		var archive_replay: Dictionary = _simulate(seed_value, seed_index, RoutePolicy.EVENT_ARCHIVE)
		var pressure: Dictionary = _simulate(seed_value, seed_index, RoutePolicy.BATTLE_PRESSURE)
		var pressure_replay: Dictionary = _simulate(seed_value, seed_index, RoutePolicy.BATTLE_PRESSURE)
		_expect(archive[&"digest"] == archive_replay[&"digest"], "chapter archive route seed %d reproduces" % seed_value)
		_expect(pressure[&"digest"] == pressure_replay[&"digest"], "chapter pressure route seed %d reproduces" % seed_value)
		archive_results.append(archive)
		pressure_results.append(pressure)
	_summarize_and_assert(archive_results, pressure_results)
	if failures == 0:
		print("PASS: all M2 chapter simulation thresholds")
		quit(0)
	else:
		push_error("FAIL: %d M2 chapter simulation thresholds failed" % failures)
		quit(1)


func _simulate(seed_value: int, seed_index: int, policy: RoutePolicy) -> Dictionary:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value)
	var total_turns: int = 0
	var battle_count: int = 0
	var assisted_battles: int = 0
	var boss_assisted: bool = false
	var seen_events: Array[StringName] = []
	var event_choice_round: int = 0
	var boss_choice: StringName = &""
	var boss_recoveries: int = 0
	while not run.available_node_ids.is_empty() and not run.run_completed:
		var node_id: StringName = _choose_node(run, policy)
		if not run.enter_node(node_id):
			break
		var node: MapNode = run.get_current_map_node()
		match node.node_type:
			MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
				var result: Dictionary = _fight(run, node.enemy_id, node.content_seed, false)
				total_turns += int(result[&"turns"])
				battle_count += 1
				assisted_battles += 1 if bool(result[&"assisted"]) else 0
				if not bool(result[&"won"]):
					break
				run.player_hp = mini(run.player_max_hp, int(result[&"player_hp"]))
				run.record_current_battle_victory()
				run.generate_reward_choices(node.depth)
				run.choose_reward(_best_reward_index(run.pending_reward_ids, policy))
				run.complete_current_node()
			MapNode.NodeType.EVENT:
				if not seen_events.has(run.selected_event_id):
					seen_events.append(run.selected_event_id)
				var choice_index: int = _event_choice(run, seed_index, event_choice_round, policy)
				event_choice_round += 1
				if not run.apply_event_choice(choice_index):
					choice_index = _first_enabled_event_choice(run)
					run.apply_event_choice(choice_index)
				if not run.pending_event_selection.is_empty():
					var candidates: Array[Dictionary] = run.get_pending_event_candidates()
					if not candidates.is_empty():
						run.resolve_event_selection(int(candidates[0][&"instance_id"]))
				if run.is_event_battle_pending():
					var event_result: Dictionary = _fight(run, run.get_event_battle_enemy_id(), node.content_seed + 313, false)
					total_turns += int(event_result[&"turns"])
					battle_count += 1
					assisted_battles += 1 if bool(event_result[&"assisted"]) else 0
					if bool(event_result[&"won"]):
						run.player_hp = mini(run.player_max_hp, int(event_result[&"player_hp"]))
						run.record_event_battle_victory()
				if run.event_resolved:
					run.complete_current_node()
			MapNode.NodeType.SHOP:
				_buy_affordable_card(run)
				run.finish_shop()
				run.complete_current_node()
			MapNode.NodeType.FORGE:
				var candidates: Array[Dictionary] = run.get_unupgraded_instances()
				if candidates.is_empty():
					run.skip_forge()
				else:
					run.resolve_forge_upgrade(int(candidates[0][&"instance_id"]))
				run.complete_current_node()
			MapNode.NodeType.REST:
				if policy == RoutePolicy.EVENT_ARCHIVE and node.depth == 3:
					run.resolve_rest_salvage()
				elif run.player_hp < run.player_max_hp:
					run.resolve_rest_heal()
				else:
					var candidates: Array[Dictionary] = run.get_unupgraded_instances()
					if candidates.is_empty():
						run.skip_rest()
					else:
						run.resolve_rest_upgrade(int(candidates[0][&"instance_id"]))
				run.complete_current_node()
			MapNode.NodeType.BOSS:
				var boss_result: Dictionary = _fight(run, node.enemy_id, node.content_seed, true)
				total_turns += int(boss_result[&"turns"])
				battle_count += 1
				boss_assisted = bool(boss_result[&"assisted"])
				assisted_battles += 1 if boss_assisted else 0
				if not bool(boss_result[&"won"]):
					break
				boss_choice = boss_result[&"choice"] as StringName
				boss_recoveries = int(boss_result[&"recoveries"])
				run.record_boss_outcome(boss_choice, boss_recoveries)
				run.complete_current_node()
	var completed_nodes: int = _completed_count(run)
	var estimated_seconds: float = float(total_turns) * SECONDS_PER_COMBAT_TURN + float(completed_nodes) * SECONDS_PER_NODE_OPERATION
	var evidence_ids: Array[StringName] = run.get_evidence_ids()
	var evidence_recalled: bool = run.boss_ending_text.contains("九个版本") or run.boss_ending_text.contains("制造接口")
	return {
		&"seed": seed_value,
		&"policy": policy,
		&"completed": run.run_completed and completed_nodes == 9,
		&"completed_nodes": completed_nodes,
		&"turns": total_turns,
		&"battles": battle_count,
		&"assisted_battles": assisted_battles,
		&"boss_assisted": boss_assisted,
		&"boss_choice": boss_choice,
		&"boss_recoveries": boss_recoveries,
		&"events": seen_events,
		&"evidence_ids": evidence_ids,
		&"evidence_recalled": evidence_recalled,
		&"estimated_minutes": estimated_seconds / 60.0,
		&"digest": "%d|%d|%s|%d|%d|%s|%s|%.2f" % [
			completed_nodes, total_turns, boss_choice, boss_recoveries, assisted_battles,
			str(seen_events), str(evidence_ids), estimated_seconds,
		],
	}


func _fight(run: RunModel, enemy_id: StringName, battle_seed: int, boss: bool) -> Dictionary:
	var first: Dictionary = _run_combat(run, enemy_id, battle_seed, boss, false)
	if bool(first[&"won"]):
		return first
	return _run_combat(run, enemy_id, battle_seed, boss, true)


func _run_combat(run: RunModel, enemy_id: StringName, battle_seed: int, boss: bool, assisted: bool) -> Dictionary:
	var model: CombatModel = CombatModel.new()
	var simulated_max_hp: int = 220 if assisted or boss else run.player_max_hp
	var simulated_hp: int = simulated_max_hp if assisted or boss else run.player_hp
	model.start_battle(
		battle_seed, 6, [], enemy_id, run.get_relic_ids(), run.get_deck_instances(),
		simulated_hp, simulated_max_hp, run.consume_current_battle_context()
	)
	while not model.battle_over and model.turn_number <= MAX_TURNS:
		if model.boss_terminal_choice_pending:
			var ending: StringName = &"read_original" if model.can_choose_boss_original_text() else &"deliver_seal"
			model.choose_boss_terminal(ending)
			break
		if model.has_pending_selection():
			var targets: Array[int] = model.get_pending_candidate_indices()
			if targets.is_empty():
				model.cancel_pending_selection()
			else:
				model.resolve_pending_selection(targets[0])
			continue
		var card_index: int = _choose_card(model)
		if card_index >= 0:
			model.play_card(card_index)
		else:
			model.end_player_turn()
	return {
		&"won": model.battle_over and model.victory,
		&"turns": model.turn_number,
		&"player_hp": model.player_hp,
		&"choice": model.boss_terminal_choice,
		&"recoveries": model.boss_recovery_count,
		&"assisted": assisted or boss,
	}


func _choose_card(model: CombatModel) -> int:
	var best_index: int = -1
	var best_score: int = -1_000_000
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		if card.card_type == CardData.CardType.STATUS and card.base_cost >= 99:
			continue
		if model.get_card_cost(card) > model.energy:
			continue
		var score: int = 10 - model.get_card_cost(card)
		var effective_type: int = model.get_card_effective_type(card)
		if model.is_name_eraser_battle() and model.boss_phase == 1 and effective_type >= 0 and not model.boss_type_sequence.has(effective_type):
			score += 55
		if effective_type == CardData.CardType.ATTACK:
			score += 42
		elif effective_type == CardData.CardType.DEFENSE:
			score += 20 if model.player_hp > 25 else 60
		elif effective_type == CardData.CardType.LAW:
			score += 28
		match card.id:
			&"dissolution_protocol":
				score += 75 if model.instability >= 3 else 5
			&"critical_permission":
				score += 65 if model.instability >= model.instability_threshold - 2 else 0
			&"rift_slash", &"broken_sentence", &"aftershock", &"countdown_scar":
				score += 35
			&"restate":
				score += 50 if model.last_card_type == CardData.CardType.ATTACK else -10
			&"copied_guard":
				score += 35 if model.last_card_type == CardData.CardType.DEFENSE else 0
			&"unseal_order":
				score += 45 if not model.sealed_zone.is_empty() else -30
			&"forced_stability":
				score += 25 if model.instability >= 4 else 0
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _choose_node(run: RunModel, policy: RoutePolicy) -> StringName:
	if run.available_node_ids.size() == 1:
		return run.available_node_ids[0]
	var preferred: Array[int] = []
	if policy == RoutePolicy.EVENT_ARCHIVE:
		preferred = [MapNode.NodeType.EVENT, MapNode.NodeType.SHOP, MapNode.NodeType.FORGE]
	else:
		preferred = [MapNode.NodeType.BATTLE, MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE]
	for wanted_type: int in preferred:
		for node_id: StringName in run.available_node_ids:
			if run.map_graph.get_node(node_id).node_type == wanted_type:
				return node_id
	return run.available_node_ids[0]


func _event_choice(run: RunModel, seed_index: int, round_index: int, policy: RoutePolicy) -> int:
	match run.selected_event_id:
		&"seventh_dock":
			return 0
		&"calibration_station":
			return 1
		&"definition_tax":
			return 3 if (seed_index + round_index + int(policy)) % 2 == 0 else (seed_index + round_index) % 3
		&"speaking_for_you":
			return (seed_index + round_index) % 3
		&"deleted_funeral":
			return (seed_index + round_index) % 2
		&"authorless_book":
			return (seed_index + round_index) % 2
	return 0


func _first_enabled_event_choice(run: RunModel) -> int:
	var options: Array[Dictionary] = run.get_event_options()
	for index: int in range(options.size()):
		if bool(options[index][&"enabled"]):
			return index
	return 0


func _best_reward_index(reward_ids: Array[StringName], policy: RoutePolicy) -> int:
	var wanted: Array[StringName] = []
	if policy == RoutePolicy.BATTLE_PRESSURE:
		wanted = [&"rift_slash", &"broken_sentence", &"dissolution_protocol", &"restate"]
	else:
		wanted = [&"delayed_guard", &"countdown_scar", &"restate", &"blank_space"]
	for wanted_id: StringName in wanted:
		var index: int = reward_ids.find(wanted_id)
		if index >= 0:
			return index
	return 0


func _buy_affordable_card(run: RunModel) -> void:
	var cards: Array = run.pending_shop_stock.get(&"cards", [])
	var chosen_index: int = -1
	var chosen_price: int = 1_000_000
	for index: int in range(cards.size()):
		var item: Dictionary = cards[index] as Dictionary
		var price: int = int(item[&"price"])
		if price <= run.ink_crystals and price < chosen_price:
			chosen_index = index
			chosen_price = price
	if chosen_index >= 0:
		run.buy_shop_card(chosen_index)


func _completed_count(run: RunModel) -> int:
	var count: int = 0
	for raw_node: Variant in run.map_graph.nodes_by_id.values():
		if (raw_node as MapNode).completed:
			count += 1
	return count


func _summarize_and_assert(archive_results: Array[Dictionary], pressure_results: Array[Dictionary]) -> void:
	var all_results: Array[Dictionary] = archive_results + pressure_results
	var covered_events: Dictionary = {}
	var ending_counts: Dictionary = {&"deliver_seal": 0, &"read_original": 0}
	var total_evidence: int = 0
	var evidence_recalled: int = 0
	for result: Dictionary in all_results:
		for event_id: StringName in result[&"events"]:
			covered_events[event_id] = true
		var ending: StringName = result[&"boss_choice"] as StringName
		ending_counts[ending] = int(ending_counts.get(ending, 0)) + 1
		total_evidence += (result[&"evidence_ids"] as Array).size()
		evidence_recalled += 1 if bool(result[&"evidence_recalled"]) else 0
		_expect(bool(result[&"completed"]), "seed %d policy %d reaches formal Boss settlement" % [result[&"seed"], result[&"policy"]])
		_expect(int(result[&"boss_recoveries"]) >= 0, "seed %d policy %d records Boss recovery count" % [result[&"seed"], result[&"policy"]])
	var archive_minutes: float = _average_minutes(archive_results)
	var pressure_minutes: float = _average_minutes(pressure_results)
	print("《断环》M2章节模拟｜%d种子×2路线=%d局｜事件覆盖 %d/6" % [SEEDS.size(), all_results.size(), covered_events.size()])
	print("Boss结局：交付 %d｜读取原文 %d｜证据记录 %d｜旧证据结算回收 %d" % [ending_counts[&"deliver_seal"], ending_counts[&"read_original"], total_evidence, evidence_recalled])
	print("估算时长：事件档案路线 %.2f 分钟｜战斗压力路线 %.2f 分钟（每战斗回合 %.0f 秒 + 每完成节点 %.0f 秒）" % [archive_minutes, pressure_minutes, SECONDS_PER_COMBAT_TURN, SECONDS_PER_NODE_OPERATION])
	print("可控辅助：Boss统一使用220生命上限生存辅助；非Boss失败后才重跑辅助，共 %d 场。该模拟验证流程与节奏，不作为胜率结论。" % _sum_int(all_results, &"assisted_battles"))
	for event_id: StringName in RunModel.EVENT_IDS:
		_expect(covered_events.has(event_id), "chapter seeds cover event %s" % event_id)
	_expect(int(ending_counts[&"deliver_seal"]) + int(ending_counts[&"read_original"]) == all_results.size(), "every chapter run records one Boss ending")
	_expect(total_evidence > 0, "chapter runs carry sourced evidence into settlement")
	_expect(evidence_recalled > 0, "at least one chapter settlement explains an earlier evidence record")
	var archive_in_target: bool = archive_minutes >= 20.0 and archive_minutes <= 30.0
	var pressure_in_target: bool = pressure_minutes >= 20.0 and pressure_minutes <= 30.0
	_expect(archive_in_target or pressure_in_target, "at least one strategy interval estimates to the 20-30 minute target")


func _average_minutes(results: Array[Dictionary]) -> float:
	var total: float = 0.0
	for result: Dictionary in results:
		total += float(result[&"estimated_minutes"])
	return total / float(results.size())


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
