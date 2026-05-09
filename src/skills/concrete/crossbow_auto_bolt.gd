extends Skill

# Crossbow auto: fires toward the cursor when LMB isn't held. Holding LMB
# pauses the auto entirely (charge primary takes over and fires through this
# skill on release). Pierce and multishot stats apply here — the auto is the
# only thing that actually shoots a bolt.

@export var damage: float = 8.0
@export var projectile_speed: float = 520.0
@export var projectile_lifetime: float = 2.5
@export var projectile_radius: float = 2.5

func _init() -> void:
	base_cooldown = 1.0
	icon = preload("res://assets/images/icons/arrowhead.svg")

const MINIGUN_UPGRADE: StringName = &"legendary_crossbow_minigun"
const UNCHARGED_CRIT_MULT: float = 2.0
const PUSHBACK_UPGRADE: StringName = &"legendary_crossbow_pushback"
# База отталкивания (px/сек). Финальная сила = PUSHBACK_BASE × charge_mult.
# Через KNOCKBACK_DECAY=12 в Enemy: смещение ≈ force / 12 px.
# Незаряженный (mult=1) → ~25px; макс заряд (mult=4) → ~100px; крит (mult=2) → ~50px.
const PUSHBACK_BASE: float = 300.0

func on_tick(_delta: float) -> void:
	# Легендарка «Болтомёт»: автоатака полностью отключается, стрельба идёт
	# только через удержание ЛКМ в crossbow_charge_shot._minigun_tick.
	if _has_upgrade(MINIGUN_UPGRADE):
		return
	if owner_player.charge_started_at >= 0.0 or owner_player._in_primary_held:
		return
	if not ready_to_cast():
		return
	fire_volley(1.0)
	start_cooldown()

# Public: called by crossbow_charge_shot.on_released to fire one bolt with a
# damage multiplier from charge time. Caller is responsible for cooldown.
func fire_volley(charge_mult: float) -> void:
	var dir: Vector2 = owner_player.aim_dir
	# On touch builds the player can't aim a cursor, so the auto-bolt snaps
	# to the nearest enemy at fire-time. Resolved here (not every input
	# tick) so the cost stays at ~one targeting query per second.
	if GameState.is_touch_ui():
		var nearest := Targeting.nearest_enemy(get_tree(), owner_player.global_position, 1800.0)
		if nearest == null:
			return
		dir = (nearest.global_position - owner_player.global_position).normalized()
	var origin: Vector2 = owner_player.global_position + dir * (owner_player.radius + 4)
	var bolt_flat: float = owner_player.stats.value(StatBlock.STAT_BOLT_DAMAGE)
	# Эпик «Молниеносный болт»: на незаряженных выстрелах (charge_mult≈1.0)
	# шанс крита читается из STAT_UNCHARGED_CRIT_CHANCE (35% за стак, до 2-х).
	# Болтомёт-очередь тоже идёт через charge_mult=1.0 → тоже может крит'ить.
	if charge_mult <= 1.001:
		var crit_chance: float = float(owner_player.stats.value(StatBlock.STAT_UNCHARGED_CRIT_CHANCE))
		if crit_chance > 0.0 and randf() < crit_chance:
			charge_mult = UNCHARGED_CRIT_MULT
	var dmg: float = (damage + bolt_flat) * charge_mult * owner_player.dmg_mult()
	var pierce: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_PIERCE))
	var multishot: int = int(owner_player.stats.value(StatBlock.STAT_CHARGE_MULTISHOT))
	# Отталкивание скейлится с charge_mult — заряженный болт толкает сильнее.
	var pushback: float = PUSHBACK_BASE * charge_mult if _has_upgrade(PUSHBACK_UPGRADE) else 0.0
	_fire_bolt(origin, dir, dmg, pierce, pushback)
	for i in range(1, multishot + 1):
		var step: int = (i + 1) / 2
		var sgn: float = 1.0 if (i % 2) == 1 else -1.0
		var angle: float = deg_to_rad(12.0) * step * sgn
		var d: Vector2 = dir.rotated(angle)
		_fire_bolt(origin, d, dmg, pierce, pushback)
	trigger_visual_fx("auto", {})
	AudioBus.play_at(&"crossbow_shoot", owner_player.global_position)

func _fire_bolt(pos: Vector2, dir: Vector2, dmg: float, pierce: int, pushback: float = 0.0) -> void:
	_spawn_projectile(
		pos,
		dir * projectile_speed,
		dmg,
		Color(1, 1, 1),
		projectile_lifetime,
		projectile_radius,
		pierce,
		{
			"sprite_path": "res://assets/images/arrow.png",
			"sprite_size": Vector2(56.0, 22.0),
			"pushback_force": pushback,
		},
	)
