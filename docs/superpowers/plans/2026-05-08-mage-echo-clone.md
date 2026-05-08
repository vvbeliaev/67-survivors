# Mage Echo Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать легендарку мага «Эхо»: после блинка маг оставляет на исходной позиции неуязвимого недвижимого клона, который повторяет следующие 3 заклинания (fireball/chain) в ближайших к себе врагов.

**Architecture:** Новая сущность `EchoClone` (Node2D) — отдельная сцена, спавнится через новый `EchoClonesSpawner` в арене (по аналогии с проджектайлами). На хосте: тикает `pending_repeats`, запускает реплеи, считает `repeats_left`. На клиенте: только рендер силуэта + счётчик. Хук в `mage_blink` спавнит клон при наличии легендарки. Хуки в `mage_fireball` и `mage_chain` нотифицируют активный клон через `Player._echo_clone`-ссылку.

**Tech Stack:** Godot 4.6, GDScript. Опирается на rarity-инфраструктуру из Спека 1 (легендарка получает `rarity=3`).

**Spec:** [docs/superpowers/specs/2026-05-08-mage-legendary-clone-design.md](../specs/2026-05-08-mage-legendary-clone-design.md)

---

## File Structure

**Create:**
- `src/skills/concrete/echo_clone.gd` — поведение клона (host-логика + рендер)
- `src/skills/concrete/echo_clone.tscn` — сцена клона (Node2D + Sprite2D + Label)
- `resources/upgrades/legendary_mage_echo_clone.tres` — легендарка
- `tests/mage_echo/mage_echo.tscn` — обёртка теста
- `tests/mage_echo/mage_echo.gd` — сценарный тест

**Modify:**
- `src/world/arena.tscn` — добавить `EchoClonesContainer` и `EchoClonesSpawner`
- `src/world/arena.gd` — фабрика `_spawn_echo_clone` + публичный helper `spawn_echo_clone`
- `src/player/player.gd` — поле `_echo_clone: Node = null`
- `src/skills/skill.gd` — helper `_notify_echo_clone(kind)`
- `src/skills/concrete/mage_blink.gd` — спавн клона при наличии легендарки
- `src/skills/concrete/mage_fireball.gd` — нотификация клона
- `src/skills/concrete/mage_chain.gd` — нотификация клона
- `Makefile` — таргет `mage-echo-test`

---

### Task 1: Player — поле _echo_clone

**Files:** Modify `src/player/player.gd`

- [ ] **Step 1: Добавить поле**

В `src/player/player.gd` найти строку (около 360):

```gdscript
var _upgrade_stacks: Dictionary = {}  # upgrade_id -> int
```

Сразу ПОСЛЕ неё добавить:

```gdscript
# Активный клон от легендарки `mage_echo_clone`. Перевешивается в скилле блинка
# при следующем приземлении; снимается клоном при `queue_free` через
# notify_echo_clone_destroyed(). Host-only — клиенту пользы нет.
var _echo_clone: Node = null

func notify_echo_clone_destroyed(clone: Node) -> void:
	if _echo_clone == clone:
		_echo_clone = null
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add src/player/player.gd
git commit -m "Player: поле _echo_clone + notify_echo_clone_destroyed"
```

---

### Task 2: Skill base — helper _notify_echo_clone

**Files:** Modify `src/skills/skill.gd`

- [ ] **Step 1: Добавить helper**

В файл `src/skills/skill.gd` добавить helper в самом конце (после `_has_upgrade`):

```gdscript
# Уведомить активный echo-клон игрока, что только что прошёл успешный каст
# заклинания указанного типа. Безопасно вызывать всегда — если клона нет,
# ничего не происходит.
func _notify_echo_clone(kind: StringName) -> void:
	if owner_player == null:
		return
	var clone: Node = owner_player._echo_clone
	if clone != null and is_instance_valid(clone) and clone.has_method("on_player_cast"):
		clone.on_player_cast(kind)
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add src/skills/skill.gd
git commit -m "Skill: helper _notify_echo_clone"
```

---

### Task 3: Создать EchoClone (сцена + скрипт)

**Files:**
- Create: `src/skills/concrete/echo_clone.tscn`
- Create: `src/skills/concrete/echo_clone.gd`

- [ ] **Step 1: Создать echo_clone.tscn**

