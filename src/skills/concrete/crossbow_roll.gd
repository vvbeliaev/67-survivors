extends Skill

# Combat roll with i-frames.

@export var distance: float = 160.0
@export var iframe_duration: float = 0.5

func _init() -> void:
	base_cooldown = 5.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.move_dir() if owner_player.move_dir().length_squared() > 0.01 else owner_player.aim_dir
	var from: Vector2 = owner_player.global_position
	owner_player.teleport(from + dir.normalized() * distance)
	owner_player.grant_iframes(iframe_duration)
	owner_player.emit_fx("roll", {"from": from})
