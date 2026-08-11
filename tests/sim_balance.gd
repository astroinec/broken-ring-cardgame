extends SceneTree

## v0.6 数值模拟与平衡阈值检查。
##
## 所有策略只读取 CombatModel 规则状态，不使用额外随机数。相同种子、场景、
## 牌组增量、遗物与策略必须产生完全相同的逐局指纹。

const CombatModelScript: Script = preload("res://scripts/core/combat_model.gd")

const SEEDS: Array[int] = [
	73103, 80011, 91027, 100003, 110009, 120011,
	130027, 140053, 150061, 160073, 170081, 180097,
]
const MAX_TURNS: int = 40
const PRESSURE_ENEMY_ID: StringName = &"pressure_archivist"

const FOCUSED_BONUS_IDS: Array[StringName] = [
	&"boundary_read", &"boundary_read",
	&"rift_slash", &"rift_slash", &"rift_slash",
	&"critical_permission", &"dissolution_protocol",
	&"delayed_guard", &"countdown_scar", &"unseal_order",
	&"restate", &"homophone",
]

const OVERLOAD_BONUS_IDS: Array[StringName] = [
	&"boundary_read", &"boundary_read", &"boundary_read",
	&"rift_slash", &"rift_slash", &"rift_slash", &"rift_slash",
	&"critical_permission", &"dissolution_protocol",
]

enum Strategy {
	BALANCED,
	OVERLOAD_AGGRESSIVE,
	SEAL_PRIORITY,
	ECHO_PRIORITY,
}

var failures: int = 0
var report_lines: Array[String] = []


func _init() -> void:
	report_lines.append("《断环》v0.6 确定性数值模拟")
	report_lines.append("固定种子：%s｜每场景 %d 局｜策略：BALANCED / OVERLOAD_AGGRESSIVE / SEAL_PRIORITY / ECHO_PRIORITY" % [
		str(SEEDS), SEEDS.size(),
	])
	report_lines.append("")

	_simulate_path_nodes()
	_simulate_formal_enemies()
	var pressure_results: Dictionary = _simulate_pressure_strategies()
	_simulate_relic_comparison()
	_verify_m0_strategy_differences(pressure_results)
	_verify_determinism()

	for line: String in report_lines:
		print(line)
	if failures == 0:
		print("PASS: 全部 M0 平衡阈值检查通过")
		quit(0)
	else:
		push_error("FAIL: %d 项 M0 平衡检查未通过" % failures)
		quit(1)


# ------------------------------------------------------------------ 主线基线

func _simulate_path_nodes() -> void:
	report_lines.append("一、主线六个路径节点（BALANCED，裂纹稳定器）")
	report_lines.append(_table_header())
	var relics: Array[StringName] = [&"crack_stabilizer"]
	var no_bonus: Array[StringName] = []
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		var result: Dictionary = _run_scenario(stage, &"", relics, Strategy.BALANCED, no_bonus)
		report_lines.append(_table_row("节点%d %s" % [stage, result[&"enemy"]], result))
		_expect(
			float(result[&"win_rate"]) >= 1.0,
			"主线节点 %d 在 BALANCED 下保持必胜（实际 %.0f%%）" % [stage, float(result[&"win_rate"]) * 100.0]
		)
		var turns: float = float(result[&"avg_turns"])
		var lower_bound: float = 1.0 if stage == 1 else 2.0
		_expect(
			turns >= lower_bound and turns <= 9.0,
			"主线节点 %d 平均回合数保持新手友好（实际 %.1f）" % [stage, turns]
		)
		if stage <= 3:
			_expect(
				float(result[&"avg_hp_left"]) >= 40.0,
				"主线节点 %d 平均剩余生命不低于 40（实际 %.1f）" % [stage, float(result[&"avg_hp_left"])]
			)
	report_lines.append("")


# -------------------------------------------------------------- 正式敌人

