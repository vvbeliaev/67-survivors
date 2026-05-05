extends Node

# Headless dedicated server. Binds an ENet port and waits. The round starts
# automatically once every connected player clicks "Готов!" in the lobby —
# handled by Network._check_all_ready(), no special server logic needed.
#
# Usage (on your VPS):
#   godot --headless --path /srv/67-survivors res://src/server/server.tscn \
#         -- --port 7777

const DEFAULT_PORT := 7777

func _ready() -> void:
	var port := DEFAULT_PORT
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])

	var err := Network.host_dedicated(port)
	if err != OK:
		push_error("[server] cannot bind :%d — %s" % [port, error_string(err)])
		get_tree().quit(1)
		return

	print("[server] listening on :%d — waiting for players to ready up" % port)
	Network.lobby_updated.connect(func():
		print("[server] roster: %d player(s)" % GameState.roster.size())
	)
