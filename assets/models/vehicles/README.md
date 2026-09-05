# Codex Jeep

`codex_jeep.glb` contains only the `codex-vehicle-root` vehicle from the user's
`playground/claude-blender/claude-jeep.blend` scene. The other two vehicles and
the presentation floor, cameras and lights are excluded. The original `.blend`
is kept outside this repository and is never saved by the export script.

To regenerate with Blender (tested with 5.2.1):

```sh
blender --background --disable-autoexec /path/to/claude-jeep.blend \
  --python tools/blender/export_codex_jeep.py -- \
  assets/models/vehicles/codex_jeep.glb
```

The exporter evaluates the authored bevels, normals, curves and text, then joins
304 visual objects into one mesh with 12 material surfaces (200,688 triangles).
It keeps the source detail and lets Godot generate mesh LODs. No Blender runtime
is needed to import or play the checked-in GLB.

The model is centered horizontally, placed with its tire bottoms at Y=0,
scaled to 2.5 units long (approximately 1.75 wide and 1.68 tall), and faces Godot
-Z. Its wheels are static; adding wheel animation would require an export with
separate wheel assemblies and axle pivots.

`kart_controller.gd` instances it beneath `Chassis`. Per-instance material
overrides target `codex-sunburst-enamel` for player paint. Preserve that material
name when editing the source; the other eleven materials keep their authored
appearance. The original kart's collision shape and gameplay stay shared.
