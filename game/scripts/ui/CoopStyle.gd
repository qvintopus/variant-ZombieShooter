## The look of the co-op screens (Co-op dialog, its pages, the quit prompt): a dark card with
## one amber accent. The game theme draws buttons with no fill and no border (the title menu
## adds its own shader), so here every button kind has a visible box and clear hover,
## pressed, focus and disabled states. Colour means one thing each: amber = the thing to do,
## green = live / done, red = destructive / failed.
## Button kinds are theme type variations: PRIMARY, DANGER, GHOST, NAV (and plain Button).
class_name CoopStyle
extends RefCounted

const THEME_PATH:String = "res://addons/top_down/resources/theme/game_gui_theme.theme"

const BG:Color = Color("121418")
const CARD:Color = Color("1b1f26")
const RAISED:Color = Color("262c35")
const FIELD:Color = Color("0c0e11")
const BORDER:Color = Color("343c48")
const TEXT:Color = Color("e8eaed")
const MUTED:Color = Color("8a93a0")
const AMBER:Color = Color("f2b33d")
const INK:Color = Color("1a1405")
const GREEN:Color = Color("3ccb8f")
const RED:Color = Color("e5484d")

const BODY:int = 8
const SMALL:int = 7
const HEADING:int = 10
const TITLE:int = 12

const PRIMARY:StringName = &"PrimaryButton"
const DANGER:StringName = &"DangerButton"
const GHOST:StringName = &"GhostButton"
const NAV:StringName = &"NavButton"
const CHIP:StringName = &"ChipButton"

enum Tone {INFO, OK, WARN, ERROR, MUTED}
enum Step {TODO, ACTIVE, DONE}

static var _theme:Theme

static func tone_color(tone:int)->Color:
	match tone:
		Tone.OK: return GREEN
		Tone.WARN: return AMBER
		Tone.ERROR: return RED
		Tone.MUTED: return MUTED
	return TEXT

static func box(fill:Color, border:Color = Color.TRANSPARENT, width:int = 0, radius:int = 2, h:float = 6.0, v:float = 2.0)->StyleBoxFlat:
	var _box:StyleBoxFlat = StyleBoxFlat.new()
	_box.bg_color = fill
	_box.border_color = border
	_box.set_border_width_all(width)
	_box.set_corner_radius_all(radius)
	_box.content_margin_left = h
	_box.content_margin_right = h
	_box.content_margin_top = v
	_box.content_margin_bottom = v
	_box.anti_aliasing = false
	return _box

