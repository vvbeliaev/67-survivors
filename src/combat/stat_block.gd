class_name StatBlock extends RefCounted

# Composable stat container. Every field is a base value plus a registry of
# named modifiers — flat additive, then percent-additive on the top:
#
#   value(stat) = (base + sum(flat)) * (1.0 + sum(pct))
#
# Modifiers are addressed by StringName so upgrade stacks (`upg_damage_3`),
# auras (`aura_bard_atk_speed`), and timed buffs (`buff_haste_42`) can be
# added and removed without bookkeeping in the consumer.

# Stat ids used by the rest of the game. Listed for documentation.
const STAT_MAX_HP    := &"max_hp"      # flat
const STAT_MAX_MP    := &"max_mp"      # flat
const STAT_HP_REGEN  := &"hp_regen"    # flat
const STAT_MP_REGEN  := &"mp_regen"    # flat
const STAT_LIFESTEAL := &"lifesteal"   # flat (fraction)
const STAT_SPEED     := &"speed"       # pct on base movement
const STAT_DMG       := &"dmg"         # pct multiplier (base 1.0)
const STAT_ATK_SPEED := &"atk_speed"   # pct multiplier (base 1.0)
const STAT_RANGE     := &"range"       # pct multiplier (base 1.0)
const STAT_COOLDOWN  := &"cooldown"    # pct multiplier (base 1.0); negative reduces

var _base: Dictionary = {}    # StringName -> float
var _flats: Dictionary = {}   # StringName -> { StringName -> float }
var _pcts: Dictionary = {}    # StringName -> { StringName -> float }

func set_base(stat: StringName, v: float) -> void:
	_base[stat] = v

func base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))

func value(stat: StringName) -> float:
	var b: float = float(_base.get(stat, 0.0))
	var f: float = 0.0
	for v in _flats.get(stat, {}).values():
		f += v
	var p: float = 0.0
	for v in _pcts.get(stat, {}).values():
		p += v
	return (b + f) * (1.0 + p)

func add_flat(stat: StringName, mod_id: StringName, v: float) -> void:
	if not _flats.has(stat):
		_flats[stat] = {}
	_flats[stat][mod_id] = v

func add_pct(stat: StringName, mod_id: StringName, v: float) -> void:
	if not _pcts.has(stat):
		_pcts[stat] = {}
	_pcts[stat][mod_id] = v

func remove(mod_id: StringName) -> void:
	for s in _flats.keys():
		_flats[s].erase(mod_id)
	for s in _pcts.keys():
		_pcts[s].erase(mod_id)

# Convenience: applies a UpgradeDef as a uniquely-keyed modifier so multiple
# stacks coexist (`mod_id_<stack_index>`).
func apply_upgrade(def: UpgradeDef, stack_index: int) -> void:
	if def == null or def.stat == &"":
		return
	var key: StringName = StringName("upg_%s_%d" % [String(def.id), stack_index])
	if def.mode == UpgradeDef.Mode.FLAT:
		add_flat(def.stat, key, def.amount)
	else:
		add_pct(def.stat, key, def.amount)
