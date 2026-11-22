## World-space drawing of the map creator: cell grid, brush preview under the cursor,
## selection and entity markers (spawns, triggers... that have no art in game).
class_name MapOverlay
extends Node2D

@export var creator:MapCreator

## Extra draw passes (selection, entity markers) register here: Callable(overlay).
var passes:Array[Callable] = []
## Layers menu: entity markers on / off.
var show_entities:bool = true

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	visible = false

func _process(_delta:float)->void:
	if visible:
		queue_redraw()

## Color of fight section `number` (1-based): spawns, triggers and barriers of the section
## the waves panel highlights, and its title there.
static func section_color(number:int)->Color:
	return Color.from_hsv(fposmod(0.08 + 0.29 * (number - 1), 1.0), 0.65, 1.0)

## Diamond of a cell, in global coords.
func diamond(cell:Vector2i, shrink:float = 0.0)->PackedVector2Array:
	var _center:Vector2 = creator.cell_center(cell)
	var _half:Vector2 = Vector2(creator.floor_layer.tile_set.tile_size) * 0.5 * (1.0 - shrink)
	return PackedVector2Array([_center + Vector2(0, -_half.y), _center + Vector2(_half.x, 0), _center + Vector2(0, _half.y), _center + Vector2(-_half.x, 0)])

func fill_cell(cell:Vector2i, color:Color, shrink:float = 0.0)->void:
	draw_colored_polygon(diamond(cell, shrink), color)

func outline_cell(cell:Vector2i, color:Color, width:float = 1.0)->void:
	var _points:PackedVector2Array = diamond(cell)
	_points.append(_points[0])
	draw_polyline(_points, color, width)

func _draw()->void:
	if creator == null || creator.floor_layer == null:
		return
	var _preset:MapCreatorPreset = creator.preset
	if creator.settings == null || creator.settings.show_grid:
		for _cell:Vector2i in creator.floor_layer.get_used_cells():
			outline_cell(_cell, _preset.grid_color)
	if creator.layout != null && show_entities:
		_draw_entities(_preset)
	elif creator.layout != null:
		_draw_selection(_preset)
	for _pass:Callable in passes:
		_pass.call(self)
	if !creator.hover_valid || creator.busy || !creator.moving.is_empty():
		return
	var _color:Color = _preset.hover_color
	if creator.tool == MapCreator.Tool.PAINT:
		_color = _preset.brush_color if creator.item == null else Color(creator.item.color, _preset.brush_color.a)
		for _cell:Vector2i in creator.brush_cells(creator.hover_cell):
			fill_cell(_cell, _color)
	elif creator.tool == MapCreator.Tool.ERASE:
		for _cell:Vector2i in creator.brush_cells(creator.hover_cell):
			fill_cell(_cell, _preset.erase_color)
	outline_cell(creator.hover_cell, _preset.hover_color)

## Every entity as a tinted diamond with its legend letter (spawns, triggers and markers
## have no art in game); the inspected one outlined.
func _draw_entities(preset:MapCreatorPreset)->void:
	var _font:Font = ThemeDB.fallback_font
	for _entity:LayoutEntity in creator.layout.entities:
		var _item:MapCatalogItem = creator.catalog.item(_entity.item_id)
		if _item == null:
			continue
		fill_cell(_entity.cell, Color(_item.color, preset.entity_marker_alpha * 0.5), 0.45)
		var _letter:String = _item.legend_char(_entity.props)
		if _letter.is_empty() || _letter == ".":
			_letter = _item.display_name.left(1)
		draw_string(_font, creator.cell_center(_entity.cell) + Vector2(-2, 2), _letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, preset.entity_marker_alpha))
	if creator.highlight_section > 0:
		var _color:Color = section_color(creator.highlight_section)
		for _entity:LayoutEntity in creator.layout.entities:
			if _entity.props.has("section") && int(_entity.props.section) == creator.highlight_section:
				outline_cell(_entity.cell, _color, 1.5)
	if creator.flash_cell is Vector2i:
		var _pulse:float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		outline_cell(creator.flash_cell, Color(1, 0.4, 0.2, _pulse), 2.0)
	if creator.inspected != null:
		outline_cell(creator.inspected.cell, preset.selection_color, 1.5)
	_draw_selection(preset)

## Selected cells, the Ctrl+drag box, and the ghost of a move/duplicate under the cursor.
func _draw_selection(preset:MapCreatorPreset)->void:
	for _entry:Dictionary in creator.selection.entries():
		fill_cell(_entry.cell, Color(preset.selection_color, preset.selection_color.a * 0.6), 0.15)
		outline_cell(_entry.cell, preset.selection_color)
	if creator.box_from != null:
		var _from:Vector2i = creator.box_from
		var _min:Vector2i = _from.min(creator.hover_cell)
		var _max:Vector2i = _from.max(creator.hover_cell)
		for _y:int in range(_min.y, _max.y + 1):
			for _x:int in range(_min.x, _max.x + 1):
				outline_cell(Vector2i(_x, _y), preset.selection_color)
	if !creator.moving.is_empty():
		var _delta:Vector2i = creator.hover_cell - creator.moving.origin
		for _p:Dictionary in creator.moving.payload:
			fill_cell(_p.cell + _delta, Color(creator._type_color(_p.type), 0.5), 0.1)
