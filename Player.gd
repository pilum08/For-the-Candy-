extends CharacterBody2D
## Герой «Дон»: собран из готовых картинок (Sprites/DON*), анимация стоп-моушен,
## передняя рука наводится на курсор, стрельба камнем (Sprites/stone.bmp).
##
## ВСЕ ПОЗЫ — в таблицах IDLE_POSES / WALK_POSES / AIR_UP_POSE / AIR_DOWN_POSE ниже.
## Углы в градусах, смещения в пикселях АРТА (умножаются на art_scale).
## Микро-джиттер (±1-2 px, ±2°) вшит прямо в числа таблиц — никакого Random в рантайме.

# --- геометрия сборки: измерена по референсу Sprites/DON.png -----------------
# Начало координат игрока = центр между стопами на земле.
const BODY_POS := Vector2(-2.0, -162.0)         # торс, пивот — талия (низ торса)
const HEAD_POS := Vector2(-17.0, -301.0)        # голова, пивот — шея (МИРОВЫЕ координаты)
const SKIRT_POS := Vector2(-3.0, -248.0)        # юбка, пивот — верх юбки (МИРОВЫЕ координаты)
# Head и Skirt — ДОЧЕРНИЕ узлы Body, поэтому им нужны ЛОКАЛЬНЫЕ координаты:
# иначе BODY_POS прибавляется дважды и голова с юбкой уезжают вверх на 162 px.
const HEAD_LOCAL := HEAD_POS - BODY_POS         # = (-15, -139): ровно как в Player.tscn
const SKIRT_LOCAL := SKIRT_POS - BODY_POS       # = (-1, -86):   ровно как в Player.tscn
const SHOULDER_BACK := Vector2(-201.0, -254.0)  # задняя (левая) рука
const SHOULDER_FRONT := Vector2(199.0, -244.0)  # передняя рука — ей целимся
const HIP_L := Vector2(-139.0, -120.0)          # дальняя нога
const HIP_R := Vector2(111.0, -109.0)           # ближняя нога
const MUZZLE_REL := Vector2(133.0, -38.0)       # центр кисти-шарика от плеча
const COLLIDER_SIZE := Vector2(452.0, 348.0)    # прямоугольник: торс + юбка + ноги
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


func _ready() -> void:
	_arm_rest_angle = MUZZLE_REL.angle()  # «покой» руки: шарик дальше и выше плеча
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

	var dir := Input.get_axis("move_left", "move_right")
	if absf(dir) > 0.01:
		velocity.x = move_toward(velocity.x, dir * speed * k, acceleration * k * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * k * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity * k
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
	if Input.is_action_pressed("shoot"):
		_shoot()


func _shoot() -> void:
	if _shoot_timer > 0.0 or projectile_scene == null:
		return
	_shoot_timer = shoot_cooldown
	_recoil_timer = recoil_time          # рывок назад, потом такой же рывок в исходное
	_face_timer = shoot_face_time

	var origin := muzzle.global_position
	var dir := get_global_mouse_position() - origin
	if dir.length_squared() < 1.0:
		dir = Vector2(float(_facing), 0.0)
	var shot := projectile_scene.instantiate()
	shot.art_scale = art_scale
	get_tree().current_scene.add_child(shot)
	shot.global_position = origin
	shot.launch(dir.normalized())


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
	body.position = BODY_POS + (p["body_pos"] as Vector2)
	body.rotation = deg_to_rad(p["body_rot"] as float)

	# Head и Skirt — дети Body: координаты локальные (см. HEAD_LOCAL / SKIRT_LOCAL).
	head.position = HEAD_LOCAL + (p["head_pos"] as Vector2)
	head.rotation = deg_to_rad(p["head_rot"] as float)

	skirt.position = SKIRT_LOCAL + (p["skirt_pos"] as Vector2)
	skirt.rotation = deg_to_rad(p["skirt_rot"] as float)

	leg_l.position = HIP_L + (p["leg_l_pos"] as Vector2)
	leg_l.rotation = deg_to_rad(p["leg_l_rot"] as float)
	leg_r.position = HIP_R + (p["leg_r_pos"] as Vector2)
	leg_r.rotation = deg_to_rad(p["leg_r_rot"] as float)

	arm_back.rotation = deg_to_rad(p["arm_back_rot"] as float)


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
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
	if is_equal_approx(_applied_art_scale, s):
		return
	_applied_art_scale = s
	var rect := RectangleShape2D.new()
	rect.size = COLLIDER_SIZE * s
	collider.shape = rect
	collider.position = COLLIDER_OFFSET * s
