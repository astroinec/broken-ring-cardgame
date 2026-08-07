class_name RunModel
extends RefCounted


const DEFAULT_SEED: int = 73103
const SCHEMA_VERSION: int = 2
const REWARD_STAGES: Array[int] = [3, 5, 6]
const EVENT_IDS: Array[StringName] = [&"authorless_book", &"seventh_dock", &"calibration_station"]
const RARE_REWARD_IDS: Array[StringName] = [
	&"critical_permission", &"dissolution_protocol", &"prewritten_ending", &"unseal_order", &"homophone",
]
const STARTING_RELIC_IDS: Array[StringName] = [&"crack_stabilizer"]
const NORMAL_BATTLE_INCOME: int = 12
const ELITE_BATTLE_INCOME: int = 30

var schema_version: int = SCHEMA_VERSION
var seed_value: int = DEFAULT_SEED
var map_graph: MapGraph = null
var current_node_id: StringName = &""
var visited_node_ids: Array[StringName] = []
var available_node_ids: Array[StringName] = []

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

var shop_remove_count: int = 0
var pending_shop_stock: Dictionary = {}
var pending_node_resolution: Dictionary = {}
var last_action_error: String = ""


func start_run(p_seed: int = DEFAULT_SEED) -> void:
	schema_version = SCHEMA_VERSION
	seed_value = p_seed
	map_graph = MapGraph.new()
	map_graph.generate(seed_value)
	current_node_id = &""
	visited_node_ids.clear()
	available_node_ids = map_graph.start_node_ids.duplicate()
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
	shop_remove_count = 0
	pending_shop_stock.clear()
	pending_node_resolution.clear()
	last_action_error = ""
	for relic_id: StringName in STARTING_RELIC_IDS:
		relics.append(relic_id)
	for card_id: StringName in CardCatalog.STARTER_IDS:
		_add_deck_card(card_id, false)


func get_relic_ids() -> Array[StringName]:
	return relics.duplicate()


func get_deck_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for instance: Dictionary in deck_instances:
		ids.append(instance[&"card_id"] as StringName)
	return ids


func get_deck_instances() -> Array[Dictionary]:
	return deck_instances.duplicate(true)


func get_acquired_card_ids() -> Array[StringName]:
	return acquired_card_ids.duplicate()


func has_deck_instance(instance_id: int) -> bool:
	return _deck_index_for_instance(instance_id) >= 0


func get_deck_instance(instance_id: int) -> Dictionary:
	var index: int = _deck_index_for_instance(instance_id)
	return {} if index < 0 else deck_instances[index].duplicate(true)


func add_card_instance(card_id: StringName, upgrade_id: StringName = &"") -> int:
	return _add_deck_card(card_id, true, upgrade_id)


func remove_card_instance(instance_id: int) -> bool:
	var index: int = _deck_index_for_instance(instance_id)
	if index < 0:
		return false
	var removed_id: StringName = deck_instances[index][&"card_id"] as StringName
	deck_instances.remove_at(index)
	var acquired_index: int = acquired_card_ids.find(removed_id)
	if acquired_index >= 0:
		acquired_card_ids.remove_at(acquired_index)
	return true


func upgrade_card_instance(instance_id: int) -> bool:
	last_action_error = ""
	var index: int = _deck_index_for_instance(instance_id)
	if index < 0:
		last_action_error = "牌组实例不存在"
		return false
	var instance: Dictionary = deck_instances[index]
	if instance.get(&"upgrade_id", &"") != &"":
		last_action_error = "该实例已经升级"
		return false
	var card_id: StringName = instance[&"card_id"] as StringName
	var upgrade_id: StringName = CardUpgradeCatalog.get_default_upgrade_id(card_id)
	if upgrade_id == &"":
		last_action_error = "该卡牌没有M1升级"
		return false
	instance[&"upgrade_id"] = upgrade_id
	deck_instances[index] = instance
	return true


func get_unupgraded_instances() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance: Dictionary in deck_instances:
		if instance.get(&"upgrade_id", &"") == &"" and CardUpgradeCatalog.can_upgrade(instance[&"card_id"] as StringName):
			result.append(instance.duplicate(true))
	return result


func describe_deck_instance(instance: Dictionary) -> String:
	var card_id: StringName = instance[&"card_id"] as StringName
	var upgrade_id: StringName = instance.get(&"upgrade_id", &"") as StringName
	var card: CardData = CardCatalog.create_card(card_id, int(instance[&"instance_id"]), upgrade_id)
	return "#%d %s｜%s" % [int(instance[&"instance_id"]), card.title, card.description]


