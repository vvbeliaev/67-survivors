extends Node

# Loads every Resource asset under res://resources/ at startup, indexed by
# its `id` StringName. Subsystems look up defs by id rather than constructing
# data inline.

var classes: Dictionary = {}     # StringName -> ClassDef
var enemies: Dictionary = {}     # StringName -> EnemyDef
var upgrades: Dictionary = {}    # StringName -> UpgradeDef
var wave_set: WaveSet = null

const CLASSES_DIR := "res://resources/classes/"
const ENEMIES_DIR := "res://resources/enemies/"
const UPGRADES_DIR := "res://resources/upgrades/"
const WAVE_SET_PATH := "res://resources/waves/arena_default.tres"

func _ready() -> void:
	classes = _load_dir(CLASSES_DIR)
	enemies = _load_dir(ENEMIES_DIR)
	upgrades = _load_dir(UPGRADES_DIR)
	if ResourceLoader.exists(WAVE_SET_PATH):
		wave_set = load(WAVE_SET_PATH)

func class_def(id: StringName) -> ClassDef:
	return classes.get(id)

func enemy_def(id: StringName) -> EnemyDef:
	return enemies.get(id)

func upgrade_def(id: StringName) -> UpgradeDef:
	return upgrades.get(id)

func _load_dir(dir: String) -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("Defs: cannot open %s" % dir)
		return out
	for fname in DirAccess.get_files_at(dir):
		if not fname.ends_with(".tres"):
			continue
		var res: Resource = load(dir + fname)
		if res == null:
			continue
		var id_val = res.get("id")
		var key: StringName
		if id_val == null or String(id_val).is_empty():
			key = StringName(fname.get_basename())
		else:
			key = StringName(String(id_val))
		out[key] = res
	return out
