extends SceneTree

const CombatModelScript: Script = preload("res://scripts/core/combat_model.gd")

var failures: int = 0


func _init() -> void:
	_test_deterministic_opening()
	_test_basic_card_play()
	_test_fracture()
	_test_echo_snapshot()
	_test_sealed_card_returns()
	_test_tutorial_stage_decks_and_unlocks()
	_test_tutorial_stage_progression_rule()
	_test_reward_card_rules()
	_test_enemy_catalog_integrity()
	_test_intent_data_validity()
	_test_path_enemies_unchanged()
	_test_target_selector()
	_test_selector_cards_full_flow()
	_test_selector_cards_cancel_path()
	_test_rule_engine_priority()
	_test_relics_in_pipeline()
	_test_hollow_name_guard()
	_test_reverse_reader()
	_test_binding_instrument()
	_test_old_wound_end_turn_damage()
	_test_no_temporary_simplification_logs()
	if failures == 0:
		print("PASS: all combat model checks")
		quit(0)
	else:
		push_error("FAIL: %d combat model checks failed" % failures)
		quit(1)


func _test_deterministic_opening() -> void:
	var first = CombatModelScript.new()
	var second = CombatModelScript.new()
	first.start_battle(73103)
	second.start_battle(73103)
	_expect(first.enemy_hp == second.enemy_hp, "fixed seed enemy hp")
	_expect(_hand_ids(first) == _hand_ids(second), "fixed seed opening hand")


func _test_basic_card_play() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103)
	var attack_index: int = _find_hand_card(model, &"calibration_strike")
	if attack_index < 0:
		_expect(false, "opening hand contains calibration strike")
		return
	var hp_before: int = model.enemy_hp
	var energy_before: int = model.energy
	_expect(model.play_card(attack_index), "calibration strike can be played")
	_expect(model.enemy_hp == hp_before - 6, "calibration strike deals 6")
	_expect(model.energy == energy_before - 1, "calibration strike spends 1 energy")


func _test_fracture() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103)
	model.instability = 9
	model._check_fracture()
	_expect(model.player_hp == CombatModelScript.PLAYER_MAX_HP, "no fracture below threshold")
	model.instability = 10
	model._check_fracture()
	_expect(model.player_hp == CombatModelScript.PLAYER_MAX_HP - CombatModelScript.FRACTURE_DAMAGE, "fracture deals fixed damage")
	_expect(model.instability == 0, "fracture reduces instability by ten")


func _test_echo_snapshot() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 5)
	_prepare_hand(model, [&"calibration_strike", &"restate"])
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "echo setup attack can be played")
	_expect(model.play_card(0), "restate can be played after attack")
	_expect(model.enemy_hp == hp_before - 9, "restate echoes sixty percent of resolved attack damage")


func _test_sealed_card_returns() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 4)
	_prepare_hand(model, [&"delayed_guard"])
	_expect(model.play_card(0), "delayed guard can be sealed")
	_expect(model.sealed_zone.size() == 1, "delayed guard enters sealed zone")
	model.end_player_turn()
	_expect(model.player_block == 12, "delayed guard grants block after unsealing")
	_expect(_find_hand_card(model, &"delayed_guard") >= 0, "unsealed card returns to hand")


func _test_tutorial_stage_decks_and_unlocks() -> void:
	var mechanics: Array[StringName] = [&"intent", &"overload", &"seal", &"echo", &"missing_name"]
	var unlock_stages: Array[int] = [2, 3, 4, 5, 6]
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		var model = CombatModelScript.new()
		model.start_battle(73103, stage)
		var ids: Array[StringName] = _all_card_ids(model)
		_expect(model.tutorial_stage == stage, "tutorial stage %d is selected" % stage)
		_expect(not model.tutorial_stage_title.is_empty(), "tutorial stage %d has title" % stage)
		_expect(not model.tutorial_hint.is_empty(), "tutorial stage %d has hint" % stage)
		_expect(not model.enemy_name.is_empty(), "tutorial stage %d has enemy name" % stage)
		_expect(not model.get_enemy_intent_text().is_empty(), "tutorial stage %d has intent text" % stage)
		for mechanic_index: int in range(mechanics.size()):
			var expected_unlocked: bool = stage >= unlock_stages[mechanic_index]
			_expect(
				model.is_mechanic_unlocked(mechanics[mechanic_index]) == expected_unlocked,
				"tutorial stage %d unlock state for %s" % [stage, mechanics[mechanic_index]]
			)
		match stage:
			1, 2:
				_expect(_contains_only_basic_cards(ids), "tutorial stage %d uses only basic attack and defense" % stage)
			3:
				_expect(ids.has(&"boundary_read"), "stage 3 deck contains boundary read")
				_expect(ids.has(&"rift_slash"), "stage 3 deck contains rift slash")
				_expect(ids.has(&"forced_stability"), "stage 3 deck contains forced stability")
				_expect(not ids.has(&"delayed_guard") and not ids.has(&"restate"), "stage 3 excludes later keywords")
			4:
				_expect(ids.has(&"delayed_guard") and ids.has(&"countdown_scar"), "stage 4 deck contains both seal cards")
				_expect(not ids.has(&"restate"), "stage 4 excludes echo")
			5:
				_expect(ids.has(&"restate"), "stage 5 deck contains restate")
				_expect(ids.has(&"delayed_guard"), "stage 5 retains seal")
			6:
				_expect(ids.has(&"boundary_read") and ids.has(&"delayed_guard") and ids.has(&"restate"), "stage 6 combines prior keyword cards")
				_expect(ids.size() == 15, "stage 6 uses comprehensive fifteen-card deck")


func _test_tutorial_stage_progression_rule() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 2)
	_expect(not model.can_advance_tutorial_stage(), "stage cannot advance before victory")
	_expect(model.get_next_tutorial_stage() == 2, "next stage remains current before victory")
	model.battle_over = true
	model.victory = true
	_expect(model.can_advance_tutorial_stage(), "victory permits tutorial advancement")
	_expect(model.get_next_tutorial_stage() == 3, "victory advances exactly one tutorial stage")
	model.start_battle(73103, 6)
	model.battle_over = true
	model.victory = true
	_expect(not model.can_advance_tutorial_stage(), "final tutorial stage cannot advance past six")
	_expect(model.get_next_tutorial_stage() == 6, "final tutorial stage remains six")


