# Rarity Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Внедрить 4-тировую систему редкости апгрейдов (common/rare/epic/legendary) с кадэнсом по уровням (10 → legendary, 5/15/20… → epic, остальное → common+rare) и стак-кэпами по тиру.

**Architecture:** `UpgradeDef.Rarity` уже существует в коде с тремя значениями (COMMON/RARE/EPIC) — добавляем LEGENDARY=3 + поле `max_stacks`. `UpgradePool.roll_for()` рефакторим: принимает уровень, маршрутизирует к нужному тиру, фильтрует по стакам через `Player._upgrade_stacks`. `UpgradeOffer` теряет хардкод-milestones (их роль играет тир-логика). UI расширяется на четвёртый тир (золотой). Старый механизм `weight <= 0` (milestone-only) выпиливается — три арбалетчика-.tres получают `weight=1.0`.

**Tech Stack:** Godot 4.6, GDScript, host-authoritative net через ENet+MultiplayerSpawner. Тесты — print-based scenario (по конвенции проекта, см. `tests/smoke_test/`).

**Spec:** [docs/superpowers/specs/2026-05-08-rarity-upgrades-design.md](../specs/2026-05-08-rarity-upgrades-design.md)

---

## File Structure

**Modify:**
- `src/data/upgrade_def.gd` — добавить LEGENDARY в enum, поле `max_stacks`
- `src/progression/upgrade_pool.gd` — переписать `roll_for()`, добавить `effective_max_stacks()` и `_target_rarity_for_level()`, удалить weight-логику
- `src/progression/upgrade_offer.gd` — передавать `new_level` в `roll_for()`, удалить `_ensure_milestone_pick()` и `_milestones_for()`
- `src/ui/level_up_screen.gd` — расширить `RARITY_LABELS`, `RARITY_COLORS`, `RARITY_BORDER_WIDTH` до 4 элементов; обновить clamp в `_make_card`
- `resources/upgrades/crossbow_charge_master.tres` — `weight = 1.0`
- `resources/upgrades/crossbow_bolt_damage.tres` — `weight = 1.0`
- `resources/upgrades/crossbow_roll_volley.tres` — `weight = 1.0`

**Create:**
- `tests/rarity_offer/rarity_offer.tscn` — сцена-обёртка
- `tests/rarity_offer/rarity_offer.gd` — сценарный тест

---

### Task 1: UpgradeDef — добавить LEGENDARY и max_stacks

**Files:**
- Modify: `src/data/upgrade_def.gd:11` (enum Rarity), и добавить `@export var max_stacks` после строки 29 (`@export var rarity: Rarity = Rarity.COMMON`)

- [ ] **Step 1: Добавить LEGENDARY в enum Rarity**

В файле `src/data/upgrade_def.gd` найти строку 11:

```gdscript
enum Rarity { COMMON, RARE, EPIC }
```

Заменить на:

```gdscript
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
```

- [ ] **Step 2: Добавить поле max_stacks**

В том же файле найти строку с объявлением `rarity` (строка 29):

```gdscript
@export var rarity: Rarity = Rarity.COMMON
```

Сразу после неё добавить:

```gdscript
# 0 = бесконечно для COMMON, либо тиро-зависимый дефолт (RARE=3, EPIC=2, LEGENDARY=1)
# вычисляется через UpgradePool.effective_max_stacks(). Положительное значение
# перекрывает дефолт (например, 5 для dodge, 8 для cooldown).
@export var max_stacks: int = 0
```

- [ ] **Step 3: Запустить parse-check**

Run: `make check`
Expected: `OK` (никаких SCRIPT ERROR / Parse Error). Существующие .tres-файлы продолжают валидироваться, поскольку добавили только новые поля и enum-значение.

- [ ] **Step 4: Commit**

```bash
git add src/data/upgrade_def.gd
git commit -m "UpgradeDef: добавлены LEGENDARY и max_stacks"
```

---

### Task 2: UpgradePool — effective_max_stacks helper

**Files:**
- Modify: `src/progression/upgrade_pool.gd` — добавить новый static-хелпер

