extends SceneTree


const NEW_CARD_IDS: Array[StringName] = [
	&"reverse_index", &"delete_redundancy", &"missing_name_arbitration",
	&"tenth_answer", &"echo_chamber", &"borrowed_name_execution",
]

var failures: int = 0
var next_instance_id: int = 10_000


func _init() -> void:
	_test_catalog_and_upgrades()
	_test_reverse_index_and_cancel()
	_test_delete_redundancy_and_cancel()
	_test_missing_name_arbitration()
	_test_tenth_answer()
	_test_echo_chamber()
	_test_borrowed_name_execution()
	_test_new_upgrades_trigger_red_pen()
	if failures == 0:
		print("PASS: all six M3 card and selector checks")
		quit(0)
	else:
		push_error("FAIL: %d M3 card checks failed" % failures)
		quit(1)


func _test_catalog_and_upgrades() -> void:
	for card_id: StringName in NEW_CARD_IDS:
		_expect(CardCatalog.has_card(card_id), "%s 有基础卡定义" % card_id)
		_expect(CardCatalog.REWARD_IDS.has(card_id), "%s 进入正式奖励池" % card_id)
		var base: CardData = _card(card_id)
		var upgrade_id: StringName = CardUpgradeCatalog.get_default_upgrade_id(card_id)
		var upgraded: CardData = _card(card_id, upgrade_id)
		_expect(upgrade_id != &"" and upgraded.upgrade_id == upgrade_id, "%s 有可用升级" % card_id)
		_expect(upgraded.title.ends_with("+") and upgraded.description != base.description, "%s 升级文本与基础版不同" % card_id)
	_expect(CardUpgradeCatalog.DEFINITIONS.size() == 25, "全部二十五张正式牌均有升级定义")


func _test_reverse_index_and_cancel() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"reverse_index"])
	_set_discard(base, [&"calibration_strike", &"redaction"])
	var hp_before: int = base.enemy_hp
	_expect(base.play_card(0) and base.has_pending_selection(), "反向索引进入弃牌选择")
	_expect(base.get_pending_candidate_indices() == [0], "反向索引排除状态牌")
	_expect(base.resolve_pending_selection(0), "反向索引确认弃牌")
	_expect(_hand_ids(base).has(&"calibration_strike") and base.discard_pile.size() == 1, "反向索引将弃牌移回手牌")
	_expect(base.get_card_cost(base.hand[_find_hand(base, &"calibration_strike")]) == 1, "基础反向索引不改变费用")
	_expect(base.enemy_hp == hp_before and _pile_has(base.exhausted_zone, &"reverse_index"), "反向索引只移动牌并自身消逝")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"reverse_index"], [&"reverse_index_plus"])
	_set_discard(upgraded, [&"calibration_strike"])
	upgraded.play_card(0)
	upgraded.resolve_pending_selection(0)
	_expect(upgraded.get_card_cost(upgraded.hand[0]) == 0, "升级反向索引令返回牌本回合费用减一")

	var cancelled: CombatModel = _model()
	_set_hand(cancelled, [&"reverse_index", &"temporary_guard"])
	_set_discard(cancelled, [&"calibration_strike"])
	cancelled.missing_name[CardData.CardType.LAW] = 1
	var before_hand: Array[StringName] = _hand_ids(cancelled)
	var before_discard: Array[StringName] = _pile_ids(cancelled.discard_pile)
	var before_energy: int = cancelled.energy
	var before_uses: Dictionary = cancelled.get_telemetry()[&"card_uses"]
	_expect(cancelled.play_card(0) and cancelled.cancel_pending_selection(), "反向索引选择可取消")
	_expect(cancelled.energy == before_energy and int(cancelled.missing_name.get(CardData.CardType.LAW, 0)) == 1, "取消返还全部稳定度与缺名")
	_expect(_hand_ids(cancelled) == before_hand and _pile_ids(cancelled.discard_pile) == before_discard, "取消恢复原手牌位置与弃牌堆")
	_expect(cancelled.exhausted_zone.is_empty() and cancelled.get_telemetry()[&"card_uses"] == before_uses, "取消不消逝、不计出牌且无遥测痕迹")

	var no_discard: CombatModel = _model()
	_set_hand(no_discard, [&"reverse_index"])
	_set_discard(no_discard, [&"redaction"])
	var no_discard_energy: int = no_discard.energy
	_expect(not no_discard.play_card(0), "弃牌堆没有非状态牌时反向索引不可打出")
	_expect(no_discard.energy == no_discard_energy and _find_hand(no_discard, &"reverse_index") >= 0, "无目标反向索引不付费也不离开手牌")


