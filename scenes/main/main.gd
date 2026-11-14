extends Control
## 目录界面（Lead 维护）
## 功能：工程/存档列表（AA 数据目录）、播放、编辑、新建、导入、数据目录设置、资源包管理。
## 依赖：AAResources（pack-dev 实现，DESIGN §5.2）、scenes/player/Player.tscn、scenes/editor/Editor.tscn。

const FONT_PATH := "res://assets/fonts/wqy-zenhei-extracted.ttf"
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"

static var _font_cache: Font = null

var project_list: ItemList
var save_list: ItemList
var status: Label
var path_label: Label
var title_label: Label
var detail_label: Label
var tabs: TabBar
var overlay_root: Control


func _ready() -> void:
	_build_ui()
	refresh()


func _font() -> Font:
	if _font_cache == null:
		_font_cache = AaRawLoader.load_font(FONT_PATH)
	return _font_cache


func _mk_button(text: String, cb: Callable, min_h := 48) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = min_h
	var f := _font()
	if f:
		b.add_theme_font_override("font", f)
		b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _mk_label(text: String, size := 18, color := Color("#cbd5e1")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := _font()
	if f:
		l.add_theme_font_override("font", f)
	return l


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1220")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var grad := ColorRect.new()
	grad.color = Color("#10233f")
	grad.modulate.a = 0.55
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grad)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# ------- 顶栏 -------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	title_label = _mk_label("AzureArchive · Godot", 40, Color("#7fd4ff"))
	header.add_child(title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	path_label = _mk_label("", 15, Color("#64748b"))
	header.add_child(path_label)

	# ------- 主体 -------
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 760
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	var tabs_row := HBoxContainer.new()
	left.add_child(tabs_row)
	var list_title := _mk_label("工程 / 存档", 22, Color("#e2e8f0"))
	tabs_row.add_child(list_title)
	var tabs_spacer := Control.new()
	tabs_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_row.add_child(tabs_spacer)
	tabs_row.add_child(_mk_button("刷新", refresh, 38))

	tabs = TabBar.new()
	tabs.add_tab("剧情工程 .aap")
	tabs.add_tab("剧情存档 .aas")
	tabs.tab_changed.connect(func(_i: int) -> void: _update_list_visibility())
	left.add_child(tabs)

	project_list = _mk_item_list()
	left.add_child(project_list)
	save_list = _mk_item_list()
	left.add_child(save_list)

	# ------- 右侧操作栏 -------
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 430
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style())
	right.add_child(card)
	var card_v := VBoxContainer.new()
	card_v.add_theme_constant_override("separation", 8)
	card.add_child(card_v)
	card_v.add_child(_mk_label("当前选中", 16, Color("#94a3b8")))
	detail_label = _mk_label("（未选择）", 19, Color("#e2e8f0"))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.y = 140
	card_v.add_child(detail_label)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right.add_child(actions)
	actions.add_child(_mk_button("▶  播放选中工程", _on_play))
	actions.add_child(_mk_button("✎  编辑选中工程", _on_edit))
	actions.add_child(_mk_button("＋  新建工程", _on_new_project))
	actions.add_child(_mk_button("⇩  导入 .aap/.aas 文件", _on_import))
	actions.add_child(_mk_button("★  载入内置示例工程", _on_load_samples))
	actions.add_child(_mk_button("?  操作说明", _on_help))
	actions.add_child(_mk_button("📦  资源包管理", _on_packs))
	actions.add_child(_mk_button("📁  数据目录设置", _on_data_dir))
	actions.add_child(_mk_button("⏻  退出", func() -> void: get_tree().quit()))

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer2)

	status = _mk_label("", 15, Color("#94a3b8"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 110
	right.add_child(status)

	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)

	_update_list_visibility()
	path_label.text = "数据目录：" + _data_root()


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#111c2e")
	s.border_color = Color("#1e3a5f")
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s


func _mk_item_list() -> ItemList:
	var l := ItemList.new()
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 19)
	var f := _font()
	if f:
		l.add_theme_font_override("font", f)
	l.item_selected.connect(_on_selection_changed)
	l.item_activated.connect(func(_i: int) -> void: _on_play())
	return l


func _data_root() -> String:
	var v: Variant = AAResources.get("data_root")
	return str(v) if v != null else "（未知）"


func _call_res(method: String, args: Array) -> Variant:
	if AAResources == null or not AAResources.has_method(method):
		return []
	return AAResources.callv(method, args)


