extends Area2D

# Берсерк-чучело (новая ПКМ): неподвижная подделка под варвара. Моб
# воспринимает её как ещё одного «игрока» — берёт того, кто физически
# ближе (см. EnemyAI._pick_target). HP базово 50; STAT_DECOY_HP_BONUS
# добавляет долю от max_hp варвара. Живёт максимум LIFETIME секунд или
# до 0 хп. STAT_RETALIATION владельца срабатывает при попадании по чучелу
# тем же радиусом, что и у обычного отскока (см. Player.RETALIATION_RADIUS).
#
# При наличии апгрейда `epic_berserker_decoy_quake` чучело при уничтожении
# (хп≤0 или таймер) кастует землетрясение в своей точке — стан без урона,
# радиус и длительность берутся из BerserkerQuake владельца со всеми его
# прокачками (range_mult × STAT_STUN_RADIUS, base_stun + STAT_STUN_DURATION).
#
# Спрайт — берсерк коричневого тона; в момент спавна 0.6с играет та же
# красная экспансия, что раньше шла от игрока («рев»), плюс кратковременный
# красный оверлей на спрайте — это та самая «красная версия себя», которая
# при оседании оставляет коричневую болванку.
#
# Реплицируется host→client через MultiplayerSpawner (kind=berserker_decoy
# в Arena._spawn_minion). HP, dying — on_change.

const MAX_HP_DEFAULT := 50.0
const RADIUS := 14.0
# Должна совпадать с Player.RETALIATION_RADIUS (отскок «шипов боли» от чучела
# работает в том же радиусе, что и отскок от игрока).
const RETALIATION_RADIUS := 110.0
const SPRITE_SIZE_MULT := 4.5  # совпадает с player_view.gd
const ROAR_FX_DURATION := 0.6
const RED_OVERLAY_DURATION := 0.6
const RETALIATION_FX_DURATION := 0.35
const LIFETIME_DEFAULT := 5.0
const DEATH_QUAKE_FX_DURATION := 0.55

const SPRITE_TEX := preload("res://assets/images/berserker_top.png")
const DEATH_QUAKE_UPGRADE_ID: StringName = &"epic_berserker_decoy_quake"

# Цвет «болванки» — выгоревший коричневый: пиксель = lerp(red, brown, t).
const BROWN_TINT := Color(0.55, 0.36, 0.22, 1.0)
const RED_OVERLAY := Color(1.0, 0.18, 0.12, 1.0)

@export var owner_peer_id: int = 0
@export var hp: float = MAX_HP_DEFAULT
@export var max_hp: float = MAX_HP_DEFAULT
@export var fx_radius: float = 240.0
# Лайфтайм фиксируется в момент спавна (LIFETIME_DEFAULT + STAT_DECOY_LIFETIME).
# Прокачка после спавна на уже стоящее чучело не влияет.
@export var lifetime: float = LIFETIME_DEFAULT
# Бамп при срабатывании отскока — клиент по изменению запускает локальный FX.
@export var retaliate_seq: int = 0
# Переход в «умирающее» состояние: alive=false, но нода ещё живёт
# DEATH_QUAKE_FX_DURATION для отрисовки эпик-FX. Реплицируется, чтобы клиент
# тоже увидел кольцо. Если квейк не прокачан — нода queue_free мгновенно,
# dying так и остаётся false.
@export var dying: bool = false
@export var death_quake_radius: float = 0.0

var team_tag: String = "player"
var alive: bool = true
var _spawn_at: float = 0.0
var _retaliate_started_at: float = -1.0
var _last_retaliate_seq: int = 0
var _dying_started_at: float = -1.0
var _last_dying: bool = false

func _ready() -> void:
	add_to_group("decoys")
	_spawn_at = _now()
	_last_retaliate_seq = retaliate_seq
	_last_dying = dying
	z_index = 1

