class_name EnemyIntent
extends RefCounted

## 单条敌人意图：一个中文名、一段中文描述模板与若干原子操作。
## “倒读者”这类会依据记录改变行为的敌人，用 requires_reverse_record 声明
## 该意图仅在记录到指定类别时可用，规则层在选择意图时做过滤。


const NO_REVERSE_REQUIREMENT: int = -99
const REVERSE_REQUIREMENT_NONE: int = -1

var id: StringName = &""
var display_name: String = ""
var description: String = ""
var operations: Array[EnemyOperation] = []
var requires_reverse_record: int = NO_REVERSE_REQUIREMENT


static func from_data(data: Dictionary) -> EnemyIntent:
	var intent: EnemyIntent = EnemyIntent.new()
	intent.id = data.get(&"id", &"")
	intent.display_name = str(data.get(&"name", ""))
	intent.description = str(data.get(&"description", ""))
	intent.requires_reverse_record = int(data.get(&"requires_reverse_record", NO_REVERSE_REQUIREMENT))
	var raw_operations: Array = data.get(&"operations", [])
	for raw: Variant in raw_operations:
		intent.operations.append(EnemyOperation.from_data(raw as Dictionary))
	return intent


func matches_reverse_record(recorded_type: int) -> bool:
	if requires_reverse_record == NO_REVERSE_REQUIREMENT:
		return true
	return requires_reverse_record == recorded_type


func describe(context: IntentContext) -> String:
	var text: String = description
	if text.is_empty():
		var parts: Array[String] = []
		for operation: EnemyOperation in operations:
			if not operation.is_active(context):
				continue
			var piece: String = operation.describe(context)
			if not piece.is_empty():
				parts.append(piece)
		text = "；".join(parts)
	else:
		for operation: EnemyOperation in operations:
			if operation.label.is_empty():
				continue
			var token: String = "{%s}" % operation.label
			if not text.contains(token):
				continue
			text = text.replace(token, operation.describe(context) if operation.is_active(context) else "")
	text = text.replace(
		EnemyOperation.TYPE_PLACEHOLDER, context.devour_type_display_name()
	)
	if display_name.is_empty():
		return text
	if text.is_empty():
		return display_name
	return "%s：%s" % [display_name, text]


func active_operations(context: IntentContext) -> Array[EnemyOperation]:
	var active: Array[EnemyOperation] = []
	for operation: EnemyOperation in operations:
		if operation.is_active(context):
			active.append(operation)
	return active


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or operations.is_empty():
		return false
	for operation: EnemyOperation in operations:
		if not operation.is_valid():
			return false
	return true
