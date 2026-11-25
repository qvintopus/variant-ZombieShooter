## Campaign graph (topbar Map / G in Edit mode): one node per room of the campaign, one
## row per door / portal with an in port (arrive here) and an out port (leads to).
## Dragging out port -> in port links them (doors both ways, portals one way); dragging a
## link off clears it. Rooms outside the campaign that are linked show dimmed. Positions,
## the start room and new campaigns save to the workspace (CampaignStore).
## Double click a room to open it (an exit row: with that exit selected); toolbar: add room, set start, remove, auto layout.
## The search box matches rooms like the room browser (others fade); the side panel shows
## the selected room's details. Preview swaps the graph for the rooms drawn with their
## tiles, placed by their stairs (CampaignPreview). Linking stairs rewires both ways and
## unlinks their old partners; the side panel's dropdowns relink the selected room's exits.
## Broken links (CampaignLinks) tint rooms and show in the bar's problems button. Saves,
## edits and workspace changes refresh the open graph / preview (keeping the view).
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
var _portal_links:CheckButton
var _info:RoomDetails
var _problems_button:Button
var _problems_menu:PopupMenu
## Problems listed by the button: [{key, text}]
var link_problems:Array[Dictionary] = []
var _rebuild_queued:bool
## Campaign the preview last zoomed to fit ("" = none yet).
var _fitted_campaign:Variant = null
var _notice_time:float
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
	_search.custom_minimum_size.x = 120
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
			["Preview", "Switch between the link graph and the rooms drawn with their tiles, placed by their stairs (right click a stairs dot to link it)", toggle_view],
			["x", "Close (G / Esc)", close]]:
		var _b:Button = Button.new()
		_b.text = _entry[0]
		_b.tooltip_text = _entry[1]
		_b.focus_mode = Control.FOCUS_NONE
		_b.pressed.connect(_entry[2])
		_bar.add_child(_b)
		if _entry[0] == "Preview":
			_view = _b
	_portal_links = CheckButton.new()
	_portal_links.text = "Portals"
	_portal_links.tooltip_text = "Preview: thin lines from portals to their target rooms (portals and their targets always show)"
	_portal_links.focus_mode = Control.FOCUS_NONE
	_portal_links.button_pressed = true
	_portal_links.visible = false
	_portal_links.toggled.connect(func (on:bool)->void: preview.set_show_portal_links(on))
	_bar.add_child(_portal_links)
	_problems_button = Button.new()
	_problems_button.focus_mode = Control.FOCUS_NONE
	_problems_button.tooltip_text = "Broken / missing links of the shown rooms: click to list, pick one to select its room"
	_problems_button.add_theme_color_override(&"font_color", problem_color)
	_problems_button.visible = false
	_problems_button.pressed.connect(_show_problems_menu)
	_bar.add_child(_problems_button)
	_problems_menu = PopupMenu.new()
	_problems_menu.id_pressed.connect(func (id:int)->void:
		if id < link_problems.size():
			select_room(link_problems[id].key, true))
	add_child(_problems_menu)
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
	_info = RoomDetails.new(creator, index)
	_info.opened.connect(close)
	_info.relink_requested.connect(relink)
	_scroll.add_child(_info)
	creator.graph_requested.connect(toggle)
	for _signal:Signal in [creator.layout_changed, creator.dirty_changed, creator.workspace_changed]:
		_signal.connect(_queue_rebuild)
	creator.message.connect(_notice)

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

## Rebuilds once at the end of the frame while shown (saves, edits, workspace switches).
func _queue_rebuild()->void:
	if !visible || _rebuild_queued:
		return
	_rebuild_queued = true
	(func ()->void:
		if _rebuild_queued && visible && store != null:
			store.reload()
			rebuild()).call_deferred()

## Messages show in the bar while the graph covers the topbar.
func _notice(text:String)->void:
	if !visible || text.is_empty():
		return
	_status.text = text
	_notice_time = 4.0

func _process(delta:float)->void:
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_status.text = _summary()

## Graph <-> Preview.
func toggle_view()->void:
	set_preview(!preview.visible)

func set_preview(on:bool)->void:
	preview.visible = on
	_graph.visible = !on
	_view.text = "Graph" if on else "Preview"
	_portal_links.visible = on
	if on:
		_show_preview()

