extends Node2D
## ВСПЫШКА ВЫСТРЕЛА ПУШКИ (CannonFire) — короткий визуальный эффект: вспышка из дула и дымок после
## выстрела. Ни коллизий, ни физики — только две картинки (Sprite2D), которые сменяют друг друга.
##
## ЧТО ЭТО: пушка (Cannon.gd) в момент выстрела ставит этот узел в мировую точку дула Body/Muzzle,
## отдаёт ему масштаб и зеркало и тут же забывает о нём. Дальше эффект живёт сам и сам себя удаляет,
## но перед удалением он сообщает сигналом animation_finished, что анимация отыграна: по этому
## сигналу пушка ломается (Cannon._on_fire_finished), то есть слом идёт ТОЛЬКО ПОСЛЕ вспышки и дыма.
##
## КАДРЫ: вспышка — fire_textures (листается по порядку), затем по smoke_delay появляется дым —
## smoke_textures (тоже по порядку). Длительность кадра берётся из fire_frame_durations /
## smoke_frame_durations (элемент на кадр), а если массив пуст — из плоских fire_frame_duration /
## smoke_frame_duration. Смещение кадра от точки дула — fire_offsets / smoke_offsets (пиксели арта,
## элемент на кадр; нет элемента — ноль). После последнего кадра дыма эффект висит ещё
## post_animation_delay секунд, шлёт animation_finished и делает queue_free(). Массив текстур
## пустой — этот этап пропускается; оба пусты — сигнал и удаление сразу.
##
## МАСШТАБ И ЗЕРКАЛО: корень всегда scale = ONE (то же правило, что у пушки: размер живёт на
## дочернем узле, а не на корне). Масштаб и зеркало ставит setup() — сразу на оба спрайта Fire и
## Smoke. art_scale приходит от пушки как ArtScale.scale_of(native_mult, size_mult), поэтому размер
## эффекта повторяет размер пушки. Смещения тоже умножаются на art_scale и зеркалятся по x: в
## пикселях арта они задаются для направления «влево», а при зеркале x меняет знак.

## Анимация отыграна: по этому сигналу пушка ломается (Cannon._on_fire_finished). Шлётся ровно один
## раз, за post_animation_delay до queue_free().
signal animation_finished

@export_group("Кадры")
## Кадры вспышки (cannon_fire_01.png): показываются по порядку.
@export var fire_textures: Array[Texture2D] = []
## Кадры дыма (cannon_fire_02..03.png): показываются после задержки, по порядку.
@export var smoke_textures: Array[Texture2D] = []

@export_group("Смещения")
## Смещение кадра вспышки от точки дула, ПИКСЕЛИ АРТА (элемент на кадр; нет элемента — ноль).
@export var fire_offsets: Array[Vector2] = []
## Смещение кадра дыма от точки дула, ПИКСЕЛИ АРТА (элемент на кадр; нет элемента — ноль).
@export var smoke_offsets: Array[Vector2] = []

@export_group("Тайминги")
## Сколько секунд держится один кадр вспышки (когда fire_frame_durations пуст).
@export var fire_frame_duration: float = 0.08
## Сколько секунд держится один кадр дыма (когда smoke_frame_durations пуст).
@export var smoke_frame_duration: float = 0.12
## Покадровые длительности вспышки, с (элемент на кадр). Пусто — берётся fire_frame_duration.
@export var fire_frame_durations: Array[float] = []
## Покадровые длительности дыма, с (элемент на кадр). Пусто — берётся smoke_frame_duration.
@export var smoke_frame_durations: Array[float] = []
## Через сколько секунд после начала вспышки появляется дым.
@export var smoke_delay: float = 0.16
## Пауза после последнего кадра дыма: столько эффект ещё виден, потом сигнал и queue_free().
@export var post_animation_delay: float = 0.3

@onready var fire: Sprite2D = $Fire
@onready var smoke: Sprite2D = $Smoke

## Сколько прошло с начала эффекта (для кадров вспышки и задержки дыма).
var _time: float = 0.0
## Дым уже начался (smoke_delay прошёл) — вспышка погашена.
var _smoke_started: bool = false
## Анимация отыграна: кадры больше не листаем, идёт пауза post_animation_delay до сигнала.
var _finished: bool = false
## Сколько уже длится пауза после последнего кадра.
var _post_time: float = 0.0
## Сколько эта пауза должна длиться (снимок post_animation_delay в момент окончания анимации).
var _post_delay: float = 0.0
## Мировой масштаб эффекта (от пушки) — на него умножаются смещения кадров.
var _art_scale: float = 1.0
## Знак зеркала по x: -1 — эффект смотрит вправо (смещения x меняют знак), +1 — влево.
var _sign: float = 1.0


