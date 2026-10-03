extends CharacterBody2D
## ВРАГ: собран из готовых картинок (Sprites/enemy/Enemy_*), анимация стоп-моушен
## (позы переключаются рывком), бежит к игроку, бьёт касанием, умирает от камней.
##
## ВСЕ ПОЗЫ — в таблицах IDLE_POSES / RUN_POSES / ATTACK_POSE ниже.
## Углы в градусах, смещения в пикселях АРТА (умножаются на enemy_scale).
## Микро-джиттер (±1-2 px, ±2°) вшит прямо в числа таблиц — никакого Random в рантайме
## (случайным остался только проворот трупа в момент смерти, см. Corpse.gd).

# ============================================================================
# СБОРКА ТЕЛА — единственное место с геометрией частей (механику см. Rig.gd).
# Начало координат врага = центр между стопами на земле (как у игрока).
#   pivot_px   — сустав ВНУТРИ картинки, в её пикселях от левого верхнего угла
#                (центр манжеты ноги, центр рукава, низ торса) → offset = -pivot_px;
#   attach_pos — куда сустав встаёт НА РОДИТЕЛЕ (пиксели арта, до enemy_scale).
# Все числа сняты с эталона Sprites/enemy/Enemy.png (холст 741x836, фигура
# (70,25)..(611,750)): при этих значениях части встают точно так, как нарисовано
# на эталоне. Заменил PNG на обрезанный — правишь только pivot_px.
# Порядок частей = порядок отрисовки: руки и ноги за торсом, пояс под футболкой,
# голова и лицо — поверх. Все части — дети Body (см. Enemy.tscn).
# ============================================================================
const Rig := preload("res://Rig.gd")   # механизм сборки: расставляет части по таблице RIG

## Точка-«нуль» эталона: середина между стопами на линии земли (пиксели холста).
## Нужна только для пересчёта: холст = ORIGIN + attach_pos (у детей Body ещё + Body_attach).
## Пример проверки руками: LegR → ORIGIN + (112, 69.3) − pivot (21, 6.3) = (444, 674) — тут
## правая нога и лежит на эталоне.
const ORIGIN := Vector2(352.0, 750.0)

const RIG: Dictionary = {
	"Body": {
		"node": "Visual/Body", "sprite": "Visual/Body/Torso",
		"attach_pos": Vector2(1.0, -139.0), "pivot_px": Vector2(166.0, 251.0),
	},
	"Pants": {
		"node": "Visual/Body/Pants",
		"attach_pos": Vector2(-3.0, -32.0), "pivot_px": Vector2(207.0, 35.0),
	},
	"ArmL": {
		"node": "Visual/Body/ArmL",
		"attach_pos": Vector2(-137.3, -106.8), "pivot_px": Vector2(105.7, 59.2),
	},
	"ArmR": {
		"node": "Visual/Body/ArmR",
		"attach_pos": Vector2(143.2, -116.3), "pivot_px": Vector2(7.2, 60.7),
	},
	"LegL": {
		"node": "Visual/Body/LegL",
		"attach_pos": Vector2(-99.6, 56.3), "pivot_px": Vector2(20.4, 5.3),
	},
	"LegR": {
		"node": "Visual/Body/LegR",
		"attach_pos": Vector2(112.0, 69.3), "pivot_px": Vector2(21.0, 6.3),
	},
	"Head": {
		"node": "Visual/Body/Head", "sprite": "Visual/Body/Head/Sprite",
		"attach_pos": Vector2(62.0, -231.0), "pivot_px": Vector2(340.0, 357.0),
	},
	"Face": {
		"node": "Visual/Body/Head/Face",
		"attach_pos": Vector2(0.0, 0.0), "pivot_px": Vector2(317.0, 301.0),
	},
}

## Коллайдер (прямоугольник по всему силуэту: торс + штаны + ноги + голова) — в пикселях арта.
const COLLIDER_SIZE := Vector2(541.0, 726.0)
const COLLIDER_OFFSET := Vector2(-5.0, -363.0)
## Зона касания игрока (Area2D HitBox) — чуть уже силуэта, по торсу.
const HITBOX_SIZE := Vector2(470.0, 620.0)
const HITBOX_OFFSET := Vector2(-5.0, -310.0)

