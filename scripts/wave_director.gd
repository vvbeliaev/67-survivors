extends Node

# Host-only authority. Spawns enemies in rings around the centroid based on
# elapsed run time. Drives the boss spawn at the end.

@export var spawn_radius_min: float = 700.0
@export var spawn_radius_max: float = 900.0

var _rng := RandomNumberGenerator.new()
var _spawn_accum: float = 0.0
var _burst_accum: float = 0.0
var _boss_spawned: bool = false

func _ready() -> void:
	_rng.randomize()

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	if not GameState.run_active:
		return
	var t := GameState.run_time
	if t >= GameState.RUN_DURATION:
		if not _boss_spawned:
			_boss_spawned = true
			_spawn_boss()
		return
	var rules := _rules_for_time(t)
	_spawn_accum += delta
	if _spawn_accum >= rules.interval:
		_spawn_accum = 0.0
		var n: int = rules.batch
		for _i in n:
			_spawn_one(rules.types)
	# Burst every 60 seconds in band 2+.
	_burst_accum += delta
	if rules.burst and _burst_accum >= 60.0:
		_burst_accum = 0.0
		for _i in 10:
			_spawn_one(rules.types)

func _rules_for_time(t: float) -> Dictionary:
	if t < 120.0:
		return {"interval": 2.5, "batch": 2, "types": ["rusher"], "burst": false}
	if t < 300.0:
		return {"interval": 2.0, "batch": 3, "types": ["rusher", "ranged"], "burst": true}
	if t < 480.0:
		return {"interval": 1.8, "batch": 3, "types": ["rusher", "ranged", "tank"], "burst": true}
	return {"interval": 1.4, "batch": 5, "types": ["rusher", "ranged", "tank"], "burst": true}

func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.alive:
			sum += p.global_position
			count += 1
	if count == 0:
		for p in get_tree().get_nodes_in_group("players"):
			sum += p.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / count

func _spawn_one(types: Array) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	var t: String = types[_rng.randi() % types.size()]
	var ang := _rng.randf() * TAU
	var rad := _rng.randf_range(spawn_radius_min, spawn_radius_max)
	var pos := _centroid() + Vector2(cos(ang), sin(ang)) * rad
	arena.spawn_enemy({"type": t, "pos": pos})

func _spawn_boss() -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	# Spawn boss right above the centroid.
	arena.spawn_enemy({"type": "boss", "pos": _centroid() + Vector2(0, -300)})
