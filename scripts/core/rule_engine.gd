class_name RuleEngine
extends RefCounted

## 遗物与状态的规则优先级系统。
##
## 所有可被修正的数值（伤害、格挡、抽牌、费用、裂解）都必须经过本管线，
## 不允许调用方自行加减。阶段顺序是硬性约定，脚本执行先后不得影响结果：
##
##   Phase.BASE          基础值（卡牌或敌人意图写明的数字）
##   Phase.ATTACKER      攻击方状态修正（力量+X、虚弱 -25%）
##   Phase.DEFENDER      受击方修正（脆弱 +50%）
##   Phase.RELIC         遗物修正（裂纹稳定器、无字藏书票等）
##   Phase.CLAMP         上限/下限裁剪（不得为负、手牌上限等）
##
## 同一阶段内部按“加法 →乘法”固定次序结算，乘法结果一律向下取整。


enum Phase {
	BASE,
	ATTACKER,
	DEFENDER,
	RELIC,
	CLAMP,
}

enum Channel {
	DAMAGE_TO_ENEMY,
	DAMAGE_TO_PLAYER,
	BLOCK,
	DRAW,
	COST,
	FRACTURE,
}

const PHASE_ORDER: Array[Phase] = [
	Phase.BASE, Phase.ATTACKER, Phase.DEFENDER, Phase.RELIC, Phase.CLAMP
]

const WEAK_MULTIPLIER: float = 0.75
const VULNERABLE_MULTIPLIER: float = 1.5

## 兼容旧调用点的只读代理；遗物定义的唯一真相源是 RelicCatalog。
static var RELIC_DEFINITIONS: Dictionary = RelicCatalog.DEFINITIONS

var player_strength: int = 0
var player_weak_turns: int = 0
var player_vulnerable_turns: int = 0
var enemy_vulnerable_turns: int = 0
var enemy_strength: int = 0
var enemy_next_attack_bonus: int = 0

var relics: Array[StringName] = []
var crack_stabilizer_used: bool = false
var bookplate_used: bool = false
var calibrator_red_pen_used: bool = false
var delay_gear_used: bool = false
var echo_hyoid_used_this_turn: bool = false
var blank_epitaph_used: bool = false
var expired_return_bell_used: bool = false

var _relic_trigger_counts: Dictionary = {}
var _relic_net_benefits: Dictionary = {}

## 最近一次计算的阶段轨迹，供日志与测试验证顺序。
var last_trace: Array[String] = []


func reset_for_battle(p_relics: Array[StringName]) -> void:
	relics = p_relics.duplicate()
	player_strength = 0
	player_weak_turns = 0
	player_vulnerable_turns = 0
	enemy_vulnerable_turns = 0
	enemy_strength = 0
	enemy_next_attack_bonus = 0
	crack_stabilizer_used = false
	bookplate_used = false
	calibrator_red_pen_used = false
	delay_gear_used = false
	echo_hyoid_used_this_turn = false
	blank_epitaph_used = false
	expired_return_bell_used = false
	_relic_trigger_counts.clear()
	_relic_net_benefits.clear()
	last_trace.clear()


func has_relic(relic_id: StringName) -> bool:
	return relics.has(relic_id)


static func relic_title(relic_id: StringName) -> String:
	var definition: Dictionary = RelicCatalog.get_definition(relic_id)
	return str(definition.get(&"title", "未知遗物"))


static func is_relic_implemented(relic_id: StringName) -> bool:
	var definition: Dictionary = RelicCatalog.get_definition(relic_id)
	return bool(definition.get(&"implemented", false))