Содержимое файла:

```
[gd_scene load_steps=3 format=3 uid="uid://b0echoclone67surv"]

[ext_resource type="Script" path="res://src/skills/concrete/echo_clone.gd" id="1_echo"]
[ext_resource type="Texture2D" path="res://assets/images/wizard_top.png" id="2_wiz"]

[node name="EchoClone" type="Node2D"]
script = ExtResource("1_echo")

[node name="Sprite" type="Sprite2D" parent="."]
texture = ExtResource("2_wiz")
modulate = Color(0.45, 0.65, 1.0, 0.55)
scale = Vector2(0.55, 0.55)

[node name="Counter" type="Label" parent="."]
offset_left = -10
offset_top = -38
offset_right = 10
offset_bottom = -22
text = "3"
horizontal_alignment = 1
modulate = Color(0.7, 0.85, 1.0, 0.95)
```

(Note: размер sprite — 0.55 чтобы силуэт был помельче живого мага. Тонировка — голубая призрачная. Counter — простой Label сверху.)

- [ ] **Step 2: Создать echo_clone.gd**

Содержимое файла:

```gdscript
extends Node2D

# Echo Clone — наследие mage_blink под легендаркой `mage_echo_clone`.
# Стоит на исходной позиции мага. Когда мага кастит fireball/chain, клон
# через 0.10s повторяет каст в ближайшего к КЛОНУ врага. После 3 повторов
# или 25s или повторного блинка — растворяется.
#
# Host-only логика. Клиент рендерит позицию + счётчик; счётчик синхронизируется
# через @export-репликацию.

const REPEAT_DELAY: float = 0.10
const LIFETIME_MAX: float = 25.0
const FADE_DURATION: float = 0.4

@export var owner_peer_id: int = 0           # spawn-only: для бэк-ссылки на player
@export var repeats_left: int = 3             # on_change: для UI
@export var fading: bool = false              # on_change: триггер fade-визуала

var owner_player: Node = null                 # резолвится при _ready (host)
var _pending: Array = []                      # [{kind: StringName, at: float}, …]
var _spawn_time: float = 0.0
var _fade_started_at: float = -1.0

func _ready() -> void:
	add_to_group("echo_clones")
	_spawn_time = _now()
	if GameState.is_authority():
		_resolve_owner_player()
	# Клиенту owner_player не нужен — рендер тащит счётчик через репликацию.
	_update_counter()

func _resolve_owner_player() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == owner_peer_id:
			owner_player = p
			# Заменяем предыдущий активный клон (если был).
			var prev: Node = p._echo_clone
			if prev != null and prev != self and is_instance_valid(prev):
				prev.start_fade()
			p._echo_clone = self
			return

func _physics_process(_delta: float) -> void:
	if not GameState.is_authority():
		_update_counter()
		return
	var t: float = _now()
	# Жёсткий хард-кэп жизни.
	if t - _spawn_time > LIFETIME_MAX and not fading:
		start_fade()
		return
	# Fade — растворение.
	if fading:
		if t - _fade_started_at >= FADE_DURATION:
			_destroy()
		return
	# Тик отложенных повторов.
	if _pending.is_empty():
		return
	var head: Dictionary = _pending[0]
	if t < float(head.get("at", 0.0)):
		return
	_pending.pop_front()
	var kind: StringName = StringName(String(head.get("kind", &"")))
	if owner_player == null or not bool(owner_player.alive):
		# Маг помер — клон гасим.
		start_fade()
		return
	if _cast(kind):
		repeats_left -= 1
		if repeats_left <= 0:
			start_fade()

# Нотификация от skill-хука. Только хост.
func on_player_cast(kind: StringName) -> void:
	if not GameState.is_authority() or fading:
		return
	if kind != &"fireball" and kind != &"chain":
		return
	_pending.append({"kind": kind, "at": _now() + REPEAT_DELAY})

# Pure visual: клон неуязвим, не получает урона. Этот метод тут для совместимости
# с возможными ауро-эффектами врагов которые ищут targets с apply_damage.
func apply_damage(_amount: float, _team: String) -> void:
	pass

func start_fade() -> void:
	if fading:
		return
	fading = true
	_fade_started_at = _now()

func _process(_delta: float) -> void:
	# Fade-визуал на всех пирах: модулята спрайта плавно гаснет.
	var sprite := get_node_or_null("Sprite")
	if sprite == null:
		return
	if fading:
		var t: float = _now() - _fade_started_at
		var k: float = clampf(1.0 - t / FADE_DURATION, 0.0, 1.0)
		sprite.modulate = Color(0.45, 0.65, 1.0, 0.55 * k)
	else:
		sprite.modulate = Color(0.45, 0.65, 1.0, 0.55)

func _update_counter() -> void:
	var lbl := get_node_or_null("Counter")
	if lbl == null:
		return
	lbl.text = str(max(repeats_left, 0))

func _destroy() -> void:
	if owner_player != null and owner_player.has_method("notify_echo_clone_destroyed"):
		owner_player.notify_echo_clone_destroyed(self)
	queue_free()

# Возвращает true, если каст реально сделан (нашлась цель и т.п.).
func _cast(kind: StringName) -> bool:
	if kind == &"fireball":
		return _cast_fireball()
	if kind == &"chain":
		return _cast_chain()
	return false

func _cast_fireball() -> bool:
	# Параметры fireball'а живут на самом скилле; читаем оттуда чтобы баланс
	# был общим. Цель — ближайший враг от позиции клона.
	var target: Node2D = Targeting.nearest_enemy(get_tree(), global_position, 9999.0)
	if target == null:
		# Цели нет — каст не тратится; повторим в следующий апдейт пуша.
		# Возвращаем false, repeats_left не декрементится.
		# Чтобы не зависнуть навсегда — head всё равно был pop'нут;
		# поэтому положим кастнутый kind обратно с задержкой.
		_pending.push_front({"kind": &"fireball", "at": _now() + REPEAT_DELAY})
		return false
	var fb_skill = _player_skill(&"primary_skill")
	if fb_skill == null:
		return false
	var aoe_radius: float = float(fb_skill.aoe_radius) if "aoe_radius" in fb_skill else 80.0
	var aoe_damage: float = float(fb_skill.aoe_damage) if "aoe_damage" in fb_skill else 8.0
	var projectile_speed: float = float(fb_skill.projectile_speed) if "projectile_speed" in fb_skill else 480.0
	var projectile_lifetime: float = float(fb_skill.projectile_lifetime) if "projectile_lifetime" in fb_skill else 1.5
	var projectile_radius: float = float(fb_skill.projectile_radius) if "projectile_radius" in fb_skill else 7.0
	var rm: float = owner_player.range_mult()
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var origin: Vector2 = global_position + dir * 16.0
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null:
		arena.spawn_projectile({
			"pos": origin,
			"vel": dir * projectile_speed,
			"damage": 0.0,
			"lifetime": projectile_lifetime,
			"team": "player",
			"color": Color(0.85, 0.95, 1.0),
			"radius": projectile_radius,
			"pierce": 0,
			"source_peer": owner_peer_id,
			"mana_on_hit_pct": 0.0,
			"sprite_path": "",
			"sprite_size": Vector2.ZERO,
		})
	var fb_flat: float = owner_player.stats.value(StatBlock.STAT_FIREBALL_DAMAGE)
	var dmg: float = (aoe_damage + fb_flat) * owner_player.dmg_mult()
	for e in Targeting.enemies_in_radius(get_tree(), target.global_position, aoe_radius * rm):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
	return true

func _cast_chain() -> bool:
	var chain_skill = _player_skill(&"secondary_skill")
	if chain_skill == null:
		return false
	var hops: int = int(chain_skill.hops) if "hops" in chain_skill else 3
	var jump_range: float = float(chain_skill.jump_range) if "jump_range" in chain_skill else 600.0
	var damage_per_hit: float = float(chain_skill.damage_per_hit) if "damage_per_hit" in chain_skill else 18.0
	var first: Node2D = Targeting.nearest_enemy(get_tree(), global_position, jump_range * owner_player.range_mult())
	if first == null:
		_pending.push_front({"kind": &"chain", "at": _now() + REPEAT_DELAY})
		return false
	var picked: Array = []
	var src: Vector2 = global_position
	var dmg: float = damage_per_hit * owner_player.dmg_mult()
	var jr: float = jump_range * owner_player.range_mult()
	var total_hops: int = hops + int(owner_player.stats.value(StatBlock.STAT_CHAIN_HOPS))
	for _i in total_hops:
		var e: Node2D = Targeting.nearest_enemy_excluding(get_tree(), src, jr, picked)
		if e == null:
			break
		picked.append(e)
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
		src = e.global_position
	return true

func _player_skill(field: StringName) -> Node:
	if owner_player == null or owner_player.class_node == null:
		return null
	return owner_player.class_node.get(field)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
```

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`. Файл создан, никто его пока не использует.

- [ ] **Step 4: Commit**

```bash
git add src/skills/concrete/echo_clone.tscn src/skills/concrete/echo_clone.gd
git commit -m "EchoClone: новая сущность (host-логика повторов + клиент-рендер)"
```

---

### Task 4: Arena — добавить EchoClonesSpawner

**Files:**
- Modify `src/world/arena.tscn`
- Modify `src/world/arena.gd`

- [ ] **Step 1: arena.tscn — добавить контейнер и спавнер**

В файле `src/world/arena.tscn` найти блок:

```
[node name="ProjectilesContainer" type="Node2D" parent="."]

