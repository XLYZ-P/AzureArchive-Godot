extends RefCounted
## test_resources.gd —— 资源层（AAResources / AaResContext / AaManifest / aa_pack）。
##
## 用 fixtures/synth 下的合成夹具搭一个临时数据根目录，验证 docs/DESIGN.md §5.2：
##   1. `set_data_root` / `ensure_layout` / `get_projects` / `get_saves`；
##   2. `install_pack`（文件夹 + .zip）→ `get_packs` / `uninstall_pack`；
##   3. 覆盖优先级（低→高）：aa_pack < overrides/ < projects/<同名文件夹>/：
##      同一张背景在 pack=红、overrides=绿、project_local=蓝，逐层断言取到正确颜色；
##   4. 背景 ID：`get_bg_by_id(xxh32(bgFriendlyName))` 与按名查询一致；
##   5. 缺资源占位不崩：背景/音效/BGM/弹出图/角色缺失都返回占位（非 null）并带
##      `aa_placeholder` 标记；空名字（`get_bg("")`）返回 null 的 AA 约定；
##   6. AaManifest 读写/overlay 合并；
##   7. 测试结束恢复 AAResources.data_root（避免污染其他用例）。
##
## 依赖 pack-dev 的 addons/aa_resources。夹具由 tests/make_fixtures.py 生成。

const Fw = preload("res://tests/framework.gd")

const PACK_DIR := "res://fixtures/synth/pack"
const OVERRIDES_DIR := "res://fixtures/synth/overrides"
const PROJECT_LOCAL_DIR := "res://fixtures/synth/project_local"
const SMOKE_AAP := "res://fixtures/synth/smoke.aap"
const TMP_ROOT := "user://qa_res_data"
const ZIP_PATH := "user://qa_res_data_pack.zip"

## 合成夹具三层背景颜色（与 make_fixtures.py 一致）
const PACK_RED := Color8(220, 40, 40)
const OVERRIDES_GREEN := Color8(40, 200, 40)
const PROJECT_BLUE := Color8(40, 40, 220)


