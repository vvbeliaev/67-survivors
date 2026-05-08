# Берсерк — cleave-автоатака + легендарка-circle + эпик-рывок

Дата: 2026-05-08. Статус: дизайн (выезжает на rarity-инфраструктуре).
Связанные доки: [rarity-upgrades-design.md](2026-05-08-rarity-upgrades-design.md), [CLAUDE.md](../../../CLAUDE.md).

## Цель

Перевести автоатаку берсерка с круговой AoE-крутилки на направленный конус-cleave перед игроком. Круговая поведение становится **легендаркой** уровня 10 (из rarity-системы). Параллельно даём берсерку **эпик** для уровня 5/15/20…: рывок наносит 300% от урона автоатаки (вместо стандартного фиксированного урона).

Дизайн-мотивация: концепт говорит «кооп держится на жёстком разделении ролей». Круговая крутилка слишком прощает позиционирование — берсерк просто стоит в куче. Cleave требует смотреть на курсор, поворачиваться, держать ориентацию — это уже маленькая моторика, которая через 20-30 минут забега становится ощутимой нагрузкой и делает класс осмысленным.

## Что меняем

### 1. `MeleeSwirl` → `MeleeCleave` (новый файл, заменяет старый)

Файл: `src/skills/concrete/melee_cleave.gd`. Старый `melee_swirl.gd` удаляется.

**Параметры:**

```gdscript
@export var radius: float = 80.0         # длина дуги (= range)
@export var arc_deg: float = 90.0        # ширина конуса в градусах
@export var damage: float = 12.0         # тот же урон, что был у swirl
```

**Поведение:**

```gdscript
func _init() -> void:
    base_cooldown = 0.4
    icon = preload("res://assets/images/icons/axe-swing.svg")

func on_tick(_delta: float) -> void:
    if not ready_to_cast():
        return
    start_cooldown()
    var r: float = radius * owner_player.range_mult()
    var dmg: float = damage * owner_player.dmg_mult()
    var aim: Vector2 = owner_player.aim_dir   # уже единичный вектор
    if owner_player.legendary_id == &"berserker_circle":
        _aoe_damage(owner_player.global_position, r, dmg)
        trigger_visual_fx("auto", {"r": r, "shape": "circle"})
    else:
        _cone_damage(owner_player.global_position, aim, r, deg_to_rad(arc_deg), dmg)
        # alternation: чередуем визуальное направление взмаха для FX.
        var swing: int = owner_player.fx_get("auto_swing", "n", 0)
        owner_player.fx_set("auto_swing", "n", (swing + 1) % 2)
        trigger_visual_fx("auto", {"r": r, "shape": "cone", "aim": aim, "arc": arc_deg, "swing": swing})
```

**Хелпер `_cone_damage`** добавляется в `Skill` (базе):

```gdscript
func _cone_damage(center: Vector2, aim: Vector2, r: float, half_arc_rad: float, dmg: float) -> void:
    # half_arc_rad = arc_total / 2. Враг попадает если расстояние ≤ r и угол ≤ half_arc_rad.
    var aim_n: Vector2 = aim.normalized() if aim.length() > 0.0001 else Vector2.RIGHT
    for e in Targeting.enemies_in_radius(get_tree(), center, r):
        var d: Vector2 = e.global_position - center
        if d.length() < 0.001:
            # Вплотную внутри игрока — считаем попаданием.
            e.apply_damage(dmg, "player")
            _apply_lifesteal(dmg)
            continue
        var angle: float = aim_n.angle_to(d.normalized())
        if abs(angle) > half_arc_rad:
            continue
        e.apply_damage(dmg, "player")
        _apply_lifesteal(dmg)

func _apply_lifesteal(dmg: float) -> void:
    var ls: float = owner_player.lifesteal()
    if ls > 0.0:
        owner_player.heal(dmg * ls)
```

(Lifesteal был inline в `_aoe_damage` — выносим в общий хелпер, чтобы и cone, и aoe его делили.)

### 2. Привязка в `berserker.gd`

```gdscript
const MeleeCleave := preload("res://src/skills/concrete/melee_cleave.gd")
# ...
func build_skills() -> void:
    auto_skill = MeleeCleave.new()
    # остальное без изменений
```

### 3. Легендарка «Круговая ярость» (Circle Auto)

Файл: `resources/upgrades/legendary_berserker_circle.tres`.

```
id = &"berserker_circle"
display_name = "Круговая ярость"
description = "Автоатака бьёт во все стороны вокруг тебя\nвместо конуса перед собой."
flavor = "Ось не выбирает направление. Топор — тоже."
rarity = 3   # LEGENDARY
class_filter = Array[StringName]([&"berserker"])
category = &"attack"
icon = preload("res://assets/images/icons/<TBD - axe spin>.svg")
# stat / amount пустые — чисто механика
```

При пике этой легендарки `Player.legendary_id = &"berserker_circle"`. `MeleeCleave` читает это поле и переключается на круговое поведение. Никакого отдельного скилл-инстанса не создаётся.

### 4. Эпик «Таран» — рывок на 300% урона автоатаки

Файл: `resources/upgrades/epic_berserker_dash_auto.tres`.

