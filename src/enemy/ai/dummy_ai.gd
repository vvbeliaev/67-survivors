extends EnemyAI

# Training dummy: stationary punching bag for the debug panel. Doesn't move,
# doesn't pick targets, doesn't attack. Massive HP so any skill rotation can
# be ground out against it without one-shotting. Not referenced by any wave
# phase — only spawnable via the debug panel.

func tick(_delta: float) -> void:
	owner_enemy.velocity = Vector2.ZERO
