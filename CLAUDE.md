# CLAUDE.md: working on the CC2D Godot port

Read `README.md` first for what this is and its public API. This file covers what you need to
**change** it safely: the architecture, the data formats, conventions, how to verify, and the
traps.

## Ground rules

- **Private repo, licensed assets.** Never push anywhere public, upload textures or JSON to
  third-party services, or paste large chunks of CC2D source or art into chat.
- **Unity is the source of truth.** Behaviour should match CC2D in Unity. Before changing
  runtime logic, read the matching C# in `~/My project/Assets/CharacterCreator2D/Data/Scripts/`
  (`Character/CharacterViewer.cs`, `Utilities/Humanoid/HumanoidSetter.cs`,
  `HumanoidAssigner.cs`, `Character/SetupData.cs`, `Part/*.cs`) or
  `Creator UI/Scripts/UIExportPNG/UIExportPNG.cs`. Port it faithfully and name the Unity
  method in a comment, as the existing code does (e.g. `# HumanoidAssigner.AssignMuzzlePosition`).
- **`cc2d/` is generated.** Don't hand-edit `parts.json`, `rigs/*.json`, `animations/*.json`
  or `textures/`. Change `CC2DGodotExporter.cs` and re-export (see "Unity side" below).
- **Two copies of the exporter.** `~/My project/Assets/Editor/CC2DGodotExporter.cs` is the one
  Unity runs, and `unity/Editor/CC2DGodotExporter.cs` is the copy in this repo. Edit the Unity
  one, then copy it here before committing.
- **Commits:** `git -c user.name="pa" -c user.email="vectorless.space@gmail.com" commit`, with
  the Co-Authored-By / session trailer lines the harness asks for. Commit only when asked or at
  the end of a finished, tested task.

## Coordinates and units (used everywhere)

Godot px = Unity units × 100, **Y flipped**, **rotations negated** (radians). That's a mirror
about X applied to every local transform, so hierarchies stay consistent. The exporter's
`PosToGodot` / `RotToGodot` do this. Any position or vector you add to the export must go
through them, and directions need `(x, -y)`. Characters are about 1100 px tall at scale 1.

## Architecture

### Runtime: `addons/cc2d/cc2d_character.gd` (`CC2DCharacter`, Node2D, ~1400 lines)
Sections are marked `# ===...=== name`:

| Section | What it does |
|---|---|
| (top) `load_character()` | reads `character.json`, then `_rebuild()` |
| body type | `set_body_type()` → `_rebuild(anim, t)`: tears everything down and rebuilds from the other rig |
| animation | `play()`, `pose()`, lengths |
| equipment / colours | `equip_part`, `set_part_color`, skin / tint |
| aim layer | Aim-layer blend trees applied **by hand** on `AnimationPlayer.mixer_applied` (`_apply_aim`), with phase advanced in `_process` |
| body sliders | port of `BodySegmentScaler`; slider positions are applied in Unity's insertion order |
| character data | CC2D CharacterData JSON in and out (Unity-compatible field names; colours `{r,g,b,a}`) |
| expressions | `emote()`; animation-driven emotes follow the `emote_anim_index` keys read in `_process` |
| setter / assigner | ports of HumanoidSetter / HumanoidAssigner (parts → sprites, weapons, masks, colours) |
| building | `_build_materials/_nodes/_cloth/_segments/_animation_player`, `_build_library` |
| muzzle flashes | particle systems → `CPUParticles2D`, padded flash texture, restart logic |

Key mechanisms:
- **Rig:** one `Node2D` per Unity transform, stored in `parts[rig_path]`. Sprites are a
  `_sprite` child (`sprites[rig_path]`). Rig paths look like
  `Root/Pos_Hip/Bone_Hip/.../Bone_Weapon R/Muzzle R`.
- **Write-defaults emulation:** `_build_library` gives every animation a track for every
  (path, prop) any animation touches, holding the rest value where a clip doesn't animate it.
  Rotations are shifted into the rest pose's 2π turn so cross-fades don't spin.
- **Sprite swaps** (weapon slash FX) are method tracks calling `_anim_sprite(path, index)` into
  a per-file sprite table. `-2` restores the rig's own sprite.
- **Cape / skirt** are `Polygon2D`s whose vertices were baked per frame in Unity
  (`rig.cloth.<slot>.animations`). Their tracks are added in `_build_library`.
- **Emotes:** discrete keys can be skipped during a cross-fade, so the current
  `emote_anim_index` is computed each frame from the playing animation's keys, not from a track.
- **Muzzle flashes:** `Muzzle R/L` nodes are shown and hidden by the Shot clips' `visible`
  tracks. `_update_particles()` restarts the burst when one turns on or when the looping clip
  wraps. Unity's stretched billboard is anchored at the particle and extends along the velocity,
  so the texture is padded on one side (`_flash_texture`). `pose()` pre-simulates with
  `preprocess`.
- **`pose()`** freezes the character (`_posed` stops `_process`). `play()` / `play_aim()` unfreeze it.
- JSON is read through `_cached_json` (static cache). Textures load with `load(path)`.

### Exporter: `addons/cc2d/cc2d_exporter.gd` (`CC2DExporter`)
Builds a SubViewport → a camera at (0, −600 px) with zoom from the scale mode → a **copy** of
the character (`load_character(src.loaded_file)` + `apply_character_data(src.get_character_data())`)
→ a second SubViewport with an un-premultiply shader (`blend_premul_alpha`), giving straight
alpha → `get_image()` → resize down by `super_sampling`. Frame timing follows
`UIExportPNG.GetAnimationLength / SaveSequence`. All exports are coroutines (`await`).

