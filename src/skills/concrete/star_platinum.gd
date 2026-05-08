extends Node2D

# Star Platinum — стенд Джотаро. Спавнится один раз вместе с игроком и
# живёт всю партию. Ходит сам — никакого ввода. Каждые 0.1с выбрасывает
# кулак (визуал fist.png в случайной точке вокруг рук) и наносит урон
# ближайшему к Джотаро врагу. Если врагов рядом нет — просто висит рядом
# с владельцем.
#
# Host-authoritative: позиция и hp реплицируются, кулаки бродкастятся
# RPC'ом с unreliable-доставкой (это чисто визуал).

const FOLLOW_OFFSET := Vector2(36.0, -8.0)   # idle-позиция относительно Джотаро
const FOLLOW_LERP := 12.0                    # сглаживание перемещения
const ENGAGE_RANGE := 600.0                  # на каком радиусе от Джотаро ищем цель
const PUNCH_RANGE := 110.0                   # на каком расстоянии от стенда уже бьём
const PUNCH_INTERVAL := 0.1                  # такт ORA-ORA-ORA
const PUNCH_DAMAGE := 7.0                    # базовый урон на кулак (стакается с dmg_mult)
const FIST_LIFETIME := 0.16                  # сколько живёт спрайт кулака
const FIST_LIMIT := 24                       # потолок одновременных кулаков (защита от переполнения)

const SP_SPRITE := preload("res://assets/images/starplatinum.png")
const FIST_SPRITE := preload("res://assets/images/fist.png")

@export var owner_peer_id: int = 0

var owner_player: Node = null
var _next_punch_at: float = 0.0
var _fists: Array = []  # [{pos: Vector2 (local), t: float, rot: float, scale: float, flip: bool}]

func _ready() -> void:
	add_to_group("minions")
	z_index = 2
	if GameState.is_authority():
		_resolve_owner_player()

func _resolve_owner_player() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == owner_peer_id:
			owner_player = p
			return

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return

	if owner_player == null or not is_instance_valid(owner_player):
		_resolve_owner_player()
		if owner_player == null:
			return

	# Если игрок лёг — стоим рядом и не лупим.
	if not bool(owner_player.alive):
		var idle_pos: Vector2 = owner_player.global_position + FOLLOW_OFFSET
		global_position = global_position.lerp(idle_pos, clampf(FOLLOW_LERP * delta, 0.0, 1.0))
		return

	# Цель — ближайший враг к Джотаро.
	var target: Node2D = Targeting.nearest_enemy(get_tree(), owner_player.global_position, ENGAGE_RANGE)

	var desired_pos: Vector2
	if target != null and is_instance_valid(target):
		# Висим между Джотаро и целью, ближе к цели — чтобы кулаки летели по врагу.
		var to_owner: Vector2 = (owner_player.global_position - target.global_position).normalized()
		desired_pos = target.global_position + to_owner * 28.0
	else:
		desired_pos = owner_player.global_position + FOLLOW_OFFSET

	global_position = global_position.lerp(desired_pos, clampf(FOLLOW_LERP * delta, 0.0, 1.0))

	# Бьём с фиксированным тактом 0.1с.
	var t: float = _now()
	if t < _next_punch_at:
		return
	_next_punch_at = t + PUNCH_INTERVAL
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > PUNCH_RANGE:
		return
	# Урон по цели.
	if target.has_method("apply_damage"):
		var dmg: float = PUNCH_DAMAGE * float(owner_player.dmg_mult())
		target.apply_damage(dmg, "player")
	# Бродкаст FX (включая хост — call_local).
	_broadcast_fist(target.global_position)

func _broadcast_fist(target_world: Vector2) -> void:
	if multiplayer.multiplayer_peer != null:
		_rpc_fist.rpc(target_world)
	else:
		_rpc_fist(target_world)

@rpc("authority", "unreliable", "call_local")
func _rpc_fist(target_world: Vector2) -> void:
	var dir: Vector2 = target_world - global_position
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var dir_n: Vector2 = dir.normalized()
	var perp: Vector2 = Vector2(-dir_n.y, dir_n.x)
	# Точка спавна — где-то вокруг «рук» стенда: чуть впереди + случайный
	# поперечный разлёт. Так создаётся ощущение шквала ударов.
	var fwd: float = randf_range(18.0, 42.0)
	var side: float = randf_range(-22.0, 22.0)
	var pos_local: Vector2 = dir_n * fwd + perp * side
	var rot: float = dir_n.angle() + randf_range(-0.35, 0.35)
	var scale: float = randf_range(0.85, 1.15)
	var flip: bool = randi() % 2 == 0
	_fists.append({"pos": pos_local, "t": _now(), "rot": rot, "scale": scale, "flip": flip})
	if _fists.size() > FIST_LIMIT:
		_fists = _fists.slice(_fists.size() - FIST_LIMIT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Спрайт стенда. Нет наклона — всегда смотрит «вперёд» (вправо), но мы
	# зеркалим по X в зависимости от того, где сейчас цель: чтобы стенд
	# не стоял спиной к врагу.
	var face_right: bool = true
	if owner_player != null and is_instance_valid(owner_player):
		var target: Node2D = Targeting.nearest_enemy(get_tree(), owner_player.global_position, ENGAGE_RANGE)
		if target != null and is_instance_valid(target):
			face_right = target.global_position.x >= global_position.x
	var sp_size: float = 96.0
	var sx: float = sp_size if face_right else -sp_size
	var sp_rect := Rect2(Vector2(-sp_size * 0.5, -sp_size * 0.5), Vector2(sx, sp_size))
	# Лёгкая фиолетово-голубая тонировка — чтобы стенд не путался с игроком.
	draw_texture_rect(SP_SPRITE, sp_rect, false, Color(0.85, 0.85, 1.0, 0.95))

	# Кулаки. Старые автоматически отсеиваем здесь же.
	var t: float = _now()
	var alive: Array = []
	var fist_size: float = 32.0
	for f in _fists:
		var age: float = t - float(f.t)
		if age >= FIST_LIFETIME:
			continue
		alive.append(f)
		var k: float = 1.0 - age / FIST_LIFETIME  # 1 → 0
		var grow: float = 1.0 + (1.0 - k) * 0.5
		var s: float = fist_size * float(f.scale) * grow
		var pos: Vector2 = f.pos
		var rot: float = float(f.rot)
		var flip_x: float = -1.0 if bool(f.flip) else 1.0
		draw_set_transform(pos, rot, Vector2(flip_x * s / fist_size, s / fist_size))
		var rect := Rect2(Vector2(-fist_size * 0.5, -fist_size * 0.5), Vector2(fist_size, fist_size))
		var col := Color(1.0, 1.0, 1.0, 0.55 + 0.45 * k)
		draw_texture_rect(FIST_SPRITE, rect, false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_fists = alive

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
