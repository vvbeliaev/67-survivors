extends Node

var _saved: bool = false
var _frame: int = 0
var _hosted: bool = false

func _ready() -> void:
	GameState.local_nick = "P"
	GameState.local_class = &"crossbow"
	var lobby_scene: PackedScene = load("res://src/lobby/lobby.tscn")
	var inst: Node = lobby_scene.instantiate()
	add_child(inst)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 5 and not _hosted:
		Network.host(7790)
		# Add fake peers to populate the squad grid so we see role lines.
		GameState.roster[2] = {"nick": "Asha", "klass": &"crossbow"}
		GameState.roster[3] = {"nick": "Vrok", "klass": &"berserker"}
		GameState.roster[4] = {"nick": "Lyra", "klass": &"bard"}
		GameState.roster_changed.emit()
		Network.lobby_updated.emit()
		_hosted = true
	if _frame == 60 and not _saved:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://lobby_wr_screenshot.png")
		var abs := ProjectSettings.globalize_path("user://lobby_wr_screenshot.png")
		print("[shot] saved to: ", abs)
		_saved = true
		Network.leave()
		get_tree().quit()
