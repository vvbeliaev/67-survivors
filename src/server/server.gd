extends Node

# Headless dedicated server. Binds an ENet port, waits for --min-players
# clients to join, then fires the round start RPC so everyone loads the arena.
#
# Usage (on your VPS):
#   godot --headless --path /srv/67-survivors res://src/server/server.tscn \
#         -- --port 7777 --min-players 2
#
# Clients connect from the lobby: enter server IP, click Join. When enough
# players are connected the server starts automatically — no Start button needed.

const DEFAULT_PORT      := 7777
const DEFAULT_MIN_PLAYERS := 2

var _port: int        = DEFAULT_PORT
var _min_players: int = DEFAULT_MIN_PLAYERS
var _started: bool    = false

func _ready() -> void:
	_parse_args()
	var err := Network.host_dedicated(_port)
	if err != OK:
		push_error("[server] cannot bind :%d — %s" % [_port, error_string(err)])
		get_tree().quit(1)
		return
	print("[server] listening on :%d, need %d player(s)" % [_port, _min_players])
	Network.lobby_updated.connect(_on_lobby_updated)

func _parse_args() -> void:
	# OS.get_cmdline_user_args() returns everything after `--` in the command line.
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			_port = int(args[i + 1])
		elif args[i] == "--min-players" and i + 1 < args.size():
			_min_players = int(args[i + 1])

func _on_lobby_updated() -> void:
	if _started:
		return
	var count := GameState.roster.size()
	print("[server] roster %d/%d" % [count, _min_players])
	if count >= _min_players:
		_started = true
		print("[server] starting round")
		Network.request_start_round()
