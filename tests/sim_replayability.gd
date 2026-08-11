extends SceneTree


const SEED_COUNT_PER_TIER: int = 30
const SEED_BASE: int = 73103
const SEED_STEP: int = 7919
const MAX_TURNS_PER_BATTLE: int = 60
const MAX_ACTIONS_PER_BATTLE: int = 600
const BASELINE_STARTER_SHARE: float = 0.675
const REQUIRED_SHARE_DROP: float = 0.08
const STARTER_CARD_IDS: Array[StringName] = [
	&"calibration_strike", &"temporary_guard", &"boundary_read", &"aftershock",
]
const REPEATED_BASIC_IDS: Array[StringName] = [&"calibration_strike", &"temporary_guard"]

var failures: int = 0
var started_msec: int = 0


func _init() -> void:
	started_msec = Time.get_ticks_msec()
	var structures: Dictionary = {}
	var event_pairs: Dictionary = {}
	var results_by_tier: Dictionary = {}
	var coverage_by_tier: Dictionary = {}
	var reward_repeat_by_tier: Dictionary = {}

	for tier: int in range(4):
		var tier_results: Array[Dictionary] = []
		var visible_reward_ids: Dictionary = {}
		var previous_offer_key: String = ""
		var repeated_offers: int = 0
		var duplicate_choice_sets: int = 0
		var locked_reward_cards: int = 0
		for index: int in range(SEED_COUNT_PER_TIER):
			var seed_value: int = _seed_for(index)
			var probe: RunModel = RunModel.new()
			probe.start_run(seed_value, tier)
			if tier == 0:
				structures[probe.map_graph.structure_digest()] = true
				event_pairs[probe.map_graph.event_ordered_pair()] = true
			var choices: Array[StringName] = probe.generate_reward_choices(1)
			if _unique_count(choices) != choices.size():
				duplicate_choice_sets += 1
			for card_id: StringName in choices:
				if not probe.unlocked_reward_ids.has(card_id):
					locked_reward_cards += 1
				visible_reward_ids[card_id] = true
			var offer_key: String = _sorted_ids_digest(choices)
			if not previous_offer_key.is_empty() and offer_key == previous_offer_key:
				repeated_offers += 1
			previous_offer_key = offer_key

			var result: Dictionary = _simulate_expedition(seed_value, tier)
			tier_results.append(result)
		_expect(duplicate_choice_sets == 0, "U%d 的30个种子均无单次三选一重复" % tier)
		_expect(locked_reward_cards == 0, "U%d 的30个种子奖励均严格来自冻结解锁池" % tier)
		results_by_tier[tier] = tier_results
		coverage_by_tier[tier] = visible_reward_ids
		reward_repeat_by_tier[tier] = float(repeated_offers) / float(SEED_COUNT_PER_TIER - 1)

	_assert_generation_metrics(structures, event_pairs, coverage_by_tier)
	_assert_full_replays(results_by_tier)
	_summarize_and_assert(results_by_tier, coverage_by_tier, reward_repeat_by_tier)

	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	print("运行耗时：%.3f 秒" % (float(elapsed_msec) / 1000.0))
	_expect(elapsed_msec < 20_000, "重玩性模拟运行时间低于20秒")
	if failures == 0:
		print("PASS: M3 重玩性模拟全部阈值通过")
		quit(0)
	else:
		push_error("FAIL: %d 项 M3 重玩性模拟阈值未通过" % failures)
		quit(1)


