extends Node

# Slim run-state autoload. Holds only data that is genuinely cross-system:
# pre-arena identity, roster, and live run progress. Cross-system events go
# through EventBus. Multiplayer authority helpers live here for convenience.

const RUN_DURATION := 600.0
const BOSS_HP := 4000
# Bard temporarily disabled — class not finished. Re-add &"bard" when ready.
const VALID_CLASSES: Array[StringName] = [&"berserker", &"mage", &"crossbow", &"jotaro"]

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

# Set by lobby debug entry-point. Solo-only sandbox: no waves, manual spawn UI.
var debug_mode: bool = false

# Live arena state. Host-authoritative; replicated via RunDirector RPCs.
var run_active: bool = false
var run_time: float = 0.0
var party_level: int = 1
var party_xp: int = 0

# Aggregated run stats (host-tracked, snapshot-replicated to clients on run end).
var run_kills: int = 0
var run_damage: int = 0
var run_xp_gained: int = 0

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
	run_kills = 0
	run_damage = 0
	run_xp_gained = 0

func xp_threshold(level: int) -> int:
	return 5 + 3 * level + level * level

func is_networked() -> bool:
	# В Godot 4.6 multiplayer_peer по умолчанию — OfflineMultiplayerPeer,
	# а не null. Считаем «по сети» только если выставлен реальный peer
	# (ENet/WebSocket/WebRTC), иначе остаёмся в соло-режиме.
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

func is_host() -> bool:
	return is_networked() and multiplayer.is_server()

# Authority = host OR offline solo. Used by every simulation gate.
func is_authority() -> bool:
	return not is_networked() or multiplayer.is_server()

func is_valid_class(klass: StringName) -> bool:
	return VALID_CLASSES.has(klass)

# True when the runtime should show on-screen touch controls instead of mouse/keys.
# Mobile native build → always true. Web build → true if the device exposes a
# touchscreen, OR if the URL carries `?touch=1` (handy for testing the mobile
# UX in a desktop browser without DevTools' touch emulation).
var _touch_force_cached: int = -1  # -1 unknown, 0 no, 1 yes — eval'd once.

func is_touch_ui() -> bool:
	if OS.has_feature("mobile"):
		return true
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		return true
	if _touch_force_url():
		return true
	return false

func _touch_force_url() -> bool:
	if not OS.has_feature("web"):
		return false
	if _touch_force_cached >= 0:
		return _touch_force_cached == 1
	var v: Variant = JavaScriptBridge.eval("window.location.search.indexOf('touch=1') >= 0 ? 1 : 0", true)
	_touch_force_cached = 1 if int(v) == 1 else 0
	return _touch_force_cached == 1