## 玩家对敌人造成的伤害。is_attack 为 false 时跳过力量/虚弱等攻击状态修正。
func compute_damage_to_enemy(
	base: int, is_attack: bool, upgrade_baseline: int = -1, is_upgraded: bool = false
) -> int:
	last_trace.clear()
	var value: float = float(base)
	var baseline_value: float = float(upgrade_baseline)
	_trace(Phase.BASE, "基础伤害 %d" % base)
	#攻击方阶段内部固定为“先加法后乘法”，因此力量永远在虚弱之前结算。
	if not is_attack:
		_trace(Phase.ATTACKER, "非攻击来源，跳过攻击方状态")
	else:
		if player_strength != 0:
			value += float(player_strength)
			if upgrade_baseline >= 0:
				baseline_value += float(player_strength)
			_trace(Phase.ATTACKER, "力量 %+d → %d" % [player_strength, int(value)])
		if player_weak_turns > 0:
			value = floor(value * WEAK_MULTIPLIER)
			if upgrade_baseline >= 0:
				baseline_value = floor(baseline_value * WEAK_MULTIPLIER)
			_trace(Phase.ATTACKER, "虚弱 ×0.75 → %d" % int(value))
		if player_strength == 0 and player_weak_turns <= 0:
			_trace(Phase.ATTACKER, "无攻击方状态修正")
	if enemy_vulnerable_turns > 0:
		value = floor(value * VULNERABLE_MULTIPLIER)
		if upgrade_baseline >= 0:
			baseline_value = floor(baseline_value * VULNERABLE_MULTIPLIER)
		_trace(Phase.DEFENDER, "敌方脆弱 ×1.5 → %d" % int(value))
	else:
		_trace(Phase.DEFENDER, "目标无受击修正")
	if _can_trigger_red_pen(is_upgraded, int(value), int(baseline_value), upgrade_baseline):
		calibrator_red_pen_used = true
		value += 3.0
		_record_relic_benefit(&"calibrator_red_pen", 3)
		_trace(Phase.RELIC, "校准官的红笔 +3 → %d" % int(value))
	else:
		_trace(Phase.RELIC, "无伤害类遗物修正")
	var result: int = maxi(0, int(value))
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


## 敌人对玩家造成的伤害。
func compute_damage_to_player(base: int, is_attack: bool) -> int:
	last_trace.clear()
	var value: float = float(base)
	_trace(Phase.BASE, "基础伤害 %d" % base)
	if is_attack and enemy_strength != 0:
		value += float(enemy_strength)
		_trace(Phase.ATTACKER, "敌方力量 %+d → %d" % [enemy_strength, int(value)])
	if is_attack and enemy_next_attack_bonus > 0:
		value += float(enemy_next_attack_bonus)
		_trace(Phase.ATTACKER, "敌方蓄力 %+d → %d" % [enemy_next_attack_bonus, int(value)])
	if not is_attack or (enemy_strength == 0 and enemy_next_attack_bonus <= 0):
		_trace(Phase.ATTACKER, "无攻击方加成")
	if is_attack and player_vulnerable_turns > 0:
		value = floor(value * VULNERABLE_MULTIPLIER)
		_trace(Phase.DEFENDER, "你处于脆弱 ×1.5 → %d" % int(value))
	else:
		_trace(Phase.DEFENDER, "你无受击修正")
	_trace(Phase.RELIC, "无受击类遗物修正")
	var result: int = maxi(0, int(value))
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


func compute_block(base: int, upgrade_baseline: int = -1, is_upgraded: bool = false) -> int:
	last_trace.clear()
	_trace(Phase.BASE, "基础格挡 %d" % base)
	_trace(Phase.ATTACKER, "无施加方格挡状态")
	_trace(Phase.DEFENDER, "无受击方格挡状态")
	var value: int = base
	if _can_trigger_red_pen(is_upgraded, value, upgrade_baseline, upgrade_baseline):
		calibrator_red_pen_used = true
		value += 3
		_record_relic_benefit(&"calibrator_red_pen", 3)
		_trace(Phase.RELIC, "校准官的红笔 +3 → %d" % value)
	else:
		_trace(Phase.RELIC, "无格挡类遗物修正")
	var result: int = maxi(0, value)
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


