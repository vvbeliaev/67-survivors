class_name ClassNode extends Node

# A class is a Node that lives on the player and provides:
#   1. base stat seeding (via ClassDef)
#   2. an auto-attack skill (optional)
#   3. three active skills bound to LMB / RMB / Space
#   4. optional per-tick hooks (e.g. crossbow charge slow)
#
# The player owns the lifecycle: on spawn it asks the class to build skills
# and seed stats; per physics tick it forwards input intents to the right
# skill.

var owner_player: Node = null
var auto_skill: Skill = null
var primary_skill: Skill = null
var secondary_skill: Skill = null
var utility_skill: Skill = null

# Sub-classes override these.
func build_skills() -> void:
	pass

func seed_stats(_def: ClassDef, _stats: StatBlock) -> void:
	pass

# Called every host physics tick. Class can apply transient stat modifiers
# such as the crossbow charge-slow.
func on_pre_move(_delta: float) -> void:
	pass

# HUD reads the icon for slot (0=auto, 1=LMB, 2=RMB, 3=Space). Default just
# forwards the bound skill's icon; classes with empty slots can override to
# return a placeholder (e.g. crossbow has no auto skill but still wants an
# icon in that slot).
func icon_for_slot(idx: int) -> Texture2D:
	var slots: Array = [auto_skill, primary_skill, secondary_skill, utility_skill]
	if idx < 0 or idx >= slots.size():
		return null
	var s: Skill = slots[idx]
	return s.icon if s != null else null

# ---- Helpers used by sub-classes ----------------------------------------

func _attach(skill: Skill) -> void:
	add_child(skill)
	skill.attach(owner_player)

func setup(p: Node, def: ClassDef, stats: StatBlock) -> void:
	owner_player = p
	seed_stats(def, stats)
	build_skills()
