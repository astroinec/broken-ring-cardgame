extends Control


const CombatModelScript: Script = preload("res://scripts/core/combat_model.gd")
const RunModelScript: Script = preload("res://scripts/core/run_model.gd")

var model: CombatModel
var run_model: RunModel
var current_stage: int = CombatModel.TUTORIAL_STAGE_MIN
var is_test_mode: bool = false
var ui_mode: StringName = &"menu"
## 机制测试场当前选定的对手；主线节点始终使用路径目录中的敌人。
var test_arena_enemy_id: StringName = EnemyCatalog.TEST_ARENA_ENEMY_IDS[0]
var screen_root: MarginContainer
var page: VBoxContainer
var hand_box: HBoxContainer
var log_view: RichTextLabel
var result_label: Label
var result_action_button: Button
var end_turn_button: Button


func _ready() -> void:
	_configure_chinese_font()
	_build_shell()
	_show_main_menu()


func _configure_chinese_font() -> void:
	var chinese_font: Font = load("res://assets/fonts/NotoSansSC-Variable.ttf") as Font
	if chinese_font == null:
		push_warning("未能加载项目内置中文字体，将使用Godot默认字体回退。")
		return
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = chinese_font
	ui_theme.default_font_size = 18
	theme = ui_theme


func _build_shell() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("111722")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	screen_root = MarginContainer.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_theme_constant_override("margin_left", 20)
	screen_root.add_theme_constant_override("margin_top", 12)
	screen_root.add_theme_constant_override("margin_right", 20)
	screen_root.add_theme_constant_override("margin_bottom", 12)
	add_child(screen_root)


func _clear_screen() -> void:
	for child: Node in screen_root.get_children():
		screen_root.remove_child(child)
		child.queue_free()


func _show_main_menu() -> void:
	ui_mode = &"menu"
	is_test_mode = false
	_clear_screen()
	var menu: VBoxContainer = VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 22)
	screen_root.add_child(menu)
	_add_page_title(menu, "断环", "无字之城 / 序章原型")
	var premise: Label = Label.new()
	premise.text = "第七名回收者在码头醒来。机构要求你进入正在坍缩的无字之城，取回一枚“定义律印”。\n墙上的返航名单被墨迹覆盖；最下面一行，像是你自己的笔迹。"
	premise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	premise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	premise.add_theme_font_size_override("font_size", 21)
	premise.add_theme_color_override("font_color", Color("d8e0e7"))
	menu.add_child(premise)
	var start_button: Button = Button.new()
	start_button.text = "进入无字之城"
	start_button.custom_minimum_size = Vector2(360, 62)
	start_button.pressed.connect(_restart_run)
	menu.add_child(start_button)
	var test_button: Button = Button.new()
	test_button.text = "机制测试场"
	test_button.custom_minimum_size = Vector2(360, 52)
	test_button.tooltip_text = "独立于主线，集中体验当前已实现的核心牌组机制。"
	test_button.pressed.connect(_show_test_arena_menu)
	menu.add_child(test_button)
	var note: Label = Label.new()
	note.text = "主线机制会随路径、敌人与获得的残页自然出现；测试场不计入故事。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("8295a8"))
	menu.add_child(note)


func _restart_run() -> void:
	is_test_mode = false
	run_model = RunModelScript.new()
	run_model.start_run(RunModel.DEFAULT_SEED)
	current_stage = CombatModel.TUTORIAL_STAGE_MIN
	_show_map_screen()


func _show_map_screen() -> void:
	ui_mode = &"map"
	_clear_screen()
	var map_page: VBoxContainer = VBoxContainer.new()
	map_page.add_theme_constant_override("separation", 10)
	screen_root.add_child(map_page)
	_add_page_title(map_page, "无字之城远征", run_model.get_summary_text())
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_page.add_child(scroll)
	var depths: VBoxContainer = VBoxContainer.new()
	depths.add_theme_constant_override("separation", 8)
	scroll.add_child(depths)
	for depth: int in range(1, 10):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		depths.add_child(row)
		var depth_label: Label = Label.new()
		depth_label.text = "第%d层" % depth
		depth_label.custom_minimum_size = Vector2(90, 48)
		row.add_child(depth_label)
		for node: MapNode in run_model.map_graph.get_nodes_at_depth(depth):
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(270, 48)
			button.text = "%s｜%s%s" % [
				node.id,
				node.type_name() if node.revealed else "未揭示",
				"｜已完成" if node.completed else "",
			]
			button.disabled = not run_model.available_node_ids.has(node.id) or node.completed
			button.tooltip_text = "只能进入当前路线的合法后继。" if button.disabled else "进入该节点"
			button.pressed.connect(_on_map_node_pressed.bind(node.id))
			row.add_child(button)
	var footer: HBoxContainer = HBoxContainer.new()
	map_page.add_child(footer)
	var deck_button: Button = Button.new()
	deck_button.text = "查看牌组实例"
	deck_button.pressed.connect(_show_deck_screen)
	footer.add_child(deck_button)
	var title_button: Button = Button.new()
	title_button.text = "返回标题"
	title_button.pressed.connect(_show_main_menu)
	footer.add_child(title_button)


