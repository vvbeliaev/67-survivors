extends Node

# Owns the run lifecycle: time tick, wipe detection, win detection, and the
# RPCs that broadcast run-state changes to peers. Consumes EventBus signals
# so it can stay decoupled from arena/wave_director internals.

var _ended: bool = false

func _ready() -> void:
	add_to_group("run_director")
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.xp_gained.connect(_on_xp_gained)
	if GameState.is_authority():
		GameState.reset_run()
		GameState.run_active = true
		EventBus.run_started.emit()
		if GameState.is_networked():
			_rpc_set_run_state.rpc(true, false, 0, 0, 0, 0.0)

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	if not GameState.run_active:
		return
	GameState.run_time += delta
	if int(GameState.run_time * 5) != int((GameState.run_time - delta) * 5):
		EventBus.time_synced.emit(GameState.run_time)
		if GameState.is_networked():
			_rpc_sync_time.rpc(GameState.run_time)

func _on_player_downed(_peer_id: int) -> void:
	if not GameState.is_authority():
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.alive:
			return
	_end(false)

func _on_enemy_killed(enemy: Node, _killer: int) -> void:
	if not GameState.is_authority():
		return
	GameState.run_kills += 1
	var boss_id: StringName = &"boss"
	if Defs.wave_set != null:
		boss_id = Defs.wave_set.boss_id
	if enemy.enemy_type == boss_id:
		_end(true)

func _on_damage_dealt(target: Node, amount: float, src_team: String) -> void:
	if not GameState.is_authority():
		return
	if src_team != "player":
		return
	if target == null or not is_instance_valid(target) or not target.is_in_group("enemies"):
		return
	GameState.run_damage += int(round(amount))

func _on_xp_gained(amount: int, _total: int) -> void:
	if not GameState.is_authority():
		return
	GameState.run_xp_gained += amount

func _end(won: bool) -> void:
	if _ended:
		return
	_ended = true
	GameState.run_active = false
	EventBus.run_ended.emit(won)
	GameState.run_state_changed.emit(false, won)
	if GameState.is_networked():
		_rpc_set_run_state.rpc(
			false, won,
			GameState.run_kills, GameState.run_damage, GameState.run_xp_gained,
			GameState.run_time,
		)

@rpc("authority", "reliable", "call_remote")
func _rpc_set_run_state(active: bool, won: bool, kills: int, dmg: int, xp_gained: int, t: float) -> void:
	GameState.run_active = active
	if not active:
		GameState.run_kills = kills
		GameState.run_damage = dmg
		GameState.run_xp_gained = xp_gained
		GameState.run_time = t
	GameState.run_state_changed.emit(active, won)
	if not active:
		EventBus.run_ended.emit(won)

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_sync_time(t: float) -> void:
	GameState.run_time = t
	EventBus.time_synced.emit(t)
