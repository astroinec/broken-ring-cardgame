extends SceneTree

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	_expect(main.screen_root.get_child_count() == 1, "main menu is shown on startup")
	main._start_test_level()
	await process_frame
	_expect(main.is_test_mode, "test level uses independent mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MAX, "test level opens full-mechanic encounter")
	_expect(main.model.is_mechanic_unlocked(&"missing_name"), "test level unlocks all implemented mechanics")
	main._restart_run()
	await process_frame
	_expect(not main.is_test_mode, "main route is separate from test mode")
	_expect(main.current_stage == CombatModel.TUTORIAL_STAGE_MIN, "main route begins at first path node")
	for stage: int in range(1, CombatModel.TUTORIAL_STAGE_MAX + 1):
		var model: CombatModel = CombatModel.new()
		model.start_battle(73103, stage)
		_expect(not model.tutorial_stage_title.contains("教学"), "path %d title is diegetic" % stage)
		_expect(not model.tutorial_hint.contains("教学"), "path %d context text is diegetic" % stage)
	main.queue_free()
	if failures == 0:
		print("PASS: main route and test-level flow checks")
		quit(0)
	else:
		push_error("FAIL: %d flow checks failed" % failures)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
