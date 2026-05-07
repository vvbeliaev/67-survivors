extends Node

# Host/join + roster sync. Owns lobby-level connectivity. The arena scene
# is loaded after `request_start_round()` is acknowledged across peers.
# Two transports supported:
#   - ENet (UDP) — for desktop LAN play.
#   - WebSocket — for browser clients connecting through a reverse proxy.
# Server.gd picks transport via --transport ws|enet (default ws for deploys).

const DEFAULT_PORT := 7777
const MAX_PEERS := 8
const ARENA_SCENE_PATH := "res://src/world/arena.tscn"
const JOIN_TIMEOUT_SEC := 6.0

signal lobby_updated
signal start_round_requested
signal ready_state_changed
signal join_started(address: String, port: int)
signal join_failed(address: String, port: int, reason: String)

# peer_id → bool (mirrors of who has clicked "Ready").
var _ready_set: Array[int] = []
var _pending_address: String = ""
var _pending_port: int = 0
var _join_session: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		_register_self()
	return err

# Dedicated-server variant: binds the port but does NOT add the server
# process itself to the roster. Only connecting players appear as peers.
func host_dedicated(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

# WebSocket dedicated server. Binds to `bind_address` (default: localhost,
# so a reverse proxy like nginx can sit in front and terminate TLS / serve
# the HTML5 client on :80/:443). Set bind_address="*" to expose directly.
func host_dedicated_ws(port: int = DEFAULT_PORT, bind_address: String = "127.0.0.1") -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, bind_address)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		join_failed.emit(address, port, "не удалось создать клиент")
		return err
	multiplayer.multiplayer_peer = peer
	_pending_address = address
	_pending_port = port
	_join_session += 1
	var session := _join_session
	get_tree().create_timer(JOIN_TIMEOUT_SEC).timeout.connect(_on_join_timeout.bind(session))
	join_started.emit(address, port)
	lobby_updated.emit()
	return OK

# WebSocket client. Accepts a full url (ws://host[:port]/path or wss://...).
func join_ws(url: String) -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		join_failed.emit(url, 0, "не удалось создать ws-клиент")
		return err
	multiplayer.multiplayer_peer = peer
	_pending_address = url
	_pending_port = 0
	_join_session += 1
	var session := _join_session
	get_tree().create_timer(JOIN_TIMEOUT_SEC).timeout.connect(_on_join_timeout.bind(session))
	join_started.emit(url, 0)
	lobby_updated.emit()
	return OK

func is_join_pending() -> bool:
	if _pending_address.is_empty():
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING

func pending_address() -> String:
	return _pending_address

func pending_port() -> int:
	return _pending_port

func _on_join_timeout(session: int) -> void:
	if session != _join_session:
		return
	if _pending_address.is_empty():
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_fail_pending_join("сервер не отвечает")

func _fail_pending_join(reason: String) -> void:
	if _pending_address.is_empty():
		return
	var addr := _pending_address
	var port := _pending_port
	_clear_pending_join()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	GameState.roster.clear()
	_ready_set.clear()
	GameState.roster_changed.emit()
	join_failed.emit(addr, port, reason)
	lobby_updated.emit()

func _clear_pending_join() -> void:
	_pending_address = ""
	_pending_port = 0
	_join_session += 1

func leave() -> void:
	_clear_pending_join()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	GameState.roster.clear()
	_ready_set.clear()
	GameState.roster_changed.emit()

func _register_self() -> void:
	var id := multiplayer.get_unique_id()
	GameState.roster[id] = _entry(GameState.local_nick, GameState.local_class)
	GameState.roster_changed.emit()
	lobby_updated.emit()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for pid in GameState.roster.keys():
			rpc_id(id, "_rpc_set_roster_entry", pid, GameState.roster[pid])

func _on_peer_disconnected(id: int) -> void:
	GameState.roster.erase(id)
	_ready_set.erase(id)
	GameState.roster_changed.emit()
	lobby_updated.emit()
	if multiplayer.is_server():
		rpc("_rpc_remove_roster_entry", id)

func _on_connected_to_server() -> void:
	_clear_pending_join()
	var id := multiplayer.get_unique_id()
	GameState.roster[id] = _entry(GameState.local_nick, GameState.local_class)
	rpc_id(1, "_rpc_register_peer", GameState.local_nick, String(GameState.local_class))
	GameState.roster_changed.emit()
	lobby_updated.emit()

func _on_connection_failed() -> void:
	if not _pending_address.is_empty():
		_fail_pending_join("не удалось подключиться")
		return
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
	var k: StringName = StringName(klass)
	if not GameState.is_valid_class(k):
		k = &"berserker"
	var entry := _entry(nick, k)
	GameState.roster[id] = entry
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

func set_local_class(klass: StringName) -> void:
	if not GameState.is_valid_class(klass):
		return
	GameState.local_class = klass
	if multiplayer.multiplayer_peer == null:
		return
	var id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		var entry := _entry(GameState.local_nick, klass)
		GameState.roster[id] = entry
		rpc("_rpc_set_roster_entry", id, entry)
	else:
		rpc_id(1, "_rpc_register_peer", GameState.local_nick, String(klass))

func request_start_round() -> void:
	if multiplayer.is_server():
		rpc("_rpc_start_round")

@rpc("authority", "reliable", "call_local")
func _rpc_start_round() -> void:
	start_round_requested.emit()
	get_tree().change_scene_to_file(ARENA_SCENE_PATH)

func _entry(nick: String, klass: StringName) -> Dictionary:
	return {"nick": nick, "klass": klass}

# ---- Ready system ----------------------------------------------------------

func is_peer_ready(peer_id: int) -> bool:
	return _ready_set.has(peer_id)

# Called by the lobby Ready button. Offline → start immediately.
func set_local_ready(is_ready: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		if is_ready:
			request_start_round()
		return
	if multiplayer.is_server():
		_rpc_sync_ready.rpc(multiplayer.get_unique_id(), is_ready)
		_check_all_ready()
	else:
		_rpc_client_set_ready.rpc_id(1, is_ready)

@rpc("any_peer", "reliable")
func _rpc_client_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_rpc_sync_ready.rpc(sender, is_ready)
	_check_all_ready()

# Broadcasts ready-state change to every peer (including server via call_local).
@rpc("authority", "reliable", "call_local")
func _rpc_sync_ready(peer_id: int, is_ready: bool) -> void:
	if is_ready:
		if not _ready_set.has(peer_id):
			_ready_set.append(peer_id)
	else:
		_ready_set.erase(peer_id)
	ready_state_changed.emit()

func _check_all_ready() -> void:
	if not GameState.is_authority():
		return
	if GameState.roster.is_empty():
		return
	for pid in GameState.roster.keys():
		if not _ready_set.has(pid):
			return
	request_start_round()
