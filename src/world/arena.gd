extends Node2D

# Thin scene-composition root. Owns the MultiplayerSpawners and the
# spawn factories. Run lifecycle, XP, upgrades, and waves live in their own
# child nodes — arena just wires them together and exposes spawn helpers.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")
const PROJECTILE_SCENE := preload("res://src/projectiles/projectile.tscn")
const DAMAGE_NUMBER_SCRIPT := preload("res://src/ui/damage_number.gd")

@onready var players_container: Node = $PlayersContainer
@onready var enemies_container: Node = $EnemiesContainer
@onready var projectiles_container: Node = $ProjectilesContainer
@onready var players_spawner: MultiplayerSpawner = $PlayersSpawner
@onready var enemies_spawner: MultiplayerSpawner = $EnemiesSpawner
@onready var projectiles_spawner: MultiplayerSpawner = $ProjectilesSpawner

func _ready() -> void:
	add_to_group("arena")
	players_spawner.spawn_path = NodePath("../PlayersContainer")
	enemies_spawner.spawn_path = NodePath("../EnemiesContainer")
	projectiles_spawner.spawn_path = NodePath("../ProjectilesContainer")
	players_spawner.spawn_function = _spawn_player
	enemies_spawner.spawn_function = _spawn_enemy
	projectiles_spawner.spawn_function = _spawn_projectile

	if GameState.is_authority():
		_host_spawn_roster()

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
	if pr.team == "player":
		pr.collision_layer = 1 << 3
		pr.collision_mask = 1 << 2
	else:
		pr.collision_layer = 1 << 4
		pr.collision_mask = 1 << 1
	pr.set_multiplayer_authority(1)
	return pr

# ---- Public spawn helpers ----------------------------------------------

func spawn_enemy(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	enemies_spawner.spawn(data)

func spawn_projectile(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	projectiles_spawner.spawn(data)

func spawn_damage_number(amount: float, world_pos: Vector2) -> void:
	# Local-only visual; called on every peer in response to enemy.apply_damage RPC.
	var n := Node2D.new()
	n.set_script(DAMAGE_NUMBER_SCRIPT)
	n.amount = int(round(amount))
	n.crit = amount >= 30.0
	n.position = world_pos + Vector2(0, -20)
	add_child(n)

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
		players_spawner.spawn({
			"peer_id": int(pid),
			"nick": entry.get("nick", "P"),
			"klass": String(entry.get("klass", &"berserker")),
			"pos": pos,
		})
		i += 1
