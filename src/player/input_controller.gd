extends Node

# Owner-side input capture. Reads the InputMap each physics tick and forwards
# the raw intent to the host. In offline / host-local mode it dispatches to
# the player directly. The host applies inputs via Player._apply_input().
#
# On touch devices (mobile build, or web build with a touchscreen) the
# pipeline switches to the TouchControls overlay: joystick → move, fingers
# on the skill ring → edge-triggered casts, joystick direction → idle facing,
# nearest enemy → aim for any directional skill that fires this frame.

# Distance from the player at which the synthetic aim point sits when no
# enemy is targeted — anything beyond `radius + ε` is enough for aim_dir to
# resolve cleanly.
const TOUCH_AIM_FALLBACK_DIST := 256.0

@export var owner_path: NodePath = NodePath("..")

var _player: Node = null
var _touch_controls: TouchControls = null

func _ready() -> void:
	_player = get_node(owner_path)

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.alive:
		return
	if not _is_local_owner():
		return

	var move: Vector2
	var aim_world: Vector2
	var primary_just: bool
	var secondary_just: bool
	var utility_just: bool
	var primary_held: bool
	var primary_release: bool

	if GameState.is_touch_ui():
		var t := _resolve_touch_controls()
		if t == null:
			return
		move = t.move
		primary_held = t.primary_held
		primary_just = t.consume_primary()
		secondary_just = t.consume_secondary()
		utility_just = t.consume_utility()
		primary_release = t.consume_primary_release()
		var auto_just: bool = t.consume_auto()
		var fallback_dir: Vector2 = move
		if fallback_dir.length_squared() < 0.001:
			fallback_dir = t.aim_hint_dir
		# Default aim: ahead of the player, in joystick direction. Skills that
		# don't actually read aim ignore it; visuals (player facing,
		# crossbow auto) follow the finger.
		aim_world = _player.global_position + fallback_dir * TOUCH_AIM_FALLBACK_DIST
		# Any directional skill firing this frame snaps aim to the nearest
		# enemy so projectiles / blinks land where mobile players expect them.
		# Utility (dash) keeps the joystick direction.
		var seek_target: bool = primary_just or secondary_just or primary_release or auto_just
		if seek_target:
			var nearest := Targeting.nearest_enemy(get_tree(), _player.global_position, 99999.0)
			if nearest != null:
				aim_world = nearest.global_position
	else:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		aim_world = _player.get_global_mouse_position()
		# Mouse-driven cast inputs are dropped while the cursor is over a
		# Control that consumes input — otherwise clicking the debug spawn
		# button (or any future panel button) would also trigger the primary
		# cast on the same frame, since polling Input bypasses GUI handling.
		var over_gui: bool = get_viewport().gui_get_hovered_control() != null
		primary_just = Input.is_action_just_pressed("cast_primary") and not over_gui
		secondary_just = Input.is_action_just_pressed("cast_secondary") and not over_gui
		utility_just = Input.is_action_just_pressed("utility")
		primary_held = Input.is_action_pressed("cast_primary") and not over_gui
		primary_release = Input.is_action_just_released("cast_primary")

	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_player.apply_input(move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)
	else:
		_player.rpc_id(1, "_rpc_apply_input", move, aim_world, primary_just, secondary_just, utility_just, primary_held, primary_release)

func _resolve_touch_controls() -> TouchControls:
	if _touch_controls != null and is_instance_valid(_touch_controls):
		return _touch_controls
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var node = hud.get_node_or_null("Root/TouchControls")
	if node is TouchControls:
		_touch_controls = node
	return _touch_controls

func _is_local_owner() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.get_unique_id() == _player.peer_id
