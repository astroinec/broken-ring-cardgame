class_name CardUpgradeCatalog
extends RefCounted


static var DEFINITIONS: Dictionary = {
	&"calibration_strike": _entry(&"calibration_strike_plus", "造成 9 点伤害。", {&"damage": 9}),
	&"temporary_guard": _entry(&"temporary_guard_plus", "获得 8 点格挡。", {&"block": 8}),
	&"boundary_read": _entry(&"boundary_read_plus", "抽 2 张牌；超载 1。", {&"overload": 1}),
	&"aftershock": _entry(&"aftershock_plus", "造成 5 点伤害。若本回合获得过不稳定，再造成 7 点伤害。", {&"bonus_damage": 7}),
	&"broken_sentence": _entry(&"broken_sentence_plus", "造成 10 点伤害。若这是本回合打出的第一张牌，抽 1 张牌。", {&"damage": 10}),
	&"blank_space": _entry(&"blank_space_plus", "获得 9 点格挡。若本回合尚未打出攻式，再获得 3 点格挡。", {&"base_block": 9}),
	&"index_reorder": _entry(&"index_reorder_plus", "查看抽牌堆顶 5 张，选择 1 张置入弃牌堆，其余顺序不变。消逝。", {&"look_count": 5}),
	&"unsigned_support": _entry(&"unsigned_support_plus", "获得 8 点格挡。若本回合有牌从封存区解封，再获得 5 点格挡。", {&"base_block": 8}),
	&"rift_slash": _entry(&"rift_slash_plus", "造成 14 点伤害；超载 3。", {&"damage": 14}),
	&"forced_stability": _entry(&"forced_stability_plus", "获得 4 点格挡；移除最多 3 点不稳定，每实际移除 1 点再获得 3 点格挡。", {&"block_per_instability": 3}),
	&"critical_permission": _entry(&"critical_permission_plus", "费用 0。本回合下一次裂解伤害变为 0；抽 1 张牌。消逝。", {&"cost": 0}),
	&"dissolution_protocol": _entry(&"dissolution_protocol_plus", "造成 18 点伤害；每有 1 点不稳定，额外造成 2 点伤害；随后不稳定清零。消逝。", {&"base_damage": 18}),
	&"delayed_guard": _entry(&"delayed_guard_plus", "封存 1。解封：获得 13 点格挡。", {&"unseal_block": 13}),
	&"countdown_scar": _entry(&"countdown_scar_plus", "封存 1。解封：对生命最低的敌人造成 14 点伤害。", {&"sealed_turns": 1}),
	&"prewritten_ending": _entry(&"prewritten_ending_plus", "费用 1。选择手牌中 1 张非消逝牌，生成其复制品并封存 1；原牌本回合费用变为 0。消逝。", {&"cost": 1}),
	&"unseal_order": _entry(&"unseal_order_plus", "选择 1 张封存牌，其倒计时立即归零并触发解封；抽 1 张牌。", {&"draw": 1}),
	&"restate": _entry(&"restate_plus", "造成 4 点伤害；再回响上一张攻式的 90% 伤害。", {&"echo_percent": 90}),
	&"copied_guard": _entry(&"copied_guard_plus", "获得 5 点格挡；回响上一张守式 90% 的格挡效果。", {&"echo_percent": 90}),
	&"homophone": _entry(&"homophone_plus", "复制紧邻上一张费用不高于 1 的非临时、非消逝牌；复制品消逝且本回合费用为 0。", {&"overload": 0}),
	&"reverse_index": _entry(&"reverse_index_plus", "从弃牌堆选择 1 张非状态牌加入手牌；其本回合费用 -1（最低 0）。消逝。", {&"returned_cost_delta": -1}),
	&"delete_redundancy": _entry(&"delete_redundancy_plus", "选择手牌中另一张牌并使其消逝；抽 3 张牌。消逝。", {&"draw": 3}),
	&"missing_name_arbitration": _entry(&"missing_name_arbitration_plus", "获得 5 点格挡；清除全部缺名，每清除 1 层再获得 6 点格挡；若至少清除 1 层，抽 1 张牌。消逝。", {&"block_per_stack": 6}),
	&"tenth_answer": _entry(&"tenth_answer_plus", "造成 6 点伤害；封存区每有 1 张牌，额外造成 7 点伤害；随后所有封存牌倒计时减少 1。", {&"damage_per_sealed": 7}),
	&"echo_chamber": _entry(&"echo_chamber_plus", "抽 1 张牌；本回合下一次成功回响的数值额外提高 150%。消逝。", {&"echo_bonus_percent": 150}),
	&"borrowed_name_execution": _entry(&"borrowed_name_execution_plus", "造成 5 点伤害；每存在一种缺名，额外造成 5 点伤害；随后每种缺名各清除 1 层。", {&"damage_per_kind": 5}),
}


static func _entry(upgrade_id: StringName, description: String, modifiers: Dictionary) -> Dictionary:
	return {
		&"upgrades": [{
			&"id": upgrade_id,
			&"title_suffix": "+",
			&"description": description,
			&"modifiers": modifiers,
			&"enabled_in_m1": true,
		}],
	}


static func get_definition(card_id: StringName) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(card_id, {})
	if definition.is_empty():
		return {}
	var result: Dictionary = definition.duplicate(true)
	result[&"card_id"] = card_id
	return result


static func get_default_upgrade(card_id: StringName) -> Dictionary:
	var definition: Dictionary = get_definition(card_id)
	if definition.is_empty():
		return {}
	var upgrades: Array = definition[&"upgrades"]
	return (upgrades[0] as Dictionary).duplicate(true)


static func get_upgrade(card_id: StringName, upgrade_id: StringName) -> Dictionary:
	if upgrade_id == &"":
		return {}
	var definition: Dictionary = get_definition(card_id)
	for raw_upgrade: Variant in definition.get(&"upgrades", []):
		var upgrade: Dictionary = raw_upgrade as Dictionary
		if upgrade.get(&"id", &"") == upgrade_id:
			return upgrade.duplicate(true)
	return {}


static func get_default_upgrade_id(card_id: StringName) -> StringName:
	var upgrade: Dictionary = get_default_upgrade(card_id)
	return upgrade.get(&"id", &"") as StringName


static func can_upgrade(card_id: StringName) -> bool:
	var upgrade: Dictionary = get_default_upgrade(card_id)
	return not upgrade.is_empty() and bool(upgrade.get(&"enabled_in_m1", false))
