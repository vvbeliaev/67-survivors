extends EnemyAI

# Stand-off shooter. Maintains preferred range, fires projectiles on cooldown.

var _ranged_cd: float = 0.0

func tick(delta: float) -> void:
	var e := owner_enemy
	if _now() < e.stunned_until:
		e.velocity = Vector2.ZERO
		return
	var target := _pick_target()
	if target == null:
		e.velocity = Vector2.ZERO
		return
	var to_t: Vector2 = target.global_position - e.global_position
	var dist: float = to_t.length()
	var dir: Vector2 = to_t.normalized() if dist > 0.001 else Vector2.ZERO
	var desired: float = e.ranged_dist
	if dist < desired - 30.0:
		e.velocity = -dir * e.move_speed
	elif dist > desired + 30.0:
		e.velocity = dir * e.move_speed
	else:
		e.velocity = Vector2.ZERO
	_ranged_cd -= delta
	if _ranged_cd <= 0.0 and dist <= e.ranged_dist + 80.0:
		_ranged_cd = e.ranged_cd
		_fire(target, dir)

func _fire(target: Node2D, dir: Vector2) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	var e := owner_enemy
	var d: Vector2 = (target.global_position - e.global_position).normalized()
	arena.spawn_projectile({
		"pos": e.global_position + d * (e.radius + 4),
		"vel": d * e.projectile_speed,
		"damage": e.projectile_damage,
		"lifetime": 3.0,
		"team": "enemy",
		"color": Color(1.0, 0.5, 0.2),
		"radius": 6.0,
		"pierce": 0,
	})
