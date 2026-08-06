class_name CombatModel
extends RefCounted


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

var player_hp: int = PLAYER_MAX_HP
var player_block: int = 0
var energy: int = BASE_ENERGY
var instability: int = 0
var enemy_hp: int = 26
var enemy_max_hp: int = 26
var enemy_block: int = 0
var enemy_intent_index: int = 0
var enemy_recorded_type: int = -1
var turn_number: int = 1
var instability_gained_this_turn: bool = false
var battle_over: bool = false
var victory: bool = false
var tutorial_stage: int = TUTORIAL_STAGE_MIN
var tutorial_stage_title: String = ""
var tutorial_hint: String = ""
var enemy_name: String = ""

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var sealed_zone: Array[CardData] = []
var exhausted_zone: Array[CardData] = []
var log_entries: Array[String] = []
var missing_name: Dictionary = {}

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


func start_battle(
	p_seed: int = DEFAULT_SEED,
	p_tutorial_stage: int = TUTORIAL_STAGE_MIN,
	p_bonus_card_ids: Array[StringName] = []
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
	enemy_recorded_type = -1
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
	missing_name.clear()
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	sealed_zone.clear()
	exhausted_zone.clear()
	log_entries.clear()
	_configure_tutorial_stage()
	enemy_hp = enemy_max_hp
	_build_tutorial_deck()
	# 六场序章继续使用原有渐进教学牌组；RunModel 中永久获得的牌作为额外牌加入，
	# 从而既不提前暴露后续关键词，也保证奖励会进入后续战斗。
	for bonus_card_id: StringName in p_bonus_card_ids:
		_add_card_by_id(bonus_card_id)
	_shuffle_cards(draw_pile)
	_log("路径节点 %d/%d：%s。" % [tutorial_stage, TUTORIAL_STAGE_MAX, tutorial_stage_title])
	_log("%s出现，生命 %d。" % [enemy_name, enemy_hp])
	_start_player_turn()


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


func play_card(hand_index: int) -> bool:
	if battle_over or hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	var cost: int = get_card_cost(card)
	if energy < cost:
		_log("稳定度不足，无法打出《%s》。" % card.title)
		return false

	energy -= cost
	_consume_missing_name(card.card_type)
	hand.remove_at(hand_index)
	_log("打出《%s》[%s]，消耗 %d 稳定度。" % [card.title, card.type_name(), cost])

	var effects: Array[CardEffect] = _generate_card_effects(card)
	var resolved_damage: int = 0
	var resolved_block: int = 0
	var card_was_sealed: bool = false
	for effect: CardEffect in effects:
		match effect.kind:
			CardEffect.Kind.DAMAGE_ENEMY:
				resolved_damage += _deal_damage_to_enemy(effect.amount, card.card_type, card.title)
			CardEffect.Kind.GAIN_BLOCK:
				player_block += effect.amount
				resolved_block += effect.amount
				_log("《%s》使你获得 %d 格挡。" % [card.title, effect.amount])
			CardEffect.Kind.DRAW_CARDS:
				draw_cards(effect.amount)
			CardEffect.Kind.GAIN_INSTABILITY:
				instability += effect.amount
				instability_gained_this_turn = true
				_log("超载 %d：不稳定升至 %d。" % [effect.amount, instability])
			CardEffect.Kind.REDUCE_INSTABILITY:
				var reduced: int = mini(instability, effect.amount)
				instability -= reduced
				var converted_block: int = reduced * effect.factor
				player_block += converted_block
				resolved_block += converted_block
				_log("不稳定减少 %d；转化为 %d 格挡。" % [reduced, converted_block])
			CardEffect.Kind.SEAL_CARD:
				card.sealed_turns = effect.amount
				sealed_zone.append(card)
				card_was_sealed = true
				_log("《%s》封存 %d 回合。" % [card.title, effect.amount])
			CardEffect.Kind.ECHO_ATTACK:
				if last_card_type == CardData.CardType.ATTACK:
					var echoed_damage: int = floori(float(last_damage_snapshot) * float(effect.amount) / 100.0)
					_log("回响上一张攻式已结算伤害的 %d%%：%d。" % [effect.amount, echoed_damage])
					resolved_damage += _deal_damage_to_enemy(echoed_damage, card.card_type, card.title)
				else:
					_log("回响失败：紧邻上一张牌不是攻式。")
			CardEffect.Kind.ECHO_BLOCK:
				if last_card_type == CardData.CardType.DEFENSE:
					var echoed_block: int = floori(float(last_block_snapshot) * float(effect.amount) / 100.0)
					player_block += echoed_block
					resolved_block += echoed_block
					_log("回响上一张守式已结算格挡的 %d%%：%d。" % [effect.amount, echoed_block])
				else:
					_log("回响失败：紧邻上一张牌不是守式。")
			CardEffect.Kind.DISCARD_DRAW_TOP:
				# 首版没有选择器：固定将可查看范围中的牌堆顶第1张弃置，其余维持原顺序。
				if not draw_pile.is_empty():
					var discarded_top: CardData = draw_pile.pop_back()
					discard_pile.append(discarded_top)
					_log("索引重排（首版确定性简化）：将牌堆顶《%s》置入弃牌堆。" % discarded_top.title)
			CardEffect.Kind.PREVENT_FRACTURE:
				prevent_next_fracture_damage = true
				_log("本回合下一次裂解伤害将变为 0。")
			CardEffect.Kind.DISSOLUTION_ATTACK:
				var dissolution_damage: int = effect.amount + instability * effect.factor
				resolved_damage += _deal_damage_to_enemy(dissolution_damage, card.card_type, card.title)
				instability = 0
				_log("崩解协议将不稳定清零。")
			CardEffect.Kind.PREWRITE_COPY:
				_resolve_prewritten_ending()
			CardEffect.Kind.UNSEAL_OLDEST:
				_unseal_oldest_card()
			CardEffect.Kind.COPY_PREVIOUS:
				_copy_previous_card_to_hand()
		if battle_over:
			break

	if not card_was_sealed:
		if card.exhausts:
			exhausted_zone.append(card)
			_log("《%s》进入消逝区。" % card.title)
		else:
			discard_pile.append(card)

	cards_played_this_turn += 1
	if card.card_type == CardData.CardType.ATTACK:
		attack_played_this_turn = true
	last_card_type = card.card_type
	last_card_id = card.id
	last_card_base_cost = card.base_cost
	last_card_exhausts = card.exhausts
	last_card_temporary = card.temporary
	last_damage_snapshot = resolved_damage
	last_block_snapshot = resolved_block
	if not battle_over:
		_check_fracture()
	return true


func end_player_turn() -> void:
	if battle_over:
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


func draw_cards(amount: int) -> void:
	for draw_index: int in range(amount):
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
		if card.id == &"redaction":
			missing_name[CardData.CardType.LAW] = int(missing_name.get(CardData.CardType.LAW, 0)) + 1
			exhausted_zone.append(card)
			_log("抽到《删节》：获得 1 层律式缺名；《删节》进入消逝区。")
			continue
		hand.append(card)
		_log("抽到《%s》。" % card.title)


func get_card_cost(card: CardData) -> int:
	var base: int = card.cost_override_this_turn if card.cost_override_this_turn >= 0 else card.base_cost
	return base + int(missing_name.get(card.card_type, 0))


func get_enemy_intent_text() -> String:
	match tutorial_stage:
		1:
			return "练习挥击：造成 5 点伤害"
		2:
			match enemy_intent_index:
				0:
					return "试探：造成 5 点伤害"
				1:
					return "架盾：获得 6 点格挡"
				2:
					return "蓄力：准备下一次重击"
				3:
					return "校准重击：造成 11 点伤害"
		3:
			return "裂隙脉冲：造成 %d 点伤害" % (6 if enemy_intent_index == 0 else 7)
		4:
			if enemy_intent_index == 0:
				return "轻敲：造成 5 点伤害"
			return "可预测重击：造成 14 点伤害"
		5:
			if enemy_intent_index == 0:
				return "回声冲击：造成 7 点伤害"
			return "回声屏障：获得 5 点格挡"
		6:
			match enemy_intent_index:
				0:
					return "啃噬：造成 6 点伤害"
				1:
					if enemy_recorded_type >= 0:
						return "偷字：施加 1 层%s缺名" % _type_name_from_int(enemy_recorded_type)
					return "偷字：未记录类别，获得 5 格挡"
				2:
					return "吐墨：造成 4×2 点伤害，清除记录"
	return "未知意图"


func get_enemy_record_text() -> String:
	if not is_mechanic_unlocked(&"missing_name"):
		return "偷字记录：尚未开放"
	if enemy_recorded_type < 0:
		return "吞字记录：空白"
	return "吞字记录：%s" % _type_name_from_int(enemy_recorded_type)


func get_missing_name_text() -> String:
	var parts: Array[String] = []
	for card_type: int in [CardData.CardType.ATTACK, CardData.CardType.DEFENSE, CardData.CardType.LAW]:
		var stacks: int = int(missing_name.get(card_type, 0))
		if stacks > 0:
			parts.append("%s缺名×%d" % [_type_name_from_int(card_type), stacks])
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


func _start_player_turn() -> void:
	player_block = 0
	energy = BASE_ENERGY
	instability_gained_this_turn = false
	cards_played_this_turn = 0
	attack_played_this_turn = false
	card_unsealed_this_turn = false
	prevent_next_fracture_damage = false
	last_card_type = -1
	last_card_id = &""
	last_card_base_cost = -1
	last_card_exhausts = false
	last_card_temporary = false
	last_damage_snapshot = 0
	last_block_snapshot = 0
	_clear_temporary_cost_overrides()
	_log("—— 第 %d 回合：格挡清零，稳定度恢复至 %d ——" % [turn_number, energy])
	_resolve_sealed_cards()
	if battle_over:
		return
	var cards_needed: int = maxi(0, BASE_HAND_SIZE - hand.size())
	draw_cards(cards_needed)


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


func _unseal_oldest_card() -> void:
	# 首版没有封存区选择器：固定选择最早进入封存区的牌。
	if sealed_zone.is_empty():
		_log("开封令未找到封存牌。")
		return
	sealed_zone[0].sealed_turns = 0
	_log("开封令（首版确定性简化）：选择最早封存的《%s》。" % sealed_zone[0].title)
	_unseal_card_at(0)


func _unseal_card_at(index: int) -> void:
	var card: CardData = sealed_zone[index]
	sealed_zone.remove_at(index)
	card_unsealed_this_turn = true
	_log("《%s》解封。" % card.title)
	match card.id:
		&"delayed_guard":
			player_block += 12
			_log("解封效果：获得 12 格挡。")
		&"countdown_scar":
			_deal_damage_to_enemy(18, CardData.CardType.ATTACK, card.title)
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
			effects.append(CardEffect.new(CardEffect.Kind.DISCARD_DRAW_TOP, 1))
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
			effects.append(CardEffect.new(CardEffect.Kind.PREWRITE_COPY, 1))
		&"unseal_order":
			effects.append(CardEffect.new(CardEffect.Kind.UNSEAL_OLDEST, 1))
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


func _deal_damage_to_enemy(amount: int, source_type: int, source_name: String) -> int:
	if amount <= 0 or battle_over:
		return 0
	if is_mechanic_unlocked(&"missing_name") and enemy_recorded_type < 0:
		enemy_recorded_type = source_type
		_log("%s吞下%s符号。" % [enemy_name, _type_name_from_int(source_type)])
	var blocked: int = mini(enemy_block, amount)
	enemy_block -= blocked
	var hp_damage: int = amount - blocked
	enemy_hp = maxi(0, enemy_hp - hp_damage)
	_log("《%s》造成 %d 伤害（格挡抵消 %d），%s生命 %d/%d。" % [source_name, hp_damage, blocked, enemy_name, enemy_hp, enemy_max_hp])
	if enemy_hp <= 0:
		battle_over = true
		victory = true
		_log("战斗胜利：穿过路径节点 %d/%d。" % [tutorial_stage, TUTORIAL_STAGE_MAX])
	return hp_damage


func _deal_damage_to_player(amount: int, source_name: String) -> void:
	var blocked: int = mini(player_block, amount)
	player_block -= blocked
	var hp_damage: int = amount - blocked
	player_hp = maxi(0, player_hp - hp_damage)
	_log("%s使用%s：造成 %d 伤害（格挡抵消 %d），你的生命 %d/%d。" % [enemy_name, source_name, hp_damage, blocked, player_hp, PLAYER_MAX_HP])
	_check_player_defeat()


func _execute_enemy_intent() -> void:
	enemy_block = 0
	match tutorial_stage:
		1:
			_deal_damage_to_player(5, "练习挥击")
		2:
			match enemy_intent_index:
				0:
					_deal_damage_to_player(5, "试探")
				1:
					enemy_block = 6
					_log("%s架起护盾，获得 6 格挡。" % enemy_name)
				2:
					_log("%s完成蓄力，下一意图是校准重击。" % enemy_name)
				3:
					_deal_damage_to_player(11, "校准重击")
		3:
			_deal_damage_to_player(6 if enemy_intent_index == 0 else 7, "裂隙脉冲")
		4:
			if enemy_intent_index == 0:
				_deal_damage_to_player(5, "轻敲")
			else:
				_deal_damage_to_player(14, "可预测重击")
		5:
			if enemy_intent_index == 0:
				_deal_damage_to_player(7, "回声冲击")
			else:
				enemy_block = 5
				_log("%s展开回声屏障，获得 5 格挡。" % enemy_name)
		6:
			match enemy_intent_index:
				0:
					_deal_damage_to_player(6, "啃噬")
				1:
					if enemy_recorded_type >= 0:
						var stacks: int = int(missing_name.get(enemy_recorded_type, 0)) + 1
						missing_name[enemy_recorded_type] = stacks
						_log("偷字：你获得 1 层%s缺名；下一张该类别牌费用 +1。" % _type_name_from_int(enemy_recorded_type))
					else:
						enemy_block = 5
						_log("偷字未找到记录：%s获得 5 格挡。" % enemy_name)
				2:
					_deal_damage_to_player(4, "吐墨（1/2）")
					if not battle_over:
						_deal_damage_to_player(4, "吐墨（2/2）")
					enemy_recorded_type = -1
					_log("%s清除了吞字记录。" % enemy_name)
	enemy_intent_index = (enemy_intent_index + 1) % _enemy_intent_count()


func _check_fracture() -> void:
	if instability < INSTABILITY_THRESHOLD or battle_over:
		return
	instability -= INSTABILITY_THRESHOLD
	var damage: int = FRACTURE_DAMAGE
	if prevent_next_fracture_damage:
		damage = 0
		prevent_next_fracture_damage = false
	player_hp = maxi(0, player_hp - damage)
	_log("裂解触发：受到 %d 点不可格挡伤害，不稳定降至 %d，生命 %d/%d。" % [damage, instability, player_hp, PLAYER_MAX_HP])
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
	_log("%s缺名被消耗，剩余 %d 层。" % [_type_name_from_int(card_type), stacks])


func _configure_tutorial_stage() -> void:
	match tutorial_stage:
		1:
			tutorial_stage_title = "第七码头·空白室"
			tutorial_hint = "墙上的旧告示只剩两行：出手，或护住自己。"
			enemy_name = "无名训练体"
			enemy_max_hp = 18
		2:
			tutorial_stage_title = "无字街口"
			tutorial_hint = "守卫抬起武器之前，胸前石片会先显出下一步动作。"
			enemy_name = "校准守卫"
			enemy_max_hp = 24
		3:
			tutorial_stage_title = "裂隙测量井"
			tutorial_hint = "井壁渗出的蓝光让规则变得更锋利，也更不稳定。"
			enemy_name = "裂隙测量体"
			enemy_max_hp = 28
		4:
			tutorial_stage_title = "迟钟长廊"
			tutorial_hint = "这里的动作总在数拍之后才抵达。远处的重锤节奏固定。"
			enemy_name = "刻时重锤"
			enemy_max_hp = 34
		5:
			tutorial_stage_title = "回声阅览室"
			tutorial_hint = "第二个声音会复述第一个动作，却从不复述它的原因。"
			enemy_name = "回声鉴别器"
			enemy_max_hp = 36
		6:
			tutorial_stage_title = "吞字巢穴"
			tutorial_hint = "虫腹里滚动着你刚使用的文字。它似乎在等待同类词句。"
			enemy_name = "拾字虫"
			enemy_max_hp = 40


func _enemy_intent_count() -> int:
	match tutorial_stage:
		1:
			return 1
		2:
			return 4
		3, 4, 5:
			return 2
		6:
			return 3
	return 1


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


func _resolve_prewritten_ending() -> void:
	# 首版没有手牌选择器：固定选择手牌中从左到右第一张非消逝牌。
	for original: CardData in hand:
		if original.exhausts:
			continue
		original.cost_override_this_turn = 0
		var copy: CardData = _make_card_from_catalog(original.id)
		copy.temporary = true
		copy.sealed_turns = 1
		sealed_zone.append(copy)
		_log("预写结局（首版确定性简化）：复制《%s》并封存 1；原牌本回合费用变为 0。" % original.title)
		return
	_log("预写结局未找到可复制的非消逝牌。")


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
	for pile in [draw_pile, hand, discard_pile, sealed_zone]:
		for card: CardData in pile:
			card.cost_override_this_turn = -1


func _shuffle_cards(cards: Array[CardData]) -> void:
	for index: int in range(cards.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var held: CardData = cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = held


func _type_name_from_int(card_type: int) -> String:
	match card_type:
		CardData.CardType.ATTACK:
			return "攻式"
		CardData.CardType.DEFENSE:
			return "守式"
		CardData.CardType.LAW:
			return "律式"
		CardData.CardType.STATUS:
			return "状态"
	return "未知类别"


func _log(message: String) -> void:
	log_entries.append(message)
