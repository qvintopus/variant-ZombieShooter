## One-line text question (new mod / room names), optionally with a second choice button. Opens on creator.prompt_requested;
## Enter or OK calls the answer with the text, Escape or x cancels.
class_name MapPrompt
extends PanelContainer

@export var creator:MapCreator
@export var panel_width:float = 200.0

var _title:Label
var _edit:LineEdit
var _answer:Callable
var _alt:Button
var _alt_answer:Callable

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 1.0)
	_style.set_content_margin_all(3)
	add_theme_stylebox_override(&"panel", _style)
	var _box:VBoxContainer = VBoxContainer.new()
	add_child(_box)
	_title = Label.new()
	_box.add_child(_title)
	var _row:HBoxContainer = HBoxContainer.new()
	_box.add_child(_row)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func (_t:String)->void: confirm())
	_row.add_child(_edit)
	for _entry:Array in [["OK", confirm], ["x", close]]:
		var _b:Button = Button.new()
		_b.text = _entry[0]
		_b.pressed.connect(_entry[1])
		_row.add_child(_b)
	_alt = Button.new()
	_alt.visible = false
	_alt.pressed.connect(func ()->void:
		var _call:Callable = _alt_answer
		close()
		if _call.is_valid():
			_call.call())
	_box.add_child(_alt)
	creator.prompt_requested.connect(ask)
	creator.choice_requested.connect(ask)

## `alt_label` adds a second button running `alt_answer` (no text).
func ask(title:String, initial:String, answer:Callable, alt_label:String = "", alt_answer:Callable = Callable())->void:
	_alt.text = alt_label
	_alt.visible = !alt_label.is_empty()
	_alt_answer = alt_answer
	_title.text = title
	_edit.text = initial
	_answer = answer
	visible = true
	size = Vector2(panel_width, 0)
	reset_size()
	position = ((get_parent() as Control).size - size) * 0.5
	_edit.grab_focus()
	_edit.select_all()

func confirm()->void:
	var _text:String = _edit.text.strip_edges()
	var _call:Callable = _answer
	close()
	if !_text.is_empty() && _call.is_valid():
		_call.call(_text)

func close()->void:
	visible = false
	_answer = Callable()
	_alt_answer = Callable()
	_edit.release_focus()

func _unhandled_key_input(event:InputEvent)->void:
	if visible && event is InputEventKey && event.pressed && event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