func _test_delete_redundancy_and_cancel() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"delete_redundancy", &"temporary_guard"])
	_set_draw(base, [&"calibration_strike", &"blank_space"])
	_expect(base.play_card(0) and base.has_pending_selection(), "删去冗句进入另一张手牌选择")
	_expect(base.resolve_pending_selection(0), "删去冗句确认目标")
	_expect(_pile_has(base.exhausted_zone, &"temporary_guard") and _pile_has(base.exhausted_zone, &"delete_redundancy"), "删去冗句令目标与自身消逝")
	_expect(base.hand.size() == 2 and base.draw_pile.is_empty(), "基础删去冗句抽两张牌")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"delete_redundancy", &"temporary_guard"], [&"delete_redundancy_plus", &""])
	_set_draw(upgraded, [&"calibration_strike", &"blank_space", &"rift_slash"])
	upgraded.play_card(0)
	upgraded.resolve_pending_selection(0)
	_expect(upgraded.hand.size() == 3 and upgraded.draw_pile.is_empty(), "升级删去冗句抽三张牌")

	var cancelled: CombatModel = _model()
	_set_hand(cancelled, [&"delete_redundancy", &"temporary_guard"])
	_set_draw(cancelled, [&"calibration_strike", &"blank_space"])
	var before_hand: Array[StringName] = _hand_ids(cancelled)
	var before_draw: Array[StringName] = _pile_ids(cancelled.draw_pile)
	var before_energy: int = cancelled.energy
	_expect(cancelled.play_card(0) and cancelled.cancel_pending_selection(), "删去冗句选择可取消")
	_expect(cancelled.energy == before_energy and _hand_ids(cancelled) == before_hand, "删去冗句取消完整恢复费用与手牌")
	_expect(_pile_ids(cancelled.draw_pile) == before_draw and cancelled.exhausted_zone.is_empty(), "删去冗句取消不抽牌也不消逝")

	var alone: CombatModel = _model()
	_set_hand(alone, [&"delete_redundancy"])
	_set_draw(alone, [&"calibration_strike", &"blank_space"])
	var alone_energy: int = alone.energy
	var alone_draw: Array[StringName] = _pile_ids(alone.draw_pile)
	_expect(not alone.play_card(0), "删去冗句是唯一手牌时不可打出")
	_expect(alone.energy == alone_energy and _find_hand(alone, &"delete_redundancy") >= 0, "无目标删去冗句不付费也不消逝")
	_expect(_pile_ids(alone.draw_pile) == alone_draw, "无目标删去冗句不会免费抽牌")


func _test_missing_name_arbitration() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"missing_name_arbitration"])
	_set_draw(base, [&"calibration_strike"])
	base.missing_name[CardData.CardType.ATTACK] = 2
	base.missing_name[CardData.CardType.LAW] = 1
	_expect(base.play_card(0), "缺名仲裁可打出")
	_expect(base.missing_name.is_empty(), "缺名仲裁清除全部缺名")
	_expect(base.player_block == 12 and base.hand.size() == 1, "基础缺名仲裁每层四格挡且有清除时抽一张")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"missing_name_arbitration"], [&"missing_name_arbitration_plus"])
	_set_draw(upgraded, [&"calibration_strike"])
	upgraded.missing_name[CardData.CardType.ATTACK] = 2
	upgraded.missing_name[CardData.CardType.LAW] = 1
	upgraded.play_card(0)
	_expect(upgraded.player_block == 15 and upgraded.missing_name.is_empty(), "升级缺名仲裁每层五格挡并清空")

	var none: CombatModel = _model()
	_set_hand(none, [&"missing_name_arbitration"])
	_set_draw(none, [&"calibration_strike"])
	none.play_card(0)
	_expect(none.player_block == 0 and none.hand.is_empty() and none.draw_pile.size() == 1, "没有缺名时仲裁不格挡也不抽牌")


