class_name PitSection
extends Node2D
## СЕКЦИЯ ЯМЫ — одна ячейка. Pit.gd создаёт их section_count штук в ряд (PitSection.tscn).
##
## Начало координат секции — УРОВЕНЬ ПОЛА у её ЛЕВОЙ стенки: X от 0 (левый край ячейки) до
## section_width (правый), Y от 0 (пол) вниз до pit_depth (дно ямы). Все числа ниже — в этих
## локальных координатах, поэтому при переносе ямы в другое место они не меняются.
##
## Что внутри:
##   DeathZone (Area2D, маска 1, скрипт SpikeZone.gd) — смерть: ПОЛОСА ШИПОВ у дна ячейки
##     (во всю ширину секции, высотой spike_kill_height). Пока секция ПУСТА и пол выключен,
##     герой падает через всю глубину ямы и умирает, только дойдя до шипов, — падение видно.
##     Секция заполнилась — зона гаснет (monitoring = false), и по ней можно ходить.
##   CatchZone (Area2D, маска 16 — слой 5 «тела») — ловит трупы из группы "corpses": труп
##     ЗАПОЛНЯЕТ секцию, если он остановился в ней (см. ниже) и секция пуста.
##   Floor (StaticBody2D, слой 4 «земля») — пол ячейки ровно на уровне пола. В сцене ВЫКЛЮЧЕН
##     (Shape.disabled = true): пока секция пуста, трупы падают на дно ямы (узел Bottom в Pit).
##
## ЗАПОЛНЕНИЕ: труп считается упавшим в секцию, если его ЦЕНТР внутри ячейки (X в пределах
## секции, Y ниже уровня пола), он почти не двигается settle_time секунд (скорость ниже
## settle_speed; страховка — settle_timeout) и секция пуста. Тогда тело queue_free(), а на его
## месте встаёт картинка "Fill" — Sprite2D без физики и коллизий и НЕ в группе "corpses"
## (лимит трупов такую картинку не считает). Секция эмитит filled(index), включает пол и гасит
## смерть: с этого момента она безопасна, а соседняя пустая — ещё нет.
##
## ЦЕНТР, А НЕ КОЛЛАЙДЕР: у трупа центр (пивот) — низ силуэта, поэтому труп, упавший на пол уже
## ЗАПОЛНЕННОЙ секции, лежит с центром на уровне пола и этой секции не принадлежит: он остаётся
## обычным физическим трупом (группа "corpses", его можно подобрать и бросить в другую секцию) —
## второй труп на ту же секцию её не меняет.
##
## КАРТИНКА "Fill": тот же арт, тот же offset (offset = −пивот, начало координат — низ силуэта)
## и ТОТ ЖЕ МАСШТАБ, что у трупа (у каждого вида моба свой art_scale — берём его у самого трупа):
## ничего не подгоняется под ячейку и не обрезается, поэтому картинка может налезть на соседние
## секции и торчать над краем ямы или не доставать до уровня пола — это допустимо. Низ силуэта —
## на дне ячейки (на bottom_overlap_px выше дна), центр по X — центр ячейки со сдвигом ±x_jitter,
## зеркало — как смотрел сам труп (его Visual.scale.x), плюс разброс ±tilt_jitter. Появляется рывком: 1–2 кадра
## светится белым (modulate > 1), твинов нет. z_index = −1: выше серого визуала шипов и дна ямы
## (в Pit.tscn узел SpikeZone идёт до Sections, поэтому при равном z картинка рисуется поверх),
## но ниже частей героя (z = 0).
##
## ГЕОМЕТРИЯ ПЕРЕСОБИРАЕТСЯ В КОДЕ (apply_layout): числа в PitSection.tscn — только для
## наглядности в редакторе (как CAPSULE_* в Corpse.gd), в игре размеры берутся из
## section_width / pit_depth, которые Pit выставляет ДО add_child.