func _show_deck_screen() -> void:
	ui_mode = &"deck"
	_clear_screen()
	var deck_page: VBoxContainer = VBoxContainer.new()
	deck_page.add_theme_constant_override("separation", 8)
	screen_root.add_child(deck_page)
	_add_page_title(deck_page, "牌组实例", "相同卡牌的每个实例独立保存升级状态。")
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_page.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	scroll.add_child(list)
	for instance: Dictionary in run_model.deck_instances:
		var label: Label = Label.new()
		label.text = run_model.describe_deck_instance(instance)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(label)
	var back: Button = Button.new()
	back.text = "返回地图"
	back.pressed.connect(_show_map_screen)
	deck_page.add_child(back)


func _on_map_node_pressed(node_id: StringName) -> void:
	if not run_model.enter_node(node_id):
		return
	var node: MapNode = run_model.get_current_map_node()
	match node.node_type:
		MapNode.NodeType.BATTLE, MapNode.NodeType.ELITE:
			_start_current_battle()
		MapNode.NodeType.EVENT:
			_show_event_screen()
		MapNode.NodeType.SHOP:
			_show_shop_screen()
		MapNode.NodeType.FORGE:
			_show_forge_screen()
		MapNode.NodeType.REST:
			_show_rest_screen()
		MapNode.NodeType.BOSS:
			_show_boss_placeholder()


func _show_shop_screen() -> void:
	ui_mode = &"shop"
	_clear_screen()
	var shop_page: VBoxContainer = VBoxContainer.new()
	shop_page.add_theme_constant_override("separation", 8)
	screen_root.add_child(shop_page)
	_add_page_title(shop_page, "残页商店", "库存由节点种子冻结；售出不补。墨晶 %d" % run_model.ink_crystals)
	var shop: ShopModel = ShopModel.new(run_model.pending_shop_stock)
	var cards: Array = run_model.pending_shop_stock.get(&"cards", [])
	for index: int in range(cards.size()):
		var item: Dictionary = cards[index]
		var definition: Dictionary = CardCatalog.get_definition(item[&"card_id"] as StringName)
		var reason: String = shop.card_unavailable_reason(run_model, index)
		var button: Button = Button.new()
		button.text = "%s｜%d 墨晶｜%s%s" % [definition[&"title"], item[&"price"], definition[&"description"], "｜不可用：%s" % reason if not reason.is_empty() else ""]
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		button.pressed.connect(_on_shop_card_pressed.bind(index))
		shop_page.add_child(button)
	var relic: Dictionary = run_model.pending_shop_stock.get(&"relic", {})
	var relic_reason: String = shop.relic_unavailable_reason(run_model)
	var relic_button: Button = Button.new()
	relic_button.text = "%s｜%d 墨晶%s" % [RuleEngine.relic_title(relic[&"relic_id"] as StringName), relic[&"price"], "｜不可用：%s" % relic_reason if not relic_reason.is_empty() else ""]
	relic_button.disabled = not relic_reason.is_empty()
	relic_button.tooltip_text = relic_reason
	relic_button.pressed.connect(_on_shop_relic_pressed)
	shop_page.add_child(relic_button)
	var service: Dictionary = run_model.pending_shop_stock.get(&"remove_service", {})
	var remove_reason: String = shop.remove_unavailable_reason(run_model)
	var remove_label: Label = Label.new()
	remove_label.text = "移除服务｜%d 墨晶%s" % [service[&"price"], "｜不可用：%s" % remove_reason if not remove_reason.is_empty() else ""]
	shop_page.add_child(remove_label)
	for instance: Dictionary in run_model.deck_instances:
		var remove_button: Button = Button.new()
		remove_button.text = "移除 %s" % run_model.describe_deck_instance(instance)
		remove_button.disabled = not remove_reason.is_empty()
		remove_button.tooltip_text = remove_reason
		remove_button.pressed.connect(_on_shop_remove_pressed.bind(int(instance[&"instance_id"])))
		shop_page.add_child(remove_button)
	var leave: Button = Button.new()
	leave.text = "离开商店并返回地图"
	leave.pressed.connect(_on_shop_leave_pressed)
	shop_page.add_child(leave)


