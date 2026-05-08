extends Node2D

# Echo Clone — наследие mage_blink под легендаркой `mage_echo_clone`.
# Стоит на исходной позиции мага. Когда мага кастит fireball/chain, клон
# через 0.10s повторяет каст в ближайшего к КЛОНУ врага. После 3 повторов
# или 25s или повторного блинка — растворяется.
#
# Host-only логика. Клиент рендерит позицию + счётчик. Поля @export'ятся
# через MultiplayerSpawner (spawn-only — не синкаются после спавна).

const REPEAT_DELAY: float = 0.10
const LIFETIME_MAX: float = 25.0
const FADE_DURATION: float = 0.4

@export var owner_peer_id: int = 0
@export var repeats_left: int = 3
@export var fading: bool = false

var owner_player: Node = null
var _pending: Array = []
var _spawn_time: float = 0.0
var _fade_started_at: float = -1.0

func _ready() -> void:
	add_to_group("echo_clones")
	_spawn_time = _now()
	if GameState.is_authority():
		_resolve_owner_player()
	_update_counter()

func _resolve_owner_player() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.peer_id) == owner_peer_id:
			owner_player = p
			# Заменяем предыдущий активный клон, если был.
			var prev: Node = p._echo_clone
			if prev != null and prev != self and is_instance_valid(prev):
				prev.start_fade()
			p._echo_clone = self
			return

func _physics_process(_delta: float) -> void:
	if not GameState.is_authority():
		_update_counter()
		return
	var t: float = _now()
	if t - _spawn_time > LIFETIME_MAX and not fading:
		start_fade()
		return
	if fading:
		if t - _fade_started_at >= FADE_DURATION:
			_destroy()
		return
	if _pending.is_empty():
		return
	var head: Dictionary = _pending[0]
	if t < float(head.get("at", 0.0)):
		return
	_pending.pop_front()
	var kind: StringName = StringName(String(head.get("kind", &"")))
	if owner_player == null or not bool(owner_player.alive):
		start_fade()
		return
	if _cast(kind):
		repeats_left -= 1
		if repeats_left <= 0:
			start_fade()

func on_player_cast(kind: StringName) -> void:
	if not GameState.is_authority() or fading:
		return
	if kind != &"fireball" and kind != &"chain":
		return
	_pending.append({"kind": kind, "at": _now() + REPEAT_DELAY})

# Pure visual: клон неуязвим. Метод тут для совместимости с возможным
# таргетингом (хотя клон в группе echo_clones, не enemies).
func apply_damage(_amount: float, _team: String) -> void:
	pass

func start_fade() -> void:
	if fading:
		return
	fading = true
	_fade_started_at = _now()

func _process(_delta: float) -> void:
	var sprite := get_node_or_null("Sprite")
	if sprite == null:
		return
	if fading:
		var t: float = _now() - _fade_started_at
		var k: float = clampf(1.0 - t / FADE_DURATION, 0.0, 1.0)
		sprite.modulate = Color(0.45, 0.65, 1.0, 0.55 * k)
	else:
		sprite.modulate = Color(0.45, 0.65, 1.0, 0.55)

func _update_counter() -> void:
	var lbl := get_node_or_null("Counter")
	if lbl == null:
		return
	lbl.text = str(max(repeats_left, 0))

func _destroy() -> void:
	if owner_player != null and owner_player.has_method("notify_echo_clone_destroyed"):
		owner_player.notify_echo_clone_destroyed(self)
	queue_free()

func _cast(kind: StringName) -> bool:
	if kind == &"fireball":
		return _cast_fireball()
	if kind == &"chain":
		return _cast_chain()
	return false

func _cast_fireball() -> bool:
	var target: Node2D = Targeting.nearest_enemy(get_tree(), global_position, 9999.0)
	if target == null:
		_pending.push_front({"kind": &"fireball", "at": _now() + REPEAT_DELAY})
		return false
	var fb_skill = _player_skill(&"primary_skill")
	if fb_skill == null:
		return false
	var aoe_radius: float = float(fb_skill.aoe_radius) if "aoe_radius" in fb_skill else 80.0
	var aoe_damage: float = float(fb_skill.aoe_damage) if "aoe_damage" in fb_skill else 8.0
	var projectile_speed: float = float(fb_skill.projectile_speed) if "projectile_speed" in fb_skill else 480.0
	var projectile_lifetime: float = float(fb_skill.projectile_lifetime) if "projectile_lifetime" in fb_skill else 1.5
	var projectile_radius: float = float(fb_skill.projectile_radius) if "projectile_radius" in fb_skill else 7.0
	var rm: float = owner_player.range_mult()
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var origin: Vector2 = global_position + dir * 16.0
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null:
		arena.spawn_projectile({
			"pos": origin,
			"vel": dir * projectile_speed,
			"damage": 0.0,
			"lifetime": projectile_lifetime,
			"team": "player",
			"color": Color(0.85, 0.95, 1.0),
			"radius": projectile_radius,
			"pierce": 0,
			"source_peer": owner_peer_id,
			"mana_on_hit_pct": 0.0,
			"sprite_path": "",
			"sprite_size": Vector2.ZERO,
		})
	var fb_flat: float = owner_player.stats.value(StatBlock.STAT_FIREBALL_DAMAGE)
	var dmg: float = (aoe_damage + fb_flat) * owner_player.dmg_mult()
	for e in Targeting.enemies_in_radius(get_tree(), target.global_position, aoe_radius * rm):
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
	return true

func _cast_chain() -> bool:
	var chain_skill = _player_skill(&"secondary_skill")
	if chain_skill == null:
		return false
	var hops: int = int(chain_skill.hops) if "hops" in chain_skill else 3
	var jump_range: float = float(chain_skill.jump_range) if "jump_range" in chain_skill else 600.0
	var damage_per_hit: float = float(chain_skill.damage_per_hit) if "damage_per_hit" in chain_skill else 18.0
	var first: Node2D = Targeting.nearest_enemy(get_tree(), global_position, jump_range * owner_player.range_mult())
	if first == null:
		_pending.push_front({"kind": &"chain", "at": _now() + REPEAT_DELAY})
		return false
	var picked: Array = []
	var src: Vector2 = global_position
	var dmg: float = damage_per_hit * owner_player.dmg_mult()
	var jr: float = jump_range * owner_player.range_mult()
	var total_hops: int = hops + int(owner_player.stats.value(StatBlock.STAT_CHAIN_HOPS))
	for _i in total_hops:
		var e: Node2D = Targeting.nearest_enemy_excluding(get_tree(), src, jr, picked)
		if e == null:
			break
		picked.append(e)
		if e.has_method("apply_damage"):
			e.apply_damage(dmg, "player")
		src = e.global_position
	return true

func _player_skill(field: StringName) -> Node:
	if owner_player == null or owner_player.class_node == null:
		return null
	return owner_player.class_node.get(field)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
