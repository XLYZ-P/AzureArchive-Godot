class_name AaPaletteButton
extends Button
## 节点工厂里的可拖拽按钮：拖到画布上创建节点；单击在画布中央创建。

var node_type := 0
var drag_enabled := true
var drag_display := ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled:
		return null
	var preview := PanelContainer.new()
	var lab := Label.new()
	lab.text = "＋ " + (drag_display if not drag_display.is_empty() else text)
	lab.add_theme_color_override("font_color", Color("#0f172a"))
	preview.add_child(lab)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#7dd3fc")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	preview.add_theme_stylebox_override("panel", style)
	set_drag_preview(preview)
	return {"aa_node_type": node_type}
