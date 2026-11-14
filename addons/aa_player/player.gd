class_name AaPlayer
extends Control
## AzureArchive 剧情播放器（运行时可被目录界面/编辑器预览实例化）。
##
## 用法（目录界面）：
##     var p = load("res://scenes/player/Player.tscn").instantiate()
##     add_child(p)
##     p.setup_from_path("user://aa_data/projects/xxx.aap")   # 或 p.setup(project)
##     p.finished.connect(...); p.request_exit.connect(...)
##     p.play()
##
## headless 测试直接调用：set_instant_mode(true) + advance()/choose(i) 或 debug_run_to_finish()。
##
## 设计约定见 docs/DESIGN.md §5.3；不依赖任何导入器产物/外部资源包，
## 缺资源时全部用 AaArt 程序化占位素材正常演出。

signal finished
signal request_exit

const MENU_H := 52

var project: Variant = null
var project_path := ""
var play_data: Dictionary = {}

var stage: AaStage
var dialogue: AaDialogueBox
var choices: AaChoiceOverlay
var backlog: AaBacklog
var audio: AaAudioBus
var auto_play: AaAutoPlay
var interpreter: AaInterpreter
var provider: AaResProvider

var top_menu: PanelContainer
var status_label: Label
var debug_label: Label
var setup_hint: Label
var ending_overlay: Control
var ending_title: Label
var ending_subtitle: Label
var ending_preview: Label
var ending_hint: Label

var instant_mode := false
var finished_flag := false

var _built := false
var _started := false
var _auto_btn: Button
var _ff_btn: Button
var _debug_visible := false
var _collected_texts: Array = []
var _line_text_len := 0
var _voice_len := 0.0
var _choice_auto_time := 0.0
var _exit_unit: Dictionary = {}
var _nextepisode_header := ""
var _nextepisode_title := ""
var _last_status := ""


func _ready() -> void:
	ensure_ui()
	if play_data.is_empty() and project_path.is_empty() and project == null:
		# 直接实例化 Player.tscn 且没有 setup 时，给一个可见的提示（不崩）
		_show_setup_hint("未设置剧情：请先调用 setup_from_path(\"xxx.aap\") 或 setup(project)")


func ensure_ui() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_input(true)
	if size.x < 1.0 or size.y < 1.0:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	stage = AaStage.new()
	stage.name = "Stage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	dialogue = AaDialogueBox.new()
	dialogue.name = "DialogueBox"
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dialogue)

	choices = AaChoiceOverlay.new()
	choices.name = "Choices"
	choices.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(choices)
	choices.chosen.connect(_on_choice_picked)

	backlog = AaBacklog.new()
	backlog.name = "Backlog"
	backlog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backlog)

	audio = AaAudioBus.new()
	audio.name = "AudioBus"
	add_child(audio)

	top_menu = _build_top_menu()
	add_child(top_menu)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.anchor_left = 1.0
	status_label.anchor_right = 1.0
	status_label.offset_left = -620
	status_label.offset_right = -24
	status_label.offset_top = 68
	status_label.offset_bottom = 98
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_override("font", AaArt.ui_font())
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.9))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)

	debug_label = Label.new()
	debug_label.name = "Debug"
	debug_label.anchor_top = 1.0
	debug_label.anchor_bottom = 1.0
	debug_label.offset_left = 30
	debug_label.offset_right = 1200
	debug_label.offset_top = -430
	debug_label.offset_bottom = -330
	debug_label.add_theme_font_override("font", AaArt.ui_font())
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7, 0.85))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.visible = false
	add_child(debug_label)

	setup_hint = Label.new()
	setup_hint.name = "SetupHint"
	setup_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	setup_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_hint.add_theme_font_override("font", AaArt.ui_font())
	setup_hint.add_theme_font_size_override("font_size", 30)
	setup_hint.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	setup_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	setup_hint.visible = false
	add_child(setup_hint)

	_build_ending_overlay()

	auto_play = AaAutoPlay.new()
	interpreter = AaInterpreter.new()
	interpreter.line_started.connect(_on_line_started)
	interpreter.choice_requested.connect(_on_choice_requested)
	interpreter.exit_reached.connect(_on_exit_reached)
	interpreter.finished.connect(_on_finished)
	provider = AaResProvider.create("", null)
	stage.menu_visible_changed.connect(_on_menu_visible_changed)
	stage.shot_fired.connect(_on_shot_fired)

	choices.visible = false
	backlog.visible = false
	ending_overlay.visible = false
	_update_status()


