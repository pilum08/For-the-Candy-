extends Node2D
## РАЗЛЁТ ЧАСТЕЙ МОБА — то, что показывается ВМЕСТО трупа, когда лимит трупов на уровне
## исчерпан (см. LevelController.can_spawn_corpse и Enemy._die). Разлёт по образу DeathBurst.gd:
## за раз каждой части выдаётся импульс и проворот, дальше её ведёт обычная физика RigidBody2D.
## Но части берутся из ПАСПОРТА моба (MobRigData): у моба в сцене узлов частей нет — их собирает
## MobVisual, поэтому поза каждой части считается по attach_pos вдоль цепочки родителей, а размер
## и точка сустава — по pivot_px.
##
## ОТЛИЧИЯ от обломков героя (DeathBurst.gd):
##   * collision_mask = 0 — мобовские обломки ни с чем не сталкиваются и падают сквозь землю;
##   * у каждого обломка дочерний VisibleOnScreenNotifier2D: уехал за экран — queue_free()
##     (обломки героя остаются лежать, эти — исчезают);
##   * collision_layer = 7 «обломки» (как в Debris.tscn) — чтобы не ломать другие сцены.
##
## Куда кладутся обломки: в текущую сцену (мир), а не в этот узел — иначе они уехали бы вместе
## с врагом и исчезли бы вместе с ним (Enemy в _die делает queue_free). Сам узел MobDeathBurst —
## разовая машина: Enemy создаёт его дочерним себе и зовёт burst(...). class_name намеренно НЕ
## ставим (как у MobRigData/MobVisual) — тип берётся через preload.

const MobRigData := preload("res://MobRigData.gd")   # тип паспорта (нужен только для типов)

## Направление взгляда эталонного арта (как в Enemy.gd): моб нарисован смотрящим ВЛЕВО.
const ART_LOOK: int = -1

## Имя части-лица в паспорте: отдельным обломком не летит — вклеивается в голову (см. _spawn_one).
const FACE_PART := "Face"
## Имя части-головы: к ней крепится мёртвое лицо.
const HEAD_PART := "Head"
## Мёртвое лицо моба (картинка на паспорте вида не хранится — берём общую).
const DEAD_FACE: Texture2D = preload("res://Sprites/enemy/enemy_dead_face.png")

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
## Слой обломков: слой 7 «обломки» (значение 64) — как у Debris.tscn.
@export var debris_layer: int = 64
## Маска обломков моба: 0 — ни с чем не сталкиваются, падают сквозь землю (см. шапку файла).
@export var debris_mask: int = 0


## Разлёт частей моба. rig — паспорт вида, world_pos — мировая позиция моба, art_scale — масштаб
## арта (MobVisual.art_scale()), facing — взгляд моба (_look из Enemy, ±1; "как нарисовано" = ART_LOOK).
## Возвращает созданные обломки.
func burst(rig: MobRigData, world_pos: Vector2, art_scale: float, facing: int) -> Array[Node2D]:
	var made: Array[Node2D] = []
	var parent := _debris_parent()
	if rig == null or debris_scene == null or parent == null:
		return made
	var s := maxf(art_scale, 0.01)
	var mirror := 1.0 if facing == ART_LOOK else -1.0

	# Мировой сустав каждой части: attach_pos вдоль цепочки родителей (как MobVisual), с масштабом
	# арта и зеркалом куклы. Родитель обязан стоять выше в списке — как в паспорте.
	# Лицо отдельным обломком не летит: оно — ребёнок головы и уезжает вместе с ней. Данные лица
	# берём заранее, потому что в паспорте Face идёт ПОСЛЕ Head.
	var face_part: Dictionary = {}
	for part: Dictionary in rig.parts:
		if part.get("name", "") == FACE_PART:
			face_part = part
			break

	var joints: Dictionary = {}      # имя части -> мировая позиция сустава
	var jobs: Array = []             # части с картинкой: {pos, pivot, texture, size, scale, center}
	for part: Dictionary in rig.parts:
		var part_name: String = part.get("name", "")
		if part_name == FACE_PART:
			continue                 # лицо не отдельная часть: его вклеивает головной обломок
		var attach: Vector2 = part.get("attach_pos", Vector2.ZERO)
		var parent_name: String = part.get("parent", "")
		var origin := world_pos
		if not parent_name.is_empty() and joints.has(parent_name):
			origin = joints[parent_name]
		var joint := origin + Vector2(attach.x * s * mirror, attach.y * s)
		joints[part_name] = joint

		var path: String = part.get("texture", "")
		if path.is_empty():
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var size := Vector2(tex.get_width(), tex.get_height()) * s
		var pivot: Vector2 = part.get("pivot_px", Vector2.ZERO)
		var job := {
			"pos": joint,
			"pivot": pivot,
			"texture": tex,
			"size": size,
			"scale": s,
			# центр картинки относительно сустава: коллизия и зона «за экраном» (как offset в MobVisual)
			"center": Vector2((-pivot.x + tex.get_width() * 0.5) * s * mirror, (-pivot.y + tex.get_height() * 0.5) * s),
		}
		if part_name == HEAD_PART and not face_part.is_empty():
			job["face"] = face_part   # головной обломок вклеит лицо (см. _spawn_one)
		jobs.append(job)
	if jobs.is_empty():
		return made

	# Центр тела — среднее центров картинок: от него разлёт идёт наружу.
	var centers: Array[Vector2] = []
	for job in jobs:
		centers.append((job["pos"] as Vector2) + (job["center"] as Vector2))
	var body_center := _average(centers)

	for job in jobs:
		var debris := _spawn_one(job, mirror)
		if debris == null:
			continue
		parent.add_child(debris)
		debris.global_position = job["pos"]
		debris.global_rotation = 0.0
		_push(debris, (job["pos"] as Vector2) + (job["center"] as Vector2), body_center)
		made.append(debris)
	return made

# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Один обломок части: тело в суставе части, спрайт как в MobVisual (offset = -pivot_px, масштаб
## с зеркалом), коллизия по картинке и уведомитель «ушёл за экран».
func _spawn_one(job: Dictionary, mirror: float) -> RigidBody2D:
	var debris := debris_scene.instantiate() as RigidBody2D
	if debris == null:
		push_warning("MobDeathBurst: сцена обломка %s — не RigidBody2D" % debris_scene.resource_path)
		return null
	debris.collision_layer = debris_layer
	debris.collision_mask = debris_mask
	if debris_mass > 0.0:
		debris.mass = debris_mass

	# Заглушка-спрайт из Debris.tscn не нужна: свой спрайт задаём числами из паспорта.
	var placeholder := debris.get_node_or_null("Sprite")
	if placeholder != null:
		placeholder.free()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	debris.add_child(sprite)
	sprite.texture = job["texture"]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.offset = -(job["pivot"] as Vector2)
	var s: float = job["scale"]
	sprite.scale = Vector2(s * mirror, s)

	# Мёртвое лицо вклеиваем прямо в спрайт головы: он уже с масштабом арта и зеркалом, поэтому
	# позиция — attach_pos из паспорта как есть (как ребёнок Face у Head в MobVisual). Нет части
	# Face в паспорте — голова летит одна.
	var face_part: Dictionary = job.get("face", {})
	if not face_part.is_empty():
		var face := Sprite2D.new()
		face.name = FACE_PART
		sprite.add_child(face)
		face.texture = DEAD_FACE
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.centered = false
		face.offset = -(face_part.get("pivot_px", Vector2.ZERO) as Vector2)
		face.position = face_part.get("attach_pos", Vector2.ZERO) as Vector2
		face.z_index = face_part.get("z_index", 0)

	# Коллизия — прямоугольник по картинке, сдвинут в её центр (центр — относительно сустава).
	var collider := debris.get_node_or_null("Collider") as CollisionShape2D
	if collider != null:
		var size: Vector2 = job["size"]
		var rect := RectangleShape2D.new()
		rect.size = size.max(Vector2.ONE)   # нулевого габарита не бывает
		collider.shape = rect
		collider.position = job["center"]
		collider.rotation = 0.0

	# Уехал за экран — обломок больше не нужен (мобовские обломки нигде не лежат).
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "ScreenExit"
	notifier.position = job["center"]
	notifier.rect = Rect2(-(job["size"] as Vector2) * 0.5, job["size"] as Vector2)
	debris.add_child(notifier)
	notifier.screen_exited.connect(debris.queue_free)
	return debris


## Импульс обломка: наружу от центра тела, со случайным разбросом и лёгким заворотом вверх.
func _push(debris: RigidBody2D, center: Vector2, body_center: Vector2) -> void:
	var direction := center - body_center
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized().rotated(deg_to_rad(randf_range(-spread_deg, spread_deg)))
	direction = direction.rotated(-deg_to_rad(up_bias_deg))   # ось Y смотрит вниз: минус — вверх
	debris.apply_central_impulse(direction * randf_range(speed_min, speed_max))
	if spin_max > 0.0:
		debris.angular_velocity = randf_range(-spin_max, spin_max)


## Среднее точек (центр тела по центрам картинок).
func _average(points: Array[Vector2]) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


## Обломки кладём в мир (текущая сцена): иначе они уехали бы вместе с врагом и исчезли бы с ним.
func _debris_parent() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	return get_parent()

