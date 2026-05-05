extends CharacterBody2D

# Slim host-authoritative player. Owns:
#   - identity (peer_id, nick, klass)
#   - replicated state (`@export` fields)
#   - a StatBlock (host-only)
#   - a ClassNode child (skills + class hooks)
#
# Behavior splits:
#   - InputController child captures input on the owner peer and RPCs it here.
#   - ClassNode owns class-specific stat seeding and the four skill children
#     (auto / primary / secondary / utility).
#   - Renderer (PlayerView) draws — no logic.
#
# All gameplay logic gates on GameState.is_authority(); clients only render.

const RESPAWN_DELAY := 30.0
const TEAM := "player"
const COOLDOWN_FLOOR := 0.4

# Identity (set at spawn).
@export var peer_id: int = 1
@export var nick: String = "P"
@export var klass: StringName = &"berserker"

# Replicated mutable state.
@export var hp: float = 200.0
@export var max_hp: float = 200.0
@export var mp: float = 100.0
@export var max_mp: float = 100.0
@export var alive: bool = true
@export var downed_until: float = 0.0
@export var color_hint: Color = Color(0.4, 0.8, 1.0)
@export var radius: float = 16.0
@export var aim_dir: Vector2 = Vector2.RIGHT
@export var charge_started_at: float = -1.0
@export var iframes_until: float = 0.0

# Marker exposed to projectile filtering.
@export var team_tag: String = "player"

# Host-only state.
var stats: StatBlock = StatBlock.new()
var class_node: ClassNode = null
var _class_def: ClassDef = null

# Visual FX payloads keyed by kind; host announces via RPC call_local.
var _fx_local: Dictionary = {}

# Latest input mirror (host stores input received from owner peer).
var _in_move: Vector2 = Vector2.ZERO
var _in_aim: Vector2 = Vector2.ZERO
var _in_primary_pressed: bool = false
var _in_secondary_pressed: bool = false
var _in_utility_pressed: bool = false
var _in_primary_held: bool = false
var _in_primary_released: bool = false
var _input_age: float = 0.0

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1                          # Players
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)   # World, Players, Enemies

func setup(peer: int, nck: String, kl: StringName) -> void:
	peer_id = peer
	nick = nck
	klass = kl
	_class_def = Defs.class_def(klass)
	if _class_def == null:
		push_warning("Player.setup: missing ClassDef for %s" % klass)
		return
	color_hint = _class_def.color_hint
	radius = _class_def.radius
	_install_class_node()
	max_hp = stats.value(StatBlock.STAT_MAX_HP)
	max_mp = stats.value(StatBlock.STAT_MAX_MP)
	hp = max_hp
	mp = max_mp

func _install_class_node() -> void:
	if _class_def == null or _class_def.node_script == null:
		return
	class_node = _class_def.node_script.new()
	add_child(class_node)
	class_node.setup(self, _class_def, stats)

# ---- Input pipeline ----------------------------------------------------