func _build_top_menu() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "TopMenu"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -436
	panel.offset_right = -20
	panel.offset_top = 18
	panel.offset_bottom = 18 + 42
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.11, 0.72)
	style.border_color = Color(0.4, 0.7, 1.0, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(_menu_button("历史", _on_history_pressed))
	_auto_btn = _menu_button("AUTO", _on_auto_pressed)
	box.add_child(_auto_btn)
	_ff_btn = _menu_button("快进", _on_fast_forward_pressed)
	box.add_child(_ff_btn)
	box.add_child(_menu_button("退出", _on_exit_pressed))
	return panel


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", AaArt.ui_font())
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color("#dceeff"))
	b.pressed.connect(cb)
	return b


func _build_ending_overlay() -> void:
	ending_overlay = Control.new()
	ending_overlay.name = "EndingOverlay"
	ending_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ending_overlay.visible = false
	add_child(ending_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.05, 0.90)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_overlay.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_overlay.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	ending_title = Label.new()
	ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_title.add_theme_font_override("font", AaArt.ui_font())
	ending_title.add_theme_font_size_override("font_size", 72)
	ending_title.add_theme_color_override("font_color", Color("#bfe8ff"))
	v.add_child(ending_title)
	ending_subtitle = Label.new()
	ending_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_subtitle.add_theme_font_override("font", AaArt.ui_font())
	ending_subtitle.add_theme_font_size_override("font_size", 36)
	ending_subtitle.add_theme_color_override("font_color", Color("#e8f4ff"))
	v.add_child(ending_subtitle)
	ending_preview = Label.new()
	ending_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending_preview.custom_minimum_size = Vector2(1100, 0)
	ending_preview.add_theme_font_override("font", AaArt.ui_font())
	ending_preview.add_theme_font_size_override("font_size", 26)
	ending_preview.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92, 0.9))
	v.add_child(ending_preview)
	ending_hint = Label.new()
	ending_hint.text = "点击「返回」或按 Esc 退出播放器"
	ending_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_hint.add_theme_font_override("font", AaArt.ui_font())
	ending_hint.add_theme_font_size_override("font_size", 22)
	ending_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.82, 0.85))
	v.add_child(ending_hint)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(260, 64)
	back.add_theme_font_override("font", AaArt.ui_font())
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(_on_exit_pressed)
	var bw := CenterContainer.new()
	bw.add_child(back)
	v.add_child(bw)


# ---------------------------------------------------------------- 对外接口

## 设置剧情数据源。project 可为 aa_core 的 AapProject / PlayScript，或已归一化的 PlayData 字典。
func setup(new_project: Variant) -> void:
	ensure_ui()
	project = new_project
	play_data = {}
	if new_project is Dictionary:
		var d: Dictionary = new_project
		if d.has("units") and d.has("start_guid"):
			play_data = d
		elif d.has("nodes"):
			play_data = AaAapMock.from_dict(d)
		else:
			play_data = {}
	elif new_project != null:
		play_data = AaAapMock.from_core_project(new_project)
	_rebind_provider()
	_reset_runtime()


func setup_from_path(path: String) -> void:
	ensure_ui()
	project_path = path
	project = null
	play_data = {}
	if path.is_empty():
		_show_setup_hint("工程路径为空")
		return
	# 优先 aa_core（若已就绪）；失败/未就绪则用内置 .aap 解析器
	var core_project := _load_project_with_core(path)
	if core_project != null:
		project = core_project
		play_data = AaAapMock.from_core_project(core_project)
	if play_data.is_empty():
		play_data = AaAapMock.from_file(path)
	if play_data.is_empty():
		_show_setup_hint("无法解析工程：\n" + path)
		return
	_rebind_provider()
	_reset_runtime()


