class_name WaveSet extends Resource

# Top-level run definition: ordered phases + finale boss.

@export var phases: Array[WavePhase] = []
@export var run_duration: float = 600.0
@export var boss_id: StringName = &"boss"
@export var spawn_radius_min: float = 700.0
@export var spawn_radius_max: float = 900.0

func phase_for(t: float) -> WavePhase:
	var chosen: WavePhase = null
	for p in phases:
		if p == null:
			continue
		if t >= p.from_time:
			chosen = p
		else:
			break
	return chosen
