extends Skill

# Forces enemies in a radius to target this player for a few seconds.

@export var radius: float = 240.0
@export var hold_duration: float = 4.0

func _init() -> void:
	base_cooldown = 8.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	for e in Targeting.enemies_in_radius(get_tree(), owner_player.global_position, r):
		if e.has_method("force_target"):
			e.force_target(owner_player.peer_id, hold_duration)
	trigger_visual_fx("roar", {"r": r})
