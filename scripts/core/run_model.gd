class_name RunModel
extends RefCounted


const DEFAULT_SEED: int = 73103
const REWARD_STAGES: Array[int] = [3, 5, 6]
const EVENT_IDS: Array[StringName] = [&"authorless_book", &"seventh_dock", &"calibration_station"]
const RARE_REWARD_IDS: Array[StringName] = [
	&"critical_permission", &"dissolution_protocol", &"prewritten_ending", &"unseal_order", &"homophone",
]

var seed_value: int = DEFAULT_SEED
var current_node: int = 0
var ink_crystals: int = 0
var evidence: Array[String] = []
var relics: Array[StringName] = []
var deck_instances: Array[Dictionary] = []
var acquired_card_ids: Array[StringName] = []
var next_deck_instance_id: int = 1
var reward_round: int = 0
var pending_reward_ids: Array[StringName] = []
var selected_event_id: StringName = &""
var event_resolved: bool = false
var event_outcome: String = ""
var player_max_hp: int = 70
var player_hp: int = 70
var next_battle_missing_name: int = 0
var completed_battles: Array[int] = []


func start_run(p_seed: int = DEFAULT_SEED) -> void:
	seed_value = p_seed
	current_node = 0
	ink_crystals = 0
	evidence.clear()
	relics.clear()
	deck_instances.clear()
	acquired_card_ids.clear()
	next_deck_instance_id = 1
	reward_round = 0
	pending_reward_ids.clear()
	selected_event_id = &""
	event_resolved = false
	event_outcome = ""
	player_max_hp = 70
	player_hp = 70
	next_battle_missing_name = 0
	completed_battles.clear()
	for card_id: StringName in CardCatalog.STARTER_IDS:
		_add_deck_card(card_id, false)


func get_deck_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for instance: Dictionary in deck_instances:
		ids.append(instance[&"card_id"] as StringName)
	return ids


func get_acquired_card_ids() -> Array[StringName]:
	return acquired_card_ids.duplicate()


func record_battle_victory(stage: int) -> void:
	if completed_battles.has(stage):
		return
	completed_battles.append(stage)
	current_node = stage
	ink_crystals += 12


func should_offer_reward(stage: int) -> bool:
	return REWARD_STAGES.has(stage)


func generate_reward_choices(stage: int) -> Array[StringName]:
	pending_reward_ids.clear()
	var reward_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	reward_rng.seed = seed_value + stage * 1009 + reward_round * 7919
	var pool: Array[StringName] = _reward_pool_for_stage(stage)
	for draw_index: int in range(3):
		var pool_index: int = reward_rng.randi_range(0, pool.size() - 1)
		pending_reward_ids.append(pool[pool_index])
		pool.remove_at(pool_index)
	reward_round += 1
	return pending_reward_ids.duplicate()


func _reward_pool_for_stage(stage: int) -> Array[StringName]:
	# 奖励池遵循教学节奏，不能让奖励提前泄露尚未教学的关键词。
	if stage <= 3:
		return [&"broken_sentence", &"blank_space", &"rift_slash", &"forced_stability"]
	if stage <= 5:
		return [
			&"broken_sentence", &"blank_space", &"unsigned_support", &"rift_slash",
			&"forced_stability", &"delayed_guard", &"countdown_scar", &"restate", &"copied_guard",
		]
	return CardCatalog.REWARD_IDS.duplicate()


func choose_reward(choice_index: int) -> bool:
	if choice_index < 0 or choice_index >= pending_reward_ids.size():
		return false
	_add_deck_card(pending_reward_ids[choice_index], true)
	pending_reward_ids.clear()
	return true


func skip_reward() -> bool:
	if pending_reward_ids.is_empty():
		return false
	pending_reward_ids.clear()
	return true


func begin_event() -> StringName:
	var event_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	event_rng.seed = seed_value + 6067
	selected_event_id = EVENT_IDS[event_rng.randi_range(0, EVENT_IDS.size() - 1)]
	event_resolved = false
	event_outcome = ""
	current_node = 7
	return selected_event_id


func get_event_title(event_id: StringName = selected_event_id) -> String:
	match event_id:
		&"authorless_book":
			return "没有作者的书"
		&"seventh_dock":
			return "第七码头"
		&"calibration_station":
			return "校准站"
	return "未知事件"


func get_event_story(event_id: StringName = selected_event_id) -> String:
	match event_id:
		&"authorless_book":
			return "一本没有作者的书正逐字记录你的动作。下一行已经写出你将选择的选项，页脚却先一步把你称作 REC-10。这个编号尚未由任何人向你公开。"
		&"seventh_dock":
			return "残骸深处立着一座与终末机构完全相同的码头，但石材年代早了数百年。返航名单上，九个同姓记录被墨迹涂去。"
		&"calibration_station":
			return "仍在运行的终末机构设备要求你提交身体编号。屏幕显示：当前编号与上一名回收者拥有相同权限和校准参数，资产标识被遮蔽。"
	return "事件记录缺失。"


