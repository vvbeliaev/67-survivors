extends Skill

# Chain lightning. Picks N nearest unique targets within range, bouncing from
# each successive enemy.

@export var hops: int = 3
@export var jump_range: float = 600.0
@export var damage_per_hit: float = 18.0

func _init() -> void:
	base_cooldown = 4.0
	mana_cost = 50.0

func on_pressed() -> void:
	if not ready_to_cast():
		return
	consume_cost()
	start_cooldown()
	var picked: Array = []
	var pts: Array = [owner_player.global_position]
	var src: Vector2 = owner_player.global_position
	var dmg: float = damage_per_hit * owner_player.dmg_mult()
	var jr: float = jump_range * owner_player.range_mult()
	for _i in hops:
		var e := Targeting.nearest_enemy_excluding(get_tree(), src, jr, picked)
		if e == null:
			break
		picked.append(e)
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
		pts.append(e.global_position)
		src = e.global_position
	owner_player.emit_fx("chain", {"points": pts})