func get_upgrade_preview(instance_id: int) -> Dictionary:
	var instance: Dictionary = get_deck_instance(instance_id)
	if instance.is_empty():
		return {}
	var card_id: StringName = instance[&"card_id"] as StringName
	var before: Dictionary = CardCatalog.get_definition(card_id)
	var upgrade: Dictionary = CardUpgradeCatalog.get_default_upgrade(card_id)
	if upgrade.is_empty():
		return {}
	return {
		&"instance_id": instance_id,
		&"before": str(before[&"description"]),
		&"after": str(upgrade[&"description"]),
		&"upgrade_id": upgrade[&"id"],
	}


func enter_node(node_id: StringName) -> bool:
	last_action_error = ""
	if map_graph == null or not available_node_ids.has(node_id):
		last_action_error = "节点当前不可达"
		return false
	var node: MapNode = map_graph.get_node(node_id)
	if node == null or node.completed:
		last_action_error = "节点不存在或已经完成"
		return false
	if not pending_node_resolution.is_empty():
		last_action_error = "当前节点尚未完成"
		return false
	current_node_id = node_id
	current_node = node.depth
	if not visited_node_ids.has(node_id):
		visited_node_ids.append(node_id)
	available_node_ids.clear()
	for raw_node: Variant in map_graph.nodes_by_id.values():
		(raw_node as MapNode).reachable = false
	node.revealed = true
	pending_node_resolution = {
		&"node_id": node_id,
		&"resolved": false,
		&"reward_settled": false,
	}
	pending_reward_ids.clear()
	pending_shop_stock.clear()
	if node.node_type == MapNode.NodeType.EVENT:
		begin_event()
	elif node.node_type == MapNode.NodeType.SHOP:
		pending_shop_stock = ShopCatalog.generate(node.content_seed, shop_remove_count)
	return true


func complete_current_node() -> bool:
	last_action_error = ""
	if current_node_id == &"" or pending_node_resolution.is_empty():
		last_action_error = "没有待完成节点"
		return false
	if not bool(pending_node_resolution.get(&"resolved", false)):
		last_action_error = "节点规则尚未结算"
		return false
	var node: MapNode = map_graph.get_node(current_node_id)
	if node == null or node.completed:
		last_action_error = "节点已经完成"
		return false
	node.completed = true
	node.reachable = false
	available_node_ids.clear()
	for next_id: StringName in node.connections:
		var next: MapNode = map_graph.get_node(next_id)
		if next != null and not next.completed:
			next.revealed = true
			next.reachable = true
			available_node_ids.append(next_id)
	pending_node_resolution.clear()
	pending_reward_ids.clear()
	pending_shop_stock.clear()
	return true


func mark_current_node_resolved() -> bool:
	if pending_node_resolution.is_empty():
		return false
	pending_node_resolution[&"resolved"] = true
	return true


func get_current_map_node() -> MapNode:
	return null if map_graph == null else map_graph.get_node(current_node_id)


func record_current_battle_victory() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or (node.node_type != MapNode.NodeType.BATTLE and node.node_type != MapNode.NodeType.ELITE):
		return false
	if bool(pending_node_resolution.get(&"reward_settled", false)):
		return false
	ink_crystals += ELITE_BATTLE_INCOME if node.node_type == MapNode.NodeType.ELITE else NORMAL_BATTLE_INCOME
	pending_node_resolution[&"reward_settled"] = true
	pending_node_resolution[&"battle_won"] = true
	if not completed_battles.has(node.depth):
		completed_battles.append(node.depth)
	return true


func record_battle_victory(stage: int) -> void:
	var node: MapNode = get_current_map_node()
	if node != null and (node.node_type == MapNode.NodeType.BATTLE or node.node_type == MapNode.NodeType.ELITE):
		record_current_battle_victory()
		return
	if completed_battles.has(stage):
		return
	completed_battles.append(stage)
	current_node = stage
	ink_crystals += NORMAL_BATTLE_INCOME


func should_offer_reward(stage: int) -> bool:
	var node: MapNode = get_current_map_node()
	if node != null and (node.node_type == MapNode.NodeType.BATTLE or node.node_type == MapNode.NodeType.ELITE):
		return bool(pending_node_resolution.get(&"battle_won", false))
	return REWARD_STAGES.has(stage)


func generate_reward_choices(stage: int) -> Array[StringName]:
	if not pending_reward_ids.is_empty():
		return pending_reward_ids.duplicate()
	var reward_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var node: MapNode = get_current_map_node()
	var base_seed: int = node.content_seed if node != null else seed_value + stage * 1009
	reward_rng.seed = base_seed + reward_round * 7919
	var pool: Array[StringName] = _reward_pool_for_stage(stage)
	for draw_index: int in range(3):
		var pool_index: int = reward_rng.randi_range(0, pool.size() - 1)
		pending_reward_ids.append(pool[pool_index])
		pool.remove_at(pool_index)
	reward_round += 1
	return pending_reward_ids.duplicate()


func _reward_pool_for_stage(stage: int) -> Array[StringName]:
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
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true
	return true