### Plugin: `addons/cc2d/plugin.gd`
An EditorExportPlugin that `add_file()`s every `*.json` under `res://cc2d`, `res://characters`
and `res://addons/cc2d`. If you add JSON elsewhere, add the folder to `DATA_DIRS`.

### Creator: `creator/creator.gd`
All UI is built in code (`_build_ui`, `_build_export_ui`). The `_updating` flag stops
refreshes from feeding back into the character.

## Data formats (written by the Unity exporter)

- `characters/<id>/character.json`: `body_type`, `skin_color`, `tint_color`, `parts` (catalogue
  path), `rigs` {Male, Female → rig json}, `animations`, `default_animation`, `materials`,
  `slots` {slot: {material, part, package, color1..3}}, `emotes`.
- `cc2d/rigs/<body>.json`: `nodes` [{path, name, parent, pos, rot, scale, visible, sprite?,
  particles?}], `materials`, `cloth` {Cape, Skirt}, `segments` (body sliders).
- `cc2d/animations/cc2d.json`: `animations` {state: {length, loop, tracks [{path, prop, times,
  values}]}}. Props are `position:x/y`, `rotation`, `scale:x/y`, `visible`, `alpha`, `sprite`
  (index into `sprites`) and `emote_anim_index`. `layers["Aim Layer"].states` {state: {children
  [{threshold, anim}]}} is a 1D blend tree on the Aim parameter.
- `cc2d/parts.json`: `categories` {category: [{name, package, body, weapon?, muzzle?, texture,
  mask, sprites}]}, plus the link tables `links`, `weapon_links` {main, off, bow, shield},
  `colorable_links`, `weapon_fx_links`, `cape_link`, `skirt_link`, and default materials.
- Colours in exported JSON are `[r, g, b, a]` arrays. In CharacterData they're `{r, g, b, a}`.

## Verifying changes

**Always run the tests after a change** and look at the screenshots they write. Visual bugs
(orientation, layering, alpha) won't fail an assertion.

```sh
godot --path . --fixed-fps 60 res://tests/fx_test.tscn
godot --path . --fixed-fps 60 res://tests/creator_test.tscn
```

`--fixed-fps 60` keeps the timing-based checks deterministic. Add checks for new features to
an existing test (or a new `tests/*_test.tscn` that follows the same `check()` /
`== RESULT:` pattern), and write images to `tests/shots/`.

### Running Godot from a Claude cloud session
The Mac's Godot can't be launched from the Linux shell. What has worked:
1. Download the Linux arm64 build into the VM (not the project):
   `curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_linux.arm64.zip`.
2. **Work on a copy** so the Mac's `.godot/` cache isn't touched:
   `rsync -a --exclude .git --exclude .godot ./ ~/tmp/cc/`.
3. Import first, or global classes (`CC2DExporter`…) won't resolve:
   `godot --headless --import`.
4. Rendering tests need a display:
   `xvfb-run -a godot --rendering-driver opengl3 --fixed-fps 60 --path . res://tests/fx_test.tscn`.
5. Copy any new `*.uid` / `*.import` files the import generated back into the repo, and
   copy the shots back if the user should see them.
To check exported builds, add an export preset in the copy and run
`godot --headless --export-pack "Linux" build/x.pck`, then `godot --main-pack build/x.pck res://some_scene.tscn`
(no export templates are needed for a .pck).

To show the user something on their Mac, use computer use on **Godot-4.6.1**. Godot ignores
background clicks, so take full-screen control. Cmd+R runs the current scene, and the game
appears in the editor's **Game** tab.

### Unity side
Unity is reachable through the CoplayDev **MCP for Unity** tools (`unityMCP__*`) when the
Editor is open:
- after editing the exporter: `refresh_unity(compile="request")`, then check `read_console` for errors
- re-export: `execute_menu_item("Tools/CC2D/Export Shared Data (rigs, animations, parts) to Godot")`
- inspect prefabs, particle systems and clips with `execute_code`. It runs C# in the Editor
  (CodeDom, C# 6; `safety_checks` blocks deletes, so use `manage_asset` for those). Clean up any
  objects you instantiate.
- to get a reference image, instantiate the prefab, `SampleAnimation`, render a temporary
  orthographic Camera to a RenderTexture and save a PNG.

After re-exporting, check that `git diff --stat cc2d/` is limited to what you meant to change.

## GDScript traps already hit here

- `:=` fails when the right-hand side is a Variant (dictionary access, `get()`, untyped
  arrays). Use an explicit type (`var s: String = d.x`) instead.
- Lambdas containing `if` must be multi-line.
- Don't name variables `name`, `position`, etc. They shadow Node properties.
- Assigning an `int` to an enum-typed var needs `as EnumName`.
- Avoid `x == null` comparisons on Dictionaries / Arrays; use `is String` / sentinel strings.
- CPUParticles2D `preprocess` runs on the next update and is scaled by `speed_scale`, so
  don't zero either right after `restart()`.
- Drawing over a transparent viewport gives **premultiplied** colour; un-premultiply before saving PNGs.

## Not done / ideas
- Bake mode and the Atlas export preset. These need `Data/Animations/Export PNG/Export Atlas.controller`
  exported (`Atlas Male/Female.anim`); the cloth bake is tied to the clip list in `ExportShared`.
- The CC2DCharacter isn't `@tool`, so the editor viewport doesn't preview characters.
