## One-line text question (new mod / room names), optionally with a second choice button. Opens on creator.prompt_requested;
## Enter or OK calls the answer with the text, Escape or x cancels.
## Confirm mode (creator.confirm_requested): a title, an explaining body and one button per
## choice (destructive ones tinted), plus Cancel. No text field.
class_name MapPrompt
extends PanelContainer

@export var creator:MapCreator
@export var panel_width:float = 200.0
## Width of confirm questions (they carry a body text).
@export var confirm_width:float = 230.0

var _title:Label
var _body:Label
var _edit:LineEdit
var _answer:Callable
var _alt:Button
var _alt_answer:Callable
var _text_row:HBoxContainer
var _choices:VBoxContainer

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 1.0)
	_style.set_content_margin_all(4)
	_style.set_corner_radius_all(3)
	_style.border_color = Color(creator.preset.active_color, 0.6)
	_style.set_border_width_all(1)
	add_theme_stylebox_override(&"panel", _style)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 3)
	add_child(_box)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.modulate.a = 0.8
	_body.visible = false
	_box.add_child(_body)
	_text_row = HBoxContainer.new()
	_box.add_child(_text_row)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func (_t:String)->void: confirm())
	_text_row.add_child(_edit)
	for _entry:Array in [["OK", confirm], ["x", close]]:
		var _b:Button = Button.new()
		_b.text = _entry[0]
		_b.pressed.connect(_entry[1])
		_text_row.add_child(_b)
	_alt = Button.new()
	_alt.visible = false
	_alt.pressed.connect(func ()->void:
		var _call:Callable = _alt_answer
		close()
		if _call.is_valid():
			_call.call())
	_box.add_child(_alt)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override(&"separation", 2)
	_choices.visible = false
	_box.add_child(_choices)
	creator.prompt_requested.connect(ask)
	creator.choice_requested.connect(ask)
	creator.confirm_requested.connect(ask_confirm)

## `alt_label` adds a second button running `alt_answer` (no text).
func ask(title:String, initial:String, answer:Callable, alt_label:String = "", alt_answer:Callable = Callable())->void:
	_set_confirm_mode(false)
	_alt.text = alt_label
	_alt.visible = !alt_label.is_empty()
	_alt_answer = alt_answer
	_title.text = title
	_edit.text = initial
	_answer = answer
	_show(panel_width)
	_edit.grab_focus()
	_edit.select_all()

## Choices: [{label, action:Callable, danger:bool}]; each closes the prompt, then runs.
func ask_confirm(title:String, body:String, choices:Array)->void:
	_set_confirm_mode(true)
	_title.text = title
	_body.text = body
	_body.visible = !body.is_empty()
	for _child:Node in _choices.get_children():
		_choices.remove_child(_child)
		_child.queue_free()
	for _choice:Dictionary in choices:
		_choice_button(String(_choice.label), _choice.get("action", Callable()), bool(_choice.get("danger", false)))
	_choice_button("Cancel", Callable(), false)
	_show(confirm_width)

func _choice_button(label:String, action:Callable, danger:bool)->void:
	var _b:Button = Button.new()
	_b.text = label
	_b.focus_mode = Control.FOCUS_NONE
	_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if danger:
		_b.add_theme_color_override(&"font_color", creator.preset.danger_color)
		_b.add_theme_color_override(&"font_hover_color", creator.preset.danger_color.lightened(0.3))
	_b.pressed.connect(func ()->void:
		close()
		if action.is_valid():
			action.call())
	_choices.add_child(_b)

## Labels of the open confirm's buttons (tests).
func choice_labels()->PackedStringArray:
	var _labels:PackedStringArray = []
	for _child:Node in _choices.get_children():
		if _child is Button && !_child.is_queued_for_deletion():
			_labels.append((_child as Button).text)
	return _labels

## Presses confirm button `index` (tests).
func press_choice(index:int)->void:
	var _buttons:Array = _choices.get_children().filter(func (n:Node)->bool: return !n.is_queued_for_deletion())
	(_buttons[index] as Button).pressed.emit()

func _set_confirm_mode(on:bool)->void:
	_text_row.visible = !on
	_choices.visible = on
	_body.visible = on
	if on:
		_alt.visible = false

func _show(width:float)->void:
	visible = true
	size = Vector2(width, 0)
	custom_minimum_size.x = width
	reset_size()
	_center()
	# wrapped labels settle a frame later
	_center.call_deferred()

func _center()->void:
	reset_size()
	position = ((get_parent() as Control).size - size) * 0.5

func confirm()->void:
	if _choices.visible:
		return
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
