class_name UpgradeDef extends Resource

# Stackable upgrade. Applied as a uniquely-named modifier in the player's
# StatBlock so multiple stacks coexist deterministically. `class_filter` and
# `archetype_filter` constrain the upgrade pool per player; empty = universal.

enum Mode { FLAT, PCT }

@export var id: StringName = &""
@export var label: String = ""
@export var weight: float = 1.0
@export var class_filter: Array[StringName] = []
@export var archetype_filter: Array[StringName] = []

@export_group("Effect")
@export var stat: StringName = &""
@export var mode: Mode = Mode.FLAT
@export var amount: float = 0.0

# Optional one-shot effects layered on top of the modifier.
@export_group("Side effects")
@export var heal_on_pick: float = 0.0   # heal applied immediately
@export var refill_mana: bool = false
