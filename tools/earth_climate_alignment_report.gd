extends SceneTree

## Headless Earth-alignment analytics: zonal (all cells vs land-only) T/P, biome histogram, MAE vs belts.
## Uses neutral runtime overrides (no UI precip multiplier / temp offset) — tune [ClimateSimulator] and exports instead.
## Run: godot --headless --path "<proj>" --script res://tools/earth_climate_alignment_report.gd

const FACE_COUNT := 6
const FACE_RES := 512
const BAKER_SCRIPT := preload("res://Scripts/PlanetBaseTruthBaker.cs")
const TECTONICS_SCRIPT := preload("res://Scripts/TectonicPlates.cs")
const CLIMATE_SIM_SCRIPT := preload("res://Scripts/ClimateSimulator.cs")

## Same instrumental-style belts as [member climate_latitude_validator.EARTH_BANDS].
const EARTH_BANDS := [
	{"lo": 0.0, "hi": 15.0, "temp_c": 26.0, "precip_cm": 180.0},
	{"lo": 15.0, "hi": 30.0, "temp_c": 21.0, "precip_cm": 105.0},
	{"lo": 30.0, "hi": 45.0, "temp_c": 11.0, "precip_cm": 85.0},
	{"lo": 45.0, "hi": 60.0, "temp_c": 2.0, "precip_cm": 75.0},
	{"lo": 60.0, "hi": 75.0, "temp_c": -8.0, "precip_cm": 55.0},
	{"lo": 75.0, "hi": 90.1, "temp_c": -20.0, "precip_cm": 25.0},
]

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

## Land-only Whittaker ids 0..9 — order-of-magnitude global land-cover mix (sums 100); TRF/desert bands
## match broad Earth totals at ~100 km scales, not pixel-perfect Köppen on a procedural mask.
const EARTH_LAND_BIOME_REF_PCT: Array[float] = [
	5.0, 12.0, 10.0, 17.0, 14.0, 3.0, 7.0, 16.0, 3.0, 13.0,
]

func _init() -> void:
	var world_seed := 1
	var t_eq := 28.5
	var t_pole := -17.0
	var temp_offset_c := 0.0
	var precip_mult := 1.0

	var grid := ClimateGrid.new()
	grid.face_resolution = FACE_RES
	grid.allocate()

	var baker: Object = BAKER_SCRIPT.new()
	var tect: Object = TECTONICS_SCRIPT.new()
	baker.Tectonics = tect
	baker.SetWorldSeed(world_seed)
	baker.GenerateBaseTruth(grid)

	var tuning := ClimateSimTuning.new()
	tuning.debug_log_biome_histogram = true
	tuning.apply_to_simulator()
	var sea_msl := float(tuning.generation_sea_level_offset_m)

	var sim: Object = CLIMATE_SIM_SCRIPT.new()
	sim.SetRuntimeGenerationOverrides(temp_offset_c, precip_mult, sea_msl)
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

	print("=== earth_climate_alignment_report ===")
	print(
		(
			"Setup: seed=%d res=%d t_eq=%.1f t_pole=%.1f runtime ΔT=%.2f °C precip×=%.3f MSL=%.1fm"
			% [world_seed, FACE_RES, t_eq, t_pole, temp_offset_c, precip_mult, sea_msl]
		)
	)
	print("")

	var zonal := _zonal_bins(grid)
	_print_zonal_vs_earth(zonal, true)
	_print_zonal_vs_earth(zonal, false)
	_print_mae(zonal, true)
	_print_mae(zonal, false)
	print("")
	var bh := _global_land_biome_histogram(grid)
	_print_biome_table(bh)
	_print_biome_earth_mae(bh)
	print("")
	print("CSV_ALL: LAT_BIN,MEAN_TEMP_C,MEAN_PRECIP_CM,CELLS")
	_print_csv(zonal, true)
	print("CSV_LAND: LAT_BIN,MEAN_TEMP_C,MEAN_PRECIP_CM,LAND_CELLS")
	_print_csv(zonal, false)
	quit()

func _zonal_bins(grid: ClimateGrid) -> Dictionary:
	var bins_all: Array = []
	var bins_land: Array = []
	for _i in range(EARTH_BANDS.size()):
		bins_all.append({"n": 0, "temp": 0.0, "precip": 0.0})
		bins_land.append({"n": 0, "temp": 0.0, "precip": 0.0})

	var res := grid.face_resolution
	var f_res := maxf(float(res), 1.0)
	var cpf := res * res
	var elev: PackedFloat32Array = grid.elevation_map
	var sea: float = 0.0

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
				var p0 := float(grid.precipitation_map[lin])
				var ba: Dictionary = bins_all[band_idx]
				ba["n"] = int(ba["n"]) + 1
				ba["temp"] = float(ba["temp"]) + t0
				ba["precip"] = float(ba["precip"]) + p0
				bins_all[band_idx] = ba
				if float(elev[lin]) >= sea:
					var bl: Dictionary = bins_land[band_idx]
					bl["n"] = int(bl["n"]) + 1
					bl["temp"] = float(bl["temp"]) + t0
					bl["precip"] = float(bl["precip"]) + p0
					bins_land[band_idx] = bl

	return {"all": bins_all, "land": bins_land}