- [ ] **Step 1: Добавить хелпер effective_max_stacks**

В файл `src/progression/upgrade_pool.gd` добавить статик-метод (любое место класса, удобно — перед `_matches`):

```gdscript
# Эффективный стак-кэп карточки. 0 = бесконечно. Положительный max_stacks
# на ресурсе перебивает тиро-дефолт.
static func effective_max_stacks(def: UpgradeDef) -> int:
	if def == null:
		return 0
	if def.max_stacks > 0:
		return def.max_stacks
	match def.rarity:
		UpgradeDef.Rarity.COMMON:
			return 0
		UpgradeDef.Rarity.RARE:
			return 3
		UpgradeDef.Rarity.EPIC:
			return 2
		UpgradeDef.Rarity.LEGENDARY:
			return 1
	return 0
```

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add src/progression/upgrade_pool.gd
git commit -m "UpgradePool: helper effective_max_stacks (тиро-дефолты + override)"
```

---

### Task 3: Сценарный тест rarity_offer (TDD — пишем перед рефактором)

**Files:**
- Create: `tests/rarity_offer/rarity_offer.tscn`
- Create: `tests/rarity_offer/rarity_offer.gd`

- [ ] **Step 1: Создать сценарий-обёртку**

Создать `tests/rarity_offer/rarity_offer.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://b0rarity67surv"]

[ext_resource type="Script" path="res://tests/rarity_offer/rarity_offer.gd" id="1_rarity"]

[node name="RarityOffer" type="Node"]
script = ExtResource("1_rarity")
```

- [ ] **Step 2: Написать тест-сценарий**

Создать `tests/rarity_offer/rarity_offer.gd`:

```gdscript
extends Node

# Headless verification of the rarity offer pipeline. We construct minimal
# UpgradeDefs in code (registered into Defs.upgrades), spawn a stub player
# with the necessary fields, and call UpgradePool.roll_for() with various
# levels — checking the routing, the stack-cap filter, and the fallback.
#
# Run with: godot --headless res://tests/rarity_offer/rarity_offer.tscn

var _failures: int = 0

func _ready() -> void:
	print("[rarity] starting")
	_run()
	if _failures > 0:
		printerr("[rarity] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[rarity] OK")
		get_tree().quit(0)

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Snapshot the live registry so we can restore it.
	var saved: Dictionary = Defs.upgrades.duplicate()

	# Build minimal test fixtures, all universal (empty class_filter).
	var common_def: UpgradeDef = _make_def(&"t_common", UpgradeDef.Rarity.COMMON, 2)
	var rare_def: UpgradeDef = _make_def(&"t_rare", UpgradeDef.Rarity.RARE, 0)
	var epic_def: UpgradeDef = _make_def(&"t_epic", UpgradeDef.Rarity.EPIC, 0)
	var leg_def: UpgradeDef = _make_def(&"t_legendary", UpgradeDef.Rarity.LEGENDARY, 0)

	Defs.upgrades.clear()
	Defs.upgrades[common_def.id] = common_def
	Defs.upgrades[rare_def.id] = rare_def
	Defs.upgrades[epic_def.id] = epic_def
	Defs.upgrades[leg_def.id] = leg_def

	var player := _make_player_stub()

	# 1. Regular level → no epic/legendary, only common+rare.
	var picks := UpgradePool.roll_for(rng, player, 3, 4)
	_assert(picks.size() >= 1, "case1 picks non-empty")
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case1 only common/rare (got %d)" % p.rarity)

	# 2. Epic level (5) → must contain the epic.
	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(_has_id(picks, &"t_epic"), "case2 epic appears at level 5")
	_assert(not _has_id(picks, &"t_legendary"), "case2 no legendary at level 5")

	# 3. Legendary level (10) → must contain legendary.
	picks = UpgradePool.roll_for(rng, player, 3, 10)
	_assert(_has_id(picks, &"t_legendary"), "case3 legendary appears at level 10")
	_assert(not _has_id(picks, &"t_epic"), "case3 no epic at level 10")

	# 4. Level 11 → back to common/rare.
	picks = UpgradePool.roll_for(rng, player, 3, 11)
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case4 only common/rare (got %d)" % p.rarity)

	# 5. Stack-cap exhaustion: pick t_common twice → it disappears.
	player._upgrade_stacks[&"t_common"] = 2
	picks = UpgradePool.roll_for(rng, player, 3, 6)
	_assert(not _has_id(picks, &"t_common"), "case5 t_common excluded at cap")
	player._upgrade_stacks.clear()

	# 6. Fallback when no epics exist for that level.
	Defs.upgrades.erase(&"t_epic")
	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(picks.size() == 3, "case6 fallback fills 3 slots without epics (got %d)" % picks.size())
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case6 fallback uses common/rare only")

	# 7. Class filter respected for the new tiers.
	# Restore epic and add a class-locked epic.
	var class_epic: UpgradeDef = _make_def(&"t_class_epic", UpgradeDef.Rarity.EPIC, 0)
	class_epic.class_filter = Array[StringName]([&"crossbow"])
	Defs.upgrades[class_epic.id] = class_epic
	Defs.upgrades[&"t_epic"] = epic_def  # restore universal epic

	# Berserker-stub player must NOT see the class_epic.
	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(not _has_id(picks, &"t_class_epic"),
		"case7a class_epic hidden from berserker")

	# Restore registry.
	Defs.upgrades.clear()
	for k in saved.keys():
		Defs.upgrades[k] = saved[k]

