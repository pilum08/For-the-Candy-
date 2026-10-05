extends Node2D
## ВСПЫШКА ВЫСТРЕЛА ПУШКИ (CannonFire) — короткий визуальный эффект: вспышка из дула и дымок после
## выстрела. Ни коллизий, ни физики — только две картинки (Sprite2D), которые сменяют друг друга.
##
## ЧТО ЭТО: пушка (Cannon.gd) в момент выстрела ставит этот узел в мировую точку дула Body/Muzzle,
## отдаёт ему масштаб и зеркало и тут же забывает о нём. Дальше эффект живёт сам и сам себя
## удаляет, когда отыграет.
##
## КАДРЫ: вспышка — fire_textures (листается каждые fire_frame_duration секунд), затем по
## smoke_delay появляется дым — smoke_textures (каждые smoke_frame_duration). После последнего
## кадра дыма узел делает queue_free(). Массив пустой — соответствующий этап просто пропускается.
##
## МАСШТАБ И ЗЕРКАЛО: корень всегда scale = ONE (то же правило, что у пушки: размер живёт на
## дочернем узле, а не на корне). Масштаб и зеркало ставит setup() — сразу на оба спрайта Fire и
## Smoke. art_scale приходит от пушки как ArtScale.scale_of(native_mult, size_mult), поэтому размер
## эффекта повторяет размер пушки.

@export_group("Кадры")
## Кадры вспышки (cannon_fire_01.png): показываются по порядку, каждый fire_frame_duration секунд.
@export var fire_textures: Array[Texture2D] = []
## Кадры дыма (cannon_fire_02..03.png): показываются после задержки, каждый smoke_frame_duration.
@export var smoke_textures: Array[Texture2D] = []

@export_group("Тайминги")
## Сколько секунд держится один кадр вспышки.
@export var fire_frame_duration: float = 0.08
## Сколько секунд держится один кадр дыма.
@export var smoke_frame_duration: float = 0.12
## Через сколько секунд после начала вспышки появляется дым.
@export var smoke_delay: float = 0.16

@onready var fire: Sprite2D = $Fire
@onready var smoke: Sprite2D = $Smoke

## Сколько прошло с начала эффекта (для кадров вспышки и задержки дыма).
var _time: float = 0.0
## Дым уже начался (smoke_delay прошёл) — вспышка погашена.
var _smoke_started: bool = false


## Масштаб и зеркало эффекта ставит пушка при создании: art_scale — мировой масштаб
## (ArtScale.scale_of у пушки), mirror — true, если вспышка смотрит вправо (тогда отражаем по x).
func setup(art_scale: float, mirror: bool) -> void:
	var s := absf(art_scale)
	if s <= 0.0:
		s = 1.0
	var sc := Vector2(-s if mirror else s, s)
	fire.scale = sc
	smoke.scale = sc


func _ready() -> void:
	# Первый кадр вспышки показываем сразу, не дожидаясь _process. Нет вспышки — просто гасим спрайт.
	if not fire_textures.is_empty():
		fire.texture = fire_textures[0]
		fire.visible = true
	else:
		fire.visible = false


func _process(delta: float) -> void:
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
		queue_free()
		return
	var index := int((_time - smoke_delay) / maxf(smoke_frame_duration, 0.0001))
	if index >= smoke_textures.size():
		queue_free()
		return
	smoke.texture = smoke_textures[index]
	smoke.visible = true


## Кадр вспышки по текущему времени: каждый fire_frame_duration — следующий, дольше последнего не идём.
func _show_fire() -> void:
	if fire_textures.is_empty():
		return
	var index := clampi(int(_time / maxf(fire_frame_duration, 0.0001)), 0, fire_textures.size() - 1)
	fire.texture = fire_textures[index]
	fire.visible = true
