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
## ВИД И МАСШТАБ — из паспорта моба (поле mob_rig, например enemy_yellow.tres):
##   картинка ← MobRigData.corpse_texture (пусто — картинка из этой сцены),
##   масштаб  ← MobRigData.art_scale (тот же, что у живого моба).
## Поэтому труп нового вида моба = копия этой сцены со своим mob_rig. Но ГЕОМЕТРИЯ ниже
## (пивот картинки и коллизия) общая для всех трупов: под сильно другой арт правь
## CORPSE_PIVOT и CAPSULE_* — или заведи рядом второй набор констант.
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

const MobRigData := preload("res://MobRigData.gd")   # тип паспорта моба (нужен только для типов)

@export_group("Вид моба")
## Паспорт моба (MobRigData, например enemy_yellow.tres): отсюда труп берёт картинку
## (corpse_texture) и масштаб (art_scale). Пусто — вид целиком из этой сцены.
@export var mob_rig: MobRigData

@export_group("Размер")
## Масштаб трупа: при смерти врага его задаёт setup() (масштаб самого моба), а у трупа,
## выставленного в сцене руками, — паспорт моба (MobRigData.art_scale) или это значение.
@export_range(0.05, 2.0, 0.01) var enemy_scale: float = 0.21

@export_group("Прочее")
## Насколько сильно труп проворачивает в момент падения (рад/с, в обе стороны).
@export var spin_on_spawn: float = 2.5
## Насколько труп кувыркается, когда его бросает игрок (рад/с, в обе стороны).
@export var throw_spin: float = 3.0

@export_group("Отрисовка")
## Мировая высота лежащего трупа: его z_index в мире (при z_as_relative = true), пока труп НЕ в
## руках. Части героя (руки, торс, голова) — z = 0, поэтому -1 = «труп позади Дона» (кисть и ноги
## героя видны поверх него), а 1 = «труп перед Доном» (труп прикроет и кисть). Задано явно здесь,
## а не порядком узлов: при равных z порядок решает список детей, и труп оказывался поверх героя
## только потому, что лежал последним в World, — на это опираться нельзя.
@export var corpse_world_z: int = -1

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
## Отрисовка «как в сцене»: относительность z и «рисоваться за родителем». Снимок делает
## save_z() (при старте и при подборе), возврат — restore_z(). Сам z в мире НЕ снимок, а явное
## правило corpse_world_z (см. @export выше): лежащий труп — позади героя, независимо от того,
## каким по счёту он лежит в World.
var _saved_z_relative: bool = true
var _saved_show_behind_parent: bool = false
## Место трупа в списке детей родителя до подбора. reparent() кладёт узел в КОНЕЦ списка, а в 2D
## порядок рисования — это и есть порядок списка: возвращаем труп на прежнее место, чтобы не
## поехал порядок СРЕДИ ТРУПОВ (у всех один и тот же corpse_world_z). На то, кто выше — труп или
## герой, этот индекс не влияет: это решает corpse_world_z.
var _saved_home_index: int = -1
## Есть ли что возвращать: true от подбора до restore_physics(). Без подбора возвращать нечего —
## иначе труп, которого никто не брал, получил бы чужие (нулевые) слои и маски.
var _saved_valid: bool = false


func _ready() -> void:
	_apply_rig()   # вид из паспорта моба (если он задан) — до масштаба: он берётся оттуда же
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	save_z()      # «как в сцене»: относительность z и «рисоваться за родителем»
	restore_z()   # и мировой z по явному правилу corpse_world_z (труп на земле — позади героя)
	_apply_scale()


