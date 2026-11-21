## "Cleaning room" bar while MapCreator.clean() runs with progress (button / C).
class_name CleanProgress
extends PanelContainer

@export var creator:MapCreator
@export var label_text:String = "Cleaning room..."

var _bar:ProgressBar

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _box:VBoxContainer = VBoxContainer.new()
	add_child(_box)
	var _label:Label = Label.new()
	_label.text = label_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(120, 6)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_box.add_child(_bar)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	creator.clean_progress.connect(_on_progress)

func _on_progress(fraction:float)->void:
	visible = fraction >= 0.0
	_bar.value = maxf(fraction, 0.0)
