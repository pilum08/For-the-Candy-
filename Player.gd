extends CharacterBody2D
## Герой «Дон»: собран из готовых картинок (Sprites/DON*), анимация стоп-моушен,
## передняя рука наводится на курсор, стрельба камнем (Sprites/stone.bmp).
##
## ВСЕ ПОЗЫ — в таблицах IDLE_POSES / WALK_POSES / AIR_UP_POSE / AIR_DOWN_POSE ниже.
## Углы в градусах, смещения в пикселях АРТА (умножаются на art_scale).
## Микро-джиттер (±1-2 px, ±2°) вшит прямо в числа таблиц — никакого Random в рантайме.

# ============================================================================
# СБОРКА ТЕЛА — единственное место с геометрией частей (механику см. Rig.gd).
# Начало координат игрока = центр между стопами на земле.
#   pivot_px   — сустав ВНУТРИ картинки, в её пикселях от левого верхнего угла
#                (например центр розового конца руки) → Sprite2D.offset = -pivot_px;
#   attach_pos — куда сустав встаёт НА РОДИТЕЛЕ (пиксели арта, до art_scale).
# Заменил PNG на обрезанный — правишь только pivot_px, размер картинки не нужен.
# Порядок частей = порядок отрисовки (он же порядок узлов в Player.tscn).
# ============================================================================
const Rig := preload("res://Rig.gd")   # механизм сборки: расставляет части по таблице RIG
const CorpseScript := preload("res://Corpse.gd")   # тип трупа: pickup/put_down/launch проверяет парсер
const RIG: Dictionary = {
	"LegL": {
		"node": "Visual/LegL", "sprite": "Visual/LegL/Sprite",
		"attach_pos": Vector2(-139.0, -120.0), "pivot_px": Vector2(21.0, 4.1),
	},
	"LegR": {
		"node": "Visual/LegR", "sprite": "Visual/LegR/Sprite",
		"attach_pos": Vector2(111.0, -109.0), "pivot_px": Vector2(11.4, 2.4),
	},
	"ArmBack": {
		"node": "Visual/ArmBack", "sprite": "Visual/ArmBack/Sprite",
		"attach_pos": Vector2(-201.0, -254.0), "pivot_px": Vector2(150.4, 77.4),
	},
	"Body": {
		"node": "Visual/Body", "sprite": "Visual/Body/Torso",
		"attach_pos": Vector2(-2.0, -162.0), "pivot_px": Vector2(223.0, 195.0),
	},
	"Skirt": {
		"node": "Visual/Body/Skirt", "sprite": "Visual/Body/Skirt/Sprite",
		"attach_pos": Vector2(-1.0, -86.0), "pivot_px": Vector2(268.0, 0.0),
	},
	"ArmFront": {
		"node": "Visual/Body/ArmFront", "sprite": "Visual/Body/ArmFront/Sprite",
		"attach_pos": Vector2(201.0, -82.0), "pivot_px": Vector2(6.6, 60.0),
	},
	"Head": {
		"node": "Visual/Body/Head", "sprite": "Visual/Body/Head/Sprite",
		"attach_pos": Vector2(-15.0, -139.0), "pivot_px": Vector2(253.5, 443.0),
	},
	"Face": {
		"node": "Visual/Body/Head/Face",
		"attach_pos": Vector2(0.0, 0.0), "pivot_px": Vector2(60.0, 345.0),
	},
	"Muzzle": {
		"node": "Visual/Body/ArmFront/Muzzle", "sprite": "",
		"attach_pos": Vector2(133.0, -38.0), "pivot_px": Vector2.ZERO,
	},
}

# Коллайдер (прямоугольник: торс + юбка + ноги) — тоже в пикселях арта.
const COLLIDER_SIZE := Vector2(452.0, 348.0)
const COLLIDER_OFFSET := Vector2(0.0, -174.0)

# --- лица (оверлеи поверх головы) -------------------------------------------
const FACE_IDLE: Texture2D = preload("res://Sprites/DON_idle_face.png")
const FACE_SHOOT: Texture2D = preload("res://Sprites/DON_shoot_face-2.png")

# ============================================================================
# ТАБЛИЦЫ ПОЗ
# Обязательные ключи: body_pos, body_rot, head_pos, head_rot,
#                     skirt_pos, skirt_rot, leg_l_pos, leg_l_rot,
#                     leg_r_pos, leg_r_rot, arm_back_rot
# ============================================================================

