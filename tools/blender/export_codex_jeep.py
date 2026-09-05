"""Export only the Codex vehicle, without saving changes to the source .blend.

blender --background --disable-autoexec SOURCE.blend --python \
    tools/blender/export_codex_jeep.py -- assets/models/vehicles/codex_jeep.glb
"""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector


output = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
root = bpy.data.objects["codex-vehicle-root"]
sources = sorted(
    (o for o in root.children_recursive if o.type in {"MESH", "CURVE", "FONT"}),
    key=lambda o: o.name,
)
if not sources:
    raise RuntimeError("The Codex vehicle root has no geometry")

# Evaluate bevels, weighted normals, lettering and tubes before joining. Keep the
# authored detail; consolidating 304 objects gives one mesh with 12 materials.
depsgraph = bpy.context.evaluated_depsgraph_get()
copies = []
points = []
for source in sources:
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    copy = bpy.data.objects.new("Export-" + source.name, mesh)
    bpy.context.scene.collection.objects.link(copy)
    copy.matrix_world = source.matrix_world.copy()
    copies.append(copy)
    points.extend(copy.matrix_world @ v.co for v in mesh.vertices)

low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
scale = 2.5 / (high.x - low.x)
# Blender +X is the nose. Rotate it to +Y so glTF's axis conversion makes the
# Godot model face -Z, with +Y up and the tire bottoms at ground level.
transform = (
    Matrix.Scale(scale, 4)
    @ Matrix.Rotation(math.pi / 2, 4, "Z")
    @ Matrix.Translation(-center)
)
for copy in copies:
    copy.matrix_world = transform @ copy.matrix_world

bpy.ops.object.select_all(action="DESELECT")
for copy in copies:
    copy.select_set(True)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.join()
vehicle = bpy.context.object
vehicle.name = "CodexJeep"
vehicle.data.name = "CodexJeep"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(output),
    export_format="GLB",
    use_selection=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
    export_yup=True,
)
print(f"Exported {len(sources)} source objects to {output}")