func play() -> void:
	ensure_ui()
	if play_data.is_empty():
		if project_path.is_empty():
			_show_setup_hint("未设置剧情：请先调用 setup_from_path() 或 setup(project)")
		else:
			_show_setup_hint("剧情数据为空，无法播放：\n" + project_path)
		return
	setup_hint.visible = false
	finished_flag = false
	_started = true
	_collected_texts.clear()
	_exit_unit = {}
	_nextepisode_header = ""
	_nextepisode_title = ""
	ending_overlay.visible = false
	backlog.clear()
	dialogue.clear()
	choices.hide_choices()
	choices.visible = false
	audio.stop_all()
	audio.stop_voice()
	auto_play.reset()
	_choice_auto_time = 0.0
	stage.reset()
	interpreter.instant_mode = instant_mode
	interpreter.configure(play_data)
	interpreter.start()
	_update_status()


func jump_to(guid: String) -> void:
	ensure_ui()
	if play_data.is_empty():
		return
	finished_flag = false
	_started = true
	ending_overlay.visible = false
	choices.hide_choices()
	backlog.close()
	interpreter.jump_to(guid)
	_update_status()


func is_finished() -> bool:
	return finished_flag


func is_waiting_choice() -> bool:
	return interpreter != null and interpreter.is_waiting_choice()


func is_waiting_click() -> bool:
	return interpreter != null and interpreter.is_waiting_click()


func is_waiting_timer_check() -> bool:
	return interpreter != null and interpreter.is_waiting_timer()


func get_current_guid() -> String:
	return interpreter.current_guid() if interpreter != null else ""


func get_current_line_index() -> int:
	return interpreter.current_index() if interpreter != null else -1


func get_play_data() -> Dictionary:
	return play_data


func set_instant_mode(v: bool) -> void:
	instant_mode = v
	ensure_ui()
	interpreter.instant_mode = v
	stage.set_instant_mode(v)
	dialogue.instant_mode = v


func is_instant_mode() -> bool:
	return instant_mode


## 等价一次点击/空格：打字中 -> 补全；等待点击 -> 下一行；计时等待 -> 跳过。
func advance() -> void:
	if not _built or finished_flag:
		return
	if choices.has_choices():
		return
	if backlog.is_open():
		return
	if interpreter.is_waiting_click():
		if dialogue.is_typing():
			dialogue.skip_typing()
		else:
			interpreter.request_advance()
	elif interpreter.is_waiting_timer():
		interpreter.request_advance()


func choose(index: int) -> void:
	if not _built or finished_flag:
		return
	if choices.has_choices():
		choices.choose(index)
	elif interpreter.is_waiting_choice():
		interpreter.choose(index)


func set_auto(enabled: bool) -> void:
	ensure_ui()
	auto_play.enabled = enabled
	if enabled:
		auto_play.fast_forward = false
	_update_status()


func toggle_auto() -> void:
	set_auto(not auto_play.enabled)


func set_fast_forward(v: bool) -> void:
	ensure_ui()
	auto_play.fast_forward = v
	_update_status()


func is_auto() -> bool:
	return auto_play != null and auto_play.enabled


## headless 测试/自动验收：用即时模式跑到出口。返回统计字典。
func debug_run_to_finish(max_steps := 6000, choice_index := 0) -> Dictionary:
	ensure_ui()
	set_instant_mode(true)
	if not _started:
		play()
	var steps := 0
	var safety := 0
	while steps < max_steps:
		if finished_flag:
			break
		if interpreter.is_waiting_choice():
			var count := choices.choice_count()
			if count <= 0:
				count = 1
			var idx := clampi(choice_index, 0, count - 1)
			choose(idx)
			if interpreter.is_waiting_choice():
				# 选项没被消费（异常数据）：标记失败退出，避免死循环
				break
		elif interpreter.is_waiting_click():
			if dialogue.is_typing():
				dialogue.skip_typing()
			else:
				interpreter.request_advance()
		elif interpreter.is_waiting_timer():
			interpreter.request_advance()
		else:
			# 解释器空闲且未结束：给它一帧机会（正常不会发生）
			safety += 1
			if safety > 8:
				break
		steps += 1
	return {
		"finished": finished_flag,
		"reason": interpreter.finish_reason,
		"steps": steps,
		"lines": interpreter.visited_lines,
		"choices": interpreter.choice_count,
		"texts": _collected_texts.duplicate(),
		"project": play_data.get("project_name", ""),
	}