func refresh() -> void:
	if project_list == null:
		return
	project_list.clear()
	save_list.clear()
	var projects: Array = _call_res("get_projects", [])
	for p in projects:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var label := str(p.get("name", "?"))
		if str(p.get("category", "")) != "":
			label = "[%s] %s" % [str(p.get("category")), label]
		project_list.add_item(label)
		project_list.set_item_metadata(project_list.item_count - 1, p)
	var saves: Array = _call_res("get_saves", [])
	for s in saves:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		save_list.add_item(str(s.get("name", "?")))
		save_list.set_item_metadata(save_list.item_count - 1, s)
	path_label.text = "数据目录：" + _data_root()
	status.text = "工程 %d 个 · 存档 %d 个 · 资源包 %d 个" % [
		projects.size(), saves.size(), _call_res("get_packs", []).size()
	]


func _current_list() -> ItemList:
	return project_list if tabs.current_tab == 0 else save_list


func _update_list_visibility() -> void:
	if project_list == null:
		return
	project_list.visible = tabs.current_tab == 0
	save_list.visible = tabs.current_tab == 1


func _selected_entry() -> Dictionary:
	var list := _current_list()
	var sel := list.get_selected_items()
	if sel.is_empty():
		return {}
	var md: Variant = list.get_item_metadata(sel[0])
	return md if typeof(md) == TYPE_DICTIONARY else {}


func _on_selection_changed(_idx: int) -> void:
	var e := _selected_entry()
	if e.is_empty():
		detail_label.text = "（未选择）"
		return
	var lines: Array[String] = []
	lines.append("名称：%s" % str(e.get("name", "?")))
	if e.has("path"):
		lines.append("路径：%s" % str(e.get("path", "")))
	for k in ["path", "category", "modified", "preview_title", "preview_header"]:
		if e.has(k) and str(e.get(k)) != "":
			lines.append("%s：%s" % [k, str(e.get(k))])
	detail_label.text = "\n".join(lines)
	status.text = "已选中：" + str(e.get("path", e.get("name", "")))


func _on_play() -> void:
	var e := _selected_entry()
	if e.is_empty():
		status.text = "请先选择一个工程/存档"
		return
	var path := str(e.get("path", ""))
	if path == "":
		status.text = "没有可播放的文件路径"
		return
	if not ResourceLoader.exists(PLAYER_SCENE):
		status.text = "播放器尚未就绪（scenes/player/Player.tscn 不存在）"
		return
	var player: Node = load(PLAYER_SCENE).instantiate()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(player)
	if player.has_method("setup_from_path"):
		player.call("setup_from_path", path)
	if player.has_signal("request_exit"):
		player.connect("request_exit", _close_overlay)
	if player.has_method("play"):
		player.call("play")
	status.text = "播放：" + path


func _on_edit() -> void:
	var e := _selected_entry()
	if e.is_empty():
		status.text = "请先选择一个工程"
		return
	if tabs.current_tab != 0:
		status.text = "存档 .aas 暂不支持直接编辑，请编辑对应的 .aap 工程"
		return
	if not ResourceLoader.exists(EDITOR_SCENE):
		status.text = "编辑器尚未就绪（scenes/editor/Editor.tscn 不存在）"
		return
	var editor: Node = load(EDITOR_SCENE).instantiate()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(editor)
	if editor.has_method("open_project_file"):
		editor.call("open_project_file", str(e.get("path", "")))
	elif editor.has_method("open"):
		editor.call("open", null, str(e.get("path", "")))
	if editor.has_signal("request_exit"):
		editor.connect("request_exit", _close_overlay)
	status.text = "编辑：" + str(e.get("path", ""))


func _close_overlay() -> void:
	if overlay_root:
		overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in overlay_root.get_children():
			c.queue_free()
	refresh()


func _new_core_project() -> Variant:
	var script := load("res://addons/aa_core/aap_project.gd")
	if script == null:
		return null
	return script.new()


func _on_new_project() -> void:
	var projects_dir := str(_call_res("join_root", ["projects"]))
	DirAccess.make_dir_recursive_absolute(projects_dir)
	var name := "新工程"
	var path := projects_dir.path_join(name + ".aap")
	if FileAccess.file_exists(path):
		path = projects_dir.path_join("%s_%d.aap" % [name, int(Time.get_unix_time_from_system())])
	var ok := false
	var proj: Variant = _new_core_project()
	if proj != null and proj.has_method("save_to_file"):
		ok = proj.call("save_to_file", path) == OK
	if not ok:
		ok = _write_minimal_aap(path)
	status.text = ("已创建：" if ok else "创建失败：") + path
	refresh()
	if ok:
		_open_editor_on(path)