func run(ctx: Fw.Ctx) -> void:
	var ar := ctx.tree.get_root().get_node_or_null("AAResources")
	ctx.not_null(ar, "autoload AAResources 存在")
	if ar == null:
		return
	var original_root: String = String(ar.get("data_root"))
	ctx.note("data_root 原值：%s -> 本轮临时目录 %s" % [original_root, TMP_ROOT])

	# ---------------------------------------------------------------- 0. 重建临时数据根
	_rmtree(TMP_ROOT)
	ar.set_data_root(TMP_ROOT)
	ctx.eq(String(ar.get("data_root")), TMP_ROOT, "set_data_root 生效")
	ar.ensure_layout()
	for sub in ["projects", "saves", "overrides", "assets", "packs", "settings"]:
		ctx.is_true(DirAccess.dir_exists_absolute(TMP_ROOT.path_join(sub)),
				"ensure_layout 创建 %s/" % sub)

	# ---------------------------------------------------------------- 1. aa_pack：文件夹安装
	var pack_error: int = ar.install_pack(PACK_DIR)
	ctx.eq(pack_error, OK, "install_pack(文件夹) 返回 OK（last_error=%s）" % String(ar.get("last_error")))
	ctx.is_true(DirAccess.dir_exists_absolute(TMP_ROOT.path_join("packs/synth_pack")),
			"pack 安装到 packs/synth_pack/")
	ctx.is_true(FileAccess.file_exists(TMP_ROOT.path_join("packs/synth_pack/catalog.json")),
			"安装后 catalog.json 存在")
	var packs: Array = ar.get_packs()
	ctx.eq(packs.size(), 1, "get_packs() 1 个包")
	if packs.size() == 1:
		ctx.eq(String((packs[0] as Dictionary).get("id", "")), "synth_pack",
				"pack id 来自 catalog.json")
		ctx.is_true(bool((packs[0] as Dictionary).get("valid", false)), "pack valid")
		ctx.eq(String((packs[0] as Dictionary).get("name", "")), "QA 合成最小包", "pack name")
	ctx.eq(ar.install_pack("res://不存在的目录"), ERR_FILE_NOT_FOUND, "install_pack(不存在) 返回 ERR_FILE_NOT_FOUND")
	ctx.eq(ar.uninstall_pack("no_such_pack"), ERR_FILE_NOT_FOUND, "uninstall_pack(未安装) 返回 ERR_FILE_NOT_FOUND")

	# ---------------------------------------------------------------- 2. overrides + 工程本地目录
	_copy_tree(OVERRIDES_DIR, TMP_ROOT.path_join("overrides"))
	_copy_tree(PROJECT_LOCAL_DIR, TMP_ROOT.path_join("projects/smoke"))
	ctx.is_true(FileAccess.file_exists(TMP_ROOT.path_join("overrides/manifest.json")), "overrides/manifest.json 就位")
	ctx.is_true(FileAccess.file_exists(TMP_ROOT.path_join("projects/smoke/bgs/synth_bg.png")),
			"projects/smoke/bgs/synth_bg.png 就位")
	# 放一个 .aap 到 projects/，验证 get_projects 列表
	_copy_file(SMOKE_AAP, TMP_ROOT.path_join("projects/smoke.aap"))
	var projects: Array = ar.get_projects()
	ctx.eq(projects.size(), 1, "get_projects() 列出 1 个工程")
	if projects.size() == 1:
		ctx.contains(String((projects[0] as Dictionary).get("path", "")), "smoke.aap", "工程路径")
		ctx.eq(String((projects[0] as Dictionary).get("name", "")), "QA-Smoke",
				"工程显示名取 .aap 里的 ProjectName")
	ctx.eq(ar.get_saves().size(), 0, "get_saves() 空")

	# ---------------------------------------------------------------- 3. 覆盖优先级：本地 > overrides > pack
	var project_path := TMP_ROOT.path_join("projects/smoke.aap")
	var ctx_all = ar.make_context(project_path)
	ctx.not_null(ctx_all, "make_context(project_path) 非空")
	if ctx_all != null:
		ctx.eq(String(ctx_all.get("data_root")), TMP_ROOT, "context.data_root")
		var kinds: Array = []
		for layer in ctx_all.get_layers():
			kinds.append(String((layer as Dictionary).get("kind", "")))
		ctx.is_true("pack" in kinds, "层里有 pack")
		ctx.is_true("global" in kinds, "层里有全局 overrides")
		ctx.is_true("project" in kinds, "层里有工程本地目录")
		_assert_bg_color(ctx, ctx_all, "synth_bg", PROJECT_BLUE, "三层齐全时应取 project_local（蓝）")
		var bg_by_id = ctx_all.get_bg_by_id(AaHash.bg_id("synth_bg"))
		_assert_color(ctx, bg_by_id, PROJECT_BLUE, "get_bg_by_id(xxh32(synth_bg)) 也是最高优先级（蓝）")

	var ctx_no_project = ar.make_context("")
	_assert_bg_color(ctx, ctx_no_project, "synth_bg", OVERRIDES_GREEN, "无工程目录时应取 overrides（绿）")

	# 删掉整个 overrides 目录 → 只剩 pack（红）
	_rmtree(TMP_ROOT.path_join("overrides"))
	var ctx_pack_only = ar.make_context("")
	_assert_bg_color(ctx, ctx_pack_only, "synth_bg", PACK_RED, "删掉 overrides 后应取 pack（红）")

	# Q-005（已修复）：只删 overrides 里的文件、但 manifest 仍登记该相对路径时，
	# 局部层不应注册 path="" 的空条目，get_bg 必须回退到低优先级 pack 的同名背景（红）。
	_copy_tree(OVERRIDES_DIR, TMP_ROOT.path_join("overrides"))
	_remove_file(TMP_ROOT.path_join("overrides/bgs/synth_bg.png"))
	var ctx_stale = ar.make_context("")
	_assert_bg_color(ctx, ctx_stale, "synth_bg", PACK_RED,
			"manifest 登记的 overrides 文件被删后回退 pack（Q-005 已修复）")
	ctx.not_null(ctx_stale.get_bg("synth_bg"), "回退到 pack 的背景非占位")
	ctx.is_false(_is_placeholder(ctx_stale.get_bg("synth_bg")), "回退结果不是占位图")
	# 恢复 overrides 完整夹具

	# 恢复 overrides → 又变回绿
	_copy_tree(OVERRIDES_DIR, TMP_ROOT.path_join("overrides"))
	var ctx_again = ar.make_context("")
	_assert_bg_color(ctx, ctx_again, "synth_bg", OVERRIDES_GREEN, "恢复 overrides 后重新变绿（上下文实时刷新）")

	# 备选背景（仅 pack 有）：按名查到
	_assert_bg_color(ctx, ctx_again, "synth_bg_alt", Color8(40, 40, 220), "pack 里的第二张背景可查（synth_bg_alt，蓝）")

	# ---------------------------------------------------------------- 4. 背景条目 / ID
	var bg_entries: Array = ctx_all.get_bg_entries()
	ctx.gt(bg_entries.size(), 0, "get_bg_entries() 非空")
	var found_bg := false
	for e in bg_entries:
		if String(e.get("name", "")).to_lower() == "synth_bg":
			found_bg = true
			ctx.eq(int(e.get("id", 0)), AaHash.bg_id("synth_bg"), "bg entry id == xxh32(synth_bg)")
	ctx.is_true(found_bg, "get_bg_entries 含 synth_bg")

	# ---------------------------------------------------------------- 5. 缺资源占位（绝不崩）
	ctx.is_null(ctx_all.get_bg(""), "get_bg(\"\") == null（AA「无背景」约定）")
	var missing_bg: Variant = ctx_all.get_bg("背景_不存在")
	ctx.not_null(missing_bg, "get_bg(不存在) 返回占位而非 null")
	ctx.is_true(_is_placeholder(missing_bg), "缺失背景带 aa_placeholder 标记")
	var missing_bg_id: Variant = ctx_all.get_bg_by_id(123456789)
	ctx.not_null(missing_bg_id, "get_bg_by_id(未知) 返回占位")
	ctx.is_true(_is_placeholder(missing_bg_id), "未知背景 ID 占位标记")
	ctx.is_null(ctx_all.get_sound(""), "get_sound(\"\") == null")
	ctx.not_null(ctx_all.get_sound("SE_不存在"), "get_sound(不存在) 返回静音占位")
	ctx.not_null(ctx_all.get_bgm("BGM_不存在"), "get_bgm(不存在) 返回静音占位")
	ctx.not_null(ctx_all.get_popup("popup_不存在"), "get_popup(不存在) 返回占位图")
	ctx.is_true(_is_placeholder(ctx_all.get_popup("popup_不存在")), "缺失弹出图带占位标记")
	var mute = ctx_all.get_bgm(999)
	ctx.not_null(mute, "get_bgm(999) 返回静音流（AA 约定，不是 null）")
	var missing_char: Variant = ctx_all.get_character("角色_不存在")
	ctx.not_null(missing_char, "get_character(不存在) 返回占位角色对象")
	if missing_char != null:
		ctx.is_true(bool(missing_char.get("is_placeholder")), "占位角色 is_placeholder")
		ctx.not_null(missing_char.get_face_texture(), "占位角色 get_face_texture() 不返回 null")
	ctx.gt(ctx_all.get_missing().size(), 0, "缺资源记录进 get_missing()")

	# ---------------------------------------------------------------- 6. 正常资源：pack 角色/音效/BGM/弹出图
	var hero: Variant = ctx_all.get_character("QA_HERO")
	ctx.not_null(hero, "get_character(QA_HERO) 从 pack 解析")
	if hero != null:
		ctx.eq(String(hero.get("identifier")), "QA_HERO", "角色 identifier")
		ctx.eq(String(hero.get("display_name")), "测试角色", "角色 display_name")
		ctx.eq(String(hero.get("mode")), "png", "角色 mode=png（合成包用 PNG 立绘）")
		ctx.is_false(bool(hero.get("is_placeholder")), "QA_HERO 不是占位")
		ctx.contains(hero.get("face_ids"), "00", "角色 face_ids 含 00")
		ctx.not_null(hero.get_face_texture("00"), "角色 00 表情贴图可加载")
		ctx.not_null(hero.get_small_portrait(), "角色头像可加载")
	var chars: Array = ctx_all.get_characters()
	ctx.gt(chars.size(), 0, "get_characters() 非空")
	var hero_listed := false
	for c in chars:
		if String(c.get("identifier")) == "QA_HERO":
			hero_listed = true
	ctx.is_true(hero_listed, "get_characters() 含 QA_HERO")

	ctx.not_null(ctx_all.get_sound("SE_QA_01"), "get_sound(SE_QA_01) 从 pack 解析")
	ctx.is_false(_is_placeholder(ctx_all.get_sound("SE_QA_01")), "SE_QA_01 不是占位")
	ctx.not_null(ctx_all.get_bgm("synth_bgm"), "get_bgm(synth_bgm) 从 pack 解析")
	ctx.not_null(ctx_all.get_popup("synth_popup"), "get_popup(synth_popup) 从 pack 解析")
	ctx.gt(ctx_all.get_bgm_entries().size(), 0, "get_bgm_entries() 非空")
	ctx.gt(ctx_all.get_sound_entries().size(), 0, "get_sound_entries() 非空")
	ctx.gt(ctx_all.get_popup_entries(false).size(), 0, "get_popup_entries() 非空")
	var char_entries: Array = ctx_all.get_characters()
	ctx.gt(char_entries.size(), 0, "角色条目非空（get_characters）")
	ctx.not_null(ctx_all.get_manifest(), "get_manifest() 非空")
	ctx.gt(ctx_all.get_manifest().bg_overrides.size() + ctx_all.get_manifest().character_overrides.size(),
			0, "合并 manifest 有覆盖项")
	ctx.not_null(ctx_all.get_bg_effect("不存在"), "get_bg_effect 缺资源不崩")

	# ---------------------------------------------------------------- 7. AaManifest 读写 / overlay
	var m_pack := AaManifest.load_from_file(PACK_DIR.path_join("manifest.json"))
	ctx.not_null(m_pack, "AaManifest.load_from_file(pack) 非空")
	if m_pack != null:
		ctx.eq(m_pack.character_overrides.size(), 1, "pack manifest 角色覆盖 1 条")
		ctx.eq(String((m_pack.character_overrides[0] as Dictionary).get("Identifier", "")), "QA_HERO",
				"manifest 角色 Identifier")
		ctx.eq(m_pack.bg_overrides.size(), 2, "pack manifest 背景覆盖 2 条")
		var tmp_manifest := TMP_ROOT.path_join("overrides/manifest_roundtrip.json")
		ctx.eq(m_pack.save_to_file(tmp_manifest), OK, "manifest.save_to_file OK")
		var m2 := AaManifest.load_from_file(tmp_manifest)
		ctx.not_null(m2, "manifest 重新载入")
		if m2 != null:
			ctx.eq_deep(m2.to_dict(), m_pack.to_dict(), "manifest round-trip 深度相等")
		var m_ov := AaManifest.load_from_file(OVERRIDES_DIR.path_join("manifest.json"))
		ctx.not_null(m_ov, "AaManifest.load_from_file(overrides)")
		if m_ov != null:
			var merged := m_pack.clone()
			merged.overlay(m_ov)
			ctx.gte(merged.bg_overrides.size(), 1, "manifest.overlay 后仍有背景覆盖")
			ctx.is_false(merged.is_empty(), "overlay 后非空")

	# ---------------------------------------------------------------- 8. zip 安装 / 卸载
	if ClassDB.class_exists("ZIPPacker"):
		_zip_dir(PACK_DIR, ZIP_PATH)
		ctx.is_true(FileAccess.file_exists(ZIP_PATH), "生成测试用 aa_pack.zip")
		ctx.eq(ar.uninstall_pack("synth_pack"), OK, "uninstall_pack(synth_pack) OK")
		ctx.eq(ar.get_packs().size(), 0, "卸载后 get_packs 为空")
		ctx.eq(ar.install_pack(ZIP_PATH), OK, "install_pack(.zip) OK（last_error=%s）" % String(ar.get("last_error")))
		ctx.eq(ar.get_packs().size(), 1, "zip 安装后 1 个包")
		var zpack: Variant = ar.get_pack("synth_pack")
		ctx.not_null(zpack, "get_pack(synth_pack) 非空")
		var zctx = ar.make_context("")
		_assert_bg_color(ctx, zctx, "synth_bg", OVERRIDES_GREEN, "zip 安装后 overrides 仍优先（绿）")
		ctx.eq(ar.uninstall_pack("synth_pack"), OK, "再次卸载 OK")


		# aa_pack 缺失时：只存在于 pack 的资源必须退化为占位（不崩、不返回 null）
		ctx.eq(ar.get_packs().size(), 0, "卸载后没有任何 aa_pack")
		var ctx_nopack = ar.make_context("")
		ctx.not_null(ctx_nopack, "无 pack 时 make_context 仍可用")
		var no_pack_bg: Variant = ctx_nopack.get_bg("synth_bg_alt")
		ctx.not_null(no_pack_bg, "aa_pack 缺失：仅 pack 有的背景返回占位而非 null")
		ctx.is_true(_is_placeholder(no_pack_bg), "aa_pack 缺失：背景占位带标记")
		var no_pack_char: Variant = ctx_nopack.get_character("QA_HERO")
		ctx.not_null(no_pack_char, "aa_pack 缺失：角色返回占位对象")
		ctx.is_true(bool(no_pack_char.get("is_placeholder")), "aa_pack 缺失：角色是占位")
		var no_pack_sound: Variant = ctx_nopack.get_sound("SE_QA_01")
		ctx.not_null(no_pack_sound, "aa_pack 缺失：音效返回静音占位")
		ctx.not_null(ctx_nopack.get_bgm("synth_bgm"), "aa_pack 缺失：BGM 返回静音占位")
		ctx.not_null(ctx_nopack.get_popup("synth_popup"), "aa_pack 缺失：弹出图返回占位")
	else:
		ctx.skip("引擎未提供 ZIPPacker，跳过 zip 安装测试")

	# ---------------------------------------------------------------- 9. 恢复 data_root
	ar.set_data_root(original_root)
	ctx.eq(String(ar.get("data_root")), original_root, "测试结束恢复原 data_root")
	_rmtree(TMP_ROOT)
	_remove_file(ZIP_PATH)


