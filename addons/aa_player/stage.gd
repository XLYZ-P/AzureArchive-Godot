class_name AaStage
extends Control
## 舞台：背景 / 5 立绘槽 / 弹出图 / 屏幕文字 / 特效 / 菜单显隐。
## 逻辑坐标：屏幕宽固定 2960 单位、原点在屏幕中心、Y 向下（源码里再换算到 1920×1080 像素）。

signal menu_visible_changed(visible: bool)
signal shot_fired(slot: int)

const LOGICAL_WIDTH := 2960.0
## 1–5 号槽位的逻辑 x（左、中偏左、中、中偏右、右）
const SLOT_X := [-1180.0, -590.0, 0.0, 590.0, 1180.0]
## 立绘底边 / 高度（逻辑单位）
const CHARACTER_BOTTOM_Y := 812.0
const CHARACTER_HEIGHT := 1350.0
const CHARACTER_ASPECT := 0.50
## 屏幕文字 50 = 原大小（对应 30px）
const SCREEN_TEXT_BASE_PX := 30

var provider: AaResProvider = null
var instant_mode := false

var bg_clip: Control
var bg_rect: TextureRect
var bg_prev_rect: TextureRect
var char_layer: Control
var popup_layer: Control
var screen_text_layer: Control
var fx_layer: Control
var transition_rect: ColorRect
var place_panel: PanelContainer
var place_label: Label
var bg_label: Label
var bg_effect_rect: TextureRect
var bg_effect_label: Label

var views: Array = []
## 下标 0..5：每个「数组槽位」当前的角色 id / 视图
var slot_ids: Array = ["", "", "", "", "", ""]
var slot_views: Array = [null, null, null, null, null, null]

var _built := false
var _cur_bg_name := ""
var _cur_bg_id := -1
var _cur_popup := ""
var _cur_place := ""
var _cur_effect := -1
var _zmc_zoom := 1.0
var _zmc_center := Vector2.ZERO
var _bg_base_size := Vector2(1920, 1080)

var _transition_tween: Tween = null
var _shake_tween: Tween = null
var _zmc_from_zoom := 1.0
var _zmc_from_center := Vector2.ZERO
var _zmc_to_zoom := 1.0
var _zmc_to_center := Vector2.ZERO
var _screen_texts: Array = []
var _effects: Array = []


func _ready() -> void:
	ensure_built()
	resized.connect(_on_resized)
	_on_resized()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_clip = _make_layer("BgClip")
	bg_clip.clip_contents = true
	bg_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg_clip)

	bg_rect = TextureRect.new()
	bg_rect.name = "BgRect"
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_clip.add_child(bg_rect)
	# 交叉溶解过渡用的「上一张背景」快照（盖在新背景之上淡出）
	bg_prev_rect = TextureRect.new()
	bg_prev_rect.name = "BgPrev"
	bg_prev_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_prev_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_prev_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_prev_rect.visible = false
	bg_prev_rect.modulate = Color(1, 1, 1, 0)
	bg_clip.add_child(bg_prev_rect)

	char_layer = _make_layer("Characters")
	add_child(char_layer)
	popup_layer = _make_layer("Popups")
	add_child(popup_layer)
	screen_text_layer = _make_layer("ScreenText")
	add_child(screen_text_layer)
	fx_layer = _make_layer("Fx")
	add_child(fx_layer)

	bg_effect_rect = TextureRect.new()
	bg_effect_rect.name = "BgEffect"
	bg_effect_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_effect_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_effect_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_effect_rect.modulate = Color(1, 1, 1, 0)
	fx_layer.add_child(bg_effect_rect)

	bg_effect_label = Label.new()
	bg_effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(bg_effect_label, 22)
	bg_effect_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	bg_effect_label.visible = false
	bg_effect_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bg_effect_label.offset_left = -300
	bg_effect_label.offset_right = 300
	bg_effect_label.offset_top = -120
	bg_effect_label.offset_bottom = -90
	bg_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx_layer.add_child(bg_effect_label)

	transition_rect = ColorRect.new()
	transition_rect.name = "Transition"
	transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_rect.color = Color(0, 0, 0, 0)
	transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(transition_rect)

	place_panel = PanelContainer.new()
	place_panel.name = "Place"
	place_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var place_style := StyleBoxFlat.new()
	place_style.bg_color = Color(0.04, 0.07, 0.12, 0.72)
	place_style.border_color = Color(0.55, 0.8, 1.0, 0.9)
	place_style.set_border_width_all(2)
	place_style.set_corner_radius_all(10)
	place_style.set_content_margin_all(14)
	place_panel.add_theme_stylebox_override("panel", place_style)
	place_label = Label.new()
	_apply_font(place_label, 30)
	place_label.add_theme_color_override("font_color", Color("#dceeff"))
	place_panel.add_child(place_label)
	place_panel.visible = false
	add_child(place_panel)

	# 背景名小字（调试用，可关）
	bg_label = Label.new()
	bg_label.name = "BgLabel"
	bg_label.position = Vector2(22, 14)
	bg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(bg_label, 17)
	bg_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.55))
	bg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	bg_label.visible = false
	add_child(bg_label)

	for i in 5:
		var view := AaCharacterView.new()
		view.name = "Char%d" % (i + 1)
		view.setup(i + 1)
		char_layer.add_child(view)
		views.append(view)
	_layout_views()