## Слой 5 «тела» — обычный труп врага (Corpse.tscn: collision_layer = 16).
const CORPSE_LAYER: int = 16
## Группа трупов (Corpse.tscn: groups=["corpses"]). Картинка "Fill" в неё НЕ входит: это
## картинка, поэтому лимит трупов её не считает.
const CORPSE_GROUP: StringName = &"corpses"
## Цвет вспышки новорождённой картинки: каналы больше 1, то есть картинка вспыхивает белым.
const FLASH_COLOR := Color(4.0, 4.0, 4.0, 1.0)
## «Позади героя»: у лежащего трупа Corpse мировой z = −1 (corpse_world_z), у частей героя z = 0.
const CORPSE_Z_BEHIND: int = -1
## Толщина пола ячейки: вниз от уровня пола (верх пола ровно на уровне пола).
const FLOOR_THICKNESS: float = 40.0

@export_group("Ячейка")
## Номер секции по порядку (0 — левая). Задаёт Pit.
@export var index: int = 0
## Ширина ячейки в пикселях: Pit ставит pit_width / section_count.
@export var section_width: float = 170.0
## Глубина ямы от уровня пола до дна: Pit ставит свой pit_depth.
@export var pit_depth: float = 110.0

@export_group("Смерть")
## Высота смертельной полосы шипов у дна ячейки (px, от дна вверх), во всю ширину секции. Пока
## секция пуста, смерть ждёт героя только тут: он падает через всю глубину ямы и умирает на дне.
@export var spike_kill_height: float = 30.0

@export_group("Заполнение")
## Скорость (px/с), ниже которой труп в ячейке считается «лёг».
@export var settle_speed: float = 30.0
## Сколько секунд подряд труп должен пролежать в ячейке почти неподвижно, чтобы её заполнить.
@export var settle_time: float = 0.3
## Страховка: труп провалялся в ячейке столько секунд, так и не успокоившись (катится, дрожит
## на другом трупе). Истекло — ячейка всё равно заполняется.
@export var settle_timeout: float = 1.5
## На сколько пикселей низ картинки трупа выше дна ячейки (0 — ровно на дне).
@export var bottom_overlap_px: float = 6.0
## Разброс картинки по X от центра ячейки, ±px. Картинка не подгоняется под ячейку, поэтому при
## большом сдвиге труп налезет на соседнюю секцию — это допустимо (см. шапку файла).
@export var x_jitter: float = 8.0
## Разброс наклона картинки, ±градусы. 0 — строго плоско.
@export_range(0.0, 45.0, 0.5) var tilt_jitter: float = 5.0

## Секция заполнена (index — её номер). Она безопасна для героя сразу после этого.
signal filled(index: int)

enum State { EMPTY, FILLED }

## EMPTY — секция смертельна и ловит трупы; FILLED — пол включён, смерть погашена.
var state: State = State.EMPTY

@onready var death_zone: Area2D = $DeathZone
@onready var death_shape: CollisionShape2D = $DeathZone/Shape
@onready var catch_zone: Area2D = $CatchZone
@onready var catch_shape: CollisionShape2D = $CatchZone/Shape
@onready var floor_shape: CollisionShape2D = $Floor/Shape

## Труп → сколько секунд подряд он в ячейке почти не двигался.
var _calm: Dictionary = {}
## Труп → сколько секунд он торчит в ячейке (для страховки settle_timeout).
var _in_pit: Dictionary = {}
## Новорождённые картинки, которым ещё светиться белым: гасит _restore_flashes.
var _flashing: Array[Sprite2D] = []


func _ready() -> void:
	apply_layout()


