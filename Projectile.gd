extends Area2D
## Снаряд — камень (Sprites/stone.bmp). Летит в сторону курсора от Muzzle по дуге,
## исчезает при попадании в стену/врага, по таймеру жизни и при выходе за экран.
## Слои: collision_layer = 4 (снаряды), collision_mask = 2|4... см. сцену
## (маска = враги (layer 2) + земля/стены (layer 3)).

## Испускается при любом попадании (в стену или во врага) — цель в аргументе.
signal hit_target(target: Node)

@export_group("Полёт")
## Начальная скорость, px/с (направление задаёт игрок: точно на курсор).
@export var speed: float = 900.0
## Время жизни, сек.
@export var lifetime: float = 3.0
## Гравитация снаряда, px/с²: каждый кадр velocity.y += shot_gravity * delta.
## 0 = летит по прямой, 1400 = заметная дуга, 2200 = как гравитация героя.
## Имя с приставкой shot_ вынужденное: у Area2D уже есть своё свойство gravity.
@export var shot_gravity: float = 1400.0
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

var _velocity := Vector2.ZERO
## Угол по вектору скорости (когда face_velocity) — spin докручивается поверх него.
var _base_rotation := 0.0
var _roll := 0.0
var _age := 0.0
var _dead := false
var _was_on_screen := false


func _ready() -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_velocity = dir.normalized() * speed
	if face_velocity:
		rotation = _base_rotation


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Дуга: гравитация добавляется каждый кадр, поэтому вектор скорости загибается вниз.
	_velocity.y += shot_gravity * delta
	global_position += _velocity * delta

	# Картинка смотрит по вектору скорости (на дуге камень «заваливается» за полётом),
	# spin докручивает её поверх — получается катящийся камень.
	if face_velocity and _velocity.length_squared() > 0.0001:
		_base_rotation = _velocity.angle()
	_roll += deg_to_rad(spin) * delta
	rotation = _base_rotation + _roll

	_age += delta
	if _age >= lifetime:
		_die(null)


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
	# Земля или стена — камень разбивается.
	_die(body)


func _on_area_entered(area: Area2D) -> void:
	# Враг (или любая Area2D): отдаём урон, если цель умеет, и сигналим наружу.
	if area.has_method("take_hit"):
		area.call("take_hit", _velocity.normalized())
	_die(area)


func _on_screen_entered() -> void:
	_was_on_screen = true


func _on_screen_exited() -> void:
	# Убираем только если снаряд реально побывал на экране.
	if _was_on_screen:
		_die(null)


func _die(target: Node) -> void:
	if _dead:
		return
	_dead = true
	hit_target.emit(target)
	queue_free()
