extends Node

# Headless verification of the rarity offer pipeline. We construct minimal
# UpgradeDefs in code (registered into Defs.upgrades), spawn a stub player
# with the necessary fields, and call UpgradePool.roll_for() with various
# levels — checking the routing, the stack-cap filter, and the fallback.
#
# Run with: godot --headless res://tests/rarity_offer/rarity_offer.tscn

class _PlayerStub extends RefCounted:
	var klass: StringName = &"berserker"
	var _upgrade_stacks: Dictionary = {}

var _failures: int = 0

func _ready() -> void:
	print("[rarity] starting")
	_run()
	if _failures > 0:
		printerr("[rarity] FAIL — %d assertion(s) failed" % _failures)
		get_tree().quit(1)
	else:
		print("[rarity] OK")
		get_tree().quit(0)

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Snapshot the live registry so we can restore it.
	var saved: Dictionary = Defs.upgrades.duplicate()

	# Build minimal test fixtures, all universal (empty class_filter).
	var common_def: UpgradeDef = _make_def(&"t_common", UpgradeDef.Rarity.COMMON, 2)
	var rare_def: UpgradeDef = _make_def(&"t_rare", UpgradeDef.Rarity.RARE, 0)
	var epic_def: UpgradeDef = _make_def(&"t_epic", UpgradeDef.Rarity.EPIC, 0)
	var leg_def: UpgradeDef = _make_def(&"t_legendary", UpgradeDef.Rarity.LEGENDARY, 0)

	Defs.upgrades.clear()
	Defs.upgrades[common_def.id] = common_def
	Defs.upgrades[rare_def.id] = rare_def
	Defs.upgrades[epic_def.id] = epic_def
	Defs.upgrades[leg_def.id] = leg_def

	var player := _make_player_stub()

	# 1. Regular level → no epic/legendary, only common+rare.
	var picks := UpgradePool.roll_for(rng, player, 3, 4)
	_assert(picks.size() >= 1, "case1 picks non-empty")
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case1 only common/rare (got %d)" % p.rarity)

	# 2. Epic level (5) → must contain the epic.
	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(_has_id(picks, &"t_epic"), "case2 epic appears at level 5")
	_assert(not _has_id(picks, &"t_legendary"), "case2 no legendary at level 5")

	# 3. Legendary level (10) → must contain legendary.
	picks = UpgradePool.roll_for(rng, player, 3, 10)
	_assert(_has_id(picks, &"t_legendary"), "case3 legendary appears at level 10")
	_assert(not _has_id(picks, &"t_epic"), "case3 no epic at level 10")

	# 4. Level 11 → back to common/rare.
	picks = UpgradePool.roll_for(rng, player, 3, 11)
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case4 only common/rare (got %d)" % p.rarity)

	# 5. Stack-cap exhaustion: t_common с cap=2, выставляем counter=2 → исчезает.
	player._upgrade_stacks[&"t_common"] = 2
	picks = UpgradePool.roll_for(rng, player, 3, 6)
	_assert(not _has_id(picks, &"t_common"), "case5 t_common excluded at cap")
	player._upgrade_stacks.clear()

	# 6. Fallback when no epics exist at level 5.
	Defs.upgrades.erase(&"t_epic")
	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(picks.size() == 3, "case6 fallback fills 3 slots without epics (got %d)" % picks.size())
	for p in picks:
		_assert(p.rarity == UpgradeDef.Rarity.COMMON or p.rarity == UpgradeDef.Rarity.RARE,
			"case6 fallback uses common/rare only")

	# 7. Class filter respected for new tiers.
	var class_epic: UpgradeDef = _make_def(&"t_class_epic", UpgradeDef.Rarity.EPIC, 0)
	var class_filter: Array[StringName] = [&"crossbow"]
	class_epic.class_filter = class_filter
	Defs.upgrades[class_epic.id] = class_epic
	Defs.upgrades[&"t_epic"] = epic_def

	picks = UpgradePool.roll_for(rng, player, 3, 5)
	_assert(not _has_id(picks, &"t_class_epic"), "case7a class_epic hidden from berserker")

	# Restore registry.
	Defs.upgrades.clear()
	for k in saved.keys():
		Defs.upgrades[k] = saved[k]

func _make_def(id: StringName, rarity: int, max_stacks: int) -> UpgradeDef:
	var d := UpgradeDef.new()
	d.id = id
	d.label = String(id)
	d.display_name = String(id)
	d.weight = 1.0
	d.rarity = rarity
	d.max_stacks = max_stacks
	d.stat = &"dmg"
	d.mode = UpgradeDef.Mode.PCT
	d.amount = 0.01
	var empty_class: Array[StringName] = []
	var empty_arch: Array[StringName] = []
	d.class_filter = empty_class
	d.archetype_filter = empty_arch
	return d

func _make_player_stub() -> _PlayerStub:
	return _PlayerStub.new()

func _has_id(picks: Array, id: StringName) -> bool:
	for p in picks:
		if p == null:
			continue
		if StringName(String(p.id)) == id:
			return true
	return false

func _assert(cond: bool, label: String) -> void:
	if cond:
		print("[rarity] OK %s" % label)
	else:
		printerr("[rarity] FAIL %s" % label)
		_failures += 1
