@tool
class_name MenuDiamond
extends Control

@export var fill_color: Color = Color(0.83, 0.63, 0.29, 1.0)
@export var deep_color: Color = Color(0.54, 0.37, 0.12, 1.0)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var glow: bool = true

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(18, 18)

func _draw() -> void:
	var s: Vector2 = size
	var cx: float = s.x * 0.5
	var cy: float = s.y * 0.5
	var pts := PackedVector2Array([
		Vector2(cx, 0),
		Vector2(s.x, cy),
		Vector2(cx, s.y),
		Vector2(0, cy),
	])
	if glow:
		var g_pts := PackedVector2Array([
			Vector2(cx, -2), Vector2(s.x + 2, cy),
			Vector2(cx, s.y + 2), Vector2(-2, cy),
		])
		draw_colored_polygon(g_pts, Color(fill_color.r, fill_color.g, fill_color.b, 0.18))
	draw_colored_polygon(pts, fill_color)
	var _ignored := deep_color
	var inner := PackedVector2Array([
		Vector2(cx, s.y * 0.18),
		Vector2(s.x * 0.82, cy),
		Vector2(cx, s.y * 0.82),
		Vector2(s.x * 0.18, cy),
	])
	draw_colored_polygon(inner, Color(fill_color.r * 1.18, fill_color.g * 1.12, fill_color.b * 0.98, 0.55))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), border_color, 1.0, true)