func _make_def(id: StringName, rarity: int, max_stacks: int) -> UpgradeDef:
	var d := UpgradeDef.new()
	d.id = id
	d.label = String(id)
	d.display_name = String(id)
	d.weight = 1.0
	d.rarity = rarity
	d.max_stacks = max_stacks
	d.stat = &"dmg"
	d.mode = UpgradeDef.Mode.PCT
	d.amount = 0.01
	d.class_filter = Array[StringName]([])
	d.archetype_filter = Array[StringName]([])
	return d

class _PlayerStub extends RefCounted:
	var klass: StringName = &"berserker"
	var _upgrade_stacks: Dictionary = {}

func _make_player_stub() -> _PlayerStub:
	# Минимальный stub с теми двумя полями, которые читает UpgradePool. Использовать
	# реального Player'а нельзя — он тянет StatBlock, MultiplayerSynchronizer,
	# репликацию и т.д.
	return _PlayerStub.new()

func _has_id(picks: Array, id: StringName) -> bool:
	for p in picks:
		if p == null:
			continue
		if StringName(String(p.id)) == id:
			return true
	return false

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[rarity] OK %s" % label)
	else:
		printerr("[rarity] FAIL %s" % label)
		_failures += 1
```

- [ ] **Step 3: Добавить таргет в Makefile**

В файл `Makefile` найти строку с `.PHONY` (строка 17):

```makefile
.PHONY: run editor import smoke check server deploy logs stop peer host join clean help
```

Добавить `rarity-test` в список:

```makefile
.PHONY: run editor import smoke rarity-test check server deploy logs stop peer host join clean help
```

И сразу после блока `smoke:` (строка 28-29) добавить:

```makefile
rarity-test:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/rarity_offer/rarity_offer.tscn
```

- [ ] **Step 4: Запустить тест — он ДОЛЖЕН упасть**

Run: `make rarity-test`
Expected: FAIL. Возможные ошибки:
- `Invalid call to method 'roll_for' (expected 3 arguments, got 4)` — потому что текущая сигнатура без `level`.
- ИЛИ часть кейсов падает потому что текущая `roll_for` не разделяет тиры.

Это ожидаемо — тест написан под новую сигнатуру.

- [ ] **Step 5: Commit (failing test)**

```bash
git add tests/rarity_offer/rarity_offer.tscn tests/rarity_offer/rarity_offer.gd Makefile
git commit -m "tests: rarity_offer scenario (failing — under TDD)"
```

---

### Task 4: UpgradePool — рефактор roll_for на тиро-логику

**Files:**
- Modify: `src/progression/upgrade_pool.gd` — переписать `roll_for`, удалить `_weighted_shuffle`, добавить `_target_rarity_for_level`

- [ ] **Step 1: Полная замена содержимого upgrade_pool.gd**

Заменить весь файл `src/progression/upgrade_pool.gd` на:

```gdscript
class_name UpgradePool extends RefCounted

