class_name AaEditorBackend
extends RefCounted
## 编辑器 <-> 数据层桥接。
##
## 设计目标：core-dev 的 `addons/aa_core/` 还在写时，编辑器也能独立跑起来；
## core 就绪后自动切换到 core 的 AapProject/AapNode/AaScriptLine/AaCharacterRecord。
## 因此编辑器内部**不静态 import 任何核心类**（避免 class_name 未注册导致解析失败），
## 而是通过 Script 资源动态调用（Script.call / 实例动态属性访问）。
##
## 用法：`var backend := AaEditorBackend.new()`；随后：
##   - `backend.new_project()` / `backend.load_from_file(path)` / `backend.load_from_string(text)`
##   - `backend.NODE_ENTRY` 等节点类型常量
##   - `backend.new_script_line()` / `backend.new_character(project)`（保证 6 槽）
##   - `backend.bg_id(friendly_name)`（AaHash）
##   - `backend.enum_table("emoticon")` 等（AaEnums 优先）

const CORE_PROJECT := "res://addons/aa_core/aap_project.gd"
const CORE_NODE := "res://addons/aa_core/aap_node.gd"
const CORE_LINE := "res://addons/aa_core/script_line.gd"
const CORE_CHAR := "res://addons/aa_core/character_record.gd"
const CORE_HASH := "res://addons/aa_core/xxhash32.gd"
const CORE_ENUMS := "res://addons/aa_core/enums.gd"
const FALLBACK_PROJECT := "res://addons/aa_editor/model/fallback_project.gd"
const FALLBACK_LINE := "res://addons/aa_editor/model/fallback_script_line.gd"
const FALLBACK_CHAR := "res://addons/aa_editor/model/fallback_character.gd"
const LOCAL_ENUMS := preload("res://addons/aa_editor/editor_enums.gd")

# 节点类型常量（默认值；init 时尽量从项目脚本的 const 表读取）
var NODE_ENTRY := 0
var NODE_SCRIPT := 1
var NODE_CHOICE := 2
var NODE_EXIT := 3

var using_core := false
var backend_name := "fallback"
var last_error := ""

var project_script: Script = null
var node_script: Script = null
var line_script: Script = null
var char_script: Script = null
var hash_script: Script = null
var enums_script: Script = null


func _init() -> void:
	_try_load_core()
	if project_script == null:
		_load_fallback()
	_read_constants()


func _try_load_core() -> void:
	var s = _load_script(CORE_PROJECT)
	if s == null:
		return
	# 校验 core 已经写完并编译通过（core-dev 并行开发时可能只有半成品）：
	# 必须能实例化，且提供静态 load_from_file
	if s is GDScript and not (s as GDScript).can_instantiate():
		return
	var has_load := false
	for m in s.get_script_method_list():
		if str(m.get("name", "")) == "load_from_file":
			has_load = true
			break
	if not has_load:
		return
	project_script = s
	node_script = _load_script(CORE_NODE)
	line_script = _load_script(CORE_LINE)
	char_script = _load_script(CORE_CHAR)
	hash_script = _load_script(CORE_HASH)
	enums_script = _load_script(CORE_ENUMS)
	using_core = true
	backend_name = "aa_core"


func _load_fallback() -> void:
	project_script = _load_script(FALLBACK_PROJECT)
	line_script = _load_script(FALLBACK_LINE)
	char_script = _load_script(FALLBACK_CHAR)
	backend_name = "fallback"
	using_core = false


func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is Script:
		return s
	return null


func _read_constants() -> void:
	if project_script == null:
		return
	var cm: Dictionary = project_script.get_script_constant_map()
	if cm.has("NODE_ENTRY"):
		NODE_ENTRY = int(cm["NODE_ENTRY"])
	if cm.has("NODE_SCRIPT"):
		NODE_SCRIPT = int(cm["NODE_SCRIPT"])
	if cm.has("NODE_CHOICE"):
		NODE_CHOICE = int(cm["NODE_CHOICE"])
	if cm.has("NODE_EXIT"):
		NODE_EXIT = int(cm["NODE_EXIT"])


