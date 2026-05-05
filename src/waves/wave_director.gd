extends Node

# Host-only spawner. Reads phases from a WaveSet (designer-edited) and
# spawns enemies in rings around the centroid. Drives boss spawn at the end.

var _rng := RandomNumberGenerator.new()
var _spawn_accum: float = 0.0
var _burst_accum: float = 0.0
var _boss_spawned: bool = false
var _wave_set: WaveSet = null

func _ready() -> void:
	_rng.randomize()
	_wave_set = Defs.wave_set
	if _wave_set == null:
		push_warning("WaveDirector: no WaveSet loaded")

func _physics_process(delta: float) -> void:
	if _wave_set == null:
		return
	if not GameState.is_authority():
		return
	if not GameState.run_active:
		return
	var t: float = GameState.run_time
	if t >= _wave_set.run_duration:
		if not _boss_spawned:
			_boss_spawned = true
			_spawn_boss()
		return
	var phase: WavePhase = _wave_set.phase_for(t)
	if phase == null:
		return
	_spawn_accum += delta
	if _spawn_accum >= phase.spawn_interval:
		_spawn_accum = 0.0
		for _i in phase.batch_size:
			_spawn_one(phase.enemy_types)
	if phase.burst_enabled:
		_burst_accum += delta
		if _burst_accum >= phase.burst_interval:
			_burst_accum = 0.0
			for _i in phase.burst_size:
				_spawn_one(phase.enemy_types)
	else:
		_burst_accum = 0.0

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
	return sum / float(count)

func _spawn_one(types: Array) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null or types.is_empty():
		return
	var t: StringName = types[_rng.randi() % types.size()]
	var ang := _rng.randf() * TAU
	var rad := _rng.randf_range(_wave_set.spawn_radius_min, _wave_set.spawn_radius_max)
	var pos := _centroid() + Vector2(cos(ang), sin(ang)) * rad
	arena.spawn_enemy({"type": String(t), "pos": pos})

func _spawn_boss() -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	arena.spawn_enemy({"type": String(_wave_set.boss_id), "pos": _centroid() + Vector2(0, -300)})
