class_name RunModel
extends RefCounted


const DEFAULT_SEED: int = 73103
const SCHEMA_VERSION: int = 3
const REWARD_STAGES: Array[int] = [3, 5, 6]
const EVENT_IDS: Array[StringName] = [
	&"authorless_book", &"seventh_dock", &"calibration_station",
	&"speaking_for_you", &"deleted_funeral", &"definition_tax",
]
const EVENT_BATTLE_ENEMY_ID: StringName = &"reinforced_word_eater"
const RARE_REWARD_IDS: Array[StringName] = [
	&"critical_permission", &"dissolution_protocol", &"prewritten_ending", &"unseal_order", &"homophone",
]
const STARTING_RELIC_IDS: Array[StringName] = [&"crack_stabilizer"]
const NORMAL_BATTLE_INCOME: int = 12
const ELITE_BATTLE_INCOME: int = 30
const ELITE_RELIC_FALLBACK_INCOME: int = 50
const REST_SALVAGE_INCOME: int = 30
const MAX_SAVE_HP: int = 999
const MAX_SAVE_INK: int = 1_000_000
const MAX_SAVE_COUNTER: int = 1_000_000
const MAX_SAVE_INSTANCE_ID: int = 2_147_483_647
const SAVE_FIELDS: Array[String] = [
	"seed_value", "current_node_id", "visited_node_ids", "available_node_ids", "current_node",
	"player_hp", "player_max_hp", "ink_crystals", "deck_instances", "next_deck_instance_id",
	"acquired_card_ids", "relics", "evidence_records", "completed_node_ids", "revealed_node_ids",
	"reward_round", "shop_remove_count", "next_battle_missing_name",
	"next_battle_instability_threshold_delta", "next_battle_enemy_strength",
	"next_battle_initial_draw_bonus", "next_battle_reward_relic_id", "fracture_damage_override",
	"institution_relation", "event_history_hints_hidden", "event_history", "completed_battles",
	"boss_ending_id", "boss_ending_text", "run_completed",
]

var schema_version: int = SCHEMA_VERSION
var seed_value: int = DEFAULT_SEED
var map_graph: MapGraph = null
var current_node_id: StringName = &""
var visited_node_ids: Array[StringName] = []
var available_node_ids: Array[StringName] = []

var current_node: int = 0
var ink_crystals: int = 0
## 旧测试与存档兼容：继续保存证据标题。
var evidence: Array[String] = []
## 新档案协议：每条记录包含 id/title/source/description。
var evidence_records: Array[Dictionary] = []
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
var next_battle_instability_threshold_delta: int = 0
var next_battle_enemy_strength: int = 0
var next_battle_initial_draw_bonus: int = 0
var next_battle_reward_relic_id: StringName = &""
## 0 表示使用 CombatModel 默认值；定义税的“疼痛”令后续战斗持续使用 5。
var fracture_damage_override: int = 0
var institution_relation: int = 0
var event_history_hints_hidden: bool = false
var event_history: Array[String] = []
var pending_event_selection: Dictionary = {}
var event_battle_pending: bool = false
var event_battle_reward_settled: bool = false
var completed_battles: Array[int] = []
var boss_ending_id: StringName = &""
var boss_ending_text: String = ""
var run_completed: bool = false

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
	evidence_records.clear()
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
	next_battle_instability_threshold_delta = 0
	next_battle_enemy_strength = 0
	next_battle_initial_draw_bonus = 0
	next_battle_reward_relic_id = &""
	fracture_damage_override = 0
	institution_relation = 0
	event_history_hints_hidden = false
	event_history.clear()
	pending_event_selection.clear()
	event_battle_pending = false
	event_battle_reward_settled = false
	completed_battles.clear()
	boss_ending_id = &""
	boss_ending_text = ""
	run_completed = false
	shop_remove_count = 0
	pending_shop_stock.clear()
	pending_node_resolution.clear()
	last_action_error = ""
	for relic_id: StringName in STARTING_RELIC_IDS:
		relics.append(relic_id)
	for card_id: StringName in CardCatalog.STARTER_IDS:
		_add_deck_card(card_id, false)


func to_save_dict() -> Dictionary:
	var saved_deck: Array[Dictionary] = []
	for instance: Dictionary in deck_instances:
		saved_deck.append({
			"instance_id": int(instance[&"instance_id"]),
			"card_id": str(instance[&"card_id"]),
			"upgrade_id": str(instance.get(&"upgrade_id", &"")),
		})
	var saved_evidence: Array[Dictionary] = []
	for record: Dictionary in evidence_records:
		saved_evidence.append({
			"id": str(record[&"id"]),
			"title": str(record[&"title"]),
			"source": str(record[&"source"]),
			"description": str(record[&"description"]),
		})
	return {
		"seed_value": seed_value,
		"current_node_id": str(current_node_id),
		"visited_node_ids": _string_name_array_to_strings(visited_node_ids),
		"available_node_ids": _string_name_array_to_strings(available_node_ids),
		"current_node": current_node,
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"ink_crystals": ink_crystals,
		"deck_instances": saved_deck,
		"next_deck_instance_id": next_deck_instance_id,
		"acquired_card_ids": _string_name_array_to_strings(acquired_card_ids),
		"relics": _string_name_array_to_strings(relics),
		"evidence_records": saved_evidence,
		"completed_node_ids": _map_node_ids_with_state(&"completed"),
		"revealed_node_ids": _map_node_ids_with_state(&"revealed"),
		"reward_round": reward_round,
		"shop_remove_count": shop_remove_count,
		"next_battle_missing_name": next_battle_missing_name,
		"next_battle_instability_threshold_delta": next_battle_instability_threshold_delta,
		"next_battle_enemy_strength": next_battle_enemy_strength,
		"next_battle_initial_draw_bonus": next_battle_initial_draw_bonus,
		"next_battle_reward_relic_id": str(next_battle_reward_relic_id),
		"fracture_damage_override": fracture_damage_override,
		"institution_relation": institution_relation,
		"event_history_hints_hidden": event_history_hints_hidden,
		"event_history": event_history.duplicate(),
		"completed_battles": completed_battles.duplicate(),
		"boss_ending_id": str(boss_ending_id),
		"boss_ending_text": boss_ending_text,
		"run_completed": run_completed,
	}


