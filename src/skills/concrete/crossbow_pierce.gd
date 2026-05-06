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
	AudioBus.play_at(&"crossbow_shoot", owner_player.global_position)
	_spawn_projectile(
		owner_player.global_position + owner_player.aim_dir * (owner_player.radius + 4),
		owner_player.aim_dir * speed,
		damage * owner_player.dmg_mult(),
		Color(1.0, 0.55, 0.15),
		2.5,
		7.5,
		pierce,
		{"sprite_path": "res://assets/images/arrow.png", "sprite_size": Vector2(84.0, 33.0)},
	)
	owner_player.emit_fx("ap", {})
