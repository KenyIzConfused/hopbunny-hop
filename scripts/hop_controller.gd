extends CharacterBody3D
## Hop Bunny, Hop - first-person controller.
##
## Replacement for proto_controller.gd (which was based on Brackeys' CC0
## prototype controller). Same export names / input actions, plus:
##
##   * HOLD the aim button (right mouse) -> a target cursor + ground marker +
##     arc preview show exactly where the next hop will land.
##   * While aiming, press JUMP (space) to hop to that spot.
##     (Set `hop_on_release` to hop when you let go of aim instead.)
##   * Camera pitch is limited (tighter while aiming) so the view never flips
##     or points somewhere useless. Yaw stays free so WASD always makes sense.
##   * The player (and therefore the camera) is kept inside the map bounds.

signal aim_changed(is_aiming: bool)
signal hop_started(target: Vector3)
signal hop_landed
signal respawned

const AimReticle = preload("res://scripts/aim_reticle.gd")
const ARC_POINTS := 24

enum AimStatus { NONE, VALID, CLAMPED, INVALID }

@export_group("General")
## Master switch (e.g. turn off while a menu is open or the ragdoll is active).
@export var can_move := true
@export var has_gravity := true
@export var can_jump := true
@export var can_sprint := true
@export var can_freefly := true

@export_group("Speeds")
@export var look_speed := 0.002
@export var base_speed := 6.0
@export var sprint_speed := 10.0
@export var freefly_speed := 25.0
@export var jump_velocity := 5.0
## 1.0 = same air control as the old controller. Lower = more momentum.
@export_range(0.0, 1.0) var air_control := 1.0
@export var gravity_scale := 1.0

@export_group("Input Actions")
@export var input_left := "left"
@export var input_right := "right"
@export var input_forward := "up"
@export var input_back := "down"
@export var input_jump := "jump"
@export var input_sprint := "sprint"
@export var input_freefly := "freefly"
## Hold this to aim your hop. Created automatically (right mouse) if missing.
@export var input_aim := "aim"

@export_group("Camera Limits")
## Max degrees you can look up / down while walking.
@export_range(10.0, 89.0) var pitch_up := 70.0
@export_range(10.0, 89.0) var pitch_down := 80.0
## Tighter range while aiming so the target always stays on the ground ahead.
@export_range(0.0, 89.0) var aim_pitch_up := 25.0
@export_range(10.0, 89.0) var aim_pitch_down := 85.0
## A single mouse event bigger than this (pixels) is treated as a glitch -
## this is what causes the camera to "snap" when the mouse is first captured.
@export var max_look_delta := 250.0

@export_group("Aim And Hop")
@export var max_hop_distance := 14.0
## Apex height of the shortest / longest hop (metres above the start point).
@export var hop_min_height := 1.6
@export var hop_max_height := 4.5
## Highest ledge (metres above your feet) you can aim at.
@export var max_hop_rise := 5.0
@export var max_landing_slope := 40.0
@export var aim_ray_length := 60.0
## Physics layers the aim ray / arc collide with (1 = default world layer).
@export_flags_3d_physics var aim_collision_mask := 1
## Walk speed multiplier while holding aim (0 = stand still).
@export_range(0.0, 1.0) var aim_move_scale := 0.4
## false: press jump while aiming.  true: hop as soon as you release aim.
@export var hop_on_release := false
@export var hop_cooldown := 0.12

@export_group("Map Bounds")
@export var enforce_bounds := true
## Optional: node whose meshes define the map (e.g. your terrain). If empty the
## biggest non-flat mesh in the scene is used automatically.
@export var bounds_from_node: NodePath
## Only used if auto-detect finds nothing. Zero size = no bounds.
@export var manual_bounds := AABB()
## Keep this far away from the map edge.
@export var bounds_margin := 2.0
## Below this Y (when there are no bounds) the player is respawned.
@export var kill_height := -100.0

var mouse_captured := false
var freeflying := false
var aiming := false

var camera: Camera3D
var head: Node3D

var _pitch := 0.0
var _shapes: Array[CollisionShape3D] = []
var _exclude: Array[RID] = []
var _feet_offset := 0.0
var _spawn_xform := Transform3D.IDENTITY