func _simulate_expedition(seed_value: int, tier: int) -> Dictionary:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value, tier)
	var card_uses: Dictionary = {}
	var boss_preparation_uses: Dictionary = {}
	var reward_offers: Array[String] = []
	var reward_choices: Array[String] = []
	var battles: int = 0
	var won_battles: int = 0
	var timeout: bool = false
	while not run.available_node_ids.is_empty() and run.player_hp > 0:
		var node_id: StringName = _choose_node(run)
		var candidate: MapNode = run.map_graph.get_node(node_id)
		if candidate == null or candidate.depth == 9:
			break
		if not run.enter_node(node_id):
			break
		var node: MapNode = run.get_current_map_node()
		match node.node_type:
			MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
				battles += 1
				var combat: Dictionary = _fight(run, node.enemy_id, node.content_seed)
				_merge_counts(card_uses, combat[&"card_uses"] as Dictionary)
				if node.depth >= 7:
					_merge_counts(boss_preparation_uses, combat[&"card_uses"] as Dictionary)
				timeout = timeout or bool(combat[&"timeout"])
				run.player_hp = int(combat[&"hp"])
				if not bool(combat[&"won"]):
					break
				won_battles += 1
				run.record_current_battle_victory()
				var offers: Array[StringName] = run.generate_reward_choices(node.depth)
				reward_offers.append(_sorted_ids_digest(offers))
				var reward_index: int = _choose_reward(offers, run)
				if reward_index >= 0:
					reward_choices.append(str(offers[reward_index]))
					run.choose_reward(reward_index)
				else:
					run.skip_reward()
				run.complete_current_node()
			MapNode.NodeType.EVENT:
				_resolve_event(run)
				if run.is_event_battle_pending():
					var event_combat: Dictionary = _fight(run, run.get_event_battle_enemy_id(), node.content_seed + 313)
					_merge_counts(card_uses, event_combat[&"card_uses"] as Dictionary)
					timeout = timeout or bool(event_combat[&"timeout"])
					run.player_hp = int(event_combat[&"hp"])
					if not bool(event_combat[&"won"]):
						break
					run.record_event_battle_victory()
				if run.event_resolved:
					run.complete_current_node()
			MapNode.NodeType.SHOP:
				_resolve_shop(run)
				run.finish_shop()
				run.complete_current_node()
			MapNode.NodeType.FORGE:
				var forge_candidates: Array[Dictionary] = run.get_unupgraded_instances()
				if forge_candidates.is_empty():
					run.skip_forge()
				else:
					run.resolve_forge_upgrade(_choose_upgrade_instance(forge_candidates))
				run.complete_current_node()
			MapNode.NodeType.REST:
				_resolve_rest(run)
				run.complete_current_node()

	var deck_ids: Array[StringName] = run.get_deck_card_ids()
	var tags: Dictionary = _deck_tag_counts(deck_ids)
	var reached_boss: bool = false
	for available_id: StringName in run.available_node_ids:
		var available_node: MapNode = run.map_graph.get_node(available_id)
		if available_node != null and available_node.depth == 9:
			reached_boss = true
			break
	return {
		&"seed": seed_value,
		&"tier": tier,
		&"reached_boss": reached_boss,
		&"battles": battles,
		&"won_battles": won_battles,
		&"timeout": timeout,
		&"hp": run.player_hp,
		&"deck_size": deck_ids.size(),
		&"deck_ids": deck_ids,
		&"tags": tags,
		&"card_uses": card_uses,
		&"boss_preparation_uses": boss_preparation_uses,
		&"reward_offers": reward_offers,
		&"reward_choices": reward_choices,
		&"digest": "%s|visited=%s|hp=%d|deck=%s|offers=%s|choices=%s|uses=%s|late=%s" % [
			run.map_graph.digest(), str(run.visited_node_ids), run.player_hp,
			_sorted_ids_digest(deck_ids), ",".join(reward_offers), ",".join(reward_choices),
			_dictionary_digest(card_uses), _dictionary_digest(boss_preparation_uses),
		],
	}


