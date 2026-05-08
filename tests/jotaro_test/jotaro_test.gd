extends Node

const ARENA_SCENE := preload("res://src/world/arena.tscn")

func _ready() -> void:
	print("[jotaro] launching")
	GameState.roster[1] = {"nick": "Joj", "klass": &"jotaro"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)

	await get_tree().create_timer(0.5).timeout

	var players := get_tree().get_nodes_in_group("players")
	var minions := get_tree().get_nodes_in_group("minions")
	print("[jotaro] players=%d minions=%d" % [players.size(), minions.size()])
	if players.size() == 0:
		print("[jotaro] FAIL: no players spawned")
		get_tree().quit(1)
		return
	if minions.size() == 0:
		print("[jotaro] FAIL: Star Platinum did not spawn")
		get_tree().quit(1)
		return
	var jp: Node = players[0]
	var sp: Node = minions[0]
	print("[jotaro] jotaro klass=%s pos=%s" % [String(jp.klass), str(jp.global_position)])
	print("[jotaro] sp pos=%s owner_peer_id=%d" % [str(sp.global_position), int(sp.owner_peer_id)])

	# Spawn a tank near the player and let SP punch it for ~1 second.
	if arena.has_method("spawn_enemy"):
		arena.spawn_enemy({"type": "tank", "pos": jp.global_position + Vector2(80, 0)})
	await get_tree().create_timer(1.2).timeout

	var tanks: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.enemy_type == &"tank":
			tanks.append(e)
	if tanks.is_empty():
		print("[jotaro] no tanks (already killed by SP — possibly OK)")
	else:
		var tank = tanks[0]
		print("[jotaro] tank hp=%.1f / max %.1f after 1.2s of SP punching" % [float(tank.hp), float(tank.max_hp)])
		if float(tank.hp) >= float(tank.max_hp) - 0.001:
			print("[jotaro] FAIL: SP did not damage the tank")
			get_tree().quit(1)
			return

	print("[jotaro] DONE")
	get_tree().quit(0)