func _test_reward_card_rules() -> void:
	var tempo = CombatModelScript.new()
	var tempo_bonus: Array[StringName] = [&"broken_sentence", &"blank_space"]
	tempo.start_battle(80001, 6, tempo_bonus)
	_prepare_hand(tempo, [&"broken_sentence", &"blank_space"])
	var hp_before: int = tempo.enemy_hp
	var draw_before: int = tempo.draw_pile.size()
	_expect(tempo.play_card(0), "broken sentence can be played")
	_expect(tempo.enemy_hp == hp_before - 7, "broken sentence deals seven damage")
	_expect(tempo.draw_pile.size() == draw_before - 1, "broken sentence draws when played first")
	var block_before: int = tempo.player_block
	_expect(tempo.play_card(0), "blank space can be played")
	_expect(tempo.player_block == block_before + 7, "blank space loses bonus after an attack")

	var permission = CombatModelScript.new()
	var permission_bonus: Array[StringName] = [&"critical_permission"]
	permission.start_battle(80002, 6, permission_bonus)
	_prepare_hand(permission, [&"critical_permission"])
	permission.instability = 10
	var player_hp_before: int = permission.player_hp
	_expect(permission.play_card(0), "critical permission can be played")
	_expect(permission.player_hp == player_hp_before, "critical permission prevents fracture damage")
	_expect(permission.instability == 0, "prevented fracture still reduces instability")

	var dissolution = CombatModelScript.new()
	var dissolution_bonus: Array[StringName] = [&"dissolution_protocol"]
	dissolution.start_battle(80003, 6, dissolution_bonus)
	_prepare_hand(dissolution, [&"dissolution_protocol"])
	dissolution.instability = 4
	var dissolution_hp: int = dissolution.enemy_hp
	_expect(dissolution.play_card(0), "dissolution protocol can be played")
	_expect(dissolution.enemy_hp == dissolution_hp - 22, "dissolution protocol scales with instability")
	_expect(dissolution.instability == 0, "dissolution protocol clears instability")

	var defense_echo = CombatModelScript.new()
	var defense_bonus: Array[StringName] = [&"copied_guard"]
	defense_echo.start_battle(80004, 6, defense_bonus)
	_prepare_hand(defense_echo, [&"temporary_guard", &"copied_guard"])
	_expect(defense_echo.play_card(0), "temporary guard sets defense echo snapshot")
	_expect(defense_echo.play_card(0), "copied guard can be played")
	_expect(defense_echo.player_block == 11, "copied guard adds four plus half prior block")

	var homophone = CombatModelScript.new()
	var homophone_bonus: Array[StringName] = [&"homophone"]
	homophone.start_battle(80005, 6, homophone_bonus)
	_prepare_hand(homophone, [&"calibration_strike", &"homophone"])
	_expect(homophone.play_card(0), "attack sets homophone source")
	_expect(homophone.play_card(0), "homophone can be played")
	var copied_index: int = _find_hand_card(homophone, &"calibration_strike")
	_expect(copied_index >= 0, "homophone creates previous card copy")
	if copied_index >= 0:
		_expect(homophone.hand[copied_index].temporary, "homophone copy is temporary")
		_expect(homophone.get_card_cost(homophone.hand[copied_index]) == 0, "homophone copy costs zero this turn")

	var prewrite = CombatModelScript.new()
	var prewrite_bonus: Array[StringName] = [&"prewritten_ending"]
	prewrite.start_battle(80006, 6, prewrite_bonus)
	_prepare_hand(prewrite, [&"prewritten_ending", &"calibration_strike"])
	_expect(prewrite.play_card(0), "prewritten ending can be played")
	_expect(prewrite.has_pending_selection(), "prewritten ending now raises a selection request")
	_expect(prewrite.resolve_pending_selection(0), "prewritten ending target can be chosen")
	_expect(prewrite.sealed_zone.size() == 1, "prewritten ending seals a temporary copy")
	_expect(prewrite.get_card_cost(prewrite.hand[0]) == 0, "prewritten ending makes source card free this turn")


# ---------------------------------------------------------------- 敌人目录完整性

func _test_enemy_catalog_integrity() -> void:
	var ids: Array[StringName] = EnemyCatalog.get_all_ids()
	_expect(ids.size() >= 9, "enemy catalog holds every path and formal enemy")
	for enemy_id: StringName in ids:
		var definition: EnemyDefinition = EnemyCatalog.create(enemy_id)
		_expect(definition.is_valid(), "enemy %s passes data validation" % enemy_id)
		_expect(not definition.display_name.is_empty(), "enemy %s has Chinese name" % enemy_id)
		_expect(definition.hp_min > 0, "enemy %s has positive hp floor" % enemy_id)
		_expect(definition.hp_max >= definition.hp_min, "enemy %s hp range is ordered" % enemy_id)
		_expect(definition.intent_count() >= 1, "enemy %s has at least one intent" % enemy_id)
		_expect(not definition.tier.is_empty(), "enemy %s declares a tier" % enemy_id)
	_expect(EnemyCatalog.PATH_ENEMY_IDS.size() == CombatModelScript.TUTORIAL_STAGE_MAX, "path enemy list covers six nodes")
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		_expect(EnemyCatalog.has_enemy(EnemyCatalog.enemy_id_for_path_stage(stage)), "path stage %d maps to a catalog enemy" % stage)
	for arena_id: StringName in EnemyCatalog.TEST_ARENA_ENEMY_IDS:
		_expect(EnemyCatalog.has_enemy(arena_id), "test arena option %s exists" % arena_id)
	for formal_id: StringName in [&"hollow_name_guard", &"reverse_reader", &"binding_instrument"]:
		_expect(EnemyCatalog.TEST_ARENA_ENEMY_IDS.has(formal_id), "formal enemy %s is selectable in test arena" % formal_id)
		_expect(not EnemyCatalog.PATH_ENEMY_IDS.has(formal_id), "formal enemy %s stays out of the main path" % formal_id)
	_expect(EnemyCatalog.has_enemy(&"pressure_archivist"), "balance pressure enemy exists in the catalog")
	_expect(not EnemyCatalog.PATH_ENEMY_IDS.has(&"pressure_archivist"), "balance pressure enemy stays out of the main path")
	_expect(not EnemyCatalog.TEST_ARENA_ENEMY_IDS.has(&"pressure_archivist"), "balance pressure enemy stays out of the test arena menu")
	_expect(EnemyCatalog.create(&"pressure_archivist").tier == "测试", "balance pressure enemy is marked test-only")


