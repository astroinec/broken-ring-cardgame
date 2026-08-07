extends SceneTree

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	_expect(main.screen_root.get_child_count() == 1, "main menu is shown on startup")
	main._start_test_level()
	await process_frame
	_expect(main.is_test_mode, "test level uses independent mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MAX, "test level opens full-mechanic encounter")
	_expect(main.model.is_mechanic_unlocked(&"missing_name"), "test level unlocks all implemented mechanics")
	main._restart_run()
	await process_frame
	_expect(not main.is_test_mode, "main route is separate from test mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MIN, "main route begins at first path node")
	for stage: int in range(1, CombatModel.TUTORIAL_STAGE_MAX + 1):
		var model: CombatModel = CombatModel.new()
		model.start_battle(73103, stage)
		_expect(not model.tutorial_stage_title.contains("教学"), "path %d title is diegetic" % stage)
		_expect(not model.tutorial_hint.contains("教学"), "path %d context text is diegetic" % stage)

	# 机制测试场的对手菜单必须列出目录中的每个可选敌人。
	main._show_test_arena_menu()
	await process_frame
	_expect(not main.is_test_mode, "arena menu itself is not a battle")
	var arena_menu: Node = main.screen_root.get_child(0)
	_expect(
		arena_menu.get_child_count() >= EnemyCatalog.TEST_ARENA_ENEMY_IDS.size(),
		"arena menu lists every selectable opponent"
	)
	for arena_id: StringName in EnemyCatalog.TEST_ARENA_ENEMY_IDS:
		main._start_test_level(arena_id)
		await process_frame
		_expect(main.model.enemy_id == arena_id, "arena launches the chosen opponent %s" % arena_id)
		_expect(main.is_test_mode, "arena battle runs in test mode for %s" % arena_id)

	# 选择模式：UI 只转交点击，规则层保持唯一真相源。
	main._start_test_level(&"word_eater")
	await process_frame
	var selector_bonus: Array[StringName] = [&"index_reorder"]
	main.model.start_battle(73103, CombatModel.TUTORIAL_STAGE_MAX, selector_bonus)
	while not main.model.hand.is_empty():
		main.model.discard_pile.append(main.model.hand.pop_back())
	for index: int in range(main.model.draw_pile.size()):
		if main.model.draw_pile[index].id == &"index_reorder":
			main.model.hand.append(main.model.draw_pile[index])
			main.model.draw_pile.remove_at(index)
			break
	main.model.energy = 9
	main._refresh_combat()
	await process_frame
	_expect(not main.model.has_pending_selection(), "no selection is pending before the card is played")
	main._on_card_pressed(0)
	await process_frame
	_expect(main.model.has_pending_selection(), "playing index reorder puts the UI into selection mode")
	_expect(main.end_turn_button.disabled, "end turn is blocked during selection mode")
	_expect(main.hand_box.get_child_count() == main.model.get_pending_candidate_indices().size() + 1, "selection row shows every candidate plus cancel")
	_expect(main.result_label.text.contains("选择模式"), "footer announces selection mode in Chinese")
	main._on_selection_cancelled()
	await process_frame
	_expect(not main.model.has_pending_selection(), "cancel exits selection mode")
	_expect(not main.end_turn_button.disabled, "end turn is available again after cancelling")
	_expect(main.hand_box.get_child_count() == main.model.hand.size(), "hand row returns after cancelling")
	main._on_card_pressed(0)
	await process_frame
	var candidates: Array[int] = main.model.get_pending_candidate_indices()
	main._on_selection_confirmed(candidates[0])
	await process_frame
	_expect(not main.model.has_pending_selection(), "confirming a target exits selection mode")

	main.queue_free()
	if failures == 0:
		print("PASS: main route and test-level flow checks")
		quit(0)
	else:
		push_error("FAIL: %d flow checks failed" % failures)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
