extends Area2D
class_name EncounterTrigger
## ЗАСАДА: герой доходит до точки — из-за правого края экрана выбегают 1–2 моба.
## Отдельная сцена EncounterTrigger.tscn инстанцируется в уровень (main.tscn).
##
## Своей логики спавна у засады нет: она только зовёт MobSpawner.spawn_group(). Где ставить
## мобов и по какой таблице тянуть жребий — дело спавнера (справа за краем экрана).
##
## НАСТРОЙКИ (инспектор, группа «Засада»):
##   * Count          — сколько мобов выпустить (для засад уровня 1–2);
##   * Spawn Table    — таблица шансов; ПУСТО = default_table спавнера (spawn_table_level1.tres);
##   * Spawn Interval — пауза между мобами пачки, сек;
##   * Once           — true (по умолчанию): сработать один раз за проход уровня,
##                      false: срабатывать на каждый вход героя в зону.
##
## СВЯЗИ (группа «Связи»): Spawner — обычно узел MobSpawner, перетащенный в поле. Пусто —
## ищем узел в группе "mob_spawner" (в main.tscn спавнер в неё входит) и пишем предупреждение:
## задать поле в инспекторе надёжнее.
##
## СЛОИ: зона на слое 0, маска 1 — видит только героя (слой «игрок»), как SpikeZone.
## Геометрия — узел Shape. Триггер намеренно невидим: в редакторе его видно по выделению и
## по отладочным коллизиям (Отладка → Видимые коллизии), а в игре он ничего не рисует.

## Группа героя (Player.tscn: groups=["player"]).
const PLAYER_GROUP: StringName = &"player"
## Группа, по которой ищем спавнер, если поле Spawner пустое (main.tscn: узел MobSpawner).
const SPAWNER_GROUP: StringName = &"mob_spawner"

@export_group("Засада")
## Сколько мобов выпустить. Для засад уровня — 1–2.
@export_range(1, 2, 1) var count: int = 2
## Таблица шансов (какие именно мобы). Пусто — общая таблица спавнера (MobSpawner.default_table).
@export var spawn_table: SpawnTable
## Пауза между мобами пачки, сек (0 — выходят разом).
@export var spawn_interval: float = 1.0
## true — засада срабатывает один раз за проход уровня; false — на каждый вход героя.
@export var once: bool = true

@export_group("Связи")
## Спавнер мобов. Пусто — берём узел из группы "mob_spawner".
@export var spawner: MobSpawner

## Уже стреляла (при once = true повторные входы игнорируем).
var _fired := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Герой вошёл в зону. Мобы и обломки игнорируются: по маске сюда попадает только герой,
## но проверка группы делает это явным.
func _on_body_entered(body: Node2D) -> void:
	if _fired and once:
		return
	if not body.is_in_group(PLAYER_GROUP):
		return
	var found := _resolve_spawner()
	if found == null:
		return
	_fired = true
	# spawn_group сама делает паузы между мобами; ждать её тут нечего — герой уже в бою.
	found.spawn_group(count, spawn_table, spawn_interval)


# ============================================================================
# СВЯЗИ
# ============================================================================
## Спавнер: поле из инспектора, иначе узел из группы "mob_spawner".
func _resolve_spawner() -> MobSpawner:
	if spawner != null:
		return spawner
	var found := get_tree().get_first_node_in_group(SPAWNER_GROUP) as MobSpawner
	if found == null:
		push_warning("EncounterTrigger: не нашёл MobSpawner (поле Spawner пусто, в группе mob_spawner никого) — засада не сработала.")
		return null
	push_warning("EncounterTrigger: поле Spawner пусто — беру MobSpawner из группы mob_spawner. Задать поле в инспекторе надёжнее.")
	return found
