class_name EnemyCatalog
extends RefCounted

## 数据驱动敌人目录。
##
## CombatModel 不再内联任何敌人的行为分支：所有生命范围、意图序列、
## 中文描述、效果与特性都写在 DEFINITIONS 里，规则层只按数据执行。
##
## PATH_ENEMY_IDS 保持主线六个路径节点原有的敌人与数值，
## 确保同一固定种子下的体验与 v0.4 完全一致。
## TEST_ARENA_ENEMY_IDS 是机制测试场可选择的对手列表。

## 主线路径节点 1～6 使用的敌人，索引 0 对应节点 1。
const PATH_ENEMY_IDS: Array[StringName] = [
	&"nameless_dummy",
	&"calibration_guard",
	&"rift_gauge",
	&"time_hammer",
	&"echo_discriminator",
	&"word_eater",
]

## 机制测试场可选对手：吞字巢穴的拾字虫加上三个正式敌人。
const TEST_ARENA_ENEMY_IDS: Array[StringName] = [
	&"word_eater",
	&"hollow_name_guard",
	&"reverse_reader",
	&"binding_instrument",
]

const DEFINITIONS: Dictionary = {
	# ---------- 主线路径节点敌人（数值与 v0.4 保持一致） ----------
	&"nameless_dummy": {
		&"name": "无名训练体", &"tier": "训练", &"hp_min": 18, &"hp_max": 18,
		&"intro_line": "墙上的旧告示只剩两行：出手，或护住自己。",
		&"intents": [
			{
				&"id": &"practice_swing", &"name": "练习挥击", &"description": "造成 5 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 5, &"action": "练习挥击"},
				],
			},
		],
	},
	&"calibration_guard": {
		&"name": "校准守卫", &"tier": "普通", &"hp_min": 24, &"hp_max": 24,
		&"intro_line": "守卫抬起武器之前，胸前石片会先显出下一步动作。",
		&"intents": [
			{
				&"id": &"probe", &"name": "试探", &"description": "造成 5 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 5, &"action": "试探"},
				],
			},
			{
				&"id": &"raise_shield", &"name": "架盾", &"description": "获得 6 点格挡",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 6,
						&"log": "{enemy}架起护盾，获得 6 格挡。",
					},
				],
			},
			{
				&"id": &"charge_up", &"name": "蓄力", &"description": "准备下一次重击",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.CHARGE,
						&"log": "{enemy}完成蓄力，下一意图是校准重击。",
					},
				],
			},
			{
				&"id": &"calibration_smash", &"name": "校准重击", &"description": "造成 11 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 11, &"action": "校准重击"},
				],
			},
		],
	},
	&"rift_gauge": {
		&"name": "裂隙测量体", &"tier": "普通", &"hp_min": 28, &"hp_max": 28,
		&"intro_line": "井壁渗出的蓝光让规则变得更锋利，也更不稳定。",
		&"intents": [
			{
				&"id": &"rift_pulse_low", &"name": "裂隙脉冲", &"description": "造成 6 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 6, &"action": "裂隙脉冲"},
				],
			},
			{
				&"id": &"rift_pulse_high", &"name": "裂隙脉冲", &"description": "造成 7 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 7, &"action": "裂隙脉冲"},
				],
			},
		],
	},
	&"time_hammer": {
		&"name": "刻时重锤", &"tier": "普通", &"hp_min": 34, &"hp_max": 34,
		&"intro_line": "这里的动作总在数拍之后才抵达。远处的重锤节奏固定。",
		&"intents": [
			{
				&"id": &"light_tap", &"name": "轻敲", &"description": "造成 5 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 5, &"action": "轻敲"},
				],
			},
			{
				&"id": &"predictable_smash", &"name": "可预测重击", &"description": "造成 14 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 14, &"action": "可预测重击"},
				],
			},
		],
	},
	&"echo_discriminator": {
		&"name": "回声鉴别器", &"tier": "普通", &"hp_min": 36, &"hp_max": 36,
		&"intro_line": "第二个声音会复述第一个动作，却从不复述它的原因。",
		&"intents": [
			{
				&"id": &"echo_impact", &"name": "回声冲击", &"description": "造成 7 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 7, &"action": "回声冲击"},
				],
			},
			{
				&"id": &"echo_barrier", &"name": "回声屏障", &"description": "获得 5 点格挡",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 5,
						&"log": "{enemy}展开回声屏障，获得 5 格挡。",
					},
				],
			},
		],
	},
	&"word_eater": {
		&"name": "拾字虫", &"tier": "普通", &"hp_min": 40, &"hp_max": 40,
		&"traits": [EnemyDefinition.TRAIT_DEVOUR],
		&"intro_line": "虫腹里滚动着你刚使用的文字。它似乎在等待同类词句。",
		&"intents": [
			{
				&"id": &"gnaw", &"name": "啃噬", &"description": "造成 6 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 6, &"action": "啃噬"},
				],
			},
			{
				&"id": &"steal_word", &"name": "偷字",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.APPLY_MISSING_NAME_RECORDED, &"amount": 1,
						&"condition": EnemyOperation.Condition.HAS_DEVOUR_RECORD,
						&"label": "施加 1 层{type}缺名",
						&"log": "偷字：你获得 1 层{type}缺名；下一张该类别牌费用 +1。",
					},
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 5,
						&"condition": EnemyOperation.Condition.NO_DEVOUR_RECORD,
						&"label": "未记录类别，获得 5 格挡",
						&"log": "偷字未找到记录：{enemy}获得 5 格挡。",
					},
				],
			},
			{
				&"id": &"spit_ink", &"name": "吐墨", &"description": "造成 4×2 点伤害，清除记录",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 4, &"times": 2,
						&"action": "吐墨",
					},
					{
						&"kind": EnemyOperation.Kind.CLEAR_DEVOUR_RECORD,
						&"log": "{enemy}清除了吞字记录。",
					},
				],
			},
		],
	},

	# ---------- 正式敌人 ----------
	&"hollow_name_guard": {
		&"name": "空名卫士", &"tier": "普通", &"hp_min": 34, &"hp_max": 38,
		&"traits": [EnemyDefinition.TRAIT_STONE_SHELL],
		&"stone_shell_initial": 8, &"stone_shell_regen": 4, &"stone_shell_adapt_block": 5,
		&"intro_line": "请出示姓名。",
		&"intents": [
			{
				&"id": &"block_road", &"name": "封路", &"description": "获得 8 点格挡；下回合攻击强化 3",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 8,
						&"log": "{enemy}封住通路，获得 8 格挡。",
					},
					{
						&"kind": EnemyOperation.Kind.EMPOWER_NEXT_ATTACK, &"amount": 3,
						&"log": "{enemy}的下一次攻击被强化 3 点。",
					},
				],
			},
			{
				&"id": &"stele_blade", &"name": "碑刃",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 15,
						&"condition": EnemyOperation.Condition.STONE_SHELL_INTACT,
						&"action": "碑刃（石壳完整）", &"label": "造成 15 点伤害（石壳未被打破）",
					},
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 11,
						&"condition": EnemyOperation.Condition.STONE_SHELL_BROKEN,
						&"action": "碑刃", &"label": "造成 11 点伤害",
					},
				],
			},
			{
				&"id": &"nameless_edict", &"name": "无名敕令",
				&"description": "将 1 张《空页》放入抽牌堆",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ADD_CARD_TO_DRAW_PILE, &"amount": 1,
						&"card_id": &"blank_page",
						&"log": "{enemy}颁下无名敕令：1 张《空页》进入抽牌堆。",
					},
				],
			},
		],
	},
	&"reverse_reader": {
		&"name": "倒读者", &"tier": "普通", &"hp_min": 68, &"hp_max": 72,
		&"traits": [EnemyDefinition.TRAIT_REVERSE_READ],
		&"intent_mode": EnemyDefinition.IntentMode.REVERSE_RECORD,
		&"intro_line": "请从最后一句开始陈述。",
		&"intents": [
			{
				&"id": &"reverse_attack", &"name": "倒读·攻式",
				&"requires_reverse_record": CardData.CardType.ATTACK,
				&"description": "获得 10 点格挡并反击 4 点伤害",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 10,
						&"log": "{enemy}倒读你的攻式，获得 10 格挡。",
					},
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 4, &"action": "倒读反击"},
				],
			},
			{
				&"id": &"reverse_defense", &"name": "倒读·守式",
				&"requires_reverse_record": CardData.CardType.DEFENSE,
				&"description": "施加 2 回合虚弱并造成 6 点伤害",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.APPLY_WEAK, &"amount": 2,
						&"log": "{enemy}倒读你的守式：你获得 2 回合虚弱。",
					},
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 6, &"action": "倒读压制"},
				],
			},
			{
				&"id": &"reverse_law", &"name": "倒读·律式",
				&"requires_reverse_record": CardData.CardType.LAW,
				&"description": "造成 5×2 点伤害并施加 1 层律式缺名",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 5, &"times": 2,
						&"action": "倒读诵读",
					},
					{
						&"kind": EnemyOperation.Kind.APPLY_MISSING_NAME_FIXED, &"amount": 1,
						&"card_type": CardData.CardType.LAW,
						&"log": "{enemy}删去一个律式名字：你获得 1 层律式缺名。",
					},
				],
			},
			{
				&"id": &"reverse_confused", &"name": "困惑",
				&"requires_reverse_record": EnemyIntent.REVERSE_REQUIREMENT_NONE,
				&"description": "没有可倒读的记录，自身失去 8 生命",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.SELF_DAMAGE, &"amount": 8,
						&"log": "{enemy}没有可倒读的句子，陷入困惑并失去 8 生命。",
					},
				],
			},
		],
	},
	&"binding_instrument": {
		&"name": "装订刑具", &"tier": "精英", &"hp_min": 88, &"hp_max": 88,
		&"traits": [EnemyDefinition.TRAIT_BINDING],
		&"binding_draw_threshold": 3, &"binding_card_id": &"redaction",
		&"intro_line": "资产装订流程开始。请保持页序。",
		&"intents": [
			{
				&"id": &"perforate", &"name": "穿孔", &"description": "造成 7×2 点伤害",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 7, &"times": 2,
						&"action": "穿孔",
					},
				],
			},
			{
				&"id": &"bind", &"name": "装订",
				&"description": "将 2 张《空页》放入抽牌堆；自身获得 8 格挡",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ADD_CARD_TO_DRAW_PILE, &"amount": 2,
						&"card_id": &"blank_page",
						&"log": "{enemy}装订书页：2 张《空页》进入抽牌堆。",
					},
					{
						&"kind": EnemyOperation.Kind.GAIN_BLOCK, &"amount": 8,
						&"log": "{enemy}收紧夹板，获得 8 格挡。",
					},
				],
			},
			{
				&"id": &"press_page", &"name": "压页",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 18, &"action": "压页",
						&"label": "造成 18 点伤害",
					},
					{
						&"kind": EnemyOperation.Kind.ATTACK, &"amount": 5,
						&"condition": EnemyOperation.Condition.PLAYER_HAND_HAS_STATUS,
						&"action": "压页（状态牌加压）",
						&"label": "手牌存在状态牌时额外造成 5 点伤害",
					},
				],
			},
			{
				&"id": &"unbind_spine", &"name": "拆脊",
				&"description": "施加 2 回合脆弱；移除自身所有减益",
				&"operations": [
					{
						&"kind": EnemyOperation.Kind.APPLY_VULNERABLE, &"amount": 2,
						&"log": "{enemy}拆开脊骨：你获得 2 回合脆弱。",
					},
					{
						&"kind": EnemyOperation.Kind.CLEANSE_SELF,
						&"log": "{enemy}移除了自身所有减益。",
					},
				],
			},
		],
	},

	# ---------- 数值模拟专用敌人：不进入 PATH_ENEMY_IDS 或 TEST_ARENA_ENEMY_IDS ----------
	&"pressure_archivist": {
		&"name": "压力校勘体", &"tier": "测试", &"hp_min": 112, &"hp_max": 112,
		&"intro_line": "仅用于固定种子数值校准。",
		&"intents": [
			{
				&"id": &"pressure_probe", &"name": "高压试探", &"description": "造成 9 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 9, &"action": "高压试探"},
				],
			},
			{
				&"id": &"pressure_pulse", &"name": "高压脉冲", &"description": "造成 10 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 10, &"action": "高压脉冲"},
				],
			},
			{
				&"id": &"pressure_smash", &"name": "高压重击", &"description": "造成 20 点伤害",
				&"operations": [
					{&"kind": EnemyOperation.Kind.ATTACK, &"amount": 20, &"action": "高压重击"},
				],
			},
		],
	},
}


static func has_enemy(enemy_id: StringName) -> bool:
	return DEFINITIONS.has(enemy_id)


static func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in DEFINITIONS.keys():
		ids.append(key as StringName)
	return ids


static func create(enemy_id: StringName) -> EnemyDefinition:
	var data: Dictionary = DEFINITIONS.get(enemy_id, {})
	assert(not data.is_empty(), "未知敌人定义：%s" % enemy_id)
	return EnemyDefinition.from_data(enemy_id, data)


## 路径节点编号（1 起）对应的敌人 id。
static func enemy_id_for_path_stage(stage: int) -> StringName:
	var index: int = clampi(stage, 1, PATH_ENEMY_IDS.size()) - 1
	return PATH_ENEMY_IDS[index]


static func get_display_name(enemy_id: StringName) -> String:
	var data: Dictionary = DEFINITIONS.get(enemy_id, {})
	return str(data.get(&"name", "未知敌人"))
