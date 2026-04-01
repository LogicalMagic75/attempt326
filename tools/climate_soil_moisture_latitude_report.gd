extends SceneTree

## Headless zonal report: mean temperature (°C) and soil wetness (cm/year) by |latitude|.
## Earth-default pipeline: seed 1, face 512, t_eq 28.5, t_pole -17, neutral runtime overrides (ΔT=0, precip×1), river V1 on.
## Run: <godot.exe> --headless --path "<proj>" --script res://tools/climate_soil_moisture_latitude_report.gd
## Godot exe: repo-root godot.path (line 1), or GODOT / GODOT_EXECUTABLE, or godot on PATH — see .cursor/rules/godot-headless-path.mdc

const FACE_COUNT := 6
const FACE_RES := 512
const BAKER_SCRIPT := preload("res://Scripts/PlanetBaseTruthBaker.cs")
const TECTONICS_SCRIPT := preload("res://Scripts/TectonicPlates.cs")
const CLIMATE_SIM_SCRIPT := preload("res://Scripts/ClimateSimulator.cs")

## Absolute latitude belts (degrees), same layout as climate_latitude_validator.gd
const LAT_BANDS := [
	{"lo": 0.0, "hi": 15.0},
	{"lo": 15.0, "hi": 30.0},
	{"lo": 30.0, "hi": 45.0},
	{"lo": 45.0, "hi": 60.0},
	{"lo": 60.0, "hi": 75.0},
	{"lo": 75.0, "hi": 90.1},
]

