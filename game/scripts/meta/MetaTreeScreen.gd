## Meta-upgrade screen: the upgrade graph from upgrades.json, bought with boss crystals.
##
## Nodes are walked with the ui directions (neighbours picked by where they sit on
## the graph) and bought with ui_accept or a click. The view pans to keep the
## focused node centred; dragging the background pans it by hand.
## The header's tree button (or Tab) switches between the main tree and its
## sister trees; only the shown tree's nodes are built into the focus walk.
## In toggleable trees (UPGRADES, HORDE) pressing an owned node switches it
## off / on, and the header's All button switches the whole tree.
## ui_cancel / pause goes back to the title, or, opened over the home base by the
## meta workbench (open_overlay), closes the overlay and unpauses the room.
class_name MetaTreeScreen
extends Control

## The overlay was closed (open_overlay)
signal closed

const TITLE_SCENE:String = "res://game/scenes/title.tscn"
## Neighbour search: how far off a direction (in degrees) a node may sit.
const NEIGHBOUR_CONE:float = 50.0
const PAN_TIME:float = 0.25
const ZOOM_MIN:float = 0.35
const ZOOM_MAX:float = 2.0
const ZOOM_STEP:float = 1.15
const OWNED_TEXT:Color = Color(0.55, 0.9, 0.6)
const SHORT_TEXT:Color = Color(1.0, 0.42, 0.42)
const COST_TEXT:Color = Color(1.0, 0.72, 0.94)
const LOCKED_TEXT:Color = Color(0.6, 0.58, 0.68)
const KEYSTONE_TEXT:Color = Color8(255, 214, 90)
const OFF_TEXT:Color = Color(0.75, 0.7, 0.55)

@export var meta_upgrade_resource:MetaUpgradeResource
@export var boss_crystal_resource:ScoreResource
@export var action_resource:ActionResource
@export var buy_sound:SoundResource
@export var denied_sound:SoundResource
@export var back_sound:SoundResource

@export_group("Nodes")
## Clips the graph; its centre is where the focused node is brought.
@export var graph_view:Control
## Holds the node buttons, moved to pan.
@export var graph_content:Control
@export var graph_links:MetaGraphLinks
@export var crystal_label:Label
@export var progress_label:Label
@export var name_label:Label
@export var tag_label:Label
@export var text_label:Label
@export var state_label:Label
@export var back_button:Button
@export var reset_button:Button
@export var title_label:Label
## Switches to the next tree; reads that tree's title.
@export var tree_button:Button
## Switches every owned node of a toggleable tree off / on; hidden elsewhere.
@export var toggle_all_button:Button
@export var hint_label:Label

## id -> MetaNodeButton
var buttons:Dictionary
var focused_id:String = MetaUpgrades.ROOT
var tree:String = MetaUpgrades.MAIN_TREE
var _pan_tween:Tween
## graph_content scale (mouse wheel, +/-)
var zoom:float = 1.0
var _dragging:bool
## Focus taken by hovering: show its info without panning under the mouse.
var _mouse_focus:bool
var _reset_armed:bool
var _leaving:bool
## Opened over a room (open_overlay): back closes instead of going to the title
var overlay:bool

const SCENE:String = "res://game/scenes/meta_upgrades.tscn"
const OVERLAY_LAYER:String = "MetaUpgradesLayer"

## Shows the tree over the running game (paused under it); the music stays.
static func open_overlay(owner_node:Node)->MetaTreeScreen:
	var _tree:SceneTree = owner_node.get_tree()
	var _old:Node = _tree.root.get_node_or_null(OVERLAY_LAYER)
	if _old != null:
		return _old.get_child(0) as MetaTreeScreen
	var _screen:MetaTreeScreen = (load(SCENE) as PackedScene).instantiate()
	_screen.overlay = true
	var _music:Node = _screen.get_node_or_null("MusicSetter")
	if _music != null:
		_screen.remove_child(_music)
		_music.free()
	var _layer:CanvasLayer = CanvasLayer.new()
	_layer.name = OVERLAY_LAYER
	_layer.layer = 4
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.add_child(_screen)
	_tree.root.add_child(_layer)
	_tree.paused = true
	return _screen

