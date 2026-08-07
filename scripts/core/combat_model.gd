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

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = DEFAULT_SEED
var next_instance_id: int = 1

var rule_engine: RuleEngine = RuleEngine.new()

var player_hp: int = PLAYER_MAX_HP
var player_block: int = 0
var energy: int = BASE_ENERGY
var instability: int = 0
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

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var sealed_zone: Array[CardData] = []
var exhausted_zone: Array[CardData] = []
var log_entries: Array[String] = []
var missing_name: Dictionary = {}

var _telemetry_fractures: int = 0
var _telemetry_card_uses: Dictionary = {}

var last_card_type: int = -1
var last_card_id: StringName = &""
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
	p_relics: Array[StringName] = []
) -> void:
	seed_value = p_seed
	rng.seed = seed_value
	tutorial_stage = clampi(p_tutorial_stage, TUTORIAL_STAGE_MIN, TUTORIAL_STAGE_MAX)
	next_instance_id = 1
	player_hp = PLAYER_MAX_HP
	player_block = 0
	energy = BASE_ENERGY
	instability = 0
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
	turn_number = 1
	battle_over = false
	victory = false
	cards_played_this_turn = 0
	attack_played_this_turn = false
	card_unsealed_this_turn = false
	prevent_next_fracture_damage = false
	last_card_id = &""
	last_card_base_cost = -1
	last_card_exhausts = false
	last_card_temporary = false
	pending_selection = null
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
	rule_engine.reset_for_battle(p_relics)
	_configure_tutorial_stage()
	_configure_enemy(p_enemy_id if p_enemy_id != &"" else EnemyCatalog.enemy_id_for_path_stage(tutorial_stage))
	_build_tutorial_deck()
	# 六场序章继续使用原有渐进教学牌组；RunModel 中永久获得的牌作为额外牌加入，
	# 从而既不提前暴露后续关键词，也保证奖励会进入后续战斗。
	for bonus_card_id: StringName in p_bonus_card_ids:
		_add_card_by_id(bonus_card_id)
	_shuffle_cards(draw_pile)
	_log("路径节点 %d/%d：%s。" % [tutorial_stage, TUTORIAL_STAGE_MAX, tutorial_stage_title])
	_log("%s出现，生命 %d。" % [enemy_name, enemy_hp])
	if not rule_engine.relics.is_empty():
		_log("携带遗物：%s。" % rule_engine.get_relic_text())
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
		context.enemy_hps.append(get_enemy_hp(index))
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
	if battle_over or pending_selection != null:
		return false
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
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
	if int(missing_name.get(card.card_type, 0)) > 0:
		_play_missing_name_refund_type = card.card_type
	_consume_missing_name(card.card_type)
	hand.remove_at(hand_index)
	_log("打出《%s》[%s]，消耗 %d 稳定度。" % [card.title, card.type_name(), cost])

	_play_card = card
	_play_hand_index = hand_index
	_play_effects = _generate_card_effects(card)
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
	match effect.kind:
		CardEffect.Kind.DAMAGE_ENEMY:
			var target: int = TargetSelector.resolve_enemy(effect.target_kind, build_target_context())
			_play_resolved_damage += _deal_damage_to_enemy(effect.amount, card.card_type, card.title, target)
		CardEffect.Kind.GAIN_BLOCK:
			_play_resolved_block += _gain_player_block(effect.amount, card.title)
		CardEffect.Kind.DRAW_CARDS:
			draw_cards(effect.amount, false)
		CardEffect.Kind.GAIN_INSTABILITY:
			_gain_instability(effect.amount)
		CardEffect.Kind.REDUCE_INSTABILITY:
			var reduced: int = mini(instability, effect.amount)
			instability -= reduced
			var converted_block: int = rule_engine.compute_block(reduced * effect.factor)
			player_block += converted_block
			_play_resolved_block += converted_block
			_log("不稳定减少 %d；转化为 %d 格挡。" % [reduced, converted_block])
		CardEffect.Kind.SEAL_CARD:
			card.sealed_turns = effect.amount
			sealed_zone.append(card)
			_play_card_was_sealed = true
			_log("《%s》封存 %d 回合。" % [card.title, effect.amount])
		CardEffect.Kind.ECHO_ATTACK:
			if last_card_type == CardData.CardType.ATTACK:
				var echoed_damage: int = floori(float(last_damage_snapshot) * float(effect.amount) / 100.0)
				_log("回响上一张攻式已结算伤害的 %d%%：%d。" % [effect.amount, echoed_damage])
				# 回响沿用原目标；原目标已死亡时改为指向生命最低的敌人。
				var echo_target: int = TargetSelector.resolve_enemy(
					TargetSelector.Kind.LOWEST_HP_ENEMY, build_target_context()
				)
				_play_resolved_damage += _deal_damage_to_enemy(
					echoed_damage, card.card_type, card.title, echo_target
				)
			else:
				_log("回响失败：紧邻上一张牌不是攻式。")
		CardEffect.Kind.ECHO_BLOCK:
			if last_card_type == CardData.CardType.DEFENSE:
				var echoed_block: int = floori(float(last_block_snapshot) * float(effect.amount) / 100.0)
				_play_resolved_block += _gain_player_block(echoed_block, card.title, false)
				_log("回响上一张守式已结算格挡的 %d%%：%d。" % [effect.amount, echoed_block])
			else:
				_log("回响失败：紧邻上一张牌不是守式。")
		CardEffect.Kind.PREVENT_FRACTURE:
			prevent_next_fracture_damage = true
			_log("本回合下一次裂解伤害将变为 0。")
		CardEffect.Kind.DISSOLUTION_ATTACK:
			var dissolution_damage: int = effect.amount + instability * effect.factor
			var dissolution_target: int = TargetSelector.resolve_enemy(
				effect.target_kind, build_target_context()
			)
			_play_resolved_damage += _deal_damage_to_enemy(
				dissolution_damage, card.card_type, card.title, dissolution_target
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
			var copy: CardData = _make_card_from_catalog(original.id)
			copy.temporary = true
			copy.sealed_turns = 1
			sealed_zone.append(copy)
			_log("预写结局：复制《%s》并封存 1；原牌本回合费用变为 0。" % original.title)
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
		if card.exhausts:
			exhausted_zone.append(card)
			_log("《%s》进入消逝区。" % card.title)
		else:
			discard_pile.append(card)

	cards_played_this_turn += 1
	_telemetry_card_uses[card.id] = int(_telemetry_card_uses.get(card.id, 0)) + 1
	if card.card_type == CardData.CardType.ATTACK:
		attack_played_this_turn = true
	if card.card_type != CardData.CardType.STATUS:
		_apply_same_type_adaptation(card.card_type)
		reverse_record_pending = card.card_type
		last_nonstatus_card_type = card.card_type
	last_card_type = card.card_type
	last_card_id = card.id
	last_card_base_cost = card.base_cost
	last_card_exhausts = card.exhausts
	last_card_temporary = card.temporary
	last_damage_snapshot = _play_resolved_damage
	last_block_snapshot = _play_resolved_block
	var bookplate_draw: int = rule_engine.consume_bookplate_draw(card.card_type)
	if bookplate_draw > 0 and not battle_over:
		_log("无字藏书票触发：本场战斗第一次打出律式，抽 %d 张牌。" % bookplate_draw)
		draw_cards(bookplate_draw, false)
	_clear_play_state()
	if not battle_over:
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
	if battle_over or pending_selection != null:
		return
	_log("结束第 %d 回合：弃置 %d 张手牌。" % [turn_number, hand.size()])
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
		hand.append(card)
		_log("抽到《%s》。" % card.title)


func get_card_cost(card: CardData) -> int:
	var base: int = card.cost_override_this_turn if card.cost_override_this_turn >= 0 else card.base_cost
	return rule_engine.compute_cost(base, int(missing_name.get(card.card_type, 0)))


# ------------------------------------------------------------------ 意图与展示

func build_intent_context(use_current_hand: bool = true) -> IntentContext:
	var context: IntentContext = IntentContext.new()
	context.devour_record_type = devour_record_type
	context.reverse_record_type = reverse_record_type
	context.stone_shell_broken = stone_shell_broken_this_turn
	if use_current_hand:
		for card: CardData in hand:
			if card.card_type == CardData.CardType.STATUS:
				context.player_hand_has_status = true
				break
	return context


func get_current_intent() -> EnemyIntent:
	if enemy_definition == null:
		return null
	return enemy_definition.select_intent(enemy_intent_index, reverse_record_type)


func get_enemy_intent_text() -> String:
	var intent: EnemyIntent = get_current_intent()
	if intent == null:
		return "未知意图"
	return intent.describe(build_intent_context())


func get_enemy_record_text() -> String:
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


func get_sealed_summary() -> String:
	if sealed_zone.is_empty():
		return "无"
	var parts: Array[String] = []
	for card: CardData in sealed_zone:
		parts.append("%s(%d)" % [card.title, card.sealed_turns])
	return "、".join(parts)


func get_player_status_text() -> String:
	return rule_engine.get_status_text()


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
	player_block = 0
	energy = BASE_ENERGY
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
	_log("—— 第 %d 回合：格挡清零，稳定度恢复至 %d ——" % [turn_number, energy])
	_resolve_sealed_cards()
	if battle_over:
		return
	var cards_needed: int = maxi(0, BASE_HAND_SIZE - hand.size())
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
		if battle_over:
			return


func _unseal_card_at(index: int) -> void:
	var card: CardData = sealed_zone[index]
	sealed_zone.remove_at(index)
	card_unsealed_this_turn = true
	_log("《%s》解封。" % card.title)
	match card.id:
		&"delayed_guard":
			var gained: int = _gain_player_block(12, card.title, false)
			_log("解封效果：获得 %d 格挡。" % gained)
		&"countdown_scar":
			var target: int = TargetSelector.resolve_enemy(
				TargetSelector.Kind.LOWEST_HP_ENEMY, build_target_context()
			)
			_deal_damage_to_enemy(18, CardData.CardType.ATTACK, card.title, target)
	if hand.size() < MAX_HAND_SIZE:
		hand.append(card)
		_log("《%s》返回手牌。" % card.title)
	else:
		discard_pile.append(card)
		_log("手牌已满，《%s》进入弃牌堆。" % card.title)


func _generate_card_effects(card: CardData) -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	match card.id:
		&"calibration_strike":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 6))
		&"temporary_guard":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 5))
		&"boundary_read":
			effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 2))
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, 2))
		&"aftershock":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 5))
			if instability_gained_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 4))
		&"broken_sentence":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 7))
			if cards_played_this_turn == 0:
				effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 1))
		&"blank_space":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 7))
			if not attack_played_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 3))
		&"index_reorder":
			# 真实选择流程：查看抽牌堆顶 3 张，由玩家指定其中 1 张置入弃牌堆。
			effects.append(
				CardEffect.new(CardEffect.Kind.DISCARD_CHOSEN_FROM_TOP, 1).with_target(
					TargetSelector.Kind.DRAW_PILE_TOP, "选择置入弃牌堆的牌",
					TargetSelector.Filter.NONE, 3
				)
			)
		&"unsigned_support":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 6))
			if card_unsealed_this_turn:
				effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 5))
		&"rift_slash":
			effects.append(CardEffect.new(CardEffect.Kind.DAMAGE_ENEMY, 11))
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, 2))
		&"forced_stability":
			effects.append(CardEffect.new(CardEffect.Kind.REDUCE_INSTABILITY, 3, 2))
		&"critical_permission":
			effects.append(CardEffect.new(CardEffect.Kind.PREVENT_FRACTURE, 1))
			effects.append(CardEffect.new(CardEffect.Kind.DRAW_CARDS, 1))
		&"dissolution_protocol":
			effects.append(CardEffect.new(CardEffect.Kind.DISSOLUTION_ATTACK, 14, 2))
		&"delayed_guard":
			effects.append(CardEffect.new(CardEffect.Kind.SEAL_CARD, 1))
		&"countdown_scar":
			effects.append(CardEffect.new(CardEffect.Kind.SEAL_CARD, 2))
		&"prewritten_ending":
			# 真实选择流程：由玩家指定手牌中的一张非消逝牌。
			effects.append(
				CardEffect.new(CardEffect.Kind.PREWRITE_COPY, 1).with_target(
					TargetSelector.Kind.HAND_CARD, "选择被复制并封存的手牌",
					TargetSelector.Filter.NON_EXHAUST
				)
			)
		&"unseal_order":
			# 真实选择流程：由玩家指定封存区中的一张牌。
			effects.append(
				CardEffect.new(CardEffect.Kind.UNSEAL_CHOSEN, 1).with_target(
					TargetSelector.Kind.SEALED_CARD, "选择立即解封的封存牌"
				)
			)
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, 2))
		&"restate":
			effects.append(CardEffect.new(CardEffect.Kind.ECHO_ATTACK, 60))
		&"copied_guard":
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_BLOCK, 4))
			effects.append(CardEffect.new(CardEffect.Kind.ECHO_BLOCK, 50))
		&"homophone":
			effects.append(CardEffect.new(CardEffect.Kind.COPY_PREVIOUS, 1))
			effects.append(CardEffect.new(CardEffect.Kind.GAIN_INSTABILITY, 1))
	return effects


