extends ClassNode

const BardAuto  := preload("res://src/skills/concrete/bard_auto_bolt.gd")
const BardHeal  := preload("res://src/skills/concrete/bard_heal.gd")
const BardBuff  := preload("res://src/skills/concrete/bard_buff.gd")
const BardDodge := preload("res://src/skills/concrete/bard_dodge.gd")

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)

func build_skills() -> void:
	auto_skill = BardAuto.new()
	primary_skill = BardHeal.new()
	secondary_skill = BardBuff.new()
	utility_skill = BardDodge.new()
	_attach(auto_skill)
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)
