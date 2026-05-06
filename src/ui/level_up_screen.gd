extends Control

# Full-screen level-up picker. Shown for every alive peer when the party
# levels up; the tree is paused until everyone has chosen (or skipped).
# All process logic runs with PROCESS_MODE_ALWAYS so the screen stays
# interactive while `get_tree().paused == true`.
#
# This view is presentation-only. It receives an array of UpgradeDef
# resources to draw and submits the chosen id back through the
# UpgradeOffer node — the host orchestrates the actual rolling, picking,
# and pause/resume.

const FONT_DISPLAY := preload("res://assets/fonts/Cinzel.ttf")
const FONT_UI := preload("res://assets/fonts/Inter.ttf")
const FONT_MONO := preload("res://assets/fonts/JetBrainsMono.ttf")

const PORTRAITS := {
	&"berserker": preload("res://assets/images/berserker_top.png"),
	&"mage":      preload("res://assets/images/wizard_top.png"),
	&"bard":      preload("res://assets/images/bard_top.png"),
	&"crossbow":  preload("res://assets/images/crossbowman_top.png"),
}

const RARITY_LABELS := ["Обычная", "Редкая", "Эпическая"]
const RARITY_COLORS := [
	Color(0.55, 0.55, 0.55),
	Color(0.30, 0.62, 0.95),
	Color(0.78, 0.45, 0.95),
]

const CATEGORY_LABELS := {
	&"attack":  "АТАКА",
	&"defense": "ЗАЩИТА",
	&"utility": "УТИЛИТА",
	&"mana":    "МАНА",
}

const CATEGORY_COLORS := {
	&"attack":  Color(0.92, 0.42, 0.32),
	&"defense": Color(0.55, 0.78, 0.97),
	&"utility": Color(0.93, 0.83, 0.47),
	&"mana":    Color(0.60, 0.50, 0.97),
}

const CARD_SIZE := Vector2(178, 300)
const CARD_BG := Color(0.055, 0.045, 0.065, 1.0)        # near-black with a touch of plum
const CARD_BG_INNER := Color(0.085, 0.07, 0.10, 1.0)    # icon-plate background
const RARITY_BORDER_WIDTH := [1, 2, 2]

var _options: Array = []                  # Array[UpgradeDef]
var _picked_locally: bool = false
var _last_party_summary: Array = []

# Built children, populated in _build().
var _level_label: Label = null
var _cards_box: HBoxContainer = null
var _cards_holder: Control = null
var _waiting_panel: Control = null
var _waiting_label: Label = null
var _party_status_label: Label = null
var _party_progress_label: Label = null
var _party_rows_box: VBoxContainer = null

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Cover the parent rect (HUD's Root, which is viewport-sized).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_to_group("level_up_screen")
	_build()

func _build() -> void:
	# Dim backdrop — fills the whole screen behind every other layer.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.025, 0.92)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Root vertical column drives the page layout: header at the top,
	# cards/waiting expand-filled in the middle, hints at the bottom. This
	# guarantees the header and hints never overlap the cards.
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# Top spacer so the header sits below the status bar.
	column.add_child(_make_vspacer(20))

	# Header.
	var header := VBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(header)

	_level_label = Label.new()
	_level_label.text = "УРОВЕНЬ 1 → 2"
	_level_label.add_theme_font_override("font", FONT_UI)
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_color_override("font_color", HUDPalette.INK_DIM)
	_level_label.add_theme_constant_override("outline_size", 3)
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_level_label)

	var title := Label.new()
	title.text = "НОВЫЙ УРОВЕНЬ"
	title.add_theme_font_override("font", FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.93, 0.32, 0.22))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var sub := Label.new()
	sub.text = "Выберите силу"
	sub.add_theme_font_override("font", FONT_DISPLAY)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sub)

	# Center area — expand-filled vertically so the cards (or the "waiting"
	# panel) sit centered between the header and the hint strip.
	var center_row := Control.new()
	center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(center_row)

	_cards_holder = CenterContainer.new()
	_cards_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_row.add_child(_cards_holder)

	_cards_box = HBoxContainer.new()
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", 14)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_holder.add_child(_cards_box)

	_waiting_panel = _build_waiting_panel()
	center_row.add_child(_waiting_panel)

	# Hint strip (1·2·3 / R / ESC) and a bottom spacer.
	column.add_child(_build_hint_strip())
	column.add_child(_make_vspacer(20))

	# Party status panel — fixed top-right, on its own layer above the column.
	add_child(_build_party_panel())

