extends Node

# Coordinates the level-up flow across the whole party. Host-only logic; the
# screen and submission are local. Steps:
#   1. EventBus.level_up fires on host.
#   2. Host pauses the tree (and broadcasts pause), rolls 3 picks per alive
#      peer, RPCs each peer's options + a party-status snapshot.
#   3. Each peer shows its LevelUpScreen and submits a pick (or skip) back.
#   4. Host applies the upgrade to that peer's Player and broadcasts a fresh
#      party-status snapshot so everyone sees the progress live.
#   5. When every alive peer has picked, host closes screens, unpauses, and
#      drains any queued level-ups (e.g. when one big XP grant crosses two
#      thresholds back-to-back).
#
# A peer that goes down while the screen is open is auto-skipped so the
# round can still complete.

const LEVEL_UP_SCREEN_SCRIPT := preload("res://src/ui/level_up_screen.gd")

var _rng := RandomNumberGenerator.new()

# Host-only round state.
var _open: bool = false
var _waiting: Dictionary = {}        # peer_id -> bool (true = haven't picked yet)
var _picks: Dictionary = {}          # peer_id -> {id: String, label: String}
var _pending_levels: Array[int] = [] # queued level-ups to resolve after the current round

func _ready() -> void:
	add_to_group("upgrade_offer")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	EventBus.level_up.connect(_on_level_up)
	EventBus.player_downed.connect(_on_player_downed)

# =========================================================================
# Round lifecycle (host only).
# =========================================================================

func _on_level_up(new_level: int) -> void:
	if not GameState.is_authority():
		return
	if _open:
		_pending_levels.append(new_level)
		return
	_start_round(new_level)

func _start_round(new_level: int) -> void:
	_open = true
	_waiting.clear()
	_picks.clear()

	var per_peer_ids: Dictionary = {}  # peer_id -> PackedStringArray
	for pid_var in GameState.roster.keys():
		var pid: int = int(pid_var)
		var player := _find_player(pid)
		if player == null or not bool(player.alive):
			print("[upgrade_offer] skip pid=%d (player_null=%s alive=%s)" %
				[pid, player == null, player != null and bool(player.alive)])
			continue
		_waiting[pid] = true
		var picks: Array = UpgradePool.roll_for(_rng, player, 3)
		_ensure_milestone_pick(picks, player, new_level)
		var ids: PackedStringArray = []
		for u in picks:
			ids.append(String(u.id))
		per_peer_ids[pid] = ids

	if _waiting.is_empty():
		# Whole party is down. Skip the round entirely; the level-up still
		# applies and waves continue. Game-over is handled elsewhere.
		_open = false
		return

	_set_paused_global(true)

	var summary: Array = _party_summary()
	print("[upgrade_offer] _start_round level=%d, peers waiting=%s" % [new_level, str(_waiting.keys())])
	for pid_var in per_peer_ids.keys():
		var pid: int = int(pid_var)
		var ids: PackedStringArray = per_peer_ids[pid]
		if pid == 1:
			print("[upgrade_offer] open local for host pid=1")
			_open_screen_local(ids, new_level, summary)
		else:
			print("[upgrade_offer] rpc_open_screen → pid=%d ids=%s" % [pid, str(ids)])
			_rpc_open_screen.rpc_id(pid, ids, new_level, summary)

func _finish_round() -> void:
	_close_screen_local()
	if GameState.is_networked():
		_rpc_close_screen.rpc()
	_set_paused_global(false)
	_open = false
	_waiting.clear()
	_picks.clear()
	if not _pending_levels.is_empty():
		var lvl: int = int(_pending_levels.pop_front())
		# Defer one frame so the unpause settles before re-entering.
		call_deferred("_start_round", lvl)

# Class-specific milestone upgrades. When a milestone level fires, the
# offered picks are *replaced* by the milestone defs (less the ones already
# taken) — no random fillers, no other upgrades. Returns silently when the
# (class, level) pair has no milestones, leaving the random picks untouched.
func _ensure_milestone_pick(picks: Array, player: Node, new_level: int) -> void:
	var milestone_ids: Array = _milestones_for(player, new_level)
	if milestone_ids.is_empty():
		return
	var milestone_picks: Array = []
	for mid_v in milestone_ids:
		var mid: StringName = mid_v
		var def: UpgradeDef = Defs.upgrade_def(mid)
		if def == null:
			continue
		if int(player._upgrade_stacks.get(mid, 0)) > 0:
			continue
		milestone_picks.append(def)
	if milestone_picks.is_empty():
		return
	picks.clear()
	picks.append_array(milestone_picks)

func _milestones_for(player: Node, new_level: int) -> Array:
	if new_level == 5 and player.klass == &"crossbow":
		return [&"crossbow_roll_volley", &"crossbow_charge_master", &"crossbow_bolt_damage"]
	return []

