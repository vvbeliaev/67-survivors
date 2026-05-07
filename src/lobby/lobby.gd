extends Control

const ICON_DIR := "res://assets/images/icons/"

const CLASS_INFO := {
	"berserker": {
		"name": "БЕРСЕРК",
		"subtitle": "Безумец крови",
		"quote": "«Каждая рана — глоток силы.»",
		"sprite": "res://assets/images/berserker.png",
		"role": "ТАНК",
		"role_note": "Контроль агро",
		"difficulty": 2,
		"skills": [
			{"key": "Авто", "icon": ICON_DIR + "axe-swing.svg",   "name": "Кружащий клинок", "desc": "AoE вокруг себя", "hot": false},
			{"key": "ЛКМ",  "icon": ICON_DIR + "sprint.svg",      "name": "Кровавый рывок",  "desc": "бьёт сильнее при низком HP", "hot": true},
			{"key": "ПКМ",  "icon": ICON_DIR + "lion.svg",        "name": "Боевой рёв",      "desc": "стянуть агро в радиусе", "hot": false},
			{"key": "Space","icon": ICON_DIR + "winged-leg.svg",  "name": "Прыжок",          "desc": "i-frames, рывок без урона", "hot": false},
		],
	},
	"mage": {
		"name": "ВОЛШЕБНИК",
		"subtitle": "Архимаг разрушения",
		"quote": "«Достаточно одной искры — и ничего не останется.»",
		"sprite": "res://assets/images/wizard.png",
		"role": "AOE",
		"role_note": "Контроль волн",
		"difficulty": 3,
		"skills": [
			{"key": "Авто", "icon": ICON_DIR + "magic-palm.svg",        "name": "Магический снаряд", "desc": "автоприцел по ближайшему", "hot": false},
			{"key": "ЛКМ",  "icon": ICON_DIR + "crowned-explosion.svg", "name": "Файрбол",           "desc": "AoE по курсору · 30 маны", "hot": false},
			{"key": "ПКМ",  "icon": ICON_DIR + "thunder-struck.svg",    "name": "Цепная молния",     "desc": "по 3 целям · 50 маны", "hot": true},
			{"key": "Space","icon": ICON_DIR + "teleport.svg",          "name": "Блинк",             "desc": "телепорт по курсору", "hot": false},
		],
	},
	"bard": {
		"name": "БАРД",
		"subtitle": "Голос пати",
		"quote": "«Без меня вы — мёртвое мясо.»",
		"sprite": "res://assets/images/bard.png",
		"role": "ХИЛ",
		"role_note": "Поддержка",
		"difficulty": 4,
		"skills": [
			{"key": "Авто", "icon": ICON_DIR + "musical-notes.svg", "name": "Колкий бренчащий", "desc": "слабый снаряд для самозащиты", "hot": false},
			{"key": "ЛКМ",  "icon": ICON_DIR + "heart-bottle.svg",  "name": "Хил-аура",         "desc": "3 пульса лечения союзникам", "hot": false},
			{"key": "ПКМ",  "icon": ICON_DIR + "musical-score.svg", "name": "Боевая песнь",     "desc": "баф скорости и урона рядом", "hot": false},
			{"key": "Space","icon": ICON_DIR + "dodging.svg",       "name": "Дэш-уворот",       "desc": "i-frames на короткую дистанцию", "hot": true},
		],
	},
	"crossbow": {
		"name": "АРБАЛЕТЧИК",
		"subtitle": "Тихий охотник",
		"quote": "«Один выстрел. Одна цель. Тишина.»",
		"sprite": "res://assets/images/crossbowman.png",
		"role": "ДД",
		"role_note": "Single-target · Боссы",
		"difficulty": 3,
		"skills": [
			{"key": "Авто", "icon": ICON_DIR + "arrowhead.svg",    "name": "Авто-болт",        "desc": "стреляет в курсор постоянно", "hot": false},
			{"key": "ЛКМ",  "icon": ICON_DIR + "crosshair.svg",    "name": "Зарядка",          "desc": "удержание = ×4 урон, но замедляет", "hot": true},
			{"key": "ПКМ",  "icon": ICON_DIR + "winged-arrow.svg", "name": "Бронебойный болт", "desc": "пробивает группы врагов", "hot": false},
			{"key": "Space","icon": ICON_DIR + "dodging.svg",      "name": "Перекат",          "desc": "i-frames на короткую дистанцию", "hot": false},
		],
	},
}