## Масштаб и зеркало эффекта ставит пушка при создании: art_scale — мировой масштаб
## (ArtScale.scale_of у пушки), mirror — true, если выстрел смотрит вправо (тогда отражаем по x).
func setup(art_scale: float, mirror: bool) -> void:
	var s := absf(art_scale)
	if s <= 0.0:
		s = 1.0
	_art_scale = s
	_sign = -1.0 if mirror else 1.0
	var sc := Vector2(-s if mirror else s, s)
	fire.scale = sc
	smoke.scale = sc
	# Кадр вспышки уже показан в _ready — переставляем его под новый масштаб и зеркало.
	if fire != null and not fire_textures.is_empty():
		_place(fire, fire_offsets, 0)


func _ready() -> void:
	# Первый кадр вспышки показываем сразу, не дожидаясь _process. Нет вспышки — гасим спрайт.
	if not fire_textures.is_empty():
		fire.texture = fire_textures[0]
		_place(fire, fire_offsets, 0)
		fire.visible = true
	else:
		fire.visible = false
	# Показывать вообще нечего — сразу переходим к окончанию (пауза + сигнал + удаление).
	if fire_textures.is_empty() and smoke_textures.is_empty():
		_finish()


func _process(delta: float) -> void:
	# ---- ПАУЗА ПОСЛЕ АНИМАЦИИ (post_animation_delay): ждём, потом сигнал и удаление.
	if _finished:
		_post_time += delta
		if _post_time >= _post_delay:
			animation_finished.emit()
			queue_free()
		return
	_time += delta
	# ---- ВСПЫШКА (до smoke_delay)
	if not _smoke_started:
		if _time < smoke_delay:
			_show_fire()
			return
		_smoke_started = true
		fire.visible = false
	# ---- ДЫМ (после smoke_delay)
	if smoke_textures.is_empty():
		_finish()
		return
	var index := _frame_index(
		_time - smoke_delay, smoke_frame_durations, smoke_frame_duration, smoke_textures.size()
	)
	if index >= smoke_textures.size():
		_finish()
		return
	smoke.texture = smoke_textures[index]
	_place(smoke, smoke_offsets, index)
	smoke.visible = true


## Кадр вспышки по текущему времени: дольше последнего кадра не идём.
func _show_fire() -> void:
	if fire_textures.is_empty():
		return
	var index := _frame_index(
		_time, fire_frame_durations, fire_frame_duration, fire_textures.size()
	)
	index = mini(index, fire_textures.size() - 1)
	fire.texture = fire_textures[index]
	_place(fire, fire_offsets, index)
	fire.visible = true


## Номер кадра по прошедшему времени: длительность каждого кадра берётся из массива durations, а
## где его нет — из плоской flat. Возвращает count, если все кадры уже отыграны (вызывающий по этому
## решает, что этап закончен).
func _frame_index(elapsed: float, durations: Array[float], flat: float, count: int) -> int:
	var acc := 0.0
	for i in count:
		var step: float = durations[i] if i < durations.size() else flat
		acc += maxf(step, 0.0001)
		if elapsed < acc:
			return i
	return count


## Смещение спрайта к кадру index: элемент offsets[index] (нет — ноль) задан в пикселях арта, поэтому
## умножаем на масштаб арта; x зеркалим по _sign (выстрел вправо).
func _place(sprite: Sprite2D, offsets: Array[Vector2], index: int) -> void:
	var o: Vector2 = offsets[index] if index >= 0 and index < offsets.size() else Vector2.ZERO
	sprite.position = Vector2(o.x * _sign, o.y) * _art_scale


## Анимация отыграла: вместо мгновенного удаления ждём post_animation_delay (последний кадр ещё
## виден), а потом один раз шлём animation_finished и уходим. Пустая пауза — сигнал и удаление сразу.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_post_time = 0.0
	_post_delay = maxf(post_animation_delay, 0.0)
	if _post_delay <= 0.0:
		animation_finished.emit()
		queue_free()
