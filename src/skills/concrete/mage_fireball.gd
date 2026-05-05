extends Skill

# Targeted fireball. Spawns a flying body for the visual + applies an AoE
# resolve at the cursor position immediately on the host.

@export var aoe_radius: float = 80.0
@export var aoe_damage: float = 8.0
@export var projectile_speed: float = 480.0
@export var projectile_lifetime: float = 1.5
@export var projectile_radius: float = 7.0

func _init() -> void:
	base_cooldown = 0.8
	mana_cost = 30.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.aim_dir
	var rm: float = owner_player.range_mult()
	trigger_visual_fx("fireball", {"pos": owner_player.aim_world(), "r": aoe_radius * rm})
	AudioBus.play_at(&"mage_cast", owner_player.global_position)
	AudioBus.play_at(&"mage_projectile_hit", owner_player.aim_world())
	_spawn_projectile(
		owner_player.global_position + dir * (owner_player.radius + 4),
		dir * projectile_speed,
		0.0,
		Color(1.0, 0.5, 0.2),
		projectile_lifetime,
		projectile_radius,
		0,
	)
	_aoe_damage(owner_player.aim_world(), aoe_radius * rm, aoe_damage * owner_player.dmg_mult())
