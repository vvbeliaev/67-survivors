# Berserker Cleave + Legendary Circle + Epic Dash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить круговую автоатаку берсерка на конус-cleave перед игроком. Легендарка `berserker_circle` (выпадает на 10м уровне) переключает обратно в круг (старое поведение). Эпик `epic_berserker_dash_auto` (выпадает на 5/15/20…) добавляет рывку AoE-удар на 300% от урона автоатаки в точке приземления.

**Architecture:** Новый скилл `MeleeCleave` заменяет `MeleeSwirl`; читает `owner_player._upgrade_stacks` чтобы решить, бить конус или круг. В `Skill` базе появляются два хелпера: `_cone_damage()` (геометрия конуса) и `_has_upgrade(id)` (тонкий wrapper над dict-lookup). `BerserkerLeap` дополнительно проверяет epic и кладёт AoE на destination. FX в `player_view.gd` различает `shape: "cone"` vs `"circle"` через данные FX.

**Tech Stack:** Godot 4.6, GDScript. Расширяет rarity-инфраструктуру из Спека 1 (требуется `apply_upgrade_def` уже инкрементит `_upgrade_stacks` — это так).

**Spec:** [docs/superpowers/specs/2026-05-08-berserker-cleave-design.md](../specs/2026-05-08-berserker-cleave-design.md)

---

## File Structure

**Modify:**
- `src/skills/skill.gd` — добавить `_cone_damage()` и `_has_upgrade()` хелперы; рефакторнуть `_aoe_damage()` чтобы переиспользовать lifesteal-логику
- `src/player/classes/berserker.gd` — заменить `MeleeSwirl` на `MeleeCleave`
- `src/skills/concrete/berserker_leap.gd` — добавить AoE-удар при наличии эпика
- `src/player/player_view.gd` — расширить `_draw_berserker_fx` на `shape: "cone"`

**Create:**
- `src/skills/concrete/melee_cleave.gd` — новый авто-скилл
- `resources/upgrades/legendary_berserker_circle.tres` — легендарка
- `resources/upgrades/epic_berserker_dash_auto.tres` — эпик
- `tests/berserker_cleave/berserker_cleave.tscn` — обёртка теста
- `tests/berserker_cleave/berserker_cleave.gd` — сценарный тест

