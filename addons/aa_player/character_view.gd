class_name AaCharacterView
extends Control
## 一个立绘槽的视图：PNG 立绘 / 程序化占位剪影 + 名字 + 表情气泡 + 动作。
## 由 AaStage 控制生命周期（1–5 号槽各一个实例）。

var slot := 1
var char_id := ""
var face_id := "00"
var display_name := ""
var nickname := ""
var is_on_stage := false
var shape_override := 0

var portrait_rect: TextureRect
var placeholder_rect: TextureRect
var name_label: Label
var face_label: Label
var emoticon_panel: PanelContainer
var emoticon_label: Label
var shot_flash: ColorRect

var base_position := Vector2.ZERO
var instant_mode := false
var art_aspect := 0.61

var _move_tween: Tween = null
var _appear_tween: Tween = null
var _action_tween: Tween = null
var _shape_tween: Tween = null
var _emoticon_time := 0.0
var _dim := false
var _base_scale := 1.0
var _built := false


func setup(slot_index: int) -> void:
	if _built:
		return
	_built = true
	slot = slot_index
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 立绘本体
	placeholder_rect = TextureRect.new()
	placeholder_rect.name = "Placeholder"
	placeholder_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	placeholder_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	placeholder_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(placeholder_rect)
	portrait_rect = TextureRect.new()
	portrait_rect.name = "Portrait"
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.visible = false
	add_child(portrait_rect)
	# 名字
	name_label = Label.new()
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(name_label, 24)
	name_label.add_theme_color_override("font_color", Color("#dff1ff"))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_x", 2)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(name_label)
	# 表情 id（占位模式下便于确认资源切换是否正确）
	face_label = Label.new()
	face_label.name = "FaceId"
	face_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(face_label, 16)
	face_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	add_child(face_label)
	# 气泡
	emoticon_panel = PanelContainer.new()
	emoticon_panel.name = "Emoticon"
	emoticon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.94)
	style.border_color = Color(0.45, 0.75, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(8)
	emoticon_panel.add_theme_stylebox_override("panel", style)
	emoticon_label = Label.new()
	emoticon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(emoticon_label, 26)
	emoticon_label.add_theme_color_override("font_color", Color("#20304a"))
	emoticon_panel.add_child(emoticon_label)
	emoticon_panel.visible = false
	add_child(emoticon_panel)
	# 中弹闪白
	shot_flash = ColorRect.new()
	shot_flash.name = "ShotFlash"
	shot_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shot_flash.color = Color(1, 1, 1, 0.0)
	shot_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shot_flash)
	visible = false
	pivot_offset = Vector2.ZERO


func _apply_font(ctrl: Control, size: int) -> void:
	var f := AaArt.ui_font()
	if f != null:
		ctrl.add_theme_font_override("font", f)
	ctrl.add_theme_font_size_override("font_size", size)


func set_art_size(art_size: Vector2) -> void:
	size = art_size
	pivot_offset = Vector2(size.x * 0.5, size.y)
	face_label.position = Vector2(size.x - 54, 10)
	face_label.size = Vector2(48, 22)
	name_label.position = Vector2(-40, size.y * 0.36)
	name_label.size = Vector2(size.x + 80, 32)
	emoticon_panel.position = Vector2(size.x * 0.5 - 60, maxf(size.y * 0.06, 8.0))


## 该槽当前演员的世界坐标 x（由 AaStage 设置 base_position 后调用）
func set_base_position(pos: Vector2, instant := false) -> void:
	base_position = pos
	# 入场淡入还没跑完时先把透明度补到 1（否则连续推进会把角色停在半透明/全透明）
	if visible and modulate.a < 1.0:
		modulate.a = 1.0
	if instant or not is_inside_tree():
		_kill_tween(_move_tween)
		_move_tween = null
		position = pos
	else:
		_kill_tween(_move_tween)
		_move_tween = create_tween()
		_move_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_move_tween.tween_property(self, "position", pos, 0.22)


func _kill_tween(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()


func _finish_tween(tw: Tween) -> Tween:
	_kill_tween(tw)
	return null


func show_character(id: String, display: String, nick: String, portrait: Texture2D,
		appear_mode: int, instant := false) -> void:
	slot = slot
	char_id = id
	display_name = display
	nickname = nick
	name_label.text = display
	shape_override = 0
	_dim = false
	visible = true
	is_on_stage = true
	if portrait != null:
		portrait_rect.texture = portrait
		portrait_rect.visible = true
		placeholder_rect.visible = false
		name_label.visible = false
	else:
		placeholder_rect.texture = AaArt.character_texture(AaArt.seed_of(id))
		placeholder_rect.visible = true
		portrait_rect.visible = false
		name_label.visible = true
	face_label.text = ""
	_apply_tint()
	# 入场动画
	var target := base_position
	var start := target
	if instant:
		position = target
		modulate.a = 1.0
		return
	match appear_mode:
		1: # al 从右入
			start = target + Vector2(240.0, 0)
		2: # ar 从左入
			start = target - Vector2(240.0, 0)
		3: # a 登场（原地淡入）
			start = target
		_:
			start = target
	_kill_tween(_move_tween)
	_kill_tween(_appear_tween)
	position = start
	modulate.a = 0.0
	_appear_tween = create_tween()
	_appear_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_appear_tween.tween_property(self, "position", target, 0.34)
	_appear_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.30)


