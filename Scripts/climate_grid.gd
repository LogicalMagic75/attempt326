class_name ClimateGrid
extends Resource

## Macro climate state for the cube-sphere: [constant FACE_COUNT] faces × [member face_resolution]²
## cells each. Layout matches [method PlanetBaseTruthBaker.generate_face_buffer] (y outer, x inner).

const FACE_COUNT: int = 6
const _FACE_RES_DEFAULT: int = 512
const _EXR_FACE_NAMES: PackedStringArray = [
	"right", "left", "top", "bottom", "front", "back"
]

@export_range(2, 4096) var face_resolution: int = _FACE_RES_DEFAULT:
	set(v):
		face_resolution = maxi(2, v)

## Mean annual precipitation stored in [member precipitation_map], centimeters
## per year (clamped to 0 … [constant MOISTURE_ANNUAL_PRECIP_CM_MAX]).
const MOISTURE_ANNUAL_PRECIP_CM_MAX: float = 450.0

@export var elevation_map: PackedFloat32Array = PackedFloat32Array()
@export var temperature_map: PackedFloat32Array = PackedFloat32Array()
@export var precipitation_map: PackedFloat32Array = PackedFloat32Array()
## Soil wetness proxy (precipitation + hydrology bonuses), centimeters per year
## (same display span as precipitation).
@export var soil_wetness_map: PackedFloat32Array = PackedFloat32Array()
@export var biome_index_map: PackedFloat32Array = PackedFloat32Array()
## Watershed flow (see [method ClimateSimulator.calculate_flow_accumulation]): upstream area + artery consolidation; major rivers when above a threshold in the biome shader.
@export var flow_accumulation_map: PackedFloat32Array = PackedFloat32Array()
## Flow DAG: linear index of the single D8 downstream neighbor on land, or
## [code]-1[/code] at pour points / ocean.
@export var flow_downstream_cell: PackedInt32Array = PackedInt32Array()
## Pour-point basin id per cell ([code]-1[/code] ocean); matches mouth index for coastal seeds (see [method ClimateSimulator.calculate_flow_accumulation]).
@export var basin_id_map: PackedInt32Array = PackedInt32Array()


func cells_per_face() -> int:
	return face_resolution * face_resolution


func total_cell_count() -> int:
	return FACE_COUNT * cells_per_face()


func cell_index(face: int, x: int, y: int) -> int:
	return face * cells_per_face() + y * face_resolution + x


func is_allocated() -> bool:
	var n := total_cell_count()
	return (
		elevation_map.size() == n
		and temperature_map.size() == n
		and precipitation_map.size() == n
		and soil_wetness_map.size() == n
		and biome_index_map.size() == n
		and flow_accumulation_map.size() == n
		and flow_downstream_cell.size() == n
		and basin_id_map.size() == n
	)


## Resizes all channels to [method total_cell_count] and fills with 0.
func allocate() -> void:
	var n := total_cell_count()
	elevation_map.resize(n)
	temperature_map.resize(n)
	precipitation_map.resize(n)
	soil_wetness_map.resize(n)
	biome_index_map.resize(n)
	flow_accumulation_map.resize(n)
	flow_downstream_cell.resize(n)
	basin_id_map.resize(n)
	elevation_map.fill(0.0)
	temperature_map.fill(0.0)
	precipitation_map.fill(0.0)
	soil_wetness_map.fill(0.0)
	biome_index_map.fill(0.0)
	flow_accumulation_map.fill(0.0)
	flow_downstream_cell.fill(-1)
	basin_id_map.fill(-1)


func get_elevation(face: int, x: int, y: int) -> float:
	return elevation_map[cell_index(face, x, y)]


func set_elevation(face: int, x: int, y: int, value: float) -> void:
	elevation_map[cell_index(face, x, y)] = value


func get_temperature(face: int, x: int, y: int) -> float:
	return temperature_map[cell_index(face, x, y)]


func set_temperature(face: int, x: int, y: int, value: float) -> void:
	temperature_map[cell_index(face, x, y)] = value


func get_precipitation(face: int, x: int, y: int) -> float:
	return precipitation_map[cell_index(face, x, y)]


func set_precipitation(face: int, x: int, y: int, value: float) -> void:
	precipitation_map[cell_index(face, x, y)] = value


func get_soil_wetness(face: int, x: int, y: int) -> float:
	return soil_wetness_map[cell_index(face, x, y)]


func set_soil_wetness(face: int, x: int, y: int, value: float) -> void:
	soil_wetness_map[cell_index(face, x, y)] = value


func get_biome_index(face: int, x: int, y: int) -> float:
	return biome_index_map[cell_index(face, x, y)]


func set_biome_index(face: int, x: int, y: int, value: float) -> void:
	biome_index_map[cell_index(face, x, y)] = value


