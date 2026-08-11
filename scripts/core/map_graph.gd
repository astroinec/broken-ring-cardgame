class_name MapGraph
extends RefCounted


const TEMPLATES: Array[Dictionary] = [
	{
		&"id": &"archive_route",
		&"depths": {
			1: [MapNode.NodeType.BATTLE],
			2: [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT],
			3: [MapNode.NodeType.REST, MapNode.NodeType.EVENT],
			4: [MapNode.NodeType.BATTLE, MapNode.NodeType.SHOP, MapNode.NodeType.BATTLE],
			5: [MapNode.NodeType.EVENT, MapNode.NodeType.REST],
			6: [MapNode.NodeType.ELITE, MapNode.NodeType.FORGE],
			7: [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT, MapNode.NodeType.BATTLE],
			8: [MapNode.NodeType.REST, MapNode.NodeType.SHOP],
			9: [MapNode.NodeType.BOSS],
		},
	},
	{
		&"id": &"rift_route",
		&"depths": {
			1: [MapNode.NodeType.BATTLE, MapNode.NodeType.BATTLE],
			2: [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT, MapNode.NodeType.BATTLE],
			3: [MapNode.NodeType.REST],
			4: [MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE],
			5: [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT],
			6: [MapNode.NodeType.ELITE, MapNode.NodeType.FORGE, MapNode.NodeType.BATTLE],
			7: [MapNode.NodeType.BATTLE, MapNode.NodeType.BATTLE],
			8: [MapNode.NodeType.REST],
			9: [MapNode.NodeType.BOSS],
		},
	},
	{
		&"id": &"calibration_route",
		&"depths": {
			1: [MapNode.NodeType.BATTLE],
			2: [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT],
			3: [MapNode.NodeType.REST, MapNode.NodeType.FORGE],
			4: [MapNode.NodeType.BATTLE, MapNode.NodeType.SHOP, MapNode.NodeType.BATTLE],
			5: [MapNode.NodeType.EVENT, MapNode.NodeType.REST, MapNode.NodeType.EVENT],
			6: [MapNode.NodeType.ELITE, MapNode.NodeType.FORGE],
			7: [MapNode.NodeType.BATTLE, MapNode.NodeType.BATTLE],
			8: [MapNode.NodeType.REST, MapNode.NodeType.FORGE],
			9: [MapNode.NodeType.BOSS],
		},
	},
]

const BATTLE_ENEMY_POOLS: Dictionary = {
	1: [&"nameless_dummy", &"calibration_guard"],
	2: [&"calibration_guard", &"rift_gauge", &"hollow_name_guard"],
	4: [&"time_hammer", &"echo_discriminator", &"hollow_name_guard"],
	7: [&"word_eater", &"reverse_reader"],
}
const ELITE_ENEMY_IDS: Array[StringName] = [&"binding_instrument"]
const EVENT_IDS: Array[StringName] = [
	&"authorless_book", &"seventh_dock", &"calibration_station",
	&"speaking_for_you", &"deleted_funeral", &"definition_tax",
]

var seed_value: int = 0
var template_id: StringName = &""
var nodes_by_id: Dictionary = {}
var node_ids_by_depth: Dictionary = {}
var start_node_ids: Array[StringName] = []
var boss_node_id: StringName = &""


func generate(p_seed_value: int) -> void:
	seed_value = maxi(1, p_seed_value)
	nodes_by_id.clear()
	node_ids_by_depth.clear()
	start_node_ids.clear()
	boss_node_id = &""
	var graph_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	graph_rng.seed = seed_value
	var template: Dictionary = TEMPLATES[graph_rng.randi_range(0, TEMPLATES.size() - 1)]
	template_id = template[&"id"] as StringName
	var depths: Dictionary = template[&"depths"] as Dictionary
	for depth: int in range(1, 10):
		var ids: Array[StringName] = []
		var types: Array = depths[depth]
		for lane: int in range(types.size()):
			var node: MapNode = MapNode.new()
			node.id = StringName("d%02d_%02d" % [depth, lane])
			node.node_type = int(types[lane]) as MapNode.NodeType
			node.depth = depth
			node.lane = lane
			node.content_seed = _derive_content_seed(depth, lane)
			_assign_non_event_content(node)
			nodes_by_id[node.id] = node
			ids.append(node.id)
		node_ids_by_depth[depth] = ids
	_connect_depths(graph_rng)
	_assign_events_without_replacement()
	start_node_ids = _ids_at_depth(1)
	boss_node_id = _ids_at_depth(9)[0]
	for start_id: StringName in start_node_ids:
		var start: MapNode = get_node(start_id)
		start.revealed = true
		start.reachable = true


