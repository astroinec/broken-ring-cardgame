class_name EnemyDefinition
extends RefCounted

## 单个敌人的完整数据描述。


enum IntentMode {
	SEQUENCE,        ## 按固定顺序循环意图（大多数敌人）
	REVERSE_RECORD,  ## 依据“倒读记录”选择意图（倒读者）
}

## 敌人特性开关，全部由数据声明，规则层按特性执行通用逻辑。
const TRAIT_DEVOUR: StringName = &"devour"            ## 吞字记录
const TRAIT_STONE_SHELL: StringName = &"stone_shell"  ## 石壳与同式适应
const TRAIT_REVERSE_READ: StringName = &"reverse_read"## 倒读记录
const TRAIT_BINDING: StringName = &"binding"          ## 装订被动
const TRAIT_NAME_ERASER: StringName = &"name_eraser"  ## 删名者两阶段规则

var id: StringName = &""
var display_name: String = ""
var hp_min: int = 1
var hp_max: int = 1
var tier: String = "普通"
var intent_mode: IntentMode = IntentMode.SEQUENCE
var intents: Array[EnemyIntent] = []
var traits: Array[StringName] = []
var stone_shell_initial: int = 0
var stone_shell_regen: int = 0
var stone_shell_adapt_block: int = 0
var binding_draw_threshold: int = 0
var binding_card_id: StringName = &""
var phase_intent_ranges: Dictionary = {}
var intro_line: String = ""


static func from_data(enemy_id: StringName, data: Dictionary) -> EnemyDefinition:
	var definition: EnemyDefinition = EnemyDefinition.new()
	definition.id = enemy_id
	definition.display_name = str(data.get(&"name", ""))
	definition.hp_min = int(data.get(&"hp_min", 1))
	definition.hp_max = int(data.get(&"hp_max", definition.hp_min))
	definition.tier = str(data.get(&"tier", "普通"))
	definition.intent_mode = int(data.get(&"intent_mode", IntentMode.SEQUENCE)) as IntentMode
	definition.stone_shell_initial = int(data.get(&"stone_shell_initial", 0))
	definition.stone_shell_regen = int(data.get(&"stone_shell_regen", 0))
	definition.stone_shell_adapt_block = int(data.get(&"stone_shell_adapt_block", 0))
	definition.binding_draw_threshold = int(data.get(&"binding_draw_threshold", 0))
	if data.has(&"binding_card_id"):
		definition.binding_card_id = data[&"binding_card_id"]
	definition.phase_intent_ranges = (data.get(&"phase_intent_ranges", {}) as Dictionary).duplicate(true)
	definition.intro_line = str(data.get(&"intro_line", ""))
	var raw_traits: Array = data.get(&"traits", [])
	for raw_trait: Variant in raw_traits:
		definition.traits.append(raw_trait as StringName)
	var raw_intents: Array = data.get(&"intents", [])
	for raw_intent: Variant in raw_intents:
		definition.intents.append(EnemyIntent.from_data(raw_intent as Dictionary))
	return definition


func has_trait(trait_id: StringName) -> bool:
	return traits.has(trait_id)


func intent_count() -> int:
	return intents.size()


func intent_count_for_phase(phase: int) -> int:
	var range_data: Array = phase_intent_ranges.get(phase, [])
	return intents.size() if range_data.size() != 2 else int(range_data[1])


## 顺序模式下按索引取意图；倒读模式下按记录类别取意图。
func select_intent(intent_index: int, reverse_record_type: int, phase: int = 0) -> EnemyIntent:
	if intents.is_empty():
		return null
	if intent_mode == IntentMode.REVERSE_RECORD:
		for intent: EnemyIntent in intents:
			if intent.matches_reverse_record(reverse_record_type):
				return intent
		return intents[0]
	var range_data: Array = phase_intent_ranges.get(phase, [])
	if range_data.size() == 2:
		var offset: int = int(range_data[0])
		var count: int = int(range_data[1])
		return intents[offset + intent_index % count]
	return intents[intent_index % intents.size()]


func is_valid() -> bool:
	if id == &"" or display_name.is_empty():
		return false
	if hp_min <= 0 or hp_max < hp_min:
		return false
	if intents.is_empty():
		return false
	for intent: EnemyIntent in intents:
		if not intent.is_valid():
			return false
	if intent_mode == IntentMode.REVERSE_RECORD:
		# 倒读模式必须覆盖“无记录”兜底分支，否则玩家不出牌时无意图可选。
		var has_fallback: bool = false
		for intent: EnemyIntent in intents:
			if intent.requires_reverse_record == EnemyIntent.REVERSE_REQUIREMENT_NONE:
				has_fallback = true
		if not has_fallback:
			return false
	if has_trait(TRAIT_STONE_SHELL) and stone_shell_initial <= 0:
		return false
	if has_trait(TRAIT_BINDING) and (binding_draw_threshold <= 0 or binding_card_id == &""):
		return false
	return true