func _open_editor_on(path: String) -> void:
	if not ResourceLoader.exists(EDITOR_SCENE):
		return
	var editor: Node = load(EDITOR_SCENE).instantiate()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(editor)
	if editor.has_method("open_project_file"):
		editor.call("open_project_file", path)
	elif editor.has_method("open"):
		editor.call("open", null, path)
	if editor.has_signal("request_exit"):
		editor.connect("request_exit", _close_overlay)


func _write_minimal_aap(path: String) -> bool:
	var guid := _new_guid()
	var data := {
		"$type": "ProjectData, Assembly-CSharp",
		"ProjectName": path.get_file().get_basename(),
		"PreviewBgName": 0,
		"PreviewHeader": null,
		"PreviewTitle": null,
		"nodes": {
			"$type": "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib",
			"$values": [{
				"$type": "EntryNodeData, Assembly-CSharp",
				"Title": "",
				"Header": "",
				"Guid": "00000000-0000-0000-0000-000000000000",
				"ConnectionsTo": {
					"$type": "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib",
					"$values": [guid],
				},
				"X": 0.0,
				"Y": 0.0,
			}, {
				"$type": "ScriptNodeData, Assembly-CSharp",
				"Scripts": {
					"$type": "System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib",
					"$values": [],
				},
				"NodeName": "01",
				"Guid": guid,
				"ConnectionsTo": {
					"$type": "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib",
					"$values": [],
				},
				"X": 0.0,
				"Y": 220.0,
			}],
		},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()
	return true


func _new_guid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	var h := ""
	for i in 16:
		h += "%02x" % bytes[i]
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


func _on_import() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.aap ; 剧情工程", "*.aas ; 剧情存档"])
	dlg.title = "导入工程/存档"
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		var dst := str(_call_res("join_root", ["projects"]))
		if path.to_lower().ends_with(".aas"):
			dst = str(_call_res("join_root", ["saves"]))
		DirAccess.make_dir_recursive_absolute(dst)
		var err := DirAccess.copy_absolute(path, dst.path_join(path.get_file()))
		status.text = ("已导入：" if err == OK else "导入失败：") + path
		_close_overlay()
		refresh()
	)
	dlg.canceled.connect(_close_overlay)
	dlg.popup_centered_ratio(0.7)


## 把内置真实样本工程复制到数据目录，方便没有 .aap 的用户立刻体验
func _on_load_samples() -> void:
	var projects_dir := str(_call_res("join_root", ["projects"]))
	DirAccess.make_dir_recursive_absolute(projects_dir)
	var samples := {
		"res://fixtures/aap/sample_kei_01.aap": "示例-Kei初遇.aap",
		"res://fixtures/aap/sample_kei_02_multi_branch.aap": "示例-多分支.aap",
		"res://fixtures/aap/sample_keiend_03_ending.aap": "示例-Ending.aap",
	}
	var copied := 0
	for src in samples:
		if not FileAccess.file_exists(src):
			continue
		var dst := projects_dir.path_join(str(samples[src]))
		var err := DirAccess.copy_absolute(src, dst)
		if err == OK:
			copied += 1
			# 同名自定义资源文件夹（manifest / voices）
			var src_dir: String = src.get_basename()
			var src_manifest: String = src_dir + ".manifest.json"
			if FileAccess.file_exists(src_manifest):
				var local_dir := projects_dir.path_join(str(samples[src]).get_basename())
				DirAccess.make_dir_recursive_absolute(local_dir)
				DirAccess.copy_absolute(src_manifest, local_dir.path_join("manifest.json"))
				var voices_src: String = src_dir + ".voices.txt"
				if FileAccess.file_exists(voices_src):
					DirAccess.copy_absolute(voices_src, local_dir.path_join("voices.txt"))
	status.text = "已载入内置示例工程 %d 个到 %s" % [copied, projects_dir]
	refresh()


