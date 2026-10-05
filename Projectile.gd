extends Area2D
## Снаряд — камень (Sprites/stone.bmp). Летит в сторону курсора от Muzzle по дуге,
## исчезает при попадании в стену/врага, по таймеру жизни и при выходе за экран.
## Слои: collision_layer = 4 (снаряды), collision_mask = 2|3|9 — см. сцену
## (маска = враги (layer 2) + земля/стены (layer 3) + башня (layer 9)).
## Попадание во врага: у цели вызывается take_hit(damage, direction) — урон берётся
## из data.damage, направление — вектор полёта (см. Enemy.gd). Враг — тело
## (CharacterBody2D), поэтому он приходит в _on_body_entered, а не в _on_area_entered.
## Попадание в башню разбирается отдельной веткой (по группе "tower"): у Tower.take_hit та же
## сигнатура, что у врага, но HP она так НЕ теряет — только дёргается, а камень всё равно исчезает
## (см. Tower.gd). Ядро пушки с can_damage_tower бьёт по HP — см. флаги ниже.
##
## ФЛАГИ ЯДРА (data, см. ProjectileData.gd) включают другие ветки — у камня они выключены:
##   * can_damage_tower — попадание в башню зовёт Tower.apply_damage(data.damage) вместо
##     take_hit: башня теряет HP, а при нуле разрушается (Tower.destroyed → победа);
##   * pierce_enemies  — снаряд отдаёт урон врагу и летит дальше, а не исчезает;
##   * report_miss     — попал в землю/стену, кончилось время жизни или ушёл за экран:
##     перед исчезновением снаряд шлёт сигнал missed (по нему Cannon объявляет поражение).
## Кто попадает в башню, видно по сигналу hit_tower(tower) — он идёт после apply_damage.
##
## РАЗМЕР: размер задаёт ProjectileData. У ядра пушки он считается по ЕДИНОМУ МАСШТАБУ АРТА
## (ArtScale.hero_scale() × native_mult × size_mult — см. ProjectileData.size_mult и
## docs/SETUP.md, раздел 16): картинка нарисована 1:1 вместе с героем и пушкой, поэтому в мире
## ядро всегда одного размера, при любом герое. У камня size_mult = 0 — его размер по-прежнему
## задаёт тот, кто бросил (art_scale × sprite_scale, поведение не менялось).
##
## ЧИСЛА типа снаряда (текстура/скорость/гравитация/урон/время жизни) лежат в
## ProjectileData.gd (ресурс .tres), а поведение — здесь. Новый тип снаряда:
##   1) сохранить копию .tres и править числа/текстуру (ядро пушки — cannonball.tres);
##   2) если нужно своё поведение при попадании — подкласс Projectile.gd с
##      переопределёнными _on_hit_enemy() / _on_hit_ground() / _on_expire().

## Испускается при любом попадании (в стену, во врага или по времени) — цель в аргументе.
signal hit_target(target: Node)
## Попал в башню — аргумент сама башня. Идёт ПОСЛЕ того, как башне отдана попытка урона
## (apply_damage или take_hit), поэтому по этому сигналу видно, кто попал и по кому.
signal hit_tower(tower: Node)
## Снаряд израсходован впустую: попал в землю/стену, кончилось время жизни или ушёл за экран.
## Шлётся только если data.report_miss (у ядра пушки — да, у камня — нет).
signal missed

## Группа башни (Tower.tscn: groups = ["tower"]) — по ней в _on_body_entered видно попадание.
const TOWER_GROUP: StringName = &"tower"

## Состояние снаряда. FLYING → один терминальный (после него снаряд исчезает).
enum State { FLYING, HIT_ENEMY, LANDED, EXPIRING }

# Тип ресурса данных (без class_name — как Rig.gd, чтобы не зависеть от кэша
# глобальных классов редактора в headless-прогоне).
const ProjectileData := preload("res://ProjectileData.gd")

@export_group("Данные")
## Тип снаряда: текстура, скорость, гравитация, урон, время жизни (см. ProjectileData.gd).
@export var data: ProjectileData

@export_group("Полёт")
## Доп. докрутка картинки, градусов в секунду (120 = камень «катится»).
@export var spin: float = 120.0
## Поворачивать снаряд по вектору скорости: rotation = velocity.angle() (учитывает дугу).
@export var face_velocity: bool = true

