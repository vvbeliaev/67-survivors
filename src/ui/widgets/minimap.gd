class_name MinimapWidget extends Control

# Schematic top-down view of the arena: a fixed-size window centered on the
# camera centroid. Players + enemies + boss markers are projected from
# world space to map space using a fixed scale.

const MAP_W := 220
const MAP_H := 160
const WORLD_RADIUS := 1100.0   # world span shown in the minimap
const FOOTER_H := 18

var sector_label: String = "СЕКТОР III"
var subzone_label: String = "ЛОГОВО"

var label_font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MAP_W + 16, MAP_H + FOOTER_H + 16)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)

	# Outer panel chrome.
	_draw_panel(r)

	# Map area.
	var map_rect := Rect2(r.position + Vector2(8, 8), Vector2(MAP_W, MAP_H))
	draw_rect(map_rect, Color(0.039, 0.024, 0.016, 1.0), true)
	draw_rect(map_rect, HUDPalette.STROKE, false, 1.0)

	# Fog of war — radial gradient lighting up the explored area near centroid.
	_draw_fog(map_rect)

	# Centroid + spread.
	var centroid := _compute_centroid()
	# Project func.
	var to_map = func (world: Vector2) -> Vector2:
		var rel := world - centroid
		var nx := clampf(rel.x / WORLD_RADIUS, -1.0, 1.0)
		var ny := clampf(rel.y / WORLD_RADIUS, -1.0, 1.0)
		return map_rect.position + Vector2(map_rect.size.x * 0.5, map_rect.size.y * 0.5) + Vector2(nx, ny) * Vector2(map_rect.size.x * 0.45, map_rect.size.y * 0.45)

	# Enemies.
	var local_id := _local_peer_id()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if not bool(e.get("alive")):
			continue
		var p: Vector2 = to_map.call(e.global_position)
		var is_boss: bool = bool(e.get("boss_aoe")) or String(e.get("enemy_type")) == "boss"
		if is_boss:
			# Diamond marker.
			_draw_diamond(p, 4.0, HUDPalette.DANGER)
		else:
			draw_circle(p, 2.0, HUDPalette.DANGER)
			draw_arc(p, 2.0, 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)

	# Players.
	for plr in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(plr):
			continue
		var p: Vector2 = to_map.call(plr.global_position)
		var is_me: bool = int(plr.get("peer_id")) == local_id
		if not bool(plr.get("alive")):
			# Faded gray cross.
			var col := Color(0.6, 0.6, 0.6, 0.5)
			draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), col, 1.5)
			draw_line(p + Vector2(-3, 3), p + Vector2(3, -3), col, 1.5)
			continue
		var fill := HUDPalette.ACCENT if is_me else Color(0.502, 0.753, 0.376, 1.0)
		var rad := 3.0 if is_me else 2.5
		draw_circle(p, rad + 0.8, Color(0, 0, 0, 1))
		draw_circle(p, rad, fill)

	# Footer labels.
	if label_font != null:
		var fs := 10
		var lpos := Vector2(r.position.x + 8, r.position.y + 8 + MAP_H + 14)
		var rs_size := label_font.get_string_size(subzone_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var rpos := Vector2(r.position.x + 8 + MAP_W - rs_size.x, lpos.y)
		draw_string(label_font, lpos, sector_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUDPalette.INK_MUTE)
		draw_string(label_font, rpos, subzone_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUDPalette.INK_MUTE)

func _draw_panel(r: Rect2) -> void:
	var n := 6
	var h := r.size.y / float(n)
	for i in n:
		var t := float(i) / float(n - 1)
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h + 1)), HUDPalette.PANEL.lerp(HUDPalette.PANEL_SOFT, t), true)
	draw_rect(r.grow(-1), HUDPalette.SHADOW_LIGHT, false, 1.0)
	draw_rect(r, HUDPalette.STROKE_STRONG, false, 1.0)

func _draw_fog(map_rect: Rect2) -> void:
	# Cheap radial fog: concentric translucent rings darkening toward the edges.
	var cx := map_rect.position.x + map_rect.size.x * 0.5
	var cy := map_rect.position.y + map_rect.size.y * 0.55
	var max_r := map_rect.size.length() * 0.5
	# Top dark cap.
	draw_rect(map_rect, Color(0, 0, 0, 0.55), true)
	# Bright lit area.
	var n := 6
	for i in range(n, 0, -1):
		var rad := max_r * float(i) / float(n)
		var a := lerpf(0.30, 0.0, float(i) / float(n))
		draw_circle(Vector2(cx, cy), rad, Color(0.706, 0.549, 0.314, a))

func _draw_diamond(c: Vector2, half: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -half),
		c + Vector2(half, 0),
		c + Vector2(0, half),
		c + Vector2(-half, 0),
	])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.85), 1.0)

func _compute_centroid() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for plr in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(plr):
			continue
		if not bool(plr.get("alive")):
			continue
		sum += plr.global_position
		count += 1
	if count == 0:
		# Fallback: any player.
		for plr in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(plr):
				sum += plr.global_position
				count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)

func _local_peer_id() -> int:
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return 1
