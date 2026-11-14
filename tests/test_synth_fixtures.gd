extends RefCounted
## test_synth_fixtures.gd —— 校验 qa-dev 自己的合成夹具 `fixtures/synth/`。
##
## 目标：合成夹具本身必须是「合法 AA 格式 + 内容可预期 + 可重复生成」，否则所有依赖它的
## 用例（player_smoke / resources / editor_smoke）都会变成假绿。断言：
##   1. `smoke.aap` / `smoke_fast.aap` 的格式契约（字段顺序/$type/图连通性/角色站位规则）；
##   2. smoke 含 `#wait;5000` 与 [size]/[color]/[ruby] 内联标记；fast 版不含额外指令；
##   3. `generated.json` 的 SHA-256 清单与磁盘一致（= python3 tests/make_fixtures.py 可重复生成）；
##   4. 最小 aa_pack 布局符合 pack-dev 定稿（catalog.json + bgs/bgm/sounds/popups/characters）；
##   5. pack/overrides/project_local 的同名背景颜色分别为 红/绿/蓝（供 resources 优先级用例）。
##
## 零业务依赖（不用 core/pack 模块），只用 FileAccess/JSON/Image。

const Fw = preload("res://tests/framework.gd")

const SYNTH_DIR := "res://fixtures/synth"
const SMOKE := "res://fixtures/synth/smoke.aap"
const SMOKE_FAST := "res://fixtures/synth/smoke_fast.aap"
const GENERATED := "res://fixtures/synth/generated.json"

const T_PROJECT := "ProjectData, Assembly-CSharp"
const T_ENTRY := "EntryNodeData, Assembly-CSharp"
const T_SCRIPT := "ScriptNodeData, Assembly-CSharp"
const T_CHOICE := "SelectionNodeData, Assembly-CSharp"
const T_EXIT := "ExitNodeData, Assembly-CSharp"
const ZERO_GUID := "00000000-0000-0000-0000-000000000000"

