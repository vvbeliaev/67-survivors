class_name Targeting extends RefCounted

# Shared spatial queries used by skills and AI. Static — no state.

static func nearest_enemy(tree: SceneTree, from: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d: float = max_dist
	for e in tree.get_nodes_in_group("enemies"):
		if not e.alive:
			continue
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

static func nearest_enemy_excluding(tree: SceneTree, from: Vector2, max_dist: float, exclude: Array) -> Node2D:
	var best: Node2D = null
	var best_d: float = max_dist
	for e in tree.get_nodes_in_group("enemies"):
		if not e.alive:
			continue
		if exclude.has(e):
			continue
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

static func enemies_in_radius(tree: SceneTree, center: Vector2, r: float) -> Array:
	var out: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if not e.alive:
			continue
		if center.distance_to(e.global_position) <= r:
			out.append(e)
	return out

static func players_in_radius(tree: SceneTree, center: Vector2, r: float) -> Array:
	var out: Array = []
	for p in tree.get_nodes_in_group("players"):
		if not p.alive:
			continue
		if center.distance_to(p.global_position) <= r:
			out.append(p)
	return out

static func nearest_alive_player(tree: SceneTree, from: Vector2, max_dist: float = INF) -> Node2D:
	var best: Node2D = null
	var best_d: float = max_dist
	for p in tree.get_nodes_in_group("players"):
		if not p.alive:
			continue
		var d: float = from.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