```
id = &"epic_berserker_dash_auto"
display_name = "Таран"
description = "Рывок наносит 300% от урона автоатаки\nвместо своего базового урона."
flavor = "Топор — это просто аргумент. Рывок — это способ его донести."
rarity = 2   # EPIC
class_filter = Array[StringName]([&"berserker"])
category = &"attack"
```

Хук в `BerserkerLeap` (`src/skills/concrete/berserker_leap.gd`). Сейчас рывок наносит фиксированный урон `damage`. Меняется на:

```gdscript
var dmg: float
if _has_upgrade(&"epic_berserker_dash_auto"):
    var auto = owner_player.auto_skill   # MeleeCleave экземпляр
    var auto_dmg: float = auto.damage if auto else damage
    dmg = auto_dmg * 3.0 * owner_player.dmg_mult()
else:
    dmg = damage * owner_player.dmg_mult()
```

Хелпер `_has_upgrade(id: StringName) -> bool` живёт на `Skill` (читает `owner_player._upgrade_stacks`). Это чтобы любые скиллы могли проверять «есть ли у меня эпик/легендарка» без копи-пасты.

### 5. FX

В `player_view.gd::_draw_berserker_fx()`:

- Если `fx_get("auto", "shape", "circle") == "cone"` → рисуем сектор: `draw_arc` с углом от `aim - arc/2` до `aim + arc/2`, плюс две радиальные линии-границы. Чередование направления (`swing == 0` или `1`) — лёгкое смещение начала сектора на ±10° для импрессии «взмах туда / взмах сюда». Альфа угасает по `ta`.
- Если `shape == "circle"` (легендарка) → старая отрисовка двух полудуг (как сейчас). Сохраняем визуал на отзыв.

Перед рисованием FX проверяем shape — это позволяет в одном забеге увидеть оба варианта: до 10го уровня — конус, после пика легендарки — круг.

**`fx_set` хелпер.** Сейчас в `Player.play_visual_fx` храним только timestamp + data. Добавляем сеттер: `fx_set(kind, key, value)` — обновляет значение в data без переустановки timestamp. Нужен для счётчика swing-чередования (см. cleave-код).

## Параметры (чёрновое значение, итерируем после первой игры)

| Параметр | Значение | Комментарий |
|---|---|---|
| `arc_deg` | 90° | Cleave-конус. Достаточно широко, чтобы попадать по 2-3 врагам в куче, но без круговости. |
| `radius` | 80 | = текущий swirl. Чтобы не менять «дальность» автоатаки на старте. |
| `damage` | 12 | = текущий swirl. Эффективный DPS ниже потому что попадает не во всех. |
| `base_cooldown` | 0.4 | Без изменений. |
| `dash_auto_mult` | 3.0 | 300% per req. Можно понизить если в плейтесте окажется OP. |
| Echo-задержка повтора (Спек 4) | — | Не относится к этому спеку. |

## Контракты

- `Player.legendary_id` — поле, добавленное в Спеке 4 (mage echo clone). Если Спек 4 не реализован первым, мы вводим это поле здесь же. План реализации проверит порядок.
- `Player.fx_set(kind, key, value)` — новый хелпер во `view-fx`-системе. Реализация рядом с `play_visual_fx`/`fx_get`.
- `Skill._has_upgrade(id)` — новый хелпер в базе. Реализация: `int(owner_player._upgrade_stacks.get(id, 0)) > 0`.
- Cleave-конус не задевает врагов **за спиной** игрока — это часть дизайна (мотивация к позиционированию). Никаких back-hit'ов в this spec.

## Тесты

Добавляется к существующему `tests/smoke_test/smoke_test.gd`:

1. Спавн берсерка → автоатака → проверить что только враг **перед** ним получил урон, враг **за спиной** — нет.
2. Симулировать пик легендарки `berserker_circle` (через `apply_upgrade_def` напрямую) → автоатака → теперь враг **за спиной** тоже получает урон.
3. Пик `epic_berserker_dash_auto` → рывок → проверить что урон рывка ≈ `12 × 3 × dmg_mult` вместо базового.

## Что НЕ входит

- Реворк остальных скиллов берсерка (quake/roar/leap-как-мобильность) — только эпик-хук в leap.
- Архетипы берсерка (Защитник/Кровавый/Командир) — Tier 2.
- Mobile auto-targeting (когда нет курсора, прицеливание по ближайшему) — отдельная фича уровня всего проекта, не только берсерка.
- Балансировка `arc_deg` / `dash_auto_mult` — итерируем после первого билда.

## Acceptance criteria

- На уровне 10 берсерк среди легендарок видит «Круговую ярость»; после пика автоатака бьёт круг.
- До 10го уровня (или если не выбрана) автоатака бьёт только в конусе перед курсором.
- Враг за спиной игрока на dist=70 не получает урона от обычного cleave.
- Эпик «Таран» появляется в эпик-оффере для берсерка (на 5/15/20…).
- После пика «Тарана» рывок с auto.damage=12, dmg_mult=1.0 наносит 36 урона по цели.
- Существующий FX swirl продолжает работать когда легендарка взята.
- `make smoke` и новые тесты — зелёные.