func _test_intent_data_validity() -> void:
	var context: IntentContext = IntentContext.new()
	for enemy_id: StringName in EnemyCatalog.get_all_ids():
		var definition: EnemyDefinition = EnemyCatalog.create(enemy_id)
		var seen_ids: Array[StringName] = []
		for intent: EnemyIntent in definition.intents:
			_expect(intent.is_valid(), "%s intent %s is valid" % [enemy_id, intent.id])
			_expect(not seen_ids.has(intent.id), "%s intent id %s is unique" % [enemy_id, intent.id])
			seen_ids.append(intent.id)
			_expect(not intent.display_name.is_empty(), "%s intent %s has Chinese name" % [enemy_id, intent.id])
			_expect(not intent.describe(context).is_empty(), "%s intent %s renders Chinese text" % [enemy_id, intent.id])
			_expect(not intent.describe(context).contains("{"), "%s intent %s leaves no placeholder" % [enemy_id, intent.id])
			for operation: EnemyOperation in intent.operations:
				_expect(operation.is_valid(), "%s intent %s operation is valid" % [enemy_id, intent.id])
				if operation.kind == EnemyOperation.Kind.ATTACK:
					_expect(not operation.action_name.is_empty(), "%s attack operation names its action" % enemy_id)
				if operation.kind == EnemyOperation.Kind.ADD_CARD_TO_DRAW_PILE or operation.kind == EnemyOperation.Kind.ADD_CARD_TO_DISCARD_PILE:
					_expect(CardCatalog.has_card(operation.card_id), "%s adds an existing card %s" % [enemy_id, operation.card_id])
		# 顺序模式下每个索引都必须能取到意图。
		if definition.intent_mode == EnemyDefinition.IntentMode.SEQUENCE:
			for index: int in range(definition.intent_count()):
				_expect(definition.select_intent(index, -1) != null, "%s sequence index %d resolves" % [enemy_id, index])


## 主线六节点的敌人、生命与意图文字必须与v0.4 一致。
func _test_path_enemies_unchanged() -> void:
	var expected_names: Array[String] = [
		"无名训练体", "校准守卫", "裂隙测量体", "刻时重锤", "回声鉴别器", "拾字虫",
	]
	var expected_hps: Array[int] = [18, 24, 28, 34, 36, 40]
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		var model = CombatModelScript.new()
		model.start_battle(73103, stage)
		_expect(model.enemy_name == expected_names[stage - 1], "path %d keeps enemy %s" % [stage, expected_names[stage - 1]])
		_expect(model.enemy_max_hp == expected_hps[stage - 1], "path %d keeps enemy hp %d" % [stage, expected_hps[stage - 1]])
	# 固定种子下的开局手牌顺序不得因目录化而改变。
	var replay_a = CombatModelScript.new()
	var replay_b = CombatModelScript.new()
	replay_a.start_battle(73103, 6)
	replay_b.start_battle(73103, 6)
	_expect(_hand_ids(replay_a) == _hand_ids(replay_b), "fixed seed remains reproducible after catalog refactor")
	var stage_two = CombatModelScript.new()
	stage_two.start_battle(73103, 2)
	_expect(stage_two.get_enemy_intent_text().contains("试探"), "path 2 first intent is still the probe")
	stage_two.end_player_turn()
	_expect(stage_two.get_enemy_intent_text().contains("架盾"), "path 2 cycles into the shield intent")


# ------------------------------------------------------------------- 目标选择器

func _test_target_selector() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 6)
	var context: TargetContext = model.build_target_context()
	_expect(context.enemy_count() == 1, "single-enemy battle exposes one logical enemy")
	_expect(TargetSelector.resolve_enemy(TargetSelector.Kind.SINGLE_ENEMY, context) == 0, "single enemy resolves to index zero")
	_expect(TargetSelector.resolve_enemy(TargetSelector.Kind.LOWEST_HP_ENEMY, context) == 0, "lowest hp enemy resolves to the only enemy")
	_expect(not TargetSelector.requires_player_choice(TargetSelector.Kind.SINGLE_ENEMY), "enemy targets are auto-resolved")
	_expect(TargetSelector.requires_player_choice(TargetSelector.Kind.HAND_CARD), "hand targets need player input")
	_expect(TargetSelector.requires_player_choice(TargetSelector.Kind.SEALED_CARD), "sealed targets need player input")
	_expect(TargetSelector.requires_player_choice(TargetSelector.Kind.DRAW_PILE_TOP), "draw pile targets need player input")

	var hand_candidates: Array[int] = TargetSelector.candidate_indices(TargetSelector.Kind.HAND_CARD, context)
	_expect(hand_candidates.size() == model.hand.size(), "hand candidates cover every card")
	# 抽牌堆顶 scope 限制：只暴露顶部三张，且第一个候选就是堆顶。
	var top_three: Array[int] = TargetSelector.candidate_indices(
		TargetSelector.Kind.DRAW_PILE_TOP, context, TargetSelector.Filter.NONE, 3
	)
	_expect(top_three.size() == 3, "draw pile scope limits candidates to three")
	_expect(top_three[0] == model.draw_pile.size() - 1, "first draw pile candidate is the top card")
	_expect(top_three[2] == model.draw_pile.size() - 3, "third draw pile candidate is three deep")
	_expect(TargetSelector.label_for(TargetSelector.Kind.DRAW_PILE_TOP, context, top_three[0]).begins_with("第1张"), "draw pile labels count depth from the top")

	# 消逝过滤器必须排除会消逝的牌。
	var exhaust_model = CombatModelScript.new()
	var exhaust_bonus: Array[StringName] = [&"critical_permission"]
	exhaust_model.start_battle(73103, 6, exhaust_bonus)
	_prepare_hand(exhaust_model, [&"critical_permission", &"calibration_strike"])
	var filtered: Array[int] = TargetSelector.candidate_indices(
		TargetSelector.Kind.HAND_CARD, exhaust_model.build_target_context(), TargetSelector.Filter.NON_EXHAUST
	)
	_expect(filtered.size() == 1 and filtered[0] == 1, "non-exhaust filter drops exhausting cards")
	var sealed_empty: Array[int] = TargetSelector.candidate_indices(
		TargetSelector.Kind.SEALED_CARD, exhaust_model.build_target_context()
	)
	_expect(sealed_empty.is_empty(), "empty sealed zone yields no candidates")
	_expect(not TargetSelector.describe(TargetSelector.Kind.SEALED_CARD).is_empty(), "target kinds have Chinese descriptions")


