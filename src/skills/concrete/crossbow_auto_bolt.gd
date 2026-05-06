extends Skill

# Crossbow auto: fires toward the cursor when LMB isn't held. Holding LMB
# pauses the auto entirely (charge primary takes over and fires through this
# skill on release). Pierce and multishot stats apply here — the auto is the
# only thing that actually shoots a bolt.

@export var damage: float = 8.0
@export var projectile_speed: float = 520.0
@export var projectile_lifetime: float = 2.5
@export var projectile_radius: float = 2.5

func _init() -> void:
	base_cooldown = 1.0
	icon = preload("res://assets/images/icons/arrowhead.svg")

func on_tick(_delta: float) -> void:
	if owner_player.charge_started_at >= 0.0 or owner_player._in_primary_held:
		return
	if not ready_to_cast():
		return
	fire_volley(1.0)
	start_cooldown()

# Public: called by crossbow_charge_shot.on_released to fire one bolt with a
# damage multiplier from charge time. Caller is responsible for cooldown.
func fire_volley(charge_mult: float) -> void:
	var dir: Vector2 = owner_player.aim_dir
	var origin: Vector2 = owner_player.global_position + dir * (owner_player.radius + 4)
	var bolt_flat: float = owner_player.stats.value(StatBlock.STAT_BOLT_DAMAGE)
	var dmg: float = (damage + bolt_flat) * charge_mult * owner_player.dmg_mult()
	var pierce: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_PIERCE))
	var multishot: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_MULTISHOT))
	_fire_bolt(origin, dir, dmg, pierce)
	for i in range(1, multishot + 1):
		var step: int = (i + 1) / 2
		var sgn: float = 1.0 if (i % 2) == 1 else -1.0
		var angle: float = deg_to_rad(12.0) * step * sgn
		var d: Vector2 = dir.rotated(angle)
		_fire_bolt(origin, d, dmg, pierce)
	trigger_visual_fx("auto", {})
	AudioBus.play_at(&"crossbow_shoot", owner_player.global_position)

func _fire_bolt(pos: Vector2, dir: Vector2, dmg: float, pierce: int) -> void:
	_spawn_projectile(
		pos,
		dir * projectile_speed,
		dmg,
		Color(1, 1, 1),
		projectile_lifetime,
		projectile_radius,
		pierce,
		{"sprite_path": "res://assets/images/arrow.png", "sprite_size": Vector2(56.0, 22.0)},
	)