## Разложить ячейку по размерам: смерть — полоса шипов у дна, ловля трупов — вся ячейка,
## пол — ровно на уровне пола. Зовётся в _ready (Pit выставляет section_width/pit_depth ДО
## add_child) и идемпотентен.
func apply_layout() -> void:
	# Смерть: только полоса шипов у дна (во всю ширину секции). Верх ячейки безопасен, поэтому
	# герой падает в пустую секцию по всей глубине и умирает уже на дне. Player.die() сам
	# защищён от повторного вызова, а вход в полосу зовёт его ровно один раз (SpikeZone.gd).
	var kill_h := clampf(spike_kill_height, 1.0, maxf(pit_depth, 1.0))
	death_shape.shape = _box(Vector2(section_width, kill_h))
	death_shape.position = Vector2(section_width * 0.5, pit_depth - kill_h * 0.5)
	catch_shape.shape = _box(Vector2(section_width, pit_depth))
	catch_shape.position = Vector2(section_width * 0.5, pit_depth * 0.5)
	# Пол: верх ровно на уровне пола, включается при заполнении.
	floor_shape.shape = _box(Vector2(section_width, FLOOR_THICKNESS))
	floor_shape.position = Vector2(section_width * 0.5, FLOOR_THICKNESS * 0.5)
	state = State.EMPTY
	floor_shape.disabled = true
	death_zone.monitoring = true
	catch_zone.monitoring = true


## Прямоугольник формы нужного размера. Формы собираются в коде: числа в PitSection.tscn —
## только для наглядности в редакторе (в игре правки формы в сцене затрутся при запуске).
func _box(size: Vector2) -> RectangleShape2D:
	var rect := RectangleShape2D.new()
	rect.size = size
	return rect


## Раз в кадр: погасить вспышку новой картинки и посмотреть, не остановился ли труп в ячейке.
## Секции, которая уже заполнена, тут делать нечего (кроме вспышки — она живёт 1–2 кадра).
func _physics_process(delta: float) -> void:
	_restore_flashes()
	if state != State.EMPTY:
		return
	var caught: RigidBody2D = null
	for body in catch_zone.get_overlapping_bodies():
		var corpse := body as RigidBody2D
		if not _owns(corpse):
			if corpse != null:
				_forget(corpse)
			continue
		_in_pit[corpse] = float(_in_pit.get(corpse, 0.0)) + delta
		if corpse.linear_velocity.length() <= settle_speed:
			_calm[corpse] = float(_calm.get(corpse, 0.0)) + delta
		else:
			_calm[corpse] = 0.0   # задел/толкнули — отсчёт покоя заново
		# Лёг и успокоился — или физике верить нельзя и истёк запасной settle_timeout.
		if float(_calm[corpse]) >= settle_time or float(_in_pit[corpse]) >= settle_timeout:
			caught = corpse
			break
	_drop_stale(caught)
	if caught != null:
		_fill(caught)


## Труп принадлежит этой ячейке? Центр трупа (пивот = низ силуэта) — внутри секции: X в
## [0, section_width), Y ниже уровня пола. Считаем по ЦЕНТРУ, а не по коллайдеру: труп, лежащий
## на полу уже заполненной секции (центр на уровне пола), сюда не попадает — он остаётся
## обычным телом. Диапазон по X полуоткрытый: центр на самой границе принадлежит только правой
## секции, иначе один труп заполнил бы сразу две.
func _owns(corpse: RigidBody2D) -> bool:
	if corpse == null or not is_instance_valid(corpse):
		return false
	if not corpse.is_in_group(CORPSE_GROUP) or corpse.collision_layer != CORPSE_LAYER:
		return false
	var local := to_local(corpse.global_position)
	return local.x >= 0.0 and local.x < section_width and local.y > 0.0


## Выбросить из счётчиков тела, которых в ячейке уже нет (труп уехал, его подобрали, он удалён).
## keep — труп, который заполняет секцию прямо сейчас: его трогать нельзя.
func _drop_stale(keep: RigidBody2D) -> void:
	# keys() отдаёт копию списка, поэтому чистить словарь прямо в цикле безопасно.
	for body in _calm.keys():
		if body == keep:
			continue
		if is_instance_valid(body) and _owns(body as RigidBody2D):
			continue
		_forget(body)


