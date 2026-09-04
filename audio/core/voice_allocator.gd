class_name VoiceAllocator
extends RefCounted
## Бюджет одновременных голосов и кулдауны. Порт alloc()/free() (audiocore.js).
##
## budget_tag и cooldown_tag разделены нарочно, как в оригинале: `ped_hit` и
## `thud` делят один budget_tag=&"ped" (не более 3 одновременно), но у каждого
## свой cooldown_tag со своим интервалом. Пустой тег — соответствующее
## ограничение не действует (только общий потолок TOTAL_BUDGET).
##
## В оригинале голос освобождается по таймеру `releaseAfter(ms)`, не по
## реальному окончанию звука — «проще и надёжнее, чем считать onended по
## каждому из нескольких узлов». В Godot это не нужно: AudioDirector
## освобождает голос по сигналу `AudioStreamPlayer.finished`, что даже точнее.

## Порт AU_BUDGET (audiocore.js:6). total=28 — общий потолок одновременных SFX.
const TOTAL_BUDGET := 28
const BUDGET := {
	&"horn": 3, &"crash": 2, &"ped": 3, &"voice": 3, &"click": 4, &"siren": 2,
}
## Порт AU_COOLDOWN (audiocore.js:7), мс.
const COOLDOWN_MS := {
	&"horn": 140, &"crash": 80, &"ped_hit": 120, &"thud": 90, &"click": 40, &"step": 60,
}

var _voice_total := 0
var _voice_by_tag: Dictionary[StringName, int] = {}
var _last_play_ms: Dictionary[StringName, int] = {}


## Пытается занять голос. При успехе счётчики уже инкрементированы — вызывающий
## обязан вызвать release(budget_tag) по завершении звука (или сразу, если голос
## взять не удалось из-за нехватки пула — см. AudioDirector).
func try_alloc(budget_tag: StringName, cooldown_tag: StringName, now_ms: int) -> bool:
	if _voice_total >= TOTAL_BUDGET:
		return false
	if budget_tag != &"" and BUDGET.has(budget_tag):
		var used: int = _voice_by_tag.get(budget_tag, 0)
		if used >= int(BUDGET[budget_tag]):
			return false
	if cooldown_tag != &"" and COOLDOWN_MS.has(cooldown_tag):
		var last: int = _last_play_ms.get(cooldown_tag, -1000000)
		if now_ms - last < int(COOLDOWN_MS[cooldown_tag]):
			return false
		_last_play_ms[cooldown_tag] = now_ms
	_voice_total += 1
	if budget_tag != &"":
		_voice_by_tag[budget_tag] = int(_voice_by_tag.get(budget_tag, 0)) + 1
	return true


## Не называем free() — на Object это зарезервированное имя без аргументов.
func release(budget_tag: StringName) -> void:
	_voice_total = maxi(0, _voice_total - 1)
	if budget_tag != &"":
		_voice_by_tag[budget_tag] = maxi(0, int(_voice_by_tag.get(budget_tag, 0)) - 1)


func voice_total() -> int:
	return _voice_total


func voice_count(budget_tag: StringName) -> int:
	return int(_voice_by_tag.get(budget_tag, 0))
