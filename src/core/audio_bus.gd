extends Node

# Authoritative audio dispatcher. Sim authority calls `play_at(id, pos)`;
# the call is fan-outed to every peer (including local) via RPC, so each
# client renders the sound locally as an AudioStreamPlayer2D placed in the
# arena. UI sounds are pure-local (`play_ui`) — used in lobby and HUD before
# replication exists.
#
# Convention: SFX id maps 1:1 to file at `res://assets/audio/sfx/<id>.ogg`.
# Streams are cached on first lookup. Add a sound = drop a file with the
# right name; no code change in this bus.

const SFX_DIR := "res://assets/audio/sfx/"
const SFX_BUS := &"Master"
const MAX_DISTANCE := 1400.0
const ATTENUATION := 1.5

var _stream_cache: Dictionary = {}                 # StringName -> AudioStream
var _last_played_at: Dictionary = {}               # StringName -> float (sec)
const MIN_REPLAY_INTERVAL := 0.04                  # de-dupe storms (AoE hits)

# Subscribe to gameplay events so callsites stay clean.
func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.level_up.connect(_on_level_up)
	EventBus.xp_gained.connect(_on_xp_gained)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)

# ---- Public API ---------------------------------------------------------

# Authority-only. Plays positional SFX on every peer.
func play_at(id: StringName, pos: Vector2) -> void:
	if not GameState.is_authority():
		return
	if _suppress_storm(id):
		return
	if multiplayer.multiplayer_peer != null:
		_rpc_play_at.rpc(id, pos)
	else:
		_rpc_play_at(id, pos)

# Pure-local UI sound (no networking). Safe to call from any peer.
func play_ui(id: StringName, volume_db: float = 0.0) -> void:
	var s := _load_stream(id)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = SFX_BUS
	p.volume_db = volume_db
	p.autoplay = true
	get_tree().root.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)

# ---- Internals ----------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_play_at(id: StringName, pos: Vector2) -> void:
	var s := _load_stream(id)
	if s == null:
		return
	var arena := get_tree().get_first_node_in_group("arena")
	var parent: Node = arena if arena != null else get_tree().root
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = SFX_BUS
	p.global_position = pos
	p.max_distance = MAX_DISTANCE
	p.attenuation = ATTENUATION
	p.autoplay = true
	parent.add_child.call_deferred(p)
	p.finished.connect(p.queue_free)

func _load_stream(id: StringName) -> AudioStream:
	if _stream_cache.has(id):
		return _stream_cache[id]
	var path: String = SFX_DIR + String(id) + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("AudioBus: missing SFX " + path)
		_stream_cache[id] = null
		return null
	var s: AudioStream = load(path)
	_stream_cache[id] = s
	return s

func _suppress_storm(id: StringName) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var prev: float = float(_last_played_at.get(id, -999.0))
	if now - prev < MIN_REPLAY_INTERVAL:
		return true
	_last_played_at[id] = now
	return false

# ---- EventBus subscribers ----------------------------------------------

func _on_damage_dealt(target: Node, _amount: float, _src_team: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var pos: Vector2 = target.global_position if target.has_method("get") else Vector2.ZERO
	if target.is_in_group("enemies"):
		play_at(&"enemy_hit", pos)
	elif target.is_in_group("players") or target.is_in_group("decoys"):
		# Чучело — фейковый игрок и звучит так же, чтобы попадание считывалось.
		play_at(&"player_hit", pos)

func _on_enemy_killed(enemy: Node, _killer_peer: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	play_at(&"enemy_death", enemy.global_position)

func _on_player_downed(peer_id: int) -> void:
	var pos := _player_pos(peer_id)
	play_at(&"player_death", pos)

func _on_level_up(_new_level: int) -> void:
	play_at(&"level_up", _party_centroid())

func _on_xp_gained(_amount: int, _total: int) -> void:
	play_at(&"pickup_xp", _party_centroid())

func _on_run_started() -> void:
	play_at(&"boss_spawn", _party_centroid())

func _on_run_ended(_won: bool) -> void:
	pass

# ---- Helpers ------------------------------------------------------------

func _player_pos(peer_id: int) -> Vector2:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == peer_id:
			return p.global_position
	return Vector2.ZERO

func _party_centroid() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		sum += p.global_position
		n += 1
	if n == 0:
		return Vector2.ZERO
	return sum / float(n)
