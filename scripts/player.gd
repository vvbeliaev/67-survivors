extends CharacterBody2D

const SPEED := 300.0

func _ready() -> void:
	$Camera2D.make_current()

func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(0.4, 0.8, 1.0))
