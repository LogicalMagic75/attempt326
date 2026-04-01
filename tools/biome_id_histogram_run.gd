extends SceneTree

## Headless: GenerateBaseTruth + full climate pipeline, then print ClimateSimulator.BiomeIdHistogram (all cells).
## Run: godot --headless --path "<proj>" --script res://tools/biome_id_histogram_run.gd
## Build C# with Debug before headless (Godot loads .godot/mono/temp/bin/Debug/Attempt326.dll by default):
##   dotnet build "<proj>/attempt-326.csproj" -c Debug

const FACE_RES := 512
const BAKER_SCRIPT := preload("res://Scripts/PlanetBaseTruthBaker.cs")
const TECTONICS_SCRIPT := preload("res://Scripts/TectonicPlates.cs")
const CLIMATE_SIM_SCRIPT := preload("res://Scripts/ClimateSimulator.cs")

## Mirrors [method ClimateSimulator.BiomeIdHistogram] (all 6×res² cells).
func _biome_id_histogram_all_cells(grid: ClimateGrid) -> PackedInt64Array:
	var hist := PackedInt64Array()
	hist.resize(16)
	hist.fill(0)
	if not grid.is_allocated():
		return hist
	var res := grid.face_resolution
	var cpf := res * res
	var bio: PackedFloat32Array = grid.biome_index_map
	for face in range(6):
		for y in range(res):
			for x in range(res):
				var lin := face * cpf + y * res + x
				var bi := clampi(int(floor(float(bio[lin]) + 0.5)), 0, 15)
				hist[bi] = int(hist[bi]) + 1
	return hist


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
	# Full pipeline in deferred frame so stdout/stderr flush reliably under --script.
	call_deferred("_run")


func _run() -> void:
	var world_seed := 1
	var t_eq := 28.5
	var t_pole := -17.0
	var land_pcts: Array[float] = [100.0, 25.0]

	var grid := ClimateGrid.new()
	grid.face_resolution = FACE_RES
	grid.allocate()

	var baker: Object = BAKER_SCRIPT.new()
	var tect: Object = TECTONICS_SCRIPT.new()
	baker.Tectonics = tect
	baker.SetWorldSeed(world_seed)

	var tuning := ClimateSimTuning.new()
	tuning.apply_to_simulator()
	var sea_msl := float(tuning.generation_sea_level_offset_m)

	var dump_all := PackedStringArray()

	for land_pct in land_pcts:
		baker.call("SetTargetLandAreaPercent", land_pct)
		baker.GenerateBaseTruth(grid)

		var sim: Object = CLIMATE_SIM_SCRIPT.new()
		sim.SetRuntimeGenerationOverrides(0.0, 1.0, sea_msl)
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

		var hist := _biome_id_histogram_all_cells(grid)
		var total := 0
		for i in range(hist.size()):
			total += int(hist[i])

		print(
			(
				"=== BiomeIdHistogram land=%.0f%% seed=%d res=%d t_eq=%.1f t_pole=%.1f MSL=%.1f total_cells=%d"
				% [land_pct, world_seed, FACE_RES, t_eq, t_pole, sea_msl, total]
			)
		)
		dump_all.append(
			(
				"=== BiomeIdHistogram land=%.0f%% seed=%d res=%d t_eq=%.1f t_pole=%.1f MSL=%.1f total_cells=%d"
				% [land_pct, world_seed, FACE_RES, t_eq, t_pole, sea_msl, total]
			)
		)
		for i in range(mini(BIOME_NAMES.size(), hist.size())):
			var c := int(hist[i])
			var pct := 100.0 * float(c) / float(maxi(total, 1))
			print("  id %2d %-24s %10d  %6.2f%%" % [i, BIOME_NAMES[i], c, pct])
			dump_all.append("  id %2d %-24s %10d  %6.2f%%" % [i, BIOME_NAMES[i], c, pct])
		for j in range(BIOME_NAMES.size(), hist.size()):
			var c2 := int(hist[j])
			if c2 != 0:
				var pct2 := 100.0 * float(c2) / float(maxi(total, 1))
				print("  id %2d (extra)              %10d  %6.2f%%" % [j, c2, pct2])
				dump_all.append("  id %2d (extra)              %10d  %6.2f%%" % [j, c2, pct2])

	var out_path := ProjectSettings.globalize_path("user://_biome_hist_last.txt")
	var df := FileAccess.open(out_path, FileAccess.WRITE)
	if df:
		df.store_string("\n".join(dump_all))
		df.close()
	print("Wrote ", out_path)
	var repo_path := ProjectSettings.globalize_path("res://tools/_biome_hist_last_run.txt")
	var rf := FileAccess.open(repo_path, FileAccess.WRITE)
	if rf:
		rf.store_string("\n".join(dump_all))
		rf.close()
		print("Wrote ", repo_path)

	call_deferred("quit")