func get_node(node_id: StringName) -> MapNode:
	return nodes_by_id.get(node_id) as MapNode


func get_nodes_at_depth(depth: int) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for node_id: StringName in _ids_at_depth(depth):
		result.append(get_node(node_id))
	return result


func get_reachable_nodes(current_id: StringName) -> Array[MapNode]:
	var result: Array[MapNode] = []
	if current_id == &"":
		for start_id: StringName in start_node_ids:
			result.append(get_node(start_id))
		return result
	var current: MapNode = get_node(current_id)
	if current == null:
		return result
	for next_id: StringName in current.connections:
		result.append(get_node(next_id))
	return result


func validate() -> Array[String]:
	var errors: Array[String] = []
	if node_ids_by_depth.size() != 9:
		errors.append("地图必须恰好有9层")
	var incoming: Dictionary = {}
	for raw_id: Variant in nodes_by_id.keys():
		incoming[raw_id] = 0
	for depth: int in range(1, 10):
		if not node_ids_by_depth.has(depth):
			errors.append("缺少第%d层" % depth)
			continue
		if get_nodes_at_depth(depth).size() > 3:
			errors.append("第%d层超过3个节点" % depth)
		for node: MapNode in get_nodes_at_depth(depth):
			if node.id == &"":
				errors.append("第%d层存在空节点ID" % depth)
			if node.depth != depth:
				errors.append("节点%s层级字段不一致" % node.id)
			if depth < 9 and node.connections.is_empty():
				errors.append("非Boss节点%s没有后继" % node.id)
			if depth == 9 and not node.connections.is_empty():
				errors.append("Boss节点%s不应有后继" % node.id)
			for next_id: StringName in node.connections:
				var next: MapNode = get_node(next_id)
				if next == null:
					errors.append("节点%s指向不存在的节点%s" % [node.id, next_id])
					continue
				if next.id == node.id:
					errors.append("节点%s存在自环" % node.id)
				if next.depth != node.depth + 1:
					errors.append("节点%s存在跨层边" % node.id)
				incoming[next_id] = int(incoming.get(next_id, 0)) + 1
			if node.node_type == MapNode.NodeType.EVENT:
				if node.event_id == &"" or node.enemy_id != &"":
					errors.append("事件节点%s内容字段不合法" % node.id)
			elif node.node_type == MapNode.NodeType.BATTLE or node.node_type == MapNode.NodeType.ELITE or node.node_type == MapNode.NodeType.BOSS:
				if node.enemy_id == &"" or node.event_id != &"" or not EnemyCatalog.has_enemy(node.enemy_id):
					errors.append("战斗节点%s内容字段不合法" % node.id)
			elif node.enemy_id != &"" or node.event_id != &"":
				errors.append("非战斗/事件节点%s不应持有敌人或事件ID" % node.id)
	for depth: int in range(2, 10):
		for node_id: StringName in _ids_at_depth(depth):
			if int(incoming.get(node_id, 0)) < 1:
				errors.append("节点%s没有前驱" % node_id)
	if not _boss_is_reachable():
		errors.append("起点无法到达Boss")
	return errors


func digest() -> String:
	var parts: Array[String] = ["seed=%d" % seed_value, "template=%s" % template_id]
	for depth: int in range(1, 10):
		for node: MapNode in get_nodes_at_depth(depth):
			var links: Array[String] = []
			for next_id: StringName in node.connections:
				links.append(str(next_id))
			parts.append("%s:%d:%d:%d:%s:%s:%s" % [
				node.id, node.depth, node.lane, node.node_type,
				node.enemy_id, node.event_id, ",".join(links),
			])
			parts.append("content=%d" % node.content_seed)
	return "|".join(parts)


func structure_digest() -> String:
	var parts: Array[String] = [str(template_id)]
	for depth: int in range(1, 10):
		for node: MapNode in get_nodes_at_depth(depth):
			var links: Array[String] = []
			for next_id: StringName in node.connections:
				links.append(str(next_id))
			parts.append("%s:%d:%s" % [node.id, node.node_type, ",".join(links)])
	return "|".join(parts)


func event_ordered_pair() -> String:
	var events: Array[String] = []
	for depth: int in range(1, 10):
		for node: MapNode in get_nodes_at_depth(depth):
			if node.node_type == MapNode.NodeType.EVENT:
				events.append(str(node.event_id))
	return "|".join(events.slice(0, mini(2, events.size())))


