class_name UpgradePool extends RefCounted

# Filters and rolls UpgradeDef resources for a specific player. Class- and
# archetype-aware so the offer screen never shows useless picks (e.g. mana
# upgrades for a class with no mana).

static func roll_for(rng: RandomNumberGenerator, player: Node, count: int) -> Array:
	var pool: Array = []
	for def in Defs.upgrades.values():
		if not _matches(def, player):
			continue
		pool.append(def)
	pool = _weighted_shuffle(rng, pool)
	var picks: Array = []
	for def in pool:
		if picks.size() >= count:
			break
		picks.append(def)
	return picks

static func _matches(def: UpgradeDef, player: Node) -> bool:
	if def == null:
		return false
	# weight <= 0 means "milestone-only" — never appears in random rolls,
	# inserted explicitly by the offer layer at scripted level-ups.
	if def.weight <= 0.0:
		return false
	if def.class_filter.size() > 0 and not def.class_filter.has(player.klass):
		return false
	# Archetype filtering reserved for Tier 2.
	return true

static func _weighted_shuffle(rng: RandomNumberGenerator, defs: Array) -> Array:
	# Simple weighted shuffle: each entry gets a key = -log(rng) / weight.
	var keyed: Array = []
	for def in defs:
		var u: float = max(rng.randf(), 1e-6)
		var w: float = max(def.weight, 0.0001)
		keyed.append({"k": -log(u) / w, "d": def})
	keyed.sort_custom(func (a, b): return a.k < b.k)
	var out: Array = []
	for kv in keyed:
		out.append(kv.d)
	return out
