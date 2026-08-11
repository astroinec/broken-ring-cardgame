class_name ProfileManager
extends RefCounted


const PROFILE_SCHEMA: int = 1
const DEFAULT_PROFILE_PATH: String = "user://broken_ring_profile_v1.json"
const REQUIRED_FIELDS: Array[String] = [
	"profile_schema", "runs_started", "boss_reached", "wins", "read_original_wins",
	"highest_depth", "unlock_tier", "recent_event_ids",
]

var profile_path: String = DEFAULT_PROFILE_PATH
var last_error: String = ""
var last_new_unlock_ids: Array[StringName] = []


func _init(p_profile_path: String = DEFAULT_PROFILE_PATH) -> void:
	profile_path = p_profile_path


static func default_profile() -> Dictionary:
	return {
		"profile_schema": PROFILE_SCHEMA,
		"runs_started": 0,
		"boss_reached": 0,
		"wins": 0,
		"read_original_wins": 0,
		"highest_depth": 0,
		"unlock_tier": 0,
		"recent_event_ids": [],
		"started_run_ids": [],
		"settled_run_ids": [],
		"run_settlements": {},
		"last_unlock_ids": [],
	}


func load_profile() -> Dictionary:
	last_error = ""
	_recover_backup_if_needed()
	if not FileAccess.file_exists(profile_path):
		return default_profile()
	var read_result: Dictionary = _read_profile()
	if not bool(read_result.get(&"valid", false)):
		last_error = str(read_result.get(&"error", "档案不可用"))
		return default_profile()
	return (read_result[&"profile"] as Dictionary).duplicate(true)


func inspect() -> Dictionary:
	last_error = ""
	_recover_backup_if_needed()
	if not FileAccess.file_exists(profile_path):
		return {&"exists": false, &"valid": true, &"error": "", &"profile": default_profile()}
	var result: Dictionary = _read_profile()
	if not bool(result.get(&"valid", false)):
		last_error = str(result.get(&"error", "档案不可用"))
		return {&"exists": true, &"valid": false, &"error": last_error, &"profile": default_profile()}
	return {&"exists": true, &"valid": true, &"error": "", &"profile": (result[&"profile"] as Dictionary).duplicate(true)}


func save_profile(profile: Dictionary) -> bool:
	last_error = ""
	var validation_error: String = _validate(profile)
	if not validation_error.is_empty():
		last_error = validation_error
		return false
	var temp_path: String = _temp_path()
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入临时档案：%s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	file.close()
	var staged: Dictionary = _read_profile_at(temp_path)
	if not bool(staged.get(&"valid", false)):
		last_error = "临时档案校验失败：%s" % staged.get(&"error", "未知错误")
		return false
	return _replace_staged_profile(temp_path)


func record_run_started(run_id: String) -> Dictionary:
	var profile: Dictionary = load_profile()
	var original_profile: Dictionary = profile.duplicate(true)
	var started: Array = profile.get("started_run_ids", [])
	if started.has(run_id):
		return profile
	started.append(run_id)
	profile["started_run_ids"] = _trim_history(started)
	profile["runs_started"] = int(profile["runs_started"]) + 1
	if not save_profile(profile):
		return original_profile
	return profile


