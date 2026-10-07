extends Node2D
## ВЗРЫВ БАШНИ (TowerExplosion) — короткая анимация разрушения и разлёт кирпичей. Ни коллизий, ни
## физики у самого эффекта: только Sprite2D, который листает кадры, и обломки-кирпичи, которые
## живут обычной физикой (Debris.tscn).
##
## ЧТО ЭТО: Tower.destroy() в момент разрушения ставит этот узел в ЦЕНТР башни (центр её коллизии) и
## тут же забывает о нём. Дальше эффект живёт сам и сам себя удаляет, но перед удалением сообщает
## сигналом explosion_finished, что анимация отыграна: по этому сигналу башня прячет корпус и ставит
## за собой копьё (Tower._on_explosion_finished), то есть находка появляется ТОЛЬКО ПОСЛЕ взрыва.
##
## КАДРЫ: explosion_textures (tower_explosion1..5.png) показываются по порядку, по frame_duration
## секунд на кадр. На кадре с номером DEBRIS_FRAME_INDEX (третий) от центра летят кирпичи: первые
## debris_stay_count — настоящие обломки (слой 7 «обломки», маска «земля»: падают и остаются лежать
## там, куда упали), остальные ни с чем не сталкиваются (маска 0 — падают сквозь землю) и удаляются,
## уехав за экран (как обломки моба, см. MobDeathBurst.gd). После последнего кадра эффект висит ещё
## post_animation_delay секунд, шлёт explosion_finished и делает queue_free(). Массив кадров пустой —
## кадров нет, сигнал и удаление сразу.
##
## МАСШТАБ: корень всегда scale = ONE (то же правило, что у башни и пушки: размер живёт на дочернем
## узле, а не на корне). Кадры разрушения сжаты в файлах до ≈35% исходного рисунка, поэтому спрайт
## получает масштаб ArtScale.scale_of(FRAME_NATIVE_MULT, 1.0) — тот же мировой размер, что у башни.
## Кирпичи нарисованы 1:1, их масштаб — ArtScale.scale_of() с обоими множителями 1.0.
##
## Куда кладутся кирпичи: в текущую сцену (мир), а не в этот узел — иначе они уехали бы вместе с
## эффектом и исчезли бы вместе с ним. Сам узел TowerExplosion — разовая машина. class_name намеренно
## НЕ ставим (как у CannonFire) — тип берётся через preload.

## Анимация отыграна: по этому сигналу башня прячет корпус и ставит копьё
## (Tower._on_explosion_finished). Шлётся ровно один раз, за post_animation_delay до queue_free().
signal explosion_finished

## Отыгран ПЕРВЫЙ кадр: по этому сигналу башня прячет корпус (Tower._on_first_frame_shown),
## чтобы он был виден только под первым кадром взрыва. Следующие кадры идут уже без корпуса.
## Шлётся один раз — на переходе с кадра 0 на кадр 1 (в _ready подписаться нельзя: кадр 0
## ставится синхронно внутри add_child, ещё до того как башня успевает подключиться).
signal first_frame_shown

## Во сколько раз ИСХОДНЫЙ рисунок кадров больше файла в проекте: файлы сжаты до ≈35%
## (1125…1506 px вместо 3200…4300), то есть 3200/1125 ≈ 2.86 (см. docs/SETUP.md, раздел 16).
const FRAME_NATIVE_MULT := 2.86
## Номер кадра (с нуля), на котором от центра разлетаются кирпичи: третий кадр взрыва.
const DEBRIS_FRAME_INDEX := 2
## Разброс точки появления кирпича вокруг центра взрыва, мировые пиксели (в обе стороны по осям).
const DEBRIS_SPREAD_PX := 50.0

@export_group("Кадры")
## Кадры взрыва (tower_explosion1..5.png): показываются по порядку.
@export var explosion_textures: Array[Texture2D] = []
## Сколько секунд держится один кадр взрыва.
@export var frame_duration: float = 0.1
## Пауза после последнего кадра: столько эффект ещё виден, потом сигнал и queue_free().
@export var post_animation_delay: float = 0.1

