class_name CameraOrbitRig
extends Node3D
## God camera: looks at planet center. World +Y = north pole axis.
## Motion follows the lines: along latitude circles = spin forever (φ). Along meridians
## (longitude lines) = north/south until the pole, then stop — no flip through (θ clamped).
## Keys: A/D = west/east along parallels; W/S = north/south along meridians (matches mouse).

const _PS := preload("res://Scripts/project_scale.gd")
## Physical radius (km); derived from [member _PS.PLANET_RADIUS_GAME_UNITS] × [member _PS.METERS_PER_GAME_UNIT].
const PLANET_RADIUS_KM: float = _PS.PLANET_RADIUS_GAME_UNITS * _PS.METERS_PER_GAME_UNIT / 1000.0
## Max zoom-in: approximate nadir ground footprint diameter (km); ortho [param ortho_size] matches this span on the tangent plane for small patches, not camera altitude.
const MIN_GROUND_FOOTPRINT_DIAMETER_KM: float = 60.0
const MIN_ORTHO_SIZE_AT_MIN_VIEW_KM: float = (
	MIN_GROUND_FOOTPRINT_DIAMETER_KM * 1000.0 / _PS.METERS_PER_GAME_UNIT
)
const TAU: float = PI * 2.0
## Colatitude stops short of 0 / π (exact poles) to avoid basis flips (radians).
const COLATITUDE_POLE_MARGIN: float = 0.1
## When |UP×forward|² is below this, UP and view are nearly parallel — use meridian × forward.
const SIDE_FROM_UP_CROSS_MIN_SQ: float = 6.4e-4
const SIDE_FALLBACK_LEN_SQ: float = 1e-14

@export var target: Vector3 = Vector3.ZERO
@export var camera_path: NodePath = ^"Camera3D"

@export_group("Orthographic zoom (1 game unit = 10 m)")
## Radial distance from target along the view ray. Zoom uses ortho size only; this is placement and clipping.
@export var orbit_radius: float = 2_000_000.0
## Orthographic diameter on the locked axis (Godot: [member Camera3D.size] is full span, not half). If <= 0 on load, starts at full-disk zoom-out.
@export var ortho_size: float = 0.0
@export var zoom_wheel_factor: float = 0.12
@export var min_ortho_size: float = MIN_ORTHO_SIZE_AT_MIN_VIEW_KM
@export var full_disk_margin: float = 1.12
## Endpoints for apparent_altitude, inverted from the ortho_size ↔ t mapping (same as the old altitude lerp).
@export var min_altitude: float = _PS.PLANET_RADIUS_GAME_UNITS * 1.15
@export var max_altitude: float = 2_000_000.0

## LOD / UI / sim: same linear "altitude" as before, derived from current ortho_size.
var apparent_altitude: float:
	get:
		return _apparent_altitude_for_ortho_size(ortho_size)


func get_apparent_altitude_km() -> float:
	return apparent_altitude * _PS.METERS_PER_GAME_UNIT / 1000.0


## Ortho vertical span in km (Camera3D.size). For nadir and patch ≪ R, ≈ ground footprint diameter.
func get_ortho_view_height_km() -> float:
	return ortho_size * _PS.METERS_PER_GAME_UNIT / 1000.0


## Perspective altitude h (km) with the same tangent-disk chord diameter S as ortho span [method get_ortho_view_height_km]: h = R/√(1−(S/2R)²) − R. Invalid (INF) when S ≥ 2R.
func get_equivalent_perspective_altitude_km() -> float:
	var s_km: float = get_ortho_view_height_km()
	var r_km: float = PLANET_RADIUS_KM
	if s_km <= 0.0:
		return 0.0
	var half_chord_over_r: float = s_km / (2.0 * r_km)
	if half_chord_over_r >= 1.0:
		return INF
	var radicand: float = 1.0 - half_chord_over_r * half_chord_over_r
	if radicand <= 0.0:
		return INF
	return r_km / sqrt(radicand) - r_km

@export_group("Orbit")
@export var rotation_sensitivity: float = 0.0025
## Radians per second while A/D/W/S are held.
@export var key_orbit_speed: float = 1.4
@export var orbit_with_middle_mouse: bool = true
@export var orbit_with_right_mouse: bool = true

## φ = azimuth around +Y: moving along a latitude circle; unbounded (wrapped modulo 2π).
var _phi: float = 0.0
## θ = colatitude from +Y (rad), clamped to [margin, π−margin] — never exact poles.
var _theta: float = PI * 0.5
## Previous camera +Y (world); keeps the twist-free frame from sign-flipping across a threshold.
var _prev_cam_up: Vector3 = Vector3.UP

@onready var _camera: Camera3D = get_node(camera_path)


func _ready() -> void:
	if ortho_size <= 0.0:
		ortho_size = _ortho_size_full_disk()
	else:
		ortho_size = _clamp_ortho_size(ortho_size)
	_wrap_phi()
	_theta = _clamp_theta(_theta)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_camera()
	call_deferred("_apply_camera")


