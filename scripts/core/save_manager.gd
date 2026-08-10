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
	var staged_file: FileAccess = FileAccess.open(temp_path, FileAccess.READ)
	if staged_file == null:
		last_error = "无法读取临时存档：%s" % error_string(FileAccess.get_open_error())
		return false
	var staged_text: String = staged_file.get_as_text()
	staged_file.close()
	var final_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if final_file == null:
		last_error = "无法替换正式存档：%s" % error_string(FileAccess.get_open_error())
		return false
	final_file.store_string(staged_text)
	final_file.flush()
	final_file.close()
	if FileAccess.file_exists(temp_path):
		var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		if remove_error != OK:
			last_error = "存档已写入，但无法清理临时文件：%s" % error_string(remove_error)
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
	for path: String in [save_path, _temp_path()]:
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
	if not FileAccess.file_exists(save_path):
		return {"valid": false, "error": "没有可用存档", "saved_at_unix": 0}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
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
	if not _is_json_integer(envelope["run_schema"]) or int(envelope["run_schema"]) != RunModel.SCHEMA_VERSION:
		return {"valid": false, "error": "远征版本不兼容：run_schema应为%d" % RunModel.SCHEMA_VERSION, "saved_at_unix": 0}
	if not _is_json_integer(envelope["saved_at_unix"]) or int(envelope["saved_at_unix"]) < 0:
		return {"valid": false, "error": "saved_at_unix无效", "saved_at_unix": 0}
	if typeof(envelope["run"]) != TYPE_DICTIONARY:
		return {"valid": false, "error": "run字段必须是对象", "saved_at_unix": int(envelope["saved_at_unix"])}
	return {
		"valid": true,
		"error": "",
		"saved_at_unix": int(envelope["saved_at_unix"]),
		"run": envelope["run"],
	}


func _temp_path() -> String:
	if save_path.ends_with(".json"):
		return save_path.trim_suffix(".json") + ".tmp"
	return save_path + ".tmp"


static func _is_json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var float_value: float = float(value)
	return is_finite(float_value) and float_value == floor(float_value)