func _make_vspacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _build_party_panel() -> Control:
	var panel := PanelContainer.new()
	# Top-right corner with a 24px margin from edges.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -296
	panel.offset_top = 24
	panel.offset_right = -24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = Color(0.30, 0.20, 0.13)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(status_row)

	_party_status_label = Label.new()
	_party_status_label.text = "ЖДЁМ ВСЕХ"
	_party_status_label.add_theme_font_override("font", FONT_UI)
	_party_status_label.add_theme_font_size_override("font_size", 12)
	_party_status_label.add_theme_color_override("font_color", HUDPalette.ACCENT)
	_party_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_party_status_label)

	_party_progress_label = Label.new()
	_party_progress_label.text = "0/0"
	_party_progress_label.add_theme_font_override("font", FONT_MONO)
	_party_progress_label.add_theme_font_size_override("font_size", 12)
	_party_progress_label.add_theme_color_override("font_color", HUDPalette.INK_DIM)
	status_row.add_child(_party_progress_label)

	# Slot indicator strip — one bar per peer, colored by their state.
	# Filled in by _refresh_party_panel.
	_party_rows_box = VBoxContainer.new()
	_party_rows_box.add_theme_constant_override("separation", 6)
	_party_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_party_rows_box)

	return panel

func _build_waiting_panel() -> Control:
	# Full-rect container with a CenterContainer inside, so the inner column
	# is naturally centered without manual position math.
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(v)

	var l1 := Label.new()
	l1.text = "ВЫБОР СДЕЛАН"
	l1.add_theme_font_override("font", FONT_DISPLAY)
	l1.add_theme_font_size_override("font_size", 28)
	l1.add_theme_color_override("font_color", HUDPalette.HEAL_BRIGHT)
	l1.add_theme_constant_override("outline_size", 5)
	l1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)

	_waiting_label = Label.new()
	_waiting_label.text = "Ждём остальных…"
	_waiting_label.add_theme_font_override("font", FONT_UI)
	_waiting_label.add_theme_font_size_override("font_size", 14)
	_waiting_label.add_theme_color_override("font_color", HUDPalette.INK_DIM)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_waiting_label)

	return holder

func _build_hint_strip() -> Control:
	# Lives inside the root VBox column — sized by content via VBox layout.
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 22)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_hint(box, "1 · 2 · 3", "ВЫБОР", Color(0.93, 0.32, 0.22))
	_make_hint(box, "ESC", "ПРОПУСТИТЬ", HUDPalette.INK_DIM)
	return box

