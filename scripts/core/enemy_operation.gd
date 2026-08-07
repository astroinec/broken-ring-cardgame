class_name EnemyOperation
extends RefCounted

## 敌人意图中的单个原子操作。
## 目录里用纯 Dictionary 描述，from_data() 负责转成强类型对象；
## 规则层只按 kind 执行，不再为某个敌人写 match 分支。


enum Kind {
	ATTACK,
	GAIN_BLOCK,
	CHARGE,
	EMPOWER_NEXT_ATTACK,
	APPLY_MISSING_NAME_RECORDED,
	APPLY_MISSING_NAME_FIXED,
	CLEAR_DEVOUR_RECORD,
	ADD_CARD_TO_DRAW_PILE,
	ADD_CARD_TO_DISCARD_PILE,
	APPLY_VULNERABLE,
	APPLY_WEAK,
	CLEANSE_SELF,
	SELF_DAMAGE,
	RESTORE_STONE_SHELL,
}

enum Condition {
	ALWAYS,
	HAS_DEVOUR_RECORD,
	NO_DEVOUR_RECORD,
	STONE_SHELL_INTACT,
	STONE_SHELL_BROKEN,
	PLAYER_HAND_HAS_STATUS,
}

const TYPE_PLACEHOLDER: String = "{type}"
const ENEMY_PLACEHOLDER: String = "{enemy}"

var kind: Kind = Kind.ATTACK
var amount: int = 0
var times: int = 1
var condition: Condition = Condition.ALWAYS
var label: String = ""
var action_name: String = ""
var log_text: String = ""
var card_id: StringName = &""
var card_type: int = -1


static func from_data(data: Dictionary) -> EnemyOperation:
	var operation: EnemyOperation = EnemyOperation.new()
	operation.kind = int(data.get(&"kind", Kind.ATTACK)) as Kind
	operation.amount = int(data.get(&"amount", 0))
	operation.times = maxi(1, int(data.get(&"times", 1)))
	operation.condition = int(data.get(&"condition", Condition.ALWAYS)) as Condition
	operation.label = str(data.get(&"label", ""))
	operation.action_name = str(data.get(&"action", ""))
	operation.log_text = str(data.get(&"log", ""))
	if data.has(&"card_id"):
		operation.card_id = data[&"card_id"]
	operation.card_type = int(data.get(&"card_type", -1))
	return operation


func is_active(context: IntentContext) -> bool:
	match condition:
		Condition.ALWAYS:
			return true
		Condition.HAS_DEVOUR_RECORD:
			return context.devour_record_type >= 0
		Condition.NO_DEVOUR_RECORD:
			return context.devour_record_type < 0
		Condition.STONE_SHELL_INTACT:
			return not context.stone_shell_broken
		Condition.STONE_SHELL_BROKEN:
			return context.stone_shell_broken
		Condition.PLAYER_HAND_HAS_STATUS:
			return context.player_hand_has_status
	return true


func describe(context: IntentContext) -> String:
	if label.is_empty():
		return ""
	return label.replace(TYPE_PLACEHOLDER, context.devour_type_display_name())


func resolve_log_text(enemy_name: String, context: IntentContext) -> String:
	if log_text.is_empty():
		return ""
	return log_text.replace(ENEMY_PLACEHOLDER, enemy_name).replace(
		TYPE_PLACEHOLDER, context.devour_type_display_name()
	)


func is_valid() -> bool:
	if amount < 0 or times < 1:
		return false
	match kind:
		Kind.ATTACK, Kind.GAIN_BLOCK, Kind.SELF_DAMAGE, Kind.EMPOWER_NEXT_ATTACK:
			return amount > 0
		Kind.ADD_CARD_TO_DRAW_PILE, Kind.ADD_CARD_TO_DISCARD_PILE:
			return card_id != &"" and amount > 0
		Kind.APPLY_MISSING_NAME_FIXED:
			return amount > 0 and card_type >= 0
		Kind.APPLY_MISSING_NAME_RECORDED, Kind.APPLY_VULNERABLE, Kind.APPLY_WEAK:
			return amount > 0
		Kind.RESTORE_STONE_SHELL:
			return amount > 0
	return true