## 返回空字符串表示成功。所有校验均在候选模型上完成，失败不会修改当前实例。
func load_from_save_dict(data: Dictionary) -> String:
	for field: String in SAVE_FIELDS:
		if not data.has(field):
			return "存档缺少字段：%s" % field
	var integer_ranges: Dictionary = {
		"seed_value": Vector2i(0, MAX_SAVE_INSTANCE_ID),
		"current_node": Vector2i(0, 9),
		"player_hp": Vector2i(0, MAX_SAVE_HP),
		"player_max_hp": Vector2i(1, MAX_SAVE_HP),
		"ink_crystals": Vector2i(0, MAX_SAVE_INK),
		"next_deck_instance_id": Vector2i(1, MAX_SAVE_INSTANCE_ID),
		"reward_round": Vector2i(0, MAX_SAVE_COUNTER),
		"shop_remove_count": Vector2i(0, MAX_SAVE_COUNTER),
		"next_battle_missing_name": Vector2i(0, 100),
		"next_battle_instability_threshold_delta": Vector2i(-100, 100),
		"next_battle_enemy_strength": Vector2i(-100, 100),
		"next_battle_initial_draw_bonus": Vector2i(0, 100),
		"fracture_damage_override": Vector2i(0, 100),
		"institution_relation": Vector2i(-100, 100),
	}
	for raw_field: Variant in integer_ranges.keys():
		var field: String = str(raw_field)
		var bounds: Vector2i = integer_ranges[field]
		if not _is_json_integer(data[field]):
			return "存档字段%s必须是整数" % field
		var value: int = int(data[field])
		if value < bounds.x or value > bounds.y:
			return "存档字段%s超出范围" % field
	if int(data["player_hp"]) > int(data["player_max_hp"]):
		return "当前生命不能大于最大生命"
	for field: String in ["current_node_id", "next_battle_reward_relic_id", "boss_ending_id", "boss_ending_text"]:
		if typeof(data[field]) != TYPE_STRING:
			return "存档字段%s必须是字符串" % field
	for field: String in ["event_history_hints_hidden", "run_completed"]:
		if typeof(data[field]) != TYPE_BOOL:
			return "存档字段%s必须是布尔值" % field
	for field: String in [
		"visited_node_ids", "available_node_ids", "deck_instances", "acquired_card_ids", "relics",
		"evidence_records", "completed_node_ids", "revealed_node_ids", "event_history", "completed_battles",
	]:
		if typeof(data[field]) != TYPE_ARRAY:
			return "存档字段%s必须是数组" % field

	var candidate: RunModel = RunModel.new()
	candidate.start_run(int(data["seed_value"]))
	var graph_errors: Array[String] = candidate.map_graph.validate()
	if not graph_errors.is_empty():
		return "地图校验失败：%s" % "; ".join(graph_errors)

	var parsed_node_arrays: Dictionary = {}
	for field: String in ["visited_node_ids", "available_node_ids", "completed_node_ids", "revealed_node_ids"]:
		var parsed_ids: Array[StringName] = []
		var seen_ids: Dictionary = {}
		for raw_id: Variant in data[field]:
			if typeof(raw_id) != TYPE_STRING or str(raw_id).is_empty():
				return "%s包含无效节点ID" % field
			var node_id: StringName = StringName(str(raw_id))
			if candidate.map_graph.get_node(node_id) == null:
				return "%s包含未知节点：%s" % [field, node_id]
			if seen_ids.has(node_id):
				return "%s包含重复节点：%s" % [field, node_id]
			seen_ids[node_id] = true
			parsed_ids.append(node_id)
		parsed_node_arrays[field] = parsed_ids

	var parsed_deck: Array[Dictionary] = []
	var instance_ids: Dictionary = {}
	var max_instance_id: int = 0
	for raw_instance: Variant in data["deck_instances"]:
		if typeof(raw_instance) != TYPE_DICTIONARY:
			return "牌组实例必须是对象"
		var instance: Dictionary = raw_instance as Dictionary
		for field: String in ["instance_id", "card_id", "upgrade_id"]:
			if not instance.has(field):
				return "牌组实例缺少字段：%s" % field
		if not _is_json_integer(instance["instance_id"]):
			return "牌组实例ID必须是整数"
		var instance_id: int = int(instance["instance_id"])
		if instance_id < 1 or instance_id > MAX_SAVE_INSTANCE_ID:
			return "牌组实例ID超出范围"
		if instance_ids.has(instance_id):
			return "牌组存在重复实例ID：%d" % instance_id
		if typeof(instance["card_id"]) != TYPE_STRING or typeof(instance["upgrade_id"]) != TYPE_STRING:
			return "牌组card_id/upgrade_id必须是字符串"
		var card_id: StringName = StringName(str(instance["card_id"]))
		var upgrade_id: StringName = StringName(str(instance["upgrade_id"]))
		if not CardCatalog.has_card(card_id):
			return "牌组包含未知卡牌：%s" % card_id
		if upgrade_id != &"" and CardUpgradeCatalog.get_upgrade(card_id, upgrade_id).is_empty():
			return "牌组包含未知升级：%s/%s" % [card_id, upgrade_id]
		instance_ids[instance_id] = true
		max_instance_id = maxi(max_instance_id, instance_id)
		parsed_deck.append({&"instance_id": instance_id, &"card_id": card_id, &"upgrade_id": upgrade_id})
	if int(data["next_deck_instance_id"]) <= max_instance_id:
		return "next_deck_instance_id必须大于所有已有实例ID"

	var parsed_acquired: Array[StringName] = []
	for raw_card_id: Variant in data["acquired_card_ids"]:
		if typeof(raw_card_id) != TYPE_STRING:
			return "acquired_card_ids包含非字符串"
		var card_id: StringName = StringName(str(raw_card_id))
		if not CardCatalog.has_card(card_id):
			return "acquired_card_ids包含未知卡牌：%s" % card_id
		parsed_acquired.append(card_id)

	var parsed_relics: Array[StringName] = []
	var seen_relics: Dictionary = {}
	for raw_relic_id: Variant in data["relics"]:
		if typeof(raw_relic_id) != TYPE_STRING:
			return "relics包含非字符串"
		var relic_id: StringName = StringName(str(raw_relic_id))
		if not RelicCatalog.has_relic(relic_id):
			return "存档包含未知遗物：%s" % relic_id
		if seen_relics.has(relic_id):
			return "存档包含重复遗物：%s" % relic_id
		seen_relics[relic_id] = true
		parsed_relics.append(relic_id)
	var reward_relic_id: StringName = StringName(str(data["next_battle_reward_relic_id"]))
	if reward_relic_id != &"" and not RelicCatalog.has_relic(reward_relic_id):
		return "下一战奖励包含未知遗物：%s" % reward_relic_id

	var parsed_evidence: Array[Dictionary] = []
	var evidence_ids: Dictionary = {}
	for raw_record: Variant in data["evidence_records"]:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return "evidence_records条目必须是对象"
		var record: Dictionary = raw_record as Dictionary
		for field: String in ["id", "title", "source", "description"]:
			if not record.has(field) or typeof(record[field]) != TYPE_STRING:
				return "证据记录字段%s缺失或类型错误" % field
		var evidence_id: StringName = StringName(str(record["id"]))
		if not EvidenceCatalog.has_evidence(evidence_id):
			return "存档包含未知证据：%s" % evidence_id
		if evidence_ids.has(evidence_id):
			return "存档包含重复证据：%s" % evidence_id
		evidence_ids[evidence_id] = true
		parsed_evidence.append(EvidenceCatalog.get_record(evidence_id))

	var parsed_history: Array[String] = []
	for raw_entry: Variant in data["event_history"]:
		if typeof(raw_entry) != TYPE_STRING:
			return "event_history包含非字符串"
		parsed_history.append(str(raw_entry))
	var parsed_battles: Array[int] = []
	var battle_depths: Dictionary = {}
	for raw_depth: Variant in data["completed_battles"]:
		if not _is_json_integer(raw_depth):
			return "completed_battles包含非整数"
		var depth: int = int(raw_depth)
		if depth < 1 or depth > 9 or battle_depths.has(depth):
			return "completed_battles包含无效或重复层级"
		battle_depths[depth] = true
		parsed_battles.append(depth)

	var completed_ids: Array[StringName] = parsed_node_arrays["completed_node_ids"]
	var revealed_ids: Array[StringName] = parsed_node_arrays["revealed_node_ids"]
	var visited_ids: Array[StringName] = parsed_node_arrays["visited_node_ids"]
	var available_ids: Array[StringName] = parsed_node_arrays["available_node_ids"]
	for raw_node: Variant in candidate.map_graph.nodes_by_id.values():
		var map_node: MapNode = raw_node as MapNode
		map_node.completed = completed_ids.has(map_node.id)
		map_node.revealed = revealed_ids.has(map_node.id)
		map_node.reachable = available_ids.has(map_node.id)
	for node_id: StringName in completed_ids:
		if not revealed_ids.has(node_id) or not visited_ids.has(node_id):
			return "已完成节点必须同时已访问且已揭示：%s" % node_id
	for node_id: StringName in visited_ids:
		if not completed_ids.has(node_id):
			return "检查点不能包含未完成的已访问节点：%s" % node_id
	for node_id: StringName in available_ids:
		if completed_ids.has(node_id) or not revealed_ids.has(node_id):
			return "可达节点状态不一致：%s" % node_id

	var loaded_current_id: StringName = StringName(str(data["current_node_id"]))
	var expected_available: Array[StringName] = []
	if loaded_current_id == &"":
		if int(data["current_node"]) != 0 or not completed_ids.is_empty() or not visited_ids.is_empty():
			return "空当前位置只允许用于新远征检查点"
		expected_available = candidate.map_graph.start_node_ids.duplicate()
	else:
		var current_map_node: MapNode = candidate.map_graph.get_node(loaded_current_id)
		if current_map_node == null:
			return "current_node_id包含未知节点：%s" % loaded_current_id
		if not current_map_node.completed or not visited_ids.has(loaded_current_id):
			return "当前位置必须是已完整结算的节点"
		if int(data["current_node"]) != current_map_node.depth:
			return "current_node与节点层级不一致"
		for next_id: StringName in current_map_node.connections:
			if not completed_ids.has(next_id):
				expected_available.append(next_id)
	if not _same_string_name_set(available_ids, expected_available):
		return "available_node_ids与地图推进状态不一致"

	var ending_id: StringName = StringName(str(data["boss_ending_id"]))
	if ending_id != &"" and ending_id != &"deliver_seal" and ending_id != &"read_original":
		return "存档包含未知Boss结局：%s" % ending_id
	if bool(data["run_completed"]):
		if ending_id == &"" or str(data["boss_ending_text"]).is_empty() or not completed_ids.has(candidate.map_graph.boss_node_id):
			return "已完成远征缺少合法Boss结算"
	elif ending_id != &"" or not str(data["boss_ending_text"]).is_empty():
		return "未完成远征不应包含Boss结算"

	candidate.current_node_id = loaded_current_id
	candidate.visited_node_ids = visited_ids
	candidate.available_node_ids = available_ids
	candidate.current_node = int(data["current_node"])
	candidate.player_hp = int(data["player_hp"])
	candidate.player_max_hp = int(data["player_max_hp"])
	candidate.ink_crystals = int(data["ink_crystals"])
	candidate.deck_instances = parsed_deck
	candidate.next_deck_instance_id = int(data["next_deck_instance_id"])
	candidate.acquired_card_ids = parsed_acquired
	candidate.relics = parsed_relics
	candidate.evidence_records = parsed_evidence
	candidate.evidence.clear()
	for record: Dictionary in candidate.evidence_records:
		candidate.evidence.append(str(record[&"title"]))
	candidate.reward_round = int(data["reward_round"])
	candidate.shop_remove_count = int(data["shop_remove_count"])
	candidate.next_battle_missing_name = int(data["next_battle_missing_name"])
	candidate.next_battle_instability_threshold_delta = int(data["next_battle_instability_threshold_delta"])
	candidate.next_battle_enemy_strength = int(data["next_battle_enemy_strength"])
	candidate.next_battle_initial_draw_bonus = int(data["next_battle_initial_draw_bonus"])
	candidate.next_battle_reward_relic_id = reward_relic_id
	candidate.fracture_damage_override = int(data["fracture_damage_override"])
	candidate.institution_relation = int(data["institution_relation"])
	candidate.event_history_hints_hidden = bool(data["event_history_hints_hidden"])
	candidate.event_history = parsed_history
	candidate.completed_battles = parsed_battles
	candidate.boss_ending_id = ending_id
	candidate.boss_ending_text = str(data["boss_ending_text"])
	candidate.run_completed = bool(data["run_completed"])
	candidate._clear_pending_state_after_load()
	graph_errors = candidate.map_graph.validate()
	if not graph_errors.is_empty():
		return "地图校验失败：%s" % "; ".join(graph_errors)
	_apply_loaded_candidate(candidate)
	return ""


