extends Skill

# Teleport directly to the cursor, any distance.

func _init() -> void:
	base_cooldown = 8.0
	icon = preload("res://assets/images/icons/teleport.svg")

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var target: Vector2 = owner_player.aim_world()
	var from_pos: Vector2 = owner_player.global_position
	if from_pos.distance_squared_to(target) <= 1.0:
		return
	owner_player.teleport(target)
	trigger_visual_fx("blink", {"from": from_pos, "to": owner_player.global_position})
	AudioBus.play_at(&"mage_cast", from_pos)
