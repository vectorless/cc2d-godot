# CC2D Godot Port (private)

Private port of the Character Creator 2D (Unity Asset Store) runtime to Godot 4.6.
Contains assets licensed under the Unity Asset Store EULA - do not publish this repo or redistribute its contents.

## What's here
- `addons/cc2d/` - GDScript runtime (`CC2DCharacter`) and the CC2D recolour shaders
- `creator/creator.tscn` - character creator (parts, colours, skin, body type, body sliders,
  expressions, animation + aim preview, save/load)
- `demo/walk_demo.tscn` - walking demo (main scene)
- `characters/` - characters exported from Unity; `characters/examples/` has CharacterData files
  saved in Unity and in Godot (each loads in the other)
- `cc2d/rigs/` - Male / Female skeletons from CC2D's body prefabs, cape & skirt meshes with
  per-frame baked cloth motion, and body-slider data
- `cc2d/animations/` - CC2D animator states, the Aim layer, weapon-slash sprite swaps/fades,
  emote keys
- `cc2d/parts.json` + `cc2d/textures/` - the full part catalogue

Unity side: `Assets/Editor/CC2DGodotExporter.cs` in the Unity project
(Tools > CC2D > Export Selected Character / Export Shared Data).

## CC2DCharacter API

```gdscript
# animation
character.play("Walk")                                  # any CC2D animation state, cross-faded
character.play_aim("Aim Bow"); character.set_aim(0.5)   # Aim layer on top (-1 down .. 1 up); "" stops
character.play_aim("Shot Bow")                          # Shot / Rapid Shot states

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
Attack) and the weapon slash effects, as in Unity.

## Demo controls (walk_demo)
A/D or arrows walk, Shift runs. Tab / Shift+Tab chooses a slot, W/S cycles parts,
C randomises the slot's colours, X removes the part, R randomises the outfit,
B switches male/female, 1-4 Blink/Attack/Hurt/Talk, 0 resets the face,
T / H / K play Talk 1 / Hit / Attack, Z zooms onto the face.

## Not ported
- Weapon muzzle-flash particle systems (guns) - the nodes exist but have no particles
- CC2D's "bake" (single-atlas) mode and PNG export screen
- Exported builds: JSON data is read with FileAccess; check the export preset includes `*.json`
