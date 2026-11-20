## Compiles the game-feel shaders with a real renderer (needs a display, not --headless).
## Shader errors print as "SHADER ERROR".
##   Godot --path . res://game/tests/shader_compile_check.tscn
extends Node2D

const SHADERS:Array[String] = [
	"res://addons/top_down/scripts/shaders/color_flash.gdshader",
	"res://addons/top_down/scripts/shaders/blessing.gdshader",
	"res://addons/top_down/scripts/shaders/inner_light.gdshader",
]
const SCENES:Array[String] = [
	"res://addons/top_down/scenes/vfx/dead/boss_death_burst.tscn",
	"res://addons/top_down/scenes/screen_effects/blessing_overlay.tscn",
	"res://addons/top_down/scenes/vfx/wave_clear_burst.tscn",
	"res://addons/top_down/scenes/abilities/bomb.tscn",
]

func _ready()->void:
	get_window().size = Vector2i(320, 180)
	var _x:float = 0.0
	for _path:String in SHADERS:
		var _rect:ColorRect = ColorRect.new()
		_rect.size = Vector2(40, 40)
		_rect.position = Vector2(_x, 0)
		var _m:ShaderMaterial = ShaderMaterial.new()
		_m.shader = load(_path)
		_m.set_shader_parameter(&"progress", 0.5)
		_rect.material = _m
		add_child(_rect)
		_x += 44.0
	for _path:String in SCENES:
		var _node:Node = (load(_path) as PackedScene).instantiate()
		if _node is Node2D:
			(_node as Node2D).position = Vector2(_x, 90)
		add_child(_node)
		_x += 44.0
	for i:int in 10:
		await get_tree().process_frame
	print("shader_compile_check: done")
	get_tree().quit(0)
