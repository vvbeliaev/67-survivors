extends Node2D

# Static map prop. Casts a flickering warm light + draws a small flame visual.
# Pure presentation: no replication, no host/client distinction. Each peer
# spawns the same torches at the same positions (deterministic seed in
# Arena._spawn_torches), so positions agree without per-tick sync.

const FLAME_CORE := Color(1.0, 0.95, 0.55, 0.95)
const FLAME_GLOW := Color(1.0, 0.55, 0.2, 0.45)
const LIGHT_COLOR := Color(1.0, 0.7, 0.35)
const FLICKER_FAST := 9.0
const FLICKER_SLOW := 2.3
const BASE_ENERGY := 1.05
const ENERGY_AMPL := 0.18

@onready var light: PointLight2D = $Light

var _phase: float = 0.0

func _ready() -> void:
	z_index = 0
	_phase = randf() * TAU
	light.texture = _make_radial_texture()
	light.color = LIGHT_COLOR
	light.energy = BASE_ENERGY
	light.texture_scale = 4.0
	light.range_layer_min = -1
	light.range_layer_max = 2

func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	light.energy = BASE_ENERGY + ENERGY_AMPL * (sin(t * FLICKER_FAST + _phase) * 0.6 + sin(t * FLICKER_SLOW + _phase * 0.5) * 0.4)
	queue_redraw()

func _draw() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 1.0 + 0.15 * sin(t * FLICKER_FAST + _phase)
	# Wood post (small dark rectangle).
	draw_rect(Rect2(Vector2(-2.5, -2), Vector2(5, 14)), Color(0.25, 0.18, 0.12))
	# Flame glow + core, jittered slightly.
	var jitter := Vector2(sin(t * 11.0 + _phase) * 1.0, -2.0 - cos(t * 7.0 + _phase) * 0.6)
	draw_circle(jitter, 9.0 * pulse, FLAME_GLOW)
	draw_circle(jitter, 4.5 * pulse, FLAME_CORE)

static func _make_radial_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	# Soft falloff via interpolation curve.
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex
