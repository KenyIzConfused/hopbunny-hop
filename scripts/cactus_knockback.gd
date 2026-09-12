extends Area3D
@onready var feedback_sound: AudioStreamPlayer3D = $"../feedbackSound"
@onready var feedback_visual: GPUParticles3D = $"../feedbackVisual"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
