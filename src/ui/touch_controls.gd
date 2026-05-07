class_name TouchControls extends Control

# On-screen touch controls for mobile / web-touch builds. Renders a virtual
# joystick (anchored where the player first touches the left half) and a
# quarter-circle of skill buttons in the bottom-right corner. The
# InputController polls this node for movement, aim hints, and edge-triggered
# skill press flags instead of reading the keyboard / mouse.
#
# Public state is host-agnostic — every peer reads its own touch input
# locally and forwards it through the same `apply_input` pathway as the
# desktop pipeline.

const JOY_BASE_RADIUS := 90.0
const JOY_KNOB_RADIUS := 36.0
const JOY_DEADZONE := 0.18

const SKILL_BTN_RADIUS := 50.0
const SKILL_RING_RADIUS := 165.0
const SKILL_CORNER_INSET := 70.0
const SKILL_HIT_RADIUS := 64.0

const DOUBLE_TAP_WINDOW := 0.30
const DOUBLE_TAP_DRIFT := 80.0

# Slot order matches Player's auto/primary/secondary/utility skill array.
const SLOT_AUTO := 0
const SLOT_PRIMARY := 1
const SLOT_SECONDARY := 2
const SLOT_UTILITY := 3

const SLOT_LABELS := ["AUTO", "LMB", "RMB", "↯"]

# Public output (read each tick by InputController).
var move: Vector2 = Vector2.ZERO          # joystick vector, [-1,1]^2
var aim_hint_dir: Vector2 = Vector2.RIGHT # last non-zero joystick direction
var primary_held: bool = false

# Edge-triggered presses. Consumed via consume_*().
var _auto_just: bool = false
var _primary_just: bool = false
var _primary_release: bool = false
var _secondary_just: bool = false
var _utility_just: bool = false

var _joy_finger: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO

var _slot_finger: Array[int] = [-1, -1, -1, -1]
var _slot_centers: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _slot_icons: Array = [null, null, null, null]

var _last_release_time: float = -10.0
var _last_release_pos: Vector2 = Vector2.ZERO

var _player: Node = null
var _last_class: StringName = &""

const FONT_DISPLAY := preload("res://assets/fonts/Cinzel.ttf")
const FONT_MONO := preload("res://assets/fonts/JetBrainsMono.ttf")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = GameState.is_touch_ui()

func _process(_delta: float) -> void:
	if not GameState.is_touch_ui():
		visible = false
		return
	# Hide while a modal overlay (level-up offer, end screen) is on top so
	# touches there reach the right Control.
	var overlay_active := _has_blocking_overlay()
	if overlay_active and visible:
		_reset_touch_state()
	visible = not overlay_active
	if not visible:
		return
	_refresh_player()
	_layout_buttons()
	queue_redraw()

func _has_blocking_overlay() -> bool:
	# The level-up screen lingers in the tree between offers (it just toggles
	# visibility), so check `visible`, not just presence in the group.
	var lvl := get_tree().get_first_node_in_group("level_up_screen")
	if lvl is Control and (lvl as Control).visible:
		return true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		var endscr = hud.get("_end_screen")
		if endscr is Control and (endscr as Control).visible:
			return true
	return false

func _refresh_player() -> void:
	if _player != null and is_instance_valid(_player):
		var k := StringName(String(_player.klass))
		if k != _last_class:
			_last_class = k
			_refresh_slot_icons()
		return
	var my_id: int = 1
	if multiplayer.multiplayer_peer != null:
		my_id = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == my_id:
			_player = p
			_last_class = StringName(String(p.klass))
			_refresh_slot_icons()
			return

func _refresh_slot_icons() -> void:
	if _player == null or _player.class_node == null:
		for i in 4:
			_slot_icons[i] = null
		return
	for i in 4:
		_slot_icons[i] = _player.class_node.icon_for_slot(i)

func _layout_buttons() -> void:
	var pivot := Vector2(size.x - SKILL_CORNER_INSET, size.y - SKILL_CORNER_INSET)
	for i in 4:
		var t: float = float(i) / 3.0
		var angle: float = lerp(PI, 1.5 * PI, t)
		_slot_centers[i] = pivot + Vector2(cos(angle), sin(angle)) * SKILL_RING_RADIUS

