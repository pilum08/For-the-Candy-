extends Area2D
class_name WaveTrigger
## ТРИГГЕР УКРЕПЛЕНИЯ: герой доходит до укрепления — один раз запускаются волны
## (WaveManager.start()), и начинается оборона. Отдельная сцена WaveTrigger.tscn
## инстанцируется в уровень (main.tscn).
##
## ЧТО ДЕЛАЕТ ПРИ ПЕРВОМ ВХОДЕ ГЕРОЯ (за проход уровня — ровно один раз):
##   1) зовёт wave_manager.start();
##   2) если волны реально пошли (WaveManager.is_running: start() умеет выйти раньше —
##      пустой список волн или ненайденный спавнер, и тогда сигнала победы не будет вообще):
##      * lock_camera = true — запоминает прежнее Camera2D.limit_right и ставит новое ровно
##        по текущему ПРАВОМУ краю кадра: правее камера больше не поедет. Левее герой тоже
##        не уйдёт — его держит стена;
##      * поднимает невидимую стену слева: узел PlayersWall (StaticBody2D на слое «земля и
##        стены») переставляется к ЛЕВОМУ краю кадра — правой гранью коллизии ровно на кромку,
##        и включается (Shape.disabled = false). Вертикаль стены скрипт не трогает — её задаёт
##        узел в main.tscn;
##   3) на WaveManager.all_waves_cleared (в консоль «Победа» печатает сам менеджер) снимает
##      ограничение камеры и выключает стену. Больше ничего: попапов и перехода уровня нет.
##
## Совсем не трогать камеру — lock_camera = false (галка в инспекторе). Стена при этом всё
## равно ставится: она держит героя в арене до победы.
##
## СВЯЗИ (группа «Связи»): Wave Manager / Camera / Left Wall — перетащить узлы в поля.
## Пустое поле — ищем узел в группе ("wave_manager", "camera", "wave_wall") и пишем
## предупреждение: задать поле в инспекторе надёжнее.
##
## СЛОИ: зона на слое 0, маска 1 — видит только героя (слой «игрок»), как SpikeZone.
## Геометрия — узел Shape. Триггер намеренно невидим.

## Группа героя (Player.tscn: groups=["player"]).
const PLAYER_GROUP: StringName = &"player"
## Группы для поиска связей, если поля в инспекторе пустые (их ставит main.tscn).
const WAVE_MANAGER_GROUP: StringName = &"wave_manager"
const CAMERA_GROUP: StringName = &"camera"
const WALL_GROUP: StringName = &"wave_wall"

@export_group("Волны")
## true — пока волны идут, камера не едет правее, чем была в момент срабатывания
## (пишем Camera2D.limit_right и возвращаем прежнее значение на победе).
## false — камеру не трогаем совсем.
@export var lock_camera: bool = true

@export_group("Связи")
## Менеджер волн. Пусто — берём узел из группы "wave_manager".
@export var wave_manager: WaveManager
## Камера уровня (CameraFollow). Пусто — берём узел из группы "camera".
@export var camera: Camera2D
## Невидимая стена слева (в main.tscn это узел PlayersWall): сам StaticBody2D, а его
## CollisionShape2D должен называться Shape. Пусто — берём узел из группы "wave_wall".
@export var left_wall: StaticBody2D

## Уже сработал: запуск волн и блокировки — один раз за проход уровня.
var _fired := false
## Камера, с которой работаем (найдена в момент срабатывания).
var _cam: Camera2D = null
## Стена, с которой работаем (найдена в момент срабатывания).
var _wall: StaticBody2D = null
## Ограничение камеры поставлено (чтобы снять и вернуть ровно прежнее значение).
var _camera_locked := false
## Прежнее Camera2D.limit_right (по умолчанию 10000000 — то есть границы нет).
var _limit_right_saved := 0
## Стена поднята (чтобы на победе выключить только её).
var _wall_raised := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Герой вошёл в зону укрепления. Мобы и обломки игнорируются: по маске сюда попадает только
## герой, но проверка группы делает это явным.
func _on_body_entered(body: Node2D) -> void:
	if _fired:
		return
	if not body.is_in_group(PLAYER_GROUP):
		return
	var manager := _resolve_wave_manager()
	if manager == null:
		return
	_fired = true
	manager.start()
	# start() выходит раньше, если запускать нечего (пустые волны, нет спавнера) — тогда
	# сигнала победы не будет, и блокировать камеру со стеной нельзя: это ловушка навсегда.
	if not manager.is_running():
		push_warning("WaveTrigger: волны не запустились (см. предупреждение WaveManager) — камеру не блокирую и стену не ставлю.")
		return
	manager.all_waves_cleared.connect(_on_victory)
	_cam = _resolve_camera()
	_wall = _resolve_wall()
	_lock_camera()
	_raise_wall()


## Победа: снимаем ограничение камеры и стену. «Победа» в консоль печатает WaveManager.
func _on_victory() -> void:
	_release_camera()
	_lower_wall()


