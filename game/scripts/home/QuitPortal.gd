## Home base portal out of the game: walking in asks "Quit game?", yes saves the
## home base and the run checkpoint and closes the game (QuitPrompt still asks
## first while a server or the virtual LAN runs on this PC).
## Built in code from the portal's sprite strip, like RejoinPortal.
class_name QuitPortal
extends Area2D

const TEXTURE:Texture2D = preload("res://addons/top_down/assets/images/misc/portal_32x32_strip6.png")
const COLOR:Color = Color(1.0, 0.55, 0.5)
const FRAME_TIME:float = 0.1

## Saved before quitting; found in the room when not set
@export var home_base:HomeBase
@export var label_text:String = "EXIT GAME"

var sprite:Sprite2D
var label:Label
var _frame_left:float
## Only after the player has stood outside it once (and after a "Stay")
var _armed:bool
var _prompt:ConfirmPrompt

func _init()->void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var _shape:CollisionPolygon2D = CollisionPolygon2D.new()
	_shape.polygon = PackedVector2Array([Vector2(0, -8), Vector2(-16, 0), Vector2(0, 8), Vector2(16, 0)])
	add_child(_shape)
	sprite = Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.hframes = 6
	sprite.centered = false
	sprite.position = Vector2(-16, -24)
	sprite.modulate = COLOR
	add_child(sprite)
	label = Label.new()
	label.z_index = 10
	label.offset_left = -60
	label.offset_right = 60
	label.offset_top = -34
	label.offset_bottom = -25
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)

func _ready()->void:
	label.text = label_text
	if home_base == null:
		home_base = _find_home_base()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_arm_if_clear.call_deferred()

func _find_home_base()->HomeBase:
	var _node:Node = get_parent()
	while _node != null:
		var _base:HomeBase = _node.get_node_or_null("HomeBase") as HomeBase
		if _base != null:
			return _base
		_node = _node.get_parent()
	return null

func _arm_if_clear()->void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var _local:Node2D = Net.players.local_body()
	_armed = _local == null || !get_overlapping_bodies().has(_local)

func _on_body_exited(body:Node2D)->void:
	if body == Net.players.local_body():
		_armed = true

func _on_body_entered(body:Node2D)->void:
	if body != Net.players.local_body() || !_armed || is_instance_valid(_prompt):
		return
	ask()

## "Quit game?" over the room
func ask()->ConfirmPrompt:
	_armed = false
	_prompt = ConfirmPrompt.open(self, "Quit game?", "Quit", "Stay")
	_prompt.confirmed.connect(quit_game)
	return _prompt

## Everything saved, then the game closes
func quit_game()->void:
	if home_base != null:
		home_base.save_state()
	QuitPrompt.request(func ()->void:
		RunSession.checkpoint()
		get_tree().quit())

func _process(delta:float)->void:
	_frame_left -= delta
	if _frame_left > 0.0:
		return
	_frame_left = FRAME_TIME
	sprite.frame = 1 + sprite.frame % (sprite.hframes - 1)
