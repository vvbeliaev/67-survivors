extends Node

const POOL := [
	{"id": "max_hp", "label": "+20 max HP & heal"},
	{"id": "move_speed", "label": "+10% move speed"},
	{"id": "damage", "label": "+10% damage"},
	{"id": "atk_speed", "label": "+10% attack speed"},
	{"id": "range", "label": "+10% range"},
	{"id": "cooldown", "label": "-8% cooldowns"},
	{"id": "regen", "label": "+1 HP/sec regen"},
	{"id": "lifesteal", "label": "+5% lifesteal"},
	{"id": "mana_cap", "label": "+25 max mana"},
	{"id": "mana_regen", "label": "+3 mana/sec"},
]

func roll_three(rng: RandomNumberGenerator) -> Array:
	var pool := POOL.duplicate()
	var picks: Array = []
	for _i in 3:
		if pool.is_empty():
			break
		var idx := rng.randi() % pool.size()
		picks.append(pool[idx])
		pool.remove_at(idx)
	return picks

func label_for(id: String) -> String:
	for u in POOL:
		if u.id == id:
			return u.label
	return id
