extends Node

# Listens for enemy_killed on the host, awards XP to the party, and emits
# level_up when thresholds are crossed. Replicates xp/level snapshots to
# clients via a host RPC routed through this node.

func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)

func _on_enemy_killed(enemy: Node, _killer_peer: int) -> void:
	if not GameState.is_authority():
		return
	GameState.party_xp += enemy.xp_value
	while GameState.party_xp >= GameState.xp_threshold(GameState.party_level):
		GameState.party_xp -= GameState.xp_threshold(GameState.party_level)
		GameState.party_level += 1
		EventBus.level_up.emit(GameState.party_level)
		GameState.party_level_changed.emit(GameState.party_level)
	EventBus.xp_gained.emit(enemy.xp_value, GameState.party_xp)
	if GameState.is_networked():
		_rpc_sync.rpc(GameState.party_xp, GameState.party_level)

@rpc("authority", "reliable", "call_remote")
func _rpc_sync(xp: int, lvl: int) -> void:
	GameState.party_xp = xp
	if lvl != GameState.party_level:
		GameState.party_level = lvl
		GameState.party_level_changed.emit(lvl)
