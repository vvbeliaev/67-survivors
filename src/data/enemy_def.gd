class_name EnemyDef extends Resource

# Pure stat block + AI script reference for an enemy archetype.

@export var id: StringName = &""
@export var max_hp: float = 25.0
@export var move_speed: float = 180.0
@export var contact_damage: float = 8.0
@export var contact_cd: float = 0.6
@export var xp_value: int = 1
@export var color_hint: Color = Color.RED
@export var radius: float = 12.0

@export_group("Ranged")
@export var ranged: bool = false
@export var ranged_dist: float = 250.0
@export var projectile_speed: float = 240.0
@export var projectile_damage: float = 6.0
@export var ranged_cd: float = 1.5

@export_group("Boss")
@export var boss: bool = false
@export var boss_aoe_radius: float = 0.0
@export var boss_aoe_damage: float = 0.0
@export var boss_aoe_cd: float = 0.0
@export var boss_aoe_windup: float = 0.0

@export_group("Behavior")
@export var ai_script: Script
