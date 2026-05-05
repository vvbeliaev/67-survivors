extends CharacterBody2D

# Host-authoritative. All AI runs only on host. Position replicated via
# MultiplayerSynchronizer. Clients render but do nothing.

const TEAM := "enemy"

@export var enemy_type: String = "rusher"
@export var hp: float = 25.0
@export var max_hp: float = 25.0
@export var move_speed: float = 180.0
@export var contact_damage: float = 8.0
@export var contact_cd: float = 0.6
@export var ranged: bool = false
@export var ranged_dist: float = 250.0
@export var projectile_speed: float = 240.0
@export var projectile_damage: float = 6.0
@export var ranged_cd: float = 1.5
@export var xp_value: int = 1
@export var color_hint: Color = Color(0.9, 0.4, 0.4)
@export var radius: float = 12.0
@export var alive: bool = true

# Boss-only telegraph attack.
@export var boss_aoe: bool = false
@export var boss_aoe_radius: float = 180.0
@export var boss_aoe_damage: float = 30.0
@export var boss_aoe_cd: float = 6.0
@export var boss_aoe_windup: float = 1.2
@export var boss_aoe_state: int = 0  # 0=idle, 1=winding, 2=resolved
@export var boss_aoe_timer: float = 0.0
@export var boss_aoe_pos: Vector2 = Vector2.ZERO

# Status effects (host-only logic, but timestamps replicated for visual).
@export var stunned_until: float = 0.0
@export var forced_target_id: int = -1
@export var forced_target_until: float = 0.0

@export var team_tag: String = "enemy"

var _attack_cd: float = 0.0
var _ranged_cd: float = 0.0
var _aoe_cd: float = 0.0

func _ready() -> void:
	collision_layer = 1 << 2  # Enemies layer (bit 2)
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)  # World, Players, Enemies
	add_to_group("enemies")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		queue_redraw()
		return
	if not alive:
		return
	var now := _now()
	if now < stunned_until:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var target := _pick_target()
	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to_t: Vector2 = target.global_position - global_position
	var dist := to_t.length()
	var dir := to_t.normalized() if dist > 0.001 else Vector2.ZERO

	if boss_aoe:
		_tick_boss_aoe(delta, target)

	if ranged:
		# Maintain stand-off distance.
		var desired := ranged_dist
		if dist < desired - 30:
			velocity = -dir * move_speed
		elif dist > desired + 30:
			velocity = dir * move_speed
		else:
			velocity = Vector2.ZERO
		_ranged_cd -= delta
		if _ranged_cd <= 0 and dist <= ranged_dist + 80:
			_ranged_cd = ranged_cd
			_fire_ranged(target)
	else:
		velocity = dir * move_speed
	move_and_slide()

	# Contact damage.
	_attack_cd -= delta
	if not ranged and dist < radius + 18 and _attack_cd <= 0:
		_attack_cd = contact_cd
		if target.has_method("apply_damage"):
			target.apply_damage(contact_damage, "enemy")

func _tick_boss_aoe(delta: float, target: Node2D) -> void:
	match boss_aoe_state:
		0:
			_aoe_cd -= delta
			if _aoe_cd <= 0:
				boss_aoe_state = 1
				boss_aoe_timer = boss_aoe_windup
				boss_aoe_pos = target.global_position
		1:
			boss_aoe_timer -= delta
			if boss_aoe_timer <= 0:
				_resolve_boss_aoe()
				boss_aoe_state = 0
				_aoe_cd = boss_aoe_cd

func _resolve_boss_aoe() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive:
			continue
		if p.global_position.distance_to(boss_aoe_pos) <= boss_aoe_radius:
			p.apply_damage(boss_aoe_damage, "enemy")

func _fire_ranged(target: Node2D) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	arena.spawn_projectile({
		"pos": global_position + dir * (radius + 4),
		"vel": dir * projectile_speed,
		"damage": projectile_damage,
		"lifetime": 3.0,
		"team": "enemy",
		"color": Color(1.0, 0.5, 0.2),
		"radius": 6.0,
		"pierce": 0,
	})

func _pick_target() -> Node2D:
	var now := _now()
	if forced_target_id != -1 and now < forced_target_until:
		var n := _find_player(forced_target_id)
		if n != null and n.alive:
			return n
		forced_target_id = -1
	# Nearest alive player.
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _find_player(peer_id: int) -> Node2D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null

func apply_damage(amount: float, _src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	hp -= amount
	if hp <= 0:
		alive = false
		var arena := get_tree().get_first_node_in_group("arena")
		if arena != null and arena.has_method("on_enemy_killed"):
			arena.on_enemy_killed(self)
		queue_free()

func force_target(peer_id: int, duration: float) -> void:
	if not GameState.is_authority():
		return
	forced_target_id = peer_id
	forced_target_until = _now() + duration

func stun(duration: float) -> void:
	if not GameState.is_authority():
		return
	stunned_until = max(stunned_until, _now() + duration)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color_hint)
	# HP bar.
	if hp < max_hp:
		var w: float = radius * 2.4
		var h := 4.0
		var top := Vector2(-w * 0.5, -radius - 10)
		draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.95, 0.3, 0.3))
	# Boss telegraph: red ring at target spot during windup.
	if boss_aoe and boss_aoe_state == 1:
		draw_arc(boss_aoe_pos - global_position, boss_aoe_radius, 0, TAU, 48, Color(1, 0.2, 0.2, 0.7), 3.0)