func _make_layer(layer_name: String) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _apply_font(ctrl: Control, size: int) -> void:
	var f := AaArt.ui_font()
	if f != null:
		ctrl.add_theme_font_override("font", f)
	ctrl.add_theme_font_size_override("font_size", size)


func attach_provider(res: AaResProvider) -> void:
	provider = res


func set_instant_mode(v: bool) -> void:
	instant_mode = v


# ---------------------------------------------------------------- 坐标换算

func _stage_size() -> Vector2:
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		if is_inside_tree():
			s = get_viewport_rect().size
	if s.x < 1.0 or s.y < 1.0:
		s = Vector2(1920, 1080)
	return s


func _logical_scale() -> float:
	return _stage_size().x / LOGICAL_WIDTH


## AA 屏幕空间（中心原点，X 右正、Y **上**正，屏宽固定 2960）-> 屏幕像素
func logical_to_px(p: Vector2) -> Vector2:
	var s := _stage_size()
	var sc := _logical_scale()
	return Vector2(s.x * 0.5 + p.x * sc, s.y * 0.5 - p.y * sc)


func slot_px_x(slot: int) -> float:
	var idx := clampi(slot - 1, 0, 4)
	return logical_to_px(Vector2(SLOT_X[idx], 0.0)).x


func _on_resized() -> void:
	_bg_base_size = _stage_size()
	_layout_views()
	_update_bg_transform()
	_layout_place_panel()


func _layout_views() -> void:
	if views.is_empty():
		return
	var s := _logical_scale()
	var h := CHARACTER_HEIGHT * s
	var w := h * CHARACTER_ASPECT
	# AA 屏幕空间 Y 上正：立绘底边在中心下方
	var bottom := logical_to_px(Vector2(0.0, -CHARACTER_BOTTOM_Y)).y
	for i in views.size():
		var view: AaCharacterView = views[i]
		view.set_art_size(Vector2(w, h))
		view.set_base_position(Vector2(slot_px_x(i + 1) - w * 0.5, bottom - h), true)
		view.instant_mode = instant_mode


func _layout_place_panel() -> void:
	if place_panel == null:
		return
	var s := _stage_size()
	place_panel.position = Vector2(s.x * 0.045, s.y * 0.05)
	place_panel.reset_size()


# ---------------------------------------------------------------- 环境

