extends SceneTree

## 数值模拟与平衡阈值检查。
##
## 用固定种子与固定策略跑若干场景，输出可读的中文汇总，并对明显失衡设断言。
## 策略是确定性的（不使用额外随机数），因此同一种子必然复现同一结果。

const CombatModelScript: Script = preload("res://scripts/core/combat_model.gd")

const SEEDS: Array[int] = [73103, 80011, 91027, 100003, 110009]
const MAX_TURNS: int = 40

## 固定策略。两种都是确定性的，不消耗额外随机数。
enum Strategy {
	BALANCED,           ## 优先攻式，生命低于一半时优先守式
	OVERLOAD_AGGRESSIVE,## 优先律式与超载牌，用于压测裂解与遗物
}

var failures: int = 0
var report_lines: Array[String] = []


func _init() -> void:
	report_lines.append("《断环》v0.5 确定性数值模拟")
	report_lines.append("固定种子：%s｜每场景 %d 局｜固定策略：优先攻击，生命偏低时优先防御" % [
		str(SEEDS), SEEDS.size(),
	])
	report_lines.append("")

	_simulate_path_nodes()
	_simulate_formal_enemies()
	_simulate_relic_comparison()
	_verify_determinism()

	for line: String in report_lines:
		print(line)
	if failures == 0:
		print("PASS: 全部平衡阈值检查通过")
		quit(0)
	else:
		push_error("FAIL: %d 项平衡检查未通过" % failures)
		quit(1)


# ------------------------------------------------------------------ 场景一：主线

func _simulate_path_nodes() -> void:
	report_lines.append("一、主线六个路径节点（起始遗物：裂纹稳定器）")
	report_lines.append(_table_header())
	var relics: Array[StringName] = [&"crack_stabilizer"]
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		var result: Dictionary = _run_scenario(stage, &"", relics)
		report_lines.append(_table_row("节点%d %s" % [stage, result[&"enemy"]], result))
		# 主线节点必须全部可以在固定策略下稳定通过，否则新玩家无法自然上手。
		_expect(
			float(result[&"win_rate"]) >= 1.0,
			"主线节点 %d 在固定策略下必胜（实际胜率 %.0f%%）" % [stage, float(result[&"win_rate"]) * 100.0]
		)
		# 普通战斗预期 3～5 回合；训练体允许更短。
		var turns: float = float(result[&"avg_turns"])
		var lower_bound: float = 1.0 if stage == 1 else 2.0
		_expect(
			turns >= lower_bound and turns <= 9.0,
			"主线节点 %d 平均回合数落在合理区间（实际 %.1f）" % [stage, turns]
		)
		# 前三场必须留下足够生命，否则初始牌组防御不足。
		if stage <= 3:
			_expect(
				float(result[&"avg_hp_left"]) >= 40.0,
				"主线节点 %d 结束时平均剩余生命充足（实际 %.1f）" % [stage, float(result[&"avg_hp_left"])]
			)
	report_lines.append("")


# -------------------------------------------------------------- 场景二：正式敌人

func _simulate_formal_enemies() -> void:
	report_lines.append("二、机制测试场的三个正式敌人（完整机制牌组）")
	report_lines.append(_table_header())
	var relics: Array[StringName] = [&"crack_stabilizer"]
	var expectations: Dictionary = {
		&"hollow_name_guard": {&"min_turns": 3.0, &"max_turns": 14.0},
		&"reverse_reader": {&"min_turns": 2.0, &"max_turns": 12.0},
		&"binding_instrument": {&"min_turns": 5.0, &"max_turns": 22.0},
	}
	for enemy_id: StringName in EnemyCatalog.TEST_ARENA_ENEMY_IDS:
		if not expectations.has(enemy_id):
			continue
		var result: Dictionary = _run_scenario(CombatModelScript.TUTORIAL_STAGE_MAX, enemy_id, relics)
		report_lines.append(_table_row(str(result[&"enemy"]), result))
		var bounds: Dictionary = expectations[enemy_id]
		var turns: float = float(result[&"avg_turns"])
		_expect(
			turns >= float(bounds[&"min_turns"]),
			"%s 不会被一两回合秒杀（实际 %.1f 回合）" % [result[&"enemy"], turns]
		)
		_expect(
			turns <= float(bounds[&"max_turns"]),
			"%s 不会陷入僵局（实际 %.1f 回合）" % [result[&"enemy"], turns]
		)
		# 精英应当明显比普通敌人更有压力，但不能必死。
		_expect(
			float(result[&"win_rate"]) > 0.0,
			"%s 至少存在可胜路径（实际胜率 %.0f%%）" % [result[&"enemy"], float(result[&"win_rate"]) * 100.0]
		)
		_expect(
			int(result[&"timeouts"]) == 0,
			"%s 不会打到回合上限（超时 %d 局）" % [result[&"enemy"], int(result[&"timeouts"])]
		)
	report_lines.append("")

	var guard: Dictionary = _run_scenario(CombatModelScript.TUTORIAL_STAGE_MAX, &"hollow_name_guard", relics)
	var elite: Dictionary = _run_scenario(CombatModelScript.TUTORIAL_STAGE_MAX, &"binding_instrument", relics)
	_expect(
		float(elite[&"avg_turns"]) > float(guard[&"avg_turns"]),
		"精英装订刑具比普通空名卫士更持久（%.1f > %.1f 回合）" % [
			float(elite[&"avg_turns"]), float(guard[&"avg_turns"]),
		]
	)
	_expect(
		float(elite[&"avg_hp_left"]) < float(guard[&"avg_hp_left"]),
		"精英战对生命的压力高于普通战（剩余 %.1f < %.1f）" % [
			float(elite[&"avg_hp_left"]), float(guard[&"avg_hp_left"]),
		]
	)