func _on_shop_card_pressed(index: int) -> void:
	if run_model.buy_shop_card(index):
		_show_shop_screen()


func _on_shop_relic_pressed() -> void:
	if run_model.buy_shop_relic():
		_show_shop_screen()


func _on_shop_remove_pressed(instance_id: int) -> void:
	if run_model.use_shop_remove(instance_id):
		_show_shop_screen()


func _on_shop_leave_pressed() -> void:
	if run_model.finish_shop() and run_model.complete_current_node():
		_show_map_screen()


func _show_forge_screen() -> void:
	_show_upgrade_screen(&"forge")


func _show_rest_upgrade_screen() -> void:
	_show_upgrade_screen(&"rest_upgrade")


func _show_upgrade_screen(mode: StringName) -> void:
	ui_mode = mode
	_clear_screen()
	var upgrade_page: VBoxContainer = VBoxContainer.new()
	upgrade_page.add_theme_constant_override("separation", 8)
	screen_root.add_child(upgrade_page)
	_add_page_title(upgrade_page, "锻造" if mode == &"forge" else "休整：升级", "选择具体未升级实例；每次只升级一张。")
	for instance: Dictionary in run_model.get_unupgraded_instances():
		var preview: Dictionary = run_model.get_upgrade_preview(int(instance[&"instance_id"]))
		var button: Button = Button.new()
		button.text = "#%d %s\n升级前：%s\n升级后：%s" % [instance[&"instance_id"], CardCatalog.get_definition(instance[&"card_id"] as StringName)[&"title"], preview[&"before"], preview[&"after"]]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_upgrade_instance_pressed.bind(int(instance[&"instance_id"]), mode))
		upgrade_page.add_child(button)
	var skip: Button = Button.new()
	skip.text = "没有可升级牌，离开" if run_model.get_unupgraded_instances().is_empty() else "跳过"
	skip.pressed.connect(_on_upgrade_skipped.bind(mode))
	upgrade_page.add_child(skip)


func _on_upgrade_instance_pressed(instance_id: int, mode: StringName) -> void:
	var resolved: bool = run_model.resolve_forge_upgrade(instance_id) if mode == &"forge" else run_model.resolve_rest_upgrade(instance_id)
	if resolved and run_model.complete_current_node():
		_show_map_screen()


func _on_upgrade_skipped(mode: StringName) -> void:
	var resolved: bool = run_model.skip_forge() if mode == &"forge" else run_model.skip_rest()
	if resolved and run_model.complete_current_node():
		_show_map_screen()


func _show_rest_screen() -> void:
	ui_mode = &"rest"
	_clear_screen()
	var rest_page: VBoxContainer = VBoxContainer.new()
	rest_page.alignment = BoxContainer.ALIGNMENT_CENTER
	rest_page.add_theme_constant_override("separation", 14)
	screen_root.add_child(rest_page)
	_add_page_title(rest_page, "休整", "恢复20%最大生命、升级一张牌，或跳过。")
	var heal_amount: int = maxi(1, floori(float(run_model.player_max_hp) * 0.2))
	var heal: Button = Button.new()
	heal.text = "恢复 %d 生命｜当前 %d/%d%s" % [heal_amount, run_model.player_hp, run_model.player_max_hp, "｜不可用：生命已满" if run_model.player_hp >= run_model.player_max_hp else ""]
	heal.disabled = run_model.player_hp >= run_model.player_max_hp
	heal.tooltip_text = "生命已满" if heal.disabled else ""
	heal.pressed.connect(_on_rest_heal_pressed)
	rest_page.add_child(heal)
	var upgrade: Button = Button.new()
	upgrade.text = "升级一张未升级牌%s" % ("｜不可用：没有可升级实例" if run_model.get_unupgraded_instances().is_empty() else "")
	upgrade.disabled = run_model.get_unupgraded_instances().is_empty()
	upgrade.tooltip_text = "没有可升级实例" if upgrade.disabled else ""
	upgrade.pressed.connect(_show_rest_upgrade_screen)
	rest_page.add_child(upgrade)
	var skip: Button = Button.new()
	skip.text = "跳过并返回地图"
	skip.pressed.connect(_on_rest_skip_pressed)
	rest_page.add_child(skip)


func _on_rest_heal_pressed() -> void:
	if run_model.resolve_rest_heal() and run_model.complete_current_node():
		_show_map_screen()