func _simulate_formal_enemies() -> void:
	report_lines.append("二、机制测试场正式敌人（BALANCED，完整机制牌组）")
	report_lines.append(_table_header())
	var relics: Array[StringName] = [&"crack_stabilizer"]
	var no_bonus: Array[StringName] = []
	var expectations: Dictionary = {
		&"hollow_name_guard": {&"min_turns": 3.0, &"max_turns": 14.0},
		&"reverse_reader": {&"min_turns": 4.0, &"max_turns": 12.0},
		&"binding_instrument": {&"min_turns": 5.0, &"max_turns": 22.0},
	}
	var formal_results: Dictionary = {}
	for enemy_id: StringName in EnemyCatalog.TEST_ARENA_ENEMY_IDS:
		if not expectations.has(enemy_id):
			continue
		var result: Dictionary = _run_scenario(
			CombatModelScript.TUTORIAL_STAGE_MAX, enemy_id, relics, Strategy.BALANCED, no_bonus
		)
		formal_results[enemy_id] = result
		report_lines.append(_table_row(str(result[&"enemy"]), result))
		var bounds: Dictionary = expectations[enemy_id]
		var turns: float = float(result[&"avg_turns"])
		_expect(
			turns >= float(bounds[&"min_turns"]),
			"%s 平均战斗至少 %.0f 回合（实际 %.1f）" % [result[&"enemy"], float(bounds[&"min_turns"]), turns]
		)
		_expect(
			turns <= float(bounds[&"max_turns"]),
			"%s 不会陷入僵局（实际 %.1f 回合）" % [result[&"enemy"], turns]
		)
		_expect(
			float(result[&"win_rate"]) > 0.0,
			"%s 至少存在可胜路径（实际胜率 %.0f%%）" % [result[&"enemy"], float(result[&"win_rate"]) * 100.0]
		)
		_expect(int(result[&"timeouts"]) == 0, "%s 无超时（实际 %d）" % [result[&"enemy"], int(result[&"timeouts"])])
		if enemy_id == &"reverse_reader":
			_expect(
				int(result[&"turn_min"]) >= 4,
				"倒读者每局至少让倒读机制完整响应两轮（最短 %d 回合）" % int(result[&"turn_min"])
			)
	var guard: Dictionary = formal_results[&"hollow_name_guard"]
	var elite: Dictionary = formal_results[&"binding_instrument"]
	_expect(
		float(elite[&"avg_turns"]) > float(guard[&"avg_turns"]),
		"装订刑具比空名卫士更持久（%.1f > %.1f）" % [float(elite[&"avg_turns"]), float(guard[&"avg_turns"])]
	)
	_expect(
		float(elite[&"avg_hp_left"]) < float(guard[&"avg_hp_left"]),
		"装订刑具生命压力高于空名卫士（%.1f < %.1f）" % [float(elite[&"avg_hp_left"]), float(guard[&"avg_hp_left"])]
	)
	report_lines.append("")


# -------------------------------------------------------------- 高压策略对照

func _simulate_pressure_strategies() -> Dictionary:
	report_lines.append("三、隔离高压场景（压力校勘体，聚焦牌组，无遗物）")
	report_lines.append(_table_header())
	var results: Dictionary = {}
	var no_relics: Array[StringName] = []
	for strategy: Strategy in [
		Strategy.BALANCED,
		Strategy.OVERLOAD_AGGRESSIVE,
		Strategy.SEAL_PRIORITY,
		Strategy.ECHO_PRIORITY,
	]:
		var result: Dictionary = _run_scenario(
			3, PRESSURE_ENEMY_ID, no_relics, strategy, FOCUSED_BONUS_IDS
		)
		results[strategy] = result
		report_lines.append(_table_row(_strategy_name(strategy), result))
		report_lines.append("　　卡牌频率：%s" % _card_frequency_text(result))
	var has_calibrated_pressure: bool = false
	for result_value: Variant in results.values():
		var result: Dictionary = result_value as Dictionary
		var win_rate: float = float(result[&"win_rate"])
		if win_rate >= 0.40 and win_rate <= 0.80 and int(result[&"losses"]) > 0:
			has_calibrated_pressure = true
	_expect(has_calibrated_pressure, "至少一个高压策略场景胜率位于 40%～80% 且存在真实败局")
	var aggressive: Dictionary = results[Strategy.OVERLOAD_AGGRESSIVE]
	_expect(
		float(aggressive[&"avg_fractures"]) >= 1.0,
		"OVERLOAD_AGGRESSIVE 平均裂解至少 1.0（实际 %.2f）" % float(aggressive[&"avg_fractures"])
	)
	_expect(int(aggressive[&"timeouts"]) == 0, "激进超载高压场景无超时")
	report_lines.append("")
	return results