var _hopping := false
var _hop_time := 0.0
var _hop_cooldown := 0.0
var _aim_status: int = AimStatus.NONE
var _aim_ground := Vector3.ZERO
var _aim_has_ground := false
var _aim_normal := Vector3.UP
var _aim_velocity := Vector3.ZERO
var _arc_points := PackedVector3Array()
var _arc_count := 0

var _bounds := AABB()
var _has_bounds := false

var _reticle: Control
var _marker: Node3D
var _marker_mat: StandardMaterial3D
var _arc_mmi: MultiMeshInstance3D
var _arc_mat: StandardMaterial3D


func _ready() -> void:
	_ensure_input_actions()
	camera = _find_camera()
	head = _find_head()
	if head:
		_pitch = head.rotation.x
	if camera == null:
		push_warning("HopController: no Camera3D found under the player - aiming is disabled.")

	_shapes.clear()
	for child in get_children():
		if child is CollisionShape3D:
			_shapes.append(child)
	_feet_offset = _compute_feet_offset()
	_spawn_xform = global_transform
	_collect_exclusions()
	_arc_points.resize(ARC_POINTS)
	_build_aim_visuals()
	_init_bounds.call_deferred()


# ---------------------------------------------------------------- input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		capture_mouse()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		release_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		_rotate_look(event.relative)

	if can_freefly and event.is_action_pressed(input_freefly):
		_set_freefly(not freeflying)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_mouse()


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false


func _rotate_look(rel: Vector2) -> void:
	if head == null or not can_move:
		return
	rel = rel.limit_length(max_look_delta)
	rotate_y(-rel.x * look_speed)

	var lo := -deg_to_rad(_pitch_down_now())
	var hi := deg_to_rad(_pitch_up_now())
	var wanted := _pitch - rel.y * look_speed
	# Moving back into range is always allowed, moving further out never is.
	_pitch = clampf(wanted, minf(lo, _pitch), maxf(hi, _pitch))
	head.rotation.x = _pitch


func _pitch_up_now() -> float:
	return aim_pitch_up if aiming else pitch_up


func _pitch_down_now() -> float:
	return aim_pitch_down if aiming else pitch_down


func _process(delta: float) -> void:
	# Ease the view back inside the limits (e.g. when aim starts while looking up).
	if head == null:
		return
	var lo := -deg_to_rad(_pitch_down_now())
	var hi := deg_to_rad(_pitch_up_now())
	if _pitch > hi or _pitch < lo:
		_pitch = move_toward(_pitch, clampf(_pitch, lo, hi), deg_to_rad(240.0) * delta)
		head.rotation.x = _pitch


# -------------------------------------------------------------- physics ----

func _physics_process(delta: float) -> void:
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)
	_update_aim_state()

	if freeflying:
		_freefly_move(delta)
	else:
		_walk_move(delta)

	_apply_bounds()


func _walk_move(delta: float) -> void:
	var on_floor := is_on_floor()

	if has_gravity and not on_floor:
		velocity.y -= _gravity() * delta

	if _hopping:
		_hop_time += delta
		if (on_floor and _hop_time > 0.15) or is_on_wall() or _hop_time > 6.0:
			_end_hop()

	# --- jump / hop -------------------------------------------------------
	if can_move and can_jump and on_floor and not _hopping and Input.is_action_just_pressed(input_jump):
		if aiming:
			if not hop_on_release:
				_try_hop()
		else:
			velocity.y = jump_velocity

	# --- horizontal movement ---------------------------------------------
	if _hopping:
		pass # committed to the arc, keep the launch velocity
	elif can_move:
		var speed := base_speed
		if can_sprint and Input.is_action_pressed(input_sprint) and not aiming:
			speed = sprint_speed
		if aiming:
			speed *= aim_move_scale
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		var target := move_dir * speed
		if on_floor:
			if move_dir != Vector3.ZERO:
				velocity.x = target.x
				velocity.z = target.z
			else:
				velocity.x = move_toward(velocity.x, 0.0, maxf(speed, 1.0))
				velocity.z = move_toward(velocity.z, 0.0, maxf(speed, 1.0))
		else:
			velocity.x = lerpf(velocity.x, target.x, air_control)
			velocity.z = lerpf(velocity.z, target.z, air_control)
	else:
		velocity.x = move_toward(velocity.x, 0.0, base_speed)
		velocity.z = move_toward(velocity.z, 0.0, base_speed)

	move_and_slide()


