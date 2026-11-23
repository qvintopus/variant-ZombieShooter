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
	_check_search(creator, graph)
	await _check_preview(creator, graph)

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
	# rewire G1 to G3: G2 (which arrived at G1) gets unlinked
	check(_rooms_manager.new_room("G3", "", creator.layout), "new room G3")
	var _g3_layout:RoomLayoutResource = creator.baker.layouts.G3.clone()
	_g3_layout.entities.append(LayoutEntity.make(&"door", Vector2i(2, 2)))
	_rooms_manager.store(_g3_layout)
	graph.rebuild()
	graph.link("G1", 0, "G3", 0)
	var _door:Callable = func (key:String)->LayoutEntity: return creator.baker.layouts[key].entities_of(&"door")[0]
	check(_door.call("G1").props.room == "room_G3" && _door.call("G3").props.room == "room_G1", "rewiring links the new pair both ways")
	check(String(_door.call("G2").props.room).is_empty(), "and unlinks the old partner")
	# the side panel's dropdown rewires too
	graph.select_room("G1")
	var _picks:Array = graph._info.find_children("*", "OptionButton", true, false)
	var _to_g2:int = -1
	if !_picks.is_empty():
		for _i:int in _picks[0].item_count:
			if _picks[0].get_item_text(_i).begins_with("room_G2"):
				_to_g2 = _i
	check(_to_g2 >= 0, "the dropdown lists G2's stairs")
	if _to_g2 >= 0:
		_picks[0].select(_to_g2)
		_picks[0].item_selected.emit(_to_g2)
		check(_door.call("G1").props.room == "room_G2" && _door.call("G2").props.room == "room_G1" && String(_door.call("G3").props.room).is_empty(), "picking G2 relinks G1 <-> G2, G3 unlinked")
	graph.unlink("G1", 0)
	check(String(creator.baker.layouts.G1.entities_of(&"door")[0].props.room).is_empty(), "unlink clears the door")
	check(String(_door.call("G2").props.room).is_empty(), "and the stairs leading back")
	# the open room changes through an undoable edit
	var _ports:Array[int] = CampaignGraph._linkable_exits(creator.layout)
	if !_ports.is_empty():
		graph.link("N01", 0, "G2", 0)
		check(creator.layout.entities[_ports[0]].props.room == "room_G2" && creator.dirty, "linking the open room edits it (unsaved)")
		creator.undo()
		check(creator.layout.entities[_ports[0]].props.room != "room_G2", "and undo takes it back")
	graph.close()

## Search fades non-matching nodes; the side panel shows the room browser's details.
func _check_search(creator:MapCreator, graph:CampaignGraph)->void:
	graph.select_room("N01")
	check(graph._info.text.contains("room_N01") && graph._info.text.contains("Size:"), "details panel shows the room's details")
	check(graph._nodes.N01.tooltip_text.contains("Size:"), "node tooltip has the details")
	var _open:Array = graph._info.find_children("*", "Button", true, false).filter(func (b:Button)->bool: return b.icon == creator.open_room_icon())
	var _expected:int = graph.index.entries.N01.links.size() + creator.rooms.link_entries("N01").size()
	check(_expected > 0 && _open.size() == _expected, "details rows open each linked room (%d of %d)" % [_open.size(), _expected])
	# a row of the open room: selects the linking stairs here, closes the graph
	var _into:Array = creator.rooms.link_entries(creator.key).filter(func (l:Dictionary)->bool: return graph._nodes.has(l.room))
	check(!_into.is_empty(), "a shown room links to the open room")
	if !_into.is_empty():
		graph.select_room(_into[0].room)
	var _here:Array = graph._info.find_children("*", "Button", true, false).filter(func (b:Button)->bool: return b.tooltip_text.contains("room_%s " % creator.key))
	if !_here.is_empty():
		graph.visible = true
		_here[0].pressed.emit()
		check(!creator.selection.is_empty() && !graph.visible, "opening the current room selects the linked stairs and closes")
		creator.selection.clear()
		creator.inspect(null)
		graph.visible = true
	graph.select_room("N01")
	var _look:String = creator.layout.look
	graph._search.text = "N01"
	graph.apply_search()
	check(graph.matches.has("N01") && graph._nodes.N01.modulate.a == 1.0, "search matches N01")
	var _faded:int = 0
	for _key:String in graph._nodes:
		if graph._nodes[_key].modulate.a < 1.0:
			_faded += 1
	check(_faded > 0 && _faded == graph._nodes.size() - graph.matches.size(), "non-matches fade (%d)" % _faded)
	graph._search.text = ""
	graph.apply_search()
	check(graph.matches.size() == graph._nodes.size(), "empty search shows all")
	check(!_look.is_empty(), "room has a look")

