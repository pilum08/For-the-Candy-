extends Node2D
## РАЗЛЁТ ЧАСТЕЙ: превращает части тела (или части любого другого объекта-куклы) в отдельные
## физические обломки. Никаких твинов: каждой части один раз выдаётся импульс и проворот,
## дальше её ведёт обычная физика RigidBody2D, и она остаётся лежать до перезагрузки сцены.
##
## Как это работает: на КАЖДУЮ часть создаётся один обломок Debris.tscn, и в него переносятся
## все спрайты этой части (у головы их два — сама голова и лицо) в ТОЧНОЙ мировой позе спрайта:
## смещение, поворот, масштаб и зеркало берутся из Transform2D как есть (в нём уже сидят
## art_scale, player_scale и зеркало куклы), поэтому обломок стартует ровно там и ровно таким,
## каким часть была в момент смерти. Оригиналы при этом скрываются.
##
## Куда кладутся обломки: в текущую сцену (мир), а не в этот узел — иначе они уехали бы вместе
## с родителем (героем) и исчезли бы вместе с ним при перезагрузке сцены.
##
## Коллизия обломка — прямоугольник по мировому габариту части (абсолютная ось, до поворота):
## форма всегда «по размеру картинки», а кувыркается обломок вокруг центра этого габарита.
##
## Числа для подбора — в экспортах ниже. Невидимые спрайты (например спрятанная передняя рука)
## в обломки не попадают: их в этот момент и на экране нет.

@export_group("Обломки")
## Сцена одного обломка: RigidBody2D + Sprite2D + CollisionShape2D (см. Debris.tscn).
@export var debris_scene: PackedScene = preload("res://Debris.tscn")
## Масса обломка (<= 0 — оставить как в сцене Debris.tscn).
@export var debris_mass: float = 1.0

@export_group("Разлёт")
## Скорость обломка, px/с: случайная из диапазона; направление — радиально от центра тела.
@export var speed_min: float = 260.0
@export var speed_max: float = 620.0
## Максимальный проворот обломка, рад/с (случайный в обе стороны).
@export var spin_max: float = 9.0
## Насколько разлёт заворачивает вверх, градусы (0 — строго радиально наружу от центра).
@export var up_bias_deg: float = 25.0
## Случайный разброс направления, градусы (в обе стороны от радиали).
@export var spread_deg: float = 30.0

@export_group("Слои обломков")
## Слой обломков: слой 7 «обломки» (значение 64). Обломки никому не мешают — их никто не видит.
@export var debris_layer: int = 64
## Маска обломков: только земля (слой 3, значение 4). С героем, врагами, снарядами и трупами
## обломки не сталкиваются.
@export var debris_mask: int = 4


## Разлёт: parts — узлы частей (вместе со всем, что в них вложено). На каждую часть создаётся
## ОДИН обломок со всеми её спрайтами. Возвращает созданные обломки; оригиналы скрываются.
func spawn_debris(parts: Array[Node2D]) -> Array[Node2D]:
	var made: Array[Node2D] = []
	var parent := _debris_parent()
	if parent == null or debris_scene == null:
		return made

	# По каждой части: её спрайты и её габарит в мире. Из габаритов считается центр тела,
	# от которого разлёт идёт наружу.
	var groups: Array = []            # по группе спрайтов (Array[Sprite2D]) на каждую часть
	var rects: Array[Rect2] = []
	for part in parts:
		if part == null or not is_instance_valid(part):
			continue
		var part_sprites := _sprites_of(part)
		if part_sprites.is_empty():
			continue
		groups.append(part_sprites)
		rects.append(_world_rect(part_sprites))
	var pivot := _average_center(rects)

	for i in groups.size():
		var sprites: Array[Sprite2D] = groups[i]
		var debris := _spawn_one(sprites, rects[i], pivot, parent)
		if debris != null:
			made.append(debris)

	for part in parts:
		if part != null and is_instance_valid(part):
			part.visible = false   # оригинал уходит: его место занял обломок
	return made


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Один обломок: тело в центре габарита части, копии её картинок и прямоугольная коллизия.
func _spawn_one(sprites: Array[Sprite2D], world_rect: Rect2, pivot: Vector2, parent: Node) -> Node2D:
	var debris := debris_scene.instantiate() as RigidBody2D
	if debris == null:
		push_warning("DeathBurst: сцена обломка %s — не RigidBody2D" % debris_scene.resource_path)
		return null
	debris.collision_layer = debris_layer
	debris.collision_mask = debris_mask
	if debris_mass > 0.0:
		debris.mass = debris_mass

	var center := world_rect.get_center()
	parent.add_child(debris)
	# Начало координат обломка — центр габарита части: вокруг него он и кувыркается.
	debris.global_position = center
	debris.global_rotation = 0.0
	# Заготовка из Debris.tscn не нужна: спрайты копируются из части как есть (см. _copy_sprite).
	var placeholder := debris.get_node_or_null("Sprite")
	if placeholder != null:
		placeholder.free()
	for src in sprites:
		_copy_sprite(src, debris)
	_copy_collider(world_rect.size, debris)

	# Импульс: наружу от центра тела, со случайным разбросом и лёгким заворотом вверх.
	var direction := center - pivot
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized().rotated(deg_to_rad(randf_range(-spread_deg, spread_deg)))
	direction = direction.rotated(-deg_to_rad(up_bias_deg))   # ось Y смотрит вниз: минус — вверх
	debris.apply_central_impulse(direction * randf_range(speed_min, speed_max))
	if spin_max > 0.0:
		debris.angular_velocity = randf_range(-spin_max, spin_max)
	return debris


