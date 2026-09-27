@tool
extends Node3D
## Forest populator for Hop Bunny, Hop.
##
## Add this as a Node3D child of your forest map (map.tscn), set `asset_folder`,
## and press "Generate forest" in the Inspector (or just run the game - it
## generates itself on start).
##
## * Scans `asset_folder` (recursively) for every .glb/.gltf/.fbx/.obj/.tscn/.scn
##   and uses ALL of them. Every asset is guaranteed at least
##   `min_instances_per_asset` copies; the rest are picked by weight.
## * Trees get more weight than bushes/rocks (decided from the file name).
## * Placement uses the ground under each spot (physics ray or, better for
##   terrain without collision, the meshes under `ground_source`), with slope,
##   spacing, clearing and "don't plant in water" rules.
## * Rendering uses MultiMesh in chunks, so hundreds of trees stay cheap.
## * Trees/rocks get a trunk collider so the bunny can't walk through them.

enum Kind { TREE, PLANT, ROCK }

const MESH_EXTENSIONS := ["glb", "gltf", "fbx", "obj", "tscn", "scn"]
const PLANT_WORDS := ["bush", "shrub", "fern", "grass", "flower", "plant", "weed", "clover", "leaf", "reed", "mushroom"]
const ROCK_WORDS := ["rock", "stone", "boulder", "pebble", "cliff"]
const CONTAINER_NAME := "GeneratedForest"
const GROUND_CELL := 4.0

@export_group("Assets")
@export_dir var asset_folder := "res://asset"
## Any asset whose path contains one of these words is skipped.
## Defaults skip the animal model pack and the dune cactus.
@export var exclude_keywords: PackedStringArray = ["model1", "duneChallenge", "characters", "icon"]
## Optional per-asset weight, key = part of the file name, e.g. {"pine": 10}.
@export var weight_overrides: Dictionary = {}
@export var min_instances_per_asset := 4

@export_group("Area")
## Optional: node (e.g. terrain) whose bounding box defines the planting area
## AND whose meshes are used to find the ground. Leave empty to use `area_size`
## around this node and a physics ray for the ground.
@export var ground_source: NodePath
@export var area_size := Vector2(160.0, 160.0)

@export_group("Density")
@export var tree_count := 400
@export var random_seed := false
@export var seed_value := 20260919
## 0 = evenly spread, 1 = strong groves with open clearings between them.
@export_range(0.0, 1.0) var clumping := 0.55
@export var noise_frequency := 0.02
## Extra breathing room between neighbours (metres).
@export var min_spacing := 1.5

@export_group("Look")
@export var scale_range := Vector2(0.85, 1.25)
@export var global_scale := 1.0
@export_range(0.0, 15.0) var random_tilt_degrees := 2.5
## How far below the ground the base is sunk (metres) to hide floating roots.
@export var sink := 0.08
## 0 = always draw. Otherwise chunks beyond this distance are hidden.
@export var draw_distance := 0.0
@export var cast_shadows := true
@export var chunk_size := 40.0

@export_group("Rules")
@export_range(0.0, 89.0) var max_slope_degrees := 32.0
@export var min_height := -1000.0
@export var max_height := 1000.0
## Nodes in this group (e.g. water zones) keep the forest out.
@export var avoid_area_group := "water"
## Nothing is planted within this radius of the spawn / player / the nodes below.
@export var keep_clear_radius := 6.0
@export var keep_clear_nodes: Array[NodePath] = []
@export var keep_clear_positions: PackedVector3Array = PackedVector3Array()

@export_group("Collision")
@export var add_colliders := true
@export_range(0.02, 0.5) var trunk_radius_ratio := 0.1
@export_flags_3d_physics var collider_layer := 1

@export_group("Run")
@export var generate_on_ready := true
## Save the generated forest into the scene file (bigger .tscn, no runtime cost).
@export var bake_into_scene := false
@export_tool_button("Generate forest", "Reload") var _generate_button = generate
@export_tool_button("Clear forest", "Remove") var _clear_button = clear_forest

var _rng := RandomNumberGenerator.new()
var _entries: Array[Dictionary] = []
var _ground_meshes: Array[Dictionary] = []
var _ground_box := AABB()
var _clear_spots: Array[Vector3] = []
var _grid: Dictionary = {}
var _report: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint() or not generate_on_ready:
		return
	if has_node(CONTAINER_NAME): # baked into the scene already
		return
	# wait until physics bodies of the map are registered before ray-casting
	await get_tree().physics_frame
	await get_tree().physics_frame
	generate()


func clear_forest() -> void:
	var old := get_node_or_null(CONTAINER_NAME)
	if old:
		old.free()


