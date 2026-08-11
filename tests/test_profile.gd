extends SceneTree


const LEGACY_REWARD_IDS: Array[StringName] = [
	&"broken_sentence", &"blank_space", &"index_reorder", &"unsigned_support",
	&"rift_slash", &"forced_stability", &"critical_permission", &"dissolution_protocol",
	&"delayed_guard", &"countdown_scar", &"prewritten_ending", &"unseal_order",
	&"restate", &"copied_guard", &"homophone",
]

var failures: int = 0
var profile_path: String
var run_path: String
var profile_manager: ProfileManager
var save_manager: SaveManager


func _init() -> void:
	var suffix: String = "%d" % OS.get_process_id()
	profile_path = "user://broken_ring_profile_test_%s.json" % suffix
	run_path = "user://broken_ring_profile_run_test_%s.json" % suffix
	profile_manager = ProfileManager.new(profile_path)
	save_manager = SaveManager.new(run_path)
	profile_manager.delete()
	save_manager.delete()
	_test_unlock_progression_and_idempotency()
	_test_repeated_atomic_save()
	_test_backup_recovery()
	_test_failed_profile_save_does_not_publish_unlocks()
	_test_corrupt_profile_degrades_without_touching_run_save()
	_test_schema_four_round_trip()
	_test_schema_three_migration()
	profile_manager.delete()
	save_manager.delete()
	if failures == 0:
		print("PASS: all profile, atomic save, and schema migration checks")
		quit(0)
	else:
		push_error("FAIL: %d profile checks failed" % failures)
		quit(1)


func _test_unlock_progression_and_idempotency() -> void:
	profile_manager.delete()
	var profile: Dictionary = profile_manager.load_profile()
	_expect(int(profile["unlock_tier"]) == 0, "新档案从 U0 开始")
	_expect(MetaCatalog.get_unlocked_reward_ids(0).size() == 12, "U0 开放十二张并包含首局关键反制的奖励牌")

	profile = profile_manager.record_run_started("run-u1")
	profile = profile_manager.record_run_started("run-u1")
	_expect(int(profile["runs_started"]) == 1, "同一远征开始记录幂等")
	profile = profile_manager.record_run_progress("run-u1", 9, true, false, false, [&"authorless_book", &"seventh_dock"])
	_expect(int(profile["unlock_tier"]) == 1 and int(profile["boss_reached"]) == 1, "首次抵达 Boss 推进到 U1")
	_expect(profile_manager.last_new_unlock_ids == MetaCatalog.TIER_CARD_IDS[1], "U1 只报告本层新解锁")
	var u1_boss_count: int = int(profile["boss_reached"])
	profile = profile_manager.record_run_progress("run-u1", 9, true, false, false, [&"authorless_book"])
	_expect(int(profile["boss_reached"]) == u1_boss_count and profile_manager.last_new_unlock_ids.is_empty(), "重复 Boss 结算不重复计数或解锁")

	profile = profile_manager.record_run_progress("run-u2", 9, false, true, false)
	_expect(int(profile["unlock_tier"]) == 2 and int(profile["wins"]) == 1, "首次通关推进到 U2")
	_expect(profile_manager.last_new_unlock_ids == MetaCatalog.TIER_CARD_IDS[2], "U2 只报告本层新解锁")
	profile = profile_manager.record_run_progress("run-u3-a", 9, false, true, false)
	_expect(int(profile["unlock_tier"]) == 2 and int(profile["wins"]) == 2, "第二次通关仍保持 U2")
	profile = profile_manager.record_run_progress("run-u3-b", 9, false, true, false)
	_expect(int(profile["unlock_tier"]) == 3 and int(profile["wins"]) == 3, "累计三次通关推进到 U3")
	_expect(profile_manager.last_new_unlock_ids == MetaCatalog.TIER_CARD_IDS[3], "U3 只报告本层新解锁")
	var u3_win_count: int = int(profile["wins"])
	profile = profile_manager.record_run_progress("run-u3-b", 9, false, true, false)
	_expect(int(profile["wins"]) == u3_win_count and profile_manager.last_new_unlock_ids.is_empty(), "重复通关结算保持 U3 档案幂等")

	profile_manager.delete()
	profile_manager.save_profile(ProfileManager.default_profile())
	profile = profile_manager.record_run_progress("run-original", 9, false, true, true)
	_expect(int(profile["unlock_tier"]) == 3 and int(profile["read_original_wins"]) == 1, "读取被删原文可直接推进到 U3")
	for index: int in range(70):
		profile_manager.record_run_progress("history-%d" % index, 1, false, false, false)
	var after_history: Dictionary = profile_manager.load_profile()
	profile = profile_manager.record_run_progress("run-original", 9, false, true, true)
	_expect(profile == after_history, "超过64条历史后恢复旧远征仍不会重复累计通关")


