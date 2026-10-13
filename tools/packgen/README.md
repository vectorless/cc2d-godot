# packgen: AI-drawn custom part packs

`packgen` makes new CC2D parts (clothes, hair, hats, shoes, held items) with an image model
and turns them into normal, recolourable CC2D parts in `res://custom/<pack>/`.
Packs are loaded at runtime with `CC2DCharacter.add_part_pack("res://custom/<pack>/parts.json")`;
the creator does this for every folder in `res://custom` (and again when its window gets focus).

Packs made so far (spec → pack folder): `flower_power` (1960s), `gangster` (1950s), `seventies`,
`underwear`, `scifi`, `nightclub`. `fetish` and `scifi_cosplay` were made by another session
with the same tool.

## Quick start

```bash
cd tools/packgen
python3 packgen.py list specs/*.json                       # what's done / pending
python3 packgen.py run specs/nightclub.json --only heels   # generate one part (resumable)
python3 packgen.py run specs/nightclub.json --redo heels   # throw away and regenerate
python3 packgen.py reconvert specs/nightclub.json          # redo cut-out/fit/colours from saved images (no image-model call)
python3 packgen.py reconvert specs/underwear.json --matte  # ...using the background-removal matte
python3 packgen.py prompts specs/*.json > PROMPTS.md       # the exact prompt for every part
```

Needs python3 with numpy, Pillow and scipy, and a Replicate API token in `~/.secrets/replicate`
on the machine running it (**never commit it**). Work files (raw generations, canvases, mattes)
go to `~/packgen_work/<Package>/<part id>/`, outside the repo. `--budget N` stops starting new
parts after N seconds (useful in sandboxes that kill long commands).

Then check the result on a character: `tests/custom_preview.tscn` renders every custom part next
to its template, or open the creator (main scene) and pick the pack in the parts list.

## Models, and why

| Step | Model (on Replicate) | Why |
|---|---|---|
| Redraw the part | `google/nano-banana-pro` (2K output) | Image *editing* model: it takes the template sheet as input and redraws it. In a side-by-side test on the same template against OpenAI gpt-image, FLUX and Seedream, it kept every piece in place and at the right size most reliably. That matters more than anything else here, because pieces that move no longer line up with the character's joints. It also holds a consistent bold-outline cartoon style, and 2K gives plenty of detail per piece. |
| Fallback | `openai/gpt-image-2` (set `"model"` on a part) | Second-best at layout. Use it when nano-banana refuses a prompt or keeps getting one part wrong. |
| Cut-out (optional) | `bria/remove-background` | Takes about a second per image and gives a clean, soft alpha matte. Flood-filling the white background (the default) fails on **white garments** (the fill leaks through gaps in the outline) and on **thin straps and loops** (white stays trapped between strap and body). Turn it on per part with `"matte": true`, per spec, or with `--matte`. The matte is cached as `gen_0_alpha.png`. |

`mesh.py` is an alternative client for Meshy's image-to-image API (`"model": "meshy/nano-banana-pro"`,
key in `~/.secrets/meshy`), with the same interface as `rep.py`.

## How templates are used

A CC2D part is not one picture. It's a texture holding separate **pieces** (torso, upper and lower
sleeves, collar; thigh and shin; shoe side and front views, boot shafts; hair front and back...),
each in a fixed rectangle with a pivot at the joint. The rig moves and rotates those pieces.
A freely drawn outfit can't be used, because its pieces wouldn't be where the rig expects them.

So every new part starts from an existing CC2D part with the right shape, its **template**
(set per part in the spec, e.g. `"template": "Daily 09 Male"`):

1. **Canvas**: the template's texture is put on white and scaled into a 2K canvas of a
   supported aspect ratio (`canvas.png`). This is the input image, so the model sees exactly
   which pieces exist, where they are and what silhouette they have.
