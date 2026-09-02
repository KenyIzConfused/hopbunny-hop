extends Node3D
class_name Ragdoll

@onready var skeleton: Skeleton3D = get_parent()
@onready var player: CharacterBody3D = skeleton.get_parent().get_parent().get_parent()

var physical_bones: Dictionary = {}
var joints: Array = []
var is_ragdoll: bool = false

const BONE_MAP := {
	"head": "Bone.026",
	"jaw": "Bone.027",
	"left_ear": "Bone.028",
	"right_ear": "Bone.029",
	"spine_1": "Bone",
	"spine_2": "Bone.001",
	"spine_3": "Bone.003",
	"spine_4": "Bone.004",
	"front_left_upper": "Bone.005",
	"front_left_lower": "Bone.006",
	"front_right_upper": "Bone.007",
	"front_right_lower": "Bone.008",
	"back_left_upper": "Bone.021",
	"back_right_upper": "Bone.022",
}

const BONE_JOINTS := {
	"Bone": ["Bone.001"],
	"Bone.001": ["Bone.003", "Bone.026"],
	"Bone.003": ["Bone.004"],
	"Bone.004": ["Bone.005", "Bone.007", "Bone.021", "Bone.022"],
	"Bone.005": ["Bone.006"],
	"Bone.006": [],
	"Bone.007": ["Bone.008"],
	"Bone.008": [],
	"Bone.021": [],
	"Bone.022": [],
	"Bone.026": ["Bone.027"],
	"Bone.027": [],
}

func _ready() -> void:
	call_deferred("setup_ragdoll")

func setup_ragdoll() -> void:
	for bone_name in BONE_MAP.values():
		if skeleton.find_bone(bone_name) < 0:
			push_warning("Bone not found: " + bone_name)
			continue
		
		var pb := PhysicalBone3D.new()
		pb.bone_name = bone_name
		pb.name = bone_name
		pb.mass = 1.0
		pb.friction = 0.5
		pb.bounce = 0.1
		pb.gravity_scale = 1.0
		pb.linear_damp = 0.1
		pb.angular_damp = 0.5
		pb.collision_layer = 2
		pb.collision_mask = 253
		
		skeleton.add_child(pb)
		physical_bones[bone_name] = pb
		
		var shape := CapsuleShape3D.new()
		shape.radius = 0.08
		shape.height = 0.2
		
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, -0.1, 0)
		pb.add_child(cs)
		
		match bone_name:
			"Bone.026", "Bone.027":
				shape.radius = 0.12
				shape.height = 0.15
				cs.position = Vector3(0, 0, 0)
				pb.mass = 0.5
			"Bone.005", "Bone.007", "Bone.021", "Bone.022":
				shape.radius = 0.06
				shape.height = 0.25
				cs.position = Vector3(0, -0.12, 0)
				pb.mass = 1.5
			"Bone.006", "Bone.008":
				shape.radius = 0.05
				shape.height = 0.2
				cs.position = Vector3(0, -0.1, 0)
				pb.mass = 0.8
	
	for parent_bone in BONE_JOINTS:
		if not physical_bones.has(parent_bone):
			continue
		for child_bone in BONE_JOINTS[parent_bone]:
			if not physical_bones.has(child_bone):
				continue
			create_joint(parent_bone, child_bone)
	
	skeleton.animate_physical_bones = true

func create_joint(parent_bone: String, child_bone: String) -> void:
	var parent_pb: PhysicalBone3D = physical_bones[parent_bone]
	var child_pb: PhysicalBone3D = physical_bones[child_bone]
	
	var joint := HingeJoint3D.new()
	joint.node_a = NodePath(parent_pb.name)
	joint.node_b = NodePath(child_pb.name)
	
	skeleton.add_child(joint)
	joints.append(joint)

func enable_ragdoll() -> void:
	if is_ragdoll:
		return
	is_ragdoll = true
	skeleton.animate_physical_bones = false
	player.can_move = false
	player.can_jump = false

func disable_ragdoll() -> void:
	if not is_ragdoll:
		return
	is_ragdoll = false
	skeleton.animate_physical_bones = true
	player.can_move = true
	player.can_jump = true

func toggle_ragdoll() -> void:
	if is_ragdoll:
		disable_ragdoll()
	else:
		enable_ragdoll()
