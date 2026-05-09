extends Node

# Headless verification of WaveDirector orc-shaman scheduling:
#  1. До t=120 орк не спавнится.
#  2. На t>=120 орк спавнится ровно один раз; повторный физ-тик НЕ создаёт
#     второго (гейт «один на карте»).
#  3. Если убить орка, до истечения 2-минутного cooldown'а с прошлого спавна
#     новый не появляется.
#  4. После того как cooldown истёк И орк убит, на следующем тике появляется
#     ровно один новый орк.
#
# Run with: godot --headless res://tests/orc_boss_spawn/orc_boss_spawn.tscn

const ARENA_SCENE := preload("res://src/world/arena.tscn")
const ORC_INTERVAL := 120.0

var _failures: int = 0

func _ready() -> void:
	print("[orc_spawn] starting")
	GameState.roster[1] = {"nick": "OrcSpawn", "klass": &"berserker"}
	var arena: Node = ARENA_SCENE.instantiate()
	add_child(arena)
	await get_tree().create_timer(0.4).timeout
	await _run(arena)
	if _failures > 0:
		printerr("[orc_spawn] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[orc_spawn] OK")
		get_tree().quit(0)

func _run(_arena: Node) -> void:
	# Чистим случайных врагов от первой волны и зануляем accumулятор спавнов,
	# чтобы они не лезли посреди тестовых проверок.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	var wd := _wave_director()
	_assert(wd != null, "wave_director found")
	if wd == null:
		return
	# Глушим обычные волны, чтобы не дёргали HARD_CAP и не путали ассерты по
	# наличию орка: заставляем waves'ы быть «между фазами».
	wd._spawn_accum = 0.0
	wd._burst_accum = 0.0

	# Случай 1: t < 120 — орк не спавнится.
	GameState.run_time = 60.0
	wd._orc_last_spawn_at = 0.0
	await get_tree().create_timer(0.1).timeout
	_assert(_count_orc_alive() == 0, "no orc before t=120 (got %d)" % _count_orc_alive())

	# Случай 2: t=121 — должен заспавниться один. Прокидываем _orc_last_spawn_at=0
	# чтобы гейт интервала был ровно на границе.
	_clear_enemies()
	GameState.run_time = 121.0
	wd._orc_last_spawn_at = 0.0
	await get_tree().create_timer(0.1).timeout
	_assert(_count_orc_alive() == 1, "exactly one orc after t>=120 (got %d)" % _count_orc_alive())
	# Сразу же ещё несколько тиков — гейт «один на карте» не должен пустить
	# второго.
	await get_tree().create_timer(0.2).timeout
	_assert(_count_orc_alive() == 1, "second orc blocked while first alive (got %d)" % _count_orc_alive())

	# Случай 3: убиваем орка ДО того как cooldown истёк — нового орка быть не
	# должно (cooldown с прошлого спавна 2 мин, прошло ~0.3с).
	_kill_orc()
	await get_tree().create_timer(0.2).timeout
	_assert(_count_orc_alive() == 0, "orc dead and cooldown not elapsed (got %d)" % _count_orc_alive())

	# Случай 4: прошёл cooldown (run_time прыгнул вперёд на >120c с прошлого
	# спавна) И орк мёртв — на следующем тике появляется новый.
	GameState.run_time = wd._orc_last_spawn_at + ORC_INTERVAL + 1.0
	await get_tree().create_timer(0.1).timeout
	_assert(_count_orc_alive() == 1, "new orc spawns after cooldown elapsed (got %d)" % _count_orc_alive())

func _wave_director() -> Node:
	for n in get_tree().get_nodes_in_group("arena"):
		var wd = n.get_node_or_null("WaveDirector")
		if wd != null:
			return wd
	# Фолбэк: ищем по всему дереву.
	return get_tree().root.find_child("WaveDirector", true, false)

func _count_orc_alive() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if e.alive and e.enemy_type == &"orc_boss":
			n += 1
	return n

func _kill_orc() -> void:
	# xp_value=0, чтобы убийство не дёрнуло level_up + upgrade-screen, который
	# поставил бы дерево на паузу и сорвал последующие проверки тика.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.enemy_type == &"orc_boss":
			e.xp_value = 0
			e.apply_damage(99999.0, "player")

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[orc_spawn] OK %s" % label)
	else:
		printerr("[orc_spawn] FAIL %s" % label)
		_failures += 1