func _on_rest_skip_pressed() -> void:
	if run_model.skip_rest() and run_model.complete_current_node():
		_show_map_screen()


func _show_boss_placeholder() -> void:
	ui_mode = &"boss_placeholder"
	_clear_screen()
	var boss_page: VBoxContainer = VBoxContainer.new()
	boss_page.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_page.add_theme_constant_override("separation", 18)
	screen_root.add_child(boss_page)
	_add_page_title(boss_page, "章节终点尚未接入", "M1 Boss占位：不冒充正式Boss战。")
	var finish: Button = Button.new()
	finish.text = "记录抵达并结束本次骨架验证"
	finish.pressed.connect(_on_boss_placeholder_finished)
	boss_page.add_child(finish)


func _on_boss_placeholder_finished() -> void:
	if run_model.acknowledge_boss_placeholder() and run_model.complete_current_node():
		_show_expedition_complete_screen()


func _show_expedition_complete_screen() -> void:
	ui_mode = &"expedition_complete"
	_clear_screen()
	var complete_page: VBoxContainer = VBoxContainer.new()
	complete_page.alignment = BoxContainer.ALIGNMENT_CENTER
	complete_page.add_theme_constant_override("separation", 18)
	screen_root.add_child(complete_page)
	_add_page_title(complete_page, "已抵达章节终点", "正式Boss将在M2接入。")
	var summary: Label = Label.new()
	summary.text = run_model.get_summary_text()
	complete_page.add_child(summary)
	var back: Button = Button.new()
	back.text = "返回标题"
	back.pressed.connect(_show_main_menu)
	complete_page.add_child(back)


func _show_test_arena_menu() -> void:
	ui_mode = &"test_menu"
	is_test_mode = false
	_clear_screen()
	var menu: VBoxContainer = VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 14)
	screen_root.add_child(menu)
	_add_page_title(menu, "机制测试场", "选择对手。此处不计入远征，可集中练习已实现机制。")
	for arena_enemy_id: StringName in EnemyCatalog.TEST_ARENA_ENEMY_IDS:
		var definition: EnemyDefinition = EnemyCatalog.create(arena_enemy_id)
		var button: Button = Button.new()
		button.text = "%s｜%s｜生命 %d～%d｜%d 个意图" % [
			definition.display_name, definition.tier,
			definition.hp_min, definition.hp_max, definition.intent_count(),
		]
		button.tooltip_text = _describe_enemy_traits(definition)
		button.custom_minimum_size = Vector2(560, 50)
		button.pressed.connect(_start_test_level.bind(arena_enemy_id))
		menu.add_child(button)
	var back: Button = Button.new()
	back.text = "返回标题"
	back.custom_minimum_size = Vector2(200, 44)
	back.pressed.connect(_show_main_menu)
	menu.add_child(back)


func _describe_enemy_traits(definition: EnemyDefinition) -> String:
	var parts: Array[String] = []
	if definition.has_trait(EnemyDefinition.TRAIT_DEVOUR):
		parts.append("吞字记录：首次被某类别命中后记录该类别。")
	if definition.has_trait(EnemyDefinition.TRAIT_STONE_SHELL):
		parts.append("石壳%d，每回合恢复 %d；同式适应 +%d 格挡，换类别则失去全部石壳。" % [
			definition.stone_shell_initial, definition.stone_shell_regen,
			definition.stone_shell_adapt_block,
		])
	if definition.has_trait(EnemyDefinition.TRAIT_REVERSE_READ):
		parts.append("倒读记录：依据你上一回合最后一张非状态牌改变意图。")
	if definition.has_trait(EnemyDefinition.TRAIT_BINDING):
		parts.append("装订：单回合额外抽牌达到 %d 张时，一张《%s》进入弃牌堆。" % [
			definition.binding_draw_threshold,
			CardCatalog.get_definition(definition.binding_card_id)[&"title"],
		])
	if parts.is_empty():
		return definition.intro_line
	return "\n".join(parts)


func _start_test_level(arena_enemy_id: StringName = EnemyCatalog.TEST_ARENA_ENEMY_IDS[0]) -> void:
	is_test_mode = true
	test_arena_enemy_id = arena_enemy_id
	run_model = RunModelScript.new()
	run_model.start_run(RunModel.DEFAULT_SEED)
	current_stage = CombatModel.TUTORIAL_STAGE_MAX
	_start_current_battle()