@export_group("Кирпичи")
## Сколько всего кирпичей вылетает на кадре DEBRIS_FRAME_INDEX.
@export var debris_count: int = 12
## Сколько из них становятся настоящими обломками (падают на землю и остаются лежать). Остальные
## падают сквозь землю и исчезают, уехав за экран.
@export var debris_stay_count: int = 6
## Картинки кирпичей (brick.png / brick2.png / brick3.png): каждому обломку достаётся случайная.
@export var brick_textures: Array[Texture2D] = []
## Сцена одного обломка: RigidBody2D + Sprite2D + CollisionShape2D (см. Debris.tscn).
@export var debris_scene: PackedScene = preload("res://Debris.tscn")
## Масса кирпича (<= 0 — оставить как в сцене Debris.tscn).
@export var debris_mass: float = 1.0

@export_group("Разлёт кирпичей")
## Скорость кирпича, px/с: случайная из диапазона; направление — радиально от центра взрыва.
@export var speed_min: float = 260.0
@export var speed_max: float = 620.0
## Максимальный проворот кирпича, рад/с (случайный в обе стороны).
@export var spin_max: float = 9.0
## Насколько разлёт заворачивает вверх, градусы (0 — строго радиально наружу от центра).
@export var up_bias_deg: float = 25.0
## Случайный разброс направления, градусы (в обе стороны от радиали).
@export var spread_deg: float = 30.0

@export_group("Слои кирпичей")
## Слой оставшихся кирпичей: слой 7 «обломки» (значение 64) — как у Debris.tscn.
@export var debris_layer: int = 64
## Маска оставшихся кирпичей: 4 — только земля (как у Debris.tscn).
@export var debris_mask: int = 4

@onready var sprite: Sprite2D = $Sprite

## Сколько держится текущий кадр (секунды, обратный отсчёт).
var _timer: float = 0.0
## Номер показанного кадра (0 — первый).
var _index: int = 0
## Кадры отыграны: идёт пауза post_animation_delay, потом сигнал и удаление.
var _finished: bool = false
## Сколько прошло с начала паузы после анимации.
var _post_time: float = 0.0
## Сколько пауза должна длиться (post_animation_delay на момент окончания анимации).
var _post_delay: float = 0.0


func _ready() -> void:
	# Размер живёт на спрайте, а не на корне: кадры сжаты в файлах до ≈35% исходного рисунка.
	sprite.scale = Vector2.ONE * ArtScale.scale_of(FRAME_NATIVE_MULT, 1.0)
	if explosion_textures.is_empty():
		# Кадров нет — анимации нет. Сигнал шлём НЕ здесь (его ещё некому слушать: башня
		# подписывается сразу после add_child), а первым же _process.
		_finish()
		return
	_set_frame(0)
	_timer = maxf(frame_duration, 0.0001)


func _process(delta: float) -> void:
	# ---- ПАУЗА ПОСЛЕ АНИМАЦИИ: ждём, потом сигнал и удаление.
	if _finished:
		_post_time += delta
		if _post_time >= _post_delay:
			explosion_finished.emit()
			queue_free()
		return
	# ---- КАДРЫ
	_timer -= delta
	if _timer > 0.0:
		return
	_index += 1
	if _index >= explosion_textures.size():
		_finish()
		return
	_set_frame(_index)
	# Первый кадр отработан: башня гасит корпус (он виден только под первым кадром взрыва).
	# Номер растёт на 1, поэтому срабатывает ровно один раз — на переходе 0 → 1.
	if _index == 1:
		first_frame_shown.emit()
	# Кирпичи летят ровно на одном кадре: дальше номер только растёт, повторно не сработает.
	if _index == DEBRIS_FRAME_INDEX:
		_spawn_debris()
	_timer = maxf(frame_duration, 0.0001)


## Показать кадр по номеру: картинка кадра (размер файла у кадров может отличаться).
func _set_frame(index: int) -> void:
	if index < 0 or index >= explosion_textures.size():
		return
	sprite.texture = explosion_textures[index]


