extends RefCounted
## 占位素材工厂（内部脚本，不注册 class_name，用 preload 使用）。
##
## 资源层契约：任何缺失资源都必须返回**可用的占位**，不能让播放器/编辑器崩溃。
##  - 背景缺失 → 渐变纹理（颜色由 key 的 xxHash32 确定，同一资源每次颜色一致）
##  - 角色缺失 → 半透明剪影纹理（名字首字/色带区分）
##  - 音频缺失 → 静音 AudioStreamWAV（可播放、可停止）
##  - 背景效果缺失 → 占位参数字典（由 AaResContext 组装）
##
## 本文件只用 Godot 内建 Image/ImageTexture/AudioStreamWAV，不依赖导入器。

const ResHash = preload("res://addons/aa_resources/res_hash.gd")

static var _texture_cache: Dictionary = {}
static var _silent_audio: AudioStream = null


static func clear_cache() -> void:
	_texture_cache.clear()
	_silent_audio = null


## 由任意 key 得到稳定的颜色（同 key 永远同色）。
static func color_for(key: String, saturation := 0.45, value := 0.65) -> Color:
	var h := float(ResHash.xxh32_text(key, 0) & 0xFF) / 255.0
	var s := float((ResHash.xxh32_text(key, 1) >> 8) & 0xFF) / 255.0
	var v := float((ResHash.xxh32_text(key, 2) >> 16) & 0xFF) / 255.0
	return Color.from_hsv(h, lerp(0.25, saturation + 0.15, s), lerp(0.45, value + 0.1, v), 1.0)


static func solid(size: Vector2i, color: Color) -> Texture2D:
	var key := "solid:%dx%d:%s" % [size.x, size.y, color.to_html()]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var w: int = maxi(1, size.x)
	var h: int = maxi(1, size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


## 纵向渐变。top/bottom 为两端颜色。
static func gradient(size: Vector2i, top: Color, bottom: Color) -> Texture2D:
	var key := "grad:%dx%d:%s:%s" % [size.x, size.y, top.to_html(), bottom.to_html()]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var w: int = maxi(1, size.x)
	var h: int = maxi(1, size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := 0.0 if h <= 1 else float(y) / float(h - 1)
		var c := top.lerp(bottom, t)
		for x in w:
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


## 缺失背景/弹出图占位：对角线渐变 + 中部暗色水纹，颜色由 key 决定。
static func bg_placeholder(key: String, size := Vector2i(480, 270)) -> Texture2D:
	var cache_key := "bg:%s:%dx%d" % [key, size.x, size.y]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var base := color_for(key, 0.35, 0.55)
	var dark := Color(base.r * 0.25, base.g * 0.25, base.b * 0.35, 1.0)
	var w: int = maxi(2, size.x)
	var h: int = maxi(2, size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		for x in w:
			var g := float(x) / float(w - 1)
			var c := base.lerp(dark, clampf(t * 0.85 + g * 0.15, 0.0, 1.0))
			# 斜向条纹，让占位图一眼可辨
			var stripe := float((x + y) % 64) / 64.0
			c = c.darkened(stripe * 0.12)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[cache_key] = tex
	return tex


## 缺失角色占位：半透明剪影（头 + 肩 + 身体），色带由角色名决定。
## size 默认 256x512，够预览用，生成快。
static func silhouette(key: String, size := Vector2i(256, 512)) -> Texture2D:
	var cache_key := "sil:%s:%dx%d" % [key, size.x, size.y]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var w: int = maxi(8, size.x)
	var h: int = maxi(16, size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tint := color_for(key, 0.5, 0.7)
	var body := Color(tint.r, tint.g, tint.b, 0.32)
	var edge := Color(tint.r, tint.g, tint.b, 0.55)
	var cx := float(w) * 0.5
	var head_cy := float(h) * 0.26
	var head_r := float(w) * 0.17
	var head_r2 := head_r * 1.12
	# 头
	for y in h:
		for x in w:
			var dx := (float(x) - cx) / head_r2
			var dy := (float(y) - head_cy) / (head_r * 1.18)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				img.set_pixel(x, y, body)
			# 躯干：梯形，肩宽 0.72w，下摆 0.9w
			var torso_top := head_cy + head_r * 1.25
			if float(y) >= torso_top:
				var tt := (float(y) - torso_top) / (float(h) - torso_top)
				var half_w := lerpf(float(w) * 0.36, float(w) * 0.45, tt)
				if absf(float(x) - cx) <= half_w:
					img.set_pixel(x, y, body)
					if absf(absf(float(x) - cx) - half_w) < 1.5 or float(y) < torso_top + 2.0:
						img.set_pixel(x, y, edge)
	# 底部色带
	var band_y := int(float(h) * 0.92)
	for y in range(band_y, h):
		for x in w:
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, 0.18))
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[cache_key] = tex
	return tex


## 静音流占位：16-bit / 22050Hz / 单声道，100ms。可播放、可 stop，不会崩。
static func silent_audio() -> AudioStream:
	if _silent_audio != null:
		return _silent_audio
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = _silent_pcm(100)
	_silent_audio = stream
	return _silent_audio


static func _silent_pcm(ms: int) -> PackedByteArray:
	var frames: int = maxi(16, int(22050.0 * float(ms) / 1000.0))
	var data := PackedByteArray()
	data.resize(frames * 2)  # 16-bit mono
	return data


## 标记一个资源是占位（播放器/编辑器可据此显示提示）。
static func mark_placeholder(res: Variant, key: String) -> Variant:
	if res is Object and res != null:
		var obj := res as Object
		obj.set_meta("aa_placeholder", true)
		obj.set_meta("aa_placeholder_key", key)
	return res
