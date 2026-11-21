# Map Creator

In-game room editor on top of `addons/top_down`. Rooms are `RoomLayoutResource`s
(`game/rooms/layouts/room_<key>.tres`). A `LayoutBaker` bakes them into scenes that
inherit `room_template.tscn`. The game's baker (`GameLayoutBaker`,
`game/resources/map_creator/layout_baker.tres`) adds the project nodes and the
balance.json entries.

## Data (shared resources)
- `MapCatalog` (`resources/catalog/default_catalog.tres`) has categories, which hold `MapCatalogItem`s
  (`resources/catalog/items/*.tres`).
  - An item is a floor look, a wall, a hole or an entity. Entity fields:
    - `bake` kind;
    - `scene_path` or `node_type`;
    - `parent_path`;
    - `defaults`;
    - `properties` (`MapPropertySpec`);
    - `variants`.
  - `MapCatalogOperation`s (`resources/catalog/operations/*.tres`) are what the radial
    menu offers.
  - Adding an asset or a variant means adding an item `.tres` and listing it in a
    category (or in another item's `variants`). No code is needed.
- `RoomLayoutResource` holds the floor cells (source + atlas), wall/hole overrides,
  `LayoutEntity`s (item id, cell, props) and sections. See its doc comment.

## Baking
- `Godot --headless --path . res://game/tools/build_rooms.tscn [-- N02 P10]` bakes the layouts.
- `game/tests/layout_roundtrip_check.tscn` fails when a committed room scene doesn't match its layout.