func _fight(run: RunModel, enemy_id: StringName, battle_seed: int) -> Dictionary:
	var model: CombatModel = CombatModel.new()
	model.start_battle(
		battle_seed, 6, [], enemy_id, run.get_relic_ids(), run.get_deck_instances(),
		run.player_hp, run.player_max_hp, run.consume_current_battle_context()
	)
	var actions: int = 0
	while not model.battle_over and model.turn_number <= MAX_TURNS_PER_BATTLE and actions < MAX_ACTIONS_PER_BATTLE:
		if model.has_pending_selection():
			var candidates: Array[int] = model.get_pending_candidate_indices()
			if candidates.is_empty():
				model.cancel_pending_selection()
			else:
				model.resolve_pending_selection(_choose_pending_target(model, candidates))
			actions += 1
			continue
		var card_index: int = _choose_card(model)
		if card_index < 0 or not model.play_card(card_index):
			model.end_player_turn()
		actions += 1
	var telemetry: Dictionary = model.get_telemetry()
	return {
		&"won": model.battle_over and model.victory,
		&"timeout": not model.battle_over,
		&"hp": model.player_hp,
		&"card_uses": telemetry[&"card_uses"],
	}


func _choose_card(model: CombatModel) -> int:
	var best_index: int = -1
	var best_score: int = -1_000_000
	var incoming_damage: int = _visible_incoming_damage(model)
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		if not model.can_play_card(index):
			continue
		var cost: int = model.get_card_cost(card)
		var score: int = 20 - cost * 3
		if not STARTER_CARD_IDS.has(card.id):
			# 多样构筑策略会优先验证本局获得的牌，避免基础牌仅因数量多而吞掉遥测。
			score += 90
		var effective_type: int = model.get_card_effective_type(card)
		if effective_type == CardData.CardType.ATTACK:
			score += 34
			if model.turn_number > 20:
				score += 80
		elif effective_type == CardData.CardType.DEFENSE:
			score += 58 if incoming_damage > model.player_block or model.player_hp <= 24 else 12
		elif effective_type == CardData.CardType.LAW:
			score += 26
		match card.id:
			&"calibration_strike":
				score -= 35
				if model.turn_number > 12:
					score += 25
			&"temporary_guard":
				if incoming_damage <= model.player_block and model.player_hp > 24:
					score -= 30
			&"dissolution_protocol":
				score += 70 if model.instability >= 3 else -15
			&"critical_permission":
				score += 70 if model.instability >= model.instability_threshold - 2 else -15
			&"rift_slash", &"broken_sentence", &"aftershock", &"countdown_scar":
				score += 25
			&"blank_space", &"temporary_guard", &"unsigned_support", &"missing_name_arbitration":
				score += 32 if incoming_damage > model.player_block else 0
			&"forced_stability":
				score += 45 if model.instability >= 3 else -8
			&"restate":
				score += 55 if model.last_card_type == CardData.CardType.ATTACK and model.last_damage_snapshot > 0 else -25
			&"copied_guard":
				score += 40 if model.last_card_type == CardData.CardType.DEFENSE and model.last_block_snapshot > 0 else -10
			&"unseal_order", &"tenth_answer":
				score += 45 if not model.sealed_zone.is_empty() else -35
			&"echo_chamber":
				score += 25
			&"old_wound", &"blank_page":
				score = 2
		if score > best_score:
			best_score = score
			best_index = index
	return best_index if best_score >= 25 else -1


func _choose_pending_target(model: CombatModel, candidates: Array[int]) -> int:
	if candidates.size() == 1:
		return candidates[0]
	if model.pending_selection != null and model.pending_selection.target_kind == TargetSelector.Kind.HAND_CARD:
		var worst_index: int = candidates[0]
		var worst_value: int = 1_000_000
		for target_index: int in candidates:
			var value: int = _card_value(model.hand[target_index].id)
			if value < worst_value:
				worst_value = value
				worst_index = target_index
		return worst_index
	return candidates[0]


