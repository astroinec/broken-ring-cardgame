extends SceneTree


var failures: int = 0
var test_path: String
var manager: SaveManager


func _init() -> void:
	test_path = "user://broken_ring_run_v1_test_%d.json" % OS.get_process_id()
	manager = SaveManager.new(test_path)
	manager.delete()
	_test_round_trip_and_summary()
	_test_combat_outside_checkpoint()
	_test_safe_rejections()
	manager.delete()
	_expect(not FileAccess.file_exists(test_path), "测试结束后清理唯一存档文件")
	if failures == 0:
		print("PASS: all M3 v1 save protocol checks")
		quit(0)
	else:
		push_error("FAIL: %d save protocol checks failed" % failures)
		quit(1)


func _test_round_trip_and_summary() -> void:
	var source: RunModel = _build_checkpoint_run()
	var expected: Dictionary = source.to_save_dict()
	for pending_field: String in [
		"pending_reward_ids", "pending_event_selection", "pending_shop_stock", "pending_node_resolution",
		"selected_event_id", "event_battle_pending", "event_battle_reward_settled",
	]:
		_expect(not expected.has(pending_field), "存档不包含pending字段%s" % pending_field)
	var before_time: int = int(Time.get_unix_time_from_system())
	_expect(manager.save_run(source), "SaveManager保存有效远征")
	var after_time: int = int(Time.get_unix_time_from_system())
	_expect(manager.last_error.is_empty(), "保存成功错误字符串为空")
	_expect(manager.last_saved_at_unix >= before_time and manager.last_saved_at_unix <= after_time, "保存时间来自运行时Unix时间")
	_expect(not FileAccess.file_exists(test_path.trim_suffix(".json") + ".tmp"), "保存成功后清理临时文件")
	var inspection: Dictionary = manager.inspect()
	_expect(bool(inspection["exists"]) and bool(inspection["valid"]), "inspect识别有效存档")
	_expect(str(inspection["summary"]) == source.get_summary_text(), "inspect返回远征摘要")

	var file: FileAccess = FileAccess.open(test_path, FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	_expect(int(parsed["save_schema"]) == SaveManager.SAVE_SCHEMA, "顶层save_schema为1")
	_expect(int(parsed["run_schema"]) == RunModel.SCHEMA_VERSION, "顶层run_schema匹配RunModel")
	_expect(typeof(parsed["run"]["current_node_id"]) == TYPE_STRING, "StringName节点ID写为JSON字符串")
	_expect(typeof(parsed["run"]["deck_instances"][0]["card_id"]) == TYPE_STRING, "StringName卡牌ID写为JSON字符串")
	_expect(typeof(parsed["run"]["relics"][0]) == TYPE_STRING, "StringName遗物ID写为JSON字符串")

	var loaded: RunModel = RunModel.new()
	loaded.start_run(99991)
	loaded.pending_reward_ids = [&"broken_sentence"]
	loaded.pending_event_selection = {&"kind": &"test"}
	loaded.pending_shop_stock = {&"test": true}
	loaded.pending_node_resolution = {&"resolved": false}
	loaded.selected_event_id = &"definition_tax"
	loaded.event_battle_pending = true
	loaded.event_battle_reward_settled = true
	_expect(manager.load_run(loaded), "有效存档加载到新RunModel")
	_expect(loaded.to_save_dict() == expected, "保存加载后全部持久字段一致")
	_expect(loaded.map_graph.validate().is_empty(), "加载后MapGraph校验通过")
	_expect(loaded.map_graph.get_node(&"d01_00").completed, "地图完成状态恢复")
	_expect(loaded.map_graph.get_node(&"d02_00").revealed and loaded.map_graph.get_node(&"d02_00").reachable, "地图揭示与可达状态恢复")
	_expect(loaded.get_deck_instance(1)[&"upgrade_id"] != &"" and loaded.get_deck_instance(2)[&"upgrade_id"] == &"", "同卡不同实例升级状态恢复")
	_expect(loaded.evidence == ["九份涂名返航记录", "未发生的尸检"], "结构化证据重建旧标题数组")
	_expect(loaded.next_battle_enemy_strength == 2 and loaded.fracture_damage_override == 5, "下一战与远征持续修正恢复")
	_expect(loaded.pending_reward_ids.is_empty(), "加载后清空pending_reward_ids")
	_expect(loaded.pending_event_selection.is_empty() and not loaded.event_battle_pending and not loaded.event_battle_reward_settled, "加载后清空事件pending状态")
	_expect(loaded.pending_shop_stock.is_empty() and loaded.pending_node_resolution.is_empty(), "加载后清空商店和节点pending状态")
	_expect(loaded.selected_event_id == &"" and not loaded.event_resolved and loaded.event_outcome.is_empty(), "加载后清空瞬时事件状态")


func _test_combat_outside_checkpoint() -> void:
	var checkpoint: RunModel = _build_checkpoint_run()
	var saved_state: Dictionary = checkpoint.to_save_dict()
	_expect(manager.save_run(checkpoint), "进入下一节点前保存战斗外检查点")
	var battle_node_id: StringName = checkpoint.available_node_ids[0]
	_expect(checkpoint.enter_node(battle_node_id), "内存远征进入下一战节点")
	checkpoint.consume_current_battle_context()
	checkpoint.player_hp = 1
	var resumed: RunModel = RunModel.new()
	_expect(manager.load_run(resumed), "强退战斗后可重新加载检查点")
	_expect(resumed.to_save_dict() == saved_state, "继续时回到进入战斗前的地图可达状态")
	_expect(resumed.available_node_ids.has(battle_node_id) and resumed.pending_node_resolution.is_empty(), "未完成战斗节点重新可达且无战斗中状态")


func _test_safe_rejections() -> void:
	var valid_run: RunModel = _build_checkpoint_run()
	_expect(manager.save_run(valid_run), "为损坏输入测试建立有效基线")
	var envelope: Dictionary = _read_json_file()

	_write_text("{broken json")
	_assert_file_load_rejected("损坏JSON安全失败", "JSON")
	_assert_inspect_invalid("损坏JSON inspect显示原因")

	var broken: Dictionary = envelope.duplicate(true)
	broken["save_schema"] = 99
	_assert_envelope_rejected(broken, "不兼容save_schema安全失败")
	broken = envelope.duplicate(true)
	broken["run_schema"] = 99
	_assert_envelope_rejected(broken, "不兼容run_schema安全失败")
	broken = envelope.duplicate(true)
	broken.erase("saved_at_unix")
	_assert_envelope_rejected(broken, "缺少顶层字段安全失败")
	broken = envelope.duplicate(true)
	(broken["run"] as Dictionary).erase("player_hp")
	_assert_envelope_rejected(broken, "缺少RunModel字段安全失败")

	broken = envelope.duplicate(true)
	(broken["run"]["completed_node_ids"] as Array).append("unknown_node")
	_assert_envelope_rejected(broken, "未知节点安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["deck_instances"][0]["card_id"] = "unknown_card"
	_assert_envelope_rejected(broken, "未知卡牌安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["deck_instances"][0]["upgrade_id"] = "unknown_upgrade"
	_assert_envelope_rejected(broken, "未知升级安全失败")
	broken = envelope.duplicate(true)
	(broken["run"]["relics"] as Array).append("unknown_relic")
	_assert_envelope_rejected(broken, "未知遗物安全失败")
	broken = envelope.duplicate(true)
	(broken["run"]["relics"] as Array).append((broken["run"]["relics"] as Array)[0])
	_assert_envelope_rejected(broken, "重复遗物安全失败")
	broken = envelope.duplicate(true)
	(broken["run"]["evidence_records"] as Array).append({
		"id": "unknown_evidence", "title": "未知", "source": "测试", "description": "测试",
	})
	_assert_envelope_rejected(broken, "未知证据安全失败")

	broken = envelope.duplicate(true)
	broken["run"]["deck_instances"][1]["instance_id"] = broken["run"]["deck_instances"][0]["instance_id"]
	_assert_envelope_rejected(broken, "重复牌组实例ID安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["next_deck_instance_id"] = broken["run"]["deck_instances"][-1]["instance_id"]
	_assert_envelope_rejected(broken, "无效next_deck_instance_id安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["player_hp"] = broken["run"]["player_max_hp"] + 1
	_assert_envelope_rejected(broken, "生命范围损坏安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["ink_crystals"] = -1
	_assert_envelope_rejected(broken, "墨晶范围损坏安全失败")
	broken = envelope.duplicate(true)
	broken["run"]["available_node_ids"] = []
	_assert_envelope_rejected(broken, "地图可达状态不一致安全失败")

	_write_envelope(envelope)
	_expect(manager.delete(), "SaveManager删除正式存档")
	_expect(not bool(manager.inspect()["exists"]), "删除后inspect报告无存档")


func _build_checkpoint_run() -> RunModel:
	var run: RunModel = RunModel.new()
	run.start_run(73103)
	var first_instance_id: int = int(run.deck_instances[0][&"instance_id"])
	run.upgrade_card_instance(first_instance_id)
	_expect(run.enter_node(&"d01_00"), "测试远征进入第一节点")
	run.record_current_battle_victory()
	run.generate_reward_choices(1)
	run.choose_reward(0)
	_expect(run.complete_current_node(), "测试远征完成第一节点检查点")
	run.player_max_hp = 75
	run.player_hp = 54
	run.ink_crystals = 321
	run._add_evidence(&"nine_redacted_return_records")
	run._add_evidence(&"nonexistent_autopsy")
	run.relics = RelicCatalog.get_all_ids()
	run.next_battle_missing_name = 2
	run.next_battle_instability_threshold_delta = -1
	run.next_battle_enemy_strength = 2
	run.next_battle_initial_draw_bonus = 1
	run.next_battle_reward_relic_id = &"expired_return_bell"
	run.fracture_damage_override = 5
	run.institution_relation = -1
	run.event_history_hints_hidden = true
	run.event_history = ["测试事件：已结算"]
	run.shop_remove_count = 2
	return run


func _assert_envelope_rejected(envelope: Dictionary, label: String) -> void:
	_write_envelope(envelope)
	_assert_file_load_rejected(label)
	_assert_inspect_invalid("%s的inspect结果无效" % label)


func _assert_file_load_rejected(label: String, error_fragment: String = "") -> void:
	var target: RunModel = RunModel.new()
	target.start_run(180097)
	target.ink_crystals = 777
	var before: Dictionary = target.to_save_dict()
	_expect(not manager.load_run(target), label)
	_expect(target.to_save_dict() == before, "%s且不改变已有RunModel" % label)
	_expect(not manager.last_error.is_empty(), "%s返回错误字符串" % label)
	if not error_fragment.is_empty():
		_expect(manager.last_error.contains(error_fragment), "%s错误原因可追踪" % label)


func _assert_inspect_invalid(label: String) -> void:
	var inspection: Dictionary = manager.inspect()
	_expect(bool(inspection["exists"]) and not bool(inspection["valid"]), label)
	_expect(not str(inspection["error"]).is_empty(), "%s并提供原因" % label)


func _read_json_file() -> Dictionary:
	var file: FileAccess = FileAccess.open(test_path, FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	return parsed


func _write_envelope(envelope: Dictionary) -> void:
	_write_text(JSON.stringify(envelope))


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string(text)
	file.flush()
	file.close()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