func record_run_progress(
	run_id: String, highest_depth: int, reached_boss: bool, won: bool,
	read_original: bool, recent_event_ids: Array[StringName] = []
) -> Dictionary:
	last_new_unlock_ids.clear()
	var profile: Dictionary = load_profile()
	var original_profile: Dictionary = profile.duplicate(true)
	var settlements: Dictionary = profile.get("run_settlements", {}) as Dictionary
	var run_settlement: Dictionary = (settlements.get(run_id, {}) as Dictionary).duplicate(true)
	if won and bool(run_settlement.get("finished", false)):
		return profile
	if reached_boss and not won and bool(run_settlement.get("boss_reached", false)):
		return profile
	if not reached_boss and not won and int(run_settlement.get("highest_depth", 0)) >= highest_depth:
		return profile
	var old_tier: int = int(profile["unlock_tier"])
	profile["highest_depth"] = maxi(int(profile["highest_depth"]), clampi(highest_depth, 0, 9))
	if reached_boss and not bool(run_settlement.get("boss_reached", false)):
		profile["boss_reached"] = int(profile["boss_reached"]) + 1
	if won and not bool(run_settlement.get("finished", false)):
		profile["wins"] = int(profile["wins"]) + 1
	if won and read_original and not bool(run_settlement.get("read_original", false)):
		profile["read_original_wins"] = int(profile["read_original_wins"]) + 1
	if not recent_event_ids.is_empty():
		var recent: Array = []
		for event_id: StringName in recent_event_ids:
			if not recent.has(str(event_id)):
				recent.append(str(event_id))
		profile["recent_event_ids"] = recent.slice(maxi(0, recent.size() - 6))
	profile["unlock_tier"] = MetaCatalog.get_tier_for_progress(profile)
	var pending_unlock_ids: Array[StringName] = MetaCatalog.get_new_unlock_ids(old_tier, int(profile["unlock_tier"]))
	if not pending_unlock_ids.is_empty():
		profile["last_unlock_ids"] = []
		for card_id: StringName in pending_unlock_ids:
			(profile["last_unlock_ids"] as Array).append(str(card_id))
	run_settlement["highest_depth"] = maxi(int(run_settlement.get("highest_depth", 0)), clampi(highest_depth, 0, 9))
	if reached_boss:
		run_settlement["boss_reached"] = true
	if won:
		run_settlement["finished"] = true
	if won and read_original:
		run_settlement["read_original"] = true
	settlements[run_id] = run_settlement
	profile["run_settlements"] = settlements
	if not save_profile(profile):
		last_new_unlock_ids.clear()
		return original_profile
	last_new_unlock_ids = pending_unlock_ids
	return profile


func delete() -> bool:
	last_error = ""
	for path: String in [profile_path, _temp_path(), _backup_path()]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			last_error = "无法删除档案：%s" % error_string(remove_error)
			return false
	return true


func _read_profile() -> Dictionary:
	return _read_profile_at(profile_path)


