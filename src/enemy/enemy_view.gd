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
# Dasher reuses the spider frames but draws a touch larger so the size step
# (and the blue tint) reads at a glance.
const DASHER_SPRITE_MULT := SPRITE_SIZE_MULT * 1.15

const SWARM_FRAME_DURATION := 0.28
const SHOCKWAVE_DURATION := 0.45
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
var _orc_boss_frames: Array[Texture2D] = []
var _icon_textures: Dictionary = {}     # StringName aura kind → Texture2D

# Black-cage ring matches ArenaBoundary's visual treatment so players read it
# as "the same kind of leash, just smaller". Rendered in enemy-view local
# coords by offsetting cage_center against the enemy's world position.
const CAGE_BORDER_THICKNESS := 18.0
const CAGE_BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const CAGE_ARC_SEGMENTS := 96
# Цвет windup-телеграфа: тёмно-фиолетовый (магия орка-шамана) + полу-прозрачная
# заливка, опасность которой нарастает по мере приближения каста.
const CAGE_WINDUP_FILL := Color(0.45, 0.10, 0.55, 0.35)
const CAGE_WINDUP_RING := Color(0.65, 0.18, 0.78, 0.85)
# Подсветка вокруг самого орка во время каста: магическая «пентаграмма» под
# ногами, видимая в любой клиент. Тайминг привязан к cage_state_started_msec.
const ORC_CAST_HALO_COLOR := Color(0.65, 0.18, 0.78, 0.65)
const ORC_CAST_HALO_RADIUS_MULT := 1.6
# Длительности должны совпадать с оrc_boss_ai (нет разделяемой константы между
# нодами и AI-модулем — реплицировать enum-длительности было бы overkill).
const ORC_CAST_WINDUP_DURATION := 1.5
const ORC_CAST_CAGE_DURATION := 5.0
# Дарк-modulate для орка: оригинальный спрайт колосса слишком светлый, чтобы
# читаться как «тёмная и маленькая» версия. Просто сжимаем RGB к 40%, alpha
# не трогаем — силуэт остаётся целым.
const ORC_BOSS_TINT := Color(0.4, 0.4, 0.4, 1.0)

# Default-art enemies all reuse the spider sprite, recolored via a per-type
# luminance ramp. Source PNG is warm-toned (avg R≈0.35, G≈0.20, B≈0.09) and
# multiply-modulate can't pull it into other hues because the original blue
# channel is near-zero — so we bake a recolored copy once per type and reuse
# it for every instance. Cost: ~one image walk × 3 frames × types-in-play.
#
# To add a new tinted spider variant: add an entry here with the per-channel
# ramp factor — values >1 emphasize that channel, <1 dampen it. Outline /
# shadow pixels stay dark either way (lum≈0 → output≈0), preserving silhouette.
const TINT_RAMP_BY_TYPE: Dictionary = {
	&"dasher": Vector3(0.30, 0.55, 1.55),  # cool blue
	&"ranged": Vector3(0.30, 1.55, 0.55),  # acid green
	&"tank":   Vector3(1.10, 0.45, 1.40),  # bruise purple
	&"boss":   Vector3(1.55, 0.35, 1.30),  # magenta
	&"dummy":  Vector3(1.55, 1.30, 0.45),  # warm gold (training dummy)
}
static var _tinted_spider_cache: Dictionary = {}  # StringName → Array[Texture2D]

# Pulse animation state — replays whenever owner_enemy.pulse_seq changes.
var _last_pulse_seq: int = 0
var _pulse_anim_start_msec: int = 0

# Boss shockwave animation — kicks off when boss_aoe_state transitions into 2.
var _last_boss_aoe_state: int = 0
var _shockwave_start_msec: int = 0

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
	if _enemy != null and _enemy.enemy_type == &"orc_boss":
		var orc_path := "res://assets/images/orc.png"
		if ResourceLoader.exists(orc_path):
			_orc_boss_frames.append(load(orc_path) as Texture2D)
	if _enemy != null and TINT_RAMP_BY_TYPE.has(_enemy.enemy_type):
		_bake_tinted_spider_frames(_enemy.enemy_type, TINT_RAMP_BY_TYPE[_enemy.enemy_type])
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
	if _enemy != null and is_instance_valid(_enemy) and _enemy.boss_aoe_state != _last_boss_aoe_state:
		if _enemy.boss_aoe_state == 2:
			_shockwave_start_msec = Time.get_ticks_msec()
		_last_boss_aoe_state = _enemy.boss_aoe_state
	queue_redraw()

func _draw() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if _enemy.enemy_type == &"swarm":
		_draw_slime_trail()
	if _enemy.aura_kind != &"":
		_draw_aura_field(_enemy.aura_kind)
	if _enemy.cage_radius > 0.0:
		match _enemy.cage_state:
			1:
				_draw_cage_windup()
				_draw_orc_cast_halo()
			2:
				_draw_cage()
	if _enemy.enemy_type == &"dasher":
		_draw_dash_indicator()
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
	if _enemy.boss_aoe and _enemy.boss_aoe_state == 2:
		_draw_shockwave()