func _test_tenth_answer() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"tenth_answer"])
	_set_sealed(base, [&"delayed_guard", &"countdown_scar"], [2, 3])
	var hp_before: int = base.enemy_hp
	base.play_card(0)
	_expect(base.enemy_hp == hp_before - 16, "基础第十种答案按两张封存牌造成十六伤害")
	_expect(_sealed_turns(base) == [1, 2], "第十种答案令全部封存倒计时减一")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"tenth_answer"], [&"tenth_answer_plus"])
	_set_sealed(upgraded, [&"delayed_guard", &"countdown_scar"], [2, 3])
	hp_before = upgraded.enemy_hp
	upgraded.play_card(0)
	_expect(upgraded.enemy_hp == hp_before - 20, "升级第十种答案每张封存牌追加六伤害")
	_expect(_sealed_turns(upgraded) == [1, 2], "升级版同样只推进一次倒计时")


func _test_echo_chamber() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"echo_chamber", &"calibration_strike", &"restate", &"calibration_strike", &"restate"])
	_set_draw(base, [&"temporary_guard"])
	base.energy = 20
	var hp_before: int = base.enemy_hp
	base.play_card(_find_hand(base, &"echo_chamber"))
	_expect(base.next_echo_bonus_percent == 50, "基础回声室准备百分之五十放大")
	base.play_card(_find_hand(base, &"calibration_strike"))
	base.play_card(_find_hand(base, &"restate"))
	_expect(base.enemy_hp == hp_before - 11 and base.next_echo_bonus_percent == 0, "回声室只放大下一次成功回响并随即消耗")
	base.play_card(_find_hand(base, &"calibration_strike"))
	base.play_card(_find_hand(base, &"restate"))
	_expect(base.enemy_hp == hp_before - 20, "同回合第二次回响恢复普通数值")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"echo_chamber", &"calibration_strike", &"restate"], [&"echo_chamber_plus", &"", &""])
	_set_draw(upgraded, [&"temporary_guard"])
	upgraded.energy = 20
	hp_before = upgraded.enemy_hp
	upgraded.play_card(0)
	upgraded.play_card(_find_hand(upgraded, &"calibration_strike"))
	upgraded.play_card(_find_hand(upgraded, &"restate"))
	_expect(upgraded.enemy_hp == hp_before - 12, "升级回声室以百分之七十五放大一次回响")

	var cleared: CombatModel = _model()
	_set_hand(cleared, [&"echo_chamber"])
	_set_draw(cleared, [&"temporary_guard"])
	cleared.play_card(0)
	_expect(cleared.next_echo_bonus_percent == 50, "回合结束前回声室增益存在")
	cleared.end_player_turn()
	_expect(cleared.next_echo_bonus_percent == 0, "未使用的回声室增益在新回合清除")


func _test_borrowed_name_execution() -> void:
	var base: CombatModel = _model()
	_set_hand(base, [&"borrowed_name_execution"])
	base.missing_name[CardData.CardType.DEFENSE] = 2
	base.missing_name[CardData.CardType.LAW] = 1
	var hp_before: int = base.enemy_hp
	base.play_card(0)
	_expect(base.enemy_hp == hp_before - 11, "基础借名执行按两种缺名造成十一伤害")
	_expect(int(base.missing_name.get(CardData.CardType.DEFENSE, 0)) == 1 and int(base.missing_name.get(CardData.CardType.LAW, 0)) == 0, "借名执行每种缺名各清除一层")

	var upgraded: CombatModel = _model()
	_set_hand(upgraded, [&"borrowed_name_execution"], [&"borrowed_name_execution_plus"])
	upgraded.missing_name[CardData.CardType.DEFENSE] = 2
	upgraded.missing_name[CardData.CardType.LAW] = 1
	hp_before = upgraded.enemy_hp
	upgraded.play_card(0)
	_expect(upgraded.enemy_hp == hp_before - 15, "升级借名执行每种缺名追加五伤害")
	_expect(int(upgraded.missing_name.get(CardData.CardType.DEFENSE, 0)) == 1, "升级借名执行仍只各清除一层")


