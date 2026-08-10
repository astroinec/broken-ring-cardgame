extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_authorless_book()
	_test_seventh_dock()
	_test_calibration_station()
	_test_speaking_for_you()
	_test_deleted_funeral()
	_test_definition_tax()
	_test_evidence_catalog()
	if failures == 0:
		print("PASS: all six-event rule and evidence checks")
		quit(0)
	else:
		push_error("FAIL: %d event checks failed" % failures)
		quit(1)


func _test_authorless_book() -> void:
	var obey: RunModel = _event_run(&"authorless_book")
	var hp_before: int = obey.player_hp
	var deck_before: int = obey.deck_instances.size()
	_expect(obey.apply_event_choice(0), "authorless obey resolves")
	_expect(obey.player_hp == hp_before - 6 and obey.deck_instances.size() == deck_before + 1, "authorless obey loses hp and adds a card")
	_expect(obey.get_deck_card_ids().has(&"prewritten_ending"), "authorless obey adds prewritten ending")

	var tear: RunModel = _event_run(&"authorless_book")
	_expect(tear.apply_event_choice(1), "authorless tear resolves")
	_expect(tear.ink_crystals == 60 and tear.get_deck_card_ids().has(&"redaction"), "authorless tear grants ink and redaction")

	var name: RunModel = _event_run(&"authorless_book")
	_expect(not bool(name.get_event_options()[2][&"enabled"]), "authorless hidden option requires bookplate")
	_expect(not name.apply_event_choice(2), "authorless hidden option rejects missing relic")
	name.relics.append(&"wordless_bookplate")
	_expect(name.apply_event_choice(2), "authorless hidden option resolves with bookplate")
	_expect(name.has_evidence_id(&"alternate_name_index"), "authorless hidden option records evidence id")
	var context: Dictionary = name.consume_current_battle_context()
	_expect(int(context[&"initial_draw_bonus"]) == 2, "authorless hidden option grants next-battle opening draw")


func _test_seventh_dock() -> void:
	var inspect: RunModel = _event_run(&"seventh_dock")
	inspect.player_hp = 50
	_expect(inspect.apply_event_choice(0), "dock manifest resolves")
	_expect(inspect.player_hp == 58 and inspect.has_evidence_id(&"nine_redacted_return_records"), "dock manifest heals and records nine returns")

	var bell: RunModel = _event_run(&"seventh_dock")
	_expect(bell.apply_event_choice(1), "dock bell resolves")
	_expect(not bell.relics.has(&"expired_return_bell"), "dock bell reward is not granted before battle victory")
	bell.available_node_ids = [&"d01_00"]
	_expect(bell.enter_node(&"d01_00"), "dock bell run enters the next battle")
	var first_context: Dictionary = bell.consume_current_battle_context()
	var retry_context: Dictionary = bell.consume_current_battle_context()
	_expect(int(first_context[&"enemy_strength"]) == 2 and first_context == retry_context, "dock bell strength modifier survives retry without double consumption")
	_expect(bell.record_current_battle_victory(), "dock bell next battle settles once")
	_expect(bell.relics.has(&"expired_return_bell") and bell.has_evidence_id(&"overdue_bell_record"), "dock bell victory grants relic and sourced evidence")
	var relic_count: int = bell.relics.count(&"expired_return_bell")
	_expect(not bell.record_current_battle_victory() and bell.relics.count(&"expired_return_bell") == relic_count, "dock bell reward cannot repeat")

	var archive: RunModel = _event_run(&"seventh_dock")
	_expect(not archive.apply_event_choice(2), "dock archive requires stamp")
	archive.relics.append(&"seventh_dock_stamp")
	_expect(archive.apply_event_choice(2) and archive.has_evidence_id(&"old_dock_recovery_process"), "dock archive records old process with stamp")


func _test_calibration_station() -> void:
	var current: RunModel = _event_run(&"calibration_station")
	current.player_hp = 30
	_expect(current.apply_event_choice(0), "calibration current id resolves")
	_expect(current.player_hp == 50 and current.has_evidence_id(&"repeated_calibration_parameters"), "calibration current id heals and records parameters")
	var context: Dictionary = current.consume_current_battle_context()
	_expect(int(context[&"initial_missing_name_law"]) == 2, "calibration current id applies two law missing-name stacks")

	var previous: RunModel = _event_run(&"calibration_station")
	_expect(previous.apply_event_choice(1), "calibration previous id resolves")
	_expect(previous.ink_crystals == 80 and previous.has_evidence_id(&"obscured_asset_log"), "calibration previous id grants ink and asset log")

	var refuse_a: RunModel = _event_run(&"calibration_station", 88001)
	var refuse_b: RunModel = _event_run(&"calibration_station", 88001)
	_expect(refuse_a.apply_event_choice(2) and refuse_b.apply_event_choice(2), "calibration refusal resolves twice")
	_expect(refuse_a.player_max_hp == 65 and refuse_a.get_deck_card_ids() == refuse_b.get_deck_card_ids(), "calibration refusal loses max hp and reproduces rare card")


