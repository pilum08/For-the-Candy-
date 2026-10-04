extends StaticBody2D
class_name Tower
## БАШНЯ — цель уровня и источник мобов: стоит справа, из двери у её левого края выбегают
## мобы и бегут к герою. У башни есть HP: обычное попадание её только дёргает, а урон
## снимает отдельный метод apply_damage() — позже его будет звать ядро пушки (сейчас, для
## проверки, отладочная клавиша F3 за своим флагом debug_keys).
##
## ЧТО ДЕЛАЕТ:
##   * СПАВН: пока башня жива, спавн активен и герой жив — если своих живых меньше max_alive,
##     выпускает пачку (не больше свободных слотов) и ждёт group_interval. Моб появляется
##     в SpawnDoor (левое-нижнее ребро башни), а не за краем экрана: спавнеру передаётся
##     позиция (MobSpawner.spawn_mob(table, at));
##   * считает ТОЛЬКО своих мобов: за каждого заспавненного подписывается на его died,
##     поэтому мобы засад (EncounterTrigger) и волн в счёт башни не входят;
##   * ПОПАДАНИЕ: take_hit() — только рывок, HP не меняется; apply_damage() — снимает HP;
##   * ЛОМАЕТСЯ: destroy() — спавн стоп, коллизия off, «Башня разрушена. Победа!» в консоль,
##     сигнал destroyed. Уже выпущенные мобы остаются на уровне.
##
## ГДЕ ЖИВЁТ: отдельная сцена Tower.tscn, инстанцируется в уровень (main.tscn) справа, за
## всеми триггерами и засадами. Позиция узла — координаты земли уровня.
##
## СЛОИ: корпус на слое 9 «башня» (бит 256), маска 0 — сам никого не ищет (как Ground).
## Героя и врагов не блокирует: в их масках (4 = земля) слоя 9 нет. Попадает в башню
## только снаряд: в Projectile.tscn в маску добавлен слой 9 (6 → 262).
##
## ЗАГЛУШКА: корпус сейчас — ColorRect с надписью «Башня» (узел Visual). TODO: заменить
## рисунком; разрушение с анимацией и кирпичами — тоже TODO (см. destroy()).
##
## СВЯЗИ: Spawner (MobSpawner) — поле в инспекторе, пусто — берём узел из группы
## "mob_spawner" (в main.tscn спавнер в неё входит) и пишем предупреждение. Герой для
## сигнала died ищется в группе "player" (как в WaveManager).
##
## class_name стоит намеренно: по нему уровень и будущее ядро пушки видят тип Tower.

## Группа героя (Player.tscn: groups=["player"]) — по ней ищем, чей died слушать.
const PLAYER_GROUP: StringName = &"player"
## Группа, по которой ищем спавнер, если поле Spawner пустое (main.tscn: узел MobSpawner).
const SPAWNER_GROUP: StringName = &"mob_spawner"
## Шаг проверки потолка max_alive, сек: пачку не выпускаем, но и следующую group_interval
## не ждём — просто проверяем, не освободился ли слот.
const FULL_WAIT_STEP := 0.25

# ============================================================================
# СИГНАЛЫ
# ============================================================================
## Башня разрушена: спавн остановлен, коллизия выключена. Сюда позже вешаем попап победы.
signal destroyed

# ============================================================================
# НАСТРОЙКИ (крутить тут)
# ============================================================================
@export_group("Бой")
## Сколько урона держит башня. Камень и любые другие попадания HP не снимают (см.
## take_hit), урон приходит только через apply_damage().
@export var max_hp: float = 1000.0

@export_group("Спавн")
## Сколько мобов в пачке.
@export var group_size: int = 4
## Пауза между пачками, сек (отсчитывается от выпуска последнего моба пачки).
@export var group_interval: float = 10.0
## Потолок СВОИХ живых мобов у башни. 0 — без лимита.
@export var max_alive: int = 8
## Пауза между мобами внутри пачки, сек (0 — выходят разом).
@export var spawn_stagger: float = 0.5
## Кого выпускать. Пусто — общая таблица спавнера (MobSpawner.default_table).
@export var spawn_table: SpawnTable

