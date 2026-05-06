extends Skill

# Hold LMB to charge: pauses the auto and accumulates a damage multiplier.
# On release, fires one bolt through the auto-skill — but only if the auto's
# cooldown is ready. If it isn't, the release does nothing (charge wasted).
# This skill has no cooldown of its own; it's effectively a passive trigger.

const CrossbowAutoBolt := preload("res://src/skills/concrete/crossbow_auto_bolt.gd")

@export var min_charge: float = 0.4
@export var max_charge: float = 1.5
@export var damage_max_mult: float = 4.0

func _init() -> void:
	icon = preload("res://assets/images/icons/crosshair.svg")

func on_held(_delta: float) -> void:
	if owner_player.charge_started_at < 0.0:
		owner_player.charge_started_at = _now()
		AudioBus.play_at(&"crossbow_charge", owner_player.global_position)

func on_released() -> void:
	if owner_player.charge_started_at < 0.0:
		return
	var t_held: float = _now() - owner_player.charge_started_at
	owner_player.charge_started_at = -1.0
	if owner_player.class_node == null:
		return
	var auto: CrossbowAutoBolt = owner_player.class_node.auto_skill as CrossbowAutoBolt
	if auto == null:
		return
	if auto.cooldown_left > 0.0:
		return
	var t_capped: float = clampf(t_held, 0.0, max_charge)
	var t: float = clampf((t_capped - min_charge) / (max_charge - min_charge), 0.0, 1.0)
	var charge_dmg: float = owner_player.stats.value(StatBlock.STAT_CHARGE_DAMAGE)
	var mult: float = lerp(1.0, damage_max_mult * charge_dmg, t)
	auto.fire_volley(mult)
	auto.start_cooldown()
	owner_player.emit_fx("shot", {})