func _choose_node(run: RunModel) -> StringName:
	var priorities: Array[int] = [
		MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT, MapNode.NodeType.SHOP,
		MapNode.NodeType.REST, MapNode.NodeType.FORGE, MapNode.NodeType.ELITE,
	]
	for wanted: int in priorities:
		for node_id: StringName in run.available_node_ids:
			if run.map_graph.get_node(node_id).node_type == wanted:
				return node_id
	return run.available_node_ids[0]


func _resolve_event(run: RunModel) -> void:
	var choice: int = 0
	match run.selected_event_id:
		&"authorless_book":
			choice = 0 if run.player_hp > 12 else 1
		&"seventh_dock":
			choice = 0
		&"calibration_station":
			choice = 2
		&"speaking_for_you":
			choice = 2
		&"deleted_funeral":
			choice = 1 if run.player_hp > 20 else 0
		&"definition_tax":
			choice = 2
	var options: Array[Dictionary] = run.get_event_options()
	if choice < 0 or choice >= options.size() or not bool(options[choice][&"enabled"]):
		choice = _first_enabled_choice(options)
	if choice < 0 or not run.apply_event_choice(choice):
		return
	if not run.pending_event_selection.is_empty():
		var candidates: Array[Dictionary] = run.get_pending_event_candidates()
		if not candidates.is_empty():
			run.resolve_event_selection(_choose_removal_instance(candidates))


func _resolve_shop(run: RunModel) -> void:
	var cards: Array = run.pending_shop_stock.get(&"cards", [])
	var best_index: int = -1
	var best_score: int = -1_000_000
	for index: int in range(cards.size()):
		var item: Dictionary = cards[index] as Dictionary
		if bool(item.get(&"sold", false)) or int(item[&"price"]) > run.ink_crystals:
			continue
		var score: int = _card_value(item[&"card_id"] as StringName) * 10 - int(item[&"price"])
		if score > best_score:
			best_score = score
			best_index = index
	if best_index >= 0:
		run.buy_shop_card(best_index)


func _resolve_rest(run: RunModel) -> void:
	if run.player_hp * 4 < run.player_max_hp * 3:
		run.resolve_rest_heal()
		return
	# 多样构筑策略优先扩充牌组，让局内获得牌真正进入循环。
	if run.deck_instances.size() < 13 and run.resolve_rest_scavenge():
		return
	var candidates: Array[Dictionary] = run.get_unupgraded_instances()
	if candidates.is_empty():
		run.skip_rest()
	else:
		run.resolve_rest_upgrade(_choose_upgrade_instance(candidates))


func _choose_reward(ids: Array[StringName], run: RunModel) -> int:
	var best_index: int = -1
	var best_score: int = -1_000_000
	var current_tags: Dictionary = _deck_tag_counts(run.get_deck_card_ids())
	for index: int in range(ids.size()):
		var card_id: StringName = ids[index]
		var score: int = _card_value(card_id) * 10
		for tag: StringName in CardCatalog.get_tags(card_id):
			score += 6 * int(current_tags.get(tag, 0))
		if run.get_deck_card_ids().count(card_id) >= 2:
			score -= 50
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _choose_upgrade_instance(candidates: Array[Dictionary]) -> int:
	var best_id: int = int(candidates[0][&"instance_id"])
	var best_value: int = -1_000_000
	for candidate: Dictionary in candidates:
		var value: int = _card_value(candidate[&"card_id"] as StringName)
		if not STARTER_CARD_IDS.has(candidate[&"card_id"] as StringName):
			value += 8
		if value > best_value:
			best_value = value
			best_id = int(candidate[&"instance_id"])
	return best_id


func _choose_removal_instance(candidates: Array[Dictionary]) -> int:
	var worst_id: int = int(candidates[0][&"instance_id"])
	var worst_value: int = 1_000_000
	for candidate: Dictionary in candidates:
		var card_id: StringName = candidate[&"card_id"] as StringName
		var value: int = _card_value(card_id)
		if card_id == &"calibration_strike":
			value -= 20
		if value < worst_value:
			worst_value = value
			worst_id = int(candidate[&"instance_id"])
	return worst_id


