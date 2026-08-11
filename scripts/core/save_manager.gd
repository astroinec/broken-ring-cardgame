class_name SaveManager
extends RefCounted


const SAVE_SCHEMA: int = 1
const DEFAULT_SAVE_PATH: String = "user://broken_ring_run_v1.json"

var save_path: String = DEFAULT_SAVE_PATH
var last_error: String = ""
var last_summary: String = ""
var last_saved_at_unix: int = 0


func _init(p_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = p_save_path


func save_run(run: RunModel) -> bool:
	last_error = ""
	last_summary = ""
	last_saved_at_unix = 0
	if run == null:
		last_error = "无法保存空远征"
		return false
	var saved_at_unix: int = int(Time.get_unix_time_from_system())
	var envelope: Dictionary = {
		"save_schema": SAVE_SCHEMA,
		"run_schema": RunModel.SCHEMA_VERSION,
		"saved_at_unix": saved_at_unix,
		"run": run.to_save_dict(),
	}
	var json_text: String = JSON.stringify(envelope, "\t")
	var temp_path: String = _temp_path()
	var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		last_error = "无法写入临时存档：%s" % error_string(FileAccess.get_open_error())
		return false
	temp_file.store_string(json_text)
	temp_file.flush()
	temp_file.close()
	var staged: Dictionary = _read_envelope_at(temp_path)
	if not bool(staged.get("valid", false)):
		last_error = "临时存档校验失败：%s" % staged.get("error", "未知错误")
		return false
	if not _replace_staged_save(temp_path):
		return false
	last_summary = run.get_summary_text()
	last_saved_at_unix = saved_at_unix
	return true


## 目标RunModel只会在完整解析与校验成功后改变。
func load_run(run: RunModel) -> bool:
	last_error = ""
	last_summary = ""
	last_saved_at_unix = 0
	if run == null:
		last_error = "无法加载到空远征"
		return false
	var read_result: Dictionary = _read_envelope()
	if not bool(read_result.get("valid", false)):
		last_error = str(read_result.get("error", "存档不可用"))
		return false
	var load_error: String = run.load_from_save_dict(read_result["run"] as Dictionary)
	if not load_error.is_empty():
		last_error = load_error
		return false
	last_summary = run.get_summary_text()
	last_saved_at_unix = int(read_result["saved_at_unix"])
	return true


func inspect() -> Dictionary:
	last_error = ""
	last_summary = ""
	last_saved_at_unix = 0
	if not FileAccess.file_exists(save_path):
		return {
			"exists": false,
			"valid": false,
			"error": "",
			"summary": "",
			"saved_at_unix": 0,
		}
	var read_result: Dictionary = _read_envelope()
	if not bool(read_result.get("valid", false)):
		last_error = str(read_result.get("error", "存档不可用"))
		return {
			"exists": true,
			"valid": false,
			"error": last_error,
			"summary": "",
			"saved_at_unix": int(read_result.get("saved_at_unix", 0)),
		}
	var candidate: RunModel = RunModel.new()
	var load_error: String = candidate.load_from_save_dict(read_result["run"] as Dictionary)
	if not load_error.is_empty():
		last_error = load_error
		return {
			"exists": true,
			"valid": false,
			"error": last_error,
			"summary": "",
			"saved_at_unix": int(read_result["saved_at_unix"]),
		}
	last_summary = candidate.get_summary_text()
	last_saved_at_unix = int(read_result["saved_at_unix"])
	return {
		"exists": true,
		"valid": true,
		"error": "",
		"summary": last_summary,
		"saved_at_unix": last_saved_at_unix,
	}


func delete() -> bool:
	last_error = ""
	for path: String in [save_path, _temp_path(), _backup_path()]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			last_error = "无法删除存档：%s" % error_string(remove_error)
			return false
	last_summary = ""
	last_saved_at_unix = 0
	return true


func _read_envelope() -> Dictionary:
	_recover_backup_if_needed()
	return _read_envelope_at(save_path)


func _read_envelope_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "error": "没有可用存档", "saved_at_unix": 0}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": "无法读取存档：%s" % error_string(FileAccess.get_open_error()), "saved_at_unix": 0}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return {"valid": false, "error": "存档JSON损坏：%s" % json.get_error_message(), "saved_at_unix": 0}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"valid": false, "error": "存档顶层必须是对象", "saved_at_unix": 0}
	var envelope: Dictionary = parsed as Dictionary
	for field: String in ["save_schema", "run_schema", "saved_at_unix", "run"]:
		if not envelope.has(field):
			return {"valid": false, "error": "存档缺少顶层字段：%s" % field, "saved_at_unix": 0}
	if not _is_json_integer(envelope["save_schema"]) or int(envelope["save_schema"]) != SAVE_SCHEMA:
		return {"valid": false, "error": "存档版本不兼容：save_schema应为%d" % SAVE_SCHEMA, "saved_at_unix": 0}
	if not _is_json_integer(envelope["run_schema"]):
		return {"valid": false, "error": "远征版本字段无效", "saved_at_unix": 0}
	var run_schema: int = int(envelope["run_schema"])
	if run_schema != RunModel.SCHEMA_VERSION and run_schema != 3:
		return {"valid": false, "error": "远征版本不兼容：仅支持run_schema 3或%d" % RunModel.SCHEMA_VERSION, "saved_at_unix": 0}
	if not _is_json_integer(envelope["saved_at_unix"]) or int(envelope["saved_at_unix"]) < 0:
		return {"valid": false, "error": "saved_at_unix无效", "saved_at_unix": 0}
	if typeof(envelope["run"]) != TYPE_DICTIONARY:
		return {"valid": false, "error": "run字段必须是对象", "saved_at_unix": int(envelope["saved_at_unix"])}
	var run_data: Dictionary = (envelope["run"] as Dictionary).duplicate(true)
	if run_schema == 3:
		run_data["unlock_tier"] = 3
		run_data["unlocked_reward_ids"] = RunModel._string_name_array_to_strings(MetaCatalog.get_unlocked_reward_ids(3))
		run_data["run_seen_reward_ids"] = []
		run_data["run_profile_id"] = "legacy-%d-%d" % [int(run_data.get("seed_value", 1)), int(envelope["saved_at_unix"])]
		_migrate_schema3_map_checkpoint(run_data)
	return {
		"valid": true,
		"error": "",
		"saved_at_unix": int(envelope["saved_at_unix"]),
		"run": run_data,
		"migrated_from_run_schema": run_schema,
	}


