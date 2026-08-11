extends SceneTree

const SEEDS: Array[int] = [73103, 80011, 91027, 100003, 110009, 120011, 130027, 140053]
const MAX_TURNS: int = 40
const BONUS_CARDS: Array[StringName] = [
	&"broken_sentence", &"blank_space", &"rift_slash", &"forced_stability",
	&"critical_permission", &"dissolution_protocol", &"delayed_guard",
	&"countdown_scar", &"restate", &"copied_guard", &"unseal_order",
]

var failures: int = 0


func _init() -> void:
	var results: Array[Dictionary] = []
	for seed_value: int in SEEDS:
		var first: Dictionary = _simulate(seed_value)
		var replay: Dictionary = _simulate(seed_value)
		_expect(first[&"digest"] == replay[&"digest"], "Boss seed %d reproduces exactly" % seed_value)
		_expect(bool(first[&"won"]), "Boss seed %d reaches a terminal victory" % seed_value)
		_expect(int(first[&"turns"]) <= MAX_TURNS, "Boss seed %d finishes before timeout" % seed_value)
		_expect(bool(first[&"phase_two_seen"]), "Boss seed %d reaches phase two" % seed_value)
		_expect(bool(first[&"cost_edit_seen"]), "Boss seed %d executes cost deletion" % seed_value)
		_expect(bool(first[&"type_edit_seen"]), "Boss seed %d executes type deletion" % seed_value)
		_expect(bool(first[&"unique_instances"]), "Boss seed %d keeps combat instance ids unique" % seed_value)
		results.append(first)
	_expect(_count_true(results, &"keyword_edit_seen") >= results.size() / 2, "at least half of fixed-seed victories execute keyword deletion before terminal")
	_print_summary(results)
	if failures == 0:
		print("PASS: all deterministic Boss simulations")
		quit(0)
	else:
		push_error("FAIL: %d deterministic Boss simulation checks failed" % failures)
		quit(1)


func _simulate(seed_value: int) -> Dictionary:
	var model: CombatModel = CombatModel.new()
	var no_relics: Array[StringName] = []
	model.start_battle(seed_value, 6, BONUS_CARDS, &"name_eraser", no_relics)
	var phase_two_seen: bool = false
	var cost_edit_seen: bool = false
	var type_edit_seen: bool = false
	var keyword_edit_seen: bool = false
	var actions: int = 0
	while not model.battle_over and model.turn_number <= MAX_TURNS:
		phase_two_seen = phase_two_seen or model.boss_phase >= 2
		cost_edit_seen = cost_edit_seen or not model.boss_cost_edits.is_empty() or _logs_contain(model, "篡改费用：")
		type_edit_seen = type_edit_seen or not model.boss_deleted_types.is_empty() or _logs_contain(model, "删除类别：《")
		keyword_edit_seen = keyword_edit_seen or not model.boss_deleted_keywords.is_empty() or _logs_contain(model, "删除关键词：《")
		if model.boss_terminal_choice_pending:
			var choice: StringName = &"read_original" if model.can_choose_boss_original_text() else &"deliver_seal"
			model.choose_boss_terminal(choice)
			break
		if model.has_pending_selection():
			var candidates: Array[int] = model.get_pending_candidate_indices()
			if candidates.is_empty():
				model.cancel_pending_selection()
			else:
				model.resolve_pending_selection(candidates[0])
			actions += 1
			continue
		var card_index: int = _choose_card(model)
		if card_index >= 0 and model.play_card(card_index):
			actions += 1
			continue
		model.end_player_turn()
		actions += 1
	phase_two_seen = phase_two_seen or model.boss_phase >= 2
	cost_edit_seen = cost_edit_seen or _logs_contain(model, "篡改费用：")
	type_edit_seen = type_edit_seen or _logs_contain(model, "删除类别：《")
	keyword_edit_seen = keyword_edit_seen or _logs_contain(model, "删除关键词：《")
	var log_digest: String = str(hash("|".join(model.log_entries)))
	return {
		&"seed": seed_value,
		&"won": model.battle_over and model.victory,
		&"turns": model.turn_number,
		&"actions": actions,
		&"choice": model.boss_terminal_choice,
		&"recoveries": model.boss_recovery_count,
		&"player_hp": model.player_hp,
		&"phase_two_seen": phase_two_seen,
		&"cost_edit_seen": cost_edit_seen,
		&"type_edit_seen": type_edit_seen,
		&"keyword_edit_seen": keyword_edit_seen,
		&"unique_instances": _instances_are_unique(model),
		&"digest": "%d/%d/%d/%s/%d/%d/%s" % [
			model.turn_number, actions, model.player_hp, model.boss_terminal_choice,
			model.boss_recovery_count, _all_card_count(model), log_digest,
		],
	}


