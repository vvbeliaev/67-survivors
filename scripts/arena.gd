extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const DAMAGE_NUMBER_SCRIPT := preload("res://scripts/damage_number.gd")

@onready var players_container: Node = $PlayersContainer
@onready var enemies_container: Node = $EnemiesContainer
@onready var projectiles_container: Node = $ProjectilesContainer
@onready var players_spawner: MultiplayerSpawner = $PlayersSpawner
@onready var enemies_spawner: MultiplayerSpawner = $EnemiesSpawner
@onready var projectiles_spawner: MultiplayerSpawner = $ProjectilesSpawner
@onready var hud: CanvasLayer = $HUD

var _rng := RandomNumberGenerator.new()
var _ended: bool = false

func _ready() -> void:
	add_to_group("arena")
	_rng.randomize()

	players_spawner.spawn_path = NodePath("../PlayersContainer")
	enemies_spawner.spawn_path = NodePath("../EnemiesContainer")
	projectiles_spawner.spawn_path = NodePath("../ProjectilesContainer")
	players_spawner.spawn_function = _spawn_player
	enemies_spawner.spawn_function = _spawn_enemy
	projectiles_spawner.spawn_function = _spawn_projectile

	if GameState.is_authority():
		_host_spawn_roster()
		GameState.reset_run()
		GameState.run_active = true
		if multiplayer.multiplayer_peer != null:
			_rpc_set_run_state.rpc(true, false)

func _physics_process(delta: float) -> void:
	if GameState.is_authority():
		if GameState.run_active:
			GameState.run_time += delta
			if int(GameState.run_time * 5) != int((GameState.run_time - delta) * 5):
				if multiplayer.multiplayer_peer != null:
					_rpc_sync_time.rpc(GameState.run_time)

# ---- Spawn helpers (called by spawner callbacks) ------------------------

func _spawn_player(data: Variant) -> Node:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	p.peer_id = int(d.get("peer_id", 1))
	p.nick = String(d.get("nick", "P"))
	p.klass = String(d.get("klass", "berserker"))
	p.position = d.get("pos", Vector2.ZERO)
	# Scene-replicated authority stays with host (id 1) so the host runs physics.
	# Inputs travel via RPC from the owning peer.
	p.set_multiplayer_authority(1)
	return p

func _spawn_enemy(data: Variant) -> Node:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	var t: String = String(d.get("type", "rusher"))
	e.position = d.get("pos", Vector2.ZERO)
	_apply_enemy_archetype(e, t)
	e.set_multiplayer_authority(1)
	return e

func _spawn_projectile(data: Variant) -> Node:
	var pr: Area2D = PROJECTILE_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	pr.position = d.get("pos", Vector2.ZERO)
	pr.velocity = d.get("vel", Vector2.ZERO)
	pr.damage = d.get("damage", 0.0)
	pr.lifetime = d.get("lifetime", 2.0)
	pr.team = String(d.get("team", "player"))
	pr.color_hint = d.get("color", Color(1, 1, 1))
	pr.radius = d.get("radius", 6.0)
	pr.pierce = int(d.get("pierce", 0))
	# Layer/mask: player projectiles hit enemies; enemy projectiles hit players.
	if pr.team == "player":
		pr.collision_layer = 1 << 3  # PlayerProjectiles
		pr.collision_mask = 1 << 2   # Enemies
	else:
		pr.collision_layer = 1 << 4  # EnemyProjectiles
		pr.collision_mask = 1 << 1   # Players
	pr.set_multiplayer_authority(1)
	return pr

func _apply_enemy_archetype(e: Node, t: String) -> void:
	e.enemy_type = t
	var prev_radius: float = e.radius
	match t:
		"rusher":
			e.max_hp = 25.0
			e.hp = 25.0
			e.move_speed = 180.0
			e.contact_damage = 8.0
			e.contact_cd = 0.6
			e.ranged = false
			e.xp_value = 1
			e.color_hint = Color(0.95, 0.4, 0.4)
			e.radius = 12.0
		"ranged":
			e.max_hp = 18.0
			e.hp = 18.0
			e.move_speed = 110.0
			e.contact_damage = 0.0
			e.ranged = true
			e.ranged_dist = 250.0
			e.projectile_speed = 240.0
			e.projectile_damage = 6.0
			e.ranged_cd = 1.5
			e.xp_value = 2
			e.color_hint = Color(0.95, 0.65, 0.4)
			e.radius = 11.0
		"tank":
			e.max_hp = 120.0
			e.hp = 120.0
			e.move_speed = 90.0
			e.contact_damage = 18.0
			e.contact_cd = 1.0
			e.ranged = false
			e.xp_value = 5
			e.color_hint = Color(0.6, 0.4, 0.7)
			e.radius = 18.0
		"boss":
			e.max_hp = float(GameState.BOSS_HP)
			e.hp = e.max_hp
			e.move_speed = 100.0
			e.contact_damage = 30.0
			e.contact_cd = 1.0
			e.ranged = false
			e.xp_value = 50
			e.color_hint = Color(0.85, 0.2, 0.85)
			e.radius = 36.0
			e.boss_aoe = true
			e.boss_aoe_radius = 180.0
			e.boss_aoe_damage = 30.0
			e.boss_aoe_cd = 6.0
			e.boss_aoe_windup = 1.2
		_:
			pass
	if e.radius != prev_radius:
		var col := e.get_node_or_null("CollisionShape2D")
		if col != null and col.shape is CircleShape2D:
			# Duplicate so per-instance changes don't mutate the shared resource.
			var s: CircleShape2D = col.shape.duplicate()
			s.radius = e.radius
			col.shape = s

