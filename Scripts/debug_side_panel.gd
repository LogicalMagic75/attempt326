class_name DebugSidePanel
extends PanelContainer

## Right debug strip (tiled layout): scrollable text, pipeline progress (bar + task),
## and a [VBoxContainer] for generation controls. Visualization toggles + biome key live in
## [VisualizationPanel] on the left; this script still wires them via scene-unique names.
## Lookup: get_tree().get_first_node_in_group(&"debug_side_panel")

const GROUP_NAME := &"debug_side_panel"
## Rainfall slider label only; [ClimateSimulator] no longer applies a global precip multiplier.
const _ORBIT_RIG_SCRIPT: GDScript = preload("res://Scripts/camera_orbit_rig.gd")
const _BAKER_SCR := preload("res://Scripts/PlanetBaseTruthBaker.cs")
## Assign a [ClimateSimTuning] resource in the inspector to override [ClimateSimulator]
## defaults.
@export var climate_tuning: Resource

@export var camera_orbit_rig_path: NodePath = ^"../PlanetColumn/AspectRatioContainer/SubViewportContainer/SubViewport/CameraOrbitRig"
@export var planet_base_truth_baker_path: NodePath = ^"../PlanetColumn/AspectRatioContainer/SubViewportContainer/SubViewport/PlanetBaseTruthBaker"
@export var planet_path: NodePath = ^"../PlanetColumn/AspectRatioContainer/SubViewportContainer/SubViewport/Planet"

@export_group("Climate (base temperature)")
@export var climate_equator_temp_c: float = 28.5:
	set(value):
		if not is_equal_approx(climate_equator_temp_c, value):
			_climatology_valid = false
		climate_equator_temp_c = value
@export var climate_pole_temp_c: float = -17.0:
	set(value):
		if not is_equal_approx(climate_pole_temp_c, value):
			_climatology_valid = false
		climate_pole_temp_c = value

@export_group("Climate (river moisture V1)")
@export var river_moisture_v1_enabled: bool = true:
	set(value):
		if river_moisture_v1_enabled != value:
			_climatology_valid = false
		river_moisture_v1_enabled = value
@export_range(0.0, 20000.0, 25.0, "or_greater")
var river_moisture_flow_threshold: float = 900.0:
	set(value):
		if not is_equal_approx(river_moisture_flow_threshold, value):
			_climatology_valid = false
		river_moisture_flow_threshold = value
@export_range(100.0, 100000.0, 50.0, "or_greater")
var river_moisture_flow_saturation: float = 6000.0:
	set(value):
		if not is_equal_approx(river_moisture_flow_saturation, value):
			_climatology_valid = false
		river_moisture_flow_saturation = value
@export_range(0.0, 120.0, 0.5, "or_greater")
var river_moisture_bank_bonus_cm: float = 15.0:
	set(value):
		if not is_equal_approx(river_moisture_bank_bonus_cm, value):
			_climatology_valid = false
		river_moisture_bank_bonus_cm = value
@export_range(0, 8, 1)
var river_moisture_radius_cells: int = 3:
	set(value):
		if river_moisture_radius_cells != value:
			_climatology_valid = false
		river_moisture_radius_cells = value
@export_range(0.0, 1.0, 0.01)
var river_moisture_decay_per_cell: float = 0.72:
	set(value):
		if not is_equal_approx(river_moisture_decay_per_cell, value):
			_climatology_valid = false
		river_moisture_decay_per_cell = value
@export_range(0.0, 200.0, 1.0, "or_greater")
var river_moisture_arid_precip_cm: float = 40.0:
	set(value):
		if not is_equal_approx(river_moisture_arid_precip_cm, value):
			_climatology_valid = false
		river_moisture_arid_precip_cm = value
@export_range(0.0, 1.0, 0.01)
var river_moisture_arid_bonus_scale: float = 0.8:
	set(value):
		if not is_equal_approx(river_moisture_arid_bonus_scale, value):
			_climatology_valid = false
		river_moisture_arid_bonus_scale = value
@export var river_moisture_freeze_start_c: float = 0.0:
	set(value):
		if not is_equal_approx(river_moisture_freeze_start_c, value):
			_climatology_valid = false
		river_moisture_freeze_start_c = value
@export var river_moisture_freeze_full_c: float = -8.0:
	set(value):
		if not is_equal_approx(river_moisture_freeze_full_c, value):
			_climatology_valid = false
		river_moisture_freeze_full_c = value