## Копия спрайта части: картинка и её настройки как есть, плюс Transform2D целиком — уже ПОСЛЕ
## того, как обломок встал в дерево. Поэтому глобальная поза копии совпадает с исходной частью
## вплоть до зеркала и масштаба (в нём сидят art_scale, player_scale и зеркало куклы).
func _copy_sprite(src: Sprite2D, debris: RigidBody2D) -> void:
	var copy := Sprite2D.new()
	copy.name = src.name   # «Sprite»/«Face»: порядок детей обломка = прежний порядок рисования
	debris.add_child(copy)
	copy.texture = src.texture
	copy.centered = src.centered
	copy.offset = src.offset
	copy.flip_h = src.flip_h
	copy.flip_v = src.flip_v
	copy.texture_filter = src.texture_filter
	copy.z_index = src.z_index
	copy.z_as_relative = src.z_as_relative
	copy.global_transform = src.global_transform


## Коллизия обломка: прямоугольник по мировому габариту части. Габарит уже в мировых единицах,
## а обломок стоит без своего масштаба, поэтому форма выходит ровно по размеру картинки
## (физика не масштабируется — форма задаётся числами, см. Rig/Player).
func _copy_collider(gabarit: Vector2, debris: RigidBody2D) -> void:
	var collider := debris.get_node_or_null("Collider") as CollisionShape2D
	if collider == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = gabarit.max(Vector2.ONE)   # нулевого габарита не бывает
	collider.shape = rect
	collider.position = Vector2.ZERO
	collider.rotation = 0.0
	collider.scale = Vector2.ONE


## Все спрайты одной части, включая вложенные: у головы их два (голова и лицо), у остальных один.
func _sprites_of(part: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	if part != null and is_instance_valid(part):
		_collect_sprites(part, found)
	return found


## Габарит части в мире: объединение габаритов всех её спрайтов. Мировой поворот и масштаб
## учтены: Sprite2D.get_rect() даёт прямоугольник в локальных осях спрайта, а глобальный
## Transform2D переносит его в мир вместе с art_scale и зеркалом куклы.
func _world_rect(sprites: Array[Sprite2D]) -> Rect2:
	var rect := sprites[0].get_global_transform() * sprites[0].get_rect()
	for i in range(1, sprites.size()):
		rect = rect.merge(sprites[i].get_global_transform() * sprites[i].get_rect())
	return rect


func _collect_sprites(node: Node, found: Array[Sprite2D]) -> void:
	var sprite := node as Sprite2D
	if sprite != null and sprite.texture != null and sprite.is_visible_in_tree():
		found.append(sprite)
	for child in node.get_children():
		_collect_sprites(child, found)


## Центр тела — среднее габаритов частей.
func _average_center(rects: Array[Rect2]) -> Vector2:
	if rects.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for rect in rects:
		sum += rect.get_center()
	return sum / float(rects.size())


## Обломки кладём в мир (текущая сцена): иначе они уехали бы вместе с родителем (куклой)
## и исчезли бы вместе с ним при перезагрузке сцены.
func _debris_parent() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	return get_parent()
