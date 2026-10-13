// Port of "CC2D Armor" shader graph: three-colour recolouring through an RGB colour mask.
// rgb = 2 * lerp(lerp(lerp(0.5*tex, c1*tex, mask.r), c2*tex, mask.g), c3*tex, mask.b) * tint * vertex
shader_type canvas_item;
render_mode unshaded;
#include "res://addons/cc2d/cc2d_color.gdshaderinc"

uniform sampler2D color_mask : hint_default_black, filter_linear_mipmap;
uniform bool has_mask = false;
uniform vec4 color1 = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color2 = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color3 = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 tint = vec4(1.0);

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR; // includes modulate / self_modulate
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 tl = cc2d_to_linear(t.rgb);
	vec3 m = has_mask ? cc2d_to_linear(texture(color_mask, UV).rgb) : vec3(0.0);
	vec3 c = cc2d_to_linear(vec3(0.5)) * tl;
	c = mix(c, cc2d_to_linear(color1.rgb) * tl, m.r);
	c = mix(c, cc2d_to_linear(color2.rgb) * tl, m.g);
	c = mix(c, cc2d_to_linear(color3.rgb) * tl, m.b);
	c = 2.0 * c * cc2d_to_linear(tint.rgb) * cc2d_to_linear(vertex_color.rgb);
	COLOR = vec4(cc2d_to_srgb(c), t.a * tint.a * vertex_color.a);
}
