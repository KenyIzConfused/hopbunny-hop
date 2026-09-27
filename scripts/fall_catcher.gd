extends Area3D

## Respawns anything that falls out of the world (e.g. through a terrain gap).
@export var respawn_position: Vector3 = Vector3(5.35, -13.5, -0.04)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.velocity = Vector3.ZERO
		body.global_position = respawn_position