# ---------------------------------------------------------------- 信号处理

func _on_line_started(line: Dictionary, _index: int) -> void:
	var text := str(line.get("text", ""))
	_collected_texts.append(text)
	var commands: Array = line.get("commands", [])
	var ne := AaText.find_command(commands, "nextepisode")
	if not ne.is_empty():
		var args: Array = ne.get("args", [])
		if args.size() > 0:
			_nextepisode_header = str(args[0])
		if args.size() > 1:
			_nextepisode_title = str(args[1])
	# 舞台环境 + 立绘 + 指令
	stage.apply_environment(line)
	stage.apply_characters(line)
	stage.apply_commands(commands, text)
	_play_character_placeholders(line)
	# 音频
	_apply_audio(line)
	# 对话框 / 屏幕文字
	var has_st := AaText.has_command(commands, "st") or AaText.has_command(commands, "stm")
	var speaker := _speaker_info(line)
	var speaker_name: String = speaker.get("display_name", "")
	var speaker_nick: String = speaker.get("nickname", "")
	if has_st:
		dialogue.set_visible_box(false)
	elif bool(line.get("is_dialog", true)) and not text.strip_edges().is_empty():
		dialogue.set_visible_box(true)
		dialogue.show_line(speaker_name, speaker_nick, text, _voice_len, _voice_len <= 0.0)
	if not text.strip_edges().is_empty():
		backlog.add_entry(speaker_name, text)
	_line_text_len = AaText.plain_length(text)
	auto_play.reset()
	_choice_auto_time = 0.0
	_update_status()


## 没有 Spine/官方资源时的动作/气泡占位音效（有正式音效时以 sound 字段为准，不重复）
func _play_character_placeholders(line: Dictionary) -> void:
	if audio == null:
		return
	if not str(line.get("sound", "")).is_empty():
		return
	var records: Array = line.get("characters", [])
	for r in records:
		if not (r is Dictionary):
			continue
		var action := int(r.get("action", 0))
		if action > 0:
			match action:
				2, 3:
					audio.play_placeholder("falldown")
				6, 7:
					audio.play_placeholder("jump")
				_:
					audio.play_placeholder("greeting")
			return
		if int(r.get("emoticon", -1)) >= 0:
			audio.play_placeholder("click")
			return


func _apply_audio(line: Dictionary) -> void:
	var bgm_id := int(line.get("bgm_id", 0))
	if bgm_id == 999:
		audio.set_bgm(null, 999)
	elif bgm_id != 0:
		var bgm_stream: AudioStream = provider.get_bgm(bgm_id) if provider != null else null
		audio.set_bgm(bgm_stream, bgm_id)
	var se_name := str(line.get("sound", ""))
	if not se_name.is_empty() and provider != null:
		var se := provider.get_sound(se_name)
		if se != null:
			audio.play_se(se)
	var voice_guid := str(line.get("voice", ""))
	_voice_len = 0.0
	if not voice_guid.is_empty() and provider != null:
		var voice := provider.get_voice(voice_guid)
		if voice != null:
			audio.play_voice(voice)
			_voice_len = voice.get_length()
		else:
			audio.stop_voice()


func _speaker_info(line: Dictionary) -> Dictionary:
	var slot := clampi(int(line.get("speaker_slot", 0)), 0, 5)
	var records: Array = line.get("characters", [])
	var id := ""
	if slot < records.size() and records[slot] is Dictionary:
		id = str(records[slot].get("name", ""))
	if id.is_empty():
		return {"display_name": "", "nickname": ""}
	if provider != null:
		var info := provider.get_character(id)
		return {"display_name": str(info.get("display_name", id)), "nickname": str(info.get("nickname", ""))}
	return {"display_name": id, "nickname": ""}


func _on_choice_requested(texts: Array) -> void:
	choices.show_choices(texts)
	_choice_auto_time = 0.0
	_update_status()


func _on_choice_picked(index: int) -> void:
	choices.visible = false
	interpreter.choose(index)
	_update_status()