# ----------------------------------------------------------------------------
# 辅助
# ----------------------------------------------------------------------------

func _assert_bg_color(ctx: Fw.Ctx, res_ctx: Variant, bg_name: String, expected: Color, msg: String) -> void:
	var tex: Variant = res_ctx.get_bg(bg_name)
	_assert_color(ctx, tex, expected, msg)


func _assert_color(ctx: Fw.Ctx, tex: Variant, expected: Color, msg: String) -> void:
	ctx.not_null(tex, msg + "（纹理非空）")
	if tex == null:
		return
	var img: Image = (tex as Texture2D).get_image()
	ctx.not_null(img, msg + "（可取 Image）")
	if img == null:
		return
	var c := img.get_pixel(0, 0)
	ctx.almost_eq(c.r, expected.r, 0.02, msg + "（R 通道）")
	ctx.almost_eq(c.g, expected.g, 0.02, msg + "（G 通道）")
	ctx.almost_eq(c.b, expected.b, 0.02, msg + "（B 通道）")


func _is_placeholder(res: Variant) -> bool:
	return AaResContext.is_placeholder(res)


func _rmtree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if d.current_is_dir():
				_rmtree(full)
			else:
				DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var from := src.path_join(name)
			var to := dst.path_join(name)
			if d.current_is_dir():
				_copy_tree(from, to)
			else:
				_copy_file(from, to)
		name = d.get_next()
	d.list_dir_end()


func _copy_file(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 把目录打包成 zip（ZIPPacker），用于测 install_pack 的 zip 分支。
func _zip_dir(src_dir: String, zip_path: String) -> void:
	var zp := ZIPPacker.new()
	if zp.open(zip_path) != OK:
		return
	_zip_recurse(zp, src_dir, "")
	zp.close()


func _zip_recurse(zp: ZIPPacker, src_dir: String, prefix: String) -> void:
	var d := DirAccess.open(src_dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := src_dir.path_join(name)
			var rel := name if prefix.is_empty() else prefix.path_join(name)
			if d.current_is_dir():
				_zip_recurse(zp, full, rel)
			else:
				zp.start_file(rel)
				zp.write_file(FileAccess.get_file_as_bytes(full))
				zp.close_file()
		name = d.get_next()
	d.list_dir_end()
