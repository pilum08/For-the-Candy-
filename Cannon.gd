class_name Cannon
extends RigidBody2D
## ПУШКА — носимый предмет и оружие одного выстрела: пока она цела, её можно носить и класть,
## а по ЛКМ она один раз стреляет ядром (cannonball.tres через Projectile.tscn) и тут же ломается.
##
## ЧТО УМЕЕТ (интерфейс группы "carryables" — так с предметами в руках работает Player):
##   * pickup(carrier)       — в руки: замирает (freeze), слои 0/0 (её никто не замечает) и едет
##                             в гнезде носильщика; герой идёт медленнее (carry_speed_mult 0.7);
##   * put_down(position)    — на землю по E: снова твёрдая, целая и снова подбирается;
##   * use_action(aim_point) — ЛКМ: ВЫСТРЕЛ ядром по направлению на курсор (см. _fire), после
##                             чего пушка выпадает из рук и остаётся сломанной навсегда (_break_free).
##
## ВЫСТРЕЛ И ИСХОД ЗАБЕГА (LevelController):
##   * ядро летит по дуге, пробивает мобов, снимает HP башни (cannonball.tres) и сообщает о себе
##     сигналами: hit_tower — попало в башню, missed — ушло в землю/время/за экран;
##   * попало в башню и та разрушилась → Tower.destroyed → LevelController.win() (победа);
##   * попало в башню, но HP осталось → fail("башня уцелела");
##   * ушло впустую (промах) → fail("промах").
##   Исход объявляется ровно один раз и только после исчезновения ядра (см. _on_ball_gone).
##
## РАЗМЕР И ЗЕРКАЛО — ТОЛЬКО У ДОЧЕРНЕГО УЗЛА Body (Sprite2D, CollisionShape2D, Marker2D):
## корневой RigidBody2D всегда scale = Vector2.ONE, иначе ломается физика. Мировой размер берётся
## из ЕДИНОГО МАСШТАБА АРТА (ArtScale, docs/SETUP.md раздел 16): картинка нарисована 1:1 вместе
## с героем, поэтому Body.scale = ArtScale.hero_scale() × native_mult × size_mult — тот же
## коэффициент, что у героя (сейчас 0.21, то есть 630 px картинки → 132 px в мире). Картинка,
## коллизия и маркер дула стоят в ПИКСЕЛЯХ КАРТИНКИ и масштабируются одной и той же величиной,
## поэтому подмена картинки на сломанную (другой рисунок, другие пропорции) масштаб не ломает:
## обе картинки остаются в том же размере арта, что и герой.
## В руках размер компенсируется масштабом гнезда носильщика, а зеркало в руках даёт сам
## носильщик (гнездо лежит внутри его Visual) — ровно как это делает Corpse.
##
## ПОТЕРИ ПУШКИ ДВЕ: упала ниже уровня старта больше чем на fall_fail_depth (пушка потеряна) и
## промах выстрелом (см. выше). Упавшую проверяем только пока пушка цела и не стреляла — сломанный
## хлам уже не важен. Контроллера уровня в сцене нет — предупреждение в консоль, дальше ничего.
##
## СЛОИ: слой 8 «предметы» (бит 128), маска 4 — только земля (как у трупа). С героем, врагами
## и снарядами пушка не сталкивается, зато её видит Player/PickupZone — поэтому E её подбирает.
## Сломанная пушка уходит на слой 7 «обломки» (broken_layer/broken_mask) и выходит из группы
## "carryables": подобрать её больше нельзя.
##
## ГЕОМЕТРИЯ: начало координат = точка картинки, которой пушка стоит на земле (низ картинки),
## поэтому в main.tscn position.y = 0 — это уровень пола, как у трупа.

