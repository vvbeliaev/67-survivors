extends Node

# Uniform spatial hash for the "enemies" group. Rebuilt once per physics frame
# at priority -1000 (before any consumer's _physics_process), then queried by
# Targeting from skills, AI, and projectiles.
#
# Why this exists: Targeting used to do full-scan over get_nodes_in_group with
# distance_to (sqrt) — O(N) per call, ~12 callers per frame. With N=300 that's
# ~3600 sqrt+compare per frame, plus 12 group-iteration allocations. The grid
# turns each query into O(R²/cell²) and replaces sqrt with squared compares.
#
# Players are NOT gridded: a party is at most 4 strong, a flat alive-cached
# array beats dictionary lookups for that count.
#
# Authority-agnostic: groups are populated on every peer (enemies/players are
# replicated as scene members), and Targeting is only invoked from
# host-gated paths anyway. Each peer's index reflects its local view.

const CELL_SIZE: float = 96.0
const INV_CELL: float = 1.0 / 96.0

var _enemy_grid: Dictionary = {}    # Vector2i -> Array[Node2D]
var _players: Array = []            # alive players cached for the frame

func _ready() -> void:
	process_physics_priority = -1000

func _physics_process(_delta: float) -> void:
	_rebuild()

func _rebuild() -> void:
	_enemy_grid.clear()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if not e.alive:
			continue
		var pos: Vector2 = e.global_position
		var key := Vector2i(int(floor(pos.x * INV_CELL)), int(floor(pos.y * INV_CELL)))
		var bucket = _enemy_grid.get(key)
		if bucket == null:
			bucket = []
			_enemy_grid[key] = bucket
		bucket.append(e)
	_players.clear()
	for plr in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(plr):
			continue
		if not plr.alive:
			continue
		_players.append(plr)

# ---- Enemy queries -----------------------------------------------------

func nearest_enemy(from: Vector2, max_dist: float, exclude: Array = []) -> Node2D:
	var best_d2: float = max_dist * max_dist
	var best: Node2D = null
	var min_x := int(floor((from.x - max_dist) * INV_CELL))
	var min_y := int(floor((from.y - max_dist) * INV_CELL))
	var max_x := int(floor((from.x + max_dist) * INV_CELL))
	var max_y := int(floor((from.y + max_dist) * INV_CELL))
	for cy in range(min_y, max_y + 1):
		for cx in range(min_x, max_x + 1):
			var bucket = _enemy_grid.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for n in bucket:
				if not is_instance_valid(n):
					continue
				if not n.alive:
					continue
				if not exclude.is_empty() and exclude.has(n):
					continue
				var d2: float = from.distance_squared_to(n.global_position)
				if d2 < best_d2:
					best_d2 = d2
					best = n
	return best

func enemies_in_radius(center: Vector2, r: float) -> Array:
	var out: Array = []
	var r2: float = r * r
	var min_x := int(floor((center.x - r) * INV_CELL))
	var min_y := int(floor((center.y - r) * INV_CELL))
	var max_x := int(floor((center.x + r) * INV_CELL))
	var max_y := int(floor((center.y + r) * INV_CELL))
	for cy in range(min_y, max_y + 1):
		for cx in range(min_x, max_x + 1):
			var bucket = _enemy_grid.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for n in bucket:
				if not is_instance_valid(n):
					continue
				if not n.alive:
					continue
				if center.distance_squared_to(n.global_position) <= r2:
					out.append(n)
	return out

# ---- Player queries (linear, party is tiny) ----------------------------

func players_in_radius(center: Vector2, r: float) -> Array:
	var out: Array = []
	var r2: float = r * r
	for p in _players:
		if not is_instance_valid(p):
			continue
		if not p.alive:
			continue
		if center.distance_squared_to(p.global_position) <= r2:
			out.append(p)
	return out

func nearest_alive_player(from: Vector2, max_dist: float = INF) -> Node2D:
	var best_d2: float = INF if max_dist == INF else max_dist * max_dist
	var best: Node2D = null
	for p in _players:
		if not is_instance_valid(p):
			continue
		if not p.alive:
			continue
		var d2: float = from.distance_squared_to(p.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best