func generate() -> void:
	if not is_inside_tree():
		return
	clear_forest()
	_rng.seed = randi() if random_seed else seed_value
	_report.clear()
	_grid.clear()

	_scan_assets()
	if _entries.is_empty():
		push_warning("ForestPopulator: no usable assets found in '%s'. Check `asset_folder` / `exclude_keywords`." % asset_folder)
		return

	_prepare_ground()
	_prepare_clear_spots()
	var placements := _plan_placements()
	_build(placements)
	_print_report(placements.size())


# --------------------------------------------------------- asset scan ----

func _scan_assets() -> void:
	_entries.clear()
	var files: Array[String] = []
	_walk(asset_folder, files)
	files.sort()

	for path in files:
		var lower := path.to_lower()
		var skip := false
		for word in exclude_keywords:
			if word != "" and lower.contains(word.to_lower()):
				skip = true
				break
		if skip:
			continue

		var res := load(path)
		var root: Node = null
		if res is PackedScene:
			root = (res as PackedScene).instantiate()
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res
			root = mi
		if root == null:
			continue

		var parts: Array[Dictionary] = []
		_collect_parts(root, Transform3D.IDENTITY, parts, true)
		root.free()
		if parts.is_empty():
			continue

		var box := AABB()
		var have := false
		for part in parts:
			var b: AABB = (part.xform as Transform3D) * (part.mesh as Mesh).get_aabb()
			box = b if not have else box.merge(b)
			have = true
		if box.size.y < 0.001:
			continue

		var file := path.get_file().get_basename()
		var kind := _classify(file.to_lower())
		var lift := 0.0
		# pivot in the middle of the model instead of at the trunk base -> lift it
		if absf(box.position.y) > 0.15 * box.size.y:
			lift = -box.position.y

		_entries.append({
			"path": path,
			"name": file,
			"parts": parts,
			"aabb": box,
			"kind": kind,
			"weight": _weight_for(file.to_lower(), kind),
			"lift": lift,
			"count": 0,
		})


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, out)
		else:
			# exported games list "x.glb.import" / "x.tscn.remap" instead of the source file
			var fname := entry
			if fname.ends_with(".import") or fname.ends_with(".remap"):
				fname = fname.get_basename()
				full = dir_path.path_join(fname)
			if fname.get_extension().to_lower() in MESH_EXTENSIONS and not out.has(full):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_parts(node: Node, parent_xform: Transform3D, out: Array[Dictionary], is_root: bool) -> void:
	var xf := parent_xform
	if node is Node3D and not is_root:
		xf = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as Node3D).visible:
		var mi := node as MeshInstance3D
		out.append({
			"mesh": mi.mesh,
			"xform": xf,
			"material": mi.material_override,
		})
	for child in node.get_children():
		_collect_parts(child, xf, out, false)


func _classify(lower_name: String) -> int:
	for w in ROCK_WORDS:
		if lower_name.contains(w):
			return Kind.ROCK
	for w in PLANT_WORDS:
		if lower_name.contains(w):
			return Kind.PLANT
	return Kind.TREE


func _weight_for(lower_name: String, kind: int) -> float:
	for key in weight_overrides:
		if lower_name.contains(String(key).to_lower()):
			return maxf(float(weight_overrides[key]), 0.0)
	match kind:
		Kind.TREE:
			return 6.0
		Kind.PLANT:
			return 3.0
	return 1.5


# ------------------------------------------------------------- ground ----

func _prepare_ground() -> void:
	_ground_meshes.clear()
	_ground_box = AABB()
	var src := get_node_or_null(ground_source) if not ground_source.is_empty() else null
	if src:
		var have := false
		var stack: Array[Node] = [src]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				var mi := n as MeshInstance3D
				var faces := mi.mesh.get_faces()
				if faces.size() >= 3:
					var xf := mi.global_transform
					var world := PackedVector3Array()
					world.resize(faces.size())
					for i in faces.size():
						world[i] = xf * faces[i]
					_ground_meshes.append({"faces": world, "grid": _index_faces(world)})
					var b := xf * mi.get_aabb()
					_ground_box = b if not have else _ground_box.merge(b)
					have = true
			stack.append_array(n.get_children())
	if _ground_meshes.is_empty():
		var c := global_position
		_ground_box = AABB(Vector3(c.x - area_size.x * 0.5, c.y - 200.0, c.z - area_size.y * 0.5), Vector3(area_size.x, 400.0, area_size.y))


