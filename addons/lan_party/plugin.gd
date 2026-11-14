@tool
## LAN Party needs nothing from the editor at runtime: its classes are global (class_name) and the
## scripts in tools/ are plain files. Enabling the plugin only reminds you of the export setting the
## virtual LAN needs.
extends EditorPlugin

const EXPORT_FILTER:String = "addons/lan_party/tools/*, lan_party.cfg"

func _enable_plugin()->void:
	print("LAN Party: for exported games add \"%s\" to each export preset's Resources > Filters to export non-resource files." % EXPORT_FILTER)
