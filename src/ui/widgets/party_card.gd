class_name PartyCard extends Control

# Compact card for one party member: portrait, nick, class, HP bar.
# The HUD owns state — this widget only draws what it's told.

const PORTRAIT_SIZE := 48
const PADDING := 6

@export var nick: String = "—"
@export var class_label: String = ""
@export var class_color: Color = HUDPalette.INK_DIM
@export var hp: float = 0.0
@export var max_hp: float = 1.0
@export var alive: bool = true
@export var is_local: bool = false
@export var portrait: Texture2D = null

var nick_font: Font = null
var class_font: Font = null
var hp_font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(280, 64)

func update_state(p_hp: float, p_max_hp: float, p_alive: bool) -> void:
	hp = p_hp
	max_hp = p_max_hp
	alive = p_alive
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)

	# Backdrop — local player gets a faint accent inner glow.
	var bg_top := HUDPalette.PANEL
	var bg_bot := HUDPalette.PANEL_SOFT
	if not alive:
		bg_top = bg_top.lerp(Color(0.05, 0.02, 0.02, 1.0), 0.5)
		bg_bot = bg_bot.lerp(Color(0.05, 0.02, 0.02, 1.0), 0.5)

	var n := 6
	var h := r.size.y / float(n)
	for i in n:
		var t := float(i) / float(n - 1)
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h + 1)), bg_top.lerp(bg_bot, t), true)

	# Inner subtle highlight on top edge.
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), HUDPalette.HIGHLIGHT, true)
	# Inner shadow.
	draw_rect(r.grow(-1), HUDPalette.SHADOW_LIGHT, false, 1.0)
	# Border — accent if local player.
	var bc := HUDPalette.ACCENT_DEEP if is_local else HUDPalette.STROKE_STRONG
	draw_rect(r, bc, false, 1.0)

	# Portrait box.
	var portrait_rect := Rect2(r.position + Vector2(PADDING, (r.size.y - PORTRAIT_SIZE) * 0.5), Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE))
	draw_rect(portrait_rect, Color(0.039, 0.024, 0.016, 1.0), true)
	draw_rect(portrait_rect, HUDPalette.STROKE_STRONG, false, 1.0)
	if portrait != null:
		draw_texture_rect(portrait, portrait_rect.grow(-2), false, Color(1, 1, 1, 1) if alive else Color(0.4, 0.4, 0.4, 0.7))
	if not alive:
		# Red overlay + cross.
		draw_rect(portrait_rect.grow(-1), Color(0.314, 0.039, 0.039, 0.6), true)
		var cross_col := Color(1.0, 0.541, 0.471, 1.0)
		var pad := 12
		draw_line(portrait_rect.position + Vector2(pad, pad), portrait_rect.position + portrait_rect.size - Vector2(pad, pad), cross_col, 2.0)
		draw_line(portrait_rect.position + Vector2(portrait_rect.size.x - pad, pad), portrait_rect.position + Vector2(pad, portrait_rect.size.y - pad), cross_col, 2.0)

	# Right side — text + bar.
	var text_x := portrait_rect.end.x + 10
	var text_w := r.size.x - (text_x - r.position.x) - PADDING

	# Nick.
	if nick_font != null:
		var nick_color := HUDPalette.ACCENT if is_local else HUDPalette.INK
		if not alive:
			nick_color = HUDPalette.INK_DIM
		var fs := 13
		var s := nick.to_upper()
		var ts := nick_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2(text_x, r.position.y + 6 + ts.y - 2)
		draw_string(nick_font, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
		draw_string(nick_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, nick_color)

	# Class label (right-aligned within text region).
	if class_font != null and class_label != "":
		var cfs := 10
		var cts := class_font.get_string_size(class_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs)
		var col := class_color if alive else HUDPalette.INK_MUTE
		var cpos := Vector2(text_x + text_w - cts.x, r.position.y + 6 + cts.y - 2)
		draw_string(class_font, cpos + Vector2(0, 1), class_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(0, 0, 0, 0.7))
		draw_string(class_font, cpos, class_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, col)

	# HP bar (drawn manually to avoid extra Control instances).
	var bar_y := r.position.y + r.size.y - 14
	var bar_rect := Rect2(Vector2(text_x, bar_y), Vector2(text_w, 9))
	_draw_hp_bar(bar_rect)

func _draw_hp_bar(r: Rect2) -> void:
	# Background.
	draw_rect(r, Color(0.039, 0.024, 0.016, 1.0), true)
	# Fill.
	if alive and max_hp > 0.0:
		var pct := clampf(hp / max_hp, 0.0, 1.0)
		var fr := Rect2(r.position, Vector2(r.size.x * pct, r.size.y))
		var n := 4
		var h := fr.size.y / float(n)
		for i in n:
			var t := float(i) / float(n - 1)
			var col := HUDPalette.HEALTH_BRIGHT.lerp(HUDPalette.HEALTH_DARK, t)
			draw_rect(Rect2(fr.position + Vector2(0, i * h), Vector2(fr.size.x, h + 1)), col, true)
		# Top sheen.
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1)), Color(1, 0.6, 0.5, 0.4), true)
	# Border.
	draw_rect(r, HUDPalette.STROKE_STRONG, false, 1.0)
	# Label.
	if hp_font != null:
		var s: String = ("%d/%d" % [int(hp), int(max_hp)]) if alive else "мёртв"
		var fs := 9
		var ts := hp_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := r.position + Vector2((r.size.x - ts.x) * 0.5, ts.y + (r.size.y - ts.y) * 0.5 - 1)
		draw_string(hp_font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
		draw_string(hp_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUDPalette.INK)
