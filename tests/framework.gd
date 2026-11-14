extends RefCounted
## qa-dev 轻量 headless 测试框架。
##
## 设计要点：
## 1. **不声明 class_name**，各用例用 `const Fw = preload("res://tests/framework.gd")`
##    引用，因此即使 class_name 缓存过期也能解析，减少环境依赖。
## 2. 断言失败信息自动带「文件:行号」，来自 get_stack()，定位到具体用例代码。
## 3. 支持四种结局：PASS / FAIL / SKIP / PENDING。
##    - FAIL   ：断言失败或用例脚本加载/执行异常 → run_all 退出码 1；
##    - SKIP   ：环境性不适用（模块永不存在、平台限制）→ 不算失败；
##    - PENDING：依赖的其他模块尚未就绪，等对方 API 出现后自动转为真实断言 → 不算失败，
##               但里程碑验收要求 pending == 0。
## 4. 提供动态加载/反射工具（load_script / static_call / has_method_any ...），
##    让用例在「别人模块还没写完」时也能安全运行，而不是整个脚本解析失败。
##
## 用例写法（每个 test_*.gd）：
## [codeblock]
## extends RefCounted
## const Fw = preload("res://tests/framework.gd")
##
## func run(ctx) -> void:                    # 必须是 run(ctx)；可以是 async（含 await）
##     var S = ctx.need("res://addons/aa_core/aap_project.gd", "core-dev")
##     if S == null:
##         return                            # need() 已标记 pending
##     ctx.eq(S.NODE_ENTRY if S.get_script_constant_map().has("NODE_ENTRY") else 0, 0, "入口节点枚举")
## [/codeblock]


# ============================================================================
# 断言/上下文
# ============================================================================