func _apply_loaded_candidate(candidate: RunModel) -> void:
	schema_version = SCHEMA_VERSION
	seed_value = candidate.seed_value
	map_graph = candidate.map_graph
	current_node_id = candidate.current_node_id
	visited_node_ids = candidate.visited_node_ids.duplicate()
	available_node_ids = candidate.available_node_ids.duplicate()
	current_node = candidate.current_node
	ink_crystals = candidate.ink_crystals
	evidence = candidate.evidence.duplicate()
	evidence_records = candidate.evidence_records.duplicate(true)
	relics = candidate.relics.duplicate()
	deck_instances = candidate.deck_instances.duplicate(true)
	acquired_card_ids = candidate.acquired_card_ids.duplicate()
	next_deck_instance_id = candidate.next_deck_instance_id
	reward_round = candidate.reward_round
	player_max_hp = candidate.player_max_hp
	player_hp = candidate.player_hp
	next_battle_missing_name = candidate.next_battle_missing_name
	next_battle_instability_threshold_delta = candidate.next_battle_instability_threshold_delta
	next_battle_enemy_strength = candidate.next_battle_enemy_strength
	next_battle_initial_draw_bonus = candidate.next_battle_initial_draw_bonus
	next_battle_reward_relic_id = candidate.next_battle_reward_relic_id
	fracture_damage_override = candidate.fracture_damage_override
	institution_relation = candidate.institution_relation
	event_history_hints_hidden = candidate.event_history_hints_hidden
	event_history = candidate.event_history.duplicate()
	completed_battles = candidate.completed_battles.duplicate()
	boss_ending_id = candidate.boss_ending_id
	boss_ending_text = candidate.boss_ending_text
	run_completed = candidate.run_completed
	shop_remove_count = candidate.shop_remove_count
	_clear_pending_state_after_load()