func _print_zonal_vs_earth(zonal: Dictionary, use_all_cells: bool) -> void:
	var key := "all" if use_all_cells else "land"
	var label := "ZONAL (all surface cells)" if use_all_cells else "ZONAL (land only, elev>=0)"
	var bins: Array = zonal[key]
	print(label)
	print("bin |cells| mean_T |ref_T |dT | mean_P |ref_P |dP")
	for i in range(EARTH_BANDS.size()):
		var ref: Dictionary = EARTH_BANDS[i]
		var b: Dictionary = bins[i]
		var n := maxi(int(b["n"]), 1)
		var t_m := float(b["temp"]) / float(n)
		var p_m := float(b["precip"]) / float(n)
		var dt := t_m - float(ref["temp_c"])
		var dp := p_m - float(ref["precip_cm"])
		var lab := "%02d-%02d" % [int(ref["lo"]), int(ref["hi"])]
		print(
			"%s | %d | %.2f | %.1f | %+.2f | %.2f | %.1f | %+.2f"
			% [lab, int(b["n"]), t_m, float(ref["temp_c"]), dt, p_m, float(ref["precip_cm"]), dp]
		)
	print("")

func _print_mae(zonal: Dictionary, use_all_cells: bool) -> void:
	var key := "all" if use_all_cells else "land"
	var bins: Array = zonal[key]
	var s_t := 0.0
	var s_p := 0.0
	for i in range(EARTH_BANDS.size()):
		var ref: Dictionary = EARTH_BANDS[i]
		var b: Dictionary = bins[i]
		var n := maxi(int(b["n"]), 1)
		var t_m := float(b["temp"]) / float(n)
		var p_m := float(b["precip"]) / float(n)
		s_t += absf(t_m - float(ref["temp_c"]))
		s_p += absf(p_m - float(ref["precip_cm"]))
	var label := "MAE_ALL" if use_all_cells else "MAE_LAND"
	print("%s: temp=%.3f °C precip=%.3f cm/yr" % [label, s_t / 6.0, s_p / 6.0])

func _print_csv(zonal: Dictionary, use_all_cells: bool) -> void:
	var key := "all" if use_all_cells else "land"
	var bins: Array = zonal[key]
	for i in range(EARTH_BANDS.size()):
		var ref: Dictionary = EARTH_BANDS[i]
		var b: Dictionary = bins[i]
		var n := maxi(int(b["n"]), 1)
		var t_m := float(b["temp"]) / float(n)
		var p_m := float(b["precip"]) / float(n)
		var lab := "%02d-%02d" % [int(ref["lo"]), int(ref["hi"])]
		print("%s,%.4f,%.4f,%d" % [lab, t_m, p_m, int(b["n"])])

func _global_land_biome_histogram(grid: ClimateGrid) -> Dictionary:
	var hist: PackedInt64Array = PackedInt64Array()
	hist.resize(16)
	hist.fill(0)
	var land_n := 0
	var elev: PackedFloat32Array = grid.elevation_map
	var bio: PackedFloat32Array = grid.biome_index_map
	for i in range(elev.size()):
		if elev[i] < 0.0:
			continue
		land_n += 1
		var id := int(floor(float(bio[i]) + 0.5))
		id = clampi(id, 0, hist.size() - 1)
		hist[id] = int(hist[id]) + 1
	return {"hist": hist, "land_n": land_n}


func _print_biome_table(bh: Dictionary) -> void:
	var hist: PackedInt64Array = bh["hist"]
	var land_n: int = int(bh["land_n"])
	print("GLOBAL land biomes (elev>=0, Whittaker class):")
	if land_n < 1:
		print("  (no land cells)")
		return
	for id in range(mini(BIOME_NAMES.size(), hist.size())):
		var c := int(hist[id])
		if id > 9:
			continue
		var sim_pct := 100.0 * float(c) / float(land_n)
		var ref_pct := float(EARTH_LAND_BIOME_REF_PCT[id]) if id < EARTH_LAND_BIOME_REF_PCT.size() else 0.0
		print(
			"  %2d %-26s %8d  sim %5.2f%%  ref %5.2f%%  Δ%+5.2f"
			% [id, BIOME_NAMES[id], c, sim_pct, ref_pct, sim_pct - ref_pct]
		)
	for id in range(mini(BIOME_NAMES.size(), hist.size())):
		if id <= 9:
			continue
		var c2 := int(hist[id])
		if c2 == 0:
			continue
		var pct2 := 100.0 * float(c2) / float(land_n)
		print("  %2d %-26s %8d  (%5.2f%%)" % [id, BIOME_NAMES[id], c2, pct2])


func _print_biome_earth_mae(bh: Dictionary) -> void:
	var hist: PackedInt64Array = bh["hist"]
	var land_n: int = int(bh["land_n"])
	if land_n < 1:
		return
	var mae := 0.0
	for id in range(10):
		var c := float(hist[id])
		var sim_pct := 100.0 * c / float(land_n)
		var ref_pct := float(EARTH_LAND_BIOME_REF_PCT[id])
		mae += absf(sim_pct - ref_pct)
	var mae_mean := mae / 10.0
	print("MAE_BIOME_PCT_0_9=%.2f  (mean |Δ%%| vs synthesis refs)" % mae_mean)
	print("PASS_BIOME_MAE=%s  (threshold 6.0 %% points)" % str(mae_mean <= 6.0))

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
