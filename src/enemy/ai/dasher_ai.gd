extends EnemyAI

# Dasher: a tougher spider that walks slowly and lunges at the nearest player
# along a telegraphed line.
#
# State machine (mirrored on `owner_enemy.dash_state` so the view can react):
#   0 IDLE        — slow chase. If a player is within TRIGGER_RADIUS, lock in
#                   a direction and enter TELEGRAPH.
#   1 TELEGRAPH   — stand still, draw the red line. Direction rotates toward
#                   the player at TURN_RATE rad/s for TELEGRAPH_TRACKING sec.
#   2 LOCKED      — last LOCKED_DURATION seconds before launch, line stops
#                   tracking — players get a fixed window to dodge.
#   3 DASHING     — high-speed linear charge along the locked direction. Deals
#                   DASH_DAMAGE on contact (player iframes prevent multi-hit).
#   4 COOLDOWN    — brief post-dash recovery before walking resumes.

const STATE_IDLE: int = 0
const STATE_TELEGRAPH: int = 1
const STATE_LOCKED: int = 2
const STATE_DASHING: int = 3
const STATE_COOLDOWN: int = 4

const DASH_RANGE: float = 350.0
const DASH_SPEED: float = 720.0
const DASH_DAMAGE: float = 32.0
# Trigger ratio: a unit lunges when its target is within this fraction of its
# *own* dash range. Trigger radius therefore inherits the per-unit jitter.
const TRIGGER_RATIO: float = 0.9

const TELEGRAPH_TRACKING: float = 1.0
const LOCKED_DURATION: float = 0.5
const COOLDOWN_DURATION: float = 0.7
const TURN_RATE: float = 0.7  # rad / second while telegraphing

# Per-unit jitter ranges. Multiplicative around the base values above so a
# pack of dashers no longer commits in lockstep — different ranges stagger
# the trigger distance, different turn rates fan their telegraph lines apart.
const RANGE_JITTER: float = 0.18    # ±18% on dash range / trigger
const TURN_JITTER: float = 0.35     # ±35% on telegraph turn rate

var _state_timer: float = 0.0
var _dash_origin: Vector2 = Vector2.ZERO
var _dash_dir: Vector2 = Vector2.RIGHT
var _attack_cd: float = 0.0

# Sampled once per instance in setup() and used for the rest of its life.
var _dash_range: float = DASH_RANGE
var _trigger_radius: float = DASH_RANGE * TRIGGER_RATIO
var _turn_rate: float = TURN_RATE

func setup(e: Node) -> void:
	super.setup(e)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_dash_range = DASH_RANGE * rng.randf_range(1.0 - RANGE_JITTER, 1.0 + RANGE_JITTER)
	_trigger_radius = _dash_range * TRIGGER_RATIO
	_turn_rate = TURN_RATE * rng.randf_range(1.0 - TURN_JITTER, 1.0 + TURN_JITTER)

func tick(delta: float) -> void:
	var e := owner_enemy
	if _now() < e.stunned_until:
		e.velocity = Vector2.ZERO
		return
	match e.dash_state:
		STATE_IDLE:
			_tick_idle(delta)
		STATE_TELEGRAPH:
			_tick_telegraph(delta)
		STATE_LOCKED:
			_tick_locked(delta)
		STATE_DASHING:
			_tick_dashing(delta)
		STATE_COOLDOWN:
			_tick_cooldown(delta)

func _tick_idle(delta: float) -> void:
	var e := owner_enemy
	var target := _pick_target()
	if target == null:
		e.velocity = Vector2.ZERO
		return
	var to_t: Vector2 = target.global_position - e.global_position
	var dist: float = to_t.length()
	var dir: Vector2 = to_t.normalized() if dist > 0.001 else Vector2.RIGHT
	e.velocity = dir * e.move_speed * e.move_speed_mult
	# Light contact damage if the player ends up brushing the spider while
	# walking (gives the unit a baseline threat outside the dash window).
	_attack_cd -= delta
	if dist < e.radius + 18.0 and _attack_cd <= 0.0:
		_attack_cd = e.contact_cd
		if target.has_method("apply_damage"):
			target.apply_damage(e.contact_damage, "enemy")
	if dist < _trigger_radius:
		_begin_telegraph(dir)

func _begin_telegraph(dir: Vector2) -> void:
	var e := owner_enemy
	_dash_dir = dir
	_dash_origin = e.global_position
	e.dash_target_pos = e.global_position + dir * _dash_range
	e.dash_state = STATE_TELEGRAPH
	_state_timer = TELEGRAPH_TRACKING
	e.velocity = Vector2.ZERO

func _tick_telegraph(delta: float) -> void:
	var e := owner_enemy
	e.velocity = Vector2.ZERO
	var target := _pick_target()
	if target != null:
		var want: Vector2 = (target.global_position - e.global_position)
		if want.length_squared() > 0.0001:
			var want_dir: Vector2 = want.normalized()
			var diff: float = _dash_dir.angle_to(want_dir)
			var step: float = clampf(diff, -_turn_rate * delta, _turn_rate * delta)
			_dash_dir = _dash_dir.rotated(step)
	# Re-anchor target_pos every tick so separation drift doesn't skew the
	# indicator, and keep facing_dir aligned for the sprite rotation.
	e.dash_target_pos = e.global_position + _dash_dir * _dash_range
	e.facing_dir = _dash_dir
	_state_timer -= delta
	if _state_timer <= 0.0:
		e.dash_state = STATE_LOCKED
		_state_timer = LOCKED_DURATION

func _tick_locked(delta: float) -> void:
	var e := owner_enemy
	e.velocity = Vector2.ZERO
	# No rotation tracking — but keep the endpoint anchored to the spider's
	# *current* position so the indicator doesn't visually drift if separation
	# nudges the body sideways during the lock window.
	e.dash_target_pos = e.global_position + _dash_dir * _dash_range
	e.facing_dir = _dash_dir
	_state_timer -= delta
	if _state_timer <= 0.0:
		_dash_origin = e.global_position
		e.dash_state = STATE_DASHING
		_dashed_hits.clear()

var _dashed_hits: Dictionary = {}  # player ref -> true (one hit per dash)

func _tick_dashing(delta: float) -> void:
	var e := owner_enemy
	e.velocity = _dash_dir * DASH_SPEED
	e.facing_dir = _dash_dir
	# Damage check: anyone we overlap during the lunge takes a hit. The
	# player's i-frame window naturally prevents multi-tick multi-hit, but
	# tracking already-hit refs avoids spamming apply_damage / damage numbers.
	# Чучело варвара ходит в одном пуле с игроками — иначе дэшеры пролетают
	# сквозь приманку, не повреждая её.
	var hit_r: float = e.radius + 18.0
	for p in Targeting.player_targets_in_radius(get_tree(), e.global_position, hit_r):
		if p == null or not is_instance_valid(p):
			continue
		if not p.alive:
			continue
		if _dashed_hits.has(p):
			continue
		_dashed_hits[p] = true
		if p.has_method("apply_damage"):
			p.apply_damage(DASH_DAMAGE, "enemy")
	if e.global_position.distance_to(_dash_origin) >= _dash_range:
		e.dash_state = STATE_COOLDOWN
		_state_timer = COOLDOWN_DURATION
		e.velocity = Vector2.ZERO

func _tick_cooldown(delta: float) -> void:
	var e := owner_enemy
	e.velocity = Vector2.ZERO
	_state_timer -= delta
	if _state_timer <= 0.0:
		e.dash_state = STATE_IDLE
