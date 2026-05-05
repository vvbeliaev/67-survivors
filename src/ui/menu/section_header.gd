@tool
class_name MenuSectionHeader
extends VBoxContainer

## Section header: uppercase amber title + fading horizontal rule below.

@export var title: String = "СОЕДИНЕНИЕ": set = set_title
@export var accent: Color = Color(0.83, 0.63, 0.29, 1.0)
@export var accent_deep: Color = Color(0.54, 0.37, 0.12, 1.0)
@export var label_size: int = 18
@export var font: FontFile

var _label: Label
var _rule: Control

func set_title(v: String) -> void:
	title = v
	if _label:
		_label.text = v.to_upper()

func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	_label = Label.new()
	_label.text = title.to_upper()
	if font:
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = 4
		_label.add_theme_font_override(&"font", fv)
	_label.add_theme_color_override(&"font_color", accent)
	_label.add_theme_font_size_override(&"font_size", label_size)
	add_child(_label)
	_rule = Control.new()
	_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule.custom_minimum_size = Vector2(40, 2)
	_rule.draw.connect(_on_rule_draw)
	_rule.resized.connect(_rule.queue_redraw)
	add_child(_rule)

func _on_rule_draw() -> void:
	var w: float = _rule.size.x
	var y: float = _rule.size.y * 0.5
	var steps := 40
	for i in range(steps):
		var t0: float = float(i) / steps
		var t1: float = float(i + 1) / steps
		var a0: float = lerp(0.95, 0.0, t0)
		var c := Color(accent_deep.r, accent_deep.g, accent_deep.b, a0)
		_rule.draw_line(Vector2(t0 * w, y), Vector2(t1 * w, y), c, 1.0, true)