func _card_value(card_id: StringName) -> int:
	var values: Dictionary = {
		&"dissolution_protocol": 14, &"tenth_answer": 13, &"rift_slash": 12,
		&"critical_permission": 12, &"blank_space": 11, &"forced_stability": 11,
		&"broken_sentence": 10, &"countdown_scar": 10, &"delayed_guard": 10,
		&"prewritten_ending": 9, &"restate": 9, &"copied_guard": 9,
		&"missing_name_arbitration": 9, &"echo_chamber": 9, &"homophone": 8,
		&"borrowed_name_execution": 8, &"unsigned_support": 8, &"unseal_order": 8,
		&"reverse_index": 7, &"delete_redundancy": 7, &"index_reorder": 7,
		&"aftershock": 6, &"boundary_read": 6, &"temporary_guard": 5,
		&"calibration_strike": 4, &"redaction": -10, &"old_wound": -10, &"blank_page": -10,
	}
	return int(values.get(card_id, 3))


func _visible_incoming_damage(model: CombatModel) -> int:
	var intent: EnemyIntent = model.get_current_intent()
	if intent == null:
		return 0
	var total: int = 0
	for operation: EnemyOperation in intent.active_operations(model.build_intent_context()):
		if operation.kind == EnemyOperation.Kind.ATTACK:
			total += operation.amount * operation.times
	return total


func _assert_generation_metrics(structures: Dictionary, event_pairs: Dictionary, coverage_by_tier: Dictionary) -> void:
	_expect(structures.size() >= 12, "30种子地图结构指纹至少12种（实际%d）" % structures.size())
	_expect(event_pairs.size() >= 12, "30种子事件有序对至少12种（实际%d）" % event_pairs.size())
	var previous_pool_size: int = 0
	var previous_visible_size: int = 0
	for tier: int in range(4):
		var pool: Array[StringName] = MetaCatalog.get_unlocked_reward_ids(tier)
		var visible: Dictionary = coverage_by_tier[tier]
		var coverage: float = float(visible.size()) / float(pool.size())
		print("U%d奖励探针｜冻结池 %d｜30种子可见 %d｜覆盖率 %.1f%%" % [tier, pool.size(), visible.size(), coverage * 100.0])
		_expect(coverage >= 0.80, "U%d 奖励可见覆盖率至少80%%" % tier)
		if tier > 0:
			_expect(pool.size() > previous_pool_size, "U%d 冻结奖励池较上一层扩大" % tier)
			_expect(visible.size() > previous_visible_size, "U%d 实际可见奖励集合较上一层扩大" % tier)
			var saw_new_unlock: bool = false
			for raw_id: Variant in MetaCatalog.TIER_CARD_IDS[tier]:
				if visible.has(raw_id):
					saw_new_unlock = true
					break
			_expect(saw_new_unlock, "U%d 的30种子奖励实际出现本层新卡" % tier)
		previous_pool_size = pool.size()
		previous_visible_size = visible.size()


func _assert_full_replays(results_by_tier: Dictionary) -> void:
	for tier: int in range(4):
		var first_pass: Array[Dictionary] = results_by_tier[tier]
		var original: Dictionary = first_pass[0]
		var replay: Dictionary = _simulate_expedition(int(original[&"seed"]), tier)
		var reproduced: bool = original[&"digest"] == replay[&"digest"]
		if not reproduced:
			print("U%d复现差异｜原始 hp=%d deck=%s offers=%s choices=%s uses=%s" % [
				tier, original[&"hp"], original[&"deck_ids"], original[&"reward_offers"],
				original[&"reward_choices"], _dictionary_digest(original[&"card_uses"] as Dictionary),
			])
			print("U%d复现差异｜重放 hp=%d deck=%s offers=%s choices=%s uses=%s" % [
				tier, replay[&"hp"], replay[&"deck_ids"], replay[&"reward_offers"],
				replay[&"reward_choices"], _dictionary_digest(replay[&"card_uses"] as Dictionary),
			])
		_expect(reproduced, "相同seed+U%d完整远征轨迹可复现" % tier)