## 应用一行的环境（背景/过渡/弹出图/地点/背景效果）。返回是否发生背景切换。
func apply_environment(line: Dictionary) -> bool:
	ensure_built()
	var bg_changed := false
	var friendly := str(line.get("bg_friendly_name", ""))
	var bg_id := int(line.get("bg_name", 0))
	var trans := int(line.get("transition", 0))
	var trans_info := AaText.transition_info(trans)
	if friendly != _cur_bg_name or bg_id != _cur_bg_id:
		bg_changed = true
		_cur_bg_name = friendly
		_cur_bg_id = bg_id
		var old_tex: Texture2D = bg_rect.texture
		var tex: Texture2D = null
		if provider != null and (not friendly.is_empty() or bg_id != 0):
			tex = provider.get_bg(friendly, bg_id)
		if tex == null:
			var seed_key := friendly if not friendly.is_empty() else "BG_%d" % bg_id
			tex = AaArt.bg_texture(AaArt.seed_of(seed_key) + bg_id)
		bg_rect.texture = tex
		_update_bg_label()
		_reset_zmc()
		if not instant_mode:
			_play_transition(trans_info, bg_changed, old_tex)
	elif trans != 0 and not instant_mode:
		_play_transition(trans_info, false, null)
	# 地点
	var place := str(line.get("place_text", ""))
	if place != _cur_place:
		_cur_place = place
		if place.is_empty():
			place_panel.visible = false
		else:
			place_label.text = place
			_layout_place_panel()
			place_panel.visible = true
			place_panel.modulate.a = 0.0 if not instant_mode else 1.0
			if not instant_mode:
				var tw := create_tween()
				tw.tween_property(place_panel, "modulate:a", 1.0, 0.35)
	# 弹出图
	var popup := str(line.get("popup", ""))
	if popup != _cur_popup:
		_cur_popup = popup
		_apply_popup(popup)
	# 背景效果
	var effect := int(line.get("bg_effect", 0))
	if effect != _cur_effect:
		_cur_effect = effect
		_apply_bg_effect(effect)
	return bg_changed


## 按 transition 表近似演出：crossfade=溶解、Fade=黑场淡入、Fade White=白场、Swipe/Noise/Circle 近似。
## 说明：AA 的过渡是「从上一脚本切到这一脚本」的全屏过渡；这里在行开始时播放（进入动画）。
func set_bg_label_visible(v: bool) -> void:
	if bg_label != null:
		bg_label.visible = v


func _update_bg_label() -> void:
	if bg_label == null:
		return
	var txt := _cur_bg_name
	if txt.is_empty():
		txt = "BG_%d" % _cur_bg_id if _cur_bg_id != 0 else "（无背景）"
	if _zmc_zoom != 1.0:
		txt += "  zoom %.2f" % _zmc_zoom
	bg_label.text = txt
	bg_label.visible = true


func _play_transition(info: Dictionary, bg_changed: bool, old_tex: Texture2D) -> void:
	var kind := str(info.get("kind", "cut"))
	var duration := float(info.get("duration", 0.5))
	if kind == "cut" or duration <= 0.0:
		return
	if kind == "crossfade" and not (bg_changed and old_tex != null):
		kind = "fade"
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	match kind:
		"crossfade":
			if bg_changed and old_tex != null:
				# 上一张背景盖在新背景上淡出 = 交叉溶解
				bg_prev_rect.texture = old_tex
				bg_prev_rect.size = bg_rect.size
				bg_prev_rect.position = bg_rect.position
				bg_prev_rect.modulate = Color(1, 1, 1, 1)
				bg_prev_rect.visible = true
				_transition_tween.tween_property(bg_prev_rect, "modulate:a", 0.0, duration)
				_transition_tween.tween_callback(func() -> void:
					bg_prev_rect.visible = false
					bg_prev_rect.texture = null)
		"fade_white":
			transition_rect.color = Color(1, 1, 1, 0.95)
			_transition_tween.tween_property(transition_rect, "color:a", 0.0, duration)
		"fade":
			transition_rect.color = Color(0.0, 0.0, 0.0, 1.0)
			_transition_tween.tween_property(transition_rect, "color:a", 0.0, duration)
		"noise", "circle":
			transition_rect.color = Color(0.0, 0.0, 0.0, 0.7)
			_transition_tween.tween_property(transition_rect, "color:a", 0.0, maxf(duration * 0.6, 0.25))
		"swipe_l", "swipe_r", "swipe_u", "swipe_d":
			# 简化：用深色遮罩快速掠过近似扫屏
			transition_rect.color = Color(0.02, 0.03, 0.06, 0.85)
			_transition_tween.tween_property(transition_rect, "color:a", 0.0, maxf(duration * 0.5, 0.2))
		_:
			transition_rect.color = Color(0.0, 0.0, 0.0, 0.8)
			_transition_tween.tween_property(transition_rect, "color:a", 0.0, duration)


