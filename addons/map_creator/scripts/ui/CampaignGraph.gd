## Campaign graph (topbar Map / G in Edit mode): one node per room of the campaign, one
## row per door / portal with an in port (arrive here) and an out port (leads to).
## Dragging out port -> in port links them (doors both ways, portals one way); dragging a
## link off clears it. Rooms outside the campaign that are linked show dimmed. Positions,
## the start room and new campaigns save to the workspace (CampaignStore).
## Double click a room to open it; toolbar: add room, set start, remove, auto layout.
## The search box matches rooms like the room browser (others fade); the side panel shows
## the selected room's details. Preview swaps the graph for the rooms drawn with their
## tiles, placed by their stairs (CampaignPreview).
class_name CampaignGraph
extends PanelContainer

@export var creator:MapCreator
@export var start_color:Color = Color(0.35, 0.85, 0.4)
@export var boss_color:Color = Color(0.9, 0.3, 0.3)
@export var home_color:Color = Color(0.4, 0.6, 0.95)
@export var external_color:Color = Color(1, 1, 1, 0.45)
@export var problem_color:Color = Color(1, 0.45, 0.2)
@export var start_zoom:float = 0.55
@export var dim_alpha:float = 0.3
## Width share of the details panel against the graph's 1.
@export var info_ratio:float = 0.45

var store:CampaignStore
var campaign_id:String
var _graph:GraphEdit
var _campaigns:OptionButton
var _status:Label
var _search:LineEdit
var _view:Button
var _info:Label
var preview:CampaignPreview
## Searchable details of every room (rebuilt with the graph).
var index:RoomIndex = RoomIndex.new()
var selected_key:String
## key -> problems of the shown rooms
var _problems:Dictionary = {}
## Shown keys the search matches.
var matches:Dictionary = {}
var _nodes:Dictionary = {}
## GraphNode name -> room key
var _keys:Dictionary = {}

func _ready()->void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if !creator.is_node_ready():
		await creator.ready
	var _style:StyleBoxFlat = StyleBoxFlat.new()
	_style.bg_color = Color(creator.preset.bar_color, 0.97)
	_style.set_content_margin_all(2)
	add_theme_stylebox_override(&"panel", _style)
	var _box:VBoxContainer = VBoxContainer.new()
	add_child(_box)
	var _bar:HBoxContainer = HBoxContainer.new()
	_box.add_child(_bar)
	_campaigns = OptionButton.new()
	_campaigns.tooltip_text = "Campaign (rooms whose layout names it)"
	_campaigns.item_selected.connect(func (i:int)->void: show_campaign(store.campaigns[i].id))
	_bar.add_child(_campaigns)
	_search = LineEdit.new()
	_search.placeholder_text = "Search rooms: name, key, enemy, look..."
	_search.custom_minimum_size.x = 150
	_search.clear_button_enabled = true
	_search.text_changed.connect(func (_t:String)->void: apply_search())
	_search.text_submitted.connect(func (_t:String)->void: _focus_first_match())
	_bar.add_child(_search)
	for _entry:Array in [
			["New", "New campaign", _new_campaign],
			["Add room", "Add a room (new key = new room, existing key = move it here)", _add_room],
			["Start", "Make the selected room the campaign start", _set_start],
			["Open", "Edit the selected room (double click)", _open_selected],
			["Remove", "Take the selected room out of the campaign", _remove_selected],
			["Auto", "Arrange by distance from the start", _auto_layout],
			["Preview", "Switch between the link graph and the rooms drawn with their tiles, placed by their stairs", toggle_view],
			["x", "Close (G / Esc)", close]]:
		var _b:Button = Button.new()
		_b.text = _entry[0]
		_b.tooltip_text = _entry[1]
		_b.focus_mode = Control.FOCUS_NONE
		_b.pressed.connect(_entry[2])
		_bar.add_child(_b)
		if _entry[0] == "Preview":
			_view = _b
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_bar.add_child(_status)
	var _body:HBoxContainer = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(_body)
	_graph = GraphEdit.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	# the built-in menu and minimap are too big at the game's resolution; wheel zooms
	_graph.show_menu = false
	_graph.minimap_enabled = false
	_graph.zoom = start_zoom
	_graph.connection_request.connect(_on_connect)
	_graph.disconnection_request.connect(_on_disconnect)
	_graph.end_node_move.connect(_save_positions)
	_graph.node_selected.connect(func (node:Node)->void:
		if _keys.has(node.name):
			select_room(_keys[node.name]))
	_body.add_child(_graph)
	preview = CampaignPreview.new()
	preview.graph = self
	preview.tile_set = creator.floor_layer.tile_set
	var _floor:TileMapLayer = creator.floor_layer
	preview.to_px = func (cell:Vector2i)->Vector2: return _floor.map_to_local(cell)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.visible = false
	preview.room_selected.connect(func (key:String)->void: select_room(key))
	preview.room_activated.connect(_open)
	_body.add_child(preview)
	var _scroll:ScrollContainer = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = info_ratio
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_info)
	creator.graph_requested.connect(toggle)