func _on_player_downed(peer_id: int) -> void:
	if not GameState.is_authority():
		return
	if not _open:
		return
	if _waiting.get(peer_id, false):
		# Force-skip so the round can complete without the downed peer.
		_record_pick(peer_id, "")

# =========================================================================
# Pick recording.
# =========================================================================

# Called locally by LevelUpScreen.
func submit_pick(id: String) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_record_pick(1, id)
	else:
		_rpc_submit.rpc_id(1, id)

@rpc("any_peer", "reliable")
func _rpc_submit(id: String) -> void:
	if not multiplayer.is_server():
		return
	_record_pick(multiplayer.get_remote_sender_id(), id)

func _record_pick(peer_id: int, id: String) -> void:
	if not _open:
		return
	if not _waiting.get(peer_id, false):
		return  # Already picked or never eligible.

	var label: String = "Пропуск"
	if id != "":
		var def: UpgradeDef = Defs.upgrade_def(StringName(id))
		if def != null:
			var player := _find_player(peer_id)
			if player != null:
				player.apply_upgrade_def(def)
				EventBus.upgrade_picked.emit(peer_id, def.id)
			label = String(def.display_name) if String(def.display_name) != "" else def.label
	_waiting[peer_id] = false
	_picks[peer_id] = {"id": id, "label": label}

	_broadcast_party_status()

	for v in _waiting.values():
		if v:
			return
	_finish_round()

# =========================================================================
# Cross-peer screen sync.
# =========================================================================

func _set_paused_global(p: bool) -> void:
	get_tree().paused = p
	if GameState.is_networked():
		_rpc_set_paused.rpc(p)

@rpc("authority", "reliable")
func _rpc_set_paused(p: bool) -> void:
	get_tree().paused = p

@rpc("authority", "reliable")
func _rpc_open_screen(ids: PackedStringArray, new_level: int, summary: Array) -> void:
	print("[upgrade_offer] rpc_open_screen received: level=%d ids=%s" % [new_level, str(ids)])
	_open_screen_local(ids, new_level, summary)

func _open_screen_local(ids: PackedStringArray, new_level: int, summary: Array) -> void:
	var screen := _ensure_screen()
	if screen == null:
		push_error("[upgrade_offer] _open_screen_local: screen is null (HUD missing?)")
		return
	var options: Array = []
	for s in ids:
		var def: UpgradeDef = Defs.upgrade_def(StringName(String(s)))
		if def != null:
			options.append(def)
	print("[upgrade_offer] _open_screen_local: opening with %d options" % options.size())
	screen.open(new_level, options, summary)
	print("[upgrade_offer] screen visible=%s" % str(screen.visible))

@rpc("authority", "reliable")
func _rpc_update_party_status(summary: Array) -> void:
	_update_party_status_local(summary)

func _broadcast_party_status() -> void:
	var summary: Array = _party_summary()
	_update_party_status_local(summary)
	if GameState.is_networked():
		_rpc_update_party_status.rpc(summary)

func _update_party_status_local(summary: Array) -> void:
	var screen := _get_screen()
	if screen != null:
		screen.update_party_status(summary)

@rpc("authority", "reliable")
func _rpc_close_screen() -> void:
	_close_screen_local()

func _close_screen_local() -> void:
	var screen := _get_screen()
	if screen != null:
		screen.close()

# =========================================================================
# Helpers.
# =========================================================================

func _party_summary() -> Array:
	var out: Array = []
	for pid_var in GameState.roster.keys():
		var pid: int = int(pid_var)
		var entry: Dictionary = GameState.roster[pid]
		var player := _find_player(pid)
		var alive: bool = player != null and bool(player.alive)
		var status: String = "dead"
		var label: String = ""
		if alive:
			if _waiting.get(pid, false):
				status = "waiting"
			elif _picks.has(pid):
				status = "picked"
				label = String(_picks[pid].get("label", ""))
		out.append({
			"peer_id": pid,
			"nick": String(entry.get("nick", "?")),
			"klass": String(entry.get("klass", "berserker")),
			"alive": alive,
			"status": status,
			"label": label,
		})
	return out

func _ensure_screen() -> Node:
	var screen := _get_screen()
	if screen != null:
		return screen
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	# Parent under the HUD's Root so the screen inherits the same canvas
	# rect and anchors resolve against the viewport-sized container.
	var parent: Node = hud.get_node_or_null("Root")
	if parent == null:
		parent = hud
	var inst: Control = LEVEL_UP_SCREEN_SCRIPT.new()
	parent.add_child(inst)
	return inst

func _get_screen() -> Node:
	return get_tree().get_first_node_in_group("level_up_screen")

func _find_player(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == peer_id:
			return p
	return null
