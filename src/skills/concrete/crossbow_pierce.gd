extends Skill

# Armour-piercing bolt that punches through several enemies.

@export var damage: float = 60.0
@export var speed: float = 700.0
@export var pierce: int = 6

func _init() -> void:
	base_cooldown = 6.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	trigger_visual_fx("ap", {})
	_spawn_projectile(
		owner_player.global_position + owner_player.aim_dir * (owner_player.radius + 4),
		owner_player.aim_dir * speed,
		damage * owner_player.dmg_mult(),
		Color(1.0, 0.6, 0.2),
		2.5,
		6.0,
		pierce,
	)
