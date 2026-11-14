extends SceneTree
## qa-dev · AzureArchive Godot 复刻 —— headless 测试入口。
##
## 运行（推荐 `scripts/test.sh`，它会先刷新 class_name 缓存）：
##   cd /root/workspace/aa-godot
##   bash scripts/test.sh                          # 全量
##   bash scripts/test.sh -- --only=xxhash         # 只跑名字含 xxhash 的用例
##   bash scripts/test.sh -- --only=fixtures,class_cache
##   bash scripts/test.sh -- --list                # 列出用例
##   bash scripts/test.sh -- --timeout=180000      # 全局超时（毫秒）
## 也兼容裸命令（首次会自动 bootstrap class 缓存并重启一次自身）：
##   /opt/godot/Godot_v4.7.2-stable_linux.arm64 --headless --path . --script tests/run_all.gd
##
## 约定：
##   - 每个 tests/test_*.gd 是 `extends RefCounted`，实现 `func run(ctx) -> void`
##     （可以是 async，含 `await ctx.advance_frames(n)`）。
##   - 结果四态：PASS / FAIL / SKIP / PENDING；FAIL → 退出码 1。
##   - PENDING = 依赖模块尚未就绪，不算失败；但最终验收要求 pending == 0。
##   - 结果同时写入 `tests/last_result.json` 便于跨轮对比。
##
## 注意：本文件刻意不直接引用其他模块的 class_name（全部动态 load + 反射），
## 这样即使 core/resources/player/editor 尚未就绪、甚至 class 缓存未刷新，
## 测试入口本身也能正常解析并给出 PENDING 报告。

const Fw = preload("res://tests/framework.gd")

## 用例清单。name 用于 --only 过滤与报告；path 必须是 res:// 下的 GDScript。
const CASES := [
	{
		"name": "fixtures",
		"path": "res://tests/test_fixtures.gd",
		"desc": "真实样本 .aap 结构/字段顺序/图连通性静态校验（零依赖）",
	},
	{
		"name": "class_cache",
		"path": "res://tests/test_class_cache.gd",
		"desc": "class_name 全局缓存 + AaRawLoader + autoload AAResources 可用性（零依赖）",
	},
	{
		"name": "xxhash",
		"path": "res://tests/test_xxhash.gd",
		"desc": "AaHash.xxh32 已知向量 + 真实样本 170 行 bgName 全量校验",
	},
	{
		"name": "aap_roundtrip",
		"path": "res://tests/test_aap_roundtrip.gd",
		"desc": "AapProject 载入真实样本 → 序列化 → 再载入 深度语义相等 + 字段顺序",
	},
	{
		"name": "commands",
		"path": "res://tests/test_commands.gd",
		"desc": "#额外指令解析 + [内联标记]→BBCode/strip_inline",
	},
	{
		"name": "core_extras",
		"path": "res://tests/test_core_extras.gd",
		"desc": "枚举表/自动等待/新建工程/错误处理/选择节点重复连线/JSON 转义（core 辅助契约）",
	},
	{
		"name": "synth_fixtures",
		"path": "res://tests/test_synth_fixtures.gd",
		"desc": "合成夹具 fixtures/synth 自身的合法性与可重复生成校验",
	},
	{
		"name": "resources",
		"path": "res://tests/test_resources.gd",
		"desc": "AAResources 数据根/aa_pack/overrides 覆盖优先级/缺资源占位",
	},
	{
		"name": "player_smoke",
		"path": "res://tests/test_player_smoke.gd",
		"desc": "实例化 AaPlayer 播放 fixtures/synth/smoke.aap 到结局不崩",
	},
	{
		"name": "editor_smoke",
		"path": "res://tests/test_editor_smoke.gd",
		"desc": "实例化编辑器 → 新建/加节点/连线/保存 → AapProject 重载一致",
	},
	{
		"name": "main_integration",
		"path": "res://tests/test_main_integration.gd",
		"desc": "目录界面用户路径：列表→播放真实样本到结局→编辑器打开→overlay 关闭",
	},
]

