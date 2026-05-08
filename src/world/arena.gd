extends Node2D

# Thin scene-composition root. Owns the MultiplayerSpawners and the
# spawn factories. Run lifecycle, XP, upgrades, and waves live in their own
# child nodes — arena just wires them together and exposes spawn helpers.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")
const PROJECTILE_SCENE := preload("res://src/projectiles/projectile.tscn")
const ECHO_CLONE_SCENE := preload("res://src/skills/concrete/echo_clone.tscn")
const DAMAGE_NUMBER_SCRIPT := preload("res://src/ui/damage_number.gd")
const TORCH_SCENE := preload("res://src/world/torch.tscn")
const DEBUG_PANEL_SCENE := preload("res://src/debug/debug_panel.tscn")
# Concentric torch rings: 1 center torch plus four rings at growing radii.
# Each ring uses a different torch count (4, 6, 7, 8) so rings don't align
# radially and the eye picks up multiple rhythms at once. The half-step
# phase offset on alternate rings shifts them tangentially. Counts stay
# below what would fully light each ring's perimeter (light radius ≈ 512),
# so dark sections remain between adjacent torches.
# Rows: [count, radius, phase_steps] — phase_steps is fraction of one slot.
const TORCH_RINGS: Array = [
	[4, 550.0, 0.5],
	[6, 1100.0, 0.0],
	[7, 1600.0, 0.5],
	[8, 2050.0, 0.0],
]

@onready var players_container: Node = $PlayersContainer
@onready var enemies_container: Node = $EnemiesContainer
@onready var projectiles_container: Node = $ProjectilesContainer
@onready var players_spawner: MultiplayerSpawner = $PlayersSpawner
@onready var enemies_spawner: MultiplayerSpawner = $EnemiesSpawner
@onready var projectiles_spawner: MultiplayerSpawner = $ProjectilesSpawner
@onready var echo_clones_container: Node = $EchoClonesContainer
@onready var echo_clones_spawner: MultiplayerSpawner = $EchoClonesSpawner

func _ready() -> void:
	add_to_group("arena")
	players_spawner.spawn_path = NodePath("../PlayersContainer")
	enemies_spawner.spawn_path = NodePath("../EnemiesContainer")
	projectiles_spawner.spawn_path = NodePath("../ProjectilesContainer")
	players_spawner.spawn_function = _spawn_player
	enemies_spawner.spawn_function = _spawn_enemy
	projectiles_spawner.spawn_function = _spawn_projectile
	echo_clones_spawner.spawn_path = NodePath("../EchoClonesContainer")
	echo_clones_spawner.spawn_function = _spawn_echo_clone

	_spawn_torches()

	if GameState.debug_mode:
		add_child(DEBUG_PANEL_SCENE.instantiate())

	if GameState.is_authority():
		# Хост попадает сюда уже после того, как все клиенты загрузили арену —
		# Network.request_start_round дожидается ack-ов до смены сцены у хоста.
		# Поэтому RPC из дочерних _ready (RunDirector, MultiplayerSpawner-ы)
		# летят в уже существующее /root/Arena у клиентов. Спавним ростер сразу.
		_host_spawn_roster()
	else:
		# Клиент: подтверждаем хосту, что арена в дереве и spawnery готовы
		# принимать spawn-пакеты.
		Network.mark_self_arena_ready()

func _spawn_torches() -> void:
	# Deterministic by index, so positions match across peers without sync.
	var container := get_node_or_null("TorchesContainer")
	if container == null:
		return
	_place_torch(container, Vector2.ZERO)
	for ring in TORCH_RINGS:
		var count: int = int(ring[0])
		var radius: float = float(ring[1])
		var phase: float = float(ring[2])
		for i in count:
			var ang: float = TAU * (float(i) + phase) / float(count)
			_place_torch(container, Vector2(cos(ang), sin(ang)) * radius)

func _place_torch(container: Node, pos: Vector2) -> void:
	var torch: Node2D = TORCH_SCENE.instantiate()
	torch.position = pos
	container.add_child(torch)

# ---- Spawn factories (called by spawner callbacks) ---------------------

