extends Control
## Screen-centre target cursor used while holding the aim button.
##
## Created and driven by hop_controller.gd - you normally never touch this.
## Idle: a tiny dot. Aiming: a ring that closes in on the centre, with four
## rotating ticks. Colour tells you whether the hop is possible.

enum Status { NONE, VALID, CLAMPED, INVALID }

const COL_NONE := Color(0.85, 0.85, 0.85)
const COL_VALID := Color(0.45, 1.0, 0.55)
const COL_CLAMPED := Color(1.0, 0.85, 0.3)
const COL_INVALID := Color(1.0, 0.35, 0.35)

@export var ring_radius := 20.0
@export var open_radius := 46.0
@export var line_width := 2.5
@export var idle_dot := true

var _active := false
var _status: int = Status.NONE
var _open := 0.0 # 0 = idle, 1 = fully in aim mode
var _spin := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_aim(active: bool, status: int) -> void:
	_active = active
	_status = status


func status_color(status: int) -> Color:
	match status:
		Status.VALID:
			return COL_VALID
		Status.CLAMPED:
			return COL_CLAMPED
		Status.INVALID:
			return COL_INVALID
	return COL_NONE


func _process(delta: float) -> void:
	_open = move_toward(_open, 1.0 if _active else 0.0, delta * 9.0)
	_spin += delta * (1.4 if _status == Status.VALID else 0.4)
	queue_redraw()


func _draw() -> void:
	var c := get_viewport_rect().size * 0.5

	if idle_dot:
		var a := 1.0 - _open
		if a > 0.01:
			draw_circle(c, 3.5, Color(0, 0, 0, 0.45 * a))
			draw_circle(c, 2.0, Color(1, 1, 1, 0.8 * a))

	if _open <= 0.01:
		return

	var col := status_color(_status)
	col.a = _open
	var shadow := Color(0, 0, 0, 0.5 * _open)
	var r := lerpf(open_radius, ring_radius, ease(_open, 0.35))

	draw_arc(c, r, 0.0, TAU, 48, shadow, line_width + 2.0, true)
	draw_arc(c, r, 0.0, TAU, 48, col, line_width, true)
	for i in 4:
		var d := Vector2.from_angle(_spin + i * TAU / 4.0)
		draw_line(c + d * (r + 3.0), c + d * (r + 12.0), shadow, line_width + 2.0)
		draw_line(c + d * (r + 3.0), c + d * (r + 12.0), col, line_width)
	draw_circle(c, 3.5, shadow)
	draw_circle(c, 2.5, col)