# ============================================================================
# ЭКСПОРТ-НАСТРОЙКИ (крутить тут)
# ============================================================================
@export_group("Размер")
## Общий размер врага: 1.0 = пиксель в пиксель (фигура ~725 px высотой),
## 0.21 = примерно как герой. Применяется к Visual и к коллизии, НЕ к корню
## CharacterBody2D (иначе поехала бы физика).
@export_range(0.05, 2.0, 0.01) var enemy_scale: float = 0.21

@export_group("Бой")
## Сколько попаданий камнем держит враг.
@export var max_hp: float = 1.0
## Горизонтальная скорость погони, px/с.
@export var speed: float = 165.0
@export var gravity: float = 1400.0
## Урон касанием: игрок умирает от касания мгновенно, потому по умолчанию огромный.
@export var contact_damage: float = 999.0
## Пауза между ударами касанием, с.
@export var attack_cooldown: float = 1.0
## Сила отката от попадания камня, px/с.
@export var knockback: float = 300.0
## Сколько секунд врага тащит после попадания.
@export var knock_time: float = 0.22

@export_group("Анимация")
## Частота кадров бега (3 позы).
@export var pose_fps: float = 7.0
## Частота кадров idle (2 позы, медленнее).
@export var idle_pose_fps: float = 2.0

@export_group("Прочее")
## Сцена трупа (Corpse.tscn). Пусто — враг просто исчезает.
@export var corpse_scene: PackedScene
## Группа, в которой искать цель.
@export var target_group: StringName = &"player"

## Удар касанием, если цель не умеет take_damage(amount).
signal attacked(target: Node)
## Смерть (аргумент — сам враг).
signal died(enemy: Node)

# ============================================================================
# УЗЛЫ
# ============================================================================
@onready var visual: Node2D = $Visual
@onready var collider: CollisionShape2D = $Collider
@onready var hit_box: Area2D = $HitBox
@onready var hit_shape: CollisionShape2D = $HitBox/Shape
@onready var body: Node2D = $Visual/Body
@onready var head: Node2D = $Visual/Body/Head
@onready var face: Sprite2D = $Visual/Body/Head/Face
@onready var pants: Sprite2D = $Visual/Body/Pants
@onready var arm_l: Sprite2D = $Visual/Body/ArmL
@onready var arm_r: Sprite2D = $Visual/Body/ArmR
@onready var leg_l: Sprite2D = $Visual/Body/LegL
@onready var leg_r: Sprite2D = $Visual/Body/LegR

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
enum State { RUN, ATTACK, DEAD }

var _state: State = State.RUN
## Куда смотрит: -1 влево, +1 вправо.
var _look: int = ART_LOOK
var _pose_index: int = 0
var _pose_timer: float = 0.0
var _hp: float = 0.0
var _attack_timer: float = 0.0
var _face_timer: float = 0.0
var _knock_velocity := Vector2.ZERO
var _knock_timer: float = 0.0
## Игрок внутри HitBox (или null).
var _target: Node2D = null
var _applied_scale: float = -1.0

## Мёртвая зона разворота: при меньшем dx враг не дёргает зеркало туда-сюда.
const TURN_DEAD_ZONE := 8.0

# ============================================================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================================
func _ready() -> void:
	Rig.apply(self, RIG)   # расставляет суставы и спрайты по таблице RIG (см. выше)
	_hp = max_hp
	_pose_index = 0
	_apply_pose(_pose_for_state())
	_apply_enemy_scale()
	face.texture = FACE_IDLE
	hit_box.body_entered.connect(_on_hit_box_entered)
	hit_box.body_exited.connect(_on_hit_box_exited)


func _process(delta: float) -> void:
	_update_poses(delta)   # позы листаются рывком, с частотой pose_fps / idle_pose_fps
	_update_face(delta)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_move(delta)
	_update_state()
	_tick_attack(delta)


