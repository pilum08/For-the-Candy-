extends Area2D
## Снаряд — камень (Sprites/stone.bmp). Летит в сторону курсора от Muzzle по дуге,
## исчезает при попадании в стену/врага, по таймеру жизни и при выходе за экран.
## Слои: collision_layer = 4 (снаряды), collision_mask = 2|4... см. сцену
## (маска = враги (layer 2) + земля/стены (layer 3)).
## Попадание во врага: у цели вызывается take_hit(damage, direction) — урон берётся
## из data.damage, направление — вектор полёта (см. Enemy.gd). Враг — тело
## (CharacterBody2D), поэтому он приходит в _on_body_entered, а не в _on_area_entered.
##
## ЧИСЛА типа снаряда (текстура/скорость/гравитация/урон/время жизни) лежат в
## ProjectileData.gd (ресурс .tres), а поведение — здесь. Новый тип снаряда:
##   1) сохранить копию .tres и править числа/текстуру;
##   2) если нужно своё поведение при попадании — подкласс Projectile.gd с
##      переопределёнными _on_hit_enemy() / _on_hit_ground() / _on_expire().

## Испускается при любом попадании (в стену, во врага или по времени) — цель в аргументе.
signal hit_target(target: Node)

## Состояние снаряда. FLYING → один терминальный (после него снаряд исчезает).
enum State { FLYING, HIT_ENEMY, LANDED, EXPIRING }

# Тип ресурса данных (без class_name — как Rig.gd, чтобы не зависеть от кэша
# глобальных классов редактора в headless-прогоне).
const ProjectileData := preload("res://ProjectileData.gd")

@export_group("Данные")
## Тип снаряда: текстура, скорость, гравитация, урон, время жизни (см. ProjectileData.gd).
@export var data: ProjectileData

@export_group("Полёт")
## Доп. докрутка картинки, градусов в секунду (120 = камень «катится»).
@export var spin: float = 120.0
## Поворачивать снаряд по вектору скорости: rotation = velocity.angle() (учитывает дугу).
@export var face_velocity: bool = true

@export_group("Вид и попадание")
## Масштаб арта; игрок подставляет свой art_scale при спавне.
@export var art_scale: float = 0.35
## Доп. масштаб картинки камня.
@export var sprite_scale: float = 1.0
## Радиус попадания в пикселях арта (сам камень ~143 px в диаметре).
@export var hit_radius: float = 62.0

@onready var sprite: Sprite2D = $Sprite
@onready var notifier: VisibleOnScreenNotifier2D = $Notifier

var _state: State = State.FLYING
var _velocity := Vector2.ZERO
## Угол по вектору скорости (когда face_velocity) — spin докручивается поверх него.
var _base_rotation := 0.0
var _roll := 0.0
var _age := 0.0
var _was_on_screen := false


func _ready() -> void:
	if data == null:
		push_warning("Projectile (%s): не задан data (ProjectileData) — беру значения по умолчанию" % name)
		data = ProjectileData.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if data.texture != null:
		sprite.texture = data.texture
	sprite.scale = Vector2.ONE * (art_scale * sprite_scale)
	_add_hit_shape()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)


## Вызывается игроком сразу после спавна: единичный вектор направления полёта.
func launch(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	_base_rotation = dir.angle()
	_roll = 0.0
	# Стартовая скорость — точно на курсор, дальше её загибает гравитация (см. _physics_process).
	_velocity = dir.normalized() * data.speed
	if face_velocity:
		rotation = _base_rotation


func _physics_process(delta: float) -> void:
	if _state != State.FLYING:
		return
	# Дуга: гравитация добавляется каждый кадр, поэтому вектор скорости загибается вниз.
	_velocity.y += data.gravity * delta
	global_position += _velocity * delta

	# Картинка смотрит по вектору скорости (на дуге камень «заваливается» за полётом),
	# spin докручивает её поверх — получается катящийся камень.
	if face_velocity and _velocity.length_squared() > 0.0001:
		_base_rotation = _velocity.angle()
	_roll += deg_to_rad(spin) * delta
	rotation = _base_rotation + _roll

	_age += delta
	if _age >= data.lifetime and _finish(State.EXPIRING, null):
		_on_expire()


# ============================================================================
# ВИРТУАЛЬНЫЕ ХУКИ (переопределяются в подклассах нового типа снаряда)
# По умолчанию во всех случаях снаряд просто исчезает, как раньше. Вызываются
# из коллизий и таймера ниже; _finish() следит, что снаряд ещё FLYING, и один
# раз шлёт сигнал hit_target.
# ============================================================================
## Попал во врага (Area2D). enemy — то, во что попали.
func _on_hit_enemy(enemy: Node) -> void:
	queue_free()


## Попал в землю/стену (StaticBody2D). point — точка попадания, мировые координаты.
func _on_hit_ground(point: Vector2) -> void:
	queue_free()


## Кончилось время жизни или снаряд ушёл за экран.
func _on_expire() -> void:
	queue_free()


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Форму строим в коде, чтобы корректно отмасштабировать радиус попадания.
func _add_hit_shape() -> void:
	if has_node("Shape"):
		return
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var circle := CircleShape2D.new()
	circle.radius = maxf(hit_radius * art_scale, 1.0)
	shape.shape = circle
	add_child(shape)


func _on_body_entered(body: Node2D) -> void:
	# Враг — это тоже тело (CharacterBody2D), поэтому он попадает именно сюда, а не в
	# _on_area_entered. Тело с методом take_hit считаем врагом: отдаём урон и зовём хук
	# попадания во врага. Остальные тела — земля и стены, камень разбивается.
	# body_entered не отдаёт точку касания, поэтому передаём текущий центр снаряда.
	if body.has_method("take_hit"):
		if _finish(State.HIT_ENEMY, body):
			_damage_target(body)
			_on_hit_enemy(body)
		return
	if _finish(State.LANDED, body):
		_on_hit_ground(global_position)


## Отдаёт урон цели, если она это умеет: take_hit(damage, direction).
## Единственное место, где урон из ProjectileData.damage уходит врагу.
func _damage_target(target: Node) -> void:
	if not target.has_method("take_hit"):
		return
	target.call("take_hit", data.damage, _velocity.normalized())


func _on_area_entered(area: Area2D) -> void:
	# Враг (или любая Area2D): отдаём урон, если цель умеет, и зовём хук попадания.
	if _state != State.FLYING:
		return
	_damage_target(area)
	_finish(State.HIT_ENEMY, area)
	_on_hit_enemy(area)


func _on_screen_entered() -> void:
	_was_on_screen = true


func _on_screen_exited() -> void:
	# Убираем только если снаряд реально побывал на экране.
	if _was_on_screen and _finish(State.EXPIRING, null):
		_on_expire()


## Переводит снаряд из FLYING в терминальное состояние state: фиксирует состояние
## и один раз шлёт hit_target(target). false — снаряд уже завершился (раньше это
## делал флаг _dead; повторные попадания по-прежнему игнорируются).
func _finish(state: State, target: Node) -> bool:
	if _state != State.FLYING:
		return false
	_state = state
	hit_target.emit(target)
	return true