@onready var _debug_label: Label = %DebugLabel
@onready var _elevation_label: Label = %ElevationReadout
@onready var controls_host: VBoxContainer = %ControlsHost
@onready var _world_seed_spin: SpinBox = %WorldSeedSpin
@onready var _random_seed_button: Button = %RandomSeedButton
@onready var _generate_base_data_button: Button = %GenerateBaseDataButton
@onready var _export_climate_exrs_button: Button = %ExportClimateExrsButton
@onready var _elevation_viz_check: CheckButton = %ElevationVizCheck
@onready var _temperature_viz_check: CheckButton = %TemperatureVizCheck
@onready var _moisture_viz_check: CheckButton = %MoistureVizCheck
@onready var _biome_viz_check: CheckButton = %BiomeVizCheck
@onready var _biome_legend_box: VBoxContainer = %BiomeLegendBox
@onready var _land_area_slider: HSlider = %LandAreaSlider
@onready var _land_area_value_label: Label = %LandAreaValueLabel
@onready var _gen_temp_slider: HSlider = %GenTempSlider
@onready var _gen_temp_value_label: Label = %GenTempValueLabel
@onready var _gen_rain_slider: HSlider = %GenRainSlider
@onready var _gen_rain_value_label: Label = %GenRainValueLabel
@onready var _gen_ocean_slider: HSlider = %GenOceanSlider
@onready var _gen_ocean_value_label: Label = %GenOceanValueLabel
@onready var _show_precip_curve_button: Button = %ShowPrecipCurveButton
@onready var _show_temp_curve_button: Button = %ShowTempCurveButton
@onready var _show_whittaker_diagram_button: Button = %ShowWhittakerDiagramButton
@onready var _pipeline_vbox: VBoxContainer = %PipelineVBox
@onready var _pipeline_task_label: Label = %PipelineTaskLabel
@onready var _pipeline_progress: ProgressBar = %PipelineProgressBar

## Baker-reported 0–1 maps to this fraction of the full bar (rest = grid merge + climatology).
const _PIPELINE_BAKE_PORTION: float = 0.34
const _PIPELINE_AFTER_BAKE_MERGE: float = 0.36

## Whittaker classes + ice: ids match [enum ClimateSimulator.BiomeID] and [code]biome_colormap.gdshader[/code]
## ([code]biome_id_to_color[/code]); ocean id 10 is applied in the shader [code]fragment[/code].
const _BIOME_LEGEND_LAND: Array[Dictionary] = [
	{"id": 0, "name": "Tundra", "color": Color(0.72, 0.78, 0.82)},
	{"id": 1, "name": "Boreal forest", "color": Color(0.18, 0.38, 0.28)},
	{"id": 2, "name": "Temperate grassland", "color": Color(0.69, 0.42, 0.24)},
	{"id": 3, "name": "Temperate seasonal forest", "color": Color(0.35, 0.55, 0.22)},
	{"id": 4, "name": "Temperate rainforest", "color": Color(0.12, 0.48, 0.42)},
	{"id": 5, "name": "Subtropical desert", "color": Color(0.85, 0.72, 0.38)},
	{"id": 6, "name": "Savannah", "color": Color(0.72, 0.62, 0.28)},
	{"id": 7, "name": "Tropical seasonal forest", "color": Color(0.24, 0.58, 0.24)},
	{"id": 8, "name": "Tropical rainforest", "color": Color(0.05, 0.42, 0.22)},
	{"id": 9, "name": "Ice", "color": Color(0.88, 0.92, 0.96)},
]

var _orbit_rig: Node3D
var _base_truth_baker: Node
var _planet: Node3D
var _climate_grid: ClimateGrid
## When true, climate channels/biomes match current elevation and slider settings
## (no full re-sim needed for visualization toggles).
var _climatology_valid: bool = false
var _base_bake_start_usec: int = 0
var _climate_worker_running: bool = false
var _climate_worker_done_cb: Callable = Callable()
var _cw_c0: float = 0.0
var _cw_c1: float = 1.0
var _cw_pending_elevation_buffers: Dictionary = {}
var _cw_last_emit_usec: int = 0
var _cw_last_emit_progress: float = -1.0
var _cw_last_emit_msg: String = ""
var _pipeline_last_update_msec: int = 0
var _ui_rng := RandomNumberGenerator.new()


func _get_baker_property_any(keys: Array[String]) -> Variant:
	if _base_truth_baker == null:
		return null
	for key in keys:
		var v: Variant = _base_truth_baker.get(key)
		if v != null:
			return v
	return null


func _set_baker_property_any(keys: Array[String], value: Variant) -> bool:
	if _base_truth_baker == null:
		return false
	for key in keys:
		_base_truth_baker.set(key, value)
		var verify: Variant = _base_truth_baker.get(key)
		if verify != null:
			return true
	return false


func _get_baker_tectonics() -> Variant:
	return _get_baker_property_any(["Tectonics", "tectonics"])


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if climate_tuning and climate_tuning.has_method("apply_to_simulator"):
		climate_tuning.apply_to_simulator()
	var n := get_node_or_null(camera_orbit_rig_path)
	if n is Node3D and n.get_script() == _ORBIT_RIG_SCRIPT:
		_orbit_rig = n

	_base_truth_baker = get_node_or_null(planet_base_truth_baker_path)
	if _base_truth_baker:
		_base_truth_baker.BakeStarted.connect(_on_base_truth_bake_started)
		_base_truth_baker.BakeProgress.connect(_on_base_truth_bake_progress)
		_base_truth_baker.BakeFinished.connect(_on_base_truth_bake_finished)
	if _generate_base_data_button:
		_generate_base_data_button.pressed.connect(_on_generate_base_data_pressed)
	if _random_seed_button:
		_random_seed_button.pressed.connect(_on_random_seed_pressed)
	if _export_climate_exrs_button:
		_export_climate_exrs_button.pressed.connect(_on_export_climate_exrs_pressed)

	_planet = get_node_or_null(planet_path) as Node3D
	if _elevation_viz_check:
		_elevation_viz_check.toggled.connect(_on_elevation_viz_toggled)
	if _temperature_viz_check:
		_temperature_viz_check.toggled.connect(_on_temperature_viz_toggled)
	if _moisture_viz_check:
		_moisture_viz_check.toggled.connect(_on_moisture_viz_toggled)
	if _biome_viz_check:
		_biome_viz_check.toggled.connect(_on_biome_viz_toggled)

	_build_biome_legend_ui()
	_update_biome_legend_visibility()

	_sync_land_area_ui_from_tectonics()
	_sync_seed_ui_from_tectonics()
	if _land_area_slider:
		_land_area_slider.value_changed.connect(_on_land_area_slider_changed)
	if _gen_temp_slider:
		_gen_temp_slider.value_changed.connect(_on_gen_temp_slider_changed)
	if _gen_rain_slider:
		_gen_rain_slider.value_changed.connect(_on_gen_rain_slider_changed)
	if _gen_ocean_slider:
		_gen_ocean_slider.value_changed.connect(_on_gen_ocean_slider_changed)
	if _show_precip_curve_button:
		_show_precip_curve_button.pressed.connect(_on_show_precip_curve_pressed)
	if _show_temp_curve_button:
		_show_temp_curve_button.pressed.connect(_on_show_temp_curve_pressed)
	if _show_whittaker_diagram_button:
		_show_whittaker_diagram_button.pressed.connect(_on_show_whittaker_diagram_pressed)
	_update_generation_param_labels()
	_push_generation_overrides_to_sim()


