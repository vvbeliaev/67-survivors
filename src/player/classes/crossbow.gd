extends ClassNode

# Crossbow: no auto-attack — LMB hold/release IS the primary. While charging
# the player gets a movement-speed slow that this class node owns as a named
# stat modifier so it composes cleanly with everything else.

const CrossbowChargeShot := preload("res://src/skills/concrete/crossbow_charge_shot.gd")
const CrossbowPierce     := preload("res://src/skills/concrete/crossbow_pierce.gd")
const CrossbowRoll       := preload("res://src/skills/concrete/crossbow_roll.gd")

const CHARGE_SLOW_MOD := &"crossbow_charge_slow"
const CHARGE_SLOW_PCT := -0.6

var _slow_active: bool = false

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_ATK_SPEED, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)

func build_skills() -> void:
	primary_skill = CrossbowChargeShot.new()
	secondary_skill = CrossbowPierce.new()
	utility_skill = CrossbowRoll.new()
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)

func on_pre_move(_delta: float) -> void:
	var charging: bool = owner_player.charge_started_at >= 0.0
	if charging and not _slow_active:
		owner_player.stats.add_pct(StatBlock.STAT_SPEED, CHARGE_SLOW_MOD, CHARGE_SLOW_PCT)
		_slow_active = true
	elif not charging and _slow_active:
		owner_player.stats.remove(CHARGE_SLOW_MOD)
		_slow_active = false