## The game theme plus the co-op look; built once.
static func theme()->Theme:
	if _theme != null:
		return _theme
	var _t:Theme = (load(THEME_PATH) as Theme).duplicate()
	_t.default_font_size = BODY
	for _type:StringName in [&"Label", &"Button", &"LineEdit", &"CheckBox", &"SpinBox", &"TooltipLabel"]:
		_t.set_font_size(&"font_size", _type, BODY)

	_t.set_color(&"font_color", &"Label", TEXT)
	_t.set_constant(&"line_spacing", &"Label", 0)
	_variation(_t, &"MutedLabel", &"Label")
	_t.set_color(&"font_color", &"MutedLabel", MUTED)
	_variation(_t, &"SmallLabel", &"Label")
	_t.set_color(&"font_color", &"SmallLabel", MUTED)
	_t.set_font_size(&"font_size", &"SmallLabel", SMALL)
	_variation(_t, &"HeadingLabel", &"Label")
	_t.set_font_size(&"font_size", &"HeadingLabel", HEADING)
	_variation(_t, &"TitleLabel", &"Label")
	_t.set_font_size(&"font_size", &"TitleLabel", TITLE)
	_t.set_color(&"font_color", &"TitleLabel", AMBER)

	var _focus:StyleBoxFlat = box(Color.TRANSPARENT, AMBER, 1, 2)
	_focus.draw_center = false
	_focus.set_expand_margin_all(1)

	# secondary (plain Button)
	_buttons(_t, &"Button", box(RAISED, BORDER, 1), box(Color("313844"), MUTED, 1), box(FIELD, BORDER, 1),
		box(Color(RAISED, 0.35), Color(BORDER, 0.5), 1), TEXT, Color.WHITE, Color(MUTED, 0.7), _focus)
	# primary: the one thing to do
	_variation(_t, PRIMARY, &"Button")
	var _focus_light:StyleBoxFlat = _focus.duplicate()
	_focus_light.border_color = TEXT
	_buttons(_t, PRIMARY, box(AMBER), box(AMBER.lightened(0.18)), box(AMBER.darkened(0.2)),
		box(Color(AMBER, 0.22)), INK, INK, Color(TEXT, 0.45), _focus_light)
	# a small pick (recent hosts)
	_variation(_t, CHIP, &"Button")
	_buttons(_t, CHIP, box(FIELD, BORDER, 1, 6, 5, 1), box(RAISED, MUTED, 1, 6, 5, 1), box(RAISED, AMBER, 1, 6, 5, 1),
		box(Color.TRANSPARENT, Color(BORDER, 0.5), 1, 6, 5, 1), MUTED, TEXT, Color(MUTED, 0.45), _focus)
	_t.set_font_size(&"font_size", CHIP, SMALL)
	# destructive
	_variation(_t, DANGER, &"Button")
	_buttons(_t, DANGER, box(Color(RED, 0.1), Color(RED, 0.7), 1), box(Color(RED, 0.25), RED, 1), box(Color(RED, 0.4), RED, 1),
		box(Color.TRANSPARENT, Color(RED, 0.25), 1), RED.lightened(0.15), Color.WHITE, Color(RED, 0.45), _focus)
	# a quiet text action
	_variation(_t, GHOST, &"Button")
	_buttons(_t, GHOST, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 3), box(Color(RAISED, 0.7), Color.TRANSPARENT, 0, 2, 3),
		box(RAISED, Color.TRANSPARENT, 0, 2, 3), box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 3), MUTED, TEXT, Color(MUTED, 0.45), _focus)
	_t.set_font_size(&"font_size", GHOST, SMALL)
	# the left rail: the open page has an amber bar
	_variation(_t, NAV, &"Button")
	var _nav_on:StyleBoxFlat = box(RAISED, AMBER, 0, 0, 8, 4)
	_nav_on.border_width_left = 2
	_buttons(_t, NAV, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 8, 4), box(Color(RAISED, 0.6), Color.TRANSPARENT, 0, 0, 8, 4), _nav_on,
		box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 8, 4), MUTED, TEXT, Color(MUTED, 0.4), _focus)
	_t.set_color(&"font_pressed_color", NAV, TEXT)
	_t.set_color(&"font_hover_pressed_color", NAV, TEXT)
	_t.set_stylebox(&"hover_pressed", NAV, _nav_on)
	_t.set_constant(&"h_separation", NAV, 4)

	# fields
	for _type:StringName in [&"LineEdit"]:
		_t.set_stylebox(&"normal", _type, box(FIELD, BORDER, 1, 2, 4, 2))
		_t.set_stylebox(&"focus", _type, _focus)
		_t.set_stylebox(&"read_only", _type, box(Color(FIELD, 0.6), Color(BORDER, 0.6), 1, 2, 4, 2))
		_t.set_color(&"font_color", _type, TEXT)
		_t.set_color(&"font_uneditable_color", _type, Color(TEXT, 0.85))
		_t.set_color(&"font_placeholder_color", _type, Color(MUTED, 0.6))
		_t.set_color(&"caret_color", _type, AMBER)
		_t.set_color(&"selection_color", _type, Color(AMBER, 0.35))
	for _state:StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		_t.set_stylebox(_state, &"CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 2, 1))
	_t.set_stylebox(&"focus", &"CheckBox", _focus)
	_t.set_color(&"font_color", &"CheckBox", MUTED)
	_t.set_color(&"font_hover_color", &"CheckBox", TEXT)
	_t.set_color(&"font_pressed_color", &"CheckBox", TEXT)
	_t.set_color(&"font_hover_pressed_color", &"CheckBox", TEXT)
	_t.set_color(&"font_disabled_color", &"CheckBox", Color(MUTED, 0.45))
	_t.set_icon(&"checked", &"CheckBox", _check_icon(true, true))
	_t.set_icon(&"unchecked", &"CheckBox", _check_icon(false, true))
	_t.set_icon(&"checked_disabled", &"CheckBox", _check_icon(true, false))
	_t.set_icon(&"unchecked_disabled", &"CheckBox", _check_icon(false, false))
	_t.set_constant(&"h_separation", &"CheckBox", 4)

	# panels
	_t.set_stylebox(&"panel", &"PanelContainer", box(CARD, BORDER, 1, 3, 6, 5))
	_variation(_t, &"DialogPanel", &"PanelContainer")
	var _dialog:StyleBoxFlat = box(BG, BORDER, 1, 4, 8, 6)
	_dialog.border_width_top = 2
	_dialog.border_color = BORDER
	_dialog.shadow_color = Color(0, 0, 0, 0.5)
	_dialog.shadow_size = 6
	_t.set_stylebox(&"panel", &"DialogPanel", _dialog)
	_variation(_t, &"BarPanel", &"PanelContainer")
	_t.set_stylebox(&"panel", &"BarPanel", box(CARD, Color.TRANSPARENT, 0, 0, 6, 3))
	_t.set_stylebox(&"panel", &"TabContainer", StyleBoxEmpty.new())
	_t.set_stylebox(&"panel", &"ScrollContainer", StyleBoxEmpty.new())
	_t.set_stylebox(&"separator", &"HSeparator", _line(BORDER))
	_t.set_constant(&"separation", &"HSeparator", 6)
	_t.set_stylebox(&"panel", &"TooltipPanel", box(BG, BORDER, 1, 2, 4, 2))
	_t.set_color(&"font_color", &"TooltipLabel", TEXT)
	for _bar:StringName in [&"VScrollBar", &"HScrollBar"]:
		_t.set_stylebox(&"scroll", _bar, box(Color(FIELD, 0.6), Color.TRANSPARENT, 0, 2, 1, 1))
		_t.set_stylebox(&"grabber", _bar, box(BORDER, Color.TRANSPARENT, 0, 2, 1, 1))
		_t.set_stylebox(&"grabber_highlight", _bar, box(MUTED, Color.TRANSPARENT, 0, 2, 1, 1))
		_t.set_stylebox(&"grabber_pressed", _bar, box(AMBER, Color.TRANSPARENT, 0, 2, 1, 1))
	_t.set_constant(&"separation", &"VBoxContainer", 4)
	_t.set_constant(&"separation", &"HBoxContainer", 4)
	_theme = _t
	return _t

static func _variation(t:Theme, name:StringName, base:StringName)->void:
	t.set_type_variation(name, base)

static func _buttons(t:Theme, type:StringName, normal:StyleBox, hover:StyleBox, pressed:StyleBox, disabled:StyleBox,
		font:Color, font_hover:Color, font_disabled:Color, focus:StyleBox)->void:
	t.set_stylebox(&"normal", type, normal)
	t.set_stylebox(&"hover", type, hover)
	t.set_stylebox(&"pressed", type, pressed)
	t.set_stylebox(&"hover_pressed", type, pressed)
	t.set_stylebox(&"disabled", type, disabled)
	t.set_stylebox(&"focus", type, focus)
	t.set_color(&"font_color", type, font)
	t.set_color(&"font_hover_color", type, font_hover)
	t.set_color(&"font_focus_color", type, font)
	t.set_color(&"font_pressed_color", type, font_hover)
	t.set_color(&"font_hover_pressed_color", type, font_hover)
	t.set_color(&"font_disabled_color", type, font_disabled)

## A checkbox drawn in the palette: a light square, filled amber when ticked.
static func _check_icon(on:bool, enabled:bool)->ImageTexture:
	var _size:int = 8
	var _image:Image = Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	_image.fill(Color(FIELD, 1.0))
	var _color:Color = AMBER if on else MUTED
	if !enabled:
		_color = Color(_color, 0.4)
	for _i:int in _size:
		_image.set_pixel(_i, 0, _color)
		_image.set_pixel(_i, _size - 1, _color)
		_image.set_pixel(0, _i, _color)
		_image.set_pixel(_size - 1, _i, _color)
	if on:
		_image.fill_rect(Rect2i(2, 2, _size - 4, _size - 4), _color)
	return ImageTexture.create_from_image(_image)

static func _line(color:Color)->StyleBoxLine:
	var _l:StyleBoxLine = StyleBoxLine.new()
	_l.color = color
	_l.thickness = 1
	return _l

# ---------------------------------------------------------------- building blocks

static func label(text:String, variation:StringName = &"", wrap:bool = false)->Label:
	var _l:Label = Label.new()
	_l.text = text
	_l.theme_type_variation = variation
	if wrap:
		_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _l

static func button(text:String, callback:Callable, kind:StringName = &"")->Button:
	var _b:Button = Button.new()
	_b.text = text
	_b.theme_type_variation = kind
	_b.pressed.connect(callback)
	return _b

static func edit(text:String, placeholder:String)->LineEdit:
	var _edit:LineEdit = LineEdit.new()
	_edit.text = text
	_edit.placeholder_text = placeholder
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _edit

static func row(children:Array, separation:int = 4)->HBoxContainer:
	var _row:HBoxContainer = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", separation)
	for _child:Control in children:
		_row.add_child(_child)
	return _row

static func spacer()->Control:
	var _c:Control = Control.new()
	_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _c

## A card (raised panel) in `parent`; returns the box to fill. `title` as its heading.
static func card(parent:Node, title:String = "", subtitle:String = "")->VBoxContainer:
	var _panel:PanelContainer = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_panel)
	var _box:VBoxContainer = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 4)
	_panel.add_child(_box)
	if !title.is_empty():
		_box.add_child(label(title, &"HeadingLabel"))
	if !subtitle.is_empty():
		_box.add_child(label(subtitle, &"MutedLabel", true))
	return _box

