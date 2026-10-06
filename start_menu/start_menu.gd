extends Control

## Emitted when the player confirms the currently shown map (clicks the middle button).
signal map_confirmed(map_name: String)
## Emitted whenever the arrows change the shown map.
signal map_changed(map_name: String)
## Emitted when the Menu button (top right) is pressed. Hook your menu scene here later.
signal menu_requested

const MAPS: Array[String] = ["Desert", "Forest", "Tundra"]

var _index := 0

@onready var _map_btn: Button = $MapSelector/MapBtn
@onready var _prev_btn: Button = $MapSelector/PrevBtn
@onready var _next_btn: Button = $MapSelector/NextBtn
@onready var _menu_btn: Button = $MenuBtn


func _ready() -> void:
	_prev_btn.pressed.connect(_on_prev_pressed)
	_next_btn.pressed.connect(_on_next_pressed)
	_map_btn.pressed.connect(_on_map_pressed)
	_menu_btn.pressed.connect(_on_menu_pressed)
	_refresh()


func _on_prev_pressed() -> void:
	_index = wrapi(_index - 1, 0, MAPS.size())
	_refresh()
	map_changed.emit(MAPS[_index])


func _on_next_pressed() -> void:
	_index = wrapi(_index + 1, 0, MAPS.size())
	_refresh()
	map_changed.emit(MAPS[_index])


func _on_map_pressed() -> void:
	# TODO: change to your map scenes, e.g. get_tree().change_scene_to_file("res://maps/desert.tscn")
	map_confirmed.emit(MAPS[_index])
	print("Selected map: ", MAPS[_index])


func _on_menu_pressed() -> void:
	# TODO: open your menu scene here later.
	menu_requested.emit()
	print("Menu pressed")


func _refresh() -> void:
	_map_btn.text = MAPS[_index]