func _on_help() -> void:
	var panel := _modal_panel("操作说明", "")
	var vb: VBoxContainer = panel.get_meta("content")
	var t := _mk_label(
		"目录界面:\n" +
		"  · 双击工程 = 播放；选中后可用右侧按钮播放/编辑\n" +
		"  · 数据目录设置：指向 AA 的 data 目录即可直接读取其中工程与 overrides\n" +
		"  · 资源包管理：导入 tools/extract_aa_pack.py 转换出的 aa_pack（zip/文件夹）\n\n" +
		"播放器:\n" +
		"  鼠标左键 / 空格 / 回车 = 推进对话；数字键 1–9 = 选择选项\n" +
		"  A = AUTO 自动播放；H = 历史记录；按住 Ctrl = 快进；Esc = 退出\n\n" +
		"编辑器:\n" +
		"  Ctrl+S 保存 / Ctrl+O 打开 / Ctrl+N 新建 / Ctrl+Z 撤销 / Ctrl+Y 重做\n" +
		"  F5 编译并预览；Delete 删除选中节点（入口与带连线节点不可删）\n" +
		"  GraphEdit：左键拖空白平移、滚轮缩放、右键拖节点连线、右键拖空白划线剪断\n" +
		"  双击节点 = 打开右侧检查器编辑属性",
		17, Color("#cbd5e1"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 900
	vb.add_child(t)
	vb.add_child(_mk_button("关闭", panel.get_meta("close")))


func _on_packs() -> void:
	var packs: Array = _call_res("get_packs", [])
	var panel := _modal_panel("资源包管理", "已安装 %d 个 aa_pack" % packs.size())
	var vb: VBoxContainer = panel.get_meta("content")
	if packs.is_empty():
		var l := _mk_label("尚未安装资源包。\n可在此导入 aa_pack 文件夹/zip（由 tools/extract_aa_pack.py 从 AA 官方资源包转换而来），\n或直接使用 AA 的 overrides/ 与 projects 本地自定义资源。", 16, Color("#94a3b8"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 760
		vb.add_child(l)
	else:
		for p in packs:
			vb.add_child(_mk_label("• %s  (%s)" % [str(p.get("id", "?")), str(p.get("path", ""))], 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_mk_button("导入资源包…", _on_import_pack))
	row.add_child(_mk_button("关闭", panel.get_meta("close")))


func _on_import_pack() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.zip ; aa_pack", "*.aapack ; aa_pack"])
	dlg.title = "导入 aa_pack"
	overlay_root.add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		var err: Variant = AAResources.call("install_pack", path) if AAResources.has_method("install_pack") else null
		status.text = ("资源包已导入：" if err == OK else "资源包导入失败：") + path
		_close_overlay()
		refresh()
	)
	dlg.canceled.connect(_close_overlay)
	dlg.popup_centered_ratio(0.7)


func _on_data_dir() -> void:
	var panel := _modal_panel("数据目录设置", "将数据目录指向 AzureArchive 的真实 data/ 目录即可直接读取其中的工程与资源。")
	var vb: VBoxContainer = panel.get_meta("content")
	var edit := LineEdit.new()
	edit.text = _data_root()
	edit.custom_minimum_size = Vector2(760, 44)
	edit.add_theme_font_size_override("font_size", 17)
	var f := _font()
	if f:
		edit.add_theme_font_override("font", f)
	vb.add_child(edit)
	var hint := _mk_label("Windows: %APPDATA%\\..\\LocalLow\\foxxlight\\AzureArchive\\data\nAndroid: /storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data\niOS: 文件 App 内 AzureArchive/data", 14, Color("#64748b"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 760
	vb.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_mk_button("应用", func() -> void:
		if AAResources.has_method("set_data_root"):
			AAResources.call("set_data_root", edit.text.strip_edges())
		_close_overlay()
		refresh()
	))
	row.add_child(_mk_button("浏览…", func() -> void:
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.dir_selected.connect(func(p: String) -> void:
			edit.text = p
			dlg.queue_free()
		)
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		overlay_root.add_child(dlg)
		dlg.popup_centered_ratio(0.7)
	))
	row.add_child(_mk_button("取消", panel.get_meta("close")))


func _modal_panel(title: String, subtitle: String) -> PanelContainer:
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(_mk_label(title, 26, Color("#7fd4ff")))
	if subtitle != "":
		var sub := _mk_label(subtitle, 15, Color("#94a3b8"))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = 760
		vb.add_child(sub)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	vb.add_child(content)
	panel.set_meta("content", content)
	panel.set_meta("close", _close_overlay)
	return panel
