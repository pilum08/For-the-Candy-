extends RigidBody2D
## ТРУП врага: ОДИН спрайт Enemy_corpse.png, физический объект — лежит там, где упал,
## его можно толкнуть или сбить камнем. Таймера удаления НЕТ: тела нужны для
## головоломки с ямой, поэтому они остаются лежать весь уровень.
##
## Начало координат = точка картинки, которой труп касается земли.
## Картинка нарисована головой ВПРАВО, поэтому если враг умирал «глядя влево»,
## зеркалим дочерний узел Visual (scale.x = -1), а не сам RigidBody2D (иначе поехала
## бы физика). Коллизия живёт в отдельном узле и тоже зеркалится сдвигом.
##
## ГЕОМЕТРИЯ — снята с Enemy_corpse.png (784x589), в её пикселях:
##   силуэт (1,1)..(783,588); голова (жёлтое) x 305..710; футболка x 62..369;
##   штаны x 62..182; ось тела по y ≈ 284; низ силуэта y = 588 (подбородок головы —
##   самая нижняя нарисованная точка, ниже всех остальных частей тела).
##   Коллайдер — капсула вдоль тела (поворот 90°), её нижняя точка тоже = 588 = низ
##   картинки, поэтому труп лежит на земле, а не висит и не проваливается.
##
## КАК ПОПРАВИТЬ ФОРМУ ВРУЧНУЮ: открой Corpse.tscn → узел Collider. В инспекторе:
##   CapsuleShape2D → radius (толщина трупа) и height (длина от головы до штанов);
##   CollisionShape2D → position (сдвиг капсулы) и rotation_degrees (наклон).
##   Числа продублированы в скрипте константами CAPSULE_* — они базовые (до
##   enemy_scale), скрипт пересчитывает форму на старте. Меняй в скрипте, а сцену
##   правь уже для наглядности в редакторе.
##
## mass / linear_damp / angular_damp — это штатные свойства RigidBody2D: они уже
## есть в инспекторе, отдельные @export не нужны (был бы конфликт имён).

@export_group("Размер")
## Тот же масштаб, что у врага (Enemy.enemy_scale): сцена трупа его получает в setup().
@export_range(0.05, 2.0, 0.01) var enemy_scale: float = 0.21

@export_group("Прочее")
## Насколько сильно труп проворачивает в момент падения (рад/с, в обе стороны).
@export var spin_on_spawn: float = 2.5
## Насколько труп кувыркается, когда его бросает игрок (рад/с, в обе стороны).
@export var throw_spin: float = 3.0

@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite
@onready var collider: CollisionShape2D = $Collider

## Точка картинки, которая встаёт в начало координат: низ силуэта (самый нижний
## нарисованный пиксель, y = 588), середина трупа по x. Труп кладут этой точкой на пол,
## поэтому арт не должен уходить ниже неё — иначе видимый низ картинки «утонет» в земле.
const CORPSE_PIVOT := Vector2(363.0, 588.0)
## Капсула по телу: толщина, длина и центр — пиксели арта, до масштаба.
## CAPSULE_CENTER.y = -CAPSULE_RADIUS, то есть низ капсулы ровно в начале координат
## (в пивоте = низу силуэта): когда труп осел, капсула, пивот и рисунок лежат на одной линии.
const CAPSULE_RADIUS := 190.0
const CAPSULE_HEIGHT := 648.0
const CAPSULE_CENTER := Vector2(23.0, -190.0)

## 1 = картинка как есть (голова вправо), -1 = зеркало (голова влево).
var _mirror: float = 1.0

## Гнездо носильщика, куда труп переезжает в руки. Лежит ВНУТРИ Visual героя
## (Player.tscn → Visual/Body/CarryPoint), поэтому труп едет за героем, зеркалится его
## scale.x и рисуется между юбкой и головой; руки героя при переноске поднимаются выше.
const CARRY_POINT := ^"Visual/Body/CarryPoint"

## Кто несёт труп (null — труп лежит сам по себе).
var _carrier: Node = null
## Родитель, в который труп вернётся при опускании/броске (обычно мир).
var _home_parent: Node = null
## Слои до подбора: в руках они погашены, при возврате восстанавливаются как были.
var _saved_layer: int = 0
var _saved_mask: int = 0
## Зеркало до подбора: в руках труп «головой вправо» (зеркалит носильщик), при возврате
## ставим прежнее — как труп лежал.
var _saved_mirror: float = 1.0
## Мировой масштаб арта (visual.global_scale) ДО подбора: и размер, и знак зеркала «как лежал».
## В руках труп должен выглядеть ровно так же, как на земле, а после броска/опускания — вернуть
## этот размер, поэтому он и запоминается, а не берётся из enemy_scale.
var _saved_global_scale: Vector2 = Vector2.ONE
## Есть ли что возвращать: true от подбора до restore_physics(). Без подбора возвращать нечего —
## иначе труп, которого никто не брал, получил бы чужие (нулевые) слои и маски.
var _saved_valid: bool = false


func _ready() -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_scale()


## Вызывает Enemy при смерти: масштаб, куда смотрел враг, импульс удара.
func setup(scale_value: float, look: int, impulse: Vector2) -> void:
	enemy_scale = scale_value
	# Труп нарисован головой ВПРАВО: смерть «глядя влево» (look = -1) — зеркалим.
	_mirror = 1.0 if look > 0 else -1.0
	_apply_scale()
	# Стартовый импульс по направлению удара плюс небольшое случайное вращение.
	apply_central_impulse(impulse * mass)
	if spin_on_spawn > 0.0:
		apply_torque_impulse(randf_range(-spin_on_spawn, spin_on_spawn) * mass)


