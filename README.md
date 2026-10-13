# CC2D Godot Port (private)

Private port of the Character Creator 2D (Unity Asset Store) runtime to Godot 4.6.
Contains assets licensed under the Unity Asset Store EULA - do not publish this repo or redistribute its contents.

- `characters/` - characters exported from Unity (Tools > CC2D > Export Selected Character to Godot)
- `cc2d/rigs/` - Male / Female skeletons from CC2D's body prefabs, with cape & skirt meshes
  whose motion is baked per animation frame (CC2D's cloth bones use 3D rotations)
- `cc2d/animations/` - CC2D animator states (only animated values; rest pose filled in per rig)
- `cc2d/parts.json` + `cc2d/textures/` - the full part catalogue
  (Tools > CC2D > Export Shared Data refreshes rigs, animations and parts)
- `addons/cc2d/` - GDScript runtime (`CC2DCharacter`) and recolour shaders
- `demo/` - walking + outfit demo

## CC2DCharacter API

```gdscript
character.play("Walk")                                  # any CC2D animation state
character.equip_part("Armor", "Fantasy 09 Male")        # "" unequips
character.equip_part("OffHand", "Bow 01")               # two-handed rules as in CC2D
character.cycle_part("Helmet", 1)                       # next / previous part
character.get_parts("MainHand")                         # parts for this body type
character.set_part_color("Armor", c1, c2, c3)
character.set_part_color("Hair", Color.RED)             # hair/eyes/eyebrow/mouth/facial hair use one colour
character.set_skin_color(Color(1, 0.8, 0.7))
character.set_tint_color(Color.WHITE)
character.set_body_type("Female")                       # parts swap to female versions
character.equip_part("Cape", "Fantasy 00")
character.equip_part("Skirt", "Base 01")
```

Slots: Armor, Boots, Ear, Eyebrow, Eyes, FacialHair, Gloves, Hair, Helmet, Mouth, Nose,
Pants, SkinDetails, MainHand, OffHand, Cape, Skirt, BodySkin

## Demo controls
A/D or arrows walk, Shift runs. Tab / Shift+Tab chooses a slot, W/S cycles parts,
C randomises the slot's colours, X removes the part, R randomises the whole outfit,
B switches between male and female.
