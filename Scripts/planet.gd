@tool
extends Node3D

const _PS := preload("res://Scripts/project_scale.gd")
## Cube-sphere body at [member _PS.PLANET_RADIUS_GAME_UNITS]; optional in-memory height / climate viz.
const _ELEVATION_SHADER: Shader = preload("res://Shaders/elevation_grayscale.gdshader")
const _TEMPERATURE_SHADER: Shader = preload("res://Shaders/temperature_colormap.gdshader")
const _PRECIPITATION_SHADER: Shader = preload("res://Shaders/moisture_colormap.gdshader")
const _BIOME_SHADER: Shader = preload("res://Shaders/biome_colormap.gdshader")

@export_group("Dimensions")
@export var radius: float = _PS.PLANET_RADIUS_GAME_UNITS:
	set(val):
		radius = val
		generate_sphere()

@export_range(2, 100) var resolution: int = 32:
	set(val):
		resolution = val
		generate_sphere()

@export_group("Elevation visualization")
## Used only for on-demand EXR export ([method PlanetBaseTruthBaker.export_height_exrs_from_grid]); heatmap uses [ClimateGrid].
@export var elevation_data_dir: String = "user://planet_data/"
@export var elevation_file_prefix: String = "level0_height_"
@export var elevation_height_min_m: float = -11000.0
@export var elevation_height_max_m: float = 8850.0

@export_group("Biome visualization (hydrology)")
## Flow accumulation above this value (watershed / artery-boosted units from [method ClimateSimulator.calculate_flow_accumulation]) draws major rivers in the biome shader.
@export var river_flow_threshold: float = 100.0

var _elevation_visualization_enabled: bool = false
var _temperature_visualization_enabled: bool = false
var _precipitation_visualization_enabled: bool = false
var _biome_visualization_enabled: bool = false
var _default_material: StandardMaterial3D
var _elevation_material: ShaderMaterial
var _height_array_tex: Texture2DArray
var _temperature_material: ShaderMaterial
var _temperature_array_tex: Texture2DArray
var _precipitation_material: ShaderMaterial
var _precipitation_array_tex: Texture2DArray
var _biome_material: ShaderMaterial
var _biome_array_tex: Texture2DArray
var _biome_elevation_array_tex: Texture2DArray
var _biome_flow_array_tex: Texture2DArray

func _ready() -> void:
	generate_sphere()

func generate_sphere() -> void:
	for child in get_children():
		child.queue_free()
		
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "SphereMesh"
	add_child(mesh_instance)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var face_normals = [
		Vector3.MODEL_FRONT, Vector3.MODEL_REAR,
		Vector3.MODEL_LEFT, Vector3.MODEL_RIGHT,
		Vector3.MODEL_TOP, Vector3.MODEL_BOTTOM
	]
	
	var current_vertex_count = 0
	for normal in face_normals:
		current_vertex_count = create_face(st, normal, current_vertex_count)
	
	st.generate_normals()
	mesh_instance.mesh = st.commit()
	_apply_active_material_to_mesh(mesh_instance)

func create_face(st: SurfaceTool, normal: Vector3, offset: int) -> int:
	var axis_a := Vector3(normal.y, normal.z, normal.x)
	var axis_b := normal.cross(axis_a)
	
	var vertices_added = 0
	
	for y in range(resolution):
		for x in range(resolution):
			var percent := Vector2(x, y) / (resolution - 1)
			var point_on_cube := normal + (percent.x - 0.5) * 2.0 * axis_a + (percent.y - 0.5) * 2.0 * axis_b
			var point_on_sphere := point_on_cube.normalized() * radius
			
			st.add_vertex(point_on_sphere)
			vertices_added += 1
			
			if x < resolution - 1 and y < resolution - 1:
				var i = x + y * resolution
				
				# FLIPPED WINDING ORDER: (offset + i, offset + i + resolution, offset + i + resolution + 1)
				# This ensures the 'front' of the face points away from the center.
				st.add_index(offset + i)
				st.add_index(offset + i + resolution)
				st.add_index(offset + i + resolution + 1)
				
				st.add_index(offset + i)
				st.add_index(offset + i + resolution + 1)
				st.add_index(offset + i + 1)
				
	return offset + vertices_added


func _ensure_default_material() -> void:
	if _default_material == null:
		_default_material = StandardMaterial3D.new()
		_default_material.albedo_color = Color(0.28, 0.32, 0.38)


func _get_sphere_mesh_instance() -> MeshInstance3D:
	return get_node_or_null("SphereMesh") as MeshInstance3D


func _apply_active_material_to_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null:
		return
	_ensure_default_material()
	if _biome_visualization_enabled and _biome_material != null:
		mesh_instance.material_override = _biome_material
	elif _precipitation_visualization_enabled and _precipitation_material != null:
		mesh_instance.material_override = _precipitation_material
	elif _temperature_visualization_enabled and _temperature_material != null:
		mesh_instance.material_override = _temperature_material
	elif _elevation_visualization_enabled and _elevation_material != null:
		mesh_instance.material_override = _elevation_material
	else:
		mesh_instance.material_override = _default_material


