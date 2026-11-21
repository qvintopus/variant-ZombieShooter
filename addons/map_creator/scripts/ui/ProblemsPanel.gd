## The room's live problems (MapChecks, refreshed after every edit): a list at the bottom
## right, opened from the topbar's problem count. Clicking one moves the edit camera to it.
class_name ProblemsPanel
extends PanelContainer

@export var creator:MapCreator
@export var panel_size:Vector2 = Vector2(220, 80)

var _list:ItemList
var _cells:Array = []

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 0.95)
	_style.set_content_margin_all(2)
	add_theme_stylebox_override(&"panel", _style)
	_list = ItemList.new()
	_list.custom_minimum_size = panel_size
	_list.item_selected.connect(_go_to)
	add_child(_list)
	creator.problems_changed.connect(refresh)
	creator.problems_requested.connect(toggle)
	creator.mode_changed.connect(func (editing:bool)->void:
		if !editing:
			visible = false)

func toggle()->void:
	visible = !visible
	if visible:
		refresh()

func refresh()->void:
	if !visible:
		return
	_list.clear()
	_cells.clear()
	for _problem:Dictionary in creator.problems:
		_list.add_item(_problem.text)
		_cells.append(_problem.get("cell"))
	if creator.problems.is_empty():
		_list.add_item("No problems found")
		_cells.append(null)
	reset_size()
	var _parent:Vector2 = (get_parent() as Control).size
	position = _parent - size - Vector2(2, 2)

func _go_to(index:int)->void:
	var _cell:Variant = _cells[index] if index < _cells.size() else null
	if _cell is Vector2i && creator.camera != null:
		creator.camera.global_position = creator.cell_center(_cell)
		creator.selection.clear()
		creator.flash_cell = _cell