func _draw_shockwave() -> void:
	# Expanding ring — sweeps from 30% to 110% of the AoE radius over
	# SHOCKWAVE_DURATION while the trailing wash fills the impact zone.
	var t: float = float(Time.get_ticks_msec() - _shockwave_start_msec) / 1000.0
	if t < 0.0 or t > SHOCKWAVE_DURATION:
		return
	var f: float = clampf(t / SHOCKWAVE_DURATION, 0.0, 1.0)
	var center: Vector2 = _enemy.boss_aoe_pos - _enemy.global_position
	var max_r: float = _enemy.boss_aoe_radius
	var ring_r: float = lerpf(max_r * 0.3, max_r * 1.1, f)
	var alpha_ring: float = (1.0 - f) * 0.95
	var alpha_fill: float = (1.0 - f) * 0.45
	var inner_r: float = max(ring_r - 18.0, 0.0)
	# Bright impact wash — radial fade approximated by stacking two filled
	# disks (light core + outer translucent) since draw_circle has no gradient.
	draw_circle(center, ring_r, Color(1.0, 0.55, 0.25, alpha_fill * 0.55))
	draw_circle(center, inner_r, Color(1.0, 0.85, 0.45, alpha_fill * 0.35))
	# Two concentric rings give the wave a clear leading edge.
	draw_arc(center, ring_r, 0, TAU, 64, Color(1.0, 0.95, 0.7, alpha_ring), 6.0)
	draw_arc(center, ring_r * 0.78, 0, TAU, 48, Color(1.0, 0.4, 0.15, alpha_ring * 0.7), 3.0)

func _draw_cage() -> void:
	# Чёрный круг в мире (визуально матчится с ArenaBoundary), посчитанный
	# в локалках вью: enemy движется, клетка остаётся приколочена к точке
	# каста.
	var center: Vector2 = _enemy.cage_center - _enemy.global_position
	draw_arc(center, _enemy.cage_radius, 0.0, TAU, CAGE_ARC_SEGMENTS, CAGE_BORDER_COLOR, CAGE_BORDER_THICKNESS, true)

func _draw_cage_windup() -> void:
	# Телеграф: фиолетовая полупрозрачная зона на месте будущей клетки.
	# Прогресс каста (0→1) усиливает заполнение, пульсирующий ринг — на 4 Гц.
	var center: Vector2 = _enemy.cage_center - _enemy.global_position
	var elapsed_ms: int = Time.get_ticks_msec() - _enemy.cage_state_started_msec
	var progress: float = clampf(float(elapsed_ms) / 1000.0 / ORC_CAST_WINDUP_DURATION, 0.0, 1.0)
	var fill := CAGE_WINDUP_FILL
	fill.a = CAGE_WINDUP_FILL.a * (0.4 + 0.6 * progress)
	draw_circle(center, _enemy.cage_radius, fill)
	# Внешний ринг — пульсирует, чтобы привлечь внимание; на финале каста
	# ширина и яркость растут.
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 4.0)
	var ring := CAGE_WINDUP_RING
	ring.a = CAGE_WINDUP_RING.a * (0.5 + 0.5 * progress)
	var thickness: float = 4.0 + 4.0 * pulse + 6.0 * progress
	draw_arc(center, _enemy.cage_radius, 0.0, TAU, CAGE_ARC_SEGMENTS, ring, thickness, true)

func _draw_orc_cast_halo() -> void:
	# Магический круг под самим орком — индикатор «он сейчас кастует». Растёт
	# по радиусу к концу windup и одновременно усиливает альфу: сначала тонкая
	# дуга, к моменту каста — полноценный круг с двойным контуром.
	var elapsed_ms: int = Time.get_ticks_msec() - _enemy.cage_state_started_msec
	var progress: float = clampf(float(elapsed_ms) / 1000.0 / ORC_CAST_WINDUP_DURATION, 0.0, 1.0)
	var r: float = _enemy.radius * lerpf(1.0, ORC_CAST_HALO_RADIUS_MULT, progress)
	var col := ORC_CAST_HALO_COLOR
	col.a = ORC_CAST_HALO_COLOR.a * (0.3 + 0.7 * progress)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, 2.5 + 2.0 * progress, true)
	# Внутренний слабый круг — даёт ощущение «вторая руна вращается».
	var col_inner := col
	col_inner.a *= 0.55
	draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 48, col_inner, 1.5, true)

func _draw_dash_indicator() -> void:
	if _enemy.dash_state != 1 and _enemy.dash_state != 2:
		return
	var origin: Vector2 = Vector2.ZERO  # local space — Player View is centered on enemy
	var endpoint: Vector2 = _enemy.dash_target_pos - _enemy.global_position
	var diff: Vector2 = endpoint - origin
	var len_sq: float = diff.length_squared()
	if len_sq < 0.0001:
		return
	var dir: Vector2 = diff.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var half_w: float = _enemy.radius * 1.12  # was 1.4; -20% per request
	# Brighter alpha during the locked window so players read the commit.
	var alpha: float = 0.15 if _enemy.dash_state == 1 else 0.26
	var fill := Color(1.0, 0.18, 0.18, alpha)
	var edge := Color(1.0, 0.25, 0.25, alpha + 0.15)
	var quad := PackedVector2Array([
		origin + perp * half_w,
		endpoint + perp * half_w,
		endpoint - perp * half_w,
		origin - perp * half_w,
	])
	draw_polygon(quad, PackedColorArray([fill, fill, fill, fill]))
	draw_line(origin + perp * half_w, endpoint + perp * half_w, edge, 1.5)
	draw_line(origin - perp * half_w, endpoint - perp * half_w, edge, 1.5)

