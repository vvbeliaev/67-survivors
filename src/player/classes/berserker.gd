extends ClassNode

const MeleeCleave    := preload("res://src/skills/concrete/melee_cleave.gd")
const BerserkerQuake := preload("res://src/skills/concrete/berserker_quake.gd")
const BerserkerRoar  := preload("res://src/skills/concrete/berserker_roar.gd")
const BerserkerLeap  := preload("res://src/skills/concrete/berserker_leap.gd")

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)
	stats.set_base(StatBlock.STAT_STUN_RADIUS, 1.0)
	stats.set_base(StatBlock.STAT_AUTO_ATTACK_SPEED, 1.0)

func build_skills() -> void:
	auto_skill = MeleeCleave.new()
	primary_skill = BerserkerQuake.new()
	secondary_skill = BerserkerRoar.new()
	utility_skill = BerserkerLeap.new()
	_attach(auto_skill)
	_attach(primary_skill)
	_attach(secondary_skill)
	_attach(utility_skill)

# ---- Кровавая ярость (легендарка) --------------------------------------
# Каждый тик читаем долю недостающего HP и переписываем два модификатора:
# `legendary_blood_rage_auto` (PCT на STAT_AUTO_ATTACK_SPEED — только cleave-
# автоатака, прочие скиллы НЕ ускоряются) и `legendary_blood_rage_regen`
# (FLAT на STAT_HP_REGEN). Пока апгрейда нет — гарантированно снимаем оба.
# Жёсткий пол на длительность авто-кд (0.3с) живёт в MeleeCleave.start_cooldown.
const _BLOOD_RAGE_UPG: StringName = &"legendary_berserker_blood_rage"
const _BLOOD_RAGE_AUTO_MOD: StringName = &"legendary_blood_rage_auto"
const _BLOOD_RAGE_REGEN_MOD: StringName = &"legendary_blood_rage_regen"
const _BLOOD_RAGE_MAX_AUTO_BONUS: float = -0.5  # PCT на STAT_AUTO_ATTACK_SPEED
const _BLOOD_RAGE_MAX_REGEN: float = 5.0        # +HP/сек, FLAT

func on_pre_move(_delta: float) -> void:
	var p: Node = owner_player
	if p == null:
		return
	if int(p._upgrade_stacks.get(_BLOOD_RAGE_UPG, 0)) <= 0:
		p.stats.remove(_BLOOD_RAGE_AUTO_MOD)
		p.stats.remove(_BLOOD_RAGE_REGEN_MOD)
		return
	var max_hp: float = float(p.stats.value(StatBlock.STAT_MAX_HP))
	if max_hp <= 0.0:
		return
	# missing_pct: 0.0 при полном HP, 1.0 при 0 HP. Линейная шкала.
	var missing_pct: float = clampf(1.0 - float(p.hp) / max_hp, 0.0, 1.0)
	p.stats.add_pct(StatBlock.STAT_AUTO_ATTACK_SPEED, _BLOOD_RAGE_AUTO_MOD, _BLOOD_RAGE_MAX_AUTO_BONUS * missing_pct)
	p.stats.add_flat(StatBlock.STAT_HP_REGEN, _BLOOD_RAGE_REGEN_MOD, _BLOOD_RAGE_MAX_REGEN * missing_pct)