var _cases: Array = []
var _started_ms := 0
var _timeout_ms := 180000
var _only: Array = []
var _list_only := false


func _init() -> void:
	_parse_args()
	if _list_only:
		print("可用用例：")
		for c in CASES:
			print("  %-16s %s" % [c["name"], c["desc"]])
		quit(0)
		return
	if _maybe_bootstrap_class_cache():
		return  # 已重启子进程 / 已报错退出
	_select_cases()
	_started_ms = Time.get_ticks_msec()
	_run_all.call_deferred()


## 裸命令兼容：没有 class_name 全局缓存时（本机无编辑器扫描），先生成缓存再重启自身。
## 正常情况下 `scripts/test.sh` 已经先生成过，这里不会触发。
func _maybe_bootstrap_class_cache() -> bool:
	if not ProjectSettings.get_global_class_list().is_empty():
		return false
	if OS.get_environment("AA_TEST_BOOTSTRAP") == "1":
		printerr("[bootstrap] class_name 缓存仍为空，放弃自举；请先跑 python3 scripts/gen_class_cache.py")
		quit(1)
		return true
	print("[bootstrap] 未检测到 class_name 全局缓存，自动生成后重启测试…")
	var gen_code := OS.execute("python3", ["scripts/gen_class_cache.py", "--quiet"], [], true)
	if gen_code != 0:
		printerr("[bootstrap] python3 scripts/gen_class_cache.py 失败（exit=%d）" % gen_code)
		quit(1)
		return true
	if ProjectSettings.get_global_class_list().is_empty() and not FileAccess.file_exists("res://.godot/global_script_class_cache.cfg"):
		printerr("[bootstrap] 缓存生成后仍不可用，请检查脚本")
		quit(1)
		return true
	var args: Array = ["--headless", "--path", ".", "--script", "tests/run_all.gd"]
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		for a in user_args:
			args.append(String(a))
	OS.set_environment("AA_TEST_BOOTSTRAP", "1")
	# 捕获子进程输出并回放（否则裸命令看起来什么都没跑）。
	var child_out: Array = []
	var code := OS.execute(OS.get_executable_path(), args, child_out, true)
	for line in child_out:
		print(String(line))
	quit(code)
	return true


# ----------------------------------------------------------------------------
# 参数
# ----------------------------------------------------------------------------

func _parse_args() -> void:
	var args: Array = []
	args.append_array(OS.get_cmdline_user_args())
	# 兼容直接写成 `--only=xxx`（不在 `--` 之后）时也能取到。
	var engine_args := OS.get_cmdline_args()
	var i := 0
	while i < engine_args.size():
		var a := String(engine_args[i])
		if a == "--only" or a == "--filter" or a == "-o":
			if i + 1 < engine_args.size():
				_push_only(String(engine_args[i + 1]))
				i += 1
		elif a.begins_with("--only="):
			_push_only(a.substr("--only=".length()))
		elif a.begins_with("--filter="):
			_push_only(a.substr("--filter=".length()))
		elif a == "--list":
			_list_only = true
		elif a.begins_with("--timeout="):
			_timeout_ms = int(a.substr("--timeout=".length()))
		i += 1
	for a2 in OS.get_cmdline_user_args():
		var s := String(a2)
		if s.begins_with("--only="):
			_push_only(s.substr("--only=".length()))
		elif s.begins_with("--filter="):
			_push_only(s.substr("--filter=".length()))
		elif s == "--list":
			_list_only = true
		elif s.begins_with("--timeout="):
			_timeout_ms = int(s.substr("--timeout=".length()))
	var env_timeout := OS.get_environment("AA_TEST_TIMEOUT_MS")
	if not env_timeout.is_empty():
		_timeout_ms = int(env_timeout)
	var env_only := OS.get_environment("AA_TEST_ONLY")
	if not env_only.is_empty():
		_push_only(env_only)


