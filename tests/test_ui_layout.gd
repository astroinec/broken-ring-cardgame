extends SceneTree

var failures: int = 0
var main: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main._restart_run()
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

	main._show_archive_screen(&"evidence")
	await process_frame
	_check_current_page("archive", true, true)
	_expect(_find_named(main.screen_root, "ArchiveContent") != null, "archive combines run state, relics and evidence")

	main.run_model.pending_shop_stock = ShopCatalog.generate(73103, main.run_model.shop_remove_count)
	main._show_shop_screen()
	await process_frame
	_check_current_page("shop", true, true)
	_expect(_scroll_has_overflow("ShopContent"), "shop removal list scrolls for a long deck")
	_expect(_find_button_with_text(main.screen_root, "离开商店") != null, "shop leave action remains visible")

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

	var reward_ids: Array[StringName] = [&"broken_sentence", &"blank_space", &"rift_slash"]
	main.run_model.pending_reward_ids = reward_ids
	main._show_reward_screen()
	await process_frame
	_check_current_page("reward", true, true)
	_expect(_find_button_with_text(main.screen_root, "跳过奖励") != null, "reward skip remains visible")

	main.run_model.selected_event_id = &"authorless_book"
	main.run_model.event_resolved = false
	main._show_event_screen()
	await process_frame
	_check_current_page("event", true, true)
	_expect(_find_named(main.screen_root, "EventContent") != null, "event story and options use scrollable content")

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
	_expect(main.page != null, "combat page exists")
	_expect(main.screen_root.size.x <= 1280.0, "combat does not widen root beyond logical viewport")
	_expect(main.page.get_combined_minimum_size().x <= 1240.0, "combat layout minimum width fits viewport")

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


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