func get_flow_accumulation(face: int, x: int, y: int) -> float:
	return flow_accumulation_map[cell_index(face, x, y)]


func set_flow_accumulation(face: int, x: int, y: int, value: float) -> void:
	flow_accumulation_map[cell_index(face, x, y)] = value


## Merges six per-face [PackedFloat32Array] layers (keys `0` … `5`, row-major y then x) into [member elevation_map].
## Resizes [member face_resolution] from buffer width if needed, then [method allocate]s when required.
func update_elevation_from_buffers(buffers: Dictionary) -> bool:
	if buffers.size() != FACE_COUNT:
		push_error(
			"ClimateGrid.update_elevation_from_buffers: need %d faces, got %d"
			% [FACE_COUNT, buffers.size()]
		)
		return false
	var buf0: PackedFloat32Array = buffers[0]
	if buf0.is_empty():
		push_error("ClimateGrid.update_elevation_from_buffers: face 0 buffer empty")
		return false
	var n: int = buf0.size()
	var side: int = int(round(sqrt(n)))
	if side * side != n:
		push_error("ClimateGrid.update_elevation_from_buffers: face buffer length %d is not square" % n)
		return false
	for face in range(1, FACE_COUNT):
		var b: PackedFloat32Array = buffers[face]
		if b.size() != n:
			push_error(
				"ClimateGrid.update_elevation_from_buffers: face %d size %d != %d"
				% [face, b.size(), n]
			)
			return false
	if face_resolution != side:
		face_resolution = side
	if not is_allocated() or elevation_map.size() != total_cell_count():
		allocate()
	var cpf: int = cells_per_face()
	for face in range(FACE_COUNT):
		var buf: PackedFloat32Array = buffers[face]
		var base: int = face * cpf
		for i in range(buf.size()):
			elevation_map[base + i] = buf[i]
	return true


## **Phase 5 / external tooling only** — imports baked height EXRs into [member elevation_map].
## Macro simulation uses [method update_elevation_from_buffers] instead.
func import_elevation_from_exr(dir: String, file_prefix: String) -> bool:
	if not is_allocated():
		allocate()
	var dir_path := dir
	if not dir_path.ends_with("/"):
		dir_path += "/"

	for face in range(FACE_COUNT):
		var path: String = dir_path + file_prefix + _EXR_FACE_NAMES[face] + ".exr"
		if not FileAccess.file_exists(path):
			push_error("ClimateGrid: missing height EXR: %s" % path)
			return false
		var img := Image.new()
		if img.load(path) != OK:
			push_error("ClimateGrid: failed to load: %s" % path)
			return false
		if img.get_width() != face_resolution or img.get_height() != face_resolution:
			push_error(
				"ClimateGrid: EXR size %dx%d != face_resolution %d for %s"
				% [img.get_width(), img.get_height(), face_resolution, path]
			)
			return false

		for y in range(face_resolution):
			for x in range(face_resolution):
				var lin := cell_index(face, x, y)
				elevation_map[lin] = img.get_pixel(x, y).r

	return true


## Phase 2.2 export: one RGBA32F EXR per face — R elevation (m), G temperature (°C), B annual precipitation (cm), A biome id.
## [param file_prefix] example: `level0_` → `level0_climate_rgba_right.exr`.
func export_packed_climate_exrs(dir: String, file_prefix: String) -> bool:
	if not is_allocated():
		push_error("ClimateGrid.export_packed_climate_exrs: grid not allocated")
		return false
	_ensure_export_dir(dir)
	var dir_path: String = dir if dir.ends_with("/") else dir + "/"
	var all_ok: bool = true
	for face in range(FACE_COUNT):
		var img := Image.create(face_resolution, face_resolution, false, Image.FORMAT_RGBAF)
		for y in range(face_resolution):
			for x in range(face_resolution):
				var e: float = get_elevation(face, x, y)
				var t: float = get_temperature(face, x, y)
				var m: float = get_precipitation(face, x, y)
				var b: float = get_biome_index(face, x, y)
				img.set_pixel(x, y, Color(e, t, m, b))
		var path: String = dir_path + file_prefix + "climate_rgba_" + _EXR_FACE_NAMES[face] + ".exr"
		if img.save_exr(path) != OK:
			push_error("ClimateGrid: save_exr failed: %s" % path)
			all_ok = false
	return all_ok


