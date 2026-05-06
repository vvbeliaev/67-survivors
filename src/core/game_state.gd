extends Node

# Slim run-state autoload. Holds only data that is genuinely cross-system:
# pre-arena identity, roster, and live run progress. Cross-system events go
# through EventBus. Multiplayer authority helpers live here for convenience.

const RUN_DURATION := 600.0
const BOSS_HP := 4000
const VALID_CLASSES: Array[StringName] = [&"berserker", &"mage", &"bard", &"crossbow"]

const NICK_POOL: Array[String] = [
	"Vrok", "Asha", "Lyra", "Korin", "Tessa", "Mireth", "Brann", "Sylvi",
	"Drevan", "Kyra", "Orin", "Zara", "Hark", "Nyssa", "Garrick", "Veska",
	"Toren", "Iska", "Roan", "Mira", "Ulrik", "Selen", "Bram", "Rune",
	"Yarko", "Lada", "Borya", "Slava", "Drago", "Velka",
]

# Pre-arena identity (set by lobby UI before starting the round).
var local_nick: String = ""
var local_class: StringName = &"berserker"

# peer_id -> {nick: String, klass: StringName}
var roster: Dictionary = {}

# Live arena state. Host-authoritative; replicated via RunDirector RPCs.
var run_active: bool = false
var run_time: float = 0.0
var party_level: int = 1
var party_xp: int = 0

signal roster_changed
signal party_level_changed(new_level: int)
signal run_state_changed(active: bool, won: bool)

func _ready() -> void:
	if local_nick.is_empty():
		local_nick = NICK_POOL[randi() % NICK_POOL.size()]

func reset_run() -> void:
	run_active = false
	run_time = 0.0
	party_level = 1
	party_xp = 0

func xp_threshold(level: int) -> int:
	return 5 + 3 * level + level * level

func is_networked() -> bool:
	return multiplayer.multiplayer_peer != null

func is_host() -> bool:
	return is_networked() and multiplayer.is_server()

# Authority = host OR offline solo. Used by every simulation gate.
func is_authority() -> bool:
	return not is_networked() or multiplayer.is_server()

func is_valid_class(klass: StringName) -> bool:
	return VALID_CLASSES.has(klass)