# ------------------------------------------------------------------ 数值结算

func _gain_player_block(amount: int, source_name: String, write_log: bool = true) -> int:
	var gained: int = rule_engine.compute_block(amount)
	player_block += gained
	if write_log and gained > 0:
		_log("《%s》使你获得 %d 格挡。" % [source_name, gained])
	return gained


func _gain_instability(amount: int) -> void:
	var gained: int = rule_engine.compute_instability_gain(amount)
	if gained < amount:
		_log("裂纹稳定器生效：本次超载减少 %d 点。" % (amount - gained))
	instability += gained
	if gained > 0:
		instability_gained_this_turn = true
	_log("超载 %d：不稳定升至 %d。" % [gained, instability])


func _deal_damage_to_enemy(base_amount: int, source_type: int, source_name: String, target_index: int) -> int:
	if base_amount <= 0 or battle_over:
		return 0
	if target_index == TargetSelector.NO_TARGET:
		_log("《%s》没有可攻击的目标。" % source_name)
		return 0
	var amount: int = rule_engine.compute_damage_to_enemy(
		base_amount, source_type == CardData.CardType.ATTACK
	)
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
	enemy_hp = maxi(0, enemy_hp - remaining)
	_log("《%s》造成 %d 伤害（格挡抵消 %d），%s生命 %d/%d。" % [
		source_name, remaining, blocked_by_intent + blocked_by_shell,
		enemy_name, enemy_hp, enemy_max_hp,
	])
	if enemy_hp <= 0:
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
	player_hp = maxi(0, player_hp - hp_damage)
	_log("%s使用%s：造成 %d 伤害（格挡抵消 %d），你的生命 %d/%d。" % [
		enemy_name, source_name, hp_damage, blocked, player_hp, PLAYER_MAX_HP,
	])
	_check_player_defeat()


