shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform float water_level : hint_range(0.0, 1.0) = 1.0;
uniform vec3 water_color : source_color = vec3(0.2, 0.4, 1.0);

// este shader es muy simple: controla la transparencia según "water_level"
// luego podemos agregar ondas, normal maps, refracción, etc.

void fragment() {
    ALBEDO = water_color;
    ALPHA = water_level;
}