## Кадры отыграли: вместо мгновенного удаления ждём post_animation_delay (последний кадр ещё виден),
## а потом один раз шлём explosion_finished и уходим.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_post_time = 0.0
	_post_delay = maxf(post_animation_delay, 0.0)


# ============================================================================
# КИРПИЧИ
# ============================================================================
## Разлёт кирпичей от центра взрыва: debris_stay_count настоящих обломков и остальные «сквозь землю».
func _spawn_debris() -> void:
	var parent := _debris_parent()
	if parent == null or debris_scene == null or brick_textures.is_empty():
		return
	var k := ArtScale.scale_of()
	for i in maxi(debris_count, 0):
		_spawn_brick(parent, k, i < debris_stay_count)


## Один кирпич: спрайт и форма — по картинке в масштабе арта, в мире Debris.tscn. stay — настоящий
## обломок (слой 7, падает на землю) или падающий сквозь землю (маска 0 + удаление за экраном).
func _spawn_brick(parent: Node, k: float, stay: bool) -> void:
	var brick := debris_scene.instantiate() as RigidBody2D
	if brick == null:
		push_warning("TowerExplosion: сцена обломка %s — не RigidBody2D" % debris_scene.resource_path)
		return
	var tex: Texture2D = brick_textures[randi() % brick_textures.size()]
	brick.collision_layer = debris_layer
	brick.collision_mask = debris_mask if stay else 0
	if debris_mass > 0.0:
		brick.mass = debris_mass
	var size := tex.get_size() * k
	# Заглушка-спрайт из Debris.tscn нарисована от левого верхнего угла и без картинки: ставим её
	# центром картинки на начало координат — тогда проворот идёт вокруг центра кирпича.
	var brick_sprite := brick.get_node_or_null("Sprite") as Sprite2D
	if brick_sprite != null:
		brick_sprite.texture = tex
		brick_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		brick_sprite.centered = true
		brick_sprite.offset = Vector2.ZERO
		brick_sprite.scale = Vector2(k, k)
	# Коллизия — прямоугольник по картинке, размерами в МИРОВЫХ пикселях (у обломка корень без масштаба).
	var collider := brick.get_node_or_null("Collider") as CollisionShape2D
	if collider != null:
		var rect := RectangleShape2D.new()
		rect.size = size.max(Vector2.ONE)   # нулевого габарита не бывает
		collider.shape = rect
		collider.position = Vector2.ZERO

	parent.add_child(brick)
	var at := global_position + Vector2(
		randf_range(-DEBRIS_SPREAD_PX, DEBRIS_SPREAD_PX),
		randf_range(-DEBRIS_SPREAD_PX, DEBRIS_SPREAD_PX)
	)
	brick.global_position = at
	# Кирпич, падающий сквозь землю, нигде не нужен: уехал за экран — удаляем (как обломки моба).
	if not stay:
		var notifier := VisibleOnScreenNotifier2D.new()
		notifier.name = "ScreenExit"
		notifier.rect = Rect2(-size * 0.5, size)
		brick.add_child(notifier)
		notifier.screen_exited.connect(brick.queue_free)
	_push(brick, at)


## Импульс кирпича: наружу от центра взрыва, со случайным разбросом и лёгким заворотом вверх.
func _push(brick: RigidBody2D, at: Vector2) -> void:
	var direction := at - global_position
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized().rotated(deg_to_rad(randf_range(-spread_deg, spread_deg)))
	direction = direction.rotated(-deg_to_rad(up_bias_deg))   # ось Y смотрит вниз: минус — вверх
	brick.apply_central_impulse(direction * randf_range(speed_min, speed_max))
	if spin_max > 0.0:
		brick.angular_velocity = randf_range(-spin_max, spin_max)


## Кирпичи кладём в мир (текущая сцена): иначе они уехали бы вместе с эффектом и исчезли бы с ним.
func _debris_parent() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	return get_parent()