## Вид из паспорта моба: картинка трупа (corpse_texture) и масштаб (art_scale). Зовётся в _ready.
## Смерть врага переписывает масштаб в setup() — это то же самое число, если .tres один и тот же
## (Enemy отдаёт visual.art_scale, то есть MobRigData.art_scale).
func _apply_rig() -> void:
	if mob_rig == null:
		return
	enemy_scale = mob_rig.art_scale
	var path := mob_rig.corpse_texture
	if path.is_empty():
		return   # про картинку паспорт ничего не сказал — оставляем ту, что стоит в сцене
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("Corpse (%s): не загрузилась текстура трупа %s" % [name, path])
		return
	sprite.texture = tex


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
## scale_mult — размер в руках относительно обычного: -1 (по умолчанию) — взять у носильщика
## (Player.carried_scale_mult, см. свойство carried_scale_mult ниже). Так зовёт Player.
func pickup(carrier: Node, scale_mult: float = -1.0) -> void:
	if _carrier != null or carrier == null:
		return
	_carrier = carrier
	if scale_mult < 0.0:
		scale_mult = carried_scale_mult   # настройка носильщика: Player.carried_scale_mult
	_home_parent = get_parent()
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_saved_mirror = _mirror
	save_z()   # отрисовка «как в сцене»: вернуть её будет restore_z() при опускании/броске
	_saved_home_index = get_index()
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
	# В руках у трупа свой порядок отрисовки: он — деталь гнезда в группе героя, поэтому z берём
	# «как у детали» (0), а НЕ мировой corpse_world_z — иначе труп выпрыгнул бы из-за спины героя.
	# Пока труп в руках, кисти героя подняты (Player.raise_arm_z): кисть задней руки видна поверх
	# трупа, передняя спрятана. Возврат — Corpse.restore_z (свой z) и Player.restore_z (руки).
	z_index = 0
	z_as_relative = true
	show_behind_parent = false
	# Тот же размер, что на земле: модуль запомненного мирового масштаба умножаем на
	# carried_scale_mult (1 = как лежал) и делим на масштаб гнезда, в котором сидит player_scale.
	# Знак по X не задаём совсем — его даёт зеркало носильщика, поэтому труп сам разворачивается
	# за взглядом героя, а размер остаётся мировым.
	var m := maxf(absf(_saved_global_scale.y), 0.0001) * maxf(scale_mult, 0.01)
	visual.scale = Vector2(m / absf(nest_scale.x), m / absf(nest_scale.y))


## Опустили перед собой (E второй раз): возврат слоёв и физики плюс лёгкий толчок вперёд.
## impulse оставлен для старых вызовов; интерфейс группы "carryables" зовёт put_down(at) —
## тогда толчка нет («положить» без броска, как и было у Player).
func put_down(at: Vector2, impulse: Vector2 = Vector2.ZERO) -> void:
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


# ============================================================================
# ИНТЕРФЕЙС ГРУППЫ "carryables" (так с предметами в руках работает Player)
# Ровно те же подбор / бросок / «положить», что и выше: use_action — это старый бросок по ЛКМ,
# put_down — старое «положить» по E. Механика не менялась, добавлены только входные точки.
# ============================================================================
## Запасные числа броска: те же, что стоят в Player по умолчанию (если носильщик их не отдал).
const DEFAULT_THROW_SPEED_MIN := 450.0
const DEFAULT_THROW_SPEED_MAX := 1200.0
const DEFAULT_THROW_FULL_DISTANCE := 500.0

## Смещение гнезда предмета, когда он в руках, в МИРОВЫХ пикселях: x — вперёд по взгляду.
## У трупа своих чисел нет: сдвиг живёт в инспекторе ГЕРОЯ (Player.carry_offset_x/y, пиксели
## арта), поэтому труп отдаёт их носильщику как есть — с переводом в мировые пиксели.
var carry_offset: Vector2:
	get:
		var ox: Variant = _carrier_prop(&"carry_offset_x")
		var oy: Variant = _carrier_prop(&"carry_offset_y")
		if ox == null or oy == null:
			return Vector2.ZERO
		return Vector2(float(ox), float(oy)) * _carrier_art_scale()


## Размер трупа в руках относительно обычного: у трупа это Player.carried_scale_mult.
var carried_scale_mult: float:
	get:
		var value: Variant = _carrier_prop(&"carried_scale_mult")
		return 1.0 if value == null else float(value)