func compute_draw(base: int, hand_size: int, max_hand_size: int) -> int:
	last_trace.clear()
	_trace(Phase.BASE, "基础抽牌 %d" % base)
	_trace(Phase.ATTACKER, "无抽牌状态修正")
	_trace(Phase.DEFENDER, "无抽牌受击修正")
	_trace(Phase.RELIC, "无抽牌数量类遗物修正")
	var room: int = maxi(0, max_hand_size - hand_size)
	var result: int = clampi(base, 0, room)
	_trace(Phase.CLAMP, "手牌上限剩余 %d → %d" % [room, result])
	return result


func compute_cost(base: int, missing_name_stacks: int) -> int:
	last_trace.clear()
	_trace(Phase.BASE, "基础费用 %d" % base)
	var value: int = base
	if missing_name_stacks > 0:
		value += missing_name_stacks
		_trace(Phase.ATTACKER, "缺名 %+d → %d" % [missing_name_stacks, value])
	else:
		_trace(Phase.ATTACKER, "无费用状态修正")
	_trace(Phase.DEFENDER, "无费用受击修正")
	_trace(Phase.RELIC, "无费用类遗物修正")
	var result: int = maxi(0, value)
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


## 裂解伤害。prevented 为真时来自《临界许可》，属于 CLAMP 阶段的强制归零。
func compute_fracture_damage(base: int, prevented: bool) -> int:
	last_trace.clear()
	_trace(Phase.BASE, "基础裂解伤害 %d" % base)
	_trace(Phase.ATTACKER, "裂解不受攻击状态影响")
	_trace(Phase.DEFENDER, "裂解不可被格挡")
	_trace(Phase.RELIC, "无裂解伤害类遗物修正")
	var result: int = 0 if prevented else maxi(0, base)
	_trace(Phase.CLAMP, "临界许可归零" if prevented else "裁剪至不小于 0 → %d" % result)
	return result


func compute_unblocked_status_damage(base: int) -> int:
	last_trace.clear()
	_trace(Phase.BASE, "基础状态伤害 %d" % base)
	_trace(Phase.ATTACKER, "状态伤害不受攻击状态影响")
	_trace(Phase.DEFENDER, "状态伤害不可被格挡")
	_trace(Phase.RELIC, "无状态伤害类遗物修正")
	var result: int = maxi(0, base)
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


## 获得不稳定。裂纹稳定器在RELIC 阶段生效，每场战斗仅首次。
func compute_instability_gain(base: int) -> int:
	last_trace.clear()
	var value: int = base
	_trace(Phase.BASE, "基础超载 %d" % base)
	_trace(Phase.ATTACKER, "无超载状态修正")
	_trace(Phase.DEFENDER, "无超载受击修正")
	if base > 0 and not crack_stabilizer_used and has_relic(&"crack_stabilizer"):
		crack_stabilizer_used = true
		value -= 1
		_record_relic_benefit(&"crack_stabilizer", 1)
		_trace(Phase.RELIC, "裂纹稳定器 -1 → %d" % value)
	else:
		_trace(Phase.RELIC, "无超载类遗物修正")
	var result: int = maxi(0, value)
	_trace(Phase.CLAMP, "裁剪至不小于 0 → %d" % result)
	return result


## 无字藏书票：每场战斗第一次打出律式后抽 1 张。返回应额外抽的张数。
func consume_bookplate_draw(card_type: int) -> int:
	if bookplate_used or card_type != CardData.CardType.LAW:
		return 0
	if not has_relic(&"wordless_bookplate"):
		return 0
	bookplate_used = true
	_record_relic_benefit(&"wordless_bookplate", 1)
	return 1


func adjust_first_seal_countdown(base_turns: int) -> int:
	if delay_gear_used or not has_relic(&"delay_gear"):
		return maxi(0, base_turns)
	delay_gear_used = true
	var adjusted: int = maxi(0, base_turns - 1)
	_record_relic_benefit(&"delay_gear", base_turns - adjusted)
	return adjusted


