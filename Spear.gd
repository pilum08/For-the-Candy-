extends RigidBody2D
## КОПЬЁ (Spear) — находка после разрушения башни: когда башня разлетается (Tower.destroy →
## TowerExplosion), за ней встаёт копьё — «герой добыл оружие» (Tower._spawn_spear ставит его в
## (x + 100, 0) и даёт толчок вверх). Арт: Sprites/spear.png (103×630, нарисован 1:1 с героем).
##
## ЧТО УМЕЕТ (интерфейс группы "carryables" — так с предметами в руках работает Player): pickup /
## put_down / use_action и свойства carry_offset, carried_scale_mult, carry_speed_mult. Сделано
## ЗАГОТОВКОЙ «на будущее»: пока копьё лежит на слое 7 «обломки», PickupZone героя (маска 144 =
## слои 5 и 8) его НЕ видит, поэтому в игре подобрать его нельзя — копьё просто лежит за упавшей
## башней. Подбирать и использовать (удар/бросок) — отдельная задача; когда до неё дойдёт, копью
## хватит переехать на слой 8 «предметы» (128), а здесь дописать use_action.
##
## РАЗМЕР: корень RigidBody2D всегда scale = ONE (иначе поедет физика), масштаб живёт на дочернем
## узле Visual — как у пушки и трупа. Мировой размер берётся из ЕДИНОГО МАСШТАБА АРТА (ArtScale,
## docs/SETUP.md раздел 16): native_mult 1.0 (файл не уменьшали) × size_mult 1.0 → 103 × 0.21 ≈ 22
## px в ширину и 630 × 0.21 ≈ 132 px в высоту (примерно рост героя). Низ картинки — в начале
## координат узла (спрайт: centered = true и offset = (0, ‑высота/2)), поэтому position.y = 0 в мире —
## уровень пола, как у башни и пушки.
##
## ГЕОМЕТРИЯ: узел Visual носит масштаб, поэтому спрайт И коллизия (прямоугольник 103×630 при
## (0, ‑315)) стоят в ПИКСЕЛЯХ КАРТИНКИ и уменьшаются одним и тем же множителем. Форма пересобирается
## в _apply_size() из NATIVE_SIZE — числа в сцене только образец для редактора.
##
## СЛОИ: слой 7 «обломки» (бит 64), маска 4 — только земля (как у Debris). Герой, враги и снаряды
## копьё не замечают (в их масках слоя 7 нет). Пока копьё в руках, слои гасятся в 0/0 — как у пушки.
##
## class_name намеренно НЕ ставим (как у CannonFire/TowerExplosion): тип берётся через preload.

## Куда предмет переезжает в руках: гнездо внутри Visual носильщика (как в Corpse.gd).
const CARRY_POINT := ^"Visual/Body/CarryPoint"
## ИСХОДНЫЙ рисунок копья (Sprites/spear.png) в пикселях 1:1, как нарисовано: от него считаются
## спрайт, коллизия и масштаб. Файл в проекте ровно такого размера, поэтому native_mult = 1.0.
const NATIVE_SIZE := Vector2(103.0, 630.0)
## Слой копья в мире: слой 7 «обломки» — лежит за башней и герою не мешает (см. шапку).
const LAYER := 64
## Маска копья в мире: слой 3 «земля» — стоит на полу и больше ни с чем не сталкивается.
const MASK := 4

@export_group("Размер")
## Во сколько раз ИСХОДНЫЙ рисунок копья больше файла в проекте (исходная ширина / ширина файла).
## Файл не уменьшали → 1.0. Уменьшишь картинку — поставь сюда 103 / ширину нового файла
## (ArtScale.mult_for_native(103, texture)).
@export_range(0.1, 4.0, 0.01) var native_mult: float = 1.0
## Подкрутка размера копья: 1.0 — как нарисовано (≈22×132 px в мире), больше — крупнее.
@export_range(0.1, 4.0, 0.01) var size_mult: float = 1.0

@export_group("Переноска (заготовка)")
## Сдвиг копья в руках носильщика, МИРОВЫЕ пиксели: Player делит его на масштаб героя
## (Player._apply_art_scale), поэтому 0 — копьё встаёт ровно в гнездо. Крутить, когда начнут носить.
@export var carry_offset: Vector2 = Vector2.ZERO
## Размер копья в руках относительно обычного.
@export_range(0.05, 2.0, 0.01) var carried_scale_mult: float = 1.0
## Множитель скорости ходьбы носильщика, пока копьё в руках (тяжёлое — идёшь медленнее).
@export_range(0.05, 1.0, 0.05) var carry_speed_mult: float = 0.7

@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite
@onready var collider: CollisionShape2D = $Visual/Collider

## Носильщик, если копьё в руках (null — копьё лежит в мире).
var _carrier: Node = null
## Куда вернуть копьё из рук: прежний родитель и его индекс в списке детей (порядок отрисовки).
var _home_parent: Node = null
var _home_index: int = -1