func _start_current_battle() -> void:
	ui_mode = &"combat"
	model = CombatModelScript.new()
	if is_test_mode:
		model.start_battle(
			CombatModel.DEFAULT_SEED + current_stage,
			current_stage,
			run_model.get_acquired_card_ids(),
			test_arena_enemy_id,
			run_model.get_relic_ids()
		)
	else:
		var node: MapNode = run_model.get_current_map_node()
		if node == null:
			_show_map_screen()
			return
		current_stage = clampi(node.depth, CombatModel.TUTORIAL_STAGE_MIN, CombatModel.TUTORIAL_STAGE_MAX)
		model.start_battle(
			node.content_seed,
			current_stage,
			[],
			node.enemy_id,
			run_model.get_relic_ids(),
			run_model.get_deck_instances(),
			run_model.player_hp,
			run_model.player_max_hp
		)
	_build_combat_screen()
	_refresh_combat()


func _build_combat_screen() -> void:
	_clear_screen()
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	screen_root.add_child(page)

	var header: HBoxContainer = HBoxContainer.new()
	page.add_child(header)
	var title: Label = Label.new()
	title.text = "断环  /  机制测试场" if is_test_mode else "断环  /  无字之城"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("e7d9b5"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var stage_label: Label = Label.new()
	stage_label.text = "独立测试 / 不计入远征" if is_test_mode else model.get_stage_progress_text()
	stage_label.add_theme_font_size_override("font_size", 20)
	stage_label.add_theme_color_override("font_color", Color("ffd27d"))
	header.add_child(stage_label)

	var hint_label: Label = Label.new()
	if is_test_mode:
		hint_label.text = "测试说明｜稳定度、超载、封存、回响、缺名与目标选择均已开放。对手：%s。遗物：%s。" % [
			model.enemy_name, model.rule_engine.get_relic_text(),
		]
	else:
		hint_label.text = "现场记录｜%s" % model.tutorial_hint
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color("a9bdd0"))
	page.add_child(hint_label)

	var stats_panel: PanelContainer = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color("182332"), Color("40566e"), 8))
	page.add_child(stats_panel)
	var stats: HBoxContainer = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	stats_panel.add_child(stats)
	_add_stat(stats, "生命", "%d / %d" % [model.player_hp, model.player_max_hp])
	_add_stat(stats, "稳定度", "%d / %d" % [model.energy, CombatModel.BASE_ENERGY])
	_add_stat(stats, "格挡", str(model.player_block))
	_add_stat(stats, "不稳定", "%d / %d" % [model.instability, CombatModel.INSTABILITY_THRESHOLD] if model.is_mechanic_unlocked(&"overload") else "读数稳定")
	_add_stat(stats, "牌堆", "抽%d 弃%d 逝%d" % [model.draw_pile.size(), model.discard_pile.size(), model.exhausted_zone.size()])
	_add_stat(stats, "状态", model.get_player_status_text())
	_add_stat(stats, "远征", "牌%d 墨晶%d" % [run_model.deck_instances.size(), run_model.ink_crystals])

	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 12)
	page.add_child(middle)
	var enemy_panel: PanelContainer = PanelContainer.new()
	enemy_panel.custom_minimum_size = Vector2(430, 185)
	enemy_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_panel.add_theme_stylebox_override("panel", _panel_style(Color("291b24"), Color("8c5367"), 12))
	middle.add_child(enemy_panel)
	var enemy_column: VBoxContainer = VBoxContainer.new()
	enemy_column.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_column.add_theme_constant_override("separation", 9)
	enemy_panel.add_child(enemy_column)
	_add_centered(enemy_column, model.enemy_name, 28, Color("f2bdc8"))
	_add_centered(
		enemy_column,
		"生命 %d/%d　格挡 %d" % [model.enemy_hp, model.enemy_max_hp, model.get_enemy_total_block()],
		18, Color("e4d4d8")
	)
	if model.is_mechanic_unlocked(&"missing_name"):
		_add_centered(enemy_column, "%s｜%s" % [model.get_enemy_record_text(), model.get_missing_name_text()], 16, Color("e0a9ba"))
	if model.is_mechanic_unlocked(&"intent"):
		_add_centered(enemy_column, "下一意图 / %s" % model.get_enemy_intent_text(), 20, Color("ffd27d"))

	var info_panel: PanelContainer = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(560, 185)
	info_panel.add_theme_stylebox_override("panel", _panel_style(Color("151e29"), Color("33485f"), 8))
	middle.add_child(info_panel)
	var info_column: VBoxContainer = VBoxContainer.new()
	info_panel.add_child(info_column)
	var log_title: Label = Label.new()
	log_title.text = "战斗日志"
	log_title.add_theme_color_override("font_color", Color("b8c9db"))
	info_column.add_child(log_title)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 15)
	log_view.add_theme_color_override("default_color", Color("b9c4cf"))
	info_column.add_child(log_view)

	var zone_row: HBoxContainer = HBoxContainer.new()
	page.add_child(zone_row)
	var hand_title: Label = Label.new()
	hand_title.text = "选择目标（点击确认，或取消）" if model.has_pending_selection() else "手牌（点击打出）"
	hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_title.add_theme_color_override("font_color", Color("d7c9a9"))
	zone_row.add_child(hand_title)
	var sealed_label: Label = Label.new()
	sealed_label.text = "封存区：%s" % model.get_sealed_summary() if model.is_mechanic_unlocked(&"seal") else "封存区：尚无记录"
	sealed_label.add_theme_color_override("font_color", Color("c5a4df"))
	zone_row.add_child(sealed_label)

	var hand_scroll: ScrollContainer = ScrollContainer.new()
	hand_scroll.custom_minimum_size = Vector2(0, 145)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(hand_scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 10)
	hand_scroll.add_child(hand_box)

	var footer: HBoxContainer = HBoxContainer.new()
	page.add_child(footer)
	result_label = Label.new()
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.add_theme_color_override("font_color", Color("9cafc2"))
	footer.add_child(result_label)
	var restart_button: Button = Button.new()
	restart_button.text = "返回标题" if is_test_mode else "重新开始远征"
	restart_button.pressed.connect(_on_restart_pressed)
	footer.add_child(restart_button)
	result_action_button = Button.new()
	result_action_button.visible = false
	result_action_button.pressed.connect(_on_battle_result_pressed)
	footer.add_child(result_action_button)
	end_turn_button = Button.new()
	end_turn_button.text = "结束回合"
	end_turn_button.custom_minimum_size = Vector2(140, 44)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	footer.add_child(end_turn_button)


