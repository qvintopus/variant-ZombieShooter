# Campaigns: New Game, New Game+, portals

The title's **New Game** starts `game/scenes/room_N00.tscn`. **New Game+** starts
`room_P00.tscn` and is only shown once it is unlocked. Every room is a layout resource
(`game/rooms/layouts/room_<key>.tres`, `RoomLayoutResource`) baked into its scene by
`GameLayoutBaker` (`game/resources/map_creator/layout_baker.tres`). The layout's
`campaign` field groups them:

| campaign | rooms | bosses |
|---|---|---|
| `new_game` | N00–N31 | Giant Zombie (N12), Broodmother (N23) |
| `new_game_plus` | P00–P32 | Big Jelly (P12), Plague Mother (P23), Giant Zombie (P32) |
| `boss_path` (from room_1) | C00–C31 | not a campaign (`writes_balance` off): no portals |
| `home` | H00 | see `home_base.md` |

```
N00 > N01 long hall > N02 hub ┬ west  N10 (side vault) > N11 gallery > N12 GIANT ZOMBIE
                              ├ east  N20 junction ┬ N21 strongroom (dead end)
                              │                    └ N22 > N23 BROODMOTHER
                              └ south N30 > N31 cistern (dead end)

P00 > P01 hub ┬ north P10 gullet > P11 (side vault) > P12 BIG JELLY
              ├ east  P20 junction ┬ P21 larder (dead end)
              │                    └ P22 spine > P23 PLAGUE MOTHER
              └ south P30 (side vault) > P31 long throat > P32 GIANT ZOMBIE
```

Each room has 1–3 sections. Dead-end rooms and side vaults are the fake paths. Long
corridors (N01, N11, P10, P22, P31) have spawn alcoves along the way.

## Side rooms
A side room is an alcove off the main path holding interactables:

- loot box
- meat grinder
- slime workbench
- slot machine

The layout marks it with `side_room = <section>`, which must be the room's last
section. That section is written without `requires`, and no gate waits for it, so its
guard fight is optional. The alcove is closed by a gate, a section 3 barrier and a
section 3 trigger.

To add a new interactable:
1. Put its scene in `scenes/interactables/`. Give it an `AstarShapeObstacle` pointing at its
   `StaticBody2D`, so enemies path around it rather than into it. The obstacle blocks every grid
   tile its body touches, and frees them while the node is disabled, as with the hidden
   workbench. `game/tests/obstacle_path_check` checks that the blocked tiles never cut off
   floor and that a zombie walks around each contraption.
2. Add a catalog item for it (`addons/map_creator/resources/catalog/items/`, listed in a
   category of `default_catalog.tres`): `scene_path`, `parent_path` `WallLayer_Ysorted`.
3. Place it in a side room of each campaign. `campaign_check` fails until every
   interactable scene appears in every campaign.

## Loot box
`scenes/interactables/loot_box.tscn` (`LootBox.gd`, extends `SlotMachine`) is free and
opens once. It pays out one weighted entry of `contraptions.loot_box.payouts` in
balance.json. It stays open for the run: `RoomStateResource.looted` remembers it until
the next campaign start.

## Portals
`scenes/obstacles/portal.tscn` (`game/scripts/Portal.gd`, extends `SceneEntry`) is shut
and hidden until the room in `open_when_cleared` is cleared, then appears as the open vortex.

- **Boss room:** a `portal` goes to the campaign hub. `victory` is the exit to
  `victory.tscn`. Both wait for the boss room itself.
- **Hub:** has one portal per boss room. Each waits for its boss room, so killing a boss
  opens a two-way shortcut for the rest of the run.
- **Labels:** a portal shows the `name` of the room it leads to, which the builder writes
  as `destination_name`. The victory exit (tag `victory`) reads EXTRACT instead and uses
  the green `portal_extract_32x32_strip6.png`.
- **Play Again:** the player walks through the victory exit like a door, so the transition
  still names `victory.tscn` when Play Again loads the start room. `FreshStart` only counts
  an arrival whose `next_scene_path` is its own room, so this starts a new run.

The baker checks that every boss fight is the room's last section, that every
campaign boss room has a portal and a victory exit, and that every portal arrives at a
portal of its target room.

## Run state and New Game+
- **Campaign start:** the start rooms (`start` on) get a `FreshStart`. A fresh start
  resets the run resources, including `RoomStateResource`, so cleared rooms, portals and
  loot boxes all start over. It also records itself as `CampaignResource.start_scene`.
  Try Again (game over) and Play Again (victory) use `CampaignRestartButton` to restart
  that campaign.
- **Starting weapon:** each `weapon_spot` entity in a start room becomes a `StartingWeaponSpawner`
  spot. It holds one random unlocked weapon, and the room's doors stay hidden until every
  spot is picked up, as in `room_start`. Walking back in through a door places nothing.
  The N00 and P00 start rooms have one each.
- **Unlocking New Game+:** walking through a boss room's victory exit opens the victory
  screen. That calls `CampaignResource.unlock_ng_plus()`, which is saved as
  `user://Campaign.tres` and loaded at boot by `PersistentData`. The title's
  `NewGamePlusEntry` shows New Game+ from then on.

## Editing a campaign
1. Edit the room in game with the map creator (Options > Gameplay > Admin tools, see
   `addons/map_creator/README.md`), which saves the layout and bakes the scene, or edit
   the layout `.tres` in the inspector (see the `RoomLayoutResource` doc comment).
2. Rebuild after inspector edits:
   `Godot --headless --path . res://game/tools/build_rooms.tscn [-- N02 P10]`.
   It rewrites the room scenes. For campaign rooms it also rewrites their maps.json
   `rooms` entries and leaves every other entry as it is.
3. Check: `Godot --headless --path . res://game/tests/campaign_check.tscn`.