func begin_player_turn() -> void:
	echo_hyoid_used_this_turn = false


func consume_echo_hyoid_block() -> int:
	if echo_hyoid_used_this_turn or not has_relic(&"echo_hyoid"):
		return 0
	echo_hyoid_used_this_turn = true
	_record_relic_benefit(&"echo_hyoid", 3)
	return 3


func consume_blank_epitaph(previous_hp: int, current_hp: int, max_hp: int) -> bool:
	if blank_epitaph_used or not has_relic(&"blank_epitaph"):
		return false
	if previous_hp * 2 < max_hp or current_hp * 2 >= max_hp:
		return false
	blank_epitaph_used = true
	_record_relic_benefit(&"blank_epitaph", 12)
	return true


func consume_expired_return_bell(lethal: bool) -> bool:
	if not lethal or expired_return_bell_used or not has_relic(&"expired_return_bell"):
		return false
	expired_return_bell_used = true
	_record_relic_benefit(&"expired_return_bell", 1)
	return true


func _can_trigger_red_pen(
	is_upgraded: bool, current_value: int, baseline_value: int, baseline_argument: int
) -> bool:
	return (
		has_relic(&"calibrator_red_pen")
		and not calibrator_red_pen_used
		and is_upgraded
		and baseline_argument >= 0
		and current_value > 0
		and current_value > baseline_value
	)


## 返回规则层只读遥测快照。不同遗物的收益单位依其规则文本定义，不直接横向比较。
func get_relic_telemetry() -> Dictionary:
	return {
		&"trigger_counts": _relic_trigger_counts.duplicate(),
		&"net_benefits": _relic_net_benefits.duplicate(),
	}


func _record_relic_benefit(relic_id: StringName, benefit: int) -> void:
	_relic_trigger_counts[relic_id] = int(_relic_trigger_counts.get(relic_id, 0)) + 1
	_relic_net_benefits[relic_id] = int(_relic_net_benefits.get(relic_id, 0)) + benefit


func advance_turn_statuses() -> Array[String]:
	var messages: Array[String] = []
	if player_weak_turns > 0:
		player_weak_turns -= 1
		messages.append("虚弱剩余 %d 回合。" % player_weak_turns)
	if player_vulnerable_turns > 0:
		player_vulnerable_turns -= 1
		messages.append("脆弱剩余 %d 回合。" % player_vulnerable_turns)
	if enemy_vulnerable_turns > 0:
		enemy_vulnerable_turns -= 1
	return messages


func get_status_text() -> String:
	var parts: Array[String] = []
	if player_strength != 0:
		parts.append("力量%d" % player_strength)
	if player_weak_turns > 0:
		parts.append("虚弱%d" % player_weak_turns)
	if player_vulnerable_turns > 0:
		parts.append("脆弱%d" % player_vulnerable_turns)
	if parts.is_empty():
		return "无"
	return "、".join(parts)


func get_relic_text() -> String:
	if relics.is_empty():
		return "无"
	var parts: Array[String] = []
	for relic_id: StringName in relics:
		parts.append(relic_title(relic_id))
	return "、".join(parts)


func _trace(phase: Phase, note: String) -> void:
	last_trace.append("%s|%s" % [phase_name(phase), note])


static func phase_name(phase: Phase) -> String:
	match phase:
		Phase.BASE:
			return "基础值"
		Phase.ATTACKER:
			return "攻击方状态"
		Phase.DEFENDER:
			return "受击方修正"
		Phase.RELIC:
			return "遗物修正"
		Phase.CLAMP:
			return "上下限裁剪"
	return "未知阶段"


## 供测试断言：轨迹中的阶段必须严格按 PHASE_ORDER 出现且完整。
func trace_phase_sequence() -> Array[String]:
	var sequence: Array[String] = []
	for entry: String in last_trace:
		sequence.append(entry.get_slice("|", 0))
	return sequence
