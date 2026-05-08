extends ClassNode

# Jotaro — герой без активных скиллов. Вместо них рядом постоянно живёт
# Star Platinum: ходит сам, выбирает цель = ближайший к Джотаро враг и
# бьёт её кулаками раз в 0.1с. Сам Джотаро оружия не имеет — только
# базовые движение и стэты.

func seed_stats(def: ClassDef, stats: StatBlock) -> void:
	stats.set_base(StatBlock.STAT_MAX_HP, def.base_max_hp)
	stats.set_base(StatBlock.STAT_MAX_MP, def.base_max_mp)
	stats.set_base(StatBlock.STAT_MP_REGEN, def.base_mana_regen)
	stats.set_base(StatBlock.STAT_SPEED, def.base_speed)
	stats.set_base(StatBlock.STAT_DMG, 1.0)
	stats.set_base(StatBlock.STAT_RANGE, 1.0)
	stats.set_base(StatBlock.STAT_COOLDOWN, 1.0)

func build_skills() -> void:
	# Без активных скиллов — стенд решает всё.
	pass

func on_player_ready() -> void:
	var arena := owner_player.get_tree().get_first_node_in_group("arena")
	if arena == null or not arena.has_method("spawn_minion"):
		return
	arena.spawn_minion({
		"kind": &"star_platinum",
		"pos": owner_player.global_position + Vector2(36.0, -8.0),
		"owner_peer_id": int(owner_player.peer_id),
	})