func _freefly_move(delta: float) -> void:
	velocity = Vector3.ZERO
	if not can_move or head == null:
		return
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var motion := (head.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	motion *= freefly_speed * delta
	move_and_collide(motion)


func _set_freefly(enable: bool) -> void:
	freeflying = enable
	for cs in _shapes:
		cs.disabled = enable
	if enable:
		_end_hop(false)
		_set_aiming(false)
		velocity = Vector3.ZERO


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale


# ------------------------------------------------------------------ aim ----

func _update_aim_state() -> void:
	var want := (
		can_move
		and camera != null
		and not freeflying
		and mouse_captured
		and Input.is_action_pressed(input_aim)
	)
	if want != aiming:
		_set_aiming(want)

	if aiming:
		_update_aim()
	else:
		_aim_status = AimStatus.NONE
		_arc_count = 0
	_update_visuals()


func _set_aiming(value: bool) -> void:
	if value == aiming:
		return
	if not value and hop_on_release and can_move and is_on_floor() and not _hopping:
		_try_hop()
	aiming = value
	if not aiming:
		_aim_status = AimStatus.NONE
		_arc_count = 0
		_update_visuals()
	aim_changed.emit(aiming)


## Works out where the crosshair points on the ground and the arc to get there.
func _update_aim() -> void:
	_aim_status = AimStatus.NONE
	_aim_has_ground = false
	_arc_count = 0
	if not is_on_floor() or _hopping or _hop_cooldown > 0.0:
		return

	var space := get_world_3d().direct_space_state
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var tip := origin + dir * aim_ray_length

	var hit := _ray(space, origin, tip)
	if hit.is_empty():
		# Looking at the sky / horizon: drop a probe from the end of the ray.
		hit = _ray(space, tip + Vector3.UP * 2.0, tip + Vector3.DOWN * aim_ray_length)
	if hit.is_empty():
		_aim_status = AimStatus.INVALID
		return

	var from := global_position
	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var status: int = AimStatus.VALID

	# Keep the landing spot in hop range and inside the map.
	var want := Vector3(pos.x, 0.0, pos.z)
	var clamped := false
	var flat := Vector3(pos.x - from.x, 0.0, pos.z - from.z)
	if flat.length() > max_hop_distance:
		want = Vector3(from.x, 0.0, from.z) + flat.normalized() * max_hop_distance
		clamped = true
	var inside := _clamp_xz_to_bounds(want)
	if not inside.is_equal_approx(want):
		want = inside
		clamped = true
	if clamped:
		var down := _ray(
			space,
			Vector3(want.x, from.y + 15.0, want.z),
			Vector3(want.x, from.y - 60.0, want.z)
		)
		if down.is_empty():
			_aim_status = AimStatus.INVALID
			return
		pos = down.position
		normal = down.normal
		status = AimStatus.CLAMPED

	_aim_ground = pos
	_aim_normal = normal
	_aim_has_ground = true

	var target := pos + Vector3.UP * (_feet_offset + 0.05)
	if normal.y < cos(deg_to_rad(max_landing_slope)) or target.y - from.y > max_hop_rise:
		_aim_status = AimStatus.INVALID
		return

	var sol := _solve_hop(from, target)
	var vel: Vector3 = sol.velocity
	var total: float = sol.time
	_aim_velocity = vel

	# Sample the arc; stop (and go red) where something is in the way.
	var g := _gravity()
	var prev := from + Vector3.UP * 0.35
	var blocked := false
	for i in ARC_POINTS:
		var t := total * float(i + 1) / float(ARC_POINTS)
		var p := from + vel * t + Vector3(0.0, -0.5 * g * t * t, 0.0)
		_arc_points[i] = p
		if not blocked:
			# the last two segments touch the landing ground - don't test those
			if i < ARC_POINTS - 2 and not _ray(space, prev, p).is_empty():
				blocked = true
			else:
				_arc_count = i + 1
		prev = p
	if blocked:
		status = AimStatus.INVALID
	_aim_status = status


## Ballistic launch velocity that lands on `to`, peaking `apex` above the start.
func _solve_hop(from: Vector3, to: Vector3) -> Dictionary:
	var g := _gravity()
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dy := to.y - from.y
	var k := clampf(flat.length() / maxf(max_hop_distance, 0.01), 0.0, 1.0)
	var apex := maxf(lerpf(hop_min_height, hop_max_height, k), maxf(dy, 0.0) + 0.6)
	var vy := sqrt(2.0 * g * apex)
	var t_up := vy / g
	var t_down := sqrt(2.0 * maxf(apex - dy, 0.01) / g)
	var t := t_up + t_down
	var v := flat / t
	v.y = vy
	return {"velocity": v, "time": t}


func _try_hop() -> bool:
	if _aim_status != AimStatus.VALID and _aim_status != AimStatus.CLAMPED:
		return false
	if not is_on_floor() or _hopping or _hop_cooldown > 0.0:
		return false
	velocity = _aim_velocity
	_hopping = true
	_hop_time = 0.0
	hop_started.emit(_aim_ground)
	return true


func _end_hop(emit := true) -> void:
	if not _hopping:
		return
	_hopping = false
	_hop_cooldown = hop_cooldown
	if emit:
		hop_landed.emit()


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, aim_collision_mask, _exclude)
	return space.intersect_ray(q)


