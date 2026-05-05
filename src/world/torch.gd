extends Node2D

# Static map prop. Casts a flickering warm light + draws the torch sprite.
# Pure presentation: no replication. Each peer spawns the same torches at
# the same positions (deterministic seed in Arena._spawn_torches).

const TORCH_TEX: Texture2D = preload("res://assets/images/torch.png")
const TORCH_DRAW_SIZE := 72.0
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
	var pulse: float = 1.0 + 0.04 * sin(t * FLICKER_FAST + _phase)
	var s: float = TORCH_DRAW_SIZE * pulse
	# Sprite has the flame in the upper half, so we offset upward a little so
	# the flame visually sits above the position the light emits from.
	var top_left := Vector2(-s * 0.5, -s * 0.65)
	draw_texture_rect(TORCH_TEX, Rect2(top_left, Vector2(s, s)), false)

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