func _on_exit_reached(unit: Dictionary) -> void:
	_exit_unit = unit


func _on_finished(reason: String) -> void:
	finished_flag = true
	_started = false
	audio.stop_voice()
	_show_ending(reason)
	finished.emit()


func _show_ending(reason: String) -> void:
	var unit := _exit_unit
	var ne_header := str(unit.get("ne_header", "")) if not unit.is_empty() else ""
	var ne_title := str(unit.get("ne_title", "")) if not unit.is_empty() else ""
	if ne_header.is_empty():
		ne_header = _nextepisode_header
	if ne_title.is_empty():
		ne_title = _nextepisode_title
	var is_ending := bool(unit.get("is_ending", false)) if not unit.is_empty() else false
	var end_text := str(unit.get("end_text", "")) if not unit.is_empty() else ""
	var preview := ""
	if unit.get("ne_script") is Dictionary:
		var ne_line: Dictionary = unit["ne_script"]
		preview = str(ne_line.get("text", ""))
		# AA 的 NeScriptDirty.text 可能是 "Header;Title"（isDialogScript=false）
		if not bool(ne_line.get("is_dialog", true)) and preview.contains(";"):
			var parts := preview.split(";")
			if ne_header.is_empty() and parts.size() > 0:
				ne_header = parts[0].strip_edges()
			if ne_title.is_empty() and parts.size() > 1:
				ne_title = parts[1].strip_edges()
			preview = ""
	if is_ending:
		ending_title.text = "Ending"
		ending_subtitle.text = end_text
		ending_preview.text = preview
	elif not ne_title.is_empty() or not ne_header.is_empty():
		ending_title.text = "未完待续"
		var sub := ""
		if not ne_header.is_empty():
			sub = ne_header
		if not ne_title.is_empty():
			sub = sub + " · " + ne_title if not sub.is_empty() else ne_title
		ending_subtitle.text = sub
		ending_preview.text = preview
	elif reason == "ending":
		ending_title.text = "Ending"
		ending_subtitle.text = end_text
		ending_preview.text = preview
	else:
		ending_title.text = "剧情结束"
		ending_subtitle.text = ""
		ending_preview.text = preview
	ending_overlay.visible = true
	choices.hide_choices()
	dialogue.set_visible_box(false)
	backlog.close()
	_update_status()


# ---------------------------------------------------------------- 帧循环 / 输入

func _process(delta: float) -> void:
	if not _built or not _started or finished_flag:
		return
	interpreter.tick(delta)
	if choices.has_choices():
		# AUTO 时默认选择第一个选项（对齐 AA 的 Auto 选项功能：默认选择 + 延迟）
		if auto_play.enabled or auto_play.fast_forward:
			_choice_auto_time += delta
			var delay := 0.2 if auto_play.fast_forward else 1.5
			if _choice_auto_time >= delay:
				var c := 0
				choices.choose(c)
		return
	if backlog.is_open():
		auto_play.reset()
		return
	if auto_play.fast_forward:
		if dialogue.is_typing():
			dialogue.skip_typing()
		if interpreter.is_waiting_timer():
			interpreter.request_advance()
		elif interpreter.is_waiting_click() and not dialogue.is_typing():
			if auto_play.tick(delta, true, _line_text_len, _voice_len):
				interpreter.request_advance()
		return
	if auto_play.enabled:
		var can := interpreter.is_waiting_click() and not dialogue.is_typing()
		if auto_play.tick(delta, can, _line_text_len, _voice_len):
			interpreter.request_advance()
	_update_status()


func _input(event: InputEvent) -> void:
	if not _built:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode == KEY_CTRL or key.physical_keycode == KEY_CTRL:
			if key.pressed:
				auto_play.fast_forward = true
				_update_status()
			else:
				auto_play.fast_forward = false
				_update_status()
			return
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_ESCAPE:
				if backlog.is_open():
					backlog.close()
				elif ending_overlay.visible:
					_on_exit_pressed()
				else:
					_on_exit_pressed()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if not backlog.is_open():
					advance()
			KEY_A:
				toggle_auto()
			KEY_H:
				_toggle_backlog()
			KEY_F8:
				_debug_visible = not _debug_visible
				debug_label.visible = _debug_visible
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				if choices.has_choices():
					var n := int(key.keycode) - int(KEY_1)
					choices.choose(n)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if not backlog.is_open() and not ending_overlay.visible:
					_toggle_backlog()
			MOUSE_BUTTON_LEFT:
				if ending_overlay.visible:
					return
				if backlog.is_open() or choices.has_choices():
					return
				advance()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		pass