func _push_only(raw: String) -> void:
	for part in raw.split(",", false):
		var p := String(part).strip_edges()
		if not p.is_empty():
			_only.append(p.to_lower())


func _select_cases() -> void:
	_cases = []
	for c in CASES:
		if _only.is_empty():
			_cases.append(c)
			continue
		var name := String(c["name"]).to_lower()
		for f in _only:
			if name.contains(String(f)):
				_cases.append(c)
				break


# ----------------------------------------------------------------------------
# 执行
# ----------------------------------------------------------------------------

class Watchdog extends Node:
	var main_loop: SceneTree
	var started_ms := 0
	var limit_ms := 180000
	var fired := false

	func _process(_delta: float) -> void:
		if fired:
			return
		if Time.get_ticks_msec() - started_ms > limit_ms:
			fired = true
			printerr("")
			printerr("!! 测试套件超时（>%d ms），强制退出，退出码 1" % limit_ms)
			main_loop.quit(1)


func _run_all() -> void:
	# 看门狗放到 root 上，避免覆盖 SceneTree 自身的处理逻辑。
	var root := get_root()
	var wd := Watchdog.new()
	wd.main_loop = self
	wd.started_ms = _started_ms
	wd.limit_ms = _timeout_ms
	root.add_child(wd)

	var version := "?"
	var info := Engine.get_version_info()
	if info is Dictionary:
		version = "%s.%s.%s" % [info.get("major", "?"), info.get("minor", "?"), info.get("patch", "?")]
	var global_classes := ProjectSettings.get_global_class_list().size()

	print("")
	print("================================================================================")
	print("qa-dev 测试套件 · AzureArchive Godot 复刻")
	print("Godot %s | 全局 class_name: %d | 用例: %d | 超时: %dms | 过滤: %s" % [
		version, global_classes, _cases.size(), _timeout_ms,
		"全部" if _only.is_empty() else str(_only),
	])
	print("工程: %s" % ProjectSettings.globalize_path("res://"))
	print("================================================================================")

	var results: Array = []
	for case_def in _cases:
		if wd.fired:
			break
		var r: Fw.CaseResult = await _run_case(case_def)
		results.append(r)
		_print_case(r)

	var failed := 0
	var skipped := 0
	var pending := 0
	var total_pass := 0
	var total_assert_fail := 0
	for r in results:
		match String(r.status):
			"FAIL":
				failed += 1
			"SKIP":
				skipped += 1
			"PENDING":
				pending += 1
		total_pass += int(r.passed)
		total_assert_fail += (r.failures as Array).size()

	var passed := results.size() - failed - skipped - pending
	print("")
	print("--------------------------------------------------------------- 失败详情")
	var any_detail := false
	for r in results:
		if r.status == "FAIL":
			any_detail = true
			print("[FAIL] %s（%s）" % [r.name, r.desc])
			for f in r.failures:
				print("   - %s  %s" % [f.get("where", "?"), f.get("message", "")])
		elif r.status == "PENDING":
			any_detail = true
			print("[PENDING] %s — %s" % [r.name, "；".join(r.pending_reasons)])
		elif r.status == "SKIP":
			any_detail = true
			print("[SKIP] %s — %s" % [r.name, "；".join(r.skip_reasons)])
	if not any_detail:
		print("（无）")

	print("")
	print("================================================================================")
	print("结果: 用例 %d 个 → PASS %d / FAIL %d / SKIP %d / PENDING %d" % [
		results.size(), passed, failed, skipped, pending,
	])
	print("断言: 通过 %d / 失败 %d" % [total_pass, total_assert_fail])
	print("耗时: %d ms" % (Time.get_ticks_msec() - _started_ms))
	print("================================================================================")

	_write_result_json(results, passed, failed, skipped, pending, total_pass, total_assert_fail)

	if wd.fired:
		quit(1)
		return
	quit(1 if failed > 0 else 0)