func _refresh_combat() -> void:
	_build_combat_screen()
	# 规则层是唯一真相源：UI 只询问“现在是否有待选择请求”，
	# 并把玩家点击原样转交给规则层，自己不保存任何选择状态。
	if model.has_pending_selection():
		_build_selection_row()
	else:
		_build_hand_row()
	var joined_log: String = ""
	for entry: String in model.log_entries:
		joined_log += entry + "\n"
	log_view.text = joined_log
	end_turn_button.disabled = model.battle_over or model.has_pending_selection()
	if model.has_pending_selection():
		result_action_button.visible = false
		result_label.text = "选择模式｜%s（可取消）" % model.get_pending_prompt()
		result_label.add_theme_color_override("font_color", Color("ffd27d"))
	elif model.battle_over:
		result_action_button.visible = true
		if model.victory:
			result_label.text = "测试完成。" if is_test_mode else "战斗胜利。结算后继续深入。"
			result_label.add_theme_color_override("font_color", Color("8ed5a6"))
			result_action_button.text = "返回标题" if is_test_mode else "查看战果"
		else:
			result_label.text = "战斗失败，可重试当前场。"
			result_label.add_theme_color_override("font_color", Color("e58c95"))
			result_action_button.text = "重试当前场"
	else:
		result_action_button.visible = false
		result_label.text = "第%d回合｜每回合3稳定度" % model.turn_number


func _build_hand_row() -> void:
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		var button: Button = Button.new()
		var cost: int = model.get_card_cost(card)
		var unplayable: bool = card.card_type == CardData.CardType.STATUS and card.base_cost >= 99
		button.custom_minimum_size = Vector2(184, 135)
		button.text = "%s
[%s·%s] %s

%s" % [
			card.title, card.type_name(), card.rarity,
			"不可打出" if unplayable else "费用%d" % cost, card.description,
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "%s

%s" % [card.flavor_text, card.description]
		button.disabled = model.battle_over or unplayable or cost > model.energy
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_stylebox_override("normal", _card_style(card.card_type, false))
		button.add_theme_stylebox_override("hover", _card_style(card.card_type, true))
		button.pressed.connect(_on_card_pressed.bind(index))
		hand_box.add_child(button)


## 选择模式：手牌区替换为候选目标按钮加一个取消按钮。
func _build_selection_row() -> void:
	var candidate_indices: Array[int] = model.get_pending_candidate_indices()
	var candidate_labels: Array[String] = model.get_pending_candidate_labels()
	for slot: int in range(candidate_indices.size()):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(184, 135)
		button.text = "选择
