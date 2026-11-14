class_name AaAutoPlay
extends RefCounted
## AUTO 自动播放与快进（Ctrl 按住）计时逻辑。
## AUTO 按台词长度/语音时长计算停留时间；快进则几乎立即推进。

var enabled := false
var fast_forward := false
var base_delay := 1.1        # 基础停留（秒）
var per_char_delay := 0.035  # 每字追加
var min_delay := 0.45
var max_delay := 8.0
var fast_delay := 0.06

var _elapsed := 0.0


func reset() -> void:
	_elapsed = 0.0


func is_active() -> bool:
	return enabled or fast_forward


func compute_delay(text_len: int, voice_length: float) -> float:
	if fast_forward:
		return fast_delay
	if voice_length > 0.3:
		return clampf(voice_length + 0.5, min_delay, max_delay + 30.0)
	return clampf(base_delay + float(text_len) * per_char_delay, min_delay, max_delay)


## 每帧调用。返回 true 表示可以推进到下一行。
func tick(delta: float, can_advance: bool, text_len: int, voice_length: float) -> bool:
	if not is_active() or not can_advance:
		_elapsed = 0.0
		return false
	_elapsed += delta
	if _elapsed >= compute_delay(text_len, voice_length):
		_elapsed = 0.0
		return true
	return false


func status_text() -> String:
	if fast_forward:
		return "快进中（按住 Ctrl / ▶▶）"
	if enabled:
		return "AUTO 开启（A 关闭）"
	return ""
