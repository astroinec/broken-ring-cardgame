extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_boss_opening_and_intent_cycle()
	_test_cost_tamper_determinism_and_recovery()
	_test_phase_transition_after_full_card_resolution()
	_test_type_deletion_and_unseal_recovery()
	_test_keyword_deletion_and_fracture_recovery()
	_test_missing_name_strength_and_echo()
	_test_terminal_choices_and_target_lock()
	_test_run_outcomes_and_deck_isolation()
	_test_evidence_changes_boss_context_and_settlement()
	if failures == 0:
		print("PASS: all M2 Boss protocol checks")
		quit(0)
	else:
		push_error("FAIL: %d M2 Boss protocol checks failed" % failures)
		quit(1)


func _test_boss_opening_and_intent_cycle() -> void:
	var model: CombatModel = _new_boss(91001)
	_expect(model.enemy_id == &"name_eraser", "Boss uses the catalog definition")
	_expect(model.enemy_hp == 168 and model.enemy_max_hp == 168, "Boss starts at 168 hp")
	_expect(model.boss_phase == 1 and model.get_boss_phase_name() == "校对", "Boss starts in proofreading phase")
	var expected: Array[String] = ["篡改费用", "红笔划除", "边注", "校对完成"]
	for intent_name: String in expected:
		_expect(model.get_enemy_intent_text().contains(intent_name), "phase one exposes intent %s" % intent_name)
		model.end_player_turn()
	_expect(model.get_enemy_intent_text().contains("篡改费用"), "phase one loops over exactly four intents")
	_expect(model.get_boss_status_text().contains("REC-10 / 可覆写载体"), "Boss status exposes the REC-10 archive")


func _test_cost_tamper_determinism_and_recovery() -> void:
	var first: CombatModel = _new_boss(91002)
	var second: CombatModel = _new_boss(91002)
	first.end_player_turn()
	second.end_player_turn()
	_expect(first.boss_cost_edits.size() == 2, "cost tamper edits two instances")
	_expect(_sorted_edit_ids(first.boss_cost_edits) == _sorted_edit_ids(second.boss_cost_edits), "cost tamper reproduces under a fixed seed")
	for raw_id: Variant in first.boss_cost_edits.keys():
		var card: CardData = first._card_for_instance(int(raw_id))
		_expect(card != null and first.get_card_cost(card) == first.get_card_original_cost(card) + 1, "tampered cost is original plus one")
		_expect(first.get_card_cost_display(card).contains("红笔+1"), "tampered cost display exposes original and edit")

	_prepare_hand(first, [&"calibration_strike", &"temporary_guard", &"boundary_read"])
	_expect(first.play_card(0), "attack advances the recovery sequence")
	_expect(first.play_card(0), "defense advances the recovery sequence")
	first.enemy_block = 10
	_expect(first.play_card(0), "law completes the three-type recovery sequence")
	_expect(first.boss_cost_edits.size() == 1, "three different formal types restore the earliest cost edit")
	_expect(first.enemy_block == 4, "cost recovery removes at most six Boss block")
	_expect(first.boss_recovery_count == 1, "actual cost recovery increments recovery count")


func _test_phase_transition_after_full_card_resolution() -> void:
	var model: CombatModel = _new_boss(91003)
	model._edit_boss_card_costs(2)
	model.enemy_block = 0
	model.enemy_hp = 105
	_prepare_hand(model, [&"rift_slash"])
	_expect(model.play_card(0), "threshold-crossing card resolves")
	_expect(model.enemy_hp == 94, "threshold-crossing damage is applied")
	_expect(model.instability == 2, "the card's post-damage overload resolves before transition")
	_expect(model.boss_phase == 2 and not model.boss_transition_pending, "Boss transitions after the complete effect queue")
	_expect(model.enemy_block == 0 and model.boss_cost_edits.is_empty(), "transition clears block and all cost edits")
	_expect(model.enemy_intent_index == 0 and model.get_enemy_intent_text().contains("删除类别"), "phase two starts from its first intent")
	_expect(_logs_contain(model, "我删掉的不是你的名字"), "transition records the designed Boss line")


