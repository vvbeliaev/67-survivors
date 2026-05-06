extends CanvasLayer

# Pure presentation. Reads GameState + local Player + EventBus, draws the
# whole top-down HUD. Submits upgrade picks through the UpgradeOffer node so
# this file knows nothing about RPC routing. Layout is built programmatically
# in _ready() to keep the .tscn minimal — the widget classes under
# `src/ui/widgets/` do the custom drawing.

const FONT_DISPLAY := preload("res://assets/fonts/Cinzel.ttf")
const FONT_UI := preload("res://assets/fonts/Inter.ttf")
const FONT_MONO := preload("res://assets/fonts/JetBrainsMono.ttf")

const PORTRAITS := {
	&"berserker": preload("res://assets/images/berserker_top.png"),
	&"mage":      preload("res://assets/images/wizard_top.png"),
	&"bard":      preload("res://assets/images/bard_top.png"),
	&"crossbow":  preload("res://assets/images/crossbowman_top.png"),
}

const CLASS_LABEL := {
	&"berserker": "berserker",
	&"mage":      "mage",
	&"bard":      "bard",
	&"crossbow":  "crossbow",
}

const CLASS_RESOURCE := {
	&"berserker": "ЯР",
	&"mage":      "МП",
	&"bard":      "МП",
	&"crossbow":  "ВЫН",
}

const SKILL_KEYS := ["Авто", "ЛКМ", "ПКМ", "Space"]

const SKILL_GLYPHS := {
	&"berserker": ["⊛", "↗", "◊", "▼"],
	&"mage":      ["✦", "✷", "Z", "✶"],
	&"bard":      ["♪", "✚", "♫", "↗"],
	&"crossbow":  ["→", "▲", "⇒", "↻"],
}

const ENEMY_NAMES := {
	&"rusher":   "Рашер",
	&"swarm":    "Рой",
	&"ranged":   "Стрелок",
	&"tank":     "Танк",
	&"colossus": "Колосс",
	&"boss":     "Паучья Матерь",
}

const BOSS_NAMES := {
	&"boss": "Паучья Матерь",
}

const BOSS_SUBTITLES := {
	&"boss": "СЕКТОР III · ЛОГОВО",
}

const RUN_DURATION_FALLBACK := 600.0
const KILL_AGGREGATE_WINDOW := 2.0       # seconds to fold "X × N" kill lines
const LOG_MAX_ENTRIES := 5

@onready var _root: Control = $Root
@onready var _party_anchor: Control = $Root/PartyAnchor
@onready var _status_anchor: Control = $Root/StatusAnchor
@onready var _minimap_anchor: Control = $Root/MinimapAnchor
@onready var _log_anchor: Control = $Root/LogAnchor
@onready var _vitals_anchor: Control = $Root/VitalsAnchor
@onready var _boss_anchor: Control = $Root/BossAnchor
@onready var _center_anchor: Control = $Root/CenterAnchor

# Built widgets — populated in _ready, mutated in _process.
var _party_box: VBoxContainer = null
var _party_cards: Dictionary = {}        # peer_id -> PartyCard

var _timer_label: Label = null
var _level_label: Label = null
var _xp_bar: ThemedBar = null
var _xp_pct_label: Label = null

var _minimap: MinimapWidget = null

var _hp_bar: ThemedBar = null
var _mp_bar: ThemedBar = null
var _mp_label_node: Label = null
var _mp_holder: Control = null
var _skill_slots: Array[SkillSlot] = []

var _log_box: VBoxContainer = null
var _log_entries: Array = []             # of {text: String, color: Color, time: float, kill_key: String, kill_n: int}

var _boss_panel: HUDPanel = null
var _boss_status: Label = null
var _boss_name_label: Label = null
var _boss_countdown: Label = null

var _upgrade_panel: HUDPanel = null
var _upgrade_title: Label = null
var _upgrade_buttons: HBoxContainer = null
var _end_screen: EndScreen = null

var _local_player: Node = null