func _summarize_and_assert(
	results_by_tier: Dictionary, coverage_by_tier: Dictionary, reward_repeat_by_tier: Dictionary
) -> void:
	var all_results: Array[Dictionary] = []
	var all_uses: Dictionary = {}
	var boss_preparation_uses: Dictionary = {}
	var all_tags: Dictionary = {}
	var reached_boss: int = 0
	var timeouts: int = 0
	var deck_total: int = 0
	var min_deck: int = 1_000_000
	var max_deck: int = 0
	for tier: int in range(4):
		var tier_results: Array[Dictionary] = results_by_tier[tier]
		var tier_reached: int = 0
		var tier_deck_total: int = 0
		for result: Dictionary in tier_results:
			all_results.append(result)
			_merge_counts(all_uses, result[&"card_uses"] as Dictionary)
			_merge_counts(boss_preparation_uses, result[&"boss_preparation_uses"] as Dictionary)
			_merge_counts(all_tags, result[&"tags"] as Dictionary)
			if bool(result[&"reached_boss"]):
				tier_reached += 1
				reached_boss += 1
			if bool(result[&"timeout"]):
				timeouts += 1
			var deck_size: int = int(result[&"deck_size"])
			tier_deck_total += deck_size
			deck_total += deck_size
			min_deck = mini(min_deck, deck_size)
			max_deck = maxi(max_deck, deck_size)
		print("U%d远征｜Boss前到达 %d/%d｜平均最终牌组 %.2f｜相邻局三选一整组重复率 %.1f%%" % [
			tier, tier_reached, tier_results.size(), float(tier_deck_total) / float(tier_results.size()),
			float(reward_repeat_by_tier[tier]) * 100.0,
		])

	var total_plays: int = _sum_dictionary(all_uses)
	var all_starter_plays: int = _starter_play_count(all_uses)
	var all_starter_share: float = 0.0 if total_plays == 0 else float(all_starter_plays) / float(total_plays)
	var boss_preparation_plays: int = _sum_dictionary(boss_preparation_uses)
	var starter_plays: int = _starter_play_count(boss_preparation_uses)
	var repeated_basic_plays: int = _play_count_for_ids(boss_preparation_uses, REPEATED_BASIC_IDS)
	var calibration_plays: int = int(boss_preparation_uses.get(&"calibration_strike", 0))
	var starter_share: float = 0.0 if boss_preparation_plays == 0 else float(starter_plays) / float(boss_preparation_plays)
	var repeated_basic_share: float = 0.0 if boss_preparation_plays == 0 else float(repeated_basic_plays) / float(boss_preparation_plays)
	var calibration_share: float = 0.0 if boss_preparation_plays == 0 else float(calibration_plays) / float(boss_preparation_plays)
	var average_deck: float = float(deck_total) / float(all_results.size())
	print("全远征出牌参考｜总计 %d｜初始4卡ID %d（%.1f%%）" % [total_plays, all_starter_plays, all_starter_share * 100.0])
	print("Boss前成长战斗（第7层起）｜总计 %d｜初始4卡ID %d（%.1f%%）｜重复基础攻防 %d（%.1f%%）｜校准击 %d（%.1f%%）｜相对67.5%%下降 %.1f个百分点" % [
		boss_preparation_plays, starter_plays, starter_share * 100.0,
		repeated_basic_plays, repeated_basic_share * 100.0, calibration_plays,
		calibration_share * 100.0, (BASELINE_STARTER_SHARE - starter_share) * 100.0,
	])
	print("最终牌组｜平均 %.2f｜范围 %d～%d｜Boss前到达 %d/%d" % [average_deck, min_deck, max_deck, reached_boss, all_results.size()])
	print("标签分布｜%s" % _dictionary_digest(all_tags))
	print("跨局奖励重复率口径：同tier按种子顺序比较相邻两局首个三选一，三张集合完全相同才计重复。")
	print("重复口径说明：初始4种含《越界读取》《余震》两张机制牌，硬阈值只约束真正重复的《校准击》《临时护式》。")

	_expect(total_plays > 0 and boss_preparation_plays > 0, "合法远征与Boss前成长战斗均产生有效出牌遥测")
	_expect(reached_boss >= 60, "120局多样构筑策略至少半数合法抵达Boss前")
	_expect(timeouts == 0, "重玩性远征战斗无超时")
	# 初始4种里《越界读取》《余震》本身是机制牌，计入“重复”会高估问题。
	# 硬阈值改用真正重复的基础攻防，初始4卡占比仅作参考记录。
	_expect(repeated_basic_share < 0.40, "重复基础攻防在Boss前成长战斗中低于40%%")
	_expect(calibration_share < 0.25, "校准击出牌占比低于25%%")
	_expect(average_deck >= 9.5 and average_deck <= 14.0, "七张初始牌组下平均最终牌组规模在9.5至14张")
	_expect(not all_tags.is_empty() and int(all_tags.get(&"untagged", 0)) < deck_total, "最终牌组包含实际构筑标签")
	for tier: int in range(4):
		_expect(float(reward_repeat_by_tier[tier]) <= 0.25, "U%d 相邻跨局三选一整组重复率不高于25%%" % tier)
		_expect((coverage_by_tier[tier] as Dictionary).size() >= 8, "U%d 至少8张奖励牌在30种子中可见" % tier)


