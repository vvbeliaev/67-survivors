extends CharacterBody2D

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

func _ready() -> void:
	collision_layer = 1 << 2                          # Enemies
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)   # World, Players, Enemies
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
	move_speed = def.move_speed
	contact_damage = def.contact_damage
	contact_cd = def.contact_cd
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

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	if ai != null:
		ai.tick(delta)

# ---- Status hooks called by skills -------------------------------------

func apply_damage(amount: float, _src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		alive = false
		EventBus.enemy_killed.emit(self, 1)
		queue_free()

func force_target(peer_id: int, duration: float) -> void:
	if not GameState.is_authority():
		return
	forced_target_id = peer_id
	forced_target_until = (Time.get_ticks_msec() / 1000.0) + duration

func stun(duration: float) -> void:
	if not GameState.is_authority():
		return
	stunned_until = max(stunned_until, (Time.get_ticks_msec() / 1000.0) + duration)