@export_group("Вид и попадание")
## Масштаб арта; игрок подставляет свой art_scale при спавне. НЕ используется, если у данных
## задан size_mult > 0: тогда снаряд берёт единый масштаб арта у героя сам (см. _ball_scale).
@export var art_scale: float = 0.35
## Доп. масштаб картинки камня (тоже не используется при size_mult > 0).
@export var sprite_scale: float = 0.6
## Радиус попадания в пикселях арта (сам камень ~143 px в диаметре). При size_mult > 0 не
## используется: там радиус — половина картинки в её мировом масштабе.
@export var hit_radius: float = 40.0

@onready var sprite: Sprite2D = $Sprite
@onready var notifier: VisibleOnScreenNotifier2D = $Notifier

var _state: State = State.FLYING
var _velocity := Vector2.ZERO
## Угол по вектору скорости (когда face_velocity) — spin докручивается поверх него.
var _base_rotation := 0.0
var _roll := 0.0
var _age := 0.0
var _was_on_screen := false


func _ready() -> void:
	if data == null:
		push_warning("Projectile (%s): не задан data (ProjectileData) — беру значения по умолчанию" % name)
		data = ProjectileData.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if data.texture != null:
		sprite.texture = data.texture
	sprite.scale = Vector2.ONE * (art_scale * sprite_scale)
	# Ядро пушки: размер берём по единому масштабу арта (size_mult в данных), а не от art_scale
	# героя — в мире ядро всегда одного размера, как и сама пушка (см. Cannon.gd).
	var ball_k := _ball_scale()
	if ball_k > 0.0:
		sprite.scale = Vector2.ONE * ball_k
	_add_hit_shape()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)


