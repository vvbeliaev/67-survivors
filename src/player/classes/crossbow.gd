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
const MAX_CHARGE_TIME: float = 1.5   # должна совпадать с crossbow_charge_shot.max_charge
const MINIGUN_UPG: StringName = &"legendary_crossbow_minigun"
# Реген перегрева в режиме болтомёта: молчит MINIGUN_REGEN_DELAY секунд после
# последнего выстрела, потом включается на MINIGUN_REGEN_RATE/сек (полная
# полоска mp=100 заливается за 100/67 ≈ 1.5с).
const MINIGUN_REGEN_DELAY: float = 1.0
const MINIGUN_REGEN_RATE: float = 67.0
const MINIGUN_REGEN_MOD: StringName = &"crossbow_minigun_regen"

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
	var p := owner_player
	var has_minigun: bool = int(p._upgrade_stacks.get(MINIGUN_UPG, 0)) > 0
	# Slow срабатывает в обоих режимах: либо классическая зарядка (charge_started_at),
	# либо минигановское удержание ЛКМ. Так апгрейды на STAT_CHARGE_SLOW работают
	# единообразно в любом режиме — можно качать «−25/50/75% замедления при стрельбе»
	# и получать уменьшение slow и в зарядке, и в очереди.
	var charging: bool = p.charge_started_at >= 0.0
	var minigun_firing: bool = has_minigun and bool(p._in_primary_held)
	var should_apply_slow: bool = charging or minigun_firing
	var slow: float = min(p.stats.value(StatBlock.STAT_CHARGE_SLOW), 0.0)
	if should_apply_slow and slow < 0.0:
		p.stats.add_pct(StatBlock.STAT_SPEED, CHARGE_SLOW_MOD, slow)
		_slow_active = true
	elif _slow_active:
		p.stats.remove(CHARGE_SLOW_MOD)
		_slow_active = false
	_tick_resource_bar()

# Шкала ресурса арбалетчика (mp / max_mp = 100):
#   • без легендарки = «концентрация»: 0 → max_mp за время удержания ЛКМ.
#     Просто визуальный индикатор зарядки, без какой-либо стоимости выстрела.
#   • с легендаркой = «перегрев»: целиком управляется crossbow_charge_shot
#     (стартовая заливка через refill_mana, расход 15/болт, регенит +10/сек).
#     Здесь ничего не трогаем — выходим раньше.
func _tick_resource_bar() -> void:
	var p := owner_player
	if p == null or p.max_mp <= 0.0:
		return
	if int(p._upgrade_stacks.get(MINIGUN_UPG, 0)) > 0:
		# Легендарка: чистим возможный leftover charge_started_at от старого
		# режима, чтобы slow-стат не залипал и вид не путался.
		if p.charge_started_at >= 0.0:
			p.charge_started_at = -1.0
		_tick_minigun_regen(p)
		return
	if p.charge_started_at >= 0.0:
		var t: float = clampf((Time.get_ticks_msec() / 1000.0) - p.charge_started_at, 0.0, MAX_CHARGE_TIME) / MAX_CHARGE_TIME
		p.mp = p.max_mp * t
	else:
		p.mp = 0.0

# В режиме болтомёта: вешаем/снимаем именованный мод на STAT_MP_REGEN
# в зависимости от времени с последнего выстрела. Пока стреляет (или прошло
# меньше 1с с последнего болта) — мод снят, реген базовый (0). После — мод
# +67/сек, полоска заливается за ~1.5с до краёв.
func _tick_minigun_regen(p: Node) -> void:
	if primary_skill == null:
		return
	var since_last: float = (Time.get_ticks_msec() / 1000.0) - float(primary_skill._minigun_last_shot_at)
	if since_last >= MINIGUN_REGEN_DELAY:
		p.stats.add_flat(StatBlock.STAT_MP_REGEN, MINIGUN_REGEN_MOD, MINIGUN_REGEN_RATE)
	else:
		p.stats.remove(MINIGUN_REGEN_MOD)
