extends SceneTree

## Zonal validation vs coarse **all-surface** (ocean + land) instrumental belts — same sampling as latitude bins
## over the cube-sphere. Uses **neutral** runtime overrides (precip×1, ΔT=0); tune [ClimateSimulator] instead of UI multipliers.
## Run: <godot.exe> --headless --path "<proj>" --script res://tools/climate_latitude_validator.gd
## Godot exe: repo-root godot.path (line 1), or GODOT / GODOT_EXECUTABLE, or godot on PATH — see .cursor/rules/godot-headless-path.mdc

const FACE_COUNT := 6
const FACE_RES := 512
const BAKER_SCRIPT := preload("res://Scripts/PlanetBaseTruthBaker.cs")
const TECTONICS_SCRIPT := preload("res://Scripts/TectonicPlates.cs")
const CLIMATE_SIM_SCRIPT := preload("res://Scripts/ClimateSimulator.cs")

const EARTH_BANDS := [
	{"lo": 0.0, "hi": 15.0, "temp_c": 26.0, "precip_cm": 180.0},
	{"lo": 15.0, "hi": 30.0, "temp_c": 21.0, "precip_cm": 105.0},
	{"lo": 30.0, "hi": 45.0, "temp_c": 11.0, "precip_cm": 85.0},
	{"lo": 45.0, "hi": 60.0, "temp_c": 2.0, "precip_cm": 75.0},
	{"lo": 60.0, "hi": 75.0, "temp_c": -8.0, "precip_cm": 55.0},
	{"lo": 75.0, "hi": 90.1, "temp_c": -20.0, "precip_cm": 25.0},
]

func _init() -> void:
	var grid := ClimateGrid.new()
	grid.face_resolution = FACE_RES
	grid.allocate()

	var baker: Object = BAKER_SCRIPT.new()
	var tect: Object = TECTONICS_SCRIPT.new()
	baker.Tectonics = tect
	baker.SetWorldSeed(1)
	baker.GenerateBaseTruth(grid)

	var sim: Object = CLIMATE_SIM_SCRIPT.new()
	# Earth-default validation: neutral runtime overrides (tune base sim, not UI multipliers).
	sim.SetRuntimeGenerationOverrides(0.0, 1.0, 0.0)
	sim.CalculateBaseTemperature(grid, 28.5, -17.0, Callable())
	sim.CalculatePrecipitation(grid, Callable())

	var bins := []
	for _i in range(EARTH_BANDS.size()):
		bins.append({"count": 0.0, "temp_sum": 0.0, "precip_sum": 0.0})

	var res := grid.face_resolution
	var f_res := maxf(float(res), 1.0)
	var cpf := res * res
	for face in range(FACE_COUNT):
		for y in range(res):
			for x in range(res):
				var uv := Vector2((x + 0.5) / f_res, (y + 0.5) / f_res)
				var dir := _face_uv01_to_unit_direction(face, uv)
				var lat_deg := absf(rad_to_deg(asin(clampf(dir.y, -1.0, 1.0))))
				var band_idx := _band_for_lat(lat_deg)
				if band_idx < 0:
					continue
				var lin := face * cpf + y * res + x
				var bucket: Dictionary = bins[band_idx]
				bucket["count"] = float(bucket["count"]) + 1.0
				bucket["temp_sum"] = float(bucket["temp_sum"]) + float(grid.temperature_map[lin])
				bucket["precip_sum"] = float(bucket["precip_sum"]) + float(grid.precipitation_map[lin])
				bins[band_idx] = bucket

	print("LAT_BIN,PROJECT_TEMP_C,EARTH_TEMP_C,DELTA_TEMP_C,PROJECT_PRECIP_CM,EARTH_PRECIP_CM,DELTA_PRECIP_CM")
	var temp_abs_sum := 0.0
	var precip_abs_sum := 0.0
	for i in range(EARTH_BANDS.size()):
		var ref: Dictionary = EARTH_BANDS[i]
		var b: Dictionary = bins[i]
		var n := maxf(float(b["count"]), 1.0)
		var t_proj := float(b["temp_sum"]) / n
		var p_proj := float(b["precip_sum"]) / n
		var t_ref := float(ref["temp_c"])
		var p_ref := float(ref["precip_cm"])
		var dt := t_proj - t_ref
		var dp := p_proj - p_ref
		temp_abs_sum += absf(dt)
		precip_abs_sum += absf(dp)
		var label := "%02d-%02d" % [int(round(float(ref["lo"]))), int(round(float(ref["hi"])))]
		print("%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [label, t_proj, t_ref, dt, p_proj, p_ref, dp])

	var mae_temp := temp_abs_sum / float(EARTH_BANDS.size())
	var mae_precip := precip_abs_sum / float(EARTH_BANDS.size())
	print("MAE_TEMP_C=%.2f" % mae_temp)
	print("MAE_PRECIP_CM=%.2f" % mae_precip)
	print("PASS_TEMP=%s" % (str(mae_temp <= 4.0)))
	print("PASS_PRECIP=%s" % (str(mae_precip <= 35.0)))
	quit()

func _band_for_lat(lat_deg: float) -> int:
	for i in range(EARTH_BANDS.size()):
		var b: Dictionary = EARTH_BANDS[i]
		if lat_deg >= float(b["lo"]) and lat_deg < float(b["hi"]):
			return i
	return -1

func _face_uv01_to_unit_direction(face: int, uv: Vector2) -> Vector3:
	var normal := _face_center_normal(face)
	var axis_a := Vector3(normal.y, normal.z, normal.x)
	var axis_b := normal.cross(axis_a)
	var cube_p := normal + (uv.x - 0.5) * 2.0 * axis_a + (uv.y - 0.5) * 2.0 * axis_b
	return cube_p.normalized()

func _face_center_normal(face: int) -> Vector3:
	match face:
		0:
			return Vector3(1, 0, 0) # RIGHT
		1:
			return Vector3(-1, 0, 0) # LEFT
		2:
			return Vector3(0, 1, 0) # TOP
		3:
			return Vector3(0, -1, 0) # BOTTOM
		4:
			return Vector3(0, 0, 1) # FRONT
		5:
			return Vector3(0, 0, -1) # BACK
		_:
			return Vector3(0, 0, 1)
