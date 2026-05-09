extends Node2D

# Presentation: top-down class sprite, combat VFX (synced via Player.play_visual_fx),
# aim pip fallback, HP/MP/down/charge overlays.

const SPRITE_SIZE_MULT := 4.5

const CLASS_SPRITE_PATHS: Dictionary = {
	&"berserker": "res://assets/images/berserker_top.png",
	&"mage": "res://assets/images/wizard_top.png",
	&"bard": "res://assets/images/bard_top.png",
	&"crossbow": "res://assets/images/crossbowman_top.png",
	&"jotaro": "res://assets/images/jotaro_top.png",
}

# Slash-текстура для берсерк-cleave. Геометрия (со слов автора арта):
#   • квадрат 1254×1254;
#   • прямая (627, 627) → (627, 0) — это «рукоятка/клинок»: рука варвара в
#     центре изображения, клинок уходит вверх в -Y;
#   • то, что слева от этой линии — след взмаха.
# При отрисовке центр текстуры крепится к руке (чуть впереди игрока по aim_dir),
# текстура поворачивается так, чтобы её -Y совпадал с aim_dir, а для swing 1
# зеркалится по X — тогда след оказывается с другой стороны и взмах визуально
# идёт справа налево.
const CLEAVE_SLASH_TEX: Texture2D = preload("res://assets/images/splash.png")
const CLEAVE_SLASH_TEX_SIZE: float = 1254.0
const CLEAVE_SLASH_HAND_PX: Vector2 = Vector2(627.0, 627.0)
const CLEAVE_SLASH_HANDLE_LEN_PX: float = 627.0

@export var owner_path: NodePath = NodePath("..")

const FLASH_SHADER := preload("res://src/player/iframe_flash.gdshader")

var _player: Node = null
var _sprite_cache: Dictionary = {}  # StringName -> Texture2D or null sentinel not stored
var _flash_mat: ShaderMaterial = null

func _sprite_texture(klass: StringName) -> Texture2D:
	if _sprite_cache.has(klass):
		return _sprite_cache[klass]
	var path_var: Variant = CLASS_SPRITE_PATHS.get(klass, "")
	var tex: Texture2D = null
	if path_var is String and not String(path_var).is_empty():
		tex = ResourceLoader.load(String(path_var)) as Texture2D
	_sprite_cache[klass] = tex
	return tex

func _ready() -> void:
	_player = get_node(owner_path)
	z_index = 1
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = FLASH_SHADER
	_flash_mat.set_shader_parameter("flash", 0.0)
	material = _flash_mat

func _process(_delta: float) -> void:
	if _flash_mat != null and _player != null:
		var now_t: float = Time.get_ticks_msec() / 1000.0
		var iframe_active: bool = _player.alive and now_t < float(_player.iframes_until)
		var recovery_active: bool = _player.alive and now_t < float(_player.hit_recovery_until)
		var flash: float = 0.0
		if iframe_active:
			flash = 0.5 + 0.5 * sin(now_t * 32.0)
		elif recovery_active:
			flash = 0.25 + 0.25 * sin(now_t * 32.0)
		_flash_mat.set_shader_parameter("flash", flash)
	queue_redraw()

func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var col: Color = _player.color_hint
	if not _player.alive:
		col = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.6)

	# Эффекты «за спиной игрока» — рисуем ДО спрайта героя, чтобы они
	# перекрывались силуэтом, а не перекрывали его.
	if String(_player.klass) == "berserker":
		_draw_berserker_slash_behind()

	var tex: Texture2D = _sprite_texture(_player.klass)
	if tex != null:
		var tint := Color(1, 1, 1, 0.55) if not _player.alive else Color(1, 1, 1, 1)
		var s: float = _player.radius * SPRITE_SIZE_MULT
		draw_set_transform(Vector2.ZERO, _player.aim_dir.angle(), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, _player.radius, col)
		draw_line(Vector2.ZERO, _player.aim_dir * (_player.radius + 6), Color(1, 1, 1, 0.7), 2.0)

	match String(_player.klass):
		"berserker":
			_draw_berserker_fx()
			if GameState.debug_mode and GameState.debug_show_berserker_cone:
				_draw_berserker_debug_cone()
		"mage":
			_draw_mage_fx()
		"bard":
			_draw_bard_fx()
		"crossbow":
			_draw_crossbow_fx()

	var w := 40.0
	var h := 4.0
	var top := Vector2(-w * 0.5, -_player.radius - 14)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
	var ratio: float = clampf(_player.hp / max(_player.max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.3, 0.95, 0.3))

	if _player.max_mp > 0.0:
		var top2 := Vector2(-w * 0.5, -_player.radius - 8)
		draw_rect(Rect2(top2, Vector2(w, h)), Color(0.1, 0.1, 0.15))
		var r2: float = clampf(_player.mp / _player.max_mp, 0.0, 1.0)
		draw_rect(Rect2(top2, Vector2(w * r2, h)), Color(0.3, 0.5, 0.95))

	if not _player.alive:
		draw_arc(Vector2.ZERO, _player.radius + 6, 0, TAU, 32, Color(1, 0.4, 0.4, 0.6), 2.0)

	# Желтой charge-полоски под игроком больше нет — у арбалетчика прогресс
	# зарядки показывается через mp-бар над игроком (он же «концентрация»;
	# crossbow.on_pre_move ставит mp = max_mp × charge_progress).