func _set_regenerate_controls_busy(busy: bool) -> void:
	if _generate_base_data_button:
		_generate_base_data_button.disabled = busy
	if _world_seed_spin:
		_world_seed_spin.editable = not busy
	if _random_seed_button:
		_random_seed_button.disabled = busy


func _sync_seed_ui_from_tectonics() -> void:
	if _world_seed_spin == null or _base_truth_baker == null:
		return
	# Prefer baker.world_seed if it is explicitly set (>= 0).
	var ws: Variant = _get_baker_property_any(["WorldSeed", "world_seed"])
	if ws != null and int(ws) >= 0:
		_world_seed_spin.set_value_no_signal(float(int(ws)))
		return
	var tect: Variant = _get_baker_tectonics()
	if tect == null:
		return
	var gs: Variant = tect.get("GenerationSeed")
	if gs == null:
		gs = tect.get("generation_seed")
	if gs != null:
		_world_seed_spin.set_value_no_signal(float(int(gs)))

## Writes UI seed into [member PlanetBaseTruthBaker.world_seed].
func _apply_ui_seed_to_baker() -> void:
	if _base_truth_baker == null or _world_seed_spin == null:
		return
	var s: int = int(_world_seed_spin.value)
	if _base_truth_baker.has_method("SetWorldSeed"):
		_base_truth_baker.call("SetWorldSeed", s)
	elif _base_truth_baker.has_method("set_world_seed"):
		_base_truth_baker.call("set_world_seed", s)
	else:
		if not _set_baker_property_any(["WorldSeed", "world_seed"], s):
			push_warning("DebugSidePanel: failed to set baker world seed")
	# Belt-and-suspenders: also write the tectonics resource seed directly so
	# Regenerate cannot run with stale GenerationSeed due interop/property mismatch.
	var tect: Variant = _get_baker_tectonics()
	if tect != null:
		tect.set("GenerationSeed", s)
		tect.set("generation_seed", s)


func _on_random_seed_pressed() -> void:
	if _world_seed_spin == null:
		return
	_ui_rng.randomize()
	_world_seed_spin.value = float(_ui_rng.randi_range(0, 2_147_483_647))


func _sync_land_area_ui_from_tectonics() -> void:
	if _land_area_slider == null or _base_truth_baker == null:
		return
	var tect: Variant = _get_baker_tectonics()
	if tect == null:
		return
	var frac_var: Variant = tect.get("TargetLandAreaFraction")
	if frac_var == null:
		frac_var = tect.get("target_land_area_fraction")
	if frac_var == null:
		return
	var frac: float = float(frac_var)
	_land_area_slider.set_value_no_signal(roundi(frac * 100.0))
	_update_land_area_percent_label()


func _on_land_area_slider_changed(value: float) -> void:
	_update_land_area_percent_label()
	if _base_truth_baker == null:
		return
	var tect: Variant = _get_baker_tectonics()
	if tect == null:
		return
	var frac: float = clampf(value / 100.0, 0.0, 1.0)
	tect.set("TargetLandAreaFraction", frac)
	tect.set("target_land_area_fraction", frac)


func _update_land_area_percent_label() -> void:
	if _land_area_value_label == null or _land_area_slider == null:
		return
	_land_area_value_label.text = "%d%%" % int(_land_area_slider.value)


func _update_generation_param_labels() -> void:
	if _gen_temp_value_label and _gen_temp_slider:
		_gen_temp_value_label.text = "%+.1f" % _gen_temp_slider.value
	if _gen_rain_value_label and _gen_rain_slider:
		var pct: int = int(roundi(100.0 + _gen_rain_slider.value))
		_gen_rain_value_label.text = "%d%%" % pct
	if _gen_ocean_value_label and _gen_ocean_slider:
		_gen_ocean_value_label.text = "%+.0f" % _gen_ocean_slider.value