func _connect_depths(graph_rng: RandomNumberGenerator) -> void:
	for depth: int in range(1, 9):
		var current_ids: Array[StringName] = _ids_at_depth(depth)
		var next_ids: Array[StringName] = _ids_at_depth(depth + 1)
		var shuffled_current: Array[StringName] = current_ids.duplicate()
		_shuffle_ids(shuffled_current, graph_rng)
		var shuffled_next: Array[StringName] = next_ids.duplicate()
		_shuffle_ids(shuffled_next, graph_rng)
		for next_index: int in range(shuffled_next.size()):
			var predecessor: MapNode = get_node(shuffled_current[next_index % shuffled_current.size()])
			predecessor.connections.append(shuffled_next[next_index])
		for current_id: StringName in shuffled_current:
			var node: MapNode = get_node(current_id)
			if node.connections.is_empty():
				node.connections.append(shuffled_next[graph_rng.randi_range(0, shuffled_next.size() - 1)])
			if shuffled_next.size() > 1 and node.connections.size() < shuffled_next.size() and graph_rng.randf() < 0.45:
				var candidates: Array[StringName] = shuffled_next.duplicate()
				for existing: StringName in node.connections:
					candidates.erase(existing)
				if not candidates.is_empty():
					node.connections.append(candidates[graph_rng.randi_range(0, candidates.size() - 1)])
			node.connections.sort_custom(_id_less)
		_break_full_interconnect(current_ids, next_ids)


func _break_full_interconnect(current_ids: Array[StringName], next_ids: Array[StringName]) -> void:
	if current_ids.size() <= 1 or next_ids.size() <= 1:
		return
	var edge_count: int = 0
	var incoming: Dictionary = {}
	for next_id: StringName in next_ids:
		incoming[next_id] = 0
	for current_id: StringName in current_ids:
		var node: MapNode = get_node(current_id)
		edge_count += node.connections.size()
		for next_id: StringName in node.connections:
			incoming[next_id] = int(incoming[next_id]) + 1
	if edge_count < current_ids.size() * next_ids.size():
		return
	for current_id: StringName in current_ids:
		var node: MapNode = get_node(current_id)
		if node.connections.size() <= 1:
			continue
		for next_id: StringName in node.connections.duplicate():
			if int(incoming[next_id]) > 1:
				node.connections.erase(next_id)
				return


func _assign_events_without_replacement() -> void:
	var event_nodes: Array[MapNode] = []
	for depth: int in range(1, 10):
		for node: MapNode in get_nodes_at_depth(depth):
			if node.node_type == MapNode.NodeType.EVENT:
				event_nodes.append(node)
	var event_pool: Array[StringName] = EVENT_IDS.duplicate()
	var event_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	event_rng.seed = int((seed_value * 214013 + 2531011) & 0x7fffffff)
	_shuffle_ids(event_pool, event_rng)
	for index: int in range(event_nodes.size()):
		event_nodes[index].event_id = event_pool[index]


func _ids_at_depth(depth: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_id: Variant in node_ids_by_depth.get(depth, []):
		result.append(raw_id as StringName)
	return result


func _derive_content_seed(depth: int, lane: int) -> int:
	return maxi(1, int((seed_value * 1103515245 + depth * 10007 + lane * 7919 + 12345) & 0x7fffffff))


func _assign_non_event_content(node: MapNode) -> void:
	var content_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	content_rng.seed = node.content_seed
	match node.node_type:
		MapNode.NodeType.BATTLE:
			var pool: Array = _battle_pool_for_depth(node.depth)
			node.enemy_id = pool[content_rng.randi_range(0, pool.size() - 1)] as StringName
		MapNode.NodeType.ELITE:
			node.enemy_id = ELITE_ENEMY_IDS[content_rng.randi_range(0, ELITE_ENEMY_IDS.size() - 1)]
		MapNode.NodeType.BOSS:
			node.enemy_id = &"name_eraser"


func _battle_pool_for_depth(depth: int) -> Array:
	if depth <= 1:
		return BATTLE_ENEMY_POOLS[1]
	if depth <= 3:
		return BATTLE_ENEMY_POOLS[2]
	if depth <= 6:
		return BATTLE_ENEMY_POOLS[4]
	return BATTLE_ENEMY_POOLS[7]


func _shuffle_ids(values: Array[StringName], source_rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = source_rng.randi_range(0, index)
		var held: StringName = values[index]
		values[index] = values[swap_index]
		values[swap_index] = held


static func _id_less(first: StringName, second: StringName) -> bool:
	return str(first) < str(second)


func _boss_is_reachable() -> bool:
	var frontier: Array[StringName] = start_node_ids.duplicate()
	var seen: Dictionary = {}
	while not frontier.is_empty():
		var node_id: StringName = frontier.pop_front()
		if seen.has(node_id):
			continue
		seen[node_id] = true
		if node_id == boss_node_id:
			return true
		var node: MapNode = get_node(node_id)
		if node == null:
			continue
		for next_id: StringName in node.connections:
			frontier.append(next_id)
	return false
