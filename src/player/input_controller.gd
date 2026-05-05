extends Node

# Owner-side input capture. Reads the InputMap each physics tick and forwards
# the raw intent to the host. In offline / host-local mode it dispatches to
# the player directly. The host applies inputs via Player._apply_input().

@export var owner_path: NodePath = NodePath("..")

var _player: Node = null

func _ready() -> void:
	_player = get_node(owner_path)

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.alive:
		return
	if not _is_local_owner():
		return
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim_world: Vector2 = _player.get_global_mouse_position()
	var primary_just := Input.is_action_just_pressed("cast_primary")
	var secondary_just := Input.is_action_just_pressed("cast_secondary")
	var utility_just := Input.is_action_just_pressed("utility")
	var primary_held := Input.is_action_pressed("cast_primary")
	var primary_release := Input.is_action_just_released("cast_primary")
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_player.apply_input(move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)
	else:
		_player.rpc_id(1, "_rpc_apply_input", move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)

func _is_local_owner() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.get_unique_id() == _player.peer_id
