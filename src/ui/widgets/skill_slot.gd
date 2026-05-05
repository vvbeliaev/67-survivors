class_name SkillSlot extends Control

# Skill bar slot: square frame, glyph in the middle, key label in the corner,
# optional cooldown sweep and remaining-seconds label. The slot doesn't
# observe a Skill — the HUD owns state and pushes via `set_state()`.

@export var key_label: String = ""
@export var glyph: String = "•"           # textual icon (we have no skill icons)
@export var glyph_color: Color = HUDPalette.ACCENT
@export var cd_pct: float = 0.0           # 0.0 .. 1.0
@export var cd_seconds: float = 0.0
@export var hot: bool = false             # signature/highlighted skill
@export var disabled: bool = false        # grey out (insufficient mana, etc.)

var key_font: Font = null
var glyph_font: Font = null
var cd_font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(76, 76)

func set_state(p_cd_pct: float, p_cd_seconds: float, p_disabled: bool) -> void:
	cd_pct = p_cd_pct
	cd_seconds = p_cd_seconds
	disabled = p_disabled
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0 or r.size.y <= 0:
		return

	# Background.
	var bg_top := Color(0.110, 0.078, 0.055, 1.0)
	var bg_bot := Color(0.067, 0.051, 0.039, 1.0)
	var n := 6
	var h := r.size.y / float(n)
	for i in n:
		var t := float(i) / float(n - 1)
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h + 1)), bg_top.lerp(bg_bot, t), true)

	# Inner inset shadow.
	draw_rect(r.grow(-1), HUDPalette.SHADOW, false, 1.0)

	# Outer border — accent if hot, stroke otherwise.
	var bc := HUDPalette.ACCENT if hot else HUDPalette.STROKE_STRONG
	draw_rect(r, bc, false, 1.0)
	if hot:
		# Inner accent ring.
		draw_rect(r.grow(-2), HUDPalette.ACCENT_DEEP, false, 1.0)

	# Glyph.
	if glyph_font != null and glyph != "":
		var gfs := 36
		var col := glyph_color
		if disabled:
			col = HUDPalette.INK_MUTE
		var ts := glyph_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, gfs)
		var pos := Vector2(
			r.position.x + (r.size.x - ts.x) * 0.5,
			r.position.y + (r.size.y + ts.y) * 0.5 - 6.0
		)
		# Shadow.
		draw_string(glyph_font, pos + Vector2(1, 2), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, Color(0, 0, 0, 0.85))
		draw_string(glyph_font, pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, col)

	# Cooldown overlay (vignette + remaining seconds).
	if cd_pct > 0.0:
		var bands := 24
		var rem := clampf(cd_pct, 0.0, 1.0)
		var blocked := int(float(bands) * rem)
		# Top→bottom curtain. Cheap fake of a conic-gradient sweep.
		var bh := r.size.y / float(bands)
		for i in blocked:
			draw_rect(Rect2(r.position + Vector2(0, i * bh), Vector2(r.size.x, bh + 1)), Color(0, 0, 0, 0.62), true)
		# Number.
		if cd_font != null and cd_seconds > 0.05:
			var s := "%.1f" % cd_seconds if cd_seconds < 10.0 else str(int(ceil(cd_seconds)))
			var fs := 22
			var ts2 := cd_font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var pos2 := Vector2(
				r.position.x + (r.size.x - ts2.x) * 0.5,
				r.position.y + (r.size.y + ts2.y) * 0.5 - 4.0
			)
			for dx in [-1, 1]:
				for dy in [-1, 1]:
					draw_string(cd_font, pos2 + Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.95))
			draw_string(cd_font, pos2, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUDPalette.INK)

	# Key chip.
	if key_font != null and key_label != "":
		var kfs := 10
		var ts := key_font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs)
		var chip_w := ts.x + 8
		var chip_h := ts.y + 4
		var chip_pos := Vector2(r.position.x + r.size.x - chip_w - 2, r.position.y + r.size.y - chip_h - 2)
		var chip_rect := Rect2(chip_pos, Vector2(chip_w, chip_h))
		draw_rect(chip_rect, Color(0, 0, 0, 0.7), true)
		draw_rect(chip_rect, HUDPalette.STROKE_STRONG, false, 1.0)
		draw_string(key_font, chip_pos + Vector2(4, ts.y + 1), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs, HUDPalette.ACCENT)