func _draw_berserker_slash_behind() -> void:
	# Slash-текстура для cleave-автоатаки. Рисуется ДО спрайта героя, чтобы
	# выходить из-за плеча, а не накрывать персонажа. Центр изображения = рука
	# варвара; в текстуре рукоятка идёт от (627, 627) — рука — вверх к (627, 0)
	# в направлении -Y. Базовый поворот aim_angle + PI/2 совмещает -Y с aim_dir.
	# За 0.25с FX клинок «прометает» дугу вокруг руки:
	#   • swing 0: угол от -arc/2 к +arc/2 (слева направо относительно aim);
	#   • swing 1: угол от +arc/2 к -arc/2 + зеркало по X — след оказывается
	#     с другой стороны, мах справа налево.
	# Размах визуального свинга масштабируется от ширины конуса (`arc`),
	# чтобы апгрейд "+градусы к атаке" читался не только через попадания.
	var ta: float = _player.fx_age("auto")
	if ta < 0.0 or ta >= 0.25:
		return
	var k: float = 1.0 - ta / 0.25
	var r: float = float(_player.fx_get("auto", "r", 1.0))
	var aim_v: Vector2 = _player.aim_dir
	if aim_v.length_squared() < 0.0001:
		aim_v = Vector2.RIGHT
	var aim_angle: float = atan2(aim_v.y, aim_v.x)
	var swing: int = int(_player.fx_get("auto", "swing", 0))
	var arc_deg: float = float(_player.fx_get("auto", "arc", 90.0))
	var t: float = clampf(ta / 0.25, 0.0, 1.0)

	var sweep_rad: float = deg_to_rad(70.0 * (arc_deg / 90.0))
	var sweep_off: float
	if swing == 0:
		sweep_off = lerp(-sweep_rad * 0.5, sweep_rad * 0.5, t)
	else:
		sweep_off = lerp(sweep_rad * 0.5, -sweep_rad * 0.5, t)

	var px_to_world: float = r / CLEAVE_SLASH_HANDLE_LEN_PX
	var draw_size: float = CLEAVE_SLASH_TEX_SIZE * px_to_world
	var hand: Vector2 = aim_v * (_player.radius * 0.5)
	var rot: float = aim_angle + PI / 2.0 + sweep_off
	var scale_x: float = 1.0 if swing == 0 else -1.0
	var color: Color = Color(1.0, 0.92, 0.55, 0.95 * k)

	var dest_rect := Rect2(-CLEAVE_SLASH_HAND_PX * px_to_world, Vector2(draw_size, draw_size))
	draw_set_transform(hand, rot, Vector2(scale_x, 1.0))
	draw_texture_rect(CLEAVE_SLASH_TEX, dest_rect, false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_berserker_fx() -> void:
	# Cleave (cone) рисуется отдельно за героем в _draw_berserker_slash_behind.
	# Здесь — только остальные FX (dash, roar, quake).
	var td: float = _player.fx_age("dash")
	if td >= 0.0 and td < 0.4:
		var k2: float = 1.0 - td / 0.4
		var start_pos: Vector2 = _player.fx_get("dash", "start", _player.global_position)
		var local_start: Vector2 = start_pos - _player.global_position
		draw_line(Vector2.ZERO, local_start, Color(1, 0.25, 0.25, 0.55 * k2), 10.0)
		var burst_r: float = float(_player.fx_get("dash", "r", 1.0))
		draw_arc(Vector2.ZERO, burst_r * (0.6 + 0.4 * (1.0 - k2)), 0, TAU, 32, Color(1, 0.5, 0.3, 0.5 * k2), 3.0)
	var trt: float = _player.fx_age("retaliate")
	if trt >= 0.0 and trt < 0.35:
		var k_ret: float = 1.0 - trt / 0.35
		var rmax_ret: float = float(_player.fx_get("retaliate", "r", 1.0))
		var rcur_ret: float = rmax_ret * clampf(trt / 0.32, 0.0, 1.0)
		draw_arc(Vector2.ZERO, rcur_ret, 0, TAU, 56, Color(1.0, 0.25, 0.25, 0.7 * k_ret), 4.0)
		draw_arc(Vector2.ZERO, rcur_ret * 0.7, 0, TAU, 48, Color(1.0, 0.55, 0.35, 0.45 * k_ret), 2.0)
	var tq: float = _player.fx_age("quake")
	if tq >= 0.0 and tq < 0.55:
		var k4: float = 1.0 - tq / 0.55
		var qmax: float = float(_player.fx_get("quake", "r", 1.0))
		var qr := qmax * clampf(tq / 0.5, 0.0, 1.0)
		draw_arc(Vector2.ZERO, qr, 0, TAU, 56, Color(0.85, 0.55, 0.25, 0.6 * k4), 6.0)
		for i in 6:
			var ang: float = i * (TAU / 6.0)
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(dir * (qr * 0.2), dir * (qr * 0.7), Color(0.7, 0.4, 0.2, 0.5 * k4), 3.0)

func _draw_berserker_debug_cone() -> void:
	# Дебаг-овержей актуального hitbox-конуса cleave-автоатаки. Геометрия —
	# ровно та же, что в Skill._cone_damage: hit_r = melee.radius × range_mult × 1.2,
	# half_arc = (melee.arc_deg + STAT_SLASH_ARC) / 2. Параметры читаем из живого
	# скилла, чтобы апгрейды на дальность/арку отражались мгновенно.
	if _player.class_node == null:
		return
	var melee: Object = _player.class_node.auto_skill
	if melee == null:
		return
	var base_r: float = float(melee.get("radius"))
	var base_arc: float = float(melee.get("arc_deg"))
	if base_r <= 0.0:
		return
	var arc_bonus: float = _player.stats.value(StatBlock.STAT_SLASH_ARC)
	var hit_r: float = base_r * _player.range_mult() * 1.2
	var half_arc: float = deg_to_rad(base_arc + arc_bonus) * 0.5
	var aim_v: Vector2 = _player.aim_dir
	if aim_v.length_squared() < 0.0001:
		aim_v = Vector2.RIGHT
	var aim_a: float = atan2(aim_v.y, aim_v.x)
	var steps := 32
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var ang: float = aim_a - half_arc + t * (half_arc * 2.0)
		pts.append(Vector2(cos(ang), sin(ang)) * hit_r)
	draw_colored_polygon(pts, Color(1.0, 0.25, 0.25, 0.16))
	var outline: PackedVector2Array = PackedVector2Array()
	outline.append(Vector2.ZERO)
	for i in range(1, pts.size()):
		outline.append(pts[i])
	outline.append(Vector2.ZERO)
	draw_polyline(outline, Color(1.0, 0.4, 0.4, 0.95), 1.5, true)

func _draw_mage_fx() -> void:
	var ta: float = _player.fx_age("auto")
	if ta >= 0.0 and ta < 0.18:
		var k: float = 1.0 - ta / 0.18
		var hand: Vector2 = _player.aim_dir * (_player.radius + 4)
		draw_circle(hand, 6.0 + 4.0 * (1.0 - k), Color(0.6, 0.8, 1.0, 0.6 * k))
	var tf: float = _player.fx_age("fireball")
	if tf >= 0.0 and tf < 0.45:
		var k2: float = 1.0 - tf / 0.45
		var pos: Vector2 = _player.fx_get("fireball", "pos", _player.global_position)
		var r: float = float(_player.fx_get("fireball", "r", 80.0))
		var local: Vector2 = pos - _player.global_position
		var grow: float = 0.4 + 0.6 * (1.0 - k2)
		draw_circle(local, r * grow * 0.5, Color(1, 0.55, 0.2, 0.45 * k2))
		draw_arc(local, r * grow, 0, TAU, 48, Color(1, 0.75, 0.3, 0.6 * k2), 4.0)
	var tc: float = _player.fx_age("chain")
	if tc >= 0.0 and tc < 0.35:
		var k3: float = 1.0 - tc / 0.35
		var pts: Variant = _player.fx_get("chain", "points", [])
		if pts is Array:
			var prev: Vector2 = Vector2.ZERO
			var i := 0
			for pt in pts:
				var p: Vector2 = pt - _player.global_position
				var dir: Vector2 = (p - prev).normalized()
				var perp := Vector2(-dir.y, dir.x)
				var mid: Vector2 = (prev + p) * 0.5 + perp * 14.0 * sin(tc * 30.0 + i)
				draw_line(prev, mid, Color(0.8, 0.9, 1.0, 0.7 * k3), 3.0)
				draw_line(mid, p, Color(0.8, 0.9, 1.0, 0.7 * k3), 3.0)
				draw_circle(p, 6.0, Color(0.7, 0.85, 1.0, 0.5 * k3))
				prev = p
				i += 1
	var tb: float = _player.fx_age("blink")
	if tb >= 0.0 and tb < 0.4:
		var k4: float = 1.0 - tb / 0.4
		var from_pos: Vector2 = _player.fx_get("blink", "from", _player.global_position)
		var to_pos: Vector2 = _player.fx_get("blink", "to", _player.global_position)
		var lf: Vector2 = from_pos - _player.global_position
		var lt: Vector2 = to_pos - _player.global_position
		draw_circle(lf, 14.0 + 6.0 * (1.0 - k4), Color(0.7, 0.7, 0.95, 0.45 * k4))
		draw_circle(lt, 14.0 * k4 + 6.0, Color(0.85, 0.85, 1.0, 0.55 * k4))

func _draw_bard_fx() -> void:
	var ta: float = _player.fx_age("auto")
	if ta >= 0.0 and ta < 0.2:
		var k: float = 1.0 - ta / 0.2
		var hand: Vector2 = _player.aim_dir * (_player.radius + 3)
		draw_circle(hand, 5.0 * (1.0 + (1.0 - k)), Color(0.6, 1.0, 0.7, 0.55 * k))
	var th: float = _player.fx_age("heal")
	if th >= 0.0 and th < 1.6:
		var r: float = float(_player.fx_get("heal", "r", 180.0))
		for i in 3:
			var t_in: float = th - i * 0.5
			if t_in >= 0.0 and t_in < 0.45:
				var pk: float = 1.0 - t_in / 0.45
				var pr: float = r * clampf(t_in / 0.4, 0.0, 1.0)
				draw_arc(Vector2.ZERO, pr, 0, TAU, 48, Color(0.4, 1.0, 0.5, 0.55 * pk), 4.0)
	var tu: float = _player.fx_age("buff")
	if tu >= 0.0 and tu < 0.6:
		var k2: float = 1.0 - tu / 0.6
		var r2: float = float(_player.fx_get("buff", "r", 180.0))
		var rr: float = r2 * clampf(tu / 0.5, 0.0, 1.0)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 48, Color(1.0, 0.85, 0.4, 0.55 * k2), 5.0)
		draw_arc(Vector2.ZERO, rr * 0.85, 0, TAU, 48, Color(1.0, 0.95, 0.6, 0.4 * k2), 3.0)
	var td: float = _player.fx_age("dash")
	if td >= 0.0 and td < 0.35:
		var k3: float = 1.0 - td / 0.35
		var s: Vector2 = _player.fx_get("dash", "from", _player.global_position) - _player.global_position
		draw_line(Vector2.ZERO, s, Color(0.6, 1.0, 0.7, 0.5 * k3), 6.0)