func _clear_pending_state_after_load() -> void:
	pending_reward_ids.clear()
	selected_event_id = &""
	event_resolved = false
	event_outcome = ""
	pending_event_selection.clear()
	event_battle_pending = false
	event_battle_reward_settled = false
	pending_shop_stock.clear()
	pending_node_resolution.clear()
	last_action_error = ""


func _map_node_ids_with_state(state: StringName) -> Array[String]:
	var result: Array[String] = []
	if map_graph == null:
		return result
	for depth: int in range(1, 10):
		for node: MapNode in map_graph.get_nodes_at_depth(depth):
			if (state == &"completed" and node.completed) or (state == &"revealed" and node.revealed):
				result.append(str(node.id))
	return result


static func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(str(value))
	return result


static func _is_json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var float_value: float = float(value)
	return is_finite(float_value) and float_value == floor(float_value)


static func _same_string_name_set(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for value: StringName in first:
		if not second.has(value):
			return false
	return true


func get_relic_ids() -> Array[StringName]:
	return relics.duplicate()


func get_evidence_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for record: Dictionary in evidence_records:
		ids.append(record[&"id"] as StringName)
	return ids


func has_evidence_id(evidence_id: StringName) -> bool:
	for record: Dictionary in evidence_records:
		if record[&"id"] == evidence_id:
			return true
	return false


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
		pending_shop_stock = ShopCatalog.generate(node.content_seed, shop_remove_count, relics)
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
	if (
		node.node_type == MapNode.NodeType.ELITE
		and bool(pending_node_resolution.get(&"battle_won", false))
		and not bool(pending_node_resolution.get(&"elite_reward_claimed", false))
	):
		last_action_error = "精英遗物必须在选择或跳过卡牌后结算"
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


## 第一次启动当前节点战斗时消费“一场”修正；失败重试复用同一上下文。
func consume_current_battle_context() -> Dictionary:
	if pending_node_resolution.has(&"battle_context"):
		return (pending_node_resolution[&"battle_context"] as Dictionary).duplicate(true)
	var context: Dictionary = {
		&"instability_threshold_delta": next_battle_instability_threshold_delta,
		&"fracture_damage_override": fracture_damage_override,
		&"initial_missing_name_law": next_battle_missing_name,
		&"enemy_strength": next_battle_enemy_strength,
		&"initial_draw_bonus": next_battle_initial_draw_bonus,
		&"evidence_ids": get_evidence_ids(),
	}
	next_battle_instability_threshold_delta = 0
	next_battle_missing_name = 0
	next_battle_enemy_strength = 0
	next_battle_initial_draw_bonus = 0
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"battle_context"] = context.duplicate(true)
	return context


