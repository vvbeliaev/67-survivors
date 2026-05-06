class_name EndScreen extends Control

# Full-screen overlay shown on run end. Wins → "ПОБЕДА" (gold).
# Losses → "СМЕРТЬ" (red). Reads aggregated stats from GameState.

signal back_to_lobby
signal revive_pressed

const FONT_DISPLAY := preload("res://assets/fonts/Cinzel.ttf")
const FONT_UI := preload("res://assets/fonts/Inter.ttf")
const FONT_MONO := preload("res://assets/fonts/JetBrainsMono.ttf")

const PANEL_SIZE := Vector2(840, 480)

const COL_BACKDROP := Color(0.024, 0.014, 0.012, 0.97)
const COL_TITLE_DEATH := Color(0.95, 0.18, 0.13, 1.0)
const COL_TITLE_VICTORY := Color(0.965, 0.769, 0.376, 1.0)
const COL_LABEL := Color(0.55, 0.48, 0.36, 1.0)
const COL_VALUE := Color(0.92, 0.85, 0.72, 1.0)
const COL_RULE_DEEP := Color(0.541, 0.369, 0.122, 1.0)
const COL_RULE_DIAMOND := Color(0.95, 0.18, 0.13, 1.0)

var _title_label: Label
var _subtitle_label: Label
var _time_value: Label
var _kills_value: Label
var _damage_value: Label
var _xp_value: Label
var _xp_label_caption: Label
var _revive_btn: Button
var _lobby_btn: Button
var _rule: Control
var _rule_color: Color = COL_RULE_DEEP
var _rule_diamond_color: Color = COL_RULE_DIAMOND

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func show_for_run(won: bool, time_secs: float, kills: int, damage: int, xp_gained: int) -> void:
	_apply_state(won)
	_time_value.text = "%02d:%02d" % [int(time_secs) / 60, int(time_secs) % 60]
	_kills_value.text = _format_int(kills)
	_damage_value.text = _format_int(damage)
	_xp_value.text = "+" + _format_int(xp_gained)
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _apply_state(won: bool) -> void:
	if won:
		_title_label.text = "ПОБЕДА"
		_title_label.add_theme_color_override("font_color", COL_TITLE_VICTORY)
		_subtitle_label.text = "ПОХОД ЗАВЕРШЁН"
		_xp_label_caption.add_theme_color_override("font_color", COL_LABEL)
		_xp_value.add_theme_color_override("font_color", COL_TITLE_VICTORY)
		_rule_color = Color(0.541, 0.369, 0.122, 1.0)
		_rule_diamond_color = COL_TITLE_VICTORY
		_revive_btn.disabled = true
	else:
		_title_label.text = "СМЕРТЬ"
		_title_label.add_theme_color_override("font_color", COL_TITLE_DEATH)
		_subtitle_label.text = "ПОХОД ОКОНЧЕН"
		_xp_label_caption.add_theme_color_override("font_color", COL_LABEL)
		_xp_value.add_theme_color_override("font_color", COL_TITLE_DEATH)
		_rule_color = Color(0.541, 0.369, 0.122, 1.0)
		_rule_diamond_color = COL_TITLE_DEATH
		_revive_btn.disabled = true
	if _rule != null:
		_rule.queue_redraw()

func _format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c == 3 and i > 0:
			out = " " + out
			c = 0
	return ("-" if n < 0 else "") + out

func _build() -> void:
	# Backdrop dim layer.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = COL_BACKDROP
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Sparse ember dots (decorative, very subtle) drawn through a custom Control.
	var dots := Control.new()
	dots.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(func ():
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x67E
		var w: float = dots.size.x
		var h: float = dots.size.y
		for _i in 32:
			var x: float = rng.randf() * w
			var y: float = rng.randf() * h
			var a: float = 0.10 + rng.randf() * 0.18
			dots.draw_circle(Vector2(x, y), 1.2, Color(0.95, 0.55, 0.20, a))
	)
	dots.resized.connect(dots.queue_redraw)
	add_child(dots)

	# Centered forged panel — anchored at viewport center, fixed size.
	var panel := HUDPanel.new()
	panel.bevel = 14.0
	panel.rivets = true
	panel.accent_border = false
	panel.fill_top = Color(0.085, 0.055, 0.040, 0.96)
	panel.fill_bottom = Color(0.050, 0.030, 0.025, 0.96)
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_left = 48
	v.offset_right = -48
	v.offset_top = 36
	v.offset_bottom = -36
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(v)

	# Subtitle "ПОХОД ОКОНЧЕН"
	_subtitle_label = Label.new()
	_subtitle_label.text = "ПОХОД ОКОНЧЕН"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fv_sub := FontVariation.new()
	fv_sub.base_font = FONT_MONO
	fv_sub.spacing_glyph = 4
	_subtitle_label.add_theme_font_override("font", fv_sub)
	_subtitle_label.add_theme_font_size_override("font_size", 12)
	_subtitle_label.add_theme_color_override("font_color", COL_LABEL)
	v.add_child(_subtitle_label)

	# Title (СМЕРТЬ / ПОБЕДА). Outline kept thin so the red doesn't desaturate.
	_title_label = Label.new()
	_title_label.text = "СМЕРТЬ"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fv_title := FontVariation.new()
	fv_title.base_font = FONT_DISPLAY
	fv_title.spacing_glyph = 18
	_title_label.add_theme_font_override("font", fv_title)
	_title_label.add_theme_font_size_override("font_size", 96)
	_title_label.add_theme_color_override("font_color", COL_TITLE_DEATH)
	_title_label.add_theme_color_override("font_outline_color", Color(0.30, 0.04, 0.02, 0.85))
	_title_label.add_theme_constant_override("outline_size", 2)
	v.add_child(_title_label)

	# Divider line with center diamond.
	_rule = Control.new()
	_rule.custom_minimum_size = Vector2(0, 14)
	_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.draw.connect(_draw_rule)
	_rule.resized.connect(_rule.queue_redraw)
	v.add_child(_rule)

	# Stats row
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_theme_constant_override("separation", 56)
	stats_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(stats_row)

	var time_pair := _make_stat_column("ВРЕМЯ", "00:00", COL_VALUE)
	stats_row.add_child(time_pair[0])
	_time_value = time_pair[1]

	var kills_pair := _make_stat_column("УБИТО", "0", COL_VALUE)
	stats_row.add_child(kills_pair[0])
	_kills_value = kills_pair[1]

	var dmg_pair := _make_stat_column("УРОН", "0", COL_VALUE)
	stats_row.add_child(dmg_pair[0])
	_damage_value = dmg_pair[1]

	var xp_pair := _make_stat_column("ОПЫТ", "+0", COL_TITLE_DEATH)
	stats_row.add_child(xp_pair[0])
	_xp_value = xp_pair[1]
	# Cache the caption so we can keep its color steady when state flips.
	_xp_label_caption = xp_pair[0].get_node("Caption")

	# Spacer pushes buttons toward the bottom.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	# Buttons row.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(btn_row)

	_revive_btn = _make_action_button("ВОЗРОДИТЬСЯ")
	_revive_btn.disabled = true
	_revive_btn.pressed.connect(func (): revive_pressed.emit())
	btn_row.add_child(_revive_btn)

	_lobby_btn = _make_action_button("В ЛОББИ")
	_lobby_btn.pressed.connect(func (): back_to_lobby.emit())
	btn_row.add_child(_lobby_btn)