## Idle: 2 позы, торс и голова «дышат» на 1-2 px, юбка еле шевелится.
const IDLE_POSES: Array = [
	{
		"body_pos": Vector2(0.0, 0.0), "body_rot": 0.0,
		"head_pos": Vector2(0.0, 0.0), "head_rot": -1.0,
		"skirt_pos": Vector2(0.0, 0.0), "skirt_rot": 1.0,
		"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": 0.0,
		"leg_r_pos": Vector2(0.0, 0.0), "leg_r_rot": 0.0,
		"arm_back_rot": 2.0,
	},
	{
		"body_pos": Vector2(0.0, -2.0), "body_rot": 1.0,
		"head_pos": Vector2(0.0, -2.0), "head_rot": 1.0,
		"skirt_pos": Vector2(1.0, -1.0), "skirt_rot": -1.5,
		"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": 1.0,
		"leg_r_pos": Vector2(0.0, 1.0), "leg_r_rot": -1.0,
		"arm_back_rot": -1.0,
	},
]

## Ходьба: 4 рывковых «кадра» (pose_fps ≈ 8). Ноги поочерёдно ±12-15°,
## торс подпрыгивает на 2-3 px, голова запаздывает и кивает, юбка качается
## в сторону, противоположную шагу. Асимметрия чисел = детерминированный джиттер.
const WALK_POSES: Array = [
	# 0 — контакт, дальняя (левая) нога вперёд
	{
		"body_pos": Vector2(0.0, -3.0), "body_rot": -2.0,
		"head_pos": Vector2(1.0, 1.0), "head_rot": 2.0,
		"skirt_pos": Vector2(0.0, -1.0), "skirt_rot": -4.0,
		"leg_l_pos": Vector2(0.0, -3.0), "leg_l_rot": 14.0,
		"leg_r_pos": Vector2(0.0, 1.0), "leg_r_rot": -12.0,
		"arm_back_rot": 8.0,
	},
	# 1 — проход, обе ноги поджаты, тело выше
	{
		"body_pos": Vector2(0.0, -5.0), "body_rot": 0.0,
		"head_pos": Vector2(-1.0, -1.0), "head_rot": -1.0,
		"skirt_pos": Vector2(0.0, 0.0), "skirt_rot": -1.0,
		"leg_l_pos": Vector2(0.0, -5.0), "leg_l_rot": 2.0,
		"leg_r_pos": Vector2(0.0, -4.0), "leg_r_rot": -2.0,
		"arm_back_rot": -4.0,
	},
	# 2 — контакт, ближняя (правая) нога вперёд (не точное зеркало позы 0)
	{
		"body_pos": Vector2(0.0, -3.0), "body_rot": 2.0,
		"head_pos": Vector2(-1.0, 1.0), "head_rot": -2.0,
		"skirt_pos": Vector2(0.0, -1.0), "skirt_rot": 4.0,
		"leg_l_pos": Vector2(0.0, 1.0), "leg_l_rot": -12.0,
		"leg_r_pos": Vector2(0.0, -3.0), "leg_r_rot": 13.0,
		"arm_back_rot": -9.0,
	},
	# 3 — проход в другую сторону
	{
		"body_pos": Vector2(0.0, -5.0), "body_rot": 0.0,
		"head_pos": Vector2(1.0, 0.0), "head_rot": 1.0,
		"skirt_pos": Vector2(-1.0, 0.0), "skirt_rot": 1.0,
		"leg_l_pos": Vector2(0.0, -4.0), "leg_l_rot": -2.0,
		"leg_r_pos": Vector2(0.0, -5.0), "leg_r_rot": 3.0,
		"arm_back_rot": 5.0,
	},
]

## Прыжок (взлёт): ноги поджаты, задняя рука задрана вверх.
const AIR_UP_POSE: Dictionary = {
	"body_pos": Vector2(0.0, -2.0), "body_rot": -3.0,
	"head_pos": Vector2(0.0, -1.0), "head_rot": 2.0,
	"skirt_pos": Vector2(0.0, 1.0), "skirt_rot": -6.0,
	"leg_l_pos": Vector2(0.0, -4.0), "leg_l_rot": -18.0,
	"leg_r_pos": Vector2(0.0, -2.0), "leg_r_rot": 16.0,
	"arm_back_rot": 26.0,
}