# ---------------------------------------------------------------- 工程

func new_project():
	if project_script == null:
		last_error = "数据层脚本缺失（aa_core 与 fallback 都不可用）"
		return null
	# core 提供了 AapProject.create_empty()/create()（自动建全 0 Guid 的入口节点），优先使用。
	# 用 create_empty 保证新工程从「只有入口节点」开始，节点增删对测试/撤销更可预期。
	for method_name in ["create_empty", "create"]:
		var has_method := false
		for m in project_script.get_script_method_list():
			if str(m.get("name", "")) == method_name:
				has_method = true
				break
		if has_method:
			var created = project_script.call(method_name, "新建工程")
			if created != null:
				return created
	var p = project_script.new()
	if p == null:
		last_error = "无法实例化工程脚本"
		return null
	if not ("project_name" in p) or p.project_name == "":
		p.project_name = "新建工程"
	var entry = p.get_entry() if p.has_method("get_entry") else null
	if entry == null and p.has_method("add_node"):
		p.call("add_node", NODE_ENTRY, Vector2.ZERO)
	return p


func load_from_file(path: String):
	if project_script == null:
		last_error = "数据层脚本缺失"
		return null
	var p = project_script.call("load_from_file", path)
	if p == null:
		last_error = "无法读取工程：" + path
		if using_core:
			# core 解析失败时用 fallback 兜底，避免编辑器打不开真实工程
			var fb = _load_script(FALLBACK_PROJECT)
			if fb != null:
				p = fb.call("load_from_file", path)
				if p != null:
					last_error = "core 解析失败，已用 fallback 打开（注意：保存仍用 core）"
	return p


func load_from_string(text: String):
	if project_script == null:
		return null
	return project_script.call("load_from_string", text)


func save_to_file(project, path: String) -> int:
	if project == null:
		return ERR_INVALID_PARAMETER
	var err = project.save_to_file(path)
	return int(err)


func to_json_text(project) -> String:
	if project == null:
		return ""
	return str(project.to_json_text(true))


## 紧凑 JSON（撤销快照 / 自动保存缓存用，体积小）
func snapshot_text(project) -> String:
	if project == null:
		return ""
	return str(project.to_json_text(false))


# ---------------------------------------------------------------- 脚本行/角色

func new_script_line():
	var line = null
	if line_script != null:
		line = line_script.new()
	if line == null:
		line = _load_script(FALLBACK_LINE).new()
	_ensure_six_characters(line)
	return line


func new_character():
	var c = null
	if char_script != null:
		c = char_script.new()
	if c == null:
		c = _load_script(FALLBACK_CHAR).new()
	# 统一默认值（不同实现可能默认不同）
	_set_prop(c, "name", "")
	_set_prop(c, "face_id", "00")
	_set_prop(c, "starting_pos", 0)
	_set_prop(c, "ending_pos", 0)
	_set_prop(c, "emoticon", -1)
	_set_prop(c, "action", 0)
	_set_prop(c, "effect", 0)
	_set_prop(c, "appear", 0)
	_set_prop(c, "shape_override", 0)
	return c


## 确保脚本行的 characters 为 6 项（core/fallback 实现可能默认不同）
func ensure_six_characters(line) -> void:
	if line == null:
		return
	var chars = line.get("characters")
	if chars == null:
		line.set("characters", [])
		chars = line.get("characters")
	if not (chars is Array):
		return
	while chars.size() < 6:
		chars.append(new_character())
	while chars.size() > 6:
		chars.pop_back()


func _ensure_six_characters(line) -> void:
	ensure_six_characters(line)


## 复制一行脚本（用于“复制脚本”或新建时继承环境信息）
func duplicate_line(line):
	if line == null:
		return new_script_line()
	if line.has_method("duplicate"):
		var d = line.duplicate(true)
		if d != null:
			ensure_six_characters(d)
			return d
	return new_script_line()


