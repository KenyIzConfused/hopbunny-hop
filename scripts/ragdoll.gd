extends Node3D
class_name Ragdoll

@onready var skeleton: Skeleton3D = get_parent()
@onready var player: CharacterBody3D = skeleton.get_parent().get_parent().get_parent()
@export var head: Node3D

var is_ragdoll: bool = false
var animation_player: AnimationPlayer = null
var _original_head_transform: Transform3D
var _recovery_transform: Transform3D

@export var ragdoll_score_penalty: int = 25

func _ready() -> void:
	animation_player = _find_animation_player()
	if not animation_player:
		push_warning("Ragdoll: AnimationPlayer not found in scene tree")
	
	if not head:
		head = player.get_node_or_null("Head")
		if not head:
			push_warning("Ragdoll: Head node not found")

func _process(delta: float) -> void:
	if is_ragdoll and head:
		_update_head_follow()

func _update_head_follow() -> void:
	var head_bone = skeleton.get_node_or_null("PhysicalBoneSimulator3D/headBone")
	if head_bone:
		head.global_transform = head_bone.global_transform

func _find_animation_player() -> AnimationPlayer:
	var current = get_parent()
	while current:
		var ap = current.get_node_or_null("AnimationPlayer")
		if ap:
			return ap
		current = current.get_parent()
	return null

func _get_physical_bone_simulator() -> PhysicalBoneSimulator3D:
	return skeleton.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D

func enable_ragdoll() -> void:
	if is_ragdoll:
		return
	is_ragdoll = true
	
	player.add_score(-ragdoll_score_penalty)
	
	if animation_player:
		animation_player.stop()

	player.velocity = Vector3.ZERO
	player.can_move = false
	player.can_jump = false

	if head:
		_original_head_transform = head.transform

	var simulator = _get_physical_bone_simulator()
	if simulator:
		simulator.physical_bones_stop_simulation()
		await get_tree().create_timer(0.05).timeout
		for bone in simulator.get_children():
			if bone is PhysicalBone3D:
				bone.linear_velocity = Vector3.ZERO
				bone.angular_velocity = Vector3.ZERO
		simulator.physical_bones_start_simulation()

func disable_ragdoll() -> void:
	if not is_ragdoll:
		return
	is_ragdoll = false

	var head_bone = skeleton.get_node_or_null("PhysicalBoneSimulator3D/headBone") as Node3D
	if head_bone:
		_recovery_transform = head_bone.global_transform

	var simulator = _get_physical_bone_simulator()
	if simulator:
		simulator.physical_bones_stop_simulation()

	if animation_player:
		animation_player.play("ArmatureAction", -1.0, 1.0, true)

	if head and _original_head_transform:
		head.transform = _original_head_transform

	if _recovery_transform:
		player.global_transform = _recovery_transform
		player.velocity = Vector3.ZERO

	player.can_move = true
	player.can_jump = true

func toggle_ragdoll() -> void:
	if is_ragdoll:
		disable_ragdoll()
	else:
		enable_ragdoll()


func apply_knockback(direction: Vector3, force: float) -> void:
	var simulator = _get_physical_bone_simulator()

	if not simulator:
		return

	for bone in simulator.get_children():
		if bone is PhysicalBone3D:
			bone.apply_central_impulse(direction * force)