func _draw_crossbow_fx() -> void:
	var tm: float = _player.fx_age("shot")
	if tm >= 0.0 and tm < 0.18:
		var k: float = 1.0 - tm / 0.18
		var origin: Vector2 = _player.aim_dir * (_player.radius + 6)
		draw_circle(origin, 8.0 + 6.0 * (1.0 - k), Color(1.0, 0.9, 0.4, 0.6 * k))
		var perp := Vector2(-_player.aim_dir.y, _player.aim_dir.x)
		draw_line(origin - perp * 10, origin + perp * 10, Color(1.0, 0.85, 0.3, 0.7 * k), 3.0)
	var tap: float = _player.fx_age("ap")
	if tap >= 0.0 and tap < 0.25:
		var k2: float = 1.0 - tap / 0.25
		var origin2: Vector2 = _player.aim_dir * (_player.radius + 6)
		draw_circle(origin2, 14.0 + 6.0 * (1.0 - k2), Color(1.0, 0.6, 0.2, 0.65 * k2))
	var tr: float = _player.fx_age("roll")
	if tr >= 0.0 and tr < 0.4:
		var k3: float = 1.0 - tr / 0.4
		var from: Vector2 = _player.fx_get("roll", "from", _player.global_position) - _player.global_position
		draw_line(Vector2.ZERO, from, Color(0.9, 0.85, 0.6, 0.45 * k3), 8.0)
		draw_circle(from, 10.0 * k3, Color(0.9, 0.85, 0.6, 0.4 * k3))
