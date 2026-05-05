extends Node2D

# Floating damage number. Local-only (spawned by the arena on every peer in
# response to the host's damage RPC). Floats up, drifts a bit, fades, frees.

const LIFETIME := 0.75
const RISE := 44.0

var amount: int = 0
var crit: bool = false
var elapsed: float = 0.0
var _origin_y: float = 0.0
var _drift_x: float = 0.0
var _font: Font

func _ready() -> void:
	z_index = 200
	z_as_relative = false
	_origin_y = position.y
	_drift_x = randf_range(-12.0, 12.0)
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LIFETIME:
		queue_free()
		return
	var t: float = elapsed / LIFETIME
	position.y = _origin_y - RISE * (1.0 - pow(1.0 - t, 2.0))
	position.x += _drift_x * delta * (1.0 - t)
	queue_redraw()

func _draw() -> void:
	var t: float = elapsed / LIFETIME
	var alpha: float = clampf(1.2 - t * 1.2, 0.0, 1.0)
	var fs: int = 20 if crit else 16
	var text: String = str(amount)
	var size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var origin := Vector2(-size.x * 0.5, 0.0)
	for ox in [-1, 1]:
		for oy in [-1, 1]:
			draw_string(_font, origin + Vector2(ox, oy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha))
	var col := Color(1, 0.95, 0.45, alpha) if not crit else Color(1, 0.55, 0.25, alpha)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