func _process(delta: float) -> void:
	var changed := false
	if Input.is_physical_key_pressed(KEY_D):
		_phi += key_orbit_speed * delta
		changed = true
	if Input.is_physical_key_pressed(KEY_A):
		_phi -= key_orbit_speed * delta
		changed = true
	if Input.is_physical_key_pressed(KEY_W):
		_theta = _clamp_theta(_theta - key_orbit_speed * delta)
		changed = true
	if Input.is_physical_key_pressed(KEY_S):
		_theta = _clamp_theta(_theta + key_orbit_speed * delta)
		changed = true
	if changed:
		_wrap_phi()
		_apply_camera()


func _clamp_theta(t: float) -> float:
	return clampf(t, COLATITUDE_POLE_MARGIN, PI - COLATITUDE_POLE_MARGIN)


func _orbit_dir() -> Vector3:
	var st := sin(_theta)
	return Vector3(st * sin(_phi), cos(_theta), st * cos(_phi))


func _wrap_phi() -> void:
	_phi = fposmod(_phi, TAU)


func _on_viewport_size_changed() -> void:
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_orbit(-1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_orbit(1.0)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _orbit_mask_pressed():
		var dx: float = event.relative.x
		var dy: float = event.relative.y
		# Along latitude (east/west around the globe): φ can spin without limit.
		_phi -= dx * rotation_sensitivity
		_wrap_phi()
		# Along meridian (north/south): θ stops at poles; inverted dy so drag matches W/S.
		_theta = _clamp_theta(_theta - dy * rotation_sensitivity)
		_apply_camera()
		get_viewport().set_input_as_handled()


func _zoom_orbit(steps_sign: float) -> void:
	var factor := 1.0 + zoom_wheel_factor * steps_sign
	ortho_size = _clamp_ortho_size(ortho_size * factor)
	_apply_camera()


func _orbit_mask_pressed() -> bool:
	var mask := Input.get_mouse_button_mask()
	return (
		(orbit_with_middle_mouse and (mask & MOUSE_BUTTON_MASK_MIDDLE) != 0)
		or (orbit_with_right_mouse and (mask & MOUSE_BUTTON_MASK_RIGHT) != 0)
	)


func _side_axis_near_pole(meridian_h: Vector3, forward: Vector3) -> Vector3:
	var side := meridian_h.cross(forward)
	if side.length_squared() < SIDE_FALLBACK_LEN_SQ:
		side = Vector3.RIGHT.cross(forward)
	if side.length_squared() < SIDE_FALLBACK_LEN_SQ:
		side = Vector3.FORWARD.cross(forward)
	return side.normalized()


func _twist_free_basis(forward: Vector3) -> Basis:
	var meridian_h := Vector3(sin(_phi), 0.0, cos(_phi))
	var side_geo := Vector3.UP.cross(forward)
	var side: Vector3
	if side_geo.length_squared() > SIDE_FROM_UP_CROSS_MIN_SQ:
		side = side_geo.normalized()
	else:
		side = _side_axis_near_pole(meridian_h, forward)
	var up_cam := forward.cross(side).normalized()
	if up_cam.dot(_prev_cam_up) < 0.0:
		side = -side
		up_cam = forward.cross(side).normalized()
	var z_axis := -forward
	var y_axis := up_cam
	var x_axis := y_axis.cross(z_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	# Second pass: Gram-Schmidt can nudge y; keep sign continuous with last frame.
	if y_axis.dot(_prev_cam_up) < 0.0:
		x_axis = -x_axis
		y_axis = -y_axis
	_prev_cam_up = y_axis
	return Basis(x_axis, y_axis, z_axis)


func _apply_camera() -> void:
	ortho_size = _clamp_ortho_size(ortho_size)
	var dir := _orbit_dir()
	var pos := target + dir * orbit_radius
	var forward := -dir
	var cam_basis := _twist_free_basis(forward)
	_camera.global_transform = Transform3D(cam_basis, pos)
	_camera.size = ortho_size
	var margin: float = maxf(50_000.0, orbit_radius * 0.05)
	_camera.near = 1.0
	_camera.far = orbit_radius + _PS.PLANET_RADIUS_GAME_UNITS + margin


func _viewport_aspect() -> float:
	var s := get_viewport().get_visible_rect().size
	return s.x / maxf(s.y, 1.0)


func _ortho_size_full_disk() -> float:
	var aspect := _viewport_aspect()
	var min_diameter := 2.0 * _PS.PLANET_RADIUS_GAME_UNITS * full_disk_margin
	return min_diameter * maxf(1.0, 1.0 / aspect)


func _clamp_ortho_size(s: float) -> float:
	return clampf(s, min_ortho_size, _ortho_size_full_disk())


func _apparent_altitude_for_ortho_size(s: float) -> float:
	var smax := _ortho_size_full_disk()
	var denom := maxf(smax - min_ortho_size, 1e-6)
	var t := clampf((s - min_ortho_size) / denom, 0.0, 1.0)
	var span := maxf(max_altitude - min_altitude, 1.0)
	return min_altitude + t * span