## Buckets triangles by their footprint on the XZ plane so a vertical ray only
## has to test the few triangles in its cell.
func _index_faces(world: PackedVector3Array) -> Dictionary:
	var grid: Dictionary = {}
	for t in int(world.size() / 3.0):
		var a := world[t * 3]
		var b := world[t * 3 + 1]
		var c := world[t * 3 + 2]
		var x0 := floori(minf(a.x, minf(b.x, c.x)) / GROUND_CELL)
		var x1 := floori(maxf(a.x, maxf(b.x, c.x)) / GROUND_CELL)
		var z0 := floori(minf(a.z, minf(b.z, c.z)) / GROUND_CELL)
		var z1 := floori(maxf(a.z, maxf(b.z, c.z)) / GROUND_CELL)
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(t)
	return grid


## Returns {"pos": Vector3, "normal": Vector3} or {} if there is no ground.
func _ground_at(x: float, z: float) -> Dictionary:
	var top := _ground_box.end.y + 50.0
	var bottom := _ground_box.position.y - 50.0

	if not _ground_meshes.is_empty():
		return _terrain_hit(x, z)

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z))
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	return {"pos": r.position, "normal": r.normal}


func _terrain_hit(x: float, z: float) -> Dictionary:
	var best_y := -INF
	var best_n := Vector3.UP
	var key := Vector2i(floori(x / GROUND_CELL), floori(z / GROUND_CELL))
	for g in _ground_meshes:
		var list: Array = (g.grid as Dictionary).get(key, [])
		var faces: PackedVector3Array = g.faces
		for t in list:
			var a := faces[t * 3]
			var b := faces[t * 3 + 1]
			var c := faces[t * 3 + 2]
			var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(d) < 0.000001:
				continue
			var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
			var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
			var l3 := 1.0 - l1 - l2
			if l1 < -0.00001 or l2 < -0.00001 or l3 < -0.00001:
				continue
			var y := l1 * a.y + l2 * b.y + l3 * c.y
			if y > best_y:
				best_y = y
				best_n = (b - a).cross(c - a).normalized()
				if best_n.y < 0.0:
					best_n = -best_n
	if best_y == -INF:
		return {}
	return {"pos": Vector3(x, best_y, z), "normal": best_n}


func _in_avoid_area(x: float, y: float, z: float) -> bool:
	if avoid_area_group == "":
		return false
	var areas := get_tree().get_nodes_in_group(avoid_area_group)
	if areas.is_empty():
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = Vector3(x, y + 0.2, z)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for hit in space.intersect_point(q, 8):
		var col := hit.collider as Node
		if col and (col.is_in_group(avoid_area_group) or (col.get_parent() and col.get_parent().is_in_group(avoid_area_group))):
			return true
	return false


func _prepare_clear_spots() -> void:
	_clear_spots.clear()
	for p in keep_clear_positions:
		_clear_spots.append(p)
	for path in keep_clear_nodes:
		var n := get_node_or_null(path) as Node3D
		if n:
			_clear_spots.append(n.global_position)
	for group in ["player", "spawn"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D:
				_clear_spots.append((n as Node3D).global_position)


func _is_clear(x: float, z: float) -> bool:
	for s in _clear_spots:
		if Vector2(x - s.x, z - s.z).length() < keep_clear_radius:
			return false
	return true


# ---------------------------------------------------------- placement ----

func _plan_placements() -> Array[Dictionary]:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.seed as int
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_frequency

	var total_weight := 0.0
	for e in _entries:
		total_weight += e.weight

	# guaranteed copies first, then weighted random until tree_count is reached
	var queue: Array[int] = []
	for i in _entries.size():
		for k in min_instances_per_asset:
			queue.append(i)
	var target := maxi(tree_count, queue.size())

	var placements: Array[Dictionary] = []
	var attempts := 0
	var max_attempts := target * 40
	var box := _ground_box

	while placements.size() < target and attempts < max_attempts:
		attempts += 1
		var forced := not queue.is_empty()
		var idx: int
		if forced:
			idx = queue[queue.size() - 1]
		else:
			idx = _pick_weighted(total_weight)
		var e: Dictionary = _entries[idx]

		var x := _rng.randf_range(box.position.x, box.end.x)
		var z := _rng.randf_range(box.position.z, box.end.z)

		# groves and clearings (forced copies ignore this so nothing goes unused)
		if not forced and clumping > 0.0:
			var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
			if _rng.randf() > lerpf(1.0, smoothstep(0.3, 0.7, n), clumping):
				continue

		if not _is_clear(x, z):
			continue

		var g := _ground_at(x, z)
		if g.is_empty():
			continue
		var pos: Vector3 = g.pos
		var normal: Vector3 = g.normal
		if pos.y < min_height or pos.y > max_height:
			continue
		if normal.y < cos(deg_to_rad(max_slope_degrees)):
			continue
		if _in_avoid_area(pos.x, pos.y, pos.z):
			continue

		var s := _rng.randf_range(scale_range.x, scale_range.y) * global_scale
		var size: Vector3 = (e.aabb as AABB).size
		var radius := clampf(maxf(size.x, size.z) * 0.5 * s * 0.4, 0.3, 3.0)
		if not _spacing_ok(pos, radius):
			continue

		_register(pos, radius)
		var yaw := _rng.randf() * TAU
		var tilt := deg_to_rad(random_tilt_degrees)
		var rot := Basis.from_euler(Vector3(_rng.randf_range(-tilt, tilt), yaw, _rng.randf_range(-tilt, tilt)))
		rot = rot.scaled(Vector3.ONE * s)
		var origin := pos + Vector3.UP * ((e.lift as float) * s - sink)
		placements.append({"entry": idx, "xform": Transform3D(rot, origin), "scale": s})
		e.count += 1
		if forced:
			queue.pop_back()

	if not queue.is_empty():
		push_warning("ForestPopulator: %d guaranteed copies could not be placed (area too small / too steep?)." % queue.size())
	return placements


func _pick_weighted(total: float) -> int:
	var r := _rng.randf() * total
	for i in _entries.size():
		r -= _entries[i].weight
		if r <= 0.0:
			return i
	return _entries.size() - 1


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 6.0), floori(p.z / 6.0))


