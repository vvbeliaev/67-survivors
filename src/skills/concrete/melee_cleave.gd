extends Skill

# Berserker auto-attack: cleave-конус перед игроком (направление = aim_dir).
# С легендаркой `berserker_circle` переключается в круговой AoE (бывший
# MeleeSwirl). Чередуется визуально между «взмахом слева» и «взмахом справа»
# для разнообразия (логически идентично).

@export var radius: float = 80.0       # длина дуги (= range)
@export var arc_deg: float = 90.0      # ширина конуса в градусах
@export var damage: float = 12.0       # базовый урон, тот же, что был у swirl

var _swing_index: int = 0  # 0/1 — для FX-чередования направления взмаха

func _init() -> void:
	base_cooldown = 0.4
	icon = preload("res://assets/images/icons/axe-swing.svg")

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	var dmg: float = damage * owner_player.dmg_mult()
	if _has_upgrade(&"berserker_circle"):
		_aoe_damage(owner_player.global_position, r, dmg)
		trigger_visual_fx("auto", {"r": r, "shape": "circle"})
	else:
		var aim: Vector2 = owner_player.aim_dir
		var half_arc: float = deg_to_rad(arc_deg) * 0.5
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
			"shape": "cone",
			"arc": arc_deg,
			"swing": swing,
		})