func _ready() -> void:
	add_to_group("hud")
	_build_party_panel()
	_build_status_bar()
	_build_minimap()
	_build_vitals_and_skills()
	_build_boss_watch()
	_build_upgrade_panel()
	_build_end_screen()

	EventBus.run_ended.connect(_on_run_ended)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.player_revived.connect(_on_player_revived)
	EventBus.player_healed.connect(_on_player_healed)
	EventBus.upgrade_picked.connect(_on_upgrade_picked)
	EventBus.level_up.connect(_on_level_up)

func _process(_dt: float) -> void:
	_find_local_player()
	_update_status_bar()
	_update_party_panel()
	_update_vitals()
	_update_skills()
	_update_boss_watch()

# =========================================================================
# Party panel (top-left)
# =========================================================================

func _build_party_panel() -> void:
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 8)
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_anchor.add_child(_party_box)

func _update_party_panel() -> void:
	# Sync card-per-peer with players group. Local player first, others by peer id.
	var present: Dictionary = {}
	var players := get_tree().get_nodes_in_group("players")
	var local_id := _local_peer_id()
	# Sort: local first, then by peer_id.
	players.sort_custom(func (a, b):
		var ai: int = int(a.peer_id)
		var bi: int = int(b.peer_id)
		if ai == local_id and bi != local_id:
			return true
		if bi == local_id and ai != local_id:
			return false
		return ai < bi
	)
	var idx := 0
	for plr in players:
		if not is_instance_valid(plr):
			continue
		var pid: int = int(plr.peer_id)
		present[pid] = true
		var card: PartyCard = _party_cards.get(pid)
		if card == null:
			card = _make_party_card(plr)
			_party_cards[pid] = card
			_party_box.add_child(card)
		_party_box.move_child(card, idx)
		idx += 1
		_refresh_party_card(card, plr)
	# Remove cards for departed players.
	for pid_var in _party_cards.keys():
		var pid: int = int(pid_var)
		if not present.has(pid):
			var card: PartyCard = _party_cards[pid]
			card.queue_free()
			_party_cards.erase(pid)

func _make_party_card(plr: Node) -> PartyCard:
	var card := PartyCard.new()
	card.nick_font = FONT_DISPLAY
	card.class_font = FONT_MONO
	card.hp_font = FONT_MONO
	var klass: StringName = StringName(String(plr.klass))
	card.portrait = PORTRAITS.get(klass)
	card.class_label = CLASS_LABEL.get(klass, String(klass))
	card.class_color = HUDPalette.CLASS_COLOR.get(klass, HUDPalette.INK_DIM)
	return card

func _refresh_party_card(card: PartyCard, plr: Node) -> void:
	card.nick = String(plr.nick)
	card.is_local = int(plr.peer_id) == _local_peer_id()
	card.update_state(float(plr.hp), float(plr.max_hp), bool(plr.alive))

# =========================================================================
# Run status bar (top-center)
# =========================================================================

