extends CanvasLayer

# Pure presentation. Reads GameState + local Player; submits upgrade picks
# through the UpgradeOffer node so this file knows nothing about RPC routing.

@onready var timer_label: Label = $Root/Top/TimerLabel
@onready var level_label: Label = $Root/Top/LevelLabel
@onready var xp_bar: ProgressBar = $Root/Top/XPBar
@onready var local_nick: Label = $Root/BottomLeft/LocalPanel/Nick
@onready var hp_bar: ProgressBar = $Root/BottomLeft/LocalPanel/HPBar
@onready var mp_bar: ProgressBar = $Root/BottomLeft/LocalPanel/MPBar
@onready var roster_box: VBoxContainer = $Root/TopLeft/Roster
@onready var upgrade_panel: PanelContainer = $Root/Center/UpgradePanel
@onready var upgrade_buttons: HBoxContainer = $Root/Center/UpgradePanel/VBox/Buttons
@onready var upgrade_label: Label = $Root/Center/UpgradePanel/VBox/Title
@onready var endgame_panel: PanelContainer = $Root/Center/EndgamePanel
@onready var endgame_label: Label = $Root/Center/EndgamePanel/VBox/Title
@onready var endgame_button: Button = $Root/Center/EndgamePanel/VBox/Back

const RUN_DURATION_FALLBACK := 600.0

var _local_player: Node = null

func _ready() -> void:
	add_to_group("hud")
	upgrade_panel.visible = false
	endgame_panel.visible = false
	endgame_button.pressed.connect(_on_back_to_lobby)
	EventBus.run_ended.connect(_on_run_ended)

func _process(_delta: float) -> void:
	_find_local_player()
	var run_duration: float = RUN_DURATION_FALLBACK
	if Defs.wave_set != null:
		run_duration = Defs.wave_set.run_duration
	var t: float = max(run_duration - GameState.run_time, 0.0)
	timer_label.text = "Time left: %d:%02d" % [int(t) / 60, int(t) % 60]
	level_label.text = "Party lvl %d" % GameState.party_level
	xp_bar.max_value = GameState.xp_threshold(GameState.party_level)
	xp_bar.value = GameState.party_xp
	if _local_player != null and is_instance_valid(_local_player):
		local_nick.text = "%s (%s)" % [_local_player.nick, String(_local_player.klass)]
		hp_bar.max_value = max(_local_player.max_hp, 1.0)
		hp_bar.value = _local_player.hp
		mp_bar.visible = _local_player.max_mp > 0.0
		if mp_bar.visible:
			mp_bar.max_value = _local_player.max_mp
			mp_bar.value = _local_player.mp
	_render_roster()

func _find_local_player() -> void:
	if _local_player != null and is_instance_valid(_local_player):
		return
	var my_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == my_id:
			_local_player = p
			return

func _render_roster() -> void:
	for c in roster_box.get_children():
		c.queue_free()
	for p in get_tree().get_nodes_in_group("players"):
		var lbl := Label.new()
		var status := ""
		if not p.alive:
			var remain: int = max(int(p.downed_until - Time.get_ticks_msec() / 1000.0), 0)
			status = " (down %ds)" % remain
		lbl.text = "%s [%s] HP %d/%d%s" % [p.nick, String(p.klass), int(p.hp), int(p.max_hp), status]
		roster_box.add_child(lbl)

func show_upgrade_picks(options: Array) -> void:
	upgrade_label.text = "LEVEL UP — pick one"
	for c in upgrade_buttons.get_children():
		c.queue_free()
	for opt in options:
		var b := Button.new()
		b.text = opt.get("label", opt.get("id", "?"))
		b.custom_minimum_size = Vector2(180, 60)
		var id: String = opt.get("id", "")
		b.pressed.connect(func ():
			AudioBus.play_ui(&"ui_click")
			upgrade_panel.visible = false
			_local_pick_upgrade(id)
		)
		b.mouse_entered.connect(func(): AudioBus.play_ui(&"ui_hover"))
		upgrade_buttons.add_child(b)
	upgrade_panel.visible = true

func _local_pick_upgrade(id: String) -> void:
	var offer := get_tree().get_first_node_in_group("upgrade_offer")
	if offer == null:
		return
	offer.submit_pick(id)

func _on_run_ended(won: bool) -> void:
	endgame_label.text = "VICTORY" if won else "WIPED"
	endgame_panel.visible = true

func _on_back_to_lobby() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://src/lobby/lobby.tscn")
