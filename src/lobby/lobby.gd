extends Control

const CLASS_INFO := {
	"berserker": {
		"name": "БЕРСЕРК",
		"subtitle": "Безумец крови",
		"sprite": "res://assets/images/berserker.png",
		"desc": "[center][i][color=#c8c8d0]«Каждая рана — глоток силы.»[/color][/i][/center]\n\n[b]Роль:[/b] [color=#ff7878]Танк[/color] · Контроль агро\n[b]Сложность:[/b] [color=#ffc060]★★[/color]☆☆☆\n\n[b][color=#ffd060]Авто[/color][/b] — кружащий клинок, AoE вокруг себя\n[b][color=#ffd060]ЛКМ[/color][/b] — кровавый рывок, [color=#ff7878]бьёт сильнее при низком HP[/color]\n[b][color=#ffd060]ПКМ[/color][/b] — боевой рёв, стянуть агро в радиусе\n[b][color=#ffd060]Space[/color][/b] — землетрясение, стан врагов вокруг",
	},
	"mage": {
		"name": "ВОЛШЕБНИК",
		"subtitle": "Архимаг разрушения",
		"sprite": "res://assets/images/wizard.png",
		"desc": "[center][i][color=#c8c8d0]«Достаточно одной искры — и ничего не останется.»[/color][/i][/center]\n\n[b]Роль:[/b] [color=#7890ff]AoE[/color] · Контроль волн\n[b]Сложность:[/b] [color=#ffc060]★★★[/color]☆☆\n\n[b][color=#ffd060]Авто[/color][/b] — магический снаряд по ближайшему\n[b][color=#ffd060]ЛКМ[/color][/b] — файрбол, AoE по курсору ([color=#7890ff]30 маны[/color])\n[b][color=#ffd060]ПКМ[/color][/b] — цепная молния по 3 целям ([color=#7890ff]50 маны[/color])\n[b][color=#ffd060]Space[/color][/b] — блинк по курсору",
	},
	"bard": {
		"name": "БАРД",
		"subtitle": "Голос пати",
		"sprite": "res://assets/images/bard.png",
		"desc": "[center][i][color=#c8c8d0]«Без меня вы — мёртвое мясо. Запомните это.»[/color][/i][/center]\n\n[b]Роль:[/b] [color=#78f078]Хил[/color] · Поддержка\n[b]Сложность:[/b] [color=#ffc060]★★★★[/color]☆\n\n[b][color=#ffd060]Авто[/color][/b] — слабый снаряд для самозащиты\n[b][color=#ffd060]ЛКМ[/color][/b] — хил-аура, [color=#78f078]3 пульса лечения союзникам[/color]\n[b][color=#ffd060]ПКМ[/color][/b] — баф скорости и урона рядом стоящим\n[b][color=#ffd060]Space[/color][/b] — дэш-уворот с [color=#78f078]i-frames[/color]",
	},
	"crossbow": {
		"name": "АРБАЛЕТЧИК",
		"subtitle": "Тихий охотник",
		"sprite": "res://assets/images/crossbowman.png",
		"desc": "[center][i][color=#c8c8d0]«Один выстрел. Одна цель. Тишина.»[/color][/i][/center]\n\n[b]Роль:[/b] [color=#ffd060]Single-target[/color] · Убийца боссов\n[b]Сложность:[/b] [color=#ffc060]★★★[/color]☆☆\n\n[b][color=#ffd060]Авто[/color][/b] — заряжаемый болт ([color=#ffd060]12→45 урона[/color] при удержании ЛКМ)\n[b][color=#ff7878]Зарядка[/color][/b] замедляет — ловите момент\n[b][color=#ffd060]ПКМ[/color][/b] — бронебойный пробивной болт\n[b][color=#ffd060]Space[/color][/b] — перекат с [color=#78f078]i-frames[/color]",
	},
}

