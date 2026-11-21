## Something the map creator can put in a room: a floor look, wall, hole or an entity
## (gate, stairs, spawner, contraption...). The catalog .tres files are the only list of
## what exists; the topbar, radial menu, baker and live editor all read them, so a new
## asset (or a variant of one) is a new item resource, not code.
class_name MapCatalogItem
extends Resource

enum Kind { FLOOR, WALL, HOLE, ENTITY }

## How LayoutBaker writes an ENTITY into the room scene.
enum Bake {
	## Instance of scene_path (or a node_type node) under parent_path, props as exports.
	SCENE,
	## Stairs/door (SceneEntry): props tag, connect_tag, room.
	DOOR,
	## Portal: props tag, connect_tag, room, waits_for.
	PORTAL,
	## Boss room's victory exit (a portal to the victory screen).
	VICTORY,
	## BlockWall from the marker layer: props section (1-based); defaults.mode 1 = gate.
	BLOCK_WALL,
	## Enemy spawn point: props section, max_simultaneous (else the section's).
	SPAWN,
	## Boss spawn point of the boss section.
	BOSS_SPAWN,
	## Section trigger polygon: props section (1 = ArenaEntry...).
	TRIGGER,
	## Moves the room's PlayerSpawner.
	PLAYER_SPAWN,
	## Starting weapon pickup spot (start rooms).
	WEAPON_SPOT,
	## Home base piston memory grid corner: props grid_size.
	PISTON_GRID,
}

@export var id:StringName
@export var display_name:String
@export var icon:Texture2D
## Tint for the icon / fallback swatch and the editor overlay.
@export var color:Color = Color.WHITE
@export_multiline var description:String
@export var kind:Kind = Kind.ENTITY
## Extra search words (the room search matches these too).
@export var tags:PackedStringArray = []

@export_group("Tile")
## FLOOR: tileset source of the look (1 base, 10 mossy, ...).
@export var floor_source:int = 1
## FLOOR: atlas coord painted (0:3 plain, 1:3..3:3 cracked).
@export var floor_atlas:Vector2i = Vector2i(0, 3)

@export_group("Entity")
@export var bake:Bake = Bake.SCENE
@export_file("*.tscn") var scene_path:String
## Script of a plain node (SPAWN) or of a node_type node.
@export_file("*.gd") var script_path:String
## Node class when there is no scene (Marker2D...).
@export var node_type:String
## Parent in the room scene ("WallLayer_Ysorted", "Behind", ".", "EnemySpawnPoints").
@export var parent_path:String = "WallLayer_Ysorted"
## Fixed node name; empty = scene root name + running number.
@export var node_name:String
## Raw .tscn property values written after position (e.g. NodePaths).
@export var fixed_props:Dictionary = {}
## Props a newly placed entity starts with.
@export var defaults:Dictionary = {}
@export var properties:Array[MapPropertySpec] = []

@export_group("Catalog")
## Other looks of the same thing (future asset types); the topbar shows a picker.
@export var variants:Array[MapCatalogItem] = []
## How often Scatter painting picks this one among an item and its variants.
@export var weight:float = 1.0
## Operations of this item; empty = its category's.
@export var operations:Array[MapCatalogOperation] = []
## ASCII legend char(s) the old maps used, by props.section when several ("123").
@export var legend:String

## Legend char of an entity with these props (span checks and the text report).
func legend_char(props:Dictionary)->String:
	if legend.length() <= 1:
		return legend
	return legend[clampi(int(props.get("section", 1)) - 1, 0, legend.length() - 1)]

func property(key:StringName)->MapPropertySpec:
	for _spec:MapPropertySpec in properties:
		if _spec.key == key:
			return _spec
	return null
