class_name LevelController
extends Node
## КОНТРОЛЛЕР УРОВНЯ — единственное место, где объявляется исход забега: победа или поражение.
## Сам он уровень не трогает: печатает результат, глушит спавн башни и при поражении
## перезагружает сцену.
##
## КТО ЗОВЁТ:
##   * win()  — башня: Tower в _ready подписывает свой сигнал destroyed на win() того узла,
##              который найден в группе "level_controller";
##   * fail() — любой, кто знает причину провала. Сейчас это пушка: Cannon, оказавшаяся ниже
##              уровня старта, зовёт fail("пушка потеряна").
##   * can_spawn_corpse() — враг: если трупов уже лимит, моб вместо трупа разлетается на части
##              (см. Enemy._die / MobDeathBurst.gd).
##   * is_any_pit_full()  — враг: после заполнения хоть одной ямы моб с шансом decay_chance_when_pit_full
##              тоже разлетается на части (см. Enemy._die).
##
## ГДЕ ЖИВЁТ: узел LevelController в main.tscn (группа "level_controller"). Скрипты, которые
## контроллера не нашли, пишут предупреждение в консоль и дальше работают как обычно.
##
## ИСХОД ОДИН: после победы поражение не объявляется, после поражения победа — тоже.
## Повторный win()/fail() молчит (перезапуск и печать в консоль — по одному разу).

## Группа башни (Tower.tscn: groups = ["tower"]) — её спавн глушим при поражении.
const TOWER_GROUP: StringName = &"tower"
## Группа ям (Pit.tscn: groups = ["pits"]) — по их секциям считается ёмкость под трупы.
const PIT_GROUP: StringName = &"pits"
## Группа лежащих трупов (Corpse.tscn: groups = ["corpses"]) — по ней видно занятое место.
const CORPSE_GROUP: StringName = &"corpses"

@export_group("Поражение")
## Пауза перед перезагрузкой сцены после поражения, с: даём увидеть провал и прочитать консоль.
## 0 — перезагружаем сразу.
@export var fail_reload_delay: float = 2.0

@export_group("Трупы")
## Запас трупов сверх ёмкости ямы: сколько трупов уровень готов держать помимо тех, что лягут в
## заполненные секции ям. Лимит = section_count всех ям (группа "pits") + corpse_reserve; лимит
## исчерпан — новый моб вместо трупа разлетается на части (см. Enemy._die / MobDeathBurst.gd).
@export var corpse_reserve: int = 4
## Шанс (0–1), что полёгший моб РАЗЛЕТИТСЯ на части, а не оставит труп, если хотя бы одна яма уже
## заполнена (см. is_any_pit_full). Лимит трупов ниже работает независимо и всегда даёт разлёт.
## 0 — вероятность выключена (после заполнения ямы всё как обычно), 1 — после заполнения ямы
## разлетаются все.
@export_range(0.0, 1.0, 0.05) var decay_chance_when_pit_full: float = 0.5

## Победа объявлена (башня разрушена). Пока никто не слушает — под будущий экран победы.
signal level_won
## Поражение объявлено: reason — причина для консоли и будущего экрана («пушка потеряна»).
signal level_failed(reason: String)

## Исход уже объявлен: и win(), и fail() после этого молчат.
var _won: bool = false
var _failed: bool = false
## Хотя бы одна яма (группа "pits") заполнена целиком (её pit_completed). Поднимается один раз и
## больше не опускается: заполненную яму назад не отыграть (см. is_any_pit_full).
var _any_pit_full: bool = false


func _ready() -> void:
	_connect_tower()
	_connect_pits()


## Победа: печатает «Победа!» ровно один раз. После поражения победа не объявляется.
func win() -> void:
	if _won or _failed:
		return
	_won = true
	print("Победа!")
	level_won.emit()


## Поражение: печатает причину, останавливает спавн башни (её метод stop_spawning) и через
## fail_reload_delay перезагружает сцену. Повторный вызов (и вызов после победы) молчит.
func fail(reason: String) -> void:
	if _failed or _won:
		return
	_failed = true
	print("Поражение: %s" % reason)
	_stop_tower_spawning()
	level_failed.emit(reason)
	await get_tree().create_timer(maxf(fail_reload_delay, 0.0)).timeout
	# F6 (герой без уровня) — перезагружать нечего, молча выходим (как Player.die).
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


# ============================================================================
# СВЯЗИ
# ============================================================================
## Подписка на башню: её destroyed зовёт win(). Башни в сцене нет или у неё нет сигнала —
## предупреждение в консоль, дальше ничего (уровень работает как обычно).
func _connect_tower() -> void:
	var tower := get_tree().get_first_node_in_group(TOWER_GROUP)
	if tower == null:
		push_warning("LevelController: в сцене нет узла в группе \"tower\" — о разрушении башни я не узнаю.")
		return
	if not tower.has_signal(&"destroyed"):
		push_warning("LevelController: у башни нет сигнала destroyed — победа по разрушению не сработает.")
		return
	tower.connect(&"destroyed", win)


## Остановить спавн башни (мобов из её двери): у живой башни метод есть. Уже выпущенные мобы
## остаются на уровне — они просто добегают. Башни нет — останавливать нечего, молчим.
func _stop_tower_spawning() -> void:
	var tower := get_tree().get_first_node_in_group(TOWER_GROUP)
	if tower != null and tower.has_method(&"stop_spawning"):
		tower.call(&"stop_spawning")


## Подписка на ямы (группа "pits"): как только любая заполнится целиком (её сигнал pit_completed),
## у контроллера поднимается _any_pit_full, и полёгшие мобы начинают разлетаться на части с шансом
## decay_chance_when_pit_full (см. Enemy._die). Ям в сцене нет — подписываться не на что, молчим.
func _connect_pits() -> void:
	for pit in get_tree().get_nodes_in_group(PIT_GROUP):
		if pit.has_signal(&"pit_completed"):
			pit.connect(&"pit_completed", _on_pit_completed)


## Яма заполнена целиком (любая из группы "pits"): запоминаем — теперь работает вероятность разлёта
## (см. is_any_pit_full). Обратно флаг не опускается.
func _on_pit_completed() -> void:
	_any_pit_full = true


# ============================================================================
# ЛИМИТ ТРУПОВ
# ============================================================================
## Сколько трупов уровень держит: ёмкость ям (сумма section_count всех узлов группы "pits")
## плюс corpse_reserve. Ям в сцене нет — только corpse_reserve.
func get_max_corpses() -> int:
	var total := maxi(corpse_reserve, 0)
	for pit in get_tree().get_nodes_in_group(PIT_GROUP):
		total += int(pit.get(&"section_count"))
	return total


## Есть ли ещё место под труп: лежащих трупов (группа "corpses") меньше лимита. Нет — враг вместо
## трупа разлетается на части (см. Enemy._die).
func can_spawn_corpse() -> bool:
	return get_tree().get_nodes_in_group(CORPSE_GROUP).size() < get_max_corpses()


## Заполнена ли целиком хотя бы одна яма (группа "pits"): true — любой полёгший моб может разлететься
## на части с шансом decay_chance_when_pit_full (см. Enemy._die). Ям в сцене нет или ни одна ещё
## не заполнена — false.
func is_any_pit_full() -> bool:
	return _any_pit_full
