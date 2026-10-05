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

@export_group("Тряска")
## Тряска камеры (Cannon.shake после выстрела): выключено — shake() ничего не делает.
@export var shake_enabled: bool = true

## Сколько секунд тряска ещё идёт (0 — не трясёт).
var _shake_time: float = 0.0
## Размах тряски, px (задан в shake()).
var _shake_intensity: float = 0.0
## Кадрирующий offset.x (без тряски) — тряска добавляется поверх него, по окончании возвращаем его.
var _framing_x: float = 0.0


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
	_framing_x = (0.5 - anchor_x) * get_viewport_rect().size.x
	# Во время тряски offset трогает _process — пока не тронем (иначе сбило бы кадр).
	if _shake_time <= 0.0:
		offset.x = _framing_x


## Тряска камеры: intensity — размах смещения, px; duration — сколько секунд держится.
## Смещение кладётся в offset (там же, где кадрирование) — узел камеры в сцене не двигаем.
func shake(intensity: float, duration: float) -> void:
	if not shake_enabled or intensity <= 0.0 or duration <= 0.0:
		return
	_shake_intensity = intensity
	_shake_time = duration


## Пока идёт тряска — каждый кадр случайное смещение поверх кадра; по окончании — возврат кадра.
func _process(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time = maxf(_shake_time - delta, 0.0)
	if _shake_time <= 0.0:
		offset = Vector2(_framing_x, 0.0)
		return
	offset = Vector2(
		_framing_x + randf_range(-_shake_intensity, _shake_intensity),
		randf_range(-_shake_intensity, _shake_intensity)
	)


func _set_anchor_x(value: float) -> void:
	anchor_x = value
	# В редакторе offset не трогаем, чтобы не «пачкать» сцену; в игре — применяем сразу.
	if is_inside_tree() and not Engine.is_editor_hint():
		_update_offset()
