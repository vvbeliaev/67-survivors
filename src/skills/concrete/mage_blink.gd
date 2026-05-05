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
	var from: Vector2 = owner_player.global_position
	var to: Vector2 = from + off.normalized() * d
	owner_player.teleport(to)
	owner_player.emit_fx("blink", {"from": from, "to": to})