func _test_speaking_for_you() -> void:
	var talk_a: RunModel = _event_run(&"speaking_for_you", 99001)
	var talk_b: RunModel = _event_run(&"speaking_for_you", 99001)
	_expect(talk_a.apply_event_choice(0) and talk_b.apply_event_choice(0), "speaking conversation resolves deterministically")
	var upgraded_a: Array[int] = _upgraded_instance_ids(talk_a)
	var upgraded_b: Array[int] = _upgraded_instance_ids(talk_b)
	_expect(upgraded_a.size() == 1 and upgraded_a == upgraded_b, "speaking conversation upgrades one concrete reproducible instance")
	var context: Dictionary = talk_a.consume_current_battle_context()
	_expect(int(context[&"instability_threshold_delta"]) == -1, "speaking conversation lowers the next battle threshold")
	var battle: CombatModel = CombatModel.new()
	battle.start_battle(99001, 6, [], &"word_eater", talk_a.get_relic_ids(), talk_a.get_deck_instances(), 70, 70, context)
	_expect(battle.instability_threshold == 9, "combat consumes the event threshold delta")

	var attack: RunModel = _event_run(&"speaking_for_you")
	var hp_before: int = attack.player_hp
	_expect(attack.apply_event_choice(1), "speaking attack resolves")
	_expect(attack.player_hp == hp_before - 8 and attack.relics.has(&"echo_hyoid"), "speaking attack grants hyoid and costs hp")

	var silence: RunModel = _event_run(&"speaking_for_you")
	var deck_before: int = silence.deck_instances.size()
	_expect(silence.apply_event_choice(2), "speaking silence opens selection")
	_expect(not silence.event_resolved and silence.get_pending_event_candidates().size() == 8, "speaking silence exposes only eight basic attack/defense instances")
	_expect(silence.cancel_event_selection(), "speaking silence selection can cancel")
	_expect(silence.deck_instances.size() == deck_before and not silence.event_resolved, "speaking silence cancel is trace-free")
	_expect(silence.apply_event_choice(2), "speaking silence can reopen after cancel")
	var chosen_id: int = int(silence.get_pending_event_candidates()[0][&"instance_id"])
	_expect(silence.resolve_event_selection(chosen_id), "speaking silence resolves selected instance")
	_expect(silence.event_resolved and silence.deck_instances.size() == deck_before - 1 and not silence.has_deck_instance(chosen_id), "speaking silence removes exactly the chosen instance")


func _test_deleted_funeral() -> void:
	var attend: RunModel = _event_run(&"deleted_funeral")
	var deck_before: int = attend.deck_instances.size()
	_expect(attend.apply_event_choice(0), "funeral attendance resolves")
	_expect(attend.player_max_hp == 75 and attend.deck_instances.size() == deck_before + 1 and attend.get_deck_card_ids().has(&"old_wound"), "funeral attendance adds max hp and old wound")

	var erase: RunModel = _event_run(&"deleted_funeral")
	var hp_before: int = erase.player_hp
	var erase_deck_before: int = erase.deck_instances.size()
	_expect(erase.apply_event_choice(1), "funeral erasure opens selection")
	_expect(erase.get_pending_event_candidates().size() == erase_deck_before, "funeral erasure exposes every deck instance")
	var chosen_id: int = int(erase.get_pending_event_candidates()[-1][&"instance_id"])
	_expect(erase.resolve_event_selection(chosen_id), "funeral erasure resolves selected instance")
	_expect(erase.player_hp == hp_before - 10 and erase.deck_instances.size() == erase_deck_before - 1, "funeral erasure removes one card and loses current hp")

	var autopsy: RunModel = _event_run(&"deleted_funeral")
	_expect(not autopsy.apply_event_choice(2), "funeral autopsy requires blank epitaph")
	autopsy.relics.append(&"blank_epitaph")
	_expect(autopsy.apply_event_choice(2) and autopsy.has_evidence_id(&"nonexistent_autopsy"), "funeral autopsy records evidence with epitaph")