# -------------------------------------------------------------- 遗物对比

func _simulate_relic_comparison() -> void:
	report_lines.append("四、遗物模拟指纹（压力校勘体，OVERLOAD_AGGRESSIVE）")
	report_lines.append(_table_header())
	var stabilizer: Array[StringName] = [&"crack_stabilizer"]
	var bookplate: Array[StringName] = [&"wordless_bookplate"]
	var with_stabilizer: Dictionary = _run_scenario(
		3, PRESSURE_ENEMY_ID, stabilizer, Strategy.OVERLOAD_AGGRESSIVE, OVERLOAD_BONUS_IDS
	)
	var with_bookplate: Dictionary = _run_scenario(
		3, PRESSURE_ENEMY_ID, bookplate, Strategy.OVERLOAD_AGGRESSIVE, OVERLOAD_BONUS_IDS
	)
	report_lines.append(_table_row("裂纹稳定器", with_stabilizer))
	report_lines.append("　　遗物：%s" % _relic_telemetry_text(with_stabilizer))
	report_lines.append(_table_row("无字藏书票", with_bookplate))
	report_lines.append("　　遗物：%s" % _relic_telemetry_text(with_bookplate))
	var stabilizer_triggers: Dictionary = with_stabilizer[&"relic_trigger_counts"]
	var stabilizer_benefits: Dictionary = with_stabilizer[&"relic_net_benefits"]
	var bookplate_triggers: Dictionary = with_bookplate[&"relic_trigger_counts"]
	var bookplate_benefits: Dictionary = with_bookplate[&"relic_net_benefits"]
	_expect(
		int(stabilizer_triggers.get(&"crack_stabilizer", 0)) == SEEDS.size(),
		"裂纹稳定器在每局首次超载时触发"
	)
	_expect(
		int(stabilizer_benefits.get(&"crack_stabilizer", 0)) == SEEDS.size(),
		"裂纹稳定器净收益记录为每局少获得 1 不稳定"
	)
	_expect(
		int(bookplate_triggers.get(&"wordless_bookplate", 0)) == SEEDS.size(),
		"无字藏书票在每局首次律式后触发"
	)
	_expect(
		int(bookplate_benefits.get(&"wordless_bookplate", 0)) == SEEDS.size(),
		"无字藏书票净收益记录为每局额外抽 1 张"
	)
	_expect(
		_result_fingerprint(with_stabilizer) != _result_fingerprint(with_bookplate),
		"裂纹稳定器与无字藏书票的模拟指纹不同"
	)
	report_lines.append("")


func _verify_m0_strategy_differences(results: Dictionary) -> void:
	report_lines.append("五、策略差异解释")
	var balanced: Dictionary = results[Strategy.BALANCED]
	var aggressive: Dictionary = results[Strategy.OVERLOAD_AGGRESSIVE]
	var seal: Dictionary = results[Strategy.SEAL_PRIORITY]
	var echo: Dictionary = results[Strategy.ECHO_PRIORITY]
	var balanced_uses: Dictionary = balanced[&"card_use_counts"]
	var aggressive_uses: Dictionary = aggressive[&"card_use_counts"]
	var seal_uses: Dictionary = seal[&"card_use_counts"]
	var echo_uses: Dictionary = echo[&"card_use_counts"]
	var aggressive_overload_uses: int = int(aggressive_uses.get(&"boundary_read", 0)) + int(aggressive_uses.get(&"rift_slash", 0))
	var balanced_overload_uses: int = int(balanced_uses.get(&"boundary_read", 0)) + int(balanced_uses.get(&"rift_slash", 0))
	var seal_uses_total: int = int(seal_uses.get(&"delayed_guard", 0)) + int(seal_uses.get(&"countdown_scar", 0)) + int(seal_uses.get(&"unseal_order", 0))
	var echo_uses_total: int = int(echo_uses.get(&"restate", 0)) + int(echo_uses.get(&"homophone", 0))
	_expect(
		float(aggressive[&"avg_fractures"]) > float(balanced[&"avg_fractures"]),
		"激进超载比保守策略产生更多裂解（%.2f > %.2f）" % [float(aggressive[&"avg_fractures"]), float(balanced[&"avg_fractures"])]
	)
	_expect(
		aggressive_overload_uses > balanced_overload_uses,
		"激进超载使用更多越界读取/裂隙挥击（%d > %d）" % [aggressive_overload_uses, balanced_overload_uses]
	)
	_expect(seal_uses_total > 0, "封存优先策略实际使用封存组件（总计 %d 次）" % seal_uses_total)
	_expect(echo_uses_total > 0, "回响优先策略实际使用回响组件（总计 %d 次）" % echo_uses_total)
	var fingerprints: Dictionary = {}
	for strategy: Strategy in [Strategy.BALANCED, Strategy.OVERLOAD_AGGRESSIVE, Strategy.SEAL_PRIORITY, Strategy.ECHO_PRIORITY]:
		fingerprints[_result_fingerprint(results[strategy])] = true
	_expect(fingerprints.size() >= 3, "四种策略至少形成三种不同结果指纹（实际 %d）" % fingerprints.size())
	report_lines.append("　BALANCED 以半血为防御切换点；OVERLOAD_AGGRESSIVE 主动累积风险；SEAL_PRIORITY 提前布置延迟收益；ECHO_PRIORITY 紧跟已结算攻式。")
	report_lines.append("")