## A small pill: "HOSTING", "ON", "YOU"...
static func chip(text:String, tone:int)->PanelContainer:
	var _panel:PanelContainer = PanelContainer.new()
	var _color:Color = tone_color(tone)
	_panel.add_theme_stylebox_override(&"panel", box(Color(_color, 0.16), Color(_color, 0.55), 1, 6, 4, 0))
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var _l:Label = label(text)
	_l.add_theme_color_override(&"font_color", _color)
	_l.add_theme_font_size_override(&"font_size", SMALL)
	_panel.add_child(_l)
	return _panel

## A coloured note with a bar on its left: warnings, failures, done.
static func banner(text:String, tone:int)->PanelContainer:
	var _panel:PanelContainer = PanelContainer.new()
	var _color:Color = tone_color(tone)
	var _box:StyleBoxFlat = box(Color(_color, 0.1), _color, 0, 2, 6, 3)
	_box.border_width_left = 2
	_panel.add_theme_stylebox_override(&"panel", _box)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var _l:Label = label(text, &"", true)
	_l.add_theme_color_override(&"font_color", _color.lerp(TEXT, 0.35))
	_panel.add_child(_l)
	return _panel

## A numbered step: a badge (amber when it's the one to do, green when done) and its title.
static func step(number:int, title:String, state:int)->HBoxContainer:
	var _color:Color = AMBER if state == Step.ACTIVE else (GREEN if state == Step.DONE else MUTED)
	var _badge:PanelContainer = PanelContainer.new()
	_badge.add_theme_stylebox_override(&"panel", box(_color if state != Step.TODO else Color.TRANSPARENT, _color, 1, 6, 3, 0))
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var _n:Label = label("ok" if state == Step.DONE else str(number))
	_n.add_theme_font_size_override(&"font_size", SMALL)
	_n.add_theme_color_override(&"font_color", INK if state != Step.TODO else MUTED)
	_badge.add_child(_n)
	var _title:Label = label(title, &"", true)
	if state == Step.TODO:
		_title.add_theme_color_override(&"font_color", MUTED)
	return row([_badge, _title], 5)