## Падение: ноги растопырены, задняя рука машет вниз.
const AIR_DOWN_POSE: Dictionary = {
	"body_pos": Vector2(0.0, 0.0), "body_rot": 2.0,
	"head_pos": Vector2(0.0, 1.0), "head_rot": -2.0,
	"skirt_pos": Vector2(0.0, -1.0), "skirt_rot": 5.0,
	"leg_l_pos": Vector2(0.0, 2.0), "leg_l_rot": 12.0,
	"leg_r_pos": Vector2(0.0, 2.0), "leg_r_rot": -10.0,
	"arm_back_rot": -22.0,
}

# ============================================================================
# ЭКСПОРТ-НАСТРОЙКИ (крутить тут)
# ============================================================================
@export_group("Вид")
## Масштаб арта: 1.0 = пиксель в пиксель (герой ~728 px высотой).
@export_range(0.05, 2.0, 0.01) var art_scale: float = 0.35
## Общий размер героя (1.0 = как был, 0.6 = 60%). Умножается на art_scale и
## применяется к Visual (а Muzzle — его ребёнок, поэтому уменьшается вместе с ним)
## и к коллайдеру. Корень CharacterBody2D не масштабируем: сломалась бы физика.
@export_range(0.1, 2.0, 0.01) var player_scale: float = 0.6
## Пересчитывать скорость/прыжок/гравитацию вместе с player_scale (см. _motion_scale):
## при 0.6 герой бежит 240 px/с и прыгает на ~185 px — то же самое «в своих ростах».
## Снять галочку — числа останутся мировыми (px), как до уменьшения героя.
@export var scale_movement_with_player: bool = true
## Включить лица-оверлеи (idle по умолчанию, shoot на время выстрела).
@export var face_enabled: bool = true

@export_group("Движение")
@export var speed: float = 400.0
@export var acceleration: float = 2400.0
@export var friction: float = 2800.0
@export var gravity: float = 2200.0
@export var max_fall_speed: float = 1400.0
@export var jump_velocity: float = -1150.0
## Отпустил прыжок в полёте — высота прыжка урезается (0.45 = короткий прыжок).
@export_range(0.0, 1.0, 0.05) var jump_cut: float = 0.45

@export_group("Анимация (стоп-моушен)")
## Частота смены поз при ходьбе (кадров в секунду, позы меняются рывком).
@export var pose_fps: float = 8.0
## Частота смены поз в idle.
@export var idle_pose_fps: float = 3.5

@export_group("Прицел и стрельба")
## Предел наклона передней руки вверх (градусы, 0 = рука не поднимается).
@export var aim_up_limit_deg: float = 85.0
## Предел наклона руки вниз (градусы).
@export var aim_down_limit_deg: float = 85.0
## Мёртвая зона курсора (px): в пределах неё направление взгляда не дёргается.
@export var aim_facing_dead_zone: float = 16.0
## Сцена снаряда (Projectile.tscn).
@export var projectile_scene: PackedScene
## Пауза между выстрелами, сек.
@export var shoot_cooldown: float = 0.25
## На сколько градусов рука откидывается назад при выстреле («отдача»).
@export var recoil_deg: float = 18.0
## Сколько секунд держится отдача (рывком, без плавности).
@export var recoil_time: float = 0.12
## Сколько держать «лицо выстрела».
@export var shoot_face_time: float = 0.18

@export_group("Труп: подбор и бросок")
## Радиус зоны подбора PickupZone — в пикселях арта (как коллайдер, умножается на
## art_scale * player_scale). Внутри неё E берёт ближайший труп из группы "corpses".
@export var pickup_radius: float = 900.0
## Доп. сдвиг гнезда трупа от позиции из Player.tscn (пиксели торса): x — вперёд
## по взгляду, y — вниз. Базовое место смотри в сцене (Visual/Body/CarryPoint).
@export var carry_offset_x: float = 0.0
@export var carry_offset_y: float = 0.0
## Размер трупа в руках относительно его обычного размера (1 = как лежал на земле).
@export_range(0.05, 2.0, 0.01) var carried_scale_mult: float = 1.0
## Поза «держу»: углы рук в градусах (0 = вперёд по взгляду). Пока труп в руках, передняя
## рука не целится за курсором, задняя не дёргается с ходьбой. Дефолт подобран так, чтобы
## кисти оказались у боков трупа при дефолтных carry_offset_*.
@export var carry_arm_angle_front: float = 69.0
@export var carry_arm_angle_back: float = 176.0
## Множители скорости ходьбы и силы прыжка, пока труп в руках.
@export_range(0.05, 1.0, 0.05) var carry_speed_mult: float = 0.7
@export_range(0.05, 1.0, 0.05) var carry_jump_mult: float = 0.75
## Куда встаёт труп, когда его опускают (E второй раз): вперёд от стоп, пиксели арта.
@export var drop_forward: float = 900.0
## Лёгкий толчок вперёд в момент, когда труп опустили (px/с).
@export var drop_impulse: float = 120.0
## Скорость броска у самого героя и на предельной дистанции (px/с).
@export var throw_speed_min: float = 450.0
@export var throw_speed_max: float = 1200.0
## Дистанция до курсора, на которой бросок набирает throw_speed_max (px).
@export var throw_full_distance: float = 500.0

