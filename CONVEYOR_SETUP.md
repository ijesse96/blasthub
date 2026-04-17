# Conveyor Setup

## Required Workspace setup

- Create one or more `Model`s in `Workspace` named like `Conveyor`, `Conveyor2`, `Conveyor_A`, etc.
- Inside each conveyor model, add:
  - `Start` (`Part`)
  - `End` (`Part`)
- Place `Start` where items should spawn and `End` where items should despawn.

## Random item source

- Put toolbox models/parts in `ServerStorage > ConveyorItems`.
- The conveyor system randomly clones from that folder.
- If no items exist there, the system spawns fallback crates.

## Script location

- Runtime script: `src/server/ConveyorSystem.server.luau`
- Rojo mapping for templates is configured in `default.project.json`:
  - `ServerStorage.ConveyorItems -> src/serverstorage/ConveyorItems`

## Tuning values

In `ConveyorSystem.server.luau`:

- `SPAWN_INTERVAL`: base seconds between spawns
- `SPAWN_JITTER`: randomness in spawn timing
- `CONVEYOR_SPEED`: movement speed
- `MAX_ACTIVE_ITEMS_PER_CONVEYOR`: hard cap per conveyor
- `ITEM_SPACING`: min distance from start before spawning next
