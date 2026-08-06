extends SceneTree

const CombatModelScript: Script = preload("res://scripts/core/combat_model.gd")

var failures: int = 0


func _init() -> void:
	_test_deterministic_opening()
	_test_basic_card_play()
	_test_fracture()
	_test_echo_snapshot()
	_test_sealed_card_returns()
	_test_tutorial_stage_decks_and_unlocks()
	_test_tutorial_stage_progression_rule()
	_test_reward_card_rules()
	if failures == 0:
		print("PASS: all combat model checks")
		quit(0)
	else:
		push_error("FAIL: %d combat model checks failed" % failures)
		quit(1)


func _test_deterministic_opening() -> void:
	var first = CombatModelScript.new()
	var second = CombatModelScript.new()
	first.start_battle(73103)
	second.start_battle(73103)
	_expect(first.enemy_hp == second.enemy_hp, "fixed seed enemy hp")
	_expect(_hand_ids(first) == _hand_ids(second), "fixed seed opening hand")


func _test_basic_card_play() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103)
	var attack_index: int = _find_hand_card(model, &"calibration_strike")
	if attack_index < 0:
		_expect(false, "opening hand contains calibration strike")
		return
	var hp_before: int = model.enemy_hp
	var energy_before: int = model.energy
	_expect(model.play_card(attack_index), "calibration strike can be played")
	_expect(model.enemy_hp == hp_before - 6, "calibration strike deals 6")
	_expect(model.energy == energy_before - 1, "calibration strike spends 1 energy")


func _test_fracture() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103)
	model.instability = 9
	model._check_fracture()
	_expect(model.player_hp == CombatModelScript.PLAYER_MAX_HP, "no fracture below threshold")
	model.instability = 10
	model._check_fracture()
	_expect(model.player_hp == CombatModelScript.PLAYER_MAX_HP - CombatModelScript.FRACTURE_DAMAGE, "fracture deals fixed damage")
	_expect(model.instability == 0, "fracture reduces instability by ten")


func _test_echo_snapshot() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 5)
	_prepare_hand(model, [&"calibration_strike", &"restate"])
	var hp_before: int = model.enemy_hp
	_expect(model.play_card(0), "echo setup attack can be played")
	_expect(model.play_card(0), "restate can be played after attack")
	_expect(model.enemy_hp == hp_before - 9, "restate echoes sixty percent of resolved attack damage")


func _test_sealed_card_returns() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 4)
	_prepare_hand(model, [&"delayed_guard"])
	_expect(model.play_card(0), "delayed guard can be sealed")
	_expect(model.sealed_zone.size() == 1, "delayed guard enters sealed zone")
	model.end_player_turn()
	_expect(model.player_block == 12, "delayed guard grants block after unsealing")
	_expect(_find_hand_card(model, &"delayed_guard") >= 0, "unsealed card returns to hand")


func _test_tutorial_stage_decks_and_unlocks() -> void:
	var mechanics: Array[StringName] = [&"intent", &"overload", &"seal", &"echo", &"missing_name"]
	var unlock_stages: Array[int] = [2, 3, 4, 5, 6]
	for stage: int in range(1, CombatModelScript.TUTORIAL_STAGE_MAX + 1):
		var model = CombatModelScript.new()
		model.start_battle(73103, stage)
		var ids: Array[StringName] = _all_card_ids(model)
		_expect(model.tutorial_stage == stage, "tutorial stage %d is selected" % stage)
		_expect(not model.tutorial_stage_title.is_empty(), "tutorial stage %d has title" % stage)
		_expect(not model.tutorial_hint.is_empty(), "tutorial stage %d has hint" % stage)
		_expect(not model.enemy_name.is_empty(), "tutorial stage %d has enemy name" % stage)
		_expect(not model.get_enemy_intent_text().is_empty(), "tutorial stage %d has intent text" % stage)
		for mechanic_index: int in range(mechanics.size()):
			var expected_unlocked: bool = stage >= unlock_stages[mechanic_index]
			_expect(
				model.is_mechanic_unlocked(mechanics[mechanic_index]) == expected_unlocked,
				"tutorial stage %d unlock state for %s" % [stage, mechanics[mechanic_index]]
			)
		match stage:
			1, 2:
				_expect(_contains_only_basic_cards(ids), "tutorial stage %d uses only basic attack and defense" % stage)
			3:
				_expect(ids.has(&"boundary_read"), "stage 3 deck contains boundary read")
				_expect(ids.has(&"rift_slash"), "stage 3 deck contains rift slash")
				_expect(ids.has(&"forced_stability"), "stage 3 deck contains forced stability")
				_expect(not ids.has(&"delayed_guard") and not ids.has(&"restate"), "stage 3 excludes later keywords")
			4:
				_expect(ids.has(&"delayed_guard") and ids.has(&"countdown_scar"), "stage 4 deck contains both seal cards")
				_expect(not ids.has(&"restate"), "stage 4 excludes echo")
			5:
				_expect(ids.has(&"restate"), "stage 5 deck contains restate")
				_expect(ids.has(&"delayed_guard"), "stage 5 retains seal")
			6:
				_expect(ids.has(&"boundary_read") and ids.has(&"delayed_guard") and ids.has(&"restate"), "stage 6 combines prior keyword cards")
				_expect(ids.size() == 15, "stage 6 uses comprehensive fifteen-card deck")


