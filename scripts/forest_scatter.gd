@tool
extends Node3D
## Procedurally scatters a low-poly pine/round-canopy forest using
## MultiMeshInstance3D (cheap to render, thousands of instances for free).
## Regenerates automatically in the editor when parameters change.

@export var tree_count: int = 160
@export var area_size: Vector2 = Vector2(126, 116)
@export var clearing_radius: float = 16.0
@export var rng_seed: int = 1337
@export var pine_ratio: float = 0.55
@export var rock_count: int = 40

@export var regenerate: bool = false:
	set(v):
		if v:
			_generate()

func _ready() -> void:
	_generate()

func _generate() -> void:
	for child in get_children():
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var trunk_xforms: Array[Transform3D] = []
	var pine_xforms: Array[Transform3D] = []
	var pine_colors: Array[Color] = []
	var round_xforms: Array[Transform3D] = []
	var round_colors: Array[Color] = []

	var placed := 0
	var attempts := 0
	while placed < tree_count and attempts < tree_count * 6:
		attempts += 1
		var x := rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z := rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		if Vector2(x, z).length() < clearing_radius:
			continue

		var trunk_height := rng.randf_range(3.2, 6.0)
		var trunk_radius := rng.randf_range(0.28, 0.45)
		var yaw := rng.randf_range(0, TAU)
		var lean_x := rng.randf_range(-0.03, 0.03)
		var lean_z := rng.randf_range(-0.03, 0.03)

		var trunk_basis := Basis.from_euler(Vector3(lean_x, yaw, lean_z))
		var trunk_scale := Basis().scaled(Vector3(trunk_radius, trunk_height, trunk_radius))
		trunk_xforms.append(Transform3D(trunk_basis * trunk_scale, Vector3(x, trunk_height * 0.5, z)))

		var is_pine := rng.randf() < pine_ratio
		var green_shift := rng.randf_range(-0.08, 0.08)

		if is_pine:
			var canopy_radius := rng.randf_range(1.6, 2.6)
			var canopy_height := rng.randf_range(3.2, 5.2)
			var canopy_scale := Basis().scaled(Vector3(canopy_radius, canopy_height, canopy_radius))
			var canopy_pos := Vector3(x, trunk_height + canopy_height * 0.42, z)
			pine_xforms.append(Transform3D(trunk_basis * canopy_scale, canopy_pos))
			pine_colors.append(Color(0.16 + green_shift, 0.42 + green_shift, 0.20 + green_shift * 0.5))
		else:
			var canopy_radius := rng.randf_range(1.8, 2.8)
			var canopy_scale := Basis().scaled(Vector3(canopy_radius, canopy_radius * 0.85, canopy_radius))
			var canopy_pos := Vector3(x, trunk_height + canopy_radius * 0.6, z)
			round_xforms.append(Transform3D(trunk_basis * canopy_scale, canopy_pos))
			round_colors.append(Color(0.22 + green_shift, 0.48 + green_shift, 0.22 + green_shift * 0.5))

		placed += 1

	_add_multimesh("Trunks", _cylinder_mesh(0.28, 0.28, 1.0, 6), trunk_xforms, [], Color(0.36, 0.24, 0.14))
	_add_multimesh("PineCanopy", _cylinder_mesh(0.0, 1.0, 1.0, 7), pine_xforms, pine_colors, Color(0.2, 0.45, 0.22))
	_add_multimesh("RoundCanopy", _sphere_mesh(1.0, 8, 6), round_xforms, round_colors, Color(0.24, 0.5, 0.24))

	var rock_xforms: Array[Transform3D] = []
	for i in range(rock_count):
		var x := rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z := rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		if Vector2(x, z).length() < clearing_radius * 0.6:
			continue
		var s := rng.randf_range(0.5, 1.4)
		var basis := Basis.from_euler(Vector3(rng.randf_range(0,0.3), rng.randf_range(0,TAU), rng.randf_range(0,0.3)))
		basis = basis.scaled(Vector3(s, s * 0.7, s))
		rock_xforms.append(Transform3D(basis, Vector3(x, s * 0.35, z)))
	_add_multimesh("Rocks", _sphere_mesh(1.0, 6, 5), rock_xforms, [], Color(0.55, 0.55, 0.53))


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], base_color: Color) -> void:
	if xforms.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	mmi.multimesh = mm

	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.albedo_color = base_color
	if mm.use_colors:
		mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat

	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	if Engine.is_editor_hint():
		mmi.owner = get_tree().edited_scene_root


func _cylinder_mesh(top_r: float, bottom_r: float, height: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m


func _sphere_mesh(radius: float, radial: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = radial
	m.rings = rings
	return m
