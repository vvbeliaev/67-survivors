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

func _pick_target() -> Node2D:
	var e := owner_enemy
	var n: float = _now()
	if e.forced_target_id != -1 and n < e.forced_target_until:
		var f := _find_player(e.forced_target_id)
		if f != null and f.alive:
			return f
		e.forced_target_id = -1
	return Targeting.nearest_alive_player(get_tree(), e.global_position)

func _find_player(peer_id: int) -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null