@export_group("Смерть")
## Сколько секунд герой лежит мёртвым до перезагрузки сцены. Сюда подключится сцена смерти.
@export var respawn_delay: float = 1.0

## Герой умер (аргумент — сам герой). Сигнал на будущую сцену смерти.
signal died(player: Node)

# ============================================================================
# УЗЛЫ
# ============================================================================
@onready var visual: Node2D = $Visual
@onready var collider: CollisionShape2D = $Collider
@onready var body: Node2D = $Visual/Body
@onready var head: Node2D = $Visual/Body/Head
@onready var face: Sprite2D = $Visual/Body/Head/Face
@onready var skirt: Node2D = $Visual/Body/Skirt
@onready var arm_front: Node2D = $Visual/Body/ArmFront
@onready var muzzle: Marker2D = $Visual/Body/ArmFront/Muzzle
@onready var arm_back: Node2D = $Visual/ArmBack
@onready var leg_l: Node2D = $Visual/LegL
@onready var leg_r: Node2D = $Visual/LegR
@onready var carry_point: Marker2D = $Visual/Body/CarryPoint
@onready var pickup_zone: Area2D = $PickupZone
@onready var pickup_shape: CollisionShape2D = $PickupZone/Shape

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
enum State { IDLE, WALK, AIR }

var _state: State = State.IDLE
var _pose_index: int = 0
var _pose_timer: float = 0.0
## +1 = смотрит вправо (как на референсе), -1 = влево (через scale.x).
var _facing: int = 1
var _shoot_timer: float = 0.0
var _recoil_timer: float = 0.0
var _face_timer: float = 0.0
var _arm_rest_angle: float = 0.0
var _applied_art_scale: float = -1.0
## Позиция гнезда трупа прямо из Player.tscn: экспорты carry_offset_* сдвигают её.
var _carry_base := Vector2.ZERO
## Руки заняты трупом: публичный флаг «несу». Ставится и сбрасывается сам — сеттером
## _carried ниже, поэтому отдельно его править не надо (его читает can_shoot).
var is_carrying: bool = false
## Труп в руках (null — руки пусты). Нести можно ровно один, см. _interact.
## Сеттер держит is_carrying в согласии с руками: где бы _carried ни меняли, флаг верен.
var _carried: CorpseScript = null:
	set(value):
		_carried = value
		is_carrying = value != null
## ЛКМ уже потрачена броском: пока кнопку не отпустят, выстрела не будет. Иначе то самое
## нажатие, которым бросили труп, следующим кадром создаёт снаряд (ЛКМ-то ещё зажата).
var _shoot_consumed: bool = false
## Порядок отрисовки рук на время переноски трупа: снимок «как было до подбора» (save_z),
## возврат — одним методом restore_z() при опускании, броске и смерти.
var _arm_order_saved: bool = false
var _arm_front_visible: bool = true
var _arm_front_z: int = 0
var _arm_front_z_relative: bool = true
var _arm_back_z: int = 0
var _arm_back_z_relative: bool = true
## Умер ли герой. Смерть — только через die(), повторный вызов ничего не делает.
var is_dead: bool = false


func _ready() -> void:
	Rig.apply(self, RIG)   # расставляет суставы и спрайты по таблице RIG (см. выше)
	_arm_rest_angle = _attach("Muzzle").angle()  # «покой» руки: шарик дальше и выше плеча
	_carry_base = carry_point.position            # база для carry_offset_* (см. _apply_art_scale)
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_art_scale()
	face.texture = FACE_IDLE
	face.visible = face_enabled
	_pose_index = 0
	_apply_pose(_pose_for_state())


func _process(delta: float) -> void:
	_apply_art_scale()   # каждый кадр: правка art_scale/player_scale видна сразу
	_update_aim()
	_update_face(delta)
	_update_poses(delta)


