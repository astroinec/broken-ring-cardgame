class_name CombatModel
extends RefCounted

## 战斗规则层。表现层只读取这里的结算结果，绝不持有规则状态。
##
## v0.5 规则硬化后的三条硬性约定：
## 1. 敌人行为全部来自 EnemyCatalog 数据，本文件不再有按敌人写死的 match 分支。
## 2. 一切“指向某个东西”的效果经由 TargetSelector 解析。
## 3. 一切可被修正的数值经由 RuleEngine 的固定阶段管线。


const DEFAULT_SEED: int = 73103
const PLAYER_MAX_HP: int = 70
const BASE_ENERGY: int = 3
const BASE_HAND_SIZE: int = 5
const MAX_HAND_SIZE: int = 10
const INSTABILITY_THRESHOLD: int = 10
const FRACTURE_DAMAGE: int = 8
const TUTORIAL_STAGE_MIN: int = 1
const TUTORIAL_STAGE_MAX: int = 6
const BOSS_PHASE_TWO_THRESHOLD: int = 100
const BOSS_TERMINAL_HP: int = 1
const BOSS_RECOVERY_REQUIRED: int = 2
const BOSS_KEYWORDS: Array[StringName] = [&"超载", &"封存", &"回响", &"消逝"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = DEFAULT_SEED
var next_instance_id: int = 1

var rule_engine: RuleEngine = RuleEngine.new()

var player_hp: int = PLAYER_MAX_HP
var player_max_hp: int = PLAYER_MAX_HP
var player_block: int = 0
var energy: int = BASE_ENERGY
var instability: int = 0
var instability_threshold: int = INSTABILITY_THRESHOLD
var fracture_damage: int = FRACTURE_DAMAGE
var initial_draw_bonus: int = 0
var battle_evidence_ids: Array[StringName] = []
var turn_number: int = 1
var instability_gained_this_turn: bool = false
var battle_over: bool = false
var victory: bool = false
var tutorial_stage: int = TUTORIAL_STAGE_MIN
var tutorial_stage_title: String = ""
var tutorial_hint: String = ""

var enemy_definition: EnemyDefinition = null
var enemy_id: StringName = &""
var enemy_name: String = ""
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var enemy_block: int = 0
var enemy_intent_index: int = 0

## 吞字记录（拾字虫）。
var devour_record_type: int = -1
## 倒读记录（倒读者）：已提交给本回合意图使用的类别。
var reverse_record_type: int = -1
## 本回合追踪到的最后一张非状态牌，将在下个回合开始时提交为倒读记录。
var reverse_record_pending: int = -1
## 石壳（空名卫士）。
var stone_shell: int = 0
var stone_shell_broken_this_turn: bool = false
var last_nonstatus_card_type: int = -1
## 装订被动（装订刑具）。
var extra_draws_this_turn: int = 0
var binding_triggered_this_turn: bool = false

## 删名者专属战斗状态。所有编辑都只引用本场 CardData.instance_id。
var boss_phase: int = 0
var boss_transition_pending: bool = false
var boss_terminal_choice_pending: bool = false
var boss_recovery_count: int = 0
var boss_strength: int = 0
var boss_cost_edits: Dictionary = {}
var boss_deleted_types: Dictionary = {}
var boss_deleted_keywords: Dictionary = {}
var boss_type_sequence: Array[int] = []
var boss_last_recovery_text: String = ""
var boss_delete_next_draw_type: bool = false
var boss_terminal_choice: StringName = &""
var boss_terminal_result_text: String = ""
var _boss_edit_order: int = 0

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var sealed_zone: Array[CardData] = []
var exhausted_zone: Array[CardData] = []
var log_entries: Array[String] = []
var missing_name: Dictionary = {}

var _telemetry_fractures: int = 0
var _telemetry_card_uses: Dictionary = {}
var _logged_red_pen_triggers: int = 0

var last_card_type: int = -1
var last_card_id: StringName = &""
var last_card_upgrade_id: StringName = &""
var last_card_base_cost: int = -1
var last_card_exhausts: bool = false
var last_card_temporary: bool = false
var last_damage_snapshot: int = 0
var last_block_snapshot: int = 0
var cards_played_this_turn: int = 0
var attack_played_this_turn: bool = false
var card_unsealed_this_turn: bool = false
var prevent_next_fracture_damage: bool = false

## 待选择请求。非 null 时战斗被挂起，只接受解析或取消两种输入。
var pending_selection: PendingSelection = null
## 结束回合时的手牌快照。敌人意图可编辑这些已进入弃牌堆的同一战斗实例。
var _ended_hand_snapshot: Array[CardData] = []

# --- 单张卡牌结算过程中的临时状态（供挂起后继续结算使用） ---
var _play_card: CardData = null
var _play_effects: Array[CardEffect] = []
var _play_effect_index: int = 0
var _play_hand_index: int = 0
var _play_paid_cost: int = 0
var _play_missing_name_refund_type: int = -1
var _play_resolved_damage: int = 0
var _play_resolved_block: int = 0
var _play_card_was_sealed: bool = false


func start_battle(
	p_seed: int = DEFAULT_SEED,
	p_tutorial_stage: int = TUTORIAL_STAGE_MIN,
	p_bonus_card_ids: Array[StringName] = [],
	p_enemy_id: StringName = &"",
	p_relics: Array[StringName] = [],
	p_deck_instances: Array[Dictionary] = [],
	p_player_hp: int = PLAYER_MAX_HP,
	p_player_max_hp: int = PLAYER_MAX_HP,
	p_battle_context: Dictionary = {}
) -> void:
	seed_value = p_seed
	rng.seed = seed_value
	tutorial_stage = clampi(p_tutorial_stage, TUTORIAL_STAGE_MIN, TUTORIAL_STAGE_MAX)
	next_instance_id = 1
	player_max_hp = maxi(1, p_player_max_hp)
	player_hp = clampi(p_player_hp, 0, player_max_hp)
	player_block = 0
	energy = BASE_ENERGY
	instability = 0
	instability_threshold = maxi(1, INSTABILITY_THRESHOLD + int(p_battle_context.get(&"instability_threshold_delta", 0)))
	var damage_override: int = int(p_battle_context.get(&"fracture_damage_override", 0))
	fracture_damage = damage_override if damage_override > 0 else FRACTURE_DAMAGE
	initial_draw_bonus = maxi(0, int(p_battle_context.get(&"initial_draw_bonus", 0)))
	battle_evidence_ids.clear()
	for raw_evidence_id: Variant in p_battle_context.get(&"evidence_ids", []):
		battle_evidence_ids.append(raw_evidence_id as StringName)
	enemy_block = 0
	enemy_intent_index = 0
	devour_record_type = -1
	reverse_record_type = -1
	reverse_record_pending = -1
	stone_shell = 0
	stone_shell_broken_this_turn = false
	last_nonstatus_card_type = -1
	extra_draws_this_turn = 0
	binding_triggered_this_turn = false
	_reset_boss_state()
	turn_number = 1
	battle_over = false
	victory = false
	cards_played_this_turn = 0
	attack_played_this_turn = false
	card_unsealed_this_turn = false
	prevent_next_fracture_damage = false
	last_card_id = &""
	last_card_upgrade_id = &""
	last_card_base_cost = -1
	last_card_exhausts = false
	last_card_temporary = false
	pending_selection = null
	_ended_hand_snapshot.clear()
	_clear_play_state()
	missing_name.clear()
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	sealed_zone.clear()
	exhausted_zone.clear()
	log_entries.clear()
	_telemetry_fractures = 0
	_telemetry_card_uses.clear()
	_logged_red_pen_triggers = 0
	rule_engine.reset_for_battle(p_relics)
	rule_engine.enemy_strength = maxi(0, int(p_battle_context.get(&"enemy_strength", 0)))
	var initial_law_missing_name: int = maxi(0, int(p_battle_context.get(&"initial_missing_name_law", 0)))
	if initial_law_missing_name > 0:
		missing_name[CardData.CardType.LAW] = initial_law_missing_name
	_configure_tutorial_stage()
	_configure_enemy(p_enemy_id if p_enemy_id != &"" else EnemyCatalog.enemy_id_for_path_stage(tutorial_stage))
	if p_deck_instances.is_empty():
		_build_tutorial_deck()
		# 旧测试与机制测试场继续使用渐进牌组；奖励牌作为额外牌加入。
		for bonus_card_id: StringName in p_bonus_card_ids:
			_add_card_by_id(bonus_card_id)
	else:
		_build_run_deck(p_deck_instances)
	_shuffle_cards(draw_pile)
	_log("路径节点 %d/%d：%s。" % [tutorial_stage, TUTORIAL_STAGE_MAX, tutorial_stage_title])
	_log("%s出现，生命 %d。" % [enemy_name, enemy_hp])
	if not rule_engine.relics.is_empty():
		_log("携带遗物：%s。" % rule_engine.get_relic_text())
	if instability_threshold != INSTABILITY_THRESHOLD or fracture_damage != FRACTURE_DAMAGE:
		_log("远征修正：不稳定阈值 %d，裂解伤害 %d。" % [instability_threshold, fracture_damage])
	if rule_engine.enemy_strength > 0:
		_log("事件压力：敌人初始力量 +%d。" % rule_engine.enemy_strength)
	_start_player_turn()


# ---------------------------------------------------------------- 敌人列表视图
# 当前战斗只有一个敌人，但一律以列表形式对外暴露，
# 目标解析层与表现层都按索引访问，加入多敌人时无需改动调用点。

func get_enemy_count() -> int:
	return 1


func get_enemy_hp(index: int = 0) -> int:
	return enemy_hp if index == 0 else 0


func get_enemy_max_hp(index: int = 0) -> int:
	return enemy_max_hp if index == 0 else 0


func get_enemy_name(index: int = 0) -> String:
	return enemy_name if index == 0 else ""


## 敌人当前可抵消伤害的总量（意图格挡 + 石壳）。
func get_enemy_total_block(index: int = 0) -> int:
	return (enemy_block + stone_shell) if index == 0 else 0


func build_target_context() -> TargetContext:
	var context: TargetContext = TargetContext.new()
	context.hand = hand
	context.sealed_zone = sealed_zone
	context.draw_pile = draw_pile
	for index: int in range(get_enemy_count()):
		context.enemy_names.append(get_enemy_name(index))
		context.enemy_hps.append(0 if boss_terminal_choice_pending else get_enemy_hp(index))
	return context


# -------------------------------------------------------------------- 教学进度

func get_stage_progress_text() -> String:
	return "路径 %d/%d｜%s" % [tutorial_stage, TUTORIAL_STAGE_MAX, tutorial_stage_title]


func is_mechanic_unlocked(mechanic: StringName) -> bool:
	match mechanic:
		&"basic":
			return true
		&"intent":
			return tutorial_stage >= 2
		&"overload":
			return tutorial_stage >= 3
		&"seal":
			return tutorial_stage >= 4
		&"echo":
			return tutorial_stage >= 5
		&"missing_name":
			return tutorial_stage >= 6
	return false


func can_advance_tutorial_stage() -> bool:
	return battle_over and victory and tutorial_stage < TUTORIAL_STAGE_MAX


func get_next_tutorial_stage() -> int:
	if can_advance_tutorial_stage():
		return tutorial_stage + 1
	return tutorial_stage


# ---------------------------------------------------------------------- 出牌流程

func play_card(hand_index: int) -> bool:
	if battle_over or boss_terminal_choice_pending or pending_selection != null:
		return false
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	var effective_type: int = get_card_effective_type(card)
	if card.card_type == CardData.CardType.STATUS and card.base_cost >= 99:
		_log("《%s》不可打出。" % card.title)
		return false
	var cost: int = get_card_cost(card)
	if energy < cost:
		_log("稳定度不足，无法打出《%s》。" % card.title)
		return false

	energy -= cost
	_play_paid_cost = cost
	_play_missing_name_refund_type = -1
	if effective_type >= 0 and int(missing_name.get(effective_type, 0)) > 0:
		_play_missing_name_refund_type = effective_type
		_consume_missing_name(effective_type)
	hand.remove_at(hand_index)
	_log("打出《%s》[%s]，消耗 %d 稳定度。" % [card.title, get_card_type_display(card), cost])

	_play_card = card
	_play_hand_index = hand_index
	_play_effects = _filter_deleted_keyword_effects(card, _generate_card_effects(card))
	if _play_effects.is_empty() and not get_card_keywords(card).is_empty():
		_log("《%s》的关键词已删除；基础正文为空。" % card.title)
	_play_effect_index = 0
	_play_resolved_damage = 0
	_play_resolved_block = 0
	_play_card_was_sealed = false
	return _run_effect_loop()


## 玩家在选择模式中确认目标。index 为 TargetSelector 给出的候选索引。
func resolve_pending_selection(target_index: int) -> bool:
	if pending_selection == null:
		return false
	var request: PendingSelection = pending_selection
	if not TargetSelector.is_valid_choice(
		request.target_kind, build_target_context(), target_index,
		request.target_filter, request.target_scope
	):
		_log("选择无效：该目标不在可选范围内。")
		return false
	pending_selection = null
	var effect: CardEffect = _play_effects[_play_effect_index]
	_apply_chosen_effect(effect, target_index)
	_play_effect_index += 1
	return _run_effect_loop()


## 玩家取消选择。取消规则见 PendingSelection 的文档注释：该牌不结算，
## 返还稳定度与缺名层数，卡牌放回手牌原位置，不产生任何效果。
func cancel_pending_selection() -> bool:
	if pending_selection == null:
		return false
	var request: PendingSelection = pending_selection
	pending_selection = null
	energy += request.paid_cost
	if request.refunded_missing_name_type >= 0:
		var restored: int = int(missing_name.get(request.refunded_missing_name_type, 0)) + 1
		missing_name[request.refunded_missing_name_type] = restored
	var insert_at: int = clampi(request.hand_index, 0, hand.size())
	hand.insert(insert_at, request.card)
	_log(
		"取消选择：《%s》不结算，返还 %d 稳定度并放回手牌。" % [request.card.title, request.paid_cost]
	)
	_clear_play_state()
	return true


func has_pending_selection() -> bool:
	return pending_selection != null


func get_pending_prompt() -> String:
	if pending_selection == null:
		return ""
	return pending_selection.describe()


func get_pending_candidate_indices() -> Array[int]:
	if pending_selection == null:
		return []
	return TargetSelector.candidate_indices(
		pending_selection.target_kind, build_target_context(),
		pending_selection.target_filter, pending_selection.target_scope
	)


func get_pending_candidate_labels() -> Array[String]:
	if pending_selection == null:
		return []
	return TargetSelector.candidate_labels(
		pending_selection.target_kind, build_target_context(),
		pending_selection.target_filter, pending_selection.target_scope
	)


func _run_effect_loop() -> bool:
	while _play_effect_index < _play_effects.size():
		var effect: CardEffect = _play_effects[_play_effect_index]
		if effect.requires_player_choice():
			var candidates: Array[int] = TargetSelector.candidate_indices(
				effect.target_kind, build_target_context(), effect.target_filter, effect.target_scope
			)
			if candidates.is_empty():
				_log("《%s》找不到可选目标：%s。" % [_play_card.title, TargetSelector.describe(effect.target_kind)])
				_play_effect_index += 1
				continue
			var request: PendingSelection = PendingSelection.new()
			request.card = _play_card
			request.hand_index = _play_hand_index
			request.paid_cost = _play_paid_cost
			request.refunded_missing_name_type = _play_missing_name_refund_type
			request.effects = _play_effects
			request.effect_index = _play_effect_index
			request.target_kind = effect.target_kind
			request.target_filter = effect.target_filter
			request.target_scope = effect.target_scope
			request.prompt = effect.prompt
			pending_selection = request
			_log("《%s》等待选择：%s。" % [_play_card.title, request.describe()])
			return true
		_apply_automatic_effect(effect)
		_play_effect_index += 1
		if battle_over:
			break
	_finish_card_play()
	return true


func _apply_automatic_effect(effect: CardEffect) -> void:
	var card: CardData = _play_card
	var base_effect: CardEffect = _base_effect_for_current_index(card)
	match effect.kind:
		CardEffect.Kind.DAMAGE_ENEMY:
			var target: int = TargetSelector.resolve_enemy(effect.target_kind, build_target_context())
			var baseline_damage: int = effect.amount if base_effect == null else base_effect.amount
			_play_resolved_damage += _deal_damage_to_enemy(
				effect.amount, get_card_effective_type(card), card.title, target,
				baseline_damage, card.upgrade_id != &""
			)
		CardEffect.Kind.GAIN_BLOCK:
			var baseline_block: int = effect.amount if base_effect == null else base_effect.amount
			_play_resolved_block += _gain_player_block(
				effect.amount, card.title, true, baseline_block, card.upgrade_id != &""
			)
		CardEffect.Kind.DRAW_CARDS:
			draw_cards(effect.amount, false)
		CardEffect.Kind.GAIN_INSTABILITY:
			_gain_instability(effect.amount)
		CardEffect.Kind.REDUCE_INSTABILITY:
			var reduced: int = mini(instability, effect.amount)
			instability -= reduced
			var baseline_factor: int = effect.factor if base_effect == null else base_effect.factor
			var converted_block: int = rule_engine.compute_block(
				reduced * effect.factor, reduced * baseline_factor, card.upgrade_id != &""
			)
			player_block += converted_block
			_play_resolved_block += converted_block
			_log("不稳定减少 %d；转化为 %d 格挡。" % [reduced, converted_block])
			_log_red_pen_if_just_triggered()
		CardEffect.Kind.SEAL_CARD:
			_seal_card(card, effect.amount, card.title)
			_play_card_was_sealed = true
		CardEffect.Kind.ECHO_ATTACK:
			if last_card_type == CardData.CardType.ATTACK:
				var echoed_damage: int = floori(float(last_damage_snapshot) * float(effect.amount) / 100.0)
				var baseline_percent: int = effect.amount if base_effect == null else base_effect.amount
				var baseline_echo_damage: int = floori(float(last_damage_snapshot) * float(baseline_percent) / 100.0)
				_log("回响上一张攻式已结算伤害的 %d%%：%d。" % [effect.amount, echoed_damage])
				# 回响沿用原目标；原目标已死亡时改为指向生命最低的敌人。
				var echo_target: int = TargetSelector.resolve_enemy(
					TargetSelector.Kind.LOWEST_HP_ENEMY, build_target_context()
				)
				_play_resolved_damage += _deal_damage_to_enemy(
					echoed_damage, get_card_effective_type(card), card.title, echo_target,
					baseline_echo_damage, card.upgrade_id != &""
				)
				_apply_echo_hyoid()
				_on_boss_echo_resolved()
			else:
				_log("回响失败：紧邻上一张牌不是攻式。")
		CardEffect.Kind.ECHO_BLOCK:
			if last_card_type == CardData.CardType.DEFENSE:
				var echoed_block: int = floori(float(last_block_snapshot) * float(effect.amount) / 100.0)
				var baseline_percent: int = effect.amount if base_effect == null else base_effect.amount
				var baseline_echo_block: int = floori(float(last_block_snapshot) * float(baseline_percent) / 100.0)
				_play_resolved_block += _gain_player_block(
					echoed_block, card.title, false, baseline_echo_block, card.upgrade_id != &""
				)
				_log("回响上一张守式已结算格挡的 %d%%：%d。" % [effect.amount, echoed_block])
				_apply_echo_hyoid()
				_on_boss_echo_resolved()
			else:
				_log("回响失败：紧邻上一张牌不是守式。")
		CardEffect.Kind.PREVENT_FRACTURE:
			prevent_next_fracture_damage = true
			_log("本回合下一次裂解伤害将变为 0。")
		CardEffect.Kind.DISSOLUTION_ATTACK:
			var dissolution_damage: int = effect.amount + instability * effect.factor
			var baseline_amount: int = effect.amount if base_effect == null else base_effect.amount
			var baseline_factor: int = effect.factor if base_effect == null else base_effect.factor
			var baseline_dissolution: int = baseline_amount + instability * baseline_factor
			var dissolution_target: int = TargetSelector.resolve_enemy(
				effect.target_kind, build_target_context()
			)
			_play_resolved_damage += _deal_damage_to_enemy(
				dissolution_damage, get_card_effective_type(card), card.title, dissolution_target,
				baseline_dissolution, card.upgrade_id != &""
			)
			instability = 0
			_log("崩解协议将不稳定清零。")
		CardEffect.Kind.COPY_PREVIOUS:
			_copy_previous_card_to_hand()


func _apply_chosen_effect(effect: CardEffect, target_index: int) -> void:
	var card: CardData = _play_card
	match effect.kind:
		CardEffect.Kind.DISCARD_CHOSEN_FROM_TOP:
			var discarded: CardData = draw_pile[target_index]
			draw_pile.remove_at(target_index)
			discard_pile.append(discarded)
			_log("索引重排：将《%s》置入弃牌堆，其余牌顺序不变。" % discarded.title)
		CardEffect.Kind.PREWRITE_COPY:
			var original: CardData = hand[target_index]
			original.cost_override_this_turn = 0
			var copy: CardData = _make_card_from_catalog(original.id, original.upgrade_id)
			copy.temporary = true
			_seal_card(copy, 1, "预写结局复制的《%s》" % original.title)
			_log("预写结局：复制《%s》并封存；原牌本回合费用变为 0。" % original.title)
		CardEffect.Kind.UNSEAL_CHOSEN:
			var chosen: CardData = sealed_zone[target_index]
			chosen.sealed_turns = 0
			_log("开封令：选择《%s》，倒计时归零。" % chosen.title)
			_unseal_card_at(target_index)
		_:
			push_error("效果 %d 声明了玩家选择目标，但缺少选择结算实现。" % effect.kind)
			_log("《%s》的选择效果未实现。" % card.title)


func _finish_card_play() -> void:
	var card: CardData = _play_card
	if card == null:
		return
	if not _play_card_was_sealed:
		if card.exhausts and is_card_keyword_active(card, &"消逝"):
			exhausted_zone.append(card)
			_log("《%s》进入消逝区。" % card.title)
		else:
			discard_pile.append(card)

	var effective_type: int = get_card_effective_type(card)
	cards_played_this_turn += 1
	_telemetry_card_uses[card.id] = int(_telemetry_card_uses.get(card.id, 0)) + 1
	if effective_type == CardData.CardType.ATTACK:
		attack_played_this_turn = true
	if effective_type >= 0 and effective_type != CardData.CardType.STATUS:
		_apply_same_type_adaptation(effective_type)
		reverse_record_pending = effective_type
		last_nonstatus_card_type = effective_type
		_track_boss_type_sequence(effective_type)
	last_card_type = effective_type
	last_card_id = card.id
	last_card_upgrade_id = card.upgrade_id
	last_card_base_cost = card.base_cost
	last_card_exhausts = card.exhausts
	last_card_temporary = card.temporary
	last_damage_snapshot = _play_resolved_damage
	last_block_snapshot = _play_resolved_block
	var bookplate_draw: int = rule_engine.consume_bookplate_draw(effective_type)
	if bookplate_draw > 0 and not battle_over and not boss_terminal_choice_pending:
		_log("无字藏书票触发：本场战斗第一次打出律式，抽 %d 张牌。" % bookplate_draw)
		draw_cards(bookplate_draw, false)
	_clear_play_state()
	if boss_transition_pending:
		_apply_boss_phase_transition()
	if not battle_over and not boss_terminal_choice_pending:
		_check_fracture()


func _clear_play_state() -> void:
	_play_card = null
	_play_effects = []
	_play_effect_index = 0
	_play_hand_index = 0
	_play_paid_cost = 0
	_play_missing_name_refund_type = -1
	_play_resolved_damage = 0
	_play_resolved_block = 0
	_play_card_was_sealed = false


func end_player_turn() -> void:
	if battle_over or boss_terminal_choice_pending or pending_selection != null:
		return
	_resolve_old_wounds_in_hand()
	if battle_over:
		return
	_log("结束第 %d 回合：弃置 %d 张手牌。" % [turn_number, hand.size()])
	_ended_hand_snapshot = hand.duplicate()
	while not hand.is_empty():
		discard_pile.append(hand.pop_back())
	_check_fracture()
	if battle_over:
		return
	_execute_enemy_intent()
	if battle_over:
		return
	turn_number += 1
	_start_player_turn()


func _resolve_old_wounds_in_hand() -> void:
	var wound_count: int = 0
	for card: CardData in hand:
		if card.id == &"old_wound":
			wound_count += 1
	for wound_index: int in range(wound_count):
		var damage: int = rule_engine.compute_unblocked_status_damage(2)
		var previous_hp: int = player_hp
		var bell_triggered: bool = rule_engine.consume_expired_return_bell(damage >= player_hp and damage > 0)
		player_hp = 1 if bell_triggered else maxi(0, player_hp - damage)
		_log("《旧伤》在回合结束时造成 %d 点不可格挡伤害，你的生命 %d/%d。" % [damage, player_hp, player_max_hp])
		_trigger_blank_epitaph(previous_hp)
		if bell_triggered:
			_log("过期返航铃触发：本次致命伤害后保留 1 点生命；立即执行裂解，本次裂解及之后的伤害仍可能致死。")
			_resolve_fracture(false, "返航铃后续裂解")
		else:
			_check_player_defeat()
		if battle_over:
			return


func draw_cards(amount: int, is_base_draw: bool = false) -> void:
	var allowed: int = rule_engine.compute_draw(amount, hand.size(), MAX_HAND_SIZE)
	if allowed < amount:
		_log("手牌上限限制：抽牌数由 %d 调整为 %d。" % [amount, allowed])
	for draw_index: int in range(allowed):
		if hand.size() >= MAX_HAND_SIZE:
			_log("手牌已满，停止抽牌。")
			return
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				_log("抽牌堆与弃牌堆均为空。")
				return
			while not discard_pile.is_empty():
				draw_pile.append(discard_pile.pop_back())
			_shuffle_cards(draw_pile)
			_log("弃牌堆洗回抽牌堆，共 %d 张。" % draw_pile.size())
		var card: CardData = draw_pile.pop_back()
		if not is_base_draw:
			extra_draws_this_turn += 1
			_check_binding_passive()
		if card.id == &"redaction":
			missing_name[CardData.CardType.LAW] = int(missing_name.get(CardData.CardType.LAW, 0)) + 1
			exhausted_zone.append(card)
			_log("抽到《删节》：获得 1 层律式缺名；《删节》进入消逝区。")
			continue
		if boss_delete_next_draw_type and card.card_type != CardData.CardType.STATUS:
			_delete_boss_card_type(card)
			boss_delete_next_draw_type = false
		hand.append(card)
		_log("抽到《%s》。" % card.title)


func get_card_cost(card: CardData) -> int:
	var base: int = card.cost_override_this_turn if card.cost_override_this_turn >= 0 else card.base_cost
	var effective_type: int = get_card_effective_type(card)
	var missing_stacks: int = 0 if effective_type < 0 else int(missing_name.get(effective_type, 0))
	var edit: Dictionary = boss_cost_edits.get(card.instance_id, {})
	return rule_engine.compute_cost(base + int(edit.get(&"increase", 0)), missing_stacks)


func get_card_original_cost(card: CardData) -> int:
	var base: int = card.cost_override_this_turn if card.cost_override_this_turn >= 0 else card.base_cost
	var effective_type: int = get_card_effective_type(card)
	var missing_stacks: int = 0 if effective_type < 0 else int(missing_name.get(effective_type, 0))
	return rule_engine.compute_cost(base, missing_stacks)


func get_card_cost_display(card: CardData) -> String:
	var current: int = get_card_cost(card)
	var edit: Dictionary = boss_cost_edits.get(card.instance_id, {})
	if edit.is_empty():
		return "费用 %d" % current
	return "费用 %d（原%d，红笔+%d）" % [current, get_card_original_cost(card), int(edit[&"increase"])]


func get_card_effective_type(card: CardData) -> int:
	return -1 if boss_deleted_types.has(card.instance_id) else card.card_type


func get_card_type_display(card: CardData) -> String:
	if boss_deleted_types.has(card.instance_id):
		return "类别：已删除（原%s）" % CardData.type_display_name(card.card_type)
	return "类别：%s" % card.type_name()


func get_card_keywords(card: CardData) -> Array[StringName]:
	var keywords: Array[StringName] = []
	match card.id:
		&"boundary_read", &"rift_slash", &"unseal_order", &"homophone":
			keywords.append(&"超载")
	match card.id:
		&"delayed_guard", &"countdown_scar", &"prewritten_ending":
			keywords.append(&"封存")
	match card.id:
		&"restate", &"copied_guard":
			keywords.append(&"回响")
	if card.exhausts:
		keywords.append(&"消逝")
	return keywords


func is_card_keyword_active(card: CardData, keyword: StringName) -> bool:
	var edit: Dictionary = boss_deleted_keywords.get(card.instance_id, {})
	var deleted: Array = edit.get(&"keywords", [])
	return not deleted.has(keyword)


func get_card_keyword_display(card: CardData) -> String:
	var parts: Array[String] = []
	for keyword: StringName in get_card_keywords(card):
		parts.append("%s（已删除）" % keyword if not is_card_keyword_active(card, keyword) else str(keyword))
	return "关键词：无" if parts.is_empty() else "关键词：%s" % "、".join(parts)


func get_card_boss_edit_text(card: CardData) -> String:
	var parts: Array[String] = []
	if boss_cost_edits.has(card.instance_id):
		parts.append("连续三种不同类别：恢复费用")
	if boss_deleted_types.has(card.instance_id):
		parts.append("封存牌解封：恢复类别")
	if boss_deleted_keywords.has(card.instance_id):
		parts.append("触发裂解：恢复关键词")
	return "" if parts.is_empty() else "恢复：%s" % "；".join(parts)


# ------------------------------------------------------------------ 意图与展示

func build_intent_context(use_current_hand: bool = true) -> IntentContext:
	var context: IntentContext = IntentContext.new()
	context.devour_record_type = devour_record_type
	context.reverse_record_type = reverse_record_type
	context.stone_shell_broken = stone_shell_broken_this_turn
	context.player_has_missing_name = _missing_name_total() > 0
	if use_current_hand:
		for card: CardData in hand:
			if card.card_type == CardData.CardType.STATUS:
				context.player_hand_has_status = true
				break
	return context


func get_current_intent() -> EnemyIntent:
	if enemy_definition == null:
		return null
	return enemy_definition.select_intent(enemy_intent_index, reverse_record_type, boss_phase)


func get_enemy_intent_text() -> String:
	var intent: EnemyIntent = get_current_intent()
	if intent == null:
		return "未知意图"
	return intent.describe(build_intent_context())


func get_enemy_record_text() -> String:
	if is_name_eraser_battle():
		return get_boss_status_text()
	if enemy_definition != null and enemy_definition.has_trait(EnemyDefinition.TRAIT_REVERSE_READ):
		if reverse_record_type < 0:
			return "倒读记录：空白"
		return "倒读记录：%s" % CardData.type_display_name(reverse_record_type)
	if enemy_definition != null and enemy_definition.has_trait(EnemyDefinition.TRAIT_STONE_SHELL):
		return "石壳：%d%s" % [stone_shell, "（本回合已被打破）" if stone_shell_broken_this_turn else ""]
	if enemy_definition != null and enemy_definition.has_trait(EnemyDefinition.TRAIT_BINDING):
		return "装订读数：额外抽牌 %d/%d" % [extra_draws_this_turn, enemy_definition.binding_draw_threshold]
	if not is_mechanic_unlocked(&"missing_name"):
		return "偷字记录：尚未开放"
	if devour_record_type < 0:
		return "吞字记录：空白"
	return "吞字记录：%s" % CardData.type_display_name(devour_record_type)


func get_missing_name_text() -> String:
	var parts: Array[String] = []
	for card_type: int in [CardData.CardType.ATTACK, CardData.CardType.DEFENSE, CardData.CardType.LAW]:
		var stacks: int = int(missing_name.get(card_type, 0))
		if stacks > 0:
			parts.append("%s缺名×%d" % [CardData.type_display_name(card_type), stacks])
	if parts.is_empty():
		return "无"
	return "、".join(parts)


func is_name_eraser_battle() -> bool:
	return enemy_definition != null and enemy_definition.has_trait(EnemyDefinition.TRAIT_NAME_ERASER)


func get_boss_phase_name() -> String:
	match boss_phase:
		1:
			return "校对"
		2:
			return "除名"
		3:
			return "终结"
	return "未启用"


func get_boss_deleted_summary() -> String:
	var parts: Array[String] = []
	if not boss_cost_edits.is_empty():
		parts.append("费用×%d" % boss_cost_edits.size())
	if not boss_deleted_types.is_empty():
		parts.append("类别×%d" % boss_deleted_types.size())
	if not boss_deleted_keywords.is_empty():
		parts.append("关键词×%d" % boss_deleted_keywords.size())
	if boss_delete_next_draw_type:
		parts.append("待删除下次抽牌类别")
	return "无" if parts.is_empty() else "、".join(parts)


func get_boss_status_text() -> String:
	var text: String = "REC-10 / 可覆写载体｜阶段%d·%s｜力量%d｜已完成恢复%d次｜删除：%s\n除名栏：%s" % [
		boss_phase, get_boss_phase_name(), boss_strength, boss_recovery_count,
		get_boss_deleted_summary(), get_boss_deleted_detail_text(),
	]
	if not boss_last_recovery_text.is_empty():
		text += "\n最近恢复：%s" % boss_last_recovery_text
	return text


func can_choose_boss_original_text() -> bool:
	return boss_terminal_choice_pending and boss_recovery_count >= BOSS_RECOVERY_REQUIRED


func get_boss_terminal_options() -> Array[Dictionary]:
	return [
		{&"id": &"deliver_seal", &"label": "交付定义律印", &"enabled": boss_terminal_choice_pending, &"reason": ""},
		{
			&"id": &"read_original", &"label": "读取被删原文",
			&"enabled": can_choose_boss_original_text(),
			&"reason": "" if can_choose_boss_original_text() else "需要本场战斗累计完成至少 2 次可计数恢复（费用、类别或关键词；当前 %d/%d）" % [boss_recovery_count, BOSS_RECOVERY_REQUIRED],
		},
	]


func choose_boss_terminal(option_id: StringName) -> bool:
	if not boss_terminal_choice_pending:
		return false
	var enabled: bool = false
	for option: Dictionary in get_boss_terminal_options():
		if option[&"id"] == option_id:
			enabled = bool(option[&"enabled"])
			break
	if not enabled:
		_log("终结选项不可用：%s。" % option_id)
		return false
	boss_terminal_choice = option_id
	boss_terminal_choice_pending = false
	battle_over = true
	victory = true
	if option_id == &"read_original":
		boss_terminal_result_text = "你读取了被删原文：第十份校准记录仍保留着九种互相冲突的文明答案。"
	else:
		boss_terminal_result_text = "你按终末机构命令交付定义律印。REC-10 档案重新封闭。"
	_log(boss_terminal_result_text)
	return true


func get_boss_deleted_detail_text() -> String:
	var parts: Array[String] = []
	for raw_id: Variant in boss_cost_edits.keys():
		var cost_card: CardData = _card_for_instance(int(raw_id))
		if cost_card != null:
			parts.append("《%s》费用+%d" % [cost_card.title, int((boss_cost_edits[raw_id] as Dictionary)[&"increase"])])
	for raw_id: Variant in boss_deleted_types.keys():
		var type_card: CardData = _card_for_instance(int(raw_id))
		if type_card != null:
			parts.append("《%s》类别已删除（原%s）" % [type_card.title, CardData.type_display_name(type_card.card_type)])
	for raw_id: Variant in boss_deleted_keywords.keys():
		var keyword_card: CardData = _card_for_instance(int(raw_id))
		if keyword_card == null:
			continue
		var keyword_names: Array[String] = []
		for raw_keyword: Variant in (boss_deleted_keywords[raw_id] as Dictionary)[&"keywords"]:
			keyword_names.append(str(raw_keyword))
		parts.append("《%s》关键词已删除（%s）" % [keyword_card.title, "、".join(keyword_names)])
	if boss_delete_next_draw_type:
		parts.append("下次抽到的第一张非状态牌将失去类别")
	return "无" if parts.is_empty() else "；".join(parts)


func _reset_boss_state() -> void:
	boss_phase = 0
	boss_transition_pending = false
	boss_terminal_choice_pending = false
	boss_recovery_count = 0
	boss_strength = 0
	boss_cost_edits.clear()
	boss_deleted_types.clear()
	boss_deleted_keywords.clear()
	boss_type_sequence.clear()
	boss_last_recovery_text = ""
	boss_delete_next_draw_type = false
	boss_terminal_choice = &""
	boss_terminal_result_text = ""
	_boss_edit_order = 0


func _next_boss_edit_order() -> int:
	_boss_edit_order += 1
	return _boss_edit_order


func _edit_boss_card_costs(amount: int) -> void:
	var candidates: Array[CardData] = []
	for pile: Array[CardData] in [draw_pile, discard_pile]:
		for card: CardData in pile:
			if card.card_type != CardData.CardType.STATUS and not boss_cost_edits.has(card.instance_id):
				candidates.append(card)
	var edit_count: int = mini(amount, candidates.size())
	for edit_index: int in range(edit_count):
		var chosen_index: int = rng.randi_range(0, candidates.size() - 1)
		var chosen: CardData = candidates[chosen_index]
		candidates.remove_at(chosen_index)
		boss_cost_edits[chosen.instance_id] = {
			&"original_cost": get_card_original_cost(chosen),
			&"increase": 1,
			&"order": _next_boss_edit_order(),
			&"source": &"tamper_cost",
		}
		_log("篡改费用：《%s》费用由 %d 改为 %d；连续打出三种不同类别可恢复。" % [
			chosen.title, get_card_original_cost(chosen), get_card_cost(chosen),
		])
	if edit_count < amount:
		_log("篡改费用只找到 %d 个可编辑实例。" % edit_count)


func _delete_boss_card_type(card: CardData) -> bool:
	if not is_name_eraser_battle() or boss_phase != 2 or card.card_type == CardData.CardType.STATUS:
		return false
	if boss_deleted_types.has(card.instance_id):
		_log("《%s》的类别已经被删除，本次标记没有重复叠加。" % card.title)
		return false
	boss_deleted_types[card.instance_id] = {
		&"original_type": card.card_type,
		&"order": _next_boss_edit_order(),
		&"source": &"delete_type",
	}
	_log("删除类别：《%s》进入手牌时失去%s；封存牌解封可恢复最早一项。" % [
		card.title, CardData.type_display_name(card.card_type),
	])
	return true


func _delete_boss_hand_keywords() -> void:
	var candidates: Array[CardData] = []
	for card: CardData in _ended_hand_snapshot:
		if not get_card_keywords(card).is_empty() and not boss_deleted_keywords.has(card.instance_id):
			candidates.append(card)
	if candidates.is_empty():
		_log("删除关键词失败：手牌中没有尚未删除关键词的卡牌。")
		return
	var card: CardData = candidates[rng.randi_range(0, candidates.size() - 1)]
	var keywords: Array[StringName] = get_card_keywords(card)
	boss_deleted_keywords[card.instance_id] = {
		&"keywords": keywords.duplicate(),
		&"order": _next_boss_edit_order(),
		&"source": &"delete_keywords",
	}
	var names: Array[String] = []
	for keyword: StringName in keywords:
		names.append(str(keyword))
	_log("删除关键词：《%s》的%s附加效果被禁用；触发裂解可恢复最早一项。" % [
		card.title, "、".join(names),
	])


func _clear_missing_name_gain_boss_strength() -> void:
	var cleared: int = _missing_name_total()
	missing_name.clear()
	if cleared <= 0:
		_log("返还原稿：当前没有缺名可清除，删名者未获得力量。")
		return
	boss_strength += cleared * 3
	rule_engine.enemy_strength = boss_strength
	_log("返还原稿：清除 %d 层缺名；删名者力量升至 %d。" % [cleared, boss_strength])


func _missing_name_total() -> int:
	var total: int = 0
	for raw_stacks: Variant in missing_name.values():
		total += maxi(0, int(raw_stacks))
	return total


func _track_boss_type_sequence(card_type: int) -> void:
	if not is_name_eraser_battle() or boss_phase != 1:
		return
	if not [CardData.CardType.ATTACK, CardData.CardType.DEFENSE, CardData.CardType.LAW].has(card_type):
		return
	if boss_type_sequence.has(card_type):
		boss_type_sequence = [card_type]
	else:
		boss_type_sequence.append(card_type)
	if boss_type_sequence.size() < 3:
		return
	boss_type_sequence.clear()
	if not _restore_earliest_boss_cost_edit():
		_log("三种不同类别已连续完成，但当前没有费用篡改可恢复。")


func _restore_earliest_boss_cost_edit() -> bool:
	var instance_id: int = _earliest_boss_edit_id(boss_cost_edits)
	if instance_id < 0:
		return false
	var card: CardData = _card_for_instance(instance_id)
	boss_cost_edits.erase(instance_id)
	var removed_block: int = mini(6, enemy_block)
	enemy_block -= removed_block
	var card_name: String = "实例#%d" % instance_id if card == null else "《%s》" % card.title
	_record_boss_recovery("%s恢复原费用；删名者失去 %d 格挡。" % [card_name, removed_block])
	return true


func _restore_earliest_boss_type_edit() -> bool:
	if not is_name_eraser_battle() or boss_phase != 2:
		return false
	var instance_id: int = _earliest_boss_edit_id(boss_deleted_types)
	if instance_id < 0:
		return false
	var card: CardData = _card_for_instance(instance_id)
	boss_deleted_types.erase(instance_id)
	var card_name: String = "实例#%d" % instance_id if card == null else "《%s》" % card.title
	_record_boss_recovery("%s恢复原类别。" % card_name)
	return true


func _restore_earliest_boss_keyword_edit() -> bool:
	if not is_name_eraser_battle() or boss_phase != 2:
		return false
	var instance_id: int = _earliest_boss_edit_id(boss_deleted_keywords)
	if instance_id < 0:
		return false
	var card: CardData = _card_for_instance(instance_id)
	boss_deleted_keywords.erase(instance_id)
	var card_name: String = "实例#%d" % instance_id if card == null else "《%s》" % card.title
	_record_boss_recovery("%s恢复被删关键词。" % card_name)
	return true


func _on_boss_echo_resolved() -> void:
	if not is_name_eraser_battle() or boss_phase != 2 or boss_strength <= 0:
		return
	boss_strength -= 1
	rule_engine.enemy_strength = boss_strength
	boss_last_recovery_text = "回响成功：删名者力量降至 %d。" % boss_strength
	_log(boss_last_recovery_text)


func _record_boss_recovery(message: String) -> void:
	boss_recovery_count += 1
	boss_last_recovery_text = message
	_log("恢复记录 %d：%s" % [boss_recovery_count, message])


func _earliest_boss_edit_id(edits: Dictionary) -> int:
	var earliest_id: int = -1
	var earliest_order: int = 2_147_483_647
	for raw_id: Variant in edits.keys():
		var entry: Dictionary = edits[raw_id] as Dictionary
		var order: int = int(entry.get(&"order", earliest_order))
		if order < earliest_order:
			earliest_order = order
			earliest_id = int(raw_id)
	return earliest_id


func _card_for_instance(instance_id: int) -> CardData:
	for pile: Array[CardData] in [draw_pile, hand, discard_pile, sealed_zone, exhausted_zone]:
		for card: CardData in pile:
			if card.instance_id == instance_id:
				return card
	return null


func _apply_boss_phase_transition() -> void:
	if not is_name_eraser_battle() or boss_phase != 1 or boss_terminal_choice_pending:
		boss_transition_pending = false
		return
	boss_transition_pending = false
	boss_phase = 2
	enemy_intent_index = 0
	enemy_block = 0
	boss_cost_edits.clear()
	boss_type_sequence.clear()
	_log("阶段转换：全部格挡与费用篡改已清除。REC-10 / 可覆写载体。")
	_log("删名者：我删掉的不是你的名字。我删掉的是他们给你的用途。")
	if battle_evidence_ids.has(&"obscured_asset_log"):
		_log("删名者：你已经看过那层遮蔽。‘资产’不是身份，只是他们给可替换身体写的用途。")


func _enter_boss_terminal() -> void:
	if not is_name_eraser_battle() or boss_terminal_choice_pending or battle_over:
		return
	boss_phase = 3
	boss_transition_pending = false
	boss_terminal_choice_pending = true
	enemy_hp = BOSS_TERMINAL_HP
	enemy_block = 0
	_log("终结阶段：删名者生命锁定为 1，并从伤害目标中移除。")
	_log("未完成的删除等待你的选择。")


func get_sealed_summary() -> String:
	if sealed_zone.is_empty():
		return "无"
	var parts: Array[String] = []
	for card: CardData in sealed_zone:
		parts.append("%s(%d)" % [card.title, card.sealed_turns])
	return "、".join(parts)


func get_player_status_text() -> String:
	return rule_engine.get_status_text()


func get_relic_hud_text() -> String:
	if rule_engine.relics.is_empty():
		return "遗物：无"
	var telemetry: Dictionary = rule_engine.get_relic_telemetry()
	var counts: Dictionary = telemetry[&"trigger_counts"]
	var parts: Array[String] = []
	for relic_id: StringName in rule_engine.relics:
		var definition: Dictionary = RelicCatalog.get_definition(relic_id)
		parts.append("%s｜%s｜本场触发 %d" % [
			definition.get(&"title", relic_id),
			definition.get(&"short_description", definition.get(&"description", "")),
			int(counts.get(relic_id, 0)),
		])
	return "\n".join(parts)


## 返回规则层只读遥测快照；模拟与测试读取此处，不从日志或 UI 反推规则事件。
func get_telemetry() -> Dictionary:
	var relic_telemetry: Dictionary = rule_engine.get_relic_telemetry()
	return {
		&"fractures": _telemetry_fractures,
		&"card_uses": _telemetry_card_uses.duplicate(),
		&"relic_trigger_counts": relic_telemetry[&"trigger_counts"],
		&"relic_net_benefits": relic_telemetry[&"net_benefits"],
	}


# ---------------------------------------------------------------------- 回合流程

func _start_player_turn() -> void:
	_ended_hand_snapshot.clear()
	player_block = 0
	energy = BASE_ENERGY
	rule_engine.begin_player_turn()
	instability_gained_this_turn = false
	cards_played_this_turn = 0
	attack_played_this_turn = false
	card_unsealed_this_turn = false
	prevent_next_fracture_damage = false
	extra_draws_this_turn = 0
	binding_triggered_this_turn = false
	stone_shell_broken_this_turn = false
	last_nonstatus_card_type = -1
	last_card_type = -1
	last_card_id = &""
	last_card_upgrade_id = &""
	last_card_base_cost = -1
	last_card_exhausts = false
	last_card_temporary = false
	last_damage_snapshot = 0
	last_block_snapshot = 0
	# 倒读者读取上一回合最后一张非状态牌，因此在回合开始时提交记录，
	# 让本回合的意图从一开始就可以被玩家看见。
	reverse_record_type = reverse_record_pending
	reverse_record_pending = -1
	_clear_temporary_cost_overrides()
	_regenerate_stone_shell()
	for message: String in rule_engine.advance_turn_statuses():
		_log(message)
	_log("第 %d 回合：格挡清零，稳定度恢复至 %d。" % [turn_number, energy])
	_resolve_sealed_cards()
	if battle_over or boss_terminal_choice_pending:
		return
	var target_hand_size: int = BASE_HAND_SIZE + initial_draw_bonus if turn_number == 1 else BASE_HAND_SIZE
	var cards_needed: int = maxi(0, target_hand_size - hand.size())
	draw_cards(cards_needed, true)


func _resolve_sealed_cards() -> void:
	for card: CardData in sealed_zone:
		card.sealed_turns -= 1
	var index: int = 0
	while index < sealed_zone.size():
		if sealed_zone[index].sealed_turns > 0:
			index += 1
			continue
		_unseal_card_at(index)
		if battle_over or boss_terminal_choice_pending:
			return


func _unseal_card_at(index: int) -> void:
	var card: CardData = sealed_zone[index]
	sealed_zone.remove_at(index)
	card_unsealed_this_turn = true
	_log("《%s》解封。" % card.title)
	_restore_earliest_boss_type_edit()
	match card.id:
		&"delayed_guard":
			var gained: int = _gain_player_block(
				card.value(&"unseal_block", 12), card.title, false, 12, card.upgrade_id != &""
			)
			_log("解封效果：获得 %d 格挡。" % gained)
		&"countdown_scar":
			var target: int = TargetSelector.resolve_enemy(
				TargetSelector.Kind.LOWEST_HP_ENEMY, build_target_context()
			)
			_deal_damage_to_enemy(card.value(&"unseal_damage", 18), CardData.CardType.ATTACK, card.title, target)
	if hand.size() < MAX_HAND_SIZE:
		hand.append(card)
		_log("《%s》返回手牌。" % card.title)
	else:
		discard_pile.append(card)
		_log("手牌已满，《%s》进入弃牌堆。" % card.title)
	if boss_transition_pending:
		_apply_boss_phase_transition()


func _generate_card_effects(card: CardData) -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	match card.id:
		&"calibration_strike":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, card.value(&"damage", 6)))
		&"temporary_guard":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, card.value(&"block", 5)))
		&"boundary_read":
			effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 2))
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, card.value(&"overload", 2)))
		&"aftershock":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 5))
			if instability_gained_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, card.value(&"bonus_damage", 4)))
		&"broken_sentence":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, card.value(&"damage", 7)))
			if cards_played_this_turn == 0:
				effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 1))
		&"blank_space":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, card.value(&"base_block", 7)))
			if not attack_played_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 3))
		&"index_reorder":
			effects.append(
				CardEffect.new(CardEffect.Kind.DISCARD_CHOSEN_FROM_TOP, 1).with_target(
					TargetSelector.Kind.DRAW_PILE_TOP, "选择置入弃牌堆的牌",
					TargetSelector.Filter.NONE, card.value(&"look_count", 3)
				)
			)
		&"unsigned_support":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, card.value(&"base_block", 6)))
			if card_unsealed_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 5))
		&"rift_slash":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, card.value(&"damage", 11)))
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, card.value(&"overload", 2)))
		&"forced_stability":
			effects.append(CardEffect.new(CardEffect.Kind.REDUCE_INSTABILITY, 3, card.value(&"block_per_instability", 2)))
		&"critical_permission":
			effects.append(CardEffect.new(CardEffect.Kind.PREVENT_FRACTURE, 1))
			effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 1))
		&"dissolution_protocol":
			effects.append(CardEffect.new(CardEffect.Kind.DISSOLUTION_ATTACK, card.value(&"base_damage", 14), 2))
		&"delayed_guard":
			effects.append(CardEffect.new(CardEffect.Kind.SEAL_CARD, card.value(&"sealed_turns", 1)))
		&"countdown_scar":
			effects.append(CardEffect.new(CardEffect.Kind.SEAL_CARD, card.value(&"sealed_turns", 2)))
		&"prewritten_ending":
			effects.append(
				CardEffect.new(CardEffect.Kind.PREWRITE_COPY, 1).with_target(
					TargetSelector.Kind.HAND_CARD, "选择被复制并封存的手牌",
					TargetSelector.Filter.NON_EXHAUST
				)
			)
		&"unseal_order":
			effects.append(
				CardEffect.new(CardEffect.Kind.UNSEAL_CHOSEN, 1).with_target(
					TargetSelector.Kind.SEALED_CARD, "选择立即解封的封存牌"
				)
			)
			var unseal_overload: int = card.value(&"overload", 2)
			if unseal_overload > 0:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, unseal_overload))
		&"restate":
			effects.append(CardEffect.new(CardEffect.Kind.ECHO_ATTACK, card.value(&"echo_percent", 60)))
		&"copied_guard":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, card.value(&"base_block", 4)))
			effects.append(CardEffect.new(CardEffect.Kind.ECHO_BLOCK, 50))
		&"homophone":
			effects.append(CardEffect.new(CardEffect.Kind.COPY_PREVIOUS, 1))
			var copy_overload: int = card.value(&"overload", 1)
			if copy_overload > 0:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, copy_overload))
	return effects


