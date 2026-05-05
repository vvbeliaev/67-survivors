class_name WavePhase extends Resource

# Time-banded spawn rules. WaveDirector picks the latest phase whose
# `from_time` is <= run_time.

@export var from_time: float = 0.0
@export var spawn_interval: float = 2.5
@export var batch_size: int = 2
@export var enemy_types: Array[StringName] = [&"rusher"]

@export_group("Burst")
@export var burst_enabled: bool = false
@export var burst_interval: float = 60.0
@export var burst_size: int = 10
