## Player settings for floating damage numbers (Options > Gameplay). Saved.
class_name DamageNumbersSettings
extends SaveableResource

signal changed_settings

@export_group("Choices")
@export var show_enemy:bool = true
@export var show_player:bool = true
## Index into size_options
@export var size_index:int = 1
## Index into color_presets
@export var preset_index:int = 0

@export_group("Options")
## Font sizes the size setting cycles through
@export var size_options:PackedInt32Array = [6, 8, 10]
@export var size_names:PackedStringArray = ["Small", "Medium", "Large"]
@export var color_presets:Array[DamageNumberColors]

func font_size()->int:
	if size_options.is_empty():
		return 8
	return size_options[clampi(size_index, 0, size_options.size() - 1)]

func size_name()->String:
	if size_names.is_empty():
		return str(font_size())
	return size_names[clampi(size_index, 0, size_names.size() - 1)]

func colors()->DamageNumberColors:
	if color_presets.is_empty():
		return DamageNumberColors.new()
	return color_presets[clampi(preset_index, 0, color_presets.size() - 1)]

func set_show_enemy(value:bool)->void:
	show_enemy = value
	changed_settings.emit()

func set_show_player(value:bool)->void:
	show_player = value
	changed_settings.emit()

func cycle_size()->void:
	size_index = (size_index + 1) % maxi(size_options.size(), 1)
	changed_settings.emit()

func cycle_preset()->void:
	preset_index = (preset_index + 1) % maxi(color_presets.size(), 1)
	changed_settings.emit()

func prepare_save()->Resource:
	return self.duplicate()

func prepare_load(data:Resource)->void:
	if data == null:
		return
	show_enemy = data.get(&"show_enemy")
	show_player = data.get(&"show_player")
	size_index = data.get(&"size_index")
	preset_index = data.get(&"preset_index")
	changed_settings.emit()

func reset_resource()->void:
	show_enemy = true
	show_player = true
	size_index = 1
	preset_index = 0
	changed_settings.emit()
