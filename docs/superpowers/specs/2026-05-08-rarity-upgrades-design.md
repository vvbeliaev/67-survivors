# Rarity-апгрейды — инфраструктура

Дата: 2026-05-08. Статус: дизайн утверждён, готов к плану реализации.
Связанные доки: [CLAUDE.md](../../../CLAUDE.md), [prototype-design.md](2026-05-05-prototype-design.md).

## Цель

Ввести 4 тира редкости апгрейдов (common / rare / epic / legendary) с разной частотой, стак-кэпами и кадэнсом по уровням. Это фундамент, на котором затем строятся:

- Спек 2 (контент): новые карточки для каждого тира.
- Спек 3 (берсерк): cleave-автоатака по дефолту + легендарка-переключатель в круговой режим, эпик «рывок наносит 300% от урона автоатаки».

В этом спеке — только инфраструктура. Никакого нового контента, кроме минимальных тестовых карточек, нужных чтобы доказать что система работает.

## Что уже есть

- `UpgradeDef` ([src/data/upgrade_def.gd](../../../src/data/upgrade_def.gd)) с полем `rarity: enum {COMMON, RARE, EPIC}` и полем `weight: float`.
- `UpgradePool.roll_for(rng, player, count)` ([src/progression/upgrade_pool.gd](../../../src/progression/upgrade_pool.gd)) — фильтрует по `class_filter` и весам, шафлит, режет до count. Конвенция: `weight <= 0` = «milestone-only, не появляется в random-роллах».
- `UpgradeOffer._milestones_for(player, level)` ([src/progression/upgrade_offer.gd:123](../../../src/progression/upgrade_offer.gd)) — хардкод-список для конкретных пар (класс, уровень). Сейчас используется только для арбалетчика на 5м.
- `Player._upgrade_stacks: Dictionary` ([src/player/player.gd:360](../../../src/player/player.gd)) — счётчик стаков, уже инкрементится в `apply_upgrade_def()`.
- `LevelUpScreen` ([src/ui/level_up_screen.gd](../../../src/ui/level_up_screen.gd)) — UI, рендерит 3 карточки, имеет константы `RARITY_LABELS`, `RARITY_COLORS`, `RARITY_BORDER_WIDTH` индексированные 0..2.

## Что меняем

### 1. `UpgradeDef`: добавить `LEGENDARY` и `max_stacks`

```gdscript
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var rarity: Rarity = Rarity.COMMON
@export var max_stacks: int = 0   # 0 = бесконечно; иначе явный кэп
```

Эффективный кэп вычисляется ролл-логикой через хелпер `effective_max_stacks(def)`:

```gdscript
static func effective_max_stacks(def: UpgradeDef) -> int:
    if def.max_stacks > 0:
        return def.max_stacks
    match def.rarity:
        Rarity.COMMON:    return 0   # 0 = бесконечно
        Rarity.RARE:      return 3
        Rarity.EPIC:      return 2
        Rarity.LEGENDARY: return 1
    return 0
```

Соответственно:

| Тир | `max_stacks=0` на .tres → эффективный кэп |
|---|---|
| COMMON | 0 (бесконечно) |
| RARE | 3 |
| EPIC | 2 |
| LEGENDARY | 1 |

Common с явным кэпом (dodge, cooldown, movespeed) — выставляется на .tres напрямую (`max_stacks = 5` и т.д.). Стак-фильтр в пуле: пускаем карточку, если `effective_max_stacks == 0` или `_upgrade_stacks[id] < effective_max_stacks`.

### 2. `UpgradePool`: тиро-зависимый ролл и стак-фильтр

Новая публичная сигнатура:

```gdscript
static func roll_for(rng, player, count, level: int) -> Array
```

Логика:

1. **Определить целевой тир по уровню:**
   - `level == 10` → `LEGENDARY`
   - `level % 5 == 0 and level != 10` → `EPIC` (т.е. 5, 15, 20, 25, 30, …)
   - иначе → `null` (обычный пул common+rare)

2. **Собрать пул** из `Defs.upgrades.values()`:
   - целевой тир `LEGENDARY` или `EPIC` → берём только этот тир
   - целевой тир `null` → берём `{COMMON, RARE}` единым списком, без весов
   - класс-фильтр: `class_filter` пуст или содержит `player.klass`
   - стак-фильтр: `effective_max_stacks(def) == 0` или `_upgrade_stacks[def.id] < effective_max_stacks(def)`

3. **Перемешать равномерно** (без `weight`-логики; см. ниже про `weight`) и взять до `count` уникальных.

4. **Фолбэк:** если набралось < count, добрать из общего common+rare пула (с теми же фильтрами). Если и там пусто — вернуть сколько есть (UI просто покажет меньше карточек; на практике этот случай невозможен пока есть хотя бы один common-апгрейд без кэпа).

### 3. Что делать со старым `weight`

Сейчас `weight` решает две задачи:
- задаёт относительные веса в рандомном пуле,
- `weight <= 0` = «milestone-only, не выпадает случайно».

После рефакторинга:
- **Вес игнорируется в роллинге** — common+rare и эпики/леги тянутся равномерно из своих пулов.
- **`weight <= 0`-маркер уходит**. Сейчас 3 .tres имеют `weight = 0.0` (milestone-only): `crossbow_roll_volley`, `crossbow_charge_master`, `crossbow_bolt_damage`. В этом же спеке они переводятся на `rarity = EPIC` (см. ниже про compat). Остальные 14 .tres имеют `weight = 1.0`.
- Поле `weight` остаётся в `UpgradeDef` (чтобы не ломать существующие .tres), но не читается из кода. Удаление поля — отдельный клин-ап после Спека 2.