# ---------------------------------------------------------------- 哈希/枚举

func bg_id(friendly_name: String) -> int:
	if friendly_name.is_empty():
		return 0
	if hash_script == null:
		hash_script = _load_script(CORE_HASH)
	if hash_script != null:
		return int(hash_script.call("bg_id", friendly_name))
	# 最后的兜底：编辑器只用于写回 ID，哈希不可用时保留旧值由调用方处理
	return 0


func hash_ready() -> bool:
	if hash_script == null:
		hash_script = _load_script(CORE_HASH)
	return hash_script != null


## 枚举表：优先 core AaEnums，缺字段回退本地表；返回 int -> String 标签
func enum_table(kind: String) -> Dictionary:
	var local: Dictionary = LOCAL_ENUMS.table(kind)
	var core_key := ""
	match kind:
		"emoticon":
			core_key = "EMOTICONS"
		"action":
			core_key = "ACTIONS"
		"appear":
			core_key = "APPEAR"
		"shape":
			core_key = "SHAPES"
		"transition":
			core_key = "TRANSITIONS"
		"bg_effect":
			core_key = "BG_EFFECTS"
	if enums_script == null:
		enums_script = _load_script(CORE_ENUMS)
	if enums_script != null and not core_key.is_empty():
		var cm: Dictionary = enums_script.get_script_constant_map()
		if cm.has(core_key) and cm[core_key] is Dictionary:
			var normalized: Dictionary = LOCAL_ENUMS.normalize(cm[core_key])
			# 本地已知项以 core 为准，但保证 0/-1 的“无”仍在
			if not normalized.is_empty():
				return normalized
	return local


func enum_options(kind: String) -> Array:
	## 返回 [[value:int, label:String], ...]，按 value 排序；用于 OptionButton
	var table := enum_table(kind)
	var keys: Array = table.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append([int(k), str(table[k])])
	return out


## 选择节点的选项列表：[{index, text, target_guid, target}]（core 有专门实现时优先用）
func choice_options(project, node) -> Array:
	if project == null or node == null:
		return []
	if project.has_method("get_choice_options"):
		var opts = project.call("get_choice_options", node)
		if opts is Array:
			return opts
	var out: Array = []
	for i in node.connections.size():
		var txt := ""
		if node.has_method("get_selection_text"):
			txt = str(node.call("get_selection_text", i))
		elif i < node.selection_texts.size():
			txt = str(node.selection_texts[i])
		out.append({"index": i, "text": txt, "target_guid": node.connections[i], "target": project.find_node(node.connections[i])})
	return out


## 枚举下拉数据：[[value:int, label:String], ...]
## kind: emoticon / action / appear / shape / transition / bg_effect
func enum_choices(kind: String) -> Array:
	var core_table := {}
	if enums_script != null:
		var cm: Dictionary = enums_script.get_script_constant_map()
		match kind:
			"emoticon":
				if enums_script.has_method("emoticon_choices"):
					var arr = enums_script.call("emoticon_choices")
					if arr is Array:
						var out: Array = []
						for it in arr:
							out.append([int(it.get("id", -1)), _emoticon_label(it)])
						return out
				core_table = cm.get("EMOTICONS", {})
			"action":
				if enums_script.has_method("action_choices"):
					var arr2 = enums_script.call("action_choices")
					if arr2 is Array:
						var out2: Array = []
						for it in arr2:
							out2.append([int(it.get("id", 0)), "%s %s" % [str(it.get("id_name", "")), str(it.get("zh", ""))]])
						return out2
				core_table = cm.get("ACTIONS", {})
			"appear":
				if enums_script.has_method("appear_choices"):
					var arr3 = enums_script.call("appear_choices")
					if arr3 is Array:
						var out3: Array = []
						for it in arr3:
							out3.append([int(it.get("id", 0)), "%s %s" % [str(it.get("id_name", "")), str(it.get("zh", ""))]])
						return out3
				core_table = cm.get("APPEAR", {})
			"shape":
				core_table = cm.get("SHAPES", {})
			"transition":
				core_table = cm.get("TRANSITIONS", {})
			"bg_effect":
				core_table = cm.get("BG_EFFECTS", {})
	if not core_table.is_empty():
		var normalized: Dictionary = LOCAL_ENUMS.normalize(core_table)
		var keys: Array = normalized.keys()
		keys.sort()
		var out: Array = []
		for k in keys:
			out.append([int(k), str(normalized[k])])
		return out
	# fallback 本地表
	var local: Dictionary = LOCAL_ENUMS.table(kind)
	var keys2: Array = local.keys()
	keys2.sort()
	var out4: Array = []
	for k in keys2:
		out4.append([int(k), str(local[k])])
	return out4


