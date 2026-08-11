extends SceneTree

var failures: int = 0
var main: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var suffix: String = "%d" % OS.get_process_id()
	var save_path: String = "user://broken_ring_ui_layout_test_%s.json" % suffix
	var profile_path: String = "user://broken_ring_ui_layout_profile_test_%s.json" % suffix
	var save_manager: SaveManager = SaveManager.new(save_path)
	var profile_manager: ProfileManager = ProfileManager.new(profile_path)
	save_manager.delete()
	profile_manager.delete()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_manager = save_manager
	main.profile_manager = profile_manager
	root.add_child(main)
	await process_frame
	main._start_new_run_with_seed(73103)
	await process_frame
	main._show_main_menu()
	await process_frame
	_check_current_page("valid save menu", false, false)
	_expect(_find_button_with_text(main.screen_root, "继续远征") != null, "有效存档菜单保留继续按钮")
	_expect(_tree_contains_text(main.screen_root, "远征存档"), "有效存档菜单摘要可见")
	main._continue_run()
	await process_frame

	_check_current_page("map", true, true)
	_expect(_find_named(main.screen_root, "RunStatus") != null, "map keeps a visible run-status panel")
	_expect(_find_button_with_text(main.screen_root, "查看牌组") != null, "map exposes deck inspection")
	_expect(_find_button_with_text(main.screen_root, "查看遗物") != null, "map exposes relic inspection")
	_expect(_find_button_with_text(main.screen_root, "查看证据") != null, "map exposes evidence inspection")

	_add_long_deck(35)
	main._show_deck_screen()
	await process_frame
	_check_current_page("deck", true, true)
	var deck_list: Control = _find_named(main.screen_root, "DeckList") as Control
	_expect(deck_list != null and deck_list.get_child_count() >= 35, "deck view renders every instance in the long test deck")
	_expect(_scroll_has_overflow("DeckList"), "long deck view scrolls instead of hiding cards")
	_expect(_find_button_with_text(main.screen_root, "返回地图") != null, "deck return action remains visible")

	main.run_model.selected_event_id = &"calibration_station"
	main.run_model.event_resolved = false
	main.run_model.apply_event_choice(1)
	main.run_model.relics = RelicCatalog.get_all_ids()
	main._show_archive_screen(&"evidence")
	await process_frame
	_check_current_page("archive", true, true)
	_expect(_find_named(main.screen_root, "ArchiveContent") != null, "archive combines run state, relics and evidence")
	_expect(_tree_contains_text(main.screen_root, "来源：随机事件：校准站"), "archive shows evidence source in the responsive scroll page")
	_expect(_tree_contains_text(main.screen_root, "可替换资产"), "archive shows evidence description in the responsive scroll page")
	for relic_id: StringName in RelicCatalog.get_all_ids():
		var definition: Dictionary = RelicCatalog.get_definition(relic_id)
		_expect(_find_named(main.screen_root, "Relic_%s" % relic_id) != null, "archive lays out relic panel %s" % relic_id)
		_expect(_tree_contains_text(main.screen_root, "完整效果：%s" % definition[&"description"]), "archive lays out full effect for %s" % relic_id)
		_expect(_tree_contains_text(main.screen_root, "风味：%s" % definition[&"flavor"]), "archive lays out flavor for %s" % relic_id)
	_expect(_scroll_has_overflow("ArchiveContent"), "complete eight-relic archive scrolls instead of clipping")
	_expect(_tree_contains_text(main.screen_root, "可能仍被后续裂解杀死"), "return bell warning remains visible in archive layout")

	main.run_model.current_node_id = &"d04_01"
	main.run_model.pending_shop_stock = ShopCatalog.generate(73103, main.run_model.shop_remove_count, main.run_model.relics)
	main._show_shop_screen()
	await process_frame
	_check_current_page("shop", true, true)
	_expect(_scroll_has_overflow("ShopContent"), "shop removal list scrolls for a long deck")
	_expect(_find_button_with_text(main.screen_root, "离开商店") != null, "shop leave action remains visible")
	_expect(_find_button_with_text(main.screen_root, "查看旧档案") != null, "shop layout keeps the old archive action visible")
	var shop_digest: String = ShopCatalog.digest(main.run_model.pending_shop_stock)
	main._show_shop_archive()
	await process_frame
	_check_current_page("shop archive", true, true)
	_expect(_find_named(main.screen_root, "ShopArchiveContent") != null, "shop old archive uses scrollable content")
	_expect(_tree_contains_text(main.screen_root, "‘自愿’一词使用另一种墨水统一补录"), "shop old archive body is visible")
	_expect(_find_button_with_text(main.screen_root, "返回商店（库存未变化）") != null, "shop archive return action states stock safety")
	_expect(ShopCatalog.digest(main.run_model.pending_shop_stock) == shop_digest, "shop archive layout does not mutate stock")

	main._show_upgrade_screen(&"forge")
	await process_frame
	_check_current_page("forge", true, true)
	var upgrade_list: Control = _find_named(main.screen_root, "UpgradeList") as Control
	_expect(upgrade_list != null and upgrade_list.get_child_count() >= 20, "upgrade view renders all eligible instances")
	_expect(_scroll_has_overflow("UpgradeList"), "upgrade candidates scroll instead of being clipped")
	_expect(_find_button_with_text(main.screen_root, "跳过") != null, "upgrade skip action remains visible")

	main._show_rest_screen()
	await process_frame
	_check_current_page("rest", true, true)

	var reward_ids: Array[StringName] = [&"critical_permission", &"blank_space", &"rift_slash"]
	main.run_model.pending_reward_ids = reward_ids
	main.run_model.pending_node_resolution = {
		&"pending_elite_relic_id": &"blank_epitaph",
		&"battle_won": true,
		&"reward_settled": true,
		&"resolved": false,
	}
	main._show_reward_screen()
	await process_frame
	_check_current_page("reward", true, true)
	_expect(_find_button_with_text(main.screen_root, "跳过奖励") != null, "reward skip remains visible")
	_expect(_find_named(main.screen_root, "EliteRelicReward") != null, "elite relic reward panel fits the reward scroll page")
	_expect(_tree_contains_text(main.screen_root, "选择或跳过卡牌后领取"), "elite reward panel keeps delayed settlement text visible")
	_expect(_tree_contains_text(main.screen_root, "精英卡池保证至少 1 张罕见"), "elite reward header keeps rare-card guarantee visible")

	main.run_model.selected_event_id = &"authorless_book"
	main.run_model.event_resolved = false
	main._show_event_screen()
	await process_frame
	_check_current_page("event", true, true)
	_expect(_find_named(main.screen_root, "EventContent") != null, "event story and options use scrollable content")

	main.run_model.selected_event_id = &"deleted_funeral"
	main.run_model.event_resolved = false
	main.run_model.apply_event_choice(1)
	main._show_event_selection_screen()
	await process_frame
	_check_current_page("event selection", true, true)
	_expect(_find_named(main.screen_root, "EventSelectionList") != null, "event instance selection uses scrollable content")
	_expect(_scroll_has_overflow("EventSelectionList"), "long event instance selection scrolls instead of clipping")
	_expect(_find_button_with_text(main.screen_root, "取消选择") != null, "event selection cancel remains visible in fixed footer")

	main.model = CombatModel.new()
	var no_bonus: Array[StringName] = []
	var no_relics: Array[StringName] = []
	main.model.start_battle(73103, 6, no_bonus, &"name_eraser", no_relics)
	main.model.boss_phase = 2
	main.model.boss_recovery_count = 2
	main.model._enter_boss_terminal()
	main._show_boss_terminal_screen()
	await process_frame
	_check_current_page("boss terminal", true, true)
	_expect(_find_named(main.screen_root, "BossTerminalContent") != null, "Boss terminal options use scrollable content")
	_expect(_find_button_with_text(main.screen_root, "读取被删原文") != null, "Boss terminal keeps the hidden option visible")

	main.run_model.boss_ending_id = &"read_original"
	main.run_model.boss_ending_text = "测试结算文本。"
	main.run_model.run_completed = true
	main._show_expedition_complete_screen()
	await process_frame
	_check_current_page("expedition complete", true, true)

	main._show_test_arena_menu()
	await process_frame
	_check_current_page("test arena menu", false, false)

	main._start_test_level()
	await process_frame
	var all_relics: Array[StringName] = RelicCatalog.get_all_ids()
	var relic_bonus_cards: Array[StringName] = []
	main.model.start_battle(73109, CombatModel.TUTORIAL_STAGE_MAX, relic_bonus_cards, &"pressure_archivist", all_relics)
	main._refresh_combat()
	await process_frame
	_expect(main.page != null, "combat page exists")
	_expect(main.screen_root.size.x <= 1280.0, "combat does not widen root beyond logical viewport")
	_expect(main.page.get_combined_minimum_size().x <= 1240.0, "combat layout minimum width fits viewport")
	var relic_hud: RichTextLabel = _find_named(main.screen_root, "RelicHUD") as RichTextLabel
	_expect(relic_hud != null, "combat layout includes RelicHUD")
	if relic_hud != null:
		_expect(relic_hud.text.contains("本场触发 0"), "RelicHUD exposes live trigger counts")
		for relic_id: StringName in all_relics:
			_expect(relic_hud.text.contains(str(RelicCatalog.get_definition(relic_id)[&"title"])), "RelicHUD lays out %s" % relic_id)
		_expect(relic_hud.text.contains("可能仍被后续裂解杀死"), "RelicHUD keeps explicit return bell warning")

	# 回归用户实测：删名者第二阶段长意图+全部遗物+0稳定度时，底部结束回合曾被挤出720视口。
	main.is_test_mode = false
	main.model.start_battle(73109, CombatModel.TUTORIAL_STAGE_MAX, relic_bonus_cards, &"name_eraser", all_relics)
	main.model.boss_phase = 2
	main.model.enemy_intent_index = 2
	main.model.enemy_hp = 54
	main.model.player_hp = 8
	main.model.energy = 0
	main.model.boss_strength = 6
	main.model.missing_name[CardData.CardType.LAW] = 3
	for card: CardData in main.model.hand:
		if card.card_type != CardData.CardType.STATUS:
			main.model.boss_deleted_types[card.instance_id] = {&"order": card.instance_id}
		var keywords: Array[StringName] = main.model.get_card_keywords(card)
		if not keywords.is_empty():
			main.model.boss_deleted_keywords[card.instance_id] = {&"order": card.instance_id, &"keywords": keywords}
	main._refresh_combat()
	await process_frame
	var combat_footer: Control = _find_named(main.screen_root, "CombatFooter") as Control
	var end_turn: Button = _find_named(main.screen_root, "EndTurnButton") as Button
	_expect(main.screen_root.size.y <= 720.0, "Boss long-intent layout does not heighten root beyond logical viewport")
	_expect(main.page.get_combined_minimum_size().y <= 668.0, "worst-case Boss combat page keeps at least 28 vertical safety pixels")
	_expect(combat_footer != null and combat_footer.position.y + combat_footer.size.y <= main.page.size.y + 0.5, "Boss combat footer remains inside viewport")
	_expect(end_turn != null and end_turn.visible and not end_turn.disabled, "zero-energy Boss state keeps End Turn visible and enabled")
	_expect(_tree_contains_text(main.screen_root, "无可打出的牌｜请结束回合"), "zero-energy state explains why cards are disabled")
	if main.hand_box.get_child_count() > 0:
		var disabled_card: Button = main.hand_box.get_child(0) as Button
		_expect(disabled_card.disabled and disabled_card.tooltip_text.contains("稳定度不足"), "disabled card exposes its exact energy reason")

	var corrupt_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken save")
	corrupt_file.close()
	main._show_main_menu()
	await process_frame
	_check_current_page("corrupt save menu", false, false)
	_expect(_tree_contains_text(main.screen_root, "存档不可用"), "损坏存档原因在紧凑标题页可见")
	_expect(_find_button_with_text(main.screen_root, "删除损坏存档") != null, "损坏存档删除操作在标题页可见")
	_expect(_find_button_with_text(main.screen_root, "开始新远征") != null, "损坏存档下新游戏操作仍可见")
	save_manager.delete()

	main.queue_free()
	if failures == 0:
		print("PASS: all responsive UI layout checks")
		quit(0)
	else:
		push_error("FAIL: %d responsive UI layout checks failed" % failures)
		quit(1)


