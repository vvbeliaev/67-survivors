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

static func nearest_alive_player(_tree: SceneTree, from: Vector2, max_dist: float = INF) -> Node2D:
	return SpatialIndex.nearest_alive_player(from, max_dist)
