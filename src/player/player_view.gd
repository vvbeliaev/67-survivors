extends Node2D

# Pure presentation node. Reads state from its parent Player (replicated) and
# draws body, aim pip, HP/MP bars, down halo, and crossbow charge bar. Logic
# stays in Player.

@export var owner_path: NodePath = NodePath("..")

var _player: Node = null

func _ready() -> void:
	_player = get_node(owner_path)
	z_index = 1

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var col: Color = _player.color_hint
	if not _player.alive:
		col = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.6)
	draw_circle(Vector2.ZERO, _player.radius, col)
	draw_line(Vector2.ZERO, _player.aim_dir * (_player.radius + 6), Color(1, 1, 1, 0.7), 2.0)

	# HP bar.
	var w := 40.0
	var h := 4.0
	var top := Vector2(-w * 0.5, -_player.radius - 14)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0.1, 0.1, 0.1))
	var ratio: float = clampf(_player.hp / max(_player.max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(top, Vector2(w * ratio, h)), Color(0.3, 0.95, 0.3))

	# MP bar (if class has mana).
	if _player.max_mp > 0.0:
		var top2 := Vector2(-w * 0.5, -_player.radius - 8)
		draw_rect(Rect2(top2, Vector2(w, h)), Color(0.1, 0.1, 0.15))
		var r2: float = clampf(_player.mp / _player.max_mp, 0.0, 1.0)
		draw_rect(Rect2(top2, Vector2(w * r2, h)), Color(0.3, 0.5, 0.95))

	if not _player.alive:
		draw_arc(Vector2.ZERO, _player.radius + 6, 0, TAU, 32, Color(1, 0.4, 0.4, 0.6), 2.0)

	# Crossbow charge bar (driven by `charge_started_at` which is replicated).
	if _player.charge_started_at >= 0.0:
		var ct: float = clampf((Time.get_ticks_msec() / 1000.0) - _player.charge_started_at, 0.0, 1.5) / 1.5
		var top3 := Vector2(-w * 0.5, _player.radius + 4)
		draw_rect(Rect2(top3, Vector2(w, h)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(top3, Vector2(w * ct, h)), Color(1.0, 0.85, 0.3))
