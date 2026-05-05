extends Node

const DEFAULT_PORT := 7777
const MAX_PEERS := 8

func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err

func leave() -> void:
	multiplayer.multiplayer_peer = null