func spawn_enemy(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	enemies_spawner.spawn(data)

func spawn_projectile(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	projectiles_spawner.spawn(data)

func spawn_damage_number(amount: float, world_pos: Vector2) -> void:
	# Local-only visual; called on every peer in response to damage RPC.
	var n := Node2D.new()
	n.set_script(DAMAGE_NUMBER_SCRIPT)
	n.amount = int(round(amount))
	n.crit = amount >= 30.0
	n.position = world_pos + Vector2(0, -20)
	add_child(n)

# ---- Host roster spawn --------------------------------------------------

func _host_spawn_roster() -> void:
	if GameState.roster.is_empty():
		# Solo/no-net path: insert self.
		var id := 1
		GameState.roster[id] = {"nick": GameState.local_nick, "klass": GameState.local_class}
		GameState.roster_changed.emit()
	var i: int = 0
	var n: int = GameState.roster.size()
	for pid in GameState.roster.keys():
		var entry: Dictionary = GameState.roster[pid]
		var ang: float = TAU * float(i) / float(max(n, 1))
		var spread: float = 40.0 if n > 1 else 0.0
		var pos: Vector2 = Vector2(cos(ang), sin(ang)) * spread
		players_spawner.spawn({
			"peer_id": int(pid),
			"nick": entry.get("nick", "P"),
			"klass": entry.get("klass", "berserker"),
			"pos": pos,
		})
		i += 1

# ---- Enemy death → XP → level up --------------------------------------

func on_enemy_killed(e: Node) -> void:
	if not GameState.is_authority():
		return
	var xp_value: int = e.xp_value
	GameState.party_xp += xp_value
	while GameState.party_xp >= GameState.xp_threshold(GameState.party_level):
		GameState.party_xp -= GameState.xp_threshold(GameState.party_level)
		GameState.party_level += 1
		_offer_upgrades_for_level()
	if multiplayer.multiplayer_peer != null:
		_rpc_sync_xp.rpc(GameState.party_xp, GameState.party_level)
	if e.enemy_type == "boss":
		_end_run(true)

func _offer_upgrades_for_level() -> void:
	var has_peer := multiplayer.multiplayer_peer != null
	for pid in GameState.roster.keys():
		var picks := Upgrades.roll_three(_rng)
		var ids: PackedStringArray = []
		var labels: PackedStringArray = []
		for u in picks:
			ids.append(u.id)
			labels.append(u.label)
		if int(pid) == 1 or not has_peer:
			_rpc_show_upgrade(ids, labels)
		else:
			_rpc_show_upgrade.rpc_id(int(pid), ids, labels)

@rpc("authority", "reliable")
func _rpc_show_upgrade(ids: PackedStringArray, labels: PackedStringArray) -> void:
	var options: Array = []
	for i in ids.size():
		options.append({"id": ids[i], "label": labels[i]})
	hud.show_upgrade_picks(options)

func submit_upgrade_pick(id: String) -> void:
	if multiplayer.multiplayer_peer == null:
		_apply_upgrade_to_peer(1, id)
	elif multiplayer.is_server():
		_apply_upgrade_to_peer(1, id)
	else:
		_rpc_submit_upgrade.rpc_id(1, id)

@rpc("any_peer", "reliable")
func _rpc_submit_upgrade(id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_apply_upgrade_to_peer(sender, id)

func _apply_upgrade_to_peer(peer_id: int, id: String) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			p.apply_upgrade(id)
			return

# ---- Wipe / win / time sync --------------------------------------------

func check_wipe() -> void:
	if not GameState.is_authority():
		return
	var any_alive := false
	for p in get_tree().get_nodes_in_group("players"):
		if p.alive:
			any_alive = true
			break
	if not any_alive:
		_end_run(false)

func _end_run(won: bool) -> void:
	if _ended:
		return
	_ended = true
	GameState.run_active = false
	if multiplayer.multiplayer_peer != null:
		_rpc_set_run_state.rpc(false, won)
	hud.show_endgame(won)

@rpc("authority", "reliable", "call_remote")
func _rpc_set_run_state(active: bool, won: bool) -> void:
	GameState.run_active = active
	GameState.run_state_changed.emit(active, won)
	if not active:
		hud.show_endgame(won)

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_sync_time(t: float) -> void:
	GameState.run_time = t

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_xp(xp: int, lvl: int) -> void:
	GameState.party_xp = xp
	if lvl != GameState.party_level:
		GameState.party_level = lvl
		GameState.party_level_changed.emit(lvl)
