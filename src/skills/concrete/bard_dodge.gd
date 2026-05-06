extends Skill

# Dodge dash with a brief i-frame window.

@export var distance: float = 180.0
@export var iframe_duration: float = 0.3

func _init() -> void:
	base_cooldown = 4.0
	icon = preload("res://assets/images/icons/dodging.svg")

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.move_dir() if owner_player.move_dir().length_squared() > 0.01 else owner_player.aim_dir
	var from_pos: Vector2 = owner_player.global_position
	owner_player.teleport(owner_player.global_position + dir.normalized() * distance)
	owner_player.grant_iframes(iframe_duration)
	trigger_visual_fx("dash", {"from": from_pos})
