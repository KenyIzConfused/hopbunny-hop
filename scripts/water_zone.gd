extends Area3D
class_name WaterZone

@export var tint_color: Color = Color(0.15, 0.45, 0.75, 0.35)
@export var fov_underwater: float = 70.0
@export var transition_speed: float = 4.0
## Movement speed multiplier for characters in this zone.
@export_range(0.0, 1.0, 0.05) var player_speed_multiplier: float = 0.2
@export var debug_logs: bool = true

var _overlay: ColorRect
var _canvas: CanvasLayer
var _camera: Camera3D
var _original_fov: float = -1.0
var _in_water: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if debug_logs:
		print("[WaterZone] Ready on ", name, " | monitoring=", monitoring)
	call_deferred("_create_overlay")

func _create_overlay() -> void:
	if _overlay:
		return
	_canvas = CanvasLayer.new()
	_canvas.name = "WaterCanvas"
	_canvas.layer = 100
	get_tree().root.add_child(_canvas)

	_overlay = ColorRect.new()
	_overlay.name = "WaterTint"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.0)
	_canvas.add_child(_overlay)
	if debug_logs:
		print("[WaterZone] Created overlay")

func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var cam = _find_camera(child)
		if cam:
			return cam
	return null

func _on_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if body.has_method('set_water_slowdown'):
		body.call('set_water_slowdown', true, player_speed_multiplier)
	if not _camera:
		_camera = _find_camera(body)
		if _camera:
			_original_fov = _camera.fov
	_in_water = true
	if debug_logs:
		print("[WaterZone] Enter: ", body.name)

func _on_body_exited(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if body.has_method('set_water_slowdown'):
		body.call('set_water_slowdown', false)
	_in_water = false
	if debug_logs:
		print("[WaterZone] Exit: ", body.name)

func _process(_delta: float) -> void:
	if not _overlay or not _camera or _original_fov < 0:
		return
	var target_alpha := tint_color.a if _in_water else 0.0
	var target_fov := fov_underwater if _in_water else _original_fov
	_overlay.color.a = move_toward(_overlay.color.a, target_alpha, _delta * transition_speed)
	_camera.fov = move_toward(_camera.fov, target_fov, _delta * transition_speed)

func _exit_tree() -> void:
	if _canvas:
		_canvas.queue_free()
