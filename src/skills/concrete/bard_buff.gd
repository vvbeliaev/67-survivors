extends Skill

# Group buff: +speed and +damage to allies in radius for a duration.

@export var radius: float = 180.0
@export var speed_pct: float = 0.20
@export var damage_pct: float = 0.20
@export var duration: float = 5.0

func _init() -> void:
	base_cooldown = 10.0
	icon = preload("res://assets/images/icons/musical-score.svg")

var _stack_serial: int = 0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	_stack_serial += 1
	var serial: int = _stack_serial
	var r: float = radius * owner_player.range_mult()
	var spd_id: StringName = StringName("buff_bard_spd_%d" % serial)
	var dmg_id: StringName = StringName("buff_bard_dmg_%d" % serial)
	for p in Targeting.players_in_radius(get_tree(), owner_player.global_position, r):
		p.apply_temp_pct_buff(StatBlock.STAT_SPEED, spd_id, speed_pct, duration)
		p.apply_temp_pct_buff(StatBlock.STAT_DMG, dmg_id, damage_pct, duration)
	trigger_visual_fx("buff", {"r": r})
	AudioBus.play_at(&"bard_buff", owner_player.global_position)
