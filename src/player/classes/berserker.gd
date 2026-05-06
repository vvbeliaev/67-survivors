extends ClassNode

const MeleeSwirl     := preload("res://src/skills/concrete/melee_swirl.gd")
const BerserkerDash  := preload("res://src/skills/concrete/berserker_dash.gd")
const BerserkerRoar  := preload("res://src/skills/concrete/berserker_roar.gd")
const BerserkerQuake := preload("res://src/skills/concrete/berserker_quake.gd")

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)

func build_skills() -> void:
	auto_skill = MeleeSwirl.new()
	primary_skill = BerserkerDash.new()
	secondary_skill = BerserkerRoar.new()
	utility_skill = BerserkerQuake.new()
	_attach(auto_skill)
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)