# ---- Input dispatch ---------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(int(event.index), event.position, event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		_handle_drag(int(event.index), event.position)
		accept_event()
	elif event is InputEventMouseButton:
		# Web fallback: mouse acts as a single touch (index 0). Helpful for
		# testing the touch UI on a desktop browser.
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(0, event.position, event.pressed)
			accept_event()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_drag(0, event.position)

func _handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var slot := _hit_test_slot(pos)
		if slot >= 0 and _slot_finger[slot] == -1:
			_slot_finger[slot] = idx
			_on_slot_pressed(slot)
			return
		if _joy_finger == -1 and slot < 0:
			var now: float = Time.get_ticks_msec() / 1000.0
			if now - _last_release_time <= DOUBLE_TAP_WINDOW \
					and pos.distance_to(_last_release_pos) <= DOUBLE_TAP_DRIFT:
				_utility_just = true
			_joy_finger = idx
			_joy_origin = pos
			_joy_pos = pos
			move = Vector2.ZERO
		return
	# Released.
	if _joy_finger == idx:
		_joy_finger = -1
		_last_release_time = Time.get_ticks_msec() / 1000.0
		_last_release_pos = pos
		move = Vector2.ZERO
		return
	for i in 4:
		if _slot_finger[i] == idx:
			_slot_finger[i] = -1
			_on_slot_released(i)
			return

func _handle_drag(idx: int, pos: Vector2) -> void:
	if _joy_finger == idx:
		_joy_pos = pos
		var raw: Vector2 = _joy_pos - _joy_origin
		if raw.length() > JOY_BASE_RADIUS:
			raw = raw.normalized() * JOY_BASE_RADIUS
		var v: Vector2 = raw / JOY_BASE_RADIUS
		if v.length() < JOY_DEADZONE:
			move = Vector2.ZERO
		else:
			move = v
			aim_hint_dir = v.normalized()

func _hit_test_slot(pos: Vector2) -> int:
	for i in 4:
		if pos.distance_squared_to(_slot_centers[i]) <= SKILL_HIT_RADIUS * SKILL_HIT_RADIUS:
			return i
	return -1

func _on_slot_pressed(slot: int) -> void:
	match slot:
		SLOT_AUTO:
			_auto_just = true
		SLOT_PRIMARY:
			_primary_just = true
			primary_held = true
		SLOT_SECONDARY:
			_secondary_just = true
		SLOT_UTILITY:
			_utility_just = true

func _on_slot_released(slot: int) -> void:
	if slot == SLOT_PRIMARY:
		primary_held = false
		_primary_release = true

func _reset_touch_state() -> void:
	_joy_finger = -1
	move = Vector2.ZERO
	primary_held = false
	for i in 4:
		_slot_finger[i] = -1
	_auto_just = false
	_primary_just = false
	_primary_release = false
	_secondary_just = false
	_utility_just = false

# ---- Output (consumed by InputController) -----------------------------

func consume_auto() -> bool:
	var v := _auto_just
	_auto_just = false
	return v

func consume_primary() -> bool:
	var v := _primary_just
	_primary_just = false
	return v

func consume_primary_release() -> bool:
	var v := _primary_release
	_primary_release = false
	return v

func consume_secondary() -> bool:
	var v := _secondary_just
	_secondary_just = false
	return v

func consume_utility() -> bool:
	var v := _utility_just
	_utility_just = false
	return v

# ---- Drawing ----------------------------------------------------------

func _draw() -> void:
	_draw_skill_buttons()
	if _joy_finger != -1:
		_draw_joystick()

func _draw_joystick() -> void:
	var raw: Vector2 = _joy_pos - _joy_origin
	if raw.length() > JOY_BASE_RADIUS:
		raw = raw.normalized() * JOY_BASE_RADIUS
	var knob_pos: Vector2 = _joy_origin + raw
	# Base ring.
	draw_circle(_joy_origin, JOY_BASE_RADIUS, Color(0.05, 0.04, 0.03, 0.45))
	draw_arc(_joy_origin, JOY_BASE_RADIUS, 0.0, TAU, 64, Color(0.92, 0.85, 0.72, 0.55), 2.0, true)
	# Knob.
	draw_circle(knob_pos, JOY_KNOB_RADIUS, Color(0.20, 0.16, 0.12, 0.85))
	draw_circle(knob_pos, JOY_KNOB_RADIUS * 0.6, Color(0.84, 0.45, 0.30, 0.95))
	draw_arc(knob_pos, JOY_KNOB_RADIUS, 0.0, TAU, 32, Color(0.92, 0.85, 0.72, 0.95), 1.5, true)