# Filters and rolls UpgradeDef resources for a specific player. Class-aware
# and rarity-routed: legendary on level 10 (one-shot), epic on multiples of 5
# (5, 15, 20…), common+rare on everything else. Falls back to common+rare if
# the targeted-tier pool is too small to fill `count` slots.

static func roll_for(rng: RandomNumberGenerator, player: Node, count: int, level: int) -> Array:
	var target: Variant = _target_rarity_for_level(level)
	var picks: Array = _roll_tier(rng, player, count, target)
	if picks.size() < count and target != null:
		# Backfill from common+rare when the tier pool is empty/short.
		var backup: Array = _roll_tier(rng, player, count - picks.size(), null)
		var seen: Dictionary = {}
		for p in picks:
			seen[p.id] = true
		for p in backup:
			if picks.size() >= count:
				break
			if seen.has(p.id):
				continue
			picks.append(p)
	return picks

# null    → pool of {COMMON, RARE}
# integer → pool of that single tier
static func _roll_tier(rng: RandomNumberGenerator, player: Node, count: int, target: Variant) -> Array:
	var pool: Array = []
	for def in Defs.upgrades.values():
		if not _matches(def, player, target):
			continue
		pool.append(def)
	pool = _uniform_shuffle(rng, pool)
	var picks: Array = []
	for def in pool:
		if picks.size() >= count:
			break
		picks.append(def)
	return picks

static func _target_rarity_for_level(level: int) -> Variant:
	if level == 10:
		return UpgradeDef.Rarity.LEGENDARY
	if level > 0 and level % 5 == 0:
		return UpgradeDef.Rarity.EPIC
	return null

static func _matches(def: UpgradeDef, player: Node, target: Variant) -> bool:
	if def == null:
		return false
	# Tier filter.
	if target == null:
		if def.rarity != UpgradeDef.Rarity.COMMON and def.rarity != UpgradeDef.Rarity.RARE:
			return false
	else:
		if def.rarity != int(target):
			return false
	# Class filter — empty array = universal.
	if def.class_filter.size() > 0 and not def.class_filter.has(player.klass):
		return false
	# Stack-cap filter.
	var cap: int = effective_max_stacks(def)
	if cap > 0:
		var picks_dict: Dictionary = player._upgrade_stacks
		var picked: int = int(picks_dict.get(def.id, 0))
		if picked >= cap:
			return false
	return true

static func _uniform_shuffle(rng: RandomNumberGenerator, defs: Array) -> Array:
	var out: Array = defs.duplicate()
	# Fisher-Yates с переданным RNG.
	var n: int = out.size()
	for i in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out

static func effective_max_stacks(def: UpgradeDef) -> int:
	if def == null:
		return 0
	if def.max_stacks > 0:
		return def.max_stacks
	match def.rarity:
		UpgradeDef.Rarity.COMMON:
			return 0
		UpgradeDef.Rarity.RARE:
			return 3
		UpgradeDef.Rarity.EPIC:
			return 2
		UpgradeDef.Rarity.LEGENDARY:
			return 1
	return 0
```

(Поле `weight` теперь нигде не читается — это намеренно. См. spec, секция «Что делать со старым `weight`».)

- [ ] **Step 2: Parse-check**

Run: `make check`
Expected: `OK`. Если что-то сломалось в `upgrade_offer.gd` (он вызывает старую сигнатуру `roll_for(rng, player, 3)`) — это пойдёт в Task 5. Сейчас `make check` НЕ запускает offer-логику, он только парсит, поэтому должен пройти.

- [ ] **Step 3: Commit**

```bash
git add src/progression/upgrade_pool.gd
git commit -m "UpgradePool: тиро-логика, стак-фильтр, фолбэк (без weight)"
```

---

### Task 5: UpgradeOffer — обновить вызов roll_for + удалить milestone-хардкод

**Files:**
- Modify: `src/progression/upgrade_offer.gd`

- [ ] **Step 1: Передать level в roll_for**

Найти в `src/progression/upgrade_offer.gd` строку (около 61):

```gdscript
		var picks: Array = UpgradePool.roll_for(_rng, player, 3)
		_ensure_milestone_pick(picks, player, new_level)
