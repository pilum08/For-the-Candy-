extends Node2D
## УНИВЕРСАЛЬНЫЙ ВИЗУАЛ МОБА: собирает по паспорту (MobRigData) дерево суставов и спрайтов
## и играет позы. У каждого вида моба свой только паспорт — код общий.
##
## ЧТО ДЕЛАЕТ MobVisual:
##   * на каждую часть паспорта строит узел-сустав (Node2D), а частям с картинкой —
##     ещё и Sprite2D (centered = false, offset = -pivot_px), и ставит сустав в attach_pos;
##   * листает walk_poses / idle_poses с частотой pose_fps / idle_pose_fps, когда моб
##     бежит или стоит (кто из них какой — решает скрипт врага через set_moving);
##   * держит лицо: покой из паспорта (face_idle) и подмена на face_damage на время
##     (flash_damage_face);
##   * даёт доступ к суставу по имени (part) — навесить дуло, точку вылета камня и т. п.
##
## ЧТО ПИШЕТ СКРИПТ ВРАГА (всё, что связано с поведением):
##   * set_moving() каждый кадр — бежит моб или стоит;
##   * свои позы (удар, прыжок, прицел) — hold_pose() / release_pose();
##   * масштаб и зеркало — set_art_transform() (это scale самого MobVisual: зеркало идёт
##     по scale.x, начало координат остаётся центром между стопами, физика родителя
##     не масштабируется);
##   * коллизии, скорость, урон, смерть и труп — тоже его дело.
##
## class_name намеренно НЕ ставим (как у Rig.gd и ProjectileData.gd), чтобы не зависеть
## от кэша глобальных классов редактора: const MobVisual := preload("res://MobVisual.gd").

const MobRigData := preload("res://MobRigData.gd")   # тип паспорта (нужен только для типов)

## Имя части-лица в паспорте: именно её текстура подменяется в flash_damage_face().
const FACE_PART := "Face"

## Паспорт моба (пример: enemy_yellow.tres). Пусто — визуал пустой, ничего не строит.
@export var rig: MobRigData

## Имя части → { "node": Node2D, "key": "arm_l", "attach": Vector2 } (ключ позы — см. _pose_key).
var _parts: Dictionary = {}
var _face: Sprite2D = null
var _face_idle: Texture2D = null
var _face_damage: Texture2D = null
var _walk: Array = []
var _idle: Array = []
var _pose_fps: float = 0.0
var _idle_fps: float = 0.0
var _moving: bool = false
var _pose_index: int = 0
var _pose_timer: float = 0.0
## Разовая поза показана: листание стоит (см. hold_pose / release_pose).
var _holding: bool = false
## Сколько секунд ещё держать лицо урона.
var _face_timer: float = 0.0


func _ready() -> void:
	if rig != null:
		build(rig)


# ============================================================================
# СБОРКА (механизм; числа — в паспорте)
# ============================================================================
## Собрать дерево частей по паспорту. Зовётся сама в _ready, если rig задан;
## можно позвать руками, чтобы пересобрать моба под другой паспорт.
func build(data: MobRigData) -> void:
	rig = data
	_clear()
	for part_data: Dictionary in rig.parts:
		_add_part(part_data)
	_face = _node(FACE_PART) as Sprite2D
	_face_idle = null
	_face_damage = null
	if _face != null:
		_face_idle = _face.texture                                    # картинка из паспорта
		if not rig.face_idle.is_empty():                              # face_idle главнее
			_face_idle = _texture(rig.face_idle)
			_face.texture = _face_idle
		_face_damage = _texture(rig.face_damage)
	_walk = rig.walk_poses
	_idle = rig.idle_poses
	_pose_fps = rig.pose_fps
	_idle_fps = rig.idle_pose_fps
	_moving = false
	_holding = false
	_face_timer = 0.0
	reset_poses()
	var first: Array = _walk if not _walk.is_empty() else _idle
	if not first.is_empty():
		apply_pose(first[0])


## Одна часть: сустав по attach_pos, спрайт — на самом суставе (offset = -pivot_px).
## Дети крепятся к родителю по имени родительской части; "" и неизвестный родитель — корень.
func _add_part(part_data: Dictionary) -> void:
	var part_name: String = part_data["name"]
	var path: String = part_data["texture"]
	# Лицо может быть задано только в face_idle: тогда часть всё равно собираем спрайтом.
	if part_name == FACE_PART and path.is_empty():
		path = rig.face_idle
	var node: Node2D
	if path.is_empty():
		node = Node2D.new()
	else:
		var sprite := Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = _texture(path)
		sprite.centered = false
		sprite.offset = -(part_data["pivot_px"] as Vector2)
		node = sprite
	node.name = part_name
	node.z_index = part_data.get("z_index", 0)
	node.position = part_data["attach_pos"]
	var parent_name: String = part_data["parent"]
	var parent: Node2D = self
	if not parent_name.is_empty():
		if _parts.has(parent_name):
			parent = _parts[parent_name]["node"]
		else:
			push_warning("MobVisual (%s): часть %s ссылается на неизвестного родителя %s — креплю к корню" % [name, part_name, parent_name])
	parent.add_child(node)
	_parts[part_name] = {
		"node": node,
		"key": _pose_key(part_name),
		"attach": part_data["attach_pos"] as Vector2,
	}


