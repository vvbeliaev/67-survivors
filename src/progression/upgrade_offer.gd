extends Node

# On level_up the host rolls 3 upgrades per peer (filtered by class) and RPCs
# them to the HUD. Pick is RPCed back to the host and applied to that peer's
# Player. Stack bookkeeping lives on Player.apply_upgrade_def.

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("upgrade_offer")
	_rng.randomize()
	EventBus.level_up.connect(_on_level_up)

func _on_level_up(_new_level: int) -> void:
	if not GameState.is_authority():
		return
	var has_peer := GameState.is_networked()
	for pid in GameState.roster.keys():
		var player := _find_player(int(pid))
		if player == null:
			continue
		var picks := UpgradePool.roll_for(_rng, player, 3)
		var ids: PackedStringArray = []
		var labels: PackedStringArray = []
		for u in picks:
			ids.append(String(u.id))
			labels.append(u.label)
		if int(pid) == 1 or not has_peer:
			_rpc_show_picks(ids, labels)
		else:
			_rpc_show_picks.rpc_id(int(pid), ids, labels)

@rpc("authority", "reliable")
func _rpc_show_picks(ids: PackedStringArray, labels: PackedStringArray) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var options: Array = []
	for i in ids.size():
		options.append({"id": ids[i], "label": labels[i]})
	hud.show_upgrade_picks(options)

# Called by the HUD when the local player makes a pick.
func submit_pick(id: String) -> void:
	if multiplayer.multiplayer_peer == null:
		_apply_to_peer(1, id)
	elif multiplayer.is_server():
		_apply_to_peer(1, id)
	else:
		_rpc_submit.rpc_id(1, id)

@rpc("any_peer", "reliable")
func _rpc_submit(id: String) -> void:
	if not multiplayer.is_server():
		return
	_apply_to_peer(multiplayer.get_remote_sender_id(), id)

func _apply_to_peer(peer_id: int, id: String) -> void:
	var def: UpgradeDef = Defs.upgrade_def(StringName(id))
	if def == null:
		push_warning("UpgradeOffer: unknown id %s" % id)
		return
	var player := _find_player(peer_id)
	if player == null:
		return
	player.apply_upgrade_def(def)
	EventBus.upgrade_picked.emit(peer_id, def.id)

func _find_player(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer_id:
			return p
	return null
