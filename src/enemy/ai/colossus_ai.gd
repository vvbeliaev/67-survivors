extends EnemyAI

# Colossus: same melee shape as a tank, but emits a buff aura. At setup it
# rolls one of three aura kinds (armor / speed / hp). Every PULSE_INTERVAL
# seconds, all alive enemies inside AURA_RADIUS (including self) get the
# corresponding effect: armor & speed are persistent buffs that decay if the
# colossus stops pulsing them, hp is an instant heal per pulse.

const AURA_RADIUS: float = 220.0
const PULSE_INTERVAL: float = 2.0
const BUFF_DURATION: float = PULSE_INTERVAL + 0.5  # natural decay
const HEAL_PER_PULSE: float = 10.0

const AURA_KINDS: Array[StringName] = [&"armor", &"speed", &"hp"]

var _attack_cd: float = 0.0
var _pulse_cd: float = 0.0

func setup(e: Node) -> void:
	super.setup(e)
	e.aura_radius = AURA_RADIUS
	if e.aura_kind == &"":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		e.aura_kind = AURA_KINDS[rng.randi() % AURA_KINDS.size()]
	# First pulse fires almost immediately so spawn-then-buff is visible.
	_pulse_cd = 0.4

func tick(delta: float) -> void:
	var e := owner_enemy
	_pulse_cd -= delta
	if _pulse_cd <= 0.0:
		_pulse_cd = PULSE_INTERVAL
		_emit_pulse()
	if _now() < e.stunned_until:
		e.velocity = Vector2.ZERO
		return
	var target := _pick_target()
	if target == null:
		e.velocity = Vector2.ZERO
		return
	var to_t: Vector2 = target.global_position - e.global_position
	var dist: float = to_t.length()
	var dir: Vector2 = to_t.normalized() if dist > 0.001 else Vector2.ZERO
	e.velocity = dir * e.move_speed * e.move_speed_mult
	_attack_cd -= delta
	if dist < e.radius + 18.0 and _attack_cd <= 0.0:
		_attack_cd = e.contact_cd
		if target.has_method("apply_damage"):
			target.apply_damage(e.contact_damage, "enemy")

func _emit_pulse() -> void:
	var e := owner_enemy
	if not e.alive:
		return
	# Bumping the seq triggers the expanding-ring animation on every peer.
	e.pulse_seq = e.pulse_seq + 1
	var kind: StringName = e.aura_kind
	for other in Targeting.enemies_in_radius(get_tree(), e.global_position, AURA_RADIUS):
		if not is_instance_valid(other) or not other.alive:
			continue
		if kind == &"hp":
			if other.has_method("heal"):
				other.heal(HEAL_PER_PULSE)
			if other.has_method("apply_aura_buff"):
				other.apply_aura_buff(&"hp", BUFF_DURATION)
		else:
			if other.has_method("apply_aura_buff"):
				other.apply_aura_buff(kind, BUFF_DURATION)
