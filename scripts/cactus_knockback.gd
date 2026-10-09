extends Area3D
@onready var feedback_sound: AudioStreamPlayer3D = $"../feedbackSound"
@onready var feedback_visual: GPUParticles3D = $"../feedbackVisual"
@export var knockback_force: float = 25.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	feedback_sound.play()
	feedback_visual.restart()
	feedback_visual.emitting = true
	var ragdoll = body.get_node_or_null("bunnyanim/Armature/Skeleton3D/Ragdoll") 
	if ragdoll: 
		ragdoll.toggle_ragdoll() 
		# Direction away from the PushZone 
		var direction = (body.global_position - global_position).normalized() 
		# Wait for the ragdoll physics to start 
		await get_tree().create_timer(0.1).timeout 
		ragdoll.apply_knockback(direction, knockback_force)


func _on_body_exited(body: Node3D) -> void:
	feedback_sound.stop()
