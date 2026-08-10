class_name CardCatalog
extends RefCounted


const STARTER_IDS: Array[StringName] = [
	&"calibration_strike", &"calibration_strike", &"calibration_strike", &"calibration_strike",
	&"temporary_guard", &"temporary_guard", &"temporary_guard", &"temporary_guard",
	&"boundary_read", &"aftershock",
]

const REWARD_IDS: Array[StringName] = [
	&"broken_sentence",
	&"blank_space",
	&"index_reorder",
	&"unsigned_support",
	&"rift_slash",
	&"forced_stability",
	&"critical_permission",
	&"dissolution_protocol",
	&"delayed_guard",
	&"countdown_scar",
	&"prewritten_ending",
	&"unseal_order",
	&"restate",
	&"copied_guard",
	&"homophone",
]

const DEFINITIONS: Dictionary = {
	&"calibration_strike": {
		&"title": "校准击", &"type": CardData.CardType.ATTACK, &"cost": 1,
		&"description": "造成 6 点伤害。", &"rarity": "基础",
		&"flavor": "“动作记录无异常。人格记录：空白。”",
	},
	&"temporary_guard": {
		&"title": "临时护式", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "获得 5 点格挡。", &"rarity": "基础",
		&"flavor": "它只能保护你到下一次校准。",
	},
	&"boundary_read": {
		&"title": "越界读取", &"type": CardData.CardType.LAW, &"cost": 1,
		&"description": "抽 2 张牌；超载 2。", &"rarity": "基础",
		&"flavor": "文件拒绝访问。你却记得里面的内容。",
	},
	&"aftershock": {
		&"title": "余震", &"type": CardData.CardType.ATTACK, &"cost": 1,
		&"description": "造成 5 点伤害。若本回合获得过不稳定，再造成 4 点伤害。", &"rarity": "基础",
		&"flavor": "身体比警报更早知道裂缝将从哪里出现。",
	},
	&"broken_sentence": {
		&"title": "断句", &"type": CardData.CardType.ATTACK, &"cost": 1,
		&"description": "造成 7 点伤害。若这是本回合打出的第一张牌，抽 1 张牌。", &"rarity": "普通",
		&"flavor": "判决在句号抵达前就已执行。",
	},
	&"blank_space": {
		&"title": "留白", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "获得 7 点格挡。若本回合尚未打出攻式，再获得 3 点格挡。", &"rarity": "普通",
		&"flavor": "空白不是缺失。空白是被允许留下的部分。",
	},
	&"index_reorder": {
		&"title": "索引重排", &"type": CardData.CardType.LAW, &"cost": 0,
		&"description": "查看抽牌堆顶 3 张，选择 1 张置入弃牌堆，其余顺序不变。消逝。", &"rarity": "普通", &"exhausts": true,
		&"flavor": "目录比正文多出一位作者。",
	},
	&"unsigned_support": {
		&"title": "未署名的援护", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "获得 6 点格挡。若本回合有牌从封存区解封，再获得 5 点格挡。", &"rarity": "普通",
		&"flavor": "有人替你签过字。档案里没有那个人。",
	},
	&"rift_slash": {
		&"title": "裂隙挥击", &"type": CardData.CardType.ATTACK, &"cost": 1,
		&"description": "造成 11 点伤害；超载 2。", &"rarity": "普通",
		&"flavor": "裂口没有出现在刀上。它先出现在目标的名字里。",
	},
	&"forced_stability": {
		&"title": "强制稳定", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "移除最多 3 点不稳定；每实际移除 1 点，获得 2 点格挡。", &"rarity": "普通",
		&"flavor": "校准不是治疗，只是暂时压住扩散的裂纹。",
	},
	&"critical_permission": {
		&"title": "临界许可", &"type": CardData.CardType.LAW, &"cost": 1,
		&"description": "本回合下一次裂解伤害变为 0；抽 1 张牌。消逝。", &"rarity": "罕见", &"exhausts": true,
		&"flavor": "许可签发时间：事故发生后三小时。",
	},
	&"dissolution_protocol": {
		&"title": "崩解协议", &"type": CardData.CardType.ATTACK, &"cost": 2,
		&"description": "造成 14 点伤害；每有 1 点不稳定，额外造成 2 点伤害；随后不稳定清零。消逝。", &"rarity": "罕见", &"exhausts": true,
		&"flavor": "协议最后一行：载体无需回收。",
	},
	&"delayed_guard": {
		&"title": "延迟防线", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "封存 1。解封：获得 12 点格挡。", &"rarity": "普通",
		&"flavor": "城墙建成时，战争已经结束了。",
	},
	&"countdown_scar": {
		&"title": "倒计刻痕", &"type": CardData.CardType.ATTACK, &"cost": 1,
		&"description": "封存 2。解封：对生命最低的敌人造成 18 点伤害。", &"rarity": "普通",
		&"flavor": "每一道刻痕都在等同一个明天。",
	},
	&"prewritten_ending": {
		&"title": "预写结局", &"type": CardData.CardType.LAW, &"cost": 2,
		&"description": "选择手牌中 1 张非消逝牌，生成其复制品并封存 1；原牌本回合费用变为 0。消逝。", &"rarity": "罕见", &"exhausts": true,
		&"flavor": "结局早已写好，你只是把它提前翻到这一页。",
	},
	&"unseal_order": {
		&"title": "开封令", &"type": CardData.CardType.LAW, &"cost": 1,
		&"description": "选择 1 张封存牌，其倒计时立即归零并触发解封；超载 2。", &"rarity": "罕见",
		&"flavor": "命令来自尚未成立的终末机构。",
	},
	&"restate": {
		&"title": "复述", &"type": CardData.CardType.LAW, &"cost": 1,
		&"description": "回响上一张攻式的 60% 伤害。", &"rarity": "普通",
		&"flavor": "第二个声音与第一个完全相同，连那次颤抖也没有遗漏。",
	},
	&"copied_guard": {
		&"title": "复写护式", &"type": CardData.CardType.DEFENSE, &"cost": 1,
		&"description": "获得 4 点格挡；回响上一张守式 50% 的格挡效果。", &"rarity": "普通",
		&"flavor": "抄本比原件早三十七年入库。",
	},
	&"homophone": {
		&"title": "同音异义", &"type": CardData.CardType.LAW, &"cost": 1,
		&"description": "复制紧邻上一张费用不高于 1 的非临时、非消逝牌。复制品本回合费用为 0，打出后消逝。超载 1。", &"rarity": "罕见",
		&"flavor": "此地称你为“载律者”，另一个纪元却用同样的读音称呼死刑犯。",
	},
	&"redaction": {
		&"title": "删节", &"type": CardData.CardType.STATUS, &"cost": 99,
		&"description": "不可打出。抽到时立即获得 1 层律式缺名，然后消逝。", &"rarity": "状态", &"exhausts": true,
		&"flavor": "此处内容从未存在。",
	},
	&"blank_page": {
		&"title": "空页", &"type": CardData.CardType.STATUS, &"cost": 1,
		&"description": "消逝。无其他效果。", &"rarity": "状态", &"exhausts": true,
		&"flavor": "纸面完好。它只是拒绝承载任何名字。",
	},
	&"old_wound": {
		&"title": "旧伤", &"type": CardData.CardType.STATUS, &"cost": 1,
		&"description": "消逝。若回合结束时仍在手牌，受到 2 点不可格挡伤害。", &"rarity": "状态", &"exhausts": true,
		&"flavor": "这具身体的伤口，比这具身体更早登记。",
	},
}