func _play_bg_change_fade() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	transition_rect.color = Color(0, 0, 0, 0.55)
	_transition_tween = create_tween()
	_transition_tween.tween_property(transition_rect, "color:a", 0.0, 0.35)


func _apply_popup(popup_name: String) -> void:
	for c in popup_layer.get_children():
		c.queue_free()
	if popup_name.is_empty():
		return
	var tex: Texture2D = null
	if provider != null:
		tex = provider.get_popup(popup_name)
	if tex == null:
		tex = AaArt.popup_texture(AaArt.seed_of(popup_name))
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _logical_scale()
	var psize := Vector2(380, 480) * (s / 0.648648)
	var center := logical_to_px(Vector2(760.0, -120.0))
	rect.size = psize
	rect.position = center - psize * 0.5
	rect.modulate.a = 0.0 if not instant_mode else 1.0
	popup_layer.add_child(rect)
	if not instant_mode:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(rect, "modulate:a", 1.0, 0.25)
		tw.parallel().tween_property(rect, "position:y", rect.position.y - 18.0, 0.25)


func _apply_bg_effect(effect_id: int) -> void:
	if effect_id <= 0:
		bg_effect_rect.modulate.a = 0.0
		bg_effect_label.visible = false
		return
	bg_effect_rect.texture = AaArt.radial_texture(effect_id)
	bg_effect_label.text = AaText.bg_effect_label(effect_id)
	bg_effect_label.visible = true
	bg_effect_rect.modulate.a = 0.0
	if instant_mode:
		bg_effect_rect.modulate.a = 0.35
		return
	var tw := create_tween()
	tw.tween_property(bg_effect_rect, "modulate:a", 0.55, 0.25)
	tw.tween_property(bg_effect_rect, "modulate:a", 0.0, 1.1)
	tw.tween_callback(func() -> void: bg_effect_label.visible = false)


# ---------------------------------------------------------------- 立绘

## 应用一行的 5 个立绘槽状态（含进出场/走位/表情/高亮/气泡/动作）。
func apply_characters(line: Dictionary) -> void:
	ensure_built()
	var records: Array = line.get("characters", [])
	var instant := instant_mode
	for i in range(1, 6):
		var rec := _record_at(records, i)
		var new_id := str(rec.get("name", ""))
		var cur_id := str(slot_ids[i])
		var view: AaCharacterView = slot_views[i]
		if new_id.is_empty():
			if view != null:
				view.hide_character(6, instant)
			slot_ids[i] = ""
			slot_views[i] = null
			continue
		var info := _character_info(new_id)
		var start_slot := int(rec.get("starting_pos", i))
		if start_slot < 1 or start_slot > 5:
			start_slot = i
		if view == null or cur_id != new_id:
			# 新角色 / 换人：旧视图立刻消失，找一个空闲视图重新登场
			if view != null:
				view.hide_character(6, true)
			view = _find_free_view()
			if view == null:
				continue
			view.set_base_position(_view_base_for_slot(start_slot), true)
			var appear := int(rec.get("appear", 0))
			if appear <= 0 or appear == 6:
				appear = 3
			view.show_character(new_id, str(info.get("display_name", new_id)),
				str(info.get("nickname", "")), info.get("portrait", null), appear, instant)
			slot_ids[i] = new_id
			slot_views[i] = view
		else:
			# 留在场上：更新位置 / 表情
			if start_slot != i:
				view.set_base_position(_view_base_for_slot(start_slot), instant)
			var face := str(rec.get("face_id", "00"))
			var faces: Dictionary = info.get("faces", {})
			var face_tex: Variant = faces.get(face, null) if face != "00" else null
			view.set_face(face, face_tex)
		view.set_shape(int(rec.get("shape_override", 0)))
		var ending := int(rec.get("ending_pos", i))
		if ending >= 1 and ending <= 5 and ending != start_slot:
			_move_view_to_slot(i, ending, instant)
		elif ending >= 1 and ending <= 5:
			view.set_base_position(_view_base_for_slot(ending), instant)
			if slot_views[i] == null:
				slot_ids[i] = new_id
				slot_views[i] = view
		var action := int(rec.get("action", 0))
		if action > 0:
			view.play_action(action, instant)
		var emo := int(rec.get("emoticon", -1))
		if emo >= 0:
			view.show_emoticon(AaText.emoticon_text(emo))
		if int(rec.get("appear", 0)) == 6:
			view.hide_character(6, instant)
			slot_ids[i] = ""
			slot_views[i] = null
	_apply_highlight(line)


