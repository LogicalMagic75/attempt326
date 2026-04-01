class_name LatitudeCurvePlot
extends Control

var _title_text: String = ""
var _x_label: String = "Latitude (deg)"
var _y_label: String = ""
var _line_color: Color = Color(0.30, 0.80, 1.00, 1.0)
var _samples: PackedVector2Array = PackedVector2Array()
var _y_min: float = 0.0
var _y_max: float = 1.0
var _plot_margin_left: float = 64.0
var _plot_margin_right: float = 24.0
var _plot_margin_top: float = 28.0
var _plot_margin_bottom: float = 52.0


func setup(
	title_text: String,
	x_label: String,
	y_label: String,
	samples: PackedVector2Array,
	line_color: Color
) -> void:
	_title_text = title_text
	_x_label = x_label
	_y_label = y_label
	_samples = samples
	_line_color = line_color
	_recompute_y_bounds()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.08, 0.09, 0.12, 1.0), true)

	var plot_rect := Rect2(
		Vector2(_plot_margin_left, _plot_margin_top),
		Vector2(
			maxf(8.0, rect.size.x - (_plot_margin_left + _plot_margin_right)),
			maxf(8.0, rect.size.y - (_plot_margin_top + _plot_margin_bottom))
		)
	)
	draw_rect(plot_rect, Color(0.13, 0.15, 0.20, 1.0), true)
	draw_rect(plot_rect, Color(0.34, 0.37, 0.45, 1.0), false, 1.0)

	_draw_grid(plot_rect)
	_draw_curve(plot_rect)
	_draw_labels(plot_rect)


func _draw_grid(plot_rect: Rect2) -> void:
	var grid_color := Color(0.30, 0.33, 0.39, 0.55)
	var n_x := 6
	var n_y := 6
	for i in range(n_x + 1):
		var u: float = float(i) / float(n_x)
		var x := lerpf(plot_rect.position.x, plot_rect.end.x, u)
		draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y), grid_color, 1.0)
	for j in range(n_y + 1):
		var v: float = float(j) / float(n_y)
		var y := lerpf(plot_rect.position.y, plot_rect.end.y, v)
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y), grid_color, 1.0)


func _draw_curve(plot_rect: Rect2) -> void:
	if _samples.is_empty():
		return
	var points := PackedVector2Array()
	for p in _samples:
		points.push_back(_to_plot_point(plot_rect, p.x, p.y))
	if points.size() >= 2:
		draw_polyline(points, _line_color, 2.2, true)


func _draw_labels(plot_rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 13
	draw_string(
		font,
		Vector2(16, 20),
		_title_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(0.95, 0.98, 1.0)
	)
	draw_string(
		font,
		Vector2(plot_rect.position.x, size.y - 18),
		"%s  [-90, 90]" % _x_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.85, 0.88, 0.94)
	)
	draw_string(
		font,
		Vector2(12, plot_rect.position.y + 8),
		_y_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.85, 0.88, 0.94)
	)
	_draw_x_tick_labels(plot_rect, font)
	var tick_vals: Array[float] = _y_ticks(5)
	for tv in tick_vals:
		var y := _to_plot_point(plot_rect, -90.0, tv).y
		draw_line(
			Vector2(plot_rect.position.x - 5.0, y),
			Vector2(plot_rect.position.x, y),
			Color(0.70, 0.74, 0.82, 0.9),
			1.0
		)
		draw_string(
			font,
			Vector2(8, y - 2),
			_format_tick_value(tv),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.77, 0.80, 0.88)
		)


func _to_plot_point(plot_rect: Rect2, lat_deg: float, value: float) -> Vector2:
	var x_u := (clampf(lat_deg, -90.0, 90.0) + 90.0) / 180.0
	var y_u := 0.5
	if _y_max > _y_min:
		y_u = (value - _y_min) / (_y_max - _y_min)
	y_u = clampf(y_u, 0.0, 1.0)
	return Vector2(
		lerpf(plot_rect.position.x, plot_rect.end.x, x_u),
		lerpf(plot_rect.end.y, plot_rect.position.y, y_u)
	)


func _recompute_y_bounds() -> void:
	if _samples.is_empty():
		_y_min = 0.0
		_y_max = 1.0
		return
	var lo := INF
	var hi := -INF
	for p in _samples:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	if is_equal_approx(lo, hi):
		lo -= 1.0
		hi += 1.0
	var pad := (hi - lo) * 0.08
	_y_min = lo - pad
	_y_max = hi + pad


func _y_ticks(count: int) -> Array[float]:
	var out: Array[float] = []
	if count <= 0:
		return out
	for i in range(count + 1):
		var u: float = float(i) / float(count)
		out.append(lerpf(_y_min, _y_max, 1.0 - u))
	return out


func _draw_x_tick_labels(plot_rect: Rect2, font: Font) -> void:
	var ticks: Array[int] = [-90, -60, -30, 0, 30, 60, 90]
	for t in ticks:
		var p := _to_plot_point(plot_rect, float(t), _y_min)
		draw_line(
			Vector2(p.x, plot_rect.end.y),
			Vector2(p.x, plot_rect.end.y + 5.0),
			Color(0.70, 0.74, 0.82, 0.9),
			1.0
		)
		var label := str(t)
		var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(
			font,
			Vector2(p.x - sz.x * 0.5, plot_rect.end.y + 18.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.77, 0.80, 0.88)
		)


func _format_tick_value(v: float) -> String:
	var av := absf(v)
	if av >= 100.0:
		return str(int(roundf(v)))
	if av >= 10.0:
		return "%.1f" % v
	return "%.2f" % v