func _ready()->void:
	assert(meta_upgrade_resource != null)
	assert(boss_crystal_resource != null)
	meta_upgrade_resource.load_resource()
	boss_crystal_resource.load_resource()

	for _id:String in MetaUpgrades.nodes():
		var _button:MetaNodeButton = MetaNodeButton.new()
		_button.setup(_id)
		graph_content.add_child(_button)
		buttons[_id] = _button
		_button.pressed.connect(_buy.bind(_id))
		_button.focus_entered.connect(_on_focus.bind(_id))
		_button.mouse_entered.connect(_on_hover.bind(_button))
	graph_links.meta_upgrade_resource = meta_upgrade_resource
	graph_view.gui_input.connect(_on_graph_input)

	meta_upgrade_resource.updated.connect(_refresh)
	boss_crystal_resource.updated.connect(_refresh)
	back_button.pressed.connect(_back)
	reset_button.pressed.connect(_on_reset)
	tree_button.pressed.connect(next_tree)
	if toggle_all_button != null:
		toggle_all_button.pressed.connect(toggle_all)
	show_tree(tree)
	_start.call_deferred()

func _exit_tree()->void:
	meta_upgrade_resource.updated.disconnect(_refresh)
	boss_crystal_resource.updated.disconnect(_refresh)

## Once the layout has sizes: centre on the root and focus it.
func _start()->void:
	graph_content.position = _pan_target(focused_id)
	buttons[focused_id].grab_focus()

## Shows one tree: only its buttons are visible and walkable, its root focused.
func show_tree(id:String)->void:
	tree = id
	for _id:String in buttons:
		buttons[_id].visible = MetaUpgrades.tree_of(_id) == tree
	_set_neighbours()
	graph_links.tree = tree
	graph_links.fit()
	title_label.text = MetaUpgrades.tree_title(tree)
	var _trees:Array = MetaUpgrades.tree_ids()
	tree_button.visible = _trees.size() > 1
	tree_button.text = tab_text(_trees, tree)
	focused_id = MetaUpgrades.tree_root(tree)
	_refresh()
	if is_node_ready():
		buttons[focused_id].grab_focus()

## All off when any owned node of the shown tree is on, else all on.
func toggle_all()->void:
	if !MetaUpgrades.is_toggleable(tree):
		return
	var _on:bool = !meta_upgrade_resource.any_enabled_in(tree)
	meta_upgrade_resource.set_tree_enabled(tree, _on)
	if buy_sound != null:
		buy_sound.play_managed()

## Every tree, the shown one in brackets: "[UPGRADES] HORDE CO-OP (Tab)"
static func tab_text(trees:Array, current:String)->String:
	var _parts:PackedStringArray = []
	for _id:String in trees:
		var _title:String = MetaUpgrades.tree_title(_id)
		_parts.append("[%s]" % _title if _id == current else _title)
	return "%s (Tab)" % " ".join(_parts)

func next_tree()->void:
	var _trees:Array = MetaUpgrades.tree_ids()
	show_tree(_trees[(_trees.find(tree) + 1) % _trees.size()])