func _record_at(records: Array, i: int) -> Dictionary:
	if i >= 0 and i < records.size() and records[i] is Dictionary:
		return records[i]
	return AaAapMock.empty_record()


func _character_info(id: String) -> Dictionary:
	if provider != null:
		return provider.get_character(id)
	return {"id": id, "display_name": id, "nickname": "", "portrait": null, "faces": {}}


func _find_free_view() -> AaCharacterView:
	for v in views:
		var cv: AaCharacterView = v
		if not cv.visible:
			return cv
	# 全部在用：复用最右槽（数据异常时兜底）
	return views[views.size() - 1]


func _view_base_for_slot(slot: int) -> Vector2:
	var s := _logical_scale()
	var h := CHARACTER_HEIGHT * s
	var w := h * CHARACTER_ASPECT
	var bottom := logical_to_px(Vector2(0.0, -CHARACTER_BOTTOM_Y)).y
	return Vector2(slot_px_x(slot) - w * 0.5, bottom - h)


func _prepare_view_visual(view: AaCharacterView, slot: int, instant: bool) -> void:
	view.set_base_position(_view_base_for_slot(slot), instant)


## 走位：把槽位 i 的角色移动到 ending 号槽的初始位置，并迁移槽位映射。
func _move_view_to_slot(from_slot: int, to_slot: int, instant: bool) -> void:
	var view: AaCharacterView = slot_views[from_slot]
	if view == null:
		return
	view.set_base_position(_view_base_for_slot(to_slot), instant)
	var moved_id: String = slot_ids[from_slot]
	slot_ids[from_slot] = ""
	slot_views[from_slot] = null
	if slot_views[to_slot] == null:
		slot_ids[to_slot] = moved_id
		slot_views[to_slot] = view
	else:
		# 目标槽有人（数据异常）：视图仍然显示，只是不迁移映射
		pass


func _apply_highlight(line: Dictionary) -> void:
	var hl: Array = line.get("highlighted_slots", [])
	var speaker := int(line.get("speaker_slot", 0))
	var bright := {}
	if hl.is_empty():
		for i in range(1, 6):
			if slot_views[i] != null:
				bright[i] = true
	else:
		for n in hl:
			bright[int(n)] = true
	if speaker >= 1 and speaker <= 5:
		bright[speaker] = true
	for i in range(1, 6):
		if slot_views[i] != null:
			slot_views[i].set_dim(not bright.has(i))


func clear_characters(instant := true) -> void:
	for i in range(1, 6):
		if slot_views[i] != null:
			slot_views[i].hide_character(6, instant)
		slot_views[i] = null
		slot_ids[i] = ""


# ---------------------------------------------------------------- 额外指令