# ------------------------------------------------- 三张选择器化卡牌：完整流程

func _test_selector_cards_full_flow() -> void:
	# 索引重排：玩家指定抽牌堆顶三张中的任意一张进入弃牌堆。
	var reorder = CombatModelScript.new()
	var reorder_bonus: Array[StringName] = [&"index_reorder"]
	reorder.start_battle(81001, 6, reorder_bonus)
	_prepare_hand(reorder, [&"index_reorder"])
	var draw_before: int = reorder.draw_pile.size()
	var discard_before: int = reorder.discard_pile.size()
	_expect(reorder.play_card(0), "index reorder can be played")
	_expect(reorder.has_pending_selection(), "index reorder raises a selection request")
	var candidates: Array[int] = reorder.get_pending_candidate_indices()
	_expect(candidates.size() == 3, "index reorder shows three top cards")
	_expect(reorder.get_pending_candidate_labels().size() == 3, "index reorder labels each candidate")
	var chosen_index: int = candidates[2]
	var chosen_title: String = reorder.draw_pile[chosen_index].title
	_expect(not reorder.resolve_pending_selection(chosen_index - 5), "index reorder rejects out-of-scope choices")
	_expect(reorder.resolve_pending_selection(chosen_index), "index reorder accepts a valid choice")
	_expect(not reorder.has_pending_selection(), "index reorder clears the request after resolving")
	_expect(reorder.draw_pile.size() == draw_before - 1, "index reorder removes exactly one card from the draw pile")
	# 索引重排本身消逝，因此弃牌堆只增加被选中的那张。
	_expect(reorder.discard_pile.size() == discard_before + 1, "index reorder discards only the chosen card")
	_expect(reorder.discard_pile[reorder.discard_pile.size() - 1].title == chosen_title, "index reorder discards the player's pick")
	_expect(reorder.exhausted_zone.size() == 1, "index reorder itself exhausts")

	# 预写结局：玩家指定手牌中的非消逝牌。
	var prewrite = CombatModelScript.new()
	var prewrite_bonus: Array[StringName] = [&"prewritten_ending"]
	prewrite.start_battle(81002, 6, prewrite_bonus)
	_prepare_hand(prewrite, [&"prewritten_ending", &"calibration_strike", &"temporary_guard"])
	_expect(prewrite.play_card(0), "prewritten ending can be played")
	_expect(prewrite.has_pending_selection(), "prewritten ending raises a selection request")
	_expect(prewrite.get_pending_candidate_indices().size() == 2, "prewritten ending offers both non-exhaust cards")
	_expect(prewrite.resolve_pending_selection(1), "prewritten ending can target the second card")
	_expect(prewrite.sealed_zone.size() == 1, "prewritten ending seals one copy")
	_expect(prewrite.sealed_zone[0].id == &"temporary_guard", "prewritten ending copies the chosen card, not the first one")
	_expect(prewrite.sealed_zone[0].temporary, "prewritten ending copy is temporary")
	_expect(prewrite.get_card_cost(prewrite.hand[1]) == 0, "prewritten ending zeroes the chosen card cost")
	_expect(prewrite.get_card_cost(prewrite.hand[0]) > 0, "prewritten ending leaves other cards untouched")

	# 开封令：玩家指定封存区中的任意一张，而不是最早那张。
	var unseal = CombatModelScript.new()
	var unseal_bonus: Array[StringName] = [&"unseal_order"]
	unseal.start_battle(81003, 6, unseal_bonus)
	_prepare_hand(unseal, [&"delayed_guard", &"countdown_scar", &"unseal_order"])
	_expect(unseal.play_card(0), "delayed guard is sealed first")
	_expect(unseal.play_card(0), "countdown scar is sealed second")
	_expect(unseal.sealed_zone.size() == 2, "two cards wait in the sealed zone")
	var enemy_hp_before: int = unseal.enemy_hp
	_expect(unseal.play_card(0), "unseal order can be played")
	_expect(unseal.has_pending_selection(), "unseal order raises a selection request")
	_expect(unseal.get_pending_candidate_indices().size() == 2, "unseal order lists both sealed cards")
	# 选择第二张（倒计刻痕）而非最早那张，证明不再是确定性简化。
	_expect(unseal.resolve_pending_selection(1), "unseal order can target the newer sealed card")
	_expect(unseal.enemy_hp < enemy_hp_before, "unseal order triggered the chosen countdown scar")
	_expect(unseal.sealed_zone.size() == 1, "unseal order releases exactly one card")
	_expect(unseal.sealed_zone[0].id == &"delayed_guard", "unseal order left the unchosen card sealed")
	_expect(unseal.player_block == 0, "unseal order did not trigger the unchosen delayed guard")


# ------------------------------------------------- 三张选择器化卡牌：取消路径

