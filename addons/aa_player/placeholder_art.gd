class_name AaArt
extends RefCounted
## 程序化占位素材 & 全局字体缓存。
## 没有官方资源包是常态：背景/立绘/弹出图/音效缺失时全部用这里生成的占位素材，
## 保证任何 .aap 都能正常演出、不崩溃。

const FONT_PATH := "res://assets/fonts/wqy-zenhei-extracted.ttf"
const CHAR_TEX_SIZE := Vector2i(256, 420)

static var _font: Font = null
static var _tex_cache: Dictionary = {}
static var _audio_cache: Dictionary = {}


static func ui_font() -> Font:
	if _font == null:
		_font = AaRawLoader.load_font(FONT_PATH)
	return _font


static func seed_of(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = (h ^ text.unicode_at(i)) * 16777619
	return h & 0x7FFFFFFF


static func color_from_seed(seed: int, sat := 0.34, val := 0.86) -> Color:
	var hue := float(seed % 360) / 360.0
	return Color.from_hsv(hue, sat, val, 1.0)


## 背景占位：竖向渐变 + 天际带 + 地面带，足以区分不同背景。
static func bg_texture(seed: int) -> Texture2D:
	var key := "bg:%d" % seed
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 96
	var h := 54
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c1 := color_from_seed(seed, 0.42, 0.62)
	var c2 := color_from_seed(seed * 7 + 13, 0.30, 0.20)
	for y in h:
		var t := float(y) / float(h - 1)
		var col := c1.lerp(c2, t)
		img.fill_rect(Rect2i(0, y, w, 1), col)
	# 天际线/地平线
	var horizon := int(h * 0.62)
	img.fill_rect(Rect2i(0, horizon, w, 1), c1.lightened(0.35))
	# 几个随机远景块
	for i in 6:
		var s := (seed >> (i * 3)) & 0xFF
		var bw := 4 + s % 14
		var bh := 3 + (s >> 3) % 12
		var bx := (s * 11 + i * 17) % (w - bw)
		img.fill_rect(Rect2i(bx, horizon - bh, bw, bh), c2.darkened(0.15 + 0.03 * i))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 角色占位剪影：半透明人形 + 头部，不同角色不同色调。
static func character_texture(seed: int) -> Texture2D:
	var key := "char:%d" % seed
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := CHAR_TEX_SIZE.x
	var h := CHAR_TEX_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := color_from_seed(seed, 0.30, 0.88)
	var body := Color(base.r * 0.85, base.g * 0.85, base.b * 0.85, 0.92)
	var body_dark := Color(base.darkened(0.35).r, base.darkened(0.35).g, base.darkened(0.35).b, 0.92)
	var head_col := Color(base.lightened(0.22).r, base.lightened(0.22).g, base.lightened(0.22).b, 0.95)
	# 身体（肩宽 -> 下摆）
	var top_y := 168
	var bot_y := h
	for y in range(top_y, bot_y):
		var t := float(y - top_y) / float(bot_y - top_y)
		var half := int(lerpf(62.0, 120.0, pow(t, 0.7)))
		var col := body.lerp(body_dark, t * 0.7)
		img.fill_rect(Rect2i(w / 2 - half, y, half * 2, 1), col)
	# 脖子
	img.fill_rect(Rect2i(w / 2 - 16, 148, 32, 32), body_dark)
	# 肩线高光，增强轮廓
	img.fill_rect(Rect2i(w / 2 - 64, top_y, 128, 4), Color(1, 1, 1, 0.18))
	# 头（椭圆逐行填充）
	var cx := w / 2
	var cy := 96
	var rx := 50.0
	var ry := 64.0
	for y in range(int(cy - ry), int(cy + ry) + 1):
		var dy := (float(y) - cy) / ry
		var dx := 1.0 - dy * dy
		if dx <= 0.0:
			continue
		var half := int(rx * sqrt(dx))
		var col := head_col
		if y < cy - 18:
			# 头发/顶部：用更深一点的色带，让人形更易辨认
			col = Color(base.darkened(0.45).r, base.darkened(0.45).g, base.darkened(0.45).b, 0.95)
		img.fill_rect(Rect2i(cx - half, y, half * 2, 1), col)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 弹出图片占位：带边框的圆角矩形。
static func popup_texture(seed: int) -> Texture2D:
	var key := "popup:%d" % seed
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 200
	var h := 260
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := color_from_seed(seed, 0.45, 0.82)
	col.a = 0.86
	img.fill_rect(Rect2i(8, 8, w - 16, h - 16), col)
	var border := Color(1, 1, 1, 0.9)
	img.fill_rect(Rect2i(8, 8, w - 16, 3), border)
	img.fill_rect(Rect2i(8, h - 11, w - 16, 3), border)
	img.fill_rect(Rect2i(8, 8, 3, h - 16), border)
	img.fill_rect(Rect2i(w - 11, 8, 3, h - 16), border)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 径向光线占位（背景效果 #bgEffect / 集中线之类）。
static func radial_texture(seed: int) -> Texture2D:
	var key := "radial:%d" % seed
	if _tex_cache.has(key):
		return _tex_cache[key]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size / 2.0, size / 2.0)
	var base := color_from_seed(seed, 0.6, 1.0)
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var d := p.distance_to(center)
			var ang := p.angle_to(center)
			var ray := 0.5 + 0.5 * sin(ang * 9.0)
			var a := clampf((1.0 - d / (size * 0.5)) * ray * 0.55, 0.0, 1.0)
			if a > 0.01:
				img.set_pixel(x, y, Color(base.r, base.g, base.b, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## AronaTouch 指纹特效占位：青色同心圆。
static func arona_texture() -> Texture2D:
	if _tex_cache.has("arona"):
		return _tex_cache["arona"]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center)
			var ring := absf(sin(d * 0.28))
			var a := clampf((1.0 - d / (size * 0.5)) * ring, 0.0, 1.0) * 0.9
			if a > 0.02:
				img.set_pixel(x, y, Color(0.35, 0.85, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["arona"] = tex
	return tex


## 合成短音效（WAV），用于动作/中弹等占位音。
static func beep(freq := 660.0, duration := 0.08, volume := 0.32) -> AudioStreamWAV:
	var key := "beep:%d:%.3f:%.2f" % [int(freq), duration, volume]
	if _audio_cache.has(key):
		return _audio_cache[key]
	var rate := 22050
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(maxi(count, 1))
		env = env * env
		var v := sin(TAU * freq * t) * env * volume
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	_audio_cache[key] = stream
	return stream


static func clear_cache() -> void:
	_tex_cache.clear()
	_audio_cache.clear()
