class_name WhittakerDiagramWindow
extends Control

var _BIOMES: Array[Dictionary] = [
	{
		"name": "Tundra",
		"color": Color(0.72, 0.78, 0.82, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(-15, 0), Vector2(-5, 0), Vector2(-5, 120), Vector2(-15, 40)]
		),
	},
	{
		"name": "Boreal forest",
		"color": Color(0.18, 0.38, 0.28, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(-5, 20), Vector2(5, 55), Vector2(5, 250), Vector2(-5, 120)]
		),
	},
	{
		"name": "Temperate grassland",
		"color": Color(0.69, 0.42, 0.24, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(-5, 10), Vector2(20, 50), Vector2(20, 100), Vector2(-5, 20)]
		),
	},
	{
		"name": "Temperate seasonal forest",
		"color": Color(0.35, 0.55, 0.22, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(5, 55), Vector2(20, 100), Vector2(20, 250), Vector2(5, 150)]
		),
	},
	{
		"name": "Temperate rainforest",
		"color": Color(0.12, 0.48, 0.42, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(5, 150), Vector2(20, 250), Vector2(20, 450), Vector2(5, 250)]
		),
	},
	{
		"name": "Subtropical desert",
		"color": Color(0.85, 0.72, 0.38, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(-5, 0), Vector2(40, 0), Vector2(40, 50), Vector2(20, 50), Vector2(-5, 10)]
		),
	},
	{
		"name": "Savannah",
		"color": Color(0.72, 0.62, 0.28, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(20, 50), Vector2(40, 50), Vector2(40, 100), Vector2(20, 100)]
		),
	},
	{
		"name": "Tropical seasonal forest",
		"color": Color(0.24, 0.58, 0.24, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(20, 100), Vector2(20, 250), Vector2(40, 250), Vector2(40, 100)]
		),
	},
	{
		"name": "Tropical rainforest",
		"color": Color(0.05, 0.42, 0.22, 0.46),
		"vertices": PackedVector2Array(
			[Vector2(20, 250), Vector2(40, 250), Vector2(40, 450), Vector2(20, 450)]
		),
	},
]

var _graph: Control
var _status_label: Label
var _table: RichTextLabel
var _hover_text: String = "Hover a vertex in the plot to inspect exact T/P."


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_table_text()


