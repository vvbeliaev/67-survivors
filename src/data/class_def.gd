class_name ClassDef extends Resource

# Designer-edited class blueprint. Behavior lives in the script referenced by
# `node_script`, which Player instantiates as a child on spawn.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color_hint: Color = Color.WHITE
@export var radius: float = 16.0

@export_group("Base stats")
@export var base_speed: float = 240.0
@export var base_max_hp: float = 200.0
@export var base_max_mp: float = 0.0
@export var base_mana_regen: float = 0.0

@export_group("Behavior")
@export var node_script: Script
