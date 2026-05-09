class_name StatBlock extends RefCounted

# Composable stat container. Every field is a base value plus a registry of
# named modifiers — flat additive, then percent-additive on the top:
#
#   value(stat) = (base + sum(flat)) * (1.0 + sum(pct))
#
# Modifiers are addressed by StringName so upgrade stacks (`upg_damage_3`),
# auras (`aura_bard_haste`), and timed buffs (`buff_haste_42`) can be
# added and removed without bookkeeping in the consumer.

# Stat ids used by the rest of the game. Listed for documentation.
const STAT_MAX_HP    := &"max_hp"      # flat
const STAT_MAX_MP    := &"max_mp"      # flat
const STAT_HP_REGEN  := &"hp_regen"    # flat
const STAT_MP_REGEN  := &"mp_regen"    # flat
const STAT_LIFESTEAL := &"lifesteal"   # flat (fraction)
const STAT_SPEED     := &"speed"       # pct on base movement
const STAT_DMG       := &"dmg"         # pct multiplier (base 1.0)
const STAT_RANGE     := &"range"       # pct multiplier (base 1.0)
const STAT_COOLDOWN  := &"cooldown"    # pct multiplier (base 1.0); negative reduces
const STAT_MANA_ON_HIT := &"mana_on_hit"   # flat (fraction of max_mp restored per auto-hit)
const STAT_CHARGE_PIERCE := &"charge_pierce"  # flat (extra pierce on crossbow charged bolt)
const STAT_CHARGE_MULTISHOT := &"charge_multishot"  # flat (extra angled bolts on crossbow charged shot)
const STAT_CHARGE_SLOW := &"charge_slow"   # pct (negative); applied to speed while crossbow is charging
const STAT_CHARGE_DAMAGE := &"charge_damage"  # pct multiplier on charge max-mult (base 1.0)
const STAT_BOLT_DAMAGE := &"bolt_damage"   # flat (added to crossbow auto-bolt and roll-volley base damage)
const STAT_CHAIN_HOPS := &"chain_hops"     # flat (extra hops on mage chain lightning)
const STAT_ROLL_VOLLEY := &"roll_volley"   # flat (radial bolts fired from roll origin)
const STAT_FIREBALL_DAMAGE := &"fireball_damage"  # flat (added to mage fireball AoE base damage)
const STAT_SLASH_ARC := &"slash_arc"       # flat (degrees added to berserker cleave arc)
const STAT_RETALIATION := &"retaliation"   # flat (fraction of incoming damage emitted as AoE around the victim)
const STAT_STUN_DURATION := &"stun_duration"  # flat (seconds added to berserker quake stun)
const STAT_STUN_RADIUS := &"stun_radius"      # pct multiplier (base 1.0); berserker quake AoE radius extra mult
const STAT_DECOY_HP_BONUS := &"decoy_hp_bonus"  # flat (fraction of berserker max_hp added to chучело's base 50)
const STAT_DECOY_LIFETIME := &"decoy_lifetime"  # flat (seconds added to chучело's base 5s lifetime)
const STAT_AUTO_ATTACK_SPEED := &"auto_attack_speed"  # pct multiplier (base 1.0); applied ONLY to auto-attack cooldown — отдельно от общего STAT_COOLDOWN
const STAT_UNCHARGED_CRIT_CHANCE := &"uncharged_crit_chance"  # flat (доля); шанс крита на незаряженных болтах арбалетчика, ×2 урон

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
# stacks coexist (`mod_id_<stack_index>`). Any `extra_stats` declared on the
# def stack under sibling keys (`mod_id_<stack_index>_x<i>`). When
# `per_stack_amounts` is non-empty, the per-stack delta overrides `def.amount`
# (clamped to last entry for stacks beyond the array length) — used for
# non-linear progressions like 30 → 45 → 60 (deltas 0.30 / 0.15 / 0.15).
func apply_upgrade(def: UpgradeDef, stack_index: int) -> void:
	if def == null:
		return
	var key: StringName = StringName("upg_%s_%d" % [String(def.id), stack_index])
	if def.stat != &"":
		var amt: float = def.amount
		if def.per_stack_amounts.size() > 0:
			var idx: int = clampi(stack_index - 1, 0, def.per_stack_amounts.size() - 1)
			amt = float(def.per_stack_amounts[idx])
		if def.mode == UpgradeDef.Mode.FLAT:
			add_flat(def.stat, key, amt)
		else:
			add_pct(def.stat, key, amt)
	var n: int = def.extra_stats.size()
	for i in n:
		var es: StringName = def.extra_stats[i]
		if es == &"":
			continue
		var em: int = int(def.extra_modes[i]) if i < def.extra_modes.size() else 0
		var ea: float = float(def.extra_amounts[i]) if i < def.extra_amounts.size() else 0.0
		var ekey: StringName = StringName("upg_%s_%d_x%d" % [String(def.id), stack_index, i])
		if em == int(UpgradeDef.Mode.FLAT):
			add_flat(es, ekey, ea)
		else:
			add_pct(es, ekey, ea)
