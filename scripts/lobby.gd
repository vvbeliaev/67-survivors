extends Control

const CLASS_INFO := {
	"berserker": {
		"name": "Берсерк",
		"sprite": "res://images/berserker.png",
		"desc": "Танк ближнего боя.\nКрутилка-AoE вокруг себя, рывок-удар, рев-агро, землетрясение-стан.\nУрон по вам = ресурс: чем меньше HP, тем сильнее рывок.",
	},
	"mage": {
		"name": "Волшебник",
		"sprite": "res://images/wizard.png",
		"desc": "AoE и контроль волн.\nАвто-снаряд по ближнему, файрбол по курсору (мана), цепная молния по 3 целям, блинк.\nХрупкий, но самый дальний урон.",
	},
	"bard": {
		"name": "Бард",
		"sprite": "res://images/bard.png",
		"desc": "Единственный хилер пати.\nХил-аура (3 пульса), баф скорости и урона союзникам, дэш с i-frames.\nБез него никого не лечат — позиционируйтесь.",
	},
	"crossbow": {
		"name": "Арбалетчик",
		"sprite": "res://images/crossbowman.png",
		"desc": "Single-target и боссы.\nЗаряжаемый болт (12→45 урона при удержании ЛКМ, замедляет), бронебойный пробивной болт, перекат с i-frames.",
	},
}

@onready var nick_edit: LineEdit = $Panel/HBox/RightCol/Conn/NickRow/Nick
@onready var addr_edit: LineEdit = $Panel/HBox/RightCol/Conn/AddrRow/Addr
@onready var port_edit: LineEdit = $Panel/HBox/RightCol/Conn/PortRow/Port
@onready var sprite_rect: TextureRect = $Panel/HBox/ClassPicker/Sprite
@onready var prev_btn: Button = $Panel/HBox/ClassPicker/Arrows/Prev
@onready var next_btn: Button = $Panel/HBox/ClassPicker/Arrows/Next
@onready var class_name_label: Label = $Panel/HBox/ClassPicker/Arrows/ClassName
@onready var desc_label: Label = $Panel/HBox/ClassPicker/Description
@onready var host_btn: Button = $Panel/HBox/RightCol/Buttons/HostJoin/Host
@onready var join_btn: Button = $Panel/HBox/RightCol/Buttons/HostJoin/Join
@onready var leave_btn: Button = $Panel/HBox/RightCol/Buttons/LeaveStart/Leave
@onready var start_btn: Button = $Panel/HBox/RightCol/Buttons/LeaveStart/Start
@onready var roster_label: Label = $Panel/HBox/RightCol/Roster
@onready var status_label: Label = $Panel/HBox/RightCol/Status

var _class_idx: int = 0

func _ready() -> void:
	nick_edit.text = GameState.local_nick
	port_edit.text = str(Network.DEFAULT_PORT)
	_class_idx = max(GameState.VALID_CLASSES.find(GameState.local_class), 0)
	prev_btn.pressed.connect(_on_prev_class)
	next_btn.pressed.connect(_on_next_class)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	leave_btn.pressed.connect(_on_leave)
	start_btn.pressed.connect(_on_start)
	nick_edit.text_changed.connect(func(t): GameState.local_nick = t)
	Network.lobby_updated.connect(_refresh)
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
	var klass: String = GameState.VALID_CLASSES[_class_idx]
	var info: Dictionary = CLASS_INFO.get(klass, {})
	class_name_label.text = info.get("name", klass)
	desc_label.text = info.get("desc", "")
	var path: String = info.get("sprite", "")
	if path != "" and ResourceLoader.exists(path):
		sprite_rect.texture = load(path)
	else:
		sprite_rect.texture = null
	Network.set_local_class(klass)

func _refresh() -> void:
	var connected := multiplayer.multiplayer_peer != null
	host_btn.disabled = connected
	join_btn.disabled = connected
	leave_btn.disabled = not connected
	start_btn.visible = connected and multiplayer.is_server()
	start_btn.disabled = GameState.roster.is_empty()
	var lines: Array[String] = []
	for pid in GameState.roster.keys():
		var entry: Dictionary = GameState.roster[pid]
		var marker := " (you)" if pid == multiplayer.get_unique_id() else ""
		var role := " [host]" if pid == 1 else ""
		var rk: String = entry.get("klass", "?")
		var rname: String = CLASS_INFO.get(rk, {}).get("name", rk)
		lines.append("- %s — %s%s%s" % [entry.get("nick", "?"), rname, role, marker])
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
	Network.leave()
	_refresh()

func _on_start() -> void:
	Network.request_start_round()
