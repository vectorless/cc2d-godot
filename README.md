# CC2D for Godot (private)

A Godot 4.6 port of the **Character Creator 2D** runtime (Unity Asset Store). You build
characters in Unity, export them, and in Godot they look and behave the same: swappable parts,
recolouring, body types, animations, aiming, expressions, body sliders, muzzle flashes, and
PNG / sprite-sheet export. Character files are interchangeable with Unity's.

**Parts included (704):** Base, Emote and Fantasy (shipped with CC2D), plus the **Daily**,
**Post Apocalyptic** and **Undead** packs.

> **Licence:** this repo contains Character Creator 2D art and data covered by the Unity Asset
> Store EULA. Keep it private and do not redistribute it.

If you're Claude (or any coding agent), read [`CLAUDE.md`](CLAUDE.md) as well. It covers the
architecture, data formats and how to test changes.

---

## Quick start

1. Open this folder in **Godot 4.6** (Compatibility renderer).
2. Press **F5**. The character creator opens (it's the main scene).
3. Click **Walk Demo** in the creator to walk around with your character.

| Scene | What it is |
|---|---|
| `creator/creator.tscn` (main scene) | The character creator: parts, colours, body, sliders, expressions, animation and aim preview, save/load, PNG export |
| `demo/walk_demo.tscn` | A character you walk around while swapping parts with the keyboard |
| `tests/*_test.tscn` | Automated checks (see [Tests](#tests)) |

### Walk demo controls
A/D or the arrow keys walk, and Shift runs. Tab / Shift+Tab picks a slot, W/S cycles its parts,
C randomises its colours and X removes the part. R randomises the whole outfit and B switches
male/female. 1–4 show the Blink, Attack, Hurt and Talk faces, and 0 resets the face. T, H and K
play the Talk 1, Hit and Attack animations. Z zooms onto the face. Esc, or the Character Creator
button at the top right, goes back to the creator with the character.

### Character creator
A port of CC2D's Creator UI. Everything works with the mouse.

- **Top bar:** the File, Body, Face, Equipment, Weapon and Gun menus, plus **Randomize** and
  **Walk Demo** buttons.
- **Left:** the open menu's categories:
  - Equipment: Helmet, Armor, Pants, Skirt, Gloves, Boots and Cape.
  - Body: Body, Skin Details, Body Sliders and Randomize.
  - Face: Hair, Eyebrow, Eyes, Nose, Mouth, Ear, Facial Hair and Emotion.
  - Weapon: Main Hand, Off Hand, Two Handed, Shield and Bow.
  - Gun: Main Hand, Off Hand and Rifle.

  Next to them are the category's parts as thumbnails, grouped by pack. Click a pack's heading
  to fold it. There's a search box, a pack filter, and a dice button that picks a random part.
  **None** removes the part. Hover over a part to see its full name and pack. Thumbnails show
  the slot's current colours and are cached in `user://cc2d_thumbs/`.
- **Centre:** the character. Zoom with the mouse wheel or the slider (zooming in moves towards
  the face), drag to move the view, and double-click to reset it. Below the character are the
  **Base Layer** animation and the **Aim Layer** state. Use ◀ ▶, or click the name for the full
  list. While aiming, a slider sets the aim angle. The button at the bottom left changes the
  background.
- **Right (COLOR):** the selected part's colour slots. Hair, eyes, eyebrows, mouth, facial hair
  and skin details have one; other parts have three. Skin parts use the skin colour. Click a
  slot, then pick a colour with the picker, from one of CC2D's palettes (Skin, Hair, Eyes, Lips,
  Fabric, Leather, Metal and others) or from the recent colours. The panel also has random
  colours and copy / paste. Eyebrows and facial hair can take the hair colour, and the mouth can
  take the skin colour. Skin details have an opacity slider, and custom parts have a
  **Pack colours** button that restores their designed colours.
- **Body** has Male / Female and the body skin, with the skin and tint colours. **Body Sliders**
  sets the width and length of each body part. **Randomize** is CC2D's randomiser: choose which
  parts, colours and packs it uses, and whether it changes the body sliders.
- **Emotion** previews Blink, Attack, Hurt, Talk and the ten custom emotes. You can choose the
  face parts for each emote and name the custom ones. Named custom emotes are saved in the JSON.
- **Custom packs** in `res://custom/<pack>/parts.json` load at startup and have their own pack
  headings. If a custom part has designed colours, picking it applies them.
- **File:** New, Open JSON, Save As JSON, Export PNG and Walk Demo. The JSON files use CC2D's
  CharacterData format: Unity's `CharacterViewer.LoadFromJSON` reads them, and files saved by
  Unity load here.
- **Export PNG:** choose a preset (Default, Portrait, FullBody, Animation) or your own settings
  (size, fps, offset, scale, background, scale mode, flip, loop aim layer). Then export a single
  image, a PNG sequence or a sprite sheet. The export uses the animation and aim state that are
  playing under the character. **Render frame** previews the result. Presets can be loaded from
  and saved to `.pngconfig` files, including Unity's.

To see a gun fire, open Gun > Main Hand, pick a gun, and set the Aim Layer to `Shot Main Hand`.
**Walk Demo** takes the character into the walk demo, and the demo's **Character Creator**
button (or Esc) brings it back.

---

## Using CC2D characters in your own Godot game

1. Copy `addons/cc2d/`, `cc2d/` and `characters/` (or just the characters you need) into
   your project, keeping the same paths.
2. Enable the plugin under Project Settings > Plugins > **Character Creator 2D**. It puts
   the JSON data into exported builds, which Godot would otherwise leave out. Leave the export
   preset on "Export all resources" (the default), because textures are loaded by path from the JSON.
3. Add a character:

```gdscript
var hero := CC2DCharacter.new()
hero.character_file = "res://characters/exa/character.json"
hero.scale = Vector2(0.4, 0.4)      # the rig is 100 px per Unity unit, about 1100 px tall
add_child(hero)
hero.play("Walk")
```

Or add a node in the editor (Create Node > CC2DCharacter) and set **Character File**. It
builds itself when the game runs. The editor viewport doesn't show it.

### CC2DCharacter API

```gdscript
# animation
hero.play("Walk")                                   # any CC2D animation state, cross-faded
hero.get_animation_names()                          # Idle, Walk, Run, Jump, Attack Main Hand 1, ...
hero.play_aim("Aim Bow"); hero.set_aim(0.5)         # Aim layer on top (-1 down .. 1 up); "" stops it
hero.play_aim("Shot Main Hand")                     # Shot / Rapid Shot states; guns flash on each shot
hero.muzzle_flash("OffHand")                        # fire a muzzle flash yourself
hero.pose("Walk", 0.25, "Shot Rifle", 0.1)          # freeze on one frame (play() unfreezes)

# parts & colours
hero.equip_part("Armor", "Fantasy 09 Male")         # "" unequips; body-type variants handled as in CC2D
hero.equip_part("MainHand", "Gun 00", "Daily")      # names repeat across packs: pass the package to be sure
hero.get_equipped("MainHand"); hero.get_equipped_package("MainHand")   # "Gun 00", "Daily"
hero.equip_part("OffHand", "Bow 01")                # one-/two-handed rules as in CC2D
hero.cycle_part("Helmet", 1)
hero.get_parts("MainHand")                          # the catalogue for a slot
hero.set_part_color("Armor", c1, c2, c3)            # most parts take 3 colours
hero.set_part_color("Hair", Color.RED)              # hair / eyes / eyebrows / mouth / facial hair take 1
hero.set_skin_color(Color(1, 0.8, 0.7))
hero.set_tint_color(Color.WHITE)
hero.set_body_type("Female")                        # parts swap to the matching female versions

# body sliders: 0..1 per axis, 0.5 = default
hero.set_body_slider("UpperLeg", Vector2(0.5, 0.9)) # Head Ear Neck Body UpperArm LowerArm Hand UpperLeg LowerLeg Foot

# expressions
hero.emote("Hurt", 1.5)                             # Blink / Attack / Hurt / Talk / Emote_0..Emote_9
hero.reset_emote()
hero.set_emote_part("Emote_0", "Mouth", "03")

# save / load: CC2D CharacterData JSON (same format as Unity's CharacterViewer)
hero.save_character("user://hero.json")
hero.load_character_data("user://hero.json")
var d := hero.get_character_data(); hero.apply_character_data(d)
```

Slots: `Armor Boots Ear Eyebrow Eyes FacialHair Gloves Hair Helmet MainHand Mouth Nose OffHand
Pants SkinDetails BodySkin Cape Skirt`. Signals: `character_loaded`, `part_equipped(slot, part)`,
`body_type_changed(body_type)`, `emote_changed(emotion)`.

Animations drive the face as they do in Unity: Idle blinks, Talk moves the mouth, Hit and Die
show Hurt, and attacks show Attack. They also drive the weapon slash effects and the gun muzzle
flashes.

### PNG export: CC2DExporter

This is a port of CC2D's Export PNG screen. It uses the same settings, framing and presets,
reads Unity's `.pngconfig` files, and adds sprite sheets.

```gdscript
var ex := CC2DExporter.new()
add_child(ex)
ex.apply_preset("fullbody")            # default | portrait | fullbody | animation
ex.load_config("user://my.pngconfig")  # a Unity .pngconfig works; save_config() writes one
ex.width = 512; ex.height = 512; ex.target_fps = 12
ex.char_position = Vector2(0, 0); ex.char_scale = 1.0     # in Unity units, as in CC2D
ex.background = CC2DExporter.Background.TRANSPARENT       # or BLACK WHITE GRAY MAGENTA GREEN
ex.scale_mode = CC2DExporter.ScaleMode.AUTOMATIC          # or ACTUAL_PIXEL_SIZE
ex.flip = false; ex.loop_aim_layer = false

await ex.export_image(hero, "user://hero.png")                                 # the frame showing now
var files := await ex.export_sequence(hero, "user://walk.png", "Walk")         # walk_000.png, walk_001.png, ...
var sheet := await ex.export_sheet(hero, "user://shot.png", "Idle", "Shot Main Hand")  # + shot.json
var frames := await ex.render_frames(hero, "Run")                              # Array[Image], nothing saved
```

The exporter renders a copy of the character off-screen, so the one in your scene isn't
touched. PNGs are written with straight alpha. The sheet's JSON gives the frame size, columns,
rows, frame count and fps.

---

## Getting new characters and data out of Unity

The Unity project is `~/My project` (Unity 6000.6, CC2D in `Assets/CharacterCreator2D`). The
exporter is `Assets/Editor/CC2DGodotExporter.cs`, and a copy is kept in `unity/Editor/` in this
repo. **If you change one copy, update the other.** It writes straight into
`/Users/pa/Games/cc2d-godot`, which is the `DefaultGodotProject` constant in the script.

- **One character:** select a CC2D character (prefab or scene object) and choose
  *Tools > CC2D > Export Selected Character to Godot*. This writes
  `characters/<name>/character.json`.
- **Everything shared** (rigs, animations, part catalogue, textures): choose
  *Tools > CC2D > Export Shared Data (rigs, animations, parts) to Godot*. Re-run this after
  adding part packs or changing the exporter.

### Adding a CC2D part pack
1. Import the pack into the Unity project.
2. In Unity, choose *Window > Character Creator 2D > Refresh Parts and Add-Ons*. Until you do,
   CC2D's part list (and so the export) doesn't include the new parts.
3. Choose *Tools > CC2D > Export Shared Data … to Godot*.
4. Open the Godot project so it imports the new textures, then run `tests/packs_test.tscn`.
   It equips every part on both bodies and compares outfits with Unity's renders. The Unity
   renders come from `unity/snippets/render_pack_outfits.cs`, run through MCP for Unity.

To move a character without re-exporting, save it in Unity (`CharacterViewer.SaveToJSON`) and
load it here with `load_character_data()`, or the other way round.

---

## Tests

The tests print `ok` / `FAIL` lines and end with `== RESULT: PASS` or `FAIL`. They write
images to `tests/shots/`, which isn't committed.

```sh
godot --path . --fixed-fps 60 res://tests/fx_test.tscn       # muzzle flashes + PNG export
godot --path . --fixed-fps 60 res://tests/creator_test.tscn  # the creator's export panel
godot --path . --fixed-fps 60 res://tests/creator_ui_test.tscn  # clicks through the creator, screenshots in tests/shots/creator_ui/
godot --path . --fixed-fps 60 res://tests/packs_test.tscn    # every part + pack outfits vs Unity
```

On a Mac, `godot` is `/Applications/Godot-4.6.1.app/Contents/MacOS/Godot` (adjust the path to
where yours is installed).

## Layout

```
addons/cc2d/              the plugin
  cc2d_character.gd         CC2DCharacter: the runtime (port of CharacterViewer + HumanoidSetter/Assigner)
  cc2d_exporter.gd          CC2DExporter: PNG / sequence / sprite sheet (port of UIExportPNG)
  cc2d_armor.gdshader       CC2D's 3-colour recolour shader (parts with a colour mask)
  cc2d_skin.gdshader        skin colour + skin details
  cc2d_color.gdshaderinc    shared colour maths
  export_presets/           CC2D's Export PNG presets (Unity ExportConfig JSON)
  plugin.cfg, plugin.gd     editor plugin: adds the JSON data to exported games
cc2d/                     shared data exported from Unity (don't hand-edit; re-export instead)
  parts.json                part catalogue + CC2D's link tables
  rigs/male.json, female.json   skeletons, sprites, cloth meshes + baked motion, body-slider data, muzzle particles
  animations/cc2d.json      every animator state, the Aim layer blend trees, sprite swaps, emote keys
  textures/                 all part / body / FX textures
characters/               exported characters (character.json) and CharacterData examples
  packs/                    one test outfit per pack and body (CharacterData saved in Unity)
creator/                  the character creator scene (UI built in creator.gd)
  icons/, backgrounds/      CC2D Creator UI icons and backgrounds
  palettes.json             CC2D's colour palettes (from Data/Color Palettes)
demo/                     the walk demo
tests/                    test scenes
unity/Editor/             copy of the Unity exporter script
```

## Not ported

- CC2D's **bake** mode (baking a character into one sprite atlas) and the Export PNG
  **Atlas** preset. The preset depends on CC2D's separate Export Atlas animations.
