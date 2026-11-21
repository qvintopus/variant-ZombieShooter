## Title > Custom: the campaigns of the map creator mods in user://mods. Picking one makes
## that mod active (its rooms baked and resolved) and loads the campaign's start room.
## The title always returns to the base game first. Offline only: guests wouldn't have
## the mod's rooms. The Custom button hides when no mod has a playable campaign.
class_name CustomCampaigns
extends Node

@export var button:Button
## The title menu row holding `button` (hidden with it).
@export var row:Control
## Filled with one button per campaign, plus Back.
@export var menu:VBoxContainer
@export var menu_traverse_manager:MenuTraverseManager
@export var menu_button_scene:PackedScene
@export var mod_state:MapModState
@export var baker:LayoutBaker

## [mod id, campaign dict] per menu button.
var entries:Array = []

func _ready()->void:
	mod_state.deactivate(baker)
	entries = playable()
	row.visible = !entries.is_empty() && !Net.is_online()
	button.pressed.connect(func ()->void:
		menu_traverse_manager.open("custom")
		(menu.get_child(0).get_node("Button") as Button).grab_focus.call_deferred())
	for _entry:Array in entries:
		var _info:MapModInfo = _entry[0]
		_add_button("%s: %s" % [_info.name, _entry[1].display_name], start.bind(_info.id, _entry[1].start))
	_add_button("Back", menu_traverse_manager.back)

## [MapModInfo, campaign] for every mod campaign whose start room exists.
func playable()->Array:
	var _out:Array = []
	var _mods:Dictionary = mod_state.scan()
	var _ids:Array = _mods.keys()
	_ids.sort()
	for _id:String in _ids:
		var _info:MapModInfo = _mods[_id]
		for _raw:Variant in _info.campaigns:
			var _campaign:Dictionary = CampaignStore.clean(_raw)
			var _start:String = _campaign.get("start", "")
			if !_start.is_empty() && (_info.has_room(_start) || ResourceLoader.exists(mod_state.canonical_scene(_start))):
				_out.append([_info, _campaign])
	return _out

func _add_button(text:String, action:Callable)->void:
	var _row:Control = menu_button_scene.instantiate()
	menu.add_child(_row)
	(_row.get_node("Label") as Label).text = text
	(_row.get_node("Button") as Button).pressed.connect(action)

func start(mod_id:String, key:String)->void:
	if !mod_state.activate(mod_id, baker):
		push_warning("CustomCampaigns: mod '%s' is gone" % mod_id)
		return
	Transition.change_scene(mod_state.canonical_scene(key))
