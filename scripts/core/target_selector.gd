class_name TargetSelector
extends RefCounted

## 统一目标解析层。
##
## 规则层任何需要“指向某个东西”的效果都必须经过这里，不再在各处写死
## `enemy_hp` 或 `hand[0]`。所有查询都基于 TargetContext 快照，
## 敌人目标一律返回“逻辑敌人索引”，因此加入多敌人时只需让规则层
## 在快照里填入更多敌人，本文件与全部调用点都不需要修改。


enum Kind {
	SINGLE_ENEMY,      ## 唯一敌人（单体战斗的默认攻击目标）
	LOWEST_HP_ENEMY,   ## 生命最低敌人（倒计刻痕、回响改指）
	HAND_CARD,         ## 手牌中某张牌（预写结局）
	SEALED_CARD,       ## 封存区某张牌（开封令）
	DRAW_PILE_TOP,     ## 抽牌堆顶若干张中的一张（索引重排）
}

enum Filter {
	NONE,
	NON_EXHAUST,       ## 排除会消逝的牌
	PLAYABLE,          ## 排除状态牌
}

const NO_TARGET: int = -1


static func is_enemy_kind(kind: Kind) -> bool:
	return kind == Kind.SINGLE_ENEMY or kind == Kind.LOWEST_HP_ENEMY


## 需要玩家点击的目标类型；敌人目标由规则层自动解析。
static func requires_player_choice(kind: Kind) -> bool:
	return not is_enemy_kind(kind)


static func describe(kind: Kind) -> String:
	match kind:
		Kind.SINGLE_ENEMY:
			return "敌人"
		Kind.LOWEST_HP_ENEMY:
			return "生命最低的敌人"
		Kind.HAND_CARD:
			return "手牌中的一张牌"
		Kind.SEALED_CARD:
			return "封存区的一张牌"
		Kind.DRAW_PILE_TOP:
			return "抽牌堆顶的一张牌"
	return "未知目标"


## 敌人目标解析：返回逻辑敌人索引，没有存活敌人时返回 NO_TARGET。
static func resolve_enemy(kind: Kind, context: TargetContext) -> int:
	match kind:
		Kind.SINGLE_ENEMY:
			for index: int in range(context.enemy_count()):
				if context.enemy_hps[index] > 0:
					return index
			return NO_TARGET
		Kind.LOWEST_HP_ENEMY:
			var best: int = NO_TARGET
			for index: int in range(context.enemy_count()):
				if context.enemy_hps[index] <= 0:
					continue
				if best == NO_TARGET or context.enemy_hps[index] < context.enemy_hps[best]:
					best = index
			return best
	assert(false, "resolve_enemy 只接受敌人类目标：%d" % kind)
	return NO_TARGET


## 卡牌类目标的候选索引列表；scope 限制可见范围（例如抽牌堆顶 3 张）。
static func candidate_indices(
	kind: Kind, context: TargetContext, filter: Filter = Filter.NONE, scope: int = 0
) -> Array[int]:
	var indices: Array[int] = []
	match kind:
		Kind.HAND_CARD:
			for index: int in range(context.hand.size()):
				if _passes_filter(context.hand[index], filter):
					indices.append(index)
		Kind.SEALED_CARD:
			for index: int in range(context.sealed_zone.size()):
				if _passes_filter(context.sealed_zone[index], filter):
					indices.append(index)
		Kind.DRAW_PILE_TOP:
			# 抽牌堆以数组末尾为堆顶，因此从后往前取 scope 张。
			var pile_size: int = context.draw_pile.size()
			var visible: int = pile_size if scope <= 0 else mini(scope, pile_size)
			for offset: int in range(visible):
				var index: int = pile_size - 1 - offset
				if _passes_filter(context.draw_pile[index], filter):
					indices.append(index)
		Kind.SINGLE_ENEMY, Kind.LOWEST_HP_ENEMY:
			for index: int in range(context.enemy_count()):
				if context.enemy_hps[index] > 0:
					indices.append(index)
	return indices


static func candidate_labels(
	kind: Kind, context: TargetContext, filter: Filter = Filter.NONE, scope: int = 0
) -> Array[String]:
	var labels: Array[String] = []
	for index: int in candidate_indices(kind, context, filter, scope):
		labels.append(label_for(kind, context, index))
	return labels


static func label_for(kind: Kind, context: TargetContext, index: int) -> String:
	match kind:
		Kind.HAND_CARD:
			if index < 0 or index >= context.hand.size():
				return "无效手牌"
			return _card_label(context.hand[index])
		Kind.SEALED_CARD:
			if index < 0 or index >= context.sealed_zone.size():
				return "无效封存牌"
			var sealed_card: CardData = context.sealed_zone[index]
			return "%s（倒计时 %d）" % [_card_label(sealed_card), sealed_card.sealed_turns]
		Kind.DRAW_PILE_TOP:
			if index < 0 or index >= context.draw_pile.size():
				return "无效牌堆位置"
			var depth: int = context.draw_pile.size() - index
			return "第%d张 %s" % [depth, _card_label(context.draw_pile[index])]
		Kind.SINGLE_ENEMY, Kind.LOWEST_HP_ENEMY:
			if index < 0 or index >= context.enemy_count():
				return "无效敌人"
			return "%s（生命 %d）" % [context.enemy_names[index], context.enemy_hps[index]]
	return "未知目标"


static func is_valid_choice(
	kind: Kind, context: TargetContext, index: int, filter: Filter = Filter.NONE, scope: int = 0
) -> bool:
	return candidate_indices(kind, context, filter, scope).has(index)


static func _passes_filter(card: CardData, filter: Filter) -> bool:
	match filter:
		Filter.NON_EXHAUST:
			return not card.exhausts
		Filter.PLAYABLE:
			return card.card_type != CardData.CardType.STATUS
	return true


static func _card_label(card: CardData) -> String:
	return "%s[%s]" % [card.title, card.type_name()]