2. **Prompt**: it names the pieces in the sheet (from the template's sprite list), asks for the
   new design, and insists on keeping every piece where it is (see below).
3. **Cut and fit** (`convert` in `packgen.py`, `piece_mask` in `ccpack.py`): for each sprite
   rectangle of the template, the drawn piece is cut out of the generated image (flood fill or
   matte) and fitted onto the template piece's bounding box with a per-piece rule, so that
   joints line up even when the model drew it a bit bigger, smaller or shifted:

   | Rule | Used for | Placement |
   |---|---|---|
   | `box` | torso, collar, hips, gloves, capes/skirts | fill the template's box (bounded stretch), top-aligned |
   | `length` | sleeves, legs, boot shafts | same length as the template piece, own width |
   | `foot` | shoes | same length, sole on the template's sole; a side view drawn mirrored is flipped back (toes point right) |
   | `head` | hair, hats | no bigger than ~1.4x the template, sitting on the same spot |
   | `width` | facial hair, weapons | same overall size, centred |
   | `width_bottom` | bras/bandeaus (`Base 00 Female`) | as wide as the template, band on its band |

   Override per part with `"fit": {"Armor Body": "box"}`, or for every part on a template in
   `TEMPLATE_FIT`. `"mode": "identity"` pastes pieces where they were drawn.
4. **Recolour** (`recolor.py`): the colours are split into 3 clusters, giving CC2D's grey
   shading texture plus an RGB colour mask, so the creator's 3 colour pickers work. The
   cluster colours become the part's default `"colors"`.
5. **Register**: the textures are copied to `custom/<pack>/textures/<Category>/` and the part
   is written to `custom/<pack>/parts.json` as a copy of the template's entry (same sprites,
   regions, pivots and body types) pointing at the new textures.

**Choosing a template.** Pick one whose pieces have the shape you want. The model follows the
silhouette closely:
- Sleeveless top → a template without sleeve pieces (`Daily 14/15 Female`). Long sleeves → `Daily 09`.
- No collar → a template whose `Armor Neck` is empty. A template with a high neckline gets you a turtleneck.
- Shoes → `Daily 00` (foot pieces only). Knee-high boots → `Fantasy 08`/`09`, whose shaft
  pieces reach the knee. `Fantasy 03` only has an ankle cuff, so a "knee-high" boot drawn on it
  is squeezed into the cuff.
- Bras and bikini tops → `Base 00 Female` (the underwear sheet).

## Prompts

Every prompt has three parts, assembled by `run_part` in `packgen.py`:

1. **Sheet description** (`describe`, using the `PIECE_WORDS` table), e.g.
   *"This image is a sprite sheet for a 2D cut-out game character: 6 separate pieces of one item
   on a white background - the torso, two forearm sleeves, a collar piece and two upper-arm sleeves."*
2. **The design**: *"Redraw it as "* + the part's `desc` from the spec.
3. **The rules** (`KEEP`): *"Keep every piece exactly where it is, at the same size, with the
   same silhouette and the same three-quarter angle, so it still fits the character's body. Same
   art style as the input: hand-drawn cartoon with bold black outlines and soft cel shading.
   Plain white background and nothing else: no body, no skin, no hands, no text, no labels, no logos."*

The full prompt for every part is in [PROMPTS.md](PROMPTS.md), and also in each part's
`done.json`. Tips learnt the hard way:
- Say what a piece is **not**. Image models draw a whole boot in each boot-shaft slot unless told
  "the boot shaft pieces are only the leg of the boot ... with no foot on them".
- Ask for plain fabric. Glitter, sequins and fine textures turn into speckle noise when the
  colours are split for recolouring.
- For revealing outfits, describe them as fashion items ("a fashionable nightclub ... top") and
  keep the "no body, no skin" rule. It also stops the model drawing a torso under the clothes.
- For halter necks, ask for only the front of the strap (it goes behind the neck).

## Spec format

```json
{"pack_dir": "custom/nightclub", "package": "Nightclub", "matte": false, "parts": [
  {"id": "heels", "category": "Boots", "name": "Strappy Heels", "template": "Daily 00",
   "desc": "fashionable nightclub strappy high-heeled sandals in gold",
   "matte": true, "fit": {}, "mode": "auto", "model": "google/nano-banana-pro"}]}
```
`id` names the work folder, `name` is what the creator shows (append ` Male`/` Female` for
body-specific clothes, like CC2D does). Only `id`, `category`, `name`, `template` and `desc` are required.

## Known limits

- Shoes sit on CC2D's flat foot, so high heels look like heels but the foot doesn't tilt.
- `Boots` has no thigh piece. Thigh-high boots end just over the knee. Going higher needs a
  matching `Pants` part (e.g. boot-coloured leggings).
- Each part is one image-model call (plus one matte call if enabled). Reconverting is free,
  so tweak fit rules first and regenerate only when the drawing itself is wrong.
