extends Node2D
## ЯМА ИЗ СЕКЦИЙ (часть Б).
##
## Яма — это N секций в ряд (PitSection.tscn, N = section_count). Каждая секция — одна ячейка от
## уровня пола до дна ямы; что происходит внутри ячейки, описано в PitSection.gd. Правила ямы:
##   * труп, упавший в ПУСТУЮ секцию, там останавливается: тело удаляется, а в секции встаёт его
##     плоская картинка; секция становится ЗАПОЛНЕННОЙ — пол включается, смерть гаснет, по ней
##     можно идти;
##   * труп, упавший на ЗАПОЛНЕННУЮ секцию, падает на её пол (уровень пола) и остаётся обычным
##     физическим трупом: секцию он не меняет, подбирается и бросается как всегда, лимит трупов
##     считает его как обычно;
##   * пока секция пуста, смертельна только полоса шипов у её дна: шагнувший в ячейку герой
##     падает через всю глубину ямы и умирает уже на дне. Прыжка в игре нет, перепрыгнуть яму
##     нечем.
##
## Когда заполнены ВСЕ секции: сигнал pit_completed, печать в консоль «Яма заполнена», шипы
## (SpikeZone: зона смерти и визуал) гаснут — пройти яму можно поверх полов секций, а они ровно
## на уровне пола, как обычная земля. Заполненные секции безопасны сразу и по отдельности:
## ходить по ним можно, не дожидаясь последней, а шагнуть в соседнюю пустую — смерть.
##
## ЧТО В ПИТЕ (Pit.tscn), кроме секций:
##   Bottom (StaticBody2D, слой 4 «земля») — дно ямы на всю её ширину (Shape 680×40 при +130, то
##   есть верх ровно на pit_depth): на нём лежат упавшие трупы, обломки героя и сам герой;
##   SpikeZone (Area2D, маска 1, SpikeZone.gd) — шипы: серая подложка дна (узел Visual, его не
##   трогаем) и смертельная полоса у дна (Shape 680×30 при +95 = нижние 30 px ямы — та же
##   полоса, что у DeathZone в секциях, см. PitSection.gd);
##   Sections (Node2D) — сюда _build_sections кладёт секции (в редакторе секций не видно: они
##   создаются в рантайме).
## Начало координат Pit — УРОВЕНЬ ПОЛА: секции ставятся по X в ряд, Y = 0 (см. PitSection.gd).
##
## ГЕОМЕТРИЯ: pit_width — ширина ямы (по умолчанию 680 — как Shape узлов Bottom и SpikeZone в
## сцене), pit_depth — от уровня пола до дна (110: верх Bottom/Shape 680×40 при +130). Ширина
## секции = pit_width / section_count; она должна быть похожа на ширину трупа (арт
## Enemy_corpse.png 784×589 при art_scale 0.21, то есть ≈165×124 px): картинка трупа в ячейке НЕ
## подгоняется по размеру, поэтому в узких секциях картинки налезут друг на друга, а в широких
## между ними будет просвет (см. PitSection._spawn_fill).
##
## Слой 6 «замороженные тела» ямой не используется (заморозки физикой нет, и в масках героя и
## врагов его нет). Сам слой в project.godot оставлен — см. docs/SETUP.md, раздел про слои.

const PIT_SECTION_SCENE := preload("res://PitSection.tscn")

@export_group("Секции")
## Сколько секций в ряду. Ширина секции = pit_width / section_count.
@export_range(1, 16, 1) var section_count: int = 4
## Ширина ямы (px). По умолчанию 680 — как Shape узлов Bottom и SpikeZone в сцене: дыру задают
## они, поэтому, поменяв число здесь, поправь и их.
@export var pit_width: float = 680.0
## Глубина ямы (px) от уровня пола до дна: по ней садится на дно картинка трупа (см. PitSection).
## 110 снято со сцены — верх Bottom/Shape 680×40 при +130.
@export var pit_depth: float = 110.0

