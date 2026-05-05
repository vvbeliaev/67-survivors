extends Node2D

# Pure presentation. Body sprite (animated for known archetypes; falls back to
# a colored circle), HP bar, boss telegraph ring.

const RUSHER_FRAMES: Array[Texture2D] = [
	preload("res://assets/images/spider_1.png"),
	preload("res://assets/images/spider_2.png"),
	preload("res://assets/images/spider_3.png"),
]
const RUSHER_FRAME_DURATION := 0.18  # seconds per frame
const SPRITE_SIZE_MULT := 4.0

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
	var frames: Array[Texture2D] = _frames_for(_enemy.enemy_type)
	if frames.is_empty():
		draw_circle(Vector2.ZERO, _enemy.radius, _enemy.color_hint)
	else:
		_draw_animated_sprite(frames)
	if _enemy.hp < _enemy.max_hp:
		var w: float = _enemy.radius * 2.4
		var h := 4.0
		var top := Vector2(-w * 0.5, -_enemy.radius - 10)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(_enemy.hp / max(_enemy.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.95, 0.3, 0.3))
	if _enemy.boss_aoe and _enemy.boss_aoe_state == 1:
		draw_arc(_enemy.boss_aoe_pos - _enemy.global_position, _enemy.boss_aoe_radius, 0, TAU, 48, Color(1, 0.2, 0.2, 0.7), 3.0)

func _frames_for(t: StringName) -> Array[Texture2D]:
	match t:
		&"rusher":
			return RUSHER_FRAMES
		_:
			return []

func _draw_animated_sprite(frames: Array[Texture2D]) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var idx: int = int(t / RUSHER_FRAME_DURATION) % frames.size()
	var tex: Texture2D = frames[idx]
	var s: float = _enemy.radius * SPRITE_SIZE_MULT
	# Source sprite faces UP (Y-). Add +π/2 so it aligns with facing_dir
	# (which is in standard math angle, +X = 0, +Y = π/2).
	var rot: float = _enemy.facing_dir.angle() + PI * 0.5
	var tint := Color(1, 1, 1, 1)
	if not _enemy.alive:
		tint = Color(1, 1, 1, 0.45)
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
