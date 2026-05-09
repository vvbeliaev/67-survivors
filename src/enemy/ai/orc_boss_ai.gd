extends EnemyAI

# Orc shaman boss. Movement is stand-off (keeps preferred range, like ranged_ai
# but without projectile attacks). Every CAGE_INTERVAL the boss locks the
# nearest player into a "black arena" — a soft circular leash centered on the
# player's position at windup start. Going outside the leash pulls that one
# player back (mirrors ArenaBoundary). Other players ignore the cage.
#
# Cast cycle (state machine on enemy.cage_state):
#   0 idle    — no cage rendered. After CAGE_IDLE seconds, transition to 1.
#   1 windup  — telegraph at cage_center for WINDUP_DURATION seconds. Target
#               and position are locked at state-1 entry; pull is NOT applied.
#               Boss self-glow signals the cast.
#   2 active  — black ring up, target peer leashed inside for CAGE_DURATION
#               seconds, then back to 0.
# CAGE_INTERVAL == WINDUP_DURATION + CAGE_DURATION + CAGE_IDLE so "every 10s"
# describes the cast-start cadence.

const CAGE_INTERVAL: float = 10.0
const WINDUP_DURATION: float = 1.5
const CAGE_DURATION: float = 5.0
const CAGE_IDLE: float = CAGE_INTERVAL - WINDUP_DURATION - CAGE_DURATION
const CAGE_RADIUS: float = 280.0
# Same as ArenaBoundary.PULL_SPEED — strictly above any reachable player speed
# so the leash is uncrossable regardless of move-speed stacking.
const CAGE_PULL_SPEED: float = 900.0

# Idle countdown to next windup. First cast happens shortly after spawn so
# players see the boss actually do something during arrival.
var _idle_left: float = max(0.5, CAGE_IDLE)
var _state_left: float = 0.0

func setup(e: Node) -> void:
	super.setup(e)
	# Capacity is replicated mode 0 (spawn-time), so set it before the
	# spawner pushes the snapshot to clients.
	e.cage_radius = CAGE_RADIUS
	e.cage_state = 0
	e.cage_state_started_msec = Time.get_ticks_msec()

func tick(delta: float) -> void:
	var e := owner_enemy
	_tick_cage(delta)
	if _now() < e.stunned_until:
		e.velocity = Vector2.ZERO
		return
	var target := _pick_target()
	if target == null:
		e.velocity = Vector2.ZERO
		return
	var to_t: Vector2 = target.global_position - e.global_position
	var dist: float = to_t.length()
	var dir: Vector2 = to_t.normalized() if dist > 0.001 else Vector2.ZERO
	# Stand-off behaviour: hold the boss at preferred range; back off if the
	# target closes in, advance if they slip too far.
	var desired: float = e.ranged_dist
	var spd: float = e.move_speed * e.move_speed_mult
	if dist < desired - 30.0:
		e.velocity = -dir * spd
	elif dist > desired + 30.0:
		e.velocity = dir * spd
	else:
		e.velocity = Vector2.ZERO

func _tick_cage(delta: float) -> void:
	var e := owner_enemy
	match e.cage_state:
		0:
			_idle_left -= delta
			if _idle_left <= 0.0:
				_start_windup()
		1:
			_state_left -= delta
			if _state_left <= 0.0:
				_start_active()
		2:
			_state_left -= delta
			if _state_left <= 0.0:
				_end_cage()
				return
			_apply_pull(delta)

func _start_windup() -> void:
	var e := owner_enemy
	var t: Node2D = Targeting.nearest_alive_player(get_tree(), e.global_position)
	if t == null:
		# Никого живого — пропускаем цикл целиком, чтобы не висеть в windup
		# впустую и не телеграфить пустоту.
		_idle_left = CAGE_IDLE
		return
	e.cage_state = 1
	e.cage_target_peer = int(t.peer_id)
	e.cage_center = t.global_position
	e.cage_state_started_msec = Time.get_ticks_msec()
	_state_left = WINDUP_DURATION

func _start_active() -> void:
	var e := owner_enemy
	# Если цель умерла за время каста — каст «срывается», возвращаемся в idle
	# без активной фазы. Кагдж на пустом месте смотрелся бы нелепо.
	var p: Node2D = _find_player(e.cage_target_peer)
	if p == null or not p.alive:
		_end_cage()
		return
	e.cage_state = 2
	e.cage_state_started_msec = Time.get_ticks_msec()
	_state_left = CAGE_DURATION

func _end_cage() -> void:
	var e := owner_enemy
	e.cage_state = 0
	e.cage_state_started_msec = Time.get_ticks_msec()
	_idle_left = CAGE_IDLE

func _apply_pull(delta: float) -> void:
	var e := owner_enemy
	var p: Node2D = _find_player(e.cage_target_peer)
	if p == null or not p.alive:
		_end_cage()
		return
	var to_center: Vector2 = e.cage_center - p.global_position
	var dist_to_center: float = to_center.length()
	if dist_to_center <= e.cage_radius:
		return
	var step: float = CAGE_PULL_SPEED * delta
	var overshoot: float = dist_to_center - e.cage_radius
	var move: float = min(step, overshoot)
	if dist_to_center > 0.001:
		p.global_position += to_center / dist_to_center * move