## Взяли в руки: труп «замерзает» и переезжает в CarryPoint носильщика, то есть едет
## за ним сам. Слои в руках ГАСИМ (0/0): враги и снаряды труп в руках не замечают,
## да и упасть он не может — физика выключена (freeze).
## scale_mult — размер в руках относительно обычного (Player.carried_scale_mult).
func pickup(carrier: Node, scale_mult: float = 1.0) -> void:
	if _carrier != null or carrier == null:
		return
	_carrier = carrier
	_home_parent = get_parent()
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_saved_mirror = _mirror
	# Размер и зеркало запоминаем ДО переноса: гнездо лежит внутри Visual героя, то есть после
	# переноса труп унаследовал бы player_scale и стал бы меньше, чем лежал на земле.
	_saved_global_scale = visual.global_scale
	_saved_valid = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	var point := carrier.get_node_or_null(CARRY_POINT) as Node2D
	if point == null:
		point = carrier as Node2D
	# Гнездо уже растянуто носильщиком (лежит внутри его Visual) — берём этот масштаб,
	# чтобы вернуть трупу его обычный размер, а не art_scale раз меньше.
	var nest_scale := _global_scale(point)
	reparent(point)
	# Встаём ровно в гнездо и без остатков физики: локально ничего не крутим и не зеркалим —
	# поворот, зеркало и масштаб трупу даёт сам носильщик, поэтому «голова вперёд по взгляду»
	# получается сама, а у лежащего на земле трупа ничего не меняется.
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	_mirror = 1.0
	# Тот же размер, что на земле: модуль запомненного мирового масштаба умножаем на
	# carried_scale_mult (1 = как лежал) и делим на масштаб гнезда, в котором сидит player_scale.
	# Знак по X не задаём совсем — его даёт зеркало носильщика, поэтому труп сам разворачивается
	# за взглядом героя, а размер остаётся мировым.
	var m := maxf(absf(_saved_global_scale.y), 0.0001) * maxf(scale_mult, 0.01)
	visual.scale = Vector2(m / absf(nest_scale.x), m / absf(nest_scale.y))


## Опустили перед собой (E второй раз): возврат слоёв и физики плюс лёгкий толчок вперёд.
func put_down(at: Vector2, impulse: Vector2) -> void:
	if _carrier == null:
		return
	restore_physics()
	global_position = at
	global_rotation = 0.0
	linear_velocity = impulse


## Бросили: труп покидает CarryPoint и летит по дуге — дальше обычная физика RigidBody2D.
func launch(dir: Vector2, speed: float) -> void:
	if _carrier == null:
		return
	restore_physics()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	linear_velocity = dir.normalized() * speed
	if throw_spin > 0.0:
		angular_velocity = randf_range(-throw_spin, throw_spin)


## Возврат трупа из рук в мир: ровно то, что запомнил pickup — родитель, слои, маски, коллизия
## и физика (freeze), а вид (масштаб, зеркало, поворот) — как труп лежал на земле.
## Зовут и опускание (put_down), и бросок (launch); позицию/скорость задают они.
## Без подбора возвращать нечего — метод молчит, чтобы не тронуть лежащий труп чужими значениями.
func restore_physics() -> void:
	if not _saved_valid:
		return
	_carrier = null
	if _home_parent != null and is_instance_valid(_home_parent):
		reparent(_home_parent)
	_home_parent = null
	freeze = false
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	scale = Vector2.ONE
	rotation = 0.0
	_mirror = _saved_mirror
	_apply_scale()
	# Коллизия гарантированно рабочая: включена, без чужих масштабов (размер формы — в _apply_scale).
	collider.disabled = false
	collider.scale = Vector2.ONE
	# Мировой размер возвращаем ровно таким, каким труп был до подбора: берём МОДУЛЬ
	# запомненного масштаба и делим на масштаб нового родителя (обычно это мир, scale = 1).
	# Знак задаём сами по _saved_mirror (по X). Готовый scale из Godot для этого не годится:
	# у зеркального узла (det < 0) глобальный scale подписан как (0.21, -0.21), и если
	# подставить его как есть, труп получит переворот по Y — арт уедет под пол.
	var m := maxf(absf(_saved_global_scale.y), 0.0001)
	var parent_scale := _global_scale(get_parent() as Node2D)
	visual.scale = Vector2(m * _saved_mirror / parent_scale.x, m / parent_scale.y)
	_saved_valid = false


## Мировой масштаб узла — с учётом зеркала (по X) и с защитой от нуля, чтобы деление на него
## не ломало размер трупа. Гнездо трупа лежит внутри Visual героя, поэтому в его масштабе уже
## сидит player_scale: именно на него и делим, чтобы получить нужный МИРОВОЙ размер.
func _global_scale(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ONE
	var s := node.global_scale
	return Vector2(
		1.0 if is_zero_approx(s.x) else s.x,
		1.0 if is_zero_approx(s.y) else s.y
	)


## Масштаб и зеркало визуала; форма коллизии — числом в коде (физика не масштабируется).
func _apply_scale() -> void:
	var s := maxf(enemy_scale, 0.01)
	visual.scale = Vector2(s * _mirror, s)
	sprite.offset = -CORPSE_PIVOT
	var cap := CapsuleShape2D.new()
	cap.radius = CAPSULE_RADIUS * s
	cap.height = maxf(CAPSULE_HEIGHT * s, cap.radius * 2.0)
	collider.shape = cap
	collider.rotation_degrees = 90.0
	collider.position = Vector2(CAPSULE_CENTER.x * s * _mirror, CAPSULE_CENTER.y * s)