## Куда предмет переезжает в руках: гнездо внутри Visual носильщика (как в Corpse.gd).
const CARRY_POINT := ^"Visual/Body/CarryPoint"
## Группа контроллера уровня (main.tscn: узел LevelController).
const LEVEL_CONTROLLER_GROUP: StringName = &"level_controller"
## Группа башни (Tower.tscn: groups = ["tower"]) — у неё спрашиваем сигнал destroyed.
const TOWER_GROUP: StringName = &"tower"
## Тип ресурса данных снаряда (без class_name — как в Projectile.gd, чтобы не зависеть от кэша
## глобальных классов редактора): по нему объявлены поля Ball Scene / Ball Data в инспекторе.
const ProjectileData := preload("res://ProjectileData.gd")

@export_group("Размер")
## Во сколько раз ИСХОДНЫЙ рисунок пушки больше файла в проекте (исходная ширина / ширина файла).
## Sprites/cannon.png — 630×337, файл ровно такой → 1.0. Уменьшишь картинку — поставь сюда
## 630 / ширину нового файла (посчитать помогает ArtScale.mult_for_native(630, texture)).
@export_range(0.1, 4.0, 0.01) var native_mult: float = 1.0
## Подкрутка размера пушки: 1.0 — как нарисовано (630 px картинки → ≈132 px в мире, чуть больше
## роста героя), 0.75 — ровно 0.8 роста. Масштаб арта берётся у героя, не из картинки.
@export_range(0.1, 4.0, 0.01) var size_mult: float = 1.0
## Где на картинке дульный срез, долей от её размера: x — по ширине (1 = правый край),
## y — по высоте (0 = верх). В эту точку встаёт Marker2D Muzzle.
@export var muzzle_frac: Vector2 = Vector2(0.92, 0.4)

@export_group("В руках")
## Смещение пушки от гнезда носильщика, в МИРОВЫХ пикселях: x — вперёд по взгляду, y — вниз.
@export var carry_offset: Vector2 = Vector2.ZERO
## Размер пушки в руках относительно обычного.
@export_range(0.05, 2.0, 0.01) var carried_scale_mult: float = 1.0
## Множитель скорости ходьбы носильщика, пока пушка в руках.
@export_range(0.05, 1.0, 0.05) var carry_speed_mult: float = 0.7

@export_group("Потеря")
## На сколько пикселей ниже уровня старта должна оказаться пушка, чтобы считаться потерянной.
@export var fall_fail_depth: float = 80.0

@export_group("Выстрел")
## Сцена снаряда (Projectile.tscn): ядро летит по той же логике, что и камень, — баллистика,
## время жизни и попадания уже в ней, разница только в данных.
@export var ball_scene: PackedScene
## Данные ядра (cannonball.tres, ProjectileData): своя картинка, скорость, урон и флаги
## (пробивает мобов, снимает HP башни, сообщает о промахе). Подставляются снаряду при выстреле.
@export var ball_data: ProjectileData
## Сцена вспышки из дула (CannonFire.tscn): вспышка и дымок после выстрела. Пусто — эффекта нет.
@export var fire_scene: PackedScene
## Отдача пушки при выстреле, px/с: толчок назад, против направления выстрела (влево при выстреле
## вправо). Работает после слома: пока пушка в руках, она заморожена (freeze) и скорость не видна.
@export var recoil_speed: float = 50.0
## Размах тряски камеры после выстрела, px (выключена у камеры — не трясёт).
@export var shake_intensity: float = 10.0
## Длительность тряски камеры после выстрела, с.
@export var shake_duration: float = 0.15

@export_group("Сломанная пушка")
## Картинка сломанной пушки (cannon_broken.png): подменяется сразу после выстрела.
@export var broken_texture: Texture2D
## Толчок сломанной пушке, px/с: x — вперёд по направлению выстрела, y — вверх (минус = вверх).
@export var break_impulse: Vector2 = Vector2(260.0, -180.0)
## Скорость кувырка сломанной пушки, рад/с (знак случаен).
@export var break_spin: float = 8.0
## Слой сломанной пушки: 64 = слой 7 «обломки» (как у Debris).
@export var broken_layer: int = 64
## Маска сломанной пушки: 4 = слой 3 «земля»; герой, враги и снаряды её не замечают.
@export var broken_mask: int = 4

