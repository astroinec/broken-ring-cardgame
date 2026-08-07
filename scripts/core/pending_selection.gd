class_name PendingSelection
extends RefCounted

## 待选择请求（pending selection）。
##
## 规则层是唯一真相源：当一张牌需要玩家指定目标时，规则层不会替玩家决定，
## 而是把这张牌挂起并生成一个 PendingSelection。表现层读取它进入选择模式，
## 然后只能调用 CombatModel.resolve_pending_selection() 或
## cancel_pending_selection() 两个入口。UI 不持有任何规则状态。
##
##【取消规则】玩家取消时，该牌不结算：
##   1. 返还本次已支付的稳定度；
##   2. 已消耗的缺名层数原样返还；
##   3.卡牌放回手牌原位置；
##   4. 不计入本回合出牌数，不更新回响快照，不产生任何效果。
## 因此取消是完全无痕的，等价于从未点击这张牌。


var card: CardData = null
var hand_index: int = 0
var paid_cost: int = 0
var refunded_missing_name_type: int = -1
var effects: Array[CardEffect] = []
var effect_index: int = 0
var target_kind: TargetSelector.Kind = TargetSelector.Kind.HAND_CARD
var target_filter: TargetSelector.Filter = TargetSelector.Filter.NONE
var target_scope: int = 0
var prompt: String = ""


func describe() -> String:
	return "%s｜%s" % [prompt, TargetSelector.describe(target_kind)]