func _neutral_sea_level_offset_m_from_tuning() -> float:
	if climate_tuning == null:
		return 0.0
	var v: Variant = climate_tuning.get("generation_sea_level_offset_m")
	if v == null:
		return 0.0
	return float(v)


func _push_generation_overrides_to_sim() -> void:
	var sim := ClimateSimulator.new()
	var sea_user: float = _gen_ocean_slider.value if _gen_ocean_slider else 0.0
	sim.SetRuntimeGenerationOverrides(
		_gen_temp_slider.value if _gen_temp_slider else 0.0,
		1.0,
		_neutral_sea_level_offset_m_from_tuning() + sea_user
	)


func _on_gen_temp_slider_changed(_v: float) -> void:
	_update_generation_param_labels()
	_climatology_valid = false
	_push_generation_overrides_to_sim()


func _on_gen_rain_slider_changed(_v: float) -> void:
	_update_generation_param_labels()
	_climatology_valid = false
	_push_generation_overrides_to_sim()


func _on_gen_ocean_slider_changed(_v: float) -> void:
	_update_generation_param_labels()
	_climatology_valid = false
	_push_generation_overrides_to_sim()


func _on_show_precip_curve_pressed() -> void:
	_push_generation_overrides_to_sim()
	_open_latitude_curve_window(
		"Base precipitation by latitude",
		"Annual precipitation (cm/yr)",
		_sample_base_precip_points(),
		Color(0.24, 0.72, 1.0, 1.0)
	)


func _on_show_temp_curve_pressed() -> void:
	_push_generation_overrides_to_sim()
	_open_latitude_curve_window(
		"Base temperature by latitude",
		"Temperature (deg C)",
		_sample_base_temperature_points(),
		Color(1.0, 0.55, 0.26, 1.0)
	)


func _on_show_whittaker_diagram_pressed() -> void:
	_open_whittaker_diagram_window()


func _open_whittaker_diagram_window() -> void:
	var root := get_tree().root
	if root == null:
		return
	var w := Window.new()
	w.title = "Whittaker biome T/P diagram"
	w.min_size = Vector2i(980, 620)
	w.size = Vector2i(1200, 760)
	w.transient = false
	w.unresizable = false
	w.close_requested.connect(func() -> void: w.queue_free())
	var plot_script := load("res://Scripts/whittaker_diagram_window.gd")
	if plot_script == null:
		append_debug_line("Whittaker window script not found.")
		w.queue_free()
		return
	var plot: Control = plot_script.new()
	plot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(w)
	w.add_child(plot)
	w.popup_centered_ratio(0.8)


func _sample_base_precip_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for lat in range(-90, 91):
		var cm: float = ClimateSimulator.SampleBasePrecipCmByLatitudeDeg(float(lat))
		points.push_back(Vector2(float(lat), cm))
	return points


func _sample_base_temperature_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for lat in range(-90, 91):
		var c: float = ClimateSimulator.SampleBaseTemperatureCByLatitudeDeg(
			float(lat), climate_equator_temp_c, climate_pole_temp_c
		)
		points.push_back(Vector2(float(lat), c))
	return points


func _open_latitude_curve_window(
	title_text: String, y_label: String, points: PackedVector2Array, line_color: Color
) -> void:
	var root := get_tree().root
	if root == null:
		return
	var w := Window.new()
	w.title = title_text
	w.min_size = Vector2i(860, 500)
	w.size = Vector2i(980, 580)
	w.transient = false
	w.unresizable = false
	w.close_requested.connect(func() -> void: w.queue_free())
	var plot_script := load("res://Scripts/latitude_curve_window.gd")
	if plot_script == null:
		append_debug_line("Latitude curve window script not found.")
		w.queue_free()
		return
	var plot: Control = plot_script.new()
	plot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(w)
	w.add_child(plot)
	if plot.has_method("setup"):
		plot.setup(title_text, "Latitude (deg)", y_label, points, line_color)
	w.popup_centered_ratio(0.66)


func _process(_delta: float) -> void:
	if _orbit_rig:
		var d_km: float = _orbit_rig.get_ortho_view_height_km()
		var h_km: float = _orbit_rig.get_equivalent_perspective_altitude_km()
		_elevation_label.text = (
			"Ground footprint (nadir ≈): %s km\nEquiv. perspective altitude: %s"
			% [_format_km(d_km), _format_equiv_altitude(h_km)]
		)
	if _climate_worker_running and _pipeline_task_label:
		var age_msec: int = Time.get_ticks_msec() - _pipeline_last_update_msec
		if age_msec > 600:
			var base_task: String = _pipeline_task_label.text
			var mark: String = " (working "
			var mark_at: int = base_task.find(mark)
			if mark_at >= 0:
				base_task = base_task.substr(0, mark_at)
			var age_s: float = float(age_msec) / 1000.0
			_pipeline_task_label.text = "%s (working %.1fs)" % [base_task, age_s]


func set_debug_text(text: String) -> void:
	_debug_label.text = text


func append_debug_line(line: String) -> void:
	if _debug_label.text.is_empty():
		_debug_label.text = line
	else:
		_debug_label.text += "\n" + line


func clear_debug() -> void:
	_debug_label.text = ""


func _baker_progress_to_pipeline(overall_01: float) -> float:
	return clampf(overall_01, 0.0, 1.0) * _PIPELINE_BAKE_PORTION