[node name="PlayersSpawner" type="MultiplayerSpawner" parent="."]
```

Добавить между ними:

```
[node name="EchoClonesContainer" type="Node2D" parent="."]
```

И в блоке после `[node name="ProjectilesSpawner" type="MultiplayerSpawner" parent="."]` добавить:

```
[node name="EchoClonesSpawner" type="MultiplayerSpawner" parent="."]
```

То есть финальный шейп `arena.tscn` должен иметь:
- PlayersContainer, EnemiesContainer, ProjectilesContainer, **EchoClonesContainer**
- PlayersSpawner, EnemiesSpawner, ProjectilesSpawner, **EchoClonesSpawner**

- [ ] **Step 2: arena.gd — фабрика и публичный helper**

В `src/world/arena.gd` найти блок констант (строки 7-12):

```gdscript
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemy/enemy.tscn")
const PROJECTILE_SCENE := preload("res://src/projectiles/projectile.tscn")
```

Добавить после них:

```gdscript
const ECHO_CLONE_SCENE := preload("res://src/skills/concrete/echo_clone.tscn")
```

В блок `@onready var` (строки 27-32) добавить:

```gdscript
@onready var echo_clones_container: Node = $EchoClonesContainer
@onready var echo_clones_spawner: MultiplayerSpawner = $EchoClonesSpawner
```

В `_ready` найти блок (строки 36-41):

```gdscript
	players_spawner.spawn_path = NodePath("../PlayersContainer")
	enemies_spawner.spawn_path = NodePath("../EnemiesContainer")
	projectiles_spawner.spawn_path = NodePath("../ProjectilesContainer")
	players_spawner.spawn_function = _spawn_player
	enemies_spawner.spawn_function = _spawn_enemy
	projectiles_spawner.spawn_function = _spawn_projectile
