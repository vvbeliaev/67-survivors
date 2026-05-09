class_name Targeting extends RefCounted

# Shared spatial queries used by skills and AI. Thin facade over the
# SpatialIndex autoload — keeps the existing call sites unchanged while the
# heavy lifting (uniform grid + squared-distance compare) happens in
# SpatialIndex, rebuilt once per physics frame.
#
# The `tree` argument is no longer needed but kept so callers don't churn.

static func nearest_enemy(_tree: SceneTree, from: Vector2, max_dist: float) -> Node2D:
	return SpatialIndex.nearest_enemy(from, max_dist)

static func nearest_enemy_excluding(_tree: SceneTree, from: Vector2, max_dist: float, exclude: Array) -> Node2D:
	return SpatialIndex.nearest_enemy(from, max_dist, exclude)

static func enemies_in_radius(_tree: SceneTree, center: Vector2, r: float) -> Array:
	return SpatialIndex.enemies_in_radius(center, r)

static func players_in_radius(_tree: SceneTree, center: Vector2, r: float) -> Array:
	return SpatialIndex.players_in_radius(center, r)

# «Цели, которые мобы воспринимают как игроков»: реальные игроки + чучела.
# Используется мобовыми AoE/dash-ударами — они должны цеплять чучело так же,
# как и игрока, иначе чучело перестаёт быть мясным щитом против AoE.
# Бардовским heal/buff'ам это НЕ нужно — там по-прежнему players_in_radius.
static func player_targets_in_radius(tree: SceneTree, center: Vector2, r: float) -> Array:
	var out: Array = SpatialIndex.players_in_radius(center, r)
	var r2: float = r * r
	for d in tree.get_nodes_in_group("decoys"):
		if d == null or not is_instance_valid(d):
			continue
		if "alive" in d and not d.alive:
			continue
		if d.global_position.distance_squared_to(center) <= r2:
			out.append(d)
	return out

static func nearest_alive_player(_tree: SceneTree, from: Vector2, max_dist: float = INF) -> Node2D:
	return SpatialIndex.nearest_alive_player(from, max_dist)

# Decoys (berserker_decoy) — редко, до 1 на варвара, поэтому без spatial index:
# линейно итерируемся по группе. Учитываем только живых.
static func nearest_decoy(tree: SceneTree, from: Vector2, max_dist: float = INF) -> Node2D:
	var best: Node2D = null
	var best_d: float = max_dist
	for d in tree.get_nodes_in_group("decoys"):
		if d == null or not is_instance_valid(d):
			continue
		if "alive" in d and not d.alive:
			continue
		var dist: float = d.global_position.distance_to(from)
		if dist < best_d:
			best_d = dist
			best = d
	return best