func _test_type_deletion_and_unseal_recovery() -> void:
	var model: CombatModel = _new_boss(91004)
	model.boss_phase = 2
	_prepare_hand(model, [])
	var target: CardData = _extract_card(model, &"calibration_strike")
	model.draw_pile.append(target)
	model.boss_delete_next_draw_type = true
	model.draw_cards(1, false)
	_expect(model.boss_deleted_types.has(target.instance_id), "marked draw loses its category on entering hand")
	_expect(model.get_card_effective_type(target) == -1, "deleted category has no effective type")
	_expect(model.get_card_type_display(target).contains("原攻式"), "type display preserves the original category")
	model.missing_name[CardData.CardType.ATTACK] = 1
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "a category-deleted card remains playable")
	_expect(model.enemy_hp == hp_before - 6, "category deletion preserves base damage")
	_expect(int(model.missing_name[CardData.CardType.ATTACK]) == 1, "category-deleted card does not consume category missing-name stacks")
	_expect(model.last_card_type == -1 and model.reverse_record_pending == -1, "category-deleted card does not enter category records")

	var deleted_again: CardData = _extract_card(model, &"temporary_guard")
	model._delete_boss_card_type(deleted_again)
	var sealed: CardData = _extract_card(model, &"delayed_guard")
	sealed.sealed_turns = 0
	model.sealed_zone.append(sealed)
	var recoveries_before: int = model.boss_recovery_count
	model._unseal_card_at(model.sealed_zone.size() - 1)
	_expect(not model.boss_deleted_types.has(target.instance_id) and model.boss_deleted_types.has(deleted_again.instance_id), "unsealing restores the earliest deleted category")
	_expect(model.boss_recovery_count == recoveries_before + 1, "actual type recovery increments recovery count")


func _test_keyword_deletion_and_fracture_recovery() -> void:
	var model: CombatModel = _new_boss(91005)
	model.boss_phase = 2
	_prepare_hand(model, [&"rift_slash"])
	model._ended_hand_snapshot = model.hand.duplicate()
	model._delete_boss_hand_keywords()
	var card: CardData = model.hand[0]
	_expect(model.boss_deleted_keywords.has(card.instance_id), "keyword deletion selects a keyword card from the ended hand snapshot")
	_expect(not model.is_card_keyword_active(card, &"超载"), "deleted overload keyword is inactive")
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "keyword-deleted card remains playable")
	_expect(model.enemy_hp == hp_before - 11, "keyword deletion preserves base damage")
	_expect(model.instability == 0, "keyword deletion suppresses only the overload effect")
	model.instability = CombatModel.INSTABILITY_THRESHOLD
	var recoveries_before: int = model.boss_recovery_count
	model._check_fracture()
	_expect(model.boss_deleted_keywords.is_empty(), "fracture restores the earliest keyword deletion")
	_expect(model.boss_recovery_count == recoveries_before + 1, "actual keyword recovery increments recovery count")


func _test_missing_name_strength_and_echo() -> void:
	var model: CombatModel = _new_boss(91006)
	model.boss_phase = 2
	model.missing_name[CardData.CardType.ATTACK] = 1
	model.missing_name[CardData.CardType.LAW] = 2
	model._clear_missing_name_gain_boss_strength()
	_expect(model.missing_name.is_empty(), "return original clears every missing-name stack")
	_expect(model.boss_strength == 9 and model.rule_engine.enemy_strength == 9, "each cleared stack grants three Boss strength through RuleEngine")
	_prepare_hand(model, [&"calibration_strike", &"restate"])
	_expect(model.play_card(0), "echo setup attack resolves")
	_expect(model.play_card(0), "echo resolves in phase two")
	_expect(model.boss_strength == 8 and model.rule_engine.enemy_strength == 8, "successful echo lowers Boss strength by one")


func _test_terminal_choices_and_target_lock() -> void:
	var model: CombatModel = _new_boss(91007)
	model.boss_phase = 2
	model.enemy_hp = 6
	_prepare_hand(model, [&"calibration_strike"])
	_expect(model.play_card(0), "terminal hit resolves")
	_expect(model.enemy_hp == 1 and model.boss_phase == 3, "Boss hp locks at one and enters terminal phase")
	_expect(model.boss_terminal_choice_pending and not model.battle_over, "combat pauses for a terminal choice")
	_expect(TargetSelector.resolve_enemy(TargetSelector.Kind.SINGLE_ENEMY, model.build_target_context()) == TargetSelector.NO_TARGET, "terminal Boss is no longer targetable")
	_expect(not model.play_card(0), "cards cannot be played while terminal choice is pending")
	_expect(not model.can_choose_boss_original_text(), "read-original option is gated below two recoveries")
	_expect(not model.choose_boss_terminal(&"read_original"), "disabled terminal option cannot resolve")
	model.boss_recovery_count = 2
	_expect(model.can_choose_boss_original_text(), "read-original option unlocks at two recoveries")
	_expect(model.choose_boss_terminal(&"read_original"), "enabled read-original option resolves")
	_expect(model.battle_over and model.victory and model.boss_terminal_choice == &"read_original", "terminal choice produces a Boss victory result")

	var deliver: CombatModel = _new_boss(91008)
	deliver.boss_phase = 2
	deliver._enter_boss_terminal()
	_expect(deliver.choose_boss_terminal(&"deliver_seal"), "deliver-seal option is always available in terminal phase")


