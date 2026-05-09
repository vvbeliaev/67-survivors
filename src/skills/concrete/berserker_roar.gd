extends Skill

# Берсерк-ПКМ: ставит у себя под ногами «чучело» — неподвижную копию варвара,
# на которую переключается весь aggro врагов (через Targeting.nearest_decoy).
# Чучело имеет 50 ХП, не атакует, не двигается. STAT_RETALIATION владельца
# срабатывает на попадания по чучелу. Анимация рёва (расходящееся красное
# кольцо) рисуется самим чучелом в момент спавна — чтобы FX исходила от
# точки установки, а не от игрока.

@export var fx_radius: float = 240.0
@export var hold_duration: float = 0.0   # legacy, не используется

func _init() -> void:
	base_cooldown = 8.0
	icon = preload("res://assets/images/icons/totem-mask.svg")

const DECOY_BASE_HP := 50.0
const DECOY_BASE_LIFETIME := 5.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	_despawn_existing_decoy()
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null or not arena.has_method("spawn_minion"):
		return
	var r: float = fx_radius * owner_player.range_mult()
	# Бонус-ХП от STAT_DECOY_HP_BONUS: чучело наследует долю max_hp варвара.
	var hp_bonus_pct: float = float(owner_player.stats.value(StatBlock.STAT_DECOY_HP_BONUS))
	var bonus_hp: float = float(owner_player.stats.value(StatBlock.STAT_MAX_HP)) * hp_bonus_pct
	var decoy_max_hp: float = DECOY_BASE_HP + max(bonus_hp, 0.0)
	# Лайфтайм: 5с + STAT_DECOY_LIFETIME (флэт-секунды).
	var lifetime_bonus: float = float(owner_player.stats.value(StatBlock.STAT_DECOY_LIFETIME))
	var decoy_lifetime: float = DECOY_BASE_LIFETIME + max(lifetime_bonus, 0.0)
	arena.spawn_minion({
		"kind": "berserker_decoy",
		"pos": owner_player.global_position,
		"owner_peer_id": owner_player.peer_id,
		"fx_radius": r,
		"max_hp": decoy_max_hp,
		"lifetime": decoy_lifetime,
	})
	AudioBus.play_at(&"berserker_roar", owner_player.global_position)

func _despawn_existing_decoy() -> void:
	# 1 чучело на варвара: повторный каст сначала чистит старое.
	for d in get_tree().get_nodes_in_group("decoys"):
		if not is_instance_valid(d):
			continue
		if int(d.owner_peer_id) == int(owner_player.peer_id):
			d.queue_free()
