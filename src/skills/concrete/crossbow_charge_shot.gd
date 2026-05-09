extends Skill

# Hold LMB to charge: pauses the auto and accumulates a damage multiplier.
# On release, fires one bolt through the auto-skill — but only if the auto's
# cooldown is ready. If it isn't, the release does nothing (charge wasted).
# This skill has no cooldown of its own; it's effectively a passive trigger.
#
# Легендарка «Болтомёт» (`legendary_crossbow_minigun`) полностью меняет ЛКМ:
# вместо зарядки персонаж стреляет очередью каждые MINIGUN_RATE секунд, пока
# ЛКМ удерживают. Каждый болт жрёт MINIGUN_COST «перегрева» (= игроцкая
# мана: max_mp + динамический регенный мод управляются в crossbow.on_pre_move).
# При mp < cost — стрельба гаснет до отката. Замедления при удержании нет
# (charge_started_at не трогается, поэтому crossbow.on_pre_move slow не накладывает).

const CrossbowAutoBolt := preload("res://src/skills/concrete/crossbow_auto_bolt.gd")

const MINIGUN_UPGRADE: StringName = &"legendary_crossbow_minigun"
const MINIGUN_RATE: float = 0.25  # секунд между болтами
const MINIGUN_COST: float = 15.0  # «перегрева» на болт

@export var min_charge: float = 0.4
@export var max_charge: float = 1.5
@export var damage_max_mult: float = 4.0

var _minigun_next_at: float = 0.0
# Время последнего минигановского выстрела. crossbow.on_pre_move читает это,
# чтобы решать, включён ли реген перегрева (≥1с с последнего выстрела).
var _minigun_last_shot_at: float = -1.0e9

func _init() -> void:
	icon = preload("res://assets/images/icons/crosshair.svg")

func on_pressed() -> void:
	# В минигановском режиме первое нажатие — мгновенный выстрел (если есть
	# заряд). Сбрасываем гейт next_at в прошлое.
	if _has_upgrade(MINIGUN_UPGRADE):
		_minigun_next_at = 0.0

func on_held(_delta: float) -> void:
	if _has_upgrade(MINIGUN_UPGRADE):
		_minigun_tick()
		return
	if owner_player.charge_started_at < 0.0:
		owner_player.charge_started_at = _now()
		AudioBus.play_at(&"crossbow_charge", owner_player.global_position)

func on_released() -> void:
	if _has_upgrade(MINIGUN_UPGRADE):
		return  # в режиме болтомёта релиз ничего не делает
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

func _minigun_tick() -> void:
	var now: float = _now()
	if now < _minigun_next_at:
		return
	if owner_player.mp < MINIGUN_COST:
		return
	if owner_player.class_node == null:
		return
	var auto: CrossbowAutoBolt = owner_player.class_node.auto_skill as CrossbowAutoBolt
	if auto == null:
		return
	owner_player.mp -= MINIGUN_COST
	_minigun_next_at = now + MINIGUN_RATE
	_minigun_last_shot_at = now
	auto.fire_volley(1.0)