@export_group("Активация")
## Размер зоны активации (узел ActivationZone) в пикселях: герой вошёл — спавн пошёл.
## Сам узел ActivationZone двигается в сцене руками, здесь задаётся только размер.
@export var activation_size: Vector2 = Vector2(500, 1200)

@export_group("Реакция на попадание")
## Позы рывка: смещения заглушки в пикселях, корпус башни от них не двигается.
## Анимации нет — позы сменяются рывком (как стоп-моушен у мобов), по twitch_pose_time
## на позу, после последней заглушка встаёт на место.
@export var twitch_offsets: Array[Vector2] = [Vector2(7, -2), Vector2(-5, 1)]
## Сколько секунд держится одна поза рывка.
@export var twitch_pose_time: float = 0.06

@export_group("Связи")
## Спавнер мобов. Пусто — берём узел из группы "mob_spawner".
@export var spawner: MobSpawner

@export_group("Тест (временно)")
## TODO: временная клавиша F3 — снимает 200 урона через apply_damage(). УБРАТЬ вместе с
## TEST_KEY / _unhandled_input, когда урон будет давать ядро пушки. false — F3 молчит.
@export var debug_keys: bool = false


# ============================================================================
# УЗЛЫ
# ============================================================================
## Заглушка корпуса: её и дёргает рывок (коллизию трогать нельзя — она у корня).
@onready var visual: Node2D = $Visual
## Коллизия корпуса: выключается в destroy() — камни начинают пролетать сквозь башню.
@onready var body_shape: CollisionShape2D = $Shape
## Дверь у нижнего левого края: точка появления мобов (Marker2D).
@onready var spawn_door: Marker2D = $SpawnDoor
## Зона активации: герой вошёл — спавн пошёл. Размер задаёт activation_size.
@onready var activation_zone: Area2D = $ActivationZone

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
## Текущее HP (в _ready ставится max_hp).
var _hp: float = 0.0
## Башня уже разрушена: второй раз ничего не делаем.
var _destroyed: bool = false
## Зона активации уже сработала: герой подходил (второй раз спавн не запускаем).
var _activated: bool = false
## Спавн идёт: герой вошёл в зону активации, башня жива и герой жив.
var _spawning: bool = false
## Мобы, которых выпустила ИМЕННО эта башня (её счётчик живых).
var _my_mobs: Array[Node2D] = []
## Сколько мобов осталось выпустить в текущей пачке (0 — пачка выпущена).
var _pack_left: int = 0
## Таймеры спавна: пауза между пачками и пауза между мобами внутри пачки.
var _interval_timer: float = 0.0
var _stagger_timer: float = 0.0
## Герой, чей died слушаем (по нему спавн прекращается).
var _player: Node = null
## Положение заглушки «как в сцене»: рывок — это смещение от него.
var _visual_base := Vector2.ZERO
## Номер позы рывка (-1 — рывка нет) и таймер текущей позы.
var _twitch_index: int = -1
var _twitch_timer: float = 0.0
## Сторона рывка: +1 — башню толкнуло вправо (камень летел вправо), -1 — влево.
var _twitch_flip: float = 1.0


# ============================================================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================================
func _ready() -> void:
	_hp = max_hp
	_visual_base = visual.position
	_apply_activation_size()
	activation_zone.body_entered.connect(_on_activation_body_entered)
	# Ввод для тестовой клавиши включаем явно (TODO: убрать вместе с _unhandled_input).
	set_process_unhandled_input(debug_keys)


func _physics_process(delta: float) -> void:
	_tick_twitch(delta)   # рывок от попадания
	_tick_spawn(delta)    # пачки мобов


# ============================================================================
# УРОН И РАЗРУШЕНИЕ
# ============================================================================
## Попадание в башню: она ТОЛЬКО реагирует — дёргается рывком и всё, HP не меняется.
## Так отрабатывают камень героя и любые другие попадания (снаряд после вызова сам
## исчезает, см. Projectile._on_body_entered). Сигнатура как у Enemy.take_hit: снаряд
## зовёт take_hit(damage, direction) — damage здесь не используется, direction задаёт
## сторону рывка.
func take_hit(_damage: float, direction: Vector2) -> void:
	if _destroyed:
		return
	_twitch(direction)