func _physics_process(delta: float) -> void:
	_tick_combat(delta)
	_move(delta)


# ============================================================================
# ДВИЖЕНИЕ
# ============================================================================
func _move(delta: float) -> void:
	# k — пересчёт движения под размер героя (см. _motion_scale): при player_scale = 0.6
	# скорость, ускорение, трение, гравитация и прыжок умножаются на 0.6.
	var k := _motion_scale()
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * k * delta, max_fall_speed * k)

	# С трупом в руках герой идёт медленнее и прыгает слабее (см. carry_* в экспортах).
	var carry_mult := carry_speed_mult if _carried != null else 1.0
	var dir := Input.get_axis("move_left", "move_right")
	if absf(dir) > 0.01:
		velocity.x = move_toward(velocity.x, dir * speed * k * carry_mult, acceleration * k * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * k * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity * k * (carry_jump_mult if _carried != null else 1.0)
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	move_and_slide()
	_update_state()


func _update_state() -> void:
	var next: State = _state
	if not is_on_floor():
		next = State.AIR
	elif absf(velocity.x) > 12.0:
		next = State.WALK
	else:
		next = State.IDLE
	if next != _state:
		_state = next
		_pose_index = 0   # смена состояния — поза переключается рывком, без сглаживания
		_pose_timer = 0.0

# ============================================================================
# ПРИЦЕЛ, ВЫСТРЕЛ, ЛИЦО
# ============================================================================
## Направление взгляда = сторона курсора; передняя рука едет за курсором.
func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if absf(to_mouse.x) > aim_facing_dead_zone:
		_facing = 1 if to_mouse.x > 0.0 else -1
		_apply_art_scale()  # зеркалим визуал через scale.x

	if _carried != null:
		# Труп в руках: передняя рука замирает в позе «держу» и не целится за курсором,
		# отдачи тоже нет (прицел не считается вовсе).
		arm_front.rotation = deg_to_rad(carry_arm_angle_front)
		return

	var shoulder := arm_front.global_position
	var aim_vec := get_global_mouse_position() - shoulder
	# Переводим направление в локальные оси визуала (учёт зеркала по scale.x).
	var local_dir := Vector2(aim_vec.x * float(_facing), aim_vec.y)
	if local_dir.length_squared() < 1.0:
		local_dir = Vector2(1.0, 0.0)
	# Рука не выворачивается за спину: ограничиваем угол относительно «вперёд».
	var ang := clampf(
		local_dir.angle(),
		-deg_to_rad(aim_up_limit_deg),
		deg_to_rad(aim_down_limit_deg)
	)
	arm_front.rotation = ang - _arm_rest_angle - _recoil_angle()


func _recoil_angle() -> float:
	return deg_to_rad(recoil_deg) if _recoil_timer > 0.0 else 0.0


func _tick_combat(delta: float) -> void:
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)
	_recoil_timer = maxf(_recoil_timer - delta, 0.0)
	if Input.is_action_just_released("shoot"):
		_shoot_consumed = false   # кнопку отпустили — следующее нажатие снова стреляет
	if Input.is_action_just_pressed("interact"):
		_interact()
	if _carried != null:
		# Труп в руках: ЛКМ бросает, а стрелять в этот момент нельзя (см. can_shoot).
		if Input.is_action_just_pressed("shoot"):
			_throw_corpse()
			# Это нажатие ЛКМ «съедено» броском: палец ещё на кнопке, но снаряда после
			# броска не будет — только после отпускания и нового нажатия (см. _shoot_consumed).
			_shoot_consumed = true
		return
	if Input.is_action_pressed("shoot") and not _shoot_consumed:
		_shoot()


## Можно ли сейчас выстрелить. Снаряд создаётся ровно в одном месте — _shoot(), и он зовёт
## это первой строкой. Запреты: руки заняты трупом, герой мёртв, идёт кулдаун между выстрелами.
func can_shoot() -> bool:
	if is_carrying or is_dead:
		return false
	return _shoot_timer <= 0.0