func _build_status_bar() -> void:
	var panel := HUDPanel.new()
	panel.bevel = 8.0
	panel.custom_minimum_size = Vector2(560, 50)
	panel.position = Vector2(-280, 24)
	_status_anchor.add_child(panel)

	var hb := HBoxContainer.new()
	hb.position = Vector2(20, 0)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 20
	hb.offset_right = -20
	hb.add_theme_constant_override("separation", 18)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)

	# "осталось 09:51"
	var time_box := _make_kv("осталось", "09:51", 24)
	hb.add_child(time_box)
	_timer_label = time_box.get_node("Value")

	hb.add_child(_make_v_separator())

	# "пати LVL 7"
	var lvl_box := _make_kv("пати", "LVL 1", 18, HUDPalette.ACCENT)
	hb.add_child(lvl_box)
	_level_label = lvl_box.get_node("Value")

	hb.add_child(_make_v_separator())

	# "прогресс [bar] 43%"
	var prog_holder := HBoxContainer.new()
	prog_holder.add_theme_constant_override("separation", 10)
	prog_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	prog_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(prog_holder)

	var prog_label := Label.new()
	prog_label.text = "прогресс"
	prog_label.add_theme_font_override("font", FONT_UI)
	prog_label.add_theme_font_size_override("font_size", 10)
	prog_label.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
	prog_label.add_theme_constant_override("outline_size", 0)
	prog_label.text = "ПРОГРЕСС"
	prog_holder.add_child(prog_label)

	_xp_bar = ThemedBar.new()
	_xp_bar.kind = ThemedBar.Kind.XP
	_xp_bar.bar_height_override = 8.0
	_xp_bar.custom_minimum_size = Vector2(180, 8)
	prog_holder.add_child(_xp_bar)

	_xp_pct_label = Label.new()
	_xp_pct_label.text = "0%"
	_xp_pct_label.add_theme_font_override("font", FONT_MONO)
	_xp_pct_label.add_theme_font_size_override("font_size", 13)
	_xp_pct_label.add_theme_color_override("font_color", HUDPalette.ACCENT)
	prog_holder.add_child(_xp_pct_label)

func _make_kv(key: String, value: String, value_size: int, value_color: Color = HUDPalette.INK) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var k := Label.new()
	k.text = key.to_upper()
	k.add_theme_font_override("font", FONT_UI)
	k.add_theme_font_size_override("font_size", 10)
	k.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
	box.add_child(k)

	var v := Label.new()
	v.name = "Value"
	v.text = value
	v.add_theme_font_override("font", FONT_DISPLAY)
	v.add_theme_font_size_override("font_size", value_size)
	v.add_theme_color_override("font_color", value_color)
	v.add_theme_constant_override("outline_size", 4)
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_child(v)

	return box

func _make_v_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = HUDPalette.STROKE_STRONG
	sep.custom_minimum_size = Vector2(1, 24)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func _update_status_bar() -> void:
	var run_duration: float = RUN_DURATION_FALLBACK
	if Defs.wave_set != null:
		run_duration = Defs.wave_set.run_duration
	var t: float = max(run_duration - GameState.run_time, 0.0)
	if _timer_label != null:
		_timer_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
	if _level_label != null:
		_level_label.text = "LVL %d" % GameState.party_level
	if _xp_bar != null:
		var thr: int = GameState.xp_threshold(GameState.party_level)
		_xp_bar.set_progress(float(GameState.party_xp), float(max(thr, 1)))
		if _xp_pct_label != null:
			var pct: int = int(round(100.0 * float(GameState.party_xp) / float(max(thr, 1))))
			_xp_pct_label.text = "%d%%" % pct

# =========================================================================
# Minimap (top-right)
# =========================================================================

func _build_minimap() -> void:
	_minimap = MinimapWidget.new()
	_minimap.label_font = FONT_MONO
	# Anchor right edge of widget at right edge of screen, with 24px margin.
	_minimap.position = Vector2(-(_minimap.MAP_W + 16) - 24, 24)
	_minimap_anchor.add_child(_minimap)

# =========================================================================
# Vitals + skill bar (bottom-center)
# =========================================================================

