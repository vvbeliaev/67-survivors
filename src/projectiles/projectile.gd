extends Area2D

# Spawned by host. Motion is deterministic on every peer; only the host
# evaluates collisions. On hit the host queue_frees the node, the despawn
# is replicated by MultiplayerSpawner.

var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var lifetime: float = 2.0
var team: String = "player"
var color_hint: Color = Color(1, 1, 1)
var radius: float = 6.0
var pierce: int = 0
var hit_set: Dictionary = {}
var source_peer: int = 0
var mana_on_hit_pct: float = 0.0
var sprite_path: String = ""
var sprite_size: Vector2 = Vector2.ZERO

var _sprite_tex: Texture2D = null
var _sprite_loaded: bool = false

func _ready() -> void:
	monitoring = GameState.is_authority()
	monitorable = false
	if monitoring:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		if GameState.is_authority():
			queue_free()
		else:
			visible = false

func _draw() -> void:
	var tex: Texture2D = _get_sprite()
	if tex != null:
		var w: float = sprite_size.x if sprite_size.x > 0.0 else radius * 8.0
		var h: float = sprite_size.y if sprite_size.y > 0.0 else radius * 3.0
		var ang: float = velocity.angle() if velocity.length_squared() > 0.0 else 0.0
		draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-Vector2(w, h) * 0.5, Vector2(w, h)), false, color_hint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, radius, color_hint)

func _get_sprite() -> Texture2D:
	if _sprite_loaded:
		return _sprite_tex
	if sprite_path.is_empty():
		_sprite_loaded = true
		return null
	_sprite_tex = ResourceLoader.load(sprite_path) as Texture2D
	_sprite_loaded = true
	return _sprite_tex

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
	var node_team: String = ""
	if "team_tag" in node:
		node_team = node.team_tag
	if team == "player" and node_team != "enemy":
		return
	if team == "enemy" and node_team != "player":
		return
	hit_set[node] = true
	node.apply_damage(damage, team)
	if mana_on_hit_pct > 0.0 and source_peer != 0:
		_restore_source_mana()
	if pierce > 0:
		pierce -= 1
	else:
		queue_free()

func _restore_source_mana() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == source_peer:
			if p.alive and p.max_mp > 0.0:
				p.mp = min(p.mp + p.max_mp * mana_on_hit_pct, p.max_mp)
			return