# ---------------------------------------------------------------- 界面辅助

func _toggle_backlog() -> void:
	ensure_ui()
	if backlog.is_open():
		backlog.close()
	else:
		backlog.open()


func _on_history_pressed() -> void:
	_toggle_backlog()


func _on_auto_pressed() -> void:
	toggle_auto()


func _on_fast_forward_pressed() -> void:
	auto_play.fast_forward = not auto_play.fast_forward
	_update_status()


func _on_menu_visible_changed(menu_visible: bool) -> void:
	if top_menu != null:
		top_menu.visible = menu_visible


func _on_shot_fired(_slot: int) -> void:
	if audio != null:
		audio.play_placeholder("shot")


func _on_exit_pressed() -> void:
	audio.stop_all()
	audio.stop_voice()
	request_exit.emit()


func _update_status() -> void:
	if not _built:
		return
	var parts: Array = []
	if auto_play != null:
		var st := auto_play.status_text()
		if not st.is_empty():
			parts.append(st)
	if interpreter != null and _debug_visible:
		parts.append("节点 %s · 行 %d" % [interpreter.current_guid().left(8), maxi(interpreter.current_index(), 0)])
	if _debug_visible and interpreter != null:
		debug_label.text = "状态: %s    guid: %s    行: %d\n已播行数: %d   choices: %d   instant: %s" % [
			interpreter.state_name(), interpreter.current_guid(), interpreter.current_index(),
			interpreter.visited_lines, interpreter.choice_count, str(instant_mode)]
	var new_status := "  |  ".join(parts)
	if new_status != _last_status:
		_last_status = new_status
		status_label.text = new_status
	if _auto_btn != null:
		_auto_btn.text = "AUTO●" if auto_play.enabled else "AUTO"
		_ff_btn.text = "快进●" if auto_play.fast_forward else "快进"


func _show_setup_hint(text: String) -> void:
	ensure_ui()
	setup_hint.text = text
	setup_hint.visible = true


func _reset_runtime() -> void:
	if interpreter != null:
		interpreter.configure(play_data)
	_finished_reset_ui()


func _finished_reset_ui() -> void:
	finished_flag = false
	_started = false
	ending_overlay.visible = false
	if dialogue != null:
		dialogue.clear()
	if choices != null:
		choices.hide_choices()
		choices.visible = false
	if stage != null:
		stage.reset()
	if backlog != null:
		backlog.clear()


func _rebind_provider() -> void:
	var context: Variant = _make_context()
	provider = AaResProvider.create(project_path, context)
	if stage != null:
		stage.attach_provider(provider)


func _make_context() -> Variant:
	var node: Node = null
	if is_inside_tree():
		node = get_node_or_null("/root/AAResources")
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			node = tree.root.get_node_or_null("AAResources")
	if node == null:
		return null
	if node.has_method("make_context"):
		var ctx: Variant = node.call("make_context", project_path, "")
		return ctx
	return null


## 用 aa_core 的 AapProject 解析（若已就绪）；失败返回 null。
func _load_project_with_core(path: String) -> Variant:
	# 文件不存在时不要调 core（core 会 push_error 刷屏）；交给调用方显示提示
	if not FileAccess.file_exists(path):
		return null
	var core_path := "res://addons/aa_core/aap_project.gd"
	if not FileAccess.file_exists(core_path):
		return null
	var script: Script = load(core_path)
	if script == null:
		return null
	var methods: Array = script.get_script_method_list()
	var has_loader := false
	for m in methods:
		if str(m.get("name", "")) == "load_from_file":
			has_loader = true
			break
	if not has_loader:
		return null
	var result: Variant = script.call("load_from_file", path)
	return result