func _build_vitals_and_skills() -> void:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(-330, -136)
	holder.custom_minimum_size = Vector2(660, 0)
	_vitals_anchor.add_child(holder)

	# Vitals row.
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 10)
	vrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(vrow)

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_override("font", FONT_DISPLAY)
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", HUDPalette.HEALTH_BRIGHT)
	hp_label.add_theme_constant_override("outline_size", 4)
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	vrow.add_child(hp_label)

	_hp_bar = ThemedBar.new()
	_hp_bar.kind = ThemedBar.Kind.HEALTH
	_hp_bar.segments = true
	_hp_bar.segment_step = 24.0
	_hp_bar.bar_height_override = 18.0
	_hp_bar.custom_minimum_size = Vector2(360, 18)
	_hp_bar.label_font = FONT_MONO
	_hp_bar.label_font_size = 11
	_hp_bar.label_text = "0 / 0"
	vrow.add_child(_hp_bar)

	_mp_holder = HBoxContainer.new()
	_mp_holder.add_theme_constant_override("separation", 10)
	_mp_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_mp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vrow.add_child(_mp_holder)

	_mp_label_node = Label.new()
	_mp_label_node.text = "ЯР"
	_mp_label_node.add_theme_font_override("font", FONT_DISPLAY)
	_mp_label_node.add_theme_font_size_override("font_size", 14)
	_mp_label_node.add_theme_color_override("font_color", HUDPalette.MANA_BRIGHT)
	_mp_label_node.add_theme_constant_override("outline_size", 4)
	_mp_label_node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_mp_holder.add_child(_mp_label_node)

	_mp_bar = ThemedBar.new()
	_mp_bar.kind = ThemedBar.Kind.MANA
	_mp_bar.segments = true
	_mp_bar.segment_step = 22.0
	_mp_bar.bar_height_override = 18.0
	_mp_bar.custom_minimum_size = Vector2(180, 18)
	_mp_bar.label_font = FONT_MONO
	_mp_bar.label_font_size = 11
	_mp_bar.label_text = "0 / 0"
	_mp_holder.add_child(_mp_bar)

	# Skill bar.
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 14)
	sb.alignment = BoxContainer.ALIGNMENT_CENTER
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sb)
	for i in 4:
		var slot := SkillSlot.new()
		slot.glyph_font = FONT_DISPLAY
		slot.key_font = FONT_MONO
		slot.cd_font = FONT_DISPLAY
		slot.key_label = SKILL_KEYS[i]
		slot.glyph = "•"
		_skill_slots.append(slot)
		sb.add_child(slot)

func _update_vitals() -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		_hp_bar.set_progress(0, 1)
		_hp_bar.label_text = "—"
		_hp_bar.queue_redraw()
		_mp_holder.visible = false
		return
	var hp_now: float = float(_local_player.hp)
	var hp_max: float = max(float(_local_player.max_hp), 1.0)
	_hp_bar.label_text = "%d / %d" % [int(hp_now), int(hp_max)]
	_hp_bar.set_progress(hp_now, hp_max)

	var mp_max: float = float(_local_player.max_mp)
	_mp_holder.visible = mp_max > 0.0
	if mp_max > 0.0:
		var klass: StringName = StringName(String(_local_player.klass))
		_mp_label_node.text = CLASS_RESOURCE.get(klass, "МП")
		_mp_bar.set_progress(float(_local_player.mp), mp_max)
		_mp_bar.label_text = "%d / %d" % [int(_local_player.mp), int(mp_max)]

func _update_skills() -> void:
	var glyphs: Array = []
	var skills: Array = []
	var cd_lefts: Array = [0.0, 0.0, 0.0, 0.0]
	var cd_totals: Array = [0.0, 0.0, 0.0, 0.0]
	if _local_player != null and is_instance_valid(_local_player) and _local_player.class_node != null:
		var cn = _local_player.class_node
		skills = [cn.auto_skill, cn.primary_skill, cn.secondary_skill, cn.utility_skill]
		var klass: StringName = StringName(String(_local_player.klass))
		glyphs = SKILL_GLYPHS.get(klass, ["•", "•", "•", "•"])
		cd_lefts = [
			float(_local_player.cd_left_auto),
			float(_local_player.cd_left_primary),
			float(_local_player.cd_left_secondary),
			float(_local_player.cd_left_utility),
		]
		cd_totals = [
			float(_local_player.cd_total_auto),
			float(_local_player.cd_total_primary),
			float(_local_player.cd_total_secondary),
			float(_local_player.cd_total_utility),
		]
	for i in _skill_slots.size():
		var slot: SkillSlot = _skill_slots[i]
		var s = skills[i] if i < skills.size() else null
		var g: String = glyphs[i] if i < glyphs.size() else "•"
		if s == null:
			slot.glyph = g
			slot.set_state(0.0, 0.0, true)
			continue
		slot.glyph = g
		var cd_left: float = float(cd_lefts[i])
		var cd_total: float = max(float(cd_totals[i]), 0.001)
		var cd_pct: float = clampf(cd_left / cd_total, 0.0, 1.0)
		var disabled := false
		if float(s.mana_cost) > 0.0 and _local_player != null:
			disabled = float(_local_player.mp) < float(s.mana_cost)
		slot.set_state(cd_pct, cd_left, disabled)

