extends Node

# Headless verification of the orc-shaman boss state machine:
#  1. Spawns with cage_radius initialised and cage_state=0 (idle).
#  2. Forced idle→windup: cage_state=1, target locked, center pinned.
#  3. After windup duration, cage_state→2 (active) and the targeted player
#     gets yanked back inside when teleported out.
#  4. After cage duration, cage_state→0 (auto-expired).
#  5. If the targeted player dies mid-windup, the cast cancels at the
#     windup→active transition (cage_state stays 0).
#
# Run with: godot --headless res://tests/orc_boss/orc_boss.tscn

const ARENA_SCENE := preload("res://src/world/arena.tscn")
const WINDUP_DURATION := 1.5
const CAGE_DURATION := 5.0

var _failures: int = 0

func _ready() -> void:
	print("[orc_boss] starting")
	GameState.roster[1] = {"nick": "Orc", "klass": &"berserker"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)
	await get_tree().create_timer(0.4).timeout
	await _run(arena)
	if _failures > 0:
		printerr("[orc_boss] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[orc_boss] OK")
		get_tree().quit(0)

func _run(arena: Node) -> void:
	var players := get_tree().get_nodes_in_group("players")
	_assert(players.size() >= 1, "player spawned")
	if players.is_empty():
		return
	var player: CharacterBody2D = players[0]
	# Глушим default-input — иначе apply_input(0, mouse_pos) перетирает позицию.
	var input_ctrl := player.get_node_or_null("InputController")
	if input_ctrl != null:
		input_ctrl.set_physics_process(false)
	# Чистим случайный ростер врагов от первой волны, чтобы тест был детерминирован.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	# Спавним орк-босса на 500px справа от игрока.
	arena.spawn_enemy({"type": "orc_boss", "pos": player.global_position + Vector2(500, 0)})
	await get_tree().create_timer(0.1).timeout
	var orc: Node = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.enemy_type == &"orc_boss":
			orc = e
			break
	_assert(orc != null, "orc_boss spawned")
	if orc == null:
		return
	_assert(orc.cage_radius > 0.0, "cage_radius initialised at setup (got %.1f)" % orc.cage_radius)
	_assert(orc.cage_state == 0, "cage_state starts idle (got %d)" % orc.cage_state)

	# Форсируем windup: AI стартует с _idle_left=0.5, обнуляем чтобы переход
	# случился на следующем тике вне зависимости от тайминга.
	orc.ai._idle_left = 0.0
	await get_tree().create_timer(0.1).timeout
	_assert(orc.cage_state == 1, "cage_state→1 (windup) after idle elapsed (got %d)" % orc.cage_state)
	_assert(orc.cage_target_peer == int(player.peer_id),
		"cage targets the only alive player (peer=%d, expected=%d)" % [orc.cage_target_peer, int(player.peer_id)])
	# Точка каста = позиция игрока в момент входа в windup (с допуском на физ-тик).
	var cast_dist: float = orc.cage_center.distance_to(player.global_position)
	_assert(cast_dist < 50.0, "cage center near player position at cast (delta=%.1f)" % cast_dist)

	# Ждём конец windup → переход в active.
	await get_tree().create_timer(WINDUP_DURATION + 0.1).timeout
	_assert(orc.cage_state == 2, "cage_state→2 (active) after windup (got %d)" % orc.cage_state)

	# В active фазе игрока должно затаскивать обратно. Телепортируем за границу.
	var cage_center: Vector2 = orc.cage_center
	var outside: Vector2 = cage_center + Vector2(0, 600)
	player.global_position = outside
	# PULL_SPEED=900px/s, overshoot=320, нужно ~0.36s.
	await get_tree().create_timer(0.6).timeout
	var dist_after_pull: float = player.global_position.distance_to(cage_center)
	_assert(dist_after_pull <= orc.cage_radius + 5.0,
		"player pulled inside cage in active phase (dist=%.1f, radius=%.1f)" % [dist_after_pull, orc.cage_radius])

	# Дожидаемся auto-expire: 5s active − 0.6 уже прошло − небольшой запас.
	await get_tree().create_timer(CAGE_DURATION - 0.6 + 0.2).timeout
	_assert(orc.cage_state == 0, "cage auto-expires after CAGE_DURATION (got %d)" % orc.cage_state)

	# Сценарий «срыв каста»: форсируем windup, убиваем цель, на переходе
	# windup→active каст должен отмениться (state остаётся 0).
	orc.ai._idle_left = 0.0
	await get_tree().create_timer(0.1).timeout
	_assert(orc.cage_state == 1, "cage_state→1 on second forced windup (got %d)" % orc.cage_state)
	# downed_until ставим в будущее — иначе Player._physics_process сам вызовет
	# _respawn() на следующем тике и тест провалится.
	player.alive = false
	player.downed_until = (Time.get_ticks_msec() / 1000.0) + 30.0
	await get_tree().create_timer(WINDUP_DURATION + 0.2).timeout
	_assert(orc.cage_state == 0, "cast cancelled at windup→active when target dead (got %d)" % orc.cage_state)

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[orc_boss] OK %s" % label)
	else:
		printerr("[orc_boss] FAIL %s" % label)
		_failures += 1
