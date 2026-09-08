extends Node3D
class_name SandGustManager

@export var spawn_interval_min: float = 3.0
@export var spawn_interval_max: float = 8.0
@export var gust_speed_min: float = 5.0
@export var gust_speed_max: float = 12.0
@export var gust_lifetime_min: float = 6.0
@export var gust_lifetime_max: float = 12.0
@export var spawn_radius: float = 40.0
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.3)
@export var gust_count: int = 5

@onready var spawn_timer: Timer = $SpawnTimer

var gusts: Array[SandGust] = []
var available: Array[SandGust] = []

func _ready() -> void:
	spawn_timer.timeout.connect(_on_spawn_timer)
	_prepare_gusts()

func _prepare_gusts() -> void:
	for i in range(gust_count):
		var gust: SandGust = SandGust.new()
		gust.name = "Gust_%d" % i
		add_child(gust)
		gusts.append(gust)
		available.append(gust)
		gust.deactivated.connect(_on_gust_deactivated.bind(gust))

func _on_spawn_timer() -> void:
	_spawn_gust()
	spawn_timer.wait_time = randf_range(spawn_interval_min, spawn_interval_max)
	spawn_timer.start()

func _spawn_gust() -> void:
	if available.is_empty():
		return
	
	var gust: SandGust = available.pop_front()
	
	var offset: Vector3 = Vector3(
		randf_range(-spawn_radius, spawn_radius),
		randf_range(0.5, 3.0),
		randf_range(-spawn_radius, spawn_radius)
	)
	
	gust.global_position = global_position + offset
	gust.activate(wind_direction, randf_range(gust_speed_min, gust_speed_max), randf_range(gust_lifetime_min, gust_lifetime_max))

func _on_gust_deactivated(gust: SandGust) -> void:
	if gust in available:
		return
	available.append(gust)

func start() -> void:
	spawn_timer.wait_time = randf_range(spawn_interval_min, spawn_interval_max)
	spawn_timer.start()

func stop() -> void:
	spawn_timer.stop()
	for gust in gusts:
		gust.deactivate()