func _shoot() -> void:
	if not can_shoot():
		return
	if projectile_scene == null:
		return
	_shoot_timer = shoot_cooldown
	_recoil_timer = recoil_time          # рывок назад, потом такой же рывок в исходное
	_face_timer = shoot_face_time

	var origin := muzzle.global_position
	var dir := get_global_mouse_position() - origin
	if dir.length_squared() < 1.0:
		dir = Vector2(float(_facing), 0.0)
	# ВРЕМЕННО (диагностика «ЛКМ при трупе в руках»): появилось в консоли — снаряд правда
	# создан. Это и есть точка создания снаряда, строки ниже. Убрать по команде.
	print("[SHOOT] снаряд создан | is_carrying=%s is_dead=%s _carried=%s" % [is_carrying, is_dead, _carried])
	print_stack()
	var shot := projectile_scene.instantiate()
	shot.art_scale = art_scale
	get_tree().current_scene.add_child(shot)
	shot.global_position = origin
	shot.launch(dir.normalized())


# ============================================================================
# ТРУП: ПОДБОР (E) И БРОСОК (ЛКМ)
# ============================================================================
## E: руки пусты — берём ближайший труп из PickupZone; руки заняты — опускаем его.
func _interact() -> void:
	if _carried != null and not is_instance_valid(_carried):
		_carried = null   # труп исчез из мира — руки снова пусты
		restore_z()       # и порядок рук тоже: вернуть его тут больше негде
	if _carried != null:
		_drop_corpse()
		return
	var corpse := _nearest_corpse()
	if corpse != null:
		_carried = corpse
		corpse.pickup(self, carried_scale_mult)
		save_z()        # порядок рук «как было» — вернуть его сможет restore_z
		raise_arm_z()   # и кисти над трупом, пока is_carrying = true


## Ближайший труп из группы "corpses", попавший в PickupZone (её форму см. _apply_art_scale).
func _nearest_corpse() -> CorpseScript:
	var best: CorpseScript = null
	var best_distance := INF
	for body in pickup_zone.get_overlapping_bodies():
		var corpse := body as CorpseScript
		if corpse == null:
			continue
		var distance := corpse.global_position.distance_to(pickup_zone.global_position)
		if distance < best_distance:
			best_distance = distance
			best = corpse
	return best


## Опускаем труп на землю перед собой (E второй раз) и слегка толкаем вперёд.
func _drop_corpse() -> void:
	var corpse := _carried
	_carried = null        # руки пусты: с этого момента подъём кистей запрещён
	restore_z(corpse)      # один возврат: руки из снимка + труп по своему corpse_world_z
	if corpse == null:
		return
	var s := maxf(art_scale, 0.01) * maxf(player_scale, 0.01)
	# Начало координат трупа — его низ, поэтому точка впереди стоп кладёт его на землю.
	var at := global_position + Vector2(drop_forward * float(_facing) * s, 0.0)
	corpse.put_down(at, Vector2(drop_impulse * float(_facing), 0.0))


## Бросок по дуге в сторону курсора: рука дёргается назад (как отдача), дальше труп летит сам.
func _throw_corpse() -> void:
	var corpse := _carried
	_carried = null        # руки пусты: с этого момента подъём кистей запрещён
	restore_z(corpse)      # один возврат: руки из снимка + труп по своему corpse_world_z
	if corpse == null:
		return
	_recoil_timer = recoil_time   # рывок передней руки, без плавности (см. _recoil_angle)
	var from := carry_point.global_position
	var to_mouse := get_global_mouse_position() - from
	var direction := Vector2(float(_facing), 0.0)
	if to_mouse.length_squared() >= 1.0:
		direction = to_mouse.normalized()
	# Чем дальше курсор, тем сильнее бросок: от throw_speed_min до throw_speed_max.
	var t := clampf(to_mouse.length() / maxf(throw_full_distance, 1.0), 0.0, 1.0)
	corpse.launch(direction, lerpf(throw_speed_min, throw_speed_max, t))


# ============================================================================
# ПОРЯДОК ОТРИСОВКИ РУК И ТРУПА ПРИ ПЕРЕНОСКЕ
# ============================================================================
## Явная шкала z. В сценах z нигде не выставлен (все узлы = 0), а при равных z порядок решает
## список детей — на этот побочный эффект иерархии НЕ опираемся:
##   труп на земле      → Corpse.corpse_world_z (-1): лежащий труп позади героя, кисть и ноги
##                        героя видны поверх него; хочешь труп впереди — поставь там 1;
##   герой и его части  → 0 (руки, торс, голова — как в сцене, ничего не трогаем);
##   труп в руках       → 0 внутри гнезда Visual/Body/CarryPoint, между юбкой и головой;
##   кисти в переноске  → ARMS_OVER_CORPSE_Z (+1): кисть задней руки видна поверх трупа.
## Снимок «как было» — один раз при подборе (save_z), возврат — одним методом restore_z() при
## опускании (E), броске (ЛКМ) и смерти (die). Каждый кадр из _carried порядок НЕ выводится:
## иначе он разъезжается с тем, где труп на самом деле, и рука остаётся поверх трупа на земле.
const ARMS_OVER_CORPSE_Z := 1