## 应用一行的额外指令。text 是该行台词（供 #st/#stm 使用）。
func apply_commands(commands: Array, text: String) -> void:
	ensure_built()
	for cmd in commands:
		if not (cmd is Dictionary):
			continue
		var c: Dictionary = cmd
		var name := str(c.get("name", ""))
		var slot := int(c.get("slot", -1))
		if name == "st" or name == "stm":
			_add_screen_text(text, c)
		elif name == "clearST":
			clear_screen_text()
		elif name == "bgshake":
			bg_shake()
		elif name == "zmc":
			apply_zmc(c)
		elif name == "fx":
			var fx := str(c.get("fx", ""))
			if fx.to_lower() == "aronatouch":
				arona_touch()
		elif name == "hidemenu":
			menu_visible_changed.emit(false)
		elif name == "showmenu":
			menu_visible_changed.emit(true)
		elif name == "shot" or (name == "fx" and str(c.get("fx", "")).contains("shot")):
			if slot >= 1 and slot <= 5:
				shot(slot)
		elif name == "hide":
			if slot >= 1 and slot <= 5 and slot_views[slot] != null:
				slot_views[slot].hide_character(6, instant_mode)
				slot_ids[slot] = ""
				slot_views[slot] = null
		elif name.begins_with("m") and name.substr(1).is_valid_int():
			var to_slot := int(name.substr(1))
			if to_slot >= 1 and to_slot <= 5:
				_move_view_to_slot(slot, to_slot, instant_mode)
		elif name in ["al", "ar", "a", "dl", "dr", "d"]:
			if slot >= 1 and slot <= 5 and slot_views[slot] != null:
				match name:
					"d", "dl", "dr":
						slot_views[slot].hide_character(_exit_mode(name), instant_mode)
						slot_ids[slot] = ""
						slot_views[slot] = null
					_:
						var v: AaCharacterView = slot_views[slot]
						v.show_character(v.char_id, v.display_name, v.nickname, null,
							_appear_mode(name), instant_mode)


func _appear_mode(cmd_name: String) -> int:
	match cmd_name:
		"al":
			return 1
		"ar":
			return 2
		"a":
			return 3
	return 3


func _exit_mode(cmd_name: String) -> int:
	match cmd_name:
		"dl":
			return 4
		"dr":
			return 5
		"d":
			return 6
	return 6


func shot(slot: int) -> void:
	if slot >= 1 and slot <= 5 and slot_views[slot] != null:
		slot_views[slot].flash_shot()
		shot_fired.emit(slot)


func bg_shake() -> void:
	if instant_mode:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var targets: Array = [bg_rect]
	if char_layer != null:
		targets.append(char_layer)
	var base_positions := {}
	for t in targets:
		base_positions[t] = (t as Control).position
	for step in 6:
		var dir := 1.0 if step % 2 == 0 else -1.0
		var amp := 18.0 * (1.0 - step / 7.0) * dir
		for t in targets:
			var ctrl: Control = t
			var base: Vector2 = base_positions[t]
			var target := base + Vector2(amp, amp * 0.35)
			_shake_tween.parallel().tween_property(ctrl, "position", target, 0.05)
	for t in targets:
		var ctrl: Control = t
		var base: Vector2 = base_positions[t]
		_shake_tween.parallel().tween_property(ctrl, "position", base, 0.06)


## #zmc;模式;X,Y;缩放系数;持续时间 —— 平移与缩放背景
func apply_zmc(cmd: Dictionary) -> void:
	var p := AaText.parse_zmc(cmd)
	var to_zoom: float = p.get("zoom", 1.0)
	var to_center: Vector2 = p.get("center", Vector2.ZERO)
	var mode := str(p.get("mode", "instant"))
	var duration := float(p.get("duration", 0.0))
	if instant_mode or mode != "smooth" or duration <= 0.0:
		_zmc_zoom = to_zoom
		_zmc_center = to_center
		_update_bg_transform()
		return
	_zmc_from_zoom = _zmc_zoom
	_zmc_from_center = _zmc_center
	_zmc_to_zoom = to_zoom
	_zmc_to_center = to_center
	var tw := create_tween()
	tw.tween_method(_zmc_step, 0.0, 1.0, duration)


func _zmc_step(t: float) -> void:
	_zmc_zoom = lerpf(_zmc_from_zoom, _zmc_to_zoom, t)
	_zmc_center = _zmc_from_center.lerp(_zmc_to_center, t)
	_update_bg_transform()
	_update_bg_label()


func _reset_zmc() -> void:
	_zmc_zoom = 1.0
	_zmc_center = Vector2.ZERO
	_update_bg_transform()