static func _migrate_schema3_map_checkpoint(run_data: Dictionary) -> void:
	# schema3使用固定全互连地图。schema4按同一seed生成稀疏模板，因此旧节点集合
	# 不能直接校验；保留已完成深度和远征资源，并投影到新版的一条合法路径。
	var graph: MapGraph = MapGraph.new()
	graph.generate(maxi(1, int(run_data.get("seed_value", 1))))
	var completed_depth: int = clampi(int(run_data.get("current_node", 0)), 0, 9)
	var old_visited: Array = run_data.get("visited_node_ids", []) as Array
	var visited: Array[StringName] = []
	var current_id: StringName = &""
	for depth: int in range(1, completed_depth + 1):
		var candidates: Array[MapNode] = graph.get_reachable_nodes(current_id)
		if candidates.is_empty():
			break
		var chosen: MapNode = candidates[0]
		for raw_old_id: Variant in old_visited:
			var old_id: StringName = StringName(str(raw_old_id))
			if str(old_id).begins_with("d%02d_" % depth):
				for candidate: MapNode in candidates:
					if candidate.id == old_id:
						chosen = candidate
						break
				break
		chosen.completed = true
		chosen.revealed = true
		visited.append(chosen.id)
		current_id = chosen.id

	var available: Array[StringName] = []
	if completed_depth <= 0:
		available = graph.start_node_ids.duplicate()
	elif completed_depth < 9:
		var current: MapNode = graph.get_node(current_id)
		if current != null:
			available = current.connections.duplicate()
	var revealed: Array[StringName] = visited.duplicate()
	for node_id: StringName in available:
		if not revealed.has(node_id):
			revealed.append(node_id)
	run_data["current_node_id"] = str(current_id)
	run_data["visited_node_ids"] = RunModel._string_name_array_to_strings(visited)
	run_data["available_node_ids"] = RunModel._string_name_array_to_strings(available)
	run_data["completed_node_ids"] = RunModel._string_name_array_to_strings(visited)
	run_data["revealed_node_ids"] = RunModel._string_name_array_to_strings(revealed)


func _temp_path() -> String:
	if save_path.ends_with(".json"):
		return save_path.trim_suffix(".json") + ".tmp"
	return save_path + ".tmp"


func _backup_path() -> String:
	if save_path.ends_with(".json"):
		return save_path.trim_suffix(".json") + ".bak"
	return save_path + ".bak"


func _recover_backup_if_needed() -> void:
	var backup_path: String = _backup_path()
	if not FileAccess.file_exists(backup_path):
		return
	if FileAccess.file_exists(save_path):
		var current: Dictionary = _read_envelope_at(save_path)
		if bool(current.get("valid", false)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
			return
	var backup: Dictionary = _read_envelope_at(backup_path)
	if not bool(backup.get("valid", false)):
		return
	if _copy_file(backup_path, save_path):
		var restored: Dictionary = _read_envelope_at(save_path)
		if bool(restored.get("valid", false)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))


func _replace_staged_save(temp_path: String) -> bool:
	var final_absolute: String = ProjectSettings.globalize_path(save_path)
	var temp_absolute: String = ProjectSettings.globalize_path(temp_path)
	var backup_path: String = _backup_path()
	var backup_absolute: String = ProjectSettings.globalize_path(backup_path)
	var had_previous: bool = FileAccess.file_exists(save_path)
	if FileAccess.file_exists(backup_path):
		var stale_error: Error = DirAccess.remove_absolute(backup_absolute)
		if stale_error != OK:
			last_error = "无法清理存档备份：%s" % error_string(stale_error)
			return false
	if had_previous and not _copy_file(save_path, backup_path):
		last_error = "无法备份现有存档"
		return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, final_absolute)
	if replace_error != OK and had_previous:
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_absolute)
		var preserve_error: Error = DirAccess.rename_absolute(final_absolute, backup_absolute)
		if preserve_error == OK:
			replace_error = DirAccess.rename_absolute(temp_absolute, final_absolute)
			if replace_error != OK:
				DirAccess.rename_absolute(backup_absolute, final_absolute)
	if replace_error != OK:
		last_error = "无法原子替换存档：%s" % error_string(replace_error)
		return false

	var verified: Dictionary = _read_envelope_at(save_path)
	if not bool(verified.get("valid", false)):
		DirAccess.rename_absolute(final_absolute, temp_absolute)
		if had_previous and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(temp_absolute)
		last_error = "正式存档写入后校验失败：%s" % verified.get("error", "未知错误")
		return false
	if FileAccess.file_exists(backup_path):
		var cleanup_error: Error = DirAccess.remove_absolute(backup_absolute)
		if cleanup_error != OK:
			push_warning("存档已保存，但无法清理备份：%s" % error_string(cleanup_error))
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


static func _is_json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var float_value: float = float(value)
	return is_finite(float_value) and float_value == floor(float_value)
