extends Skill

# Self-centred AoE that stuns and chips. Utility, not mobility.

@export var radius: float = 140.0
@export var damage: float = 8.0
@export var stun_duration: float = 1.5

func _init() -> void:
	base_cooldown = 12.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	var dmg: float = damage * owner_player.dmg_mult()
	for e in Targeting.enemies_in_radius(get_tree(), owner_player.global_position, r):
		if e.has_method("stun"):
			e.stun(stun_duration)
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