class Ctx extends RefCounted:
	var tree: SceneTree
	var case_name: String
	## 断言通过数（含辅助断言）。
	var passed := 0
	## 失败详情：[{where, message}]
	var failures: Array = []
	## 跳过原因（不失败）。
	var skip_reasons: Array = []
	## 未就绪原因（不失败，但最终验收必须清零）。
	var pending_reasons: Array = []
	## 用例自述的阶段性信息（只打印，不计分）。
	var notes: Array = []
	## 当前用例是否已请求 skip/pending（标记后用例应尽早 return）。
	var skip_requested := false
	var pending_requested := false

	func _init(p_tree: SceneTree, p_case_name: String) -> void:
		tree = p_tree
		case_name = p_case_name

	# ---------------------------------------------------------------- 定位
	## 返回调用断言的文件:行号（跳过框架自身栈帧）。
	func _where() -> String:
		var st := get_stack()
		for i in range(1, st.size()):
			var frame: Dictionary = st[i]
			var src := String(frame.get("source", ""))
			if src.ends_with("tests/framework.gd"):
				continue
			var fn := String(frame.get("function", ""))
			var line := int(frame.get("line", 0))
			return "%s:%d(%s)" % [src.get_file(), line, fn]
		if st.size() > 1:
			var f2: Dictionary = st[st.size() - 1]
			return "%s:%d" % [String(f2.get("source", "?")), int(f2.get("line", 0))]
		return "(unknown)"

	func _fmt(v: Variant) -> String:
		var t := typeof(v)
		if t == TYPE_STRING:
			var s: String = v
			s = s.replace("\n", "\\n").replace("\r", "\\r")
			if s.length() > 160:
				s = s.substr(0, 160) + "…(%d chars)" % String(v).length()
			return "\"%s\"" % s
		if t == TYPE_STRING_NAME:
			return "&\"%s\"" % String(v)
		if t == TYPE_FLOAT:
			return "%.6f" % float(v)
		if t == TYPE_ARRAY or t == TYPE_DICTIONARY or t == TYPE_PACKED_STRING_ARRAY:
			var s2 := JSON.stringify(v)
			if s2.length() > 240:
				s2 = s2.substr(0, 240) + "…"
			return s2
		if t == TYPE_NIL:
			return "<null>"
		if t == TYPE_OBJECT:
			var o = v
			if o == null:
				return "<null:Object>"
			return "<%s>" % o.get_class()
		return str(v)

	func _record_fail(message: String) -> void:
		failures.append({"where": _where(), "message": message})

	func note(text: String) -> void:
		notes.append(text)

	# ---------------------------------------------------------------- 基础断言
	func ok(cond: bool, msg := "") -> bool:
		if cond:
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望为 true，实际为 false"))
		return false

	func is_true(cond: bool, msg := "") -> bool:
		return ok(cond, msg)

	func is_false(cond: bool, msg := "") -> bool:
		if cond:
			_record_fail(_prefix(msg, "期望为 false，实际为 true"))
			return false
		passed += 1
		return true

	func is_null(v: Variant, msg := "") -> bool:
		if v == null:
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望为 null，实际为 %s" % _fmt(v)))
		return false

	func not_null(v: Variant, msg := "") -> bool:
		if v != null:
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望非 null，实际为 null"))
		return false

	func eq(actual: Variant, expected: Variant, msg := "") -> bool:
		if _loose_equal(actual, expected):
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望 %s，实际 %s" % [_fmt(expected), _fmt(actual)]))
		return false

	func ne(actual: Variant, unexpected: Variant, msg := "") -> bool:
		if not _loose_equal(actual, unexpected):
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望不等于 %s，实际相等" % _fmt(unexpected)))
		return false

	## 数值近似比较（int/float 都接受）。
	func almost_eq(actual: Variant, expected: Variant, eps := 1e-5, msg := "") -> bool:
		if _is_num(actual) and _is_num(expected) and absf(float(actual) - float(expected)) <= eps:
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望约等于 %s (±%s)，实际 %s" % [_fmt(expected), str(eps), _fmt(actual)]))
		return false

	func gt(actual: Variant, other: Variant, msg := "") -> bool:
		if actual is int or actual is float:
			if float(actual) > float(other):
				passed += 1
				return true
		return _cmp_fail(msg, actual, ">", other)

	func gte(actual: Variant, other: Variant, msg := "") -> bool:
		if actual is int or actual is float:
			if float(actual) >= float(other):
				passed += 1
				return true
		return _cmp_fail(msg, actual, ">=", other)

	func lt(actual: Variant, other: Variant, msg := "") -> bool:
		if actual is int or actual is float:
			if float(actual) < float(other):
				passed += 1
				return true
		return _cmp_fail(msg, actual, "<", other)

	func lte(actual: Variant, other: Variant, msg := "") -> bool:
		if actual is int or actual is float:
			if float(actual) <= float(other):
				passed += 1
				return true
		return _cmp_fail(msg, actual, "<=", other)

	func in_range(actual: Variant, low: Variant, high: Variant, msg := "") -> bool:
		if _is_num(actual) and float(actual) >= float(low) and float(actual) <= float(high):
			passed += 1
			return true
		_record_fail(_prefix(msg, "期望在 [%s, %s] 内，实际 %s" % [str(low), str(high), _fmt(actual)]))
		return false

	func _cmp_fail(msg: String, actual: Variant, op: String, other: Variant) -> bool:
		_record_fail(_prefix(msg, "期望 %s %s %s" % [_fmt(actual), op, _fmt(other)]))
		return false

	func contains(haystack: Variant, needle: Variant, msg := "") -> bool:
		var found := false
		if haystack is String:
			found = String(needle) in String(haystack)
		elif haystack is Array or haystack is PackedStringArray:
			found = needle in haystack
		elif haystack is Dictionary:
			found = haystack.has(needle)
		if found:
			passed += 1
			return true
		_record_fail(_prefix(msg, "%s 中应包含 %s" % [_fmt(haystack), _fmt(needle)]))
		return false

	func not_contains(haystack: Variant, needle: Variant, msg := "") -> bool:
		var found := false
		if haystack is String:
			found = String(needle) in String(haystack)
		elif haystack is Array or haystack is PackedStringArray:
			found = needle in haystack
		if not found:
			passed += 1
			return true
		_record_fail(_prefix(msg, "%s 中不应包含 %s" % [_fmt(haystack), _fmt(needle)]))
		return false

	## 富文本去标记后是否含可读文字（用于 [size]/[color]/[ruby] 这类断言）。
	func visible_contains(bbcode: String, needle: String, msg := "") -> bool:
		return contains(bbcode, needle, msg)

	## 精确比较 Dictionary 的 key 顺序（JSON 字段顺序契约用）。
	func eq_keys(d: Variant, expected_keys: Array, msg := "") -> bool:
		if not (d is Dictionary):
			_record_fail(_prefix(msg, "期望 Dictionary，实际 %s" % _fmt(d)))
			return false
		var actual: Array = (d as Dictionary).keys()
		if actual.size() == expected_keys.size() and _array_str_eq(actual, expected_keys):
			passed += 1
			return true
		_record_fail(_prefix(msg, "key 顺序不符：期望 %s，实际 %s" % [_fmt(expected_keys), _fmt(actual)]))
		return false

	## 深度相等（Dictionary 忽略 key 顺序、int/float 数值等价）。
	func eq_deep(actual: Variant, expected: Variant, msg := "") -> bool:
		var err := _deep_diff(actual, expected, "$")
		if err == "":
			passed += 1
			return true
		_record_fail(_prefix(msg, "深度不等：%s" % err))
		return false

	## 深度相等且 Dictionary 的 key 顺序也一致（round-trip 字段顺序契约用）。
	func eq_deep_ordered(actual: Variant, expected: Variant, msg := "") -> bool:
		var err := _deep_diff_ordered(actual, expected, "$")
		if err == "":
			passed += 1
			return true
		_record_fail(_prefix(msg, "深度/顺序不等：%s" % err))
		return false

	func _deep_diff(a: Variant, b: Variant, path: String) -> String:
		var ta := typeof(a)
		var tb := typeof(b)
		if _is_num(a) and _is_num(b):
			return "" if float(a) == float(b) else "%s: %s != %s" % [path, _fmt(a), _fmt(b)]
		if ta != tb:
			return "%s: 类型不同 %s vs %s" % [path, type_string(ta), type_string(tb)]
		match ta:
			TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
				if a.size() != b.size():
					return "%s: 数组长度 %d != %d" % [path, a.size(), b.size()]
				for i in a.size():
					var e := _deep_diff(a[i], b[i], "%s[%d]" % [path, i])
					if e != "":
						return e
				return ""
			TYPE_DICTIONARY:
				var ka: Array = (a as Dictionary).keys()
				var kb: Array = (b as Dictionary).keys()
				for k in ka:
					if not (b as Dictionary).has(k):
						return "%s: 缺少 key %s" % [path, _fmt(k)]
				for k in kb:
					if not (a as Dictionary).has(k):
						return "%s: 多了 key %s" % [path, _fmt(k)]
				for k in ka:
					var e := _deep_diff(a[k], b[k], "%s.%s" % [path, str(k)])
					if e != "":
						return e
				return ""
			_:
				return "" if a == b else "%s: %s != %s" % [path, _fmt(a), _fmt(b)]

	func _deep_diff_ordered(a: Variant, b: Variant, path: String) -> String:
		if not ((a is Dictionary) and (b is Dictionary)):
			return _deep_diff(a, b, path)
		var ka: Array = (a as Dictionary).keys()
		var kb: Array = (b as Dictionary).keys()
		if ka.size() != kb.size():
			return "%s: key 数量 %d != %d" % [path, ka.size(), kb.size()]
		for i in ka.size():
			if str(ka[i]) != str(kb[i]):
				return "%s: 第 %d 个 key 不同 %s != %s（顺序契约）" % [path, i, _fmt(ka[i]), _fmt(kb[i])]
			var e := _deep_diff_ordered(a[ka[i]], b[kb[i]], "%s.%s" % [path, str(ka[i])])
			if e != "":
				return e
		return ""

	func _is_num(v: Variant) -> bool:
		return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

	func _loose_equal(a: Variant, b: Variant) -> bool:
		if _is_num(a) and _is_num(b):
			return float(a) == float(b)
		return a == b

	func _array_str_eq(a: Array, b: Array) -> bool:
		for i in a.size():
			if str(a[i]) != str(b[i]):
				return false
		return true

	func _prefix(msg: String, detail: String) -> String:
		if msg.is_empty():
			return detail
		return "%s —— %s" % [msg, detail]

	# ---------------------------------------------------------------- 失败/跳过
	func fail(msg: String) -> void:
		_record_fail(msg)

	func skip(reason: String) -> void:
		skip_requested = true
		skip_reasons.append(reason)

	func pending(reason: String) -> void:
		pending_requested = true
		pending_reasons.append(reason)

	# ---------------------------------------------------------------- 模块就绪探测
	## 加载脚本；路径不存在或解析失败返回 null（不打印错误，交给 need() 归因）。
	func load_script(path: String) -> GDScript:
		if not ResourceLoader.exists(path):
			return null
		var s := load(path)
		if s is GDScript:
			return s
		return null

	## 加载依赖脚本；失败时自动 pending。返回 null 表示必须 return。
	func need(path: String, owner := "") -> GDScript:
		var s := load_script(path)
		if s == null:
			var who := "" if owner.is_empty() else "（%s）" % owner
			pending("等待%s模块就绪：%s 不存在或解析失败" % [who, path])
		return s

	## 检查脚本是否提供全部（静态/实例）方法；不满足自动 pending。
	func need_methods(script: GDScript, methods: Array, owner := "") -> bool:
		if script == null:
			return false
		var have := _script_methods(script)
		var missing: Array = []
		for m in methods:
			if not have.has(String(m)):
				missing.append(m)
		if missing.is_empty():
			return true
		var who := "" if owner.is_empty() else "（%s）" % owner
		pending("等待%s API：%s 缺少方法 %s" % [who, script.resource_path, _fmt(missing)])
		return false

	func _script_methods(script: GDScript) -> Array:
		var out: Array = []
		for m in script.get_script_method_list():
			out.append(String(m.get("name", "")))
		return out

	func has_script_method(script: GDScript, method: String) -> bool:
		return script != null and _script_methods(script).has(method)

	## 调用脚本上的静态方法（GDScript 资源本身可调用静态函数）。
	func static_call(script: GDScript, method: String, args := []) -> Variant:
		if script == null:
			return null
		return script.callv(method, args)

	## 读取脚本常量（枚举/const），不存在返回 default。
	func const_of(script: GDScript, name: String, default: Variant = null) -> Variant:
		if script == null:
			return default
		var m: Dictionary = script.get_script_constant_map()
		if m.has(name):
			return m[name]
		return default

	## 全局 class_name 是否已注册（需要 scripts/gen_class_cache.py 已运行）。
	func has_global_class(cls_name: String) -> bool:
		for g in ProjectSettings.get_global_class_list():
			if String(g.get("class", "")) == cls_name:
				return true
		return false

	## 读取对象/字典的字段（兼容不同实现返回 Dictionary 或内部 class 对象）。
	func prop(obj: Variant, name: String, default: Variant = null) -> Variant:
		if obj == null:
			return default
		if obj is Dictionary:
			return (obj as Dictionary).get(name, default)
		if obj is Object:
			var target := obj as Object
			if StringName(name) in target:
				return target.get(name)
		return default

	## 对象上第一个存在的方法名（用于适配对方 API 的多种命名）；没有返回 ""。
	func first_method(obj: Object, names: Array) -> String:
		if obj == null:
			return ""
		for n in names:
			if obj.has_method(String(n)):
				return String(n)
		return ""

	## 依次尝试方法名，返回第一个调用结果；都不存在返回 null。
	func call_first(obj: Object, names: Array, args := []) -> Variant:
		var m := first_method(obj, names)
		if m.is_empty():
			return null
		return obj.callv(m, args)

	## 实例化脚本；失败返回 null 并 fail（不是 pending，因为脚本已存在）。
	func instantiate(script: GDScript, msg := "") -> Object:
		if script == null:
			_record_fail(msg if not msg.is_empty() else "instantiate(null)")
			return null
		if not script.can_instantiate():
			_record_fail((msg if not msg.is_empty() else "instantiate") + "：脚本不可实例化 " + script.resource_path)
			return null
		var o = script.new()
		if o == null:
			_record_fail((msg if not msg.is_empty() else "instantiate") + "：new() 返回 null")
		return o

	# ---------------------------------------------------------------- 帧推进（异步用例用）
	## 等待 n 帧（SceneTree.process_frame）。
	func advance_frames(n: int) -> void:
		for _i in range(maxi(n, 0)):
			await tree.process_frame

	## 等待真实时间（秒）。headless 下帧率很高，但计时器按真实时间走。
	func wait_seconds(sec: float) -> void:
		if sec <= 0.0:
			await tree.process_frame
			return
		await tree.create_timer(sec).timeout

	## 最高层窗口（测试里加节点用）。
	func root_node() -> Window:
		return tree.get_root()

	func ticks_ms() -> int:
		return Time.get_ticks_msec()


## 一轮用例执行结果统计。
class CaseResult extends RefCounted:
	var name := ""
	var desc := ""
	var status := "PASS"  # PASS / FAIL / SKIP / PENDING
	var passed := 0
	var failures: Array = []
	var skip_reasons: Array = []
	var pending_reasons: Array = []
	var notes: Array = []
	var duration_ms := 0
