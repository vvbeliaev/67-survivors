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
		p.iframes_until = 0.0
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
	print("[smoke] run_kills=%d run_damage=%d run_xp_gained=%d" % [
		GameState.run_kills, GameState.run_damage, GameState.run_xp_gained
	])
	# Level-up flow: force a level threshold, fire the event, verify the
	# screen opens and the tree pauses; submit a pick and verify it resumes.
	GameState.party_xp = 0
	EventBus.level_up.emit(GameState.party_level + 1)
	await get_tree().create_timer(0.1).timeout
	print("[smoke] level_up paused=%s screen=%s" % [
		str(get_tree().paused),
		str(get_tree().get_first_node_in_group("level_up_screen") != null),
	])
	var offer := get_tree().get_first_node_in_group("upgrade_offer")
	if offer != null:
		offer.submit_pick("damage")
	await get_tree().create_timer(0.1).timeout
	print("[smoke] after-pick paused=%s" % str(get_tree().paused))
	# End-screen path: trigger run end and confirm EndScreen instance shows.
	var rd := get_tree().get_first_node_in_group("run_director")
	if rd != null:
		rd._end(false)
	await get_tree().create_timer(0.1).timeout
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.get("_end_screen") != null:
		var es = hud.get("_end_screen")
		print("[smoke] end_screen visible=%s" % str(es.visible))
	print("[smoke] DONE")
	get_tree().quit(0)