## Запомнить порядок рук «как было до подбора»: что показывать, z и его относительность.
## Зовётся ровно один раз — в момент подбора, вместе с Corpse.pickup (труп снимает свои
## значения сам, см. Corpse.save_z).
func save_z() -> void:
	if _arm_order_saved:
		return
	_arm_front_visible = arm_front.visible
	_arm_front_z = arm_front.z_index
	_arm_front_z_relative = arm_front.z_as_relative
	_arm_back_z = arm_back.z_index
	_arm_back_z_relative = arm_back.z_as_relative
	_arm_order_saved = true


## Поднять кисти над трупом в руках: труп в гнезде рисуется над торсом и юбкой, но под руками и
## головой, поэтому кисти надо поднять — тогда видна кисть задней руки, а передняя рука (та, что
## со стороны взгляда) прячется целиком.
## Пока is_carrying = false, метод молчит: «навсегда поверх» быть не должно.
func raise_arm_z() -> void:
	if not is_carrying:
		return
	save_z()
	arm_front.visible = false
	# z_as_relative = true: поднятие считается от группы героя, то есть «выше всего, что
	# рисуется вместе с ним», а не «на 1 выше уровня земли».
	arm_front.z_index = ARMS_OVER_CORPSE_Z
	arm_front.z_as_relative = true
	arm_back.z_index = ARMS_OVER_CORPSE_Z
	arm_back.z_as_relative = true


## ЕДИНСТВЕННЫЙ возврат порядка отрисовки — руки и труп одним вызовом. Труп возвращает свой
## мировой z сам (Corpse.restore_z: явное corpse_world_z), но зовём его отсюда, чтобы у
## опускания, броска и смерти был ровно один и тот же путь. Без снимка рук ничего не делаем —
## возвращать нечего.
func restore_z(corpse: CorpseScript = null) -> void:
	if corpse != null and is_instance_valid(corpse):
		corpse.restore_z()
	if not _arm_order_saved:
		return
	arm_front.visible = _arm_front_visible
	arm_front.z_index = _arm_front_z
	arm_front.z_as_relative = _arm_front_z_relative
	arm_back.z_index = _arm_back_z
	arm_back.z_as_relative = _arm_back_z_relative
	_arm_order_saved = false


func _update_face(delta: float) -> void:
	_face_timer = maxf(_face_timer - delta, 0.0)
	if not face_enabled:
		face.visible = false
		return
	face.visible = true
	face.texture = FACE_SHOOT if _face_timer > 0.0 else FACE_IDLE


# ============================================================================
# АНИМАЦИЯ (стоп-моушен: позы переключаются рывком с частотой pose_fps)
# ============================================================================
func _update_poses(delta: float) -> void:
	if _state == State.AIR:
		_pose_index = 0
		_pose_timer = 0.0
		_apply_pose(_pose_for_state())
		return

	var fps := pose_fps if _state == State.WALK else idle_pose_fps
	var period := 1.0 / maxf(fps, 0.001)
	var pose_count: int = WALK_POSES.size() if _state == State.WALK else IDLE_POSES.size()
	_pose_timer += delta
	while _pose_timer >= period:
		_pose_timer -= period
		_pose_index = (_pose_index + 1) % maxi(pose_count, 1)
	_apply_pose(_pose_for_state())


func _pose_for_state() -> Dictionary:
	match _state:
		State.WALK:
			var walk: Array = WALK_POSES
			return walk[_pose_index % walk.size()]
		State.AIR:
			if velocity.y < 0.0:
				return AIR_UP_POSE
			return AIR_DOWN_POSE
		_:
			var idle: Array = IDLE_POSES
			return idle[_pose_index % idle.size()]


