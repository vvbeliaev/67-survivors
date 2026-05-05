class_name HUDPalette extends RefCounted

# Single source of truth for HUD colors. Mirrors the gothic palette from
# the design mock (Игра/styles.css). Pixel-equivalent Color8 values.

const BG_DEEP := Color(0.047, 0.039, 0.031, 1.0)
const BG := Color(0.086, 0.067, 0.051, 1.0)
const PANEL := Color(0.133, 0.102, 0.075, 1.0)
const PANEL_SOFT := Color(0.165, 0.125, 0.094, 1.0)
const STROKE := Color(0.227, 0.180, 0.133, 1.0)
const STROKE_STRONG := Color(0.345, 0.263, 0.180, 1.0)
const METAL := Color(0.420, 0.353, 0.271, 1.0)
const METAL_LIGHT := Color(0.659, 0.565, 0.439, 1.0)

const INK := Color(0.922, 0.851, 0.722, 1.0)
const INK_DIM := Color(0.612, 0.533, 0.412, 1.0)
const INK_MUTE := Color(0.420, 0.353, 0.271, 1.0)

const ACCENT := Color(0.831, 0.627, 0.290, 1.0)
const ACCENT_GLOW := Color(0.965, 0.769, 0.376, 1.0)
const ACCENT_DEEP := Color(0.541, 0.369, 0.122, 1.0)

const DANGER := Color(0.839, 0.290, 0.227, 1.0)
const DANGER_DEEP := Color(0.431, 0.118, 0.086, 1.0)

const HEALTH_DARK := Color(0.416, 0.094, 0.063, 1.0)
const HEALTH_MID := Color(0.690, 0.188, 0.125, 1.0)
const HEALTH_BRIGHT := Color(0.910, 0.353, 0.227, 1.0)

const MANA_DARK := Color(0.063, 0.157, 0.408, 1.0)
const MANA_MID := Color(0.157, 0.345, 0.847, 1.0)
const MANA_BRIGHT := Color(0.290, 0.541, 1.0, 1.0)

const XP_DARK := Color(0.353, 0.220, 0.031, 1.0)
const XP_MID := Color(0.690, 0.471, 0.125, 1.0)
const XP_BRIGHT := Color(0.941, 0.753, 0.376, 1.0)

const HEAL_DARK := Color(0.102, 0.282, 0.094, 1.0)
const HEAL_MID := Color(0.251, 0.533, 0.220, 1.0)
const HEAL_BRIGHT := Color(0.502, 0.878, 0.471, 1.0)

const LOG_KILL := Color(0.910, 0.769, 0.471, 1.0)
const LOG_LOOT := Color(0.502, 0.753, 0.376, 1.0)
const LOG_DMG := Color(0.910, 0.439, 0.376, 1.0)
const LOG_WARN := Color(0.722, 0.471, 0.847, 1.0)

# Semi-transparent overlays.
const SHADOW := Color(0, 0, 0, 0.7)
const SHADOW_LIGHT := Color(0, 0, 0, 0.4)
const HIGHLIGHT := Color(1.0, 0.824, 0.588, 0.06)

# Class color hints (fallback when ClassDef not available).
const CLASS_COLOR := {
	&"berserker": Color(0.95, 0.30, 0.30),
	&"mage":      Color(0.40, 0.60, 1.00),
	&"bard":      Color(0.40, 0.95, 0.50),
	&"crossbow":  Color(0.95, 0.85, 0.30),
}
