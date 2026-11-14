class_name AaJson
extends RefCounted
## `.aap` / `.aac` 用的 JSON 无损辅助层。
##
## AA 的 `.aap` 是 Newtonsoft.Json 输出的 UTF-8 无 BOM JSON：
## - 每个对象带 `$type`（类型判别）；
## - `List<T>` 包成 `{"$type": "...", "$values": [...]}`；
## - **字段顺序有语义**（AA 读写时保持顺序），因此这里自写序列化器，
##   严格按普通 Dictionary 的插入顺序输出，不做任何排序；
## - 数字：AA 的 int 字段在 JSON 里是整数字面量。Godot 的 JSON 解析器会把
##   **所有数字都解析成 float**，所以各模型读取 int 字段时必须显式 `int()`；
##   写出时我们自己区分 int/float（int 写整数、float 至少写 `x.0`）。
##
## 自写序列化器还带来两个好处：
## 1. 浮点数按“能精确 round-trip 的最短小数位”输出，避免丢精度；
## 2. 提供 `pretty` 选项（2 空格缩进，和 Newtonsoft Formatting.Indented 一致），
##    方便调试；`save_to_file` 默认写压缩格式（与 AA 实际产物一致）。

# ---------------------------------------------------------------------------
# $type 常量（必须与 AA 逐字节一致，注意反引号和空格）
# ---------------------------------------------------------------------------
const T_PROJECT := "ProjectData, Assembly-CSharp"
const T_NODE_LIST := "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib"
const T_ENTRY := "EntryNodeData, Assembly-CSharp"
const T_SCRIPT_NODE := "ScriptNodeData, Assembly-CSharp"
const T_SELECTION := "SelectionNodeData, Assembly-CSharp"
const T_EXIT := "ExitNodeData, Assembly-CSharp"
const T_SCRIPT_LIST := "System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib"
const T_SCRIPT := "ScriptData, Assembly-CSharp"
const T_CHARACTER_LIST := "System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib"
const T_CHARACTER := "ScriptData+CharacterRecordData, Assembly-CSharp"
const T_GUID_LIST := "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib"
const T_INT_LIST := "System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib"
const T_STRING_LIST := "System.Collections.Generic.List`1[[System.String, mscorlib]], mscorlib"

## 节点 `$type` -> `AapProject.NODE_*` 常量（-1 = 未知类型，原样保留）。
const NODE_TYPE_TABLE := {
	T_ENTRY: 0,
	T_SCRIPT_NODE: 1,
	T_SELECTION: 2,
	T_EXIT: 3,
}


# ---------------------------------------------------------------------------
# 解析
# ---------------------------------------------------------------------------

## 解析 JSON 文本；失败返回 null。自动剥离 UTF-8 BOM（AA 一般不写，但容错）。
static func parse(text: String) -> Variant:
	if text.is_empty():
		return null
	if text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	return JSON.parse_string(text)


## 读取并解析 JSON 文件；失败返回 null（错误已 push_error）。
static func parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("AaJson: 文件不存在 " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("AaJson: 无法打开 " + path + "，错误码 " + str(FileAccess.get_open_error()))
		return null
	var text := f.get_as_text()
	f.close()
	var value: Variant = parse(text)
	if value == null:
		push_error("AaJson: JSON 解析失败 " + path)
	return value


# ---------------------------------------------------------------------------
# 容错读取
# ---------------------------------------------------------------------------

## 取 List 包装器的 `$values`；直接是数组（非 Newtonsoft 风格）也接受。
static func values_of(wrapper: Variant) -> Array:
	if wrapper is Array:
		return wrapper
	if wrapper is Dictionary:
		var v: Variant = wrapper.get("$values")
		if v is Array:
			return v
	return []


static func type_of(d: Variant) -> String:
	if d is Dictionary:
		var t: Variant = d.get("$type")
		if t is String:
			return t
	return ""


static func has(d: Dictionary, key: String) -> bool:
	return d.has(key)


## 字段是否为 JSON null（AA 对“未设置”的可选字符串会写 null，必须原样保留）。
static func is_null_field(d: Dictionary, key: String) -> bool:
	return d.has(key) and d[key] == null


static func get_str(d: Dictionary, key: String, fallback := "") -> String:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	if v == null:
		return fallback
	if v is String:
		return v
	return str(v)


static func get_int(d: Dictionary, key: String, fallback := 0) -> int:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	if v == null:
		return fallback
	if v is bool:
		return 1 if v else 0
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String:
		return v.to_int()
	return fallback


static func get_float(d: Dictionary, key: String, fallback := 0.0) -> float:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	if v == null:
		return fallback
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is String:
		return v.to_float()
	return fallback


static func get_bool(d: Dictionary, key: String, fallback := false) -> bool:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	if v == null:
		return fallback
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v.to_lower() == "true" or v == "1"
	return fallback


# ---------------------------------------------------------------------------
# Newtonsoft List 包装
# ---------------------------------------------------------------------------

static func wrap_list(type_string: String, values: Variant) -> Dictionary:
	var d := {}
	d["$type"] = type_string
	d["$values"] = values
	return d


static func wrap_guid_list(values: PackedStringArray) -> Dictionary:
	return wrap_list(T_GUID_LIST, values)


static func wrap_int_list(values: PackedInt32Array) -> Dictionary:
	return wrap_list(T_INT_LIST, values)


static func wrap_string_list(values: PackedStringArray) -> Dictionary:
	return wrap_list(T_STRING_LIST, values)


# ---------------------------------------------------------------------------
# 序列化（字段顺序 = Dictionary 插入顺序）
# ---------------------------------------------------------------------------

const INDENT := "  "


## 把 Variant 序列化成 JSON 文本。
## pretty = true 时按 2 空格缩进（Newtonsoft Formatting.Indented 风格）。
static func stringify(value: Variant, pretty := false) -> String:
	var out := PackedStringArray()
	_write(value, out, pretty, 0)
	return "".join(out)


static func _write(value: Variant, out: PackedStringArray, pretty: bool, level: int) -> void:
	var t := typeof(value)
	match t:
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if value else "false")
		TYPE_INT:
			out.append(str(value))
		TYPE_FLOAT:
			out.append(format_float(value))
		TYPE_STRING:
			out.append(quote(value))
		TYPE_STRING_NAME:
			out.append(quote(str(value)))
		TYPE_DICTIONARY:
			_write_object(value, out, pretty, level)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
		TYPE_PACKED_BYTE_ARRAY:
			_write_array(value, out, pretty, level)
		_:
			# 兜底：转字符串写出去，不丢数据（正常 .aap 不会走到这里）
			out.append(quote(str(value)))