func _test_new_upgrades_trigger_red_pen() -> void:
	var arbitration: CombatModel = _model_with_relic(&"calibrator_red_pen")
	_set_hand(arbitration, [&"missing_name_arbitration"], [&"missing_name_arbitration_plus"])
	arbitration.missing_name[CardData.CardType.ATTACK] = 1
	arbitration.play_card(0)
	_expect(arbitration.player_block == 8, "升级缺名仲裁触发红笔并在五格挡上追加三点")

	var tenth: CombatModel = _model_with_relic(&"calibrator_red_pen")
	_set_hand(tenth, [&"tenth_answer"], [&"tenth_answer_plus"])
	_set_sealed(tenth, [&"delayed_guard"], [2])
	var hp_before: int = tenth.enemy_hp
	tenth.play_card(0)
	_expect(tenth.enemy_hp == hp_before - 17, "升级第十种答案以未升级基线触发红笔")

	var borrowed: CombatModel = _model_with_relic(&"calibrator_red_pen")
	_set_hand(borrowed, [&"borrowed_name_execution"], [&"borrowed_name_execution_plus"])
	borrowed.missing_name[CardData.CardType.DEFENSE] = 1
	borrowed.missing_name[CardData.CardType.LAW] = 1
	hp_before = borrowed.enemy_hp
	borrowed.play_card(0)
	_expect(borrowed.enemy_hp == hp_before - 18, "升级借名执行以未升级基线触发红笔")


func _model() -> CombatModel:
	var model: CombatModel = CombatModel.new()
	model.start_battle(73103, 6, [], &"name_eraser")
	model.enemy_hp = 500
	model.enemy_max_hp = 500
	model.enemy_block = 0
	model.stone_shell = 0
	model.boss_phase = 0
	model.boss_transition_pending = false
	model.boss_terminal_choice_pending = false
	model.hand.clear()
	model.draw_pile.clear()
	model.discard_pile.clear()
	model.sealed_zone.clear()
	model.exhausted_zone.clear()
	model.energy = 20
	return model


func _model_with_relic(relic_id: StringName) -> CombatModel:
	var model: CombatModel = _model()
	var relics: Array[StringName] = [relic_id]
	model.rule_engine.reset_for_battle(relics)
	return model


func _card(card_id: StringName, upgrade_id: StringName = &"") -> CardData:
	next_instance_id += 1
	return CardCatalog.create_card(card_id, next_instance_id, upgrade_id)


func _set_hand(model: CombatModel, ids: Array[StringName], upgrades: Array[StringName] = []) -> void:
	model.hand.clear()
	for index: int in range(ids.size()):
		var upgrade_id: StringName = upgrades[index] if index < upgrades.size() else &""
		model.hand.append(_card(ids[index], upgrade_id))


func _set_draw(model: CombatModel, ids: Array[StringName]) -> void:
	model.draw_pile.clear()
	for card_id: StringName in ids:
		model.draw_pile.append(_card(card_id))


func _set_discard(model: CombatModel, ids: Array[StringName]) -> void:
	model.discard_pile.clear()
	for card_id: StringName in ids:
		model.discard_pile.append(_card(card_id))


func _set_sealed(model: CombatModel, ids: Array[StringName], turns: Array[int]) -> void:
	model.sealed_zone.clear()
	for index: int in range(ids.size()):
		var card: CardData = _card(ids[index])
		card.sealed_turns = turns[index]
		model.sealed_zone.append(card)


func _find_hand(model: CombatModel, card_id: StringName) -> int:
	for index: int in range(model.hand.size()):
		if model.hand[index].id == card_id:
			return index
	return -1


func _hand_ids(model: CombatModel) -> Array[StringName]:
	return _pile_ids(model.hand)


func _pile_ids(pile: Array[CardData]) -> Array[StringName]:
	var result: Array[StringName] = []
	for card: CardData in pile:
		result.append(card.id)
	return result


func _pile_has(pile: Array[CardData], card_id: StringName) -> bool:
	return _pile_ids(pile).has(card_id)


func _sealed_turns(model: CombatModel) -> Array[int]:
	var result: Array[int] = []
	for card: CardData in model.sealed_zone:
		result.append(card.sealed_turns)
	return result


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
