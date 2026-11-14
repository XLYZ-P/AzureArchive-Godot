class_name AaAudioBus
extends Node
## BGM / SE / Voice 三条音轨（AudioStreamPlayer 池）。
## - BGM：循环播放、切歌淡入淡出，`bgmId == 999` = 静音（淡出停止）。
## - SE：多播放器池，支持并发。
## - Voice：单轨，新语音打断旧语音；语音缺失时静默不出错。

const SE_POOL_SIZE := 6
const FADE_TIME := 0.6

var bgm_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var se_players: Array[AudioStreamPlayer] = []

var current_bgm_key: Variant = null
var current_bgm_stream: AudioStream = null
var master_volume_db := 0.0

var _se_index := 0
var _built := false


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	bgm_player.volume_db = -6.0
	add_child(bgm_player)
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	voice_player.volume_db = 0.0
	add_child(voice_player)
	for i in SE_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SePlayer%d" % i
		p.volume_db = -8.0
		add_child(p)
		se_players.append(p)


## 设置背景音乐。key 为 .aap 的 bgmId（int）或名称；999 = 静音。
func set_bgm(stream: AudioStream, key: Variant = null) -> void:
	ensure_built()
	if key != null and current_bgm_key != null and str(current_bgm_key) == str(key) and current_bgm_stream != null:
		return
	if stream == null:
		# 资源缺失：记录 key 但保持静音（不打断现有？按 AA 语义：换歌失败则静音）
		current_bgm_key = key
		current_bgm_stream = null
		_fade_stop_bgm()
		return
	current_bgm_key = key
	current_bgm_stream = stream
	if not is_inside_tree() or get_tree() == null:
		return
	if bgm_player.stream == stream and bgm_player.playing:
		return
	_prepare_loop(stream)
	bgm_player.stream = stream
	bgm_player.play()
	if is_inside_tree():
		bgm_player.volume_db = -40.0
		var tw := create_tween()
		tw.tween_property(bgm_player, "volume_db", -6.0, FADE_TIME)
	else:
		bgm_player.volume_db = -6.0


func stop_bgm(fade := true) -> void:
	ensure_built()
	current_bgm_key = null
	current_bgm_stream = null
	if fade:
		_fade_stop_bgm()
	else:
		bgm_player.stop()


func _fade_stop_bgm() -> void:
	ensure_built()
	if not bgm_player.playing:
		return
	if not is_inside_tree():
		bgm_player.stop()
		return
	var tw := create_tween()
	tw.tween_property(bgm_player, "volume_db", -40.0, FADE_TIME)
	tw.tween_callback(bgm_player.stop)


func play_se(stream: AudioStream, volume_db := -8.0) -> void:
	ensure_built()
	if stream == null:
		return
	if not is_inside_tree() or get_tree() == null:
		return
	var p := se_players[_se_index % se_players.size()]
	_se_index += 1
	p.stream = stream
	p.volume_db = volume_db
	p.play()


## 占位音效（资源缺失时给动作/中弹一点听觉反馈；player 里可关闭）
func play_placeholder(kind: String) -> void:
	ensure_built()
	match kind:
		"jump":
			play_se(AaArt.beep(720.0, 0.07, 0.20), -14.0)
		"falldown", "fall":
			play_se(AaArt.beep(240.0, 0.12, 0.22), -14.0)
		"greeting":
			play_se(AaArt.beep(560.0, 0.06, 0.18), -16.0)
		"shot":
			play_se(AaArt.beep(150.0, 0.16, 0.30), -10.0)
		"click":
			play_se(AaArt.beep(880.0, 0.03, 0.12), -20.0)
		_:
			play_se(AaArt.beep(480.0, 0.05, 0.16), -18.0)


func play_voice(stream: AudioStream) -> void:
	ensure_built()
	stop_voice()
	if stream == null:
		return
	if not is_inside_tree() or get_tree() == null:
		return
	voice_player.stream = stream
	voice_player.volume_db = 0.0
	voice_player.play()


func stop_voice() -> void:
	ensure_built()
	if voice_player.playing:
		voice_player.stop()


func is_voice_playing() -> bool:
	return voice_player != null and voice_player.playing


func voice_length() -> float:
	if voice_player != null and voice_player.stream != null:
		return voice_player.stream.get_length()
	return 0.0


func stop_all() -> void:
	ensure_built()
	bgm_player.stop()
	voice_player.stop()
	for p in se_players:
		p.stop()


func _prepare_loop(stream: AudioStream) -> void:
	# Ogg/MP3 有 loop 属性；WAV/其他没有时忽略
	for pd in stream.get_property_list():
		if str(pd.get("name", "")) == "loop":
			stream.set("loop", true)
			return