func _test_run_outcomes_and_deck_isolation() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(91009)
	var deck_before: Array[Dictionary] = run.get_deck_instances()
	var battle: CombatModel = CombatModel.new()
	var no_bonus: Array[StringName] = []
	battle.start_battle(91009, 6, no_bonus, &"name_eraser", run.get_relic_ids(), run.get_deck_instances())
	battle._edit_boss_card_costs(2)
	battle.boss_phase = 2
	var type_target: CardData = battle.draw_pile[0]
	battle._delete_boss_card_type(type_target)
	_expect(run.get_deck_instances() == deck_before, "combat-only Boss edits never mutate RunModel deck instances")

	var boss_id: StringName = run.map_graph.boss_node_id
	run.available_node_ids = [boss_id]
	_expect(run.enter_node(boss_id), "RunModel can enter the formal Boss node")
	_expect(not run.record_boss_outcome(&"read_original", 1), "RunModel independently rejects an under-qualified hidden ending")
	_expect(run.record_boss_outcome(&"read_original", 2), "RunModel records the qualified hidden ending")
	_expect(run.complete_current_node(), "recorded Boss outcome completes through the node protocol")
	_expect(run.run_completed and run.boss_ending_id == &"read_original", "RunModel stores the selected ending")
	_expect(run.evidence.has("第十份校准记录"), "read-original ending adds the designed evidence")
	_expect(run.boss_ending_text.contains("第十种答案") and run.boss_ending_text.contains("第七名回收者"), "hidden settlement contains Mira's correction")
	_expect(run.get_deck_instances() == deck_before, "Boss settlement leaves the permanent deck unchanged")


func _test_evidence_changes_boss_context_and_settlement() -> void:
	var context: Dictionary = {&"evidence_ids": [&"obscured_asset_log"]}
	var battle: CombatModel = CombatModel.new()
	var no_bonus: Array[StringName] = []
	var no_relics: Array[StringName] = []
	battle.start_battle(91010, 6, no_bonus, &"name_eraser", no_relics, [], 500, 500, context)
	battle._apply_boss_phase_transition()
	_expect(_logs_contain(battle, "你已经看过那层遮蔽"), "asset-log evidence changes the Boss phase-transition line through combat context")

	var run: RunModel = RunModel.new()
	run.start_run(91011)
	run.selected_event_id = &"seventh_dock"
	run.apply_event_choice(0)
	run.event_resolved = false
	run.selected_event_id = &"deleted_funeral"
	run.relics.append(&"blank_epitaph")
	run.apply_event_choice(2)
	var boss_id: StringName = run.map_graph.boss_node_id
	run.available_node_ids = [boss_id]
	_expect(run.enter_node(boss_id), "evidence settlement enters formal Boss node")
	_expect(run.record_boss_outcome(&"read_original", 2), "evidence settlement records read-original ending")
	_expect(run.boss_ending_text.contains("九个版本") and run.boss_ending_text.contains("制造接口"), "old evidence adds two traceable explanations to Boss settlement")
	_expect(run.evidence.has("第十份校准记录") and run.evidence_records.size() == 3, "Boss settlement keeps legacy evidence titles and structured records in sync")


func _new_boss(seed_value: int) -> CombatModel:
	var model: CombatModel = CombatModel.new()
	var no_bonus: Array[StringName] = []
	var no_relics: Array[StringName] = []
	model.start_battle(seed_value, 6, no_bonus, &"name_eraser", no_relics, [], 500, 500)
	return model


func _prepare_hand(model: CombatModel, card_ids: Array[StringName]) -> void:
	while not model.hand.is_empty():
		model.discard_pile.append(model.hand.pop_back())
	for card_id: StringName in card_ids:
		var card: CardData = _extract_card(model, card_id)
		if card != null:
			model.hand.append(card)
	model.energy = 20


func _extract_card(model: CombatModel, card_id: StringName) -> CardData:
	for pile: Array[CardData] in [model.draw_pile, model.discard_pile, model.hand]:
		for index: int in range(pile.size()):
			if pile[index].id == card_id:
				var card: CardData = pile[index]
				pile.remove_at(index)
				return card
	_expect(false, "Boss test deck contains %s" % card_id)
	return null


func _sorted_edit_ids(edits: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for raw_id: Variant in edits.keys():
		ids.append(int(raw_id))
	ids.sort()
	return ids


func _logs_contain(model: CombatModel, fragment: String) -> bool:
	for entry: String in model.log_entries:
		if entry.contains(fragment):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
