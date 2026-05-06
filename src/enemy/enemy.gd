extends CharacterBody2D

const _EnemyPace := preload("res://src/data/enemy_pace.gd")

# Slim host-authoritative enemy. Holds the replicated state needed for view +
# host-only stats. Behaviour lives on the AI child node, which is built from
# the EnemyDef referenced at spawn.

const TEAM := "enemy"

# Replicated identity / stats.
@export var enemy_type: StringName = &"rusher"
@export var hp: float = 25.0
@export var max_hp: float = 25.0
@export var color_hint: Color = Color(0.9, 0.4, 0.4)
@export var radius: float = 12.0
@export var alive: bool = true
@export var team_tag: String = "enemy"

# Replicated boss telegraph state (so clients can draw the ring).
@export var boss_aoe: bool = false
@export var boss_aoe_radius: float = 0.0
@export var boss_aoe_state: int = 0
@export var boss_aoe_pos: Vector2 = Vector2.ZERO

# Last meaningful movement direction. Replicated so the view rotates the
# sprite consistently for every peer.
@export var facing_dir: Vector2 = Vector2.DOWN

# Host-only fields (not replicated).
var move_speed: float = 180.0
var contact_damage: float = 8.0
var contact_cd: float = 0.6
var ranged: bool = false
var ranged_dist: float = 250.0
var projectile_speed: float = 240.0
var projectile_damage: float = 6.0
var ranged_cd: float = 1.5
var xp_value: int = 1

var boss_aoe_damage: float = 0.0
var boss_aoe_cd: float = 0.0
var boss_aoe_windup: float = 0.0
var boss_aoe_timer: float = 0.0

var stunned_until: float = 0.0
var forced_target_id: int = -1
var forced_target_until: float = 0.0

var ai: EnemyAI = null
var _def: EnemyDef = null

const SEP_RADIUS_MULT := 2.0
const SEP_STRENGTH := 0.6

func _ready() -> void:
	collision_layer = 1 << 2                # Enemies
	collision_mask = (1 << 0) | (1 << 1)    # World, Players (no enemy↔enemy: replaced by manual separation)
	add_to_group("enemies")

func setup(def: EnemyDef) -> void:
	_def = def
	if def == null:
		return
	enemy_type = def.id
	max_hp = def.max_hp
	hp = max_hp
	color_hint = def.color_hint
	radius = def.radius
	contact_damage = def.contact_damage
	contact_cd = def.contact_cd
	move_speed = _EnemyPace.move_speed(def)
	ranged = def.ranged
	ranged_dist = def.ranged_dist
	projectile_speed = def.projectile_speed
	projectile_damage = def.projectile_damage
	ranged_cd = def.ranged_cd
	xp_value = def.xp_value
	boss_aoe = def.boss
	boss_aoe_radius = def.boss_aoe_radius
	boss_aoe_damage = def.boss_aoe_damage
	boss_aoe_cd = def.boss_aoe_cd
	boss_aoe_windup = def.boss_aoe_windup
	if def.ai_script != null:
		ai = def.ai_script.new()
		add_child(ai)
		ai.setup(self)
	var col := get_node_or_null("CollisionShape2D")
	if col != null and col.shape is CircleShape2D:
		var s: CircleShape2D = col.shape.duplicate()
		s.radius = radius
		col.shape = s

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	if ai != null:
		ai.tick(delta)
	_apply_separation()
	move_and_slide()
	if velocity.length_squared() > 1.0:
		facing_dir = velocity.normalized()

# Cheap boids-style repulsion replacing the removed enemy↔enemy physics
# pairs. Pulls candidates from SpatialIndex (rebuilt at -1000 priority, so
# already populated this frame). Inverse-square accumulation, then a single
# normalized push at SEP_STRENGTH × move_speed — no jitter spikes.
func _apply_separation() -> void:
	var sep_r: float = radius * SEP_RADIUS_MULT
	var others: Array = SpatialIndex.enemies_in_radius(global_position, sep_r)
	if others.size() <= 1:
		return
	var push: Vector2 = Vector2.ZERO
	var sep_r2: float = sep_r * sep_r
	for o in others:
		if o == self:
			continue
		if not is_instance_valid(o) or not o.alive:
			continue
		var diff: Vector2 = global_position - o.global_position
		var d2: float = diff.length_squared()
		if d2 > 0.0001 and d2 < sep_r2:
			push += diff / d2
	if push.length_squared() > 0.0:
		velocity += push.normalized() * move_speed * SEP_STRENGTH

# ---- Status hooks called by skills -------------------------------------

func apply_damage(amount: float, _src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	hp -= amount
	_broadcast_damage_number(amount, global_position)
	if hp <= 0.0:
		alive = false
		EventBus.enemy_killed.emit(self, 1)
		queue_free()

func _broadcast_damage_number(amount: float, pos: Vector2) -> void:
	var crit := amount >= 30.0
	if multiplayer.multiplayer_peer != null:
		_rpc_show_damage_number.rpc(amount, pos, crit)
	else:
		_rpc_show_damage_number(amount, pos, crit)

@rpc("authority", "reliable", "call_local")
func _rpc_show_damage_number(amount: float, pos: Vector2, crit: bool) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("spawn_damage_number"):
		arena.spawn_damage_number(amount, pos, crit)

func force_target(peer_id: int, duration: float) -> void:
	if not GameState.is_authority():
		return
	forced_target_id = peer_id
	forced_target_until = (Time.get_ticks_msec() / 1000.0) + duration

func stun(duration: float) -> void:
	if not GameState.is_authority():
		return
	stunned_until = max(stunned_until, (Time.get_ticks_msec() / 1000.0) + duration)