func _ready() -> void:
	_apply_size()


# ============================================================================
# РАЗМЕР (масштаб живёт только у Visual — корень всегда scale = ONE)
# ============================================================================
## Размер из единого масштаба арта: Visual получает масштаб k = ArtScale.hero_scale() × native_mult
## × size_mult, а картинка и коллизия нарисованы в пикселях картинки — значит масштабируются одной
## и той же величиной. Пиксельных размеров у копья больше нет: размер двигают два множителя.
## nest_scale — масштаб гнезда носильщика (в руках): на него делим, чтобы мировой размер копья
## остался тем же, а не унаследовал уменьшенный Visual героя (как в Cannon.pickup / Corpse.pickup).
## carried_mult — размер в руках (carried_scale_mult; в мире всегда 1).
func _apply_size(nest_scale: Vector2 = Vector2.ONE, carried_mult: float = 1.0) -> void:
	var k := ArtScale.scale_of(native_mult, size_mult) * maxf(carried_mult, 0.01)
	visual.scale = Vector2(
		k / maxf(absf(nest_scale.x), 0.0001),
		k / maxf(absf(nest_scale.y), 0.0001)
	)
	# Низ картинки = начало координат (точка опоры): offset в пикселях картинки, БЕЗ масштаба —
	# масштаб даёт сам Visual. Копьё стоит на земле, а не наполовину в ней.
	sprite.centered = true
	sprite.position = Vector2.ZERO
	sprite.offset = Vector2(0.0, -NATIVE_SIZE.y * 0.5)
	# Коллизия — прямоугольник по картинке (физика у предмета не масштабируется, форму собираем
	# кодом; так же сделано у трупа и пушки). Числа — в пикселях картинки: узел Collider лежит
	# внутри Visual и уменьшается вместе с ним.
	var rect := RectangleShape2D.new()
	rect.size = NATIVE_SIZE
	collider.shape = rect
	collider.position = Vector2(0.0, -NATIVE_SIZE.y * 0.5)


# ============================================================================
# ПЕРЕНОСКА (интерфейс группы "carryables") — заготовка, в игре пока не используется
# ============================================================================
## Взяли в руки (E): копьё замирает и переезжает в гнездо носильщика, слои физики гаснут — его
## больше никто не замечает (как труп и пушка в руках). Поворот, зеркало и позицию в руках даёт
## носильщик: гнездо лежит внутри его Visual, поэтому копьё разворачивается по взгляду само.
## ЗАГОТОВКА: пока копьё на слое 7, PickupZone героя его не видит и в игре это не вызывается.
func pickup(carrier: Node) -> void:
	if _carrier != null or carrier == null:
		return
	_carrier = carrier
	_home_parent = get_parent()
	_home_index = get_index()
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	var nest := carrier.get_node_or_null(CARRY_POINT) as Node2D
	if nest == null:
		nest = carrier as Node2D
	if nest != null:
		reparent(nest)
	# Встаём ровно в гнездо и без остатков физики: локально ничего не крутим.
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	_apply_size(_node_scale(nest), carried_scale_mult)


## Положили на землю (E): возврат слоя «обломки» и физики, постановка на мировую точку (точку по
## земле ищет Player лучом вниз). Толчок при укладке копьё не использует — параметр есть для
## совместимости с интерфейсом carryables (как Corpse.put_down).
func put_down(at: Vector2, _impulse: Vector2 = Vector2.ZERO) -> void:
	if _carrier == null:
		return
	_carrier = null
	if _home_parent != null and is_instance_valid(_home_parent):
		reparent(_home_parent)
		# reparent() добавляет узел в конец списка детей, а порядок списка — это порядок
		# отрисовки: возвращаем копьё на прежнее место среди детей.
		if _home_index >= 0:
			_home_parent.move_child(self, clampi(_home_index, 0, _home_parent.get_child_count() - 1))
	_home_parent = null
	freeze = false
	collision_layer = LAYER
	collision_mask = MASK
	scale = Vector2.ONE
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_position = at
	_apply_size()


## ЛКМ с копьём в руках: пока ничего. TODO: удар или бросок, когда копьё станет оружием — сюда
## добавить бросок (как Cannon.use_action) или попап подсказки. Параметр оставлен ради интерфейса
## carryables: Player всегда зовёт use_action(aim_point).
func use_action(_aim_point: Vector2) -> void:
	pass


## Масштаб узла (у гнезда носильщика): |global_scale| — по нему делим, чтобы мировой размер остался.
func _node_scale(node: Node2D) -> Vector2:
	if node == null:
		return Vector2.ONE
	var s := node.global_scale
	return Vector2(maxf(absf(s.x), 0.0001), maxf(absf(s.y), 0.0001))