```

Заменить на:

```gdscript
		var picks: Array = UpgradePool.roll_for(_rng, player, 3, new_level)
```

- [ ] **Step 2: Удалить _ensure_milestone_pick и _milestones_for**

В том же файле найти и удалить целиком два блока (включая комментарии перед ними и пустые строки между ними). Должно уйти РОВНО это:

```gdscript
# Class-specific milestone upgrades. When a milestone level fires, the
# offered picks are *replaced* by the milestone defs (less the ones already
# taken) — no random fillers, no other upgrades. Returns silently when the
# (class, level) pair has no milestones, leaving the random picks untouched.
func _ensure_milestone_pick(picks: Array, player: Node, new_level: int) -> void:
	var milestone_ids: Array = _milestones_for(player, new_level)
	if milestone_ids.is_empty():
		return
	var milestone_picks: Array = []
	for mid_v in milestone_ids:
		var mid: StringName = mid_v
		var def: UpgradeDef = Defs.upgrade_def(mid)
		if def == null:
			continue
		if int(player._upgrade_stacks.get(mid, 0)) > 0:
			continue
		milestone_picks.append(def)
	if milestone_picks.is_empty():
		return
	picks.clear()
	picks.append_array(milestone_picks)

func _milestones_for(player: Node, new_level: int) -> Array:
	if new_level == 5 and player.klass == &"crossbow":
		return [&"crossbow_roll_volley", &"crossbow_charge_master", &"crossbow_bolt_damage"]
	return []
```

После удаления проверь: следующий метод после удаления должен быть `_on_player_downed`.

- [ ] **Step 3: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add src/progression/upgrade_offer.gd
git commit -m "UpgradeOffer: передаём level в pool, выпиливаем milestone-хардкод"
```

---

### Task 6: Crossbow .tres миграция (weight=0 → weight=1)

**Files:**
- Modify: `resources/upgrades/crossbow_charge_master.tres:10`
- Modify: `resources/upgrades/crossbow_bolt_damage.tres:10`
- Modify: `resources/upgrades/crossbow_roll_volley.tres:10`

- [ ] **Step 1: crossbow_charge_master.tres**

В файле `resources/upgrades/crossbow_charge_master.tres` найти строку 10:

```
weight = 0.0
```

Заменить на:

```
weight = 1.0
```

- [ ] **Step 2: crossbow_bolt_damage.tres**

В файле `resources/upgrades/crossbow_bolt_damage.tres` найти строку 10:

```
weight = 0.0
```

Заменить на:

```
weight = 1.0
```

- [ ] **Step 3: crossbow_roll_volley.tres**

В файле `resources/upgrades/crossbow_roll_volley.tres` найти строку 10:

```
weight = 0.0
```

Заменить на:

```
weight = 1.0
```

- [ ] **Step 4: Verify**

Run: `grep "^weight" resources/upgrades/crossbow_*.tres`
Expected output (3 lines, все с 1.0):
```
resources/upgrades/crossbow_bolt_damage.tres:weight = 1.0
resources/upgrades/crossbow_charge_master.tres:weight = 1.0
resources/upgrades/crossbow_roll_volley.tres:weight = 1.0
```

- [ ] **Step 5: Commit**

```bash
git add resources/upgrades/crossbow_charge_master.tres resources/upgrades/crossbow_bolt_damage.tres resources/upgrades/crossbow_roll_volley.tres
git commit -m "Кроссбоумен: weight 0→1 для трёх milestone-карт (теперь EPIC через тир)"
```

---

### Task 7: LevelUpScreen — четвёртый тир в UI

**Files:**
- Modify: `src/ui/level_up_screen.gd`

- [ ] **Step 1: Расширить RARITY_LABELS**

Найти строку 24:

