extends Resource
class_name SpawnTable
## ТАБЛИЦА СПАВНА: список записей (SpawnEntry) и взвешенный жребий по ним.
##
## КАК НАПОЛНЯТЬ (пример — spawn_table_level1.tres):
##   1. Открыть таблицу двойным щелчком в FileSystem (откроется в инспекторе).
##   2. Развернуть entries → Add Element → New SpawnEntry (её поля появятся тут же).
##   3. У записи задать mob_scene (сцена врага) — или mob_data (паспорт вида) и weight.
##   4. Новый моб = новая запись. Шансы = веса: у всех 1.0 — выпадают поровну,
##      3.0 против 1.0 — первый в три раза чаще.
##
## Жребий тянет СВОЙ генератор (RandomNumberGenerator), поэтому не сбивает randf() других
## систем и не зависит от них.
##
## class_name стоит намеренно: по нему поля типа SpawnTable (WaveManager.common_table,
## MobSpawner.default_table, WaveData.spawn_table) инспектор показывает своим типом.

# ============================================================================
# ЗАПИСИ
# ============================================================================
## Записи таблицы, элементы — SpawnEntry. Тип массива намеренно не жёсткий (как parts
## в MobRigData): чужой ресурс в списке жребий молча пропускает, а жёсткий Array[SpawnEntry]
## ломал бы загрузку .tres, если в него положили не-SpawnEntry.
@export var entries: Array = []

# ============================================================================
# ЖРЕБИЙ
# ============================================================================
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Взвешенный случайный выбор. Вернёт null, если годных записей нет (пустая таблица,
## у всех весов 0, у всех записей нет ни сцены, ни паспорта).
func pick() -> SpawnEntry:
	var total := 0.0
	for item in entries:
		var entry := item as SpawnEntry
		if entry != null and entry.is_usable() and entry.weight > 0.0:
			total += entry.weight
	if total <= 0.0:
		return null
	var roll := _rng.randf_range(0.0, total)
	var last: SpawnEntry = null
	for item in entries:
		var entry := item as SpawnEntry
		if entry == null or not entry.is_usable() or entry.weight <= 0.0:
			continue
		last = entry
		roll -= entry.weight
		if roll < 0.0:
			return entry
	return last   # сюда попадаем только из-за округления float — отдаём последнюю годную
