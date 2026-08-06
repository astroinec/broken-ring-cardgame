extends SceneTree

const RunModelScript: Script = preload("res://scripts/core/run_model.gd")

var failures: int = 0


func _init() -> void:
	_test_card_catalog()
	_test_deterministic_rewards()
	_test_choose_and_skip_reward()
	_test_reward_enters_later_battle()
	_test_deterministic_event()
	_test_event_branches()
	if failures == 0:
		print("PASS: all run, reward, and event checks")
		quit(0)
	else:
		push_error("FAIL: %d run checks failed" % failures)
		quit(1)


func _test_card_catalog() -> void:
	_expect(CardCatalog.REWARD_IDS.size() == 15, "catalog exposes fifteen reward cards")
	for card_id: StringName in CardCatalog.REWARD_IDS:
		_expect(CardCatalog.has_card(card_id), "catalog contains %s" % card_id)
		var definition: Dictionary = CardCatalog.get_definition(card_id)
		_expect(not str(definition.get(&"title", "")).is_empty(), "%s has Chinese title" % card_id)
		_expect(not str(definition.get(&"description", "")).is_empty(), "%s has rules text" % card_id)
		_expect(not str(definition.get(&"rarity", "")).is_empty(), "%s has rarity" % card_id)
		_expect(not str(definition.get(&"flavor", "")).is_empty(), "%s has flavor text" % card_id)


func _test_deterministic_rewards() -> void:
	var first = RunModelScript.new()
	var second = RunModelScript.new()
	first.start_run(73103)
	second.start_run(73103)
	var first_choices: Array[StringName] = first.generate_reward_choices(3)
	var second_choices: Array[StringName] = second.generate_reward_choices(3)
	_expect(first_choices == second_choices, "same seed and stage produce same rewards")
	_expect(first_choices.size() == 3, "reward contains three choices")
	_expect(first_choices[0] != first_choices[1] and first_choices[1] != first_choices[2] and first_choices[0] != first_choices[2], "reward choices are unique")
	var stage_three_pool: Array[StringName] = [&"broken_sentence", &"blank_space", &"rift_slash", &"forced_stability"]
	for card_id: StringName in first_choices:
		_expect(stage_three_pool.has(card_id), "stage three reward does not expose later keywords: %s" % card_id)


func _test_choose_and_skip_reward() -> void:
	var chosen = RunModelScript.new()
	chosen.start_run(73103)
	var starting_size: int = chosen.deck_instances.size()
	var choices: Array[StringName] = chosen.generate_reward_choices(3)
	_expect(chosen.choose_reward(1), "reward choice succeeds")
	_expect(chosen.deck_instances.size() == starting_size + 1, "chosen reward grows deck")
	_expect(chosen.get_acquired_card_ids().has(choices[1]), "chosen reward is recorded as acquired")
	var skipped = RunModelScript.new()
	skipped.start_run(73103)
	skipped.generate_reward_choices(3)
	_expect(skipped.skip_reward(), "reward can be skipped")
	_expect(skipped.deck_instances.size() == starting_size, "skipping does not grow deck")


func _test_reward_enters_later_battle() -> void:
	var run = RunModelScript.new()
	run.start_run(73103)
	var choices: Array[StringName] = run.generate_reward_choices(3)
	run.choose_reward(0)
	var battle: CombatModel = CombatModel.new()
	battle.start_battle(73108, 5, run.get_acquired_card_ids())
	var all_ids: Array[StringName] = []
	for pile in [battle.draw_pile, battle.hand, battle.discard_pile]:
		for card: CardData in pile:
			all_ids.append(card.id)
	_expect(all_ids.has(choices[0]), "reward card enters later battle deck")


func _test_deterministic_event() -> void:
	var first = RunModelScript.new()
	var second = RunModelScript.new()
	first.start_run(73103)
	second.start_run(73103)
	_expect(first.begin_event() == second.begin_event(), "same seed selects same event")
	_expect(RunModel.EVENT_IDS.has(first.selected_event_id), "selected event is from approved event pool")


func _test_event_branches() -> void:
	for event_id: StringName in RunModel.EVENT_IDS:
		var run = RunModelScript.new()
		run.start_run(73103)
		run.selected_event_id = event_id
		var options: Array[Dictionary] = run.get_event_options(event_id)
		_expect(options.size() >= 2, "%s has at least two choices" % event_id)
		_expect(run.apply_event_choice(0, event_id), "%s first branch resolves" % event_id)
		_expect(run.event_resolved, "%s marks event resolved" % event_id)
		_expect(not run.event_outcome.is_empty(), "%s produces outcome text" % event_id)
	var gated = RunModelScript.new()
	gated.start_run(73103)
	gated.selected_event_id = &"authorless_book"
	var gated_options: Array[Dictionary] = gated.get_event_options()
	_expect(not bool(gated_options[2][&"enabled"]), "conditional event option is disabled without relic")
	_expect(not gated.apply_event_choice(2), "disabled event option cannot resolve")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
