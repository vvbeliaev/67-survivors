extends EnemyAI

# Boss: melee + telegraphed AoE on the targeted player's position.
#
# AoE state machine:
#   0 — cooldown between casts.
#   1 — windup, red ring telegraphed at boss_aoe_pos.
#   2 — shockwave detonation. Damage is applied at the 1→2 transition; this
#       state simply keeps the enemy state replicated long enough for every
#       peer's view to play the expanding-ring animation.

const SHOCKWAVE_DURATION: float = 0.45

var _attack_cd: float = 0.0
var _aoe_cd: float = 0.0

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

	_tick_aoe(delta, target)

	e.velocity = dir * e.move_speed * e.move_speed_mult
	_attack_cd -= delta
	if dist < e.radius + 18.0 and _attack_cd <= 0.0:
		_attack_cd = e.contact_cd
		if target.has_method("apply_damage"):
			target.apply_damage(e.contact_damage, "enemy")

func _tick_aoe(delta: float, target: Node2D) -> void:
	var e := owner_enemy
	match e.boss_aoe_state:
		0:
			_aoe_cd -= delta
			if _aoe_cd <= 0.0:
				e.boss_aoe_state = 1
				e.boss_aoe_timer = e.boss_aoe_windup
				e.boss_aoe_pos = target.global_position
		1:
			e.boss_aoe_timer -= delta
			if e.boss_aoe_timer <= 0.0:
				_resolve(e)
				e.boss_aoe_state = 2
				e.boss_aoe_timer = SHOCKWAVE_DURATION
		2:
			e.boss_aoe_timer -= delta
			if e.boss_aoe_timer <= 0.0:
				e.boss_aoe_state = 0
				_aoe_cd = e.boss_aoe_cd

func _resolve(e: Node) -> void:
	for p in Targeting.players_in_radius(get_tree(), e.boss_aoe_pos, e.boss_aoe_radius):
		p.apply_damage(e.boss_aoe_damage, "enemy")