func _spawn_player(data: Variant) -> Node:
	var p: CharacterBody2D = PLAYER_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	var peer_id: int = int(d.get("peer_id", 1))
	var nick: String = String(d.get("nick", "P"))
	var klass: StringName = StringName(String(d.get("klass", "berserker")))
	p.position = d.get("pos", Vector2.ZERO)
	p.set_multiplayer_authority(1)
	p.setup(peer_id, nick, klass)
	return p

func _spawn_enemy(data: Variant) -> Node:
	var e: CharacterBody2D = ENEMY_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	var t: StringName = StringName(String(d.get("type", "rusher")))
	e.position = d.get("pos", Vector2.ZERO)
	var def: EnemyDef = Defs.enemy_def(t)
	if def != null:
		e.setup(def)
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
	pr.source_peer = int(d.get("source_peer", 0))
	pr.mana_on_hit_pct = float(d.get("mana_on_hit_pct", 0.0))
	pr.sprite_path = String(d.get("sprite_path", ""))
	pr.sprite_size = d.get("sprite_size", Vector2.ZERO)
	if pr.team == "player":
		pr.collision_layer = 1 << 3
		pr.collision_mask = 1 << 2
	else:
		pr.collision_layer = 1 << 4
		pr.collision_mask = 1 << 1
	pr.set_multiplayer_authority(1)
	return pr

func _spawn_echo_clone(data: Variant) -> Node:
	var c: Node2D = ECHO_CLONE_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	c.position = d.get("pos", Vector2.ZERO)
	c.owner_peer_id = int(d.get("owner_peer_id", 0))
	c.repeats_left = int(d.get("repeats", 3))
	c.set_multiplayer_authority(1)
	return c

# MultiplayerSpawner.spawn() requires a multiplayer_peer (ENet, WebSocket,
# OfflineMultiplayerPeer, ...). In true solo (no peer set — e.g. the debug
# arena entry-point) it ERR_FAIL_COND_V's and returns null. Bypass the
# spawner in that case by invoking the factory directly: there is no client
# to replicate to anyway, so the local node is the whole world.
func _spawn_via(spawner: MultiplayerSpawner, container: Node, factory: Callable, data: Variant) -> void:
	if multiplayer.has_multiplayer_peer():
		spawner.spawn(data)
		return
	var node: Node = factory.call(data)
	if node != null:
		container.add_child(node)

# ---- Public spawn helpers ----------------------------------------------

func spawn_enemy(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	_spawn_via(enemies_spawner, enemies_container, _spawn_enemy, data)

func spawn_projectile(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	_spawn_via(projectiles_spawner, projectiles_container, _spawn_projectile, data)

func spawn_echo_clone(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	_spawn_via(echo_clones_spawner, echo_clones_container, _spawn_echo_clone, data)

func spawn_damage_number(amount: float, world_pos: Vector2, crit: bool = false) -> void:
	var n := Node2D.new()
	n.set_script(DAMAGE_NUMBER_SCRIPT)
	n.amount = int(round(amount))
	n.crit = crit
	n.position = world_pos + Vector2(0, -20)
	add_child(n)
	EventBus.damage_number_spawned.emit(world_pos, n.amount, crit)

# ---- Roster --------------------------------------------------------------

func _host_spawn_roster() -> void:
	if GameState.roster.is_empty():
		GameState.roster[1] = {"nick": GameState.local_nick, "klass": GameState.local_class}
		GameState.roster_changed.emit()
	var i: int = 0
	var n: int = GameState.roster.size()
	for pid in GameState.roster.keys():
		var entry: Dictionary = GameState.roster[pid]
		var ang: float = TAU * float(i) / float(max(n, 1))
		var spread: float = 40.0 if n > 1 else 0.0
		var pos := Vector2(cos(ang), sin(ang)) * spread
		_spawn_via(players_spawner, players_container, _spawn_player, {
			"peer_id": int(pid),
			"nick": entry.get("nick", "P"),
			"klass": String(entry.get("klass", &"berserker")),
			"pos": pos,
		})
		i += 1
