# Arena target spawn setup

Targets spawn from outside the **BulletArenaBoundaries** axis-aligned bounds, cross the arena on straight paths (four cardinals + two diagonals), and despawn past the far side. Legacy `Conveyor` models with `Start`/`End` parts are **no longer used**.

## Required Workspace setup

- **`Workspace.BulletArenaBoundaries`** (folder): include `BasePart`s whose combined world XZ bounding box defines the play rectangle. Walls around the arena work; the script unions every descendant part’s oriented bounding box into one AABB.
- **Target height**: travel plane Y uses **`Workspace.Baseplate` top surface** + `Y_OFFSET` when a `Baseplate` part exists (so targets sit on the floor, not mid-wall). If there is no Baseplate, the script uses the **lowest world Y** among all boundary part corners + `Y_OFFSET`.
- **Edges** (fixed in code): Left = min X, Right = max X, Top = max Z, Bottom = min Z. Swap Top/Bottom in script comments/constants if your camera feels inverted.

## Studio cleanup (optional visuals)

- Remove or hide old conveyor lane meshes and any `Conveyor*` models that only existed for `Start`/`End` routing.
- Ensure boundary parts wrap the **playable floor** you want—if spawns sit too far in/out, resize or add invisible rim parts so the AABB matches the intended arena.

## Random item source

- Put toolbox models/parts in `ServerStorage > ConveyorItems`.
- The server randomly clones from that folder.
- If no items exist there, the system spawns fallback crates.

## Script location

- Runtime script: `src/server/ConveyorSystem.server.luau`
- Rojo mapping for templates: `default.project.json` → `ServerStorage.ConveyorItems -> src/serverstorage/ConveyorItems`

## Tuning values

In `ConveyorSystem.server.luau`:

- `SPAWN_MARGIN`: studs outside the AABB where spawns originate
- `SPAWN_INTERVAL`: base seconds between spawn attempts
- `CONVEYOR_SPEED`: travel speed
- `MAX_ACTIVE_ITEMS` / `TARGET_ACTIVE_ITEMS`: global caps
- `ITEM_SPACING`: minimum horizontal separation vs other active targets (scaled by model spawn scale)
- `PATH_WEIGHTS`: relative weights for L→R, R→L, Top→Bottom, Bottom→Top, TL→BR, BL→TR

## Per-template spawn size

After spawn, every conveyor template is scaled so its largest bounding-box axis matches `TARGET_ITEM_MAX_AXIS_STUDS` (default 40 studs). To make **one** model smaller or larger than that baseline, add a **Number** attribute on the template’s root **Model** (in Studio, then save your `.rbxm` under `ServerStorage.ConveyorItems`):

- **`ConveyorSpawnRelativeSize`**: multiplier applied after the baseline scale (default behavior = omit attribute, or any invalid value). Use values between roughly **0.25** and **0.6** for a noticeably smaller prop (e.g. shark fin); values above **1** grow the model up to the same hard cap as other items. Internally the server clamps this attribute to **0.01–3** and re-applies arena bounds clamping.
- **Shark fin default**: a root model named exactly **`shark fin`** (matches `shark fin.rbxm` from Rojo) gets relative size **0.45** when this attribute is missing, so you do not need to open the binary model in Studio. Set **`ConveyorSpawnRelativeSize`** on the model to override that default.