const STATUS_IDS: Array[StringName] = [&"redaction", &"blank_page", &"old_wound"]


static func has_card(card_id: StringName) -> bool:
	return DEFINITIONS.has(card_id)


static func get_definition(card_id: StringName) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(card_id, {})
	return definition.duplicate(true)


static func create_card(
	card_id: StringName, instance_id: int, upgrade_id: StringName = &""
) -> CardData:
	var definition: Dictionary = DEFINITIONS.get(card_id, {})
	assert(not definition.is_empty(), "未知卡牌定义：%s" % card_id)
	var title: String = str(definition[&"title"])
	var cost: int = int(definition[&"cost"])
	var description: String = str(definition[&"description"])
	var modifiers: Dictionary = {}
	if upgrade_id != &"":
		var upgrade: Dictionary = CardUpgradeCatalog.get_upgrade(card_id, upgrade_id)
		assert(not upgrade.is_empty(), "未知卡牌升级：%s/%s" % [card_id, upgrade_id])
		title += str(upgrade[&"title_suffix"])
		description = str(upgrade[&"description"])
		modifiers = (upgrade[&"modifiers"] as Dictionary).duplicate(true)
		cost = int(modifiers.get(&"cost", cost))
	return CardData.new(
		instance_id,
		card_id,
		title,
		int(definition[&"type"]) as CardData.CardType,
		cost,
		description,
		bool(definition.get(&"exhausts", false)),
		str(definition[&"rarity"]),
		str(definition[&"flavor"]),
		upgrade_id,
		modifiers
	)