@export_group("Смерть в пустой секции")
## Высота смертельной полосы шипов у дна секции (px, от дна вверх, во всю ширину секции). Пока
## секция пуста и её пол выключен, герой падает через всю глубину ямы и умирает на дне — смерть
## ждёт его только в этой полосе (плюс такая же полоса у шипов самой ямы, узел SpikeZone).
@export var spike_kill_height: float = 30.0

@export_group("Заполнение секции")
## Скорость (px/с), ниже которой труп в ячейке считается «лёг».
@export var settle_speed: float = 30.0
## Сколько секунд подряд труп должен пролежать в ячейке почти неподвижно, чтобы её заполнить.
@export var settle_time: float = 0.3
## Страховка: труп провалялся в ячейке столько секунд, так и не успокоившись (катится, дрожит
## на другом трупе). Истекло — ячейка всё равно заполняется.
@export var settle_timeout: float = 1.5
## На сколько пикселей низ картинки трупа выше дна ячейки (0 — ровно на дне).
@export var bottom_overlap_px: float = 6.0
## Разброс картинки по X от центра ячейки, ±px. Картинка не подгоняется под ячейку, поэтому при
## большом сдвиге труп налезет на соседнюю секцию — это допустимо (см. PitSection.gd).
@export var x_jitter: float = 8.0
## Разброс наклона картинки, ±градусы. 0 — строго плоско.
@export_range(0.0, 45.0, 0.5) var tilt_jitter: float = 5.0

## Секция заполнена (index — её номер). Секция безопасна для героя сразу после этого.
signal section_filled(index: int)
## Заполнены все секции: яма пройдена.
signal pit_completed

@onready var spike_zone: Area2D = $SpikeZone
@onready var sections_root: Node2D = $Sections

## Секции по порядку (0 — левая).
var _sections: Array[PitSection] = []
## Сколько секций заполнено.
var _filled: int = 0
## Все секции заполнены (защита от повторной обработки: сигнал и печать — один раз).
var _completed: bool = false


func _ready() -> void:
	_build_sections()
	# Начальное состояние шипов: пока секции пусты, дно ямы смертельно и нарисовано.
	spike_zone.monitoring = true
	spike_zone.visible = true


## Построить секции в ряд. Они создаются в рантайме (не @tool), поэтому в редакторе видно только
## контейнер Sections. Все параметры заполнения копируются в каждую секцию ДО add_child: свою
## геометрию (зоны, пол) секция раскладывает в _ready по этим числам.
func _build_sections() -> void:
	var count := maxi(section_count, 1)
	var width := pit_width / float(count)
	var x := -pit_width * 0.5   # левый край 1-й ячейки; X каждой следующей = правый край предыдущей
	_sections.clear()
	_filled = 0
	_completed = false
	for i in count:
		var section := PIT_SECTION_SCENE.instantiate() as PitSection
		section.index = i
		section.section_width = width
		section.pit_depth = pit_depth
		section.spike_kill_height = spike_kill_height
		section.settle_speed = settle_speed
		section.settle_time = settle_time
		section.settle_timeout = settle_timeout
		section.bottom_overlap_px = bottom_overlap_px
		section.x_jitter = x_jitter
		section.tilt_jitter = tilt_jitter
		# Y = 0 — уровень пола (начало координат секции, см. PitSection.gd).
		section.position = Vector2(x, 0.0)
		section.filled.connect(_on_section_filled)
		sections_root.add_child(section)
		_sections.append(section)
		x += width


## Секция заполнилась (труп улёгся в пустую ячейку): считаем и смотрим, вся ли яма заполнена.
func _on_section_filled(index: int) -> void:
	_filled += 1
	section_filled.emit(index)
	if _filled >= _sections.size():
		_complete_pit()


## Заполнены все секции: печать в консоль, шипы гаснут, сигнал pit_completed.
func _complete_pit() -> void:
	if _completed:
		return
	_completed = true
	spike_zone.monitoring = false   # шипы больше никого не убивают
	spike_zone.visible = false      # и не нарисованы
	print("Яма заполнена")
	pit_completed.emit()