func _choose_card(model: CombatModel) -> int:
	var best_index: int = -1
	var best_score: int = -1_000_000
	for index: int in range(model.hand.size()):
		var card: CardData = model.hand[index]
		if not model.can_play_card(index):
			continue
		var score: int = _card_score(model, card)
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _card_score(model: CombatModel, card: CardData) -> int:
	var score: int = 10 - model.get_card_cost(card)
	var effective_type: int = model.get_card_effective_type(card)
	if model.boss_phase == 1 and effective_type >= 0 and not model.boss_type_sequence.has(effective_type):
		score += 45
	if effective_type == CardData.CardType.ATTACK:
		score += 35
	elif effective_type == CardData.CardType.DEFENSE:
		score += 14 if model.player_hp > 25 else 45
	elif effective_type == CardData.CardType.LAW:
		score += 20
	match card.id:
		&"dissolution_protocol":
			score += 70 if model.instability >= 3 else 5
		&"critical_permission":
			score += 65 if model.instability >= 8 else 0
		&"rift_slash", &"broken_sentence", &"aftershock":
			score += 35
		&"countdown_scar":
			score += 28
		&"restate":
			score += 50 if model.last_card_type == CardData.CardType.ATTACK else -10
		&"copied_guard":
			score += 28 if model.last_card_type == CardData.CardType.DEFENSE else 0
		&"unseal_order":
			score += 45 if not model.sealed_zone.is_empty() else -30
		&"forced_stability":
			score += 20 if model.instability >= 4 else 0
	return score


func _instances_are_unique(model: CombatModel) -> bool:
	var ids: Dictionary = {}
	for pile: Array[CardData] in [model.draw_pile, model.hand, model.discard_pile, model.sealed_zone, model.exhausted_zone]:
		for card: CardData in pile:
			if ids.has(card.instance_id):
				return false
			ids[card.instance_id] = true
	return true


func _all_card_count(model: CombatModel) -> int:
	return model.draw_pile.size() + model.hand.size() + model.discard_pile.size() + model.sealed_zone.size() + model.exhausted_zone.size()


func _logs_contain(model: CombatModel, fragment: String) -> bool:
	for entry: String in model.log_entries:
		if entry.contains(fragment):
			return true
	return false


func _count_true(results: Array[Dictionary], key: StringName) -> int:
	var count: int = 0
	for result: Dictionary in results:
		count += 1 if bool(result[key]) else 0
	return count


func _print_summary(results: Array[Dictionary]) -> void:
	var wins: int = 0
	var hidden: int = 0
	var total_turns: int = 0
	var total_recoveries: int = 0
	for result: Dictionary in results:
		wins += 1 if bool(result[&"won"]) else 0
		hidden += 1 if result[&"choice"] == &"read_original" else 0
		total_turns += int(result[&"turns"])
		total_recoveries += int(result[&"recoveries"])
	print("《断环》M2 Boss模拟｜固定种子 %d 个｜胜利 %d/%d｜读取原文 %d/%d" % [
		results.size(), wins, results.size(), hidden, results.size(),
	])
	print("平均回合 %.2f｜平均恢复 %.2f" % [
		float(total_turns) / float(results.size()), float(total_recoveries) / float(results.size()),
	])


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
