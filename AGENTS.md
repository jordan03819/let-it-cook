# Editing `.tscn` Files

- Read the complete scene before editing.
- Directly edit `.tscn` for simple nodes, properties, resources, paths, and signals.
- Use headless GDScript with Godot's resource APIs for bulk changes or complex resources.
- Treat inherited scenes conservatively; preserve their base scene and overrides.
- Preserve resource IDs and unrelated formatting.
- Keep node parent paths and resource references valid.
- When adding nodes through GDScript, set `owner` so they are saved.
- Never directly edit `.godot/`, generated import data, or binary `.res` files.
- Run a smoke check and check its output:


```bash
godot --headless --path . --editor --quit
```

- Run the affected scene or relevant tests when practical.

# Complex Scene Data

Do not directly edit complex editor-generated serialization such as animations, TileSets, navigation data, skeletons, or large nested resources.

Write a focused GDScript with Godot's resource APIs to load, modify, and save it.

# Visual Validation

After visual changes, capture the affected scene, and save them to a /tmp directory here. For example:

```bash
GODOT="godot.exe"
"$GODOT" --path "$(wslpath -w "$PWD")" --scene res://Scenes/example.tscn --write-movie "$(wslpath -w /tmp/example.png)" --quit-after 30
```

To prevent hanging on this or similar commands, it is recommended to set timeouts.

Inspect the screenshot and iterate on the visual properties as needed.
