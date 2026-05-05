class_name Skill extends Node

# Base for every active and auto-cast ability. Owned by a class node which is
# itself a child of Player. Server-authoritative: only the host runs `tick()`
# and the input hooks. Clients keep this node alive only for parity; nothing
# observable happens there.
#
# Subclasses override the hooks they care about. Cooldown bookkeeping is
# centralised here so concrete skills only deal with effects.

@export var base_cooldown: float = 1.0
@export var mana_cost: float = 0.0

var owner_player: Node = null   # set by ClassNode at attach time
var cooldown_left: float = 0.0

func attach(player: Node) -> void:
	owner_player = player

func tick(_delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = max(cooldown_left - _delta, 0.0)
	on_tick(_delta)

# Returns true if cooldown elapsed and mana suffices.
func ready_to_cast() -> bool:
	if cooldown_left > 0.0:
		return false
	if mana_cost > 0.0 and owner_player.mp < mana_cost:
		return false
	return true

func consume_cost() -> void:
	if mana_cost > 0.0:
		owner_player.mp = max(owner_player.mp - mana_cost, 0.0)

func start_cooldown() -> void:
	cooldown_left = base_cooldown * owner_player.cooldown_factor()

# ---- Hooks (override in subclasses) -------------------------------------

func on_tick(_delta: float) -> void:
	pass

func on_pressed() -> void:
	pass

func on_held(_delta: float) -> void:
	pass

func on_released() -> void:
	pass

# ---- Helpers exposed to subclasses --------------------------------------

func _aoe_damage(center: Vector2, r: float, dmg: float) -> void:
	for e in Targeting.enemies_in_radius(get_tree(), center, r):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
			var ls: float = owner_player.lifesteal()
			if ls > 0.0:
				owner_player.heal(dmg * ls)

func _spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, color: Color, life: float, r: float, pierce: int) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	arena.spawn_projectile({
		"pos": pos,
		"vel": vel,
		"damage": dmg,
		"lifetime": life,
		"team": "player",
		"color": color,
		"radius": r,
		"pierce": pierce,
	})

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func trigger_visual_fx(kind: String, data: Dictionary = {}) -> void:
	if owner_player != null and owner_player.has_method("play_visual_fx"):
		owner_player.play_visual_fx(kind, data)
