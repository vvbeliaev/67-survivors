extends Node2D

# Presentation: top-down class sprite, combat VFX (synced via Player.play_visual_fx),
# aim pip fallback, HP/MP/down/charge overlays.

const SPRITE_SIZE_MULT := 4.5

const CLASS_SPRITE_PATHS: Dictionary = {
	&"berserker": "res://assets/images/berserker_top.png",
	&"mage": "res://assets/images/wizard_top.png",
	&"bard": "res://assets/images/bard_top.png",
	&"crossbow": "res://assets/images/crossbowman_top.png",
}

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
		var flash: float = 0.0
		if iframe_active:
			flash = 0.5 + 0.5 * sin(now_t * 32.0)
		_flash_mat.set_shader_parameter("flash", flash)
	queue_redraw()

func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var col: Color = _player.color_hint
	if not _player.alive:
		col = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.6)
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

	if _player.charge_started_at >= 0.0:
		var ct: float = clampf((Time.get_ticks_msec() / 1000.0) - _player.charge_started_at, 0.0, 1.5) / 1.5
		var top3 := Vector2(-w * 0.5, _player.radius + 4)
		draw_rect(Rect2(top3, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(top3, Vector2(w * ct, h)), Color(1.0, 0.85, 0.3))

func _draw_berserker_fx() -> void:
	var ta: float = _player.fx_age("auto")
	if ta >= 0.0 and ta < 0.25:
		var k: float = 1.0 - ta / 0.25
		var r: float = float(_player.fx_get("auto", "r", 1.0))
		var spin: float = ta * 18.0
		draw_arc(Vector2.ZERO, r, spin, spin + PI, 32, Color(1, 0.95, 0.6, 0.45 * k), 6.0)
		draw_arc(Vector2.ZERO, r, spin + PI, spin + TAU, 32, Color(1, 0.7, 0.3, 0.35 * k), 4.0)
	var td: float = _player.fx_age("dash")
	if td >= 0.0 and td < 0.4:
		var k2: float = 1.0 - td / 0.4
		var start_pos: Vector2 = _player.fx_get("dash", "start", _player.global_position)
		var local_start: Vector2 = start_pos - _player.global_position
		draw_line(Vector2.ZERO, local_start, Color(1, 0.25, 0.25, 0.55 * k2), 10.0)
		var burst_r: float = float(_player.fx_get("dash", "r", 1.0))
		draw_arc(Vector2.ZERO, burst_r * (0.6 + 0.4 * (1.0 - k2)), 0, TAU, 32, Color(1, 0.5, 0.3, 0.5 * k2), 3.0)
	var tr: float = _player.fx_age("roar")
	if tr >= 0.0 and tr < 0.6:
		var k3: float = 1.0 - tr / 0.6
		var rmax: float = float(_player.fx_get("roar", "r", 1.0))
		var rcur := rmax * clampf(tr / 0.55, 0.0, 1.0)
		draw_arc(Vector2.ZERO, rcur, 0, TAU, 64, Color(1, 0.35, 0.35, 0.55 * k3), 4.0)
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