func toggle()->void:
	if visible:
		close()
	else:
		open()

func open()->void:
	store = CampaignStore.new(creator.baker, creator.mod_state)
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_top = 2
	var _current:String = String(creator.layout.campaign) if creator.layout != null else ""
	if store.find(_current).is_empty() && !store.campaigns.is_empty():
		_current = store.campaigns[0].id
	show_campaign(_current)
	_search.grab_focus()
	_search.select_all()

func close()->void:
	visible = false
	_search.release_focus()

## Graph <-> Preview.
func toggle_view()->void:
	set_preview(!preview.visible)

func set_preview(on:bool)->void:
	preview.visible = on
	_graph.visible = !on
	_view.text = "Graph" if on else "Preview"
	if on:
		_show_preview()

func _show_preview()->void:
	var _tints:Dictionary = {}
	for _key:String in _nodes:
		_tints[_key] = _nodes[_key].self_modulate
	var _campaign:Dictionary = store.find(campaign_id)
	preview.show_rooms(_nodes.keys(), String(_campaign.get("start", "")), _tints)
	preview.set_dimmed(_dimmed())
	preview.set_selected(selected_key)

## The layout the graph reads and edits: the open room's live copy, else the stored one.
func layout_of(key:String)->RoomLayoutResource:
	if key == creator.key && creator.layout != null:
		return creator.layout
	return creator.baker.layouts.get(key, null)

func show_campaign(id:String)->void:
	campaign_id = id
	_campaigns.clear()
	for _i:int in store.campaigns.size():
		_campaigns.add_item(store.campaigns[_i].display_name)
		if store.campaigns[_i].id == id:
			_campaigns.select(_i)
	rebuild()

func rebuild()->void:
	_graph.clear_connections()
	for _node:Node in _nodes.values():
		_graph.remove_child(_node)
		_node.free()
	_nodes.clear()
	_keys.clear()
	index.build(creator.baker, creator.catalog, creator.mod_state)
	var _campaign:Dictionary = store.find(campaign_id)
	if _campaign.is_empty():
		_status.text = "No campaign: New makes one"
		_info.text = ""
		return
	var _rooms:PackedStringArray = store.rooms_of(campaign_id)
	if creator.layout != null && String(creator.layout.campaign) == campaign_id && !_rooms.has(creator.key):
		_rooms.append(creator.key)
	var _missing_positions:bool = false
	for _key:String in _rooms:
		if !_campaign.nodes.has(_key):
			_missing_positions = true
	if _missing_positions:
		store.auto_layout(campaign_id)
	_problems = _problems_by_room(_rooms)
	for _key:String in _rooms:
		_add_node(_key, false, _campaign, _problems.get(_key, PackedStringArray()))
	# linked rooms of other campaigns, dimmed, right of what links to them
	for _key:String in _rooms:
		var _layout:RoomLayoutResource = layout_of(_key)
		for _i:int in CampaignStore.exits_of(_layout):
			var _to:String = String(_layout.entities[_i].props.get("room", "")).trim_prefix("room_")
			if !_to.is_empty() && !_nodes.has(_to) && layout_of(_to) != null:
				_add_node(_to, true, _campaign, PackedStringArray())
				_nodes[_to].position_offset = _nodes[_key].position_offset + Vector2(220, 40 * _i)
	_connect_links()
	_status.text = "%s: %d rooms, start room_%s" % [_campaign.display_name, _rooms.size(), _campaign.start]
	if !_nodes.has(selected_key):
		selected_key = creator.key if _nodes.has(creator.key) else String(_campaign.start)
	apply_search()
	select_room(selected_key)
	if preview.visible:
		_show_preview()