func _run_case(case_def: Dictionary) -> Fw.CaseResult:
	var r: Fw.CaseResult = Fw.CaseResult.new()
	r.name = String(case_def.get("name", "?"))
	r.desc = String(case_def.get("desc", ""))
	var t0 := Time.get_ticks_msec()
	var path := String(case_def.get("path", ""))
	var script = load(path)
	if script == null:
		r.status = "FAIL"
		r.failures.append({
			"where": path.get_file(),
			"message": "用例脚本加载失败（语法错误或 class_name 缓存过期？先跑 python3 scripts/gen_class_cache.py）",
		})
		r.duration_ms = Time.get_ticks_msec() - t0
		return r
	if not (script is GDScript):
		r.status = "FAIL"
		r.failures.append({"where": path.get_file(), "message": "不是 GDScript：%s" % path})
		r.duration_ms = Time.get_ticks_msec() - t0
		return r
	if not script.can_instantiate():
		r.status = "FAIL"
		r.failures.append({"where": path.get_file(), "message": "用例脚本不可实例化：%s" % path})
		r.duration_ms = Time.get_ticks_msec() - t0
		return r
	var inst = script.new()
	if not inst.has_method("run"):
		r.status = "FAIL"
		r.failures.append({"where": path.get_file(), "message": "用例脚本缺少 func run(ctx)"})
		r.duration_ms = Time.get_ticks_msec() - t0
		return r

	var ctx: Fw.Ctx = Fw.Ctx.new(self, r.name)
	await inst.run(ctx)

	r.passed = ctx.passed
	r.failures = ctx.failures
	r.skip_reasons = ctx.skip_reasons
	r.pending_reasons = ctx.pending_reasons
	r.notes = ctx.notes
	if not (ctx.failures as Array).is_empty():
		r.status = "FAIL"
	elif ctx.pending_requested:
		r.status = "PENDING"
	elif ctx.skip_requested:
		r.status = "SKIP"
	elif ctx.passed == 0:
		r.status = "FAIL"
		r.failures.append({
			"where": path.get_file(),
			"message": "用例执行完毕但没有任何断言（run() 是否提前 return / 脚本中途报错？）",
		})
	else:
		r.status = "PASS"
	r.duration_ms = Time.get_ticks_msec() - t0
	return r


func _print_case(r: Fw.CaseResult) -> void:
	var tag := "[%s]" % String(r.status)
	# 手工对齐：PASS/FAIL/SKIP/PENDING 长度不同，统一到 9 字符。
	var pad := " " if tag.length() < 9 else ""
	var extra := ""
	match r.status:
		"PASS":
			extra = "%d 断言" % r.passed
		"FAIL":
			extra = "%d 断言 / %d 失败" % [r.passed, (r.failures as Array).size()]
		"PENDING":
			extra = "等待依赖：" + "；".join(r.pending_reasons)
		"SKIP":
			extra = "跳过：" + "；".join(r.skip_reasons)
	print("%s%s %-18s %6dms  %s" % [tag, pad, r.name, r.duration_ms, extra])


func _write_result_json(results: Array, passed: int, failed: int, skipped: int, pending: int, total_pass: int, total_assert_fail: int) -> void:
	var cases_out: Array = []
	for r in results:
		var fails: Array = []
		for f in r.failures:
			fails.append("%s %s" % [f.get("where", "?"), f.get("message", "")])
		cases_out.append({
			"name": r.name,
			"status": r.status,
			"passed": r.passed,
			"failures": fails,
			"pending": r.pending_reasons,
			"skip": r.skip_reasons,
			"duration_ms": r.duration_ms,
		})
	var payload := {
		"timestamp": Time.get_datetime_string_from_system(true),
		"godot": str(Engine.get_version_info().get("string", "")),
		"case_filter": _only,
		"summary": {
			"cases": results.size(),
			"pass": passed,
			"fail": failed,
			"skip": skipped,
			"pending": pending,
			"assert_pass": total_pass,
			"assert_fail": total_assert_fail,
		},
		"cases": cases_out,
	}
	var f := FileAccess.open("res://tests/last_result.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  ", false) + "\n")
		f.close()
