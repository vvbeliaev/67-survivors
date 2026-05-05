class_name ThemedBar extends Control

# Stat bar with custom drawing: dark inset background, gradient fill,
# optional segmentation marks, optional inline label. Used for HP / MP /
# XP / progress in the HUD.

enum Kind { HEALTH, MANA, XP, HEAL, NEUTRAL }

@export var value: float = 100.0
@export var max_value: float = 100.0
@export var kind: Kind = Kind.HEALTH
@export var segments: bool = false
@export var segment_step: float = 24.0   # pixels per segment
@export var label_text: String = ""      # if non-empty, drawn centered
@export var label_color: Color = HUDPalette.INK
@export var label_font: Font = null
@export var label_font_size: int = 11
@export var bar_height_override: float = -1.0   # if >0, override Control height

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_progress(v: float, mx: float) -> void:
	value = v
	max_value = mx
	queue_redraw()

func _get_minimum_size() -> Vector2:
	var h := bar_height_override if bar_height_override > 0.0 else 12.0
	return Vector2(40, h)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0 or r.size.y <= 0:
		return

	# Background — deep dark inset.
	draw_rect(r, Color(0.039, 0.024, 0.016, 1.0), true)
	draw_rect(r.grow(-1), HUDPalette.SHADOW, false, 1.0)

	# Fill.
	var pct: float = 0.0
	if max_value > 0.0:
		pct = clampf(value / max_value, 0.0, 1.0)
	if pct > 0.0:
		var fill_w: float = r.size.x * pct
		var fill_rect := Rect2(r.position, Vector2(fill_w, r.size.y))
		var fill_top: Color
		var fill_mid: Color
		var fill_bot: Color
		match kind:
			Kind.HEALTH:
				fill_top = HUDPalette.HEALTH_BRIGHT
				fill_mid = HUDPalette.HEALTH_MID
				fill_bot = HUDPalette.HEALTH_DARK
			Kind.MANA:
				fill_top = HUDPalette.MANA_BRIGHT
				fill_mid = HUDPalette.MANA_MID
				fill_bot = HUDPalette.MANA_DARK
			Kind.XP:
				fill_top = HUDPalette.XP_BRIGHT
				fill_mid = HUDPalette.XP_MID
				fill_bot = HUDPalette.XP_DARK
			Kind.HEAL:
				fill_top = HUDPalette.HEAL_BRIGHT
				fill_mid = HUDPalette.HEAL_MID
				fill_bot = HUDPalette.HEAL_DARK
			_:
				fill_top = HUDPalette.METAL_LIGHT
				fill_mid = HUDPalette.METAL
				fill_bot = HUDPalette.STROKE
		_draw_3stop_gradient(fill_rect, fill_top, fill_mid, fill_bot)
		# Top sheen.
		draw_rect(Rect2(fill_rect.position + Vector2(0, 0), Vector2(fill_rect.size.x, 1)), Color(1, 1, 1, 0.20), true)

	# Segments overlay.
	if segments and segment_step > 1.0:
		var x := segment_step
		while x < r.size.x:
			draw_line(Vector2(x, 1), Vector2(x, r.size.y - 1), Color(0, 0, 0, 0.35), 1.0)
			x += segment_step

	# Border.
	draw_rect(r, HUDPalette.STROKE_STRONG, false, 1.0)

	# Inline label.
	if label_text != "" and label_font != null:
		var fs := label_font_size
		var ts := label_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos := Vector2(
			r.position.x + (r.size.x - ts.x) * 0.5,
			r.position.y + (r.size.y + ts.y) * 0.5 - 2.0
		)
		# Shadow pass.
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				draw_string(label_font, pos + Vector2(dx, dy), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
		draw_string(label_font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_color)

func _draw_3stop_gradient(r: Rect2, top: Color, mid: Color, bot: Color) -> void:
	# 6-band linear blend top→mid→bot. Cheaper than a shader, looks fine.
	var n := 6
	var h := r.size.y / float(n)
	for i in n:
		var t := float(i) / float(n - 1) if n > 1 else 0.0
		var col: Color
		if t < 0.5:
			col = top.lerp(mid, t * 2.0)
		else:
			col = mid.lerp(bot, (t - 0.5) * 2.0)
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h + 1)), col, true)