func hide_character(mode := 6, instant := false) -> void:
	if not visible:
		return
	_kill_tween(_appear_tween)
	_kill_tween(_move_tween)
	_kill_tween(_action_tween)
	if instant or not is_inside_tree():
		_finish_hide()
		return
	var target := position
	match mode:
		4: # dl 向左退
			target = position - Vector2(260.0, 0)
		5: # dr 向右退
			target = position + Vector2(260.0, 0)
		_:
			target = position
	_appear_tween = create_tween()
	_appear_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_appear_tween.tween_property(self, "position", target, 0.28)
	_appear_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.28)
	_appear_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	visible = false
	is_on_stage = false
	char_id = ""
	modulate.a = 1.0
	rotation = 0.0
	scale = Vector2(_base_scale, _base_scale) * _shape_scale()
	position = base_position
	emoticon_panel.visible = false


func set_face(new_face: String, texture: Texture2D = null) -> bool:
	var changed := new_face != face_id
	face_id = new_face
	if texture != null:
		portrait_rect.texture = texture
		portrait_rect.visible = true
		placeholder_rect.visible = false
		name_label.visible = false
	face_label.text = ""
	face_label.visible = false
	return changed


func set_dim(dimmed: bool) -> void:
	if _dim == dimmed:
		return
	_dim = dimmed
	_apply_tint()


func set_shape(shape: int) -> void:
	shape_override = shape
	var s := 1.0
	match shape:
		4:
			s = 1.30
		_:
			s = 1.0
	if not is_inside_tree() or instant_mode:
		scale = Vector2(s, s)
	else:
		_kill_tween(_shape_tween)
		_shape_tween = create_tween()
		_shape_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_shape_tween.tween_property(self, "scale", Vector2(s, s), 0.25)
	_apply_tint()


func _shape_scale() -> float:
	return 1.30 if shape_override == 4 else 1.0


func _apply_tint() -> void:
	var tint := Color(1, 1, 1, 1)
	if _dim:
		tint = Color(0.62, 0.68, 0.80, 1.0)
	match shape_override:
		1:
			tint = Color(0.16, 0.18, 0.24, 1.0) # 剪影
		2:
			tint = Color(0.30, 0.30, 0.34, 1.0) # 变暗
	if portrait_rect != null:
		portrait_rect.self_modulate = tint
	if placeholder_rect != null:
		placeholder_rect.self_modulate = tint


func play_action(action: int, instant := false) -> void:
	if not visible:
		return
	if instant or not is_inside_tree():
		return
	_kill_tween(_action_tween)
	_kill_tween(_move_tween)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	match action:
		1: # greeting 向下确认
			_action_tween = _make_action_tween()
			_action_tween.tween_property(self, "position", base_position + Vector2(0, 26), 0.16)
			_action_tween.tween_property(self, "position", base_position, 0.20)
		2: # falldownl 向左倒
			_action_tween = _make_action_tween()
			_action_tween.tween_property(self, "rotation", -0.13, 0.28)
			_action_tween.parallel().tween_property(self, "position", base_position + Vector2(-24, 10), 0.28)
			_action_tween.tween_property(self, "rotation", 0.0, 0.30)
			_action_tween.parallel().tween_property(self, "position", base_position, 0.30)
		3: # falldownr 向右倒
			_action_tween = _make_action_tween()
			_action_tween.tween_property(self, "rotation", 0.13, 0.28)
			_action_tween.parallel().tween_property(self, "position", base_position + Vector2(24, 10), 0.28)
			_action_tween.tween_property(self, "rotation", 0.0, 0.30)
			_action_tween.parallel().tween_property(self, "position", base_position, 0.30)
		4: # stiff 小颤抖
			_shake(6.0, 3, 0.05)
		5: # shake 大颤抖
			_shake(16.0, 5, 0.055)
		6: # jump 跳
			_action_tween = _make_action_tween()
			_action_tween.tween_property(self, "position", base_position + Vector2(0, -64), 0.16)
			_action_tween.tween_property(self, "position", base_position, 0.20)
		7: # hophop 蹦跳（两下）
			_action_tween = _make_action_tween()
			for i in 2:
				_action_tween.tween_property(self, "position", base_position + Vector2(0, -46), 0.13)
				_action_tween.tween_property(self, "position", base_position, 0.16)


func _make_action_tween() -> Tween:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return tw


func _shake(amount: float, times: int, step: float) -> void:
	_action_tween = _make_action_tween()
	for i in times:
		var dx := amount if i % 2 == 0 else -amount
		_action_tween.tween_property(self, "position", base_position + Vector2(dx, 0), step)
	_action_tween.tween_property(self, "position", base_position, step)


func show_emoticon(symbol: String) -> void:
	if symbol.is_empty():
		return
	emoticon_label.text = symbol
	emoticon_panel.visible = true
	emoticon_panel.modulate.a = 1.0
	_emoticon_time = 2.6
	if is_inside_tree() and not instant_mode:
		emoticon_panel.pivot_offset = emoticon_panel.size * 0.5
		emoticon_panel.scale = Vector2(0.6, 0.6)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(emoticon_panel, "scale", Vector2.ONE, 0.22)


func hide_emoticon() -> void:
	emoticon_panel.visible = false
	_emoticon_time = 0.0


func flash_shot() -> void:
	if not visible:
		return
	shot_flash.color = Color(1, 1, 1, 0.9)
	if is_inside_tree() and not instant_mode:
		var tw := create_tween()
		tw.tween_property(shot_flash, "color:a", 0.0, 0.28)
	else:
		shot_flash.color.a = 0.0
	rotation = 0.05
	_action_tween = _make_action_tween()
	_action_tween.tween_property(self, "rotation", 0.0, 0.2)


func _process(delta: float) -> void:
	if _emoticon_time > 0.0 and emoticon_panel != null and emoticon_panel.visible:
		_emoticon_time -= delta
		if _emoticon_time <= 0.0:
			emoticon_panel.visible = false
