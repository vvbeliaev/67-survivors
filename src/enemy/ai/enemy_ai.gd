class_name EnemyAI extends Node

# Behaviour bag for an enemy archetype. Lives as a child of Enemy. The host
# calls tick(delta) every physics step. Movement, attacks, and target choice
# are all delegated here so adding a new archetype is `new file + tres`.

var owner_enemy: Node = null

func setup(e: Node) -> void:
	owner_enemy = e

func tick(_delta: float) -> void:
	pass

# ---- Helpers shared across AI variants ---------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# Чучело — фейковый игрок: моб видит его в одном пуле с реальными игроками
# и идёт к тому, кто ближе. Никакой глобальной «провокации» нет, чучело
# просто перетягивает на себя мобов, у которых оно физически ближайший
# таргет. Если оба живы — побеждает меньшая дистанция.
func _pick_target() -> Node2D:
	var e := owner_enemy
	var p: Node2D = Targeting.nearest_alive_player(get_tree(), e.global_position)
	var d: Node2D = Targeting.nearest_decoy(get_tree(), e.global_position)
	if d == null:
		return p
	if p == null:
		return d
	var dp: float = e.global_position.distance_squared_to(p.global_position)
	var dd: float = e.global_position.distance_squared_to(d.global_position)
	return d if dd < dp else p

func _find_player(peer_id: int) -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null
