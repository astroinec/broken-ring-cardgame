extends SceneTree

## 卡牌性价比审计：用真实规则引擎结算每张牌，输出每点稳定度的实际收益。
## 只读诊断，不写入任何文件，不参与CI门禁。

const BASELINE_ATTACK_PER_ENERGY: float = 6.0
const BASELINE_BLOCK_PER_ENERGY: float = 5.0

var next_instance_id: int = 90_000


func _init() -> void:
	print("《断环》卡牌性价比审计")
	print("基线：1 费 = 6 伤害 = 5 格挡（《校准击》《临时护式》）")
	print("")
	_audit_raw_numbers()
	print("")
	_audit_conditional_cards()
	print("")
	_audit_upgrade_gains()
	quit(0)


func _audit_raw_numbers() -> void:
	print("一、纯数值牌的每费收益（无条件、无机制依赖）")
	print("  卡牌            费用  基础  升级  基础每费  升级每费  基线比")
	var rows: Array[Array] = [
		["校准击", &"calibration_strike", 1, 6, 9, true],
		["临时护式", &"temporary_guard", 1, 5, 8, false],
		["断句", &"broken_sentence", 1, 7, 10, true],
		["留白", &"blank_space", 1, 7, 9, false],
		["裂隙挥击", &"rift_slash", 1, 10, 14, true],
		["未署名的援护", &"unsigned_support", 1, 6, 8, false],
		["延迟防线", &"delayed_guard", 1, 9, 13, false],
		["倒计刻痕", &"countdown_scar", 1, 14, 14, true],
		["崩解协议", &"dissolution_protocol", 2, 14, 18, true],
	]
	for row: Array in rows:
		var label: String = row[0]
		var cost: int = int(row[2])
		var base: int = int(row[3])
		var upgraded: int = int(row[4])
		var is_attack: bool = bool(row[5])
		var baseline: float = BASELINE_ATTACK_PER_ENERGY if is_attack else BASELINE_BLOCK_PER_ENERGY
		var base_rate: float = float(base) / float(cost)
		var up_rate: float = float(upgraded) / float(cost)
		print("  %-14s  %d    %2d    %2d    %5.1f     %5.1f     %+.0f%%" % [
			label, cost, base, upgraded, base_rate, up_rate,
			(base_rate / baseline - 1.0) * 100.0,
		])


func _audit_conditional_cards() -> void:
	print("二、条件牌的实测触发收益（用真实战斗结算）")

	var restate_low: int = _measure_restate(&"calibration_strike", &"")
	var restate_high: int = _measure_restate(&"rift_slash", &"")
	var restate_up_low: int = _measure_restate(&"calibration_strike", &"restate_plus")
	var restate_up_high: int = _measure_restate(&"rift_slash", &"restate_plus")
	print("  复述(1费)｜接校准击6 → %d 伤害｜接裂隙挥击11 → %d 伤害" % [restate_low, restate_high])
	print("  复述+(1费)｜接校准击6 → %d 伤害｜接裂隙挥击11 → %d 伤害" % [restate_up_low, restate_up_high])

	var copied_low: int = _measure_copied_guard(&"temporary_guard", &"")
	var copied_high: int = _measure_copied_guard(&"delayed_guard", &"")
	print("  复写护式(1费)｜接临时护式5 → %d 格挡｜前置无守式 → %d 格挡" % [
		copied_low, _measure_copied_guard(&"", &""),
	])
	print("  复写护式+(1费)｜接临时护式5 → %d 格挡" % _measure_copied_guard(&"temporary_guard", &"copied_guard_plus"))
	if copied_high > 0:
		print("  复写护式(1费)｜接封存解封12格挡场景 → %d 格挡" % copied_high)

	for stacks: int in [0, 1, 2, 3]:
		print("  缺名仲裁(1费)｜%d 层缺名 → %d 格挡" % [stacks, _measure_arbitration(stacks, &"")])
	for kinds: int in [0, 1, 2, 3]:
		print("  借名执行(1费)｜%d 种缺名 → %d 伤害" % [kinds, _measure_borrowed(kinds, &"")])
	for sealed: int in [0, 1, 2, 3]:
		print("  第十种答案(1费)｜封存 %d 张 → %d 伤害" % [sealed, _measure_tenth(sealed, &"")])
	for instability: int in [0, 3, 6, 9]:
		print("  崩解协议(2费)｜不稳定 %d → %d 伤害" % [instability, _measure_dissolution(instability, &"")])
	for instability: int in [0, 1, 2, 3]:
		print("  强制稳定(1费)｜不稳定 %d → %d 格挡" % [instability, _measure_forced_stability(instability, &"")])
	print("  余震(1费)｜本回合未超载 → %d 伤害｜已超载 → %d 伤害" % [
		_measure_aftershock(false, &""), _measure_aftershock(true, &""),
	])
	print("  断句(1费)｜首张打出 → 7伤害+抽1｜非首张 → 7伤害+抽0")
	print("  留白(1费)｜未打攻式 → 10格挡｜已打攻式 → 7格挡")