func _base_effect_for_current_index(card: CardData) -> CardEffect:
	if card == null or card.upgrade_id == &"":
		return null
	var base_card: CardData = CardCatalog.create_card(card.id, card.instance_id)
	var base_effects: Array[CardEffect] = _generate_card_effects(base_card)
	if _play_effect_index < 0 or _play_effect_index >= base_effects.size():
		return null
	return base_effects[_play_effect_index]


func _filter_deleted_keyword_effects(card: CardData, effects: Array[CardEffect]) -> Array[CardEffect]:
	if not boss_deleted_keywords.has(card.instance_id):
		return effects
	var filtered: Array[CardEffect] = []
	for effect: CardEffect in effects:
		var keyword: StringName = &""
		match effect.kind:
			CardEffect.Kind.GAIN_INSTABILITY:
				keyword = &"超载"
			CardEffect.Kind.SEAL_CARD, CardEffect.Kind.PREWRITE_COPY:
				keyword = &"封存"
			CardEffect.Kind.ECHO_ATTACK, CardEffect.Kind.ECHO_BLOCK:
				keyword = &"回响"
		if keyword != &"" and not is_card_keyword_active(card, keyword):
			_log("《%s》的关键词“%s”已删除，附加效果不结算。" % [card.title, keyword])
			continue
		filtered.append(effect)
	return filtered


