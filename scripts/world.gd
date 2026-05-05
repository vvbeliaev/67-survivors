extends Node2D

const CELL := 64
const EXTENT := 64

func _draw() -> void:
	var col := Color(0.18, 0.18, 0.22)
	var axis := Color(0.35, 0.35, 0.4)
	var half := EXTENT * CELL
	for i in range(-EXTENT, EXTENT + 1):
		var p := i * CELL
		var c := axis if i == 0 else col
		draw_line(Vector2(p, -half), Vector2(p, half), c, 1.0)
		draw_line(Vector2(-half, p), Vector2(half, p), c, 1.0)
