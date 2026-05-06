extends Skill

# Combat roll with i-frames. If STAT_ROLL_VOLLEY > 0, fires that many bolts
# in evenly-spaced radial directions from the roll's origin point.

@export var distance: float = 160.0
@export var iframe_duration: float = 0.5
@export var volley_damage: float = 8.0
@export var volley_speed: float = 520.0
@export var volley_lifetime: float = 2.5
@export var volley_radius: float = 2.5

func _init() -> void:
	base_cooldown = 5.0
	icon = preload("res://assets/images/icons/dodging.svg")

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.move_dir() if owner_player.move_dir().length_squared() > 0.01 else owner_player.aim_dir
	var from_pos: Vector2 = owner_player.global_position
	owner_player.teleport(owner_player.global_position + dir.normalized() * distance)
	owner_player.grant_iframes(iframe_duration)
	trigger_visual_fx("roll", {"from": from_pos})
	_fire_volley(from_pos)

func _fire_volley(from_pos: Vector2) -> void:
	var count: int = int(owner_player.stats.value(StatBlock.STAT_ROLL_VOLLEY))
	if count <= 0:
		return
	var bolt_flat: float = owner_player.stats.value(StatBlock.STAT_BOLT_DAMAGE)
	var dmg: float = (volley_damage + bolt_flat) * owner_player.dmg_mult()
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		var d: Vector2 = Vector2(cos(angle), sin(angle))
		_spawn_projectile(
			from_pos + d * (owner_player.radius + 4),
			d * volley_speed,
			dmg,
			Color(1, 1, 1),
			volley_lifetime,
			volley_radius,
			0,
			{"sprite_path": "res://assets/images/arrow.png", "sprite_size": Vector2(56.0, 22.0)},
		)
	AudioBus.play_at(&"crossbow_shoot", from_pos)