func _test_selector_cards_cancel_path() -> void:
	for card_id: StringName in [&"index_reorder", &"prewritten_ending", &"unseal_order"]:
		var model = CombatModelScript.new()
		var bonus: Array[StringName] = [card_id]
		model.start_battle(82001, 6, bonus)
		if card_id == &"unseal_order":
			_prepare_hand(model, [&"delayed_guard", card_id])
			model.play_card(0)
		else:
			_prepare_hand(model, [card_id, &"calibration_strike"])
		var hand_before: Array[StringName] = _hand_ids(model)
		var energy_before: int = model.energy
		var draw_before: int = model.draw_pile.size()
		var discard_before: int = model.discard_pile.size()
		var sealed_before: int = model.sealed_zone.size()
		var exhaust_before: int = model.exhausted_zone.size()
		var played_before: int = model.cards_played_this_turn
		var instability_before: int = model.instability
		var enemy_hp_before: int = model.enemy_hp
		var block_before: int = model.player_block
		_expect(model.play_card(0), "%s can be played before cancelling" % card_id)
		_expect(model.has_pending_selection(), "%s raises a selection request" % card_id)
		_expect(model.energy <= energy_before, "%s does not gain energy while suspended" % card_id)
		_expect(model.pending_selection.paid_cost == energy_before - model.energy, "%s records the exact paid cost" % card_id)
		_expect(model.cancel_pending_selection(), "%s selection can be cancelled" % card_id)
		_expect(not model.has_pending_selection(), "%s clears the request on cancel" % card_id)
		_expect(model.energy == energy_before, "%s refunds the full cost on cancel" % card_id)
		_expect(_hand_ids(model) == hand_before, "%s returns to its original hand position" % card_id)
		_expect(model.draw_pile.size() == draw_before, "%s cancel leaves the draw pile untouched" % card_id)
		_expect(model.discard_pile.size() == discard_before, "%s cancel leaves the discard pile untouched" % card_id)
		_expect(model.sealed_zone.size() == sealed_before, "%s cancel leaves the sealed zone untouched" % card_id)
		_expect(model.exhausted_zone.size() == exhaust_before, "%s cancel does not exhaust the card" % card_id)
		_expect(model.cards_played_this_turn == played_before, "%s cancel does not count as a played card" % card_id)
		_expect(model.instability == instability_before, "%s cancel applies no overload" % card_id)
		_expect(model.enemy_hp == enemy_hp_before, "%s cancel deals no damage" % card_id)
		_expect(model.player_block == block_before, "%s cancel grants no block" % card_id)
		_expect(model.last_card_id != card_id, "%s cancel does not update the echo snapshot" % card_id)
		# 取消后仍可重新打出并正常完成。
		_expect(model.play_card(0), "%s can be replayed after cancelling" % card_id)
		_expect(model.has_pending_selection(), "%s raises the request again on replay" % card_id)
		var retry: Array[int] = model.get_pending_candidate_indices()
		_expect(model.resolve_pending_selection(retry[0]), "%s resolves normally after a cancel" % card_id)

	# 缺名层数也必须原样返还。
	var missing = CombatModelScript.new()
	var missing_bonus: Array[StringName] = [&"index_reorder"]
	missing.start_battle(82002, 6, missing_bonus)
	_prepare_hand(missing, [&"index_reorder"])
	missing.missing_name[CardData.CardType.LAW] = 2
	var cost_with_missing: int = missing.get_card_cost(missing.hand[0])
	_expect(cost_with_missing == 2, "missing name raises the law card cost")
	_expect(missing.play_card(0), "law card can be played with missing name")
	_expect(int(missing.missing_name.get(CardData.CardType.LAW, 0)) == 1, "playing consumes one missing name stack")
	_expect(missing.cancel_pending_selection(), "selection can be cancelled with missing name active")
	_expect(int(missing.missing_name.get(CardData.CardType.LAW, 0)) == 2, "cancel restores the consumed missing name stack")

	# 挂起期间不接受出牌与结束回合，规则层仍是唯一真相源。
	var locked = CombatModelScript.new()
	var locked_bonus: Array[StringName] = [&"index_reorder"]
	locked.start_battle(82003, 6, locked_bonus)
	_prepare_hand(locked, [&"index_reorder", &"calibration_strike"])
	locked.play_card(0)
	var locked_turn: int = locked.turn_number
	_expect(not locked.play_card(0), "no other card can be played while a selection is pending")
	locked.end_player_turn()
	_expect(locked.turn_number == locked_turn, "turn cannot end while a selection is pending")
	_expect(locked.has_pending_selection(), "pending selection survives rejected input")


# ------------------------------------------------------------ 规则优先级系统

func _test_rule_engine_priority() -> void:
	var expected_order: Array[String] = [
		RuleEngine.phase_name(RuleEngine.Phase.BASE),
		RuleEngine.phase_name(RuleEngine.Phase.ATTACKER),
		RuleEngine.phase_name(RuleEngine.Phase.DEFENDER),
		RuleEngine.phase_name(RuleEngine.Phase.RELIC),
		RuleEngine.phase_name(RuleEngine.Phase.CLAMP),
	]
	var engine: RuleEngine = RuleEngine.new()
	var no_relics: Array[StringName] = []
	engine.reset_for_battle(no_relics)

	# 每个通道都必须完整走完五个阶段，且顺序固定。
	engine.compute_damage_to_enemy(6, true)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "damage pipeline follows the fixed phase order")
	engine.compute_block(5)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "block pipeline follows the fixed phase order")
	engine.compute_draw(2, 0, CombatModelScript.MAX_HAND_SIZE)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "draw pipeline follows the fixed phase order")
	engine.compute_cost(1, 0)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "cost pipeline follows the fixed phase order")
	engine.compute_fracture_damage(CombatModelScript.FRACTURE_DAMAGE, false)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "fracture pipeline follows the fixed phase order")
	engine.compute_instability_gain(2)
	_expect(_first_occurrences(engine.trace_phase_sequence()) == expected_order, "instability pipeline follows the fixed phase order")

	# 力量在虚弱之前结算：(6+3)*0.75 = 6，而非 6*0.75+3 = 7。
	engine.player_strength = 3
	engine.player_weak_turns = 1
	_expect(engine.compute_damage_to_enemy(6, true) == 6, "strength is added before weak multiplies")
	# 受击方脆弱在攻击方修正之后：((6+3)*0.75)*1.5 = 9。
	engine.enemy_vulnerable_turns = 1
	_expect(engine.compute_damage_to_enemy(6, true) == 9, "defender vulnerable applies after attacker modifiers")
	engine.enemy_vulnerable_turns = 0
	# 非攻击来源跳过攻击方状态。
	_expect(engine.compute_damage_to_enemy(6, false) == 6, "non-attack damage skips attacker status")
	engine.player_strength = 0
	engine.player_weak_turns = 0

	# CLAMP 阶段负责下限与上限。
	_expect(engine.compute_damage_to_enemy(-5, true) == 0, "clamp floors damage at zero")
	_expect(engine.compute_block(-3) == 0, "clamp floors block at zero")
	_expect(engine.compute_cost(0, 0) == 0, "clamp floors cost at zero")
	_expect(engine.compute_draw(5, CombatModelScript.MAX_HAND_SIZE - 2, CombatModelScript.MAX_HAND_SIZE) == 2, "clamp caps draw at remaining hand room")
	_expect(engine.compute_draw(5, CombatModelScript.MAX_HAND_SIZE, CombatModelScript.MAX_HAND_SIZE) == 0, "clamp blocks draw when hand is full")
	_expect(engine.compute_fracture_damage(CombatModelScript.FRACTURE_DAMAGE, true) == 0, "clamp zeroes prevented fracture damage")
	_expect(engine.compute_cost(1, 2) == 3, "missing name raises cost inside the pipeline")

	# 玩家受击通道：蓄力加成在脆弱之前。(11+3)*1.5 = 21。
	engine.enemy_next_attack_bonus = 3
	engine.player_vulnerable_turns = 1
	_expect(engine.compute_damage_to_player(11, true) == 21, "enemy charge is added before player vulnerable multiplies")
	engine.enemy_next_attack_bonus = 0
	engine.player_vulnerable_turns = 0

	# 战斗内的伤害、格挡与费用确实经过管线。
	var model = CombatModelScript.new()
	model.start_battle(83001, 6)
	model.rule_engine.player_strength = 2
	_prepare_hand(model, [&"calibration_strike", &"temporary_guard"])
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "attack routes through the pipeline")
	_expect(model.enemy_hp == hp_before - 8, "combat damage includes pipeline strength")
	model.rule_engine.player_weak_turns = 1
	var block_before: int = model.player_block
	_expect(model.play_card(0), "block routes through the pipeline")
	_expect(model.player_block == block_before + 5, "weak does not reduce block")


