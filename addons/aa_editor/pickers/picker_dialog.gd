class_name AaPickerDialog
extends AcceptDialog
## 资源选择器弹窗：角色 / 背景 / BGM / 音效 / 弹出图 / 语音。
##
## 数据来源：AAResources.make_context(...)（pack-dev 的 AaResContext）。
## 资源层没就绪 / 没装资源包时：列表为空，但**仍然可以手动输入 ID**——
## 对应 AA 的自定义资源场景（自定义背景名、自定义角色 Identifier、voice GUID 等）。
##
## 用法：
##   var dlg := AaPickerDialog.new()
##   dlg.setup("bg", context, current_value)
##   add_child(dlg)
##   dlg.picked.connect(func(v): ...)
##   dlg.popup_centered(Vector2i(820, 640))
##
## picked 的值：
##   character -> String（Identifier）
##   bg        -> {"id": int, "name": String}（id < 0 表示需要 editor 用 AaHash 现算）
##   bgm       -> int（bgmId；999 静音）
##   sound/popup/voice -> String

signal picked(value)

const KIND_TITLES := {
	"character": "选择角色",
	"bg": "选择背景",
	"bgm": "选择 BGM",
	"sound": "选择音效",
	"popup": "选择弹出图",
	"voice": "选择语音",
}

var kind := ""
var context = null
var current_value = null
var backend = null

var _entries: Array = []
var _filtered: Array = []
var _list: ItemList
var _input: LineEdit
var _status: Label
var _title_label: Label
var _manual_btn: Button


func setup(p_kind: String, p_context, p_current, p_backend = null) -> void:
	kind = p_kind
	context = p_context
	current_value = p_current
	backend = p_backend
	title = str(KIND_TITLES.get(kind, "选择资源"))
	ok_button_text = "取消"


func _ready() -> void:
	_build_ui()
	# AcceptDialog 自带的确认按钮由本弹窗底部按钮替代，避免出现两个「取消」
	var builtin_ok := get_ok_button()
	if builtin_ok != null:
		builtin_ok.visible = false
	_load_entries()
	_apply_filter("")
	_refresh_status()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)


	var hint := Label.new()
	hint.text = "提示：资源列表来自数据目录/资源包；资源缺失时可直接手动输入 ID/名称。"
	hint.add_theme_color_override("font_color", Color("#94a3b8"))
	hint.add_theme_font_size_override("font_size", 16)
	v.add_child(hint)

	var search_row := HBoxContainer.new()
	v.add_child(search_row)
	var sl := Label.new()
	sl.text = "筛选/手动输入："
	search_row.add_child(sl)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "输入名称或 ID 筛选；或直接填一个 ID/名称后点右侧按钮"
	_input.text_changed.connect(_on_input_changed)
	_input.text_submitted.connect(func(_t): _use_manual())
	search_row.add_child(_input)
	_manual_btn = Button.new()
	_manual_btn.text = "使用输入值"
	_manual_btn.pressed.connect(_use_manual)
	search_row.add_child(_manual_btn)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(760, 420)
	_list.fixed_icon_size = Vector2i(160, 90)
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.item_activated.connect(_on_activate)
	_list.item_selected.connect(_on_select)
	v.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#94a3b8"))
	_status.add_theme_font_size_override("font_size", 16)
	v.add_child(_status)

	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	var b_ok := Button.new()
	b_ok.text = "选定"
	b_ok.pressed.connect(_on_ok)
	bottom.add_child(b_ok)
	var b_cancel := Button.new()
	b_cancel.text = "取消"
	b_cancel.pressed.connect(_on_cancel)
	bottom.add_child(b_cancel)
	if kind == "bgm":
		var b_mute := Button.new()
		b_mute.text = "设为静音（999）"
		b_mute.pressed.connect(func(): _emit(999))
		bottom.add_child(b_mute)


# ---------------------------------------------------------------------------
# 数据加载
# ---------------------------------------------------------------------------

func _field(obj, names: Array, fallback = null):
	if obj == null:
		return fallback
	if obj is Dictionary:
		for n in names:
			if obj.has(n):
				return obj[n]
	else:
		for n in names:
			if n in obj:
				var v = obj.get(n)
				if v != null:
					return v
	return fallback