# -------------------------------------------------------------- 确定性验证

func _verify_determinism() -> void:
	report_lines.append("六、固定种子可复现性")
	var cases: Array[Dictionary] = [
		{&"label": "主线节点6", &"stage": 6, &"enemy": &"", &"relics": [&"crack_stabilizer"], &"strategy": Strategy.BALANCED, &"bonus": []},
		{&"label": "倒读者", &"stage": 6, &"enemy": &"reverse_reader", &"relics": [&"crack_stabilizer"], &"strategy": Strategy.BALANCED, &"bonus": []},
		{&"label": "高压激进超载", &"stage": 3, &"enemy": PRESSURE_ENEMY_ID, &"relics": [], &"strategy": Strategy.OVERLOAD_AGGRESSIVE, &"bonus": FOCUSED_BONUS_IDS},
	]
	for case: Dictionary in cases:
		var relics: Array[StringName] = []
		for relic_value: Variant in case[&"relics"]:
			relics.append(relic_value as StringName)
		var bonus_ids: Array[StringName] = []
		for bonus_value: Variant in case[&"bonus"]:
			bonus_ids.append(bonus_value as StringName)
		var first: Dictionary = _run_scenario(
			int(case[&"stage"]), case[&"enemy"] as StringName, relics,
			int(case[&"strategy"]) as Strategy, bonus_ids
		)
		var second: Dictionary = _run_scenario(
			int(case[&"stage"]), case[&"enemy"] as StringName, relics,
			int(case[&"strategy"]) as Strategy, bonus_ids
		)
		_expect(first[&"digest"] == second[&"digest"], "%s 的逐局模拟完全复现" % case[&"label"])
		report_lines.append("　%s：%s" % [case[&"label"], first[&"digest"]])
	report_lines.append("")


# ------------------------------------------------------------------ 模拟内核