## A coloured dot (status lights).
static func dot(color:Color)->Control:
	var _d:PanelContainer = PanelContainer.new()
	_d.add_theme_stylebox_override(&"panel", box(color, Color.TRANSPARENT, 0, 3, 0, 0))
	_d.custom_minimum_size = Vector2(5, 5)
	_d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return _d

## A code or address you hand to someone: shown read-only with a Copy button.
## `copied` is called with the text after copying.
static func copy_row(text:String, copied:Callable)->HBoxContainer:
	var _field:LineEdit = edit(text, "")
	_field.editable = false
	_field.selecting_enabled = true
	_field.caret_blink = false
	var _copy:Button = button("Copy", func ()->void:
		DisplayServer.clipboard_set(text)
		copied.call(text), PRIMARY)
	return row([_field, _copy])

## A field you paste a code into, with Paste and the action.
static func paste_row(placeholder:String, action:String, callback:Callable)->HBoxContainer:
	var _field:LineEdit = edit("", placeholder)
	_field.text_submitted.connect(func (_t:String)->void: callback.call(_field.text))
	return row([_field,
		button("Paste", func ()->void: _field.text = DisplayServer.clipboard_get().strip_edges()),
		button(action, func ()->void: callback.call(_field.text), PRIMARY)])

## A label + control row with the label in a fixed column.
static func field(text:String, control:Control, width:float = 52.0)->HBoxContainer:
	var _l:Label = label(text, &"MutedLabel")
	_l.custom_minimum_size = Vector2(width, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row([_l, control])

## Free every child of `node` now (pages rebuild their controls).
static func clear(node:Node)->void:
	for _child:Node in node.get_children():
		node.remove_child(_child)
		_child.queue_free()
