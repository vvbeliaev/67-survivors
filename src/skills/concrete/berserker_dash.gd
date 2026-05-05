extends Skill

# Dash strike. Damage scales with missing HP (rage). Lands AoE at the dash
# endpoint plus a smaller pulse along the path's midpoint to mimic a line.

@export var dash_distance: float = 160.0
@export var endpoint_radius: float = 50.0
@export var endpoint_damage: float = 25.0
@export var path_pulse_damage: float = 15.0

func _init() -> void:
	base_cooldown = 1.2

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var range_mult: float = owner_player.range_mult()
	var rage: float = 1.0 + clampf((owner_player.max_hp - owner_player.hp) / max(owner_player.max_hp, 1.0), 0.0, 1.0)
	var dist: float = dash_distance * range_mult
	var start: Vector2 = owner_player.global_position
	owner_player.teleport(start + owner_player.aim_dir * dist)
	var dmg: float = owner_player.dmg_mult()
	_aoe_damage(owner_player.global_position, endpoint_radius * range_mult, endpoint_damage * dmg * rage)
	_aoe_damage((start + owner_player.global_position) * 0.5, dist * 0.5, path_pulse_damage * dmg * rage)
