class_name SpawnWaveList
extends Resource

@export var is_boss:bool

## Name shown on the boss wave banner (boss waves only).
@export var display_name:String

@export var count:int

## Enemies of this wave kept alive at once (spawners keep spawning to hold it, past
## the section's density), 0 = each spawner keeps its density slots.
@export var max_alive:int

@export var instance_list:Array[InstanceResource]