func _add_long_deck(target_size: int) -> void:
	var ids: Array[StringName] = CardCatalog.REWARD_IDS
	var index: int = 0
	while main.run_model.deck_instances.size() < target_size:
		main.run_model.add_card_instance(ids[index % ids.size()])
		index += 1


func _check_current_page(label: String, expect_scroll: bool, expect_footer: bool) -> void:
	var page: Control = _find_named(main.screen_root, "Page") as Control
	_expect(page != null, "%s uses shared page container" % label)
	if page == null:
		return
	_expect(page.get_combined_minimum_size().x <= 1240.0, "%s minimum width fits viewport margins" % label)
	_expect(main.screen_root.size.x <= 1280.0, "%s does not widen root beyond logical viewport" % label)
	if expect_scroll:
		_expect(_find_named(page, "PageScroll") != null, "%s has a vertical scroll region" % label)
	if expect_footer:
		var footer: Control = _find_named(page, "PageFooter") as Control
		_expect(footer != null, "%s has a fixed footer" % label)
		if footer != null:
			_expect(footer.position.y + footer.size.y <= page.size.y + 0.5, "%s footer remains inside viewport" % label)
			var bottom_gap: float = page.size.y - (footer.position.y + footer.size.y)
			_expect(bottom_gap >= 12.0, "%s footer keeps at least 12 vertical safety pixels" % label)
		var safety: Control = _find_named(page, "PageBottomSafety") as Control
		_expect(safety != null and safety.custom_minimum_size.y >= 12.0, "%s declares a 12-pixel bottom safety spacer" % label)


func _scroll_has_overflow(content_name: String) -> bool:
	var content: Control = _find_named(main.screen_root, content_name) as Control
	var scroll: ScrollContainer = _find_named(main.screen_root, "PageScroll") as ScrollContainer
	if content == null or scroll == null:
		return false
	return content.get_combined_minimum_size().y > scroll.size.y


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
