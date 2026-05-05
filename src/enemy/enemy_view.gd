extends Node2D

# Pure presentation. Body sprite (animated for known archetypes; falls back to
# a colored circle), HP bar, boss telegraph ring.

const RUSHER_FRAMES: Array[Texture2D] = [
	preload("res://assets/images/spider_1.png"),
	preload("res://assets/images/spider_2.png"),
	preload("res://assets/images/spider_3.png"),
]
const RUSHER_FRAME_DURATION := 0.18
# Spider art has ~70% padding, so a 2.6x multiplier keeps the visible body
# only slightly bigger than the collision diameter — clusters no longer
# visually merge into one blob when they pile up on a player.
const SPRITE_SIZE_MULT := 2.6

const SWARM_FRAME_DURATION := 0.28
const SLIME_COLOR         := Color(0.25, 0.85, 0.20, 1.0)
const SLIME_TRAIL_COLOR   := Color(0.15, 0.72, 0.10)
const TRAIL_POINTS        := 10
const TRAIL_INTERVAL      := 0.07   # seconds between trail snapshots
const TRAIL_LIFETIME      := TRAIL_POINTS * TRAIL_INTERVAL

@export var owner_path: NodePath = NodePath("..")

var _enemy: Node = null

# Swarm trail: ring buffer of world positions + capture times.
var _trail: Array[Dictionary] = []
var _last_trail_t: float = -999.0

# Loaded at runtime so the game doesn't crash if slime sprites are missing.
var _swarm_frames: Array[Texture2D] = []

func _ready() -> void:
	_enemy = get_node(owner_path)
	z_index = 1
	if _enemy != null and _enemy.enemy_type == &"swarm":
		for path: String in [
			"res://assets/images/slime_1.png",
			"res://assets/images/slime_2.png",
		]:
			if ResourceLoader.exists(path):
				_swarm_frames.append(load(path) as Texture2D)

func _process(_delta: float) -> void:
	if _enemy != null and is_instance_valid(_enemy) and _enemy.enemy_type == &"swarm":
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_trail_t >= TRAIL_INTERVAL:
			_trail.append({"pos": _enemy.global_position, "t": now})
			_last_trail_t = now
			if _trail.size() > TRAIL_POINTS:
				_trail.pop_front()
	queue_redraw()

func _draw() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if _enemy.enemy_type == &"swarm":
		_draw_slime_trail()
	var frames: Array[Texture2D] = _frames_for(_enemy.enemy_type)
	if frames.is_empty():
		draw_circle(Vector2.ZERO, _enemy.radius, _enemy.color_hint)
	else:
		_draw_animated_sprite(frames, _frame_duration_for(_enemy.enemy_type))
	if _enemy.hp < _enemy.max_hp:
		var w: float = _enemy.radius * 2.4
		var h := 4.0
		var top := Vector2(-w * 0.5, -_enemy.radius - 10)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(_enemy.hp / max(_enemy.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.95, 0.3, 0.3))
	if _enemy.boss_aoe and _enemy.boss_aoe_state == 1:
		draw_arc(_enemy.boss_aoe_pos - _enemy.global_position, _enemy.boss_aoe_radius, 0, TAU, 48, Color(1, 0.2, 0.2, 0.7), 3.0)

func _draw_slime_trail() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _trail:
		var age: float = now - float(entry["t"])
		var frac: float = clampf(1.0 - age / TRAIL_LIFETIME, 0.0, 1.0)
		var alpha: float = frac * 0.45
		var r: float = _enemy.radius * (0.55 + (1.0 - frac) * 0.35)
		var local_pos: Vector2 = to_local(entry["pos"])
		# Flatten into a puddle shape (wider than tall).
		draw_set_transform(local_pos, 0.0, Vector2(1.5, 0.65))
		draw_circle(Vector2.ZERO, r, Color(SLIME_TRAIL_COLOR, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _frames_for(t: StringName) -> Array[Texture2D]:
	match t:
		&"rusher":
			return RUSHER_FRAMES
		&"swarm":
			return _swarm_frames
		_:
			return []

func _frame_duration_for(t: StringName) -> float:
	if t == &"swarm":
		return SWARM_FRAME_DURATION
	return RUSHER_FRAME_DURATION

func _draw_animated_sprite(frames: Array[Texture2D], frame_dur: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var idx: int = int(t / frame_dur) % frames.size()
	var tex: Texture2D = frames[idx]
	var s: float = _enemy.radius * SPRITE_SIZE_MULT
	var rot: float = _enemy.facing_dir.angle() + PI * 0.5
	var tint := Color(1, 1, 1, 1)
	if not _enemy.alive:
		tint = Color(1, 1, 1, 0.45)
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