## Применяет позу: пивоты остаются на местах, меняются повороты и мелкие смещения.
func _apply_pose(p: Dictionary) -> void:
	body.position = _attach("Body") + (p["body_pos"] as Vector2)
	body.rotation = deg_to_rad(p["body_rot"] as float)

	# Head и Skirt — дети Body: координаты локальные (attach_pos части в таблице RIG).
	head.position = _attach("Head") + (p["head_pos"] as Vector2)
	head.rotation = deg_to_rad(p["head_rot"] as float)

	skirt.position = _attach("Skirt") + (p["skirt_pos"] as Vector2)
	skirt.rotation = deg_to_rad(p["skirt_rot"] as float)

	leg_l.position = _attach("LegL") + (p["leg_l_pos"] as Vector2)
	leg_l.rotation = deg_to_rad(p["leg_l_rot"] as float)
	leg_r.position = _attach("LegR") + (p["leg_r_pos"] as Vector2)
	leg_r.rotation = deg_to_rad(p["leg_r_rot"] as float)

	# В руках труп: задняя рука тоже замирает в позе «держу», без дёргания с ходьбой.
	if _carried != null:
		arm_back.rotation = deg_to_rad(carry_arm_angle_back)
	else:
		arm_back.rotation = deg_to_rad(p["arm_back_rot"] as float)


# ============================================================================
# СМЕРТЬ — ЕДИНСТВЕННАЯ ТОЧКА (шипы, враг касанием и всё будущее зовут только die())
# ============================================================================
## Герой умер. Своей логики смерти здесь нет: ни анимации, ни экрана — только
## «замер и перезапуск». Сюда подключится сцена смерти (сигнал died / настройка respawn_delay).
func die() -> void:
	if is_dead:
		return            # защита от двойного вызова: шипы + враг в одном кадре и т. п.
	is_dead = true
	velocity = Vector2.ZERO
	# Руки разжимаются насовсем: _drop_corpse() уже вернул и труп, и кисти; вызов ниже — на случай
	# смерти с пустыми руками (без снимка он молчит) и он же явно показывает скрытую переднюю руку:
	# дальше выключается _process, и поставить порядок рук больше некому.
	if _carried != null:
		_drop_corpse()
	restore_z()
	_apply_art_scale()
	set_physics_process(false)   # движение выключено
	set_process(false)           # ввод/прицел/анимация выключены
	died.emit(self)
	await get_tree().create_timer(respawn_delay).timeout
	# Сцена перезагружается сама; при F6 (герой без сцены) молча выходим.
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
## attach_pos части из таблицы RIG — «покой» сустава в координатах родителя.
func _attach(part_name: String) -> Vector2:
	return Rig.attach(RIG, part_name)


## Коэффициент пересчёта движения под размер героя. player_scale = 0.6 → скорость,
## ускорение, трение, прыжок и гравитация умножаются на 0.6: высота прыжка (~185 px)
## и время прыжка остаются теми же «в ростах героя». Галочка снята — числа мировые.
func _motion_scale() -> float:
	if not scale_movement_with_player:
		return 1.0
	return maxf(player_scale, 0.01)


## Масштаб + зеркалирование делаем на узле Visual (не на CharacterBody2D!),
## чтобы физика не масштабировалась. Коллайдер масштабируем отдельно.
## Muzzle — ребёнок Visual, поэтому уменьшается вместе с ним; отдельно его не
## трогаем, иначе масштаб применился бы дважды.
func _apply_art_scale() -> void:
	var s := maxf(art_scale, 0.01) * maxf(player_scale, 0.01)
	visual.scale = Vector2(s * float(_facing), s)
	# Гнездо трупа лежит ВНУТРИ Visual/Body: зеркало и масштаб оно получает от родителя,
	# поэтому тут только позиция (база из сцены плюс подстройка экспортами).
	carry_point.position = _carry_base + Vector2(carry_offset_x, carry_offset_y)
	# Порядок отрисовки рук тут НЕ трогаем: он меняется только в момент подбора и возврата
	# трупа (см. save_z / raise_arm_z / restore_z). Выводить его каждый кадр из
	# _carried нельзя: если руки приподняты, а труп на самом деле лежит на земле, рука
	# окажется нарисованной поверх трупа — как раз то, что и было.
	if is_equal_approx(_applied_art_scale, s):
		return
	_applied_art_scale = s
	var rect := RectangleShape2D.new()
	rect.size = COLLIDER_SIZE * s
	collider.shape = rect
	collider.position = COLLIDER_OFFSET * s
	# Зона подбора трупов масштабируется так же, как коллайдер (физика не масштабируется).
	var circle := CircleShape2D.new()
	circle.radius = maxf(pickup_radius * s, 1.0)
	pickup_shape.shape = circle