## Preview: every room placed, none overlap, a door-linked room lies on its stairs' side,
## several stairs to one room count as their mean.
func _check_preview(creator:MapCreator, graph:CampaignGraph)->void:
	graph.set_preview(true)
	await _frames(2)
	var _preview:CampaignPreview = graph.preview
	check(_preview.visible && !graph._graph.visible, "Preview swaps the view")
	check(_preview.rooms.size() == graph._nodes.size(), "preview has every shown room (%d)" % _preview.rooms.size())
	check(!_preview.links.is_empty(), "preview draws links")
	var _portal_links:Array = _preview.links.filter(func (l:Dictionary)->bool: return l.kind == &"portal")
	check(!_portal_links.is_empty(), "portals get their own links (%d)" % _portal_links.size())
	graph._portal_links.button_pressed = false
	check(!_preview.show_portal_links, "the Portal links toggle hides them")
	graph._portal_links.button_pressed = true
	var _overlaps:int = 0
	var _cells:Dictionary = {}
	for _key:String in _preview.rooms:
		var _room:Dictionary = _preview.rooms[_key]
		for _cell:Vector2i in _room.layout.floor:
			if _cells.has(_cell + _room.cell_offset):
				_overlaps += 1
			_cells[_cell + _room.cell_offset] = true
	check(_overlaps == 0, "no rooms overlap (%d)" % _overlaps)
	_preview.set_selected("N01")
	var _hit:String = _preview.room_at(_preview.to_screen(_preview.rooms.N01.offset + _preview.rooms.N01.center))
	check(_hit == "N01", "room_at finds the room under its centre (%s)" % _hit)
	graph.set_preview(false)
	check(graph._graph.visible && !_preview.visible, "and back to the graph")

	# synthetic rooms: A with two stairs on its right to B; B's stairs on its left
	var _a:RoomLayoutResource = _square("A", Vector2i(0, 0))
	var _b:RoomLayoutResource = _square("B", Vector2i(0, 0))
	for _y:int in [3, 5]:
		var _door:LayoutEntity = LayoutEntity.make(&"door", Vector2i(9, _y))
		_door.props = {"room": "room_B", "tag": "a%d" % _y, "connect_tag": "b"}
		_a.entities.append(_door)
	var _back:LayoutEntity = LayoutEntity.make(&"door", Vector2i(0, 4))
	_back.props = {"room": "room_A", "tag": "b", "connect_tag": "a3"}
	_b.entities.append(_back)
	var _layouts:Dictionary = {"A": _a, "B": _b}
	check(CampaignPreview.ends(_a, "A", _b, "B") == Vector2(9, 4), "two stairs side by side meet at their mean")
	var _offsets:Dictionary = CampaignPreview.layout_rooms(_layouts, "A", 3)
	check(_offsets.B.x >= 11 && _offsets.B.x <= 13 && absi(_offsets.B.y) <= 1, "B sits right of A's stairs, its stairs facing them (%s)" % _offsets.B)
	# mismatched: B's stairs on its right too -> pushed out until clear of A
	_back.cell = Vector2i(9, 4)
	_offsets = CampaignPreview.layout_rooms(_layouts, "A", 3)
	check(_offsets.B.x >= 11, "mismatched stairs: B pushed right of A, not overlapping (%s)" % _offsets.B)
	# an unlinked room lines up below
	_layouts.C = _square("C", Vector2i.ZERO)
	_offsets = CampaignPreview.layout_rooms(_layouts, "A", 3)
	check(_offsets.C.y >= 10, "unlinked room goes below (%s)" % _offsets.C)
	# portals never place rooms: C reached only by a portal still lines up below
	var _portal:LayoutEntity = LayoutEntity.make(&"portal", Vector2i(9, 9))
	_portal.props = {"room": "room_C", "tag": "pc", "connect_tag": ""}
	_a.entities.append(_portal)
	check(!CampaignPreview.stairs_between(_layouts, "A", "C") && !CampaignPreview.neighbours(_layouts, "A").has("C"), "a portal isn't a stairs link")
	_offsets = CampaignPreview.layout_rooms(_layouts, "A", 3)
	check(_offsets.C.y >= 10, "portal-only room still goes below (%s)" % _offsets.C)
	_portal.props.room = "room_B"
	check(CampaignPreview.ends(_a, "A", _b, "B") == Vector2(9, 4), "portals don't move the stairs spot")
	_check_links()
	await _check_refresh(creator, graph)

