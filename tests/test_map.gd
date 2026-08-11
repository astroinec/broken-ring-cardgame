extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_template_structure()
	_test_determinism()
	_test_diversity_thresholds()
	_test_graph_validity()
	_test_run_progression()
	if failures == 0:
		print("PASS: all expedition map checks")
		quit(0)
	else:
		push_error("FAIL: %d map checks failed" % failures)
		quit(1)


func _test_template_structure() -> void:
	var seen_templates: Dictionary = {}
	for seed_value: int in range(1, 600):
		var graph: MapGraph = MapGraph.new()
		graph.generate(seed_value)
		if seen_templates.has(graph.template_id):
			continue
		seen_templates[graph.template_id] = true
		_expect(graph.node_ids_by_depth.size() == 9, "%s 模板恰好九层" % graph.template_id)
		_expect(graph.validate().is_empty(), "%s 模板完整校验通过" % graph.template_id)
		_expect(graph.get_nodes_at_depth(9).size() == 1 and graph.get_nodes_at_depth(9)[0].node_type == MapNode.NodeType.BOSS, "%s 模板第九层是唯一 Boss" % graph.template_id)
		for depth: int in range(1, 10):
			var width: int = graph.get_nodes_at_depth(depth).size()
			_expect(width >= 1 and width <= 3, "%s 第%d层宽度在1到3" % [graph.template_id, depth])
		var event_ids: Array[StringName] = []
		for depth: int in range(1, 10):
			for node: MapNode in graph.get_nodes_at_depth(depth):
				if node.node_type == MapNode.NodeType.EVENT:
					event_ids.append(node.event_id)
		_expect(_unique_count(event_ids) == event_ids.size(), "%s 事件节点无放回" % graph.template_id)
		if seen_templates.size() == MapGraph.TEMPLATES.size():
			break
	_expect(seen_templates.size() == MapGraph.TEMPLATES.size(), "全部地图模板都能由种子选中并合法生成")


func _test_determinism() -> void:
	var first: MapGraph = MapGraph.new()
	var second: MapGraph = MapGraph.new()
	var other: MapGraph = MapGraph.new()
	first.generate(73103)
	second.generate(73103)
	other.generate(73104)
	_expect(first.digest() == second.digest(), "same seed reproduces graph digest")
	_expect(first.digest() != other.digest(), "different seed changes graph digest")
	for tier: int in range(4):
		_expect(_run_content_digest(73103, tier) == _run_content_digest(73103, tier), "同 seed 同 U%d 完整内容摘要一致" % tier)
	_expect(_run_content_digest(73103, 0) != _run_content_digest(73103, 3), "同 seed 不同解锁层拥有不同冻结奖励摘要")
	for depth: int in range(1, 10):
		for node: MapNode in first.get_nodes_at_depth(depth):
			_expect(node.id == StringName("d%02d_%02d" % [depth, node.lane]), "node %s has stable id" % node.id)


func _test_diversity_thresholds() -> void:
	var structures: Dictionary = {}
	var event_pairs: Dictionary = {}
	for index: int in range(30):
		var seed_value: int = 73103 + index * 7919
		var graph: MapGraph = MapGraph.new()
		graph.generate(seed_value)
		structures[graph.structure_digest()] = true
		event_pairs[graph.event_ordered_pair()] = true
		var event_ids: Array[StringName] = []
		for depth: int in range(1, 10):
			for node: MapNode in graph.get_nodes_at_depth(depth):
				if node.node_type == MapNode.NodeType.EVENT:
					event_ids.append(node.event_id)
		_expect(_unique_count(event_ids) == event_ids.size(), "seed %d 事件无放回" % seed_value)
	_expect(structures.size() >= 12, "30种子结构指纹至少12种（实际%d）" % structures.size())
	_expect(event_pairs.size() >= 12, "30种子事件有序对至少12种（实际%d）" % event_pairs.size())


func _test_graph_validity() -> void:
	for seed_value: int in [73103, 80011, 91027, 100003, 110009]:
		var graph: MapGraph = MapGraph.new()
		graph.generate(seed_value)
		var errors: Array[String] = graph.validate()
		_expect(errors.is_empty(), "seed %d graph validates: %s" % [seed_value, "; ".join(errors)])
		for depth: int in range(1, 9):
			var current_nodes: Array[MapNode] = graph.get_nodes_at_depth(depth)
			var next_nodes: Array[MapNode] = graph.get_nodes_at_depth(depth + 1)
			var edge_count: int = 0
			for node: MapNode in current_nodes:
				_expect(not node.connections.is_empty(), "%s has successor" % node.id)
				edge_count += node.connections.size()
				for next_id: StringName in node.connections:
					_expect(graph.get_node(next_id).depth == depth + 1, "%s connects only to next depth" % node.id)
			if current_nodes.size() > 1 and next_nodes.size() > 1:
				_expect(edge_count < current_nodes.size() * next_nodes.size(), "seed %d 第%d层不是全互连" % [seed_value, depth])


func _test_run_progression() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	_expect(run.available_node_ids == run.map_graph.start_node_ids, "run starts with graph start nodes")
	for depth: int in range(1, 10):
		_expect(not run.available_node_ids.is_empty(), "depth %d has reachable node" % depth)
		var node_id: StringName = run.available_node_ids[0]
		var node: MapNode = run.map_graph.get_node(node_id)
		_expect(node.depth == depth, "reachable node advances one depth")
		_expect(run.enter_node(node_id), "enter reachable node %s" % node_id)
		_expect(not run.enter_node(node_id), "cannot re-enter while node unresolved")
		_resolve_node_for_test(run, node)
		_expect(run.complete_current_node(), "complete node %s" % node_id)
		_expect(node.completed, "completed state stored on map node")
		_expect(not run.enter_node(node_id), "completed node cannot be entered again")
	_expect(run.map_graph.get_node(run.map_graph.boss_node_id).completed, "route reaches and completes formal Boss node")


func _resolve_node_for_test(run: RunModel, node: MapNode) -> void:
	match node.node_type:
		MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
			run.record_current_battle_victory()
			run.generate_reward_choices(node.depth)
			run.skip_reward()
		MapNode.NodeType.EVENT:
			run.apply_event_choice(0)
		MapNode.NodeType.SHOP:
			run.finish_shop()
		MapNode.NodeType.FORGE:
			run.skip_forge()
		MapNode.NodeType.REST:
			run.skip_rest()
		MapNode.NodeType.BOSS:
			# 地图推进测试不重跑战斗；用总是可选的正式结局验证节点协议。
			run.record_boss_outcome(&"deliver_seal", 0)


func _types_at(graph: MapGraph, depth: int) -> Array[int]:
	var result: Array[int] = []
	for node: MapNode in graph.get_nodes_at_depth(depth):
		result.append(node.node_type)
	return result


func _run_content_digest(seed_value: int, tier: int) -> String:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value, tier)
	var rewards: Array[StringName] = run.generate_reward_choices(1)
	var shop: Dictionary = ShopCatalog.generate(seed_value + 404, 0, [], run.unlocked_reward_ids, run.run_seen_reward_ids)
	return "%s|U%d|%s|%s" % [run.map_graph.digest(), tier, str(rewards), ShopCatalog.digest(shop)]


func _unique_count(values: Array[StringName]) -> int:
	var seen: Dictionary = {}
	for value: StringName in values:
		seen[value] = true
	return seen.size()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
