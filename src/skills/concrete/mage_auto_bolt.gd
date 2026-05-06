extends Skill

# Mage auto: snaps to nearest enemy in range and fires a slow bolt.

@export var seek_range: float = 700.0
@export var damage: float = 8.0
@export var projectile_speed: float = 360.0
@export var projectile_lifetime: float = 2.5
@export var projectile_radius: float = 5.0

func _init() -> void:
	base_cooldown = 1.0

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	var target := Targeting.nearest_enemy(get_tree(), owner_player.global_position, seek_range * owner_player.range_mult())
	if target == null:
		return
	cooldown_left = base_cooldown / max(owner_player.atk_speed_mult(), 0.01)
	var dir: Vector2 = (target.global_position - owner_player.global_position).normalized()
	var mana_pct: float = owner_player.stats.value(StatBlock.STAT_MANA_ON_HIT)
	_spawn_projectile(
		owner_player.global_position + dir * (owner_player.radius + 4),
		dir * projectile_speed,
		damage * owner_player.dmg_mult(),
		Color(0.6, 0.7, 1.0),
		projectile_lifetime,
		projectile_radius,
		0,
		{"source_peer": int(owner_player.peer_id), "mana_on_hit_pct": mana_pct},
	)
	trigger_visual_fx("auto", {})