# ------------------------------------------------------------------ 数值结算

func _seal_card(card: CardData, base_turns: int, source_name: String) -> void:
	var adjusted_turns: int = rule_engine.adjust_first_seal_countdown(base_turns)
	card.sealed_turns = adjusted_turns
	sealed_zone.append(card)
	_log("%s进入封存区，倒计时 %d。" % [source_name, adjusted_turns])
	if adjusted_turns < base_turns:
		_log("延迟齿轮触发：倒计时 %d → %d；本效果队列不立即解封，将在下一次封存结算窗口处理。" % [
			base_turns, adjusted_turns,
		])


func _apply_echo_hyoid() -> void:
	var bonus_block: int = rule_engine.consume_echo_hyoid_block()
	if bonus_block <= 0:
		return
	var gained: int = _gain_player_block(bonus_block, "复读舌骨", false)
	_log("复读舌骨触发：本回合第一次成功回响，额外获得 %d 格挡。" % gained)


func _log_red_pen_if_just_triggered() -> void:
	var telemetry: Dictionary = rule_engine.get_relic_telemetry()
	var counts: Dictionary = telemetry[&"trigger_counts"]
	var current: int = int(counts.get(&"calibrator_red_pen", 0))
	if current <= _logged_red_pen_triggers:
		return
	_logged_red_pen_triggers = current
	_log("校准官的红笔触发：升级实例本次正伤害或格挡高于未升级基线，首个符合结果额外 +3。")


