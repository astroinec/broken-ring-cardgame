class_name EvidenceCatalog
extends RefCounted


const DEFINITIONS: Dictionary = {
	&"alternate_name_index": {
		&"title": "异名索引",
		&"source": "随机事件：没有作者的书 / 写下另一个名字",
		&"description": "书页把 REC-10 与另一个名字并列索引，说明编号早于机构公开记录。",
	},
	&"nine_redacted_return_records": {
		&"title": "九份涂名返航记录",
		&"source": "随机事件：第七码头 / 检查返航名单",
		&"description": "九条同姓返航记录被以相同手法涂去，像是同一实验的连续版本。",
	},
	&"overdue_bell_record": {
		&"title": "过期铃声记录",
		&"source": "随机事件：第七码头 / 敲响返航铃后的战斗",
		&"description": "铃声只为无人返航的流程响起，却把你识别为重复到访者。",
	},
	&"old_dock_recovery_process": {
		&"title": "旧码头回收流程",
		&"source": "随机事件：第七码头 / 盖上通行章",
		&"description": "数百年前的码头已经使用与终末机构完全相同的回收步骤。",
	},
	&"repeated_calibration_parameters": {
		&"title": "重复校准参数",
		&"source": "随机事件：校准站 / 提交当前编号",
		&"description": "当前编号与上一名回收者共享身体校准参数和权限等级。",
	},
	&"obscured_asset_log": {
		&"title": "遮蔽资产日志",
		&"source": "随机事件：校准站 / 提交上一名回收者编号",
		&"description": "两个编号的资产标识被同一遮蔽层覆盖，机构可能把人格当作可替换资产。",
	},
	&"nonexistent_autopsy": {
		&"title": "未发生的尸检",
		&"source": "随机事件：被删除的葬礼 / 询问死因",
		&"description": "尸检记录描述的不是伤口，而是回收者身体内部的制造接口。",
	},
	&"tenth_calibration_record": {
		&"title": "第十份校准记录",
		&"source": "Boss结算：删名者 / 读取被删原文",
		&"description": "九种互相冲突的文明答案都登记在 REC-10 名下，证明“第十名”并非单纯序号。",
	},
}


static func has_evidence(evidence_id: StringName) -> bool:
	return DEFINITIONS.has(evidence_id)


static func get_record(evidence_id: StringName) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(evidence_id, {})
	assert(not definition.is_empty(), "未知证据定义：%s" % evidence_id)
	return {
		&"id": evidence_id,
		&"title": str(definition[&"title"]),
		&"source": str(definition[&"source"]),
		&"description": str(definition[&"description"]),
	}
