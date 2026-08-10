extends SceneTree

const FORBIDDEN_PLAYER_TERMS: Array[String] = [
	"固定种子", "具体实例", "规则层", "当前单敌人规则", "M1", "Unix", "—",
]

var failures: int = 0
var player_texts: Array[Dictionary] = []
var main: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_collect_catalog_copy()
	_check_key_mechanic_copy()
	await _collect_rendered_ui_copy()
	for entry: Dictionary in player_texts:
		var text: String = str(entry[&"text"])
		for forbidden: String in FORBIDDEN_PLAYER_TERMS:
			if text.contains(forbidden):
				failures += 1
				push_error("FAIL: %s 含禁用词“%s”：%s" % [entry[&"source"], forbidden, text])
	print("PASS: 已检查 %d 条玩家可见文本，不扫描 README 或内部开发日志" % player_texts.size())
	if main != null and is_instance_valid(main):
		main.queue_free()
	if failures == 0:
		print("PASS: 玩家可见目录、UI与关键机制文案审校通过")
		quit(0)
	else:
		push_error("FAIL: %d 项玩家文案检查未通过" % failures)
		quit(1)


func _collect_catalog_copy() -> void:
	for raw_id: Variant in CardCatalog.DEFINITIONS.keys():
		var card_id: StringName = raw_id as StringName
		_collect_fields("卡牌 %s" % card_id, CardCatalog.get_definition(card_id), [
			&"title", &"description", &"rarity", &"flavor",
		])
		var upgrade: Dictionary = CardUpgradeCatalog.get_default_upgrade(card_id)
		_collect_fields("卡牌升级 %s" % card_id, upgrade, [&"description", &"title_suffix"])
	for enemy_id: StringName in EnemyCatalog.get_all_ids():
		var enemy: Dictionary = EnemyCatalog.DEFINITIONS[enemy_id]
		_collect_fields("敌人 %s" % enemy_id, enemy, [&"name", &"tier", &"intro_line"])
		for raw_intent: Variant in enemy.get(&"intents", []):
			var intent: Dictionary = raw_intent as Dictionary
			_collect_fields("敌人意图 %s/%s" % [enemy_id, intent.get(&"id", &"")], intent, [
				&"name", &"description",
			])
			for raw_operation: Variant in intent.get(&"operations", []):
				_collect_fields("敌人行动 %s/%s" % [enemy_id, intent.get(&"id", &"")], raw_operation as Dictionary, [
					&"action", &"label", &"log",
				])
	for relic_id: StringName in RelicCatalog.get_all_ids():
		_collect_fields("遗物 %s" % relic_id, RelicCatalog.get_definition(relic_id), [
			&"title", &"rarity", &"description", &"short_description", &"flavor", &"source_hint",
		])
	for raw_id: Variant in EvidenceCatalog.DEFINITIONS.keys():
		var evidence_id: StringName = raw_id as StringName
		_collect_fields("证据 %s" % evidence_id, EvidenceCatalog.get_record(evidence_id), [
			&"title", &"source", &"description",
		])
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	for event_id: StringName in RunModel.EVENT_IDS:
		_add_player_text("事件标题 %s" % event_id, run.get_event_title(event_id))
		_add_player_text("事件正文 %s" % event_id, run.get_event_story(event_id))
		for option: Dictionary in run.get_event_options(event_id):
			_collect_fields("事件选项 %s" % event_id, option, [&"label", &"consequence", &"reason"])


