extends CharacterBody2D

# Server-authoritative. Local peer reads input and forwards to host via RPC;
# host runs physics and effects; MultiplayerSynchronizer pushes state back to
# every client.

const TEAM := "player"

const CLASS_SPRITES := {
	"berserker": preload("res://images/berserker_top.png"),
	"mage": preload("res://images/wizard_top.png"),
	"bard": preload("res://images/bard_top.png"),
	"crossbow": preload("res://images/crossbowman_top.png"),
}
const SPRITE_SIZE_MULT := 4.5  # sprite drawn ~ radius * mult px wide

# Identity (set at spawn).
@export var peer_id: int = 1
@export var nick: String = "P"
@export var klass: String = "berserker"

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
@export var charge_started_at: float = -1.0  # crossbow only
@export var iframes_until: float = 0.0

# Upgrade-applied multipliers (host-authoritative, replicated).
@export var dmg_mult: float = 1.0
@export var atk_speed_mult: float = 1.0
@export var range_mult: float = 1.0
@export var cooldown_mult: float = 1.0
@export var move_speed_bonus: float = 1.0
@export var max_hp_bonus: float = 0.0
@export var hp_regen: float = 0.0
@export var lifesteal: float = 0.0
@export var max_mp_bonus: float = 0.0
@export var mana_regen_bonus: float = 0.0

@export var team_tag: String = "player"

# Class base stats — populated in setup().
var base_speed: float = 240.0
var base_max_hp: float = 200.0
var base_max_mp: float = 100.0
var base_mana_regen: float = 8.0

# Skill cooldown timers (host-side).
var _auto_cd: float = 0.0
var _cast1_cd: float = 0.0
var _cast2_cd: float = 0.0
var _util_cd: float = 0.0
var _bard_heal_pulses_left: int = 0
var _bard_heal_next: float = 0.0

# Local-only FX timestamps. Triggered by host RPC, each peer ticks its own
# fade clock. Values are local Time.get_ticks_msec() seconds.
var _fx_local: Dictionary = {}
var _fx_dash_start: Vector2 = Vector2.ZERO

# Last input mirror (host stores input received from owner peer).
var _in_move: Vector2 = Vector2.ZERO
var _in_aim: Vector2 = Vector2.ZERO
var _in_primary_pressed: bool = false
var _in_secondary_pressed: bool = false
var _in_utility_pressed: bool = false
var _in_primary_held: bool = false
var _in_primary_released: bool = false
var _input_age: float = 0.0  # seconds since last input from peer

const RESPAWN_DELAY := 30.0

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1  # Players
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)  # World, Players, Enemies
	_apply_class_base()
	if GameState.is_authority():
		hp = max_hp
		mp = max_mp
	queue_redraw()

func setup(peer: int, nck: String, kl: String) -> void:
	peer_id = peer
	nick = nck
	klass = kl
	_apply_class_base()
	hp = max_hp
	mp = max_mp

func _apply_class_base() -> void:
	match klass:
		"berserker":
			base_speed = 240.0
			base_max_hp = 200.0
			base_max_mp = 0.0
			base_mana_regen = 0.0
			color_hint = Color(0.95, 0.3, 0.3)
		"mage":
			base_speed = 240.0
			base_max_hp = 90.0
			base_max_mp = 100.0
			base_mana_regen = 8.0
			color_hint = Color(0.4, 0.6, 1.0)
		"bard":
			base_speed = 260.0
			base_max_hp = 110.0
			base_max_mp = 0.0
			base_mana_regen = 0.0
			color_hint = Color(0.4, 0.95, 0.5)
		"crossbow":
			base_speed = 220.0
			base_max_hp = 110.0
			base_max_mp = 0.0
			base_mana_regen = 0.0
			color_hint = Color(0.95, 0.85, 0.3)
		_:
			pass
	max_hp = base_max_hp + max_hp_bonus
	max_mp = base_max_mp + max_mp_bonus