# ------------------------------------------------------- aim visuals ----

func _build_aim_visuals() -> void:
	# Screen-space target cursor.
	var layer := CanvasLayer.new()
	layer.name = "AimUI"
	layer.layer = 5
	add_child(layer)
	_reticle = AimReticle.new()
	_reticle.name = "AimReticle"
	layer.add_child(_reticle)

	# Ground marker (ring + soft disc), lives in world space.
	_marker = Node3D.new()
	_marker.name = "AimMarker"
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)

	_marker_mat = _make_mat(Color.WHITE, 0.9)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.65
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _marker_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(ring)

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.01
	cyl.radial_segments = 24
	cyl.rings = 1
	disc.mesh = cyl
	disc.material_override = _make_mat(Color.WHITE, 0.25)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(disc)

	# Arc preview: a row of little dots.
	_arc_mat = _make_mat(Color.WHITE, 0.9)
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	dot.radial_segments = 8
	dot.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = ARC_POINTS
	mm.visible_instance_count = 0
	_arc_mmi = MultiMeshInstance3D.new()
	_arc_mmi.name = "AimArc"
	_arc_mmi.multimesh = mm
	_arc_mmi.material_override = _arc_mat
	_arc_mmi.top_level = true
	_arc_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_mmi.extra_cull_margin = 100.0
	add_child(_arc_mmi)


func _make_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, alpha)
	return m


func _update_visuals() -> void:
	if _reticle == null:
		return
	_reticle.set_aim(aiming, _aim_status)

	# INVALID targets with a known ground point (too steep / blocked) still show, in red.
	var show_marker := aiming and _aim_status != AimStatus.NONE and _aim_has_ground
	_marker.visible = show_marker

	var col: Color = _reticle.status_color(_aim_status)
	if show_marker:
		var up := _aim_normal
		var x := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
		var z := x.cross(up).normalized()
		x = up.cross(z).normalized()
		_marker.global_transform = Transform3D(Basis(x, up, z), _aim_ground + up * 0.06)
		_marker_mat.albedo_color = Color(col, 0.9)

	_arc_mmi.visible = aiming and _arc_count > 0
	if _arc_mmi.visible:
		_arc_mat.albedo_color = Color(col, 0.9)
		var mm := _arc_mmi.multimesh
		mm.visible_instance_count = _arc_count
		for i in _arc_count:
			mm.set_instance_transform(i, Transform3D(Basis(), _arc_points[i]))


# ---------------------------------------------------------- map bounds ----

func _init_bounds() -> void:
	_has_bounds = false
	if not enforce_bounds:
		return

	var box := AABB()
	if not bounds_from_node.is_empty():
		var n := get_node_or_null(bounds_from_node)
		if n:
			box = _merged_mesh_aabb(n)
	if not box.has_volume():
		box = _auto_detect_bounds()
	if not box.has_volume() and manual_bounds.has_volume():
		box = manual_bounds
	if not box.has_volume():
		push_warning("HopController: no map bounds found. Set `bounds_from_node` to your terrain so the player can't leave the map.")
		return

	box.position.y -= 40.0
	box.size.y += 40.0 + 150.0 # generous headroom for hops
	_bounds = box
	_has_bounds = true


