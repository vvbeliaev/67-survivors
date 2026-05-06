extends ClassNode

# Crossbow: auto-fires toward the cursor; holding LMB pauses the auto and
# starts a charge whose damage scales with hold time. While charging the
# player gets a movement-speed slow that this class node owns as a named
# stat modifier so it composes cleanly with everything else.

const CrossbowAutoBolt   := preload("res://src/skills/concrete/crossbow_auto_bolt.gd")
const CrossbowChargeShot := preload("res://src/skills/concrete/crossbow_charge_shot.gd")
const CrossbowPierce     := preload("res://src/skills/concrete/crossbow_pierce.gd")
const CrossbowRoll       := preload("res://src/skills/concrete/crossbow_roll.gd")

const CHARGE_SLOW_MOD := &"crossbow_charge_slow"

var _slow_active: bool = false

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)
	stats.set_base(StatBlock.STAT_CHARGE_SLOW, -0.75)
	stats.set_base(StatBlock.STAT_CHARGE_DAMAGE, 1.0)

func build_skills() -> void:
	auto_skill = CrossbowAutoBolt.new()
	primary_skill = CrossbowChargeShot.new()
	secondary_skill = CrossbowPierce.new()
	utility_skill = CrossbowRoll.new()
	_attach(auto_skill)
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)

func on_pre_move(_delta: float) -> void:
	var charging: bool = owner_player.charge_started_at >= 0.0
	var slow: float = min(owner_player.stats.value(StatBlock.STAT_CHARGE_SLOW), 0.0)
	var should_apply: bool = charging and slow < 0.0
	if should_apply:
		owner_player.stats.add_pct(StatBlock.STAT_SPEED, CHARGE_SLOW_MOD, slow)
		_slow_active = true
	elif _slow_active:
		owner_player.stats.remove(CHARGE_SLOW_MOD)
		_slow_active = false
