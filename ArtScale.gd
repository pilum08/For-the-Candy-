class_name ArtScale
extends RefCounted
## ЕДИНЫЙ МАСШТАБ АРТА — одна точка правды о размере объектов в мире.
##
## ЗАЧЕМ: весь арт проекта нарисован в одном масштабе 1:1 (герой, пушка, ядро, башня, кирпичи,
## мобы — всё «одним карандашом»). Значит, у ЛЮБОГО объекта в игре должен быть тот же
## коэффициент «пиксель картинки → пиксель мира», что у героя. Этот коэффициент и возвращает
## hero_scale(): масштаб узла Visual героя, куда Player.gd кладёт art_scale × player_scale
## (сейчас 0.35 × 0.6 = 0.21). Свой размер «в пикселях мира» объекты больше не задают — они
## берут масштаб отсюда (пушка, башня, ядро — см. Cannon.gd, Tower.gd, ProjectileData.gd).
##
## ФОРМУЛА (держать в голове, добавляя новый объект):
##     размер в мире = пиксели исходного рисунка × hero_scale() × native_mult × size_mult
##   * hero_scale() — общий масштаб всей игры, сейчас 0.21 (искать не надо: метод вернёт сам);
##   * native_mult  — во сколько раз ИСХОДНЫЙ рисунок больше файла в проекте (исходная ширина /
##                    ширина файла). Файл не уменьшали — 1.0. Читает его объект из инспектора,
##                    посчитать помогает mult_for_native();
##   * size_mult    — подкрутка конкретного объекта: 1.0 — как нарисовано, 2.0 — вдвое крупнее
##                    (ядро пушки — 2.0, «мультяшнее»). Тоже поле инспектора.
## Пример: пушка — cannon.png 630×337 в исходном масштабе, то есть 630 × 0.21 ≈ 132 px.
##
## ГДЕ ЖИВЁТ: RefCounted со статическими методами — узел создавать не нужно, достаточно написать
## ArtScale.scale_of(). Класс ничего не хранит и в сцене не появляется.
##
## КОРНИ НЕ МАСШТАБИРУЕМ: масштаб достаётся ДОЧЕРНЕМУ узлу (Body/Visual), а корень
## (CharacterBody2D/RigidBody2D) остаётся scale = ONE — иначе поедет физика (см. Cannon.gd).
##
## Подробная таблица «исходный размер → множители → размер в мире» и порядок добавления новых
## объектов (копьё, кирпичи, мобы) — в docs/SETUP.md, раздел 16.

## Группа героя (Player.tscn: groups=["player"]) — по ней ищем, у кого спросить масштаб.
const PLAYER_GROUP: StringName = &"player"
## Узел внутри героя, который носит масштаб арта и зеркало (Player.gd → _apply_art_scale).
const HERO_VISUAL: NodePath = ^"Visual"
## Скрипт героя: из него берём запасные числа, если героя в сцене ещё нет.
const HERO_SCRIPT: String = "res://Player.gd"
## Запасной масштаб, если и скрипт героя не прочитался (0.35 × 0.6).
const FALLBACK_SCALE: float = 0.21


## Общий масштаб игры: |global_scale.x| узла Visual ЖИВОГО героя — со всем, что на нём накручено
## (art_scale, player_scale, зеркало героя). Героя в сцене нет (сцена открыта отдельно, объект
## добавлен раньше героя) — те же два числа берём из Player.gd по умолчанию.
static func hero_scale() -> float:
	var visual := _hero_visual()
	if visual != null:
		var s := absf(visual.global_scale.x)
		if s > 0.0:
			return s
	return _hero_default_scale()


## Масштаб объекта в мире: единый масштаб арта × native_mult × size_mult (см. шапку).
## Оба множителя — поля инспектора у самого объекта (пушка и башня — группа «Размер»,
## снаряд — ProjectileData).
static func scale_of(native_mult: float = 1.0, size_mult: float = 1.0) -> float:
	return hero_scale() * maxf(native_mult, 0.0001) * maxf(size_mult, 0.0001)


## Во сколько раз исходный рисунок больше файла в проекте: native_width / ширина текстуры.
## Нужно тем, кто уменьшал файл (например кадры разрушения башни сжаты до 35%): положи
## результат в native_mult — и объект снова встанет в масштаб героя. Файл не уменьшали — 1.0.
static func mult_for_native(native_width: float, texture: Texture2D) -> float:
	if texture == null:
		return 1.0
	var width := texture.get_size().x
	if width <= 0.0:
		return 1.0
	return maxf(native_width, 0.0001) / width


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Узел Visual героя — носитель масштаба: герой ищется по группе "player".
static func _hero_visual() -> Node2D:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	var hero := loop.get_first_node_in_group(PLAYER_GROUP)
	if hero == null:
		return null
	return hero.get_node_or_null(HERO_VISUAL) as Node2D


## Запасные числа героя (art_scale × player_scale) из Player.gd: пустой узел с этим скриптом
## отдаёт значения по умолчанию прямо из инспектора, в дерево его класть не нужно.
static func _hero_default_scale() -> float:
	var script := load(HERO_SCRIPT) as GDScript
	if script == null:
		return FALLBACK_SCALE
	var probe := script.new() as Node
	if probe == null:
		return FALLBACK_SCALE
	var art := float(probe.get(&"art_scale"))
	var player := float(probe.get(&"player_scale"))
	probe.free()
	if art <= 0.0 or player <= 0.0:
		return FALLBACK_SCALE
	return art * player