func _set_pipeline(global_01: float, task: String) -> void:
	_pipeline_last_update_msec = Time.get_ticks_msec()
	if _pipeline_task_label:
		_pipeline_task_label.text = task
	if _pipeline_progress:
		_pipeline_progress.value = clampf(global_01, 0.0, 1.0)
	if _pipeline_vbox:
		_pipeline_vbox.visible = true


func _hide_pipeline_ui() -> void:
	if _pipeline_vbox:
		_pipeline_vbox.visible = false
	if _pipeline_progress:
		_pipeline_progress.value = 0.0
	if _pipeline_task_label:
		_pipeline_task_label.text = ""


## Main thread only; invoked via [method call_deferred] from the climate worker
## so the progress bar can repaint.
func _deferred_set_pipeline(global_01: float, task: String) -> void:
	_set_pipeline(global_01, task)


func _queue_climate_rebuild_worker(
	climate_from: float, climate_to: float, done_cb: Callable
) -> void:
	if _climate_worker_running:
		push_warning("DebugSidePanel: climate worker already running")
		return
	_push_generation_overrides_to_sim()
	_climate_worker_running = true
	_climate_worker_done_cb = done_cb
	_cw_c0 = climate_from
	_cw_c1 = climate_to
	_cw_last_emit_usec = 0
	_cw_last_emit_progress = -1.0
	_cw_last_emit_msg = ""
	_pipeline_last_update_msec = Time.get_ticks_msec()
	WorkerThreadPool.add_task(Callable(self, "_climate_worker_task"))


func _climate_worker_task() -> void:
	var grid: ClimateGrid = _climate_grid
	if grid == null:
		call_deferred("_climate_worker_finished", false)
		return
	var c0: float = _cw_c0
	var c1: float = _cw_c1
	var w: float = c1 - c0
	var t_eq: float = climate_equator_temp_c
	var t_pol: float = climate_pole_temp_c
	var river_moisture_params: Dictionary = {
		"enabled": river_moisture_v1_enabled,
		"flow_threshold": river_moisture_flow_threshold,
		"flow_saturation": river_moisture_flow_saturation,
		"bank_bonus_cm": river_moisture_bank_bonus_cm,
		"radius_cells": river_moisture_radius_cells,
		"decay_per_cell": river_moisture_decay_per_cell,
		"arid_precip_cm": river_moisture_arid_precip_cm,
		"arid_bonus_scale": river_moisture_arid_bonus_scale,
		"freeze_start_c": river_moisture_freeze_start_c,
		"freeze_full_c": river_moisture_freeze_full_c,
	}
	var report := func(la: float, lb: float, u: float, msg: String) -> void:
		var p: float = lerpf(la, lb, u)
		var now_usec: int = Time.get_ticks_usec()
		var msg_changed: bool = msg != _cw_last_emit_msg
		var progress_jump: bool = _cw_last_emit_progress < 0.0 or absf(p - _cw_last_emit_progress) >= 0.003
		var stale_emit: bool = (now_usec - _cw_last_emit_usec) >= 40_000
		var final_emit: bool = p >= (lb - 0.000001)
		if msg_changed or final_emit or (progress_jump and stale_emit):
			_cw_last_emit_usec = now_usec
			_cw_last_emit_progress = p
			_cw_last_emit_msg = msg
			call_deferred("_deferred_set_pipeline", p, msg)
	var pending_buffers: Dictionary = _cw_pending_elevation_buffers
	if not pending_buffers.is_empty():
		# Merge baked elevation into ClimateGrid off main thread to avoid UI hitch.
		report.call(c0, c0 + w * 0.02, 0.0, "ClimateGrid: merging elevation buffers…")
		var merged_ok: bool = grid.update_elevation_from_buffers(pending_buffers)
		_cw_pending_elevation_buffers = {}
		report.call(c0, c0 + w * 0.02, 1.0, "ClimateGrid: merge complete")
		if not merged_ok:
			call_deferred("_climate_worker_finished", false)
			return
		c0 += w * 0.02
		w = c1 - c0
	elif not grid.is_allocated():
		call_deferred("_climate_worker_finished", false)
		return
	var sim := ClimateSimulator.new()
	sim.CalculateBaseTemperature(
		grid,
		t_eq,
		t_pol,
		func(t: float) -> void:
			report.call(c0 + w * 0.0, c0 + w * 0.12, t, "Climatology: temperature (lat + lapse)")
	)
	sim.CalculatePrecipitation(
		grid,
		func(t: float) -> void:
			report.call(c0 + w * 0.12, c0 + w * 0.58, t, "Climatology: precipitation / rain shadow")
	)
	sim.CalculateFlowAccumulation(
		grid,
		func(t: float) -> void:
			report.call(c0 + w * 0.58, c0 + w * 0.90, t, "Climatology: flow accumulation / rivers")
	)
	sim.CalculateSoilWetness(
		grid,
		river_moisture_params,
		func(t: float) -> void:
			report.call(c0 + w * 0.90, c0 + w * 0.96, t, "Climatology: soil wetness (river bonus)")
	)
	sim.CalculateBiomes(
		grid,
		func(t: float) -> void:
			report.call(c0 + w * 0.96, c1, t, "Climatology: Whittaker biomes")
	)
	call_deferred("_climate_worker_finished", true)


