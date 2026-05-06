extends Skill

# Held-charge primary. Holding LMB starts the charge (slows movement via the
# class node), releasing fires a bolt whose damage and speed scale with charge
# time. Records `charge_started_at` on the player so the view can render it.

@export var min_charge: float = 0.4
@export var max_charge: float = 1.5
@export var damage_min: float = 12.0
@export var damage_max: float = 45.0
@export var speed_base: float = 520.0
@export var speed_bonus: float = 200.0

func _init() -> void:
	# Short post-shot cooldown only; gating is via charge_started_at.
	base_cooldown = 0.25

func on_held(_delta: float) -> void:
	if owner_player.charge_started_at < 0.0:
		owner_player.charge_started_at = _now()
		AudioBus.play_at(&"crossbow_charge", owner_player.global_position)

func on_released() -> void:
	if owner_player.charge_started_at < 0.0:
		return
	if cooldown_left > 0.0:
		owner_player.charge_started_at = -1.0
		return
	var charge_t: float = clampf(_now() - owner_player.charge_started_at, 0.0, max_charge)
	owner_player.charge_started_at = -1.0
	start_cooldown()
	var t: float = clampf((charge_t - min_charge) / (max_charge - min_charge), 0.0, 1.0)
	var dmg: float = damage_min + (damage_max - damage_min) * t
	var speed: float = speed_base + speed_bonus * t
	var pierce: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_PIERCE))
	var multishot: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_MULTISHOT))
	trigger_visual_fx("shot", {})
	AudioBus.play_at(&"crossbow_shoot", owner_player.global_position)
	var origin: Vector2 = owner_player.global_position + owner_player.aim_dir * (owner_player.radius + 4)
	var final_dmg: float = dmg * owner_player.dmg_mult()
	_fire_bolt(origin, owner_player.aim_dir, speed, final_dmg, pierce)
	for i in range(1, multishot + 1):
		var step: int = (i + 1) / 2
		var sgn: float = 1.0 if (i % 2) == 1 else -1.0
		var angle: float = deg_to_rad(12.0) * step * sgn
		var dir: Vector2 = owner_player.aim_dir.rotated(angle)
		_fire_bolt(origin, dir, speed, final_dmg, pierce)
	owner_player.emit_fx("shot", {})

func _fire_bolt(pos: Vector2, dir: Vector2, speed: float, dmg: float, pierce: int) -> void:
	_spawn_projectile(
		pos,
		dir * speed,
		dmg,
		Color(1, 1, 1),
		2.5,
		5.0,
		pierce,
		{"sprite_path": "res://assets/images/arrow.png", "sprite_size": Vector2(56.0, 22.0)},
	)