func is_event_battle_pending() -> bool:
	return event_battle_pending and selected_event_id == &"definition_tax" and not event_resolved


func get_event_battle_enemy_id() -> StringName:
	return EVENT_BATTLE_ENEMY_ID if is_event_battle_pending() else &""


func record_event_battle_victory() -> bool:
	if not is_event_battle_pending() or event_battle_reward_settled:
		return false
	event_battle_reward_settled = true
	event_battle_pending = false
	_settle_next_battle_relic_reward()
	if not relics.has(&"wordless_bookplate"):
		relics.append(&"wordless_bookplate")
	event_outcome = "你拒绝交出定义。强化拾字虫独自承担了原本属于两只敌人的压力；胜利后获得遗物“无字藏书票”。"
	_finish_event()
	return true


func record_current_battle_victory() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or (node.node_type != MapNode.NodeType.BATTLE and node.node_type != MapNode.NodeType.ELITE):
		return false
	if bool(pending_node_resolution.get(&"reward_settled", false)):
		return false
	ink_crystals += ELITE_BATTLE_INCOME if node.node_type == MapNode.NodeType.ELITE else NORMAL_BATTLE_INCOME
	_settle_next_battle_relic_reward()
	if node.node_type == MapNode.NodeType.ELITE:
		_prepare_elite_relic_reward(node.content_seed)
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
	var elite_reward: bool = node != null and node.node_type == MapNode.NodeType.ELITE
	if elite_reward:
		var rare_pool: Array[StringName] = []
		for card_id: StringName in pool:
			if str(CardCatalog.get_definition(card_id).get(&"rarity", "")) == "罕见":
				rare_pool.append(card_id)
		if not rare_pool.is_empty():
			var rare_id: StringName = rare_pool[reward_rng.randi_range(0, rare_pool.size() - 1)]
			pending_reward_ids.append(rare_id)
			pool.erase(rare_id)
	while pending_reward_ids.size() < 3 and not pool.is_empty():
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
	_settle_pending_elite_reward()
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true
	return true


func skip_reward() -> bool:
	if pending_reward_ids.is_empty():
		return false
	pending_reward_ids.clear()
	_settle_pending_elite_reward()
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true
	return true


func get_pending_elite_reward() -> Dictionary:
	if pending_node_resolution.is_empty():
		return {}
	var relic_id: StringName = pending_node_resolution.get(&"pending_elite_relic_id", &"") as StringName
	var fallback_ink: int = int(pending_node_resolution.get(&"pending_elite_fallback_ink", 0))
	if relic_id != &"":
		return {&"kind": &"relic", &"relic_id": relic_id, &"definition": RelicCatalog.get_definition(relic_id)}
	if fallback_ink > 0:
		return {&"kind": &"ink", &"amount": fallback_ink}
	return {}


func can_view_shop_archive() -> bool:
	var node: MapNode = get_current_map_node()
	return (
		node != null
		and node.node_type == MapNode.NodeType.SHOP
		and relics.has(&"seventh_dock_stamp")
		and not pending_shop_stock.is_empty()
	)


func get_shop_archive_record() -> Dictionary:
	if not can_view_shop_archive():
		return {}
	return {
		&"title": "第七码头旧档案",
		&"source": "第七码头通行章 / 商店隐藏抽屉",
		&"description": "档案显示，终末机构的回收者登记、残骸编号与返航注销流程，逐栏复制自数百年前的旧码头。‘自愿’一词使用另一种墨水统一补录。",
	}


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