## 单个值的显示文案（用于按钮/标签）
func enum_label(kind: String, value: int) -> String:
	match kind:
		"shape":
			if value == 0:
				return "无"
			if enums_script != null and enums_script.has_method("shape_zh"):
				return str(enums_script.call("shape_zh", value))
			return "shape=%d" % value
		"emoticon":
			if enums_script != null and enums_script.has_method("emoticon_info"):
				var info = enums_script.call("emoticon_info", value)
				if info is Dictionary:
					return "%s %s" % [str(info.get("symbol", "")), str(info.get("zh", ""))]
		"action":
			if enums_script != null and enums_script.has_method("action_info"):
				var info2 = enums_script.call("action_info", value)
				if info2 is Dictionary:
					return "%s %s" % [str(info2.get("id", "")), str(info2.get("zh", ""))]
		"appear":
			if enums_script != null and enums_script.has_method("appear_info"):
				var info3 = enums_script.call("appear_info", value)
				if info3 is Dictionary:
					return "%s %s" % [str(info3.get("id", "")), str(info3.get("zh", ""))]
		"transition":
			if enums_script != null and enums_script.has_method("transition_info"):
				var info4 = enums_script.call("transition_info", value)
				if info4 is Dictionary:
					return "%s（%s）" % [str(info4.get("zh", "无")), str(info4.get("name", ""))]
		"bg_effect":
			if enums_script != null and enums_script.has_method("bg_effect_info"):
				var info5 = enums_script.call("bg_effect_info", value)
				if info5 is Dictionary:
					return str(info5.get("zh", str(value)))
	for pair in enum_choices(kind):
		if int(pair[0]) == value:
			return str(pair[1])
	return "%s=%d" % [kind, value]


func _emoticon_label(it: Variant) -> String:
	if it is Dictionary:
		var sym := str(it.get("symbol", ""))
		var zh := str(it.get("zh", ""))
		if sym.is_empty():
			return zh
		return "%s %s" % [sym, zh]
	return str(it)


# ---------------------------------------------------------------- 播放器

func player_scene_path() -> String:
	var p := "res://scenes/player/Player.tscn"
	if ResourceLoader.exists(p):
		return p
	return ""


func player_script_path() -> String:
	var p := "res://addons/aa_player/player.gd"
	if ResourceLoader.exists(p):
		return p
	return ""


# ---------------------------------------------------------------- 动态工具

func _call(obj, method: String, a = null, b = null, c = null, d = null):
	if obj == null or not obj.has_method(method):
		return null
	match _argc(a):
		0:
			return obj.call(method)
		1:
			return obj.call(method, a)
		2:
			return obj.call(method, a, b)
		3:
			return obj.call(method, a, b, c)
		_:
			return obj.call(method, a, b, c, d)


func _argc(a) -> int:
	# 简化：用哨兵区分“未传参”和“传了 null”
	if a == _NO_ARG:
		return 0
	return 4


const _NO_ARG := "__AA_NO_ARG__"


func _set_prop(obj, prop: String, value) -> void:
	if obj != null and prop in obj:
		obj.set(prop, value)


static func prop_has(obj, prop: String) -> bool:
	return obj != null and prop in obj