@onready var nick_edit: LineEdit = $Center/Panel/HBox/RightCol/Conn/NickRow/Nick
@onready var addr_edit: LineEdit = $Center/Panel/HBox/RightCol/Conn/AddrRow/Addr
@onready var port_edit: LineEdit = $Center/Panel/HBox/RightCol/Conn/PortRow/Port
@onready var sprite_rect: TextureRect = $Center/Panel/HBox/ClassPicker/Sprite
@onready var prev_btn: Button = $Center/Panel/HBox/ClassPicker/Arrows/Prev
@onready var next_btn: Button = $Center/Panel/HBox/ClassPicker/Arrows/Next
@onready var class_name_label: Label = $Center/Panel/HBox/ClassPicker/Arrows/ClassName
@onready var subtitle_label: Label = $Center/Panel/HBox/ClassPicker/Subtitle
@onready var desc_label: RichTextLabel = $Center/Panel/HBox/ClassPicker/Description
@onready var host_btn: Button = $Center/Panel/HBox/RightCol/Buttons/HostWrap/Host
@onready var join_btn: Button = $Center/Panel/HBox/RightCol/Buttons/JoinWrap/Join
@onready var leave_btn: Button = $Center/Panel/HBox/RightCol/Buttons/LeaveWrap/Leave
@onready var ready_btn: Button = $Center/Panel/HBox/RightCol/Buttons/ReadyWrap/Ready
@onready var roster_label: Label = $Center/Panel/HBox/RightCol/Roster
@onready var status_label: Label = $Center/Panel/HBox/RightCol/Status

var _class_idx: int = 0
var _is_ready: bool = false

func _ready() -> void:
	nick_edit.text = GameState.local_nick
	port_edit.text = str(Network.DEFAULT_PORT)
	_class_idx = max(GameState.VALID_CLASSES.find(GameState.local_class), 0)
	prev_btn.pressed.connect(_on_prev_class)
	next_btn.pressed.connect(_on_next_class)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	leave_btn.pressed.connect(_on_leave)
	ready_btn.pressed.connect(_on_ready_toggle)
	for b in [prev_btn, next_btn, host_btn, join_btn, leave_btn, ready_btn]:
		b.pressed.connect(func(): AudioBus.play_ui(&"ui_click"))
		b.mouse_entered.connect(func(): AudioBus.play_ui(&"ui_hover"))
	nick_edit.text_changed.connect(func(t): GameState.local_nick = t)
	Network.lobby_updated.connect(_refresh)
	Network.ready_state_changed.connect(_refresh)
	GameState.roster_changed.connect(_refresh)
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
	desc_label.text = info.get("desc", "")
	var path: String = info.get("sprite", "")
	if path != "" and ResourceLoader.exists(path):
		sprite_rect.texture = load(path)
	else:
		sprite_rect.texture = null
	Network.set_local_class(StringName(klass))

func _on_ready_toggle() -> void:
	_is_ready = not _is_ready
	Network.set_local_ready(_is_ready)
	_refresh()

func _refresh() -> void:
	var connected := multiplayer.multiplayer_peer != null
	host_btn.disabled = connected
	join_btn.disabled = connected
	leave_btn.disabled = not connected
	ready_btn.visible = connected
	ready_btn.text = "Не готов" if _is_ready else "Готов!"

	var lines: Array[String] = []
	for pid in GameState.roster.keys():
		var entry: Dictionary = GameState.roster[pid]
		var marker := " (вы)" if pid == multiplayer.get_unique_id() else ""
		var role := " [хост]" if pid == 1 else ""
		var rk: String = String(entry.get("klass", "?"))
		var rname: String = CLASS_INFO.get(rk, {}).get("name", rk)
		var rdy: String = " ✓" if Network.is_peer_ready(pid) else " ⏳"
		lines.append("- %s — %s%s%s%s" % [entry.get("nick", "?"), rname, rdy, role, marker])
	roster_label.text = "Пати:\n" + ("\n".join(lines) if lines.size() > 0 else "(пусто)")

	if connected:
		status_label.text = "Подключено. id=%d host=%s" % [multiplayer.get_unique_id(), str(multiplayer.is_server())]
	else:
		status_label.text = "Оффлайн"

func _on_host() -> void:
	GameState.local_nick = nick_edit.text.strip_edges()
	if GameState.local_nick.is_empty():
		GameState.local_nick = "Host"
	var port := int(port_edit.text)
	var err := Network.host(port)
	if err != OK:
		status_label.text = "Host failed: %s" % str(err)
	_refresh()

func _on_join() -> void:
	GameState.local_nick = nick_edit.text.strip_edges()
	if GameState.local_nick.is_empty():
		GameState.local_nick = "Peer"
	var port := int(port_edit.text)
	var addr := addr_edit.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	var err := Network.join(addr, port)
	if err != OK:
		status_label.text = "Join failed: %s" % str(err)
	_refresh()

func _on_leave() -> void:
	_is_ready = false
	Network.leave()
	_refresh()