func resolve_rest_salvage() -> bool:
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.REST or bool(pending_node_resolution.get(&"resolved", false)):
		return false
	ink_crystals += REST_SALVAGE_INCOME
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


func record_boss_outcome(choice_id: StringName, recovery_count: int) -> bool:
	last_action_error = ""
	var node: MapNode = get_current_map_node()
	if node == null or node.node_type != MapNode.NodeType.BOSS:
		last_action_error = "当前节点不是Boss战"
		return false
	if bool(pending_node_resolution.get(&"resolved", false)) or run_completed:
		last_action_error = "Boss结局已经记录"
		return false
	if choice_id != &"deliver_seal" and choice_id != &"read_original":
		last_action_error = "未知Boss终结选项"
		return false
	if choice_id == &"read_original" and recovery_count < CombatModel.BOSS_RECOVERY_REQUIRED:
		last_action_error = "读取被删原文需要至少两次恢复"
		return false
	boss_ending_id = choice_id
	run_completed = true
	pending_node_resolution[&"boss_choice"] = choice_id
	pending_node_resolution[&"boss_recoveries"] = recovery_count
	if choice_id == &"read_original":
		_add_evidence(&"tenth_calibration_record")
		boss_ending_text = "你没有立即交出律印，而是读取了被删原文。九种互相冲突的文明答案都写在 REC-10 名下。\n\n弥拉低声说：‘第十种答案，欢迎返航。’她停顿片刻，又改口：‘第七名回收者。’"
		if has_evidence_id(&"nine_redacted_return_records"):
			boss_ending_text += "\n\n返航名单上九次相同的涂改终于可以回溯：那不是九名士兵，而是同一实验被注销的九个版本。"
		if has_evidence_id(&"nonexistent_autopsy"):
			boss_ending_text += "\n\n那份未发生的尸检也有了解释：所谓伤口其实是版本之间共用的制造接口。"
	else:
		boss_ending_text = "你按终末机构命令交付定义律印。无字之城暂时停止坍缩，REC-10 档案在返航前重新封闭。"
	event_outcome = boss_ending_text
	return mark_current_node_resolved()


func get_boss_ending_title() -> String:
	if boss_ending_id == &"read_original":
		return "被删原文"
	if boss_ending_id == &"deliver_seal":
		return "定义律印已交付"
	return "远征尚未结算"


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
	pending_event_selection.clear()
	event_battle_pending = false
	event_battle_reward_settled = false
	return selected_event_id


func get_event_title(event_id: StringName = selected_event_id) -> String:
	match event_id:
		&"authorless_book":
			return "没有作者的书"
		&"seventh_dock":
			return "第七码头"
		&"calibration_station":
			return "校准站"
		&"speaking_for_you":
			return "替你说话的人"
		&"deleted_funeral":
			return "被删除的葬礼"
		&"definition_tax":
			return "定义税"
	return "未知事件"


func get_event_story(event_id: StringName = selected_event_id) -> String:
	match event_id:
		&"authorless_book":
			return "一本没有作者的书正逐字记录你的动作。下一行已经写出你将选择的选项，页脚却先一步把你称作 REC-10。这个编号尚未由任何人向你公开。"
		&"seventh_dock":
			return "残骸深处立着一座与终末机构完全相同的码头，但石材年代早了数百年。返航名单上，九个同姓记录被墨迹涂去。"
		&"calibration_station":
			return "仍在运行的终末机构设备要求你提交身体编号。屏幕显示：当前编号与上一名回收者拥有相同权限和校准参数，资产标识被遮蔽。"
		&"speaking_for_you":
			return "无名同盟成员隔着墙复述你尚未说出口的话。声音并不来自墙后，而像从你的骨骼里折返。"
		&"deleted_funeral":
			return "一群没有面孔的人正在为你举行葬礼。墓碑日期是明天，碑面留着一块等待姓名的空白。"
		&"definition_tax":
			return "无字之城的收税者要求你交出一个仍属于自己的词。拒绝并不会召来第二只怪物：当前单敌人规则只能诚实地让一只强化拾字虫承担事件战。"
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
			options.append(_option("敲响返航铃", "下一场战斗敌人力量 +2；胜利后获得遗物“过期返航铃”。"))
			options.append(_conditional_option("盖上通行章", "获得证据“旧码头回收流程”。", relics.has(&"seventh_dock_stamp"), "需要遗物“第七码头通行章”"))
		&"calibration_station":
			options.append(_option("提交当前编号", "恢复 20 生命；下一场战斗初始获得 2 层律式缺名。"))
			options.append(_option("提交上一名回收者编号", "获得 80 墨晶；获得证据“遮蔽资产日志”。"))
			options.append(_option("拒绝校准", "最大生命减少 5；获得 1 张确定性随机罕见卡。"))
		&"speaking_for_you":
			options.append(_option("继续对话", "固定种子升级 1 个具体未升级实例；下一场战斗不稳定阈值 -1。"))
			options.append(_option("攻击墙后的人", "获得遗物“复读舌骨”；失去 8 生命。"))
			options.append(_option("保持沉默", "进入实例选择；移除 1 张基础《校准击》或《临时护式》。"))
		&"deleted_funeral":
			options.append(_option("参加自己的葬礼", "最大生命 +5；牌组加入 1 张《旧伤》。"))
			options.append(_option("擦去墓碑", "进入实例选择；移除 1 张牌并失去 10 当前生命。"))
			options.append(_conditional_option("询问死因", "获得证据“未发生的尸检”。", relics.has(&"blank_epitaph"), "需要遗物“空白墓志铭”"))
		&"definition_tax":
			options.append(_option("交出“疼痛”", "最大生命 -4；本次远征后续裂解伤害 8 → 5。"))
			options.append(_option("交出“记忆”", "获得 120 墨晶；隐藏事件历史提示，但保留全部证据。"))
			options.append(_option("交出“服从”", "固定种子获得 1 张罕见卡；终末机构关系 -1。"))
			options.append(_option("拒绝定义", "进入强化拾字虫单敌人事件战；胜利获得“无字藏书票”。"))
	return options


