## Campaign graph: CampaignStore finds the built-in campaigns (rooms by layout campaign,
## start room), the graph shows a campaign's rooms with their links as connections,
## linking / unlinking ports rewrites the doors (both ways), new campaigns and starts save
## to a mod, and Title > Custom lists that mod campaign and resolves its start room.
##   Godot --headless --path . res://game/tests/campaign_graph_check.tscn
extends Node

const BAKER:String = "res://game/resources/map_creator/layout_baker.tres"
const CREATOR:String = "res://addons/map_creator/scenes/map_creator.tscn"
const OUT:String = "user://campaign_graph_check/"

var failures:int = 0
var checks:int = 0

func check(condition:bool, label:String)->void:
	checks += 1
	if !condition:
		failures += 1
		printerr("FAIL: ", label)

func _frames(count:int)->void:
	for _i:int in count:
		await get_tree().process_frame

func _ready()->void:
	(load("res://addons/top_down/resources/global_resources/action_resource.tres") as ActionResource).reset_resource()
	_wipe(OUT)
	var _baker:GameLayoutBaker = _test_baker()
	_baker.quiet = true
	var _creator:MapCreator = _open("N01", _baker)
	await _frames(2)
	_check_store(_creator, _baker)
	var _graph:CampaignGraph = _creator.get_node("UI/Root/CampaignGraph")
	await _check_graph(_creator, _graph)
	_check_custom(_creator, _graph)
	_creator.mod_state.deactivate(_baker)
	_creator.room.queue_free()
	await _frames(2)
	print("campaign_graph_check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_baker()->GameLayoutBaker:
	var _source:GameLayoutBaker = load(BAKER)
	var _baker:GameLayoutBaker = _source.duplicate()
	_baker.catalog = _source.catalog
	_baker.layouts_dir = OUT + "layouts/"
	_baker.write_dir = OUT + "scenes/"
	_baker.balance_path = OUT + "balance.json"
	_baker.maps_path = OUT + "maps.json"
	for _dir:String in [_baker.layouts_dir, _baker.write_dir]:
		DirAccess.make_dir_recursive_absolute(_dir)
	for _file:String in DirAccess.get_files_at("res://game/rooms/layouts/"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/rooms/layouts/" + _file), ProjectSettings.globalize_path(_baker.layouts_dir + _file))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/balance.json"), ProjectSettings.globalize_path(_baker.balance_path))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://game/balance/maps.json"), ProjectSettings.globalize_path(_baker.maps_path))
	_baker.load_layouts()
	return _baker

func _open(key:String, baker:LayoutBaker)->MapCreator:
	var _room:Node2D = (load("res://game/scenes/room_%s.tscn" % key) as PackedScene).instantiate()
	var _creator:MapCreator = (load(CREATOR) as PackedScene).instantiate()
	_creator.baker = baker
	_creator.settings = MapCreatorSettings.new()
	_creator.settings.not_saved = true
	_creator.settings.auto_clean = false
	_creator.room = _room
	add_child(_room)
	_room.add_child(_creator)
	return _creator

func _check_store(creator:MapCreator, baker:GameLayoutBaker)->void:
	var _store:CampaignStore = CampaignStore.new(baker, creator.mod_state)
	var _campaign:String = String(baker.layouts.N01.campaign)
	check(!_store.find(_campaign).is_empty(), "N01's campaign '%s' is listed" % _campaign)
	check(_store.rooms_of(_campaign).has("N01"), "rooms_of has N01")
	var _start:String = _store.find(_campaign).get("start", "")
	check(!_start.is_empty() && baker.layouts[_start].start, "campaign start is a start room (%s)" % _start)
	var _with_room:int = 0
	for _key:String in baker.layouts:
		for _entity:LayoutEntity in baker.layouts[_key].entities:
			if _entity.props.has("room"):
				_with_room += 1
	check(_store.links().size() == _with_room, "every door/portal is a link")
	_store.auto_layout(_campaign)
	check(_store.find(_campaign).nodes.size() == _store.rooms_of(_campaign).size(), "auto layout places every room")
	check(_store.find(_campaign).nodes[_start] == [0.0, 0.0], "the start room is first")