const MAX_SQUAD: int = 4

# Main menu nodes
@onready var main_menu_view: MarginContainer = $Layout
@onready var nick_edit: LineEdit = %Nick
@onready var addr_edit: LineEdit = %Addr
@onready var port_edit: LineEdit = %Port
@onready var sprite_rect: TextureRect = %HeroSprite
@onready var prev_btn: Button = %PrevBtn
@onready var next_btn: Button = %NextBtn
@onready var class_name_label: Label = %ClassName
@onready var subtitle_label: Label = %Subtitle
@onready var quote_label: Label = %Quote
@onready var role_label: Label = %RoleLabel
@onready var role_note_label: Label = %RoleNote
@onready var stars: Control = %Stars
@onready var skills_row: GridContainer = %SkillsRow
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var leave_btn: Button = %LeaveBtn
@onready var debug_btn: Button = %DebugBtn
@onready var ready_btn: Button = %ReadyBtn
@onready var roster_label: Label = %Roster
@onready var status_label: Label = %StatusLabel
@onready var version_label: Label = %VersionLabel

# Waiting room nodes
@onready var waiting_room_view: Control = %WaitingRoomView
@onready var wr_subtitle: Label = %WRSubtitle
@onready var wr_settings_btn: Button = %WRSettingsBtn
@onready var wr_leave_btn: Button = %WRLeaveBtn
@onready var squad_count_label: Label = %SquadCount
@onready var squad_grid: GridContainer = %SquadGrid
@onready var start_btn: Button = %StartBtn
@onready var start_status: Label = %StartStatus
@onready var chat_log: Label = %ChatLog
@onready var chat_input: LineEdit = %ChatInput

var _class_idx: int = 0
var _is_ready: bool = false
var _join_error: String = ""

const WEB_BLOCK_HINT := "Недоступно в браузере: ENet/UDP не поддерживается WebAssembly. Скачай десктоп-сборку для коопа."

func _is_web() -> bool:
	return OS.has_feature("web")

func _ready() -> void:
	GameState.debug_mode = false
	nick_edit.text = GameState.local_nick
	port_edit.text = str(Network.DEFAULT_PORT)
	_class_idx = max(GameState.VALID_CLASSES.find(GameState.local_class), 0)
	prev_btn.pressed.connect(_on_prev_class)
	next_btn.pressed.connect(_on_next_class)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	leave_btn.pressed.connect(_on_quit_app)
	debug_btn.pressed.connect(_on_debug)
	ready_btn.pressed.connect(_on_ready_toggle)
	wr_leave_btn.pressed.connect(_on_leave)
	start_btn.pressed.connect(_on_start_btn)
	for b in [prev_btn, next_btn, host_btn, join_btn, leave_btn, debug_btn, ready_btn,
			settings_btn, wr_settings_btn, wr_leave_btn, start_btn]:
		b.pressed.connect(func(): AudioBus.play_ui(&"ui_click"))
		b.mouse_entered.connect(func(): AudioBus.play_ui(&"ui_hover", -10.5))
	nick_edit.text_changed.connect(func(t): GameState.local_nick = t)
	chat_input.editable = false
	chat_input.placeholder_text = "(чат пока отключён)"
	chat_input.focus_mode = Control.FOCUS_NONE
	chat_input.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	Network.lobby_updated.connect(_refresh)
	Network.ready_state_changed.connect(_refresh)
	Network.join_started.connect(_on_join_started)
	Network.join_failed.connect(_on_join_failed)
	GameState.roster_changed.connect(_refresh)
	version_label.text = "v 0.7.3 · alpha"
	if _is_web():
		host_btn.text = "Начать поход"
		join_btn.tooltip_text = WEB_BLOCK_HINT
		addr_edit.editable = false
		addr_edit.tooltip_text = WEB_BLOCK_HINT
		port_edit.editable = false
		port_edit.tooltip_text = WEB_BLOCK_HINT
		debug_btn.visible = false
		leave_btn.visible = false
	_apply_class_selection()
	_refresh()