func _load_entries() -> void:
	_entries.clear()
	if context == null:
		return
	match kind:
		"character":
			var arr = _safe_call(context, "get_characters")
			if arr is Array:
				for it in arr:
					var id := str(_field(it, ["identifier", "Identifier", "id", "name"], ""))
					var nm := str(_field(it, ["display_name", "name", "Name", "nickname"], id))
					var nick := str(_field(it, ["nickname"], ""))
					var label := id
					if not nm.is_empty() and nm != id:
						label = "%s（%s）" % [nm, id]
					elif nm.is_empty():
						label = id
					if not nick.is_empty():
						label += " · " + nick
					var avatar = null
					if it != null and it.has_method("get_small_portrait"):
						avatar = it.call("get_small_portrait")
					_entries.append({"value": id, "label": label, "icon": avatar if avatar is Texture2D else null, "raw": it})
		"bg":
			var arr2 = _safe_call(context, "get_bg_entries")
			if arr2 is Array:
				for it in arr2:
					var id2: int = int(_field(it, ["id", "Id", "bg_id"], 0))
					var nm2 := str(_field(it, ["name", "Name", "friendly_name", "bgFriendlyName"], ""))
					var tex = _field(it, ["texture", "Texture", "image"], null)
					_entries.append({"value": {"id": id2, "name": nm2}, "label": nm2, "icon": tex if tex is Texture2D else null, "raw": it})
		"bgm":
			var arr3 = _safe_call(context, "get_bgm_entries")
			if arr3 is Array:
				for it in arr3:
					var raw_id = _field(it, ["id", "Id", "bgm_id"], null)
					var id3: int = int(raw_id) if raw_id != null else -1
					var nm3 := str(_field(it, ["name", "Name", "title"], ""))
					var label3 := nm3
					if id3 >= 0:
						label3 = "%s（%d）" % [nm3, id3]
					else:
						label3 = nm3 + "（无数字 ID）"
					_entries.append({"value": id3, "label": label3, "raw": it})
		"sound":
			var arr4 = _safe_call(context, "get_sound_entries")
			if arr4 is Array:
				for it in arr4:
					var nm4 := str(_field(it, ["name", "Name", "stem"], str(it)))
					_entries.append({"value": nm4, "label": nm4, "raw": it})
		"popup":
			var arr5 = _safe_call(context, "get_popup_entries")
			if arr5 is Array:
				for it in arr5:
					var nm5 := str(_field(it, ["name", "Name", "stem"], str(it)))
					var tex5 = _field(it, ["texture", "Texture", "image"], null)
					_entries.append({"value": nm5, "label": nm5, "icon": tex5 if tex5 is Texture2D else null, "raw": it})
		"voice":
			var arr6 = _safe_call(context, "get_voice_entries")
			if arr6 is Array:
				for it in arr6:
					var guid6 := str(_field(it, ["guid", "name", "Name"], ""))
					var text6 := str(_field(it, ["text"], ""))
					if text6.length() > 28:
						text6 = text6.substr(0, 28) + "…"
					var label6 := guid6 if text6.is_empty() else "%s  「%s」" % [guid6, text6]
					_entries.append({"value": guid6, "label": label6, "raw": it})
			if _entries.is_empty():
				var manifest = _safe_call(context, "get_manifest")
				if manifest != null:
					var voices = _field(manifest, ["voice_overrides", "VoiceOverrides"], [])
					if voices is Array:
						for path in voices:
							var p := str(path).replace("\\", "/")
							var fname := p.get_file().get_basename()
							if fname.is_empty():
								fname = p
							_entries.append({"value": fname, "label": fname})
	_entries.sort_custom(func(a, b): return str(a["label"]).naturalnocasecmp_to(str(b["label"])) < 0)


func _safe_call(obj, method: String, a = null):
	if obj == null or not obj.has_method(method):
		return null
	if a == null:
		return obj.call(method)
	return obj.call(method, a)


func _refresh_status() -> void:
	var source := "资源上下文"
	if context == null:
		source = "资源层未就绪（AAResources context = null）"
	var cur := "当前值：%s" % str(current_value)
	_status.text = "%s · 可选项 %d 个 · %s" % [source, _filtered.size(), cur]


# ---------------------------------------------------------------------------
# 列表/筛选
# ---------------------------------------------------------------------------

func _apply_filter(text: String) -> void:
	_list.clear()
	_filtered.clear()
	var needle := text.strip_edges().to_lower()
	for e in _entries:
		if not needle.is_empty():
			var hay := (str(e.get("label", "")) + " " + str(e.get("value", ""))).to_lower()
			if not hay.contains(needle):
				continue
		_filtered.append(e)
		var idx := _list.add_item(str(e.get("label", "")))
		var icon = e.get("icon", null)
		if icon is Texture2D:
			_list.set_item_icon(idx, icon)
		_list.set_item_metadata(idx, _filtered.size() - 1)
	# 手动输入项：永远把输入框内容作为最后一项
	if not text.strip_edges().is_empty():
		var idx2 := _list.add_item("使用手动输入：" + text.strip_edges())
		_list.set_item_metadata(idx2, -2)


func _on_input_changed(text: String) -> void:
	_apply_filter(text)
	_refresh_status()


func _on_select(index: int) -> void:
	var meta = _list.get_item_metadata(index)
	if meta == -2:
		_status.text = "将使用手动输入：" + _input.text.strip_edges()
	elif meta is int and meta >= 0 and meta < _filtered.size():
		_status.text = "已选：" + str(_filtered[meta].get("label", ""))


func _on_activate(index: int) -> void:
	_on_select(index)
	_on_ok()


func _use_manual() -> void:
	var txt := _input.text.strip_edges()
	if txt.is_empty():
		_status.text = "请输入一个 ID / 名称"
		return
	_emit_manual(txt)


func _on_ok() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		# 没选列表项时，用输入框内容
		var txt := _input.text.strip_edges()
		if not txt.is_empty():
			_emit_manual(txt)
		else:
			_status.text = "请选择一个资源，或手动输入 ID"
		return
	var index: int = sel[0]
	var meta = _list.get_item_metadata(index)
	if meta == -2:
		_emit_manual(_input.text.strip_edges())
		return
	if meta is int and meta >= 0 and meta < _filtered.size():
		var entry: Dictionary = _filtered[meta]
		if kind == "bgm" and int(entry.get("value", -1)) < 0:
			_status.text = "该 BGM 没有数字 ID（自定义 BGM）：请在输入框填 AA 的 bgmId 数字，或选其他 BGM"
			return
		_emit(entry.get("value"))


func _emit(value) -> void:
	picked.emit(value)
	hide()
	queue_free()


func _emit_manual(txt: String) -> void:
	match kind:
		"bg":
			_emit({"id": -1, "name": txt})
		"bgm":
			# 允许输入数字 ID 或名称
			if txt.is_valid_int():
				_emit(int(txt))
			else:
				for e in _entries:
					if str(e.get("label", "")).to_lower().contains(txt.to_lower()):
						_emit(e.get("value"))
						return
				_emit(999 if txt.to_lower() in ["静音", "mute", "none"] else 0)
		_:
			_emit(txt)


func _on_cancel() -> void:
	hide()
	queue_free()