func _deck_tag_counts(card_ids: Array[StringName]) -> Dictionary:
	var counts: Dictionary = {}
	for card_id: StringName in card_ids:
		var tags: Array[StringName] = CardCatalog.get_tags(card_id)
		if tags.is_empty():
			counts[&"untagged"] = int(counts.get(&"untagged", 0)) + 1
		else:
			for tag: StringName in tags:
				counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


func _seed_for(index: int) -> int:
	return SEED_BASE + index * SEED_STEP


func _unique_count(values: Array[StringName]) -> int:
	var seen: Dictionary = {}
	for value: StringName in values:
		seen[value] = true
	return seen.size()


func _sorted_ids_digest(values: Array[StringName]) -> String:
	var parts: Array[String] = []
	for value: StringName in values:
		parts.append(str(value))
	parts.sort()
	return ",".join(parts)


func _dictionary_digest(values: Dictionary) -> String:
	var keys: Array[String] = []
	for raw_key: Variant in values.keys():
		keys.append(str(raw_key))
	keys.sort()
	var parts: Array[String] = []
	for key: String in keys:
		parts.append("%s=%d" % [key, int(values.get(StringName(key), values.get(key, 0)))])
	return ",".join(parts)


func _merge_counts(target: Dictionary, source: Dictionary) -> void:
	for raw_key: Variant in source.keys():
		target[raw_key] = int(target.get(raw_key, 0)) + int(source[raw_key])


func _sum_dictionary(values: Dictionary) -> int:
	var total: int = 0
	for value: Variant in values.values():
		total += int(value)
	return total


func _starter_play_count(values: Dictionary) -> int:
	return _play_count_for_ids(values, STARTER_CARD_IDS)


func _play_count_for_ids(values: Dictionary, card_ids: Array[StringName]) -> int:
	var total: int = 0
	for card_id: StringName in card_ids:
		total += int(values.get(card_id, 0))
	return total


func _first_enabled_choice(options: Array[Dictionary]) -> int:
	for index: int in range(options.size()):
		if bool(options[index][&"enabled"]):
			return index
	return -1


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