## CampaignLinks: per stairs states and problems; the preview draws one line per stairs.
func _check_links()->void:
	var _a:RoomLayoutResource = _square("A", Vector2i.ZERO)
	var _b:RoomLayoutResource = _square("B", Vector2i.ZERO)
	for _entry:Array in [[_a, Vector2i(9, 3), {"room": "room_B", "tag": "a3", "connect_tag": "b"}],
			[_a, Vector2i(9, 5), {"room": "room_B", "tag": "a5", "connect_tag": "b"}],
			[_a, Vector2i(5, 9), {"room": "", "tag": "a_down", "connect_tag": ""}],
			[_b, Vector2i(0, 4), {"room": "room_A", "tag": "b", "connect_tag": "a3"}]]:
		var _door:LayoutEntity = LayoutEntity.make(&"door", _entry[1])
		_door.props = _entry[2]
		_entry[0].entities.append(_door)
	var _layouts:Dictionary = {"A": _a, "B": _b}
	check(CampaignLinks.state(_layouts, "A", 0) == CampaignLinks.LINKED && CampaignLinks.state(_layouts, "B", 0) == CampaignLinks.LINKED, "stairs leading to each other are linked")
	check(CampaignLinks.state(_layouts, "A", 1) == CampaignLinks.ONE_WAY, "stairs arriving at stairs that lead elsewhere are one way")
	check(CampaignLinks.state(_layouts, "A", 2) == CampaignLinks.NOWHERE, "stairs without a room lead nowhere")
	_a.entities[1].props.connect_tag = "nope"
	check(CampaignLinks.state(_layouts, "A", 1) == CampaignLinks.BAD_TAG, "a missing arrival tag is bad")
	_a.entities[2].props.room = "room_ZZ"
	check(CampaignLinks.state(_layouts, "A", 2) == CampaignLinks.MISSING, "a missing room")
	check(CampaignLinks.state(_layouts, "A", 2, func (_k:String)->bool: return true) == CampaignLinks.UNKNOWN, "a hand-made room can't be checked")
	_b.entities[0].props.tag = "a3"
	var _kinds:Array = CampaignLinks.problems(_layouts, ["A", "B"]).map(func (p:Dictionary)->StringName: return p.kind)
	check(_kinds.has(CampaignLinks.BAD_TAG) && _kinds.has(CampaignLinks.MISSING) && _kinds.has(CampaignLinks.ONE_WAY), "problems list them (%s)" % [_kinds])
	_b.entities[0].props.tag = "b"
	var _preview:CampaignPreview = CampaignPreview.new()
	_preview.to_px = func (cell:Vector2i)->Vector2: return Vector2(cell) * 16.0
	var _doors:Array = _preview.links_of(_layouts, {"A": Vector2i.ZERO, "B": Vector2i(14, 0)}).filter(func (l:Dictionary)->bool: return l.kind == &"door")
	check(_doors.size() == 2, "a stairs pair draws once, other stairs their own line (%d)" % _doors.size())
	var _bad:Array = _doors.filter(func (l:Dictionary)->bool: return l.state == CampaignLinks.BAD_TAG)
	check(_bad.size() == 1 && _bad[0].to == Vector2(14 + 4.5, 4.5) * 16.0, "a broken line goes to the room's centre")
	_preview.free()

## Edits refresh the open graph / preview, keeping the view.
func _check_refresh(creator:MapCreator, graph:CampaignGraph)->void:
	var _ports:Array[int] = CampaignGraph._linkable_exits(creator.layout)
	var _door:int = -1
	for _i:int in _ports:
		if creator.layout.entities[_i].item_id == &"door" && !CampaignLinks.target(creator.layout.entities[_i]).is_empty():
			_door = _i
			break
	if _door < 0:
		check(false, "N01 has linked stairs")
		return
	graph.set_preview(true)
	await _frames(2)
	graph.preview._canvas.position += Vector2(13, 7)
	var _at:Vector2 = graph.preview._canvas.position
	creator.edit(func ()->void: creator.layout.entities[_door].props.connect_tag = "nope")
	await _frames(2)
	var _broken:Array = graph.preview.links.filter(func (l:Dictionary)->bool: return l.a == creator.key && l.index == _door)
	check(!_broken.is_empty() && _broken[0].state == CampaignLinks.BAD_TAG, "an edit refreshes the preview's links")
	check(graph.preview._canvas.position == _at, "and keeps the view")
	check(graph.link_problems.any(func (p:Dictionary)->bool: return p.key == creator.key) && graph._problems_button.visible, "the problems button lists it")
	check(MapChecks.link_problems(creator).size() > 0, "the room's live checks list it")
	creator.undo()
	await _frames(2)
	graph.set_preview(false)

func _square(key:String, origin:Vector2i)->RoomLayoutResource:
	var _layout:RoomLayoutResource = RoomLayoutResource.new()
	_layout.key = key
	for _y:int in 10:
		for _x:int in 10:
			_layout.floor[origin + Vector2i(_x, _y)] = Vector3i(1, 0, 0)
	return _layout

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
