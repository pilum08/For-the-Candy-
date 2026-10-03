extends Node
class_name WaveManager
## МЕНЕДЖЕР ВОЛН: гонит волны мобов через MobSpawner по расписанию из WaveData.
## Живёт в уровне (main.tscn) рядом со спавнером. Своих координат не требует: где ставить
## мобов, решает MobSpawner (справа за краем экрана, по таблице).
##
## ХОД ВОЛН (start()):
##   first_wave_delay (пауза перед первой волной) →
##   волна: mob_count мобов с паузой spawn_interval и потолком max_alive живых →
##   ждём, пока всех мобов волны убьют → pause_after → следующая волна → ...
##   последняя волна заспавнена и вычищена → победа (all_waves_cleared).
##
## СОБЫТИЯ НАРУЖУ (попапы/HUD подключим позже — пока на каждое print в консоль):
##   wave_started(index, total) — «Волна 1 из 3 началась» (index считается с 1);
##   wave_cleared(index)        — «Волна 1 пройдена»;
##   all_waves_cleared          — «Победа! Все волны отражены».
##
## СМЕРТЬ ГЕРОЯ: умер — спавн прекращаем (слушаем сигнал died героя); сцену перезапускает
## сам герой (Player.gd в конце смерти зовёт reload_current_scene).
##
## ЗАПУСК: снаружи — start(); его зовёт триггер уровня WaveTrigger.tscn (один раз, когда герой
## доходит до укрепления). Для отладки осталась клавиша F2 — она работает только при
## DebugKeys.ENABLED = true (см. DebugKeys.gd).
##
## Почему ожидание волны на опросе, а не только на сигнале о смерти: моб гибнет сигналом
## died, но если моб исчезнет из сцены без него, await по сигналу повис бы навсегда. Опрос
## раз в WAIT_STEP с проверкой удалённых этого не боится и стоит копейки.
##
## class_name стоит намеренно: он нужен для @export Array[WaveData] — инспектор видит тип
## элементов, а в списке лежат отдельные файлы-ресурсы волн (wave_1.tres, wave_2.tres,
## wave_3.tres), на которые узел WaveManager ссылается из main.tscn.

## Группа героя: по ней ищем, чей died слушать (так же ищет цель Enemy.gd).
const PLAYER_GROUP: StringName = &"player"
## Шаг опроса при ожидании, сек: и «мобов волны убили», и «освободился слот max_alive».
const WAIT_STEP := 0.25


# ============================================================================
# СИГНАЛЫ
# ============================================================================
## Волна началась: index — номер с 1, total — сколько всего волн в списке.
signal wave_started(index: int, total: int)
## Волна пройдена: всех её мобов убили.
signal wave_cleared(index: int)
## Победа: последняя волна вычищена. Сюда позже вешаем попап победы.
signal all_waves_cleared

# ============================================================================
# НАСТРОЙКИ
# ============================================================================
@export_group("Волны")
## Волны по порядку. Тип жёсткий (Array[WaveData]) — не-волну в список не положить.
## По умолчанию три волны лежат отдельными файлами-ресурсами: wave_1.tres (4 моба),
## wave_2.tres (6), wave_3.tres (8) — интервал 1.5 с, потолок живых 0, пауза после волны 4 с.
## Ссылки на них стоят на узле WaveManager в main.tscn, а не вложенными sub_resource: так
## каждая волна — отдельный файл, её видно в FileSystem и правят независимо.
## Менять: правкой .tres либо прямо здесь (Add Element → New WaveData).
@export var waves: Array[WaveData] = []
## Общая таблица мобов. У волны своя spawn_table главнее. Пусто — спавнер возьмёт свою
## default_table.
@export var common_table: SpawnTable
## Пауза перед первой волной, сек. У следующих волн пауза своя — WaveData.pause_after.
@export var first_wave_delay: float = 2.0

@export_group("Победа")
## true — после победы перезагрузить сцену (пока попапа победы нет). false — только принт.
@export var reload_on_victory: bool = false
## Через сколько секунд после победы перезагружать сцену (reload_on_victory = true).
@export var victory_reload_delay: float = 3.0

