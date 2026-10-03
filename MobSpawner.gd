extends Node
class_name MobSpawner
## СПАВНЕР МОБОВ: ставит врагов справа за краем экрана по таблице (SpawnTable) и следит
## за живыми. Живёт в уровне (main.tscn). Своих координат не требует: место появления
## считается от Camera2D, высота — лучом вниз до земли.
##
## ЧТО ДЕЛАЕТ:
##   * spawn_mob(table) — один моб: таблица тянет жребий (какая запись), запись даёт сцену
##     врага (mob_scene) либо паспорт вида (mob_data + prototype_scene);
##   * spawn_group(count, table, interval) — пачка мобов с паузой между ними;
##   * заспавненным ставит группу "mobs", считает живых (alive_count), а смерть моба
##     пробрасывает наружу сигналом mob_died(mob) — это сигнал Enemy.died.
##
## ПОЧЕМУ ОТ КАМЕРЫ, А НЕ ОТ ЧИСЕЛ: уровень скроллится, фиксированные координаты «где-то
## справа» перестают быть за экраном. Берём то, что камера видит прямо сейчас
## (Camera2D.get_screen_center_position + видимый прямоугольник с учётом зума), прибавляем
## spawn_margin и ищем землю лучом под этой точкой.
##
## class_name стоит намеренно: по нему WaveManager объявляет @export MobSpawner spawner, а поля
## типов SpawnTable (default_table) и SpawnEntry (аргументы методов) видит инспектор.

## Группа, в которую попадает каждый заспавненный моб.
const MOB_GROUP: StringName = &"mobs"

# ============================================================================
# СИГНАЛЫ
# ============================================================================
## Моб родился.
signal mob_spawned(mob: Node2D)
## Заспавненный моб умер: проброс Enemy.died (эмитится до queue_free, моб ещё валиден).
signal mob_died(mob: Node2D)

# ============================================================================
# НАСТРОЙКИ
# ============================================================================
@export_group("Таблица")
## Таблица, если spawn_mob() позвали без аргумента (обычный случай).
@export var default_table: SpawnTable

@export_group("Место появления")
## Насколько отступить вправо от кромки экрана, пиксели мира (моб появляется за кадром).
@export var spawn_margin: float = 200.0
## Искать землю лучом вниз (true). false — ставить сразу на spawn_y.
@export var find_ground: bool = true
## Уровень земли, если лучом не ищем (find_ground = false). Это y ПОВЕРХНОСТИ,
## то есть ровно та высота, на которой моб стоит ногами.
@export var spawn_y: float = 0.0
## Слои земли для луча: по умолчанию 4 = слой 3 «земля и стены» (как collision_layer
## у Ground в main.tscn).
@export_flags_2d_physics var ground_mask: int = 4
## Насколько глубоко вниз пускать луч, пиксели.
@export var ground_ray_depth: float = 3000.0

@export_group("Сцена-прототип")
## Что инстансить, когда у записи задан только паспорт (mob_data): Enemy.tscn по умолчанию,
## его узел Visual пересобирается под паспорт записи. Пусто — мобы, заданные одним паспортом,
## спавниться не будут (сцена не найдена), а заданные сценой (mob_scene) — как обычно.
@export var prototype_scene: PackedScene = preload("res://Enemy.tscn")

@export_group("Тест (временно)")
## TODO: временное включение клавиши теста — УБРАТЬ вместе с _unhandled_input и TEST_KEY,
## когда появление мобов будет звать настоящая логика уровня.
## Сама клавиша работает только при DebugKeys.ENABLED = true (см. DebugKeys.gd) — это общий
## выключатель отладочных клавиш F1/F2 в одном месте.
@export var test_key_enabled: bool = true

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
## Заспавненные мобы (для счётчика). Мёртвые и удалённые мимо смерти выпадают сами —
## см. alive_count().
var _alive: Array[Node] = []


# ============================================================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================================
func _ready() -> void:
	# Ввод для тестовой клавиши включаем явно (TODO: убрать вместе с _unhandled_input).
	# DebugKeys.ENABLED — общий выключатель: при false клавиша F1 не делает ничего.
	set_process_unhandled_input(DebugKeys.ENABLED and test_key_enabled)


# ============================================================================
# СПАВН
# ============================================================================
## Поставить одного моба: таблица тянет жребий, моб появляется справа за краем экрана.
## Бежать к игроку он начинает сам: Enemy.gd гоняется за целью из группы, не глядя на
## расстояние (ограничителя дистанции там нет).
## Вернёт null (с предупреждением в консоль), если спавнить нечем: нет Camera2D, таблицы,
## годной записи или сцены в записи.
func spawn_mob(table: SpawnTable = null) -> Node2D:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		push_warning("MobSpawner: в сцене нет Camera2D — кромку экрана считать не от чего, спавн пропущен.")
		return null
	var src: SpawnTable = table if table != null else default_table
	if src == null:
		push_warning("MobSpawner: не задана таблица спавна (default_table).")
		return null
	var entry: SpawnEntry = src.pick()
	if entry == null:
		push_warning("MobSpawner: таблица не дала запись (пустая, все веса <= 0 или нет ни сцены, ни паспорта).")
		return null
	var scene := _scene_for(entry)
	if scene == null:
		push_warning("MobSpawner: в записи нет ни mob_scene, ни mob_data (или не задан prototype_scene).")
		return null
	var mob := scene.instantiate() as Node2D
	if mob == null:
		push_warning("MobSpawner: корень сцены моба не Node2D — спавн пропущен.")
		return null
	_apply_data(mob, entry)   # паспорт ставим ДО add_child: MobVisual соберётся в своём _ready
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	parent.add_child(mob)
	mob.global_position = _spawn_point(cam)
	_register(mob)
	mob_spawned.emit(mob)
	return mob


