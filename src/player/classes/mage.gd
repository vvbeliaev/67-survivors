extends ClassNode

const MageAuto     := preload("res://src/skills/concrete/mage_auto_bolt.gd")
const MageFireball := preload("res://src/skills/concrete/mage_fireball.gd")
const MageChain    := preload("res://src/skills/concrete/mage_chain.gd")
const MageBlink    := preload("res://src/skills/concrete/mage_blink.gd")

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)

func build_skills() -> void:
	auto_skill = MageAuto.new()
	primary_skill = MageFireball.new()
	secondary_skill = MageChain.new()
	utility_skill = MageBlink.new()
	_attach(auto_skill)
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)
