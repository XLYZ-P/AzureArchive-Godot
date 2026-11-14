extends RefCounted
## xxHash32 实现（资源层内部使用，不注册 class_name）。
##
## AA 的 `bgName` = xxHash32(UTF-8(bgFriendlyName), seed=0)，见 docs/spec、
## research/halocue/docs__format.md。aa_core 的 `AaHash` 由 core-dev 提供；
## 资源层不想反向依赖未完成模块，所以这里保留一份同样算法的实现。
## 两者算法一致，调用方优先用 `AaHash`，资源层内部用本文件。
##
## 用法（其它脚本 preload）：
##   const ResHash = preload("res://addons/aa_resources/res_hash.gd")
##   ResHash.bg_id("BG_MainOffice")

const MASK := 0xFFFFFFFF
const P1 := 2654435761  # 0x9E3779B1
const P2 := 2246822519  # 0x85EBCA77
const P3 := 3266489917  # 0xC2B2AE3D
const P4 := 668265263   # 0x27D4EB2F
const P5 := 374761393   # 0x165667B1


static func _rotl(x: int, r: int) -> int:
	return ((x << r) | (x >> (32 - r))) & MASK


static func _round(acc: int, lane: int) -> int:
	return (_rotl((acc + lane * P2) & MASK, 13) * P1) & MASK


## 计算 xxHash32，返回 0..0xFFFFFFFF 的非负整数（AA 的 bgName 是 uint）。
static func xxh32(data: PackedByteArray, seed: int = 0) -> int:
	var n := data.size()
	var i := 0
	var h := 0
	if n >= 16:
		var v1 := (seed + P1 + P2) & MASK
		var v2 := (seed + P2) & MASK
		var v3 := seed & MASK
		var v4 := (seed - P1) & MASK
		while i <= n - 16:
			v1 = _round(v1, data.decode_u32(i))
			i += 4
			v2 = _round(v2, data.decode_u32(i))
			i += 4
			v3 = _round(v3, data.decode_u32(i))
			i += 4
			v4 = _round(v4, data.decode_u32(i))
			i += 4
		h = (_rotl(v1, 1) + _rotl(v2, 7) + _rotl(v3, 12) + _rotl(v4, 18)) & MASK
	else:
		h = (seed + P5) & MASK
	h = (h + n) & MASK
	while i <= n - 4:
		h = (_rotl((h + data.decode_u32(i) * P3) & MASK, 17) * P4) & MASK
		i += 4
	while i < n:
		h = (_rotl((h + data[i] * P5) & MASK, 11) * P1) & MASK
		i += 1
	h ^= (h >> 15)
	h = (h * P2) & MASK
	h ^= (h >> 13)
	h = (h * P3) & MASK
	h ^= (h >> 16)
	return h & MASK


static func xxh32_text(text: String, seed: int = 0) -> int:
	return xxh32(text.to_utf8_buffer(), seed)


## 背景友好名（如 "BG_MainOffice"）→ AA bgName。文件名 stem 直接传入。
static func bg_id(friendly_name: String) -> int:
	return xxh32_text(friendly_name, 0)