func _record_devour(source_type: int) -> void:
	if enemy_definition == null or not enemy_definition.has_trait(EnemyDefinition.TRAIT_DEVOUR):
		return
	if not is_mechanic_unlocked(&"missing_name") or devour_record_type >= 0:
		return
	if source_type == CardData.CardType.STATUS:
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
	var intent: EnemyIntent = enemy_definition.select_intent(enemy_intent_index, reverse_record_type)
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
	enemy_intent_index = (enemy_intent_index + 1) % maxi(1, enemy_definition.intent_count())


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


func _discard_contains_status_from_this_turn() -> bool:
	for card: CardData in discard_pile:
		if card.card_type == CardData.CardType.STATUS:
			return true
	return false


# -------------------------------------------------------------------- 其他规则

func _check_fracture() -> void:
	if instability < INSTABILITY_THRESHOLD or battle_over:
		return
	instability -= INSTABILITY_THRESHOLD
	_telemetry_fractures += 1
	var damage: int = rule_engine.compute_fracture_damage(FRACTURE_DAMAGE, prevent_next_fracture_damage)
	if prevent_next_fracture_damage:
		prevent_next_fracture_damage = false
	player_hp = maxi(0, player_hp - damage)
	_log("裂解触发：受到 %d 点不可格挡伤害，不稳定降至 %d，生命 %d/%d。" % [
		damage, instability, player_hp, PLAYER_MAX_HP,
	])
	_check_player_defeat()


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
	if not enemy_definition.intro_line.is_empty() and enemy_definition.tier != "训练":
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


func _make_card_from_catalog(card_id: StringName) -> CardData:
	var card: CardData = CardCatalog.create_card(card_id, next_instance_id)
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
	var copy: CardData = _make_card_from_catalog(last_card_id)
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
