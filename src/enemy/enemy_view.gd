extends Node2D

# Pure presentation for enemies: body, HP bar, and boss telegraph ring.

@export var owner_path: NodePath = NodePath("..")

var _enemy: Node = null

func _ready() -> void:
	_enemy = get_node(owner_path)
	z_index = 1

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	draw_circle(Vector2.ZERO, _enemy.radius, _enemy.color_hint)
	if _enemy.hp < _enemy.max_hp:
		var w: float = _enemy.radius * 2.4
		var h := 4.0
		var top := Vector2(-w * 0.5, -_enemy.radius - 10)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(_enemy.hp / max(_enemy.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.95, 0.3, 0.3))
	if _enemy.boss_aoe and _enemy.boss_aoe_state == 1:
		draw_arc(_enemy.boss_aoe_pos - _enemy.global_position, _enemy.boss_aoe_radius, 0, TAU, 48, Color(1, 0.2, 0.2, 0.7), 3.0)