func _gain_player_block(
	amount: int,
	source_name: String,
	write_log: bool = true,
	upgrade_baseline: int = -1,
	is_upgraded: bool = false
) -> int:
	var gained: int = rule_engine.compute_block(amount, upgrade_baseline, is_upgraded)
	player_block += gained
	if write_log and gained > 0:
		_log("《%s》使你获得 %d 格挡。" % [source_name, gained])
	_log_red_pen_if_just_triggered()
	return gained


func _gain_instability(amount: int) -> void:
	var gained: int = rule_engine.compute_instability_gain(amount)
	if gained < amount:
		_log("裂纹稳定器生效：本次超载减少 %d 点。" % (amount - gained))
	instability += gained
	if gained > 0:
		instability_gained_this_turn = true
	_log("超载 %d：不稳定升至 %d。" % [gained, instability])


func _deal_damage_to_enemy(
	base_amount: int,
	source_type: int,
	source_name: String,
	target_index: int,
	upgrade_baseline: int = -1,
	is_upgraded: bool = false
) -> int:
	if base_amount <= 0 or battle_over or boss_terminal_choice_pending:
		return 0
	if target_index == TargetSelector.NO_TARGET:
		_log("《%s》没有可攻击的目标。" % source_name)
		return 0
	var amount: int = rule_engine.compute_damage_to_enemy(
		base_amount, source_type == CardData.CardType.ATTACK, upgrade_baseline, is_upgraded
	)
	_log_red_pen_if_just_triggered()
	if amount <= 0:
		return 0
	_record_devour(source_type)
	var blocked_by_intent: int = mini(enemy_block, amount)
	enemy_block -= blocked_by_intent
	var remaining: int = amount - blocked_by_intent
	var blocked_by_shell: int = mini(stone_shell, remaining)
	stone_shell -= blocked_by_shell
	remaining -= blocked_by_shell
	if blocked_by_shell > 0 and stone_shell == 0:
		stone_shell_broken_this_turn = true
		_log("%s的石壳被击碎。" % enemy_name)
	var hp_floor: int = BOSS_TERMINAL_HP if is_name_eraser_battle() else 0
	enemy_hp = maxi(hp_floor, enemy_hp - remaining)
	_log("《%s》造成 %d 伤害（格挡抵消 %d），%s生命 %d/%d。" % [
		source_name, remaining, blocked_by_intent + blocked_by_shell,
		enemy_name, enemy_hp, enemy_max_hp,
	])
	if is_name_eraser_battle():
		if boss_phase == 1 and enemy_hp <= BOSS_PHASE_TWO_THRESHOLD:
			boss_transition_pending = true
		if enemy_hp <= BOSS_TERMINAL_HP:
			_enter_boss_terminal()
	elif enemy_hp <= 0:
		battle_over = true
		victory = true
		_log("战斗胜利：穿过路径节点 %d/%d。" % [tutorial_stage, TUTORIAL_STAGE_MAX])
	return remaining


