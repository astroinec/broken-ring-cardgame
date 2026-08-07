extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_fixed_structure()
	_test_determinism()
	_test_graph_validity()
	_test_run_progression()
	if failures == 0:
		print("PASS: all expedition map checks")
		quit(0)
	else:
		push_error("FAIL: %d map checks failed" % failures)
		quit(1)


func _test_fixed_structure() -> void:
	var graph: MapGraph = MapGraph.new()
	graph.generate(73103)
	_expect(graph.node_ids_by_depth.size() == 9, "map has exactly nine depths")
	var expected_counts: Array[int] = [1, 2, 1, 2, 1, 2, 1, 1, 1]
	for depth: int in range(1, 10):
		_expect(graph.get_nodes_at_depth(depth).size() == expected_counts[depth - 1], "depth %d has expected lane count" % depth)
	_expect(graph.get_nodes_at_depth(1)[0].node_type == MapNode.NodeType.BATTLE, "depth one is battle")
	_expect(_types_at(graph, 2) == [MapNode.NodeType.BATTLE, MapNode.NodeType.EVENT], "depth two branches battle/event")
	_expect(graph.get_nodes_at_depth(3)[0].node_type == MapNode.NodeType.REST, "depth three is rest")
	_expect(_types_at(graph, 4) == [MapNode.NodeType.BATTLE, MapNode.NodeType.SHOP], "depth four branches battle/shop")
	_expect(graph.get_nodes_at_depth(5)[0].node_type == MapNode.NodeType.EVENT, "depth five is event")
	_expect(_types_at(graph, 6) == [MapNode.NodeType.ELITE, MapNode.NodeType.FORGE], "depth six branches elite/forge")
	_expect(graph.get_nodes_at_depth(9)[0].node_type == MapNode.NodeType.BOSS, "depth nine is boss placeholder")


func _test_determinism() -> void:
	var first: MapGraph = MapGraph.new()
	var second: MapGraph = MapGraph.new()
	var other: MapGraph = MapGraph.new()
	first.generate(73103)
	second.generate(73103)
	other.generate(73104)
	_expect(first.digest() == second.digest(), "same seed reproduces graph digest")
	_expect(first.digest() != other.digest(), "different seed changes graph digest")
	for depth: int in range(1, 10):
		for node: MapNode in first.get_nodes_at_depth(depth):
			_expect(node.id == StringName("d%02d_%02d" % [depth, node.lane]), "node %s has stable id" % node.id)


func _test_graph_validity() -> void:
	for seed_value: int in [73103, 80011, 91027, 100003, 110009]:
		var graph: MapGraph = MapGraph.new()
		graph.generate(seed_value)
		var errors: Array[String] = graph.validate()
		_expect(errors.is_empty(), "seed %d graph validates: %s" % [seed_value, "; ".join(errors)])
		for depth: int in range(1, 9):
			for node: MapNode in graph.get_nodes_at_depth(depth):
				_expect(not node.connections.is_empty(), "%s has successor" % node.id)
				for next_id: StringName in node.connections:
					_expect(graph.get_node(next_id).depth == depth + 1, "%s connects only to next depth" % node.id)


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
	_expect(run.map_graph.get_node(run.map_graph.boss_node_id).completed, "route reaches and completes boss placeholder")


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
			run.acknowledge_boss_placeholder()


func _types_at(graph: MapGraph, depth: int) -> Array[int]:
	var result: Array[int] = []
	for node: MapNode in graph.get_nodes_at_depth(depth):
		result.append(node.node_type)
	return result


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
