extends Node2D

# Tiled floor background. The texture (1254² seamless dungeon stone) is drawn
# inside a huge centered rect with texture_repeat enabled; CanvasModulate
# darkens it, torches and player lights brighten it back up.

const TILE_TEX: Texture2D = preload("res://assets/images/floor_tile.png")
const HALF_EXTENT := 6000.0
const TILE_SCALE := 0.6  # render the 1254² tile a bit smaller so detail reads

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	z_index = -10

func _draw() -> void:
	# Source rect spans many tile lengths so draw_texture_rect_region tiles
	# without needing a Sprite2D / region. Scaled via the destination rect.
	var src_size: Vector2 = TILE_TEX.get_size()
	var dest := Rect2(Vector2(-HALF_EXTENT, -HALF_EXTENT), Vector2(HALF_EXTENT * 2, HALF_EXTENT * 2))
	var tiles_x: float = (HALF_EXTENT * 2) / (src_size.x * TILE_SCALE)
	var tiles_y: float = (HALF_EXTENT * 2) / (src_size.y * TILE_SCALE)
	var src := Rect2(Vector2.ZERO, Vector2(src_size.x * tiles_x, src_size.y * tiles_y))
	draw_texture_rect_region(TILE_TEX, dest, src)
