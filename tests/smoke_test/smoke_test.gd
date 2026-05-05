extends Node

# Headless verification: load the arena, run a few seconds, exercise damage,
# kill, level-up, and boss spawn paths.
#
# Run with: godot --headless res://tests/smoke_test/smoke_test.tscn

const ARENA_SCENE := preload("res://src/world/arena.tscn")

func _ready() -> void:
	print("[smoke] launching")
	GameState.roster[1] = {"nick": "Smoke", "klass": &"berserker"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)
	await get_tree().create_timer(6.0).timeout
	var players := get_tree().get_nodes_in_group("players")
	var enemies := get_tree().get_nodes_in_group("enemies")
	var projectiles := arena.get_node("ProjectilesContainer").get_children()
	print("[smoke] players=%d enemies=%d projectiles=%d run_time=%.2f xp=%d lvl=%d" % [
		players.size(), enemies.size(), projectiles.size(),
		GameState.run_time, GameState.party_xp, GameState.party_level
	])
	if not enemies.is_empty():
		var e: Node = enemies[0]
		e.apply_damage(9999.0, "player")
		print("[smoke] killed one enemy")
	await get_tree().create_timer(0.5).timeout
	print("[smoke] post-kill xp=%d lvl=%d" % [GameState.party_xp, GameState.party_level])
	GameState.run_time = (Defs.wave_set.run_duration if Defs.wave_set != null else 600.0) + 1.0
	await get_tree().create_timer(2.0).timeout
	var boss_count := 0
	for ee in get_tree().get_nodes_in_group("enemies"):
		if ee.enemy_type == &"boss":
			boss_count += 1
	print("[smoke] boss_count=%d" % boss_count)
	if players.size() > 0:
		var p: Node = players[0]
		var hp_before: float = p.hp
		p.apply_damage(50.0, "enemy")
		print("[smoke] player hp %.1f -> %.1f" % [hp_before, p.hp])
	if players.size() > 0:
		var p2: Node = players[0]
		var dmg_before: float = p2.dmg_mult()
		var def: UpgradeDef = Defs.upgrade_def(&"damage")
		if def != null:
			p2.apply_upgrade_def(def)
			print("[smoke] upgrade damage %.2f -> %.2f" % [dmg_before, p2.dmg_mult()])
	print("[smoke] DONE")
	get_tree().quit(0)
