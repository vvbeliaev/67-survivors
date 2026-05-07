extends Node

# Owner-side input capture. Reads the InputMap each physics tick and forwards
# the raw intent to the host. In offline / host-local mode it dispatches to
# the player directly. The host applies inputs via Player._apply_input().
#
# On touch devices (mobile build, or web build with a touchscreen) the
# pipeline switches to the TouchControls overlay:
#   - movement is the unit vector from the hero toward the held finger
#   - skill buttons emit edge-triggered cast presses
#   - aim is auto-resolved to the nearest enemy for any directional skill
#     so the player never has to "aim" — the projectile finds its target.

# Distance from the player at which the synthetic aim point sits when no
# enemy exists for auto-targeting. Anything beyond the player's radius is
# enough for `aim_dir` to resolve cleanly.
const TOUCH_AIM_FALLBACK_DIST := 256.0

# Cap on the auto-aim search radius. Larger than any reasonable on-screen
# range (camera half-view is ~600 even at min zoom) and tiny compared to
# 99999 — every cell beyond this is empty anyway, and SpatialIndex pays for
# the bounding box of the search.
const AUTO_AIM_RANGE := 1800.0

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
		# `auto_just` is consumed but not dispatched — the auto-skill ticks on
		# its own; the press only exists to keep the consumer state clean.
		t.consume_auto()
		# Aim resolution (touch-only). Default cheap path: walk direction.
		# Calling `Targeting.nearest_enemy` every frame is *much* too heavy
		# for mobile WebGL — the host pays for one targeting query per fire
		# instead, and skills that need true auto-aim (crossbow auto-bolt)
		# query themselves on tick.
		var fallback: Vector2 = move
		if fallback.length_squared() < 0.001:
			fallback = _player.aim_dir
		var fallback_aim: Vector2 = _player.global_position + fallback * TOUCH_AIM_FALLBACK_DIST
		aim_world = fallback_aim
		# When a directional skill button is tapped, snap aim to the nearest
		# enemy so projectiles / blinks land on a real target. Utility (dash)
		# keeps the walk direction.
		if primary_just or secondary_just or primary_release:
			var nearest := Targeting.nearest_enemy(get_tree(), _player.global_position, AUTO_AIM_RANGE)
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
