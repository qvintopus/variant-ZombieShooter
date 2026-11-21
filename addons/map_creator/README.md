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

## In game
Options > Gameplay > **Admin tools: ON** (title or pause menu). The room template's
`MapCreatorHook` then adds `scenes/map_creator.tscn` to every room. It does this for solo
games and the co-op host, not for guests or a dedicated server. Edits are not synced.

| key | action |
|---|---|
| F2 | Edit / Play. Edit pauses the room and switches to a free camera (WASD/arrows, middle-drag, wheel zoom) |
| 1-9 | category tabs |
| Q / E | previous / next item (variants included) |
| B / X / V / G | Paint / Erase / Select / Move |
| C | Clean: autotile walls, holes and floor, then colliders, hole scenes and AStar (progress bar) |
| Ctrl+Z / Ctrl+Y | undo / redo (one step per stroke) |
| Ctrl+S | save the layout + bake the room scene (+ balance.json entry) |

Entities (stairs, portals, gates/barriers, spawners, triggers, contraptions, hazards,
markers) are placed with Paint and removed with Erase, one per floor cell. They are
built live through `LiveEntities` and drawn on the overlay with their legend letter.
Starting weapon spots, the piston grid and plain markers apply after Save and a reload.
The Select tool opens an entity in the **inspector**, which edits its `MapPropertySpec`
props. With nothing selected the inspector edits the room: name, look, flags,
side/boss section and the sections' waves as JSON.

**Selection**
- Ctrl+click toggles the top thing on a cell. The order is entity, painted wall, floor
  look, generated wall, hole.
- Ctrl+drag box-selects.
- A plain click lets go of the selection.
- Delete removes the selection. Ctrl+D duplicates it.
- With the Move tool, drag the selection.
- Esc cancels.
- A selection of one entity type is edited together in the inspector.

**Radial menu** (right click)
- Ring 1 holds:
  - the hovered thing, or each selected type plus "All selected";
  - every kind of thing in the room, plus the brush item;
  - More, which opens categories and then items.
- Hovering a slice opens its children on the next ring.
- The operations come from `MapCatalogOperation`s: Use as brush, Modify, Change to
  (a third ring of items), Duplicate, Move, Remove, Add here, Select all, Remove all.

Painting a floor look adds floor cells. Wall and hole painting writes overrides. Erasing a
hole brings back the room look's floor. With **Auto** on, every stroke is cleaned.
Saving writes into `res://`, so it only works when running from the project, not from an
export. Hotkeys, colors and UI size are in `resources/presets/default_preset.tres`.
`game/tests/map_creator_snapshot.tscn` saves a screenshot of the editor UI.