func _spacing_ok(p: Vector3, radius: float) -> bool:
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list: Array = _grid.get(Vector2i(c.x + dx, c.y + dz), [])
			for other in list:
				var d := Vector2(p.x - other.x, p.z - other.z).length()
				if d < radius + other.w + min_spacing * 0.5:
					return false
	return true


func _register(p: Vector3, radius: float) -> void:
	var c := _cell(p)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(Vector4(p.x, p.y, p.z, radius))


# -------------------------------------------------------------- build ----

func _build(placements: Array[Dictionary]) -> void:
	var container := Node3D.new()
	container.name = CONTAINER_NAME
	add_child(container)
	if bake_into_scene and Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root

	# group by (asset, part, chunk) -> one MultiMesh each, so culling works
	var groups: Dictionary = {}
	var bodies: Dictionary = {}

	for pl in placements:
		var e: Dictionary = _entries[pl.entry]
		var xf: Transform3D = pl.xform
		var cell := Vector2i(floori(xf.origin.x / chunk_size), floori(xf.origin.z / chunk_size))

		var parts: Array = e.parts
		for pi in parts.size():
			var key := "%d|%d|%d|%d" % [pl.entry, pi, cell.x, cell.y]
			if not groups.has(key):
				groups[key] = {"entry": pl.entry, "part": pi, "list": [] as Array[Transform3D], "center": xf.origin}
			(groups[key].list as Array).append(xf * (parts[pi].xform as Transform3D))

		if add_colliders and (e.kind == Kind.TREE or e.kind == Kind.ROCK):
			var bkey := "%d|%d" % [cell.x, cell.y]
			if not bodies.has(bkey):
				var body := StaticBody3D.new()
				body.name = "Colliders_%d_%d" % [cell.x, cell.y]
				body.collision_layer = collider_layer
				body.collision_mask = 0
				container.add_child(body)
				bodies[bkey] = body
			_add_collider(bodies[bkey], e, xf, pl.scale)

	var mm_count := 0
	for key in groups:
		var grp: Dictionary = groups[key]
		var e: Dictionary = _entries[grp.entry]
		var part: Dictionary = e.parts[grp.part]
		var list: Array = grp.list

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [String(e.name).validate_node_name(), mm_count]
		mmi.multimesh = mm
		if part.material:
			mmi.material_override = part.material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if draw_distance > 0.0:
			mmi.visibility_range_end = draw_distance + chunk_size
		container.add_child(mmi)
		mm_count += 1

	if bake_into_scene and Engine.is_editor_hint():
		_set_owner_recursive(container, get_tree().edited_scene_root)


func _add_collider(body: StaticBody3D, e: Dictionary, xf: Transform3D, s: float) -> void:
	var size: Vector3 = (e.aabb as AABB).size
	var radius := clampf(minf(size.x, size.z) * trunk_radius_ratio * s, 0.12, 1.6)
	var height := clampf(size.y * s, 0.5, 8.0)
	if e.kind == Kind.ROCK:
		radius = clampf(maxf(size.x, size.z) * 0.4 * s, 0.2, 3.0)
		height = clampf(size.y * s, 0.3, 4.0)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(Basis(), xf.origin + Vector3.UP * (height * 0.5))
	body.add_child(cs)


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for c in node.get_children():
		c.owner = new_owner
		_set_owner_recursive(c, new_owner)


func _print_report(total: int) -> void:
	var lines: Array[String] = []
	for e in _entries:
		lines.append("    %-28s x%d" % [e.name, e.count])
	print("[ForestPopulator] placed %d objects from %d assets:\n%s" % [total, _entries.size(), "\n".join(lines)])