func _draw_aura_field(kind: StringName) -> void:
	# Constant translucent disk + outline so the radius is legible.
	var col: Color = _aura_color(kind)
	var fill := Color(col.r, col.g, col.b, 0.05)
	var ring := Color(col.r, col.g, col.b, 0.275)
	draw_circle(Vector2.ZERO, COLOSSUS_AURA_RADIUS, fill)
	draw_arc(Vector2.ZERO, COLOSSUS_AURA_RADIUS, 0, TAU, 96, ring, 1.5)
	# Expanding pulse animation — replayed each time pulse_seq increments.
	var t: float = float(Time.get_ticks_msec() - _pulse_anim_start_msec) / 1000.0
	if t >= 0.0 and t < PULSE_DURATION:
		var f: float = t / PULSE_DURATION
		var r: float = f * COLOSSUS_AURA_RADIUS
		var a: float = (1.0 - f) * 0.35
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
	# Tinted spiders win over the raw rusher art when a ramp is registered.
	if TINT_RAMP_BY_TYPE.has(t):
		var cached = _tinted_spider_cache.get(t)
		if cached != null and not (cached as Array).is_empty():
			return cached
		return RUSHER_FRAMES
	match t:
		&"rusher":
			return RUSHER_FRAMES
		&"swarm":
			return _swarm_frames
		&"colossus":
			return _colossus_frames
		&"orc_boss":
			return _orc_boss_frames
		_:
			return []

# Bake a recolored spider palette for `t` by mapping per-pixel luminance onto
# a cool / warm / acid ramp. Outline / shadow pixels stay dark (lum≈0), so
# silhouette is preserved. Idempotent — first caller for a given type pays
# the cost, subsequent instances hit the static cache.
func _bake_tinted_spider_frames(t: StringName, ramp: Vector3) -> void:
	if _tinted_spider_cache.has(t):
		return
	var out: Array[Texture2D] = []
	for src: Texture2D in RUSHER_FRAMES:
		var img: Image = src.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w: int = img.get_width()
		var h: int = img.get_height()
		for y in h:
			for x in w:
				var c: Color = img.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				img.set_pixel(x, y, Color(
					clampf(lum * ramp.x, 0.0, 1.0),
					clampf(lum * ramp.y, 0.0, 1.0),
					clampf(lum * ramp.z, 0.0, 1.0),
					c.a,
				))
		out.append(ImageTexture.create_from_image(img))
	_tinted_spider_cache[t] = out

func _frame_duration_for(t: StringName) -> float:
	if t == &"swarm":
		return SWARM_FRAME_DURATION
	return RUSHER_FRAME_DURATION

func _sprite_mult_for(t: StringName) -> float:
	if t == &"swarm":
		return SWARM_SPRITE_MULT
	if t == &"colossus":
		return COLOSSUS_SPRITE_MULT
	if t == &"dasher":
		return DASHER_SPRITE_MULT
	return SPRITE_SIZE_MULT

# Per-type rotation offset added to facing_dir.angle(). Default formula
# (`+PI/2`) assumes the sprite faces UP in its source image — true for the
# spider/slime art. Orc art faces DOWN, so it needs the opposite offset
# (-PI/2) to keep its head pointing along the velocity vector.
func _sprite_rot_offset_for(t: StringName) -> float:
	if t == &"colossus" or t == &"orc_boss":
		return -PI * 0.5
	return PI * 0.5

func _draw_animated_sprite(frames: Array[Texture2D], frame_dur: float, size_mult: float, rot_offset: float = PI * 0.5) -> void:
	var idx: int
	# Dasher freezes its walk frame whenever it's preparing or executing the
	# dash — only state 0 (walk) and 4 (post-dash) play the animation. The
	# user-facing rule is "preparing the dash → walk animation freezes" so we
	# also freeze during the dash itself, otherwise the spider visibly shimmies
	# during the lunge.
	if _enemy.enemy_type == &"dasher" and _enemy.dash_state != 0 and _enemy.dash_state != 4:
		idx = 0
	else:
		var t: float = Time.get_ticks_msec() / 1000.0
		idx = int(t / frame_dur) % frames.size()
	var tex: Texture2D = frames[idx]
	var s: float = _enemy.radius * size_mult
	var rot: float = _enemy.facing_dir.angle() + rot_offset
	# Dasher uses a baked blue palette (see _bake_dasher_frames), so plain
	# white modulate keeps the recolored pixels intact.
	var tint := Color(1, 1, 1, 1)
	if _enemy.enemy_type == &"orc_boss":
		tint = ORC_BOSS_TINT
	if not _enemy.alive:
		tint.a = 0.45
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