func _deal_damage_to_player(base_amount: int, source_name: String) -> void:
	var amount: int = rule_engine.compute_damage_to_player(base_amount, true)
	rule_engine.enemy_next_attack_bonus = 0
	var blocked: int = mini(player_block, amount)
	player_block -= blocked
	var hp_damage: int = amount - blocked
	var previous_hp: int = player_hp
	var bell_triggered: bool = rule_engine.consume_expired_return_bell(hp_damage >= player_hp and hp_damage > 0)
	player_hp = 1 if bell_triggered else maxi(0, player_hp - hp_damage)
	_log("%s使用%s：造成 %d 伤害（格挡抵消 %d），你的生命 %d/%d。" % [
		enemy_name, source_name, hp_damage, blocked, player_hp, player_max_hp,
	])
	_trigger_blank_epitaph(previous_hp)
	if bell_triggered:
		_log("过期返航铃触发：本次致命伤害后保留 1 点生命；立即执行裂解，本次裂解及之后的伤害仍可能致死。")
		_resolve_fracture(false, "返航铃后续裂解")
	else:
		_check_player_defeat()


func _record_devour(source_type: int) -> void:
	if enemy_definition == null or not enemy_definition.has_trait(EnemyDefinition.TRAIT_DEVOUR):
		return
	if not is_mechanic_unlocked(&"missing_name") or devour_record_type >= 0:
		return
	if source_type < 0 or source_type == CardData.CardType.STATUS:
		return
	devour_record_type = source_type
	_log("%s吞下%s符号。" % [enemy_name, CardData.type_display_name(source_type)])