func _show_preview()->void:
	var _tints:Dictionary = {}
	for _key:String in _nodes:
		_tints[_key] = _nodes[_key].self_modulate
	var _campaign:Dictionary = store.find(campaign_id)
	var _refit:bool = _fitted_campaign != campaign_id
	_fitted_campaign = campaign_id
	var _all:Dictionary = all_layouts()
	preview.show_rooms(_nodes.keys(), String(_campaign.get("start", "")), _tints, _refit,
		func (key:String, index:int)->StringName: return CampaignLinks.state(_all, key, index, _exists))
	preview.set_dimmed(_dimmed())
	preview.set_selected(selected_key)

## The layout the graph reads and edits: the open room's live copy, else the stored one.
func layout_of(key:String)->RoomLayoutResource:
	if key == creator.key && creator.layout != null:
		return creator.layout
	return creator.baker.layouts.get(key, null)

## key -> layout of every room, the open one live.
func all_layouts()->Dictionary:
	var _out:Dictionary = creator.baker.layouts.duplicate()
	if creator.layout != null && !creator.key.is_empty():
		_out[creator.key] = creator.layout
	return _out

## A room without a layout that has a (hand-made) scene.
func _exists(key:String)->bool:
	return layout_of(key) != null || ResourceLoader.exists(creator.scene_of(key))

func show_campaign(id:String)->void:
	campaign_id = id
	_campaigns.clear()
	for _i:int in store.campaigns.size():
		_campaigns.add_item(store.campaigns[_i].display_name)
		if store.campaigns[_i].id == id:
			_campaigns.select(_i)
	rebuild()

func rebuild()->void:
	_rebuild_queued = false
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
		_info.show_message("")
		link_problems.clear()
		_problems_button.visible = false
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
	_status.text = _summary()
	_problems_button.text = "! %d link problem%s" % [link_problems.size(), "" if link_problems.size() == 1 else "s"]
	_problems_button.visible = !link_problems.is_empty()
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
			# double click the row: open the room with this exit selected
			var _tag:String = String(_entity.props.get("tag", ""))
			_row.mouse_filter = Control.MOUSE_FILTER_PASS
			_row.tooltip_text = "Double click: open %s with this exit selected" % key
			_row.gui_input.connect(func (event:InputEvent)->void:
				if event is InputEventMouseButton && event.double_click && event.button_index == MOUSE_BUTTON_LEFT:
					_row.accept_event()
					_open(key, {"tags": PackedStringArray([_tag])}))
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

func _summary()->String:
	var _campaign:Dictionary = store.find(campaign_id) if store != null else {}
	if _campaign.is_empty():
		return ""
	return "%s: %d rooms, start room_%s" % [_campaign.display_name, store.rooms_of(campaign_id).size(), _campaign.start]

## Room key -> problems from the game baker's rules plus broken links (CampaignLinks);
## the link ones also fill link_problems.
func _problems_by_room(rooms:PackedStringArray)->Dictionary:
	var _baker:LayoutBaker = creator.baker
	var _out:Dictionary = {}
	var _was_quiet:bool = _baker.quiet
	_baker.quiet = true
	link_problems.clear()
	var _all:Dictionary = all_layouts()
	for _key:String in rooms:
		var _layout:RoomLayoutResource = layout_of(_key)
		var _list:PackedStringArray = []
		_baker.reset_problems()
		_baker._validate(_layout)
		for _problem:Dictionary in _baker.problem_list:
			_list.append(_problem.text)
			if String(_problem.text).contains("arrives at"):
				link_problems.append({"key": _key, "text": "room_%s: %s" % [_key, _problem.text.trim_prefix(_key + ": ")]})
		for _problem:Dictionary in CampaignLinks.problems(_all, [_key], _exists):
			_list.append(_problem.text)
			link_problems.append({"key": _key, "text": "room_%s: %s" % [_key, _problem.text]})
		if !_list.is_empty():
			_out[_key] = _list
	_baker.reset_problems()
	_baker.quiet = _was_quiet
	return _out

# --- search / details -------------------------------------------------------------------

## The room browser's details of `key` plus its graph problems.
func details_of(key:String)->String:
	var _text:String = index.details(key, creator.catalog, creator.rooms)
	var _problems_text:String = _problem_text(key)
	return _text + ("\n" + _problems_text if !_problems_text.is_empty() else "")

func _problem_text(key:String)->String:
	var _list:PackedStringArray = _problems.get(key, PackedStringArray())
	return "Problems:\n- " + "\n- ".join(_list) if !_list.is_empty() else ""

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
	if selected_key.is_empty():
		_info.show_message("Select a room")
	else:
		_info.show_room(selected_key, _problem_text(selected_key), _relink_rows(selected_key))
	if selected_key.is_empty():
		return
	var _node:GraphNode = _nodes[selected_key]
	if !_node.selected:
		_graph.set_selected(_node)
	preview.set_selected(selected_key)
	if center:
		_graph.scroll_offset = (_node.position_offset + _node.size * 0.5) * _graph.zoom - _graph.size * 0.5
		preview.center_on(selected_key)

