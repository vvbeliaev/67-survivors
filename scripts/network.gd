extends Node

const DEFAULT_PORT := 7777
const MAX_PEERS := 8

signal lobby_updated
signal start_round_requested

func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		_register_self()
	return err

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	GameState.roster.clear()
	GameState.roster_changed.emit()

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _register_self() -> void:
	var id := multiplayer.get_unique_id()
	GameState.roster[id] = {
		"nick": GameState.local_nick,
		"klass": GameState.local_class,
	}
	GameState.roster_changed.emit()
	lobby_updated.emit()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		# Send full roster to new peer.
		for pid in GameState.roster.keys():
			var entry: Dictionary = GameState.roster[pid]
			rpc_id(id, "_rpc_set_roster_entry", pid, entry)

func _on_peer_disconnected(id: int) -> void:
	GameState.roster.erase(id)
	GameState.roster_changed.emit()
	lobby_updated.emit()
	if multiplayer.is_server():
		rpc("_rpc_remove_roster_entry", id)

func _on_connected_to_server() -> void:
	# Tell server (and through it everyone else) about us.
	var id := multiplayer.get_unique_id()
	GameState.roster[id] = {
		"nick": GameState.local_nick,
		"klass": GameState.local_class,
	}
	rpc_id(1, "_rpc_register_peer", GameState.local_nick, GameState.local_class)
	GameState.roster_changed.emit()
	lobby_updated.emit()

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	lobby_updated.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	GameState.roster.clear()
	GameState.roster_changed.emit()
	lobby_updated.emit()

@rpc("any_peer", "reliable")
func _rpc_register_peer(nick: String, klass: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not GameState.VALID_CLASSES.has(klass):
		klass = "berserker"
	var entry := {"nick": nick, "klass": klass}
	GameState.roster[id] = entry
	# Broadcast to all peers (including the new one for confirmation).
	rpc("_rpc_set_roster_entry", id, entry)
	GameState.roster_changed.emit()
	lobby_updated.emit()

@rpc("authority", "reliable")
func _rpc_set_roster_entry(id: int, entry: Dictionary) -> void:
	GameState.roster[id] = entry
	GameState.roster_changed.emit()
	lobby_updated.emit()

@rpc("authority", "reliable")
func _rpc_remove_roster_entry(id: int) -> void:
	GameState.roster.erase(id)
	GameState.roster_changed.emit()
	lobby_updated.emit()

# Host can change a peer's class entry locally and broadcast.
func set_local_class(klass: String) -> void:
	if not GameState.VALID_CLASSES.has(klass):
		return
	GameState.local_class = klass
	if multiplayer.multiplayer_peer == null:
		return
	var id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		var entry := {"nick": GameState.local_nick, "klass": klass}
		GameState.roster[id] = entry
		rpc("_rpc_set_roster_entry", id, entry)
	else:
		rpc_id(1, "_rpc_register_peer", GameState.local_nick, klass)

func request_start_round() -> void:
	if multiplayer.is_server():
		rpc("_rpc_start_round")

@rpc("authority", "reliable", "call_local")
func _rpc_start_round() -> void:
	start_round_requested.emit()
	get_tree().change_scene_to_file("res://scenes/arena.tscn")