# -------------------------------------------------------------- 场景三：遗物对比

func _simulate_relic_comparison() -> void:
	report_lines.append("三、遗物对裂解压力的影响（节点 3 超载牌组）")
	report_lines.append(_table_header())
	var none: Array[StringName] = []
	var stabilizer: Array[StringName] = [&"crack_stabilizer"]
	var bookplate: Array[StringName] = [&"wordless_bookplate"]
	var without: Dictionary = _run_scenario(3, &"", none)
	var with_stabilizer: Dictionary = _run_scenario(3, &"", stabilizer)
	var with_bookplate: Dictionary = _run_scenario(3, &"", bookplate)
	report_lines.append(_table_row("无遗物", without))
	report_lines.append(_table_row("裂纹稳定器", with_stabilizer))
	report_lines.append(_table_row("无字藏书票", with_bookplate))
	# 裂纹稳定器降低超载积累，因此裂解次数不应上升。
	_expect(
		float(with_stabilizer[&"avg_fractures"]) <= float(without[&"avg_fractures"]),
		"裂纹稳定器不会增加裂解次数（%.2f ≤ %.2f）" % [
			float(with_stabilizer[&"avg_fractures"]), float(without[&"avg_fractures"]),
		]
	)
	_expect(
		float(with_stabilizer[&"avg_hp_left"]) >= float(without[&"avg_hp_left"]),
		"裂纹稳定器不会降低剩余生命（%.1f ≥ %.1f）" % [
			float(with_stabilizer[&"avg_hp_left"]), float(without[&"avg_hp_left"]),
		]
	)
	# 单件遗物不应把平均剩余生命改变超过 15 点，否则遗物强度失衡。
	var hp_swing: float = absf(float(with_stabilizer[&"avg_hp_left"]) - float(without[&"avg_hp_left"]))
	_expect(hp_swing <= 15.0, "单件起始遗物的生命影响可控（波动 %.1f ≤ 15）" % hp_swing)
	var bookplate_swing: float = absf(float(with_bookplate[&"avg_turns"]) - float(without[&"avg_turns"]))
	_expect(bookplate_swing <= 4.0, "无字藏书票的节奏影响可控（回合波动 %.1f ≤ 4）" % bookplate_swing)
	report_lines.append("")


# ------------------------------------------------------------------ 确定性验证

func _verify_determinism() -> void:
	report_lines.append("四、固定种子可复现性")
	var relics: Array[StringName] = [&"crack_stabilizer"]
	for enemy_id: StringName in [&"", &"hollow_name_guard", &"reverse_reader", &"binding_instrument"]:
		var first: Dictionary = _run_scenario(CombatModelScript.TUTORIAL_STAGE_MAX, enemy_id, relics)
		var second: Dictionary = _run_scenario(CombatModelScript.TUTORIAL_STAGE_MAX, enemy_id, relics)
		var label: String = "主线节点6" if enemy_id == &"" else EnemyCatalog.get_display_name(enemy_id)
		_expect(first[&"digest"] == second[&"digest"], "%s 的模拟结果可完全复现" % label)
		report_lines.append("%s：指纹 %s" % [label, first[&"digest"]])
	report_lines.append("")


