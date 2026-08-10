class_name RelicCatalog
extends RefCounted


const DEFINITIONS: Dictionary = {
	&"crack_stabilizer": {
		&"id": &"crack_stabilizer",
		&"title": "裂纹稳定器",
		&"rarity": "起始遗物",
		&"description": "每场战斗第一次获得不稳定时，少获得 1 点。",
		&"short_description": "首次超载 -1 不稳定",
		&"flavor": "标签写着“新型号”。内部零件已更换过九次。",
		&"source_hint": "远征初始配发",
		&"implemented": true,
		&"elite_drop": false,
		&"shop_offer": false,
	},
	&"wordless_bookplate": {
		&"id": &"wordless_bookplate",
		&"title": "无字藏书票",
		&"rarity": "普通 / 纪元",
		&"description": "每场战斗第一次打出律式后，抽 1 张牌。",
		&"short_description": "首次律式后抽 1",
		&"flavor": "持票者可以借阅一本不存在的书。",
		&"source_hint": "精英掉落、商店或定义税事件",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": true,
	},
	&"calibrator_red_pen": {
		&"id": &"calibrator_red_pen",
		&"title": "校准官的红笔",
		&"rarity": "普通",
		&"description": "每场战斗第一次升级效果实际提高正伤害或格挡时，该牌首个符合条件的结果额外 +3。",
		&"short_description": "首次有效升级伤害/格挡 +3",
		&"flavor": "它只修改那些已经发生的错误。",
		&"source_hint": "精英掉落或商店",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": true,
	},
	&"delay_gear": {
		&"id": &"delay_gear",
		&"title": "延迟齿轮",
		&"rarity": "普通",
		&"description": "每场战斗第一张进入封存区的牌倒计时 -1，最低为 0；降至 0 时在下一次封存结算窗口解封。",
		&"short_description": "首张封存牌倒计时 -1",
		&"flavor": "齿轮拒绝承认“现在”是一个有效刻度。",
		&"source_hint": "精英掉落或商店",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": true,
	},
	&"echo_hyoid": {
		&"id": &"echo_hyoid",
		&"title": "复读舌骨",
		&"rarity": "罕见",
		&"description": "每回合第一次成功触发回响时，额外获得 3 格挡。",
		&"short_description": "每回合首次回响 +3 格挡",
		&"flavor": "骨骼检测结果：单一样本。复检结果：无法确定。",
		&"source_hint": "精英掉落、商店或替你说话的人事件",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": true,
	},
	&"seventh_dock_stamp": {
		&"id": &"seventh_dock_stamp",
		&"title": "第七码头通行章",
		&"rarity": "罕见 / 纪元",
		&"description": "商店移除卡牌费用降低 25（最低为 0）；进入商店时可查看旧档案。",
		&"short_description": "商店移除 -25；查看旧档案",
		&"flavor": "发给每一位自愿进入残骸的回收者。",
		&"source_hint": "精英掉落或商店",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": true,
	},
	&"blank_epitaph": {
		&"id": &"blank_epitaph",
		&"title": "空白墓志铭",
		&"rarity": "稀有 / 纪元",
		&"description": "每场战斗第一次生命从 50% 或以上降至低于 50% 时，伤害结算后获得 12 格挡，再从当前手牌随机封存 1 张非状态牌 1 回合；无合规手牌仍消耗触发。",
		&"short_description": "首次降至半血以下 +12 格挡并封存手牌",
		&"flavor": "墓中没有尸体。碑上没有姓名。祭奠者却是你。",
		&"source_hint": "精英掉落",
		&"implemented": true,
		&"elite_drop": true,
		&"shop_offer": false,
	},
	&"expired_return_bell": {
		&"id": &"expired_return_bell",
		&"title": "过期返航铃",
		&"rarity": "Boss级",
		&"description": "每场战斗第一次受到致命伤害时先保留 1 点生命，随后立即执行一次裂解；临界许可可防止该次裂解，否则你可能仍被后续裂解杀死。",
		&"short_description": "首次致命保留 1；可能仍被后续裂解杀死",
		&"flavor": "铃声只在无人返航时响起。它一直在响。",
		&"source_hint": "第七码头事件临时授予",
		&"implemented": true,
		&"elite_drop": false,
		&"shop_offer": false,
	},
}


static func has_relic(relic_id: StringName) -> bool:
	return DEFINITIONS.has(relic_id)


static func get_definition(relic_id: StringName) -> Dictionary:
	return (DEFINITIONS.get(relic_id, {}) as Dictionary).duplicate(true)


static func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for raw_id: Variant in DEFINITIONS.keys():
		ids.append(raw_id as StringName)
	return ids


static func get_elite_drop_ids(owned_relics: Array[StringName] = []) -> Array[StringName]:
	return _eligible_ids(&"elite_drop", owned_relics)


static func get_shop_offer_ids(owned_relics: Array[StringName] = []) -> Array[StringName]:
	return _eligible_ids(&"shop_offer", owned_relics)


static func _eligible_ids(flag: StringName, owned_relics: Array[StringName]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for relic_id: StringName in get_all_ids():
		var definition: Dictionary = DEFINITIONS[relic_id]
		if bool(definition.get(flag, false)) and not owned_relics.has(relic_id):
			ids.append(relic_id)
	return ids