## Забыть тело: оно не в ячейке (или уже учтено) — счётчики покоя и времени сбрасываются.
func _forget(body: Object) -> void:
	_calm.erase(body)
	_in_pit.erase(body)


## Очистить счётчики секции: заполнять в ней больше нечего.
func _forget_all() -> void:
	_calm.clear()
	_in_pit.clear()


## Труп остановился в ПУСТОЙ секции: тело уходит из мира, на его месте встаёт картинка,
## секция становится заполненной и безопасной (пол включается, смерть гаснет).
func _fill(corpse: RigidBody2D) -> void:
	_forget_all()
	# Страховка: труп мог оказаться в руках героя (слои погашены) — тогда его не трогаем.
	if corpse == null or not is_instance_valid(corpse) or corpse.collision_layer != CORPSE_LAYER:
		return
	state = State.FILLED
	_spawn_fill(corpse)
	corpse.queue_free()
	floor_shape.disabled = false      # пол ячейки: по секции можно идти
	death_zone.monitoring = false     # и она больше не смертельна
	catch_zone.monitoring = false     # ловить в заполненной секции нечего
	filled.emit(index)


## Картинка трупа в секции: Sprite2D ровно как сам труп — тот же арт, тот же offset (offset =
## −пивот, то есть начало координат картинки — низ силуэта) и тот же масштаб (art_scale моба,
## берём у самого трупа). Ничего не подгоняется под ячейку и не обрезается: картинка может
## налезть на соседние секции и торчать над краем ямы — так и задумано (см. шапку файла).
func _spawn_fill(corpse: RigidBody2D) -> void:
	var src := corpse.get_node_or_null("Visual/Sprite") as Sprite2D
	# Обычный масштаб трупа (мировой): у разных мобов разный art_scale, а поднятый и брошенный
	# труп носит свой масштаб в узле Visual — поэтому спрашиваем у картинки трупа, а не у Pit.
	# Зеркало в масштаб не попадает: global_scale знака не хранит, а зеркало берём ниже — у самого трупа.
	var art_scale := 1.0
	if src != null:
		art_scale = maxf(absf(src.global_scale.y), 0.001)
	var fill := Sprite2D.new()
	fill.name = "Fill"
	fill.centered = false
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if src != null:
		# Вид ровно как у трупа: тот же арт и тот же offset (начало координат — низ силуэта).
		fill.texture = src.texture
		fill.offset = src.offset
	# Направление взгляда берём у самого трупа: его узел Visual зеркалён по X (_mirror в Corpse.gd),
	# поэтому картинка смотрит туда же, куда смотрел труп, а не отзеркаливается случайно. Плюс
	# разброс наклона. Низ силуэта — на дне ячейки (на bottom_overlap_px выше дна), центр по X —
	# центр ячейки плюс случайный сдвиг.
	var mirror := 1.0
	var corpse_visual := corpse.get_node_or_null("Visual") as Node2D
	if corpse_visual != null and corpse_visual.scale.x < 0.0:
		mirror = -1.0
	fill.scale = Vector2(mirror * art_scale, art_scale)
	fill.rotation_degrees = randf_range(-tilt_jitter, tilt_jitter)
	fill.position = Vector2(section_width * 0.5 + randf_range(-x_jitter, x_jitter),
		pit_depth - bottom_overlap_px)
	fill.z_index = CORPSE_Z_BEHIND
	fill.modulate = FLASH_COLOR
	add_child(fill)
	_flashing.append(fill)


## Снять вспышку: modulate возвращается к обычному на следующем физическом кадре.
func _restore_flashes() -> void:
	for sprite in _flashing:
		if is_instance_valid(sprite):
			sprite.modulate = Color.WHITE
	_flashing.clear()