func _add_node(key:String, external:bool, campaign:Dictionary, problems:PackedStringArray)->void:
	var _layout:RoomLayoutResource = layout_of(key)
	var _node:GraphNode = GraphNode.new()
	_node.name = "room_" + key
	_node.title = "%s %s" % [key, _layout.display_name if _layout.display_name != "room_" + key else ""]
	_node.tooltip_text = details_of(key)
	if campaign.nodes.has(key):
		_node.position_offset = Vector2(campaign.nodes[key][0], campaign.nodes[key][1])
	var _flags:PackedStringArray = []
	var _tint:Color = Color.WHITE
	if key == campaign.start:
		_flags.append("START")
		_tint = start_color
	if _layout.home:
		_flags.append("home")
		_tint = home_color
	if _layout.boss_section > 0:
		_flags.append("boss")
		_tint = boss_color
	var _waves:int = 0
	for _section:Dictionary in _layout.sections:
		_waves += _section.get("waves", []).size()
	_flags.append("%d sections, %d waves" % [_layout.sections.size(), _waves])
	if !problems.is_empty():
		_flags.append("%d problems" % problems.size())
		_tint = problem_color
	var _head:Label = Label.new()
	_head.text = " ".join(_flags)
	_node.add_child(_head)
	for _i:int in CampaignStore.exits_of(_layout):
		var _entity:LayoutEntity = _layout.entities[_i]
		var _row:Label = Label.new()
		if _entity.item_id == &"victory":
			_row.text = "victory exit"
		else:
			var _to:String = String(_entity.props.get("room", ""))
			_row.text = "%s %s -> %s" % [_entity.item_id, _entity.props.get("tag", ""), _to if !_to.is_empty() else "(unlinked)"]
		_node.add_child(_row)
		var _slot:int = _node.get_child_count() - 1
		var _linkable:bool = _entity.item_id != &"victory"
		_node.set_slot(_slot, _linkable, 0, Color(0.7, 0.9, 1.0), _linkable, 0, Color(1.0, 0.85, 0.5))
	_node.self_modulate = external_color if external else _tint
	_node.gui_input.connect(func (event:InputEvent)->void:
		if event is InputEventMouseButton && event.double_click && event.button_index == MOUSE_BUTTON_LEFT:
			_open(key))
	_graph.add_child(_node)
	_nodes[key] = _node
	_keys[_node.name] = key

## Port index (out or in) of entity `index` in `layout`: its order among the exits.
static func port_of(layout:RoomLayoutResource, index:int)->int:
	var _linkable:Array[int] = _linkable_exits(layout)
	return _linkable.find(index)

static func _linkable_exits(layout:RoomLayoutResource)->Array[int]:
	var _out:Array[int] = []
	for _i:int in CampaignStore.exits_of(layout):
		if layout.entities[_i].item_id != &"victory":
			_out.append(_i)
	return _out

func _connect_links()->void:
	for _from:String in _nodes:
		var _layout:RoomLayoutResource = layout_of(_from)
		for _i:int in _linkable_exits(_layout):
			var _entity:LayoutEntity = _layout.entities[_i]
			var _to:String = String(_entity.props.get("room", "")).trim_prefix("room_")
			if !_nodes.has(_to):
				continue
			var _target:RoomLayoutResource = layout_of(_to)
			for _j:int in _linkable_exits(_target):
				if String(_target.entities[_j].props.get("tag", "")) == String(_entity.props.get("connect_tag", "")):
					_graph.connect_node(_nodes[_from].name, port_of(_layout, _i), _nodes[_to].name, port_of(_target, _j))
					break

## Room key -> problems from the game baker's rules plus links that arrive nowhere.
func _problems_by_room(rooms:PackedStringArray)->Dictionary:
	var _baker:LayoutBaker = creator.baker
	var _out:Dictionary = {}
	var _was_quiet:bool = _baker.quiet
	_baker.quiet = true
	for _key:String in rooms:
		var _layout:RoomLayoutResource = layout_of(_key)
		var _list:PackedStringArray = []
		_baker.reset_problems()
		_baker._validate(_layout)
		for _problem:Dictionary in _baker.problem_list:
			_list.append(_problem.text)
		for _i:int in _linkable_exits(_layout):
			var _entity:LayoutEntity = _layout.entities[_i]
			var _to:String = String(_entity.props.get("room", "")).trim_prefix("room_")
			if _to.is_empty():
				_list.append("%s at %s leads nowhere" % [_entity.item_id, _entity.cell])
			elif layout_of(_to) == null && !ResourceLoader.exists(creator.scene_of(_to)):
				_list.append("%s at %s leads to missing room_%s" % [_entity.item_id, _entity.cell, _to])
		if !_list.is_empty():
			_out[_key] = _list
	_baker.reset_problems()
	_baker.quiet = _was_quiet
	return _out

