// Port of "CC2D Skin" shader graph: skin/face parts tinted by the sprite colour,
// with an optional details overlay (tattoos etc.).
// base = 2*tex ; rgb = lerp(base, base*details*details_color, details.a*details_color.a) * tint * vertex
shader_type canvas_item;
render_mode unshaded;
#include "res://addons/cc2d/cc2d_color.gdshaderinc"

uniform sampler2D details : hint_default_transparent, filter_linear_mipmap;
uniform bool has_details = false;
uniform vec4 details_color = vec4(1.0);
uniform vec4 tint = vec4(1.0);

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 base = 2.0 * cc2d_to_linear(t.rgb);
	vec3 c = base;
	if (has_details) {
		vec4 d = texture(details, UV);
		vec3 dl = cc2d_to_linear(d.rgb) * cc2d_to_linear(details_color.rgb);
		c = mix(base, base * dl, d.a * details_color.a);
	}
	c = c * cc2d_to_linear(tint.rgb) * cc2d_to_linear(vertex_color.rgb);
	COLOR = vec4(cc2d_to_srgb(c), t.a * vertex_color.a);
}
