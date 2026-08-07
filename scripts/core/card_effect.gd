class_name CardEffect
extends RefCounted


enum Kind {
	DAMAGE_ENEMY,
	GAIN_BLOCK,
	DRAW_CARDS,
	GAIN_INSTABILITY,
	REDUCE_INSTABILITY,
	SEAL_CARD,
	ECHO_ATTACK,
	ECHO_BLOCK,
	DISCARD_CHOSEN_FROM_TOP,
	PREVENT_FRACTURE,
	DISSOLUTION_ATTACK,
	PREWRITE_COPY,
	UNSEAL_CHOSEN,
	COPY_PREVIOUS,
}

const NO_TARGET_SCOPE: int = 0

var kind: Kind
var amount: int
var factor: int

## 该效果需要的目标类型。攻击类默认指向唯一敌人；
## 需要玩家点选的效果（索引重排、预写结局、开封令）在此声明卡牌类目标，
## 规则层遇到它们时会挂起卡牌并生成待选择请求。
var target_kind: TargetSelector.Kind = TargetSelector.Kind.SINGLE_ENEMY
var target_filter: TargetSelector.Filter = TargetSelector.Filter.NONE
var target_scope: int = NO_TARGET_SCOPE
var prompt: String = ""


func _init(p_kind: Kind, p_amount: int, p_factor: int = 0) -> void:
	kind = p_kind
	amount = p_amount
	factor = p_factor


## 链式配置目标，便于在卡牌定义处一行写完。
func with_target(
	p_kind: TargetSelector.Kind,
	p_prompt: String,
	p_filter: TargetSelector.Filter = TargetSelector.Filter.NONE,
	p_scope: int = NO_TARGET_SCOPE
) -> CardEffect:
	target_kind = p_kind
	target_filter = p_filter
	target_scope = p_scope
	prompt = p_prompt
	return self


func requires_player_choice() -> bool:
	return TargetSelector.requires_player_choice(target_kind)
