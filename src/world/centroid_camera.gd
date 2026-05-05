extends Camera2D

# Single shared camera bound to centroid of alive players. Dynamic zoom
# shrinks as the party spreads out. Players too far from the centroid get
# pulled back ("the screen squeezes" rule from the design doc).

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.4
const BASE_HALF_VIEW := 360.0
const LEASH_RADIUS := 600.0
const LEASH_PULL := 6.0

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
		for p in players:
			alive_pos.append(p.global_position)
	var centroid := Vector2.ZERO
	for v in alive_pos:
		centroid += v
	centroid /= alive_pos.size()
	var spread := 0.0
	for v in alive_pos:
		spread = max(spread, centroid.distance_to(v))
	var target_zoom_scalar: float = clampf(BASE_HALF_VIEW / max(spread + 200.0, 200.0), MIN_ZOOM, MAX_ZOOM)
	zoom = zoom.lerp(Vector2(target_zoom_scalar, target_zoom_scalar), 0.06)
	global_position = global_position.lerp(centroid, 0.18)

	if GameState.is_authority():
		for p in players:
			if not p.alive:
				continue
			var off: Vector2 = p.global_position - centroid
			var d := off.length()
			if d > LEASH_RADIUS:
				var overshoot: float = d - LEASH_RADIUS
				p.global_position -= off.normalized() * min(overshoot, LEASH_PULL * overshoot * delta + 1.0)