# ============================================================================
# ДВИЖЕНИЕ
# ============================================================================
func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, 2000.0)

	_knock_timer = maxf(_knock_timer - delta, 0.0)
	if _knock_timer > 0.0:
		# Откат от попадания: камень тащит врага, погоня на время забыта.
		velocity.x = _knock_velocity.x
		_knock_velocity = _knock_velocity.move_toward(Vector2.ZERO, knockback * 3.0 * delta)
	else:
		_chase(delta)

	move_and_slide()


## Погоня: бежим горизонтально к цели из группы target_group, нет цели — стоим.
func _chase(delta: float) -> void:
	var goal := get_tree().get_first_node_in_group(target_group) as Node2D
	if goal == null or _state == State.ATTACK:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		return
	var dx := goal.global_position.x - global_position.x
	if absf(dx) > TURN_DEAD_ZONE:
		_look = 1 if dx > 0.0 else -1
		_apply_enemy_scale()   # зеркалим визуал через scale.x
	velocity.x = move_toward(velocity.x, signf(dx) * speed, speed * 4.0 * delta)


func _update_state() -> void:
	var next: State = State.RUN
	if _target != null and is_instance_valid(_target):
		next = State.ATTACK
	if next != _state:
		_state = next
		_pose_index = 0   # смена состояния — поза переключается рывком
		_pose_timer = 0.0