func apply_input(move: Vector2, aim_world: Vector2, primary_just: bool, secondary_just: bool, utility_just: bool, primary_held: bool, primary_release: bool) -> void:
	_in_move = move.limit_length(1.0)
	_in_aim = aim_world
	_in_primary_pressed = primary_just
	_in_secondary_pressed = secondary_just
	_in_utility_pressed = utility_just
	_in_primary_held = primary_held
	_in_primary_released = primary_release
	_input_age = 0.0

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_apply_input(move: Vector2, aim_world: Vector2, primary_just: bool, secondary_just: bool, utility_just: bool, primary_held: bool, primary_release: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not GameState.is_authority():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	apply_input(move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)

# ---- Per-tick simulation -----------------------------------------------

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		velocity = Vector2.ZERO
		move_and_slide()
		if Time.get_ticks_msec() / 1000.0 >= downed_until:
			_respawn()
		return

	# Discard stale inputs after 0.6s of silence.
	_input_age += delta
	if _input_age > 0.6:
		_in_move = Vector2.ZERO
		_in_primary_held = false

	# Aim direction.
	var aim_off: Vector2 = _in_aim - global_position
	if aim_off.length_squared() > 1.0:
		aim_dir = aim_off.normalized()

	# Class hooks (e.g. crossbow charge slow toggle).
	if class_node != null:
		class_node.on_pre_move(delta)

	# Movement.
	var speed := stats.value(StatBlock.STAT_SPEED)
	velocity = _in_move * speed
	move_and_slide()

	# Regen.
	if max_mp > 0.0:
		mp = min(mp + stats.value(StatBlock.STAT_MP_REGEN) * delta, max_mp)
	var hpr := stats.value(StatBlock.STAT_HP_REGEN)
	if hpr > 0.0:
		hp = min(hp + hpr * delta, max_hp)

	# Skills.
	_dispatch_skills(delta)

	# Reset edge-trigger flags.
	_in_primary_pressed = false
	_in_secondary_pressed = false
	_in_utility_pressed = false
	_in_primary_released = false

	# Refresh derived replicated maxima (in case stats changed via upgrades or buffs).
	var new_max_hp := stats.value(StatBlock.STAT_MAX_HP)
	if absf(new_max_hp - max_hp) > 0.001:
		max_hp = new_max_hp
		hp = min(hp, max_hp)
	var new_max_mp := stats.value(StatBlock.STAT_MAX_MP)
	if absf(new_max_mp - max_mp) > 0.001:
		max_mp = new_max_mp
		mp = min(mp, max_mp)

func _dispatch_skills(delta: float) -> void:
	if class_node == null:
		return
	if class_node.auto_skill != null:
		class_node.auto_skill.tick(delta)
	if class_node.primary_skill != null:
		class_node.primary_skill.tick(delta)
		if _in_primary_pressed:
			class_node.primary_skill.on_pressed()
		if _in_primary_held:
			class_node.primary_skill.on_held(delta)
		if _in_primary_released:
			class_node.primary_skill.on_released()
	if class_node.secondary_skill != null:
		class_node.secondary_skill.tick(delta)
		if _in_secondary_pressed:
			class_node.secondary_skill.on_pressed()
	if class_node.utility_skill != null:
		class_node.utility_skill.tick(delta)
		if _in_utility_pressed:
			class_node.utility_skill.on_pressed()

# ---- Stat accessors used by skills -------------------------------------

func dmg_mult() -> float:    return stats.value(StatBlock.STAT_DMG)
func atk_speed_mult() -> float: return stats.value(StatBlock.STAT_ATK_SPEED)
func range_mult() -> float:  return stats.value(StatBlock.STAT_RANGE)
func cooldown_factor() -> float: return max(stats.value(StatBlock.STAT_COOLDOWN), COOLDOWN_FLOOR)
func lifesteal() -> float:   return stats.value(StatBlock.STAT_LIFESTEAL)
func aim_world() -> Vector2: return _in_aim
func move_dir() -> Vector2:  return _in_move

# ---- Mutations --------------------------------------------------------

func teleport(world_pos: Vector2) -> void:
	if not GameState.is_authority():
		return
	global_position = world_pos

func grant_iframes(duration: float) -> void:
	if not GameState.is_authority():
		return
	iframes_until = (Time.get_ticks_msec() / 1000.0) + duration

func apply_damage(amount: float, _src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	if Time.get_ticks_msec() / 1000.0 < iframes_until:
		return
	hp -= amount
	_broadcast_damage_number(amount, global_position)
	EventBus.damage_dealt.emit(self, amount, _src_team)
	if hp <= 0.0:
		hp = 0.0
		_go_down()

func play_visual_fx(kind: String, data: Dictionary = {}) -> void:
	if not GameState.is_authority():
		return
	if multiplayer.multiplayer_peer != null:
		_rpc_play_vis_fx.rpc(kind, data)
	else:
		_rpc_play_vis_fx(kind, data)

@rpc("authority", "reliable", "call_local")
func _rpc_play_vis_fx(kind: String, data: Dictionary) -> void:
	var entry: Dictionary = data.duplicate(true)
	entry["t"] = Time.get_ticks_msec() / 1000.0
	_fx_local[kind] = entry

func fx_age(kind: String) -> float:
	if not _fx_local.has(kind):
		return -1.0
	return (Time.get_ticks_msec() / 1000.0) - float(_fx_local[kind].get("t", 0.0))

func fx_get(kind: String, key: String, default_value: Variant = null) -> Variant:
	if not _fx_local.has(kind):
		return default_value
	return _fx_local[kind].get(key, default_value)

func _broadcast_damage_number(amount: float, world_pos: Vector2) -> void:
	var crit := amount >= 30.0
	if multiplayer.multiplayer_peer != null:
		_rpc_damage_number.rpc(amount, world_pos, crit)
	else:
		_rpc_damage_number(amount, world_pos, crit)

@rpc("authority", "reliable", "call_local")
func _rpc_damage_number(amount: float, world_pos: Vector2, crit: bool) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("spawn_damage_number"):
		arena.spawn_damage_number(amount, world_pos, crit)

func heal(amount: float) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	hp = min(hp + amount, max_hp)
	EventBus.player_healed.emit(peer_id, amount)

func apply_temp_pct_buff(stat: StringName, mod_id: StringName, amount: float, duration: float) -> void:
	if not GameState.is_authority():
		return
	stats.add_pct(stat, mod_id, amount)
	get_tree().create_timer(duration).timeout.connect(func ():
		stats.remove(mod_id)
	)

# Apply an UpgradeDef. Stack index is bookkept here so duplicate picks coexist.
var _upgrade_stacks: Dictionary = {}  # upgrade_id -> int

func apply_upgrade_def(def: UpgradeDef) -> void:
	if not GameState.is_authority():
		return
	if def == null:
		return
	var prev: int = int(_upgrade_stacks.get(def.id, 0))
	prev += 1
	_upgrade_stacks[def.id] = prev
	stats.apply_upgrade(def, prev)
	if def.heal_on_pick > 0.0:
		hp = min(hp + def.heal_on_pick, stats.value(StatBlock.STAT_MAX_HP))
	if def.refill_mana:
		mp = stats.value(StatBlock.STAT_MAX_MP)

# ---- Down / respawn ---------------------------------------------------

func _go_down() -> void:
	alive = false
	downed_until = (Time.get_ticks_msec() / 1000.0) + RESPAWN_DELAY
	EventBus.player_downed.emit(peer_id)

func _respawn() -> void:
	# Snap to centroid of remaining alive party.
	var sum := Vector2.ZERO
	var count := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self:
			continue
		if p.alive:
			sum += p.global_position
			count += 1
	if count > 0:
		global_position = sum / float(count)
	alive = true
	hp = max_hp * 0.5
	mp = max_mp * 0.5
	iframes_until = (Time.get_ticks_msec() / 1000.0) + 1.0
	EventBus.player_revived.emit(peer_id)