func _test_tutorial_stage_progression_rule() -> void:
	var model = CombatModelScript.new()
	model.start_battle(73103, 2)
	_expect(not model.can_advance_tutorial_stage(), "stage cannot advance before victory")
	_expect(model.get_next_tutorial_stage() == 2, "next stage remains current before victory")
	model.battle_over = true
	model.victory = true
	_expect(model.can_advance_tutorial_stage(), "victory permits tutorial advancement")
	_expect(model.get_next_tutorial_stage() == 3, "victory advances exactly one tutorial stage")
	model.start_battle(73103, 6)
	model.battle_over = true
	model.victory = true
	_expect(not model.can_advance_tutorial_stage(), "final tutorial stage cannot advance past six")
	_expect(model.get_next_tutorial_stage() == 6, "final tutorial stage remains six")


func _test_reward_card_rules() -> void:
	var tempo = CombatModelScript.new()
	var tempo_bonus: Array[StringName] = [&"broken_sentence", &"blank_space"]
	tempo.start_battle(80001, 6, tempo_bonus)
	_prepare_hand(tempo, [&"broken_sentence", &"blank_space"])
	var hp_before: int = tempo.enemy_hp
	var draw_before: int = tempo.draw_pile.size()
	_expect(tempo.play_card(0), "broken sentence can be played")
	_expect(tempo.enemy_hp == hp_before - 7, "broken sentence deals seven damage")
	_expect(tempo.draw_pile.size() == draw_before - 1, "broken sentence draws when played first")
	var block_before: int = tempo.player_block
	_expect(tempo.play_card(0), "blank space can be played")
	_expect(tempo.player_block == block_before + 7, "blank space loses bonus after an attack")

	var permission = CombatModelScript.new()
	var permission_bonus: Array[StringName] = [&"critical_permission"]
	permission.start_battle(80002, 6, permission_bonus)
	_prepare_hand(permission, [&"critical_permission"])
	permission.instability = 10
	var player_hp_before: int = permission.player_hp
	_expect(permission.play_card(0), "critical permission can be played")
	_expect(permission.player_hp == player_hp_before, "critical permission prevents fracture damage")
	_expect(permission.instability == 0, "prevented fracture still reduces instability")

	var dissolution = CombatModelScript.new()
	var dissolution_bonus: Array[StringName] = [&"dissolution_protocol"]
	dissolution.start_battle(80003, 6, dissolution_bonus)
	_prepare_hand(dissolution, [&"dissolution_protocol"])
	dissolution.instability = 4
	var dissolution_hp: int = dissolution.enemy_hp
	_expect(dissolution.play_card(0), "dissolution protocol can be played")
	_expect(dissolution.enemy_hp == dissolution_hp - 22, "dissolution protocol scales with instability")
	_expect(dissolution.instability == 0, "dissolution protocol clears instability")

	var defense_echo = CombatModelScript.new()
	var defense_bonus: Array[StringName] = [&"copied_guard"]
	defense_echo.start_battle(80004, 6, defense_bonus)
	_prepare_hand(defense_echo, [&"temporary_guard", &"copied_guard"])
	_expect(defense_echo.play_card(0), "temporary guard sets defense echo snapshot")
	_expect(defense_echo.play_card(0), "copied guard can be played")
	_expect(defense_echo.player_block == 11, "copied guard adds four plus half prior block")

	var homophone = CombatModelScript.new()
	var homophone_bonus: Array[StringName] = [&"homophone"]
	homophone.start_battle(80005, 6, homophone_bonus)
	_prepare_hand(homophone, [&"calibration_strike", &"homophone"])
	_expect(homophone.play_card(0), "attack sets homophone source")
	_expect(homophone.play_card(0), "homophone can be played")
	var copied_index: int = _find_hand_card(homophone, &"calibration_strike")
	_expect(copied_index >= 0, "homophone creates previous card copy")
	if copied_index >= 0:
		_expect(homophone.hand[copied_index].temporary, "homophone copy is temporary")
		_expect(homophone.get_card_cost(homophone.hand[copied_index]) == 0, "homophone copy costs zero this turn")

	var prewrite = CombatModelScript.new()
	var prewrite_bonus: Array[StringName] = [&"prewritten_ending"]
	prewrite.start_battle(80006, 6, prewrite_bonus)
	_prepare_hand(prewrite, [&"prewritten_ending", &"calibration_strike"])
	_expect(prewrite.play_card(0), "prewritten ending can be played")
	_expect(prewrite.sealed_zone.size() == 1, "prewritten ending seals a temporary copy")
	_expect(prewrite.get_card_cost(prewrite.hand[0]) == 0, "prewritten ending makes source card free this turn")


func _contains_only_basic_cards(ids: Array[StringName]) -> bool:
	for card_id: StringName in ids:
		if card_id != &"calibration_strike" and card_id != &"temporary_guard":
			return false
	return ids.size() == 10


func _all_card_ids(model) -> Array[StringName]:
	var ids: Array[StringName] = []
	for pile in [model.draw_pile, model.hand, model.discard_pile, model.sealed_zone, model.exhausted_zone]:
		for card in pile:
			ids.append(card.id)
	return ids


func _prepare_hand(model, card_ids: Array[StringName]) -> void:
	while not model.hand.is_empty():
		model.discard_pile.append(model.hand.pop_back())
	for card_id: StringName in card_ids:
		var card = _extract_card(model, card_id)
		if card != null:
			model.hand.append(card)
	model.energy = 9


func _extract_card(model, card_id: StringName):
	for pile in [model.draw_pile, model.discard_pile]:
		for index: int in range(pile.size()):
			if pile[index].id == card_id:
				var card = pile[index]
				pile.remove_at(index)
				return card
	_expect(false, "card exists in test deck: %s" % card_id)
	return null


func _hand_ids(model) -> Array[StringName]:
	var ids: Array[StringName] = []
	for card in model.hand:
		ids.append(card.id)
	return ids


func _find_hand_card(model, card_id: StringName) -> int:
	for index: int in range(model.hand.size()):
		if model.hand[index].id == card_id:
			return index
	return -1


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