## Единственный путь снять у башни HP. Зовёт ядро пушки (сделаем позже), сейчас — клавиша
## F3 в тесте. При HP <= 0 башня разрушается.
func apply_damage(damage: float) -> void:
	if _destroyed:
		return
	_hp -= damage
	_twitch(Vector2.ZERO)
	# ВРЕМЕННО (вместо HUD): по этой строке видно, что HP правда падает.
	print("Башня: попадание %.0f, осталось HP %.0f" % [damage, maxf(_hp, 0.0)])
	if _hp <= 0.0:
		destroy()


## Разрушение: спавн останавливаем, коллизию выключаем, заглушку скрываем и объявляем
## победу. Мобы, которые уже на уровне, остаются и продолжают бежать.
## TODO: анимация разрушения и кирпичи (Debris) — отдельной задачей.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_spawning = false
	_pack_left = 0
	body_shape.set_deferred("disabled", true)   # камни и всё прочее теперь пролетают сквозь башню
	activation_zone.set_deferred("monitoring", false)
	print("Башня разрушена. Победа!")
	visual.visible = false
	destroyed.emit()


# ============================================================================
# РЫВОК (реакция на попадание: 1–2 позы, рывком, без плавности)
# ============================================================================
## Запустить рывок: показываем первую позу сразу. Повторное попадание перезапускает рывок.
func _twitch(direction: Vector2) -> void:
	if twitch_offsets.is_empty():
		return
	# Камень летел влево (direction.x < 0) — он пришёл справа, башню толкнуло влево.
	if direction != Vector2.ZERO:
		_twitch_flip = -1.0 if direction.x < 0.0 else 1.0
	_twitch_index = 0
	_twitch_timer = twitch_pose_time
	visual.position = _visual_base + _twitch_pose(0)


## Смещение позы с учётом стороны рывка.
func _twitch_pose(index: int) -> Vector2:
	var offset := twitch_offsets[index]
	return Vector2(offset.x * _twitch_flip, offset.y)


## Тик рывка: позы сменяются рывком по twitch_pose_time, после последней — на место.
func _tick_twitch(delta: float) -> void:
	if _twitch_index < 0:
		return
	_twitch_timer -= delta
	if _twitch_timer > 0.0:
		return
	_twitch_index += 1
	if _twitch_index >= twitch_offsets.size():
		_twitch_index = -1
		visual.position = _visual_base
		return
	_twitch_timer = twitch_pose_time
	visual.position = _visual_base + _twitch_pose(_twitch_index)


# ============================================================================
# СПАВН ПАЧЕК (своих мобов башня считает сама: заспавнила — подписалась на died)
# ============================================================================
func _tick_spawn(delta: float) -> void:
	if not _spawning:
		return
	if _pack_left > 0:
		# Пачка выпускается не разом, а рывками по spawn_stagger.
		_stagger_timer -= delta
		if _stagger_timer > 0.0:
			return
		_release_one()
		return
	_interval_timer -= delta
	if _interval_timer > 0.0:
		return
	_start_pack()


## Собрать новую пачку: сколько мобов, и сразу выпустить первого.
func _start_pack() -> void:
	var free_slots := group_size
	if max_alive > 0:
		# Больше свободных слотов, чем позволяет max_alive, не выпускаем.
		free_slots = mini(group_size, max_alive - alive_own())
	if free_slots <= 0:
		# Своих живых уже под потолок: подождём FULL_WAIT_STEP и проверим снова
		# (group_interval тут не ждём — пачка выйдет, как только освободится слот).
		_interval_timer = FULL_WAIT_STEP
		return
	_pack_left = free_slots
	_stagger_timer = 0.0
	# ВРЕМЕННО (вместо HUD): по этой строке видно, что пачка вышла и сколько своих живых.
	print("Башня: пачка из %d (своих живых %d)" % [_pack_left, alive_own()])
	_release_one()


## Выпустить одного моба из пачки: он появляется в SpawnDoor и бежит к герою сам
## (Enemy гонится за целью из группы player). Заспавненного записываем в свои и слушаем
## его died — свой счётчик живых считается по этому списку.
func _release_one() -> void:
	_pack_left = maxi(_pack_left - 1, 0)
	_stagger_timer = spawn_stagger
	var found := _resolve_spawner()
	if found != null:
		var mob: Node2D = found.spawn_mob(spawn_table, spawn_door.global_position)
		if mob != null:
			_my_mobs.append(mob)
			if mob.has_signal("died"):
				mob.connect("died", _on_own_mob_died)
	# Пачка выпущена — только теперь пауза между пачками.
	if _pack_left <= 0:
		_interval_timer = group_interval


