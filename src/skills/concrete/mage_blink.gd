extends Skill

# Short teleport toward the cursor.

@export var max_distance: float = 220.0

func _init() -> void:
	base_cooldown = 5.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var off: Vector2 = owner_player.aim_world() - owner_player.global_position
	var d: float = min(off.length(), max_distance)
	if d <= 0.0:
		return
	var from_pos: Vector2 = owner_player.global_position
	owner_player.teleport(owner_player.global_position + off.normalized() * d)
	trigger_visual_fx("blink", {"from": from_pos, "to": owner_player.global_position})
	AudioBus.play_at(&"mage_cast", from_pos)
