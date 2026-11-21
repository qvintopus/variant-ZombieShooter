## Saves a screenshot of a room with the map creator in Edit mode (UI checks).
##   Godot --path . res://game/tests/map_creator_snapshot.tscn -- <room key> <out.png> [category index] [hover x,y] [radial [hover path, e.g. -1,3]]
## "radial" opens the radial menu on the hovered cell and hovers its first slice and that
## slice's third operation; "rooms" opens the room browser; "waves", "graph", "problems",
## "help" open those panels.
extends Node

func _ready()->void:
	var _args:PackedStringArray = OS.get_cmdline_user_args()
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	var _settings:MapCreatorSettings = load("res://addons/map_creator/resources/settings/map_creator_settings.tres")
	_settings.not_saved = true
	_settings.admin_enabled = true
	var _room:Node = (load("res://game/scenes/room_%s.tscn" % _args[0]) as PackedScene).instantiate()
	add_child(_room)
	for _i:int in 10:
		await get_tree().process_frame
	var _creator:MapCreator = null
	for _child:Node in _room.get_children():
		if _child is MapCreator:
			_creator = _child
	_creator.set_editing(true)
	if _args.size() > 2:
		_creator.select_category(_creator.catalog.categories[int(_args[2])])
	if _args.size() > 3:
		var _xy:PackedStringArray = _args[3].split(",")
		_creator.hover_cell = Vector2i(int(_xy[0]), int(_xy[1]))
		_creator.hover_valid = true
	if _args.size() > 4 && _args[4] in ["waves", "graph", "problems", "help"]:
		_creator.emit_signal(StringName(_args[4] + "_requested"))
		if _args[4] == "problems":
			_creator.run_checks()
	if _args.size() > 4 && _args[4] == "rooms":
		_creator.browse_requested.emit()
	if _args.size() > 4 && _args[4] == "radial":
		var _menu:RadialMenu = _creator.get_node("UI/Root/RadialMenu")
		var _screen:Vector2 = _creator.get_viewport().get_canvas_transform() * _creator.cell_center(_creator.hover_cell)
		_menu.open(_screen, _creator.radial_slices(_creator.hover_cell))
		if _args.size() > 5:
			# hover path per ring: "-1,3" = last slice of ring 1 (More...), then its 4th
			var _ring:int = 0
			for _index:String in _args[5].split(","):
				var _count:int = _menu.ring_slices(_ring).size()
				_menu.hover_slice(_ring, posmod(int(_index), _count))
				_ring += 1
		else:
			_menu.hover_slice(0, 0)
			if _menu.ring_slices(1).size() > 2:
				_menu.hover_slice(1, 2)
	for _i:int in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_args[1])
	get_tree().quit()