@export_group("Связи")
## Спавнер мобов. Пусто — берём соседний узел MobSpawner (в main.tscn он рядом).
@export var spawner: MobSpawner

@export_group("Тест (временно)")
## TODO: временный запуск волн клавишей F2 — УБРАТЬ вместе с TEST_KEY и _unhandled_input,
## когда волны будет запускать триггер уровня.
@export var start_on_test_key: bool = true

# ============================================================================
# СОСТОЯНИЕ
# ============================================================================
## Волны идут (start() уже позвали, волны ещё не кончились).
var _running := false
## Спавнер, найденный в start().
var _spawner: MobSpawner = null
## Мобы текущей волны, ещё живые (по ним и потолок max_alive, и «волна пройдена»).
var _wave_mobs: Array[Node] = []
## Герой, чей died слушаем.
var _player: Node = null


# ============================================================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================================
func _ready() -> void:
	# Печать хода волн — временная замена попапов: сами попапы подпишем на эти же сигналы.
	wave_started.connect(_print_wave_started)
	wave_cleared.connect(_print_wave_cleared)
	all_waves_cleared.connect(_print_victory)
	# Ввод для тестовой клавиши включаем явно (TODO: убрать вместе с _unhandled_input).
	# DebugKeys.ENABLED — общий выключатель: при false клавиша F2 не делает ничего.
	set_process_unhandled_input(DebugKeys.ENABLED and start_on_test_key)


# ============================================================================
# ЗАПУСК
# ============================================================================
## Запустить волны. Зовёт внешний триггер уровня (или клавиша F2 в тесте).
## Пока волны идут, повторный вызов игнорируется с предупреждением.
func start() -> void:
	if _running:
		push_warning("WaveManager: волны уже идут — повторный start() пропущен.")
		return
	if waves.is_empty():
		push_warning("WaveManager: список waves пуст — волн нет, спавнить нечего.")
		return
	_spawner = _resolve_spawner()
	if _spawner == null:
		push_warning("WaveManager: не нашёл MobSpawner — спавнить нечем.")
		return
	_running = true
	_connect_player()
	await _run_waves()


## Волны идут прямо сейчас: true — start() действительно начал волны и они ещё не кончились.
## Удачный start() ставит флаг до первого await, так что сразу после вызова значение честное.
## false — либо волн ещё не запускали, либо start() вышел раньше (пустой список волн или не
## нашёлся спавнер), либо волны уже кончились (победа или смерть героя).
## Нужно триггеру уровня (WaveTrigger): по нему он решает, блокировать ли камеру и ставить
## стену — если волны не пошли, сигнала победы не будет и снимать блокировку станет нечем.
func is_running() -> bool:
	return _running


# ============================================================================
# ХОД ВОЛН
# ============================================================================
## Все волны по порядку: пауза перед первой → волна → пауза после неё → ... → победа.
func _run_waves() -> void:
	if first_wave_delay > 0.0:
		await get_tree().create_timer(first_wave_delay).timeout
	var total := waves.size()
	for i in total:
		if not _running:      # герой погиб — дальше не идём (сцену перезапустит Player.gd)
			return
		var data := waves[i] as WaveData
		if data == null:
			push_warning("WaveManager: волна %d — не WaveData, пропускаю." % (i + 1))
			continue
		var index := i + 1
		wave_started.emit(index, total)
		await _spawn_wave(data)
		if not _running:
			return
		await _wait_wave_cleared()
		if not _running:
			return
		wave_cleared.emit(index)
		# Пауза после волны. У последней не играет: после неё сразу победа.
		if data.pause_after > 0.0 and index < total:
			await get_tree().create_timer(data.pause_after).timeout
	all_waves_cleared.emit()
	_running = false   # волны кончились: start() снова разрешён (уровень/триггер может перезапустить)
	if reload_on_victory:
		await get_tree().create_timer(maxf(victory_reload_delay, 0.0)).timeout
		if get_tree().current_scene != null:
			get_tree().reload_current_scene()


