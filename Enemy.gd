extends CharacterBody2D
## ВРАГ: бежит к игроку, бьёт касанием, умирает от камней. Анимация стоп-моушен
## (позы переключаются рывком).
##
## ВИД врага живёт в паспорте MobRigData (у жёлтого — enemy_yellow.tres): из чего моб
## собран, как ходит и стоит, какие у него лица и труп. Дерево узлов и анимацию по этому
## паспорту собирает MobVisual, поэтому в сцене врага узлов частей нет — только Visual
## и коллизии. Здесь остаётся ПОВЕДЕНИЕ: погоня, удар касанием, урон, смерть, труп.
##
## Новый вид моба = свой MobRigData (+ своя сцена трупа при другом арте трупа) и, если
## нужно другое поведение, скрипт-наследник этого (прыжок, дальний бой, свой урон).
##
## Позы удара (ATTACK_POSE ниже) — часть поведения, поэтому лежат здесь: MobVisual
## показывает их через hold_pose(), а ходьбу и покой листает сам по паспорту.
## Углы в градусах, смещения — в пикселях АРТА (умножаются на art_scale моба).
## Микро-джиттер (±1-2 px, ±2°) вшит прямо в числа поз — никакого Random в рантайме
## (случайным остался только проворот трупа в момент смерти, см. Corpse.gd).

# ============================================================================
# ГЕОМЕТРИЯ ФИЗИКИ — всё, что осталось в скрипте от сборки тела.
# Сам вид (части, суставы, позы, лица) — в паспорте MobRigData, тут только коллизии
# в пикселях арта. Начало координат врага = центр между стопами на земле (как у игрока).
# ============================================================================
const MobVisual := preload("res://MobVisual.gd")     # визуал: собирает дерево по паспорту
const MobRigData := preload("res://MobRigData.gd")   # тип паспорта (нужен только для типов)
const MobDeathBurst := preload("res://MobDeathBurst.gd")   # разлёт частей, когда труп не положен
## Группа контроллера уровня (main.tscn) — у него спрашиваем лимит трупов (см. _die).
const LEVEL_CONTROLLER_GROUP: StringName = &"level_controller"


## Коллайдер (прямоугольник по всему силуэту: торс + штаны + ноги + голова) — в пикселях арта.
const COLLIDER_SIZE := Vector2(541.0, 726.0)
const COLLIDER_OFFSET := Vector2(-5.0, -363.0)
## Зона касания игрока (Area2D HitBox) — чуть уже силуэта, по торсу.
const HITBOX_SIZE := Vector2(470.0, 620.0)
const HITBOX_OFFSET := Vector2(-5.0, -310.0)

# ============================================================================
# ЭКСПОРТ-НАСТРОЙКИ (крутить тут)
# ============================================================================
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
## Визуал моба: дерево частей, позы и лицо собираются по паспорту (см. MobRigData.gd).
@onready var visual: MobVisual = $Visual
@onready var collider: CollisionShape2D = $Collider
@onready var hit_box: Area2D = $HitBox
@onready var hit_shape: CollisionShape2D = $HitBox/Shape

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
enum State { RUN, ATTACK, DEAD }

var _state: State = State.RUN
## Куда смотрит: -1 влево, +1 вправо.
var _look: int = ART_LOOK
var _hp: float = 0.0
var _attack_timer: float = 0.0
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
	# Дерево частей, поза покоя и лицо уже собраны MobVisual: он ребёнок, его _ready идёт раньше.
	_hp = max_hp
	_apply_enemy_scale()
	hit_box.body_entered.connect(_on_hit_box_entered)
	hit_box.body_exited.connect(_on_hit_box_exited)


func _process(_delta: float) -> void:
	if _state == State.ATTACK:
		visual.hold_pose(ATTACK_POSE)   # удар: разовая поза, листание стоит
		return
	visual.release_pose()               # вернулись к бегу/покою — листаем с первого кадра
	visual.set_moving(absf(velocity.x) > 8.0)


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
		_state = next   # смена состояния: поза переключается рывком (см. MobVisual.hold_pose)


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
	visual.flash_damage_face()   # лицо «урон» на 2 кадра бега (потом MobVisual вернёт покой)
	if _hp <= 0.0:
		_die()


