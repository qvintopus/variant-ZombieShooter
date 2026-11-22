## One thing the map creator can do to a tile, an entity or a whole kind of them
## (add, remove, modify, select all, duplicate, move, replace). The radial menu and
## the topbar are built only from these, so a new operation is a new .tres.
class_name MapCatalogOperation
extends Resource

## Where the operation shows up in the radial menu's second ring.
enum Context {
	## The hovered tile/entity, or a group of selected ones.
	TARGET = 1,
	## A catalog item slice (things of that kind in the room / to add).
	CATALOG = 2,
}

## Handled by MapCreator: add, remove, remove_all, modify, select_all, duplicate, move, replace.
@export var id:StringName
@export var label:String
@export var icon:Texture2D
@export var color:Color = Color(0.8, 0.8, 0.8)
@export_flags("Target", "Catalog") var context:int = Context.TARGET
## Kinds (MapCatalogItem.Kind) it applies to; empty = every kind.
@export var kinds:Array[int] = []

func applies_to(kind:int, in_context:int)->bool:
	return (context & in_context) != 0 && (kinds.is_empty() || kinds.has(kind))
