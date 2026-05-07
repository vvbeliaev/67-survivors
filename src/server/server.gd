extends Node

# Headless dedicated server. Binds a port (WebSocket by default — the deploy
# pipeline puts nginx in front and serves the HTML5 client on :80) and waits.
# The round starts automatically once every connected player clicks "Готов!"
# in the lobby — handled by Network._check_all_ready(), no special server
# logic needed.
#
# Usage (on a VPS, behind nginx):
#   godot --headless --path /srv/67-survivors res://src/server/server.tscn \
#         -- --port 7777 --transport ws --bind 127.0.0.1
#
# Local desktop LAN (legacy ENet/UDP):
#   godot --headless --path . res://src/server/server.tscn \
#         -- --port 7777 --transport enet

const DEFAULT_PORT := 7777
const DEFAULT_TRANSPORT := "ws"
const DEFAULT_BIND := "127.0.0.1"

func _ready() -> void:
	var port := DEFAULT_PORT
	var transport := DEFAULT_TRANSPORT
	var bind_addr := DEFAULT_BIND
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
			i += 2
			continue
		if a == "--transport" and i + 1 < args.size():
			transport = String(args[i + 1]).to_lower()
			i += 2
			continue
		if a == "--bind" and i + 1 < args.size():
			bind_addr = String(args[i + 1])
			i += 2
			continue
		i += 1

	var err: int
	if transport == "enet":
		err = Network.host_dedicated(port)
	elif transport == "ws":
		err = Network.host_dedicated_ws(port, bind_addr)
	else:
		push_error("[server] unknown --transport %s (expected ws|enet)" % transport)
		get_tree().quit(2)
		return

	if err != OK:
		push_error("[server] cannot bind :%d (%s) — %s" % [port, transport, error_string(err)])
		get_tree().quit(1)
		return

	var bind_human := bind_addr if transport == "ws" else "0.0.0.0"
	print("[server] %s listening on %s:%d — waiting for players to ready up" % [transport, bind_human, port])
	Network.lobby_updated.connect(func():
		print("[server] roster: %d player(s)" % GameState.roster.size())
	)
