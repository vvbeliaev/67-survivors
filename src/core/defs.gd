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
	_setup_font_fallbacks()
	classes = _load_dir(CLASSES_DIR)
	enemies = _load_dir(ENEMIES_DIR)
	upgrades = _load_dir(UPGRADES_DIR)
	if ResourceLoader.exists(WAVE_SET_PATH):
		wave_set = load(WAVE_SET_PATH)

# Cinzel.ttf has no Cyrillic glyphs. On desktop Godot's allow_system_fallback
# papers over this; in Web export there are no system fonts, so Russian text
# renders as tofu. Wire Inter (which has full Cyrillic) as an explicit fallback.
func _setup_font_fallbacks() -> void:
	var cinzel := load("res://assets/fonts/Cinzel.ttf") as FontFile
	var inter := load("res://assets/fonts/Inter.ttf") as FontFile
	if cinzel != null and inter != null:
		cinzel.fallbacks = [inter]

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
		# Web export converts .tres to .res by default — accept both, plus
		# .remap which Godot creates when stripping source extensions on export.
		var ext := fname.get_extension()
		if ext != "tres" and ext != "res" and ext != "remap":
			continue
		var path: String = dir + fname
		if ext == "remap":
			path = path.get_basename()
		var res: Resource = load(path)
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
