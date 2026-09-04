class_name ToastStack
extends VBoxContainer
## Стек тостов HUD: узкие плашки у правого края, растут снизу вверх над
## приборной панелью. Владеет анимацией (Tween) и утилизацией панелей;
## порядок вытеснения по приоритету — в ToastQueue (чистая логика).

const ToastQueueScript = preload("res://ui/hud/toast_queue.gd")

const ANIM_IN := 0.22
const ANIM_OUT := 0.26

const PANEL_WIDTH := 280.0
const MARGIN_H := 12.0  # HudStyle.toast_style(): content_margin_left/right

var _queue: ToastQueueScript
var _nodes: Dictionary = {}  # int id -> {wrap: Control, panel: PanelContainer, tween: Tween}


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue = ToastQueueScript.new(3)


## text/level — level один из HudStyle.LEVEL_*; неизвестный трактуется как
## LEVEL_INFO и там же красится (HudStyle.level_color()).
func push_toast(text: String, level: StringName) -> void:
	var rank := HudStyle.level_rank(level)
	var result: Array = _queue.push(rank)
	var id: int = result[0]
	if id == -1:
		return  # переполнение более важными сообщениями — тост не показан

	var evicted_id: int = result[1]
	if evicted_id != -1 and _nodes.has(evicted_id):
		_evict(evicted_id)

	# wrap — обычный Control (не Container): VBoxContainer управляет его
	# position/size сам, а panel внутри свободен для Tween.position без
	# борьбы с раскладкой при пересортировке стека.
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.toast_style(level))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(panel)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Без явной ширины автоперенос меряет себя по ширине 0 (Label ещё нигде
	# не размещён) и заворачивает каждое слово на отдельную строку — панель
	# раздувается на сотни px. Ширина — единственное, что нужно задать
	# заранее: высоту после переноса TextServer посчитает сам.
	lbl.custom_minimum_size.x = PANEL_WIDTH - MARGIN_H * 2.0
	lbl.add_theme_font_size_override("font_size", HudStyle.level_font_size(level))
	lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	panel.add_child(lbl)

	# wrap не Container — не наследует размер panel сам; PanelContainer же
	# теперь считает свой минимум корректно благодаря ширине Label выше.
	var min_size := panel.get_combined_minimum_size()
	wrap.custom_minimum_size = min_size
	panel.size = min_size
	panel.position = Vector2(24.0, 0.0)
	panel.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, ANIM_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position:x", 0.0, ANIM_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(HudStyle.level_duration(level))
	tw.chain().tween_callback(func() -> void: _expire(id))

	_nodes[id] = {"wrap": wrap, "panel": panel, "tween": tw}


func _expire(id: int) -> void:
	if not _nodes.has(id):
		return
	_queue.remove(id)
	_fade_out_and_free(id)


func _evict(id: int) -> void:
	_fade_out_and_free(id)


func _fade_out_and_free(id: int) -> void:
	var entry: Dictionary = _nodes[id]
	_nodes.erase(id)
	var panel: PanelContainer = entry["panel"]
	var wrap: Control = entry["wrap"]
	var old_tween: Tween = entry["tween"]
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 0.0, ANIM_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "position:x", 16.0, ANIM_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(wrap.queue_free)