func _draw_skill_buttons() -> void:
	var cd_lefts: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var cd_totals: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var mana_lacks: Array[bool] = [false, false, false, false]
	if _player != null and is_instance_valid(_player) and _player.class_node != null:
		cd_lefts = [
			float(_player.cd_left_auto),
			float(_player.cd_left_primary),
			float(_player.cd_left_secondary),
			float(_player.cd_left_utility),
		]
		cd_totals = [
			float(_player.cd_total_auto),
			float(_player.cd_total_primary),
			float(_player.cd_total_secondary),
			float(_player.cd_total_utility),
		]
		var skills := [
			_player.class_node.auto_skill,
			_player.class_node.primary_skill,
			_player.class_node.secondary_skill,
			_player.class_node.utility_skill,
		]
		for i in 4:
			var s = skills[i]
			if s != null and float(s.mana_cost) > 0.0:
				mana_lacks[i] = float(_player.mp) < float(s.mana_cost)

	for i in 4:
		var center: Vector2 = _slot_centers[i]
		var pressed: bool = _slot_finger[i] != -1
		_draw_skill_button(i, center, pressed, cd_lefts[i], cd_totals[i], mana_lacks[i])

func _draw_skill_button(slot: int, center: Vector2, pressed: bool, cd_left: float, cd_total: float, mana_lack: bool) -> void:
	var bg_color := Color(0.10, 0.07, 0.05, 0.85)
	if pressed:
		bg_color = Color(0.18, 0.13, 0.08, 0.95)
	var border := Color(0.42, 0.35, 0.27, 1.0)
	if slot == SLOT_PRIMARY:
		border = Color(0.84, 0.45, 0.30, 1.0)
	# Plate.
	draw_circle(center, SKILL_BTN_RADIUS, bg_color)
	draw_arc(center, SKILL_BTN_RADIUS, 0.0, TAU, 64, border, 2.0, true)
	# Icon.
	var icon: Texture2D = _slot_icons[slot]
	if icon != null:
		var s: float = SKILL_BTN_RADIUS * 1.1
		var tint := Color(0.84, 0.63, 0.29, 0.95)
		if mana_lack or (cd_left > 0.0):
			tint = Color(0.5, 0.45, 0.40, 0.65)
		var rect := Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_texture_rect(icon, rect, false, tint)
	# Cooldown sweep — pie slice that drains clockwise from 12 o'clock.
	if cd_left > 0.0 and cd_total > 0.0:
		var pct: float = clampf(cd_left / cd_total, 0.0, 1.0)
		_draw_cd_sweep(center, SKILL_BTN_RADIUS - 1.0, pct)
		# Remaining seconds.
		var s: String = "%.1f" % cd_left if cd_left < 10.0 else str(int(ceil(cd_left)))
		var fs: int = 22
		var ts: Vector2 = FONT_DISPLAY.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p: Vector2 = center - Vector2(ts.x * 0.5, -ts.y * 0.35)
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				draw_string(FONT_DISPLAY, p + Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.95))
		draw_string(FONT_DISPLAY, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.85, 0.72, 1.0))
	# Slot label (bottom of plate).
	if FONT_MONO != null:
		var lbl: String = SLOT_LABELS[slot]
		var fs: int = 11
		var ts: Vector2 = FONT_MONO.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p: Vector2 = center + Vector2(-ts.x * 0.5, SKILL_BTN_RADIUS - 6.0)
		draw_string(FONT_MONO, p + Vector2(1, 1), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
		draw_string(FONT_MONO, p, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.61, 0.53, 0.41, 1.0))

func _draw_cd_sweep(center: Vector2, r: float, pct: float) -> void:
	# Cheap conic: stack thin radial slices, fill ones whose angle is within
	# the remaining cooldown arc. Drains clockwise from 12 o'clock.
	var bands: int = 36
	var blocked: int = int(round(float(bands) * pct))
	for i in blocked:
		var a0: float = -PI * 0.5 + TAU * float(i) / float(bands)
		var a1: float = a0 + TAU / float(bands) + 0.005
		var pts := PackedVector2Array()
		pts.append(center)
		var steps: int = 4
		for k in (steps + 1):
			var a: float = lerp(a0, a1, float(k) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