func _update_bg_transform() -> void:
	if bg_rect == null:
		return
	var st := _stage_size()
	var sc := st.x / LOGICAL_WIDTH
	var center_px := Vector2(_zmc_center.x * sc, -_zmc_center.y * sc)
	bg_rect.size = st * _zmc_zoom
	bg_rect.position = st * 0.5 - (center_px + st * 0.5) * _zmc_zoom


## #st / #stm 屏幕文字（文字内容来自该行台词的 text）
func _add_screen_text(text: String, cmd: Dictionary) -> void:
	if text.strip_edges().is_empty():
		return
	var p := AaText.parse_screen_text(cmd)
	var size_ratio := float(int(p.get("size", 50))) / 50.0
	var px := maxi(int(SCREEN_TEXT_BASE_PX * size_ratio), 12)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_override("normal_font", AaArt.ui_font())
	rt.add_theme_font_size_override("normal_font_size", px)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rt.add_theme_constant_override("outline_size", 6)
	var bb := AaText.to_bbcode(text, px)
	var centered: bool = p.get("centered", false)
	if centered:
		bb = "[center]%s[/center]" % bb
	rt.text = bb
	var s := _stage_size()
	var pos: Vector2 = p.get("pos", Vector2.ZERO)
	var anchor_px := logical_to_px(pos)
	rt.size = Vector2(s.x, 320)
	if centered:
		rt.position = Vector2(0, anchor_px.y - px)
	else:
		rt.position = Vector2(anchor_px.x, anchor_px.y - px)
	screen_text_layer.add_child(rt)
	_screen_texts.append(rt)
	match str(p.get("mode", "instant")):
		"smooth":
			if instant_mode:
				rt.modulate.a = 1.0
			else:
				rt.modulate.a = 0.0
				var tw := create_tween()
				tw.tween_property(rt, "modulate:a", 1.0, 0.7)
		"serial":
			if instant_mode:
				rt.visible_ratio = 1.0
			else:
				rt.visible_ratio = 0.0
				var total := maxf(float(AaText.plain_length(text)), 1.0)
				var tw := create_tween()
				tw.tween_property(rt, "visible_ratio", 1.0, total * 0.05)
		_:
			rt.modulate.a = 1.0


func clear_screen_text() -> void:
	for rt in _screen_texts:
		if is_instance_valid(rt):
			rt.queue_free()
	_screen_texts.clear()


## #fx;AronaTouch 占位特效
func arona_touch() -> void:
	var rect := TextureRect.new()
	rect.texture = AaArt.arona_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _stage_size()
	rect.size = Vector2(s.y * 0.62, s.y * 0.62)
	rect.position = s * 0.5 - rect.size * 0.5
	rect.modulate.a = 0.0
	fx_layer.add_child(rect)
	var label := Label.new()
	label.text = "AronaTouch（特效占位）"
	_apply_font(label, 26)
	label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.9))
	label.position = s * 0.5 + Vector2(-140, s.y * 0.22)
	fx_layer.add_child(label)
	_effects.append(rect)
	_effects.append(label)
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(rect, "rotation", 0.5, 1.2)
	tw.tween_interval(0.7)
	tw.tween_property(rect, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		if is_instance_valid(rect):
			rect.queue_free()
		if is_instance_valid(label):
			label.queue_free())


func _process(_delta: float) -> void:
	# 清理已释放的特效引用
	if not _effects.is_empty():
		var alive: Array = []
		for e in _effects:
			if is_instance_valid(e):
				alive.append(e)
		_effects = alive


# ---------------------------------------------------------------- 复位

func reset() -> void:
	ensure_built()
	clear_characters(true)
	clear_screen_text()
	for c in popup_layer.get_children():
		c.queue_free()
	_cur_popup = ""
	_cur_place = ""
	place_panel.visible = false
	_cur_effect = -1
	bg_effect_rect.modulate.a = 0.0
	bg_effect_label.visible = false
	_cur_bg_name = ""
	_cur_bg_id = -1
	bg_rect.texture = null
	bg_label.visible = false
	_reset_zmc()
	transition_rect.color = Color(0, 0, 0, 0)
	menu_visible_changed.emit(true)