func _auto_detect_bounds() -> AABB:
	var root := get_tree().current_scene
	if root == null:
		return AABB()
	var best := AABB()
	var best_area := 0.0
	var best_name := ""
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or self.is_ancestor_of(mi):
			continue
		if mi.mesh is PlaneMesh or mi.mesh is QuadMesh:
			continue
		var n := String(mi.name).to_lower()
		if n.contains("water") or n.contains("sky") or n.contains("fog") or n.contains("cloud"):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.size.y < 0.5: # flat sheets (water, decals) aren't the terrain
			continue
		var area := box.size.x * box.size.z
		if area > best_area:
			best_area = area
			best = box
			best_name = String(mi.name)
	if best_area > 0.0:
		print("[HopController] map bounds auto-detected from '%s' (%.0f x %.0f m)." % [best_name, best.size.x, best.size.z])
	return best


func _merged_mesh_aabb(node: Node) -> AABB:
	var out := AABB()
	var have := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var box := mi.global_transform * mi.get_aabb()
			out = box if not have else out.merge(box)
			have = true
		stack.append_array(n.get_children())
	return out


func _bounds_xz() -> Rect2:
	return Rect2(
		Vector2(_bounds.position.x + bounds_margin, _bounds.position.z + bounds_margin),
		Vector2(_bounds.size.x - bounds_margin * 2.0, _bounds.size.z - bounds_margin * 2.0)
	)


func _clamp_xz_to_bounds(p: Vector3) -> Vector3:
	if not _has_bounds:
		return p
	var r := _bounds_xz()
	return Vector3(clampf(p.x, r.position.x, r.end.x), p.y, clampf(p.z, r.position.y, r.end.y))


func _apply_bounds() -> void:
	var p := global_position
	var floor_y := _bounds.position.y if _has_bounds else kill_height
	if p.y < floor_y:
		respawn()
		return
	if not _has_bounds:
		return

	var r := _bounds_xz()
	var q := p
	q.x = clampf(p.x, r.position.x, r.end.x)
	q.z = clampf(p.z, r.position.y, r.end.y)
	q.y = minf(p.y, _bounds.end.y)
	if q == p:
		return
	# Stop pushing into the invisible wall instead of sliding along it.
	if q.x != p.x:
		velocity.x = 0.0
	if q.z != p.z:
		velocity.z = 0.0
	if q.y != p.y:
		velocity.y = minf(velocity.y, 0.0)
	global_position = q


func respawn() -> void:
	global_transform = _spawn_xform
	velocity = Vector3.ZERO
	_end_hop(false)
	_pitch = 0.0
	if head:
		head.rotation.x = 0.0
	respawned.emit()


# -------------------------------------------------------------- helpers ----

func _find_camera() -> Camera3D:
	for c in find_children("*", "Camera3D", true, false):
		return c as Camera3D
	return null


func _find_head() -> Node3D:
	if has_node("Head"):
		return get_node("Head") as Node3D
	if camera:
		var p := camera.get_parent()
		if p is Node3D and p != self:
			return p as Node3D
		return camera
	return self


func _collect_exclusions() -> void:
	_exclude.clear()
	_exclude.append(get_rid())
	# ragdoll bones / limb colliders would otherwise block the aim ray
	for o in find_children("*", "CollisionObject3D", true, false):
		_exclude.append((o as CollisionObject3D).get_rid())


func _compute_feet_offset() -> float:
	var lowest := INF
	for cs in _shapes:
		if cs.shape == null:
			continue
		var mesh := cs.shape.get_debug_mesh()
		if mesh == null:
			continue
		var box := cs.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	if is_inf(lowest):
		return 0.0
	return clampf(global_position.y - lowest, 0.0, 3.0)


func _ensure_input_actions() -> void:
	if not InputMap.has_action(input_aim):
		InputMap.add_action(input_aim)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(input_aim, ev)
	for action in [input_left, input_right, input_forward, input_back, input_jump]:
		if not InputMap.has_action(action):
			push_error("HopController: input action '%s' is missing in Project Settings > Input Map." % action)
	for action in [input_sprint, input_freefly]:
		if not InputMap.has_action(action):
			push_warning("HopController: optional input action '%s' is missing." % action)