@export_group("Исход выстрела")
## Что сказать игроку, если ядро ушло впустую (земля/стена, конец времени жизни, край экрана).
@export var miss_reason: String = "промах"
## Что сказать игроку, если ядро попало в башню, но та уцелела.
@export var tower_alive_reason: String = "башня уцелела"

@export_group("Отрисовка")
## Мировой z пушки, лежащей на земле (в руках — 0: пушка рисуется деталью гнезда носильщика).
@export var world_z: int = -1

@onready var body: Node2D = $Body
@onready var sprite: Sprite2D = $Body/Sprite
@onready var collider: CollisionShape2D = $Collider
## Дульный срез: отсюда при выстреле летит ядро (см. use_action).
@onready var muzzle: Marker2D = $Body/Muzzle

## Носильщик, если пушка в руках (null — пушка лежит в мире).
var _carrier: Node = null
## Куда вернуть пушку из рук: прежний родитель и её индекс в списке детей (порядок отрисовки).
var _home_parent: Node = null
var _home_index: int = -1
## Что было до подбора, чтобы вернуть это в put_down.
var _saved_layer: int = 0
var _saved_mask: int = 0
var _saved_z_index: int = 0
var _saved_z_relative: bool = true
## Уровень старта: ниже него на fall_fail_depth пушка считается потерянной.
var _start_y: float = 0.0
## Про потерю уже сообщено — второй раз не сообщаем.
var _fail_reported: bool = false
## Выстрел уже был: пушка одноразовая — второй ЛКМ молчит, и потеря сломанного хлама уже не важна.
var _used: bool = false
## Выпущенное ядро и башня, за разрушением которой следим (её destroyed = победа контроллера).
var _ball: Node = null
var _tower: Node = null
var _tower_destroyed: bool = false
## Что успело случиться с ядром (исход объявляется один раз, когда оно исчезнет — _on_ball_gone).
var _ball_missed: bool = false
var _ball_hit_tower: bool = false
## Исход выстрела уже объявлен — второй раз не объявляем.
var _outcome_reported: bool = false


func _ready() -> void:
	_start_y = global_position.y
	z_index = world_z
	_apply_size()
	_connect_tower()


## Каждый физический кадр — только слежение за падением (см. _check_fall).
func _physics_process(_delta: float) -> void:
	_check_fall()


# ============================================================================
# РАЗМЕР (и размер, и зеркало живут только у Body — корень всегда scale = ONE)
# ============================================================================
## Размер из единого масштаба арта: Body получает масштаб k = ArtScale.hero_scale() × native_mult
## × size_mult, а картинка, коллизия и маркер дула нарисованы в пикселях картинки — значит
## масштабируются одной и той же величиной. Пиксельных размеров у пушки больше нет: размер
## двигают только два множителя, оба из инспектора.
## nest_scale — масштаб гнезда носильщика (в руках): на него делим, чтобы мировой размер пушки
## остался тем же, а не унаследовал уменьшенный Visual героя (как в Corpse.pickup).
## carried_mult — размер в руках (carried_scale_mult; в мире всегда 1).
func _apply_size(nest_scale: Vector2 = Vector2.ONE, carried_mult: float = 1.0) -> void:
	var tex := sprite.texture
	if tex == null:
		return
	var size := tex.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var k := ArtScale.scale_of(native_mult, size_mult) * maxf(carried_mult, 0.01)
	body.scale = Vector2(
		k / maxf(absf(nest_scale.x), 0.0001),
		k / maxf(absf(nest_scale.y), 0.0001)
	)
	# Низ картинки = начало координат (точка опоры): offset в пикселях картинки, БЕЗ масштаба —
	# масштаб даёт сам Body. Пушка встаёт на землю, а не наполовину в неё.
	sprite.centered = true
	sprite.position = Vector2.ZERO
	sprite.offset = Vector2(0.0, -size.y * 0.5)
	# Коллизия — простая форма по размеру картинки (физика у предмета не масштабируется, форму
	# собираем кодом; так же сделано у трупа).
	var rect := RectangleShape2D.new()
	rect.size = size
	collider.shape = rect
	collider.position = Vector2(0.0, -size.y * 0.5)
	# Дуло: доля muzzle_frac от картинки — x от левого края, y от верхнего (как на картинке).
	muzzle.position = Vector2((muzzle_frac.x - 0.5) * size.x, (muzzle_frac.y - 1.0) * size.y)