%s" % candidate_labels[slot]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_stylebox_override("normal", _panel_style(Color("2c3a26"), Color("8fc27a"), 9))
		button.add_theme_stylebox_override("hover", _panel_style(Color("3b4f33"), Color("b0dc9b"), 9))
		button.pressed.connect(_on_selection_confirmed.bind(candidate_indices[slot]))
		hand_box.add_child(button)
	var cancel: Button = Button.new()
	cancel.custom_minimum_size = Vector2(184, 135)
	cancel.text = "取消

该牌不结算，返还稳定度并放回手牌。"
	cancel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel.add_theme_font_size_override("font_size", 15)
	cancel.add_theme_stylebox_override("normal", _panel_style(Color("3a2a2a"), Color("b98080"), 9))
	cancel.add_theme_stylebox_override("hover", _panel_style(Color("4d3636"), Color("d59a9a"), 9))
	cancel.pressed.connect(_on_selection_cancelled)
	hand_box.add_child(cancel)


func _on_selection_confirmed(target_index: int) -> void:
	model.resolve_pending_selection(target_index)
	_refresh_combat()


func _on_selection_cancelled() -> void:
	model.cancel_pending_selection()
	_refresh_combat()


func _on_restart_pressed() -> void:
	if is_test_mode:
		_show_main_menu()
	else:
		_restart_run()


func _on_card_pressed(hand_index: int) -> void:
	model.play_card(hand_index)
	_refresh_combat()


func _on_end_turn_pressed() -> void:
	model.end_player_turn()
	_refresh_combat()


func _on_battle_result_pressed() -> void:
	if not model.victory:
		_start_current_battle()
		return
	if is_test_mode:
		_show_main_menu()
		return
	run_model.player_hp = model.player_hp
	run_model.record_battle_victory(current_stage)
	if run_model.should_offer_reward(current_stage):
		run_model.generate_reward_choices(current_stage)
		_show_reward_screen()
	else:
		run_model.mark_current_node_resolved()
		run_model.complete_current_node()
		_show_map_screen()


func _show_reward_screen() -> void:
	ui_mode = &"reward"
	_clear_screen()
	var reward_page: VBoxContainer = VBoxContainer.new()
	reward_page.add_theme_constant_override("separation", 18)
	screen_root.add_child(reward_page)
	_add_page_title(reward_page, "战后回收", "选择一张残页加入牌组，也可以跳过。")
	var summary: Label = Label.new()
	summary.text = run_model.get_summary_text()
	summary.add_theme_color_override("font_color", Color("9cafc2"))
	reward_page.add_child(summary)
	var cards: HBoxContainer = HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 18)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reward_page.add_child(cards)
	for index: int in range(run_model.pending_reward_ids.size()):
		var card_id: StringName = run_model.pending_reward_ids[index]
		var definition: Dictionary = CardCatalog.get_definition(card_id)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(300, 300)
		button.text = "%s
[%s] 费用%d

%s

——
%s" % [
			definition[&"title"], definition[&"rarity"], definition[&"cost"],
			definition[&"description"], definition[&"flavor"],
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_reward_chosen.bind(index))
		cards.add_child(button)
	var skip: Button = Button.new()
	skip.text = "跳过奖励"
	skip.custom_minimum_size = Vector2(180, 48)
	skip.pressed.connect(_on_reward_skipped)
	reward_page.add_child(skip)


func _on_reward_chosen(index: int) -> void:
	if run_model.choose_reward(index) and run_model.complete_current_node():
		_show_map_screen()


func _on_reward_skipped() -> void:
	if run_model.skip_reward() and run_model.complete_current_node():
		_show_map_screen()


func _advance_after_interlude() -> void:
	if current_stage < CombatModel.TUTORIAL_STAGE_MAX:
		current_stage += 1
		_show_path_transition()
	else:
		run_model.begin_event()
		_show_event_screen()