const EXPECT_TOP := ["$type", "ProjectName", "PreviewBgName", "PreviewHeader", "PreviewTitle", "nodes"]
const EXPECT_ENTRY := ["$type", "Title", "Header", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_SCRIPT := ["$type", "Scripts", "NodeName", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_CHOICE := ["$type", "selectionTexts", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_EXIT := ["$type", "IsEnding", "EndText", "NeHeader", "NeTitle", "NeScriptDirty", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_SCRIPT_DATA := [
	"$type", "text", "popup", "bgEffect", "bgName", "bgFriendlyName", "sound", "voice",
	"transition", "bgmId", "selectionGroup", "additionalPrompt", "characters",
	"speakerSlotNum", "highlightedSlotNums", "isDialogScript", "placeText",
]
const EXPECT_CHAR := ["$type", "name", "faceId", "startingPos", "endingPos", "emoticon",
		"action", "effect", "appear", "shapeOverride"]

## 生成器产出的文件清单（相对 fixtures/synth；generated.json 自身不在列表内）
const REQUIRED_FILES := [
	"smoke.aap",
	"smoke_fast.aap",
	"pack/catalog.json",
	"pack/manifest.json",
	"pack/bgs/synth_bg.png",
	"pack/bgs/synth_bg_alt.png",
	"pack/popups/synth_popup.png",
	"pack/characters/QA_HERO/00.png",
	"pack/characters/QA_HERO/00-avatar.png",
	"pack/bgm/synth_bgm.wav",
	"pack/sounds/SE_QA_01.wav",
	"overrides/manifest.json",
	"overrides/bgs/synth_bg.png",
	"project_local/manifest.json",
	"project_local/bgs/synth_bg.png",
]


func run(ctx: Fw.Ctx) -> void:
	# ---------------------------------------------------------------- 1. 文件清单
	ctx.is_true(FileAccess.file_exists(GENERATED), "generated.json 存在（先跑 python3 tests/make_fixtures.py）")
	for rel in REQUIRED_FILES:
		ctx.is_true(FileAccess.file_exists(SYNTH_DIR.path_join(rel)), "合成夹具存在：%s" % rel)
	if not FileAccess.file_exists(SMOKE) or not FileAccess.file_exists(GENERATED):
		return

	var gen: Variant = JSON.parse_string(FileAccess.get_file_as_string(GENERATED))
	ctx.is_true(gen is Dictionary, "generated.json 可解析")
	if not (gen is Dictionary):
		return
	var gd: Dictionary = gen
	ctx.eq(String(gd.get("generator", "")), "tests/make_fixtures.py", "generated.json.generator")
	ctx.eq(int(gd.get("generator_version", 0)), 2, "generator_version == 2")
	var vectors: Dictionary = gd.get("xxh32_vectors", {})
	ctx.eq(int(vectors.get("", -1)), 0, "xxh32 向量：空串 -> 0（AA 无背景约定）")
	ctx.eq(int(vectors.get("BG_RuinUndergroundPassage", -1)), 3558049603,
			"xxh32 向量：BG_RuinUndergroundPassage -> 3558049603（与真实样本一致）")
	var synth_bg_id := int(vectors.get("synth_bg", -1))
	ctx.ne(synth_bg_id, -1, "xxh32 向量里有 synth_bg")

	# ---------------------------------------------------------------- 2. smoke.aap 格式契约
	var smoke: Variant = JSON.parse_string(FileAccess.get_file_as_string(SMOKE))
	ctx.is_true(smoke is Dictionary, "smoke.aap 可解析为 JSON")
	if smoke is Dictionary:
		var d: Dictionary = smoke
		ctx.eq_keys(d, EXPECT_TOP, "smoke.aap 顶层字段顺序")
		ctx.eq(String(d.get("$type", "")), T_PROJECT, "smoke.aap 顶层 $type")
		ctx.eq(String(d.get("ProjectName", "")), "QA-Smoke", "ProjectName")
		ctx.eq(int(d.get("PreviewBgName", 0)), synth_bg_id, "PreviewBgName == xxh32(synth_bg)")
		ctx.is_null(d.get("PreviewHeader"), "PreviewHeader 为 null（合法）")
		var nodes: Array = (d.get("nodes", {}) as Dictionary).get("$values", [])
		ctx.eq(nodes.size(), 6, "smoke.aap 6 节点")
		var types := {T_ENTRY: 0, T_SCRIPT: 0, T_CHOICE: 0, T_EXIT: 0}
		var guids: Array = []
		for n in nodes:
			var t := String((n as Dictionary).get("$type", ""))
			if types.has(t):
				types[t] = int(types[t]) + 1
			guids.append(String((n as Dictionary).get("Guid", "")))
		ctx.eq(int(types[T_ENTRY]), 1, "1 个入口")
		ctx.eq(int(types[T_SCRIPT]), 3, "3 个 ScriptNode")
		ctx.eq(int(types[T_CHOICE]), 1, "1 个 SelectionNode")
		ctx.eq(int(types[T_EXIT]), 1, "1 个 ExitNode")
		ctx.eq(String(nodes[0].get("Guid", "")), ZERO_GUID, "入口在最前且 Guid 全 0")
		ctx.eq(guids.size(), 6, "6 个 Guid")

		var total_lines := 0
		var all_conn_ok := true
		var choice_node: Dictionary = {}
		var exit_node: Dictionary = {}
		var script_rows: Array = []
		for n in nodes:
			var node: Dictionary = n
			var t2 := String(node.get("$type", ""))
			var ct: Dictionary = node.get("ConnectionsTo", {})
			ctx.eq_keys(ct, ["$type", "$values"], "ConnectionsTo 字段顺序")
			for target in ct.get("$values", []):
				if not (String(target) in guids):
					all_conn_ok = false
					ctx.fail("连线目标不存在：%s" % target)
			match t2:
				T_ENTRY:
					ctx.eq_keys(node, EXPECT_ENTRY, "Entry 字段顺序")
				T_SCRIPT:
					ctx.eq_keys(node, EXPECT_SCRIPT, "ScriptNode 字段顺序")
					for row in (node.get("Scripts", {}) as Dictionary).get("$values", []):
						total_lines += 1
						script_rows.append(row)
						ctx.eq_keys(row, EXPECT_SCRIPT_DATA, "ScriptData 字段顺序")
						var chars: Array = (row.get("characters", {}) as Dictionary).get("$values", [])
						ctx.eq(chars.size(), 6, "characters 固定 6 项")
						for idx in range(chars.size()):
							ctx.eq_keys(chars[idx], EXPECT_CHAR, "CharacterRecordData 字段顺序")
							# 槽 0 = 无立绘说话槽；1–5 的 startingPos 必须等于下标
							if idx >= 1 and String(chars[idx].get("name", "")) != "":
								ctx.eq(int(chars[idx].get("startingPos", -1)), idx,
										"槽 %d 角色 startingPos == 下标" % idx)
						if String(row.get("bgFriendlyName", "")) != "":
							ctx.eq(int(row.get("bgName", 0)), synth_bg_id, "行 bgName == xxh32(synth_bg)")
				T_CHOICE:
					choice_node = node
					ctx.eq_keys(node, EXPECT_CHOICE, "SelectionNode 字段顺序")
					var texts: Dictionary = node.get("selectionTexts", {})
					ctx.eq(texts.get("$values", []).size(), 16, "选择节点固定 16 槽")
					var opts: Array = texts.get("$values", [])
					ctx.eq(String(opts[0]), "向右走", "选项 0 文本")
					ctx.eq(String(opts[1]), "向左走", "选项 1 文本")
					for k in range(2, 16):
						ctx.eq(String(opts[k]), "", "未用槽 %d 补空串" % k)
					ctx.eq(ct.get("$values", []).size(), 2, "选择节点 2 条出边")
				T_EXIT:
					exit_node = node
					ctx.eq_keys(node, EXPECT_EXIT, "ExitNode 字段顺序")
					ctx.eq(bool(node.get("IsEnding", false)), true, "出口 IsEnding == true（Ending）")
					ctx.eq(String(node.get("EndText", "")), "—— 合成冒烟测试结束 ——", "EndText")
					ctx.eq_keys(node.get("NeScriptDirty", {}), EXPECT_SCRIPT_DATA, "NeScriptDirty 字段顺序")
					total_lines += 1  # NeScriptDirty 也是一行 ScriptData
		ctx.is_true(all_conn_ok, "所有连线目标都存在")
		ctx.eq(total_lines, 6, "smoke.aap 共 6 行 ScriptData（3 正文 + 2 分支 + 1 出口预告）")
		ctx.is_true(not choice_node.is_empty(), "存在选择节点")
		ctx.is_true(not exit_node.is_empty(), "存在出口节点")

		# 角色沿用与站位连续性（编译规则硬约束）
		ctx.eq(script_rows.size(), 5, "5 行正文 ScriptData")
		var row2: Dictionary = script_rows[1]
		var row3: Dictionary = script_rows[2]
		var hero2: Dictionary = (row2.get("characters", {}) as Dictionary).get("$values", [])[1]
		var hero3: Dictionary = (row3.get("characters", {}) as Dictionary).get("$values", [])[1]
		ctx.eq(String(hero2.get("name", "")), "QA_HERO", "第 2 行槽 1 角色是 QA_HERO")
		ctx.eq(int(hero2.get("appear", 0)), 3, "首次登场 appear=3")
		ctx.eq(int(hero3.get("startingPos", -1)), 1, "第 3 行槽 1 startingPos 保持 1")
		ctx.eq(int(hero2.get("endingPos", -1)), int(hero3.get("startingPos", -2)), "上一行 endingPos == 下一行 startingPos")

		# 额外指令 + 内联标记（任务要求 smoke 必须包含）
		var prompts: Array = []
		var texts: Array = []
		for r in script_rows:
			prompts.append(String((r as Dictionary).get("additionalPrompt", "")))
			texts.append(String((r as Dictionary).get("text", "")))
		ctx.is_true("#wait;5000" in prompts, "smoke.aap 含 #wait;5000 额外指令")
		ctx.is_true("#bgshake" in prompts, "smoke.aap 含 #bgshake 额外指令")
		var joined := "\n".join(texts)
		ctx.contains(joined, "[size=200]放大[/size]", "内联标记 [size=...]")
		ctx.contains(joined, "[FF0000]红色[-]", "内联标记 [颜色]...[-]")
		ctx.contains(joined, "[ruby=zhùyīn]注音[/ruby]", "内联标记 [ruby=...]")
		ctx.contains(joined, "合成工程开始", "smoke.aap 有可读台词")

	# ---------------------------------------------------------------- 3. smoke_fast.aap：快速播放兜底
	var fast: Variant = JSON.parse_string(FileAccess.get_file_as_string(SMOKE_FAST))
	ctx.is_true(fast is Dictionary, "smoke_fast.aap 可解析")
	if fast is Dictionary:
		var fnodes: Array = ((fast as Dictionary).get("nodes", {}) as Dictionary).get("$values", [])
		ctx.eq(fnodes.size(), 6, "smoke_fast.aap 也是 6 节点")
		var fast_prompts: Array = []
		for n in fnodes:
			if String((n as Dictionary).get("$type", "")) == T_SCRIPT:
				for row in ((n as Dictionary).get("Scripts", {}) as Dictionary).get("$values", []):
					fast_prompts.append(String((row as Dictionary).get("additionalPrompt", "")))
		ctx.not_contains("|".join(fast_prompts), "#wait", "smoke_fast.aap 不含 #wait（无需 instant_mode 也能快速跑完）")
		ctx.not_contains("|".join(fast_prompts), "#bgshake", "smoke_fast.aap 不含 #bgshake")

	# ---------------------------------------------------------------- 4. generated.json 哈希清单 = 可重复生成
	var files: Dictionary = gd.get("files", {})
	ctx.eq(files.size(), REQUIRED_FILES.size(), "generated.json 列出的产物数 == %d" % REQUIRED_FILES.size())
	for rel in REQUIRED_FILES:
		ctx.is_true(files.has(rel), "generated.json 记录 %s 的哈希" % rel)
	var bad_hash: Array = []
	for rel in files:
		var path := SYNTH_DIR.path_join(String(rel))
		if not FileAccess.file_exists(path):
			bad_hash.append("%s 缺失" % rel)
			continue
		var actual := _sha256_file(path)
		if actual != String(files[rel]):
			bad_hash.append("%s 哈希不符（夹具被手改？重新 python3 tests/make_fixtures.py）" % rel)
	ctx.eq(bad_hash.size(), 0, "全部夹具 SHA-256 与 generated.json 一致：%s" % str(bad_hash))

	# 目录里不应有未登记的生成产物（README.md 除外）
	var extra: Array = []
	_walk(SYNTH_DIR, "", extra)
	for rel2 in extra:
		if rel2 == "README.md" or rel2 == "generated.json":
			continue
		if not files.has(rel2):
			ctx.fail("fixtures/synth 下有未登记文件：%s（应加入生成器或删除）" % rel2)
	ctx.eq(extra.size(), REQUIRED_FILES.size() + 2, "fixtures/synth 文件总数 = 15 产物 + generated.json + README.md")

	# ---------------------------------------------------------------- 5. 最小 aa_pack 布局（pack-dev 定稿）
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(SYNTH_DIR.path_join("pack/catalog.json")))
	ctx.is_true(catalog is Dictionary, "pack/catalog.json 可解析")
	if catalog is Dictionary:
		var cat: Dictionary = catalog
		ctx.eq(String(cat.get("format", "")), "aa_pack", "catalog.format == aa_pack")
		ctx.eq(int(cat.get("format_version", 0)), 1, "catalog.format_version == 1")
		ctx.eq(String(cat.get("id", "")), "synth_pack", "catalog.id")
		ctx.eq(String(cat.get("game", "")), "AzureArchive", "catalog.game")
		for section in ["bgs", "bgm", "sounds", "popups", "characters"]:
			ctx.is_true(cat.get(section) is Array, "catalog 有 %s 数组" % section)
		ctx.eq((cat.get("bgs", []) as Array).size(), 2, "catalog.bgs 2 条")
		ctx.eq(String((cat.get("bgs", []) as Array)[0].get("name", "")), "synth_bg", "catalog.bgs[0].name")
		ctx.eq(String((cat.get("characters", []) as Array)[0].get("identifier", "")), "QA_HERO",
				"catalog.characters[0].identifier")
		ctx.eq(String((cat.get("characters", []) as Array)[0].get("portrait_mode", "")), "png",
				"合成角色立绘模式 png（不需 Spine）")
		# catalog 里登记的文件都真实存在
		for entry in cat.get("bgs", []):
			ctx.is_true(FileAccess.file_exists(SYNTH_DIR.path_join("pack").path_join(String(entry.get("file", "?")))),
					"catalog.bgs 文件存在：%s" % entry.get("file", "?"))
		for entry in cat.get("sounds", []):
			ctx.is_true(FileAccess.file_exists(SYNTH_DIR.path_join("pack").path_join(String(entry.get("file", "?")))),
					"catalog.sounds 文件存在：%s" % entry.get("file", "?"))
		for entry in cat.get("bgm", []):
			ctx.is_true(FileAccess.file_exists(SYNTH_DIR.path_join("pack").path_join(String(entry.get("file", "?")))),
					"catalog.bgm 文件存在：%s" % entry.get("file", "?"))

	# ---------------------------------------------------------------- 6. 素材可解码 + 三色覆盖夹具
	var red: Variant = _png_color(ctx, SYNTH_DIR.path_join("pack/bgs/synth_bg.png"), "pack/bgs/synth_bg.png")
	var green: Variant = _png_color(ctx, SYNTH_DIR.path_join("overrides/bgs/synth_bg.png"), "overrides/bgs/synth_bg.png")
	var blue: Variant = _png_color(ctx, SYNTH_DIR.path_join("project_local/bgs/synth_bg.png"), "project_local/bgs/synth_bg.png")
	ctx.not_null(red, "pack 背景 PNG 可解码")
	ctx.not_null(green, "overrides 背景 PNG 可解码")
	ctx.not_null(blue, "project_local 背景 PNG 可解码")
	if red != null and green != null and blue != null:
		var cr: Color = red
		var cg: Color = green
		var cb: Color = blue
		ctx.is_true(cr.r > 0.7 and cr.g < 0.3, "pack 背景是红色（覆盖优先级底层）")
		ctx.is_true(cg.g > 0.6 and cg.r < 0.3, "overrides 背景是绿色（中层）")
		ctx.is_true(cb.b > 0.7 and cb.r < 0.3, "project_local 背景是蓝色（最高层）")
		ctx.ne(cr, cg, "三层背景颜色互不相同（否则优先级测试无效）")
		ctx.ne(cg, cb, "overrides / project_local 颜色不同")
	_png_color(ctx, SYNTH_DIR.path_join("pack/characters/QA_HERO/00.png"), "pack 角色立绘 PNG")
	_png_color(ctx, SYNTH_DIR.path_join("pack/popups/synth_popup.png"), "pack 弹出图 PNG")
	_png_color(ctx, SYNTH_DIR.path_join("pack/characters/QA_HERO/00-avatar.png"), "pack 角色头像 PNG")

	# WAV 头（RIFF/WAVE），避免依赖音频设备
	for wav_rel in ["pack/bgm/synth_bgm.wav", "pack/sounds/SE_QA_01.wav"]:
		var wav_bytes := FileAccess.get_file_as_bytes(SYNTH_DIR.path_join(wav_rel))
		ctx.gt(wav_bytes.size(), 44, "%s 大小 > 44 字节" % wav_rel)
		if wav_bytes.size() >= 12:
			ctx.eq(wav_bytes.slice(0, 4).get_string_from_ascii(), "RIFF", "%s RIFF 头" % wav_rel)
			ctx.eq(wav_bytes.slice(8, 12).get_string_from_ascii(), "WAVE", "%s WAVE 头" % wav_rel)


func _sha256_file(path: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var pos := 0
	var size := f.get_length()
	while pos < size:
		var n := mini(1 << 20, size - pos)
		h.update(f.get_buffer(n))
		pos += n
	f.close()
	return h.finish().hex_encode()


## 递归列出目录下所有文件（相对 BASE 的路径）。
func _walk(dir_path: String, prefix: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var rel := name if prefix.is_empty() else prefix.path_join(name)
			if d.current_is_dir():
				_walk(dir_path.path_join(name), rel, out)
			else:
				out.append(rel)
		name = d.get_next()
	d.list_dir_end()


## 读 PNG 第一个像素颜色；失败返回 null。
func _png_color(ctx: Fw.Ctx, path: String, label: String) -> Variant:
	var img := Image.new()
	var err := img.load(path)
	if err != OK or img.is_empty():
		ctx.fail("%s 无法解码（err=%d）" % [label, err])
		return null
	ctx.passed += 1
	return img.get_pixel(0, 0)
