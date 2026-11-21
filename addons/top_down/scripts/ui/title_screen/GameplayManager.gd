## Options > Gameplay: damage number toggles, size and colors (modeled on GraphicsManager).
extends Node

@export var settings:DamageNumbersSettings
## Optional: map creator settings (admin_enabled, set_admin_enabled), see addons/map_creator.
@export var admin_settings:SaveableResource

@export_group("Rows")
@export var enemy_button:Button
@export var enemy_label:Label
@export var player_button:Button
@export var player_label:Label
@export var size_button:Button
@export var size_label:Label
@export var colors_button:Button
@export var colors_label:Label
@export var admin_button:Button
@export var admin_label:Label
## Pressing it saves
@export var back_button:Button

@export_group("Preview")
@export var preview_enemy:Label
@export var preview_critical:Label
@export var preview_player:Label
@export var preview_heal:Label

@export_group("Texts")
@export var enemy_text:String = "Enemy numbers: %s"
@export var player_text:String = "Player numbers: %s"
@export var size_text:String = "Number size: %s"
@export var colors_text:String = "Number colors: %s"
@export var admin_text:String = "Admin tools: %s"
@export var on_text:String = "ON"
@export var off_text:String = "OFF"

func _ready()->void:
	assert(settings != null)
	enemy_button.pressed.connect(func ()->void: settings.set_show_enemy(!settings.show_enemy))
	player_button.pressed.connect(func ()->void: settings.set_show_player(!settings.show_player))
	size_button.pressed.connect(settings.cycle_size)
	colors_button.pressed.connect(settings.cycle_preset)
	back_button.pressed.connect(settings.save_resource)
	settings.changed_settings.connect(_refresh)
	if admin_settings != null && admin_button != null:
		admin_button.pressed.connect(func ()->void: admin_settings.call(&"set_admin_enabled", !admin_settings.get(&"admin_enabled")))
		back_button.pressed.connect(admin_settings.save_resource)
		admin_settings.connect(&"changed_settings", _refresh)
	elif admin_button != null:
		admin_button.get_parent().visible = false
	_refresh()

func _on_off(value:bool)->String:
	return on_text if value else off_text

func _refresh()->void:
	enemy_label.text = enemy_text % _on_off(settings.show_enemy)
	player_label.text = player_text % _on_off(settings.show_player)
	size_label.text = size_text % settings.size_name()
	var _colors:DamageNumberColors = settings.colors()
	colors_label.text = colors_text % _colors.preset_name
	if admin_settings != null && admin_label != null:
		admin_label.text = admin_text % _on_off(admin_settings.get(&"admin_enabled"))
	_preview(preview_enemy, _colors.enemy, settings.show_enemy)
	_preview(preview_critical, _colors.critical, settings.show_enemy)
	_preview(preview_player, _colors.player, settings.show_player)
	_preview(preview_heal, _colors.heal, true)

func _preview(label:Label, color:Color, shown:bool)->void:
	if label == null:
		return
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", settings.font_size() * 2)
	label.modulate.a = 1.0 if shown else 0.3