func _on_prev_class() -> void:
	_class_idx = (_class_idx - 1 + GameState.VALID_CLASSES.size()) % GameState.VALID_CLASSES.size()
	_apply_class_selection()

func _on_next_class() -> void:
	_class_idx = (_class_idx + 1) % GameState.VALID_CLASSES.size()
	_apply_class_selection()

func _apply_class_selection() -> void:
	var klass: String = String(GameState.VALID_CLASSES[_class_idx])
	var info: Dictionary = CLASS_INFO.get(klass, {})
	class_name_label.text = info.get("name", klass)
	subtitle_label.text = info.get("subtitle", "")
	quote_label.text = info.get("quote", "")
	role_label.text = info.get("role", "—")
	role_note_label.text = "· " + String(info.get("role_note", ""))
	if stars and stars.has_method("set_value"):
		stars.set_value(int(info.get("difficulty", 2)))
	var path: String = info.get("sprite", "")
	if path != "" and ResourceLoader.exists(path):
		sprite_rect.texture = load(path)
	else:
		sprite_rect.texture = null
	_populate_skills(info.get("skills", []))
	Network.set_local_class(StringName(klass))

func _populate_skills(skills: Array) -> void:
	for c in skills_row.get_children():
		c.queue_free()
	for s in skills:
		var slot := _build_skill_slot(s)
		skills_row.add_child(slot)

