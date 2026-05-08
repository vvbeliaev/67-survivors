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

# UI icon shown on the skill bar. Subclasses preload it in _init().
var icon: Texture2D = null
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
			_apply_lifesteal(dmg)

# Конус-удар вокруг направления aim. half_arc_rad = половина раствора в радианах.
# Враг попадает, если расстояние от center ≤ r и угол между (e - center) и aim
# ≤ half_arc_rad. Враги вплотную к center (dist < 1px) считаются попаданиями.
func _cone_damage(center: Vector2, aim: Vector2, r: float, half_arc_rad: float, dmg: float) -> void:
	var aim_n: Vector2 = aim.normalized() if aim.length() > 0.0001 else Vector2.RIGHT
	for e in Targeting.enemies_in_radius(get_tree(), center, r):
		if not e.has_method("apply_damage"):
			continue
		var d: Vector2 = e.global_position - center
		if d.length() < 1.0:
			e.apply_damage(dmg, "player")
			_apply_lifesteal(dmg)
			continue
		var angle: float = abs(aim_n.angle_to(d.normalized()))
		if angle > half_arc_rad:
			continue
		e.apply_damage(dmg, "player")
		_apply_lifesteal(dmg)

func _apply_lifesteal(dmg: float) -> void:
	if owner_player == null:
		return
	var ls: float = owner_player.lifesteal()
	if ls > 0.0:
		owner_player.heal(dmg * ls)

# True, если у игрока хотя бы один стак указанного апгрейда.
func _has_upgrade(id: StringName) -> bool:
	if owner_player == null:
		return false
	return int(owner_player._upgrade_stacks.get(id, 0)) > 0

func _spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, color: Color, life: float, r: float, pierce: int, extras: Dictionary = {}) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena == null:
		return
	var data: Dictionary = {
		"pos": pos,
		"vel": vel,
		"damage": dmg,
		"lifetime": life,
		"team": "player",
		"color": color,
		"radius": r,
		"pierce": pierce,
	}
	for k in extras.keys():
		data[k] = extras[k]
	arena.spawn_projectile(data)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func trigger_visual_fx(kind: String, data: Dictionary = {}) -> void:
	if owner_player != null and owner_player.has_method("play_visual_fx"):
		owner_player.play_visual_fx(kind, data)