## Множитель скорости ходьбы носильщика, пока труп в руках: Player.carry_speed_mult.
var carry_speed_mult: float:
	get:
		var value: Variant = _carrier_prop(&"carry_speed_mult")
		return 1.0 if value == null else float(value)


## ЛКМ с трупом в руках: бросок в сторону точки прицела. Это тот же бросок, что делал
## Player._use_item: направление — от гнезда к курсору, скорость растёт с расстоянием.
## Числа броска труп берёт у носильщика (Player.throw_speed_min/max, throw_full_distance),
## чтобы ручки в инспекторе героя продолжали работать; нет их — значения по умолчанию.
## Летит труп через существующий launch(): сама механика полёта не менялась.
func use_action(aim_point: Vector2) -> void:
	if _carrier == null:
		return
	var to_aim := aim_point - global_position
	var direction := Vector2.RIGHT
	var distance := to_aim.length()
	if distance >= 1.0:
		direction = to_aim / distance
	var full := maxf(_carrier_float(&"throw_full_distance", DEFAULT_THROW_FULL_DISTANCE), 1.0)
	var t := clampf(distance / full, 0.0, 1.0)
	launch(direction, lerpf(
		_carrier_float(&"throw_speed_min", DEFAULT_THROW_SPEED_MIN),
		_carrier_float(&"throw_speed_max", DEFAULT_THROW_SPEED_MAX),
		t
	))


## Свойство носильщика по имени (null — носильщика нет или свойства у него нет): так труп берёт
## настройки переноски и броска у того, кто его несёт (у героя они лежат в Player).
func _carrier_prop(prop: StringName) -> Variant:
	if _carrier == null or not is_instance_valid(_carrier):
		return null
	return _carrier.get(prop)


## Числовая настройка носильщика с запасным значением.
func _carrier_float(prop: StringName, fallback: float) -> float:
	var value: Variant = _carrier_prop(prop)
	return fallback if value == null else float(value)


## Масштаб арта носильщика (у героя art_scale × player_scale): числа carry_offset_x/y заданы в
## пикселях арта, а интерфейс carryables — в мировых пикселях.
func _carrier_art_scale() -> float:
	var art: Variant = _carrier_prop(&"art_scale")
	var player_size: Variant = _carrier_prop(&"player_scale")
	if art == null or player_size == null:
		return 1.0
	return maxf(float(art), 0.01) * maxf(float(player_size), 0.01)


## Запомнить отрисовку «как в сцене»: относительность z и «рисоваться за родителем».
## Зовётся при старте (чтобы снимок был до первого restore_z) и при подборе (pickup).
func save_z() -> void:
	_saved_z_relative = z_as_relative
	_saved_show_behind_parent = show_behind_parent


## ЕДИНСТВЕННЫЙ возврат отрисовки на землю: z — явное правило corpse_world_z (лежащий труп
## позади героя), относительность и «за родителем» — как в сцене. Зовут: опускание (put_down) и
## бросок (launch) через restore_physics, а также Player.restore_z — чтобы у опускания, броска и
## смерти это был ровно один и тот же возврат. Идемпотентен: повторный вызов ничего не меняет.
func restore_z() -> void:
	z_index = corpse_world_z
	z_as_relative = _saved_z_relative
	show_behind_parent = _saved_show_behind_parent


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
		# reparent() добавляет узел в конец списка детей, а в 2D порядок рисования — это и есть
		# порядок списка: возвращаем труп на прежнее место, чтобы не поехал порядок среди самих
		# трупов. Кто выше — труп или герой — решает не индекс, а corpse_world_z (см. restore_z).
		if _saved_home_index >= 0:
			_home_parent.move_child(self, clampi(_saved_home_index, 0, _home_parent.get_child_count() - 1))
	_home_parent = null
	freeze = false
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	scale = Vector2.ONE
	rotation = 0.0
	_mirror = _saved_mirror
	# Порядок отрисовки — снова мировой: z по явному corpse_world_z (лежащий труп позади героя),
	# а относительность и «за родителем» — как в сцене (в руках труп рисовался деталью группы).
	restore_z()
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