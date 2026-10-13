# CC2D Godot Port (private)

Private port of the Character Creator 2D (Unity Asset Store) runtime to Godot 4.6.
Contains assets licensed under the Unity Asset Store EULA - do not publish this repo or redistribute its contents.

## What's here
- `addons/cc2d/` - the plugin: GDScript runtime (`CC2DCharacter`), PNG exporter (`CC2DExporter`,
  with CC2D's export presets), the CC2D recolour shaders, and an export plugin that puts the
  JSON data into exported games
- `creator/creator.tscn` - character creator (parts, colours, skin, body type, body sliders,
  expressions, animation + aim preview, save/load, PNG / sequence / sprite-sheet export)
- `demo/walk_demo.tscn` - walking demo (main scene)
- `characters/` - characters exported from Unity; `characters/examples/` has CharacterData files
  saved in Unity and in Godot (each loads in the other)
- `cc2d/rigs/` - Male / Female skeletons from CC2D's body prefabs, cape & skirt meshes with
  per-frame baked cloth motion, and body-slider data
- `cc2d/animations/` - CC2D animator states, the Aim layer, weapon-slash sprite swaps/fades,
  emote keys
- `cc2d/parts.json` + `cc2d/textures/` - the full part catalogue

Unity side: `Assets/Editor/CC2DGodotExporter.cs` in the Unity project
(Tools > CC2D > Export Selected Character / Export Shared Data); a copy is kept in `unity/Editor/`.

## Using it in another Godot project
Copy `addons/cc2d/`, `cc2d/` and your `characters/` into the project and enable
**Character Creator 2D** under Project Settings > Plugins. The plugin adds every `*.json` under
`res://cc2d`, `res://characters` and `res://addons/cc2d` to exported builds (Godot leaves
non-resource files out by default). Keep the export preset on "Export all resources" (the
default), since the textures are loaded by path from the JSON.

## CC2DCharacter API

```gdscript
# animation
character.play("Walk")                                  # any CC2D animation state, cross-faded
character.play_aim("Aim Bow"); character.set_aim(0.5)   # Aim layer on top (-1 down .. 1 up); "" stops
character.play_aim("Shot Bow")                          # Shot / Rapid Shot states
character.play_aim("Shot Main Hand")                    # guns: the muzzle flash fires on each shot
character.muzzle_flash("OffHand")                       # ...or fire one yourself
character.pose("Walk", 0.25, "Shot Rifle", 0.1)         # freeze on one frame (play() unfreezes)

# parts & colours
character.equip_part("Armor", "Fantasy 09 Male")        # "" unequips; body-type alternates as in CC2D
character.equip_part("OffHand", "Bow 01")               # two-handed rules as in CC2D
character.equip_part("Cape", "Fantasy 00")
character.cycle_part("Helmet", 1)
character.get_parts("MainHand")
character.set_part_color("Armor", c1, c2, c3)
character.set_part_color("Hair", Color.RED)             # hair/eyes/eyebrow/mouth/facial hair: one colour
character.set_skin_color(Color(1, 0.8, 0.7))
character.set_tint_color(Color.WHITE)
character.set_body_type("Female")

# body sliders (0..1, 0.5 = default)
character.set_body_slider("UpperLeg", Vector2(0.5, 0.9))   # Head Ear Neck Body UpperArm LowerArm Hand UpperLeg LowerLeg Foot

# facial expressions
character.emote("Hurt", 1.5)        # Blink / Attack / Hurt / Talk / Emote_0..Emote_9
character.reset_emote()
character.set_emote_part("Emote_0", "Mouth", "03")

# save / load - CC2D CharacterData JSON, same format as Unity's CharacterViewer.SaveToJSON/LoadFromJSON
character.save_character("user://hero.json")
character.load_character_data("user://hero.json")
var d := character.get_character_data(); character.apply_character_data(d)
```

Animations drive the face (Idle blinks, Talk moves the mouth, Hit/Die show Hurt, attacks show
Attack), the weapon slash effects and the gun muzzle flashes, as in Unity. Muzzle flashes are
CC2D's particle systems (burst, cone, lifetime, size, colour over life, additive stretched
billboards) as CPUParticles2D, positioned per weapon (`Weapon.muzzlePosition`).

## PNG export (CC2D's Export PNG screen)

```gdscript
var ex := CC2DExporter.new()
add_child(ex)
ex.apply_preset("fullbody")            # CC2D's presets: default, portrait, fullbody, animation
ex.load_config("user://my.pngconfig")  # or a Unity .pngconfig; save_config() writes one
ex.width = 512; ex.height = 512; ex.target_fps = 12
ex.char_position = Vector2(0, 0); ex.char_scale = 1.0   # Unity units, as in CC2D
ex.background = CC2DExporter.Background.TRANSPARENT; ex.flip = false; ex.loop_aim_layer = false

await ex.export_image(character, "user://hero.png")                             # as it is now
var files := await ex.export_sequence(character, "user://walk.png", "Walk")      # walk_000.png ...
var sheet := await ex.export_sheet(character, "user://shot.png", "Idle", "Shot Main Hand")  # + shot.json
var frames := await ex.render_frames(character, "Run")                           # Array[Image]
```

Framing, frame count and timing follow UIExportPNG: the same camera, Automatic / Actual Pixel
Size scale modes, 2x supersampling, base animation repeated until the aim state has played
once. The exporter renders a copy of the character in its own SubViewport, so the one on screen
isn't touched. PNGs are written with straight (not premultiplied) alpha. The sprite sheet is an
addition: the same frames in a grid, with a JSON file giving frame size, count and fps.

## Demo controls (walk_demo)
A/D or arrows walk, Shift runs. Tab / Shift+Tab chooses a slot, W/S cycles parts,
C randomises the slot's colours, X removes the part, R randomises the outfit,
B switches male/female, 1-4 Blink/Attack/Hurt/Talk, 0 resets the face,
T / H / K play Talk 1 / Hit / Attack, Z zooms onto the face.

## Tests
`tests/fx_test.tscn` (muzzle flashes, PNG export) and `tests/creator_test.tscn` (the creator's
export panel) print ok / FAIL lines and write images to `tests/shots/` (not committed):

    godot --path . --fixed-fps 60 res://tests/fx_test.tscn

## Not ported
- CC2D's "bake" mode (a character baked into one sprite atlas) and the Export PNG "Atlas"
  preset, which needs CC2D's separate Export Atlas animator
