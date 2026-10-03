extends RefCounted
## Сборка персонажа из отдельных PNG — механизм для таблицы частей (см. Player.gd → RIG).
##
## Подключается к персонажу так (без class_name — чтобы не зависеть от кэша глобальных
## классов редактора, который в headless-прогоне может быть не обновлён):
##     const Rig := preload("res://Rig.gd")
##     ... Rig.apply(self, RIG) ...
##
## У каждой части в таблице ровно два «говорящих» числа:
##   "pivot_px"   — точка сустава ВНУТРИ самой картинки, в её пикселях от левого верхнего
##                  угла (например центр розового конца руки). Механизм ставит её так:
##                  Sprite2D.centered = false, Sprite2D.offset = -pivot_px, тогда
##                  узел-сустав оказывается ровно на суставе картинки.
##   "attach_pos" — куда этот сустав встаёт НА РОДИТЕЛЕ (пиксели арта, до art_scale).
##                  Пишется в position узла-сустава; позы/прицел потом добавляют к нему
##                  свои микросмещения и повороты.
## Плюс две ссылки на узлы (пути от корня персонажа):
##   "node"   — узел-сустав (position = attach_pos);
##   "sprite" — Sprite2D этой части. Ключ не указан → спрайт = сам "node" (так у оверлеев:
##              лицо лежит прямо на пивоте головы, торс — на талии). "" → спрайта нет
##              (например Marker2D Muzzle, откуда вылетает камень).
##
## Размер PNG в таблице не нужен: при centered = false и offset = -pivot_px картинка
## рисуется ровно там же, где рисовалась при centered = true, поэтому обрезка краёв
## PNG на вид не влияет. Замена картинки на обрезанную = правка только pivot_px.
## Враг собирается этим же кодом: свой const RIG в Enemy.gd + Rig.apply(self, RIG).


## Расставляет суставы и настраивает спрайты по таблице частей.
static func apply(root: Node, parts: Dictionary) -> void:
	for part_name: String in parts:
		var part: Dictionary = parts[part_name]
		var pivot_node := root.get_node_or_null(part["node"]) as Node2D
		if pivot_node == null:
			push_warning("Rig (%s): нет узла-сустава %s (часть %s)" % [root.name, part["node"], part_name])
			continue
		pivot_node.position = part["attach_pos"]

		var sprite_path: String = part.get("sprite", part["node"])
		if sprite_path.is_empty():
			continue   # часть без картинки: задан только сустав
		var sprite := root.get_node_or_null(sprite_path) as Sprite2D
		if sprite == null:
			push_warning("Rig (%s): нет Sprite2D %s (часть %s)" % [root.name, sprite_path, part_name])
			continue
		sprite.centered = false
		sprite.offset = -(part["pivot_px"] as Vector2)


## attach_pos части — «покой» сустава в координатах родителя (для таблиц поз).
static func attach(parts: Dictionary, part_name: String) -> Vector2:
	return parts[part_name]["attach_pos"]


## pivot_px части — сустав внутри картинки, в её пикселях.
static func pivot(parts: Dictionary, part_name: String) -> Vector2:
	return parts[part_name]["pivot_px"]


## Таблица частей текстом: часть | родитель | узел-сустав | спрайт | attach_pos | pivot_px.
## Значения всегда берутся из самой таблицы, так что её можно печатать в любой момент.
static func dump(parts: Dictionary) -> String:
	var head: Array = ["часть", "родитель", "узел-сустав", "спрайт", "attach_pos", "pivot_px"]
	var rows: Array = []
	for part_name: String in parts:
		var part: Dictionary = parts[part_name]
		var node_path: String = part["node"]
		var sprite_path: String = part.get("sprite", node_path)
		var anchor := sprite_path if not sprite_path.is_empty() else node_path
		var parent_name := _parent_part(parts, anchor)
		rows.append([
			part_name,
			parent_name if not parent_name.is_empty() else "—",
			node_path,
			sprite_path if not sprite_path.is_empty() else "—",
			str(part["attach_pos"]),
			str(part["pivot_px"]),
		])

	var widths: Array = []
	for column in head.size():
		var width: int = (head[column] as String).length()
		for row: Array in rows:
			width = maxi(width, (row[column] as String).length())
		widths.append(width)

	var lines: Array = [_row_text(head, widths), "-".repeat(_row_width(widths))]
	for row: Array in rows:
		lines.append(_row_text(row, widths))
	return "\n".join(lines)


# ============================================================================
# ВНУТРЕННЕЕ
# ============================================================================
## Имя части, которой принадлежит узел path (его родитель), или "" если не нашли.
static func _parent_part(parts: Dictionary, path: String) -> String:
	var parent_path := path.get_base_dir()
	for part_name: String in parts:
		if (parts[part_name]["node"] as String) == parent_path:
			return part_name
	return ""


static func _row_text(cells: Array, widths: Array) -> String:
	var out: Array = []
	for i in cells.size():
		out.append(_pad(cells[i] as String, widths[i] as int))
	return "  ".join(out)


static func _row_width(widths: Array) -> int:
	var total := 2 * maxi(widths.size() - 1, 0)
	for width: int in widths:
		total += width
	return total


static func _pad(text: String, width: int) -> String:
	return text + " ".repeat(maxi(width - text.length(), 0))
