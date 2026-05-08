extends Skill

# Pure mobility leap. Short forward dash with brief i-frames, no damage.
# Used as the berserker's utility / mobile double-tap trigger; the rush
# strike on LMB stays the offensive option.

@export var distance: float = 220.0
@export var iframe_duration: float = 0.4

const IMPACT_RADIUS: float = 70.0   # AoE-радиус при срабатывании эпика «Таран»

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
	var to_pos: Vector2 = from_pos + dir.normalized() * distance
	owner_player.teleport(to_pos)
	owner_player.grant_iframes(iframe_duration)
	# Эпик «Таран»: AoE-удар в точке приземления, 300% от базового урона автоатаки.
	if _has_upgrade(&"epic_berserker_dash_auto"):
		var auto: Skill = owner_player.class_node.auto_skill if owner_player.class_node != null else null
		var auto_base_dmg: float = float(auto.damage) if auto != null and "damage" in auto else 0.0
		var dmg: float = auto_base_dmg * 3.0 * owner_player.dmg_mult()
		_aoe_damage(to_pos, IMPACT_RADIUS, dmg)
	trigger_visual_fx("dash", {"start": from_pos, "r": 30.0})
	AudioBus.play_at(&"berserker_swing", owner_player.global_position)
