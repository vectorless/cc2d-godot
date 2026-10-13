# packgen: AI-drawn custom part packs

Custom packs live in `res://custom/<pack>/` (`parts.json` + `textures/`), and are loaded at
runtime with `CC2DCharacter.add_part_pack("res://custom/<pack>/parts.json")`.
`tests/custom_preview.tscn` renders every custom part next to its template part.

Pipeline for one part (all scripts run with python3, numpy, Pillow, scipy):

1. **Template**: an existing CC2D part with the same guide layout (e.g. `Daily 09 Male` for a
   long-sleeved male top), composited on white and scaled 2x into a 2048x1152 (16:9) canvas.
2. **Generate**: `rep.py <model> <input.json> <out>` calls Replicate. The model is
   `google/nano-banana-pro` (best layout adherence in the bake-off; `openai/gpt-image-2` is
   the second choice). The prompt describes the sheet's pieces, the redesign, and "keep every
   piece where it is, same size/silhouette, bold black outlines, soft cel shading, white
   background".
3. **Fit**: `ccpack.py gen.png template.png regions.json out.png` crops the canvas, cuts each
   piece out of the white background and fits it onto the template piece's box (so joints line
   up), rebuilding anti-aliased alpha.
4. **Recolourable**: `recolor.py out.png tex.png mask.png` splits the colours into 3 clusters,
   writes CC2D's grey shading texture + RGB colour mask, and prints the 3 default colours.
5. **Register**: `add_part.py <pack dir> <Package> <Category> "<Part name>" tex.png "<template>" mask.png '<colors>'`.

The Replicate token is read from `~/.secrets/replicate` on the machine running the scripts.
Never commit it.