func _read_profile_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {&"valid": false, &"error": "档案不存在"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {&"valid": false, &"error": "无法读取档案：%s" % error_string(FileAccess.get_open_error())}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return {&"valid": false, &"error": "档案JSON损坏：%s" % json.get_error_message()}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {&"valid": false, &"error": "档案顶层必须是对象"}
	var profile: Dictionary = json.data as Dictionary
	var validation_error: String = _validate(profile)
	if not validation_error.is_empty():
		return {&"valid": false, &"error": validation_error}
	var normalized: Dictionary = profile.duplicate(true)
	for field: String in ["profile_schema", "runs_started", "boss_reached", "wins", "read_original_wins", "highest_depth", "unlock_tier"]:
		normalized[field] = int(normalized[field])
	if not normalized.has("started_run_ids"):
		normalized["started_run_ids"] = []
	if not normalized.has("settled_run_ids"):
		normalized["settled_run_ids"] = []
	if not normalized.has("last_unlock_ids"):
		normalized["last_unlock_ids"] = []
	if not normalized.has("run_settlements"):
		normalized["run_settlements"] = {}
	return {&"valid": true, &"error": "", &"profile": normalized}


func _validate(profile: Dictionary) -> String:
	for field: String in REQUIRED_FIELDS:
		if not profile.has(field):
			return "档案缺少字段：%s" % field
	for field: String in ["profile_schema", "runs_started", "boss_reached", "wins", "read_original_wins", "highest_depth", "unlock_tier"]:
		if not _is_json_integer(profile[field]):
			return "档案字段%s必须是整数" % field
	if int(profile["profile_schema"]) != PROFILE_SCHEMA:
		return "档案版本不兼容"
	if int(profile["highest_depth"]) < 0 or int(profile["highest_depth"]) > 9:
		return "档案最高层级超出范围"
	if int(profile["unlock_tier"]) < 0 or int(profile["unlock_tier"]) > 3:
		return "档案解锁层级超出范围"
	for field: String in ["runs_started", "boss_reached", "wins", "read_original_wins"]:
		if int(profile[field]) < 0:
			return "档案计数不能为负数"
	for field: String in ["recent_event_ids", "started_run_ids", "settled_run_ids", "last_unlock_ids"]:
		if profile.has(field) and typeof(profile[field]) != TYPE_ARRAY:
			return "档案字段%s必须是数组" % field
	if profile.has("run_settlements") and typeof(profile["run_settlements"]) != TYPE_DICTIONARY:
		return "档案字段run_settlements必须是对象"
	return ""


func _temp_path() -> String:
	return profile_path.trim_suffix(".json") + ".tmp" if profile_path.ends_with(".json") else profile_path + ".tmp"


func _backup_path() -> String:
	return profile_path.trim_suffix(".json") + ".bak" if profile_path.ends_with(".json") else profile_path + ".bak"


func _recover_backup_if_needed() -> void:
	var backup_path: String = _backup_path()
	if not FileAccess.file_exists(backup_path):
		return
	if FileAccess.file_exists(profile_path):
		var current: Dictionary = _read_profile_at(profile_path)
		if bool(current.get(&"valid", false)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
			return
	var backup: Dictionary = _read_profile_at(backup_path)
	if not bool(backup.get(&"valid", false)):
		return
	if _copy_file(backup_path, profile_path):
		var restored: Dictionary = _read_profile_at(profile_path)
		if bool(restored.get(&"valid", false)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))


func _replace_staged_profile(temp_path: String) -> bool:
	var final_absolute: String = ProjectSettings.globalize_path(profile_path)
	var temp_absolute: String = ProjectSettings.globalize_path(temp_path)
	var backup_path: String = _backup_path()
	var backup_absolute: String = ProjectSettings.globalize_path(backup_path)
	var had_previous: bool = FileAccess.file_exists(profile_path)
	if FileAccess.file_exists(backup_path):
		var stale_error: Error = DirAccess.remove_absolute(backup_absolute)
		if stale_error != OK:
			last_error = "无法清理档案备份：%s" % error_string(stale_error)
			return false
	if had_previous and not _copy_file(profile_path, backup_path):
		last_error = "无法备份现有档案"
		return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, final_absolute)
	if replace_error != OK and had_previous:
		# 某些平台不允许 rename 覆盖现有文件；先把正式文件移到备份名，
		# 再把已校验临时文件移入。第二步失败时立即恢复原文件。
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_absolute)
		var preserve_error: Error = DirAccess.rename_absolute(final_absolute, backup_absolute)
		if preserve_error == OK:
			replace_error = DirAccess.rename_absolute(temp_absolute, final_absolute)
			if replace_error != OK:
				DirAccess.rename_absolute(backup_absolute, final_absolute)
	if replace_error != OK:
		last_error = "无法原子替换档案：%s" % error_string(replace_error)
		return false

	var verified: Dictionary = _read_profile_at(profile_path)
	if not bool(verified.get(&"valid", false)):
		var invalid_absolute: String = ProjectSettings.globalize_path(temp_path)
		DirAccess.rename_absolute(final_absolute, invalid_absolute)
		if had_previous and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(invalid_absolute)
		last_error = "正式档案写入后校验失败：%s" % verified.get(&"error", "未知错误")
		return false
	if FileAccess.file_exists(backup_path):
		var cleanup_error: Error = DirAccess.remove_absolute(backup_absolute)
		if cleanup_error != OK:
			push_warning("档案已保存，但无法清理备份：%s" % error_string(cleanup_error))
	return true


static func _copy_file(source_path: String, destination_path: String) -> bool:
	var source: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var bytes: PackedByteArray = source.get_buffer(source.get_length())
	source.close()
	var destination: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
	if destination == null:
		return false
	destination.store_buffer(bytes)
	destination.flush()
	destination.close()
	return true


static func _trim_history(values: Array) -> Array:
	return values.slice(maxi(0, values.size() - 64))


static func _is_json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number)