func _physics_process(delta: float) -> void:
	queue_redraw()
	var has_peer := multiplayer.multiplayer_peer != null
	var local_is_owner := (not has_peer) or multiplayer.get_unique_id() == peer_id
	if local_is_owner and alive:
		_send_input_to_host()
	if (not has_peer) or multiplayer.is_server():
		_server_step(delta)

func _send_input_to_host() -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim_world := get_global_mouse_position()
	var primary_just := Input.is_action_just_pressed("cast_primary")
	var secondary_just := Input.is_action_just_pressed("cast_secondary")
	var utility_just := Input.is_action_just_pressed("utility")
	var primary_held := Input.is_action_pressed("cast_primary")
	var primary_release := Input.is_action_just_released("cast_primary")
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_apply_input(move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)
	else:
		rpc_id(1, "_rpc_apply_input", move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_apply_input(move: Vector2, aim_world: Vector2, primary_just: bool, secondary_just: bool, utility_just: bool, primary_held: bool, primary_release: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not GameState.is_authority():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_apply_input(move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)

func _apply_input(move: Vector2, aim_world: Vector2, primary_just: bool, secondary_just: bool, utility_just: bool, primary_held: bool, primary_release: bool) -> void:
	_in_move = move.limit_length(1.0)
	_in_aim = aim_world
	_in_primary_pressed = primary_just
	_in_secondary_pressed = secondary_just
	_in_utility_pressed = utility_just
	_in_primary_held = primary_held
	_in_primary_released = primary_release
	_input_age = 0.0

func _server_step(delta: float) -> void:
	if not alive:
		# Tick respawn.
		if _now() >= downed_until:
			_respawn()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Stop using stale inputs after ~0.6s.
	_input_age += delta
	if _input_age > 0.6:
		_in_move = Vector2.ZERO
		_in_primary_held = false

	# Aim direction.
	var aim_off: Vector2 = _in_aim - global_position
	if aim_off.length_squared() > 1.0:
		aim_dir = aim_off.normalized()

	# Charge logic for crossbow slows movement.
	var move_mult := move_speed_bonus
	if klass == "crossbow" and charge_started_at >= 0.0:
		move_mult *= 0.4

	velocity = _in_move * base_speed * move_mult
	move_and_slide()

	# Cooldowns.
	_auto_cd = max(_auto_cd - delta, 0.0)
	_cast1_cd = max(_cast1_cd - delta, 0.0)
	_cast2_cd = max(_cast2_cd - delta, 0.0)
	_util_cd = max(_util_cd - delta, 0.0)

	# Mana regen.
	if max_mp > 0:
		mp = min(mp + (base_mana_regen + mana_regen_bonus) * delta, max_mp)

	# HP regen.
	if hp_regen > 0:
		hp = min(hp + hp_regen * delta, max_hp)

	# Class-specific behaviors.
	match klass:
		"berserker":
			_tick_berserker(delta)
		"mage":
			_tick_mage(delta)
		"bard":
			_tick_bard(delta)
		"crossbow":
			_tick_crossbow(delta)

	# Reset edge-trigger flags after one tick.
	_in_primary_pressed = false
	_in_secondary_pressed = false
	_in_utility_pressed = false
	_in_primary_released = false

# ---- Class behaviors (host-only) ----------------------------------------

func _tick_berserker(_delta: float) -> void:
	# Auto-attack: AoE swirl around self.
	if _auto_cd <= 0:
		_auto_cd = 0.4 / atk_speed_mult
		var r: float = 80.0 * range_mult
		_aoe_damage_enemies(global_position, r, 12.0 * dmg_mult)
		_emit_fx("auto", Vector2.ZERO, r)
	# LMB: dash strike (line damage, scales with missing hp).
	if _in_primary_pressed and _cast1_cd <= 0:
		_cast1_cd = 1.2 * cooldown_mult
		var rage := 1.0 + clampf((max_hp - hp) / max_hp, 0.0, 1.0)
		var dist := 160.0 * range_mult
		var start := global_position
		global_position += aim_dir * dist
		_aoe_damage_enemies(global_position, 50.0 * range_mult, 25.0 * dmg_mult * rage)
		_aoe_damage_enemies((start + global_position) * 0.5, dist * 0.5, 15.0 * dmg_mult * rage)
		_emit_fx("dash", start, 50.0 * range_mult)
	# RMB: roar — force agro within radius.
	if _in_secondary_pressed and _cast2_cd <= 0:
		_cast2_cd = 8.0 * cooldown_mult
		var r2: float = 240.0 * range_mult
		for e in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(e.global_position) <= r2:
				if e.has_method("force_target"):
					e.force_target(peer_id, 4.0)
		_emit_fx("roar", Vector2.ZERO, r2)
	# Space: quake — AoE stun + small damage.
	if _in_utility_pressed and _util_cd <= 0:
		_util_cd = 12.0 * cooldown_mult
		var rq: float = 140.0 * range_mult
		for e in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(e.global_position) <= rq:
				if e.has_method("stun"):
					e.stun(1.5)
				if e.has_method("apply_damage"):
					e.apply_damage(8.0 * dmg_mult, "player")
		_emit_fx("quake", Vector2.ZERO, rq)

func _tick_mage(_delta: float) -> void:
	# Auto: homing-ish snap to nearest enemy in range.
	if _auto_cd <= 0:
		var target := _nearest_enemy(700.0 * range_mult)
		if target != null:
			_auto_cd = 1.0 / atk_speed_mult
			var dir: Vector2 = (target.global_position - global_position).normalized()
			_spawn_proj(global_position + dir * (radius + 4), dir * 360.0, 8.0 * dmg_mult, Color(0.6, 0.7, 1.0), 2.5, 5.0, 0)
	# LMB: fireball at cursor (AoE on impact, costs mana).
	if _in_primary_pressed and _cast1_cd <= 0 and mp >= 30:
		_cast1_cd = 0.8 * cooldown_mult
		mp -= 30
		var dir: Vector2 = aim_dir
		# Spawn special: explode on first hit; we approximate by pierce=0, but
		# add an AoE on impact via spawning damage at position. Simpler: high
		# damage single hit + small AoE handled here as ring.
		_spawn_proj(global_position + dir * (radius + 4), dir * 480.0, 0.0, Color(1.0, 0.5, 0.2), 1.5, 7.0, 0)
		# Apply AoE at cursor immediately as approximation (host).
		_aoe_damage_enemies(_in_aim, 80.0 * range_mult, 8.0 * dmg_mult)
	# RMB: chain lightning — 3 nearest enemies.
	if _in_secondary_pressed and _cast2_cd <= 0 and mp >= 50:
		_cast2_cd = 4.0 * cooldown_mult
		mp -= 50
		var picked: Array = []
		var src: Vector2 = global_position
		for _i in 3:
			var e := _nearest_enemy_excluding(src, 600.0 * range_mult, picked)
			if e == null:
				break
			picked.append(e)
			if e.has_method("apply_damage"):
				e.apply_damage(18.0 * dmg_mult, "player")
			src = e.global_position
	# Space: blink toward cursor.
	if _in_utility_pressed and _util_cd <= 0:
		_util_cd = 5.0 * cooldown_mult
		var off: Vector2 = (_in_aim - global_position)
		var dist: float = min(off.length(), 220.0)
		global_position += off.normalized() * dist

func _tick_bard(_delta: float) -> void:
	# Auto: weak snap projectile.
	if _auto_cd <= 0:
		var target := _nearest_enemy(500.0 * range_mult)
		if target != null:
			_auto_cd = 0.8 / atk_speed_mult
			var dir: Vector2 = (target.global_position - global_position).normalized()
			_spawn_proj(global_position + dir * (radius + 4), dir * 320.0, 4.0 * dmg_mult, Color(0.7, 1.0, 0.7), 2.0, 5.0, 0)
	# LMB: heal aura (3 pulses).
	if _in_primary_pressed and _cast1_cd <= 0:
		_cast1_cd = 6.0 * cooldown_mult
		_bard_heal_pulses_left = 3
		_bard_heal_next = 0.0
	if _bard_heal_pulses_left > 0:
		_bard_heal_next -= _delta
		if _bard_heal_next <= 0:
			_bard_heal_next = 0.5
			_bard_heal_pulses_left -= 1
			var r: float = 180.0 * range_mult
			for p in get_tree().get_nodes_in_group("players"):
				if not p.alive:
					continue
				if p.global_position.distance_to(global_position) <= r:
					p.heal(8.0)
	# RMB: speed/damage buff.
	if _in_secondary_pressed and _cast2_cd <= 0:
		_cast2_cd = 10.0 * cooldown_mult
		var r2: float = 180.0 * range_mult
		for p in get_tree().get_nodes_in_group("players"):
			if not p.alive:
				continue
			if p.global_position.distance_to(global_position) <= r2:
				p.apply_temp_buff(0.2, 0.2, 5.0)
	# Space: dodge dash.
	if _in_utility_pressed and _util_cd <= 0:
		_util_cd = 4.0 * cooldown_mult
		var dir: Vector2 = _in_move if _in_move.length_squared() > 0.01 else aim_dir
		global_position += dir.normalized() * 180.0
		iframes_until = _now() + 0.3

func _tick_crossbow(_delta: float) -> void:
	# Holding LMB charges.
	if _in_primary_held and charge_started_at < 0:
		charge_started_at = _now()
	# Release fires the bolt.
	if _in_primary_released and _cast1_cd <= 0 and charge_started_at >= 0:
		var charge_t: float = clampf(_now() - charge_started_at, 0.0, 1.5)
		charge_started_at = -1.0
		_cast1_cd = 0.25 * cooldown_mult  # short post-shot cooldown
		var damage_min := 12.0
		var damage_max := 45.0
		var t: float = clampf((charge_t - 0.4) / 1.1, 0.0, 1.0)
		var damage: float = damage_min + (damage_max - damage_min) * t
		_spawn_proj(global_position + aim_dir * (radius + 4), aim_dir * (520.0 + 200.0 * t), damage * dmg_mult, Color(1.0, 0.95, 0.5), 2.5, 5.0, 0)
	# RMB: armor-piercing bolt (pierces).
	if _in_secondary_pressed and _cast2_cd <= 0:
		_cast2_cd = 6.0 * cooldown_mult
		_spawn_proj(global_position + aim_dir * (radius + 4), aim_dir * 700.0, 60.0 * dmg_mult, Color(1.0, 0.6, 0.2), 2.5, 6.0, 6)
	# Space: roll with iframes.
	if _in_utility_pressed and _util_cd <= 0:
		_util_cd = 5.0 * cooldown_mult
		var dir: Vector2 = _in_move if _in_move.length_squared() > 0.01 else aim_dir
		global_position += dir.normalized() * 160.0
		iframes_until = _now() + 0.5

# ---- Helpers ------------------------------------------------------------

func _aoe_damage_enemies(center: Vector2, r: float, dmg: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if center.distance_to(e.global_position) <= r:
			if e.has_method("apply_damage"):
				e.apply_damage(dmg, "player")
				if lifesteal > 0:
					heal(dmg * lifesteal)

func _nearest_enemy(max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _nearest_enemy_excluding(from: Vector2, max_d: float, exclude: Array) -> Node2D:
	var best: Node2D = null
	var best_d := max_d
	for e in get_tree().get_nodes_in_group("enemies"):
		if exclude.has(e):
			continue
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _spawn_proj(pos: Vector2, vel: Vector2, dmg: float, color: Color, life: float, r: float, pierce: int) -> void:
	if not GameState.is_authority():
		return
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	arena.spawn_projectile({
		"pos": pos,
		"vel": vel,
		"damage": dmg,
		"lifetime": life,
		"team": "player",
		"color": color,
		"radius": r,
		"pierce": pierce,
	})

# ---- Damage / Heal / Buffs ---------------------------------------------

func apply_damage(amount: float, _src_team: String) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	if _now() < iframes_until:
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		_go_down()

func _go_down() -> void:
	alive = false
	downed_until = _now() + RESPAWN_DELAY
	# Check wipe.
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("check_wipe"):
		arena.check_wipe()

func _respawn() -> void:
	# Snap to centroid of alive players, half hp.
	var sum := Vector2.ZERO
	var count := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p == self:
			continue
		if p.alive:
			sum += p.global_position
			count += 1
	if count > 0:
		global_position = sum / count
	alive = true
	hp = max_hp * 0.5
	mp = max_mp * 0.5
	iframes_until = _now() + 1.0

func heal(amount: float) -> void:
	if not GameState.is_authority():
		return
	if not alive:
		return
	hp = min(hp + amount, max_hp)

# Temporary buff (+spd, +dmg) for duration. Implemented as scheduled revert.
func apply_temp_buff(spd_bonus: float, dmg_bonus: float, duration: float) -> void:
	if not GameState.is_authority():
		return
	move_speed_bonus += spd_bonus
	dmg_mult += dmg_bonus
	# Use a child Timer so it's freed with the player on scene change / despawn.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = duration
	t.autostart = true
	add_child(t)
	t.timeout.connect(func ():
		if not is_instance_valid(self):
			return
		move_speed_bonus -= spd_bonus
		dmg_mult -= dmg_bonus
		t.queue_free()
	)

# Apply an upgrade by id (host-side, replicated via synced fields).
func apply_upgrade(id: String) -> void:
	if not GameState.is_authority():
		return
	match id:
		"max_hp":
			max_hp_bonus += 20
			max_hp = base_max_hp + max_hp_bonus
			hp = min(hp + 20, max_hp)
		"move_speed":
			move_speed_bonus += 0.10
		"damage":
			dmg_mult += 0.10
		"atk_speed":
			atk_speed_mult += 0.10
		"range":
			range_mult += 0.10
		"cooldown":
			cooldown_mult = max(cooldown_mult - 0.08, 0.4)
		"regen":
			hp_regen += 1.0
		"lifesteal":
			lifesteal += 0.05
		"mana_cap":
			max_mp_bonus += 25
			max_mp = base_max_mp + max_mp_bonus
		"mana_regen":
			mana_regen_bonus += 3.0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---- Berserker visual FX -----------------------------------------------

func _draw_berserker_fx() -> void:
	# Auto-swirl: two arcs spinning around self, fade ~0.25s.
	var ta := _fx_age("auto")
	if ta >= 0.0 and ta < 0.25:
		var k: float = 1.0 - ta / 0.25
		var r: float = max(_fx_radius("auto"), 1.0)
		var spin: float = ta * 18.0
		draw_arc(Vector2.ZERO, r, spin, spin + PI, 32, Color(1, 0.95, 0.6, 0.45 * k), 6.0)
		draw_arc(Vector2.ZERO, r, spin + PI, spin + TAU, 32, Color(1, 0.7, 0.3, 0.35 * k), 4.0)
	# Dash trail: thick translucent line from start to current position.
	var td := _fx_age("dash")
	if td >= 0.0 and td < 0.4:
		var k2: float = 1.0 - td / 0.4
		var local_start: Vector2 = _fx_dash_start - global_position
		draw_line(Vector2.ZERO, local_start, Color(1, 0.25, 0.25, 0.55 * k2), 10.0)
		# Hit-burst at end (current pos).
		var burst_r: float = max(_fx_radius("dash"), 1.0)
		draw_arc(Vector2.ZERO, burst_r * (0.6 + 0.4 * (1.0 - k2)), 0, TAU, 32, Color(1, 0.5, 0.3, 0.5 * k2), 3.0)
	# Roar: red expanding ring out to roar radius, ~0.6s.
	var tr := _fx_age("roar")
	if tr >= 0.0 and tr < 0.6:
		var k3: float = 1.0 - tr / 0.6
		var rmax := _fx_radius("roar")
		var rcur := rmax * clampf(tr / 0.55, 0.0, 1.0)
		draw_arc(Vector2.ZERO, rcur, 0, TAU, 64, Color(1, 0.35, 0.35, 0.55 * k3), 4.0)
	# Quake: brown shockwave + cracks, ~0.55s.
	var tq := _fx_age("quake")
	if tq >= 0.0 and tq < 0.55:
		var k4: float = 1.0 - tq / 0.55
		var qmax := _fx_radius("quake")
		var qr := qmax * clampf(tq / 0.5, 0.0, 1.0)
		draw_arc(Vector2.ZERO, qr, 0, TAU, 56, Color(0.85, 0.55, 0.25, 0.6 * k4), 6.0)
		# Cracks: 6 short radial lines from center to half radius.
		for i in 6:
			var ang: float = i * (TAU / 6.0)
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(dir * (qr * 0.2), dir * (qr * 0.7), Color(0.7, 0.4, 0.2, 0.5 * k4), 3.0)

# ---- Visual FX (host announces, each peer fades locally) -----------------

func _emit_fx(kind: String, world_pos: Vector2, radius_hint: float) -> void:
	if not GameState.is_authority():
		return
	if multiplayer.multiplayer_peer != null:
		_rpc_play_fx.rpc(kind, world_pos, radius_hint)
	else:
		_rpc_play_fx(kind, world_pos, radius_hint)

@rpc("authority", "reliable", "call_local")
func _rpc_play_fx(kind: String, world_pos: Vector2, radius_hint: float) -> void:
	_fx_local[kind] = {"t": _now(), "r": radius_hint}
	if kind == "dash":
		_fx_dash_start = world_pos

func _fx_age(kind: String) -> float:
	var d: Variant = _fx_local.get(kind)
	if d == null:
		return -1.0
	return _now() - float(d.t)

func _fx_radius(kind: String) -> float:
	var d: Variant = _fx_local.get(kind)
	if d == null:
		return 0.0
	return float(d.r)

func _draw() -> void:
	# Body.
	var col: Color = color_hint
	if not alive:
		col = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.6)
	var tex: Texture2D = CLASS_SPRITES.get(klass)
	if tex != null:
		var tint := Color(1, 1, 1, 0.55) if not alive else Color(1, 1, 1, 1)
		var s: float = radius * SPRITE_SIZE_MULT
		draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2.ONE)
		draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, radius, col)
		# Aim pip only when no sprite.
		draw_line(Vector2.ZERO, aim_dir * (radius + 6), Color(1, 1, 1, 0.7), 2.0)
	if klass == "berserker":
		_draw_berserker_fx()
	# HP bar.
	var w := 40.0
	var h := 4.0
	var top := Vector2(-w * 0.5, -radius - 14)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
	var ratio: float = clampf(hp / max(max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.3, 0.95, 0.3))
	# MP bar (if applicable).
	if max_mp > 0:
		var top2 := Vector2(-w * 0.5, -radius - 8)
		draw_rect(Rect2(top2, Vector2(w, h)), Color(0.1, 0.1, 0.15))
		var ratio2: float = clampf(mp / max_mp, 0.0, 1.0)
		draw_rect(Rect2(top2, Vector2(w * ratio2, h)), Color(0.3, 0.5, 0.95))
	# Down indicator.
	if not alive:
		draw_arc(Vector2.ZERO, radius + 6, 0, TAU, 32, Color(1, 0.4, 0.4, 0.6), 2.0)
	# Charge bar (crossbow).
	if klass == "crossbow" and charge_started_at >= 0:
		var ct: float = clampf(_now() - charge_started_at, 0.0, 1.5) / 1.5
		var top3 := Vector2(-w * 0.5, radius + 4)
		draw_rect(Rect2(top3, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(top3, Vector2(w * ct, h)), Color(1.0, 0.85, 0.3))
