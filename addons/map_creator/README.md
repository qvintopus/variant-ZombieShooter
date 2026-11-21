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
`MapCreatorHook` then loads `scenes/map_creator.tscn` and adds it to every room. The
scene is only loaded once the option is on. It does this for solo
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
| Tab | room browser |
| Delete / Ctrl+D / Esc | remove / duplicate the selection, cancel |

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

**Rooms**
- **Rooms** (or Tab) opens the browser. Its search (`RoomIndex`) matches every word
  against everything in a room: key, name, campaign, look, entities with their names and
  tags, enemy ids, boss names, door targets, flags. Hand-made room scenes are listed too.
  The info panel shows the selected room. Go switches to it.
- **Recent** lists the last 5 rooms visited.
- A switch goes through the scene transition with the entry tag `map_creator`, which no
  door has, so the player lands on the PlayerSpawner. The next room opens in Edit mode
  when this one was editing.
- Unsaved edits need a second switch to drop them. Switching is off in co-op.

Painting a floor look adds floor cells. Wall and hole painting writes overrides. Erasing a
hole brings back the room look's floor. With **Auto** on, every stroke is cleaned.
Saving writes into `res://`, so it only works when running from the project, not from an
export. Hotkeys, colors and UI size are in `resources/presets/default_preset.tres`.
`game/tests/map_creator_snapshot.tscn` saves a screenshot of the editor UI.

## Mods (workspaces)
- Mod = folder `user://mods/<id>/`: `mod.json` (name, author, version, description, campaigns) + `layouts/room_<key>.json`. Share by copying the folder (topbar workspace menu > Open mods folder).
- Mods hold JSON only, never .tres/.tscn (those can carry scripts). `LayoutCodec` checks items/props against the catalog, keeps strings to safe chars, bounds cells.
- `MapModState` (`resources/settings/mod_state.tres`): active mod; bakes its rooms into `user://map_creator/cache/<id>/` (rebakes on JSON/game version change); balance entries go to the `Balance` autoload (`register_rooms`).
- Baked doors/portals always link `res://game/scenes/room_<key>.tscn`; `Transition.change_scene` resolves through the mod state, so a mod room with a built-in key overrides it and new keys just work.
- Workspace menu (topbar): Game (project files, only when run from Godot) or a mod. Saving a built-in room in a mod copies it into the mod. In an exported game, Save on a built-in room asks for a new mod name.
- Runs remember their mod (`RunSave.mod_id`); Continue re-activates it.

## Room management (Rooms browser)
- New (12x12 floor + player spawn), Duplicate, Rename (rewrites every door/portal/waits_for link), Delete (press twice; in a mod drops only the mod copy), Import (hand-made scene -> layout: tiles, overrides, entries, block walls, spawns, triggers, catalog scenes, waves). `RoomManager`, `RoomImporter`.
- Ctrl+Shift+arrows shifts the whole room.

## Campaign graph (Map / M)
- `CampaignGraph` (GraphEdit): node per room of the campaign (layout `campaign`), row per door/portal with in/out ports. Drag out->in links (doors both ways), drag off unlinks. Add room, Start, Open (double click), Remove, Auto layout. Problems tint nodes.
- `CampaignStore`: campaigns `{id, display_name, start, nodes}` in mod.json (or `res://game/rooms/campaigns.json`).
- Title > Custom (`CustomCampaigns`): mod campaigns with a start room; activates the mod and loads the start. Offline only. Title deactivates mods.

## Painting tools (`MapTools`)
- Fill (F): same floor look, or an enclosed empty area (max `preset.fill_max`). Line brush (L). Pick (I / Alt+click) takes item + entity props.
- MirX / MirY mirror the brush across the floor's middle. Mix scatters item variants by `MapCatalogItem.weight`.
- Ctrl+C / Ctrl+V clipboard (kept across rooms). Stamps: save selection to `user://map_creator/stamps/<name>.json`; built-ins in `resources/stamps/`. Stamp JSON is checked like mod layouts.

## Waves (K)
- `WavesPanel` (left): sections (add/remove/reorder, Boss / Side flags, density, spawner cap), waves (count, alive cap, boss name, duplicate/reorder/remove), enemy rows from balance.json. Each change one undo step. Section title highlights + selects its spawns/triggers/barriers (`MapOverlay.section_color`).
- Test: saves, reloads the room (`settings.test_section`), puts the player on the section's trigger, starts the fight.

## Checks and comfort
- `MapChecks` after every edit / clean: baker rules, things under walls/holes, barrier/trigger gaps, links to missing rooms, reachability flood from player spawn + entries (unreachable doors/triggers/contraptions, spawns without a path). Topbar badge (O) opens `ProblemsPanel`; click jumps the camera.
- P: play from the cursor; F2 returns to the same view. F1 / ?: `HelpOverlay` from the preset keys.
- Autosave every `preset.autosave_seconds` while dirty (`user://map_creator/autosave/<workspace>/`); Ctrl+R restores; Save drops it.
- Saved rooms keep undo history across room switches (`settings.histories`). Layers menu hides floor / wall / hole tiles and entity markers.
