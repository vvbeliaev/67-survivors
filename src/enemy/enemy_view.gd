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
const SWARM_SPRITE_MULT := SPRITE_SIZE_MULT * 1.2
const COLOSSUS_SPRITE_MULT := SPRITE_SIZE_MULT * 1.4

const SWARM_FRAME_DURATION := 0.28
const SLIME_TRAIL_COLOR   := Color(0.15, 0.72, 0.10)
const TRAIL_POINTS        := 14
const TRAIL_INTERVAL      := 0.05
const TRAIL_LIFETIME      := 0.9
const TRAIL_MIN_STEP      := 2.0   # px — don't add a new point if slime barely moved

const COLOSSUS_AURA_RADIUS := 220.0
const PULSE_DURATION := 0.8
const ICON_SIZE := 11.0
const ICON_SPACING := 13.0

@export var owner_path: NodePath = NodePath("..")

var _enemy: Node = null

# Swarm trail: ring buffer of world positions + capture times.
var _trail: Array[Dictionary] = []
var _last_trail_t: float = -999.0

# Loaded at runtime so the game doesn't crash if slime sprites are missing.
var _swarm_frames: Array[Texture2D] = []
var _colossus_frames: Array[Texture2D] = []
var _icon_textures: Dictionary = {}     # StringName aura kind → Texture2D

# Pulse animation state — replays whenever owner_enemy.pulse_seq changes.
var _last_pulse_seq: int = 0
var _pulse_anim_start_msec: int = 0

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
	if _enemy != null and _enemy.enemy_type == &"colossus":
		var orc_path := "res://assets/images/orc.png"
		if ResourceLoader.exists(orc_path):
			_colossus_frames.append(load(orc_path) as Texture2D)
	# Aura icons — loaded for any enemy because anyone can be buffed.
	for entry: Array in [
		[&"hp", "res://assets/images/aura_health.svg"],
		[&"armor", "res://assets/images/aura_shield.svg"],
		[&"speed", "res://assets/images/aura_sprint.svg"],
	]:
		if ResourceLoader.exists(entry[1]):
			_icon_textures[entry[0]] = load(entry[1]) as Texture2D
	if _enemy != null:
		_last_pulse_seq = _enemy.pulse_seq

func _process(_delta: float) -> void:
	if _enemy != null and is_instance_valid(_enemy) and _enemy.enemy_type == &"swarm":
		var now: float = Time.get_ticks_msec() / 1000.0
		# Drop expired tail points (so trail fades away when slime stops moving).
		while not _trail.is_empty() and now - float(_trail[0]["t"]) > TRAIL_LIFETIME:
			_trail.pop_front()
		if now - _last_trail_t >= TRAIL_INTERVAL:
			var moved_enough := true
			if not _trail.is_empty():
				var last_pos: Vector2 = _trail[_trail.size() - 1]["pos"]
				moved_enough = _enemy.global_position.distance_to(last_pos) >= TRAIL_MIN_STEP
			if moved_enough:
				_trail.append({"pos": _enemy.global_position, "t": now})
				_last_trail_t = now
				if _trail.size() > TRAIL_POINTS:
					_trail.pop_front()
	if _enemy != null and is_instance_valid(_enemy) and _enemy.pulse_seq != _last_pulse_seq:
		_last_pulse_seq = _enemy.pulse_seq
		_pulse_anim_start_msec = Time.get_ticks_msec()
	queue_redraw()

func _draw() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if _enemy.enemy_type == &"swarm":
		_draw_slime_trail()
	if _enemy.aura_kind != &"":
		_draw_aura_field(_enemy.aura_kind)
	var frames: Array[Texture2D] = _frames_for(_enemy.enemy_type)
	if frames.is_empty():
		draw_circle(Vector2.ZERO, _enemy.radius, _enemy.color_hint)
	else:
		_draw_animated_sprite(frames, _frame_duration_for(_enemy.enemy_type), _sprite_mult_for(_enemy.enemy_type), _sprite_rot_offset_for(_enemy.enemy_type))
	if _enemy.hp < _enemy.max_hp:
		var w: float = _enemy.radius * 2.4
		var h := 4.0
		var top := Vector2(-w * 0.5, -_enemy.radius - 10)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(_enemy.hp / max(_enemy.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.95, 0.3, 0.3))
	_draw_aura_buff_icons()
	if _enemy.boss_aoe and _enemy.boss_aoe_state == 1:
		draw_arc(_enemy.boss_aoe_pos - _enemy.global_position, _enemy.boss_aoe_radius, 0, TAU, 48, Color(1, 0.2, 0.2, 0.7), 3.0)

func _draw_aura_field(kind: StringName) -> void:
	# Constant translucent disk + outline so the radius is legible.
	var col: Color = _aura_color(kind)
	var fill := Color(col.r, col.g, col.b, 0.10)
	var ring := Color(col.r, col.g, col.b, 0.55)
	draw_circle(Vector2.ZERO, COLOSSUS_AURA_RADIUS, fill)
	draw_arc(Vector2.ZERO, COLOSSUS_AURA_RADIUS, 0, TAU, 96, ring, 1.5)
	# Expanding pulse animation — replayed each time pulse_seq increments.
	var t: float = float(Time.get_ticks_msec() - _pulse_anim_start_msec) / 1000.0
	if t >= 0.0 and t < PULSE_DURATION:
		var f: float = t / PULSE_DURATION
		var r: float = f * COLOSSUS_AURA_RADIUS
		var a: float = (1.0 - f) * 0.7
		var pulse_col := Color(col.r, col.g, col.b, a)
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, pulse_col, 4.0)