# =========================================================================
# Event log (bottom-left)
# =========================================================================

func _build_event_log() -> void:
	var panel := HUDPanel.new()
	panel.bevel = 6.0
	panel.custom_minimum_size = Vector2(340, 100)
	panel.position = Vector2(24, -124)
	_log_anchor.add_child(panel)

	_log_box = VBoxContainer.new()
	_log_box.position = Vector2(12, 8)
	_log_box.size = Vector2(316, 84)
	_log_box.add_theme_constant_override("separation", 4)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_log_box)

func _push_log(text: String, color: Color, kill_key: String = "") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Aggregate consecutive kills of the same enemy type within the window.
	if kill_key != "" and not _log_entries.is_empty():
		var last: Dictionary = _log_entries[-1]
		if String(last.get("kill_key", "")) == kill_key and now - float(last.get("time", 0.0)) <= KILL_AGGREGATE_WINDOW:
			last["kill_n"] = int(last.get("kill_n", 1)) + 1
			last["text"] = "%s × %d" % [String(last.get("base_text", text)), int(last["kill_n"])]
			last["time"] = now
			_log_entries[-1] = last
			return
	var entry := {
		"text": text,
		"base_text": text,
		"color": color,
		"time": now,
		"kill_key": kill_key,
		"kill_n": 1 if kill_key != "" else 0,
	}
	_log_entries.append(entry)
	while _log_entries.size() > LOG_MAX_ENTRIES:
		_log_entries.pop_front()

func _update_event_log() -> void:
	if _log_box == null:
		return
	for c in _log_box.get_children():
		c.queue_free()
	for entry in _log_entries:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_log_box.add_child(hb)

		var marker := ColorRect.new()
		marker.color = entry["color"]
		marker.custom_minimum_size = Vector2(6, 6)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.rotation = PI * 0.25
		marker.pivot_offset = Vector2(3, 3)
		hb.add_child(marker)

		var text := Label.new()
		text.text = String(entry["text"])
		text.add_theme_font_override("font", FONT_UI)
		text.add_theme_font_size_override("font_size", 12)
		text.add_theme_color_override("font_color", HUDPalette.INK_DIM)
		hb.add_child(text)

# =========================================================================
# Boss watch (bottom-right)
# =========================================================================

func _build_boss_watch() -> void:
	_boss_panel = HUDPanel.new()
	_boss_panel.bevel = 6.0
	_boss_panel.custom_minimum_size = Vector2(240, 78)
	_boss_panel.position = Vector2(-(240) - 24, -100)
	_boss_anchor.add_child(_boss_panel)

	var v := VBoxContainer.new()
	v.position = Vector2(14, 10)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)

	var diamond := ColorRect.new()
	diamond.color = HUDPalette.DANGER
	diamond.custom_minimum_size = Vector2(10, 10)
	diamond.rotation = PI * 0.25
	diamond.pivot_offset = Vector2(5, 5)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(diamond)

	_boss_status = Label.new()
	_boss_status.text = "БОСС ПРИБЛИЖАЕТСЯ"
	_boss_status.add_theme_font_override("font", FONT_DISPLAY)
	_boss_status.add_theme_font_size_override("font_size", 12)
	_boss_status.add_theme_color_override("font_color", HUDPalette.DANGER)
	head.add_child(_boss_status)

	_boss_name_label = Label.new()
	_boss_name_label.text = "Паучья Матерь"
	_boss_name_label.add_theme_font_override("font", FONT_DISPLAY)
	_boss_name_label.add_theme_font_size_override("font_size", 20)
	_boss_name_label.add_theme_color_override("font_color", HUDPalette.INK)
	_boss_name_label.add_theme_constant_override("outline_size", 4)
	_boss_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	v.add_child(_boss_name_label)

	_boss_countdown = Label.new()
	_boss_countdown.text = "через 00:00"
	_boss_countdown.add_theme_font_override("font", FONT_MONO)
	_boss_countdown.add_theme_font_size_override("font_size", 11)
	_boss_countdown.add_theme_color_override("font_color", HUDPalette.INK_MUTE)
	v.add_child(_boss_countdown)