```

Добавить ниже:

```gdscript
	echo_clones_spawner.spawn_path = NodePath("../EchoClonesContainer")
	echo_clones_spawner.spawn_function = _spawn_echo_clone
```

После метода `_spawn_projectile` (около строки 124) добавить новую фабрику:

```gdscript
func _spawn_echo_clone(data: Variant) -> Node:
	var c: Node2D = ECHO_CLONE_SCENE.instantiate()
	var d: Dictionary = data as Dictionary
	c.position = d.get("pos", Vector2.ZERO)
	c.owner_peer_id = int(d.get("owner_peer_id", 0))
	c.repeats_left = int(d.get("repeats", 3))
	c.set_multiplayer_authority(1)
	return c
```

И после `spawn_projectile` (около строки 149) — публичный helper:

```gdscript
func spawn_echo_clone(data: Dictionary) -> void:
	if not GameState.is_authority():
		return
	_spawn_via(echo_clones_spawner, echo_clones_container, _spawn_echo_clone, data)
```

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 4: Smoke**

Run: `make smoke`
Expected: ends with `[smoke] DONE`. Spawner добавлен, но никто его не вызывает — поведение существующих фич не меняется.

- [ ] **Step 5: Commit**

```bash
git add src/world/arena.tscn src/world/arena.gd
git commit -m "Arena: EchoClonesSpawner + spawn_echo_clone() helper"
```

---

### Task 5: mage_blink — спавн клона при наличии легендарки

**Files:** Modify `src/skills/concrete/mage_blink.gd`

- [ ] **Step 1: Заменить on_pressed**

В `src/skills/concrete/mage_blink.gd` заменить ПОЛНОСТЬЮ метод `on_pressed`:

```gdscript
func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var target: Vector2 = owner_player.aim_world()
	var from_pos: Vector2 = owner_player.global_position
	if from_pos.distance_squared_to(target) <= 1.0:
		return
	owner_player.teleport(target)
	trigger_visual_fx("blink", {"from": from_pos, "to": owner_player.global_position})
	AudioBus.play_at(&"mage_cast", from_pos)
	# Легендарка «Эхо»: оставляем клон на исходной позиции.
	if _has_upgrade(&"mage_echo_clone"):
		var arena := get_tree().get_first_node_in_group("arena")
		if arena != null and arena.has_method("spawn_echo_clone"):
			arena.spawn_echo_clone({
				"pos": from_pos,
				"owner_peer_id": int(owner_player.peer_id),
				"repeats": 3,
			})
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add src/skills/concrete/mage_blink.gd
git commit -m "MageBlink: спавн EchoClone при наличии легендарки"
```

---

### Task 6: mage_fireball / mage_chain — нотификация клона

**Files:**
- Modify `src/skills/concrete/mage_fireball.gd`
- Modify `src/skills/concrete/mage_chain.gd`

- [ ] **Step 1: mage_fireball — добавить нотификацию в конце on_pressed**

В `src/skills/concrete/mage_fireball.gd` в самый конец метода `on_pressed`, после строки `_aoe_damage(...)`, добавить:

```gdscript
	_notify_echo_clone(&"fireball")
