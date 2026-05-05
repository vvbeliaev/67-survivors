extends Control

@onready var nick_edit: LineEdit = $Panel/VBox/NickRow/Nick
@onready var addr_edit: LineEdit = $Panel/VBox/AddrRow/Addr
@onready var port_edit: LineEdit = $Panel/VBox/AddrRow/Port
@onready var class_option: OptionButton = $Panel/VBox/ClassRow/ClassOption
@onready var host_btn: Button = $Panel/VBox/Buttons/Host
@onready var join_btn: Button = $Panel/VBox/Buttons/Join
@onready var leave_btn: Button = $Panel/VBox/Buttons/Leave
@onready var start_btn: Button = $Panel/VBox/Buttons/Start
@onready var roster_label: Label = $Panel/VBox/Roster
@onready var status_label: Label = $Panel/VBox/Status

func _ready() -> void:
	nick_edit.text = GameState.local_nick
	port_edit.text = str(Network.DEFAULT_PORT)
	for klass in GameState.VALID_CLASSES:
		class_option.add_item(String(klass))
	class_option.select(GameState.VALID_CLASSES.find(GameState.local_class))
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	leave_btn.pressed.connect(_on_leave)
	start_btn.pressed.connect(_on_start)
	class_option.item_selected.connect(_on_class_selected)
	nick_edit.text_changed.connect(func(t): GameState.local_nick = t)
	Network.lobby_updated.connect(_refresh)
	GameState.roster_changed.connect(_refresh)
	_refresh()

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
		lines.append("- %s as %s%s%s" % [entry.get("nick", "?"), String(entry.get("klass", &"?")), role, marker])
	roster_label.text = "Roster:\n" + ("\n".join(lines) if lines.size() > 0 else "(empty)")
	if connected:
		status_label.text = "Connected. id=%d host=%s" % [multiplayer.get_unique_id(), str(multiplayer.is_server())]
	else:
		status_label.text = "Offline"

func _on_class_selected(idx: int) -> void:
	var klass: StringName = GameState.VALID_CLASSES[idx]
	Network.set_local_class(klass)

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