func _update_boss_watch() -> void:
	if _boss_panel == null:
		return
	var run_duration: float = RUN_DURATION_FALLBACK
	var boss_id: StringName = &"boss"
	if Defs.wave_set != null:
		run_duration = Defs.wave_set.run_duration
		boss_id = StringName(String(Defs.wave_set.boss_id))
	_boss_name_label.text = String(BOSS_NAMES.get(boss_id, "Босс"))

	var remaining: float = run_duration - GameState.run_time
	# Hide if run hasn't started or already long over.
	if not GameState.run_active:
		_boss_panel.visible = false
		return
	_boss_panel.visible = true
	if remaining <= 0.0:
		_boss_status.text = "БОСС НА АРЕНЕ"
		_boss_countdown.text = "сектор III"
	else:
		_boss_status.text = "БОСС ПРИБЛИЖАЕТСЯ"
		_boss_countdown.text = "через %d:%02d" % [int(remaining) / 60, int(remaining) % 60]

# =========================================================================
# Upgrade panel (center, on level up)
# =========================================================================

func _build_upgrade_panel() -> void:
	_upgrade_panel = HUDPanel.new()
	_upgrade_panel.bevel = 12.0
	_upgrade_panel.rivets = true
	_upgrade_panel.accent_border = true
	_upgrade_panel.custom_minimum_size = Vector2(720, 240)
	_upgrade_panel.position = Vector2(-360, -120)
	_upgrade_panel.visible = false
	_upgrade_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_center_anchor.add_child(_upgrade_panel)

	var v := VBoxContainer.new()
	v.position = Vector2(20, 20)
	v.size = Vector2(680, 200)
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_upgrade_panel.add_child(v)

	_upgrade_title = Label.new()
	_upgrade_title.text = "LEVEL UP — выберите силу"
	_upgrade_title.add_theme_font_override("font", FONT_DISPLAY)
	_upgrade_title.add_theme_font_size_override("font_size", 20)
	_upgrade_title.add_theme_color_override("font_color", HUDPalette.ACCENT)
	_upgrade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_title.add_theme_constant_override("outline_size", 4)
	_upgrade_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	v.add_child(_upgrade_title)

	_upgrade_buttons = HBoxContainer.new()
	_upgrade_buttons.add_theme_constant_override("separation", 16)
	_upgrade_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_upgrade_buttons)

func show_upgrade_picks(options: Array) -> void:
	_upgrade_title.text = "LEVEL UP — выберите силу"
	for c in _upgrade_buttons.get_children():
		c.queue_free()
	for opt in options:
		var b := _make_upgrade_button(String(opt.get("label", opt.get("id", "?"))), String(opt.get("id", "")))
		_upgrade_buttons.add_child(b)
	_upgrade_panel.visible = true