## 空名卫士“同式适应”：连续两张同类别非状态牌使其获得格挡；类别不同则石壳全失。
func _apply_same_type_adaptation(card_type: int) -> void:
	if enemy_definition == null or not enemy_definition.has_trait(EnemyDefinition.TRAIT_STONE_SHELL):
		return
	if battle_over or last_nonstatus_card_type < 0:
		return
	if last_nonstatus_card_type == card_type:
		enemy_block += enemy_definition.stone_shell_adapt_block
		_log("同式适应：连续两张%s牌让%s获得 %d 格挡。" % [
			CardData.type_display_name(card_type), enemy_name,
			enemy_definition.stone_shell_adapt_block,
		])
	elif stone_shell > 0:
		stone_shell = 0
		stone_shell_broken_this_turn = true
		_log("类别切换：%s失去全部石壳。" % enemy_name)


func _regenerate_stone_shell() -> void:
	if enemy_definition == null or not enemy_definition.has_trait(EnemyDefinition.TRAIT_STONE_SHELL):
		return
	if turn_number == 1:
		stone_shell = enemy_definition.stone_shell_initial
		_log("%s的石壳初始为 %d。" % [enemy_name, stone_shell])
		return
	if stone_shell >= enemy_definition.stone_shell_initial:
		return
	var restored: int = mini(
		enemy_definition.stone_shell_regen, enemy_definition.stone_shell_initial - stone_shell
	)
	stone_shell += restored
	_log("%s的石壳恢复 %d，现为 %d。" % [enemy_name, restored, stone_shell])