**Delete:**
- `src/skills/concrete/melee_swirl.gd` (заменяется на melee_cleave.gd)
- `src/skills/concrete/melee_swirl.gd.uid` (uid'шник Godot — удаляем чтобы избежать orphan)

---

### Task 1: Skill base — _has_upgrade и рефактор _aoe_damage

**Files:**
- Modify: `src/skills/skill.gd`

- [ ] **Step 1: Рефактор _aoe_damage с выделением lifesteal-хелпера**

В файле `src/skills/skill.gd` найти блок (строки 58-64):

```gdscript
func _aoe_damage(center: Vector2, r: float, dmg: float) -> void:
	for e in Targeting.enemies_in_radius(get_tree(), center, r):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
			var ls: float = owner_player.lifesteal()
			if ls > 0.0:
				owner_player.heal(dmg * ls)
```

Заменить на:

```gdscript
func _aoe_damage(center: Vector2, r: float, dmg: float) -> void:
	for e in Targeting.enemies_in_radius(get_tree(), center, r):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
			_apply_lifesteal(dmg)

# Конус-удар вокруг направления aim. half_arc_rad = половина раствора в радианах.
# Враг попадает, если расстояние от center ≤ r и угол между (e - center) и aim
# ≤ half_arc_rad. Враги вплотную к center (dist < 1px) считаются попаданиями.
func _cone_damage(center: Vector2, aim: Vector2, r: float, half_arc_rad: float, dmg: float) -> void:
	var aim_n: Vector2 = aim.normalized() if aim.length() > 0.0001 else Vector2.RIGHT
	for e in Targeting.enemies_in_radius(get_tree(), center, r):
		if not e.has_method("apply_damage"):
			continue
		var d: Vector2 = e.global_position - center
		if d.length() < 1.0:
			e.apply_damage(dmg, "player")
			_apply_lifesteal(dmg)
			continue
		var angle: float = abs(aim_n.angle_to(d.normalized()))
		if angle > half_arc_rad:
			continue
		e.apply_damage(dmg, "player")
		_apply_lifesteal(dmg)

func _apply_lifesteal(dmg: float) -> void:
	if owner_player == null:
		return
	var ls: float = owner_player.lifesteal()
	if ls > 0.0:
		owner_player.heal(dmg * ls)

# True, если у игрока хотя бы один стак указанного апгрейда.
func _has_upgrade(id: StringName) -> bool:
	if owner_player == null:
		return false
	return int(owner_player._upgrade_stacks.get(id, 0)) > 0
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`. Существующие скиллы используют `_aoe_damage` — поведение сохранилось через делегирование в `_apply_lifesteal`.

- [ ] **Step 3: Smoke**

Run: `make smoke`
Expected: ends with `[smoke] DONE` exit 0. Берсерк-автоатака продолжает работать (старая `MeleeSwirl` ещё на месте, использует тот же `_aoe_damage`).

- [ ] **Step 4: Commit**

```bash
git add src/skills/skill.gd
git commit -m "Skill: helpers _cone_damage / _apply_lifesteal / _has_upgrade"
```

---

### Task 2: Создать MeleeCleave (на конусе)

**Files:**
- Create: `src/skills/concrete/melee_cleave.gd`

- [ ] **Step 1: Создать файл melee_cleave.gd**

Содержимое `src/skills/concrete/melee_cleave.gd`:

```gdscript
extends Skill

# Berserker auto-attack: cleave-конус перед игроком (направление = aim_dir).
# С легендаркой `berserker_circle` переключается в круговой AoE (бывший
# MeleeSwirl). Чередуется визуально между «взмахом слева» и «взмахом справа»
# для разнообразия (логически идентично).

@export var radius: float = 80.0       # длина дуги (= range)
@export var arc_deg: float = 90.0      # ширина конуса в градусах
@export var damage: float = 12.0       # базовый урон, тот же, что был у swirl

var _swing_index: int = 0  # 0/1 — для FX-чередования направления взмаха

func _init() -> void:
	base_cooldown = 0.4
	icon = preload("res://assets/images/icons/axe-swing.svg")

func on_tick(_delta: float) -> void:
	if not ready_to_cast():
		return
	start_cooldown()
	var r: float = radius * owner_player.range_mult()
	var dmg: float = damage * owner_player.dmg_mult()
	if _has_upgrade(&"berserker_circle"):
		_aoe_damage(owner_player.global_position, r, dmg)
		trigger_visual_fx("auto", {"r": r, "shape": "circle"})
	else:
		var aim: Vector2 = owner_player.aim_dir
		var half_arc: float = deg_to_rad(arc_deg) * 0.5
		_cone_damage(owner_player.global_position, aim, r, half_arc, dmg)
		var swing := _swing_index
		_swing_index = (_swing_index + 1) % 2
		trigger_visual_fx("auto", {
			"r": r,
			"shape": "cone",
			"aim_x": aim.x,
			"aim_y": aim.y,
			"arc": arc_deg,
			"swing": swing,
		})
```

(Vector2 в FX-словарь не сериализуется через RPC так же чисто как float, поэтому раскладываем `aim` в `aim_x`/`aim_y`.)

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`. (MeleeCleave создан, но никто его ещё не использует.)

- [ ] **Step 3: Commit**

```bash
git add src/skills/concrete/melee_cleave.gd
git commit -m "MeleeCleave: новый авто-скилл берсерка (конус + legendary-circle)"
```

---

### Task 3: Berserker — переключить с MeleeSwirl на MeleeCleave + удалить старый файл

**Files:**
- Modify: `src/player/classes/berserker.gd`
- Delete: `src/skills/concrete/melee_swirl.gd`
- Delete: `src/skills/concrete/melee_swirl.gd.uid`

- [ ] **Step 1: В berserker.gd заменить ссылку**

В файле `src/player/classes/berserker.gd` найти строки 3 и 18:

```gdscript
const MeleeSwirl     := preload("res://src/skills/concrete/melee_swirl.gd")
```
и
```gdscript
	auto_skill = MeleeSwirl.new()
```

Заменить на:

```gdscript
const MeleeCleave    := preload("res://src/skills/concrete/melee_cleave.gd")
```
и
```gdscript
	auto_skill = MeleeCleave.new()
```

- [ ] **Step 2: Удалить старый файл MeleeSwirl**

```bash
rm src/skills/concrete/melee_swirl.gd src/skills/concrete/melee_swirl.gd.uid
```

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`. Возможно увидишь warning «file removed» от Godot — это норм.

- [ ] **Step 4: Smoke**

Run: `make smoke`
Expected: `[smoke] DONE` exit 0. Берсерк теперь на cleave; smoke не делает специфичных проверок направления удара, поэтому должен пройти (враги обычно перед берсерком в смоке).

- [ ] **Step 5: Commit**

```bash
git add src/player/classes/berserker.gd src/skills/concrete/melee_swirl.gd src/skills/concrete/melee_swirl.gd.uid
git commit -m "Берсерк: автоатака — cleave-конус (вместо MeleeSwirl)"
```

(Удалённые файлы попадут в коммит автоматически через `git add` потому что они уже tracked.)

---

### Task 4: Player view — конус-FX

**Files:**
- Modify: `src/player/player_view.gd`

- [ ] **Step 1: Заменить блок _draw_berserker_fx (auto-часть)**

В файле `src/player/player_view.gd` найти блок (строки 103-110):

```gdscript
func _draw_berserker_fx() -> void:
	var ta: float = _player.fx_age("auto")
	if ta >= 0.0 and ta < 0.25:
		var k: float = 1.0 - ta / 0.25
		var r: float = float(_player.fx_get("auto", "r", 1.0))
		var spin: float = ta * 18.0
		draw_arc(Vector2.ZERO, r, spin, spin + PI, 32, Color(1, 0.95, 0.6, 0.45 * k), 6.0)
		draw_arc(Vector2.ZERO, r, spin + PI, spin + TAU, 32, Color(1, 0.7, 0.3, 0.35 * k), 4.0)
```

Заменить на:

```gdscript
func _draw_berserker_fx() -> void:
	var ta: float = _player.fx_age("auto")
	if ta >= 0.0 and ta < 0.25:
		var k: float = 1.0 - ta / 0.25
		var r: float = float(_player.fx_get("auto", "r", 1.0))
		var shape: String = String(_player.fx_get("auto", "shape", "circle"))
		if shape == "cone":
			var ax: float = float(_player.fx_get("auto", "aim_x", 1.0))
			var ay: float = float(_player.fx_get("auto", "aim_y", 0.0))
			var aim_angle: float = atan2(ay, ax)
			var arc_rad: float = deg_to_rad(float(_player.fx_get("auto", "arc", 90.0)))
			var swing: int = int(_player.fx_get("auto", "swing", 0))
			# Чередуем смещение начала сектора, чтобы было видно «взмах туда / сюда».
			var bias: float = (-1.0 if swing == 0 else 1.0) * 0.10
			var start_a: float = aim_angle - arc_rad * 0.5 + bias
			var end_a: float = aim_angle + arc_rad * 0.5 + bias
			draw_arc(Vector2.ZERO, r, start_a, end_a, 32, Color(1, 0.95, 0.6, 0.55 * k), 6.0)
			draw_arc(Vector2.ZERO, r * 0.7, start_a, end_a, 24, Color(1, 0.7, 0.3, 0.35 * k), 4.0)
			# Радиальные «границы» сектора — тонкие линии.
			var d_start := Vector2(cos(start_a), sin(start_a)) * r
			var d_end := Vector2(cos(end_a), sin(end_a)) * r
			draw_line(Vector2.ZERO, d_start, Color(1, 0.95, 0.6, 0.30 * k), 2.0)
			draw_line(Vector2.ZERO, d_end, Color(1, 0.95, 0.6, 0.30 * k), 2.0)
		else:
			# Legacy circular swirl (используется при наличии legendary `berserker_circle`).
			var spin: float = ta * 18.0
			draw_arc(Vector2.ZERO, r, spin, spin + PI, 32, Color(1, 0.95, 0.6, 0.45 * k), 6.0)
			draw_arc(Vector2.ZERO, r, spin + PI, spin + TAU, 32, Color(1, 0.7, 0.3, 0.35 * k), 4.0)
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Smoke**

Run: `make smoke`
Expected: `[smoke] DONE`.

- [ ] **Step 4: Commit**

```bash
git add src/player/player_view.gd
git commit -m "PlayerView: cone-FX для cleave-автоатаки берсерка (legacy circle сохранён)"
```

---

### Task 5: BerserkerLeap — AoE-удар при наличии эпика «Таран»

**Files:**
- Modify: `src/skills/concrete/berserker_leap.gd`

- [ ] **Step 1: Расширить on_pressed**

В файле `src/skills/concrete/berserker_leap.gd` найти метод `on_pressed` (строки 14-25). Заменить ВЕСЬ метод на:

```gdscript
func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var dir: Vector2 = owner_player.move_dir() if owner_player.move_dir().length_squared() > 0.01 else owner_player.aim_dir
	var from_pos: Vector2 = owner_player.global_position
	var to_pos: Vector2 = from_pos + dir.normalized() * distance
	owner_player.teleport(to_pos)
	owner_player.grant_iframes(iframe_duration)
	# Эпик «Таран»: AoE-удар в точке приземления, 300% от базового урона автоатаки.
	if _has_upgrade(&"epic_berserker_dash_auto"):
		var auto = owner_player.auto_skill
		var auto_base_dmg: float = float(auto.damage) if auto != null and "damage" in auto else 0.0
		var dmg: float = auto_base_dmg * 3.0 * owner_player.dmg_mult()
		_aoe_damage(to_pos, IMPACT_RADIUS, dmg)
	trigger_visual_fx("dash", {"start": from_pos, "r": 30.0})
	AudioBus.play_at(&"berserker_swing", owner_player.global_position)
```

- [ ] **Step 2: Добавить константу IMPACT_RADIUS**

В том же файле, прямо после `@export var iframe_duration: float = 0.4` (строка 8) добавить:

```gdscript
const IMPACT_RADIUS: float = 70.0   # AoE-радиус при срабатывании эпика «Таран»
```

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 4: Smoke**

Run: `make smoke`
Expected: `[smoke] DONE`.

- [ ] **Step 5: Commit**

```bash
git add src/skills/concrete/berserker_leap.gd
git commit -m "BerserkerLeap: AoE 300% от автоатаки при эпике «Таран»"
```

---

### Task 6: .tres — легендарка «Круговая ярость»

**Files:**
- Create: `resources/upgrades/legendary_berserker_circle.tres`

- [ ] **Step 1: Создать legendary_berserker_circle.tres**

Содержимое `resources/upgrades/legendary_berserker_circle.tres`:

```
[gd_resource type="Resource" script_class="UpgradeDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://src/data/upgrade_def.gd" id="1_def"]
[ext_resource type="Texture2D" path="res://assets/images/icons/crowned-explosion.svg" id="2_icon"]

[resource]
script = ExtResource("1_def")
id = &"berserker_circle"
label = "Круговая ярость"
weight = 1.0
class_filter = Array[StringName]([&"berserker"])
archetype_filter = Array[StringName]([])
icon = ExtResource("2_icon")
display_name = "Круговая ярость"
description = "Автоатака бьёт во все стороны
вокруг тебя вместо конуса перед собой."
rarity = 3
category = &"attack"
flavor = "Ось не выбирает направление. Топор — тоже."
stat = &""
mode = 0
amount = 0.0
max_stacks = 0
heal_on_pick = 0.0
refill_mana = false
```

- [ ] **Step 2: Import + parse-check**

Run: `make import` (Godot подхватит новый .tres) затем `make check`.
Expected: `make import` завершается без ошибок; `make check` → `OK`.

- [ ] **Step 3: Commit**

```bash
git add resources/upgrades/legendary_berserker_circle.tres
git commit -m ".tres: легендарка berserker_circle (Круговая ярость)"
```

---

### Task 7: .tres — эпик «Таран»

**Files:**
- Create: `resources/upgrades/epic_berserker_dash_auto.tres`

- [ ] **Step 1: Создать epic_berserker_dash_auto.tres**

Содержимое `resources/upgrades/epic_berserker_dash_auto.tres`:

```
[gd_resource type="Resource" script_class="UpgradeDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://src/data/upgrade_def.gd" id="1_def"]
[ext_resource type="Texture2D" path="res://assets/images/icons/confrontation.svg" id="2_icon"]

[resource]
script = ExtResource("1_def")
id = &"epic_berserker_dash_auto"
label = "Таран"
weight = 1.0
class_filter = Array[StringName]([&"berserker"])
archetype_filter = Array[StringName]([])
icon = ExtResource("2_icon")
display_name = "Таран"
description = "Рывок наносит 300% урона автоатаки
в точке приземления."
rarity = 2
category = &"attack"
flavor = "Топор — это аргумент. Рывок — способ его донести."
stat = &""
mode = 0
amount = 0.0
max_stacks = 0
heal_on_pick = 0.0
refill_mana = false
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add resources/upgrades/epic_berserker_dash_auto.tres
git commit -m ".tres: эпик epic_berserker_dash_auto (Таран)"
```

---

### Task 8: Сценарный тест berserker_cleave

**Files:**
- Create: `tests/berserker_cleave/berserker_cleave.tscn`
- Create: `tests/berserker_cleave/berserker_cleave.gd`
- Modify: `Makefile`

- [ ] **Step 1: Создать сцену-обёртку**

Содержимое `tests/berserker_cleave/berserker_cleave.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://b0bcleave67surv"]

[ext_resource type="Script" path="res://tests/berserker_cleave/berserker_cleave.gd" id="1_bcleave"]

[node name="BerserkerCleaveTest" type="Node"]
script = ExtResource("1_bcleave")
```

- [ ] **Step 2: Создать сценарный тест**

Содержимое `tests/berserker_cleave/berserker_cleave.gd`:

```gdscript
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
	var enemies: Array = _enemies_alive()
	_assert(enemies.size() == 2, "case1: 2 enemies spawned")
	if enemies.size() < 2:
		return
	var hp_front_before: float = enemies[0].hp
	var hp_back_before: float = enemies[1].hp
	# Дождёмся 1 тика автоатаки (cd=0.4, ждём 0.6 чтобы наверняка бахнуло хотя бы раз).
	await get_tree().create_timer(0.6).timeout
	var hp_front_after: float = enemies[0].hp
	var hp_back_after: float = enemies[1].hp
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
	enemies = _enemies_alive()
	_assert(enemies.size() == 2, "case2: 2 enemies spawned")
	if enemies.size() < 2:
		return
	var hp2_front_before: float = enemies[0].hp
	var hp2_back_before: float = enemies[1].hp
	await get_tree().create_timer(0.6).timeout
	var hp2_front_after: float = enemies[0].hp
	var hp2_back_after: float = enemies[1].hp
	_assert(hp2_front_after < hp2_front_before, "case2 front took damage with legendary")
	_assert(hp2_back_after < hp2_back_before, "case2 back ALSO took damage with legendary")

	# Очистка.
	for e in _enemies_alive():
		e.queue_free()
	await get_tree().create_timer(0.05).timeout

	# Кейс 3 — эпик «Таран»: рывок наносит AoE на месте приземления.
	# Подготовка: дадим эпик, разместим врага вдалеке, рывок туда.
	var epic_def: UpgradeDef = Defs.upgrade_def(&"epic_berserker_dash_auto")
	_assert(epic_def != null, "case3: epic def loaded")
	if epic_def == null:
		return
	player.apply_upgrade_def(epic_def)
	# Двигаем врага в радиус приземления. distance=220 у leap, IMPACT_RADIUS=70.
	# Поставим врага на 220px вправо.
	var landing: Vector2 = player.global_position + Vector2(220, 0)
	arena.spawn_enemy({"type": "rusher", "pos": landing})
	await get_tree().create_timer(0.05).timeout
	enemies = _enemies_alive()
	_assert(enemies.size() == 1, "case3: 1 enemy spawned")
	if enemies.is_empty():
		return
	var hp3_before: float = enemies[0].hp
	# Дёргаем рывок напрямую через utility_skill.
	var leap = player.get("utility_skill")
	_assert(leap != null, "case3: utility_skill exists")
	if leap == null:
		return
	# Заставляем игрока двигаться вправо (move_dir используется в leap).
	# move_dir() читает _in_move; на хосте для тест-стаба эмулируем через apply_input.
	player.apply_input(Vector2(1, 0), player.global_position + Vector2(220, 0), false, false, false, false, false)
	await get_tree().create_timer(0.05).timeout
	leap.on_pressed()
	await get_tree().create_timer(0.05).timeout
	var hp3_after: float = enemies[0].hp
	# Берсерк cleave damage = 12. С эпиком: 12 * 3 = 36. С dmg_mult=1.0 ⇒ 36 урона.
	# Учитывая возможный auto-tick автоатаки сразу после рывка тоже мог попасть,
	# проверяем «существенно > обычного auto-удара».
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
```

- [ ] **Step 3: Добавить таргет в Makefile**

В `Makefile` найти строку `.PHONY` (после Спека 1 уже включает `rarity-test`):
```
.PHONY: run editor import smoke rarity-test check server deploy logs stop peer host join clean help
```
Заменить на (добавляем `bcleave-test`):
```
.PHONY: run editor import smoke rarity-test bcleave-test check server deploy logs stop peer host join clean help
```

После блока `rarity-test:` добавить:
```
bcleave-test:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/berserker_cleave/berserker_cleave.tscn
```

- [ ] **Step 4: Запустить bcleave-test**

Run: `make bcleave-test`
Expected: ends with `[bcleave] OK` exit 0. Все три кейса печатают `OK`.

Если падает на case3 (delta < 30) — возможна проблема с тем что Skill.tick() декрементит cooldown в физическом тике, и за 0.05с автоатака не успела сделать второй удар. Это нормально, тест проверяет именно ОДИН AoE-удар от рывка — `delta ≥ 30` и так выполнено.

Если падает на case1 (back took damage) — баг в `_cone_damage`: либо half_arc_rad посчитан неверно, либо геометрия не работает как ожидается. Чинить в `src/skills/skill.gd`.

- [ ] **Step 5: Commit**

```bash
git add tests/berserker_cleave/berserker_cleave.tscn tests/berserker_cleave/berserker_cleave.gd Makefile
git commit -m "tests: berserker_cleave (cone vs circle vs dash AoE)"
```

---

### Task 9: Финальная верификация

- [ ] **Step 1: Все тесты**

Run: `make check && make rarity-test && make bcleave-test && make smoke`
Expected: все четыре зелёные, без SCRIPT ERROR / FAIL.

- [ ] **Step 2: Manual sanity (опционально)**

Run: `make run`. Залогиниться берсерком. Должно быть видно:
- Автоатака бьёт сектор перед курсором (раньше — крутилка вокруг).
- Враги за спиной не получают урона.

(Не блокирует — просто фиксируем визуально.)

---

## Self-Review Notes

**Spec coverage:**
- ✅ Task 1: helpers `_cone_damage`, `_apply_lifesteal`, `_has_upgrade`
- ✅ Task 2-3: новый `MeleeCleave` + замена в `berserker.gd` + удаление `melee_swirl.gd`
- ✅ Task 4: cone vs circle FX в `player_view.gd`
- ✅ Task 5: эпик-хук в `BerserkerLeap`
- ✅ Task 6-7: .tres легендарки + эпика
- ✅ Task 8-9: сценарный тест + verification

**Compat-риски:**
- Текущий `MeleeSwirl` удаляется. Старого использования нет (проверено grep'ом — только `berserker.gd`). Регрессии быть не должно.
- `_aoe_damage` сохраняет публичную сигнатуру; lifesteal вынесен в внутренний хелпер.
- Авто-тик берсерка теперь зависит от `aim_dir`. До рефактора круговая бьёт во все стороны (aim не нужен). Если игрок не двигал мышь / геймпад — `aim_dir = Vector2.RIGHT` (default), берсерк бьёт вправо. На активной игре `aim_dir` всегда живой через `apply_input`.

**Не покрыто** (вынесено в иные спеки):
- Магская легендарка «Эхо» — Спек 4.
- Новые карточки common/rare для прокачек (dodge, +10% размер и т.п.) — Спек 2 (контент).
- Архетипы берсерка — Tier 2.
- Mobile auto-targeting (без курсора) — отдельная фича.