func _test_relics_in_pipeline() -> void:
	#裂纹稳定器：每场战斗第一次获得不稳定时少 1 点。
	var stabilizer = CombatModelScript.new()
	var stabilizer_bonus: Array[StringName] = []
	var stabilizer_relics: Array[StringName] = [&"crack_stabilizer"]
	stabilizer.start_battle(84001, 6, stabilizer_bonus, &"", stabilizer_relics)
	_prepare_hand(stabilizer, [&"rift_slash", &"boundary_read"])
	_expect(stabilizer.play_card(0), "rift slash can be played with the stabilizer")
	_expect(stabilizer.instability == 1, "crack stabilizer removes one point from the first overload")
	_expect(stabilizer.play_card(0), "boundary read can be played next")
	_expect(stabilizer.instability == 3, "crack stabilizer only affects the first overload")

	var without = CombatModelScript.new()
	var no_relic: Array[StringName] = []
	var no_bonus: Array[StringName] = []
	without.start_battle(84001, 6, no_bonus, &"", no_relic)
	_prepare_hand(without, [&"rift_slash"])
	without.play_card(0)
	_expect(without.instability == 2, "without the stabilizer the first overload is unchanged")

	# 无字藏书票：每场战斗第一次打出律式后抽 1 张。
	var bookplate = CombatModelScript.new()
	var bookplate_bonus: Array[StringName] = []
	var bookplate_relics: Array[StringName] = [&"wordless_bookplate"]
	bookplate.start_battle(84002, 6, bookplate_bonus, &"", bookplate_relics)
	_prepare_hand(bookplate, [&"forced_stability", &"restate", &"boundary_read"])
	var hand_after_defense: int = bookplate.hand.size()
	_expect(bookplate.play_card(0), "defense card can be played first")
	_expect(bookplate.hand.size() == hand_after_defense - 1, "bookplate does not trigger on a defense card")
	_expect(not bookplate.rule_engine.bookplate_used, "bookplate stays armed before any law card")
	var before_law: int = bookplate.hand.size()
	_expect(bookplate.play_card(0), "first law card can be played")
	# 打出后手牌 -1，藏书票再补 1，因此净变化为 0。
	_expect(bookplate.hand.size() == before_law, "bookplate draws one card after the first law card")
	_expect(bookplate.rule_engine.bookplate_used, "bookplate marks itself spent after the first law card")
	_expect(bookplate.rule_engine.consume_bookplate_draw(CardData.CardType.LAW) == 0, "bookplate only triggers once per battle")
	_expect(bookplate.play_card(0), "second law card can be played")

	_expect(RuleEngine.is_relic_implemented(&"crack_stabilizer"), "crack stabilizer is wired into the pipeline")
	_expect(RuleEngine.is_relic_implemented(&"wordless_bookplate"), "wordless bookplate is wired into the pipeline")
	_expect(RuleEngine.RELIC_DEFINITIONS.size() == 8, "all eight designed relics have a data slot")
	for relic_id: Variant in RuleEngine.RELIC_DEFINITIONS.keys():
		var relic_name: StringName = relic_id as StringName
		_expect(not RuleEngine.relic_title(relic_name).is_empty(), "relic %s has a Chinese title" % relic_name)
		var definition: Dictionary = RuleEngine.RELIC_DEFINITIONS[relic_name]
		_expect(not str(definition.get(&"description", "")).is_empty(), "relic %s has rules text" % relic_name)


# ------------------------------------------------------------------- 正式敌人