## 装订刑具“装订”被动：单回合额外抽牌达到阈值时，把一张状态牌放入弃牌堆。
func _check_binding_passive() -> void:
	if enemy_definition == null or not enemy_definition.has_trait(EnemyDefinition.TRAIT_BINDING):
		return
	if binding_triggered_this_turn:
		return
	if extra_draws_this_turn < enemy_definition.binding_draw_threshold:
		return
	binding_triggered_this_turn = true
	var card: CardData = _make_card_from_catalog(enemy_definition.binding_card_id)
	discard_pile.append(card)
	_log("装订触发：本回合额外抽牌达到 %d 张，《%s》被放入弃牌堆。" % [
		enemy_definition.binding_draw_threshold, card.title,
	])


# -------------------------------------------------------------------- 敌人行动

func _execute_enemy_intent() -> void:
	if enemy_definition == null:
		return
	enemy_block = 0
	var intent: EnemyIntent = enemy_definition.select_intent(enemy_intent_index, reverse_record_type, boss_phase)
	if intent == null:
		return
	var context: IntentContext = build_intent_context(false)
	# 意图执行时手牌已弃置，因此“手牌是否存在状态牌”读取回合结束前的快照。
	context.player_hand_has_status = _discard_contains_status_from_this_turn()
	_log("%s执行意图：%s。" % [enemy_name, intent.display_name])
	for operation: EnemyOperation in intent.active_operations(context):
		_apply_enemy_operation(operation, context)
		if battle_over:
			return
	enemy_intent_index = (enemy_intent_index + 1) % maxi(
		1, enemy_definition.intent_count_for_phase(boss_phase)
	)


func _apply_enemy_operation(operation: EnemyOperation, context: IntentContext) -> void:
	var message: String = operation.resolve_log_text(enemy_name, context)
	match operation.kind:
		EnemyOperation.Kind.ATTACK:
			for hit_index: int in range(operation.times):
				if battle_over:
					return
				var action: String = operation.action_name
				if operation.times > 1:
					action = "%s（%d/%d）" % [action, hit_index + 1, operation.times]
				_deal_damage_to_player(operation.amount, action)
		EnemyOperation.Kind.GAIN_BLOCK:
			enemy_block += operation.amount
			_log_if(message)
		EnemyOperation.Kind.CHARGE:
			_log_if(message)
		EnemyOperation.Kind.EMPOWER_NEXT_ATTACK:
			rule_engine.enemy_next_attack_bonus += operation.amount
			_log_if(message)
		EnemyOperation.Kind.APPLY_MISSING_NAME_RECORDED:
			if devour_record_type >= 0:
				var stacks: int = int(missing_name.get(devour_record_type, 0)) + operation.amount
				missing_name[devour_record_type] = stacks
				_log_if(message)
		EnemyOperation.Kind.APPLY_MISSING_NAME_FIXED:
			var fixed_stacks: int = int(missing_name.get(operation.card_type, 0)) + operation.amount
			missing_name[operation.card_type] = fixed_stacks
			_log_if(message)
		EnemyOperation.Kind.CLEAR_DEVOUR_RECORD:
			devour_record_type = -1
			_log_if(message)
		EnemyOperation.Kind.ADD_CARD_TO_DRAW_PILE:
			for copy_index: int in range(operation.amount):
				draw_pile.append(_make_card_from_catalog(operation.card_id))
			_shuffle_cards(draw_pile)
			_log_if(message)
		EnemyOperation.Kind.ADD_CARD_TO_DISCARD_PILE:
			for copy_index: int in range(operation.amount):
				discard_pile.append(_make_card_from_catalog(operation.card_id))
			_log_if(message)
		EnemyOperation.Kind.APPLY_VULNERABLE:
			rule_engine.player_vulnerable_turns += operation.amount
			_log_if(message)
		EnemyOperation.Kind.APPLY_WEAK:
			rule_engine.player_weak_turns += operation.amount
			_log_if(message)
		EnemyOperation.Kind.CLEANSE_SELF:
			rule_engine.enemy_vulnerable_turns = 0
			_log_if(message)
		EnemyOperation.Kind.SELF_DAMAGE:
			enemy_hp = maxi(0, enemy_hp - operation.amount)
			_log_if(message)
			if enemy_hp <= 0:
				battle_over = true
				victory = true
				_log("战斗胜利：%s被自身规则终结。" % enemy_name)
		EnemyOperation.Kind.RESTORE_STONE_SHELL:
			stone_shell = mini(
				enemy_definition.stone_shell_initial, stone_shell + operation.amount
			)
			_log_if(message)
		EnemyOperation.Kind.EDIT_CARD_COSTS:
			_edit_boss_card_costs(operation.amount)
		EnemyOperation.Kind.MARK_NEXT_DRAW_TYPE_DELETION:
			boss_delete_next_draw_type = true
			_log("删除类别已标记：下次抽到的第一张非状态牌进入手牌时失去类别；封存牌解封可恢复。")
		EnemyOperation.Kind.DELETE_HAND_KEYWORDS:
			_delete_boss_hand_keywords()
		EnemyOperation.Kind.CLEAR_MISSING_NAME_GAIN_STRENGTH:
			_clear_missing_name_gain_boss_strength()