func skip_reward() -> bool:
	if pending_reward_ids.is_empty():
		return false
	pending_reward_ids.clear()
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true
	return true


func buy_shop_card(stock_index: int) -> bool:
	var shop: ShopModel = ShopModel.new(pending_shop_stock)
	var success: bool = shop.buy_card(self, stock_index)
	pending_shop_stock = shop.stock
	last_action_error = shop.last_error
	return success


func buy_shop_relic() -> bool:
	var shop: ShopModel = ShopModel.new(pending_shop_stock)
	var success: bool = shop.buy_relic(self)
	pending_shop_stock = shop.stock
	last_action_error = shop.last_error
	return success


func use_shop_remove(instance_id: int) -> bool:
	var shop: ShopModel = ShopModel.new(pending_shop_stock)
	var success: bool = shop.remove_card(self, instance_id)
	pending_shop_stock = shop.stock
	last_action_error = shop.last_error
	return success


func finish_shop() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.SHOP:
		return false
	return mark_current_node_resolved()


func resolve_forge_upgrade(instance_id: int) -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.FORGE or bool(pending_node_resolution.get(&"resolved", false)):
		return false
	if not upgrade_card_instance(instance_id):
		return false
	return mark_current_node_resolved()


func skip_forge() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.FORGE:
		return false
	return mark_current_node_resolved()


func resolve_rest_heal() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.REST or bool(pending_node_resolution.get(&"resolved", false)):
		return false
	var amount: int = maxi(1, floori(float(player_max_hp) * 0.2))
	player_hp = mini(player_max_hp, player_hp + amount)
	return mark_current_node_resolved()


func resolve_rest_upgrade(instance_id: int) -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.REST or bool(pending_node_resolution.get(&"resolved", false)):
		return false
	if not upgrade_card_instance(instance_id):
		return false
	return mark_current_node_resolved()


func skip_rest() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.REST:
		return false
	return mark_current_node_resolved()


func acknowledge_boss_placeholder() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.BOSS:
		return false
	event_outcome = "章节终点尚未接入。M1不包含正式Boss逻辑。"
	return mark_current_node_resolved()


func begin_event() -> StringName:
	var node: MapNode = get_current_map_node()
	if node != null and node.node_type == MapNode.NodeType.EVENT:
		selected_event_id = node.event_id
	else:
		var event_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		event_rng.seed = seed_value + 6067
		selected_event_id = EVENT_IDS[event_rng.randi_range(0, EVENT_IDS.size() - 1)]
	event_resolved = false
	event_outcome = ""
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
			options.append(_conditional_option("写下另一个名字", "获得证据“异名索引”。", relics.has(&"wordless_bookplate"), "需要遗物“无字藏书票”"))
		&"seventh_dock":
			options.append(_option("检查返航名单", "恢复 8 生命；获得证据“九份涂名返航记录”。"))
			options.append(_option("敲响返航铃", "获得遗物“过期返航铃”；铃声记录只留下怀疑。"))
			options.append(_conditional_option("盖上通行章", "获得证据“旧码头回收流程”。", relics.has(&"seventh_dock_stamp"), "需要遗物“第七码头通行章”"))
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
					event_outcome = "返航铃进入档案。获得遗物与疑点记录。"
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
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true
	return true


func get_summary_text() -> String:
	return "固定种子 %d｜当前第%d层｜已完成节点 %d｜牌组 %d 张｜墨晶 %d｜证据 %d 条｜生命 %d/%d" % [
		seed_value, current_node, _completed_node_count(), deck_instances.size(), ink_crystals,
		evidence.size(), player_hp, player_max_hp,
	]


func _add_deck_card(card_id: StringName, acquired: bool, upgrade_id: StringName = &"") -> int:
	assert(CardCatalog.has_card(card_id), "牌组加入了未知卡牌：%s" % card_id)
	var instance_id: int = next_deck_instance_id
	deck_instances.append({&"instance_id": instance_id, &"card_id": card_id, &"upgrade_id": upgrade_id})
	next_deck_instance_id += 1
	if acquired:
		acquired_card_ids.append(card_id)
	return instance_id


func _deck_index_for_instance(instance_id: int) -> int:
	for index: int in range(deck_instances.size()):
		if int(deck_instances[index][&"instance_id"]) == instance_id:
			return index
	return -1


func _completed_node_count() -> int:
	if map_graph == null:
		return 0
	var count: int = 0
	for raw_node: Variant in map_graph.nodes_by_id.values():
		if (raw_node as MapNode).completed:
			count += 1
	return count


func _add_evidence(entry: String) -> void:
	if not evidence.has(entry):
		evidence.append(entry)


func _option(label: String, consequence: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": true, &"reason": ""}


func _conditional_option(label: String, consequence: String, enabled: bool, reason: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": enabled, &"reason": "" if enabled else reason}