# ============================================================================
# ПЕРЕНОСКА (интерфейс группы "carryables")
# ============================================================================
## Взяли в руки (E): пушка замирает и переезжает в гнездо носильщика, слои физики гаснут —
## её больше никто не замечает (как труп в руках). Поворот, зеркало и размер даёт носильщик:
## гнездо лежит внутри его Visual, поэтому пушка разворачивается по взгляду сама.
func pickup(carrier: Node) -> void:
	if _carrier != null or carrier == null:
		return
	_carrier = carrier
	_home_parent = get_parent()
	_home_index = get_index()
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_saved_z_index = z_index
	_saved_z_relative = z_as_relative
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	var nest := carrier.get_node_or_null(CARRY_POINT) as Node2D
	if nest == null:
		nest = carrier as Node2D
	reparent(nest)
	# Встаём ровно в гнездо и без остатков физики: локально ничего не крутим и не зеркалим.
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	# В руках пушка — деталь гнезда в группе героя: рисуется между юбкой и головой.
	z_index = 0
	z_as_relative = true
	show_behind_parent = false
	_apply_size(_node_scale(nest), carried_scale_mult)


## Положили на землю (E): возврат прежних слоёв, физики и порядка отрисовки, постановка на
## мировую точку (точку по земле ищет Player лучом вниз). Пушка остаётся целой — её можно
## поднять снова.
func put_down(world_position: Vector2) -> void:
	if _carrier == null:
		return
	_carrier = null
	if _home_parent != null and is_instance_valid(_home_parent):
		reparent(_home_parent)
		# reparent() добавляет узел в конец списка детей, а порядок списка — это порядок
		# отрисовки: возвращаем пушку на прежнее место среди детей.
		if _home_index >= 0:
			_home_parent.move_child(self, clampi(_home_index, 0, _home_parent.get_child_count() - 1))
	_home_parent = null
	freeze = false
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	scale = Vector2.ONE
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_position = world_position
	z_index = _saved_z_index
	z_as_relative = _saved_z_relative
	_apply_size()


# ============================================================================
# ВЫСТРЕЛ (ЛКМ)
# ============================================================================
## ЛКМ с пушкой в руках: выстрел ядром из дула в сторону курсора. Пушка одноразовая — флаг _used,
## поэтому второй ЛКМ уже ничего не делает. Порядок важен: сначала выстрел (дуло ещё в руках, точка
## вылета — как в этот момент), потом слом: вместе со сломом пушка уезжает из CarryPoint, и Player
## в том же такте возвращает руки за курсором (рывок отдачи Player._use_item ставит сам).
func use_action(aim_point: Vector2) -> void:
	if _used or _carrier == null:
		return
	_used = true
	# Стреляем от дула: его мировая позиция и есть точка вылета. В руках дуло зеркалится вместе с
	# Visual носильщика, поэтому направление на курсор «влево/вправо» учитывается само.
	var from := muzzle.global_position
	var to_aim := aim_point - from
	if to_aim.length_squared() < 1.0:
		to_aim = Vector2.RIGHT if aim_point.x >= from.x else Vector2.LEFT
	var dir := to_aim.normalized()
	# Вспышка/дым — в точке дула, пока пушка ещё в руках (со сломом она уедет из CarryPoint).
	_spawn_fire(dir)
	_fire(from, dir)
	_break_free(dir)
	# Отдача: толчок назад, против выстрела. Строго ПОСЛЕ _break_free — он переписывает
	# linear_velocity целиком, поэтому импульс, добавленный раньше, был бы затёрт.
	linear_velocity += -dir * recoil_speed
	_shake_camera()