## Ставит мобов волны: mob_count штук с паузой spawn_interval и потолком max_alive живых.
func _spawn_wave(data: WaveData) -> void:
	_wave_mobs.clear()   # считаем только мобов этой волны
	var count := maxi(data.mob_count, 0)
	var interval := maxf(data.spawn_interval, 0.0)
	var limit := maxi(data.max_alive, 0)
	for i in count:
		if not _running:
			return
		await _wait_for_slot(limit)
		var table: SpawnTable = data.spawn_table if data.spawn_table != null else common_table
		var mob := _spawner.spawn_mob(table)
		if mob != null:
			_wave_mobs.append(mob)
		if interval > 0.0 and i < count - 1:
			await get_tree().create_timer(interval).timeout


## Ждём, пока живых мобов волны станет меньше limit (limit <= 0 — ждать нечего).
func _wait_for_slot(limit: int) -> void:
	while limit > 0 and _wave_mobs_alive() >= limit:
		await get_tree().create_timer(WAIT_STEP).timeout


## Ждём, пока всех мобов волны убьют.
func _wait_wave_cleared() -> void:
	while _wave_mobs_alive() > 0:
		await get_tree().create_timer(WAIT_STEP).timeout


## Сколько мобов волны ещё в сцене. Заодно выкидывает уже удалённых: моб, ушедший из сцены
## без сигнала died, тоже перестаёт считаться — ожидание не заклинит.
func _wave_mobs_alive() -> int:
	var live: Array[Node] = []
	for mob in _wave_mobs:
		if is_instance_valid(mob):
			live.append(mob)
	_wave_mobs = live
	return live.size()


# ============================================================================
# ГЕРОЙ
# ============================================================================
## Подписка на смерть героя. Герой ищется в группе "player" — по той же группе враги
## (Enemy.target_group) ищут цель.
func _connect_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var found := get_tree().get_first_node_in_group(PLAYER_GROUP)
	if found == null:
		push_warning("WaveManager: в сцене нет узла в группе \"player\" — смерть героя волны не остановит.")
		return
	if not found.has_signal("died"):
		push_warning("WaveManager: у героя нет сигнала died — смерть героя волны не остановит.")
		return
	_player = found
	found.connect("died", _on_player_died)


## Герой погиб — волны останавливаем сразу (спавн прекращается, ожидания выходят по _running).
## Сцену перезапустит сам герой: Player.gd в конце смерти зовёт reload_current_scene.
## TODO: сюда же вешаем попап смерти, когда он появится.
func _on_player_died(_hero: Node) -> void:
	if not _running:
		return
	_running = false
	print("Герой погиб — волны остановлены")


# ============================================================================
# СЛУЖЕБНОЕ
# ============================================================================
## Спавнер: поле в инспекторе, иначе соседний узел MobSpawner.
func _resolve_spawner() -> MobSpawner:
	if spawner != null:
		return spawner
	var parent := get_parent()
	if parent == null:
		return null
	var found := parent.get_node_or_null("MobSpawner") as MobSpawner
	if found == null:
		return null
	push_warning("WaveManager: поле Spawner пустое — работаю с соседним узлом MobSpawner. Задать поле в инспекторе надёжнее.")
	return found


# ============================================================================
# ПЕЧАТЬ ХОДА ВОЛН (временно, вместо попапов: TODO — заменить подписками попапов)
# ============================================================================
func _print_wave_started(index: int, total: int) -> void:
	print("Волна %d из %d началась" % [index, total])


func _print_wave_cleared(index: int) -> void:
	print("Волна %d пройдена" % index)


func _print_victory() -> void:
	print("Победа! Все волны отражены")


# ============================================================================
# ТЕСТ (временно, TODO: убрать)
# ============================================================================
## Клавиша теста: F2 (клавиатура не зависит от раскладки). TODO: убрать вместе с методом.
const TEST_KEY := KEY_F2


## TODO: временный запуск волн с клавиатуры — зовёт start(). Убрать этот метод вместе с
## TEST_KEY / start_on_test_key, когда волны будет запускать триггер уровня.
func _unhandled_input(event: InputEvent) -> void:
	if not start_on_test_key:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != TEST_KEY:
		return
	get_viewport().set_input_as_handled()
	start()