static func _write_object(value: Dictionary, out: PackedStringArray, pretty: bool, level: int) -> void:
	var keys := value.keys()
	if keys.is_empty():
		out.append("{}")
		return
	out.append("{")
	var inner := INDENT.repeat(level + 1)
	for i in keys.size():
		if i > 0:
			out.append(",")
		if pretty:
			out.append("\n")
			out.append(inner)
		out.append(quote(str(keys[i])))
		out.append(": " if pretty else ":")
		_write(value[keys[i]], out, pretty, level + 1)
	if pretty:
		out.append("\n")
		out.append(INDENT.repeat(level))
	out.append("}")


static func _write_array(value: Variant, out: PackedStringArray, pretty: bool, level: int) -> void:
	var size: int = value.size()
	if size == 0:
		out.append("[]")
		return
	out.append("[")
	var inner := INDENT.repeat(level + 1)
	for i in size:
		if i > 0:
			out.append(",")
		if pretty:
			out.append("\n")
			out.append(inner)
		_write(value[i], out, pretty, level + 1)
	if pretty:
		out.append("\n")
		out.append(INDENT.repeat(level))
	out.append("]")


## 需要转义的字符（`"`、`\`、U+0000–U+001F）；用 RegEx 在 C++ 里一次扫描。
static var _escape_re: RegEx = null


static func _needs_escape(s: String) -> bool:
	if _escape_re == null:
		_escape_re = RegEx.create_from_string("[\\x00-\\x1F\"\\\\]")
	return _escape_re.search(s) != null


## JSON 字符串转义（与 Newtonsoft 默认行为一致：中文等非 ASCII 原样输出）。
## 性能：大多数台词没有任何需转义字符，直接拼 `"` + 原文 + `"`；
## 只有含引号/反斜杠/控制字符时才走逐段转义。
static func quote(s: String) -> String:
	if not _needs_escape(s):
		return "\"" + s + "\""
	var n := s.length()
	if n == 0:
		return "\"\""
	var out := PackedStringArray()
	out.append("\"")
	var start := 0
	for i in n:
		var c := s.unicode_at(i)
		var escaped := ""
		match c:
			0x22: escaped = "\\\""
			0x5C: escaped = "\\\\"
			0x08: escaped = "\\b"
			0x0C: escaped = "\\f"
			0x0A: escaped = "\\n"
			0x0D: escaped = "\\r"
			0x09: escaped = "\\t"
			_:
				if c < 0x20:
					escaped = "\\u%04x" % c
		if not escaped.is_empty():
			if i > start:
				out.append(s.substr(start, i - start))
			out.append(escaped)
			start = i + 1
	if start < n:
		out.append(s.substr(start))
	out.append("\"")
	return "".join(out)


## 浮点数格式化：输出能精确 round-trip 的最短形式；整数值的 float 写 `x.0`
## （AA 的 X/Y 是 double 字段，保持 float 语义）。
static func format_float(f: float) -> String:
	if is_nan(f) or is_inf(f):
		return "0.0"
	if f == 0.0:
		if str(f).begins_with("-"):
			return "-0.0"
		return "0.0"
	var as_int := int(f)
	if float(as_int) == f and absf(f) < 9007199254740992.0:
		return str(as_int) + ".0"
	for decimals in range(1, 18):
		var s := String.num(f, decimals)
		if s.to_float() == f:
			if not s.contains(".") and not s.contains("e") and not s.contains("E"):
				s += ".0"
			return s
	return str(f)