func _show_problems_menu()->void:
	_problems_menu.clear()
	for _i:int in link_problems.size():
		_problems_menu.add_item(link_problems[_i].text, _i)
	_problems_menu.reset_size()
	_problems_menu.position = Vector2i(_problems_button.get_screen_position() + Vector2(0, _problems_button.size.y))
	_problems_menu.popup()

func _focus_first_match()->void:
	for _key:String in index.search(_search.text):
		if _nodes.has(_key):
			select_room(_key, true)
			return

# --- editing ----------------------------------------------------------------------------

## Out port `from_port` of room A -> in port `to_port` of room B.
func link(from_key:String, from_port:int, to_key:String, to_port:int)->void:
	link_exits(from_key, _linkable_exits(layout_of(from_key))[from_port], to_key, _linkable_exits(layout_of(to_key))[to_port])

## Exit entity `ai` of room A leads to exit `bj` of room B (stairs to stairs: both ways).
## Stairs that arrived at either one before lose their link (they'd be one way).
func link_exits(from_key:String, ai:int, to_key:String, bj:int)->void:
	var _a_entity:LayoutEntity = layout_of(from_key).entities[ai]
	var _b_entity:LayoutEntity = layout_of(to_key).entities[bj]
	var _a_tag:String = String(_a_entity.props.get("tag", ""))
	var _b_tag:String = String(_b_entity.props.get("tag", ""))
	var _both:bool = _a_entity.item_id == &"door" && _b_entity.item_id == &"door"
	_release(from_key, _a_tag, [to_key, bj])
	if _both:
		_release(to_key, _b_tag, [from_key, ai])
	if _a_tag.is_empty():
		_a_tag = ("%s_%s" % [from_key, to_key]).to_lower()
	if _b_tag.is_empty():
		_b_tag = ("%s_%s" % [to_key, from_key]).to_lower()
	var _a_props:Dictionary = {"tag": _a_tag, "room": "room_" + to_key, "connect_tag": _b_tag}
	var _b_props:Dictionary = {"tag": _b_tag}
	if _both:
		_b_props.room = "room_" + from_key
		_b_props.connect_tag = _a_tag
	_change(from_key, ai, _a_props)
	_change(to_key, bj, _b_props)
	rebuild()

## Unlinks the stairs (other than `keep` [key, index]) that arrive at the exit tagged
## `tag` of room `key`.
func _release(key:String, tag:String, keep:Array)->void:
	if tag.is_empty():
		return
	var _all:Dictionary = all_layouts()
	for _other:String in _all:
		var _layout:RoomLayoutResource = _all[_other]
		for _i:int in _layout.entities.size():
			var _entity:LayoutEntity = _layout.entities[_i]
			if _entity.item_id == &"door" && CampaignLinks.target(_entity) == key \
					&& String(_entity.props.get("connect_tag", "")) == tag && [_other, _i] != keep:
				_change(_other, _i, {"room": "", "connect_tag": ""})

func unlink(from_key:String, from_port:int)->void:
	unlink_exit(from_key, _linkable_exits(layout_of(from_key))[from_port])

## Clears exit `index` of room `key`, and its partner stairs if they lead back to it.
func unlink_exit(key:String, index:int)->void:
	var _all:Dictionary = all_layouts()
	var _entity:LayoutEntity = _all[key].entities[index]
	if _entity.item_id == &"door" && CampaignLinks.state(_all, key, index) == CampaignLinks.LINKED:
		var _to:String = CampaignLinks.target(_entity)
		var _p:int = CampaignLinks.partner(_all, key, index)
		if _all[_to].entities[_p].item_id == &"door":
			_change(_to, _p, {"room": "", "connect_tag": ""})
	_change(key, index, {"room": "", "connect_tag": ""})
	rebuild()

## Only exit `index` of `key` changes: it leads to exit `to_index` of `to_key` (that one
## gets a tag if it has none) and nothing else is touched, so stairs can end up one way.
## `to_index` -1: just the room, arriving nowhere (a broken link, fixed later).
func link_one_way(key:String, index:int, to_key:String, to_index:int)->void:
	var _tag:String = ""
	if to_index >= 0:
		var _b:LayoutEntity = layout_of(to_key).entities[to_index]
		_tag = String(_b.props.get("tag", ""))
		if _tag.is_empty():
			_tag = ("%s_%s" % [to_key, key]).to_lower()
			_change(to_key, to_index, {"tag": _tag})
	var _a:LayoutEntity = layout_of(key).entities[index]
	var _props:Dictionary = {"room": "room_" + to_key, "connect_tag": _tag}
	if String(_a.props.get("tag", "")).is_empty():
		_props.tag = ("%s_%s" % [key, to_key]).to_lower()
	_change(key, index, _props)
	rebuild()

