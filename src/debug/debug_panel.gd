extends CanvasLayer

# Debug spawn panel. Lives only when GameState.debug_mode is true.
# Reads enemy ids from Defs.enemies, lets user pick one, "+" spawns it
# at the current world-mouse position via Arena.spawn_enemy().

@onready var enemy_list: ItemList = %EnemyList
@onready var spawn_btn: Button = %SpawnBtn
@onready var hint_label: Label = %HintLabel
@onready var level_up_btn: Button = %LevelUpBtn
@onready var level_label: Label = %LevelLabel

var _enemy_ids: Array[StringName] = []

func _ready() -> void:
	_populate_list()
	spawn_btn.pressed.connect(_on_spawn)
	level_up_btn.pressed.connect(_on_level_up)
	GameState.party_level_changed.connect(_refresh_level_label)
	_refresh_level_label(GameState.party_level)

func _populate_list() -> void:
	enemy_list.clear()
	_enemy_ids.clear()
	var keys: Array = Defs.enemies.keys()
	keys.sort()
	for k in keys:
		var def: EnemyDef = Defs.enemies[k]
		var label: String = String(k)
		if def != null:
			label = "%s · hp %d" % [String(k), int(def.max_hp)]
		enemy_list.add_item(label)
		_enemy_ids.append(StringName(k))
	if _enemy_ids.size() > 0:
		enemy_list.select(0)

func _on_spawn() -> void:
	var sel: PackedInt32Array = enemy_list.get_selected_items()
	if sel.is_empty():
		hint_label.text = "выбери врага из списка"
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _enemy_ids.size():
		return
	var arena: Node2D = get_tree().get_first_node_in_group("arena") as Node2D
	if arena == null or not arena.has_method("spawn_enemy"):
		return
	var t: StringName = _enemy_ids[idx]
	var pos: Vector2 = arena.get_global_mouse_position()
	arena.spawn_enemy({"type": String(t), "pos": pos})
	hint_label.text = "заспавнен %s в (%d, %d)" % [String(t), int(pos.x), int(pos.y)]

func _on_level_up() -> void:
	if not GameState.is_authority():
		hint_label.text = "+уровень: только хост"
		return
	GameState.party_level += 1
	var new_lvl: int = GameState.party_level
	EventBus.level_up.emit(new_lvl)
	GameState.party_level_changed.emit(new_lvl)
	# Sync to clients via xp_system's existing RPC.
	if GameState.is_networked():
		var arena: Node = get_tree().get_first_node_in_group("arena")
		if arena != null:
			var xp_sys: Node = arena.get_node_or_null("XpSystem")
			if xp_sys != null:
				xp_sys._rpc_sync.rpc(GameState.party_xp, new_lvl)
	hint_label.text = "уровень → %d" % new_lvl

func _refresh_level_label(new_level: int) -> void:
	if level_label != null:
		level_label.text = "уровень: %d" % new_level
