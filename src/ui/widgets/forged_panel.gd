class_name HUDPanel extends Control

# Drawn-from-scratch panel chrome: gradient fill, beveled border, optional
# corner rivets, optional accent border. Used as a backdrop everywhere in
# the HUD to emulate the "forged-flat" look from the design mock without
# having to author StyleBox resources.

@export var bevel: float = 10.0           # corner cut size (0 = sharp rect)
@export var rivets: bool = false          # draw 4 metal rivets at corners
@export var accent_border: bool = false   # gold border instead of bronze
@export var inner_glow: bool = true       # subtle highlight along top edge
@export var fill_top: Color = HUDPalette.PANEL
@export var fill_bottom: Color = HUDPalette.PANEL_SOFT
@export var border_color: Color = HUDPalette.STROKE_STRONG

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0 or r.size.y <= 0:
		return

	# Fill — vertical 2-stop gradient via two trapezoids.
	_draw_gradient_fill(r, fill_top, fill_bottom)

	# Inner shadow on top + bottom edges (faint).
	if inner_glow:
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), HUDPalette.HIGHLIGHT, true)

	# Inner dark line — the "inset 0 0 0 1px rgba(0,0,0,0.5)" from CSS.
	draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), HUDPalette.SHADOW_LIGHT, false, 1.0)

	# Outer border.
	var bc := HUDPalette.ACCENT_DEEP if accent_border else border_color
	draw_rect(r, bc, false, 1.0)

	# Beveled corner accents (small diagonal chips at each corner).
	if bevel > 0.0:
		_draw_corner_chips(r, bc)

	# Rivets at the corners.
	if rivets:
		var inset := 7.0
		_draw_rivet(r.position + Vector2(inset, inset))
		_draw_rivet(r.position + Vector2(r.size.x - inset, inset))
		_draw_rivet(r.position + Vector2(inset, r.size.y - inset))
		_draw_rivet(r.position + Vector2(r.size.x - inset, r.size.y - inset))

func _draw_gradient_fill(r: Rect2, top: Color, bot: Color) -> void:
	# Lightweight vertical gradient: 8 horizontal bands.
	var bands := 8
	var h := r.size.y / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1) if bands > 1 else 0.0
		var col := top.lerp(bot, t)
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h + 1)), col, true)

func _draw_corner_chips(r: Rect2, col: Color) -> void:
	# Tiny inward-facing chips: not a full clip-path bevel, but a hint at one.
	var b := bevel
	var c := col.lerp(HUDPalette.METAL, 0.3)
	# Top-left
	draw_line(r.position + Vector2(0, b), r.position + Vector2(b, 0), c, 1.0)
	# Top-right
	draw_line(r.position + Vector2(r.size.x - b, 0), r.position + Vector2(r.size.x, b), c, 1.0)
	# Bottom-left
	draw_line(r.position + Vector2(0, r.size.y - b), r.position + Vector2(b, r.size.y), c, 1.0)
	# Bottom-right
	draw_line(r.position + Vector2(r.size.x - b, r.size.y), r.position + Vector2(r.size.x, r.size.y - b), c, 1.0)

func _draw_rivet(center: Vector2) -> void:
	draw_circle(center, 3.0, HUDPalette.METAL)
	draw_circle(center, 2.0, HUDPalette.METAL_LIGHT)
	draw_circle(center - Vector2(0.7, 0.7), 0.8, Color(1, 1, 1, 0.4))
