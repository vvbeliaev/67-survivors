extends Skill

# Weak self-defence projectile snapping to the nearest enemy.

@export var seek_range: float = 500.0
@export var damage: float = 4.0
@export var projectile_speed: float = 320.0
@export var projectile_lifetime: float = 2.0
@export var projectile_radius: float = 5.0

func _init() -> void:
	base_cooldown = 0.8

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	var target := Targeting.nearest_enemy(get_tree(), owner_player.global_position, seek_range * owner_player.range_mult())
	if target == null:
		return
	cooldown_left = base_cooldown / max(owner_player.atk_speed_mult(), 0.01)
	var dir: Vector2 = (target.global_position - owner_player.global_position).normalized()
	_spawn_projectile(
		owner_player.global_position + dir * (owner_player.radius + 4),
		dir * projectile_speed,
		damage * owner_player.dmg_mult(),
		Color(0.7, 1.0, 0.7),
		projectile_lifetime,
		projectile_radius,
		0,
	)
	owner_player.emit_fx("auto", {})
