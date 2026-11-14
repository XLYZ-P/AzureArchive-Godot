extends RefCounted
## Fallback 版 PlayScript（只用于编辑器统计/预览兜底；core 就绪后用 core 的 PlayScript）。

var start_guid := ""
var nodes: Dictionary = {}
var node_count := 0