func _run_scenario(
	stage: int,
	enemy_id: StringName,
	relics: Array[StringName],
	strategy: Strategy,
	bonus_card_ids: Array[StringName]
) -> Dictionary:
	var turn_values: Array[int] = []
	var fracture_values: Array[int] = []
	var total_hp: int = 0
	var wins: int = 0
	var losses: int = 0
	var timeouts: int = 0
	var card_use_counts: Dictionary = {}
	var relic_trigger_counts: Dictionary = {}
	var relic_net_benefits: Dictionary = {}
	var digest_parts: Array[String] = []
	var enemy_label: String = ""
	for card_key: Variant in CardCatalog.DEFINITIONS.keys():
		card_use_counts[card_key as StringName] = 0
	for battle_seed: int in SEEDS:
		var outcome: Dictionary = _simulate_battle(
			battle_seed, stage, enemy_id, relics, strategy, bonus_card_ids
		)
		turn_values.append(int(outcome[&"turns"]))
		fracture_values.append(int(outcome[&"fractures"]))
		total_hp += int(outcome[&"hp_left"])
		if bool(outcome[&"victory"]):
			wins += 1
		elif bool(outcome[&"timeout"]):
			timeouts += 1
		else:
			losses += 1
		_merge_counts(card_use_counts, outcome[&"card_uses"] as Dictionary)
		_merge_counts(relic_trigger_counts, outcome[&"relic_trigger_counts"] as Dictionary)
		_merge_counts(relic_net_benefits, outcome[&"relic_net_benefits"] as Dictionary)
		enemy_label = str(outcome[&"enemy"])
		digest_parts.append(str(outcome[&"digest"]))
	var count: float = float(SEEDS.size())
	var total_turns: int = 0
	var total_fractures: int = 0
	for turns: int in turn_values:
		total_turns += turns
	for fractures: int in fracture_values:
		total_fractures += fractures
	var card_use_frequency: Dictionary = {}
	for card_key: Variant in card_use_counts.keys():
		card_use_frequency[card_key] = float(card_use_counts[card_key]) / count
	return {
		&"enemy": enemy_label,
		&"strategy": _strategy_name(strategy),
		&"wins": wins,
		&"losses": losses,
		&"timeouts": timeouts,
		&"win_rate": float(wins) / count,
		&"loss_rate": float(losses) / count,
		&"timeout_rate": float(timeouts) / count,
		&"avg_turns": float(total_turns) / count,
		&"turn_min": _minimum(turn_values),
		&"turn_p25": _percentile(turn_values, 0.25),
		&"turn_p50": _percentile(turn_values, 0.50),
		&"turn_p75": _percentile(turn_values, 0.75),
		&"avg_hp_left": float(total_hp) / count,
		&"avg_fractures": float(total_fractures) / count,
		&"fracture_values": fracture_values,
		&"card_use_counts": card_use_counts,
		&"card_use_frequency": card_use_frequency,
		&"relic_trigger_counts": relic_trigger_counts,
		&"relic_net_benefits": relic_net_benefits,
		&"digest": "|".join(digest_parts),
	}


func _simulate_battle(
	battle_seed: int,
	stage: int,
	enemy_id: StringName,
	relics: Array[StringName],
	strategy: Strategy,
	bonus_card_ids: Array[StringName]
) -> Dictionary:
	var model: CombatModel = CombatModelScript.new()
	model.start_battle(battle_seed, stage, bonus_card_ids, enemy_id, relics)
	var completed_turns: int = 0
	var action_guard: int = 0
	while not model.battle_over and completed_turns < MAX_TURNS:
		var acted: bool = true
		while acted and not model.battle_over:
			acted = false
			action_guard += 1
			if action_guard > MAX_TURNS * 100:
				break
			if model.has_pending_selection():
				var candidates: Array[int] = model.get_pending_candidate_indices()
				if candidates.is_empty():
					model.cancel_pending_selection()
				else:
					model.resolve_pending_selection(candidates[0])
				acted = true
				continue
			var index: int = _pick_card(model, strategy)
			if index >= 0:
				model.play_card(index)
				acted = true
		if model.battle_over or action_guard > MAX_TURNS * 100:
			break
		model.end_player_turn()
		completed_turns += 1
	var timeout: bool = not model.battle_over
	var telemetry: Dictionary = model.get_telemetry()
	return {
		&"turns": model.turn_number,
		&"hp_left": model.player_hp,
		&"fractures": int(telemetry[&"fractures"]),
		&"card_uses": telemetry[&"card_uses"],
		&"relic_trigger_counts": telemetry[&"relic_trigger_counts"],
		&"relic_net_benefits": telemetry[&"relic_net_benefits"],
		&"victory": model.victory,
		&"timeout": timeout,
		&"enemy": model.enemy_name,
		&"digest": "%d/%d/%d/%d/%s/%s" % [
			model.turn_number,
			model.player_hp,
			int(telemetry[&"fractures"]),
			1 if model.victory else 0,
			_dictionary_digest(telemetry[&"card_uses"] as Dictionary),
			_dictionary_digest(telemetry[&"relic_net_benefits"] as Dictionary),
		],
	}


func _pick_card(model: CombatModel, strategy: Strategy) -> int:
	match strategy:
		Strategy.OVERLOAD_AGGRESSIVE:
			return _pick_overload_aggressive(model)
		Strategy.SEAL_PRIORITY:
			return _pick_seal_priority(model)
		Strategy.ECHO_PRIORITY:
			return _pick_echo_priority(model)
		_:
			return _pick_balanced(model)


