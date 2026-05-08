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
	if _has_upgrade(&"mage_echo_clone"):
		var arena := get_tree().get_first_node_in_group("arena")
		if arena != null and arena.has_method("spawn_echo_clone"):
			arena.spawn_echo_clone({
				"pos": from_pos,
				"owner_peer_id": int(owner_player.peer_id),
				"repeats": 3,
			})