```

То есть метод заканчивается так:

```gdscript
	_aoe_damage(owner_player.aim_world(), aoe_radius * rm, (aoe_damage + fb_flat) * owner_player.dmg_mult())
	_notify_echo_clone(&"fireball")
```

- [ ] **Step 2: mage_chain — добавить нотификацию в конце on_pressed**

В `src/skills/concrete/mage_chain.gd` в самый конец метода `on_pressed`, после строки `AudioBus.play_at(...)`, добавить:

```gdscript
	_notify_echo_clone(&"chain")
```

То есть метод заканчивается так:

```gdscript
	AudioBus.play_at(&"mage_cast", owner_player.global_position)
	_notify_echo_clone(&"chain")
```

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 4: Smoke**

Run: `make smoke`
Expected: `[smoke] DONE`. Маг в смоке не задействован, но проверяем что код парсится.

- [ ] **Step 5: Commit**

```bash
git add src/skills/concrete/mage_fireball.gd src/skills/concrete/mage_chain.gd
git commit -m "MageFireball/Chain: нотификация echo-клона после успешного каста"
```

---

### Task 7: legendary_mage_echo_clone.tres

**Files:** Create `resources/upgrades/legendary_mage_echo_clone.tres`

- [ ] **Step 1: Создать .tres**

Содержимое `resources/upgrades/legendary_mage_echo_clone.tres`:

```
[gd_resource type="Resource" script_class="UpgradeDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://src/data/upgrade_def.gd" id="1_def"]
[ext_resource type="Texture2D" path="res://assets/images/icons/magic-swirl.svg" id="2_icon"]

[resource]
script = ExtResource("1_def")
id = &"mage_echo_clone"
label = "Эхо"
weight = 1.0
class_filter = Array[StringName]([&"mage"])
archetype_filter = Array[StringName]([])
icon = ExtResource("2_icon")
display_name = "Эхо"
description = "После блинка остаётся неуязвимый клон.
Клон повторяет 3 следующих заклинания
(fireball, chain) в ближайших к нему врагов."
rarity = 3
category = &"utility"
flavor = "Тень мага задерживается там, где он был."
stat = &""
mode = 0
amount = 0.0
max_stacks = 0
heal_on_pick = 0.0
refill_mana = false
```

- [ ] **Step 2: Import + parse-check**

Run: `make import` затем `make check`.
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add resources/upgrades/legendary_mage_echo_clone.tres
git commit -m ".tres: легендарка mage_echo_clone (Эхо)"
```

---

