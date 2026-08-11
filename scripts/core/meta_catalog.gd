class_name MetaCatalog
extends RefCounted


const TIER_CARD_IDS: Dictionary = {
	0: [
		&"broken_sentence", &"blank_space", &"index_reorder", &"unsigned_support",
		&"rift_slash", &"forced_stability", &"critical_permission", &"delayed_guard",
		&"countdown_scar", &"unseal_order", &"restate", &"copied_guard",
	],
	1: [&"prewritten_ending", &"dissolution_protocol", &"homophone"],
	2: [&"reverse_index", &"delete_redundancy", &"missing_name_arbitration"],
	3: [&"tenth_answer", &"echo_chamber", &"borrowed_name_execution"],
}

const TIER_CONDITIONS: Dictionary = {
	0: "初始开放",
	1: "首次抵达删名者",
	2: "首次完成任意结局",
	3: "读取被删原文，或累计通关 3 次",
}


static func get_unlocked_reward_ids(unlock_tier: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for tier: int in range(0, clampi(unlock_tier, 0, 3) + 1):
		for raw_id: Variant in TIER_CARD_IDS[tier]:
			var card_id: StringName = raw_id as StringName
			if CardCatalog.has_card(card_id) and not result.has(card_id):
				result.append(card_id)
	return result


static func get_tier_for_progress(profile: Dictionary) -> int:
	if int(profile.get("read_original_wins", 0)) > 0 or int(profile.get("wins", 0)) >= 3:
		return 3
	if int(profile.get("wins", 0)) > 0:
		return 2
	if int(profile.get("boss_reached", 0)) > 0:
		return 1
	return 0


static func next_unlock_condition(unlock_tier: int) -> String:
	if unlock_tier >= 3:
		return "全部卡牌解锁已完成"
	return str(TIER_CONDITIONS[unlock_tier + 1])


static func unlock_condition_for_card(card_id: StringName) -> String:
	for tier: int in range(4):
		if (TIER_CARD_IDS[tier] as Array).has(card_id):
			return str(TIER_CONDITIONS[tier])
	return "不属于局外解锁池"


static func get_new_unlock_ids(old_tier: int, new_tier: int) -> Array[StringName]:
	var old_ids: Array[StringName] = get_unlocked_reward_ids(old_tier)
	var result: Array[StringName] = []
	for card_id: StringName in get_unlocked_reward_ids(new_tier):
		if not old_ids.has(card_id):
			result.append(card_id)
	return result