func _make_hint(parent: BoxContainer, key: String, action: String, color: Color) -> void:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# PanelContainer auto-sizes around its label, so the key chip is exactly
	# as wide as its text plus stylebox padding.
	var key_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = HUDPalette.PANEL_SOFT
	sb.border_color = color * Color(1, 1, 1, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	key_panel.add_theme_stylebox_override("panel", sb)
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_override("font", FONT_MONO)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", color)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.add_child(key_label)
	holder.add_child(key_panel)

	var action_label := Label.new()
	action_label.text = action
	action_label.add_theme_font_override("font", FONT_UI)
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(action_label)

	parent.add_child(holder)

# =========================================================================
# Public API — driven by UpgradeOffer.
# =========================================================================

func open(new_level: int, options: Array, party_summary: Array) -> void:
	_options = options
	_picked_locally = false
	_level_label.text = "УРОВЕНЬ %d → %d" % [max(new_level - 1, 1), new_level]
	_rebuild_cards()
	_cards_holder.visible = true
	_waiting_panel.visible = false
	_last_party_summary = party_summary
	_refresh_party_panel(party_summary)
	visible = true

func close() -> void:
	visible = false
	_options.clear()
	_picked_locally = false
	for c in _cards_box.get_children():
		c.queue_free()

func update_party_status(party_summary: Array) -> void:
	_last_party_summary = party_summary
	_refresh_party_panel(party_summary)

# =========================================================================
# Card construction.
# =========================================================================

func _rebuild_cards() -> void:
	for c in _cards_box.get_children():
		c.queue_free()
	var i := 1
	for opt in _options:
		_cards_box.add_child(_make_card(i, opt))
		i += 1

func _make_card(index: int, def: UpgradeDef) -> Control:
	var rarity: int = clamp(int(def.rarity), 0, 2)
	var category_id: StringName = StringName(String(def.category)) if def.category != &"" else &"attack"
	var rarity_color: Color = RARITY_COLORS[rarity]
	var category_color: Color = CATEGORY_COLORS.get(category_id, HUDPalette.ACCENT)

	# Root: a Button so the whole rectangle is clickable. Styles come from the
	# Panel laid behind the content so the Button stays purely interactive.
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.toggle_mode = false
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	# Card backdrop — near-black with a rarity-colored border.
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = CARD_BG
	sb_bg.border_color = rarity_color
	var bw: int = RARITY_BORDER_WIDTH[rarity]
	sb_bg.set_border_width_all(bw)
	sb_bg.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", sb_bg)
	card.add_child(bg)

	# Hover highlight — invisible by default, rarity-tinted on hover.
	var hover_overlay := ColorRect.new()
	hover_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hover_overlay.color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.0)
	hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hover_overlay)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)

	# Top row: category badge + index.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)

	top.add_child(_make_category_badge(category_id, category_color))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	var idx_lbl := Label.new()
	idx_lbl.text = str(index)
	idx_lbl.add_theme_font_override("font", FONT_MONO)
	idx_lbl.add_theme_font_size_override("font_size", 10)
	idx_lbl.add_theme_color_override("font_color", HUDPalette.INK_DIM)
	idx_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(idx_lbl)

	# Icon block — dark plate with a category-colored radial-ish glow tint
	# behind the icon. Two layers: deep bg, then a soft tinted overlay.
	var icon_plate := Panel.new()
	icon_plate.custom_minimum_size = Vector2(0, 110)
	var sb_plate := StyleBoxFlat.new()
	sb_plate.bg_color = CARD_BG_INNER
	sb_plate.border_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.35)
	sb_plate.set_border_width_all(1)
	sb_plate.set_corner_radius_all(0)
	icon_plate.add_theme_stylebox_override("panel", sb_plate)
	icon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_plate)

	# Soft glow behind the icon — flat color rect with very low alpha.
	var glow := ColorRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.color = Color(category_color.r, category_color.g, category_color.b, 0.10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_plate.add_child(glow)

	if def.icon != null:
		var tr := TextureRect.new()
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.texture = def.icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate = category_color
		tr.offset_left = 14
		tr.offset_top = 12
		tr.offset_right = -14
		tr.offset_bottom = -12
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_plate.add_child(tr)

	# Display name + rarity caption.
	var name_lbl := Label.new()
	var dn: String = String(def.display_name) if String(def.display_name) != "" else String(def.label)
	name_lbl.text = dn.to_upper()
	name_lbl.add_theme_font_override("font", FONT_DISPLAY)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", HUDPalette.INK)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	var rarity_lbl := Label.new()
	rarity_lbl.text = "· %s · I" % RARITY_LABELS[rarity]
	rarity_lbl.add_theme_font_override("font", FONT_UI)
	rarity_lbl.add_theme_font_size_override("font_size", 9)
	rarity_lbl.add_theme_color_override("font_color", rarity_color)
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rarity_lbl)

	# Effect lines from `description`. Tab splits a name/value pair; lines
	# without a tab render as plain wrapped text (for prose descriptions).
	var desc: String = String(def.description) if String(def.description) != "" else String(def.label)
	for line in desc.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			continue
		v.add_child(_make_effect_line(trimmed))

	# Spacer pushes the flavor text to the bottom of the card.
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)

	if String(def.flavor) != "":
		var fl := Label.new()
		fl.text = "«%s»" % String(def.flavor)
		fl.add_theme_font_override("font", FONT_UI)
		fl.add_theme_font_size_override("font_size", 9)
		fl.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fl)

	card.pressed.connect(func ():
		AudioBus.play_ui(&"ui_click")
		_submit(StringName(String(def.id)))
	)
	card.mouse_entered.connect(func ():
		AudioBus.play_ui(&"ui_hover", -10.5)
		hover_overlay.color = rarity_color * Color(1, 1, 1, 0.10)
	)
	card.mouse_exited.connect(func ():
		hover_overlay.color = rarity_color * Color(1, 1, 1, 0.0)
	)

	return card

func _make_category_badge(category_id: StringName, color: Color) -> Control:
	var label_text: String = String(CATEGORY_LABELS.get(category_id, String(category_id).to_upper()))
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.15)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", FONT_UI)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel

func _make_effect_line(line: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if line.contains("\t"):
		var parts: PackedStringArray = line.split("\t", false, 1)
		var k := Label.new()
		k.text = parts[0]
		k.add_theme_font_override("font", FONT_UI)
		k.add_theme_font_size_override("font_size", 10)
		k.add_theme_color_override("font_color", HUDPalette.INK)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(k)
		var val := Label.new()
		val.text = parts[1] if parts.size() > 1 else ""
		val.add_theme_font_override("font", FONT_MONO)
		val.add_theme_font_size_override("font_size", 10)
		val.add_theme_color_override("font_color", HUDPalette.HEAL_BRIGHT)
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(val)
	else:
		var l := Label.new()
		l.text = line
		l.add_theme_font_override("font", FONT_UI)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", HUDPalette.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	return row

# =========================================================================
# Party panel.
# =========================================================================

func _refresh_party_panel(party_summary: Array) -> void:
	for c in _party_rows_box.get_children():
		c.queue_free()

	var local_id := _local_peer_id()
	var alive_total := 0
	var picked := 0
	var waiting := 0
	for entry in party_summary:
		if entry.get("alive", false):
			alive_total += 1
			match String(entry.get("status", "")):
				"picked": picked += 1
				"waiting": waiting += 1

	if waiting == 0 and alive_total > 0:
		_party_status_label.text = "ВСЕ ВЫБРАЛИ"
		_party_status_label.add_theme_color_override("font_color", HUDPalette.HEAL_BRIGHT)
	else:
		_party_status_label.text = "ЖДЁМ %d" % waiting
		_party_status_label.add_theme_color_override("font_color", HUDPalette.ACCENT)

	_party_progress_label.text = "%d/%d" % [picked, alive_total]

	# Sort: local first, then by peer_id.
	var sorted: Array = party_summary.duplicate()
	sorted.sort_custom(func (a, b):
		var ai: int = int(a.get("peer_id", 0))
		var bi: int = int(b.get("peer_id", 0))
		if ai == local_id and bi != local_id:
			return true
		if bi == local_id and ai != local_id:
			return false
		return ai < bi
	)
	for entry in sorted:
		_party_rows_box.add_child(_make_party_row(entry, local_id))

func _make_party_row(entry: Dictionary, local_id: int) -> Control:
	var pid: int = int(entry.get("peer_id", 0))
	var nick: String = String(entry.get("nick", "?")).to_upper()
	var klass: StringName = StringName(String(entry.get("klass", "berserker")))
	var alive: bool = bool(entry.get("alive", true))
	var status: String = String(entry.get("status", ""))
	var label_text: String = String(entry.get("label", ""))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait_holder := Panel.new()
	portrait_holder.custom_minimum_size = Vector2(32, 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = HUDPalette.BG_DEEP
	sb.border_color = HUDPalette.CLASS_COLOR.get(klass, HUDPalette.STROKE_STRONG)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	portrait_holder.add_theme_stylebox_override("panel", sb)
	portrait_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_tex: Texture2D = PORTRAITS.get(klass)
	if p_tex != null:
		var portrait := TextureRect.new()
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.texture = p_tex
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_holder.add_child(portrait)
	row.add_child(portrait_holder)

	var name_lbl := Label.new()
	name_lbl.text = nick
	name_lbl.add_theme_font_override("font", FONT_DISPLAY)
	name_lbl.add_theme_font_size_override("font_size", 14)
	var name_color: Color = HUDPalette.INK if alive else HUDPalette.INK_MUTE
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.add_theme_font_override("font", FONT_UI)
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not alive:
		status_lbl.text = "ПАЛ"
		status_lbl.add_theme_color_override("font_color", HUDPalette.DANGER)
	elif pid == local_id:
		if status == "picked":
			status_lbl.text = label_text
			status_lbl.add_theme_color_override("font_color", HUDPalette.HEAL_BRIGHT)
		else:
			status_lbl.text = "ЭТО ВЫ"
			status_lbl.add_theme_color_override("font_color", HUDPalette.ACCENT)
	elif status == "picked":
		status_lbl.text = label_text
		status_lbl.add_theme_color_override("font_color", HUDPalette.HEAL_BRIGHT)
	else:
		status_lbl.text = "ВЫБИРАЕТ…"
		status_lbl.add_theme_color_override("font_color", HUDPalette.INK_DIM)
	row.add_child(status_lbl)

	return row

# =========================================================================
# Input + submission.
# =========================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if _picked_locally:
		# Allow ESC to do nothing; cards already submitted.
		return
	match key_event.keycode:
		KEY_1:
			_pick_index(0)
			get_viewport().set_input_as_handled()
		KEY_2:
			_pick_index(1)
			get_viewport().set_input_as_handled()
		KEY_3:
			_pick_index(2)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_submit(&"")  # skip
			get_viewport().set_input_as_handled()

func _pick_index(i: int) -> void:
	if i < 0 or i >= _options.size():
		return
	var def: UpgradeDef = _options[i]
	if def == null:
		return
	AudioBus.play_ui(&"ui_click")
	_submit(StringName(String(def.id)))

func _submit(id: StringName) -> void:
	if _picked_locally:
		return
	_picked_locally = true
	# Switch the center to the "waiting for others" panel; party panel stays.
	_cards_holder.visible = false
	_waiting_panel.visible = true
	var director := get_tree().get_first_node_in_group("upgrade_offer")
	if director != null:
		director.submit_pick(String(id))

func _local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()