func _climate_worker_finished(ok: bool) -> void:
	_climate_worker_running = false
	_climatology_valid = ok
	var cb: Callable = _climate_worker_done_cb
	_climate_worker_done_cb = Callable()
	if cb.is_valid():
		cb.call(ok)


func _run_climate_on_grid_sync(grid: ClimateGrid) -> bool:
	if grid == null or not grid.is_allocated():
		_climatology_valid = false
		return false
	_push_generation_overrides_to_sim()
	var eq: float = climate_equator_temp_c
	var pole: float = climate_pole_temp_c
	var sim := ClimateSimulator.new()
	sim.CalculateBaseTemperature(grid, eq, pole, Callable())
	sim.CalculatePrecipitation(grid, Callable())
	sim.CalculateFlowAccumulation(grid, Callable())
	sim.CalculateSoilWetness(
		grid,
		{
			"enabled": river_moisture_v1_enabled,
			"flow_threshold": river_moisture_flow_threshold,
			"flow_saturation": river_moisture_flow_saturation,
			"bank_bonus_cm": river_moisture_bank_bonus_cm,
			"radius_cells": river_moisture_radius_cells,
			"decay_per_cell": river_moisture_decay_per_cell,
			"arid_precip_cm": river_moisture_arid_precip_cm,
			"arid_bonus_scale": river_moisture_arid_bonus_scale,
			"freeze_start_c": river_moisture_freeze_start_c,
			"freeze_full_c": river_moisture_freeze_full_c,
		},
		Callable()
	)
	sim.CalculateBiomes(grid, Callable())
	_climatology_valid = true
	return true


func _on_generate_base_data_pressed() -> void:
	if _base_truth_baker == null:
		append_debug_line("Regenerate: PlanetBaseTruthBaker node not found.")
		return
	_push_generation_overrides_to_sim()
	_apply_ui_seed_to_baker()
	var seed_applied: int = int(_world_seed_spin.value) if _world_seed_spin else -1
	var ws: Variant = _get_baker_property_any(["WorldSeed", "world_seed"])
	if ws != null:
		seed_applied = int(ws)
	append_debug_line("Regenerate: using world seed %d." % seed_applied)
	append_debug_line("Regenerate: requested (terrain bake + climate).")
	# C# entry point is PascalCase; snake_case aliases are not always registered.
	_base_truth_baker.call("RequestGenerateBaseTruth")


func _on_base_truth_bake_started() -> void:
	_set_regenerate_controls_busy(true)
	_base_bake_start_usec = Time.get_ticks_usec()
	_set_pipeline(0.0, "Terrain bake: queued…")


func _on_base_truth_bake_progress(_phase: String, overall_01: float, message: String) -> void:
	_set_pipeline(_baker_progress_to_pipeline(overall_01), message)


func _on_base_truth_bake_finished(success: bool, elevation_buffers_by_face: Dictionary) -> void:
	var bake_total_s: float = float(Time.get_ticks_usec() - _base_bake_start_usec) / 1_000_000.0
	if success:
		var grid := _ensure_climate_grid()
		_climatology_valid = false
		_set_pipeline(_PIPELINE_BAKE_PORTION, "Terrain bake: done (%.1f s)" % bake_total_s)
		if not elevation_buffers_by_face.is_empty():
			_cw_pending_elevation_buffers = elevation_buffers_by_face
			_set_pipeline(
				lerpf(_PIPELINE_BAKE_PORTION, _PIPELINE_AFTER_BAKE_MERGE, 0.5),
				"ClimateGrid: merge queued…"
			)
		else:
			_cw_pending_elevation_buffers = {}
			_set_pipeline(_PIPELINE_AFTER_BAKE_MERGE, "ClimateGrid: merge skipped (no buffers)")
		_queue_climate_rebuild_worker(
			_PIPELINE_AFTER_BAKE_MERGE,
			1.0,
			func(ok: bool) -> void: _on_generate_climate_worker_done(ok, grid)
		)
		return
	append_debug_line(
		"Base data bake failed after %.2f s (see Output)." % bake_total_s
	)
	_hide_pipeline_ui()
	_set_regenerate_controls_busy(false)


func _on_generate_climate_worker_done(ok: bool, grid: ClimateGrid) -> void:
	if ok:
		_set_pipeline(1.0, "Complete — climatology ready")
		var total_s: float = float(Time.get_ticks_usec() - _base_bake_start_usec) / 1_000_000.0
		append_debug_line(
			"Regenerate: finished in %.1f s (terrain + climatology)." % total_s
		)
		call_deferred("_hide_pipeline_ui")
		if _elevation_viz_check and _elevation_viz_check.button_pressed and _planet:
			if _planet.has_method("refresh_elevation_visualization"):
				_planet.refresh_elevation_visualization(grid)
		if _temperature_viz_check and _temperature_viz_check.button_pressed:
			if _planet and _planet.has_method("refresh_temperature_visualization"):
				_planet.refresh_temperature_visualization(_climate_grid)
		if _moisture_viz_check and _moisture_viz_check.button_pressed:
			if _planet and _planet.has_method("refresh_precipitation_visualization"):
				_planet.refresh_precipitation_visualization(_climate_grid)
		if _biome_viz_check and _biome_viz_check.button_pressed:
			if _planet and _planet.has_method("refresh_biome_visualization"):
				_planet.refresh_biome_visualization(_climate_grid)
	else:
		append_debug_line("Climate pass after bake failed (see console).")
		_hide_pipeline_ui()
	_set_regenerate_controls_busy(false)


