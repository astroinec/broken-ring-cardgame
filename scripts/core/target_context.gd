class_name TargetContext
extends RefCounted

## 目标解析用的只读快照。
##
## 存在的意义是切断 TargetSelector 与 CombatModel 的循环依赖：
## 规则层负责把当前战斗状态装进这个快照，目标解析层只读它。
## 敌人一律以列表形式提供，因此加入多敌人时无需改动解析逻辑。


var hand: Array[CardData] = []
var sealed_zone: Array[CardData] = []
var draw_pile: Array[CardData] = []
var enemy_names: Array[String] = []
var enemy_hps: Array[int] = []


func enemy_count() -> int:
	return enemy_hps.size()