func _build_ui() -> void:
	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.split_offset = int(size.x * 0.67)
	root.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	_graph = _WhittakerGraph.new(_BIOMES)
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.vertex_hovered.connect(_on_vertex_hovered)
	left.add_child(_graph)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = _hover_text
	left.add_child(_status_label)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	var side_title := Label.new()
	side_title.text = "Biome polygon vertices (T deg C, P cm/yr)"
	side_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(side_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	_table = RichTextLabel.new()
	_table.fit_content = true
	_table.bbcode_enabled = true
	_table.selection_enabled = true
	scroll.add_child(_table)


func _refresh_table_text() -> void:
	if _table == null:
		return
	var lines: Array[String] = []
	for biome in _BIOMES:
		lines.append("[b]%s[/b]" % str(biome["name"]))
		var vertices: PackedVector2Array = biome["vertices"]
		for i in range(vertices.size()):
			var v := vertices[i]
			lines.append("  v%d: T=%5.1f, P=%6.1f" % [i, v.x, v.y])
		lines.append("")
	_table.text = "\n".join(lines)


func _on_vertex_hovered(hit: Dictionary) -> void:
	if hit.is_empty():
		_hover_text = "Hover a vertex in the plot to inspect exact T/P."
	else:
		_hover_text = "%s v%d  |  T=%.1f deg C, P=%.1f cm/yr" % [
			str(hit["biome_name"]), int(hit["vertex_index"]), float(hit["temp_c"]), float(hit["precip_cm"])
		]
	if _status_label:
		_status_label.text = _hover_text


class _WhittakerGraph:
	extends Control

	signal vertex_hovered(hit: Dictionary)

	const AXIS_TEMP_MIN := -15.0
	const AXIS_TEMP_MAX := 40.0
	const AXIS_PRECIP_MIN := 0.0
	const AXIS_PRECIP_MAX := 450.0
	const PANEL_BG := Color(0.08, 0.09, 0.12, 1.0)
	const PLOT_BG := Color(0.13, 0.15, 0.20, 1.0)
	const GRID := Color(0.30, 0.33, 0.39, 0.50)
	const AXIS := Color(0.68, 0.72, 0.80, 0.95)
	const TEXT := Color(0.88, 0.92, 0.98, 1.0)
	const MUTED := Color(0.74, 0.78, 0.87, 1.0)
	const PLOT_MARGIN_LEFT := 72.0
	const PLOT_MARGIN_RIGHT := 20.0
	const PLOT_MARGIN_TOP := 28.0
	const PLOT_MARGIN_BOTTOM := 52.0
	const VERTEX_HOVER_RADIUS_PX := 9.0

	var _biomes: Array[Dictionary]
	var _hover_hit: Dictionary = {}
	var _font: Font


	func _init(biomes: Array[Dictionary]) -> void:
		_biomes = biomes
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS


	func _ready() -> void:
		_font = ThemeDB.fallback_font
		set_process_unhandled_input(true)


	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_update_hover(event.position)


	func _update_hover(mouse_pos: Vector2) -> void:
		var best: Dictionary = {}
		var best_d2 := INF
		var plot := _plot_rect()
		for b in _biomes:
			var vertices: PackedVector2Array = b["vertices"]
			for i in range(vertices.size()):
				var world := vertices[i]
				var p := _tp_to_plot(plot, world.x, world.y)
				var d2 := p.distance_squared_to(mouse_pos)
				if d2 < best_d2 and d2 <= VERTEX_HOVER_RADIUS_PX * VERTEX_HOVER_RADIUS_PX:
					best_d2 = d2
					best = {
						"biome_name": str(b["name"]),
						"vertex_index": i,
						"temp_c": world.x,
						"precip_cm": world.y,
					}
		if best != _hover_hit:
			_hover_hit = best
			vertex_hovered.emit(_hover_hit)
			queue_redraw()


	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, PANEL_BG, true)
		var plot := _plot_rect()
		draw_rect(plot, PLOT_BG, true)
		draw_rect(plot, Color(0.34, 0.37, 0.45, 1.0), false, 1.0)
		_draw_grid(plot)
		_draw_polygons(plot)
		_draw_axes_and_ticks(plot)
		_draw_titles(plot)


	func _plot_rect() -> Rect2:
		return Rect2(
			Vector2(PLOT_MARGIN_LEFT, PLOT_MARGIN_TOP),
			Vector2(
				maxf(8.0, size.x - (PLOT_MARGIN_LEFT + PLOT_MARGIN_RIGHT)),
				maxf(8.0, size.y - (PLOT_MARGIN_TOP + PLOT_MARGIN_BOTTOM))
			)
		)


	func _draw_grid(plot: Rect2) -> void:
		var t_ticks: Array[float] = [-15.0, -5.0, 5.0, 20.0, 30.0, 40.0]
		for t in t_ticks:
			var x := _tp_to_plot(plot, t, AXIS_PRECIP_MIN).x
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID, 1.0)
		var p_ticks: Array[float] = [0.0, 50.0, 100.0, 150.0, 250.0, 350.0, 450.0]
		for p in p_ticks:
			var y := _tp_to_plot(plot, AXIS_TEMP_MIN, p).y
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)


	func _draw_polygons(plot: Rect2) -> void:
		for b in _biomes:
			var poly: PackedVector2Array = b["vertices"]
			var pix := PackedVector2Array()
			for v in poly:
				pix.push_back(_tp_to_plot(plot, v.x, v.y))
			draw_colored_polygon(pix, b["color"])
			var outline := pix.duplicate()
			if outline.size() >= 2:
				outline.push_back(outline[0])
				draw_polyline(outline, Color(0.93, 0.95, 0.99, 0.88), 1.3, true)
			var center := _centroid(poly)
			var cp := _tp_to_plot(plot, center.x, center.y)
			_draw_text_clamped(str(b["name"]), cp + Vector2(-42, -2), 11)

			for i in range(poly.size()):
				var vv := poly[i]
				var vp := _tp_to_plot(plot, vv.x, vv.y)
				var c := Color(0.98, 0.99, 1.0, 0.95)
				if not _hover_hit.is_empty() and str(_hover_hit["biome_name"]) == str(b["name"]) and int(_hover_hit["vertex_index"]) == i:
					c = Color(1.0, 0.92, 0.46, 1.0)
				draw_circle(vp, 3.0, c)


	func _draw_axes_and_ticks(plot: Rect2) -> void:
		draw_line(Vector2(plot.position.x, plot.end.y), plot.end, AXIS, 1.2)
		draw_line(plot.position, Vector2(plot.position.x, plot.end.y), AXIS, 1.2)

		for t in [-15.0, -5.0, 5.0, 20.0, 30.0, 40.0]:
			var p := _tp_to_plot(plot, t, AXIS_PRECIP_MIN)
			draw_line(Vector2(p.x, plot.end.y), Vector2(p.x, plot.end.y + 5.0), AXIS, 1.0)
			var txt := "%.0f" % t
			var sz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(_font, Vector2(p.x - sz.x * 0.5, plot.end.y + 19.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)

		for pval in [0.0, 50.0, 100.0, 150.0, 250.0, 350.0, 450.0]:
			var py := _tp_to_plot(plot, AXIS_TEMP_MIN, pval).y
			draw_line(Vector2(plot.position.x - 5.0, py), Vector2(plot.position.x, py), AXIS, 1.0)
			draw_string(_font, Vector2(9, py + 4.0), "%.0f" % pval, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)


	func _draw_titles(plot: Rect2) -> void:
		draw_string(_font, Vector2(14, 20), "Whittaker biome diagram (runtime classification polygons)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		draw_string(_font, Vector2(plot.position.x, size.y - 16), "Temperature (deg C)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		draw_string(_font, Vector2(12, plot.position.y + 8), "Precipitation / soil wetness (cm/yr)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)


	func _draw_text_clamped(txt: String, pos: Vector2, px_size: int) -> void:
		var p := pos
		p.x = clampf(p.x, 4.0, size.x - 140.0)
		p.y = clampf(p.y, 16.0, size.y - 8.0)
		draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px_size, TEXT)


	func _tp_to_plot(plot: Rect2, temp_c: float, precip_cm: float) -> Vector2:
		var tx := (clampf(temp_c, AXIS_TEMP_MIN, AXIS_TEMP_MAX) - AXIS_TEMP_MIN) / (AXIS_TEMP_MAX - AXIS_TEMP_MIN)
		var py := (clampf(precip_cm, AXIS_PRECIP_MIN, AXIS_PRECIP_MAX) - AXIS_PRECIP_MIN) / (AXIS_PRECIP_MAX - AXIS_PRECIP_MIN)
		return Vector2(
			lerpf(plot.position.x, plot.end.x, tx),
			lerpf(plot.end.y, plot.position.y, py)
		)


	func _centroid(poly: PackedVector2Array) -> Vector2:
		if poly.is_empty():
			return Vector2.ZERO
		var s := Vector2.ZERO
		for p in poly:
			s += p
		return s / float(poly.size())
