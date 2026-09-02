class_name QuoteBank
extends Resource
## Пул реплик. Порт пулов из dialogues.js и peds.js.
## Строки хранятся как ключи локализации — раскрываются через tr() на показе.

@export var id: StringName = &""
@export var lines: PackedStringArray = PackedStringArray()


func is_empty() -> bool:
	return lines.is_empty()


func pick(rng: SeededRng) -> String:
	if lines.is_empty():
		return ""
	return lines[rng.randi_below(lines.size())]
