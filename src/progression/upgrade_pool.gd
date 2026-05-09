class_name UpgradePool extends RefCounted

# Filters and rolls UpgradeDef resources for a specific player. Class-aware
# и rarity-routed: legendary on level 10 (one-shot), epic on multiples of 5
# (5, 15, 20…). Каждый слот «спускается» по цепочке rarities — если для класса
# нет легендарок, слот заполняется фиолетовой (эпиком), нет фиолетовых — синей
# (rare), нет синих — белой (common). На обычных уровнях позиционный layout
# сохраняется: последний слот стартует с COMMON-цепочки, остальные — с RARE.
#
# Это даёт два важных свойства:
#   • На 10 ур. крафтер без класс-легендарки получит эпик (а не common).
#   • На 5/15/20 ур. с пустым эпик-пулом упадёт RARE / COMMON, а не «дырка».

# Цепочки фолбэка идут СТРОГО ВНИЗ. COMMON в самом низу — дальше падать некуда.
const _RARITY_DESCEND: Dictionary = {
	int(UpgradeDef.Rarity.LEGENDARY): [
		UpgradeDef.Rarity.LEGENDARY, UpgradeDef.Rarity.EPIC,
		UpgradeDef.Rarity.RARE, UpgradeDef.Rarity.COMMON,
	],
	int(UpgradeDef.Rarity.EPIC): [
		UpgradeDef.Rarity.EPIC, UpgradeDef.Rarity.RARE, UpgradeDef.Rarity.COMMON,
	],
	int(UpgradeDef.Rarity.RARE): [
		UpgradeDef.Rarity.RARE, UpgradeDef.Rarity.COMMON,
	],
	int(UpgradeDef.Rarity.COMMON): [
		UpgradeDef.Rarity.COMMON,
	],
}

static func roll_for(rng: RandomNumberGenerator, player: Node, count: int, level: int) -> Array:
	var pools: Dictionary = _build_pools(rng, player)
	var seen: Dictionary = {}
	var picks: Array = []
	var target: Variant = _target_rarity_for_level(level)
	if target != null:
		# Tier-targeted уровень (5/10/15/...): все слоты стартуют с одной редкости
		# и спускаются вниз. На 10 ур. цепочка LEG→EPIC→RARE→COMMON.
		for _i in count:
			var pick: UpgradeDef = _pick_cascade(pools, int(target), seen)
			if pick == null:
				break
			picks.append(pick)
			seen[pick.id] = true
		return picks
	# Обычный уровень: позиционный — последний слот идёт с COMMON, остальные с RARE.
	# Каждый слот при пустом таргете спускается дальше вниз. RARE→COMMON, COMMON→ничего
	# (но common-пул бесконечно стакабельный, поэтому на практике никогда не пустой).
	for i in range(count):
		var is_last: bool = i == count - 1
		var start: int = int(UpgradeDef.Rarity.COMMON if is_last else UpgradeDef.Rarity.RARE)
		var pick: UpgradeDef = _pick_cascade(pools, start, seen)
		if pick == null:
			continue
		picks.append(pick)
		seen[pick.id] = true
	return picks

# Строит и шафлит пулы по каждой редкости один раз — потом мы их «вычерпываем»
# через _pop_first_unseen, так что один и тот же апгрейд не вылезет дважды.
static func _build_pools(rng: RandomNumberGenerator, player: Node) -> Dictionary:
	var out: Dictionary = {}
	for r in [UpgradeDef.Rarity.COMMON, UpgradeDef.Rarity.RARE, UpgradeDef.Rarity.EPIC, UpgradeDef.Rarity.LEGENDARY]:
		out[int(r)] = _uniform_shuffle(rng, _build_pool(player, r))
	return out

# Спуск по цепочке для одного слота. Берём первый доступный апгрейд из самой
# высокой непустой ступени; останавливаемся, когда нашли.
static func _pick_cascade(pools: Dictionary, start_rarity: int, seen: Dictionary) -> UpgradeDef:
	var chain: Array = _RARITY_DESCEND.get(start_rarity, [])
	for tier in chain:
		var pool = pools.get(int(tier))
		if pool == null:
			continue
		var pick: UpgradeDef = _pop_first_unseen(pool, seen)
		if pick != null:
			return pick
	return null

static func _target_rarity_for_level(level: int) -> Variant:
	# Особые уровни: 8-й — легендарный one-shot, остальные кратные 4 — эпик.
	# Порядок проверок важен: 8 — кратное 4, но легендарка приоритетнее.
	if level == 8:
		return UpgradeDef.Rarity.LEGENDARY
	if level > 0 and level % 4 == 0:
		return UpgradeDef.Rarity.EPIC
	return null

static func _matches(def: UpgradeDef, player: Node, target: Variant) -> bool:
	if def == null:
		return false
	# Tier filter — strict: каждый пул содержит ровно одну редкость.
	if target != null and def.rarity != int(target):
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

static func _build_pool(player: Node, target: Variant) -> Array:
	var out: Array = []
	for def in Defs.upgrades.values():
		if _matches(def, player, target):
			out.append(def)
	return out

static func _pop_first_unseen(pool: Array, seen: Dictionary) -> UpgradeDef:
	while pool.size() > 0:
		var d: UpgradeDef = pool.pop_front()
		if not seen.has(d.id):
			return d
	return null

static func _uniform_shuffle(rng: RandomNumberGenerator, defs: Array) -> Array:
	var out: Array = defs.duplicate()
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
