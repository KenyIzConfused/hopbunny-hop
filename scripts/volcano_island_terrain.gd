@tool
extends LowPolyTerrainManager
class_name VolcanoIslandTerrain

## Procedurally builds the expanded forest island on top of the Low Poly
## Terrain Builder addon: rolling forest floor, a shoreline that sinks into
## the surrounding sea on every side, and a large inactive volcano near the
## north end. The volcano's crater rim is intentionally unclimbable from the
## outside — the only way to the summit is through the cave at its base.

## Toggle in the Inspector to force a full regenerate (also runs once on _ready).
@export var regenerate_button: bool:
	set(v):
		if v:
			call_deferred("_run_generation")

var volcano_center_world: Vector2 = Vector2.ZERO
var volcano_radius: float = 115.0
var volcano_base_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_run_generation()


func _run_generation() -> void:
	# Self-contained sizing so this can be re-triggered any time, not only on
	# the very first _ready(). 14x24 chunks * 12 verts * 2.5m = a 420 x 720m
	# island, far larger than the original ~50x50 test terrain.
	world_chunks = Vector2i(14, 24)
	chunk_size = 12
	cell_size = 2.5
	preview_world_chunks = world_chunks
	preview_chunk_size = chunk_size
	preview_cell_size = cell_size
	terrain_backend = TerrainBackend.MESH_NODES
	jitter_strength = 0.35
	jitter_slope_threshold = 1.2
	step_height = 0.25
	runtime_collision = RuntimeCollision.PREBUILT
	collision_group = "Wall"

	_recalculate_matrix_bounds()
	global_height_data = PackedFloat32Array()
	_initialize_empty_grid()

	_generate_island()
	rebuild_chunks_structure()
	notify_property_list_changed()

	if Engine.is_editor_hint():
		_bake_live_collisions_as_child()


func _generate_island() -> void:
	var w: int = _total_vertices_x
	var d: int = _total_vertices_z
	var world_w: float = total_size_meters.x
	var world_l: float = total_size_meters.y

	# Volcano sits toward the northern (high-Z-index / "top") end of the island,
	# far enough from the map edge that its slopes never get clipped by the
	# shoreline falloff.
	volcano_center_world = Vector2(world_w * 0.5, world_l * 0.80)
	volcano_radius = 115.0
	var volcano_height: float = 72.0
	var crater_radius: float = 27.0
	var crater_depth: float = 24.0
	volcano_base_world = Vector2(world_w * 0.5, world_l * 0.80 - volcano_radius * 0.92)

	var edge_margin: float = 45.0

	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.015

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = 4242
	detail_noise.frequency = 0.08

	for z in range(d):
		var wz: float = float(z) * cell_size
		for x in range(w):
			var wx: float = float(x) * cell_size

			# Rolling forest floor.
			var base_h: float = 3.0 + noise.get_noise_2d(wx, wz) * 3.5
			base_h += detail_noise.get_noise_2d(wx, wz) * 0.6

			# Distance to nearest map edge sinks the shoreline into the sea bed.
			var dist_edge: float = minf(minf(wx, world_w - wx), minf(wz, world_l - wz))
			var shore_t: float = clampf(dist_edge / edge_margin, 0.0, 1.0)
			var shore_curve: float = shore_t * shore_t * (3.0 - 2.0 * shore_t)
			var shoreline_h: float = lerpf(-9.0, base_h, shore_curve)

			# Volcano cone.
			var dist_v: float = Vector2(wx, wz).distance_to(volcano_center_world)
			var cone_t: float = clampf(1.0 - dist_v / volcano_radius, 0.0, 1.0)
			var cone_h: float = pow(cone_t, 1.4) * volcano_height

			var h: float = maxf(shoreline_h, cone_h)

			# Hollow, inactive crater bowl at the summit — steep-walled and closed,
			# not meant to be reached by climbing.
			if dist_v < crater_radius and h > volcano_height * 0.5:
				var crater_t: float = 1.0 - clampf(dist_v / crater_radius, 0.0, 1.0)
				h -= crater_depth * pow(crater_t, 1.6)

			global_height_data[z * w + x] = h


## World-space height at a given XZ, used by other scripts placing props/markers.
func sample_height(world_x: float, world_z: float) -> float:
	return get_height_at_world_coords(world_x, world_z)
