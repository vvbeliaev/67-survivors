extends Node

# Headless verification: маг с легендаркой `mage_echo_clone` блинкает,
# на исходной позиции появляется клон. После каста fireball'а клон через
# ~0.10s повторяет в ближайшего к себе врага. После 3 повторов клон
# растворяется. Авто-атаки не повторяются.
#
# Run: godot --headless res://tests/mage_echo/mage_echo.tscn

const ARENA_SCENE := preload("res://src/world/arena.tscn")

var _failures: int = 0

func _ready() -> void:
	print("[mecho] starting")
	GameState.roster[1] = {"nick": "MEcho", "klass": &"mage"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)
	await get_tree().create_timer(0.4).timeout
	await _run(arena)
	if _failures > 0:
		printerr("[mecho] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[mecho] OK")
		get_tree().quit(0)

func _run(arena: Node) -> void:
	var players := get_tree().get_nodes_in_group("players")
	_assert(players.size() >= 1, "player spawned")
	if players.is_empty():
		return
	var player: Node = players[0]
	var input_ctrl: Node = player.get_node_or_null("InputController")
	if input_ctrl != null:
		input_ctrl.set_physics_process(false)

	var leg_def: UpgradeDef = Defs.upgrade_def(&"mage_echo_clone")
	_assert(leg_def != null, "legendary def loaded")
	if leg_def == null:
		return
	player.apply_upgrade_def(leg_def)
	_assert(int(player._upgrade_stacks.get(&"mage_echo_clone", 0)) > 0, "legendary applied")

	player.mp = player.max_mp

	var origin: Vector2 = player.global_position
	var target_pos: Vector2 = origin + Vector2(300, 0)
	player.apply_input(Vector2.ZERO, target_pos, false, false, false, false, false)
	await get_tree().create_timer(0.1).timeout

	var blink_skill = player.class_node.get("utility_skill")
	_assert(blink_skill != null, "blink skill resolved")
	if blink_skill == null:
		return
	blink_skill.cooldown_left = 0.0
	blink_skill.on_pressed()
	await get_tree().create_timer(0.1).timeout

	var clones := get_tree().get_nodes_in_group("echo_clones")
	_assert(clones.size() == 1, "exactly 1 clone after blink (got %d)" % clones.size())
	if clones.is_empty():
		return
	var clone: Node = clones[0]
	_assert(clone.global_position.distance_to(origin) < 5.0,
		"clone at origin (delta=%.1f)" % clone.global_position.distance_to(origin))
	_assert(int(clone.repeats_left) == 3, "clone repeats_left == 3")
	_assert(player._echo_clone == clone, "player._echo_clone references the clone")

	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.05).timeout
	var near_clone: Vector2 = clone.global_position + Vector2(60, 0)
	arena.spawn_enemy({"type": "tank", "pos": near_clone})
	await get_tree().create_timer(0.05).timeout

	var enemies: Array = _enemies_alive()
	_assert(enemies.size() == 1, "1 enemy spawned")
	if enemies.is_empty():
		return
	var enemy_hp_before: float = enemies[0].hp

	var fb_skill = player.class_node.get("primary_skill")
	_assert(fb_skill != null, "fireball skill resolved")
	if fb_skill == null:
		return
	var mage_target: Vector2 = player.global_position + Vector2(400, 0)
	player.apply_input(Vector2.ZERO, mage_target, false, false, false, false, false)
	await get_tree().create_timer(0.1).timeout
	fb_skill.cooldown_left = 0.0
	fb_skill.on_pressed()
	await get_tree().create_timer(0.25).timeout

	var enemy_hp_after: float = enemies[0].hp
	_assert(enemy_hp_after < enemy_hp_before,
		"enemy hp dropped after clone repeat (before=%.1f after=%.1f)" % [enemy_hp_before, enemy_hp_after])
	_assert(int(clone.repeats_left) == 2, "clone repeats_left == 2 after first repeat")

	# Авто-атаки не повторяются.
	await get_tree().create_timer(1.0).timeout
	_assert(int(clone.repeats_left) >= 1, "clone repeats_left didn't drop on auto-attacks (got %d)" % int(clone.repeats_left))

	for _i in 2:
		fb_skill.cooldown_left = 0.0
		player.mp = player.max_mp
		fb_skill.on_pressed()
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.6).timeout
	clones = get_tree().get_nodes_in_group("echo_clones")
	var alive_clones: Array = []
	for c in clones:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			alive_clones.append(c)
	_assert(alive_clones.is_empty(), "clone gone after 3 repeats (got %d alive)" % alive_clones.size())
	_assert(player._echo_clone == null, "player._echo_clone cleared")

func _enemies_alive() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			out.append(e)
	return out

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[mecho] OK %s" % label)
	else:
		printerr("[mecho] FAIL %s" % label)
		_failures += 1
