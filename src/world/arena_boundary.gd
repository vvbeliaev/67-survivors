class_name ArenaBoundary extends Node2D

# Soft cylindrical leash around (0, 0). Players outside the radius are pulled
# back toward the origin at a speed strictly greater than any reasonable
# player movement speed (base 220–260, with stacked +10% upgrades reaching
# ~400). The boundary is also drawn as a semi-transparent black ring in
# world space and re-projected onto the minimap.

const ARENA_RADIUS := 2160.0
const PULL_SPEED := 900.0
const BORDER_THICKNESS := 18.0
const BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const ARC_SEGMENTS := 128

func _ready() -> void:
	add_to_group("arena_boundary")
	z_index = -1

func get_radius() -> float:
	return ARENA_RADIUS

func _draw() -> void:
	# Thick semi-transparent ring centered at origin (the arena center).
	draw_arc(Vector2.ZERO, ARENA_RADIUS, 0.0, TAU, ARC_SEGMENTS, BORDER_COLOR, BORDER_THICKNESS, true)

func _physics_process(delta: float) -> void:
	if not GameState.is_authority():
		return
	var step: float = PULL_SPEED * delta
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive:
			continue
		var pos: Vector2 = p.global_position
		var d: float = pos.length()
		if d <= ARENA_RADIUS:
			continue
		# Pull toward origin; cap step so the player doesn't tunnel past zero.
		var move: float = min(step, d)
		p.global_position = pos - pos.normalized() * move
