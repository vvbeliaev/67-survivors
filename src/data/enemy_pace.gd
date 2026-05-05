class_name EnemyPace extends RefCounted

# Single knob for the whole run (waves, player upgrades, etc. stay unchanged).
static var global_move_mult: float = 1.0

# px/s for types listed here — keeps *relative* pacing in one place. Anything
# not listed (e.g. boss) uses EnemyDef.move_speed as authored.
const _MOVE_SPEED_BY_ID: Dictionary = {
	&"rusher": 115.0,
	&"swarm": 200.0,
	&"ranged": 82.0,
	&"tank": 62.0,
	&"colossus": 38.0,
}


static func move_speed(def: EnemyDef) -> float:
	var base: float
	if _MOVE_SPEED_BY_ID.has(def.id):
		base = float(_MOVE_SPEED_BY_ID[def.id])
	else:
		base = def.move_speed
	return base * global_move_mult