func _pick_balanced(model: CombatModel) -> int:
	var defensive_first: bool = model.player_hp * 2 < CombatModelScript.PLAYER_MAX_HP
	var priorities: Array[int] = [
		CardData.CardType.DEFENSE if defensive_first else CardData.CardType.ATTACK,
		CardData.CardType.ATTACK if defensive_first else CardData.CardType.DEFENSE,
		CardData.CardType.LAW,
	]
	return _find_first_type(model, priorities)


## 文档约定：临界许可(>=8)与崩解协议(>=5、能量>=2)先检查；随后优先
## 越界读取、裂隙挥击；不主动强制稳定；生命低于 25% 才转守式，否则攻击。
func _pick_overload_aggressive(model: CombatModel) -> int:
	var index: int = -1
	if model.instability >= 8:
		index = _find_card_by_id(model, &"critical_permission")
		if index >= 0:
			return index
	if model.instability >= 5 and model.energy >= 2:
		index = _find_card_by_id(model, &"dissolution_protocol")
		if index >= 0:
			return index
	for overload_id: StringName in [&"boundary_read", &"rift_slash"]:
		index = _find_card_by_id(model, overload_id)
		if index >= 0:
			return index
	if model.player_hp * 4 < CombatModelScript.PLAYER_MAX_HP:
		index = _find_first_type(model, [CardData.CardType.DEFENSE], [&"forced_stability"])
		if index >= 0:
			return index
	index = _find_first_type(model, [CardData.CardType.ATTACK], [&"forced_stability"])
	if index >= 0:
		return index
	return _find_first_type(model, [CardData.CardType.LAW], [&"forced_stability"])


func _pick_seal_priority(model: CombatModel) -> int:
	var index: int = -1
	if not model.sealed_zone.is_empty():
		index = _find_card_by_id(model, &"unseal_order")
		if index >= 0:
			return index
	for card_id: StringName in [&"countdown_scar", &"delayed_guard", &"prewritten_ending"]:
		index = _find_card_by_id(model, card_id)
		if index >= 0:
			return index
	if model.player_hp * 2 < CombatModelScript.PLAYER_MAX_HP:
		index = _find_first_type(model, [CardData.CardType.DEFENSE])
		if index >= 0:
			return index
	return _find_first_type(model, [CardData.CardType.ATTACK, CardData.CardType.LAW, CardData.CardType.DEFENSE])


func _pick_echo_priority(model: CombatModel) -> int:
	var index: int = -1
	if model.last_card_type == CardData.CardType.ATTACK and model.last_damage_snapshot > 0:
		for echo_id: StringName in [&"restate", &"homophone"]:
			index = _find_card_by_id(model, echo_id)
			if index >= 0:
				return index
	if model.last_card_type == CardData.CardType.DEFENSE and model.last_block_snapshot > 0:
		index = _find_card_by_id(model, &"copied_guard")
		if index >= 0:
			return index
	index = _find_first_type(model, [CardData.CardType.ATTACK])
	if index >= 0:
		return index
	if model.player_hp * 2 < CombatModelScript.PLAYER_MAX_HP:
		index = _find_first_type(model, [CardData.CardType.DEFENSE])
		if index >= 0:
			return index
	return _find_first_type(model, [CardData.CardType.LAW, CardData.CardType.DEFENSE])


func _find_card_by_id(model: CombatModel, card_id: StringName) -> int:
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		if card.id == card_id and model.can_play_card(index):
			return index
	return -1


func _find_first_type(
	model: CombatModel,
	priorities: Array[int],
	excluded_ids: Array[StringName] = []
) -> int:
	for wanted_type: int in priorities:
		for index: int in range(model.hand.size()):
			var card: CardData = model.hand[index]
			if card.card_type != wanted_type or excluded_ids.has(card.id):
				continue
			if model.can_play_card(index):
				return index
	return -1


func _is_playable(model: CombatModel, card: CardData) -> bool:
	if card.card_type == CardData.CardType.STATUS:
		return false
	return model.get_card_cost(card) <= model.energy


# ---------------------------------------------------------------------- 汇总