func apply_event_choice(choice_index: int, event_id: StringName = selected_event_id) -> bool:
	if event_resolved or not pending_event_selection.is_empty() or event_battle_pending:
		return false
	var options: Array[Dictionary] = get_event_options(event_id)
	if choice_index < 0 or choice_index >= options.size() or not bool(options[choice_index][&"enabled"]):
		return false
	selected_event_id = event_id
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
					_add_evidence(&"alternate_name_index")
					next_battle_initial_draw_bonus += 2
					event_outcome = "书页接受了另一个名字。获得证据“异名索引”；下一场战斗初始多抽 2 张。"
		&"seventh_dock":
			match choice_index:
				0:
					player_hp = mini(player_max_hp, player_hp + 8)
					_add_evidence(&"nine_redacted_return_records")
					event_outcome = "名单没有给出答案，只留下九次相似的涂改。生命 +8，获得证据。"
				1:
					next_battle_enemy_strength += 2
					next_battle_reward_relic_id = &"expired_return_bell"
					event_outcome = "返航铃惊醒了下一名敌人：下场敌人力量 +2，胜利后才获得“过期返航铃”。"
				2:
					_add_evidence(&"old_dock_recovery_process")
					event_outcome = "旧档案显示两套流程高度相似，但不足以证明谁复制了谁。获得证据。"
		&"calibration_station":
			match choice_index:
				0:
					player_hp = mini(player_max_hp, player_hp + 20)
					next_battle_missing_name = 2
					_add_evidence(&"repeated_calibration_parameters")
					event_outcome = "设备接受了编号。生命 +20；记录下场律式缺名 2，并获得重复参数疑点。"
				1:
					ink_crystals += 80
					_add_evidence(&"obscured_asset_log")
					event_outcome = "两个编号返回相同权限。墨晶 +80，获得证据“遮蔽资产日志”。"
				2:
					player_max_hp = maxi(1, player_max_hp - 5)
					player_hp = mini(player_hp, player_max_hp)
					var rare_id: StringName = _deterministic_rare_card(9013)
					_add_deck_card(rare_id, true)
					event_outcome = "你拒绝让设备定义身体。最大生命 -5，获得《%s》。" % CardCatalog.get_definition(rare_id)[&"title"]
		&"speaking_for_you":
			match choice_index:
				0:
					var candidates: Array[Dictionary] = get_unupgraded_instances()
					if candidates.is_empty():
						return false
					var upgrade_rng: RandomNumberGenerator = RandomNumberGenerator.new()
					upgrade_rng.seed = seed_value + 12017
					var chosen: Dictionary = candidates[upgrade_rng.randi_range(0, candidates.size() - 1)]
					var instance_id: int = int(chosen[&"instance_id"])
					if not upgrade_card_instance(instance_id):
						return false
					next_battle_instability_threshold_delta -= 1
					event_outcome = "墙后的声音替你完成一句话。升级实例 #%d《%s》；下一场不稳定阈值 -1。" % [instance_id, CardCatalog.get_definition(chosen[&"card_id"] as StringName)[&"title"]]
				1:
					player_hp = maxi(0, player_hp - 8)
					if not relics.has(&"echo_hyoid"):
						relics.append(&"echo_hyoid")
					event_outcome = "墙体碎裂，里面只有与你共振的骨骼。生命 -8，获得遗物“复读舌骨”。"
				2:
					_begin_event_selection(&"remove_basic", "选择 1 个基础攻击或防御实例移除。", _basic_removal_candidates())
					return true
		&"deleted_funeral":
			match choice_index:
				0:
					player_max_hp += 5
					_add_deck_card(&"old_wound", true)
					event_outcome = "你参加了自己的葬礼。最大生命 +5，牌组加入《旧伤》。"
				1:
					_begin_event_selection(&"remove_any_lose_hp", "选择 1 个具体牌组实例移除；确认后失去 10 当前生命。", get_deck_instances())
					return true
				2:
					_add_evidence(&"nonexistent_autopsy")
					event_outcome = "尸检没有描述伤口，只列出回收者制造接口。获得证据“未发生的尸检”。"
		&"definition_tax":
			match choice_index:
				0:
					player_max_hp = maxi(1, player_max_hp - 4)
					player_hp = mini(player_hp, player_max_hp)
					fracture_damage_override = 5
					event_outcome = "你交出“疼痛”。最大生命 -4；从此直到本次远征结束，后续每场裂解伤害固定为 5。"
				1:
					ink_crystals += 120
					event_history_hints_hidden = true
					event_outcome = "你交出“记忆”。墨晶 +120；事件历史提示已隐藏，但证据记录完整保留。"
				2:
					var rare_id: StringName = _deterministic_rare_card(14033)
					_add_deck_card(rare_id, true)
					institution_relation -= 1
					event_outcome = "你交出“服从”。获得《%s》；终末机构关系 -1。" % CardCatalog.get_definition(rare_id)[&"title"]
				3:
					event_battle_pending = true
					event_battle_reward_settled = false
					event_outcome = "收税者退入文字背后。一只强化拾字虫进入单敌人事件战。"
					return true
		_:
			return false
	_finish_event()
	return true