# --- search / details -------------------------------------------------------------------

## The room browser's details of `key` plus its graph problems.
func details_of(key:String)->String:
	var _text:String = index.details(key, creator.catalog, creator.rooms)
	var _list:PackedStringArray = _problems.get(key, PackedStringArray())
	if !_list.is_empty():
		_text += "\nProblems:\n- " + "\n- ".join(_list)
	return _text

## Fades the shown rooms the search box doesn't match.
func apply_search()->void:
	matches.clear()
	for _key:String in index.search(_search.text):
		if _nodes.has(_key):
			matches[_key] = true
	for _key:String in _nodes:
		_nodes[_key].modulate = Color.WHITE if matches.has(_key) else Color(1, 1, 1, dim_alpha)
	if preview.visible:
		preview.set_dimmed(_dimmed())
	if !_search.text.strip_edges().is_empty():
		var _campaign:Dictionary = store.find(campaign_id)
		_status.text = "%d of %d rooms match" % [matches.size(), _nodes.size()] if !_campaign.is_empty() else ""

func _dimmed()->Dictionary:
	var _out:Dictionary = {}
	for _key:String in _nodes:
		if !matches.has(_key):
			_out[_key] = true
	return _out

## Selects a room (graph node / preview) and shows its details; `center` scrolls to it.
func select_room(key:String, center:bool = false)->void:
	selected_key = key if _nodes.has(key) else ""
	_info.text = details_of(selected_key) if !selected_key.is_empty() else "Select a room"
	if selected_key.is_empty():
		return
	var _node:GraphNode = _nodes[selected_key]
	if !_node.selected:
		_graph.set_selected(_node)
	preview.set_selected(selected_key)
	if center:
		_graph.scroll_offset = (_node.position_offset + _node.size * 0.5) * _graph.zoom - _graph.size * 0.5
		preview.center_on(selected_key)

func _focus_first_match()->void:
	for _key:String in index.search(_search.text):
		if _nodes.has(_key):
			select_room(_key, true)
			return

# --- editing ----------------------------------------------------------------------------

## Out port `from_port` of room A -> in port `to_port` of room B.
func link(from_key:String, from_port:int, to_key:String, to_port:int)->void:
	var _a:RoomLayoutResource = layout_of(from_key)
	var _b:RoomLayoutResource = layout_of(to_key)
	var _ai:int = _linkable_exits(_a)[from_port]
	var _bj:int = _linkable_exits(_b)[to_port]
	var _a_entity:LayoutEntity = _a.entities[_ai]
	var _b_entity:LayoutEntity = _b.entities[_bj]
	var _a_tag:String = String(_a_entity.props.get("tag", ""))
	var _b_tag:String = String(_b_entity.props.get("tag", ""))
	if _a_tag.is_empty():
		_a_tag = ("%s_%s" % [from_key, to_key]).to_lower()
	if _b_tag.is_empty():
		_b_tag = ("%s_%s" % [to_key, from_key]).to_lower()
	var _a_props:Dictionary = {"tag": _a_tag, "room": "room_" + to_key, "connect_tag": _b_tag}
	var _b_props:Dictionary = {"tag": _b_tag}
	if _a_entity.item_id == &"door" && _b_entity.item_id == &"door":
		_b_props.room = "room_" + from_key
		_b_props.connect_tag = _a_tag
	_change(from_key, _ai, _a_props)
	_change(to_key, _bj, _b_props)
	rebuild()

func unlink(from_key:String, from_port:int)->void:
	var _a:RoomLayoutResource = layout_of(from_key)
	_change(from_key, _linkable_exits(_a)[from_port], {"room": "", "connect_tag": ""})
	rebuild()