## Phase 2.2 export: five RF EXR sets (six files each), same face names as height bake.
## Writes `{prefix}climate_elevation_{face}.exr`, `climate_temperature_`,
## `climate_precipitation_`, `climate_soil_wetness_`, `climate_biome_`,
## `climate_flow_`.
func export_separate_climate_exrs(dir: String, file_prefix: String) -> bool:
	if not is_allocated():
		push_error("ClimateGrid.export_separate_climate_exrs: grid not allocated")
		return false
	_ensure_export_dir(dir)
	var dir_path: String = dir if dir.ends_with("/") else dir + "/"
	var all_ok: bool = true
	for face in range(FACE_COUNT):
		var fn: String = _EXR_FACE_NAMES[face]
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_elevation_" + fn + ".exr", face, 0
		):
			all_ok = false
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_temperature_" + fn + ".exr", face, 1
		):
			all_ok = false
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_precipitation_" + fn + ".exr", face, 2
		):
			all_ok = false
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_soil_wetness_" + fn + ".exr", face, 3
		):
			all_ok = false
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_biome_" + fn + ".exr", face, 4
		):
			all_ok = false
		if not _save_rf_channel_exr(
			dir_path + file_prefix + "climate_flow_" + fn + ".exr", face, 5
		):
			all_ok = false
	return all_ok


func _save_rf_channel_exr(path: String, face: int, channel: int) -> bool:
	var img := Image.create(face_resolution, face_resolution, false, Image.FORMAT_RF)
	for y in range(face_resolution):
		for x in range(face_resolution):
			var v: float = 0.0
			match channel:
				0:
					v = get_elevation(face, x, y)
				1:
					v = get_temperature(face, x, y)
				2:
					v = get_precipitation(face, x, y)
				3:
					v = get_soil_wetness(face, x, y)
				4:
					v = get_biome_index(face, x, y)
				_:
					v = get_flow_accumulation(face, x, y)
			img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))
	if img.save_exr(path) != OK:
		push_error("ClimateGrid: save_exr failed: %s" % path)
		return false
	return true


static func _ensure_export_dir(path: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var relative: String = path
	if relative.begins_with("user://"):
		relative = relative.substr("user://".length())
	if relative.ends_with("/"):
		relative = relative.substr(0, relative.length() - 1)
	dir.make_dir_recursive(relative)


func _get_map_range(map: PackedFloat32Array, default_max: float) -> Vector2:
	if not is_allocated() or map.is_empty():
		return Vector2(0.0, default_max)
	var v_min: float = map[0]
	var v_max: float = map[0]
	for v in map:
		v_min = minf(v_min, v)
		v_max = maxf(v_max, v)
	if is_equal_approx(v_min, v_max):
		v_max = v_min + 1.0
	return Vector2(v_min, v_max)


## Min/max over [member temperature_map] (requires [method is_allocated]).
func get_temperature_range() -> Vector2:
	return _get_map_range(temperature_map, 1.0)


## Min/max over [member precipitation_map] (annual precipitation, cm;
## requires [method is_allocated]).
func get_precipitation_range() -> Vector2:
	return _get_map_range(precipitation_map, MOISTURE_ANNUAL_PRECIP_CM_MAX)


## Fixed display span for [method build_precipitation_texture_array]:
## annual precipitation 0 … [constant MOISTURE_ANNUAL_PRECIP_CM_MAX] cm.
func get_precipitation_colormap_range() -> Vector2:
	return Vector2(0.0, MOISTURE_ANNUAL_PRECIP_CM_MAX)


## Min/max over [member soil_wetness_map] (annual cm; requires [method is_allocated]).
func get_soil_wetness_range() -> Vector2:
	return _get_map_range(soil_wetness_map, MOISTURE_ANNUAL_PRECIP_CM_MAX)


func get_soil_wetness_colormap_range() -> Vector2:
	return Vector2(0.0, MOISTURE_ANNUAL_PRECIP_CM_MAX)


func _build_rf_texture_array_from_channel_map(map: PackedFloat32Array) -> Texture2DArray:
	if not is_allocated():
		push_error("ClimateGrid._build_rf_texture_array_from_channel_map: grid not allocated")
		return null
	if map.size() != total_cell_count():
		push_error("ClimateGrid._build_rf_texture_array_from_channel_map: size mismatch")
		return null
	var w: int = face_resolution
	var h: int = face_resolution
	var cpf: int = cells_per_face()
	var images: Array[Image] = []
	for face in range(FACE_COUNT):
		var slice: PackedFloat32Array = map.slice(face * cpf, face * cpf + cpf)
		var bytes: PackedByteArray = slice.to_byte_array()
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, bytes)
		images.append(img)
	var tex := Texture2DArray.new()
	var err := tex.create_from_images(images)
	if err != OK:
		push_error("ClimateGrid: Texture2DArray.create_from_images failed (%d)" % err)
		return null
	return tex


## One RF layer per cube face; [method Image.create_from_data] per face
## (no [method Image.set_pixel] loops).
func build_elevation_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(elevation_map)


func build_temperature_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(temperature_map)


func build_precipitation_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(precipitation_map)


func build_soil_wetness_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(soil_wetness_map)


func build_biome_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(biome_index_map)


func build_flow_accumulation_texture_array() -> Texture2DArray:
	return _build_rf_texture_array_from_channel_map(flow_accumulation_map)