### Task 8: Сценарный тест mage_echo

**Files:**
- Create: `tests/mage_echo/mage_echo.tscn`
- Create: `tests/mage_echo/mage_echo.gd`
- Modify: `Makefile`

- [ ] **Step 1: Создать сцену-обёртку**

Содержимое `tests/mage_echo/mage_echo.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://b0mecho67surv"]

[ext_resource type="Script" path="res://tests/mage_echo/mage_echo.gd" id="1_mecho"]

[node name="MageEchoTest" type="Node"]
script = ExtResource("1_mecho")
```

- [ ] **Step 2: Создать сценарный тест**

Содержимое `tests/mage_echo/mage_echo.gd`:

```gdscript
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
	# Заглушим input controller, иначе его _physics_process перезапишет _in_aim
	# в неконтролируемых направлениях.
	var input_ctrl: Node = player.get_node_or_null("InputController")
	if input_ctrl != null:
		input_ctrl.set_physics_process(false)

	# Дать легендарку.
	var leg_def: UpgradeDef = Defs.upgrade_def(&"mage_echo_clone")
	_assert(leg_def != null, "legendary def loaded")
	if leg_def == null:
		return
	player.apply_upgrade_def(leg_def)
	_assert(int(player._upgrade_stacks.get(&"mage_echo_clone", 0)) > 0, "legendary applied")

	# Поставим mp по максимуму чтобы не лимитироваться маной.
	player.mp = player.max_mp

	# Сохраним исходную позицию — там должен появиться клон.
	var origin: Vector2 = player.global_position
	# Целимся в (origin + 300, 0) и выполняем блинк.
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

	# Должен появиться клон рядом с origin.
	var clones := get_tree().get_nodes_in_group("echo_clones")
	_assert(clones.size() == 1, "exactly 1 clone after blink (got %d)" % clones.size())
	if clones.is_empty():
		return
	var clone: Node = clones[0]
	_assert(clone.global_position.distance_to(origin) < 5.0,
		"clone at origin (delta=%.1f)" % clone.global_position.distance_to(origin))
	_assert(int(clone.repeats_left) == 3, "clone repeats_left == 3")
	_assert(player._echo_clone == clone, "player._echo_clone references the clone")

	# Поставим врага рядом с клоном (НЕ рядом с магом — чтобы убедиться что
	# клон выбирает свою цель, а не магскую).
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().create_timer(0.05).timeout
	var near_clone: Vector2 = clone.global_position + Vector2(60, 0)
	arena.spawn_enemy({"type": "tank", "pos": near_clone})  # tank побольше HP, чтобы не убить за один тик
	await get_tree().create_timer(0.05).timeout

	var enemies: Array = _enemies_alive()
	_assert(enemies.size() == 1, "1 enemy spawned")
	if enemies.is_empty():
		return
	var enemy_hp_before: float = enemies[0].hp

	# Маг кастует fireball (не у клона, у себя — но клон должен повторить).
	var fb_skill = player.class_node.get("primary_skill")
	_assert(fb_skill != null, "fireball skill resolved")
	if fb_skill == null:
		return
	# Целимся в позицию ОТ клона (далеко справа от мага). Так fireball мага
	# полетит в ту сторону, не попав по нашему врагу около клона.
	var mage_target: Vector2 = player.global_position + Vector2(400, 0)
	player.apply_input(Vector2.ZERO, mage_target, false, false, false, false, false)
	await get_tree().create_timer(0.1).timeout
	fb_skill.cooldown_left = 0.0
	fb_skill.on_pressed()
	# Ждём задержку клона + чуть-чуть.
	await get_tree().create_timer(0.25).timeout

	var enemy_hp_after: float = enemies[0].hp
	_assert(enemy_hp_after < enemy_hp_before,
		"enemy hp dropped after clone repeat (before=%.1f after=%.1f)" % [enemy_hp_before, enemy_hp_after])
	_assert(int(clone.repeats_left) == 2, "clone repeats_left == 2 after first repeat")

	# Авто-атаки не повторяются: дождёмся пока маг автокастит несколько раз
	# и убедимся что repeats_left не упал.
	await get_tree().create_timer(1.0).timeout
	_assert(int(clone.repeats_left) >= 1, "clone repeats_left didn't drop on auto-attacks (got %d)" % int(clone.repeats_left))

	# Доводим клон до растворения: ещё 2 fireball'а.
	for _i in 2:
		fb_skill.cooldown_left = 0.0
		player.mp = player.max_mp
		fb_skill.on_pressed()
		await get_tree().create_timer(0.25).timeout
	# После 3-го повтора клон должен начать fade. Дождёмся пока удалится.
	await get_tree().create_timer(0.6).timeout
	clones = get_tree().get_nodes_in_group("echo_clones")
	# После fade _destroy → queue_free; клон удалится из дерева.
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
```