## Снести прежнее дерево (перед пересборкой).
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_parts.clear()
	_face = null


## Узел-сустав части по имени (null — такой части нет).
func _node(part_name: String) -> Node2D:
	var info: Dictionary = _parts.get(part_name, {})
	return info.get("node", null) as Node2D


## Сустав части по имени — для своих узлов (дуло, точка вылета снаряда, эффект).
func part(part_name: String) -> Node2D:
	return _node(part_name)


## Текстура по пути из паспорта; "" → null (часть без картинки).
func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("MobVisual (%s): не загрузилась текстура %s" % [name, path])
	return tex


## Ключ позы части: имя CamelCase → snake_case (Body → body, ArmL → arm_l, ArmBack → arm_back).
## Из него в кадрах берутся "<ключ>_pos" и "<ключ>_rot".
static func _pose_key(part_name: String) -> String:
	var key := ""
	for i in part_name.length():
		var symbol := part_name[i]
		var upper := symbol.to_upper()
		if i > 0 and symbol == upper and upper != symbol.to_lower():
			key += "_"
		key += symbol.to_lower()
	return key


# ============================================================================
# ВИД (масштаб и зеркало — на этом узле, не на CharacterBody2D врага)
# ============================================================================
## Масштаб арта из паспорта (1.0 — если паспорта нет).
func art_scale() -> float:
	return maxf(rig.art_scale, 0.01) if rig != null else 1.0


## Масштаб из паспорта + зеркало по scale.x: 1.0 — как нарисовано, -1.0 — отражение.
## Зеркалим именно Visual, чтобы не масштабировалась и не отражалась физика врага.
func set_art_transform(mirror: float) -> void:
	var s := art_scale()
	scale = Vector2(s * mirror, s)


# ============================================================================
# АНИМАЦИЯ
# ============================================================================
## Бежит моб или стоит: набор кадров и их частота берутся из паспорта
## (walk_poses/idle_poses, pose_fps/idle_pose_fps). Звать из _process скрипта врага.
func set_moving(moving: bool) -> void:
	_moving = moving


## Разовая поза вместо листания (удар, прыжок, прицел). Звать КАЖДЫЙ кадр, пока поза нужна:
## пока её зовут, MobVisual стоит на ней и кадры walk/idle не листает.
func hold_pose(p: Dictionary) -> void:
	if not _holding:
		_holding = true    # вход в разовую позу = смена состояния: листание с первого кадра
		reset_poses()
	apply_pose(p)


## Вернуться к листанию после hold_pose: продолжит с первого кадра.
func release_pose() -> void:
	if not _holding:
		return
	_holding = false
	reset_poses()


## Сброс листания на первый кадр.
func reset_poses() -> void:
	_pose_index = 0
	_pose_timer = 0.0


## Применить позу: каждой части — смещение "<ключ>_pos" и поворот "<ключ>_rot" (градусы).
## Части, которых в позе нет, остаются на своём attach_pos с нулевым поворотом.
func apply_pose(p: Dictionary) -> void:
	for info: Dictionary in _parts.values():
		var node: Node2D = info["node"]
		var key: String = info["key"]
		node.position = (info["attach"] as Vector2) + (p.get(key + "_pos", Vector2.ZERO) as Vector2)
		node.rotation = deg_to_rad(p.get(key + "_rot", 0.0) as float)


func _process(delta: float) -> void:
	_update_face(delta)
	if _holding:
		return
	var poses: Array = _walk if _moving else _idle
	if poses.is_empty():
		return
	# Листание рывком: кадр держится 1/fps, копится остаток времени (дельта не квантуется).
	var period := 1.0 / maxf(_pose_fps if _moving else _idle_fps, 0.001)
	_pose_timer += delta
	while _pose_timer >= period:
		_pose_timer -= period
		_pose_index = (_pose_index + 1) % maxi(poses.size(), 1)
		apply_pose(poses[_pose_index % poses.size()])


# ============================================================================
# ЛИЦО
# ============================================================================
## Временно показать лицо урона (MobRigData.face_damage), потом само вернётся к покою.
## Держим ровно 2 кадра бега (2 / pose_fps) — как было у жёлтого врага.
func flash_damage_face() -> void:
	if _face == null or _face_damage == null:
		return
	_face.texture = _face_damage
	_face_timer = 2.0 / maxf(_pose_fps, 0.001)


func _update_face(delta: float) -> void:
	if _face == null:
		return
	_face_timer = maxf(_face_timer - delta, 0.0)
	# Смена лица рывком, без плавности: пару кадров лицо «урон», потом обратно.
	_face.texture = _face_damage if _face_timer > 0.0 else _face_idle