func _build_skill_slot(s: Dictionary) -> Control:
	var hot: bool = bool(s.get("hot", false))
	var icon_color := Color(0.83, 0.63, 0.29, 1.0) if not hot else Color(0.84, 0.29, 0.23, 1.0)
	var ink_dim := Color(0.61, 0.53, 0.41, 1.0)
	var ink := Color(0.92, 0.85, 0.72, 1.0)
	var name_color := icon_color if hot else ink

	var root := HBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(48, 48)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.13, 0.09, 0.06, 0.85)
	icon_style.border_color = Color(0.22, 0.17, 0.13, 1.0)
	icon_style.set_border_width_all(1)
	icon_style.content_margin_left = 7
	icon_style.content_margin_right = 7
	icon_style.content_margin_top = 7
	icon_style.content_margin_bottom = 7
	icon_panel.add_theme_stylebox_override(&"panel", icon_style)

	var icon_path: String = String(s.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate = icon_color
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_panel.add_child(tr)
	else:
		var key_lbl := Label.new()
		key_lbl.text = String(s.get("key", "")).to_upper()
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_lbl.add_theme_color_override(&"font_color", icon_color)
		key_lbl.add_theme_font_size_override(&"font_size", 11)
		icon_panel.add_child(key_lbl)
	root.add_child(icon_panel)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override(&"separation", 2)
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_lbl := Label.new()
	name_lbl.text = String(s.get("name", "")).to_upper()
	name_lbl.add_theme_color_override(&"font_color", name_color)
	name_lbl.add_theme_font_size_override(&"font_size", 13)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_col.add_child(name_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(s.get("desc", ""))
	desc_lbl.add_theme_color_override(&"font_color", ink_dim)
	desc_lbl.add_theme_font_size_override(&"font_size", 11)
	desc_lbl.clip_text = true
	desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_col.add_child(desc_lbl)
	root.add_child(text_col)
	return root

func _exit_tree() -> void:
	Network.lobby_updated.disconnect(_refresh)
	Network.ready_state_changed.disconnect(_refresh)
	Network.join_started.disconnect(_on_join_started)
	Network.join_failed.disconnect(_on_join_failed)
	GameState.roster_changed.disconnect(_refresh)

func _on_join_started(_addr: String, _port: int) -> void:
	_join_error = ""
	_refresh()

func _on_join_failed(addr: String, port: int, reason: String) -> void:
	_is_ready = false
	_join_error = "не удалось подключиться к %s:%d (%s)" % [addr, port, reason]
	_refresh()

func _on_ready_toggle() -> void:
	_is_ready = not _is_ready
	Network.set_local_ready(_is_ready)
	_refresh()

func _on_start_btn() -> void:
	if multiplayer.is_server():
		if Network.has_method("request_start_round"):
			Network.request_start_round()
	else:
		_on_ready_toggle()

func _is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or not (peer is ENetMultiplayerPeer):
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _refresh() -> void:
	if not is_inside_tree():
		return
	var connected := _is_online()
	var connecting := Network.is_join_pending()
	main_menu_view.visible = not connected
	waiting_room_view.visible = connected

	# Main menu state
	var web := _is_web()
	host_btn.disabled = connected or connecting
	join_btn.disabled = connected or connecting or web
	debug_btn.disabled = connected or connecting
	leave_btn.disabled = false
	ready_btn.visible = false  # in waiting room now
	roster_label.visible = false

	if connected:
		var addr := addr_edit.text.strip_edges()
		if addr.is_empty():
			addr = "127.0.0.1"
		var port := int(port_edit.text)
		var info_addr := "хост" if multiplayer.is_server() else addr
		wr_subtitle.text = "ЛОББИ · %s:%d · id %d" % [info_addr, port, multiplayer.get_unique_id()]
		_rebuild_squad()
		_update_start_status()
		status_label.text = "● Подключено · id=%d" % multiplayer.get_unique_id()
		status_label.modulate = Color(0.76, 0.88, 0.62, 1)
	elif connecting:
		status_label.text = "● Подключение к %s:%d..." % [Network.pending_address(), Network.pending_port()]
		status_label.modulate = Color(0.83, 0.63, 0.29, 1)
	elif not _join_error.is_empty():
		status_label.text = "● %s" % _join_error
		status_label.modulate = Color(0.84, 0.29, 0.23, 1)
	elif web:
		status_label.text = "● Браузерная версия — только соло. Для коопа скачай десктоп."
		status_label.modulate = Color(0.83, 0.63, 0.29, 1)
	else:
		status_label.text = "● Сервер найден"
		status_label.modulate = Color(0.83, 0.63, 0.29, 1)

func _rebuild_squad() -> void:
	for c in squad_grid.get_children():
		c.queue_free()
	var entries: Array = []
	for pid in GameState.roster.keys():
		var entry: Dictionary = GameState.roster[pid]
		entries.append({
			"pid": pid,
			"nick": String(entry.get("nick", "?")),
			"klass": String(entry.get("klass", "?")),
			"is_host": pid == 1,
			"is_self": pid == multiplayer.get_unique_id(),
			"is_ready": Network.is_peer_ready(pid),
		})
	for e in entries:
		squad_grid.add_child(_build_player_slot(e))
	for i in range(MAX_SQUAD - entries.size()):
		squad_grid.add_child(_build_empty_slot())
	squad_count_label.text = "· %d / %d" % [entries.size(), MAX_SQUAD]

func _build_player_slot(e: Dictionary) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 130)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.055, 0.040, 0.7)
	if e.get("is_self", false):
		style.bg_color = Color(0.10, 0.075, 0.052, 0.85)
		style.border_color = Color(0.84, 0.29, 0.23, 0.95)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.30, 0.50, 0.18, 0.85)
		style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	slot.add_theme_stylebox_override(&"panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	slot.add_child(row)

	# Portrait frame
	var pframe := PanelContainer.new()
	pframe.custom_minimum_size = Vector2(86, 104)
	var pframe_style := StyleBoxFlat.new()
	pframe_style.bg_color = Color(0.025, 0.020, 0.015, 1)
	pframe_style.border_color = Color(0.22, 0.17, 0.13, 1)
	pframe_style.set_border_width_all(1)
	pframe.add_theme_stylebox_override(&"panel", pframe_style)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info: Dictionary = CLASS_INFO.get(String(e.get("klass", "")), {})
	var sprite_path: String = info.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		portrait.texture = load(sprite_path)
	pframe.add_child(portrait)
	row.add_child(pframe)

	# Info VBox
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override(&"separation", 4)
	row.add_child(info_col)

	# Nick + host tag
	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override(&"separation", 8)
	info_col.add_child(nick_row)

	var nick_lbl := Label.new()
	nick_lbl.text = String(e.get("nick", "?"))
	nick_lbl.add_theme_color_override(&"font_color", Color(0.92, 0.85, 0.72, 1))
	nick_lbl.add_theme_font_size_override(&"font_size", 18)
	nick_row.add_child(nick_lbl)

	if e.get("is_host", false):
		var host_pill := PanelContainer.new()
		var host_style := StyleBoxFlat.new()
		host_style.bg_color = Color(0, 0, 0, 0.4)
		host_style.border_color = Color(0.42, 0.35, 0.27, 1)
		host_style.set_border_width_all(1)
		host_style.content_margin_left = 6
		host_style.content_margin_right = 6
		host_style.content_margin_top = 1
		host_style.content_margin_bottom = 1
		host_pill.add_theme_stylebox_override(&"panel", host_style)
		host_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var hl := Label.new()
		hl.text = "ХОСТ"
		hl.add_theme_color_override(&"font_color", Color(0.61, 0.53, 0.41, 1))
		hl.add_theme_font_size_override(&"font_size", 10)
		host_pill.add_child(hl)
		nick_row.add_child(host_pill)

	# Class name
	var class_lbl := Label.new()
	var class_id := String(e.get("klass", ""))
	class_lbl.text = String(info.get("name", class_id)).to_upper()
	class_lbl.add_theme_color_override(&"font_color", Color(0.84, 0.45, 0.40, 1))
	class_lbl.add_theme_font_size_override(&"font_size", 12)
	info_col.add_child(class_lbl)

	# Role · role_note (e.g. "ДД · Single-target · Боссы")
	var role: String = String(info.get("role", ""))
	var role_note: String = String(info.get("role_note", ""))
	if role != "" or role_note != "":
		var role_lbl := Label.new()
		var sep: String = " · " if role != "" and role_note != "" else ""
		role_lbl.text = role + sep + role_note
		role_lbl.add_theme_color_override(&"font_color", Color(0.61, 0.53, 0.41, 1))
		role_lbl.add_theme_font_size_override(&"font_size", 10)
		role_lbl.clip_text = true
		role_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info_col.add_child(role_lbl)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_col.add_child(spacer)

	# Ready row
	var ready_row := HBoxContainer.new()
	ready_row.add_theme_constant_override(&"separation", 6)
	info_col.add_child(ready_row)
	var dot := _make_status_dot(bool(e.get("is_ready", false)))
	ready_row.add_child(dot)
	var ready_lbl := Label.new()
	ready_lbl.text = "ГОТОВ" if bool(e.get("is_ready", false)) else "НЕ ГОТОВ"
	ready_lbl.add_theme_color_override(&"font_color",
		Color(0.55, 0.78, 0.42, 1) if bool(e.get("is_ready", false))
		else Color(0.85, 0.50, 0.30, 1))
	ready_lbl.add_theme_font_size_override(&"font_size", 11)
	ready_row.add_child(ready_lbl)

	if e.get("is_self", false):
		slot.gui_input.connect(_on_self_slot_input)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var hint := Label.new()
		hint.text = "клик — переключить"
		hint.add_theme_color_override(&"font_color", Color(0.42, 0.35, 0.27, 1))
		hint.add_theme_font_size_override(&"font_size", 10)
		info_col.add_child(hint)

	return slot

func _build_empty_slot() -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(0, 130)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.035, 0.027, 0.6)
	style.border_color = Color(0.22, 0.17, 0.13, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	slot.add_theme_stylebox_override(&"panel", style)
	var lbl := Label.new()
	lbl.text = "+ СВОБОДНО"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override(&"font_color", Color(0.42, 0.35, 0.27, 1))
	lbl.add_theme_font_size_override(&"font_size", 13)
	slot.add_child(lbl)
	return slot

func _make_status_dot(is_ok: bool) -> Control:
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(10, 10)
	var col: Color = Color(0.45, 0.85, 0.40, 1) if is_ok else Color(0.95, 0.60, 0.32, 1)
	dot.draw.connect(func():
		dot.draw_circle(dot.size * 0.5, dot.size.x * 0.5, col)
		dot.draw_circle(dot.size * 0.5, dot.size.x * 0.32, Color(col.r * 1.4, col.g * 1.3, col.b * 1.2, 1))
	)
	return dot

func _on_self_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_ready_toggle()
		AudioBus.play_ui(&"ui_click")

func _update_start_status() -> void:
	var total: int = GameState.roster.size()
	var ready_count: int = 0
	for pid in GameState.roster.keys():
		if Network.is_peer_ready(pid):
			ready_count += 1
	var not_ready := total - ready_count
	var is_host := multiplayer.is_server()
	if is_host:
		start_btn.text = "Начать поход"
		start_btn.disabled = false
		if total <= 1:
			start_status.text = "● можно начинать соло"
			start_status.modulate = Color(0.61, 0.53, 0.41, 1)
		elif not_ready > 0:
			start_status.text = "● %d из %d готовы · можно стартовать" % [ready_count, total]
			start_status.modulate = Color(0.85, 0.50, 0.30, 1)
		else:
			start_status.text = "● все готовы"
			start_status.modulate = Color(0.55, 0.78, 0.42, 1)
	else:
		start_btn.text = "Не готов" if _is_ready else "Готов!"
		start_btn.disabled = false
		start_status.text = "● ожидаем хоста"
		start_status.modulate = Color(0.61, 0.53, 0.41, 1)

func _plural_suffix(n: int) -> String:
	var mod10 := n % 10
	var mod100 := n % 100
	if mod10 == 1 and mod100 != 11:
		return ""
	if mod10 in [2, 3, 4] and not (mod100 in [12, 13, 14]):
		return "а"
	return "ов"

func _on_host() -> void:
	GameState.local_nick = nick_edit.text.strip_edges()
	if GameState.local_nick.is_empty():
		GameState.local_nick = "Host"
	if _is_web():
		# No ENet/UDP in browser — go straight into a solo run.
		GameState.debug_mode = false
		get_tree().change_scene_to_file(Network.ARENA_SCENE_PATH)
		return
	var port := int(port_edit.text)
	_join_error = ""
	var err := Network.host(port)
	if err != OK:
		status_label.text = "● Host failed: %s" % str(err)
		status_label.modulate = Color(0.84, 0.29, 0.23, 1)
	_refresh()

func _on_join() -> void:
	GameState.local_nick = nick_edit.text.strip_edges()
	if GameState.local_nick.is_empty():
		GameState.local_nick = "Peer"
	var port := int(port_edit.text)
	var addr := addr_edit.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	_join_error = ""
	Network.join(addr, port)
	_refresh()

func _on_leave() -> void:
	_is_ready = false
	_join_error = ""
	Network.leave()
	_refresh()

func _on_quit_app() -> void:
	get_tree().quit()

func _on_debug() -> void:
	GameState.local_nick = nick_edit.text.strip_edges()
	if GameState.local_nick.is_empty():
		GameState.local_nick = "Debug"
	GameState.debug_mode = true
	get_tree().change_scene_to_file(Network.ARENA_SCENE_PATH)