func _test_hollow_name_guard() -> void:
	var model = CombatModelScript.new()
	var bonus: Array[StringName] = []
	var relics: Array[StringName] = []
	model.start_battle(85001, 6, bonus, &"hollow_name_guard", relics)
	_expect(model.enemy_name == "空名卫士", "hollow name guard is loaded from the catalog")
	_expect(model.enemy_max_hp >= 34 and model.enemy_max_hp <= 38, "hollow name guard hp sits in its designed range")
	_expect(model.stone_shell == 8, "hollow name guard opens with eight stone shell")

	# 石壳先于生命承受伤害。
	_prepare_hand(model, [&"calibration_strike", &"temporary_guard", &"temporary_guard"])
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "attack hits the stone shell first")
	_expect(model.stone_shell == 2, "stone shell absorbs the six damage")
	_expect(model.enemy_hp == hp_before, "stone shell protects enemy hp")

	# 切换类别（攻式 → 守式）使卫士失去全部石壳。
	_expect(model.play_card(0), "defense card switches the played type")
	_expect(model.stone_shell == 0, "switching card type strips all stone shell")
	_expect(model.stone_shell_broken_this_turn, "stone shell counts as broken after the switch")

	# 同式适应：连续两张同类别非状态牌让卫士获得 5 格挡。
	var block_before: int = model.enemy_block
	_expect(model.play_card(0), "second defense card of the same type resolves")
	_expect(model.enemy_block == block_before + 5, "same-type adaptation grants five block")

	# 石壳每回合恢复 4，不超过初始值。
	model.end_player_turn()
	_expect(model.stone_shell == 4, "stone shell regenerates four per turn")
	_expect(not model.stone_shell_broken_this_turn, "broken flag resets each turn")
	model.end_player_turn()
	_expect(model.stone_shell == 8, "stone shell regeneration caps at its initial value")

	# 碑刃随石壳状态在11 与 15 之间切换。
	var intact = CombatModelScript.new()
	intact.start_battle(85002, 6, bonus, &"hollow_name_guard", relics)
	intact.enemy_intent_index = 1
	_expect(intact.get_enemy_intent_text().contains("15"), "stele blade reads fifteen while the shell holds")
	intact.stone_shell = 0
	intact.stone_shell_broken_this_turn = true
	_expect(intact.get_enemy_intent_text().contains("11"), "stele blade drops to eleven once the shell breaks")
	var player_hp_before: int = intact.player_hp
	intact.end_player_turn()
	_expect(intact.player_hp < player_hp_before, "stele blade actually damages the player")

	# 无名敕令把《空页》放入抽牌堆。
	var edict = CombatModelScript.new()
	edict.start_battle(85003, 6, bonus, &"hollow_name_guard", relics)
	edict.enemy_intent_index = 2
	var total_before: int = _count_all_cards(edict, &"blank_page")
	_expect(total_before == 0, "no blank page exists before the edict")
	edict.end_player_turn()
	# 敕令后立刻进入新回合并抽牌，因此《空页》可能已经进入手牌，统计全部区域。
	_expect(_count_all_cards(edict, &"blank_page") == 1, "nameless edict inserts exactly one blank page")


func _test_reverse_reader() -> void:
	var bonus: Array[StringName] = []
	var relics: Array[StringName] = []
	var expectations: Array[Dictionary] = [
		{&"card": &"calibration_strike", &"intent": "倒读·攻式", &"block": 10},
		{&"card": &"temporary_guard", &"intent": "倒读·守式", &"weak": 2},
		{&"card": &"boundary_read", &"intent": "倒读·律式", &"missing": 1},
	]
	for case: Dictionary in expectations:
		var model = CombatModelScript.new()
		model.start_battle(86001, 6, bonus, &"reverse_reader", relics)
		_expect(model.enemy_name == "倒读者", "reverse reader is loaded from the catalog")
		_expect(model.enemy_max_hp >= 68 and model.enemy_max_hp <= 72, "reverse reader hp sits in its calibrated range")
		_expect(model.reverse_record_type < 0, "reverse reader starts with no record")
		_prepare_hand(model, [case[&"card"] as StringName])
		_expect(model.play_card(0), "record card %s can be played" % case[&"card"])
		model.end_player_turn()
		# 记录在下一回合开始时提交，玩家因此能提前看见改变后的意图。
		_expect(
			model.get_enemy_intent_text().contains(str(case[&"intent"])),
			"reverse reader switches to %s after the recorded card" % case[&"intent"]
		)
		if case.has(&"block"):
			var block_target: int = int(case[&"block"])
			model.end_player_turn()
			_expect(model.enemy_block >= block_target, "reverse reader gained %d block from the attack record" % block_target)
		if case.has(&"weak"):
			model.end_player_turn()
			_expect(model.rule_engine.player_weak_turns >= 1, "reverse reader applied weak from the defense record")
		if case.has(&"missing"):
			model.end_player_turn()
			_expect(int(model.missing_name.get(CardData.CardType.LAW, 0)) >= 1, "reverse reader applied law missing name")

	# 玩家未出牌：倒读者进入困惑并失去 8 生命。
	var confused = CombatModelScript.new()
	confused.start_battle(86002, 6, bonus, &"reverse_reader", relics)
	_expect(confused.get_enemy_intent_text().contains("困惑"), "reverse reader shows confusion without a record")
	var hp_before: int = confused.enemy_hp
	confused.end_player_turn()
	_expect(confused.enemy_hp == hp_before - 8, "confusion costs the reverse reader eight hp")

	# 状态牌不进入倒读记录。
	var status = CombatModelScript.new()
	status.start_battle(86003, 6, bonus, &"reverse_reader", relics)
	_prepare_hand(status, [&"calibration_strike"])
	status.hand.append(CardCatalog.create_card(&"blank_page", 900))
	status.play_card(0)
	_expect(status.reverse_record_pending == CardData.CardType.ATTACK, "attack card is recorded")
	status.play_card(0)
	_expect(status.reverse_record_pending == CardData.CardType.ATTACK, "status card does not overwrite the reverse record")


