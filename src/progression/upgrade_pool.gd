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