func _check_graph(creator:MapCreator, graph:CampaignGraph)->void:
	graph.open()
	await _frames(1)
	var _campaign:String = String(creator.layout.campaign)
	check(graph.visible && graph.campaign_id == _campaign, "the graph opens on the room's campaign")
	var _rooms:PackedStringArray = graph.store.rooms_of(_campaign)
	var _nodes:int = 0
	for _child:Node in graph._graph.get_children():
		if _child is GraphNode:
			_nodes += 1
	check(_nodes >= _rooms.size(), "a node per room (%d for %d)" % [_nodes, _rooms.size()])
	var _connections:Array = graph._graph.get_connection_list()
	check(_connections.size() > 0, "links show as connections (%d)" % _connections.size())
	var _ok:bool = true
	for _c:Dictionary in _connections:
		var _from:RoomLayoutResource = graph.layout_of(graph._keys[_c.from_node])
		var _to:String = graph._keys[_c.to_node]
		var _entity:LayoutEntity = _from.entities[CampaignGraph._linkable_exits(_from)[_c.from_port]]
		_ok = _ok && String(_entity.props.room).trim_prefix("room_") == _to
	check(_ok, "every connection is a real link")

	# two new rooms with a door each, linked through the graph
	var _rooms_manager:RoomManager = creator.rooms
	for _key:String in ["G1", "G2"]:
		check(_rooms_manager.new_room(_key, "", creator.layout), "new room %s" % _key)
		var _layout:RoomLayoutResource = creator.baker.layouts[_key].clone()
		_layout.entities.append(LayoutEntity.make(&"door", Vector2i(2, 2)))
		_rooms_manager.store(_layout)
	graph.rebuild()
	check(graph._nodes.has("G1") && graph._nodes.has("G2"), "new rooms join the campaign graph")
	graph.link("G1", 0, "G2", 0)
	var _g1:LayoutEntity = creator.baker.layouts.G1.entities_of(&"door")[0]
	var _g2:LayoutEntity = creator.baker.layouts.G2.entities_of(&"door")[0]
	check(_g1.props.room == "room_G2" && _g1.props.connect_tag == _g2.props.tag && !String(_g2.props.tag).is_empty(), "link sets the door's target and arrival tag")
	check(_g2.props.room == "room_G1" && _g2.props.connect_tag == _g1.props.tag, "doors link both ways")
	var _linked:bool = false
	for _c:Dictionary in graph._graph.get_connection_list():
		_linked = _linked || (graph._keys[_c.from_node] == "G1" && graph._keys[_c.to_node] == "G2")
	check(_linked, "the new link shows")
	graph.unlink("G1", 0)
	check(String(creator.baker.layouts.G1.entities_of(&"door")[0].props.room).is_empty(), "unlink clears the door")
	# the open room changes through an undoable edit
	var _ports:Array[int] = CampaignGraph._linkable_exits(creator.layout)
	if !_ports.is_empty():
		graph.link("N01", 0, "G2", 0)
		check(creator.layout.entities[_ports[0]].props.room == "room_G2" && creator.dirty, "linking the open room edits it (unsaved)")
		creator.undo()
		check(creator.layout.entities[_ports[0]].props.room != "room_G2", "and undo takes it back")
	graph.close()

func _check_custom(creator:MapCreator, graph:CampaignGraph)->void:
	var _mods:MapModState = creator.mod_state
	_mods.mods_dir = OUT + "mods/"
	_mods.cache_dir = OUT + "cache/"
	check(creator.create_mod("Camp", false), "test mod")
	check(creator.rooms.new_room("CS1", "Custom start"), "mod room")
	var _store:CampaignStore = CampaignStore.new(creator.baker, _mods)
	var _campaign:Dictionary = _store.add("My run", "My run")
	check(!_campaign.is_empty(), "new campaign")
	_campaign.start = "CS1"
	check(_store.save() == OK, "campaign saved into the mod")
	var _reread:MapModInfo = _mods.active_mod()
	var _saved:Array = _reread.campaigns.filter(func (c:Dictionary)->bool: return c.id == "my_run")
	check(_saved.size() == 1 && _saved[0].start == "CS1", "mod.json has the campaign")
	var _custom:CustomCampaigns = CustomCampaigns.new()
	_custom.mod_state = _mods
	var _playable:Array = _custom.playable()
	var _found:bool = false
	for _entry:Array in _playable:
		_found = _found || (_entry[0].id == "camp" && _entry[1].start == "CS1")
	check(_found, "Title > Custom lists the mod campaign")
	_custom.free()
	_mods.deactivate(creator.baker)
	check(_mods.activate("camp", creator.baker) && _mods.resolve(_mods.canonical_scene("CS1")) == _mods.cache_scene("camp", "CS1"), "starting it resolves to the mod's room")
	check(CampaignStore.clean({"id": "a\"b", "start": "x/../y", "nodes": {"k": "bad"}}).nodes.is_empty(), "campaign JSON cleaned")

func _wipe(dir:String)->void:
	if !DirAccess.dir_exists_absolute(dir):
		return
	for _sub:String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(_sub))
	for _file:String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(_file))
	DirAccess.remove_absolute(dir)
