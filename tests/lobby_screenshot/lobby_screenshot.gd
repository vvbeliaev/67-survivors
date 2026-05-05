extends Node

var _saved: bool = false
var _frame: int = 0

func _ready() -> void:
	var lobby_scene: PackedScene = load("res://src/lobby/lobby.tscn")
	var inst: Node = lobby_scene.instantiate()
	add_child(inst)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 60 and not _saved:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://lobby_screenshot.png")
		var abs := ProjectSettings.globalize_path("user://lobby_screenshot.png")
		print("[shot] saved to: ", abs)
		_saved = true
		get_tree().quit()