## Поставить count мобов с паузой interval секунд между ними (interval <= 0 — все сразу).
## Функция асинхронная: если нужен конец пачки, можно await spawn_group(...).
func spawn_group(count: int, table: SpawnTable = null, interval: float = 0.0) -> void:
	for i in maxi(count, 0):
		spawn_mob(table)
		if interval > 0.0 and i < count - 1:
			await get_tree().create_timer(interval).timeout


# ============================================================================
# ЖИВЫЕ МОБЫ
# ============================================================================
## Сколько заспавненных мобов ещё живо.
func alive_count() -> int:
	var live: Array[Node] = []
	for mob in _alive:
		if is_instance_valid(mob):
			live.append(mob)
	_alive = live
	return _alive.size()


## Список живых заспавненных мобов (копия — править извне нечего).
func alive_mobs() -> Array[Node]:
	alive_count()   # заодно выкидывает мёртвых и удалённых
	var out: Array[Node] = []
	out.assign(_alive)
	return out


## Поставить моба в группу "mobs" и слушать его смерть.
func _register(mob: Node2D) -> void:
	mob.add_to_group(MOB_GROUP)
	_alive.append(mob)
	if mob.has_signal("died"):
		# Enemy.gd: signal died(enemy: Node) — моб передаёт себя, обработчику хватает одного параметра.
		mob.connect("died", _on_mob_died)


func _on_mob_died(mob: Node2D) -> void:
	_alive.erase(mob)
	mob_died.emit(mob)

# ============================================================================
# МЕСТО ПОЯВЛЕНИЯ (всё считается от камеры: координат уровня спавнер не знает)
# ============================================================================
## Точка появления: x — правая кромка видимой области + spawn_margin (то есть за кадром),
## y — земля под этой точкой (луч вниз) или spawn_y, если луч не нужен.
func _spawn_point(cam: Camera2D) -> Vector2:
	# get_screen_center_position — то, что камера видит СЕЙЧАС (учитывает лимиты и сглаживание).
	var center := cam.get_screen_center_position()
	var half := _visible_half(cam)
	var x := center.x + half.x + spawn_margin
	return Vector2(x, _ground_y(x, center.y - half.y))   # луч пускаем из-за верхней кромки: он точно выше земли


## Половина видимой области в пикселях МИРА: видимый прямоугольник делим на зум камеры
## (при stretch "canvas_items" get_visible_rect() — это и есть то, что видно на экране).
func _visible_half(cam: Camera2D) -> Vector2:
	var visible := Vector2(get_viewport().get_visible_rect().size)
	var zoom := Vector2(maxf(cam.zoom.x, 0.001), maxf(cam.zoom.y, 0.001))
	return visible * 0.5 / zoom


## Уровень земли под точкой x: луч вниз из from_y по слоям ground_mask.
## Ничего не задели — возвращаем spawn_y (и пишем предупреждение: над ямой моб упадёт).
func _ground_y(x: float, from_y: float) -> float:
	if not find_ground:
		return spawn_y
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, from_y), Vector2(x, from_y + ground_ray_depth), ground_mask)
	query.collide_with_areas = false
	# Мир берём через viewport: у обычного Node (не Node2D/CanvasItem) своего get_world_2d нет.
	var hit := get_viewport().find_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		push_warning("MobSpawner: земли под x = %.1f нет — ставлю на spawn_y = %.1f." % [x, spawn_y])
		return spawn_y
	return (hit["position"] as Vector2).y


# ============================================================================
# ЗАПИСЬ ТАБЛИЦЫ → СЦЕНА
# ============================================================================
## Сцена для записи: своя сцена главнее, иначе сцена-прототип (её визуал пересоберёт _apply_data).
func _scene_for(entry: SpawnEntry) -> PackedScene:
	if entry.mob_scene != null:
		return entry.mob_scene
	if entry.mob_data != null:
		return prototype_scene
	return null


## Подставить паспорт записи в поле rig узла Visual сцены-прототипа. Если у записи задана своя
## сцена, паспорт не применяется: своя сцена сама знает, каким паспортом собрана.
func _apply_data(mob: Node2D, entry: SpawnEntry) -> void:
	if entry.mob_scene != null or entry.mob_data == null:
		return
	var vis := mob.get_node_or_null("Visual")
	if vis == null or not ("rig" in vis):
		push_warning("MobSpawner: у сцены моба нет узла Visual с полем rig — паспорт записи не применён.")
		return
	vis.set("rig", entry.mob_data)


# ============================================================================
# ТЕСТ (временно, TODO: убрать)
# ============================================================================
## Клавиша теста: F1 (клавиатура не зависит от раскладки). TODO: убрать вместе с методом.
const TEST_KEY := KEY_F1


## TODO: временная клавиша для проверки спавна — зовёт spawn_mob() с default_table.
## Убрать этот метод вместе с TEST_KEY / test_key_enabled, когда появление мобов будет
## звать настоящая логика уровня (триггеры EncounterTrigger и WaveTrigger уже появились).
## Работает только при DebugKeys.ENABLED = true (см. DebugKeys.gd).
func _unhandled_input(event: InputEvent) -> void:
	if not DebugKeys.ENABLED or not test_key_enabled:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != TEST_KEY:
		return
	get_viewport().set_input_as_handled()
	spawn_mob()