func _apply_active_material() -> void:
	_apply_active_material_to_mesh(_get_sphere_mesh_instance())


## Builds [Texture2DArray] from [param grid] [member ClimateGrid.elevation_map] (GPU path: [method Image.create_from_data]).
func set_elevation_visualization(enabled: bool, grid: ClimateGrid = null) -> bool:
	if enabled:
		_temperature_visualization_enabled = false
		_precipitation_visualization_enabled = false
		_biome_visualization_enabled = false
		if grid == null or not grid.is_allocated():
			return false
		if not _load_elevation_texture_array_from_grid(grid):
			return false
		_ensure_elevation_shader_material()
		_elevation_visualization_enabled = true
	else:
		_elevation_visualization_enabled = false
	_apply_active_material()
	return true


func is_elevation_visualization_enabled() -> bool:
	return _elevation_visualization_enabled


## Unshaded colormap from [ClimateGrid] temperature channel. Mutually exclusive with elevation viz.
func set_temperature_visualization(enabled: bool, grid: ClimateGrid = null) -> bool:
	if not enabled:
		_temperature_visualization_enabled = false
		_apply_active_material()
		return true
	if grid == null or not grid.is_allocated():
		return false
	var tex: Texture2DArray = grid.build_temperature_texture_array()
	if tex == null:
		return false
	_temperature_array_tex = tex
	var temp_rng: Vector2 = grid.get_temperature_range()
	_ensure_temperature_shader_material()
	_temperature_material.set_shader_parameter("u_temperatures", _temperature_array_tex)
	_temperature_material.set_shader_parameter("u_t_min", temp_rng.x)
	_temperature_material.set_shader_parameter("u_t_max", temp_rng.y)
	_temperature_visualization_enabled = true
	_elevation_visualization_enabled = false
	_precipitation_visualization_enabled = false
	_biome_visualization_enabled = false
	_apply_active_material()
	return true


func is_temperature_visualization_enabled() -> bool:
	return _temperature_visualization_enabled


## Unshaded colormap from [ClimateGrid] precipitation channel
## (annual precipitation, cm). Mutually exclusive with others.
func set_precipitation_visualization(enabled: bool, grid: ClimateGrid = null) -> bool:
	if not enabled:
		_precipitation_visualization_enabled = false
		_apply_active_material()
		return true
	if grid == null or not grid.is_allocated():
		return false
	var tex: Texture2DArray = grid.build_precipitation_texture_array()
	if tex == null:
		return false
	_precipitation_array_tex = tex
	var p_rng: Vector2 = grid.get_precipitation_colormap_range()
	_ensure_precipitation_shader_material()
	_precipitation_material.set_shader_parameter("u_moistures", _precipitation_array_tex)
	_precipitation_material.set_shader_parameter("u_m_min", p_rng.x)
	_precipitation_material.set_shader_parameter("u_m_max", p_rng.y)
	_precipitation_visualization_enabled = true
	_elevation_visualization_enabled = false
	_temperature_visualization_enabled = false
	_biome_visualization_enabled = false
	_apply_active_material()
	return true


func is_precipitation_visualization_enabled() -> bool:
	return _precipitation_visualization_enabled


## Unshaded discrete palette from [ClimateGrid] [member ClimateGrid.biome_index_map]. Mutually exclusive with others.
func set_biome_visualization(enabled: bool, grid: ClimateGrid = null) -> bool:
	if not enabled:
		_biome_visualization_enabled = false
		_apply_active_material()
		return true
	if grid == null or not grid.is_allocated():
		return false
	var tex: Texture2DArray = grid.build_biome_texture_array()
	if tex == null:
		return false
	_biome_array_tex = tex
	var elev_tex: Texture2DArray = grid.build_elevation_texture_array()
	if elev_tex == null:
		return false
	_biome_elevation_array_tex = elev_tex
	var flow_tex: Texture2DArray = grid.build_flow_accumulation_texture_array()
	if flow_tex == null:
		return false
	_biome_flow_array_tex = flow_tex
	_ensure_biome_shader_material()
	_biome_material.set_shader_parameter("u_biomes", _biome_array_tex)
	_biome_material.set_shader_parameter("u_heights", _biome_elevation_array_tex)
	_biome_material.set_shader_parameter("u_flow_accumulation", _biome_flow_array_tex)
	_biome_material.set_shader_parameter("u_river_flow_threshold", river_flow_threshold)
	_biome_visualization_enabled = true
	_elevation_visualization_enabled = false
	_temperature_visualization_enabled = false
	_precipitation_visualization_enabled = false
	_apply_active_material()
	return true


func is_biome_visualization_enabled() -> bool:
	return _biome_visualization_enabled