## Rooms exit `index` of `key` can lead to, for the preview's menu: [{key, free, exits:
## [{index, text, free}]}], exits of the same kind, rooms and exits that are free (not
## linked both ways / properly) first. `current` [key, index] marks the present target.
func exit_targets(key:String, index:int)->Array:
	var _all:Dictionary = all_layouts()
	var _entity:LayoutEntity = _all[key].entities[index]
	var _out:Array = []
	var _keys:Array = _nodes.keys()
	_keys.sort()
	for _other:String in _keys:
		var _layout:RoomLayoutResource = layout_of(_other)
		if _other == key || _layout == null:
			continue
		var _exits:Array = []
		var _free:int = 0
		for _j:int in _linkable_exits(_layout):
			var _e:LayoutEntity = _layout.entities[_j]
			if _e.item_id != _entity.item_id:
				continue
			var _state:StringName = CampaignLinks.state(_all, _other, _j, _exists)
			var _is_free:bool = _state != CampaignLinks.LINKED
			var _to:String = CampaignLinks.target(_e)
			var _text:String = "%s at %s" % [_e.props.get("tag", "") if !String(_e.props.get("tag", "")).is_empty() else "(no tag)", _e.cell]
			_text += "  [free%s]" % ("" if _state == CampaignLinks.NOWHERE else ": " + String(_state).replace("_", " ")) if _is_free else "  -> room_%s" % _to
			_exits.append({"index": _j, "text": _text, "free": _is_free})
			_free += 1 if _is_free else 0
		if _exits.is_empty():
			continue
		_exits.sort_custom(func (x:Dictionary, y:Dictionary)->bool: return x.free && !y.free)
		_out.append({"key": _other, "free": _free, "exits": _exits})
	_out.sort_custom(func (x:Dictionary, y:Dictionary)->bool: return x.free > 0 && y.free == 0)
	return _out

## Side panel dropdown picked: exit `index` of `key` -> exit `to_index` of `to_key`
## ("" = unlink).
func relink(key:String, index:int, to_key:String, to_index:int)->void:
	if to_key.is_empty():
		unlink_exit(key, index)
	else:
		link_exits(key, index, to_key, to_index)

## Dropdown rows of `key`'s stairs / portals: [{index, label, options: [{key, index,
## text}], selected (option index, -1 = current target isn't listed), current}].
## Options: exits of the same kind in the other shown rooms.
func _relink_rows(key:String)->Array:
	var _rows:Array = []
	var _layout:RoomLayoutResource = layout_of(key)
	if _layout == null:
		return _rows
	var _all:Dictionary = all_layouts()
	var _keys:Array = _nodes.keys()
	_keys.sort()
	for _i:int in _linkable_exits(_layout):
		var _entity:LayoutEntity = _layout.entities[_i]
		var _to:String = CampaignLinks.target(_entity)
		var _p:int = CampaignLinks.partner(_all, key, _i)
		var _row:Dictionary = {"index": _i, "options": [], "selected": -1,
			"label": "%s %s" % ["stairs" if _entity.item_id == &"door" else "portal", _entity.props.get("tag", "")],
			"state": CampaignLinks.state(_all, key, _i, _exists),
			"current": "room_%s '%s'" % [_to, _entity.props.get("connect_tag", "")] if !_to.is_empty() else ""}
		for _other:String in _keys:
			if _other == key:
				continue
			var _target:RoomLayoutResource = layout_of(_other)
			for _j:int in _linkable_exits(_target):
				var _e:LayoutEntity = _target.entities[_j]
				if _e.item_id != _entity.item_id:
					continue
				if _other == _to && _j == _p:
					_row.selected = _row.options.size()
				_row.options.append({"key": _other, "index": _j, "text": "room_%s %s" % [_other, _e.props.get("tag", "")]})
		_rows.append(_row)
	return _rows

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

## `focus` {tags, back_to}: what the room selects (MapCreator.focus_exits).
func _open(key:String, focus:Dictionary = {})->void:
	if creator.open_room(key, focus):
		close()

func _unhandled_key_input(event:InputEvent)->void:
	if visible && event is InputEventKey && event.pressed && event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
