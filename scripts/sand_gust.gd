extends Node3D
class_name SandGust

signal deactivated

@onready var fog_volume: FogVolume = $FogVolume
@onready var particles: GPUParticles3D = $GPUParticles3D

var lifetime: float = 0.0
var max_lifetime: float = 8.0
var speed: float = 6.0
var wind_dir: Vector3 = Vector3(1.0, 0.0, 0.3)
var active: bool = false

func _ready() -> void:
	if not fog_volume:
		_create_gust_nodes()

func _create_gust_nodes() -> void:
	var fog_mat: FogMaterial = FogMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = preload("res://Maps/Dunes/dune_gust_fog.gdshader").code
	fog_mat.shader = shader
	fog_mat.set_shader_parameter("noise_scale", 0.15)
	fog_mat.set_shader_parameter("detail_scale", 0.4)
	fog_mat.set_shader_parameter("density", 2.5)
	fog_mat.set_shader_parameter("sand_color", Vector3(0.85, 0.65, 0.35))
	
	fog_volume = FogVolume.new()
	fog_volume.size = Vector3(8, 4, 12)
	fog_volume.material = fog_mat
	add_child(fog_volume)
	
	var particle_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(1, 0, 0.3)
	particle_mat.spread = 15.0
	particle_mat.initial_velocity_min = 3.0
	particle_mat.initial_velocity_max = 8.0
	particle_mat.gravity = Vector3(0, -2.0, 0)
	particle_mat.scale_min = 0.5
	particle_mat.scale_max = 1.5
	
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.35, 0.6)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	
	particles = GPUParticles3D.new()
	particles.amount = 200
	particles.explosiveness = 0.2
	particles.randomness = 0.5
	particles.process_material = particle_mat
	particles.draw_pass_1 = quad
	add_child(particles)
	
	visible = false
	fog_volume.visible = false
	particles.visible = false
	particles.emitting = false

func activate(dir: Vector3, spd: float, life: float) -> void:
	wind_dir = dir.normalized()
	speed = spd
	max_lifetime = life
	lifetime = 0.0
	active = true
	visible = true
	if fog_volume:
		fog_volume.visible = true
	if particles:
		particles.visible = true
		particles.emitting = true

func deactivate() -> void:
	active = false
	if particles:
		particles.emitting = false
	visible = false
	if fog_volume:
		fog_volume.visible = false
	if particles:
		particles.visible = false
	deactivated.emit()

func _process(delta: float) -> void:
	if not active:
		return
	
	lifetime += delta
	if lifetime >= max_lifetime:
		deactivate()
		return
	
	position += wind_dir * speed * delta
