@tool
class_name StarRating
extends Control

@export_range(0, 5) var value: int = 2: set = set_value
@export var max_value: int = 5
@export var on_color: Color = Color(0.83, 0.63, 0.29, 1.0)
@export var off_color: Color = Color(0.42, 0.35, 0.27, 0.55)
@export var star_size: float = 14.0
@export var spacing: float = 4.0

func set_value(v: int) -> void:
	value = clamp(v, 0, max_value)
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(max_value * star_size + (max_value - 1) * spacing, star_size)

func _draw() -> void:
	var x: float = 0.0
	var cy: float = size.y * 0.5
	for i in range(max_value):
		var c: Color = on_color if i < value else off_color
		_draw_star(Vector2(x + star_size * 0.5, cy), star_size * 0.5, c)
		x += star_size + spacing

func _draw_star(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var inner_r: float = r * 0.42
	for i in range(10):
		var ang: float = -PI * 0.5 + i * PI / 5.0
		var rr: float = r if i % 2 == 0 else inner_r
		pts.append(center + Vector2(cos(ang) * rr, sin(ang) * rr))
	draw_colored_polygon(pts, col)