func _test_repeated_atomic_save() -> void:
	profile_manager.delete()
	var profile: Dictionary = ProfileManager.default_profile()
	for index: int in range(6):
		profile["runs_started"] = index
		_expect(profile_manager.save_profile(profile), "macOS 重复保存第 %d 次可替换正式档案" % (index + 1))
		_expect(profile_manager.load_profile() == profile, "重复保存第 %d 次内容完整" % (index + 1))
		_expect(not FileAccess.file_exists(profile_manager._temp_path()), "重复保存后不残留临时档案")
		_expect(not FileAccess.file_exists(profile_manager._backup_path()), "重复保存后不残留备份档案")
	var persisted: Dictionary = profile_manager.load_profile()
	var invalid: Dictionary = persisted.duplicate(true)
	invalid["unlock_tier"] = 99
	_expect(not profile_manager.save_profile(invalid), "无效候选档案在替换前被拒绝")
	_expect(profile_manager.load_profile() == persisted, "无效保存不改变正式档案")


func _test_backup_recovery() -> void:
	profile_manager.delete()
	var profile: Dictionary = ProfileManager.default_profile()
	profile["runs_started"] = 7
	_expect(profile_manager.save_profile(profile), "备份恢复测试保存正式Profile")
	_write_text(profile_manager._backup_path(), _read_text(profile_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	_expect(profile_manager.load_profile() == profile, "正式Profile缺失时从有效备份恢复")
	_expect(FileAccess.file_exists(profile_path) and not FileAccess.file_exists(profile_manager._backup_path()), "Profile恢复后清理备份")

	var run: RunModel = RunModel.new()
	run.start_run(80011, 2)
	_expect(save_manager.save_run(run), "备份恢复测试保存正式远征")
	_write_text(save_manager._backup_path(), _read_text(run_path))
	_write_text(run_path, "{broken save")
	var loaded: RunModel = RunModel.new()
	_expect(save_manager.load_run(loaded), "正式远征损坏时从有效备份恢复")
	_expect(loaded.seed_value == 80011 and not FileAccess.file_exists(save_manager._backup_path()), "远征备份恢复正确并清理备份")


func _test_failed_profile_save_does_not_publish_unlocks() -> void:
	var invalid_path: String = "user://missing_profile_dir_%d/profile.json" % OS.get_process_id()
	var failing: ProfileManager = ProfileManager.new(invalid_path)
	var result: Dictionary = failing.record_run_progress("failed-save", 9, true, false, false)
	_expect(not failing.last_error.is_empty(), "Profile写入失败提供错误")
	_expect(failing.last_new_unlock_ids.is_empty(), "Profile写入失败不发布新解锁")
	_expect(int(result["unlock_tier"]) == 0 and int(result["boss_reached"]) == 0, "Profile写入失败返回未变更档案")


func _test_corrupt_profile_degrades_without_touching_run_save() -> void:
	var run: RunModel = RunModel.new()
	run.start_run(73103, 2)
	run.add_card_instance(&"reverse_index")
	var expected: Dictionary = run.to_save_dict()
	_expect(save_manager.save_run(run), "损坏档案测试先保存独立远征")
	_write_text(profile_path, "{broken profile")
	var degraded: Dictionary = profile_manager.load_profile()
	_expect(degraded == ProfileManager.default_profile(), "损坏 Profile 安全降级为默认档案")
	_expect(not profile_manager.last_error.is_empty(), "损坏 Profile 提供可追踪错误")
	var inspection: Dictionary = profile_manager.inspect()
	_expect(bool(inspection[&"exists"]) and not bool(inspection[&"valid"]), "inspect 标记损坏 Profile 无效")
	var loaded: RunModel = RunModel.new()
	_expect(save_manager.load_run(loaded), "Profile 损坏不影响远征存档加载")
	_expect(loaded.to_save_dict() == expected, "Profile 与 run save 完全隔离")


func _test_schema_four_round_trip() -> void:
	var source: RunModel = RunModel.new()
	source.start_run(91027, 3)
	source.add_card_instance(&"echo_chamber", CardUpgradeCatalog.get_default_upgrade_id(&"echo_chamber"))
	source.run_seen_reward_ids = [&"broken_sentence", &"echo_chamber"]
	var expected: Dictionary = source.to_save_dict()
	_expect(save_manager.save_run(source), "schema4 远征保存成功")
	_expect(save_manager.save_run(source), "schema4 正式文件存在时重复保存成功")
	var loaded: RunModel = RunModel.new()
	_expect(save_manager.load_run(loaded), "schema4 远征恢复成功")
	_expect(loaded.to_save_dict() == expected, "schema4 解锁层、冻结卡池与已见奖励完整恢复")
	_expect(loaded.unlock_tier == 3 and loaded.unlocked_reward_ids == MetaCatalog.get_unlocked_reward_ids(3), "schema4 恢复 U3 冻结池")


func _test_schema_three_migration() -> void:
	var legacy: RunModel = RunModel.new()
	legacy.start_run(73103, 0)
	for card_id: StringName in LEGACY_REWARD_IDS:
		legacy.add_card_instance(card_id)
	var legacy_run: Dictionary = legacy.to_save_dict()
	legacy_run.erase("unlock_tier")
	legacy_run.erase("unlocked_reward_ids")
	legacy_run.erase("run_seen_reward_ids")
	legacy_run.erase("run_profile_id")
	# 真实schema3使用固定全互连图；构造推进到第4层后的旧节点状态，不能依赖新版图生成。
	legacy_run["current_node"] = 4
	legacy_run["current_node_id"] = "d04_01"
	legacy_run["visited_node_ids"] = ["d01_00", "d02_01", "d03_00", "d04_01"]
	legacy_run["available_node_ids"] = ["d05_00"]
	legacy_run["completed_node_ids"] = ["d01_00", "d02_01", "d03_00", "d04_01"]
	legacy_run["revealed_node_ids"] = ["d01_00", "d02_00", "d02_01", "d03_00", "d04_00", "d04_01", "d05_00"]
	var envelope: Dictionary = {
		"save_schema": SaveManager.SAVE_SCHEMA,
		"run_schema": 3,
		"saved_at_unix": 1_700_000_000,
		"run": legacy_run,
	}
	_write_text(run_path, JSON.stringify(envelope, "\t"))
	var loaded: RunModel = RunModel.new()
	_expect(save_manager.load_run(loaded), "手工 schema3 旧存档经 SaveManager 迁移后加载成功")
	_expect(loaded.unlock_tier == 3, "schema3 旧存档迁移到 unlock tier3")
	_expect(loaded.unlocked_reward_ids == MetaCatalog.get_unlocked_reward_ids(3), "schema3 旧存档获得完整兼容奖励池")
	for card_id: StringName in LEGACY_REWARD_IDS:
		_expect(loaded.get_deck_card_ids().has(card_id), "schema3 迁移保留旧卡 %s" % card_id)
	_expect(loaded.run_profile_id.begins_with("legacy-73103-"), "schema3 迁移生成稳定旧档案远征标识")
	_expect(loaded.current_node == 4 and loaded.visited_node_ids.size() == 4, "schema3 固定地图检查点投影到新版合法路径并保留深度")
	_expect(not loaded.available_node_ids.is_empty(), "schema3 迁移后继续节点来自新版当前连接")
	_expect(loaded.map_graph.validate().is_empty(), "schema3 迁移后的随机地图保持合法")


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.flush()
	file.close()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