## Ядро: Projectile.tscn (та же баллистика и попадания, что у камня) + cannonball.tres (свои числа
## и флаги). Сигналы вешаем до добавления в сцену: hit_tower/missed придут нам сразу, а tree_exiting
## — единственное место, где объявляется исход (см. _on_ball_gone).
func _fire(from: Vector2, dir: Vector2) -> void:
	if ball_scene == null:
		push_warning("Cannon: не задана сцена ядра (Ball Scene, Projectile.tscn) — выстрела не будет.")
		return
	if ball_data == null:
		push_warning("Cannon: не заданы данные ядра (Ball Data, cannonball.tres) — выстрела не будет.")
		return
	_ball = ball_scene.instantiate()
	if not _ball.has_method(&"launch"):
		push_warning("Cannon: снаряд без launch() — выстрела не будет.")
		_ball.queue_free()
		_ball = null
		return
	# Projectile.tscn по умолчанию — камень, поэтому ядру подставляем его собственные данные.
	_ball.set(&"data", ball_data)
	_ball.connect(&"hit_tower", _on_ball_hit_tower)
	_ball.connect(&"missed", _on_ball_missed)
	_ball.connect(&"tree_exiting", _on_ball_gone)
	get_tree().current_scene.add_child(_ball)
	var ball_node := _ball as Node2D
	if ball_node != null:
		ball_node.global_position = from
	_ball.call(&"launch", dir)


## Выстрел сделан — пушка выпадает из рук и остаётся сломанной навсегда: картинка cannon_broken.png,
## слои обломков, толчок вперёд и кувырок. Она уходит из группы "carryables" (E её больше не видит)
## и уезжает из CarryPoint: Player в том же такте замечает, что рука пуста (is_carrying = false), —
## и снова может стрелять камнем и подбирать предметы.
func _break_free(dir: Vector2) -> void:
	remove_from_group(&"carryables")
	if broken_texture != null:
		sprite.texture = broken_texture
	else:
		push_warning("Cannon: не задана картинка сломанной пушки (Broken Texture) — оставляю целую.")
	_carrier = null
	if _home_parent != null and is_instance_valid(_home_parent):
		reparent(_home_parent)
		if _home_index >= 0:
			_home_parent.move_child(self, clampi(_home_index, 0, _home_parent.get_child_count() - 1))
	_home_parent = null
	freeze = false
	collision_layer = broken_layer
	collision_mask = broken_mask
	scale = Vector2.ONE
	rotation = 0.0
	z_index = _saved_z_index
	z_as_relative = _saved_z_relative
	_apply_size()   # пересчитываем размер: картинка сломанной пушки другая
	# Толчок вперёд по выстрелу и вверх, плюс кувырок — как разлёт обломков при смерти моба.
	var forward := 1.0 if dir.x >= 0.0 else -1.0
	linear_velocity = Vector2(break_impulse.x * forward, break_impulse.y)
	angular_velocity = randf_range(-absf(break_spin), absf(break_spin))


# ============================================================================
# ЭФФЕКТЫ ВЫСТРЕЛА (вспышка из дула, дым, тряска камеры)
# ============================================================================
## Вспышка из дула: CannonFire.tscn в мировой точке дула. Масштаб — как у пушки (ArtScale), зеркало
## — по направлению выстрела (dir.x >= 0 — смотрит вправо). Эффект сам себя удалит, когда отыграет.
func _spawn_fire(dir: Vector2) -> void:
	if fire_scene == null:
		return
	var effect := fire_scene.instantiate() as Node2D
	if effect == null:
		return
	get_tree().current_scene.add_child(effect)
	effect.global_position = muzzle.global_position
	if effect.has_method(&"setup"):
		effect.call(&"setup", ArtScale.scale_of(native_mult, size_mult), dir.x >= 0.0)


