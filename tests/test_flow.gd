extends SceneTree

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var suffix: String = "%d" % OS.get_process_id()
	var save_path: String = "user://broken_ring_flow_test_%s.json" % suffix
	var profile_path: String = "user://broken_ring_flow_profile_test_%s.json" % suffix
	var save_manager: SaveManager = SaveManager.new(save_path)
	var profile_manager: ProfileManager = ProfileManager.new(profile_path)
	save_manager.delete()
	profile_manager.delete()
	_expect(int(ProjectSettings.get_setting("display/window/size/window_width_override")) <= 960, "default window fits compact desktop width")
	_expect(int(ProjectSettings.get_setting("display/window/size/window_height_override")) <= 540, "default window fits compact desktop height")
	_expect(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "window resizing preserves 16:9 viewport aspect")
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	main.save_manager = save_manager
	main.profile_manager = profile_manager
	root.add_child(main)
	await process_frame
	_expect(main.screen_root.get_child_count() == 1, "main menu is shown on startup")
	_expect(_find_button_with_text(main.screen_root, "继续远征") == null, "无存档时标题页不显示继续")
	var seed_input: LineEdit = _find_named(main.screen_root, "SeedInput") as LineEdit
	var seed_error: Label = _find_named(main.screen_root, "SeedInputError") as Label
	_expect(seed_input != null and _find_button_with_text(main.screen_root, "使用种子复现") != null, "标题页提供随机种子复现入口")
	main._start_seeded_run_from_text("not-a-seed", seed_input, seed_error)
	_expect(seed_error.text.contains("正整数") and main.run_model == null, "非法 seed 显示错误且不开始远征")
	await _test_profile_archive_ui(main, profile_manager)
	main._start_test_level()
	await process_frame
	_expect(main.is_test_mode, "test level uses independent mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MAX, "test level opens full-mechanic encounter")
	_expect(main.model.is_mechanic_unlocked(&"missing_name"), "test level unlocks all implemented mechanics")
	_expect(main.page.get_combined_minimum_size().x <= 1240.0, "combat page minimum width fits inside 1280 viewport margins")
	_expect(main.screen_root.size.x <= 1280.0, "combat controls do not force the root wider than the logical viewport")
	main._restart_run()
	await process_frame
	var first_random_seed: int = main.run_model.seed_value
	main._restart_run()
	await process_frame
	var second_random_seed: int = main.run_model.seed_value
	_expect(first_random_seed != second_random_seed, "连续新远征使用不同运行时随机 seed")
	main._start_new_run_with_seed(73103)
	await process_frame
	_expect(main.run_model.seed_value == 73103, "测试可用固定 seed 精确复现")
	_expect(not main.is_test_mode, "main route is separate from test mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MIN, "main route begins at first path node")
	_expect(FileAccess.file_exists(save_path), "开始新远征立即写入战斗外检查点")
	main._show_main_menu()
	await process_frame
	_expect(_find_button_with_text(main.screen_root, "继续远征") != null, "有效存档在标题页显示继续远征")
	_expect(_tree_contains_text(main.screen_root, main.run_model.get_summary_text()), "有效存档在标题页显示摘要")
	main.run_model.player_hp = 1
	main._continue_run()
	await process_frame
	_expect(main.ui_mode == &"map" and main.run_model.player_hp == main.run_model.player_max_hp, "继续远征加载存档并回到地图")
	for stage: int in range(1, CombatModel.TUTORIAL_STAGE_MAX + 1):
		var model: CombatModel = CombatModel.new()
		model.start_battle(73103, stage)
		_expect(not model.tutorial_stage_title.contains("教学"), "path %d title is diegetic" % stage)
		_expect(not model.tutorial_hint.contains("教学"), "path %d context text is diegetic" % stage)

	await _test_expedition_ui(main)
	await _test_event_selection_and_event_battle_ui(main)
	await _test_relic_ui(main)

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

	var corrupt_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken save")
	corrupt_file.close()
	main._show_main_menu()
	await process_frame
	_expect(_tree_contains_text(main.screen_root, "存档不可用"), "损坏存档在标题页显示原因")
	_expect(_find_button_with_text(main.screen_root, "删除损坏存档") != null, "损坏存档标题页显示删除按钮")
	_expect(_find_button_with_text(main.screen_root, "开始新远征") != null, "损坏存档不阻止新游戏")
	main._delete_save_and_refresh()
	await process_frame
	_expect(not FileAccess.file_exists(save_path), "标题页可删除损坏存档")

	main.queue_free()
	save_manager.delete()
	profile_manager.delete()
	if failures == 0:
		print("PASS: main route and test-level flow checks")
		quit(0)
	else:
		push_error("FAIL: %d flow checks failed" % failures)
		quit(1)


func _test_profile_archive_ui(main, profile_manager: ProfileManager) -> void:
	main._show_profile_archive()
	await process_frame
	_expect(_tree_contains_text(main.screen_root, "断句"), "U0 图鉴显示已解锁卡完整名称")
	_expect(_tree_contains_text(main.screen_root, "未识别残页") and not _tree_contains_text(main.screen_root, "第十种答案"), "U0 图鉴隐藏未解锁卡名称与正文")
	var profile: Dictionary = ProfileManager.default_profile()
	profile["unlock_tier"] = 3
	profile["wins"] = 3
	profile_manager.save_profile(profile)
	main._show_profile_archive()
	await process_frame
	_expect(_tree_contains_text(main.screen_root, "第十种答案") and _tree_contains_text(main.screen_root, "回声室"), "U3 图鉴显示新卡完整内容")
	profile_manager.save_profile(ProfileManager.default_profile())
	main._show_main_menu()
	await process_frame


func _test_expedition_ui(main) -> void:
	_expect(main.ui_mode == &"map", "starting a run opens the nine-depth map UI")
	_expect(main.run_model.available_node_ids == main.run_model.map_graph.start_node_ids, "map UI begins with exactly the legal seeded start nodes")
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
	_expect(main.ui_mode == &"map" and main.run_model.available_node_ids == main.run_model.map_graph.get_node(&"d01_00").connections, "reward completion returns to the map and opens seeded successors")

	_force_available(main, &"d02_01")
	main._on_map_node_pressed(&"d02_01")
	await process_frame
	_expect(main.ui_mode == &"event", "event node opens the event UI")
	main._on_event_choice(0)
	await process_frame
	_expect(main.ui_mode == &"event_outcome", "event choice completes into an outcome screen")
	main._show_map_screen()
	await process_frame
	_expect(main.run_model.available_node_ids == main.run_model.map_graph.get_node(&"d02_01").connections, "event outcome returns to the seeded legal successors")

	_force_available(main, &"d03_00")
	main._on_map_node_pressed(&"d03_00")
	await process_frame
	_expect(main.ui_mode == &"rest", "REST node opens heal/upgrade/skip choices")
	main._on_rest_skip_pressed()
	await process_frame
	_expect(main.ui_mode == &"map", "skipping REST returns to the map")

	_force_available(main, &"d04_01")
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

	_force_available(main, &"d05_00")
	main._on_map_node_pressed(&"d05_00")
	await process_frame
	_expect(main.ui_mode == &"event", "second event node is wired through the same map protocol")
	main._on_event_choice(0)
	await process_frame
	main._show_map_screen()
	await process_frame

	_force_available(main, &"d06_01")
	main._on_map_node_pressed(&"d06_01")
	await process_frame
	_expect(main.ui_mode == &"forge", "forge node opens instance upgrade selection")
	var forge_candidates: Array[Dictionary] = main.run_model.get_unupgraded_instances()
	var forge_id: int = int(forge_candidates[0][&"instance_id"])
	main._on_upgrade_instance_pressed(forge_id, &"forge")
	await process_frame
	_expect(main.ui_mode == &"map", "forge upgrade completes and returns to map")
	_expect(main.run_model.get_deck_instance(forge_id)[&"upgrade_id"] != &"", "forge UI upgrades the selected stable instance")

	_force_available(main, &"d07_00")
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
	var expected_rest_hp: int = mini(
		main.run_model.player_max_hp,
		40 + maxi(1, floori(float(main.run_model.player_max_hp) * 0.2))
	)
	_force_available(main, &"d08_00")
	main._on_map_node_pressed(&"d08_00")
	await process_frame
	_expect(main.ui_mode == &"rest", "pre-Boss REST node opens correctly")
	main._on_rest_heal_pressed()
	await process_frame
	_expect(main.run_model.player_hp == expected_rest_hp and main.ui_mode == &"map", "REST heal applies 20 percent and returns to map")

	_force_available(main, &"d09_00")
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
	_expect(not FileAccess.file_exists(main.save_manager.save_path), "Boss结算后删除远征存档")
	_expect(main.run_model.map_graph.get_node(&"d09_00").completed, "formal Boss can only be completed once through the node protocol")
	_expect(main.run_model.evidence.has("第十份校准记录"), "hidden Boss ending reaches RunModel evidence")
	_expect(_tree_contains_text(main.screen_root, "本局新解锁卡牌") and _tree_contains_text(main.screen_root, "第十种答案"), "结算页展示本局推进产生的新解锁")


func _test_event_selection_and_event_battle_ui(main) -> void:
	main._restart_run()
	await process_frame
	var event_node_ids: Array[StringName] = [&"d02_01"]
	main.run_model.available_node_ids = event_node_ids
	main._on_map_node_pressed(&"d02_01")
	await process_frame
	main.run_model.selected_event_id = &"speaking_for_you"
	main._show_event_screen()
	await process_frame
	main._on_event_choice(2)
	await process_frame
	_expect(main.ui_mode == &"event_selection", "event card removal opens the rule-layer instance selection page")
	_expect(_tree_contains_text(main.screen_root, "基础攻击或防御牌"), "event selection displays the rule-layer prompt")
	main._on_event_selection_cancelled()
	await process_frame
	_expect(main.ui_mode == &"event" and main.run_model.pending_event_selection.is_empty(), "event selection cancel returns without mutating the deck")
	main._on_event_choice(2)
	await process_frame
	var chosen_id: int = int(main.run_model.get_pending_event_candidates()[0][&"instance_id"])
	main._on_event_selection_confirmed(chosen_id)
	await process_frame
	_expect(main.ui_mode == &"event_outcome" and not main.run_model.has_deck_instance(chosen_id), "event selection confirms through RunModel and returns to outcome")

	main._restart_run()
	await process_frame
	event_node_ids = [&"d02_01"]
	main.run_model.available_node_ids = event_node_ids
	main._on_map_node_pressed(&"d02_01")
	await process_frame
	main.run_model.selected_event_id = &"definition_tax"
	main._show_event_screen()
	await process_frame
	main._on_event_choice(3)
	await process_frame
	_expect(main.ui_mode == &"combat" and main.model.enemy_id == &"reinforced_word_eater", "definition refusal launches the single reinforced event enemy")
	main.model.battle_over = true
	main.model.victory = true
	main._on_battle_result_pressed()
	await process_frame
	_expect(main.ui_mode == &"event_outcome" and main.run_model.relics.has(&"wordless_bookplate"), "event combat victory grants reward and returns to event outcome")
	_expect(main.run_model.map_graph.get_node(&"d02_01").completed, "event combat completes its map node exactly once")

	main.run_model.selected_event_id = &"calibration_station"
	main.run_model.event_resolved = false
	main.run_model.apply_event_choice(1)
	main._show_archive_screen(&"evidence")
	await process_frame
	_expect(_tree_contains_text(main.screen_root, "来源：随机事件：校准站"), "archive renders structured evidence source")
	_expect(_tree_contains_text(main.screen_root, "可替换资产"), "archive renders structured evidence description")


func _test_relic_ui(main) -> void:
	main._restart_run()
	await process_frame
	main.run_model.relics = RelicCatalog.get_all_ids()
	main._show_archive_screen(&"relics")
	await process_frame
	for relic_id: StringName in RelicCatalog.get_all_ids():
		var definition: Dictionary = RelicCatalog.get_definition(relic_id)
		_expect(_tree_contains_text(main.screen_root, str(definition[&"title"])), "relic archive shows %s title" % relic_id)
		_expect(_tree_contains_text(main.screen_root, "完整效果：%s" % definition[&"description"]), "relic archive shows %s full effect" % relic_id)
		_expect(_tree_contains_text(main.screen_root, "风味：%s" % definition[&"flavor"]), "relic archive shows %s flavor" % relic_id)
	_expect(_tree_contains_text(main.screen_root, "可能仍被后续裂解杀死"), "return bell archive warning is explicit")

	main._start_new_run_with_seed(73103)
	await process_frame
	main.run_model.relics.append(&"seventh_dock_stamp")
	var shop_node: MapNode = _first_node_of_type(main.run_model.map_graph, MapNode.NodeType.SHOP)
	_expect(shop_node != null, "deterministic replay map contains a shop")
	var shop_ids: Array[StringName] = [shop_node.id]
	main.run_model.available_node_ids = shop_ids
	shop_node.revealed = true
	shop_node.reachable = true
	main._on_map_node_pressed(shop_node.id)
	await process_frame
	var shop_digest: String = ShopCatalog.digest(main.run_model.pending_shop_stock)
	_expect(_find_button_with_text(main.screen_root, "查看旧档案") != null, "dock stamp exposes the old archive action in shop UI")
	main._show_shop_archive()
	await process_frame
	_expect(main.ui_mode == &"shop_archive" and _tree_contains_text(main.screen_root, "第七码头旧档案"), "shop old archive opens from the stamp action")
	_expect(_tree_contains_text(main.screen_root, "‘自愿’一词使用另一种墨水统一补录"), "shop old archive renders its full record")
	_expect(ShopCatalog.digest(main.run_model.pending_shop_stock) == shop_digest, "shop old archive leaves frozen stock unchanged")

	main._restart_run()
	await process_frame
	var elite_ids: Array[StringName] = [&"d06_00"]
	main.run_model.available_node_ids = elite_ids
	var elite_node: MapNode = main.run_model.map_graph.get_node(&"d06_00")
	elite_node.revealed = true
	elite_node.reachable = true
	main._on_map_node_pressed(&"d06_00")
	await process_frame
	main.model.battle_over = true
	main.model.victory = true
	main._on_battle_result_pressed()
	await process_frame
	var pending: Dictionary = main.run_model.get_pending_elite_reward()
	var pending_relic: StringName = pending.get(&"relic_id", &"") as StringName
	_expect(main.ui_mode == &"reward" and _find_named(main.screen_root, "EliteRelicReward") != null, "elite victory opens the dedicated relic reward panel")
	_expect(_tree_contains_text(main.screen_root, "精英卡池保证至少 1 张罕见"), "elite reward UI explains its rare-card guarantee")
	_expect(_tree_contains_text(main.screen_root, "选择或跳过卡牌后领取"), "elite reward UI explains delayed relic settlement")
	_expect(pending_relic != &"" and not main.run_model.relics.has(pending_relic), "elite UI keeps the relic pending before card resolution")
	main._on_reward_skipped()
	await process_frame
	_expect(main.run_model.relics.count(pending_relic) == 1, "elite UI skip settles the relic once")
	_expect(elite_node.completed and not main.run_model.complete_current_node(), "elite UI completes its node exactly once")

	main.is_test_mode = true
	main.run_model = RunModel.new()
	main.run_model.start_run(73103)
	main.run_model.relics = RelicCatalog.get_all_ids()
	main.current_stage = CombatModel.TUTORIAL_STAGE_MAX
	main._start_current_battle()
	await process_frame
	var relic_hud: RichTextLabel = _find_named(main.screen_root, "RelicHUD") as RichTextLabel
	_expect(relic_hud != null, "combat creates RelicHUD")
	if relic_hud != null:
		for relic_id: StringName in RelicCatalog.get_all_ids():
			_expect(relic_hud.text.contains(str(RelicCatalog.get_definition(relic_id)[&"title"])), "RelicHUD shows %s" % relic_id)
		_expect(relic_hud.text.contains("本场触发 0"), "RelicHUD shows live trigger counts")
		_expect(relic_hud.text.contains("可能仍被后续裂解杀死"), "RelicHUD keeps the return bell death warning explicit")


func _force_available(main, node_id: StringName) -> void:
	var forced: Array[StringName] = [node_id]
	main.run_model.available_node_ids = forced
	for raw_node: Variant in main.run_model.map_graph.nodes_by_id.values():
		(raw_node as MapNode).reachable = false
	var node: MapNode = main.run_model.map_graph.get_node(node_id)
	node.revealed = true
	node.reachable = true


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


func _find_button_with_text(node: Node, fragment: String) -> Button:
	if node is Button and (node as Button).text.contains(fragment):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button_with_text(child, fragment)
		if found != null:
			return found
	return null


func _first_node_of_type(graph: MapGraph, node_type: MapNode.NodeType) -> MapNode:
	for raw_node: Variant in graph.nodes_by_id.values():
		var node: MapNode = raw_node as MapNode
		if node.node_type == node_type:
			return node
	return null


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
