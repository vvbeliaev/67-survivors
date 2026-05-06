extends EnemyAI

# Melee runner. Charges nearest player, smashes on contact.

var _attack_cd: float = 0.0

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
	e.velocity = dir * e.move_speed * e.move_speed_mult
	_attack_cd -= delta
	if dist < e.radius + 18.0 and _attack_cd <= 0.0:
		_attack_cd = e.contact_cd
		if target.has_method("apply_damage"):
			target.apply_damage(e.contact_damage, "enemy")