## Matches [enum ClimateSimulator.BiomeID] names used by this project.
const BIOME_NAMES: PackedStringArray = [
	"Tundra",
	"Boreal forest",
	"Temperate grassland",
	"Temperate seasonal forest",
	"Temperate rainforest",
	"Subtropical desert",
	"Savannah",
	"Tropical seasonal forest",
	"Tropical rainforest",
	"Ice",
	"Ocean",
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
	var t_eq := 28.5
	var t_pole := -17.0
	sim.SetRuntimeGenerationOverrides(0.0, 1.0, 0.0)
	sim.CalculateBaseTemperature(grid, t_eq, t_pole, Callable())
	sim.CalculatePrecipitation(grid, Callable())
	sim.CalculateFlowAccumulation(grid, Callable())
	sim.CalculateSoilWetness(
		grid,
		{
			"enabled": true,
			"flow_threshold": 900.0,
			"flow_saturation": 6000.0,
			"bank_bonus_cm": 15.0,
			"radius_cells": 3,
			"decay_per_cell": 0.72,
			"arid_precip_cm": 40.0,
			"arid_bonus_scale": 0.8,
			"freeze_start_c": 0.0,
			"freeze_full_c": -8.0,
		},
		Callable()
	)
	sim.CalculateBiomes(grid, Callable())

	var bins_all: Array = []
	var bins_land: Array = []
	for band_i in range(LAT_BANDS.size()):
		bins_all.append(
			{
				"n": 0.0,
				"temp": 0.0,
				"soil": 0.0,
				"precip": 0.0,
			}
		)
		bins_land.append(
			{
				"n": 0.0,
				"temp": 0.0,
				"soil": 0.0,
				"precip": 0.0,
				"biome_hist": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
			}
		)

	var res := grid.face_resolution
	var f_res := maxf(float(res), 1.0)
	var cpf := res * res
	var elev: PackedFloat32Array = grid.elevation_map
	var biome_map: PackedFloat32Array = grid.biome_index_map
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
				var t0 := float(grid.temperature_map[lin])
				var s0 := float(grid.soil_wetness_map[lin])
				var p0 := float(grid.precipitation_map[lin])
				var h0 := float(elev[lin])

				var b_all: Dictionary = bins_all[band_idx]
				b_all["n"] = float(b_all["n"]) + 1.0
				b_all["temp"] = float(b_all["temp"]) + t0
				b_all["soil"] = float(b_all["soil"]) + s0
				b_all["precip"] = float(b_all["precip"]) + p0
				bins_all[band_idx] = b_all

				if h0 >= 0.0:
					var b_land: Dictionary = bins_land[band_idx]
					b_land["n"] = float(b_land["n"]) + 1.0
					b_land["temp"] = float(b_land["temp"]) + t0
					b_land["soil"] = float(b_land["soil"]) + s0
					b_land["precip"] = float(b_land["precip"]) + p0
					var bid := int(floor(float(biome_map[lin]) + 0.5))
					bid = clampi(bid, 0, BIOME_NAMES.size() - 1)
					var hist: Array = b_land["biome_hist"]
					hist[bid] = int(hist[bid]) + 1
					b_land["biome_hist"] = hist
					bins_land[band_idx] = b_land

	print("=== Soil moisture & temperature by latitude ===")
	var setup := "Setup: seed=1, face_res=%d, t_equator=%.1f C, t_pole=%.1f C" % [FACE_RES, t_eq, t_pole]
	print(setup)
	print(
		"Soil = annual precip + river bank bonus (V1); ocean cells = precip only."
	)
	print(
		"Whittaker biome = mean (T, soil) in diagram. Modal biome = majority class on land cells."
	)
	print("")
	var hdr_all := (
		"ALL_CELLS: bin | cells | mean_temp_C | mean_soil_cm_yr | mean_precip_cm_yr | "
		+ "whittaker_from_mean"
	)
	print(hdr_all)
	for i in range(LAT_BANDS.size()):
		var ref: Dictionary = LAT_BANDS[i]
		var b: Dictionary = bins_all[i]
		var n := maxf(float(b["n"]), 1.0)
		var t_mean := float(b["temp"]) / n
		var s_mean := float(b["soil"]) / n
		var label := "%02d-%02d" % [int(round(float(ref["lo"]))), int(round(float(ref["hi"])))]
		var bio := _whittaker_biome_label(t_mean, s_mean)
		print(
			(
				"%s | %.0f | %.2f | %.2f | %.2f | %s"
				% [label, float(b["n"]), t_mean, s_mean, float(b["precip"]) / n, bio]
			)
		)

	print("")
	var hdr_land := (
		"LAND (elev>=0): bin | cells | mean_temp_C | mean_soil_cm_yr | "
		+ "mean_precip_cm_yr | mean_extra_cm | whittaker_from_mean | modal_biome | modal_%"
	)
	print(hdr_land)
	for i in range(LAT_BANDS.size()):
		var ref2: Dictionary = LAT_BANDS[i]
		var bl: Dictionary = bins_land[i]
		var nl := maxf(float(bl["n"]), 1.0)
		var label2 := "%02d-%02d" % [int(round(float(ref2["lo"]))), int(round(float(ref2["hi"])))]
		var pbar := float(bl["precip"]) / nl
		var sbar := float(bl["soil"]) / nl
		var t_land := float(bl["temp"]) / nl
		var bio_l := _whittaker_biome_label(t_land, sbar)
		var hist_l: Array = bl["biome_hist"]
		var modal_id := _modal_biome_id(hist_l)
		var modal_name := _biome_name(modal_id)
		var modal_share := 100.0 * float(hist_l[modal_id]) / maxf(float(bl["n"]), 1.0)
		print(
			(
				"%s | %.0f | %.2f | %.2f | %.2f | %.2f | %s | %s | %.1f"
				% [label2, float(bl["n"]), t_land, sbar, pbar, sbar - pbar, bio_l, modal_name, modal_share]
			)
		)

	print("")
	print("LAND top-3 biome mix (by land cell count in bin):")
	for j in range(LAT_BANDS.size()):
		var ref3: Dictionary = LAT_BANDS[j]
		var bl3: Dictionary = bins_land[j]
		var n3 := maxf(float(bl3["n"]), 1.0)
		var label3 := "%02d-%02d" % [int(round(float(ref3["lo"]))), int(round(float(ref3["hi"])))]
		var hist3: Array = bl3["biome_hist"]
		print("  %s | %s" % [label3, _format_top_biomes(hist3, n3, 3)])

	quit()

func _whittaker_biome_label(temp_c: float, soil_cm_yr: float) -> String:
	var bid := _whittaker_biome_id(temp_c, soil_cm_yr)
	return "%s (%d)" % [_biome_name(bid), bid]


func _whittaker_biome_id(temp_c: float, soil_cm_yr: float) -> int:
	if temp_c < -15.0:
		return 9
	var t := temp_c
	var p := soil_cm_yr
	if t < -5.0:
		if p < 120.0:
			return 0
		return 1
	if t < 5.0:
		if p < 50.0:
			return 5
		if p < 120.0:
			return 1
		return 3
	if t < 20.0:
		if p < 50.0:
			return 5
		if p < 100.0:
			return 2
		if p < 250.0:
			return 3
		return 4
	if p < 50.0:
		return 5
	if p < 100.0:
		return 6
	if p < 250.0:
		return 7
	return 8


func _format_top_biomes(hist: Array, n_land: float, k: int) -> String:
	var pairs: Array[Vector2i] = []
	for idx in range(mini(hist.size(), BIOME_NAMES.size())):
		var c := int(hist[idx])
		if c > 0:
			pairs.append(Vector2i(c, idx))
	pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	var parts: PackedStringArray = []
	for t in range(mini(k, pairs.size())):
		var pr: Vector2i = pairs[t]
		var pct := 100.0 * float(pr.x) / maxf(n_land, 1.0)
		var nm := _biome_name(pr.y)
		parts.append("%s %.1f%%" % [nm, pct])
	return ", ".join(parts)


func _modal_biome_id(hist: Array) -> int:
	var best_id := 0
	var best_n := -1
	for i in range(hist.size()):
		var n := int(hist[i])
		if n > best_n:
			best_n = n
			best_id = i
	return best_id


func _biome_name(bid: int) -> String:
	if bid >= 0 and bid < BIOME_NAMES.size():
		return BIOME_NAMES[bid]
	return "Unknown"


func _band_for_lat(lat_deg: float) -> int:
	for i in range(LAT_BANDS.size()):
		var b: Dictionary = LAT_BANDS[i]
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
			return Vector3(1, 0, 0)
		1:
			return Vector3(-1, 0, 0)
		2:
			return Vector3(0, 1, 0)
		3:
			return Vector3(0, -1, 0)
		4:
			return Vector3(0, 0, 1)
		5:
			return Vector3(0, 0, -1)
		_:
			return Vector3(0, 0, 1)