## Call after climate recompute while biome viz is on.
func refresh_biome_visualization(grid: ClimateGrid) -> void:
	if not _biome_visualization_enabled or grid == null or not grid.is_allocated():
		return
	var tex: Texture2DArray = grid.build_biome_texture_array()
	if tex == null:
		return
	_biome_array_tex = tex
	var elev_tex: Texture2DArray = grid.build_elevation_texture_array()
	var flow_tex: Texture2DArray = grid.build_flow_accumulation_texture_array()
	if elev_tex != null:
		_biome_elevation_array_tex = elev_tex
	if flow_tex != null:
		_biome_flow_array_tex = flow_tex
	if _biome_material != null:
		_biome_material.set_shader_parameter("u_biomes", _biome_array_tex)
		if _biome_elevation_array_tex != null:
			_biome_material.set_shader_parameter("u_heights", _biome_elevation_array_tex)
		if _biome_flow_array_tex != null:
			_biome_material.set_shader_parameter("u_flow_accumulation", _biome_flow_array_tex)
		_biome_material.set_shader_parameter("u_river_flow_threshold", river_flow_threshold)


## Call after climate recompute while temperature viz is on.
func refresh_temperature_visualization(grid: ClimateGrid) -> void:
	if not _temperature_visualization_enabled or grid == null or not grid.is_allocated():
		return
	var tex: Texture2DArray = grid.build_temperature_texture_array()
	if tex == null:
		return
	_temperature_array_tex = tex
	var temp_rng: Vector2 = grid.get_temperature_range()
	if _temperature_material != null:
		_temperature_material.set_shader_parameter("u_temperatures", _temperature_array_tex)
		_temperature_material.set_shader_parameter("u_t_min", temp_rng.x)
		_temperature_material.set_shader_parameter("u_t_max", temp_rng.y)


## Call after climate recompute while precipitation viz is on.
func refresh_precipitation_visualization(grid: ClimateGrid) -> void:
	if not _precipitation_visualization_enabled or grid == null or not grid.is_allocated():
		return
	var tex: Texture2DArray = grid.build_precipitation_texture_array()
	if tex == null:
		return
	_precipitation_array_tex = tex
	var p_rng: Vector2 = grid.get_precipitation_colormap_range()
	if _precipitation_material != null:
		_precipitation_material.set_shader_parameter("u_moistures", _precipitation_array_tex)
		_precipitation_material.set_shader_parameter("u_m_min", p_rng.x)
		_precipitation_material.set_shader_parameter("u_m_max", p_rng.y)


## Call after elevation data changes while heatmap is on.
func refresh_elevation_visualization(grid: ClimateGrid) -> void:
	if not _elevation_visualization_enabled or grid == null or not grid.is_allocated():
		return
	if not _load_elevation_texture_array_from_grid(grid):
		return
	if _elevation_material != null:
		_elevation_material.set_shader_parameter("u_heights", _height_array_tex)


func _load_elevation_texture_array_from_grid(grid: ClimateGrid) -> bool:
	var tex: Texture2DArray = grid.build_elevation_texture_array()
	if tex == null:
		push_warning("Planet: build_elevation_texture_array failed")
		return false
	_height_array_tex = tex
	return true


func _ensure_elevation_shader_material() -> void:
	if _elevation_material == null:
		_elevation_material = ShaderMaterial.new()
		_elevation_material.shader = _ELEVATION_SHADER
	_elevation_material.set_shader_parameter("u_heights", _height_array_tex)
	_elevation_material.set_shader_parameter("u_h_min", elevation_height_min_m)
	_elevation_material.set_shader_parameter("u_h_max", elevation_height_max_m)


func _ensure_temperature_shader_material() -> void:
	if _temperature_material == null:
		_temperature_material = ShaderMaterial.new()
		_temperature_material.shader = _TEMPERATURE_SHADER
	_temperature_material.set_shader_parameter("u_temperatures", _temperature_array_tex)


func _ensure_precipitation_shader_material() -> void:
	if _precipitation_material == null:
		_precipitation_material = ShaderMaterial.new()
		_precipitation_material.shader = _PRECIPITATION_SHADER
	_precipitation_material.set_shader_parameter("u_moistures", _precipitation_array_tex)


func _ensure_biome_shader_material() -> void:
	if _biome_material == null:
		_biome_material = ShaderMaterial.new()
		_biome_material.shader = _BIOME_SHADER
	_biome_material.set_shader_parameter("u_biomes", _biome_array_tex)
	if _biome_elevation_array_tex != null:
		_biome_material.set_shader_parameter("u_heights", _biome_elevation_array_tex)
	if _biome_flow_array_tex != null:
		_biome_material.set_shader_parameter("u_flow_accumulation", _biome_flow_array_tex)
	_biome_material.set_shader_parameter("u_river_flow_threshold", river_flow_threshold)