func _make_stat_column(caption_text: String, value_text: String, value_color: Color) -> Array:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_PASS

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fv_cap := FontVariation.new()
	fv_cap.base_font = FONT_UI
	fv_cap.spacing_glyph = 2
	caption.add_theme_font_override("font", fv_cap)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", COL_LABEL)
	col.add_child(caption)

	var value := Label.new()
	value.name = "Value"
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", FONT_DISPLAY)
	value.add_theme_font_size_override("font_size", 30)
	value.add_theme_color_override("font_color", value_color)
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	value.add_theme_constant_override("outline_size", 3)
	col.add_child(value)

	return [col, value]

func _make_action_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(280, 56)
	b.set_script(preload("res://src/ui/menu/menu_button.gd"))
	# Diamond ornament colors picked to match the gothic palette.
	b.set("diamond_color", Color(0.95, 0.32, 0.18, 1.0))
	b.set("diamond_deep", Color(0.43, 0.12, 0.08, 1.0))
	b.set("diamond_size", Vector2(20, 20))
	b.set("diamond_inset", 22.0)

	var fv_btn := FontVariation.new()
	fv_btn.base_font = FONT_DISPLAY
	fv_btn.spacing_glyph = 5
	b.add_theme_font_override("font", fv_btn)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.92, 0.85, 0.72, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.93, 0.78, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.78, 0.70, 0.55, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.42, 0.35, 0.27, 1.0))

	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.11, 0.075, 0.055, 0.95)
	sb_normal.border_color = Color(0.43, 0.18, 0.13, 1.0)
	sb_normal.set_border_width_all(1)
	sb_normal.set_corner_radius_all(0)
	sb_normal.content_margin_left = 56
	sb_normal.content_margin_right = 56
	sb_normal.content_margin_top = 12
	sb_normal.content_margin_bottom = 12
	sb_normal.shadow_color = Color(0, 0, 0, 0.5)
	sb_normal.shadow_size = 4

	var sb_hover := sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.18, 0.10, 0.07, 1.0)
	sb_hover.border_color = Color(0.78, 0.28, 0.20, 1.0)

	var sb_pressed := sb_normal.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.07, 0.05, 0.040, 1.0)
	sb_pressed.border_color = Color(0.62, 0.22, 0.16, 1.0)

	var sb_disabled := sb_normal.duplicate() as StyleBoxFlat
	sb_disabled.bg_color = Color(0.075, 0.055, 0.045, 0.7)
	sb_disabled.border_color = Color(0.27, 0.18, 0.14, 1.0)

	b.add_theme_stylebox_override("normal", sb_normal)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("focus", sb_hover)
	b.add_theme_stylebox_override("disabled", sb_disabled)
	return b

func _draw_rule() -> void:
	if _rule == null:
		return
	var w: float = _rule.size.x
	var y: float = _rule.size.y * 0.5
	# Faded line: bright in the middle, fades toward the edges.
	var steps := 60
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var dist0: float = absf(t0 - 0.5) * 2.0
		var a: float = lerp(0.85, 0.0, dist0)
		var col := Color(_rule_color.r, _rule_color.g, _rule_color.b, a)
		_rule.draw_line(Vector2(t0 * w, y), Vector2(t1 * w, y), col, 1.0, true)
	# Center diamond glow.
	var cx: float = w * 0.5
	var ds: float = 5.0
	var glow := PackedVector2Array([
		Vector2(cx, y - ds * 1.6), Vector2(cx + ds * 1.6, y),
		Vector2(cx, y + ds * 1.6), Vector2(cx - ds * 1.6, y),
	])
	_rule.draw_colored_polygon(glow, Color(_rule_diamond_color.r, _rule_diamond_color.g, _rule_diamond_color.b, 0.22))
	var pts := PackedVector2Array([
		Vector2(cx, y - ds), Vector2(cx + ds, y),
		Vector2(cx, y + ds), Vector2(cx - ds, y),
	])
	_rule.draw_colored_polygon(pts, _rule_diamond_color)