# ============================================================================
# УДАР КАСАНИЕМ
# ============================================================================
func _tick_attack(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _state != State.ATTACK or _attack_timer > 0.0:
		return
	var target := _target
	if target == null or not is_instance_valid(target):
		return
	_attack(target)


## Если цель умеет take_damage(amount) — зовём его. Иначе удар касанием смертелен:
## у кого есть die() (герой) — тот умирает. Сигнал attacked — на будущую сцену смерти.
func _attack(target: Node) -> void:
	_attack_timer = attack_cooldown
	if target.has_method("take_damage"):
		target.call("take_damage", contact_damage)
		return
	attacked.emit(target)
	if target.has_method("die"):
		target.call("die")


func _on_hit_box_entered(other: Node2D) -> void:
	if not other.is_in_group(target_group):
		return
	_target = other
	_attack_timer = 0.0   # первое касание бьёт сразу, дальше — по attack_cooldown


func _on_hit_box_exited(other: Node2D) -> void:
	if other == _target:
		_target = null


# ============================================================================
# УРОН, ЛИЦО, СМЕРТЬ
# ============================================================================
## Камень попал: снимаем HP, откатываем по direction, на 2 позы подменяем лицо.
func take_hit(damage: float, direction: Vector2) -> void:
	if _state == State.DEAD:
		return
	_hp -= damage
	_knock_velocity = direction.normalized() * knockback
	_knock_timer = knock_time
	_face_timer = 2.0 / maxf(pose_fps, 0.001)   # ровно 2 позы бега
	face.texture = FACE_DAMAGE
	if _hp <= 0.0:
		_die()


func _update_face(delta: float) -> void:
	_face_timer = maxf(_face_timer - delta, 0.0)
	# Смена лица рывком, без плавности: пару поз лицо «урон», потом обратно.
	face.texture = FACE_DAMAGE if _face_timer > 0.0 else FACE_IDLE


func _die() -> void:
	if _state == State.DEAD:
		return
	_state = State.DEAD
	died.emit(self)
	if corpse_scene != null:
		var corpse := corpse_scene.instantiate()
		get_tree().current_scene.add_child(corpse)
		corpse.global_position = global_position
		if corpse.has_method("setup"):
			corpse.call("setup", enemy_scale, _look, _knock_velocity)
	queue_free()


# ============================================================================
# АНИМАЦИЯ (стоп-моушен: позы переключаются рывком с частотой pose_fps)
# ============================================================================
func _update_poses(delta: float) -> void:
	if _state == State.ATTACK:
		_apply_pose(ATTACK_POSE)
		return

	var moving := absf(velocity.x) > 8.0
	var fps := pose_fps if moving else idle_pose_fps
	var poses: Array = RUN_POSES if moving else IDLE_POSES
	var period := 1.0 / maxf(fps, 0.001)
	_pose_timer += delta
	while _pose_timer >= period:
		_pose_timer -= period
		_pose_index = (_pose_index + 1) % maxi(poses.size(), 1)
	_apply_pose(poses[_pose_index % poses.size()])


func _pose_for_state() -> Dictionary:
	if _state == State.ATTACK:
		return ATTACK_POSE
	var poses: Array = RUN_POSES
	return poses[_pose_index % poses.size()]


## Применяет позу: пивоты остаются на местах, меняются повороты и мелкие смещения.
func _apply_pose(p: Dictionary) -> void:
	body.position = _attach("Body") + (p["body_pos"] as Vector2)
	body.rotation = deg_to_rad(p["body_rot"] as float)
	# Head и Pants — дети Body: координаты локальные (attach_pos части в таблице RIG).
	head.position = _attach("Head") + (p["head_pos"] as Vector2)
	head.rotation = deg_to_rad(p["head_rot"] as float)
	pants.position = _attach("Pants") + (p["pants_pos"] as Vector2)
	pants.rotation = deg_to_rad(p["pants_rot"] as float)
	leg_l.position = _attach("LegL") + (p["leg_l_pos"] as Vector2)
	leg_l.rotation = deg_to_rad(p["leg_l_rot"] as float)
	leg_r.position = _attach("LegR") + (p["leg_r_pos"] as Vector2)
	leg_r.rotation = deg_to_rad(p["leg_r_rot"] as float)
	arm_l.rotation = deg_to_rad(p["arm_l_rot"] as float)
	arm_r.rotation = deg_to_rad(p["arm_r_rot"] as float)


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
## attach_pos части из таблицы RIG — «покой» сустава в координатах родителя.
func _attach(part_name: String) -> Vector2:
	return Rig.attach(RIG, part_name)


## Масштаб + зеркалирование делаем на узле Visual (не на CharacterBody2D!), чтобы
## физика не масштабировалась. Коллайдер и HitBox масштабируем числом, в коде.
func _apply_enemy_scale() -> void:
	var s := maxf(enemy_scale, 0.01)
	var mirror := 1.0 if _look == ART_LOOK else -1.0
	visual.scale = Vector2(s * mirror, s)
	if is_equal_approx(_applied_scale, s):
		return
	_applied_scale = s
	var rect := RectangleShape2D.new()
	rect.size = COLLIDER_SIZE * s
	collider.shape = rect
	collider.position = Vector2(COLLIDER_OFFSET.x * s * mirror, COLLIDER_OFFSET.y * s)
	var hit := RectangleShape2D.new()
	hit.size = HITBOX_SIZE * s
	hit_shape.shape = hit
	hit_shape.position = HITBOX_OFFSET * s

# --- лица (оверлеи поверх головы; Enemy_corpse учитывается отдельно) ---------
const FACE_IDLE: Texture2D = preload("res://Sprites/enemy/Enemy_idle_face.png")
const FACE_DAMAGE: Texture2D = preload("res://Sprites/enemy/Enemy_damage_face.png")

## Направление взгляда эталонного арта: враг нарисован смотрящим ВЛЕВО
## (обе стопы и челюсть смотрят влево). Значит «как нарисовано» = взгляд влево,
## а взгляд вправо — то же самое, но с Visual.scale.x = -enemy_scale.
const ART_LOOK: int = -1

# ============================================================================
# ТАБЛИЦЫ ПОЗ (крутить тут)
# Обязательные ключи: body_pos, body_rot, head_pos, head_rot, pants_pos,
#   pants_rot, leg_l_pos, leg_l_rot, leg_r_pos, leg_r_rot, arm_l_rot, arm_r_rot.
# Углы в градусах: положительный = по часовой стрелке (ось Y вниз). Угол 0 —
# положение из таблицы RIG (то есть ровно как на эталоне).
# Ноги — дети Body: когда тело приподнято (body_pos.y < 0), ноги компенсируют это
# своим leg_*_pos.y, чтобы опорная нога осталась на земле.
# ============================================================================

## Idle: 2 позы, «дыхание» на 1 px, руки чуть качаются.
const IDLE_POSES: Array = [
	{
		"body_pos": Vector2(0.0, 0.0), "body_rot": 0.0,
		"head_pos": Vector2(0.0, 0.0), "head_rot": -1.0,
		"pants_pos": Vector2(0.0, 0.0), "pants_rot": 1.0,
		"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": 0.0,
		"leg_r_pos": Vector2(0.0, 0.0), "leg_r_rot": 0.0,
		"arm_l_rot": 2.0, "arm_r_rot": -2.0,
	},
	{
		"body_pos": Vector2(0.0, -1.0), "body_rot": 1.0,
		"head_pos": Vector2(0.0, -1.0), "head_rot": 1.0,
		"pants_pos": Vector2(0.0, 1.0), "pants_rot": -1.0,
		"leg_l_pos": Vector2(0.0, 1.0), "leg_l_rot": 1.0,
		"leg_r_pos": Vector2(0.0, 1.0), "leg_r_rot": -1.0,
		"arm_l_rot": -3.0, "arm_r_rot": 3.0,
	},
]

## Бег: 3 рывковых «кадра» (pose_fps ≈ 7). Ноги поочерёдно вперёд/назад ±16°,
## тело подпрыгивает на 2-5 px, руки машут в противофазе, голова кивает, пояс качается.
const RUN_POSES: Array = [
	# 0 — контакт: дальняя (левая) нога вперёд
	{
		"body_pos": Vector2(0.0, -2.0), "body_rot": -2.0,
		"head_pos": Vector2(0.0, 0.0), "head_rot": 2.0,
		"pants_pos": Vector2(0.0, 0.0), "pants_rot": -3.0,
		"leg_l_pos": Vector2(0.0, 2.0), "leg_l_rot": -16.0,
		"leg_r_pos": Vector2(0.0, 2.0), "leg_r_rot": 14.0,
		"arm_l_rot": 13.0, "arm_r_rot": 11.0,
	},
	# 1 — проход: тело выше, обе ноги поджаты (миг «полёта»)
	{
		"body_pos": Vector2(0.0, -5.0), "body_rot": 0.0,
		"head_pos": Vector2(0.0, -1.0), "head_rot": -1.0,
		"pants_pos": Vector2(0.0, 1.0), "pants_rot": 0.0,
		"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": 2.0,
		"leg_r_pos": Vector2(0.0, 0.0), "leg_r_rot": -3.0,
		"arm_l_rot": -8.0, "arm_r_rot": -8.0,
	},
	# 2 — контакт: ближняя (правая) нога вперёд (не точное зеркало позы 0)
	{
		"body_pos": Vector2(0.0, -2.0), "body_rot": 2.0,
		"head_pos": Vector2(0.0, 0.0), "head_rot": -2.0,
		"pants_pos": Vector2(0.0, 0.0), "pants_rot": 3.0,
		"leg_l_pos": Vector2(0.0, 2.0), "leg_l_rot": 15.0,
		"leg_r_pos": Vector2(0.0, 2.0), "leg_r_rot": -16.0,
		"arm_l_rot": -12.0, "arm_r_rot": -9.0,
	},
]

## Атака: наклон вперёд (в сторону взгляда), обе руки вскинуты, голова вжата.
const ATTACK_POSE: Dictionary = {
	"body_pos": Vector2(-3.0, 0.0), "body_rot": -7.0,
	"head_pos": Vector2(0.0, 1.0), "head_rot": -3.0,
	"pants_pos": Vector2(0.0, 0.0), "pants_rot": -2.0,
	"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": -6.0,
	"leg_r_pos": Vector2(0.0, 0.0), "leg_r_rot": 8.0,
	"arm_l_rot": 22.0, "arm_r_rot": -24.0,
}