func _discard_contains_status_from_this_turn() -> bool:
	for card: CardData in _ended_hand_snapshot:
		if card.card_type == CardData.CardType.STATUS:
			return true
	return false


# -------------------------------------------------------------------- 其他规则

func _check_fracture() -> void:
	if instability < instability_threshold or battle_over:
		return
	_resolve_fracture(true, "不稳定阈值")


func _resolve_fracture(consume_instability: bool, source_name: String) -> void:
	if battle_over:
		return
	if consume_instability:
		instability -= instability_threshold
	_telemetry_fractures += 1
	var prevented: bool = prevent_next_fracture_damage
	var damage: int = rule_engine.compute_fracture_damage(fracture_damage, prevented)
	if prevented:
		prevent_next_fracture_damage = false
	var previous_hp: int = player_hp
	var bell_triggered: bool = rule_engine.consume_expired_return_bell(damage >= player_hp and damage > 0)
	player_hp = 1 if bell_triggered else maxi(0, player_hp - damage)
	var instability_text: String = "不稳定降至 %d" % instability if consume_instability else "不稳定保持 %d" % instability
	_log("裂解触发（%s）：受到 %d 点不可格挡伤害，%s，生命 %d/%d。" % [
		source_name, damage, instability_text, player_hp, player_max_hp,
	])
	_restore_earliest_boss_keyword_edit()
	_trigger_blank_epitaph(previous_hp)
	if bell_triggered:
		_log("过期返航铃触发：本次致命裂解后保留 1 点生命；立即执行额外裂解，本次额外裂解及之后的伤害仍可能致死。")
		_resolve_fracture(false, "返航铃后续裂解")
	else:
		_check_player_defeat()


func _trigger_blank_epitaph(previous_hp: int) -> void:
	if not rule_engine.consume_blank_epitaph(previous_hp, player_hp, player_max_hp):
		return
	var gained: int = _gain_player_block(12, "空白墓志铭", false)
	var candidates: Array[int] = []
	for index: int in range(hand.size()):
		if hand[index].card_type != CardData.CardType.STATUS:
			candidates.append(index)
	if candidates.is_empty():
		_log("空白墓志铭触发：伤害已经结算，获得 %d 格挡；当前手牌没有合规非状态牌，仍消耗本场触发。" % gained)
		return
	var chosen_index: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var chosen: CardData = hand[chosen_index]
	hand.remove_at(chosen_index)
	_seal_card(chosen, 1, "空白墓志铭选中的《%s》" % chosen.title)
	_log("空白墓志铭触发：伤害已经结算，获得 %d 格挡并随机封存《%s》；新格挡只保护后续伤害。" % [
		gained, chosen.title,
	])


func _check_player_defeat() -> void:
	if player_hp > 0:
		return
	battle_over = true
	victory = false
	_log("战斗失败：回收者记录中断。")


func _consume_missing_name(card_type: int) -> void:
	var stacks: int = int(missing_name.get(card_type, 0))
	if stacks <= 0:
		return
	stacks -= 1
	missing_name[card_type] = stacks
	_log("%s缺名被消耗，剩余 %d 层。" % [CardData.type_display_name(card_type), stacks])


func _configure_tutorial_stage() -> void:
	match tutorial_stage:
		1:
			tutorial_stage_title = "第七码头·空白室"
			tutorial_hint = "墙上的旧告示只剩两行：出手，或护住自己。"
		2:
			tutorial_stage_title = "无字街口"
			tutorial_hint = "守卫抬起武器之前，胸前石片会先显出下一步动作。"
		3:
			tutorial_stage_title = "裂隙测量井"
			tutorial_hint = "井壁渗出的蓝光让规则变得更锋利，也更不稳定。"
		4:
			tutorial_stage_title = "迟钟长廊"
			tutorial_hint = "这里的动作总在数拍之后才抵达。远处的重锤节奏固定。"
		5:
			tutorial_stage_title = "回声阅览室"
			tutorial_hint = "第二个声音会复述第一个动作，却从不复述它的原因。"
		6:
			tutorial_stage_title = "吞字巢穴"
			tutorial_hint = "虫腹里滚动着你刚使用的文字。它似乎在等待同类词句。"


func _configure_enemy(p_enemy_id: StringName) -> void:
	assert(EnemyCatalog.has_enemy(p_enemy_id), "未知敌人定义：%s" % p_enemy_id)
	enemy_id = p_enemy_id
	enemy_definition = EnemyCatalog.create(p_enemy_id)
	enemy_name = enemy_definition.display_name
	# 生命范围相等时不消耗随机数，保证既有六个路径节点的洗牌结果完全不变。
	if enemy_definition.hp_max > enemy_definition.hp_min:
		enemy_max_hp = rng.randi_range(enemy_definition.hp_min, enemy_definition.hp_max)
	else:
		enemy_max_hp = enemy_definition.hp_min
	enemy_hp = enemy_max_hp
	if enemy_definition.has_trait(EnemyDefinition.TRAIT_NAME_ERASER):
		boss_phase = 1
		tutorial_hint = enemy_definition.intro_line
	elif not enemy_definition.intro_line.is_empty() and enemy_definition.tier != "训练":
		tutorial_hint = enemy_definition.intro_line if tutorial_hint.is_empty() else tutorial_hint


func _build_tutorial_deck() -> void:
	match tutorial_stage:
		1, 2:
			_add_basic_cards(5, 5)
		3:
			_add_basic_cards(4, 3)
			_add_card_by_id(&"boundary_read")
			_add_card_by_id(&"rift_slash")
			_add_card_by_id(&"forced_stability")
		4:
			_add_basic_cards(3, 3)
			_add_card_by_id(&"boundary_read")
			_add_card_by_id(&"forced_stability")
			_add_card_by_id(&"delayed_guard")
			_add_card_by_id(&"countdown_scar")
		5:
			_add_basic_cards(3, 2)
			_add_card_by_id(&"rift_slash")
			_add_card_by_id(&"forced_stability")
			_add_card_by_id(&"delayed_guard")
			_add_card_by_id(&"countdown_scar")
			_add_card_by_id(&"restate")
		6:
			_add_basic_cards(4, 4)
			for card_id: StringName in [
				&"boundary_read",
				&"aftershock",
				&"rift_slash",
				&"forced_stability",
				&"delayed_guard",
				&"countdown_scar",
				&"restate",
			]:
				_add_card_by_id(card_id)


func _build_run_deck(deck_instances: Array[Dictionary]) -> void:
	for instance: Dictionary in deck_instances:
		var instance_id: int = int(instance[&"instance_id"])
		var card_id: StringName = instance[&"card_id"] as StringName
		var upgrade_id: StringName = instance.get(&"upgrade_id", &"") as StringName
		draw_pile.append(CardCatalog.create_card(card_id, instance_id, upgrade_id))
		next_instance_id = maxi(next_instance_id, instance_id + 1)


func _add_basic_cards(attack_count: int, defense_count: int) -> void:
	for duplicate_index: int in range(attack_count):
		_add_card_by_id(&"calibration_strike")
	for duplicate_index: int in range(defense_count):
		_add_card_by_id(&"temporary_guard")


func _add_card_by_id(card_id: StringName) -> void:
	if not CardCatalog.has_card(card_id):
		push_error("未知卡牌定义：%s" % card_id)
		return
	draw_pile.append(_make_card_from_catalog(card_id))


func _make_card_from_catalog(card_id: StringName, upgrade_id: StringName = &"") -> CardData:
	var card: CardData = CardCatalog.create_card(card_id, next_instance_id, upgrade_id)
	next_instance_id += 1
	return card


func _copy_previous_card_to_hand() -> void:
	if last_card_id == &"" or last_card_id == &"homophone":
		_log("同音异义复制失败：没有可复制的紧邻上一张牌。")
		return
	if last_card_base_cost > 1 or last_card_exhausts or last_card_temporary:
		_log("同音异义复制失败：上一张牌费用过高、会消逝或是临时牌。")
		return
	if hand.size() >= MAX_HAND_SIZE:
		_log("同音异义复制失败：手牌已满。")
		return
	var copy: CardData = _make_card_from_catalog(last_card_id, last_card_upgrade_id)
	copy.temporary = true
	copy.exhausts = true
	copy.cost_override_this_turn = 0
	hand.append(copy)
	_log("同音异义生成《%s》的临时复制品：本回合费用 0，使用后消逝。" % copy.title)


func _clear_temporary_cost_overrides() -> void:
	for pile: Array[CardData] in [draw_pile, hand, discard_pile, sealed_zone]:
		for card: CardData in pile:
			card.cost_override_this_turn = -1


func _shuffle_cards(cards: Array[CardData]) -> void:
	for index: int in range(cards.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var held: CardData = cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = held


func _log_if(message: String) -> void:
	if not message.is_empty():
		_log(message)


func _log(message: String) -> void:
	log_entries.append(message)
