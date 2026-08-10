extends SceneTree

var failures: int = 0
var main: Control
var save_manager: SaveManager


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_path: String = "user://broken_ring_accessibility_test_%d.json" % OS.get_process_id()
	save_manager = SaveManager.new(save_path)
	save_manager.delete()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_manager = save_manager
	root.add_child(main)
	await process_frame
	await _check_page("menu")

	main._restart_run()
	await _check_page("map")
	main._show_deck_screen()
	await _check_page("deck")

	main.run_model.current_node_id = &"d04_01"
	main.run_model.pending_shop_stock = ShopCatalog.generate(73103, 0, main.run_model.relics)
	main._show_shop_screen()
	await _check_page("shop")

	main._show_upgrade_screen(&"forge")
	await _check_page("upgrade")

	main.run_model.selected_event_id = &"authorless_book"
	main.run_model.event_resolved = false
	main._show_event_screen()
	await _check_page("event")

	var reward_ids: Array[StringName] = [&"critical_permission", &"blank_space", &"rift_slash"]
	main.run_model.pending_reward_ids = reward_ids
	main._show_reward_screen()
	await _check_page("reward")

	main.is_test_mode = true
	main.run_model = RunModel.new()
	main.run_model.start_run(73103)
	main.current_stage = 6
	main._start_current_battle()
	await _check_page("combat")
	await _check_combat_escape_routes()
	await _check_event_escape_route()

	save_manager.delete()
	main.queue_free()
	if failures == 0:
		print("PASS: 键盘焦点、禁用原因与 Escape 取消路由通过")
		quit(0)
	else:
		push_error("FAIL: %d 项无障碍检查未通过" % failures)
		quit(1)


func _check_page(label: String) -> void:
	await process_frame
	var buttons: Array[Button] = []
	_collect_buttons(main.screen_root, buttons)
	var focusable: Array[Button] = []
	for button: Button in buttons:
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			focusable.append(button)
	_expect(not focusable.is_empty(), "%s 至少有一个可见可聚焦按钮" % label)
	var focus_owner: Control = root.gui_get_focus_owner()
	_expect(
		focus_owner != null
		and main.screen_root.is_ancestor_of(focus_owner)
		and focus_owner.is_visible_in_tree()
		and focus_owner.focus_mode != Control.FOCUS_NONE,
		"%s 打开后焦点落在当前页面有效控件" % label
	)
	for button: Button in buttons:
		if button.is_visible_in_tree() and button.disabled:
			_expect(not button.tooltip_text.strip_edges().is_empty(), "%s 禁用按钮“%s”提供原因" % [label, button.text.get_slice("\n", 0)])


func _check_combat_escape_routes() -> void:
	var model: CombatModel = main.model
	model.hand.clear()
	model.draw_pile.clear()
	model.discard_pile.clear()
	model.hand.append(CardCatalog.create_card(&"index_reorder", 9001))
	model.draw_pile.append(CardCatalog.create_card(&"calibration_strike", 9002))
	model.draw_pile.append(CardCatalog.create_card(&"temporary_guard", 9003))
	model.draw_pile.append(CardCatalog.create_card(&"aftershock", 9004))
	model.energy = 3
	model.play_card(0)
	main._refresh_combat()
	await process_frame
	_expect(model.has_pending_selection(), "战斗选择模式已建立")
	var paid_energy: int = model.energy
	_push_escape()
	await process_frame
	_expect(not model.has_pending_selection(), "战斗选择按 Escape 取消")
	_expect(model.hand.size() == 1 and model.hand[0].id == &"index_reorder", "战斗 Escape 取消后卡牌回到手牌")
	_expect(model.energy == paid_energy + 0, "战斗 Escape 取消返还零费牌费用")
	_expect(main.ui_mode == &"combat", "战斗选择取消后仍留在战斗")

	var turn_before: int = model.turn_number
	var hp_before: int = model.player_hp
	_push_escape()
	await process_frame
	_expect(main.ui_mode == &"combat" and model.turn_number == turn_before and model.player_hp == hp_before, "战斗普通状态按 Escape 不退出也不推进规则")
	_expect(is_instance_valid(main) and main.is_inside_tree(), "战斗 Escape 不触发系统退出")

	model.energy = 0
	main._refresh_combat()
	await process_frame
	var buttons: Array[Button] = []
	_collect_buttons(main.screen_root, buttons)
	for button: Button in buttons:
		if button.is_visible_in_tree() and button.disabled:
			_expect(not button.tooltip_text.strip_edges().is_empty(), "combat 禁用按钮“%s”提供原因" % button.text.get_slice("\n", 0))


func _check_event_escape_route() -> void:
	main.is_test_mode = false
	main.run_model = RunModel.new()
	main.run_model.start_run(73103)
	main.run_model.selected_event_id = &"deleted_funeral"
	main.run_model.event_resolved = false
	_expect(main.run_model.apply_event_choice(1), "事件牌选择已建立")
	main._show_event_selection_screen()
	await process_frame
	_expect(not main.run_model.pending_event_selection.is_empty(), "事件选择模式保持待选状态")
	_push_escape()
	await process_frame
	_expect(main.run_model.pending_event_selection.is_empty(), "事件选择按 Escape 取消")
	_expect(main.ui_mode == &"event", "事件 Escape 取消后返回事件页面")
	_expect(not main.run_model.event_resolved, "事件 Escape 取消不结算事件")


func _push_escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)


func _collect_buttons(node: Node, result: Array[Button]) -> void:
	if node is Button:
		result.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, result)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