func _on_elevation_viz_toggled(pressed: bool) -> void:
	if pressed and _temperature_viz_check and _temperature_viz_check.button_pressed:
		_temperature_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_temperature_visualization"):
			_planet.call("set_temperature_visualization", false)
	if pressed and _moisture_viz_check and _moisture_viz_check.button_pressed:
		_moisture_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_precipitation_visualization"):
			_planet.call("set_precipitation_visualization", false)
	if pressed and _biome_viz_check and _biome_viz_check.button_pressed:
		_biome_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_biome_visualization"):
			_planet.call("set_biome_visualization", false)
	if _planet == null or not _planet.has_method("set_elevation_visualization"):
		if _elevation_viz_check:
			_elevation_viz_check.set_pressed_no_signal(false)
		append_debug_line("Elevation viz: Planet not found or unsupported.")
		return
	var grid := _ensure_climate_grid()
	var ok: bool = bool(_planet.call("set_elevation_visualization", pressed, grid))
	if pressed and not ok:
		if _elevation_viz_check:
			_elevation_viz_check.set_pressed_no_signal(false)
		append_debug_line("Elevation viz: run Regenerate first (ClimateGrid empty).")
	elif not pressed:
		append_debug_line("Elevation heatmap off.")
	else:
		append_debug_line("Elevation heatmap on (black = low, white = high, unshaded).")


func _on_temperature_viz_toggled(pressed: bool) -> void:
	if pressed and _elevation_viz_check and _elevation_viz_check.button_pressed:
		_elevation_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_elevation_visualization"):
			_planet.call("set_elevation_visualization", false)
	if pressed and _moisture_viz_check and _moisture_viz_check.button_pressed:
		_moisture_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_precipitation_visualization"):
			_planet.call("set_precipitation_visualization", false)
	if pressed and _biome_viz_check and _biome_viz_check.button_pressed:
		_biome_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_biome_visualization"):
			_planet.call("set_biome_visualization", false)
	if _planet == null or not _planet.has_method("set_temperature_visualization"):
		if _temperature_viz_check:
			_temperature_viz_check.set_pressed_no_signal(false)
		append_debug_line("Temperature viz: Planet not found or unsupported.")
		return
	if not pressed:
		_planet.call("set_temperature_visualization", false)
		append_debug_line("Temperature colormap off.")
		return
	if not _ensure_climate_simulated_for_viz():
		if _temperature_viz_check:
			_temperature_viz_check.set_pressed_no_signal(false)
		append_debug_line("Temperature viz: run Regenerate first.")
		return
	var ok: bool = bool(_planet.call("set_temperature_visualization", true, _climate_grid))
	if not ok:
		if _temperature_viz_check:
			_temperature_viz_check.set_pressed_no_signal(false)
		append_debug_line("Temperature viz: failed to build texture.")
	else:
		append_debug_line("Temperature on (blue=cold, red=hot, unshaded).")


func _on_moisture_viz_toggled(pressed: bool) -> void:
	if pressed and _elevation_viz_check and _elevation_viz_check.button_pressed:
		_elevation_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_elevation_visualization"):
			_planet.call("set_elevation_visualization", false)
	if pressed and _temperature_viz_check and _temperature_viz_check.button_pressed:
		_temperature_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_temperature_visualization"):
			_planet.call("set_temperature_visualization", false)
	if pressed and _biome_viz_check and _biome_viz_check.button_pressed:
		_biome_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_biome_visualization"):
			_planet.call("set_biome_visualization", false)
	if _planet == null or not _planet.has_method("set_precipitation_visualization"):
		if _moisture_viz_check:
			_moisture_viz_check.set_pressed_no_signal(false)
		append_debug_line("Moisture viz: Planet not found or unsupported.")
		return
	if not pressed:
		_planet.call("set_precipitation_visualization", false)
		append_debug_line("Moisture colormap off.")
		return
	if not _ensure_climate_simulated_for_viz():
		if _moisture_viz_check:
			_moisture_viz_check.set_pressed_no_signal(false)
		append_debug_line("Moisture viz: run Regenerate first.")
		return
	var ok: bool = bool(_planet.call("set_precipitation_visualization", true, _climate_grid))
	if not ok:
		if _moisture_viz_check:
			_moisture_viz_check.set_pressed_no_signal(false)
		append_debug_line("Moisture viz: failed to build texture.")
	else:
		append_debug_line("Moisture on (tan=dry, blue=high precip, unshaded).")