# ============================================================================
# КАМЕРА
# ============================================================================
## Заморозить правую границу кадра: limit_right = текущий правый край видимой области.
## Правая кромка = центр вида + половина видимой ширины — та же арифметика, что у MobSpawner
## в _spawn_point (get_screen_center_position + видимый прямоугольник, делённый на зум):
## именно поэтому точка спавна гарантированно остаётся за кадром.
func _lock_camera() -> void:
	if not lock_camera:
		return
	if _cam == null:
		return
	_limit_right_saved = _cam.limit_right
	var edge := _cam.get_screen_center_position().x + _visible_half().x
	_cam.limit_right = int(ceil(edge))
	_camera_locked = true


## Вернуть прежнюю границу кадра (на победе).
func _release_camera() -> void:
	if not _camera_locked:
		return
	if _cam == null:
		return
	_cam.limit_right = _limit_right_saved
	_camera_locked = false


# ============================================================================
# СТЕНА СЛЕВА
# ============================================================================
## Поставить невидимую стену по левому краю кадра и включить её. Левый край = центр вида минус
## половина видимой ширины. Правую грань коллизии кладём точно на кромку (из центра вычитаем
## полуширину формы), чтобы герой упирался в самый край, но оставался целиком в кадре.
## Нет камеры — стену не трогаем вовсе: поставить её наугад хуже, чем не ставить (можно
## запереть героя).
func _raise_wall() -> void:
	if _wall == null:
		return
	var shape := _wall.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		push_warning("WaveTrigger: у стены %s нет узла Shape (CollisionShape2D) — стену не ставлю." % _wall.name)
		return
	if _cam == null:
		push_warning("WaveTrigger: не нашёл камеру — не могу посчитать левый край экрана, стену не ставлю.")
		return
	var pos := _wall.global_position
	pos.x = _cam.get_screen_center_position().x - _visible_half().x - _shape_half_width(shape)
	_wall.global_position = pos
	shape.disabled = false
	_wall_raised = true


## Полуширина формы стены: центр узла надо сдвинуть левее на неё, чтобы ПРАВАЯ грань формы
## встала на нужную линию. Форма не прямоугольная (или пустая) — 0, ставим по центру узла.
func _shape_half_width(shape: CollisionShape2D) -> float:
	var rect := shape.shape as RectangleShape2D
	if rect == null:
		return 0.0
	return rect.size.x * 0.5


## Выключить стену на победе: узел остаётся на месте, просто перестаёт быть препятствием.
func _lower_wall() -> void:
	if not _wall_raised:
		return
	if _wall == null:
		return
	var shape := _wall.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		return
	shape.disabled = true
	_wall_raised = false


# ============================================================================
# РАЗМЕРЫ ВИДИМОЙ ОБЛАСТИ
# ============================================================================
## Половина видимой области в пикселях МИРА: видимый прямоугольник, делённый на зум камеры
## (формула скопирована у MobSpawner._visible_half — считать кромки экрана надо одинаково).
func _visible_half() -> Vector2:
	var visible := Vector2(get_viewport().get_visible_rect().size)
	var zoom := Vector2(maxf(_cam.zoom.x, 0.001), maxf(_cam.zoom.y, 0.001))
	return visible * 0.5 / zoom


# ============================================================================
# СВЯЗИ
# ============================================================================
## Менеджер волн: поле из инспектора, иначе узел из группы "wave_manager".
func _resolve_wave_manager() -> WaveManager:
	if wave_manager != null:
		return wave_manager
	var found := get_tree().get_first_node_in_group(WAVE_MANAGER_GROUP) as WaveManager
	if found == null:
		push_warning("WaveTrigger: не нашёл WaveManager (поле Wave Manager пусто, в группе wave_manager никого) — волны не запустятся.")
		return null
	push_warning("WaveTrigger: поле Wave Manager пусто — беру узел из группы wave_manager. Задать поле в инспекторе надёжнее.")
	return found


## Камера: поле из инспектора, иначе узел из группы "camera".
func _resolve_camera() -> Camera2D:
	if camera != null:
		return camera
	var found := get_tree().get_first_node_in_group(CAMERA_GROUP) as Camera2D
	if found == null:
		push_warning("WaveTrigger: не нашёл камеру (поле Camera пусто, в группе camera никого) — камеру не блокирую, стену не ставлю.")
		return null
	camera = found   # запоминаем находку: второй раз по группе уже не ищем
	push_warning("WaveTrigger: поле Camera пусто — беру камеру из группы camera. Задать поле в инспекторе надёжнее.")
	return found


## Стена: поле из инспектора, иначе узел из группы "wave_wall".
func _resolve_wall() -> StaticBody2D:
	if left_wall != null:
		return left_wall
	var found := get_tree().get_first_node_in_group(WALL_GROUP) as StaticBody2D
	if found == null:
		push_warning("WaveTrigger: не нашёл стену (поле Left Wall пусто, в группе wave_wall никого) — герой сможет уйти влево с арены.")
		return null
	left_wall = found   # запоминаем находку: второй раз по группе уже не ищем
	push_warning("WaveTrigger: поле Left Wall пусто — беру стену из группы wave_wall. Задать поле в инспекторе надёжнее.")
	return found
