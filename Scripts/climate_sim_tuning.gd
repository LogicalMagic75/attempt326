class_name ClimateSimTuning
extends Resource

const _CLIMATE_SIM_CS := preload("res://Scripts/ClimateSimulator.cs")

@export_group("Maritime (moisture along prevailing-wind ray)")
@export var maritime_enabled: bool = true
## Higher = weight upwind ocean samples nearer the cell more (power on 0..1 along ~2.2 Mm fetch). Neutral ~2.
@export_range(0.25, 8.0, 0.05) var moisture_upwind_near_cell_weight_power: float = 2.0
@export var maritime_coast_precip_factor: float = 1.6
@export var maritime_interior_precip_factor: float = 0.85

@export_group("Orography (uplift along wind path)")
@export var orographic_uplift_cm_per_km: float = 24.0
@export var orographic_uplift_max_cm: float = 150.0

@export_group("Rain shadow (barrier height / leeward distance)")
## Dimensionless scale in shadow = clamp(scale * h_eff_m / max(geodesic_m, floor_m), 0, 1). ~14 aligns mid-latitude major ranges with observed leeward aridity (Columbia Basin, Patagonia, NZ Otago scale); lower = weaker drying.
@export_range(1.0, 40.0, 0.5) var rain_shadow_h_over_d_scale: float = 14.0
## Minimum crest-to-cell distance (m) used in the ratio (avoids singularity). ~40 km matches Earth-like foothill-to-basin scale; prior 85 km diluted shadows vs references (Cascades, Himalaya, Andes).
@export_range(5000.0, 120000.0, 1000.0) var rain_shadow_distance_floor_m: float = 42000.0
## Crest must be at least this MSL (m) to count as the upwind barrier.
@export var rain_shadow_barrier_elev_min_m: float = 600.0
## Upwind moisture ray length (m) on the sphere toward prevailing wind. ~2000–2500 km typical before coastal ranges.
@export var rain_shadow_upwind_range_m: float = 2_200_000.0

@export_group("Temperature (land bias, not precipitation)")
@export_range(0.0, 10.0, 0.1) var subtropical_land_warm_bias_peak_c: float = 6.0
@export_range(0.0, 6.0, 0.1) var midlatitude_land_warm_bias_peak_c: float = 2.2

@export_group("Runtime generation (neutral Earth calibration)")
## Positive = higher MSL for the climate ocean mask (runtime sea-level offset on the simulator).
## At 512², baked hypsometry is mostly above the narrow coastal band MSL can flood, so global ocean stays
## near ~two-thirds; this offset still removes some low-elevation land for Whittaker balance.
@export var generation_sea_level_offset_m: float = 195.0

@export_group("Debug")
@export var debug_log_biome_histogram: bool = false


func apply_to_simulator() -> void:
	_CLIMATE_SIM_CS.new().ApplyTuningPack(
		{
			"maritime_enabled": maritime_enabled,
			"moisture_upwind_near_cell_weight_power": moisture_upwind_near_cell_weight_power,
			"maritime_coast_precip_factor": maritime_coast_precip_factor,
			"maritime_interior_precip_factor": maritime_interior_precip_factor,
			"orographic_uplift_cm_per_km": orographic_uplift_cm_per_km,
			"orographic_uplift_max_cm": orographic_uplift_max_cm,
			"rain_shadow_h_over_d_scale": rain_shadow_h_over_d_scale,
			"rain_shadow_distance_floor_m": rain_shadow_distance_floor_m,
			"rain_shadow_barrier_elev_min_m": rain_shadow_barrier_elev_min_m,
			"rain_shadow_upwind_range_m": rain_shadow_upwind_range_m,
			"subtropical_land_warm_bias_peak_c": subtropical_land_warm_bias_peak_c,
			"midlatitude_land_warm_bias_peak_c": midlatitude_land_warm_bias_peak_c,
			"debug_log_biome_histogram": debug_log_biome_histogram,
		}
	)