func _test_definition_tax() -> void:
	var pain: RunModel = _event_run(&"definition_tax")
	_expect(pain.apply_event_choice(0), "definition pain resolves")
	_expect(pain.player_max_hp == 66 and pain.fracture_damage_override == 5, "definition pain lowers max hp and persists fracture override")
	var context: Dictionary = pain.consume_current_battle_context()
	var battle: CombatModel = CombatModel.new()
	battle.start_battle(10101, 6, [], &"word_eater", pain.get_relic_ids(), pain.get_deck_instances(), pain.player_hp, pain.player_max_hp, context)
	battle.instability = battle.instability_threshold
	var hp_before: int = battle.player_hp
	battle._check_fracture()
	_expect(battle.player_hp == hp_before - 5, "definition pain changes fracture damage from eight to five")
	_expect(int(pain.consume_current_battle_context()[&"fracture_damage_override"]) == 5, "definition pain remains active for later expedition battles")

	var memory: RunModel = _event_run(&"definition_tax")
	memory.relics.append(&"wordless_bookplate")
	memory.selected_event_id = &"authorless_book"
	memory.apply_event_choice(2)
	memory.selected_event_id = &"definition_tax"
	memory.event_resolved = false
	_expect(memory.apply_event_choice(1), "definition memory resolves")
	_expect(memory.ink_crystals == 120 and memory.event_history_hints_hidden, "definition memory grants ink and hides only history hints")
	_expect(memory.has_evidence_id(&"alternate_name_index") and not memory.evidence_records.is_empty(), "definition memory preserves evidence records")

	var obey_a: RunModel = _event_run(&"definition_tax", 20202)
	var obey_b: RunModel = _event_run(&"definition_tax", 20202)
	_expect(obey_a.apply_event_choice(2) and obey_b.apply_event_choice(2), "definition obedience resolves reproducibly")
	_expect(obey_a.institution_relation == -1 and obey_a.get_deck_card_ids() == obey_b.get_deck_card_ids(), "definition obedience grants deterministic rare card and relation loss")

	var refuse: RunModel = _event_run(&"definition_tax")
	refuse.available_node_ids = [&"d02_01"]
	_expect(refuse.enter_node(&"d02_01"), "definition refusal uses a formal event node")
	refuse.selected_event_id = &"definition_tax"
	_expect(refuse.apply_event_choice(3, &"definition_tax"), "definition refusal starts event battle")
	_expect(refuse.is_event_battle_pending() and refuse.get_event_battle_enemy_id() == &"reinforced_word_eater", "definition refusal exposes the honest single reinforced enemy")
	var event_battle: CombatModel = CombatModel.new()
	event_battle.start_battle(30303, 6, [], refuse.get_event_battle_enemy_id(), refuse.get_relic_ids(), refuse.get_deck_instances(), 70, 70, refuse.consume_current_battle_context())
	_expect(event_battle.get_enemy_count() == 1 and event_battle.enemy_id == &"reinforced_word_eater", "definition event combat never pretends to contain two enemies")
	_expect(refuse.record_event_battle_victory(), "definition event victory settles reward")
	_expect(refuse.event_resolved and refuse.relics.has(&"wordless_bookplate"), "definition event victory resolves event and grants bookplate")
	_expect(refuse.complete_current_node(), "definition event victory returns through map node protocol")
	var relic_count: int = refuse.relics.count(&"wordless_bookplate")
	_expect(not refuse.record_event_battle_victory() and refuse.relics.count(&"wordless_bookplate") == relic_count, "definition event reward cannot repeat")


func _test_evidence_catalog() -> void:
	for raw_id: Variant in EvidenceCatalog.DEFINITIONS.keys():
		var record: Dictionary = EvidenceCatalog.get_record(raw_id as StringName)
		_expect(not str(record[&"title"]).is_empty(), "%s evidence has title" % raw_id)
		_expect(not str(record[&"source"]).is_empty(), "%s evidence has source" % raw_id)
		_expect(not str(record[&"description"]).is_empty(), "%s evidence has description" % raw_id)


func _event_run(event_id: StringName, seed_value: int = 73103) -> RunModel:
	var run: RunModel = RunModel.new()
	run.start_run(seed_value)
	run.selected_event_id = event_id
	run.event_resolved = false
	return run


func _upgraded_instance_ids(run: RunModel) -> Array[int]:
	var ids: Array[int] = []
	for instance: Dictionary in run.deck_instances:
		if instance.get(&"upgrade_id", &"") != &"":
			ids.append(int(instance[&"instance_id"]))
	return ids


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
