class_name MapNode
extends RefCounted


enum NodeType {
	BATTLE,
	ELITE,
	EVENT,
	SHOP,
	FORGE,
	REST,
	BOSS,
}

var id: StringName = &""
var node_type: NodeType = NodeType.BATTLE
var depth: int = 1
var lane: int = 0
var connections: Array[StringName] = []
var enemy_id: StringName = &""
var event_id: StringName = &""
var content_seed: int = 0
var revealed: bool = false
var reachable: bool = false
var completed: bool = false


func type_name() -> String:
	match node_type:
		NodeType.BATTLE:
			return "普通战斗"
		NodeType.ELITE:
			return "精英"
		NodeType.EVENT:
			return "事件"
		NodeType.SHOP:
			return "商店"
		NodeType.FORGE:
			return "锻造"
		NodeType.REST:
			return "休整"
		NodeType.BOSS:
			return "Boss战"
	return "未知节点"