## Merges props into entity `index` of room `key` (the open room through an undoable
## edit, saved with it; other rooms are stored and baked right away).
func _change(key:String, index:int, props:Dictionary)->void:
	if key == creator.key && creator.layout != null:
		creator.edit(func ()->void: creator.layout.entities[index].props.merge(props, true))
		return
	var _copy:RoomLayoutResource = creator.baker.layouts[key].clone()
	_copy.entities[index].props.merge(props, true)
	if !creator.rooms.store(_copy):
		creator.message.emit(creator.rooms.last_message)

func _change_layout(key:String, change:Callable)->void:
	if key == creator.key && creator.layout != null:
		creator.edit(func ()->void: change.call(creator.layout))
		return
	var _copy:RoomLayoutResource = creator.baker.layouts[key].clone()
	change.call(_copy)
	if !creator.rooms.store(_copy):
		creator.message.emit(creator.rooms.last_message)

func _on_connect(from_node:StringName, from_port:int, to_node:StringName, to_port:int)->void:
	if from_node == to_node:
		return
	link(_keys[from_node], from_port, _keys[to_node], to_port)

func _on_disconnect(from_node:StringName, from_port:int, _to_node:StringName, _to_port:int)->void:
	unlink(_keys[from_node], from_port)

func _selected()->String:
	if _nodes.has(selected_key):
		return selected_key
	for _key:String in _nodes:
		if _nodes[_key].selected:
			return _key
	return ""

func _save_positions()->void:
	var _campaign:Dictionary = store.find(campaign_id)
	for _key:String in _nodes:
		if store.rooms_of(campaign_id).has(_key):
			var _pos:Vector2 = _nodes[_key].position_offset
			_campaign.nodes[_key] = [roundf(_pos.x), roundf(_pos.y)]
	_save()

func _save()->void:
	if store.save() != OK:
		creator.message.emit("Campaigns not saved: pick a mod (workspace menu)")

func _new_campaign()->void:
	creator.prompt_requested.emit("New campaign name", "my_campaign", func (text:String)->void:
		var _campaign:Dictionary = store.add(text, text)
		if _campaign.is_empty():
			creator.message.emit("Campaign '%s' exists or isn't a valid name" % text)
			return
		_save()
		show_campaign(_campaign.id))

func _add_room()->void:
	if campaign_id.is_empty():
		return
	creator.prompt_requested.emit("Room key to add (new or existing)", "", func (key:String)->void:
		if !creator.baker.layouts.has(key) && !creator.rooms.new_room(key, "", creator.layout):
			creator.message.emit(creator.rooms.last_message)
			return
		var _id:StringName = StringName(campaign_id)
		_change_layout(key, func (layout:RoomLayoutResource)->void: layout.campaign = _id)
		if String(store.find(campaign_id).start).is_empty():
			store.find(campaign_id).start = key
			_save()
		rebuild())

func _set_start()->void:
	var _key:String = _selected()
	if _key.is_empty() || !store.rooms_of(campaign_id).has(_key):
		creator.message.emit("Select a room of this campaign")
		return
	var _campaign:Dictionary = store.find(campaign_id)
	var _old:String = _campaign.start
	_campaign.start = _key
	_save()
	if !layout_of(_key).home:
		_change_layout(_key, func (layout:RoomLayoutResource)->void: layout.start = true)
	if !_old.is_empty() && _old != _key && layout_of(_old) != null && layout_of(_old).start:
		_change_layout(_old, func (layout:RoomLayoutResource)->void: layout.start = false)
	rebuild()

func _remove_selected()->void:
	var _key:String = _selected()
	if _key.is_empty() || !store.rooms_of(campaign_id).has(_key):
		return
	_change_layout(_key, func (layout:RoomLayoutResource)->void: layout.campaign = &"")
	store.find(campaign_id).nodes.erase(_key)
	_save()
	rebuild()

func _auto_layout()->void:
	store.find(campaign_id).nodes.clear()
	store.auto_layout(campaign_id)
	_save()
	rebuild()

func _open_selected()->void:
	var _key:String = _selected()
	if !_key.is_empty():
		_open(_key)

func _open(key:String)->void:
	if key == creator.key:
		close()
		return
	if creator.switch_room(key):
		close()

func _unhandled_key_input(event:InputEvent)->void:
	if visible && event is InputEventKey && event.pressed && event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
