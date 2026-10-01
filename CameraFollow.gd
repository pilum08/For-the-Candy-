extends Camera2D
## Камера уровня: держит героя НЕ по центру, а на заданной доле ширины экрана от
## левого края — справа остаётся место для волн мобов и головоломок (дизайн-док).
##
## Сдвиг кадра делается через offset — сам узел камеры в сцене двигать не нужно.
## Камера — ребёнок Player, position_smoothing мягко догоняет героя.
## Активная камера в сцене одна — эта.

@export_group("Кадрирование")
## Доля ширины экрана (0..1) от левого края, на которой стоит герой.
## 0.5 — было по центру, 0.25-0.30 — рабочее значение, чтобы справа был простор.
@export_range(0.05, 0.95, 0.01) var anchor_x: float = 0.28:
	set = _set_anchor_x
## Сглаживание движения камеры (мягко догоняет героя).
@export var smoothing_enabled: bool = true
## Скорость сглаживания: больше = жёстче привязка к герою.
@export var smoothing_speed: float = 8.0

@export_group("Границы мира")
## Левый предел, px: левее этого края камера не показывает (-2000 = край земли).
@export var left_limit: int = -2000


func _ready() -> void:
	position_smoothing_enabled = smoothing_enabled
	position_smoothing_speed = smoothing_speed
	limit_left = left_limit
	# Ширина экрана может меняться (растяжка окна) — тогда сдвиг пересчитываем.
	get_viewport().size_changed.connect(_update_offset)
	_update_offset()
	# Страховка: если на момент _ready() размер окна ещё не готов (ручная сборка сцены,
	# headless), пересчитываем сдвиг в конце кадра — тогда размер уже известен.
	call_deferred("_update_offset")


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Сдвиг кадра: положительный offset.x уводит вид вправо, герой остаётся слева.
## anchor_x = 0.28 при ширине 1152 px даёт offset.x = +0.22 * 1152 = 253 px.
func _update_offset() -> void:
	offset.x = (0.5 - anchor_x) * get_viewport_rect().size.x


func _set_anchor_x(value: float) -> void:
	anchor_x = value
	# В редакторе offset не трогаем, чтобы не «пачкать» сцену; в игре — применяем сразу.
	if is_inside_tree() and not Engine.is_editor_hint():
		_update_offset()
