extends Node

# Headless verification of the berserker cleave: enemies in front are hit,
# enemies behind are not. Then we apply the legendary upgrade and verify
# that the same auto-tick now also hits the enemy behind. Finally we apply
# the epic dash upgrade and verify that the leap deals AoE damage at the
# landing position.
#
# Run with: godot --headless res://tests/berserker_cleave/berserker_cleave.tscn

const ARENA_SCENE := preload("res://src/world/arena.tscn")

var _failures: int = 0

func _ready() -> void:
	print("[bcleave] starting")
	GameState.roster[1] = {"nick": "BCleave", "klass": &"berserker"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)
	# Wait for arena to settle and player to spawn.
	await get_tree().create_timer(0.4).timeout
	await _run(arena)
	if _failures > 0:
		printerr("[bcleave] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[bcleave] OK")
		get_tree().quit(0)

func _run(arena: Node) -> void:
	var players := get_tree().get_nodes_in_group("players")
	_assert(players.size() >= 1, "player spawned")
	if players.is_empty():
		return
	var player: Node = players[0]
	# В headless InputController каждый физ-тик зовёт apply_input(move=0, aim=mouse_pos)
	# где mouse_pos - дефолтный (-473,-473). Глушим его, чтобы наш test'овый
	# apply_input не перезатирался.
	var input_ctrl := player.get_node_or_null("InputController")
	if input_ctrl != null:
		input_ctrl.set_physics_process(false)
	# Берсерк всегда смотрит вправо в этом тесте; aim_dir обновляется в
	# Player._physics_process из _in_aim, поэтому пропихиваем aim_world через
	# apply_input. Move=ноль чтобы игрок не сдвинулся с позиции.
	var aim_world: Vector2 = player.global_position + Vector2(200, 0)
	player.apply_input(Vector2.ZERO, aim_world, false, false, false, false, false)
	await get_tree().create_timer(0.1).timeout  # дать пройти физ-тику чтобы aim_dir обновился
	_assert(player.aim_dir.x > 0.9, "aim_dir is right (got %.2f, %.2f)" % [player.aim_dir.x, player.aim_dir.y])

	# Очистим начальных enemies, чтобы тест был детерминирован.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	# Кейс 1 — без легендарки: враг ПЕРЕД (вправо) получает урон, враг СЗАДИ (влево) — нет.
	var pos: Vector2 = player.global_position
	arena.spawn_enemy({"type": "rusher", "pos": pos + Vector2(40, 0)})    # перед
	arena.spawn_enemy({"type": "rusher", "pos": pos + Vector2(-40, 0)})   # сзади
	await get_tree().create_timer(0.05).timeout
	# Reapply input — иначе stale-input discard через 0.6s обнулит aim.
	player.apply_input(Vector2.ZERO, aim_world, false, false, false, false, false)
	var enemies: Array = _enemies_alive()
	_assert(enemies.size() == 2, "case1: 2 enemies spawned (got %d)" % enemies.size())
	if enemies.size() < 2:
		return
	# Найдём кто где (front = enemy с большим x).
	var front_enemy: Node = enemies[0] if enemies[0].global_position.x > enemies[1].global_position.x else enemies[1]
	var back_enemy: Node = enemies[1] if enemies[0].global_position.x > enemies[1].global_position.x else enemies[0]
	var hp_front_before: float = front_enemy.hp
	var hp_back_before: float = back_enemy.hp
	# Дождёмся 1 тика автоатаки (cd=0.4, ждём 0.6 чтобы наверняка бахнуло хотя бы раз).
	await get_tree().create_timer(0.6).timeout
	var hp_front_after: float = front_enemy.hp
	var hp_back_after: float = back_enemy.hp
	_assert(hp_front_after < hp_front_before,
		"case1 front took damage (before=%.1f after=%.1f)" % [hp_front_before, hp_front_after])
	_assert(hp_back_after >= hp_back_before - 0.01,
		"case1 back unharmed (before=%.1f after=%.1f)" % [hp_back_before, hp_back_after])

	# Очистка для следующего кейса.
	for e in _enemies_alive():
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	# Кейс 2 — с легендаркой: оба врага получают урон.
	var leg_def: UpgradeDef = Defs.upgrade_def(&"berserker_circle")
	_assert(leg_def != null, "case2: legendary def loaded")
	if leg_def != null:
		player.apply_upgrade_def(leg_def)
	arena.spawn_enemy({"type": "rusher", "pos": pos + Vector2(40, 0)})
	arena.spawn_enemy({"type": "rusher", "pos": pos + Vector2(-40, 0)})
	await get_tree().create_timer(0.05).timeout
	player.apply_input(Vector2.ZERO, aim_world, false, false, false, false, false)
	enemies = _enemies_alive()
	_assert(enemies.size() == 2, "case2: 2 enemies spawned")
	if enemies.size() < 2:
		return
	var front2: Node = enemies[0] if enemies[0].global_position.x > enemies[1].global_position.x else enemies[1]
	var back2: Node = enemies[1] if enemies[0].global_position.x > enemies[1].global_position.x else enemies[0]
	var hp2_front_before: float = front2.hp
	var hp2_back_before: float = back2.hp
	await get_tree().create_timer(0.6).timeout
	var hp2_front_after: float = front2.hp
	var hp2_back_after: float = back2.hp
	_assert(hp2_front_after < hp2_front_before, "case2 front took damage with legendary")
	_assert(hp2_back_after < hp2_back_before, "case2 back ALSO took damage with legendary")

	# Очистка.
	for e in _enemies_alive():
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	# Кейс 3 — эпик «Таран»: рывок наносит AoE на месте приземления.
	var epic_def: UpgradeDef = Defs.upgrade_def(&"epic_berserker_dash_auto")
	_assert(epic_def != null, "case3: epic def loaded")
	if epic_def == null:
		return
	player.apply_upgrade_def(epic_def)
	# Поставим врага на расстоянии leap.distance вправо.
	var landing: Vector2 = player.global_position + Vector2(220, 0)
	arena.spawn_enemy({"type": "rusher", "pos": landing})
	await get_tree().create_timer(0.05).timeout
	enemies = _enemies_alive()
	_assert(enemies.size() == 1, "case3: 1 enemy spawned")
	if enemies.is_empty():
		return
	var hp3_before: float = enemies[0].hp
	# Дёргаем рывок напрямую через class_node (не player).
	var leap: Skill = player.class_node.utility_skill if player.class_node != null else null
	_assert(leap != null, "case3: utility_skill exists")
	if leap == null:
		return
	# Заставляем move_dir смотреть вправо (leap читает move_dir() в первую очередь).
	player.apply_input(Vector2(1, 0), player.global_position + Vector2(220, 0), false, false, false, false, false)
	await get_tree().create_timer(0.05).timeout
	# Сбросим cooldown leap'а в 0 чтобы избежать ready_to_cast=false.
	leap.cooldown_left = 0.0
	leap.on_pressed()
	await get_tree().create_timer(0.05).timeout
	var hp3_after: float = enemies[0].hp
	# damage=12 × 3 × dmg_mult(=1.0) = 36 (минимум, без авто-доп).
	_assert(hp3_before - hp3_after >= 30.0,
		"case3 dash AoE landed major hit (delta=%.1f, expected ≥30)" % (hp3_before - hp3_after))

func _enemies_alive() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			out.append(e)
	return out

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[bcleave] OK %s" % label)
	else:
		printerr("[bcleave] FAIL %s" % label)
		_failures += 1
