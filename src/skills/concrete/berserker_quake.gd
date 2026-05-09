extends Skill

# Self-centred AoE that stuns and chips. Utility, not mobility.

@export var radius: float = 140.0
@export var damage: float = 8.0
@export var stun_duration: float = 1.5

func _init() -> void:
	base_cooldown = 12.0
	icon = preload("res://assets/images/icons/confrontation.svg")

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var stun_radius_mult: float = owner_player.stats.value(StatBlock.STAT_STUN_RADIUS)
	var stun_bonus: float = owner_player.stats.value(StatBlock.STAT_STUN_DURATION)
	var r: float = radius * owner_player.range_mult() * stun_radius_mult
	var dmg: float = damage * owner_player.dmg_mult()
	var total_stun: float = stun_duration + stun_bonus
	for e in Targeting.enemies_in_radius(get_tree(), owner_player.global_position, r):
		if e.has_method("stun"):
			e.stun(total_stun)
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
	trigger_visual_fx("quake", {"r": r})
	AudioBus.play_at(&"berserker_quake", owner_player.global_position)
