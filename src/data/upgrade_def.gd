class_name UpgradeDef extends Resource

# Stackable upgrade. Applied as a uniquely-named modifier in the player's
# StatBlock so multiple stacks coexist deterministically. `class_filter` and
# `archetype_filter` constrain the upgrade pool per player; empty = universal.
#
# Display fields drive the level-up screen presentation; effect fields drive
# the actual stat change.

enum Mode { FLAT, PCT }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
# Short technical summary. Used in combat log lines like "Vrok взял +10% damage".
@export var label: String = ""
@export var weight: float = 1.0
@export var class_filter: Array[StringName] = []
@export var archetype_filter: Array[StringName] = []
@export var icon: Texture2D = null

@export_group("Display")
# Russian display title shown on the level-up card, e.g. "Жажда крови".
@export var display_name: String = ""
# Multi-line description rendered on the card. Each line may use a single
# tab to split a "Name\tValue" pair which the card right-aligns the value.
# Lines without a tab render as plain wrapped text — useful for upgrades that
# describe new behavior rather than a numeric stat change.
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
# 0 = бесконечно для COMMON, либо тиро-зависимый дефолт (RARE=3, EPIC=2, LEGENDARY=1)
# вычисляется через UpgradePool.effective_max_stacks(). Положительное значение
# перекрывает дефолт (например, 5 для dodge, 8 для cooldown).
@export var max_stacks: int = 0
# Visual category badge: &"attack" / &"defense" / &"utility" / &"mana".
@export var category: StringName = &"attack"
@export_multiline var flavor: String = ""

@export_group("Effect")
@export var stat: StringName = &""
@export var mode: Mode = Mode.FLAT
@export var amount: float = 0.0

# Optional secondary stats applied alongside the primary one. Parallel arrays;
# all three must be the same length. Empty arrays = no secondary effects.
@export var extra_stats: Array[StringName] = []
@export var extra_modes: Array[int] = []   # 0=FLAT, 1=PCT
@export var extra_amounts: Array[float] = []

# Optional one-shot effects layered on top of the modifier.
@export_group("Side effects")
@export var heal_on_pick: float = 0.0   # heal applied immediately
@export var refill_mana: bool = false
