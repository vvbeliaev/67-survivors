extends Skill

# Heal aura. Three pulses over ~1.5s; each pulse heals every nearby ally.

@export var radius: float = 180.0
@export var heal_per_pulse: float = 8.0
@export var pulse_count: int = 3
@export var pulse_interval: float = 0.5

func _init() -> void:
	base_cooldown = 6.0
	icon = preload("res://assets/images/icons/heart-bottle.svg")

var _pulses_left: int = 0
var _next_pulse_in: float = 0.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	trigger_visual_fx("heal", {"r": radius * owner_player.range_mult()})
	AudioBus.play_at(&"bard_buff", owner_player.global_position)
	_pulses_left = pulse_count
	_next_pulse_in = 0.0
	owner_player.emit_fx("heal", {"r": radius * owner_player.range_mult()})

func on_tick(delta: float) -> void:
	if _pulses_left <= 0:
		return
	_next_pulse_in -= delta
	if _next_pulse_in > 0.0:
		return
	_next_pulse_in = pulse_interval
	_pulses_left -= 1
	var r: float = radius * owner_player.range_mult()
	for p in Targeting.players_in_radius(get_tree(), owner_player.global_position, r):
		p.heal(heal_per_pulse)