func _die() -> void:
	if _state == State.DEAD:
		return
	_state = State.DEAD
	died.emit(self)
	# Труп не положен — моб разлетается на части (MobDeathBurst.gd) в двух случаях, по порядку:
	#   1) какая-то яма уже заполнена целиком и выпал шанс decay_chance_when_pit_full;
	#   2) место под труп исчерпано (лимит LevelController.can_spawn_corpse()).
	# Иначе — обычный труп. Контроллера в сцене нет — труп как раньше.
	var controller := get_tree().get_first_node_in_group(LEVEL_CONTROLLER_GROUP) as LevelController
	var decay := false
	if controller != null:
		if controller.is_any_pit_full() and randf() < controller.decay_chance_when_pit_full:
			decay = true
		elif not controller.can_spawn_corpse():
			decay = true
	if decay:
		_burst_parts()
	else:
		_spawn_corpse()
	queue_free()


## Труп моба: corpse_scene создаётся в мире и получает вид, взгляд и откат от попадания.
## corpse_scene пусто — враг просто исчезает (как раньше).
func _spawn_corpse() -> void:
	if corpse_scene == null:
		return
	var corpse := corpse_scene.instantiate()
	get_tree().current_scene.add_child(corpse)
	corpse.global_position = global_position
	if corpse.has_method("setup"):
		corpse.call("setup", visual.art_scale(), _look, _knock_velocity)


## Вместо трупа (лимит исчерпан): моб разлетается на части (MobDeathBurst.gd). Узел живёт
## дочерним у врага и уходит вместе с ним; обломки кладутся в мир и гаснут, уехав за экран.
func _burst_parts() -> void:
	var burst := MobDeathBurst.new() as Node2D
	burst.name = "MobDeathBurst"
	add_child(burst)
	burst.call(&"burst", rig(), global_position, visual.art_scale(), _look)


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
## Паспорт моба (MobRigData): из чего собран, как ходит, какие лица и труп.
## Нужен наследникам и отладке; править вид на ходу не нужно — он в .tres у Visual.
func rig() -> MobRigData:
	return visual.rig


## Сустав визуала по имени части из паспорта ("Body", "ArmR", "Face") — сюда наследник
## вешает своё (дуло, точку вылета камня, эффект). null — такой части в паспорте нет.
func part(part_name: String) -> Node2D:
	return visual.part(part_name)


## Масштаб + зеркалирование делаем на узле Visual (не на CharacterBody2D!), чтобы
## физика не масштабировалась. Коллайдер и HitBox масштабируем числом, в коде.
func _apply_enemy_scale() -> void:
	var s := visual.art_scale()   # масштаб арта — из паспорта моба (MobRigData.art_scale)
	var mirror := 1.0 if _look == ART_LOOK else -1.0
	visual.set_art_transform(mirror)   # зеркалим scale.x у Visual, физику корня не трогаем
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

## Направление взгляда эталонного арта: враг нарисован смотрящим ВЛЕВО
## (обе стопы и челюсть смотрят влево). Значит «как нарисовано» = взгляд влево,
## а взгляд вправо — то же самое, но с Visual.scale.x = -art_scale.
const ART_LOOK: int = -1

# ============================================================================
# ПОЗА УДАРА (крутить тут)
# Ходьба и покой живут в паспорте моба (MobRigData: walk_poses / idle_poses) —
# их листает MobVisual. Здесь только поза поведения: её MobVisual держит через
# hold_pose, пока враг в State.ATTACK.
# Ключи кадра — "<ключ>_pos" / "<ключ>_rot" по именам частей паспорта: body, head,
#   pants, leg_l, leg_r, arm_l, arm_r (см. MobVisual._pose_key). Углы в градусах:
#   положительный = по часовой стрелке (ось Y вниз), 0 — положение из паспорта.
# Ноги — дети Body: когда тело приподнято (body_pos.y < 0), ноги компенсируют это
# своим leg_*_pos.y, чтобы опорная нога осталась на земле.
# ============================================================================

## Атака: наклон вперёд (в сторону взгляда), обе руки вскинуты, голова вжата.
const ATTACK_POSE: Dictionary = {
	"body_pos": Vector2(-3.0, 0.0), "body_rot": -7.0,
	"head_pos": Vector2(0.0, 1.0), "head_rot": -3.0,
	"pants_pos": Vector2(0.0, 0.0), "pants_rot": -2.0,
	"leg_l_pos": Vector2(0.0, 0.0), "leg_l_rot": -6.0,
	"leg_r_pos": Vector2(0.0, 0.0), "leg_r_rot": 8.0,
	"arm_l_rot": 22.0, "arm_r_rot": -24.0,
}