func _draw_aura_buff_icons() -> void:
	# Lay every active aura buff out in a horizontal row above the HP bar.
	# Order is fixed (armor / speed / hp) so the icons don't reshuffle when
	# a buff expires and re-applies.
	var now: int = Time.get_ticks_msec()
	var active: Array[StringName] = []
	if now < _enemy.aura_armor_until_msec:
		active.append(&"armor")
	if now < _enemy.aura_speed_until_msec:
		active.append(&"speed")
	if now < _enemy.aura_hp_until_msec:
		active.append(&"hp")
	if active.is_empty():
		return
	var n: int = active.size()
	var row_w: float = (n - 1) * ICON_SPACING
	var y: float = -_enemy.radius - 16.0
	var x0: float = -row_w * 0.5
	for i in range(n):
		var kind: StringName = active[i]
		var center := Vector2(x0 + i * ICON_SPACING, y)
		var col: Color = _aura_color(kind)
		var tex: Texture2D = _icon_textures.get(kind)
		if tex == null:
			draw_circle(center, ICON_SIZE * 0.5, col)
			continue
		draw_circle(center, ICON_SIZE * 0.65, Color(col.r, col.g, col.b, 0.35))
		var rect := Rect2(center - Vector2(ICON_SIZE, ICON_SIZE) * 0.5, Vector2(ICON_SIZE, ICON_SIZE))
		draw_texture_rect(tex, rect, false, col)

func _aura_color(kind: StringName) -> Color:
	match kind:
		&"hp":
			return Color(0.95, 0.30, 0.30)
		&"armor":
			return Color(1.0, 0.85, 0.25)
		&"speed":
			return Color(0.35, 0.65, 1.0)
		_:
			return Color(1, 1, 1)

func _draw_slime_trail() -> void:
	# Tapered ribbon from oldest → newest position. Width grows toward the
	# slime; alpha fades toward the tail. Drawn as N-1 per-segment quads:
	# a single closed ribbon polygon would self-intersect on tight curves
	# and collapse at the tail (w=0 → duplicate vertex), breaking
	# Geometry2D ear-clip triangulation.
	var n: int = _trail.size()
	if n < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for entry: Dictionary in _trail:
		pts.append(to_local(entry["pos"]))
	var max_width: float = _enemy.radius * 1.1
	var left: PackedVector2Array = PackedVector2Array()
	var right: PackedVector2Array = PackedVector2Array()
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[n - 1] - pts[n - 2]
		else:
			dir = pts[i + 1] - pts[i - 1]
		if dir.length() < 0.01:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var t_along: float = float(i) / float(n - 1)
		var w: float = t_along * max_width
		left.append(pts[i] + perp * w)
		right.append(pts[i] - perp * w)
	for i in range(n - 1):
		var t_a: float = float(i) / float(n - 1)
		var t_b: float = float(i + 1) / float(n - 1)
		var ca := Color(SLIME_TRAIL_COLOR, t_a * 0.55)
		var cb := Color(SLIME_TRAIL_COLOR, t_b * 0.55)
		var quad := PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]])
		var qcols := PackedColorArray([ca, cb, cb, ca])
		draw_polygon(quad, qcols)

func _frames_for(t: StringName) -> Array[Texture2D]:
	match t:
		&"rusher":
			return RUSHER_FRAMES
		&"swarm":
			return _swarm_frames
		&"colossus":
			return _colossus_frames
		_:
			return []

func _frame_duration_for(t: StringName) -> float:
	if t == &"swarm":
		return SWARM_FRAME_DURATION
	return RUSHER_FRAME_DURATION

func _sprite_mult_for(t: StringName) -> float:
	if t == &"swarm":
		return SWARM_SPRITE_MULT
	if t == &"colossus":
		return COLOSSUS_SPRITE_MULT
	return SPRITE_SIZE_MULT

# Per-type rotation offset added to facing_dir.angle(). Default formula
# (`+PI/2`) assumes the sprite faces UP in its source image — true for the
# spider/slime art. Orc art faces DOWN, so it needs the opposite offset
# (-PI/2) to keep its head pointing along the velocity vector.
func _sprite_rot_offset_for(t: StringName) -> float:
	if t == &"colossus":
		return -PI * 0.5
	return PI * 0.5

func _draw_animated_sprite(frames: Array[Texture2D], frame_dur: float, size_mult: float, rot_offset: float = PI * 0.5) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var idx: int = int(t / frame_dur) % frames.size()
	var tex: Texture2D = frames[idx]
	var s: float = _enemy.radius * size_mult
	var rot: float = _enemy.facing_dir.angle() + rot_offset
	var tint := Color(1, 1, 1, 1)
	if not _enemy.alive:
		tint = Color(1, 1, 1, 0.45)
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