# ------------------------------------------------------------------ 模拟内核

func _run_scenario(stage: int, enemy_id: StringName, relics: Array[StringName]) -> Dictionary:
	var total_turns: int = 0
	var total_hp: int = 0
	var total_fractures: int = 0
	var wins: int = 0
	var timeouts: int = 0
	var digest_parts: Array[String] = []
	var enemy_label: String = ""
	for battle_seed: int in SEEDS:
		var outcome: Dictionary = _simulate_battle(battle_seed, stage, enemy_id, relics)
		total_turns += int(outcome[&"turns"])
		total_hp += int(outcome[&"hp_left"])
		total_fractures += int(outcome[&"fractures"])
		if bool(outcome[&"victory"]):
			wins += 1
		if bool(outcome[&"timeout"]):
			timeouts += 1
		enemy_label = str(outcome[&"enemy"])
		digest_parts.append("%d/%d/%d" % [
			int(outcome[&"turns"]), int(outcome[&"hp_left"]), int(outcome[&"fractures"]),
		])
	var count: float = float(SEEDS.size())
	return {
		&"enemy": enemy_label,
		&"avg_turns": float(total_turns) / count,
		&"avg_hp_left": float(total_hp) / count,
		&"avg_fractures": float(total_fractures) / count,
		&"win_rate": float(wins) / count,
		&"timeouts": timeouts,
		&"digest": "|".join(digest_parts),
	}


## 固定策略：
## 1. 有待选择请求时，一律选择第一个候选（确定性，且覆盖真实选择流程）。
## 2. 生命低于最大值一半时优先打守式，否则优先打攻式。
## 3. 同优先级内按手牌从左到右取第一张打得起的牌。
## 4. 没有可打的牌就结束回合。
func _simulate_battle(
	battle_seed: int, stage: int, enemy_id: StringName, relics: Array[StringName]
) -> Dictionary:
	var model = CombatModelScript.new()
	var no_bonus: Array[StringName] = []
	model.start_battle(battle_seed, stage, no_bonus, enemy_id, relics)
	var fractures: int = 0
	var guard_turns: int = 0
	while not model.battle_over and guard_turns < MAX_TURNS:
		var acted: bool = true
		while acted and not model.battle_over:
			acted = false
			if model.has_pending_selection():
				var candidates: Array[int] = model.get_pending_candidate_indices()
				if candidates.is_empty():
					model.cancel_pending_selection()
				else:
					model.resolve_pending_selection(candidates[0])
				acted = true
				continue
			var index: int = _pick_card(model)
			if index >= 0:
				var before: int = model.instability
				model.play_card(index)
				if model.instability < before -1:
					fractures += 1
				acted = true
		if model.battle_over:
			break
		var instability_before_end: int = model.instability
		model.end_player_turn()
		if model.instability < instability_before_end - 1:
			fractures += 1
		guard_turns += 1
	return {
		&"turns": model.turn_number,
		&"hp_left": model.player_hp,
		&"fractures": fractures,
		&"victory": model.victory,
		&"timeout": guard_turns >= MAX_TURNS and not model.battle_over,
		&"enemy": model.enemy_name,
	}


func _pick_card(model) -> int:
	var defensive_first: bool = model.player_hp * 2 < CombatModelScript.PLAYER_MAX_HP
	var priority: Array[int] = []
	if defensive_first:
		priority = [CardData.CardType.DEFENSE, CardData.CardType.ATTACK, CardData.CardType.LAW]
	else:
		priority = [CardData.CardType.ATTACK, CardData.CardType.DEFENSE, CardData.CardType.LAW]
	for wanted_type: int in priority:
		for index: int in range(model.hand.size()):
			var card = model.hand[index]
			if card.card_type != wanted_type:
				continue
			if card.card_type == CardData.CardType.STATUS:
				continue
			if model.get_card_cost(card) > model.energy:
				continue
			return index
	return -1


# ---------------------------------------------------------------------- 输出

func _table_header() -> String:
	return "　%-22s %8s %10s %8s %8s" % ["场景", "平均回合", "剩余生命", "裂解", "胜率"]


func _table_row(label: String, result: Dictionary) -> String:
	return "　%-22s %8.1f %10.1f %8.2f %7.0f%%" % [
		label,
		float(result[&"avg_turns"]),
		float(result[&"avg_hp_left"]),
		float(result[&"avg_fractures"]),
		float(result[&"win_rate"]) * 100.0,
	]


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
