extends Skill

# Armour-piercing bolt that punches through several enemies.

@export var damage: float = 60.0
@export var speed: float = 700.0
@export var pierce: int = 6

func _init() -> void:
	base_cooldown = 6.0
	icon = preload("res://assets/images/icons/winged-arrow.svg")

const PUSHBACK_UPGRADE: StringName = &"legendary_crossbow_pushback"
# AP-болт толкает как незаряженный авто (mult=1.0). Геймплейно ровно — это
# сильный «заряженный» по урону, но без ручной зарядки, поэтому скейл нельзя.
const AP_PUSHBACK: float = 300.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	trigger_visual_fx("ap", {})
	AudioBus.play_at(&"crossbow_shoot", owner_player.global_position)
	var pushback: float = AP_PUSHBACK if _has_upgrade(PUSHBACK_UPGRADE) else 0.0
	_spawn_projectile(
		owner_player.global_position + owner_player.aim_dir * (owner_player.radius + 4),
		owner_player.aim_dir * speed,
		damage * owner_player.dmg_mult(),
		Color(1.0, 0.55, 0.15),
		2.5,
		7.5,
		pierce,
		{
			"sprite_path": "res://assets/images/arrow.png",
			"sprite_size": Vector2(84.0, 33.0),
			"pushback_force": pushback,
		},
	)
	owner_player.emit_fx("ap", {})
