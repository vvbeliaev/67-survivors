extends Camera2D

# Single shared camera bound to centroid of alive players. Dynamic zoom shrinks
# as the party spreads out. Players too far from the centroid are pulled back
# (the "screen squeezes" rule from the design doc).

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.4
const BASE_HALF_VIEW := 360.0  # comfortable half-extent at zoom 1
const LEASH_RADIUS := 600.0
const LEASH_PULL := 6.0  # units of velocity nudge per second per pixel of overshoot

func _ready() -> void:
	make_current()
	top_level = true

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	var alive_pos: Array[Vector2] = []
	for p in players:
		if p.alive:
			alive_pos.append(p.global_position)
	if alive_pos.is_empty():
		# Fall back to mean of all (so camera doesn't snap to origin on wipe).
		for p in players:
			alive_pos.append(p.global_position)
	var centroid := Vector2.ZERO
	for v in alive_pos:
		centroid += v
	centroid /= alive_pos.size()
	# Spread = max distance from centroid.
	var spread := 0.0
	for v in alive_pos:
		spread = max(spread, centroid.distance_to(v))
	# Target zoom: tighter when alone, wider when spread.
	var target_zoom_scalar: float = clampf(BASE_HALF_VIEW / max(spread + 200.0, 200.0), MIN_ZOOM, MAX_ZOOM)
	zoom = zoom.lerp(Vector2(target_zoom_scalar, target_zoom_scalar), 0.06)
	global_position = global_position.lerp(centroid, 0.18)

	# Leash: only host moves players, so we only enforce on host.
	if multiplayer.is_server():
		for p in players:
			if not p.alive:
				continue
			var off: Vector2 = p.global_position - centroid
			var d := off.length()
			if d > LEASH_RADIUS:
				var overshoot: float = d - LEASH_RADIUS
				p.global_position -= off.normalized() * min(overshoot, LEASH_PULL * overshoot * delta + 1.0)