func _make_upgrade_button(label: String, id: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(200, 96)
	b.add_theme_font_override("font", FONT_DISPLAY)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", HUDPalette.INK)
	b.add_theme_color_override("font_hover_color", HUDPalette.ACCENT_GLOW)
	b.add_theme_color_override("font_pressed_color", HUDPalette.ACCENT_DEEP)
	var sb := StyleBoxFlat.new()
	sb.bg_color = HUDPalette.PANEL
	sb.border_color = HUDPalette.STROKE_STRONG
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = HUDPalette.PANEL_SOFT
	sb_hover.border_color = HUDPalette.ACCENT_DEEP
	b.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = HUDPalette.BG_DEEP
	sb_pressed.border_color = HUDPalette.ACCENT
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.pressed.connect(func ():
		AudioBus.play_ui(&"ui_click")
		_upgrade_panel.visible = false
		_local_pick_upgrade(id)
	)
	b.mouse_entered.connect(func (): AudioBus.play_ui(&"ui_hover", -10.5))
	return b

func _local_pick_upgrade(id: String) -> void:
	var offer := get_tree().get_first_node_in_group("upgrade_offer")
	if offer == null:
		return
	offer.submit_pick(id)

# =========================================================================
# End screen (victory / death)
# =========================================================================

func _build_end_screen() -> void:
	_end_screen = EndScreen.new()
	_end_screen.back_to_lobby.connect(_on_back_to_lobby)
	_root.add_child(_end_screen)

func _on_run_ended(won: bool) -> void:
	if _end_screen == null:
		return
	# Hide every other HUD anchor so the death overlay reads cleanly.
	for child in _root.get_children():
		if child == _end_screen:
			continue
		if child is Control:
			(child as Control).visible = false
	_end_screen.show_for_run(
		won,
		GameState.run_time,
		GameState.run_kills,
		GameState.run_damage,
		GameState.run_xp_gained,
	)

func _on_back_to_lobby() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://src/lobby/lobby.tscn")

# =========================================================================
# EventBus → log lines
# =========================================================================

func _on_enemy_killed(enemy: Node, _killer_peer: int) -> void:
	if enemy == null:
		return
	var t: StringName = StringName(String(enemy.get("enemy_type"))) if enemy.get("enemy_type") != null else &"enemy"
	var name_str: String = String(ENEMY_NAMES.get(t, String(t)))
	# Killer attribution is currently unreliable (always 1) — credit the
	# locally-controlled player, which reads naturally for solo play.
	var nick: String = _resolve_nick(_local_peer_id())
	var text := "%s убил %s" % [nick, name_str]
	_push_log(text, HUDPalette.LOG_KILL, "kill:%s" % String(t))

func _on_player_downed(peer_id: int) -> void:
	var nick := _resolve_nick(peer_id)
	_push_log("%s пал" % nick, HUDPalette.LOG_DMG)

func _on_player_revived(peer_id: int) -> void:
	var nick := _resolve_nick(peer_id)
	_push_log("%s встал" % nick, HUDPalette.LOG_LOOT)

func _on_player_healed(peer_id: int, amount: float) -> void:
	if amount < 1.0:
		return
	var nick := _resolve_nick(peer_id)
	_push_log("%s получил +%d хп" % [nick, int(round(amount))], HUDPalette.LOG_LOOT)

func _on_upgrade_picked(peer_id: int, upgrade_id: StringName) -> void:
	var nick := _resolve_nick(peer_id)
	var label := String(upgrade_id)
	var def := Defs.upgrade_def(upgrade_id)
	if def != null and def.label != "":
		label = def.label
	_push_log("%s взял %s" % [nick, label], HUDPalette.LOG_WARN)

func _on_level_up(new_level: int) -> void:
	_push_log("Пати: уровень %d" % new_level, HUDPalette.LOG_KILL)

func _resolve_nick(peer_id: int) -> String:
	for plr in get_tree().get_nodes_in_group("players"):
		if int(plr.peer_id) == peer_id:
			return String(plr.nick)
	if peer_id == _local_peer_id() and _local_player != null and is_instance_valid(_local_player):
		return String(_local_player.nick)
	return "P%d" % peer_id

# =========================================================================
# Helpers
# =========================================================================

func _find_local_player() -> void:
	if _local_player != null and is_instance_valid(_local_player):
		return
	var my_id := _local_peer_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == my_id:
			_local_player = p
			return

func _local_peer_id() -> int:
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return 1