## Тряска камеры после выстрела: камера уровня — в группе "camera" (CameraFollow.gd). Метода нет
## (камеру подменили) — молча пропускаем, чтобы выстрел из-за этого не падал.
func _shake_camera() -> void:
	var camera := get_tree().get_first_node_in_group(&"camera")
	if camera != null and camera.has_method(&"shake"):
		camera.call(&"shake", shake_intensity, shake_duration)


# ============================================================================
# ИСХОД ВЫСТРЕЛА (победа и поражение)
# ============================================================================
## Подписываемся на разрушение башни. Победу объявляет LevelController по тому же сигналу
## (см. Tower._connect_level_controller), а нам он нужен, чтобы не сказать «башня уцелела» уже
## разрушенной башне: после попадания ядра Tower.apply_damage успевает эмитнуть destroyed.
func _connect_tower() -> void:
	_tower = get_tree().get_first_node_in_group(TOWER_GROUP)
	if _tower == null:
		push_warning("Cannon: в сцене нет башни (группа \"tower\") — исход выстрела по ней не проверить.")
		return
	if not _tower.has_signal(&"destroyed"):
		push_warning("Cannon: у башни нет сигнала destroyed — победа после выстрела не сработает.")
		return
	_tower.connect(&"destroyed", _on_tower_destroyed)


func _on_tower_destroyed() -> void:
	_tower_destroyed = true


## Ядро ушло впустую (земля/стена, конец времени жизни, край экрана): исход решаем в _on_ball_gone.
func _on_ball_missed() -> void:
	_ball_missed = true


## Ядро попало в башню. Здесь решать исход рано: снаряд сейчас исчезнет, и уже в _on_ball_gone
## видно, чем кончилось дело (Tower.apply_damage успел отработать, а при нуле HP — эмитнуть destroyed).
func _on_ball_hit_tower(_tower_hit: Node) -> void:
	_ball_hit_tower = true


## Ядро исчезло — единственная точка, где исход объявляется, и то один раз. Победу объявляет
## LevelController по Tower.destroyed, поэтому здесь остаются только два проигрыша: промах и
## попадание в уцелевшую башню.
func _on_ball_gone() -> void:
	if _outcome_reported:
		return
	_outcome_reported = true
	_ball = null
	if _ball_missed:
		_fail_level(miss_reason)
	elif _ball_hit_tower and not _tower_destroyed:
		_fail_level(tower_alive_reason)


# ============================================================================
# ПОТЕРЯ ПУШКИ
# ============================================================================
## Пушка ушла ниже уровня старта больше чем на fall_fail_depth — она потеряна (пустая ячейка
## ямы, край мира). Сообщаем один раз: LevelController.fail() глушит спавн башни и перезагружает
## сцену. Контроллера в сцене нет — предупреждение и всё.
## Пока пушка в руках, проверка молчит: её несёт герой, и «потерянной» она быть не может.
## Уже стрелявшая (сломанная) пушка тоже не считается потерянной — хлам в яме уровня не решает.
func _check_fall() -> void:
	if _fail_reported or _carrier != null or _used:
		return
	if global_position.y <= _start_y + fall_fail_depth:
		return
	_fail_reported = true
	_fail_level("пушка потеряна")


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
## Мировой масштаб узла (модуль по осям, защита от нуля): в руках на него делим размер пушки.
func _node_scale(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ONE
	var s := node.global_scale
	return Vector2(
		1.0 if is_zero_approx(s.x) else s.x,
		1.0 if is_zero_approx(s.y) else s.y
	)


## Сообщить контроллеру уровня о поражении. У LevelController исход один: второй fail молчит сам.
## Контроллера в сцене нет — предупреждение в консоль и всё (победа/поражение не сработают).
func _fail_level(reason: String) -> void:
	var controller := get_tree().get_first_node_in_group(LEVEL_CONTROLLER_GROUP) as LevelController
	if controller == null:
		push_warning("Cannon: в сцене нет LevelController (группа \"level_controller\") — про \"%s\" сообщить некому." % reason)
		return
	controller.fail(reason)