func get_event_options(event_id: StringName = selected_event_id) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	match event_id:
		&"authorless_book":
			options.append(_option("照书中写的做", "失去 6 生命；牌组加入《预写结局》。"))
			options.append(_option("撕掉下一页", "获得 60 墨晶；牌组加入 1 张《删节》。"))
			options.append(_conditional_option(
				"写下另一个名字",
				"获得证据“异名索引”。",
				relics.has(&"wordless_bookplate"),
				"需要遗物“无字藏书票”"
			))
		&"seventh_dock":
			options.append(_option("检查返航名单", "恢复 8 生命；获得证据“九份涂名返航记录”。"))
			options.append(_option("敲响返航铃", "获得遗物“过期返航铃”；铃声记录只留下怀疑。"))
			options.append(_conditional_option(
				"盖上通行章",
				"获得证据“旧码头回收流程”。",
				relics.has(&"seventh_dock_stamp"),
				"需要遗物“第七码头通行章”"
			))
		&"calibration_station":
			options.append(_option("提交当前编号", "恢复 20 生命；下一场战斗初始获得 2 层律式缺名。"))
			options.append(_option("提交上一名回收者编号", "获得 80 墨晶；获得证据“遮蔽资产日志”。"))
			options.append(_option("拒绝校准", "最大生命减少 5；获得 1 张确定性随机罕见卡。"))
	return options


func apply_event_choice(choice_index: int, event_id: StringName = selected_event_id) -> bool:
	if event_resolved:
		return false
	var options: Array[Dictionary] = get_event_options(event_id)
	if choice_index < 0 or choice_index >= options.size() or not bool(options[choice_index][&"enabled"]):
		return false
	match event_id:
		&"authorless_book":
			match choice_index:
				0:
					player_hp = maxi(0, player_hp - 6)
					_add_deck_card(&"prewritten_ending", true)
					event_outcome = "你照着尚未发生的文字行动。生命 -6，获得《预写结局》。"
				1:
					ink_crystals += 60
					_add_deck_card(&"redaction", true)
					event_outcome = "下一页在手中变成墨晶。墨晶 +60，牌组加入《删节》。"
				2:
					_add_evidence("异名索引")
					event_outcome = "书页接受了另一个名字。获得证据“异名索引”。"
		&"seventh_dock":
			match choice_index:
				0:
					player_hp = mini(player_max_hp, player_hp + 8)
					_add_evidence("九份涂名返航记录")
					event_outcome = "名单没有给出答案，只留下九次相似的涂改。生命 +8，获得证据。"
				1:
					if not relics.has(&"expired_return_bell"):
						relics.append(&"expired_return_bell")
					_add_evidence("过期铃声记录")
					event_outcome = "本版序章事件后不再进入战斗，因此返航铃直接入库；获得遗物与疑点记录。"
				2:
					_add_evidence("旧码头回收流程")
					event_outcome = "旧档案显示两套流程高度相似，但不足以证明谁复制了谁。获得证据。"
		&"calibration_station":
			match choice_index:
				0:
					player_hp = mini(player_max_hp, player_hp + 20)
					next_battle_missing_name = 2
					_add_evidence("重复校准参数")
					event_outcome = "设备接受了编号。生命 +20；记录下场律式缺名 2，并获得重复参数疑点。"
				1:
					ink_crystals += 80
					_add_evidence("遮蔽资产日志")
					event_outcome = "两个编号返回相同权限。墨晶 +80，获得证据“遮蔽资产日志”。"
				2:
					player_max_hp = maxi(1, player_max_hp - 5)
					player_hp = mini(player_hp, player_max_hp)
					var rare_rng: RandomNumberGenerator = RandomNumberGenerator.new()
					rare_rng.seed = seed_value + 9013
					var rare_id: StringName = RARE_REWARD_IDS[rare_rng.randi_range(0, RARE_REWARD_IDS.size() - 1)]
					_add_deck_card(rare_id, true)
					event_outcome = "你拒绝让设备定义身体。最大生命 -5，获得《%s》。" % CardCatalog.get_definition(rare_id)[&"title"]
		_:
			return false
	event_resolved = true
	current_node = 8
	return true


func get_summary_text() -> String:
	return "固定种子 %d｜完成战斗 %d/6｜牌组 %d 张｜墨晶 %d｜证据 %d 条｜生命 %d/%d" % [
		seed_value,
		completed_battles.size(),
		deck_instances.size(),
		ink_crystals,
		evidence.size(),
		player_hp,
		player_max_hp,
	]


func _add_deck_card(card_id: StringName, acquired: bool) -> void:
	assert(CardCatalog.has_card(card_id), "牌组加入了未知卡牌：%s" % card_id)
	deck_instances.append({&"instance_id": next_deck_instance_id, &"card_id": card_id})
	next_deck_instance_id += 1
	if acquired:
		acquired_card_ids.append(card_id)


func _add_evidence(entry: String) -> void:
	if not evidence.has(entry):
		evidence.append(entry)


func _option(label: String, consequence: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": true, &"reason": ""}


func _conditional_option(label: String, consequence: String, enabled: bool, reason: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": enabled, &"reason": "" if enabled else reason}
