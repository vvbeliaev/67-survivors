extends Skill

# Berserker auto-attack: cleave-конус перед игроком (направление = aim_dir).
# Чередуется визуально между «взмахом слева» и «взмахом справа» для
# разнообразия (логически идентично). Ширина конуса арки растёт от
# апгрейдов через `STAT_SLASH_ARC` (FLAT, в градусах).

@export var radius: float = 80.0       # длина дуги (= range)
@export var arc_deg: float = 90.0      # базовая ширина конуса в градусах
@export var damage: float = 12.0       # базовый урон

# Жёсткий пол на длительность авто-кд: даже при максимуме «Кровавой ярости»
# и стопке cooldown-апгрейдов чаще, чем раз в 0.3с, варвар не машет.
const AUTO_FLOOR_SECONDS: float = 0.3

var _swing_index: int = 0  # 0/1 — для FX-чередования направления взмаха

func _init() -> void:
	base_cooldown = 0.4
	icon = preload("res://assets/images/icons/axe-swing.svg")

# Override: помимо общего STAT_COOLDOWN применяем STAT_AUTO_ATTACK_SPEED
# (кд только автоатаки, не других скиллов) и фиксим финальное значение
# полом AUTO_FLOOR_SECONDS — 0.3с между cleave'ами как минимум.
func start_cooldown() -> void:
	var general_cd: float = float(owner_player.cooldown_factor())
	var auto_speed: float = float(owner_player.stats.value(StatBlock.STAT_AUTO_ATTACK_SPEED))
	if auto_speed <= 0.0:
		auto_speed = 1.0
	cooldown_left = max(base_cooldown * general_cd * auto_speed, AUTO_FLOOR_SECONDS)

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	var dmg: float = damage * owner_player.dmg_mult()
	var arc_bonus: float = owner_player.stats.value(StatBlock.STAT_SLASH_ARC)
	var effective_arc: float = arc_deg + arc_bonus
	var aim: Vector2 = owner_player.aim_dir
	var half_arc: float = deg_to_rad(effective_arc) * 0.5
	# Хитбокс конуса на 20% длиннее визуала — чтобы враги, чей центр чуть
	# дальше видимого кончика клинка, всё равно попадали под удар.
	_cone_damage(owner_player.global_position, aim, r * 1.2, half_arc, dmg)
	var swing := _swing_index
	_swing_index = (_swing_index + 1) % 2
	# Note: визуал берёт aim_dir игрока живьём в _draw, чтобы конус
	# доворачивался за курсором во время 0.25с-FX. Здесь передаём только
	# параметры, которые специфичны для именно этого удара (arc и swing
	# для альтернации). aim_x/aim_y НЕ передаём — устаревший снэпшот
	# направления только сбивал бы с толку, если упгрейд изменит arc.
	trigger_visual_fx("auto", {
		"r": r,
		"arc": effective_arc,
		"swing": swing,
	})
