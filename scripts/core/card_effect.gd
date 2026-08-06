class_name CardEffect
extends RefCounted


enum Kind {
	DAMAGE_ENEMY,
	GAIN_BLOCK,
	DRAW_CARDS,
	GAIN_INSTABILITY,
	REDUCE_INSTABILITY,
	SEAL_CARD,
	ECHO_ATTACK,
	ECHO_BLOCK,
	DISCARD_DRAW_TOP,
	PREVENT_FRACTURE,
	DISSOLUTION_ATTACK,
	PREWRITE_COPY,
	UNSEAL_OLDEST,
	COPY_PREVIOUS,
}

var kind: Kind
var amount: int
var factor: int


func _init(p_kind: Kind, p_amount: int, p_factor: int = 0) -> void:
	kind = p_kind
	amount = p_amount
	factor = p_factor
