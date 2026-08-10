class_name IntentContext
extends RefCounted

## 意图求值上下文。
## 敌人意图是纯数据；数据中的条件需要一份只读快照才能判断是否生效。
## 规则层在展示意图（使用当前手牌）与执行意图（使用回合结束时的手牌快照）时
## 分别构造不同的上下文，保证“显示的意图”与“实际结算的意图”一致。


var devour_record_type: int = -1
var reverse_record_type: int = -1
var stone_shell_broken: bool = false
var player_hand_has_status: bool = false
var player_has_missing_name: bool = false


func devour_type_display_name() -> String:
	return CardData.type_display_name(devour_record_type)


func reverse_type_display_name() -> String:
	return CardData.type_display_name(reverse_record_type)