```gdscript
const RARITY_LABELS := ["Обычная", "Редкая", "Эпическая"]
```

Заменить на:

```gdscript
const RARITY_LABELS := ["Обычная", "Редкая", "Эпическая", "Легендарная"]
```

- [ ] **Step 2: Расширить RARITY_COLORS**

Найти строки 25-29:

```gdscript
const RARITY_COLORS := [
	Color(0.55, 0.55, 0.55),
	Color(0.30, 0.62, 0.95),
	Color(0.78, 0.45, 0.95),
]
```

Заменить на:

```gdscript
const RARITY_COLORS := [
	Color(0.55, 0.55, 0.55),
	Color(0.30, 0.62, 0.95),
	Color(0.78, 0.45, 0.95),
	Color(1.00, 0.78, 0.20),
]
```

- [ ] **Step 3: Расширить RARITY_BORDER_WIDTH**

Найти строку 48:

```gdscript
const RARITY_BORDER_WIDTH := [1, 2, 2]
```

Заменить на:

```gdscript
const RARITY_BORDER_WIDTH := [1, 2, 2, 3]
```

- [ ] **Step 4: Обновить clamp в _make_card**

Найти строку 345:

```gdscript
	var rarity: int = clamp(int(def.rarity), 0, 2)
```

Заменить на:

```gdscript
	var rarity: int = clamp(int(def.rarity), 0, 3)
```

- [ ] **Step 5: Parse-check**

Run: `make check`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add src/ui/level_up_screen.gd
git commit -m "LevelUpScreen: легендарный тир (золотая рамка) в UI"
```

---

### Task 8: Verify

- [ ] **Step 1: Запустить новый scenario test**

Run: `make rarity-test`
Expected output ends with `[rarity] OK` and `quit(0)`. Все семь кейсов должны напечатать `OK`.

Если падает — читать конкретный `FAIL`-лог, диагностировать в коде `upgrade_pool.gd`, чинить, перезапускать.

- [ ] **Step 2: Запустить smoke-тест**

Run: `make smoke`
Expected: тест доходит до `[smoke] DONE` и завершается с exit 0. Особое внимание — на блок `level_up paused=true` и `after-pick paused=false` (показывает что upgrade-flow жив).

- [ ] **Step 3: Manual sanity (опционально)**

Run: `make run` → залогиниться берсерком → дойти до 5 уровня → визуально убедиться что в оффере 3 фиолетовых эпик-карточки. На 10м — 3 золотых легендарных (фолбэк, поскольку легендарок ещё не наполнено — будут common+rare с золотой рамкой? Нет — фолбэк выдаёт common+rare с НАСТОЯЩИМИ их цветами, не золотыми).

Этот шаг — не блокирующий. Если визуальная проверка не проводилась, отметить в финальном отчёте.

---

## Self-Review Notes

**Spec coverage check:**
- ✅ Task 1: добавили LEGENDARY и max_stacks
- ✅ Task 2: effective_max_stacks helper
- ✅ Task 4: roll_for(level), тир-маршрутизация, фолбэк, выпил weight
- ✅ Task 5: UpgradeOffer передаёт level, удалены milestone-хуки
- ✅ Task 6: миграция трёх crossbow .tres
- ✅ Task 7: четвёртый тир в UI
- ✅ Task 3, 8: scenario test + verify

**Не покрыто** (вынесено в Спек 2 / Спек 3 / Спек 4):
- Контентные карточки нового тира
- Берсерк-cleave
- Магская легендарка «Эхо»
- Удаление поля `weight` из `UpgradeDef` (последующий клин-ап)

**Compat-риски:**
- `mage_fireball_damage`, `chain_hops`, `charge_multishot`, `max_hp` имеют `rarity=2` (EPIC) уже сейчас и `weight=1.0` — то есть появляются в random rolls. После рефактора они будут только на эпик-уровнях. Это **намеренное** изменение поведения (соответствует spec'у). Не регрессия.
- Crossbow milestones (3 файла) сохраняют `rarity=2`, теперь `weight=1.0` — на 5м арбалетчик их видит как эпик, поведение для UX сохраняется.
