@tool
class_name MenuButton67
extends Button

## A long horizontal menu button with diamond ornaments on each side.
## Designed to match the "Crypt of the Survivors" gothic UI.

@export var diamond_color: Color = Color(0.83, 0.63, 0.29, 1.0)
@export var diamond_deep: Color = Color(0.54, 0.37, 0.12, 1.0)
@export var diamond_size: Vector2 = Vector2(22, 22)
@export var diamond_inset: float = 14.0

func _ready() -> void:
	if custom_minimum_size.y < 56:
		custom_minimum_size.y = 64
	flat = false
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var s: Vector2 = size
	var hovered := is_hovered() or has_focus()
	var fill_col: Color = diamond_color
	if disabled:
		fill_col = Color(0.40, 0.32, 0.21, 0.8)
	elif hovered:
		fill_col = Color(min(diamond_color.r * 1.18, 1.0), min(diamond_color.g * 1.12, 1.0), min(diamond_color.b * 1.05, 1.0), 1.0)
	# Left diamond
	_draw_diamond(Vector2(diamond_inset, s.y * 0.5), diamond_size, fill_col)
	# Right diamond
	_draw_diamond(Vector2(s.x - diamond_inset, s.y * 0.5), diamond_size, fill_col)

func _draw_diamond(center: Vector2, ds: Vector2, col: Color) -> void:
	var hx: float = ds.x * 0.5
	var hy: float = ds.y * 0.5
	# subtle outer glow
	var glow_pts := PackedVector2Array([
		center + Vector2(0, -hy - 3),
		center + Vector2(hx + 3, 0),
		center + Vector2(0, hy + 3),
		center + Vector2(-hx - 3, 0),
	])
	draw_colored_polygon(glow_pts, Color(col.r, col.g, col.b, 0.18))
	var pts := PackedVector2Array([
		center + Vector2(0, -hy),
		center + Vector2(hx, 0),
		center + Vector2(0, hy),
		center + Vector2(-hx, 0),
	])
	draw_colored_polygon(pts, col)
	# Highlight inset
	var hi_pts := PackedVector2Array([
		center + Vector2(0, -hy * 0.55),
		center + Vector2(hx * 0.55, 0),
		center + Vector2(0, hy * 0.55),
		center + Vector2(-hx * 0.55, 0),
	])
	draw_colored_polygon(hi_pts, Color(min(col.r * 1.25, 1.0), min(col.g * 1.18, 1.0), min(col.b * 1.05, 1.0), 0.55))
	# border
	var border_pts := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(border_pts, Color(0, 0, 0, 0.6), 1.0, true)
