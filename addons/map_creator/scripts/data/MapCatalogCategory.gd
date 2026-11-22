## A topbar tab of the map creator (Terrain, Structure, Passages, Enemies...).
class_name MapCatalogCategory
extends Resource

@export var id:StringName
@export var display_name:String
@export var icon:Texture2D
@export var color:Color = Color.WHITE
@export var items:Array[MapCatalogItem] = []
## Operations of the items that don't list their own.
@export var operations:Array[MapCatalogOperation] = []