func _input(event:InputEvent)->void:
	# before the room's pause menu (PausingManager) takes the key
	if overlay && (event.is_action("ui_cancel") || (action_resource != null && event.is_action(action_resource.pause_action))):
		get_viewport().set_input_as_handled()
		if event.is_released():
			_back()
		return
	if event is InputEventKey && event.pressed:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				set_zoom(zoom * ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_zoom(zoom / ZOOM_STEP)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_focus_next") && tree_button.visible:
		get_viewport().set_input_as_handled()
		next_tree()

func _unhandled_input(event:InputEvent)->void:
	if event.is_action_released("ui_cancel") || (action_resource != null && event.is_action_released(action_resource.pause_action)):
		get_viewport().set_input_as_handled()
		_back()

func _back()->void:
	if _leaving:
		return
	_leaving = true
	if back_sound != null:
		back_sound.play_managed()
	if overlay:
		get_tree().paused = false
		var _layer:Node = get_parent()
		(_layer if _layer is CanvasLayer else self).queue_free()
		closed.emit()
		return
	Transition.change_scene(TITLE_SCENE)

func _buy(id:String)->void:
	var _button:MetaNodeButton = buttons[id]
	if meta_upgrade_resource.toggle(id):
		_button.play_bought()
		if buy_sound != null:
			buy_sound.play_managed()
		return
	if meta_upgrade_resource.buy(id):
		_button.play_bought()
		if buy_sound != null:
			buy_sound.play_managed()
		return
	if meta_upgrade_resource.state(id) != MetaUpgradeResource.State.OWNED:
		_button.play_denied()
		if denied_sound != null:
			denied_sound.play_managed()

## First press asks, the second within 2s refunds every crystal spent.
func _on_reset()->void:
	if !_reset_armed:
		_reset_armed = true
		reset_button.text = "Sure?"
		get_tree().create_timer(2.0).timeout.connect(_disarm_reset)
		return
	_disarm_reset()
	meta_upgrade_resource.refund_all()
	for _id:String in buttons:
		buttons[_id].play_bought()

func _disarm_reset()->void:
	_reset_armed = false
	reset_button.text = "Reset"

func _refresh()->void:
	crystal_label.text = str(boss_crystal_resource.value)
	var _owned:int = 0
	var _shown:int = 0
	for _id:String in buttons:
		var _state:MetaUpgradeResource.State = meta_upgrade_resource.state(_id)
		if MetaUpgrades.tree_of(_id) == tree:
			_shown += 1
			if _state == MetaUpgradeResource.State.OWNED:
				_owned += 1
		buttons[_id].refresh(_state, LootItems.can_afford(MetaUpgrades.cost(_id)), meta_upgrade_resource.disabled.has(_id))
	progress_label.text = "%d/%d" % [_owned, _shown]
	reset_button.disabled = meta_upgrade_resource.owned.is_empty()
	var _toggleable:bool = MetaUpgrades.is_toggleable(tree)
	if toggle_all_button != null:
		toggle_all_button.visible = _toggleable
		toggle_all_button.disabled = meta_upgrade_resource.toggleable_in(tree).is_empty()
		toggle_all_button.text = "All off" if meta_upgrade_resource.any_enabled_in(tree) || toggle_all_button.disabled else "All on"
	if hint_label != null:
		hint_label.text = "Arrows: move   Enter: buy / on-off   Wheel / +-: zoom   Esc: back" if _toggleable else "Arrows: move   Enter: buy   Wheel / +-: zoom   Esc: back"
	graph_links.queue_redraw()
	_show_info(focused_id)

func _show_info(id:String)->void:
	var _node:Dictionary = MetaUpgrades.node(id)
	name_label.text = _node.get("title", id)
	var _keystone:bool = MetaUpgrades.is_keystone(id)
	name_label.modulate = KEYSTONE_TEXT if _keystone else Color.WHITE
	tag_label.visible = _keystone && !MetaUpgrades.is_root(id)
	text_label.text = MetaUpgrades.describe(id)
	match meta_upgrade_resource.state(id):
		MetaUpgradeResource.State.OWNED:
			if meta_upgrade_resource.disabled.has(id):
				state_label.text = "Owned - OFF"
				state_label.modulate = OFF_TEXT
			else:
				state_label.text = "Owned - ON" if meta_upgrade_resource.can_toggle(id) else "Owned"
				state_label.modulate = OWNED_TEXT
		MetaUpgradeResource.State.AVAILABLE:
			var _cost:Array = MetaUpgrades.cost(id)
			var _affordable:bool = LootItems.can_afford(_cost)
			state_label.text = "Cost: %s%s" % [LootItems.describe(_cost), "" if _affordable else "  (not enough)"]
			state_label.modulate = COST_TEXT if _affordable else SHORT_TEXT
		MetaUpgradeResource.State.LOCKED:
			var _titles:PackedStringArray = []
			for _required:String in MetaUpgrades.requires(id):
				_titles.append(MetaUpgrades.node(_required).get("title", _required))
			state_label.text = "Requires %s" % " or ".join(_titles)
			state_label.modulate = LOCKED_TEXT

func _on_focus(id:String)->void:
	focused_id = id
	_show_info(id)
	if !_mouse_focus:
		_pan_to(id)

func _on_hover(button:MetaNodeButton)->void:
	if _dragging || button.has_focus():
		return
	_mouse_focus = true
	button.grab_focus()
	_mouse_focus = false

func _pan_target(id:String)->Vector2:
	return (graph_view.size * 0.5 - MetaUpgrades.position(id) * zoom).round()

## Zooms keeping the graph point under `pivot` (graph_view coordinates) in place.
func set_zoom(value:float, pivot:Vector2 = Vector2.INF)->void:
	if pivot == Vector2.INF:
		pivot = graph_view.size * 0.5
	var _new:float = clampf(value, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_new, zoom):
		return
	if _pan_tween != null:
		_pan_tween.kill()
	graph_content.position = (pivot - (pivot - graph_content.position) * (_new / zoom)).round()
	zoom = _new
	graph_content.scale = Vector2.ONE * zoom

func _pan_to(id:String)->void:
	if _pan_tween != null:
		_pan_tween.kill()
	_pan_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_property(graph_content, "position", _pan_target(id), PAN_TIME)

func _on_graph_input(event:InputEvent)->void:
	if event is InputEventMouseButton && event.pressed && (event.button_index == MOUSE_BUTTON_WHEEL_UP || event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var _step:float = ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
		set_zoom(zoom * _step, event.position)
		accept_event()
		return
	if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging && _pan_tween != null:
			_pan_tween.kill()
	elif event is InputEventMouseMotion && _dragging:
		graph_content.position = (graph_content.position + event.relative).round()

## For every node and direction: the nearest node of the same tree inside a cone
## around that direction. Without one, focus stays put instead of jumping to the buttons.
func _set_neighbours()->void:
	var _directions:Dictionary = {
		SIDE_LEFT: Vector2.LEFT, SIDE_RIGHT: Vector2.RIGHT, SIDE_TOP: Vector2.UP, SIDE_BOTTOM: Vector2.DOWN,
	}
	for _id:String in buttons:
		var _button:MetaNodeButton = buttons[_id]
		var _from:Vector2 = MetaUpgrades.position(_id)
		for _side:Side in _directions:
			var _best:MetaNodeButton = _button
			var _best_score:float = INF
			for _other_id:String in buttons:
				if _other_id == _id || MetaUpgrades.tree_of(_other_id) != MetaUpgrades.tree_of(_id):
					continue
				var _offset:Vector2 = MetaUpgrades.position(_other_id) - _from
				var _angle:float = rad_to_deg(absf(_offset.angle_to(_directions[_side])))
				if _angle > NEIGHBOUR_CONE:
					continue
				# Straight ahead wins over a closer node off to the side.
				var _score:float = _offset.length() * (1.0 + _angle / 45.0)
				if _score < _best_score:
					_best_score = _score
					_best = buttons[_other_id]
			_button.set_focus_neighbor(_side, _button.get_path_to(_best))
		_button.focus_next = _button.get_path_to(_button)
		_button.focus_previous = _button.get_path_to(_button)

## Focus walk for tests: the node reached from `id` going toward `side`.
func neighbour(id:String, side:Side)->String:
	var _button:MetaNodeButton = buttons[id]
	var _target:Node = _button.get_node(_button.get_focus_neighbor(side))
	return _target.id if _target is MetaNodeButton else id