func _test_binding_instrument() -> void:
	var bonus: Array[StringName] = []
	var relics: Array[StringName] = []
	var model = CombatModelScript.new()
	model.start_battle(87001, 6, bonus, &"binding_instrument", relics)
	_expect(model.enemy_name == "装订刑具", "binding instrument is loaded from the catalog")
	_expect(model.enemy_max_hp == 88, "binding instrument has eighty-eight hp")
	_expect(model.enemy_definition.tier == "精英", "binding instrument is marked elite")
	_expect(model.enemy_definition.binding_draw_threshold == 3, "binding triggers at three extra draws")

	# 基础回合抽牌不计入装订读数。
	_expect(model.extra_draws_this_turn == 0, "base draw does not count towards binding")
	var discard_before: int = model.discard_pile.size()
	model.draw_cards(2, false)
	_expect(model.discard_pile.size() == discard_before, "two extra draws do not trigger binding yet")
	model.draw_cards(1, false)
	_expect(_pile_contains(model.discard_pile, &"redaction"), "third extra draw puts a redaction in the discard pile")
	var after_trigger: int = model.discard_pile.size()
	model.draw_cards(3, false)
	_expect(model.discard_pile.size() == after_trigger, "binding triggers at most once per turn")

	# 下一回合可以再次触发。
	model.end_player_turn()
	_expect(not model.binding_triggered_this_turn, "binding resets each turn")

	# 压页在手牌存在状态牌时额外造成 5 点伤害。
	var press = CombatModelScript.new()
	press.start_battle(87002, 6, bonus, &"binding_instrument", relics)
	press.enemy_intent_index = 2
	var clean_hp: int = press.player_hp
	press.end_player_turn()
	var clean_damage: int = clean_hp - press.player_hp
	var pressed = CombatModelScript.new()
	pressed.start_battle(87002, 6, bonus, &"binding_instrument", relics)
	pressed.enemy_intent_index = 2
	pressed.hand.append(CardCatalog.create_card(&"blank_page", 901))
	_expect(pressed.get_enemy_intent_text().contains("额外"), "press page warns about the status card bonus")
	var status_hp: int = pressed.player_hp
	pressed.end_player_turn()
	var status_damage: int = status_hp - pressed.player_hp
	_expect(status_damage == clean_damage + 5, "press page adds five damage when a status card is held")

	# 拆脊施加 2 回合脆弱。
	var unbind = CombatModelScript.new()
	unbind.start_battle(87003, 6, bonus, &"binding_instrument", relics)
	unbind.enemy_intent_index = 3
	unbind.end_player_turn()
	_expect(unbind.rule_engine.player_vulnerable_turns >= 1, "unbind spine applies vulnerable")

	# 装订意图把两张《空页》放入抽牌堆。
	var bind = CombatModelScript.new()
	bind.start_battle(87004, 6, bonus, &"binding_instrument", relics)
	bind.enemy_intent_index = 1
	_expect(_count_all_cards(bind, &"blank_page") == 0, "no blank page exists before binding")
	bind.end_player_turn()
	_expect(_count_all_cards(bind, &"blank_page") == 2, "bind adds exactly two blank pages")
	_expect(bind.get_enemy_total_block() >= 8, "bind grants the instrument eight block")


## 战斗日志不得再出现“首版确定性简化”之类的临时说明。
func _test_old_wound_end_turn_damage() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 6)
	model.hand.clear()
	model.player_hp = 20
	model.player_block = 99
	model.hand.append(CardCatalog.create_card(&"old_wound", 9001))
	model.hand.append(CardCatalog.create_card(&"old_wound", 9002))
	model._resolve_old_wounds_in_hand()
	_expect(model.player_hp == 16, "each old wound deals two end-turn damage")
	_expect(model.player_block == 99, "old wound damage bypasses block")
	_expect(not model.battle_over, "nonlethal old wound damage keeps battle active")


func _test_no_temporary_simplification_logs() -> void:
	var forbidden: Array[String] = ["首版确定性简化", "首版", "确定性简化", "尚无选择器"]
	var models: Array = []
	for card_id: StringName in [&"index_reorder", &"prewritten_ending", &"unseal_order"]:
		var model = CombatModelScript.new()
		var bonus: Array[StringName] = [card_id]
		model.start_battle(88001, 6, bonus)
		if card_id == &"unseal_order":
			_prepare_hand(model, [&"delayed_guard", card_id])
			model.play_card(0)
		else:
			_prepare_hand(model, [card_id, &"calibration_strike"])
		model.play_card(0)
		if model.has_pending_selection():
			var candidates: Array[int] = model.get_pending_candidate_indices()
			model.resolve_pending_selection(candidates[0])
		models.append(model)
	for model in models:
		for entry: String in model.log_entries:
			for phrase: String in forbidden:
				_expect(not entry.contains(phrase), "combat log avoids the phrase %s" % phrase)


func _first_occurrences(sequence: Array[String]) -> Array[String]:
	var unique: Array[String] = []
	for entry: String in sequence:
		if not unique.has(entry):
			unique.append(entry)
	return unique


func _count_all_cards(model, card_id: StringName) -> int:
	var total: int = 0
	for pile in [model.draw_pile, model.hand, model.discard_pile, model.sealed_zone, model.exhausted_zone]:
		for card in pile:
			if card.id == card_id:
				total += 1
	return total


func _pile_contains(pile: Array[CardData], card_id: StringName) -> bool:
	for card: CardData in pile:
		if card.id == card_id:
			return true
	return false


func _contains_only_basic_cards(ids: Array[StringName]) -> bool:
	for card_id: StringName in ids:
		if card_id != &"calibration_strike" and card_id != &"temporary_guard":
			return false
	return ids.size() == 10


func _all_card_ids(model) -> Array[StringName]:
	var ids: Array[StringName] = []
	for pile in [model.draw_pile, model.hand, model.discard_pile, model.sealed_zone, model.exhausted_zone]:
		for card in pile:
			ids.append(card.id)
	return ids


func _prepare_hand(model, card_ids: Array[StringName]) -> void:
	while not model.hand.is_empty():
		model.discard_pile.append(model.hand.pop_back())
	for card_id: StringName in card_ids:
		var card = _extract_card(model, card_id)
		if card != null:
			model.hand.append(card)
	model.energy = 9


func _extract_card(model, card_id: StringName):
	for pile in [model.draw_pile, model.discard_pile]:
		for index: int in range(pile.size()):
			if pile[index].id == card_id:
				var card = pile[index]
				pile.remove_at(index)
				return card
	_expect(false, "card exists in test deck: %s" % card_id)
	return null


func _hand_ids(model) -> Array[StringName]:
	var ids: Array[StringName] = []
	for card in model.hand:
		ids.append(card.id)
	return ids


func _find_hand_card(model, card_id: StringName) -> int:
	for index: int in range(model.hand.size()):
		if model.hand[index].id == card_id:
			return index
	return -1


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