func _process(_delta: float) -> void:
	if retaliate_seq != _last_retaliate_seq:
		_last_retaliate_seq = retaliate_seq
		_retaliate_started_at = _now()
	if dying != _last_dying:
		_last_dying = dying
		if dying:
			_dying_started_at = _now()
	# Хост-side: лайфтайм-таймер и cleanup умирающего чучела.
	if GameState.is_authority():
		if alive and (_now() - _spawn_at) >= lifetime:
			_enter_dying()
		elif dying and (_now() - _dying_started_at) >= DEATH_QUAKE_FX_DURATION:
			queue_free()
	queue_redraw()

# ---- Damage path -------------------------------------------------------

func apply_damage(amount: float, src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive or amount <= 0.0:
		return
	hp = max(hp - amount, 0.0)
	_broadcast_damage_number(amount, global_position)
	EventBus.damage_dealt.emit(self, amount, src_team)
	# Шипы боли. Стат лежит на варваре-владельце, не на чучеле.
	var owner_p: Node = _owner_player()
	if owner_p != null and owner_p.alive:
		var ret_pct: float = float(owner_p.stats.value(StatBlock.STAT_RETALIATION))
		if ret_pct > 0.0:
			_emit_retaliation(amount * ret_pct)
	if hp <= 0.0:
		_enter_dying()

func _emit_retaliation(dmg: float) -> void:
	if dmg <= 0.0:
		return
	for e in Targeting.enemies_in_radius(get_tree(), global_position, RETALIATION_RADIUS):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
	retaliate_seq += 1   # бамп → клиенты увидят change → запустят FX

func _enter_dying() -> void:
	if not alive:
		return
	alive = false
	var owner_p: Node = _owner_player()
	# Эпик-апгрейд: землетрясение со всеми прокачками владельца.
	if owner_p != null and _has_death_quake(owner_p):
		var r: float = _trigger_death_quake(owner_p)
		if r > 0.0:
			death_quake_radius = r
			dying = true   # нода живёт ещё DEATH_QUAKE_FX_DURATION для отрисовки
			_dying_started_at = _now()
			return
	# Без эпика — просто исчезаем.
	queue_free()

func _has_death_quake(owner_p: Node) -> bool:
	if not ("_upgrade_stacks" in owner_p):
		return false
	return int(owner_p._upgrade_stacks.get(DEATH_QUAKE_UPGRADE_ID, 0)) > 0

# Землетрясение от чучела. Чистый стан — без урона; параметры тянутся из
# BerserkerQuake владельца, поэтому учитывают все его апгрейды (range,
# stun_radius, stun_duration). Возвращает финальный радиус, чтобы FX
# рисовал правильный размер.
func _trigger_death_quake(owner_p: Node) -> float:
	if owner_p.class_node == null:
		return 0.0
	var quake: Object = owner_p.class_node.primary_skill
	if quake == null:
		return 0.0
	var base_r: float = float(quake.get("radius"))
	var base_stun: float = float(quake.get("stun_duration"))
	if base_r <= 0.0:
		return 0.0
	var stun_radius_mult: float = float(owner_p.stats.value(StatBlock.STAT_STUN_RADIUS))
	var stun_bonus: float = float(owner_p.stats.value(StatBlock.STAT_STUN_DURATION))
	var r: float = base_r * float(owner_p.range_mult()) * stun_radius_mult
	var total_stun: float = base_stun + stun_bonus
	for e in Targeting.enemies_in_radius(get_tree(), global_position, r):
		if e.has_method("stun"):
			e.stun(total_stun)
	return r

func _owner_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == owner_peer_id:
			return p
	return null

func _broadcast_damage_number(amount: float, pos: Vector2) -> void:
	var crit := amount >= 30.0
	if multiplayer.multiplayer_peer != null:
		_rpc_damage_number.rpc(amount, pos, crit)
	else:
		_rpc_damage_number(amount, pos, crit)

@rpc("authority", "reliable", "call_local")
func _rpc_damage_number(amount: float, pos: Vector2, crit: bool) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("spawn_damage_number"):
		arena.spawn_damage_number(amount, pos, crit)

# ---- Render ------------------------------------------------------------

func _draw() -> void:
	var t: float = _now()
	var spawn_age: float = t - _spawn_at
	# Спрайт варвара. Тон лерпится из красного в коричневый за RED_OVERLAY_DURATION.
	# Когда чучело умирает (dying=true) — затухание в FX-ринг.
	var fade: float = 1.0
	if dying and _dying_started_at >= 0.0:
		var dt: float = t - _dying_started_at
		fade = clampf(1.0 - dt / DEATH_QUAKE_FX_DURATION, 0.0, 1.0)
	var size: float = RADIUS * SPRITE_SIZE_MULT
	var rect := Rect2(-Vector2(size, size) * 0.5, Vector2(size, size))
	var k_settle: float = clampf(spawn_age / RED_OVERLAY_DURATION, 0.0, 1.0)
	var tint: Color = RED_OVERLAY.lerp(BROWN_TINT, k_settle)
	tint.a *= fade
	draw_texture_rect(SPRITE_TEX, rect, false, tint)
	# Анимация рёва — повторяет старую FX из player_view._draw_berserker_fx.
	if spawn_age >= 0.0 and spawn_age < ROAR_FX_DURATION:
		var k: float = 1.0 - spawn_age / ROAR_FX_DURATION
		var rcur: float = fx_radius * clampf(spawn_age / (ROAR_FX_DURATION * 0.92), 0.0, 1.0)
		draw_arc(Vector2.ZERO, rcur, 0, TAU, 64, Color(1, 0.35, 0.35, 0.55 * k), 4.0)
	# Импульс отдачи (когда заиграл retaliate_seq).
	if _retaliate_started_at >= 0.0:
		var rt: float = t - _retaliate_started_at
		if rt < RETALIATION_FX_DURATION:
			var k_ret: float = 1.0 - rt / RETALIATION_FX_DURATION
			var rmax_ret: float = float(RETALIATION_RADIUS)
			var rcur_ret: float = rmax_ret * clampf(rt / (RETALIATION_FX_DURATION * 0.92), 0.0, 1.0)
			draw_arc(Vector2.ZERO, rcur_ret, 0, TAU, 56, Color(1.0, 0.25, 0.25, 0.7 * k_ret), 4.0)
			draw_arc(Vector2.ZERO, rcur_ret * 0.7, 0, TAU, 48, Color(1.0, 0.55, 0.35, 0.45 * k_ret), 2.0)
	# Эпик-предсмертный квейк: расходящееся рыжее кольцо.
	if dying and death_quake_radius > 0.0 and _dying_started_at >= 0.0:
		var dt: float = t - _dying_started_at
		if dt < DEATH_QUAKE_FX_DURATION:
			var kq: float = 1.0 - dt / DEATH_QUAKE_FX_DURATION
			var grow: float = clampf(dt / (DEATH_QUAKE_FX_DURATION * 0.9), 0.0, 1.0)
			var rcur: float = death_quake_radius * grow
			draw_arc(Vector2.ZERO, rcur, 0, TAU, 64, Color(0.85, 0.55, 0.25, 0.7 * kq), 6.0)
			for i in 6:
				var ang: float = i * (TAU / 6.0)
				var dir := Vector2(cos(ang), sin(ang))
				draw_line(dir * (rcur * 0.2), dir * (rcur * 0.7), Color(0.7, 0.4, 0.2, 0.55 * kq), 3.0)
	# HP-бар над чучелом.
	if hp < max_hp and not dying:
		var w := 40.0
		var h := 4.0
		var top := Vector2(-w * 0.5, -RADIUS - 14)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(hp / max(max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.85, 0.45, 0.25))

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