func _merge_counts(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		target[key] = int(target.get(key, 0)) + int(source[key])


func _minimum(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var result: int = values[0]
	for value: int in values:
		result = mini(result, value)
	return result


func _percentile(values: Array[int], quantile: float) -> int:
	if values.is_empty():
		return 0
	var sorted_values: Array[int] = values.duplicate()
	sorted_values.sort()
	var index: int = floori(float(sorted_values.size() - 1) * quantile)
	return sorted_values[index]


func _dictionary_digest(values: Dictionary) -> String:
	var keys: Array[String] = []
	for key: Variant in values.keys():
		if int(values[key]) != 0:
			keys.append(str(key))
	keys.sort()
	var parts: Array[String] = []
	for key_text: String in keys:
		parts.append("%s=%d" % [key_text, int(values[StringName(key_text)])])
	return ",".join(parts)


func _result_fingerprint(result: Dictionary) -> String:
	return "%d/%d/%d/%.2f/%.1f/%s/%s" % [
		int(result[&"wins"]),
		int(result[&"losses"]),
		int(result[&"timeouts"]),
		float(result[&"avg_fractures"]),
		float(result[&"avg_hp_left"]),
		_dictionary_digest(result[&"card_use_counts"] as Dictionary),
		_dictionary_digest(result[&"relic_net_benefits"] as Dictionary),
	]


func _strategy_name(strategy: Strategy) -> String:
	match strategy:
		Strategy.BALANCED:
			return "BALANCED"
		Strategy.OVERLOAD_AGGRESSIVE:
			return "OVERLOAD_AGGRESSIVE"
		Strategy.SEAL_PRIORITY:
			return "SEAL_PRIORITY"
		Strategy.ECHO_PRIORITY:
			return "ECHO_PRIORITY"
	return "UNKNOWN"


func _card_frequency_text(result: Dictionary) -> String:
	var counts: Dictionary = result[&"card_use_counts"]
	var frequencies: Dictionary = result[&"card_use_frequency"]
	var active_ids: Array[String] = []
	for key: Variant in counts.keys():
		if int(counts[key]) > 0:
			active_ids.append(str(key))
	active_ids.sort()
	var parts: Array[String] = []
	for card_id_text: String in active_ids:
		var card_id: StringName = StringName(card_id_text)
		var definition: Dictionary = CardCatalog.get_definition(card_id)
		parts.append("%s %d次/%.2f每局" % [str(definition.get(&"title", card_id_text)), int(counts[card_id]), float(frequencies[card_id])])
	return "；".join(parts)


func _relic_telemetry_text(result: Dictionary) -> String:
	var triggers: Dictionary = result[&"relic_trigger_counts"]
	var benefits: Dictionary = result[&"relic_net_benefits"]
	var ids: Array[String] = []
	for key: Variant in triggers.keys():
		ids.append(str(key))
	ids.sort()
	var parts: Array[String] = []
	for id_text: String in ids:
		var relic_id: StringName = StringName(id_text)
		parts.append("%s 触发%d/净收益%d" % [RuleEngine.relic_title(relic_id), int(triggers[relic_id]), int(benefits.get(relic_id, 0))])
	return "；".join(parts) if not parts.is_empty() else "无触发"


func _table_header() -> String:
	return "　%-22s %8s %11s %11s %10s %8s %10s %8s" % [
		"场景/策略", "胜/负/超时", "胜/负/超时率", "回合P25/50/75", "平均回合", "剩余HP", "平均裂解", "裂解分布",
	]


func _table_row(label: String, result: Dictionary) -> String:
	return "　%-22s %2d/%2d/%2d %3.0f/%3.0f/%3.0f%% %3d/%3d/%3d %10.1f %8.1f %10.2f %8s" % [
		label,
		int(result[&"wins"]), int(result[&"losses"]), int(result[&"timeouts"]),
		float(result[&"win_rate"]) * 100.0, float(result[&"loss_rate"]) * 100.0, float(result[&"timeout_rate"]) * 100.0,
		int(result[&"turn_p25"]), int(result[&"turn_p50"]), int(result[&"turn_p75"]),
		float(result[&"avg_turns"]), float(result[&"avg_hp_left"]), float(result[&"avg_fractures"]),
		str(result[&"fracture_values"]),
	]


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