## Вызывается игроком сразу после спавна: единичный вектор направления полёта.
func launch(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	_base_rotation = dir.angle()
	_roll = 0.0
	# Стартовая скорость — точно на курсор, дальше её загибает гравитация (см. _physics_process).
	_velocity = dir.normalized() * data.speed
	if face_velocity:
		rotation = _base_rotation


func _physics_process(delta: float) -> void:
	if _state != State.FLYING:
		return
	# Дуга: гравитация добавляется каждый кадр, поэтому вектор скорости загибается вниз.
	_velocity.y += data.gravity * delta
	global_position += _velocity * delta

	# Картинка смотрит по вектору скорости (на дуге камень «заваливается» за полётом),
	# spin докручивает её поверх — получается катящийся камень.
	if face_velocity and _velocity.length_squared() > 0.0001:
		_base_rotation = _velocity.angle()
	_roll += deg_to_rad(spin) * delta
	rotation = _base_rotation + _roll

	_age += delta
	if _age >= data.lifetime and _finish(State.EXPIRING, null):
		_report_miss()   # время вышло — для ядра это промах
		_on_expire()


# ============================================================================
# ВИРТУАЛЬНЫЕ ХУКИ (переопределяются в подклассах нового типа снаряда)
# По умолчанию во всех случаях снаряд просто исчезает, как раньше. Вызываются
# из коллизий и таймера ниже; _finish() следит, что снаряд ещё FLYING, и один
# раз шлёт сигнал hit_target.
# ============================================================================
## Попал во врага (Area2D). enemy — то, во что попали.
func _on_hit_enemy(enemy: Node) -> void:
	queue_free()


## Попал в землю/стену (StaticBody2D). point — точка попадания, мировые координаты.
func _on_hit_ground(point: Vector2) -> void:
	queue_free()


## Кончилось время жизни или снаряд ушёл за экран.
func _on_expire() -> void:
	queue_free()


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Масштаб снаряда по ЕДИНОМУ МАСШТАБУ АРТА (ArtScale × native_mult × size_mult). 0 — снаряд
## живёт по старой схеме (art_scale × sprite_scale: так камень берёт размер у того, кто бросил).
## Больше нуля — размер задан данными (см. ProjectileData.size_mult).
func _ball_scale() -> float:
	if data == null or data.size_mult <= 0.0:
		return 0.0
	return ArtScale.scale_of(data.native_mult, data.size_mult)


## Форму строим в коде, чтобы корректно отмасштабировать радиус попадания.
func _add_hit_shape() -> void:
	if has_node("Shape"):
		return
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var circle := CircleShape2D.new()
	# Ядро пушки (size_mult): радиус в мире — половина картинки в её масштабе. Камень: как было.
	var ball_k := _ball_scale()
	var width := 0.0
	if ball_k > 0.0 and sprite.texture != null:
		width = sprite.texture.get_size().x
	if ball_k > 0.0 and width > 0.0:
		circle.radius = maxf(width * ball_k * 0.5, 1.0)
	else:
		circle.radius = maxf(hit_radius * art_scale, 1.0)
	shape.shape = circle
	add_child(shape)


func _on_body_entered(body: Node2D) -> void:
	# Башня — тоже StaticBody2D с методом take_hit, поэтому её ветка идёт ПЕРВОЙ: HP снимает
	# только снаряд с can_damage_tower, остальные её лишь дёргают (см. _hit_tower).
	if body.is_in_group(TOWER_GROUP):
		if _finish(State.HIT_ENEMY, body):
			_hit_tower(body)
		return
	# Враг — это тоже тело (CharacterBody2D), поэтому он попадает именно сюда, а не в
	# _on_area_entered. Тело с методом take_hit считаем врагом: отдаём урон и зовём хук
	# попадания во врага. Остальные тела — земля и стены, камень разбивается.
	# body_entered не отдаёт точку касания, поэтому передаём текущий центр снаряда.
	if body.has_method("take_hit"):
		# Пробивающий снаряд (ядро пушки): враг получает урон, а снаряд летит дальше. Состояние
		# остаётся FLYING, поэтому терминальные хуки не зовутся: их смысл — исчезнуть.
		if data.pierce_enemies:
			_damage_target(body)
			return
		if _finish(State.HIT_ENEMY, body):
			_damage_target(body)
			_on_hit_enemy(body)
		return
	if _finish(State.LANDED, body):
		_report_miss()   # у ядра — сигнал missed, по нему Cannon объявляет поражение
		_on_hit_ground(global_position)


## Попадание в башню: снаряд, который умеет её ломать (can_damage_tower — ядро пушки), снимает
## ей HP через Tower.apply_damage: при нуле Tower сам разрушается, а LevelController объявляет
## победу. Все остальные снаряды (камень) её только дёргают — Tower.take_hit. Снаряд после
## попадания исчезает в любом случае, а сигнал hit_tower уходит подписчикам (Cannon ждёт его,
## чтобы понять, добила ли башню эта пуля).
func _hit_tower(tower: Node) -> void:
	if data.can_damage_tower and tower.has_method("apply_damage"):
		tower.call("apply_damage", data.damage)
	elif tower.has_method("take_hit"):
		_damage_target(tower)
	hit_tower.emit(tower)
	queue_free()


## Отдаёт урон цели, если она это умеет: take_hit(damage, direction).
## Единственное место, где урон из ProjectileData.damage уходит врагу.
func _damage_target(target: Node) -> void:
	if not target.has_method("take_hit"):
		return
	target.call("take_hit", data.damage, _velocity.normalized())


## Снаряд израсходован впустую: попал в землю, кончилось время жизни или он ушёл за границы
## экрана. Сообщаем об этом, только если тип снаряда это умеет (data.report_miss — ядро пушки).
## Зовётся ДО исчезновения, поэтому подписчик (Cannon) успевает поймать сигнал missed.
func _report_miss() -> void:
	if data.report_miss:
		missed.emit()


func _on_area_entered(area: Area2D) -> void:
	# Враг (или любая Area2D): отдаём урон, если цель умеет, и зовём хук попадания.
	if _state != State.FLYING:
		return
	_damage_target(area)
	_finish(State.HIT_ENEMY, area)
	_on_hit_enemy(area)


func _on_screen_entered() -> void:
	_was_on_screen = true


func _on_screen_exited() -> void:
	# Убираем только если снаряд реально побывал на экране.
	if _was_on_screen and _finish(State.EXPIRING, null):
		_report_miss()   # ушёл за границы экрана — для ядра это промах
		_on_expire()


## Переводит снаряд из FLYING в терминальное состояние state: фиксирует состояние
## и один раз шлёт hit_target(target). false — снаряд уже завершился (раньше это
## делал флаг _dead; повторные попадания по-прежнему игнорируются).
func _finish(state: State, target: Node) -> bool:
	if _state != State.FLYING:
		return false
	_state = state
	hit_target.emit(target)
	return true
