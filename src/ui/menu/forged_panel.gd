@tool
class_name ForgedPanel
extends PanelContainer

## A dark "forged iron" panel with corner brackets and rivets.

@export var bracket_color: Color = Color(0.54, 0.37, 0.12, 1.0)
@export var inner_bracket_color: Color = Color(0.42, 0.35, 0.27, 0.6)
@export var bracket_size: float = 28.0
@export var bracket_inset: float = 14.0
@export var rivet_color: Color = Color(0.66, 0.56, 0.43, 1.0)
@export var rivet_dark: Color = Color(0.10, 0.07, 0.04, 1.0)
@export var rivet_radius: float = 3.0
@export var rivet_inset: float = 10.0
@export var draw_rivets: bool = true
@export var draw_brackets: bool = true

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var s: Vector2 = size
	if draw_brackets:
		_draw_bracket(Vector2(bracket_inset, bracket_inset), 1)
		_draw_bracket(Vector2(s.x - bracket_inset, bracket_inset), 2)
		_draw_bracket(Vector2(bracket_inset, s.y - bracket_inset), 3)
		_draw_bracket(Vector2(s.x - bracket_inset, s.y - bracket_inset), 4)
	if draw_rivets:
		_draw_rivet(Vector2(rivet_inset, rivet_inset))
		_draw_rivet(Vector2(s.x - rivet_inset, rivet_inset))
		_draw_rivet(Vector2(rivet_inset, s.y - rivet_inset))
		_draw_rivet(Vector2(s.x - rivet_inset, s.y - rivet_inset))

func _draw_bracket(origin: Vector2, corner: int) -> void:
	# corner 1=TL, 2=TR, 3=BL, 4=BR
	var dx: float = 1.0 if corner == 1 or corner == 3 else -1.0
	var dy: float = 1.0 if corner == 1 or corner == 2 else -1.0
	var p0 := origin + Vector2(0, bracket_size * dy)
	var p1 := origin
	var p2 := origin + Vector2(bracket_size * dx, 0)
	draw_line(p0, p1, bracket_color, 1.5, true)
	draw_line(p1, p2, bracket_color, 1.5, true)
	# inner echo
	var off := Vector2(4 * dx, 4 * dy)
	var ip0 := p0 + Vector2(off.x, 0)
	var ip1 := p1 + off
	var ip2 := p2 + Vector2(0, off.y)
	draw_line(ip0, ip1, inner_bracket_color, 1.0, true)
	draw_line(ip1, ip2, inner_bracket_color, 1.0, true)

func _draw_rivet(c: Vector2) -> void:
	draw_circle(c + Vector2(0.5, 0.5), rivet_radius + 0.5, rivet_dark)
	draw_circle(c, rivet_radius, rivet_color)
	draw_circle(c - Vector2(rivet_radius * 0.35, rivet_radius * 0.35), rivet_radius * 0.35, Color(rivet_color.r * 1.25, rivet_color.g * 1.18, rivet_color.b * 1.05, 0.9))
