extends CharacterBody3D

@onready var physical_bone_simulator_3d: PhysicalBoneSimulator3D = $bunnyanim/Armature/Skeleton3D/PhysicalBoneSimulator3D
@onready var animation_player: AnimationPlayer = $bunnyanim/AnimationPlayer
@onready var timer_label: Label = $Control/VBoxContainer/timerLabel
@onready var score_label: Label = $Control/VBoxContainer/scoreLabel

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false
## Can we press to toggle ragdoll?
@export var can_ragdoll : bool = true

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 20.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0
## Movement speed multiplier while in water.
@export_range(0.0, 1.0, 0.05) var water_speed_multiplier : float = 0.5

var elapsed_time: float = 0.0
var score: int = 0

var score_timer: float = 0.0
var score_requirement: int = 15
var score_interval: float = 10.0
var score_at_interval_start: int = 0

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "left"
## Name of Input Action to move Right.
@export var input_right : String = "right"
## Name of Input Action to move Forward.
@export var input_forward : String = "up"
## Name of Input Action to move Backward.
@export var input_back : String = "down"
## Name of Input Action to Jump.
@export var input_jump : String = "accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"
## Name of Input Action to toggle ragdoll mode.
@export var input_ragdoll : String = "ragdoll"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false
var in_water : bool = false

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
#@onready var collider: CollisionShape3D = $Collider
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var ragdoll: Ragdoll = $bunnyanim/Armature/Skeleton3D/Ragdoll


func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x

func _unhandled_input(event: InputEvent) -> void:
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()
	
	# Toggle ragdoll mode
	if can_ragdoll and Input.is_action_just_pressed(input_ragdoll):
		ragdoll.toggle_ragdoll()
	
func add_score(points: int) -> void:
	score += points
	score_label.text = "Score: %d" % score

func _physics_process(delta: float) -> void:

	# =========================
	# GAME TIMER
	# =========================
	elapsed_time += delta

	var minutes: int = int(elapsed_time) / 60
	var seconds: int = int(elapsed_time) % 60

	timer_label.text = "Time: %02d:%02d" % [minutes, seconds]


	# =========================
	# SCORE TIMER
	# =========================
	score_timer += delta

	score_label.text = "Score: %d" % score

	if score_timer >= score_interval:
		score_timer -= score_interval

		var points_earned: int = score - score_at_interval_start

		if points_earned >= score_requirement:
			print("Requirement met! +%d points" % points_earned)
		else:
			print("Requirement failed! Only earned %d/%d" % [
				points_earned,
				score_requirement
			])

		score_at_interval_start = score
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		return
	
	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
			velocity.y = jump_velocity
			add_score(15)

	# Modify speed based on sprinting and water
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed
	if in_water:
		move_speed *= water_speed_multiplier

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if input_dir.length() > 0:
			if animation_player.current_animation != "ArmatureAction_001":
				animation_player.play("ArmatureAction_001")
		else:
			if animation_player.current_animation != "ArmatureAction":
				animation_player.play("ArmatureAction")
		
		
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0
	
	# Use velocity to actually move
	move_and_slide()


## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly():
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly():
	collider.disabled = false
	freeflying = false


func set_water_slowdown(enabled: bool, multiplier: float = 1.0) -> void:
	in_water = enabled
	water_speed_multiplier = multiplier if enabled else 1.0


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false
	if can_ragdoll and not InputMap.has_action(input_ragdoll):
		push_error("Ragdoll disabled. No InputAction found for input_ragdoll: " + input_ragdoll)
		can_ragdoll = false