## Сколько СВОИХ мобов башни ещё живо. Заодно выкидывает уже удалённых: моб, ушедший из
## сцены без сигнала died, тоже перестаёт считаться (как в MobSpawner.alive_count).
func alive_own() -> int:
	var live: Array[Node2D] = []
	for mob in _my_mobs:
		if is_instance_valid(mob):
			live.append(mob)
	_my_mobs = live
	return _my_mobs.size()


## Смерть своего моба: он больше не держит слот max_alive.
func _on_own_mob_died(mob: Node2D) -> void:
	_my_mobs.erase(mob)


# ============================================================================
# АКТИВАЦИЯ И ГЕРОЙ
# ============================================================================
## Герой вошёл в зону активации — башня начинает спавн. Один раз за проход уровня.
func _on_activation_body_entered(body: Node2D) -> void:
	if _activated or _destroyed:
		return
	if not body.is_in_group(PLAYER_GROUP):
		return
	_activated = true
	# Зона нужна ровно один раз. Выключение отложенное: мы внутри сигнала body_entered,
	# менять monitoring прямо здесь физика запрещает (ERROR: Function blocked during in/out signal).
	activation_zone.set_deferred("monitoring", false)
	_spawning = true
	_interval_timer = 0.0                # первую пачку выпускаем сразу
	_connect_player()


## Размер зоны активации из инспектора: форма строится в коде, чтобы крутить её числом,
## а сам узел ActivationZone в сцене двигать руками.
func _apply_activation_size() -> void:
	var shape := activation_zone.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		push_warning("Tower: у ActivationZone нет узла Shape — размер зоны активации не применён.")
		return
	var rect := RectangleShape2D.new()
	rect.size = activation_size
	shape.shape = rect


## Подписка на смерть героя: герой ищется в группе "player" — по той же группе цели ищут
## враги (Enemy.target_group) и WaveManager слушает смерть.
func _connect_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var found := get_tree().get_first_node_in_group(PLAYER_GROUP)
	if found == null:
		push_warning("Tower: в сцене нет узла в группе \"player\" — смерть героя спавн не остановит.")
		return
	if not found.has_signal("died"):
		push_warning("Tower: у героя нет сигнала died — смерть героя спавн не остановит.")
		return
	_player = found
	found.connect("died", _on_player_died)


## Герой погиб — пачки больше не выходят. Сцену перезапускает сам герой (Player.gd),
## уже выпущенные мобы просто продолжают бежать.
func _on_player_died(_hero: Node) -> void:
	if not _spawning:
		return
	_spawning = false
	print("Башня: герой погиб — спавн остановлен")


# ============================================================================
# СВЯЗИ
# ============================================================================
## Спавнер: поле из инспектора, иначе узел из группы "mob_spawner". Найденное запоминаем,
## чтобы предупреждение не печаталось на каждого моба.
func _resolve_spawner() -> MobSpawner:
	if spawner != null:
		return spawner
	var found := get_tree().get_first_node_in_group(SPAWNER_GROUP) as MobSpawner
	if found == null:
		push_warning("Tower: не нашёл MobSpawner (поле Spawner пусто, в группе mob_spawner никого) — мобов не будет.")
		return null
	spawner = found
	push_warning("Tower: поле Spawner пусто — беру MobSpawner из группы mob_spawner. Надёжнее задать поле в инспекторе.")
	return found


# ============================================================================
# ТЕСТ (временно, TODO: убрать)
# ============================================================================
## Клавиша теста: F3 (не зависит от раскладки). TODO: убрать вместе с методом.
const TEST_KEY := KEY_F3
## Сколько урона снимает тестовая клавиша.
const TEST_DAMAGE := 200.0


## TODO: временная клавиша проверки HP — зовёт apply_damage(TEST_DAMAGE). Убрать этот метод
## вместе с TEST_KEY / debug_keys, когда урон башне будет давать ядро пушки.
func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != TEST_KEY:
		return
	get_viewport().set_input_as_handled()
	apply_damage(TEST_DAMAGE)
