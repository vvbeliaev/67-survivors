extends Node

# Pre-arena lobby state (set by lobby UI before starting the round).
var local_nick: String = "P"
var local_class: String = "berserker"

# Per-peer roster: peer_id -> {nick: String, klass: String}
var roster: Dictionary = {}

# Live arena state. Host-authoritative; replicated to peers via rpc.
var run_active: bool = false
var run_time: float = 0.0
var party_level: int = 1
var party_xp: int = 0

const RUN_DURATION := 600.0
const BOSS_HP := 4000
const VALID_CLASSES := ["berserker", "mage", "bard", "crossbow"]

signal roster_changed
signal party_level_changed(new_level: int)
signal run_state_changed(active: bool, won: bool)

func reset_run() -> void:
	run_active = false
	run_time = 0.0
	party_level = 1
	party_xp = 0

func xp_threshold(level: int) -> int:
	return 100 + 50 * level

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func is_networked() -> bool:
	return multiplayer.multiplayer_peer != null

# Authority = host OR offline solo. Used by simulation code.
func is_authority() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