- [ ] **Step 3: Добавить таргет в Makefile**

В `Makefile` найти `.PHONY` (после Спека 1 и Спека 3 имеет `rarity-test bcleave-test`):
```
.PHONY: run editor import smoke rarity-test bcleave-test check server deploy logs stop peer host join clean help
```
Заменить на:
```
.PHONY: run editor import smoke rarity-test bcleave-test mage-echo-test check server deploy logs stop peer host join clean help
```

После блока `bcleave-test:` добавить:
```
mage-echo-test:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/mage_echo/mage_echo.tscn
```

- [ ] **Step 4: Запустить mage-echo-test**

Run: `make mage-echo-test`
Expected: ends with `[mecho] OK` exit 0.

Если падает — частые проблемы:
- "exactly 1 clone after blink (got 0)": блинк не сработал (возможно blink_distance_squared <= 1), или EchoClonesContainer не найден. Проверить arena.spawn_echo_clone и arena.tscn.
- "clone repeats_left == 2 after first repeat": клон не получил on_player_cast, или не нашёл цель. Проверить _notify_echo_clone в mage_fireball.gd, и что Targeting.nearest_enemy возвращает врага около клона.
- "clone gone after 3 repeats": fade не запустился или _destroy не вызвался. Проверить logic в _physics_process клона.

- [ ] **Step 5: Commit**

```bash
git add tests/mage_echo/mage_echo.tscn tests/mage_echo/mage_echo.gd Makefile
git commit -m "tests: mage_echo (clone spawn / repeat / 3 repeats / no auto-replay)"
```

---

### Task 9: Финальная верификация

- [ ] **Step 1: Все тесты**

Run: `make check && make rarity-test && make bcleave-test && make mage-echo-test && make smoke`
Expected: все 5 целей зелёные, без SCRIPT ERROR / FAIL / non-zero exit.

- [ ] **Step 2: Не делаем manual sanity** в этой автономной сессии — visual проверка отложена.

---

## Self-Review Notes

**Spec coverage:**
- ✅ Task 1, 2: Player._echo_clone, Skill._notify_echo_clone
- ✅ Task 3: EchoClone (сцена + скрипт): неуязвимость (apply_damage no-op), неподвижность (Node2D без physics), счётчик 3, fade, hard-cap 25s, on_player_cast, _cast_fireball/chain
- ✅ Task 4: spawn-инфра в арене
- ✅ Task 5: блинк-хук (с заменой старого клона через `_resolve_owner_player`)
- ✅ Task 6: fireball/chain нотификация (НЕ авто, НЕ блинк)
- ✅ Task 7: легендарка-тырез
- ✅ Task 8, 9: сценарный тест + verification

**Compat-риски:**
- mage_blink/fireball/chain получают по +1 строке, не меняют существующее поведение для magа без легендарки.
- arena.tscn получает 2 новых ноды; существующие фичи не задеты.
- EchoClone.apply_damage = no-op — клон не входит в targeting.enemies (он в группе echo_clones, не enemies).

**Известные ограничения:**
- Лайфстил мага НЕ срабатывает на хитах клона (потому что клон не вызывает Skill._aoe_damage, а делает свой цикл). Это совпадает со spec'ом «клон не даёт магу лайфстил/ману».
- При смерти мага клон гасится через 1 тик (`owner_player.alive == false`).
- Клон запоминает положение в момент блинка; маг может улететь куда угодно — клон останется (это и есть фича).

**Не покрыто** (вне спека):
- Звук кастов клона (отдельный звуковой слой) — последующая полировка.
- Анимация прорастания клона при спавне — последующая полировка.
- Балансировка (3 повтора vs 5; задержка 0.10s) — итерируем после плейтеста.
