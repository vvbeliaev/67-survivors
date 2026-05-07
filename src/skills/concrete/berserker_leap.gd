extends Skill

# Pure mobility leap. Short forward dash with brief i-frames, no damage.
# Used as the berserker's utility / mobile double-tap trigger; the rush
# strike on LMB stays the offensive option.

@export var distance: float = 220.0
@export var iframe_duration: float = 0.4

func _init() -> void:
	base_cooldown = 4.0
	icon = preload("res://assets/images/icons/winged-leg.svg")

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.move_dir() if owner_player.move_dir().length_squared() > 0.01 else owner_player.aim_dir
	var from_pos: Vector2 = owner_player.global_position
	owner_player.teleport(from_pos + dir.normalized() * distance)
	owner_player.grant_iframes(iframe_duration)
	trigger_visual_fx("dash", {"start": from_pos, "r": 30.0})
	AudioBus.play_at(&"berserker_swing", owner_player.global_position)
