extends Skill

# Berserker auto-attack: AoE swirl around the player on a tight cooldown.

@export var radius: float = 80.0
@export var damage: float = 12.0

func _init() -> void:
	base_cooldown = 0.4
	icon = preload("res://assets/images/icons/axe-swing.svg")

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	_aoe_damage(owner_player.global_position, r, damage * owner_player.dmg_mult())
	trigger_visual_fx("auto", {"r": r})
