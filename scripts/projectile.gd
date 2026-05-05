extends Area2D

# Spawned by host, motion is deterministic on every peer.
# Only the host evaluates collisions; on hit the host queue_frees the node
# and the spawner pushes the despawn to clients.

var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var lifetime: float = 2.0
var team: String = "player"  # "player" or "enemy"
var color_hint: Color = Color(1, 1, 1)
var radius: float = 6.0
var pierce: int = 0  # extra hits before despawn
var hit_set: Dictionary = {}

func _ready() -> void:
	monitoring = GameState.is_authority()
	monitorable = false
	if monitoring:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	# Layer/mask configured at spawn-time setup (see Arena._spawn_projectile).
	queue_redraw()

func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0:
		if GameState.is_authority():
			queue_free()
		else:
			visible = false

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color_hint)

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(node: Node) -> void:
	if not GameState.is_authority():
		return
	if hit_set.has(node):
		return
	if not node.has_method("apply_damage"):
		return
	# Filter by team.
	var node_team: String = node.get("team_tag") if node.has_method("get") and "team_tag" in node else ""
	if team == "player" and node_team != "enemy":
		return
	if team == "enemy" and node_team != "player":
		return
	hit_set[node] = true
	node.apply_damage(damage, team)
	if pierce > 0:
		pierce -= 1
	else:
		queue_free()
