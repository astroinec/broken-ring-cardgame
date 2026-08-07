class_name CardData
extends RefCounted


enum CardType {
	ATTACK,
	DEFENSE,
	LAW,
	STATUS,
}

var instance_id: int
var id: StringName
var title: String
var card_type: CardType
var base_cost: int
var description: String
var rarity: String
var flavor_text: String
var exhausts: bool
var temporary: bool = false
var sealed_turns: int = -1
var cost_override_this_turn: int = -1


func _init(
	p_instance_id: int,
	p_id: StringName,
	p_title: String,
	p_card_type: CardType,
	p_base_cost: int,
	p_description: String,
	p_exhausts: bool = false,
	p_rarity: String = "基础",
	p_flavor_text: String = ""
) -> void:
	instance_id = p_instance_id
	id = p_id
	title = p_title
	card_type = p_card_type
	base_cost = p_base_cost
	description = p_description
	exhausts = p_exhausts
	rarity = p_rarity
	flavor_text = p_flavor_text


func type_name() -> String:
	return type_display_name(card_type)


static func type_display_name(p_card_type: int) -> String:
	match p_card_type:
		CardType.ATTACK:
			return "攻式"
		CardType.DEFENSE:
			return "守式"
		CardType.LAW:
			return "律式"
		CardType.STATUS:
			return "状态"
	return "未知类别"