func _show_path_transition() -> void:
	_clear_screen()
	var transition: VBoxContainer = VBoxContainer.new()
	transition.alignment = BoxContainer.ALIGNMENT_CENTER
	transition.add_theme_constant_override("separation", 22)
	screen_root.add_child(transition)
	var data: Dictionary = _get_path_transition_data(current_stage)
	_add_page_title(transition, str(data[&"title"]), "无字之城 / 路径记录")
	var body: Label = Label.new()
	body.text = str(data[&"body"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 22)
	body.add_theme_color_override("font_color", Color("d8e0e7"))
	transition.add_child(body)
	var proceed: Button = Button.new()
	proceed.text = "继续前行"
	proceed.custom_minimum_size = Vector2(260, 54)
	proceed.pressed.connect(_start_current_battle)
	transition.add_child(proceed)


func _get_path_transition_data(stage: int) -> Dictionary:
	match stage:
		2:
			return {&"title": "街口的石片", &"body": "码头之后没有路标。守卫胸前的石片却会在动作发生前亮起，像一段被迫公开的念头。"}
		3:
			return {&"title": "井下蓝光", &"body": "一张陌生残页从测量井边缘自行脱落。握住它时，你第一次听见体内传来裂纹扩张的声音。"}
		4:
			return {&"title": "迟到的钟声", &"body": "长廊里的钟总在重锤落下之后才响。散落的文字却提前排列成防线，等待尚未到来的那一击。"}
		5:
			return {&"title": "第二个声音", &"body": "阅览室无人应答。你挥动武器，书架深处却完整复述了一次相同的动作。"}
		6:
			return {&"title": "被吞下的字", &"body": "越靠近巢穴，墙上的词越少。虫腹里滚动着失踪的字，其中一个与你的编号形状相同。"}
	return {&"title": "继续深入", &"body": "路径仍在向城内延伸。"}


func _show_event_screen() -> void:
	ui_mode = &"event"
	_clear_screen()
	var event_page: VBoxContainer = VBoxContainer.new()
	event_page.add_theme_constant_override("separation", 18)
	screen_root.add_child(event_page)
	_add_page_title(event_page, run_model.get_event_title(), "纪元残骸 / 异常记录")
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("171f2b"), Color("536980"), 12))
	event_page.add_child(panel)
	var story: Label = Label.new()
	story.text = run_model.get_event_story()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	story.add_theme_font_size_override("font_size", 22)
	story.add_theme_color_override("font_color", Color("d8e0e7"))
	panel.add_child(story)
	var options: VBoxContainer = VBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	event_page.add_child(options)
	var option_data: Array[Dictionary] = run_model.get_event_options()
	for index: int in range(option_data.size()):
		var option: Dictionary = option_data[index]
		var button: Button = Button.new()
		button.text = "%s｜%s" % [option[&"label"], option[&"consequence"]]
		button.disabled = not bool(option[&"enabled"])
		button.tooltip_text = str(option[&"reason"])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 58)
		button.pressed.connect(_on_event_choice.bind(index))
		options.add_child(button)


func _on_event_choice(index: int) -> void:
	if run_model.apply_event_choice(index) and run_model.complete_current_node():
		_show_summary_screen()


func _show_summary_screen() -> void:
	ui_mode = &"event_outcome"
	_clear_screen()
	var summary_page: VBoxContainer = VBoxContainer.new()
	summary_page.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_page.add_theme_constant_override("separation", 22)
	screen_root.add_child(summary_page)
	_add_page_title(summary_page, "事件记录", "节点已经完成；路线后继已开放。")
	var outcome: Label = Label.new()
	outcome.text = run_model.event_outcome
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.add_theme_font_size_override("font_size", 22)
	outcome.add_theme_color_override("font_color", Color("d9c7a5"))
	summary_page.add_child(outcome)
	var summary: Label = Label.new()
	summary.text = run_model.get_summary_text()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_color_override("font_color", Color("9cafc2"))
	summary_page.add_child(summary)
	if not run_model.evidence.is_empty():
		var evidence_label: Label = Label.new()
		evidence_label.text = "已记录证据：%s" % "、".join(run_model.evidence)
		evidence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		evidence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary_page.add_child(evidence_label)
	var back: Button = Button.new()
	back.text = "返回地图"
	back.custom_minimum_size = Vector2(240, 50)
	back.pressed.connect(_show_map_screen)
	summary_page.add_child(back)


func _add_page_title(parent: VBoxContainer, heading: String, subtitle: String) -> void:
	var title: Label = Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("e7d9b5"))
	parent.add_child(title)
	var sub: Label = Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("9cafc2"))
	parent.add_child(sub)


func _add_stat(parent: HBoxContainer, title: String, value: String) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(170, 52)
	parent.add_child(box)
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", Color("7f96aa"))
	box.add_child(title_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", Color("e4ebf1"))
	box.add_child(value_label)


func _add_centered(parent: VBoxContainer, text: String, size: int, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	return style


func _card_style(card_type: int, hovered: bool) -> StyleBoxFlat:
	var fill: Color
	var border: Color
	match card_type:
		CardData.CardType.ATTACK:
			fill = Color("4a2630") if not hovered else Color("65333f")
			border = Color("c56d79")
		CardData.CardType.DEFENSE:
			fill = Color("20394d") if not hovered else Color("2c4d68")
			border = Color("69a7c7")
		_:
			fill = Color("392d4c") if not hovered else Color("4d3b67")
			border = Color("a98bd1")
	return _panel_style(fill, border, 9)