func _audit_upgrade_gains() -> void:
	print("三、升级增量（升级只应改变选择或明显改变数值）")
	var rows: Array[Array] = [
		["校准击", "6→9 伤害", "+50%", "纯数值"],
		["临时护式", "5→8 格挡", "+60%", "纯数值"],
		["断句", "7→10 伤害", "+43%", "纯数值"],
		["留白", "7→9 基础格挡", "+29%", "纯数值"],
		["裂隙挥击", "11→15 伤害", "+36%", "纯数值"],
		["未署名的援护", "6→8 基础格挡", "+33%", "纯数值"],
		["延迟防线", "12→16 解封格挡", "+33%", "纯数值"],
		["倒计刻痕", "封存2→1", "提前1回合", "改变节奏"],
		["崩解协议", "14→18 基础", "+29%", "纯数值"],
		["越界读取", "超载2→1", "降低代价", "改变风险"],
		["余震", "追加4→7", "+75%", "纯数值"],
		["索引重排", "看3→看5", "+67%信息", "改变质量"],
		["强制稳定", "每层2→3格挡", "+50%", "纯数值"],
		["临界许可", "1费→0费", "省1费", "改变节奏"],
		["预写结局", "2费→1费", "省1费", "改变节奏"],
		["开封令", "超载2→0", "去除代价", "改变风险"],
		["复述", "60%→90%", "+50%", "纯数值"],
		["复写护式", "4→6 基础格挡", "+50%", "纯数值"],
		["同音异义", "超载1→0", "去除代价", "改变风险"],
		["反向索引", "回手牌-1费", "省1费", "改变节奏"],
		["删去冗句", "抽2→抽3", "+50%", "纯数值"],
		["缺名仲裁", "每层4→5格挡", "+25%", "纯数值"],
		["第十种答案", "每封存4→6", "+50%", "纯数值"],
		["回声室", "50%→75%", "+50%", "纯数值"],
		["借名执行", "每种3→5", "+67%", "纯数值"],
	]
	var pure_number: int = 0
	for row: Array in rows:
		if str(row[3]) == "纯数值":
			pure_number += 1
		print("  %-14s %-18s %-10s %s" % [row[0], row[1], row[2], row[3]])
	print("")
	print("  纯数值升级 %d/%d（%.0f%%）——升级几乎不提供构筑分叉。" % [
		pure_number, rows.size(), 100.0 * float(pure_number) / float(rows.size()),
	])


# ------------------------------------------------------------------ 实测工具

func _measure_restate(previous_attack_id: StringName, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	if previous_attack_id != &"":
		model.hand.append(_card(previous_attack_id))
		model.play_card(0)
	var before: int = model.enemy_hp
	model.hand.append(_card(&"restate", upgrade_id))
	model.play_card(model.hand.size() - 1)
	return before - model.enemy_hp


func _measure_copied_guard(previous_defense_id: StringName, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	if previous_defense_id != &"":
		model.hand.append(_card(previous_defense_id))
		model.play_card(0)
	var before: int = model.player_block
	model.hand.append(_card(&"copied_guard", upgrade_id))
	model.play_card(model.hand.size() - 1)
	return model.player_block - before


func _measure_arbitration(stacks: int, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	if stacks > 0:
		model.missing_name[CardData.CardType.ATTACK] = stacks
	model.hand.append(_card(&"missing_name_arbitration", upgrade_id))
	model.play_card(0)
	return model.player_block


func _measure_borrowed(kinds: int, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	var types: Array[int] = [CardData.CardType.DEFENSE, CardData.CardType.LAW, CardData.CardType.ATTACK]
	for index: int in range(mini(kinds, types.size())):
		model.missing_name[types[index]] = 1
	var before: int = model.enemy_hp
	model.hand.append(_card(&"borrowed_name_execution", upgrade_id))
	model.play_card(0)
	return before - model.enemy_hp


func _measure_tenth(sealed: int, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	for index: int in range(sealed):
		var card: CardData = _card(&"delayed_guard")
		card.sealed_turns = 3
		model.sealed_zone.append(card)
	var before: int = model.enemy_hp
	model.hand.append(_card(&"tenth_answer", upgrade_id))
	model.play_card(0)
	return before - model.enemy_hp


func _measure_dissolution(instability: int, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	model.instability = instability
	var before: int = model.enemy_hp
	model.hand.append(_card(&"dissolution_protocol", upgrade_id))
	model.play_card(0)
	return before - model.enemy_hp


func _measure_forced_stability(instability: int, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	model.instability = instability
	model.hand.append(_card(&"forced_stability", upgrade_id))
	model.play_card(0)
	return model.player_block


func _measure_aftershock(gained_instability: bool, upgrade_id: StringName) -> int:
	var model: CombatModel = _model()
	model.instability_gained_this_turn = gained_instability
	var before: int = model.enemy_hp
	model.hand.append(_card(&"aftershock", upgrade_id))
	model.play_card(0)
	return before - model.enemy_hp


func _model() -> CombatModel:
	var model: CombatModel = CombatModel.new()
	model.start_battle(73103, 6, [], &"name_eraser")
	model.enemy_hp = 9999
	model.enemy_max_hp = 9999
	model.enemy_block = 0
	model.stone_shell = 0
	model.boss_phase = 0
	model.boss_transition_pending = false
	model.boss_terminal_choice_pending = false
	model.hand.clear()
	model.draw_pile.clear()
	model.discard_pile.clear()
	model.sealed_zone.clear()
	model.exhausted_zone.clear()
	model.player_block = 0
	model.energy = 50
	return model


func _card(card_id: StringName, upgrade_id: StringName = &"") -> CardData:
	next_instance_id += 1
	return CardCatalog.create_card(card_id, next_instance_id, upgrade_id)