func _on_biome_viz_toggled(pressed: bool) -> void:
	if pressed and _elevation_viz_check and _elevation_viz_check.button_pressed:
		_elevation_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_elevation_visualization"):
			_planet.call("set_elevation_visualization", false)
	if pressed and _temperature_viz_check and _temperature_viz_check.button_pressed:
		_temperature_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_temperature_visualization"):
			_planet.call("set_temperature_visualization", false)
	if pressed and _moisture_viz_check and _moisture_viz_check.button_pressed:
		_moisture_viz_check.set_pressed_no_signal(false)
		if _planet and _planet.has_method("set_precipitation_visualization"):
			_planet.call("set_precipitation_visualization", false)
	if _planet == null or not _planet.has_method("set_biome_visualization"):
		if _biome_viz_check:
			_biome_viz_check.set_pressed_no_signal(false)
		append_debug_line("Biome viz: Planet not found or unsupported.")
		_update_biome_legend_visibility()
		return
	if not pressed:
		_planet.call("set_biome_visualization", false)
		append_debug_line("Biome colormap off.")
		_update_biome_legend_visibility()
		return
	if not _ensure_climate_simulated_for_viz():
		if _biome_viz_check:
			_biome_viz_check.set_pressed_no_signal(false)
		append_debug_line("Biome viz: run Regenerate first.")
		_update_biome_legend_visibility()
		return
	var ok: bool = bool(_planet.call("set_biome_visualization", true, _climate_grid))
	if not ok:
		if _biome_viz_check:
			_biome_viz_check.set_pressed_no_signal(false)
		append_debug_line("Biome viz: failed to build texture.")
	else:
		append_debug_line("Biomes on (discrete palette, unshaded).")
	_update_biome_legend_visibility()


func _ensure_climate_grid() -> ClimateGrid:
	if _climate_grid != null:
		return _climate_grid
	_climate_grid = ClimateGrid.new()
	_climate_grid.face_resolution = 512
	return _climate_grid


func _ensure_climate_simulated_for_viz() -> bool:
	var grid := _ensure_climate_grid()
	if not grid.is_allocated():
		return false
	if _climatology_valid:
		return true
	if _climate_worker_running:
		return false
	return _run_climate_on_grid_sync(grid)


func _on_export_climate_exrs_pressed() -> void:
	if _base_truth_baker == null:
		append_debug_line("Export: PlanetBaseTruthBaker not found.")
		return
	var grid := _ensure_climate_grid()
	if not grid.is_allocated():
		append_debug_line("Export: run Regenerate first (grid empty).")
		return
	if _export_climate_exrs_button:
		_export_climate_exrs_button.disabled = true
	_set_pipeline(0.0, "Export: rebuilding climatology…")
	_queue_climate_rebuild_worker(
		0.0, 1.0, func(ok: bool) -> void: _on_export_climate_worker_done(ok, grid)
	)
	return


func _on_export_climate_worker_done(ok: bool, grid: ClimateGrid) -> void:
	if not ok:
		append_debug_line("Export: climate rebuild failed.")
		_hide_pipeline_ui()
		if _export_climate_exrs_button:
			_export_climate_exrs_button.disabled = false
		return
	_set_pipeline(1.0, "Export: writing EXRs…")
	var dir: String = str(_get_baker_property_any(["OutputDir", "output_dir"]))
	var prefix: String = str(_get_baker_property_any(["FilePrefix", "file_prefix"]))
	var ok_pack: bool = grid.export_packed_climate_exrs(dir, prefix)
	var ok_sep: bool = grid.export_separate_climate_exrs(dir, prefix)
	call_deferred("_hide_pipeline_ui")
	if _export_climate_exrs_button:
		_export_climate_exrs_button.disabled = false
	if ok_pack and ok_sep:
		append_debug_line("Phase 2.2 EXRs written (packed RGBA + 5× RF sets) → %s" % dir)
	else:
		append_debug_line("Export finished with errors (see console).")


func add_control(node: Control) -> void:
	controls_host.add_child(node)


func _build_biome_legend_ui() -> void:
	if _biome_legend_box == null:
		return
	var title := Label.new()
	title.text = "Whittaker biomes"
	_biome_legend_box.add_child(title)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1))
	var blurb := Label.new()
	blurb.text = "Grid ids 0–9: class from mean annual T × soil wetness (cm/yr), same as the Whittaker diagram."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 10)
	blurb.add_theme_color_override("font_color", Color(0.68, 0.73, 0.82, 1))
	_biome_legend_box.add_child(blurb)
	for entry: Dictionary in _BIOME_LEGEND_LAND:
		var row_label := "%d  %s" % [int(entry["id"]), str(entry["name"])]
		_biome_legend_box.add_child(_make_legend_row(row_label, entry["color"]))
	_biome_legend_box.add_child(
		_make_legend_row("10  Ocean (sea cells)", Color(0.06, 0.14, 0.38))
	)
	_biome_legend_box.add_child(
		_make_legend_row("—  Major rivers (flow tint)", Color(0.12, 0.42, 0.82))
	)


func _make_legend_row(label_text: String, swatch_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(18, 14)
	sw.color = swatch_color
	sw.tooltip_text = "RGB %.2f, %.2f, %.2f" % [swatch_color.r, swatch_color.g, swatch_color.b]
	row.add_child(sw)
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 1))
	row.add_child(lab)
	return row


func _update_biome_legend_visibility() -> void:
	if _biome_legend_box == null or _biome_viz_check == null:
		return
	_biome_legend_box.visible = _biome_viz_check.button_pressed


func _format_km(km: float) -> String:
	if km >= 10000.0:
		return "%.0f" % km
	if km >= 100.0:
		return "%.1f" % km
	return "%.2f" % km


func _format_equiv_altitude(h_km: float) -> String:
	if is_inf(h_km):
		return "— (S ≥ 2R)"
	var m: float = h_km * 1000.0
	if m < 1.0:
		return "%.2f m" % m
	if m < 100.0:
		return "%.1f m" % m
	return "%.0f m" % m