### 4. `UpgradeOffer`: новый контракт с пулом

В `_start_round`:

```gdscript
var picks: Array = UpgradePool.roll_for(_rng, player, 3, new_level)
```

Удалить `_ensure_milestone_pick()` и `_milestones_for()` — их роль теперь играет тир-логика в пуле. Хардкод трёх milestone-апгрейдов арбалетчика (`crossbow_roll_volley`, `crossbow_charge_master`, `crossbow_bolt_damage`) переводим в этом же спеке на `rarity = EPIC` в их .tres-файлах (плюс убираем `weight = 0.0`). Это чисто контент-перенос, не ломает существующее поведение арбалетчика — он по-прежнему получит свои фирменные карточки на 5м (теперь как эпик-оффер из общего эпик-пула).

### 5. `LevelUpScreen`: четвёртый тир в UI

```gdscript
const RARITY_LABELS := ["Обычная", "Редкая", "Эпическая", "Легендарная"]
const RARITY_COLORS := [
    Color(0.55, 0.55, 0.55),
    Color(0.30, 0.62, 0.95),
    Color(0.78, 0.45, 0.95),
    Color(1.00, 0.78, 0.20),   # gold
]
const RARITY_BORDER_WIDTH := [1, 2, 2, 3]
```

`_make_card()`: заменить `clamp(int(def.rarity), 0, 2)` → `clamp(int(def.rarity), 0, 3)`.

Опциональная полировка (можно в follow-up): отдельный glow/анимация открытия для легендарной карточки.

## Контракты

- **Authority:** ролл и применение апгрейдов остаются host-only. Пул и стаки — host-only словарь, клиенту не нужны (он видит итоговый результат через репликацию StatBlock).
- **Детерминизм пула в забеге:** при одинаковом RNG-seed и одинаковой истории пиков пул повторяется. Это уже свойство существующей системы, ничего нового не добавляем.
- **Class-filter работает одинаково для всех тиров.** Эпик `dash_300_auto` (Спек 3) с `class_filter = [&"berserker"]` будет видеть только варвар. Кросс-классовые эпики/легендарки допустимы (пустой filter).

## Что не входит в этот спек

- Конкретный новый контент (новые common/rare/epic/legendary карточки) — Спек 2.
- Берсерк-cleave + легендарка-переключатель — Спек 3.
- Эпик «рывок 300% автоатаки» — Спек 3.
- Аудио/анимации легендарного открытия — последующая полировка.
- Удаление поля `weight` из `UpgradeDef` — отдельный клин-ап.
- Архетипы и их влияние на пул — Tier 2 в концепте.

## Тесты

Сценарный тест в `tests/rarity_offer/rarity_offer.tscn` + `.gd` (новый). Тест дёргает `UpgradePool.roll_for()` напрямую, без фактического левел-апа в раунде:

1. Регистрируем в `Defs.upgrades` минимальную тестовую тушку: 1 common (`max_stacks=2`), 1 rare, 1 epic, 1 legendary — все универсальные (пустой `class_filter`).
2. `roll_for(rng, player, 3, level=4)` → среди возвращённых нет эпиков/легендарок, только common+rare.
3. `roll_for(rng, player, 3, level=5)` → среди возвращённых есть карточка с `rarity == EPIC`.
4. `roll_for(rng, player, 3, level=10)` → среди возвращённых есть карточка с `rarity == LEGENDARY`.
5. `roll_for(rng, player, 3, level=11)` → снова только common+rare.
6. Дважды применить тестовый common (через `apply_upgrade_def`) → последующий `roll_for` не возвращает эту карточку.
7. Удалить тестовый epic из `Defs.upgrades`. `roll_for(rng, player, 3, level=5)` → ровно 3 карточки, все common+rare (фолбэк сработал).

`make smoke` остаётся обязательным — проверить что существующие игровые сценарии не сломались.

## Риски и compat

- **Существующие 17 .tres-файлов.** Все остаются `COMMON, max_stacks=0` — не меняем поведение существующих апгрейдов в этом спеке. Перетиражирование (пометка некоторых как rare/epic) — в Спеке 2.
- **Crossbow milestone на уровне 5.** После рефакторинга на 5м арбалетчик увидит эпик-оффер. Поэтому в этом же спеке три бывших milestone-апгрейда (`crossbow_roll_volley`, `crossbow_charge_master`, `crossbow_bolt_damage`) меняем на `rarity = EPIC` в их .tres. Это сохраняет UX (на 5м арбалетчик видит свои фирменные перки), но переводит их на новые рельсы. Без этого изменения арбалетчик на 5м увидит фолбэк common+rare — регрессия.
- **Нет легендарок в пуле на момент мержа этого спека.** На 10м оффер сделает фолбэк → 3 common+rare. Это не баг, а ожидаемое поведение «контент ещё не наполнен». В Спеке 3 появится первая легендарка (берсерк-circle).

## Acceptance criteria

- `UpgradeDef.Rarity` имеет 4 значения, на ресурсе можно выставить `LEGENDARY`.
- `UpgradeDef.max_stacks` есть, по дефолту 0.
- `UpgradePool.roll_for(rng, player, count, level)` принимает уровень и роллит правильный тир по таблице кадэнса.
- Кэпы соблюдаются: при достижении `effective_max_stacks` карточка не появляется в дальнейших роллах.
- Фолбэк работает: если эпиков для игрока нет, оффер на эпик-уровне всё равно показывает 3 карточки common+rare.
- `LevelUpScreen` рендерит легендарную карточку с золотой рамкой.
- Старые milestone-апгрейды арбалетчика на 5м всё ещё показываются (как эпик-оффер).
- `make smoke` зелёный, новый сценарный тест зелёный.
