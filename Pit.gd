extends Node2D
## ЯМА С ШИПАМИ И ЗАМОРОЖЕННЫМИ ТРУПАМИ (часть Б).
##
## PitZone (Area2D, маска = слой 5 «тела») ловит трупы из группы "corpses". Труп, который
## лежит в яме и почти не двигается settle_time секунд, ЗАМОРАЖИВАЕТСЯ: freeze = true,
## freeze_mode = STATIC, collision_layer = слой 6 «замороженные тела», маска = 0. Такой труп
## становится твёрдым куском пола — герой и враги ходят по нему (слой 6 добавлен в их маски),
## а сам он ни с чем не сталкивается. Трупа в руках это не касается: в руках труп лежит
## на слое 0 (Corpse.pickup гасит слои), поэтому PitZone его не видит вовсе.
##
## Верх замороженного трупа подтягивается к уровню пола (см. max_depth): тело встаёт заподлицо,
## и по нему можно перейти яму. Когда замороженных тел стало >= required_corpses (0 = выключено),
## шипы гаснут (monitoring = false) и скрываются — «мост» закрывается и логикой, и просто тем,
## что герой идёт по телам выше шипов.
##
## ШИПЫ: узел SpikeZone с уже существующим SpikeZone.gd — при касании героя зовётся тот же
## Player.die(), что и при ударе врага. Своей логики смерти у ямы нет.
##
## ГЕОМЕТРИЯ — в Pit.tscn (начало координат ямы = УРОВЕНЬ ПОЛА, поэтому max_depth = 0 значит
## «верх трупа не ниже уровня пола», и при переносе ямы в другое место число не меняется):
##   PitZone/Shape   — весь проём ямы (что считать «трупом в яме»);
##   Floor/Shape     — дно ямы (StaticBody2D, слой 3 «земля»: трупы и герой падают на него);
##   SpikeZone       — шипы на дне (Shape + Visual правятся в сцене).

## Слой 5 «тела» — обычный труп врага (Corpse.tscn: collision_layer = 16).
const CORPSE_LAYER: int = 16
## Слой 6 «замороженные тела» — труп стал твёрдым полом (см. project.godot, layer_6).
const FROZEN_LAYER: int = 32
## Группа трупов (Corpse.tscn: groups=["corpses"]).
const CORPSE_GROUP: StringName = &"corpses"

@export_group("Заморозка")
## Скорость (px/с), ниже которой труп считается «лёг» и начинает накапливать время покоя.
@export var settle_speed: float = 30.0
## Сколько секунд подряд труп должен лежать в яме почти неподвижно, чтобы замёрзнуть.
@export var settle_time: float = 0.3
## Насколько низко (px от начала координат Pit) допустим верх трупа после заморозки.
## 0 — уровень пола: тело подтягивается вверх и встаёт заподлицо с полом.
@export var max_depth: float = 0.0

@export_group("Мост")
## Сколько замороженных тел закрывает яму. 0 — выключено: шипы работают всегда.
@export var required_corpses: int = 0

@onready var pit_zone: Area2D = $PitZone
@onready var spike_zone: Area2D = $SpikeZone

## Трупы в яме, которые ещё не замёрзли: тело → сколько секунд подряд оно почти не двигалось.
var _calm: Dictionary = {}
## Замороженные этой ямой тела: по их числу решается, закрылись ли шипы (required_corpses).
var _frozen: Array[RigidBody2D] = []


func _ready() -> void:
	pit_zone.body_entered.connect(_on_pit_body_entered)
	pit_zone.body_exited.connect(_on_pit_body_exited)
	_refresh_spikes()


func _physics_process(delta: float) -> void:
	if _calm.is_empty():
		return
	# keys() отдаёт копию списка, поэтому чистить _calm прямо в цикле безопасно.
	for body in _calm.keys():
		var corpse := body as RigidBody2D
		# Труп исчез из мира или уже выехал из ямы — считать нечего.
		if corpse == null or not is_instance_valid(corpse) or not pit_zone.overlaps_body(corpse):
			_calm.erase(body)
			continue
		if corpse.linear_velocity.length() <= settle_speed:
			_calm[body] = float(_calm[body]) + delta
			if float(_calm[body]) >= settle_time:
				_freeze(corpse)
		else:
			_calm[body] = 0.0   # задел/толкнули — отсчёт покоя заново


## Труп в яме (влетел, упал, бросили). Считаем только настоящий труп на слое «тела»: труп
## в руках героя лежит на слое 0 и сюда не попадает.
func _on_pit_body_entered(body: Node2D) -> void:
	if not body.is_in_group(CORPSE_GROUP) or body.collision_layer != CORPSE_LAYER:
		return
	_calm[body] = 0.0


func _on_pit_body_exited(body: Node2D) -> void:
	_calm.erase(body)


## Труп лёг: замораживаем его, то есть делаем твёрдым куском пола.
func _freeze(corpse: RigidBody2D) -> void:
	_calm.erase(corpse)
	# Страховка: если труп всё-таки оказался в руках (слои погашены) — не трогаем его.
	if corpse.collision_layer != CORPSE_LAYER:
		return
	# Верх считаем ДО заморозки: на эту же дельту труп надо будет подтянуть вверх.
	var top := _body_top_y(corpse)
	corpse.linear_velocity = Vector2.ZERO
	corpse.angular_velocity = 0.0
	corpse.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	corpse.freeze = true
	# Верх трупа не должен уходить ниже уровня пола: тело встаёт заподлицо, и по нему идут.
	var limit := global_position.y + max_depth
	if top > limit:
		corpse.global_position.y -= top - limit
	# Твёрдый пол: слой 6 «замороженные тела» (его видят герой и враги), маска 0 — сам ни с чем
	# не сталкивается. Обычный труп (слой 5) остаётся проходимым для всех.
	corpse.collision_layer = FROZEN_LAYER
	corpse.collision_mask = 0
	_frozen.append(corpse)
	_refresh_spikes()


## Шипы: пока замороженных тел меньше required_corpses, они включены. required_corpses = 0 —
## выключено, шипы работают всегда (мост держится только на самих телах).
func _refresh_spikes() -> void:
	var closed := required_corpses > 0 and _count_frozen() >= required_corpses
	spike_zone.monitoring = not closed
	spike_zone.visible = not closed


## Сколько замороженных тел реально ещё в игре (замороженное тело никто не удаляет: страховка).
func _count_frozen() -> int:
	var alive := 0
	for corpse in _frozen:
		if is_instance_valid(corpse):
			alive += 1
	return alive


## Верх тела в мировых координатах. Форма трупа — капсула (Corpse.tscn → Collider), её верх —
## это верхняя из двух чашек капсулы минус радиус. Труп мог катиться (форма повёрнута), поэтому
## берём мировой трансформ формы, а не локальные числа: у Corpse scale всегда 1, так что радиус
## и высота капсулы — уже мировые.
func _body_top_y(body: Node2D) -> float:
	var shape_node := body.get_node_or_null("Collider") as CollisionShape2D
	if shape_node == null:
		return body.global_position.y
	var capsule := shape_node.shape as CapsuleShape2D
	if capsule == null:
		return body.global_position.y
	var half_axis := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var xf := shape_node.global_transform
	var a := xf * Vector2(0.0, -half_axis)
	var b := xf * Vector2(0.0, half_axis)
	return minf(a.y, b.y) - capsule.radius