func get_pending_event_selection() -> Dictionary:
	return pending_event_selection.duplicate(true)


func get_pending_event_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_candidate: Variant in pending_event_selection.get(&"candidates", []):
		result.append((raw_candidate as Dictionary).duplicate(true))
	return result


func resolve_event_selection(instance_id: int) -> bool:
	if pending_event_selection.is_empty() or event_resolved:
		return false
	var candidate_found: bool = false
	for candidate: Dictionary in get_pending_event_candidates():
		if int(candidate[&"instance_id"]) == instance_id:
			candidate_found = true
			break
	if not candidate_found or not remove_card_instance(instance_id):
		return false
	var kind: StringName = pending_event_selection[&"kind"] as StringName
	pending_event_selection.clear()
	if kind == &"remove_basic":
		event_outcome = "你保持沉默，墙后也停止复述。已移除基础牌实例 #%d。" % instance_id
	elif kind == &"remove_any_lose_hp":
		player_hp = maxi(0, player_hp - 10)
		event_outcome = "墓碑上的字连同牌组实例 #%d 一起消失。当前生命 -10。" % instance_id
	else:
		return false
	_finish_event()
	return true


func cancel_event_selection() -> bool:
	if pending_event_selection.is_empty() or event_resolved:
		return false
	pending_event_selection.clear()
	event_outcome = ""
	return true


func get_summary_text() -> String:
	var summary: String = "固定种子 %d｜当前第%d层｜已完成节点 %d｜牌组 %d 张｜墨晶 %d｜证据 %d 条｜生命 %d/%d" % [
		seed_value, current_node, _completed_node_count(), deck_instances.size(), ink_crystals,
		evidence.size(), player_hp, player_max_hp,
	]
	if run_completed:
		summary += "｜结局：%s" % get_boss_ending_title()
	return summary


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


func _add_evidence(evidence_id: StringName) -> void:
	if has_evidence_id(evidence_id):
		return
	var record: Dictionary = EvidenceCatalog.get_record(evidence_id)
	evidence_records.append(record)
	var title: String = str(record[&"title"])
	if not evidence.has(title):
		evidence.append(title)


func _finish_event() -> void:
	event_resolved = true
	pending_event_selection.clear()
	event_battle_pending = false
	if not event_outcome.is_empty():
		event_history.append("%s：%s" % [get_event_title(), event_outcome])
	if not pending_node_resolution.is_empty():
		pending_node_resolution[&"resolved"] = true


func _begin_event_selection(kind: StringName, prompt: String, candidates: Array[Dictionary]) -> void:
	pending_event_selection = {
		&"kind": kind,
		&"prompt": prompt,
		&"candidates": candidates.duplicate(true),
	}


func _basic_removal_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for instance: Dictionary in deck_instances:
		var card_id: StringName = instance[&"card_id"] as StringName
		if card_id == &"calibration_strike" or card_id == &"temporary_guard":
			candidates.append(instance.duplicate(true))
	return candidates


func _deterministic_rare_card(seed_offset: int) -> StringName:
	var rare_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rare_rng.seed = seed_value + seed_offset
	return RARE_REWARD_IDS[rare_rng.randi_range(0, RARE_REWARD_IDS.size() - 1)]


func _prepare_elite_relic_reward(content_seed: int) -> void:
	if pending_node_resolution.has(&"pending_elite_relic_id") or pending_node_resolution.has(&"pending_elite_fallback_ink"):
		return
	var pool: Array[StringName] = RelicCatalog.get_elite_drop_ids(relics)
	if pool.is_empty():
		pending_node_resolution[&"pending_elite_fallback_ink"] = ELITE_RELIC_FALLBACK_INCOME
		return
	var reward_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	reward_rng.seed = content_seed + 17041
	pending_node_resolution[&"pending_elite_relic_id"] = pool[reward_rng.randi_range(0, pool.size() - 1)]


func _settle_pending_elite_reward() -> void:
	if pending_node_resolution.is_empty() or bool(pending_node_resolution.get(&"elite_reward_claimed", false)):
		return
	var relic_id: StringName = pending_node_resolution.get(&"pending_elite_relic_id", &"") as StringName
	var fallback_ink: int = int(pending_node_resolution.get(&"pending_elite_fallback_ink", 0))
	if relic_id != &"" and not relics.has(relic_id):
		relics.append(relic_id)
	elif fallback_ink > 0:
		ink_crystals += fallback_ink
	else:
		return
	pending_node_resolution[&"elite_reward_claimed"] = true
	pending_node_resolution.erase(&"pending_elite_relic_id")
	pending_node_resolution.erase(&"pending_elite_fallback_ink")


func _settle_next_battle_relic_reward() -> void:
	if next_battle_reward_relic_id == &"":
		return
	var reward_id: StringName = next_battle_reward_relic_id
	next_battle_reward_relic_id = &""
	if not relics.has(reward_id):
		relics.append(reward_id)
	if reward_id == &"expired_return_bell":
		_add_evidence(&"overdue_bell_record")


func _option(label: String, consequence: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": true, &"reason": ""}


func _conditional_option(label: String, consequence: String, enabled: bool, reason: String) -> Dictionary:
	return {&"label": label, &"consequence": consequence, &"enabled": enabled, &"reason": "" if enabled else reason}
