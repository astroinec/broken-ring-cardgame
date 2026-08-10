extends SceneTree

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(int(ProjectSettings.get_setting("display/window/size/window_width_override")) <= 960, "default window fits compact desktop width")
	_expect(int(ProjectSettings.get_setting("display/window/size/window_height_override")) <= 540, "default window fits compact desktop height")
	_expect(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "window resizing preserves 16:9 viewport aspect")
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
	_expect(main.page.get_combined_minimum_size().x <= 1240.0, "combat page minimum width fits inside 1280 viewport margins")
	_expect(main.screen_root.size.x <= 1280.0, "combat controls do not force the root wider than the logical viewport")
	main._restart_run()
	await process_frame
	_expect(not main.is_test_mode, "main route is separate from test mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MIN, "main route begins at first path node")
	for stage: int in range(1, CombatModel.TUTORIAL_STAGE_MAX + 1):
		var model: CombatModel = CombatModel.new()
		model.start_battle(73103, stage)
		_expect(not model.tutorial_stage_title.contains("教学"), "path %d title is diegetic" % stage)
		_expect(not model.tutorial_hint.contains("教学"), "path %d context text is diegetic" % stage)

	await _test_expedition_ui(main)

	# 机制测试场的对手菜单必须列出目录中的每个可选敌人。
	main._show_test_arena_menu()
	await process_frame
	_expect(not main.is_test_mode, "arena menu itself is not a battle")
	var arena_menu: Node = main.screen_root.get_child(0)
	var opponent_list: Node = arena_menu.get_node("PageScroll/TestOpponentList")
	_expect(
		opponent_list.get_child_count() == EnemyCatalog.TEST_ARENA_ENEMY_IDS.size(),
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


func _test_expedition_ui(main) -> void:
	_expect(main.ui_mode == &"map", "starting a run opens the nine-depth map UI")
	_expect(main.run_model.available_node_ids == [&"d01_00"], "map UI begins with only the legal start node")
	main._on_map_node_pressed(&"d02_01")
	await process_frame
	_expect(main.ui_mode == &"map", "UI rejects an unreachable map node")

	main._on_map_node_pressed(&"d01_00")
	await process_frame
	_expect(main.ui_mode == &"combat", "battle node opens the combat UI")
	main.model.battle_over = true
	main.model.victory = true
	main._on_battle_result_pressed()
	await process_frame
	_expect(main.ui_mode == &"reward", "battle victory opens the reward UI")
	_expect(main.run_model.ink_crystals == RunModel.NORMAL_BATTLE_INCOME, "battle UI settles normal-node ink income once")
	main._on_reward_skipped()
	await process_frame
	_expect(main.ui_mode == &"map" and main.run_model.available_node_ids.size() == 2, "reward completion returns to the map and opens the fork")

	main._on_map_node_pressed(&"d02_01")
	await process_frame
	_expect(main.ui_mode == &"event", "event node opens the event UI")
	main._on_event_choice(0)
	await process_frame
	_expect(main.ui_mode == &"event_outcome", "event choice completes into an outcome screen")
	main._show_map_screen()
	await process_frame
	_expect(main.run_model.available_node_ids == [&"d03_00"], "event outcome returns to the legal route successor")

	main._on_map_node_pressed(&"d03_00")
	await process_frame
	_expect(main.ui_mode == &"rest", "REST node opens heal/upgrade/skip choices")
	main._on_rest_skip_pressed()
	await process_frame
	_expect(main.ui_mode == &"map", "skipping REST returns to the map")

	main._on_map_node_pressed(&"d04_01")
	await process_frame
	_expect(main.ui_mode == &"shop", "shop node opens deterministic stock and removal UI")
	var stock_digest: String = ShopCatalog.digest(main.run_model.pending_shop_stock)
	main._show_shop_screen()
	await process_frame
	_expect(ShopCatalog.digest(main.run_model.pending_shop_stock) == stock_digest, "redrawing the shop UI does not reroll stock")
	main._on_shop_leave_pressed()
	await process_frame
	_expect(main.ui_mode == &"map", "leaving the shop completes it and returns to map")

	main._on_map_node_pressed(&"d05_00")
	await process_frame
	_expect(main.ui_mode == &"event", "second event node is wired through the same map protocol")
	main._on_event_choice(0)
	await process_frame
	main._show_map_screen()
	await process_frame

	main._on_map_node_pressed(&"d06_01")
	await process_frame
	_expect(main.ui_mode == &"forge", "forge node opens instance upgrade selection")
	var forge_candidates: Array[Dictionary] = main.run_model.get_unupgraded_instances()
	var forge_id: int = int(forge_candidates[0][&"instance_id"])
	main._on_upgrade_instance_pressed(forge_id, &"forge")
	await process_frame
	_expect(main.ui_mode == &"map", "forge upgrade completes and returns to map")
	_expect(main.run_model.get_deck_instance(forge_id)[&"upgrade_id"] != &"", "forge UI upgrades the selected stable instance")

	main._on_map_node_pressed(&"d07_00")
	await process_frame
	_expect(main.ui_mode == &"combat", "later battle node reuses combat UI with run deck")
	main.model.battle_over = true
	main.model.victory = true
	main._on_battle_result_pressed()
	await process_frame
	_expect(main.ui_mode == &"reward", "later battle also returns through reward UI")
	main._on_reward_skipped()
	await process_frame

	main.run_model.player_hp = 40
	main._on_map_node_pressed(&"d08_00")
	await process_frame
	_expect(main.ui_mode == &"rest", "pre-Boss REST node opens correctly")
	main._on_rest_heal_pressed()
	await process_frame
	_expect(main.run_model.player_hp == 54 and main.ui_mode == &"map", "REST heal applies 20 percent and returns to map")

	main._on_map_node_pressed(&"d09_00")
	await process_frame
	_expect(main.ui_mode == &"combat", "depth-nine node opens the formal Boss combat UI")
	_expect(main.model.enemy_id == &"name_eraser" and main.model.boss_phase == 1, "depth-nine combat uses the phase-one name eraser")
	main.model.boss_phase = 2
	var deleted_card: CardData = main.model.hand[0]
	main.model._delete_boss_card_type(deleted_card)
	main._refresh_combat()
	await process_frame
	_expect(_tree_contains_text(main.hand_box, "类别：已删除"), "Boss hand cards visibly expose category deletion")
	_expect(_tree_contains_text(main.page, "REC-10 / 可覆写载体"), "Boss combat visibly exposes archive and deletion state")
	main.model.boss_recovery_count = 2
	main.model._enter_boss_terminal()
	main._refresh_combat()
	await process_frame
	_expect(main.ui_mode == &"boss_terminal", "terminal hp lock opens the two-option Boss page")
	_expect(_tree_contains_text(main.screen_root, "交付定义律印") and _tree_contains_text(main.screen_root, "读取被删原文"), "terminal page renders both rule-layer options")
	main._on_boss_terminal_choice(&"read_original")
	await process_frame
	_expect(main.ui_mode == &"expedition_complete", "Boss terminal choice reaches the expedition settlement")
	_expect(main.run_model.map_graph.get_node(&"d09_00").completed, "formal Boss can only be completed once through the node protocol")
	_expect(main.run_model.evidence.has("第十份校准记录"), "hidden Boss ending reaches RunModel evidence")


func _tree_contains_text(node: Node, fragment: String) -> bool:
	if node is Button and (node as Button).text.contains(fragment):
		return true
	if node is Label and (node as Label).text.contains(fragment):
		return true
	for child: Node in node.get_children():
		if _tree_contains_text(child, fragment):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
