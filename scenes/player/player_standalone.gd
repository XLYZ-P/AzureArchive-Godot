extends Control
## 独立播放入口（双击 .aap 直接播放用）：
##   直接运行 scenes/player/player_standalone.tscn 会播放 fixtures/aap/sample_kei_01.aap。
## 若通过命令行 `--` 传入了 .aap 路径，则优先播放该文件。

const DEFAULT_AAP := "res://fixtures/aap/sample_kei_01.aap"
const PLAYER_SCENE := "res://scenes/player/Player.tscn"

var player: AaPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#070b12")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	player = load(PLAYER_SCENE).instantiate()
	add_child(player)
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.request_exit.connect(_on_request_exit)
	player.finished.connect(_on_finished)
	var path := _resolve_path()
	if FileAccess.file_exists(path):
		player.setup_from_path(path)
	else:
		print("[player_standalone] 找不到 .aap: ", path, "，使用合成演示剧本")
		player.setup(AaAapMock.demo_data())
	player.set_instant_mode(false)
	player.play()


func _resolve_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".aap"):
			return arg
	var globalized := DEFAULT_AAP
	return globalized


func _on_request_exit() -> void:
	get_tree().quit()


func _on_finished() -> void:
	print("[player_standalone] 播放结束")