func _check_key_mechanic_copy() -> void:
	var old_wound: String = str(CardCatalog.get_definition(&"old_wound")[&"description"])
	_expect(old_wound.contains("回合结束时") and old_wound.contains("2 点不可格挡伤害"), "旧伤明确回合结束时造成 2 点不可格挡伤害")
	var redaction: String = str(CardCatalog.get_definition(&"redaction")[&"description"])
	_expect(redaction.contains("不可打出") and redaction.contains("抽到时立即") and redaction.contains("律式缺名") and redaction.contains("然后消逝"), "删节明确不可打出、抽到触发律式缺名并消逝")
	var reorder: String = str(CardCatalog.get_definition(&"index_reorder")[&"description"])
	var reorder_upgrade: String = str(CardUpgradeCatalog.get_default_upgrade(&"index_reorder")[&"description"])
	_expect(reorder.contains("选择 1 张") and reorder.contains("其余顺序不变") and not reorder.contains("任意排序"), "索引重排基础文案忠于选择弃置且不重排")
	_expect(reorder_upgrade.contains("选择 1 张") and reorder_upgrade.contains("其余顺序不变"), "索引重排升级文案忠于选择弃置且不重排")
	var boss: CombatModel = CombatModel.new()
	boss.start_battle(73103, 6, [], &"name_eraser", [])
	var cost_recovery: String = str((EnemyCatalog.DEFINITIONS[&"name_eraser"][&"intents"] as Array)[0][&"description"])
	var type_recovery: String = str((EnemyCatalog.DEFINITIONS[&"name_eraser"][&"intents"] as Array)[4][&"description"])
	var keyword_recovery: String = str((EnemyCatalog.DEFINITIONS[&"name_eraser"][&"intents"] as Array)[6][&"description"])
	_expect(cost_recovery.contains("连续打出三种不同类别") and cost_recovery.contains("恢复最早一项"), "Boss费用恢复条件明确")
	_expect(type_recovery.contains("封存牌解封") and type_recovery.contains("恢复最早一项"), "Boss类别恢复条件明确")
	_expect(keyword_recovery.contains("裂解") and keyword_recovery.contains("恢复最早一项"), "Boss关键词恢复条件明确")
	boss.boss_phase = 2
	boss._enter_boss_terminal()
	var terminal_reason: String = str(boss.get_boss_terminal_options()[1][&"reason"])
	_expect(terminal_reason.contains("至少 2 次可计数恢复") and terminal_reason.contains("费用、类别或关键词"), "Boss原文选项明确按恢复次数计数")
	var bell: Dictionary = RelicCatalog.get_definition(&"expired_return_bell")
	var bell_description: String = str(bell[&"description"])
	_expect(bell_description.contains("第一次受到致命伤害") and bell_description.contains("保留 1 点生命") and bell_description.contains("随后立即裂解一次"), "返航铃明确首次致命保留生命并立即裂解")
	_expect(bell_description.contains("可能仍被后续裂解杀死"), "返航铃明确不是无条件复活")


func _collect_rendered_ui_copy() -> void:
	var save_path: String = "user://broken_ring_copy_test_%d.json" % OS.get_process_id()
	var save_manager: SaveManager = SaveManager.new(save_path)
	save_manager.delete()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_manager = save_manager
	root.add_child(main)
	await process_frame
	_collect_visible_tree("标题页", main.screen_root)
	main._restart_run()
	await process_frame
	_collect_visible_tree("地图", main.screen_root)
	main._show_deck_screen()
	await process_frame
	_collect_visible_tree("牌组", main.screen_root)
	main.run_model.current_node_id = &"d04_01"
	main.run_model.pending_shop_stock = ShopCatalog.generate(73103, 0, main.run_model.relics)
	main._show_shop_screen()
	await process_frame
	_collect_visible_tree("商店", main.screen_root)
	main._show_upgrade_screen(&"forge")
	await process_frame
	_collect_visible_tree("升级", main.screen_root)
	main.run_model.selected_event_id = &"authorless_book"
	main.run_model.event_resolved = false
	main._show_event_screen()
	await process_frame
	_collect_visible_tree("事件", main.screen_root)
	var reward_ids: Array[StringName] = [&"critical_permission", &"blank_space", &"rift_slash"]
	main.run_model.pending_reward_ids = reward_ids
	main._show_reward_screen()
	await process_frame
	_collect_visible_tree("奖励", main.screen_root)
	main.is_test_mode = true
	main.run_model = RunModel.new()
	main.run_model.start_run(73103)
	main.current_stage = 6
	main._start_current_battle()
	await process_frame
	_collect_visible_tree("战斗", main.screen_root)
	save_manager.delete()


func _collect_visible_tree(source: String, node: Node) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is Button:
		_add_player_text("%s按钮" % source, (node as Button).text)
		_add_player_text("%s按钮提示" % source, (node as Button).tooltip_text)
	elif node is RichTextLabel:
		_add_player_text("%s文本" % source, (node as RichTextLabel).text)
		_add_player_text("%s文本提示" % source, (node as RichTextLabel).tooltip_text)
	elif node is Label:
		_add_player_text("%s文本" % source, (node as Label).text)
		_add_player_text("%s文本提示" % source, (node as Label).tooltip_text)
	for child: Node in node.get_children():
		_collect_visible_tree(source, child)


func _collect_fields(source: String, data: Dictionary, fields: Array[StringName]) -> void:
	for field: StringName in fields:
		if data.has(field):
			_add_player_text("%s.%s" % [source, field], str(data[field]))


func _add_player_text(source: String, text: String) -> void:
	if not text.is_empty():
		player_texts.append({&"source": source, &"text": text})


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
